import Foundation

public enum SessionSource: Equatable, Sendable {
    case cli
    case vscode
    case exec
    case mcp
    case custom(String)
    case `internal`(InternalSessionSource)
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
        case let .custom(source):
            return source
        case let .internal(source):
            return "internal_\(source.description)"
        case let .subagent(source):
            return "subagent_\(source.description)"
        case .unknown:
            return "unknown"
        }
    }

    public var isInternal: Bool {
        if case .internal = self {
            return true
        }
        return false
    }

    public var isNonRootAgent: Bool {
        switch self {
        case .internal, .subagent:
            return true
        case .cli, .vscode, .exec, .mcp, .custom, .unknown:
            return false
        }
    }

    public var nickname: String? {
        guard case let .subagent(.threadSpawn(_, _, _, nickname, _)) = self else {
            return nil
        }
        return nickname
    }

    public var agentRole: String? {
        guard case let .subagent(.threadSpawn(_, _, _, _, role)) = self else {
            return nil
        }
        return role
    }

    public var agentPath: AgentPath? {
        guard case let .subagent(.threadSpawn(_, _, path, _, _)) = self else {
            return nil
        }
        return path
    }

    public static func fromStartupArg(_ value: String) throws -> SessionSource {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SessionSourceError("session source must not be empty")
        }

        let normalized = trimmed.lowercased()
        switch normalized {
        case "cli":
            return .cli
        case "vscode":
            return .vscode
        case "exec":
            return .exec
        case "mcp", "appserver", "app-server", "app_server":
            return .mcp
        case "unknown":
            return .unknown
        default:
            return .custom(normalized)
        }
    }

    /// Decode a persisted Rust session-source string and return its thread-spawn parent, if any.
    ///
    /// Rust first tries to parse the stored source as full JSON, then falls back to treating it as
    /// a plain session-source string. Matching that order keeps state backfills and imported
    /// rollout metadata from inventing graph edges for non-thread-spawn sources.
    public static func threadSpawnParentThreadID(fromPersistedSource source: String) -> ThreadId? {
        if let data = source.data(using: .utf8),
           let parsed = try? JSONDecoder().decode(SessionSource.self, from: data),
           case let .subagent(.threadSpawn(parentThreadID, _, _, _, _)) = parsed {
            return parentThreadID
        }

        let quoted = try? JSONEncoder().encode(source)
        if let quoted,
           let parsed = try? JSONDecoder().decode(SessionSource.self, from: quoted),
           case let .subagent(.threadSpawn(parentThreadID, _, _, _, _)) = parsed {
            return parentThreadID
        }

        return nil
    }

    public func restrictionProduct() -> Product? {
        switch self {
        case .custom(let source):
            return Product(sessionSourceName: source)
        case .cli, .vscode, .exec, .mcp, .unknown:
            return .codex
        case .internal, .subagent:
            return nil
        }
    }

    public func matchesProductRestriction(_ products: [Product]) -> Bool {
        products.isEmpty || restrictionProduct().map { products.contains($0) } == true
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
        case custom
        case `internal`
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
        guard container.allKeys.count <= 1 else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected externally tagged SessionSource object with exactly one tag"
                )
            )
        }
        if container.contains(.custom) {
            self = .custom(try container.decode(String.self, forKey: .custom))
        } else if container.contains(.internal) {
            self = .internal(try container.decode(InternalSessionSource.self, forKey: .internal))
        } else if container.contains(.subagent) {
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
        case let .custom(source):
            var container = encoder.container(keyedBy: TaggedKey.self)
            try container.encode(source, forKey: .custom)
        case let .internal(source):
            var container = encoder.container(keyedBy: TaggedKey.self)
            try container.encode(source, forKey: .internal)
        case let .subagent(source):
            var container = encoder.container(keyedBy: TaggedKey.self)
            try container.encode(source, forKey: .subagent)
        case .unknown:
            var container = encoder.singleValueContainer()
            try container.encode(UnitValue.unknown)
        }
    }
}

