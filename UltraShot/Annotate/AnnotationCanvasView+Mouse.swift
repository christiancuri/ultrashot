import AnnotateKit
import AppKit

extension AnnotationCanvasView {
    /// Pointer travel (screen points) before a press counts as a drag.
    static let dragThreshold: CGFloat = 2

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        mouseDownPoint = point
        didDrag = false

        // A press anywhere while typing only ends the text edit.
        if textEditing != nil {
            endTextEditing()
            gesture = .consumed
            return
        }

        if let handle = selectedHandle(at: point), let id = editor.selectedID {
            gesture = .resizing(id: id, handle: handle.kind, snapshot: editor.document)
            return
        }

        if let id = editor.document.hitTest(point, tolerance: tolerance), let hit = editor.document[id] {
            if case .text(let content) = hit.kind, event.clickCount == 2 || editor.tool == .text {
                editor.selectedID = nil
                beginTextEditing(content, style: hit.style, annotationID: id)
                gesture = .consumed
                return
            }
            editor.selectedID = id
            gesture = .moving(id: id, snapshot: editor.document)
            needsDisplay = true
            return
        }

        editor.selectedID = nil
        guard let tool = editor.tool else {
            gesture = .consumed
            return
        }
        if tool == .text {
            beginTextEditing(
                TextContent(string: "", origin: point, fontSize: editor.fontSize),
                style: editor.style,
                annotationID: nil
            )
            gesture = .consumed
            return
        }
        gesture = .creating(AnnotationBuilder(
            tool: tool,
            style: editor.style,
            start: point,
            counterNumber: editor.document.nextCounterNumber,
            fontSize: editor.fontSize
        ))
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let gesture, let start = mouseDownPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        if !didDrag {
            guard hypot(point.x - start.x, point.y - start.y) >= Self.dragThreshold * pointSize else { return }
            didDrag = true
        }
        let modifiers = DragModifiers(event.modifierFlags)
        switch gesture {
        case .creating(var builder):
            builder.update(to: point, modifiers: modifiers)
            self.gesture = .creating(builder)
        case .moving(let id, let snapshot):
            var moved = snapshot
            moved.move(id, by: CGVector(dx: point.x - start.x, dy: point.y - start.y))
            editor.document = moved
        case .resizing(let id, let handle, let snapshot):
            editor.document = snapshot.applying(handleDrag: HandleDrag(
                id: id, handle: handle, location: point, constrained: modifiers.contains(.shift)
            ))
        case .consumed:
            return
        }
        needsDisplay = true
        cursor(at: point).set()
    }

    override func mouseUp(with event: NSEvent) {
        let finished = gesture
        gesture = nil
        mouseDownPoint = nil
        defer {
            didDrag = false
            needsDisplay = true
            cursor(at: convert(event.locationInWindow, from: nil)).set()
        }
        switch finished {
        case .creating(var builder):
            builder.update(to: convert(event.locationInWindow, from: nil), modifiers: DragModifiers(event.modifierFlags))
            if let annotation = builder.finish() {
                editor.add(annotation)
            }
        case .moving, .resizing:
            // A click without travel only selects.
            if didDrag { editor.commit() }
        case .consumed, nil:
            break
        }
    }

    override func scrollWheel(with event: NSEvent) {
        // Scrolling is handled session-wide (a local event monitor); never scroll anything.
    }
}
