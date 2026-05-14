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

public enum CodexError: Error, Equatable, CustomStringConvertible, Sendable {
    case contextWindowExceeded
    case quotaExceeded
    case usageNotIncluded
    case stream(message: String, delay: Duration?)
    case serverOverloaded
    case unexpectedStatus(UnexpectedResponseError)
    case invalidRequest(String)
    case cyberPolicy(message: String)
    case responseStreamFailed(ResponseStreamFailedError)
    case connectionFailed(ConnectionFailedError)
    case usageLimitReached(UsageLimitReachedError)
    case invalidImageRequest
    case internalServerError
    case retryLimit(RetryLimitReachedError)
    case timeout

    public init(apiError: APIError) {
        self = Self.map(apiError)
    }

    public var description: String {
        switch self {
        case .contextWindowExceeded:
            return "context window exceeded"
        case .quotaExceeded:
            return "quota exceeded"
        case .usageNotIncluded:
            return "usage not included"
        case let .stream(message, _):
            return message
        case .serverOverloaded:
            return "server overloaded"
        case let .unexpectedStatus(error):
            return String(describing: error)
        case let .invalidRequest(message):
            return message
        case let .cyberPolicy(message):
            return "cyber policy: \(message)"
        case let .responseStreamFailed(error):
            return String(describing: error)
        case let .connectionFailed(error):
            return String(describing: error)
        case let .usageLimitReached(error):
            return String(describing: error)
        case .invalidImageRequest:
            return "invalid image request"
        case .internalServerError:
            return "internal server error"
        case let .retryLimit(error):
            return String(describing: error)
        case .timeout:
            return "timeout"
        }
    }

    public static func map(_ error: APIError) -> CodexError {
        switch error {
        case .contextWindowExceeded:
            return .contextWindowExceeded
        case .quotaExceeded:
            return .quotaExceeded
        case .usageNotIncluded:
            return .usageNotIncluded
        case let .retryable(message, delay):
            return .stream(message: message, delay: delay)
        case let .stream(message):
            return .stream(message: message, delay: nil)
        case .serverOverloaded:
            return .serverOverloaded
        case let .api(statusCode, message):
            return .unexpectedStatus(UnexpectedResponseError(statusCode: statusCode, body: message))
        case let .invalidRequest(message):
            return .invalidRequest(message)
        case let .cyberPolicy(message):
            return .cyberPolicy(message: message)
        case let .transport(transport):
            return mapTransportError(transport)
        case let .rateLimit(message):
            return .stream(message: message, delay: nil)
        }
    }

    public func toCodexProtocolError() -> CodexErrorInfo {
        switch self {
        case .contextWindowExceeded:
            return .contextWindowExceeded
        case .usageLimitReached, .quotaExceeded, .usageNotIncluded:
            return .usageLimitExceeded
        case .serverOverloaded:
            return .serverOverloaded
        case .cyberPolicy:
            return .cyberPolicy
        case let .retryLimit(error):
            return .responseTooManyFailedAttempts(httpStatusCode: Self.httpStatusCodeValue(error.statusCode))
        case let .connectionFailed(error):
            return .httpConnectionFailed(httpStatusCode: Self.httpStatusCodeValue(error.statusCode))
        case let .responseStreamFailed(error):
            return .responseStreamConnectionFailed(httpStatusCode: Self.httpStatusCodeValue(error.statusCode))
        case .internalServerError:
            return .internalServerError
        default:
            return .other
        }
    }

    public func toErrorEvent(messagePrefix: String? = nil) -> ErrorEvent {
        let errorMessage = String(describing: self)
        let message = messagePrefix.map { "\($0): \(errorMessage)" } ?? errorMessage
        return ErrorEvent(message: message, codexErrorInfo: toCodexProtocolError())
    }

    private static func httpStatusCodeValue(_ statusCode: Int?) -> UInt16? {
        guard let statusCode, (0...Int(UInt16.max)).contains(statusCode) else {
            return nil
        }
        return UInt16(statusCode)
    }

    private static func mapTransportError(_ error: TransportError) -> CodexError {
        switch error {
        case let .http(statusCode, url, headers, body):
            return mapHTTPError(statusCode: statusCode, url: url, headers: headers, body: body ?? "")
        case .retryLimit:
            return .retryLimit(RetryLimitReachedError(statusCode: 500))
        case .timeout:
            return .timeout
        case let .network(message), let .build(message):
            return .stream(message: message, delay: nil)
        }
    }

