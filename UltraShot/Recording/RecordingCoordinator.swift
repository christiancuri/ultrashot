import AppKit
import CoreMedia
import Observation
import RecordingKit
import UltraShotCore

/// Screen recording: area selection, recorder, HUD. The status item observes ``state``
/// and ``elapsed``.
///
/// Flow: ``recordScreen()`` → ``RecordSelectionController`` (live dimmed overlay + panel)
/// → ``RecordingHUD`` + `ScreenRecorder` → ``AppModel/deliver(_:)``. Pressing the Record
/// Screen shortcut (or clicking the status item) again stops the recording.
@MainActor
@Observable
final class RecordingCoordinator {
    enum RecordingState: Equatable {
        case idle
        case selecting
        case recording
        case paused
    }

    /// One recording in progress, from the moment its HUD appears until it is stopped.
    private final class ActiveRecording {
        let request: RecordingRequest
        /// `nil` in the Debug `record-panel` demo, which shows the HUD without capturing.
        let recorder: ScreenRecorder?
        let hud: RecordingHUD
        var demoClock = PauseClock()
        var isEnding = false

        init(request: RecordingRequest, recorder: ScreenRecorder?, hud: RecordingHUD) {
            self.request = request
            self.recorder = recorder
            self.hud = hud
        }
    }

    @ObservationIgnored weak var model: AppModel?

    private(set) var state: RecordingState = .idle
    /// Recorded time, excluding pauses.
    private(set) var elapsed: TimeInterval = 0

    @ObservationIgnored private var selection: RecordSelectionController?
    @ObservationIgnored private var active: ActiveRecording?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var screenObserver: (any NSObjectProtocol)?
    /// The stop or discard still finalizing after its HUD closed (awaited when quitting).
    @ObservationIgnored private var ending: Task<Void, Never>?
    /// Quitting: a recording that finishes now is saved to the export folder, because the
    /// quit would close its thumbnail and delete it right away.
    @ObservationIgnored private var isTerminating = false
    /// Debug `record-panel`: fake background, no capture.
    @ObservationIgnored private var isDemo = false

    // MARK: - Entry points

    /// Starts the record flow, or stops the recording when one is running.
    func recordScreen() {
        switch state {
        case .recording, .paused:
            stop()
        case .selecting:
            if active != nil {
                // The HUD is up but the recorder is still starting: nothing worth keeping yet.
                discard()
            } else {
                Log.recording.debug("recordScreen ignored: already selecting")
            }
        case .idle:
            beginSelection(demo: false)
        }
    }

    /// Stops and keeps the recording (it goes through the after-capture pipeline). While the
    /// recorder is still starting there is nothing to keep: the start is cancelled instead.
    func stop() {
        guard let active, !active.isEnding else { return }
        guard state == .recording || state == .paused else {
            Log.recording.info("stop while starting: cancelling")
            discard()
            return
        }
        active.isEnding = true
        endUI(for: active)
        guard let recorder = active.recorder else {
            Log.recording.info("demo recording stopped")
            debugRecordingEnded(item: nil)
            return
        }
        ending = Task {
            do {
                // Also returns the result when the stream had already stopped by itself.
                let result = try await recorder.stop()
                if let reason = result.interruption {
                    Log.recording.notice("recording ended by itself: \(reason, privacy: .public)")
                }
                deliver(result)
            } catch {
                Log.recording.error("stopping the recording failed: \(error.localizedDescription, privacy: .public)")
                debugRecordingEnded(item: nil)
            }
            ending = nil
        }
    }

    /// Whether quitting has to wait for a recording (running, starting or finalizing).
    var isBusyForTermination: Bool {
        active != nil || ending != nil
    }

    /// Quitting: stops a running recording, waits until the file is finalized and saves it
    /// to the export folder (a starting recording is cancelled).
    func finishForTermination() async {
        isTerminating = true
        if let active, !active.isEnding { stop() }
        await ending?.value
    }

    func togglePause() {
        guard let active, !active.isEnding else { return }
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        switch state {
        case .recording:
            active.recorder?.pause()
            active.demoClock.pause(at: now)
            state = .paused
            Log.recording.info("paused")
        case .paused:
            active.recorder?.resume()
            active.demoClock.resume(at: now)
            state = .recording
            Log.recording.info("resumed")
        default:
            return
        }
        tick()
    }

