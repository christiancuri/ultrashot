import CaptureKit
import CoreGraphics
import Foundation
import UltraShotCore

/// Turns a captured image into a file in the capture store, following the Screenshots
/// settings (format, JPEG quality, sRGB conversion, Retina → 1x).
enum CaptureOutput {
    struct Written: Sendable {
        let url: URL
        let pixelWidth: Int
        let pixelHeight: Int
    }

    /// Encodes and writes `image` (taken at `scale` pixels per point) to a new temporary file.
    /// The work runs off the main actor.
    static func write(_ image: CGImage, scale: CGFloat, settings: ScreenshotSettings, store: CaptureStore) async throws -> Written {
        let url = try store.makeTemporaryURL(kind: .screenshot, ext: settings.format.fileExtension)
        return try await Task.detached(priority: .userInitiated) {
            try encode(image, scale: scale, settings: settings, to: url)
        }.value
    }

    /// Writes `image` over the file at `url` (an annotated version of an existing capture),
    /// keeping the file's format.
    static func overwrite(_ url: URL, with image: CGImage, scale: CGFloat, settings: ScreenshotSettings) async throws -> Written {
        var settings = settings
        settings.format = url.pathExtension.lowercased() == "png" ? .png : .jpeg
        let finalSettings = settings
        return try await Task.detached(priority: .userInitiated) {
            try encode(image, scale: scale, settings: finalSettings, to: url)
        }.value
    }

    nonisolated static func encode(_ image: CGImage, scale: CGFloat, settings: ScreenshotSettings, to url: URL) throws -> Written {
        var output = image
        var outputScale = max(scale, 1)
        if settings.downscaleRetina, outputScale > 1 {
            guard let small = ImageProcessing.downscale(output, factor: outputScale) else { throw CaptureError.encodingFailed }
            output = small
            outputScale = 1
        }
        if settings.convertToSRGB {
            guard let srgb = ImageProcessing.convertToSRGB(output) else { throw CaptureError.encodingFailed }
            output = srgb
        }
        let format: ImageEncoder.Format = switch settings.format {
        case .png: .png
        case .jpeg: .jpeg(quality: settings.jpegQuality)
        }
        try ImageEncoder.write(output, to: url, format: format, scale: outputScale)
        return Written(url: url, pixelWidth: output.width, pixelHeight: output.height)
    }
}

extension CapturedItem {
    /// A screenshot item for a freshly written file.
    init(screenshot written: CaptureOutput.Written) {
        self.init(kind: .screenshot, fileURL: written.url, pixelWidth: written.pixelWidth, pixelHeight: written.pixelHeight)
    }
}
