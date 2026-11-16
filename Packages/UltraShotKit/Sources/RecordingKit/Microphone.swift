import AVFoundation

/// An audio input device that can be passed as `RecordingConfiguration.microphoneDeviceID`.
public struct MicrophoneDevice: Sendable, Equatable, Hashable, Identifiable {
    /// `AVCaptureDevice.uniqueID`.
    public let id: String
    /// Localized device name.
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Microphone (TCC) authorization for the current process.
public enum MicrophonePermission {
    public enum Status: Sendable, Equatable {
        case notDetermined
        case denied
        case restricted
        case authorized
    }

    public static var status: Status {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    /// Shows the system prompt when the status is `.notDetermined`; otherwise returns the
    /// current answer without prompting.
    public static func request() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }
}

extension ScreenRecorder {
    /// Audio input devices currently connected (built-in and external).
    public nonisolated static func availableMicrophones() -> [MicrophoneDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        .devices
        .map { MicrophoneDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    /// The system default audio input (what `microphoneDeviceID == nil` records), if any.
    public nonisolated static func defaultMicrophone() -> MicrophoneDevice? {
        AVCaptureDevice.default(for: .audio).map { MicrophoneDevice(id: $0.uniqueID, name: $0.localizedName) }
    }
}
