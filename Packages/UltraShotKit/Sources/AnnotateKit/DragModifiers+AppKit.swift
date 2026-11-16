import AppKit

extension DragModifiers {
    /// Maps the event modifier flags that matter while drawing.
    public init(_ flags: NSEvent.ModifierFlags) {
        self = flags.contains(.shift) ? .shift : []
    }
}
