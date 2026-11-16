import CoreGraphics
import Foundation

/// A capturable on-screen window. `id` equals `SCWindow.windowID`.
public struct WindowInfo: Sendable, Equatable {
    public var id: CGWindowID
    /// CG global points, top-left origin (`kCGWindowBounds`).
    public var frameCG: CGRect
    public var ownerPID: pid_t
    public var ownerName: String
    /// Window title; nil when the window has none or Screen Recording is not granted.
    public var title: String?
    public var layer: Int

    public init(id: CGWindowID, frameCG: CGRect, ownerPID: pid_t, ownerName: String, title: String?, layer: Int) {
        self.id = id
        self.frameCG = frameCG
        self.ownerPID = ownerPID
        self.ownerName = ownerName
        self.title = title
        self.layer = layer
    }
}

/// Window enumeration for hover-highlight and window capture.
public enum WindowList {
    /// Windows smaller than this (points, either side) are ignored.
    public static let minimumSide: CGFloat = 40

    /// On-screen normal windows (layer 0, alpha > 0, at least 40×40 pt), front to back,
    /// excluding windows owned by `excludingPID` (pass the app's own pid).
    public static func onScreen(excludingPID: pid_t) -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let entries = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        return windows(from: entries, excludingPID: excludingPID)
    }

    /// The frontmost window containing `cgPoint` (CG global points). `windows` must be front to back,
    /// as returned by `onScreen(excludingPID:)`.
    public static func topmost(at cgPoint: CGPoint, in windows: [WindowInfo]) -> WindowInfo? {
        windows.first { $0.frameCG.contains(cgPoint) }
    }

    /// Parses and filters raw `CGWindowListCopyWindowInfo` entries, keeping their order.
    static func windows(from entries: [[String: Any]], excludingPID: pid_t) -> [WindowInfo] {
        entries.compactMap { info(from: $0) }.filter { window in
            window.layer == 0
                && window.ownerPID != excludingPID
                && window.frameCG.width >= minimumSide
                && window.frameCG.height >= minimumSide
        }
    }

    private static func info(from entry: [String: Any]) -> WindowInfo? {
        guard
            let number = entry[kCGWindowNumber as String] as? NSNumber,
            let pid = entry[kCGWindowOwnerPID as String] as? NSNumber,
            let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
            let bounds = CGRect(dictionaryRepresentation: boundsDict)
        else { return nil }
        let alpha = (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
        guard alpha > 0 else { return nil }
        let title = (entry[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return WindowInfo(
            id: number.uint32Value,
            frameCG: bounds,
            ownerPID: pid.int32Value,
            ownerName: entry[kCGWindowOwnerName as String] as? String ?? "",
            title: title,
            layer: (entry[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        )
    }
}
