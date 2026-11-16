import AnnotateKit
import AppKit
import ImageIO

/// How an annotation session ended.
enum AnnotationOutcome {
    /// Copy (⌘C / ↩): the flattened image.
    case copy(CGImage)
    /// Save (⌘S): the flattened image.
    case save(CGImage)
    case cancelled
}

/// Lightshot-style in-place annotation on a frozen selection. One session at a time: while
/// one (or another full-screen flow) is up, a new one is refused, never swapped in.
@MainActor
final class AnnotationCoordinator {
    weak var model: AppModel?

    private(set) var session: AnnotationSession?

    /// Annotates on top of a frozen screen image.
    ///
    /// - Parameters:
    ///   - background: the frozen image of `screen`, full size.
    ///   - screen: the screen the session runs on.
    ///   - initialSelection: the selection in the screen's AppKit view coordinates (points
    ///     relative to `screen.frame.origin`, y up), or `nil` to let the user drag one.
    ///   - completion: called once on the main actor with the outcome. The exported image
    ///     has the background's scale (pixels per point) and color space.
    func annotate(
        background: CGImage,
        screen: NSScreen,
        initialSelection: CGRect?,
        completion: @escaping @MainActor (AnnotationOutcome) -> Void
    ) {
        let size = screen.frame.size
        guard background.width > 0, size.width > 0 else {
            completion(.cancelled)
            return
        }
        start(AnnotationSession.Configuration(
            screen: screen,
            displayBackground: background,
            base: background,
            baseScale: CGFloat(background.width) / size.width,
            canvasFrame: CGRect(origin: .zero, size: size),
            selectionLimit: nil,
            initialSelection: initialSelection
        ), completion: completion)
    }

    /// Annotates an image file (the thumbnail's Annotate button): the image is shown at its
    /// point size (from its DPI), centered on the screen with the pointer over a dimmed
    /// overlay, fit to 90% of the visible frame when larger. The selection starts on the
    /// whole image and cannot leave it (cropping is allowed). The exported image has the
    /// file's scale and color space.
    func annotate(imageAt url: URL, completion: @escaping @MainActor (AnnotationOutcome) -> Void) {
        guard let loaded = Self.loadImage(at: url) else {
            Log.annotate.error("annotate(imageAt:) cannot read \(url.lastPathComponent, privacy: .public)")
            completion(.cancelled)
            return
        }
        let screen = Self.screenWithPointer()
        let canvasSize = CGSize(width: CGFloat(loaded.image.width) / loaded.scale, height: CGFloat(loaded.image.height) / loaded.scale)
        let visible = screen.visibleFrame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        let mapping = CanvasMapping.fitted(canvasSize: canvasSize, in: visible, displayScale: screen.backingScaleFactor)
        guard let composite = Self.composite(loaded.image, in: mapping.displayRect, screenSize: screen.frame.size, scale: screen.backingScaleFactor) else {
            completion(.cancelled)
            return
        }
        let shownAt = String(describing: mapping.displayRect)
        Log.annotate.info("annotate file \(loaded.image.width)x\(loaded.image.height) px @\(loaded.scale)x shown at \(shownAt, privacy: .public)")
        start(AnnotationSession.Configuration(
            screen: screen,
            displayBackground: composite,
            base: loaded.image,
            baseScale: loaded.scale,
            canvasFrame: mapping.displayRect,
            selectionLimit: mapping.displayRect,
            initialSelection: mapping.displayRect,
            dimAlpha: 0.55
        ), completion: completion)
    }

    private func start(_ configuration: AnnotationSession.Configuration, completion: @escaping @MainActor (AnnotationOutcome) -> Void) {
        // Never replace a session in progress (its annotations would be lost) or stack on
        // another full-screen flow.
        guard model?.canBeginModalFlow("annotation") ?? (session == nil) else {
            completion(.cancelled)
            return
        }
        let session = AnnotationSession(configuration: configuration, completion: completion)
        session.onFinish = { [weak self, weak session] in
            guard let self, self.session === session else { return }
            self.session = nil
        }
        self.session = session
        session.show()
        debugAutomate(session)
    }

    // MARK: - Helpers

    static func screenWithPointer() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// Decodes the first image of a file and its scale (DPI / 72, 1 when absent or odd).
    nonisolated static func loadImage(at url: URL) -> (image: CGImage, scale: CGFloat)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let dpi = (properties?[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 72
        let scale = dpi / 72
        return (image, (1...4).contains(scale) ? CGFloat(scale) : 1)
    }

    /// A transparent screen-sized image with `image` drawn in `rect` (what the overlay shows
    /// around the selection; the live screen shows dimmed through the transparent part).
    nonisolated static func composite(_ image: CGImage, in rect: CGRect, screenSize: CGSize, scale: CGFloat) -> CGImage? {
        let space = image.colorSpace.flatMap { $0.model == .rgb && $0.supportsOutput ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: Int((screenSize.width * scale).rounded()),
            height: Int((screenSize.height * scale).rounded()),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: rect)
        return ctx.makeImage()
    }
}
