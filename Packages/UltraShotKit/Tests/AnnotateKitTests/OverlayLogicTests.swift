@testable import AnnotateKit
import CoreGraphics
import Testing

struct ToolbarLayoutTests {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let toolSize = CGSize(width: 36, height: 380)
    private let actionSize = CGSize(width: 110, height: 36)

    private func layout(_ selection: CGRect) -> ToolbarLayout {
        ToolbarLayout.compute(selection: selection, bounds: screen, toolStripSize: toolSize, actionStripSize: actionSize, gap: 6, margin: 4)
    }

    @Test func preferredLShape() {
        let selection = CGRect(x: 400, y: 200, width: 500, height: 400)
        let result = layout(selection)
        #expect(result.toolSide == .right)
        #expect(result.actionSide == .below)
        // Right of the selection, bottom-aligned with it.
        #expect(result.toolStrip == CGRect(x: 906, y: 200, width: 36, height: 380))
        // Below the selection, right-aligned with it.
        #expect(result.actionStrip == CGRect(x: 790, y: 158, width: 110, height: 36))
        #expect(!result.toolStrip.intersects(result.actionStrip))
    }

    @Test func toolStripFlipsLeftAtRightEdge() {
        let result = layout(CGRect(x: 900, y: 200, width: 540, height: 400))
        #expect(result.toolSide == .left)
        #expect(result.toolStrip.maxX == 894)
        #expect(result.actionStrip.maxX <= screen.maxX - 4)
    }

    @Test func actionStripFlipsAboveAtBottomEdge() {
        let selection = CGRect(x: 400, y: 0, width: 500, height: 300)
        let result = layout(selection)
        #expect(result.actionSide == .above)
        #expect(result.actionStrip.minY == 306)
        // The tool strip is clamped inside the screen.
        #expect(result.toolStrip.minY == 4)
    }

    @Test func fullScreenSelectionPutsBothInsideWithoutOverlap() {
        let result = layout(screen)
        #expect(result.toolSide == .inside)
        #expect(result.actionSide == .inside)
        #expect(screen.contains(result.toolStrip))
        #expect(screen.contains(result.actionStrip))
        #expect(!result.toolStrip.intersects(result.actionStrip))
        #expect(result.toolStrip.maxX == screen.maxX - 6)
    }

    @Test func shortSelectionKeepsToolStripOnScreen() {
        // Tool strip is taller than the selection and the selection hugs the top.
        let result = layout(CGRect(x: 300, y: 700, width: 300, height: 196))
        #expect(result.toolStrip.maxY <= screen.maxY - 4)
        #expect(screen.contains(result.actionStrip))
    }

    @Test func respectsScreenOrigin() {
        // Bounds that do not start at zero (e.g. limited to an image rect).
        let bounds = CGRect(x: 100, y: 50, width: 800, height: 600)
        let result = ToolbarLayout.compute(
            selection: CGRect(x: 100, y: 50, width: 800, height: 600),
            bounds: bounds, toolStripSize: toolSize, actionStripSize: actionSize
        )
        #expect(bounds.contains(result.toolStrip))
        #expect(bounds.contains(result.actionStrip))
    }
}

struct PointerRoutingTests {
    private let selection = CGRect(x: 100, y: 100, width: 300, height: 200)

    @Test func noSelectionGoesToSelection() {
        #expect(PointerRouting.target(for: CGPoint(x: 150, y: 150), in: .init(selection: nil, toolActive: true)) == .selection)
    }

    @Test func toolActiveDrawsInside() {
        let inside = CGPoint(x: 200, y: 200)
        #expect(PointerRouting.target(for: inside, in: .init(selection: selection, toolActive: true)) == .canvas)
        #expect(PointerRouting.target(for: inside, in: .init(selection: selection, toolActive: false)) == .selection)
        #expect(PointerRouting.target(for: inside, in: .init(selection: selection, toolActive: false, hitsAnnotation: true)) == .canvas)
    }

    @Test func outsideAlwaysGoesToSelection() {
        let outside = CGPoint(x: 50, y: 50)
        #expect(PointerRouting.target(for: outside, in: .init(selection: selection, toolActive: true, hitsAnnotation: true)) == .selection)
    }

    @Test func handlesPriority() {
        let corner = CGPoint(x: 400, y: 300)
        #expect(PointerRouting.target(for: corner, in: .init(selection: selection, toolActive: true, hitsSelectionHandle: true)) == .selection)
        #expect(PointerRouting.target(
            for: corner, in: .init(selection: selection, toolActive: true, hitsAnnotationHandle: true, hitsSelectionHandle: true)
        ) == .canvas)
    }
}

