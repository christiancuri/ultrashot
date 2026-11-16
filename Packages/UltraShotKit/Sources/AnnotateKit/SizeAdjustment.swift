import CoreGraphics

/// Scroll-wheel size changes: stroke width for shapes, font size for text.
public enum SizeAdjustment {
    /// Font size change per step (stroke width changes by 1 pt per step).
    public static let fontSizeStep: CGFloat = 2

    public static func lineWidth(_ width: CGFloat, steps: Int) -> CGFloat {
        clamp(width + CGFloat(steps), to: Annotation.Style.lineWidthRange)
    }

    public static func fontSize(_ size: CGFloat, steps: Int) -> CGFloat {
        clamp(size + CGFloat(steps) * fontSizeStep, to: TextContent.fontSizeRange)
    }

    private static func clamp(_ value: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

extension Annotation {
    /// Text grows its font size, every other kind its stroke width (clamped to the ranges).
    public func adjustingSize(steps: Int) -> Annotation {
        var copy = self
        if case .text(var content) = kind {
            content.fontSize = SizeAdjustment.fontSize(content.fontSize, steps: steps)
            copy.kind = .text(content)
        } else {
            copy.style.lineWidth = SizeAdjustment.lineWidth(style.lineWidth, steps: steps)
        }
        return copy
    }

    /// The size the UI shows for this annotation: font size for text, stroke width otherwise.
    public var displayedSize: CGFloat {
        if case .text(let content) = kind { return content.fontSize }
        return style.lineWidth
    }
}

/// Turns scroll-wheel deltas into whole steps: a mouse wheel notch is one step, trackpad
/// (precise) deltas accumulate until `threshold` points.
public struct ScrollStepper: Sendable {
    public var threshold: CGFloat
    private var accumulated: CGFloat = 0

    public init(threshold: CGFloat = 8) {
        self.threshold = threshold
    }

    /// Positive steps for scrolling up (content moving down), negative for down.
    public mutating func steps(deltaY: CGFloat, precise: Bool) -> Int {
        guard precise else {
            accumulated = 0
            return deltaY > 0 ? 1 : deltaY < 0 ? -1 : 0
        }
        accumulated += deltaY
        let steps = Int((accumulated / threshold).rounded(.towardZero))
        accumulated -= CGFloat(steps) * threshold
        return steps
    }

    public mutating func reset() {
        accumulated = 0
    }
}
