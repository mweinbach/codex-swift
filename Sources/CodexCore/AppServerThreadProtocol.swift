import Foundation

public enum AppServerSortDirection: String, Codable, Equatable, Sendable {
    case asc
    case desc
}

public enum AppServerTurnItemsView: String, Codable, Equatable, Sendable {
    case notLoaded
    case summary
    case full
}

public enum AppServerTurnStatus: String, Codable, Equatable, Sendable {
    case completed
    case interrupted
    case failed
    case inProgress
}

public enum ThreadUnsubscribeStatus: String, Codable, Equatable, Sendable {
    case notLoaded
    case notSubscribed
    case unsubscribed
}

public struct AppServerTurnError: Equatable, Codable, Sendable {
    public let message: String
    public let codexErrorInfo: CodexErrorInfo?
    public let additionalDetails: String?

    private enum CodingKeys: String, CodingKey {
        case message
        case codexErrorInfo
        case additionalDetails
    }

    public init(
        message: String,
        codexErrorInfo: CodexErrorInfo? = nil,
        additionalDetails: String? = nil
    ) {
        self.message = message
        self.codexErrorInfo = codexErrorInfo
        self.additionalDetails = additionalDetails
    }
}

public enum AppServerThreadItem: Equatable, Sendable {
    case agentMessage(id: String, text: String, phase: MessagePhase? = nil)
    case plan(id: String, text: String)
    case reasoning(id: String, summary: [String] = [], content: [String] = [])
    case contextCompaction(id: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case text
        case phase
        case summary
        case content
    }

    private enum ItemType: String, Codable {
        case agentMessage
        case plan
        case reasoning
        case contextCompaction
    }

    public var id: String {
        switch self {
        case let .agentMessage(id, _, _),
             let .plan(id, _),
             let .reasoning(id, _, _),
             let .contextCompaction(id):
            id
        }
    }
}

extension AppServerThreadItem: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ItemType.self, forKey: .type) {
        case .agentMessage:
            self = .agentMessage(
                id: try container.decode(String.self, forKey: .id),
                text: try container.decode(String.self, forKey: .text),
                phase: try container.decodeIfPresent(MessagePhase.self, forKey: .phase)
            )
        case .plan:
            self = .plan(
                id: try container.decode(String.self, forKey: .id),
                text: try container.decode(String.self, forKey: .text)
            )
        case .reasoning:
            self = .reasoning(
                id: try container.decode(String.self, forKey: .id),
                summary: try container.decodeIfPresent([String].self, forKey: .summary) ?? [],
                content: try container.decodeIfPresent([String].self, forKey: .content) ?? []
            )
        case .contextCompaction:
            self = .contextCompaction(id: try container.decode(String.self, forKey: .id))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .agentMessage(id, text, phase):
            try container.encode(ItemType.agentMessage, forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(phase, forKey: .phase)
        case let .plan(id, text):
            try container.encode(ItemType.plan, forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(text, forKey: .text)
        case let .reasoning(id, summary, content):
            try container.encode(ItemType.reasoning, forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(summary, forKey: .summary)
            try container.encode(content, forKey: .content)
        case let .contextCompaction(id):
            try container.encode(ItemType.contextCompaction, forKey: .type)
            try container.encode(id, forKey: .id)
        }
    }
}

public struct AppServerTurn: Equatable, Codable, Sendable {
    public let id: String
    public var items: [AppServerThreadItem]
    public var itemsView: AppServerTurnItemsView
    public let status: AppServerTurnStatus
    public let error: AppServerTurnError?
    public let startedAt: Int64?
    public let completedAt: Int64?
    public let durationMs: Int64?

    private enum CodingKeys: String, CodingKey {
        case id
        case items
        case itemsView
        case status
        case error
        case startedAt
        case completedAt
        case durationMs
    }

