import CoreGraphics
import Foundation

/// Small non-settings state remembered across launches, saved by ``SettingsStore`` as `state.json`.
///
/// Decoding is tolerant like ``Settings``: missing or invalid keys fall back to their defaults.
public struct AppState: Codable, Sendable, Equatable {
    /// Bump when the shape changes incompatibly.
    public static let currentSchemaVersion = 1

    /// Format version of the document. Missing in JSON means ``currentSchemaVersion``.
    public var schemaVersion: Int
    /// The last recorded area in global top-left points, or `nil` if none yet.
    public var lastRecordingArea: CGRect?
    /// `CGDirectDisplayID` of the display ``lastRecordingArea`` was on.
    public var lastRecordingDisplayID: UInt32?

    // Not synthesized because both Codable requirements are implemented by hand.
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case lastRecordingArea
        case lastRecordingDisplayID
    }

    /// Empty state.
    public init() {
        schemaVersion = Self.currentSchemaVersion
        lastRecordingArea = nil
        lastRecordingDisplayID = nil
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = container.lenient(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        lastRecordingArea = container.lenient(CGRect.self, forKey: .lastRecordingArea)
        lastRecordingDisplayID = container.lenient(UInt32.self, forKey: .lastRecordingDisplayID)
    }

    /// Writes every key, with `null` for unset values.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(lastRecordingArea, forKey: .lastRecordingArea)
        try container.encode(lastRecordingDisplayID, forKey: .lastRecordingDisplayID)
    }
}
