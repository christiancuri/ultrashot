@testable import CaptureKit
import CoreGraphics
import Foundation
import Testing

struct WindowListTests {
    private func window(_ id: CGWindowID, _ frame: CGRect, pid: pid_t = 100) -> WindowInfo {
        WindowInfo(id: id, frameCG: frame, ownerPID: pid, ownerName: "App", title: nil, layer: 0)
    }

    @Test func topmostPicksFrontmostContainingWindow() {
        // Front to back: small front window, big middle window, full-screen back window.
        let list = [
            window(1, CGRect(x: 100, y: 100, width: 200, height: 100)),
            window(2, CGRect(x: 50, y: 50, width: 600, height: 400)),
            window(3, CGRect(x: 0, y: 0, width: 1800, height: 1169))
        ]
        #expect(WindowList.topmost(at: CGPoint(x: 150, y: 150), in: list)?.id == 1)
        #expect(WindowList.topmost(at: CGPoint(x: 60, y: 60), in: list)?.id == 2)
        #expect(WindowList.topmost(at: CGPoint(x: 1000, y: 1000), in: list)?.id == 3)
        #expect(WindowList.topmost(at: CGPoint(x: -10, y: 5), in: list) == nil)
    }

    @Test func topmostWorksOnNegativeCoordinates() {
        let list = [window(7, CGRect(x: -1920, y: -1080, width: 800, height: 600))]
        #expect(WindowList.topmost(at: CGPoint(x: -1500, y: -700), in: list)?.id == 7)
    }

    private func entry(_ number: Int, layer: Int = 0, pid: Int = 100, alpha: Double = 1,
                       bounds: CGRect = CGRect(x: 0, y: 0, width: 300, height: 200),
                       name: String? = nil) -> [String: Any] {
        var dict: [String: Any] = [
            kCGWindowNumber as String: NSNumber(value: number),
            kCGWindowLayer as String: NSNumber(value: layer),
            kCGWindowOwnerPID as String: NSNumber(value: pid),
            kCGWindowOwnerName as String: "Owner\(pid)",
            kCGWindowAlpha as String: NSNumber(value: alpha),
            kCGWindowBounds as String: bounds.dictionaryRepresentation
        ]
        if let name { dict[kCGWindowName as String] = name }
        return dict
    }

    @Test func parsingFiltersAndKeepsOrder() {
        let entries = [
            entry(1, layer: 25),                                        // status/menu level
            entry(2, name: "Doc"),
            entry(3, pid: 42),                                          // own process
            entry(4, alpha: 0),                                         // invisible
            entry(5, bounds: CGRect(x: 0, y: 0, width: 39, height: 300)), // too thin
            entry(6, bounds: CGRect(x: -500, y: -300, width: 40, height: 40), name: "")
        ]
        let windows = WindowList.windows(from: entries, excludingPID: 42)
        #expect(windows.map(\.id) == [2, 6])
        #expect(windows[0].title == "Doc")
        #expect(windows[0].ownerName == "Owner100")
        #expect(windows[1].title == nil)
        #expect(windows[1].frameCG == CGRect(x: -500, y: -300, width: 40, height: 40))
    }

    @Test func parsingSkipsMalformedEntries() {
        var broken = entry(9)
        broken.removeValue(forKey: kCGWindowBounds as String)
        #expect(WindowList.windows(from: [broken], excludingPID: 0).isEmpty)
    }

    @Test func liveListExcludesOwnProcessAndIsLayerZero() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let windows = WindowList.onScreen(excludingPID: pid)
        #expect(windows.allSatisfy { $0.ownerPID != pid && $0.layer == 0 })
        #expect(windows.allSatisfy { $0.frameCG.width >= 40 && $0.frameCG.height >= 40 })
    }
}
