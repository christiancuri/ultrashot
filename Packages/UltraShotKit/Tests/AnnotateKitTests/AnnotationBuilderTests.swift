@testable import AnnotateKit
import CoreGraphics
import Testing

struct AnnotationBuilderTests {
    private let style = Annotation.Style()

    @Test func lineFollowsPointerWithoutShift() {
        var builder = AnnotationBuilder(tool: .line, style: style, start: CGPoint(x: 10, y: 10))
        builder.update(to: CGPoint(x: 50, y: 23))
        #expect(builder.annotation.kind == .line(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 50, y: 23)))
    }

    @Test(arguments: [
        (CGPoint(x: 100, y: 8), CGFloat(0)),      // nearly horizontal → 0°
        (CGPoint(x: 90, y: 85), CGFloat(45)),     // near diagonal → 45°
        (CGPoint(x: 5, y: 100), CGFloat(90)),     // nearly vertical → 90°
        (CGPoint(x: -80, y: -70), CGFloat(-135)), // lower-left diagonal
    ])
    func shiftSnapsArrowTo45Degrees(target: CGPoint, expectedDegrees: CGFloat) throws {
        var builder = AnnotationBuilder(tool: .arrow, style: style, start: .zero)
        builder.update(to: target, modifiers: .shift)
        guard case .arrow(let start, let end) = builder.annotation.kind else {
            Issue.record("expected arrow")
            return
        }
        #expect(start == .zero)
        let degrees = atan2(end.y, end.x) * 180 / .pi
        #expect(abs(degrees - expectedDegrees) < 0.001)
        // Length is preserved.
        #expect(abs(hypot(end.x, end.y) - hypot(target.x, target.y)) < 0.001)
    }

    @Test func shiftMakesRectangleSquareAndEllipseCircle() {
        var rect = AnnotationBuilder(tool: .rectangle, style: style, start: CGPoint(x: 10, y: 10))
        rect.update(to: CGPoint(x: 70, y: 30), modifiers: .shift)
        #expect(rect.annotation.kind == .rectangle(CGRect(x: 10, y: 10, width: 60, height: 60)))

        var ellipse = AnnotationBuilder(tool: .ellipse, style: style, start: CGPoint(x: 100, y: 100))
        ellipse.update(to: CGPoint(x: 80, y: 20), modifiers: .shift)
        // Dragging down-left: anchor stays fixed, the square grows toward the pointer.
        #expect(ellipse.annotation.kind == .ellipse(CGRect(x: 20, y: 20, width: 80, height: 80)))
    }

    @Test func withoutShiftRectangleIsFreeAndStandardized() {
        var builder = AnnotationBuilder(tool: .blur, style: style, start: CGPoint(x: 50, y: 50))
        builder.update(to: CGPoint(x: 10, y: 70))
        #expect(builder.annotation.kind == .blur(CGRect(x: 10, y: 50, width: 40, height: 20)))
    }

    @Test func penIgnoresShiftAndDecimatesSamples() {
        var builder = AnnotationBuilder(tool: .pen, style: style, start: .zero)
        // 100 samples 0.5 pt apart: only every third survives the 1.5 pt spacing.
        for step in 1...100 {
            builder.update(to: CGPoint(x: CGFloat(step) * 0.5, y: 0), modifiers: .shift)
        }
        guard case .pen(let live) = builder.annotation.kind else {
            Issue.record("expected pen")
            return
        }
        #expect(live.count < 40)
        #expect(live.first == .zero)
        #expect(live.last == CGPoint(x: 50, y: 0))

        // A straight stroke simplifies down to its endpoints.
        guard case .pen(let finished)? = builder.finish()?.kind else {
            Issue.record("expected finished pen")
            return
        }
        #expect(finished.count == 2)
        #expect(finished.first == .zero)
        #expect(finished.last == CGPoint(x: 50, y: 0))
    }

    @Test func markerKeepsCurveShape() throws {
        var builder = AnnotationBuilder(tool: .marker, style: style, start: CGPoint(x: 0, y: 0))
        for step in 1...60 {
            let angle = CGFloat(step) / 60 * .pi
            builder.update(to: CGPoint(x: 50 - cos(angle) * 50, y: sin(angle) * 50))
        }
        let finished = try #require(builder.finish())
        guard case .marker(let points) = finished.kind else {
            Issue.record("expected marker")
            return
        }
        #expect(points.count > 5)
        #expect(points.contains { $0.y > 45 })
    }

    @Test func clickWithShapeToolIsDiscarded() {
        let builder = AnnotationBuilder(tool: .rectangle, style: style, start: CGPoint(x: 5, y: 5))
        #expect(builder.finish() == nil)
        var arrow = AnnotationBuilder(tool: .arrow, style: style, start: CGPoint(x: 5, y: 5))
        arrow.update(to: CGPoint(x: 6, y: 5))
        #expect(arrow.finish() == nil)
    }

    @Test func clickToolsPlaceAtPointer() throws {
        var counter = AnnotationBuilder(tool: .counter, style: style, start: CGPoint(x: 5, y: 5), counterNumber: 3)
        counter.update(to: CGPoint(x: 40, y: 30))
        let badge = try #require(counter.finish())
        #expect(badge.kind == .counter(center: CGPoint(x: 40, y: 30), number: 3))

        let text = AnnotationBuilder(tool: .text, style: style, start: CGPoint(x: 12, y: 80), fontSize: 24)
        #expect(text.annotation.kind == .text(TextContent(string: "", origin: CGPoint(x: 12, y: 80), fontSize: 24)))
        // Empty text is not committed; the UI adds it after editing.
        #expect(text.finish() == nil)
    }

    @Test func builderKeepsStableID() {
        var builder = AnnotationBuilder(tool: .line, style: style, start: .zero)
        let first = builder.annotation.id
        builder.update(to: CGPoint(x: 30, y: 30))
        #expect(builder.annotation.id == first)
        #expect(builder.finish()?.id == first)
    }
}
