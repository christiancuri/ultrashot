import CoreGraphics
import Foundation

/// Everything the recorder needs to know before it starts. Immutable for the whole recording.
public struct RecordingConfiguration: Sendable, Equatable {
    /// What to record.
    public enum Target: Sendable, Equatable {
        /// A display. `sourceRect` is in display-local points with a TOP-LEFT origin (the
        /// convention `SCStreamConfiguration.sourceRect` expects); `nil` records the full display.
        case display(CGDirectDisplayID, sourceRect: CGRect?)
        /// A single window, captured independently of what covers it. The output size is fixed
        /// at start from the window's size; later resizes are scaled into that frame.
        case window(CGWindowID)
    }

    public var target: Target
    /// Target frame rate (frames per second). Clamped to 1...120.
    public var frameRate: Int
    public var showsCursor: Bool
    public var capturesSystemAudio: Bool
    public var capturesMicrophone: Bool
    /// `AVCaptureDevice.uniqueID` of the microphone; `nil` uses the system default input.
    public var microphoneDeviceID: String?
    /// Output pixels per point: 2 records a Retina display natively, 1 downscales by half.
    public var scale: CGFloat
    /// Windows hidden from the video (our HUD and selection border). Ids that ScreenCaptureKit
    /// does not list (for example windows with `sharingType = .none`) are ignored.
    public var excludedWindowIDs: [CGWindowID]
    /// Leave our own process' sounds out of the system audio track.
    public var excludesCurrentProcessAudio: Bool
    /// Destination file (.mp4). An existing file at this URL is replaced.
    public var outputURL: URL

    public init(
        target: Target,
        frameRate: Int = 30,
        showsCursor: Bool = true,
        capturesSystemAudio: Bool = false,
        capturesMicrophone: Bool = false,
        microphoneDeviceID: String? = nil,
        scale: CGFloat = 2,
        excludedWindowIDs: [CGWindowID] = [],
        excludesCurrentProcessAudio: Bool = true,
        outputURL: URL
    ) {
        self.target = target
        self.frameRate = frameRate
        self.showsCursor = showsCursor
        self.capturesSystemAudio = capturesSystemAudio
        self.capturesMicrophone = capturesMicrophone
        self.microphoneDeviceID = microphoneDeviceID
        self.scale = scale
        self.excludedWindowIDs = excludedWindowIDs
        self.excludesCurrentProcessAudio = excludesCurrentProcessAudio
        self.outputURL = outputURL
    }

    /// `frameRate` limited to the range the recorder supports.
    public var effectiveFrameRate: Int { min(max(frameRate, 1), 120) }
}
