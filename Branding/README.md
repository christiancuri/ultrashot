# UltraShot branding

## Files

| Output | Source | Notes |
| --- | --- | --- |
| `UltraShot/AppIcon.icon` | `app-icon-layers.py` (layer SVGs) + hand-edited `icon.json` | Icon Composer package. `render-app-icon.sh` regenerates the layers and renders previews to `build/icon-preview/`. |
| `dmg-background.png`, `dmg-background@2x.png` | `dmg-background.svg` | 660 × 400 pt DMG window background, rendered with resvg and SF Pro by `make-dmg-assets.sh`. `scripts/release.sh` merges both into a multi-resolution TIFF, which Finder needs for Retina. |
| `VolumeIcon.icns` | `UltraShot/AppIcon.icon` via `render-icon.swift` | DMG volume icon: the app icon as macOS renders it (actool compiles the icon into a throwaway bundle, then IconServices draws it). |

Regenerate the DMG assets with:

```sh
brew install resvg                     # once
Branding/make-dmg-assets.sh            # add --background-only to skip the volume icon
```

## Colors

From `UltraShot/AppIcon.icon/icon.json`:

| Token | Light | Dark |
| --- | --- | --- |
| Icon gradient, top | `#7A5CFF` | `#4A33B0` |
| Icon gradient, bottom | `#2E1A8C` | `#0F092E` |
| Glyph | `#FFFFFF` | `#FFFFFF` |

## DMG layout

The background has no icons of its own; Finder draws them at these positions.

- Window content size: **660 × 400 pt** (icon view, with the toolbar and status bar hidden).
- Icon size **128 pt**, text size **13 pt**.
- `UltraShot.app` centered at **(160, 190)**; the `Applications` link centered at **(500, 190)**.
  Finder icon positions are the icon's center, with the origin at the top left of the window content.
- The background draws a faint 160 × 190 pt slot behind each icon and its label (x 80 and 420, y 100),
  selection-corner brackets around the app slot (the icon's motif), an indigo arrow from x 266 to x 393
  at y 190 and a caption centered at y 350.
- Volume icon: `VolumeIcon.icns`, copied to `.VolumeIcon.icns` at the volume root and marked with the
  custom-icon Finder flag.
