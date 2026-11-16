import CoreGraphics

/// Pure geometry for the recording UI, kept free of AppKit so it can be unit tested.
///
/// "Local" rects are in a screen's overlay view: points relative to the screen's origin,
/// y up (AppKit). "Global top-left" rects are CoreGraphics global points: origin at the
/// top-left of the primary screen, y down.
public enum RecordingGeometry {
    /// Which side of the anchor a panel ended up on.
    public enum Side: Sendable, Equatable {
        case below
        case above
        case inside
    }

    public struct Placement: Sendable, Equatable {
        public var frame: CGRect
        public var side: Side

        public init(frame: CGRect, side: Side) {
            self.frame = frame
            self.side = side
        }
    }

    // MARK: Coordinate conversion

    /// `SCStreamConfiguration.sourceRect` (display-local points, top-left origin) for a rect in
    /// the overlay view of a screen `screenHeight` points tall. The screen's position in the
    /// global space does not matter, so this holds for primary and secondary displays alike.
    public static func displaySourceRect(fromLocal rect: CGRect, screenHeight: CGFloat) -> CGRect {
        let rect = rect.standardized
        return CGRect(x: rect.minX, y: screenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// A local rect of the screen whose AppKit frame is `screenFrame`, in global top-left points.
    public static func globalTopLeftRect(fromLocal rect: CGRect, screenFrame: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        let global = rect.standardized.offsetBy(dx: screenFrame.minX, dy: screenFrame.minY)
        return CGRect(x: global.minX, y: primaryScreenHeight - global.maxY, width: global.width, height: global.height)
    }

    /// Global top-left points to a local rect of the screen whose AppKit frame is `screenFrame`.
    public static func localRect(fromGlobalTopLeft rect: CGRect, screenFrame: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        let rect = rect.standardized
        let appKitY = primaryScreenHeight - rect.maxY
        return CGRect(x: rect.minX - screenFrame.minX, y: appKitY - screenFrame.minY, width: rect.width, height: rect.height)
    }

    /// A local point of the screen whose AppKit frame is `screenFrame`, in global top-left points.
    public static func globalTopLeftPoint(fromLocal point: CGPoint, screenFrame: CGRect, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x + screenFrame.minX, y: primaryScreenHeight - (point.y + screenFrame.minY))
    }

    // MARK: Panel placement

    /// Frame for a panel of `size` attached to `anchor`, inside `bounds`: centered below the
    /// anchor, else above it, else inside it along its bottom edge. The panel never leaves
    /// `bounds` inset by `margin`.
    public static func place(_ size: CGSize, near anchor: CGRect, in bounds: CGRect, gap: CGFloat = 10, margin: CGFloat = 8) -> Placement {
        let anchor = anchor.standardized
        let area = bounds.insetBy(dx: margin, dy: margin)
        let x = clamp(anchor.midX - size.width / 2, lower: area.minX, upper: area.maxX - size.width)
        let below = anchor.minY - gap - size.height
        if below >= area.minY {
            return Placement(frame: CGRect(x: x, y: below, width: size.width, height: size.height), side: .below)
        }
        let above = anchor.maxY + gap
        if above + size.height <= area.maxY {
            return Placement(frame: CGRect(x: x, y: above, width: size.width, height: size.height), side: .above)
        }
        let inside = clamp(anchor.minY + gap, lower: area.minY, upper: area.maxY - size.height)
        return Placement(frame: CGRect(x: x, y: inside, width: size.width, height: size.height), side: .inside)
    }

    /// Frame for a panel of `size` when there is no anchor: centered horizontally, `offset`
    /// points above the bottom of `bounds`.
    public static func placeWithoutAnchor(_ size: CGSize, in bounds: CGRect, offset: CGFloat = 80) -> CGRect {
        CGRect(
            x: bounds.midX - size.width / 2,
            y: clamp(bounds.minY + offset, lower: bounds.minY, upper: bounds.maxY - size.height),
            width: size.width,
            height: size.height
        )
    }

    // MARK: Selection editing

    /// The selection after the user types a size (points). Keeps the top-left corner of the
    /// current selection, limits each side to `minimumSide ... bounds side`, then shifts the
    /// rect back inside `bounds`. Without a current selection the new rect is centered.
    public static func resized(_ selection: CGRect?, to size: CGSize, in bounds: CGRect, minimumSide: CGFloat = 4) -> CGRect {
        let width = clamp(size.width.isFinite ? size.width.rounded() : 0, lower: minimumSide, upper: bounds.width)
        let height = clamp(size.height.isFinite ? size.height.rounded() : 0, lower: minimumSide, upper: bounds.height)
        guard let current = selection?.standardized else {
            return CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)
        }
        let x = clamp(current.minX, lower: bounds.minX, upper: bounds.maxX - width)
        let top = clamp(current.maxY, lower: bounds.minY + height, upper: bounds.maxY)
        return CGRect(x: x, y: top - height, width: width, height: height)
    }

    /// True when `selection` covers `bounds` (within half a point on every edge).
    public static func isFullscreen(_ selection: CGRect, in bounds: CGRect, tolerance: CGFloat = 0.5) -> Bool {
        let selection = selection.standardized
        return abs(selection.minX - bounds.minX) <= tolerance
            && abs(selection.minY - bounds.minY) <= tolerance
            && abs(selection.maxX - bounds.maxX) <= tolerance
            && abs(selection.maxY - bounds.maxY) <= tolerance
    }

    // MARK: Elapsed time

    /// `mm:ss`, or `h:mm:ss` from one hour on. Negative values read as zero.
    public static func elapsedText(_ elapsed: Double) -> String {
        let total = max(0, Int(elapsed.isFinite ? elapsed.rounded(.down) : 0))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        func pad(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
        return hours > 0 ? "\(hours):\(pad(minutes)):\(pad(seconds))" : "\(pad(minutes)):\(pad(seconds))"
    }

    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        // When the range is empty (panel wider than the area) prefer the lower edge.
        max(lower, min(value, upper))
    }
}
