import CoreGraphics
import CoreImage

extension AnnotationRenderer {
    /// Pixel block size of the pixelate effect, in canvas points. Large enough that body
    /// text (and 2x Retina text) is unreadable.
    public static let pixelateBlockSize: CGFloat = 12

    /// Shared Core Image context (`CIContext` is thread-safe and Sendable).
    static let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// Draws `rect` (canvas points) of `baseImage` pixelated, aligned to whole base pixels.
    static func drawPixelated(_ rect: CGRect, in ctx: CGContext, canvasSize: CGSize, baseImage: CGImage?) {
        let rect = rect.standardized.intersection(CGRect(origin: .zero, size: canvasSize))
        guard !rect.isNull, rect.width > 0, rect.height > 0 else { return }
        guard let base = baseImage, canvasSize.width > 0, canvasSize.height > 0,
              let tile = pixelatedTile(of: base, canvasRect: rect, canvasSize: canvasSize) else {
            ctx.setFillColor(CGColor(gray: 0.55, alpha: 1))
            ctx.fill(rect)
            return
        }
        ctx.saveGState()
        ctx.interpolationQuality = .none
        ctx.draw(tile.image, in: tile.canvasRect)
        ctx.restoreGState()
    }

    /// Pixelates the base pixels under `canvasRect`. The block grid is anchored at the
    /// region's corner, so moving the region by whole blocks keeps the same look.
    static func pixelatedTile(
        of base: CGImage,
        canvasRect: CGRect,
        canvasSize: CGSize
    ) -> (image: CGImage, canvasRect: CGRect)? {
        let pixelsPerPoint = CGFloat(base.width) / canvasSize.width
        let extent = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        // Core Image uses a bottom-left origin, like the canvas: no flip needed.
        let pixelRect = CGRect(
            x: canvasRect.minX * pixelsPerPoint,
            y: canvasRect.minY * pixelsPerPoint,
            width: canvasRect.width * pixelsPerPoint,
            height: canvasRect.height * pixelsPerPoint
        ).integral.intersection(extent)
        guard !pixelRect.isNull, pixelRect.width >= 1, pixelRect.height >= 1 else { return nil }

        let block = max(pixelateBlockSize * pixelsPerPoint, 4)
        // CIPixellate samples one pixel per block; box-blurring first makes each block the
        // average of its area, so no original pixel values survive.
        let output = CIImage(cgImage: base)
            .clampedToExtent()
            .applyingFilter("CIBoxBlur", parameters: [kCIInputRadiusKey: block / 2])
            .applyingFilter("CIPixellate", parameters: [
                kCIInputScaleKey: block,
                kCIInputCenterKey: CIVector(x: pixelRect.minX + block / 2, y: pixelRect.minY + block / 2),
            ])
            .cropped(to: pixelRect)

        let colorSpace = base.colorSpace.flatMap { $0.model == .rgb && $0.supportsOutput ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let format: CIFormat = base.bitsPerComponent > 8 ? .RGBAh : .RGBA8
        guard let image = ciContext.createCGImage(output, from: pixelRect, format: format, colorSpace: colorSpace) else {
            return nil
        }
        let canvasTileRect = CGRect(
            x: pixelRect.minX / pixelsPerPoint,
            y: pixelRect.minY / pixelsPerPoint,
            width: pixelRect.width / pixelsPerPoint,
            height: pixelRect.height / pixelsPerPoint
        )
        return (image, canvasTileRect)
    }
}
