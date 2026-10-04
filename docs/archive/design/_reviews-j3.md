# 評審 J3 原始意見

評審視角：台灣重度使用者兼產品經理（在意繁中/中英夾雜品質、延遲、隱私，以及是否真的勝過 Typeless 與 Wispr Flow）

評分維度（1–10）：feasibility_small_team、time_to_mvp、chinese_quality、cost、privacy、maintainability；total = 加總。

**勝出提案**：Atype：MVP-First 執行方案（雲端優先、最少原生碼、12 週可收費）


## Atype：MVP-First 執行方案（雲端優先、最少原生碼、12 週可收費）

| 面向 | 分數 |
|---|---|
| 小團隊可行性 | 9 |
| MVP 時程 | 9 |
| 中文品質 | 6 |
| 成本 | 5 |
| 隱私 | 5 |
| 可維護性 | 7 |
| **總分** | **41** |

【強項】§1 與 §4「薄客戶端＋胖後端、不做 UniFFI」是三份中唯一真的能讓 1–2 人在 12 週內收到錢的路徑；§5.1/§5.2 直接站在 Handy MIT 的 handy-keys、paste_tx、secure_input 上，不重造輪子；§6.1 的 W6（收費＋iOS go/no-go）與 W10 兩個停損點、§9 的不做清單是三份中最有紀律的；對 `_verification.md` 的處理最保守（文首明說所有 Typeless 數字只當錨點、STT 選型只信 W1 bake-off），沒有任何依賴被駁回主張的設計。

【不同意的地方】(1) §2.2「iOS 用 Apple SpeechTranscriber 而不是雲端 STT」：CER 7.97、無熱詞 API、中英夾雜表現未知，而 iPhone + LINE 正是台灣人最常聽寫的場景——等於在手機上 ASR 比 Typeless（雲端）還差，且 Free/Pro 都一樣。正確做法是 Apple 當 Free/離線層、Pro 走與桌機相同的 WS（quality-first §2.1 iOS 列），自己 §8 R2 也承認只要 +3 天。(2) §5.3 延遲預算 p50 ≤ 1.5 s 只是打平 Wispr Flow，沒有「擊敗感」；LLM 給 700 ms 預算太寬鬆，台灣用戶對 Typeless 最大抱怨就是延遲。(3) §5.5「詞典 MVP 只做手動、中文用子字串比對」：對中文人名/產品名幾乎無效，拼音別名比對不該排 v1。(4) §5.5 pipeline 把 OpenCC/pangu 全放在 Worker（opencc-js 授權還標 ⚠），iOS 端 `PolishClient` 逾時就直接插 raw——客戶端沒有任何確定性層兜底，簡體會漏出，與自己訂的「簡體字出現率 0 硬門檻」矛盾。(5) §5.1 第 6 點 Windows 預設 Ctrl+Win：查核已確認 Typeless 是 Right Alt，而本方案鎖定的就是 Typeless 遷移者，預設應直接是 Right Alt/Right Ctrl，而非沿用一個未經查核的 Wispr 預設。(6) §7.2/§9：本地引擎延到 M6，代價是 Free 用戶 $0.44/月 × 5,000 MAU ≈ $2,200/月的燒錢與零隱私差異化；macOS 26 的 SpeechTranscriber 走 Swift FFI 成本並不高（quality-first W2 就做到），至少 Apple 平台的 Free 本地層應提前。(7) §9 把 iOS Action Button/Control Center 入口延到 M8——它是零 App 切換、不碰 4.4.1 風險的入口，local-first §5.4(d) 把它當主入口是對的，應在 MVP。

【隱私】結構上與 Typeless/Wispr 相同（桌機音訊預設送美國供應商），只是文案誠實、不送視窗標題/URL、iOS 音訊不出裝置——對在意隱私的台灣用戶沒有可感知的差異化。

【結論】作為執行骨架最可信，但「打敗 Typeless」的部分要靠移植 quality-first 的品質層才成立。


## Atype：品質優先（Quality-first / Chinese-first）方案——以「繁中＋中英夾雜正確率」與「亞秒級延遲」打敗 Typeless 的架構與執行計畫

