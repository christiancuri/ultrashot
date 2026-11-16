import CoreGraphics
import Foundation

/// Errors thrown by CaptureKit.
public enum CaptureError: Error, Equatable, Sendable {
    /// Screen Recording permission is not granted to this process.
    case permissionDenied
    /// The display is not connected (or not listed by ScreenCaptureKit).
    case displayNotFound(CGDirectDisplayID)
    /// The window is not on screen (or not listed by ScreenCaptureKit).
    case windowNotFound(CGWindowID)
    /// ScreenCaptureKit returned no image.
    case noImage
    /// ScreenCaptureKit failed; carries the underlying error description.
    case captureFailed(String)
    /// An image could not be encoded into the requested format.
    case encodingFailed
    /// Writing the encoded image to disk failed; carries the underlying error description.
    case writeFailed(String)
}

extension CaptureError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Screen Recording permission is not granted."
        case let .displayNotFound(id):
            "Display \(id) is not available for capture."
        case let .windowNotFound(id):
            "Window \(id) is not available for capture."
        case .noImage:
            "The capture returned no image."
        case let .captureFailed(reason):
            "The capture failed: \(reason)"
        case .encodingFailed:
            "The image could not be encoded."
        case let .writeFailed(reason):
            "The image could not be written: \(reason)"
        }
    }
}
