import AppKit

/// The shared selection surface used by capture, recording and annotation: one per screen,
/// inside an ``OverlayWindow``.
///
/// **Coordinates:** the view is *not* flipped and fills its screen, so every point and rect
/// (``selection``, ``highlightRect``, callback arguments) is in points relative to
/// `screen.frame.origin`, y up — AppKit's convention. Use
/// `NSScreen.globalTopLeftRect(fromLocal:)` for ScreenCaptureKit and
/// `SelectionGeometry.imagePixelRect(for:viewHeight:scale:)` to crop ``backgroundImage``.
///
/// **Modes:**
/// - ``Mode/create``: a drag draws a new rect; releasing the mouse commits it right away
///   through ``onCommit``. A click without a drag calls ``onClick`` (window capture).
/// - ``Mode/adjust``: the selection shows 8 handles; drag a handle to resize, drag inside to
///   move, drag outside to draw a new one. ↩ or a double-click inside commits through
///   ``onCommit``. Arrow keys nudge it by 1 pt (10 pt with ⇧).
///
/// In both modes ⇧ constrains a new or corner-resized selection to a square, the selection
/// stays inside the screen, Esc calls ``onCancel``, and ``onKeyDown`` sees every key first.
///
/// Toolbars and other controls go in with ``addAccessoryView(_:)``; they stay above the
/// drawing and receive their own mouse events.
final class SelectionView: NSView {
    enum Mode: Sendable {
        case create
        case adjust
    }

    // MARK: Configuration

    var mode: Mode = .create {
        didSet { refresh() }
    }

    /// The frozen screen image, drawn to fill the view. `nil` shows the live screen through
    /// a lighter dim.
    var backgroundImage: CGImage? {
        didSet {
            renderer.backgroundImage = backgroundImage
            refresh()
        }
    }

    /// Tinted rect, e.g. the window under the pointer in window capture. Undimmed while
    /// there is no selection.
    var highlightRect: CGRect? {
        didSet { refresh() }
    }

    /// Pixels per point for the size label and pixel snapping. `nil` = the window's backing scale.
    var scale: CGFloat?

    /// Smallest selection side in points. Smaller drags in create mode do not commit.
    var minimumSize: CGFloat = 4

    var showsSizeLabel = true {
        didSet { refresh() }
    }

    /// Opacity of the black dim outside the selection. `nil` = 0.4 with a background, 0.25 without.
    var dimAlpha: CGFloat? {
        didSet { refresh() }
    }

    // MARK: Callbacks

    /// The user changed the selection (drawing, moving, resizing, nudging, clearing).
    /// Not called for programmatic changes to ``selection``.
    var onSelectionChanged: ((CGRect?) -> Void)?
    /// Create mode: mouse up after a drag. Adjust mode: ↩ or double-click inside.
    var onCommit: ((CGRect) -> Void)?
    /// Esc.
    var onCancel: (() -> Void)?
    /// The pointer moved (no button down).
    var onMouseMoved: ((CGPoint) -> Void)?
    /// Mouse down and up without dragging (outside the selection in adjust mode).
    var onClick: ((CGPoint) -> Void)?
    /// Sees every key down first; return `true` when consumed.
    var onKeyDown: ((NSEvent) -> Bool)?
    /// A drag started on this view (``OverlaySession`` clears the other screens).
    var onInteractionBegan: (() -> Void)?

    // MARK: State

    /// The current selection. Setting it clamps it to the view and does not call
    /// ``onSelectionChanged``.
    var selection: CGRect? {
        get { currentSelection }
        set {
            currentSelection = newValue.flatMap { SelectionGeometry.clamp($0, to: bounds) }
            refresh()
        }
    }

