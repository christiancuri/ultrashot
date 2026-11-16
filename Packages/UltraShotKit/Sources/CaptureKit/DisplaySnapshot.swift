import AppKit
import CoreGraphics

/// Identifies a display to capture. Built by the app from `NSScreen`.
public struct DisplayDescriptor: Sendable, Equatable {
    public var displayID: CGDirectDisplayID
    /// AppKit global points, bottom-left origin (`NSScreen.frame`).
    public var frame: CGRect
    /// Pixels per point (`NSScreen.backingScaleFactor`).
    public var scale: CGFloat

    public init(displayID: CGDirectDisplayID, frame: CGRect, scale: CGFloat) {
        self.displayID = displayID
        self.frame = frame
        self.scale = scale
    }

    /// Builds a descriptor from a screen. Returns nil when the screen has no display number.
    @MainActor
    public init?(screen: NSScreen) {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
        self.init(displayID: number.uint32Value, frame: screen.frame, scale: screen.backingScaleFactor)
    }
}

/// Options for a full-display snapshot.
public struct SnapshotOptions: Sendable, Equatable {
    /// Exclude Finder's desktop-icon window; the wallpaper stays.
    public var hideDesktopIcons: Bool
    /// Draw the mouse cursor into the image.
    public var showCursor: Bool

    public init(hideDesktopIcons: Bool = false, showCursor: Bool = false) {
        self.hideDesktopIcons = hideDesktopIcons
        self.showCursor = showCursor
    }
}

/// A still image of one whole display, at native resolution.
public struct DisplaySnapshot: Sendable {
    public let displayID: CGDirectDisplayID
    /// AppKit global points, bottom-left origin (`NSScreen.frame`).
    public let frame: CGRect
    /// Pixels per point.
    public let scale: CGFloat
    /// The display image, top-left origin, in the display's color profile.
    public let image: CGImage

    public init(displayID: CGDirectDisplayID, frame: CGRect, scale: CGFloat, image: CGImage) {
        self.displayID = displayID
        self.frame = frame
        self.scale = scale
        self.image = image
    }

    /// Crops a rect given in AppKit global points. The rect is clamped to the display;
    /// returns nil when nothing of it lies on the display.
    public func crop(toAppKitRect rect: CGRect) -> CGImage? {
        crop(toLocalRect: ScreenGeometry.localRect(forAppKitRect: rect, displayFrame: frame))
    }

    /// Crops a rect given in points relative to the display's origin (bottom-left, y up).
    /// The rect is clamped to the image; returns nil when the clamped rect is empty.
    public func crop(toLocalRect rect: CGRect) -> CGImage? {
        guard let pixels = pixelRect(forLocalRect: rect) else { return nil }
        return image.cropping(to: pixels)
    }

    /// Image pixels per point on each axis, from the image and frame sizes. Usually equal to
    /// ``scale``, but the image may not be exactly `frame × backingScaleFactor`, so crops use this.
    public var pixelsPerPoint: CGSize {
        guard frame.width > 0, frame.height > 0 else { return CGSize(width: scale, height: scale) }
        return CGSize(width: CGFloat(image.width) / frame.width, height: CGFloat(image.height) / frame.height)
    }

    /// The clamped pixel rect (top-left origin) for a display-local rect, or nil when empty.
    public func pixelRect(forLocalRect rect: CGRect) -> CGRect? {
        let ratio = pixelsPerPoint
        let raw = ScreenGeometry.pixelRect(forLocalRect: rect, displaySize: frame.size, scaleX: ratio.width, scaleY: ratio.height)
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let clamped = raw.intersection(bounds)
        guard !clamped.isNull, clamped.width >= 1, clamped.height >= 1 else { return nil }
        return clamped
    }
}
