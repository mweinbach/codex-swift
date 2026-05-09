import Foundation

public enum AgentStatus: Equatable, Codable, Sendable {
    case pendingInit
    case running
    case interrupted
    case completed(String?)
    case errored(String)
    case shutdown
    case notFound

    fileprivate enum UnitVariant: String, Codable {
        case pendingInit = "pending_init"
        case running
        case interrupted
        case shutdown
        case notFound = "not_found"
    }

    private enum ObjectVariant: String, CodingKey {
        case completed
        case errored
    }

    public init(from decoder: Decoder) throws {
        let singleValue = try decoder.singleValueContainer()
        if let rawValue = try? singleValue.decode(String.self) {
            guard let variant = UnitVariant(rawValue: rawValue) else {
                throw DecodingError.dataCorruptedError(
                    in: singleValue,
                    debugDescription: "Unknown AgentStatus variant: \(rawValue)"
                )
            }
            self = variant.agentStatus
            return
        }

        let container = try decoder.container(keyedBy: ObjectVariant.self)
        guard container.allKeys.count == 1, let key = container.allKeys.first else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected exactly one AgentStatus object variant"
                )
            )
        }

        switch key {
        case .completed:
            self = .completed(try container.decodeIfPresent(String.self, forKey: .completed))
        case .errored:
            self = .errored(try container.decode(String.self, forKey: .errored))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .pendingInit:
            var container = encoder.singleValueContainer()
            try container.encode(UnitVariant.pendingInit.rawValue)
        case .running:
            var container = encoder.singleValueContainer()
            try container.encode(UnitVariant.running.rawValue)
        case .interrupted:
            var container = encoder.singleValueContainer()
            try container.encode(UnitVariant.interrupted.rawValue)
        case let .completed(message):
            var container = encoder.container(keyedBy: ObjectVariant.self)
            try container.encodeNilOrValue(message, forKey: .completed)
        case let .errored(message):
            var container = encoder.container(keyedBy: ObjectVariant.self)
            try container.encode(message, forKey: .errored)
        case .shutdown:
            var container = encoder.singleValueContainer()
            try container.encode(UnitVariant.shutdown.rawValue)
        case .notFound:
            var container = encoder.singleValueContainer()
            try container.encode(UnitVariant.notFound.rawValue)
        }
    }
}

private extension AgentStatus.UnitVariant {
    var agentStatus: AgentStatus {
        switch self {
        case .pendingInit:
            return .pendingInit
        case .running:
            return .running
        case .interrupted:
            return .interrupted
        case .shutdown:
            return .shutdown
        case .notFound:
            return .notFound
        }
    }
}

public struct CollabAgentRef: Equatable, Codable, Sendable {
    public let threadID: ThreadId
    public let agentNickname: String?
    public let agentRole: String?

    private enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case agentNickname = "agent_nickname"
        case agentRole = "agent_role"
        case agentType = "agent_type"
    }

    public init(threadID: ThreadId, agentNickname: String? = nil, agentRole: String? = nil) {
        self.threadID = threadID
        self.agentNickname = agentNickname
        self.agentRole = agentRole
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threadID = try container.decode(ThreadId.self, forKey: .threadID)
        agentNickname = try container.decodeIfPresent(String.self, forKey: .agentNickname)
        agentRole = try container.decodeIfPresent(String.self, forKey: .agentRole)
            ?? container.decodeIfPresent(String.self, forKey: .agentType)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(threadID, forKey: .threadID)
        try container.encodeIfPresent(agentNickname, forKey: .agentNickname)
        try container.encodeIfPresent(agentRole, forKey: .agentRole)
    }
}

public struct CollabAgentStatusEntry: Equatable, Codable, Sendable {
    public let threadID: ThreadId
    public let agentNickname: String?
    public let agentRole: String?
    public let status: AgentStatus