    var effectiveScale: CGFloat {
        scale ?? window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    let renderer: SelectionRenderer
    var currentSelection: CGRect?
    var drag: DragOperation?
    var mouseDownPoint: CGPoint?
    var didDrag = false
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        renderer = SelectionRenderer(frame: NSRect(origin: .zero, size: frameRect.size))
        super.init(frame: frameRect)
        renderer.autoresizingMask = [.width, .height]
        addSubview(renderer)
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: API

    /// Adds a control (toolbar, panel) above the selection drawing.
    func addAccessoryView(_ view: NSView) {
        addSubview(view, positioned: .above, relativeTo: nil)
    }

    /// Clears the selection; with `notify`, also calls ``onSelectionChanged``.
    func clearSelection(notify: Bool) {
        guard currentSelection != nil else { return }
        drag = nil
        if notify {
            setSelectionFromUser(nil)
        } else {
            selection = nil
        }
    }

    /// Updates the selection on behalf of the user (calls ``onSelectionChanged``).
    func setSelectionFromUser(_ rect: CGRect?) {
        currentSelection = rect.flatMap { SelectionGeometry.clamp($0, to: bounds) }
        refresh()
        onSelectionChanged?(currentSelection)
    }

    func refresh() {
        let alpha = dimAlpha ?? (backgroundImage == nil ? 0.25 : 0.4)
        var label: String?
        if showsSizeLabel, let selection = currentSelection {
            let scale = effectiveScale
            label = "\(Int((selection.width * scale).rounded())) × \(Int((selection.height * scale).rounded()))"
        }
        renderer.apply(SelectionRenderer.State(
            selection: currentSelection,
            highlight: highlightRect,
            showsHandles: mode == .adjust && currentSelection != nil,
            dimAlpha: alpha,
            sizeLabel: label
        ))
    }

    // MARK: Responder and tracking

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        refresh()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        // Multi-screen: keyboard focus follows the pointer so Esc and ↩ work everywhere.
        if window?.isKeyWindow == false { window?.makeKey() }
        window?.makeFirstResponder(self)
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        updateCursor(at: point)
        onMouseMoved?(point)
    }

    func updateCursor(at point: CGPoint) {
        if let hit = hitTest(convert(point, to: superview)), hit !== self {
            NSCursor.arrow.set()
            return
        }
        if case .moving = drag {
            NSCursor.closedHand.set()
            return
        }
        if case .resizing(let handle, _) = drag {
            handle.cursor.set()
            return
        }
        guard mode == .adjust, let selection = currentSelection else {
            NSCursor.crosshair.set()
            return
        }
        if let handle = SelectionGeometry.handle(at: point, in: selection, tolerance: Self.handleTolerance) {
            handle.cursor.set()
        } else if selection.contains(point) {
            NSCursor.openHand.set()
        } else {
            NSCursor.crosshair.set()
        }
    }

    static let handleTolerance: CGFloat = 8

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true { return }
        switch Int(event.keyCode) {
        case KeyCode.escape:
            onCancel?()
        case KeyCode.returnKey, KeyCode.enter:
            if mode == .adjust, let selection = currentSelection { onCommit?(selection) }
        case KeyCode.leftArrow, KeyCode.rightArrow, KeyCode.downArrow, KeyCode.upArrow:
            nudge(event)
        default:
            super.keyDown(with: event)
        }
    }

    private func nudge(_ event: NSEvent) {
        guard mode == .adjust, let selection = currentSelection else { return }
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        let delta: CGVector = switch Int(event.keyCode) {
        case KeyCode.leftArrow: CGVector(dx: -step, dy: 0)
        case KeyCode.rightArrow: CGVector(dx: step, dy: 0)
        case KeyCode.downArrow: CGVector(dx: 0, dy: -step)
        default: CGVector(dx: 0, dy: step)
        }
        setSelectionFromUser(SelectionGeometry.move(selection, by: delta, in: bounds))
    }

    /// Virtual key codes (Carbon `kVK_*`).
    enum KeyCode {
        static let returnKey = 36
        static let escape = 53
        static let enter = 76
        static let leftArrow = 123
        static let rightArrow = 124
        static let downArrow = 125
        static let upArrow = 126
    }
}
