import CoreGraphics
import CoreText

/// The one Core Graphics renderer used by the on-screen canvas and by export.
///
/// The context must be in canvas points with a bottom-left origin (an unflipped view whose
/// bounds equal the canvas size, or a bitmap context scaled by the image scale).
public enum AnnotationRenderer {
    /// Draws `annotations` in order (first = bottom-most). Does NOT draw the base image:
    /// the caller draws it first, in the same context, so the marker's multiply blend and
    /// the blur sample the real pixels.
    ///
    /// - Parameters:
    ///   - canvasSize: canvas size in points (base image pixel size / image scale).
    ///   - baseImage: the full base image; needed by blur (pixelate). Without it blur
    ///     regions draw as a neutral gray placeholder.
    ///   - scale: device pixels per canvas point of `ctx` (export: the image scale; on
    ///     screen: the view's backing scale factor). Keeps shadows the same size in
    ///     canvas points on every output.
    public static func draw(
        _ annotations: [Annotation],
        in ctx: CGContext,
        canvasSize: CGSize,
        baseImage: CGImage?,
        scale: CGFloat
    ) {
        for annotation in annotations {
            draw(annotation, in: ctx, canvasSize: canvasSize, baseImage: baseImage, scale: scale)
        }
    }

    /// Draws one annotation (for example the in-progress one from `AnnotationBuilder`).
    public static func draw(
        _ annotation: Annotation,
        in ctx: CGContext,
        canvasSize: CGSize,
        baseImage: CGImage?,
        scale: CGFloat
    ) {
        let style = annotation.style
        let color = style.color.cgColor
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high

        switch annotation.kind {
        case .pen(let points):
            applyShadow(ctx, scale: scale)
            strokeFreehand(points, in: ctx, color: color, width: style.lineWidth, cap: .round)
        case .marker(let points):
            ctx.setBlendMode(.multiply)
            let markerColor = style.color.withAlpha(style.color.alpha * Annotation.Style.markerOpacity).cgColor
            strokeFreehand(points, in: ctx, color: markerColor, width: style.markerWidth, cap: .butt)
        case .line(let start, let end):
            applyShadow(ctx, scale: scale)
            ctx.setStrokeColor(color)
            ctx.setLineWidth(style.lineWidth)
            ctx.setLineCap(.round)
            ctx.strokeLineSegments(between: [start, end])
        case .arrow(let start, let end):
            applyShadow(ctx, scale: scale)
            ctx.setFillColor(color)
            ctx.addPath(ArrowShape(start: start, end: end, lineWidth: style.lineWidth).path)
            ctx.fillPath()
        case .rectangle(let rect):
            applyShadow(ctx, scale: scale)
            ctx.setStrokeColor(color)
            ctx.setLineWidth(style.lineWidth)
            ctx.setLineJoin(.miter)
            ctx.stroke(rect.standardized)
        case .ellipse(let rect):
            applyShadow(ctx, scale: scale)
            ctx.setStrokeColor(color)
            ctx.setLineWidth(style.lineWidth)
            ctx.strokeEllipse(in: rect.standardized)
        case .text(let content):
            TextLayout.draw(content, color: color, in: ctx)
        case .blur(let rect):
            drawPixelated(rect, in: ctx, canvasSize: canvasSize, baseImage: baseImage)
        case .counter(let center, let number):
            drawCounter(center: center, number: number, style: style, in: ctx, scale: scale)
        }
    }

    // MARK: - Pieces

    /// Soft drop shadow that lifts strokes off busy backgrounds. Shadow metrics are in
    /// device space, hence the `scale` factor.
    private static func applyShadow(_ ctx: CGContext, scale: CGFloat) {
        ctx.setShadow(
            offset: CGSize(width: 0, height: -1 * scale),
            blur: 3 * scale,
            color: CGColor(gray: 0, alpha: 0.35)
        )
    }

    private static func strokeFreehand(
        _ points: [CGPoint],
        in ctx: CGContext,
        color: CGColor,
        width: CGFloat,
        cap: CGLineCap
    ) {
        guard !points.isEmpty else { return }
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.setLineCap(cap)
        ctx.setLineJoin(.round)
        if points.count == 1, cap == .butt {
            // A butt-capped zero-length segment paints nothing; show a square dab instead.
            let point = points[0]
            ctx.setFillColor(color)
            ctx.fill(CGRect(x: point.x - width / 2, y: point.y - width / 2, width: width, height: width))
            return
        }
        ctx.addPath(CanvasGeometry.smoothPath(through: points))
        ctx.strokePath()
    }

    private static func drawCounter(
        center: CGPoint,
        number: Int,
        style: Annotation.Style,
        in ctx: CGContext,
        scale: CGFloat
    ) {
        let radius = style.counterRadius
        let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        ctx.saveGState()
        applyShadow(ctx, scale: scale)
        ctx.setFillColor(style.color.cgColor)
        ctx.fillEllipse(in: circle)
        ctx.restoreGState()

        // Thin white ring keeps dark badges visible on dark backgrounds.
        let ring = max(radius * 0.08, 1)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.9))
        ctx.setLineWidth(ring)
        ctx.strokeEllipse(in: circle.insetBy(dx: ring / 2, dy: ring / 2))

        let label = String(number)
        let fontSize = radius * (label.count > 2 ? 0.8 : label.count == 2 ? 0.95 : 1.15)
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, fontSize, nil)
            ?? CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
        let textColor = style.color.luminance > 0.7 ? RGBAColor.black.cgColor : RGBAColor.white.cgColor
        let attributes = [
            kCTFontAttributeName as String: font,
            kCTForegroundColorAttributeName as String: textColor,
        ] as CFDictionary
        guard let attributed = CFAttributedStringCreate(nil, label as CFString, attributes) else { return }
        let line = CTLineCreateWithAttributedString(attributed)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        // Digits sit on the baseline and reach cap height: center that band vertically.
        let capHeight = CTFontGetCapHeight(font)
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: center.x - width / 2, y: center.y - capHeight / 2)
        CTLineDraw(line, ctx)
    }
}
