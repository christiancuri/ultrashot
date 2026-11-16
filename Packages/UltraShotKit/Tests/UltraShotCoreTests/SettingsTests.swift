import Foundation
import Testing
@testable import UltraShotCore

@Suite("Settings")
struct SettingsTests {
    @Test func defaultsMatchSpec() {
        let settings = Settings()
        #expect(settings == .defaults)
        #expect(settings.schemaVersion == Settings.currentSchemaVersion)

        let general = settings.general
        #expect(general.playSounds)
        #expect(general.hideDesktopIcons)
        #expect(general.exportFolderPath == "~/Desktop")
        #expect(general.afterCapture.screenshot == AfterCaptureActions(showThumbnail: true, copyToClipboard: true, save: false))
        #expect(general.afterCapture.recording == AfterCaptureActions(showThumbnail: true, copyToClipboard: false, save: false))

        let quickAccess = settings.quickAccess
        #expect(quickAccess.position == .left)
        #expect(quickAccess.moveToActiveScreen)
        #expect(quickAccess.overlaySize == 2)
        #expect(quickAccess.autoClose)
        #expect(quickAccess.autoCloseAction == .saveAndClose)
        #expect(quickAccess.autoCloseInterval == 30)
        #expect(quickAccess.closeAfterDragging)

        let screenshots = settings.screenshots
        #expect(screenshots.format == .png)
        #expect(screenshots.jpegQuality == 0.9)
        #expect(!screenshots.convertToSRGB)
        #expect(!screenshots.downscaleRetina)
        #expect(screenshots.windowShadow)
        #expect(!screenshots.showCursor)

        let recording = settings.recording
        #expect(recording.frameRate == 30)
        #expect(recording.showCursor)
        #expect(recording.systemAudio)
        #expect(!recording.microphone)
        #expect(recording.microphoneDeviceID == nil)
        #expect(!recording.downscaleRetina)
        #expect(recording.rememberLastArea)

        #expect(settings.advanced.fileNameTemplate == FileNaming.defaultTemplate)
    }

    @Test func afterCaptureActionsPerKind() {
        let afterCapture = AfterCaptureSettings()
        #expect(afterCapture.actions(for: .screenshot).copyToClipboard)
        #expect(!afterCapture.actions(for: .recording).copyToClipboard)
    }

    @Test func exportFolderURLExpandsAndAbbreviatesTilde() {
        var general = GeneralSettings()
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(general.exportFolderURL.standardizedFileURL == home.appending(path: "Desktop", directoryHint: .isDirectory).standardizedFileURL)
        #expect(general.exportFolderURL.hasDirectoryPath)

        general.exportFolderURL = home.appending(path: "Pictures/Shots", directoryHint: .isDirectory)
        #expect(general.exportFolderPath == "~/Pictures/Shots")

        general.exportFolderURL = URL(filePath: "/Volumes/Data/Shots", directoryHint: .isDirectory)
        #expect(general.exportFolderPath == "/Volumes/Data/Shots")
    }

    @Test func enumDisplayNamesAndExtensions() {
        #expect(ImageFormat.png.fileExtension == "png")
        #expect(ImageFormat.jpeg.fileExtension == "jpg")
        #expect(ImageFormat.allCases.map(\.displayName) == ["PNG", "JPEG"])
        #expect(AutoCloseAction.allCases.map(\.displayName) == ["Close and Delete", "Save and Close"])
        #expect(QuickAccessPosition.allCases.map(\.displayName) == ["Left", "Right"])
        #expect(CapturedItem.Kind.allCases.map(\.displayName) == ["Screenshot", "Recording"])
    }

    @Test(arguments: [(5, "5 seconds"), (1, "1 second"), (60, "1 minute"), (120, "2 minutes"), (600, "10 minutes"), (90, "90 seconds")])
    func intervalLabels(seconds: Int, label: String) {
        #expect(QuickAccessSettings.intervalLabel(seconds) == label)
    }

