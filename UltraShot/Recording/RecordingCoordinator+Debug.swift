import AppKit
import AVFoundation
import CaptureKit
import UltraShotCore

/// Debug-only automation of the record flow, so it can run end to end without synthetic input.
///
/// - `-debug-open record` runs the real flow. With `ULTRASHOT_DEBUG_AUTORECORD="<area>;<seconds>"`
///   it selects `<area>` on the main screen, records for `<seconds>` and stops (the result goes
///   through `AppModel.deliver`). `<area>` is `x,y,w,h` (overlay-local points of the main
///   screen, y up), `full`, or `window` (a window UltraShot creates for the purpose).
///   `ULTRASHOT_DEBUG_AUTOPAUSE=1` pauses at 1/3 and resumes at 2/3 of `<seconds>`;
///   `ULTRASHOT_DEBUG_AUTODISCARD=1` discards at the end instead of stopping. The stop goes
///   through ``RecordingCoordinator/recordScreen()``, the shortcut's path.
///   `ULTRASHOT_DEBUG_AUTOINTERRUPT=<ms>` makes the stream "stop by itself" halfway, then
///   presses Stop `<ms>` later (the stop/interruption race). `ULTRASHOT_DEBUG_AUTOSTOP_MS=<ms>`
///   presses Record Screen `<ms>` after committing, while the recorder is still starting.
/// - `-debug-open record-panel` shows the panel over the fake snapshot without capturing; with
///   `ULTRASHOT_DEBUG_AUTORECORD` it commits and shows the HUD (demo, no capture) for `<seconds>`.
///   Without it, `ULTRASHOT_DEBUG_WINDOWMODE="x,y"` turns on window pick mode and hovers that
///   overlay-local point of the main screen. Add `ULTRASHOT_DEBUG_CAPTURABLE_OVERLAY=1` to
///   screenshot the overlay and HUD windows.
struct DebugAutoRecord {
    enum Area: Equatable {
        case rect(CGRect)
        case full
        case window
    }

    let area: Area
    let seconds: Double
    let pauses: Bool
    var discards = false

    /// The parsed environment, or `nil` (always `nil` in Release).
    static var current: DebugAutoRecord? {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        guard let spec = environment["ULTRASHOT_DEBUG_AUTORECORD"] else { return nil }
        var parsed = parse(spec, pauses: environment["ULTRASHOT_DEBUG_AUTOPAUSE"] == "1")
        parsed?.discards = environment["ULTRASHOT_DEBUG_AUTODISCARD"] == "1"
        return parsed
        #else
        return nil
        #endif
    }

    static var isActive: Bool { current != nil }

    static func parse(_ spec: String, pauses: Bool) -> DebugAutoRecord? {
        let parts = spec.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let seconds = Double(parts[1]), seconds > 0 else { return nil }
        switch parts[0] {
        case "full":
            return DebugAutoRecord(area: .full, seconds: seconds, pauses: pauses)
        case "window":
            return DebugAutoRecord(area: .window, seconds: seconds, pauses: pauses)
        default:
            let numbers = parts[0].split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard numbers.count == 4 else { return nil }
            return DebugAutoRecord(
                area: .rect(CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])),
                seconds: seconds,
                pauses: pauses
            )
        }
    }
}

/// State kept alive for the automation.
@MainActor
private enum DebugAutomationState {
    /// The window recorded by `ULTRASHOT_DEBUG_AUTORECORD="window;…"`.
    static var window: NSWindow?
}

extension RecordingCoordinator {
    /// `-debug-open record-panel`: the pre-record panel over the fake snapshot background.
    func debugShowPanel() {
        #if DEBUG
        beginSelection(demo: true)
        #endif
    }

