# 研究報告索引（2026-10-01）

這 11 份報告是「自製 Typeless（桌機 + 手機）」方案的事實基礎，由 11 個平行研究代理產出，之後再對每份報告最關鍵的 5 條主張做對抗式查證（結果見 [`_verification.md`](./_verification.md)，**查證後的修正版優先於報告原文**）。

## 先讀這段：研究環境的限制

- 研究是在受限的雲端容器內進行，出口代理封鎖了多數商業網站：`typeless.com`、`wisprflow.ai`、`superwhisper.com`、`apps.apple.com`、`play.google.com`、`stripe.com`、`paddle.com`、`learn.microsoft.com`、`support.google.com`、`openai.com`、`deepgram.com`、`huggingface.co`、`arxiv.org` 等。能直接讀到一手來源的主要是 **Apple Developer、Android Developers、Google Cloud、Anthropic/Claude Platform、GitHub（含 raw 原始碼）、Cloudflare/Supabase 文件原始碼**。
- 因此：**競品定價、第三方 API 價格、Play/Store 政策細節**多半來自搜尋摘要或第三方整理頁（部分整理頁本身是競品部落格，有利益衝突），報告內一律標示「待驗證」「⚠」「[二手]」。**開源專案的技術細節**則是直接 clone 並讀原始碼，可信度高。
- 每份報告末尾都有「未解問題」清單；所有需要真機或官方頁面才能確認的項目，已彙整進 [`../PLAN.md`](../PLAN.md) 的「第 0 週驗證清單」。

## 報告清單

| # | 檔案 | 主題 | 一句話結論 |
|---|---|---|---|
| 1 | [typeless-teardown.md](./typeless-teardown.md) | Typeless 產品拆解 | Typeless 體驗 = 全域快捷鍵 + 底部膠囊 HUD + 串流 STT → LLM 清理 + Dictate/Translate/Ask 三入口 + 詞典/History；純雲端（AWS us-east-2）、延遲約 3 秒、單次 6 分鐘上限、iOS 鍵盤佔用 emoji 鍵、Android 無軟鍵盤是主要抱怨點 |
| 2 | [competitors-and-oss.md](./competitors-and-oss.md) | 競品與開源生態 | 市場已收斂為同一形態、Pro 定價 US$12/月年繳；**Handy（Rust + Tauri 2，MIT，32.5k★）**已解掉桌機最難的三件事（純修飾鍵熱鍵、收據式貼上、Linux 工具鏈），是桌機端的藍圖 |
| 3 | [stt-engines.md](./stt-engines.md) | STT 引擎（雲端 + 本地） | zh-TW 本地首選 Apple iOS/macOS 26 `SpeechTranscriber`（零成本、含 zh-TW）；非 Apple 平台用 sherpa-onnx + SenseVoice-Small；雲端普通話最佳為 ElevenLabs Scribe v2；Whisper 家族簡繁混出、Parakeet 無中文 |
| 4 | [llm-postprocess.md](./llm-postprocess.md) | LLM 後處理層 | 聽寫 App 的「智慧」幾乎全在 ASR 之後的一次 LLM 呼叫；繁簡（OpenCC）、中英空格（pangu）、全形標點要用確定性規則保證；附完整 zh-TW system prompt 與延遲預算 |
| 5 | [desktop-macos.md](./desktop-macos.md) | macOS 技術 | 文字注入以「剪貼簿 + ⌘V + 收據式還原」為主；Fn 鍵靠 CGEventTap `flagsChanged` keycode 63；只需 Microphone + Accessibility；不上 Mac App Store |
| 6 | [desktop-windows-linux.md](./desktop-windows-linux.md) | Windows / Linux 技術 | Windows 用 `WH_KEYBOARD_LL` + 剪貼簿收據貼上（`WM_RENDERFORMAT`）；Linux 分 X11 / KDE Wayland / GNOME Wayland 三種 profile，GNOME Wayland 連寫剪貼簿都會失敗 |
| 7 | [ios-keyboard.md](./ios-keyboard.md) | iOS 鍵盤擴充 | 鍵盤 extension 無法錄音、記憶體上限約 30–60 MB；所有上架產品都是「鍵盤當遙控器 → 主 App 錄音 → App Group + Darwin notification 回傳」；iOS 26 `SpeechTranscriber` 與 `AudioRecordingIntent`（Action Button）是新武器 |
| 8 | [android-ime.md](./android-ime.md) | Android IME | 做成 `imeSubtypeMode="voice"` + `isAuxiliary="true"` 的輔助語音 IME；IME 可見時可直接錄音不需 FGS；Gboard/Samsung 麥克風鍵寫死不交接，需 Tile 入口 |
| 9 | [business-privacy-store.md](./business-privacy-store.md) | 商業、法遵、上架 | COGS 典型用戶 US$2–4/月、重度用戶可達 $8–13；台灣收款走 MoR（Paddle）+ Apple IAP + Play Billing；iOS 審查三地雷 4.4.1 / 2.5.14 / 5.1.2(i) |
| 10 | [product-ux.md](./product-ux.md) | 產品 UX 規格 | 互動模型已收斂為「按住說話、放開一次貼上」；附 HUD 狀態機、插入階梯、iOS 交接序列圖、設定 schema、MVP/v1/Later 功能優先序 |
| 11 | [backend-architecture.md](./backend-architecture.md) | 後端與共享核心 | Tauri 不能做 iOS 鍵盤或 Android IME；共享核心用 Rust + UniFFI；後端 Cloudflare Workers + Durable Objects + Supabase Tokyo；台灣延遲瓶頸在 STT 供應商機房 |
| — | [_verification.md](./_verification.md) | 關鍵主張查證 | 55 條關鍵主張的對抗式查證結果（確認 / 修正 / 不確定），修正版優先 |

