import CoreGraphics

/// Pure coordinate conversions between the two global coordinate spaces macOS uses.
///
/// - AppKit global points: origin at the bottom-left of the primary screen, y grows upward
///   (`NSScreen.frame`, `NSEvent.mouseLocation`).
/// - CG global points: origin at the top-left of the primary screen, y grows downward
///   (`CGDisplayBounds`, `kCGWindowBounds`, ScreenCaptureKit rect APIs).
///
/// Both spaces share the x axis; converting only flips y around the primary screen height.
public enum ScreenGeometry {
    /// AppKit global rect (bottom-left origin) to CG global rect (top-left origin).
    public static func appKitToCG(_ rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// CG global rect (top-left origin) to AppKit global rect (bottom-left origin).
    public static func cgToAppKit(_ rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        // The flip is its own inverse.
        appKitToCG(rect, primaryScreenHeight: primaryScreenHeight)
    }

    /// AppKit global point to CG global point.
    public static func appKitToCG(_ point: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    /// CG global point to AppKit global point.
    public static func cgToAppKit(_ point: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        appKitToCG(point, primaryScreenHeight: primaryScreenHeight)
    }

    /// Maps a rect in display-local points (bottom-left origin, AppKit orientation) to a pixel
    /// rect in the display image (top-left origin). Edges are rounded to the nearest pixel.
    /// The result is not clamped; see `DisplaySnapshot.crop(toLocalRect:)`.
    ///
    /// - Parameters:
    ///   - localRect: rect relative to the display's origin, in points, y growing upward.
    ///   - displaySize: the display size in points.
    ///   - scale: pixels per point (backing scale factor).
    public static func pixelRect(forLocalRect localRect: CGRect, displaySize: CGSize, scale: CGFloat) -> CGRect {
        pixelRect(forLocalRect: localRect, displaySize: displaySize, scaleX: scale, scaleY: scale)
    }

    /// Like ``pixelRect(forLocalRect:displaySize:scale:)`` with a separate scale per axis.
    public static func pixelRect(forLocalRect localRect: CGRect, displaySize: CGSize, scaleX: CGFloat, scaleY: CGFloat) -> CGRect {
        let rect = localRect.standardized
        let minX = (rect.minX * scaleX).rounded()
        let maxX = (rect.maxX * scaleX).rounded()
        let minY = ((displaySize.height - rect.maxY) * scaleY).rounded()
        let maxY = ((displaySize.height - rect.minY) * scaleY).rounded()
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Converts an AppKit global rect to display-local points (bottom-left origin) for a display
    /// whose AppKit frame is `displayFrame`.
    public static func localRect(forAppKitRect rect: CGRect, displayFrame: CGRect) -> CGRect {
        rect.offsetBy(dx: -displayFrame.minX, dy: -displayFrame.minY)
    }
}
