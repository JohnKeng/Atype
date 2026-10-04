# macOS 桌面端（選單列 App）技術研究：語音聽寫 App 的文字注入、權限、全域熱鍵、音訊、UI 與框架選擇

研究日期：2026-10-01。
主要證據來源：四個開源專案的**原始碼**（都在 2026-09-28 ~ 2026-10-01 之間 clone 的最新 main）：

| 專案 | 技術棧 | 版本/commit | 連結 |
|---|---|---|---|
| Handy | Tauri 2 (Rust + React) | v0.9.7, commit `29bd2c0` (2026-09-28) | https://github.com/cjpais/Handy |
| handy-keys（Handy 的熱鍵函式庫） | Rust crate 0.3.4 | main | https://github.com/handy-computer/handy-keys |
| VoiceInk | 原生 Swift/SwiftUI | commit `c09cc1f` (2026-10-01) | https://github.com/Beingpax/VoiceInk |
| Whispering（epicenter monorepo） | Tauri 2 (Rust + Svelte) | commit `f9441c8` (2026-09-29) | https://github.com/epicenter-md/epicenter |
| VoiceVoice | 原生 Swift (SwiftPM) | commit `79a5320` (2026-09-30) | https://github.com/sergekruf/voicevoice |

加上 Apple 官方文件與各 crate/套件的 README。**Superwhisper、Wispr Flow、Typeless 官網在本次環境被 egress proxy 擋住，無法讀取第一手資料；Superwhisper 為閉源**，以下凡提到它們的行為都標註為「未驗證」。

---

## 0. 執行摘要

1. **文字注入沒有銀彈，業界共識是「剪貼簿 + 模擬 ⌘V」為主路徑**，再以 AppleScript（System Events）與 AXUIElement 直接寫入當備援。四個開源專案全部以 ⌘V 為第一層：VoiceInk 用 `CGEvent` 4 連發（`privateState`、10 ms 間隔）；Handy / Whispering 用 Rust `enigo` 送 `Key::Meta + keycode 9`；VoiceVoice 做三層瀑布（CGEvent → AppleScript → AX）。`CGEventKeyboardSetUnicodeString` 直接打字（enigo `.text()`）有 20 字元上限、每事件 20 ms，而且 Apple 文件明說「應用框架可能忽略事件裡的 Unicode 字串」，所以只適合當備援。
2. **剪貼簿還原是最大坑**：固定延遲會跟目標 App 讀剪貼簿的時機競速（Handy issue #502）。Handy 0.9.x 已實作「收據式」還原：用 `declareTypes:owner:` 放 promise，等 AppKit 回呼 `pasteboard:provideDataForType:` 才算被讀走，再以 `changeCount` 守衛還原。另外要寫入 `org.nspasteboard.TransientType / ConcealedType` 標記讓 Maccy 等剪貼簿管理器略過。
3. **權限**：最低需要 Microphone（`AVCaptureDevice.requestAccess`，Info.plist 必須有 `NSMicrophoneUsageDescription` 否則直接 crash）與 Accessibility（`AXIsProcessTrustedWithOptions` + `kAXTrustedCheckOptionPrompt`）。Input Monitoring（`CGRequestListenEventAccess`）四個專案都沒要求。**重大陷阱**：重新 build / 改簽章後 `AXIsProcessTrusted()` 會回 true 但事件 tap 其實已死、⌘V 靜默失敗——Whispering 為此專門養一條「活著的 CGEventTap」當 oracle，VoiceVoice 用 `NSEvent.addGlobalMonitorForEvents` 回傳 nil 來偵測。
4. **Mac App Store 基本不可行**：MAS 強制 App Sandbox；四個專案全部 `com.apple.security.app-sandbox = false`，走 Developer ID + Hardened Runtime + notarization 直接發布（Handy CI 用 `Developer ID Application` 憑證簽章）。
5. **Fn/🌐 鍵**：透過 `CGEventTap` 或 `NSEvent` 的 `flagsChanged`，keycode `0x3F (63)` 搭配 `CGEventFlags.maskSecondaryFn` / `NSEvent.ModifierFlags.function`。只需 Accessibility。但 (a) 第三方鍵盤的 Fn 不會送任何事件（Apple 專屬 HID usage，Handy README）；(b) 系統「按下 🌐 鍵時：開始聽寫」會先攔走 Fn（`com.apple.HIToolbox` 的 `AppleFnUsageType == 3`），必須請使用者改成「不執行任何操作」；(c) Carbon `RegisterEventHotKey`（Tauri global-shortcut / KeyboardShortcuts 套件）**不支援 Fn 與純修飾鍵**，但它免權限、Sandbox 可用、而且不受 Secure Input 影響——Handy 拿它做 Secure Input 時的備援。
6. **Secure Input**（密碼欄、Terminal「安全鍵盤輸入」）會讓 CGEventTap 收不到 KeyDown/KeyUp，但 FlagsChanged 照常流動（Handy 實測），因此「純修飾鍵 / Fn 按住說話」的熱鍵在 Secure Input 下仍可用。
7. **音訊**：三種做法都可達 16 kHz mono：VoiceInk 用 AUHAL AudioUnit 指定裝置（不改系統預設輸入）、Handy 用 `cpal` + `rubato` 重採樣、VoiceVoice 用 `AVAudioEngine` + `AVAudioConverter` 並常駐「暖機」引擎做 0.5 秒 pre-roll。VAD 用 Silero（ONNX/CoreML，2 MB，30 ms 幀 <1 ms）或 earshot（16 ms/256 樣本，Rust 原生）。藍牙耳機麥克風會把耳機從 A2DP 切到 HFP（16 kHz mono 電話音質）——VoiceVoice 做了 `SystemInputGuard` 自動把輸入切回內建麥克風。
8. **框架選擇**：若要跨平台桌面，Handy 與 Whispering 證明 **Tauri 2 + Rust** 在 macOS 上可以做到原生等級（`tauri-nspanel` 做非激活浮動面板、`objc2` 直接呼叫 NSPasteboard、自管 CGEventTap），但 **Whispering 已在 ADR-0117 明確放棄 Fn / 純修飾鍵熱鍵**（只用 plugin chord），Handy 則自寫 `handy-keys` 來支援；兩者 Tauri 版本都是 2.11.x。原生 Swift（VoiceInk）整合度最高但不跨平台。Electron 的 `globalShortcut` 文件沒有 key-up 事件（push-to-talk 困難）；Flutter `hotkey_manager` 的 key-up 僅 macOS 支援。

---

## 1. 文字注入（Text Insertion）

### 1.1 方法總覽與各專案實作

