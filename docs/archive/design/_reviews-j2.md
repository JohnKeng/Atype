# 評審 J2 原始意見

評審視角：資深平台工程師（macOS/iOS/Android 內部機制，檢查每個技術主張在現行 OS 版本與商店政策下是否成立）

評分維度（1–10）：feasibility_small_team、time_to_mvp、chinese_quality、cost、privacy、maintainability；total = 加總。

**勝出提案**：Atype：MVP-First 執行方案（雲端優先、最少原生碼、12 週可收費）


## Atype：MVP-First 執行方案（雲端優先、最少原生碼、12 週可收費）

| 面向 | 分數 |
|---|---|
| 小團隊可行性 | 9 |
| MVP 時程 | 9 |
| 中文品質 | 7 |
| 成本 | 5 |
| 隱私 | 5 |
| 可維護性 | 7 |
| **總分** | **42** |

平台可行性最高的一份：桌機直接 fork MIT 的 Handy（§2.2、§4），把 handy-keys 的 CGEventTap/WH_KEYBOARD_LL、paste_tx 收據式貼上、Secure Input 影子註冊全部繼承，§5.1/§5.2 的每個 API 細節（keycode 63 + maskSecondaryFn、AppleFnUsageType、UCKeyTranslate、VK_V、LLKHF_INJECTED、UIPI 完整性等級、WM_RENDERFORMAT）都與現行 macOS 26 / Windows 11 行為一致；iOS 走「主 App 錄音 + SpeechTranscriber + 鍵盤只 insertText」是 Apple 文件允許的唯一正規路徑，而且把音訊留在裝置、STT 成本為零，是三份裡最聰明的 iOS 取捨。對查核檔的態度也最防禦（文首 (a)–(d)），所有 Typeless 數字只當錨點。但要扣分的技術點：(1) §5.1 第 4 點的授權活性探針用 `CGEventTapOptions::ListenOnly` 建鍵盤 tap——在 Catalina 之後 listen-only 鍵盤 tap 歸 Input Monitoring 管轄，而實際熱鍵 tap 是 `Default`（Accessibility），探針可能彈出另一個 TCC 對話框或給出假陰性；應改用與 handy-keys 相同的 `.defaultTap` flagsChanged tap 當探針（研究 desktop-macos.md §2.3 也列為未解題，但本文程式碼已寫死）。(2) §5.3 第 4 點以 `max_tokens: 0` 做 Haiku cache 預熱——Messages API 要求 max_tokens ≥ 1，會直接 400；改成 1。(3) §5.4 鍵盤「App Group 讀取不需 Full Access」是三份共有的假設，Apple《Configuring open access》文件把 shared container 列在 open access 能力裡，雖然研究檔與 Dictus 稱唯讀可行，但這是整個 iOS 交接協定的地基，本文把它排進 W1 spike 是對的，不應寫成已知事實。(4) §2.2 iOS 最低 26、§9 把 AudioRecordingIntent/ControlWidget 延到 M8——這條不經鍵盤的入口恰好是 4.4.1 退件時最便宜的保險（R1 自己也承認），應提前進 MVP。(5) 品質面：桌機吃雲端串流、iOS 吃 Apple 本地（CER ≈ 8），同一個使用者在兩台裝置上會感受到不同的中文準確率；§5.5 詞典只做子字串精確比對、沒把 known terms 餵進 STT keyterm，AutoLearn 排 v1，中文品質層明顯比 quality-first 薄。(6) 成本：§7.2 Free 用戶每月 $0.44 全靠雲端 STT 燒，5,000 Free MAU 一個月 $2,200，M6 本地引擎如果延誤會直接吃掉毛利；§7.3 的 53–57% 毛利對 $10 定價偏緊。(7) 隱私：桌機音訊預設送美國供應商，與 local-first 相比沒有「關掉雲端就零外連」的可驗證敘事，只有誠實文案。總體而言，這是唯一一份 1–2 人在 12 週內真的做得完、而且每個平台 API 都站得住的方案。


## Atype：本地優先（Local-first）、隱私為差異化的跨平台語音聽寫產品——架構與執行方案

