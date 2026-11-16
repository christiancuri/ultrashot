import CoreGraphics

/// Geometry of the Quick Access thumbnails: size per overlay-size stop and the stacking of
/// several thumbnails along the left or right edge (newest at the bottom).
///
/// Measured from CleanShot X: at the default stop the card is about 209 × 150 pt, 40 pt from
/// the screen edge and 100 pt from the bottom.
public enum ThumbnailLayout {
    /// Largest card size at stop 2 (the default).
    public static let referenceSize = CGSize(width: 209, height: 150)
    /// Scale of the largest card per stop 1...5 relative to ``referenceSize``.
    public static let stopScales: [CGFloat] = [0.8, 1.0, 1.25, 1.55, 1.9]
    /// Smallest card side so the hover buttons always fit.
    public static let minimumSize = CGSize(width: 140, height: 96)
    public static let edgeInset: CGFloat = 40
    public static let bottomInset: CGFloat = 100
    /// Gap between stacked cards.
    public static let spacing: CGFloat = 12
    /// Minimum distance to the visible frame (menu bar, Dock).
    public static let margin: CGFloat = 12
    public static let maxVisible = 5

    /// The largest card size for `stop` (clamped to 1...5).
    public static func maxSize(forStop stop: Int) -> CGSize {
        let index = min(max(stop, 1), stopScales.count) - 1
        let scale = stopScales[index]
        return CGSize(width: (referenceSize.width * scale).rounded(), height: (referenceSize.height * scale).rounded())
    }

    /// The card size for an image: the image aspect-fit into ``maxSize(forStop:)``, each side at
    /// least ``minimumSize`` (very wide or tall images are then cropped by the card).
    public static func cardSize(imageSize: CGSize, stop: Int) -> CGSize {
        let box = maxSize(forStop: stop)
        guard imageSize.width > 0, imageSize.height > 0 else { return box }
        let fit = min(box.width / imageSize.width, box.height / imageSize.height)
        let width = min(box.width, max(minimumSize.width, (imageSize.width * fit).rounded()))
        let height = min(box.height, max(minimumSize.height, (imageSize.height * fit).rounded()))
        return CGSize(width: width, height: height)
    }

    /// Frames (AppKit global points) for cards of `sizes`, newest first. The newest sits at the
    /// bottom; older ones stack upward. At most ``maxVisible`` frames are returned, fewer when
    /// the stack would leave the visible frame.
    public static func frames(
        for sizes: [CGSize],
        position: QuickAccessPosition,
        screenFrame: CGRect,
        visibleFrame: CGRect
    ) -> [CGRect] {
        var frames: [CGRect] = []
        var y = max(screenFrame.minY + bottomInset, visibleFrame.minY + margin)
        for size in sizes.prefix(maxVisible) {
            if !frames.isEmpty, y + size.height > visibleFrame.maxY - margin { break }
            let x: CGFloat = switch position {
            case .left: max(screenFrame.minX + edgeInset, visibleFrame.minX + margin)
            case .right: min(screenFrame.maxX - edgeInset, visibleFrame.maxX - margin) - size.width
            }
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            y += size.height + spacing
        }
        return frames
    }
}

extension QuickAccessSettings {
    /// Seconds before a thumbnail closes itself, or `nil` when "Close automatically" is off.
    public var autoCloseSeconds: Double? {
        autoClose ? Double(autoCloseInterval) : nil
    }
}

/// The auto-close countdown of one thumbnail. Pure state: the caller supplies `now` and
/// schedules a wake-up at ``deadline``.
///
/// The countdown pauses while any ``PauseReason`` is active (hover, drag, Quick Look, ...) and
/// restarts from the full interval when the last one ends (CleanShot behavior).
public struct AutoCloseTimer: Equatable, Sendable {
    public enum PauseReason: Hashable, Sendable {
        case hover
        case drag
        case preview
        case annotate
        case menu
    }

    /// Seconds before auto-close; `nil` disables auto-close.
    public let interval: Double?
    /// When the thumbnail should close; `nil` while paused or disabled.
    public private(set) var deadline: Double?
    public private(set) var pauseReasons: Set<PauseReason> = []

    /// Starts the countdown at `now` (seconds on any monotonic clock).
    public init(interval: Double?, now: Double) {
        self.interval = interval
        deadline = interval.map { now + $0 }
    }

    public var isPaused: Bool { !pauseReasons.isEmpty }

    public mutating func pause(_ reason: PauseReason) {
        pauseReasons.insert(reason)
        deadline = nil
    }

    /// Ends `reason`; when nothing else pauses the timer it restarts with the full interval.
    public mutating func resume(_ reason: PauseReason, now: Double) {
        guard pauseReasons.remove(reason) != nil else { return }
        if pauseReasons.isEmpty, let interval {
            deadline = now + interval
        }
    }

    public func isExpired(at now: Double) -> Bool {
        guard let deadline else { return false }
        return now >= deadline
    }
}
