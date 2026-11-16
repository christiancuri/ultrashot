#if DEBUG
import AnnotateKit
import AppKit

/// Scripted actions for `ULTRASHOT_DEBUG_ANNOTATE_SCRIPT` (see `AnnotationCoordinator+Debug`).
extension AnnotationSession {
    func debugRun(_ steps: [String], copyDelay: Double) {
        guard let canvas, let selection = canvas.selectionInCanvas else {
            Log.annotate.error("debug script: no selection")
            return
        }
        for step in steps {
            switch step {
            case "1", "sample":
                debugAddSample(in: selection)
            case "text":
                let origin = CGPoint(x: selection.minX + selection.width * 0.55, y: selection.minY + selection.height * 0.3)
                canvas.beginTextEditing(
                    TextContent(string: "Editing text\nsecond line", origin: origin, fontSize: 22),
                    style: Annotation.Style(color: Palette.blue),
                    annotationID: nil
                )
            case "textalign":
                // A committed red text with a blue live editor on top at the same origin:
                // when TextLayout and the text view agree, the red copy is fully hidden.
                let content = TextContent(string: "Alignment Ågy\nsecond line", origin: CGPoint(
                    x: selection.minX + selection.width * 0.55, y: selection.minY + selection.height * 0.3
                ), fontSize: 28)
                editor.add(Annotation(kind: .text(content), style: Annotation.Style(color: Palette.red)))
                canvas.beginTextEditing(content, style: Annotation.Style(color: Palette.blue), annotationID: nil)
            case "selftest":
                debugSelfTest()
            case "palette":
                if let button = toolbars.debugColorButton { toolbars.showPalette(from: button) }
            case "copy":
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(copyDelay))
                    Log.annotate.info("debug script: copy")
                    self?.copy()
                }
            case "save":
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(copyDelay))
                    Log.annotate.info("debug script: save")
                    self?.save()
                }
            default:
                if step.hasPrefix("tool="), let tool = Tool(rawValue: String(step.dropFirst(5))) {
                    editor.tool = tool
                } else {
                    Log.annotate.error("debug script: unknown step \(step, privacy: .public)")
                }
            }
        }
        Log.annotate.info("debug script ran: \(steps.joined(separator: ","), privacy: .public) (\(self.editor.document.annotations.count) objects)")
    }

    /// One object per tool, laid out relative to `s` (canvas points); the rectangle ends up selected.
    private func debugAddSample(in s: CGRect) {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: s.minX + s.width * x, y: s.minY + s.height * y) }
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: s.minX + s.width * x, y: s.minY + s.height * y, width: s.width * w, height: s.height * h)
        }
        let red = Annotation.Style(color: Palette.red, lineWidth: 4)
        var squiggle: [CGPoint] = []
        for index in 0...60 {
            let t = CGFloat(index) / 60
            squiggle.append(p(0.06 + t * 0.3, 0.14 + sin(t * .pi * 3) * 0.05))
        }
        let rectangle = Annotation(kind: .rectangle(r(0.05, 0.56, 0.32, 0.3)), style: red)
        let samples: [Annotation] = [
            Annotation(kind: .marker(points: [p(0.45, 0.82), p(0.9, 0.82)]), style: Annotation.Style(color: Palette.yellow, lineWidth: 5)),
            rectangle,
            Annotation(kind: .ellipse(r(0.62, 0.5, 0.3, 0.24)), style: Annotation.Style(color: Palette.orange, lineWidth: 4)),
            Annotation(kind: .arrow(start: p(0.62, 0.3), end: p(0.4, 0.55)), style: red),
            Annotation(kind: .line(start: p(0.45, 0.08), end: p(0.92, 0.08)), style: Annotation.Style(color: Palette.purple, lineWidth: 3)),
            Annotation(kind: .pen(points: squiggle), style: red),
            Annotation(kind: .blur(r(0.45, 0.62, 0.14, 0.12)), style: red),
            Annotation(
                kind: .text(TextContent(string: "Annotated with UltraShot", origin: p(0.06, 0.48), fontSize: 20)),
                style: red
            ),
            Annotation(kind: .counter(center: p(0.4, 0.86), number: 1), style: red),
            Annotation(kind: .counter(center: p(0.95, 0.62), number: 2), style: Annotation.Style(color: Palette.blue, lineWidth: 4)),
            Annotation(kind: .counter(center: p(0.95, 0.3), number: 3), style: Annotation.Style(color: Palette.green, lineWidth: 4)),
        ]
        for annotation in samples {
            editor.add(annotation)
        }
        editor.tool = .arrow
        editor.selectedID = rectangle.id
    }
}

extension AnnotationToolbars {
    /// The color button, for the `palette` script step.
    var debugColorButton: StripButton? {
        toolStrip.findButton { if case .color = $0.content { true } else { false } }
    }
}

private extension NSView {
    func findButton(where predicate: (StripButton) -> Bool) -> StripButton? {
        for subview in subviews {
            if let button = subview as? StripButton, predicate(button) { return button }
            if let found = subview.findButton(where: predicate) { return found }
        }
        return nil
    }
}
#endif
