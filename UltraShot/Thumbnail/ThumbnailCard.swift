import AppKit
import Quartz
import UltraShotCore
import UniformTypeIdentifiers

/// One Quick Access thumbnail: its capture, panel, view and auto-close countdown.
/// User actions arrive from ``ThumbnailView`` and are carried out with the coordinator's model.
@MainActor
final class ThumbnailCard {
    private(set) var item: CapturedItem
    let panel: ThumbnailPanel
    let view: ThumbnailView
    private(set) var size: CGSize
    private var timer: AutoCloseTimer
    private var timerTask: Task<Void, Never>?
    private weak var coordinator: ThumbnailCoordinator?
    private var isClosing = false

    init(item: CapturedItem, autoCloseInterval: Double?, stop: Int, coordinator: ThumbnailCoordinator) {
        self.item = item
        self.coordinator = coordinator
        size = ThumbnailLayout.cardSize(imageSize: CGSize(width: item.pixelWidth, height: item.pixelHeight), stop: stop)
        panel = ThumbnailPanel(frame: CGRect(origin: .zero, size: size))
        view = ThumbnailView(frame: CGRect(origin: .zero, size: size), isRecording: item.kind == .recording)
        timer = AutoCloseTimer(interval: autoCloseInterval, now: Self.now)
        panel.contentView = view
        view.card = self
        view.setDuration(item.duration)
        scheduleTimer()
        loadPreview()
    }

    private var model: AppModel? { coordinator?.model }

    /// Hidden while the annotator edits the capture.
    var isAnnotating: Bool { timer.pauseReasons.contains(.annotate) }

    /// The file was dropped into another app. Receivers copy dropped files asynchronously
    /// (a long recording can take a while), so closing keeps it until the next launch's purge.
    private(set) var wasDraggedOut = false

    /// Saved to the export folder (or elsewhere): closing must not delete it.
    var isSaved: Bool {
        model.map { !$0.captureStore.isTemporary(item.fileURL) } ?? false
    }

    // MARK: - Timer

    private static var now: Double { ProcessInfo.processInfo.systemUptime }

    func setPaused(_ reason: AutoCloseTimer.PauseReason, _ paused: Bool) {
        if paused { timer.pause(reason) } else { timer.resume(reason, now: Self.now) }
        scheduleTimer()
    }

