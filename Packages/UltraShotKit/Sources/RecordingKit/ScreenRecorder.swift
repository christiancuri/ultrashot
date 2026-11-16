import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Records a display, a display region or a window to an H.264 MP4 with optional system audio
/// and microphone tracks, with pause/resume into a single file.
///
/// Track layout: video first, then system audio (stereo AAC) when enabled, then microphone
/// (mono AAC) when enabled. With both audio sources on, the file has two separate audio tracks.
///
/// ScreenCaptureKit objects stay on the main actor; sample buffers are handled by a
/// queue-confined `RecordingSink`.
@MainActor
public final class ScreenRecorder {
    private struct Session {
        let token: UUID
        let stream: SCStream
        let sink: RecordingSink
        let configuration: RecordingConfiguration
    }

    public private(set) var state: RecorderState = .idle {
        didSet { if state != oldValue { onStateChange?(state) } }
    }

    /// Called on the main actor after every state change.
    public var onStateChange: ((RecorderState) -> Void)?

    /// The most recent finished recording, including one finalized after an interruption.
    public private(set) var lastResult: RecordingResult?

    private var session: Session?
    /// Token of a `start` that has not created its session yet; cleared by `cancel()`.
    private var pendingStart: UUID?
    /// The finalize in flight (`.finishing`), so a `stop()` that races an unexpected stop gets
    /// the same result instead of an error.
    private var finalizing: Task<RecordingResult, any Error>?

    public init() {}

    /// Recorded time excluding pauses. After a recording finishes, its final duration.
    public var elapsed: TimeInterval {
        if let session { return session.sink.elapsed() }
        if case .finished = state { return lastResult?.duration ?? 0 }
        return 0
    }

    // MARK: Start

    /// Starts recording. Throws (and moves to `.failed`) when the target is unavailable, the
    /// writer cannot be created or capture cannot start (for example without permission).
    public func start(_ configuration: RecordingConfiguration) async throws {
        guard state.canStart else { throw RecordingError.invalidState("start while \(state)") }
        state = .starting
        finalizing = nil
        let token = UUID()
        pendingStart = token
        defer { if pendingStart == token { pendingStart = nil } }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard pendingStart == token else { throw CancellationError() } // cancelled while starting
            let filter = try Self.makeFilter(for: configuration, content: content)
            let streamConfiguration = try StreamConfigurationFactory.makeStreamConfiguration(
                for: configuration,
                contentSize: filter.contentRect.size
            )
            let size = PixelSize(width: streamConfiguration.width, height: streamConfiguration.height)
            try Self.prepareOutputLocation(configuration.outputURL)
            let sink = try RecordingSink(
                url: configuration.outputURL,
                size: size,
                frameRate: configuration.effectiveFrameRate,
                systemAudio: configuration.capturesSystemAudio,
                microphone: configuration.capturesMicrophone,
                onUnexpectedStop: { [weak self] reason in
                    Task { @MainActor in await self?.handleUnexpectedStop(token: token, reason: reason) }
                }
            )
            let stream = SCStream(filter: filter, configuration: streamConfiguration, delegate: sink)
            try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sink.queue)
            if configuration.capturesSystemAudio {
                try stream.addStreamOutput(sink, type: .audio, sampleHandlerQueue: sink.queue)
            }
            if configuration.capturesMicrophone {
                try stream.addStreamOutput(sink, type: .microphone, sampleHandlerQueue: sink.queue)
            }
            session = Session(token: token, stream: stream, sink: sink, configuration: configuration)
            do {
                try await Self.startCapture(stream)
            } catch {
                if session?.token == token { session = nil }
                sink.cancel()
                throw RecordingError.captureFailed(error.localizedDescription)
            }
            guard session?.token == token else {
                // Cancelled while starting.
                try? await Self.stopCapture(stream)
                throw CancellationError()
            }
            state = .recording
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try? FileManager.default.removeItem(at: configuration.outputURL)
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    // MARK: Pause / resume

    /// Pauses a recording in progress. No-op unless `.recording`.
    public func pause() {
        guard state == .recording, let session else { return }
        session.sink.pause()
        state = .paused
    }