| 方法 | 需要的權限 | 優點 | 缺點 | 誰在用 |
|---|---|---|---|---|
| 寫剪貼簿 + 模擬 ⌘V（CGEvent） | Accessibility | 幾乎所有 App 都吃、支援任何 Unicode/長文 | 污染剪貼簿、還原競速、Secure Input 下可能失效 | VoiceInk（第一層）、Handy、Whispering、VoiceVoice（第一層） |
| AppleScript `tell "System Events" to keystroke "v" using command down` | Automation（System Events）+ `NSAppleEventsUsageDescription` + `com.apple.security.automation.apple-events` | 不依賴 CGEvent 權限狀態；某些鍵盤佈局更穩 | 多一個權限提示；慢（spawn osascript ~百毫秒） | VoiceInk（可選）、VoiceVoice（第二層） |
| `CGEventKeyboardSetUnicodeString` 逐字打字 | Accessibility | 不碰剪貼簿、密碼欄可能可用 | 每事件最多 20 字元、每事件 ~20 ms、框架可忽略 Unicode 字串、Electron/終端機常忽略 | Handy「Direct」模式（enigo `.text()`） |
| `AXUIElementSetAttributeValue(kAXSelectedTextAttribute)` | Accessibility | 不碰剪貼簿、可驗證結果 | 只有原生 Cocoa 文字欄可靠；Electron/Chromium 會 crash 或無效 | VoiceVoice（第三層） |
| Input Method Kit（真正的輸入法） | 不需 Accessibility | 最「正統」，透過 `IMKInputController` 把文字交給 client | 使用者必須切換輸入來源；安裝到 `~/Library/Input Methods`；與使用者原本的注音/倉頡輸入法互斥 | 四個專案都沒用 |

Apple 對 `CGEventKeyboardSetUnicodeString` 的原文：「Application frameworks may ignore the Unicode string in a keyboard event and do their own translation based on the virtual keycode and perceived event state.」（https://developer.apple.com/documentation/coregraphics/cgevent/keyboardsetunicodestring(stringlength:unicodestring:)）。enigo 的 macOS 實作註解寫明「truncates strings down to 20 characters」，所以以 20 字元分塊、清空所有 modifier flags、post 到 `HIDEventTap`、每個事件等 20 ms（https://raw.githubusercontent.com/enigo-rs/enigo/main/src/macos/macos_impl.rs）。以 1000 字的聽寫稿計算：50 個事件 × 20 ms ≈ 1 秒，使用者會看到「逐段跳出」。

Input Method Kit 概述見 https://developer.apple.com/documentation/inputmethodkit （`IMKServer` 管連線、每個輸入 session 一個 `IMKInputController`）。它的好處是不需要任何 TCC 權限，壞處是台灣使用者會同時要用注音，切換成本高；對我們的產品更適合當「iOS/Android 的鍵盤延伸」概念，而不是 macOS 主路徑。

### 1.2 VoiceInk 的 ⌘V 實作（Swift，可直接參考）

來源：`VoiceInk/Infrastructure/SystemIntegration/Paste/CursorPaster.swift`（https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/Infrastructure/SystemIntegration/Paste/CursorPaster.swift）

```swift
// 關鍵參數（VoiceInk 實際值）
private static let prePasteDelay: TimeInterval = 0.10          // 寫入剪貼簿後等 100 ms 再送 ⌘V
private static let pasteShortcutEventDelay: TimeInterval = 0.01 // 四個事件之間各 10 ms
private static let minimumClipboardRestoreDelay: TimeInterval = 0.25 // 至少 250 ms 後才還原剪貼簿

@MainActor
private static func pasteFromClipboard() async -> PasteResult {
    guard AXIsProcessTrusted() else { return .commandNotPosted }
    let source = CGEventSource(stateID: .privateState)
    guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
          let vDown   = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
          let vUp     = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false),
          let cmdUp   = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
    else { return .commandNotPosted }
    cmdDown.flags = .maskCommand; vDown.flags = .maskCommand; vUp.flags = .maskCommand
    cmdDown.post(tap: .cghidEventTap); await wait(pasteShortcutEventDelay)
    vDown.post(tap: .cghidEventTap);   await wait(pasteShortcutEventDelay)
    vUp.post(tap: .cghidEventTap);     await wait(pasteShortcutEventDelay)
    cmdUp.post(tap: .cghidEventTap)
    return .commandPosted
}
```

細節：
- 剪貼簿寫入（`ClipboardManager.swift`）同時寫 `org.nspasteboard.source`（自己的 bundle id）、`org.nspasteboard.TransientType`、`org.nspasteboard.AutoGeneratedType`，以及自訂的 `com.VoiceInk.PasteSession`（session UUID）。還原前先驗證 `.string` 仍等於貼上的文字且 session 標記仍在，才清空並寫回快照（快照是逐 `NSPasteboardItem`、逐 type 的完整 `Data`，不是只存字串）。
- Maccy README 明列預設忽略 `org.nspasteboard.TransientType / ConcealedType / AutoGeneratedType`（https://github.com/p0deje/Maccy），Whispering 註解說 Raycast 是否遵守「未確認」。
- AppleScript 模式：對名稱以「⌘」結尾的「X – QWERTY ⌘」佈局（按住 ⌘ 時改用 QWERTY），改用 `key code 9 using command down` 而非 `keystroke "v"`，否則會打錯鍵。
- `CGEventSource(stateID: .privateState)`：Apple 文件說 private state 是獨立狀態表，適合遠端控制類程式；VoiceVoice 則選 `.hidSystemState`（「模擬實體鍵盤、不繼承本程序 modifier 狀態」）。兩者皆可；**不要用 `.combinedSessionState`**（會把使用者正按著的熱鍵 modifier 混進來）。狀態說明見 https://developer.apple.com/documentation/coregraphics/cgeventsourcestateid 。
- VoiceVoice 另外在 Fn 放開後**延遲 80 ms** 才送 ⌘V，確保 Fn 的 flagsChanged 已傳播完畢，避免目標 App 看到「Fn+⌘+V」。

### 1.3 Handy 的 Rust 實作：鍵盤佈局感知的 ⌘V + 收據式還原

**佈局問題**：Dvorak、俄文等佈局下 keycode 9 不一定是 V。Handy `src-tauri/src/input.rs` 用 Carbon `TISCopyCurrentKeyboardLayoutInputSource` + `UCKeyTranslate`（modifier state = Command）掃描 0..127 找出「按住 ⌘ 時會產生 'v'」的實體鍵，再交給 enigo `Key::Other(keycode)`；失敗才退回 ANSI 9。這段必須在主執行緒呼叫（TIS 限制）。（https://github.com/cjpais/Handy/blob/main/src-tauri/src/input.rs）

```rust
// Handy input.rs 節錄：送 Cmd+V，modifier 多按住 hold_ms（預設 100 ms）
pub fn send_paste_ctrl_v(enigo: &mut Enigo, hold_ms: u64) -> Result<(), String> {
    #[cfg(target_os = "macos")]
    let (modifier_key, v_key_code) = (Key::Meta, macos::command_v_key()); // 佈局解析後的 keycode
    enigo.key(modifier_key, Direction::Press).map_err(|e| e.to_string())?;
    enigo.key(v_key_code, Direction::Click).map_err(|e| e.to_string())?;
    std::thread::sleep(std::time::Duration::from_millis(hold_ms)); // 有些 App 用輪詢讀 modifier 狀態
    enigo.key(modifier_key, Direction::Release).map_err(|e| e.to_string())?;
    Ok(())
}
```

預設時序（`settings.rs`）：`paste_delay_ms = 60`（寫剪貼簿後等待）、`paste_delay_after_ms = 60`（貼上後等待再還原）。