    private enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case agentNickname = "agent_nickname"
        case agentRole = "agent_role"
        case agentType = "agent_type"
        case status
    }

    public init(
        threadID: ThreadId,
        agentNickname: String? = nil,
        agentRole: String? = nil,
        status: AgentStatus
    ) {
        self.threadID = threadID
        self.agentNickname = agentNickname
        self.agentRole = agentRole
        self.status = status
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threadID = try container.decode(ThreadId.self, forKey: .threadID)
        agentNickname = try container.decodeIfPresent(String.self, forKey: .agentNickname)
        agentRole = try container.decodeIfPresent(String.self, forKey: .agentRole)
            ?? container.decodeIfPresent(String.self, forKey: .agentType)
        status = try container.decode(AgentStatus.self, forKey: .status)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(threadID, forKey: .threadID)
        try container.encodeIfPresent(agentNickname, forKey: .agentNickname)
        try container.encodeIfPresent(agentRole, forKey: .agentRole)
        try container.encode(status, forKey: .status)
    }
}

public struct CollabAgentSpawnBeginEvent: Equatable, Codable, Sendable {
    public let callID: String
    public let startedAtMilliseconds: Int64
    public let senderThreadID: ThreadId
    public let prompt: String
    public let model: String
    public let reasoningEffort: ReasoningEffort

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case startedAtMilliseconds = "started_at_ms"
        case senderThreadID = "sender_thread_id"
        case prompt
        case model
        case reasoningEffort = "reasoning_effort"
    }

    public init(
        callID: String,
        startedAtMilliseconds: Int64 = 0,
        senderThreadID: ThreadId,
        prompt: String,
        model: String,
        reasoningEffort: ReasoningEffort
    ) {
        self.callID = callID
        self.startedAtMilliseconds = startedAtMilliseconds
        self.senderThreadID = senderThreadID
        self.prompt = prompt
        self.model = model
        self.reasoningEffort = reasoningEffort
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callID = try container.decode(String.self, forKey: .callID)
        startedAtMilliseconds = try container.decodeIfPresent(Int64.self, forKey: .startedAtMilliseconds) ?? 0
        senderThreadID = try container.decode(ThreadId.self, forKey: .senderThreadID)
        prompt = try container.decode(String.self, forKey: .prompt)
        model = try container.decode(String.self, forKey: .model)
        reasoningEffort = try container.decode(ReasoningEffort.self, forKey: .reasoningEffort)
    }
}

public struct CollabAgentSpawnEndEvent: Equatable, Codable, Sendable {
    public let callID: String
    public let completedAtMilliseconds: Int64
    public let senderThreadID: ThreadId
    public let newThreadID: ThreadId?
    public let newAgentNickname: String?
    public let newAgentRole: String?
    public let prompt: String
    public let model: String
    public let reasoningEffort: ReasoningEffort
    public let status: AgentStatus

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case completedAtMilliseconds = "completed_at_ms"
        case senderThreadID = "sender_thread_id"
        case newThreadID = "new_thread_id"
        case newAgentNickname = "new_agent_nickname"
        case newAgentRole = "new_agent_role"
        case prompt
        case model
        case reasoningEffort = "reasoning_effort"
        case status
    }

    public init(
        callID: String,
        completedAtMilliseconds: Int64 = 0,
        senderThreadID: ThreadId,
        newThreadID: ThreadId? = nil,
        newAgentNickname: String? = nil,
        newAgentRole: String? = nil,
        prompt: String,
        model: String,
        reasoningEffort: ReasoningEffort,
        status: AgentStatus
    ) {
        self.callID = callID
        self.completedAtMilliseconds = completedAtMilliseconds
        self.senderThreadID = senderThreadID
        self.newThreadID = newThreadID
        self.newAgentNickname = newAgentNickname
        self.newAgentRole = newAgentRole
        self.prompt = prompt
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.status = status
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callID = try container.decode(String.self, forKey: .callID)
        completedAtMilliseconds = try container.decodeIfPresent(Int64.self, forKey: .completedAtMilliseconds) ?? 0
        senderThreadID = try container.decode(ThreadId.self, forKey: .senderThreadID)
        newThreadID = try container.decodeIfPresent(ThreadId.self, forKey: .newThreadID)
        newAgentNickname = try container.decodeIfPresent(String.self, forKey: .newAgentNickname)
        newAgentRole = try container.decodeIfPresent(String.self, forKey: .newAgentRole)
        prompt = try container.decode(String.self, forKey: .prompt)
        model = try container.decode(String.self, forKey: .model)
        reasoningEffort = try container.decode(ReasoningEffort.self, forKey: .reasoningEffort)
        status = try container.decode(AgentStatus.self, forKey: .status)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(callID, forKey: .callID)
        try container.encode(completedAtMilliseconds, forKey: .completedAtMilliseconds)
        try container.encode(senderThreadID, forKey: .senderThreadID)
        try container.encodeIfPresent(newThreadID, forKey: .newThreadID)
        try container.encodeIfPresent(newAgentNickname, forKey: .newAgentNickname)
        try container.encodeIfPresent(newAgentRole, forKey: .newAgentRole)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(model, forKey: .model)
        try container.encode(reasoningEffort, forKey: .reasoningEffort)
        try container.encode(status, forKey: .status)
    }
}

