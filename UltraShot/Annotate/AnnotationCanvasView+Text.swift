import AnnotateKit
import AppKit

/// In-place text entry: an `NSTextView` laid out exactly like `TextLayout` (same font,
/// fixed line height, top-left origin), growing as the user types.
///
/// ↩ inserts a newline; ⌘↩, Esc or a click anywhere else commits. Empty text is dropped
/// (and an edited text emptied out is deleted).
extension AnnotationCanvasView {
    struct TextEditing {
        let textView: AnnotationTextView
        /// The annotation being re-edited, `nil` for a new text.
        let annotationID: Annotation.ID?
        var content: TextContent
        var style: Annotation.Style
    }

    var isEditingText: Bool { textEditing != nil }

    func beginTextEditing(_ content: TextContent, style: Annotation.Style, annotationID: Annotation.ID?) {
        let textView = AnnotationTextView(frame: .zero)
        textView.string = content.string
        textView.onCommit = { [weak self] in self?.endTextEditing() }
        textView.delegate = self
        textEditing = TextEditing(textView: textView, annotationID: annotationID, content: content, style: style)
        applyTextAttributes()
        addSubview(textView)
        window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        needsDisplay = true
        Log.annotate.debug("text editing began (\(annotationID == nil ? "new" : "existing", privacy: .public))")
    }

    /// Commits the text being edited. Safe to call when nothing is being edited.
    func endTextEditing() {
        guard let editing = textEditing else { return }
        textEditing = nil
        let string = editing.textView.string
        editing.textView.delegate = nil
        let hadFocus = window?.firstResponder === editing.textView
        editing.textView.removeFromSuperview()
        if hadFocus {
            // Hand the keyboard back to the selection view (Esc, ↩, tool keys).
            window?.makeFirstResponder(superview)
        }

        var content = editing.content
        content.string = string
        let isEmpty = string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if let id = editing.annotationID {
            if isEmpty {
                editor.document.remove(id)
            } else {
                editor.document.update(id) { annotation in
                    annotation.kind = .text(content)
                    annotation.style = editing.style
                }
            }
            editor.commit()
        } else if !isEmpty {
            editor.add(Annotation(kind: .text(content), style: editing.style))
        }
        needsDisplay = true
    }

    /// Scroll wheel while typing: resize the text being edited.
    func adjustEditingFontSize(steps: Int) -> CGFloat? {
        guard var editing = textEditing else { return nil }
        editing.content.fontSize = SizeAdjustment.fontSize(editing.content.fontSize, steps: steps)
        textEditing = editing
        editor.setFontSize(editing.content.fontSize)
        applyTextAttributes()
        return editing.content.fontSize
    }

    /// Color change while typing.
    func setEditingColor(_ color: RGBAColor) {
        guard var editing = textEditing else { return }
        editing.style.color = color
        textEditing = editing
        applyTextAttributes()
    }

    func applyTextAttributes() {
        guard let editing = textEditing else { return }
        let textView = editing.textView
        let fontSize = editing.content.fontSize
        let lineHeight = TextLayout.lineHeight(fontSize: fontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        let attributes: [NSAttributedString.Key: Any] = [
            .font: TextLayout.font(size: fontSize) as NSFont,
            .foregroundColor: editing.style.color.nsColor,
            .paragraphStyle: paragraph,
        ]
        textView.typingAttributes = attributes
        textView.insertionPointColor = editing.style.color.nsColor
        if let storage = textView.textStorage, storage.length > 0 {
            storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
        }
        layoutTextView()
    }

    func layoutTextView() {
        guard let editing = textEditing else { return }
        var content = editing.content
        content.string = editing.textView.string
        let frame = content.frame
        // Room for the caret (and the next character) on the right.
        let slack = max(content.fontSize * 0.6, 8)
        editing.textView.frame = CGRect(x: frame.minX, y: frame.minY, width: frame.width + slack, height: frame.height)
        needsDisplay = true
    }
}

extension AnnotationCanvasView: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        layoutTextView()
    }

    func textDidEndEditing(_ notification: Notification) {
        // Focus moved away (a click on the selection, a toolbar, another window).
        endTextEditing()
    }
}

/// The text view used for in-place editing.
final class AnnotationTextView: NSTextView {
    var onCommit: (() -> Void)?

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        configure()
    }

    override convenience init(frame frameRect: NSRect) {
        let container = NSTextContainer(size: CGSize(width: 100_000, height: 100_000))
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        container.lineFragmentPadding = 0
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(container)
        let storage = NSTextStorage()
        storage.addLayoutManager(layoutManager)
        self.init(frame: frameRect, textContainer: container)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func configure() {
        isRichText = false
        importsGraphics = false
        drawsBackground = false
        textContainerInset = .zero
        isHorizontallyResizable = false
        isVerticallyResizable = false
        allowsUndo = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        focusRingType = .none
    }

    override func keyDown(with event: NSEvent) {
        let keyCode = Int(event.keyCode)
        let isReturn = keyCode == SelectionView.KeyCode.returnKey || keyCode == SelectionView.KeyCode.enter
        if keyCode == SelectionView.KeyCode.escape || (isReturn && event.modifierFlags.contains(.command)) {
            onCommit?()
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let keyCode = Int(event.keyCode)
        if keyCode == SelectionView.KeyCode.returnKey || keyCode == SelectionView.KeyCode.enter,
           event.modifierFlags.contains(.command) {
            onCommit?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

extension RGBAColor {
    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    init?(_ color: NSColor) {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        self.init(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent, alpha: srgb.alphaComponent)
    }
}
