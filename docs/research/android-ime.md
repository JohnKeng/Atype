# Android 端語音輸入（Voice IME）技術研究報告

研究日期：2026-10-01。目標：為自製 Typeless 類產品（按鍵/按鈕 → 說話 → 乾淨文字插入任何 App）的 Android 端提供可執行方案。本報告以 2025–2026 的官方文件與開源專案原始碼為主要依據；本次環境無法直接讀取 `support.google.com`、`developers.google.com`、`k2-fsa.github.io`、`alphacephei.com`、`onnxruntime.ai`（被 proxy 阻擋），對應段落已明確標示「未能直接驗證」。

---

## 1. 執行摘要（Executive Summary）

1. **Android 唯一能「把文字塞進任何 App 游標位置」的正規管道是 IME（`InputMethodService`）＋ `InputConnection`。** 無障礙服務（`AccessibilityService`）與浮窗貼上是次要/備援方案，各有明顯政策與可靠度風險。
2. **正確產品型態是「voice-only 的輔助 IME」**：在 `method.xml` 宣告 `android:imeSubtypeMode="voice"` 且 `android:isAuxiliary="true"`，讓 HeliBoard/FlorisBoard/AnySoftKeyboard/SwiftKey 等鍵盤的「麥克風鍵」能一鍵切到我們，講完後呼叫 `switchToPreviousInputMethod()`（API 28+）自動切回原鍵盤。這是 FUTO Voice Input、Sayboard、Transcribro、VoxWrite 等專案的共同作法。**但 Gboard 與 Samsung Keyboard 的麥克風鍵是寫死（hardcoded）導向 Google/Samsung 自家語音服務，無法把 handoff 給第三方**（FUTO README 明示），對台灣主流的「Gboard 注音」使用者，必須提供「用地球鍵/輸入法切換器切到我們、講完自動切回」或「我們自己也提供注音鍵盤」兩種補償路徑。
3. **麥克風權限**：`RECORD_AUDIO` 是 runtime permission，Service 不能自己彈出授權框，必須由一個透明/設定 Activity 代為請求（FUTO 與 Sayboard 皆如此）。**IME 視窗顯示中時系統以 `BIND_TREAT_LIKE_ACTIVITY | BIND_FOREGROUND_SERVICE` 綁定 IME 程序**（AOSP `InputMethodBindingController.IME_VISIBLE_BIND_FLAGS`），實務上 FUTO 直接在 IME 內用 `AudioRecord` 錄音、**不啟動 foreground service**。只有「鍵盤收起後仍要持續錄音」或「作為 `RecognitionService` 供他人呼叫」才需要 `foregroundServiceType="microphone"` 的 FGS，且 Android 14+ 不得從背景/`BOOT_COMPLETED` 啟動 microphone FGS。
4. **IME 必須是原生 Kotlin/Java**：Flutter/RN/KMP 都無法「宣告」一個 IME；少數專案把 `FlutterView` 塞進 `InputMethodService` 視窗，但那仍是原生 Service 殼。Jetpack Compose 可用，需自己實作 `LifecycleOwner / ViewModelStoreOwner / SavedStateRegistryOwner` 並 `setViewTree*Owner` 到 decor view（FlorisBoard `LifecycleInputMethodService`、FUTO `setOwners()` 範式）。
5. **on-device STT 選型（中文）**：`sherpa-onnx`（Apache-2.0）是目前中文最務實的選擇：SenseVoice int8 約 228 MB（zh/yue/en/ja/ko，RK3588 A76 單執行緒 RTF 0.099）、Paraformer-zh-small int8 79 MB、streaming Zipformer bilingual zh-en small int8 約 47 MB。whisper.cpp 在手機上只建議 tiny/base（75/142 MiB，記憶體 ~273/388 MB），中文品質偏弱；Vosk 中文小模型約 42–50 MB、串流零延遲但準確度較低。Google `SpeechRecognizer.createOnDeviceSpeechRecognizer()`（API 31）免費但依賴 Google 服務且不保證離線中文。Gemini Nano（ML Kit GenAI，minSdk 26、`genai-prompt` 1.0.0-beta4）適合**事後潤稿**而非 STT，且裝置覆蓋率有限。
6. **建議架構**：Kotlin 原生 IME（Compose UI）＋ 本機 VAD（WebRTC/Silero）＋ sherpa-onnx SenseVoice/Zipformer 本地辨識 ＋ 可選雲端 LLM 潤稿（透過 `commitText` 一次提交）＋ 設定/權限 Activity ＋ Quick Settings Tile 作為第二入口。Play 上架需：Data safety 表格宣告 `RECORD_AUDIO`、Prominent disclosure、targetSdk 36（2026-08-31 起）、原生 .so 支援 16 KB page size（2027-02-01 起強制）。

---

## 2. IME 基礎：`InputMethodService` 與宣告

### 2.1 Manifest 與 `method.xml`

