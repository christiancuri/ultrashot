import Foundation

/// What to do with a finished capture, derived from its kind and the after-capture settings.
///
/// Screenshots go to the clipboard as image data (so pasting still works after the temporary
/// file is deleted). Recordings go to the clipboard as a file reference, which means the file
/// must stay on disk until the clipboard is replaced by the next capture.
public struct DeliveryPlan: Equatable, Sendable {
    public enum ClipboardContent: Equatable, Sendable {
        case none
        /// PNG + TIFF data; no file URL.
        case imageData
        /// The file URL; the file must outlive the clipboard entry.
        case fileReference
    }

    public var clipboard: ClipboardContent
    /// Move the file to the export folder right away.
    public var save: Bool
    public var showThumbnail: Bool

    public init(clipboard: ClipboardContent, save: Bool, showThumbnail: Bool) {
        self.clipboard = clipboard
        self.save = save
        self.showThumbnail = showThumbnail
    }

    /// The plan for a capture of `kind` with `actions`.
    public static func make(kind: CapturedItem.Kind, actions: AfterCaptureActions) -> DeliveryPlan {
        let clipboard: ClipboardContent = switch (actions.copyToClipboard, kind) {
        case (false, _): .none
        case (true, .screenshot): .imageData
        case (true, .recording): .fileReference
        }
        return DeliveryPlan(clipboard: clipboard, save: actions.save, showThumbnail: actions.showThumbnail)
    }

    /// Nothing keeps the temporary file after delivery: delete it right away.
    /// (A saved file is no longer temporary, and a thumbnail or a clipboard file reference
    /// keeps it alive.)
    public var deletesTemporaryFile: Bool {
        !save && !showThumbnail && clipboard != .fileReference
    }
}

/// Who still needs a capture file on disk. A temporary capture is deleted once its last
/// holder lets go; saved files are never deleted (see ``CaptureStore/isTemporary(_:)``).
public struct CaptureFileHolds: Sendable, Equatable {
    public enum Holder: Hashable, Sendable {
        /// An open thumbnail, by capture id.
        case thumbnail(UUID)
        /// The clipboard holds a file reference (recordings).
        case clipboard
    }

    private var holds: [URL: Set<Holder>] = [:]

    public init() {}

    public mutating func retain(_ url: URL, by holder: Holder) {
        holds[key(url), default: []].insert(holder)
    }

    /// Drops `holder`'s claim on `url`.
    /// - Returns: `true` when nobody holds `url` any more.
    @discardableResult
    public mutating func release(_ url: URL, by holder: Holder) -> Bool {
        let key = key(url)
        holds[key]?.remove(holder)
        if holds[key]?.isEmpty ?? true {
            holds[key] = nil
            return true
        }
        return false
    }

    /// Forgets every holder of `url` (the file was deleted on purpose).
    public mutating func removeAll(for url: URL) {
        holds[key(url)] = nil
    }

    public func isHeld(_ url: URL) -> Bool {
        !(holds[key(url)]?.isEmpty ?? true)
    }

    public func holders(of url: URL) -> Set<Holder> {
        holds[key(url)] ?? []
    }

    /// The file `holder` currently holds, if any (e.g. the clipboard's file reference).
    public func url(heldBy holder: Holder) -> URL? {
        holds.first { $0.value.contains(holder) }?.key
    }

    /// The file moved (saved): its holders now refer to `destination`.
    public mutating func move(_ source: URL, to destination: URL) {
        guard let holders = holds.removeValue(forKey: key(source)) else { return }
        holds[key(destination), default: []].formUnion(holders)
    }

    private func key(_ url: URL) -> URL {
        url.standardizedFileURL
    }
}

extension CaptureStore {
    /// Whether `url` lives in the temporary captures folder (and may be deleted).
    /// Files anywhere else, e.g. saved to the export folder, are the user's.
    public func isTemporary(_ url: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path(percentEncoded: false)
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return url.standardizedFileURL.path(percentEncoded: false).hasPrefix(prefix)
    }

    /// Whether `folder` cannot hold saved captures: the captures folder itself or anything in
    /// it, where saved files would count as temporary and be deleted.
    public func isUnsafeExportFolder(_ folder: URL) -> Bool {
        let path = folder.standardizedFileURL.path(percentEncoded: false)
        let rootPath = root.standardizedFileURL.path(percentEncoded: false)
        let trim = { (value: String) in value.count > 1 && value.hasSuffix("/") ? String(value.dropLast()) : value }
        return trim(path) == trim(rootPath) || isTemporary(folder)
    }

    /// `requested`, or `fallback` when `requested` is an unsafe export folder.
    public func exportFolder(_ requested: URL, fallback: URL) -> URL {
        isUnsafeExportFolder(requested) ? fallback : requested
    }
}
