import CoreGraphics
import Foundation
import UltraShotCore

/// Debug-only environment switches that drive the capture and thumbnail flows end to end
/// without synthetic mouse or keyboard events. Every value is `nil`/`false` in Release.
///
/// - `ULTRASHOT_DEBUG_AUTOSELECT="x,y,w,h"`: capture-area and capture-annotate commit this
///   selection (points, main screen, origin bottom-left) about a second after the overlay opens.
/// - `ULTRASHOT_DEBUG_AUTOWINDOW=1`: window mode captures the topmost non-UltraShot window.
///   Use only with `ULTRASHOT_DEBUG_FAKE_SNAPSHOT=1`, and never look at the resulting image.
/// - `ULTRASHOT_DEBUG_PASTEBOARD=1`: clipboard writes go to a private named pasteboard
///   (``Clipboard/debugPasteboardName``).
/// - `ULTRASHOT_DEBUG_AUTOCLOSE=<seconds>|off`: overrides the thumbnail auto-close interval
///   (`off` = "Close automatically" off) without touching the saved settings.
/// - `ULTRASHOT_DEBUG_AUTOCLOSE_ACTION=close|saveAndClose`: overrides the auto-close action.
/// - `ULTRASHOT_DEBUG_QA_POSITION=left|right`: overrides the thumbnail position (keeps
///   automated runs away from a pointer resting in the corner, which pauses auto-close).
/// - `ULTRASHOT_DEBUG_EXPORT_DIR=<path>`: overrides the export folder (never write to the
///   real Desktop from tests).
/// - `ULTRASHOT_DEBUG_THUMBNAIL_ACTION=<action>[,<action>…]`: every two seconds after a
///   thumbnail appears, performs the next of `hover`, `copy`, `save`, `save-only`, `close`,
///   `delete`, `annotate`, `dragged` (a drop into another app ended), `menu-log` or
///   `saved-feedback` on it;
///   `<action>:screenshot` / `<action>:recording` limits it to one kind.
/// - `ULTRASHOT_DEBUG_AFTER_CAPTURE="screenshot=<flags>;recording=<flags>"`: overrides the
///   after-capture actions per kind without touching the saved settings. `<flags>` is a
///   `+`-separated subset of `thumbnail`, `copy`, `save`, or `none`; a kind left out keeps
///   its settings.
/// - `ULTRASHOT_DEBUG_FEED_URL=<url>`: Sparkle reads this appcast instead of `SUFeedURL`
///   (e.g. a local feed listing a higher version, to test the update check).
enum DebugAutomation {
    /// Any `ULTRASHOT_DEBUG_*` switch (or `-debug-open`) is set: an automated run.
    static var isActive: Bool {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        return environment.contains { $0.key.hasPrefix("ULTRASHOT_DEBUG_") && !$0.value.isEmpty }
            || UserDefaults.standard.string(forKey: "debug-open") != nil
        #else
        return false
        #endif
    }

    static var updateFeedURL: String? {
        value("ULTRASHOT_DEBUG_FEED_URL")
    }

    static var autoSelectRect: CGRect? {
        guard let raw = value("ULTRASHOT_DEBUG_AUTOSELECT") else { return nil }
        let numbers = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard numbers.count == 4, numbers[2] > 0, numbers[3] > 0 else { return nil }
        return CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
    }

    static var autoWindow: Bool {
        value("ULTRASHOT_DEBUG_AUTOWINDOW") == "1"
    }

    static var usesDebugPasteboard: Bool {
        value("ULTRASHOT_DEBUG_PASTEBOARD") == "1"
    }

    enum AutoCloseOverride {
        case off
        case seconds(Double)
    }

    static var autoCloseOverride: AutoCloseOverride? {
        guard let raw = value("ULTRASHOT_DEBUG_AUTOCLOSE") else { return nil }
        if raw == "off" { return .off }
        return Double(raw).flatMap { $0 > 0 ? .seconds($0) : nil }
    }

    static var autoCloseAction: AutoCloseAction? {
        value("ULTRASHOT_DEBUG_AUTOCLOSE_ACTION").flatMap(AutoCloseAction.init(rawValue:))
    }

    static var exportFolder: URL? {
        value("ULTRASHOT_DEBUG_EXPORT_DIR").map { URL(filePath: ($0 as NSString).expandingTildeInPath, directoryHint: .isDirectory) }
    }

    static var quickAccessPosition: QuickAccessPosition? {
        value("ULTRASHOT_DEBUG_QA_POSITION").flatMap(QuickAccessPosition.init(rawValue:))
    }

    static var thumbnailAction: String? {
        value("ULTRASHOT_DEBUG_THUMBNAIL_ACTION")
    }

    /// The `ULTRASHOT_DEBUG_AFTER_CAPTURE` actions for `kind`, or `nil` to use the settings.
    static func afterCaptureActions(for kind: CapturedItem.Kind) -> AfterCaptureActions? {
        guard let raw = value("ULTRASHOT_DEBUG_AFTER_CAPTURE") else { return nil }
        for entry in raw.split(separator: ";") {
            let parts = entry.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[0] == kind.rawValue else { continue }
            let flags = Set(parts[1].split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) })
            return AfterCaptureActions(showThumbnail: flags.contains("thumbnail"), copyToClipboard: flags.contains("copy"), save: flags.contains("save"))
        }
        return nil
    }

    private static func value(_ key: String) -> String? {
        #if DEBUG
        let value = ProcessInfo.processInfo.environment[key]
        return value?.isEmpty == false ? value : nil
        #else
        return nil
        #endif
    }
}
