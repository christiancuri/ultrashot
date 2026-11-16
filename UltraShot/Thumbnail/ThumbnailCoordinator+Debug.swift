import AppKit
import AVFoundation
import UltraShotCore

extension ThumbnailCoordinator {
    /// Shows three sample thumbnails without auto-close: a short synthetic recording, a
    /// full-screen synthetic screenshot and a cropped one (newest, at the bottom).
    func showSamples() async {
        guard let model, let screen = NSScreen.screens.first else { return }
        let scale = screen.backingScaleFactor
        let fullImage = DebugLaunchHooks.fakeSnapshotImage(size: screen.frame.size, scale: scale)
        let settings = model.settings.screenshots
        do {
            let movieURL = try model.captureStore.makeTemporaryURL(kind: .recording, ext: "mp4")
            try await Self.writeSampleMovie(from: fullImage, to: movieURL)
            show(CapturedItem(kind: .recording, fileURL: movieURL, pixelWidth: 640, pixelHeight: 400, duration: 3), autoClose: false)
        } catch {
            Log.thumbnail.error("sample recording failed: \(error.localizedDescription, privacy: .public)")
        }
        do {
            let full = try await CaptureOutput.write(fullImage, scale: scale, settings: settings, store: model.captureStore)
            show(CapturedItem(screenshot: full), autoClose: false)
            let cropRect = CGRect(x: 120 * scale, y: 160 * scale, width: 520 * scale, height: 300 * scale)
            if let crop = fullImage.cropping(to: cropRect) {
                let cropped = try await CaptureOutput.write(crop, scale: scale, settings: settings, store: model.captureStore)
                show(CapturedItem(screenshot: cropped), autoClose: false)
            }
        } catch {
            Log.thumbnail.error("sample screenshot failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// A 3-second, 640×400 H.264 movie of `image` with a moving white square.
    private nonisolated static func writeSampleMovie(from image: CGImage, to url: URL) async throws {
        let width = 640, height = 400, frames = 30
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        for frame in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool,
                  CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else {
                throw CocoaError(.fileWriteUnknown)
            }
            CVPixelBufferLockBaseAddress(buffer, [])
            let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            )
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            context?.setFillColor(CGColor(gray: 1, alpha: 1))
            context?.fill(CGRect(x: 20 + frame * 18, y: 30, width: 48, height: 48))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 10)) else {
                throw writer.error ?? CocoaError(.fileWriteUnknown)
            }
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(frames), timescale: 10))
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }
}
