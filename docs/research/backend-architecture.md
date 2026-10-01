# 後端與共享核心架構研究（backend-architecture）

研究日期：2026-10-01。對象：由 1–2 位開發者打造的跨平台（macOS / Windows / Linux / iOS / Android）AI 語音聽寫（Typeless 類）產品。

> **來源可信度標記**
> - ✅ = 本次直接讀取一手來源（GitHub 原始碼/README、Apple/Android 官方文件、Cloudflare/Supabase 文件原始碼）並附 URL。
> - ⚠️ = 本次研究環境無法連到該網站（WebSearch 額度已用罄；deepgram.com、openai.com、platform.openai.com、developers.cloudflare.com、supabase.com、posthog.com、sentry.io、revenuecat.com、keygen.sh、lemonsqueezy.com、typeless.com、wisprflow.ai、superwhisper.com、huggingface.co、fly.io、hetzner.com、railway.com、groq.com、ai.google.dev、onnxruntime.ai、tauri.app 等皆被 egress proxy 封鎖），所以該敘述來自我的既有知識（可能過時），**動工前請自行開啟附上的 URL 再確認一次**。
> - 凡是會改變架構決策的 ⚠️ 項目，都列在最後的「未解問題」。

---

## 0. 執行摘要

1. **手機端「鍵盤」決定了共享核心的上限。** iOS 自訂鍵盤是獨立進程、有未公開的記憶體上限（Apple 原文：超過即被系統終止）✅，且 App Store 4.4.1 要求鍵盤「在沒有 Full Access、沒有網路時仍需可用」✅；Android IME 則可直接在 `InputMethodService` 內拿 `RECORD_AUDIO` 錄音（開源 Sayboard 已證明）✅。因此**手機鍵盤必須是原生 Swift / Kotlin 薄客戶端**，本地大模型不可能塞進 iOS 鍵盤進程，手機端以雲端 STT（經你的後端代理）為主。
2. **Tauri 2 不能當 iOS 鍵盤或 Android IME。** Tauri 2.12.1 為最新穩定版（3.0.0-alpha.4 於 2026-10-01 發佈）✅；官方 mobile plugin 文件完全沒有 app extension / InputMethodService 的概念 ✅；實務上有人用 XcodeGen 把 share extension 塞進 Tauri iOS 專案，但 CI 以 App Store Connect API key 簽章時 extension 的 entitlements 會被默默丟掉（issue #15663，未修）✅。**結論：Tauri 只適合當桌機殼（Handy 就是這樣做）**，手機鍵盤要走原生。
3. **共享核心建議用 Rust + UniFFI。** UniFFI v0.32.1（2026-09-08）支援 async constructor、`&[u8]` 零拷貝傳遞（對音訊 buffer 很重要）、proc-macro；Mozilla 在 Firefox 桌機/手機大量使用 ✅。Rust 生態的現況是：`whisper-rs` 已於 2025-07-30 封存 ✅、`sherpa-rs` 已於 2026-06-06 封存並指向 **sherpa-onnx 官方 Rust crate** ✅；Handy（32.5k 星、MIT）實際用的是 `transcribe-rs 0.3.8`（ONNX：Parakeet/SenseVoice/Moonshine…）+ `transcribe-cpp 0.2.4`（whisper.cpp，含 metal / vulkan / cuda feature）+ `cpal 0.16` + `vad-rs`（Silero）+ `enigo 0.6.1` ✅。
4. **後端建議「Cloudflare Workers + Durable Objects 做串流代理與計量」+「Supabase（Tokyo 或 Singapore）做 Auth / Postgres / 權益」。** Workers Paid US$5/月含 1,000 萬次請求、3,000 萬 CPU-ms；DO 每百萬請求 US$0.15、每百萬 GB-s US$12.5、WebSocket 訊息以 20:1 計價、休眠期間不計 GB-s ✅。DO 可用 `locationHint: "apac-ne"` / `"apac-se"` 提示放在東北亞 / 東南亞，但「只是 best effort，不能釘到台北/東京」✅。Supabase Edge Functions 有 Tokyo (`ap-northeast-1`)、Singapore (`ap-southeast-1`)，**沒有香港** ✅；Free 方案 50k MAU / 500MB DB，閒置 1 週會暫停、最多 2 個專案；Pro US$25/月 ✅。
5. **台灣用戶的延遲瓶頸不在你的後端，而在 STT 供應商的機房位置。** Deepgram、OpenAI 官方文件這次無法讀取 ⚠️；就我所知 Deepgram 託管 API 只有美國端點（self-hosted 需企業合約 + GPU），OpenAI Realtime 也不保證亞太就近 ⚠️。這代表「台北→美西」約 130–180 ms RTT 是固定成本，應把 WebSocket 連線在按下熱鍵前就預先建立、邊說邊送（interim results），放開熱鍵後只剩「最後 finalize + LLM 清理」的等待。
6. **本地離線模式：桌機可以、手機鍵盤不行。** whisper.cpp 支援 Metal / CoreML / CUDA / Vulkan / OpenVINO / ROCm ✅，`large-v3-turbo` 1.5 GiB、`large-v3-turbo-q5_0` 547 MiB、`small` 466 MiB、`base` 142 MiB ✅。**注意 Parakeet TDT 0.6B v3 只支援 25 種歐洲語言，沒有中文** ✅（FluidAudio README），對台灣用戶本地中文只能靠 whisper large-v3-turbo、SenseVoice-Small（zh / yue / en / ja / ko）✅ 或 sherpa-onnx 的 zh-en Zipformer；iOS/macOS 26 的 `SpeechAnalyzer` 是零下載的系統級選項 ✅，但 zh-TW 支援與 extension 可用性需實測。
7. **授權 / 計費：** App Store 平台（iOS + macOS）用 RevenueCat（purchases-ios 支援 macOS 10.15+、Mac Catalyst、visionOS）✅；Windows / Linux 用 Keygen（Community Edition 可自架，Fair Core License 兩年後轉 Apache-2.0，支援 Ed25519 離線授權）✅ 或 Lemon Squeezy License API（activate / validate / deactivate）✅。若提供 Google 登入就**必須**同時提供 Sign in with Apple（Guideline 4.8，僅「只用自家帳號系統」等情況豁免）✅。
8. **推薦架構：變體 B「Tauri 桌機 + 原生手機鍵盤 + Rust 共享核心 + CF/Supabase 後端」**，分三階段落地（§7）。

---

## 1. 共享核心策略（Shared Core）

### 1.1 先看平台硬限制：手機鍵盤能跑什麼

**iOS 自訂鍵盤（Keyboard Extension）** ✅
- 「Your custom keyboard code executes in a separate process, and that process has a limit on the amount of memory it may use. If your keyboard extension exceeds the memory limit the system terminates it.」— Apple, *Creating a custom keyboard*（https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard）。數值未公開；社群普遍量到的上限約 50–70 MB ⚠️。
- `RequestsOpenAccess`（Full Access）開啟後才有：網路、與主 App 共用的 App Group 容器、iCloud、Location/Contacts；Apple 要求「Don't store received keystroke or voice data beyond the time needed to provide text back to the user」（https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard）。
- **麥克風**：Apple 的 Extension Programming Guide（iOS 8 時代的 archive）明文說 app extension 不能存取相機與麥克風（iMessage app 除外）（https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionOverview.html）；而現行的 open-access 文件把「No access to microphone and speaker」列在**未開 Full Access 的限制清單**中。就我所知 Gboard iOS 的語音輸入與 Wispr Flow iOS 鍵盤都是在鍵盤進程內直接錄音（需 Full Access + 麥克風權限）⚠️。**這是本專案第一週就要用真機驗證的事**（見未解問題 #1）。
- App Store Review 4.4.1：鍵盤必須「Remain functional without full network access and without requiring full access」、必須提供切換到下一個鍵盤的方法、只能開啟 Settings 不能啟動其他 App（https://developer.apple.com/app-store/review/guidelines/）。意思是：你的鍵盤在沒有 Full Access 時至少要能打字（哪怕只是最陽春的 QWERTY），語音功能可以是 Full Access 才解鎖的功能。
- 密碼欄位、電話欄位會被系統鍵盤取代；自訂鍵盤無法選取文字 ✅（archive 文件）。

