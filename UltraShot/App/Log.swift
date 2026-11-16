import os

/// App-target loggers. The subsystem is the bundle id (UltraShotCore logs under the same one).
///
///     log show --predicate 'subsystem == "dev.christiancuri.ultrashot"' --last 5m
enum Log {
    static let subsystem = "dev.christiancuri.ultrashot"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let thumbnail = Logger(subsystem: subsystem, category: "thumbnail")
    static let recording = Logger(subsystem: subsystem, category: "recording")
    static let annotate = Logger(subsystem: subsystem, category: "annotate")
    static let hotkeys = Logger(subsystem: subsystem, category: "hotkeys")
}
