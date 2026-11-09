#!/usr/bin/env bash
# 从 src/*.html 与 index.html 重新生成 dist/ 下的 PDF、PNG 与 SVG 成品。
# 用法：bash scripts/build.sh
# 依赖：Microsoft Edge 或 Google Chrome、Python 3、bash（Windows 用 Git Bash）。
# 若浏览器不在默认路径，可用 BROWSER_BIN=/path/to/browser 指定。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/src"
DIST="$ROOT/dist"
TMP="$ROOT/.tmp-build"
mkdir -p "$DIST" "$TMP"
trap 'rm -rf "$TMP"' EXIT

# Git Bash 的 /d/path 转成原生程序可识别的 D:/path
to_win() {
  local p="$1"
  if [[ "$p" =~ ^/([a-zA-Z])/(.*)$ ]]; then
    printf '%s:/%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
  else
    printf '%s' "$p"
  fi
}

file_url() {
  local p; p="$(to_win "$1")"
  printf 'file:///%s' "${p#/}"
}

find_browser() {
  if [[ -n "${BROWSER_BIN:-}" ]]; then printf '%s' "$BROWSER_BIN"; return; fi
  local candidates=(
    "/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"
    "/c/Program Files/Microsoft/Edge/Application/msedge.exe"
    "/c/Program Files/Google/Chrome/Application/chrome.exe"
    "/c/Program Files (x86)/Google/Chrome/Application/chrome.exe"
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  )
  local p
  for p in "${candidates[@]}"; do
    if [[ -f "$p" ]]; then printf '%s' "$p"; return; fi
  done
  echo "找不到 Edge/Chrome，请使用 BROWSER_BIN=/path/to/browser 指定。" >&2
  exit 1
}

EDGE="$(find_browser)"
WIN_DIST="$(to_win "$DIST")"
WIN_TMP="$(to_win "$TMP")"
CARD_URL="$(file_url "$SRC/china-econ-cheatsheet.html")"
VISUAL_URL="$(file_url "$SRC/china-econ-visual.html")"
COMMON=(--headless=new --disable-gpu --no-sandbox --no-first-run --disable-extensions --hide-scrollbars)

echo "[1/5] 导出 A4 速查卡 PDF"
"$EDGE" "${COMMON[@]}" --user-data-dir="$WIN_TMP/pdf" \
  --no-pdf-header-footer --print-to-pdf-no-header \
  --print-to-pdf="$WIN_DIST/中国经济数量级速查卡_2025.pdf" \
  "$CARD_URL" >/dev/null 2>&1

for SCALE in 2 3; do
  echo "[2/5] 导出速查卡 PNG ${SCALE}x"
  "$EDGE" "${COMMON[@]}" --user-data-dir="$WIN_TMP/card$SCALE" \
    --force-device-scale-factor="$SCALE" --window-size=794,1123 \
    --screenshot="$WIN_DIST/中国经济数量级速查卡_2025_${SCALE}x.png" \
    "$CARD_URL" >/dev/null 2>&1
done

echo "[3/5] 测量可视化图鉴页面高度"
python - "$SRC/china-econ-visual.html" "$TMP/measure.html" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
html = open(src, encoding='utf-8').read()
html = html.replace(
    '</body>',
    '<script>document.documentElement.setAttribute("data-h", document.body.scrollHeight);</script></body>',
)
open(dst, 'w', encoding='utf-8').write(html)
PY
H="$({ "$EDGE" "${COMMON[@]}" --user-data-dir="$WIN_TMP/measure" \
        --dump-dom "$(file_url "$TMP/measure.html")" 2>/dev/null \
        | grep -o 'data-h="[0-9]*"' | head -1 | grep -o '[0-9]*'; } || true)"
[[ -z "$H" ]] && H=2420
H=$((H + 20))

echo "[4/5] 导出可视化图鉴长图（页面高度 ${H}px）"
"$EDGE" "${COMMON[@]}" --user-data-dir="$WIN_TMP/visual" \
  --force-device-scale-factor=2 --window-size="1160,$H" \
  --screenshot="$WIN_DIST/中国经济可视化图鉴_2025.png" \
  "$VISUAL_URL" >/dev/null 2>&1

echo "[5/5] 从主页渲染结果导出财政资金流桑基图 SVG"
"$EDGE" "${COMMON[@]}" --user-data-dir="$WIN_TMP/sankey" \
  --dump-dom "$(file_url "$ROOT/index.html")" > "$TMP/sankey-dom.html" 2>/dev/null
python - "$TMP/sankey-dom.html" "$DIST/财政资金流桑基图_2025.svg" <<'PY'
import re, sys
# 桑基图由 index.html 内联脚本生成，这里直接抽取渲染后的 SVG，避免维护第二份数据
dom = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'<svg id="sankey"[^>]*>([\s\S]*?)</svg>', dom)
if not m:
    sys.exit('主页中没有找到渲染后的桑基 SVG')
inner = m.group(1).replace(
    '</defs>', '</defs>\n<rect width="1000" height="470" fill="#ffffff"/>', 1)
style = '''<style>
.link { opacity: 0.72; }
.lbl { font-family: "Microsoft YaHei", "PingFang SC", sans-serif;
       paint-order: stroke fill; stroke: #ffffff; stroke-width: 2.5px; stroke-linejoin: round; }
</style>'''
svg = ('<?xml version="1.0" encoding="UTF-8"?>\n'
       '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 470" width="1000" height="470" '
       'role="img" aria-label="2025 年中国财政资金流桑基图">\n'
       '<title>2025 年中国财政资金流桑基图 · 三段合计 35.32 万亿元</title>\n'
       + style + '\n' + inner + '\n</svg>\n')
open(sys.argv[2], 'w', encoding='utf-8').write(svg)
PY

python - "$DIST" <<'PY'
import os, struct, sys
dist = sys.argv[1]
names = [
    '中国经济数量级速查卡_2025.pdf',
    '中国经济数量级速查卡_2025_2x.png',
    '中国经济数量级速查卡_2025_3x.png',
    '中国经济可视化图鉴_2025.png',
    '财政资金流桑基图_2025.svg',
]
print('\n产物：')
for n in names:
    p = os.path.join(dist, n)
    if not os.path.exists(p) or os.path.getsize(p) == 0:
        print('  失败:', n); sys.exit(1)
    extra = ''
    if n.endswith('.png'):
        with open(p, 'rb') as f:
            head = f.read(24)
        w, h = struct.unpack('>II', head[16:24])
        extra = f'{w} x {h} px | '
    print(f'  {n} | {extra}{os.path.getsize(p)//1024} KB')
PY
echo "完成。"
