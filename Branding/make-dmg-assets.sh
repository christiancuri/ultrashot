#!/usr/bin/env bash
# Regenerates the DMG branding used by scripts/release.sh:
#   Branding/dmg-background.png, dmg-background@2x.png   660 x 400 pt window background
#                                                        (resvg + SF Pro, from dmg-background.svg)
#   Branding/VolumeIcon.icns                             DMG volume icon: UltraShot/AppIcon.icon
#                                                        as macOS renders it (render-icon.swift)
#
# usage: Branding/make-dmg-assets.sh [--background-only]
# Requires `brew install resvg`; the volume icon needs Xcode 26+ (actool).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ICON="$HERE/../UltraShot/AppIcon.icon"
RENDER_ICON=1
[[ "${1:-}" == "--background-only" ]] && RENDER_ICON=0

command -v resvg >/dev/null || { echo "missing resvg: brew install resvg" >&2; exit 1; }

# SF Pro is passed explicitly so the caption matches Finder's labels.
FONT=(--use-font-file /System/Library/Fonts/SFNS.ttf)
resvg "${FONT[@]}" -w 660 "$HERE/dmg-background.svg" "$HERE/dmg-background.png"
resvg "${FONT[@]}" -w 1320 "$HERE/dmg-background.svg" "$HERE/dmg-background@2x.png"
echo "rendered dmg-background.png (660 x 400) and dmg-background@2x.png (1320 x 800)"

if [[ "$RENDER_ICON" == 1 ]]; then
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  swift "$HERE/render-icon.swift" "$ICON" "$TMP/VolumeIcon.iconset"
  iconutil -c icns -o "$HERE/VolumeIcon.icns" "$TMP/VolumeIcon.iconset"
  echo "rendered VolumeIcon.icns"
fi
