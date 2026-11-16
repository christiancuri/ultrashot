import AppKit
import CoreText

/// Text measurement and drawing shared by the renderer and hit-testing, so the box the
/// user clicks is exactly the box that is drawn.
///
/// Layout is line-based: the string is split on newlines, every line is `lineHeight` tall,
/// and lines are left-aligned from the top-left `origin`. A trailing newline adds an empty
/// line (matching a text view's caret).
public enum TextLayout {
    /// System font, medium weight (Lightshot-like).
    public static func font(size: CGFloat) -> CTFont {
        NSFont.systemFont(ofSize: size, weight: .medium) as CTFont
    }

    /// Distance between baselines of consecutive lines.
    public static func lineHeight(fontSize: CGFloat) -> CGFloat {
        metrics(for: font(size: fontSize)).lineHeight
    }

    /// Size of the text box in canvas points.
    public static func size(for content: TextContent) -> CGSize {
        let layout = Layout(content: content)
        return layout.size
    }

    /// Draws the text with its top-left corner at `content.origin` in an unflipped context.
    static func draw(_ content: TextContent, color: CGColor, in ctx: CGContext) {
        let layout = Layout(content: content, color: color)
        ctx.saveGState()
        ctx.textMatrix = .identity
        for (index, line) in layout.lines.enumerated() {
            let baseline = content.origin.y - layout.metrics.ascent - CGFloat(index) * layout.metrics.lineHeight
            ctx.textPosition = CGPoint(x: content.origin.x, y: baseline)
            CTLineDraw(line, ctx)
        }
        ctx.restoreGState()
    }

    // MARK: - Internals

    struct Metrics {
        let ascent: CGFloat
        let lineHeight: CGFloat
    }

    static func metrics(for font: CTFont) -> Metrics {
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        let leading = CTFontGetLeading(font)
        return Metrics(ascent: ascent, lineHeight: ceil(ascent + descent + leading))
    }

    private struct Layout {
        let lines: [CTLine]
        let metrics: Metrics
        let size: CGSize

        init(content: TextContent, color: CGColor? = nil) {
            let font = TextLayout.font(size: content.fontSize)
            metrics = TextLayout.metrics(for: font)
            var attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
            ]
            if let color {
                attributes[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = color
            }
            let rawLines = content.string
                .replacingOccurrences(of: "\r\n", with: "\n")
                .split(separator: "\n", omittingEmptySubsequences: false)
            lines = rawLines.map { line in
                CTLineCreateWithAttributedString(NSAttributedString(string: String(line), attributes: attributes))
            }
            let widest = lines.map { CGFloat(CTLineGetTypographicBounds($0, nil, nil, nil)) }.max() ?? 0
            let minimumWidth = content.fontSize * 0.3
            size = CGSize(
                width: ceil(max(widest, minimumWidth)),
                height: metrics.lineHeight * CGFloat(max(lines.count, 1))
            )
        }
    }
}
