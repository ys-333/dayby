#!/bin/sh
# Rasterise the brand mark to PNG. No dependencies beyond Chrome — this machine
# has no rsvg-convert, ImageMagick, Inkscape or cairosvg, and headless Chrome
# renders SVG exactly and outputs RGB with no alpha, which is what the Play
# Store requires anyway.
#
#   sh docs/brand/render.sh
set -e
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
[ -x "$CHROME" ] || { echo "Chrome not found at $CHROME" >&2; exit 1; }

mkdir -p png
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# The mark inlined with percentage sizing so one source scales to every target.
cat > "$TMP/wrap.html" <<'HTML'
<style>html,body{margin:0;padding:0;background:#3F6C51}svg{display:block}</style>
<svg xmlns="http://www.w3.org/2000/svg" width="100%" height="100%" viewBox="0 0 320 320">
  <rect width="320" height="320" fill="#3F6C51"/>
  <path d="M160 62 A 98 98 0 0 0 160 258 Z" fill="#F1F3EF"/>
  <circle cx="160" cy="160" r="98" fill="none" stroke="#F1F3EF" stroke-width="26"/>
</svg>
HTML

for s in 320 512 1080; do
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars \
    --screenshot="png/icon-partial-$s.png" --window-size="$s,$s" \
    "file://$TMP/wrap.html" >/dev/null 2>&1
  echo "png/icon-partial-$s.png"
done
