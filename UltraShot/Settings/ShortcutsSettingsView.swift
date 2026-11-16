import AppKit
import KeyboardShortcuts
import SwiftUI

struct ShortcutsSettingsView: View {
    @State private var systemConflicts: [SystemScreenshotShortcuts.Shortcut] = []

    var body: some View {
        Form {
            if !systemConflicts.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("macOS screenshot shortcuts are still on", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundStyle(.orange)
                        Text("They take precedence over UltraShot. Turn them off in System Settings › Keyboard › Keyboard Shortcuts › Screenshots:")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(systemConflicts, id: \.self) { shortcut in
                            Text("• \(shortcut.title)")
                                .font(.callout)
                        }
                        Button("Open Keyboard Shortcuts…") { SystemScreenshotShortcuts.openSystemSettings() }
                            .padding(.top, 2)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                ForEach(Shortcuts.all) { shortcut in
                    KeyboardShortcuts.Recorder(shortcut.title, name: shortcut.name)
                }
            } header: {
                Text("Global Shortcuts")
            } footer: {
                Text("Press a shortcut anywhere. Pressing Record Screen again stops a recording.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 360)
        .onAppear(perform: readConflicts)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            readConflicts()
        }
    }

    /// The user can change these in System Settings at any time: re-read on every activation.
    private func readConflicts() {
        systemConflicts = SystemScreenshotShortcuts.enabled()
    }
}
