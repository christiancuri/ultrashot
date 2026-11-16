import AppKit

/// A rounded glass strip of ``StripButton``s laid out along one axis, with optional
/// separators. Sized by its content (``preferredSize``).
final class StripView: NSView {
    enum Item {
        case button(StripButton)
        case separator
    }

    static let padding: CGFloat = 4
    static let spacing: CGFloat = 2
    static let separatorLength: CGFloat = 9

    let orientation: NSUserInterfaceLayoutOrientation
    private let items: [Item]
    private let glass = NSGlassEffectView()
    private let content = NSView()

    init(orientation: NSUserInterfaceLayoutOrientation, items: [Item]) {
        self.orientation = orientation
        self.items = items
        super.init(frame: .zero)
        glass.cornerRadius = 11
        // A light tint keeps the symbols legible over busy screenshots.
        glass.tintColor = NSColor.windowBackgroundColor.withAlphaComponent(0.7)
        glass.contentView = content
        addSubview(glass)
        for item in items {
            switch item {
            case .button(let button): content.addSubview(button)
            case .separator: content.addSubview(SeparatorView())
            }
        }
        setFrameSize(preferredSize)
        layoutItems()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var preferredSize: CGSize {
        let along = items.reduce(CGFloat(0)) { total, item in
            switch item {
            case .button: total + StripButton.side
            case .separator: total + Self.separatorLength
            }
        } + CGFloat(max(items.count - 1, 0)) * Self.spacing + Self.padding * 2
        let across = StripButton.side + Self.padding * 2
        return orientation == .vertical ? CGSize(width: across, height: along) : CGSize(width: along, height: across)
    }

    override func layout() {
        super.layout()
        layoutItems()
    }

    private func layoutItems() {
        glass.frame = bounds
        content.frame = glass.bounds
        let vertical = orientation == .vertical
        // Vertical strips read top to bottom.
        var cursor = vertical ? bounds.height - Self.padding : Self.padding
        for view in content.subviews {
            let length = view is SeparatorView ? Self.separatorLength : StripButton.side
            if vertical {
                cursor -= length
                view.frame = CGRect(x: Self.padding, y: cursor, width: StripButton.side, height: length)
                cursor -= Self.spacing
            } else {
                view.frame = CGRect(x: cursor, y: Self.padding, width: length, height: StripButton.side)
                cursor += length + Self.spacing
            }
        }
    }

    /// Hairline separator centered in its slot.
    private final class SeparatorView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            NSColor.separatorColor.setFill()
            if bounds.width > bounds.height {
                CGRect(x: 4, y: (bounds.height - 1) / 2, width: bounds.width - 8, height: 1).fill()
            } else {
                CGRect(x: (bounds.width - 1) / 2, y: 4, width: 1, height: bounds.height - 8).fill()
            }
        }
    }
}
