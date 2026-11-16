import CoreGraphics
import CoreMedia
import CoreVideo
import ScreenCaptureKit

/// Pure mapping from `RecordingConfiguration` to `SCStreamConfiguration`, kept separate from the
/// recorder so it can be tested without capturing.
public enum StreamConfigurationFactory {
    /// Pixel buffers per stream. The recorder keeps one frame for the static-tail fix and the
    /// encoder holds a few, so stay above the default of 3.
    static let queueDepth = 6

    /// The display region to capture: `sourceRect` clipped to `contentSize` (display points,
    /// top-left origin), or `nil` for the full display and for window targets.
    /// Throws `RecordingError.emptySourceRect` when the rect misses the display.
    public static func clippedSourceRect(for config: RecordingConfiguration, contentSize: CGSize) throws -> CGRect? {
        guard case .display(_, let sourceRect?) = config.target else { return nil }
        let clipped = sourceRect.standardized.intersection(CGRect(origin: .zero, size: contentSize))
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else { throw RecordingError.emptySourceRect }
        return clipped
    }

    /// Encoded size: captured points (`sourceRect` or the full content) × `scale`, rounded to
    /// even pixels.
    public static func outputPixelSize(for config: RecordingConfiguration, contentSize: CGSize) throws -> PixelSize {
        let points = try clippedSourceRect(for: config, contentSize: contentSize)?.size ?? contentSize
        return VideoEncoding.outputPixelSize(pointSize: points, scale: config.scale)
    }

    /// Builds the stream configuration.
    /// - Parameter contentSize: size in points of the filter's content (`SCContentFilter.contentRect`):
    ///   the display for display targets, the window for window targets.
    public static func makeStreamConfiguration(
        for config: RecordingConfiguration,
        contentSize: CGSize
    ) throws -> SCStreamConfiguration {
        let size = try outputPixelSize(for: config, contentSize: contentSize)
        let stream = SCStreamConfiguration()
        stream.width = size.width
        stream.height = size.height
        if let rect = try clippedSourceRect(for: config, contentSize: contentSize) {
            stream.sourceRect = rect
        }
        stream.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(config.effectiveFrameRate))
        stream.pixelFormat = kCVPixelFormatType_32BGRA
        // Must be set explicitly: the default produced wrong colors in the spike (and reading the
        // default value crashed, so never read it before assigning).
        stream.colorSpaceName = CGColorSpace.sRGB
        stream.showsCursor = config.showsCursor
        stream.queueDepth = queueDepth

        stream.capturesAudio = config.capturesSystemAudio
        stream.excludesCurrentProcessAudio = config.excludesCurrentProcessAudio
        stream.sampleRate = 48_000
        stream.channelCount = 2

        stream.captureMicrophone = config.capturesMicrophone
        if config.capturesMicrophone {
            stream.microphoneCaptureDeviceID = config.microphoneDeviceID
        }
        return stream
    }
}
