# Atype

自用的 Typeless：按住說話，放開就得到可以直接送出的繁體中文。使用者只有一個人（John），只做 Mac 與 iPhone。回覆一律用繁體中文。

## 現況（2026-10-04）

- **Mac**（`apps/mac`）：可用，每天在用。Tauri 2 + Rust + React，桌面殼來自 Handy v0.9.8（MIT）。
- **iPhone**：下一個要做。做成和 Typeless 一樣的**鍵盤**，不是捷徑。設計與分段在 `docs/PLAN.md` 的「iPhone」節與 `docs/architecture.html`。先做 I1（App 會聽會整理），再做 I2（鍵盤插字）。程式放 `apps/ios`。

## Mac 版規則

- Atype 自己的程式全部放 `apps/mac/src-tauri/src/atype/`（`zh_post.rs` 中文層、`config.rs` 讀寫 `atype.json`、`brain.rs` 第二大腦、`defaults.rs` 一次性預設、`commands.rs` 個人化頁的指令、`mod.rs` 模型清單）。對 Handy 原有檔案只加最少的掛鉤。
- 新設定放 `atype.json`（`AtypeConfig`），不要往 Handy 的 `AppSettings` 加欄位。要改既有使用者的 Handy 設定，用 `atype/defaults.rs` 加一個新版本，不要只改 `default_*` 函式。
- 前端新畫面放 `src/components/settings/atype/`；介面文字一律走 i18n，`en` 與 `zh-TW` 兩份都要加。
- 顏色只改 `src/styles/theme.css` 的 token（目前是鸚鵡綠，取自 App 圖示）。
- 改了 Rust 指令後要重產 `src/bindings.ts`：在 `apps/mac/src-tauri` 跑一次 debug 版（例如 `./target/debug/atype --list-models`），tauri-specta 會在啟動時寫出。
- 不定期跟 Handy 上游同步；需要時挑單一修正搬過來。

## 常用指令（在 `apps/mac`）

```bash
bun install
bun run tauri dev                 # 開發；權限算在終端機身上
bun run app:install               # 編 release 版並裝到 /Applications/Atype.app
bun run build                     # 前端型別檢查與建置
cd src-tauri && cargo test        # 300 個測試
cargo run -- --polish "我们明天下午3:30开会"   # 直接看中文層輸出
bun run icon:gen / icon:set       # 生圖示（CLIProxyAPI 的 gpt-image）/ 換圖示
```

推送前跑：`bun run build`、`bunx eslint src`、`bunx prettier --check src scripts`、`cargo fmt -- --check`、`cargo test`。

## 注意

- ad-hoc 簽章：每次重新安裝後，「輔助使用」清單裡的 Atype 要關掉再打開一次。
- LLM 預設 Gemini（`gemini-3.1-flash-lite`），2.5 秒時間預算，逾時貼本機處理過的原文。
- 第二大腦預設寫到 iCloud 雲碟 `Atype/brain/`（`atype.jsonl` 與每日 Markdown），iPhone 版也要寫到同一處。
- 唯一的分支 `claude/typeless-cross-platform-5afuaf` 就是 GitHub 的預設分支。
- 早期研究與商用版方案在 `docs/archive/`，只供查來源，不再維護。
