# 評審 J1 原始意見

評審視角：務實的獨立開發者（已獨自出貨付費 Mac + iOS App，在意 time-to-revenue 與維護負擔）

評分維度（1–10）：feasibility_small_team、time_to_mvp、chinese_quality、cost、privacy、maintainability；total = 加總。

**勝出提案**：Atype：MVP-First 執行方案（雲端優先、最少原生碼、12 週可收費）


## Atype：MVP-First 執行方案（雲端優先、最少原生碼、12 週可收費）

| 面向 | 分數 |
|---|---|
| 小團隊可行性 | 9 |
| MVP 時程 | 9 |
| 中文品質 | 7 |
| 成本 | 6 |
| 隱私 | 5 |
| 可維護性 | 7 |
| **總分** | **43** |

這是三份裡唯一把「1–2 人、12 週」當真的方案。§4 明說不做共享 Rust core / UniFFI、所有智慧放一個 Worker（薄客戶端＋胖後端），§2.2 直接 fork Handy 把熱鍵、Secure Input、收據式貼上、三平台打包全部白拿，iOS 只寫薄鍵盤＋主 App——這是最短的可信路徑。§6.1 在 W6 就有 Paddle 收款與 macOS 公測、W6 設 iOS go/no-go、W10 送審，兩個停損點（W6、W10）對獨立開發者極重要。對 `_verification.md` 的處理也最誠實：§5.1 第 6 點明寫 Typeless Windows 預設是 Right Alt 而非 Ctrl+Win，並把 Typeless 數字只當錨點。不同意的地方：(1) §2.1 / §5.1 第 6 點 / W11 仍把 Windows 預設定為 Ctrl+Win，理由是「Wispr Flow 的預設」——這條來自同一份被修正過的研究，且未被查核；既然查核檔唯一可讀的修正就是 Right Alt，預設應改 Right Ctrl 或 Right Alt，Ctrl+Win 降為備選。(2) §5.5 詞典「MVP 只做子字串比對」太弱，中文誤辨（成慶/承慶）靠子字串完全抓不到，而 quality-first 的拼音滑窗比對用 TS 的 pinyin 套件一天就能做。(3) §2.1 iOS 全走 Apple `SpeechTranscriber`（CER 7.97、無熱詞 API）、桌機走雲端，等於同一個產品兩種品質曲線，eval 集要分兩套跑；可接受但 §7.2 把 iOS COGS 當優勢時要同時承認品質落差。(4) §9 把本地引擎押到 M6，但 §7.3 自己算出 5,000 Free MAU 每月燒 US$2,200；macOS 26 的 `SpeechTranscriber` 透過 Swift FFI（Handy 已有 apple_intelligence 的 FFI 模式）當 Free 層本地 STT，應提前到 M4。(5) §5.3 延遲預算把 Haiku 清理估 p50 700 ms，但 §2.2 自己引用的 TTFT 是 0.6–1.0 s，p50 1.5 s 的門檻很可能要靠 W3 的 provider 切換才達標——好在 W3 有硬性切換規則。(6) §5.5 的 opencc-js 授權標 ⚠ 未確認，W1 要查。(7) R10 Handy fork 每月 rebase 是真實的持續成本，建議只動 `cloud/`、`stt/` 與 UI，不改 Handy 既有模組。整體：對「最快把錢收進來、最少要維護的碼」這兩個指標，這份最接近我自己會做的。


## Atype：本地優先（Local-first）、隱私為差異化的跨平台語音聽寫產品——架構與執行方案

| 面向 | 分數 |
|---|---|
| 小團隊可行性 | 5 |
| MVP 時程 | 4 |
| 中文品質 | 5 |
| 成本 | 9 |
| 隱私 | 10 |
| 可維護性 | 4 |
| **總分** | **37** |