    /// Stops and throws the recording away (HUD Discard).
    func discard() {
        guard let active, !active.isEnding else { return }
        active.isEnding = true
        endUI(for: active)
        ending = Task {
            await active.recorder?.cancel()
            Log.recording.info("recording discarded")
            debugRecordingEnded(item: nil)
            ending = nil
        }
    }

    #if DEBUG
    /// Debug automation (`ULTRASHOT_DEBUG_AUTOINTERRUPT`): the stream "stops by itself".
    func debugSimulateInterruption() {
        active?.recorder?.debugSimulateUnexpectedStop(reason: "debug interruption")
    }
    #endif

    // MARK: - Selection

    /// Shows the pre-record overlay. `demo` (Debug only) uses the fake snapshot background and
    /// shows the HUD without capturing.
    func beginSelection(demo: Bool) {
        guard state == .idle, let model, model.canBeginModalFlow("record screen") else { return }
        if !demo, !ScreenCapturePermission.isGranted {
            Log.recording.notice("record screen: screen recording permission missing, showing onboarding")
            model.showOnboarding()
            return
        }
        isDemo = demo
        var background: OverlaySession.BackgroundProvider?
        if demo {
            background = { screen in DebugLaunchHooks.fakeSnapshotImage(size: screen.frame.size, scale: screen.backingScaleFactor) }
        }
        let controller = RecordSelectionController(model: model, background: background)
        controller.onRecord = { [weak self] request in
            guard let self else { return }
            selection = nil
            Task { await self.start(request) }
        }
        controller.onCancel = { [weak self] in
            guard let self else { return }
            selection = nil
            state = .idle
            Log.recording.info("record screen cancelled")
            debugRecordingEnded(item: nil)
        }
        selection = controller
        state = .selecting
        let remember = model.settings.recording.rememberLastArea
        controller.show(
            initialArea: remember ? model.appState.lastRecordingArea : nil,
            displayID: remember ? model.appState.lastRecordingDisplayID : nil
        )
        Log.recording.info("record screen: selecting (demo \(demo))")
        debugSelectionShown(controller)
    }

    // MARK: - Recording

    private func start(_ request: RecordingRequest) async {
        guard let model, let screen = Self.screen(for: request.displayID) else {
            Log.recording.error("record screen: the selected display is gone")
            state = .idle
            return
        }
        if !isDemo {
            var appState = model.appState
            appState.lastRecordingArea = screen.globalTopLeftRect(fromLocal: request.localArea)
            appState.lastRecordingDisplayID = request.displayID
            model.appState = appState
        }

        let hud = RecordingHUD(area: Self.globalArea(request, on: screen), screenFrame: screen.frame, showsBorder: !request.isFullscreen)
        hud.onTogglePause = { [weak self] in self?.togglePause() }
        hud.onStop = { [weak self] in self?.stop() }
        hud.onDiscard = { [weak self] in self?.discard() }
        hud.show()

        guard !isDemo else {
            active = ActiveRecording(request: request, recorder: nil, hud: hud)
            active?.demoClock.start(at: CMClockGetTime(CMClockGetHostTimeClock()))
            didStart(request)
            return
        }

        // Active from here on, so the HUD's Stop/Discard and the shortcut work while the
        // microphone prompt or the recorder start is pending.
        let recorder = ScreenRecorder()
        let recording = ActiveRecording(request: request, recorder: recorder, hud: hud)
        active = recording
        recorder.onStateChange = { [weak self, weak recording] recorderState in
            guard let self, let recording else { return }
            recorderStateChanged(recorderState, for: recording)
        }

        let settings = model.settings.recording
        let microphone = settings.microphone ? await Self.microphoneAllowed() : false
        guard active === recording, !recording.isEnding else { return } // cancelled during the prompt
        let configuration: RecordingConfiguration
        do {
            configuration = RecordingConfiguration(
                target: request.target,
                frameRate: settings.frameRate,
                showsCursor: settings.showCursor,
                capturesSystemAudio: settings.systemAudio,
                capturesMicrophone: microphone,
                microphoneDeviceID: settings.microphoneDeviceID,
                scale: request.scale,
                excludedWindowIDs: hud.windowIDs,
                outputURL: try model.captureStore.makeTemporaryURL(kind: .recording, ext: "mp4")
            )
        } catch {
            Log.recording.error("record screen: no output file: \(error.localizedDescription, privacy: .public)")
            endUI(for: recording)
            return
        }

        do {
            try await recorder.start(configuration)
        } catch is CancellationError {
            Log.recording.info("record screen: start cancelled") // Stop/Discard while starting
            return
        } catch {
            Log.recording.error("record screen: could not start: \(error.localizedDescription, privacy: .public)")
            if active === recording { endUI(for: recording) }
            if !ScreenCapturePermission.isGranted { model.showOnboarding() }
            debugRecordingEnded(item: nil)
            return
        }
        guard active === recording, !recording.isEnding else { return } // discarded while starting
        didStart(request)
    }

