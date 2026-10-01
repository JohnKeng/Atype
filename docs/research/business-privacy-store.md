# Typeless-like 產品的商業、法遵與上架研究（台灣 1–2 人團隊視角）

研究日期：2026-10-01。
取材限制：本次 session 的網路搜尋額度已用罄，且 egress proxy 封鎖了多數商業網站（typeless.com、wisprflow.ai、superwhisper.com、stripe.com、paddle.com、lemonsqueezy.com、revenuecat.com、support.google.com、learn.microsoft.com、law.moj.gov.tw、tipo.gov.tw 等）。能直接讀到的一手來源為 **Apple Developer、Android Developers、Google Cloud、Anthropic/Claude Platform、GitHub（含 raw）**。競品定價與 STT 價格部分引用本專案同梯次研究（`competitors-and-oss.md`、`typeless-teardown.md`、`stt-engines.md`、`llm-postprocess.md`）已帶 URL 的結論，以及 LiteLLM 的公開價格表鏡像。凡是**無法一手驗證**的數字都標示「⚠ 未驗證」，請在動手前自行確認。

---

## 0. 執行摘要（Executive Summary）

1. **定價錨點已經固定**：Pro 幾乎都落在 **US$12/月（年繳）、$15/月（月繳）**，免費層 **2,000 字/週**。Typeless 月繳 $30 最貴、免費 8,000 字/週最大方（但有兩個非官方訊號指出 2026-09-22 起降到 2,000 字/週）。本地優先產品則賣終身：VoiceInk $25–49、Superwhisper $249.99。（來源：同梯次研究整理，官方頁面本次被擋）
2. **單位經濟非常健康，但重度用戶會吃掉毛利**：以 3,000 字/天估，雲端 STT（Deepgram Nova-3 / OpenAI gpt-4o-mini-transcribe）每月約 **$1.3–2.6**，LLM 潤飾（Gemini Flash-Lite / gpt-4.1-nano / Claude Sonnet 5.5+cache）每月 **$0.2–1.5**，合計 COGS ≈ **$2–4/月**；定價 $8–12 時毛利 60–80%。但 10,000 字/天的用戶 COGS 可到 **$8–13/月**，必須靠「本地 STT 免費層 + 雲端公平使用上限」兜住。
3. **從台灣收錢的現實**：Stripe 的「支援國家」清單裡沒有台灣（⚠ 本次無法開啟 stripe.com 驗證，但這是多年現況），1–2 人團隊最省事的是 **Merchant of Record（Paddle / Lemon Squeezy / Polar）** 代收代繳全球稅務；手機端走 **Apple IAP（Small Business Program 15%）** 與 **Google Play Billing**，用 RevenueCat 把三邊訂閱狀態統一。
4. **桌面端不要上 Mac App Store**：聽寫工具需要 Accessibility / CGEvent 貼字，與 MAS 強制的 App Sandbox 衝突；走 **Developer ID + Hardened Runtime + notarization + Sparkle 2**（Apple 一手文件已確認流程）。Windows 走 NSIS/MSI + Azure Trusted Signing（已更名 Artifact Signing，⚠ 台灣是否在開放名單待確認）。
5. **iOS 審查的三個地雷**：4.4.1 鍵盤 extension「沒有 Full Access 也要能用」、2.5.14「錄音必須有明確提示」、**5.1.2(i) 2025–26 新增「分享給第三方 AI 必須明示並取得明確同意」**。這直接決定 onboarding 的同意流程設計。
6. **隱私標籤可以「乾淨」**：Apple 定義「Collect」= 傳離裝置且保留超過即時服務所需。選擇**不保留音訊的供應商（Deepgram 預設不存、Anthropic 預設不存對話內容、ZDR 可申請）**，加上本地優先，可以把 Audio Data 標為「未蒐集」或大幅縮小揭露範圍。
7. **Apple iOS 26 / macOS 26 的 `SpeechAnalyzer` 是雙面刃**：它讓系統聽寫變強（威脅），但也是**免費、零打包、純裝置端**的 STT 引擎（機會）——拿來做 Free 方案的本地引擎，雲端只給 Pro。
8. **建議定價**：Free（本地無限 + 雲端 1,500 字/週）、Pro **US$8/月年繳（$96/年）、$10/月月繳**、Pro Lifetime（桌面本地版，NT$1,490 ≈ US$49）、Team **$8/席/月（3 席起）**。台灣以 NT$ 顯示並支援台灣常用支付。
9. **開源策略**：桌面 client 用 **GPL-3（如 VoiceInk）或 source-available**，雲端中繼、同步、團隊功能閉源收費；iOS/Android app 不要用 GPL（與 App Store 條款衝突），用 MIT/Apache 或閉源。
10. **商標**：不要碰「Typeless」。「Atype」本次無法查詢 TIPO/USPTO/WIPO（全被擋），申請前務必查第 9、42 類；同時確認 `atype.app` / App Store 名稱無衝突。

---

## 1. 定價基準（Pricing Benchmarks）

> 官方定價頁本次全部被 egress proxy 擋掉。下表來自同梯次 `competitors-and-oss.md` / `typeless-teardown.md` 彙整（其來源為第三方整理頁，如 getvoibe、spokenly、usevoicy，與 Typeless 官方 pricing 的摘要）。**所有價格請於上線前重新核對。**

| 產品 | 平台 | Free | Pro（月繳 / 年繳） | 終身 | Team | 備註 |
|---|---|---|---|---|---|---|
| **Typeless** | macOS/Win/iOS/Android | 8,000 字/週（⚠ 疑似 2026-09-22 降為 2,000 字/週） | **$30/月** 或 **$12/月年繳（$144/年）**；新帳號 30 天 Pro 試用 | 無 | 同 Pro $12/member/月；Enterprise 客製（SSO、SCIM、audit log、HIPAA） | 月繳全場最貴；session 6 分鐘上限 |
| **Wispr Flow** | macOS/Win/iOS/Android | 2,000 字/週（iPhone 1,000；Android 無上限） | $15/月 或 $12/月年繳 | 無 | $10–12/人/月，3 席起 | 2026-08 B 輪 $280M、估值 $2B（⚠ 二手） |
| **Superwhisper** | macOS/Win/iOS | 小型本地模型無限用 | $8.49/月、$84.99/年 | **$249.99** | — | 本地優先；SOC 2 Type II；學生 6 折 |
| **Willow Voice** | macOS/iOS/Win | 2,000 字/週 | $15/月 或 $144/年 | 無 | $10/人/月 | 專業用戶定位 |
| **Aqua Voice** | macOS/Win/iOS | 一次性 1,000 字 | $10/月 或 $8/月年繳（$96/年） | 無 | — | 自研模型 Avalon |
| **VoiceInk** | macOS 15+ | GPL-3 原始碼可自行編譯 | — | **$25 / $39 / $49**（Solo / Personal / Extended） | — | 買的是「編譯好的版本 + 自動更新 + 優先支援」 |
| **MacWhisper** | macOS | 免費版（本地） | App Store 版 $6.99/月、$29.99/年 | Gumroad **€59**；App Store $99.99 | — | 檔案轉錄為主 |
| Monologue（Every） | macOS/iOS | 1,000 字 + 10 則筆記 | $15/月 或 $144/年 | 無 | — | 綁 Every bundle $30/月 |
| Voicy | 全平台 | — | $8.49/月、$82/年 | $260 | — | 純雲端 |

