import CoreGraphics

extension AnnotationRenderer {
    /// Draws the selection outline and resize handles for `annotation`. On-screen only:
    /// export never calls this.
    ///
    /// - Parameter pointSize: size of one screen point in canvas points (1 when the view
    ///   shows the canvas 1:1). Keeps the chrome the same on-screen size when zoomed.
    public static func drawSelectionChrome(for annotation: Annotation, in ctx: CGContext, pointSize: CGFloat = 1) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.setBlendMode(.normal)

        let handles = annotation.handles
        let isSegment = handles.contains { $0.kind == .lineStart }
        if !isSegment {
            let outline = annotation.bounds.insetBy(dx: -3 * pointSize, dy: -3 * pointSize)
            ctx.setLineWidth(pointSize)
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.95))
            ctx.stroke(outline)
            ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 0.95))
            ctx.setLineDash(phase: 0, lengths: [4 * pointSize, 3 * pointSize])
            ctx.stroke(outline)
            ctx.setLineDash(phase: 0, lengths: [])
        }

        let side = handleSize * pointSize
        for handle in handles {
            let box = CGRect(
                x: handle.position.x - side / 2,
                y: handle.position.y - side / 2,
                width: side,
                height: side
            )
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
            ctx.setLineWidth(pointSize)
            if isSegment {
                ctx.fillEllipse(in: box)
                ctx.strokeEllipse(in: box.insetBy(dx: pointSize / 2, dy: pointSize / 2))
            } else {
                ctx.fill(box)
                ctx.stroke(box.insetBy(dx: pointSize / 2, dy: pointSize / 2))
            }
        }
    }

    /// Side of a resize handle in screen points (use it with `AnnotationDocument.handle(at:)`).
    public static let handleSize: CGFloat = 8
}
