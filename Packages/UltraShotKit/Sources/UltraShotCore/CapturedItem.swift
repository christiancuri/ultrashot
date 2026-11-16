import Foundation

/// One finished capture: a still screenshot or a screen recording on disk.
public struct CapturedItem: Sendable, Identifiable, Equatable, Hashable {
    /// What kind of capture an item is.
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case screenshot
        case recording

        /// `Screenshot` / `Recording`; also the `{kind}` file-name token.
        public var displayName: String {
            switch self {
            case .screenshot: "Screenshot"
            case .recording: "Recording"
            }
        }
    }

    public let id: UUID
    public let kind: Kind
    /// Current location of the file; changes when the capture is saved (moved).
    public var fileURL: URL
    public let createdAt: Date
    public let pixelWidth: Int
    public let pixelHeight: Int
    /// Length of a recording in seconds; `nil` for screenshots.
    public let duration: TimeInterval?

    public init(
        id: UUID = UUID(),
        kind: Kind,
        fileURL: URL,
        createdAt: Date = Date(),
        pixelWidth: Int,
        pixelHeight: Int,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.kind = kind
        self.fileURL = fileURL
        self.createdAt = createdAt
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.duration = duration
    }
}
