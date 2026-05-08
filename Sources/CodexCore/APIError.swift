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
