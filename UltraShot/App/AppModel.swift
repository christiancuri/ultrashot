import AppKit
import Observation
import UltraShotCore

/// Settings window tabs (deep-linkable, e.g. `-debug-open settings:shortcuts`).
enum SettingsTab: String, CaseIterable, Hashable, Sendable {
    case general
    case shortcuts
    case quickAccess
    case screenshots
    case recording
    case about
}

/// App-level state shared by the menu bar, Settings and the feature coordinators.
///
/// Owns the persisted ``Settings`` (saved on every change), the small ``AppState``, the
/// ``CaptureStore`` and one coordinator per feature. Coordinators reach back through their
/// `weak var model`, which is set right after they are created.
@MainActor
@Observable
final class AppModel {
    /// Hooks into the AppKit layer, installed once at launch by ``AppDelegate``.
    struct Actions {
        var showSettings: @MainActor () -> Void = {}
        var showOnboarding: @MainActor () -> Void = {}
    }

    @ObservationIgnored let settingsStore: SettingsStore
    @ObservationIgnored let captureStore: CaptureStore

    /// User settings; every change is written to `settings.json`.
    var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            persist(settings)
        }
    }

    /// Non-settings state (e.g. the last recording area); written to `state.json`.
    var appState: AppState {
        didSet {
            guard appState != oldValue else { return }
            do {
                try settingsStore.save(appState)
            } catch {
                Log.app.error("saving state failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Selected Settings tab; set before opening Settings to deep-link.
    var settingsTab: SettingsTab = .general

    let capture: CaptureCoordinator
    let thumbnails: ThumbnailCoordinator
    let recording: RecordingCoordinator
    let annotation: AnnotationCoordinator

    @ObservationIgnored var actions = Actions()

    init(settingsStore: SettingsStore = .standard(), captureStore: CaptureStore = .standard()) {
        self.settingsStore = settingsStore
        self.captureStore = captureStore
        settings = settingsStore.loadSettings()
        appState = settingsStore.loadState()
        capture = CaptureCoordinator()
        thumbnails = ThumbnailCoordinator()
        recording = RecordingCoordinator()
        annotation = AnnotationCoordinator()
        capture.model = self
        thumbnails.model = self
        recording.model = self
        annotation.model = self
    }

    // MARK: - Actions

    func openSettings(_ tab: SettingsTab? = nil) {
        if let tab { settingsTab = tab }
        actions.showSettings()
    }

    func showOnboarding() {
        actions.showOnboarding()
    }

    func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Modal flows

    /// A full-screen flow is up: a capture overlay (or its snapshots being taken), the record
    /// selection or a recording that is still starting, or an annotation session.
    var isModalFlowActive: Bool {
        capture.isActive || recording.state == .selecting || annotation.session != nil
    }

    /// Entry-point guard for full-screen flows: they never stack (a second overlay would sit on
    /// top of the first) and never replace one in progress (an annotation would be lost).
    /// Returns `false`, with a beep, while another flow is up.
    func canBeginModalFlow(_ flow: String) -> Bool {
        guard isModalFlowActive else { return true }
        Log.app.info("\(flow, privacy: .public) ignored: another capture flow is active")
        NSSound.beep()
        return false
    }

    // MARK: - Private

    private func persist(_ settings: Settings) {
        do {
            try settingsStore.save(settings)
        } catch {
            Log.app.error("saving settings failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
