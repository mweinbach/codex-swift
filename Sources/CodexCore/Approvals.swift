import Foundation

public struct ExecPolicyAmendment: Equatable, Codable, Sendable {
    public let command: [String]

    public init(command: [String]) {
        self.command = command
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.command = try container.decode([String].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(command)
    }
}

public enum RequestID: Equatable, Codable, Sendable {
    case string(String)
    case integer(Int64)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        self = .integer(try container.decode(Int64.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .integer(value):
            try container.encode(value)
        }
    }
}

public struct ExecApprovalRequestEvent: Equatable, Codable, Sendable {
    public let callID: String
    public let turnID: String
    public let command: [String]
    public let cwd: String
    public let reason: String?
    public let proposedExecPolicyAmendment: ExecPolicyAmendment?
    public let parsedCmd: [ParsedCommand]

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case turnID = "turn_id"
        case command
        case cwd
        case reason
        case proposedExecPolicyAmendment = "proposed_execpolicy_amendment"
        case parsedCmd = "parsed_cmd"
    }

    public init(
        callID: String,
        turnID: String = "",
        command: [String],
        cwd: String,
        reason: String? = nil,
        proposedExecPolicyAmendment: ExecPolicyAmendment? = nil,
        parsedCmd: [ParsedCommand]
    ) {
        self.callID = callID
        self.turnID = turnID
        self.command = command
        self.cwd = cwd
        self.reason = reason
        self.proposedExecPolicyAmendment = proposedExecPolicyAmendment
        self.parsedCmd = parsedCmd
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.callID = try container.decode(String.self, forKey: .callID)
        self.turnID = try container.decodeIfPresent(String.self, forKey: .turnID) ?? ""
        self.command = try container.decode([String].self, forKey: .command)
        self.cwd = try container.decode(String.self, forKey: .cwd)
        self.reason = try container.decodeIfPresent(String.self, forKey: .reason)
        self.proposedExecPolicyAmendment = try container.decodeIfPresent(
            ExecPolicyAmendment.self,
            forKey: .proposedExecPolicyAmendment
        )
        self.parsedCmd = try container.decode([ParsedCommand].self, forKey: .parsedCmd)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(callID, forKey: .callID)
        try container.encode(turnID, forKey: .turnID)
        try container.encode(command, forKey: .command)
        try container.encode(cwd, forKey: .cwd)
        try container.encodeIfPresent(reason, forKey: .reason)
        try container.encodeIfPresent(proposedExecPolicyAmendment, forKey: .proposedExecPolicyAmendment)
        try container.encode(parsedCmd, forKey: .parsedCmd)
    }
}

public struct ElicitationRequestEvent: Equatable, Codable, Sendable {
    public let serverName: String
    public let id: RequestID
    public let message: String

    private enum CodingKeys: String, CodingKey {
        case serverName = "server_name"
        case id
        case message
    }

    public init(serverName: String, id: RequestID, message: String) {
        self.serverName = serverName
        self.id = id
        self.message = message
    }
}

public enum ElicitationAction: String, Codable, Equatable, Sendable {
    case accept
    case decline
    case cancel
}

public struct ApplyPatchApprovalRequestEvent: Equatable, Codable, Sendable {
    public let callID: String
    public let turnID: String
    public let changes: [String: FileChange]
    public let reason: String?
    public let grantRoot: String?

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case turnID = "turn_id"
        case changes
        case reason
        case grantRoot = "grant_root"
    }

    public init(
        callID: String,
        turnID: String = "",
        changes: [String: FileChange],
        reason: String? = nil,
        grantRoot: String? = nil
    ) {
        self.callID = callID
        self.turnID = turnID
        self.changes = changes
        self.reason = reason
        self.grantRoot = grantRoot
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.callID = try container.decode(String.self, forKey: .callID)
        self.turnID = try container.decodeIfPresent(String.self, forKey: .turnID) ?? ""
        self.changes = try container.decode([String: FileChange].self, forKey: .changes)
        self.reason = try container.decodeIfPresent(String.self, forKey: .reason)
        self.grantRoot = try container.decodeIfPresent(String.self, forKey: .grantRoot)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(callID, forKey: .callID)
        try container.encode(turnID, forKey: .turnID)
        try container.encode(changes, forKey: .changes)
        try container.encodeIfPresent(reason, forKey: .reason)
        try container.encodeIfPresent(grantRoot, forKey: .grantRoot)
    }
}

public enum ReviewDecision: Equatable, Codable, Sendable {
    case approved
    case approvedExecpolicyAmendment(proposedExecpolicyAmendment: ExecPolicyAmendment)
    case approvedForSession
    case denied
    case abort

    public static let `default`: ReviewDecision = .denied

    private enum UnitDecision: String, Codable {
        case approved
        case approvedForSession = "approved_for_session"
        case denied
        case abort
    }

    private enum CodingKeys: String, CodingKey {
        case approvedExecpolicyAmendment = "approved_execpolicy_amendment"
    }

    private enum AmendmentKeys: String, CodingKey {
        case proposedExecpolicyAmendment = "proposed_execpolicy_amendment"
    }

    public init(from decoder: Decoder) throws {
        if let unit = try? UnitDecision(from: decoder) {
            switch unit {
            case .approved:
                self = .approved
            case .approvedForSession:
                self = .approvedForSession
            case .denied:
                self = .denied
            case .abort:
                self = .abort
            }
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.approvedExecpolicyAmendment) {
            let nested = try container.nestedContainer(
                keyedBy: AmendmentKeys.self,
                forKey: .approvedExecpolicyAmendment
            )
            self = .approvedExecpolicyAmendment(
                proposedExecpolicyAmendment: try nested.decode(
                    ExecPolicyAmendment.self,
                    forKey: .proposedExecpolicyAmendment
                )
            )
            return
        }

        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Unsupported review decision"
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .approved:
            try UnitDecision.approved.encode(to: encoder)
        case let .approvedExecpolicyAmendment(amendment):
            var container = encoder.container(keyedBy: CodingKeys.self)
            var nested = container.nestedContainer(
                keyedBy: AmendmentKeys.self,
                forKey: .approvedExecpolicyAmendment
            )
            try nested.encode(amendment, forKey: .proposedExecpolicyAmendment)
        case .approvedForSession:
            try UnitDecision.approvedForSession.encode(to: encoder)
        case .denied:
            try UnitDecision.denied.encode(to: encoder)
        case .abort:
            try UnitDecision.abort.encode(to: encoder)
        }
    }
}
