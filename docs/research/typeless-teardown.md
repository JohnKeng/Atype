# Typeless 產品拆解報告（Product Teardown）

研究日期：2026-10-01
研究方法說明：本環境的網路代理封鎖了 typeless.com、apps.apple.com、play.google.com、producthunt.com、x.com、medium.com 以及大多數第三方評測站的直接抓取（WebFetch 回傳 `EGRESS_BLOCKED`），因此本報告的事實來源是：(1) 多輪 WebSearch（extended 模式）對官方 help/release-notes 頁、App Store / Google Play、X 貼文、台灣部落格的索引摘要；(2) 可直接讀取的 GitHub 專案（多個「Typeless 平替」的 README 與 issue，它們詳細記錄了 Typeless 的互動細節）。凡只有單一來源或摘要層級的數字，文中都會標註「待驗證」。使用者若能在本機開啟 typeless.com/help，建議逐條核對「未解問題」章節。

---

## 1. 執行摘要（Executive Summary）

- **Typeless 是什麼**：一款「語音 → 可直接送出的乾淨文字」的 AI 聽寫鍵盤 / 桌面工具。定位語是 "voice-to-perfect-text"（而非 voice-to-text），核心價值是 LLM 後處理：去除贅字、處理自我更正、自動排版清單、依 App 調整語氣。（來源：https://x.com/huang_song_/status/2025566656416858294 ）
- **平台覆蓋是業界最廣**：macOS、Windows（2025-10-22 Beta）、iOS 鍵盤（2025-12）、Android 鍵盤（2026-01-20 公開）、Linux（2026-09）。沒有 Web 版 / Chrome 擴充。
- **桌面互動模型**：Mac 預設 `Fn` 聽寫、`Fn+Shift` 翻譯、`Fn+Space` Ask Anything；Windows 預設「按住 `Ctrl+Win`」。支援按住說話（push-to-talk）與 v1.2.0 起的免持（hands-free：按一下開始、再按主快捷鍵結束）。單次聽寫上限 **6 分鐘**，5 分鐘時 "Typeless bar" 顯示 60 秒倒數。
- **手機互動模型**：iOS 是第三方鍵盤 extension，必須開 Full Access；鍵盤上「取代 emoji 鍵」放聽寫按鈕是最常被抱怨的設計。Android 版**完全沒有軟鍵盤**，只有一顆大麥克風，被定位為 Gboard 的補充而非取代。
- **定價**：Free 每週 8,000 字（2026-09-22 起疑似降為 2,000 字/週，待驗證）、Pro 年繳 US$12/月（US$144/年）或月繳 US$30、新帳號 30 天 Pro 試用；Enterprise 客製（SSO、SCIM、audit log、HIPAA）。Pro 的差異化是「unlimited words、enhanced accuracy、priority access、Cloud Sync、團隊管理」。
- **技術堆疊未公開**：純雲端（無離線模式），音訊送到 AWS us-east-2 處理（2025-11 第三方逆向分析），官方宣稱 zero data retention。STT / LLM 供應商沒有任何可靠公開資訊；開源平替社群普遍用 Groq `whisper-large-v3-turbo` + `gemini-2.5-flash` 達到接近體驗。
- **使用者評價兩極**：Product Hunt 5.0/5、App Store 4.5（729 評分）、Google Play 4.1（2.85K 評論）、Trustpilot 2.5–2.6。讚美集中在「真的可以直接送出的文字」與繁中/中英夾雜品質；抱怨集中在延遲（約 3 秒，約為 Wispr Flow 兩倍）、6 分鐘上限、"High demand right now" 雲端錯誤、iOS emoji 鍵、Android 無法打字、隱私行銷與實際雲端處理落差、以及免費方案彈窗。
- **對我們的意涵**：Typeless 的「體驗」= 一顆全域快捷鍵 + 一條狀態列 + 兩段式管線（串流 STT → LLM 清理）+ 三個語音模式（Dictate / Translate / Ask-Edit）+ 個人詞典與風格學習。要「複製並超越」，最有效的攻擊點是：延遲（串流插入）、離線/本地選項、單次時長上限、手機鍵盤的完整性（保留 emoji 鍵與基本打字）、以及對繁體中文/台灣用語的保證。

