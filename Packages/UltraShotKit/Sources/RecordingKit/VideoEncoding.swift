import AVFoundation
import CoreGraphics

/// Encoded frame size in pixels.
public struct PixelSize: Sendable, Equatable, Hashable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var cgSize: CGSize { CGSize(width: width, height: height) }
}

/// Encoder settings for recordings: H.264 video and AAC audio in an MP4 container.
public enum VideoEncoding {
    /// Average bits spent per pixel per frame. Screen content is mostly static with sharp text,
    /// so 0.1 keeps text crisp while static frames cost almost nothing.
    public static let bitsPerPixelPerFrame: Double = 0.1
    /// Floor so tiny regions and low frame rates still get legible text.
    public static let minimumBitRate = 2_000_000
    /// Ceiling to keep files sane for 5K/6K displays at high frame rates.
    public static let maximumBitRate = 120_000_000
    /// Maximum time between key frames, in seconds.
    public static let keyFrameIntervalSeconds: Double = 2

    /// Average video bit rate in bits per second:
    /// `clamp(width × height × fps × 0.1, 2 Mbit/s ... 120 Mbit/s)`.
    /// Examples: 1728×1116 at 30 fps ≈ 5.8 Mbit/s; 3456×2234 at 30 fps ≈ 23 Mbit/s, at 60 fps ≈ 46 Mbit/s.
    public static func bitRate(width: Int, height: Int, frameRate: Int) -> Int {
        let raw = Double(max(width, 0)) * Double(max(height, 0)) * Double(max(frameRate, 1)) * bitsPerPixelPerFrame
        return min(max(Int(raw.rounded()), minimumBitRate), maximumBitRate)
    }

    /// Rounds a pixel length to the nearest integer, then down to an even number (H.264 with
    /// 4:2:0 chroma needs even dimensions). Never less than 2.
    public static func evenPixelLength(_ value: CGFloat) -> Int {
        guard value.isFinite else { return 2 }
        let rounded = Int(value.rounded())
        return max(2, rounded - rounded % 2)
    }

    /// Output size for a source of `pointSize` points at `scale` pixels per point.
    public static func outputPixelSize(pointSize: CGSize, scale: CGFloat) -> PixelSize {
        let factor = scale > 0 ? scale : 1
        return PixelSize(
            width: evenPixelLength(pointSize.width * factor),
            height: evenPixelLength(pointSize.height * factor)
        )
    }

    /// `AVAssetWriterInput` output settings for the video track.
    static func videoSettings(size: PixelSize, frameRate: Int) -> [String: Any] {
        [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
            // Frames arrive as sRGB BGRA; tag the output as Rec. 709 (the spike-verified pairing).
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate(width: size.width, height: size.height, frameRate: frameRate),
                AVVideoExpectedSourceFrameRateKey: frameRate,
                AVVideoMaxKeyFrameIntervalKey: max(1, Int((Double(frameRate) * keyFrameIntervalSeconds).rounded())),
                AVVideoMaxKeyFrameIntervalDurationKey: keyFrameIntervalSeconds,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoAllowFrameReorderingKey: false
            ] as [String: Any]
        ]
    }

    /// `AVAssetWriterInput` output settings for an AAC audio track at 48 kHz.
    static func audioSettings(channels: Int) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: channels > 1 ? 128_000 : 64_000
        ]
    }
}
