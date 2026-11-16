@testable import RecordingKit
import Testing

@Suite("MicrophoneSelection")
struct MicrophoneSelectionTests {
    private let builtIn = MicrophoneDevice(id: "BuiltInMicrophoneDevice", name: "Built-in Microphone")
    private let usb = MicrophoneDevice(id: "AppleUSBAudioEngine:Vendor:Mic:1", name: "USB Mic")

    // MARK: resolve

    @Test func systemDefaultResolvesToNil() {
        let resolution = MicrophoneSelection.resolve(savedID: nil, available: [builtIn, usb])
        #expect(resolution.effectiveDeviceID == nil)
        #expect(!resolution.isSavedDeviceMissing)
    }

    @Test func connectedDeviceIsUsed() {
        let resolution = MicrophoneSelection.resolve(savedID: usb.id, available: [builtIn, usb])
        #expect(resolution.effectiveDeviceID == usb.id)
        #expect(!resolution.isSavedDeviceMissing)
    }

    @Test func missingDeviceFallsBackToSystemDefault() {
        let resolution = MicrophoneSelection.resolve(savedID: usb.id, available: [builtIn])
        #expect(resolution.effectiveDeviceID == nil)
        #expect(resolution.isSavedDeviceMissing)
    }

    @Test func noDevicesAtAll() {
        #expect(MicrophoneSelection.resolve(savedID: nil, available: []).effectiveDeviceID == nil)
        #expect(MicrophoneSelection.resolve(savedID: usb.id, available: []).isSavedDeviceMissing)
    }

    // MARK: options

    @Test func optionsListSystemDefaultThenDevices() {
        let options = MicrophoneSelection.options(savedID: nil, savedName: nil, available: [builtIn, usb], defaultDevice: builtIn)
        #expect(options.map(\.title) == ["System Default (Built-in Microphone)", "Built-in Microphone", "USB Mic"])
        #expect(options.map(\.deviceID) == [nil, builtIn.id, usb.id])
        #expect(options.map(\.kind) == [.systemDefault, .device, .device])
        #expect(options.allSatisfy { $0.isAvailable })
        #expect(Set(options.map(\.id)).count == options.count)
    }

    @Test func systemDefaultWithoutKnownDefaultDevice() {
        let options = MicrophoneSelection.options(savedID: nil, savedName: nil, available: [], defaultDevice: nil)
        #expect(options.map(\.title) == ["System Default"])
    }

    @Test func savedConnectedDeviceAddsNoExtraEntry() {
        let options = MicrophoneSelection.options(savedID: usb.id, savedName: "Old Name", available: [builtIn, usb], defaultDevice: builtIn)
        #expect(options.count == 3)
        #expect(options.last?.title == "USB Mic", "the live name wins over the saved one")
    }

    @Test func missingDeviceKeepsItsSavedName() {
        let options = MicrophoneSelection.options(savedID: usb.id, savedName: "USB Mic", available: [builtIn], defaultDevice: builtIn)
        let last = options.last
        #expect(last?.deviceID == usb.id)
        #expect(last?.title == "USB Mic (disconnected)")
        #expect(last?.kind == .disconnected)
        #expect(last?.isAvailable == false)
    }

    @Test(arguments: [nil, "", "  "] as [String?])
    func missingDeviceWithoutNameIsUnavailable(savedName: String?) {
        let options = MicrophoneSelection.options(savedID: usb.id, savedName: savedName, available: [], defaultDevice: nil)
        #expect(options.map(\.title) == ["System Default", "Unavailable Device"])
    }

    @Test func duplicateDeviceIDsAreListedOnce() {
        let options = MicrophoneSelection.options(savedID: nil, savedName: nil, available: [usb, usb], defaultDevice: nil)
        #expect(options.count == 2)
    }

    // MARK: name

    @Test func nameFollowsTheConnectedDevice() {
        #expect(MicrophoneSelection.name(for: usb.id, available: [builtIn, usb], previousName: "Old") == "USB Mic")
        #expect(MicrophoneSelection.name(for: usb.id, available: [builtIn], previousName: "Old") == "Old")
        #expect(MicrophoneSelection.name(for: nil, available: [builtIn], previousName: "Old") == nil)
    }
}