    @Test func partialJSONKeepsOtherDefaults() throws {
        let settings = try decodeSettings(#"{"general":{"playSounds":false}}"#)
        var expected = Settings()
        expected.general.playSounds = false
        #expect(settings == expected)
    }

    @Test func emptyObjectDecodesToDefaults() throws {
        #expect(try decodeSettings("{}") == .defaults)
    }

    @Test func partialAfterCaptureUsesPerKindDefaults() throws {
        let settings = try decodeSettings(#"{"general":{"afterCapture":{"screenshot":{"save":true},"recording":7}}}"#)
        #expect(settings.general.afterCapture.screenshot == AfterCaptureActions(showThumbnail: true, copyToClipboard: true, save: true))
        #expect(settings.general.afterCapture.recording == AfterCaptureSettings().recording)
    }

    @Test func unknownEnumValuesFallBack() throws {
        let json = #"""
        {"quickAccess":{"position":"top","autoCloseAction":"explode","autoClose":false},
         "screenshots":{"format":"webp","windowShadow":false}}
        """#
        let settings = try decodeSettings(json)
        #expect(settings.quickAccess.position == .left)
        #expect(settings.quickAccess.autoCloseAction == .saveAndClose)
        #expect(!settings.quickAccess.autoClose, "valid siblings survive")
        #expect(settings.screenshots.format == .png)
        #expect(!settings.screenshots.windowShadow)
    }

    @Test func wrongTypesFallBack() throws {
        let json = #"""
        {"schemaVersion":"one","general":{"playSounds":"yes","exportFolderPath":42,"hideDesktopIcons":false},
         "quickAccess":"big","recording":{"frameRate":"fast","microphoneDeviceID":5,"microphone":true},
         "advanced":{"fileNameTemplate":null}}
        """#
        let settings = try decodeSettings(json)
        #expect(settings.schemaVersion == Settings.currentSchemaVersion)
        #expect(settings.general.playSounds)
        #expect(settings.general.exportFolderPath == "~/Desktop")
        #expect(!settings.general.hideDesktopIcons)
        #expect(settings.quickAccess == QuickAccessSettings())
        #expect(settings.recording.frameRate == 30)
        #expect(settings.recording.microphoneDeviceID == nil)
        #expect(settings.recording.microphone)
        #expect(settings.advanced.fileNameTemplate == FileNaming.defaultTemplate)
    }

    @Test func outOfRangeValuesNormalizedOnDecode() throws {
        let json = #"""
        {"quickAccess":{"overlaySize":9,"autoCloseInterval":45},
         "screenshots":{"jpegQuality":1.7},"recording":{"frameRate":59}}
        """#
        let settings = try decodeSettings(json)
        #expect(settings.quickAccess.overlaySize == 5)
        #expect(settings.quickAccess.autoCloseInterval == 30, "ties snap to the smaller interval")
        #expect(settings.screenshots.jpegQuality == 1)
        #expect(settings.recording.frameRate == 60)

        let low = try decodeSettings(#"{"quickAccess":{"overlaySize":-3,"autoCloseInterval":0},"screenshots":{"jpegQuality":-1},"recording":{"frameRate":1}}"#)
        #expect(low.quickAccess.overlaySize == 1)
        #expect(low.quickAccess.autoCloseInterval == 5)
        #expect(low.screenshots.jpegQuality == 0)
        #expect(low.recording.frameRate == 24)
    }

    @Test func extremeIntegersDoNotOverflow() throws {
        let json = #"{"quickAccess":{"autoCloseInterval":-9223372036854775808},"recording":{"frameRate":9223372036854775807}}"#
        let settings = try decodeSettings(json)
        #expect(settings.quickAccess.autoCloseInterval == 5)
        #expect(settings.recording.frameRate == 60)
    }

    @Test func settersNormalize() {
        var settings = Settings()
        settings.quickAccess.overlaySize = 0
        settings.quickAccess.autoCloseInterval = 1000
        settings.screenshots.jpegQuality = .nan
        settings.recording.frameRate = 26
        #expect(settings.quickAccess.overlaySize == 1)
        #expect(settings.quickAccess.autoCloseInterval == 600)
        #expect(settings.screenshots.jpegQuality == 0.9)
        #expect(settings.recording.frameRate == 24)
    }

    @Test func encodingWritesAllKeys() throws {
        let data = try JSONEncoder().encode(Settings())
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["schemaVersion", "general", "quickAccess", "screenshots", "recording", "advanced"])
        let recording = try #require(object["recording"] as? [String: Any])
        #expect(recording.keys.contains("microphoneDeviceID"), "nil optionals are written as null")
        #expect(recording.keys.contains("microphoneDeviceName"))
        #expect(recording.count == 8)
    }

    @Test func codableRoundTrip() throws {
        var settings = Settings()
        settings.general.afterCapture.recording.save = true
        settings.quickAccess.position = .right
        settings.screenshots.format = .jpeg
        settings.recording.microphoneDeviceID = "BuiltInMic"
        let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
    }
}