**收據式還原（reliable paste，`paste_tx/mod.rs` + `paste_tx/macos.rs`，目前是 debug-gated 的 Beta）**：
- 問題描述（原文註解）：「the target application reads the clipboard whenever its event loop gets to it, so any fixed delay can lose the race and the user gets their old clipboard pasted back (#502)」。
- 做法：用 `objc2` 定義 `HandyPasteProvider : NSObject`，實作 `pasteboard:provideDataForType:`（NSPasteboardOwner 非正式協定）。以 `declareTypes:owner:` 放入 **promise**，當任何消費者真的讀取 `NSPasteboardTypeString` 時才回呼 ＝ 收據。只有「⌘V 注入之後」的收據才算數（之前的是剪貼簿管理器 / 防毒搶讀）；還原前檢查 `changeCount` 未變且未收到 `pasteboardChangedOwner:`（使用者沒有自己複製新東西）。Chromium 會「先探測再讀」多次，所以收據後還要安靜期；最後有上限 timeout，失敗模式永遠是「轉錄稿在剪貼簿多留一會兒」，絕不是「貼回舊內容」。
- Windows 端對應做法：`SetClipboardData(CF_UNICODETEXT, NULL)` 延遲渲染 + `WM_RENDERFORMAT`——這個設計可以直接搬去我們的 Windows 版。

Whispering 的 `clipboard.rs` 用 `objc2-app-kit` 做 **全保真快照**（每個 `NSPasteboardItem` 的每個 UTI + bytes），解決「使用者剛複製一張圖片，聽寫後圖片不見」的 bug；promised/lazy 資料會被跳過（`dataForType:` 回 nil）。寫入時加 `org.nspasteboard.ConcealedType`。時序：`PRE_PASTE_SETTLE = 50 ms`、`PRE_RESTORE_SETTLE = 100 ms`（https://github.com/epicenter-md/epicenter/blob/main/apps/epicenter/src-tauri/src/delivery.rs）。

### 1.4 VoiceVoice 的三層瀑布與「焦點在哪」判斷（最細緻的參考）

`Services/TextInserter.swift`（https://github.com/sergekruf/voicevoice/blob/main/Sources/VoiceVoice/Services/TextInserter.swift）：

1. **先判斷焦點元素能否貼**：`AXUIElementCreateSystemWide()` 取 `kAXFocusedUIElementAttribute`，失敗則對前景 App 的 `AXUIElementCreateApplication(pid)` 再問一次。角色在 `AXTextField / AXTextArea / AXComboBox / AXSearchField` 或 `AXUIElementIsAttributeSettable(kAXValueAttribute)` → editable；在 `AXButton / AXImage / AXLink / AXCheckBox / AXMenu*...` 黑名單 → notEditable（只放剪貼簿、顯示提示）；其餘（AXGroup、AXWebArea、Qt/Chromium 的奇怪角色）→ axUnreadable，照樣嘗試 ⌘V。
2. **Electron 的 AX 樹預設關閉**：對前景 App 設 `AXManualAccessibility = true` 一次（Electron 官方文件說明第三方輔助工具可用此屬性開啟 AX 樹：https://raw.githubusercontent.com/electron/electron/main/docs/tutorial/accessibility.md）。開啟後 Electron 的 focused 查詢仍常常是空的，所以 VoiceVoice 從 `kAXFocusedWindowAttribute`/`kAXMainWindowAttribute` 往下走樹找 `AXFocused == true` 的文字欄，限制 3000 節點、深度 80、**150 ms deadline**（Claude 桌面版約 450 節點 ~30 ms）。Safari 的 WebArea 是懶建樹，第一次查詢會觸發建構，要等 150 ms 再查一次。
3. **判斷 App 是否 Electron/Chromium/Qt**：看 `Contents/Frameworks` 裡有沒有 `Electron Framework.framework`、`Chromium Embedded Framework.framework`、`QtCore.framework`，結果快取。
4. **Tier 1 CGEvent ⌘V** → 等 450 ms → 若能讀 `kAXValueAttribute` 就比對前後值驗證（含「貼上覆蓋選取」與「重複貼上要算出現次數」兩種邊界）。
5. **Tier 2 NSAppleScript**、**Tier 2b `/usr/bin/osascript` 子程序** → 各等 400 ms 再驗證。
6. **Tier 3 AX 直寫**：`AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute, chunk)`，每塊 2000 字元（註解：Electron 超過 2040 字元會 crash，所以 Electron 一律跳過）。Apple 文件把 `kAXSelectedTextAttribute` 列為 `{ get }`，但實務上對可編輯文字元素是可設定的（https://developer.apple.com/documentation/applicationservices/kaxselectedtextattribute）。
7. 全部失敗 → 以普通字串留在剪貼簿並提示手動 ⌘V。對 AX 不可讀的 App（Bitrix24、Slack、Termius），⌘V 送出後**不馬上還原**，先留 15 秒（`unverifiedKeepSeconds`），期間剪貼簿未被動過才還原——因為曾有使用者抱怨「聽寫完習慣性 ⌘V 又貼了第二次」。
8. 自動化權限：`AEDeterminePermissionToAutomateTarget` 在 macOS Tahoe 上不會可靠彈窗，只有真的跑一次 `NSAppleScript` 才會；錯誤碼 -1743 = 被拒。

### 1.5 哪些 App 會壞掉（整理自各專案註解與 README）

| 目標 | ⌘V | Unicode 打字 | AX 直寫 | 備註 |
|---|---|---|---|---|
| 原生 Cocoa（Notes、Mail、Xcode） | ✅ | ✅ | ✅ | 最佳情況 |
| Electron（Slack、VS Code、Cursor、Discord、Notion） | ✅ | 常忽略（Handy issue #439 討論 Direct 模式問題：https://github.com/cjpais/Handy/issues/439） | ❌ crash | AX 樹需 `AXManualAccessibility`；焦點查詢常空 |
| Chromium 瀏覽器 | ✅（會多次讀剪貼簿） | 不穩 | ❌ | 頁面 AX 樹常不開；Chrome 只露出網址列 |
| Safari/WebKit | ✅ | 不穩 | 視頁面 | AX 樹懶建，需等 150 ms |
| Terminal / iTerm / xterm.js（Termius） | ✅（Termius 的 AX 文字欄是永遠空的中介） | 常忽略 | ❌ | 驗證會失敗，但 ⌘V 其實有進去，**不要重送** |
| 密碼欄 / Secure Input | ⌘V 通常仍可（貼上是 posting 不是 listening） | 可能 | ❌ | 熱鍵的 KeyDown 會收不到，見 §2.5 |
| Java/Qt App（VoiceVoice 提到的 MAX） | ✅ | 不穩 | ❌ | AX 角色不標準（例如 AXStaticText 卻可編輯） |

一個 VoiceInk fork（https://github.com/bigloudjeff/VoiceInk-tweaks）宣稱對「阻擋剪貼簿貼上的欄位（密碼欄、某些網頁表單）」改用逐字 CGEvent 打字——這點只來自該 README，未讀其程式碼。

---

## 2. 權限與發布

### 2.1 Microphone

- `AVCaptureDevice.authorizationStatus(for: .audio)` / `requestAccess(for: .audio)`；Info.plist 沒有 `NSMicrophoneUsageDescription` 會 raise exception（https://developer.apple.com/documentation/avfoundation/avcapturedevice/requestaccess(for:completionhandler:)）。
- Hardened Runtime 下需要 entitlement `com.apple.security.device.audio-input`（https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.audio-input）。Handy 的 `Entitlements.plist` 同時放了 `device.microphone` 與 `device.audio-input`。
- 被拒後只能導到 `x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone`（VoiceVoice `SettingsView.swift`）。
- VoiceVoice 的「暖機」模式會讓 macOS 的橘色麥克風指示燈常亮（註解明說這是代價，由設定 `instantRecordStart` 控制）。

### 2.2 Accessibility

```swift
// VoiceInk OnboardingPermissionController.swift / VoiceVoice HotkeyMonitor.swift
let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
AXIsProcessTrustedWithOptions(options)   // 彈窗是非同步的，回傳值不受影響
NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
// 之後輪詢 AXIsProcessTrusted()：VoiceInk 每秒最多 60 次；Whispering supervisor 每 1 s
```

Apple 文件（macOS 10.9+）：「Prompting occurs asynchronously and does not affect the return value.」（https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions）。macOS 沒有權限變化的通知，所以每個專案都在輪詢。

**陷阱：過期授權（stale grant）**。VoiceVoice `HotkeyMonitor.canCreateEventTap()` 的註解：「Returns nil if Accessibility was actually denied by TCC for this binary (e.g. after a rebuild), even when AXIsProcessTrusted reports true.」做法是真的裝一個 `NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged)`，拿到 nil 就代表實際被拒。Whispering ADR-0117 說得更直白：「a stale post-update Accessibility grant reads as trusted through AXIsProcessTrusted yet silently drops the synthetic ⌘V」，所以 Rust 端養一條 `ListenOnly` 的 CGEventTap 純粹當活性探針，tap 死掉（在仍回 trusted 的情況下）就把 `DictationCapability` 標為 `Broken`，`write_text` 改走「留在剪貼簿」路徑（https://github.com/epicenter-md/epicenter/blob/main/docs/adr/0117-global-shortcut-input-is-plugin-chords-only-and-the-macos-tap-is-just-the-paste-grant-watcher.md）。開發期每次 Xcode 重 build 都會踩到，**用穩定的 Developer ID 簽章（而不是 ad-hoc `-`）可大幅減少**。

### 2.3 Input Monitoring

- API：`CGPreflightListenEventAccess()` 檢查、`CGRequestListenEventAccess()` 請求（macOS 10.15+），另有 `CGRequestPostEventAccess()` 針對「送出事件」（https://developer.apple.com/documentation/coregraphics/cgrequestlisteneventaccess()）。
- `CGEvent.tapCreate` 文件：event tap 收得到 key up/down 的條件是「process 以 root 執行」或「已啟用輔助使用（Accessibility）」（https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)）。
- 實務：VoiceInk（`.defaultTap`）、handy-keys（`Default`）、Whispering（`ListenOnly`）、VoiceVoice（NSEvent monitor）**都只要求 Accessibility**，沒有一個去要 Input Monitoring；VoiceVoice 註解：「Input Monitoring is NOT required for modifier-only (.flagsChanged) global monitors」。Tauri 生態有 `tauri-plugin-macos-permissions`（提供 `check/requestInputMonitoringPermission` 等六組 API，https://github.com/ayangweb/tauri-plugin-macos-permissions）備用。
- 開放問題：macOS 26 上純 `listenOnly` 的鍵盤 tap 是否會被歸到 Input Monitoring 而非 Accessibility，需實機驗證（Whispering 的 ListenOnly tap 是以 `AXIsProcessTrusted` 當前置條件）。

