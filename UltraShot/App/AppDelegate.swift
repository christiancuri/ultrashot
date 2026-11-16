import AppKit
import UltraShotCore

/// Owns the AppKit side: the status item, global shortcuts, the Settings window
/// coordinator and the onboarding window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    private lazy var statusItem = StatusItemManager(model: model)
    private let windows = WindowCoordinator()
    /// Held for the app's lifetime: only the instance holding it purges the capture store.
    private var captureStoreLock: InstanceLock?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("launched \(Bundle.main.shortVersion, privacy: .public) (\(Bundle.main.buildNumber, privacy: .public))")
        // Leftovers of the previous run: nothing is kept unless saved. Another running
        // instance (holding the lock) still owns its files, so leave them alone then.
        captureStoreLock = InstanceLock(url: model.captureStore.instanceLockURL)
        if captureStoreLock != nil {
            model.captureStore.purgeAll()
        } else {
            Log.app.notice("another UltraShot instance owns the capture store: skipping the purge")
        }
        model.actions = AppModel.Actions(
            showSettings: { [weak self] in self?.windows.showSettings() },
            showOnboarding: { [weak self] in self?.windows.showOnboarding() }
        )
        windows.start()
        statusItem.start()
        Shortcuts.register(model: model)

        if ScreenCapturePermission.isGranted {
            Log.app.info("screen recording permission granted")
        } else {
            Log.app.notice("screen recording permission missing: showing onboarding")
            windows.showOnboarding()
        }

        DebugLaunchHooks.run(model: model)
    }

    /// Quitting (or logging out) during a recording waits until the file is finalized and
    /// saved, for at most ``terminationTimeout``.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.recording.isBusyForTermination else { return .terminateNow }
        Log.app.notice("quitting during a recording: finishing it first")
        let recording = model.recording
        Task { @MainActor in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await recording.finishForTermination() }
                group.addTask { try? await Task.sleep(for: Self.terminationTimeout) }
                await group.next()
                group.cancelAll()
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private static let terminationTimeout: Duration = .seconds(8)

    /// Closes open thumbnails, deleting their unsaved captures (or saving them first when the
    /// auto-close action is Save and Close).
    func applicationWillTerminate(_ notification: Notification) {
        model.capture.cancelActiveSession()
        model.thumbnails.closeAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Reopening the app from Finder/Spotlight while it runs opens Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windows.showSettings()
        return false
    }
}

extension Bundle {
    /// `CFBundleShortVersionString`, e.g. `0.1.0`.
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// `CFBundleVersion`.
    var buildNumber: String {
        object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
}