public struct CollabAgentInteractionBeginEvent: Equatable, Codable, Sendable {
    public let callID: String
    public let startedAtMilliseconds: Int64
    public let senderThreadID: ThreadId
    public let receiverThreadID: ThreadId
    public let prompt: String

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case startedAtMilliseconds = "started_at_ms"
        case senderThreadID = "sender_thread_id"
        case receiverThreadID = "receiver_thread_id"
        case prompt
    }

    public init(
        callID: String,
        startedAtMilliseconds: Int64 = 0,
        senderThreadID: ThreadId,
        receiverThreadID: ThreadId,
        prompt: String
    ) {
        self.callID = callID
        self.startedAtMilliseconds = startedAtMilliseconds
        self.senderThreadID = senderThreadID
        self.receiverThreadID = receiverThreadID
        self.prompt = prompt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callID = try container.decode(String.self, forKey: .callID)
        startedAtMilliseconds = try container.decodeIfPresent(Int64.self, forKey: .startedAtMilliseconds) ?? 0
        senderThreadID = try container.decode(ThreadId.self, forKey: .senderThreadID)
        receiverThreadID = try container.decode(ThreadId.self, forKey: .receiverThreadID)
        prompt = try container.decode(String.self, forKey: .prompt)
    }
}

public struct CollabAgentInteractionEndEvent: Equatable, Codable, Sendable {
    public let callID: String
    public let completedAtMilliseconds: Int64
    public let senderThreadID: ThreadId
    public let receiverThreadID: ThreadId
    public let receiverAgentNickname: String?
    public let receiverAgentRole: String?
    public let prompt: String
    public let status: AgentStatus

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case completedAtMilliseconds = "completed_at_ms"
        case senderThreadID = "sender_thread_id"
        case receiverThreadID = "receiver_thread_id"
        case receiverAgentNickname = "receiver_agent_nickname"
        case receiverAgentRole = "receiver_agent_role"
        case prompt
        case status
    }

    public init(
        callID: String,
        completedAtMilliseconds: Int64 = 0,
        senderThreadID: ThreadId,
        receiverThreadID: ThreadId,
        receiverAgentNickname: String? = nil,
        receiverAgentRole: String? = nil,
        prompt: String,
        status: AgentStatus
    ) {
        self.callID = callID
        self.completedAtMilliseconds = completedAtMilliseconds
        self.senderThreadID = senderThreadID
        self.receiverThreadID = receiverThreadID
        self.receiverAgentNickname = receiverAgentNickname
        self.receiverAgentRole = receiverAgentRole
        self.prompt = prompt
        self.status = status
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callID = try container.decode(String.self, forKey: .callID)
        completedAtMilliseconds = try container.decodeIfPresent(Int64.self, forKey: .completedAtMilliseconds) ?? 0
        senderThreadID = try container.decode(ThreadId.self, forKey: .senderThreadID)
        receiverThreadID = try container.decode(ThreadId.self, forKey: .receiverThreadID)
        receiverAgentNickname = try container.decodeIfPresent(String.self, forKey: .receiverAgentNickname)
        receiverAgentRole = try container.decodeIfPresent(String.self, forKey: .receiverAgentRole)
        prompt = try container.decode(String.self, forKey: .prompt)
        status = try container.decode(AgentStatus.self, forKey: .status)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(callID, forKey: .callID)
        try container.encode(completedAtMilliseconds, forKey: .completedAtMilliseconds)
        try container.encode(senderThreadID, forKey: .senderThreadID)
        try container.encode(receiverThreadID, forKey: .receiverThreadID)
        try container.encodeIfPresent(receiverAgentNickname, forKey: .receiverAgentNickname)
        try container.encodeIfPresent(receiverAgentRole, forKey: .receiverAgentRole)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(status, forKey: .status)
    }
}

