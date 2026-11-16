@testable import CaptureKit
import CoreGraphics
import Foundation
import ImageIO
import Testing

struct ImageEncoderTests {
    private func properties(_ data: Data) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    private func decode(_ data: Data) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    @Test func pngRoundTripKeepsSizeProfileAndDPI() throws {
        let image = TestImages.solid(width: 64, height: 48, colorSpace: TestImages.displayP3)
        let data = try ImageEncoder.data(for: image, format: .png, scale: 2)
        let decoded = try decode(data)
        #expect(decoded.width == 64 && decoded.height == 48)
        let props = try properties(data)
        #expect((props[kCGImagePropertyDPIWidth] as? Double) == 144)
        #expect((props[kCGImagePropertyDPIHeight] as? Double) == 144)
        #expect(props[kCGImagePropertyProfileName] as? String == "Display P3")
        let iccData = try #require(decoded.colorSpace?.copyICCData() as Data?)
        #expect(!iccData.isEmpty)
        #expect(decoded.colorSpace?.name == CGColorSpace.displayP3)
    }

    @Test func pngKeepsAlpha() throws {
        let image = TestImages.solid(width: 8, height: 8, rgba: [1, 0, 0, 0])
        let decoded = try decode(try ImageEncoder.data(for: image, format: .png))
        #expect(ImageProcessing.hasAlpha(decoded))
        #expect(TestImages.pixel(decoded, x: 4, y: 4)[3] == 0)
    }

    @Test func scaleOneIs72DPI() throws {
        let data = try ImageEncoder.data(for: TestImages.solid(width: 4, height: 4), format: .png, scale: 1)
        #expect((try properties(data)[kCGImagePropertyDPIWidth] as? Double) == 72)
    }

    @Test func jpegQualityIsHonored() throws {
        let image = TestImages.noise(width: 256, height: 256)
        let low = try ImageEncoder.data(for: image, format: .jpeg(quality: 0.1), scale: 2)
        let high = try ImageEncoder.data(for: image, format: .jpeg(quality: 0.95), scale: 2)
        #expect(low.count * 2 < high.count)
        let props = try properties(high)
        #expect((props[kCGImagePropertyDPIWidth] as? Double) == 144)
        let decoded = try decode(high)
        #expect(decoded.width == 256 && decoded.height == 256)
    }

    @Test func jpegFlattensTransparencyOverWhite() throws {
        let image = TestImages.solid(width: 16, height: 16, colorSpace: TestImages.sRGB, rgba: [0, 0, 0, 0])
        let decoded = try decode(try ImageEncoder.data(for: image, format: .jpeg(quality: 1)))
        let pixel = TestImages.pixel(decoded, x: 8, y: 8)
        #expect(pixel[0] > 245 && pixel[1] > 245 && pixel[2] > 245)
    }

    @Test func writeCreatesFileInTemp() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("capturekit-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try ImageEncoder.write(TestImages.solid(width: 10, height: 10), to: url, format: .png, scale: 2)
        let decoded = try decode(try Data(contentsOf: url))
        #expect(decoded.width == 10)
    }

    @Test func writeToMissingDirectoryThrows() {
        let url = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/x.png")
        #expect(throws: CaptureError.self) {
            try ImageEncoder.write(TestImages.solid(width: 2, height: 2), to: url, format: .png)
        }
    }

    @Test func formatMetadata() {
        #expect(ImageEncoder.Format.png.fileExtension == "png")
        #expect(ImageEncoder.Format.jpeg(quality: 0.8).fileExtension == "jpg")
        #expect(ImageEncoder.Format.jpeg(quality: 0.8).utType == .jpeg)
    }
}

struct ImageProcessingTests {
    @Test func downscaleHalvesPixelSize() throws {
        let image = TestImages.solid(width: 3600, height: 2338)
        let small = try #require(ImageProcessing.downscale(image, factor: 2))
        #expect(small.width == 1800 && small.height == 1169)
        #expect(small.colorSpace?.name == CGColorSpace.displayP3)
    }

    @Test func downscaleFactorOneIsIdentity() throws {
        let image = TestImages.solid(width: 10, height: 10)
        let same = try #require(ImageProcessing.downscale(image, factor: 1))
        #expect(same === image)
    }

    @Test func convertToSRGBChangesColorSpaceKeepsSize() throws {
        let image = TestImages.solid(width: 20, height: 10, colorSpace: TestImages.displayP3)
        let converted = try #require(ImageProcessing.convertToSRGB(image))
        #expect(converted.colorSpace?.name == CGColorSpace.sRGB)
        #expect(converted.width == 20 && converted.height == 10)
        let already = TestImages.solid(width: 2, height: 2, colorSpace: TestImages.sRGB)
        let unchanged = try #require(ImageProcessing.convertToSRGB(already))
        #expect(unchanged === already)
    }

    @Test func flattenedRemovesAlpha() throws {
        let image = TestImages.solid(width: 4, height: 4, rgba: [0, 0, 0, 0])
        let flat = try #require(ImageProcessing.flattened(image))
        #expect(!ImageProcessing.hasAlpha(flat))
        #expect(TestImages.pixel(flat, x: 1, y: 1) == [255, 255, 255, 255])
    }
}
