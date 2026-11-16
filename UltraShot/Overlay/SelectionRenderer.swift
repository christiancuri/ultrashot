import AppKit
import QuartzCore

/// Layer-hosting view that draws everything a ``SelectionView`` shows: the frozen
/// background, the dimming outside the selection, the window highlight, the selection
/// border with its handles and the size label.
///
/// Built from Core Animation layers so dragging a selection over a full-resolution
/// screenshot only updates a few shape paths. It never takes mouse events
/// (``hitTest(_:)`` returns `nil`), so they reach the ``SelectionView`` underneath.
final class SelectionRenderer: NSView {
    struct State: Equatable {
        var selection: CGRect?
        var highlight: CGRect?
        var showsHandles = false
        var dimAlpha: CGFloat = 0.4
        /// Text of the size label, `nil` hides it.
        var sizeLabel: String?
    }

    static let handleDiameter: CGFloat = 8

    private let rootLayer = CALayer()
    private let backgroundLayer = CALayer()
    private let dimLayer = CAShapeLayer()
    private let highlightLayer = CAShapeLayer()
    private let outlineLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let handlesLayer = CAShapeLayer()
    private let labelLayer = CALayer()
    private let labelTextLayer = CATextLayer()
    private var state = State()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Layer hosting: assign the layer before turning `wantsLayer` on.
        layer = rootLayer
        wantsLayer = true
        layerContentsRedrawPolicy = .never

        backgroundLayer.contentsGravity = .resize
        dimLayer.fillRule = .evenOdd
        highlightLayer.fillColor = NSColor.systemBlue.withAlphaComponent(0.18).cgColor
        highlightLayer.strokeColor = NSColor.systemBlue.withAlphaComponent(0.9).cgColor
        highlightLayer.lineWidth = 2
        outlineLayer.fillColor = nil
        outlineLayer.strokeColor = NSColor.black.withAlphaComponent(0.35).cgColor
        outlineLayer.lineWidth = 3
        borderLayer.fillColor = nil
        borderLayer.strokeColor = NSColor.white.cgColor
        borderLayer.lineWidth = 1
        handlesLayer.fillColor = NSColor.white.cgColor
        handlesLayer.strokeColor = NSColor.black.withAlphaComponent(0.45).cgColor
        handlesLayer.lineWidth = 1
        labelLayer.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        labelLayer.cornerRadius = 4
        labelLayer.isHidden = true
        labelTextLayer.alignmentMode = .center
        labelTextLayer.actions = Self.noAnimations
        labelLayer.addSublayer(labelTextLayer)

        for sublayer in [backgroundLayer, dimLayer, highlightLayer, outlineLayer, borderLayer, handlesLayer, labelLayer] {
            sublayer.actions = Self.noAnimations
            rootLayer.addSublayer(sublayer)
        }
        rootLayer.actions = Self.noAnimations
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    var backgroundImage: CGImage? {
        didSet { backgroundLayer.contents = backgroundImage }
    }

    override func layout() {
        super.layout()
        apply(state, force: true)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        for sublayer in rootLayer.sublayers ?? [] { sublayer.contentsScale = scale }
        labelTextLayer.contentsScale = scale
        apply(state, force: true)
    }

    func apply(_ newState: State, force: Bool = false) {
        guard force || newState != state else { return }
        state = newState
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        backgroundLayer.frame = bounds
        for shape in [dimLayer, highlightLayer, outlineLayer, borderLayer, handlesLayer] { shape.frame = bounds }

        let dim = CGMutablePath()
        dim.addRect(bounds)
        if let hole = state.selection ?? state.highlight { dim.addRect(hole) }
        dimLayer.path = dim
        dimLayer.fillColor = NSColor.black.withAlphaComponent(state.dimAlpha).cgColor

        highlightLayer.path = state.highlight.map { CGPath(rect: $0.insetBy(dx: 1, dy: 1), transform: nil) }

        if let selection = state.selection {
            let border = CGPath(rect: selection.insetBy(dx: -0.5, dy: -0.5), transform: nil)
            outlineLayer.path = border
            borderLayer.path = border
        } else {
            outlineLayer.path = nil
            borderLayer.path = nil
        }

        handlesLayer.path = state.showsHandles ? state.selection.map(Self.handlesPath) : nil
        layoutLabel()
    }

    private static func handlesPath(for rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let radius = handleDiameter / 2
        for handle in SelectionHandle.allCases {
            let center = handle.point(in: rect)
            path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: handleDiameter, height: handleDiameter))
        }
        return path
    }

    /// Above the selection's top-left corner; just inside it when there is no room above.
    private func layoutLabel() {
        guard let text = state.sizeLabel, let selection = state.selection else {
            labelLayer.isHidden = true
            return
        }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.white])
        let textSize = string.size()
        let padding = CGSize(width: 6, height: 3)
        let textFrameSize = CGSize(width: ceil(textSize.width), height: ceil(textSize.height))
        let size = CGSize(width: textFrameSize.width + padding.width * 2, height: textFrameSize.height + padding.height * 2)
        let gap: CGFloat = 6
        var origin = CGPoint(x: selection.minX, y: selection.maxY + gap)
        if origin.y + size.height > bounds.maxY {
            origin.y = selection.maxY - gap - size.height
        }
        origin.x = min(max(origin.x, bounds.minX), bounds.maxX - size.width)
        origin.y = max(origin.y, bounds.minY)
        labelTextLayer.string = string
        labelLayer.frame = CGRect(origin: origin, size: size)
        labelTextLayer.frame = CGRect(origin: CGPoint(x: padding.width, y: padding.height), size: textFrameSize)
        labelLayer.isHidden = false
    }

    private static let noAnimations: [String: any CAAction] = [
        "position": NSNull(), "bounds": NSNull(), "frame": NSNull(), "path": NSNull(),
        "contents": NSNull(), "hidden": NSNull(), "fillColor": NSNull(), "string": NSNull(),
    ]
}
