import AppKit
@testable import CaptureKit
import ScreenCaptureKit
import Testing

/// Live ScreenCaptureKit tests. Skipped without Screen Recording permission.
/// Images of the real screen are only inspected for metadata, never written or viewed.
@MainActor
@Suite(.serialized, .enabled(if: ScreenCapturePermission.isGranted), .timeLimit(.minutes(1)))
struct LiveCaptureTests {
    private static let clock = ContinuousClock()

    private static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    private func mainDescriptor() throws -> DisplayDescriptor {
        let screen = try #require(NSScreen.screens.first)
        return try #require(DisplayDescriptor(screen: screen))
    }

    /// Declared first so it is the first ScreenCaptureKit call of the process when the suite runs alone.
    @Test func snapshotMainDisplayMatchesFrameTimesScale() async throws {
        let capture = StillCapture()
        let display = try mainDescriptor()
        let start = Self.clock.now
        let snapshots = try await capture.snapshotDisplays([display], options: SnapshotOptions())
        let cold = Self.milliseconds(Self.clock.now - start)
        let snapshot = try #require(snapshots.first)
        #expect(snapshot.displayID == display.displayID)
        #expect(snapshot.image.width == Int(display.frame.width * display.scale))
        #expect(snapshot.image.height == Int(display.frame.height * display.scale))
        #expect(snapshot.image.colorSpace?.copyICCData() != nil)

        var warm: [Double] = []
        for _ in 0..<5 {
            let tick = Self.clock.now
            _ = try await capture.snapshotDisplays([display], options: SnapshotOptions())
            warm.append(Self.milliseconds(Self.clock.now - tick))
        }
        print("LATENCY rect snapshot cold=\(cold) ms warm=\(warm.map { Int($0) }) ms")
    }

    @Test func hideDesktopIconsSnapshotSucceedsAtNativeSize() async throws {
        let capture = StillCapture()
        let display = try mainDescriptor()
        let options = SnapshotOptions(hideDesktopIcons: true, showCursor: false)
        var times: [Double] = []
        var snapshot: DisplaySnapshot?
        for _ in 0..<4 {
            let tick = Self.clock.now
            snapshot = try await capture.snapshotDisplays([display], options: options).first
            times.append(Self.milliseconds(Self.clock.now - tick))
        }
        let result = try #require(snapshot)
        #expect(result.image.width == Int(display.frame.width * display.scale))
        #expect(result.image.height == Int(display.frame.height * display.scale))
        print("LATENCY hide-icons snapshot (first in this test, then warm)=\(times.map { Int($0) }) ms")
    }

    /// Exercises the concurrent multi-display path (the main display twice) on both capture paths.
    @Test(arguments: [false, true])
    func multipleDisplaysKeepOrderAndSize(hideDesktopIcons: Bool) async throws {
        let display = try mainDescriptor()
        let options = SnapshotOptions(hideDesktopIcons: hideDesktopIcons)
        let capture = StillCapture()
        _ = try await capture.snapshotDisplays([display], options: options) // warm up
        let tick = Self.clock.now
        let snapshots = try await capture.snapshotDisplays([display, display], options: options)
        let elapsed = Self.milliseconds(Self.clock.now - tick)
        #expect(snapshots.count == 2)
        #expect(snapshots.allSatisfy { $0.image.width == Int(display.frame.width * display.scale) })
        print("LATENCY 2-display snapshot via StillCapture hideIcons=\(hideDesktopIcons): \(Int(elapsed)) ms")
    }

    @Test func showCursorSnapshotSucceeds() async throws {
        let display = try mainDescriptor()
        let snapshot = try await StillCapture()
            .snapshotDisplays([display], options: SnapshotOptions(showCursor: true)).first
        #expect(snapshot?.image.width == Int(display.frame.width * display.scale))
    }

    @Test func unknownDisplayThrows() async throws {
        let bogus = DisplayDescriptor(displayID: 0xDEAD, frame: CGRect(x: 0, y: 0, width: 10, height: 10), scale: 1)
        await #expect(throws: CaptureError.displayNotFound(0xDEAD)) {
            _ = try await StillCapture().snapshotDisplays([bogus], options: SnapshotOptions())
        }
        await #expect(throws: CaptureError.displayNotFound(0xDEAD)) {
            _ = try await StillCapture().snapshotDisplays([bogus], options: SnapshotOptions(hideDesktopIcons: true))
        }
    }

    @Test func unknownWindowThrows() async {
        await #expect(throws: CaptureError.windowNotFound(0xFFFF_FFF0)) {
            _ = try await StillCapture().captureWindow(0xFFFF_FFF0, includeShadow: false)
        }
    }

    /// Captures a window this test creates, by id.
    @Test func captureOwnWindowByID() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let window = NSWindow(contentRect: NSRect(x: 300, y: 300, width: 320, height: 200),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .systemTeal
        window.level = .normal // layer 0, so WindowList includes it
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(500))

        let id = CGWindowID(window.windowNumber)
        let scale = window.backingScaleFactor
        let capture = StillCapture()

        let plain = try await capture.captureWindow(id, includeShadow: false)
        #expect(plain.width == Int(window.frame.width * scale))
        #expect(plain.height == Int(window.frame.height * scale))
        #expect(ImageProcessing.hasAlpha(plain))

        let shadowed = try await capture.captureWindow(id, includeShadow: true)
        #expect(shadowed.width > plain.width && shadowed.height > plain.height)

        let opaque = try await capture.captureWindow(id, includeShadow: false, opaque: true)
        #expect(!ImageProcessing.hasAlpha(opaque))
        #expect(opaque.width == plain.width)

        // The window is listed by CGWindowList when our own pid is not excluded.
        let listed = WindowList.onScreen(excludingPID: -1).first { $0.id == id }
        let expectedFrame = ScreenGeometry.appKitToCG(window.frame, primaryScreenHeight: NSScreen.screens[0].frame.height)
        #expect(listed?.frameCG == expectedFrame)
    }

    /// Measures whether two ScreenCaptureKit display captures overlap when issued together.
    /// Uses the main display twice, since this machine may have only one display.
    @Test func concurrentVersusSequentialCaptures() async throws {
        let bounds = CGDisplayBounds(CGMainDisplayID())
        _ = try await Self.rectShot(bounds) // warm up
        var sequential: [Double] = []
        var concurrent: [Double] = []
        for _ in 0..<5 {
            var tick = Self.clock.now
            _ = try await Self.rectShot(bounds)
            _ = try await Self.rectShot(bounds)
            sequential.append(Self.milliseconds(Self.clock.now - tick))
            tick = Self.clock.now
            async let first = Self.rectShot(bounds)
            async let second = Self.rectShot(bounds)
            _ = try await (first, second)
            concurrent.append(Self.milliseconds(Self.clock.now - tick))
        }
        print("LATENCY 2 captures sequential=\(sequential.map { Int($0) }) ms concurrent=\(concurrent.map { Int($0) }) ms")
    }

    private nonisolated static func rectShot(_ rect: CGRect) async throws -> CGImage {
        let config = SCScreenshotConfiguration()
        config.showsCursor = false
        let output = try await SCScreenshotManager.captureScreenshot(rect: rect, configuration: config)
        return try #require(output.sdrImage)
    }
}
