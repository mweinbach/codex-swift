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
