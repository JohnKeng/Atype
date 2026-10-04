# AI 語音聽寫 / 語音鍵盤：競品與開源生態地圖（2026-10）

> 研究日期：2026-10-01。優先引用 2025–2026 來源；標註「⚠ 可能過時」者表示來源較舊或僅來自第三方轉述。
> 注意：本次研究環境無法直接連到 wisprflow.ai、typeless.com、superwhisper.com、tryvoiceink.com、talonvoice.com、apps.apple.com、blogs.windows.com 等官方頁面（被 egress proxy 擋下），這些產品的定價與功能主要來自搜尋摘要與第三方整理站（getvoibe、spokenly、usevoicy、laxis 等多為競品部落格，有利益衝突，數字請在動工前再對照官方頁面一次）。開源專案部分則直接讀了 GitHub README 與原始碼（raw.githubusercontent.com）。

---

## 0. 執行摘要（Executive Summary）

1. **市場已經收斂成一個標準產品形態**：全域熱鍵（按住說話或切換）→ 錄音 → STT → LLM 清理（去填充詞、自我修正、依 app 調整語氣）→ 把文字貼進目前焦點的 app。Wispr Flow、Typeless、Willow、Aqua Voice、Monologue、Superwhisper、VoiceInk 全部都是這個形狀；差異在「本地 vs 雲端」、「平台覆蓋」、「定價」與「上下文感知的深度」。
2. **定價已經高度同質化**：Pro 幾乎都是 **US$12/月（年繳）或 $15/月（月繳）**，免費層 **每週 1,000–2,000 字**（Typeless 例外，8,000 字/週；Typeless 月繳 $30 是全場最貴）。本地優先的 Superwhisper（$8.49/月或 $249.99 終身）與 VoiceInk（$25–49 終身買斷）用「一次付清、資料不離機」打差異化。
3. **平台覆蓋是護城河之一**：只有 Wispr Flow 與 Typeless 同時覆蓋 macOS/Windows/iOS/Android；**沒有任何主流商業產品支援 Linux**（Wispr Flow 的 Linux 僅在 waitlist）。這是開源專案（Handy、Whispering、OpenWhispr）的主場。
4. **平台廠商正在往上吃**：Apple iOS 26 / macOS 26 推出全新 on-device `SpeechAnalyzer`/`SpeechTranscriber` API（WWDC25 session 277，本地、長句、低延遲）；Windows 在 Copilot+ PC 上推出 **Fluid Dictation**（on-device SLM 自動修正文法/標點/填充詞，2025-09 進 Insider，2026-05 加西/法語）；Google 於 2026-05-12 推出 Gboard **Rambler**（Gemini 驅動去填充詞、句中修正）。「只是把 Whisper 包起來」的產品空間正在被壓縮。
5. **開源最值得抄的是 Handy（Rust + Tauri 2，MIT，32.5k★，v0.9.7 於 2026-09-18 發佈）**：它把三個最難的桌面工程問題都解掉並開源：(a) 跨平台全域熱鍵（獨立 crate `handy-keys`，支援純修飾鍵熱鍵、macOS Secure Event Input 偵測與 Carbon fallback）；(b) 可靠貼上（`paste_tx` 模組用 Windows `WM_RENDERFORMAT` / macOS `provideDataForType` 的「剪貼簿讀取回執」決定何時還原剪貼簿）；(c) Linux X11/Wayland 的 xdotool/wtype/dotool/ydotool/kwtype 工具鏈選擇邏輯；外加本地推論 crate `transcribe-cpp`（Whisper/ggml）與 `transcribe-rs`（ONNX：Parakeet、Moonshine、SenseVoice 等）。
6. **手機端的硬限制決定架構**：iOS 自訂鍵盤 extension **不能存取麥克風**，且記憶體上限約 50–60 MB（被 jetsam 砍掉時無 crash log）。所有 iOS 聽寫鍵盤（Wispr Flow、Dictus、WhisperBoard）都採「鍵盤當遙控器 → 跳到主 app 錄音/辨識 → 經 App Group 把文字回傳鍵盤」。Android 則有兩條路：**IME（`InputMethodService` + `InputConnection.commitText`）** 或 **Accessibility Service + 懸浮泡泡**（Wispr Flow Android 用後者）。
7. **對繁中使用者的機會**：Superwhisper iOS 被回報 80–90% 時間輸出簡體；Apple 聽寫是逐字稿不去填充詞；Handy 的 Cargo.toml 已經引入 `ferrous-opencc`（OpenCC）。「繁中（台灣用語）+ 中英夾雜 + 程式術語」是一個現成產品都做不好的縫隙。

---

## 1. 商業競品一覽

### 1.1 總表

