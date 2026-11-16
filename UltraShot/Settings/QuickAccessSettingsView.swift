import SwiftUI
import UltraShotCore

/// The thumbnail overlay shown after each capture.
struct QuickAccessSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Overlay") {
                Picker("Position on screen", selection: $model.settings.quickAccess.position) {
                    ForEach(QuickAccessPosition.allCases) { position in
                        Text(position.displayName).tag(position)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Move to active screen", isOn: $model.settings.quickAccess.moveToActiveScreen)
                LabeledContent("Overlay size") {
                    Slider(
                        value: Binding(
                            get: { Double(model.settings.quickAccess.overlaySize) },
                            set: { model.settings.quickAccess.overlaySize = Int($0.rounded()) }
                        ),
                        in: Double(QuickAccessSettings.overlaySizeRange.lowerBound)...Double(QuickAccessSettings.overlaySizeRange.upperBound),
                        step: 1
                    ) {
                        Text("Overlay size")
                    } minimumValueLabel: {
                        Image(systemName: "rectangle.compress.vertical").accessibilityLabel("Smaller")
                    } maximumValueLabel: {
                        Image(systemName: "rectangle.expand.vertical").accessibilityLabel("Larger")
                    }
                    .labelsHidden()
                    .frame(maxWidth: 240)
                }
            }

            Section {
                Toggle("Close automatically", isOn: $model.settings.quickAccess.autoClose)
                Picker("Action", selection: $model.settings.quickAccess.autoCloseAction) {
                    ForEach(AutoCloseAction.allCases) { action in
                        Text(action.displayName).tag(action)
                    }
                }
                .disabled(!model.settings.quickAccess.autoClose)
                Picker("Close after", selection: $model.settings.quickAccess.autoCloseInterval) {
                    ForEach(QuickAccessSettings.autoCloseIntervals, id: \.self) { seconds in
                        Text(QuickAccessSettings.intervalLabel(seconds)).tag(seconds)
                    }
                }
                .disabled(!model.settings.quickAccess.autoClose)
            } header: {
                Text("Auto-Close")
            } footer: {
                Text("The timer pauses while the pointer is over a thumbnail. Closing deletes the file unless it was saved.")
                    .foregroundStyle(.secondary)
            }

            Section("Drag and Drop") {
                Toggle("Close after dragging", isOn: $model.settings.quickAccess.closeAfterDragging)
            }
        }
        .formStyle(.grouped)
        .frame(height: 470)
    }
}
