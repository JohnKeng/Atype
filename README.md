# Atype

**按住一顆鍵說話，放開就得到可以直接送出的繁體中文——中英夾雜不翻譯、不出簡體、不改你的意思。** 桌機（macOS / Windows，之後 Linux）與手機（iOS / Android）同一個帳號、同一本詞典。

這是一個「自製 Typeless」的專案。目前 repo 只有**研究與可執行方案**，還沒有程式碼；方案以 2026-10-02 的事實為準，所有無法用一手來源核實的數字都標 ⚠。

## 從哪裡開始讀

| 想知道 | 讀這份 |
|---|---|
| 最終要怎麼做（架構、選型、12 週計畫、成本、風險、第一週任務） | [`docs/PLAN.md`](docs/PLAN.md) |
| 為什麼這樣選（11 份研究報告，含原始碼級細節與來源 URL） | [`docs/research/README.md`](docs/research/README.md) |
| 關鍵主張有沒有被查證、哪些被修正 | [`docs/research/_verification.md`](docs/research/_verification.md) |
| 三條路線（MVP-first / Local-first / Quality-first）各自長什麼樣、評審怎麼打分 | [`docs/design/`](docs/design/) |
| 第一版方案被挑出哪些問題、第二版怎麼改 | [`docs/design/_critique-of-plan-v1.md`](docs/design/_critique-of-plan-v1.md)、`docs/PLAN.md` 末尾的變更紀錄 |

## 十句話版本的結論

1. **骨架：薄客戶端 + 胖後端。** 桌機 fork MIT 授權的 [Handy](https://github.com/cjpais/Handy)（Tauri 2 + Rust）當殼，全域熱鍵、收據式剪貼簿貼上、Secure Input 處理、三平台打包全部繼承；所有「智慧」（STT 代理、LLM 清理、繁體正規化、詞典、計量）集中在一個 Cloudflare Worker + Durable Object。
2. **手機一定是原生薄客戶端。** iOS 鍵盤 extension 不能錄音、記憶體上限約 30–60 MB，所以鍵盤只做 `insertText`，錄音與辨識在主 App，透過 App Group + Darwin notification 交接；Android 做成 `imeSubtypeMode="voice"` 的輔助語音 IME。Tauri 做不了這兩件事。
3. **STT 分層。** 桌機 MVP 走雲端串流（ElevenLabs Scribe v2 Realtime / Deepgram Nova-3 zh-TW / Azure 於第 1 週用自建台灣口音測試集決勝）；iOS Free 用 Apple `SpeechTranscriber(zh_TW)`（純裝置端、零成本），Pro 走雲端；macOS 本地層（Apple 原生）第 4 個月進來，SenseVoice / Breeze-ASR-25 第 6 個月。Whisper 家族簡繁混出、Parakeet 無中文，不用。
4. **中文品質是護城河，但靠確定性層保證。** OpenCC s2twp（含占位符保護詞典條目）→ 口語指令 regex → 拼音滑窗詞典 → LLM（預設 `claude-haiku-4-5`，Gemini 3.1 Flash-Lite / Groq 做 A/B）→ pangu 中英空格 → 全形標點。簡體洩漏率 0、注入通過率 ≥ 98% 是 CI 的 PR gate。
5. **延遲目標誠實寫。** 放開熱鍵到文字落地：第 3 週硬門檻 p50 ≤ 1.5 s / p95 ≤ 2.5 s，v1 目標 1.2 s；0.5 s pre-roll 環形緩衝、熱鍵按下即預開上游、LLM 逾時 2.0 s 就貼確定性結果。
6. **熱鍵。** macOS 預設 Fn（無 Apple 鍵盤自動改 Right Option），Windows 預設 Right Ctrl（提供「Typeless 遷移」預設組 Right Alt）；hold = 按住說話、tap = 切換；Fn 單按放行給系統，不破壞台灣用戶切輸入法的習慣。
7. **隱私三級寫死在 UI 與政策。** 全本地 / 文字上雲 / 音訊上雲各自獨立同意與計量；音訊永不落地；永不送視窗標題、URL、App 名；History 本機 SQLCipher。
8. **定價。** Free 雲端 1,500 字/週（耗盡後雲端 STT 與 LLM 都關，Apple 平台退本地）；Pro US$10/月年繳（NT$299）、$12 月繳，公平使用 120,000 字/月；第 6 個月本地引擎落地後降到 $8 並推桌機 Lifetime。
9. **成本。** 第一年固定成本約 US$1.9–2.9k；Pro 典型用戶 COGS MVP 期約 $4.2，本地引擎後 $1–1.5。
10. **兩個停損點。** 第 6 週（Paddle 收款上線 + iOS go/no-go）、第 10 週（iOS 送審 + Windows 起手）；第 1 週的每個 spike 都有寫好的備案。計畫同時提供 2 人版與 1 人版時程。

## 研究方法與限制（請先看）

- 研究由 11 個平行代理完成，每份報告最關鍵的 5 條主張再由獨立代理以一手來源嘗試反駁（55 條：44 確認、11 修正）；三條路線各寫成完整方案後由三位不同視角的評審打分，勝出者嫁接其他兩份的優點成為最終方案，再經一輪完整性批評與修訂。
- 研究環境的出口代理封鎖了多數商業網站（typeless.com、wisprflow.ai、App Store、Stripe、learn.microsoft.com 等），能直接讀的一手來源主要是 Apple / Android / Google Cloud / Anthropic 的開發者文件與 GitHub 原始碼。**競品定價與第三方 API 價格多為二手，動工當週務必親自核對**；開源專案的技術細節則是直接讀原始碼，可信度高。
- 已於 2026-10-02 用官方頁面複核的事實：iOS 27.0.1 / macOS 27.0.1 於 2026-09-28 發布（計畫以 27 為現行、26 為前一版）；Google Play 16 KB page size 自 2027-02-01 起強制；Supabase Auth 以非對稱金鑰簽 JWT、後端用 JWKS 驗證。

## 第一週就能動手的事

詳見 `docs/PLAN.md` 第 12 節。濃縮版：

1. 開帳號與金鑰：Apple Developer、Cloudflare Workers Paid、Supabase（Tokyo）、Anthropic / ElevenLabs / Deepgram / Azure Speech、Paddle 與備案 MoR 的賣家 KYC、Azure Trusted Signing 身分驗證試開。
2. `git subtree add` Handy v0.9.7 到 `apps/desktop`，先確認原版在 macOS 27 能跑；開 Worker 骨架與 Supabase migrations。
3. 錄 2 位講者 × 40 句的台灣口音黃金測試集（含中英夾雜、贅詞、自我更正、數字、注入攻擊），跑 STT 與 LLM bake-off。
4. iOS 真機 spike（iOS 27 + 26）：鍵盤 → 主 App → App Group → 插字的 round-trip、無 Full Access 的行為、`SpeechTranscriber.supportedLocales`、背景錄音存活、Action Button 入口。
5. macOS spike：Default `flagsChanged` CGEventTap 在 macOS 27 的授權歸屬；Developer ID 簽章 + 公證走通。
6. 寫下 `docs/w1-decisions.md`：每個 spike「可 / 不可 + 備案」。

## 狀態

- [x] 研究（11 份）與查證
- [x] 三條路線提案與評審
- [x] 最終方案 v1 → 完整性批評 → v2（`docs/PLAN.md`）
- [ ] 第一週 spike 與 bake-off（需要真機與可上網環境）
- [ ] 程式碼
