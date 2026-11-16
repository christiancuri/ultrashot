import Foundation

/// Loads and saves ``Settings`` (`settings.json`) and ``AppState`` (`state.json`) in one directory.
///
/// - Missing file: defaults.
/// - Unreadable settings, or a newer `schemaVersion` written by a later app version: the file is
///   moved aside as `settings.corrupt-<stamp>.json` and defaults are returned, so user data is
///   never silently overwritten by the next save.
/// - Unreadable state: defaults (state is disposable, so no backup is kept).
public struct SettingsStore: Sendable {
    public static let settingsFileName = "settings.json"
    public static let stateFileName = "state.json"

    public let directory: URL

    /// - Parameter directory: where both JSON files live; created on first save.
    public init(directory: URL) {
        self.directory = directory
    }

    /// `~/Library/Application Support/dev.christiancuri.ultrashot`.
    public static func standard() -> SettingsStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return SettingsStore(directory: support.appending(path: "dev.christiancuri.ultrashot", directoryHint: .isDirectory))
    }

    public var settingsURL: URL { directory.appending(path: Self.settingsFileName, directoryHint: .notDirectory) }
    public var stateURL: URL { directory.appending(path: Self.stateFileName, directoryHint: .notDirectory) }

    /// Loads the settings. Never throws: any problem yields defaults (see the type docs).
    public func loadSettings() -> Settings {
        guard let data = try? Data(contentsOf: settingsURL) else { return .defaults }
        do {
            var settings = try JSONDecoder().decode(Settings.self, from: data)
            guard settings.schemaVersion <= Settings.currentSchemaVersion else {
                Log.core.error("Unsupported settings schemaVersion \(settings.schemaVersion, privacy: .public)")
                backUpUnreadableSettings()
                return .defaults
            }
            // Older versions decode tolerantly; future migrations go here.
            settings.schemaVersion = Settings.currentSchemaVersion
            return settings
        } catch {
            Log.core.error("Unreadable \(Self.settingsFileName, privacy: .public): \(String(describing: error), privacy: .public)")
            backUpUnreadableSettings()
            return .defaults
        }
    }

    /// Atomically writes `settings`, creating ``directory`` if needed.
    public func save(_ settings: Settings) throws {
        try write(settings, to: settingsURL)
    }

    /// Loads the app state. Never throws: missing, unreadable or newer files yield defaults.
    public func loadState() -> AppState {
        guard let data = try? Data(contentsOf: stateURL) else { return AppState() }
        do {
            var state = try JSONDecoder().decode(AppState.self, from: data)
            guard state.schemaVersion <= AppState.currentSchemaVersion else {
                Log.core.notice("Ignoring state with schemaVersion \(state.schemaVersion, privacy: .public)")
                return AppState()
            }
            state.schemaVersion = AppState.currentSchemaVersion
            return state
        } catch {
            Log.core.notice("Ignoring unreadable \(Self.stateFileName, privacy: .public): \(String(describing: error), privacy: .public)")
            return AppState()
        }
    }

    /// Atomically writes `state`, creating ``directory`` if needed.
    public func save(_ state: AppState) throws {
        try write(state, to: stateURL)
    }

    // MARK: - Private

    private func write(_ value: some Encodable, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private func backUpUnreadableSettings() {
        let name = "settings.corrupt-\(FileNaming.compactStamp(Date())).json"
        let backup = FileNaming.uniqueURL(in: directory, fileName: name)
        do {
            try FileManager.default.moveItem(at: settingsURL, to: backup)
            Log.core.notice("Moved unreadable settings to \(backup.lastPathComponent, privacy: .public)")
        } catch {
            Log.core.fault("Could not back up unreadable settings: \(error.localizedDescription, privacy: .public)")
        }
    }
}
