import AppKit
import CaptureKit
import RecordingKit

/// What the user chose to record.
struct RecordingRequest {
    let target: RecordingConfiguration.Target
    let displayID: CGDirectDisplayID
    /// The recorded area in the screen's local coordinates (points from the screen origin, y up).
    let localArea: CGRect
    /// Output pixels per point.
    let scale: CGFloat
    let isFullscreen: Bool
}

/// The pre-record flow: a live (dimmed) adjust-mode overlay on every screen with the
/// ``RecordPanelView`` attached to the selection. Space toggles window pick mode (hover
/// highlights the topmost window, click picks it), ↩ or Record commits, Esc cancels.
@MainActor
final class RecordSelectionController {
    /// The user committed a selection or a window. The overlay is already closed.
    var onRecord: ((RecordingRequest) -> Void)?
    /// Esc or a display change. The overlay is already closed.
    var onCancel: (() -> Void)?

    private weak var model: AppModel?
    private let session: OverlaySession
    private let panel = RecordPanelView()
    private weak var host: SelectionView?
    private var windowMode = false
    private var windows: [WindowInfo] = []
    private var picked: WindowInfo?
    /// The app that was active before the overlay took focus; it gets it back afterwards.
    private var previousApp: NSRunningApplication?

    private static let spaceKeyCode = 49

    init(model: AppModel, background: OverlaySession.BackgroundProvider? = nil) {
        self.model = model
        session = OverlaySession(mode: .adjust, background: background)
        installHandlers()
        installPanelHandlers()
    }

    // MARK: API

    /// Shows the overlay, pre-selecting `initialArea` (global top-left points on `displayID`)
    /// when that display is still connected.
    func show(initialArea: CGRect?, displayID: CGDirectDisplayID?) {
        let frontmost = NSWorkspace.shared.frontmostApplication
        previousApp = frontmost?.processIdentifier == getpid() ? nil : frontmost
        session.show()
        if let initialArea, let displayID,
           let screen = NSScreen.screens.first(where: { $0.displayID == displayID }),
           let view = session.view(for: screen) {
            view.selection = screen.localRect(fromGlobalTopLeft: initialArea)
            attachPanel(to: view)
        } else {
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.screens.first
            if let screen, let view = session.view(for: screen) { attachPanel(to: view) }
        }
        refreshPanel()
    }

    /// The current selection (local points of its screen), if any.
    var selectedArea: CGRect? {
        session.activeView?.selection
    }

    func close() {
        panel.removeFromSuperview()
        session.close()
        restoreActiveApp()
    }

    /// The view and screen holding the selection (or the panel), for debug automation.
    func view(for screen: NSScreen) -> SelectionView? {
        session.view(for: screen)
    }

    /// Sets the selection programmatically (debug automation).
    func select(_ localRect: CGRect, on screen: NSScreen) {
        guard let view = session.view(for: screen) else { return }
        exitWindowMode()
        picked = nil
        for other in session.views.values where other !== view { other.clearSelection(notify: false) }
        view.selection = localRect
        attachPanel(to: view)
        refreshPanel()
    }

    /// Picks `window` as the recording target (click in window mode, or debug automation).
    func pick(_ window: WindowInfo, on screen: NSScreen) {
        guard let view = session.view(for: screen) else { return }
        exitWindowMode()
        for other in session.views.values where other !== view { other.clearSelection(notify: false) }
        view.selection = screen.localRect(fromGlobalTopLeft: window.frameCG)
        picked = view.selection == nil ? nil : window
        attachPanel(to: view)
        refreshPanel()
    }

    /// Commits the current selection, as ↩ does.
    func commit() {
        guard let view = session.activeView, let selection = view.selection else { return }
        commit(view: view, selection: selection)
    }

    #if DEBUG
    /// Turns on window pick mode and hovers `point` (local to `screen`), for screenshots.
    func debugHover(at point: CGPoint, on screen: NSScreen) {
        guard let view = session.view(for: screen) else { return }
        if !windowMode { toggleWindowMode() }
        highlightWindow(in: view, at: point)
    }
    #endif

    // MARK: Handlers

    private func installHandlers() {
        session.onSelectionChanged = { [weak self] view, _ in
            guard let self else { return }
            picked = nil // a manual edit turns a picked window back into an area
            if view.selection != nil {
                exitWindowMode() // dragging in window mode draws an area instead
                attachPanel(to: view)
            }
            refreshPanel()
        }
        session.onCommit = { [weak self] view, rect in
            self?.commit(view: view, selection: rect)
        }
        session.onCancel = { [weak self] in
            guard let self else { return }
            panel.removeFromSuperview()
            restoreActiveApp()
            onCancel?()
        }
        session.onMouseMoved = { [weak self] view, point in
            self?.highlightWindow(in: view, at: point)
        }
        session.onClick = { [weak self] view, point in
            self?.pickWindow(in: view, at: point)
        }
        session.onKeyDown = { [weak self] _, event in
            guard let self, Int(event.keyCode) == Self.spaceKeyCode else { return false }
            toggleWindowMode()
            return true
        }
    }

