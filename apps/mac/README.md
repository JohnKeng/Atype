# Atype for Mac

按住熱鍵說話，放開就把整理好的繁體中文貼進目前的 App。

## 安裝與更新

有兩種方式，裝好的 App 一樣。只支援 Apple 晶片（M1 以後）的 Mac。

### 方式一：下載編好的 App（不用裝開發工具）

1. 到 [Releases](https://github.com/JohnKeng/Atype/releases/latest) 下載 `Atype-<版本>-macos-arm64.zip`，解壓縮，把 `Atype.app` 拖進「應用程式」。
2. **第一次打開會被擋**：這個 App 沒有經過 Apple 公證，macOS 會說「無法驗證開發者」或「Apple 無法檢查是否包含惡意軟體」。這時：
   - 按「完成」關掉提示，到「系統設定 → 隱私權與安全性」，往下捲到「已阻擋 Atype」，按 **「仍要打開」**，輸入密碼後再按一次「打開」。只要做一次。
   - 如果看到的是「**已損毀，應丟到垃圾桶**」，在終端機執行下面這行再打開：

     ```bash
     xattr -dr com.apple.quarantine /Applications/Atype.app
     ```
3. 更新：下載新版本，覆蓋 `/Applications/Atype.app`，再照下面「輔助使用權限」重給一次。

### 方式二：自己從原始碼編

需要 Xcode Command Line Tools、Rust（`rustup`）、[bun](https://bun.sh)、cmake（`brew install cmake`）。完整的 Xcode 不需要。第一次約 5 到 10 分鐘。自己編的 App 不會被擋。

```bash
git clone https://github.com/JohnKeng/Atype.git
cd Atype/apps/mac
bun install
bun run app:install    # 編譯 release 版，裝到 /Applications/Atype.app 並啟動
```

更新：`git pull` 後再跑一次 `bun run app:install`。

### 輔助使用權限（兩種方式都要）

Atype 要能把字貼進其他 App，需要「系統設定 → 隱私權與安全性 → 輔助使用」打開 Atype。麥克風權限會在第一次錄音時詢問。

目前用 ad-hoc 簽章，**每次重新安裝或更新後**，清單裡的 Atype 會看起來是開的但其實失效。設定頁一直顯示「等待中」就是這個原因：在清單裡選 Atype 按「−」刪掉，按「＋」重新加入 `/Applications/Atype.app`，然後結束 Atype 再打開。還是不行就執行 `tccutil reset Accessibility com.atype.mac`，再打開 Atype 重新授權。

開發時用 `bun run tauri dev`。這時沒有 Atype.app，權限算在啟動它的終端機（例如 iTerm）身上，所以要給的是終端機的麥克風與輔助使用權限。開發版與安裝版共用同一份設定、模型與歷史。

## 第一次設定

1. **模型**：首頁選 SenseVoice Small（約 240 MB）。想比較就到「模型」頁再下載 Qwen3-ASR 0.6B。
2. **LLM 整理**：請自備 Gemini API key（https://aistudio.google.com/apikey 免費建立）。側邊欄「後處理」：供應商 Gemini、貼上 key。模型預設 `gemini-3.1-flash-lite`，提示詞預設「整理口語（zh-TW）」，都不用改。模型選單只列得出能用的模型。沒有 key 也能用，只是不會去贅詞、整理語句或幫你寫信。
3. **熱鍵**：預設 Option + Space。要改 Fn：在「一般」裡改，並把「系統設定 → 鍵盤 → 按下 🌐 鍵時」設成「不執行任何操作」。

## 每天怎麼用

| 動作 | 做法 |
|---|---|
| 說一段話 | 按住 Option + Space 說，放開就貼上 |
| 說很長一段 | 輕按一下 Option + Space 開始，說完再按一下 |
| 取消 | 錄音中按 Esc |
| 找回剛才的文字 | 側邊欄「歷史紀錄」，或選單列圖示的最近一筆 |
| 請 AI 幫你寫（信、訊息、會議記錄…） | 按住 **AI 指令快捷鍵**說內容或大綱，開頭可以說「回信」「條列」「會議記錄」「翻英文」等口令。可以設成主熱鍵再加一個鍵（例如主熱鍵右 ⌘ + 右 ⌥、AI 指令右 ⌘ + 右 ⌥ + ←）：先按主熱鍵開始說，中途補按 ← 就升級成 AI |

- **主熱鍵**預設只在本機處理（辨識、詞典、繁體與排版），放開就貼上，不經過 AI。想讓它也去贅詞、修語句，到「個人化」打開「主熱鍵也用 AI 整理」（會慢 1～2 秒，固定用「整理口語」提示詞）。
- **AI 指令快捷鍵**用「後處理」頁選的提示詞（預設「萬用口令」，依口令選格式），缺的資訊標【待補】，不會自己編。等多久（預設 12 秒）在「個人化」頁設定。內建提示詞：整理口語、萬用口令、正式信件、訊息回覆、改成正式語氣、條列重點、會議記錄、待辦清單、公告／通知、翻成英文；都可以在「後處理」頁修改。
- **浮窗**：一般聽寫是圓點；AI 指令從錄音開始就換成旋轉的彩色外框、✦ 和彩色波形；AI 整理或撰寫時顯示「AI 整理中…」「AI 撰寫中…」。
- **詞典**（「個人化」頁）：修正常聽錯的人名、產品名。中文詞只填正確寫法就會自動比對同音字；英文詞要填聽錯的拼法。在本機處理，不開 AI 也有效。

**Dock**：設定完成後，Atype 開啟時只出現在選單列，不會出現在 Dock。從選單列圖示打開設定視窗時 Dock 才會暫時出現圖示，關掉視窗就消失。想每次開啟都顯示視窗，到「進階」關掉「隱藏啟動」。

## 換 App 圖示

圖示用你自己 CLIProxyAPI 的 GPT 生圖產生，風格對齊你其他 App（LogScope 的松鼠、Tako 的章魚、Omi Ear 的蝙蝠）。

```bash
cd apps/mac
export CLIPROXY_BASE_URL=http://127.0.0.1:8317     # 你的 CLIProxyAPI 位址
export CLIPROXY_API_KEY=你在 CLIProxyAPI 設定的 api-key
bun run icon:gen                 # 產生 3 張大象候選，存到 ~/Desktop/atype-icons
bun run icon:gen owl 4           # 或貓頭鷹 4 張；meerkat 是狐獴
bun run icon:gen elephant 2 --ref ~/Desktop/tako.png   # 照某張既有圖示的畫風重畫
bun run icon:set ~/Desktop/atype-icons/<選中的檔案>.png  # 裁成 macOS 圓角、加陰影、換掉所有圖示
bun run app:install
```

- 模型預設 `gpt-image-2`，可用 `ATYPE_ICON_MODEL` 改成你 `/v1/models` 列出的圖像模型。
- 想拿既有 App 的圖示當參考：`sips -s format png "/Applications/Tako.app/Contents/Resources/$(defaults read /Applications/Tako.app/Contents/Info CFBundleIconFile | sed 's/\.icns$//').icns" --out ~/Desktop/tako.png`
- 已經是完整圓角圖示、四角透明的 PNG 用 `bun run icon:set --as-is <檔案>`。
- 已經是圓角圖示但四周是白底（例如 JPG）用 `bun run icon:set --on-grid <檔案>`，會照 macOS 圖示網格把圓角框挖出來。目前的鸚鵡圖示就是這樣做的，原圖在 `design/atype-icon-source.jpg`。
- `icon:set` 同時更新 App 圖示與 App 內左上角的 logo；選單列的小圖示維持單色剪影（macOS 規定）。
- 換完 Finder 或 Dock 還是舊圖時：`killall Dock`。
- 提示詞在 `scripts/icon-prompts.ts`，可以直接改。

## 資料放在哪

| 東西 | 位置 |
|---|---|
| 設定、`atype.json`、歷史資料庫、錄音 | `~/Library/Application Support/com.atype.mac/` |
| 下載的 GGUF 模型 | `~/.cache/huggingface/hub/` |
| 第二大腦 | iCloud 雲碟的 `service-db/Atype/`（沒有 iCloud Drive 時在上面的資料目錄裡的 `brain/`） |
| Log | `~/Library/Logs/com.atype.mac/` |

第二大腦每一筆寫兩處：`atype.jsonl`（時間、貼上的文字、原始辨識、是否經過 LLM）與 `年/年-月-日.md` 的每日紀錄。App 的歷史紀錄只保留最近 300 筆，第二大腦不會刪。

## 個人化頁面與 `atype.json`

側邊欄「個人化」可以看今天、本週、累計說了多少字，選第二大腦資料夾並在 Finder 打開，調整 LLM 時間預算與開關，還有一個「試試看」框直接看中文排版效果。這些設定存在 `atype.json`，也可以用文字編輯器改，存檔後下一次錄音就生效。

| 欄位 | 預設 | 意思 |
|---|---|---|
| `zh_post_enabled` | `true` | 每次都跑確定性中文層（繁體、全形標點、中英空格） |
| `llm_timeout_ms` | `2500` | LLM 的時間預算，超過就貼原文 |
| `llm_on_main_hotkey` | `false` | 主熱鍵也經過 LLM 整理（後處理開著時） |
| `brain_enabled` | `true` | 寫入第二大腦 |
| `brain_dir` | `null` | 第二大腦資料夾，`null` 用預設；可填 `~/Documents/Obsidian/Atype` 這類路徑 |
| `dictionary` | `[]` | 詞典，`{"term": "iCloud", "aliases": ["iclo"]}` 的清單 |
| `command_timeout_ms` | `12000` | AI 指令快捷鍵的時間預算 |
| `defaults_version` | — | App 自己管理，不用改 |

## 程式結構

桌面殼來自 [Handy](https://github.com/cjpais/Handy) v0.9.8（MIT）：熱鍵、錄音、可靠貼上、Secure Input、浮窗、模型下載與執行、歷史。Atype 自己的部分都在 `src-tauri/src/atype/`：

| 檔案 | 做什麼 |
|---|---|
| `zh_post.rs` | 確定性中文層。只有偵測到真正的簡體字才跑 OpenCC `s2twp`（软件→軟體、网络→網路），台北、著名、後面這類共用字不會誤判；中文句子的標點轉全形，保留 3.5、3:30、example.com、1,000；中英數之間加空格 |
| `config.rs` | 讀寫 `atype.json`，決定第二大腦資料夾 |
| `commands.rs` | 個人化頁面用的指令：讀寫設定、使用量統計、套用中文排版、打開第二大腦資料夾 |
| `brain.rs` | 第二大腦：收到歷史紀錄新增或更新的事件就寫入 |
| `defaults.rs` | 一次性把 Atype 的偏好套到既有設定（後處理開、繁體、歷史 300 筆） |
| `mod.rs` | 中文模型清單與推薦順序、主熱鍵是否走 LLM |

掛到殼上的地方：`actions.rs` 的輸出處理（LLM 時間預算與中文層）與主熱鍵、`managers/model.rs` 的模型清單、`lib.rs` 的初始化與 `--polish` 指令、`settings.rs` 的預設值。

相對 Handy 移除的：24 個介面語言（只留英文與繁中）、Windows / Linux 打包、自動更新與選單裡的「檢查更新」、新版本說明彈窗、捐款按鈕、上游 CI 與開發文件。不定期跟上游同步，需要時挑單一修正搬過來。

## 開發與測試

```bash
bun run build                                  # 前端型別檢查與建置
cd src-tauri && cargo test                     # 298 個測試，含 atype 模組
cargo run -- --polish "我们明天下午3:30开会,地点在Costco旁边."
# → 我們明天下午 3:30 開會，地點在 Costco 旁邊。
```

`--transcribe-file 檔案.wav --model 模型id --json` 可以不開麥克風直接辨識一段 16 kHz 單聲道 WAV，`--list-models` 列出可用的模型 id。

Linux 不是目標平台，但可以在 Linux 上編譯與跑測試，用來檢查改動：

```bash
apt-get install -y libwebkit2gtk-4.1-dev libgtk-3-dev libayatana-appindicator3-dev \
  librsvg2-dev libasound2-dev libxdo-dev libgtk-layer-shell-dev cmake clang
# ort 需要 onnxruntime 1.24.2；拿不到 cdn.pyke.io 時用官方動態庫
curl -L https://github.com/microsoft/onnxruntime/releases/download/v1.24.2/onnxruntime-linux-x64-1.24.2.tgz | tar xz
export ORT_LIB_LOCATION=$PWD/onnxruntime-linux-x64-1.24.2 ORT_PREFER_DYNAMIC_LINK=1 ORT_SKIP_DOWNLOAD=1
export LD_LIBRARY_PATH=$ORT_LIB_LOCATION/lib
cd apps/mac && bun install && bun run build && cd src-tauri && cargo test
```