**Typeless 免費額度疑似調降的證據**（皆非官方）：第三方工具 typeless-switch-mac 的 README 寫「账号自动轮动（默认阈值 2,000 词）」用來避免額度耗盡（https://github.com/caofanf/typeless-switch-mac ）；另一個 PR 標題「Typeless: free tier drops to 2,000 words/week from Sep 22」（https://github.com/richcalls/dictation-list/pull/4 ，本次 404）。

**可觀察的規律**
- 年繳折扣幾乎都是 **20–60%**（Typeless 月繳 $30 → 年繳 $12/月，是用月繳當「錨」逼年繳）。
- 字數上限是**免費層**的主要閥門，Pro 一律「unlimited words」（實務上有公平使用）。
- 本地優先 → 可賣終身；純雲端 → 只賣訂閱。這是 COGS 結構決定的，見第 2 節。
- Team 定價反而比個人便宜（$10 vs $12），因為席次量與低流失。

---

## 2. 單位經濟（Unit Economics）

### 2.1 2026 年的 API 單價（每分鐘音訊 / 每百萬 token）

STT（來源：LiteLLM 公開價格表鏡像 https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json ，以 `input_cost_per_second × 60` 換算；Google 為官方頁 https://cloud.google.com/speech-to-text/pricing ；OpenAI 新模型與 Mistral 另參照同梯次 `stt-engines.md`）：

| 供應商 / 模型 | $/分鐘 | $/小時 | 備註 |
|---|---|---|---|
| Groq `whisper-large-v3-turbo` | 0.00067 | **0.04** | 最便宜；Whisper 中文簡繁混出問題 |
| Gemini 2.5 Flash-Lite 音訊輸入（$0.30/M audio tokens，≈32 tok/s） | ≈0.0006 | ≈0.035 | 2.5 Flash-Lite 將於 2026-10 退役（⚠ 二手），改看 3.1 Flash-Lite 音訊 $0.50/M（官方 Vertex 頁） |
| OpenAI `gpt-4o-mini-transcribe` | 0.003 | 0.18 | |
| Mistral Voxtral Mini Transcribe | 0.003 | 0.18 | 4B 開源權重可自架；Realtime $0.006/min |
| ElevenLabs Scribe v2 | 0.0037 | 0.22 | 普通話獨立基準最佳（⚠ 二手）；Realtime $0.39/hr |
| Deepgram Nova-3（批次） | 0.0043 | 0.26 | 2026-03-31 新增 zh-TW |
| Deepgram Nova-3（串流 / 多語串流） | 0.0048 / 0.0058 | 0.29 / 0.35 | |
| OpenAI `gpt-transcribe`（2026-07） | 0.0045 | 0.27 | |
| OpenAI `whisper-1` / `gpt-4o-transcribe` | 0.006 | 0.36 | |
| OpenAI `gpt-live-transcribe` / `gpt-realtime-whisper` | 0.017 | 1.02 | 串流貴 3–4 倍 |
| Google Speech-to-Text v2 Standard | **0.016**（含 data logging）/ 0.024（不含） | 0.96 / 1.44 | 官方：每月前 60 分鐘免費；Dynamic batch $0.003/min |
| Apple `SpeechAnalyzer`（iOS/macOS 26） | **0** | 0 | 純裝置端，模型存於系統不佔 app 體積（WWDC25 session 277） |

LLM 潤飾（官方：Anthropic https://platform.claude.com/docs/en/about-claude/pricing ；Google Vertex https://cloud.google.com/vertex-ai/generative-ai/pricing ；OpenAI 價格來自 LiteLLM 鏡像）：

| 模型 | 輸入 $/MTok | 輸出 $/MTok | Cache 讀 | 備註 |
|---|---|---|---|---|
| OpenAI `gpt-4.1-nano` | 0.10 | 0.40 | 0.025 | |
| OpenAI `gpt-5-nano` / `gpt-5-mini` | 0.05 / 0.25 | 0.40 / 2.00 | | gpt-5 系需 `reasoning.effort=minimal` 否則延遲爆炸 |
| Gemini 2.5 Flash-Lite | 0.10 | 0.40 | 0.01 | 退役中 |
| Gemini 3.1 Flash-Lite | 0.25 | 1.50 | 0.025 | 官方 Vertex 頁 |
| Gemini 3.5 Flash-Lite / 3.5 Flash | 0.30 / 1.50 | 2.50 / 9.00 | | 官方 Vertex 頁 |
| Claude Haiku 4.5 | 1.00 | 5.00 | 0.10 | 最低可 cache 4,096 token，短 prompt 吃不到 |
| Claude Sonnet 5.5 | 2.00 | 10.00 | 0.20 | 512 token 即可 cache |
| Claude Opus 5.5 | 4.00 | 20.00 | 0.20 | 不需要用在聽寫潤飾 |

### 2.2 用量假設

- 語速：中文約 200 字/分、英文約 130–150 詞/分；中英夾雜取 **150 字/分**。
- 3,000 字/天 ≈ **20 分鐘音訊/天**；10,000 字/天 ≈ **67 分鐘/天**。以 22 個工作天計：**440 分鐘/月** 與 **1,467 分鐘/月**。
- 每次聽寫平均 60 字 → 3,000 字/天 ≈ 50 次/天 ≈ **1,100 次/月**；每次 LLM 呼叫：system prompt 1,000 token（可 cache）+ 原文 100 token + 輸出 90 token。
- 免費層 2,000 字/週 ≈ 8,700 字/月 ≈ **58 分鐘/月**。

### 2.3 每位活躍用戶的月成本（COGS）

