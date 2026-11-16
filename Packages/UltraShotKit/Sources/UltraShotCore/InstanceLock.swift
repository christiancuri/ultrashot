import Darwin
import Foundation

/// An exclusive advisory lock (`flock`) on a file, held until the lock is released or the
/// process exits. UltraShot takes one next to the capture store at launch and purges leftover
/// captures only when it gets it, so a second instance never deletes the files (or a
/// recording being written) of the one already running.
public final class InstanceLock: Sendable {
    public let url: URL
    private let descriptor: Int32

    /// Takes the lock without waiting; `nil` when another process (or another open of the
    /// same file) holds it, or the file cannot be opened.
    public init?(url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(url.path(percentEncoded: false), O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { return nil }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }
        self.url = url
        self.descriptor = descriptor
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}

extension CaptureStore {
    /// The lock file of the instance that owns ``root``: next to it, so purging never
    /// removes it.
    public var instanceLockURL: URL {
        root.deletingLastPathComponent().appending(path: "\(root.lastPathComponent).lock", directoryHint: .notDirectory)
    }
}
