import CoreGraphics

/// A draggable control point of a selected annotation.
///
/// "Top" means visually top, i.e. the larger y in the bottom-left canvas convention.
public struct Handle: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case corner(Corner)
        case edge(Edge)
        case lineStart
        case lineEnd
    }

    public enum Corner: Sendable, Hashable, CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    public enum Edge: Sendable, Hashable, CaseIterable {
        case top, bottom, left, right
    }

    public var kind: Kind
    /// Center of the handle in canvas points.
    public var position: CGPoint

    public init(kind: Kind, position: CGPoint) {
        self.kind = kind
        self.position = position
    }
}

/// One step of a handle drag.
///
/// Apply it to the document snapshot taken at mouse-down with the *current* mouse location
/// (absolute, not a delta). Rects that are dragged past their opposite side flip and are
/// re-standardized, so re-applying to the snapshot keeps the handle identity stable.
public struct HandleDrag: Sendable, Hashable {
    public var id: Annotation.ID
    public var handle: Handle.Kind
    /// Current mouse location in canvas points.
    public var location: CGPoint
    /// Shift held: corners keep a square, endpoints snap to 45 degrees.
    public var constrained: Bool

    public init(id: Annotation.ID, handle: Handle.Kind, location: CGPoint, constrained: Bool = false) {
        self.id = id
        self.handle = handle
        self.location = location
        self.constrained = constrained
    }
}

extension Annotation {
    /// Resize handles: eight for rectangle, ellipse and blur; both endpoints for line and
    /// arrow; none for pen, marker, text and counter (those only move).
    public var handles: [Handle] {
        switch kind {
        case .rectangle(let rect), .ellipse(let rect), .blur(let rect):
            let rect = rect.standardized
            return Handle.Corner.allCases.map { Handle(kind: .corner($0), position: $0.point(in: rect)) }
                + Handle.Edge.allCases.map { Handle(kind: .edge($0), position: $0.point(in: rect)) }
        case .line(let start, let end), .arrow(let start, let end):
            return [Handle(kind: .lineStart, position: start), Handle(kind: .lineEnd, position: end)]
        case .pen, .marker, .text, .counter:
            return []
        }
    }

    /// Returns a copy with `handle` dragged to `location`. Handles that do not apply to
    /// this kind leave it unchanged.
    public func applying(handle: Handle.Kind, to location: CGPoint, constrained: Bool = false) -> Annotation {
        var copy = self
        switch (kind, handle) {
        case (.rectangle(let rect), _):
            copy.kind = .rectangle(Self.resize(rect, handle: handle, to: location, constrained: constrained))
        case (.ellipse(let rect), _):
            copy.kind = .ellipse(Self.resize(rect, handle: handle, to: location, constrained: constrained))
        case (.blur(let rect), _):
            copy.kind = .blur(Self.resize(rect, handle: handle, to: location, constrained: constrained))
        case (.line(_, let end), .lineStart):
            copy.kind = .line(start: Self.endpoint(location, anchor: end, constrained: constrained), end: end)
        case (.line(let start, _), .lineEnd):
            copy.kind = .line(start: start, end: Self.endpoint(location, anchor: start, constrained: constrained))
        case (.arrow(_, let end), .lineStart):
            copy.kind = .arrow(start: Self.endpoint(location, anchor: end, constrained: constrained), end: end)
        case (.arrow(let start, _), .lineEnd):
            copy.kind = .arrow(start: start, end: Self.endpoint(location, anchor: start, constrained: constrained))
        default:
            break
        }
        return copy
    }

    private static func endpoint(_ location: CGPoint, anchor: CGPoint, constrained: Bool) -> CGPoint {
        constrained ? CanvasGeometry.snapTo45Degrees(location, from: anchor) : location
    }

    private static func resize(_ rect: CGRect, handle: Handle.Kind, to location: CGPoint, constrained: Bool) -> CGRect {
        let rect = rect.standardized
        switch handle {
        case .corner(let corner):
            let fixed = corner.opposite.point(in: rect)
            return CanvasGeometry.rect(from: fixed, to: location, square: constrained)
        case .edge(let edge):
            var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
            switch edge {
            case .top: maxY = location.y
            case .bottom: minY = location.y
            case .left: minX = location.x
            case .right: maxX = location.x
            }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).standardized
        case .lineStart, .lineEnd:
            return rect
        }
    }
}

extension Handle.Corner {
    var opposite: Handle.Corner {
        switch self {
        case .topLeft: .bottomRight
        case .topRight: .bottomLeft
        case .bottomLeft: .topRight
        case .bottomRight: .topLeft
        }
    }

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.minY)
        }
    }
}

extension Handle.Edge {
    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .top: CGPoint(x: rect.midX, y: rect.maxY)
        case .bottom: CGPoint(x: rect.midX, y: rect.minY)
        case .left: CGPoint(x: rect.minX, y: rect.midY)
        case .right: CGPoint(x: rect.maxX, y: rect.midY)
        }
    }
}
