import CoreGraphics
import Foundation

/// Synthetic images and pixel readers for tests.
enum TestImages {
    static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Solid image of the given pixel size.
    static func solid(width: Int, height: Int, gray: CGFloat = 1, colorSpace: CGColorSpace = srgb) -> CGImage {
        let ctx = context(width: width, height: height, colorSpace: colorSpace)
        ctx.setFillColor(CGColor(colorSpace: colorSpace, components: [gray, gray, gray, 1])!)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    /// Deterministic per-pixel gray noise (high local variance).
    static func noise(width: Int, height: Int, seed: UInt64 = 42) -> CGImage {
        var state = seed
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for index in 0..<(width * height) {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let value = UInt8(truncatingIfNeeded: state >> 56)
            bytes[index * 4] = value
            bytes[index * 4 + 1] = value
            bytes[index * 4 + 2] = value
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: srgb, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }

    static func context(width: Int, height: Int, colorSpace: CGColorSpace = srgb) -> CGContext {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
    }
}

/// RGBA8 sRGB copy of an image; `pixel(x:row:)` uses a TOP-LEFT origin (row 0 = top).
struct PixelBuffer {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init(_ image: CGImage) {
        width = image.width
        height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        data.withUnsafeMutableBytes { raw in
            let ctx = CGContext(
                data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: TestImages.srgb,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            ctx.interpolationQuality = .none
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        bytes = data
    }

    func pixel(x: Int, row: Int) -> (r: Int, g: Int, b: Int) {
        let offset = (row * width + x) * 4
        return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
    }

    func isRed(x: Int, row: Int) -> Bool {
        let p = pixel(x: x, row: row)
        return p.r > 200 && p.g < 90 && p.b < 90
    }

    func isWhite(x: Int, row: Int) -> Bool {
        let p = pixel(x: x, row: row)
        return p.r > 245 && p.g > 245 && p.b > 245
    }

    /// Variance of the luma over a TOP-LEFT pixel rect.
    func lumaVariance(in rect: CGRect) -> Double {
        var values: [Double] = []
        for row in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                let p = pixel(x: x, row: row)
                values.append(0.299 * Double(p.r) + 0.587 * Double(p.g) + 0.114 * Double(p.b))
            }
        }
        let mean = values.reduce(0, +) / Double(values.count)
        return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
    }
}
