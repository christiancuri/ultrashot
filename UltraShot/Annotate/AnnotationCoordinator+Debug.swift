import AnnotateKit
import AppKit
import CaptureKit

/// Debug entry point (`-debug-open annotate-sample`) and automation for visual checks.
///
/// Environment (Debug builds only):
/// - `ULTRASHOT_DEBUG_ANNOTATE_FILE=<path>`: open that image file (file mode) instead of
///   the synthetic screen.
/// - `ULTRASHOT_DEBUG_ANNOTATE_SELECTION="x,y,w,h"`: initial selection (screen points,
///   bottom-left), e.g. touching an edge to check toolbar flipping. `none` = drag one.
/// - `ULTRASHOT_DEBUG_ANNOTATE_SCRIPT=<steps>`: comma-separated scripted actions run once
///   the overlay is up: `1`/`sample` (one object per tool, the rectangle selected, the
///   arrow tool active), `text` (start editing a two-line text), `palette` (open the color
///   popover), `textalign` (live editor over the same committed text), `selftest`
///   (interaction checks, logged PASS/FAIL), `tool=<name>`, `copy` (scripted Copy after a delay).
/// - `ULTRASHOT_DEBUG_ANNOTATE_EXPORT=<path>`: on Copy/Save, write the exported PNG there
///   and log its metadata instead of delivering it. Implies a scripted `copy` when a
///   script is given.
/// - `ULTRASHOT_DEBUG_ANNOTATE_DELAY=<seconds>`: wait before the scripted Copy (default 3).
/// - `ULTRASHOT_DEBUG_ANNOTATE_FINISH=copy|save`: every session, whatever opened it (capture
///   area & annotate, the thumbnail's Annotate), runs `ULTRASHOT_DEBUG_ANNOTATE_SCRIPT` and
///   then finishes with a scripted Copy or Save through the caller's real completion.
extension AnnotationCoordinator {
    /// Applies `ULTRASHOT_DEBUG_ANNOTATE_FINISH` to a freshly shown session.
    func debugAutomate(_ session: AnnotationSession) {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        guard let finish = environment["ULTRASHOT_DEBUG_ANNOTATE_FINISH"], ["copy", "save"].contains(finish) else { return }
        var steps = (environment["ULTRASHOT_DEBUG_ANNOTATE_SCRIPT"] ?? "").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "copy" && $0 != "save" }
        steps.append(finish)
        let delay = Double(environment["ULTRASHOT_DEBUG_ANNOTATE_DELAY"] ?? "") ?? 3
        Task { @MainActor [weak session] in
            try? await Task.sleep(for: .milliseconds(400))
            session?.debugRun(steps, copyDelay: delay)
        }
        #endif
    }

    func debugShowSample() {
        let environment = ProcessInfo.processInfo.environment
        let exportPath = environment["ULTRASHOT_DEBUG_ANNOTATE_EXPORT"]
        let completion: @MainActor (AnnotationOutcome) -> Void = { outcome in
            Self.debugDeliver(outcome, exportPath: exportPath)
        }

        if let file = environment["ULTRASHOT_DEBUG_ANNOTATE_FILE"], !file.isEmpty {
            annotate(imageAt: URL(fileURLWithPath: file), completion: completion)
        } else {
            let screen = Self.screenWithPointer()
            let size = screen.frame.size
            let background = DebugLaunchHooks.fakeSnapshotImage(size: size, scale: screen.backingScaleFactor)
            annotate(
                background: background,
                screen: screen,
                initialSelection: Self.debugSelection(environment["ULTRASHOT_DEBUG_ANNOTATE_SELECTION"], screenSize: size),
                completion: completion
            )
        }

        #if DEBUG
        // With ULTRASHOT_DEBUG_ANNOTATE_FINISH the session's own automation runs the script.
        guard environment["ULTRASHOT_DEBUG_ANNOTATE_FINISH"] == nil,
              let script = environment["ULTRASHOT_DEBUG_ANNOTATE_SCRIPT"], !script.isEmpty else { return }
        var steps = script.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if exportPath != nil, !steps.contains("copy") { steps.append("copy") }
        let delay = Double(environment["ULTRASHOT_DEBUG_ANNOTATE_DELAY"] ?? "") ?? 3
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            self?.session?.debugRun(steps, copyDelay: delay)
        }
        #endif
    }

    private static func debugSelection(_ value: String?, screenSize: CGSize) -> CGRect? {
        if value == "none" { return nil }
        let numbers = (value ?? "").split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        if numbers.count == 4 {
            return CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
        }
        let size = CGSize(width: min(760, screenSize.width * 0.6), height: min(470, screenSize.height * 0.55))
        return CGRect(
            x: ((screenSize.width - size.width) / 2).rounded(),
            y: ((screenSize.height - size.height) / 2).rounded(),
            width: size.width,
            height: size.height
        )
    }

    private static func debugDeliver(_ outcome: AnnotationOutcome, exportPath: String?) {
        let image: CGImage
        let kind: String
        switch outcome {
        case .copy(let copied):
            image = copied
            kind = "copy"
        case .save(let saved):
            image = saved
            kind = "save"
        case .cancelled:
            Log.annotate.info("annotate-sample: cancelled")
            return
        }
        let space = image.colorSpace?.name.map { $0 as String } ?? "none"
        Log.annotate.info("annotate-sample: \(kind, privacy: .public) \(image.width)x\(image.height) px, \(space, privacy: .public)")
        guard let exportPath else { return }
        do {
            try ImageEncoder.write(image, to: URL(fileURLWithPath: exportPath), format: .png)
            Log.annotate.info("annotate-sample: exported to \(exportPath, privacy: .public)")
        } catch {
            Log.annotate.error("annotate-sample: export failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
