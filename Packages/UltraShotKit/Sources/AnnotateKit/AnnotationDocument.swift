import CoreGraphics

/// The ordered list of annotations on one canvas (value type; first = bottom-most).
public struct AnnotationDocument: Sendable, Hashable, Codable {
    public private(set) var annotations: [Annotation]

    public init(annotations: [Annotation] = []) {
        self.annotations = annotations
    }

    public var isEmpty: Bool { annotations.isEmpty }

    /// Number for the next counter badge: one more than the highest counter on the canvas,
    /// or 1. Derived, so undo and delete keep it consistent.
    public var nextCounterNumber: Int {
        let highest = annotations.compactMap { annotation -> Int? in
            if case .counter(_, let number) = annotation.kind { return number }
            return nil
        }.max()
        return (highest ?? 0) + 1
    }

    public subscript(id: Annotation.ID) -> Annotation? {
        annotations.first { $0.id == id }
    }

    public func index(of id: Annotation.ID) -> Int? {
        annotations.firstIndex { $0.id == id }
    }

    // MARK: - Editing

    /// Appends on top. An annotation whose id already exists replaces it in place instead.
    public mutating func add(_ annotation: Annotation) {
        if let index = index(of: annotation.id) {
            annotations[index] = annotation
        } else {
            annotations.append(annotation)
        }
    }

    /// Replaces the annotation with the same id. Returns false when it does not exist.
    @discardableResult
    public mutating func update(_ annotation: Annotation) -> Bool {
        guard let index = index(of: annotation.id) else { return false }
        annotations[index] = annotation
        return true
    }

    /// Edits the annotation with `id` in place. Returns false when it does not exist.
    @discardableResult
    public mutating func update(_ id: Annotation.ID, _ change: (inout Annotation) -> Void) -> Bool {
        guard let index = index(of: id) else { return false }
        change(&annotations[index])
        return true
    }

    @discardableResult
    public mutating func remove(_ id: Annotation.ID) -> Annotation? {
        guard let index = index(of: id) else { return nil }
        return annotations.remove(at: index)
    }

    public mutating func removeAll() {
        annotations.removeAll()
    }

    /// Translates the annotation by `offset` canvas points.
    @discardableResult
    public mutating func move(_ id: Annotation.ID, by offset: CGVector) -> Bool {
        update(id) { $0 = $0.moved(by: offset) }
    }

    /// Moves the annotation to the top of the z-order.
    public mutating func bringToFront(_ id: Annotation.ID) {
        guard let index = index(of: id), index != annotations.count - 1 else { return }
        annotations.append(annotations.remove(at: index))
    }

    // MARK: - Hit-testing

    /// The topmost annotation touching `point`, if any. `tolerance` is in canvas points
    /// (use a few screen points converted to canvas points).
    public func hitTest(_ point: CGPoint, tolerance: CGFloat = 4) -> Annotation.ID? {
        annotations.last { $0.contains(point, tolerance: tolerance) }?.id
    }

    /// Painted bounds of the annotation (stroke width and arrow head included).
    public func bounds(of id: Annotation.ID) -> CGRect? {
        self[id]?.bounds
    }

    // MARK: - Handles

    public func handles(for id: Annotation.ID) -> [Handle] {
        self[id]?.handles ?? []
    }

    /// The handle of annotation `id` under `point`, if any (`radius` in canvas points).
    public func handle(at point: CGPoint, for id: Annotation.ID, radius: CGFloat = 6) -> Handle? {
        handles(for: id)
            .filter { CanvasGeometry.distance($0.position, point) <= radius }
            .min { CanvasGeometry.distance($0.position, point) < CanvasGeometry.distance($1.position, point) }
    }

    /// Returns a copy with the drag applied (see `HandleDrag` for the snapshot rule).
    public func applying(handleDrag drag: HandleDrag) -> AnnotationDocument {
        var copy = self
        copy.apply(handleDrag: drag)
        return copy
    }

    public mutating func apply(handleDrag drag: HandleDrag) {
        update(drag.id) { $0 = $0.applying(handle: drag.handle, to: drag.location, constrained: drag.constrained) }
    }
}