**Android IME** ✅
- 繼承 `InputMethodService`，Manifest 宣告 `android.permission.BIND_INPUT_METHOD` + `<action android:name="android.view.InputMethod"/>`；文字用 `currentInputConnection.commitText("Hello", 1)` 寫入（https://developer.android.com/develop/ui/views/touch-and-input/creating-input-method）。
- 開源 **Sayboard**（GPL-3.0、F-Droid 上架）就是一個在 IME 內直接用麥克風錄音、以 Vosk 離線辨識的語音鍵盤，權限為 `RECORD_AUDIO`、`INTERNET`（僅下載模型）、`FOREGROUND_SERVICE` 等（https://github.com/ElishaAz/Sayboard）。**Android IME 沒有 iOS 那種記憶體/麥克風困境**，本地模型在 Android 可行（但手機 CPU 跑 whisper 仍慢）。

**結論**：手機鍵盤 = 原生 Swift / Kotlin。共享核心最多只能以「靜態函式庫」形式被鍵盤進程載入，且在 iOS 要極度精簡（不含任何推論 runtime）。

### 1.2 Tauri 2 能不能做手機鍵盤？——不能（已確認）✅

- 版本：crates.io 上 `tauri` `max_stable_version = 2.12.1`，`newest_version = 3.0.0-alpha.4`（2026-10-01 更新）（https://crates.io/api/v1/crates/tauri）。Handy 鎖在 `tauri = "2.11.5"`。
- 官方 *Mobile Plugin Development* 文件：iOS plugin 是「a Swift class that extends the `Plugin` class from the `Tauri` package」、Android 是 `@TauriPlugin` 類別；生命週期只有 `load`、`onNewIntent`；**完全沒有 app extension、InputMethodService 的概念**（https://github.com/tauri-apps/tauri-docs/blob/v2/src/content/docs/develop/Plugins/develop-mobile.mdx）。
- 實務證據：issue **#15663**（2026-07-06，Open、無維護者回覆）：作者用 XcodeGen 在 Tauri iOS 專案加入 share extension（`PlugIns/*.appex`）宣告 App Group；以 App Store Connect API key 在 CI 建置時 Tauri 會以 `CODE_SIGNING_ALLOWED=NO` 建置、只對主 App 自簽以保留 entitlements，extension 在 export 時被用預設 profile 重簽，**App Group entitlement 被默默丟掉**，TestFlight 全程成功、到 runtime 才爆（https://github.com/tauri-apps/tauri/issues/15663）。另有 #9586「Document how to use system extensions with tauri?」（2024-04，仍 Open）、#10074（extension 在模擬器跑不起來，已關）。
- 所以：即使你硬把鍵盤 extension 塞進 Tauri iOS 專案，extension 本體仍是純 Swift、WebView 無法用，而且簽章要自己用 `xcodebuild` / fastlane 處理。**Tauri 在手機端沒有價值；在桌機端價值很高（一份碼出 mac/win/linux）。**

### 1.3 選項 A：Rust 核心 + UniFFI（推薦）

**UniFFI 現況** ✅（https://github.com/mozilla/uniffi-rs ；CHANGELOG https://github.com/mozilla/uniffi-rs/blob/main/CHANGELOG.md）
- 最新 **v0.32.1（2026-09-08）**。v0.32.0 重點：async constructor；`&[u8]` / `[ByRef] bytes` **零拷貝**傳遞（不再經 RustBuffer）——這對每 20 ms 一包的 PCM 音訊很關鍵；遞迴 enum 自動偵測；`Box<T>`；Kotlin 端 `&[u8]` 現在要傳 `java.nio.ByteBuffer` 而非 `ByteArray`（breaking）。
- 官方定位：「ready for production use」但「a long way from a 1.0 release」；簡單用法盡量不破壞，進階功能升級時可能壞。Mozilla 在 Firefox 手機/桌機大量使用。
- 目標語言：Kotlin、Swift、Python、Ruby 官方；C#、Go 第三方；另有 JS/Dart 等社群綁定。
- Swift 打包：`uniffi-bindgen-swift` 可分別產出 `--swift-sources`、`--headers`、`--modulemap`、`--xcframework`（XCFramework 相容 modulemap），以 library mode 自動支援 proc-macro（https://github.com/mozilla/uniffi-rs/blob/main/docs/manual/src/swift/uniffi-bindgen-swift.md）。Xcode 整合文件建議參考 `examples/app/ios` 的 `xc-universal-binary.sh`，把 Rust 編成 static lib 後 `xcodebuild -create-xcframework` 打包 device + simulator + macOS（https://github.com/mozilla/uniffi-rs/blob/main/docs/manual/src/swift/xcode.md）。

**Rust 音訊/STT crate 現況**（以 Handy 的 `src-tauri/Cargo.toml` 為準）✅（https://github.com/cjpais/Handy/blob/main/src-tauri/Cargo.toml）

| 用途 | Crate | 備註 |
|---|---|---|
| 音訊擷取 | `cpal 0.16.0` | 跨平台；iOS/Android 也可，但鍵盤 extension 內建議直接用 AVAudioEngine / AudioRecord 原生錄音再把 PCM 丟進 Rust |
| VAD | `vad-rs`（cjpais fork，Silero） | Silero VAD JIT 約 2 MB、每 30 ms chunk（512 samples @16k）CPU 單執行緒 <1 ms、MIT（https://github.com/snakers4/silero-vad） |
| ONNX 引擎 | `transcribe-rs 0.3.8`（feature `onnx`） | Parakeet / Canary / Cohere / Moonshine / SenseVoice / GigaAM；feature：`ort-cuda`、`ort-rocm`、`ort-directml`、`ort-coreml`、`ort-webgpu`；輸入須 16 kHz mono 16-bit PCM（https://github.com/cjpais/transcribe-rs） |
| whisper.cpp 引擎 | `transcribe-cpp 0.2.4` | Handy 明寫「不用 whisper-rs」；feature：macOS `metal`、Windows x64 / Linux `dynamic-backends + vulkan`、Windows ARM64 CPU-only |
| 文字注入 | `enigo 0.6.1` + X11 `xdotool` / Wayland `wtype` + 剪貼簿貼上 | Handy 有「Reliable Paste (Beta)」用剪貼簿變更通知確認 |
| 熱鍵 | `rdev`（rustdesk fork） | macOS fn 鍵有限制 |

- `whisper-rs` 已於 **2025-07-30 封存**（https://github.com/tazz4843/whisper-rs）；`sherpa-rs` 已於 **2026-06-06 封存**，指向 **sherpa-onnx 官方 Rust crate**（預設 static link、首次建置自動下載對應平台的原生函式庫；`--features shared` 可改動態）（https://github.com/thewh1teagle/sherpa-rs ；https://github.com/k2-fsa/sherpa-onnx/tree/master/rust-api-examples）。
- 崩潰回報：`sentry-rust` MSRV 1.88.0、尚未 1.0、不遵循 semver；有 panic / minidump / tracing 整合（https://github.com/getsentry/sentry-rust）。

