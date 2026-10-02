# Final Plan v1.0 完整性批判（Completeness Critique）

批判日期：2026-10-01。對象：`design/final-plan.md`（1,234 行）。依據：`research/` 11 份報告 + `_verification.md`（截斷）、三份方案、本機 `claude-api` skill（2026-09-25 快取）、Handy 原始碼快照（`scratchpad/Cargo.toml` 等）。

讀法：每條給 **嚴重度（高 / 中 / 低）**、**類型**（缺漏 / 錯誤 / 含糊 / 未驗證 / 矛盾 / 過時）、**證據**、**建議動作**。§6 有一張總表可直接變成 W1 工作項。

先說結論：這份計畫的骨架（薄客戶端 + DO 中繼、Handy fork、iOS 遙控器模型、確定性層包夾 LLM）是研究能支撐的，裁決紀錄也誠實。但它有 **三類會讓計畫在第一週就撞牆的問題**：(1) 幾個 CI 硬門檻與 KPI 的定義或算術本身有錯（簡體洩漏率反向、延遲預算自相矛盾、Free 配額擋不住主要成本）；(2) 被當作「現行」的 OS / API 事實已過期（iOS/macOS 27 已於 2026-09 出貨；Supabase JWT 簽章方式已換；查核檔 11 項修正中 10 項計畫根本不知道內容）；(3) 幾個「可執行」的程式片段在關鍵處是手寫的佔位（STT 供應商 WS 協定、Supabase claims、AudioRecordingIntent 的執行程序、熱鍵 chord 與吞鍵的順序），照抄會在 W2–W3 失敗。

---

## 1. 高嚴重度（會讓 KPI / CI / 成本模型或時程不成立）

### H1. 「簡體洩漏率」定義反向，且 `hasSimplified` gate 恰好排除了要修的情境 ｜ 錯誤
- **證據**：§1.5 與 §4.6 eval 表把簡體洩漏率定義為「輸出中經 **t2s** 後會變化的字數 / 總字數」。`t2s` 是繁→簡；會變化的是**繁體字**。一段完全正確的台灣正體輸出會被算成高洩漏率，CI 硬門檻「0」永遠擋或永遠失效（取決於實作怎麼算）。Quality-first §5.1 也是同一寫法，被原封搬進來。
- `hasSimplified = t2s(s) === s && s2tw(s) !== s`：純簡體 → true；純繁體 → false；**簡繁混出**（`stt-engines.md` §2.3 明寫這正是 Whisper 系與多數雲端 API 的失敗模式，例如「我们今天要去臺北」）→ `t2s(s) !== s` → gate 為 false → **不轉換，簡體字直接漏出**。gate 的設計目的（避免誤轉日文漢字）用這個布林邏輯達不到，反而把主要戰場排除。
- **建議**：(a) 指標改為「字元級簡體專有字數 / 總漢字數」：以 OpenCC `STCharacters.txt` 建立「只在簡體出現」字集（扣掉簡繁共用字如 台/后/干/面），逐字判定；(b) 轉換 gate 改為「若存在任一簡體專有字則整段 s2tw(p)」，日文漢字另以 `whatlang`/Unicode 區塊比例判斷（Handy 已這麼做：gate on effective language）；(c) 在 `eval/fixtures/normalize.json` 加入 ≥ 20 條混出案例與 ≥ 5 條日文漢字案例，W2 驗收前先通過。

### H2. 延遲 KPI 與計畫自己的 LLM 數字矛盾；「串流」對整段貼上沒有幫助 ｜ 矛盾 / 未驗證
- **證據**：§4.5 延遲預算把「LLM 清理（Haiku，cache 命中）」寫成 p50 650 ms；§5.2 LLM 表同一列卻寫「cache 命中後預期 0.8–1.3 s」，`llm-postprocess.md` §4.2 給 Haiku 的 50 字清理估計是 1.2–1.8 s（無 cache）。用 §5.2 的 0.8–1.3 s 代入 §4.5 其他項（30+80+250+5+60 ≈ 425 ms）→ p50 ≈ 1.25–1.75 s，**不滿足 KPI p50 ≤ 1.2 s**，只勉強碰到 W3 門檻 1.5 s。
- §4.5「做法」欄寫「串流」，但計畫自己在 §11 明確不做串流插入、§4.6 等 LLM 完才貼一次。對「整段文字拿到才能貼」的工作負載，串流不縮短任何體感延遲；延遲 = TTFT + 全部輸出 token 時間（60–100 token ÷ 95–150 tok/s = 0.4–1.0 s）。
- 另外 TTFT 0.6–1.0 s 來自第三方搜尋摘要（研究已標 ⚠），而 KPI 卻建立在它的樂觀端。
- **建議**：(a) 把 KPI 改成「W3 實測後定」：先寫 p50 ≤ 1.5 s / p95 ≤ 2.5 s（與 W3 門檻一致），1.2 s 標為 v1 目標；(b) 刪掉「串流」做法，改寫為「縮短輸出：`max_tokens` 緊貼輸入、prompt 要求不加任何前言」；(c) W3 A/B 的切換門檻（Haiku p50 > 1.6 s）要與 KPI 對齊，否則 Haiku 達 1.5 s 時既不切又不達標；(d) 把 Groq/Cerebras（TTFT 0.1–0.3 s）的 A/B 從「挑戰者」升為 W3 必跑。

