import Foundation

public enum NetworkApprovalProtocol: String, Codable, Equatable, Sendable {
    case http
    case https
    case socks5Tcp = "socks5_tcp"
    case socks5Udp = "socks5_udp"

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        switch try container.decode(String.self) {
        case "http":
            self = .http
        case "https", "https_connect", "http-connect":
            self = .https
        case "socks5_tcp":
            self = .socks5Tcp
        case "socks5_udp":
            self = .socks5Udp
        case let value:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported network approval protocol: \(value)"
            )
        }
    }
}

public enum GuardianRiskLevel: String, Codable, Equatable, Sendable {
    case low
    case medium
    case high
    case critical
}

public enum GuardianUserAuthorization: String, Codable, Equatable, Sendable {
    case unknown
    case low
    case medium
    case high
}

public enum GuardianAssessmentOutcome: String, Codable, Equatable, Sendable {
    case allow
    case deny
}

public enum GuardianAssessmentStatus: String, Codable, Equatable, Sendable {
    case inProgress = "in_progress"
    case approved
    case denied
    case timedOut = "timed_out"
    case aborted
}

public enum GuardianAssessmentDecisionSource: String, Codable, Equatable, Sendable {
    case agent
}

public enum GuardianCommandSource: String, Codable, Equatable, Sendable {
    case shell
    case unifiedExec = "unified_exec"
}

public enum GuardianAssessmentAction: Equatable, Sendable {
    case command(source: GuardianCommandSource, command: String, cwd: String)
    case execve(source: GuardianCommandSource, program: String, argv: [String], cwd: String)
    case applyPatch(cwd: String, files: [String])
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
        case toolName = "tool_name"
        case connectorID = "connector_id"
        case connectorName = "connector_name"
        case toolTitle = "tool_title"
        case reason
        case permissions
    }

    private enum ActionType: String, Codable {
        case command
        case execve
        case applyPatch = "apply_patch"
        case networkAccess = "network_access"
        case mcpToolCall = "mcp_tool_call"
        case requestPermissions = "request_permissions"
    }
}

extension GuardianAssessmentAction: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ActionType.self, forKey: .type) {
        case .command:
            self = .command(
                source: try container.decode(GuardianCommandSource.self, forKey: .source),
                command: try container.decode(String.self, forKey: .command),
                cwd: try container.decode(String.self, forKey: .cwd)
            )
        case .execve:
            self = .execve(
                source: try container.decode(GuardianCommandSource.self, forKey: .source),
                program: try container.decode(String.self, forKey: .program),
                argv: try container.decode([String].self, forKey: .argv),
                cwd: try container.decode(String.self, forKey: .cwd)
            )
        case .applyPatch:
            self = .applyPatch(
                cwd: try container.decode(String.self, forKey: .cwd),
                files: try container.decode([String].self, forKey: .files)
            )
        case .networkAccess:
            self = .networkAccess(
                target: try container.decode(String.self, forKey: .target),
                host: try container.decode(String.self, forKey: .host),
                protocol: try container.decode(NetworkApprovalProtocol.self, forKey: .protocol),
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
            try container.encode(protocolValue, forKey: .protocol)
            try container.encode(port, forKey: .port)
        case let .mcpToolCall(server, toolName, connectorID, connectorName, toolTitle):
            try container.encode(ActionType.mcpToolCall, forKey: .type)
            try container.encode(server, forKey: .server)
            try container.encode(toolName, forKey: .toolName)
            try container.encodeIfPresent(connectorID, forKey: .connectorID)
            try container.encodeIfPresent(connectorName, forKey: .connectorName)
            try container.encodeIfPresent(toolTitle, forKey: .toolTitle)
        case let .requestPermissions(reason, permissions):
            try container.encode(ActionType.requestPermissions, forKey: .type)
            try container.encodeIfPresent(reason, forKey: .reason)
            try container.encode(permissions, forKey: .permissions)
        }
    }
}

public struct GuardianAssessmentEvent: Codable, Equatable, Sendable {
    public let id: String
    public let targetItemID: String?
    public let turnID: String
    public let startedAtMilliseconds: Int64
    public let completedAtMilliseconds: Int64?
    public let status: GuardianAssessmentStatus
    public let riskLevel: GuardianRiskLevel?
    public let userAuthorization: GuardianUserAuthorization?
    public let rationale: String?
    public let decisionSource: GuardianAssessmentDecisionSource?
    public let action: GuardianAssessmentAction

    private enum CodingKeys: String, CodingKey {
        case id
        case targetItemID = "target_item_id"
        case turnID = "turn_id"
        case startedAtMilliseconds = "started_at_ms"
        case completedAtMilliseconds = "completed_at_ms"
        case status
        case riskLevel = "risk_level"
        case userAuthorization = "user_authorization"
        case rationale
        case decisionSource = "decision_source"
        case action
    }

    public init(
        id: String,
        targetItemID: String? = nil,
        turnID: String = "",
        startedAtMilliseconds: Int64 = 0,
        completedAtMilliseconds: Int64? = nil,
        status: GuardianAssessmentStatus,
        riskLevel: GuardianRiskLevel? = nil,
        userAuthorization: GuardianUserAuthorization? = nil,
        rationale: String? = nil,
        decisionSource: GuardianAssessmentDecisionSource? = nil,
        action: GuardianAssessmentAction
    ) {
        self.id = id
        self.targetItemID = targetItemID
        self.turnID = turnID
        self.startedAtMilliseconds = startedAtMilliseconds
        self.completedAtMilliseconds = completedAtMilliseconds
        self.status = status
        self.riskLevel = riskLevel
        self.userAuthorization = userAuthorization
        self.rationale = rationale
        self.decisionSource = decisionSource
        self.action = action
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        targetItemID = try container.decodeIfPresent(String.self, forKey: .targetItemID)
        turnID = try container.decodeIfPresent(String.self, forKey: .turnID) ?? ""
        startedAtMilliseconds = try container.decodeIfPresent(Int64.self, forKey: .startedAtMilliseconds) ?? 0
        completedAtMilliseconds = try container.decodeIfPresent(Int64.self, forKey: .completedAtMilliseconds)
        status = try container.decode(GuardianAssessmentStatus.self, forKey: .status)
        riskLevel = try container.decodeIfPresent(GuardianRiskLevel.self, forKey: .riskLevel)
        userAuthorization = try container.decodeIfPresent(GuardianUserAuthorization.self, forKey: .userAuthorization)
        rationale = try container.decodeIfPresent(String.self, forKey: .rationale)
        decisionSource = try container.decodeIfPresent(GuardianAssessmentDecisionSource.self, forKey: .decisionSource)
        action = try container.decode(GuardianAssessmentAction.self, forKey: .action)
    }
}
