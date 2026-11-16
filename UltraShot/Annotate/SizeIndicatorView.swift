import AppKit

/// Transient pill showing the stroke width or font size while scrolling.
final class SizeIndicatorView: NSView {
    private let label = NSTextField(labelWithString: "")
    private var hideTask: Task<Void, Never>?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
        layer?.cornerRadius = 7
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        addSubview(label)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Shows `text` just above `point` (superview coordinates), kept inside `bounds`.
    func show(_ text: String, near point: CGPoint, in bounds: CGRect) {
        label.stringValue = text
        label.sizeToFit()
        let size = CGSize(width: ceil(label.frame.width) + 16, height: 22)
        var origin = CGPoint(x: point.x + 14, y: point.y + 14)
        origin.x = min(max(origin.x, bounds.minX + 4), bounds.maxX - size.width - 4)
        origin.y = min(max(origin.y, bounds.minY + 4), bounds.maxY - size.height - 4)
        frame = CGRect(origin: origin, size: size)
        label.frame = CGRect(x: 0, y: (size.height - label.frame.height) / 2, width: size.width, height: label.frame.height)
        isHidden = false
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            self?.isHidden = true
        }
    }
}