| 面向 | 分數 |
|---|---|
| 小團隊可行性 | 6 |
| MVP 時程 | 6 |
| 中文品質 | 9 |
| 成本 | 5 |
| 隱私 | 7 |
| 可維護性 | 6 |
| **總分** | **39** |

【強項】§5.1 五層品質保證是三份中唯一把「繁中正確率」當成可量測 KPI 的設計：黃金測試集格式（ref_raw/ref_clean/tags/terms、靜音/音樂/咳嗽幻覺段）、`atype-text` 一份 Rust 正規化碼編成 XCFramework/AAR/WASM 讓客戶端、Worker、eval 跑同一段碼、拼音相似度詞典三個注入點（STT keyterms ≤50/LLM known_terms/確定性前後各一次）、詞典條目豁免 s2twp（解決「刻意說大陸用語被改掉」）、AutoLearn 閉環、eval 當 PR CI gate 並斷言 `cache_read_input_tokens > 0`。§5.2 延遲預算 p50 0.9 s / p95 1.8 s 有逐段拆解，是唯一真正同時打敗 Typeless（3 s）與 Wispr（1.5 s）的目標。§2.2 抓到 Deepgram `language=multi` 不含中文、§9 第 10 條拒用 Alibaba 雲端 API（資料落地新加坡/北京）——這兩個判斷展現了對台灣用戶的理解。M6 的 s2hk/粵語路線是另兩份沒想到的市場。

【不同意的地方】(1) §2.2「macOS 走原生 Swift 與 iOS 共用 AtypeKit」：論證（SpeechAnalyzer/FoundationModels/AudioRecordingIntent 是 Swift-only）成立，但代價寫在 §5.3（Swift）與 §5.5（Rust）——熱鍵狀態機、收據式貼上、焦點分類、Secure Input 各實作一次，之後每個貼上 bug 都要修兩次；而開發者的強項是 TypeScript，這是三份中最吃 Swift 的方案。(2) §6.2 兩人 12 週出四平台（Android 開放測試在 W12、macOS GA + iOS App Store + Windows 公測）過度樂觀；單人版 W1–W6 要同時做 macOS 原生殼 + 後端 + eval，W2 就要本地管線貼進 TextEdit/Notes/Safari。(3) §5.1(b) 把 8 個引擎 bake-off（含自架 vLLM Qwen3-ASR-1.7B 與 WhisperKit Breeze）塞進 W1–W2，W1 根本做不完；且 GigaSpeechBench 排名寫得太像定論，而 stt-engines 主題有 2 條被駁回、內容不可讀——雖然文中說「不要在 bake-off 前決定」，但 M5 自架 Qwen3-ASR 的整條路線是建立在那個 3.95% 數字上的。(4) §1 開場引用 typeless-teardown §8（查核表 0 confirmed / 5 refuted）的「3 秒、6 分鐘上限」作論點，雖已標示來源是台灣部落格，仍是在一個全數被修正的主題上立論。(5) §7.2 Pro 典型 COGS $4.65、毛利 48–52%，比 MVP-first 還略差，重度用戶在任何組合都是負毛利；自架 GPU $400–700/月只在 >1,300 hr/月才划算，M5 就做太早。(6) §6.2 收費在 W10，比 MVP-first 晚一個月。

【隱私】Free 層全本地（Apple SpeechTranscriber / Windows SenseVoice）、拒 Alibaba、自架台灣/東京降低出境、不送視窗標題——比 MVP-first 好一截，但 Pro 預設音訊上雲，仍是「誠實版 Typeless」。

【結論】這是「產品品質」最對台灣用戶胃口的方案，但執行結構（兩套原生桌機管線）不是 1–2 人該背的；它的品質層應整個移植到 MVP-first 的骨架上。


## Atype：本地優先（Local-first）、隱私為差異化的跨平台語音聽寫產品——架構與執行方案

| 面向 | 分數 |
|---|---|
| 小團隊可行性 | 4 |
| MVP 時程 | 4 |
| 中文品質 | 5 |
| 成本 | 9 |
| 隱私 | 9 |
| 可維護性 | 5 |
| **總分** | **36** |

