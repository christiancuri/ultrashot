import Foundation

/// Resolves the saved microphone choice against the devices that are connected right now.
///
/// The saved choice is never changed here: a device that is unplugged stays selected and is
/// used again once it comes back, while recordings fall back to the system default meanwhile.
public enum MicrophoneSelection {
    /// The microphone a recording should use.
    public struct Resolution: Sendable, Equatable {
        /// `RecordingConfiguration.microphoneDeviceID`: the saved device when connected,
        /// otherwise `nil` (the system default input).
        public let effectiveDeviceID: String?
        /// A device is saved but not connected, so the system default is used instead.
        public let isSavedDeviceMissing: Bool
    }

    /// One entry of a microphone picker.
    public struct Option: Sendable, Equatable, Hashable, Identifiable {
        public enum Kind: Sendable, Equatable, Hashable {
            /// Follow the system default input. Its `deviceID` is `nil`.
            case systemDefault
            /// A connected device.
            case device
            /// The saved device, currently not connected. Shown so the choice stays visible.
            case disconnected
        }

        /// The value to save as the selection (`nil` for the system default).
        public let deviceID: String?
        public let title: String
        public let kind: Kind

        public var id: String { deviceID.map { "device:\($0)" } ?? "default" }
        public var isAvailable: Bool { kind != .disconnected }
    }

    public static func resolve(savedID: String?, available: [MicrophoneDevice]) -> Resolution {
        guard let savedID else { return Resolution(effectiveDeviceID: nil, isSavedDeviceMissing: false) }
        guard available.contains(where: { $0.id == savedID }) else {
            return Resolution(effectiveDeviceID: nil, isSavedDeviceMissing: true)
        }
        return Resolution(effectiveDeviceID: savedID, isSavedDeviceMissing: false)
    }

    /// Picker entries: System Default (named after `defaultDevice` when known), every
    /// connected device in the given order, and, when the saved device is missing, a
    /// disconnected entry titled with `savedName` (or "Unavailable Device").
    public static func options(
        savedID: String?,
        savedName: String?,
        available: [MicrophoneDevice],
        defaultDevice: MicrophoneDevice?
    ) -> [Option] {
        let defaultTitle = defaultDevice.map { "System Default (\($0.name))" } ?? "System Default"
        var options = [Option(deviceID: nil, title: defaultTitle, kind: .systemDefault)]
        var seen = Set<String>()
        for device in available where seen.insert(device.id).inserted {
            options.append(Option(deviceID: device.id, title: device.name, kind: .device))
        }
        if let savedID, !seen.contains(savedID) {
            let name = savedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let title = name.isEmpty ? "Unavailable Device" : "\(name) (disconnected)"
            options.append(Option(deviceID: savedID, title: title, kind: .disconnected))
        }
        return options
    }

    /// The name to save next to `deviceID` when the user picks it: the device's current name,
    /// or `previousName` when the id is not connected (re-picking a disconnected entry).
    public static func name(for deviceID: String?, available: [MicrophoneDevice], previousName: String?) -> String? {
        guard let deviceID else { return nil }
        return available.first { $0.id == deviceID }?.name ?? previousName
    }
}