### 2.4 Sandbox、Mac App Store 與直接發布

- Apple：「To distribute a macOS app through the Mac App Store, you must enable the App Sandbox capability.」（https://developer.apple.com/documentation/security/app-sandbox）
- 四個專案的 entitlements 全部是非 sandbox：VoiceInk `VoiceInk.entitlements` 明寫 `com.apple.security.app-sandbox = false`，並開 `automation.apple-events`、`device.audio-input`、`screen-capture`、`network.client`；Handy `tauri.conf.json` 設 `hardenedRuntime: true`、`minimumSystemVersion: 10.15`，CI 用「Developer ID Application」憑證簽章（`.github/workflows/build.yml`）。
- Hardened Runtime 是 notarization 的必要條件；流程 Developer ID → Hardened Runtime → codesign → `notarytool` 提交 → `xcrun stapler staple`（https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution 、https://developer.apple.com/documentation/security/hardened-runtime）。AppleScript 路徑需要 entitlement `com.apple.security.automation.apple-events`（https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events）。
- 可 Sandbox 的部分：Carbon `RegisterEventHotKey` 熱鍵（sindresorhus/KeyboardShortcuts 自述「fully sandboxed and Mac App Store compatible」，https://github.com/sindresorhus/KeyboardShortcuts）；Sparkle 2 支援 sandbox。
- 本次**沒有**抓到 Apple 第一手文件明寫「sandbox 禁止 AX 控制其他 App / CGEventPost」（archive 頁面只回傳標題）；但結論與所有參考專案一致：**要做「貼到前景 App」就不要走 MAS**。
- Apple Developer Program 內含 Developer ID 憑證與 notarization（https://developer.apple.com/support/compare-memberships/ ；年費頁面本次未抓到，一般為 USD 99/年，標為未驗證）。

### 2.5 Secure Input（密碼欄、Terminal 安全鍵盤輸入）

- Apple TN2150：啟用後系統阻擋鍵盤事件到達任何攔截程序，包括 CGEvent event taps；若某程序在背景忘了關，會持續封鎖全系統（https://developer.apple.com/library/archive/technotes/tn2150/_index.html）。
- Handy `secure_input.rs` 的實測（註解）：「CGEventTaps stop receiving KeyDown/KeyUp events while FlagsChanged still flows」→ Option+Space 這類有主鍵的熱鍵靜默失效，純修飾鍵熱鍵照常。對策：每 1 秒輪詢 Carbon `IsSecureEventInputEnabled()`，持續 3 秒才視為「卡住」；卡住期間把有主鍵的綁定**影子註冊到 Tauri global-shortcut（Carbon）**，因為 Carbon 熱鍵不受 Secure Input 影響；用 `ioreg -l -w 0` 找 `kCGSSessionSecureInputPID` 猜肇事程序（Apple 無可靠 API，常指到父程序或 loginwindow）；錄製新熱鍵時若 Secure Input 中則拒絕並顯示橫幅（https://github.com/cjpais/Handy/blob/main/src-tauri/src/secure_input.rs）。

---

## 3. 全域熱鍵與 Fn/🌐 鍵

### 3.1 三種機制比較

