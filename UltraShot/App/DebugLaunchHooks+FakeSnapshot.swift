import AppKit
import CoreGraphics
import ImageIO

extension DebugLaunchHooks {
    /// A synthetic "screenshot" to use instead of the real screen in debug and QA flows:
    /// a diagonal gradient with a 50 pt grid, a fake menu bar, three fake windows with
    /// title bars and a few solid color blocks. Deterministic, sRGB, top-left origin like
    /// a real capture. With `ULTRASHOT_DEBUG_FAKE_SNAPSHOT=<path>`, that image instead,
    /// scaled to fill (aspect fill, centered).
    ///
    /// - Parameters:
    ///   - size: the screen size in points.
    ///   - scale: pixels per point (the screen's backing scale factor).
    nonisolated static func fakeSnapshotImage(size: CGSize, scale: CGFloat) -> CGImage {
        let width = max(1, Int((size.width * scale).rounded()))
        let height = max(1, Int((size.height * scale).rounded()))
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return fallbackImage()
        }
        // Draw in points with a top-left origin, like the screen.
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        let bounds = CGRect(origin: .zero, size: size)

        if let file = fakeSnapshotFile {
            if drawImageFile(file, in: context, bounds: bounds) {
                return context.makeImage() ?? fallbackImage()
            }
            Log.app.error("fake snapshot: cannot read \(file.path, privacy: .public), using the built-in desktop")
        }

        drawGradient(in: context, bounds: bounds, space: space)
        drawGrid(in: context, bounds: bounds)
        drawBlocks(in: context, bounds: bounds)
        let windows: [(CGRect, CGColor)] = [
            (CGRect(x: bounds.width * 0.08, y: bounds.height * 0.14, width: bounds.width * 0.36, height: bounds.height * 0.42), rgb(0.97, 0.97, 0.98)),
            (CGRect(x: bounds.width * 0.30, y: bounds.height * 0.34, width: bounds.width * 0.40, height: bounds.height * 0.46), rgb(0.16, 0.17, 0.20)),
            (CGRect(x: bounds.width * 0.62, y: bounds.height * 0.10, width: bounds.width * 0.30, height: bounds.height * 0.30), rgb(0.93, 0.96, 1.0)),
        ]
        for (frame, color) in windows {
            drawWindow(in: context, frame: frame, body: color)
        }
        drawMenuBar(in: context, bounds: bounds)
        return context.makeImage() ?? fallbackImage()
    }

    // MARK: - Pieces

    /// Draws the image at `url` aspect-filling `bounds` (top-left origin context). `false`
    /// when the file cannot be decoded.
    private nonisolated static func drawImageFile(_ url: URL, in context: CGContext, bounds: CGRect) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return false }
        let imageSize = CGSize(width: image.width, height: image.height)
        let fill = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let drawn = CGSize(width: imageSize.width * fill, height: imageSize.height * fill)
        let rect = CGRect(x: (bounds.width - drawn.width) / 2, y: (bounds.height - drawn.height) / 2, width: drawn.width, height: drawn.height)
        context.saveGState()
        // Undo the flip for this draw so the image is upright.
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height))
        context.restoreGState()
        return true
    }

    private nonisolated static func drawGradient(in context: CGContext, bounds: CGRect, space: CGColorSpace) {
        let colors = [rgb(0.20, 0.36, 0.78), rgb(0.55, 0.30, 0.72), rgb(0.95, 0.55, 0.42)] as CFArray
        guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.55, 1]) else { return }
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: bounds.maxX, y: bounds.maxY), options: [])
    }

    private nonisolated static func drawGrid(in context: CGContext, bounds: CGRect) {
        context.setStrokeColor(rgb(1, 1, 1, alpha: 0.18))
        context.setLineWidth(1)
        var x: CGFloat = 0
        while x <= bounds.maxX {
            context.move(to: CGPoint(x: x + 0.5, y: 0))
            context.addLine(to: CGPoint(x: x + 0.5, y: bounds.maxY))
            x += 50
        }
        var y: CGFloat = 0
        while y <= bounds.maxY {
            context.move(to: CGPoint(x: 0, y: y + 0.5))
            context.addLine(to: CGPoint(x: bounds.maxX, y: y + 0.5))
            y += 50
        }
        context.strokePath()
    }

    private nonisolated static func drawBlocks(in context: CGContext, bounds: CGRect) {
        let blocks: [(CGRect, CGColor)] = [
            (CGRect(x: bounds.width * 0.05, y: bounds.height * 0.72, width: 160, height: 110), rgb(0.95, 0.26, 0.21)),
            (CGRect(x: bounds.width * 0.22, y: bounds.height * 0.80, width: 120, height: 120), rgb(0.30, 0.69, 0.31)),
            (CGRect(x: bounds.width * 0.78, y: bounds.height * 0.62, width: 180, height: 90), rgb(1.0, 0.76, 0.03)),
            (CGRect(x: bounds.width * 0.86, y: bounds.height * 0.80, width: 100, height: 100), rgb(0.0, 0.74, 0.83)),
        ]
        for (rect, color) in blocks {
            context.setFillColor(color)
            context.fill(rect)
        }
    }

    private nonisolated static func drawWindow(in context: CGContext, frame: CGRect, body: CGColor) {
        let titleHeight: CGFloat = 28
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 12), blur: 30, color: rgb(0, 0, 0, alpha: 0.45))
        let shape = CGPath(roundedRect: frame, cornerWidth: 12, cornerHeight: 12, transform: nil)
        context.addPath(shape)
        context.setFillColor(body)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(shape)
        context.clip()
        context.setFillColor(rgb(0.82, 0.83, 0.86))
        context.fill(CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: titleHeight))
        // Fake content lines.
        context.setFillColor(rgb(0.5, 0.5, 0.55, alpha: 0.45))
        var lineY = frame.minY + titleHeight + 20
        var index = 0
        while lineY + 10 < frame.maxY - 12 {
            let lineWidth = (frame.width - 40) * (index.isMultiple(of: 3) ? 0.55 : 0.85)
            context.fill(CGRect(x: frame.minX + 20, y: lineY, width: lineWidth, height: 8))
            lineY += 22
            index += 1
        }
        context.restoreGState()

        let dots = [rgb(1.0, 0.37, 0.34), rgb(1.0, 0.74, 0.18), rgb(0.16, 0.79, 0.25)]
        for (offset, color) in dots.enumerated() {
            context.setFillColor(color)
            context.fillEllipse(in: CGRect(x: frame.minX + 12 + CGFloat(offset) * 20, y: frame.minY + 8, width: 12, height: 12))
        }
    }

    private nonisolated static func drawMenuBar(in context: CGContext, bounds: CGRect) {
        context.setFillColor(rgb(1, 1, 1, alpha: 0.55))
        context.fill(CGRect(x: 0, y: 0, width: bounds.width, height: 24))
        context.setFillColor(rgb(0.1, 0.1, 0.12, alpha: 0.75))
        var x: CGFloat = 16
        for width in [18, 54, 40, 44, 52, 48] as [CGFloat] {
            context.fill(CGRect(x: x, y: 8, width: width, height: 8))
            x += width + 18
        }
    }

    private nonisolated static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    /// 1×1 gray, only if a bitmap context cannot be created.
    private nonisolated static func fallbackImage() -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        )
        context?.setFillColor(gray: 0.5, alpha: 1)
        context?.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let image = context?.makeImage() else {
            preconditionFailure("cannot create a 1x1 bitmap")
        }
        return image
    }
}