| 產品 | 平台 | 定價（2026） | STT 架構 | 亮點 | 弱點 |
|---|---|---|---|---|---|
| **Wispr Flow** | macOS / Windows / iOS / Android（Linux 僅 waitlist） | Free 2,000 字/週（iPhone 1,000 字/週、Android 無上限）；Pro $15/月或 $12/月年繳；Teams $10–12/人/月（3 席起） | 雲端 ASR + 多層 LLM | 跨平台單一帳號、Context Awareness（透過 accessibility API 讀游標附近文字，非截圖）、2026-08 完成 $280M B 輪、估值 $2B | 純雲端；無 Linux；免費層字數小 |
| **Typeless** | macOS / Windows / iOS / Android | Free 8,000 字/週；Pro $12/月年繳（$144/年）、月繳 $30 | 雲端（LLM 用 OpenAI 等第三方，宣稱零保留） | 平台最廣、免費層最大、語氣依 app 自適應、個人字典 | 月繳最貴；單次 session 6 分鐘上限；2025-11 逆向分析指出音訊送 AWS us-east-2 並收集瀏覽 URL/視窗標題，與「on-device」行銷用語有落差 |
| **Superwhisper** | macOS / Windows（有穩定性回報）/ iOS；Android 為公開看板最高票需求（198 票）未出 | Free（小型本地模型無限用）；Pro $8.49/月、$84.99/年、$249.99 終身；學生 6 折 | **本地優先**：whisper.cpp（Tiny→Large V3 Turbo）、Parakeet V2/V3；Pro 可用雲端模型與 BYOK | 「Modes」架構（每個 mode 綁 STT 模型 + LLM + system prompt + actions）；SOC 2 Type II | iOS 版繁中輸出常變簡體；Windows 版不穩 |
| **MacWhisper** | macOS | Gumroad €59 終身 Pro；App Store 版 $6.99/月、$29.99/年、$99.99 終身 | 本地 whisper.cpp + 雲端選項 | 檔案轉錄為主（批次、字幕、說話者分離）；Gumroad 版附系統級即時聽寫 | 聽寫不是核心，手機無 |
| **Willow Voice** | macOS / iOS / Windows（2026-01 新增） | Free 2,000 字/週；Individual $15/月或 $144/年；Team $10/人/月 | 雲端 | 專業用戶定位 | 無 Android/Linux |
| **Aqua Voice** | macOS（Apple Silicon + Intel）/ Windows 10/11 / iOS（2026-04） | Free 一次性 1,000 字；Pro $8/月年繳（$96/年）、$10/月月繳 | 雲端自研 **Avalon** 模型（49 語言），主打程式術語 97.4% | 實測延遲：標準 965 ms、Instant Mode ≈450 ms | 無 Android；免費額度一次性 |
| **VoiceInk** | macOS 15+ | Solo $25 / Personal $39 / Extended $49 **終身買斷**；GPL-3 原始碼可自行編譯免費 | 本地：whisper.cpp、transcribe.cpp（GGUF）、SenseVoice Small、Parakeet（經 FluidAudio）；另有雲端 provider | Power Mode 依 app/URL 自動切 profile（最多 10 組）；螢幕上下文 AI 增強 | Mac only |
| **Monologue**（Every） | macOS / iOS | Free 1,000 字 + 10 則筆記；Pro $15/月或 $144/年；早鳥 $10/月；Every bundle $30/月 | 本地離線轉錄 + 上下文格式化 | 跟 Every 其他 AI app 綁售 | Apple only、無終身方案 |
| **Voicy** | macOS / Windows / 瀏覽器擴充 / iOS / Android | $8.49/月、$82/年、$260 終身 | 雲端 | 平台廣、含檔案轉錄 | 純雲端 |
| **Talon** | macOS / Windows / Linux(X11，公開版將移除) | 公開版免費；Patreon $5 起、beta 層約 $25/月 | **本地** Conformer（2025-12 beta 出 Conformer D，準確度 +~20%） | 語音「控制」整台電腦、Python 腳本、眼動追蹤；無障礙社群首選 | 不是聽寫產品，學習曲線高 |
| **Dragon Professional** | Windows only（Mac 版 2018-10 停產） | v16 $699.99 一次買斷 | 本地（Nuance / Microsoft 2022 併購） | 企業/醫療、客製詞彙 | 貴、無 Mac/手機 |
| **Apple 內建聽寫** | macOS / iOS | 免費 | 本地為主（Tahoe 擴大 on-device 語言與長度） | 系統整合、Tahoe 加智慧標點、選單列指示 | 逐字稿、不去填充詞、混語句子表現差、某些欄位不可用 |
| **Windows Voice Typing (Win+H) / Voice Access** | Windows 10/11 | 免費 | Win+H 需連網；Voice Access 離線 on-device；Copilot+ PC 加 **Fluid Dictation**（on-device SLM） | Fluid Dictation 自動修文法/標點/填充詞 | Fluid Dictation 需 40+ TOPS NPU；語言僅英/西/法 |
| **Gboard 語音輸入** | Android | 免費 | 本地（離線語言包 50–100 MB）+ 雲端；**Rambler**（Gemini，2026-05-12 發表） | 去填充詞、句中修正、多語 code-switching | 先限 Pixel/Samsung；第三方鍵盤無法叫用 Google voice |

來源：
- Wispr Flow 定價/平台：https://www.getvoibe.com/resources/wispr-flow-pricing/ 、https://spokenly.app/blog/wispr-flow-pricing 、https://www.laxis.com/blog/wispr-flow/ ；募資：https://en.wikipedia.org/wiki/Wispr_Flow 、https://pulse2.com/wispr-25-million-series-a-extension/amp/ ；Linux 狀態：https://voicekeyboardpro.com/blog/wispr-flow-linux.html 、https://usevoicy.com/blog/wispr-flow-alternative-for-linux
- Typeless：https://www.getvoibe.com/resources/typeless-pricing/ 、https://usevoicy.com/blog/typeless-pricing 、https://spokenly.app/blog/typeless-review 、https://www.getvoibe.com/resources/typeless-privacy-issues/ 、https://x.com/typelessdotcom/status/1965243454331761036 、https://www.typeless.com/data-controls
- Superwhisper：https://www.getvoibe.com/resources/superwhisper-pricing/ 、https://spokenly.app/blog/superwhisper-pricing 、https://www.getvoibe.com/resources/superwhisper-platform-support/ 、https://superwhisper.com/docs/models/voice 、繁簡問題：https://superwhisper.userjot.com/board/p/ios-app---traditional-chinese-v-s-simplified-chinese
- MacWhisper：https://www.getvoibe.com/resources/macwhisper-pricing/ 、https://lumevoice.com/blog/macwhisper-pricing-2026/
- Willow：https://www.getvoibe.com/resources/willow-voice-pricing/ 、https://www.getvoibe.com/resources/willow-voice-review/
- Aqua Voice：https://www.getvoibe.com/resources/aqua-voice-pricing/ 、https://spokenly.app/blog/aqua-voice-review 、https://www.getvoibe.com/resources/aqua-voice-review/
- VoiceInk 定價：https://tryvoiceink.com/pricing 、https://www.getvoibe.com/resources/voiceink-pricing/
- Monologue：https://www.getvoibe.com/resources/monologue-pricing/
- Voicy：https://usevoicy.com/blog/voicy-pricing
- Talon：https://www.stork.ai/en/talon-voice 、https://www.patreon.com/posts/conformer-now-in-49562777 、https://talon.wiki/Resource%20Hub/Speech%20Recognition/speech%20engines/
- Dragon：https://www.getvoibe.com/resources/dragon-pricing/ 、https://www.theregister.com/2018/10/30/mac_users_burned_after_nuance_drops_dragon_speech_to_text_software/
- Apple 聽寫 / Tahoe：https://www.yaps.ai/blog/macos-tahoe-dictation-review-2026 、https://bossai.tech/blog/remove-filler-words
- Windows Fluid Dictation：https://blogs.windows.com/windows-insider/2025/09/05/announcing-windows-11-insider-preview-build-26120-5790-beta-channel 、https://www.elevenforum.com/t/enable-or-disable-fluid-dictation-in-voice-typing-on-windows-11.42286/ 、https://www.getvoibe.com/resources/how-to-use-dictation-windows/
- Gboard Rambler：https://9to5google.com/2026/05/12/gemini-intelligence-announcement/ 、https://androidauthority.com/gboard-rambler-gemini-intelligence-3665653 、離線語言包：https://www.yaps.ai/blog/voice-typing-android-without-google

