import CoreGraphics
import Foundation
import Testing
@testable import UltraShotCore

@Suite("SettingsStore")
struct SettingsStoreTests {
    @Test func missingFilesYieldDefaults() throws {
        let sandbox = try Sandbox()
        let store = sandbox.settingsStore
        #expect(store.loadSettings() == .defaults)
        #expect(store.loadState() == AppState())
        #expect(!exists(store.directory), "loading never creates files")
    }

    @Test func fileLocations() throws {
        let sandbox = try Sandbox()
        let store = sandbox.settingsStore
        #expect(store.settingsURL.lastPathComponent == "settings.json")
        #expect(store.stateURL.lastPathComponent == "state.json")
        #expect(store.settingsURL.deletingLastPathComponent().pathComponents == store.directory.pathComponents)
        #expect(store.stateURL.deletingLastPathComponent().pathComponents == store.directory.pathComponents)
        #expect(SettingsStore.standard().directory.lastPathComponent == "dev.christiancuri.ultrashot")
    }

    @Test func settingsRoundTrip() throws {
        let sandbox = try Sandbox()
        let store = sandbox.settingsStore
        var settings = Settings()
        settings.general.playSounds = false
        settings.general.exportFolderPath = "~/Pictures"
        settings.quickAccess.autoCloseInterval = 120
        settings.quickAccess.autoCloseAction = .close
        settings.screenshots.format = .jpeg
        settings.screenshots.jpegQuality = 0.5
        settings.recording.frameRate = 60
        settings.recording.microphoneDeviceID = "mic-1"
        settings.advanced.fileNameTemplate = "{kind} {date}"
        try store.save(settings)

        #expect(store.loadSettings() == settings)
        let json = try String(contentsOf: store.settingsURL, encoding: .utf8)
        #expect(json.contains("\"schemaVersion\" : 1"), "pretty-printed")
        let general = try #require(json.range(of: "\"general\""))
        let quickAccess = try #require(json.range(of: "\"quickAccess\""))
        #expect(general.lowerBound < quickAccess.lowerBound, "sorted keys")
    }

    @Test func missingSchemaVersionIsCurrent() throws {
        let sandbox = try Sandbox()
        let store = sandbox.settingsStore
        try sandbox.write(#"{"general":{"playSounds":false}}"#, to: "Support/settings.json")
        let settings = store.loadSettings()
        #expect(settings.schemaVersion == Settings.currentSchemaVersion)
        #expect(!settings.general.playSounds)
        #expect(sandbox.files(in: "Support") == ["settings.json"], "no backup for a readable file")
    }

    @Test func corruptFileIsBackedUp() throws {
        let sandbox = try Sandbox()
        let store = sandbox.settingsStore
        let garbage = #"{"general":{"playSounds":"#
        try sandbox.write(garbage, to: "Support/settings.json")

        #expect(store.loadSettings() == .defaults)
        let files = sandbox.files(in: "Support")
        #expect(files.count == 1)
        let backupName = try #require(files.first)
        #expect(backupName.hasPrefix("settings.corrupt-"))
        #expect(backupName.hasSuffix(".json"))
        #expect(try String(contentsOf: sandbox.path("Support/\(backupName)"), encoding: .utf8) == garbage, "original bytes preserved")
        #expect(!exists(store.settingsURL))
    }

    @Test func nonObjectDocumentIsBackedUp() throws {
        let sandbox = try Sandbox()
        try sandbox.write("[1, 2, 3]", to: "Support/settings.json")
        #expect(sandbox.settingsStore.loadSettings() == .defaults)
        #expect(sandbox.files(in: "Support").first?.hasPrefix("settings.corrupt-") == true)
    }

    @Test func repeatedCorruptionKeepsEveryBackup() throws {
        let sandbox = try Sandbox()
        let store = sandbox.settingsStore
        try sandbox.write("nope", to: "Support/settings.json")
        _ = store.loadSettings()
        try sandbox.write("still nope", to: "Support/settings.json")
        _ = store.loadSettings()
        let backups = sandbox.files(in: "Support").filter { $0.hasPrefix("settings.corrupt-") }
        #expect(backups.count == 2)
    }

    @Test func newerSchemaVersionIsBackedUp() throws {
        let sandbox = try Sandbox()
        let store = sandbox.settingsStore
        try sandbox.write(#"{"schemaVersion":99,"general":{"playSounds":false}}"#, to: "Support/settings.json")
        #expect(store.loadSettings() == .defaults)
        let files = sandbox.files(in: "Support")
        #expect(files.count == 1)
        #expect(files.first?.hasPrefix("settings.corrupt-") == true)
    }

    @Test func saveCreatesDirectoryAndOverwrites() throws {
        let sandbox = try Sandbox()
        let store = SettingsStore(directory: sandbox.path("Deep/Nested/Support"))
        var settings = Settings()
        try store.save(settings)
        settings.general.hideDesktopIcons = false
        try store.save(settings)
        #expect(store.loadSettings() == settings)
    }

    @Test func stateRoundTripWithRect() throws {
        let sandbox = try Sandbox()
        let store = sandbox.settingsStore
        var state = AppState()
        state.lastRecordingArea = CGRect(x: 120.5, y: -40, width: 800, height: 600.25)
        state.lastRecordingDisplayID = 69_733_382
        try store.save(state)
        #expect(store.loadState() == state)

        try store.save(AppState())
        let json = try String(contentsOf: store.stateURL, encoding: .utf8)
        #expect(json.contains("\"lastRecordingArea\" : null"), "every key written")
        #expect(store.loadState() == AppState())
    }

    @Test func corruptOrNewerStateYieldsDefaults() throws {
        let sandbox = try Sandbox()
        let store = sandbox.settingsStore
        try sandbox.write("{{{", to: "Support/state.json")
        #expect(store.loadState() == AppState())

        try sandbox.write(#"{"schemaVersion":7,"lastRecordingDisplayID":1}"#, to: "Support/state.json")
        #expect(store.loadState() == AppState())

        try sandbox.write(#"{"lastRecordingArea":"wide","lastRecordingDisplayID":3}"#, to: "Support/state.json")
        let partial = store.loadState()
        #expect(partial.lastRecordingArea == nil)
        #expect(partial.lastRecordingDisplayID == 3)
    }
}
