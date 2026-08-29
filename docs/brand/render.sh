#!/bin/sh
# Rasterise every brand mark to PNG.
#
#   sh docs/brand/render.sh
#
# Uses headless Chrome: this machine has no rsvg-convert, ImageMagick, Inkscape
# or cairosvg, and Chrome renders SVG exactly and writes 8-bit RGB with no alpha
# — which is what the Play Store requires of a listing icon anyway.
#
# icon-adaptive-foreground.svg is skipped on purpose: it is a foreground layer
# with no field, on a 432 canvas, and Android composites it over a separate
# background layer. Rendering it here would bake in a background it must not have.
set -e
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
[ -x "$CHROME" ] || { echo "Chrome not found at $CHROME" >&2; exit 1; }

SIZES="320 512 1080"
mkdir -p png
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

for svg in icon-partial.svg mark-honest-grid.svg mark-return.svg mark-d-bowl.svg; do
  name="${svg%.svg}"

  # Swap the fixed 320x320 for percentage sizing so the single vector source
  # scales to any target; the viewBox does the rest.
  {
    printf '%s\n' '<style>html,body{margin:0;padding:0;background:#3F6C51}svg{display:block}</style>'
    sed 's/width="320" height="320"/width="100%" height="100%"/' "$svg"
  } > "$TMP/wrap.html"

  for s in $SIZES; do
    "$CHROME" --headless=new --disable-gpu --hide-scrollbars \
      --screenshot="png/$name-$s.png" --window-size="$s,$s" \
      "file://$TMP/wrap.html" >/dev/null 2>&1
    echo "png/$name-$s.png"
  done
done
