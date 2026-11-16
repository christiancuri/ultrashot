import AppKit
import SwiftUI

/// The permission onboarding window, shown at launch while Screen Recording is not granted.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let windowIdentifier = "ultrashot.onboarding"

    private let permission = ScreenCapturePermission()
    private var window: NSWindow?

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        permission.startPolling()
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow {
        let view = OnboardingView(permission: permission) { [weak self] in
            self?.window?.close()
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.identifier = NSUserInterfaceItemIdentifier(Self.windowIdentifier)
        window.title = "Welcome to UltraShot"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    func windowWillClose(_ notification: Notification) {
        permission.stopPolling()
    }
}

/// Explains why Screen Recording is needed, requests it, and offers the relaunch once granted.
struct OnboardingView: View {
    let permission: ScreenCapturePermission
    let close: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text("Allow Screen Recording")
                    .font(.title2.bold())
                Text("UltraShot needs Screen Recording access to take screenshots and record your screen. Captures stay on your Mac.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            statusRow
            actions
        }
        .padding(.horizontal, 36)
        .padding(.top, 36)
        .padding(.bottom, 28)
        .frame(width: 440)
    }

    @ViewBuilder private var statusRow: some View {
        if permission.isGranted {
            Label("Access granted. Relaunch UltraShot to start capturing.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Label {
                Text("In System Settings, turn on UltraShot under Screen & System Audio Recording. This window updates on its own.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                ProgressView().controlSize(.small)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 10) {
            Button("Later", action: close)
                .keyboardShortcut(.cancelAction)
            if permission.isGranted {
                Button("Relaunch UltraShot") { ScreenCapturePermission.relaunch() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
            } else {
                Button("Grant Access…") { permission.requestAccess() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
            }
        }
        .padding(.top, 4)
    }
}
