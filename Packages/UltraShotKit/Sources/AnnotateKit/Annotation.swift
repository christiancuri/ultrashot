import CoreGraphics
import Foundation

// MARK: - Coordinate convention
//
// Every geometric value in AnnotateKit is expressed in *canvas points*:
//
//   - The canvas is the base image measured in points: `canvasSize = imagePixelSize / scale`.
//   - The origin is the BOTTOM-LEFT corner of the image, x grows right, y grows UP.
//     This matches an unflipped AppKit view whose bounds equal the canvas size, and a
//     Core Graphics bitmap context after `scaleBy(x: scale, y: scale)`.
//   - Image pixel = canvas point × scale.
//
// The only exception is `AnnotationRenderer.export(cropPixelRect:)`, which takes a rect in
// base-image pixels with a TOP-LEFT origin (the `CGImage.cropping(to:)` convention).
// Use `CanvasGeometry.pixelRect(forCanvasRect:canvasSize:scale:)` to convert.
//
// Annotations always live in the canvas of the full base image, even when the export is
// cropped, so the selection can keep moving while annotating.

/// One drawn object on the canvas.
public struct Annotation: Identifiable, Sendable, Hashable, Codable {
    /// `Annotation.ID` (from `Identifiable`) is `UUID`.
    public var id: UUID
    public var kind: Kind
    public var style: Style

    public init(id: UUID = UUID(), kind: Kind, style: Style = Style()) {
        self.id = id
        self.kind = kind
        self.style = style
    }

    /// Geometry per tool, in canvas points.
    public enum Kind: Sendable, Hashable, Codable {
        /// Freehand stroke through the points.
        case pen(points: [CGPoint])
        case line(start: CGPoint, end: CGPoint)
        /// The head sits at `end`.
        case arrow(start: CGPoint, end: CGPoint)
        case rectangle(CGRect)
        case ellipse(CGRect)
        /// Wide, translucent highlighter stroke through the points.
        case marker(points: [CGPoint])
        case text(TextContent)
        /// Pixelated region of the base image.
        case blur(CGRect)
        /// Numbered badge centered at `center`.
        case counter(center: CGPoint, number: Int)

        /// The tool that creates this kind.
        public var tool: Tool {
            switch self {
            case .pen: .pen
            case .line: .line
            case .arrow: .arrow
            case .rectangle: .rectangle
            case .ellipse: .ellipse
            case .marker: .marker
            case .text: .text
            case .blur: .blur
            case .counter: .counter
            }
        }
    }

    /// Visual style. `lineWidth` is the single "size" the UI adjusts (scroll wheel);
    /// each kind derives its own metrics from it (see the `*Width`/`*Radius` helpers).
    public struct Style: Sendable, Hashable, Codable {
        public var color: RGBAColor
        public var lineWidth: CGFloat

        public static let defaultLineWidth: CGFloat = 4
        public static let lineWidthRange: ClosedRange<CGFloat> = 1...40

        public init(color: RGBAColor = Palette.defaultColor, lineWidth: CGFloat = Style.defaultLineWidth) {
            self.color = color
            self.lineWidth = lineWidth
        }

        /// Stroke width of the highlighter, which is much wider than the pen.
        public var markerWidth: CGFloat { max(lineWidth * 4, 8) }

        /// Radius of a counter badge.
        public var counterRadius: CGFloat { lineWidth * 2 + 8 }

        /// Opacity of the highlighter stroke (applied on top of `color.alpha`).
        public static let markerOpacity: CGFloat = 0.45
    }
}

/// Text annotation content.
public struct TextContent: Sendable, Hashable, Codable {
    /// May contain newlines; each line is laid out left-aligned.
    public var string: String
    /// TOP-LEFT corner of the text box in canvas points. The box extends DOWN (toward
    /// smaller y) by `TextLayout.size(for:).height`. This is where the user clicked.
    public var origin: CGPoint
    public var fontSize: CGFloat

    public static let defaultFontSize: CGFloat = 20
    public static let fontSizeRange: ClosedRange<CGFloat> = 8...160

    public init(string: String, origin: CGPoint, fontSize: CGFloat = TextContent.defaultFontSize) {
        self.string = string
        self.origin = origin
        self.fontSize = fontSize
    }

    /// The laid-out text box in canvas points (bottom-left origin).
    public var frame: CGRect {
        let size = TextLayout.size(for: self)
        return CGRect(x: origin.x, y: origin.y - size.height, width: size.width, height: size.height)
    }
}

extension Annotation {
    /// Returns a copy translated by `offset`.
    public func moved(by offset: CGVector) -> Annotation {
        var copy = self
        copy.kind = kind.moved(by: offset)
        return copy
    }
}

extension Annotation.Kind {
    func moved(by offset: CGVector) -> Annotation.Kind {
        let shift = { (point: CGPoint) in CGPoint(x: point.x + offset.dx, y: point.y + offset.dy) }
        switch self {
        case .pen(let points): return .pen(points: points.map(shift))
        case .marker(let points): return .marker(points: points.map(shift))
        case .line(let start, let end): return .line(start: shift(start), end: shift(end))
        case .arrow(let start, let end): return .arrow(start: shift(start), end: shift(end))
        case .rectangle(let rect): return .rectangle(rect.offsetBy(dx: offset.dx, dy: offset.dy))
        case .ellipse(let rect): return .ellipse(rect.offsetBy(dx: offset.dx, dy: offset.dy))
        case .blur(let rect): return .blur(rect.offsetBy(dx: offset.dx, dy: offset.dy))
        case .counter(let center, let number): return .counter(center: shift(center), number: number)
        case .text(var content):
            content.origin = shift(content.origin)
            return .text(content)
        }
    }
}