public struct SessionSourceError: Error, Equatable, CustomStringConvertible, Sendable {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}

public enum Product: String, Codable, Equatable, Sendable {
    case chatgpt
    case codex
    case atlas

    public var appPlatform: String {
        switch self {
        case .chatgpt:
            return "chat"
        case .codex:
            return "codex"
        case .atlas:
            return "atlas"
        }
    }

    public init?(sessionSourceName value: String) {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "chatgpt":
            self = .chatgpt
        case "codex":
            self = .codex
        case "atlas":
            self = .atlas
        default:
            return nil
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
        case "chatgpt", "CHATGPT":
            self = .chatgpt
        case "codex", "CODEX":
            self = .codex
        case "atlas", "ATLAS":
            self = .atlas
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown product: \(value)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum ThreadSource: String, Codable, Equatable, Sendable, CustomStringConvertible {
    case user
    case subagent
    case memoryConsolidation = "memory_consolidation"

    public var description: String {
        rawValue
    }
}

public enum InternalSessionSource: String, Codable, Equatable, Sendable, CustomStringConvertible {
    case memoryConsolidation = "memory_consolidation"

    public var description: String {
        rawValue
    }
}

public enum SubAgentSource: Equatable, Sendable {
    case review
    case compact
    case threadSpawn(
        parentThreadID: ThreadId,
        depth: Int32,
        agentPath: AgentPath? = nil,
        agentNickname: String? = nil,
        agentRole: String? = nil
    )
    case memoryConsolidation
    case other(String)

    public var description: String {
        switch self {
        case .review:
            return "review"
        case .compact:
            return "compact"
        case let .threadSpawn(parentThreadID, depth, _, _, _):
            return "thread_spawn_\(parentThreadID)_d\(depth)"
        case .memoryConsolidation:
            return "memory_consolidation"
        case let .other(label):
            return label
        }
    }
}

extension SubAgentSource: Codable {
    private enum UnitValue: String, Codable {
        case review
        case compact
        case memoryConsolidation = "memory_consolidation"
    }

    private enum TaggedKey: String, CodingKey {
        case threadSpawn = "thread_spawn"
        case other
    }

    private enum ThreadSpawnKey: String, CodingKey {
        case parentThreadID = "parent_thread_id"
        case depth
        case agentPath = "agent_path"
        case agentNickname = "agent_nickname"
        case agentRole = "agent_role"
        case agentType = "agent_type"
    }

    public init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let unit = try? single.decode(UnitValue.self) {
            switch unit {
            case .review:
                self = .review
            case .compact:
                self = .compact
            case .memoryConsolidation:
                self = .memoryConsolidation
            }
            return
        }

        let container = try decoder.container(keyedBy: TaggedKey.self)
        if container.contains(.threadSpawn) {
            let spawn = try container.nestedContainer(keyedBy: ThreadSpawnKey.self, forKey: .threadSpawn)
            self = .threadSpawn(
                parentThreadID: try spawn.decode(ThreadId.self, forKey: .parentThreadID),
                depth: try spawn.decode(Int32.self, forKey: .depth),
                agentPath: try spawn.decodeIfPresent(AgentPath.self, forKey: .agentPath),
                agentNickname: try spawn.decodeIfPresent(String.self, forKey: .agentNickname),
                agentRole: try Self.decodeAgentRole(from: spawn, codingPath: decoder.codingPath)
            )
        } else {
            self = .other(try container.decode(String.self, forKey: .other))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .review:
            var container = encoder.singleValueContainer()
            try container.encode(UnitValue.review)
        case .compact:
            var container = encoder.singleValueContainer()
            try container.encode(UnitValue.compact)
        case let .threadSpawn(parentThreadID, depth, agentPath, agentNickname, agentRole):
            var container = encoder.container(keyedBy: TaggedKey.self)
            var spawn = container.nestedContainer(keyedBy: ThreadSpawnKey.self, forKey: .threadSpawn)
            try spawn.encode(parentThreadID, forKey: .parentThreadID)
            try spawn.encode(depth, forKey: .depth)
            try spawn.encodeIfPresent(agentPath, forKey: .agentPath)
            try spawn.encodeIfPresent(agentNickname, forKey: .agentNickname)
            try spawn.encodeIfPresent(agentRole, forKey: .agentRole)
        case .memoryConsolidation:
            var container = encoder.singleValueContainer()
            try container.encode(UnitValue.memoryConsolidation)
        case let .other(label):
            var container = encoder.container(keyedBy: TaggedKey.self)
            try container.encode(label, forKey: .other)
        }
    }

    private static func decodeAgentRole(
        from container: KeyedDecodingContainer<ThreadSpawnKey>,
        codingPath: [CodingKey]
    ) throws -> String? {
        if container.contains(.agentRole), container.contains(.agentType) {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: codingPath + [TaggedKey.threadSpawn, ThreadSpawnKey.agentRole],
                    debugDescription: "duplicate field `agent_role`"
                )
            )
        }
        return try container.decodeIfPresent(String.self, forKey: .agentRole)
            ?? container.decodeIfPresent(String.self, forKey: .agentType)
    }
}

