import AppKit

/// Launch hooks that open a surface directly, for manual QA and screenshots of UltraShot's
/// own windows. Active in Debug builds only; in Release every hook is a no-op and the
/// flags read `false`.
///
///     open UltraShot.app --args -debug-open settings:shortcuts
///     ULTRASHOT_DEBUG_OPEN=overlay-sample ULTRASHOT_DEBUG_FAKE_SNAPSHOT=1 …/UltraShot
///
/// `-debug-open <name>` (or env `ULTRASHOT_DEBUG_OPEN`), one of: `settings`,
/// `settings:<tab>` (general, shortcuts, quickAccess, screenshots, recording, about),
/// `onboarding`, `capture-area`, `capture-fullscreen`, `capture-window`,
/// `capture-annotate`, `record`, `record-panel`, `thumbnail-sample`, `annotate-sample`, `overlay-sample`,
/// `check-updates` (with `ULTRASHOT_DEBUG_FEED_URL`, see ``DebugAutomation``).
///
/// Environment flags:
/// - `ULTRASHOT_DEBUG_FAKE_SNAPSHOT=1`: capture flows use ``fakeSnapshotImage(size:scale:)``
///   instead of the real screen (so nobody has to look at the real desktop).
///   `ULTRASHOT_DEBUG_FAKE_SNAPSHOT=<path>` does the same with that image file, scaled to
///   fill each screen (for README screenshots over a designed desktop).
/// - `ULTRASHOT_DEBUG_APPEARANCE=light|dark`: sets `NSApp.appearance` (Light and Dark
///   screenshots without touching the system setting).
/// - `ULTRASHOT_DEBUG_OVERLAY_SELECTION="x,y,w,h"`: the `overlay-sample` (and `record-panel`)
///   selection, in main screen points with the origin at the bottom left.
/// - `ULTRASHOT_DEBUG_BACKDROP=1`, `ULTRASHOT_DEBUG_ANNOTATE_JSON=<path>`,
///   `ULTRASHOT_DEBUG_THUMBNAIL_MENU=1`: README staging, see `DebugLaunchHooks+Staging.swift`.
/// - `ULTRASHOT_DEBUG_CAPTURABLE_OVERLAY=1`: overlay windows allow `screencapture -l`.
/// - `ULTRASHOT_DEBUG_REPEAT=<n>` (+ `ULTRASHOT_DEBUG_REPEAT_INTERVAL=<seconds>`, default 4):
///   opens the surface `n` times (memory checks over several automated captures).
/// - `ULTRASHOT_DEBUG_QUIT_AFTER=<seconds>`: quits through `NSApp.terminate` after that long.
@MainActor
enum DebugLaunchHooks {
    /// Keeps the `overlay-sample` session alive.
    private static var sampleSession: OverlaySession?

    /// Capture flows should use ``fakeSnapshotImage(size:scale:)`` instead of the screen.
    nonisolated static var useFakeSnapshot: Bool {
        isDebug && ProcessInfo.processInfo.environment["ULTRASHOT_DEBUG_FAKE_SNAPSHOT"]?.isEmpty == false
    }

    /// The image file from `ULTRASHOT_DEBUG_FAKE_SNAPSHOT=<path>`, or `nil` for `=1` (the
    /// built-in synthetic desktop).
    nonisolated static var fakeSnapshotFile: URL? {
        guard isDebug, let value = ProcessInfo.processInfo.environment["ULTRASHOT_DEBUG_FAKE_SNAPSHOT"],
              !value.isEmpty, value != "1" else { return nil }
        return URL(filePath: (value as NSString).expandingTildeInPath)
    }

    /// Overlay windows may be captured by `screencapture -l` (they are hidden otherwise).
    nonisolated static var capturableOverlays: Bool {
        isDebug && ProcessInfo.processInfo.environment["ULTRASHOT_DEBUG_CAPTURABLE_OVERLAY"] == "1"
    }

    /// The requested surface, from `-debug-open` or `ULTRASHOT_DEBUG_OPEN`.
    static var requestedSurface: String? {
        guard isDebug else { return nil }
        return UserDefaults.standard.string(forKey: "debug-open")
            ?? ProcessInfo.processInfo.environment["ULTRASHOT_DEBUG_OPEN"]
    }

