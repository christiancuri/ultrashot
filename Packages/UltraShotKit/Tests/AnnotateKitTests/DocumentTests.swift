@testable import AnnotateKit
import CoreGraphics
import Foundation
import Testing

struct HandleTests {
    private let style = Annotation.Style()

    @Test func cornerDragResizesRectangle() {
        let rect = Annotation(kind: .rectangle(CGRect(x: 10, y: 10, width: 50, height: 40)), style: style)
        let doc = AnnotationDocument(annotations: [rect])
        #expect(doc.handles(for: rect.id).count == 8)
        let handle = doc.handle(at: CGPoint(x: 61, y: 49), for: rect.id)
        #expect(handle?.kind == .corner(.topRight))

        let dragged = doc.applying(handleDrag: HandleDrag(id: rect.id, handle: .corner(.topRight), location: CGPoint(x: 100, y: 70)))
        #expect(dragged[rect.id]?.kind == .rectangle(CGRect(x: 10, y: 10, width: 90, height: 60)))

        let square = doc.applying(handleDrag: HandleDrag(
            id: rect.id, handle: .corner(.topRight), location: CGPoint(x: 100, y: 70), constrained: true
        ))
        #expect(square[rect.id]?.kind == .rectangle(CGRect(x: 10, y: 10, width: 90, height: 90)))
    }

    @Test func cornerDraggedPastOppositeFlips() {
        let blur = Annotation(kind: .blur(CGRect(x: 10, y: 10, width: 50, height: 40)), style: style)
        let doc = AnnotationDocument(annotations: [blur])
        let dragged = doc.applying(handleDrag: HandleDrag(id: blur.id, handle: .corner(.bottomLeft), location: CGPoint(x: 80, y: 70)))
        #expect(dragged[blur.id]?.kind == .blur(CGRect(x: 60, y: 50, width: 20, height: 20)))
    }

    @Test func edgeDragChangesOneSide() {
        let ellipse = Annotation(kind: .ellipse(CGRect(x: 0, y: 0, width: 40, height: 40)), style: style)
        let doc = AnnotationDocument(annotations: [ellipse])
        let dragged = doc.applying(handleDrag: HandleDrag(id: ellipse.id, handle: .edge(.top), location: CGPoint(x: 999, y: 90)))
        #expect(dragged[ellipse.id]?.kind == .ellipse(CGRect(x: 0, y: 0, width: 40, height: 90)))
    }

    @Test func endpointDragMovesArrowHead() {
        let arrow = Annotation(kind: .arrow(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 50, y: 0)), style: style)
        let doc = AnnotationDocument(annotations: [arrow])
        let handles = doc.handles(for: arrow.id)
        #expect(handles.map(\.kind) == [.lineStart, .lineEnd])

        let moved = doc.applying(handleDrag: HandleDrag(id: arrow.id, handle: .lineEnd, location: CGPoint(x: 30, y: 70)))
        #expect(moved[arrow.id]?.kind == .arrow(start: .zero, end: CGPoint(x: 30, y: 70)))

        let snapped = doc.applying(handleDrag: HandleDrag(
            id: arrow.id, handle: .lineStart, location: CGPoint(x: 52, y: 40), constrained: true
        ))
        guard case .arrow(let start, let end)? = snapped[arrow.id]?.kind else {
            Issue.record("expected arrow")
            return
        }
        #expect(end == CGPoint(x: 50, y: 0))
        #expect(abs(start.x - 50) < 0.0001) // snapped straight up from the fixed head
    }

    @Test func freehandTextAndCounterHaveNoHandles() {
        let kinds: [Annotation.Kind] = [
            .pen(points: [.zero, CGPoint(x: 5, y: 5)]),
            .text(TextContent(string: "a", origin: .zero)),
            .counter(center: .zero, number: 1),
        ]
        for kind in kinds {
            #expect(Annotation(kind: kind).handles.isEmpty)
        }
    }
}

struct HistoryTests {
    private enum Step { case undo, redo }

    /// Mutating calls cannot appear inside `#expect`.
    private func step(_ history: inout History, _ step: Step) -> AnnotationDocument? {
        switch step {
        case .undo: history.undo()
        case .redo: history.redo()
        }
    }

    private func doc(_ count: Int) -> AnnotationDocument {
        AnnotationDocument(annotations: (0..<count).map { index in
            Annotation(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!,
                kind: .counter(center: .zero, number: index + 1)
            )
        })
    }

