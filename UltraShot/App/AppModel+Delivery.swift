import AppKit
import UltraShotCore

extension AppModel {
    /// What the annotator asked for when it finished.
    enum AnnotationAction {
        case copy
        case save
    }

    /// After-capture pipeline: every finished capture (screenshot or recording) ends here.
    /// Applies `settings.general.afterCapture` for the item's kind (see ``DeliveryPlan``).
    ///
    /// File lifetime: a temporary capture lives while a thumbnail or a clipboard file
    /// reference holds it (``ThumbnailCoordinator/fileHolds``) and is deleted when the last
    /// holder lets go. Saved files (outside the capture store) are never deleted.
    func deliver(_ item: CapturedItem) {
        var item = item
        let plan = DeliveryPlan.make(kind: item.kind, actions: afterCaptureActions(for: item.kind))
        var showThumbnail = plan.showThumbnail
        if plan.save {
            do {
                item = try saveToExportFolder(item)
            } catch {
                // Keep the capture reachable so the user can retry.
                Log.app.error("auto-save failed: \(error.localizedDescription, privacy: .public)")
                showThumbnail = true
            }
        }
        if plan.clipboard != .none {
            copyToClipboard(item)
        }
        if showThumbnail {
            thumbnails.show(item)
        } else {
            deleteIfUnheld(item.fileURL)
        }
        let clipboard = String(describing: plan.clipboard)
        let summary = "\(item.kind.rawValue) \(item.pixelWidth)x\(item.pixelHeight) clipboard=\(clipboard) save=\(plan.save) thumbnail=\(showThumbnail)"
        Log.app.info("deliver \(summary, privacy: .public)")
    }

    /// Delivers the result of capture-and-annotate: Copy puts it on the clipboard, Save saves
    /// it to the export folder; either shows a thumbnail when the screenshot settings say so.
    func deliverAnnotation(_ item: CapturedItem, action: AnnotationAction) {
        var item = item
        var showThumbnail = afterCaptureActions(for: .screenshot).showThumbnail
        switch action {
        case .copy:
            copyToClipboard(item)
        case .save:
            do {
                item = try saveToExportFolder(item)
            } catch {
                Log.app.error("saving annotation failed: \(error.localizedDescription, privacy: .public)")
                showThumbnail = true
            }
        }
        if showThumbnail {
            thumbnails.show(item)
        } else {
            deleteIfUnheld(item.fileURL)
        }
        let summary = "\(action) \(item.pixelWidth)x\(item.pixelHeight) thumbnail=\(showThumbnail)"
        Log.app.info("deliver annotation \(summary, privacy: .public)")
    }

    // MARK: - Building blocks

    /// The after-capture actions for `kind` (`ULTRASHOT_DEBUG_AFTER_CAPTURE` overrides them
    /// in Debug builds).
    func afterCaptureActions(for kind: CapturedItem.Kind) -> AfterCaptureActions {
        DebugAutomation.afterCaptureActions(for: kind) ?? settings.general.afterCapture.actions(for: kind)
    }

    /// The export folder (`ULTRASHOT_DEBUG_EXPORT_DIR` overrides it in Debug builds). A folder
    /// inside the temporary captures folder falls back to the default (saved files there would
    /// be deleted as temporary).
    var exportFolder: URL {
        let requested = DebugAutomation.exportFolder ?? settings.general.exportFolderURL
        let folder = captureStore.exportFolder(requested, fallback: GeneralSettings().exportFolderURL)
        if folder != requested {
            Log.app.error("export folder is inside the captures folder: using \(folder.path(percentEncoded: false), privacy: .private)")
        }
        return folder
    }

    /// The export file name for `item` from the file-name template.
    func exportFileName(for item: CapturedItem) -> String {
        FileNaming.fileName(
            template: settings.advanced.fileNameTemplate,
            kind: item.kind,
            date: item.createdAt,
            fileExtension: item.fileURL.pathExtension
        )
    }

