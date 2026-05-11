import Foundation

public struct SessionMeta: Equatable, Codable, Sendable {
    public let id: ConversationId
    public let forkedFromID: ConversationId?
    public let timestamp: String
    public let cwd: String
    public let originator: String
    public let cliVersion: String
    public let instructions: String?
    public let source: SessionSource
    public let threadSource: ThreadSource?
    public let agentNickname: String?
    public let agentRole: String?
    public let agentPath: String?
    public let modelProvider: String?
    public let baseInstructions: BaseInstructions?
    public let dynamicTools: [DynamicToolSpec]?
    public let memoryMode: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case forkedFromID = "forked_from_id"
        case timestamp
        case cwd
        case originator
        case cliVersion = "cli_version"
        case instructions
        case source
        case threadSource = "thread_source"
        case agentNickname = "agent_nickname"
        case agentRole = "agent_role"
        case agentType = "agent_type"
        case agentPath = "agent_path"
        case modelProvider = "model_provider"
        case baseInstructions = "base_instructions"
        case dynamicTools = "dynamic_tools"
        case memoryMode = "memory_mode"
    }

    public init(
        id: ConversationId,
        forkedFromID: ConversationId? = nil,
        timestamp: String,
        cwd: String,
        originator: String,
        cliVersion: String,
        instructions: String? = nil,
        source: SessionSource = .default,
        threadSource: ThreadSource? = nil,
        agentNickname: String? = nil,
        agentRole: String? = nil,
        agentPath: String? = nil,
        modelProvider: String? = nil,
        baseInstructions: BaseInstructions? = nil,
        dynamicTools: [DynamicToolSpec]? = nil,
        memoryMode: String? = nil
    ) {
        self.id = id
        self.forkedFromID = forkedFromID
        self.timestamp = timestamp
        self.cwd = cwd
        self.originator = originator
        self.cliVersion = cliVersion
        self.instructions = instructions
        self.source = source
        self.threadSource = threadSource
        self.agentNickname = agentNickname
        self.agentRole = agentRole
        self.agentPath = agentPath
        self.modelProvider = modelProvider
        self.baseInstructions = baseInstructions
        self.dynamicTools = dynamicTools
        self.memoryMode = memoryMode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(ConversationId.self, forKey: .id)
        self.forkedFromID = try container.decodeIfPresent(ConversationId.self, forKey: .forkedFromID)
        self.timestamp = try container.decode(String.self, forKey: .timestamp)
        self.cwd = try container.decode(String.self, forKey: .cwd)
        self.originator = try container.decode(String.self, forKey: .originator)
        self.cliVersion = try container.decode(String.self, forKey: .cliVersion)
        self.instructions = try container.decodeIfPresent(String.self, forKey: .instructions)
        self.source = try container.decodeIfPresent(SessionSource.self, forKey: .source) ?? .default
        self.threadSource = try container.decodeIfPresent(ThreadSource.self, forKey: .threadSource)
        self.agentNickname = try container.decodeIfPresent(String.self, forKey: .agentNickname)
        self.agentRole = try container.decodeIfPresent(String.self, forKey: .agentRole)
            ?? container.decodeIfPresent(String.self, forKey: .agentType)
        self.agentPath = try container.decodeIfPresent(String.self, forKey: .agentPath)
        self.modelProvider = try container.decodeIfPresent(String.self, forKey: .modelProvider)
        self.baseInstructions = try container.decodeIfPresent(BaseInstructions.self, forKey: .baseInstructions)
        self.dynamicTools = try container.decodeIfPresent([DynamicToolSpec].self, forKey: .dynamicTools)
        self.memoryMode = try container.decodeIfPresent(String.self, forKey: .memoryMode)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(forkedFromID, forKey: .forkedFromID)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(cwd, forKey: .cwd)
        try container.encode(originator, forKey: .originator)
        try container.encode(cliVersion, forKey: .cliVersion)
        try container.encode(instructions, forKey: .instructions)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(threadSource, forKey: .threadSource)
        try container.encodeIfPresent(agentNickname, forKey: .agentNickname)
        try container.encodeIfPresent(agentRole, forKey: .agentRole)
        try container.encodeIfPresent(agentPath, forKey: .agentPath)
        try container.encode(modelProvider, forKey: .modelProvider)
        try container.encode(baseInstructions, forKey: .baseInstructions)
        try container.encodeIfPresent(dynamicTools, forKey: .dynamicTools)
        try container.encodeIfPresent(memoryMode, forKey: .memoryMode)
    }
}

public struct BaseInstructions: Equatable, Codable, Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

