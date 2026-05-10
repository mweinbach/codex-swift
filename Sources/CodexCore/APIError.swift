import Foundation

public enum APIError: Error, Equatable, CustomStringConvertible, Sendable {
    case transport(TransportError)
    case api(statusCode: Int, message: String)
    case stream(String)
    case contextWindowExceeded
    case quotaExceeded
    case usageNotIncluded
    case retryable(message: String, delay: Duration?)
    case rateLimit(String)
    case invalidRequest(message: String)
    case cyberPolicy(message: String)
    case serverOverloaded

    public init(rateLimitError: RateLimitError) {
        self = .rateLimit(String(describing: rateLimitError))
    }

    public var description: String {
        switch self {
        case let .transport(error):
            return String(describing: error)
        case let .api(statusCode, message):
            return "api error \(HTTPStatus.description(for: statusCode)): \(message)"
        case let .stream(message):
            return "stream error: \(message)"
        case .contextWindowExceeded:
            return "context window exceeded"
        case .quotaExceeded:
            return "quota exceeded"
        case .usageNotIncluded:
            return "usage not included"
        case let .retryable(message, _):
            return "retryable error: \(message)"
        case let .rateLimit(message):
            return "rate limit: \(message)"
        case let .invalidRequest(message):
            return "invalid request: \(message)"
        case let .cyberPolicy(message):
            return "cyber policy: \(message)"
        case .serverOverloaded:
            return "server overloaded"
        }
    }
}

public struct RateLimitError: Error, Equatable, CustomStringConvertible, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var description: String {
        message
    }
}

public struct UnexpectedResponseError: Error, Equatable, CustomStringConvertible, Sendable {
    public let statusCode: Int
    public let body: String
    public let url: String?
    public let cfRay: String?
    public let requestID: String?
    public let identityAuthorizationError: String?
    public let identityErrorCode: String?

    private static let cloudflareBlockedMessage =
        "Access blocked by Cloudflare. This usually happens when connecting from a restricted region"
    private static let bodyMaxBytes = 1_000

    public init(
        statusCode: Int,
        body: String,
        url: String? = nil,
        cfRay: String? = nil,
        requestID: String? = nil,
        identityAuthorizationError: String? = nil,
        identityErrorCode: String? = nil
    ) {
        self.statusCode = statusCode
        self.body = body
        self.url = url
        self.cfRay = cfRay
        self.requestID = requestID
        self.identityAuthorizationError = identityAuthorizationError
        self.identityErrorCode = identityErrorCode
    }

    public var description: String {
        if let friendlyMessage {
            return friendlyMessage
        }

        var message = "unexpected status \(HTTPStatus.description(for: statusCode)): \(displayBody)"
        appendMetadata(to: &message)
        return message
    }

    private var displayBody: String {
        if let message = extractedErrorMessage {
            return message
        }

        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Unknown error"
        }

        return Self.truncateWithEllipsis(trimmed, maxBytes: Self.bodyMaxBytes)
    }

    private var extractedErrorMessage: String? {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any],
              let rawMessage = error["message"] as? String
        else {
            return nil
        }

        let message = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? nil : message
    }

    private var friendlyMessage: String? {
        guard statusCode == 403,
              body.contains("Cloudflare"),
              body.contains("blocked")
        else {
            return nil
        }

        var message = "\(Self.cloudflareBlockedMessage) (status \(HTTPStatus.description(for: statusCode)))"
        appendMetadata(to: &message)
        return message
    }

    private func appendMetadata(to message: inout String) {
        if let url {
            message += ", url: \(url)"
        }
        if let cfRay {
            message += ", cf-ray: \(cfRay)"
        }
        if let requestID {
            message += ", request id: \(requestID)"
        }
        if let identityAuthorizationError {
            message += ", auth error: \(identityAuthorizationError)"
        }
        if let identityErrorCode {
            message += ", auth error code: \(identityErrorCode)"
        }
    }

    private static func truncateWithEllipsis(_ text: String, maxBytes: Int) -> String {
        guard text.utf8.count > maxBytes else {
            return text
        }

        var byteCount = 0
        var result = ""
        for character in text {
            let characterBytes = character.utf8.count
            if byteCount + characterBytes > maxBytes {
                break
            }
            result.append(character)
            byteCount += characterBytes
        }
        return result + "..."
    }
}