    /// Applies `ULTRASHOT_DEBUG_AUTORECORD` to a freshly shown selection overlay. In the
    /// `record-panel` demo without it, pre-selects a centered rect so the panel is visible.
    func debugSelectionShown(_ controller: RecordSelectionController) {
        #if DEBUG
        guard let screen = NSScreen.screens.first, let view = controller.view(for: screen) else { return }
        guard let auto = DebugAutoRecord.current else {
            if let hover = ProcessInfo.processInfo.environment["ULTRASHOT_DEBUG_WINDOWMODE"] {
                let numbers = hover.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                if numbers.count == 2 { controller.debugHover(at: CGPoint(x: numbers[0], y: numbers[1]), on: screen) }
            } else if DebugLaunchHooks.requestedSurface == "record-panel", controller.selectedArea == nil {
                let size = CGSize(width: min(640, view.bounds.width / 2), height: min(400, view.bounds.height / 2))
                controller.select(
                    CGRect(x: view.bounds.midX - size.width / 2, y: view.bounds.midY - size.height / 2, width: size.width, height: size.height),
                    on: screen
                )
            }
            return
        }
        Log.recording.info("autorecord: \(String(describing: auto.area), privacy: .public) for \(auto.seconds) s, pauses \(auto.pauses)")
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            switch auto.area {
            case .rect(let rect):
                controller.select(rect, on: screen)
            case .full:
                controller.select(view.bounds, on: screen)
            case .window:
                guard let window = await Self.makeDebugWindow(on: screen) else {
                    Log.recording.error("autorecord: debug window not found")
                    return
                }
                controller.pick(window, on: screen)
            }
            try? await Task.sleep(for: .milliseconds(400))
            controller.commit()
            if let delay = Int(ProcessInfo.processInfo.environment["ULTRASHOT_DEBUG_AUTOSTOP_MS"] ?? "") {
                try? await Task.sleep(for: .milliseconds(delay))
                Log.recording.info("autorecord: pressing Record Screen while starting")
                self.recordScreen()
            }
        }
        #endif
    }

    /// Schedules the automated pause, resume and stop.
    func debugRecordingStarted() {
        #if DEBUG
        guard let auto = DebugAutoRecord.current else { return }
        Task { @MainActor [weak self] in
            if let delay = Int(ProcessInfo.processInfo.environment["ULTRASHOT_DEBUG_AUTOINTERRUPT"] ?? "") {
                try? await Task.sleep(for: .seconds(auto.seconds / 2))
                Log.recording.info("autorecord: simulating an unexpected stream stop")
                self?.debugSimulateInterruption()
                try? await Task.sleep(for: .milliseconds(delay))
                Log.recording.info("autorecord: stopping during the interruption")
                self?.stop() // no-op once the recording already ended
                return
            }
            if auto.pauses {
                try? await Task.sleep(for: .seconds(auto.seconds / 3))
                self?.togglePause()
                try? await Task.sleep(for: .seconds(auto.seconds / 3))
                self?.togglePause()
                try? await Task.sleep(for: .seconds(auto.seconds / 3))
            } else {
                try? await Task.sleep(for: .seconds(auto.seconds))
            }
            if auto.discards {
                Log.recording.info("autorecord: discarding")
                self?.discard()
            } else {
                Log.recording.info("autorecord: stopping")
                self?.recordScreen()
            }
        }
        #endif
    }

    /// Logs the delivered file for external checks and closes the debug window.
    func debugRecordingEnded(item: CapturedItem?) {
        #if DEBUG
        guard DebugAutoRecord.isActive else { return }
        DebugAutomationState.window?.orderOut(nil)
        DebugAutomationState.window = nil
        if let item {
            let path = item.fileURL.path
            let duration = item.duration ?? 0
            Log.recording.info("autorecord: delivered \(path, privacy: .public) \(item.pixelWidth)x\(item.pixelHeight) \(duration) s")
            Task { await Self.logMetadata(of: item.fileURL) }
        } else {
            Log.recording.info("autorecord: ended without a file")
        }
        #endif
    }

    #if DEBUG
    /// Container metadata of the delivered file (no frame is decoded).
    private static func logMetadata(of url: URL) async {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration).seconds
            let video = try await asset.loadTracks(withMediaType: .video)
            let audio = try await asset.loadTracks(withMediaType: .audio)
            let size = try await video.first?.load(.naturalSize) ?? .zero
            let dimensions = "\(Int(size.width))x\(Int(size.height))"
            Log.recording.info("autorecord: file metadata duration \(duration) s, video tracks \(video.count) \(dimensions), audio tracks \(audio.count)")
        } catch {
            Log.recording.error("autorecord: reading metadata failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// A plain titled window of our own, for window-target automation.
    private static func makeDebugWindow(on screen: NSScreen) async -> WindowInfo? {
        let frame = NSRect(x: screen.frame.minX + 200, y: screen.frame.minY + 200, width: 480, height: 300)
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "UltraShot debug recording target"
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(srgbRed: 0.2, green: 0.45, blue: 0.85, alpha: 1)
        window.level = .floating
        window.orderFrontRegardless()
        DebugAutomationState.window = window
        try? await Task.sleep(for: .milliseconds(300))
        let id = CGWindowID(window.windowNumber)
        let entries = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]] ?? []
        guard let bounds = (entries.first?[kCGWindowBounds as String] as? NSDictionary).flatMap({ CGRect(dictionaryRepresentation: $0) })
        else { return nil }
        return WindowInfo(id: id, frameCG: bounds, ownerPID: getpid(), ownerName: "UltraShot", title: window.title, layer: 0)
    }
    #endif
}
