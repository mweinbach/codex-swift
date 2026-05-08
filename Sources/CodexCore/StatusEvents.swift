import Foundation

public enum CodexErrorInfo: Equatable, Codable, Sendable {
    case contextWindowExceeded
    case usageLimitExceeded
    case httpConnectionFailed(httpStatusCode: UInt16?)
    case responseStreamConnectionFailed(httpStatusCode: UInt16?)
    case internalServerError
    case unauthorized
    case badRequest
    case sandboxError
    case responseStreamDisconnected(httpStatusCode: UInt16?)
    case responseTooManyFailedAttempts(httpStatusCode: UInt16?)
    case other

    fileprivate enum UnitVariant: String, Codable {
        case contextWindowExceeded = "context_window_exceeded"
        case usageLimitExceeded = "usage_limit_exceeded"
        case internalServerError = "internal_server_error"
        case unauthorized
        case badRequest = "bad_request"
        case sandboxError = "sandbox_error"
        case other
    }

    private enum ObjectVariant: String, CodingKey {
        case httpConnectionFailed = "http_connection_failed"
        case responseStreamConnectionFailed = "response_stream_connection_failed"
        case responseStreamDisconnected = "response_stream_disconnected"
        case responseTooManyFailedAttempts = "response_too_many_failed_attempts"
    }

    public init(from decoder: Decoder) throws {
        let singleValue = try decoder.singleValueContainer()
        if let rawValue = try? singleValue.decode(String.self) {
            guard let variant = UnitVariant(rawValue: rawValue) else {
                throw DecodingError.dataCorruptedError(
                    in: singleValue,
                    debugDescription: "Unknown CodexErrorInfo variant: \(rawValue)"
                )
            }
            self = variant.codexErrorInfo
            return
        }

        let container = try decoder.container(keyedBy: ObjectVariant.self)
        guard container.allKeys.count == 1, let key = container.allKeys.first else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected exactly one CodexErrorInfo object variant"
                )
            )
        }

        let payload = try container.decode(HTTPStatusPayload.self, forKey: key)
        switch key {
        case .httpConnectionFailed:
            self = .httpConnectionFailed(httpStatusCode: payload.httpStatusCode)
        case .responseStreamConnectionFailed:
            self = .responseStreamConnectionFailed(httpStatusCode: payload.httpStatusCode)
        case .responseStreamDisconnected:
            self = .responseStreamDisconnected(httpStatusCode: payload.httpStatusCode)
        case .responseTooManyFailedAttempts:
            self = .responseTooManyFailedAttempts(httpStatusCode: payload.httpStatusCode)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .contextWindowExceeded:
            var container = encoder.singleValueContainer()
            try container.encode(UnitVariant.contextWindowExceeded.rawValue)
        case .usageLimitExceeded:
            var container = encoder.singleValueContainer()
            try container.encode(UnitVariant.usageLimitExceeded.rawValue)
        case let .httpConnectionFailed(httpStatusCode):
            try encodeHTTPStatusPayload(httpStatusCode, forKey: .httpConnectionFailed, to: encoder)
        case let .responseStreamConnectionFailed(httpStatusCode):
            try encodeHTTPStatusPayload(httpStatusCode, forKey: .responseStreamConnectionFailed, to: encoder)
        case .internalServerError:
            var container = encoder.singleValueContainer()
            try container.encode(UnitVariant.internalServerError.rawValue)
        case .unauthorized:
            var container = encoder.singleValueContainer()
            try container.encode(UnitVariant.unauthorized.rawValue)
        case .badRequest:
            var container = encoder.singleValueContainer()
            try container.encode(UnitVariant.badRequest.rawValue)
        case .sandboxError:
            var container = encoder.singleValueContainer()
            try container.encode(UnitVariant.sandboxError.rawValue)
        case let .responseStreamDisconnected(httpStatusCode):
            try encodeHTTPStatusPayload(httpStatusCode, forKey: .responseStreamDisconnected, to: encoder)
        case let .responseTooManyFailedAttempts(httpStatusCode):
            try encodeHTTPStatusPayload(httpStatusCode, forKey: .responseTooManyFailedAttempts, to: encoder)
        case .other:
            var container = encoder.singleValueContainer()
            try container.encode(UnitVariant.other.rawValue)
        }
    }

    private func encodeHTTPStatusPayload(
        _ httpStatusCode: UInt16?,
        forKey key: ObjectVariant,
        to encoder: Encoder
    ) throws {
        var container = encoder.container(keyedBy: ObjectVariant.self)
        try container.encode(HTTPStatusPayload(httpStatusCode: httpStatusCode), forKey: key)
    }
}