### H3. 以 iOS / macOS 26 為「現行版本」，但 iOS 27 / macOS 27 已於 2026-09 發布 ｜ 過時
- **證據**：計畫日期 2026-10-01；Apple 每年 9 月出新版（研究中已出現「`installTap` 在 27.0 起棄用」「iOS 27 `allowedExecutionTargets`」等 27 的文件痕跡，以及「macOS 26.5.2」「iOS 26.5」等 26 後期版本）。計畫所有 spike（W1 #3、#4、#5）、`@available(macOS 26, *)`、R9「WWDC26 公告」（WWDC26 已於 2026-06 舉行）、M9「追蹤 iOS 27 allowedExecutionTargets」全部把 27 當未來。
- 影響：(1) W1 若只在 26 測，上架時主流已是 27，鍵盤 extension / Live Activity / SpeechAnalyzer locale / Foundation Models 語言任何變動都會在 W10 才被發現；(2) R9 的威脅（Apple 把 LLM 清理接進系統聽寫）是否已在 27 成真，決定整個產品的免費層價值，卻沒人查；(3) 若 27 真的開放 `allowedExecutionTargets = .main`，iOS 交接 UX 可能整個改寫，應在 W1 而非 M9 驗證。
- **建議**：W1 spike 以「27（現行）+ 26（N-1）」雙版本跑；Day 1 先讀 WWDC26 的 Speech / AppIntents / Keyboard / Foundation Models session 清單與 iOS 27 release notes；把 M9 的追蹤項搬到 W1 結論文件第 9 條；`minimumSystemVersion` 與 `@available` 以 26 為下限、27 為測試主線。同理 Android 17（2026 年中發布）對 IME / 麥克風 / FGS 的行為變更未研究。

### H4. 查核檔截斷：11 項 REFUTED/CORRECTED 中有 10 項內容未知，計畫卻直接引用那些研究 ｜ 未驗證
- **證據**：`_verification.md` 摘要表：typeless-teardown 5、competitors 1、stt-engines 2、llm-postprocess 1、ios-keyboard 1、android-ime 1 項被修正；檔案在第二項修正中途截斷。計畫（文首、R19）只承認「唯一完整可讀的修正是 Windows 預設鍵」，但沒有列出其他 10 項可能打到哪些主張。另外摘要表寫 UNCERTAIN = 0，而唯一可讀的那條內文結論卻是「Verdict: uncertain」——查核檔本身不自洽。
- 依各主題內容推斷**最可能被修正、且計畫有依賴**的主張：
  - stt-engines（2）：Deepgram Nova-3 zh-TW 於 2026-03-31 新增；ElevenLabs Scribe v2 的 GigaSpeechBench 數字 / 繁體輸出；Apple `SpeechTranscriber` locale 數（stt-engines 寫 42 個、ios-keyboard 寫 30 個，**兩份研究互相矛盾**，計畫引 30）。
  - llm-postprocess（1）：Groq Llama 下架日、Gemini 2.5 Flash-Lite 2026-10-16 關閉、Apple Foundation Models 支援繁中、Haiku TTFT。
  - ios-keyboard（1）：「App Group 讀取不需 Full Access」（計畫 A6 已列 spike）、「iOS 26.4 封私有 API」、30 locale 清單。
  - android-ime（1）：16 KB 強制日期（研究寫 2027-02-01；Google 2025 年公告的日期是 **2025-11-01** 起對 targetSdk 35+ 新上架/更新強制，兩者衝突）、targetSdk 36 期限、Gemini Nano 語言。
  - competitors（1）：Handy v0.9.7 發布日（competitors 寫 2026-09-18、desktop-macos 寫 commit 29bd2c0 於 2026-09-28、計畫寫「v0.9.7（2026-09-28）」——三者不一致，且 subtree 指令釘的是 commit 而非 tag）。
  - typeless-teardown（5，0 confirmed）：所有 Typeless 數字（免費額度、6 分鐘、3 秒、iOS 機制、熱鍵）。計畫說只當行銷錨點，但 §1.2 目標使用者 #2 與 §1.4 差異化表把它們寫成產品訊息（見 M15）。
- **建議**：W1 Day 1 以可上網的環境重跑 `_verification.md`（至少補完 11 條原文），把每條映射到計畫段落；在那之前，§1.4 表全部標 ⚠ 並禁止進入落地頁文案。

### H5. Free 配額耗盡只「降快速模式」，但快速模式仍走雲端 STT，而 STT 才是 Free 成本的 2/3 ｜ 錯誤 / 矛盾
- **證據**：§8.2：Free COGS $0.44 = STT $0.28 + LLM $0.11 + 攤提 $0.05。§8.3 / W6 / R5 的緩解都是「1,500 字/週耗盡 → 降快速模式」；§4.6 快速模式 = `mode: "fast"` 不呼叫 LLM，**STT 照常走 ElevenLabs/Deepgram**。所以配額只關掉 $0.11 的那部分，$0.28 的 STT 對 Free 用戶無上限；R5「Free 燒錢」的緩解實際失效。M4 以前 Windows / Android / iOS<26 用戶沒有本地 STT 可退。
- **建議**：Free 配額改以「雲端 STT 秒數 + LLM 次數」雙計量，耗盡後**雲端 STT 也關閉**（Apple 平台退本地 `SpeechTranscriber`，其他平台顯示「本週雲端額度已用完」並保留 History / 詞典）；或把 Free 的雲端 STT 改成批次最便宜供應商（研究 §6：Groq $0.04/hr，但簡繁問題要靠 H1 修好的 OpenCC 兜）。同時修正 §8.2 把「耗盡後」的 STT 成本算進 Free 行。

### H6. 熱鍵設計在三個地方與「純修飾鍵當熱鍵」的現實衝突 ｜ 錯誤 / 缺漏
1. **每次 Down 就送 `start` 並開上游 STT**（§2.2、§2.5、§4.5 客戶端說明）。macOS 的 Fn 是 Fn+Delete（前向刪除）、Fn+方向鍵（Home/End/PgUp/PgDn）、Fn+F 鍵的前綴，台灣筆電用戶每天按幾十次；Windows 的 Right Ctrl + C/V/方向鍵同理。每一次 chord 都會開一條上游 WebSocket 再在 1.0 s 內取消 → 供應商連線 churn、並發上限（見 H7）、以及可能的最小計費。
   - **建議**：Down 後延遲 150–200 ms 且 1.0 s chord 視窗內無其他鍵才開上游（pre-roll 環已經接住前 0.5 s 音訊，體感不變）；或 Down 立即只做「本機錄音 + pending 佇列」，上游在第一個 PCM frame 且 150 ms 後才開。
