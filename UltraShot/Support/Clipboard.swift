import AppKit
import CaptureKit

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

    /// Puts the image file at `url` on the pasteboard as PNG and TIFF data (no file URL),
    /// keeping the color profile and DPI.
    ///
    /// The file is read before this returns (it may be deleted right after). Building the TIFF
    /// (and the PNG, for a JPEG file) runs off the main actor; the pasteboard is written when it
    /// is done, then `completion` runs. A newer write that lands first wins: this one is dropped.
    func writeImage(contentsOf url: URL, completion: @escaping @MainActor () -> Void = {}) throws {
        let fileData = try Data(contentsOf: url)
        let write = Self.beginWrite()
        Task { @MainActor in
            let image: PasteboardImage
            do {
                image = try await PerfTrace.measure("clipboard.encode (background)") {
                    try await Task.detached(priority: .userInitiated) { try PasteboardImage(fileData: fileData) }.value
                }
            } catch {
                Log.app.error("copy failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            guard write == Self.writeCount else {
                Log.app.info("clipboard: image dropped, a newer write came first")
                return
            }
            PerfTrace.measure("clipboard.write") {
                let item = NSPasteboardItem()
                item.setData(image.png, forType: .png)
                item.setData(image.tiff, forType: .tiff)
                pasteboard.clearContents()
                pasteboard.writeObjects([item])
            }
            Log.app.info("clipboard: image \(image.png.count) B png, \(image.tiff.count) B tiff (debug pasteboard: \(isDebugPasteboard))")
            completion()
        }
    }

    /// Puts a file reference on the pasteboard (recordings).
    func writeFileURL(_ url: URL) {
        _ = Self.beginWrite()
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        Log.app.info("clipboard: file reference \(url.lastPathComponent, privacy: .private) (debug pasteboard: \(isDebugPasteboard))")
    }

    /// Every write takes a number; an image write only lands if no write started after it.
    private static var writeCount = 0

    private static func beginWrite() -> Int {
        writeCount += 1
        return writeCount
    }
}
