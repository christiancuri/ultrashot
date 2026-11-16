import AnnotateKit
import AppKit

/// One annotation session on one screen: an adjust-mode ``OverlaySession`` (frozen image,
/// resizable selection) with the annotation canvas and the two toolbars as accessories.
///
/// Mouse split (see `PointerRouting`): selection handles always resize the selection and
/// drags outside it draw a new one; inside, a chosen tool draws and existing objects can
/// be grabbed. With no tool (the initial state, like Lightshot) a drag inside moves the
/// selection. Annotations live in the base image's canvas, so they stay put on screen
/// while the selection moves; the export is cropped to the selection.
@MainActor
final class AnnotationSession {
    struct Configuration {
        let screen: NSScreen
        /// What the overlay shows full screen (the frozen screen, or a composite with the
        /// file image centered).
        let displayBackground: CGImage
        /// The image annotations are drawn on and exported from.
        let base: CGImage
        /// Base pixels per canvas point.
        let baseScale: CGFloat
        /// Where the base is shown, in the overlay view's coordinates.
        let canvasFrame: CGRect
        /// The selection may not leave this rect (the image, in file mode).
        let selectionLimit: CGRect?
        let initialSelection: CGRect?
        /// Dim outside the selection (`nil` = the overlay default).
        var dimAlpha: CGFloat?
    }

    let configuration: Configuration
    let editor = AnnotationEditor()
    /// Called once the session has closed (after the completion).
    var onFinish: (() -> Void)?

    private(set) var overlay: OverlaySession?
    private(set) var canvas: AnnotationCanvasView?
    let toolbars = AnnotationToolbars()
    private let sizeIndicator = SizeIndicatorView()
    private let completion: @MainActor (AnnotationOutcome) -> Void
    private var scrollMonitor: Any?
    private var scrollStepper = ScrollStepper()
    private var scrollCommitTask: Task<Void, Never>?
    /// The object the pending scroll commit resizes.
    private var scrollCommitTarget: Annotation.ID?
    private var lastSelection: CGRect?
    private var isFinished = false

    init(configuration: Configuration, completion: @escaping @MainActor (AnnotationOutcome) -> Void) {
        self.configuration = configuration
        self.completion = completion
    }

    var selectionView: SelectionView? {
        overlay?.view(for: configuration.screen)
    }

    // MARK: - Lifecycle

    func show() {
        let config = configuration
        let overlay = OverlaySession(mode: config.initialSelection == nil ? .create : .adjust, screens: [config.screen]) { _ in
            config.displayBackground
        }
        self.overlay = overlay
        overlay.show()
        guard let view = overlay.view(for: config.screen) else {
            Log.annotate.error("annotation overlay has no view")
            finish(.cancelled)
            return
        }

        let canvasSize = CGSize(width: CGFloat(config.base.width) / config.baseScale, height: CGFloat(config.base.height) / config.baseScale)
        let canvas = AnnotationCanvasView(frame: config.canvasFrame, canvasSize: canvasSize, baseImage: config.base, editor: editor)
        canvas.selectionProvider = { [weak view] in view?.selection }
        canvas.onKeyEquivalent = { [weak self] event in self?.handleKeyEquivalent(event) ?? false }
        self.canvas = canvas
        // The size label shows base pixels.
        view.scale = config.baseScale * CanvasMapping(displayRect: config.canvasFrame, canvasSize: canvasSize).canvasPerView.width
        view.dimAlpha = config.dimAlpha
        view.addAccessoryView(canvas)
        toolbars.install(in: view)
        view.addAccessoryView(sizeIndicator)

        wireOverlay(overlay)
        wireToolbars()
        editor.onChange = { [weak self] in self?.editorChanged() }
        installScrollMonitor()

        if let initial = config.initialSelection {
            view.selection = clampToLimit(initial, previous: nil)
        }
        selectionDidChange()
        editorChanged()
        Log.annotate.info("annotation session shown (canvas \(Int(canvasSize.width))x\(Int(canvasSize.height)) pt, scale \(config.baseScale))")
    }

    /// Ends the session with `outcome`. Safe to call more than once.
    func finish(_ outcome: AnnotationOutcome) {
        guard !isFinished else { return }
        isFinished = true
        canvas?.endTextEditing()
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
        scrollCommitTask?.cancel()
        toolbars.closePopover()
        ColorPanelBridge.shared.dismiss()
        overlay?.onCancel = nil
        overlay?.close()
        overlay = nil
        switch outcome {
        case .copy: Log.annotate.info("annotation finished: copy")
        case .save: Log.annotate.info("annotation finished: save")
        case .cancelled: Log.annotate.info("annotation finished: cancelled")
        }
        completion(outcome)
        onFinish?()
    }

    // MARK: - Export

    /// The selection flattened at the base image's full resolution.
    func exportImage() -> CGImage? {
        guard let canvas, let selection = selectionView?.selection else { return nil }
        canvas.endTextEditing()
        let mapping = CanvasMapping(displayRect: canvas.frame, canvasSize: canvas.canvasSize)
        guard let crop = mapping.cropPixelRect(forViewSelection: selection, imageScale: configuration.baseScale) else { return nil }
        return AnnotationRenderer.export(
            base: configuration.base,
            scale: configuration.baseScale,
            cropPixelRect: crop,
            annotations: editor.document.annotations
        )
    }

