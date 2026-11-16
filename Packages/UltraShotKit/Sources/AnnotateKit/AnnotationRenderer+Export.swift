import CoreGraphics

extension AnnotationRenderer {
    /// Draws `base` and `annotations` at the base image's full pixel resolution.
    ///
    /// - Parameters:
    ///   - base: the full base image (annotations are in its canvas: pixel size / scale).
    ///   - scale: base pixels per canvas point (2 for a Retina capture).
    ///   - cropPixelRect: optional crop in base PIXELS, TOP-LEFT origin (the
    ///     `CGImage.cropping(to:)` convention). It is rounded outward to whole pixels and
    ///     clipped to the image. Build it with `CanvasGeometry.pixelRect(forCanvasRect:...)`.
    /// - Returns: an image of the crop's (or base's) pixel size in the base's RGB color space
    ///   (sRGB when the base is not RGB), or nil when the crop is empty or a context fails.
    public static func export(
        base: CGImage,
        scale: CGFloat,
        cropPixelRect: CGRect? = nil,
        annotations: [Annotation]
    ) -> CGImage? {
        guard scale > 0, base.width > 0, base.height > 0 else { return nil }
        let full = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        let crop = (cropPixelRect?.standardized.integral ?? full).intersection(full)
        guard !crop.isNull, crop.width >= 1, crop.height >= 1 else { return nil }
        guard let ctx = makeContext(width: Int(crop.width), height: Int(crop.height), matching: base) else {
            return nil
        }

        let canvasSize = CGSize(width: CGFloat(base.width) / scale, height: CGFloat(base.height) / scale)
        // Pixel space is bottom-left in a bitmap context: move the crop's bottom-left to 0,0.
        ctx.translateBy(x: -crop.minX, y: -(full.height - crop.maxY))
        ctx.scaleBy(x: scale, y: scale)

        ctx.interpolationQuality = .none
        ctx.draw(base, in: CGRect(origin: .zero, size: canvasSize))
        draw(annotations, in: ctx, canvasSize: canvasSize, baseImage: base, scale: scale)
        return ctx.makeImage()
    }

    /// A bitmap context that keeps the base's color space and depth (8-bit, 16-bit or float).
    static func makeContext(width: Int, height: Int, matching base: CGImage) -> CGContext? {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let colorSpace: CGColorSpace = {
            guard let space = base.colorSpace, space.model == .rgb, space.supportsOutput else { return srgb }
            return space
        }()
        let opaque = [.none, .noneSkipFirst, .noneSkipLast].contains(base.alphaInfo)
        let isFloat = base.bitmapInfo.contains(.floatComponents)

        var formats: [(bits: Int, info: UInt32)] = []
        if isFloat && base.bitsPerComponent == 32 {
            let alpha = opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast
            formats.append((32, alpha.rawValue | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
        } else if isFloat && base.bitsPerComponent == 16 {
            let alpha = opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast
            formats.append((16, alpha.rawValue | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder16Little.rawValue))
        } else if base.bitsPerComponent > 8 {
            let alpha = opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast
            formats.append((16, alpha.rawValue | CGBitmapInfo.byteOrder16Little.rawValue))
        }
        let alpha8 = opaque ? CGImageAlphaInfo.noneSkipFirst : .premultipliedFirst
        formats.append((8, alpha8.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))

        for space in [colorSpace, srgb] {
            for format in formats {
                if let ctx = CGContext(
                    data: nil,
                    width: width,
                    height: height,
                    bitsPerComponent: format.bits,
                    bytesPerRow: 0,
                    space: space,
                    bitmapInfo: format.info
                ) {
                    return ctx
                }
            }
        }
        return nil
    }
}