| 項目 | Free（2,000 字/週） | Pro 典型（3,000 字/天） | Pro 重度（10,000 字/天） |
|---|---|---|---|
| STT：Apple SpeechAnalyzer / whisper.cpp 本地 | $0 | $0 | $0 |
| STT：Groq whisper-turbo | $0.04 | $0.29 | $0.98 |
| STT：OpenAI gpt-4o-mini-transcribe | $0.17 | $1.32 | $4.40 |
| STT：Deepgram Nova-3 批次 / 串流 | $0.25 / $0.28 | $1.89 / $2.11 | $6.31 / $7.04 |
| STT：OpenAI gpt-4o-transcribe | $0.35 | $2.64 | $8.80 |
| STT：OpenAI gpt-live-transcribe（串流） | $0.99 | $7.48 | $24.9 |
| STT：Google STT v2 | $0.93 | $7.04 | $23.5 |
| LLM：gpt-4.1-nano（無 cache） | $0.02 | $0.16 | $0.53 |
| LLM：Gemini 3.1 Flash-Lite | $0.06 | $0.45 | $1.50 |
| LLM：Claude Haiku 4.5（無 cache） | $0.23 | $1.71 | $5.70 |
| LLM：Claude Sonnet 5.5（system prompt cache 命中） | $0.19 | $1.45 | $4.83 |
| 中繼伺服器 / 認證 / 分析（攤提） | ~$0.05 | ~$0.3 | ~$0.5 |
| **合計（推薦組合：Deepgram 串流 + Gemini Flash-Lite 或 nano）** | **≈$0.35** | **≈$2.6–2.9** | **≈$8.5–9.5** |
| **合計（高品質組合：gpt-4o-transcribe + Sonnet 5.5）** | ≈$0.6 | ≈$4.4 | ≈$14 |

### 2.4 毛利

| 售價（月） | 收款通道費後淨收 | 典型用戶毛利 | 重度用戶毛利 |
|---|---|---|---|
| $8（年繳折算） | MoR 5%+$0.50 → $7.10；Apple SBP 15% → $6.80 | 55–65% | **≈ -25% ~ 0%** |
| $10 | $9.00 / $8.50 | 65–72% | 0–10% |
| $12 | $10.90 / $10.20 | 72–78% | 10–25% |
| $15 | $13.75 / $12.75 | 78–82% | 30–40% |

結論：
- 定價 **$8–10** 在典型用戶可行，但**必須**有：(a) Free/Pro 都預設本地 STT（Apple 平台零成本），(b) Pro 的雲端「無限」設公平使用（例如 150,000 字/月，超過降速或切本地），(c) LLM 用 fast tier（Flash-Lite / nano）當預設、Sonnet 當「進階潤飾」選項。
- 串流 STT（gpt-live-transcribe、Google）在重度用戶是賠錢的；聽寫是「說完再送」為主的工作負載，用批次（短檔）即可，延遲由 UX 補償。
- 免費用戶每人每月 $0.3–0.6，1 萬免費活躍用戶 ≈ $3–6k/月——**免費層必須預設本地引擎**，雲端只給少量額度。

---

## 3. 收款與訂閱（Payment / Billing）

### 3.1 從台灣能用什麼

| 通道 | 費率 | 台灣可用性 | 適用 |
|---|---|---|---|
| **Stripe（直接）** | ~2.9% + $0.30（⚠ 未驗證） | **台灣不在 Stripe 支援國家清單**（⚠ stripe.com 本次被擋，無法再確認 2026 現況）；常見解法是 Stripe Atlas 設立美國 LLC（⚠ 約 $500 設立費 + 德拉瓦州年度稅/註冊代理人） | 若未來設海外公司 |
| **Paddle（MoR）** | ⚠ 約 5% + $0.50/筆 | MoR 代為處理 VAT/銷售稅、退款、發票；付款至台灣帳戶需確認 | **桌面與 Web 訂閱首選** |
| **Lemon Squeezy（MoR）** | ⚠ 約 5% + $0.50/筆 | 2024 被 Stripe 收購（⚠），新帳號政策需確認 | 同上 |
| **Polar.sh / Creem（MoR，新創）** | ⚠ 約 4% + $0.40 | 開發者友善、支援 license key | 替代方案 |
| **Gumroad** | ⚠ 10% 平台費 | 可賣終身授權 | MacWhisper 模式 |
| **台灣本地：綠界 ECPay / 藍新 NewebPay / TapPay** | ⚠ 約 2.75–3% + 固定費 | 支援信用卡定期定額、LINE Pay、超商；需自行開立電子發票與營業登記 | 針對台灣 NT$ 用戶、企業採購 |
| **Apple IAP** | 30%；**Small Business Program 15%**（前一年與當年 proceeds ≤ $1M；新開發者自動符合；超過即回 30%） | 全球 | iOS 必須；macOS 僅 MAS |
| **Google Play Billing** | ⚠ 15%（首 $1M/年）、訂閱 15%、其餘 30% | 台灣可開發者帳號（⚠ 一次性 $25） | Android 必須 |

Apple Small Business Program 細節（一手：https://developer.apple.com/app-store/small-business-program/ ）：「15% on paid apps and Apple In-App Purchases」；門檻「up to 1 million USD in proceeds in the prior calendar year for all their apps」；需列出所有 Associated Developer Accounts；超過 $1M 當年即「the standard commission rate will apply to future sales」。

### 3.2 App Store 外部連結規則（2026）

- 一手（App Review Guidelines 3.1.1(a)，https://developer.apple.com/app-store/review/guidelines/ ）：「These entitlements are not required for developers to include buttons, external links, or other calls to action in their **United States storefront** apps.」且「In all other storefronts, except for the United States storefront, where this prohibition does not apply, apps and their metadata may not include buttons, external links, or other calls to action that direct customers to purchasing mechanisms other than in-app purchase.」
- 意涵：**只有美國 storefront** 可以在 app 內放「到官網訂閱更便宜」的連結且不用 entitlement；**台灣 storefront 不行**。iOS app 在台灣仍需提供 IAP。
- 3.1.3(b) Multiplatform Services：「may allow users to access content, subscriptions, or features they have acquired in your app on other platforms or your web site... **provided those items are also available as in-app purchases within the app**」→ 桌面/網頁買的 Pro 可以在 iOS 解鎖，但 iOS 內也要有 IAP 可買。
- StoreKit External Purchase API 的地區（一手：https://developer.apple.com/documentation/storekit/external-purchase ）：EU、南韓、EEA/俄羅斯、巴西（iOS 26.5 起）、日本（iOS 26.2 起）；文件未提美國（美國靠 3.1.1(a) 的法院命令例外）。

### 3.3 Google Play Billing

