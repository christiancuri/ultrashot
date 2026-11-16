import Foundation

/// General preferences.
public struct GeneralSettings: Codable, Sendable, Equatable, Hashable {
    public var playSounds = true
    /// Hide desktop icons while capturing.
    public var hideDesktopIcons = true
    /// Where saved captures go, stored abbreviated with `~` (e.g. `~/Desktop`).
    public var exportFolderPath: String = "~/Desktop"
    public var afterCapture = AfterCaptureSettings()

    public init() {}

    /// ``exportFolderPath`` with `~` expanded. Setting it stores the path abbreviated with `~`.
    public var exportFolderURL: URL {
        get {
            URL(filePath: (exportFolderPath as NSString).expandingTildeInPath, directoryHint: .isDirectory)
        }
        set {
            let path = (newValue.standardizedFileURL.path(percentEncoded: false) as NSString).standardizingPath
            exportFolderPath = (path as NSString).abbreviatingWithTildeInPath
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = GeneralSettings()
        playSounds = container.lenient(Bool.self, forKey: .playSounds) ?? defaults.playSounds
        hideDesktopIcons = container.lenient(Bool.self, forKey: .hideDesktopIcons) ?? defaults.hideDesktopIcons
        exportFolderPath = container.lenient(String.self, forKey: .exportFolderPath)
            .flatMap { $0.isEmpty ? nil : $0 } ?? defaults.exportFolderPath
        afterCapture = container.lenient(AfterCaptureSettings.self, forKey: .afterCapture) ?? defaults.afterCapture
    }
}

/// What happens right after a capture finishes, per capture kind.
public struct AfterCaptureSettings: Codable, Sendable, Equatable, Hashable {
    public var screenshot = AfterCaptureActions(showThumbnail: true, copyToClipboard: true, save: false)
    public var recording = AfterCaptureActions(showThumbnail: true, copyToClipboard: false, save: false)

    public init() {}

    /// The actions configured for `kind`.
    public func actions(for kind: CapturedItem.Kind) -> AfterCaptureActions {
        switch kind {
        case .screenshot: screenshot
        case .recording: recording
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AfterCaptureSettings()
        // Missing flags inside each block fall back to that kind's defaults, not to `false`.
        screenshot = AfterCaptureActions.lenient(in: container, forKey: .screenshot, defaults: defaults.screenshot)
        recording = AfterCaptureActions.lenient(in: container, forKey: .recording, defaults: defaults.recording)
    }
}

/// The after-capture toggles for one capture kind.
public struct AfterCaptureActions: Codable, Sendable, Equatable, Hashable {
    /// Show the Quick Access overlay.
    public var showThumbnail: Bool
    public var copyToClipboard: Bool
    /// Save to the export folder immediately.
    public var save: Bool

    // Spelled out because the private decoding init below names the type in its signature.
    private enum CodingKeys: String, CodingKey {
        case showThumbnail
        case copyToClipboard
        case save
    }

    public init(showThumbnail: Bool, copyToClipboard: Bool, save: Bool) {
        self.showThumbnail = showThumbnail
        self.copyToClipboard = copyToClipboard
        self.save = save
    }

    /// Standalone decoding: missing or invalid flags become `false`. Inside
    /// ``AfterCaptureSettings`` the per-kind defaults are used instead.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(container: container, defaults: AfterCaptureActions(showThumbnail: false, copyToClipboard: false, save: false))
    }

    private init(container: KeyedDecodingContainer<CodingKeys>, defaults: AfterCaptureActions) {
        showThumbnail = container.lenient(Bool.self, forKey: .showThumbnail) ?? defaults.showThumbnail
        copyToClipboard = container.lenient(Bool.self, forKey: .copyToClipboard) ?? defaults.copyToClipboard
        save = container.lenient(Bool.self, forKey: .save) ?? defaults.save
    }

    /// Decodes the object at `key`, filling missing or invalid flags from `defaults`;
    /// returns `defaults` if the key is missing or not an object.
    static func lenient<K: CodingKey>(
        in container: KeyedDecodingContainer<K>,
        forKey key: K,
        defaults: AfterCaptureActions
    ) -> AfterCaptureActions {
        guard let nested = try? container.nestedContainer(keyedBy: CodingKeys.self, forKey: key) else {
            return defaults
        }
        return AfterCaptureActions(container: nested, defaults: defaults)
    }
}

/// Quick Access overlay (the floating thumbnail shown after a capture).
public struct QuickAccessSettings: Codable, Sendable, Equatable, Hashable {
    /// Supported values of ``overlaySize``.
    public static let overlaySizeRange = 1...5
    /// Supported values of ``autoCloseInterval``, in seconds.
    public static let autoCloseIntervals = [5, 10, 15, 30, 60, 120, 300, 600]

    public var position: QuickAccessPosition = .left
    /// Follow the screen with keyboard focus instead of the main screen.
    public var moveToActiveScreen = true
    /// Thumbnail size stop; clamped to ``overlaySizeRange`` when set or decoded.
    public var overlaySize: Int = 2 {
        didSet { overlaySize = Normalize.clamp(overlaySize, to: Self.overlaySizeRange) }
    }
    public var autoClose = true
    public var autoCloseAction: AutoCloseAction = .close
    /// Seconds before auto-close; snapped to the nearest of ``autoCloseIntervals`` when set or decoded.
    public var autoCloseInterval: Int = 30 {
        didSet { autoCloseInterval = Normalize.snap(autoCloseInterval, to: Self.autoCloseIntervals) }
    }
    /// Dismiss the overlay after its capture is dragged out.
    public var closeAfterDragging = true

    public init() {}

