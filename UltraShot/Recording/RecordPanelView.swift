import AppKit
import RecordingKit

/// The panel attached to the recording selection (an accessory view of ``SelectionView``):
/// width × height fields (points), Fullscreen, Window pick, Microphone and System Audio
/// toggles and the Record button. The chevron next to the microphone (or a right-click on it)
/// opens the microphone menu: System Default and every connected input, the saved one checked.
///
/// It only reports user intent through its callbacks; ``RecordingCoordinator`` owns the state
/// and pushes it back with ``update(_:)``.
final class RecordPanelView: NSView, NSTextFieldDelegate, NSMenuDelegate {
    struct State: Equatable {
        var selectionSize: CGSize?
        var windowMode = false
        var windowPicked = false
        var microphone = false
        /// The microphone that will be recorded, for the tooltip (e.g. "System Default (…)").
        var microphoneTitle: String?
        var systemAudio = false
    }

    /// The microphone menu's content, read each time it opens.
    struct MicrophoneMenu {
        var options: [MicrophoneSelection.Option]
        /// The saved choice (`nil` = System Default), shown with a checkmark.
        var selectedID: String?
    }

    var onSizeEntered: ((CGSize) -> Void)?
    var onFullscreen: (() -> Void)?
    var onToggleWindowMode: (() -> Void)?
    var onMicrophoneChanged: ((Bool) -> Void)?
    var microphoneMenuProvider: (() -> MicrophoneMenu)?
    /// A device was picked in the microphone menu (`nil` = System Default).
    var onMicrophoneSelected: ((String?) -> Void)?
    var onSystemAudioChanged: ((Bool) -> Void)?
    var onRecord: (() -> Void)?
    /// Esc while a size field is being edited.
    var onCancel: (() -> Void)?
    /// Editing ended (↩ or Tab out of the fields): give keyboard focus back to the selection.
    var onFinishedEditing: (() -> Void)?

    private let background = RecordingPanelBackground(cornerRadius: 12)
    private let widthField = RecordPanelView.makeField(label: "Width in points")
    private let heightField = RecordPanelView.makeField(label: "Height in points")
    private let fullscreenButton = RecordingIconButton(symbol: "arrow.up.left.and.arrow.down.right", label: "Fullscreen", toggle: false)
    private let windowButton = RecordingIconButton(symbol: "macwindow", label: "Pick a window (Space)", toggle: true)
    private let microphoneButton = RecordingIconButton(symbol: "mic", label: "Microphone", toggle: true, side: 34)
    private let microphoneMenuButton = RecordingIconButton(
        symbol: "chevron.down", label: "Choose Microphone", toggle: false, side: 34, width: 16, pointSize: 9
    )
    private let microphoneMenu = NSMenu(title: "Microphone")
    private var microphoneMenuOptions: [MicrophoneSelection.Option] = []
    private let systemAudioButton = RecordingIconButton(symbol: "speaker.wave.2", label: "System audio", toggle: true, side: 34)
    private let recordButton = NSButton()
    private var state = State()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        appearance = NSAppearance(named: .darkAqua)
        setUp()
        update(state)
        setFrameSize(fittingSize)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: API

    func update(_ newState: State) {
        state = newState
        if widthField.currentEditor() == nil, heightField.currentEditor() == nil {
            widthField.stringValue = newState.selectionSize.map { "\(Int($0.width.rounded()))" } ?? ""
            heightField.stringValue = newState.selectionSize.map { "\(Int($0.height.rounded()))" } ?? ""
        }
        windowButton.state = newState.windowMode ? .on : .off
        microphoneButton.state = newState.microphone ? .on : .off
        microphoneButton.setSymbol(newState.microphone ? "mic.fill" : "mic.slash")
        microphoneButton.toolTip = newState.microphoneTitle.map { "Microphone: \($0)" } ?? "Microphone"
        systemAudioButton.state = newState.systemAudio ? .on : .off
        systemAudioButton.setSymbol(newState.systemAudio ? "speaker.wave.2.fill" : "speaker.slash")
        recordButton.isEnabled = newState.selectionSize != nil && !newState.windowMode
        recordButton.title = newState.windowPicked ? "Record Window" : "Record Video"
    }

    // MARK: Mouse

