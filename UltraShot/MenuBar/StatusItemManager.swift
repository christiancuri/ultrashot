import AppKit
import KeyboardShortcuts
import Observation

/// The single menu bar item.
///
/// Idle: a camera glyph; any click opens the menu. While a recording runs (or is paused)
/// the button shows a stop glyph and the elapsed time, and a left click stops the
/// recording (right click still opens the menu). The menu is rebuilt on every open so
/// titles and shortcuts are always current.
@MainActor
final class StatusItemManager: NSObject {
    private let model: AppModel
    private var item: NSStatusItem?
    /// Last rendered button state, to skip redundant updates on every elapsed tick.
    private var rendered: (isRecording: Bool, label: String)?

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "main"
        item.isVisible = true
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }
        self.item = item
        observeRecording()
        Log.app.info("status item ready (button: \(item.button != nil), visible: \(item.isVisible))")
    }

    // MARK: - Recording state

    private var isRecording: Bool {
        switch model.recording.state {
        case .recording, .paused: true
        case .idle, .selecting: false
        }
    }

    private func observeRecording() {
        withObservationTracking {
            render(isRecording: isRecording, elapsed: model.recording.elapsed)
        } onChange: { [weak self] in
            // Fires before the new value is set: re-read on the next turn.
            Task { @MainActor in self?.observeRecording() }
        }
    }

    private func render(isRecording: Bool, elapsed: TimeInterval) {
        let label = isRecording ? Self.elapsedText(elapsed) : ""
        if let rendered, rendered.isRecording == isRecording, rendered.label == label { return }
        let stateChanged = rendered?.isRecording != isRecording
        rendered = (isRecording, label)
        guard let button = item?.button else { return }
        defer { debugLogRender(button, stateChanged: stateChanged) }

        let symbol = isRecording ? "stop.circle.fill" : "camera.viewfinder"
        let description = isRecording ? "Stop Recording" : "UltraShot"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        image?.isTemplate = true
        button.image = image
        if isRecording {
            let size = NSFont.menuBarFont(ofSize: 0).pointSize
            button.attributedTitle = NSAttributedString(
                string: " " + label,
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)]
            )
            button.toolTip = "Recording \(label) — click to stop"
        } else {
            button.title = ""
            button.toolTip = "UltraShot"
        }
        button.setAccessibilityLabel(isRecording ? "Stop recording, \(label)" : "UltraShot")
    }

    /// `mm:ss` below an hour, `h:mm:ss` from one hour on.
    static func elapsedText(_ elapsed: TimeInterval) -> String {
        let total = max(0, Int(elapsed.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Debug builds log what the button shows (and the menu titles when the recording state
    /// flips), so automated recording runs can check the status item.
    private func debugLogRender(_ button: NSStatusBarButton, stateChanged: Bool) {
        #if DEBUG
        let symbol = button.image?.accessibilityDescription ?? "none"
        Log.app.info("status item: title '\(button.title, privacy: .public)' image '\(symbol, privacy: .public)'")
        if stateChanged {
            let titles = makeMenu().items.filter { !$0.isSeparatorItem }.map(\.title).joined(separator: " | ")
            Log.app.info("status item menu: \(titles, privacy: .public)")
        }
        #endif
    }

    // MARK: - Clicks

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isSecondary = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if isRecording, !isSecondary {
            model.recording.stop()
        } else {
            showMenu(for: sender)
        }
    }

    private func showMenu(for button: NSStatusBarButton) {
        guard let item else { return }
        // Attach the menu only for this click so a left click can stop a recording.
        item.menu = makeMenu()
        button.performClick(nil)
        item.menu = nil
    }

    // MARK: - Menu

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let capture = model.capture
        menu.addItem(item("Capture Area", symbol: "rectangle.dashed", shortcut: .captureArea) { capture.captureArea() })
        menu.addItem(item("Capture Area & Annotate", symbol: "pencil.and.outline", shortcut: .captureAreaAnnotate) { capture.captureAreaAndAnnotate() })
        menu.addItem(item("Capture Fullscreen", symbol: "macwindow.on.rectangle", shortcut: .captureFullscreen) { capture.captureFullscreen() })
        menu.addItem(item("Capture Window", symbol: "macwindow", shortcut: .captureWindow) { capture.captureWindow() })
        menu.addItem(.separator())
        let recording = model.recording
        let recordTitle = isRecording ? "Stop Recording" : "Record Screen"
        let recordSymbol = isRecording ? "stop.circle" : "record.circle"
        menu.addItem(item(recordTitle, symbol: recordSymbol, shortcut: .recordScreen) { recording.recordScreen() })
        menu.addItem(.separator())
        menu.addItem(item("Settings…", key: ",", symbol: "gearshape") { [weak self] in self?.model.openSettings() })
        if let version = model.updater.availableUpdateVersion {
            menu.addItem(item("Update to \(version)…", symbol: "arrow.down.circle.fill") { [weak self] in self?.model.checkForUpdates() })
        } else if model.updater.isAvailable {
            menu.addItem(item("Check for Updates…", symbol: "arrow.down.circle") { [weak self] in self?.model.checkForUpdates() })
        }
        menu.addItem(.separator())
        menu.addItem(item("Quit UltraShot", key: "q", symbol: "power") { [weak self] in self?.model.quit() })
        return menu
    }

    private func item(
        _ title: String,
        key: String = "",
        symbol: String,
        shortcut: KeyboardShortcuts.Name? = nil,
        action: @escaping @MainActor () -> Void
    ) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, keyEquivalent: key, action: action)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        if let shortcut {
            item.setShortcut(for: shortcut)
        }
        return item
    }
}

/// `NSMenuItem` that runs a closure.
@MainActor
final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, keyEquivalent: String, action: @escaping @MainActor () -> Void) {
        handler = action
        super.init(title: title, action: #selector(run), keyEquivalent: keyEquivalent)
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func run() {
        handler()
    }
}
