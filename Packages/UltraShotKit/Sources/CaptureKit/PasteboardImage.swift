import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The PNG and TIFF data a screenshot goes on the pasteboard as, built from its encoded file.
///
/// Building it decodes the image and re-encodes it as TIFF (and as PNG for a JPEG file), which
/// takes tens of milliseconds for a Retina screen, so callers run it off the main actor. The
/// color profile and DPI are kept.
public struct PasteboardImage: Sendable {
    public let png: Data
    public let tiff: Data

    /// - Parameter fileData: the contents of an encoded image file (PNG or JPEG). A PNG is
    ///   used as-is.
    public init(fileData: Data) throws {
        guard let source = CGImageSourceCreateWithData(fileData as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let isPNG = (CGImageSourceGetType(source) as String?) == UTType.png.identifier
        guard let png = isPNG ? fileData : Self.convert(source, to: .png),
              let tiff = Self.convert(source, to: .tiff) else {
            throw CaptureError.encodingFailed
        }
        self.png = png
        self.tiff = tiff
    }

    /// Re-encodes the first image of `source` as `type`, keeping its metadata (DPI, profile).
    private static func convert(_ source: CGImageSource, to type: UTType) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, type.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImageFromSource(destination, source, 0, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
