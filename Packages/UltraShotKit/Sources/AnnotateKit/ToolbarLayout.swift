import CoreGraphics

/// Placement of the two annotation toolbars around a selection, Lightshot's "L" layout:
/// the vertical tool strip sits just outside the selection's RIGHT edge, bottom-aligned
/// with it; the horizontal action strip sits just outside the BOTTOM edge, right-aligned.
///
/// When a strip does not fit on its preferred side it flips (tool strip: right → left →
/// inside the right edge; action strip: below → above → inside the bottom edge), is
/// clamped to the screen, and the action strip slides left of the tool strip if the two
/// would overlap. All rects use the bottom-left (AppKit) convention.
public struct ToolbarLayout: Sendable, Equatable {
    public enum ToolSide: Sendable, Equatable { case right, left, inside }
    public enum ActionSide: Sendable, Equatable { case below, above, inside }

    public var toolStrip: CGRect
    public var actionStrip: CGRect
    public var toolSide: ToolSide
    public var actionSide: ActionSide

    /// - Parameters:
    ///   - selection: the selection rect.
    ///   - bounds: the area the strips must stay inside (the screen / overlay view bounds).
    ///   - gap: distance between the selection and a strip.
    ///   - margin: minimum distance between a strip and the bounds' edges.
    public static func compute(
        selection: CGRect,
        bounds: CGRect,
        toolStripSize: CGSize,
        actionStripSize: CGSize,
        gap: CGFloat = 6,
        margin: CGFloat = 4
    ) -> ToolbarLayout {
        let selection = selection.standardized
        let minX = bounds.minX + margin, maxX = bounds.maxX - margin
        let minY = bounds.minY + margin, maxY = bounds.maxY - margin

        // Tool strip: right, else left, else inside the right edge.
        var tool = CGRect(origin: .zero, size: toolStripSize)
        let toolSide: ToolSide
        if selection.maxX + gap + tool.width <= maxX {
            toolSide = .right
            tool.origin.x = selection.maxX + gap
        } else if selection.minX - gap - tool.width >= minX {
            toolSide = .left
            tool.origin.x = selection.minX - gap - tool.width
        } else {
            toolSide = .inside
            tool.origin.x = selection.maxX - gap - tool.width
        }
        tool.origin.y = toolSide == .inside ? selection.minY + gap : selection.minY
        tool.origin = clamp(tool, minX: minX, maxX: maxX, minY: minY, maxY: maxY)

        // Action strip: below, else above, else inside the bottom edge; right-aligned.
        var action = CGRect(origin: .zero, size: actionStripSize)
        let actionSide: ActionSide
        if selection.minY - gap - action.height >= minY {
            actionSide = .below
            action.origin.y = selection.minY - gap - action.height
        } else if selection.maxY + gap + action.height <= maxY {
            actionSide = .above
            action.origin.y = selection.maxY + gap
        } else {
            actionSide = .inside
            action.origin.y = selection.minY + gap
        }
        action.origin.x = actionSide == .inside ? selection.maxX - gap - action.width : selection.maxX - action.width
        action.origin = clamp(action, minX: minX, maxX: maxX, minY: minY, maxY: maxY)

        if action.intersects(tool) {
            // Slide left of the tool strip; if there is no room, stack above it.
            let slid = tool.minX - gap - action.width
            if slid >= minX {
                action.origin.x = slid
            } else {
                action.origin.y = min(tool.maxY + gap, maxY - action.height)
            }
        }
        return ToolbarLayout(toolStrip: tool, actionStrip: action, toolSide: toolSide, actionSide: actionSide)
    }

    private static func clamp(_ rect: CGRect, minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat) -> CGPoint {
        CGPoint(
            x: max(minX, min(rect.minX, maxX - rect.width)),
            y: max(minY, min(rect.minY, maxY - rect.height))
        )
    }
}