2. **Windows `ll_proc` 無條件吞掉 Right Ctrl 的 Down**，之後若 1.0 s 內來了 C，就「視為一般快捷鍵，短按回放原鍵」——但 Down 已經被吞，目標程式收到的是沒有 Ctrl 修飾的 `c`；要「回放」只能在 C 到達時合成 Ctrl↓C↑Ctrl↑，而這時原始 `c` 已經送出（或必須把 Right Ctrl 按住期間的所有鍵都延遲/緩衝 1 秒）。計畫沒有處理這個時序。
   - **建議**：Right Ctrl **不要吞**（單獨按下/放開 Ctrl 在 Windows 沒有副作用），只觀察 up/down；只有 Right Alt（單按放開會把焦點移到 Win32 功能表列，Explorer/Office/Chrome 都會閃）才需要在 Up 前注入一個「無害鍵」（AutoHotkey 的 `{Blind}` 技巧）或吞掉 Up。**計畫的 Right Alt「Typeless 遷移」預設組完全沒提到功能表列問題**，會成為第一批 Windows 工單。另外 VirtualBox 預設 host key 就是 Right Ctrl、VMware/Hyper-V 也常用 Right Ctrl，目標客群（軟體工程師）撞擊機率高——onboarding 要偵測。
3. **macOS 🌐/Fn 單按是台灣用戶切換注音/英文的日常手勢**（`AppleFnUsageType = 1` 是雙輸入法用戶常見設定，研究 desktop-macos §3.4 有列），計畫只處理 `= 3`（聽寫）。而 §4.2(a) 的 HoldOrToggle 把「Up < 300 ms」當 tap-to-toggle 並用 `.defaultTap` 吞掉 Fn → 使用者再也不能用 🌐 切輸入法。
   - **建議**：Fn 模式下 tap（< 300 ms）**放行給系統**、只有 hold 觸發；toggle/免持改由雙擊或 Fn+Space；onboarding 讀到 `AppleFnUsageType` 為 1/2 時說明會發生什麼並建議 Right Option；研究已指出 Caps Lock 在 macOS zh-TW 預設是切換輸入法鍵，也別拿來當熱鍵。
4. `LLKHF_INJECTED` 過濾會把 **RDP、AutoHotkey、PowerToys** 等所有注入事件一律忽略；RDP 在相容矩陣裡，透過 RDP 使用時熱鍵會整個失效。
   - **建議**：只以 `dwExtraInfo == OUR_MARKER` 過濾自家事件，不用 `LLKHF_INJECTED`。

### H7. STT 供應商的即時 WS 協定、並發上限、速率限制完全沒研究，W2 驗收「wscat 收到 partial/final」不可執行 ｜ 缺漏
- **證據**：`stt-engines.md` 只有價格與 CER 表；`backend-architecture.md` §2.4 自承 Deepgram/OpenAI 文件被封鎖；ElevenLabs Scribe v2 Realtime 的 WS URL、驗證 header、`audio_format`/取樣率、commit/finalize 訊息、partial 與 final 的事件形狀、keyterm 參數、session 最長時間，一條都沒有。計畫的 `openUpstream()` / `finalizeUpstream()` 是空殼。
- **並發**：ElevenLabs 依方案有 realtime 並發上限（創作者/專業方案通常是個位數到十幾條），Deepgram 付費即用也有預設並發；公測首週目標 ≥ 200 下載、台灣上班時段尖峰同時聽寫數可能破 10 → 上游 429。Anthropic 新 org 從 Tier 1 起跳（RPM 僅數十），1,000 名 Pro 用戶 × 50 次/天的尖峰會撞 RPM；cache 讀不計 ITPM 是好消息（skill `prompt-caching.md`），但 RPM 仍要靠預付提升 Tier。這些都不在 R 列。
- **建議**：W1 bake-off 同時產出一份「協定對照表」（三家 WS 訊息 JSON、鑑權、取樣率、keyterm、finalize、session 上限、並發/速率上限、計費最小單位）；Day 1 向 ElevenLabs/Deepgram 詢問並發上限與企業方案門檻，向 Anthropic 預付以到 Tier 2+；DO 加「上游 429 → 立即切第二供應商」路徑；R 列新增 R20「供應商並發/速率上限」。

### H8. 一人 12 週交付 macOS 1.0 + iOS App Store + Windows 公測 + 後端 + 收款 + eval，不可信；W1 工作量尤其不實際 ｜ 含糊
- **證據**：§7 人力假設「1 人為主；2 人時 B 從 W4 起接 iOS」，但 12 週表是以 iOS 一定發生來寫的（W7–W9 SwiftUI App + 鍵盤 + Live Activity + AudioRecordingIntent + StoreKit + RevenueCat + 兩份 PrivacyInfo + TestFlight，3 週，同時 W6 起 macOS 公測的支援工單也落在同一人身上）。W1 要同時完成：repo + 簽章公證 CI、**5 位講者 × 40 句 × 3 環境 = 600 段錄音 + ref_raw/ref_clean 標註**、三家 STT bake-off、iOS 真機 7 項 spike、macOS 26 tap spike、Trusted Signing 試開、兩家 KYC、商標自查、授權確認。
- **建議**：寫兩個版本的時程：「1 人版」= 12 週只做 macOS 1.0 + 後端 + Paddle（iOS 延到 M4，Windows 公測 W12 用 Handy 既有 Windows 建置最小改）；「2 人版」才是現在這張表。W1 的黃金集縮到 2 位講者 × 40 句（160 段）、W4 前擴到 5 位；ref_clean 要先寫一頁標註規範（贅詞/自我更正/數字/標點規則與 §4.6 prompt 一致），否則 eval 在量 prompt 與標註者的分歧。

