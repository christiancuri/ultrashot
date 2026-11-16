import AppKit

/// Solid dark rounded background shared by the record panel and the HUD. Solid rather than
/// vibrant: a behind-window material would sample whatever is under the overlay.
final class RecordingPanelBackground: NSView {
    init(cornerRadius: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor(white: 0.13, alpha: 0.96).cgColor
        layer?.borderColor = NSColor(white: 1, alpha: 0.12).cgColor
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

/// Borderless SF Symbol button for the dark panels. Toggle buttons get a light fill while on.
final class RecordingIconButton: NSButton {
    private let isToggle: Bool

    init(symbol: String, label: String, toggle: Bool, side: CGFloat = 30) {
        isToggle = toggle
        super.init(frame: .zero)
        setButtonType(toggle ? .pushOnPushOff : .momentaryChange)
        isBordered = false
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        setSymbol(symbol)
        toolTip = label
        setAccessibilityLabel(label)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: side),
            heightAnchor.constraint(equalToConstant: side - 4),
        ])
        refreshAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func setSymbol(_ name: String) {
        image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    override var state: NSControl.StateValue {
        didSet { refreshAppearance() }
    }

    override var isEnabled: Bool {
        didSet { refreshAppearance() }
    }

    /// Tint for the symbol; `nil` uses the default white.
    var tint: NSColor? {
        didSet { refreshAppearance() }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func refreshAppearance() {
        let isOn = isToggle && state == .on
        layer?.backgroundColor = isOn ? NSColor(white: 1, alpha: 0.18).cgColor : NSColor.clear.cgColor
        let base = tint ?? NSColor.white
        contentTintColor = isEnabled ? (isOn || !isToggle ? base : base.withAlphaComponent(0.6)) : base.withAlphaComponent(0.3)
    }
}
