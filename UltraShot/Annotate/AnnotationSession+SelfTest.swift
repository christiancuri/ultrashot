#if DEBUG
import AnnotateKit
import AppKit

/// `ULTRASHOT_DEBUG_ANNOTATE_SCRIPT=selftest`: drives the interaction code with NSEvent
/// objects handed straight to the handlers (nothing is posted to the system, so the real
/// cursor and other apps are untouched) and logs PASS/FAIL per check.
extension AnnotationSession {
    func debugSelfTest() {
        guard let canvas, let view = selectionView, let window = view.window, let selection = view.selection else {
            Log.annotate.error("selftest: no session")
            return
        }
        let driver = SelfTestDriver(session: self, canvas: canvas, view: view, window: window)
        let center = CGPoint(x: selection.midX, y: selection.midY)
        if let id = driver.checkRoutingAndDrawing(selection: selection, center: center) {
            driver.checkEditing(id)
        }
        driver.checkCountersTextAndEscape(center: center)
        Log.annotate.info("selftest done: \(driver.failures) failure(s)")
    }
}

@MainActor
private final class SelfTestDriver {
    let session: AnnotationSession
    let canvas: AnnotationCanvasView
    let view: SelectionView
    let window: NSWindow
    private(set) var failures = 0

    private var editor: AnnotationEditor { session.editor }

    init(session: AnnotationSession, canvas: AnnotationCanvasView, view: SelectionView, window: NSWindow) {
        self.session = session
        self.canvas = canvas
        self.view = view
        self.window = window
    }

    // MARK: - Phases

    /// Routing, tool shortcut, Shift-constrained drawing. Returns the drawn rectangle.
    func checkRoutingAndDrawing(selection: CGRect, center: CGPoint) -> Annotation.ID? {
        check("no tool: inside routes to selection", canvas.hitTest(center) == nil)
        press("r", code: 15)
        check("R picks rectangle", editor.tool == .rectangle)
        check("tool: inside routes to canvas", canvas.hitTest(center) === canvas)
        check("tool: outside routes to selection", canvas.hitTest(CGPoint(x: selection.minX - 20, y: selection.minY - 20)) == nil)
        check("tool: selection corner routes to selection", canvas.hitTest(CGPoint(x: selection.maxX, y: selection.maxY)) == nil)

        let count = editor.document.annotations.count
        drag(from: CGPoint(x: center.x - 100, y: center.y - 60), to: CGPoint(x: center.x - 20, y: center.y - 10), shift: true)
        let drawn = editor.document.annotations.last
        check("drag draws one rectangle", editor.document.annotations.count == count + 1)
        if case .rectangle(let rect)? = drawn?.kind {
            check("shift makes it square (\(Int(rect.width))x\(Int(rect.height)))", rect.width == rect.height)
        } else {
            check("drawn object is a rectangle", false)
        }
        check("undo enabled after drawing", editor.canUndo)
        return drawn?.id
    }