public struct GitInfo: Equatable, Codable, Sendable {
    public let commitHash: String?
    public let branch: String?
    public let repositoryURL: String?

    private enum CodingKeys: String, CodingKey {
        case commitHash = "commit_hash"
        case branch
        case repositoryURL = "repository_url"
    }

    public init(commitHash: String? = nil, branch: String? = nil, repositoryURL: String? = nil) {
        self.commitHash = commitHash
        self.branch = branch
        self.repositoryURL = repositoryURL
    }
}

public struct SessionMetaLine: Equatable, Codable, Sendable {
    public let meta: SessionMeta
    public let git: GitInfo?

    private enum CodingKeys: String, CodingKey {
        case git
    }

    public init(meta: SessionMeta, git: GitInfo? = nil) {
        self.meta = meta
        self.git = git
    }

    public init(from decoder: Decoder) throws {
        self.meta = try SessionMeta(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.git = try container.decodeIfPresent(GitInfo.self, forKey: .git)
    }

    public func encode(to encoder: Encoder) throws {
        try meta.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(git, forKey: .git)
    }
}

public struct CompactedItem: Equatable, Codable, Sendable {
    public let message: String
    public let replacementHistory: [ResponseItem]?

    private enum CodingKeys: String, CodingKey {
        case message
        case replacementHistory = "replacement_history"
    }

    public init(message: String, replacementHistory: [ResponseItem]? = nil) {
        self.message = message
        self.replacementHistory = replacementHistory
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.message = try container.decode(String.self, forKey: .message)

        guard let rawHistory = try container.decodeIfPresent([JSONValue].self, forKey: .replacementHistory) else {
            self.replacementHistory = nil
            return
        }

        self.replacementHistory = try rawHistory
            .filter { !Self.isLegacyGhostSnapshot($0) }
            .map { rawItem in
                let data = try JSONEncoder().encode(rawItem)
                return try JSONDecoder().decode(ResponseItem.self, from: data)
            }
    }

    private static func isLegacyGhostSnapshot(_ value: JSONValue) -> Bool {
        guard case let .object(fields) = value,
              fields["type"] == .string("ghost_snapshot")
        else {
            return false
        }
        return true
    }
}

public struct ConversationPathResponseEvent: Equatable, Codable, Sendable {
    public let conversationID: ConversationId
    public let path: String

    private enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id"
        case path
    }

    public init(conversationID: ConversationId, path: String) {
        self.conversationID = conversationID
        self.path = path
    }
}

public struct TurnContextNetworkItem: Equatable, Codable, Sendable {
    public let allowedDomains: [String]
    public let deniedDomains: [String]

    private enum CodingKeys: String, CodingKey {
        case allowedDomains = "allowed_domains"
        case deniedDomains = "denied_domains"
    }

    public init(allowedDomains: [String], deniedDomains: [String]) {
        self.allowedDomains = allowedDomains
        self.deniedDomains = deniedDomains
    }
}

public struct TurnContextItem: Equatable, Codable, Sendable {
    public let turnID: String?
    public let traceID: String?
    public let cwd: String
    public let currentDate: String?
    public let timezone: String?
    public let approvalPolicy: AskForApproval
    public let sandboxPolicy: SandboxPolicy
    public let permissionProfile: PermissionProfile?
    public let activePermissionProfile: ActivePermissionProfile?
    public let network: TurnContextNetworkItem?
    public let fileSystemSandboxPolicy: FileSystemSandboxPolicy?
    public let model: String
    public let personality: Personality?
    public let collaborationMode: CollaborationMode?
    public let realtimeActive: Bool?
    public let effort: ReasoningEffort?
    public let summary: ReasoningSummary
    public let userInstructions: String?
    public let developerInstructions: String?
    public let finalOutputJSONSchema: JSONValue?
    public let truncationPolicy: TruncationPolicy?

    private enum CodingKeys: String, CodingKey {
        case turnID = "turn_id"
        case traceID = "trace_id"
        case cwd
        case currentDate = "current_date"
        case timezone
        case approvalPolicy = "approval_policy"
        case sandboxPolicy = "sandbox_policy"
        case permissionProfile = "permission_profile"
        case activePermissionProfile = "active_permission_profile"
        case network
        case fileSystemSandboxPolicy = "file_system_sandbox_policy"
        case model
        case personality
        case collaborationMode = "collaboration_mode"
        case realtimeActive = "realtime_active"
        case effort
        case summary
        case userInstructions = "user_instructions"
        case developerInstructions = "developer_instructions"
        case finalOutputJSONSchema = "final_output_json_schema"
        case truncationPolicy = "truncation_policy"
    }

