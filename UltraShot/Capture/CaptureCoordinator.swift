import AppKit
import CaptureKit
import UltraShotCore

/// Screenshot flows: area, fullscreen, window, and area followed by annotation.
///
/// Every overlay flow freezes all displays first (one ScreenCaptureKit snapshot each, or the
/// debug fake snapshot), shows them in a ``CaptureSession`` and crops the result from the
/// frozen image. Window captures are taken live by window id. Results go to
/// ``AppModel/deliver(_:)``.
@MainActor
final class CaptureCoordinator {
    weak var model: AppModel?

    let stillCapture = StillCapture()
    private var session: CaptureSession?
    /// A flow is preparing its snapshots (guards double hotkey presses).
    private var isStarting = false

    /// Snapshots are being taken or an overlay is up.
    var isActive: Bool {
        isStarting || session != nil
    }

    func captureArea() {
        begin(.area)
    }

    func captureWindow() {
        begin(.window)
    }

    func captureAreaAndAnnotate() {
        begin(.annotate)
    }

    /// Captures the display under the pointer right away, without an overlay.
    func captureFullscreen() {
        guard model?.canBeginModalFlow("capture fullscreen") == true else { return }
        isStarting = true
        Task { @MainActor in
            defer { isStarting = false }
            let mouse = NSEvent.mouseLocation
            guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.screens.first,
                  let snapshot = await snapshots(of: [screen])?[screen.displayID] else { return }
            playShutter()
            await output(snapshot.image, scale: snapshot.pixelsPerPoint.width, label: "fullscreen")
        }
    }

    /// Closes an open overlay (quitting).
    func cancelActiveSession() {
        session?.cancel()
    }

    // MARK: - Overlay flows

    private func begin(_ intent: CaptureSession.Intent) {
        guard model?.canBeginModalFlow("capture") == true else { return }
        isStarting = true
        let start = ContinuousClock.now
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { isStarting = false }
            guard let snapshots = await snapshots(of: NSScreen.screens), !snapshots.isEmpty else { return }
            let snapshotTime = ContinuousClock.now - start
            let session = CaptureSession(intent: intent, snapshots: snapshots)
            session.onFinish = { [weak self] result in self?.finish(result, intent: intent) }
            self.session = session
            session.show()
            let total = ContinuousClock.now - start
            let fake = DebugLaunchHooks.useFakeSnapshot
            let snapshotMS = Self.milliseconds(snapshotTime)
            Log.capture.info("overlay visible after \(Self.milliseconds(total)) ms (snapshots \(snapshotMS) ms, \(snapshots.count) display(s), fake \(fake))")
        }
    }

    private func finish(_ result: CaptureSession.Result, intent: CaptureSession.Intent) {
        session = nil
        switch result {
        case .cancelled:
            Log.capture.info("capture cancelled")
        case let .area(screen, rect, snapshot):
            guard let image = snapshot.crop(toLocalRect: rect) else {
                Log.capture.error("crop failed for \(String(describing: rect), privacy: .public)")
                return
            }
            playShutter()
            if intent == .annotate {
                annotate(snapshot: snapshot, screen: screen, selection: rect)
            } else {
                Task { await output(image, scale: snapshot.pixelsPerPoint.width, label: "area") }
            }
        case let .window(window, screen):
            Task { await captureWindow(window, scale: screen.backingScaleFactor) }
        }
    }

    private func captureWindow(_ window: WindowInfo, scale: CGFloat) async {
        guard let model else { return }
        guard ScreenCapturePermission.isGranted else {
            Log.capture.notice("window capture needs Screen Recording permission")
            model.showOnboarding()
            return
        }
        do {
            let image = try await stillCapture.captureWindow(window.id, includeShadow: model.settings.screenshots.windowShadow)
            playShutter()
            await output(image, scale: scale, label: "window")
        } catch {
            report(error, while: "window capture")
        }
    }

    private func annotate(snapshot: DisplaySnapshot, screen: NSScreen, selection: CGRect) {
        guard let model else { return }
        model.annotation.annotate(background: snapshot.image, screen: screen, initialSelection: selection) { [weak self] outcome in
            guard let self else { return }
            switch outcome {
            case let .copy(image):
                Task { await self.outputAnnotation(image, scale: snapshot.pixelsPerPoint.width, action: .copy) }
            case let .save(image):
                Task { await self.outputAnnotation(image, scale: snapshot.pixelsPerPoint.width, action: .save) }
            case .cancelled:
                Log.capture.info("annotation cancelled")
            }
        }
    }

    // MARK: - Output

    private func output(_ image: CGImage, scale: CGFloat, label: String) async {
        guard let model else { return }
        do {
            let written = try await CaptureOutput.write(image, scale: scale, settings: model.settings.screenshots, store: model.captureStore)
            let name = written.url.lastPathComponent
            Log.capture.info("\(label, privacy: .public) capture \(written.pixelWidth)x\(written.pixelHeight) -> \(name, privacy: .public)")
            model.deliver(CapturedItem(screenshot: written))
        } catch {
            report(error, while: "\(label) capture")
        }
    }

    private func outputAnnotation(_ image: CGImage, scale: CGFloat, action: AppModel.AnnotationAction) async {
        guard let model else { return }
        do {
            let written = try await CaptureOutput.write(image, scale: scale, settings: model.settings.screenshots, store: model.captureStore)
            model.deliverAnnotation(CapturedItem(screenshot: written), action: action)
        } catch {
            report(error, while: "annotation output")
        }
    }

    // MARK: - Snapshots

    /// Frozen images of `screens`, keyed by display id. `nil` when capturing is not possible
    /// (missing permission opens onboarding).
    private func snapshots(of screens: [NSScreen]) async -> [CGDirectDisplayID: DisplaySnapshot]? {
        if DebugLaunchHooks.useFakeSnapshot {
            return Dictionary(uniqueKeysWithValues: screens.map { screen in
                let image = DebugLaunchHooks.fakeSnapshotImage(size: screen.frame.size, scale: screen.backingScaleFactor)
                let snapshot = DisplaySnapshot(displayID: screen.displayID, frame: screen.frame, scale: screen.backingScaleFactor, image: image)
                return (screen.displayID, snapshot)
            })
        }
        guard let model else { return nil }
        guard ScreenCapturePermission.isGranted else {
            Log.capture.notice("capture needs Screen Recording permission: showing onboarding")
            model.showOnboarding()
            return nil
        }
        let options = SnapshotOptions(
            hideDesktopIcons: model.settings.general.hideDesktopIcons,
            showCursor: model.settings.screenshots.showCursor
        )
        do {
            let snapshots = try await stillCapture.snapshotDisplays(screens.compactMap(DisplayDescriptor.init(screen:)), options: options)
            return Dictionary(snapshots.map { ($0.displayID, $0) }, uniquingKeysWith: { first, _ in first })
        } catch {
            report(error, while: "display snapshot")
            return nil
        }
    }

    private func report(_ error: any Error, while action: String) {
        Log.capture.error("\(action, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        if case CaptureError.permissionDenied = error {
            model?.showOnboarding()
        } else {
            NSSound.beep()
        }
    }

    private func playShutter() {
        if model?.settings.general.playSounds == true { ShutterSound.play() }
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000)
    }
}
