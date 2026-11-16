import CoreGraphics

/// Who gets a mouse press in the annotation overlay: the annotation canvas or the
/// selection underneath it.
///
/// The rule (Lightshot-like):
/// 1. No selection yet → the selection (the user drags one first).
/// 2. A handle of the selected annotation → the canvas (resize / endpoint drag).
/// 3. A handle of the selection → the selection (it stays resizable with any tool).
/// 4. Outside the selection → the selection (drag a new one).
/// 5. Inside, with a tool chosen or on an existing annotation → the canvas (draw, or
///    select and move the object).
/// 6. Inside, no tool, empty spot → the selection (drag moves it).
public enum PointerRouting {
    public enum Target: Sendable, Equatable {
        case canvas
        case selection
    }

    public struct Context: Sendable, Equatable {
        public var selection: CGRect?
        public var toolActive: Bool
        public var hitsAnnotation: Bool
        public var hitsAnnotationHandle: Bool
        public var hitsSelectionHandle: Bool

        public init(
            selection: CGRect?,
            toolActive: Bool,
            hitsAnnotation: Bool = false,
            hitsAnnotationHandle: Bool = false,
            hitsSelectionHandle: Bool = false
        ) {
            self.selection = selection
            self.toolActive = toolActive
            self.hitsAnnotation = hitsAnnotation
            self.hitsAnnotationHandle = hitsAnnotationHandle
            self.hitsSelectionHandle = hitsSelectionHandle
        }
    }

    /// `point` and `context.selection` share one coordinate space.
    public static func target(for point: CGPoint, in context: Context) -> Target {
        guard let selection = context.selection else { return .selection }
        if context.hitsAnnotationHandle { return .canvas }
        if context.hitsSelectionHandle { return .selection }
        guard selection.contains(point) else { return .selection }
        return context.toolActive || context.hitsAnnotation ? .canvas : .selection
    }
}