public struct CollabWaitingBeginEvent: Equatable, Codable, Sendable {
    public let startedAtMilliseconds: Int64
    public let senderThreadID: ThreadId
    public let receiverThreadIDs: [ThreadId]
    public let receiverAgents: [CollabAgentRef]
    public let callID: String

    private enum CodingKeys: String, CodingKey {
        case startedAtMilliseconds = "started_at_ms"
        case senderThreadID = "sender_thread_id"
        case receiverThreadIDs = "receiver_thread_ids"
        case receiverAgents = "receiver_agents"
        case callID = "call_id"
    }

    public init(
        startedAtMilliseconds: Int64 = 0,
        senderThreadID: ThreadId,
        receiverThreadIDs: [ThreadId],
        receiverAgents: [CollabAgentRef] = [],
        callID: String
    ) {
        self.startedAtMilliseconds = startedAtMilliseconds
        self.senderThreadID = senderThreadID
        self.receiverThreadIDs = receiverThreadIDs
        self.receiverAgents = receiverAgents
        self.callID = callID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startedAtMilliseconds = try container.decodeIfPresent(Int64.self, forKey: .startedAtMilliseconds) ?? 0
        senderThreadID = try container.decode(ThreadId.self, forKey: .senderThreadID)
        receiverThreadIDs = try container.decode([ThreadId].self, forKey: .receiverThreadIDs)
        receiverAgents = try container.decodeIfPresent([CollabAgentRef].self, forKey: .receiverAgents) ?? []
        callID = try container.decode(String.self, forKey: .callID)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(startedAtMilliseconds, forKey: .startedAtMilliseconds)
        try container.encode(senderThreadID, forKey: .senderThreadID)
        try container.encode(receiverThreadIDs, forKey: .receiverThreadIDs)
        if !receiverAgents.isEmpty {
            try container.encode(receiverAgents, forKey: .receiverAgents)
        }
        try container.encode(callID, forKey: .callID)
    }
}

public struct CollabWaitingEndEvent: Equatable, Codable, Sendable {
    public let senderThreadID: ThreadId
    public let callID: String
    public let completedAtMilliseconds: Int64
    public let agentStatuses: [CollabAgentStatusEntry]
    public let statuses: [ThreadId: AgentStatus]

    private enum CodingKeys: String, CodingKey {
        case senderThreadID = "sender_thread_id"
        case callID = "call_id"
        case completedAtMilliseconds = "completed_at_ms"
        case agentStatuses = "agent_statuses"
        case statuses
    }

    public init(
        senderThreadID: ThreadId,
        callID: String,
        completedAtMilliseconds: Int64 = 0,
        agentStatuses: [CollabAgentStatusEntry] = [],
        statuses: [ThreadId: AgentStatus]
    ) {
        self.senderThreadID = senderThreadID
        self.callID = callID
        self.completedAtMilliseconds = completedAtMilliseconds
        self.agentStatuses = agentStatuses
        self.statuses = statuses
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        senderThreadID = try container.decode(ThreadId.self, forKey: .senderThreadID)
        callID = try container.decode(String.self, forKey: .callID)
        completedAtMilliseconds = try container.decodeIfPresent(Int64.self, forKey: .completedAtMilliseconds) ?? 0
        agentStatuses = try container.decodeIfPresent([CollabAgentStatusEntry].self, forKey: .agentStatuses) ?? []
        let statusContainer = try container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: .statuses)
        statuses = try statusContainer.allKeys.reduce(into: [:]) { result, key in
            result[try ThreadId(string: key.stringValue)] = try statusContainer.decode(AgentStatus.self, forKey: key)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(senderThreadID, forKey: .senderThreadID)
        try container.encode(callID, forKey: .callID)
        try container.encode(completedAtMilliseconds, forKey: .completedAtMilliseconds)
        if !agentStatuses.isEmpty {
            try container.encode(agentStatuses, forKey: .agentStatuses)
        }
        var statusContainer = container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: .statuses)
        for (threadID, status) in statuses {
            try statusContainer.encode(status, forKey: DynamicCodingKey(stringValue: threadID.description))
        }
    }
}