    public init(
        turnID: String? = nil,
        traceID: String? = nil,
        cwd: String,
        currentDate: String? = nil,
        timezone: String? = nil,
        approvalPolicy: AskForApproval,
        sandboxPolicy: SandboxPolicy,
        permissionProfile: PermissionProfile? = nil,
        activePermissionProfile: ActivePermissionProfile? = nil,
        network: TurnContextNetworkItem? = nil,
        fileSystemSandboxPolicy: FileSystemSandboxPolicy? = nil,
        model: String,
        personality: Personality? = nil,
        collaborationMode: CollaborationMode? = nil,
        realtimeActive: Bool? = nil,
        effort: ReasoningEffort? = nil,
        summary: ReasoningSummary,
        userInstructions: String? = nil,
        developerInstructions: String? = nil,
        finalOutputJSONSchema: JSONValue? = nil,
        truncationPolicy: TruncationPolicy? = nil
    ) {
        self.turnID = turnID
        self.traceID = traceID
        self.cwd = cwd
        self.currentDate = currentDate
        self.timezone = timezone
        self.approvalPolicy = approvalPolicy
        self.sandboxPolicy = sandboxPolicy
        self.permissionProfile = permissionProfile
        self.activePermissionProfile = activePermissionProfile
        self.network = network
        self.fileSystemSandboxPolicy = fileSystemSandboxPolicy
        self.model = model
        self.personality = personality
        self.collaborationMode = collaborationMode
        self.realtimeActive = realtimeActive
        self.effort = effort
        self.summary = summary
        self.userInstructions = userInstructions
        self.developerInstructions = developerInstructions
        self.finalOutputJSONSchema = finalOutputJSONSchema
        self.truncationPolicy = truncationPolicy
    }

    public init(
        cwd: String,
        approvalPolicy: AskForApproval,
        sandboxPolicy: SandboxPolicy,
        model: String,
        effort: ReasoningEffort? = nil,
        summary: ReasoningSummary,
        userInstructions: String? = nil,
        developerInstructions: String? = nil,
        finalOutputJSONSchema: JSONValue? = nil,
        truncationPolicy: TruncationPolicy? = nil
    ) {
        self.init(
            turnID: nil,
            traceID: nil,
            cwd: cwd,
            currentDate: nil,
            timezone: nil,
            approvalPolicy: approvalPolicy,
            sandboxPolicy: sandboxPolicy,
            permissionProfile: nil,
            activePermissionProfile: nil,
            network: nil,
            fileSystemSandboxPolicy: nil,
            model: model,
            personality: nil,
            collaborationMode: nil,
            realtimeActive: nil,
            effort: effort,
            summary: summary,
            userInstructions: userInstructions,
            developerInstructions: developerInstructions,
            finalOutputJSONSchema: finalOutputJSONSchema,
            truncationPolicy: truncationPolicy
        )
    }

    public var effectivePermissionProfile: PermissionProfile {
        if let permissionProfile {
            return permissionProfile
        }
        if let fileSystemSandboxPolicy {
            return PermissionProfile.fromRuntimePermissionsWithEnforcement(
                SandboxEnforcement.fromLegacySandboxPolicy(sandboxPolicy),
                fileSystem: fileSystemSandboxPolicy,
                network: NetworkSandboxPolicy.fromLegacySandboxPolicy(sandboxPolicy)
            )
        }
        return PermissionProfile.fromLegacySandboxPolicy(sandboxPolicy)
    }
}

public enum RolloutRecordItem: Equatable, Sendable {
    case sessionMeta(SessionMetaLine)
    case responseItem(ResponseItem)
    case compacted(CompactedItem)
    case turnContext(TurnContextItem)
    case eventMsg(EventMessage)

    private enum CodingKeys: String, CodingKey {
        case type
        case payload
    }

    private enum ItemType: String, Codable {
        case sessionMeta = "session_meta"
        case responseItem = "response_item"
        case compacted
        case turnContext = "turn_context"
        case eventMsg = "event_msg"
    }

    public var eventMessage: EventMessage? {
        guard case let .eventMsg(event) = self else {
            return nil
        }
        return event
    }
}