---

## 2. 公司背景與時間軸

### 2.1 公司與創辦人
- 創辦人兼 CEO：**Huang Song**，Stanford 校友，曾任 Google、LinkedIn 軟體工程師與 Apple 硬體工程師。公司位於 Palo Alto，受 **StartX**（Stanford 加速器）支持，團隊自述為「Stanford alumni and serial entrepreneurs」、「the voice OS company」。（來源：https://www.linkedin.com/in/huang-song-33122743/ 、https://www.typeless.com/about ，透過搜尋摘要）
- iOS App 的賣家名稱是 **Simply CA LLC**（https://apps.apple.com/us/app/typeless-ai-voice-keyboard/id6749257650 ）；Google Play 開發者名稱為 **TYPELESS**（https://play.google.com/store/apps/developer?id=TYPELESS ）。
- 2025-10 從 stealth 公開（https://x.com/StealthCoSpy/status/1983534284590797142 ）。
- 募資：PitchBook 記錄 2026-03-01 一輪 Early Stage VC，投資人 Hat-trick Capital 與 StartX，**金額未揭露**（https://pitchbook.com/profiles/company/1166524-75 ）。Tracxn / CB Insights 列出 Balderton Capital 2014 年種子輪，這幾乎可以確定是**同名不同公司**（2014 年的 Typeless 與 Crunchbase 的「Typeless Pte.」皆不應視為本公司）。（https://tracxn.com/d/companies/typeless/__Yy_hSiUWhNmeFyLa9xgXs0Zw4664FXgZarHHEMwAFmw/funding-and-investors 、https://www.cbinsights.com/company/typeless/financials ）
- 「100,000 subscribers」的里程碑貼文，搜尋摘要指出是 **YouTube 訂閱數**，不是付費訂閱數，不要誤用。（https://www.linkedin.com/in/huang-song-33122743/ ，待驗證）

### 2.2 產品時間軸（已交叉驗證的日期）
| 日期 | 事件 | 來源 |
|---|---|---|
| 2025-09-03 | 桌面版推出 Writing assistance（選取文字 → 快捷鍵 → 說出修改指令） | https://x.com/huang_song_/status/1963225476521926958 |
| 2025-10-22 | Windows Beta V0.1.0 | https://www.typeless.com/help/release-notes/windows/introducing-typeless-windows-app-beta |
| 2025-11-18 | Product Hunt 正式發表，513 upvotes、11 則評論 5.0/5 | https://www.producthunt.com/products/typeless-2 、https://aitoolly.com/producthunt-daily/2025-11-18 |
| 2025-11 | @medmuspg 逆向分析隱私行為（AWS us-east-2、URL/視窗標題蒐集） | https://www.getvoibe.com/resources/typeless-privacy-issues/ |
| 2025-12-24 | iOS 鍵盤在 Product Hunt 發表 | https://x.com/huang_song_/status/2003741470457758134 |
| 2025-12-31 | iOS 新增 Speak to edit | https://x.com/huang_song_/status/2006535054764167296 |
| 2026-01 | Android 私測 → 2026-01-20 公開 | https://x.com/huang_song_/status/2008178624441327831 、https://x.com/huang_song_/status/2013522407055860072 |
| 2026-02 | Typeless 1.0.0：Dictate / Translate / Ask anything 三模式 | https://x.com/huang_song_/status/2021579604129951967 |
| 2026（春） | v1.2.0 macOS & Windows：完全免持模式 | https://x.com/typelessdotcom/status/2043705779916554435 |
| 2026-07-08 | Typeless 2.0.0（四平台）：多目標翻譯語言、Enterprise 方案 | https://www.typeless.com/help/release-notes/macos/set-multiple-target-languages |
| 2026-09-22 | "Help me write"（Windows V2.8.0、Android 2.7.0） | https://www.typeless.com/help/release-notes/windows/use-help-me-write-desktop 、https://www.typeless.com/help/release-notes/android/use-help-me-write-android |
| 2026-09（下旬） | Linux 版發表，「所有 Mac 核心功能」 | https://x.com/huang_song_/status/2103109386860364050 |

---

## 3. 平台支援現況（2026-10）