成本與隱私結構最漂亮（§7.2 Free 用戶每月 < US$0.15、Pro 典型 US$0.65–1.3；§3 資料流原則與三級隱私標籤寫得最清楚），對 Right Alt 修正的處理也正確（§2.1 Windows 列 Right Alt 為查核檔確認的 Typeless 預設）。但作為要在 12 週內收費的獨立開發者，我無法接受以下幾點：(1) §1 論點把產品押在「預設路徑＝本地引擎」，而 §5.3 自己承認「本地中文引擎沒有一個是為台灣訓練的、SenseVoice 輸出簡體、Apple 無熱詞 API」，R1 標為「高／高」（本地 CER 輸雲端 > 2 倍）。換句話說，前六個月你賣的是一個在「中文準不準」這個唯一決勝點上刻意比 Typeless 弱的產品，雲端音訊要到 M6 才給 Pro opt-in。研究本身已說明中文市場勝負在 LLM 層，而 §5.5(d) 的本地 LLM 是 Apple FM（zh-TW 支援未驗證、4,096 token 含輸出、prompt ≤ 300 token）或 Windows 上 2–4 s 的 llama.cpp——清理品質一定明顯退步。(2) §2.2「為什麼共享核心是 Rust + UniFFI」：三個客戶端真正共用的只有清理規則與協定，MVP-first §4 說得對，放 Worker 一處最快；UniFFI 0.32 + XCFramework + AAR + swift-rs 橋接 + sherpa-onnx Rust crate 在 Android 的靜態連結（§5.3(a) 自己承認可能建不起來）是 1–2 人不該在 W2 就背的工具鏈。(3) §6 時程：Paddle 收款排在 W12（MVP-first 是 W6），W10 Android alpha、W11 iOS v0、iOS 鍵盤正式版要到 M4——12 週內同時碰五個平台，而 iOS 在 M4 之前沒有可競爭的產品。(4) §2.1 Android 預設下載 228 MB SenseVoice、IME 內 400–500 MB RAM（R10 OEM 殺進程）加上 R4 Gboard 不交接，對台灣主流注音使用者是雙重摩擦。(5) 對被修正研究的依賴：SenseVoice AISHELL-1 CER 2.96 是簡體朗讀語料，與台灣口音＋中英夾雜無關；Apple locale 數「30 vs 42」不一致；這些都在 stt-engines（2 條被修正）的範圍內，方案雖標「待驗證」，但整個預設引擎選型就建立在上面。(6) 維護面：五個平台 × 本地引擎二進位 × 模型下載 / 校驗 / 卸載 × 單人維護的 crate（R8）× 兩種本地 LLM runtime，對一個人是長期負擔。這份方案是很好的 v1.5–v2 方向（本地無限免費層、Lifetime 桌機版、GPL 開源驗證），不是 MVP。


## Atype：品質優先（Quality-first / Chinese-first）方案——以「繁中＋中英夾雜正確率」與「亞秒級延遲」打敗 Typeless 的架構與執行計畫

| 面向 | 分數 |
|---|---|
| 小團隊可行性 | 5 |
| MVP 時程 | 5 |
| 中文品質 | 9 |
| 成本 | 5 |
| 隱私 | 6 |
| 可維護性 | 5 |
| **總分** | **35** |

