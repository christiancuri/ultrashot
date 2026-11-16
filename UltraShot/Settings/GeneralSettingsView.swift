import AppKit
import ServiceManagement
import SwiftUI
import UltraShotCore

struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model

    @State private var launchAtLogin = false
    @State private var loginRequiresApproval = false
    @State private var loginError: String?

    var body: some View {
        @Bindable var model = model
        @Bindable var updater = model.updater
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                if loginRequiresApproval {
                    LabeledContent {
                        Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                    } label: {
                        Label("Waiting for your approval in System Settings.", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                    }
                }
                if let loginError {
                    Label(loginError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }

            Section("Capture") {
                Toggle("Play sounds", isOn: $model.settings.general.playSounds)
                Toggle("Hide desktop icons while capturing", isOn: $model.settings.general.hideDesktopIcons)
                LabeledContent("Export location") {
                    HStack(spacing: 8) {
                        Text(model.settings.general.exportFolderPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Choose…", action: chooseExportFolder)
                    }
                }
            }

            Section {
                AfterCaptureGrid(settings: $model.settings.general.afterCapture)
            } header: {
                Text("After Capture")
            } footer: {
                Text("Files that are not saved are deleted when their thumbnail closes.")
                    .foregroundStyle(.secondary)
            }

            if model.updater.isAvailable {
                Section("Updates") {
                    Toggle("Check for updates automatically", isOn: $updater.automaticallyChecksForUpdates)
                    LabeledContent("Version \(Bundle.main.shortVersion)") {
                        Button("Check Now") { model.checkForUpdates() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 600)
        .onAppear(perform: readLoginItemStatus)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            readLoginItemStatus()
        }
    }

    private func chooseExportFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose where saved screenshots and recordings go."
        panel.directoryURL = model.settings.general.exportFolderURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard !model.captureStore.isUnsafeExportFolder(url) else {
            // Saved files there would count as temporary captures and be deleted.
            NSSound.beep()
            Log.app.error("export folder rejected: inside the temporary captures folder")
            return
        }
        model.settings.general.exportFolderURL = url
    }

    /// The user can change this in System Settings at any time: always re-read.
    private func readLoginItemStatus() {
        launchAtLogin = LoginItemManager.isEnabled
        loginRequiresApproval = LoginItemManager.requiresApproval
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItemManager.setEnabled(enabled)
            loginError = nil
        } catch {
            loginError = "Couldn't \(enabled ? "enable" : "disable") launch at login: \(error.localizedDescription)"
        }
        readLoginItemStatus()
    }
}

/// Rows: Show thumbnail / Copy to clipboard / Save. Columns: Screenshot / Recording.
private struct AfterCaptureGrid: View {
    @Binding var settings: AfterCaptureSettings

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
            GridRow {
                Text("")
                Text("Screenshot").font(.subheadline.weight(.semibold)).gridColumnAlignment(.center)
                Text("Recording").font(.subheadline.weight(.semibold)).gridColumnAlignment(.center)
            }
            row("Show thumbnail", \.showThumbnail)
            row("Copy to clipboard", \.copyToClipboard)
            row("Save to export location", \.save)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ title: String, _ keyPath: WritableKeyPath<AfterCaptureActions, Bool>) -> some View {
        GridRow {
            Text(title)
            Toggle(title, isOn: $settings.screenshot[dynamicMember: keyPath])
                .labelsHidden()
                .toggleStyle(.checkbox)
            Toggle(title, isOn: $settings.recording[dynamicMember: keyPath])
                .labelsHidden()
                .toggleStyle(.checkbox)
        }
    }
}