    @Test func undoRedoWalkSnapshots() {
        var history = History(doc(0))
        #expect(!history.canUndo && !history.canRedo)
        history.push(doc(1))
        history.push(doc(2))
        #expect(step(&history, .undo) == doc(1))
        #expect(step(&history, .undo) == doc(0))
        #expect(step(&history, .undo) == nil)
        #expect(step(&history, .redo) == doc(1))
        #expect(history.current == doc(1))
        #expect(history.canUndo && history.canRedo)
    }

    @Test func newPushClearsRedo() {
        var history = History(doc(0))
        history.push(doc(1))
        history.push(doc(2))
        history.undo()
        #expect(history.canRedo)
        history.push(doc(3))
        #expect(!history.canRedo)
        #expect(step(&history, .redo) == nil)
        #expect(history.current == doc(3))
        #expect(step(&history, .undo) == doc(1))
    }

    @Test func identicalPushIsIgnored() {
        var history = History(doc(1))
        history.push(doc(1))
        #expect(!history.canUndo)
    }

    @Test func historyIsCapped() {
        var history = History(doc(0), limit: 3)
        for count in 1...10 {
            history.push(doc(count))
        }
        #expect(history.undoCount == 3)
        history.undo()
        history.undo()
        #expect(step(&history, .undo) == doc(7))
        #expect(!history.canUndo)
    }

    @Test func historyHasValueSemantics() {
        var original = History(doc(0))
        original.push(doc(1))
        var copy = original
        copy.undo()
        #expect(original.current == doc(1))
        #expect(copy.current == doc(0))
    }
}

struct CounterTests {
    @Test func counterNumbersAutoIncrement() throws {
        var doc = AnnotationDocument()
        #expect(doc.nextCounterNumber == 1)
        for index in 0..<3 {
            var builder = AnnotationBuilder(
                tool: .counter, style: Annotation.Style(), start: CGPoint(x: 20 * index, y: 0),
                counterNumber: doc.nextCounterNumber
            )
            builder.update(to: CGPoint(x: 20 * index, y: 0))
            doc.add(try #require(builder.finish()))
        }
        let numbers = doc.annotations.compactMap { annotation -> Int? in
            if case .counter(_, let number) = annotation.kind { return number }
            return nil
        }
        #expect(numbers == [1, 2, 3])
        #expect(doc.nextCounterNumber == 4)

        // Removing the last badge (or undoing it) gives its number back.
        doc.remove(doc.annotations[2].id)
        #expect(doc.nextCounterNumber == 3)
    }

    @Test func documentEditing() {
        var doc = AnnotationDocument()
        var line = Annotation(kind: .line(start: .zero, end: CGPoint(x: 10, y: 10)))
        doc.add(line)
        line.style.lineWidth = 9
        let updated = doc.update(line)
        #expect(updated)
        #expect(doc[line.id]?.style.lineWidth == 9)
        let missing = doc.update(Annotation(kind: .counter(center: .zero, number: 1)))
        #expect(!missing)
        let removed = doc.remove(line.id)
        #expect(removed == line)
        #expect(doc.isEmpty)
    }

    @Test func textFontSizeChangesAfterCommit() {
        var doc = AnnotationDocument()
        let text = Annotation(kind: .text(TextContent(string: "Note", origin: CGPoint(x: 0, y: 100), fontSize: 16)))
        doc.add(text)
        let before = doc.bounds(of: text.id)!
        doc.update(text.id) { annotation in
            if case .text(var content) = annotation.kind {
                content.fontSize = 32
                annotation.kind = .text(content)
            }
        }
        let after = doc.bounds(of: text.id)!
        #expect(after.width > before.width * 1.8)
        #expect(after.maxY == before.maxY) // the top-left stays put
    }
}

struct ToolTests {
    @Test func shortcutsAreUniqueAndRoundTrip() {
        let keys = Tool.allCases.map(\.shortcutKey)
        #expect(Set(keys).count == keys.count)
        #expect(String(keys) == "plaromtbn")
        for tool in Tool.allCases {
            #expect(Tool(shortcutKey: Character(tool.shortcutKey.uppercased())) == tool)
        }
        #expect(Tool(shortcutKey: "z") == nil)
    }

    @Test @MainActor func symbolsExist() {
        for tool in Tool.allCases {
            #expect(NSImageSymbolCheck.exists(tool.symbolName), "\(tool.symbolName)")
        }
    }

    @Test func paletteDefaultsToRed() {
        #expect(Palette.colors.count == 8)
        #expect(Palette.colors.first == Palette.defaultColor)
        #expect(Annotation.Style().color == Palette.red)
    }
}