public struct CollabCloseBeginEvent: Equatable, Codable, Sendable {
    public let callID: String
    public let startedAtMilliseconds: Int64
    public let senderThreadID: ThreadId
    public let receiverThreadID: ThreadId

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case startedAtMilliseconds = "started_at_ms"
        case senderThreadID = "sender_thread_id"
        case receiverThreadID = "receiver_thread_id"
    }

    public init(
        callID: String,
        startedAtMilliseconds: Int64 = 0,
        senderThreadID: ThreadId,
        receiverThreadID: ThreadId
    ) {
        self.callID = callID
        self.startedAtMilliseconds = startedAtMilliseconds
        self.senderThreadID = senderThreadID
        self.receiverThreadID = receiverThreadID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callID = try container.decode(String.self, forKey: .callID)
        startedAtMilliseconds = try container.decodeIfPresent(Int64.self, forKey: .startedAtMilliseconds) ?? 0
        senderThreadID = try container.decode(ThreadId.self, forKey: .senderThreadID)
        receiverThreadID = try container.decode(ThreadId.self, forKey: .receiverThreadID)
    }
}

public struct CollabCloseEndEvent: Equatable, Codable, Sendable {
    public let callID: String
    public let completedAtMilliseconds: Int64
    public let senderThreadID: ThreadId
    public let receiverThreadID: ThreadId
    public let receiverAgentNickname: String?
    public let receiverAgentRole: String?
    public let status: AgentStatus

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case completedAtMilliseconds = "completed_at_ms"
        case senderThreadID = "sender_thread_id"
        case receiverThreadID = "receiver_thread_id"
        case receiverAgentNickname = "receiver_agent_nickname"
        case receiverAgentRole = "receiver_agent_role"
        case status
    }

    public init(
        callID: String,
        completedAtMilliseconds: Int64 = 0,
        senderThreadID: ThreadId,
        receiverThreadID: ThreadId,
        receiverAgentNickname: String? = nil,
        receiverAgentRole: String? = nil,
        status: AgentStatus
    ) {
        self.callID = callID
        self.completedAtMilliseconds = completedAtMilliseconds
        self.senderThreadID = senderThreadID
        self.receiverThreadID = receiverThreadID
        self.receiverAgentNickname = receiverAgentNickname
        self.receiverAgentRole = receiverAgentRole
        self.status = status
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callID = try container.decode(String.self, forKey: .callID)
        completedAtMilliseconds = try container.decodeIfPresent(Int64.self, forKey: .completedAtMilliseconds) ?? 0
        senderThreadID = try container.decode(ThreadId.self, forKey: .senderThreadID)
        receiverThreadID = try container.decode(ThreadId.self, forKey: .receiverThreadID)
        receiverAgentNickname = try container.decodeIfPresent(String.self, forKey: .receiverAgentNickname)
        receiverAgentRole = try container.decodeIfPresent(String.self, forKey: .receiverAgentRole)
        status = try container.decode(AgentStatus.self, forKey: .status)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(callID, forKey: .callID)
        try container.encode(completedAtMilliseconds, forKey: .completedAtMilliseconds)
        try container.encode(senderThreadID, forKey: .senderThreadID)
        try container.encode(receiverThreadID, forKey: .receiverThreadID)
        try container.encodeIfPresent(receiverAgentNickname, forKey: .receiverAgentNickname)
        try container.encodeIfPresent(receiverAgentRole, forKey: .receiverAgentRole)
        try container.encode(status, forKey: .status)
    }
}