    public init(
        id: String,
        items: [AppServerThreadItem],
        itemsView: AppServerTurnItemsView = .full,
        status: AppServerTurnStatus,
        error: AppServerTurnError? = nil,
        startedAt: Int64? = nil,
        completedAt: Int64? = nil,
        durationMs: Int64? = nil
    ) {
        self.id = id
        self.items = items
        self.itemsView = itemsView
        self.status = status
        self.error = error
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.durationMs = durationMs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        items = try container.decode([AppServerThreadItem].self, forKey: .items)
        itemsView = try container.decodeIfPresent(AppServerTurnItemsView.self, forKey: .itemsView) ?? .full
        status = try container.decode(AppServerTurnStatus.self, forKey: .status)
        error = try container.decodeIfPresent(AppServerTurnError.self, forKey: .error)
        startedAt = try container.decodeIfPresent(Int64.self, forKey: .startedAt)
        completedAt = try container.decodeIfPresent(Int64.self, forKey: .completedAt)
        durationMs = try container.decodeIfPresent(Int64.self, forKey: .durationMs)
    }
}

public struct AppServerThread: Equatable, Sendable {
    public let id: String
    public var turns: [AppServerTurn]

    public init(id: String, turns: [AppServerTurn]) {
        self.id = id
        self.turns = turns
    }

    public func items(forTurnID turnID: String) -> [AppServerThreadItem]? {
        turns.first { $0.id == turnID }?.items
    }
}

public enum AppServerTurnCompletionBackfill {
    public static func shouldBackfill(threadEphemeral: Bool, completedTurn: AppServerTurn) -> Bool {
        !threadEphemeral && completedTurn.items.isEmpty
    }

    public static func backfilledTurn(_ completedTurn: AppServerTurn, from thread: AppServerThread) -> AppServerTurn {
        guard let items = thread.items(forTurnID: completedTurn.id) else {
            return completedTurn
        }
        var turn = completedTurn
        turn.items = items
        return turn
    }
}

public struct ThreadLoadedListParams: Equatable, Codable, Sendable {
    public let cursor: String?
    public let limit: UInt32?

    private enum CodingKeys: String, CodingKey {
        case cursor
        case limit
    }

    public init(cursor: String? = nil, limit: UInt32? = nil) {
        self.cursor = cursor
        self.limit = limit
    }
}

public struct ThreadLoadedListResponse: Equatable, Codable, Sendable {
    public let data: [String]
    public let nextCursor: String?

    private enum CodingKeys: String, CodingKey {
        case data
        case nextCursor
    }

    public init(data: [String], nextCursor: String?) {
        self.data = data
        self.nextCursor = nextCursor
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(data, forKey: .data)
        if let nextCursor {
            try container.encode(nextCursor, forKey: .nextCursor)
        } else {
            try container.encodeNil(forKey: .nextCursor)
        }
    }
}

public struct ThreadInjectItemsParams: Equatable, Codable, Sendable {
    public let threadID: String
    public let items: [JSONValue]

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case items
    }

    public init(threadID: String, items: [JSONValue]) {
        self.threadID = threadID
        self.items = items
    }
}

public struct ThreadInjectItemsResponse: Equatable, Codable, Sendable {
    public init() {}
}

public struct ThreadArchiveParams: Equatable, Codable, Sendable {
    public let threadID: String

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
    }

    public init(threadID: String) {
        self.threadID = threadID
    }
}

public struct ThreadArchiveResponse: Equatable, Codable, Sendable {
    public init() {}
}

public struct ThreadUnarchiveParams: Equatable, Codable, Sendable {
    public let threadID: String

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
    }

    public init(threadID: String) {
        self.threadID = threadID
    }
}

public struct ThreadUnsubscribeParams: Equatable, Codable, Sendable {
    public let threadID: String

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
    }

    public init(threadID: String) {
        self.threadID = threadID
    }
}

public struct ThreadUnsubscribeResponse: Equatable, Codable, Sendable {
    public let status: ThreadUnsubscribeStatus

    public init(status: ThreadUnsubscribeStatus) {
        self.status = status
    }
}

