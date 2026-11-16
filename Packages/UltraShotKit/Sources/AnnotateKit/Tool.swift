/// Annotation tools, in toolbar order.
public enum Tool: String, CaseIterable, Sendable, Codable {
    case pen
    case line
    case arrow
    case rectangle
    case ellipse
    case marker
    case text
    case blur
    case counter

    /// Single-key shortcut (lowercase; match case-insensitively, without modifiers).
    public var shortcutKey: Character {
        switch self {
        case .pen: "p"
        case .line: "l"
        case .arrow: "a"
        case .rectangle: "r"
        case .ellipse: "o"
        case .marker: "m"
        case .text: "t"
        case .blur: "b"
        case .counter: "n"
        }
    }

    /// SF Symbol name for the toolbar button.
    public var symbolName: String {
        switch self {
        case .pen: "pencil"
        case .line: "line.diagonal"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .marker: "highlighter"
        case .text: "textformat"
        case .blur: "checkerboard.rectangle"
        case .counter: "1.circle"
        }
    }

    /// Tooltip / accessibility label (English).
    public var title: String {
        switch self {
        case .pen: "Pen"
        case .line: "Line"
        case .arrow: "Arrow"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .marker: "Marker"
        case .text: "Text"
        case .blur: "Pixelate"
        case .counter: "Counter"
        }
    }

    /// The tool whose shortcut matches `key` (case-insensitive), if any.
    public init?(shortcutKey key: Character) {
        let lower = Character(key.lowercased())
        guard let tool = Tool.allCases.first(where: { $0.shortcutKey == lower }) else { return nil }
        self = tool
    }

    /// Text and counters are created by a click; everything else by a drag.
    public var createsByClick: Bool {
        self == .text || self == .counter
    }
}
