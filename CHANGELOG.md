# Changelog

All notable changes to UltraShot. Each `## <version>` section is used as the
GitHub Release notes and the in-app (Sparkle) update notes.

## 0.2.1

- **Choose your microphone**: pick the input device in Settings › Recording or from the chevron next to the microphone button in the record panel. If the chosen device is unplugged, recordings use the system default until it is back.
- **Smoother captures**: the shutter sound and the clipboard copy no longer block the screen for a moment after you release the selection.
- **Auto-close now saves by default**: thumbnails that close on their own are saved to your export folder. Pick Close and Delete in Settings › Quick Access to keep the old behavior.

## 0.2.0

- **Automatic updates** through Sparkle: UltraShot checks this repository's GitHub Releases and offers new versions. Turn automatic checks off in Settings › General, or check any time with **Check for Updates…** in the menu bar menu.
- Coming from 0.1.0? Download 0.2.0 manually once; later versions arrive on their own.

## 0.1.0

The first release: a native menu bar app for screenshots and screen recordings on macOS 26.

- **Captures**: Capture Area (⇧⌘4), Capture Area & Annotate (⌥⇧⌘4), Capture Fullscreen (⇧⌘3) and Capture Window. Every shortcut can be changed in Settings › Shortcuts.
- **Clipboard first**: every screenshot is copied to the clipboard right away.
- **Screen recording**: Record Screen (⇧⌘5) saves an MP4 with system audio and your microphone, with pause/resume and a recording HUD; press the shortcut again to stop.
- **Quick Access thumbnail**: Copy, Save, Save As…, Open With, Quick Look, Annotate and Delete from the floating thumbnail, drag and drop it into any app, or right-click for the full menu. It closes on its own after a while, with Close and Delete or Save and Close.
- **Annotation editor** in the style of Lightshot: rectangle, ellipse, arrow, line, pen, marker, text, blur and numbered counters, with undo/redo.
- **Tidy by default**: temporary files you never saved are cleaned up.
