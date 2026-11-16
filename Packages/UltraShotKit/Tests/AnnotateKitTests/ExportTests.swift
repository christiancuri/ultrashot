@testable import AnnotateKit
import CoreGraphics
import Foundation
import Testing

struct ExportTests {
    private let redRect = Annotation(
        kind: .rectangle(CGRect(x: 20, y: 10, width: 60, height: 40)),
        style: Annotation.Style(color: RGBAColor(red: 1, green: 0, blue: 0), lineWidth: 4)
    )

    @Test(arguments: [1, 2])
    func outputMatchesBasePixelSize(scale: Int) throws {
        let base = TestImages.solid(width: 200 * scale, height: 100 * scale)
        let output = try #require(AnnotationRenderer.export(base: base, scale: CGFloat(scale), annotations: [redRect]))
        #expect(output.width == base.width)
        #expect(output.height == base.height)
    }

    /// Canvas y=10 (bottom edge of the rect) must land near the BOTTOM of the image:
    /// top-left pixel row = (canvasHeight - y) * scale. Its mirror must stay white.
    @Test(arguments: [1, 2])
    func strokeLandsAtCanvasLocation(scale: Int) throws {
        let base = TestImages.solid(width: 200 * scale, height: 100 * scale)
        let output = try #require(AnnotationRenderer.export(base: base, scale: CGFloat(scale), annotations: [redRect]))
        let pixels = PixelBuffer(output)
        let s = scale
        // Bottom edge (canvas y = 10) → row (100 - 10) * s, column x = 50.
        #expect(pixels.isRed(x: 50 * s, row: 90 * s - 1))
        // Top edge (canvas y = 50) → row 50 * s.
        #expect(pixels.isRed(x: 50 * s, row: 50 * s))
        // Left edge (canvas x = 20) at mid height (canvas y = 30 → row 70 * s).
        #expect(pixels.isRed(x: 20 * s, row: 70 * s))
        // Mirror of the bottom edge (canvas y = 90) is untouched: no flipped Y.
        #expect(pixels.isWhite(x: 50 * s, row: 10 * s))
        // Interior stays white.
        #expect(pixels.isWhite(x: 50 * s, row: 70 * s))
    }

    @Test func cropKeepsAnnotationsInBaseCanvas() throws {
        // Base: 200x100 pt at 2x. Crop the canvas rect (10, 0, 100, 60) → 200x120 px.
        let base = TestImages.solid(width: 400, height: 200)
        let canvasCrop = CGRect(x: 10, y: 0, width: 100, height: 60)
        let cropPixels = CanvasGeometry.pixelRect(forCanvasRect: canvasCrop, canvasSize: CGSize(width: 200, height: 100), scale: 2)
        #expect(cropPixels == CGRect(x: 20, y: 80, width: 200, height: 120))

        let output = try #require(AnnotationRenderer.export(base: base, scale: 2, cropPixelRect: cropPixels, annotations: [redRect]))
        #expect(output.width == 200)
        #expect(output.height == 120)
        let pixels = PixelBuffer(output)
        // Rect bottom edge: canvas (50, 10) → crop-local canvas (40, 10) → row (60 - 10) * 2.
        #expect(pixels.isRed(x: 80, row: 99))
        // Rect top edge: canvas y = 50 → row (60 - 50) * 2 = 20.
        #expect(pixels.isRed(x: 80, row: 20))
        #expect(pixels.isWhite(x: 80, row: 60))
    }

    @Test func emptyOrOutsideCropFails() {
        let base = TestImages.solid(width: 100, height: 100)
        #expect(AnnotationRenderer.export(base: base, scale: 1, cropPixelRect: CGRect(x: 200, y: 200, width: 10, height: 10), annotations: []) == nil)
        #expect(AnnotationRenderer.export(base: base, scale: 1, cropPixelRect: .zero, annotations: []) == nil)
    }

    @Test(arguments: [1, 2])
    func blurDestroysDetail(scale: Int) throws {
        let base = TestImages.noise(width: 200 * scale, height: 120 * scale)
        let blur = Annotation(kind: .blur(CGRect(x: 40, y: 20, width: 96, height: 72)))
        let output = try #require(AnnotationRenderer.export(base: base, scale: CGFloat(scale), annotations: [blur]))
        // Canvas rect (40, 20, 96, 72) → top-left pixel rect (40, 120 - 92, 96, 72) × scale.
        let region = CGRect(x: 40 * scale, y: 28 * scale, width: 96 * scale, height: 72 * scale)
        let before = PixelBuffer(base).lumaVariance(in: region)
        let after = PixelBuffer(output).lumaVariance(in: region)
        #expect(before > 1000)
        #expect(after < before * 0.1, "variance \(before) → \(after)")
        // Outside the region the noise is untouched.
        let outside = CGRect(x: 0, y: 0, width: 30 * scale, height: 20 * scale)
        #expect(abs(PixelBuffer(output).lumaVariance(in: outside) - PixelBuffer(base).lumaVariance(in: outside)) < 1)
    }

    @Test func preservesDisplayP3ColorSpace() throws {
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let base = TestImages.solid(width: 120, height: 80, colorSpace: p3)
        let blur = Annotation(kind: .blur(CGRect(x: 10, y: 10, width: 40, height: 30)))
        let output = try #require(AnnotationRenderer.export(base: base, scale: 2, annotations: [redRect, blur]))
        #expect(output.colorSpace?.name == CGColorSpace.displayP3)
    }

    @Test func preservesSRGBAndUntouchedPixels() throws {
        let base = TestImages.noise(width: 64, height: 64)
        let output = try #require(AnnotationRenderer.export(base: base, scale: 1, annotations: []))
        #expect(output.colorSpace?.name == CGColorSpace.sRGB)
        let a = PixelBuffer(base), b = PixelBuffer(output)
        for (x, row) in [(0, 0), (13, 40), (63, 63)] {
            #expect(a.pixel(x: x, row: row) == b.pixel(x: x, row: row))
        }
    }

    @Test func keeps16BitDepth() throws {
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let ctx = try #require(CGContext(
            data: nil, width: 40, height: 30, bitsPerComponent: 16, bytesPerRow: 0, space: p3,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        let base = try #require(ctx.makeImage())
        let output = try #require(AnnotationRenderer.export(base: base, scale: 1, annotations: [redRect]))
        #expect(output.bitsPerComponent == 16)
        #expect(output.colorSpace?.name == CGColorSpace.displayP3)
    }

    @Test func pixelateIsFastEnoughForLiveDrawing() throws {
        let base = TestImages.noise(width: 2880, height: 1800)
        let canvas = CGSize(width: 1440, height: 900)
        let ctx = TestImages.context(width: 2880, height: 1800)
        ctx.scaleBy(x: 2, y: 2)
        let blur = Annotation(kind: .blur(CGRect(x: 100, y: 100, width: 600, height: 400)))
        AnnotationRenderer.draw([blur], in: ctx, canvasSize: canvas, baseImage: base, scale: 2) // warm-up
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for _ in 0..<10 {
                AnnotationRenderer.draw([blur], in: ctx, canvasSize: canvas, baseImage: base, scale: 2)
            }
        }
        print("pixelate 1200x800 px region: \(elapsed / 10) per draw")
        #expect(elapsed / 10 < .milliseconds(100))
    }
}