    /// Resumes a paused recording. No-op unless `.paused`.
    public func resume() {
        guard state == .paused, let session else { return }
        session.sink.resume()
        state = .recording
    }

    // MARK: Stop / cancel

    /// Stops and finalizes the file. When stopped while paused, the video ends at the pause point.
    /// While the recorder is already finalizing (the stream stopped by itself), returns that
    /// finalize's result.
    public func stop() async throws -> RecordingResult {
        if state == .finishing, let finalizing { return try await finalizing.value }
        if case .finished = state, session == nil, let lastResult { return lastResult } // finalized on its own just now
        guard state.isActive, let session else { throw RecordingError.invalidState("stop while \(state)") }
        return try await finalize(session, interruption: nil)
    }

    /// Stops without keeping anything: the file is deleted and the state returns to `.idle`.
    public func cancel() async {
        if state == .finishing, let finalizing {
            // Already finalizing on its own: wait for the file, then throw it away.
            if let result = try? await finalizing.value { try? FileManager.default.removeItem(at: result.url) }
            state = .idle
            return
        }
        guard let session else {
            // Nothing captured yet: a pending `start` notices the cleared token and bails out.
            pendingStart = nil
            if state != .finishing { state = .idle }
            return
        }
        self.session = nil
        session.sink.cancel()
        try? await Self.stopCapture(session.stream)
        try? FileManager.default.removeItem(at: session.configuration.outputURL)
        state = .idle
    }

    private func finalize(_ session: Session, interruption: String?) async throws -> RecordingResult {
        let task = Task { @MainActor in try await self.performFinalize(session, interruption: interruption) }
        finalizing = task
        state = .finishing
        return try await task.value
    }

    private func performFinalize(_ session: Session, interruption: String?) async throws -> RecordingResult {
        session.sink.markStop()
        // Throws when the stream already stopped by itself; the sink has the samples either way.
        try? await Self.stopCapture(session.stream)
        if self.session?.token == session.token { self.session = nil }
        switch await session.sink.finish() {
        case .success(let finished):
            let result = RecordingResult(
                url: session.configuration.outputURL,
                duration: finished.duration,
                pixelSize: session.sink.pixelSize.cgSize,
                interruption: interruption
            )
            lastResult = result
            state = .finished(result.url)
            return result
        case .failure(let error):
            try? FileManager.default.removeItem(at: session.configuration.outputURL)
            let message = [interruption, error.localizedDescription].compactMap(\.self).joined(separator: " ")
            state = .failed(message)
            throw error
        }
    }

    /// The stream stopped by itself (display gone, permission revoked, stopped from the system
    /// indicator) or the writer failed: keep what was recorded when possible.
    private func handleUnexpectedStop(token: UUID, reason: String) async {
        guard let session, session.token == token, state.isActive else { return }
        _ = try? await finalize(session, interruption: reason)
    }

    #if DEBUG
    /// Debug automation: behaves as if the stream had stopped by itself (display gone,
    /// stopped from the system indicator), while the real stream is still running.
    public func debugSimulateUnexpectedStop(reason: String) {
        guard let session else { return }
        Task { await handleUnexpectedStop(token: session.token, reason: reason) }
    }
    #endif

    // MARK: Helpers

    private static func makeFilter(for configuration: RecordingConfiguration, content: SCShareableContent) throws -> SCContentFilter {
        switch configuration.target {
        case .display(let displayID, _):
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                throw RecordingError.displayNotFound(displayID)
            }
            let excludedIDs = Set(configuration.excludedWindowIDs)
            let excluded = content.windows.filter { excludedIDs.contains($0.windowID) }
            return SCContentFilter(display: display, excludingWindows: excluded)
        case .window(let windowID):
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                throw RecordingError.windowNotFound(windowID)
            }
            return SCContentFilter(desktopIndependentWindow: window)
        }
    }

    private static func prepareOutputLocation(_ url: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
    }

    private static func startCapture(_ stream: SCStream) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            stream.startCapture { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    private static func stopCapture(_ stream: SCStream) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            stream.stopCapture { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }
}
