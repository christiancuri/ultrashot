import Foundation
import os
import Synchronization

/// Debug-only capture performance tracing.
///
/// ``measure(_:_:)`` times a phase and logs it (category `perf`). With
/// `ULTRASHOT_DEBUG_STALLS=1`, a watchdog thread also pings the main queue every 16 ms and
/// logs every main-thread stall longer than 50 ms with the phases that ran during it.
/// Release builds run the measured work directly and log nothing.
enum PerfTrace {
    #if DEBUG
    private static let logger = Logger(subsystem: Log.subsystem, category: "perf")
    #endif

    /// Runs `body`, logging how long it took as `phase` (Debug only).
    static func measure<T>(_ phase: String, _ body: () throws -> T) rethrows -> T {
        #if DEBUG
        let start = ContinuousClock.now
        StallWatchdog.shared.mark(phase)
        defer {
            logger.info("phase \(phase, privacy: .public) \(milliseconds(ContinuousClock.now - start), format: .fixed(precision: 1)) ms")
        }
        #endif
        return try body()
    }

    /// Async variant of ``measure(_:_:)``: the wall time includes any suspension.
    static func measure<T>(
        _ phase: String,
        isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> T
    ) async rethrows -> T {
        #if DEBUG
        let start = ContinuousClock.now
        StallWatchdog.shared.mark(phase)
        defer {
            logger.info("phase \(phase, privacy: .public) \(milliseconds(ContinuousClock.now - start), format: .fixed(precision: 1)) ms")
        }
        #endif
        return try await body()
    }

    /// Starts the stall watchdog once, when `ULTRASHOT_DEBUG_STALLS=1` (Debug only).
    static func startStallWatchdogIfRequested() {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["ULTRASHOT_DEBUG_STALLS"] == "1" else { return }
        StallWatchdog.shared.start()
        #endif
    }

    static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    #if DEBUG
    /// Pings the main queue from a background thread and reports late answers.
    private final class StallWatchdog: Sendable {
        static let shared = StallWatchdog()

        private struct State {
            var started = false
            /// Recent phase marks, oldest first.
            var marks: [(time: ContinuousClock.Instant, phase: String)] = []
        }

        private let state = Mutex(State())
        private static let threshold = Duration.milliseconds(50)

        func mark(_ phase: String) {
            state.withLock { state in
                state.marks.append((ContinuousClock.now, phase))
                if state.marks.count > 32 { state.marks.removeFirst(state.marks.count - 32) }
            }
        }

        func start() {
            let shouldStart = state.withLock { state in
                defer { state.started = true }
                return !state.started
            }
            guard shouldStart else { return }
            let thread = Thread { [self] in run() }
            thread.name = "UltraShot stall watchdog"
            thread.qualityOfService = .userInteractive
            thread.start()
            PerfTrace.logger.info("stall watchdog on (threshold \(Self.threshold.components.attoseconds / 1_000_000_000_000_000) ms)")
        }

        private func run() {
            while true {
                let posted = ContinuousClock.now
                let answered = DispatchSemaphore(value: 0)
                DispatchQueue.main.async { answered.signal() }
                answered.wait()
                let latency = ContinuousClock.now - posted
                if latency > Self.threshold { report(latency, since: posted) }
                Thread.sleep(forTimeInterval: 0.016)
            }
        }

        /// Logs a stall with the phase in progress when it began and every phase marked during it.
        private func report(_ latency: Duration, since posted: ContinuousClock.Instant) {
            let phases = state.withLock { state -> [String] in
                let before = state.marks.last { $0.time <= posted }.map { "\($0.phase) (in progress)" }
                let during = state.marks.filter { $0.time > posted }.map(\.phase)
                return (before.map { [$0] } ?? []) + during
            }
            let list = phases.isEmpty ? "none" : phases.joined(separator: " > ")
            PerfTrace.logger.error("main thread stall \(PerfTrace.milliseconds(latency), format: .fixed(precision: 0)) ms, phases: \(list, privacy: .public)")
        }
    }
    #endif
}
