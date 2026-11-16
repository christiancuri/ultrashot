import CoreGraphics

/// Sendable sRGB color with components in 0...1.
public struct RGBAColor: Sendable, Hashable, Codable {
    public var red: CGFloat
    public var green: CGFloat
    public var blue: CGFloat
    public var alpha: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Creates a color from a 0xRRGGBB value.
    public init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    /// The color in the sRGB color space.
    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    public func withAlpha(_ alpha: CGFloat) -> RGBAColor {
        RGBAColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// Relative luminance (sRGB coefficients, gamma ignored), used to pick a legible
    /// foreground on top of this color.
    public var luminance: CGFloat {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    public static let white = RGBAColor(red: 1, green: 1, blue: 1)
    public static let black = RGBAColor(red: 0, green: 0, blue: 0)
}

/// The annotation palette shown in the color picker.
public enum Palette {
    public static let red = RGBAColor(hex: 0xFF2D2D)
    public static let orange = RGBAColor(hex: 0xFF8A00)
    public static let yellow = RGBAColor(hex: 0xFFD60A)
    public static let green = RGBAColor(hex: 0x30C24B)
    public static let blue = RGBAColor(hex: 0x0A84FF)
    public static let purple = RGBAColor(hex: 0xA550DC)
    public static let black = RGBAColor(hex: 0x1C1C1E)
    public static let white = RGBAColor(hex: 0xFFFFFF)

    /// Red, like Lightshot.
    public static let defaultColor = red

    /// Picker order.
    public static let colors: [RGBAColor] = [red, orange, yellow, green, blue, purple, black, white]
}