    private func didStart(_ request: RecordingRequest) {
        state = .recording
        elapsed = 0
        tick()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
        if model?.settings.general.playSounds == true, !DebugAutoRecord.isActive {
            NSSound(named: "Tink")?.play()
        }
        Log.recording.info("recording started: \(String(describing: request.target), privacy: .public) scale \(request.scale)")
        debugRecordingStarted()
    }

    /// The recorder ended on its own (display gone, permission revoked, stopped from the
    /// system's screen-sharing indicator, writer failure). Keep what was recorded.
    private func recorderStateChanged(_ recorderState: RecorderState, for recording: ActiveRecording) {
        guard active === recording, !recording.isEnding else { return }
        switch recorderState {
        case .finishing:
            // The recorder finalizes on its own (the stream stopped): end through `stop()`,
            // whose `recorder.stop()` returns this finalize's result and delivers it once.
            Log.recording.notice("recorder is finishing by itself: stopping")
            stop()
        case .finished:
            recording.isEnding = true
            endUI(for: recording)
            if let result = recording.recorder?.lastResult {
                Log.recording.notice("recording ended by itself: \(result.interruption ?? "unknown reason", privacy: .public)")
                deliver(result)
            }
        case .failed(let message):
            recording.isEnding = true
            endUI(for: recording)
            Log.recording.error("recording failed: \(message, privacy: .public)")
            debugRecordingEnded(item: nil)
        default:
            break
        }
    }

    private func screensChanged() {
        guard let active, !active.isEnding else { return }
        guard let screen = Self.screen(for: active.request.displayID) else {
            Log.recording.notice("recorded display disconnected: stopping")
            stop()
            return
        }
        active.hud.layout(area: Self.globalArea(active.request, on: screen), screenFrame: screen.frame)
    }

    private func tick() {
        guard let active else { return }
        elapsed = active.recorder?.elapsed
            ?? active.demoClock.recordedDuration(now: CMClockGetTime(CMClockGetHostTimeClock())).seconds
        active.hud.update(elapsed: elapsed, paused: state == .paused)
    }

    /// Removes the HUD and timers and returns to idle; the recorder may still be finalizing.
    private func endUI(for recording: ActiveRecording) {
        recording.hud.close()
        ticker?.invalidate()
        ticker = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        if active === recording { active = nil }
        state = .idle
        elapsed = 0
    }

    private func deliver(_ result: RecordingResult) {
        let item = CapturedItem(
            kind: .recording,
            fileURL: result.url,
            pixelWidth: Int(result.pixelSize.width),
            pixelHeight: Int(result.pixelSize.height),
            duration: result.duration
        )
        Log.recording.info("recording finished: \(item.pixelWidth)x\(item.pixelHeight), \(result.duration, format: .fixed(precision: 2)) s")
        if isTerminating, let model {
            do {
                let saved = try model.saveToExportFolder(item)
                Log.recording.notice("quitting: saved the recording as \(saved.fileURL.lastPathComponent, privacy: .private)")
            } catch {
                Log.recording.error("quitting: saving the recording failed: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            model?.deliver(item)
        }
        debugRecordingEnded(item: item)
    }

    // MARK: - Helpers

    /// Microphone permission on first use. Without it the recording goes on without the mic.
    private static func microphoneAllowed() async -> Bool {
        switch MicrophonePermission.status {
        case .authorized:
            return true
        case .notDetermined:
            let granted = await MicrophonePermission.request()
            if !granted { Log.recording.notice("microphone permission declined: recording without the microphone") }
            return granted
        case .denied, .restricted:
            Log.recording.notice("microphone permission denied: recording without the microphone")
            return false
        }
    }

    static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { $0.displayID == displayID }
    }

    /// The recorded area in AppKit global points.
    private static func globalArea(_ request: RecordingRequest, on screen: NSScreen) -> CGRect {
        request.localArea.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
    }
}
