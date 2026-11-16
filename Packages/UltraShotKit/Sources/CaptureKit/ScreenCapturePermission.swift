import CoreGraphics

/// Screen Recording (TCC) permission for this process.
public enum ScreenCapturePermission {
    /// Whether the process may capture the screen. Does not prompt.
    public static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Asks for access. The first call shows the system prompt; later calls return the current
    /// state. A grant usually takes effect only after the app relaunches.
    @discardableResult
    public static func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }
}
