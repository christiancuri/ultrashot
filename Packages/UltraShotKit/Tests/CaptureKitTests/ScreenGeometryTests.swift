@testable import CaptureKit
import CoreGraphics
import Testing

/// Layout used throughout: a 1800×1169 @2x primary (laptop), a 2560×1440 @1x external to its right
/// (top edges aligned), and a 1920×1080 @1x display above-left with a negative origin.
enum MixedLayout {
    static let primaryHeight: CGFloat = 1169
    static let primary = CGRect(x: 0, y: 0, width: 1800, height: 1169)
    static let right = CGRect(x: 1800, y: -271, width: 2560, height: 1440)
    static let aboveLeft = CGRect(x: -1920, y: 1169, width: 1920, height: 1080)
}

struct ScreenGeometryTests {
    @Test func primaryDisplayMapsToOrigin() {
        let cg = ScreenGeometry.appKitToCG(MixedLayout.primary, primaryScreenHeight: MixedLayout.primaryHeight)
        #expect(cg == CGRect(x: 0, y: 0, width: 1800, height: 1169))
    }

    @Test func externalRightTopAlignedHasZeroCGY() {
        let cg = ScreenGeometry.appKitToCG(MixedLayout.right, primaryScreenHeight: MixedLayout.primaryHeight)
        #expect(cg == CGRect(x: 1800, y: 0, width: 2560, height: 1440))
    }

    @Test func aboveLeftDisplayHasNegativeCGOrigin() {
        let cg = ScreenGeometry.appKitToCG(MixedLayout.aboveLeft, primaryScreenHeight: MixedLayout.primaryHeight)
        #expect(cg == CGRect(x: -1920, y: -1080, width: 1920, height: 1080))
    }

    @Test(arguments: [MixedLayout.primary, MixedLayout.right, MixedLayout.aboveLeft,
                      CGRect(x: 123.5, y: -40.25, width: 10, height: 7.5)])
    func rectRoundTrips(_ rect: CGRect) {
        let height = MixedLayout.primaryHeight
        let back = ScreenGeometry.cgToAppKit(ScreenGeometry.appKitToCG(rect, primaryScreenHeight: height),
                                             primaryScreenHeight: height)
        #expect(back == rect)
    }

    @Test func pointConversion() {
        let height = MixedLayout.primaryHeight
        // Top-left corner of the primary in AppKit is (0, 1169) -> CG (0, 0).
        #expect(ScreenGeometry.appKitToCG(CGPoint(x: 0, y: 1169), primaryScreenHeight: height) == .zero)
        // A point on the above-left display.
        let appKit = CGPoint(x: -100, y: 2000)
        let cg = ScreenGeometry.appKitToCG(appKit, primaryScreenHeight: height)
        #expect(cg == CGPoint(x: -100, y: -831))
        #expect(ScreenGeometry.cgToAppKit(cg, primaryScreenHeight: height) == appKit)
    }

    @Test func windowRectSpanningTwoDisplays() {
        // A selection crossing from the primary onto the external display.
        let appKit = CGRect(x: 1700, y: 900, width: 300, height: 200)
        let cg = ScreenGeometry.appKitToCG(appKit, primaryScreenHeight: MixedLayout.primaryHeight)
        #expect(cg == CGRect(x: 1700, y: 69, width: 300, height: 200))
        #expect(cg.intersects(CGRect(x: 1800, y: 0, width: 2560, height: 1440)))
    }

    @Test func localRectForEachDisplay() {
        let appKit = CGRect(x: 1900, y: -200, width: 100, height: 50)
        let local = ScreenGeometry.localRect(forAppKitRect: appKit, displayFrame: MixedLayout.right)
        #expect(local == CGRect(x: 100, y: 71, width: 100, height: 50))
        let onAbove = ScreenGeometry.localRect(forAppKitRect: CGRect(x: -1900, y: 1200, width: 10, height: 10),
                                               displayFrame: MixedLayout.aboveLeft)
        #expect(onAbove == CGRect(x: 20, y: 31, width: 10, height: 10))
    }

    @Test func pixelRectAtScale2FlipsY() {
        // 100×50 pt rect whose bottom edge is 10 pt above the bottom of a 1800×1169 display.
        let pixels = ScreenGeometry.pixelRect(forLocalRect: CGRect(x: 20, y: 10, width: 100, height: 50),
                                              displaySize: CGSize(width: 1800, height: 1169), scale: 2)
        #expect(pixels == CGRect(x: 40, y: (1169 - 60) * 2, width: 200, height: 100))
    }

    @Test func pixelRectAtScale1() {
        let pixels = ScreenGeometry.pixelRect(forLocalRect: CGRect(x: 100, y: 71, width: 100, height: 50),
                                              displaySize: CGSize(width: 2560, height: 1440), scale: 1)
        #expect(pixels == CGRect(x: 100, y: 1440 - 121, width: 100, height: 50))
    }

    @Test func pixelRectRoundsFractionalPoints() {
        let pixels = ScreenGeometry.pixelRect(forLocalRect: CGRect(x: 10.3, y: 0, width: 5.4, height: 1),
                                              displaySize: CGSize(width: 100, height: 100), scale: 2)
        // 20.6 -> 21, 31.4 -> 31
        #expect(pixels == CGRect(x: 21, y: 198, width: 10, height: 2))
    }

    @Test func pixelRectStandardizesNegativeSizes() {
        let pixels = ScreenGeometry.pixelRect(forLocalRect: CGRect(x: 30, y: 30, width: -10, height: -10),
                                              displaySize: CGSize(width: 100, height: 100), scale: 1)
        #expect(pixels == CGRect(x: 20, y: 70, width: 10, height: 10))
    }
}