public struct CollabResumeBeginEvent: Equatable, Codable, Sendable {
    public let callID: String
    public let startedAtMilliseconds: Int64
    public let senderThreadID: ThreadId
    public let receiverThreadID: ThreadId
    public let receiverAgentNickname: String?
    public let receiverAgentRole: String?

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case startedAtMilliseconds = "started_at_ms"
        case senderThreadID = "sender_thread_id"
        case receiverThreadID = "receiver_thread_id"
        case receiverAgentNickname = "receiver_agent_nickname"
        case receiverAgentRole = "receiver_agent_role"
    }

    public init(
        callID: String,
        startedAtMilliseconds: Int64 = 0,
        senderThreadID: ThreadId,
        receiverThreadID: ThreadId,
        receiverAgentNickname: String? = nil,
        receiverAgentRole: String? = nil
    ) {
        self.callID = callID
        self.startedAtMilliseconds = startedAtMilliseconds
        self.senderThreadID = senderThreadID
        self.receiverThreadID = receiverThreadID
        self.receiverAgentNickname = receiverAgentNickname
        self.receiverAgentRole = receiverAgentRole
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callID = try container.decode(String.self, forKey: .callID)
        startedAtMilliseconds = try container.decodeIfPresent(Int64.self, forKey: .startedAtMilliseconds) ?? 0
        senderThreadID = try container.decode(ThreadId.self, forKey: .senderThreadID)
        receiverThreadID = try container.decode(ThreadId.self, forKey: .receiverThreadID)
        receiverAgentNickname = try container.decodeIfPresent(String.self, forKey: .receiverAgentNickname)
        receiverAgentRole = try container.decodeIfPresent(String.self, forKey: .receiverAgentRole)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(callID, forKey: .callID)
        try container.encode(startedAtMilliseconds, forKey: .startedAtMilliseconds)
        try container.encode(senderThreadID, forKey: .senderThreadID)
        try container.encode(receiverThreadID, forKey: .receiverThreadID)
        try container.encodeIfPresent(receiverAgentNickname, forKey: .receiverAgentNickname)
        try container.encodeIfPresent(receiverAgentRole, forKey: .receiverAgentRole)
    }
}

public struct CollabResumeEndEvent: Equatable, Codable, Sendable {
    public let callID: String
    public let completedAtMilliseconds: Int64
    public let senderThreadID: ThreadId
    public let receiverThreadID: ThreadId
    public let receiverAgentNickname: String?
    public let receiverAgentRole: String?
    public let status: AgentStatus

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case completedAtMilliseconds = "completed_at_ms"
        case senderThreadID = "sender_thread_id"
        case receiverThreadID = "receiver_thread_id"
        case receiverAgentNickname = "receiver_agent_nickname"
        case receiverAgentRole = "receiver_agent_role"
        case status
    }

    public init(
        callID: String,
        completedAtMilliseconds: Int64 = 0,
        senderThreadID: ThreadId,
        receiverThreadID: ThreadId,
        receiverAgentNickname: String? = nil,
        receiverAgentRole: String? = nil,
        status: AgentStatus
    ) {
        self.callID = callID
        self.completedAtMilliseconds = completedAtMilliseconds
        self.senderThreadID = senderThreadID
        self.receiverThreadID = receiverThreadID
        self.receiverAgentNickname = receiverAgentNickname
        self.receiverAgentRole = receiverAgentRole
        self.status = status
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callID = try container.decode(String.self, forKey: .callID)
        completedAtMilliseconds = try container.decodeIfPresent(Int64.self, forKey: .completedAtMilliseconds) ?? 0
        senderThreadID = try container.decode(ThreadId.self, forKey: .senderThreadID)
        receiverThreadID = try container.decode(ThreadId.self, forKey: .receiverThreadID)
        receiverAgentNickname = try container.decodeIfPresent(String.self, forKey: .receiverAgentNickname)
        receiverAgentRole = try container.decodeIfPresent(String.self, forKey: .receiverAgentRole)
        status = try container.decode(AgentStatus.self, forKey: .status)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(callID, forKey: .callID)
        try container.encode(completedAtMilliseconds, forKey: .completedAtMilliseconds)
        try container.encode(senderThreadID, forKey: .senderThreadID)
        try container.encode(receiverThreadID, forKey: .receiverThreadID)
        try container.encodeIfPresent(receiverAgentNickname, forKey: .receiverAgentNickname)
        try container.encodeIfPresent(receiverAgentRole, forKey: .receiverAgentRole)
        try container.encode(status, forKey: .status)
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

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue _: Int) {
        nil
    }
}