| 面向 | 分數 |
|---|---|
| 小團隊可行性 | 5 |
| MVP 時程 | 5 |
| 中文品質 | 5 |
| 成本 | 9 |
| 隱私 | 10 |
| 可維護性 | 6 |
| **總分** | **40** |

隱私與成本結構是三份裡最好的（§3 資料流原則、§7.2 Free < $0.15/月、SQLCipher 歷史、GPL 桌機可驗證「音訊沒出去」、W7 驗收要求 Little Snitch 抓包截圖），§5.1 的注入階梯與 §5.2 的 HoldOrToggle 狀態機（雙擊鎖定、1 s chord 中斷窗、Windows 鉤子 watchdog）寫得比另外兩份更完整，R9 對 SenseVoice 權重授權的提醒也是另外兩份漏掉的。但作為平台工程師我不相信它的 12 週。(1) §4/§附錄 A 要求 Rust 核心經 UniFFI 0.32 同時產出 XCFramework、AAR、桌機靜態庫，W2 就要 Swift/Kotlin 綁定 smoke test，§5.3 還承認 sherpa-onnx Rust crate 在 aarch64-linux-android 的靜態連結「若 W10 前無法穩定建置」要改走 Kotlin API——這等於核心抽象在 Android 上破功，三個平台最後還是各寫一份 STT 層；(2) §2.1 macOS 26 的 SpeechTranscriber 與 Apple Foundation Models 都要經 swift-rs 從 Tauri 的 Rust 側橋接（§5.5(d) AppleFM.swift「與 iOS 主 App 共用同一檔」），這條 Rust→Swift→Rust 的 FFI 鏈在 Tauri 專案裡的建置與簽章成本被嚴重低估；(3) §6 的 MVP 定義同時包含 macOS + Windows 可付費、Android 輔助 IME alpha、iOS 主 App v0 加鍵盤 spike，兩個人 12 週，W10–W12 三週內要做完 Android IME、iOS App、付費與 beta——不可信，連文中自己的「一人版」都把 iOS/Android 推到第 4–5 個月。(4) 中文品質是硬傷：§1 論點用 SenseVoice-Small 的 AISHELL-1 CER 2.96 當證據，那是大陸朗讀語料，不含台灣口音、不含中英夾雜，而且模型輸出簡體，整個繁體保證壓在 OpenCC s2twp 上（§5.3 自己承認「沒有一個是為台灣訓練」、驗收門檻 CER ≤ 8%、R1 標為高/高）；Apple SpeechTranscriber zh_TW 的 CER ≈ 8 也不如雲端；音訊上雲要到 M6 才有（§6 Roadmap），所以 MVP 期間「贏 Typeless 的中文正確率」這個產品主張是立不住的——它賣的是隱私，不是品質。(5) §2.1 iOS 17/18 在主 App 內放 47 MB Zipformer、Android 首次下載 228 MB SenseVoice 並在中階機吃 400–500 MB（R10），都是真實的 OEM 殺進程與留存風險。(6) 對查核檔的處理與另外兩份相當；但 §2.2 引用的 Apple locale 數量（30 vs 42）正是可能被修正的項目，本文已標待驗證，可接受。結論：這是正確的 v1 終點（M6 本地引擎 + 開源桌機），不是正確的 MVP 起點。


## Atype：品質優先（Quality-first / Chinese-first）方案——以「繁中＋中英夾雜正確率」與「亞秒級延遲」打敗 Typeless 的架構與執行計畫

| 面向 | 分數 |
|---|---|
| 小團隊可行性 | 5 |
| MVP 時程 | 4 |
| 中文品質 | 9 |
| 成本 | 5 |
| 隱私 | 6 |
| 可維護性 | 6 |
| **總分** | **35** |

