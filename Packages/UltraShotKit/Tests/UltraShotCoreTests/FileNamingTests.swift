import Foundation
import Testing
@testable import UltraShotCore

@Suite("FileNaming")
struct FileNamingTests {
    @Test func defaultTemplate() {
        let name = FileNaming.render(template: FileNaming.defaultTemplate, kind: .screenshot, date: fixedDate, timeZone: utc)
        #expect(name == "UltraShot 2026-11-15 at 10.10.10")
    }

    @Test func kindTokenAndUnknownTokens() {
        let name = FileNaming.render(template: "{kind} {date} {foo} {time}", kind: .recording, date: fixedDate, timeZone: utc)
        #expect(name == "Recording 2026-11-15 {foo} 10.10.10")
    }

    @Test func timeZoneIsHonored() throws {
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        #expect(FileNaming.render(template: "{date} {time}", kind: .screenshot, date: fixedDate, timeZone: tokyo) == "2026-11-15 19.10.10")
    }

    @Test func fileNameAddsExtension() {
        let name = FileNaming.fileName(template: "Shot {time}", kind: .screenshot, date: fixedDate, fileExtension: "png", timeZone: utc)
        #expect(name == "Shot 10.10.10.png")
        #expect(FileNaming.fileName(template: "a", kind: .recording, date: fixedDate, fileExtension: "", timeZone: utc) == "a")
    }

    @Test func renderSanitizes() {
        #expect(FileNaming.render(template: "a/b:{kind}", kind: .screenshot, date: fixedDate, timeZone: utc) == "a-b-Screenshot")
        #expect(FileNaming.render(template: "", kind: .screenshot, date: fixedDate, timeZone: utc) == "UltraShot")
    }

    @Test(arguments: [
        ("a/b:c", "a-b-c"),
        ("  padded  ", "padded"),
        ("line\nbreak\r\ttab", "linebreaktab"),
        ("bell\u{07}\u{7F}", "bell"),
        ("..hidden", "hidden"),
        (". . .x", "x"),
        ("", "UltraShot"),
        ("   ", "UltraShot"),
        ("...", "UltraShot"),
        ("\n\n", "UltraShot"),
        ("emoji 📸 ok", "emoji 📸 ok"),
        ("para\u{2029}graph", "paragraph"),
    ])
    func sanitize(input: String, expected: String) {
        #expect(FileNaming.sanitize(input) == expected)
    }

    @Test func sanitizeCapsLength() {
        let long = String(repeating: "x", count: 500)
        #expect(FileNaming.sanitize(long).count == 200)
        let trailingSpace = String(repeating: "y", count: 199) + "  zzz"
        #expect(FileNaming.sanitize(trailingSpace) == String(repeating: "y", count: 199), "trailing whitespace trimmed after the cut")
    }

    @Test func uniqueURLAppendsCounter() throws {
        let sandbox = try Sandbox()
        let folder = sandbox.url
        #expect(FileNaming.uniqueURL(in: folder, fileName: "a.png").lastPathComponent == "a.png")

        try sandbox.write("1", to: "a.png")
        #expect(FileNaming.uniqueURL(in: folder, fileName: "a.png").lastPathComponent == "a 2.png")

        try sandbox.write("2", to: "a 2.png")
        #expect(FileNaming.uniqueURL(in: folder, fileName: "a.png").lastPathComponent == "a 3.png")
    }

    @Test func uniqueURLWithoutExtensionAndWithDots() throws {
        let sandbox = try Sandbox()
        try sandbox.write("1", to: "notes")
        try sandbox.write("1", to: "UltraShot 2026-11-15 at 10.10.10.png")
        #expect(FileNaming.uniqueURL(in: sandbox.url, fileName: "notes").lastPathComponent == "notes 2")
        let dotted = FileNaming.uniqueURL(in: sandbox.url, fileName: "UltraShot 2026-11-15 at 10.10.10.png")
        #expect(dotted.lastPathComponent == "UltraShot 2026-11-15 at 10.10.10 2.png")
    }

    @Test func compactStamp() {
        #expect(FileNaming.compactStamp(fixedDate, timeZone: utc) == "20261115-101010")
    }
}
