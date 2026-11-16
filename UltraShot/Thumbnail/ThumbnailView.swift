import AppKit
import Quartz

/// Content of a thumbnail panel: the capture (aspect-fill, rounded), and on hover a dim with
/// Copy and Save in the center, close top-left and annotate bottom-left (CleanShot layout).
/// Recordings show a duration badge. The view is a drag source for the capture file, owns the
/// keyboard shortcuts and the context menu, and hosts Quick Look.
final class ThumbnailView: NSView {
    weak var card: ThumbnailCard?

    private let imageLayer = CALayer()
    private let dimLayer = CALayer()
    private let controls = NSView()
    private let copyButton = ThumbnailButton(.pill("Copy"))
    private let saveButton = ThumbnailButton(.pill("Save"))
    private let closeButton = ThumbnailButton(.circle(symbol: "xmark", label: "Close"))
    private let annotateButton = ThumbnailButton(.circle(symbol: "pencil", label: "Annotate"))
    private let deleteButton = ThumbnailButton(.circle(symbol: "trash", label: "Delete"))
    private let badge = NSTextField(labelWithString: "")
    private let feedback = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var mouseDownEvent: NSEvent?
    private var isDragging = false
    private(set) var isHovered = false
    private var feedbackShown = false

    static let cornerRadius: CGFloat = 12
    private static let inset: CGFloat = 6

    var image: CGImage? {
        didSet { imageLayer.contents = image }
    }

    init(frame: CGRect, isRecording: Bool) {
        super.init(frame: frame)
        wantsLayer = true
        guard let layer else { return }
        layer.cornerRadius = Self.cornerRadius
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        layer.backgroundColor = NSColor(white: 0.16, alpha: 1).cgColor
        layer.borderWidth = 0.5
        layer.borderColor = NSColor(white: 1, alpha: 0.18).cgColor

        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.masksToBounds = true
        layer.addSublayer(imageLayer)
        dimLayer.backgroundColor = NSColor.black.cgColor
        dimLayer.opacity = 0
        layer.addSublayer(dimLayer)

        controls.alphaValue = 0
        addSubview(controls)
        for button in [copyButton, saveButton, closeButton, deleteButton] { controls.addSubview(button) }
        if !isRecording { controls.addSubview(annotateButton) }
        copyButton.action = { [weak self] in self?.card?.copy() }
        saveButton.action = { [weak self] in self?.card?.save() }
        closeButton.action = { [weak self] in self?.card?.close() }
        annotateButton.action = { [weak self] in self?.card?.annotate() }
        deleteButton.action = { [weak self] in self?.card?.delete() }

        configureLabel(badge, size: 11)
        badge.isHidden = !isRecording
        addSubview(badge)
        configureLabel(feedback, size: 13)
        feedback.alphaValue = 0
        addSubview(feedback)
        layoutContents()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Recording length, shown as `m:ss` in the bottom-right corner.
    func setDuration(_ seconds: Double?) {
        guard let seconds, seconds.isFinite else { return }
        let total = Int(seconds.rounded())
        badge.stringValue = String(format: " %d:%02d ", total / 60, total % 60)
        layoutContents()
    }

    // MARK: - Layout

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutContents()
    }

