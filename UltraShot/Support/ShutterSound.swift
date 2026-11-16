import AudioToolbox
import Foundation

/// The camera shutter played after a screenshot (`settings.general.playSounds`).
///
/// Played as a system sound: `AudioServicesPlaySystemSound` returns at once, while
/// `NSSound.play()` blocks the main thread while it starts audio output (about 45 ms per
/// capture, over 100 ms the first time).
@MainActor
enum ShutterSound {
    /// The system "Screen Capture" sound, the same one macOS's own screenshots use.
    private static let systemSoundURL = URL(
        filePath: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
    )
    private static let fallbackURL = URL(filePath: "/System/Library/Sounds/Tink.aiff")

    private static let soundID: SystemSoundID? = makeSoundID(systemSoundURL) ?? makeSoundID(fallbackURL)

    static func play() {
        guard let soundID else { return }
        AudioServicesPlaySystemSound(soundID)
    }

    /// Registers the sound file. It is not marked as an interface sound, so like the `NSSound`
    /// it replaces it plays whenever UltraShot's own "Play sounds" setting is on, whatever the
    /// system "Play user interface sound effects" setting says.
    private static func makeSoundID(_ url: URL) -> SystemSoundID? {
        var soundID: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(url as CFURL, &soundID) == kAudioServicesNoError else { return nil }
        var isUISound: UInt32 = 0
        AudioServicesSetProperty(
            kAudioServicesPropertyIsUISound,
            UInt32(MemoryLayout<SystemSoundID>.size), &soundID,
            UInt32(MemoryLayout<UInt32>.size), &isUISound
        )
        return soundID
    }
}
