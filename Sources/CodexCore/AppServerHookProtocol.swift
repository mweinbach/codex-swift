import Foundation

public enum AppServerHookEventName: String, Codable, Equatable, Sendable {
    case preToolUse
    case permissionRequest
    case postToolUse
    case preCompact
    case postCompact
    case sessionStart
    case userPromptSubmit
    case stop

    public init(core eventName: HookEventName) {
        switch eventName {
        case .preToolUse: self = .preToolUse
        case .permissionRequest: self = .permissionRequest
        case .postToolUse: self = .postToolUse
        case .preCompact: self = .preCompact
        case .postCompact: self = .postCompact
        case .sessionStart: self = .sessionStart
        case .userPromptSubmit: self = .userPromptSubmit
        case .stop: self = .stop
        }
    }
}

public enum AppServerHookHandlerType: String, Codable, Equatable, Sendable {
    case command
    case prompt
    case agent

    public init(core handlerType: HookHandlerType) {
        switch handlerType {
        case .command: self = .command
        case .prompt: self = .prompt
        case .agent: self = .agent
        }
    }
}

public enum AppServerHookExecutionMode: String, Codable, Equatable, Sendable {
    case sync
    case `async`

    public init(core executionMode: HookExecutionMode) {
        switch executionMode {
        case .sync: self = .sync
        case .async: self = .async
        }
    }
}

public enum AppServerHookScope: String, Codable, Equatable, Sendable {
    case thread
    case turn

    public init(core scope: HookScope) {
        switch scope {
        case .thread: self = .thread
        case .turn: self = .turn
        }
    }
}

public enum AppServerHookSource: String, Codable, Equatable, Sendable {
    case system
    case user
    case project
    case mdm
    case sessionFlags
    case plugin
    case cloudRequirements
    case legacyManagedConfigFile
    case legacyManagedConfigMdm
    case unknown

    public init(core source: HookSource) {
        switch source {
        case .system: self = .system
        case .user: self = .user
        case .project: self = .project
        case .mdm: self = .mdm
        case .sessionFlags: self = .sessionFlags
        case .plugin: self = .plugin
        case .cloudRequirements: self = .cloudRequirements
        case .legacyManagedConfigFile: self = .legacyManagedConfigFile
        case .legacyManagedConfigMdm: self = .legacyManagedConfigMdm
        case .unknown: self = .unknown
        }
    }
}

public enum AppServerHookTrustStatus: String, Codable, Equatable, Sendable {
    case managed
    case untrusted
    case trusted
    case modified

    public init(core trustStatus: HookTrustStatus) {
        switch trustStatus {
        case .managed: self = .managed
        case .untrusted: self = .untrusted
        case .trusted: self = .trusted
        case .modified: self = .modified
        }
    }
}

public enum AppServerHookRunStatus: String, Codable, Equatable, Sendable {
    case running
    case completed
    case failed
    case blocked
    case stopped

    public init(core status: HookRunStatus) {
        switch status {
        case .running: self = .running
        case .completed: self = .completed
        case .failed: self = .failed
        case .blocked: self = .blocked
        case .stopped: self = .stopped
        }
    }
}

public enum AppServerHookOutputEntryKind: String, Codable, Equatable, Sendable {
    case warning
    case stop
    case feedback
    case context
    case error

    public init(core kind: HookOutputEntryKind) {
        switch kind {
        case .warning: self = .warning
        case .stop: self = .stop
        case .feedback: self = .feedback
        case .context: self = .context
        case .error: self = .error
        }
    }
}

public struct AppServerHookOutputEntry: Equatable, Codable, Sendable {
    public let kind: AppServerHookOutputEntryKind
    public let text: String

    public init(kind: AppServerHookOutputEntryKind, text: String) {
        self.kind = kind
        self.text = text
    }

    public init(core entry: HookOutputEntry) {
        self.init(kind: AppServerHookOutputEntryKind(core: entry.kind), text: entry.text)
    }
}

public struct AppServerHookRunSummary: Equatable, Sendable {
    public let id: String
    public let eventName: AppServerHookEventName
    public let handlerType: AppServerHookHandlerType
    public let executionMode: AppServerHookExecutionMode
    public let scope: AppServerHookScope
    public let sourcePath: AbsolutePath
    public let source: AppServerHookSource
    public let displayOrder: Int64
    public let status: AppServerHookRunStatus
    public let statusMessage: String?
    public let startedAt: Int64
    public let completedAt: Int64?
    public let durationMs: Int64?
    public let entries: [AppServerHookOutputEntry]