    private func layoutContents() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        dimLayer.frame = bounds
        CATransaction.commit()
        controls.frame = bounds
        let inset = Self.inset - 1
        closeButton.setFrameOrigin(CGPoint(x: inset, y: bounds.height - inset - closeButton.frame.height))
        annotateButton.setFrameOrigin(CGPoint(x: inset, y: inset))
        deleteButton.setFrameOrigin(CGPoint(x: bounds.width - inset - deleteButton.frame.width, y: inset))
        let gap: CGFloat = 11
        copyButton.setFrameOrigin(CGPoint(x: (bounds.width - copyButton.frame.width) / 2, y: (bounds.midY + gap / 2).rounded()))
        saveButton.setFrameOrigin(CGPoint(x: (bounds.width - saveButton.frame.width) / 2, y: (bounds.midY - gap / 2 - saveButton.frame.height).rounded()))
        badge.sizeToFit()
        badge.setFrameOrigin(CGPoint(x: bounds.width - badge.frame.width - Self.inset, y: Self.inset))
        feedback.sizeToFit()
        feedback.setFrameSize(CGSize(width: feedback.frame.width + 20, height: 26))
        feedback.setFrameOrigin(CGPoint(x: (bounds.width - feedback.frame.width) / 2, y: (bounds.height - feedback.frame.height) / 2))
    }

    private func configureLabel(_ label: NSTextField, size: CGFloat) {
        label.font = .monospacedDigitSystemFont(ofSize: size, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.wantsLayer = true
        label.layer?.backgroundColor = NSColor(white: 0, alpha: 0.6).cgColor
        label.layer?.cornerRadius = 6
    }

    // MARK: - Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        setHovered(true)
    }

    override func mouseExited(with event: NSEvent) {
        setHovered(false)
    }

    /// - Parameter takeKey: become key for the keyboard shortcuts (debug automation passes
    ///   `false` so it never takes keyboard focus from the user's app).
    func setHovered(_ hovered: Bool, takeKey: Bool = true) {
        guard hovered != isHovered else { return }
        isHovered = hovered
        if hovered, takeKey {
            window?.makeKey()
            window?.makeFirstResponder(self)
        } else if !hovered, !isDragging {
            (window as? ThumbnailPanel)?.relinquishKey()
        }
        updateChrome(animated: true)
        card?.hoverChanged(hovered)
    }

    private func updateChrome(animated: Bool) {
        let showControls = isHovered && !feedbackShown
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? 0.15 : 0
            controls.animator().alphaValue = showControls ? 1 : 0
            // The duration badge yields its corner to the delete button.
            badge.animator().alphaValue = showControls || feedbackShown ? 0 : 1
            feedback.animator().alphaValue = feedbackShown ? 1 : 0
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.15 : 0)
        dimLayer.opacity = showControls || feedbackShown ? 0.45 : 0
        CATransaction.commit()
    }

    /// Shows a short confirmation ("Saved", "Copied") over the dimmed image.
    func showFeedback(_ text: String) {
        feedback.stringValue = text
        feedbackShown = true
        layoutContents()
        updateChrome(animated: true)
    }

    // MARK: - Mouse: click, double-click, drag out

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        if event.clickCount == 2 {
            mouseDownEvent = nil
            card?.doubleClicked()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isDragging, let start = mouseDownEvent, let card else { return }
        let distance = hypot(event.locationInWindow.x - start.locationInWindow.x, event.locationInWindow.y - start.locationInWindow.y)
        guard distance >= 3 else { return }
        isDragging = true
        let item = NSDraggingItem(pasteboardWriter: card.item.fileURL as NSURL)
        let contents: Any = image.map { NSImage(cgImage: $0, size: bounds.size) } ?? NSImage(size: bounds.size)
        item.setDraggingFrame(bounds, contents: contents)
        let session = beginDraggingSession(with: [item], event: start, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        card.dragBegan()
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
    }

    // MARK: - Keyboard

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: card?.close() // Esc
        case 49: card?.toggleQuickLook() // Space
        default: super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, let card else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "c": card.copy()
        case "s": card.save()
        case "w": card.close()
        case "e": card.annotate()
        case "\u{7f}", "\u{8}": card.delete() // ⌘⌫
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    // MARK: - Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        card?.makeContextMenu()
    }

    // MARK: - Quick Look

    // Quick Look calls these on the main thread.

    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel?) -> Bool {
        true
    }

    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel?) {
        MainActor.assumeIsolated {
            panel?.dataSource = self
            card?.previewChanged(true)
        }
    }

    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel?) {
        MainActor.assumeIsolated {
            panel?.dataSource = nil
            card?.previewChanged(false)
        }
    }
}

extension ThumbnailView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Copy only: receivers (Finder included) never move the temporary file away.
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isDragging = false
        mouseDownEvent = nil
        let keep = NSEvent.modifierFlags.contains(.option)
        card?.dragEnded(delivered: !operation.isEmpty, keepRequested: keep)
        let mouse = NSEvent.mouseLocation
        if let window, !window.frame.contains(mouse) { setHovered(false) }
    }
}

extension ThumbnailView: @preconcurrency QLPreviewPanelDataSource {
    func numberOfPreviewItems(in panel: QLPreviewPanel?) -> Int {
        card == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel?, previewItemAt index: Int) -> (any QLPreviewItem)? {
        card?.item.fileURL as NSURL?
    }
}
