import Foundation

public enum ThreadGoalStatus: String, Codable, Equatable, Sendable {
    case active
    case paused
    case budgetLimited
    case complete
}

public struct ThreadGoal: Equatable, Codable, Sendable {
    public let threadID: ThreadId
    public let objective: String
    public let status: ThreadGoalStatus
    public let tokenBudget: Int64?
    public let tokensUsed: Int64
    public let timeUsedSeconds: Int64
    public let createdAt: Int64
    public let updatedAt: Int64

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case objective
        case status
        case tokenBudget
        case tokensUsed
        case timeUsedSeconds
        case createdAt
        case updatedAt
    }

    public init(
        threadID: ThreadId,
        objective: String,
        status: ThreadGoalStatus,
        tokenBudget: Int64? = nil,
        tokensUsed: Int64,
        timeUsedSeconds: Int64,
        createdAt: Int64,
        updatedAt: Int64
    ) {
        self.threadID = threadID
        self.objective = objective
        self.status = status
        self.tokenBudget = tokenBudget
        self.tokensUsed = tokensUsed
        self.timeUsedSeconds = timeUsedSeconds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(threadID, forKey: .threadID)
        try container.encode(objective, forKey: .objective)
        try container.encode(status, forKey: .status)
        if let tokenBudget {
            try container.encode(tokenBudget, forKey: .tokenBudget)
        } else {
            try container.encodeNil(forKey: .tokenBudget)
        }
        try container.encode(tokensUsed, forKey: .tokensUsed)
        try container.encode(timeUsedSeconds, forKey: .timeUsedSeconds)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

public struct ThreadGoalUpdatedEvent: Equatable, Codable, Sendable {
    public let threadID: ThreadId
    public let turnID: String?
    public let goal: ThreadGoal

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case turnID = "turnId"
        case goal
    }

    public init(threadID: ThreadId, turnID: String? = nil, goal: ThreadGoal) {
        self.threadID = threadID
        self.turnID = turnID
        self.goal = goal
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(threadID, forKey: .threadID)
        try container.encodeIfPresent(turnID, forKey: .turnID)
        try container.encode(goal, forKey: .goal)
    }
}
