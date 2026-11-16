import AppKit
import UltraShotCore

/// The Quick Access thumbnails shown after a capture, stacked in the bottom-left (or right)
/// corner with the newest at the bottom, and the lifetime of the temporary capture files.
///
/// A thumbnail holds its file (``fileHolds``); closing it — by timer, close button, ⌘W or
/// Esc — releases the hold, and an unsaved file nobody else holds is deleted. Saved files are
/// never deleted.
@MainActor
final class ThumbnailCoordinator {
    weak var model: AppModel?

    /// Who still needs each capture file (thumbnails, the clipboard).
    var fileHolds = CaptureFileHolds()

    /// Open thumbnails, newest first.
    private(set) var cards: [ThumbnailCard] = []

    func show(_ item: CapturedItem) {
        show(item, autoClose: true)
    }

    /// - Parameter autoClose: `false` keeps the thumbnail until closed (debug samples).
    func show(_ item: CapturedItem, autoClose: Bool) {
        guard let model else { return }
        let settings = model.settings.quickAccess
        var interval: Double?
        if autoClose {
            switch DebugAutomation.autoCloseOverride {
            case .off: interval = nil
            case let .seconds(seconds): interval = seconds
            case nil: interval = settings.autoCloseSeconds
            }
        }
        fileHolds.retain(item.fileURL, by: .thumbnail(item.id))
        let card = ThumbnailCard(item: item, autoCloseInterval: interval, stop: settings.overlaySize, coordinator: self)
        cards.insert(card, at: 0)
        relayout(appearing: card)
        if let actions = DebugAutomation.thumbnailAction {
            Task { @MainActor [weak card] in
                for action in actions.split(separator: ",") {
                    try? await Task.sleep(for: .seconds(2))
                    card?.performDebugAction(String(action))
                }
            }
        }
        let autoCloseLabel = interval.map { "\($0)s" } ?? "off"
        Log.thumbnail.info("show \(item.kind.rawValue, privacy: .public) \(item.fileURL.lastPathComponent, privacy: .public)")
        Log.thumbnail.info(
            "card \(Int(card.size.width))x\(Int(card.size.height)) autoClose \(autoCloseLabel, privacy: .public) window \(card.panel.windowNumber)"
        )
    }

    /// Closes every thumbnail (quitting). Unsaved files are deleted, or saved first when the
    /// auto-close action is Save and Close.
    func closeAll() {
        let action = DebugAutomation.autoCloseAction ?? model?.settings.quickAccess.autoCloseAction ?? .close
        for card in cards {
            if action == .saveAndClose, !card.isSaved {
                card.saveNow()
            }
            close(card)
        }
    }

    /// Debug hook (`-debug-open thumbnail-sample`): shows sample thumbnails over synthetic
    /// captures, without auto-close. See `ThumbnailCoordinator+Debug.swift`.
    func debugShowSample() {
        Task { await showSamples() }
    }

    // MARK: - Card callbacks

    /// Removes `card` and releases its file, deleting it if unsaved and unheld. A file dragged
    /// into another app is kept until the next launch's purge (the receiver may still copy it).
    func close(_ card: ThumbnailCard) {
        guard let index = cards.firstIndex(where: { $0 === card }) else { return }
        cards.remove(at: index)
        card.tearDown()
        Log.thumbnail.info("close \(card.item.fileURL.lastPathComponent, privacy: .public) saved \(card.isSaved) dragged \(card.wasDraggedOut)")
        if card.wasDraggedOut {
            fileHolds.release(card.item.fileURL, by: .thumbnail(card.item.id))
        } else {
            model?.releaseCaptureFile(card.item.fileURL, holder: .thumbnail(card.item.id))
        }
        relayout()
    }

    /// The auto-close interval elapsed: Close, or Save and Close per settings.
    func autoClose(_ card: ThumbnailCard) {
        guard let model else { return }
        let action = DebugAutomation.autoCloseAction ?? model.settings.quickAccess.autoCloseAction
        Log.thumbnail.info("auto-close (\(action.rawValue, privacy: .public)) \(card.item.fileURL.lastPathComponent, privacy: .public)")
        if action == .saveAndClose, !card.isSaved {
            // A failed save keeps the thumbnail so the capture is not lost.
            guard card.saveNow() else { return }
        }
        close(card)
    }

    /// A card's file moved (saved) or was replaced: move its hold along.
    func itemChanged(_ card: ThumbnailCard, from oldURL: URL) {
        let holder = CaptureFileHolds.Holder.thumbnail(card.item.id)
        guard oldURL.standardizedFileURL != card.item.fileURL.standardizedFileURL else { return }
        fileHolds.retain(card.item.fileURL, by: holder)
        model?.releaseCaptureFile(oldURL, holder: holder)
    }

    // MARK: - Layout

    /// The screen thumbnails go on: the one under the pointer with "Move to active screen",
    /// otherwise the main (menu bar) screen.
    private var targetScreen: NSScreen? {
        let screens = NSScreen.screens
        if model?.settings.quickAccess.moveToActiveScreen == true {
            let mouse = NSEvent.mouseLocation
            if let screen = screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) { return screen }
        }
        return screens.first
    }

    /// Positions every card; `appearing` slides in from the screen edge.
    func relayout(appearing: ThumbnailCard? = nil) {
        guard let model, let screen = targetScreen else { return }
        let position = DebugAutomation.quickAccessPosition ?? model.settings.quickAccess.position
        let visible = cards.filter { !$0.isAnnotating }
        let frames = ThumbnailLayout.frames(for: visible.map(\.size), position: position, screenFrame: screen.frame, visibleFrame: screen.visibleFrame)
        for (index, card) in visible.enumerated() {
            guard index < frames.count else {
                card.panel.orderOut(nil)
                continue
            }
            let frame = frames[index]
            if card === appearing || !card.panel.isVisible {
                let offset: CGFloat = position == .left ? -(frame.width + ThumbnailLayout.edgeInset) : frame.width + ThumbnailLayout.edgeInset
                card.panel.setFrame(frame.offsetBy(dx: offset, dy: 0), display: false)
                card.panel.alphaValue = 0
                card.panel.orderFrontRegardless()
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                card.panel.animator().setFrame(frame, display: true)
                card.panel.animator().alphaValue = 1
            }
        }
    }
}
