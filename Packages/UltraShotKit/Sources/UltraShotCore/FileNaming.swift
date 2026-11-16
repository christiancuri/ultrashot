import Foundation

/// Builds file names for saved captures from a user template.
///
/// Template tokens:
/// - `{date}`: `yyyy-MM-dd`
/// - `{time}`: `HH.mm.ss` (24-hour)
/// - `{kind}`: ``CapturedItem/Kind/displayName`` (`Screenshot` / `Recording`)
///
/// Unknown tokens are left as-is. Dates use the Gregorian calendar with ASCII digits,
/// independent of the user's locale.
public enum FileNaming {
    public static let defaultTemplate = "UltraShot {date} at {time}"

    /// Used when a rendered name sanitizes to nothing.
    static let fallbackName = "UltraShot"
    /// Maximum length (in characters) of a sanitized base name.
    static let maxNameLength = 200

    /// Renders `template` for a capture of `kind` taken at `date`, as a sanitized base name without extension.
    public static func render(template: String, kind: CapturedItem.Kind, date: Date, timeZone: TimeZone = .current) -> String {
        let parts = components(of: date, in: timeZone)
        let rendered = template
            .replacingOccurrences(of: "{date}", with: String(format: "%04d-%02d-%02d", parts.year, parts.month, parts.day))
            .replacingOccurrences(of: "{time}", with: String(format: "%02d.%02d.%02d", parts.hour, parts.minute, parts.second))
            .replacingOccurrences(of: "{kind}", with: kind.displayName)
        return sanitize(rendered)
    }

    /// ``render(template:kind:date:timeZone:)`` plus `.fileExtension` (no dot added if the extension is empty).
    public static func fileName(
        template: String,
        kind: CapturedItem.Kind,
        date: Date,
        fileExtension: String,
        timeZone: TimeZone = .current
    ) -> String {
        let base = render(template: template, kind: kind, date: date, timeZone: timeZone)
        return fileExtension.isEmpty ? base : "\(base).\(fileExtension)"
    }

    /// Makes `name` safe as a macOS file name: `/` and `:` become `-`, control characters and
    /// line breaks are removed, surrounding whitespace and leading dots are dropped, and the
    /// result is capped at 200 characters. An empty result becomes `UltraShot`.
    public static func sanitize(_ name: String) -> String {
        let scalars = name.unicodeScalars.compactMap { scalar -> Unicode.Scalar? in
            switch scalar {
            case "/", ":": return "-"
            default:
                let isControl = scalar.properties.generalCategory == .control
                return isControl || CharacterSet.newlines.contains(scalar) ? nil : scalar
            }
        }
        var result = String(String.UnicodeScalarView(scalars))
        result = trimmed(result)
        while result.hasPrefix(".") {
            result = trimmed(String(result.dropFirst()))
        }
        if result.count > maxNameLength {
            result = trimmed(String(result.prefix(maxNameLength)))
        }
        return result.isEmpty ? fallbackName : result
    }

    /// `folder/fileName` if nothing exists there, otherwise the first free `name 2.ext`, `name 3.ext`, ...
    public static func uniqueURL(in folder: URL, fileName: String, fileManager: FileManager = .default) -> URL {
        let candidate = folder.appending(path: fileName, directoryHint: .notDirectory)
        guard fileManager.fileExists(atPath: candidate.path(percentEncoded: false)) else { return candidate }

        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var index = 2
        while true {
            let name = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            let url = folder.appending(path: name, directoryHint: .notDirectory)
            if !fileManager.fileExists(atPath: url.path(percentEncoded: false)) { return url }
            index += 1
        }
    }

    // MARK: - Internal

    /// `yyyyMMdd-HHmmss`, used for temporary and backup file names.
    static func compactStamp(_ date: Date, timeZone: TimeZone = .current) -> String {
        let parts = components(of: date, in: timeZone)
        return String(
            format: "%04d%02d%02d-%02d%02d%02d",
            parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second
        )
    }

    private struct DateParts {
        var year: Int
        var month: Int
        var day: Int
        var hour: Int
        var minute: Int
        var second: Int
    }

    private static func components(of date: Date, in timeZone: TimeZone) -> DateParts {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return DateParts(
            year: parts.year ?? 0,
            month: parts.month ?? 0,
            day: parts.day ?? 0,
            hour: parts.hour ?? 0,
            minute: parts.minute ?? 0,
            second: parts.second ?? 0
        )
    }

    private static func trimmed(_ string: String) -> String {
        string.trimmingCharacters(in: .whitespaces)
    }
}
