import AnnotateKit
import AppKit

/// Editing state of one annotation session: current tool and style, the working document,
/// the selected object and undo history. Views read it and call its mutations; every
/// change calls ``onChange``.
///
/// `document` is the working copy. Gestures mutate it freely and call ``commit()`` once
/// at the end (mouse up, text commit), which records an undo step.
@MainActor
final class AnnotationEditor {
    /// `nil` = no tool: drags inside the selection move it (Lightshot's initial state).
    var tool: Tool? {
        didSet {
            guard tool != oldValue else { return }
            if tool != nil { selectedID = nil }
            notify()
        }
    }

    /// Color and stroke width for new objects.
    private(set) var style = Annotation.Style()
    /// Font size for new text.
    private(set) var fontSize = TextContent.defaultFontSize

    var document: AnnotationDocument
    private(set) var history: History

    var selectedID: Annotation.ID? {
        didSet { if selectedID != oldValue { notify() } }
    }

    var selectedAnnotation: Annotation? {
        selectedID.flatMap { document[$0] }
    }

    var onChange: (() -> Void)?

    init(document: AnnotationDocument = AnnotationDocument()) {
        self.document = document
        history = History(document)
    }

    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }

    // MARK: - History

    /// Records the working document as one undo step (no-op when unchanged).
    func commit() {
        history.push(document)
        notify()
    }

    /// Drops uncommitted changes of the working document.
    func revert() {
        document = history.current
        notify()
    }

    func undo() {
        guard let previous = history.undo() else { return }
        document = previous
        dropStaleSelection()
        notify()
    }

    func redo() {
        guard let next = history.redo() else { return }
        document = next
        dropStaleSelection()
        notify()
    }

    // MARK: - Objects

    func add(_ annotation: Annotation) {
        document.add(annotation)
        commit()
    }

    func deleteSelected() {
        guard let selectedID else { return }
        document.remove(selectedID)
        self.selectedID = nil
        commit()
    }

    func nudgeSelected(by offset: CGVector) {
        guard let selectedID else { return }
        document.move(selectedID, by: offset)
        commit()
    }

    /// New color for future objects, and for the selected one.
    func setColor(_ color: RGBAColor) {
        style.color = color
        if let selectedID {
            document.update(selectedID) { $0.style.color = color }
            commit()
        } else {
            notify()
        }
    }

    /// Scroll-wheel size change. Applies to the selected object if there is one (call
    /// ``commit()`` when the gesture settles), otherwise to the defaults of the current
    /// tool. Returns the new size for the indicator.
    @discardableResult
    func adjustSize(steps: Int) -> CGFloat {
        if let selected = selectedAnnotation {
            let resized = selected.adjustingSize(steps: steps)
            document.update(resized)
            notify()
            return resized.displayedSize
        }
        if tool == .text {
            fontSize = SizeAdjustment.fontSize(fontSize, steps: steps)
            notify()
            return fontSize
        }
        style.lineWidth = SizeAdjustment.lineWidth(style.lineWidth, steps: steps)
        notify()
        return style.lineWidth
    }

    func setFontSize(_ size: CGFloat) {
        fontSize = size
    }

    private func dropStaleSelection() {
        if let selectedID, document[selectedID] == nil { self.selectedID = nil }
    }

    private func notify() {
        onChange?()
    }
}