中文品質層是三份裡最完整、最可量測的：§5.1(a) 黃金測試集 schema（tags / terms / ref_raw / ref_clean）與指標定義（簡體洩漏率用 t2s 差異判定、幻覺插入字數、贅詞 P/R、注入通過率）、§5.1(e) 拼音滑窗詞典＋三個注入點（STT keyterms / LLM known_terms / 確定性替換）＋ AutoLearn 閉環、§5.1(f) eval 當 PR gate 的硬門檻、§5.2 的暖連線＋0.5 s pre-roll＋pending 佇列沖出、pipelined cleanup——這些全部該進最終計畫。對 Right Alt 修正處理正確（§2.1 Windows 預設 Right Ctrl、備選 Right Alt）。但我不同意它的核心分歧：(1) §2.2「為什麼 macOS 與 iOS 走原生 Swift」：AtypeKit 共用 ≥ 70% 的是音訊 / STT / 清理 / 歷史這些相對簡單的層，而 macOS 真正難、真正吃時間的部分（§5.3 的 CGEventTap 熱鍵、收據式 Paster、NSPanel HUD、Secure Input、焦點分類、Sparkle、onboarding）正是 Handy 已經用 Rust 解掉的；VoiceInk 是 GPL 只能看不能抄，等於要用 Swift 重寫 3–4 週，然後永遠維護兩套桌機（§4 的 `AtypeMac` 與 `desktop-win`）：每個熱鍵 / 貼上 bug 修兩次、兩個更新器（Sparkle vs tauri-updater）、兩套設定頁。對獨立開發者這是最昂貴的決定。(2) §6.2 兩軌 12 週要同時交付 macOS GA、iOS App Store、Windows 公測、Android 開放測試，不可信；§6.1 的 solo 版本把 Windows 推到 M4、Android 到 M5–M6，結果與 MVP-first 一樣晚，卻多了一套 Swift 桌機碼。收款排在 W10，比 MVP-first 晚一個月。(3) §1 的 KPI「p50 ≤ 0.9 s 打敗 Typeless 的 3 s」建立在 typeless-teardown（5 條被修正，佔查核檔修正數的近半）的二手數字上；若 Typeless 實際體感沒有 3 s，這條差異化就縮水，而為了達成 0.9 s 又要走 §5.2 第 6 點的自架 Qwen3-ASR-1.7B（東京 GPU US$400–700/月、R14 on-call）——第一年不該有 GPU 維運。(4) §5.1(b) W1–W2 對 8 個引擎 bake-off（含 Azure、Soniox、自架 vLLM、whisper.cpp Metal 跑 Breeze）工作量過大，W1 應只跑 3 家商用 API＋Apple 實機。(5) §4「一份正規化碼、四個產物」（XCFramework / AAR / 靜態 lib / WASM）理念正確但 W2 就要 uniffi-bindgen-swift + wasm-pack 兩條工具鏈；MVP 階段用 TS（opencc-js + pangu）在 Worker 一處實作、以共用 JSON fixture 測試防分歧即可。(6) §7.2 Pro 典型 COGS US$4.65、毛利 48–52%，是三份中最差；§7.3 定價 $10 與 MVP-first 相同但成本更高。總結：這份是「最終產品該長什麼樣」的最佳藍圖，但不是 1–2 人三個月內收到錢的執行方案。


## 應嫁接進最終方案的其他提案優點