---

## 2. 中嚴重度（會造成明顯返工、成本偏差或上架風險）

### M1. 熱鍵狀態機三處自相矛盾 ｜ 矛盾
- §2.2 Mermaid：`Arming --> Idle: Up < 300 ms 且無錄音 → toggle 判定`（讀起來是丟棄回 Idle）；§4.2(a)：`Up < 300 ms → Toggle（tap-speak-tap）`（進入免持錄音）；`product-ux.md` §13.1：`hotkey up < 300ms (no audio, discard)`。
- §4.2(a)：tap 已經是免持；「300 ms 內第二次 Down → Locked」與「錄音中則停止」同時成立 → 第二次 tap 到底是停止還是鎖定？
- **建議**：只保留一套：hold（≥ 300 ms）= PTT；tap = toggle on，再 tap = toggle off；刪掉「雙擊鎖定」（它是 Wispr 給純 hold 模式的補丁，與 HoldOrToggle 重複）；< 0.5 s 丟棄只套用在 PTT 放開。把最終狀態機以單元測試（Blurt 的 tap/hold/combo 測試是 MIT 範本）固定下來。

### M2. 客戶端 2.0 s 逾時與 DO 端 2.0 s LLM 逾時起點不同，晚到的 `cleaned` 會二次貼上；DO 並發狀態被覆蓋 ｜ 錯誤
- 客戶端：`stop` 後 2.0 s 未收到 `cleaned` → 貼 `final`。DO：`stop` → 等 STT finalize（250–450 ms）→ `polish(timeoutMs: 2000)`。最壞情況 `cleaned` 在 2.4 s 到達，客戶端已貼了 `final`；計畫沒說收到晚到 `cleaned` 怎麼辦（丟棄？替換？會不會再 `deliver()`？）。
- DO 的 `webSocketMessage` 在 `await polish()` 期間，input gate 不會擋 WebSocket 事件（只擋 storage 操作），使用者「無冷卻連續聽寫」（research product-ux §4）時第二個 `start` 會覆寫 `this.t0 / this.cfg / this.raw / this.pending`，第一段的 `ms`、`recordUsage` 與 `pending` 沖出都會錯。
- **建議**：`stop` 帶 `deadline_ms`（客戶端絕對期限），DO 以 `deadline − now − 50ms` 當 LLM 逾時；客戶端一旦貼了 `final` 就把後到的 `cleaned` 只寫 History（HUD 顯示「有整理版，按 ⌘⇧V 替換」）；DO 以「每段聽寫一個物件 `{id, t0, cfg, pending, upstream}`」而非實例欄位，訊息帶 `dictation_id`。

### M3. Anthropic SDK / cache 細節：五個會在 W2–W3 咬人的點 ｜ 錯誤 / 缺漏（已對照本機 `claude-api` skill）
1. **`maxRetries` 預設 2**：TS SDK 對 408/409/429/5xx 與連線錯誤自動重試，`timeout: 2000` 的最壞 wall-clock 是 6 s；熱路徑要明寫 `maxRetries: 0`（A/B 的 Gemini/Groq client 同理）。
2. **`temperature` 未設**：Haiku 4.5 允許設定；文字濾鏡任務 + 以 0.5 點 CER 當 PR gate，預設 temperature 1.0 會讓同一輸入在兩次 CI 跑出不同結果 → 門檻雜訊。Haiku 設 `temperature: 0`；Sonnet 5.5 非預設 temperature 會 400（skill），編輯模式只能靠 effort。
3. **`fallbacks: "default"` 只重試 `cyber` / `frontier_llm` 類 refusal**，不重試 `bio` / `reasoning_extraction` / `general_harms`（後者「benign work 也會觸發」）；計畫寫「處理安全分類器 refusal」是過度承諾。計畫的最後防線（貼確定性結果）正確，但 HUD 要能顯示「AI 整理未完成」而不是靜默。
4. **Cache 每個 workspace 隔離**（skill §API reference）：Cron 預熱 Worker 與 `/v1/polish` 必須用同一把 key / 同一 workspace，否則預熱永遠打不到。
5. **預熱成本算錯**：4,100 token × $1.25/M = $0.0051/次寫入；`*/4 * * * *` = 360 次/天 ≈ **$55/月**，不是「只付一次寫入」。skill 的建議是：流量稀疏時改 `cache_control: {ttl: "1h"}`（寫入 2× = $0.0082）每小時預熱一次 ≈ **$6/月**，命中後讀價相同。另外 §8.2 的「Haiku cache 每次 ≈ $0.00098」漏算 breakpoint 之後的可變區（`<task>`+`<known_terms>` 100–300 token 全價）與每次 miss 的寫入；實際約 $0.0012–0.0013。
- 其餘對照結果（確認無誤）：`max_tokens: 0` 預熱是官方做法（skill `prompt-caching.md` § Pre-warming，拒絕條件與 A5 所列一致）；Haiku 4.5 最小可 cache 4,096 token、cache 讀 $0.10/M；Sonnet 5.5 用 `thinking: {type: "between_tools"}`（effort ≤ high）、Opus 5.5 不可關 thinking；server-side fallback 遇 `between_tools` 會在 fallback 模型上改以 disabled 執行，與計畫相容。

