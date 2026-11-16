import AppKit
import CoreGraphics
import Observation

/// Screen Recording permission (TCC). The grant is tied to the code signature, and macOS
/// only applies it to a process started after the grant, hence the relaunch step.
@MainActor
@Observable
final class ScreenCapturePermission {
    /// System Settings › Privacy & Security › Screen & System Audio Recording.
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")

    /// Whether this process may capture the screen.
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    private(set) var isGranted = ScreenCapturePermission.isGranted
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    /// Re-checks the permission every second until it is granted or ``stopPolling()`` is called.
    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                isGranted = Self.isGranted
                if isGranted { break }
                try? await Task.sleep(for: .seconds(1))
            }
            self?.pollTask = nil
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Adds UltraShot to the Screen Recording list (the system prompt appears the first
    /// time) and opens the matching System Settings pane.
    func requestAccess() {
        Log.app.info("requesting screen recording access")
        _ = CGRequestScreenCaptureAccess()
        if let url = Self.settingsURL {
            NSWorkspace.shared.open(url)
        }
        startPolling()
    }

    /// Starts a new instance shortly after this one quits, then quits.
    static func relaunch() {
        let bundlePath = Bundle.main.bundlePath
        Log.app.info("relaunching")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // The path is passed as $0, never interpolated into the script.
        process.arguments = ["-c", "sleep 1; /usr/bin/open -n \"$0\"", bundlePath]
        do {
            try process.run()
        } catch {
            Log.app.error("relaunch failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        NSApp.terminate(nil)
    }
}
