import Foundation
import Testing
@testable import UltraShotCore

@Suite("Microphone settings")
struct MicrophoneSettingsTests {
    @Test func settingsWithoutTheNameDecode() throws {
        // Settings written before the name was stored.
        let settings = try decodeSettings(#"{"recording":{"microphone":true,"microphoneDeviceID":"mic-1"}}"#)
        #expect(settings.recording.microphoneDeviceID == "mic-1")
        #expect(settings.recording.microphoneDeviceName == nil)
        #expect(settings.recording.microphone)
    }

    @Test func wrongNameTypeFallsBack() throws {
        let settings = try decodeSettings(#"{"recording":{"microphoneDeviceID":"mic-1","microphoneDeviceName":7}}"#)
        #expect(settings.recording.microphoneDeviceID == "mic-1", "valid siblings survive")
        #expect(settings.recording.microphoneDeviceName == nil)
    }

    @Test func nameRoundTrips() throws {
        var settings = Settings()
        settings.recording.microphoneDeviceID = "mic-1"
        settings.recording.microphoneDeviceName = "USB Mic"
        let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.recording.microphoneDeviceName == "USB Mic")
        #expect(decoded == settings)
    }
}