### M4. Supabase 認證細節過時 / 缺漏 ｜ 過時 / 缺漏
- `npx wrangler secret put SUPABASE_JWT_SECRET` 假設 HS256 共用密鑰。Supabase 自 2025 起新專案預設改用**非對稱 JWT 簽章金鑰**（ECC/RSA，透過 `/auth/v1/.well-known/jwks.json` 驗證），舊的 legacy JWT secret 走淘汰流程；Worker 應以 `jose` + JWKS 驗證並快取 kid。
- JWT claims `plan` / `quota_words_week`：Supabase access token 預設不含自訂 claims，要用 **Custom Access Token Auth Hook**（Postgres 函式）注入，或由 Worker 驗完 Supabase token 後自簽短效 JWT。計畫兩者都沒寫，W2「JWT 驗證」與 W6「JWT 帶 plan」不可執行。
- Magic link 依賴 Supabase 內建 SMTP，免費層每小時只有個位數信件配額，公測第一天就會卡；需自備 SMTP（Resend/SES）。
- 「桌機首次 20 次免登入」的配額如何綁定（Supabase anonymous sign-in + machine id 升級為正式帳號？）未定義。
- **建議**：W2 改為「JWKS 驗證 + auth hook 注入 claims + 自備 SMTP + anonymous auth 升級流程」四項，各一行驗收。

### M5. Workers 執行環境限制未評估：opencc-js + pinyin-pro + pangu 的 bundle 大小與啟動時間 ｜ 缺漏
- opencc-js 含全部字典約數 MB、pinyin-pro 約 1–2 MB；Workers 有腳本大小（壓縮後）與啟動 CPU 時間上限，字典若在模組載入時展開可能超過啟動限制或拖慢冷啟動（每個 DO/Worker 隔離體都要載一次）。研究沒有任何一份評估過 Worker 內跑 OpenCC。
- **建議**：W2 第一件事量 `wrangler deploy` 的 bundle 大小與冷啟動；必要時只打包 `s2tw`/`s2twp`/`t2s` 三組字典、延遲載入、或把確定性層放到客戶端 Rust（`ferrous-opencc` 已在 Handy Cargo.toml）——這會動搖 A10「Worker TS 為真相」的裁決，應早決定。

### M6. iOS 四個技術點寫錯或未覆蓋 ｜ 錯誤 / 缺漏
1. `StartDictationIntent: AudioRecordingIntent` 放在 `AtypeWidgets/` target 並直接呼叫 `DictationSession.shared.startFromIntent()`。Widget extension 是獨立程序，沒有主 App 的 `DictationSession`，也不能錄音；`AudioRecordingIntent` 的語意是系統在背景啟動 **App** 執行 `perform()`，所以 intent 必須定義在 App target（widget 只引用）。照目前目錄結構寫會在 W7 編譯過但執行失敗。
2. Dictus 一手實證「iOS forbids changing AVAudioSession category from background」且 `AVAudioEngine.start()` 不能在非 active 狀態；Action Button 路徑正是「App 從未在前景、由 intent 在背景啟動」。計畫 W1 spike #5 只驗「綁 Action Button → Live Activity 啟動」，沒驗「App 冷啟動於背景時能否真的開始擷取音訊」。這是 4.4.1 退件備案的成立條件，必須納入 spike。
3. **iOS < 26 的 Free 用戶沒有任何 STT**：Free = `SpeechTranscriber`（26+）、第三層 `DictationTranscriber` 也是 26+，Pro 才走雲端。TL;DR 說「順便覆蓋 iOS 17/18」只對 Pro 成立。要嘛 iOS < 26 的 Free 走雲端配額（成本回來），要嘛用 `SFSpeechRecognizer` 裝置端（zh-TW 是否 `supportsOnDeviceRecognition`、1 分鐘上限）——需決定並寫進分層表。
4. `SpeechTranscriber.supportedLocales` 數量兩份研究矛盾（30 vs 42），且清單來自 macOS 26.5.2；iOS 27 實機清單應是 W1 的第一個輸出。

### M7. 「全本地」隱私層沒有清理層，與產品一句話承諾衝突；桌機本地清理的現成選項被忽略 ｜ 矛盾 / 缺漏
- §9 三級隱私：① 全本地（M4 起 Apple 平台 Free；iOS Free 一開始就是）。但 §4.7 iOS Free 流程是 `/v1/polish`（文字上雲），§8.2「MVP iOS Free（Apple + Haiku cache）≈ $0.16」也假設每次都呼叫 Haiku——那 iOS Free 到底是 ① 還是 ②？若是 ①（純本地），輸出只有 Apple raw + Swift 鏡像的確定性層，沒有贅詞/自我更正/條列處理，「可以直接送出的繁體中文」對 Free 不成立；若是 ②，「音訊不出裝置」仍對但「全本地」錯，而且 Free 的 LLM 次數是否受 1,500 字/週限制未說。
- Handy 已有 MIT 的 `apple_intelligence.swift`（Foundation Models `@Generable` 清理），`llm-postprocess.md` §4.4 有完整分析（4,096 context、≤ 300 token prompt、zh-TW 需 `supportsLocale` 實測）。計畫把 Apple FM 推到 M8 且只給 iOS「配額耗盡降級」，macOS 本地層（M4）完全沒有清理。一個真正零外連的 macOS 26+/Apple Silicon 「全本地」層在 M4 是可達的，且是對「不信任雲端的台灣開發者」（§1.2 #3）唯一誠實的賣點。
- **建議**：明確定義 ①＝本地 STT + 本地清理（Apple FM，可用時）/ 確定性層（不可用時）；iOS Free 歸 ②並說明 LLM 次數計量；M4 的 Swift FFI 一次把 `SpeechTranscriber` 與 Foundation Models 都橋進來（同一個 `@_cdecl` 檔）。

### M8. 拼音滑窗詞典：演算法未定義、無最小長度、無誤替換率 ｜ 含糊
- `similarity(key(win), tk) >= 0.85`：`similarity` 是哪個（Levenshtein ratio / Jaro-Winkler / 音節級編輯距離）未指定；對 2 字詞，拼音字串長度 ~8–12 字元，0.85 門檻等於允許 1 個字元差 → 「cheng qing」會吃掉所有「成/城/程 + 慶/情/清」組合；對 len = n−1 的單字視窗則幾乎永遠不命中。常見 2 字詞（小米、老師、公司）進詞典後會把所有同音/近音詞全部改掉，且在 LLM 前後各跑一次、`applyDictionary` 在 LLM 之後再跑會把 LLM 已正確判斷的詞也覆蓋。
- W4 驗收只有命中率（20 案例 ≥ 18），沒有誤替換率。
- **建議**：指定「無聲調拼音的音節級比對，≤ 2 字詞要求完全相等、≥ 3 字詞允許 1 音節差」；只對 `starred` 或使用者手動加的詞做 LLM 後的二次替換；eval 加 50 句「含同音非目標詞」的負樣本，誤替換率 ≤ 1% 當 gate；詞典條目數上限與 O(terms × windows) 的 Worker CPU 時間要量。

