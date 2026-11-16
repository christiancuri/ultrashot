import AVFoundation
import ImageIO
import UltraShotCore

/// Loads the small image a thumbnail shows: a downsampled screenshot, or a recording's poster
/// frame and duration. Runs off the main actor.
enum ThumbnailPreview {
    struct Result: Sendable {
        var image: CGImage?
        var duration: Double?
    }

    static func load(_ item: CapturedItem, maxPixelSize: Int) async -> Result {
        switch item.kind {
        case .screenshot:
            let url = item.fileURL
            return await Task.detached(priority: .userInitiated) {
                Result(image: downsampledImage(at: url, maxPixelSize: maxPixelSize), duration: nil)
            }.value
        case .recording:
            return await posterFrame(of: item.fileURL, maxPixelSize: maxPixelSize)
        }
    }

    /// Pixels per point of an image file, from its DPI (72 × scale); 1 when unknown.
    static func scale(ofImageAt url: URL) -> CGFloat {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let dpi = (properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue, dpi > 0 else { return 1 }
        return max(1, (dpi / 72).rounded())
    }

    private nonisolated static func downsampledImage(at url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(64, maxPixelSize),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private nonisolated static func posterFrame(of url: URL, maxPixelSize: Int) async -> Result {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        let image = try? await generator.image(at: .zero).image
        let duration = try? await asset.load(.duration).seconds
        return Result(image: image, duration: duration)
    }
}
