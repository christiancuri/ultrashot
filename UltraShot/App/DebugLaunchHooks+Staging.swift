#if DEBUG
import AnnotateKit
import AppKit

/// Staging helpers for README screenshots (Debug builds only).
///
/// `ULTRASHOT_DEBUG_BACKDROP=1` (with `ULTRASHOT_DEBUG_FAKE_SNAPSHOT`): before the surface
/// opens, covers the main screen with a window showing the fake snapshot, at the normal
/// window level and ignoring the mouse. UltraShot's own glass windows (Settings, Quick
/// Access) then refract the fake desktop instead of whatever is really behind them.
///
/// `ULTRASHOT_DEBUG_OVERLAY_SELECTION="x,y,w,h"` with `record-panel`: a second after the
/// overlay opens, selects that rect (main screen points, origin bottom-left) as if dragged,
/// so the pre-record panel follows it.
///
/// `ULTRASHOT_DEBUG_THUMBNAIL_MENU=1`: two seconds after the first Quick Access thumbnail
/// appears, opens the newest screenshot thumbnail's context menu over it. The menu tracks
/// until the app is killed (`ULTRASHOT_DEBUG_QUIT_AFTER` cannot fire during menu tracking).
///
/// `ULTRASHOT_DEBUG_ANNOTATE_JSON=<path>`: once an annotation session
/// is up (`annotate-sample`, or `capture-annotate` after the auto-selection), adds the
/// annotations decoded from that file and activates the arrow tool with nothing selected.
/// Used to stage README screenshots over a designed fake desktop.
///
/// The file is a JSON array of `Annotation` in its synthesized `Codable` form, with every
/// coordinate in points relative to the selection's BOTTOM-LEFT corner (y grows up), e.g.
///
///     [{"id": "<uuid>", "style": {"color": {"red": 1, "green": 0.18, "blue": 0.18, "alpha": 1}, "lineWidth": 4},
///       "kind": {"arrow": {"start": [300, 120], "end": [420, 260]}}}]
///
/// (`rectangle`/`ellipse`/`blur` take `{"_0": [[x, y], [w, h]]}`, `text` takes
/// `{"_0": {"string": …, "origin": [x, y], "fontSize": …}}` with `origin` at the text's
/// top-left corner, `counter` takes `{"center": [x, y], "number": n}`.)
@MainActor
private enum StagingState {
    static var backdrop: NSWindow?
}

extension DebugLaunchHooks {
    static func showBackdropIfRequested() {
        guard ProcessInfo.processInfo.environment["ULTRASHOT_DEBUG_BACKDROP"] == "1", useFakeSnapshot,
              let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let image = fakeSnapshotImage(size: screen.frame.size, scale: screen.backingScaleFactor)
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer?.contents = image
        view.layer?.contentsGravity = .resize
        window.contentView = view
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        StagingState.backdrop = window
        Log.app.info("backdrop shown")
    }

    static func scheduleRecordSelection(_ rect: CGRect?) {
        guard let rect, requestedSurface == "record-panel" else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1200))
            guard let screen = NSScreen.screens.first,
                  let view = NSApp.windows.lazy.compactMap({ $0.contentView?.firstSelectionView() }).first(where: { $0.window?.screen == screen }) else {
                Log.app.error("record selection: no selection view")
                return
            }
            view.setSelectionFromUser(rect.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY))
            Log.app.info("record selection: \(String(describing: rect), privacy: .public)")
        }
    }

    static func scheduleThumbnailMenu(model: AppModel) {
        guard ProcessInfo.processInfo.environment["ULTRASHOT_DEBUG_THUMBNAIL_MENU"] == "1" else { return }
        Task { @MainActor in
            for _ in 0..<100 where model.thumbnails.cards.isEmpty {
                try? await Task.sleep(for: .milliseconds(100))
            }
            try? await Task.sleep(for: .seconds(2))
            // `cards` is newest first.
            guard let card = model.thumbnails.cards.first(where: { $0.item.kind == .screenshot }) else {
                Log.app.error("thumbnail-menu: no thumbnail")
                return
            }
            let bounds = card.view.bounds
            Log.app.info("thumbnail-menu: opening")
            card.makeContextMenu().popUp(positioning: nil, at: CGPoint(x: bounds.midX, y: bounds.midY), in: card.view)
        }
    }

    static func scheduleAnnotationsFile(model: AppModel) {
        guard let path = ProcessInfo.processInfo.environment["ULTRASHOT_DEBUG_ANNOTATE_JSON"], !path.isEmpty else { return }
        let url = URL(filePath: (path as NSString).expandingTildeInPath)
        Task { @MainActor in
            // Wait up to 10 s for a session with a selection.
            for _ in 0..<100 {
                if let session = model.annotation.session, session.canvas?.selectionInCanvas != nil {
                    // Let the toolbars settle before staging.
                    try? await Task.sleep(for: .milliseconds(300))
                    addAnnotations(from: url, to: session)
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            Log.app.error("annotate-json: no annotation session")
        }
    }

    private static func addAnnotations(from url: URL, to session: AnnotationSession) {
        guard let selection = session.canvas?.selectionInCanvas else { return }
        do {
            let annotations = try JSONDecoder().decode([Annotation].self, from: Data(contentsOf: url))
            let offset = CGVector(dx: selection.minX, dy: selection.minY)
            for annotation in annotations {
                session.editor.add(annotation.moved(by: offset))
            }
            session.editor.tool = .arrow
            session.editor.selectedID = nil
            Log.app.info("annotate-json: added \(annotations.count) annotations")
        } catch {
            Log.app.error("annotate-json: \(error.localizedDescription, privacy: .public)")
        }
    }
}
private extension NSView {
    func firstSelectionView() -> SelectionView? {
        if let view = self as? SelectionView { return view }
        for subview in subviews {
            if let found = subview.firstSelectionView() { return found }
        }
        return nil
    }
}
#endif
