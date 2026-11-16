import CoreGraphics
import Foundation

/// Lifecycle of a `ScreenRecorder`.
public enum RecorderState: Sendable, Equatable {
    case idle
    case starting
    case recording
    case paused
    case finishing
    case finished(URL)
    case failed(String)

    /// True while a recording is in progress (capturing or paused).
    public var isActive: Bool {
        switch self {
        case .recording, .paused: true
        default: false
        }
    }

    /// True when `start` may be called.
    public var canStart: Bool {
        switch self {
        case .idle, .finished, .failed: true
        default: false
        }
    }
}

/// A finished recording.
public struct RecordingResult: Sendable, Equatable {
    public var url: URL
    /// Recorded time in seconds, excluding pauses.
    public var duration: TimeInterval
    /// Encoded video size in pixels.
    public var pixelSize: CGSize
    /// Why the recording ended on its own (display disconnected, permission revoked, stopped
    /// from the system's screen-sharing indicator). `nil` when it was stopped with `stop()`.
    public var interruption: String?

    public init(url: URL, duration: TimeInterval, pixelSize: CGSize, interruption: String? = nil) {
        self.url = url
        self.duration = duration
        self.pixelSize = pixelSize
        self.interruption = interruption
    }
}

public enum RecordingError: Error, LocalizedError, Equatable {
    case invalidState(String)
    case displayNotFound(CGDirectDisplayID)
    case windowNotFound(CGWindowID)
    case emptySourceRect
    case writerFailed(String)
    case noFramesCaptured
    case captureFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidState(let detail): "The recorder cannot do that now (\(detail))."
        case .displayNotFound(let id): "Display \(id) is not available for recording."
        case .windowNotFound(let id): "Window \(id) is not available for recording."
        case .emptySourceRect: "The recording area does not intersect the display."
        case .writerFailed(let detail): "Could not write the video file: \(detail)"
        case .noFramesCaptured: "No video frames were captured."
        case .captureFailed(let detail): "Screen capture failed: \(detail)"
        }
    }
}
