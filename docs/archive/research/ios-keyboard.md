# iOS 語音輸入（Typeless-like）技術研究：Keyboard Extension、麥克風限制與可行架構

研究日期：2026-10-01。優先引用 2025–2026 的 Apple 官方文件與開源專案原始碼。
研究環境限制說明：本次工作階段的網路搜尋額度已用盡，且 wisprflow.ai、typeless.com、superwhisper.com、willowvoice.com、withaqua.com、apps.apple.com/itunes.apple.com、support.apple.com、Reddit、StackOverflow、Apple Developer Forums 搜尋頁皆被代理阻擋。因此競品機制的證據主要來自：(1) Apple 官方文件（JSON 端點）、(2) 開源 iOS 聽寫 app 的原始碼與 issue（Dictus、VoiceInk-iOS、OpenSuperWhisper、KeyboardKit 等）、(3) 這些 issue 中對 Wispr Flow / superwhisper / Willow 行為的描述。凡屬二手轉述者，文中均明確標示。

---

## 1. 執行摘要（Executive Summary）

1. **關鍵問題的答案：iOS 自訂鍵盤（`UIInputViewController` extension）無法使用麥克風。** Apple 官方文件明言「Custom keyboards, like all app extensions in iOS 8.0, have no access to the device microphone, so dictation input is not possible」，且「Allow Full Access」並不改變這點（Full Access 只開放網路、App Group 寫入、剪貼簿、定位/聯絡人等）。2026 年的開源專案實測仍一致回報 keyboard extension 無法錄音（「media-server-level block, through iOS 26.x; Full Access doesn't help」）。
2. **所有市售產品（Wispr Flow、superwhisper iOS、Willow、Spokenly、Dictus）在 iOS 上都採同一套「App 切換 + 背景錄音 + 鍵盤只負責 UI 與插字」模式**：鍵盤上的麥克風鍵透過 URL scheme 開啟主 app → 主 app 在前景啟動 `AVAudioSession`（`.playAndRecord`）並以 `UIBackgroundModes: audio` 在背景持續錄音 → 使用者「往左滑回去」原本的 app → 鍵盤經 App Group + Darwin notification 取得辨識/潤飾結果後用 `textDocumentProxy.insertText` 插入。Wispr Flow 的官方措辭（二手引用）：「We wish you didn't have to switch apps to use Flow, but Apple requires this step」。這段 app 切換是無法消除的 UX 摩擦；自動跳回原 app 只能靠私有 API（App Review 風險）。
3. **記憶體**：Apple 只說「strict memory limits… vary by device model」，超限即被 `EXC_CRASH (SIGQUIT)` 砍掉。社群實測：Dictus 設計上限 ~50 MB、實測 66–70 MB 高原仍存活但「成為系統回收時的大目標」；其他專案共識 30–60 MB。結論：**任何 ASR/LLM 模型都不能放進鍵盤 extension**，鍵盤必須是 thin client。
4. **iOS 26 的新武器**：`SpeechAnalyzer` / `SpeechTranscriber` 是完全裝置端、模型存於系統空間「不佔 app 記憶體」、支援 30 個 locale（含 **zh-TW、zh-HK、zh-CN、yue-CN、ja-JP、ko-KR**），非常適合在主 app 做即時串流辨識；`Foundation Models` 提供裝置端 LLM 做文字潤飾，但 context 僅 **4,096 tokens**（中文約 1 字 = 1 token），且只在支援 Apple Intelligence 的機型可用。兩者是否能在 extension 內使用無官方說明，但因鍵盤不錄音，這問題在建議架構下不重要。
5. **建議架構**：Swift 原生鍵盤 extension（< 40 MB、無 ML、可在無 Full Access 下至少能讀 App Group 插字）+ Swift 主 app（錄音、ASR、LLM 潤飾、Live Activity、App Intents 控制項）+ App Group/Darwin notification IPC。跨平台框架（Flutter/RN/KMP）至多用於主 app 的畫面，絕不要放進 keyboard extension。

---

## 2. Keyboard Extension 的硬性限制（Apple 官方文件）

### 2.1 麥克風與聽寫

- Apple App Extension Programming Guide（Custom Keyboard 章節，雖為 archive 文件但目前仍是唯一直接談及麥克風的官方敘述）：「**Custom keyboards, like all app extensions in iOS 8.0, have no access to the device microphone, so dictation input is not possible.**」
  來源：https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html
- 現行文件《Configuring open access for a custom keyboard》列出 Full Access 開放的能力：網路傳送鍵擊、App Group 共享容器**寫入**、定位/聯絡人（需使用者同意）、iCloud、Game Center/IAP（透過 containing app）、MDM。**清單中沒有麥克風**；未開 Full Access 時「No network access、shared container 僅能讀取」。
  來源：https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard
