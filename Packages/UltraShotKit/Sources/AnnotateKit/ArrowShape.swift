import CoreGraphics

/// Filled arrow outline: a tapered shaft and a swept, filled head whose size scales with
/// the line width. Used for rendering, bounds and hit-testing so all three agree.
struct ArrowShape {
    let start: CGPoint
    let end: CGPoint
    let lineWidth: CGFloat

    /// Polygon vertices (empty when the arrow has no length).
    let outline: [CGPoint]
    /// Radius of the rounded tail cap.
    let tailRadius: CGFloat

    init(start: CGPoint, end: CGPoint, lineWidth: CGFloat) {
        self.start = start
        self.end = end
        self.lineWidth = lineWidth

        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        let shaftHalf = max(lineWidth / 2, 0.75)
        tailRadius = max(shaftHalf * 0.6, 0.5)
        guard length > 0.5 else {
            outline = []
            return
        }
        let ux = dx / length
        let uy = dy / length
        // Normal (pointing left of the direction of travel).
        let nx = -uy
        let ny = ux

        let headLength = min(max(lineWidth * 3 + 9, 12), length * 0.75)
        let headHalfWidth = headLength * 0.62
        let notchDepth = headLength * 0.74

        func point(along distance: CGFloat, across offset: CGFloat) -> CGPoint {
            CGPoint(x: start.x + ux * distance + nx * offset, y: start.y + uy * distance + ny * offset)
        }
        let joinHalf = min(shaftHalf, headHalfWidth * 0.5)
        let join = length - notchDepth
        let base = length - headLength
        outline = [
            point(along: 0, across: tailRadius),
            point(along: join, across: joinHalf),
            point(along: base, across: headHalfWidth),
            end,
            point(along: base, across: -headHalfWidth),
            point(along: join, across: -joinHalf),
            point(along: 0, across: -tailRadius),
        ]
    }

    var path: CGPath {
        let path = CGMutablePath()
        guard let first = outline.first else { return path }
        path.move(to: first)
        for vertex in outline.dropFirst() {
            path.addLine(to: vertex)
        }
        // Round the tail with an arc around the back of `start` (one contour, so the
        // winding stays consistent and the cap never punches a hole in the shaft).
        let normalAngle = atan2(end.x - start.x, start.y - end.y) // direction of the left normal
        path.addArc(center: start, radius: tailRadius, startAngle: normalAngle + .pi, endAngle: normalAngle, clockwise: true)
        path.closeSubpath()
        return path
    }

    var bounds: CGRect {
        guard !outline.isEmpty else {
            return CGRect(origin: start, size: .zero).insetBy(dx: -tailRadius, dy: -tailRadius)
        }
        return CanvasGeometry.boundingRect(of: outline).insetBy(dx: -tailRadius, dy: -tailRadius)
    }

    func contains(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        if path.contains(point) { return true }
        return CanvasGeometry.distance(from: point, toPolyline: outline, closed: true) <= tolerance
            || CanvasGeometry.distance(point, start) <= tailRadius + tolerance
    }
}