    /// Saves `item` into the export folder (unique name) and returns it with its new URL.
    /// Already-saved items are returned unchanged. When the clipboard references the temporary
    /// file (recordings), the file is copied instead of moved so the reference stays valid.
    func saveToExportFolder(_ item: CapturedItem) throws -> CapturedItem {
        guard captureStore.isTemporary(item.fileURL) else { return item }
        return try saveTemporaryFile(of: item, to: exportFolder.appending(path: exportFileName(for: item), directoryHint: .notDirectory), unique: true)
    }

    /// Saves `item`'s temporary file to `destination` (moved, or copied when the clipboard
    /// references it). With `unique`, a taken name becomes `name 2.ext`; otherwise an existing
    /// file at `destination` is replaced (Save As… already asked).
    func saveTemporaryFile(of item: CapturedItem, to destination: URL, unique: Bool) throws -> CapturedItem {
        let fileManager = FileManager.default
        let folder = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        var target = destination
        if unique {
            target = FileNaming.uniqueURL(in: folder, fileName: destination.lastPathComponent, fileManager: fileManager)
        }
        let clipboardHoldsFile = thumbnails.fileHolds.holders(of: item.fileURL).contains(.clipboard)
        // Replaces an existing file only once the new one is in place (Save As… "Replace").
        target = try FileTransfer.place(item.fileURL, at: target, keepSource: clipboardHoldsFile, fileManager: fileManager)
        if !clipboardHoldsFile {
            thumbnails.fileHolds.move(item.fileURL, to: target)
        }
        Log.app.info("saved \(item.kind.rawValue, privacy: .public) as \(target.lastPathComponent, privacy: .private) (copied: \(clipboardHoldsFile))")
        var saved = item
        saved.fileURL = target
        return saved
    }

    /// Copies `item` to the clipboard: image data for screenshots, a file reference for
    /// recordings (which then keeps the file until the next capture replaces the clipboard).
    func copyToClipboard(_ item: CapturedItem) {
        let clipboard = Clipboard.current
        switch item.kind {
        case .screenshot:
            do {
                try clipboard.writeImage(contentsOf: item.fileURL)
            } catch {
                Log.app.error("copy failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            setClipboardFile(nil)
        case .recording:
            clipboard.writeFileURL(item.fileURL)
            setClipboardFile(item.fileURL)
        }
    }

    /// Drops `holder`'s claim on `url` and deletes the file once nobody holds it.
    func releaseCaptureFile(_ url: URL, holder: CaptureFileHolds.Holder) {
        thumbnails.fileHolds.release(url, by: holder)
        deleteIfUnheld(url)
    }

    /// Deletes `url` when it is a temporary capture that nothing holds any more.
    func deleteIfUnheld(_ url: URL) {
        guard captureStore.isTemporary(url), !thumbnails.fileHolds.isHeld(url),
              FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        captureStore.delete(url)
        Log.app.info("deleted temporary capture \(url.lastPathComponent, privacy: .public)")
    }

    /// Deletes a capture on the user's request (Delete in the thumbnail): a temporary file is
    /// removed right away, a saved one goes to the Trash. Holders are forgotten.
    func deleteCaptureFile(_ url: URL) {
        thumbnails.fileHolds.removeAll(for: url)
        if captureStore.isTemporary(url) {
            captureStore.delete(url)
            Log.app.info("deleted capture \(url.lastPathComponent, privacy: .public) on request")
        } else {
            NSWorkspace.shared.recycle([url]) { _, error in
                if let error {
                    Log.app.error("moving to Trash failed: \(error.localizedDescription, privacy: .public)")
                } else {
                    Log.app.info("moved saved capture to Trash")
                }
            }
        }
    }

    /// The file the clipboard references (recordings), or `nil` after an image copy.
    private func setClipboardFile(_ url: URL?) {
        let previous = thumbnails.fileHolds.url(heldBy: .clipboard)
        guard previous?.standardizedFileURL != url?.standardizedFileURL else { return }
        if let url { thumbnails.fileHolds.retain(url, by: .clipboard) }
        if let previous { releaseCaptureFile(previous, holder: .clipboard) }
    }
}