- 一手（https://developer.android.com/google/play/billing ）：「By Aug 31, 2026, all new apps and updates to existing apps must use Billing Library version 8 or later」（可申請延至 2026-11-01）；目前文件已推 **Billing Library 9**。這個期限已過，新專案直接用 v9。
- 訂閱支援 base plans / offers、免費試用（Google 會先驗證付款方式）、grace period、account hold（https://developer.android.com/google/play/billing/subscriptions ）。
- 替代計費（User Choice Billing、External Offers）文件提到存在，但台灣適用性未在頁面列出。

### 3.4 RevenueCat

- ⚠ 未能開啟定價頁。以往方案：免費至每月 $2.5k MTR，之後約 1% MTR。用途：統一 Apple / Google / Stripe(或 MoR) 的訂閱狀態、entitlement、跨平台解鎖（配合 3.1.3(b)）。
- 1–2 人團隊建議：**桌面 + Web 用 MoR（Paddle）發 license / 帳號 entitlement，手機用 IAP + Play Billing，RevenueCat 做 entitlement 真相來源**；自家後端只存「user → entitlement → 到期日」。

---

## 4. 發行與散佈（Distribution）

### 4.1 macOS：直接下載 DMG（不上 Mac App Store）

- 理由：MAS 強制 App Sandbox（2.4.5(i)「They must be appropriately sandboxed」），且「(vii) They must use the Mac App Store to distribute updates」。聽寫工具要 Accessibility（`AXIsProcessTrusted`）、`CGEvent` 貼字、監聽全域熱鍵，同梯次研究的四個參考專案（VoiceInk、Handy、Whispering、VoiceVoice）全部 `com.apple.security.app-sandbox = false`。
- 流程（一手：https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution ）：Developer ID Application 憑證 → Hardened Runtime → `codesign` 含 secure timestamp → `notarytool submit` → `xcrun stapler staple`。「Beginning in macOS 10.15, all software built after June 1, 2019, and distributed with Developer ID must be notarized」；「the Apple notary service no longer accepts uploads from altool or Xcode 13 or earlier」（2023-11-01 起）。
- 更新：Sparkle 2（https://github.com/sparkle-project/Sparkle ）：EdDSA 簽章、appcast、delta 更新、支援 sandbox、macOS 12+。
- 費用：Apple Developer Program **US$99/年**（一手：https://developer.apple.com/programs/ ），內含 Developer ID 與 notarization。
- Homebrew cask 是台灣/全球開發者的重要入口（Handy 已有），零成本。

### 4.2 Windows：直接安裝檔 + 簽章

- 安裝檔：NSIS（Tauri 預設 per-user，不需 UAC；支援 ARM64）或 MSI；更新用 Tauri updater（強制 minisign 簽章）。
- 簽章選項：
  - **Azure Trusted Signing（已更名 Artifact Signing）**：⚠ Basic 約 US$9.99/月。Electron 官方文件說 2023-06 起軟體型 OV 憑證在 SmartScreen 眼中等同未簽章，而 Trusted Signing「gets rid of SmartScreen warnings」，但「僅限某些國家的開發者」（https://github.com/electron/electronjs.org-new/blob/main/docs/latest/tutorial/code-signing.md ）。Azure 官方 action 的 issue #81「Availability outside US and Canada」仍開啟（https://github.com/Azure/trusted-signing-action/issues ）。**台灣個人/公司是否可用，必須先去 Azure Portal 試開 Identity Validation。** 憑證為短效（簽章需 timestamp 才能超過 3 天有效）。
  - OV/EV 憑證（Sectigo / DigiCert / SSL.com）：⚠ 每年約 US$200–500，2023-06 起需硬體 token 或雲端 HSM；新憑證仍需累積 SmartScreen 信譽。
- **Microsoft Store**：開發者帳號現在**免費**（一手：「there are no registration fees for either account type」https://github.com/MicrosoftDocs/windows-dev-docs/blob/docs/hub/apps/publish/partner-center/open-a-developer-account.md ；個人需證件+自拍驗證，公司需 DUNS 或營業文件）。⚠ 佣金：若用自家金流為 0%、用微軟金流 12%（未一手驗證）。MSIX 打包、Store 的信譽可免 SmartScreen；建議 v1 先直接下載，v1.x 再補 Store。
- winget 上架免費，對開發者族群很有用。

### 4.3 Linux

- AppImage / .deb / Flatpak；無簽章成本。Tauri updater Linux 僅支援 AppImage。Linux 市場小但 Wispr Flow 沒有 Linux 版，是便宜的差異化（Handy 32.5k stars 顯示需求存在）。

### 4.4 iOS：TestFlight 與審查

- TestFlight（一手：https://developer.apple.com/testflight/ ）：內部測試 **100 人**（需 App Store Connect 角色）、外部測試 **10,000 人**、最多 100 個 build、每位測試者 30 台裝置；外部測試需先通過 Beta App Review 並填寫 beta app description。
- **審查地雷（一手：App Review Guidelines）**：
  - **4.4.1 Keyboard Extensions**：必須「Remain functional without full network access and without requiring full access」、「Provide a method for progressing to the next keyboard」、「Collect user activity only to enhance the functionality of the user's keyboard extension」；不得「Launch other apps besides Settings」。市售聽寫鍵盤（Wispr Flow、Dictus 等）都會開啟自家 containing app（因為 extension 不能用麥克風），實務被容忍，但**送審備註要寫明理由**。
  - **Full Access 的系統警告**：Apple 文件直言開啟後「they know their keystrokes are available to the keyboard developer」（https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard ）；未開 Full Access 時「No access to microphone and speaker」「No network access」。設計上：**鍵盤 = 薄 UI + 插字；錄音與辨識在主 app**；Full Access 只拿來解鎖「免開 app 的 session 續用」。
  - **2.5.14 Recording**：「Apps must request explicit user consent and provide a clear visual and/or audible indication when recording」→ 錄音中必須有 Live Activity / 狀態列 / 音效提示。
  - **5.1.1(i) 隱私政策**必須寫明蒐集什麼、如何用、第三方（含 SDK）、**資料保留/刪除政策與撤回同意方式**；5.1.1(ii) 付費功能不得以授權資料為前提；(iv) 不得要求不必要的權限。
  - **5.1.2(i)（關鍵）**：「You must clearly disclose where personal data will be shared with third parties, **including with third-party AI**, and obtain explicit permission before doing so.」→ 第一次使用雲端模式前要有明確的「你的語音將傳送到 OpenAI/Deepgram 處理」同意畫面，且可隨時關閉。
  - 3.1.1 非訂閱 app 的免費試用需用 Price Tier 0 的「XX-day Trial」非消耗品；訂閱則直接用 StoreKit 的 introductory offer。
