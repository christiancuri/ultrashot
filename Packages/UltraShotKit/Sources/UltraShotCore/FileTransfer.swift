import Foundation

/// Moves or copies a capture to a chosen destination without risking an existing file there.
public enum FileTransfer {
    /// Puts the file at `source` at `destination`, moving it (or copying it with `keepSource`).
    ///
    /// An existing file at `destination` is replaced only once the new file is fully in place
    /// next to it (staged, then swapped with `replaceItemAt`), so a failed move or copy leaves
    /// the old file untouched. A missing source throws before anything is touched; the same
    /// path for both is a no-op.
    /// - Returns: the URL of the file at the destination.
    @discardableResult
    public static func place(_ source: URL, at destination: URL, keepSource: Bool, fileManager: FileManager = .default) throws -> URL {
        let sourcePath = source.standardizedFileURL.path(percentEncoded: false)
        guard fileManager.fileExists(atPath: sourcePath) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: sourcePath])
        }
        if sourcePath == destination.standardizedFileURL.path(percentEncoded: false) { return destination }
        let folder = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        guard fileManager.fileExists(atPath: destination.path(percentEncoded: false)) else {
            if keepSource {
                try fileManager.copyItem(at: source, to: destination)
            } else {
                try fileManager.moveItem(at: source, to: destination)
            }
            return destination
        }

        // Stage on the destination's volume, then swap: the old file survives any failure.
        let staged = folder.appending(path: ".\(UUID().uuidString)-\(destination.lastPathComponent)", directoryHint: .notDirectory)
        if keepSource {
            try fileManager.copyItem(at: source, to: staged)
        } else {
            try fileManager.moveItem(at: source, to: staged)
        }
        do {
            return try fileManager.replaceItemAt(destination, withItemAt: staged) ?? destination
        } catch {
            if keepSource {
                try? fileManager.removeItem(at: staged)
            } else {
                try? fileManager.moveItem(at: staged, to: source) // give the source back
            }
            throw error
        }
    }
}
