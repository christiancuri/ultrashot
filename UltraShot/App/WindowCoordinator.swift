import AppKit
import SwiftUI

/// Opens the SwiftUI Settings window and the onboarding window from AppKit, and keeps the
/// activation policy in sync: `.regular` (Dock icon, app menu, proper window ordering) while
/// one of them (or a Sparkle update window) is open, `.accessory` (menu bar only) once they close.
///
/// Overlays, thumbnails and HUDs are borderless windows or panels and never count.
@MainActor
final class WindowCoordinator {
    /// SwiftUI's `openSettings`, captured from a hosted view (see ``SettingsActionBridge``).
    var openSettingsAction: OpenSettingsAction?

    private var observers: [any NSObjectProtocol] = []
    /// Keeps the bridge's hosting window alive.
    private var bridgeWindow: NSWindow?
    private var onboarding: OnboardingWindowController?

    func start() {
        installSettingsBridge()
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.willCloseNotification,
            NSWindow.didMiniaturizeNotification,
        ]
        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // Deferred: during `willClose` the closing window is still visible.
                Task { @MainActor in self?.windowsChanged() }
            }
        }
    }

    /// The Settings window, once SwiftUI has created it.
    var settingsWindow: NSWindow? {
        NSApp.windows.first { Self.isAppWindow($0) && !Self.isOwnWindow($0) && !Self.isSparkleWindow($0) }
    }

    func showSettings() {
        if let window = settingsWindow, window.isVisible || window.isMiniaturized {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
            bringToFront(window)
            return
        }
        guard let openSettingsAction else {
            Log.app.error("openSettings is not available yet")
            return
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        openSettingsAction()
        // SwiftUI creates the window on the next run loop turn.
        Task { @MainActor in
            for _ in 0..<20 {
                if let window = self.settingsWindow, window.isVisible {
                    self.bringToFront(window)
                    return
                }
                try? await Task.sleep(for: .milliseconds(25))
            }
            // No window after 500 ms: don't leave a Dock icon without a window behind.
            Log.app.error("Settings window did not appear")
            self.windowsChanged()
        }
    }

    func showOnboarding() {
        let controller = onboarding ?? OnboardingWindowController()
        onboarding = controller
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        controller.show()
    }

    /// `NSApp.activate()` is only a request: `orderFrontRegardless()` guarantees the
    /// window does not open behind the frontmost app.
    private func bringToFront(_ window: NSWindow) {
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    /// Titled app windows (Settings, onboarding). Panels, status items and the bridge are excluded.
    private static func isAppWindow(_ window: NSWindow) -> Bool {
        window.styleMask.contains(.titled) && !(window is NSPanel) && window.className != "NSStatusBarWindow"
            && window.identifier?.rawValue != SettingsActionBridge.windowIdentifier
    }

    /// Windows UltraShot creates itself (identifier prefixed `ultrashot.`), i.e. not Settings.
    private static func isOwnWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue.hasPrefix("ultrashot.") == true
    }

    /// Sparkle's update windows (their controllers come from Sparkle.framework). They count as
    /// app windows for the activation policy, but they are not Settings.
    private static func isSparkleWindow(_ window: NSWindow) -> Bool {
        guard let controller = window.windowController else { return false }
        return Bundle(for: type(of: controller)).bundleIdentifier == "org.sparkle-project.Sparkle"
    }

    private func windowsChanged() {
        let hasWindows = NSApp.windows.contains { Self.isAppWindow($0) && $0.isVisible && !$0.isMiniaturized }
        let policy: NSApplication.ActivationPolicy = hasWindows ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        Log.app.debug("activation policy \(hasWindows ? "regular" : "accessory", privacy: .public)")
    }

    // MARK: - openSettings bridge

    /// SwiftUI only hands out `openSettings` to views inside its scene graph. A hosted,
    /// invisible 1×1 window captures it at launch.
    private func installSettingsBridge() {
        let host = NSHostingView(rootView: SettingsActionBridge { [weak self] action in
            self?.openSettingsAction = action
        })
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 1, height: 1), styleMask: .borderless, backing: .buffered, defer: false)
        window.identifier = NSUserInterfaceItemIdentifier(SettingsActionBridge.windowIdentifier)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.isExcludedFromWindowsMenu = true
        window.collectionBehavior = [.transient, .ignoresCycle, .canJoinAllSpaces]
        window.contentView = host
        window.orderFrontRegardless()
        bridgeWindow = window
    }
}

/// Captures `openSettings` once it is in a window.
struct SettingsActionBridge: View {
    static let windowIdentifier = "settings-bridge"

    @Environment(\.openSettings) private var openSettings
    let onReady: (OpenSettingsAction) -> Void

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onAppear { onReady(openSettings) }
    }
}