- **Privacy Manifest**（一手：https://developer.apple.com/documentation/bundleresources/privacy-manifest-files ）：`PrivacyInfo.xcprivacy` 需 `NSPrivacyTracking`、`NSPrivacyTrackingDomains`、`NSPrivacyCollectedDataTypes`、`NSPrivacyAccessedAPITypes`（required reason APIs）。主 app 與 keyboard extension 各一份。
- **App Privacy 標籤**（一手：https://developer.apple.com/app-store/app-privacy-details/ ）：「Collect refers to transmitting data off the device in a way that allows you and/or your third-party partners to access it for a period longer than what is necessary to service the transmitted request in real time」；「Data that is processed only on device is not 'collected'」。開發者要替整合的第三方 SDK 負責揭露。

### 4.5 Android：Play 測試軌與資料安全

- ⚠（support.google.com 被擋，以下為既有規則，請確認）：開發者帳號一次性 $25；Internal testing 最多 100 位測試者；**2023-11 之後建立的個人帳號需先做 closed testing：至少 12 位測試者連續 14 天**才能申請正式上架；Data safety 表單需揭露「Audio / Voice or sound recordings」是否蒐集、分享、是否加密、可否刪除。
- IME（`InputMethodService`）在 Android 可以直接錄音（不像 iOS），但 Play 對 IME 有「Accessibility/鍵盤不得蒐集按鍵以外資料」的政策要點（⚠ play-policies 頁可開啟但未逐條核對）。

---

## 5. 法遵與隱私（Legal / Privacy）

### 5.1 隱私政策要寫什麼（給麥克風資料）

最低內容（對應 Apple 5.1.1(i)、GDPR Art. 13、台灣個資法第 8 條）：
1. 蒐集項目：語音音訊、辨識文字、（若有）前景 app 名稱/視窗標題等上下文、裝置識別、帳號 email。
2. 目的與法律依據：提供聽寫服務（契約必要）、改善模型（**需另行選擇同意，預設關閉**）。
3. 第三方處理者清單：OpenAI / Deepgram / Anthropic / Google 等，各自的保留期間。
4. 保留與刪除：音訊即時處理不落地；文字歷史存於裝置（或雲端同步可關閉）；帳號刪除 30 天內清除。
5. 使用者權利：查詢、下載、刪除、撤回同意、停止雲端模式。
6. 跨境傳輸聲明（資料送到美國）。
7. 聯絡方式與（若服務 EU）EU 代表。

### 5.2 供應商的資料保留 / ZDR

