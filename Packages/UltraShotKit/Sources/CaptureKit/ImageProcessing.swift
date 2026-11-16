import CoreGraphics

/// Pixel-level image transforms. All functions return nil when a bitmap context cannot be made.
public enum ImageProcessing {
    /// Shrinks the image by `factor` (2 turns a Retina image into 1x), keeping its color space.
    /// Pixel sizes are rounded and never drop below 1. A factor ≤ 1 returns the image unchanged.
    public static func downscale(_ image: CGImage, factor: CGFloat) -> CGImage? {
        guard factor > 1 else { return image }
        let width = max(1, Int((CGFloat(image.width) / factor).rounded()))
        let height = max(1, Int((CGFloat(image.height) / factor).rounded()))
        return redraw(image, width: width, height: height, colorSpace: outputColorSpace(of: image))
    }

    /// Converts the image to sRGB. Returns the image unchanged when it already is sRGB.
    public static func convertToSRGB(_ image: CGImage) -> CGImage? {
        if image.colorSpace?.name == CGColorSpace.sRGB { return image }
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return redraw(image, width: image.width, height: image.height, colorSpace: srgb)
    }

    /// Composites the image over an opaque background color (white by default), removing alpha.
    /// Returns the image unchanged when it has no alpha channel.
    public static func flattened(_ image: CGImage, background: CGColor? = nil) -> CGImage? {
        guard hasAlpha(image) else { return image }
        let space = outputColorSpace(of: image)
        let fill = background ?? CGColor(gray: 1, alpha: 1)
        guard let context = makeContext(width: image.width, height: image.height, colorSpace: space,
                                        alphaInfo: .noneSkipLast) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(fill)
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }

    /// Whether the image carries an alpha channel.
    public static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
    }

    // MARK: - Private

    private static func redraw(_ image: CGImage, width: Int, height: Int, colorSpace: CGColorSpace) -> CGImage? {
        guard let context = makeContext(width: width, height: height, colorSpace: colorSpace,
                                        alphaInfo: .premultipliedLast) else { return nil }
        context.interpolationQuality = .high
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func makeContext(width: Int, height: Int, colorSpace: CGColorSpace,
                                    alphaInfo: CGImageAlphaInfo) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: colorSpace, bitmapInfo: alphaInfo.rawValue)
    }

    /// The image's own RGB color space when it can back a bitmap context, otherwise sRGB.
    private static func outputColorSpace(of image: CGImage) -> CGColorSpace {
        if let own = image.colorSpace, own.model == .rgb, own.supportsOutput { return own }
        return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }
}
