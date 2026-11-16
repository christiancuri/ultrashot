import AppKit

/// The panel attached to the recording selection (an accessory view of ``SelectionView``):
/// width × height fields (points), Fullscreen, Window pick, Microphone and System Audio
/// toggles and the Record button.
///
/// It only reports user intent through its callbacks; ``RecordingCoordinator`` owns the state
/// and pushes it back with ``update(_:)``.
final class RecordPanelView: NSView, NSTextFieldDelegate {
    struct State: Equatable {
        var selectionSize: CGSize?
        var windowMode = false
        var windowPicked = false
        var microphone = false
        var systemAudio = false
    }

    var onSizeEntered: ((CGSize) -> Void)?
    var onFullscreen: (() -> Void)?
    var onToggleWindowMode: (() -> Void)?
    var onMicrophoneChanged: ((Bool) -> Void)?
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
        let actionRow = NSStackView(views: [microphoneButton, systemAudioButton, NSView(), recordButton, returnHint])
        actionRow.spacing = 6
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
