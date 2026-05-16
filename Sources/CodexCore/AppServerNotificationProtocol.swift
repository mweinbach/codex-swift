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

public enum GuardianApprovalReviewStatus: String, Codable, Equatable, Sendable {
    case inProgress
    case approved
    case denied
    case timedOut
    case aborted
}

public struct GuardianApprovalReview: Equatable, Sendable {
    public let status: GuardianApprovalReviewStatus
    public let riskLevel: GuardianRiskLevel?
    public let userAuthorization: GuardianUserAuthorization?
    public let rationale: String?

    private enum CodingKeys: String, CodingKey {
        case status
        case riskLevel
        case userAuthorization
        case rationale
    }

    public init(
        status: GuardianApprovalReviewStatus,
        riskLevel: GuardianRiskLevel? = nil,
        userAuthorization: GuardianUserAuthorization? = nil,
        rationale: String? = nil
    ) {
        self.status = status
        self.riskLevel = riskLevel
        self.userAuthorization = userAuthorization
        self.rationale = rationale
    }
}

extension GuardianApprovalReview: Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encodeNilOrValue(riskLevel, forKey: .riskLevel)
        try container.encodeNilOrValue(userAuthorization, forKey: .userAuthorization)
        try container.encodeNilOrValue(rationale, forKey: .rationale)
    }
}

public enum GuardianApprovalReviewCommandSource: String, Codable, Equatable, Sendable {
    case shell
    case unifiedExec
}

public enum GuardianApprovalReviewAction: Equatable, Sendable {
    case command(source: GuardianApprovalReviewCommandSource, command: String, cwd: AbsolutePath)
    case execve(source: GuardianApprovalReviewCommandSource, program: String, argv: [String], cwd: AbsolutePath)
    case applyPatch(cwd: AbsolutePath, files: [AbsolutePath])
    case networkAccess(target: String, host: String, protocol: NetworkApprovalProtocol, port: UInt16)
    case mcpToolCall(
        server: String,
        toolName: String,
        connectorID: String?,
        connectorName: String?,
        toolTitle: String?
    )
    case requestPermissions(reason: String?, permissions: RequestPermissionProfile)

    private enum CodingKeys: String, CodingKey {
        case type
        case source
        case command
        case cwd
        case program
        case argv
        case files
        case target
        case host
        case `protocol`
        case port
        case server
        case toolName
        case connectorID = "connectorId"
        case connectorName
        case toolTitle
        case reason
        case permissions
    }

    private enum ActionType: String, Codable {
        case command
        case execve
        case applyPatch
        case networkAccess
        case mcpToolCall
        case requestPermissions
    }
}

extension GuardianApprovalReviewAction: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ActionType.self, forKey: .type) {
        case .command:
            self = .command(
                source: try container.decode(GuardianApprovalReviewCommandSource.self, forKey: .source),
                command: try container.decode(String.self, forKey: .command),
                cwd: try container.decode(AbsolutePath.self, forKey: .cwd)
            )
        case .execve:
            self = .execve(
                source: try container.decode(GuardianApprovalReviewCommandSource.self, forKey: .source),
                program: try container.decode(String.self, forKey: .program),
                argv: try container.decode([String].self, forKey: .argv),
                cwd: try container.decode(AbsolutePath.self, forKey: .cwd)
            )
        case .applyPatch:
            self = .applyPatch(
                cwd: try container.decode(AbsolutePath.self, forKey: .cwd),
                files: try container.decode([AbsolutePath].self, forKey: .files)
            )
        case .networkAccess:
            self = .networkAccess(
                target: try container.decode(String.self, forKey: .target),
                host: try container.decode(String.self, forKey: .host),
                protocol: try Self.decodeAppServerNetworkApprovalProtocol(container, forKey: .protocol),
                port: try container.decode(UInt16.self, forKey: .port)
            )
        case .mcpToolCall:
            self = .mcpToolCall(
                server: try container.decode(String.self, forKey: .server),
                toolName: try container.decode(String.self, forKey: .toolName),
                connectorID: try container.decodeIfPresent(String.self, forKey: .connectorID),
                connectorName: try container.decodeIfPresent(String.self, forKey: .connectorName),
                toolTitle: try container.decodeIfPresent(String.self, forKey: .toolTitle)
            )
        case .requestPermissions:
            self = .requestPermissions(
                reason: try container.decodeIfPresent(String.self, forKey: .reason),
                permissions: try container.decode(RequestPermissionProfile.self, forKey: .permissions)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .command(source, command, cwd):
            try container.encode(ActionType.command, forKey: .type)
            try container.encode(source, forKey: .source)
            try container.encode(command, forKey: .command)
            try container.encode(cwd, forKey: .cwd)
        case let .execve(source, program, argv, cwd):
            try container.encode(ActionType.execve, forKey: .type)
            try container.encode(source, forKey: .source)
            try container.encode(program, forKey: .program)
            try container.encode(argv, forKey: .argv)
            try container.encode(cwd, forKey: .cwd)
        case let .applyPatch(cwd, files):
            try container.encode(ActionType.applyPatch, forKey: .type)
            try container.encode(cwd, forKey: .cwd)
            try container.encode(files, forKey: .files)
        case let .networkAccess(target, host, protocolValue, port):
            try container.encode(ActionType.networkAccess, forKey: .type)
            try container.encode(target, forKey: .target)
            try container.encode(host, forKey: .host)
            try container.encode(Self.appServerNetworkApprovalProtocolName(protocolValue), forKey: .protocol)
            try container.encode(port, forKey: .port)
        case let .mcpToolCall(server, toolName, connectorID, connectorName, toolTitle):
            try container.encode(ActionType.mcpToolCall, forKey: .type)
            try container.encode(server, forKey: .server)
            try container.encode(toolName, forKey: .toolName)
            try container.encodeNilOrValue(connectorID, forKey: .connectorID)
            try container.encodeNilOrValue(connectorName, forKey: .connectorName)
            try container.encodeNilOrValue(toolTitle, forKey: .toolTitle)
        case let .requestPermissions(reason, permissions):
            try container.encode(ActionType.requestPermissions, forKey: .type)
            try container.encodeNilOrValue(reason, forKey: .reason)
            try container.encode(permissions, forKey: .permissions)
        }
    }

    private static func decodeAppServerNetworkApprovalProtocol<Key: CodingKey>(
        _ container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) throws -> NetworkApprovalProtocol {
        switch try container.decode(String.self, forKey: key) {
        case "http":
            return .http
        case "https":
            return .https
        case "socks5Tcp", "socks5_tcp":
            return .socks5Tcp
        case "socks5Udp", "socks5_udp":
            return .socks5Udp
        case let value:
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Unsupported network approval protocol: \(value)"
            )
        }
    }

    private static func appServerNetworkApprovalProtocolName(_ value: NetworkApprovalProtocol) -> String {
        switch value {
        case .http:
            return "http"
        case .https:
            return "https"
        case .socks5Tcp:
            return "socks5Tcp"
        case .socks5Udp:
            return "socks5Udp"
        }
    }
}

