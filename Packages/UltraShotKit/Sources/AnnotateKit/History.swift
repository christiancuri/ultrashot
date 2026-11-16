/// Undo/redo as document snapshots (value type).
///
/// `current` is the committed state. Push once per user action (on mouse-up, on text
/// commit), not on every drag step: keep a transient working copy while dragging.
public struct History: Sendable, Hashable {
    public static let defaultLimit = 100

    public private(set) var current: AnnotationDocument
    private var past: [AnnotationDocument] = []
    private var future: [AnnotationDocument] = []
    public let limit: Int

    public init(_ initial: AnnotationDocument = AnnotationDocument(), limit: Int = History.defaultLimit) {
        current = initial
        self.limit = max(limit, 1)
    }

    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }
    public var undoCount: Int { past.count }

    /// Records `document` as the new current state and clears redo. A push equal to
    /// `current` is ignored so no-op actions do not create empty undo steps.
    public mutating func push(_ document: AnnotationDocument) {
        guard document != current else { return }
        past.append(current)
        if past.count > limit {
            past.removeFirst(past.count - limit)
        }
        future.removeAll()
        current = document
    }

    /// Steps back; returns the new current document, or nil when there is nothing to undo.
    @discardableResult
    public mutating func undo() -> AnnotationDocument? {
        guard let previous = past.popLast() else { return nil }
        future.append(current)
        current = previous
        return current
    }

    /// Steps forward; returns the new current document, or nil when there is nothing to redo.
    @discardableResult
    public mutating func redo() -> AnnotationDocument? {
        guard let next = future.popLast() else { return nil }
        past.append(current)
        current = next
        return current
    }
}
