import AnnotateKit
import AppKit

/// The two Lightshot-style strips: tools (vertical, right of the selection) and actions
/// (horizontal, below it), placed by `ToolbarLayout`.
@MainActor
final class AnnotationToolbars {
    let toolStrip: StripView
    let actionStrip: StripView

    var onTool: ((Tool) -> Void)?
    var onPickColor: ((RGBAColor) -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onClose: (() -> Void)?

    private var toolButtons: [Tool: StripButton] = [:]
    private let colorButton: StripButton
    private let undoButton: StripButton
    private let redoButton: StripButton
    private var popover: NSPopover?
    private(set) var layout: ToolbarLayout?

    init() {
        var toolItems: [StripView.Item] = []
        var buttons: [Tool: StripButton] = [:]
        for tool in Tool.allCases {
            let button = StripButton(content: .symbol(tool.symbolName), toolTip: "\(tool.title) (\(tool.shortcutKey.uppercased()))")
            buttons[tool] = button
            toolItems.append(.button(button))
        }
        colorButton = StripButton(content: .color(Palette.defaultColor), toolTip: "Color")
        undoButton = StripButton(content: .symbol("arrow.uturn.backward"), toolTip: "Undo (⌘Z)")
        redoButton = StripButton(content: .symbol("arrow.uturn.forward"), toolTip: "Redo (⇧⌘Z)")
        toolItems += [.separator, .button(colorButton), .separator, .button(undoButton), .button(redoButton)]
        toolButtons = buttons
        toolStrip = StripView(orientation: .vertical, items: toolItems)

        let copy = StripButton(content: .symbol("doc.on.doc"), toolTip: "Copy (⌘C)")
        let save = StripButton(content: .symbol("square.and.arrow.down"), toolTip: "Save (⌘S)")
        let close = StripButton(content: .symbol("xmark"), toolTip: "Close (Esc)")
        actionStrip = StripView(orientation: .horizontal, items: [.button(copy), .button(save), .separator, .button(close)])

        for (tool, button) in toolButtons {
            button.action = { [weak self] _ in self?.onTool?(tool) }
        }
        colorButton.action = { [weak self] button in self?.showPalette(from: button) }
        undoButton.action = { [weak self] _ in self?.onUndo?() }
        redoButton.action = { [weak self] _ in self?.onRedo?() }
        copy.action = { [weak self] _ in self?.onCopy?() }
        save.action = { [weak self] _ in self?.onSave?() }
        close.action = { [weak self] _ in self?.onClose?() }
    }

    func install(in view: SelectionView) {
        view.addAccessoryView(toolStrip)
        view.addAccessoryView(actionStrip)
    }

    /// Mirrors the editor: active tool, current color, undo/redo availability.
    func update(tool: Tool?, color: RGBAColor, canUndo: Bool, canRedo: Bool) {
        for (candidate, button) in toolButtons {
            button.isActive = candidate == tool
        }
        colorButton.content = .color(color)
        undoButton.isEnabled = canUndo
        redoButton.isEnabled = canRedo
    }

    /// Places the strips around `selection` (hidden without a selection).
    func place(around selection: CGRect?, in bounds: CGRect) {
        guard let selection, selection.width > 0, selection.height > 0 else {
            toolStrip.isHidden = true
            actionStrip.isHidden = true
            layout = nil
            return
        }
        let result = ToolbarLayout.compute(
            selection: selection,
            bounds: bounds,
            toolStripSize: toolStrip.preferredSize,
            actionStripSize: actionStrip.preferredSize,
            gap: 8,
            margin: 6
        )
        toolStrip.frame = result.toolStrip
        actionStrip.frame = result.actionStrip
        toolStrip.isHidden = false
        actionStrip.isHidden = false
        layout = result
    }

    func closePopover() {
        popover?.close()
        popover = nil
    }

    var isShowingPalette: Bool { popover?.isShown == true }

    // MARK: - Palette

    func showPalette(from button: StripButton) {
        if isShowingPalette {
            closePopover()
            return
        }
        let controller = PaletteViewController(selected: currentColor) { [weak self] color in
            self?.onPickColor?(color)
            self?.closePopover()
        } more: { [weak self] in
            self?.closePopover()
            self?.showColorPanel()
        }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = controller
        let edge: NSRectEdge = layout?.toolSide == .left ? .minX : .maxX
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: edge)
        self.popover = popover
    }

