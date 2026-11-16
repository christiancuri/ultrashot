import AppKit

/// One of the eight resize handles of a selection.
enum SelectionHandle: CaseIterable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    /// Whether dragging this handle moves the left/right/bottom/top edge.
    var movesMinX: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    var movesMaxX: Bool { self == .topRight || self == .right || self == .bottomRight }
    var movesMinY: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }
    var movesMaxY: Bool { self == .topLeft || self == .top || self == .topRight }
    var isCorner: Bool { (movesMinX || movesMaxX) && (movesMinY || movesMaxY) }

    /// The handle's position on `rect` (non-flipped coordinates: top = maxY).
    func point(in rect: CGRect) -> CGPoint {
        let x = movesMinX ? rect.minX : movesMaxX ? rect.maxX : rect.midX
        let y = movesMinY ? rect.minY : movesMaxY ? rect.maxY : rect.midY
        return CGPoint(x: x, y: y)
    }

    @MainActor var cursor: NSCursor {
        let position: NSCursor.FrameResizePosition = switch self {
        case .topLeft: .topLeft
        case .top: .top
        case .topRight: .topRight
        case .right: .right
        case .bottomRight: .bottomRight
        case .bottom: .bottom
        case .bottomLeft: .bottomLeft
        case .left: .left
        }
        return .frameResize(position: position, directions: .all)
    }
}

/// Pure rectangle math for ``SelectionView``. All rects are in the view's non-flipped
/// coordinates (points, origin bottom-left of the screen).
enum SelectionGeometry {
    /// Where a selection may live and how small it may get.
    struct Limits {
        var bounds: CGRect
        var minimumSize: CGFloat
    }

