import CoreMedia

/// Pure pause/resume bookkeeping on the host clock (the clock ScreenCaptureKit stamps its
/// sample buffers with).
///
/// Paused spans are cut out of the timeline: `adjusted(_:)` maps a host time to a time on the
/// recorded timeline by subtracting every paused span before it. A time inside a paused span
/// maps to the instant the pause began, so samples captured while paused can be detected with
/// `isPaused(at:)` and dropped.
public struct PauseClock: Sendable, Equatable {
    /// One paused span. `end` is `nil` while the pause is ongoing.
    public struct Interval: Sendable, Equatable {
        public let start: CMTime
        public fileprivate(set) var end: CMTime?
    }

    /// Host time the recorded timeline starts at (the first video frame). `nil` until started.
    public private(set) var startTime: CMTime?
    public private(set) var intervals: [Interval] = []

    public init() {}

    /// True while a pause is ongoing.
    public var isPaused: Bool { intervals.last.map { $0.end == nil } ?? false }

    /// Sets the start of the recorded timeline. Only the first call has an effect.
    public mutating func start(at time: CMTime) {
        if startTime == nil { startTime = time }
    }

    /// Begins a pause. Returns false (no-op) when already paused.
    @discardableResult
    public mutating func pause(at time: CMTime) -> Bool {
        guard !isPaused else { return false }
        let floor = intervals.last?.end ?? time
        intervals.append(Interval(start: max(time, floor), end: nil))
        return true
    }

    /// Ends the ongoing pause. Returns false (no-op) when not paused.
    @discardableResult
    public mutating func resume(at time: CMTime) -> Bool {
        guard isPaused, let last = intervals.indices.last else { return false }
        intervals[last].end = max(time, intervals[last].start)
        return true
    }

    /// Total paused time that elapsed before `time` (an ongoing pause counts up to `time`).
    public func offset(at time: CMTime) -> CMTime {
        intervals.reduce(CMTime.zero) { total, interval in
            guard interval.start < time else { return total }
            let end = min(interval.end ?? time, time)
            return total + (end - interval.start)
        }
    }

    /// True when `time` falls inside a paused span (the boundaries are not paused).
    public func isPaused(at time: CMTime) -> Bool {
        intervals.contains { interval in
            guard time > interval.start else { return false }
            guard let end = interval.end else { return true }
            return time < end
        }
    }

    /// Maps a host time to the recorded timeline (`time` minus the paused time before it).
    public func adjusted(_ time: CMTime) -> CMTime {
        time - offset(at: time)
    }

    /// Recorded time between `startTime` and `now`, excluding pauses. Zero before `start(at:)`.
    public func recordedDuration(now: CMTime) -> CMTime {
        guard let startTime, now > startTime else { return .zero }
        return adjusted(now) - adjusted(startTime)
    }
}

enum HostClock {
    /// Current host time, the time base of ScreenCaptureKit sample buffers.
    static func now() -> CMTime { CMClockGetTime(CMClockGetHostTimeClock()) }
}
