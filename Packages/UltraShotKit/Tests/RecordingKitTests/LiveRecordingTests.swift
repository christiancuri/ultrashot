import AVFoundation
import CoreGraphics
import Foundation
@testable import RecordingKit
import Testing

/// Records the real screen. Runs only with Screen Recording permission; asserts on metadata
/// only (no frame is looked at) and deletes every file it writes.
@Suite("Live recording", .serialized, .enabled(if: CGPreflightScreenCaptureAccess()), .timeLimit(.minutes(2)))
@MainActor
struct LiveRecordingTests {
    @Test func mainDisplayWithPauseAndSystemAudio() async throws {
        let url = LiveTestSupport.temporaryURL("display-pause")
        defer { LiveTestSupport.removeRecording(url) }
        let config = RecordingConfiguration(
            target: .display(CGMainDisplayID(), sourceRect: nil),
            frameRate: 30,
            capturesSystemAudio: true,
            scale: 1,
            outputURL: url
        )
        let recorder = ScreenRecorder()
        var states: [RecorderState] = []
        recorder.onStateChange = { states.append($0) }

        try await recorder.start(config)
        try await Task.sleep(for: .seconds(1))
        recorder.pause()
        let atPause = recorder.elapsed
        try await Task.sleep(for: .seconds(1))
        let duringPause = recorder.elapsed
        recorder.pause() // no-op while paused
        recorder.resume()
        try await Task.sleep(for: .seconds(1))
        let result = try await recorder.stop()

        print("[live] display: elapsed at pause=\(atPause) during pause=\(duringPause) result=\(result)")
        #expect(abs(duringPause - atPause) < 0.05, "elapsed must freeze while paused")
        #expect(states == [.starting, .recording, .paused, .recording, .finishing, .finished(url)])
        #expect(recorder.state == .finished(url))
        #expect(abs(recorder.elapsed - result.duration) < 0.001)

        let displayPoints = CGSize(width: CGDisplayPixelsWide(CGMainDisplayID()), height: CGDisplayPixelsHigh(CGMainDisplayID()))
        let expected = VideoEncoding.outputPixelSize(pointSize: displayPoints, scale: 1).cgSize
        #expect(result.pixelSize == expected)
        #expect(abs(result.duration - 2) <= 0.3)

        let info = try await LiveTestSupport.assetInfo(url)
        print("[live] display: AVFoundation=\(info.duration) video=\(info.videoTrackDuration) size=\(info.videoSize) audio=\(info.audioTracks)")
        #expect(info.videoTracks == 1)
        #expect(info.audioTracks == 1)
        #expect(info.videoSize == expected)
        #expect(abs(info.duration - 2) <= 0.3)

        if let probe = try LiveTestSupport.probe(url) {
            print("[live] display: ffprobe format=\(probe.formatDuration) streams=\(probe.streams)")
            #expect(abs(probe.formatDuration - 2) <= 0.3)
            #expect(abs((probe.video?.duration ?? 0) - 2) <= 0.3)
            #expect(probe.streams.contains { $0.codecType == "audio" })
        }
    }

    @Test func staticRegionKeepsFullDurationInFFprobe() async throws {
        let window = StaticTestWindow(rect: CGRect(x: 120, y: 160, width: 240, height: 160))
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(500))
        let url = LiveTestSupport.temporaryURL("static-tail")
        defer { LiveTestSupport.removeRecording(url) }
        let config = RecordingConfiguration(
            target: .display(CGMainDisplayID(), sourceRect: window.rect),
            frameRate: 60,
            showsCursor: false,
            scale: 2,
            outputURL: url
        )
        let recorder = ScreenRecorder()
        try await recorder.start(config)
        try await Task.sleep(for: .seconds(2))
        let result = try await recorder.stop()

