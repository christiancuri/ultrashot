@testable import CaptureKit
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

struct PasteboardImageTests {
    private func source(_ data: Data) throws -> CGImageSource {
        try #require(CGImageSourceCreateWithData(data as CFData, nil))
    }

    private func properties(_ data: Data) throws -> [CFString: Any] {
        try #require(CGImageSourceCopyPropertiesAtIndex(try source(data), 0, nil) as? [CFString: Any])
    }

    private func decode(_ data: Data) throws -> CGImage {
        try #require(CGImageSourceCreateImageAtIndex(try source(data), 0, nil))
    }

    @Test func pngFileIsUsedAsIsAndGetsATIFF() throws {
        let file = try ImageEncoder.data(for: TestImages.solid(width: 40, height: 30), format: .png, scale: 2)
        let image = try PasteboardImage(fileData: file)
        #expect(image.png == file)
        #expect(CGImageSourceGetType(try source(image.tiff)) as String? == UTType.tiff.identifier)
        let tiff = try decode(image.tiff)
        #expect(tiff.width == 40 && tiff.height == 30)
        #expect((try properties(image.tiff)[kCGImagePropertyDPIWidth] as? Double) == 144)
        #expect(tiff.colorSpace?.name == CGColorSpace.displayP3)
    }

    @Test func jpegFileIsConvertedToPNGAndTIFF() throws {
        let file = try ImageEncoder.data(for: TestImages.noise(width: 24, height: 16), format: .jpeg(quality: 0.8), scale: 2)
        let image = try PasteboardImage(fileData: file)
        #expect(CGImageSourceGetType(try source(image.png)) as String? == UTType.png.identifier)
        #expect(CGImageSourceGetType(try source(image.tiff)) as String? == UTType.tiff.identifier)
        for data in [image.png, image.tiff] {
            let decoded = try decode(data)
            #expect(decoded.width == 24 && decoded.height == 16)
            #expect((try properties(data)[kCGImagePropertyDPIWidth] as? Double) == 144)
        }
    }

    @Test func garbageThrows() {
        #expect(throws: (any Error).self) { try PasteboardImage(fileData: Data("not an image".utf8)) }
        #expect(throws: (any Error).self) { try PasteboardImage(fileData: Data()) }
    }
}
