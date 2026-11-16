import SwiftUI

/// Settings window (⌘,): toolbar tabs, each a grouped form bound to `model.settings`
/// (every change is saved right away).
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.settingsTab) {
            Tab("General", systemImage: "gearshape", value: SettingsTab.general) {
                GeneralSettingsView()
            }
            Tab("Shortcuts", systemImage: "command", value: SettingsTab.shortcuts) {
                ShortcutsSettingsView()
            }
            Tab("Quick Access", systemImage: "rectangle.on.rectangle", value: SettingsTab.quickAccess) {
                QuickAccessSettingsView()
            }
            Tab("Screenshots", systemImage: "camera", value: SettingsTab.screenshots) {
                ScreenshotsSettingsView()
            }
            Tab("Recording", systemImage: "record.circle", value: SettingsTab.recording) {
                RecordingSettingsView()
            }
            Tab("About", systemImage: "info.circle", value: SettingsTab.about) {
                AboutSettingsView()
            }
        }
        .frame(width: 560)
    }
}
