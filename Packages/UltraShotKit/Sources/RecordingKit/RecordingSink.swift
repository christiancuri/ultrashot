import AVFoundation
import ScreenCaptureKit

/// Receives ScreenCaptureKit sample buffers and writes them to an `AVAssetWriter`.
///
/// All mutable state is confined to `queue`, which is also the stream's sample handler queue.
/// Main-actor callers reach it through `queue.sync` / `queue.async`; only Sendable values leave.
final class RecordingSink: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    struct Finished: Sendable {
        let duration: TimeInterval
        let tailFrameAppended: Bool
    }

    /// Per-track append bookkeeping for an audio input.
    private struct AudioTrack {
        let input: AVAssetWriterInput
        var lastEnd: CMTime?
    }

    let queue = DispatchQueue(label: "RecordingKit.RecordingSink", qos: .userInitiated)
    let pixelSize: PixelSize

    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let frameDuration: CMTime
    /// Called at most once, on an arbitrary queue, when the stream stops by itself or the writer fails.
    private let onUnexpectedStop: @Sendable (String) -> Void

    // MARK: Queue-confined state

    private var clock = PauseClock()
    private var systemAudio: AudioTrack?
    private var microphone: AudioTrack?
    /// Recorded-timeline time the writer session started at (first video frame).
    private var sessionStart: CMTime?
    /// Recorded-timeline PTS of the last appended video frame.
    private var lastVideoTime: CMTime?
    /// Host PTS of the last appended video frame.
    private var lastAppendedSourceTime: CMTime?
    /// Newest complete frame, kept even while paused; re-appended on resume and at stop.
    private var latestFrame: CMSampleBuffer?
    /// Host time the recording stopped at; later samples are dropped.
    private var stopTime: CMTime?
    /// Set once inputs are finished or the writer is cancelled; nothing may be appended after.
    private var isClosed = false
    private var didReportStop = false

    init(
        url: URL,
        size: PixelSize,
        frameRate: Int,
        systemAudio: Bool,
        microphone: Bool,
        onUnexpectedStop: @escaping @Sendable (String) -> Void
    ) throws {
        pixelSize = size
        frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(frameRate, 1)))
        self.onUnexpectedStop = onUnexpectedStop
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: VideoEncoding.videoSettings(size: size, frameRate: frameRate))
        videoInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(videoInput) else { throw RecordingError.writerFailed("cannot add the video track") }
        writer.add(videoInput)
        // Track order: video, system audio, microphone.
        self.systemAudio = try Self.addAudioInput(to: writer, channels: 2, enabled: systemAudio)
        self.microphone = try Self.addAudioInput(to: writer, channels: 1, enabled: microphone)
        super.init()
        guard writer.startWriting() else {
            throw RecordingError.writerFailed(writer.error?.localizedDescription ?? "startWriting failed")
        }
    }

    private static func addAudioInput(to writer: AVAssetWriter, channels: Int, enabled: Bool) throws -> AudioTrack? {
        guard enabled else { return nil }
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: VideoEncoding.audioSettings(channels: channels))
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw RecordingError.writerFailed("cannot add an audio track") }
        writer.add(input)
        return AudioTrack(input: input)
    }

    // MARK: Control (called from the main actor)

    /// Recorded time so far, excluding pauses.
    func elapsed() -> TimeInterval {
        queue.sync { clock.recordedDuration(now: stopTime ?? HostClock.now()).seconds }
    }

    func pause() {
        queue.sync { _ = clock.pause(at: HostClock.now()) }
    }

    func resume() {
        queue.sync {
            let now = HostClock.now()
            guard clock.resume(at: now) else { return }
            // The screen may have changed while paused and then gone static, in which case no new
            // frame would arrive; show the newest frame from the resume point on.
            if let frame = latestFrame, let sent = lastAppendedSourceTime, frame.presentationTimeStamp > sent {
                appendVideo(frame, at: clock.adjusted(now))
            }
        }
    }

    /// Marks the stop instant; samples captured later are dropped. Only the first call counts.
    func markStop() {
        queue.sync { markStopOnQueue(HostClock.now()) }
    }

    private func markStopOnQueue(_ time: CMTime) {
        if stopTime == nil { stopTime = time }
    }

    /// Finalizes the file. Call after `markStop()` and after the stream stopped.
    func finish() async -> Result<Finished, RecordingError> {
        await withCheckedContinuation { continuation in
            queue.async { self.finishOnQueue { continuation.resume(returning: $0) } }
        }
    }

    /// Discards the recording (the caller deletes the file).
    func cancel() {
        queue.sync {
            markStopOnQueue(HostClock.now())
            isClosed = true
            if writer.status == .writing { writer.cancelWriting() }
        }
    }

    private func finishOnQueue(_ completion: @escaping @Sendable (Result<Finished, RecordingError>) -> Void) {
        markStopOnQueue(HostClock.now())
        guard !isClosed else { return completion(.failure(.writerFailed("the recording was already closed"))) }
        isClosed = true
        guard writer.status == .writing else {
            return completion(.failure(.writerFailed(writer.error?.localizedDescription ?? "writer status \(writer.status.rawValue)")))
        }
        guard let sessionStart, let stopTime else {
            writer.cancelWriting()
            return completion(.failure(.noFramesCaptured))
        }
        let end = max(clock.adjusted(stopTime), sessionStart)
        let tailAppended = appendTailFrame(before: end)
        videoInput.markAsFinished()
        systemAudio?.input.markAsFinished()
        microphone?.input.markAsFinished()
        writer.endSession(atSourceTime: end)
        let duration = (end - sessionStart).seconds
        writer.finishWriting { [self] in
            queue.async { [self] in
                if writer.status == .completed {
                    completion(.success(Finished(duration: duration, tailFrameAppended: tailAppended)))
                } else {
                    completion(.failure(.writerFailed(writer.error?.localizedDescription ?? "writer status \(writer.status.rawValue)")))
                }
            }
        }
    }

    /// Static-tail fix: when the screen is static, ScreenCaptureKit stops delivering frames, so the
    /// last sample can sit far before the stop time. Players that ignore the edit list then report
    /// a short duration. Re-append the newest frame one frame interval before `end` so the video
    /// track itself reaches the stop time.
    private func appendTailFrame(before end: CMTime) -> Bool {
        guard let frame = latestFrame, let last = lastVideoTime else { return false }
        let target = end - frameDuration
        guard target > last else { return false }
        return appendVideo(frame, at: target)
    }

    // MARK: SCStreamOutput / SCStreamDelegate

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid, !isClosed, writer.status == .writing else { return }
        let pts = sampleBuffer.presentationTimeStamp
        guard pts.isValid else { return }
        if let stopTime, pts > stopTime { return }
        switch type {
        case .screen:
            handleVideo(sampleBuffer, pts: pts)
        case .audio:
            if var track = systemAudio { handleAudio(sampleBuffer, pts: pts, track: &track); systemAudio = track }
        case .microphone:
            if var track = microphone { handleAudio(sampleBuffer, pts: pts, track: &track); microphone = track }
        @unknown default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let now = HostClock.now()
        queue.async { [self] in
            markStopOnQueue(now)
            reportUnexpectedStop(error.localizedDescription)
        }
    }

    // MARK: Appending

    private func handleVideo(_ sampleBuffer: CMSampleBuffer, pts: CMTime) {
        // Only .complete frames carry new pixels; .idle/.blank/.started/... must be skipped.
        guard Self.frameStatus(of: sampleBuffer) == .complete, sampleBuffer.imageBuffer != nil else { return }
        latestFrame = sampleBuffer
        guard !clock.isPaused(at: pts) else { return }
        if sessionStart == nil {
            // PTS is host-clock time, so the session starts at the first frame, not at zero.
            clock.start(at: pts)
            let start = clock.adjusted(pts)
            writer.startSession(atSourceTime: start)
            sessionStart = start
        }
        appendVideo(sampleBuffer, at: clock.adjusted(pts))
    }

    @discardableResult
    private func appendVideo(_ sampleBuffer: CMSampleBuffer, at time: CMTime) -> Bool {
        guard writer.status == .writing, sessionStart != nil else { return false }
        if let last = lastVideoTime, time <= last { return false }
        guard videoInput.isReadyForMoreMediaData else { return false }
        guard let buffer = Self.retimed(sampleBuffer, by: time - sampleBuffer.presentationTimeStamp) else { return false }
        guard videoInput.append(buffer) else {
            reportWriterFailure()
            return false
        }
        lastVideoTime = time
        lastAppendedSourceTime = sampleBuffer.presentationTimeStamp
        return true
    }

    private func handleAudio(_ sampleBuffer: CMSampleBuffer, pts: CMTime, track: inout AudioTrack) {
        // Audio before the first video frame is dropped: the session starts at that frame.
        guard let sessionStart, !clock.isPaused(at: pts) else { return }
        let time = clock.adjusted(pts)
        guard time >= sessionStart else { return }
        // A buffer straddling a pause boundary can overlap the next one after retiming; drop it.
        if let lastEnd = track.lastEnd, time < lastEnd { return }
        guard track.input.isReadyForMoreMediaData,
              let buffer = Self.retimed(sampleBuffer, by: time - pts) else { return }
        guard track.input.append(buffer) else {
            reportWriterFailure()
            return
        }
        let duration = sampleBuffer.duration
        track.lastEnd = duration.isValid ? time + duration : time
    }

    private func reportWriterFailure() {
        reportUnexpectedStop("Video writer failed: \(writer.error?.localizedDescription ?? "unknown error")")
    }

    private func reportUnexpectedStop(_ reason: String) {
        guard !didReportStop else { return }
        didReportStop = true
        onUnexpectedStop(reason)
    }

    // MARK: Helpers

    static func frameStatus(of sampleBuffer: CMSampleBuffer) -> SCFrameStatus? {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int else { return nil }
        return SCFrameStatus(rawValue: raw)
    }

    /// Shifts every timestamp of `sampleBuffer` by `delta`, sharing the media data.
    static func retimed(_ sampleBuffer: CMSampleBuffer, by delta: CMTime) -> CMSampleBuffer? {
        guard delta != .zero else { return sampleBuffer }
        guard let timings = try? sampleBuffer.sampleTimingInfos() else { return nil }
        let shifted = timings.map { timing in
            CMSampleTimingInfo(
                duration: timing.duration,
                presentationTimeStamp: timing.presentationTimeStamp + delta,
                decodeTimeStamp: timing.decodeTimeStamp.isValid ? timing.decodeTimeStamp + delta : .invalid
            )
        }
        return try? CMSampleBuffer(copying: sampleBuffer, withNewTiming: shifted)
    }
}