    /// Select, move, resize, size step, color, delete, undo / redo.
    func checkEditing(_ id: Annotation.ID) {
        press("\u{1b}", code: SelectionView.KeyCode.escape)
        check("Esc drops the tool", editor.tool == nil)
        guard let before = editor.document[id]?.bounds else { return }
        let edge = CGPoint(x: before.minX + 2, y: before.midY)
        check("no tool: object outline routes to canvas", canvas.hitTest(edge) === canvas)
        drag(from: edge, to: CGPoint(x: edge.x + 30, y: edge.y + 15))
        check("click selects the object", editor.selectedID == id)
        let moved = editor.document[id]?.bounds ?? .null
        check("drag moves it by (30, 15)", abs(moved.minX - before.minX - 30) < 0.01 && abs(moved.minY - before.minY - 15) < 0.01)

        let corner = CGPoint(x: moved.maxX - 2, y: moved.maxY - 2)
        drag(from: corner, to: CGPoint(x: corner.x + 40, y: corner.y + 40))
        check("corner handle grows it", (editor.document[id]?.bounds.width ?? 0) > moved.width + 30)

        let grown = editor.document[id]?.bounds
        let scrollWidth = editor.document[id]?.style.lineWidth ?? 0
        session.applyScrollSize(steps: 3)
        check("scroll resizes the selected object", editor.document[id]?.style.lineWidth != scrollWidth)
        if let event = key("z", code: 6, flags: [.command]) { _ = session.handleKeyEquivalent(event) }
        check("⌘Z right after a scroll undoes only the resize",
              editor.document[id]?.style.lineWidth == scrollWidth && editor.document[id]?.bounds == grown)

        let width = editor.document[id]?.style.lineWidth ?? 0
        editor.adjustSize(steps: 2)
        check("size step on the selected object", editor.document[id]?.style.lineWidth == width + 2)
        editor.setColor(Palette.blue)
        check("color applies to the selected object", editor.document[id]?.style.color == Palette.blue)
        press("\u{7f}", code: 51)
        check("Delete removes it", editor.document[id] == nil)
        if let event = key("z", code: 6, flags: [.command]) { _ = session.handleKeyEquivalent(event) }
        check("⌘Z restores it", editor.document[id] != nil)
        if let event = key("z", code: 6, flags: [.command, .shift]) { _ = session.handleKeyEquivalent(event) }
        check("⇧⌘Z deletes it again", editor.document[id] == nil)
    }

    /// Counter numbering, text placement and commit, the end of the Esc chain.
    func checkCountersTextAndEscape(center: CGPoint) {
        editor.tool = .counter
        drag(from: center, to: center)
        drag(from: CGPoint(x: center.x + 40, y: center.y), to: CGPoint(x: center.x + 40, y: center.y))
        let numbers = editor.document.annotations.compactMap { annotation -> Int? in
            if case .counter(_, let number) = annotation.kind { return number }
            return nil
        }
        check("counters number themselves \(numbers)", numbers == [1, 2])

        editor.tool = .text
        let textPoint = CGPoint(x: center.x - 150, y: center.y + 100)
        drag(from: textPoint, to: textPoint)
        check("text tool opens an editor", canvas.isEditingText)
        canvas.textEditing?.textView.insertText("Typed", replacementRange: NSRange(location: NSNotFound, length: 0))
        canvas.endTextEditing()
        if case .text(let content)? = editor.document.annotations.last?.kind {
            check("committed text \"\(content.string)\" at the click", content.string == "Typed")
        } else {
            check("text committed", false)
        }

        press("\u{1b}", code: SelectionView.KeyCode.escape)
        if let event = key("\u{1b}", code: SelectionView.KeyCode.escape) {
            check("last Esc falls through to close", session.handleKeyDown(event) == false)
        }
    }

    // MARK: - Helpers

    private func check(_ name: String, _ condition: Bool) {
        if !condition { failures += 1 }
        Log.annotate.info("selftest \(condition ? "PASS" : "FAIL", privacy: .public): \(name, privacy: .public)")
    }

    private func mouse(_ type: NSEvent.EventType, _ point: CGPoint, shift: Bool = false) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type, location: view.convert(point, to: nil), modifierFlags: shift ? [.shift] : [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1
        )
    }

    /// Mouse down, five drag steps, mouse up (selection-view coordinates).
    private func drag(from start: CGPoint, to end: CGPoint, shift: Bool = false) {
        if let down = mouse(.leftMouseDown, start) { canvas.mouseDown(with: down) }
        for step in 1...5 {
            let t = CGFloat(step) / 5
            let point = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
            if let event = mouse(.leftMouseDragged, point, shift: shift) { canvas.mouseDragged(with: event) }
        }
        if let up = mouse(.leftMouseUp, end, shift: shift) { canvas.mouseUp(with: up) }
    }

    private func key(_ characters: String, code: Int, flags: NSEvent.ModifierFlags = []) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(code)
        )
    }

    private func press(_ characters: String, code: Int) {
        if let event = key(characters, code: code) { _ = session.handleKeyDown(event) }
    }
}
#endif