官方指南（[creating-input-method](https://developer.android.com/develop/ui/views/touch-and-input/creating-input-method)）要求：Service 需 `android.permission.BIND_INPUT_METHOD`、intent-filter `android.view.InputMethod`、`meta-data android.view.im` 指向 subtype XML。IME 可以看到所有輸入的文字（含密碼欄），官方要求密碼欄不得送網路、不得儲存。

Sayboard 的宣告（[AndroidManifest.xml](https://github.com/ElishaAz/Sayboard/blob/master/app/src/main/AndroidManifest.xml)、[method.xml](https://github.com/ElishaAz/Sayboard/blob/master/app/src/main/res/xml/method.xml)）與 FUTO 的 [input_method.xml](https://github.com/futo-org/voice-input/blob/master/app/src/main/res/xml/input_method.xml) 是 voice-only IME 的範本：

```xml
<!-- res/xml/method.xml -->
<input-method xmlns:android="http://schemas.android.com/apk/res/android"
    android:settingsActivity="com.example.atype.SettingsActivity"
    android:supportsSwitchingToNextInputMethod="true">
    <subtype
        android:label="@string/voice_input"
        android:imeSubtypeLocale=""
        android:imeSubtypeMode="voice"
        android:isAuxiliary="true"
        android:overridesImplicitlyEnabledSubtype="true" />
</input-method>
```

```xml
<!-- AndroidManifest.xml -->
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<service
    android:name=".ime.AtypeImeService"
    android:exported="true"
    android:permission="android.permission.BIND_INPUT_METHOD">
    <intent-filter><action android:name="android.view.InputMethod" /></intent-filter>
    <meta-data android:name="android.view.im" android:resource="@xml/method" />
</service>
```

**三個關鍵屬性的語意**（AOSP `InputMethodSubtype.java` javadoc，[android-36 鏡像](https://github.com/Reginer/aosp-android-jar/blob/main/android-36/src/android/view/inputmethod/InputMethodSubtype.java)）：

- `imeSubtypeMode="voice"`：subtype 的模式（javadoc 以 "voice, keyboard" 為例）。其他鍵盤透過 `InputMethodManager.getShortcutInputMethodsAndSubtypes()` 找到的「shortcut IME」就是這類 voice subtype。
- `isAuxiliary="true"`："An auxiliary subtype cannot be chosen as the default IME in Settings"、"The framework will never switch to this subtype through switchToLastInputMethod"，用途是 "IMEs to specify they are meant to be invoked temporarily in a one-shot way, and to return to the previous IME once finished (e.g. voice input)"。這正是我們要的一次性語音模式。
- `overridesImplicitlyEnabledSubtype="true"`：沒有其他 subtype 被明確啟用時預設啟用，且不會出現在各 IME 的 subtype 啟用清單裡（適合「自動語言」類 subtype）。

### 2.2 生命週期

[InputMethodService 參考](https://developer.android.com/reference/android/inputmethodservice/InputMethodService)：`onCreate → onCreateInputView → onStartInput(EditorInfo, restarting) → onStartInputView → onFinishInputView → onFinishInput`。`onWindowShown/onWindowHidden` 可對應 Compose 的 ON_RESUME/ON_PAUSE（FlorisBoard 作法）。`requestShowSelf()/requestHideSelf()` 用來自行顯示/隱藏；`onEvaluateFullscreenMode()` 回傳 false 可避免橫向全螢幕模式。

### 2.3 Kotlin 骨架（含 Compose）

FUTO 的 `VoiceInputMethodService` 宣告為 `InputMethodService(), LifecycleOwner, ViewModelStoreOwner, SavedStateRegistryOwner`，在 `onCreateInputView()` 建 `ComposeView` 並 `setOwners()` 把自己設為 decor view 的 ViewTree owners（[VoiceInputMethodService.kt](https://github.com/futo-org/voice-input/blob/master/app/src/main/java/org/futo/voiceinput/VoiceInputMethodService.kt)）。FlorisBoard 抽成可重用的 [`LifecycleInputMethodService`](https://github.com/florisboard/florisboard/blob/main/app/src/main/kotlin/dev/patrickgold/florisboard/ime/lifecycle/LifecycleInputMethodService.kt)：`LifecycleRegistry` 在 `onCreate` 發 ON_CREATE/ON_START、`onWindowShown` 發 ON_RESUME、`onWindowHidden` 發 ON_PAUSE、`onDestroy` 發 ON_STOP/ON_DESTROY，並以 `decorView.setViewTreeLifecycleOwner(this)` 等三個呼叫安裝 owners。整合後的最小骨架：

```kotlin
open class LifecycleImeService : InputMethodService(),
    LifecycleOwner, ViewModelStoreOwner, SavedStateRegistryOwner {

    private val lifecycleRegistry by lazy { LifecycleRegistry(this) }
    private val store by lazy { ViewModelStore() }
    private val savedStateController by lazy { SavedStateRegistryController.create(this) }

    override val lifecycle: Lifecycle get() = lifecycleRegistry
    override val viewModelStore: ViewModelStore get() = store
    override val savedStateRegistry: SavedStateRegistry get() = savedStateController.savedStateRegistry

    override fun onCreate() {
        super.onCreate()
        savedStateController.performRestore(null)
        lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_CREATE)
        lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_START)
    }
    override fun onWindowShown() { super.onWindowShown(); lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_RESUME) }
    override fun onWindowHidden() { super.onWindowHidden(); lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_PAUSE) }
    override fun onDestroy() {
        lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_STOP)
        lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_DESTROY)
        store.clear(); super.onDestroy()
    }

    protected fun installViewTreeOwners() {
        val decor = window!!.window!!.decorView
        decor.setViewTreeLifecycleOwner(this)
        decor.setViewTreeViewModelStoreOwner(this)
        decor.setViewTreeSavedStateRegistryOwner(this)
    }
}

class AtypeImeService : LifecycleImeService() {
    private val recognizer by lazy { Recognizer(this, lifecycleScope) }

    override fun onCreateInputView(): View {
        installViewTreeOwners()
        return ComposeView(this).apply {
            setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnViewTreeLifecycleDestroyed)
            setContent { VoicePanel(state = recognizer.state, onCancel = ::returnToPreviousIme) }
        }
    }
    override fun onEvaluateFullscreenMode() = false

    override fun onStartInputView(info: EditorInfo, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        if (!restarting) recognizer.start(
            onPartial = { currentInputConnection?.setComposingText(it, 1) },
            onFinal = { commitAndReturn(it) },
            onNeedPermission = { launchPermissionActivity() }
        )
    }
    override fun onFinishInputView(finishingInput: Boolean) {
        recognizer.stop(); super.onFinishInputView(finishingInput)
    }
}
```

### 2.4 跨技術棧結論：IME 必須原生

- Android 只認 `InputMethodService` 子類。Flutter/React Native/KMP 都沒有 IME 抽象；GitHub 上確有把 `FlutterEngine + FlutterView` 掛進 `InputMethodService` 的專案（例如 [Indica-Keyboard](https://github.com/noelpinto47/Indica-Keyboard/blob/main/android/src/main/kotlin/com/noelpinto47/indica_keyboard/IndicaInputMethodService.kt)、[flime2](https://github.com/youunn/flime2/blob/main/android/app/src/main/kotlin/im/nue/flime/Flime.kt)），但 Service 殼、`InputConnection`、權限、切換邏輯全在 Kotlin。Flutter 專案 [VoxWrite](https://github.com/drgnchan/Voxwrite) 的做法是「Flutter 設定 App ＋ 獨立原生 auxiliary voice IME」，同樣印證。
- Compose 可用（FUTO、Sayboard、Transcribro、FlorisBoard 皆用），代價是上述 owner 樣板與 IME 視窗的 insets/edge-to-edge 處理。
- **建議**：IME 模組純 Kotlin；若桌機/手機要共用「文字清理/格式化規則、API client」，用 KMP 共用 commonMain 邏輯即可，不要讓 UI 框架介入 IME。

---

## 3. 與其他鍵盤的交接（handoff）與自動切回

### 3.1 其他鍵盤怎麼找到我們

AOSP LatinIME（[RichInputMethodManager.java, LineageOS 鏡像](https://github.com/LineageOS/android_packages_inputmethods_LatinIME/blob/lineage-21.0/java/src/com/android/inputmethod/latin/RichInputMethodManager.java)）：`getShortcutInputMethodsAndSubtypes()` 取第一個 shortcut IME 與其第一個 subtype，再以 `imm.setInputMethodAndSubtype(token, imiId, subtype)` 切換。HeliBoard 的 Kotlin 版（[RichInputMethodManager.kt](https://github.com/Helium314/HeliBoard/blob/main/app/src/main/java/helium314/keyboard/latin/RichInputMethodManager.kt)）：

```kotlin
shortcuts = inputMethodManager.shortcutInputMethodsAndSubtypes.entries
    .flatMap { (imi, subtypes) -> subtypes.map { Shortcut(imi, it) } }
fun switchToShortcutIme(inputMethodService: InputMethodService) = scope.launch {
    val imiId = shortcuts.firstOrNull()?.imi?.id ?: return@launch
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
        inputMethodService.switchInputMethod(imiId, shortcuts.first().subtype)
```

AOSP 的 `getShortcutInputMethodsAndSubtypes()` 會「先檢查系統 IME」（[android-36 InputMethodManager.java](https://github.com/Reginer/aosp-android-jar/blob/main/android-36/src/android/view/inputmethod/InputMethodManager.java) 註解 "Ensure we check system IMEs first"），意即若裝置預載的 Google 語音輸入也宣告了 voice subtype，開源鍵盤可能優先挑到它——**使用者需在系統設定停用 Google 語音輸入或在鍵盤設定中選我們**；這是真實的 onboarding 摩擦點。

FUTO README（[futo-org/voice-input](https://github.com/futo-org/voice-input)）整理的相容性：**可交接**：HeliBoard、FlorisBoard、AnySoftKeyboard、Unexpected Keyboard、AOSP 系、Grammarly、Microsoft SwiftKey；**不可交接**：Gboard、Samsung Keyboard、Simple Keyboard 系（hardcoded 到特定服務）。另一個入口是 `android.speech.action.RECOGNIZE_SPEECH` 隱式 Intent（FUTO 的 `RecognizeActivity`，`launchMode="singleInstance"`，以浮窗回傳結果），供一般 App 與部分鍵盤呼叫。

**開機後找不到的坑**：FUTO issue [#17](https://github.com/futo-org/voice-input/issues/17)——SwiftKey 等鍵盤在重開機後抓不到 FUTO，直到 App 被開啟一次；FUTO 以一個 exported 的 `DummyService` 註冊 recognition/keyboard intent-filter 作為 workaround。Sayboard 則需要 `QUERY_ALL_PACKAGES`（README 說是 speech recognition service 的系統需求）。設計時要考慮 package visibility（`<queries>`）。

### 3.2 自動切回上一個鍵盤

FUTO `VoiceInputMethodService.kt` 在辨識完成/取消時：

```kotlin
if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
    switchToPreviousInputMethod()           // InputMethodService, API 28
} else {
    inputMethodManager.switchToLastInputMethod(window.window!!.attributes.token)
}
```

Sayboard `ActionManager.kt`（[原始碼](https://github.com/ElishaAz/Sayboard/blob/master/app/src/main/java/com/elishaazaria/sayboard/ime/ActionManager.kt)）更完整：先看使用者是否指定「預設鍵盤」→ `ime.switchInputMethod(prefs.logicDefaultIME.get())`；否則 `switchToPreviousInputMethod()`；回傳 false（沒有上一個）時退回指定 IME 或 Toast 報錯。建議照抄這套 fallback，因為使用者可能直接從系統設定選到我們、沒有「上一個」。

```kotlin
fun returnToPreviousIme() {
    val ok = if (Build.VERSION.SDK_INT >= 28) switchToPreviousInputMethod()
             else imm.switchToLastInputMethod(window.window!!.attributes.token)
    if (!ok) prefs.fallbackImeId?.let { switchInputMethod(it) }
        ?: imm.showInputMethodPicker()
}
```

官方 javadoc：`switchToPreviousInputMethod()` = "Force switch to the last used input method and subtype"；`switchToNextInputMethod(onlyCurrentIme)`、`shouldOfferSwitchingToNextInputMethod()` 用於地球鍵（[InputMethodService.java](https://github.com/Reginer/aosp-android-jar/blob/main/android-36/src/android/inputmethodservice/InputMethodService.java)）。

---

## 4. 麥克風：權限、程序狀態、Foreground Service

### 4.1 Runtime permission 必須經由 Activity

FUTO `AudioRecognizer.create()`：`checkSelfPermission(RECORD_AUDIO) != GRANTED` → `needPermission()`；原始碼註解明言權限請求無法從 Service 發起，需啟動 Activity（`SettingsActivity`/`RecognizeActivity` 以 `ActivityResultContracts.RequestPermission` 處理）。Sayboard 在 `onCreate/onInitializeInterface/onStartInputView` 都檢查，缺權限時在鍵盤面板顯示錯誤。建議流程：

```kotlin
private fun launchPermissionActivity() {
    startActivity(Intent(this, MicPermissionActivity::class.java)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION))
}
// MicPermissionActivity: 透明主題, registerForActivityResult(RequestPermission()) { granted -> finish() }
```

Android 10+ 對「從背景啟動 Activity」有限制，但 "apps are not affected if they start activities as a direct result of user interaction"（[Android 10 privacy changes](https://developer.android.com/about/versions/10/privacy/changes)）；IME 面板上的使用者點擊屬於此類。Android 15 進一步要求非可見視窗不得背景啟動 Activity（[behavior-changes-15](https://developer.android.com/about/versions/15/behavior-changes-15)），IME 視窗可見時啟動是安全的，**不要在 `onStartInput` 無使用者互動時自動彈權限頁**。

### 4.2 IME 可見時可以直接錄音（不需 FGS）

AOSP `InputMethodBindingController`（[android-36](https://github.com/Reginer/aosp-android-jar/blob/main/android-36/src/com/android/server/inputmethod/InputMethodBindingController.java)）定義 "Binding flags used only while the InputMethodService is showing window"：`IME_VISIBLE_BIND_FLAGS = BIND_AUTO_CREATE | BIND_TREAT_LIKE_ACTIVITY | BIND_FOREGROUND_SERVICE ...`。這使可見 IME 程序被視為前景，FUTO 便直接在 IME 內：

```kotlin
AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, 16000,
    AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, 16000 * 2 * 5)
```

以 `lifecycleScope.launch(Dispatchers.Default)` 讀取、WebRTC VAD（very aggressive；連續 >8 幀語音或 RMS>0.01 視為開始，語音後連續 >66 幀靜音即停止，另有 30 秒上限）、停止後呼叫 whisper（[AudioRecognizer.kt](https://github.com/futo-org/voice-input/blob/master/app/src/main/java/org/futo/voiceinput/AudioRecognizer.kt)）。FUTO manifest 雖宣告 `foregroundServiceType="microphone"` 與 `FOREGROUND_SERVICE` 權限，但原始碼**沒有 `startForeground`**；Sayboard 的 microphone FGS 是給它的 `RecognitionService` 用。

### 4.3 何時需要 microphone FGS、以及限制

[fg-service-types](https://developer.android.com/develop/background-work/services/fg-service-types)：`microphone` 類型需 `FOREGROUND_SERVICE_MICROPHONE` + `RECORD_AUDIO`（runtime）；"you cannot create a microphone foreground service while your app is in the background"。[restrictions-bg-start](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start) 的一般豁免清單明列 "Your app is the device's current input method"，但 while-in-use（麥克風）豁免清單只有系統元件、widget/通知互動、其他可見 App 的 PendingIntent、VoiceInteractionService 等——**IME 身分不在 while-in-use 豁免內**，所以 microphone FGS 必須在 IME/Activity 可見時啟動。Android 14 起 targetSdk 34 必須宣告 `foregroundServiceType` 否則 `MissingForegroundServiceTypeException`（[fgs-types-required](https://developer.android.com/about/versions/14/changes/fgs-types-required)）；Android 14+ 禁止從 `BOOT_COMPLETED` 啟動 microphone FGS（[Android 15 FGS changes](https://developer.android.com/about/versions/15/changes/foreground-service-types)）。Android 15 另要求 top app 或 FGS 才能取得 audio focus（錄音通常不需要，但若要暫停音樂需注意）。

**設計結論**：主要路徑「鍵盤面板可見 → 錄音 → 辨識 → 提交 → 切回」完全不用 FGS。只有「浮動按鈕/長時間聽寫鍵盤已收起」的進階模式才啟 FGS，且要處理通知與 Android 16 的 FGS job quota 變更（[behavior-changes-all 16](https://developer.android.com/about/versions/16/behavior-changes-all)）。

### 4.4 Direct boot

`InputMethodManagerService` 以 `MATCH_DIRECT_BOOT_AWARE | MATCH_DIRECT_BOOT_UNAWARE` 列舉 IME（[android-36](https://github.com/Reginer/aosp-android-jar/blob/main/android-36/src/com/android/server/inputmethod/InputMethodManagerService.java)），但未 `directBootAware` 的元件在首次解鎖前不會啟動，且只能用 device-protected storage（[direct-boot](https://developer.android.com/privacy-and-security/direct-boot)）。語音 IME 幾乎不會在鎖屏前使用，**建議不要宣告 directBootAware**，避免模型檔與偏好在 DE/CE 儲存體間分裂；工作資料夾（work profile）下 IME 由主使用者提供，一般不需特別處理。

---

## 5. `InputConnection`：插入、取代、刪除、讀取上下文

[InputConnection 參考](https://developer.android.com/reference/android/view/inputmethod/InputConnection)重點：
- `commitText(text, 1)`：提交並把游標放在文字後。
- `setComposingText(text, 1)` / `finishComposingText()`：顯示「正在辨識中」的灰字（partial），最後用 `commitText` 定稿；Sayboard `TextManager.kt` 與 FUTO 皆是 partial→`setComposingText`、final→`commitText` 的模式。
- `getTextBeforeCursor(n, 0)` / `getTextAfterCursor` / `getSelectedText` / `getSurroundingText(before, after, flags)`（API 31）：可能回傳 `null`（編輯器未實作或逾時），必須 null-safe。
- `deleteSurroundingTextInCodePoints(before, after)`（API 24）優先於 `deleteSurroundingText`，避免切開 emoji/代理對。
- `beginBatchEdit()/endBatchEdit()` 包住多步操作；`performEditorAction(IME_ACTION_SEND/GO)` 可實作「說完直接送出」；`performContextMenuAction(android.R.id.paste)` 是備援。
- 密碼欄（`EditorInfo.inputType` 含 `TYPE_TEXT_VARIATION_PASSWORD`）應拒絕啟動辨識或至少不送雲端。

```kotlin
fun commitFinal(ic: InputConnection, text: String, editor: EditorInfo) {
    ic.beginBatchEdit()
    val before = ic.getTextBeforeCursor(64, 0) ?: ""
    val needsSpace = before.isNotEmpty() && !before.last().isWhitespace()
                     && isLatin(before.last()) && isLatin(text.first())  // 中文不加空格
    ic.finishComposingText()
    ic.commitText((if (needsSpace) " " else "") + text, 1)
    ic.endBatchEdit()
}
fun replaceLastUtterance(ic: InputConnection, oldLen: Int, newText: String) {
    ic.beginBatchEdit(); ic.deleteSurroundingTextInCodePoints(oldLen, 0); ic.commitText(newText, 1); ic.endBatchEdit()
}
```

**中英夾雜細節**：Sayboard/FUTO 的「自動補空格、首字大寫」邏輯是英文導向；我們要依前後字元腳本判斷（中文↔中文不加空格、中英交界可選加空格、全形標點）。LLM 潤稿階段可一併處理。

---

## 6. 替代入口：無障礙、浮窗貼上、Quick Settings、助理

| 方案 | 能力 | 風險/限制 |
|---|---|---|
| **AccessibilityService** `ACTION_SET_TEXT`（API 21，用 `ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE`，會清除原文字並把游標放尾端）、`ACTION_PASTE`、`ACTION_SET_SELECTION`（[AccessibilityNodeInfo](https://developer.android.com/reference/android/view/accessibility/AccessibilityNodeInfo)） | 可對焦點 `EditText` 整段設值，不需成為 IME | `SET_TEXT` 是「取代全部」不是插入；WebView/Compose/遊戲節點常不可編輯；Play 對無障礙 API 用於非無障礙目的有嚴格審查（政策頁 [support.google.com/.../10964491](https://support.google.com/googleplay/android-developer/answer/10964491)，本次無法直接讀取）；Android 16 棄用 `announceForAccessibility`（[16 behavior changes](https://developer.android.com/about/versions/16/behavior-changes-all)）。|
| **浮窗 `SYSTEM_ALERT_WINDOW` + 剪貼簿貼上** | 任何 App 上方浮一顆麥克風鍵 | Android 10 起只有「預設 IME 或焦點 App」能讀剪貼簿（[Android 10 privacy](https://developer.android.com/about/versions/10/privacy/changes)），寫入剪貼簿可以但「貼上」動作要靠使用者或無障礙；Android 15 要 overlay **實際可見**才算 FGS 背景啟動豁免（[behavior-changes-15](https://developer.android.com/about/versions/15/behavior-changes-15)）。適合「複製到剪貼簿＋提示貼上」的降級體驗。|
| **Quick Settings Tile** `TileService` | 下拉快捷鍵 | `onClick` 後 Android 14+ 需 `startActivityAndCollapse(PendingIntent)`（[TileService](https://developer.android.com/reference/android/service/quicksettings/TileService)）；可用來一鍵「切換到我們的 IME 並展開」（需 `InputMethodManager.showInputMethodPicker()` 或引導）。|
| **預設數位助理** `VoiceInteractionService`/`RoleManager.ROLE_ASSISTANT` | 長按 Home/電源啟動、可讀 `AssistStructure` 畫面文字 | 需 `BIND_VOICE_INTERACTION`、使用者得把預設助理從 Gemini 換成我們；無法任意注入文字（[VoiceInteractionService](https://developer.android.com/reference/android/service/voice/VoiceInteractionService)）。只適合極客使用者。|
| **`RECOGNIZE_SPEECH` Activity / `RecognitionService`** | 讓其他 App/鍵盤把我們當系統語音引擎 | 要處理可見性查詢與開機註冊問題（FUTO #17）；`RecognitionService` 需 microphone FGS（Sayboard）。|

結論：IME 是主幹，Tile + `RECOGNIZE_SPEECH` 為輔，無障礙與浮窗只作可選降級，避免政策風險。

---

## 7. 本地 STT 引擎與模型（Android）

### 7.1 whisper.cpp（JNI/CMake）
- 模型大小與記憶體（[README](https://github.com/ggml-org/whisper.cpp)）：tiny 75 MiB/~273 MB RAM、base 142 MiB/~388 MB、small 466 MiB/~852 MB、medium 1.5 GiB/~2.1 GB、large 2.9 GiB/~3.9 GB；量化 `large-v3-turbo-q5_0` 547 MiB、`large-v3-q5_0` 1.1 GiB（[models/README](https://github.com/ggml-org/whisper.cpp/blob/master/models/README.md)）。
- 官方 Android 範例（[examples/whisper.android](https://github.com/ggml-org/whisper.cpp/tree/master/examples/whisper.android)）："I recommend the tiny or base models for running on an Android device"；Vulkan 支援存在但 Android 整合未在文件中承諾。
- 實務：FUTO Voice Input（16 語含中文）、Transcribro（whisper.cpp + Silero VAD，Compose，目前僅英文；[repo](https://github.com/soupslurpr/Transcribro)）。Whisper 是非串流（講完才出字），中文需 small 以上才可用，手機上延遲明顯。

### 7.2 sherpa-onnx（Apache-2.0，Kotlin API，推薦）
[README](https://github.com/k2-fsa/sherpa-onnx)：支援 arm64/arm32/x86 Android，Kotlin/Java，預編 APK；模型族含 streaming/offline Zipformer、Paraformer（含方言）、SenseVoice（zh/en/ja/ko/yue）、Whisper、Moonshine、FireRedASR、Dolphin、TeleSpeech。
- **SenseVoice**（[pretrained.rst](https://github.com/k2-fsa/sherpa/blob/master/docs/source/onnx/sense-voice/pretrained.rst)）：`sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17` int8 **228 MB**（fp32 894 MB），`use_itn=1` 可輸出標點；RK3588 CPU RTF：Cortex-A55 單執行緒 0.436、四執行緒 0.175；Cortex-A76 單執行緒 **0.099**。2025-09-09 版 226 MB（粵語加強，無標點）。非串流但極快，適合「放開按鍵→0.5 秒內出全文」。
- **Streaming Zipformer**（[zipformer-transducer-models.rst](https://github.com/k2-fsa/sherpa/blob/master/docs/source/onnx/pretrained_models/online-transducer/zipformer-transducer-models.rst)）：bilingual zh-en 2023-02-20 int8 encoder 174 MB；small bilingual zh-en int8 encoder 41 MB + decoder 3.4 MB + joiner 3.1 MB（≈47 MB）；2025-06-30 zh int8 154 MB、xlarge 726 MB。適合邊講邊出灰字。
- **Offline Paraformer**（[paraformer-models.rst](https://github.com/k2-fsa/sherpa/blob/master/docs/source/onnx/pretrained_models/offline-paraformer/paraformer-models.rst)）：zh-small 2024-03-09 int8 **79 MB**（中英＋方言）、trilingual zh-cantonese-en int8 234 MB。
- 文件另有 "Android with QNN"（Qualcomm NPU）章節（[docs 目錄](https://github.com/k2-fsa/sherpa/tree/master/docs/source/onnx/android)），本次未能讀取細節。

### 7.3 Vosk（Apache-2.0）
[vosk-api README](https://github.com/alphacep/vosk-api)：20+ 語言含中文、"small (50 Mb)" 模型、"zero-latency response with streaming API"、有 Android binding。中文 `vosk-model-small-cn-0.22` 約 42–50 MB、`vosk-model-cn-0.22` 約 1.3 GB（第三方 catalog 數字，官方頁 alphacephei.com 本次無法讀取）。Sayboard 即以 Vosk 實作（GPL-3.0）。Kaldi 架構準確度不如 SenseVoice/Zipformer，但 RAM/電量最省。

### 7.4 Google `SpeechRecognizer` on-device
`SpeechRecognizer.createOnDeviceSpeechRecognizer(context)`（API 31，[android-31 原始碼](https://github.com/Reginer/aosp-android-jar/blob/main/android-31/src/android/speech/SpeechRecognizer.java)）需先 `isOnDeviceRecognitionAvailable()`，不可用則拋 `UnsupportedOperationException`；`checkRecognitionSupport()`/`triggerModelDownload()` 可觸發語言包下載；必須主執行緒呼叫；class javadoc 明言 "not intended to be used for continuous recognition"。`RecognizerIntent.EXTRA_PREFER_OFFLINE`（只用離線引擎）、`EXTRA_PARTIAL_RESULTS`、`EXTRA_ENABLE_FORMATTING`、`EXTRA_SEGMENTED_SESSION`（[RecognizerIntent.java](https://github.com/Reginer/aosp-android-jar/blob/main/android-36/src/android/speech/RecognizerIntent.java)）。優點：零模型體積、免費；缺點：依賴 Google app/Pixel 的離線語言包，中文（zh-TW）離線可用性視裝置而定，AOSP/中國 ROM 可能沒有，且無法控制品質與格式。可作為「無模型時的第一天體驗」fallback。

### 7.5 Gemini Nano / ML Kit GenAI
[developer.android.com/ai/gemini-nano](https://developer.android.com/ai/gemini-nano)：經 AICore 存取，ML Kit GenAI 提供 Prompt、Summarization、Proofreading、Rewriting、Image Description，頁面並列出 "Speech Recognition — Transcribe spoken audio to text"（細節頁本次 404/無法讀取，**需再驗證**）。Prompt API：`com.google.mlkit:genai-prompt` ≥ `1.0.0-beta4`、minSdk 26、需等 `FeatureStatus == AVAILABLE`、>200 字建議 prefix caching（[SKILL.md](https://github.com/android/skills/blob/main/device-ai/ml-kit-genai-prompt-api/SKILL.md)）。支援裝置清單在 developers.google.com（本次被阻擋）；一般認知僅 Pixel 9+/部分旗艦，**不能當主要路徑**，可作「本機潤稿」的可選加速。

### 7.6 加速與打包
- NNAPI 自 Android 15 棄用（[NDK guide](https://developer.android.com/ndk/guides/neuralnetworks)），建議改用 LiteRT GPU/NPU（[LiteRT](https://github.com/google-ai-edge/LiteRT)：OpenCL/OpenGL GPU、Qualcomm/MediaTek/Tensor NPU 單一 API）或 ONNX Runtime QNN EP（onnxruntime.ai 本次無法讀取）。初版以 CPU int8 即可（SenseVoice A76 RTF 0.1）。
- 原生 .so 必須 16 KB page 對齊：Play 於 **2027-02-01** 起強制 targetSdk 35+ 的 App 支援 16 KB；NDK r28+ 預設，舊版加 `-Wl,-z,max-page-size=16384`、AGP ≥ 8.5.1（[page-sizes](https://developer.android.com/guide/practices/page-sizes)）。sherpa-onnx/whisper.cpp 自建時要確認。
- 模型不要打進 APK（Play 200 MB AAB 上限之外還拖慢安裝）：用 Play Asset Delivery 或首次啟動下載到 `filesDir`（Sayboard/FUTO 皆內建下載器）。

### 7.7 RAM/電池/延遲粗估（供規劃）
- 中階機（4–6 GB RAM、Cortex-A7x）：SenseVoice int8 推論記憶體約模型 ×1.5–2（~400–500 MB），應在鍵盤收起後釋放模型或延遲卸載；Zipformer small（47 MB）可常駐。
- 旗艦（8–16 GB）：可考慮 Zipformer zh 2025（154 MB）串流＋SenseVoice 定稿雙引擎。
- 電池：串流模型每秒持續推論，長聽寫耗電高於「VAD 切段後離線辨識」；FUTO 的 VAD-gated 模式是省電參考。
- 這些為推估，需實機量測（見未解問題）。

---

## 8. Play 政策與上架

- **Target SDK**：2026-08-31 起新 App/更新須 target **Android 16 (API 36)**，可申請延至 2026-11-01（[target-sdk](https://developer.android.com/google/play/requirements/target-sdk)）。target 36 代表：predictive back 預設啟用且 `onBackPressed` 不再被呼叫、無法退出 edge-to-edge（[behavior-changes-16](https://developer.android.com/about/versions/16/behavior-changes-16)）——IME 面板需正確處理 insets。
- **Data safety**：`RECORD_AUDIO` 屬會觸發「Voice or sound recordings」宣告的權限（[collect-share 指南](https://developer.android.com/guide/topics/data/collect-share)）；若音訊只在裝置內處理、不上傳，仍需在表單中依「存取但不收集/分享」原則正確填寫；若送雲端 STT/LLM 則是「收集並分享」。
- **Prominent disclosure & consent**（User Data policy，[answer/9888170](https://support.google.com/googleplay/android-developer/answer/9888170)，本次無法直接讀取，依既有政策理解）：在首次錄音前需在 App 內顯示明確說明（收集什麼、用途、是否分享）並取得主動同意，不能只靠系統權限框。IME 可看見所有輸入文字，隱私政策必須說明不蒐集鍵入內容。
- **無障礙 API**：若採用 AccessibilityService 注入，需在 Play Console 填寫用途聲明且非無障礙用途常被拒；建議避免。
- Play 政策頁亦預告 2027-01-27 起的 Location/Contacts/SMS 權限政策變更（[play-policies](https://developer.android.com/distribute/play-policies)），與本產品無直接關係。

---

## 9. 台灣中文輸入 UX 期待

- 台灣主流為 Gboard 注音/倉頡（以及 Samsung Keyboard）。依 FUTO 的相容性清單，**Gboard 的麥克風鍵不會交接給第三方**；可行體驗為：(a) 使用者用「地球鍵長按/輸入法切換器」切到我們，講完自動切回 Gboard；(b) 我們提供 Quick Settings Tile 或通知捷徑一鍵切換；(c) 中長期自行提供注音鍵盤（成本高）。
- 中文輸出格式：全形標點（，。？！）、中英間距規則、數字/單位 ITN（SenseVoice `use_itn`）、繁體正規化（SenseVoice/Paraformer 多以簡體語料訓練，需 OpenCC 類轉換與台灣用語詞表，否則「視頻/軟件」會出現）。
- 中英夾雜：SenseVoice/Zipformer bilingual 直接支援 code-switching；whisper 需靠語言自動偵測，較不穩。

---

## 10. 對我們的設計意涵

1. **Android 端 = 原生 Kotlin IME 模組 + Compose UI**，與桌機端僅共用「文字後處理/LLM client/詞彙表」（可用 KMP 或純 HTTP API 契約共用）。
2. **產品定位為 auxiliary voice IME**，不做完整鍵盤（至少 v1）。必須做好三件事：手動切換引導（含停用 Google 語音輸入的教學）、自動切回（Sayboard 式 fallback）、對 Gboard 使用者的 Tile/通知入口。
3. **權限與程序模型**：錄音只在 IME 可見時進行，不用 FGS；權限經透明 Activity；`EditorInfo` 為密碼欄時停用。
4. **STT 預設本地 sherpa-onnx**：v1 用 SenseVoice int8（228 MB，按住說話→放開出字，含標點）；v2 加 streaming Zipformer small（47 MB）做即時灰字（`setComposingText`），最終以 SenseVoice 或雲端定稿後 `commitText` 取代。Vosk 僅作低階機備援；Google on-device 作「尚未下載模型」時的第一天體驗。
5. **文字插入策略**：partial → composing；final → `beginBatchEdit + finishComposingText + commitText`；「重講取代」用 `deleteSurroundingTextInCodePoints`。永遠 null-check `InputConnection`。
6. **後處理鏈**：本地 ITN/繁化/標點 → 可選雲端 LLM 潤稿（使用者可關、密碼欄禁止）→ 一次性提交，減少 App 看到的中間狀態。
7. **上架工程**：targetSdk 36、AGP ≥ 8.5.1、NDK r28、16 KB 對齊、Play Asset Delivery 或自建下載器、Data safety + prominent disclosure 畫面放在 onboarding。
8. **不做**：AccessibilityService 注入、常駐 microphone FGS、依賴 Gemini Nano 作主要路徑。

---

## 11. 未解問題（Open Questions）

1. Gboard 是否在任何版本/地區提供可設定的第三方語音輸入？（FUTO 稱 hardcoded；需實測 2026 版 Gboard 注音。）
2. ML Kit GenAI「Speech Recognition」API 的實際存在、支援裝置與語言（頁面被阻擋/404，需於 developers.google.com/ml-kit/genai 驗證）。
3. `SpeechRecognizer.createOnDeviceSpeechRecognizer` 在台灣常見機型（Pixel/Samsung/小米/OPPO）上 zh-TW 離線語言包的可用率。
4. SenseVoice/Zipformer 在中階 Android（A55/A7x）上實際 RTF、記憶體峰值與每分鐘耗電；是否需要 QNN/LiteRT NPU 加速。
5. 繁體/台灣用語品質：SenseVoice 輸出簡體的比例、OpenCC 轉換後錯誤率，是否需要微調或 hotword/LM bias（sherpa-onnx 支援 keywords/hotwords，需評估）。
6. Prominent disclosure 的精確措辭與 Data safety 對「音訊只在本機處理」的歸類（官方政策頁本次無法讀取）。
7. 開機後其他鍵盤找不到我們的問題（FUTO #17）在 Android 15/16 的最新行為，是否仍需 DummyService 或 `<queries>` 宣告。
8. Compose 在 IME 視窗內於 Android 16 edge-to-edge 強制下的 insets 行為（導覽列高度、橫向）需實機驗證。