| 平台 | 狀態 | 細節 |
|---|---|---|
| macOS | 正式 | Apple Silicon 需 macOS 13+，下載 `Typeless--arm64.dmg`；也有 Intel 版（最低版本未查到）。（https://www.typeless.com/help/faqs ） |
| Windows | 正式（2025-10 Beta 起） | Windows 10 以上；最新版號 V2.8.0（2026-09-22）。 |
| Linux | 正式（2026-09） | 宣稱與 Mac 核心功能一致，套件格式未查到。 |
| iOS | 正式（2025-12） | 第三方鍵盤 extension；iOS 16.1+、347 MB（v0.5.0，2026-01-29 的資料，**可能已過時**）。（https://apps.apple.com/us/app/typeless-ai-voice-keyboard/id6749257650 ） |
| Android | 正式（2026-01） | 套件 `com.typeless.mobile`，Android 7.0+，500K+ 下載，4.1 星 / 2.85K 評論。（https://play.google.com/store/apps/details?id=com.typeless.mobile ） |
| Web / 瀏覽器擴充 | 無 | 搜尋無任何官方 Web 版或 Chrome extension。Trustpilot 有人抱怨「付費給瀏覽器擴充作者在彈窗導流到 Typeless 官網」，屬行銷手法而非產品。（https://www.trustpilot.com/review/typeless.com ） |

注意：App Store 另有兩個同名但無關的 App（"Typeless: Keyboard Shortcuts" id6742476791、"TypeLess: AI Messenger" id6478489620），搜尋資料時要排除。

---

## 4. 桌面版完整功能清單與互動細節

### 4.1 啟動與快捷鍵
- **macOS 預設**：`Fn` = Dictate；`Fn + Shift` = Translate；`Fn + Space` = Ask Anything。可自訂（在設定裡按下想用的鍵或組合即可）。（https://www.typeless.com/help/quickstart/settings 、Threads 轉述 https://www.threads.com/@githubprojects/post/DU8TxDME-Xk/ ）
- **Windows 預設**：按住 `Ctrl + Win` 聽寫（純修飾鍵 chord，沒有一般按鍵）。這點重要到開源平替 OpenTypeless 專門開了 issue 討論「Tauri global-shortcut 無法註冊純修飾鍵 chord、需要用低階 keyboard hook 並吞掉事件以免跳出開始功能表」。（https://github.com/tover0314-w/opentypeless/issues/119 ）
- **兩種模式**：
  - Push-to-talk：按住說、放開即處理。
  - Hands-free：v1.2.0 起「按一下快捷鍵開始 Dictate / Translate / Ask Anything，再按主快捷鍵結束」。（https://x.com/typelessdotcom/status/2043705779916554435 ）
  - 台灣早期教學提到 Mac「按 Fn 開始、再按一次停止」及「Alt + 空白鍵後持續聽寫」（https://www.kocpc.com.tw/archives/625756 ）——這篇是 2025 年文章，快捷鍵配置**可能已過時**。
- **前提**：游標必須在任一 App 的文字框中（Slack、Teams、Google Docs、Notion…）。（https://www.typeless.com/help/quickstart/first-dictation ）

### 4.2 狀態列 / Overlay（"Typeless bar"）
- 官方文件稱之為 **Typeless bar**；聽寫到 5 分鐘時 bar 上出現 60 秒倒數，**6 分鐘硬上限**，超過自動把目前內容存進 History。（https://www.typeless.com/help/troubleshooting/dictation-limit ）
- 平替專案一致把它做成「螢幕底部置中的膠囊 / pill，有即時波形，聽寫中與思考中兩個狀態」（WaveType: "Siri-inspired floating waveform… Listening / Thinking states"；OpenTypeless: "Floating capsule with state indicators and idle auto-hide"）。（https://github.com/midearobin-beep/WaveType 、https://github.com/tover0314-w/opentypeless ）
- Ask Anything 的結果以「小型浮動便條（floating note）只顯示最終答案」呈現，而不是插入文字框。（https://github.com/tover0314-w/opentypeless ）

