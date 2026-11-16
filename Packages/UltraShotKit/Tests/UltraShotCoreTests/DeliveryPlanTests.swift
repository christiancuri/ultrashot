import Foundation
import Testing
@testable import UltraShotCore

struct DeliveryPlanTests {
    private static let flags: [(Bool, Bool, Bool)] = [false, true].flatMap { thumb in
        [false, true].flatMap { copy in [false, true].map { save in (thumb, copy, save) } }
    }

    @Test(arguments: CapturedItem.Kind.allCases)
    func decisionTable(kind: CapturedItem.Kind) {
        for (thumb, copy, save) in Self.flags {
            let plan = DeliveryPlan.make(kind: kind, actions: AfterCaptureActions(showThumbnail: thumb, copyToClipboard: copy, save: save))
            let expectedClipboard: DeliveryPlan.ClipboardContent = !copy ? .none : (kind == .screenshot ? .imageData : .fileReference)
            #expect(plan.clipboard == expectedClipboard)
            #expect(plan.save == save)
            #expect(plan.showThumbnail == thumb)
            let kept = save || thumb || expectedClipboard == .fileReference
            #expect(plan.deletesTemporaryFile == !kept, "kind \(kind) thumb \(thumb) copy \(copy) save \(save)")
        }
    }

    @Test func defaultsKeepScreenshotForThumbnailOnly() {
        let settings = AfterCaptureSettings()
        let shot = DeliveryPlan.make(kind: .screenshot, actions: settings.screenshot)
        #expect(shot == DeliveryPlan(clipboard: .imageData, save: false, showThumbnail: true))
        let recording = DeliveryPlan.make(kind: .recording, actions: settings.recording)
        #expect(recording == DeliveryPlan(clipboard: .none, save: false, showThumbnail: true))
    }

    @Test func copyOnlyScreenshotDeletesFileRightAway() {
        let plan = DeliveryPlan.make(kind: .screenshot, actions: AfterCaptureActions(showThumbnail: false, copyToClipboard: true, save: false))
        #expect(plan.deletesTemporaryFile)
    }

    @Test func copyOnlyRecordingKeepsFileForClipboard() {
        let plan = DeliveryPlan.make(kind: .recording, actions: AfterCaptureActions(showThumbnail: false, copyToClipboard: true, save: false))
        #expect(!plan.deletesTemporaryFile)
    }
}

struct CaptureFileHoldsTests {
    private let fileA = URL(filePath: "/tmp/caps/a.png")
    private let fileB = URL(filePath: "/tmp/caps/b.mp4")

    @Test func lastReleaseReportsFree() {
        var holds = CaptureFileHolds()
        let thumb = CaptureFileHolds.Holder.thumbnail(UUID())
        holds.retain(fileB, by: thumb)
        holds.retain(fileB, by: .clipboard)
        let freedByThumbnail = holds.release(fileB, by: thumb)
        #expect(!freedByThumbnail)
        #expect(holds.isHeld(fileB))
        let freedByClipboard = holds.release(fileB, by: .clipboard)
        #expect(freedByClipboard)
        #expect(!holds.isHeld(fileB))
    }

    @Test func releasingUnknownFileIsFree() {
        var holds = CaptureFileHolds()
        let freed = holds.release(fileA, by: .clipboard)
        #expect(freed)
    }

    @Test func clipboardHolderLookupAndMove() {
        var holds = CaptureFileHolds()
        holds.retain(fileB, by: .clipboard)
        #expect(holds.url(heldBy: .clipboard) == fileB)
        let saved = URL(filePath: "/Users/x/Desktop/Recording.mp4")
        holds.move(fileB, to: saved)
        #expect(holds.url(heldBy: .clipboard) == saved)
        #expect(!holds.isHeld(fileB))
    }

    @Test func pathsAreStandardized() {
        var holds = CaptureFileHolds()
        holds.retain(URL(filePath: "/tmp/caps/./a.png"), by: .clipboard)
        #expect(holds.isHeld(fileA))
    }

    @Test func temporaryMeansInsideTheStoreRoot() {
        let store = CaptureStore(root: URL(filePath: "/tmp/caps", directoryHint: .isDirectory))
        #expect(store.isTemporary(fileA))
        #expect(!store.isTemporary(URL(filePath: "/tmp/capsule/a.png")))
        #expect(!store.isTemporary(URL(filePath: "/Users/x/Desktop/a.png")))
        #expect(!store.isTemporary(URL(filePath: "/tmp/caps")))
    }
}
