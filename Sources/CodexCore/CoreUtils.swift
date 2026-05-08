import Foundation

public enum CoreUtils {
    public static let initialDelayMilliseconds: UInt64 = 200
    public static let backoffFactor = 2.0

    public static func backoffMilliseconds(attempt: UInt64, jitter: () -> Double = {
        Double.random(in: 0.9..<1.1)
    }) -> UInt64 {
        let exponent = Int(attempt.saturatingSubtracting(1))
        let base = Double(initialDelayMilliseconds) * pow(backoffFactor, Double(exponent))
        let value = base * jitter()
        guard value.isFinite, value < Double(UInt64.max) else {
            return UInt64.max
        }
        return UInt64(max(0, value))
    }

    public static func errorOrPanic(_ message: @autoclosure () -> String) {
        #if DEBUG
        fatalError(message())
        #else
        fputs(message() + "\n", stderr)
        #endif
    }

    public static func tryParseErrorMessage(_ text: String) -> String {
        if let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String
        {
            return message
        }

        if text.isEmpty {
            return "Unknown error"
        }
        return text
    }

    public static func resolvePath(base: String, path: String) -> String {
        guard !path.hasPrefix("/") else {
            return path
        }
        guard base != "/" else {
            return "/" + path
        }
        return base + "/" + path
    }
}

private extension UInt64 {
    func saturatingSubtracting(_ value: UInt64) -> UInt64 {
        self > value ? self - value : 0
    }
}