    func copy() {
        guard let image = exportImage() else {
            Log.annotate.error("copy: nothing to export")
            NSSound.beep()
            return
        }
        finish(.copy(image))
    }

    func save() {
        guard let image = exportImage() else {
            Log.annotate.error("save: nothing to export")
            NSSound.beep()
            return
        }
        finish(.save(image))
    }

    // MARK: - Wiring

    private func wireOverlay(_ overlay: OverlaySession) {
        overlay.onSelectionChanged = { [weak self] view, rect in
            guard let self else { return }
            if let rect {
                let clamped = clampToLimit(rect, previous: lastSelection)
                if clamped != rect { view.selection = clamped }
            }
            selectionDidChange()
        }
        overlay.onCommit = { [weak self] view, _ in
            guard let self else { return }
            if view.mode == .create {
                // The first selection is drawn: switch to adjusting it.
                view.mode = .adjust
                selectionDidChange()
            } else {
                copy()
            }
        }
        overlay.onCancel = { [weak self] in self?.finish(.cancelled) }
        overlay.onKeyDown = { [weak self] _, event in self?.handleKeyDown(event) ?? false }
        overlay.onMouseMoved = { [weak self] view, point in
            guard let self, let canvas, canvas.hitTest(point) === canvas else { return }
            canvas.cursor(at: canvas.convert(point, from: view)).set()
        }
    }

    private func wireToolbars() {
        toolbars.onTool = { [weak self] tool in
            guard let self else { return }
            canvas?.endTextEditing()
            flushScrollCommit()
            editor.tool = editor.tool == tool ? nil : tool
        }
        toolbars.onPickColor = { [weak self] color in
            guard let self else { return }
            canvas?.setEditingColor(color)
            editor.setColor(color)
        }
        toolbars.onUndo = { [weak self] in self?.undo() }
        toolbars.onRedo = { [weak self] in self?.redo() }
        toolbars.onCopy = { [weak self] in self?.copy() }
        toolbars.onSave = { [weak self] in self?.save() }
        toolbars.onClose = { [weak self] in self?.finish(.cancelled) }
    }

    func undo() {
        canvas?.endTextEditing()
        flushScrollCommit()
        editor.undo()
    }

    func redo() {
        canvas?.endTextEditing()
        flushScrollCommit()
        editor.redo()
    }

    private func editorChanged() {
        toolbars.update(tool: editor.tool, color: editor.style.color, canUndo: editor.canUndo, canRedo: editor.canRedo)
        canvas?.needsDisplay = true
    }

    private func selectionDidChange() {
        guard let view = selectionView else { return }
        let selection = view.mode == .adjust ? view.selection : nil
        lastSelection = view.selection
        toolbars.place(around: selection, in: view.bounds)
        canvas?.needsDisplay = true
    }

    /// File mode: keeps the selection on the image. A move is pushed back inside; a resize
    /// or a new rect is cut to the image.
    private func clampToLimit(_ rect: CGRect, previous: CGRect?) -> CGRect {
        guard let limit = configuration.selectionLimit else { return rect }
        if let previous, previous.size == rect.size, rect.width <= limit.width, rect.height <= limit.height {
            return CGRect(
                x: min(max(rect.minX, limit.minX), limit.maxX - rect.width),
                y: min(max(rect.minY, limit.minY), limit.maxY - rect.height),
                width: rect.width,
                height: rect.height
            )
        }
        let cut = rect.intersection(limit)
        return cut.isNull || cut.isEmpty ? (previous ?? limit) : cut
    }

    // MARK: - Scroll wheel

    private func installScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            // Local monitors run on the main thread.
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self, let view = self.selectionView, event.window === view.window else { return false }
                self.handleScroll(event, in: view)
                return true
            }
            return consumed ? nil : event
        }
    }

    private func handleScroll(_ event: NSEvent, in view: SelectionView) {
        guard view.mode == .adjust, view.selection != nil, let canvas else { return }
        let steps = scrollStepper.steps(deltaY: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas)
        guard steps != 0 else { return }
        let value: CGFloat
        if let size = canvas.adjustEditingFontSize(steps: steps) {
            value = size
        } else {
            value = applyScrollSize(steps: steps)
        }
        let point = view.convert(event.locationInWindow, from: nil)
        sizeIndicator.show("\(Int(value.rounded())) pt", near: point, in: view.bounds)
    }

    /// Steps the stroke width (of the selected object, committed once the gesture pauses).
    @discardableResult
    func applyScrollSize(steps: Int) -> CGFloat {
        let value = editor.adjustSize(steps: steps)
        if editor.selectedID != nil { scheduleScrollCommit() }
        return value
    }

    /// One undo step per scroll gesture on a selected object.
    private func scheduleScrollCommit() {
        // Scrolling another object now: the previous object's resize is its own step.
        if scrollCommitTarget != editor.selectedID { flushScrollCommit() }
        scrollCommitTask?.cancel()
        scrollCommitTarget = editor.selectedID
        scrollCommitTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self?.flushScrollCommit()
        }
    }

    /// Commits a pending scroll resize right away (before undo, redo or a tool change), so
    /// ⌘Z right after a scroll undoes the resize instead of dropping it plus one more step.
    private func flushScrollCommit() {
        guard let task = scrollCommitTask else { return }
        task.cancel()
        scrollCommitTask = nil
        scrollCommitTarget = nil
        editor.commit()
    }
}
