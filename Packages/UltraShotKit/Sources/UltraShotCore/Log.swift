import os

/// Loggers for UltraShotCore.
enum Log {
    static let subsystem = "dev.christiancuri.ultrashot"

    /// Settings, state and capture-file persistence.
    static let core = Logger(subsystem: subsystem, category: "core")
}