| 機制 | 權限 | Press/Release | 純修飾鍵 | Fn | 可吞掉事件 | Sandbox | Secure Input 影響 |
|---|---|---|---|---|---|---|---|
| Carbon `RegisterEventHotKey`（global-hotkey crate → tauri-plugin-global-shortcut；KeyboardShortcuts；Flutter hotkey_manager 底層 soffes/HotKey） | 無 | ✅ `kEventHotKeyPressed/Released`（https://raw.githubusercontent.com/tauri-apps/global-hotkey/dev/src/platform_impl/macos/mod.rs ；plugin 的 `ShortcutState::Pressed/Released` https://raw.githubusercontent.com/tauri-apps/plugins-workspace/v2/plugins/global-shortcut/src/lib.rs） | ❌ | ❌（`key_to_scancode` 無 Fn） | ✅（系統層獨占） | ✅ | 不受影響 |
| `CGEvent.tapCreate`（VoiceInk、handy-keys、Whispering、rdev） | Accessibility | ✅ | ✅ | ✅ | `.defaultTap` 可回傳 NULL 吞掉；`.listenOnly` 不行 | ❌ | KeyDown/Up 被擋，FlagsChanged 仍有 |
| `NSEvent.addGlobalMonitorForEvents`（VoiceVoice） | Accessibility（鍵盤事件） | ✅ | ✅ | ✅ | ❌ 只能觀察（https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:)） | ❌ | 同上 |

Handy 的設定 `KeyboardImplementation` 預設 macOS/Windows 用 `HandyKeys`，Linux 用 `Tauri`；`tauri_impl::validate_shortcut` 明寫「Tauri requires at least one non-modifier key and doesn't support the fn key」。

### 3.2 Fn/🌐 偵測（Swift）

VoiceVoice `HotkeyMonitor.swift`（最輕量，只需 Accessibility）：

```swift
globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] e in self?.handle(event: e) }
localMonitor  = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] e in self?.handle(event: e); return e }
if globalMonitor == nil { /* Accessibility 其實被拒（例如重 build 後）*/ }

private func handle(event: NSEvent) {
    switch currentHotkey {
    case .fn:          if event.keyCode == 63 { updateState(down: event.modifierFlags.contains(.function)) }
    case .rightOption: if event.keyCode == 61 { updateState(down: event.modifierFlags.contains(.option)) }
    case .capsLock:    // flagsChanged 反映的是「鎖定狀態」不是實體按鍵，無法偵測放開 → 只能做 toggle，
                       // 並用 IOHIDSetModifierLockState(kIOHIDCapsLockState) 立刻把 Caps 關掉
        if event.keyCode == 57 && event.modifierFlags.contains(.capsLock) { Self.setSystemCapsLock(on: false); updateState(down: !isDown) }
    }
}
```

VoiceInk `ShortcutMonitor.swift` 用 `CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, ...)` 監聽 keyDown/keyUp/flagsChanged + otherMouseDown/Up（支援滑鼠側鍵當熱鍵）；Fn 以 `kVK_Function (63)` 列為修飾鍵碼、flag 用 `.function`；callback 收到 `.tapDisabledByTimeout / .tapDisabledByUserInput` 時重置所有按住狀態並 `CGEvent.tapEnable(tap:enable:true)`；另以 `CGSessionCopyCurrentDictionary()` 檢查 `kCGSessionOnConsoleKey`、`kCGSessionLoginDoneKey`、`CGSSessionScreenIsLocked`，鎖屏時不處理熱鍵（`UserSessionInputPolicy.swift`）。

### 3.3 Fn/🌐 偵測（Rust，handy-keys 的做法）

`handy-keys/src/platform/macos/listener.rs`（https://github.com/handy-computer/handy-keys/blob/main/src/platform/macos/listener.rs），用 `objc2-core-graphics`：

```rust
// 建立 tap：Default 模式才能回傳 null 吞掉事件（給「按住 Fn 不要觸發系統動作」用）
let tap = CGEvent::tap_create(
    CGEventTapLocation::SessionEventTap, CGEventTapPlacement::HeadInsertEventTap,
    CGEventTapOptions::Default, event_mask, Some(event_tap_callback), ctx_ptr as *mut c_void);
// callback 內：
if matches!(event_type, CGEventType::TapDisabledByTimeout | CGEventType::TapDisabledByUserInput) {
    CGEvent::tap_enable(tap, true);                       // 在 callback 內重新啟用（Apple 文件模式）
    reconcile_modifiers(&mut state.current_modifiers,     // 用 CombinedSessionState 的 flags 校正漏掉的 release
        CGEventSource::flags_state(CGEventSourceStateID::CombinedSessionState));
    return event.as_ptr();
}
let flags = CGEvent::flags(Some(cg_event));
let fn_down = flags.contains(CGEventFlags::MaskSecondaryFn);   // Apple: kCGEventFlagMaskSecondaryFn
// FlagsChanged 且 keycode == 0x3F 代表 Fn 本身被按/放
```

重要註解（Handy issue #1827）：**不要**在 run loop 裡輪詢 `CGEventTapIsEnabled`——「recurring WindowServer RPCs leak kernel IPC vouchers and eventually panic the whole machine」；要在 callback 收到 `TapDisabledBy*` 偽事件時重啟。Whispering 的 `mac_tap.rs` 則是在每 250 ms 的 run-loop slice 檢查一次 `CGEventTapIsEnabled`（兩種做法互相矛盾，Handy 的經驗較新、且有實機 kernel panic 的教訓，建議採 callback 內重啟）。Whispering 另指出 rustdesk 的 rdev fork `listen()` 把 tap 掛在 `CFRunLoopGetMain()` 卻在背景執行緒 `CFRunLoopRun()`，會立刻返回——這是他們改成自管 tap 的原因之一。

`CGEventFlags.maskSecondaryFn` 文件：「Indicates that the Fn (Function) key is down for a keyboard, mouse, or flag-changed event.」（https://developer.apple.com/documentation/coregraphics/cgeventflags/masksecondaryfn）。

### 3.4 Fn 鍵的三個硬限制

1. **第三方鍵盤沒有 Fn 事件**。Handy README：「`fn` is not part of the standard USB HID keyboard specification: Apple reports it through a vendor-specific usage that macOS honors only from Apple devices, while third-party keyboards handle their Fn key entirely in firmware and send nothing to the computer.」（https://github.com/cjpais/Handy#fn-and-globe-key-shortcuts-macos）VoiceVoice README 也說外接 USB 鍵盤 Fn 有時不產生修飾事件，建議改右 Option 或 Caps Lock。IOHIDManager 也救不了（根本沒有 HID report）。
2. **系統聽寫搶 Fn**。VoiceVoice README：「When macOS system dictation is active, its overlay intercepts Fn — disable it」。它讀 `UserDefaults(suiteName: "com.apple.HIToolbox")` 的 `AppleFnUsageType`：1 = 切換輸入法、2 = 表情符號、3 = 系統聽寫、0/其他 = 不執行任何操作；並提供深連結 `x-apple.systempreferences:com.apple.preference.keyboard?Dictation`。handy-keys 另外發現：當 🌐 設為聽寫時，按它會產生 keycode `0xB0`（Dictation 鍵）而非單純 Fn 修飾（`types/key.rs` 的 `Dictation` 註解）。**設定頁必須提供「一鍵檢查並引導關閉」**。（Apple support 頁面本次被擋，無法引用官方「按下 🌐 兩次開始聽寫」原文。）
3. **Carbon 熱鍵不能註冊 Fn / 純修飾鍵** → 若用 Tauri 只靠 `tauri-plugin-global-shortcut`，就得像 Whispering 一樣放棄 Fn；Whispering ADR-0117 的理由：Fn 在 Windows/Linux 根本沒有對應事件、rdev 的 Fn 路徑「只有單元測試沒有實機證明」、而且 plugin 已提供 Pressed/Released 邊緣可做 chord 版 push-to-talk。