extension RolloutRecordItem: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ItemType.self, forKey: .type) {
        case .sessionMeta:
            self = .sessionMeta(try container.decode(SessionMetaLine.self, forKey: .payload))
        case .responseItem:
            self = .responseItem(try container.decode(ResponseItem.self, forKey: .payload))
        case .compacted:
            self = .compacted(try container.decode(CompactedItem.self, forKey: .payload))
        case .turnContext:
            self = .turnContext(try container.decode(TurnContextItem.self, forKey: .payload))
        case .eventMsg:
            self = .eventMsg(try container.decode(EventMessage.self, forKey: .payload))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .sessionMeta(item):
            try container.encode(ItemType.sessionMeta, forKey: .type)
            try container.encode(item, forKey: .payload)
        case let .responseItem(item):
            try container.encode(ItemType.responseItem, forKey: .type)
            try container.encode(item, forKey: .payload)
        case let .compacted(item):
            try container.encode(ItemType.compacted, forKey: .type)
            try container.encode(item, forKey: .payload)
        case let .turnContext(item):
            try container.encode(ItemType.turnContext, forKey: .type)
            try container.encode(item, forKey: .payload)
        case let .eventMsg(item):
            try container.encode(ItemType.eventMsg, forKey: .type)
            try container.encode(item, forKey: .payload)
        }
    }
}

public struct RolloutLine: Equatable, Codable, Sendable {
    public let timestamp: String
    public let item: RolloutRecordItem

    private enum CodingKeys: String, CodingKey {
        case timestamp
    }

    public init(timestamp: String, item: RolloutRecordItem) {
        self.timestamp = timestamp
        self.item = item
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.timestamp = try container.decode(String.self, forKey: .timestamp)
        self.item = try RolloutRecordItem(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try item.encode(to: encoder)
    }
}

public struct ResumedHistory: Equatable, Codable, Sendable {
    public let conversationID: ConversationId
    public let history: [RolloutRecordItem]
    public let rolloutPath: String?

    private enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id"
        case history
        case rolloutPath = "rollout_path"
    }

    public init(conversationID: ConversationId, history: [RolloutRecordItem], rolloutPath: String?) {
        self.conversationID = conversationID
        self.history = history
        self.rolloutPath = rolloutPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        conversationID = try container.decode(ConversationId.self, forKey: .conversationID)
        history = try container.decode([RolloutRecordItem].self, forKey: .history)
        rolloutPath = try container.decodeIfPresent(String.self, forKey: .rolloutPath)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(conversationID, forKey: .conversationID)
        try container.encode(history, forKey: .history)
        try container.encode(rolloutPath, forKey: .rolloutPath)
    }
}

public enum InitialHistory: Equatable, Sendable {
    case new
    case cleared
    case resumed(ResumedHistory)
    case forked([RolloutRecordItem])

    private enum VariantKey: String, CodingKey {
        case resumed = "Resumed"
        case forked = "Forked"
    }

    public var rolloutItems: [RolloutRecordItem] {
        switch self {
        case .new, .cleared:
            return []
        case let .resumed(resumed):
            return resumed.history
        case let .forked(items):
            return items
        }
    }

    public var eventMessages: [EventMessage]? {
        switch self {
        case .new, .cleared:
            return nil
        case let .resumed(resumed):
            return resumed.history.compactMap(\.eventMessage)
        case let .forked(items):
            return items.compactMap(\.eventMessage)
        }
    }

    public var dynamicTools: [DynamicToolSpec]? {
        switch self {
        case .new, .cleared:
            return nil
        case let .resumed(resumed):
            return Self.firstDynamicTools(in: resumed.history)
        case let .forked(items):
            return Self.firstDynamicTools(in: items)
        }
    }

    private static func firstDynamicTools(in items: [RolloutRecordItem]) -> [DynamicToolSpec]? {
        items.compactMap { item -> [DynamicToolSpec]? in
            guard case let .sessionMeta(metaLine) = item else {
                return nil
            }
            return metaLine.meta.dynamicTools
        }.first
    }
}

extension InitialHistory: Codable {
    public init(from decoder: Decoder) throws {
        if let value = try? decoder.singleValueContainer().decode(String.self) {
            switch value {
            case "New":
                self = .new
                return
            case "Cleared":
                self = .cleared
                return
            default:
                break
            }
        }

        let container = try decoder.container(keyedBy: VariantKey.self)
        if container.contains(.resumed) {
            self = .resumed(try container.decode(ResumedHistory.self, forKey: .resumed))
            return
        }
        if container.contains(.forked) {
            self = .forked(try container.decode([RolloutRecordItem].self, forKey: .forked))
            return
        }

        throw DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown InitialHistory variant")
        )
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .new:
            var container = encoder.singleValueContainer()
            try container.encode("New")
        case .cleared:
            var container = encoder.singleValueContainer()
            try container.encode("Cleared")
        case let .resumed(history):
            var container = encoder.container(keyedBy: VariantKey.self)
            try container.encode(history, forKey: .resumed)
        case let .forked(items):
            var container = encoder.container(keyedBy: VariantKey.self)
            try container.encode(items, forKey: .forked)
        }
    }
}
