import CoreMedia
@testable import RecordingKit
import Testing

private func t(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 1_000_000) }
private func s(_ time: CMTime) -> Double { (time.seconds * 1_000).rounded() / 1_000 }

@Suite("PauseClock")
struct PauseClockTests {
    @Test func noPausesMeansNoOffset() {
        var clock = PauseClock()
        clock.start(at: t(100))
        #expect(s(clock.offset(at: t(105))) == 0)
        #expect(s(clock.adjusted(t(105))) == 105)
        #expect(s(clock.recordedDuration(now: t(103.5))) == 3.5)
        #expect(!clock.isPaused)
    }

    @Test func recordedDurationIsZeroBeforeStart() {
        var clock = PauseClock()
        #expect(clock.recordedDuration(now: t(50)) == .zero)
        clock.start(at: t(100))
        #expect(clock.recordedDuration(now: t(99)) == .zero)
    }

    @Test func startOnlyCountsFirstCall() {
        var clock = PauseClock()
        clock.start(at: t(100))
        clock.start(at: t(200))
        #expect(clock.startTime == t(100))
    }

    @Test func singlePauseIsCutOut() {
        var clock = PauseClock()
        clock.start(at: t(100))
        let paused = clock.pause(at: t(102)); #expect(paused)
        #expect(clock.isPaused)
        // Ongoing pause: the recorded time freezes at the pause point.
        #expect(s(clock.recordedDuration(now: t(103))) == 2)
        #expect(s(clock.offset(at: t(103))) == 1)
        let resumed = clock.resume(at: t(104.5)); #expect(resumed)
        #expect(!clock.isPaused)
        #expect(s(clock.offset(at: t(110))) == 2.5)
        #expect(s(clock.adjusted(t(110))) == 107.5)
        #expect(s(clock.recordedDuration(now: t(106))) == 3.5)
        // Before the pause nothing is subtracted.
        #expect(s(clock.adjusted(t(101))) == 101)
    }

    @Test func multiplePausesAccumulate() {
        var clock = PauseClock()
        clock.start(at: t(0))
        clock.pause(at: t(1)); clock.resume(at: t(2))     // 1 s
        clock.pause(at: t(3)); clock.resume(at: t(5.5))   // 2.5 s
        clock.pause(at: t(7)); clock.resume(at: t(7.25))  // 0.25 s
        #expect(s(clock.offset(at: t(10))) == 3.75)
        #expect(s(clock.recordedDuration(now: t(10))) == 6.25)
        // Between the second and third pause only the first two count.
        #expect(s(clock.offset(at: t(6))) == 3.5)
        #expect(s(clock.adjusted(t(6))) == 2.5)
        #expect(clock.intervals.count == 3)
    }

    @Test func pauseWhilePausedIsNoOp() {
        var clock = PauseClock()
        clock.start(at: t(0))
        let firstPause = clock.pause(at: t(1)); #expect(firstPause)
        let secondPause = clock.pause(at: t(2)); #expect(!secondPause)
        #expect(clock.intervals.count == 1)
        #expect(clock.intervals[0].start == t(1))
        clock.resume(at: t(3))
        #expect(s(clock.offset(at: t(4))) == 2)
    }

    @Test func resumeWhileRecordingIsNoOp() {
        var clock = PauseClock()
        clock.start(at: t(0))
        let resumedEarly = clock.resume(at: t(1)); #expect(!resumedEarly)
        #expect(clock.intervals.isEmpty)
        clock.pause(at: t(2)); clock.resume(at: t(3))
        let resumedTwice = clock.resume(at: t(4)); #expect(!resumedTwice)
        #expect(s(clock.offset(at: t(5))) == 1)
    }

    @Test func samplesInsidePauseAreDetectedAndFrozen() {
        var clock = PauseClock()
        clock.start(at: t(0))
        clock.pause(at: t(2)); clock.resume(at: t(4))
        #expect(!clock.isPaused(at: t(1.9)))
        #expect(!clock.isPaused(at: t(2)))
        #expect(clock.isPaused(at: t(3)))
        #expect(!clock.isPaused(at: t(4)))
        #expect(s(clock.adjusted(t(3))) == 2)
        #expect(s(clock.adjusted(t(4))) == 2)
        #expect(s(clock.adjusted(t(4.5))) == 2.5)
    }

    @Test func ongoingPauseMarksLaterSamplesPaused() {
        var clock = PauseClock()
        clock.start(at: t(0))
        clock.pause(at: t(5))
        #expect(clock.isPaused(at: t(6)))
        #expect(clock.isPaused(at: t(600)))
        #expect(s(clock.adjusted(t(9))) == 5)
    }

    @Test func pauseBeforeStartDoesNotReduceRecordedTime() {
        var clock = PauseClock()
        clock.pause(at: t(1)); clock.resume(at: t(3))
        clock.start(at: t(4))
        #expect(s(clock.recordedDuration(now: t(6))) == 2)
    }

    @Test func outOfOrderTimesAreClamped() {
        var clock = PauseClock()
        clock.start(at: t(0))
        clock.pause(at: t(5)); clock.resume(at: t(4)) // resume before pause → zero-length
        #expect(s(clock.offset(at: t(10))) == 0)
        clock.pause(at: t(3)); clock.resume(at: t(6)) // pause before the previous end → starts at 5
        #expect(clock.intervals[1].start == t(5))
        #expect(s(clock.offset(at: t(10))) == 1)
    }
}
