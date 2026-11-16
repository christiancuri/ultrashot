import AnnotateKit
import AppKit

/// A compact toolbar button: an SF Symbol (or a color swatch) on a rounded square that
/// fills with the accent color when active. Never takes keyboard focus, so the selection
/// view keeps receiving Esc, ↩ and the tool shortcuts.
final class StripButton: NSView {
    enum Content: Equatable {
        case symbol(String)
        case color(RGBAColor)
    }

    static let side: CGFloat = 28

    var content: Content {
        didSet { needsDisplay = true }
    }

    var isActive = false {
        didSet {
            needsDisplay = true
            setAccessibilitySelected(isActive)
        }
    }

    var isEnabled = true {
        didSet {
            needsDisplay = true
            setAccessibilityEnabled(isEnabled)
        }
    }

    var action: ((StripButton) -> Void)?

    private var isHovered = false
    private var isPressed = false
    private var trackingArea: NSTrackingArea?

    init(content: Content, toolTip: String, action: ((StripButton) -> Void)? = nil) {
        self.content = content
        self.action = action
        super.init(frame: CGRect(x: 0, y: 0, width: Self.side, height: Self.side))
        self.toolTip = toolTip
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(toolTip)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: Self.side, height: Self.side) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if inside != isPressed {
            isPressed = inside
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        let fire = isPressed && isEnabled && bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        needsDisplay = true
        if fire { action?(self) }
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        action?(self)
        return true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let plate = NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7)
        if isActive {
            NSColor.controlAccentColor.setFill()
            plate.fill()
        } else if isEnabled, isPressed || isHovered {
            NSColor.labelColor.withAlphaComponent(isPressed ? 0.18 : 0.09).setFill()
            plate.fill()
        }

        switch content {
        case .symbol(let name):
            drawSymbol(name)
        case .color(let color):
            drawSwatch(color)
        }
    }

    private func drawSymbol(_ name: String) {
        let tint: NSColor = isActive ? .white : (isEnabled ? .labelColor : .tertiaryLabelColor)
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [tint]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return }
        let size = image.size
        let rect = CGRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        ).integral
        image.draw(in: rect)
    }

    private func drawSwatch(_ color: RGBAColor) {
        let circle = bounds.insetBy(dx: 6, dy: 6)
        let path = NSBezierPath(ovalIn: circle)
        color.nsColor.setFill()
        path.fill()
        // Hairline ring so white and black read on any material.
        NSColor.labelColor.withAlphaComponent(0.35).setStroke()
        let ring = NSBezierPath(ovalIn: circle.insetBy(dx: 0.5, dy: 0.5))
        ring.lineWidth = 1
        ring.stroke()
    }
}