### 3.5 啟動模式與雙擊

- Handy `ShortcutActivation`：`Toggle` / `PushToTalk` / `HoldOrToggle`（預設；`hold_threshold_ms = 300`：按超過 300 ms 當作按住說話，否則 toggle）。
- VoiceInk `Mode`：`toggle` / `pushToTalk` / `hybrid`（`hybridPressThreshold = 0.5 s`）/ `doubleTap`（`doubleTapThreshold = 0.7 s`：兩次 release 間隔 ≤ 0.7 s 觸發）；另有 `shortcutPressCooldown = 0.5 s` 防連按。純修飾鍵熱鍵有「standalone」邏輯：按下修飾鍵後 1.0 s 內若有其他鍵 keyDown，視為一般快捷鍵（如 ⌘C）而不觸發（`shortcutInterruptionWindow = 1.0`）——**這是純修飾鍵熱鍵能否實用的關鍵**。
- 使用者「停用熱鍵」設定：VoiceInk 的 `secondaryRecordingShortcut == .none` 時直接不註冊；Handy 以 binding 清單增刪。另需提供「切換到右 Option / Caps Lock」給第三方鍵盤使用者。

---

## 4. 音訊擷取

### 4.1 三種擷取路徑

| | VoiceInk `CoreAudioRecorder.swift` | Handy `audio_toolkit/audio/recorder.rs` | VoiceVoice `AudioRecorder.swift` |
|---|---|---|---|
| API | AUHAL AudioUnit，`setInputDevice(deviceID)`，**不改系統預設輸入裝置** | `cpal` 0.16 預設/指定裝置 | `AVAudioEngine.inputNode.installTap` |
| 轉 16 kHz mono | 自訂轉換到 Int16 16 kHz，render callback 內零 malloc、無鎖（swift-atomics ring，96 slots） | `rubato::FftFixedIn`（chunk 1024）→ `rtrb` SPSC ring（2 秒容量，10 ms 輪詢） | `AVAudioConverter` → Float32 |
| 裝置熱切換 | `switchDevice(to:)`，監聽 `kAudioHardwarePropertyDefaultInputDevice`、合蓋（clamshell）時避開內建麥克風 | `device.rs` 列舉 | `AVAudioEngineConfigurationChange` 通知 |
| 低延遲啟動 | `prepare(deviceID:)` 預先初始化 AUHAL | `always_on_microphone` 選項 | 「暖機」常駐引擎 + 1.5 s 環形緩衝、**0.5 s pre-roll**（接住與按鍵同時說出的字）；引擎操作全部丟到專用 queue 並設 4 s timeout（曾遇 CoreAudio HAL 無限輪詢把主執行緒卡死） |

Apple 文件：`installTap(onBus:bufferSize:format:block:)` 的 `bufferSize` 只是建議值、tapBlock 可能在非主執行緒呼叫、每個 bus 只能一個 tap；**文件標示在 27.0 起棄用，改用 `installAudioTap(onBus:bufferSize:format:tapProvider:)`**（https://developer.apple.com/documentation/avfaudio/avaudionode/installtap(onbus:buffersize:format:block:)）。`AVAudioConverter` 支援取樣率、聲道、PCM 格式轉換（https://developer.apple.com/documentation/avfaudio/avaudioconverter）。

### 4.2 VAD

- Handy 可選兩個後端：`SileroVad`（透過 `vad-rs`，30 ms 幀 = 480 樣本 @16 kHz，threshold 0..1，session 間 `reset()` 清 LSTM 狀態）與 `EarshotVad`。平滑參數：`VAD_PREFILL_MS = 450`（語音開始前補回 450 ms）、`VAD_OFFLINE_HANGOVER_MS = 450`、`VAD_STREAMING_HANGOVER_MS = 1650`、`VAD_ONSET_MS = 60`（https://github.com/cjpais/Handy/blob/main/src-tauri/src/audio_toolkit/vad/mod.rs）。
- Silero VAD 官方：JIT 模型約 2 MB、支援 8k/16k、「One audio chunk (30+ ms) takes less than 1ms」、MIT、6000+ 語言語料（https://github.com/snakers4/silero-vad）。
- earshot：Rust 原生，16 ms 幀 / 256 樣本 @16 kHz，RTF ≈ 0.0003，宣稱比 Silero v6 快 40×，Apache-2.0/MIT（https://github.com/pykeio/earshot）。
- Swift 端：FluidAudio 提供 CoreML 版 Silero VAD（streaming API `processStreamingChunk`）與 Parakeet ASR，Apache 2.0，VoiceInk 已依賴（https://github.com/FluidInference/FluidAudio）。

### 4.3 藍牙耳機、Ducking、裝置切換

- Handy README：「Using a Bluetooth headset microphone on macOS may temporarily reduce playback quality or volume while recording because Bluetooth switches to bidirectional audio」——建議輸出留耳機、輸入選內建麥克風。
- VoiceVoice `SystemInputGuard.swift`：監聽 `kAudioHardwarePropertyDefaultInputDevice`，若新預設是藍牙裝置就改回內建或使用者指定的非藍牙麥克風（代價：使用者暫時無法手動選藍牙麥克風）。
- 壓低其他音訊：VoiceInk `PlaybackController` 透過 `MediaRemoteAdapter`（包裝私有 MediaRemote framework）偵測正在播放的 App 並 `pause()`，錄完再 `play()`，並記錄 bundle id 避免恢復錯 App（Plexamp 會忽略 play 指令）；VoiceVoice `SystemAudioMuter` 用 CoreAudio `kAudioDevicePropertyMute` 靜音預設輸出，裝置不支援 mute 則把主音量設 0 再還原，使用者原本就靜音則不動。兩者都不是真正的 ducking（macOS 沒有 iOS 的 `AVAudioSession` ducking）。

---

## 5. UI：浮動 HUD、選單列、登入啟動、自動更新

### 5.1 非激活浮動面板（NSPanel）

VoiceInk `NotchRecorderPanel.swift`（瀏海區 HUD）：

```swift
super.init(contentRect: rect, styleMask: [.nonactivatingPanel, .fullSizeContentView, .hudWindow], backing: .buffered, defer: false)
isFloatingPanel = true; canHide = false
level = .statusBar + 3                       // 比選單列還高
backgroundColor = .clear; isOpaque = false; hasShadow = false
hidesOnDeactivate = false
collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
// 顯示：orderFrontRegardless()；瀏海寬度用 screen.auxiliaryTopLeftArea/RightArea 推算，高度用 safeAreaInsets.top
```

`MiniRecorderPanel` 則用 `level = .floating`、`[.canJoinAllSpaces, .fullScreenAuxiliary]`。Apple 對 `nonactivatingPanel` 的定義：「the window is a panel or a subclass of NSPanel that does not activate the owning app」（https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel）。VoiceInk 的 panel 覆寫 `canBecomeKey = true` 以便面板內有輸入框時能打字（配合 `MenuBarExtra` 關閉後再 `show` 的時序註解）。

Tauri 端（Whispering `overlay.rs`，Handy `overlay.rs` 相同模式）用 `tauri-nspanel`（v2 branch，https://github.com/ahkohd/tauri-nspanel）：