    public init(
        id: String,
        eventName: AppServerHookEventName,
        handlerType: AppServerHookHandlerType,
        executionMode: AppServerHookExecutionMode,
        scope: AppServerHookScope,
        sourcePath: AbsolutePath,
        source: AppServerHookSource = .unknown,
        displayOrder: Int64,
        status: AppServerHookRunStatus,
        statusMessage: String?,
        startedAt: Int64,
        completedAt: Int64?,
        durationMs: Int64?,
        entries: [AppServerHookOutputEntry]
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

    public init(core run: HookRunSummary) {
        self.init(
            id: run.id,
            eventName: AppServerHookEventName(core: run.eventName),
            handlerType: AppServerHookHandlerType(core: run.handlerType),
            executionMode: AppServerHookExecutionMode(core: run.executionMode),
            scope: AppServerHookScope(core: run.scope),
            sourcePath: run.sourcePath,
            source: AppServerHookSource(core: run.source),
            displayOrder: run.displayOrder,
            status: AppServerHookRunStatus(core: run.status),
            statusMessage: run.statusMessage,
            startedAt: run.startedAt,
            completedAt: run.completedAt,
            durationMs: run.durationMs,
            entries: run.entries.map(AppServerHookOutputEntry.init(core:))
        )
    }
}

extension AppServerHookRunSummary: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case eventName
        case handlerType
        case executionMode
        case scope
        case sourcePath
        case source
        case displayOrder
        case status
        case statusMessage
        case startedAt
        case completedAt
        case durationMs
        case entries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            eventName: try container.decode(AppServerHookEventName.self, forKey: .eventName),
            handlerType: try container.decode(AppServerHookHandlerType.self, forKey: .handlerType),
            executionMode: try container.decode(AppServerHookExecutionMode.self, forKey: .executionMode),
            scope: try container.decode(AppServerHookScope.self, forKey: .scope),
            sourcePath: try container.decode(AbsolutePath.self, forKey: .sourcePath),
            source: try container.decodeIfPresent(AppServerHookSource.self, forKey: .source) ?? .unknown,
            displayOrder: try container.decode(Int64.self, forKey: .displayOrder),
            status: try container.decode(AppServerHookRunStatus.self, forKey: .status),
            statusMessage: try container.decodeIfPresent(String.self, forKey: .statusMessage),
            startedAt: try container.decode(Int64.self, forKey: .startedAt),
            completedAt: try container.decodeIfPresent(Int64.self, forKey: .completedAt),
            durationMs: try container.decodeIfPresent(Int64.self, forKey: .durationMs),
            entries: try container.decode([AppServerHookOutputEntry].self, forKey: .entries)
        )
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

public struct HookStartedNotification: Equatable, Sendable {
    public let threadID: String
    public let turnID: String?
    public let run: AppServerHookRunSummary

    public init(threadID: String, turnID: String?, run: AppServerHookRunSummary) {
        self.threadID = threadID
        self.turnID = turnID
        self.run = run
    }
}

extension HookStartedNotification: Codable {
    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case turnID = "turnId"
        case run
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            threadID: try container.decode(String.self, forKey: .threadID),
            turnID: try container.decodeIfPresent(String.self, forKey: .turnID),
            run: try container.decode(AppServerHookRunSummary.self, forKey: .run)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(threadID, forKey: .threadID)
        try container.encodeNilOrValue(turnID, forKey: .turnID)
        try container.encode(run, forKey: .run)
    }
}

public struct HookCompletedNotification: Equatable, Sendable {
    public let threadID: String
    public let turnID: String?
    public let run: AppServerHookRunSummary

    public init(threadID: String, turnID: String?, run: AppServerHookRunSummary) {
        self.threadID = threadID
        self.turnID = turnID
        self.run = run
    }
}

extension HookCompletedNotification: Codable {
    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case turnID = "turnId"
        case run
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            threadID: try container.decode(String.self, forKey: .threadID),
            turnID: try container.decodeIfPresent(String.self, forKey: .turnID),
            run: try container.decode(AppServerHookRunSummary.self, forKey: .run)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(threadID, forKey: .threadID)
        try container.encodeNilOrValue(turnID, forKey: .turnID)
        try container.encode(run, forKey: .run)
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