**核心應該包含什麼（給 1–2 人團隊的「夠小」定義）**
```
core/                      # Rust crate: `atype-core`
  audio/      resample 48k→16k, ring buffer, level meter
  vad/        silero (onnxruntime 或 ten-vad) + endpointing 狀態機
  stt/        trait SttEngine { fn feed(&mut self, pcm16: &[i16]); fn finalize(&mut self) -> Transcript }
              impl: CloudWs (你的後端), WhisperCpp (desktop), SherpaOnnx (desktop/android)
  cleanup/    dictionary/snippet 套用、標點與中英夾雜間距規則（純文字處理，不含 LLM）
  api/        後端 client：auth token、usage、WebSocket framing（統一協定）
  ffi/        uniffi proc-macro 導出：`#[uniffi::export]`
```
**不要放進核心**：UI、熱鍵、文字注入、鍵盤 UI——這些每個平台都不一樣，硬共享只會更慢。

### 1.4 選項 B：Kotlin Multiplatform
- Compose Multiplatform：iOS 與 Desktop 已 Stable，Web (Wasm) Beta ✅（https://github.com/JetBrains/compose-multiplatform）。
- 問題：桌機端是 JVM（menubar 常駐小工具帶 JVM 不理想、Windows/Linux 打包大）；iOS 端 Kotlin/Native framework 塞進鍵盤 extension 的記憶體開銷未知；音訊/推論生態（whisper.cpp、onnxruntime）都是 C/C++/Rust，KMP 仍要再包一層。**只有在你本來就是 Android/Kotlin 工程師時才值得**。

### 1.5 選項 C：C++ 核心
- whisper.cpp、sherpa-onnx 本身就是 C++，直接以 C API 給 Swift / Kotlin(JNI) / C#(P/Invoke) 呼叫，零綁定工具成本。
- 缺點：網路/協定/狀態機用 C++ 寫對 1–2 人團隊效率低、安全性差；Rust 透過 `transcribe-cpp` / 官方 sherpa-onnx crate 已經把這兩個 C++ 引擎包好，等於「Rust 當膠水、C++ 當引擎」，是 A 的子集。

### 1.6 選項 D：不共享核心，原生到底 + 共享後端
- 每平台原生（Swift / Kotlin / C# 或 Tauri），把「髒活」上移到後端：STT 代理、LLM 清理、字典套用、片段展開都在伺服器做；客戶端只做「錄音 → 送 PCM → 收文字 → 注入」。
- 優點：客戶端極薄、鍵盤 extension 體積最小、邏輯只改一處（後端）。缺點：**沒有離線模式**、每次聽寫都依賴網路與你的伺服器，macOS 桌機用戶（Typeless / superwhisper 的主力客群）會期待本地模型。可以當 **MVP 階段**策略，之後把 Rust 核心補進桌機。

### 1.7 真實案例

| 產品 | 技術棧 | 平台 | 本地引擎 | 授權/商模 |
|---|---|---|---|---|
| **Handy** ✅ | Tauri 2.11.5 + React；Rust：cpal、vad-rs、transcribe-rs、transcribe-cpp、enigo、rdev | mac / win / linux | Whisper（GPU）、Parakeet V3（CPU、自動語言偵測） | MIT；32.5k★（https://github.com/cjpais/Handy） |
| **Whispering / Epicenter** ✅ | Svelte + SvelteKit + Tailwind + Tauri；Bun monorepo（`apps/`、`packages/`：`@epicenter/data`、`sqlite`、`sync`、`ui`、`server`） | 桌機 + Web（無手機） | 桌機限定 GGUF on-device；雲端/自架供應商、Epicenter gateway | AGPL-3.0-or-later；local-first on Yjs；同步 = 每帳號一個 Durable Object，「signed in on two devices is the entire sharing model」（https://github.com/epicenter-md/epicenter） |
| **VoiceInk** ✅ | 原生 Swift，macOS 15+ | macOS | whisper.cpp、Parakeet（經 FluidAudio）、SenseVoice-Small | GPL-3.0；一次買斷、定位對抗 superwhisper / Wispr Flow 訂閱（https://github.com/Beingpax/VoiceInk） |
| **FluidAudio** ✅ | Swift SDK，CoreML / ANE | iOS 18+ / macOS 15+（部分模型） | Parakeet TDT v3（25 歐語）、v2（英）、Silero VAD、diarization、Kokoro TTS；batch ASR「~190x on M4 Pro」 | Apache-2.0（https://github.com/FluidInference/FluidAudio） |
| Wispr Flow ⚠️ | 網站被封鎖。我的認知：原生 Mac（Swift）+ Windows + iOS 鍵盤 + Android，雲端 STT/LLM，訂閱制、免費每週字數上限 | 全平台 | 無 | 訂閱 |
| superwhisper ⚠️ | 網站被封鎖。我的認知：原生 macOS + iOS，主打本地 whisper 模型，另有雲端模型；訂閱 + lifetime | mac / iOS | whisper 系列 | 訂閱/買斷 |
| Typeless ⚠️ | 網站被封鎖。目標對象：桌機 + 手機鍵盤、雲端 AI 清理 | 全平台 | 不明 | 訂閱 |

**觀察**：開源陣營（Handy、VoiceInk、Whispering）全部**沒有手機版**——因為手機鍵盤的工程與審核成本高、又不能跑本地模型。這正是你的差異化空間，也是最難的一塊。

---

## 2. 後端（帳號、計量、計費、STT/LLM 代理）

### 2.1 後端要做的事
1. **Auth**：Email magic link / passkey + Sign in with Apple + Google。
2. **Entitlements**：方案、每月字數/分鐘數配額、裝置數。
3. **Usage metering**：每次聽寫的秒數、字數、使用的引擎、成本。
4. **STT/LLM 代理**：API key 絕不下發到客戶端；客戶端用短效 JWT 連你的 WebSocket。
5. **同步**：字典、片段、設定（小而頻繁）；歷史紀錄（大且敏感，預設只留本機）。
6. **模型下載**：桌機本地模型檔（數百 MB～1.5 GB）走 CDN。
7. **遙測 / 崩潰 / feature flags**。

### 2.2 平台選項與價格

**Cloudflare Workers + Durable Objects** ✅
- Workers Free：100,000 req/天、每次 10 ms CPU。Paid：US$5/月，含 1,000 萬 req（超出 US$0.30/百萬）、3,000 萬 CPU-ms（超出 US$0.02/百萬 CPU-ms）、**不計 wall-clock duration、不計 egress 流量**；每次呼叫 CPU 上限預設 30 s、最高 5 分鐘（https://raw.githubusercontent.com/cloudflare/cloudflare-docs/production/src/content/docs/workers/platform/pricing.mdx）。
- Workers 限制：每次呼叫最多 6 條同時等待 response header 的連線（fetch / WebSocket / TCP socket 都算）；request body 上限 100 MB（Free/Pro）（…/workers/platform/limits.mdx）。
- Durable Objects：請求 US$0.15/百萬（含 100 萬）；duration US$12.50/百萬 GB-s（含 40 萬 GB-s）；**WebSocket 訊息 20:1 計為請求**；最低月費 US$5（…/durable-objects/platform/pricing.mdx）。
- WebSocket Hibernation：閒置時 DO 被逐出記憶體但客戶端連線保留、**休眠期間不計 GB-s**；`serializeAttachment()` 每連線最多 16,384 bytes；**對外（outbound）WebSocket 不能休眠，且會讓 DO 保持活躍約 15 分鐘**（…/durable-objects/best-practices/websockets.mdx）。
- DO 限制：收到的 WebSocket 訊息上限 32 MiB；SQLite-backed 每物件 10 GB、Paid 帳號總量不限；每請求 CPU 30 s（可設到 5 min）；對外同時連線 6（…/durable-objects/platform/limits.mdx）。
- 位置：DO 在**第一次 `get()` 的請求附近**建立、之後不會搬家；可給 `locationHint`：`wnam`、`enam`、`sam`、`weur`、`eeur`、`apac`、`oc`、`afr`、`me`、**`apac-ne`（東北亞）、`apac-se`（東南亞）**；「Hints are a best effort and not a guarantee」，不能釘到東京/新加坡特定城市；jurisdiction 只有 `eu`、`us`、`fedramp`（…/durable-objects/reference/data-location.mdx）。
- 台北 POP：Cloudflare 官網被封鎖 ⚠️；就我所知 Cloudflare 在台北有機房，Workers 在所有 POP 執行。

**Supabase** ✅（價格來源：https://raw.githubusercontent.com/supabase/supabase/master/packages/shared-data/plans.ts）
- Free US$0：50,000 MAU、500 MB DB、5 GB egress、1 GB 檔案；「Free projects are paused after 1 week of inactivity. Limit of 2 active projects.」
- Pro 從 US$25/月：100,000 MAU（之後 US$0.00325/MAU）、8 GB DB（之後 US$0.125/GB）、250 GB egress（US$0.09/GB）、100 GB 檔案（US$0.0213/GB）。Team 從 US$599/月。
- Edge Functions 可指定區域：`ap-northeast-1`（東京）、`ap-northeast-2`（首爾）、`ap-south-1`、`ap-southeast-1`（新加坡）、`ap-southeast-2`；**沒有 `ap-east-1` 香港**；以 `x-region` header 或 `supabase.functions.invoke(name, { region })` 指定，回應 `x-sb-edge-region` 可驗證（https://raw.githubusercontent.com/supabase/supabase/master/apps/docs/content/guides/functions/regional-invocation.mdx）。
- Sign in with Apple：原生 iOS/macOS 走 `signInWithIdToken`，不需設定 OAuth；Web OAuth 需 Services ID + `.p8` 金鑰且 **Apple 要求每 6 個月換一次 secret**；「Apple only provides the user's full name on the first sign-in」（https://github.com/supabase/supabase/blob/master/apps/docs/content/guides/auth/social-login/auth-apple.mdx）。
- Edge Functions 是 Deno，**不適合長連線 WebSocket 串流代理**（有執行時間與記憶體限制 ⚠️）；把串流交給 Cloudflare DO，Supabase 只做 Auth + DB。

**Firebase / Convex** ⚠️
- 兩者網站皆被封鎖。就我所知：Firebase Auth + Firestore 在亞洲有 `asia-east1`（彰化，台灣！）與 `asia-northeast1`（東京）區域，但 Cloud Functions 不適合 WebSocket 長連線；Convex 區域選擇有限（主要美國），對台灣延遲不利。兩者都無法「只用它就做完串流代理」。

**自己開一台小伺服器（Go / Rust axum / Node）** ⚠️
- Fly.io（`nrt` 東京、`sin` 新加坡、`hkg` 香港）、Railway（有 Singapore 區）、Hetzner（2024 年起有 Singapore，但價格高於歐洲）——三者網站本次皆被封鎖，區域清單請自行確認。
- 優點：WebSocket 代理最直覺（一條 goroutine / task 對一條上游連線）、可同時跑 Opus 解碼、可自架 STT；缺點：你要管 TLS、擴縮、監控與 on-call。對 1–2 人團隊，**Cloudflare DO 的「每用戶一個物件 + 自帶 SQLite + 休眠免費」**比較省心；當流量到了需要自架 GPU STT 時再加一台 Fly/Hetzner。

### 2.3 串流代理的參考設計（Cloudflare DO）

```ts
// worker/src/session.ts  —— 每個使用者 session 一個 DO
export class DictationSession extends DurableObject {
  upstream?: WebSocket;              // 到 Deepgram / OpenAI Realtime 的對外連線（不能休眠）
  async fetch(req: Request) {
    const { 0: client, 1: server } = new WebSocketPair();
    this.ctx.acceptWebSocket(server);            // Hibernation API
    // 驗 JWT → 查配額（SQLite 存本月用量）→ 開上游
    this.upstream = await openUpstream(this.env, /* model, language */);
    this.upstream.addEventListener("message", (e) => server.send(e.data)); // 轉發 interim/final
    return new Response(null, { status: 101, webSocket: client });
  }
  webSocketMessage(ws: WebSocket, msg: ArrayBuffer | string) {
    if (typeof msg === "string") return this.control(JSON.parse(msg));   // {type:"finalize"} 等
    this.upstream?.send(msg);                                            // 二進位 PCM/Opus 直通
    this.bytesIn += (msg as ArrayBuffer).byteLength;                     // 計量
  }
  webSocketClose() { this.upstream?.close(); this.flushUsage(); }
}
```
- 成本試算：一次 10 秒聽寫 ≈ DO 活躍 12 s × 128 MB = 1.5 GB-s ≈ US$0.000019；20 ms 一包 PCM = 500 則訊息 ÷ 20 = 25 次「請求」≈ US$0.0000038。**後端代理本身幾乎免費，錢都在 STT/LLM 供應商。**
- 要注意「對外 WebSocket 讓 DO 保持活躍 ~15 分鐘」：**聽寫結束一定要主動 `close()` 上游**，否則一個用戶一天 100 次聽寫會被記成數千秒的 GB-s。
- 流量在 Workers 不計費，但 Supabase egress 計費（Pro 含 250 GB）——所以**音訊不要經過 Supabase**。

### 2.4 STT / LLM 供應商與台灣延遲

| 供應商 | 我能核實的 | 未能核實（⚠️） |
|---|---|---|
| **Deepgram** | JS SDK 以 `client.listen.v1.connect()` 開 WebSocket；選項 `model: "nova-3"`、`interim_results`、`punctuate`；self-hosted 提供 Helm / Docker Compose / Podman（https://github.com/deepgram/deepgram-js-sdk ；https://github.com/deepgram/self-hosted-resources） | 託管端點是否只有美國、Nova-3 串流價（我的記憶：約 US$0.0077/分鐘 pay-as-you-go）、`endpointing` 預設 10 ms、支援 `encoding=linear16/opus/ogg-opus/flac/mulaw…`、self-hosted 需企業合約與 NVIDIA GPU |
| **OpenAI Realtime** | 參考客戶端：「Default audio format is pcm16 with sample rate of 24,000 Hz」，`turn_detection: server_vad` 或 `none`；Python SDK 以 `client.realtime.connect(model=...)` 連線（https://github.com/openai/openai-realtime-api-beta ；https://github.com/openai/openai-python） | `gpt-4o-transcribe` / `gpt-4o-mini-transcribe` 價格（我的記憶：約 US$0.006 / 0.003 每分鐘）、transcription session 的 `input_audio_format` 只接受 pcm16 / g711、是否有亞太區端點 |
| **Anthropic（LLM 清理）** ✅ | Claude Haiku 4.5 `claude-haiku-4-5` US$1 / US$5 每百萬 tokens（200K context）；Sonnet 5.5 `claude-sonnet-5-5` US$2 / US$10；Opus 5.5 US$4 / US$20（本機 claude-api skill 快取 2026-09-25；請以 https://docs.anthropic.com/en/docs/about-claude/pricing 為準） | 實測 TTFT |
| Gemini Flash-Lite / Groq whisper | — | 網站被封鎖；記憶中 Groq whisper-large-v3-turbo 約 US$0.04/小時、Gemini 2.5 Flash-Lite 約 US$0.10 / 0.40 每百萬 tokens |
| **本地 LLM 清理** | — | 可用 llama.cpp 跑 1–3B 模型做標點/格式，但中英夾雜品質需實測 |

**台灣延遲的現實** ⚠️：台北→東京 RTT 約 35–50 ms、→新加坡約 50–70 ms、→美西約 130–180 ms。若 STT 供應商只在美國，你的後端放東京或新加坡並不會縮短「音訊→供應商」這段，只會讓 Auth/配額查詢快一點。真正能做的是：
1. **預先連線**：App 啟動或熱鍵按下的瞬間就建立 WS（Deepgram 用 KeepAlive；OpenAI 用 session），省掉 TLS + WS 握手（跨太平洋約 2–3 個 RTT ≈ 400 ms）。
2. **邊說邊送**，放開熱鍵時只等 finalize。
3. **LLM 清理用最小模型、串流輸出、提示詞快取**，並把字典/片段的套用做在客戶端 Rust（零延遲）。

### 2.5 WebSocket vs HTTP、音訊編碼

- **WebSocket**：必要——interim results 與 finalize 都需要雙向。HTTP chunked 上傳只適合「放開才送整段」的非串流模式（可當 fallback，例如公司防火牆擋 WS）。
- **Opus** ✅/⚠️：xiph/opus README 列出 frame size 2.5 / 5 / 10 / 20 / 40 / 60 ms（預設 20），royalty-free（https://github.com/xiph/opus）。RFC 6716 本次無法讀取 ⚠️（記憶：6–510 kbps、8–48 kHz、預設演算法延遲 26.5 ms）。
- **頻寬數學**：PCM16 @16 kHz mono = 256 kbps = 32 KB/s；Opus 24 kbps = 3 KB/s。10 秒聽寫：320 KB vs 30 KB。桌機有線/WiFi 無感；手機 4G 上傳 Opus 明顯更穩。
- **但要看供應商吃什麼**：OpenAI Realtime 預設 **pcm16 @ 24 kHz**（= 384 kbps），不吃 Opus ⚠️；Deepgram 我記得吃 `opus` / `ogg-opus` ⚠️。在 DO 內轉碼不實際（Workers 無 libopus，WASM 可行但 CPU-ms 計費）。
- **建議**：v1 統一 **PCM16 16 kHz**（Deepgram）或 24 kHz（OpenAI）直通，簡單可靠；手機版 v2 再視供應商加 Opus。客戶端 Rust 核心負責重採樣（48k → 16k/24k）。

### 2.6 端到端延遲預算（放開熱鍵 → 文字出現）

| 階段 | 數字 | 來源 |
|---|---|---|
| 擷取緩衝 | 20–50 ms（cpal / AVAudioEngine buffer） | 設計值 |
| VAD | Silero 每 30 ms chunk < 1 ms；endpoint 靜音判定 300–500 ms（可調） | ✅ silero-vad README；設計值 |
| 網路（台北→美西） | 單程 65–90 ms；WS 已預連則每包只付單程 | ⚠️ 經驗值 |
| 雲端 STT finalize | Deepgram / AssemblyAI 皆宣稱約 300 ms 等級（本次無法核實）| ⚠️ |
| 本地 STT（桌機） | FluidAudio Parakeet CoreML「~190x on M4 Pro」→ 10 s 音訊 ≈ 50 ms；whisper large-v3-turbo Metal 10 s 音訊約 0.5–1.5 s | ✅ / ⚠️ |
| LLM 清理 | Haiku 4.5 串流：TTFT 約 0.3–0.6 s + 輸出 50–150 tokens 約 0.3–0.8 s | ⚠️ 需實測 |
| 注入 | 剪貼簿貼上 50–150 ms（Handy 有可調 delay）；`commitText` / `insertText` < 10 ms | ✅ Handy README |
| **合計（雲端路徑）** | **約 0.9–1.8 s**；若略過 LLM 清理只套字典：**約 0.4–0.7 s** | |
| **合計（桌機本地 Parakeet/CoreML + 無 LLM）** | **約 0.4–0.6 s** | |

→ 產品決策：提供「快速模式（只做字典/標點規則）」與「AI 清理模式」兩檔，讓用戶自選延遲 vs 品質。

---

## 3. 離線 / 本地優先模式

### 3.1 引擎與加速後端 ✅
- **whisper.cpp**（https://github.com/ggml-org/whisper.cpp）：Metal + Core ML（Apple Silicon）、CUDA、ROCm/HIP、Vulkan、OpenVINO、AMD Ryzen AI NPU（VitisAI）、Ascend CANN、MUSA；平台含 iOS / Android / WASM；內建 Silero VAD；整數量化（Q5_0 等）。
- **模型大小**（https://github.com/ggml-org/whisper.cpp/blob/master/models/README.md）：tiny 75 MiB（RAM ~273 MB）、base 142 MiB（~388 MB）、small 466 MiB（~852 MB）、medium 1.5 GiB（~2.1 GB）、large 2.9 GiB（~3.9 GB）、**large-v3-turbo 1.5 GiB、large-v3-turbo-q5_0 547 MiB**。
- **sherpa-onnx**（https://github.com/k2-fsa/sherpa-onnx）：12 種語言綁定（含 Swift、Kotlin、Rust、C、Dart）、平台含 iOS / Android / WearOS / HarmonyOS / RISC-V；模型：Zipformer（串流）、Paraformer、Whisper、SenseVoice、Parakeet；NPU：Rockchip RKNN、Qualcomm QNN、Ascend、Axera、Intel OpenVINO；有預建 Android APK。
- **ONNX Runtime EP 狀態**（https://github.com/microsoft/onnxruntime/blob/gh-pages/docs/execution-providers/index.md）：NNAPI、QNN、DirectML、CUDA、TensorRT、OpenVINO、XNNPACK 為正式；**CoreML 標為 preview**；WebGPU preview；ROCm deprecated。→ Apple 平台上要 ANE 加速，**FluidAudio（原生 CoreML）比 ort-coreml 可靠**。
- **Apple SpeechAnalyzer**（iOS / macOS / visionOS 26+）：on-device、`AssetInventory.assetInstallationRequest(supporting:)` 下載系統模型、`SpeechTranscriber.supportedLocale(equivalentTo:)` 檢查語系、結果以 `AsyncSequence` 串流（https://developer.apple.com/documentation/speech/speechanalyzer）。是否可在鍵盤 extension 內用、zh-TW 品質如何——文件未提 ⚠️。

### 3.2 語言支援——台灣用戶的大坑 ✅
- **Parakeet TDT 0.6B v3 = 25 種歐洲語言**（FluidAudio README；HF 模型卡被封鎖無法再確認）。Handy 的「Parakeet V3 自動語言偵測」對中文無效。
- 本地中文選項：(a) whisper `large-v3-turbo`（zh 可用，但中英夾雜、台灣用語與繁簡需後處理）；(b) **SenseVoice-Small**：zh / yue / en / ja / ko，宣稱比 Whisper-Large 快 15 倍、非自回歸、程式碼 MIT、權重用 FunASR Model License（維護者表示遵守即可商用）、可匯出 ONNX（https://github.com/FunAudioLLM/SenseVoice）；(c) sherpa-onnx 的 zh-en 串流 Zipformer（真串流、CPU 即可）。
- VoiceInk 同時整合 whisper.cpp + Parakeet + SenseVoice，正是為了語言覆蓋。

### 3.3 各平台打包策略

| 平台 | 本地引擎 | 加速 | 模型存放 |
|---|---|---|---|
| macOS | whisper.cpp（`transcribe-cpp` feature `metal`）+ FluidAudio（Swift，走 ANE）| Metal / CoreML | `~/Library/Application Support/<app>/models/`，CoreML 模型由 FluidAudio 自動從 HF 下載（可改自家 registry、支援離線） |
| Windows x64 | whisper.cpp `dynamic-backends + vulkan`（Handy 同款）；ONNX 走 `ort-directml` | Vulkan / DirectML | `%LOCALAPPDATA%\<app>\models\` |
| Windows ARM64 | CPU-only（Handy 現況）；QNN 需 sherpa-onnx | — | 同上 |
| Linux | `dynamic-backends + vulkan` | Vulkan | `~/.local/share/<app>/models/` |
| Android（主 App，不是 IME 進程）| sherpa-onnx（Zipformer 串流 / SenseVoice）| NNAPI / QNN | App 私有儲存；IME 透過 AIDL/Binder 或同進程呼叫 |
| iOS 鍵盤 | **不放模型**；可試 SpeechAnalyzer（系統管理資產，不佔你的記憶體上限 ⚠️）| — | — |

- 模型分發：放 Cloudflare R2（egress 免費 ⚠️ 記憶）+ 自家 manifest（`models.json`：name、size、sha256、url、min_app_version），客戶端支援續傳與校驗；Handy 也允許用戶手動把檔案丟進 `models` 目錄。
- 二進位大小 ⚠️：whisper.cpp 靜態庫數 MB；onnxruntime 每架構約 10–30 MB；加上 Tauri/WebView 殼，桌機安裝檔預估 30–80 MB（不含模型）。

---

## 4. 同步、帳號、遙測、崩潰、Feature Flags、授權

### 4.1 同步與加密
- Epicenter 的做法：local-first、Yjs CRDT、每帳號一個 Durable Object、登入即同步（https://github.com/epicenter-md/epicenter）。`@epicenter/sync` 只負責 WS 握手與 bearer token 子協定，不含 E2EE（https://github.com/epicenter-md/epicenter/blob/main/packages/sync/README.md）。
- **建議資料分級**：
  - 字典 / 片段 / 設定：小、低敏感 → 明文存 Supabase Postgres（RLS by user_id），用 `updated_at` LWW 即可，不需要 CRDT。
  - 聽寫歷史（含原始逐字稿）：高敏感 → **預設只留本機**（Handy / VoiceInk 的賣點），若要跨裝置，用客戶端金鑰加密後存 R2，金鑰經 iCloud Keychain（Apple 內）或 QR 配對交換；跨到 Windows 的 E2EE 金鑰交換是 v2 題目。
  - 音訊：永不上傳儲存（Apple 鍵盤指引也要求不得保留語音資料）。

### 4.2 Auth
- Guideline 4.8：用第三方登入（Google、Facebook…）就必須提供「限制只收 name/email、可隱藏 email、不做廣告追蹤」的等價選項（= Sign in with Apple）；豁免：「Your app exclusively uses your company's own account setup and sign-in systems」等 ✅。
- 推薦：Email magic link / passkey（自家）+ Apple + Google；在 Supabase 原生 Apple 流程用 `signInWithIdToken` 可免 6 個月換 secret。
- 鍵盤 extension 取 token：主 App 登入後把 refresh token 放 App Group 的 Keychain（`kSecAttrAccessGroup`），extension 讀取後向後端換短效 JWT。

### 4.3 遙測 / 崩潰 / Flags
- **TelemetryDeck** Swift SDK：使用者識別先雜湊、伺服器再加鹽、不送 PII；iOS / macOS / watchOS / tvOS / visionOS（https://github.com/TelemetryDeck/SwiftSDK）；Kotlin / Rust SDK 與定價本次未能核實 ⚠️。
- **PostHog** ⚠️：網站被封鎖；記憶中免費額度 100 萬事件/月、含 feature flags、有 EU 雲。
- **Sentry**：Rust SDK（MSRV 1.88、pre-1.0）✅；Cocoa / Android SDK 存在但本次未讀；價格 ⚠️。
- **Feature flags**：最便宜是自家 `GET /config`（Workers KV 快取的 JSON，含 model 路由、提示詞版本、配額），客戶端每小時拉一次。

### 4.4 授權 / 權益
| 平台 | 方案 | 核實 |
|---|---|---|
| iOS + macOS（App Store）| RevenueCat：purchases-ios 支援 iOS 13+、macOS 10.15+、Mac Catalyst、visionOS、StoreKit 2 | ✅ https://github.com/RevenueCat/purchases-ios ；定價 ⚠️（記憶：月追蹤收入 US$2.5k 以下免費，之後約 1%）|
| macOS（App Store 外）+ Windows + Linux | **Keygen**：license key、machine activation、entitlements、Ed25519 離線授權；CE 可自架（Fair Core License → 2 年後 Apache-2.0）；EE 付費（audit log、SSO…）| ✅ https://github.com/keygen-sh/keygen-api ；雲端定價 ⚠️ |
| 同上（想要 MoR 幫你處理各國稅務）| **Lemon Squeezy** License API：`activateLicense` / `validateLicense` / `deactivateLicense`；SDK 警告勿在瀏覽器暴露 API key | ✅ https://github.com/lmsqueezy/lemonsqueezy.js ；license 端點是否免 API key、手續費 ⚠️（記憶：5% + US$0.50）|
| 自家 | Supabase `entitlements` 表 + Stripe/Paddle webhook；客戶端只信後端簽發的 JWT claims | 設計 |

**建議**：單一真相放在你的 Postgres `entitlements`（來源欄位：`apple_iap` / `google_play` / `stripe` / `license_key`），所有客戶端只看 JWT 裡的 `plan`、`quota`、`exp`；RevenueCat / Keygen 只是「來源」。

---

## 5. Repo 結構與 CI

### 5.1 Monorepo 佈局
```
atype/
├─ core/                     # Rust workspace
│  ├─ atype-core/            # 音訊、VAD、STT trait、cleanup、API client（#[uniffi::export]）
│  ├─ atype-engines/         # feature-gated：whisper (transcribe-cpp)、onnx (transcribe-rs / sherpa-onnx)
│  └─ atype-ffi/             # uniffi-bindgen-swift / kotlin 產物、XCFramework 腳本
├─ apps/
│  ├─ desktop/               # Tauri 2（React/Svelte）；src-tauri 依賴 atype-core
│  ├─ ios/                   # Xcode: App + KeyboardExtension（Swift Package 依賴 AtypeCore.xcframework）
│  ├─ android/               # Gradle: app + ime module（依賴 core-android .aar + Kotlin bindings）
│  └─ macos-native/          # （可選）若未來改原生 Swift menubar app，與 ios/ 共用 Swift package
├─ packages/
│  ├─ protocol/              # WS 協定 schema（JSON Schema / protobuf）→ 產生 TS/Swift/Kotlin/Rust 型別
│  └─ prompts/               # LLM 清理提示詞版本化
├─ backend/
│  ├─ worker/                # Cloudflare Workers + DO（TypeScript, wrangler）
│  └─ supabase/              # migrations、RLS policies、edge functions（可選）
├─ infra/                    # models.json manifest、R2 上傳腳本
└─ .github/workflows/
```
- 版本一致性：`protocol/` 單一來源，CI 比對產生檔是否過期。
- Rust → Swift：`cargo build --target aarch64-apple-ios / aarch64-apple-ios-sim / aarch64-apple-darwin` → `uniffi-bindgen-swift --xcframework` → `xcodebuild -create-xcframework` → SwiftPM binary target。
- Rust → Kotlin：`cargo ndk -t arm64-v8a -t x86_64 build` → `uniffi-bindgen generate --language kotlin` → `.aar`；Kotlin 端 `&[u8]` 參數要用 `ByteBuffer`（0.32 breaking）。

### 5.2 CI（GitHub Actions）✅
- Runner 影像（https://github.com/actions/runner-images）：`macos-latest`（arm64）、`macos-26`、`macos-15`（arm64）、`macos-14` **已標 deprecated**、`ubuntu-24.04` / `ubuntu-26.04-arm` / `ubuntu-24.04-arm`、`windows-11-arm`。
- 計費：公開 repo 標準 runner 免費；文件範例「3,000 Linux minutes at $0.006 USD per minute」「2,000 Windows minutes at $0.010 USD per minute」（https://github.com/github/docs/blob/main/content/billing/concepts/product-billing/github-actions.md）；macOS 每分鐘價與各方案免費分鐘數本次未能讀到 ⚠️（記憶：macOS US$0.08/分鐘、Free 方案 2,000 分鐘/月、macOS 以 10 倍計）。→ **私有 repo 的 macOS 建置會是 CI 主要成本，iOS/macOS 工作流要用 cache 與 path filter。**
- Tauri 桌機：`tauri-apps/tauri-action` 範例矩陣 `macos-latest`（`aarch64-apple-darwin` / `x86_64-apple-darwin`）、`ubuntu-22.04`、`windows-latest`；`mobile: "android" | "ios"` 為實驗性，只產 `.apk` / `.ipa`、不上傳商店（https://github.com/tauri-apps/tauri-action）。
- macOS 簽章/公證環境變數：`APPLE_CERTIFICATE`（base64 .p12）、`APPLE_CERTIFICATE_PASSWORD`、`APPLE_SIGNING_IDENTITY`、`KEYCHAIN_PASSWORD`；公證二選一：`APPLE_API_ISSUER` + `APPLE_API_KEY` + `APPLE_API_KEY_PATH`，或 `APPLE_ID` + `APPLE_PASSWORD`（app-specific）+ `APPLE_TEAM_ID`；App Store 外用 **Developer ID Application**、App Store 用 Apple Distribution；簽章後自動公證（https://github.com/tauri-apps/tauri-docs/blob/v2/src/content/docs/distribute/Sign/macos.mdx）。
- iOS（含鍵盤 extension）**不要用 tauri-action**，用 `xcodebuild -exportArchive` + fastlane（`match` 文件本次無法讀取 ⚠️；記憶：憑證放 git/S3/GCS，CI 用 `readonly: true` + App Store Connect API key）。
- Windows 簽章：Azure Trusted Signing 或 EV 憑證（本次未研究）。

---

## 6. 參考架構圖與變體

### 6.1 推薦：變體 B「Tauri 桌機 + 原生手機鍵盤 + Rust 核心 + CF/Supabase」

```mermaid
flowchart LR
  subgraph Desktop["桌機 (Tauri 2: macOS / Windows / Linux)"]
    DK[熱鍵 rdev] --> DC[atype-core (Rust)]
    DC -->|PCM16| DL[本地引擎<br/>whisper.cpp / sherpa-onnx / FluidAudio]
    DC -->|PCM16 over WS| WS
    DC --> DI[文字注入 enigo / 剪貼簿]
  end
  subgraph iOS["iOS App + Keyboard Extension (Swift)"]
    IK[鍵盤 UI] -->|AVAudioEngine PCM| IC[AtypeCore.xcframework<br/>(VAD + API client + cleanup)]
    IC -->|WS| WS
    IC --> IT[insertText]
  end
  subgraph Android["Android App + IME (Kotlin)"]
    AK[IME UI] -->|AudioRecord PCM| AC[core-android .aar]
    AC -->|WS| WS
    AC --> AT[commitText]
  end
  subgraph CF["Cloudflare (Workers Paid, hint apac-ne)"]
    WS[/Worker: /ws 驗 JWT/] --> DO[(DictationSession DO<br/>計量 + SQLite)]
    DO -->|WS 直通| STT[Deepgram / OpenAI Realtime]
    DO -->|HTTP 串流| LLM[Claude Haiku 4.5 / 其他]
    KV[(KV: /config flags, prompts)]
    R2[(R2: models.json + 模型檔)]
  end
  subgraph SB["Supabase (ap-northeast-1 Tokyo)"]
    AUTH[Auth: Apple / Google / Magic link]
    PG[(Postgres: users, entitlements,<br/>dictionary, snippets, usage_daily)]
  end
  DC & IC & AC -->|JWT| AUTH
  DO -->|usage upsert (batched)| PG
  RC[RevenueCat / Keygen / Lemon Squeezy] -->|webhook| PG