### 1.2 幾個值得深讀的商業設計細節

**Wispr Flow 的 iOS 架構（我們手機端必須照抄的模式）**：iOS 第三方鍵盤被沙盒化、不能碰麥克風，所以 Flow 鍵盤上的「Start Flow」會跳到主 app、開啟一段「Flow Session」（可設 5 分鐘 / 15 分鐘 / 1 小時 / 永不自動結束的麥克風授權窗），再跳回原 app；之後鍵盤上的麥克風鈕才能錄音。鍵盤需要 Full Access。還可綁 iPhone Action Button。來源：https://9to5mac.com/2025/06/30/wispr-flow-is-an-ai-that-transcribes-what-you-say-right-from-the-iphone-keyboard/ 、https://docs.wisprflow.ai/articles/4500510662-set-up-the-action-button-for-flow-on-iphone 、https://developer.apple.com/forums/thread/800500

**Wispr Flow 的 Android 架構**：不是（只）做 IME，而是「懸浮泡泡 overlay + Accessibility Service」把文字塞進任何有焦點的 app；另也提供 Flow Keyboard（IME）。Android 版 2026 年初推出。來源：https://zackproser.com/blog/wisprflow-android-setup-guide-2026 、https://docs.wisprflow.ai/articles/3152211871-setup-guide

**Wispr Flow 的 Context Awareness**：文件描述為透過 accessibility API 讀取游標周圍有限文字，不是截圖；用於判斷 code vs email 並調整格式。來源：https://www.laxis.com/blog/wispr-flow/

**Typeless 的隱私爭議**：2025-11 一則 X 上的逆向分析指出音訊送往 AWS us-east-2，且除語音外還收集瀏覽 URL 與焦點視窗標題；Typeless 回應是「零保留」協議（與 OpenAI 等第三方）。「on-device」指的是歷史紀錄儲存，不是辨識。對我們的啟示：**要嘛真的本地，要嘛行銷用語要誠實**，否則會被社群抓包。來源：https://www.getvoibe.com/resources/typeless-privacy-issues/ 、https://weesperneonflow.ai/en/blog/2026-06-11-typeless-review-cloud-dictation-2026/

**Superwhisper 的 Modes**：每個 mode = 一個 STT 模型 + 一個 LLM + system prompt + 一組 actions，依情境（coding / email / chat）切換。這是「上下文感知」最直覺的產品化方式，VoiceInk 的 Power Mode（依 app bundle id / 瀏覽器 URL 自動切 profile）是同一想法的自動化版本。來源：https://www.aiwiki.ai/wiki/superwhisper/raw 、https://www.getvoibe.com/resources/voiceink-review/

**Aqua Voice 的延遲數字**：是目前唯一公開「end-of-speech → 文字出現」量測的競品：標準 965 ms、Instant Mode ≈450 ms（第三方實測）。這可當我們的 KPI 基準。來源：https://spokenly.app/blog/aqua-voice-review

### 1.3 平台內建功能（我們的「免費競品」）

- **Apple `SpeechAnalyzer`（iOS 26 / macOS 26 / iPadOS / visionOS / tvOS / Catalyst 26）**：WWDC25 session 277。`SpeechTranscriber` 是全新 on-device 模型，專為長句、對話、即時低延遲設計；結果以 `AsyncStream` 回傳，`reportingOptions` 加 `.volatileResults` 可拿到即時暫定文字 + 最終文字；模型由 `AssetInventory` 系統層管理（不佔 app 體積與記憶體，`AssetInventory.assetInstallationRequest(supporting:)` 下載）；`DictationTranscriber` 是舊語言/舊機型的 fallback，**不需要使用者開啟 Siri 或鍵盤聽寫**。第三方基準：乾淨英文 WER 2.12%，比 Whisper Small（3.74%）好且在 M2 Pro 上快約 3 倍；Apple 自稱比 Whisper Large-v3 處理時間少 55%。來源：https://developer.apple.com/videos/play/wwdc2025/277/ 、https://www.gigazine.net/gsc_news/en/20250619-apple-speech-analyzer 、https://rohitraj.tech/en/notes/apple-speechanalyzer-vs-whisper-on-device-stt-2026 、https://dev.to/simple_memo/ios-26s-speechanalyzer-on-a-live-mic-the-5-things-the-docs-dont-tell-you-2ng5
  - ⚠ 未確認：`SpeechTranscriber.supportedLocales` 是否含 zh-Hant-TW（session 只說「these languages, with more to come」）。這是我們 Apple 平台「免費本地 STT」能否成立的關鍵。
- **Windows**：Win+H Voice Typing 需連網；Voice Access（22H2+）離線；**Fluid Dictation** 於 2025-09-05 Insider Build 26120.5790 進 Voice Access（Copilot+ PC、on-device SLM、全英文 locale），後擴到 Win+H 的 NPU 裝置，2026-05 加西/法語。需要 40+ TOPS NPU（Snapdragon X、Core Ultra 200V、Ryzen AI 300）。來源同上。
- **Gboard Rambler**：2026-05-12「Android Show: I/O Edition」發表，Gemini 驅動，去填充詞、句中修正、多語 code-switching，先 Pixel/Samsung。Gboard 本身仍可離線（語言包 50–100 MB）。注意：Gboard 與 Samsung 鍵盤被硬編碼只用 Google/Samsung 語音，第三方語音 IME 無法接入它們。來源：https://9to5google.com/2026/05/12/gemini-intelligence-announcement/ 、https://github.com/futo-org/voice-input

