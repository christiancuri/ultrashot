import AppKit
import SwiftUI

struct AboutSettingsView: View {
    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 88, height: 88)
                        .accessibilityHidden(true)
                    VStack(spacing: 3) {
                        Text("UltraShot")
                            .font(.system(size: 22, weight: .bold))
                        Text("Version \(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Text(Bundle.main.bundleIdentifier ?? "")
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }
                    Text("Screenshots and screen recordings from the menu bar.")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } footer: {
                Text(Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
        }
        .formStyle(.grouped)
        .frame(height: 320)
    }
}