### 4.3 文字後處理（Typeless 的核心賣點）
- 去贅字（um / uh / you know）、去重複、**辨識句中自我更正只保留最終意圖**、自動標點、把口語列舉轉成編號/項目清單。（https://play.google.com/store/apps/details?id=com.typeless.mobile ）
- **App-aware 語氣**：依目前 App 調整（工作郵件 vs 聊天）。第三方比較指出 Typeless 只有「基本的 App 偵測」，不像 Wispr Flow 會讀 IDE 程式碼上下文、也沒有螢幕內容感知（使用者要回信得先把對方郵件貼到別的 AI）。（https://www.getvoibe.com/resources/typeless-vs-wispr-flow/ 、https://bossai.tech/blog/typeless-review ）
- **個人化寫作風格學習**：「越用越貼近你的語氣（formal/casual/concise/detailed）」，可在設定關閉，關閉後改用非個人化措辭。（https://www.typeless.com/help/release-notes/macos/personalized-smarter ）
- **Enhanced accuracy（Pro）vs Standard accuracy（Free）**：官方未量化差異，暗示兩套模型/路由。（https://www.typeless.com/help/billing ）

### 4.4 三個語音模式 + 兩個衍生功能
1. **Dictate**：主流程。
2. **Translate**（`Fn+Shift`）：說 A 語言、輸出 B 語言且「措辭自然」；2.0 起可預設多個目標語言並即時切換（Settings → Language → Translation targets → Edit → Add another language）。（https://www.typeless.com/help/quickstart/translate ）
3. **Ask Anything**（`Fn+Space`）：一次性語音問答，答案顯示在浮動卡片。
4. **Writing assistance / Speak to edit**：選取文字 → 按快捷鍵 → 說「改得更簡潔」「翻成西班牙文」「改成條列」→ 直接取代選取區。也能對唯讀文字做「摘要/解釋/翻譯」。（https://x.com/huang_song_/status/1968396158562353506 ）
5. **Help me write**（2026-09-22）：游標在空白文字框、**不選取任何文字**，用 Ask Anything 入口說肯定句指令（「幫我寫一封問週五有沒有空的 email」），生成草稿直接插入。系統會把「問句 → QA」「肯定句 → 生成」「有選取 + 指令 → 編輯」三種意圖分流。（https://github.com/Open-Less/openless/issues/1100 整理自官方 release notes）

### 4.5 詞典、History、同步
- **Personal dictionary**：可手動加專有名詞；台灣用戶觀察「字典會自動累積，專有名詞、品牌名、人名慢慢都會記住」。（https://readingoutpost.com/typeless/ 摘要）
- **History**：可檢視每次聽寫；「Keep history」可選 Forever / 1 year / 1 month / 1 week / 24 hours / Never，存於裝置。（https://www.typeless.com/help/quickstart/history-and-dictionary ）
- **Cloud Sync（Pro）**：History 跨裝置同步（手機記下的想法回到電腦可見）。（https://www.typeless.com/pricing ）
- **Snippets**：**沒有**。多篇比較皆指出 snippets（語音觸發固定文字如行事曆連結、簽名檔）是 Wispr Flow 有而 Typeless 沒有的功能。（https://www.getvoibe.com/resources/typeless-vs-wispr-flow/ ）
- **Whisper mode（小聲聽寫）**：來源衝突——一篇說 Free 就有，官方 help 摘要說是 Pro 功能。**待驗證**。（https://www.typeless.com/help/quickstart/key-features ）

### 4.6 語言與繁體中文
- 宣稱 100+ 語言、自動偵測、同一句混語也能處理。
- **Preferred Language Variants**：可指定 Chinese → Traditional Chinese (Taiwan) / Hong Kong / Simplified，避免輸出簡體。Windows 路徑：Settings → "Set Preferred Language Variants"。（https://www.typeless.com/help/release-notes/macos/more-language-variants-supported 、https://www.kocpc.com.tw/archives/625756 ）
- 台灣部落客實測共識：繁中準確度高、台灣用語辨識佳、中英夾雜 OK、「幾乎不會出現簡體」；但「偶爾還是會變簡中」、「偶爾修正過頭改錯意思」、「想保留口語節奏或完整逐字稿時會被過度濃縮」。（https://readingoutpost.com/typeless/ 、https://iseeu.tw/typeless/ 、https://leadingmrk.com/typeless-tutorial/ 、https://joelin.cc/p/8040 ）

