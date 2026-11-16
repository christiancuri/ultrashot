#!/usr/bin/env bash
# Regenerates the AppIcon.icon layer SVGs and renders previews to build/icon-preview/
# (Icon Composer's ictool, light and dark, 1024/128/32 px). Edit the sizes at the top of
# app-icon-layers.py, run this script, and look at the PNGs.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ICON="$HERE/../UltraShot/AppIcon.icon"
OUT="$HERE/../build/icon-preview"
ICTOOL="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"

python3 -I "$HERE/app-icon-layers.py"
mkdir -p "$OUT"
for rendition in Default Dark; do
  for px in 1024 128 32; do
    "$ICTOOL" "$ICON" --export-image --output-file "$OUT/$rendition-$px.png" \
      --platform macOS --rendition "$rendition" --width "$px" --height "$px" --scale 1 >/dev/null
  done
done
ls "$OUT"
