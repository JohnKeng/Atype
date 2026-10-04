# Atype

按住熱鍵說話，放開就得到可以直接送出的**繁體中文**：去掉贅詞、保留中英夾雜、全形標點、中英之間有空格，不出簡體，不改你的意思。

這是自用的 Typeless。Mac 已經能用，iPhone 是下一步。

![Atype 的個人化頁面](docs/images/atype-mac-personal.png)

## 在 Mac 上安裝

需要 Xcode Command Line Tools、Rust、bun、cmake。第一次編譯約 5 到 10 分鐘。

```bash
git clone https://github.com/JohnKeng/Atype.git
cd Atype/apps/mac
bun install
bun run app:install      # 編譯並安裝到「應用程式」
```

開發時用 `bun run tauri dev`。第一次設定（下載模型、填 Gemini key、給權限）與每天的用法在 [`apps/mac/README.md`](apps/mac/README.md)。

## 怎麼運作

```mermaid
flowchart LR
  K[按住 Option + Space] --> R[錄音]
  R --> S[本機辨識<br/>SenseVoice Small]
  S --> L{{LLM 整理<br/>Gemini · 2.5 秒預算}}
  L -->|回來| Z[確定性中文層<br/>繁體 · 全形標點 · 中英空格]
  L -->|逾時或失敗| Z
  Z --> P[貼到目前的 App]
  Z --> H[(歷史紀錄)]
  H --> B[[第二大腦<br/>iCloud Drive/Atype/brain]]
```

- **聲音不離開這台 Mac**。只有辨識出來的文字會送到 LLM 整理，而且可以關掉。
- **繁體與排版由程式保證**，不靠 LLM 記得。LLM 慢或失敗時，貼的是本機處理過的原文。
- **每一筆輸入都存一份**到 `atype.jsonl` 和每日 Markdown，給之後的搜尋與摘要用。

## 目錄

| 路徑 | 內容 |
|---|---|
| [`apps/mac/`](apps/mac/README.md) | Mac App。Atype 自己的程式在 `src-tauri/src/atype/` |
| [`docs/PLAN.md`](docs/PLAN.md) | 決策、下一步、iPhone 計畫、模型、prompt、測試句 |
| [`docs/archive/`](docs/archive/README.md) | 早期研究與商用版方案，不再維護 |

## 致謝

Mac 版的桌面殼（熱鍵、錄音、貼上、浮窗、模型執行）來自 CJ Pais 的 [Handy](https://github.com/cjpais/Handy)，MIT 授權，授權條款保留在 `apps/mac/LICENSE`。
