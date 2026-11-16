import SwiftUI
import UltraShotCore

struct ScreenshotsSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Picker("Format", selection: $model.settings.screenshots.format) {
                    ForEach(ImageFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                if model.settings.screenshots.format == .jpeg {
                    LabeledContent("JPEG quality") {
                        HStack {
                            Slider(value: $model.settings.screenshots.jpegQuality, in: ScreenshotSettings.jpegQualityRange, step: 0.05)
                                .frame(maxWidth: 200)
                            Text(model.settings.screenshots.jpegQuality, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
                TextField("File name", text: $model.settings.advanced.fileNameTemplate, prompt: Text(FileNaming.defaultTemplate))
            } header: {
                Text("File")
            } footer: {
                Text("File name tokens: {date} (2026-01-31), {time} (14.05.09), {kind} (Screenshot or Recording).")
                    .foregroundStyle(.secondary)
            }

            Section("Image") {
                Toggle("Convert to sRGB", isOn: $model.settings.screenshots.convertToSRGB)
                Toggle("Downscale Retina screenshots to 1x", isOn: $model.settings.screenshots.downscaleRetina)
                Toggle("Capture window shadow", isOn: $model.settings.screenshots.windowShadow)
                Toggle("Show cursor", isOn: $model.settings.screenshots.showCursor)
            }
        }
        .formStyle(.grouped)
        .frame(height: 400)
    }
}
