import AppKit
import AVFoundation
import Foundation

/// Helpers for the live recording tests. They inspect file metadata only; no frame is decoded.
enum LiveTestSupport {
    static let ffprobePath = "/opt/homebrew/bin/ffprobe"

    static func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("RecordingKitTests-\(UUID().uuidString)")
            .appendingPathComponent("\(name).mp4")
    }

    static func removeRecording(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    struct AssetInfo {
        let duration: Double
        let videoTracks: Int
        let audioTracks: Int
        let videoSize: CGSize
        let videoTrackDuration: Double
    }

    static func assetInfo(_ url: URL) async throws -> AssetInfo {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let video = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        var size = CGSize.zero
        var videoDuration = 0.0
        if let first = video.first {
            size = try await first.load(.naturalSize)
            videoDuration = try await first.load(.timeRange).duration.seconds
        }
        return AssetInfo(duration: duration, videoTracks: video.count, audioTracks: audio.count, videoSize: size, videoTrackDuration: videoDuration)
    }

    struct ProbeStream {
        let codecType: String
        let duration: Double?
        let frames: Int?
    }

    struct ProbeInfo {
        let formatDuration: Double
        let streams: [ProbeStream]
        var video: ProbeStream? { streams.first { $0.codecType == "video" } }
    }

    /// Container and stream metadata from ffprobe, or nil when ffprobe is not installed.
    static func probe(_ url: URL) throws -> ProbeInfo? {
        guard FileManager.default.isExecutableFile(atPath: ffprobePath) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobePath)
        process.arguments = [
            "-v", "error", "-count_packets",
            "-show_entries", "format=duration:stream=codec_type,duration,nb_read_packets",
            "-of", "json", url.path
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let format = json["format"] as? [String: Any],
              let duration = (format["duration"] as? String).flatMap(Double.init) else { return nil }
        let streams = (json["streams"] as? [[String: Any]] ?? []).map { stream in
            ProbeStream(
                codecType: stream["codec_type"] as? String ?? "",
                duration: (stream["duration"] as? String).flatMap(Double.init),
                frames: (stream["nb_read_packets"] as? String).flatMap(Int.init)
            )
        }
        return ProbeInfo(formatDuration: duration, streams: streams)
    }
}

/// An opaque, solid, borderless window of our own above everything, used as a static area to
/// record. Its rect is in top-left display points of the main display.
@MainActor
final class StaticTestWindow {
    let window: NSWindow
    let rect: CGRect

    init(rect: CGRect) {
        _ = NSApplication.shared
        self.rect = rect
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        window = NSWindow(
            contentRect: NSRect(x: rect.minX, y: screenHeight - rect.maxY, width: rect.width, height: rect.height),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = .screenSaver
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.backgroundColor = NSColor(srgbRed: 0.1, green: 0.6, blue: 0.3, alpha: 1)
        window.orderFrontRegardless()
    }

    var windowID: CGWindowID { CGWindowID(window.windowNumber) }

    func close() { window.orderOut(nil) }
}