## 查證後最重要的修正

1. **Typeless 預設快捷鍵**：官方說明中心記載 macOS 為 `Fn`（Dictate）/ `Fn+Left Shift`（Translate）/ `Fn+Space`（Ask anything），Windows 為 `Right Alt` / `Right Alt+Right Shift` / `Right Alt+Space`，皆為「點一下開始、再點一下結束」的 toggle；「Windows 按住 Ctrl+Win」是第三方開源仿製品的 issue，不是 Typeless 官方預設。
2. **Typeless 免費額度**：多個讀取官方用量 API 的第三方工具一致顯示已從 8,000 字/週降為 2,000 字/週（約 2026-09 中旬、2.7.0/2.8.0 前後），新帳號 Pro 試用期實測為 3 天而非 30 天；官方定價頁本次無法直接讀取。
3. **iOS 鍵盤麥克風**：Apple 現行文件把「No access to microphone and speaker」列在未開 Full Access 的限制清單，開啟 Full Access 的能力清單也**沒有**加入麥克風；多個 2026 年開源專案實測 `AVAudioEngine.start()` 在 extension 內即使有 Full Access 仍失敗。查證者之間對「文件是否絕對禁止」有分歧，但**所有上架產品（Wispr Flow、Typeless、Dictus）都採主 App 錄音**。設計上以主 App 錄音為準，並把「extension 內錄音」列為第 0 週 spike。
4. **Apple `SpeechTranscriber.supportedLocales`**：Apple 未公布數量；社群實測回傳 30 個 locale（依 OS 版本與裝置約 30–45），**一致包含 zh-TW、zh-CN、zh-HK、yue-CN**。
5. **Qwen3-ASR**：2026-01-29 以 Apache-2.0 開源 0.6B / 1.7B；1.7B 在 AISHELL-2 WER 2.71（Whisper-large-v3 5.06）；串流推理目前僅支援 vLLM 後端。
6. **FUTO Voice Input 相容性**：Gboard 與 Samsung Keyboard 的麥克風鍵 hardcoded 不交接第三方；可交接的有 HeliBoard、FlorisBoard、AnySoftKeyboard、Unexpected Keyboard、AOSP Keyboard、Grammarly、SwiftKey。
7. **Whisper 簡繁混出**：OpenAI 維護者在 discussion #277 表示「預期」訓練資料繁簡混雜（而非確認）；`initial_prompt` 引導在 large-v3 上「有時」失效，確定性解法是事後用 OpenCC / zhconv 轉換。
