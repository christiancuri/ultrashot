import CoreGraphics
import Foundation
import Testing
@testable import UltraShotCore

struct ThumbnailLayoutTests {
    // A 1800×1169 screen with a 24 pt menu bar and a 70 pt Dock at the bottom.
    private let screen = CGRect(x: 0, y: 0, width: 1800, height: 1169)
    private let visible = CGRect(x: 0, y: 70, width: 1800, height: 1075)

    @Test func stopTwoIsCleanShotSize() {
        #expect(ThumbnailLayout.maxSize(forStop: 2) == CGSize(width: 209, height: 150))
    }

    @Test func stopsGrowAndClamp() {
        let widths = (1...5).map { ThumbnailLayout.maxSize(forStop: $0).width }
        #expect(widths == widths.sorted())
        #expect(Set(widths).count == 5)
        #expect(ThumbnailLayout.maxSize(forStop: 0) == ThumbnailLayout.maxSize(forStop: 1))
        #expect(ThumbnailLayout.maxSize(forStop: 9) == ThumbnailLayout.maxSize(forStop: 5))
    }

    @Test func screenAspectFitsTheBox() {
        // 3600×2338 (16:10.4) at stop 2: height-limited, 209×150 box.
        let size = ThumbnailLayout.cardSize(imageSize: CGSize(width: 3600, height: 2338), stop: 2)
        #expect(size.width <= 209 && size.height <= 150)
        #expect(abs(size.width / size.height - 3600 / 2338) < 0.02)
    }

    @Test func tallAndWideImagesKeepTheMinimum() {
        let tall = ThumbnailLayout.cardSize(imageSize: CGSize(width: 40, height: 2000), stop: 2)
        #expect(tall == CGSize(width: ThumbnailLayout.minimumSize.width, height: 150))
        let wide = ThumbnailLayout.cardSize(imageSize: CGSize(width: 4000, height: 30), stop: 2)
        #expect(wide == CGSize(width: 209, height: ThumbnailLayout.minimumSize.height))
        #expect(ThumbnailLayout.cardSize(imageSize: .zero, stop: 3) == ThumbnailLayout.maxSize(forStop: 3))
    }

    @Test func firstCardSitsBottomLeft() {
        let frames = ThumbnailLayout.frames(for: [CGSize(width: 209, height: 150)], position: .left, screenFrame: screen, visibleFrame: visible)
        #expect(frames == [CGRect(x: 40, y: 100, width: 209, height: 150)])
    }

    @Test func rightPositionAlignsEachCardToTheRightEdge() {
        let sizes = [CGSize(width: 209, height: 150), CGSize(width: 150, height: 120)]
        let frames = ThumbnailLayout.frames(for: sizes, position: .right, screenFrame: screen, visibleFrame: visible)
        #expect(frames.map(\.maxX) == [1760, 1760])
        #expect(frames[1].minY == 100 + 150 + ThumbnailLayout.spacing)
    }

    @Test func stackGrowsUpwardNewestAtBottom() {
        let sizes = Array(repeating: CGSize(width: 209, height: 150), count: 3)
        let frames = ThumbnailLayout.frames(for: sizes, position: .left, screenFrame: screen, visibleFrame: visible)
        #expect(frames.map(\.minY) == [100, 262, 424])
    }

    @Test func atMostFiveVisible() {
        let sizes = Array(repeating: CGSize(width: 100, height: 60), count: 8)
        #expect(ThumbnailLayout.frames(for: sizes, position: .left, screenFrame: screen, visibleFrame: visible).count == 5)
    }

    @Test func stackStopsAtTheTopOfTheVisibleFrame() {
        let small = CGRect(x: 0, y: 0, width: 1280, height: 600)
        let sizes = Array(repeating: CGSize(width: 209, height: 150), count: 5)
        let frames = ThumbnailLayout.frames(for: sizes, position: .left, screenFrame: small, visibleFrame: small)
        // 100, 262, 424 (ends at 574); a fourth would end at 736, above the 588 pt limit.
        #expect(frames.map(\.minY) == [100, 262, 424])
        #expect(frames.allSatisfy { $0.maxY <= small.maxY - ThumbnailLayout.margin })
    }

