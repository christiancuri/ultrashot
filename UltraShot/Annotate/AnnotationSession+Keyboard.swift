import AnnotateKit
import AppKit

/// Keyboard handling. Plain keys reach the session through the selection view's
/// `onKeyDown` (it stays first responder; the canvas and toolbars never take focus);
/// ⌘-shortcuts arrive through the canvas' `performKeyEquivalent`. While a text is being
/// edited its text view is first responder and gets every key instead.
///
/// - P L A R O M T B N: pick a tool (again: back to no tool).
/// - Esc steps back: close the palette → deselect the object → drop the tool → close.
/// - Delete / Backspace: delete the selected object. Arrows nudge it (⇧ = 10 pt), or the
///   selection when nothing is selected.
/// - ↩ (selection view) and ⌘C copy, ⌘S saves, ⌘Z / ⇧⌘Z undo / redo, ⌘W closes.
extension AnnotationSession {
    private enum Key {
        static let delete = 51
        static let forwardDelete = 117
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard selectionView?.mode == .adjust else { return false }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch Int(event.keyCode) {
        case SelectionView.KeyCode.escape:
            return stepBack()
        case Key.delete, Key.forwardDelete:
            guard editor.selectedID != nil else { return false }
            editor.deleteSelected()
            return true
        case SelectionView.KeyCode.leftArrow, SelectionView.KeyCode.rightArrow,
             SelectionView.KeyCode.downArrow, SelectionView.KeyCode.upArrow:
            guard editor.selectedID != nil else { return false }
            editor.nudgeSelected(by: nudge(for: event))
            return true
        default:
            break
        }
        guard modifiers.isDisjoint(with: [.command, .control, .option]),
              let key = event.charactersIgnoringModifiers?.first,
              let tool = Tool(shortcutKey: key) else { return false }
        editor.tool = editor.tool == tool ? nil : tool
        return true
    }

    func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        switch (modifiers, key) {
        case ([.command], "c"): copy()
        case ([.command], "s"): save()
        case ([.command], "z"): undo()
        case ([.command, .shift], "z"): redo()
        case ([.command], "w"): finish(.cancelled)
        default: return false
        }
        return true
    }

    /// Esc: undoes one level of focus; `false` when there is nothing left (closes).
    private func stepBack() -> Bool {
        if toolbars.isShowingPalette {
            toolbars.closePopover()
            return true
        }
        if editor.selectedID != nil {
            editor.selectedID = nil
            return true
        }
        if editor.tool != nil {
            editor.tool = nil
            return true
        }
        return false
    }

    private func nudge(for event: NSEvent) -> CGVector {
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        return switch Int(event.keyCode) {
        case SelectionView.KeyCode.leftArrow: CGVector(dx: -step, dy: 0)
        case SelectionView.KeyCode.rightArrow: CGVector(dx: step, dy: 0)
        case SelectionView.KeyCode.downArrow: CGVector(dx: 0, dy: -step)
        default: CGVector(dx: 0, dy: step)
        }
    }
}