### 4.7 安裝、權限與登入（onboarding）
- 下載 → 拖進 Applications → **登入（Google / Apple / email，必須）** → 授權 **Microphone** 與 **Accessibility**（官方說明 Accessibility 是為了「把文字貼進任何文字框」）→ 選麥克風與快捷鍵。（https://www.typeless.com/help/installation-and-setup 、https://www.typeless.com/help/troubleshooting/permission-issues ）
- 2025-11 的逆向分析指出 App 還會請求 **Screen Recording、Camera、Bluetooth** 等廣泛權限，並透過 macOS Accessibility API 讀取**焦點視窗標題**、瀏覽器 **URL（含 Gmail/Google Docs）**、存取**剪貼簿**，本地資料庫為**明文**。（https://www.getvoibe.com/resources/typeless-privacy-issues/ ，原始推文 @medmuspg 無法直接存取，待驗證）
- 文字插入方式未公開；從「需要 Accessibility 才能貼上」推測是**剪貼簿 + 模擬 Cmd/Ctrl+V**（平替 Talk 也採「auto-paste 需 Accessibility」；WaveType 改用 CGEvent Unicode 逐字注入以避開剪貼簿）。

---

## 5. 手機版的使用者視角

### 5.1 iOS（第三方鍵盤 extension）
- 安裝 App → Settings → General → Keyboards 加入 Typeless → **開啟 Allow Full Access**。官方 FAQ 說明 Full Access 是為了麥克風與網路。（https://www.typeless.com/help/faqs 、https://voicekeyboardpro.com/blog/enable-full-access-keyboard-iphone.html ）
- 技術背景：Apple 文件明載 custom keyboard「no access to the device microphone, so dictation input is not possible」（https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html ），且開發者論壇持續有「keyboard extension 錄音失敗（error 561145187）」的討論（https://developer.apple.com/forums/thread/775077 ）。第三方說明把 Full Access 描述為「允許存取麥克風並上傳」，但這與 Apple 文件衝突；**Typeless 究竟是在 extension 內錄音、還是靠 host app / App Group / 其他機制，是本報告最大的未解技術問題**（見第 9 節）。
- 使用流程：點文字框 → 鍵盤出現 → **點麥克風（取代原本 emoji 鍵位置）** → 說話 → 再點一次 → 文字插入。右下角另有 **Speak to edit** 鈕：選取文字 → 點 → 說指令 → 再點結束 → 取代選取區。官方範例："Hey, can we meet tomorrow to go over the plan" + 指令「把 tomorrow 改成 next Tuesday at 2 PM 並加問號」→ "Hey, can we meet next Tuesday at 2 PM to go over the plan?"（https://www.typeless.com/help/release-notes/ios/speak-to-edit ）
- 使用者抱怨：emoji 鍵被佔用（多則負評）、鍵盤在背景讓螢幕不會自動鎖定（auto-lock bug）、希望加 Enter 鍵、「Apple 限制讓它不能自動使用」。（https://apps.apple.com/us/app/typeless-ai-voice-keyboard/id6749257650?see-all=reviews&platform=iphone 摘要）
- 評分：4.5 / 729 評分（美區，2026 年初資料）。

### 5.2 Android（IME，無軟鍵盤）
- 首次啟動導覽：麥克風權限 → 設為輸入法 → **朗讀幾句話做校準**（第三方 user guide 說約 30 秒、安靜環境；準確度低時可重跑）。（https://www.makeuseof.com/typeless-ai-voice-typing-android/ 、https://typeless.cc/en/user-guide.html — 後者網域非官方，待驗證）
- 鍵盤呈現：**只有一顆大麥克風，沒有 QWERTY**。點一下開始、再點一下結束；中間長時間停頓也不會自動停止。用 Android 導覽列的地球圖示或鍵盤右下角圖示切回 Gboard。Computerworld 與 MakeUseOf 皆定位為「Gboard 的補充（supplement）」。（https://www.computerworld.com/article/4122901/android-voice-typing-supertool.html ）
- Help me write 在 Android 有專屬按鈕（2.7.0）。
- 使用者抱怨：輸密碼時無法切回一般鍵盤、希望邊說邊看到字（即時字幕）、引號樣式不一致、隨機插入 emoji、沒有 emoji/GIF、常常要切回 SwiftKey 修正。（https://play.google.com/store/apps/details?id=com.typeless.mobile 摘要）
- 台灣 Threads 使用者：「手機開始比較頻繁卡頓，推測 Typeless 一直在背景運作吃資源」。（https://www.threads.com/@elijah.shi.sensei/post/DTcFbJeiQ60/ ）