### M9. Accessibility 活性探針「每次 deliver() 前建一個 tap」與 Handy #1827 是同類 WindowServer RPC 風險 ｜ 未驗證
- #1827 的教訓是「反覆對 WindowServer 做 RPC（輪詢 `CGEventTapIsEnabled`）洩漏 IPC voucher 導致 kernel panic」。每次貼上前 `tap_create`+`tap_enable(false)`+drop，以及 Broken 狀態每 1 s 重試，都是高頻 WindowServer RPC；A4 的裁決只解決了「授權域一致」沒解決頻率。
- **建議**：以 handy-keys 既有 tap 的「最近一次 callback 時間 + 是否收到 TapDisabled 偽事件」當活性訊號；探針只在啟動、權限頁、以及貼上失敗後各做一次；Broken 狀態重試退避到 5–10 s；W1 spike 加「連續 1,000 次探針不 panic」。

### M10. Windows 注入兩個細節 ｜ 缺漏
- 注音組字中（`ImmGetCompositionString` 非空）直接貼上，會把文字塞進組字緩衝或被 IME 吃掉；應先 `ImmNotifyIME(hIMC, NI_COMPOSITIONSTR, CPS_COMPLETE, 0)` 完成組字再貼。macOS 端的 marked text（注音輸入中）同樣未處理。
- `ExcludeClipboardContentFromMonitorProcessing` 效果研究標 ⚠ 未驗證；Win+V 歷史會收錄每一段聽寫（隱私）。W10 要實測。

### M11. 麥克風暖機 / 藍牙喚醒延遲與「常駐麥克風」的隱私觀感未處理 ｜ 缺漏 / 矛盾
- `desktop-macos.md` §4 與 `product-ux.md` §3.2：macOS 麥克風閒置斷電後首次啟動要 2–5 s 才有樣本、藍牙 SCO 再加 1–3 s；這段會完全吃掉 1.2 s 的延遲預算，而且發生在「第一句」——使用者印象最深的一次。計畫的 0.5 s pre-roll 環形緩衝隱含「麥克風常開」，但沒寫這會讓 macOS 橘點 / Windows 麥克風圖示常亮，對一個以隱私行銷的產品是負面；也沒寫可關。
- **建議**：pre-roll / 暖機做成 opt-in 並在設定頁說明指示燈；預設改「熱鍵 Down 即開麥克風 + 上游 ready 前 pending 佇列」；W3 延遲量測分「首次聽寫」與「連續聽寫」兩組。

### M12. 執行細節缺件（照打會失敗） ｜ 缺漏
- `wrangler.toml` 片段缺 `[[migrations]] tag="v1" new_sqlite_classes=["DictationSession"]`，沒有它 DO 不會部署，SQLite 計量也不會啟用。
- secrets 清單缺 `SUPABASE_SERVICE_ROLE_KEY`（DO 批次 upsert Postgres 需要）、`PADDLE_WEBHOOK_SECRET`、`REVENUECAT_WEBHOOK_SECRET`。
- `git subtree add ... --squash` 之後「每月 rebase 上游」應是 `git subtree pull --squash`；rebase 會打爆 squash 歷史。
- Handy 實際是 `tauri = "2.11.5"`、`tauri-nspanel` 走 git branch `v2.1`、`tauri-specta = "=2.0.0-rc.21"`；計畫「鎖 2.12.x」是一次升級而非鎖定，相容性要在 Day 1–2 的 `npm run tauri dev` 驗證，否則 W1 就卡在建置。
- `rusqlite` 的 `bundled-sqlcipher` 需要 OpenSSL 或 `bundled-sqlcipher-vendored-openssl`，Windows 交叉建置要選後者；未提。

### M13. 金鑰與授權存放未定義 ｜ 缺漏
- SQLCipher 的金鑰放哪（macOS Keychain / Windows DPAPI / Linux secret service）？若與 DB 同目錄，加密只是裝飾。
- 桌機 JWT / refresh token 存放（Keychain vs `tauri-plugin-store` 明文）。
- Pro Lifetime（M6）是桌機本地版，離線授權驗證（Ed25519 簽章的 license、Keygen 或自簽）研究有、計畫無。

### M14. 三位評審（J1–J3）的原始意見不在 scratchpad，§0b 裁決無法稽核 ｜ 缺漏
- `grep` 整個 scratchpad 找不到任何評審檔；§0b 的「J2：Messages API 要求 ≥ 1」之類引述無法對照。
- **建議**：把評審原文存成 `design/_reviews-{j1,j2,j3}.md` 並在 §0b 加連結。

### M15. 比較廣告的法律風險：以未查核的競品數字寫落地頁 ｜ 缺漏
- §1.4 把「Typeless 約 3 s / 6 分鐘 / 8,000→2,000 字」「Wispr 設定繁體仍出簡體」寫成差異化表，W12 行銷「實測文（繁中準確率 vs 內建聽寫）」。typeless-teardown 是 0 confirmed / 5 refuted。台灣《公平交易法》第 21 條（不實廣告）與第 24 條（損害營業信譽）對比較廣告要求有據；數字錯了會收到律師函。
- **建議**：對外文案只用自家可重現的量測（公開 eval 集 + 方法）；競品數字在 W1 #7 核對並留存截圖前不上線。

