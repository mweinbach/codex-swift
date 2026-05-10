import Foundation

public enum NonSteerableTurnKind: String, Codable, Equatable, Sendable {
    case review
    case compact
}

public enum CodexErrorInfo: Equatable, Codable, Sendable {
    case contextWindowExceeded
    case usageLimitExceeded
    case serverOverloaded
    case cyberPolicy
    case httpConnectionFailed(httpStatusCode: UInt16?)
    case responseStreamConnectionFailed(httpStatusCode: UInt16?)
    case internalServerError
    case unauthorized
    case badRequest
    case sandboxError
    case responseStreamDisconnected(httpStatusCode: UInt16?)
    case responseTooManyFailedAttempts(httpStatusCode: UInt16?)
    case activeTurnNotSteerable(turnKind: NonSteerableTurnKind)
    case threadRollbackFailed
    case other

    /// Whether this error should mark the current turn as failed when replaying history.
    public var affectsTurnStatus: Bool {
        switch self {
        case .activeTurnNotSteerable, .threadRollbackFailed:
            return false
        case .contextWindowExceeded,
             .usageLimitExceeded,
             .serverOverloaded,
             .cyberPolicy,
             .httpConnectionFailed,
             .responseStreamConnectionFailed,
             .internalServerError,
             .unauthorized,
             .badRequest,
             .sandboxError,
             .responseStreamDisconnected,
             .responseTooManyFailedAttempts,
             .other:
            return true
        }
    }

    fileprivate enum UnitVariant: String, Codable {
        case contextWindowExceeded = "context_window_exceeded"
        case usageLimitExceeded = "usage_limit_exceeded"
        case serverOverloaded = "server_overloaded"
        case cyberPolicy = "cyber_policy"
        case internalServerError = "internal_server_error"
        case unauthorized
        case badRequest = "bad_request"
        case sandboxError = "sandbox_error"
        case threadRollbackFailed = "thread_rollback_failed"
        case other
    }

    private enum ObjectVariant: String, CodingKey {
        case httpConnectionFailed = "http_connection_failed"
        case responseStreamConnectionFailed = "response_stream_connection_failed"
        case responseStreamDisconnected = "response_stream_disconnected"
        case responseTooManyFailedAttempts = "response_too_many_failed_attempts"
        case activeTurnNotSteerable = "active_turn_not_steerable"
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

