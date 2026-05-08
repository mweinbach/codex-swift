import Foundation

public enum HookEventName: String, Codable, CaseIterable, Equatable, Sendable {
    case preToolUse = "pre_tool_use"
    case permissionRequest = "permission_request"
    case postToolUse = "post_tool_use"
    case preCompact = "pre_compact"
    case postCompact = "post_compact"
    case sessionStart = "session_start"
    case userPromptSubmit = "user_prompt_submit"
    case stop

    public var configLabel: String {
        switch self {
        case .preToolUse: return "PreToolUse"
        case .permissionRequest: return "PermissionRequest"
        case .postToolUse: return "PostToolUse"
        case .preCompact: return "PreCompact"
        case .postCompact: return "PostCompact"
        case .sessionStart: return "SessionStart"
        case .userPromptSubmit: return "UserPromptSubmit"
        case .stop: return "Stop"
        }
    }
}

public enum HookHandlerType: String, Codable, Equatable, Sendable {
    case command
    case prompt
    case agent
}

public enum HookExecutionMode: String, Codable, Equatable, Sendable {
    case sync
    case `async`
}

public enum HookScope: String, Codable, Equatable, Sendable {
    case thread
    case turn
}

public enum HookSource: String, Codable, Equatable, Sendable {
    case system
    case user
    case project
    case mdm
    case sessionFlags = "session_flags"
    case plugin
    case cloudRequirements = "cloud_requirements"
    case legacyManagedConfigFile = "legacy_managed_config_file"
    case legacyManagedConfigMdm = "legacy_managed_config_mdm"
    case unknown
}

public enum HookTrustStatus: String, Codable, Equatable, Sendable {
    case managed
    case untrusted
    case trusted
    case modified
}

public enum HookRunStatus: String, Codable, Equatable, Sendable {
    case running
    case completed
    case failed
    case blocked
    case stopped
}

public enum HookOutputEntryKind: String, Codable, Equatable, Sendable {
    case warning
    case stop
    case feedback
    case context
    case error
}

public struct HookOutputEntry: Codable, Equatable, Sendable {
    public let kind: HookOutputEntryKind
    public let text: String

    public init(kind: HookOutputEntryKind, text: String) {
        self.kind = kind
        self.text = text
    }
}

public struct HookRunSummary: Codable, Equatable, Sendable {
    public let id: String
    public let eventName: HookEventName
    public let handlerType: HookHandlerType
    public let executionMode: HookExecutionMode
    public let scope: HookScope
    public let sourcePath: AbsolutePath
    public let source: HookSource
    public let displayOrder: Int64
    public let status: HookRunStatus
    public let statusMessage: String?
    public let startedAt: Int64
    public let completedAt: Int64?
    public let durationMs: Int64?
    public let entries: [HookOutputEntry]

    public init(
        id: String,
        eventName: HookEventName,
        handlerType: HookHandlerType,
        executionMode: HookExecutionMode,
        scope: HookScope,
        sourcePath: AbsolutePath,
        source: HookSource = .unknown,
        displayOrder: Int64,
        status: HookRunStatus,
        statusMessage: String?,
        startedAt: Int64,
        completedAt: Int64?,
        durationMs: Int64?,
        entries: [HookOutputEntry]
    ) {
        self.id = id
        self.eventName = eventName
        self.handlerType = handlerType
        self.executionMode = executionMode
        self.scope = scope
        self.sourcePath = sourcePath
        self.source = source
        self.displayOrder = displayOrder
        self.status = status
        self.statusMessage = statusMessage
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.durationMs = durationMs
        self.entries = entries
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case eventName = "event_name"
        case handlerType = "handler_type"
        case executionMode = "execution_mode"
        case scope
        case sourcePath = "source_path"
        case source
        case displayOrder = "display_order"
        case status
        case statusMessage = "status_message"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case durationMs = "duration_ms"
        case entries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.eventName = try container.decode(HookEventName.self, forKey: .eventName)
        self.handlerType = try container.decode(HookHandlerType.self, forKey: .handlerType)
        self.executionMode = try container.decode(HookExecutionMode.self, forKey: .executionMode)
        self.scope = try container.decode(HookScope.self, forKey: .scope)
        self.sourcePath = try container.decode(AbsolutePath.self, forKey: .sourcePath)
        self.source = try container.decodeIfPresent(HookSource.self, forKey: .source) ?? .unknown
        self.displayOrder = try container.decode(Int64.self, forKey: .displayOrder)
        self.status = try container.decode(HookRunStatus.self, forKey: .status)
        self.statusMessage = try container.decodeIfPresent(String.self, forKey: .statusMessage)
        self.startedAt = try container.decode(Int64.self, forKey: .startedAt)
        self.completedAt = try container.decodeIfPresent(Int64.self, forKey: .completedAt)
        self.durationMs = try container.decodeIfPresent(Int64.self, forKey: .durationMs)
        self.entries = try container.decode([HookOutputEntry].self, forKey: .entries)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(eventName, forKey: .eventName)
        try container.encode(handlerType, forKey: .handlerType)
        try container.encode(executionMode, forKey: .executionMode)
        try container.encode(scope, forKey: .scope)
        try container.encode(sourcePath, forKey: .sourcePath)
        try container.encode(source, forKey: .source)
        try container.encode(displayOrder, forKey: .displayOrder)
        try container.encode(status, forKey: .status)
        try container.encodeNilOrValue(statusMessage, forKey: .statusMessage)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encodeNilOrValue(completedAt, forKey: .completedAt)
        try container.encodeNilOrValue(durationMs, forKey: .durationMs)
        try container.encode(entries, forKey: .entries)
    }
}

public struct HookStartedEvent: Codable, Equatable, Sendable {
    public let turnID: String?
    public let run: HookRunSummary

    public init(turnID: String?, run: HookRunSummary) {
        self.turnID = turnID
        self.run = run
    }

    private enum CodingKeys: String, CodingKey {
        case turnID = "turn_id"
        case run
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNilOrValue(turnID, forKey: .turnID)
        try container.encode(run, forKey: .run)
    }
}

public struct HookCompletedEvent: Codable, Equatable, Sendable {
    public let turnID: String?
    public let run: HookRunSummary

    public init(turnID: String?, run: HookRunSummary) {
        self.turnID = turnID
        self.run = run
    }

    private enum CodingKeys: String, CodingKey {
        case turnID = "turn_id"
        case run
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNilOrValue(turnID, forKey: .turnID)
        try container.encode(run, forKey: .run)
    }
}

public enum HooksProtocol {
    public static let eventNames: [String] = HookEventName.allCases.map(\.configLabel)

    public static let eventNamesWithMatchers: [String] = [
        HookEventName.preToolUse.configLabel,
        HookEventName.permissionRequest.configLabel,
        HookEventName.postToolUse.configLabel,
        HookEventName.preCompact.configLabel,
        HookEventName.postCompact.configLabel,
        HookEventName.sessionStart.configLabel,
    ]

    public static func hookEventKeyLabel(_ eventName: HookEventName) -> String {
        eventName.rawValue
    }

    public static func hookKey(
        keySource: String,
        eventName: HookEventName,
        groupIndex: Int,
        handlerIndex: Int
    ) -> String {
        "\(keySource):\(hookEventKeyLabel(eventName)):\(groupIndex):\(handlerIndex)"
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