public struct RetryLimitReachedError: Error, Equatable, CustomStringConvertible, Sendable {
    public let statusCode: Int
    public let requestID: String?

    public init(statusCode: Int, requestID: String? = nil) {
        self.statusCode = statusCode
        self.requestID = requestID
    }

    public var description: String {
        var message = "exceeded retry limit, last status: \(HTTPStatus.description(for: statusCode))"
        if let requestID {
            message += ", request id: \(requestID)"
        }
        return message
    }
}

public struct EnvVarError: Error, Equatable, CustomStringConvertible, Sendable {
    public let variable: String
    public let instructions: String?

    public init(variable: String, instructions: String? = nil) {
        self.variable = variable
        self.instructions = instructions
    }

    public var description: String {
        var message = "Missing environment variable: `\(variable)`."
        if let instructions {
            message += " \(instructions)"
        }
        return message
    }
}

public struct UsageLimitReachedError: Error, Equatable, CustomStringConvertible, Sendable {
    public let planType: PlanType?
    public let resetsAt: Date?
    public let rateLimits: RateLimitSnapshot?
    public let promoMessage: String?

    public init(
        planType: PlanType? = nil,
        resetsAt: Date? = nil,
        rateLimits: RateLimitSnapshot? = nil,
        promoMessage: String? = nil
    ) {
        self.planType = planType
        self.resetsAt = resetsAt
        self.rateLimits = rateLimits
        self.promoMessage = promoMessage
    }

    public var description: String {
        description(now: Date(), calendar: .current)
    }

    public func description(now: Date, calendar: Calendar) -> String {
        if let limitName = rateLimits?.limitName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !limitName.isEmpty,
           limitName.lowercased() != "codex" {
            return "You've hit your usage limit for \(limitName). Switch to another model now,\(retrySuffixAfterOr(now: now, calendar: calendar))"
        }

        if let promoMessage {
            return "You've hit your usage limit. \(promoMessage),\(retrySuffixAfterOr(now: now, calendar: calendar))"
        }

        switch planType {
        case .plus:
            return """
            You've hit your usage limit. Upgrade to Pro (https://chatgpt.com/explore/pro), visit https://chatgpt.com/codex/settings/usage to purchase more credits\(retrySuffixAfterOr(now: now, calendar: calendar))
            """
        case .team, .selfServeBusinessUsageBased, .business, .enterpriseCbpUsageBased:
            return "You've hit your usage limit. To get more access now, send a request to your admin\(retrySuffixAfterOr(now: now, calendar: calendar))"
        case .free, .go:
            return "You've hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus),\(retrySuffixAfterOr(now: now, calendar: calendar))"
        case .pro, .proLite:
            return "You've hit your usage limit. Visit https://chatgpt.com/codex/settings/usage to purchase more credits\(retrySuffixAfterOr(now: now, calendar: calendar))"
        case .enterprise, .edu, .unknown, nil:
            return "You've hit your usage limit.\(retrySuffix(now: now, calendar: calendar))"
        }
    }

    private func retrySuffix(now: Date, calendar: Calendar) -> String {
        guard let resetsAt else {
            return " Try again later."
        }
        return " Try again at \(Self.formatRetryTimestamp(resetsAt, now: now, calendar: calendar))."
    }

    private func retrySuffixAfterOr(now: Date, calendar: Calendar) -> String {
        guard let resetsAt else {
            return " or try again later."
        }
        return " or try again at \(Self.formatRetryTimestamp(resetsAt, now: now, calendar: calendar))."
    }

    private static func formatRetryTimestamp(_ resetsAt: Date, now: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone

        if calendar.isDate(resetsAt, inSameDayAs: now) {
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: resetsAt)
        }

        formatter.dateFormat = "MMM d'\(daySuffix(calendar.component(.day, from: resetsAt)))', yyyy h:mm a"
        return formatter.string(from: resetsAt)
    }

    private static func daySuffix(_ day: Int) -> String {
        switch day {
        case 11...13:
            return "th"
        default:
            switch day % 10 {
            case 1:
                return "st"
            case 2:
                return "nd"
            case 3:
                return "rd"
            default:
                return "th"
            }
        }
    }
}
