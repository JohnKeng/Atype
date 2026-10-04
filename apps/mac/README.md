# Atype for Mac

按住熱鍵說話，放開就把整理好的繁體中文貼進目前的 App。

## 安裝與更新

需要 Xcode Command Line Tools、Rust（`rustup`）、[bun](https://bun.sh)、cmake（`brew install cmake`）。完整的 Xcode 不需要。

```bash
cd apps/mac
bun install
bun run app:install    # 編譯 release 版，裝到 /Applications/Atype.app 並啟動
```

更新：`git pull` 後再跑一次 `bun run app:install`。

**輔助使用權限**：安裝後到「系統設定 → 隱私權與安全性 → 輔助使用」打開 Atype。目前用 ad-hoc 簽章，**每次重新安裝後**清單裡的 Atype 會看起來是開的但其實失效，要關掉再打開一次。之後加入 Apple Developer Program 用固定簽章就不會這樣。

開發時用 `bun run tauri dev`。這時沒有 Atype.app，權限算在啟動它的終端機（例如 iTerm）身上，所以要給的是終端機的麥克風與輔助使用權限。開發版與安裝版共用同一份設定、模型與歷史。

## 第一次設定

1. **模型**：首頁選 SenseVoice Small（約 240 MB）。想比較就到「模型」頁再下載 Qwen3-ASR 0.6B。
2. **LLM 整理**：到 https://aistudio.google.com/apikey 建 Gemini API key。側邊欄「後處理」：供應商 Gemini、貼上 key、模型填 `gemini-3.1-flash-lite`。提示詞預設就是「整理口語（zh-TW）」。沒有 key 也能用，只是不會去贅詞與整理語句。
3. **熱鍵**：預設 Option + Space。要改 Fn：在「一般」裡改，並把「系統設定 → 鍵盤 → 按下 🌐 鍵時」設成「不執行任何操作」。

## 每天怎麼用

| 動作 | 做法 |
|---|---|
| 說一段話 | 按住 Option + Space 說，放開就貼上 |
| 說很長一段 | 輕按一下 Option + Space 開始，說完再按一下 |
| 取消 | 錄音中按 Esc |
| 找回剛才的文字 | 側邊欄「歷史紀錄」，或選單列圖示的最近一筆 |

後處理開著時，主熱鍵就會經過 LLM。LLM 超過 2.5 秒沒回應，就貼本機處理過的原文，不會卡住。

## 資料放在哪

| 東西 | 位置 |
|---|---|
| 設定、`atype.json`、歷史資料庫、錄音 | `~/Library/Application Support/com.atype.mac/` |
| 下載的 GGUF 模型 | `~/.cache/huggingface/hub/` |
| 第二大腦 | iCloud 雲碟的 `Atype/brain/`（沒有 iCloud Drive 時在上面的資料目錄裡的 `brain/`） |
| Log | `~/Library/Logs/com.atype.mac/` |

第二大腦每一筆寫兩處：`atype.jsonl`（時間、貼上的文字、原始辨識、是否經過 LLM）與 `年/年-月-日.md` 的每日紀錄。App 的歷史紀錄只保留最近 300 筆，第二大腦不會刪。

## `atype.json`

第一次啟動時自動建立。用文字編輯器改完存檔，下一次錄音就生效。

| 欄位 | 預設 | 意思 |
|---|---|---|
| `zh_post_enabled` | `true` | 每次都跑確定性中文層（繁體、全形標點、中英空格） |
| `llm_timeout_ms` | `2500` | LLM 的時間預算，超過就貼原文 |
| `llm_on_main_hotkey` | `true` | 主熱鍵也經過 LLM（後處理開著時） |
| `brain_enabled` | `true` | 寫入第二大腦 |
| `brain_dir` | `null` | 第二大腦資料夾，`null` 用預設；可填 `~/Documents/Obsidian/Atype` 這類路徑 |
| `defaults_version` | — | App 自己管理，不用改 |

## 程式結構

桌面殼來自 [Handy](https://github.com/cjpais/Handy) v0.9.8（MIT）：熱鍵、錄音、可靠貼上、Secure Input、浮窗、模型下載與執行、歷史。Atype 自己的部分都在 `src-tauri/src/atype/`：

| 檔案 | 做什麼 |
|---|---|
| `zh_post.rs` | 確定性中文層。只有偵測到真正的簡體字才跑 OpenCC `s2twp`（软件→軟體、网络→網路），台北、著名、後面這類共用字不會誤判；中文句子的標點轉全形，保留 3.5、3:30、example.com、1,000；中英數之間加空格 |
| `config.rs` | 讀寫 `atype.json`，決定第二大腦資料夾 |
| `brain.rs` | 第二大腦：收到歷史紀錄新增或更新的事件就寫入 |
| `defaults.rs` | 一次性把 Atype 的偏好套到既有設定（後處理開、繁體、歷史 300 筆） |
| `mod.rs` | 中文模型清單與推薦順序、主熱鍵是否走 LLM |

掛到殼上的地方：`actions.rs` 的輸出處理（LLM 時間預算與中文層）與主熱鍵、`managers/model.rs` 的模型清單、`lib.rs` 的初始化與 `--polish` 指令、`settings.rs` 的預設值。

相對 Handy 移除的：24 個介面語言（只留英文與繁中）、Windows / Linux 打包、自動更新與選單裡的「檢查更新」、新版本說明彈窗、捐款按鈕、上游 CI 與開發文件。不定期跟上游同步，需要時挑單一修正搬過來。

## 開發與測試

```bash
bun run build                                  # 前端型別檢查與建置
cd src-tauri && cargo test                     # 290 個測試，含 atype 模組
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