### M16. 黃金集與 eval gate 的方法學 ｜ 含糊
- 「注入通過率 100%」對 20 句、temperature 未鎖的 LLM 當 PR gate 會 flaky（見 M3-2）；「CER 退步 > 0.5 點」在 200 句（約 4,000 字）等於 20 個字錯，LLM 隨機性就能超過。
- 錄音 5 位講者的個資同意書、音檔授權（R2 上的音檔是個資）、ref_clean 標註規範、標註者一致性（至少雙標 50 句算 agreement）都沒有。
- **建議**：LLM 層 eval 固定用 `ref_raw` 文字輸入（不重跑 STT）、temperature 0、每個 PR 跑 3 次取中位數；注入集擴到 50 句（計畫 §6 寫 50 條、§4.6 寫 20 句，自相矛盾）並以「≥ 98%，且 0 句執行指令」為門檻；STT 層 eval 另跑（每月）。

---

## 3. 低嚴重度 / 待驗證（記錄即可）

- **L1 Android `MicPermissionActivity` 觸發時機**：§4.4 註解寫「只在使用者點擊後啟動」，程式碼卻在 `onStartInputView` 無權限時直接 `startActivity`——IME 一顯示就跳權限頁，Android 15 對非可見視窗的背景啟動限制可能擋下，且 UX 差。改為面板上的麥克風鍵 onClick 才啟動。
- **L2 16 KB 強制日期**：研究寫 2027-02-01，Google 2025 公告為 2025-11-01（targetSdk 35+ 新上架/更新）。新專案直接對齊即可，但 §4.4 的「2027-02-01 強制」要改。
- **L3 Lemon Squeezy 備案**：被 Stripe 收購後是否仍接受新賣家，研究已標 ⚠；Day 1 同時送 Polar / Creem 的 KYC 才是真備案。Stripe 台灣現況同樣要查（若已開放，MoR 5% 可省）。
- **L4 Apple 登入在桌機**：Tauri 走 web OAuth（Services ID + .p8），6 個月換 secret 的義務對桌機仍適用；計畫把「免換 secret」寫成通用好處。
- **L5 「字」的定義**：中文字 = 1、英文 word = 1？混排怎麼算？影響配額、公平使用與行銷「1,500 字/週」；DO `countWords` 要有規格與單元測試。
- **L6 音訊「永不落地」**：`product-ux.md` §5 建議供應商失敗時保留音訊可重試；研究的設定 schema 有 `keep_audio_days`。計畫應區分「伺服器端永不落地」與「本機可選暫存 N 分鐘供重試」。
- **L7 暫停媒體**：W5「錄音暫停媒體（可選）」若照 VoiceInk 用 MediaRemote 私有框架，macOS 26/27 可能失效；研究建議 CoreAudio mute 備案，計畫未選。
- **L8 CI 成本**：私有 repo macOS 分鐘 $600–1,200/年可用自家 Mac 當 self-hosted runner 歸零；計畫未提。
- **L9 `SpeechTranscriber` 資產首次下載**：數百 MB，onboarding 應在 Wi-Fi 預載；`recordUsage` 的 seconds 從熱鍵 Down 算到 LLM 回來，會多計 1–2 s/次。
- **L10 Haiku 4.5 的 `stop_reason === "refusal"`**：Haiku 4.5 沒有即時安全分類器（skill：這類安全措施「對來自 Haiku 4.5 的程式碼是新的」），分支無害但不會觸發；Sonnet 5.5 才會。
- **L11 Handy 版本/日期不一致**：見 H4；subtree 指令改釘 tag `v0.9.7` 的 commit 並在註解寫日期來源。
- **L12 pangu 在 code 模式**：commit message / 程式註解不應加盤古之白；`postClean` 的 `p.pangu !== false` 預設開啟，app_hint = code 時應關。
- **L13 無障礙**：`product-ux.md` §11 的 VoiceOver/NVDA 狀態公告、減少動態、純音效回饋都沒進計畫。
- **L14 iOS Opus**：Pro 在 4G 上傳 PCM16 256 kbps；研究建議手機 v2 走 Opus，計畫未列入 roadmap。

---

## 4. 研究完全未涵蓋、而計畫需要的主題

1. STT 供應商即時 WS 協定、並發/速率上限、session 上限、計費最小單位（H7）。
2. Anthropic 速率限制 Tier 與預付升級（H7）。
3. Cloudflare Workers 腳本大小 / 啟動時間對 opencc-js + pinyin-pro 的影響（M5）。
4. Supabase 非對稱 JWT / JWKS、Custom Access Token Hook、SMTP 配額、anonymous auth（M4）。
5. Windows：Right Alt 單按啟動功能表列、Right Ctrl 與虛擬機 host key 衝突、RDP 下 `LLKHF_INJECTED`（H6）。
6. macOS：`AppleFnUsageType = 1/2`（台灣雙輸入法用戶）與 tap 手勢衝突、Caps Lock 在 zh-TW 的預設角色（H6）。
7. iOS/macOS 27 的變動：Speech / AppIntents / 鍵盤 / Foundation Models 語言、`allowedExecutionTargets`（H3）。
8. 麥克風暖機、藍牙 SCO 喚醒延遲、常駐麥克風指示燈（M11）。
9. 法律：比較廣告（公平交易法）、語料錄音同意書與音檔個資、EULA 對 AI 輸出的免責（M15/M16）。
10. 金鑰管理：SQLCipher 金鑰、桌機 token 存放、離線授權（M13）。
11. 本地清理：macOS Apple Foundation Models 可行性（研究有素材，計畫未採）（M7）。
12. Android 17 行為變更；Gboard 2026 版是否開放第三方語音（研究 #1 未解，計畫未列 spike）。
13. 字數/配額定義與中英混排計量（L5）。

---

## 5. 建議立即修改的計畫段落（可直接動手）