    static func run(model: AppModel) {
        scheduleQuit()
        applyAppearance()
        guard let name = requestedSurface?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return }
        Log.app.info("debug-open \(name, privacy: .public)")
        #if DEBUG
        showBackdropIfRequested()
        scheduleAnnotationsFile(model: model)
        scheduleThumbnailMenu(model: model)
        scheduleRecordSelection(rect(from: ProcessInfo.processInfo.environment["ULTRASHOT_DEBUG_OVERLAY_SELECTION"]))
        #endif
        let environment = ProcessInfo.processInfo.environment
        let repeats = max(1, Int(environment["ULTRASHOT_DEBUG_REPEAT"] ?? "") ?? 1)
        let interval = Double(environment["ULTRASHOT_DEBUG_REPEAT_INTERVAL"] ?? "") ?? 4
        Task { @MainActor in
            // Let the status item and the Settings bridge settle.
            try? await Task.sleep(for: .milliseconds(800))
            for run in 1...repeats {
                if run > 1 {
                    try? await Task.sleep(for: .seconds(interval))
                    Log.app.info("debug-open \(name, privacy: .public) run \(run)/\(repeats)")
                }
                open(name, model: model)
            }
        }
    }

    private static func open(_ name: String, model: AppModel) {
        if name.hasPrefix("settings") {
            let tab = name.split(separator: ":").dropFirst().first.flatMap { SettingsTab(rawValue: String($0)) }
            model.openSettings(tab ?? .general)
            return
        }
        switch name {
        case "onboarding": model.showOnboarding()
        case "capture-area": model.capture.captureArea()
        case "capture-fullscreen": model.capture.captureFullscreen()
        case "capture-window": model.capture.captureWindow()
        case "capture-annotate": model.capture.captureAreaAndAnnotate()
        case "record": model.recording.recordScreen()
        case "record-panel": model.recording.debugShowPanel()
        case "thumbnail-sample": model.thumbnails.debugShowSample()
        case "annotate-sample": model.annotation.debugShowSample()
        case "overlay-sample": showOverlaySample()
        case "check-updates": model.checkForUpdates()
        default: Log.app.error("debug-open: unknown surface \(name, privacy: .public)")
        }
    }

    /// `ULTRASHOT_DEBUG_QUIT_AFTER=<seconds>`: quits through `NSApp.terminate` (the real quit
    /// path, unlike a signal) after that long.
    private static func scheduleQuit() {
        guard isDebug, let seconds = Double(ProcessInfo.processInfo.environment["ULTRASHOT_DEBUG_QUIT_AFTER"] ?? ""), seconds > 0 else { return }
        // A run loop timer, like a menu click: `terminate` called from a main-queue job (a
        // Task) would block the main queue while `.terminateLater` waits.
        Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
            MainActor.assumeIsolated {
                Log.app.info("debug quit")
                NSApp.terminate(nil)
            }
        }
    }

    /// `ULTRASHOT_DEBUG_APPEARANCE=light|dark`: forces the app's appearance.
    private static func applyAppearance() {
        guard isDebug else { return }
        switch ProcessInfo.processInfo.environment["ULTRASHOT_DEBUG_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }

    /// An adjust-mode overlay on every screen over a synthetic background, with a selection
    /// on the screen under the pointer. Esc closes it; ↩ logs the committed rect.
    private static func showOverlaySample() {
        let session = OverlaySession(mode: .adjust) { screen in
            fakeSnapshotImage(size: screen.frame.size, scale: screen.backingScaleFactor)
        }
        session.onCommit = { view, rect in
            Log.app.info("overlay-sample commit \(String(describing: rect), privacy: .public) scale \(view.effectiveScale)")
        }
        session.onCancel = {
            Log.app.info("overlay-sample cancelled")
            sampleSession = nil
        }
        session.show()
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.screens.first,
           let view = session.view(for: screen) {
            if let rect = rect(from: ProcessInfo.processInfo.environment["ULTRASHOT_DEBUG_OVERLAY_SELECTION"]) {
                view.selection = rect.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
                sampleSession = session
                return
            }
            let size = CGSize(width: min(640, view.bounds.width / 2), height: min(400, view.bounds.height / 2))
            view.selection = CGRect(x: view.bounds.midX - size.width / 2, y: view.bounds.midY - size.height / 2, width: size.width, height: size.height)
        }
        sampleSession = session
    }

    /// `"x,y,w,h"` → rect, `nil` when missing or malformed.
    private static func rect(from value: String?) -> CGRect? {
        guard isDebug, let value else { return nil }
        let numbers = value.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard numbers.count == 4, numbers[2] > 0, numbers[3] > 0 else { return nil }
        return CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
    }

    private nonisolated static var isDebug: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}
