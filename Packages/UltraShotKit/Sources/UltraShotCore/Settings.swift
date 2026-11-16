import Foundation

/// Everything the user configured, saved by ``SettingsStore`` as one versioned JSON document.
///
/// Decoding is tolerant at every level: missing keys, `null`, wrong types and unknown enum
/// values fall back to that key's default instead of failing the whole document, so new
/// settings can be added without a schema bump. Numeric fields are clamped or snapped to
/// their supported values both on decode and whenever they are assigned (`didSet`).
public struct Settings: Codable, Sendable, Equatable, Hashable {
    /// Bump when the shape changes incompatibly, and add a migration in ``SettingsStore``.
    public static let currentSchemaVersion = 1

    /// Format version of the document. Missing in JSON means ``currentSchemaVersion``.
    public var schemaVersion: Int
    public var general: GeneralSettings
    public var quickAccess: QuickAccessSettings
    public var screenshots: ScreenshotSettings
    public var recording: RecordingSettings
    public var advanced: AdvancedSettings

    /// All defaults.
    public init() {
        schemaVersion = Self.currentSchemaVersion
        general = GeneralSettings()
        quickAccess = QuickAccessSettings()
        screenshots = ScreenshotSettings()
        recording = RecordingSettings()
        advanced = AdvancedSettings()
    }

    /// First-launch settings.
    public static let defaults = Settings()

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = container.lenient(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        general = container.lenient(GeneralSettings.self, forKey: .general) ?? GeneralSettings()
        quickAccess = container.lenient(QuickAccessSettings.self, forKey: .quickAccess) ?? QuickAccessSettings()
        screenshots = container.lenient(ScreenshotSettings.self, forKey: .screenshots) ?? ScreenshotSettings()
        recording = container.lenient(RecordingSettings.self, forKey: .recording) ?? RecordingSettings()
        advanced = container.lenient(AdvancedSettings.self, forKey: .advanced) ?? AdvancedSettings()
    }
}

/// Which edge of the screen the Quick Access overlay sits on.
public enum QuickAccessPosition: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case left
    case right

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        }
    }
}

/// What happens when the Quick Access overlay closes itself after its interval.
public enum AutoCloseAction: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    /// Dismiss the overlay; unsaved captures are discarded.
    case close
    /// Save the capture to the export folder, then dismiss.
    case saveAndClose

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .close: "Close and Delete"
        case .saveAndClose: "Save and Close"
        }
    }
}

/// Encoded format for still screenshots.
public enum ImageFormat: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case png
    case jpeg

    public var id: String { rawValue }

    /// Extension without the dot: `png` / `jpg`.
    public var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        }
    }

    public var displayName: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        }
    }
}