| 段落 | 修改 |
|---|---|
| §1.5 KPI、§4.6 eval 表 | 簡體洩漏率改為「簡體專有字數 / 漢字數」，附字集來源；延遲 KPI 改 1.5/2.5（W3）→ 1.2/2.2（v1 目標） |
| §4.6 `preClean` | 重寫 `hasSimplified`（字元級）+ 日文漢字判斷；`applyDictionary` 指定演算法與最小長度；`postClean` 在 code 模式關 pangu |
| §4.6 `cleanWithClaude` | 加 `maxRetries: 0`、`temperature: 0`；註解改為「fallbacks 只覆蓋 cyber/frontier_llm」 |
| §4.6 預熱 / §8.1 | 改 `ttl: "1h"` + 每小時 Cron，預熱成本 ≈ $6/月列入固定成本；標註 cache 每 workspace 隔離 |
| §2.2 / §4.2(a) | 統一狀態機：hold = PTT、tap = toggle、刪雙擊鎖定；Fn 模式 tap 放行；Down 後 150–200 ms 且無 chord 才開上游 |
| §4.2(f) | Right Ctrl 不吞；Right Alt 加功能表列抑制；`dwExtraInfo` 取代 `LLKHF_INJECTED`；偵測 VirtualBox/VMware host key |
| §4.2(c) | 探針只在啟動 / 權限頁 / 貼上失敗後；用既有 tap 活性 |
| §4.3(d) | `StartDictationIntent` 移到 App target；spike 加「背景冷啟動能否開始擷取」 |
| §4.3 / §4.7 | iOS < 26 Free 路線（SFSpeechRecognizer 或雲端配額）寫明 |
| §4.5 DO / 客戶端 | `dictation_id` + `deadline_ms`；晚到 `cleaned` 只寫 History；每段聽寫獨立物件 |
| §4.5 延遲表 | LLM 列改 0.8–1.3 s、刪「串流」做法 |
| §8.2 / §8.3 / R5 | Free 配額同時關雲端 STT；COGS 補算配額耗盡後 STT |
| §9 隱私三級 | ① 定義含本地清理；iOS Free 歸 ②並寫 LLM 計量 |
| §12 Day 1 | 加：重跑 `_verification.md`；讀 iOS/macOS 27 release notes；向 ElevenLabs/Deepgram/Anthropic 問並發與 Tier；Polar/Creem KYC |
| §12 Day 1–2 | `wrangler.toml` 加 migrations；secrets 加 service role / webhook secrets；subtree pull；Tauri 2.12 升級驗證 |
| §12 Day 2–3 | 黃金集縮到 2 位講者；加標註規範、同意書、負樣本（同音詞）、混出樣本 |
| §7 | 增加「1 人版」時程 |
| §0b | 連結評審原文檔 |

---

## 6. 總表

| # | 嚴重度 | 類型 | 一句話 |
|---|---|---|---|
| H1 | 高 | 錯誤 | 簡體洩漏率用 t2s 算是反的；`hasSimplified` gate 排除簡繁混出 |
| H2 | 高 | 矛盾 | LLM 650 ms vs 自家表 0.8–1.3 s；串流對整段貼上無效；KPI 1.2 s 無支撐 |
| H3 | 高 | 過時 | iOS/macOS 27 已出，計畫全以 26 為現行；WWDC26 已過 |
| H4 | 高 | 未驗證 | 查核檔 11 項修正只知 1 項；兩份研究 locale 數矛盾；Handy 日期三種 |
| H5 | 高 | 錯誤 | Free 配額耗盡只關 LLM，STT（2/3 成本）照燒 |
| H6 | 高 | 錯誤 | 每個 Fn/Right Ctrl chord 都開上游；吞 Right Ctrl 破壞 chord；Right Alt 功能表列；🌐 切輸入法衝突；RDP 被 INJECTED 擋 |
| H7 | 高 | 缺漏 | STT WS 協定、並發/速率上限、Anthropic Tier 未研究 |
| H8 | 高 | 含糊 | 1 人 12 週三平台 + W1 工作量不實際 |
| M1 | 中 | 矛盾 | 狀態機 tap / 雙擊三處不一致 |
| M2 | 中 | 錯誤 | 兩端 2.0 s 逾時起點不同 → 二次貼上；DO 並發狀態覆蓋 |
| M3 | 中 | 錯誤 | maxRetries、temperature、fallbacks 範圍、cache workspace、預熱成本 9× |
| M4 | 中 | 過時 | Supabase JWKS / 自訂 claims hook / SMTP / 免登入配額 |
| M5 | 中 | 缺漏 | Worker bundle 與啟動時間（opencc-js、pinyin-pro） |
| M6 | 中 | 錯誤 | AudioRecordingIntent 放錯 target；背景冷啟動錄音未驗；iOS<26 Free 無 STT |
| M7 | 中 | 矛盾 | 「全本地」無清理；macOS Apple FM 被忽略；iOS Free 層級不明 |
| M8 | 中 | 含糊 | 拼音詞典演算法、最小長度、誤替換率 |
| M9 | 中 | 未驗證 | 每次貼上建 tap 的 WindowServer RPC 風險 |
| M10 | 中 | 缺漏 | 注音組字中貼上；Win+V 歷史 |
| M11 | 中 | 缺漏 | 麥克風暖機 / 藍牙喚醒 / 指示燈 |
| M12 | 中 | 缺漏 | wrangler migrations、secrets、subtree pull、Tauri 2.12 升級、sqlcipher-vendored |
| M13 | 中 | 缺漏 | SQLCipher 金鑰、token 存放、離線授權 |
| M14 | 中 | 缺漏 | 評審原文不在 scratchpad |
| M15 | 中 | 缺漏 | 比較廣告法律風險 |
| M16 | 中 | 含糊 | eval gate flaky、標註規範、同意書、注入集 20 vs 50 |
| L1–L14 | 低 | — | 見 §3 |