    @Test func secondaryScreenWithNegativeOriginAndTallDock() {
        let left = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let leftVisible = CGRect(x: -1920, y: -50, width: 1920, height: 1005)
        let frames = ThumbnailLayout.frames(for: [CGSize(width: 209, height: 150)], position: .left, screenFrame: left, visibleFrame: leftVisible)
        // 100 pt from the bottom is -100, inside the Dock: lifted to the visible frame.
        #expect(frames.first?.origin == CGPoint(x: -1880, y: -50 + ThumbnailLayout.margin))
    }
}

struct AutoCloseTimerTests {
    @Test func expiresAfterInterval() {
        let timer = AutoCloseTimer(interval: 30, now: 100)
        #expect(timer.deadline == 130)
        #expect(!timer.isExpired(at: 129.9))
        #expect(timer.isExpired(at: 130))
    }

    @Test func disabledNeverExpires() {
        let timer = AutoCloseTimer(interval: nil, now: 0)
        #expect(timer.deadline == nil)
        #expect(!timer.isExpired(at: 1_000_000))
    }

    @Test func hoverPausesAndRestartsWithFullInterval() {
        var timer = AutoCloseTimer(interval: 10, now: 0)
        timer.pause(.hover)
        #expect(timer.isPaused)
        #expect(!timer.isExpired(at: 50))
        timer.resume(.hover, now: 50)
        #expect(timer.deadline == 60)
    }

    @Test func overlappingReasonsResumeOnlyWhenAllEnd() {
        var timer = AutoCloseTimer(interval: 5, now: 0)
        timer.pause(.hover)
        timer.pause(.drag)
        timer.resume(.hover, now: 3)
        #expect(timer.deadline == nil)
        timer.resume(.drag, now: 4)
        #expect(timer.deadline == 9)
    }

    @Test func resumingAReasonThatWasNotActiveDoesNothing() {
        var timer = AutoCloseTimer(interval: 5, now: 0)
        timer.resume(.preview, now: 3)
        #expect(timer.deadline == 5)
    }

    @Test func disabledStaysDisabledAfterResume() {
        var timer = AutoCloseTimer(interval: nil, now: 0)
        timer.pause(.hover)
        timer.resume(.hover, now: 1)
        #expect(timer.deadline == nil)
    }
}

struct AutoCloseSettingsTests {
    @Test(arguments: QuickAccessSettings.autoCloseIntervals)
    func everyIntervalIsHonored(seconds: Int) {
        var settings = QuickAccessSettings()
        settings.autoCloseInterval = seconds
        #expect(settings.autoCloseSeconds == Double(seconds))
        let timer = AutoCloseTimer(interval: settings.autoCloseSeconds, now: 0)
        #expect(!timer.isExpired(at: Double(seconds) - 0.01))
        #expect(timer.isExpired(at: Double(seconds)))
    }

    @Test func toggleOffNeverCloses() {
        var settings = QuickAccessSettings()
        settings.autoClose = false
        #expect(settings.autoCloseSeconds == nil)
        #expect(!AutoCloseTimer(interval: settings.autoCloseSeconds, now: 0).isExpired(at: 1e9))
    }

    @Test func actionNamesSayWhatHappensToTheFile() {
        #expect(AutoCloseAction.close.displayName.contains("Delete"))
        #expect(AutoCloseAction.saveAndClose.displayName.contains("Save"))
    }
}

struct CaptureFileHoldsRemoveAllTests {
    @Test func removeAllDropsEveryHolder() {
        var holds = CaptureFileHolds()
        let url = URL(filePath: "/tmp/caps/x.mp4")
        holds.retain(url, by: .clipboard)
        holds.retain(url, by: .thumbnail(UUID()))
        holds.removeAll(for: url)
        #expect(!holds.isHeld(url))
        #expect(holds.url(heldBy: .clipboard) == nil)
    }
}