---

## 6. 定價與限制

| 方案 | 價格 | 內容 |
|---|---|---|
| Free | $0 | **8,000 字/週**（多篇 2026-06/07 文章一致）；standard accuracy；高峰時段 standard access；Whisper mode（來源衝突） |
| Pro | **US$12/member/月（年繳 US$144）** 或 **US$30/月（月繳）** | unlimited words、enhanced accuracy、priority access、Cloud Sync、team member management、usage analytics、集中帳單 |
| Enterprise | 客製 | SSO、SCIM、domain verification & capture、可設定保留期的 audit logs、enforced HIPAA controls、volume discounts、彈性付款、優先支援 |
| 試用 | 新帳號 30 天 Pro | 到期自動降為 Free |

來源：https://www.typeless.com/pricing （摘要）、https://usevoicy.com/blog/typeless-pricing 、https://www.getvoibe.com/resources/typeless-pricing/ 。

**2026-09-22 疑似調降免費額度**：一個 GitHub PR 標題「Typeless: free tier drops to 2,000 words/week from Sep 22」（https://github.com/richcalls/dictation-list/pull/4 ，抓取時 404），另一個第三方工具 Typeless Switch 的「依週字數自動輪換帳號」預設值正是 **2,000 字**（https://github.com/caofanf/typeless-switch-mac ），兩者互相印證但都非官方。**若屬實，Free 方案只剩原來的 1/4**，對我們的免費額度策略影響很大，列為 critical 待驗證。

其他硬限制：
- 單次聽寫 6 分鐘。
- 純雲端，無離線模式；離線或高峰時出現 "High demand right now, couldn't finish writing"，且無重試鈕。（https://bossai.tech/blog/typeless-review ）
- 免費方案有「super annoying pop-up windows」。（Trustpilot 摘要）
- 月繳 US$30 被多篇評測稱為「類別中最貴」；相較 Wispr Flow 免費 2,000 字/週但月繳較便宜。

---

## 7. 技術堆疊：已知與推測

**已知（有來源）**
- 處理在雲端：官方 privacy / data-controls 頁說「audio inputs and contextual information are processed in real time on cloud servers and immediately discarded once the transcription result is returned」、不用於訓練。（https://www.typeless.com/privacy 、https://www.typeless.com/data-controls 摘要；https://x.com/typelessdotcom/status/1965243454331761036 ）
- 伺服器位置 AWS **us-east-2**（俄亥俄）；上傳內容除音訊外還有視窗標題、URL 等 context（2025-11 逆向分析）。
- 延遲：VoiceDash 2026 測試 Typeless ≈ **3.0 秒**（說完到文字出現）vs Wispr Flow ≈ 1.5 秒；同篇給 Typeless WER ≈ 20% vs Wispr 3.9%——**該站是競品，數字要打折**。（https://voicedash.ai/wispr-flow-vs-typeless/ ）台灣平替 SayIt 以「3 秒完成輸入」為賣點對打 Typeless（https://www.kocpc.com.tw/archives/635026 ），側面印證 Typeless 體感在 2–4 秒。
- 從「enhanced vs standard accuracy」、「priority access during high demand」可推測後端有**兩個品質層級的模型路由**與**佇列/限流**。

**未知 / 無可靠來源**
- STT 供應商（Whisper？Deepgram？ElevenLabs Scribe？自研？）與 LLM 供應商（GPT / Gemini / Claude？）——搜尋不到任何洩漏或官方說明。
- 桌面 App 框架（Electron / Tauri / 原生）未查到。

