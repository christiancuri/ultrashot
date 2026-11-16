import CoreGraphics
import Foundation

extension Annotation {
    /// Everything this annotation paints, in canvas points: stroke width, arrow head,
    /// marker width, counter badge and text box included.
    public var bounds: CGRect {
        switch kind {
        case .pen(let points):
            return CanvasGeometry.boundingRect(of: points).insetBy(dx: -style.lineWidth / 2, dy: -style.lineWidth / 2)
        case .marker(let points):
            let half = style.markerWidth / 2
            return CanvasGeometry.boundingRect(of: points).insetBy(dx: -half, dy: -half)
        case .line(let start, let end):
            return CanvasGeometry.boundingRect(of: [start, end]).insetBy(dx: -style.lineWidth / 2, dy: -style.lineWidth / 2)
        case .arrow(let start, let end):
            return ArrowShape(start: start, end: end, lineWidth: style.lineWidth).bounds
        case .rectangle(let rect), .ellipse(let rect):
            return rect.standardized.insetBy(dx: -style.lineWidth / 2, dy: -style.lineWidth / 2)
        case .blur(let rect):
            return rect.standardized
        case .text(let content):
            return content.frame
        case .counter(let center, _):
            let radius = style.counterRadius
            return CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        }
    }

    /// Whether `point` (canvas points) touches the annotation. Strokes and outlines use
    /// the distance to the drawn path (half the stroke width plus `tolerance`); blur,
    /// text and counters use their filled area grown by `tolerance`.
    public func contains(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        switch kind {
        case .pen(let points):
            return CanvasGeometry.distance(from: point, toPolyline: points) <= style.lineWidth / 2 + tolerance
        case .marker(let points):
            return CanvasGeometry.distance(from: point, toPolyline: points) <= style.markerWidth / 2 + tolerance
        case .line(let start, let end):
            return CanvasGeometry.distance(from: point, toSegment: start, end) <= style.lineWidth / 2 + tolerance
        case .arrow(let start, let end):
            return ArrowShape(start: start, end: end, lineWidth: style.lineWidth).contains(point, tolerance: tolerance)
        case .rectangle(let rect):
            let corners = CanvasGeometry.corners(of: rect.standardized)
            return CanvasGeometry.distance(from: point, toPolyline: corners, closed: true) <= style.lineWidth / 2 + tolerance
        case .ellipse(let rect):
            let polygon = CanvasGeometry.ellipsePolygon(in: rect.standardized)
            return CanvasGeometry.distance(from: point, toPolyline: polygon, closed: true) <= style.lineWidth / 2 + tolerance
        case .blur(let rect):
            return rect.standardized.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .text(let content):
            return content.frame.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .counter(let center, _):
            return CanvasGeometry.distance(point, center) <= style.counterRadius + tolerance
        }
    }

    /// Whether the annotation is too small to keep (a click without a drag).
    public var isDegenerate: Bool {
        let minimum: CGFloat = 2
        switch kind {
        case .pen(let points), .marker(let points):
            return points.isEmpty
        case .line(let start, let end), .arrow(let start, let end):
            return CanvasGeometry.distance(start, end) < minimum
        case .rectangle(let rect), .ellipse(let rect), .blur(let rect):
            return abs(rect.width) < minimum || abs(rect.height) < minimum
        case .text(let content):
            return content.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .counter:
            return false
        }
    }
}