public struct ThreadIncrementElicitationParams: Equatable, Codable, Sendable {
    public let threadID: String

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
    }

    public init(threadID: String) {
        self.threadID = threadID
    }
}

public struct ThreadIncrementElicitationResponse: Equatable, Codable, Sendable {
    public let count: UInt64
    public let paused: Bool

    public init(count: UInt64, paused: Bool) {
        self.count = count
        self.paused = paused
    }
}

public struct ThreadDecrementElicitationParams: Equatable, Codable, Sendable {
    public let threadID: String

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
    }

    public init(threadID: String) {
        self.threadID = threadID
    }
}

public struct ThreadDecrementElicitationResponse: Equatable, Codable, Sendable {
    public let count: UInt64
    public let paused: Bool

    public init(count: UInt64, paused: Bool) {
        self.count = count
        self.paused = paused
    }
}

public struct ThreadSetNameParams: Equatable, Codable, Sendable {
    public let threadID: String
    public let name: String

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case name
    }

    public init(threadID: String, name: String) {
        self.threadID = threadID
        self.name = name
    }
}

public struct ThreadSetNameResponse: Equatable, Codable, Sendable {
    public init() {}
}

public struct ThreadCompactStartParams: Equatable, Codable, Sendable {
    public let threadID: String

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
    }

    public init(threadID: String) {
        self.threadID = threadID
    }
}

public struct ThreadCompactStartResponse: Equatable, Codable, Sendable {
    public init() {}
}

public struct ThreadShellCommandParams: Equatable, Codable, Sendable {
    public let threadID: String
    public let command: String

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case command
    }

    public init(threadID: String, command: String) {
        self.threadID = threadID
        self.command = command
    }
}

public struct ThreadShellCommandResponse: Equatable, Codable, Sendable {
    public init() {}
}

public struct ThreadApproveGuardianDeniedActionParams: Equatable, Codable, Sendable {
    public let threadID: String
    public let event: JSONValue

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case event
    }

    public init(threadID: String, event: JSONValue) {
        self.threadID = threadID
        self.event = event
    }
}

public struct ThreadApproveGuardianDeniedActionResponse: Equatable, Codable, Sendable {
    public init() {}
}

public struct ThreadBackgroundTerminalsCleanParams: Equatable, Codable, Sendable {
    public let threadID: String

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
    }

    public init(threadID: String) {
        self.threadID = threadID
    }
}

public struct ThreadBackgroundTerminalsCleanResponse: Equatable, Codable, Sendable {
    public init() {}
}

public enum ThreadMetadataStringPatch: Equatable, Sendable {
    case preserve
    case clear
    case set(String)
}

public struct ThreadMetadataGitInfoUpdateParams: Equatable, Codable, Sendable {
    public let sha: ThreadMetadataStringPatch
    public let branch: ThreadMetadataStringPatch
    public let originURL: ThreadMetadataStringPatch

    private enum CodingKeys: String, CodingKey {
        case sha
        case branch
        case originURL = "originUrl"
    }

    public init(
        sha: ThreadMetadataStringPatch = .preserve,
        branch: ThreadMetadataStringPatch = .preserve,
        originURL: ThreadMetadataStringPatch = .preserve
    ) {
        self.sha = sha
        self.branch = branch
        self.originURL = originURL
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sha = try Self.decodePatch(from: container, forKey: .sha)
        branch = try Self.decodePatch(from: container, forKey: .branch)
        originURL = try Self.decodePatch(from: container, forKey: .originURL)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try Self.encodePatch(sha, into: &container, forKey: .sha)
        try Self.encodePatch(branch, into: &container, forKey: .branch)
        try Self.encodePatch(originURL, into: &container, forKey: .originURL)
    }