- 【quality-first §5.1(a)/(f)】把 MVP-first 的 200 句 eval 升級成 quality-first 的黃金集 schema（id / speaker / env / ref_raw / ref_clean / tags / terms）與指標定義（簡體洩漏率＝輸出經 OpenCC t2s 後會變化的字、幻覺插入字數對靜音/噪音段、贅詞移除 P/R、注入通過率），並做成 PR gate：簡體洩漏 > 0、注入 < 100%、CER 退步 > 0.5 點就擋下；STT bake-off 每月重跑一次（供應商會換模型）。
- 【quality-first §5.1(e)】中文詞典改用拼音滑動視窗比對（無聲調拼音相似度 ≥ 0.85 且字面不同即替換），在 Worker 以 TS 的 pinyin 套件實作而非 Rust；三個注入點：DO `start` 時帶 ≤ 50 條 keyterms 給 ElevenLabs/Deepgram、LLM `<known_terms>`、確定性替換在 LLM 前後各跑一次；v1 加 AutoLearn 閉環（使用者貼上後 10 秒內的修改 diff → 每日批次送 Haiku 判定四欄 JSON → 入詞典標 ✨）。
- 【quality-first §5.1(c) / local-first §5.3(b)】OpenCC s2twp 前先把詞典條目以占位符保護再還原，避免把使用者刻意說的專有名詞或大陸用語轉掉；設定頁提供「只轉字（s2tw）不轉詞」選項；只在偵測到簡體字時才轉，避免誤轉日文漢字。
- 【quality-first §5.2 第 1、5 點】客戶端維持 0.5 s pre-roll 環形緩衝，熱鍵按下的第一毫秒送 start，DO 在上游 ready 前把 PCM 存 pending 佇列、ready 後一次沖出；v1 加 pipelined cleanup：長篇口述每收到一個 final 句就把「前文已清理版＋本句」送 LLM，放開時只剩最後一句要清，把 LLM 延遲藏進說話時間。
- 【local-first §5.4(d) / quality-first §5.4 第 4 點】iOS 的 `AudioRecordingIntent` + `ControlWidget`（Action Button / Control Center）入口從 M8 提前到 W9 或 M4：Live Activity 已經要做，多一個 intent 成本很低，卻是 4.4.1 被拒時的完整備案（鍵盤只插字、錄音全走 Action Button），也是 iPhone 15 Pro 以上使用者零 App 切換的最佳路徑。
- 【local-first §2.1 / quality-first §2.1 macOS 列】macOS 26 的 `SpeechTranscriber(zh_TW)` 經 Swift FFI（照 Handy `apple_intelligence` 的 FFI 模式）當桌機 Free 層本地 STT，從 M6 提前到 M4：Free 用戶 STT 成本歸零（MVP-first §7.3 自己算 5,000 Free MAU 每月燒 US$2,200），同時給「不信任雲端」的台灣開發者一個免費本地選項；SenseVoice / Breeze 仍留 M6。
- 【local-first §3 資料流原則 / §9 第 13 點】隱私文案分三級（全本地 / 文字上雲 / 音訊上雲）寫死在設定頁與隱私政策，明確區分「辨識在哪」與「資料存在哪」；歷史用 SQLCipher 加密落地；`/v1/stt` 與 `/v1/polish` 獨立同意、獨立計量；桌機 client 在 M6 隨本地引擎 GPL 開源讓社群驗證「音訊真的沒出去」。
- 【local-first §5.2(b)(e) / quality-first §2.1 Windows】熱鍵狀態機補上：雙擊 300 ms 內進入 hands-free 鎖定（HUD 顯示計時器、10 分鐘上限、9 分鐘警告）、按住中按其他鍵視為一般快捷鍵取消錄音、單一修飾鍵一律 HoldOrToggle 短按回放原鍵（不破壞 Right Alt+Tab）、Windows 鉤子 30 秒 watchdog 偵測被靜默移除即重裝。
- 【Windows 預設鍵，依 `_verification.md` 唯一可讀的修正】把 MVP-first §2.1 / §5.1 第 6 點的 Ctrl+Win 預設改為 Right Ctrl（local-first 與 quality-first 的選擇），並提供 Right Alt 預設組給 Typeless 遷移者；Ctrl+Win 降為備選，因為它來自被修正的 issue #119，而「Wispr Flow 預設 Ctrl+Win」本身未經查核。
- 【local-first §5.3(d)】所有路徑前置 VAD gating：短於 0.5 s 的錄音直接丟棄不送引擎、不呼叫 LLM，既防幻覺也省 STT/LLM 成本；hands-free 模式容忍 3–20 s 思考停頓。
- 【quality-first §5.1(d)】LLM 呼叫後的 `sane()` 檢查（長度膨脹 > 2×、「以下是」前綴、空輸出 → 貼確定性結果）與 `usage.cache_read_input_tokens == 0` 告警（代表 stable 區塊不足 4,096 token 或被動態內容污染），加上 Cron 每 4 分鐘預熱 cache 的做法保留。
- 【quality-first M6】香港與粵語只是 OpenCC `s2hk` 切換＋ `SpeechTranscriber zh_HK / yue_CN` 或 Scribe v2 Cantonese 的 locale 參數，加 100 句粵語 eval 集即可擴市場，排進 M6–M7 低成本擴張。
- 【quality-first §4 原則】雖然 MVP 不做 Rust atype-text，但保留「桌機看到的繁體/空格規則與後端 eval 量到的是同一段碼」的原則：Worker 的 TS 正規化碼以共用 JSON fixtures 做跨語言比對測試（Swift 鏡像 ≥ 120 條邊界案例：15%、30°、iPhone、Costco 好市多），防止 iOS 與桌機輸出分歧。