    private var currentColor: RGBAColor {
        if case .color(let color) = colorButton.content { return color }
        return Palette.defaultColor
    }

    private func showColorPanel() {
        ColorPanelBridge.shared.show(color: currentColor) { [weak self] color in
            self?.onPickColor?(color)
        }
    }
}

/// Palette grid shown in a popover from the color button.
private final class PaletteViewController: NSViewController {
    private let selected: RGBAColor
    private let onPick: (RGBAColor) -> Void
    private let onMore: () -> Void

    init(selected: RGBAColor, pick: @escaping (RGBAColor) -> Void, more: @escaping () -> Void) {
        self.selected = selected
        onPick = pick
        onMore = more
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let columns = 4
        let cell = StripButton.side
        let gap: CGFloat = 4
        let inset: CGFloat = 10
        let rows = (Palette.colors.count + columns - 1) / columns
        let gridWidth = CGFloat(columns) * cell + CGFloat(columns - 1) * gap
        let gridHeight = CGFloat(rows) * cell + CGFloat(rows - 1) * gap
        let moreHeight: CGFloat = 24
        let root = NSView(frame: CGRect(x: 0, y: 0, width: gridWidth + inset * 2, height: gridHeight + moreHeight + inset * 2 + 6))

        for (index, color) in Palette.colors.enumerated() {
            let row = index / columns, column = index % columns
            let button = StripButton(content: .color(color), toolTip: Self.name(for: color)) { [weak self] _ in self?.onPick(color) }
            button.isActive = color == selected
            button.frame = CGRect(
                x: inset + CGFloat(column) * (cell + gap),
                y: root.bounds.height - inset - CGFloat(row + 1) * cell - CGFloat(row) * gap,
                width: cell,
                height: cell
            )
            root.addSubview(button)
        }
        let more = NSButton(title: "More Colors…", target: self, action: #selector(moreColors))
        more.bezelStyle = .push
        more.controlSize = .small
        more.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        more.refusesFirstResponder = true
        more.frame = CGRect(x: inset, y: inset, width: gridWidth, height: moreHeight)
        root.addSubview(more)
        view = root
    }

    @objc private func moreColors() {
        onMore()
    }

    private static func name(for color: RGBAColor) -> String {
        switch color {
        case Palette.red: "Red"
        case Palette.orange: "Orange"
        case Palette.yellow: "Yellow"
        case Palette.green: "Green"
        case Palette.blue: "Blue"
        case Palette.purple: "Purple"
        case Palette.black: "Black"
        case Palette.white: "White"
        default: "Color"
        }
    }
}

/// Shows the shared color panel above the overlay (which sits at screen-saver level) and
/// forwards its changes. Restores the panel's level when it closes.
@MainActor
final class ColorPanelBridge: NSObject {
    static let shared = ColorPanelBridge()

    private var onChange: ((RGBAColor) -> Void)?
    private var savedLevel: NSWindow.Level?

    func show(color: RGBAColor, onChange: @escaping (RGBAColor) -> Void) {
        self.onChange = onChange
        let panel = NSColorPanel.shared
        if savedLevel == nil { savedLevel = panel.level }
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.showsAlpha = false
        panel.color = color.nsColor
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.isContinuous = true
        panel.orderFrontRegardless()
    }

    /// Detaches and hides the panel (session ended).
    func dismiss() {
        guard onChange != nil || savedLevel != nil else { return }
        let panel = NSColorPanel.shared
        panel.setTarget(nil)
        panel.setAction(nil)
        if let savedLevel { panel.level = savedLevel }
        savedLevel = nil
        onChange = nil
        panel.orderOut(nil)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        guard let color = RGBAColor(sender.color) else { return }
        onChange?(color)
    }
}
