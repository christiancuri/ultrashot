import Foundation
import Testing
@testable import UltraShotCore

@Suite("FileTransfer")
struct FileTransferTests {
    private func read(_ url: URL) -> String? {
        (try? Data(contentsOf: url)).flatMap { String(bytes: $0, encoding: .utf8) }
    }

    @Test func movesWhenTheDestinationIsFree() throws {
        let sandbox = try Sandbox()
        let source = try sandbox.write("new", to: "Captures/a.png")
        let destination = sandbox.path("Export/sub/a.png")
        let placed = try FileTransfer.place(source, at: destination, keepSource: false)
        #expect(read(placed) == "new")
        #expect(!exists(source))
    }

    @Test func replacesAnExistingFileByMoving() throws {
        let sandbox = try Sandbox()
        let source = try sandbox.write("new", to: "Captures/a.png")
        let destination = try sandbox.write("old", to: "Export/a.png")
        let placed = try FileTransfer.place(source, at: destination, keepSource: false)
        #expect(read(placed) == "new")
        #expect(!exists(source))
        #expect(sandbox.files(in: "Export") == ["a.png"], "no staged leftovers")
    }

    @Test func replacesAnExistingFileByCopyingAndKeepsTheSource() throws {
        let sandbox = try Sandbox()
        let source = try sandbox.write("new", to: "Captures/a.mp4")
        let destination = try sandbox.write("old", to: "Export/a.mp4")
        try FileTransfer.place(source, at: destination, keepSource: true)
        #expect(read(destination) == "new")
        #expect(read(source) == "new")
        #expect(sandbox.files(in: "Export") == ["a.mp4"])
    }

    @Test func missingSourceLeavesTheExistingFileAlone() throws {
        let sandbox = try Sandbox()
        let destination = try sandbox.write("old", to: "Export/a.png")
        #expect(throws: (any Error).self) {
            try FileTransfer.place(sandbox.path("Captures/gone.png"), at: destination, keepSource: false)
        }
        #expect(read(destination) == "old")
    }

    @Test func samePathIsANoOp() throws {
        let sandbox = try Sandbox()
        let file = try sandbox.write("keep", to: "Export/a.png")
        let placed = try FileTransfer.place(file, at: sandbox.path("Export/./a.png"), keepSource: true)
        #expect(read(placed) == "keep")
        #expect(sandbox.files(in: "Export") == ["a.png"])
    }
}

@Suite("InstanceLock")
struct InstanceLockTests {
    @Test func secondLockFailsUntilTheFirstIsReleased() throws {
        let sandbox = try Sandbox()
        let url = sandbox.path("Caches/Captures.lock")
        var first: InstanceLock? = InstanceLock(url: url)
        #expect(first != nil)
        #expect(InstanceLock(url: url) == nil, "flock conflicts across open file descriptions")
        first = nil
        #expect(InstanceLock(url: url) != nil)
    }

    @Test func lockFileSitsNextToTheCaptureStore() throws {
        let sandbox = try Sandbox()
        let store = sandbox.captureStore
        #expect(store.instanceLockURL.deletingLastPathComponent().standardizedFileURL
                    == store.root.deletingLastPathComponent().standardizedFileURL)
        #expect(!store.isTemporary(store.instanceLockURL), "purging the store never removes the lock")
    }
}

@Suite("Export folder safety")
struct ExportFolderSafetyTests {
    @Test func captureFolderAndItsSubfoldersAreUnsafe() {
        let store = CaptureStore(root: URL(filePath: "/tmp/caps/Captures", directoryHint: .isDirectory))
        let fallback = URL(filePath: "/Users/x/Desktop", directoryHint: .isDirectory)
        #expect(store.isUnsafeExportFolder(URL(filePath: "/tmp/caps/Captures", directoryHint: .isDirectory)))
        #expect(store.isUnsafeExportFolder(URL(filePath: "/tmp/caps/Captures")))
        #expect(store.isUnsafeExportFolder(URL(filePath: "/tmp/caps/Captures/Saved", directoryHint: .isDirectory)))
        #expect(store.exportFolder(URL(filePath: "/tmp/caps/Captures/Saved"), fallback: fallback) == fallback)
    }

    @Test func otherFoldersAreKept() {
        let store = CaptureStore(root: URL(filePath: "/tmp/caps/Captures", directoryHint: .isDirectory))
        let fallback = URL(filePath: "/Users/x/Desktop", directoryHint: .isDirectory)
        for path in ["/tmp/caps", "/tmp/caps/CapturesSaved", "/Users/x/Pictures"] {
            let folder = URL(filePath: path, directoryHint: .isDirectory)
            #expect(!store.isUnsafeExportFolder(folder), "\(path)")
            #expect(store.exportFolder(folder, fallback: fallback) == folder)
        }
    }
}
