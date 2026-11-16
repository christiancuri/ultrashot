import AVFoundation
import Observation
import RecordingKit
import UltraShotCore

/// The audio input devices currently connected, kept fresh on hot-plug, for the microphone
/// pickers in Settings › Recording and the record panel.
///
/// Listing devices needs no microphone permission and never prompts.
@MainActor
@Observable
final class MicrophoneCatalog {
    static let shared = MicrophoneCatalog()

    private(set) var devices: [MicrophoneDevice] = []
    /// The system default input. AVFoundation posts no notification when it changes, so it is
    /// re-read on hot-plug and whenever a picker is shown (``refresh()``).
    private(set) var defaultDevice: MicrophoneDevice?

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private init() {
        refresh()
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.devicesChanged() }
            })
        }
        let permission = String(describing: MicrophonePermission.status)
        Log.recording.info("microphone: authorization \(permission, privacy: .public), \(self.devices.count) input devices")
    }

    func refresh() {
        let devices = ScreenRecorder.availableMicrophones()
        let defaultDevice = ScreenRecorder.defaultMicrophone()
        if devices != self.devices { self.devices = devices }
        if defaultDevice != self.defaultDevice { self.defaultDevice = defaultDevice }
    }

    /// Picker entries for `settings` (System Default, devices, and the saved one if unplugged).
    func options(for settings: RecordingSettings) -> [MicrophoneSelection.Option] {
        MicrophoneSelection.options(
            savedID: settings.microphoneDeviceID,
            savedName: settings.microphoneDeviceName,
            available: devices,
            defaultDevice: defaultDevice
        )
    }

    /// Saves `deviceID` (`nil` = System Default) with its name, so an unplugged device keeps
    /// its label in the pickers.
    func select(_ deviceID: String?, in settings: inout RecordingSettings) {
        settings.microphoneDeviceName = MicrophoneSelection.name(
            for: deviceID,
            available: devices,
            previousName: deviceID == settings.microphoneDeviceID ? settings.microphoneDeviceName : nil
        )
        settings.microphoneDeviceID = deviceID
    }

    private func devicesChanged() {
        refresh()
        Log.recording.info("audio input devices changed: \(self.devices.count) connected")
    }
}

extension RecordingSettings {
    /// These settings with the DEBUG microphone overrides applied (unchanged in Release). The
    /// overrides are never saved:
    /// - `ULTRASHOT_DEBUG_MIC=on|off` turns the microphone on or off.
    /// - `ULTRASHOT_DEBUG_MIC_DEVICE=<uniqueID>|default|non-default|missing` selects a device:
    ///   `non-default` is the first connected input that isn't the system default, `missing` a
    ///   device that is not connected (named "Debug Microphone").
    @MainActor
    var withDebugMicrophoneOverrides: RecordingSettings {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        var settings = self
        switch environment["ULTRASHOT_DEBUG_MIC"] {
        case "on": settings.microphone = true
        case "off": settings.microphone = false
        default: break
        }
        guard let device = environment["ULTRASHOT_DEBUG_MIC_DEVICE"], !device.isEmpty else { return settings }
        let catalog = MicrophoneCatalog.shared
        switch device {
        case "default":
            settings.microphoneDeviceID = nil
        case "non-default":
            settings.microphoneDeviceID = catalog.devices.first { $0.id != catalog.defaultDevice?.id }?.id
        case "missing":
            settings.microphoneDeviceID = "dev.christiancuri.ultrashot.debug-missing-microphone"
        default:
            settings.microphoneDeviceID = device
        }
        settings.microphoneDeviceName = device == "missing" ? "Debug Microphone"
            : MicrophoneSelection.name(for: settings.microphoneDeviceID, available: catalog.devices, previousName: nil)
        return settings
        #else
        return self
        #endif
    }
}
