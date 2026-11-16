import AppKit
import Carbon

/// Detects whether macOS's own screenshot shortcuts are enabled. No public API turns them
/// off, so the user disables them once in System Settings › Keyboard › Keyboard Shortcuts ›
/// Screenshots; Settings › Shortcuts shows a notice while any of them is still on.
enum SystemScreenshotShortcuts {
    /// A system screenshot shortcut (symbolic hot key ids 28, 29, 30, 31 and 184).
    struct Shortcut: Hashable, Sendable {
        let symbolicID: Int
        let keyCode: Int
        /// Carbon modifier mask (`cmdKey`, `shiftKey`, `controlKey`).
        let carbonModifiers: Int
        let title: String
    }

    static let screenshotShortcuts: [Shortcut] = [
        Shortcut(symbolicID: 28, keyCode: kVK_ANSI_3, carbonModifiers: cmdKey | shiftKey, title: "Save picture of screen as a file (⇧⌘3)"),
        Shortcut(
            symbolicID: 29, keyCode: kVK_ANSI_3, carbonModifiers: cmdKey | shiftKey | controlKey,
            title: "Copy picture of screen to the clipboard (⌃⇧⌘3)"
        ),
        Shortcut(symbolicID: 30, keyCode: kVK_ANSI_4, carbonModifiers: cmdKey | shiftKey, title: "Save picture of selected area as a file (⇧⌘4)"),
        Shortcut(
            symbolicID: 31, keyCode: kVK_ANSI_4, carbonModifiers: cmdKey | shiftKey | controlKey,
            title: "Copy picture of selected area to the clipboard (⌃⇧⌘4)"
        ),
        Shortcut(symbolicID: 184, keyCode: kVK_ANSI_5, carbonModifiers: cmdKey | shiftKey, title: "Screenshot and recording options (⇧⌘5)"),
    ]

    /// System Settings › Keyboard › Keyboard Shortcuts.
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts")

    /// The system screenshot shortcuts that are currently enabled (empty = no conflict).
    ///
    /// `CopySymbolicHotKeys` lists every system hot key with its key code, modifiers and
    /// enabled flag, but not its symbolic id, so entries are matched by key combination.
    static func enabled() -> [Shortcut] {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr,
              let entries = unmanaged?.takeRetainedValue() as? [[String: Any]]
        else {
            return []
        }
        let modifierMask = cmdKey | shiftKey | controlKey | optionKey
        var enabledCombos: Set<[Int]> = []
        for entry in entries {
            guard (entry[kHISymbolicHotKeyEnabled as String] as? Bool) == true,
                  let code = entry[kHISymbolicHotKeyCode as String] as? Int,
                  let modifiers = entry[kHISymbolicHotKeyModifiers as String] as? Int
            else { continue }
            enabledCombos.insert([code, modifiers & modifierMask])
        }
        return screenshotShortcuts.filter { enabledCombos.contains([$0.keyCode, $0.carbonModifiers]) }
    }

    @MainActor
    static func openSystemSettings() {
        guard let settingsURL else { return }
        NSWorkspace.shared.open(settingsURL)
    }
}