---

## 2. 開源專案深度分析（最重要）

### 2.1 比較表

| 專案 | 語言/框架 | 平台 | 音訊擷取 | 文字注入 | 熱鍵 | STT 引擎 | 授權 | 星數/活躍 | 可借用 |
|---|---|---|---|---|---|---|---|---|---|
| **Handy** (cjpais/Handy) | Rust + Tauri 2.11 + TS/Vite | macOS / Windows / Linux | `cpal` 0.16 + `rtrb` ring buffer + `rubato` 重取樣；VAD 用 Silero（`vad-rs`）與 `earshot` | 剪貼簿 + 模擬 Ctrl/Cmd+V（`enigo` 0.6）；`paste_tx` 回執式可靠貼上；Linux 直接打字（xdotool/wtype/dotool/ydotool/kwtype） | 自家 `handy-keys` 0.3.4（純修飾鍵、擋鍵、macOS Secure Input fallback）或 `tauri-plugin-global-shortcut` | `transcribe-cpp` 0.2.4（Whisper/ggml/GGUF，串流）、`transcribe-rs` 0.3.8（ONNX：Parakeet、Moonshine、SenseVoice、GigaAM、Canary、Cohere）；LLM 後處理走 OpenAI-compatible `chat/completions`；macOS 可用 Apple Intelligence（`apple_intelligence.rs` FFI） | MIT | 32.5k★ / 3k forks；v0.9.7 2026-09-18 | **幾乎整套桌面基礎設施** |
| **VoiceInk** (Beingpax/VoiceInk) | Swift / SwiftUI / AppKit | macOS 15+ | AVFoundation（Infrastructure/Audio） | Paste 模組 + Accessibility（AXUIElement）；Context 模組讀 app/URL | 可設鍵盤或滑鼠快捷鍵、push-to-talk | whisper.cpp、transcribe.cpp（GGUF）、SenseVoice Small、Parakeet（FluidAudio）；加雲端 providers | GPL-3.0 | 6.6k★ / 939 forks / 104 open issues | Power Mode 設計、螢幕上下文、Sparkle 更新；但 GPL 傳染 |
| **Whispering** (EpicenterHQ/epicenter, apps/whispering) | Svelte 5 + Tauri 2 + TS/Rust；`#platform/*` 條件模組 | 桌面（Epicenter 殼）+ 瀏覽器 SPA（目前無 hosted deploy） | 瀏覽器 MediaRecorder / 原生 | 桌面「native delivery when permitted」否則剪貼簿 | 只有桌面殼有全域熱鍵 | 雲端 BYOK：Groq、OpenAI Whisper、ElevenLabs；本地 GGUF 僅桌面 | AGPL-3.0-or-later | 4.8k★ | 「BYOK 零抽成」商業模型、瀏覽器/桌面共用 UI；AGPL 需注意 |
| **whisper-writer** (savbell) | Python 3.11 + PyQt5 | 跨平台（跑 Python） | `sounddevice` | `pynput` 模擬鍵入 | 自製 listener（`input_backend` 可換） | `faster-whisper` 本地或 OpenAI API（可改 base URL） | GPL-3.0 | 1.1k★；最後大更新 2024-05 ⚠ 已停滯 | 四種錄音模式（continuous / VAD / toggle / hold）的設定語意 |
| **Blurt** (AssemblyAI/blurt) | Swift 6, AppKit+SwiftUI；`BlurtEngine` 零依賴 package | macOS 15+ | `AVCaptureSession` 16 kHz mono PCM | 剪貼簿 + 合成 ⌘V，保存/還原原剪貼簿 | `CGEventTap` 偵測單一修飾鍵（預設右 ⌘），tap/hold/combo 狀態機有單元測試 | AssemblyAI `dictation.assemblyai.com/v1/transcribe/live`（串流，同一請求含伺服端 LLM 清理） | MIT | 56★（新） | 乾淨的 Swift 6 pipeline 範本；單修飾鍵狀態機 |
| **OpenSuperWhisper** (Starmel) | Swift（Apple Silicon only） | macOS | 多麥克風選擇（含 iPhone Continuity） | 未在 README 說明 | 全域組合鍵或單修飾鍵（左 ⌘、右 ⌥、Fn）、滑鼠鍵 | whisper.cpp 主、Parakeet 次；HF 下載 | MIT | 3.0k★ / 255 forks / 49 issues | 亞洲語言自動校正、hold-to-record |
| **OpenWhispr** | React 19 + Electron 41 + better-sqlite3 | macOS / Windows / Linux | — | — | — | whisper.cpp、sherpa-onnx（Parakeet）或雲端 | MIT | 2.2k–3.7k★（2025-06 創） | Electron 路線的參考（我們應避免） |
| **Buzz** (chidiwilliams) | Python + PyQt6 | macOS(Apple Silicon) / Win / Linux | 麥克風 live 錄音 | 無（轉錄工具） | — | Whisper、whisper.cpp、faster-whisper、HF transformers；CUDA/Vulkan | MIT | 21.8k★ | 檔案轉錄/字幕；非聽寫 |
| **Vibe** (thewh1teagle) | Rust + Tauri | macOS / Win / Linux（手機僅掃 QR 連線） | 麥克風、系統音訊 | 無（轉錄工具） | — | whisper.cpp（Vulkan/CoreML）、Parakeet TDT v3、Nemotron | MIT | 7.7k★ | Tauri + whisper.cpp 的 GPU build 腳本、CLI/HTTP API |
| **FUTO Voice Input** (futo-org/voice-input) | Kotlin + C++（whisper.cpp/ggml） | Android | 自家 `AudioRecognizer.kt` | `VoiceInputMethodService : InputMethodService`，`currentInputConnection.setComposingText()` 即時、`commitText()` 定稿、`switchToPreviousInputMethod()` 切回 | — | OpenAI Whisper via whisper.cpp（16 語言 ≥1,000 hr） | FUTO Source First 1.0（**非 OSI 開源**） | 334★ / 111 issues；重心已移到 FUTO Keyboard | **Android 語音 IME 的完整參考實作**（含 `RecognitionService`） |
| **FUTO Keyboard** (futo-org/android-keyboard) | Java/Kotlin + C++ | Android | 內建 voice input（`voiceinput-shared`） | LatinIME fork，IME | — | whisper.cpp | FUTO Source First 1.1 | 3.3k★ | 完整鍵盤 + 語音整合範例 |
| **Sayboard** (ElishaAz) | Kotlin | Android | 自錄 | IME + `RecognitionService` | — | Vosk（alphacephei 模型） | GPL-3.0 | 583★；F-Droid v4.2.1 2024-09 ⚠ 停滯 | Vosk 低資源路線；需 `QUERY_ALL_PACKAGES` 的坑 |
| **HeliBoard** | Kotlin/Java（OpenBoard/AOSP fork） | Android | 無內建語音 | IME | — | 交給 FUTO Voice Input 等外部 | GPL-3.0 | 6.2k★ | 證明「鍵盤 ↔ 語音 IME」解耦可行 |
| **AnySoftKeyboard** | Java | Android | 內建 voice input（呼叫系統） | IME | — | 系統 RECOGNIZE_SPEECH | Apache-2.0 | 3.4k★ / 9,044 commits | Apache 授權的 IME 骨架 |
| **Dictus** (getdictus/dictus-ios) | Swift | iOS 17+ / iPhone 12+ | 主 app 錄音（「audio bridge」） | 鍵盤 extension `insertText`；App Group `group.solutions.pivi.dictus` | — | WhisperKit（CoreML，tiny/base/small） | MIT | 37★ / 115 issues | **iOS 鍵盤 ≈50 MB 限制的實作解法** |
| **WhisperBoard** (fmachta) | Swift 5.9 | iOS | 鍵盤錄 PCM 存 App Group → Darwin notification → 主 app 轉錄 → 寫回 | 鍵盤 extension | — | WhisperKit | MIT | 1★ | 鍵盤端 <20 MB、主 app <150 MB 的記憶體策略、memory warning 卸模型 |
| **WhisperSource** (ksaitor) | Swift | iOS | 聲稱鍵盤內直接辨識、不需 Full Access ⚠ 與 Apple 麥克風限制矛盾，待驗證 | 鍵盤 extension | — | WhisperKit tiny(40MB)→medium(770MB) | GPL-3.0 | 9★ | 模型尺寸/機型對照 |
| macOS Swift 小工具群：pindrop、aparte、WhisperApp、SimpleWhisper、justwisper、local-whisper-dictation-macos | Swift/SwiftUI | macOS（多為 Apple Silicon） | AVFoundation | 多為剪貼簿 ⌘V | 單修飾鍵（右 ⌥、Fn） | WhisperKit、whisper.cpp、FluidAudio Parakeet v3、Apple Speech | 多 MIT | 數十～數百★ | SimpleWhisper 展示「Whisper / Parakeet / Apple Speech 三引擎切換 + fn 熱鍵 + 口述標點」 |