**開源平替社群的經驗值（可直接拿來當我們的起點）**
- OpenTypeless（Tauri v2 + Rust + React，MIT）：推薦 Groq `whisper-large-v3-turbo` + Google `gemini-2.5-flash`；支援 Deepgram、AssemblyAI、GLM-ASR、SiliconFlow、Volcengine Doubao、Ollama；Windows 用 SendInput、macOS 用鍵盤模擬 + 剪貼簿備援；SQLite 存 History / 詞典；71 個內建 App profile 做 app-aware。（https://github.com/tover0314-w/opentypeless ）
- openless：**串流逐字插入**（polish 一邊產生一邊打到游標，降低體感延遲）；prompt 原則「模型只清理文字，不回答問題；輸出只有清理後文字」；Style Pack 市集。（https://github.com/H-Chris233/openless ）
- platx-ai/Talk（全本地 macOS）：Qwen3-ASR-0.6B 對 3–5 秒音訊 0.07–0.18 秒、Qwen3.5-4B polish 0.35–1.2 秒、**全管線約 1 秒**。（https://github.com/platx-ai/Talk ）
- WaveType：MLX Qwen3-ASR 1.7B + Ollama；CGEvent Unicode 注入；**自動從使用者事後修改 diff 出更正對，回灌成 ASR hotword 與 LLM 約束**（這是 Typeless「字典會自動累積」的開源實作版）。（https://github.com/midearobin-beep/WaveType ）
- Typeless Switch：第三方「多帳號輪換」工具，顯示免費額度被繞過的壓力，也提示我們做免費方案時要考慮 device fingerprint 與濫用。（https://github.com/caofanf/typeless-switch-mac ）

---

## 8. 使用者評價彙整

**讚美（Product Hunt / X / 台灣部落格）**
- 「真的能直接送出」：清理贅字、自我更正、自動清單是最常被提到的 wow moment（Computerworld：「看起來像認真寫過的 email，含編號清單」）。
- 速度：官方比較 QWERTY 45 WPM vs 語音 220 WPM；PH 用戶自述 158 WPM、19 天省 10 小時。（https://www.producthunt.com/products/typeless-2/reviews 摘要）
- 繁中/台灣用語/中英夾雜品質（第 4.6 節）。
- 免費額度大（相對 Wispr Flow 2,000 字/週）、30 天完整試用。
- 翻譯與語音編輯是相對 Wispr Flow 的差異化優勢。

**抱怨**
- 延遲約 3 秒、比競品慢。
- 6 分鐘上限 + "High demand" 錯誤無重試。
- 隱私行銷（"on-device history"）與實際雲端處理的落差；要求過多權限。
- iOS：emoji 鍵被佔、auto-lock bug、缺 Enter。
- Android：沒有鍵盤、密碼無法輸入、引號/emoji 不一致、背景耗資源。
- 過度潤飾：想要逐字稿時被濃縮；偶爾改錯意思；偶爾簡體。
- 月繳太貴；免費版彈窗；導流式行銷。
- 情境限制：開放辦公室不方便說話（這點所有語音產品共通）。

評分總表：Product Hunt 5.0（11 則）、App Store 4.5（729）、Google Play 4.1（2.85K；另一來源 3.9 / 1,335 為較早資料）、Trustpilot 2.5–2.6（7 則）。（https://spokenly.app/blog/typeless-review 、https://www.trustpilot.com/review/typeless.com ）

---

## 9. 對我們的設計意涵

1. **「Typeless 體驗」可以被精確定義為五件事**，我們的 MVP 應一次做齊，否則不會被認為是同類產品：
   (a) 一顆全域快捷鍵（Mac `Fn`、Windows 純修飾鍵 chord 要能處理）+ 按住 / 免持雙模式；
   (b) 底部置中的膠囊狀態列，有即時波形與「聽 / 想 / 錯誤」三態，且能出現在全螢幕 App 之上；
   (c) 兩段管線：串流 STT → LLM 清理（去贅字、自我更正、清單化、App-aware 語氣），prompt 必須「只清理、不回答」；
   (d) 三個入口：Dictate / Translate / Ask-Edit（選取文字 → 指令；無選取 → Help me write）；
   (e) 個人詞典（自動從使用者修改學習）+ History（本地、可設保留期）+ 風格學習開關。