public enum AutoReviewDecisionSource: String, Codable, Equatable, Sendable {
    case agent
}

public struct ItemGuardianApprovalReviewStartedNotification: Equatable, Sendable {
    public let threadID: String
    public let turnID: String
    public let startedAtMilliseconds: Int64
    public let reviewID: String
    public let targetItemID: String?
    public let review: GuardianApprovalReview
    public let action: GuardianApprovalReviewAction

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case turnID = "turnId"
        case startedAtMilliseconds = "startedAtMs"
        case reviewID = "reviewId"
        case targetItemID = "targetItemId"
        case review
        case action
    }

    public init(
        threadID: String,
        turnID: String,
        startedAtMilliseconds: Int64,
        reviewID: String,
        targetItemID: String?,
        review: GuardianApprovalReview,
        action: GuardianApprovalReviewAction
    ) {
        self.threadID = threadID
        self.turnID = turnID
        self.startedAtMilliseconds = startedAtMilliseconds
        self.reviewID = reviewID
        self.targetItemID = targetItemID
        self.review = review
        self.action = action
    }
}

extension ItemGuardianApprovalReviewStartedNotification: Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(threadID, forKey: .threadID)
        try container.encode(turnID, forKey: .turnID)
        try container.encode(startedAtMilliseconds, forKey: .startedAtMilliseconds)
        try container.encode(reviewID, forKey: .reviewID)
        try container.encodeNilOrValue(targetItemID, forKey: .targetItemID)
        try container.encode(review, forKey: .review)
        try container.encode(action, forKey: .action)
    }
}

public struct ItemGuardianApprovalReviewCompletedNotification: Equatable, Sendable {
    public let threadID: String
    public let turnID: String
    public let startedAtMilliseconds: Int64
    public let completedAtMilliseconds: Int64
    public let reviewID: String
    public let targetItemID: String?
    public let decisionSource: AutoReviewDecisionSource
    public let review: GuardianApprovalReview
    public let action: GuardianApprovalReviewAction

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case turnID = "turnId"
        case startedAtMilliseconds = "startedAtMs"
        case completedAtMilliseconds = "completedAtMs"
        case reviewID = "reviewId"
        case targetItemID = "targetItemId"
        case decisionSource
        case review
        case action
    }

    public init(
        threadID: String,
        turnID: String,
        startedAtMilliseconds: Int64,
        completedAtMilliseconds: Int64,
        reviewID: String,
        targetItemID: String?,
        decisionSource: AutoReviewDecisionSource,
        review: GuardianApprovalReview,
        action: GuardianApprovalReviewAction
    ) {
        self.threadID = threadID
        self.turnID = turnID
        self.startedAtMilliseconds = startedAtMilliseconds
        self.completedAtMilliseconds = completedAtMilliseconds
        self.reviewID = reviewID
        self.targetItemID = targetItemID
        self.decisionSource = decisionSource
        self.review = review
        self.action = action
    }
}

extension ItemGuardianApprovalReviewCompletedNotification: Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(threadID, forKey: .threadID)
        try container.encode(turnID, forKey: .turnID)
        try container.encode(startedAtMilliseconds, forKey: .startedAtMilliseconds)
        try container.encode(completedAtMilliseconds, forKey: .completedAtMilliseconds)
        try container.encode(reviewID, forKey: .reviewID)
        try container.encodeNilOrValue(targetItemID, forKey: .targetItemID)
        try container.encode(decisionSource, forKey: .decisionSource)
        try container.encode(review, forKey: .review)
        try container.encode(action, forKey: .action)
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
    public let serverName: String
    public let installationID: String
    public let environmentID: String?

    public init(
        status: RemoteControlConnectionStatus,
        serverName: String = RemoteControlStatusSnapshot.defaultServerName,
        installationID: String,
        environmentID: String?
    ) {
        self.status = status
        self.serverName = serverName
        self.installationID = installationID
        self.environmentID = environmentID
    }

    public init(snapshot: RemoteControlStatusSnapshot) {
        self.init(
            status: snapshot.status,
            serverName: snapshot.serverName,
            installationID: snapshot.installationID,
            environmentID: snapshot.environmentID
        )
    }
}

extension RemoteControlStatusChangedNotification: Codable {
    private enum CodingKeys: String, CodingKey {
        case status
        case serverName
        case installationID = "installationId"
        case environmentID = "environmentId"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encode(serverName, forKey: .serverName)
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
