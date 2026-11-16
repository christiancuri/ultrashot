import CoreGraphics
import Foundation

/// Synthetic images for tests. Nothing here touches the real screen.
enum TestImages {
    static let displayP3 = CGColorSpace(name: CGColorSpace.displayP3)!
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// A solid image. `rgba` components are in 0...1, drawn in `colorSpace`.
    static func solid(width: Int, height: Int, colorSpace: CGColorSpace = displayP3,
                      rgba: [CGFloat] = [0.2, 0.4, 0.8, 1]) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(colorSpace: colorSpace, components: rgba)!)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// A noisy image so JPEG size depends on quality.
    static func noise(width: Int, height: Int) -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        var seed: UInt32 = 12_345
        for index in stride(from: 0, to: bytes.count, by: 4) {
            for channel in 0..<3 {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                bytes[index + channel] = UInt8(truncatingIfNeeded: seed >> 24)
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: sRGB,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    /// Reads one pixel (top-left origin) as RGBA8 in sRGB.
    static func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: 4)
        buffer.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        }
        return buffer
    }
}
