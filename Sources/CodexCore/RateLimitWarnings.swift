public enum RateLimitWarningLabels {
    public static func durationLabel(windowMinutes: Int64) -> String {
        let minutesPerHour: Int64 = 60
        let minutesPerDay: Int64 = 24 * minutesPerHour
        let minutesPerWeek: Int64 = 7 * minutesPerDay
        let minutesPerMonth: Int64 = 30 * minutesPerDay
        let roundingBiasMinutes: Int64 = 3

        let minutes = max(windowMinutes, 0)

        if minutes <= minutesPerDay + roundingBiasMinutes {
            let adjusted = minutes + roundingBiasMinutes
            let hours = max(Int64(1), adjusted / minutesPerHour)
            return "\(hours)h"
        }
        if minutes <= minutesPerWeek + roundingBiasMinutes {
            return "weekly"
        }
        if minutes <= minutesPerMonth + roundingBiasMinutes {
            return "monthly"
        }
        return "annual"
    }
}

public struct RateLimitWarningState: Equatable, Sendable {
    private var secondaryIndex: Int
    private var primaryIndex: Int

    public init() {
        secondaryIndex = 0
        primaryIndex = 0
    }

    public mutating func takeWarnings(
        secondaryUsedPercent: Double?,
        secondaryWindowMinutes: Int64?,
        primaryUsedPercent: Double?,
        primaryWindowMinutes: Int64?
    ) -> [String] {
        if secondaryUsedPercent == 100.0 || primaryUsedPercent == 100.0 {
            return []
        }

        var warnings: [String] = []

        if let secondaryUsedPercent,
           let warning = Self.takeWarning(
               usedPercent: secondaryUsedPercent,
               windowMinutes: secondaryWindowMinutes,
               fallbackLabel: "weekly",
               index: &secondaryIndex
           ) {
            warnings.append(warning)
        }

        if let primaryUsedPercent,
           let warning = Self.takeWarning(
               usedPercent: primaryUsedPercent,
               windowMinutes: primaryWindowMinutes,
               fallbackLabel: "5h",
               index: &primaryIndex
           ) {
            warnings.append(warning)
        }

        return warnings
    }

    private static func takeWarning(
        usedPercent: Double,
        windowMinutes: Int64?,
        fallbackLabel: String,
        index: inout Int
    ) -> String? {
        var highestThreshold: Double?
        while index < Self.warningThresholds.count && usedPercent >= Self.warningThresholds[index] {
            highestThreshold = Self.warningThresholds[index]
            index += 1
        }

        guard let highestThreshold else {
            return nil
        }

        let limitLabel = windowMinutes.map(RateLimitWarningLabels.durationLabel(windowMinutes:)) ?? fallbackLabel
        let remainingPercent = Int((100.0 - highestThreshold).rounded(.towardZero))
        return "Heads up, you have less than \(remainingPercent)% of your \(limitLabel) limit left. Run /status for a breakdown."
    }

    private static let warningThresholds: [Double] = [75.0, 90.0, 95.0]
}
