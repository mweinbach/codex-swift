import Foundation

public enum ElapsedFormat {
    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    public static func formatElapsed(since startTime: Date, now: Date = Date()) -> String {
        formatDuration(now.timeIntervalSince(startTime))
    }

    public static func formatDuration(_ duration: TimeInterval) -> String {
        let milliseconds = Int64((duration * 1_000).rounded(.towardZero))
        return formatDuration(milliseconds: milliseconds)
    }

    public static func formatDuration(milliseconds: Int64) -> String {
        if milliseconds < 1_000 {
            return "\(milliseconds)ms"
        }
        if milliseconds < 60_000 {
            return String(format: "%.2fs", locale: posixLocale, Double(milliseconds) / 1_000.0)
        }

        let minutes = milliseconds / 60_000
        let seconds = (milliseconds % 60_000) / 1_000
        return String(format: "%lldm %02llds", minutes, seconds)
    }
}
