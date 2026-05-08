import Foundation

public enum StringByteBoundary {
    /// Port of codex-utils-string take_bytes_at_char_boundary.
    public static func takeBytesAtUnicodeScalarBoundary(_ value: String, maxBytes: Int) -> String {
        guard maxBytes >= 0 else { return "" }
        guard value.utf8.count > maxBytes else { return value }

        var used = 0
        var result = String()
        for scalar in value.unicodeScalars {
            let width = scalar.utf8.count
            guard used + width <= maxBytes else { break }
            result.unicodeScalars.append(scalar)
            used += width
        }
        return result
    }

    /// Port of codex-utils-string take_last_bytes_at_char_boundary.
    public static func takeLastBytesAtUnicodeScalarBoundary(_ value: String, maxBytes: Int) -> String {
        guard maxBytes >= 0 else { return "" }
        guard value.utf8.count > maxBytes else { return value }

        var used = 0
        var selected: [UnicodeScalar] = []
        for scalar in value.unicodeScalars.reversed() {
            let width = scalar.utf8.count
            guard used + width <= maxBytes else { break }
            selected.append(scalar)
            used += width
        }

        var result = String()
        for scalar in selected.reversed() {
            result.unicodeScalars.append(scalar)
        }
        return result
    }
}