        switch key {
        case .httpConnectionFailed:
            let payload = try container.decode(HTTPStatusPayload.self, forKey: key)
            self = .httpConnectionFailed(httpStatusCode: payload.httpStatusCode)
        case .responseStreamConnectionFailed:
            let payload = try container.decode(HTTPStatusPayload.self, forKey: key)
            self = .responseStreamConnectionFailed(httpStatusCode: payload.httpStatusCode)
        case .responseStreamDisconnected:
            let payload = try container.decode(HTTPStatusPayload.self, forKey: key)
            self = .responseStreamDisconnected(httpStatusCode: payload.httpStatusCode)
        case .responseTooManyFailedAttempts:
            let payload = try container.decode(HTTPStatusPayload.self, forKey: key)
            self = .responseTooManyFailedAttempts(httpStatusCode: payload.httpStatusCode)
        case .activeTurnNotSteerable:
            let payload = try container.decode(ActiveTurnNotSteerablePayload.self, forKey: key)
            self = .activeTurnNotSteerable(turnKind: payload.turnKind)
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
        case .serverOverloaded:
            var container = encoder.singleValueContainer()
            try container.encode(UnitVariant.serverOverloaded.rawValue)
        case .cyberPolicy:
            var container = encoder.singleValueContainer()
            try container.encode(UnitVariant.cyberPolicy.rawValue)
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
        case let .activeTurnNotSteerable(turnKind):
            try encodeActiveTurnNotSteerablePayload(turnKind, to: encoder)
        case .threadRollbackFailed:
            var container = encoder.singleValueContainer()
            try container.encode(UnitVariant.threadRollbackFailed.rawValue)
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

    private func encodeActiveTurnNotSteerablePayload(
        _ turnKind: NonSteerableTurnKind,
        to encoder: Encoder
    ) throws {
        var container = encoder.container(keyedBy: ObjectVariant.self)
        try container.encode(
            ActiveTurnNotSteerablePayload(turnKind: turnKind),
            forKey: .activeTurnNotSteerable
        )
    }
}

private extension CodexErrorInfo.UnitVariant {
    var codexErrorInfo: CodexErrorInfo {
        switch self {
        case .contextWindowExceeded:
            return .contextWindowExceeded
        case .usageLimitExceeded:
            return .usageLimitExceeded
        case .serverOverloaded:
            return .serverOverloaded
        case .cyberPolicy:
            return .cyberPolicy
        case .internalServerError:
            return .internalServerError
        case .unauthorized:
            return .unauthorized
        case .badRequest:
            return .badRequest
        case .sandboxError:
            return .sandboxError
        case .threadRollbackFailed:
            return .threadRollbackFailed
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

private struct ActiveTurnNotSteerablePayload: Equatable, Codable {
    let turnKind: NonSteerableTurnKind

    private enum CodingKeys: String, CodingKey {
        case turnKind = "turn_kind"
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

    /// Whether this error should mark the current turn as failed when replaying history.
    public var affectsTurnStatus: Bool {
        codexErrorInfo?.affectsTurnStatus ?? true
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

public enum ModelRerouteReason: String, Codable, Equatable, Sendable {
    case highRiskCyberActivity = "high_risk_cyber_activity"
}

public struct ModelRerouteEvent: Equatable, Codable, Sendable {
    public let fromModel: String
    public let toModel: String
    public let reason: ModelRerouteReason

    private enum CodingKeys: String, CodingKey {
        case fromModel = "from_model"
        case toModel = "to_model"
        case reason
    }

    public init(fromModel: String, toModel: String, reason: ModelRerouteReason) {
        self.fromModel = fromModel
        self.toModel = toModel
        self.reason = reason
    }
}

public enum ModelVerification: String, Codable, Equatable, Sendable {
    case trustedAccessForCyber = "trusted_access_for_cyber"
}

public struct ModelVerificationEvent: Equatable, Codable, Sendable {
    public let verifications: [ModelVerification]

    public init(verifications: [ModelVerification]) {
        self.verifications = verifications
    }
}

public struct TaskCompleteEvent: Equatable, Codable, Sendable {
    public let turnID: String
    public let lastAgentMessage: String?
    public let completedAt: Int64?
    public let durationMilliseconds: Int64?
    public let timeToFirstTokenMilliseconds: Int64?

    private enum CodingKeys: String, CodingKey {
        case turnID = "turn_id"
        case lastAgentMessage = "last_agent_message"
        case completedAt = "completed_at"
        case durationMilliseconds = "duration_ms"
        case timeToFirstTokenMilliseconds = "time_to_first_token_ms"
    }

    public init(
        turnID: String,
        lastAgentMessage: String?,
        completedAt: Int64? = nil,
        durationMilliseconds: Int64? = nil,
        timeToFirstTokenMilliseconds: Int64? = nil
    ) {
        self.turnID = turnID
        self.lastAgentMessage = lastAgentMessage
        self.completedAt = completedAt
        self.durationMilliseconds = durationMilliseconds
        self.timeToFirstTokenMilliseconds = timeToFirstTokenMilliseconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.turnID = try container.decode(String.self, forKey: .turnID)
        self.lastAgentMessage = try container.decodeIfPresent(String.self, forKey: .lastAgentMessage)
        self.completedAt = try container.decodeIfPresent(Int64.self, forKey: .completedAt)
        self.durationMilliseconds = try container.decodeIfPresent(Int64.self, forKey: .durationMilliseconds)
        self.timeToFirstTokenMilliseconds = try container.decodeIfPresent(Int64.self, forKey: .timeToFirstTokenMilliseconds)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(turnID, forKey: .turnID)
        try container.encodeIfPresentOrNull(lastAgentMessage, forKey: .lastAgentMessage)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encodeIfPresent(durationMilliseconds, forKey: .durationMilliseconds)
        try container.encodeIfPresent(timeToFirstTokenMilliseconds, forKey: .timeToFirstTokenMilliseconds)
    }
}

public struct TaskStartedEvent: Equatable, Codable, Sendable {
    public let turnID: String
    public let startedAt: Int64?
    public let modelContextWindow: Int64?
    public let collaborationModeKind: CollaborationModeKind?

    private enum CodingKeys: String, CodingKey {
        case turnID = "turn_id"
        case startedAt = "started_at"
        case modelContextWindow = "model_context_window"
        case collaborationModeKind = "collaboration_mode_kind"
    }

    public init(
        turnID: String,
        startedAt: Int64? = nil,
        modelContextWindow: Int64?,
        collaborationModeKind: CollaborationModeKind? = nil
    ) {
        self.turnID = turnID
        self.startedAt = startedAt
        self.modelContextWindow = modelContextWindow
        self.collaborationModeKind = collaborationModeKind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.turnID = try container.decode(String.self, forKey: .turnID)
        self.startedAt = try container.decodeIfPresent(Int64.self, forKey: .startedAt)
        self.modelContextWindow = try container.decodeIfPresent(Int64.self, forKey: .modelContextWindow)
        self.collaborationModeKind = try container.decodeIfPresent(
            CollaborationModeKind.self,
            forKey: .collaborationModeKind
        ) ?? .defaultMode
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(turnID, forKey: .turnID)
        try container.encodeIfPresent(startedAt, forKey: .startedAt)
        try container.encodeIfPresentOrNull(modelContextWindow, forKey: .modelContextWindow)
        try container.encode(collaborationModeKind ?? .defaultMode, forKey: .collaborationModeKind)
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
    public let turnID: String?
    public let reason: TurnAbortReason
    public let completedAt: Int64?
    public let durationMilliseconds: Int64?

    private enum CodingKeys: String, CodingKey {
        case turnID = "turn_id"
        case reason
        case completedAt = "completed_at"
        case durationMilliseconds = "duration_ms"
    }

    public init(
        turnID: String? = nil,
        reason: TurnAbortReason,
        completedAt: Int64? = nil,
        durationMilliseconds: Int64? = nil
    ) {
        self.turnID = turnID
        self.reason = reason
        self.completedAt = completedAt
        self.durationMilliseconds = durationMilliseconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        turnID = try container.decodeIfPresent(String.self, forKey: .turnID)
        reason = try container.decode(TurnAbortReason.self, forKey: .reason)
        completedAt = try container.decodeIfPresent(Int64.self, forKey: .completedAt)
        durationMilliseconds = try container.decodeIfPresent(Int64.self, forKey: .durationMilliseconds)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(turnID, forKey: .turnID)
        try container.encode(reason, forKey: .reason)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encodeIfPresent(durationMilliseconds, forKey: .durationMilliseconds)
    }
}

public enum TurnAbortReason: String, Codable, Equatable, Sendable {
    case interrupted
    case replaced
    case reviewEnded = "review_ended"
    case budgetLimited = "budget_limited"

    var rustDebugDescription: String {
        switch self {
        case .interrupted:
            return "Interrupted"
        case .replaced:
            return "Replaced"
        case .reviewEnded:
            return "ReviewEnded"
        case .budgetLimited:
            return "BudgetLimited"
        }
    }
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
