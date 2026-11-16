import AppKit

/// The camera shutter played after a screenshot (`settings.general.playSounds`).
@MainActor
enum ShutterSound {
    /// The system "Screen Capture" sound, the same one macOS's own screenshots use.
    private static let systemSoundURL = URL(
        filePath: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
    )

    private static let sound: NSSound? = NSSound(contentsOf: systemSoundURL, byReference: true)
        ?? NSSound(named: NSSound.Name("Tink"))

    static func play() {
        guard let sound else { return }
        sound.stop()
        sound.play()
    }
}
