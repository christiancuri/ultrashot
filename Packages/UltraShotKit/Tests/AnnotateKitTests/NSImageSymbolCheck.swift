import AppKit

enum NSImageSymbolCheck {
    @MainActor
    static func exists(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }
}
