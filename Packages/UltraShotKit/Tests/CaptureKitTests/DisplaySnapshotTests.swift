@testable import CaptureKit
import CoreGraphics
import Testing

struct DisplaySnapshotTests {
    /// A 200×100 pt display at 2x whose image is red on the top half (pixel rows 0..<100)
    /// and blue on the bottom half.
    private func retinaSnapshot(frame: CGRect = CGRect(x: 0, y: 0, width: 200, height: 100)) -> DisplaySnapshot {
        let width = Int(frame.width * 2), height = Int(frame.height * 2)
        let space = TestImages.sRGB
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2)) // CG bottom = image bottom
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: height / 2, width: width, height: height / 2))
        return DisplaySnapshot(displayID: 1, frame: frame, scale: 2, image: context.makeImage()!)
    }

    @Test func cropLocalRectAtScale2() throws {
        let snapshot = retinaSnapshot()
        // Top-left 50×25 pt in AppKit terms: y from 75 to 100.
        let image = try #require(snapshot.crop(toLocalRect: CGRect(x: 0, y: 75, width: 50, height: 25)))
        #expect(image.width == 100 && image.height == 50)
        #expect(TestImages.pixel(image, x: 10, y: 10) == [255, 0, 0, 255])
        #expect(snapshot.pixelRect(forLocalRect: CGRect(x: 0, y: 75, width: 50, height: 25))
                    == CGRect(x: 0, y: 0, width: 100, height: 50))
    }

    @Test func cropBottomHalfIsBlue() throws {
        let snapshot = retinaSnapshot()
        let image = try #require(snapshot.crop(toLocalRect: CGRect(x: 10, y: 0, width: 20, height: 10)))
        #expect(image.width == 40 && image.height == 20)
        #expect(TestImages.pixel(image, x: 5, y: 5) == [0, 0, 255, 255])
    }

    @Test func cropAtScale1() throws {
        let image = TestImages.solid(width: 2560, height: 1440)
        let snapshot = DisplaySnapshot(displayID: 2, frame: MixedLayout.right, scale: 1, image: image)
        #expect(snapshot.pixelRect(forLocalRect: CGRect(x: 100, y: 71, width: 100, height: 50))
                    == CGRect(x: 100, y: 1319, width: 100, height: 50))
        let cropped = try #require(snapshot.crop(toAppKitRect: CGRect(x: 1900, y: -200, width: 100, height: 50)))
        #expect(cropped.width == 100 && cropped.height == 50)
    }

    @Test func cropAppKitRectOnNegativeOriginDisplay() throws {
        let image = TestImages.solid(width: 1920, height: 1080)
        let snapshot = DisplaySnapshot(displayID: 3, frame: MixedLayout.aboveLeft, scale: 1, image: image)
        // 10×10 pt near the display's bottom-left corner.
        #expect(snapshot.pixelRect(forLocalRect: CGRect(x: 20, y: 31, width: 10, height: 10))
                    == CGRect(x: 20, y: 1039, width: 10, height: 10))
        let cropped = try #require(snapshot.crop(toAppKitRect: CGRect(x: -1900, y: 1200, width: 10, height: 10)))
        #expect(cropped.width == 10 && cropped.height == 10)
    }

    @Test func cropClampsToDisplay() throws {
        let snapshot = retinaSnapshot(frame: CGRect(x: 1800, y: 0, width: 200, height: 100))
        // Starts 50 pt left of the display (on another screen) and runs past its top.
        let image = try #require(snapshot.crop(toAppKitRect: CGRect(x: 1750, y: 50, width: 100, height: 100)))
        #expect(image.width == 100 && image.height == 100) // 50×50 pt on-display at 2x
    }

    @Test func cropUsesImagePixelRatioNotBackingScale() throws {
        // A 1800×1169 pt display reported at 2x whose image is 3024×1964 px (native panel).
        let image = TestImages.solid(width: 3024, height: 1964)
        let snapshot = DisplaySnapshot(displayID: 4, frame: CGRect(x: 0, y: 0, width: 1800, height: 1169), scale: 2, image: image)
        #expect(snapshot.pixelsPerPoint == CGSize(width: 3024.0 / 1800.0, height: 1964.0 / 1169.0))
        // The whole display maps to the whole image, not to a 3600×2338 rect clamped to it.
        #expect(snapshot.pixelRect(forLocalRect: CGRect(x: 0, y: 0, width: 1800, height: 1169))
                    == CGRect(x: 0, y: 0, width: 3024, height: 1964))
        // The right half starts at the image's horizontal middle.
        let half = try #require(snapshot.pixelRect(forLocalRect: CGRect(x: 900, y: 0, width: 900, height: 1169)))
        #expect(half.minX == 1512 && half.width == 1512)
    }

    @Test func cropOutsideDisplayIsNil() {
        let snapshot = retinaSnapshot()
        #expect(snapshot.crop(toAppKitRect: CGRect(x: 500, y: 500, width: 10, height: 10)) == nil)
        #expect(snapshot.crop(toLocalRect: CGRect(x: 10, y: 10, width: 0, height: 10)) == nil)
    }
}
