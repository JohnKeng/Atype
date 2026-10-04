#!/usr/bin/env bash
# Build Atype (release) and install it to /Applications.
#   cd apps/mac && bun run app:install
# Settings, models and history live in ~/Library/Application Support/com.atype.mac
# and are shared with `bun run tauri dev`, so nothing has to be set up again.
set -euo pipefail
cd "$(dirname "$0")/.."

bun install
bun run tauri build

APP="src-tauri/target/release/bundle/macos/Atype.app"
[ -d "$APP" ] || { echo "Build output not found: $APP" >&2; exit 1; }

osascript -e 'quit app "Atype"' >/dev/null 2>&1 || true
pkill -x atype >/dev/null 2>&1 || true
sleep 1
rm -rf /Applications/Atype.app
cp -R "$APP" /Applications/
open /Applications/Atype.app

cat <<'MSG'

Atype 已安裝到「應用程式」並啟動。
第一次（或每次重新安裝後）請到「系統設定 → 隱私權與安全性 → 輔助使用」：
  - 若清單已有 Atype：先關掉再打開一次（重新編譯後簽章會變，舊的授權會失效）。
  - 若沒有：按「+」選 /Applications/Atype.app。
麥克風權限會在第一次錄音時詢問。之後可以把 iTerm 的輔助使用權限關掉。
MSG
