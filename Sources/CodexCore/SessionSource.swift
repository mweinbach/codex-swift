import Foundation

public enum SessionSource: Equatable, Sendable {
    case cli
    case vscode
    case exec
    case mcp
    case subagent(SubAgentSource)
    case unknown

    public static let `default`: SessionSource = .vscode

    public var description: String {
        switch self {
        case .cli:
            return "cli"
        case .vscode:
            return "vscode"
        case .exec:
            return "exec"
        case .mcp:
            return "mcp"
        case let .subagent(source):
            return "subagent_\(source.description)"
        case .unknown:
            return "unknown"
        }
    }
}

extension SessionSource: Codable {
    private enum UnitValue: String, Codable {
        case cli
        case vscode
        case exec
        case mcp
        case unknown
    }

    private enum TaggedKey: String, CodingKey {
        case subagent
    }

    public init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let unit = try? single.decode(UnitValue.self) {
            switch unit {
            case .cli:
                self = .cli
            case .vscode:
                self = .vscode
            case .exec:
                self = .exec
            case .mcp:
                self = .mcp
            case .unknown:
                self = .unknown
            }
            return
        }

        if let raw = try? single.decode(String.self) {
            switch raw {
            case "Cli":
                self = .cli
            case "VSCode":
                self = .vscode
            case "Exec":
                self = .exec
            case "Mcp":
                self = .mcp
            default:
                self = .unknown
            }
            return
        }

        let container = try decoder.container(keyedBy: TaggedKey.self)
        if container.contains(.subagent) {
            self = .subagent(try container.decode(SubAgentSource.self, forKey: .subagent))
        } else {
            self = .unknown
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .cli:
            var container = encoder.singleValueContainer()
            try container.encode(UnitValue.cli)
        case .vscode:
            var container = encoder.singleValueContainer()
            try container.encode(UnitValue.vscode)
        case .exec:
            var container = encoder.singleValueContainer()
            try container.encode(UnitValue.exec)
        case .mcp:
            var container = encoder.singleValueContainer()
            try container.encode(UnitValue.mcp)
        case let .subagent(source):
            var container = encoder.container(keyedBy: TaggedKey.self)
            try container.encode(source, forKey: .subagent)
        case .unknown:
            var container = encoder.singleValueContainer()
            try container.encode(UnitValue.unknown)
        }
    }
}

public enum SubAgentSource: Equatable, Sendable {
    case review
    case compact
    case other(String)

    public var description: String {
        switch self {
        case .review:
            return "review"
        case .compact:
            return "compact"
        case let .other(label):
            return label
        }
    }
}

extension SubAgentSource: Codable {
    private enum UnitValue: String, Codable {
        case review
        case compact
    }

    private enum TaggedKey: String, CodingKey {
        case other
    }

    public init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let unit = try? single.decode(UnitValue.self) {
            switch unit {
            case .review:
                self = .review
            case .compact:
                self = .compact
            }
            return
        }

        let container = try decoder.container(keyedBy: TaggedKey.self)
        self = .other(try container.decode(String.self, forKey: .other))
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .review:
            var container = encoder.singleValueContainer()
            try container.encode(UnitValue.review)
        case .compact:
            var container = encoder.singleValueContainer()
            try container.encode(UnitValue.compact)
        case let .other(label):
            var container = encoder.container(keyedBy: TaggedKey.self)
            try container.encode(label, forKey: .other)
        }
    }
}

public enum CodexRequestHeaders {
    public static func conversationHeaders(conversationID: String?) -> [String: String] {
        guard let conversationID else {
            return [:]
        }

        return [
            "conversation_id": conversationID,
            "thread_id": conversationID,
            "thread-id": conversationID,
            "session_id": conversationID,
            "session-id": conversationID
        ]
    }

    public static func subagentHeader(for source: SessionSource?) -> String? {
        guard case let .subagent(subagent)? = source else {
            return nil
        }
        return subagent.description
    }
}