```rust
tauri_panel! { panel!(RecordingOverlayPanel { config: { can_become_key_window: false, is_floating_panel: true } }) }
let panel = PanelBuilder::<_, RecordingOverlayPanel>::new(app, "recording-overlay")
    .url(WebviewUrl::External(url))
    .size(tauri::Size::Logical(LogicalSize { width: 224.0, height: 40.0 }))
    .level(PanelLevel::Status)
    .style_mask(StyleMask::empty().nonactivating_panel())   // 點按不會激活本 App
    .has_shadow(false).transparent(true).no_activate(true)
    .corner_radius(20.0)
    .with_window(|w| w.decorations(false).transparent(true).accept_first_mouse(true))
    .collection_behavior(CollectionBehavior::new().can_join_all_spaces().full_screen_auxiliary())
    .build()?;
```

Whispering 註解：普通 `WebviewWindow` 設 `focusable: false` 只擋鍵盤焦點，**點擊仍會把整個 App 帶到前景**，所以必須是 NSPanel。兩個 Tauri 專案都在 `tauri.conf.json` 開 `macOSPrivateApi: true` 並在 Cargo 開 `macos-private-api` feature（透明視窗需要）。Handy 的 overlay 尺寸 256×50（串流模式 400×120）、距頂 46 pt；Linux 走 `gtk-layer-shell`，Windows 另用 Win32 強制 topmost。

### 5.2 選單列

- SwiftUI `MenuBarExtra`（macOS 13+），`.menuBarExtraStyle(.window)` 可做 popover 式視窗（https://developer.apple.com/documentation/swiftui/menubarextra）；AppKit 則 `NSStatusBar.system.statusItem(withLength:)`（https://developer.apple.com/documentation/appkit/nsstatusbar）。
- VoiceInk `MenuBarManager` 以 `NSApplication.shared.setActivationPolicy(.accessory / .regular)` 在「只在選單列」與一般模式間切換（Info.plist `LSUIElement = false`，執行期動態改）。
- Tauri：`tauri` 的 `tray-icon` feature（Handy `tray.rs` 有 i18n 選單與狀態 icon）。

### 5.3 登入時啟動

`SMAppService.mainApp.register()` / `unregister()`，`status` 有 `.enabled / .requiresApproval / .notRegistered / .notFound`，`SMAppService.openSystemSettingsLoginItems()` 可直接開設定頁；macOS 13+，取代 `SMLoginItemSetEnabled`（https://developer.apple.com/documentation/servicemanagement/smappservice）。VoiceInk `LaunchAtLoginManager.swift` 在 `Task.detached(priority: .utility)` 內呼叫。Tauri 用 `tauri-plugin-autostart` 2.5。

### 5.4 自動更新

- Sparkle 2：macOS 12+（2.9.6 可到 10.13）、EdDSA 簽章（`SUPublicEDKey`）、`SUFeedURL` 需 HTTPS、`generate_appcast` 產生 appcast 與 delta、支援 sandbox、SwiftPM（https://github.com/sparkle-project/Sparkle）。VoiceInk Info.plist：`SUFeedURL`、`SUPublicEDKey`、`SUEnableInstallerLauncherService = true`、`SUScheduledCheckInterval = 14400`；程式用 `SPUStandardUpdaterController`。
- Tauri：`tauri-plugin-updater` 2.10 + minisign 公鑰，`endpoints` 指向 GitHub Releases 的 `latest.json`（Handy `tauri.conf.json`，`createUpdaterArtifacts: true`）。

---

## 6. 跨平台桌面框架選擇

| 框架 | 代表專案 | macOS 關鍵能力 | 熱鍵 | 文字注入 | 評語 |
|---|---|---|---|---|---|
| **Tauri 2 (Rust)** | Handy（2.11.5 + React）、Whispering（2.11 + Svelte） | `tauri-nspanel` 浮動面板、`objc2`/`core-graphics` 直呼 AppKit/CG、`tauri-plugin-macos-permissions` | `tauri-plugin-global-shortcut`（Carbon，Press/Released，無 Fn/純修飾）；要 Fn 得自寫 tap（handy-keys）或用 rdev fork | `enigo` 0.5/0.6 + `tauri-plugin-clipboard-manager`；高階需求自己用 objc2 寫 NSPasteboard | 兩個成熟專案證明可行；Rust 側可與 Windows 共用 VAD/重採樣/收據式貼上邏輯 |
| 原生 Swift | VoiceInk、VoiceVoice | 全部原生 | CGEventTap / NSEvent / KeyboardShortcuts | 直接 | 最穩、最細緻（瀏海 HUD、AUHAL、MediaRemote），但 Windows 需另寫 |
| Electron | — | 需要 native addon 才能做 NSPanel/CGEvent | `globalShortcut` 文件未提供 key-up；媒體鍵需 Accessibility；被佔用的快捷鍵會靜默失敗（https://raw.githubusercontent.com/electron/electron/main/docs/api/global-shortcut.md） | 需 robotjs/nut.js 類 addon | push-to-talk 需自寫 native；記憶體與包體大 |
| Flutter desktop | — | 需 platform channel / FFI | `hotkey_manager`：key-up「Only works on macOS」，底層 soffes/HotKey（Carbon）（https://github.com/leanflutter/hotkey_manager） | 無現成 | docs.flutter.dev 本次被擋，未深入 |
| .NET MAUI / Avalonia | — | 未研究（文件站被擋） | — | — | 列為未解問題 |

Rust 生態重點：
- `enigo`：Windows/macOS/Linux(X11，Wayland/libei 實驗性)；macOS 缺 Accessibility 時會自動偵測並請求，可在 `Settings` 關掉（https://github.com/enigo-rs/enigo 、Permissions.md）。docs.rs 本次被擋。
- `global-hotkey`（tauri 官方）：macOS 需在主執行緒有 event loop；Linux 僅 X11；媒體鍵另用 CGEventTap 繞路（https://github.com/tauri-apps/global-hotkey）。
- `rdev`（rustdesk fork）：listen/simulate/grab；macOS 用 CGEventTap、「listen 必須在父程序、不能 fork」、沒 Accessibility 會靜默不回呼（https://github.com/rustdesk-org/rdev）。Handy 仍依賴它，Whispering 已移除。
- `handy-keys` 0.3.4：跨平台（macOS CGEventTap、Windows low-level hook、Linux），支援側別修飾鍵、純修飾鍵、Fn、滑鼠側鍵、可吞事件（https://github.com/handy-computer/handy-keys）。

---

## 7. 已知陷阱清單（含來源）