【強項】§3 資料流原則（實線=裝置內、虛線=明確同意）與三級 LLM/STT 同意（全本地 / 文字上雲 / 音訊上雲）是三份中最乾淨、最能通過 Apple 隱私標籤與 5.1.2(i) 的設計；§9 第 13 條「不用 on-device 做行銷卻送雲端」是對的產品信條；§5.3(b) 確定性清理 + 拼音別名詞典、§5.4(d) 把 AudioRecordingIntent/ControlWidget 當 iOS 主入口（零 App 切換、避開 4.4.1）、§5.4(b) raw 先落地 App Group 再做 LLM、SQLCipher 歷史、W7 驗收「關閉雲端時 Wireshark 抓包零外連截圖進 docs」——這些都該被採納。§7.2 Free COGS < $0.15、Pro 毛利 > 80% 是最健康的成本結構。

【不同意的地方】(1) §5.3 開頭自己承認「本地中文引擎沒有一個是為台灣訓練的」：SenseVoice 以簡體語料訓練、Apple CER 7.97 且無熱詞、Breeze-ASR-25 要 3 GB + 16 GB Apple Silicon；§5.3(c) 的 MVP 驗收門檻是 CER_zh ≤ 8%、WER_en ≤ 15%——這明顯低於 Typeless 的雲端水準。對台灣用戶「準不準」是 Day 1 第一印象，而雲端音訊要到 §6 Roadmap 的 M6 才開放給 Pro，等於前半年產品的品質天花板由簡體語料模型決定。這與「打敗 Typeless」直接衝突。(2) §1 論點把差異化押在「Typeless 已因 on-device 行銷 vs 送 AWS、上傳視窗標題、本地明文 DB 被抓包（competitors-and-oss §1.2、typeless-teardown §7）」——typeless-teardown 在查核表是 0 confirmed / 5 refuted，competitors-and-oss 也有 1 條被駁回；若被駁回的正是這些抓包主張，整個行銷故事就站不住。隱私本身仍有價值，但不該當成主論點。(3) §2.2/§4/§6 的工程量不是 1–2 人 12 週的量：Rust 核心 + UniFFI 0.32（自認「離 1.0 很遠」）+ swift-rs 橋接 SpeechAnalyzer 與 Foundation Models + sherpa-onnx Rust crate（whisper-rs/sherpa-rs 已封存，官方 crate 成熟度未知，自己也寫了 Android 靜態連結備案）+ transcribe-cpp + llama.cpp + SQLCipher + R2 模型分發含續傳/sha256。§6 W2 要 UniFFI 三平台綁定 + Kotlin 零拷貝測試、W8 一週內接 Apple Speech FFI + Apple FM FFI + Breeze + 模型管理 + 藍牙防護、W10 一週出 Android IME 含 sherpa-onnx + Tile + 16 KB 對齊、W11 一週出 iOS 主 App + Action Button + FM 清理 + 鍵盤 spike。(4) §6 MVP 定義：W12 只是 50 人 closed beta、iOS 鍵盤只做 spike、Android 內測、單人版要砍到桌機 + iOS v0——實際是桌機 beta，不是可上架的 MVP。(5) §5.5(d) 用 Apple Foundation Models（3B、≤300 token prompt、zh-TW `supportsLocale` 未驗證）做清理：對「然後/就是/對」有無實義的語意判斷，3B 模型靠不住，自己 R2 也列為高衝擊風險。(6) §8 R8（handy-keys/transcribe-cpp/transcribe-rs 單人維護）、R9（SenseVoice FunASR 授權不明）、R10（中階 Android 400–500 MB 被 OEM 殺）都是結構性風險，不是可用 vendor 進 repo 就解決的。

【結論】隱私與成本結構是三份中最好的，但 MVP 的中文品質會輸 Typeless，且工程量超出小團隊負荷；它的隱私分級、iOS 入口、本地 Free 層應作為 roadmap 移植，而非當起點。


## 應嫁接進最終方案的其他提案優點

