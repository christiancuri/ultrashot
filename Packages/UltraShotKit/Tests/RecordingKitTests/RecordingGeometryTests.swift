import CoreGraphics
@testable import RecordingKit
import Testing

@Suite("RecordingGeometry")
struct RecordingGeometryTests {
    // Primary 1728×1117 at the origin; a secondary 1920×1080 to its right, bottoms aligned
    // 200 pt higher (AppKit y up), and one above the primary.
    private let primary = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    private let secondary = CGRect(x: 1728, y: 200, width: 1920, height: 1080)
    private let above = CGRect(x: -300, y: 1117, width: 2560, height: 1440)

    // MARK: sourceRect

    @Test func sourceRectFlipsWithinTheScreen() {
        let local = CGRect(x: 100, y: 50, width: 400, height: 300) // bottom-left based
        #expect(RecordingGeometry.displaySourceRect(fromLocal: local, screenHeight: primary.height)
            == CGRect(x: 100, y: 767, width: 400, height: 300))
        // Same local rect on the secondary: only its own height matters, not its global origin.
        #expect(RecordingGeometry.displaySourceRect(fromLocal: local, screenHeight: secondary.height)
            == CGRect(x: 100, y: 730, width: 400, height: 300))
    }

    @Test func sourceRectOfFullScreenIsTheWholeDisplay() {
        let local = CGRect(origin: .zero, size: secondary.size)
        #expect(RecordingGeometry.displaySourceRect(fromLocal: local, screenHeight: secondary.height)
            == CGRect(origin: .zero, size: secondary.size))
    }

    @Test func sourceRectStandardizesNegativeSizes() {
        let local = CGRect(x: 500, y: 400, width: -400, height: -300)
        #expect(RecordingGeometry.displaySourceRect(fromLocal: local, screenHeight: 1000)
            == CGRect(x: 100, y: 600, width: 400, height: 300))
    }

    // MARK: Global conversions

    @Test func globalTopLeftRoundTripsOnEveryScreen() {
        let local = CGRect(x: 10, y: 20, width: 300, height: 200)
        for frame in [primary, secondary, above] {
            let global = RecordingGeometry.globalTopLeftRect(fromLocal: local, screenFrame: frame, primaryScreenHeight: primary.height)
            #expect(RecordingGeometry.localRect(fromGlobalTopLeft: global, screenFrame: frame, primaryScreenHeight: primary.height) == local)
        }
    }

    @Test func globalTopLeftValues() {
        let local = CGRect(x: 10, y: 20, width: 300, height: 200)
        #expect(RecordingGeometry.globalTopLeftRect(fromLocal: local, screenFrame: primary, primaryScreenHeight: primary.height)
            == CGRect(x: 10, y: 897, width: 300, height: 200))
        // Secondary: x shifts by 1728; AppKit maxY = 200 + 220 = 420 → CG y = 1117 − 420 = 697.
        #expect(RecordingGeometry.globalTopLeftRect(fromLocal: local, screenFrame: secondary, primaryScreenHeight: primary.height)
            == CGRect(x: 1738, y: 697, width: 300, height: 200))
        // Screen above the primary has negative CG y.
        #expect(RecordingGeometry.globalTopLeftRect(fromLocal: local, screenFrame: above, primaryScreenHeight: primary.height)
            == CGRect(x: -290, y: -220, width: 300, height: 200))
    }

    @Test func globalPointConversion() {
        #expect(RecordingGeometry.globalTopLeftPoint(fromLocal: CGPoint(x: 5, y: 7), screenFrame: secondary, primaryScreenHeight: primary.height)
            == CGPoint(x: 1733, y: 910))
    }

    // MARK: Panel placement

    private let panel = CGSize(width: 300, height: 80)
    private let bounds = CGRect(x: 0, y: 0, width: 1728, height: 1117)

    @Test func panelGoesBelowWhenThereIsRoom() {
        let placement = RecordingGeometry.place(panel, near: CGRect(x: 400, y: 400, width: 500, height: 300), in: bounds)
        #expect(placement.side == .below)
        #expect(placement.frame == CGRect(x: 500, y: 310, width: 300, height: 80))
    }

    @Test func panelFlipsAboveAtTheBottomEdge() {
        let placement = RecordingGeometry.place(panel, near: CGRect(x: 400, y: 30, width: 500, height: 300), in: bounds)
        #expect(placement.side == .above)
        #expect(placement.frame.minY == 340)
    }

    @Test func panelGoesInsideWhenSelectionFillsTheHeight() {
        let placement = RecordingGeometry.place(panel, near: bounds, in: bounds)
        #expect(placement.side == .inside)
        #expect(placement.frame == CGRect(x: 714, y: 10, width: 300, height: 80))
    }

    @Test func panelIsClampedHorizontally() {
        let left = RecordingGeometry.place(panel, near: CGRect(x: 0, y: 500, width: 40, height: 40), in: bounds)
        #expect(left.frame.minX == 8)
        let right = RecordingGeometry.place(panel, near: CGRect(x: 1700, y: 500, width: 28, height: 40), in: bounds)
        #expect(right.frame.maxX == 1720)
    }

    @Test func panelStaysInsideBoundsWithOffsetOrigin() {
        let screen = CGRect(x: 1728, y: 200, width: 1920, height: 1080)
        let placement = RecordingGeometry.place(panel, near: CGRect(x: 1728, y: 210, width: 100, height: 100), in: screen)
        #expect(placement.side == .above)
        #expect(placement.frame.minX == 1736)
        #expect(screen.contains(placement.frame))
    }

    @Test func panelWithoutAnchorSitsBottomCenter() {
        #expect(RecordingGeometry.placeWithoutAnchor(panel, in: bounds) == CGRect(x: 714, y: 80, width: 300, height: 80))
    }

    // MARK: Numeric size entry

    @Test func resizeKeepsTopLeftCorner() {
        let current = CGRect(x: 100, y: 500, width: 400, height: 300) // top = 800
        let resized = RecordingGeometry.resized(current, to: CGSize(width: 640, height: 360), in: bounds)
        #expect(resized == CGRect(x: 100, y: 440, width: 640, height: 360))
    }

    @Test func resizeShiftsBackInsideBounds() {
        let current = CGRect(x: 1500, y: 100, width: 200, height: 200) // top = 300
        let resized = RecordingGeometry.resized(current, to: CGSize(width: 600, height: 500), in: bounds)
        #expect(resized == CGRect(x: 1128, y: 0, width: 600, height: 500))
    }

    @Test func resizeClampsToBoundsAndMinimum() {
        let current = CGRect(x: 100, y: 100, width: 200, height: 200)
        #expect(RecordingGeometry.resized(current, to: CGSize(width: 5000, height: 9999), in: bounds) == bounds)
        let tiny = RecordingGeometry.resized(current, to: CGSize(width: 0, height: -20), in: bounds)
        #expect(tiny.size == CGSize(width: 4, height: 4))
        #expect(RecordingGeometry.resized(current, to: CGSize(width: CGFloat.nan, height: 10), in: bounds).width == 4)
    }

    @Test func resizeRoundsToWholePoints() {
        let resized = RecordingGeometry.resized(CGRect(x: 0, y: 0, width: 10, height: 10), to: CGSize(width: 99.6, height: 50.2), in: bounds)
        #expect(resized.size == CGSize(width: 100, height: 50))
    }

    @Test func resizeWithoutSelectionCenters() {
        #expect(RecordingGeometry.resized(nil, to: CGSize(width: 800, height: 600), in: bounds)
            == CGRect(x: 464, y: 258.5, width: 800, height: 600))
    }

    @Test func fullscreenDetection() {
        #expect(RecordingGeometry.isFullscreen(bounds, in: bounds))
        #expect(RecordingGeometry.isFullscreen(bounds.insetBy(dx: 0.2, dy: 0.2), in: bounds))
        #expect(!RecordingGeometry.isFullscreen(bounds.insetBy(dx: 2, dy: 0), in: bounds))
    }

    @Test(arguments: [(0.0, "00:00"), (9.99, "00:09"), (65, "01:05"), (3599, "59:59"), (3600, "1:00:00"), (-3, "00:00"), (.nan, "00:00")])
    func elapsedText(seconds: Double, expected: String) {
        #expect(RecordingGeometry.elapsedText(seconds) == expected)
    }
}