1. **CGEventTap 被系統停用**：`kCGEventTapDisabledByTimeout`（callback 太慢）與 `ByUserInput`，必須在 callback 內 `CGEventTapEnable` 重啟並重置按鍵狀態（VoiceInk、handy-keys）；不要輪詢 `CGEventTapIsEnabled`（Handy #1827 kernel panic）。Apple 定義：https://developer.apple.com/documentation/coregraphics/cgeventtype/tapdisabledbytimeout
2. **Accessibility 授權在重 build / 換簽章後失效但 `AXIsProcessTrusted` 仍回 true**（Whispering ADR-0040/0117、VoiceVoice）。
3. **Secure Input** 讓 KeyDown/KeyUp 消失、FlagsChanged 仍在；Terminal「Secure Keyboard Entry」或背景 App 忘記關會卡住全系統（TN2150、Handy）。
4. **Fn 鍵只在 Apple 鍵盤有事件**；系統「🌐 鍵 → 聽寫」會先攔截。
5. **鍵盤佈局**：Dvorak/非拉丁佈局下 keycode 9 不是 V（Handy 用 UCKeyTranslate 解析；VoiceInk 對「QWERTY ⌘」佈局改 key code）。
6. **剪貼簿還原競速**（Handy #502）與 **Chromium 多次讀剪貼簿**；**使用者習慣性再按 ⌘V 貼第二次**（VoiceVoice 15 秒延遲還原）。
7. **剪貼簿管理器**會把轉錄稿記進歷史 → 加 `org.nspasteboard.*` 標記（Maccy 遵守）。
8. **Electron**：AX 樹預設關閉（需 `AXManualAccessibility`）、焦點查詢常空、AX 直寫超過 ~2040 字元 crash。
9. **Safari WebArea 懶建樹**、**Termius/xterm.js 的隱藏文字欄**導致驗證失敗但其實已貼上——不要重送。
10. **鎖屏 / 非 console session** 仍會收到事件（VoiceInk 用 `CGSessionCopyCurrentDictionary` 過濾）。
11. **CoreAudio HAL 可能無限輪詢卡死主執行緒**（VoiceVoice 以專用 queue + 4 s timeout 防護）。
12. **藍牙耳機麥克風觸發 HFP** 導致播放音質掉到 16 kHz mono。
13. **`installTap` 在 27.0 棄用**，新專案可直接用 `installAudioTap(...tapProvider:)`（需實機確認 API 可用的最低 OS）。
14. **Tauri 透明/面板需要 `macos-private-api`**，這會讓 App 無法上 MAS（反正本來就不上）。
15. **AppleScript 自動化權限在 Tahoe 只有真的執行 NSAppleScript 才會彈窗**（VoiceVoice）。

---

## 8. 對我們的設計意涵

1. **架構決策：Tauri 2 + Rust core，macOS 專用部分用 objc2 / core-graphics 直寫**，而不是 Electron。理由：Handy 與 Whispering 已把最難的三件事（NSPanel 非激活 HUD、全保真剪貼簿快照、自管 CGEventTap）在 Rust 做出來且 MIT 開源可借鏡；Rust core（VAD、重採樣、收據式貼上、熱鍵狀態機）可與 Windows 共用。若團隊 Swift 能力強且願意雙寫，原生 Swift 在 macOS 體驗上限更高（VoiceInk 的瀏海 HUD、AUHAL、MediaRemote 暫停）。
2. **熱鍵：採 handy-keys 式自管 CGEventTap（Default 模式）為主、Carbon global-shortcut 為 Secure Input 備援**，同時支援 Fn、右 ⌘/右 ⌥、Caps Lock（toggle）、自訂 chord。預設建議「右 ⌘ 按住說話 + Fn 可選」，因為 Fn 在第三方鍵盤與系統聽寫設定下不可靠；首次設定要自動檢查 `AppleFnUsageType` 並引導改成「不執行任何操作」。實作 VoiceInk 的「純修飾鍵 1 秒內若按其他鍵就不觸發」與 Handy 的 `HoldOrToggle (300 ms)`。
3. **文字注入：剪貼簿 + ⌘V 為主，加三道保險**：(a) 佈局感知 keycode（UCKeyTranslate）；(b) 收據式還原（declareTypes:owner: promise + changeCount 守衛）+ `org.nspasteboard.*` 標記 + 全保真快照；(c) AX 焦點分類：notEditable 時不貼只放剪貼簿並提示；Electron/Chromium 不做 AX 直寫、不重送 ⌘V。Direct Unicode 打字只作為使用者可選的備援（密碼欄/終端機）。
4. **權限 onboarding**：只要 Microphone + Accessibility；提供「實際建立一個 global monitor / tap 來驗證」的真實檢查而非只看 `AXIsProcessTrusted`；每秒輪詢直到授權；偵測 Secure Input 並指出肇事 App；永遠用正式 Developer ID 簽章（含 dev build），避免 TCC 失效。
5. **發布：Developer ID + Hardened Runtime + notarization + Sparkle/Tauri updater，不上 Mac App Store**；entitlements 至少 `device.audio-input`、`automation.apple-events`（若保留 AppleScript 備援）、`network.client`；`minimumSystemVersion` 建議 13（MenuBarExtra、SMAppService）。
6. **音訊**：以 `cpal`（或 Swift 側 AUHAL）指定裝置、不更動系統預設輸入；16 kHz mono 重採樣；Silero VAD（跨平台 ONNX）或 earshot；提供「暖機 + 0.5 s pre-roll」選項（並告知會常亮麥克風燈）；藍牙防護（自動改回內建麥克風）與「錄音時暫停媒體」選項（MediaRemote 私有 API 有被 Apple 封鎖的風險，備案為 CoreAudio mute）。
7. **UI**：NSPanel `nonactivatingPanel` + `.statusBar` 層級 + `canJoinAllSpaces/fullScreenAuxiliary`，HUD 不可搶焦點；選單列常駐（`.accessory` policy）；`SMAppService` 登入啟動。
8. **可共用到 Windows 的設計**：收據式剪貼簿（`SetClipboardData(NULL)` + `WM_RENDERFORMAT`）、VAD/重採樣、熱鍵狀態機、「貼上結果分類（pasted / leftOnClipboard / clipboardOnly）」的 UI 狀態模型。

---

## 9. 未解問題

1. macOS 26（Tahoe）上 `listenOnly` 鍵盤 CGEventTap 是否只需 Accessibility，還是會被要求 Input Monitoring？（需實機測試；參考專案都用 Accessibility。）
2. Secure Input 啟用時，`CGEventPost` 的 ⌘V 是否仍能進入密碼欄 / Terminal？（TN2150 只講「攔截」被擋；VoiceInk fork 宣稱逐字打字可進密碼欄，未驗證。）
3. Wispr Flow / Typeless / Superwhisper 實際的 Fn 擷取與貼上細節（官網被擋、Superwhisper 閉源）：是否也走 flagsChanged+keycode 63？是否用 IMKit？
4. `installAudioTap(onBus:bufferSize:format:tapProvider:)` 的最低可用 OS 與行為差異。
5. MediaRemote 私有框架（VoiceInk 的 MediaRemoteAdapter）在 macOS 26/27 是否仍可用、notarization 是否會被拒。
6. Apple Developer Program 年費與 Developer ID 憑證流程的最新數字（頁面未抓到）。
7. .NET MAUI / Avalonia 在 macOS 的 NSPanel 與 CGEventTap 整合成熟度（文件站被擋）。
8. Handy 的「reliable paste」目前仍是 debug-gated Beta——在 Chromium、Office、JetBrains 等大宗 App 的收據可靠度需要自己量測。
9. IMKit 作為「MAS 相容、免 Accessibility」的替代注入路徑是否值得做（與注音輸入法共存的 UX 問題）。
10. 第三方鍵盤使用者比例（決定預設熱鍵是否該是 Fn）。