    /// Clamps `point` into `bounds`.
    static func clamp(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    /// The intersection of `rect` and `bounds` (standardized), or `nil` when empty.
    static func clamp(_ rect: CGRect, to bounds: CGRect) -> CGRect? {
        let clipped = rect.standardized.intersection(bounds)
        return clipped.isNull || clipped.isEmpty ? nil : clipped
    }

    /// Rounds `rect` to the pixel grid so crops are pixel exact.
    static func snap(_ rect: CGRect, scale: CGFloat) -> CGRect {
        guard scale > 0 else { return rect }
        let minX = (rect.minX * scale).rounded() / scale
        let minY = (rect.minY * scale).rounded() / scale
        let maxX = (rect.maxX * scale).rounded() / scale
        let maxY = (rect.maxY * scale).rounded() / scale
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The rect spanned by a drag from `anchor` to `point`. With `square`, the larger side
    /// wins, limited to what fits inside `bounds` in the drag direction.
    static func rect(from anchor: CGPoint, to point: CGPoint, square: Bool, bounds: CGRect) -> CGRect {
        var dx = point.x - anchor.x
        var dy = point.y - anchor.y
        if square {
            let roomX = dx >= 0 ? bounds.maxX - anchor.x : anchor.x - bounds.minX
            let roomY = dy >= 0 ? bounds.maxY - anchor.y : anchor.y - bounds.minY
            let side = min(max(abs(dx), abs(dy)), roomX, roomY)
            dx = dx >= 0 ? side : -side
            dy = dy >= 0 ? side : -side
        }
        return CGRect(x: min(anchor.x, anchor.x + dx), y: min(anchor.y, anchor.y + dy), width: abs(dx), height: abs(dy))
    }

    /// `original` resized by dragging `handle` to `point`. Dragging past the opposite edge
    /// flips the rect; sides never get smaller than `minimumSize`; the result stays in `bounds`.
    static func resize(_ original: CGRect, handle: SelectionHandle, to point: CGPoint, square: Bool, limits: Limits) -> CGRect {
        let bounds = limits.bounds
        let minimumSize = limits.minimumSize
        let point = clamp(point, to: bounds)
        if handle.isCorner {
            let anchor = CGPoint(x: handle.movesMinX ? original.maxX : original.minX, y: handle.movesMinY ? original.maxY : original.minY)
            var rect = self.rect(from: anchor, to: point, square: square, bounds: bounds)
            rect = enforceMinimum(rect, anchor: anchor, moving: point, minimumSize: minimumSize, bounds: bounds)
            return rect
        }
        var xRange = (original.minX, original.maxX)
        var yRange = (original.minY, original.maxY)
        if handle.movesMinX || handle.movesMaxX {
            let anchorX = handle.movesMinX ? original.maxX : original.minX
            xRange = axisRange(anchor: anchorX, moving: point.x, minimumSize: minimumSize, lower: bounds.minX, upper: bounds.maxX)
        }
        if handle.movesMinY || handle.movesMaxY {
            let anchorY = handle.movesMinY ? original.maxY : original.minY
            yRange = axisRange(anchor: anchorY, moving: point.y, minimumSize: minimumSize, lower: bounds.minY, upper: bounds.maxY)
        }
        return CGRect(x: xRange.0, y: yRange.0, width: xRange.1 - xRange.0, height: yRange.1 - yRange.0)
    }

    /// `rect` moved by `delta`, kept fully inside `bounds` (its size never changes).
    static func move(_ rect: CGRect, by delta: CGVector, in bounds: CGRect) -> CGRect {
        var moved = rect.offsetBy(dx: delta.dx, dy: delta.dy)
        moved.origin.x = min(max(moved.minX, bounds.minX), bounds.maxX - moved.width)
        moved.origin.y = min(max(moved.minY, bounds.minY), bounds.maxY - moved.height)
        return moved
    }

    /// The handle under `point`, if any: corners first, then edge midpoints, then anywhere
    /// along an edge within `tolerance`.
    static func handle(at point: CGPoint, in rect: CGRect, tolerance: CGFloat) -> SelectionHandle? {
        let corners: [SelectionHandle] = [.topLeft, .topRight, .bottomRight, .bottomLeft]
        let edges: [SelectionHandle] = [.top, .right, .bottom, .left]
        for handle in corners + edges {
            let center = handle.point(in: rect)
            if abs(point.x - center.x) <= tolerance, abs(point.y - center.y) <= tolerance { return handle }
        }
        let insideX = point.x >= rect.minX - tolerance && point.x <= rect.maxX + tolerance
        let insideY = point.y >= rect.minY - tolerance && point.y <= rect.maxY + tolerance
        if insideX, abs(point.y - rect.maxY) <= tolerance / 2 { return .top }
        if insideX, abs(point.y - rect.minY) <= tolerance / 2 { return .bottom }
        if insideY, abs(point.x - rect.minX) <= tolerance / 2 { return .left }
        if insideY, abs(point.x - rect.maxX) <= tolerance / 2 { return .right }
        return nil
    }

    /// The pixel rect inside a top-left-origin image of the whole view (`viewHeight` points
    /// tall at `scale` pixels per point) that corresponds to `rect`.
    static func imagePixelRect(for rect: CGRect, viewHeight: CGFloat, scale: CGFloat) -> CGRect {
        CGRect(
            x: (rect.minX * scale).rounded(),
            y: ((viewHeight - rect.maxY) * scale).rounded(),
            width: (rect.width * scale).rounded(),
            height: (rect.height * scale).rounded()
        )
    }

    // MARK: - Private

    private static func axisRange(anchor: CGFloat, moving: CGFloat, minimumSize: CGFloat, lower: CGFloat, upper: CGFloat) -> (CGFloat, CGFloat) {
        var low = min(anchor, moving)
        var high = max(anchor, moving)
        if high - low < minimumSize {
            if moving < anchor {
                low = anchor - minimumSize
                high = anchor
            } else {
                low = anchor
                high = anchor + minimumSize
            }
        }
        // Growing to the minimum size may cross the screen edge: shift back inside.
        if low < lower {
            high += lower - low
            low = lower
        }
        if high > upper {
            low -= high - upper
            high = upper
        }
        return (low, high)
    }

    private static func enforceMinimum(_ rect: CGRect, anchor: CGPoint, moving: CGPoint, minimumSize: CGFloat, bounds: CGRect) -> CGRect {
        guard rect.width < minimumSize || rect.height < minimumSize else { return rect }
        let xRange = rect.width < minimumSize
            ? axisRange(anchor: anchor.x, moving: moving.x, minimumSize: minimumSize, lower: bounds.minX, upper: bounds.maxX)
            : (rect.minX, rect.maxX)
        let yRange = rect.height < minimumSize
            ? axisRange(anchor: anchor.y, moving: moving.y, minimumSize: minimumSize, lower: bounds.minY, upper: bounds.maxY)
            : (rect.minY, rect.maxY)
        return CGRect(x: xRange.0, y: yRange.0, width: xRange.1 - xRange.0, height: yRange.1 - yRange.0)
    }
}

extension NSScreen {
    /// The display id (`NSScreenNumber`), the key ScreenCaptureKit and CoreGraphics use.
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// Height of the primary screen, the reference for flipping between AppKit (bottom-left)
    /// and CoreGraphics/ScreenCaptureKit (top-left) global coordinates.
    static var primaryScreenHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    /// Converts a rect in this screen's overlay view (points relative to `frame.origin`, y up)
    /// to global top-left points (CoreGraphics, ScreenCaptureKit, `CGWindowListCopyWindowInfo`).
    func globalTopLeftRect(fromLocal rect: CGRect) -> CGRect {
        let global = rect.offsetBy(dx: frame.minX, dy: frame.minY)
        return CGRect(x: global.minX, y: Self.primaryScreenHeight - global.maxY, width: global.width, height: global.height)
    }

    /// Converts global top-left points to this screen's overlay view coordinates.
    func localRect(fromGlobalTopLeft rect: CGRect) -> CGRect {
        let appKitY = Self.primaryScreenHeight - rect.maxY
        return CGRect(x: rect.minX - frame.minX, y: appKitY - frame.minY, width: rect.width, height: rect.height)
    }
}