    /// Human-readable interval: `5 seconds`, `1 minute`, `2 minutes`, `10 minutes`.
    public static func intervalLabel(_ seconds: Int) -> String {
        if seconds >= 60, seconds.isMultiple(of: 60) {
            let minutes = seconds / 60
            return minutes == 1 ? "1 minute" : "\(minutes) minutes"
        }
        return seconds == 1 ? "1 second" : "\(seconds) seconds"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = QuickAccessSettings()
        position = container.lenient(QuickAccessPosition.self, forKey: .position) ?? defaults.position
        moveToActiveScreen = container.lenient(Bool.self, forKey: .moveToActiveScreen) ?? defaults.moveToActiveScreen
        overlaySize = Normalize.clamp(
            container.lenient(Int.self, forKey: .overlaySize) ?? defaults.overlaySize,
            to: Self.overlaySizeRange
        )
        autoClose = container.lenient(Bool.self, forKey: .autoClose) ?? defaults.autoClose
        autoCloseAction = container.lenient(AutoCloseAction.self, forKey: .autoCloseAction) ?? defaults.autoCloseAction
        autoCloseInterval = Normalize.snap(
            container.lenient(Int.self, forKey: .autoCloseInterval) ?? defaults.autoCloseInterval,
            to: Self.autoCloseIntervals
        )
        closeAfterDragging = container.lenient(Bool.self, forKey: .closeAfterDragging) ?? defaults.closeAfterDragging
    }
}

/// Still screenshot output.
public struct ScreenshotSettings: Codable, Sendable, Equatable, Hashable {
    /// Supported values of ``jpegQuality``.
    public static let jpegQualityRange = 0.0...1.0

    public var format: ImageFormat = .png
    /// JPEG compression quality; clamped to ``jpegQualityRange`` when set or decoded (NaN becomes the default).
    public var jpegQuality: Double = 0.9 {
        didSet { jpegQuality = Normalize.clamp(jpegQuality, to: Self.jpegQualityRange, fallback: 0.9) }
    }
    public var convertToSRGB = false
    /// Save Retina captures at 1x.
    public var downscaleRetina = false
    /// Include the shadow in window captures.
    public var windowShadow = true
    public var showCursor = false

    public init() {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ScreenshotSettings()
        format = container.lenient(ImageFormat.self, forKey: .format) ?? defaults.format
        jpegQuality = Normalize.clamp(
            container.lenient(Double.self, forKey: .jpegQuality) ?? defaults.jpegQuality,
            to: Self.jpegQualityRange,
            fallback: defaults.jpegQuality
        )
        convertToSRGB = container.lenient(Bool.self, forKey: .convertToSRGB) ?? defaults.convertToSRGB
        downscaleRetina = container.lenient(Bool.self, forKey: .downscaleRetina) ?? defaults.downscaleRetina
        windowShadow = container.lenient(Bool.self, forKey: .windowShadow) ?? defaults.windowShadow
        showCursor = container.lenient(Bool.self, forKey: .showCursor) ?? defaults.showCursor
    }
}

/// Screen recording output.
public struct RecordingSettings: Codable, Sendable, Equatable, Hashable {
    /// Supported values of ``frameRate``.
    public static let frameRates = [24, 30, 60]

    /// Frames per second; snapped to the nearest of ``frameRates`` when set or decoded.
    public var frameRate: Int = 30 {
        didSet { frameRate = Normalize.snap(frameRate, to: Self.frameRates) }
    }
    public var showCursor = true
    public var systemAudio = true
    public var microphone = false
    /// Selected microphone (`AVCaptureDevice.uniqueID`); `nil` means the system default.
    public var microphoneDeviceID: String?
    /// Record Retina displays at 1x.
    public var downscaleRetina = false
    /// Pre-select the previous recording area (see ``AppState/lastRecordingArea``).
    public var rememberLastArea = true

    // Not synthesized because both Codable requirements are implemented by hand.
    private enum CodingKeys: String, CodingKey {
        case frameRate
        case showCursor
        case systemAudio
        case microphone
        case microphoneDeviceID
        case downscaleRetina
        case rememberLastArea
    }

    public init() {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = RecordingSettings()
        frameRate = Normalize.snap(container.lenient(Int.self, forKey: .frameRate) ?? defaults.frameRate, to: Self.frameRates)
        showCursor = container.lenient(Bool.self, forKey: .showCursor) ?? defaults.showCursor
        systemAudio = container.lenient(Bool.self, forKey: .systemAudio) ?? defaults.systemAudio
        microphone = container.lenient(Bool.self, forKey: .microphone) ?? defaults.microphone
        microphoneDeviceID = container.lenient(String.self, forKey: .microphoneDeviceID) ?? defaults.microphoneDeviceID
        downscaleRetina = container.lenient(Bool.self, forKey: .downscaleRetina) ?? defaults.downscaleRetina
        rememberLastArea = container.lenient(Bool.self, forKey: .rememberLastArea) ?? defaults.rememberLastArea
    }

    /// Writes every key, including `microphoneDeviceID` as `null` when unset.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(frameRate, forKey: .frameRate)
        try container.encode(showCursor, forKey: .showCursor)
        try container.encode(systemAudio, forKey: .systemAudio)
        try container.encode(microphone, forKey: .microphone)
        try container.encode(microphoneDeviceID, forKey: .microphoneDeviceID)
        try container.encode(downscaleRetina, forKey: .downscaleRetina)
        try container.encode(rememberLastArea, forKey: .rememberLastArea)
    }
}

/// Advanced preferences.
public struct AdvancedSettings: Codable, Sendable, Equatable, Hashable {
    /// File name template for saved captures; see ``FileNaming`` for the tokens.
    public var fileNameTemplate: String = FileNaming.defaultTemplate

    public init() {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fileNameTemplate = container.lenient(String.self, forKey: .fileNameTemplate) ?? FileNaming.defaultTemplate
    }
}