struct CanvasMappingTests {
    @Test func identityForFullScreen() {
        let mapping = CanvasMapping(displayRect: CGRect(x: 0, y: 0, width: 1440, height: 900), canvasSize: CGSize(width: 1440, height: 900))
        let rect = CGRect(x: 10, y: 20, width: 30, height: 40)
        #expect(mapping.canvasRect(fromView: rect) == rect)
        #expect(mapping.viewRect(fromCanvas: rect) == rect)
        // 2x screen: canvas (10, 20, 30, 40) → top-left pixels (20, (900 - 60) * 2, 60, 80).
        #expect(mapping.cropPixelRect(forViewSelection: rect, imageScale: 2) == CGRect(x: 20, y: 1680, width: 60, height: 80))
    }

    @Test func scaledImageDisplay() {
        // A 2000x1000 pt image shown at half size, centered at (100, 50).
        let mapping = CanvasMapping(displayRect: CGRect(x: 100, y: 50, width: 1000, height: 500), canvasSize: CGSize(width: 2000, height: 1000))
        #expect(mapping.canvasPoint(fromView: CGPoint(x: 600, y: 300)) == CGPoint(x: 1000, y: 500))
        let canvasRect = mapping.canvasRect(fromView: CGRect(x: 100, y: 50, width: 500, height: 250))
        #expect(canvasRect == CGRect(x: 0, y: 0, width: 1000, height: 500))
        #expect(mapping.viewRect(fromCanvas: canvasRect) == CGRect(x: 100, y: 50, width: 500, height: 250))
        // Bottom-left quarter of a 1x image → pixels (0, 500, 1000, 500) top-left.
        #expect(mapping.cropPixelRect(forViewSelection: CGRect(x: 100, y: 50, width: 500, height: 250), imageScale: 1)
            == CGRect(x: 0, y: 500, width: 1000, height: 500))
    }

    @Test func selectionOutsideCanvasHasNoCrop() {
        let mapping = CanvasMapping(displayRect: CGRect(x: 100, y: 100, width: 200, height: 200), canvasSize: CGSize(width: 200, height: 200))
        #expect(mapping.cropPixelRect(forViewSelection: CGRect(x: 0, y: 0, width: 50, height: 50), imageScale: 2) == nil)
        // Partially outside: clipped to the canvas.
        #expect(mapping.cropPixelRect(forViewSelection: CGRect(x: 50, y: 250, width: 100, height: 100), imageScale: 1)
            == CGRect(x: 0, y: 0, width: 50, height: 50))
    }
}

struct SizeAdjustmentTests {
    @Test func strokeAndFontSteps() {
        let line = Annotation(kind: .line(start: .zero, end: CGPoint(x: 10, y: 0)), style: .init(lineWidth: 4))
        #expect(line.adjustingSize(steps: 3).style.lineWidth == 7)
        #expect(line.adjustingSize(steps: -10).style.lineWidth == Annotation.Style.lineWidthRange.lowerBound)
        let text = Annotation(kind: .text(TextContent(string: "a", origin: .zero, fontSize: 20)))
        #expect(text.adjustingSize(steps: 2).displayedSize == 24)
        #expect(text.adjustingSize(steps: 2).style == text.style)
        #expect(text.adjustingSize(steps: 500).displayedSize == TextContent.fontSizeRange.upperBound)
    }

    @Test func scrollStepperAccumulatesPreciseDeltas() {
        var stepper = ScrollStepper(threshold: 8)
        #expect(stepper.steps(deltaY: 3, precise: true) == 0)
        #expect(stepper.steps(deltaY: 6, precise: true) == 1)
        #expect(stepper.steps(deltaY: 16, precise: true) == 2)
        #expect(stepper.steps(deltaY: -0.4, precise: false) == -1)
        #expect(stepper.steps(deltaY: 0, precise: false) == 0)
    }
}

struct FittedMappingTests {
    private let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)

    @Test func smallImageShowsAtPointSizeCentered() {
        let mapping = CanvasMapping.fitted(canvasSize: CGSize(width: 400, height: 300), in: visible)
        #expect(mapping.displayRect == CGRect(x: 520, y: 287.5, width: 400, height: 300))
        #expect(mapping.canvasPerView == CGSize(width: 1, height: 1))
    }

    @Test func largeImageFitsNinetyPercent() {
        let mapping = CanvasMapping.fitted(canvasSize: CGSize(width: 2880, height: 1800), in: visible)
        #expect(mapping.displayRect.width <= 1440 * 0.9 + 0.5)
        #expect(mapping.displayRect.height <= 875 * 0.9 + 0.5)
        #expect(abs(mapping.displayRect.midX - visible.midX) <= 0.5)
        // Aspect ratio kept.
        #expect(abs(mapping.displayRect.width / mapping.displayRect.height - 1.6) < 0.01)
    }
}
