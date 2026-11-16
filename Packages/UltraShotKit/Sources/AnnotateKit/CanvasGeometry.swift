import CoreGraphics

/// Geometry helpers shared by the builder, hit-testing and the renderer.
public enum CanvasGeometry {
    /// Converts a canvas rect (points, bottom-left origin) into a base-image pixel rect
    /// (top-left origin), rounded outward to whole pixels. This is the rect
    /// `AnnotationRenderer.export(cropPixelRect:)` expects.
    public static func pixelRect(forCanvasRect rect: CGRect, canvasSize: CGSize, scale: CGFloat) -> CGRect {
        let rect = rect.standardized
        let flipped = CGRect(
            x: rect.minX * scale,
            y: (canvasSize.height - rect.maxY) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        return flipped.integral
    }

    /// Snaps `point` so the segment from `anchor` is a multiple of 45 degrees, keeping its length.
    public static func snapTo45Degrees(_ point: CGPoint, from anchor: CGPoint) -> CGPoint {
        let dx = point.x - anchor.x
        let dy = point.y - anchor.y
        let length = hypot(dx, dy)
        guard length > 0 else { return point }
        let step = CGFloat.pi / 4
        let angle = (atan2(dy, dx) / step).rounded() * step
        return CGPoint(x: anchor.x + cos(angle) * length, y: anchor.y + sin(angle) * length)
    }

    /// The rect spanned by `anchor` and `point`; when `square` is set, the shorter side
    /// grows to match the longer one, keeping `anchor` fixed.
    public static func rect(from anchor: CGPoint, to point: CGPoint, square: Bool) -> CGRect {
        var dx = point.x - anchor.x
        var dy = point.y - anchor.y
        if square {
            let side = max(abs(dx), abs(dy))
            dx = dx < 0 ? -side : side
            dy = dy < 0 ? -side : side
        }
        return CGRect(x: anchor.x, y: anchor.y, width: dx, height: dy).standardized
    }

    // MARK: - Distances

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    static func distance(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let abx = b.x - a.x
        let aby = b.y - a.y
        let lengthSquared = abx * abx + aby * aby
        guard lengthSquared > 0 else { return distance(point, a) }
        let t = max(0, min(1, ((point.x - a.x) * abx + (point.y - a.y) * aby) / lengthSquared))
        return distance(point, CGPoint(x: a.x + t * abx, y: a.y + t * aby))
    }

    static func distance(from point: CGPoint, toPolyline points: [CGPoint], closed: Bool = false) -> CGFloat {
        guard let first = points.first else { return .infinity }
        guard points.count > 1 else { return distance(point, first) }
        var best = CGFloat.infinity
        for index in 1..<points.count {
            best = min(best, distance(from: point, toSegment: points[index - 1], points[index]))
        }
        if closed, let last = points.last {
            best = min(best, distance(from: point, toSegment: last, first))
        }
        return best
    }

    /// The ellipse inscribed in `rect`, flattened to a closed polygon.
    static func ellipsePolygon(in rect: CGRect, segments: Int = 72) -> [CGPoint] {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let rx = rect.width / 2
        let ry = rect.height / 2
        return (0..<segments).map { index in
            let angle = CGFloat(index) / CGFloat(segments) * 2 * .pi
            return CGPoint(x: center.x + cos(angle) * rx, y: center.y + sin(angle) * ry)
        }
    }

    static func corners(of rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
        ]
    }

    /// Smallest rect containing all points (zero-size for one point, null for none).
    static func boundingRect(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .null }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: - Paths

    /// A smooth path through freehand points: quadratic curves through segment midpoints.
    static func smoothPath(through points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            // A single point still needs a (zero-length) segment so round caps draw a dot.
            path.addLine(to: points.count == 2 ? points[1] : first)
            return path
        }
        for index in 1..<(points.count - 1) {
            let control = points[index]
            let next = points[index + 1]
            let mid = CGPoint(x: (control.x + next.x) / 2, y: (control.y + next.y) / 2)
            path.addQuadCurve(to: mid, control: control)
        }
        path.addLine(to: points[points.count - 1])
        return path
    }
}
