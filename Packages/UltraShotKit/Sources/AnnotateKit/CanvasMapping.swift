import CoreGraphics

/// Maps between a host view's coordinates and the annotation canvas shown in it.
///
/// The canvas (size `canvasSize`, in canvas points) is displayed in `displayRect` of the
/// host view, possibly scaled (an image shown smaller than its point size). Both spaces
/// use a bottom-left origin. For a frozen full screen, `displayRect` is the view bounds and
/// `canvasSize` its size, so the mapping is the identity.
public struct CanvasMapping: Sendable, Equatable {
    public var displayRect: CGRect
    public var canvasSize: CGSize

    public init(displayRect: CGRect, canvasSize: CGSize) {
        self.displayRect = displayRect
        self.canvasSize = canvasSize
    }

    /// Canvas points per view point along x and y.
    public var canvasPerView: CGSize {
        CGSize(
            width: displayRect.width > 0 ? canvasSize.width / displayRect.width : 1,
            height: displayRect.height > 0 ? canvasSize.height / displayRect.height : 1
        )
    }

    public func canvasPoint(fromView point: CGPoint) -> CGPoint {
        let factor = canvasPerView
        return CGPoint(x: (point.x - displayRect.minX) * factor.width, y: (point.y - displayRect.minY) * factor.height)
    }

    public func canvasRect(fromView rect: CGRect) -> CGRect {
        let factor = canvasPerView
        let rect = rect.standardized
        return CGRect(
            x: (rect.minX - displayRect.minX) * factor.width,
            y: (rect.minY - displayRect.minY) * factor.height,
            width: rect.width * factor.width,
            height: rect.height * factor.height
        )
    }

    public func viewRect(fromCanvas rect: CGRect) -> CGRect {
        let factor = canvasPerView
        let rect = rect.standardized
        return CGRect(
            x: displayRect.minX + rect.minX / factor.width,
            y: displayRect.minY + rect.minY / factor.height,
            width: rect.width / factor.width,
            height: rect.height / factor.height
        )
    }

    /// The `export(cropPixelRect:)` rect for a selection given in view coordinates: the
    /// selection in canvas points, clipped to the canvas, in base pixels (top-left origin).
    /// `nil` when the selection does not overlap the canvas.
    public func cropPixelRect(forViewSelection selection: CGRect, imageScale: CGFloat) -> CGRect? {
        let canvasRect = canvasRect(fromView: selection).intersection(CGRect(origin: .zero, size: canvasSize))
        guard !canvasRect.isNull, canvasRect.width > 0, canvasRect.height > 0 else { return nil }
        return CanvasGeometry.pixelRect(forCanvasRect: canvasRect, canvasSize: canvasSize, scale: imageScale)
    }
}

extension CanvasMapping {
    /// Shows a canvas of `canvasSize` centered in `container` at its point size, scaled down
    /// to fit `fraction` of the container when larger. The display rect is snapped to whole
    /// pixels of a `displayScale` screen.
    public static func fitted(
        canvasSize: CGSize,
        in container: CGRect,
        fraction: CGFloat = 0.9,
        displayScale: CGFloat = 2
    ) -> CanvasMapping {
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return CanvasMapping(displayRect: CGRect(origin: CGPoint(x: container.midX, y: container.midY), size: .zero), canvasSize: canvasSize)
        }
        let fit = min(1, container.width * fraction / canvasSize.width, container.height * fraction / canvasSize.height)
        let size = CGSize(width: canvasSize.width * fit, height: canvasSize.height * fit)
        let snap = { (value: CGFloat) in (value * displayScale).rounded() / displayScale }
        let rect = CGRect(
            x: snap(container.midX - size.width / 2),
            y: snap(container.midY - size.height / 2),
            width: snap(size.width),
            height: snap(size.height)
        )
        return CanvasMapping(displayRect: rect, canvasSize: canvasSize)
    }
}
