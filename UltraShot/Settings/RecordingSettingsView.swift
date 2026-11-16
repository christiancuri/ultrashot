import RecordingKit
import SwiftUI
import UltraShotCore

struct RecordingSettingsView: View {
    @Environment(AppModel.self) private var model
    private let microphones = MicrophoneCatalog.shared

    var body: some View {
        @Bindable var model = model
        let recording = model.settings.recording.withDebugMicrophoneOverrides
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
                Toggle("Record microphone", isOn: microphoneEnabled)
                Picker("Microphone", selection: microphoneSelection) {
                    ForEach(microphones.options(for: recording)) { option in
                        Text(option.title)
                            .foregroundStyle(option.isAvailable ? .primary : .secondary)
                            .tag(option.deviceID)
                    }
                }
                .disabled(!recording.microphone)
            } header: {
                Text("Audio")
            } footer: {
                Text("""
                    System audio is captured from apps directly, whatever output device is in use. \
                    Both can also be changed in the panel before each recording. \
                    macOS asks for microphone access the first time.
                    """)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 470)
        .onAppear { microphones.refresh() }
    }

    private var microphoneEnabled: Binding<Bool> {
        Binding {
            model.settings.recording.withDebugMicrophoneOverrides.microphone
        } set: { isOn in
            model.settings.recording.microphone = isOn
        }
    }

    /// The saved device id (`nil` = System Default); picking also stores the device name.
    private var microphoneSelection: Binding<String?> {
        Binding {
            model.settings.recording.withDebugMicrophoneOverrides.microphoneDeviceID
        } set: { deviceID in
            microphones.select(deviceID, in: &model.settings.recording)
        }
    }
}