private extension CodexErrorInfo.UnitVariant {
    var codexErrorInfo: CodexErrorInfo {
        switch self {
        case .contextWindowExceeded:
            return .contextWindowExceeded
        case .usageLimitExceeded:
            return .usageLimitExceeded
        case .internalServerError:
            return .internalServerError
        case .unauthorized:
            return .unauthorized
        case .badRequest:
            return .badRequest
        case .sandboxError:
            return .sandboxError
        case .other:
            return .other
        }
    }
}

private struct HTTPStatusPayload: Equatable, Codable {
    let httpStatusCode: UInt16?

    private enum CodingKeys: String, CodingKey {
        case httpStatusCode = "http_status_code"
    }

    init(httpStatusCode: UInt16?) {
        self.httpStatusCode = httpStatusCode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.httpStatusCode = try container.decodeIfPresent(UInt16.self, forKey: .httpStatusCode)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresentOrNull(httpStatusCode, forKey: .httpStatusCode)
    }
}

public struct ErrorEvent: Equatable, Codable, Sendable {
    public let message: String
    public let codexErrorInfo: CodexErrorInfo?

    private enum CodingKeys: String, CodingKey {
        case message
        case codexErrorInfo = "codex_error_info"
    }

    public init(message: String, codexErrorInfo: CodexErrorInfo? = nil) {
        self.message = message
        self.codexErrorInfo = codexErrorInfo
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.message = try container.decode(String.self, forKey: .message)
        self.codexErrorInfo = try container.decodeIfPresent(CodexErrorInfo.self, forKey: .codexErrorInfo)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(message, forKey: .message)
        try container.encodeIfPresentOrNull(codexErrorInfo, forKey: .codexErrorInfo)
    }
}

public struct WarningEvent: Equatable, Codable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

public struct TaskCompleteEvent: Equatable, Codable, Sendable {
    public let lastAgentMessage: String?

    private enum CodingKeys: String, CodingKey {
        case lastAgentMessage = "last_agent_message"
    }

    public init(lastAgentMessage: String?) {
        self.lastAgentMessage = lastAgentMessage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.lastAgentMessage = try container.decodeIfPresent(String.self, forKey: .lastAgentMessage)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresentOrNull(lastAgentMessage, forKey: .lastAgentMessage)
    }
}

public struct TaskStartedEvent: Equatable, Codable, Sendable {
    public let modelContextWindow: Int64?

    private enum CodingKeys: String, CodingKey {
        case modelContextWindow = "model_context_window"
    }

    public init(modelContextWindow: Int64?) {
        self.modelContextWindow = modelContextWindow
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.modelContextWindow = try container.decodeIfPresent(Int64.self, forKey: .modelContextWindow)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresentOrNull(modelContextWindow, forKey: .modelContextWindow)
    }
}

public struct DeprecationNoticeEvent: Equatable, Codable, Sendable {
    public let summary: String
    public let details: String?

    public init(summary: String, details: String? = nil) {
        self.summary = summary
        self.details = details
    }
}

public struct UndoStartedEvent: Equatable, Codable, Sendable {
    public let message: String?

    public init(message: String? = nil) {
        self.message = message
    }
}

public struct UndoCompletedEvent: Equatable, Codable, Sendable {
    public let success: Bool
    public let message: String?

    public init(success: Bool, message: String? = nil) {
        self.success = success
        self.message = message
    }
}

public struct StreamErrorEvent: Equatable, Codable, Sendable {
    public let message: String
    public let codexErrorInfo: CodexErrorInfo?
    public let additionalDetails: String?

    private enum CodingKeys: String, CodingKey {
        case message
        case codexErrorInfo = "codex_error_info"
        case additionalDetails = "additional_details"
    }

    public init(message: String, codexErrorInfo: CodexErrorInfo? = nil, additionalDetails: String? = nil) {
        self.message = message
        self.codexErrorInfo = codexErrorInfo
        self.additionalDetails = additionalDetails
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.message = try container.decode(String.self, forKey: .message)
        self.codexErrorInfo = try container.decodeIfPresent(CodexErrorInfo.self, forKey: .codexErrorInfo)
        self.additionalDetails = try container.decodeIfPresent(String.self, forKey: .additionalDetails)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(message, forKey: .message)
        try container.encodeIfPresentOrNull(codexErrorInfo, forKey: .codexErrorInfo)
        try container.encodeIfPresentOrNull(additionalDetails, forKey: .additionalDetails)
    }
}

public struct StreamInfoEvent: Equatable, Codable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

public struct TurnAbortedEvent: Equatable, Codable, Sendable {
    public let reason: TurnAbortReason

    public init(reason: TurnAbortReason) {
        self.reason = reason
    }
}

public enum TurnAbortReason: String, Codable, Equatable, Sendable {
    case interrupted
    case replaced
    case reviewEnded = "review_ended"
}

private extension KeyedEncodingContainer {
    mutating func encodeIfPresentOrNull<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}
