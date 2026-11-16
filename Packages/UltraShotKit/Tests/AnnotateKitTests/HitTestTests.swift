@testable import AnnotateKit
import CoreGraphics
import Testing

struct HitTestTests {
    private let style = Annotation.Style(color: Palette.red, lineWidth: 4)

    @Test func pointNearLineHitsWithinTolerance() {
        let line = Annotation(kind: .line(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0)), style: style)
        let doc = AnnotationDocument(annotations: [line])
        // Half stroke (2) + tolerance (4) = 6.
        #expect(doc.hitTest(CGPoint(x: 50, y: 5.5), tolerance: 4) == line.id)
        #expect(doc.hitTest(CGPoint(x: 50, y: -5.5), tolerance: 4) == line.id)
        #expect(doc.hitTest(CGPoint(x: 50, y: 7), tolerance: 4) == nil)
        #expect(doc.hitTest(CGPoint(x: 120, y: 0), tolerance: 4) == nil)
    }

    @Test func topmostAnnotationWins() {
        let bottom = Annotation(kind: .blur(CGRect(x: 0, y: 0, width: 100, height: 100)), style: style)
        let top = Annotation(kind: .counter(center: CGPoint(x: 50, y: 50), number: 1), style: style)
        var doc = AnnotationDocument(annotations: [bottom, top])
        #expect(doc.hitTest(CGPoint(x: 50, y: 50)) == top.id)
        #expect(doc.hitTest(CGPoint(x: 90, y: 90)) == bottom.id)
        doc.bringToFront(bottom.id)
        #expect(doc.hitTest(CGPoint(x: 50, y: 50)) == bottom.id)
    }

    @Test func rectangleOutlineHitsButHollowInteriorMisses() {
        let rect = Annotation(kind: .rectangle(CGRect(x: 0, y: 0, width: 100, height: 60)), style: style)
        let doc = AnnotationDocument(annotations: [rect])
        #expect(doc.hitTest(CGPoint(x: 100, y: 30)) == rect.id)
        #expect(doc.hitTest(CGPoint(x: 50, y: 30)) == nil)
    }

    @Test func ellipseOutlineHits() {
        let ellipse = Annotation(kind: .ellipse(CGRect(x: 0, y: 0, width: 100, height: 50)), style: style)
        let doc = AnnotationDocument(annotations: [ellipse])
        #expect(doc.hitTest(CGPoint(x: 50, y: 50)) == ellipse.id)
        #expect(doc.hitTest(CGPoint(x: 0, y: 25)) == ellipse.id)
        #expect(doc.hitTest(CGPoint(x: 50, y: 25)) == nil)
    }

    @Test func textUsesLaidOutBounds() {
        let content = TextContent(string: "Hello\nWorld!", origin: CGPoint(x: 10, y: 200), fontSize: 20)
        let text = Annotation(kind: .text(content), style: style)
        let doc = AnnotationDocument(annotations: [text])
        let size = TextLayout.size(for: content)
        #expect(size.height == TextLayout.lineHeight(fontSize: 20) * 2)
        #expect(size.width > 40)
        // The box hangs down from the top-left origin.
        #expect(doc.bounds(of: text.id) == CGRect(x: 10, y: 200 - size.height, width: size.width, height: size.height))
        #expect(doc.hitTest(CGPoint(x: 12, y: 198), tolerance: 0) == text.id)
        #expect(doc.hitTest(CGPoint(x: 12, y: 200 - size.height + 1), tolerance: 0) == text.id)
        #expect(doc.hitTest(CGPoint(x: 12, y: 205), tolerance: 0) == nil)
        #expect(doc.hitTest(CGPoint(x: 10 + size.width + 5, y: 190), tolerance: 0) == nil)
    }

    @Test func textSizeGrowsWithFontSize() {
        let small = TextLayout.size(for: TextContent(string: "Abc", origin: .zero, fontSize: 12))
        let large = TextLayout.size(for: TextContent(string: "Abc", origin: .zero, fontSize: 36))
        #expect(large.width > small.width * 2.5)
        #expect(large.height > small.height * 2.5)
        // Trailing newline adds a line, like a text view caret.
        let trailing = TextLayout.size(for: TextContent(string: "Abc\n", origin: .zero, fontSize: 12))
        #expect(trailing.height == small.height * 2)
    }

    @Test func counterUsesBadgeRadius() {
        let counter = Annotation(kind: .counter(center: CGPoint(x: 50, y: 50), number: 7), style: style)
        let doc = AnnotationDocument(annotations: [counter])
        let radius = style.counterRadius
        #expect(doc.hitTest(CGPoint(x: 50 + radius - 1, y: 50), tolerance: 0) == counter.id)
        #expect(doc.hitTest(CGPoint(x: 50 + radius + 1, y: 50), tolerance: 0) == nil)
        #expect(doc.bounds(of: counter.id) == CGRect(x: 50 - radius, y: 50 - radius, width: radius * 2, height: radius * 2))
    }

    @Test func arrowHeadIsHittableAndInBounds() {
        let arrow = Annotation(kind: .arrow(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0)), style: style)
        let bounds = arrow.bounds
        // The head is wider than the stroke.
        #expect(bounds.maxY > style.lineWidth)
        #expect(bounds.maxX >= 100)
        // Inside the swept head, well off the shaft axis; the same offset along the shaft misses.
        #expect(arrow.contains(CGPoint(x: 82, y: 10), tolerance: 0))
        #expect(!arrow.contains(CGPoint(x: 20, y: 10), tolerance: 0))
    }

    @Test func boundsIncludeStrokeWidth() {
        let rect = Annotation(kind: .rectangle(CGRect(x: 10, y: 10, width: 20, height: 20)), style: style)
        #expect(rect.bounds == CGRect(x: 8, y: 8, width: 24, height: 24))
        let marker = Annotation(kind: .marker(points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)]), style: style)
        #expect(marker.bounds.height == style.markerWidth)
    }

    @Test func moveTranslatesEveryKind() {
        let offset = CGVector(dx: 5, dy: -3)
        let kinds: [Annotation.Kind] = [
            .pen(points: [.zero, CGPoint(x: 10, y: 10)]),
            .marker(points: [.zero, CGPoint(x: 10, y: 10)]),
            .line(start: .zero, end: CGPoint(x: 10, y: 0)),
            .arrow(start: .zero, end: CGPoint(x: 30, y: 0)),
            .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)),
            .ellipse(CGRect(x: 0, y: 0, width: 10, height: 10)),
            .blur(CGRect(x: 0, y: 0, width: 10, height: 10)),
            .text(TextContent(string: "Hi", origin: CGPoint(x: 0, y: 30))),
            .counter(center: .zero, number: 1),
        ]
        for kind in kinds {
            let annotation = Annotation(kind: kind, style: style)
            var doc = AnnotationDocument(annotations: [annotation])
            doc.move(annotation.id, by: offset)
            let moved = doc.bounds(of: annotation.id)!
            #expect(abs(moved.minX - (annotation.bounds.minX + 5)) < 0.0001, "\(kind.tool)")
            #expect(abs(moved.minY - (annotation.bounds.minY - 3)) < 0.0001, "\(kind.tool)")
        }
    }
}
