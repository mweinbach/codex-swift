import Foundation

public struct GranularApprovalConfig: Codable, Equatable, Sendable {
    public let sandboxApproval: Bool
    public let rules: Bool
    public let skillApproval: Bool
    public let requestPermissions: Bool
    public let mcpElicitations: Bool

    private enum CodingKeys: String, CodingKey {
        case sandboxApproval = "sandbox_approval"
        case rules
        case skillApproval = "skill_approval"
        case requestPermissions = "request_permissions"
        case mcpElicitations = "mcp_elicitations"
    }

    public init(
        sandboxApproval: Bool,
        rules: Bool,
        skillApproval: Bool = false,
        requestPermissions: Bool = false,
        mcpElicitations: Bool
    ) {
        self.sandboxApproval = sandboxApproval
        self.rules = rules
        self.skillApproval = skillApproval
        self.requestPermissions = requestPermissions
        self.mcpElicitations = mcpElicitations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sandboxApproval = try container.decode(Bool.self, forKey: .sandboxApproval)
        rules = try container.decode(Bool.self, forKey: .rules)
        skillApproval = try container.decodeIfPresent(Bool.self, forKey: .skillApproval) ?? false
        requestPermissions = try container.decodeIfPresent(Bool.self, forKey: .requestPermissions) ?? false
        mcpElicitations = try container.decode(Bool.self, forKey: .mcpElicitations)
    }

    public var allowsSandboxApproval: Bool {
        sandboxApproval
    }

    public var allowsRulesApproval: Bool {
        rules
    }

    public var allowsSkillApproval: Bool {
        skillApproval
    }

    public var allowsRequestPermissions: Bool {
        requestPermissions
    }

    public var allowsMcpElicitations: Bool {
        mcpElicitations
    }
}

public enum AskForApproval: Equatable, RawRepresentable, Sendable {
    public typealias RawValue = String

    case unlessTrusted
    case onFailure
    case onRequest
    case granular(GranularApprovalConfig)
    case never

    public init?(rawValue: String) {
        switch rawValue {
        case "untrusted":
            self = .unlessTrusted
        case "on-failure":
            self = .onFailure
        case "on-request":
            self = .onRequest
        case "never":
            self = .never
        default:
            return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .unlessTrusted:
            return "untrusted"
        case .onFailure:
            return "on-failure"
        case .onRequest:
            return "on-request"
        case .granular:
            return "granular"
        case .never:
            return "never"
        }
    }
}

extension AskForApproval: CustomStringConvertible {
    public var description: String {
        rawValue
    }
}

extension AskForApproval: Codable {
    private enum CodingKeys: String, CodingKey {
        case granular
    }

    public init(from decoder: Decoder) throws {
        let singleValue = try decoder.singleValueContainer()
        if let value = try? singleValue.decode(String.self) {
            guard let mode = AskForApproval(rawValue: value) else {
                throw DecodingError.dataCorruptedError(
                    in: singleValue,
                    debugDescription: "Unknown approval policy: \(value)"
                )
            }
            self = mode
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.allKeys == [.granular] else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected exactly one AskForApproval object variant"
                )
            )
        }
        self = .granular(try container.decode(GranularApprovalConfig.self, forKey: .granular))
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .unlessTrusted, .onFailure, .onRequest, .never:
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        case let .granular(config):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(config, forKey: .granular)
        }
    }
}

public enum ApprovalsReviewer: Equatable, Sendable {
    case user
    case autoReview

    public var rustDebugDescription: String {
        switch self {
        case .user:
            "User"
        case .autoReview:
            "AutoReview"
        }
    }

    public var appServerRawValue: String {
        switch self {
        case .user:
            "user"
        case .autoReview:
            "guardian_subagent"
        }
    }
}

extension ApprovalsReviewer: DefaultValue {
    public static var defaultValue: ApprovalsReviewer { .user }
}

extension ApprovalsReviewer: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        switch try container.decode(String.self) {
        case "user":
            self = .user
        case "guardian_subagent", "auto_review":
            self = .autoReview
        case let value:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown approvals reviewer: \(value)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .user:
            try container.encode("user")
        case .autoReview:
            try container.encode("guardian_subagent")
        }
    }
}

public enum ApprovalModeCLIArgument: String, CaseIterable, Equatable, Sendable {
    case untrusted
    case onFailure = "on-failure"
    case onRequest = "on-request"
    case never

    public var approvalMode: AskForApproval {
        switch self {
        case .untrusted:
            return .unlessTrusted
        case .onFailure:
            return .onFailure
        case .onRequest:
            return .onRequest
        case .never:
            return .never
        }
    }
}
