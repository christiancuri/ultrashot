import AnnotateKit
import AppKit

/// Draws the annotations over the frozen image and turns mouse gestures into edits.
///
/// Lives inside the ``SelectionView`` as an accessory. Its `frame` is where the base image
/// is shown (the whole screen for a frozen screen, the centered image for a file) and its
/// `bounds` is the base image's canvas in points, so local coordinates are AnnotateKit
/// canvas points (unflipped, bottom-left) and AppKit scales a downsized image for free.
///
/// It only claims the mouse where ``PointerRouting`` says so (see ``hitTest(_:)``);
/// everywhere else events fall through to the selection view. Annotations are clipped to
/// the selection.
final class AnnotationCanvasView: NSView {
    let editor: AnnotationEditor
    /// The image annotations are drawn on and exported with.
    let baseImage: CGImage
    /// The selection in the superview's (selection view's) coordinates.
    var selectionProvider: () -> CGRect? = { nil }
    /// ⌘-shortcuts while not typing (⌘C, ⌘S, ⌘Z…); return `true` when handled.
    var onKeyEquivalent: ((NSEvent) -> Bool)?

    var gesture: Gesture?
    var mouseDownPoint: CGPoint?
    var didDrag = false
    var textEditing: TextEditing?

    /// Hit tolerance in screen points.
    static let hitTolerance: CGFloat = 5

    enum Gesture {
        case creating(AnnotationBuilder)
        case moving(id: Annotation.ID, snapshot: AnnotationDocument)
        case resizing(id: Annotation.ID, handle: Handle.Kind, snapshot: AnnotationDocument)
        /// The press only ended text editing or selected something.
        case consumed
    }

    init(frame: CGRect, canvasSize: CGSize, baseImage: CGImage, editor: AnnotationEditor) {
        self.editor = editor
        self.baseImage = baseImage
        super.init(frame: frame)
        setBoundsSize(canvasSize)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var canvasSize: CGSize { bounds.size }

    /// Canvas points per screen point (1 for a frozen screen; >1 for a downsized image).
    var pointSize: CGFloat {
        frame.width > 0 ? bounds.width / frame.width : 1
    }

    /// The selection in canvas points.
    var selectionInCanvas: CGRect? {
        guard let superview, let selection = selectionProvider() else { return nil }
        return convert(selection, from: superview)
    }

    var tolerance: CGFloat { Self.hitTolerance * pointSize }

    /// The handle of the selected annotation under `point` (canvas points).
    func selectedHandle(at point: CGPoint) -> Handle? {
        guard let id = editor.selectedID else { return nil }
        return editor.document.handle(at: point, for: id, radius: (AnnotationRenderer.handleSize / 2 + 3) * pointSize)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // While typing, the text view (and the menu) get ⌘-keys first.
        if textEditing == nil, onKeyEquivalent?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Routing

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, let superview, frame.contains(point) else { return nil }
        let local = convert(point, from: superview)
        if let textView = textEditing?.textView, textView.frame.contains(local) {
            return textView
        }
        guard let selection = selectionProvider() else { return nil }
        let context = PointerRouting.Context(
            selection: selection,
            toolActive: editor.tool != nil || textEditing != nil,
            hitsAnnotation: editor.document.hitTest(local, tolerance: tolerance) != nil,
            hitsAnnotationHandle: selectedHandle(at: local) != nil,
            hitsSelectionHandle: SelectionGeometry.handle(at: point, in: selection, tolerance: SelectionView.handleTolerance) != nil
        )
        return PointerRouting.target(for: point, in: context) == .canvas ? self : nil
    }

    /// Cursor for a point the canvas owns (canvas points).
    func cursor(at point: CGPoint) -> NSCursor {
        if case .moving = gesture { return .closedHand }
        if selectedHandle(at: point) != nil { return .crosshair }
        if let id = editor.document.hitTest(point, tolerance: tolerance) {
            if editor.tool == .text, case .text = editor.document[id]?.kind { return .iBeam }
            return .openHand
        }
        switch editor.tool {
        case .text: return .iBeam
        case .some: return .crosshair
        case nil: return .openHand
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let selection = selectionInCanvas else { return }
        var annotations = editor.document.annotations
        if let editingID = textEditing?.annotationID {
            annotations.removeAll { $0.id == editingID }
        }
        if case .creating(let builder) = gesture {
            annotations.append(builder.annotation)
        }
        let scale = (window?.backingScaleFactor ?? 2) / pointSize

        ctx.saveGState()
        ctx.clip(to: selection)
        // The marker multiplies with the image under it, which lives in another layer:
        // repaint the base under markers so the blend matches the export exactly.
        let markerRects = annotations.compactMap { annotation -> CGRect? in
            if case .marker = annotation.kind { return annotation.bounds.insetBy(dx: -1, dy: -1) }
            return nil
        }
        if !markerRects.isEmpty {
            ctx.saveGState()
            ctx.clip(to: markerRects)
            ctx.interpolationQuality = .none
            ctx.draw(baseImage, in: CGRect(origin: .zero, size: canvasSize))
            ctx.restoreGState()
        }
        AnnotationRenderer.draw(annotations, in: ctx, canvasSize: canvasSize, baseImage: baseImage, scale: scale)
        ctx.restoreGState()

        if let selected = editor.selectedAnnotation, textEditing?.annotationID != selected.id {
            AnnotationRenderer.drawSelectionChrome(for: selected, in: ctx, pointSize: pointSize)
        }
    }
}
