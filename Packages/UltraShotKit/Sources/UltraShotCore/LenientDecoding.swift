import Foundation

extension KeyedDecodingContainer {
    /// Decodes `key` if present and valid; returns `nil` when the key is missing, `null`,
    /// of the wrong type or (for enums) an unknown raw value.
    ///
    /// Settings decoding uses this per key so one bad value falls back to that key's
    /// default instead of failing the whole document.
    func lenient<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        // `try?` flattens the `T??` from `decodeIfPresent` into `T?`.
        try? decodeIfPresent(type, forKey: key)
    }
}

/// Numeric normalization shared by decoding and property setters.
enum Normalize {
    /// `value` clamped to `range`.
    static func clamp<T: Comparable>(_ value: T, to range: ClosedRange<T>) -> T {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// `value` clamped to `range`; NaN becomes `fallback`.
    static func clamp(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isNaN ? fallback : clamp(value, to: range)
    }

    /// The element of `options` closest to `value`; ties go to the earlier option.
    /// Returns `value` unchanged if `options` is empty.
    static func snap(_ value: Int, to options: [Int]) -> Int {
        guard let lowest = options.min(), let highest = options.max() else { return value }
        // Clamp first so extreme values (e.g. Int.min from a hand-edited file) cannot overflow.
        let bounded = clamp(value, to: lowest...highest)
        return options.min { abs($0 - bounded) < abs($1 - bounded) } ?? value
    }
}
