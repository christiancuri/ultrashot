import CoreGraphics
import Foundation
import ScreenCaptureKit

/// ScreenCaptureKit still capture. All ScreenCaptureKit objects stay on the main actor;
/// only `CGImage`, ids and rects leave it.
///
/// Images are native resolution (2x on Retina) in the display's color profile.
/// Hide UltraShot's own windows with `NSWindow.sharingType = .none`.
@MainActor
public final class StillCapture {
    public init() {}

    /// Loads ScreenCaptureKit's shareable content once so the first real capture is faster.
    /// Errors are ignored; call it at launch when permission is granted.
    public func prewarm() async {
        _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    // MARK: - Displays

    /// Captures each display whole, concurrently, and returns them in the order given.
    ///
    /// Without `hideDesktopIcons` the rect API is used (no shareable-content lookup, fastest).
    /// With it, a display filter excludes Finder's desktop-icon window; the wallpaper stays.
    public func snapshotDisplays(_ displays: [DisplayDescriptor],
                                 options: SnapshotOptions) async throws -> [DisplaySnapshot] {
        guard ScreenCapturePermission.isGranted else { throw CaptureError.permissionDenied }
        guard !displays.isEmpty else { return [] }
        let jobs = JobList(options.hideDesktopIcons ? try await filterJobs(for: displays)
                                                    : try rectJobs(for: displays))
        let showCursor = options.showCursor
        if jobs.items.count == 1 { return [try await snapshot(jobs, at: 0, showCursor: showCursor)] }
        // Concurrent captures overlap inside ScreenCaptureKit (measured ~1.4x faster for two
        // displays). Children capture only Sendable values and hop to the main actor, so SCK
        // objects never leave it. (A `@MainActor` child closure trips a Swift 6.4 region-checker bug.)
        return try await withThrowingTaskGroup(of: (Int, DisplaySnapshot).self) { group in
            for index in jobs.items.indices {
                group.addTask {
                    let snapshot = try await self.snapshot(jobs, at: index, showCursor: showCursor)
                    return (index, snapshot)
                }
            }
            var results: [Int: DisplaySnapshot] = [:]
            for try await (index, snapshot) in group { results[index] = snapshot }
            return jobs.items.indices.compactMap { results[$0] }
        }
    }

    /// How one display is captured.
    private enum Source {
        /// Rect API, CG global points.
        case rect(CGRect)
        /// Display filter plus the display size in points (the full-display source rect).
        case filter(SCContentFilter, CGSize)
    }

    private struct Job {
        let display: DisplayDescriptor
        let source: Source
    }

    /// Main-actor box (Sendable as a global-actor class) so child tasks can share the jobs.
    @MainActor
    private final class JobList {
        let items: [Job]
        init(_ items: [Job]) { self.items = items }
    }

    private func rectJobs(for displays: [DisplayDescriptor]) throws -> [Job] {
        try displays.map { display in
            let bounds = CGDisplayBounds(display.displayID)
            guard !bounds.isEmpty else { throw CaptureError.displayNotFound(display.displayID) }
            return Job(display: display, source: .rect(bounds))
        }
    }

    private func filterJobs(for displays: [DisplayDescriptor]) async throws -> [Job] {
        let content = try await Self.mapErrors {
            try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        }
        let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
        let desktopIcons = content.windows.filter {
            $0.owningApplication?.bundleIdentifier == "com.apple.finder" && $0.windowLayer == iconLevel
        }
        return try displays.map { display in
            guard let scDisplay = content.displays.first(where: { $0.displayID == display.displayID }) else {
                throw CaptureError.displayNotFound(display.displayID)
            }
            let filter = SCContentFilter(display: scDisplay, excludingWindows: desktopIcons)
            return Job(display: display, source: .filter(filter, scDisplay.frame.size))
        }
    }

    private func snapshot(_ jobs: JobList, at index: Int, showCursor: Bool) async throws -> DisplaySnapshot {
        let job = jobs.items[index]
        let config = SCScreenshotConfiguration()
        config.showsCursor = showCursor
        let output: SCScreenshotOutput
        switch job.source {
        case let .rect(bounds):
            output = try await Self.mapErrors {
                try await SCScreenshotManager.captureScreenshot(rect: bounds, configuration: config)
            }
        case let .filter(filter, size):
            config.sourceRect = CGRect(origin: .zero, size: size) // display-local points
            output = try await Self.mapErrors {
                try await SCScreenshotManager.captureScreenshot(contentFilter: filter, configuration: config)
            }
        }
        guard let image = output.sdrImage else { throw CaptureError.noImage }
        return DisplaySnapshot(displayID: job.display.displayID, frame: job.display.frame,
                               scale: job.display.scale, image: image)
    }

    // MARK: - Windows

    /// Captures one window by id (`kCGWindowNumber` / `SCWindow.windowID`).
    ///
    /// - includeShadow: true lets ScreenCaptureKit size the image with transparent shadow margins;
    ///   false returns exactly the window at native resolution with transparent rounded corners.
    /// - opaque: composites the result over white so it has no alpha channel.
    public func captureWindow(_ windowID: CGWindowID, includeShadow: Bool,
                              opaque: Bool = false) async throws -> CGImage {
        guard ScreenCapturePermission.isGranted else { throw CaptureError.permissionDenied }
        let content = try await Self.mapErrors {
            try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        }
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.windowNotFound(windowID)
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCScreenshotConfiguration()
        config.showsCursor = false
        config.ignoreShadows = !includeShadow
        if !includeShadow {
            let scale = CGFloat(filter.pointPixelScale)
            config.width = Int((filter.contentRect.width * scale).rounded())
            config.height = Int((filter.contentRect.height * scale).rounded())
        }
        let output = try await Self.mapErrors {
            try await SCScreenshotManager.captureScreenshot(contentFilter: filter, configuration: config)
        }
        guard let image = output.sdrImage else { throw CaptureError.noImage }
        guard opaque else { return image }
        guard let flat = ImageProcessing.flattened(image) else { throw CaptureError.noImage }
        return flat
    }

    // MARK: - Helpers

    private static func mapErrors<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as CaptureError {
            throw error
        } catch {
            let nsError = error as NSError
            if nsError.domain == SCStreamErrorDomain, nsError.code == SCStreamError.userDeclined.rawValue {
                throw CaptureError.permissionDenied
            }
            throw CaptureError.captureFailed(nsError.localizedDescription)
        }
    }
}
