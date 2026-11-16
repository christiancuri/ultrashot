# Debug automation

Debug builds of UltraShot read the switches below so every flow can run end to end without synthetic
mouse or keyboard events. Release builds ignore all of them. Run the binary directly to pass
environment variables:

```sh
APP=build/DerivedData/Build/Products/Debug/UltraShot.app/Contents/MacOS/UltraShot
ULTRASHOT_DEBUG_OPEN=capture-annotate ULTRASHOT_DEBUG_FAKE_SNAPSHOT=1 \
ULTRASHOT_DEBUG_AUTOSELECT=400,250,600,400 ULTRASHOT_DEBUG_ANNOTATE_SCRIPT=sample \
ULTRASHOT_DEBUG_ANNOTATE_FINISH=copy ULTRASHOT_DEBUG_PASTEBOARD=1 \
ULTRASHOT_DEBUG_EXPORT_DIR=/tmp/ultrashot-export "$APP"
```

| Variable | Effect |
|---|---|
| `ULTRASHOT_DEBUG_OPEN=<surface>` (or `-debug-open <surface>`) | Opens a surface at launch: `settings`, `settings:<tab>` (general, shortcuts, quickAccess, screenshots, recording, about), `onboarding`, `capture-area`, `capture-fullscreen`, `capture-window`, `capture-annotate`, `record`, `record-panel`, `thumbnail-sample`, `annotate-sample` or `overlay-sample`. |
| `ULTRASHOT_DEBUG_REPEAT=<n>`, `ULTRASHOT_DEBUG_REPEAT_INTERVAL=<s>` | Opens the surface `n` times, `s` seconds apart (default 4). Useful for memory checks. |
| `ULTRASHOT_DEBUG_QUIT_AFTER=<s>` | Quits through the real quit path (`NSApp.terminate`) after `s` seconds. |
| `ULTRASHOT_DEBUG_FAKE_SNAPSHOT=1` | Capture flows use a synthetic desktop instead of the real screen. |
| `ULTRASHOT_DEBUG_FAKE_SNAPSHOT=<path>` | Same, but uses that image file, scaled to fill each screen (the README screenshots use a designed desktop). |
| `ULTRASHOT_DEBUG_BACKDROP=1` | With the fake snapshot, covers the main screen with a click-through window showing it, so glass windows (Settings, thumbnails, menus) blur the synthetic desktop instead of the real one. |
| `ULTRASHOT_DEBUG_APPEARANCE=light\|dark` | Forces the app's appearance without touching the system setting. |
| `ULTRASHOT_DEBUG_OVERLAY_SELECTION="x,y,w,h"` | The selection for `overlay-sample`, and for `record-panel` as if it was dragged. Main-screen points, origin at the bottom left. |
| `ULTRASHOT_DEBUG_ANNOTATE_JSON=<path>` | Once an annotation session has a selection, adds the annotations from that JSON file (an array of `Annotation`, coordinates relative to the selection's bottom-left corner). |
| `ULTRASHOT_DEBUG_THUMBNAIL_MENU=1` | Opens the newest screenshot thumbnail's context menu 2 s after it appears. Menu tracking blocks `ULTRASHOT_DEBUG_QUIT_AFTER`, so stop the app with `kill`. |
| `ULTRASHOT_DEBUG_CAPTURABLE_OVERLAY=1` | Lets `screencapture -l <id>` capture the overlay, thumbnail and HUD windows. Use it only with the fake snapshot. |
| `ULTRASHOT_DEBUG_AUTOSELECT="x,y,w,h"` | Capture Area and Capture Area & Annotate commit this selection, in main-screen points with the origin at the bottom left. |
| `ULTRASHOT_DEBUG_AUTOWINDOW=1` | Capture Window takes the topmost window that isn't UltraShot's. |
| `ULTRASHOT_DEBUG_PASTEBOARD=1` | Clipboard writes go to the named pasteboard `dev.christiancuri.ultrashot.debug`, leaving your real clipboard alone. |
| `ULTRASHOT_DEBUG_EXPORT_DIR=<path>` | Overrides the export folder. |
| `ULTRASHOT_DEBUG_AFTER_CAPTURE="screenshot=<flags>;recording=<flags>"` | Overrides the after-capture actions. Flags are `thumbnail`, `copy` and `save` joined with `+`, or `none`. |
| `ULTRASHOT_DEBUG_AUTOCLOSE=<s>\|off`, `ULTRASHOT_DEBUG_AUTOCLOSE_ACTION=close\|saveAndClose` | Overrides the thumbnail auto-close interval and action. |
| `ULTRASHOT_DEBUG_QA_POSITION=left\|right` | Overrides the thumbnail position. |
| `ULTRASHOT_DEBUG_THUMBNAIL_ACTION=<a>[,<a>…]` | Runs one action every 2 s after a thumbnail appears: `hover`, `copy`, `save`, `save-only`, `close`, `delete`, `annotate`, `dragged` (a drop into another app finished), `menu-log` or `saved-feedback`. Add `:screenshot` or `:recording` to limit an action to one kind. |
| `ULTRASHOT_DEBUG_ANNOTATE_FINISH=copy\|save` | Every annotation session runs the script below, then finishes with Copy or Save through the real completion. |
| `ULTRASHOT_DEBUG_ANNOTATE_SCRIPT=<steps>` | Scripted annotator steps: `sample`, `text`, `palette`, `textalign`, `selftest`, `tool=<name>`, `copy` and `save`. |
| `ULTRASHOT_DEBUG_ANNOTATE_DELAY=<s>` | Wait before the scripted Copy or Save (default 3). |
| `ULTRASHOT_DEBUG_ANNOTATE_FILE=<path>`, `ULTRASHOT_DEBUG_ANNOTATE_SELECTION="x,y,w,h"\|none`, `ULTRASHOT_DEBUG_ANNOTATE_EXPORT=<path>` | Options for `annotate-sample`: open a file, set the initial selection, or write the export to a path. |
| `ULTRASHOT_DEBUG_AUTORECORD="<area>;<s>"` | With `record`, selects `<area>` (`x,y,w,h`, `full` or `window`, where `window` is a window UltraShot creates), records for `s` seconds and stops. With `record-panel`, runs a demo without capturing. |
| `ULTRASHOT_DEBUG_AUTOPAUSE=1`, `ULTRASHOT_DEBUG_AUTODISCARD=1` | The automated recording pauses at 1/3 and resumes at 2/3, or is discarded at the end. |
| `ULTRASHOT_DEBUG_AUTOINTERRUPT=<ms>` | Halfway through, the stream acts as if it stopped by itself, and Stop is pressed `ms` later. |
| `ULTRASHOT_DEBUG_AUTOSTOP_MS=<ms>` | Presses Record Screen `ms` after committing the selection, while the recorder is still starting. |
| `ULTRASHOT_DEBUG_WINDOWMODE="x,y"` | With `record-panel`, turns on window-pick mode hovering that point. |

Automation runs should use the fake snapshot, the debug pasteboard and a scratch export
folder. If a run captures the real screen, check the results from logs and file metadata
and never open the images.
