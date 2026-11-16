import AppKit

/// The floating window of one Quick Access thumbnail: borderless, non-activating, above
/// normal windows on every Space (fullscreen apps included), and hidden from captures.
final class ThumbnailPanel: NSPanel {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        identifier = NSUserInterfaceItemIdentifier("ultrashot.thumbnail")
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // Debug builds can opt in to `screencapture -l` for visual checks.
        sharingType = DebugLaunchHooks.capturableOverlays ? .readOnly : .none
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isMovable = false
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .none
    }

    /// Key while hovered, so ⌘C, ⌘S, ⌘W, ⌘E, Space and Esc reach the thumbnail.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Gives keyboard focus back to the app the user was in (the panel never activates
    /// UltraShot, so ordering it out and back in returns key status to that app).
    func relinquishKey() {
        guard isKeyWindow, isVisible else { return }
        orderOut(nil)
        orderFrontRegardless()
    }
}

/// A light, rounded control drawn over the dimmed thumbnail: a text pill (Copy, Save) or a
/// small circle with an SF Symbol (close, annotate).
final class ThumbnailButton: NSView {
    enum Style {
        case pill(String)
        case circle(symbol: String, label: String)
    }

    let style: Style
    var action: (() -> Void)?
    private var isPressed = false {
        didSet { needsDisplay = true }
    }

    init(_ style: Style, action: (() -> Void)? = nil) {
        self.style = style
        self.action = action
        super.init(frame: CGRect(origin: .zero, size: Self.size(for: style)))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        switch style {
        case let .pill(title): setAccessibilityLabel(title)
        case let .circle(_, label): setAccessibilityLabel(label); toolTip = label
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    static func size(for style: Style) -> CGSize {
        switch style {
        case let .pill(title):
            let width = (title as NSString).size(withAttributes: [.font: font]).width
            return CGSize(width: (width + 32).rounded(), height: 26)
        case .circle:
            return CGSize(width: 22, height: 22)
        }
    }

    private static let font = NSFont.systemFont(ofSize: 13, weight: .semibold)

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let fill = NSColor(white: isPressed ? 0.72 : 0.86, alpha: 0.96)
        fill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        switch style {
        case let .pill(title):
            let attributes: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: NSColor(white: 0.1, alpha: 1)]
            let size = (title as NSString).size(withAttributes: attributes)
            (title as NSString).draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
        case let .circle(symbol, label):
            let configuration = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
                .applying(.init(paletteColors: [NSColor(white: 0.1, alpha: 1)]))
            guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
                .withSymbolConfiguration(configuration) else { return }
            let rect = CGRect(
                x: (bounds.width - image.size.width) / 2, y: (bounds.height - image.size.height) / 2,
                width: image.size.width, height: image.size.height
            )
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
    }

    override func mouseDragged(with event: NSEvent) {
        isPressed = bounds.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        if inside { action?() }
    }

    override func accessibilityPerformPress() -> Bool {
        action?()
        return true
    }
}
