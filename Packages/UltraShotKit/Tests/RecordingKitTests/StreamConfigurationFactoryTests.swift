import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
@testable import RecordingKit
import Testing

@Suite("StreamConfigurationFactory")
struct StreamConfigurationFactoryTests {
    private let url = URL(fileURLWithPath: "/tmp/never-written.mp4")
    private let display = CGSize(width: 1728, height: 1117)

    @Test func regionUsesSourceRectTimesScale() throws {
        let rect = CGRect(x: 200, y: 100, width: 400, height: 301)
        let config = RecordingConfiguration(target: .display(1, sourceRect: rect), frameRate: 60, scale: 2, outputURL: url)
        let stream = try StreamConfigurationFactory.makeStreamConfiguration(for: config, contentSize: display)
        #expect(stream.width == 800)
        #expect(stream.height == 602)
        #expect(stream.sourceRect == rect)
        #expect(stream.minimumFrameInterval == CMTime(value: 1, timescale: 60))
        #expect(stream.pixelFormat == kCVPixelFormatType_32BGRA)
        #expect(stream.colorSpaceName == CGColorSpace.sRGB)
        #expect(stream.queueDepth == 6)
    }

    @Test func fullDisplayUsesContentSize() throws {
        let config = RecordingConfiguration(target: .display(1, sourceRect: nil), frameRate: 30, scale: 1, outputURL: url)
        let stream = try StreamConfigurationFactory.makeStreamConfiguration(for: config, contentSize: display)
        #expect(stream.width == 1728)
        #expect(stream.height == 1116)
        #expect(stream.minimumFrameInterval == CMTime(value: 1, timescale: 30))
        #expect(try StreamConfigurationFactory.clippedSourceRect(for: config, contentSize: display) == nil)
    }

    @Test func windowIgnoresSourceRectAndUsesWindowSize() throws {
        let config = RecordingConfiguration(target: .window(42), scale: 2, outputURL: url)
        let stream = try StreamConfigurationFactory.makeStreamConfiguration(for: config, contentSize: CGSize(width: 640, height: 480))
        #expect(stream.width == 1280)
        #expect(stream.height == 960)
    }

    @Test func sourceRectIsClippedToDisplay() throws {
        let config = RecordingConfiguration(
            target: .display(1, sourceRect: CGRect(x: 1600, y: -20, width: 400, height: 220)), scale: 1, outputURL: url
        )
        let clipped = try StreamConfigurationFactory.clippedSourceRect(for: config, contentSize: display)
        #expect(clipped == CGRect(x: 1600, y: 0, width: 128, height: 200))
        #expect(try StreamConfigurationFactory.outputPixelSize(for: config, contentSize: display) == PixelSize(width: 128, height: 200))
    }

    @Test func sourceRectOutsideDisplayThrows() {
        let config = RecordingConfiguration(
            target: .display(1, sourceRect: CGRect(x: 5000, y: 0, width: 10, height: 10)), outputURL: url
        )
        #expect(throws: RecordingError.emptySourceRect) {
            try StreamConfigurationFactory.makeStreamConfiguration(for: config, contentSize: display)
        }
    }

    @Test func cursorAndAudioFlagsAreMapped() throws {
        let off = RecordingConfiguration(target: .display(1, sourceRect: nil), showsCursor: false, outputURL: url)
        let offStream = try StreamConfigurationFactory.makeStreamConfiguration(for: off, contentSize: display)
        #expect(!offStream.showsCursor)
        #expect(!offStream.capturesAudio)
        #expect(!offStream.captureMicrophone)

        let on = RecordingConfiguration(
            target: .display(1, sourceRect: nil),
            showsCursor: true,
            capturesSystemAudio: true,
            capturesMicrophone: true,
            microphoneDeviceID: "BuiltInMicrophoneDevice",
            excludesCurrentProcessAudio: false,
            outputURL: url
        )
        let onStream = try StreamConfigurationFactory.makeStreamConfiguration(for: on, contentSize: display)
        #expect(onStream.showsCursor)
        #expect(onStream.capturesAudio)
        #expect(!onStream.excludesCurrentProcessAudio)
        #expect(onStream.sampleRate == 48_000)
        #expect(onStream.channelCount == 2)
        #expect(onStream.captureMicrophone)
        #expect(onStream.microphoneCaptureDeviceID == "BuiltInMicrophoneDevice")
    }

    @Test func frameRateIsClamped() throws {
        let fast = RecordingConfiguration(target: .display(1, sourceRect: nil), frameRate: 500, outputURL: url)
        let slow = RecordingConfiguration(target: .display(1, sourceRect: nil), frameRate: 0, outputURL: url)
        #expect(try StreamConfigurationFactory.makeStreamConfiguration(for: fast, contentSize: display).minimumFrameInterval
            == CMTime(value: 1, timescale: 120))
        #expect(try StreamConfigurationFactory.makeStreamConfiguration(for: slow, contentSize: display).minimumFrameInterval
            == CMTime(value: 1, timescale: 1))
    }
}
