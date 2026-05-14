import Foundation

public struct DeprecationNoticeNotification: Equatable, Sendable {
    public let summary: String
    public let details: String?

    public init(summary: String, details: String? = nil) {
        self.summary = summary
        self.details = details
    }
}

extension DeprecationNoticeNotification: Codable {
    private enum CodingKeys: String, CodingKey {
        case summary
        case details
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(summary, forKey: .summary)
        try container.encodeNilOrValue(details, forKey: .details)
    }
}

public struct WarningNotification: Equatable, Sendable {
    public let threadID: String?
    public let message: String

    public init(threadID: String? = nil, message: String) {
        self.threadID = threadID
        self.message = message
    }
}

extension WarningNotification: Codable {
    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case message
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNilOrValue(threadID, forKey: .threadID)
        try container.encode(message, forKey: .message)
    }
}

public struct GuardianWarningNotification: Equatable, Codable, Sendable {
    public let threadID: String
    public let message: String

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case message
    }

    public init(threadID: String, message: String) {
        self.threadID = threadID
        self.message = message
    }
}

public struct ErrorNotification: Equatable, Codable, Sendable {
    public let error: AppServerTurnError
    public let willRetry: Bool
    public let threadID: String
    public let turnID: String

    private enum CodingKeys: String, CodingKey {
        case error
        case willRetry
        case threadID = "threadId"
        case turnID = "turnId"
    }

    public init(error: AppServerTurnError, willRetry: Bool, threadID: String, turnID: String) {
        self.error = error
        self.willRetry = willRetry
        self.threadID = threadID
        self.turnID = turnID
    }
}

public struct ServerRequestResolvedNotification: Equatable, Codable, Sendable {
    public let threadID: String
    public let requestID: RequestID

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case requestID = "requestId"
    }

    public init(threadID: String, requestID: RequestID) {
        self.threadID = threadID
        self.requestID = requestID
    }
}

public struct RemoteControlStatusChangedNotification: Equatable, Sendable {
    public let status: RemoteControlConnectionStatus
    public let installationID: String
    public let environmentID: String?

    public init(status: RemoteControlConnectionStatus, installationID: String, environmentID: String?) {
        self.status = status
        self.installationID = installationID
        self.environmentID = environmentID
    }

    public init(snapshot: RemoteControlStatusSnapshot) {
        self.init(
            status: snapshot.status,
            installationID: snapshot.installationID,
            environmentID: snapshot.environmentID
        )
    }
}

extension RemoteControlStatusChangedNotification: Codable {
    private enum CodingKeys: String, CodingKey {
        case status
        case installationID = "installationId"
        case environmentID = "environmentId"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encode(installationID, forKey: .installationID)
        try container.encodeNilOrValue(environmentID, forKey: .environmentID)
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeNilOrValue<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}