- 【quality-first §4/§5.1(c)】`atype-text`：把 OpenCC s2twp/s2hk、pangu 空格、全形標點、口語指令、拼音別名詞典、LLM 剝殼做成一份 Rust crate，編成 XCFramework（iOS/macOS）、AAR（Android）、WASM（Worker + eval）——取代 MVP-first 只在 Worker 用 opencc-js/pangu npm 的做法，讓 iOS/桌機在 polish 逾時插 raw 時也有本地確定性層兜底，真正守住「簡體 0」硬門檻；eval 量到的和用戶看到的是同一段碼。
- 【quality-first §5.1(e)】拼音相似度詞典比對（pinyin crate + strsim，滑動視窗 ≥0.85）＋三個注入點：DO 每次 `start` 帶 ≤50 條 keyterms 給雲端 STT、LLM `<known_terms>`、確定性 `apply_dictionary` 在 LLM 前後各跑一次；詞典條目用占位符保護、豁免 s2twp 轉換；英文術語命中後還原官方大小寫（GitHub、iPhone、Costco）。MVP-first 的「子字串比對、拼音排 v1」應改為 MVP 內做。
- 【quality-first §5.2】延遲硬 KPI 與逐段預算：放開熱鍵起算 p50 ≤ 0.9 s / p95 ≤ 1.8 s（ASR 尾段 250 / LLM 550 / 後處理+貼上 60 ms），客戶端 LLM 逾時 2.0 s（非 2.5 s）；0.5 s pre-roll 環形緩衝＋熱鍵按下第一毫秒就送 `start`、上游 `ready` 前 PCM 存本地佇列再一次沖出；W3/W4 從台北量 100 次當驗收。取代 MVP-first 的 p50 ≤ 1.5 s（只打平 Wispr）。
- 【quality-first §2.1 iOS 列 / §5.4】iOS 分層：Apple `SpeechTranscriber(zh_TW)` 當 Free/離線層，Pro 走與桌機相同的 DO WebSocket 雲端串流（含 keyterms），`DictationTranscriber` 第三層；順便覆蓋 iOS 17/18。修正 MVP-first §2.2 全員 Apple-only 造成手機 ASR 輸 Typeless 的問題。
- 【quality-first §5.1(a)/(f)】黃金測試集規格：5 位台灣講者 × 40 句起、三環境（安靜/咖啡廳/藍牙耳機）、每筆含 ref_raw/ref_clean/tags/terms、30 段靜音/音樂/咳嗽量幻覺插入；指標加「英文術語大小寫正確率 ≥ 98%」與「贅詞移除 precision/recall」；eval 當 PR CI gate（簡體 >0、注入 <100%、CER 退步 >0.5 點即擋），並斷言 `usage.cache_read_input_tokens > 0` 偵測 prompt 前綴靜默失效；STT bake-off 每月重跑。
- 【quality-first §2.2】Deepgram Nova-3 `language=multi` code-switching 不含中文——中英夾雜只能靠 `zh-TW` 單語模式順便辨英文，bake-off 必須專門量這一項，不能只看普通話 CER；Alibaba `qwen3-asr-flash` 雲端 API 只用於量品質上限，正式不採用（資料落地新加坡/北京）。
- 【quality-first §2.1 Windows 列】Windows 預設 Right Ctrl 按住、設定頁預設組提供 Right Alt（查核確認的 Typeless 官方預設，給遷移者肌肉記憶）；單一修飾鍵一律 HoldOrToggle 且短按回放原鍵（不破壞 Right Alt+Tab）；取代 MVP-first 的 Ctrl+Win。
- 【quality-first §5.2 第 5 點】Pipelined cleanup（v1）：長篇口述時每收到一個 final 句就把「前文已清理版＋本句」送 LLM，放開只剩最後一句——把 LLM 延遲藏進說話時間；附前一句允許 LLM 回傳修改前一句的 diff 以處理跨句自我更正。
- 【quality-first §5.1(e) / local-first §5.3(b)】AutoLearn 閉環進 MVP 尾段或 M4（非 M6）：使用者貼上後 10 秒內或在歷史頁改字 → 累積 (original, corrected) diff → 每日批次送 Haiku 判定四欄 JSON {candidateID, learningAction, incorrectTextToReplace, correctedVocabularyTerm} → 入詞典標 ✨、可一鍵移除。
- 【local-first §3 / §9 第 13 條】三級隱私分級寫死在 UI 與隱私政策：全本地 / 文字上雲 / 音訊上雲，各自獨立同意、獨立端點（`/v1/clean` 只收文字、`/v1/stt` 獨立計量）、文案區分「辨識在哪」與「資料存在哪」；加上 W7 式驗收「關閉雲端時 Little Snitch/Wireshark 抓包零外連、截圖進 docs」——這是對 Typeless 隱私疑慮最有力的回應，且不需等本地引擎完成。
- 【local-first §5.4(d) / quality-first §5.4 第 4 點】iOS 不經鍵盤的主入口在 MVP 做（非 M8）：`AudioRecordingIntent`（必須同時啟動 Live Activity）＋ `ControlWidgetButton` 綁 Action Button / Control Center / 鎖定畫面，錄完同時寫 App Group（鍵盤可插）、放剪貼簿、Live Activity 顯示「已複製」——零 App 切換、不依賴第三方鍵盤、完全避開 4.4.1 退件風險，是 iPhone 15 Pro 以上用戶的預設推薦。
- 【local-first §2.1 macOS 列 / quality-first W2】把 macOS 26 的 `SpeechTranscriber(zh_TW)` 本地層從 M6 提前到 MVP：Swift FFI（照 Handy `apple_intelligence.swift` 的 FFI 模式）成本低，立刻給 Free 用戶「本地無限」、把 Free COGS 從 $0.44 壓到 ≈ $0.1、並讓 Apple 平台隱私標籤乾淨；Windows 的 SenseVoice 可仍留 M6。
- 【local-first §5.4(b)】Handoff 協定細節：`rawTranscript` 先落地 App Group 再做 LLM（鍵盤被殺也不丟字）、`sessionHeartbeat` 每 2 s 更新 / >6 s 視為死亡、`handoffToken` 去重；主 App 進背景即啟動 Live Activity 並在來電/Siri 中斷或閒置 5 分鐘結束，避免「8 小時幽靈 pill」；`scene(_:willConnectTo:)` 搶先讀 launch URL 避免首幀閃主畫面。
- 【local-first §5.5(c)】詞典子集選擇：對 transcript 做拼音 bigram，與每條詞典的拼音 bigram 算 Jaccard，雲端取前 50、本機取前 20，完全無重疊時不注入 `<known_terms>`——省 token 也降噪；配合 50 條注入測試集（`injection.jsonl`）每次改 prompt 必跑。
- 【local-first §5.5(d)】Apple Foundation Models 當 iOS/macOS 26 的免費本地清理層（≤300 token 濃縮版 prompt、`@Generable` 結構化輸出、`supportsLocale(zh-TW)` 執行期檢查、`exceededContextWindowSize` 時退回確定性結果）——作為配額耗盡後的降級路徑，比 MVP-first「直接降 fast 模式」體驗好；但不當主清理層。
- 【local-first §5.2(e) / §5.1(d)】Windows 鉤子 watchdog（每 30 s 檢查鉤子是否仍在、被 1000 ms 逾時靜默移除就重裝）；每次發版兩 OS 各 200 次連續貼上、剪貼簿遺失率必須為 0 的驗收標準；SQLCipher 加密本地歷史。
- 【local-first §8 R9 / §9 第 3 條】在 M6 綁定本地引擎前先讀 SenseVoice/Paraformer 的 FunASR Model License 商用分發條款；模型不打進安裝檔、由使用者從 R2 下載（只做鏡像）；備案 Qwen3-ASR（Apache-2.0）與 Breeze-ASR-25（MIT）。
- 【quality-first §6.3 M6】香港/粵語路線：`script: HongKongTraditional`（OpenCC s2hk + 香港用語表）、`SpeechTranscriber zh_HK / yue_CN`、粵語 eval 100 句——繁中市場第二大客群，另兩份完全沒想到。
