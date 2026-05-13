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