| 供應商 | 預設保留 | ZDR | 來源 |
|---|---|---|---|
| **Anthropic Claude API** | 「Conversation content (your prompts and Claude's outputs) is **not retained by default**」；例外為 Covered Models（Fable/Mythos 系列）需 30 天；「Retained data is never used for model training without your express permission」 | 「Under a ZDR arrangement, Anthropic does not store customer prompts or responses at rest after the API response is returned」，**需聯絡 sales、以 organization 為單位啟用**；Batch API、Files API、code execution 不在 ZDR 範圍 | https://platform.claude.com/docs/en/manage-claude/api-and-data-retention ；商業條款「Anthropic may not train models on Customer Content from Services」https://www.anthropic.com/legal/commercial-terms |
| OpenAI API | ⚠ 預設最多 30 天供濫用監控；不用於訓練 | ⚠ ZDR 需申請、限合格端點/帳號 | 二手彙整 https://meetily.ai/llm-privacy/openai （一手頁被擋） |
| Deepgram | 音訊即時處理不儲存，除非開啟儲存或加入 Model Improvement Partnership | 企業可簽 | https://developers.deepgram.com/docs/the-deepgram-model-improvement-partnership-program （本次被擋，沿用同梯次研究） |
| AssemblyAI | ⚠ 可設定 ZDR（企業） | 企業 | 二手 |
| Google Cloud STT | 可選「with data logging」享折扣（$0.016 vs $0.024/min），不選即不記錄 | 以 Cloud DPA 為準 | https://cloud.google.com/speech-to-text/pricing |

設計意涵：**Anthropic（LLM）+ Deepgram 或自架 Voxtral（STT）** 的組合可以在不簽企業約的情況下，把「音訊/文字不保留」寫進隱私政策與 App Privacy 標籤；OpenAI 的 30 天保留會讓 Audio Data 落入「已蒐集」。

### 5.3 GDPR / CCPA / 台灣個資法（基本盤）

- **GDPR**（⚠ eur-lex 被擋，依既有條文）：若向 EU 用戶提供服務即適用。需 lawful basis（契約履行；模型改善需同意）、與每個處理者簽 DPA（OpenAI/Anthropic/Deepgram 都有標準 DPA）、資料主體權利（存取/刪除/可攜）、72 小時內通報監管機關的洩漏義務、無 EU 據點需指定 **Art. 27 代表**（通常每年數百歐元的代理服務）。語音是個人資料；若做聲紋辨識才算特殊類別（Art. 9）。
- **CCPA/CPRA**（⚠）：門檻為年營收 >$25M 或 >100,000 加州消費者/住戶資料等；1–2 人團隊初期多半不適用，但隱私政策仍建議放「Do Not Sell or Share」聲明以免被平台要求。
- **台灣《個人資料保護法》**（⚠ law.moj.gov.tw 被擋，條號依既有法條）：
  - 第 8 條：蒐集時應告知機關名稱、目的、類別、利用期間/地區/對象/方式、當事人權利、不提供之影響。
  - 第 19 條：非公務機關蒐集需有特定目的並符合法定情形之一（含當事人同意、契約關係）。
  - 第 20 條：目的外利用的限制；第 27 條：應採取適當安全維護措施（建議有書面安全維護計畫）。
  - 2023-05 修法後罰鍰提高（⚠ 一般違反安全維護義務 NT$2 萬–200 萬，情節重大可達 NT$15 萬–1,500 萬），並設立專責機關「個人資料保護委員會」（⚠ 2025 年掛牌）。
  - 聲音屬個資法定義之個人資料（「得以直接或間接方式識別該個人之資料」）；語音歷史若含他人姓名/電話也會牽涉第三人資料。
  - 跨境傳輸（第 21 條）：目前未有普遍禁止，但要在告知事項寫明「利用地區」含美國。

### 5.4 SOC 2 與企業採購

- 1–2 人團隊不需要一開始做 SOC 2。Superwhisper 有 SOC 2 Type II（二手），Typeless Enterprise 標榜 HIPAA/SSO/SCIM；這些是 Team/Enterprise 方案的門票。
- ⚠ 行情：Vanta/Drata 類工具 + 審計，Type I 約 US$10–20k，Type II 約 US$20–60k/年（未一手驗證）。替代做法：先提供「安全白皮書 + 子處理者清單 + DPA + 資料流程圖」，多數中小企業採購即可過。
- Anthropic 的 HIPAA readiness 可在 Console 自助簽 BAA（一手文件），若未來要做醫療聽寫，可免談銷售。

---

## 6. Apple iOS 26 / macOS 26 內建聽寫的競爭威脅

- 一手：`SpeechAnalyzer` 於 iOS/iPadOS/macOS/tvOS/visionOS **26.0+** 提供（https://developer.apple.com/documentation/speech/speechanalyzer ）；WWDC25 session 277「Bring advanced speech-to-text to your app with SpeechAnalyzer」：「Our new, on-device model」、「transcription is entirely on device but the models need to be fetched」、「already powering features across many system apps, such as Notes, Voice Memos, Journal」、「faster and more flexible than the one previously available through SFSpeechRecognizer」、模型存於系統儲存不增加 app 體積（https://developer.apple.com/videos/play/wwdc2025/277/ ）。
- 威脅面：系統聽寫（Fn/🌐 鍵）變準、變快、免費、離線，而且在**所有輸入框**都能用——這正是 Typeless 類產品的核心場景。對「只想把話變成字」的輕度用戶，Apple 內建已經夠。
- 機會面：
  1. **零成本 STT 引擎**：我們的 iOS/macOS Free 方案直接用 `SpeechTranscriber`，不用付 Deepgram；同時解決「鍵盤 extension 不能錄音」的體積問題（模型在系統內）。
  2. Apple 聽寫**不做 LLM 潤飾**（贅詞、標點、格式、依 app 調語氣、個人字典、中英夾雜一致性、繁體不混簡）——這些是我們的價值層。同梯次 `llm-postprocess.md` 的台灣評測顯示 Typeless 對「Costco 好市多」這類混用的處理明顯優於原生。
  3. Windows / Android / Linux 沒有同等品質的免費內建方案（Win+H 的中文表現普通），跨平台一致體驗是護城河。
  4. Apple 的語言清單仍在擴充（session 未列出），zh-TW 品質需實測。
- 風險：若 Apple 在 iOS 27 把 Apple Intelligence 的「重寫/校對」接到系統聽寫，價值層會被侵蝕；對策是深耕「上下文感知」「個人/團隊字典」「跨裝置歷史」「開發者情境（IDE/terminal）」。

---

## 7. 商標（Trademark）

- **不要用「Typeless」或近似名**（typeless.com 已是現役商業產品，且他們顯然在美/台等市場營運）。
- **「Atype」**：本次 TIPO 商標檢索（cloud.tipo.gov.tw）、USPTO、WIPO Global Brand Database、EUIPO 全部被 proxy 擋住，**無法查詢**。申請前請自查：
  1. TIPO 商標檢索系統 → 類別 **第 9 類（軟體）與第 42 類（SaaS）**，查「Atype」「A-Type」「a type」及中文音譯。
  2. USPTO Trademark Search（若賣美國）；WIPO Global Brand DB 一次看多國。
  3. 網域與商店名稱：`atype.app`、`atype.ai`、App Store / Play 的 app 名稱是否已被占用（App Store 名稱唯一）。
  4. 風險提示：「Atype」是「a type」的常見拼寫、也是字型圈常用字（如 OpenType 相關命名），可能被認為識別性弱或與既有字型/排版軟體商標近似；建議準備備案名。
- 台灣商標申請（⚠）：每類 NT$3,000 規費、審查約 6–8 個月；先用「TM」不影響上線。

---

## 8. 開源 vs 閉源策略

一手觀察：
- **Handy**（MIT，32.5k stars，Windows/macOS/Linux）：「Accessibility tooling belongs in everyone's hands, not behind a paywall」，靠贊助商（Wordcab、Epicenter 等）維持，**沒有營收模式**。（https://github.com/cjpais/Handy ）
- **VoiceInk**（GPL-3，6.6k stars，macOS 15+）：原始碼可自行編譯，但「purchasing a license helps support continued development and gives you access to automatic updates, priority support, and upcoming features」，賣 $25–49 終身；且「not accepting pull requests」。（https://github.com/Beingpax/VoiceInk ）

選項比較：

| 策略 | 優點 | 缺點 | 適合 |
|---|---|---|---|
| 全閉源 | 單純、可賣終身/訂閱、無授權糾紛 | 開發者社群不會幫你推；信任需靠 SOC2/白皮書 | 以手機與一般用戶為主 |
| **Open core（GPL-3 桌面 client + 閉源雲端）** | VoiceInk 已證明 GPL 不妨礙收費；社群檢視「音訊不出裝置」的宣稱，天然的信任背書；GitHub 是台灣/全球開發者的獲客通路 | GPL 與 App Store 條款衝突（需雙授權或手機端閉源）；競品可 fork（但沒有雲端/字典/同步） | **推薦**：桌面 GPL/AGPL，手機閉源或 MIT |
| Source-available（FSL / BUSL） | 可看、可自建、商用受限，兩年後轉開源 | 社群接受度較低 | 若擔心被整包 fork 上架 |
| MIT 全開（Handy 模式） | 最大擴散 | 幾乎無法收費 | 只想做名聲 |

建議：**桌面 client（Tauri/Swift）GPL-3；雲端中繼（ZDR proxy、API key 託管、同步、團隊字典、用量計費）閉源；手機 app 閉源**。對外論述：「本地模式永遠免費且可自行編譯；付費買的是雲端品質、同步與省心」。

---

## 9. 台灣 / 中文市場 Go-to-Market

證據：Typeless 在台灣已有自然聲量——數位時代的 Typeless vs Wispr Flow 評測（https://www.bnext.com.tw/article/89732/typeless-vs-wisprflow-best-speech-recognition-comparison ）、閱讀前哨站（https://readingoutpost.com/typeless/ ）、vocus 心得（https://vocus.cc/article/6996fe3dfd8978000192eadc ）、電腦王阿達介紹語言變體設定（https://www.kocpc.com.tw/archives/625756 ）。（以上為同梯次研究的搜尋摘要來源，本次無法開啟）這代表：(1) 台灣知識工作者已在找這類工具，(2) **繁體/中英夾雜正確性**是台灣用戶最在意的評比項目。

通路優先序（依 1–2 人團隊的投入產出）：
1. **Threads（台灣 2024–2026 最活躍的文字社群）**：用「打字 vs 說話」對比影片、注音選字痛點梗，創辦人帳號日更；成本最低。
2. **YouTube 工具型創作者合作**：電腦王阿達、PAPAYA 電腦教室型的教學頻道（給免費 Pro 一年 + 聯盟碼）；影片是聽寫類產品最好的 demo 媒介。
3. **Dcard**：軟體工程師板、工作板、研究所板（論文/報告聽寫）；**PTT**：Soft_Job、MacShop、Windows、Office；內容以「實測繁中準確率、與內建聽寫比較」為主，避免硬廣。
4. **Facebook 社團**：Mac 使用者社團、AI 工具交流社團、自由工作者社團——台灣 35+ 族群仍在 FB。
5. **巴哈姆特**：以遊戲為主，與聽寫工具關聯弱，**不建議投入**（除非做「遊戲內語音轉文字聊天」情境）。
6. 媒體：iThome、INSIDE、數位時代投稿「台灣團隊做的繁中聽寫」；Product Hunt 與 Hacker News（Show HN）打全球開發者。
7. 本地化細節：NT$ 定價與台灣發票（MoR 可省）、支援 LINE Pay/超商（若走綠界）、注音/倉頡用戶的 onboarding、台灣國語口音與台語夾雜的測試集。

---

## 10. 可比獨立 App 的 MAU / 營收現況

- 本次無法開啟 Indie Hackers、X、TechCrunch、Wikipedia 等來源，**沒有拿到可驗證的公開營收數字**。同梯次研究提到：Wispr Flow 2026-08 B 輪 $280M、估值 $2B（⚠ 二手，Wikipedia/pulse2）；Typeless 2026-03 有一輪 Early Stage VC 但金額未揭露（PitchBook）。
- 可用的規劃框架（取代數字）：
  - 免費→付費轉換率：工具型 freemium 常見 **2–5%**。
  - 以 2 人團隊、台灣 + 英語開發者市場為目標，**12 個月內 300–1,500 位付費者**是務實區間：1,000 × $8 ≈ **$8k MRR**（約 NT$26 萬/月）。
  - 終身方案能在初期帶來現金（VoiceInk 模式），但要控制比例（建議 ≤ 30% 的付費者），因為雲端成本是持續的。
- 建議在上線前就把「每位用戶的 STT 分鐘數 / LLM token / 毛利」當 KPI 進儀表板，比追求 MAU 更重要。

---

## 11. 建議的定價與方案（Pricing & Packaging）

| 方案 | 價格 | 內容 | COGS 估計 | 說明 |
|---|---|---|---|---|
| **Free** | $0 | 本地 STT 無限（Apple SpeechAnalyzer / whisper.cpp / Parakeet）；雲端 STT + fast-tier 潤飾 **1,500 字/週**；基本 LLM 潤飾（本地 Apple Foundation Models 或 Flash-Lite）；單裝置歷史 | ≤ $0.3/月 | 額度略低於競品 2,000 字/週，但本地無限是競品（Typeless/Wispr）沒有的 |
| **Pro** | **US$8/月（年繳 $96）**、$10/月月繳；台灣 NT$249/月年繳、NT$329 月繳 | 雲端 STT 無限（公平使用 150k 字/月後降為本地或排隊）；進階潤飾（Claude Sonnet 5.5 / gpt-4o 級）；跨裝置同步；個人字典與 snippets；依 app 的語氣模式；優先支援 | $2.5–4/月 | 低於 Typeless $12 與 Wispr $12，與 Aqua $8 同價；手機 IAP 同價（Apple 15% 自行吸收） |
| **Pro Lifetime（桌面本地版）** | **NT$1,490（≈US$49）** | 桌面 app 全功能、本地引擎、一年更新（之後可續 $19/年）；**不含雲端額度** | ≈ 0 | 對位 VoiceInk/Superwhisper；給不信任雲端的台灣開發者 |
| **Team** | **US$8/席/月年繳（3 席起）**、$10 月繳 | Pro 全部 + 共用字典 + 管理後台 + 集中帳單/發票 + 用量報表；10 席以上可簽 DPA/ZDR | 同 Pro | 席次量換低價；Typeless/Wispr 都是 $10–12 |
| Enterprise | 洽談 | SSO/SCIM、ZDR 合約、自架 Voxtral 選項、SOC 2 報告 | — | 第二年再做 |

試用：新帳號 **14 天 Pro**（Typeless 給 30 天，但 14 天夠讓習慣養成並控制成本）。學生/教育 5 折（Superwhisper 6 折）。

---

## 12. 成本模型（固定 + 變動）

**固定成本（年）**

| 項目 | 金額 | 來源/備註 |
|---|---|---|
| Apple Developer Program | US$99 | 一手 |
| Google Play 開發者帳號 | ⚠ US$25 一次性 | 未能驗證 |
| Microsoft Partner Center | **US$0** | 一手（MicrosoftDocs） |
| Windows 簽章：Azure Trusted Signing Basic | ⚠ ≈ US$120/年 | 或 OV 憑證 ⚠ $200–500/年 |
| 網域、Email、狀態頁 | ≈ US$100 | |
| 中繼伺服器（Cloudflare Workers / Fly.io）+ DB（Supabase/Turso） | US$300–1,200 | 隨用戶量；初期免費層可撐 |
| 認證（Supabase Auth / Clerk）、分析（PostHog）、錯誤追蹤（Sentry） | US$0–600 | 免費層 |
| MoR 平台費 | 收入的 ⚠ 5% + $0.50/筆 | Paddle/Lemon Squeezy |
| RevenueCat | ⚠ 收入的 1%（> $2.5k MTR 後） | |
| 商標（台灣 2 類） | ⚠ NT$6,000 + 代辦 | 選配 |
| GDPR EU 代表（若開 EU） | ⚠ €300–800/年 | 選配 |
| SOC 2 Type I（第二年起） | ⚠ US$10–20k | 選配 |

**變動成本（每位付費用戶／月，推薦組合）**：STT $1.3–2.1 + LLM $0.2–1.5 + 基礎設施 $0.3 ≈ **$2–4**；免費活躍用戶 ≈ $0.1–0.3（本地優先時趨近 0）。

**損益示意（第 12 個月）**：1,000 付費 × $8 = $8,000；MoR/IAP 混合通道費約 8% → $7,360；COGS $3,000；固定 $400/月 → **毛利約 $4,000/月**。

---

## 13. 對我們的設計意涵（Implications for Design）

1. **架構即成本結構**：本地 STT 做預設（Apple SpeechAnalyzer、whisper.cpp、Parakeet），雲端 STT 只在 Pro 且「使用者明確選擇」時啟用。這同時解決 COGS、隱私標籤與 App Review 5.1.2 的第三方 AI 同意要求。
2. **雲端呼叫一律經自家中繼**：不要把供應商 API key 放在 client；中繼負責計量（字數/分鐘）、公平使用、供應商切換（Deepgram ↔ Voxtral 自架）、ZDR 設定、以及把音訊即丟不落地。CORS 在 Anthropic ZDR 下不支援，更要走後端。
3. **同意流程是產品功能**：首次啟用雲端模式 → 一頁式說明「送到哪、保留多久、如何關閉」+ 開關；錄音中要有可見指示（2.5.14）；鍵盤 extension 在未開 Full Access 時仍要能打字與插字（4.4.1）。
4. **Entitlement 單一真相**：RevenueCat（或自家表）記錄 Apple/Google/MoR 的訂閱；iOS 內必須提供 IAP（3.1.3(b)），台灣 storefront 不可放外部購買連結。
5. **選供應商時把「保留政策」當功能規格**：Anthropic 預設不保留對話內容、Deepgram 預設不存音訊；避免 OpenAI 30 天保留成為隱私標籤的負擔，或用 OpenAI 時明確揭露。
6. **桌面發行流程要在第一週就自動化**：Developer ID + notarization + Sparkle appcast；Windows 先確認 Trusted Signing 的台灣身分驗證能否通過，不行就提早買 OV 憑證（新憑證要累積信譽）。
7. **公平使用與降級路徑**：Pro「無限」背後要有 150k 字/月的軟上限，超過時自動切本地引擎並提示，避免重度用戶把毛利吃成負數。
8. **繁中品質是台灣市場的唯一門票**：系統 prompt 強制台灣正體、中英夾雜保留原文、數字格式；評測集與自動回歸要在第一版就有。
9. **開源桌面 client（GPL-3）+ 閉源雲端**：以 GitHub 做開發者獲客，手機端閉源避免 GPL/App Store 衝突。
10. **命名與商標在寫第一行 code 前決定**：避免「Typeless」近似；「Atype」需自查第 9/42 類與 App Store 名稱。

---

## 14. 未解問題（Open Questions）

1. **Stripe 是否已支援台灣帳戶（2026）**？若已支援，直接用 Stripe Billing 可省 MoR 的 5%，但要自己處理 VAT/銷售稅。本次無法開啟 stripe.com。
2. **Paddle / Lemon Squeezy / Polar 對台灣賣家的付款（payout）與 KYC 現況**，以及 Lemon Squeezy 被 Stripe 收購後是否仍收新賣家。
3. **Azure Trusted Signing（Artifact Signing）的個人/公司身分驗證是否開放台灣**；若否，OV 憑證的供應商與價格。
4. **Typeless 免費額度是否真的在 2026-09-22 從 8,000 降到 2,000 字/週**（兩個非官方來源互證）；這影響我們 Free 額度的對位。
5. **Google Play 目前的服務費分級、$25 註冊費、以及個人帳號「12 位測試者 × 14 天」規則是否仍有效**（support.google.com 被擋）。
6. **RevenueCat 2026 定價**（免費額度與費率）。
7. **OpenAI 音訊端點的 ZDR 資格與 30 天保留**是否有 2026 年更新；Deepgram / AssemblyAI 的預設保留條款原文。
8. **台灣個資法 2023 修法後的罰則數字與個資保護委員會的運作現況**（law.moj.gov.tw 被擋）。
9. **「Atype」在 TIPO / USPTO / WIPO 第 9、42 類的檢索結果**，以及 `atype.app` 等網域是否可註冊。
10. **Apple `SpeechTranscriber` 的 zh-TW 支援與實測 CER**，以及 macOS 26 上事件 tap 是否需要 Input Monitoring（影響 onboarding）。
11. **App Review 對「鍵盤 extension 開啟自家 containing app」的實際尺度**（4.4.1 不得啟動其他 app）；建議首次送審前用 TestFlight + App Review 問答確認。
12. **可比獨立產品的公開營收/MAU**（MacWhisper、Superwhisper、VoiceInk 作者的公開分享）——本次所有社群來源被擋，無法引用數字。

---

## 來源清單（本次實際讀取的一手頁面）

- Apple Small Business Program：https://developer.apple.com/app-store/small-business-program/
- App Review Guidelines（2.4.5、2.5.14、3.1.1、3.1.3、4.4.1、5.1.1、5.1.2）：https://developer.apple.com/app-store/review/guidelines/
- App Privacy Details（nutrition label 定義）：https://developer.apple.com/app-store/app-privacy-details/
- Privacy manifest files：https://developer.apple.com/documentation/bundleresources/privacy-manifest-files
- Configuring open access for a custom keyboard：https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard
- StoreKit External Purchase：https://developer.apple.com/documentation/storekit/external-purchase
- Notarizing macOS software：https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- Apple Developer Program（$99）：https://developer.apple.com/programs/
- TestFlight 限制：https://developer.apple.com/testflight/
- SpeechAnalyzer：https://developer.apple.com/documentation/speech/speechanalyzer ；WWDC25 session 277：https://developer.apple.com/videos/play/wwdc2025/277/
- Google Play Billing 總覽（Billing Library 8/9 期限）：https://developer.android.com/google/play/billing ；訂閱：https://developer.android.com/google/play/billing/subscriptions
- Google Cloud Speech-to-Text 定價：https://cloud.google.com/speech-to-text/pricing
- Google Vertex AI Gemini 定價：https://cloud.google.com/vertex-ai/generative-ai/pricing
- Anthropic 定價：https://platform.claude.com/docs/en/about-claude/pricing ；API 與資料保留 / ZDR：https://platform.claude.com/docs/en/manage-claude/api-and-data-retention ；商業條款：https://www.anthropic.com/legal/commercial-terms
- LiteLLM 價格表（STT/LLM 鏡像）：https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json
- VoiceInk（GPL-3、授權模式）：https://github.com/Beingpax/VoiceInk ；Handy（MIT、贊助模式）：https://github.com/cjpais/Handy ；Sparkle 2：https://github.com/sparkle-project/Sparkle
- Microsoft Partner Center 開戶（免費）：https://github.com/MicrosoftDocs/windows-dev-docs/blob/docs/hub/apps/publish/partner-center/open-a-developer-account.md
- Typeless 免費額度訊號：https://github.com/caofanf/typeless-switch-mac
- 二手（同梯次研究引用，本次無法開啟）：Electron code-signing 文件 https://github.com/electron/electronjs.org-new/blob/main/docs/latest/tutorial/code-signing.md ；Azure trusted-signing-action issues https://github.com/Azure/trusted-signing-action/issues ；getvoibe / spokenly / usevoicy 定價整理頁；數位時代、閱讀前哨站、vocus、電腦王阿達的 Typeless 評測。
