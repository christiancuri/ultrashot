import AppKit
import CaptureKit

/// One frozen selection on every screen: area drag (create mode, release commits) and
/// window mode (Space toggles; hover highlights the window under the pointer, click picks it).
///
/// The session only decides *what* was picked; ``CaptureCoordinator`` captures and delivers.
@MainActor
final class CaptureSession {
    enum Intent {
        case area
        case window
        case annotate
    }

    enum Result {
        /// An area in `screen`'s view coordinates (points from the screen origin, y up).
        case area(screen: NSScreen, rect: CGRect, snapshot: DisplaySnapshot)
        /// A window, picked on `screen`.
        case window(WindowInfo, screen: NSScreen)
        case cancelled
    }

    let intent: Intent
    /// Called once, after the overlay has closed.
    var onFinish: ((Result) -> Void)?

    private let snapshots: [CGDirectDisplayID: DisplaySnapshot]
    private let overlay: OverlaySession
    /// On-screen windows, front to back, taken when the session opens (the screen is frozen).
    private let windows: [WindowInfo]
    private var isWindowMode: Bool
    private var hoveredWindow: WindowInfo?
    private var finished = false

    init(intent: Intent, snapshots: [CGDirectDisplayID: DisplaySnapshot]) {
        self.intent = intent
        self.snapshots = snapshots
        isWindowMode = intent == .window
        windows = WindowList.onScreen(excludingPID: ProcessInfo.processInfo.processIdentifier)
        let screens = NSScreen.screens.filter { snapshots[$0.displayID] != nil }
        overlay = OverlaySession(mode: .create, screens: screens) { screen in
            snapshots[screen.displayID]?.image
        }
        overlay.onCommit = { [weak self] view, rect in self?.commitArea(view: view, rect: rect) }
        overlay.onCancel = { [weak self] in self?.finish(.cancelled, closeOverlay: false) }
        overlay.onMouseMoved = { [weak self] view, point in self?.mouseMoved(in: view, at: point) }
        overlay.onClick = { [weak self] view, point in self?.click(in: view, at: point) }
        overlay.onKeyDown = { [weak self] view, event in self?.keyDown(in: view, event: event) ?? false }
    }

    func show() {
        overlay.show()
        if isWindowMode { refreshHighlight(at: NSEvent.mouseLocation) }
        runDebugAutomation()
    }

    /// Closes the overlay without a result (e.g. app quitting).
    func cancel() {
        finish(.cancelled, closeOverlay: true)
    }

    // MARK: - Area

    private func commitArea(view: SelectionView, rect: CGRect) {
        guard let screen = overlay.screen(for: view), let snapshot = snapshots[screen.displayID] else {
            finish(.cancelled, closeOverlay: true)
            return
        }
        finish(.area(screen: screen, rect: rect, snapshot: snapshot), closeOverlay: true)
    }

    // MARK: - Window mode

    private func keyDown(in view: SelectionView, event: NSEvent) -> Bool {
        guard event.keyCode == 49, intent != .annotate else { return false } // Space
        isWindowMode.toggle()
        Log.capture.info("window mode \(self.isWindowMode ? "on" : "off", privacy: .public)")
        if isWindowMode {
            for view in overlay.views.values { view.clearSelection(notify: false) }
            refreshHighlight(at: NSEvent.mouseLocation)
        } else {
            setHighlight(nil)
        }
        return true
    }

    private func mouseMoved(in view: SelectionView, at point: CGPoint) {
        guard isWindowMode, let screen = overlay.screen(for: view) else { return }
        refreshHighlight(at: CGPoint(x: point.x + screen.frame.minX, y: point.y + screen.frame.minY))
        NSCursor.pointingHand.set()
    }

    private func click(in view: SelectionView, at point: CGPoint) {
        guard isWindowMode, let screen = overlay.screen(for: view) else { return }
        refreshHighlight(at: CGPoint(x: point.x + screen.frame.minX, y: point.y + screen.frame.minY))
        guard let window = hoveredWindow else { return }
        finish(.window(window, screen: screen), closeOverlay: true)
    }

    /// Highlights the topmost window under `appKitPoint` (global AppKit points).
    private func refreshHighlight(at appKitPoint: CGPoint) {
        let cgPoint = CGPoint(x: appKitPoint.x, y: NSScreen.primaryScreenHeight - appKitPoint.y)
        setHighlight(WindowList.topmost(at: cgPoint, in: windows))
    }

    private func setHighlight(_ window: WindowInfo?) {
        hoveredWindow = window
        for (displayID, view) in overlay.views {
            guard let window, let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else {
                view.highlightRect = nil
                continue
            }
            let local = screen.localRect(fromGlobalTopLeft: window.frameCG)
            view.highlightRect = local.intersects(view.bounds) ? local : nil
        }
    }

    // MARK: - Finish

    private func finish(_ result: Result, closeOverlay: Bool) {
        guard !finished else { return }
        finished = true
        if closeOverlay { overlay.close() }
        onFinish?(result)
    }

    // MARK: - Debug automation

    private func runDebugAutomation() {
        if intent != .window, let rect = DebugAutomation.autoSelectRect {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard let self, !finished, let screen = NSScreen.screens.first, let view = overlay.view(for: screen) else { return }
                view.selection = rect
                guard let selection = view.selection else { return }
                Log.capture.info("debug autoselect \(String(describing: selection), privacy: .public)")
                try? await Task.sleep(for: .milliseconds(400))
                commitArea(view: view, rect: selection)
            }
        }
        if isWindowMode, DebugAutomation.autoWindow {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard let self, !finished, let window = windows.first else {
                    Log.capture.error("debug autowindow: no window")
                    return
                }
                setHighlight(window)
                Log.capture.info("debug autowindow \(window.id) \(String(describing: window.frameCG), privacy: .public)")
                try? await Task.sleep(for: .milliseconds(600))
                let center = CGPoint(x: window.frameCG.midX, y: NSScreen.primaryScreenHeight - window.frameCG.midY)
                let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.screens[0]
                finish(.window(window, screen: screen), closeOverlay: true)
            }
        }
    }
}