    /// Swallow clicks on the panel background so they never start a selection drag below.
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: NSTextFieldDelegate

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            onCancel?()
            return true
        case #selector(NSResponder.insertNewline(_:)):
            applyFields()
            window?.makeFirstResponder(nil)
            onFinishedEditing?()
            return true
        default:
            return false
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        applyFields()
    }

    // MARK: Microphone menu

    /// Opens the microphone menu under the microphone button (above it when the panel sits
    /// too close to the bottom of the screen), as the chevron does.
    func showMicrophoneMenu() {
        menuNeedsUpdate(microphoneMenu) // fill it now to know its height
        let button = microphoneButton
        let gap: CGFloat = 4
        let height = microphoneMenu.size.height
        let floor = button.window?.screen?.visibleFrame.minY ?? -.greatestFiniteMagnitude
        let buttonBottom = button.window?.convertToScreen(button.convert(button.bounds, to: nil)).minY ?? .greatestFiniteMagnitude
        let fitsBelow = buttonBottom - gap - height >= floor
        // `popUp` puts the menu's top-left corner at this point, in the button's coordinates.
        let top: CGFloat = switch (fitsBelow, button.isFlipped) {
        case (true, true): button.bounds.maxY + gap
        case (true, false): -gap
        case (false, true): -gap - height
        case (false, false): button.bounds.maxY + gap + height
        }
        microphoneMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: top), in: button)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === microphoneMenu else { return }
        menu.removeAllItems()
        let content = microphoneMenuProvider?() ?? MicrophoneMenu(options: [], selectedID: nil)
        microphoneMenuOptions = content.options
        menu.addItem(.sectionHeader(title: "Microphone"))
        for (index, option) in content.options.enumerated() {
            if index == 1 { menu.addItem(.separator()) } // System Default, then the devices
            let item = NSMenuItem(title: option.title, action: #selector(microphoneItemChosen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = option.deviceID == content.selectedID ? .on : .off
            item.isEnabled = option.isAvailable
            menu.addItem(item)
        }
    }

    @objc private func microphoneItemChosen(_ item: NSMenuItem) {
        guard microphoneMenuOptions.indices.contains(item.tag) else { return }
        onMicrophoneSelected?(microphoneMenuOptions[item.tag].deviceID)
    }

    // MARK: Private

    private func applyFields() {
        guard let width = Double(widthField.stringValue.trimmingCharacters(in: .whitespaces)),
              let height = Double(heightField.stringValue.trimmingCharacters(in: .whitespaces)) else {
            update(state)
            return
        }
        let size = CGSize(width: width, height: height)
        guard size != state.selectionSize else { return }
        onSizeEntered?(size)
    }

    private func setUp() {
        addSubview(background)

        widthField.delegate = self
        heightField.delegate = self
        let times = NSTextField(labelWithString: "×")
        times.textColor = .secondaryLabelColor

        fullscreenButton.target = self
        fullscreenButton.action = #selector(fullscreenPressed)
        windowButton.target = self
        windowButton.action = #selector(windowPressed)
        microphoneButton.target = self
        microphoneButton.action = #selector(microphonePressed)
        microphoneButton.menu = microphoneMenu // right-click
        microphoneMenu.delegate = self
        microphoneMenu.autoenablesItems = false
        microphoneMenu.appearance = appearance // dark, like the panel
        microphoneMenuButton.target = self
        microphoneMenuButton.action = #selector(microphoneMenuPressed)
        microphoneMenuButton.sendAction(on: .leftMouseDown) // opens on press, like a pull-down
        // Keep keyboard focus on the selection (↩ records) even with full keyboard access on.
        microphoneButton.refusesFirstResponder = true
        microphoneMenuButton.refusesFirstResponder = true
        systemAudioButton.target = self
        systemAudioButton.action = #selector(systemAudioPressed)

        recordButton.bezelStyle = .push
        recordButton.controlSize = .large
        recordButton.bezelColor = .systemRed
        recordButton.image = Self.symbol("record.circle")
        recordButton.imagePosition = .imageLeading
        recordButton.target = self
        recordButton.action = #selector(recordPressed)
        recordButton.toolTip = "Start recording (↩)"
        let returnHint = NSTextField(labelWithString: "↩")
        returnHint.textColor = .secondaryLabelColor

        let sizeRow = NSStackView(views: [widthField, times, heightField, Self.separator(), fullscreenButton, windowButton])
        sizeRow.spacing = 6
        let actionRow = NSStackView(views: [microphoneButton, microphoneMenuButton, systemAudioButton, NSView(), recordButton, returnHint])
        actionRow.spacing = 6
        actionRow.setCustomSpacing(0, after: microphoneButton)
        let column = NSStackView(views: [sizeRow, actionRow])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 8
        column.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)

        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor),
            actionRow.widthAnchor.constraint(equalTo: sizeRow.widthAnchor),
        ])
    }

    @objc private func fullscreenPressed() { onFullscreen?() }
    @objc private func windowPressed() { onToggleWindowMode?() }
    @objc private func microphonePressed() { onMicrophoneChanged?(microphoneButton.state == .on) }
    @objc private func microphoneMenuPressed() { showMicrophoneMenu() }
    @objc private func systemAudioPressed() { onSystemAudioChanged?(systemAudioButton.state == .on) }

    @objc private func recordPressed() {
        applyFields()
        onRecord?()
    }

    private static func makeField(label: String) -> NSTextField {
        let field = NSTextField()
        field.alignment = .center
        field.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        field.bezelStyle = .roundedBezel
        field.placeholderString = "—"
        field.setAccessibilityLabel(label)
        field.toolTip = label
        field.widthAnchor.constraint(equalToConstant: 64).isActive = true
        return field
    }

    private static func separator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return box
    }

    private static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }
}
