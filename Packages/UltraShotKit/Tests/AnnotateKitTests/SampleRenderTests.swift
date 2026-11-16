import AnnotateKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

/// Renders every tool on a synthetic background for visual review.
/// Runs only when ANNOTATEKIT_SAMPLE_DIR is set:
///   ANNOTATEKIT_SAMPLE_DIR=$PWD swift test --filter SampleRenderTests
struct SampleRenderTests {
    static let outputDirectory = ProcessInfo.processInfo.environment["ANNOTATEKIT_SAMPLE_DIR"]

    @Test(.enabled(if: outputDirectory != nil))
    func renderAllTools() throws {
        let directory = try #require(Self.outputDirectory)
        let scale: CGFloat = 2
        let canvas = CGSize(width: 900, height: 560)
        let base = try #require(Self.background(canvas: canvas, scale: scale))
        let annotations = Self.sampleAnnotations(canvas: canvas)

        let exported = try #require(AnnotationRenderer.export(base: base, scale: scale, annotations: annotations))
        try Self.writePNG(exported, to: URL(fileURLWithPath: directory).appendingPathComponent("annotatekit-sample.png"))

        // Same scene as the on-screen view would draw it, plus selection chrome.
        let ctx = TestImages.context(width: base.width, height: base.height)
        ctx.scaleBy(x: scale, y: scale)
        ctx.draw(base, in: CGRect(origin: .zero, size: canvas))
        AnnotationRenderer.draw(annotations, in: ctx, canvasSize: canvas, baseImage: base, scale: scale)
        for index in [1, 4, 6] {
            AnnotationRenderer.drawSelectionChrome(for: annotations[index], in: ctx)
        }
        let chrome = try #require(ctx.makeImage())
        try Self.writePNG(chrome, to: URL(fileURLWithPath: directory).appendingPathComponent("annotatekit-sample-chrome.png"))
    }

    static func sampleAnnotations(canvas: CGSize) -> [Annotation] {
        let height = canvas.height
        // Helper: author the scene with a top-left origin, convert to canvas (bottom-left).
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: height - y) }
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: x, y: height - y - h, width: w, height: h)
        }
        let red = Annotation.Style(color: Palette.red, lineWidth: 4)
        var squiggle: [CGPoint] = []
        for step in 0...80 {
            let t = CGFloat(step) / 80
            squiggle.append(p(560 + t * 280, 470 + sin(t * .pi * 4) * 28))
        }
        var highlight: [CGPoint] = []
        for step in 0...40 {
            highlight.append(p(46 + CGFloat(step) * 4.6, 133 + sin(CGFloat(step) / 6) * 1.5))
        }
        return [
            Annotation(kind: .marker(points: highlight), style: Annotation.Style(color: Palette.yellow, lineWidth: 5)),
            Annotation(kind: .arrow(start: p(430, 300), end: p(320, 205)), style: red),
            Annotation(kind: .arrow(start: p(650, 120), end: p(780, 70)), style: Annotation.Style(color: Palette.blue, lineWidth: 2)),
            Annotation(kind: .arrow(start: p(500, 380), end: p(700, 330)), style: Annotation.Style(color: Palette.green, lineWidth: 8)),
            Annotation(kind: .rectangle(r(40, 190, 300, 90)), style: red),
            Annotation(kind: .ellipse(r(600, 170, 220, 110)), style: Annotation.Style(color: Palette.orange, lineWidth: 4)),
            Annotation(kind: .blur(r(48, 330, 300, 60)), style: red),
            Annotation(kind: .line(start: p(40, 520), end: p(360, 520)), style: Annotation.Style(color: Palette.purple, lineWidth: 3)),
            Annotation(kind: .pen(points: squiggle), style: red),
            Annotation(
                kind: .text(TextContent(string: "Fix this button\nand the label", origin: p(380, 410), fontSize: 22)),
                style: red
            ),
            Annotation(kind: .counter(center: p(370, 160), number: 1), style: red),
            Annotation(kind: .counter(center: p(860, 230), number: 2), style: Annotation.Style(color: Palette.blue, lineWidth: 4)),
            Annotation(kind: .counter(center: p(40, 460), number: 12), style: Annotation.Style(color: Palette.black, lineWidth: 6)),
            Annotation(kind: .counter(center: p(90, 460), number: 3), style: Annotation.Style(color: Palette.white, lineWidth: 6)),
            Annotation(
                kind: .text(TextContent(string: "White text on dark", origin: p(560, 20), fontSize: 14)),
                style: Annotation.Style(color: Palette.white, lineWidth: 4)
            ),
        ]
    }

    /// Gradient + grid + fake UI text, drawn with a top-left mental model.
    static func background(canvas: CGSize, scale: CGFloat) -> CGImage? {
        let ctx = TestImages.context(width: Int(canvas.width * scale), height: Int(canvas.height * scale))
        ctx.scaleBy(x: scale, y: scale)
        let colors = [CGColor(srgbRed: 0.93, green: 0.95, blue: 0.99, alpha: 1), CGColor(srgbRed: 0.72, green: 0.80, blue: 0.93, alpha: 1)]
        guard let gradient = CGGradient(colorsSpace: TestImages.srgb, colors: colors as CFArray, locations: [0, 1]) else { return nil }
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: canvas.height), end: CGPoint(x: canvas.width, y: 0), options: [])

        ctx.setStrokeColor(CGColor(gray: 0.5, alpha: 0.18))
        ctx.setLineWidth(1)
        for x in stride(from: CGFloat(0), through: canvas.width, by: 30) {
            ctx.strokeLineSegments(between: [CGPoint(x: x, y: 0), CGPoint(x: x, y: canvas.height)])
        }
        for y in stride(from: CGFloat(0), through: canvas.height, by: 30) {
            ctx.strokeLineSegments(between: [CGPoint(x: 0, y: y), CGPoint(x: canvas.width, y: y)])
        }
        // Dark strip top-right to test light-on-dark legibility.
        ctx.setFillColor(CGColor(srgbRed: 0.12, green: 0.13, blue: 0.16, alpha: 1))
        ctx.fill(CGRect(x: 540, y: canvas.height - 50, width: 360, height: 50))

        let lines = [
            (CGPoint(x: 50, y: 140), "Account settings", CGFloat(20)),
            (CGPoint(x: 50, y: 230), "Email: someone@example.com", 14),
            (CGPoint(x: 50, y: 252), "Password: ••••••••••", 14),
            (CGPoint(x: 56, y: 350), "API token: sk-test-0000-FAKE-1234", 15),
            (CGPoint(x: 56, y: 372), "Secret line that must be unreadable", 15),
            (CGPoint(x: 600, y: 220), "Save changes", 16),
        ]
        for (origin, string, size) in lines {
            draw(string, at: CGPoint(x: origin.x, y: canvas.height - origin.y), size: size, in: ctx)
        }
        return ctx.makeImage()
    }

    private static func draw(_ string: String, at baseline: CGPoint, size: CGFloat, in ctx: CGContext) {
        let font = CTFontCreateUIFontForLanguage(.system, size, nil)!
        let attributes = [
            kCTFontAttributeName as String: font,
            kCTForegroundColorAttributeName as String: CGColor(gray: 0.15, alpha: 1),
        ] as CFDictionary
        let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, string as CFString, attributes)!)
        ctx.textMatrix = .identity
        ctx.textPosition = baseline
        CTLineDraw(line, ctx)
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}