    private static func mapHTTPError(
        statusCode: Int,
        url: String?,
        headers: [String: String]?,
        body: String
    ) -> CodexError {
        if statusCode == 503,
           let value = decodeJSONObject(body),
           let code = (value["error"] as? [String: Any])?["code"] as? String,
           code == "server_is_overloaded" || code == "slow_down" {
            return .serverOverloaded
        }

        if statusCode == 400 {
            if let value = decodeJSONObject(body),
               let error = value["error"] as? [String: Any],
               error["code"] as? String == cyberPolicyErrorCode {
                return .cyberPolicy(message: cyberPolicyMessage(error["message"] as? String))
            }
            if body.contains("The image data you provided does not represent a valid image") {
                return .invalidImageRequest
            }
            return .invalidRequest(body)
        }

        if statusCode == 500 {
            return .internalServerError
        }

        if statusCode == 429 {
            if let usageError = try? JSONDecoder().decode(UsageErrorResponse.self, from: Data(body.utf8)) {
                if usageError.error.errorType == "usage_limit_reached" {
                    let limitID = header(headers, activeLimitHeader)
                    return .usageLimitReached(UsageLimitReachedError(
                        planType: usageError.error.planType,
                        resetsAt: usageError.error.resetsAt.map(Date.init(timeIntervalSince1970:)),
                        rateLimits: headers.flatMap { RateLimitSnapshot.parseRateLimit(headers: $0, limitID: limitID) },
                        promoMessage: promoMessage(headers)
                    ))
                }
                if usageError.error.errorType == "usage_not_included" {
                    return .usageNotIncluded
                }
            }
            return .retryLimit(RetryLimitReachedError(
                statusCode: statusCode,
                requestID: requestTrackingID(headers)
            ))
        }

        return .unexpectedStatus(UnexpectedResponseError(
            statusCode: statusCode,
            body: body,
            url: url,
            cfRay: header(headers, cfRayHeader),
            requestID: requestID(headers),
            identityAuthorizationError: header(headers, openAIAuthorizationErrorHeader),
            identityErrorCode: errorJSONCode(headers)
        ))
    }

    private static let activeLimitHeader = "x-codex-active-limit"
    private static let requestIDHeader = "x-request-id"
    private static let openAIRequestIDHeader = "x-oai-request-id"
    private static let cfRayHeader = "cf-ray"
    private static let openAIAuthorizationErrorHeader = "x-openai-authorization-error"
    private static let errorJSONHeader = "x-error-json"
    private static let promoMessageHeader = "x-codex-promo-message"
    private static let cyberPolicyErrorCode = "cyber_policy"
    private static let cyberPolicyFallbackMessage =
        "This request has been flagged for possible cybersecurity risk."

    private static func cyberPolicyMessage(_ message: String?) -> String {
        guard let message = message?.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty
        else {
            return cyberPolicyFallbackMessage
        }
        return message
    }

    private static func promoMessage(_ headers: [String: String]?) -> String? {
        guard let promo = header(headers, promoMessageHeader)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !promo.isEmpty
        else {
            return nil
        }
        return promo
    }

    private static func requestTrackingID(_ headers: [String: String]?) -> String? {
        requestID(headers) ?? header(headers, cfRayHeader)
    }

    private static func requestID(_ headers: [String: String]?) -> String? {
        header(headers, requestIDHeader) ?? header(headers, openAIRequestIDHeader)
    }

    private static func header(_ headers: [String: String]?, _ name: String) -> String? {
        headers?.first { key, _ in key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    private static func errorJSONCode(_ headers: [String: String]?) -> String? {
        guard let encoded = header(headers, errorJSONHeader),
              let decoded = Data(base64Encoded: encoded),
              let value = try? JSONSerialization.jsonObject(with: decoded) as? [String: Any]
        else {
            return nil
        }
        return (value["error"] as? [String: Any])?["code"] as? String
    }

    private static func decodeJSONObject(_ body: String) -> [String: Any]? {
        guard let data = body.data(using: .utf8) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

private struct UsageErrorResponse: Decodable {
    let error: UsageErrorBody
}

private struct UsageErrorBody: Decodable {
    let errorType: String?
    let planType: PlanType?
    let resetsAt: Double?

    private enum CodingKeys: String, CodingKey {
        case errorType = "type"
        case planType = "plan_type"
        case resetsAt = "resets_at"
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

public struct ConnectionFailedError: Error, Equatable, CustomStringConvertible, Sendable {
    public let sourceDescription: String
    public let statusCode: Int?

    public init(sourceDescription: String, statusCode: Int? = nil) {
        self.sourceDescription = sourceDescription
        self.statusCode = statusCode
    }

    public init(statusCode: Int, url: String) {
        self.sourceDescription = Self.statusErrorDescription(statusCode: statusCode, url: url)
        self.statusCode = statusCode
    }

    public var description: String {
        "Connection failed: \(sourceDescription)"
    }
}

public struct ResponseStreamFailedError: Error, Equatable, CustomStringConvertible, Sendable {
    public let sourceDescription: String
    public let statusCode: Int?
    public let requestID: String?

    public init(sourceDescription: String, statusCode: Int? = nil, requestID: String? = nil) {
        self.sourceDescription = sourceDescription
        self.statusCode = statusCode
        self.requestID = requestID
    }

    public init(statusCode: Int, url: String, requestID: String? = nil) {
        self.sourceDescription = ConnectionFailedError.statusErrorDescription(statusCode: statusCode, url: url)
        self.statusCode = statusCode
        self.requestID = requestID
    }

    public var description: String {
        var message = "Error while reading the server response: \(sourceDescription)"
        if let requestID {
            message += ", request id: \(requestID)"
        }
        return message
    }
}

private extension ConnectionFailedError {
    static func statusErrorDescription(statusCode: Int, url: String) -> String {
        let statusClass: String
        switch statusCode {
        case 400...499:
            statusClass = "client"
        case 500...599:
            statusClass = "server"
        default:
            statusClass = "status"
        }
        return "HTTP status \(statusClass) error (\(HTTPStatus.description(for: statusCode))) for url (\(url))"
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