public enum CodexRequestHeaders {
    public static let installationIDHeaderName = "x-codex-installation-id"
    public static let windowIDHeaderName = "x-codex-window-id"
    public static let parentThreadIDHeaderName = "x-codex-parent-thread-id"
    public static let subagentHeaderName = "x-openai-subagent"
    public static let turnMetadataHeaderName = "x-codex-turn-metadata"

    public static func sessionHeaders(sessionID: String?, threadID: String?) -> [String: String] {
        var headers: [String: String] = [:]
        if let sessionID {
            headers["session_id"] = sessionID
            headers["session-id"] = sessionID
        }
        if let threadID {
            headers["thread_id"] = threadID
            headers["thread-id"] = threadID
        }
        return headers
    }

    public static func conversationHeaders(conversationID: String?) -> [String: String] {
        var headers = sessionHeaders(sessionID: conversationID, threadID: conversationID)
        if let conversationID {
            headers["conversation_id"] = conversationID
        }
        return headers
    }

    public static func filterForProvider(_ headers: [String: String], provider: APIProvider) -> [String: String] {
        guard provider.name == ModelProviderInfo.amazonBedrockProviderName else {
            return headers
        }
        return headers.filter { name, _ in !name.contains("_") }
    }

    public static func subagentHeader(for source: SessionSource?) -> String? {
        switch source {
        case let .subagent(subagent):
            switch subagent {
            case .review, .compact, .memoryConsolidation, .other:
                return subagent.description
            case .threadSpawn:
                return "collab_spawn"
            }
        case .internal(.memoryConsolidation):
            return "memory_consolidation"
        case .cli, .vscode, .exec, .mcp, .custom, .unknown, nil:
            return nil
        }
    }

    public static func parentThreadIDHeader(for source: SessionSource?) -> String? {
        guard case let .subagent(.threadSpawn(parentThreadID, _, _, _, _)) = source else {
            return nil
        }
        return parentThreadID.description
    }

    public static func isValidHeaderValue(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { scalar in
            scalar.value == 0x09 || (0x20...0x7E).contains(scalar.value)
        }
    }

    public static func webSocketClientMetadata(
        installationID: String,
        threadID: ThreadId,
        windowGeneration: Int,
        sessionSource: SessionSource,
        turnMetadataHeader: String? = nil
    ) -> [String: String] {
        var metadata = [
            installationIDHeaderName: installationID,
            windowIDHeaderName: "\(threadID):\(windowGeneration)"
        ]
        if let subagent = subagentHeader(for: sessionSource) {
            metadata[subagentHeaderName] = subagent
        }
        if let parentThreadID = parentThreadIDHeader(for: sessionSource) {
            metadata[parentThreadIDHeaderName] = parentThreadID
        }
        if let turnMetadataHeader,
           isValidHeaderValue(turnMetadataHeader) {
            metadata[turnMetadataHeaderName] = turnMetadataHeader
        }
        return metadata
    }
}
