import AppKit

/// A borderless, transparent window covering one whole screen, above the menu bar, the
/// Dock and fullscreen apps. Hosts a ``SelectionView`` (see ``OverlaySession``).
///
/// Excluded from every screen capture (`sharingType = .none`), so the overlay never shows
/// up in screenshots or recordings. Debug builds can opt out with
/// `ULTRASHOT_DEBUG_CAPTURABLE_OVERLAY=1` to inspect the overlay with `screencapture -l`.
final class OverlayWindow: NSWindow {
    /// The screen this window covers.
    let targetScreen: NSScreen

    init(screen: NSScreen) {
        targetScreen = screen
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        identifier = NSUserInterfaceItemIdentifier("ultrashot.overlay")
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        sharingType = DebugLaunchHooks.capturableOverlays ? .readOnly : .none
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        isMovable = false
        animationBehavior = .none
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Brings the overlay up and makes it key so it receives keyboard events (Esc, ↩).
    func present() {
        NSApp.activate()
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
    }

    /// Keeps the window on its screen even if AppKit tries to constrain it below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