    private func scheduleTimer() {
        timerTask?.cancel()
        guard let deadline = timer.deadline else { return }
        timerTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(0, deadline - Self.now)))
            guard !Task.isCancelled, let self, timer.isExpired(at: Self.now) else { return }
            coordinator?.autoClose(self)
        }
    }

    func hoverChanged(_ hovered: Bool) {
        Log.thumbnail.debug("hover \(hovered) \(self.item.fileURL.lastPathComponent, privacy: .public)")
        setPaused(.hover, hovered)
    }

    func previewChanged(_ visible: Bool) {
        setPaused(.preview, visible)
    }

    // MARK: - Actions

    func copy() {
        guard let model, !isClosing else { return }
        model.copyToClipboard(item)
        view.showFeedback("Copied")
        closeSoon()
    }

    func save() {
        guard !isClosing else { return }
        guard saveNow() else { return }
        view.showFeedback("Saved")
        closeSoon()
    }

    /// Saves to the export folder if needed. Returns `false` (and beeps) on failure.
    @discardableResult
    func saveNow() -> Bool {
        guard let model else { return false }
        do {
            update(try model.saveToExportFolder(item))
            return true
        } catch {
            Log.thumbnail.error("save failed: \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
            return false
        }
    }

    func saveAs() {
        guard let model else { return }
        setPaused(.menu, true)
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = model.exportFileName(for: item)
        savePanel.directoryURL = model.exportFolder
        if let type = UTType(filenameExtension: item.fileURL.pathExtension) { savePanel.allowedContentTypes = [type] }
        NSApp.activate()
        savePanel.begin { [weak self] response in
            guard let self else { return }
            setPaused(.menu, false)
            guard response == .OK, let url = savePanel.url else { return }
            do {
                if model.captureStore.isTemporary(item.fileURL) {
                    update(try model.saveTemporaryFile(of: item, to: url, unique: false))
                } else {
                    // Already saved: copy, replacing an existing file safely (no-op onto itself).
                    try FileTransfer.place(item.fileURL, at: url, keepSource: true)
                }
                close()
            } catch {
                Log.thumbnail.error("save as failed: \(error.localizedDescription, privacy: .public)")
                NSSound.beep()
            }
        }
    }

    func annotate() {
        guard let model, item.kind == .screenshot, !isClosing else { return }
        setPaused(.annotate, true)
        panel.orderOut(nil)
        model.annotation.annotate(imageAt: item.fileURL) { [weak self] outcome in
            guard let self else { return }
            Task { @MainActor in await self.finishAnnotation(outcome) }
        }
    }

    private func finishAnnotation(_ outcome: AnnotationOutcome) async {
        defer {
            setPaused(.annotate, false)
            if !isClosing { coordinator?.relayout() }
        }
        guard let model else { return }
        let image: CGImage
        switch outcome {
        case .cancelled: return
        case let .copy(result), let .save(result): image = result
        }
        do {
            let scale = ThumbnailPreview.scale(ofImageAt: item.fileURL)
            let written = try await CaptureOutput.overwrite(item.fileURL, with: image, scale: scale, settings: model.settings.screenshots)
            update(CapturedItem(
                id: item.id, kind: .screenshot, fileURL: item.fileURL, createdAt: item.createdAt,
                pixelWidth: written.pixelWidth, pixelHeight: written.pixelHeight
            ))
            loadPreview()
            if case .copy = outcome {
                model.copyToClipboard(item)
            } else {
                // Same as the Save button: save, show "Saved" and close the thumbnail.
                save()
            }
        } catch {
            Log.thumbnail.error("annotation write failed: \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
        }
    }

    func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
    }

    func openWithDefaultApp() {
        NSWorkspace.shared.open(item.fileURL)
    }

    func doubleClicked() {
        if item.kind == .recording { openWithDefaultApp() } else { annotate() }
    }

    func toggleQuickLook() {
        guard let preview = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists(), preview.isVisible {
            preview.orderOut(nil)
        } else {
            panel.makeKey()
            panel.makeFirstResponder(view)
            preview.makeKeyAndOrderFront(nil)
        }
    }

    func close() {
        guard !isClosing else { return }
        coordinator?.close(self)
    }

    /// Deletes the capture now: a temporary file is removed, a saved one goes to the Trash.
    func delete() {
        guard !isClosing, let model else { return }
        model.deleteCaptureFile(item.fileURL)
        coordinator?.close(self)
    }

    // MARK: - Drag

    func dragBegan() {
        setPaused(.drag, true)
    }

    /// - Parameters:
    ///   - delivered: the receiver accepted the file.
    ///   - keepRequested: ⌥ was held (keep the thumbnail).
    func dragEnded(delivered: Bool, keepRequested: Bool) {
        setPaused(.drag, false)
        if delivered { wasDraggedOut = true }
        guard delivered, !keepRequested, model?.settings.quickAccess.closeAfterDragging == true else { return }
        coordinator?.close(self)
    }

    /// Debug automation (`ULTRASHOT_DEBUG_THUMBNAIL_ACTION`).
    /// `action` may be limited to one kind: `copy:recording`, `save:screenshot`.
    func performDebugAction(_ spec: String) {
        let parts = spec.split(separator: ":").map(String.init)
        let action = parts.first ?? spec
        if parts.count > 1, parts[1] != item.kind.rawValue { return }
        Log.thumbnail.info("debug action \(action, privacy: .public) on \(self.item.fileURL.lastPathComponent, privacy: .public)")
        switch action {
        case "hover": view.setHovered(true, takeKey: false)
        case "copy": copy()
        case "save": save()
        case "close": close()
        case "save-only": saveNow()
        case "menu-log":
            let titles = makeContextMenu().items.map { $0.isSeparatorItem ? "—" : $0.title + ($0.submenu.map { " ▸ \($0.items.count) apps" } ?? "") }
            Log.thumbnail.info("menu: \(titles.joined(separator: " | "), privacy: .public)")
        case "delete": delete()
        case "annotate": annotate()
        case "dragged": dragEnded(delivered: true, keepRequested: false)
        case "saved-feedback": view.setHovered(true, takeKey: false); view.showFeedback("Saved")
        default: Log.thumbnail.error("unknown debug action \(action, privacy: .public)")
        }
    }

    // MARK: - Context menu

    /// CleanShot-like menu: annotate, copy/save, Quick Look, Open With, Finder, Delete, Close.
    func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        if item.kind == .screenshot { add("Open Annotation Tool…", key: "e", to: menu) { $0.annotate() } }
        add("Quick Look", key: " ", to: menu) { $0.toggleQuickLook() }
        menu.addItem(.separator())
        add("Copy", key: "c", to: menu) { $0.copy() }
        add("Save", key: "s", to: menu) { $0.save() }
        add("Save As…", to: menu) { $0.saveAs() }
        menu.addItem(openWithItem())
        if isSaved { add("Show in Finder", to: menu) { $0.showInFinder() } }
        menu.addItem(.separator())
        add(isSaved ? "Move to Trash" : "Delete", key: "\u{8}", to: menu) { $0.delete() }
        add("Close", key: "w", to: menu) { $0.close() }
        return menu
    }

    /// "Open With ▸": the default app first, then the other apps that open the file.
    private func openWithItem() -> NSMenuItem {
        let url = item.fileURL
        let submenu = NSMenu()
        let workspace = NSWorkspace.shared
        let defaultApp = workspace.urlForApplication(toOpen: url)
        var apps = workspace.urlsForApplications(toOpen: url).filter { $0 != defaultApp }
        if let defaultApp { apps.insert(defaultApp, at: 0) }
        for (index, appURL) in apps.prefix(12).enumerated() {
            var title = FileManager.default.displayName(atPath: appURL.path(percentEncoded: false))
            if index == 0, appURL == defaultApp { title += " (default)" }
            let entry = ClosureMenuItem(title: title, keyEquivalent: "") {
                workspace.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
            }
            let icon = workspace.icon(forFile: appURL.path(percentEncoded: false))
            icon.size = NSSize(width: 16, height: 16)
            entry.image = icon
            submenu.addItem(entry)
            if index == 0, appURL == defaultApp, apps.count > 1 { submenu.addItem(.separator()) }
        }
        let item = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
        item.submenu = submenu
        item.isEnabled = !apps.isEmpty
        return item
    }

    private func add(_ title: String, key: String = "", to menu: NSMenu, action: @escaping @MainActor (ThumbnailCard) -> Void) {
        let menuItem = ClosureMenuItem(title: title, keyEquivalent: key) { [weak self] in
            guard let self else { return }
            action(self)
        }
        // Shortcuts shown for reference; the view handles the keys while hovered.
        menuItem.keyEquivalentModifierMask = key == " " ? [] : .command
        menu.addItem(menuItem)
    }

    // MARK: - Lifecycle

    /// Hides the panel; the coordinator releases the file.
    func tearDown() {
        isClosing = true
        timerTask?.cancel()
        if QLPreviewPanel.sharedPreviewPanelExists(), let preview = QLPreviewPanel.shared(), preview.isVisible,
           preview.dataSource === view {
            preview.orderOut(nil)
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: { [panel] in
            Task { @MainActor in
                panel.orderOut(nil)
                panel.close()
            }
        })
    }

    private func closeSoon() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            self?.close()
        }
    }

    private func update(_ newItem: CapturedItem) {
        let oldURL = item.fileURL
        item = newItem
        coordinator?.itemChanged(self, from: oldURL)
    }

    private func loadPreview() {
        let item = item
        let maxPixel = Int(max(size.width, size.height) * 2 * (panel.screen?.backingScaleFactor ?? 2))
        Task { @MainActor [weak self] in
            let preview = await ThumbnailPreview.load(item, maxPixelSize: maxPixel)
            guard let self else { return }
            view.image = preview.image
            if item.kind == .recording { view.setDuration(item.duration ?? preview.duration) }
        }
    }
}