> 任務清單中提到的「Kavita」是開源電子書/漫畫伺服器，與語音輸入無關，推測是誤列，未納入。「Whisper Flow」在搜尋結果中幾乎都指向 Wispr Flow（同一產品的常見誤拼）。

來源：
- Handy：https://github.com/cjpais/Handy 、https://github.com/cjpais/Handy/releases 、原始碼 https://raw.githubusercontent.com/cjpais/Handy/main/src-tauri/Cargo.toml 、`src-tauri/src/{paste_tx/mod.rs,input.rs,clipboard.rs,shortcut/mod.rs,secure_input.rs,llm_client.rs,apple_intelligence.rs,settings.rs}`；crates：https://crates.io/crates/handy-keys 、https://crates.io/crates/transcribe-rs 、https://crates.io/crates/transcribe-cpp 、https://github.com/handy-computer/handy-keys
- VoiceInk：https://github.com/Beingpax/VoiceInk 、https://github.com/Beingpax/VoiceInk/tree/main/VoiceInk/Infrastructure/SystemIntegration
- Whispering/Epicenter：https://github.com/EpicenterHQ/epicenter 、https://raw.githubusercontent.com/EpicenterHQ/epicenter/main/apps/whispering/README.md 、https://epicenter.so/whispering/ 、https://slator.com/whispering-open%E2%80%91source-local%E2%80%91first-transcription-app/
- whisper-writer：https://github.com/savbell/whisper-writer
- Blurt：https://github.com/AssemblyAI/blurt 、https://www.assemblyai.com/blurt
- OpenSuperWhisper：https://github.com/Starmel/OpenSuperWhisper
- OpenWhispr：https://github.com/0xShaito/openwhispr 、https://ossinsight.io/analyze/OpenWhispr/openwhispr
- Buzz：https://github.com/chidiwilliams/buzz ；Vibe：https://github.com/thewh1teagle/vibe
- FUTO：https://github.com/futo-org/voice-input 、https://github.com/futo-org/android-keyboard 、原始碼 `app/src/main/java/org/futo/voiceinput/{VoiceInputMethodService.kt,WhisperRecognizerService.kt}`
- Sayboard：https://github.com/ElishaAz/Sayboard 、https://f-droid.org/en/packages/com.elishaazaria.sayboard/
- HeliBoard：https://github.com/Helium314/HeliBoard ；AnySoftKeyboard：https://github.com/AnySoftKeyboard/AnySoftKeyboard
- iOS 鍵盤：https://github.com/getdictus/dictus-ios 、https://github.com/fmachta/WhisperBoard 、https://github.com/ksaitor/WhisperSource 、https://github.com/KeyboardKit/KeyboardKit
- macOS Swift 工具：https://github.com/watzon/pindrop 、https://github.com/clemarc/aparte 、https://github.com/wbfrancis/WhisperApp 、https://github.com/mwgo/SimpleWhisper 、https://github.com/dhirajcdry/justwisper 、https://github.com/alexktitarov/local-whisper-dictation-macos

