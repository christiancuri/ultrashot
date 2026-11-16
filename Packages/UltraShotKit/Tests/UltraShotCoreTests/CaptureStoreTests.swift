import Foundation
import Testing
@testable import UltraShotCore

@Suite("CaptureStore")
struct CaptureStoreTests {
    @Test func standardLocation() {
        let root = CaptureStore.standard().root
        #expect(root.lastPathComponent == "Captures")
        #expect(root.deletingLastPathComponent().lastPathComponent == "dev.christiancuri.ultrashot")
    }

    @Test func temporaryURLsAreUniqueAndUnclaimed() throws {
        let sandbox = try Sandbox()
        let store = sandbox.captureStore
        #expect(!exists(store.root))

        let urls = try (0..<50).map { _ in try store.makeTemporaryURL(kind: .screenshot, ext: "png", date: fixedDate) }
        #expect(exists(store.root), "root created")
        #expect(Set(urls).count == urls.count)
        #expect(urls.allSatisfy { !exists($0) }, "files are not created")
        #expect(urls.allSatisfy { $0.deletingLastPathComponent().pathComponents == store.root.pathComponents })

        let name = try #require(urls.first?.lastPathComponent)
        #expect(name.hasPrefix("screenshot-"))
        #expect(name.hasSuffix(".png"))
        // screenshot-yyyyMMdd-HHmmss-XXXXXXXX.png
        let stem = name.dropFirst("screenshot-".count).dropLast(".png".count)
        let parts = stem.split(separator: "-")
        #expect(parts.count == 3)
        #expect(parts.first?.count == 8)
        #expect(parts.dropFirst().first?.count == 6)
        #expect(parts.last?.count == 8)
    }

    @Test func temporaryURLUsesKindAndExtension() throws {
        let sandbox = try Sandbox()
        let url = try sandbox.captureStore.makeTemporaryURL(kind: .recording, ext: "mov")
        #expect(url.lastPathComponent.hasPrefix("recording-"))
        #expect(url.pathExtension == "mov")
    }

    @Test func saveMovesFileAndCreatesFolder() throws {
        let sandbox = try Sandbox()
        let store = sandbox.captureStore
        let temp = try store.makeTemporaryURL(kind: .screenshot, ext: "png")
        try Data("pixels".utf8).write(to: temp)

        let folder = sandbox.path("Export/Shots")
        let saved = try store.save(temp, toFolder: folder, fileName: "Shot.png")
        #expect(saved.lastPathComponent == "Shot.png")
        #expect(saved.deletingLastPathComponent().pathComponents == folder.pathComponents)
        #expect(try Data(contentsOf: saved) == Data("pixels".utf8))
        #expect(!exists(temp), "moved, not copied")
    }

    @Test func saveCollisionGetsCounter() throws {
        let sandbox = try Sandbox()
        let store = sandbox.captureStore
        let folder = sandbox.path("Export")
        try sandbox.write("existing", to: "Export/Shot.png")

        let first = try store.makeTemporaryURL(kind: .screenshot, ext: "png")
        try Data("one".utf8).write(to: first)
        #expect(try store.save(first, toFolder: folder, fileName: "Shot.png").lastPathComponent == "Shot 2.png")

        let second = try store.makeTemporaryURL(kind: .screenshot, ext: "png")
        try Data("two".utf8).write(to: second)
        #expect(try store.save(second, toFolder: folder, fileName: "Shot.png").lastPathComponent == "Shot 3.png")
        #expect(try String(contentsOf: folder.appending(path: "Shot.png"), encoding: .utf8) == "existing")
    }

    @Test func saveItemMovesItsFile() throws {
        let sandbox = try Sandbox()
        let store = sandbox.captureStore
        let temp = try store.makeTemporaryURL(kind: .recording, ext: "mov")
        try Data("frames".utf8).write(to: temp)
        let item = CapturedItem(kind: .recording, fileURL: temp, pixelWidth: 1920, pixelHeight: 1080, duration: 3.5)

        let saved = try store.save(item, toFolder: sandbox.path("Export"), fileName: "Clip.mov")
        #expect(saved.lastPathComponent == "Clip.mov")
        #expect(exists(saved))
        #expect(!exists(temp))
    }

    @Test func saveInPlaceIsNoOp() throws {
        let sandbox = try Sandbox()
        let file = try sandbox.write("x", to: "Export/Shot.png")
        let saved = try sandbox.captureStore.save(file, toFolder: sandbox.path("Export"), fileName: "Shot.png")
        #expect(saved == file)
        #expect(sandbox.files(in: "Export") == ["Shot.png"])
    }

    @Test func saveMissingSourceThrows() throws {
        let sandbox = try Sandbox()
        #expect(throws: (any Error).self) {
            try sandbox.captureStore.save(sandbox.path("nope.png"), toFolder: sandbox.path("Export"), fileName: "a.png")
        }
    }

    @Test func deleteRemovesFileAndToleratesMissing() throws {
        let sandbox = try Sandbox()
        let store = sandbox.captureStore
        let file = try sandbox.write("x", to: "Captures/a.png")
        store.delete(file)
        #expect(!exists(file))
        store.delete(file)
        store.delete(sandbox.path("never/existed.png"))
    }

    @Test func purgeAllKeepsRoot() throws {
        let sandbox = try Sandbox()
        let store = sandbox.captureStore
        store.purgeAll()
        try sandbox.write("1", to: "Captures/a.png")
        try sandbox.write("2", to: "Captures/sub/b.mov")
        try sandbox.write("3", to: "Captures/.hidden")

        store.purgeAll()
        #expect(exists(store.root))
        #expect(sandbox.files(in: "Captures").isEmpty)
    }

    @Test func contentsSortedByName() throws {
        let sandbox = try Sandbox()
        let store = sandbox.captureStore
        #expect(store.contents().isEmpty)
        try sandbox.write("1", to: "Captures/b.png")
        try sandbox.write("2", to: "Captures/a.png")
        try sandbox.write("3", to: "Captures/c.mov")
        #expect(store.contents().map(\.lastPathComponent) == ["a.png", "b.png", "c.mov"])
    }
}