    private static func decodePatch(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> ThreadMetadataStringPatch {
        if !container.contains(key) {
            return .preserve
        }
        if try container.decodeNil(forKey: key) {
            return .clear
        }
        return .set(try container.decode(String.self, forKey: key))
    }

    private static func encodePatch(
        _ patch: ThreadMetadataStringPatch,
        into container: inout KeyedEncodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws {
        switch patch {
        case .preserve:
            break
        case .clear:
            try container.encodeNil(forKey: key)
        case let .set(value):
            try container.encode(value, forKey: key)
        }
    }
}

public struct ThreadMetadataUpdateParams: Equatable, Codable, Sendable {
    public let threadID: String
    public let gitInfo: ThreadMetadataGitInfoUpdateParams?

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case gitInfo
    }

    public init(threadID: String, gitInfo: ThreadMetadataGitInfoUpdateParams?) {
        self.threadID = threadID
        self.gitInfo = gitInfo
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(threadID, forKey: .threadID)
        if let gitInfo {
            try container.encode(gitInfo, forKey: .gitInfo)
        } else {
            try container.encodeNil(forKey: .gitInfo)
        }
    }
}

public enum ThreadGoalTokenBudgetPatch: Equatable, Sendable {
    case preserve
    case clear
    case set(Int64)
}

public struct ThreadGoalSetParams: Equatable, Codable, Sendable {
    public let threadID: String
    public let objective: String?
    public let status: ThreadGoalStatus?
    public let tokenBudget: ThreadGoalTokenBudgetPatch

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case objective
        case status
        case tokenBudget
    }

    public init(
        threadID: String,
        objective: String? = nil,
        status: ThreadGoalStatus? = nil,
        tokenBudget: ThreadGoalTokenBudgetPatch = .preserve
    ) {
        self.threadID = threadID
        self.objective = objective
        self.status = status
        self.tokenBudget = tokenBudget
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threadID = try container.decode(String.self, forKey: .threadID)
        objective = try container.decodeIfPresent(String.self, forKey: .objective)
        status = try container.decodeIfPresent(ThreadGoalStatus.self, forKey: .status)
        if !container.contains(.tokenBudget) {
            tokenBudget = .preserve
        } else if try container.decodeNil(forKey: .tokenBudget) {
            tokenBudget = .clear
        } else {
            tokenBudget = .set(try container.decode(Int64.self, forKey: .tokenBudget))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(threadID, forKey: .threadID)
        try container.encodeIfPresent(objective, forKey: .objective)
        try container.encodeIfPresent(status, forKey: .status)
        switch tokenBudget {
        case .preserve:
            break
        case .clear:
            try container.encodeNil(forKey: .tokenBudget)
        case let .set(value):
            try container.encode(value, forKey: .tokenBudget)
        }
    }
}

public struct ThreadGoalSetResponse: Equatable, Codable, Sendable {
    public let goal: ThreadGoal

    public init(goal: ThreadGoal) {
        self.goal = goal
    }
}

public struct ThreadGoalGetParams: Equatable, Codable, Sendable {
    public let threadID: String

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
    }

    public init(threadID: String) {
        self.threadID = threadID
    }
}

public struct ThreadGoalGetResponse: Equatable, Codable, Sendable {
    public let goal: ThreadGoal?

    public init(goal: ThreadGoal?) {
        self.goal = goal
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let goal {
            try container.encode(goal, forKey: .goal)
        } else {
            try container.encodeNil(forKey: .goal)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case goal
    }
}

public struct ThreadGoalClearParams: Equatable, Codable, Sendable {
    public let threadID: String

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
    }

    public init(threadID: String) {
        self.threadID = threadID
    }
}

public struct ThreadGoalClearResponse: Equatable, Codable, Sendable {
    public let cleared: Bool

    public init(cleared: Bool) {
        self.cleared = cleared
    }
}

public struct ThreadMemoryModeSetParams: Equatable, Codable, Sendable {
    public let threadID: String
    public let mode: ThreadMemoryMode

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case mode
    }

    public init(threadID: String, mode: ThreadMemoryMode) {
        self.threadID = threadID
        self.mode = mode
    }
}

public struct ThreadMemoryModeSetResponse: Equatable, Codable, Sendable {
    public init() {}
}