### 2.2 Handy 原始碼解剖（我們桌面端的藍圖）

**依賴（`src-tauri/Cargo.toml`，version 0.9.7）**：
```toml
tauri = { version = "2.11.5", features = ["macos-private-api", "tray-icon", ...] }
rdev = { git = "https://github.com/rustdesk-org/rdev" }   # 低階鍵盤監聽（rustdesk fork）
cpal = "0.16.0"            # 音訊擷取
rtrb = "0.4.0"             # 即時 ring buffer
rubato = "0.16.2"          # 重取樣到 16 kHz
vad-rs = { git = "https://github.com/cjpais/vad-rs" }   # Silero VAD
earshot = "1.2.2"          # 另一個 VAD
enigo = "0.6.1"            # 模擬按鍵（Ctrl/Cmd+V）
transcribe-rs = { version = "0.3.8", features = ["onnx"] }  # Parakeet/Moonshine/SenseVoice/GigaAM/Canary/Cohere
transcribe-cpp = { version = "0.2.4" }                      # Whisper 家族 GGUF/ggml，含串流
handy-keys = "0.3.4"       # 全域熱鍵
ferrous-opencc = "0.2.3"   # OpenCC 繁簡轉換（已引入，接線位置未查到）
whatlang / isolang         # 文字語言偵測，用於填充詞移除 fallback
hf-hub (fork, cancellable-downloads)   # 模型下載
rusqlite                   # 歷史紀錄
```
Windows 另外引入 `windows` 0.61（`Win32_Media_Audio_Endpoints`、`Win32_System_DataExchange` 等）與 `webview2-com`；註解明說 ONNX Runtime 在 Windows 刻意用 CPU-only（DirectML 的 prebuilt 用 `/arch:AVX2` 會在 pre-Haswell CPU 開機即崩）。這類「血淚註解」是我們最省錢的學習。

**模組結構（`src-tauri/src/`）**：`audio_toolkit/`、`catalog/`（模型目錄）、`commands/`、`managers/`、`paste_tx/`、`shortcut/`、`actions.rs`、`apple_intelligence.rs`、`clipboard.rs`、`input.rs`、`llm_client.rs`、`overlay.rs`、`secure_input.rs`、`transcription_coordinator.rs`、`tray.rs`、`portable.rs`、`cli.rs`。

**文字注入（`input.rs` + `clipboard.rs` + `paste_tx/`）**：
- 預設 macOS/Windows 走 `PasteMethod::CtrlV`（Linux 預設 `Direct` 打字）；另支援 `CtrlShiftV`、`ShiftInsert`（終端機）。
- macOS 用 `TISCopyCurrentKeyboardLayoutInputSource` + `UCKeyTranslate` 動態找出目前鍵盤配置下「V」的 keycode（`resolve_command_v_keycode`），避免 Dvorak/非 ANSI 配置貼不出來。
- Linux：`try_send_key_combo_linux` / `try_direct_typing_linux` 依序偵測：Wayland → KDE 用 `kwtype`（KDE Fake Input，支援變音符）、非 KDE/GNOME 用 `wtype`、再 `dotool`、再 `ydotool`；X11 → `xdotool` 再 `ydotool`。註解寫明 wtype 在 KDE 不行（缺 `zwp_virtual_keyboard_manager_v1`）。剪貼簿寫入在 Wayland 優先用 `wl-copy`。
- `paste_tx`（Reliable Paste beta）：把文字以「延遲渲染」放上剪貼簿——Windows `SetClipboardData(CF_UNICODETEXT, NULL)` 等 `WM_RENDERFORMAT`、macOS `declareTypes:owner:` 等 `pasteboard:provideDataForType:`——只有在貼上按鍵送出**之後**收到的讀取才算「回執」，且只在仍擁有剪貼簿（changeCount 未變）時才還原；`QUIET_PERIOD` 200 ms（Chromium 會先 probe 再讀）、`RESTORE_TIMEOUT` 8 s、`FAILED_INJECTION_TIMEOUT` 500 ms。這解掉了「固定延遲後還原剪貼簿 → 使用者貼到舊內容」的經典 bug（issue #502）。

**熱鍵（`shortcut/`、`secure_input.rs`、`handy-keys`）**：
- 兩套實作可切換：`tauri-plugin-global-shortcut`（Carbon-backed）與 `handy-keys`（CGEventTap-based，支援純修飾鍵如 `Cmd+Shift`、可擋住按鍵不傳給其他 app、提供「錄製熱鍵」UI 所需的低階 listener）。
- `ShortcutActivation` 三種：`Toggle`、`Hold`、`HoldOrToggle`（按住超過 `hold_threshold_ms` 視為 push-to-talk，短按視為切換）。
- `secure_input.rs`：macOS 任何程序開啟 Secure Event Input（密碼欄、Terminal 的 Secure Keyboard Entry、卡住的 loginwindow）時 CGEventTap 收不到 KeyDown/KeyUp 但 FlagsChanged 仍有，於是 keyed 熱鍵（如 Option+Space）會無聲失效（issue #1578）。Handy 輪詢 `IsSecureEventInputEnabled()`，持續時把 keyed 綁定「影子註冊」到 Carbon 路徑，純修飾鍵綁定不需 fallback；Fn+key 無法 fallback。
- README 也註明 macOS 的 fn+key 有限制。

**STT 與後處理**：`transcribe-cpp`（whisper 串流，v0.9.0 引入）+ `transcribe-rs` ONNX（Parakeet V3 CPU 友善、自動語言偵測）。`llm_client.rs` 是 OpenAI-compatible `chat/completions` client（處理 DeepSeek 等 reasoning 參數的拒絕記憶、JSON schema `response_format`）；`apple_intelligence.rs` 透過 Swift FFI（`is_apple_intelligence_available`、`process_text_with_system_prompt_apple`）呼叫 Apple Foundation Models 做本地 LLM 清理。`whatlang`+`isolang` 做文字語言偵測以選填充詞清單。

