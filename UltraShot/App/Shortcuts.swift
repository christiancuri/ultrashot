import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// ⇧⌘4 (⌃⇧⌘4 in Debug).
    static let captureArea = Self("captureArea", initial: Shortcuts.shortcut(.four))
    /// ⇧⌘3 (⌃⇧⌘3 in Debug).
    static let captureFullscreen = Self("captureFullscreen", initial: Shortcuts.shortcut(.three))
    /// Unset by default.
    static let captureWindow = Self("captureWindow")
    /// ⌥⇧⌘4 (⌃⌥⇧⌘4 in Debug).
    static let captureAreaAnnotate = Self("captureAreaAnnotate", initial: Shortcuts.shortcut(.four, extra: .option))
    /// ⇧⌘5 (⌃⌥⇧⌘5 in Debug: ⌃⇧⌘5 is an enabled system hot key). Also stops a running recording.
    static let recordScreen = Self("recordScreen", initial: Shortcuts.recordScreenDefault)
}

/// Global shortcuts (Carbon hot keys through KeyboardShortcuts).
///
/// Debug builds add ⌃ to every default so they can run next to another screenshot app
/// that owns ⇧⌘3/⇧⌘4. Users change them in Settings › Shortcuts.
@MainActor
enum Shortcuts {
    struct Item: Identifiable {
        let name: KeyboardShortcuts.Name
        let title: String
        var id: String { name.rawValue }
    }

    /// Every shortcut, in Settings and menu order.
    static let all: [Item] = [
        Item(name: .captureArea, title: "Capture Area"),
        Item(name: .captureAreaAnnotate, title: "Capture Area & Annotate"),
        Item(name: .captureFullscreen, title: "Capture Fullscreen"),
        Item(name: .captureWindow, title: "Capture Window"),
        Item(name: .recordScreen, title: "Record Screen"),
    ]

    #if DEBUG
    nonisolated static let baseModifiers: NSEvent.ModifierFlags = [.control, .shift, .command]
    #else
    nonisolated static let baseModifiers: NSEvent.ModifierFlags = [.shift, .command]
    #endif

    #if DEBUG
    /// macOS holds ⌃⇧⌘5 as an enabled symbolic hot key (key code 23, modifiers 0x1300), which
    /// the system handles before app hot keys, so Debug adds ⌥ for Record Screen.
    nonisolated static let recordScreenDefault = shortcut(.five, extra: .option)
    #else
    nonisolated static let recordScreenDefault = shortcut(.five)
    #endif

    nonisolated static func shortcut(_ key: KeyboardShortcuts.Key, extra: NSEvent.ModifierFlags = []) -> KeyboardShortcuts.Shortcut {
        KeyboardShortcuts.Shortcut(key, modifiers: baseModifiers.union(extra))
    }

    /// Installs the handlers. Captures fire on key down for the shortest delay.
    static func register(model: AppModel) {
        KeyboardShortcuts.onKeyDown(for: .captureArea) { [weak model] in
            Log.hotkeys.debug("captureArea")
            model?.capture.captureArea()
        }
        KeyboardShortcuts.onKeyDown(for: .captureFullscreen) { [weak model] in
            Log.hotkeys.debug("captureFullscreen")
            model?.capture.captureFullscreen()
        }
        KeyboardShortcuts.onKeyDown(for: .captureWindow) { [weak model] in
            Log.hotkeys.debug("captureWindow")
            model?.capture.captureWindow()
        }
        KeyboardShortcuts.onKeyDown(for: .captureAreaAnnotate) { [weak model] in
            Log.hotkeys.debug("captureAreaAnnotate")
            model?.capture.captureAreaAndAnnotate()
        }
        KeyboardShortcuts.onKeyDown(for: .recordScreen) { [weak model] in
            Log.hotkeys.debug("recordScreen")
            model?.recording.recordScreen()
        }
        Log.hotkeys.info("registered \(all.count) shortcuts")
    }
}
