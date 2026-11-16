import SwiftUI
import UltraShotCore

struct RecordingSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Video") {
                Picker("Frame rate", selection: $model.settings.recording.frameRate) {
                    ForEach(RecordingSettings.frameRates, id: \.self) { rate in
                        Text("\(rate) fps").tag(rate)
                    }
                }
                Toggle("Show cursor", isOn: $model.settings.recording.showCursor)
                Toggle("Downscale Retina recordings to 1x", isOn: $model.settings.recording.downscaleRetina)
                Toggle("Remember last recording area", isOn: $model.settings.recording.rememberLastArea)
            }

            Section {
                Toggle("Record system audio", isOn: $model.settings.recording.systemAudio)
                Toggle("Record microphone", isOn: $model.settings.recording.microphone)
            } header: {
                Text("Audio")
            } footer: {
                Text("Both can also be toggled in the panel before each recording. macOS asks for microphone access the first time.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 400)
    }
}
