import AppKit
import RecordingKit

/// What shows on screen while recording: a thin border around the recorded area and a small
/// control panel (elapsed time, Pause/Resume, Stop, Discard) just outside it.
///
/// Both windows are click-through or non-activating, join every Space and are hidden from
/// screen capture (`sharingType = .none`; their ids are also excluded from the recording
/// filter). `ULTRASHOT_DEBUG_CAPTURABLE_OVERLAY=1` makes them capturable in Debug builds.
@MainActor
final class RecordingHUD {
    var onTogglePause: (() -> Void)?
    var onStop: (() -> Void)?
    var onDiscard: (() -> Void)?

    private let border: RecordingBorderWindow?
    private let panel: HUDPanel
    private let controls = HUDControlsView()

    /// - Parameters:
    ///   - area: recorded area in AppKit global points.
    ///   - screenFrame: AppKit frame of the screen being recorded.
    ///   - showsBorder: false for a fullscreen recording.
    init(area: CGRect, screenFrame: CGRect, showsBorder: Bool) {
        border = showsBorder ? RecordingBorderWindow() : nil
        panel = HUDPanel(contentView: controls)
        controls.onTogglePause = { [weak self] in self?.onTogglePause?() }
        controls.onStop = { [weak self] in self?.onStop?() }
        controls.onDiscard = { [weak self] in self?.onDiscard?() }
        layout(area: area, screenFrame: screenFrame)
    }

    /// Window ids to exclude from the recording.
    var windowIDs: [CGWindowID] {
        [border?.windowNumber, panel.windowNumber].compactMap { $0 }.filter { $0 > 0 }.map { CGWindowID($0) }
    }

    func show() {
        border?.orderFrontRegardless()
        panel.orderFrontRegardless()
    }

    func close() {
        border?.orderOut(nil)
        border?.close()
        panel.orderOut(nil)
        panel.close()
    }

    func update(elapsed: TimeInterval, paused: Bool) {
        controls.update(elapsed: elapsed, paused: paused)
    }

    /// Positions the border around `area` and the panel below it (above or inside at the
    /// screen edges; bottom-center for a fullscreen recording).
    func layout(area: CGRect, screenFrame: CGRect) {
        border?.setFrame(area.insetBy(dx: -RecordingBorderWindow.lineWidth, dy: -RecordingBorderWindow.lineWidth), display: true)
        let size = controls.fittingSize
        let anchor = area.insetBy(dx: -RecordingBorderWindow.lineWidth, dy: -RecordingBorderWindow.lineWidth)
        let placement = RecordingGeometry.place(size, near: anchor, in: screenFrame, gap: 8, margin: 12)
        panel.setFrame(placement.frame, display: true)
    }
}

/// Click-through window that draws the recorded area's outline.
private final class RecordingBorderWindow: NSWindow {
    static let lineWidth: CGFloat = 2

    init() {
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        configureOverlay(self)
        ignoresMouseEvents = true
        contentView = BorderView()
    }

    private final class BorderView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(rect: bounds.insetBy(dx: RecordingBorderWindow.lineWidth / 2, dy: RecordingBorderWindow.lineWidth / 2))
            path.lineWidth = RecordingBorderWindow.lineWidth
            path.setLineDash([6, 4], count: 2, phase: 0)
            NSColor.systemRed.withAlphaComponent(0.9).setStroke()
            path.stroke()
        }
    }
}

/// Non-activating panel hosting the HUD controls.
private final class HUDPanel: NSPanel {
    init(contentView view: NSView) {
        super.init(contentRect: NSRect(origin: .zero, size: view.fittingSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        configureOverlay(self)
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private func configureOverlay(_ window: NSWindow) {
    window.identifier = NSUserInterfaceItemIdentifier("ultrashot.recording")
    window.level = .statusBar
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    window.sharingType = DebugLaunchHooks.capturableOverlays ? .readOnly : .none
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.isReleasedWhenClosed = false
    window.animationBehavior = .none
}

/// Red dot, elapsed time, Pause/Resume, Stop and Discard.
private final class HUDControlsView: NSView {
    var onTogglePause: (() -> Void)?
    var onStop: (() -> Void)?
    var onDiscard: (() -> Void)?

    private let dot = NSImageView()
    private let time = NSTextField(labelWithString: "00:00")
    private let pauseButton = RecordingIconButton(symbol: "pause.fill", label: "Pause", toggle: false)
    private let stopButton = RecordingIconButton(symbol: "stop.fill", label: "Stop and save", toggle: false)
    private let discardButton = RecordingIconButton(symbol: "trash", label: "Discard recording", toggle: false)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        appearance = NSAppearance(named: .darkAqua)
        let background = RecordingPanelBackground(cornerRadius: 10)
        addSubview(background)

        dot.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Recording")
        dot.contentTintColor = .systemRed
        dot.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .regular)
        time.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        time.setAccessibilityLabel("Elapsed time")
        pauseButton.target = self
        pauseButton.action = #selector(pausePressed)
        stopButton.target = self
        stopButton.action = #selector(stopPressed)
        stopButton.tint = .systemRed
        discardButton.target = self
        discardButton.action = #selector(discardPressed)

        let row = NSStackView(views: [dot, time, pauseButton, stopButton, discardButton])
        row.spacing = 6
        row.setCustomSpacing(10, after: time)
        row.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 6)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            time.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        setFrameSize(fittingSize)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func update(elapsed: TimeInterval, paused: Bool) {
        let text = RecordingGeometry.elapsedText(elapsed)
        if time.stringValue != text { time.stringValue = text }
        pauseButton.setSymbol(paused ? "play.fill" : "pause.fill")
        pauseButton.toolTip = paused ? "Resume" : "Pause"
        pauseButton.setAccessibilityLabel(paused ? "Resume" : "Pause")
        dot.contentTintColor = paused ? .systemGray : .systemRed
    }

    @objc private func pausePressed() { onTogglePause?() }
    @objc private func stopPressed() { onStop?() }
    @objc private func discardPressed() { onDiscard?() }
}
