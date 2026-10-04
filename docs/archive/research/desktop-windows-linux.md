# Windows / Linux 桌面端技術研究：文字注入、全域熱鍵、音訊、簽章、打包

> 研究日期：2026-10-01。主題：自製 Typeless 類語音聽寫工具的 Windows 與 Linux 端實作。
> 方法：以一手來源為主（Microsoft 官方文件的 GitHub 原始碼鏡像 `MicrosoftDocs/*`、各開源專案原始碼、xdg-desktop-portal 介面定義），並直接 clone 閱讀 Handy、Whispering(epicenter)、whisper-writer 三個開源聽寫專案的程式碼。
> 研究環境限制：本次環境無法連到 learn.microsoft.com、azure.microsoft.com、support.microsoft.com、docs.rs、flatpak.github.io 等網域，因此部分 Microsoft 文件改引用 `github.com/MicrosoftDocs/*` 的原始 markdown。**凡是沒有一手來源佐證、只憑記憶的敘述，下文都以「⚠ 未驗證」標示**，請在動工前再確認。

---

## 0. 執行摘要（Executive Summary）

1. **Windows 文字注入沒有「單一萬用解」**。三個被研究的開源專案（Handy、Whispering、whisper-writer）在 Windows 上都以「**剪貼簿 + 模擬 Ctrl+V**」為主要路徑，而非逐字 `SendInput`；原因是逐字輸入在 CJK、長文本、IME 啟用時的可靠性和速度都不如貼上。Handy 最新版（2026-09）進一步實作「**收據序列化貼上（receipt-sequenced paste）**」：用 `SetClipboardData(CF_UNICODETEXT, NULL)` 延遲渲染，等到目標程式真的讀取（`WM_RENDERFORMAT`）才還原使用者原本的剪貼簿，解決固定延遲造成「舊剪貼簿被貼回去」的競態（[Handy paste_tx/mod.rs](https://github.com/cjpais/Handy/blob/main/src-tauri/src/paste_tx/mod.rs)）。**我們應直接採用這個設計。**
2. **`SendInput` + `KEYEVENTF_UNICODE`** 是次要（fallback）路徑：Microsoft 文件明確說「應用程式只能把輸入注入到完整性等級相同或更低的程式」（UIPI），所以對**以系統管理員執行的視窗注入會靜默失敗**，而且 `GetLastError` 不會回報（[SendInput 文件](https://github.com/MicrosoftDocs/sdk-api/blob/docs/sdk-api-src/content/winuser/nf-winuser-sendinput.md)）。這點對剪貼簿路徑的 Ctrl+V 按鍵同樣適用。
3. **TSF（Text Services Framework）做成真正的 IME** 是「最正統、相容性最高（含 UWP/Store app 與 Win+H 等級的 in-place 插入）」但也是**最貴**的方案：要寫 in-proc COM DLL、在 edit session 內透過 `ITfInsertAtSelection` 插入文字、處理註冊與 32/64 位元。文件明言「**文字只能在 edit session 內修改**」（[TSF edit-sessions](https://github.com/MicrosoftDocs/win32/blob/docs/desktop-src/TSF/edit-sessions.md)）。建議列為 v2 項目。
4. **全域熱鍵：Windows 用 `WH_KEYBOARD_LL`，不用 `RegisterHotKey`**。`RegisterHotKey` 只給 `WM_HOTKEY`（無放開事件、無法綁單一修飾鍵如 Right-Ctrl、不能用 Win 鍵組合、F12 保留給除錯器）；低階鉤子則可得按下/放開、可吞掉按鍵、可偵測 `LLKHF_INJECTED`（我們自己送出的 Ctrl+V 要忽略），但**Windows 10 1709 起鉤子回呼最多 1000 ms、逾時會被靜默移除**（[LowLevelKeyboardProc](https://github.com/MicrosoftDocs/win32/blob/docs/desktop-src/winmsg/lowlevelkeyboardproc.md)）。Handy 作者為此抽出 `handy-keys` crate（0.3.4，2026-08），Windows 走低階鉤子、Linux 直讀 evdev 並透過 uinput 重新注入未被攔截的鍵（[handy-keys](https://github.com/handy-computer/handy-keys)）。
5. **Linux 是兩個世界**：X11 下 `xdotool`/XTest 和 X11 全域熱鍵都成熟；**Wayland 沒有通用的輸入注入與全域熱鍵 API**。可行路徑：(a) **xdg-desktop-portal `GlobalShortcuts`**（v2 介面，有 `Activated`/`Deactivated` 訊號可做 push-to-talk；GNOME 48 起有後端、KDE 已有）；(b) 文字注入在 wlroots 系用 `wtype`（`zwp_virtual_keyboard_v1`，**GNOME Mutter 與 KWin 皆不支援**）、KDE 用 fake-input/`kwtype` 或 KWin 的 `eis` 外掛、GNOME 用 **RemoteDesktop portal 的 EIS socket（libei）**（GNOME 45 起）或 uinput（`ydotool`/`dotool`，需 `input` 群組，`ydotool` 不支援非 ASCII）；(c) **做成 Fcitx5/IBus 輸入法引擎**用 `commitString`/`ibus_engine_commit_text` 插入，在任何工具組與 Wayland 下都可靠，但使用者必須切換到我們的輸入法。
6. **GNOME Wayland 連「寫剪貼簿」都是問題**：Handy issue #1742（2026，GNOME 50.1）顯示 Tauri/arboard 需要 `ext-data-control`/`wlr-data-control` 協定，而 GNOME 不提供，導致「轉錄成功但貼不出去」。**在 GNOME Wayland 上，「剪貼簿+Ctrl+V」路徑可能從第一步就失敗**，這是 Linux 端最大的設計風險。
7. **簽章與散佈**：Electron 官方文件直言，2023-06 起軟體型（非硬體金鑰）OV 憑證在 SmartScreen 眼中「等同未簽章」，而 **Azure Trusted Signing（已更名 Artifact Signing）**是最便宜且能免除 SmartScreen 警告的選項，但「**僅限某些國家的開發者**」（[Electron code-signing](https://github.com/electron/electronjs.org-new/blob/main/docs/latest/tutorial/code-signing.md)；[trusted-signing-action issue #81「Availability outside US and Canada」](https://github.com/Azure/trusted-signing-action/issues?q=individual+validation)）。**台灣開發者能否申請、以及月費數字，本次無法以一手來源驗證**（⚠ 記憶中 Basic 約 US$9.99/月、Premium 約 US$99.99/月）。
8. **安裝與更新**：Tauri v2 的 NSIS 安裝檔預設 per-user（不需 UAC）、可交叉編譯、支援 ARM64（**MSI/WiX 不支援 ARM64**）；Tauri updater 強制 minisign 簽章、Windows 支援 MSI/NSIS、Linux **只支援 AppImage**（[windows-installer.mdx](https://github.com/tauri-apps/tauri-docs/blob/v2/src/content/docs/distribute/windows-installer.mdx)、[updater.mdx](https://github.com/tauri-apps/tauri-docs/blob/v2/src/content/docs/plugin/updater.mdx)）。Velopack（MIT，Rust 核心，支援 C#/Rust/C++/JS、delta 更新）是 Squirrel.Windows 的實質繼任者；Squirrel.Windows 自己 README 已在徵求維護者。
9. **Windows ARM64**：ONNX Runtime QNN EP 可用 Snapdragon X 的 Hexagon NPU，但 **HTP 後端只吃量化（8/16-bit）且輸入形狀必須固定**的模型；Whisper 的 decoder 形狀動態、加上 Qualcomm 自家 Windows 工具鏈還註明「Snapdragon X 上只支援 x64 Python」，因此 **v1 在 ARM64 上應以 CPU（whisper.cpp/sherpa-onnx ARM64 build）為主，NPU 列為研究項目**。
10. 內建競品：Windows 11 有 Win+H 語音輸入與 Voice Access（22H2 起）。⚠ 本次環境無法取得 Microsoft 支援頁，語言支援與離線能力細節未能驗證。

---

## 1. Windows：文字注入（Text Insertion）

### 1.1 方法總覽與相容性矩陣

| 方法 | 機制 | 優點 | 已知破綻 | 來源 |
|---|---|---|---|---|
| **剪貼簿 + 模擬 Ctrl+V** | 寫入 `CF_UNICODETEXT`，`SendInput` 送 Ctrl+V，再還原剪貼簿 | 速度與 CJK/Emoji 無關、長文本一次到位、幾乎所有編輯器都支援貼上 | 要處理剪貼簿還原競態、剪貼簿管理工具會記錄、終端機/部分程式 Ctrl+V 行為不同（Windows Terminal 用 Ctrl+V 可貼，但 Handy 回報「尾端空白」在 Windows Terminal 失效 [#1018](https://github.com/cjpais/Handy/issues/1018)）；Ctrl+V 本身是 `SendInput`，受 UIPI 限制 | Handy `clipboard.rs`、`paste_tx/*`；Whispering `delivery.rs` |
| **`SendInput` + `KEYEVENTF_UNICODE`** | 每個 UTF-16 code unit 送 `VK_PACKET` 按下/放開 | 不動剪貼簿、不依賴鍵盤配置 | 受 UIPI（管理員視窗、UAC 畫面）阻擋且無錯誤碼；逐字送、長文慢；部分遊戲/使用 Raw Input 的程式忽略 `VK_PACKET`（⚠ 未驗證）；某些舊程式/終端對 `VK_PACKET` 支援不佳（⚠ 未驗證） | [KEYBDINPUT](https://github.com/MicrosoftDocs/sdk-api/blob/docs/sdk-api-src/content/winuser/ns-winuser-keybdinput.md)、[SendInput](https://github.com/MicrosoftDocs/sdk-api/blob/docs/sdk-api-src/content/winuser/nf-winuser-sendinput.md)、enigo `win_impl.rs` |
| **`WM_CHAR` / `PostMessage`** | 對目標 HWND 直接送 `WM_CHAR` | 不需焦點 | 繞過 IME 與輸入管線、UWP/Electron/Chromium 多半不理會、受 UIPI 阻擋（⚠ 一般經驗，未找到一手文件） | — |
| **UI Automation `ValuePattern.SetValue`** | 透過 UIA 直接設值 | 可在不模擬按鍵下寫入、可讀取既有內容做上下文 | **取代整個值而非在游標處插入**；需 `IsEnabled=TRUE` 且 `IsReadOnly=FALSE`；多行控制項建議同時實作 `ITextProvider`，但 **TextPattern 本身沒有插入/取代文字的方法** | [uiauto-implementingvalue](https://github.com/MicrosoftDocs/win32/blob/docs/desktop-src/WinAuto/uiauto-implementingvalue.md)、[uiauto-implementingtextandtextrange](https://github.com/MicrosoftDocs/win32/blob/docs/desktop-src/WinAuto/uiauto-implementingtextandtextrange.md) |
| **TSF 文字服務（真 IME）** | 註冊 Text Input Processor，在 edit session 內 `ITfInsertAtSelection::InsertAtSelection` | 等同 Win+H 的插入等級：UWP、Office、瀏覽器、終端皆可；可做 composition（邊講邊顯示底線文字）、可讀取周圍文字 | 需 COM in-proc DLL 載入每個程序、32/64 位元各一份、需簽章、使用者需啟用該輸入法；`ITfInsertAtSelection` 由 manager 實作、由 `ITfContext::QueryInterface` 取得，且「text can only be changed inside an edit session」 | [nn-msctf-itfinsertatselection](https://github.com/MicrosoftDocs/sdk-api/blob/docs/sdk-api-src/content/msctf/nn-msctf-itfinsertatselection.md)、[TSF edit-sessions](https://github.com/MicrosoftDocs/win32/blob/docs/desktop-src/TSF/edit-sessions.md) |

**UIPI 的關鍵句**（[SendInput 文件](https://github.com/MicrosoftDocs/sdk-api/blob/docs/sdk-api-src/content/winuser/nf-winuser-sendinput.md)）：「Applications are permitted to inject input only into applications that are at an equal or lesser integrity level.」而且文件指出 UIPI 阻擋時 `GetLastError` 和回傳值都不會明確回報。回傳值為「成功插入鍵盤或滑鼠輸入串流的事件數」；若為 0 表示「輸入已被另一個執行緒阻擋」。

**`KEYEVENTF_UNICODE` 的規格**（[KEYBDINPUT](https://github.com/MicrosoftDocs/sdk-api/blob/docs/sdk-api-src/content/winuser/ns-winuser-keybdinput.md)）：「If specified, the system synthesizes a VK_PACKET keystroke. The wVk parameter must be zero.」`wScan` 放要送到前景程式的 Unicode 字元；「This flag can only be combined with the KEYEVENTF_KEYUP flag.」文件未提代理對（surrogate pair），但 enigo 的實作是把每個 `char` `encode_utf16()` 後逐個 code unit 送按下/放開，並把整段文字的 `INPUT` 陣列**一次 `SendInput`** 送出（[enigo src/win/win_impl.rs](https://github.com/enigo-rs/enigo/blob/main/src/win/win_impl.rs)）；`\n` 轉成 `Key::Return`、`\t` 類似。

**哪些程式會壞掉（彙整）**：
- **管理員權限視窗（elevated）**：`SendInput`（含模擬 Ctrl+V）靜默失敗 — 一手來源見上。對策：偵測前景視窗的程序完整性等級（`OpenProcess` → `GetTokenInformation(TokenIntegrityLevel)`，⚠ 作法來自經驗），無法注入時改為「留在剪貼簿並提示」。Whispering 的 `write_text` 就設計了 `WriteTextOutcome::LeftOnClipboard` 回傳值作為降級結果（[delivery.rs](https://github.com/epicenter-md/epicenter/blob/main/apps/epicenter/src-tauri/src/delivery.rs)）。
- **UWP / Store app**：貼上與 `VK_PACKET` 一般可用（它們走正常輸入管線），但 `WM_CHAR`/`PostMessage` 不行（⚠ 經驗）。
- **Electron / Chromium / VS Code**：貼上可用；Handy 註解提到 Chromium「先探測再讀取」會讀剪貼簿多次，因此還原剪貼簿必須等「最後一次讀取後的靜默期」（[paste_tx/mod.rs](https://github.com/cjpais/Handy/blob/main/src-tauri/src/paste_tx/mod.rs)）。
- **終端機**：Windows Terminal 支援 Ctrl+V；舊式 conhost 需 Ctrl+V 開啟「啟用 Ctrl 鍵快速鍵」（⚠ 經驗）。Handy 提供 `PasteMethod::{CtrlV, CtrlShiftV, ShiftInsert, Direct, None, ExternalScript}` 讓使用者按程式切換（[settings.rs](https://github.com/cjpais/Handy/blob/main/src-tauri/src/settings.rs)）。
- **RDP / 遠端桌面**：注入發生在本機 RDP 用戶端視窗，由 RDP 轉送鍵盤事件到遠端；`VK_PACKET` 經 RDP 的行為不保證（⚠ 未驗證）。剪貼簿路徑依賴 RDP 剪貼簿重導向。
- **遊戲 / 反作弊**：使用 Raw Input 或 DirectInput 的遊戲會忽略 `SendInput` 合成事件；反作弊可能把低階鉤子視為可疑（⚠ 未驗證，但這類程式不是聽寫工具的目標場景）。
- **Secure Desktop（UAC 提示、登入畫面）**：任何使用者層級注入都不可行。

### 1.2 建議實作：收據序列化剪貼簿貼上（Handy 的作法）

Handy `paste_tx/mod.rs` 的設計說明值得逐條採納（[原始碼](https://github.com/cjpais/Handy/blob/main/src-tauri/src/paste_tx/mod.rs)）：

- 以**延遲渲染**發佈轉錄文字：Windows 用 `SetClipboardData(CF_UNICODETEXT, NULL)`，擁有者視窗會在有人讀取時收到 `WM_RENDERFORMAT`；macOS 用 `declareTypes:owner:`。
- 兩條信任規則：(1) **只有在貼上按鍵送出之後**觀察到的讀取才算「收據」，之前的讀取是剪貼簿管理工具/防毒在反應剪貼簿變更；(2) **只有在我們仍擁有剪貼簿時**（`GetClipboardSequenceNumber()` 未變、未收到 `WM_DESTROYCLIPBOARD`）才還原，使用者中途複製了別的東西就以使用者為準。
- 還原要等「最後一次收據後的短暫靜默期」（Chromium 會讀多次），並設上限逾時；失敗模式永遠是「文字在剪貼簿多待一會兒」，不會是「舊內容被貼回」。
- Windows 實作用一個隱藏的 message-only window 跑自己的 message pump（`pump_thread`），處理 `WM_RENDERFORMAT`、`WM_RENDERALLFORMATS`、`WM_DESTROYCLIPBOARD`、`WM_TIMER`（[paste_tx/windows.rs](https://github.com/cjpais/Handy/blob/main/src-tauri/src/paste_tx/windows.rs)）。
- 快照時除了文字也保存原本的點陣圖（`CF_BITMAP`）等格式，避免「使用者剛截圖就被清掉」。Whispering 在 macOS 端也做了同樣的全格式快照（`NSPasteboardItem` 全部 type/data 對），並寫入 `org.nspasteboard.ConcealedType` 讓剪貼簿歷史工具跳過（[clipboard.rs](https://github.com/epicenter-md/epicenter/blob/main/apps/epicenter/src-tauri/src/clipboard.rs)）。Windows 端對應的慣例是 `ExcludeClipboardContentFromMonitorProcessing` 格式（⚠ 未在本次一手驗證）。
- Handy 的舊路徑（固定延遲後還原）在 Windows 預設 Ctrl 鍵「按住 100 ms」再放開，因為部分程式在處理 V 鍵時會輪詢全域修飾鍵狀態（[input.rs](https://github.com/cjpais/Handy/blob/main/src-tauri/src/input.rs) 的 `send_paste_ctrl_v(enigo, hold_ms)`）。Whispering 則用 50 ms 前置、100 ms 後置的固定延遲（`PRE_PASTE_SETTLE`/`PRE_RESTORE_SETTLE`，[delivery.rs](https://github.com/epicenter-md/epicenter/blob/main/apps/epicenter/src-tauri/src/delivery.rs)）— 這正是 Handy #502 想解決的競態。
- Windows 的 Ctrl+V 用 **虛擬鍵碼 `VK_V` (0x56)** 而非字元，避免 AZERTY/Dvorak/俄文配置下按錯鍵（Handy、Whispering 皆如此）。

### 1.3 程式碼片段

**Rust（`windows` crate）：`SendInput` + `KEYEVENTF_UNICODE`**（需 feature `Win32_UI_Input_KeyboardAndMouse`；寫法與 enigo 一致）

```rust
use windows::Win32::UI::Input::KeyboardAndMouse::{
    SendInput, INPUT, INPUT_0, INPUT_KEYBOARD, KEYBDINPUT, KEYEVENTF_KEYUP, KEYEVENTF_UNICODE,
    VIRTUAL_KEY,
};

fn type_unicode(text: &str) -> u32 {
    let mut inputs: Vec<INPUT> = Vec::with_capacity(text.len() * 4);
    for unit in text.encode_utf16() {
        for flags in [KEYEVENTF_UNICODE, KEYEVENTF_UNICODE | KEYEVENTF_KEYUP] {
            inputs.push(INPUT {
                r#type: INPUT_KEYBOARD,
                Anonymous: INPUT_0 {
                    ki: KEYBDINPUT {
                        wVk: VIRTUAL_KEY(0),      // 文件：KEYEVENTF_UNICODE 時 wVk 必須為 0
                        wScan: unit,              // UTF-16 code unit（代理對各送一次）
                        dwFlags: flags,
                        time: 0,
                        dwExtraInfo: OUR_MARKER,  // 讓自家低階鉤子辨識並忽略
                    },
                },
            });
        }
    }
    // 回傳值 = 成功插入的事件數；UIPI 阻擋時可能 == inputs.len() 卻沒效果，無法靠此偵測
    unsafe { SendInput(&inputs, std::mem::size_of::<INPUT>() as i32) }
}
```

**Rust：用 `enigo` 0.6 做同一件事**（Handy/Whispering 的實際依賴；`enigo.text()` 在 Windows 內部就是上面那段）

```rust
use enigo::{Enigo, Keyboard, Settings, Key, Direction};
let mut enigo = Enigo::new(&Settings::default())?;
enigo.text("今天天氣很好。")?;                      // KEYEVENTF_UNICODE 批次送出
enigo.key(Key::Control, Direction::Press)?;         // 模擬 Ctrl+V（配合剪貼簿）
enigo.key(Key::Other(0x56), Direction::Click)?;     // VK_V，與鍵盤配置無關
enigo.key(Key::Control, Direction::Release)?;
```

**C#（P/Invoke）：剪貼簿 + Ctrl+V 並以序號保護還原**

```csharp
[DllImport("user32.dll", SetLastError = true)]
static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);
[DllImport("user32.dll")] static extern uint GetClipboardSequenceNumber();

const ushort VK_CONTROL = 0x11, VK_V = 0x56;
const uint KEYEVENTF_KEYUP = 0x0002;

static INPUT Key(ushort vk, bool up) => new INPUT {
    type = 1, // INPUT_KEYBOARD
    U = new InputUnion { ki = new KEYBDINPUT { wVk = vk, dwFlags = up ? KEYEVENTF_KEYUP : 0, dwExtraInfo = OurMarker } }
};

async Task PasteAsync(string transcript) {
    var backup = Clipboard.GetDataObject();            // 建議完整快照（文字+影像）
    Clipboard.SetText(transcript);
    uint seq = GetClipboardSequenceNumber();
    var chord = new[] { Key(VK_CONTROL,false), Key(VK_V,false), Key(VK_V,true), Key(VK_CONTROL,true) };
    if (SendInput((uint)chord.Length, chord, Marshal.SizeOf<INPUT>()) == 0) { /* 被阻擋：留在剪貼簿並提示 */ return; }
    await WaitForRenderFormatOrTimeout();               // 正式版：改用延遲渲染 + WM_RENDERFORMAT 收據
    if (GetClipboardSequenceNumber() == seq) Clipboard.SetDataObject(backup, true); // 只有仍是我們的內容才還原
}
```

**C#：UIA `ValuePattern` 作為「可讀上下文」而非插入**

```csharp
var el = AutomationElement.FocusedElement;
if (el.TryGetCurrentPattern(TextPattern.Pattern, out var tp)) {
    var sel = ((TextPattern)tp).GetSelection();          // 取得游標前後文字給 LLM 做格式修正
}
if (el.TryGetCurrentPattern(ValuePattern.Pattern, out var vp) && !((ValuePattern)vp).Current.IsReadOnly) {
    // 注意：SetValue 會取代整個值，只適合單行欄位的「整段替換」情境
}
```

**TSF：真 IME 的核心呼叫（C++，概念骨架）**

```cpp
// 在 ITfEditSession::DoEditSession(TfEditCookie ec) 內：
CComPtr<ITfInsertAtSelection> ias;
if (SUCCEEDED(context->QueryInterface(IID_ITfInsertAtSelection, (void**)&ias))) {
    CComPtr<ITfRange> range;
    ias->InsertAtSelection(ec, TF_IAS_NOQUERY, text, (LONG)wcslen(text), &range);
}
// 觸發：context->RequestEditSession(clientId, this, TF_ES_READWRITE | TF_ES_ASYNCDONTCARE, &hr);
```
（`InsertAtSelection` 參數與 `TF_IAS_*` 旗標名稱來自 msctf.h 的一般知識，本次只驗證到介面層級說明；⚠ 旗標細節請以 SDK 標頭為準。）

---

## 2. Windows：全域熱鍵與 Push-to-Talk

### 2.1 `RegisterHotKey` vs `WH_KEYBOARD_LL`

| | `RegisterHotKey` | `SetWindowsHookEx(WH_KEYBOARD_LL)` |
|---|---|---|
| 事件 | 只有 `WM_HOTKEY`（按下），文件未區分 down/repeat；`MOD_NOREPEAT`（Vista+）可抑制自動重複 | 每個按下/放開都進回呼（`LLKHF_UP` 位元） |
| 單一修飾鍵（Right-Ctrl、Caps Lock、Fn） | 不行 | 可以（看 `vkCode`/`scanCode`；Fn 多數鍵盤不產生事件） |
| 吞掉按鍵 | 註冊成功即獨占 | 回傳非零即阻止傳遞 |
| 限制 | 已被其他程式註冊則失敗；`MOD_WIN` 保留給 OS；F12 保留給除錯器；不能綁到其他執行緒建立的視窗 | 安裝執行緒必須跑 message loop；**Win7+ 逾時會被靜默移除；Win10 1709+ 上限 1000 ms**（`HKCU\Control Panel\Desktop\LowLevelHooksTimeout`） |
| 自我注入辨識 | — | `KBDLLHOOKSTRUCT.flags` 的 `LLKHF_INJECTED (0x10)`、`LLKHF_LOWER_IL_INJECTED (0x02)` |
| 來源 | [RegisterHotKey](https://github.com/MicrosoftDocs/sdk-api/blob/docs/sdk-api-src/content/winuser/nf-winuser-registerhotkey.md) | [LowLevelKeyboardProc](https://github.com/MicrosoftDocs/win32/blob/docs/desktop-src/winmsg/lowlevelkeyboardproc.md)、[KBDLLHOOKSTRUCT](https://github.com/MicrosoftDocs/sdk-api/blob/docs/sdk-api-src/content/winuser/ns-winuser-kbdllhookstruct.md) |

**結論**：Push-to-talk（按住說話、放開送出）與「Right-Ctrl 單鍵」這兩個 Typeless 式體驗都**只能靠低階鉤子**。

### 2.2 現成 Rust 方案比較

- **`tauri-plugin-global-shortcut` 2.x**：支援 Windows/Linux/macOS、不支援行動端；事件有 `ShortcutState::Pressed/Released`（[README](https://github.com/tauri-apps/plugins-workspace/blob/v2/plugins/global-shortcut/README.md)）。底層是 **`global-hotkey` crate**：Windows 用 `RegisterHotKey`（需 win32 event loop 在同一執行緒）、Linux **只支援 X11**（[global-hotkey](https://github.com/tauri-apps/global-hotkey)、[lib.rs](https://github.com/tauri-apps/global-hotkey/blob/dev/src/lib.rs) 定義 `HotKeyState { Pressed, Released }`）。因此它**無法做單一修飾鍵熱鍵**。
- **`rdev`**：Windows 用 `WH_KEYBOARD_LL`、Linux 用 X11 XRecord（**不支援 Wayland**）、`unstable_grab` 可吞鍵；`listen` 會阻塞執行緒（[rdev](https://github.com/Narsil/rdev)）。Handy 用的是 rustdesk 的 fork（Cargo.toml 第 50 行）。
- **`handy-keys` 0.3.4（2026-08-07）**：Handy 作者抽出的函式庫。Windows 低階鉤子、免權限；macOS 需輔助使用權限；Linux **直接讀 `/dev/input/event*`（evdev），X11/Wayland/console 行為一致**，要吞鍵時「透過每個裝置的 uinput 複本重新注入未被阻擋的按鍵」，建議發行時附 udev `uaccess` 規則而非要求使用者加入 `input` 群組；支援**只有修飾鍵的熱鍵**（如 `Cmd+Shift`）、字串解析 `"Ctrl+Alt+Space"`、以及錄製熱鍵用的 `KeyboardListener`（[handy-keys](https://github.com/handy-computer/handy-keys)；原始碼結構 `src/platform/{windows,linux,macos}/{listener.rs,keycode.rs,mod.rs}`）。
- Handy 的切換邏輯：`KeyboardImplementation` 預設 **Windows/macOS 用 HandyKeys、Linux 用 Tauri 外掛**；HandyKeys 初始化失敗會回退到 Tauri 並持久化（[shortcut/mod.rs](https://github.com/cjpais/Handy/blob/main/src-tauri/src/shortcut/mod.rs)、[settings.rs](https://github.com/cjpais/Handy/blob/main/src-tauri/src/settings.rs)）。啟動模式 `ShortcutActivation::{Toggle, PushToTalk, HoldOrToggle}`，`HoldOrToggle` 以 `hold_threshold_ms` 判斷是按住還是輕點（[settings.rs](https://github.com/cjpais/Handy/blob/main/src-tauri/src/settings.rs)）。
- Whispering 則刻意**只用 Tauri 外掛的組合鍵**（ADR-0117），macOS 的 CGEventTap 只拿來偵測輔助使用授權是否失效（[keyboard/mod.rs](https://github.com/epicenter-md/epicenter/blob/main/apps/epicenter/src-tauri/src/keyboard/mod.rs)）。

### 2.3 Rust（`windows` crate）低階鉤子骨架：Right-Ctrl push-to-talk、忽略自家注入、吞 Caps Lock

```rust
use windows::Win32::Foundation::{LPARAM, LRESULT, WPARAM};
use windows::Win32::UI::WindowsAndMessaging::*;
use windows::Win32::UI::Input::KeyboardAndMouse::VK_RCONTROL;

static TX: OnceLock<std::sync::mpsc::Sender<(u32, bool)>> = OnceLock::new();

unsafe extern "system" fn ll_proc(code: i32, w: WPARAM, l: LPARAM) -> LRESULT {
    if code == HC_ACTION as i32 {
        let k = &*(l.0 as *const KBDLLHOOKSTRUCT);
        let injected = (k.flags.0 & LLKHF_INJECTED.0) != 0;      // 我們自己送的 Ctrl+V → 不處理
        let is_up = matches!(w.0 as u32, WM_KEYUP | WM_SYSKEYUP);
        if !injected && k.vkCode == VK_RCONTROL.0 as u32 {
            let _ = TX.get().map(|tx| tx.send((k.vkCode, !is_up)));  // 只做「送到 channel」，回呼必須 < 1000 ms
            return LRESULT(1);                                     // 吞掉，不讓目標程式看到 Right-Ctrl
        }
    }
    CallNextHookEx(None, code, w, l)
}

fn hook_thread() {               // 專用執行緒：安裝鉤子 + message loop（文件要求）
    let _h = unsafe { SetWindowsHookExW(WH_KEYBOARD_LL, Some(ll_proc), None, 0) }.unwrap();
    let mut msg = MSG::default();
    while unsafe { GetMessageW(&mut msg, None, 0, 0) }.as_bool() {
        unsafe { TranslateMessage(&msg); DispatchMessageW(&msg); }
    }
}
```
重點：(1) 回呼內**不做任何 I/O、不鎖重量級 mutex**，避免 1000 ms 逾時被系統移除；(2) Caps Lock 當熱鍵時必須回傳 1 吞掉，否則會切換大小寫狀態；(3) 吞掉單一修飾鍵會讓「Right-Ctrl + C」這類組合失效，需要「按住超過閾值才視為 PTT、否則回放原鍵」的策略（Handy 的 `HoldOrToggle` 概念）。

---

## 3. Windows：音訊、權限、系統匣、簽章、安裝、更新、競品、ARM64

### 3.1 音訊擷取
- **WASAPI** 是 Windows 的核心 API：「enables client applications to manage the flow of audio data between the application and an audio endpoint device」，先取得 `IAudioClient`，再經 `GetService()` 拿 `IAudioCaptureClient` 讀取擷取緩衝（[wasapi.md](https://github.com/MicrosoftDocs/win32/blob/docs/desktop-src/CoreAudio/wasapi.md)）。
- **`cpal`**（Handy 0.16、Whispering 0.18.1）：Windows 預設 WASAPI、可選 ASIO；Linux 預設 ALSA（JACK/PipeWire/PulseAudio 可選，但「即使用 JACK/PipeWire/PulseAudio 也需要 ALSA」）；Android AAudio、iOS CoreAudio（[cpal](https://github.com/RustAudio/cpal)）。Handy 以 `host.default_input_device()` 列舉並自行重取樣到 16 kHz（`audio_toolkit/audio/{device,resampler}.rs`）。
- Whispering 示範了 `windows` crate 的 COM 陷阱：crate **不會替你初始化 COM**，所有 WinRT/COM 工作要在自己 `CoInitializeEx(COINIT_MULTITHREADED)` 的執行緒上做，絕不能在 Tauri 的 UI/STA 執行緒（[media/windows.rs](https://github.com/epicenter-md/epicenter/blob/main/apps/epicenter/src-tauri/src/media/windows.rs)）。它用 GSMTC（`Windows.Media.Control`）在錄音時暫停媒體播放，Linux 用 MPRIS over D-Bus（[media/linux.rs](https://github.com/epicenter-md/epicenter/blob/main/apps/epicenter/src-tauri/src/media/linux.rs)）— 這是個不錯的 UX 細節。
- **麥克風隱私設定**：⚠ 未能取得一手文件。記憶：Windows 10 1803 起「設定 > 隱私權 > 麥克風」有「允許桌面應用程式存取麥克風」總開關，關閉時 WASAPI 擷取會失敗或只得到靜音；應在首次錄音失敗時引導使用者到 `ms-settings:privacy-microphone`。

### 3.2 系統匣與自動啟動
Handy 使用 `tauri`（2.11.5）內建 tray、`tauri-plugin-autostart` 2.5.1、`tauri-plugin-single-instance` 2.3.2、`tauri-plugin-updater` 2.10.1（[Cargo.toml](https://github.com/cjpais/Handy/blob/main/src-tauri/Cargo.toml)）。這組依賴是目前 Tauri 聽寫工具的標準配置。

### 3.3 程式碼簽章與 SmartScreen
- Electron 官方文件（[code-signing.md](https://github.com/electron/electronjs.org-new/blob/main/docs/latest/tutorial/code-signing.md)）：2023 年 6 月起，舊式「軟體型 OV 憑證」不再提供保護，「Windows will treat your app as completely unsigned and display the equivalent warning dialogs」；Azure Artifact Signing（原 Trusted Signing）「gets rid of SmartScreen warnings」、是「the cheapest option」、免除 FIPS 140 Level 2 硬體金鑰需求，但「currently limited to developers in certain countries」。
- Azure 官方 GitHub Action 需 Windows runner、`Artifact Signing Certificate Profile Signer` 角色，且「Files must be signed with timestamping enabled in order for the signatures to be valid for longer than 3 days」— 這反映 Trusted Signing 憑證是**短效憑證**（[trusted-signing-action](https://github.com/Azure/trusted-signing-action)）。
- 同專案 issue 顯示：個人開發者身分驗證已開放但常卡關（#150「Address matching failed」、#151、#129 荷蘭個人續約），#81「Availability outside US and Canada」（2025-06）仍開啟（[issues](https://github.com/Azure/trusted-signing-action/issues?q=individual+validation)）。**台灣是否在可用清單內，本次無法確認。**
- ⚠ 價格（未能一手驗證）：Basic 約 US$9.99/月（含數千次簽章）、Premium 約 US$99.99/月。EV 憑證則通常每年數百美元且需硬體 token。
- Tauri 整合：社群工具 `trusted-signing-cli`（需 .NET 8、Azure CLI、Windows 11 SDK 10.0.26100+ 的 signtool；以 `AZURE_CLIENT_ID/SECRET/TENANT_ID` 等環境變數認證）可接在 Tauri 的 `signCommand`（[trusted-signing-cli](https://github.com/Levminer/trusted-signing-cli)）。Tauri 文件也指出「交叉編譯的 Windows 安裝檔需外部簽章工具」（[windows-installer.mdx](https://github.com/tauri-apps/tauri-docs/blob/v2/src/content/docs/distribute/windows-installer.mdx)）。.NET Foundation 的 `dotnet/sign` 目前只支援 Azure Key Vault（[dotnet/sign](https://github.com/dotnet/sign)）。
- SmartScreen 信譽：即使用 OV/EV 簽章，新憑證仍需累積下載量才不跳警告（EV 以往宣稱即時信譽，但 Microsoft 近年文件已淡化；⚠ 未一手驗證）。

### 3.4 安裝檔：MSIX vs NSIS/WiX
- Tauri v2（[windows-installer.mdx](https://github.com/tauri-apps/tauri-docs/blob/v2/src/content/docs/distribute/windows-installer.mdx)）：
  - **WiX/MSI** 只能在 Windows 上建置；**NSIS** 可在 Linux/macOS 交叉編譯，單一安裝檔含多語系。
  - 架構：x64、x86 兩者皆可；**ARM64 只有 NSIS 支援**（MSI/WiX ✗），NSIS 以 x86 模擬執行。
  - WebView2 模式：`downloadBootstrapper`（預設，+0 MB）、`embedBootstrapper`（+1.8 MB）、`offlineInstaller`（+127 MB）、`fixedRuntime`（+180 MB）、`skip`。
  - 安裝範圍：**預設 per-user 到 `%LOCALAPPDATA%`，不需系統管理員**；`perMachine` 需管理員。
- **MSIX**：⚠ 本次未能取得 MSIX 文件（路徑 404）。記憶：MSIX 需以受信任憑證簽章、安裝/移除乾淨、可用 `.appinstaller` 自動更新、是 Microsoft Store 的格式；desktop app 需 `runFullTrust`；低階鍵盤鉤子與 uinput 類行為在 MSIX 容器內一般可行但註冊表/檔案系統會被虛擬化。建議 v1 用 NSIS，Store 上架時再加 MSIX。

### 3.5 自動更新
- **Tauri updater**（[updater.mdx](https://github.com/tauri-apps/tauri-docs/blob/v2/src/content/docs/plugin/updater.mdx)）：靜態 JSON（GitHub Releases/CDN）或動態伺服器（支援 `{{current_version}}`、`{{target}}`、`{{arch}}`）；**簽章必要且無法關閉**（minisign，公鑰在 `tauri.conf.json`，私鑰走 `TAURI_SIGNING_PRIVATE_KEY`）；Windows `installMode`：`passive`（預設，進度列無互動）、`basicUi`、`quiet`（需管理員）；支援 Windows MSI/NSIS、macOS `.tar.gz`、**Linux 僅 AppImage**。
- **Velopack**：MIT；支援 C#、C++、JS、Rust；Windows/macOS/Linux；delta 更新、Setup.exe、`vpk` CLI、簽章支援、可從 Squirrel.Windows 自動遷移；自稱 Squirrel.Windows/Clowd.Squirrel 的繼任者（[velopack](https://github.com/velopack/velopack)）。
- **Squirrel.Windows**：per-user、無 UAC、delta 更新，但 README 明示「We are looking for help with maintaining this important project」（[Squirrel.Windows](https://github.com/Squirrel/Squirrel.Windows)）— 不建議新專案採用。

### 3.6 內建競品：Win+H 語音輸入與 Voice Access
⚠ 本次無法連到 Microsoft 支援頁與 Windows 部落格，以下為記憶、需驗證：Windows 11 的 Win+H 語音輸入支援含繁體中文在內的多種語言、具自動標點，傳統上依賴雲端辨識；Voice Access 於 22H2 推出、以裝置端辨識控制電腦與聽寫，初期僅英文、後續擴充語言；Windows Speech Recognition 已宣布淘汰由 Voice Access 取代。**對我們的意義**：純「把聲音變字」在 Windows 上是免費內建功能，產品差異化必須來自 LLM 後處理（格式、語氣、個人詞庫、中英夾雜）、跨裝置一致體驗與離線模型。

### 3.7 Windows ARM64（Snapdragon X）
- Tauri：ARM64 只能出 NSIS；需 Visual C++ ARM64 build tools（見 3.4）。
- **ONNX Runtime QNN EP**（[QNN-ExecutionProvider.md](https://github.com/microsoft/onnxruntime/blob/gh-pages/docs/execution-providers/QNN-ExecutionProvider.md)）：以 Qualcomm AI Engine Direct SDK 把 ONNX 圖轉成 QNN 圖；支援 Android 與 **Windows ARM64**；**HTP（NPU）後端只支援量化模型（8/16-bit）**，浮點模型須先量化；**不允許動態維度**；預建套件（Windows，ORT 1.18+）：NuGet `Microsoft.ML.OnnxRuntime.QNN`、pip `onnxruntime-qnn`（需 Python 3.11）；`provider_options=[{"backend_path": "QnnHtp.dll"}]`；支援 context binary 快取與混合精度；約 80 個運算子。
- Qualcomm AI Hub Models 列出 Whisper-Tiny 到 Large-V3-Turbo，支援 ONNX 與 QNN runtime，但註明「NOTE for Snapdragon X Elite and Snapdragon X2 Elite users: Only AMDx64 (64-bit) Python is supported on Windows. Installation will fail when using Windows ARM64 Python.」（[ai-hub-models](https://github.com/quic/ai-hub-models)）；AI Hub Apps 有一個 Windows Python Whisper 範例，runtime 標為 ONNX（[ai-hub-apps](https://github.com/quic/ai-hub-apps)）。
- 意涵：NPU 版 Whisper 需要靜態形狀、量化、分 encoder/decoder 的特製模型，工程成本高且 Qualcomm 工具鏈本身仍在 x64 模擬下跑；v1 應以 ARM64 原生 CPU 推論（whisper.cpp / sherpa-onnx 的 aarch64 build，⚠ 效能數字未驗證）為主。

---

## 4. Linux：X11 vs Wayland 的文字注入

### 4.1 X11
- **XTest**（`xdotool type`、enigo 的 `xdo`/`x11rb` 後端）成熟可靠。enigo 0.6.1 預設 feature 為 `x11rb`，另有 `xdo`、`wayland`、`libei`、`xdg_desktop` 等 feature（[Cargo.toml](https://github.com/enigo-rs/enigo/blob/main/Cargo.toml)）；README 註明 Wayland/libei 為實驗性、GNOME 的 libei 需要 portal 支援（[enigo](https://github.com/enigo-rs/enigo)）。enigo 在 Linux 的後端嘗試順序：`xdg_desktop`（需 tokio/smol）→ `wayland` → `x11`（x11rb/xdo）→ `libei`，全部失敗回 `NewConError::EstablishCon("no successful connection")`（[src/linux/mod.rs](https://github.com/enigo-rs/enigo/blob/main/src/linux/mod.rs)）。
- Handy 在 X11 的順序：`xdotool` → `ydotool` → enigo（[clipboard.rs](https://github.com/cjpais/Handy/blob/main/src-tauri/src/clipboard.rs) `try_direct_typing_linux`）。
- 已知問題：Handy README 指出 Linux 上錄音浮層（overlay）可能被視為作用中視窗而搶走焦點，導致貼上進錯視窗，因此 Linux 預設關閉 overlay（[README Linux Notes](https://github.com/cjpais/Handy#linux-notes)）。

### 4.2 Wayland：沒有通用注入 API，只有各桌面的「門」

| 路徑 | 機制 | GNOME (Mutter) | KDE (KWin) | wlroots (Sway/Hyprland) | 權限/備註 |
|---|---|---|---|---|---|
| `wtype` | `zwp_virtual_keyboard_v1`（wlr 協定，wlr-protocols 已於 2021 封存、新協定應走 wayland-protocols） | ✗ 不實作（wtype issues #45/#34/#29「Compositor does not support the virtual keyboard protocol」；Handy 註解「Mutter deliberately does not implement the virtual-keyboard-v1 protocol」） | ✗（Handy 註解：「no zwp_virtual_keyboard_manager_v1 support」） | ✓ | 支援 Unicode（README 範例 `wtype ∇⋅∇ψ = ρ`）（[wtype](https://github.com/atx/wtype)、[issues](https://github.com/atx/wtype/issues?q=gnome)、[wlr-protocols](https://github.com/swaywm/wlr-protocols)） |
| `kwtype` / KDE Fake Input | KDE 私有 fake-input 協定 | ✗ | ✓（Handy：「uses KDE Fake Input protocol, supports umlauts」） | ✗ | Handy `TypingTool::Kwtype`（[clipboard.rs](https://github.com/cjpais/Handy/blob/main/src-tauri/src/clipboard.rs)） |
| **libei / EIS via RemoteDesktop portal** | 應用程式經 `org.freedesktop.portal.RemoteDesktop` 取得 EIS socket，用 libei 送鍵盤事件 | ✓ GNOME 45 起「Remote desktop: add the ability to communicate via an EIS socket」（[xdg-desktop-portal-gnome NEWS](https://github.com/GNOME/xdg-desktop-portal-gnome/blob/main/NEWS)） | ✓ KWin 有 `eis` 外掛（[kwin/src/plugins](https://github.com/KDE/kwin/tree/master/src/plugins)）、portal 有 `remotedesktop.cpp`（[xdg-desktop-portal-kde/src](https://github.com/KDE/xdg-desktop-portal-kde/tree/master/src)） | 視 compositor | 使用者需在 portal 對話框核准（可持久化 session）；enigo `libei` feature 走此路但標為實驗性 |
| `ydotool` / `dotool` | Linux **uinput** 虛擬鍵盤，與顯示伺服器無關（X11/Wayland/TTY 皆可） | ✓ | ✓ | ✓ | 需 `/dev/uinput` 權限（root、`uinput`/`input` 群組或 udev 規則）、`ydotoold` 常駐；**不自動偵測鍵盤配置**；社群回報 **ydotool 不支援非 ASCII（西里爾、重音字）**（[ydotool](https://github.com/ReimuNotMoe/ydotool)、[Handy PR #557](https://github.com/cjpais/Handy/pull/557)）。`dotool` 可用 `DOTOOL_XKB_LAYOUT` 指定配置（⚠ sr.ht 無法連線，來自 Handy README：需 `input` 群組） |
| InputCapture portal | 擷取輸入（KVM 類用途） | 45 起有 | 有 | — | **只能擷取、不能注入**（[InputCapture.xml](https://github.com/flatpak/xdg-desktop-portal/blob/main/data/org.freedesktop.portal.InputCapture.xml)） |
| **IME 引擎（Fcitx5 / IBus）** | 以輸入法身分 `commitString` | ✓ | ✓ | ✓ | 使用者必須啟用/切換到該輸入法；需在 Wayland 用 text-input 協定（由框架處理） |

**CJK 的額外陷阱**：uinput/虛擬鍵盤路徑送的是「鍵碼」，中文字沒有鍵碼，`ydotool type` 會對非 ASCII 失效；`wtype` 透過動態 keymap 可送任意 Unicode；libei 同樣是鍵碼層級。**因此在 Linux 上，中文聽寫的可靠做法是「剪貼簿 + Ctrl+V（只注入 3 個鍵碼）」或「IME commitString」**，而不是逐字打字。

### 4.3 GNOME Wayland 的剪貼簿問題（高風險）
Handy issue #1742（2026，Ubuntu 26.04 / GNOME 50.1 / Handy 0.9.3）：轉錄與熱鍵正常，但「A required Wayland protocol (ext-data-control, or wlr-data-control version 1) is not supported by the compositor」，**所有貼上方法都失敗**（[#1742](https://github.com/cjpais/Handy/issues/1742)）。原因是 Tauri 的 clipboard plugin（arboard → wl-clipboard-rs）在沒有視窗焦點時依賴 data-control 協定寫入剪貼簿，而 GNOME 不實作該協定。Handy 在 Wayland 上優先改呼叫 `wl-copy`（[clipboard.rs `write_text_to_clipboard`](https://github.com/cjpais/Handy/blob/main/src-tauri/src/clipboard.rs)），但 `wl-copy` 同樣依賴 data-control。相關 meta issue：[#1555「Wayland text insertion, hotkeys, and Flathub publication」](https://github.com/cjpais/Handy/issues/1555)、[#1549 GNOME Wayland 選到 wtype 後失敗無回退](https://github.com/cjpais/Handy/issues/1549)、[#1831 Ubuntu 24.04 Ctrl+V 靜默失敗](https://github.com/cjpais/Handy/issues/1831)。Handy README 甚至直接寫「Ubuntu 26.04：wtype 不能用，需安裝 ydotool 並設定 systemd user service」（[README](https://github.com/cjpais/Handy#linux-notes)；[PR #557 的 ydotoold.service 範例](https://github.com/cjpais/Handy/pull/557)）。

**可行解**：在 GNOME Wayland 上 (a) 走 RemoteDesktop portal + libei 送 Ctrl+V 鍵碼，剪貼簿改由「取得一次性焦點」或 GTK 的 `wl_data_device`（需最近的輸入 serial，⚠ 未驗證）寫入；或 (b) 乾脆走 IBus 引擎 `commit_text`，完全不碰剪貼簿與鍵碼。

### 4.4 Linux 全域熱鍵
- **X11**：`global-hotkey`（X11 only）或 XRecord（rdev）皆可。
- **Wayland 的正規解：`org.freedesktop.portal.GlobalShortcuts`**（[介面 XML](https://github.com/flatpak/xdg-desktop-portal/blob/main/data/org.freedesktop.portal.GlobalShortcuts.xml)）：`version` 目前 2；`CreateSession` → `BindShortcuts`（每個捷徑有 `id`、`description`、可選 `preferred_trigger`，portal 會跳對話框讓使用者確認/修改；每個 session 只能 bind 一次）→ `ListShortcuts`、`ConfigureShortcuts`（v2，開設定 UI）；訊號 `Activated`/`Deactivated`（含 timestamp）與 `ShortcutsChanged`。**`Activated`+`Deactivated` 讓 push-to-talk 可行。**
  - 後端：GNOME **48.rc「Add global shortcuts portal backend」**，49/50/51 持續修正（[NEWS](https://github.com/GNOME/xdg-desktop-portal-gnome/blob/main/NEWS)；`src/globalshortcuts.c` 存在）；KDE `src/globalshortcuts.cpp` 存在（[xdg-desktop-portal-kde](https://github.com/KDE/xdg-desktop-portal-kde/tree/master/src)）。wlroots 系需 `xdg-desktop-portal-hyprland` 等（⚠ 未驗證）。
  - Rust 綁定：`ashpd` 0.13（enigo 的依賴）有 `desktop::global_shortcuts` 模組（⚠ docs.rs 無法連線，模組 API 未逐一驗證）。
  - 限制：**不能綁單一修飾鍵**（trigger 用 XDG shortcut 格式）；GNOME < 48 無此 portal。
- **evdev 直讀**（handy-keys Linux 後端、whisper-writer 的 `EvdevBackend`）：不分 X11/Wayland，可做單鍵與 PTT，但需 `/dev/input` 讀取權限（udev `uaccess` 規則或 `input` 群組），且在 Flatpak 沙箱內不可行。whisper-writer 的後端選擇順序是 `[EvdevBackend, PynputBackend]`（[key_listener.py](https://github.com/savbell/whisper-writer/blob/main/src/key_listener.py)），文字輸出可選 `pynput`/`ydotool`/`dotool`（[input_simulation.py](https://github.com/savbell/whisper-writer/blob/main/src/input_simulation.py)、[config_schema.yaml](https://github.com/savbell/whisper-writer/blob/main/src/config_schema.yaml)）。
- **外部觸發**：Handy 提供 CLI 旗標與 Unix signal，讓使用者在桌面環境的快捷鍵設定裡綁 `handy --toggle`；注意 **SIGUSR1 被 WebKitGTK 內部使用**，Handy 已移除對它的監聽（[README](https://github.com/cjpais/Handy#linux-notes)）。這是 Wayland 上零權限、零相依的保底方案。

**ashpd GlobalShortcuts 用法草圖**（API 名稱依 portal 介面推定，⚠ 請對照 ashpd 0.13 原始碼）：
```rust
use ashpd::desktop::global_shortcuts::{GlobalShortcuts, NewShortcut};
let proxy = GlobalShortcuts::new().await?;
let session = proxy.create_session().await?;
let shortcuts = [NewShortcut::new("ptt", "按住說話").preferred_trigger(Some("CTRL+SPACE"))];
proxy.bind_shortcuts(&session, &shortcuts, None).await?;      // portal 跳對話框讓使用者確認
let mut on = proxy.receive_activated().await?;                  // Activated → 開始錄音
let mut off = proxy.receive_deactivated().await?;               // Deactivated → 停止並送出
```

### 4.5 IME 引擎路徑（Fcitx5 / IBus）
- **Fcitx5**：引擎繼承 `InputMethodEngine`（V2–V4 逐步加 `subModeIcon`、`invokeAction`、`virtualKeyboardEvent`），核心為 `virtual void keyEvent(const InputMethodEntry &entry, KeyEvent &keyEvent) = 0;`；插入文字用 `InputContext::commitString(const std::string &text)`，另有 `updatePreedit()`、`forwardKey()`、`surroundingText()` 與 `CapabilityFlag::CommitStringWithCursor`（[inputmethodengine.h](https://github.com/fcitx/fcitx5/blob/master/src/lib/fcitx/inputmethodengine.h)、[inputcontext.h](https://github.com/fcitx/fcitx5/blob/master/src/lib/fcitx/inputcontext.h)）。Fcitx5 支援 X11/Wayland 與 GTK/Qt IM module（[fcitx5](https://github.com/fcitx/fcitx5)）。
- **IBus**：引擎為 `IBusEngine` 子類，`gboolean (*process_key_event)(IBusEngine*, guint keyval, guint keycode, guint state)`，插入用 `void ibus_engine_commit_text(IBusEngine*, IBusText*)`，預編輯用 `ibus_engine_update_preedit_text(engine, text, cursor_pos, visible)`（[ibusengine.h](https://github.com/ibus/ibus/blob/main/src/ibusengine.h)）。GNOME 預設整合 IBus（⚠ 一般知識）。
- 設計：我們的 daemon 收到轉錄結果後，透過 D-Bus 通知自家 IM 引擎在**目前焦點的 InputContext** 上 `commitString`。好處：任何工具組、X11/Wayland、Flatpak 內都能插入、支援 surrounding text；代價：使用者得安裝並切到我們的輸入法（或我們做成 Fcitx5 addon 而非 IM，⚠ addon 能否對非自己的 IC commit 需驗證）、與現有中文輸入法（新酷音/Rime）並存的 UX。

Fcitx5 引擎骨架（C++）：
```cpp
class DictationEngine : public fcitx::InputMethodEngineV2 {
public:
  void keyEvent(const fcitx::InputMethodEntry&, fcitx::KeyEvent& ev) override {
    if (ev.key().check(FcitxKey_space, fcitx::KeyState::Ctrl)) { startOrStop(ev.inputContext()); ev.filterAndAccept(); }
  }
  void onTranscript(fcitx::InputContext* ic, const std::string& text) { ic->commitString(text); }
};
FCITX_ADDON_FACTORY(DictationEngineFactory)   // 搭配 dictation.conf / dictation-addon.conf 註冊
```

### 4.6 音訊：PipeWire / PulseAudio
cpal 在 Linux 預設 ALSA，PipeWire/PulseAudio 經 ALSA 外掛相容，或啟用對應 feature 原生整合（[cpal](https://github.com/RustAudio/cpal)）。Flatpak 內需 `--socket=pulseaudio`（PipeWire 提供 Pulse 相容層）（[sandbox-permissions](https://github.com/flatpak/flatpak-docs/blob/master/docs/sandbox-permissions.rst)）。

### 4.7 打包
- **AppImage**：Tauri updater 在 Linux 唯一支援的格式；建議在 Ubuntu 22.04/Debian 12 等舊基線建置以避免 glibc 問題；ARM AppImage 不能交叉編譯；`bundleMediaFramework` 會把 gstreamer 塞進去（[appimage.mdx](https://github.com/tauri-apps/tauri-docs/blob/v2/src/content/docs/distribute/appimage.mdx)）。
- **Flatpak**：Tauri 範例 finish-args：`--socket=wayland`、`--socket=fallback-x11`、`--device=dri`、`--share=ipc`，runtime `org.gnome.Platform 47`（[flatpak.mdx](https://github.com/tauri-apps/tauri-docs/blob/v2/src/content/docs/distribute/flatpak.mdx)）。沙箱內 **沒有 `/dev/uinput`、不能讀 `/dev/input`、不能呼叫外部 `xdotool`/`wtype`**（除非 `--device=all` 與 `--talk-name=org.freedesktop.Flatpak` 逃逸，審核不會過），**只剩 portal（GlobalShortcuts、RemoteDesktop/EIS）與 IME 路徑**。Handy 的 Flathub 上架因此被列為 meta issue（#1555）。
- **deb/rpm**：最直接，但 Tauri updater 不處理；可配合發行版套件庫或自寫下載器。
- **udev 規則**：若採 evdev/uinput，隨 deb/rpm 安裝 `/etc/udev/rules.d/70-ourapp-uaccess.rules`（handy-keys 建議）。

---

## 5. 三個開源專案的作法速覽（含檔案引用）

| 專案 | 版本/時間 | 熱鍵 | Windows 注入 | Linux 注入 | 備註 |
|---|---|---|---|---|---|
| **Handy**（Rust/Tauri 2.11.5） | main @ 2026-09-28 | `handy-keys` 0.3.4（Win/mac 預設）或 `tauri-plugin-global-shortcut`（Linux 預設）；Toggle/PTT/HoldOrToggle | 剪貼簿 + Ctrl+V（enigo，VK_V 0x56，Ctrl 保持 100 ms）；debug 旗標啟用 receipt-sequenced paste（`WM_RENDERFORMAT`）；可選 `Direct`（`enigo.text()`） | X11：xdotool→ydotool→enigo；Wayland：kwtype(KDE)→wtype(非 GNOME/KDE)→dotool→ydotool→enigo；剪貼簿先試 `wl-copy` | [input.rs](https://github.com/cjpais/Handy/blob/main/src-tauri/src/input.rs)、[clipboard.rs](https://github.com/cjpais/Handy/blob/main/src-tauri/src/clipboard.rs)、[paste_tx/windows.rs](https://github.com/cjpais/Handy/blob/main/src-tauri/src/paste_tx/windows.rs)、[shortcut/handy_keys.rs](https://github.com/cjpais/Handy/blob/main/src-tauri/src/shortcut/handy_keys.rs)、[utils.rs](https://github.com/cjpais/Handy/blob/main/src-tauri/src/utils.rs)（以 `WAYLAND_DISPLAY`/`XDG_SESSION_TYPE`/`XDG_CURRENT_DESKTOP` 判斷桌面） |
| **Whispering**（epicenter monorepo，Rust/Tauri） | main，2026 | 只用 `tauri-plugin-global-shortcut` 組合鍵（ADR-0117） | 剪貼簿 + Ctrl+V（enigo 0.5，VK_V），50/100 ms 固定延遲，失敗回 `LeftOnClipboard` | 同上，Linux 用 `Key::Unicode('v')` | [delivery.rs](https://github.com/epicenter-md/epicenter/blob/main/apps/epicenter/src-tauri/src/delivery.rs)、[clipboard.rs](https://github.com/epicenter-md/epicenter/blob/main/apps/epicenter/src-tauri/src/clipboard.rs)、[keyboard/mod.rs](https://github.com/epicenter-md/epicenter/blob/main/apps/epicenter/src-tauri/src/keyboard/mod.rs) |
| **whisper-writer**（Python） | 2024-08-24（已久未更新） | `evdev`（優先）或 `pynput` | `pynput` 逐字打字 | `pynput`/`ydotool`/`dotool` 逐字打字 | [key_listener.py](https://github.com/savbell/whisper-writer/blob/main/src/key_listener.py)、[input_simulation.py](https://github.com/savbell/whisper-writer/blob/main/src/input_simulation.py) |

---

## 6. 對我們的設計意涵

1. **注入層做成「策略 + 偵測 + 降級」的狀態機，而非單一呼叫**。順序：偵測前景視窗（程序名、完整性等級、是否終端/Electron）→ 選策略（預設剪貼簿收據貼上；終端用 Ctrl+Shift+V/Shift+Insert；使用者可按程式覆寫）→ 執行 → 驗證（收據、剪貼簿序號）→ 降級（留在剪貼簿 + 浮層提示「已複製，按 Ctrl+V 貼上」）。Whispering 的 `WriteTextOutcome` 與 Handy 的 `PasteMethod` 列舉是好的 API 形狀。
2. **把 Handy 的 receipt-sequenced paste 當作 Windows 一等公民實作**（不是 debug 旗標），並加上 `ExcludeClipboardContentFromMonitorProcessing`（⚠）與完整格式快照。
3. **熱鍵在 Windows 用自家低階鉤子**（或直接依賴 `handy-keys`），回呼內只投遞到 channel；用 `dwExtraInfo` 標記自家 `SendInput` 並以 `LLKHF_INJECTED` 過濾；支援 Right-Ctrl/Caps Lock 單鍵與 HoldOrToggle。`RegisterHotKey` 只留作「無鉤子模式」備援。
4. **Linux 必須分三種 profile**：X11（xdotool/XTest + X11 hotkey）、KDE Wayland（portal GlobalShortcuts + fake-input/EIS）、GNOME Wayland（portal GlobalShortcuts（GNOME ≥ 48）+ RemoteDesktop/EIS，或 IBus 引擎）。**GNOME Wayland 不要依賴剪貼簿寫入**。偵測方式沿用 Handy 的環境變數判斷。
5. **認真評估「IME 引擎」作為跨平台第二階段**：Windows TSF 與 Linux Fcitx5/IBus 是唯一能在 UWP、Flatpak、Wayland 全部可靠插入並拿到 surrounding text 的路徑；但實作成本高（COM DLL、簽章、使用者切換 IM），應在 v1 用剪貼簿路徑驗證市場後再投入。
6. **中文（CJK）不要走鍵碼逐字打字**：Windows 用 `KEYEVENTF_UNICODE` 可以，但 Linux 的 uinput/libei/ydotool 都是鍵碼層級，中文會失敗；一律以剪貼簿或 IME 承載文字，鍵碼只用來送 Ctrl+V。
7. **簽章與地區風險要在第一週釐清**：確認台灣是否能申請 Azure Artifact Signing（個人或公司）；若不能，預算一張 OV/EV 憑證（硬體 token 或雲端 HSM）並接受 SmartScreen 信譽累積期。CI 用 Windows runner 跑簽章（Action 限 Windows）。
8. **安裝/更新**：Tauri NSIS per-user + updater（minisign 金鑰離線保管）；Linux 出 AppImage（updater）+ deb；Flatpak 延後到 portal 路徑穩定後。ARM64 Windows 只出 NSIS。
9. **音訊**：cpal + 自行重取樣 16 kHz 單聲道；錄音時用 GSMTC/MPRIS 暫停媒體（Whispering 作法）；首次失敗引導隱私設定。
10. **產品差異化**不在「辨識」本身（Win+H 免費），而在 LLM 後處理與跨裝置一致性；桌面端要把「可靠插入到任何視窗」做到比 Win+H 更穩，這正是上述所有工程投入的理由。

---

## 7. 各 OS 建議方案與風險清單

### 7.1 Windows（v1）
- 技術棧：Rust + Tauri 2（或 Rust core + 任意 UI）；`windows` crate 做鉤子與剪貼簿；`cpal` WASAPI；`handy-keys` 或自寫 `WH_KEYBOARD_LL`。
- 注入：剪貼簿收據貼上（主）→ `KEYEVENTF_UNICODE`（短文本/使用者指定）→ 留在剪貼簿（elevated/失敗）。
- 散佈：NSIS per-user（x64 + ARM64）+ Tauri updater；Artifact Signing 或 OV/EV 憑證。
- 風險：
  1. **UIPI**：對管理員視窗無法注入且無錯誤碼 → 需主動偵測並提示。
  2. **低階鉤子 1000 ms 逾時被移除** → 回呼零 I/O；可加 watchdog 定期重裝鉤子。
  3. **剪貼簿管理工具/防毒搶讀** → 收據必須在貼上鍵之後才算。
  4. **SmartScreen / 簽章地區限制**（台灣可用性未確認）。
  5. **終端/特定程式 Ctrl+V 行為差異**（Windows Terminal 尾端空白問題 #1018）。
  6. **反作弊/企業端點防護**可能把低階鉤子 + SendInput 視為鍵盤側錄；需簽章與明確說明。

### 7.2 Linux（v1 以 X11 + KDE/GNOME Wayland 盡力支援）
- X11：enigo(x11rb) + global-hotkey；剪貼簿 + Ctrl+V。
- Wayland：GlobalShortcuts portal（GNOME ≥ 48、KDE）做熱鍵，`Activated/Deactivated` 做 PTT；注入順序 KDE → fake-input/EIS、GNOME → RemoteDesktop EIS（使用者一次授權）、wlroots → wtype；全部不行 → 通知 + 留在剪貼簿；提供 CLI/D-Bus 觸發讓使用者自綁快捷鍵。
- 打包：AppImage + deb（附 udev 規則，可選）；Flatpak 後續。
- 風險：
  1. **GNOME Wayland 剪貼簿寫入失敗**（無 data-control）→ 可能需要 IBus 引擎才能真正解決。
  2. **portal 授權對話框**（RemoteDesktop/GlobalShortcuts）造成首次體驗摩擦；session 持久化支援度依桌面版本而異（GNOME 51 才給 InputCapture 持久化）。
  3. **ydotool 非 ASCII 失效、不認鍵盤配置**；dotool 需 `input` 群組。
  4. **桌面碎片化**：Hyprland/Sway/COSMIC 各自 portal 後端成熟度不一。
  5. **WebKitGTK 相關怪異行為**（SIGUSR1 衝突、overlay 搶焦點、`gtk-layer-shell` 相依）。
  6. **Flatpak 幾乎只能走 portal/IME**，若要上 Flathub 需提早設計。

### 7.3 共通
- 以 Handy 的設定模型為藍本：`PasteMethod`、`TypingTool`、`ShortcutActivation`、`KeyboardImplementation`，讓進階使用者能逐程式覆寫。
- 建立「相容性測試矩陣」自動化：Notepad、Word、Chrome/Electron、VS Code、Windows Terminal、conhost、UWP（Mail/Notepad Store 版）、以管理員執行的 Notepad、RDP 用戶端；Linux 端 GNOME/KDE/Sway × GTK4/Qt6/Electron/終端。

---

## 8. 未解問題（需後續驗證）

1. **Azure Artifact (Trusted) Signing 的台灣可用性、個人身分驗證流程與目前月費**（本次無法連 learn/azure.microsoft.com；issue #81 顯示美加以外仍在請求中）。
2. **Windows 11 Win+H 語音輸入與 Voice Access 的語言清單（繁中？）、是否離線、Copilot+ PC NPU 版本差異**。
3. `KEYEVENTF_UNICODE`（`VK_PACKET`）在 **RDP 用戶端、Citrix、遊戲、舊式 Win32 控制項**的實際行為；是否有程式只處理 `WM_KEYDOWN` 而忽略 `VK_PACKET`。
4. Windows **`ExcludeClipboardContentFromMonitorProcessing` / `CanIncludeInClipboardHistory`** 格式對剪貼簿歷史（Win+V）與第三方管理工具的實際效果。
5. **MSIX 封裝下**低階鍵盤鉤子、`SendInput`、以及 per-user 自動更新的限制（文件未取得）。
6. GNOME Wayland 在**沒有 data-control** 時，桌面應用是否能用 GTK/`wl_data_device` 在無焦點狀態寫入剪貼簿；或 RemoteDesktop/EIS session 能否持久化而不每次跳對話框。
7. **Fcitx5 addon（非 IM）能否對當前 InputContext 直接 `commitString`**，讓使用者不必切換輸入法；IBus 是否有等價機制。
8. `ashpd` 0.13 的 `global_shortcuts` 模組實際 API 與在 Hyprland/Sway portal 的相容性。
9. **Whisper 在 Snapdragon X NPU（QNN EP）的可用模型與延遲**；是否值得為 ARM64 做 NPU 路徑，或 CPU 已足夠（需實測 whisper.cpp/sherpa-onnx aarch64）。
10. `handy-keys` 在 Windows 上處理 **Fn 鍵、Caps Lock 吞鍵後的 LED 狀態、以及與其他鉤子（PowerToys、AutoHotkey）共存**的行為。
11. Windows 麥克風隱私總開關對桌面 app 的具體錯誤碼（WASAPI 回傳什麼），以便做精準引導。