中文品質層是三份裡最專業的：§5.1(a) 黃金測試集的 jsonl schema（ref_raw / ref_clean / tags / terms）、以 OpenCC t2s 往返偵測簡體洩漏、靜音段幻覺插入字數、注入通過率當 CI gate（§5.1(f)）、(c) 詞典條目用占位符豁免 s2twp 誤轉、(e) 拼音相似度詞典比對 + 把 known terms 同時餵進 STT keyterm / LLM / 確定性層三處 + AutoLearn 閉環，以及 §4 把 atype-text 編成 WASM 讓 Worker 與 eval 跑同一份正規化碼——這些都該直接進最終計畫。§5.2 的 0.5 s pre-roll、上游未 ready 前的 pending 佇列、v1 的 pipelined cleanup 也是正確的延遲工程。但架構決策對 1–2 人、TS 為主的團隊不成立：(1) §2.2 「既然 iOS 一定要寫 Swift，讓 macOS 直接共用它」——實際能共用的只有 AudioPipeline / STT engine / Polish / History（§4 AtypeKit），而 macOS 最難、最花時間的部分（§5.3 的 CGEventTap 熱鍵狀態機、收據式 Paster、AX FocusClassifier、NSPanel HUD、Secure Input、Sparkle、onboarding）全是 mac-only，而且 VoiceInk 是 GPL 只能看不能抄，等於要用一個不熟的語言從零重寫 Handy 已經用 MIT 送給你的東西；「≥ 70% 共用」的前提（§1 末段、R13）在我看來達不到 50%。(2) §6.2 兩個人 12 週同時交付 macOS GA、iOS App Store、Windows 公測、Android 開放測試四個平台，Track B 一個人要做 Rust 核心、Windows 殼、後端、Android、eval——不可信；自己的「1 人」版本已把 Windows 推到 M4、Android 到 M5–M6。(3) §5.1(e) 假設 Deepgram Nova-3 的 keyterm 可用於 zh-TW——研究 stt-engines.md 明寫 Nova-3 keyterm「英文最佳」且 multi 模式不含中文，keyterm 對中文很可能無效，本文把它當作三個注入點之一卻沒標待驗證。(4) §5.2 延遲預算把 Haiku 清理押在 p50 550 ms，但 llm-postprocess 的量測是 TTFT 0.6–1.0 s，加上 50 字輸出，p50 ≤ 0.9 s 的 KPI 要靠 M5 自架 Qwen3-ASR 才可能達成；mvp-first 的 1.1–1.5 s 才是誠實數字。(5) §7.2 COGS 是三份最高（Pro 典型 $4.65、毛利 48–52%），且 §7.3 不賣終身方案，重度用戶一律負毛利，只能靠 150k 字/月公平使用硬擋。(6) §5.3(d) 用 NSEvent.addGlobalMonitorForEvents 當授權探針——鍵盤事件的 global monitor 同樣牽涉 Accessibility / Input Monitoring 歸屬問題，與實際 `.defaultTap` 的授權狀態不一定同步。(7) 隱私：Apple 平台免費層本地、不送視窗標題是加分，但 Pro 桌機音訊預設上雲且 M5 要自架 GPU（R14 維運）。結論：品質層與 eval 基礎設施應整份搬走，但原生雙棧的架構會讓 MVP 延後至少一季。


## 應嫁接進最終方案的其他提案優點