public struct MemoryResetResponse: Equatable, Codable, Sendable {
    public init() {}
}

public struct ThreadRollbackParams: Equatable, Codable, Sendable {
    public let threadID: String
    public let numTurns: UInt32

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case numTurns
    }

    public init(threadID: String, numTurns: UInt32) {
        self.threadID = threadID
        self.numTurns = numTurns
    }
}

public struct ThreadReadParams: Equatable, Codable, Sendable {
    public let threadID: String
    public let includeTurns: Bool

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case includeTurns
    }

    public init(threadID: String, includeTurns: Bool = false) {
        self.threadID = threadID
        self.includeTurns = includeTurns
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threadID = try container.decode(String.self, forKey: .threadID)
        includeTurns = try container.decodeIfPresent(Bool.self, forKey: .includeTurns) ?? false
    }
}

public struct ThreadTurnsListParams: Equatable, Codable, Sendable {
    public let threadID: String
    public let cursor: String?
    public let limit: UInt32?
    public let sortDirection: AppServerSortDirection?
    public let itemsView: AppServerTurnItemsView?

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case cursor
        case limit
        case sortDirection
        case itemsView
    }

    public init(
        threadID: String,
        cursor: String? = nil,
        limit: UInt32? = nil,
        sortDirection: AppServerSortDirection? = nil,
        itemsView: AppServerTurnItemsView? = nil
    ) {
        self.threadID = threadID
        self.cursor = cursor
        self.limit = limit
        self.sortDirection = sortDirection
        self.itemsView = itemsView
    }
}

public struct ThreadTurnsListResponse: Equatable, Codable, Sendable {
    public let data: [AppServerTurn]
    public let nextCursor: String?
    public let backwardsCursor: String?

    private enum CodingKeys: String, CodingKey {
        case data
        case nextCursor
        case backwardsCursor
    }

    public init(data: [AppServerTurn], nextCursor: String?, backwardsCursor: String?) {
        self.data = data
        self.nextCursor = nextCursor
        self.backwardsCursor = backwardsCursor
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(data, forKey: .data)
        if let nextCursor {
            try container.encode(nextCursor, forKey: .nextCursor)
        } else {
            try container.encodeNil(forKey: .nextCursor)
        }
        if let backwardsCursor {
            try container.encode(backwardsCursor, forKey: .backwardsCursor)
        } else {
            try container.encodeNil(forKey: .backwardsCursor)
        }
    }
}

public struct ThreadTurnsItemsListParams: Equatable, Codable, Sendable {
    public let threadID: String
    public let turnID: String
    public let cursor: String?
    public let limit: UInt32?
    public let sortDirection: AppServerSortDirection?

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case turnID = "turnId"
        case cursor
        case limit
        case sortDirection
    }

    public init(
        threadID: String,
        turnID: String,
        cursor: String? = nil,
        limit: UInt32? = nil,
        sortDirection: AppServerSortDirection? = nil
    ) {
        self.threadID = threadID
        self.turnID = turnID
        self.cursor = cursor
        self.limit = limit
        self.sortDirection = sortDirection
    }
}

public struct ThreadTurnsItemsListResponse: Equatable, Codable, Sendable {
    public let data: [AppServerThreadItem]
    public let nextCursor: String?
    public let backwardsCursor: String?

    private enum CodingKeys: String, CodingKey {
        case data
        case nextCursor
        case backwardsCursor
    }

    public init(data: [AppServerThreadItem], nextCursor: String?, backwardsCursor: String?) {
        self.data = data
        self.nextCursor = nextCursor
        self.backwardsCursor = backwardsCursor
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(data, forKey: .data)
        if let nextCursor {
            try container.encode(nextCursor, forKey: .nextCursor)
        } else {
            try container.encodeNil(forKey: .nextCursor)
        }
        if let backwardsCursor {
            try container.encode(backwardsCursor, forKey: .backwardsCursor)
        } else {
            try container.encodeNil(forKey: .backwardsCursor)
        }
    }
}