**UX 細節**：overlay 顯示位置/樣式、音效回饋主題、自訂詞彙（v0.9.6 起不限空白）、歷史紀錄 SQLite、CLI `--toggle-transcription` / `--cancel`、Raycast 整合、portable 模式、多聲道麥克風選聲道（v0.9.5）、第二螢幕 overlay（v0.9.5）、非文字剪貼簿內容保留（v0.9.5）。

### 2.3 Android 語音 IME 參考（FUTO Voice Input 原始碼）

`VoiceInputMethodService.kt`（390 行）繼承 `InputMethodService`，同時實作 `LifecycleOwner`/`ViewModelStoreOwner`（Compose UI）。關鍵呼叫：
- 即時暫定文字：`currentInputConnection.setComposingText(result, 1)`（第 268 行）
- 定稿：`currentInputConnection.commitText(modifiedResult, 1)`（第 261 行）
- 完成後：`switchToPreviousInputMethod()`（第 220 行）切回使用者原本的鍵盤
- `WhisperRecognizerService : RecognitionService`（僅 19 行殼）讓它可當系統語音辨識服務。
- 支援兩種入口：`android.speech.action.RECOGNIZE_SPEECH` implicit intent（浮動視窗）與 IME voice subtype（佔鍵盤下半部）；明言**不支援** `SpeechRecognizer` API；Gboard/Samsung 鍵盤硬編碼只能用 Google/Samsung 語音。
- 授權是 FUTO Source First（不是 OSI 開源，商用需留意），**只能學思路，不要複製碼**。

### 2.4 iOS 鍵盤聽寫的三個硬限制（所有專案一致）

1. **鍵盤 extension 不能存取麥克風**（即使 Full Access 也不行；Apple 的理由是無法向使用者明示「手機在聽」）。來源：https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html 、https://developer.apple.com/forums/thread/775077 、https://medium.com/@inFullMobile/limitations-of-custom-ios-keyboards-3be88dfb694
2. **記憶體上限約 50–60 MB**（有人 30 MB 就掛、有人 70 MB），超過直接被 jetsam 砍、無 crash log、iOS 默默切回上一個鍵盤。來源：https://dev.to/tbds_2dadf2b626f315902eae/the-three-hard-constraints-of-an-ios-keyboard-extension-46af 、https://developer.apple.com/forums/thread/105815
3. **Full Access 才有網路與 App Group 寫入權**。

共同解法（Wispr Flow、Dictus、WhisperBoard）：鍵盤只做觸發與 `textDocumentProxy.insertText`，錄音與辨識在主 app（或由主 app 預先授權的 session），透過 App Group 容器 + Darwin notification 交換資料。WhisperBoard 把鍵盤端壓在 ~20 MB、主 app <150 MB，並在 memory warning 時卸載模型。

---

## 3. 「可以借用什麼」清單（What to borrow）

| # | 借什麼 | 從哪裡 | 授權可行性 |
|---|---|---|---|
| 1 | 跨平台全域熱鍵（純修飾鍵、擋鍵、錄製 UI）| `handy-keys` crate | MIT ✅ 直接依賴 |
| 2 | 回執式可靠貼上（`paste_tx`）、動態 V keycode、Linux 工具鏈選擇 | Handy `paste_tx/`、`input.rs`、`clipboard.rs` | MIT ✅ 可複製改寫 |
| 3 | macOS Secure Event Input 偵測 + Carbon fallback | Handy `secure_input.rs` | MIT ✅ |
| 4 | 本地 STT 抽象層：Whisper（ggml）+ ONNX（Parakeet/SenseVoice/Moonshine） | `transcribe-cpp`、`transcribe-rs` | MIT ✅ |
| 5 | `Hold / Toggle / HoldOrToggle` + `hold_threshold_ms` 的啟動語意；四種錄音模式命名 | Handy `settings.rs`、whisper-writer | ✅ 設計概念 |
| 6 | OpenAI-compatible LLM client（含 reasoning 參數相容性、JSON schema 輸出） | Handy `llm_client.rs` | MIT ✅ |
| 7 | Apple Foundation Models FFI 做本地清理 | Handy `apple_intelligence.rs` + Swift bridge | MIT ✅ |
| 8 | 「Modes / Power Mode」：依 app bundle id / 瀏覽器 URL 自動切 prompt + 模型 | Superwhisper（概念）、VoiceInk（GPL，只學不抄） | 概念 ✅ |
| 9 | 單修飾鍵 tap/hold/combo 狀態機（有單元測試）、`AVCaptureSession` 16 kHz 錄音 | Blurt `BlurtEngine` | MIT ✅ |
| 10 | 上下文送雲端時的最小化原則（只送游標前一小段 + 本次 session 歷史，不送 app 名/視窗標題） | Blurt README；對照 Typeless 被抓包案例 | 設計原則 |
| 11 | Android IME：`setComposingText` 串流 → `commitText` 定稿 → `switchToPreviousInputMethod` | FUTO Voice Input（Source First，**只學 API 用法**）、AnySoftKeyboard（Apache ✅ 骨架） | 混合 |
| 12 | Android 第二路：Accessibility Service + 懸浮泡泡（跨 app 塞字） | Wispr Flow Android（閉源，只學行為） | 概念 |
| 13 | iOS：鍵盤當遙控器、主 app 錄音、App Group + Darwin notification、記憶體預算 | Dictus（MIT）、WhisperBoard（MIT） | ✅ |
| 14 | iOS/macOS 26 免費本地 STT：`SpeechAnalyzer` + `SpeechTranscriber`（volatile/final 雙流、`AssetInventory`） | Apple WWDC25 277、SimpleWhisper 示範三引擎切換 | Apple API ✅ |
| 15 | OpenCC 繁簡轉換、文字語言偵測（`whatlang`）選填充詞表 | Handy Cargo.toml（`ferrous-opencc`） | MIT ✅ |
| 16 | BYOK（自帶 API key）零抽成的免費層 + 瀏覽器/桌面共用 UI | Whispering | AGPL ⚠ 只學商業模型 |
| 17 | 模型下載（可取消的 hf-hub fork）、SQLite 歷史、portable 模式、CLI/Raycast 整合 | Handy | MIT ✅ |