- 【quality-first §5.1(a)(f)】整套 eval 設計：golden jsonl schema（ref_raw / ref_clean / tags / terms / speaker / env）、簡體洩漏率以 OpenCC t2s 往返偵測、靜音／音樂／咳嗽 30 段的幻覺插入字數、贅詞移除 precision/recall、注入通過率 100% 與簡體 0 作為 PR gate（eval.yml 擋 prompt / 模型改動）、STT bake-off 每月重跑；mvp-first 的 200 句集應直接採用這個 schema 與指標。
- 【quality-first §4】一份中文正規化碼、多個產物：把 OpenCC s2twp / pangu / 全形標點 / 口語指令 / 剝殼 寫成一個無 I/O 的 Rust crate（atype-text），MVP 先編成 WASM 給 Worker 與 eval runner 共用，保證「後端量到的」與「使用者看到的」是同一段碼；M6 做本地引擎時再編成 XCFramework / AAR 給客戶端，而不是 M9 才評估共享核心。
- 【quality-first §5.1(e)】中文詞典三個注入點：拼音相似度（pinyin crate + 滑動視窗 ≥ 0.85）取代 mvp-first 的子字串比對、DO 在每次 start 把 ≤ 50 條最相關 keyterm 餵給 ElevenLabs Scribe v2（Deepgram 的中文 keyterm 須先驗證）、LLM <known_terms> 以拼音 bigram Jaccard 挑選；AutoLearn（使用者 10 秒內修改 → diff → Haiku 四欄 JSON 判定 → ✨ 標記入庫）排進 M5 而非更晚。
- 【quality-first §5.1(c)、local-first R15】OpenCC 誤轉防護：詞典條目以占位符保護後再做 s2twp、提供「只轉字 s2tw」設定、以引擎回報的語言標籤 gate 轉換避免誤轉日文漢字。
- 【local-first §5.4(d) / quality-first §5.4 第 4 點】把 AudioRecordingIntent + ControlWidget（Action Button / Control Center / 鎖定畫面）從 M8 提前進 MVP 的 iOS 主 App（與 Live Activity 同時啟動），作為不經鍵盤的主入口與 4.4.1 退件時的保險；鍵盤只負責 insertText。
- 【quality-first §5.2】延遲工程細節：客戶端 0.5 s pre-roll 環形緩衝、上游 ready 前的 pending 佇列一次沖出、放開熱鍵即 finalize 不等 VAD；v1 的 pipelined cleanup（每個 final 句就先送 LLM，放開時只剩最後一句）作為長句 p95 超標時的對策。
- 【local-first §3 資料流原則、§9 第 13 條】隱私分三級（全本地 / 文字上雲 / 音訊上雲）寫死在設定 UI 與隱私政策，音訊上雲走獨立端點、獨立同意、獨立計量；W7 式驗收：關閉雲端時以 Little Snitch / Wireshark 抓包證明零外連並把截圖放進公開 docs。
- 【local-first §2.1、§5.3(a)】macOS 26 的 SpeechTranscriber zh_TW 作為桌機免費層本地引擎應從 M6 提前（Handy 已有 apple_intelligence.rs 的 Swift FFI 模式可照抄），這是把 Free 用戶 COGS 從 $0.44 壓到 ≈ $0.1 的最便宜槓桿，也讓「iOS 與 macOS 用同一個 Apple 引擎」的品質一致。
- 【local-first §5.2(b)(e)】熱鍵狀態機與 Windows 鉤子紀律：Down 後 1.0 s 內出現其他鍵即視為一般快捷鍵不觸發、< 300 ms 放開為 toggle、300 ms 內二次 Down 為 hands-free 鎖定、Esc / 任意非修飾鍵取消；Windows 回呼零 I/O、dwExtraInfo 標記自家 SendInput、每 30 s watchdog 檢查鉤子是否被靜默移除並重裝。
- 【local-first R9、附錄 B 第 6 條】M6 啟用本地引擎前先讀完 SenseVoice / Paraformer 的 ModelScope Model License 商用分發條款；模型不打進安裝檔、由使用者從 R2 下載；備案 Qwen3-ASR（Apache-2.0）與 Breeze-ASR-25（MIT）。
- 【local-first §2.1 History】歷史用 rusqlite bundled-sqlcipher 加密落地，而不是明文 SQLite（Typeless 被抓包的「本地明文 DB」）。
- 【quality-first M6】s2hk + 香港用語表與粵語（SpeechTranscriber zh_HK / yue_CN、Scribe v2 Cantonese）作為第二市場的擴張路徑，確定性層已天然支援。
- 【三份共同的修正建議】授權活性探針應用與實際熱鍵 tap 相同的 `.defaultTap` flagsChanged tap 建立／釋放來測，而不是 ListenOnly tap 或 NSEvent global monitor（避免 Input Monitoring 歸屬差異造成假陰性）；Haiku cache 預熱請求 max_tokens 設 1 而非 0；「App Group 唯讀不需 Full Access」與「無 Full Access 可 extensionContext.open / Darwin post」維持為 W1 真機 spike 的前提而非既定事實。
