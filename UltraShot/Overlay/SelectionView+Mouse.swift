import AppKit

extension SelectionView {
    /// What the current mouse drag does.
    enum DragOperation {
        /// Drawing a new rect from `anchor`.
        case creating(anchor: CGPoint)
        /// Moving `original` with the pointer that went down at `start`.
        case moving(start: CGPoint, original: CGRect)
        /// Resizing `original` by one of its handles.
        case resizing(SelectionHandle, original: CGRect)
    }

    /// Pointer travel (points) before a press counts as a drag rather than a click.
    static let dragThreshold: CGFloat = 3

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = SelectionGeometry.clamp(convert(event.locationInWindow, from: nil), to: bounds)
        mouseDownPoint = point
        didDrag = false

        guard mode == .adjust, let selection = currentSelection else {
            drag = .creating(anchor: point)
            return
        }
        if event.clickCount == 2, selection.contains(point) {
            drag = nil
            mouseDownPoint = nil
            onCommit?(selection)
            return
        }
        if let handle = SelectionGeometry.handle(at: point, in: selection, tolerance: Self.handleTolerance) {
            drag = .resizing(handle, original: selection)
        } else if selection.contains(point) {
            drag = .moving(start: point, original: selection)
        } else {
            drag = .creating(anchor: point)
        }
        updateCursor(at: point)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag, let start = mouseDownPoint else { return }
        let point = SelectionGeometry.clamp(convert(event.locationInWindow, from: nil), to: bounds)
        if !didDrag {
            guard hypot(point.x - start.x, point.y - start.y) >= Self.dragThreshold else { return }
            didDrag = true
            onInteractionBegan?()
        }
        let square = event.modifierFlags.contains(.shift)
        let scale = effectiveScale
        let rect: CGRect
        switch drag {
        case .creating(let anchor):
            rect = SelectionGeometry.snap(SelectionGeometry.rect(from: anchor, to: point, square: square, bounds: bounds), scale: scale)
        case .moving(let start, let original):
            let delta = CGVector(dx: point.x - start.x, dy: point.y - start.y)
            rect = SelectionGeometry.snap(SelectionGeometry.move(original, by: delta, in: bounds), scale: scale)
        case .resizing(let handle, let original):
            rect = SelectionGeometry.snap(
                SelectionGeometry.resize(original, handle: handle, to: point, square: square, limits: .init(bounds: bounds, minimumSize: minimumSize)),
                scale: scale
            )
        }
        setSelectionFromUser(rect)
        updateCursor(at: point)
    }

    override func mouseUp(with event: NSEvent) {
        let point = SelectionGeometry.clamp(convert(event.locationInWindow, from: nil), to: bounds)
        let operation = drag
        let wasDrag = didDrag
        drag = nil
        mouseDownPoint = nil
        didDrag = false
        defer { updateCursor(at: point) }

        guard let operation else { return }
        guard wasDrag else {
            handleClick(at: point, operation: operation)
            return
        }
        guard case .creating = operation, let selection = currentSelection else { return }
        let isLargeEnough = selection.width >= minimumSize && selection.height >= minimumSize
        if !isLargeEnough {
            setSelectionFromUser(nil)
        } else if mode == .create {
            onCommit?(selection)
        }
    }

    /// A press without a drag: in create mode or outside the selection it is a click
    /// (window capture); inside the selection it does nothing (first half of a double-click).
    private func handleClick(at point: CGPoint, operation: DragOperation) {
        guard case .creating = operation else { return }
        if mode == .create, currentSelection != nil {
            setSelectionFromUser(nil)
        }
        onClick?(point)
    }
}
