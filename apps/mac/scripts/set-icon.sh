#!/usr/bin/env bash
# Replace Atype's icon everywhere from one square PNG (ideally 1024x1024):
#   cd apps/mac && bun run icon:set ~/Desktop/atype-icon.png
# Updates the macOS app icon set (src-tauri/icons) and the in-app logo
# (src/assets/atype-icon.png). The menu-bar glyph stays a monochrome template
# image (src-tauri/resources/tray_*.png), as macOS expects.
set -euo pipefail
# By default the image is treated as a full-bleed illustration (what
# `bun run icon:gen` produces) and cut into the macOS rounded tile with a
# shadow by scripts/make-icon.ts. Pass --as-is for an already finished icon.
# Pass --on-grid for a finished icon flattened onto a white/opaque background
# (e.g. a JPG of a rounded icon): the tile is cut out in place.
AS_IS=0
MODE=""
if [ "${1:-}" = "--as-is" ]; then AS_IS=1; shift; fi
if [ "${1:-}" = "--on-grid" ]; then MODE="--on-grid"; shift; fi
SRC="${1:-}"
[ -n "$SRC" ] && [ -f "$SRC" ] || { echo "用法：bun run icon:set [--as-is | --on-grid] <圖片>" >&2; exit 1; }
SRC="$(cd "$(dirname "$SRC")" && pwd)/$(basename "$SRC")"
cd "$(dirname "$0")/.."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [ "$AS_IS" = 1 ]; then
  if command -v sips >/dev/null 2>&1; then
    sips -s format png -z 1024 1024 "$SRC" --out "$TMP/source.png" >/dev/null
  else
    cp "$SRC" "$TMP/source.png"
  fi
else
  bun scripts/make-icon.ts $MODE "$SRC" "$TMP/source.png" >/dev/null
fi

bunx tauri icon "$TMP/source.png" -o "$TMP/icons" >/dev/null
for f in 32x32.png 64x64.png 128x128.png 128x128@2x.png icon.icns icon.png; do
  cp "$TMP/icons/$f" "src-tauri/icons/$f"
done
cp "$TMP/source.png" src-tauri/icons/logo.png
cp "$TMP/icons/128x128@2x.png" src/assets/atype-icon.png

echo "圖示已更新。執行 bun run app:install 重新安裝後就會看到。"
echo "Dock 或 Finder 若還顯示舊圖示：killall Dock"
