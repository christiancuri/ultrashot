import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Writes captures to a pasteboard.
///
/// Screenshots go on as image data only (PNG + TIFF, no file URL), so pasting keeps working
/// after the temporary file is deleted. Recordings go on as a file URL.
///
/// Debug builds redirect every write to a private named pasteboard when
/// `ULTRASHOT_DEBUG_PASTEBOARD=1`, so automated runs never touch the user's clipboard.
@MainActor
struct Clipboard {
    /// The named pasteboard used by debug automation (`ULTRASHOT_DEBUG_PASTEBOARD=1`).
    static let debugPasteboardName = NSPasteboard.Name("dev.christiancuri.ultrashot.debug")

    let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard) {
        self.pasteboard = pasteboard
    }

    /// The general pasteboard, or the debug one when `ULTRASHOT_DEBUG_PASTEBOARD=1` (Debug only).
    static var current: Clipboard {
        if DebugAutomation.usesDebugPasteboard {
            return Clipboard(pasteboard: NSPasteboard(name: debugPasteboardName))
        }
        return Clipboard(pasteboard: .general)
    }

    var isDebugPasteboard: Bool {
        pasteboard.name == Self.debugPasteboardName
    }

    /// Puts the image file at `url` on the pasteboard as PNG and TIFF data (no file URL).
    /// The color profile and DPI are kept.
    func writeImage(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let isPNG = (CGImageSourceGetType(source) as String?) == UTType.png.identifier
        guard let png = isPNG ? data : Self.convert(source, to: .png),
              let tiff = Self.convert(source, to: .tiff) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setData(tiff, forType: .tiff)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        Log.app.info("clipboard: image \(png.count) B png, \(tiff.count) B tiff (debug pasteboard: \(isDebugPasteboard))")
    }

    /// Puts a file reference on the pasteboard (recordings).
    func writeFileURL(_ url: URL) {
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        Log.app.info("clipboard: file reference \(url.lastPathComponent, privacy: .private) (debug pasteboard: \(isDebugPasteboard))")
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