- 2025–2026 社群實證（皆為實作過的開源專案）：
  - whispr-bro（2026-07）：「Keyboard extensions can never record audio (media-server-level block, through iOS 26.x; Full Access doesn't help)」→ 架構改為「All capture + inference lives in the main app. Keyboard = thin UI + IPC + `insertText`」。https://github.com/Micaxes/whispr-bro/issues/13
  - OpenSuperWhisper（2026-07）：「iOS keyboard extensions cannot access the microphone (hard Apple restriction since iOS 8, unchanged through iOS 18)」；「Every competitor (Spokenly, Wispr Flow, Willow) works around this via app-switching.」https://github.com/my-monkeys/OpenSuperWhisper/issues/52
  - VoiceInk-iOS（2026-07）：鍵盤內註解「keyboard extensions can't record reliably」，改以 `voiceink://record` URL scheme 開主 app 錄音。https://github.com/Beingpax/VoiceInk-iOS/issues/3
  - Dictus（App Store/TestFlight 上架中的 MIT 專案）：「WhisperKit runs inside DictusApp (the keyboard extension has a ~50 MB memory limit)」，錄音引擎 `UnifiedAudioEngine.swift` 位於主 app 目標，並以 `UIBackgroundModes: audio` 保持背景運作。https://github.com/getdictus/dictus-ios

> 注意：Dictus README 寫「Allow Full Access (required for microphone)」。對照 Apple 文件，這裡的 Full Access 實際上是鍵盤**寫入** App Group（傳遞「開始/停止錄音」狀態）與網路所需，而非讓鍵盤直接錄音。

### 2.2 其他輸入限制

- 安全欄位（密碼）會被系統鍵盤暫時取代；電話號碼欄位（`UIKeyboardTypePhonePad` / `NamePhonePad`）不可用自訂鍵盤；鍵盤只能在自己的 primary view 內繪製，不能選取文字、不能存取 host app 的編輯選單（Cut/Copy/Paste）、不能在插入點旁顯示 inline 自動校正。
  來源：同 2.1 archive 文件。
- `UITextDocumentProxy` 能力：`insertText(_:)`、`deleteBackward()`、`adjustTextPosition(byCharacterOffset:)`、`setMarkedText(_:selectedRange:)`/`unmarkText()`、`documentContextBeforeInput` / `documentContextAfterInput` / `selectedText`、`documentInputMode`、`documentIdentifier`、`hasText`。`UITextInputDelegate` 的 `textDidChange(_:)` 等回呼中 `textInput` 參數永遠為 `nil`（extension 拿不到真正的 text input）。
  來源：https://developer.apple.com/documentation/uikit/handling-text-interactions-in-custom-keyboards 、https://developer.apple.com/documentation/uikit/uitextdocumentproxy
- **context 長度**：Apple 文件沒有寫明 `documentContextBeforeInput` 回傳多少字；社群普遍觀察到只會回到最近的句/段落邊界、僅數百字元。要拿更長上下文得反覆 `adjustTextPosition` 移動游標再讀取（慢且會干擾 host app），不建議。
- `hasFullAccess`（iOS 11+）用於執行期判斷；`needsInputModeSwitchKey`：Face ID 機型系統會在鍵盤下方自動顯示地球鍵並回傳 `false`，其餘機型必須自己畫地球鍵並綁 `handleInputModeList(from:with:)`（`.allTouchEvents`，長按才會出鍵盤清單）。`hasDictationKey` 僅是旗標。
  來源：https://developer.apple.com/documentation/uikit/uiinputviewcontroller/hasfullaccess 、https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard
- 鍵盤高度：可用 Auto Layout 約束自訂高度；需同時支援 compact/regular 寬度、直橫向、iPad 浮動鍵盤。Dictus 經驗：「declared height constraint is a forbidden zone — three regressions」（高度約束改動極易出 bug）。

### 2.3 記憶體限制（目前數據）

- Apple：「Custom keyboard code executes in a separate process with strict memory limits… limits vary by device model… If exceeded, the system terminates the extension」；crash log 會顯示 `EXC_CRASH (SIGQUIT)`；**收起鍵盤不會結束 process**，記憶體不會因此釋放。https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard
- Dictus issue #555（2026）實測鍵盤 extension footprint：啟動 5 MB → 顯示鍵盤 12 MB → 閒置 20 MB → 第一次聽寫後 45 MB → 多次後 64–69 MB → 高原 66–70 MB；專案設計上限 ~50 MB；超過並未立刻被殺，但「becomes a large target when the system reclaims memory」。https://github.com/getdictus/dictus-ios/issues/555
- coriander issue #10：「community consensus is ~30-60 MB with silent kills and no crash logs」、「keyboard memory limits are undocumented」。https://github.com/Winn-Gaoti-Studio/coriander/issues/10
- 對照 whisper.cpp 官方表：tiny 模型就要 ~273 MB RAM、base ~388 MB（https://github.com/ggml-org/whisper.cpp ）→ 任何 Whisper 等級模型都不可能塞進鍵盤。

### 2.4 從鍵盤開啟主 app 的 API 現況（2024–2026 有變動）

- 官方 `NSExtensionContext.open(_:completionHandler:)` 文件只列 Today widget 與 iMessage extension 可用。https://developer.apple.com/documentation/foundation/nsextensioncontext/open(_:completionhandler:)
- 傳統 responder-chain + `openURL:` selector 的 hack **在 iOS 18 失效**（UIKit log：「BUG IN CLIENT OF UIKIT: The caller of UIApplication.openURL(_:) needs to migrate to the non-deprecated UIApplication.open(_:options:completionHandler:)」）。KeyboardKit 8.8.6 的因應：把 URL 動作改成 SwiftUI `Link` view。https://github.com/KeyboardKit/KeyboardKit/issues/795
- Dictus 的做法：直接呼叫 `extensionContext?.open(url, completionHandler:)`，並註明「preferred over SwiftUI's openURL because the latter can fail silently in keyboard extensions」（KeyboardState.swift）。https://github.com/getdictus/dictus-ios/blob/main/DictusKeyboard/KeyboardState.swift
- **審查灰色地帶**：App Store Review Guideline 4.4.1 寫「They must not: Launch other apps besides Settings」。市面上 Wispr Flow、Dictus、KeyboardKit 等皆開啟自己的 containing app 且已上架，實務上被容忍，但需在審查備註中說明理由。https://developer.apple.com/app-store/review/guidelines/

---

## 3. 競品在 iOS 上實際怎麼做

無法直接讀取官網/App Store 頁面，以下為開源專案 issue 中對競品行為的描述（二手），加上 Dictus 原始碼（一手）。

| 產品 | 機制（依證據） | 來源 |
|---|---|---|
| **Wispr Flow (iOS, 2025)** | 自訂鍵盤 + 「Flow Session」：鍵盤麥克風鍵 → 開主 app 啟動麥克風 → 顯示「Swipe back to continue」動畫 → 使用者滑回原 app，錄音在背景持續（session 預設 5 分鐘，整段 mic on）→ 鍵盤插字。對已知 app 嘗試自動跳回（URL scheme / 私有 API），未知 app 顯示動畫。官方說法「We wish you didn't have to switch apps to use Flow, but Apple requires this step」。 | https://github.com/getdictus/dictus-ios/issues/9 、https://github.com/Micaxes/whispr-bro/issues/13 、https://github.com/my-monkeys/OpenSuperWhisper/issues/52 |
| **superwhisper iOS** | 同 Wispr 的「開 app 啟動麥克風 → swipe back → 回鍵盤才開始錄」模式。 | https://github.com/getdictus/dictus-ios/issues/9 |
| **Willow / Spokenly** | 「works around this via app-switching」。 | https://github.com/my-monkeys/OpenSuperWhisper/issues/52 |
| **Typeless** | GitHub issue 描述其 macOS 用 Accessibility API 找焦點欄位、iOS 以 keyboard extension 形式提供；細節未取得。 | GitHub issue 搜尋結果（多筆，描述一致） |
| **Aqua Voice** | 未取得 iOS 證據（官網被阻擋）；列為未解問題。 | — |
| **LocalWhisper (iOS)** | 主 app 背景持有 mic session；使用者回報「Dynamic Island 麥克風指示一直亮著，直到關閉主 app」（iPhone 15 Pro, iOS 26.5）。證明主 app 背景錄音模式的副作用。 | https://github.com/kevn-m/localwhisper-support/issues/1 |
| **Dictus (開源, MIT)** | 一手原始碼，見第 4 節。 | https://github.com/getdictus/dictus-ios |
| **OpenSuperWhisper iOS 提案** | 把 **App Intents** 當主要入口（Action Button / Control Center / Back Tap / Siri / Spotlight），鍵盤 extension 為輔。 | https://github.com/my-monkeys/OpenSuperWhisper/issues/52 |

UX 摩擦點（多個專案一致）：
1. 加鍵盤 + 開 Full Access 的系統警告（「The keyboard can transmit anything you type…」）被形容為「genuinely scary warning… where keyboards lose users」。https://github.com/jkishaba-creator/bobby-speak/issues/8 、https://github.com/ferraroroberto/voice-transcriber/issues/7
2. 每次冷啟動要切到主 app 再滑回來；無公開 API 可自動返回（Dictus 試過 `canOpenURL` 列舉已知 scheme、讀 host bundle ID、模擬手勢，全部失敗或需私有 API）。https://github.com/getdictus/dictus-ios/issues/23
3. 背景 session 會被 iOS 中斷/暫停（VoiceInk：「session dies between conversations — must press Start every time」）。https://github.com/Beingpax/VoiceInk-iOS/issues/3
4. 冷啟動切換期間鍵盤 extension 可能「失去所有 live `KeyboardViewController` 達 10 秒」，畫面凍結。https://github.com/getdictus/dictus-ios/issues/281

---

## 4. 一手案例拆解：Dictus iOS 的資料流（可直接參考的實作）

Dictus 三個 target：`DictusApp`（錄音、模型、設定）、`DictusKeyboard`（UI + 觸發 + 插字）、`DictusCore`（App Group、共享 keys）。來源：https://github.com/getdictus/dictus-ios

**主 app 端（`DictusApp/Audio/UnifiedAudioEngine.swift`）**
- `AVAudioSession.setCategory(.playAndRecord, options: [.allowBluetoothA2DP, .defaultToSpeaker, .duckOthers])`；註解：「iOS forbids changing AVAudioSession category from background」→ 類別必須在前景設定一次；「iOS interrupts the audio session when the app goes to background」→ 需反覆 `setActive(true)`。
- `UIBackgroundModes: audio` 讓 app 在背景持續跑 `AVAudioEngine`；input tap 取硬體原生格式（通常 48 kHz）轉成 16 kHz mono Float32 餵 WhisperKit/Parakeet；引擎常駐但以 `isRecording` 閘控是否累積樣本（避免「64M idle sample accumulation bug」）。
- 冷啟動：鍵盤以 `dictus://…?source=keyboard` 開 app；app 在 `scene(_:willConnectTo:options:)` 搶先讀 launch URL 以免首幀閃出主畫面（`ColdStartLaunch.swift`）；因「iOS forbids `AVAudioEngine.start()` from non-active state」，app 把請求「park」起來，進入 active 後再啟動，並持有 `UIBackgroundTaskIdentifier` 直到真正開始錄音（`ColdStartResolutionPolicy.swift`、`DictationCoordinator.swift`）。
- `LiveActivityManager.swift`：app 進背景即啟動 Live Activity（Dynamic Island 顯示「ready to record」），錄音中斷（來電/Siri）或閒置釋放時結束，避免「8 小時幽靈 pill」。

**鍵盤端（`DictusKeyboard/KeyboardState.swift`）**
- 請求：寫 App Group `UserDefaults`（`dictationStatus = .requested`、`stopRequested` 等）+ `DarwinNotificationCenter.post(...)`；若 app ~500 ms 無回應才 `extensionContext.open(url)` 冷啟動。
- 接收：監聽 Darwin notification `transcriptionReady` → 讀 App Group 的 `lastTranscription` → `controller?.textDocumentProxy.insertText(transcription)` + 觸覺回饋。
- Handoff keys（`DictationHandoff.swift`）：`lastTranscription`、`lastTranscriptionPolicy`（JSON 快照，避免轉錄與潤飾語言不一致）、`handoffToken`（UUID）、`dictationStatus`（idle/recording/processing/ready）；原則「raw transcription is durable before any generation starts」（鍵盤被殺也不丟字）。
- 冷啟動回來的 watchdog grace period 15 s（平時 5 s）。
- 私有 API 風險：為了知道 host app 是誰（以便自動跳回），swizzle `_UIKeyboardArbiterClient +enabled` 並讀 `_hostProcessIdentifier`（`HostArbiterActivation.m`、`HostAppResolver.swift`），作者自述「the keyboard extension launching is the most fragile path in this product」。**我們不建議採用。**

---

## 5. iOS 26 的裝置端 AI 能力

### 5.1 SpeechAnalyzer / SpeechTranscriber / DictationTranscriber（iOS 26.0+）

- `SpeechAnalyzer` 為 actor，以 `AsyncSequence` 餵 `AnalyzerInput`，模組 `SpeechTranscriber` 回傳 `results` 非同步序列（含 `volatileResults` 即時中間結果、`audioTimeRange` 屬性）。https://developer.apple.com/documentation/speech/speechanalyzer 、https://developer.apple.com/documentation/speech/speechtranscriber
- WWDC25 Session 277：完全裝置端；「The model is retained in system storage and does not increase the download or storage size of your application, nor does it increase the run-time memory… It operates outside of your application's memory space」；長語音、遠場、低延遲即時轉錄；不需使用者去設定開啟 Siri/聽寫。https://developer.apple.com/videos/play/wwdc2025/277/
- 模型資產經 `AssetInventory.assetInstallationRequest(supporting:)` → `downloadAndInstall()` 下載，系統管理、跨 app 共享；每個 app 有 `maximumReservedLocales` 配額，需 `reserve(locale:)` / `release(reservedLocale:)`。https://developer.apple.com/documentation/speech/assetinventory
- **支援語言（實機查詢 `SpeechTranscriber.supportedLocales`，macOS 26.5.2 build 25F84，30 個）**：de-AT de-CH de-DE en-AU en-CA en-GB en-IE en-IN en-NZ en-SG en-US en-ZA es-CL es-ES es-MX es-US fr-BE fr-CA fr-CH fr-FR it-CH it-IT **ja-JP ko-KR** pt-BR pt-PT **yue-CN zh-CN zh-HK zh-TW**。https://github.com/bitwize-ai/Logue/issues/41 （iOS 端清單應相同但建議上線前以 `supportedLocales` 實測）
- `DictationTranscriber`：給舊裝置/不支援語言的後備，使用與系統聽寫/`SFSpeechRecognizer` 相同的裝置端模型，「does not support languages or locales that SFSpeechRecognizer only supports via network access」。https://developer.apple.com/documentation/speech/dictationtranscriber
- 舊 API `SFSpeechRecognizer`（iOS 10–18 的選項）：伺服器辨識「stops speech recognition tasks that last longer than one minute」、每裝置每日次數限制、各 app 可能被全域節流；`supportsOnDeviceRecognition` 視 locale 而定。https://developer.apple.com/documentation/speech/sfspeechrecognizer
- 是否可在 extension 使用：官方文件未提。因建議架構由主 app 錄音與辨識，此點影響小。

### 5.2 Foundation Models（裝置端 LLM，iOS 26.0+）

- `SystemLanguageModel.default` → `LanguageModelSession(instructions:)` → `respond(to:)` / `streamResponse`；`@Generable` 結構化輸出；`prewarm()` 預載。https://developer.apple.com/documentation/foundationmodels/languagemodelsession
- **Context window 4,096 tokens**（instructions + 所有 prompt + 輸出合計）；「~3-4 characters = 1 token (English)… ~1 character = 1 token (Japanese, Chinese, Korean)」；超過丟 `contextSizeExceeded`。https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models
- 可用性：`availability` 可能回 `.unavailable(.deviceNotEligible)` / `.modelNotReady`；`supportedLanguages` / `supportsLocale(_:)` / `contextSize` 可在執行期查詢。https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel
- 文件頁列出的語言包含 zh-CN 但**未見 zh-TW**；繁中/台灣用語品質需實測。支援機型需支援 Apple Intelligence（本次無法讀取 Apple 機型清單頁；一般認知為 iPhone 15 Pro 以上，請上線前確認）。
- 可否在 extension 使用：無官方說明；且 4 K context 對「潤飾一段口述」足夠（中文約 2–3 千字的輸入+輸出），但做長文改寫需分段。

### 5.3 第三方裝置端 ASR（在主 app 內跑）

| 方案 | 數據 | 來源 |
|---|---|---|
| whisper.cpp | 模型/RAM：tiny 75 MB / ~273 MB；base 142 MB / ~388 MB；small 466 MB / ~852 MB；medium 1.5 GB / ~2.1 GB；Core ML encoder 在 ANE 上「more than x3 faster」；有 whisper.objc / whisper.swiftui 範例（iPhone 13 即時）。 | https://github.com/ggml-org/whisper.cpp |
| WhisperKit（Argmax OSS SDK，MIT） | 建議「large-v3-v20240930_626MB for maximum multilingual accuracy, tiny for fastest debugging」；SPM `argmax-oss-swift` 1.x；需 Xcode 16+；有 VAD 分段與增量載入降低峰值記憶體。Dictus 以 tiny/base/small 在 iPhone 12 (A14) 以上運行。 | https://github.com/argmaxinc/WhisperKit 、https://github.com/getdictus/dictus-ios |
| sherpa-onnx（Apache-2.0） | 串流 zipformer 中英雙語：`small-bilingual-zh-en` encoder fp32 85 MB / int8 41 MB；`zh-14M` int8 encoder 21 MB；`streaming-zipformer-zh-int8-2025-06-30` 154 MB；另有 SenseVoice（zh/yue/en/ko/ja）。提供 iOS Swift SPM 與 SwiftUI 範例。 | https://github.com/k2-fsa/sherpa-onnx 、https://github.com/k2-fsa/sherpa/blob/master/docs/source/onnx/pretrained_models/online-transducer/zipformer-transducer-models.rst |

對繁中使用者：iOS 26 `SpeechTranscriber`（zh-TW 原生、零記憶體負擔）是首選；iOS 17/18 後備可用 sherpa-onnx 小型中英串流模型（< 50 MB）或雲端。

---

## 6. 不經鍵盤的入口：App Intents / Controls / Live Activity

- iOS 18 **Controls**（WidgetKit `ControlWidgetButton`/`Toggle`）可放在 Control Center、鎖定畫面與 **Action Button**；用 `OpenIntent` 可開 app，或讓 intent 在背景執行。https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system
- `AudioRecordingIntent`（iOS 18+）：宣告 app 會錄音、系統顯示錄音指示；**在 iOS 上必須同時啟動 Live Activity，否則錄音會被停止**。這是「按 Action Button 直接開始錄音、不必開 app 畫面」的官方路徑。https://developer.apple.com/documentation/appintents/audiorecordingintent
- `UIBackgroundModes: audio` 官方描述為「play audible content in the background」，但實務（Dictus、foil 提案、LocalWhisper）皆用它維持背景錄音；需在前景先把 `AVAudioSession` 設成 `.playAndRecord` 並 `setActive(true)`。https://developer.apple.com/documentation/xcode/configuring-background-execution-modes
- 用法建議：Action Button / Control Center 啟動「錄音 session」（Live Activity 顯示狀態、可從 Dynamic Island 停止），鍵盤只需負責把結果插進欄位。這與 Wispr 的 Flow Session 等價，但少一次 app 切換（session 已在背景時，鍵盤的麥克風鍵只需寫 App Group + Darwin notification，不必開 app）。

---

## 7. App Store 審查與隱私

- Guideline 4.4.1 鍵盤必須：提供鍵入功能、提供切換下一個鍵盤的方法、「**Remain functional without full network access and without requiring full access**」、只為了鍵盤功能蒐集活動；不得「Launch other apps besides Settings」、不得改變按鍵用途。https://developer.apple.com/app-store/review/guidelines/
  - 意涵：鍵盤在未開 Full Access 時仍要能打字（至少 QWERTY 或注音/英文基本鍵盤），且最好連「插入辨識結果」也不依賴 Full Access（App Group **讀取**不需 Full Access）。
- Apple 對開放存取鍵盤的要求：「do not store received keystroke or voice data beyond the time needed to provide text back to the user or to provide features that you explain to the user」。https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard
- App Privacy Details：「Collect」定義為把資料傳離裝置且保留超過即時服務所需；純裝置端處理不算蒐集；若把音訊/文字送到自家伺服器必須在 nutrition label 揭露（Audio Data、Other User Content），且必須提供隱私政策 URL。https://developer.apple.com/app-store/app-privacy-details/
- 兩個 target 都要有 `PrivacyInfo.xcprivacy`（Dictus 專案中 app 與 keyboard 各一份）。
- 送審備註建議：解釋 (a) 為何需要 Full Access（網路/雲端辨識、App Group 寫入），(b) 鍵盤為何會開啟自己的 containing app（Apple 禁止 extension 使用麥克風），並附上無 Full Access 的功能示範。

---

## 8. 技術選型：Swift vs Flutter vs React Native vs KMP

- **Keyboard extension 必須是 Swift/ObjC 原生**：記憶體 30–60 MB 的實測上限，無法承受 Flutter engine / JS runtime（開源專案回報「Loading the full Flutter Engine inside an app extension is very heavy」https://github.com/mrdeephang/Kirat-Script/issues/7 ；Flutter 官方「iOS app extensions」頁本次無法讀取，請自行確認其對有記憶體上限之 extension 的警告）。KMP 可編成原生 framework 但 Kotlin/Native runtime 仍增加 footprint，且 UIKit/`UITextDocumentProxy` 互動全是 Swift，收益極低。
- **主 app**：SwiftUI 原生最省事（`SpeechAnalyzer`、`FoundationModels`、`ActivityKit`、`AppIntents` 都是 Swift-only 的現代 API，無跨平台綁定）。若桌面端已用 Flutter/RN/Tauri，iOS 建議仍以 Swift 寫 app 殼與所有系統整合，只把「設定頁/帳號」等共用畫面做成跨平台模組（add-to-app）；或乾脆共用的是後端與潤飾 prompt，而非 UI。

---

## 9. 程式片段

### 9.1 鍵盤 extension：麥克風鍵、讀 App Group、Darwin notification、插字

```swift
// KeyboardViewController.swift（DictationKeyboard target）
import UIKit

let appGroupID = "group.com.yourco.typeless"
let transcriptionReadyName = "com.yourco.typeless.transcriptionReady" as CFString

final class KeyboardViewController: UIInputViewController {
    private let defaults = UserDefaults(suiteName: appGroupID)!
    private var micButton = UIButton(type: .system)
    private var nextKeyboardButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        // 4.4.1：必須提供切換鍵盤的方法（Face ID 機型 needsInputModeSwitchKey == false 時系統自己畫）
        nextKeyboardButton.setImage(UIImage(systemName: "globe"), for: .normal)
        nextKeyboardButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        nextKeyboardButton.isHidden = !needsInputModeSwitchKey

        micButton.setImage(UIImage(systemName: "mic.fill"), for: .normal)
        micButton.addTarget(self, action: #selector(micTapped), for: .touchUpInside)
        // ...layout 略；view.heightAnchor 可自訂鍵盤高度

        // 跨 process 通知：主 app 寫完結果後 post；不帶 payload，資料走 App Group
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(center, Unmanaged.passUnretained(self).toOpaque(), { _, observer, _, _, _ in
            guard let observer else { return }
            let me = Unmanaged<KeyboardViewController>.fromOpaque(observer).takeUnretainedValue()
            DispatchQueue.main.async { me.insertPendingTranscription() }
        }, transcriptionReadyName, nil, .deliverImmediately)
    }

    @objc private func micTapped() {
        // 1) 若主 app 的錄音 session 已在背景存活：只寫狀態 + 通知（需 Full Access 才能寫 App Group）
        if hasFullAccess, defaults.bool(forKey: "sessionAlive") {
            defaults.set("requested", forKey: "dictationStatus")
            defaults.set(Date().timeIntervalSince1970, forKey: "requestedAt")
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                CFNotificationName("com.yourco.typeless.startRequested" as CFString), nil, nil, true)
            return
        }
        // 2) 冷啟動：開主 app（Dictus 實測 extensionContext.open 在 iOS 18 仍可用；SwiftUI openURL 可能靜默失敗）
        var comps = URLComponents(string: "typeless://dictate")!
        comps.queryItems = [URLQueryItem(name: "source", value: "keyboard")]
        extensionContext?.open(comps.url!) { ok in
            if !ok { /* 顯示「請先開啟 Typeless app」提示 */ }
        }
    }

    private func insertPendingTranscription() {
        // App Group 讀取不需 Full Access；用 token 去重，避免重複插入
        guard let text = defaults.string(forKey: "lastTranscription"),
              let token = defaults.string(forKey: "handoffToken"),
              token != defaults.string(forKey: "lastInsertedToken") else { return }
        let proxy = textDocumentProxy
        // 根據前文決定是否補空白（中文不補，英文補）
        if let before = proxy.documentContextBeforeInput, let last = before.last,
           !last.isWhitespace, last.isASCII, text.first?.isASCII == true {
            proxy.insertText(" ")
        }
        proxy.insertText(text)
        if hasFullAccess { defaults.set(token, forKey: "lastInsertedToken") }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        // textInput 永遠為 nil；可在此用 documentContextBeforeInput 更新上下文供潤飾使用
        let ctx = textDocumentProxy.documentContextBeforeInput ?? ""
        if hasFullAccess { defaults.set(String(ctx.suffix(300)), forKey: "hostContextBefore") }
    }
}
```

Info.plist（extension）：`NSExtension > NSExtensionAttributes > RequestsOpenAccess = true`、`PrimaryLanguage = zh-Hant`（或 `en-US`）、`IsASCIICapable`。兩個 target 都加 App Groups entitlement（`group.com.yourco.typeless`）。

### 9.2 主 app：背景錄音 + iOS 26 SpeechTranscriber 串流 + 回寫 App Group

```swift
import AVFoundation
import Speech          // iOS 26: SpeechAnalyzer / SpeechTranscriber
import FoundationModels

@MainActor
final class DictationSession {
    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private let defaults = UserDefaults(suiteName: appGroupID)!

    func configureAudioSessionInForeground() throws {
        // 類別必須在前景設定（背景改 category 會失敗）；UIBackgroundModes 需含 "audio"
        let s = AVAudioSession.sharedInstance()
        try s.setCategory(.playAndRecord, mode: .default,
                          options: [.allowBluetoothA2DP, .defaultToSpeaker, .duckOthers])
        try s.setActive(true)
    }

    func start(locale: Locale = Locale(identifier: "zh-TW")) async throws {
        guard SpeechTranscriber.isAvailable else { throw NSError(domain: "asr", code: 1) } // 否則退回 DictationTranscriber / 雲端
        let t = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                  reportingOptions: [.volatileResults], attributeOptions: [])
        if let req = try await AssetInventory.assetInstallationRequest(supporting: [t]) {
            try await req.downloadAndInstall()          // 首次需下載語言資產（系統空間）
        }
        let a = SpeechAnalyzer(modules: [t])
        let fmt = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [t])
        let (stream, builder) = AsyncStream<AnalyzerInput>.makeStream()
        inputBuilder = builder
        try await a.start(inputSequence: stream)
        analyzer = a; transcriber = t

        let input = engine.inputNode
        let hw = input.outputFormat(forBus: 0)
        let conv = AVAudioConverter(from: hw, to: fmt!)!
        input.installTap(onBus: 0, bufferSize: 4096, format: hw) { [weak self] buf, _ in
            let out = AVAudioPCMBuffer(pcmFormat: fmt!, frameCapacity: AVAudioFrameCount(fmt!.sampleRate * 0.1))!
            var err: NSError?
            conv.convert(to: out, error: &err) { _, status in status.pointee = .haveData; return buf }
            self?.inputBuilder?.yield(AnalyzerInput(buffer: out))
        }
        try engine.start()
        defaults.set("recording", forKey: "dictationStatus")

        Task {
            var finalText = ""
            for try await r in t.results {                       // r.isFinal 區分 volatile / final
                if r.isFinal { finalText += String(r.text.characters) }
            }
            await self.finish(raw: finalText)
        }
    }

    func stop() async throws {
        engine.inputNode.removeTap(onBus: 0); engine.stop()
        inputBuilder?.finish()
        try await analyzer?.finalizeAndFinishThroughEndOfInput()
    }

    private func finish(raw: String) async {
        // 原則：先把 raw 寫入 App Group（durable），再做 LLM 潤飾
        let token = UUID().uuidString
        defaults.set(raw, forKey: "lastTranscriptionRaw")
        defaults.set(token, forKey: "handoffToken")

        var polished = raw
        if SystemLanguageModel.default.isAvailable {            // iOS 26 + Apple Intelligence 機型
            let ctx = defaults.string(forKey: "hostContextBefore") ?? ""
            let session = LanguageModelSession(instructions: """
            你是聽寫潤飾器。移除贅字與口語停頓、加上標點、保留原意與語言（繁體中文/英文混用照舊）。
            只輸出潤飾後的文字。前文：\(ctx.suffix(200))
            """)
            if let r = try? await session.respond(to: raw) { polished = r.content }  // 注意 4096 token 上限
        } else {
            // 退回自家雲端 LLM
        }
        defaults.set(polished, forKey: "lastTranscription")
        defaults.set("ready", forKey: "dictationStatus")
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(transcriptionReadyName), nil, nil, true)
    }
}
```

主 app 另需：`NSMicrophoneUsageDescription`、`NSSpeechRecognitionUsageDescription`（若用 SFSpeechRecognizer）、`UIBackgroundModes = [audio]`、URL scheme `typeless`、`onOpenURL` 處理 `source=keyboard` 並顯示「滑回原 app」全螢幕引導、`ActivityKit` Live Activity（錄音中/待命），以及 `AudioRecordingIntent` + `ControlWidget` 供 Action Button / Control Center 使用。

---

## 10. 對我們的設計意涵

1. **鍵盤 = thin client，主 app = 引擎。** 鍵盤 extension 只做：QWERTY/注音基本輸入（滿足 4.4.1）、麥克風鍵、狀態顯示（錄音中/處理中）、`insertText`、少量上下文回報。目標常駐 < 30 MB、峰值 < 45 MB；不載入任何 ML 模型、不引入 Flutter/RN。
2. **UX 一定要為「切換 app」設計**：首次（或 session 失效後）按麥克風 → 開主 app → 全螢幕「向左滑回去」動畫 → Live Activity 顯示錄音中 → 回到原 app 時鍵盤已顯示波形/「聆聽中」。不要嘗試自動跳回（需私有 API，Dictus 自述為「most fragile path」，KeyboardKit 因此被拒過）。
3. **用 Flow Session 降低切換頻率**：session 存活期間（例如 5 分鐘、可設定），鍵盤麥克風鍵只需寫 App Group + Darwin notification，不必再開 app。要處理：iOS 暫停主 app 後 session 其實已死但狀態仍寫著 alive（VoiceInk 的 bug）→ 以 heartbeat 時間戳判定，過期就走冷啟動。
4. **提供 Action Button / Control Center 入口**（`AudioRecordingIntent` + `ControlWidget` + Live Activity）作為「不用換鍵盤也能用」的主要路徑：對 iPhone 15 Pro 以上使用者摩擦最低，也能服務不願裝第三方鍵盤的人（結果可複製到剪貼簿或由 Live Activity 一鍵插入自家 app）。
5. **ASR 分層**：iOS 26 + 支援機型 → `SpeechTranscriber`（zh-TW/yue/en 裝置端、零 app 記憶體）；iOS 17/18 → 自家雲端串流 ASR（或 sherpa-onnx 小模型離線後備）；`DictationTranscriber` 作為第三層。LLM 潤飾：Foundation Models（4 K tokens，中文 1 字 1 token → 單段口述夠用；注意 zh-TW 未在文件語言清單）→ 雲端 LLM 後備。
6. **Full Access 策略**：預設不要求。無 Full Access 時鍵盤仍可：打字、開主 app 冷啟動、**讀取** App Group 取得結果並插字（需驗證 Darwin notification 在無 Full Access 下可收）。開 Full Access 才解鎖：鍵盤直接寫狀態（免開 app 的 session 續用）、雲端辨識、上下文回報。Onboarding 要在跳 Settings 前先解釋那段系統警告。
7. **隱私標籤與送審**：若音訊上雲必須標 Audio Data/Other User Content；兩個 target 各放 `PrivacyInfo.xcprivacy`；送審備註說明「extension 無麥克風權限，故需開啟 containing app」。
8. **可觀測性**：鍵盤 extension 被殺沒有 crash log，必須自行在 App Group 寫 footprint/生命週期事件（Dictus 的 `KeyboardLifecycleProbe`、`AppGroupDiagnostic` 做法）。
9. **桌機/手機共用的部分**：後端 ASR/LLM 服務、潤飾 prompt、字典/快捷片語同步（iCloud 或自家帳號）、設定模型；UI 與系統整合各平台原生。

---

## 11. 未解問題

1. **Full Access 以外的 IPC**：無 Full Access 的鍵盤能否成功 `CFNotificationCenterPostNotification`（Darwin）與 `extensionContext.open`？需實機驗證（文獻只確認 App Group 寫入需 Full Access）。
2. **背景錄音的真實存活時間**：`UIBackgroundModes: audio` 的 session 在 iOS 26 於不同情境（來電、Siri、其他 app 播放、低電量）會被中斷多久；Wispr「5 分鐘預設」是產品設定還是系統限制？
3. **`SpeechTranscriber` 在 iPhone 上的 zh-TW 清單與硬體門檻**：30 locale 清單來自 macOS 26.5.2，iOS 需實測；WWDC 僅說「certain hardware requirements」。
4. **Foundation Models 對繁體中文/台灣用語的品質與 zh-TW 支援**：文件語言清單只有 zh-CN；需用 `supportsLocale(Locale(identifier: "zh-TW"))` 實測，並評估潤飾品質。
5. **Foundation Models / SpeechAnalyzer 能否在 extension 內呼叫**：官方未說明；若未來想讓鍵盤直接潤飾文字（如 Dictus 讓鍵盤在前景跑 polish），需驗證記憶體與可用性。
6. **冷啟動期間鍵盤 controller 消失 ~10 秒**（Dictus #281）的根因與規避方法。
7. **4.4.1「不得啟動其他 app」對開啟 containing app 的實際審查尺度**：目前靠市場先例，建議首次送審前以 TestFlight + App Review 的 Expedited 問答確認。
8. **Aqua Voice、Typeless、Willow 的 iOS 實作細節與定價**：官網不可達，本報告未能驗證；Wispr Flow iOS 的免費額度/價格亦未取得。
9. **WhisperKit / sherpa-onnx 在 iPhone 15/16 的實際延遲與 RTF**：本次未能讀取 benchmark 頁，需自行量測後再決定 iOS 17/18 後備方案是否走裝置端。
