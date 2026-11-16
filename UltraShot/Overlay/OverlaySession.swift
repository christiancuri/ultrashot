import AppKit

/// One ``OverlayWindow`` + ``SelectionView`` per screen, presented and closed together.
///
/// Usage:
///
///     let session = OverlaySession(mode: .create) { screen in frozenImages[screen.displayID] }
///     session.onCommit = { view, rect in … crop … ; session.close() }
///     session.onCancel = { … }          // the session is already closed
///     session.show()
///
/// The session installs every callback of its views and forwards them with the view, so
/// set the session-level handlers instead of the views' own `onCancel`, `onCommit`, etc.
/// Other view properties (``SelectionView/selection``, ``SelectionView/highlightRect``,
/// accessory views) are free to use.
///
/// Routing: once a drag starts on one screen, the other screens drop their selection. Esc
/// on any screen cancels the whole session, as does a display configuration change.
@MainActor
final class OverlaySession {
    typealias BackgroundProvider = @MainActor (NSScreen) -> CGImage?

    /// Views and windows by display id (`NSScreen.displayID`).
    private(set) var views: [CGDirectDisplayID: SelectionView] = [:]
    private(set) var windows: [CGDirectDisplayID: OverlayWindow] = [:]
    private(set) var isOpen = false

    // MARK: Callbacks (forwarded from the views)

    var onSelectionChanged: ((SelectionView, CGRect?) -> Void)?
    var onCommit: ((SelectionView, CGRect) -> Void)?
    /// Esc or a display change. The session is closed before this is called.
    var onCancel: (() -> Void)?
    var onMouseMoved: ((SelectionView, CGPoint) -> Void)?
    var onClick: ((SelectionView, CGPoint) -> Void)?
    /// Sees every key down first; return `true` when consumed.
    var onKeyDown: ((SelectionView, NSEvent) -> Bool)?

    private let mode: SelectionView.Mode
    private let screens: [NSScreen]
    private let background: BackgroundProvider?
    private var screenObserver: (any NSObjectProtocol)?

    /// - Parameters:
    ///   - mode: the initial mode of every view (change per view later if needed).
    ///   - screens: the screens to cover, all of them by default.
    ///   - background: the frozen image for each screen, `nil` for a live (dimmed) screen.
    init(mode: SelectionView.Mode, screens: [NSScreen] = NSScreen.screens, background: BackgroundProvider? = nil) {
        self.mode = mode
        self.screens = screens
        self.background = background
    }

    /// The view on `screen`.
    func view(for screen: NSScreen) -> SelectionView? {
        views[screen.displayID]
    }

    /// The screen `view` covers.
    func screen(for view: SelectionView) -> NSScreen? {
        (windows.values.first { $0.contentView === view })?.targetScreen
    }

    /// The view with a selection, if any (at most one has one at a time).
    var activeView: SelectionView? {
        views.values.first { $0.selection != nil }
    }

    /// Creates the windows and brings them up; the one under the pointer becomes key.
    func show() {
        guard !isOpen else { return }
        isOpen = true
        for screen in screens {
            let window = OverlayWindow(screen: screen)
            let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.mode = mode
            view.scale = screen.backingScaleFactor
            view.backgroundImage = background?(screen)
            install(view)
            window.contentView = view
            windows[screen.displayID] = window
            views[screen.displayID] = view
            window.orderFrontRegardless()
        }
        let mouse = NSEvent.mouseLocation
        let keyWindow = windows.values.first { $0.targetScreen.frame.contains(mouse) } ?? windows.values.first
        keyWindow?.present()
        if let view = keyWindow?.contentView { keyWindow?.makeFirstResponder(view) }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                Log.app.notice("display configuration changed: cancelling overlay")
                self?.cancel()
            }
        }
        Log.app.debug("overlay session shown on \(self.screens.count) screen(s)")
    }

    /// Removes every window. Safe to call more than once.
    func close() {
        guard isOpen else { return }
        isOpen = false
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        for window in windows.values {
            window.orderOut(nil)
            window.close()
        }
        windows = [:]
        views = [:]
    }

    /// Closes the session and calls ``onCancel``.
    func cancel() {
        guard isOpen else { return }
        close()
        onCancel?()
    }

    // MARK: - Private

    private func install(_ view: SelectionView) {
        view.onCancel = { [weak self] in self?.cancel() }
        view.onInteractionBegan = { [weak self, weak view] in
            guard let self, let view else { return }
            for other in views.values where other !== view {
                other.clearSelection(notify: true)
            }
        }
        view.onSelectionChanged = { [weak self, weak view] rect in
            guard let self, let view else { return }
            onSelectionChanged?(view, rect)
        }
        view.onCommit = { [weak self, weak view] rect in
            guard let self, let view else { return }
            onCommit?(view, rect)
        }
        view.onMouseMoved = { [weak self, weak view] point in
            guard let self, let view else { return }
            onMouseMoved?(view, point)
        }
        view.onClick = { [weak self, weak view] point in
            guard let self, let view else { return }
            onClick?(view, point)
        }
        view.onKeyDown = { [weak self, weak view] event in
            guard let self, let view else { return false }
            return onKeyDown?(view, event) ?? false
        }
    }
}
