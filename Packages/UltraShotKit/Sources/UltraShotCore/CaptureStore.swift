import Foundation

/// Owns the temporary folder captures are written to before the user saves them.
///
/// Every capture first lands in ``root`` under a unique temporary name; saving moves it to
/// the export folder. The app purges ``root`` on launch.
public struct CaptureStore: Sendable {
    public let root: URL

    /// - Parameter root: the temporary captures folder; created on demand.
    public init(root: URL) {
        self.root = root
    }

    /// `~/Library/Caches/dev.christiancuri.ultrashot/Captures`.
    public static func standard() -> CaptureStore {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let root = caches
            .appending(path: "dev.christiancuri.ultrashot", directoryHint: .isDirectory)
            .appending(path: "Captures", directoryHint: .isDirectory)
        return CaptureStore(root: root)
    }

    /// A fresh, unused URL in ``root`` such as `screenshot-20261115-101010-1A2B3C4D.png`.
    /// Creates ``root`` if needed; the file itself is not created.
    public func makeTemporaryURL(kind: CapturedItem.Kind, ext: String, date: Date = Date()) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let stamp = FileNaming.compactStamp(date)
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        while true {
            let token = UUID().uuidString.prefix(8)
            let url = root.appending(path: "\(kind.rawValue)-\(stamp)-\(token)\(suffix)", directoryHint: .notDirectory)
            if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) { return url }
        }
    }

    /// Moves `item`'s file into `folder` as `fileName`, like the URL overload.
    @discardableResult
    public func save(_ item: CapturedItem, toFolder folder: URL, fileName: String) throws -> URL {
        try save(item.fileURL, toFolder: folder, fileName: fileName)
    }

    /// Moves the file at `url` into `folder` as `fileName`, creating `folder` if needed.
    /// On a name collision the file becomes `name 2.ext`, `name 3.ext`, ...
    /// - Returns: the final URL of the file.
    @discardableResult
    public func save(_ url: URL, toFolder folder: URL, fileName: String) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appending(path: fileName, directoryHint: .notDirectory)
        // Already in place: nothing to move (avoids renaming the file to "name 2").
        if target.standardizedFileURL.path(percentEncoded: false) == url.standardizedFileURL.path(percentEncoded: false) {
            return url
        }
        let destination = FileNaming.uniqueURL(in: folder, fileName: fileName, fileManager: fileManager)
        try fileManager.moveItem(at: url, to: destination)
        Log.core.info("Saved capture as \(destination.lastPathComponent, privacy: .private)")
        return destination
    }

    /// Deletes the file at `url`. Does nothing if it is missing; errors are logged, never thrown.
    public func delete(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Log.core.error("Deleting capture failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Removes everything inside ``root``, keeping the folder itself.
    public func purgeAll() {
        let items = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for item in items {
            do {
                try FileManager.default.removeItem(at: item)
            } catch {
                Log.core.error("Purging capture failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        Log.core.info("Purged \(items.count) leftover capture(s)")
    }

    /// Visible entries in ``root`` sorted by name; empty if ``root`` does not exist.
    public func contents() -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return items.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