        let info = try await LiveTestSupport.assetInfo(url)
        let probe = try LiveTestSupport.probe(url)
        print("[live] static: result=\(result) AVFoundation=\(info.duration) videoTrack=\(info.videoTrackDuration) ffprobe=\(String(describing: probe))")
        #expect(result.pixelSize == CGSize(width: 480, height: 320))
        #expect(info.videoSize == CGSize(width: 480, height: 320))
        #expect(info.audioTracks == 0)
        #expect(abs(info.duration - 2) <= 0.3)
        let ffprobe = try #require(probe, "ffprobe not installed at \(LiveTestSupport.ffprobePath)")
        #expect(abs(ffprobe.formatDuration - 2) <= 0.3)
        #expect(abs((ffprobe.video?.duration ?? 0) - 2) <= 0.3)
        // Without the tail fix the video stream ends at the last delivered frame (measured 1.87 s
        // for a 2.09 s recording), so require ffprobe to agree with the recorder within ~3 frames.
        #expect(abs(ffprobe.formatDuration - result.duration) <= 0.05)
        #expect(abs((ffprobe.video?.duration ?? 0) - result.duration) <= 0.05)
        // A static area yields only a handful of frames (proves the tail case was exercised).
        #expect((ffprobe.video?.frames ?? .max) < 30)
    }

    @Test func ownWindowRecordingUsesWindowSize() async throws {
        let window = StaticTestWindow(rect: CGRect(x: 420, y: 160, width: 200, height: 120))
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(500))
        let url = LiveTestSupport.temporaryURL("window")
        defer { LiveTestSupport.removeRecording(url) }
        let recorder = ScreenRecorder()
        try await recorder.start(RecordingConfiguration(target: .window(window.windowID), frameRate: 30, scale: 2, outputURL: url))
        try await Task.sleep(for: .seconds(1))
        let result = try await recorder.stop()
        let info = try await LiveTestSupport.assetInfo(url)
        print("[live] window: result=\(result) AVFoundation=\(info.duration)")
        #expect(result.pixelSize == CGSize(width: 400, height: 240))
        #expect(info.videoSize == CGSize(width: 400, height: 240))
        #expect(abs(info.duration - 1) <= 0.3)
    }

    @Test func pauseThenStopEndsAtPausePoint() async throws {
        let window = StaticTestWindow(rect: CGRect(x: 120, y: 360, width: 160, height: 100))
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(500))
        let url = LiveTestSupport.temporaryURL("pause-stop")
        defer { LiveTestSupport.removeRecording(url) }
        let recorder = ScreenRecorder()
        try await recorder.start(RecordingConfiguration(
            target: .display(CGMainDisplayID(), sourceRect: window.rect), showsCursor: false, scale: 1, outputURL: url
        ))
        try await Task.sleep(for: .seconds(1))
        recorder.pause()
        try await Task.sleep(for: .seconds(1))
        let result = try await recorder.stop()
        let info = try await LiveTestSupport.assetInfo(url)
        print("[live] pause-stop: result=\(result) AVFoundation=\(info.duration)")
        #expect(abs(result.duration - 1) <= 0.3)
        #expect(abs(info.duration - 1) <= 0.3)
    }

    @Test func cancelDeletesTheFile() async throws {
        let url = LiveTestSupport.temporaryURL("cancel")
        defer { LiveTestSupport.removeRecording(url) }
        let recorder = ScreenRecorder()
        try await recorder.start(RecordingConfiguration(
            target: .display(CGMainDisplayID(), sourceRect: CGRect(x: 0, y: 0, width: 200, height: 200)), scale: 1, outputURL: url
        ))
        try await Task.sleep(for: .milliseconds(500))
        await recorder.cancel()
        #expect(recorder.state == .idle)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func cancelWhileStartingAbortsTheStart() async throws {
        let url = LiveTestSupport.temporaryURL("cancel-starting")
        defer { LiveTestSupport.removeRecording(url) }
        let recorder = ScreenRecorder()
        let config = RecordingConfiguration(
            target: .display(CGMainDisplayID(), sourceRect: CGRect(x: 0, y: 0, width: 200, height: 200)), scale: 1, outputURL: url
        )
        let start = Task { try await recorder.start(config) }
        await Task.yield()
        #expect(recorder.state == .starting)
        await recorder.cancel()
        let outcome = await start.result
        #expect(throws: CancellationError.self) { try outcome.get() }
        #expect(recorder.state == .idle)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func unknownTargetsFail() async throws {
        let recorder = ScreenRecorder()
        let url = LiveTestSupport.temporaryURL("missing")
        defer { LiveTestSupport.removeRecording(url) }
        await #expect(throws: RecordingError.displayNotFound(987_654)) {
            try await recorder.start(RecordingConfiguration(target: .display(987_654, sourceRect: nil), outputURL: url))
        }
        guard case .failed = recorder.state else {
            Issue.record("expected .failed, got \(recorder.state)")
            return
        }
        await #expect(throws: RecordingError.windowNotFound(UInt32.max)) {
            try await recorder.start(RecordingConfiguration(target: .window(UInt32.max), outputURL: url))
        }
        await #expect(throws: RecordingError.self) { _ = try await recorder.stop() }
    }

    @Test(.enabled(if: MicrophonePermission.status == .authorized))
    func microphoneAndSystemAudioMakeTwoAudioTracks() async throws {
        let url = LiveTestSupport.temporaryURL("mic")
        defer { LiveTestSupport.removeRecording(url) }
        let recorder = ScreenRecorder()
        try await recorder.start(RecordingConfiguration(
            target: .display(CGMainDisplayID(), sourceRect: CGRect(x: 0, y: 0, width: 200, height: 200)),
            capturesSystemAudio: true,
            capturesMicrophone: true,
            scale: 1,
            outputURL: url
        ))
        try await Task.sleep(for: .seconds(1.5))
        _ = try await recorder.stop()
        let info = try await LiveTestSupport.assetInfo(url)
        print("[live] mic: audioTracks=\(info.audioTracks) duration=\(info.duration)")
        #expect(info.audioTracks == 2)
    }
}