```

### 6.2 三個變體比較

| | **A. 原生到底 + Rust 核心**（Swift mac/iOS、Kotlin Android、Windows 用 Tauri 或 C#） | **B. Tauri 桌機 + 原生手機 + Rust 核心（推薦）** | **C. 不共享核心，原生薄客戶端 + 胖後端** |
|---|---|---|---|
| 桌機三平台成本 | 高（mac 原生一份、Windows/Linux 另一份） | **低**（Handy 已驗證一份碼三平台） | 中（仍要三份殼） |
| macOS 體驗 | 最好（menubar、Accessibility、低記憶體） | 好（Tauri 用系統 WebView，Handy 證明可接受） | 視殼而定 |
| 手機鍵盤 | 原生 | 原生 | 原生 |
| 離線模式 | 桌機可、Android 可 | 桌機可、Android 可 | **無** |
| 共享邏輯位置 | Rust 核心 | Rust 核心 | 後端 |
| 1–2 人上手 | 需 Swift + Kotlin + Rust + (C#) | 需 TS + Rust + Swift + Kotlin | 需 Swift + Kotlin + 一種桌機技術 + 後端 |
| 第一個可售版本 | 最慢 | 中 | **最快**（但只有雲端） |
| 風險 | 人力 | Tauri 3 alpha 轉換期；WebView 差異 | 供應商鎖定、無隱私賣點 |

**為什麼選 B**：桌機是這類產品的營收主力，Tauri 讓 1–2 人一次覆蓋三平台（Handy 32.5k★ 是最好的證據）；手機不管哪個變體都得原生；Rust 核心讓桌機本地引擎與雲端 client 一份碼，手機只取用其中的小子集（VAD、協定、cleanup），不帶推論 runtime。

### 6.3 分階段落地
1. **Phase 1（0–8 週）**：`backend/worker` DO 代理 + Supabase Auth；`atype-core` 僅含 API client + VAD + cleanup；Tauri 桌機（mac 先）雲端模式；Keygen 或 Lemon Squeezy 授權。
2. **Phase 2（8–16 週）**：桌機本地引擎（`transcribe-cpp` metal / vulkan；中文用 large-v3-turbo-q5_0 547 MiB + SenseVoice）；Windows/Linux 打包；RevenueCat 上 Mac App Store（可選）。
3. **Phase 3（16–28 週）**：iOS 鍵盤（Full Access 錄音驗證通過才做）+ Android IME；UniFFI XCFramework / AAR 管線；字典/片段同步。

---

## 7. 對我們的設計意涵

1. **把「鍵盤能不能錄音」當第一個 spike**：iOS 真機測 `AVAudioSession` 在 keyboard extension（Full Access 開啟）能否錄音；若不行，備案是「鍵盤按鈕 → 以 URL scheme 跳主 App 錄音 → 文字經 App Group 回鍵盤」的流程（體驗差一截，Apple 4.4.1 也只允許開 Settings，跳主 App 的作法需查審核風險）。
2. **核心 API 以 `&[u8]` / `&[i16]` 餵 PCM，不要用 `Vec<u8>`**（UniFFI 0.32 零拷貝），Kotlin 端配 `ByteBuffer`。
3. **一條統一的 WS 協定**（`protocol/`）：客戶端↔你的 DO，與供應商無關；供應商切換只改 DO。訊息：`{type:"start", sr:16000, lang:"zh-TW", mode:"fast|ai"}`、二進位 PCM、`{type:"partial"|"final"|"cleaned"}`、`{type:"stop"}`。
4. **預連線 + KeepAlive**：熱鍵按下前已有 WS；DO 一次 session 結束要 `close()` 上游，避免 15 分鐘活躍計費。
5. **語言策略**：雲端 Nova-3 / gpt-4o-transcribe 對中英夾雜較穩；本地中文走 whisper large-v3-turbo-q5_0 或 SenseVoice；**不要承諾 Parakeet 中文**。
6. **延遲雙模式**：「快速」（STT + 客戶端規則）與「AI 清理」（+ Haiku 串流），讓用戶自選。
7. **後端放東京**（Supabase `ap-northeast-1`、DO `apac-ne`），但要向用戶誠實：雲端模式延遲取決於供應商機房。
8. **隱私為賣點**：音訊不落地、歷史預設本機；這同時滿足 Apple 鍵盤指引。
9. **CI 成本**：私有 repo 的 macOS 分鐘數是大頭；iOS/macOS workflow 只在 `apps/ios/**`、`core/**` 變更時跑。
10. **別碰 whisper-rs / sherpa-rs**（皆已封存）；用 `transcribe-cpp`、`transcribe-rs` 或 sherpa-onnx 官方 crate。
11. **Tauri 3 alpha 已出**：鎖 2.12.x，待 3.0 穩定再遷。
12. **授權單一真相在自家 Postgres**，RevenueCat / Keygen / Lemon Squeezy 只是來源。

---

## 8. 未解問題（依影響排序）

1. **【關鍵】iOS keyboard extension 開啟 Full Access 後能否使用麥克風？** Apple 現行文件未明說、archive 文件說不行、業界產品（Gboard、Wispr Flow）似乎可以 ⚠️。需真機實測；結果決定 iOS 鍵盤的整個互動模型。
2. **【關鍵】Deepgram / OpenAI 託管 STT 是否有亞太端點？** 文件被封鎖 ⚠️。若無，雲端路徑固定多 130–180 ms；可考慮 ElevenLabs Scribe、AssemblyAI、Azure Speech（有 East Asia / Japan East 區域 ⚠️）或 self-hosted（Deepgram 需企業合約 ⚠️）。
3. **【關鍵】iOS 鍵盤 extension 的實際記憶體上限**（傳聞 50–70 MB ⚠️）與 UniFFI XCFramework（含 onnxruntime 或不含）的 footprint。決定核心能否進鍵盤。
4. **SpeechAnalyzer（iOS 26）是否支援 zh-TW、是否可在 extension 內用、品質如何**——若可，iOS 鍵盤有零成本離線模式。
5. **Deepgram 串流支援的 encoding 清單與 Opus 是否可直通**；OpenAI transcription session 是否只收 pcm16/g711。決定手機是否要做 Opus。
6. **各家確切價格**：Deepgram Nova-3 串流、gpt-4o-transcribe、RevenueCat、Keygen Cloud、Lemon Squeezy 手續費、PostHog / TelemetryDeck / Sentry、GitHub Actions macOS 分鐘價——本次全部無法讀取。
7. **Lemon Squeezy license 端點是否可從桌機客戶端直接呼叫（免 API key）**；Stripe 在台灣的可用性與 MoR 稅務（Paddle vs Lemon Squeezy）。
8. **Cloudflare 台北 POP 與 Workers 是否在台北執行**；DO `apac-ne` 實際落在東京還是大阪/首爾。
9. **Tauri iOS 專案內嵌 extension 的簽章流程**（#15663 未修）——若 Phase 3 想讓 iOS 主 App 也用 Tauri，需自建 `xcodebuild` 流程；否則 iOS 主 App 直接原生 Swift 更省事。
10. **Windows ARM64 的本地推論**（Handy 目前 CPU-only）：sherpa-onnx QNN 在 Snapdragon X 的可用性。
11. **Supabase Edge Functions 的執行時間/記憶體上限**（確認不適合長連線）。
12. **E2EE 跨 Apple/Windows 的金鑰交換 UX**（Phase 3 之後）。

---

## 來源清單（本次實際讀取）

- UniFFI：https://github.com/mozilla/uniffi-rs ；https://github.com/mozilla/uniffi-rs/blob/main/CHANGELOG.md ；https://github.com/mozilla/uniffi-rs/blob/main/docs/manual/src/swift/uniffi-bindgen-swift.md ；https://github.com/mozilla/uniffi-rs/blob/main/docs/manual/src/swift/xcode.md
- Tauri：https://crates.io/api/v1/crates/tauri ；https://github.com/tauri-apps/tauri/issues/15663 ；https://github.com/tauri-apps/tauri-docs/blob/v2/src/content/docs/develop/Plugins/develop-mobile.mdx ；https://github.com/tauri-apps/tauri-docs/blob/v2/src/content/docs/distribute/Sign/macos.mdx ；https://github.com/tauri-apps/tauri-action
- Handy：https://github.com/cjpais/Handy ；https://github.com/cjpais/Handy/blob/main/src-tauri/Cargo.toml ；https://github.com/cjpais/transcribe-rs
- Epicenter / Whispering：https://github.com/epicenter-md/epicenter ；https://github.com/epicenter-md/epicenter/blob/main/apps/whispering/README.md ；https://github.com/epicenter-md/epicenter/blob/main/packages/sync/README.md
- VoiceInk：https://github.com/Beingpax/VoiceInk ；FluidAudio：https://github.com/FluidInference/FluidAudio
- 引擎：https://github.com/ggml-org/whisper.cpp ；https://github.com/ggml-org/whisper.cpp/blob/master/models/README.md ；https://github.com/k2-fsa/sherpa-onnx ；https://github.com/k2-fsa/sherpa-onnx/tree/master/rust-api-examples ；https://github.com/thewh1teagle/sherpa-rs ；https://github.com/tazz4843/whisper-rs ；https://github.com/snakers4/silero-vad ；https://github.com/FunAudioLLM/SenseVoice ；https://github.com/microsoft/onnxruntime/blob/gh-pages/docs/execution-providers/index.md ；https://github.com/xiph/opus
- Apple：https://developer.apple.com/app-store/review/guidelines/ ；https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard ；https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard ；https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html ；https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionOverview.html ；https://developer.apple.com/documentation/speech/speechanalyzer
- Android：https://developer.android.com/develop/ui/views/touch-and-input/creating-input-method ；https://github.com/ElishaAz/Sayboard
- Cloudflare（docs 原始碼）：https://github.com/cloudflare/cloudflare-docs/blob/production/src/content/docs/workers/platform/pricing.mdx ；…/workers/platform/limits.mdx ；…/durable-objects/platform/pricing.mdx ；…/durable-objects/platform/limits.mdx ；…/durable-objects/best-practices/websockets.mdx ；…/durable-objects/reference/data-location.mdx
- Supabase：https://github.com/supabase/supabase/blob/master/packages/shared-data/plans.ts ；https://github.com/supabase/supabase/blob/master/apps/docs/content/guides/functions/regional-invocation.mdx ；https://github.com/supabase/supabase/blob/master/apps/docs/content/guides/auth/social-login/auth-apple.mdx
- STT 供應商：https://github.com/deepgram/deepgram-js-sdk ；https://github.com/deepgram/self-hosted-resources ；https://github.com/openai/openai-realtime-api-beta ；https://github.com/openai/openai-python
- 授權/遙測：https://github.com/RevenueCat/purchases-ios ；https://github.com/keygen-sh/keygen-api ；https://github.com/lmsqueezy/lemonsqueezy.js ；https://github.com/TelemetryDeck/SwiftSDK ；https://github.com/getsentry/sentry-rust
- CI：https://github.com/actions/runner-images ；https://github.com/github/docs/blob/main/content/billing/concepts/product-billing/github-actions.md
- KMP：https://github.com/JetBrains/compose-multiplatform
- Claude 價格：本機 `claude-api` skill（快取 2026-09-25）；官方 https://docs.anthropic.com/en/docs/about-claude/pricing
