import SwiftUI

/// Menu bar app: AppKit status item and overlays (see ``AppDelegate``) plus a SwiftUI
/// Settings scene. `LSUIElement` keeps it out of the Dock until Settings opens.
@main
struct UltraShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // `SwiftUI.` because UltraShotCore also has a `Settings` type.
        SwiftUI.Settings {
            SettingsView()
                .environment(appDelegate.model)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About UltraShot") { appDelegate.model.openSettings(.about) }
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { appDelegate.model.checkForUpdates() }
                    .disabled(!appDelegate.model.updater.isAvailable)
            }
        }
    }
}