    private func installPanelHandlers() {
        panel.onSizeEntered = { [weak self] size in
            guard let self, let view = host else { return }
            picked = nil
            view.selection = RecordingGeometry.resized(view.selection, to: size, in: view.bounds, minimumSide: view.minimumSize)
            refreshPanel()
        }
        panel.onFullscreen = { [weak self] in
            guard let self, let view = host else { return }
            exitWindowMode()
            picked = nil
            view.selection = view.bounds
            refreshPanel()
        }
        panel.onToggleWindowMode = { [weak self] in self?.toggleWindowMode() }
        panel.onMicrophoneChanged = { [weak self] isOn in
            self?.model?.settings.recording.microphone = isOn
            self?.refreshPanel()
        }
        panel.onSystemAudioChanged = { [weak self] isOn in
            self?.model?.settings.recording.systemAudio = isOn
            self?.refreshPanel()
        }
        panel.onRecord = { [weak self] in self?.commit() }
        panel.onCancel = { [weak self] in self?.session.cancel() }
        panel.onFinishedEditing = { [weak self] in
            guard let view = self?.host else { return }
            view.window?.makeFirstResponder(view)
        }
    }

    private func restoreActiveApp() {
        previousApp?.activate()
        previousApp = nil
    }

    // MARK: Window mode

    private func toggleWindowMode() {
        if windowMode {
            exitWindowMode()
        } else {
            windowMode = true
            windows = WindowList.onScreen(excludingPID: getpid())
            picked = nil
            for view in session.views.values { view.clearSelection(notify: false) }
            Log.recording.debug("window pick mode: \(self.windows.count) windows")
        }
        refreshPanel()
    }

    private func exitWindowMode() {
        guard windowMode else { return }
        windowMode = false
        windows = []
        for view in session.views.values { view.highlightRect = nil }
    }

    private func window(in view: SelectionView, at point: CGPoint) -> (WindowInfo, NSScreen)? {
        guard windowMode, let screen = session.screen(for: view) else { return nil }
        let global = RecordingGeometry.globalTopLeftPoint(fromLocal: point, screenFrame: screen.frame, primaryScreenHeight: NSScreen.primaryScreenHeight)
        return WindowList.topmost(at: global, in: windows).map { ($0, screen) }
    }

    private func highlightWindow(in view: SelectionView, at point: CGPoint) {
        guard windowMode else { return }
        for other in session.views.values where other !== view { other.highlightRect = nil }
        view.highlightRect = window(in: view, at: point).map { $0.1.localRect(fromGlobalTopLeft: $0.0.frameCG) }
    }

    private func pickWindow(in view: SelectionView, at point: CGPoint) {
        guard let (window, screen) = self.window(in: view, at: point) else { return }
        Log.recording.info("picked window \(window.id) of \(window.ownerName, privacy: .public)")
        pick(window, on: screen)
    }

    // MARK: Panel

    private func attachPanel(to view: SelectionView) {
        if panel.superview !== view {
            panel.removeFromSuperview()
            view.addAccessoryView(panel)
            host = view
        }
    }

    private func refreshPanel() {
        let settings = model?.settings.recording
        let selection = host?.selection
        panel.update(RecordPanelView.State(
            selectionSize: selection?.size,
            windowMode: windowMode,
            windowPicked: picked != nil,
            microphone: settings?.microphone ?? false,
            systemAudio: settings?.systemAudio ?? false
        ))
        guard let view = host else { return }
        let size = panel.fittingSize
        let frame = selection.map { RecordingGeometry.place(size, near: $0, in: view.bounds).frame }
            ?? RecordingGeometry.placeWithoutAnchor(size, in: view.bounds)
        panel.frame = frame.integral
    }

    // MARK: Commit

    private func commit(view: SelectionView, selection: CGRect) {
        guard !windowMode, let screen = session.screen(for: view) else { return }
        let scale = model?.settings.recording.downscaleRetina == true ? 1 : screen.backingScaleFactor
        let fullscreen = picked == nil && RecordingGeometry.isFullscreen(selection, in: view.bounds)
        let request: RecordingRequest
        if let picked {
            request = RecordingRequest(
                target: .window(picked.id), displayID: screen.displayID,
                localArea: screen.localRect(fromGlobalTopLeft: picked.frameCG), scale: scale, isFullscreen: false
            )
        } else {
            let sourceRect = fullscreen ? nil : RecordingGeometry.displaySourceRect(fromLocal: selection, screenHeight: screen.frame.height)
            request = RecordingRequest(
                target: .display(screen.displayID, sourceRect: sourceRect), displayID: screen.displayID,
                localArea: selection, scale: scale, isFullscreen: fullscreen
            )
        }
        close()
        onRecord?(request)
    }
}
