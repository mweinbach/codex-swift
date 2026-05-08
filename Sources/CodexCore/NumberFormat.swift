import Foundation

public enum NumberFormat {
    public static func formatWithSeparators(_ value: Int64, locale: Locale = .current) -> String {
        integerFormatter(locale: locale).string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Port of codex-protocol format_si_suffix.
    public static func formatSISuffix(_ value: Int64, locale: Locale = .current) -> String {
        formatSISuffix(value, locale: locale, separatorLocale: locale)
    }

    static func formatSISuffix(
        _ value: Int64,
        locale: Locale,
        separatorLocale: Locale
    ) -> String {
        let nonNegative = max(value, 0)
        if nonNegative < 1_000 {
            return formatWithSeparators(nonNegative, locale: locale)
        }

        let units: [(scale: Int64, suffix: String)] = [
            (1_000, "K"),
            (1_000_000, "M"),
            (1_000_000_000, "G")
        ]

        let floating = Double(nonNegative)
        for unit in units {
            if (100.0 * floating / Double(unit.scale)).rounded() < 1_000.0 {
                return formatScaled(nonNegative, scale: unit.scale, fractionDigits: 2, locale: locale) + unit.suffix
            }
            if (10.0 * floating / Double(unit.scale)).rounded() < 1_000.0 {
                return formatScaled(nonNegative, scale: unit.scale, fractionDigits: 1, locale: locale) + unit.suffix
            }
            if (floating / Double(unit.scale)).rounded() < 1_000.0 {
                return formatScaled(nonNegative, scale: unit.scale, fractionDigits: 0, locale: locale) + unit.suffix
            }
        }

        let wholeGigabytes = Int64((floating / 1_000_000_000.0).rounded())
        return formatWithSeparators(wholeGigabytes, locale: separatorLocale) + "G"
    }

    private static func formatScaled(
        _ value: Int64,
        scale: Int64,
        fractionDigits: Int,
        locale: Locale
    ) -> String {
        let factor = pow(10.0, Double(fractionDigits))
        let scaled = (Double(value) / Double(scale) * factor).rounded() / factor
        let formatter = decimalFormatter(locale: locale, fractionDigits: fractionDigits, usesGroupingSeparator: true)
        return formatter.string(from: NSNumber(value: scaled)) ?? "\(scaled)"
    }

    private static func integerFormatter(locale: Locale) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        formatter.usesGroupingSeparator = true
        return formatter
    }

    private static func decimalFormatter(
        locale: Locale,
        fractionDigits: Int,
        usesGroupingSeparator: Bool
    ) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        formatter.usesGroupingSeparator = usesGroupingSeparator
        return formatter
    }
}