**要避開的**：Electron（OpenWhispr 路線，記憶體與體積都輸 Tauri）、Python/PyQt（whisper-writer/Buzz：發佈困難、已停滯）、GPL/AGPL 專案的程式碼（VoiceInk、Whispering、HeliBoard、Sayboard、WhisperSource）若我們打算閉源或雙授權。

---

## 4. 對我們的設計意涵

1. **桌面技術棧選 Rust + Tauri 2，直接站在 Handy 的肩膀上**。Handy 已驗證 macOS/Windows/Linux 三平台可行、32.5k★ 社群在幫忙踩坑（Secure Input、Wayland、pre-Haswell CPU、Chromium 剪貼簿 probe）。我們應 fork 或至少依賴 `handy-keys`、`transcribe-cpp`、`transcribe-rs`，把工程時間投在差異化而非基礎設施。
2. **架構分層**：`capture (cpal+VAD)` → `stt (本地/雲端 provider trait)` → `polish (LLM provider trait：本地 Apple Intelligence / Ollama / 雲端)` → `inject (per-OS strategy：paste_tx / direct typing / IME)` → `context (app id、URL、游標前文)`。每層都要可替換，因為平台廠商（Apple SpeechAnalyzer、Windows Fluid Dictation、Gboard Rambler）會持續把下層變免費。
3. **本地優先 + 雲端加速是正確的定位**：市場上純雲端（Wispr/Typeless/Willow/Aqua/Voicy）與純本地（Superwhisper/VoiceInk/Handy）各占一半；Typeless 隱私爭議證明「本地」是可賣點，但雲端在噪音與專有名詞上仍勝。建議預設本地（Apple 平台用 `SpeechTranscriber`，其他用 Parakeet V3 ONNX），Pro 加雲端模型與 BYOK。
4. **延遲 KPI**：以 Aqua Voice 的 965 ms / 450 ms（end-of-speech → 文字）為目標區間；用 `transcribe-cpp` 串流 + VAD 在放開熱鍵前就先轉錄，可把感知延遲壓到只剩 LLM 清理那段。
5. **手機端不要幻想「鍵盤內辨識」**：iOS 必須採「鍵盤遙控 + 主 app 錄音 + App Group」且鍵盤端 <20–30 MB；Android 建議同時提供 IME（精準、省電）與 Accessibility 泡泡（覆蓋 Gboard/Samsung 用戶）。Android 的 Whisper/Parakeet 本地推論可參考 FUTO（whisper.cpp JNI）或 sherpa-onnx。
6. **定價錨點**：Pro $12/月年繳是行業共識；免費層 2,000 字/週是常態、Typeless 8,000 字/週是進攻訊號。本地優先產品可以賣終身（VoiceInk $25–49、Superwhisper $249.99）。若主打本地，「免費本地無限 + 雲端/團隊付費」（Superwhisper 模式）是最自然的。
7. **繁中/台灣差異化**：(a) 預設輸出繁體（OpenCC `s2twp` 台灣用語），避免 Superwhisper iOS 的簡體問題；(b) 中英夾雜的 code-switching 在 LLM 清理 prompt 中特別處理（英文技術詞不翻譯、保留原大小寫）；(c) 注音/標點習慣（全形標點）；(d) 台灣常用 app（LINE、Notion、Slack、VS Code）的 Power Mode 預設。這些是 Wispr/Typeless 以英語為中心的 LLM 層不會特別優化的。
8. **誠實的隱私文案**：明確區分「辨識在哪裡」與「資料保存在哪裡」；若送雲端，只送最小上下文（參考 Blurt：不送 app 名、視窗標題、整段欄位）。
9. **上下文感知的實作路徑**：macOS 用 AXUIElement 讀焦點元素的 `AXValue`/`AXSelectedTextRange` 與 bundle id、瀏覽器 URL（VoiceInk `Context/` 模組做法）；Windows 用 UI Automation；Linux 受限（Wayland 幾乎拿不到）。這也是為什麼 Linux 聽寫產品普遍只做「貼上」不做「感知」。
10. **Secure Input / 密碼欄位**：必須像 Handy 一樣偵測並降級，否則使用者會回報「熱鍵突然不靈」。

---

## 5. 未解問題（Open Questions）

1. Apple `SpeechTranscriber.supportedLocales` 是否包含 `zh-Hant-TW`？若否，Apple 平台的本地 STT 需退回 `DictationTranscriber` 或 Whisper/Parakeet（後者中文品質待測）。
2. Parakeet V3（ONNX）對繁中/中英夾雜的 WER 實測？SenseVoice Small（Handy/VoiceInk 皆支援）是否才是中文本地首選？
3. Typeless 與 Wispr Flow 的實際 STT 供應商是什麼（自研？Deepgram/AssemblyAI/OpenAI？）——僅確認 Typeless 的 LLM 用 OpenAI 等第三方，ASR 未知。
4. Wispr Flow Android 的 Accessibility Service 寫入文字在各廠牌 ROM（Samsung One UI、小米）的相容性如何？Google Play 對 Accessibility 權限的審核（需說明無障礙用途）是否會卡住我們？
5. iOS 26 的 App Intents / Action Button 是否能讓我們省掉「跳主 app 再跳回」的體驗斷裂？（OpenSuperWhisper issue #135 正在討論 iOS 伴侶 app 走 App Intents）
6. Handy 的 `ferrous-opencc` 實際接在哪一層（輸出轉換？模型 metadata？）——未在 `settings.rs` 找到相關設定，需讀 `managers/` 或 `transcription_coordinator.rs`。
7. Windows Fluid Dictation 與 Gboard Rambler 擴到中文的時程？若 2027 前覆蓋繁中，純「本地 Whisper + 清理」的免費層價值會大幅下降。
8. 商業競品定價資料多來自競品部落格（getvoibe、spokenly、usevoicy 本身都是聽寫產品），需在上線前對照官方頁面重新核實。
9. WhisperSource 宣稱鍵盤 extension 不需 Full Access 即可直接辨識，與 Apple 文件衝突；需實機驗證是否只是「不需網路」的誤述。
10. Linux Wayland 的上下文感知與可靠貼上是否值得投入（GNOME/KDE 各自協定不同）；或接受 Linux 僅為「貼上即可」的二級平台。