2. **延遲是最大可攻擊點**。Typeless 約 3 秒；本地 Qwen3-ASR + 小型 LLM 已能做到約 1 秒，openless 的串流逐字插入進一步降低體感。我們應設計為「STT 串流 + LLM 串流輸出 + 逐字插入」，並提供「raw 模式」（不潤飾、零 LLM 延遲）給想要逐字稿的人，直接回應「過度濃縮」抱怨。
3. **單次時長不要設 6 分鐘硬上限**；改用分段（chunked）轉錄 + 滾動上下文，長篇口述是明確需求（OpenTypeless/Tyler913 以「long dictation, talk for minutes」為賣點）。
4. **離線 / 本地選項是差異化也是信任**。Typeless 的隱私爭議（雲端、AWS、視窗標題/URL 上傳、明文 DB）給我們空間：預設本地 ASR（Apple Speech / Qwen3-ASR / whisper.cpp）、雲端 LLM 可選、明確的 context 蒐集開關、本地 DB 加密。
5. **手機鍵盤設計要修正 Typeless 的兩個明顯錯誤**：iOS 不要佔用 emoji 鍵（把麥克風放在空白鍵旁或獨立列）；Android 要提供最小可用鍵盤（至少能打密碼與修正）或「一鍵切回系統鍵盤」。並且要做即時字幕（邊說邊看到字）。
6. **iOS 錄音架構必須先做技術驗證（spike）**：Apple 文件說 keyboard extension 無麥克風；Typeless 顯然做到了某種流程（Full Access 後直接在鍵盤內按麥克風）。可能路徑：extension 內使用 `AVAudioSession`（實務上部分 iOS 版本可行但不穩）、或透過 host app 錄音 + App Group / Darwin notification 回傳文字。這決定 iOS 架構，列為 critical。
7. **繁體中文要變成「保證」而非「支援」**：Preferred Language Variant（zh-TW）預設開啟、輸出前做簡→繁強制轉換與台灣用語表、中英夾雜用 code-switching 友善的 ASR（實測 Qwen3-ASR / Whisper large-v3 對 zh-en 混語的表現）。
8. **定價可對位**：Free 給比 Typeless（若已降為 2,000 字/週）更大的額度但限制雲端 LLM 次數；本地模式無限免費；Pro 定在 US$8–10/月年繳以低於 Typeless 的 $12。Snippets（Typeless 沒有）、團隊詞典、程式碼上下文（IDE）是低成本的加分項。
9. **權限與 onboarding**：只要 Microphone + Accessibility（Windows 不需 Accessibility，但純修飾鍵 chord 需低階 hook）；不要像 Typeless 要 Screen Recording / Camera / Bluetooth；登入可延後（Typeless 強制登入是抱怨點之一）。
10. **防濫用**：Typeless Switch 的存在說明免費額度會被多帳號繞過；設計時就要有 device 綁定與合理的 rate limit，而不是事後用彈窗懲罰免費用戶。

---

## 10. 未解問題（需本機或人工驗證）

1. **iOS 鍵盤的錄音機制**：extension 內直接錄音？還是 host app 中繼？Full Access 關閉時行為？（決定 iOS 架構，critical）
2. **免費額度是否已於 2026-09-22 從 8,000 降到 2,000 字/週**（兩個非官方來源互證，官方 pricing 頁無法抓取）。
3. **Whisper mode 是 Free 還是 Pro 功能**（來源衝突）。
4. **Typeless 目前的 STT / LLM 供應商**與是否自研模型；"enhanced accuracy" 的實際差異。
5. **桌面文字插入方式**（剪貼簿貼上 vs CGEvent/SendInput 逐字）以及是否會還原剪貼簿。
6. **Windows / Linux 版的框架與套件格式**（Electron? Tauri? .deb/.AppImage?）。
7. **Mac Intel 版最低 macOS 版本**。
8. **2026-03 募資金額與估值**（PitchBook 未揭露）；Crunchbase「Typeless Pte.」是否同一家。
9. **Linux 版確切發布日期**（X 貼文 ID 2103109386860364050，推測 2026-09 下旬）。
10. **目前 iOS 版號與是否已修 auto-lock bug、是否已把 emoji 鍵還回去**（App Store 資料為 2026-01，可能過時）。
11. **@medmuspg 逆向分析的原始內容**（僅透過第三方轉述；需確認是否仍成立於 2.x 版）。
12. **App-aware 的實作深度**：是只看 bundle id / process name，還是有讀取視窗內容？與其隱私爭議相關。
