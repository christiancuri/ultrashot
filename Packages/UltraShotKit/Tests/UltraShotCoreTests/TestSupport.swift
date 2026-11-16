import Foundation
@testable import UltraShotCore

/// A temporary directory for one test, removed on deinit.
final class Sandbox: Sendable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "UltraShotCoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func path(_ relative: String) -> URL {
        url.appending(path: relative)
    }

    var settingsStore: SettingsStore { SettingsStore(directory: path("Support")) }
    var captureStore: CaptureStore { CaptureStore(root: path("Captures")) }

    func files(in relative: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: path(relative).path(percentEncoded: false))) ?? []).sorted()
    }

    /// Writes `contents` to `relative`, creating intermediate folders.
    @discardableResult
    func write(_ contents: String, to relative: String) throws -> URL {
        let file = path(relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: file)
        return file
    }
}

func exists(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
}

func decodeSettings(_ json: String) throws -> Settings {
    try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
}

/// 2026-11-15T10:10:10Z.
let fixedDate = Date(timeIntervalSince1970: 1_794_737_410)

let utc = TimeZone(identifier: "UTC") ?? .gmt
