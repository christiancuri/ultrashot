import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Encodes images with ImageIO. The image's color profile is embedded as-is, and DPI metadata is
/// set to 72 × scale so a 2x image opens at its point size in Preview.
public enum ImageEncoder {
    public enum Format: Sendable, Equatable {
        case png
        /// `quality` from 0 (smallest) to 1 (best).
        case jpeg(quality: Double)

        public var utType: UTType {
            switch self {
            case .png: .png
            case .jpeg: .jpeg
            }
        }

        public var fileExtension: String {
            switch self {
            case .png: "png"
            case .jpeg: "jpg"
            }
        }
    }

    /// Encodes `image`. JPEG has no alpha, so transparent pixels are composited over white first.
    /// - Parameter scale: pixels per point of the image (2 for Retina); sets DPI to 72 × scale.
    public static func data(for image: CGImage, format: Format, scale: CGFloat = 1) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData, format.utType.identifier as CFString, 1, nil
        ) else { throw CaptureError.encodingFailed }
        try encode(image, format: format, scale: scale, into: destination)
        return data as Data
    }

    /// Encodes `image` and writes it atomically to `url`.
    public static func write(_ image: CGImage, to url: URL, format: Format, scale: CGFloat = 1) throws {
        let encoded = try data(for: image, format: format, scale: scale)
        do {
            try encoded.write(to: url, options: .atomic)
        } catch {
            throw CaptureError.writeFailed(error.localizedDescription)
        }
    }

    // MARK: - Private

    private static func encode(_ image: CGImage, format: Format, scale: CGFloat,
                               into destination: CGImageDestination) throws {
        let dpi = 72 * max(scale, 0.01)
        var properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi
        ]
        var source = image
        if case let .jpeg(quality) = format {
            properties[kCGImageDestinationLossyCompressionQuality] = min(max(quality, 0), 1)
            guard let flat = ImageProcessing.flattened(image) else { throw CaptureError.encodingFailed }
            source = flat
        }
        CGImageDestinationAddImage(destination, source, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CaptureError.encodingFailed }
    }
}
