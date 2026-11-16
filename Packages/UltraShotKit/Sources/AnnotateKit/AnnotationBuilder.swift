import CoreGraphics
import Foundation

/// Modifier keys that affect interactive creation and handle drags.
public struct DragModifiers: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Line/arrow snap to 45 degrees; rectangle/ellipse/blur become square/circle.
    public static let shift = DragModifiers(rawValue: 1 << 0)
}

/// Builds the in-progress annotation for one mouse-down → drag → mouse-up gesture.
///
///     var builder = AnnotationBuilder(tool: .arrow, style: style, start: down)
///     builder.update(to: dragged, modifiers: .shift)   // on every mouseDragged
///     preview(builder.annotation)                      // draw on top of the document
///     if let done = builder.finish() { doc.add(done) } // on mouseUp
///
/// Text and counters are click tools: the annotation is placed at the current point.
/// For text, `annotation` carries an empty string; the UI edits it and adds it on commit.
public struct AnnotationBuilder: Sendable {
    public let tool: Tool
    public let style: Annotation.Style
    public let id: Annotation.ID
    public let start: CGPoint
    public private(set) var current: CGPoint
    public private(set) var modifiers: DragModifiers = []

    private let counterNumber: Int
    private let fontSize: CGFloat
    /// Accepted freehand samples (pen/marker), decimated by `minimumSpacing`.
    private var samples: [CGPoint]

    /// Freehand samples closer than this to the previous one are dropped.
    static let minimumSpacing: CGFloat = 1.5

    public init(
        tool: Tool,
        style: Annotation.Style,
        start: CGPoint,
        counterNumber: Int = 1,
        fontSize: CGFloat = TextContent.defaultFontSize,
        id: Annotation.ID = UUID()
    ) {
        self.tool = tool
        self.style = style
        self.start = start
        self.current = start
        self.counterNumber = counterNumber
        self.fontSize = fontSize
        self.id = id
        self.samples = [start]
    }

    /// Feeds the current mouse location (canvas points).
    public mutating func update(to point: CGPoint, modifiers: DragModifiers = []) {
        current = point
        self.modifiers = modifiers
        if tool == .pen || tool == .marker,
           let last = samples.last,
           CanvasGeometry.distance(last, point) >= Self.minimumSpacing {
            samples.append(point)
        }
    }

    /// The annotation as it should be previewed right now.
    public var annotation: Annotation {
        Annotation(id: id, kind: kind(freehand: liveFreehandPoints), style: style)
    }

    /// The final annotation (freehand strokes smoothed and simplified), or nil when the
    /// gesture produced nothing worth keeping (for example a click with a shape tool).
    public func finish() -> Annotation? {
        let result = Annotation(id: id, kind: kind(freehand: Self.smoothed(liveFreehandPoints)), style: style)
        return result.isDegenerate ? nil : result
    }

    // MARK: - Internals

    private var liveFreehandPoints: [CGPoint] {
        guard let last = samples.last, last != current else { return samples }
        return samples + [current]
    }

    private func kind(freehand: [CGPoint]) -> Annotation.Kind {
        let shift = modifiers.contains(.shift)
        switch tool {
        case .pen:
            return .pen(points: freehand)
        case .marker:
            return .marker(points: freehand)
        case .line:
            return .line(start: start, end: shift ? CanvasGeometry.snapTo45Degrees(current, from: start) : current)
        case .arrow:
            return .arrow(start: start, end: shift ? CanvasGeometry.snapTo45Degrees(current, from: start) : current)
        case .rectangle:
            return .rectangle(CanvasGeometry.rect(from: start, to: current, square: shift))
        case .ellipse:
            return .ellipse(CanvasGeometry.rect(from: start, to: current, square: shift))
        case .blur:
            return .blur(CanvasGeometry.rect(from: start, to: current, square: shift))
        case .text:
            return .text(TextContent(string: "", origin: current, fontSize: fontSize))
        case .counter:
            return .counter(center: current, number: counterNumber)
        }
    }

    /// One pass of a [1, 2, 1] / 4 moving average (endpoints kept), then
    /// Ramer–Douglas–Peucker with a sub-point tolerance to drop redundant samples.
    static func smoothed(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var averaged = points
        for index in 1..<(points.count - 1) {
            let prev = points[index - 1], here = points[index], next = points[index + 1]
            averaged[index] = CGPoint(
                x: (prev.x + 2 * here.x + next.x) / 4,
                y: (prev.y + 2 * here.y + next.y) / 4
            )
        }
        return simplify(averaged, epsilon: 0.35)
    }

    static func simplify(_ points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var stack = [(0, points.count - 1)]
        while let (first, last) = stack.popLast() {
            guard last > first + 1 else { continue }
            var farthest = first
            var farthestDistance: CGFloat = 0
            for index in (first + 1)..<last {
                let distance = CanvasGeometry.distance(from: points[index], toSegment: points[first], points[last])
                if distance > farthestDistance {
                    farthest = index
                    farthestDistance = distance
                }
            }
            if farthestDistance > epsilon {
                keep[farthest] = true
                stack.append((first, farthest))
                stack.append((farthest, last))
            }
        }
        return zip(points, keep).compactMap { $1 ? $0 : nil }
    }
}
