import AVFoundation
import CoreGraphics
@testable import RecordingKit
import Testing

@Suite("VideoEncoding")
struct VideoEncodingTests {
    @Test func bitRateScalesWithPixelsAndFrameRate() {
        #expect(VideoEncoding.bitRate(width: 1920, height: 1080, frameRate: 30) == 6_220_800)
        #expect(VideoEncoding.bitRate(width: 3456, height: 2234, frameRate: 60) == 46_324_224)
        let at30 = VideoEncoding.bitRate(width: 2560, height: 1600, frameRate: 30)
        let at60 = VideoEncoding.bitRate(width: 2560, height: 1600, frameRate: 60)
        #expect(at60 == at30 * 2)
    }

    @Test func bitRateHasFloorAndCeiling() {
        #expect(VideoEncoding.bitRate(width: 200, height: 100, frameRate: 10) == VideoEncoding.minimumBitRate)
        #expect(VideoEncoding.bitRate(width: 0, height: 0, frameRate: 0) == VideoEncoding.minimumBitRate)
        #expect(VideoEncoding.bitRate(width: 6016, height: 3384, frameRate: 120) == VideoEncoding.maximumBitRate)
    }

    @Test(arguments: [
        (CGFloat(100), 100), (101, 100), (100.4, 100), (100.6, 100), (101.5, 102), (99.5, 100),
        (1, 2), (0, 2), (-5, 2), (3, 2), (2234, 2234)
    ])
    func evenPixelLength(input: CGFloat, expected: Int) {
        #expect(VideoEncoding.evenPixelLength(input) == expected)
    }

    @Test func evenPixelLengthHandlesNonFinite() {
        #expect(VideoEncoding.evenPixelLength(.infinity) == 2)
        #expect(VideoEncoding.evenPixelLength(.nan) == 2)
    }

    @Test func outputPixelSizeAppliesScale() {
        #expect(VideoEncoding.outputPixelSize(pointSize: CGSize(width: 1728, height: 1117), scale: 2)
            == PixelSize(width: 3456, height: 2234))
        #expect(VideoEncoding.outputPixelSize(pointSize: CGSize(width: 1728, height: 1117), scale: 1)
            == PixelSize(width: 1728, height: 1116))
        #expect(VideoEncoding.outputPixelSize(pointSize: CGSize(width: 333.3, height: 201), scale: 1.5)
            == PixelSize(width: 500, height: 302))
    }

    @Test func videoSettingsUseH264WithKeyFramesEveryTwoSeconds() throws {
        let settings = VideoEncoding.videoSettings(size: PixelSize(width: 1280, height: 720), frameRate: 30)
        #expect(settings[AVVideoCodecKey] as? AVVideoCodecType == .h264)
        #expect(settings["AVVideoWidthKey"] as? Int == 1280)
        #expect(settings["AVVideoHeightKey"] as? Int == 720)
        let compression = try #require(settings["AVVideoCompressionPropertiesKey"] as? [String: Any])
        #expect(compression["MaxKeyFrameInterval"] as? Int == 60)
        #expect(compression["MaxKeyFrameIntervalDuration"] as? Double == 2)
        #expect(compression["AverageBitRate"] as? Int == VideoEncoding.bitRate(width: 1280, height: 720, frameRate: 30))
    }
}
