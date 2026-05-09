import Foundation

public struct AgentMessageEvent: Equatable, Codable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

public struct UserMessageEvent: Equatable, Codable, Sendable {
    public let message: String
    public let images: [String]?

    private enum CodingKeys: String, CodingKey {
        case message
        case images
    }

    public init(message: String, images: [String]? = nil) {
        self.message = message
        self.images = images
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.message = try container.decode(String.self, forKey: .message)
        self.images = try container.decodeIfPresent([String].self, forKey: .images)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(message, forKey: .message)
        try container.encodeIfPresent(images, forKey: .images)
    }
}

public struct AgentMessageDeltaEvent: Equatable, Codable, Sendable {
    public let delta: String

    public init(delta: String) {
        self.delta = delta
    }
}

public struct AgentReasoningEvent: Equatable, Codable, Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

public struct AgentReasoningDeltaEvent: Equatable, Codable, Sendable {
    public let delta: String

    public init(delta: String) {
        self.delta = delta
    }
}

public struct AgentReasoningRawContentEvent: Equatable, Codable, Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

public struct AgentReasoningRawContentDeltaEvent: Equatable, Codable, Sendable {
    public let delta: String

    public init(delta: String) {
        self.delta = delta
    }
}

public struct AgentReasoningSectionBreakEvent: Equatable, Codable, Sendable {
    public let itemID: String
    public let summaryIndex: Int64

    private enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case summaryIndex = "summary_index"
    }

    public init(itemID: String = "", summaryIndex: Int64 = 0) {
        self.itemID = itemID
        self.summaryIndex = summaryIndex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.itemID = try container.decodeIfPresent(String.self, forKey: .itemID) ?? ""
        self.summaryIndex = try container.decodeIfPresent(Int64.self, forKey: .summaryIndex) ?? 0
    }
}

public struct WebSearchBeginEvent: Equatable, Codable, Sendable {
    public let callID: String

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
    }

    public init(callID: String) {
        self.callID = callID
    }
}

public struct WebSearchEndEvent: Equatable, Codable, Sendable {
    public let callID: String
    public let query: String
    public let action: WebSearchAction

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case query
        case action
    }

    public init(callID: String, query: String, action: WebSearchAction? = nil) {
        self.callID = callID
        self.query = query
        self.action = action ?? .search(query: query)
    }
}

public struct ImageGenerationBeginEvent: Equatable, Codable, Sendable {
    public let callID: String

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
    }

    public init(callID: String) {
        self.callID = callID
    }
}

public struct ImageGenerationEndEvent: Equatable, Codable, Sendable {
    public let callID: String
    public let status: String
    public let revisedPrompt: String?
    public let result: String
    public let savedPath: AbsolutePath?

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case status
        case revisedPrompt = "revised_prompt"
        case result
        case savedPath = "saved_path"
    }

    public init(
        callID: String,
        status: String,
        revisedPrompt: String? = nil,
        result: String,
        savedPath: AbsolutePath? = nil
    ) {
        self.callID = callID
        self.status = status
        self.revisedPrompt = revisedPrompt
        self.result = result
        self.savedPath = savedPath
    }
}

public struct AgentMessageContentDeltaEvent: Equatable, Codable, Sendable {
    public let threadID: String
    public let turnID: String
    public let itemID: String
    public let delta: String

    private enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case turnID = "turn_id"
        case itemID = "item_id"
        case delta
    }

    public init(threadID: String, turnID: String, itemID: String, delta: String) {
        self.threadID = threadID
        self.turnID = turnID
        self.itemID = itemID
        self.delta = delta
    }

    public func asLegacyEvents() -> [LegacyEventMessage] {
        [.agentMessageDelta(AgentMessageDeltaEvent(delta: delta))]
    }
}

public struct ReasoningContentDeltaEvent: Equatable, Codable, Sendable {
    public let threadID: String
    public let turnID: String
    public let itemID: String
    public let delta: String
    public let summaryIndex: Int64

    private enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case turnID = "turn_id"
        case itemID = "item_id"
        case delta
        case summaryIndex = "summary_index"
    }

    public init(threadID: String, turnID: String, itemID: String, delta: String, summaryIndex: Int64 = 0) {
        self.threadID = threadID
        self.turnID = turnID
        self.itemID = itemID
        self.delta = delta
        self.summaryIndex = summaryIndex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.threadID = try container.decode(String.self, forKey: .threadID)
        self.turnID = try container.decode(String.self, forKey: .turnID)
        self.itemID = try container.decode(String.self, forKey: .itemID)
        self.delta = try container.decode(String.self, forKey: .delta)
        self.summaryIndex = try container.decodeIfPresent(Int64.self, forKey: .summaryIndex) ?? 0
    }

    public func asLegacyEvents() -> [LegacyEventMessage] {
        [.agentReasoningDelta(AgentReasoningDeltaEvent(delta: delta))]
    }
}

public struct ReasoningRawContentDeltaEvent: Equatable, Codable, Sendable {
    public let threadID: String
    public let turnID: String
    public let itemID: String
    public let delta: String
    public let contentIndex: Int64

    private enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case turnID = "turn_id"
        case itemID = "item_id"
        case delta
        case contentIndex = "content_index"
    }

    public init(threadID: String, turnID: String, itemID: String, delta: String, contentIndex: Int64 = 0) {
        self.threadID = threadID
        self.turnID = turnID
        self.itemID = itemID
        self.delta = delta
        self.contentIndex = contentIndex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.threadID = try container.decode(String.self, forKey: .threadID)
        self.turnID = try container.decode(String.self, forKey: .turnID)
        self.itemID = try container.decode(String.self, forKey: .itemID)
        self.delta = try container.decode(String.self, forKey: .delta)
        self.contentIndex = try container.decodeIfPresent(Int64.self, forKey: .contentIndex) ?? 0
    }

    public func asLegacyEvents() -> [LegacyEventMessage] {
        [.agentReasoningRawContentDelta(AgentReasoningRawContentDeltaEvent(delta: delta))]
    }
}

public enum LegacyEventMessage: Equatable, Codable, Sendable {
    case agentMessage(AgentMessageEvent)
    case userMessage(UserMessageEvent)
    case agentMessageDelta(AgentMessageDeltaEvent)
    case agentReasoning(AgentReasoningEvent)
    case agentReasoningDelta(AgentReasoningDeltaEvent)
    case agentReasoningRawContent(AgentReasoningRawContentEvent)
    case agentReasoningRawContentDelta(AgentReasoningRawContentDeltaEvent)
    case agentReasoningSectionBreak(AgentReasoningSectionBreakEvent)
    case webSearchBegin(WebSearchBeginEvent)
    case webSearchEnd(WebSearchEndEvent)
    case viewImageToolCall(ViewImageToolCallEvent)
    case imageGenerationBegin(ImageGenerationBeginEvent)
    case imageGenerationEnd(ImageGenerationEndEvent)
    case contextCompacted(ContextCompactedEvent)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    private enum EventType: String, Codable {
        case agentMessage = "agent_message"
        case userMessage = "user_message"
        case agentMessageDelta = "agent_message_delta"
        case agentReasoning = "agent_reasoning"
        case agentReasoningDelta = "agent_reasoning_delta"
        case agentReasoningRawContent = "agent_reasoning_raw_content"
        case agentReasoningRawContentDelta = "agent_reasoning_raw_content_delta"
        case agentReasoningSectionBreak = "agent_reasoning_section_break"
        case webSearchBegin = "web_search_begin"
        case webSearchEnd = "web_search_end"
        case viewImageToolCall = "view_image_tool_call"
        case imageGenerationBegin = "image_generation_begin"
        case imageGenerationEnd = "image_generation_end"
        case contextCompacted = "context_compacted"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(EventType.self, forKey: .type) {
        case .agentMessage:
            self = .agentMessage(try AgentMessageEvent(from: decoder))
        case .userMessage:
            self = .userMessage(try UserMessageEvent(from: decoder))
        case .agentMessageDelta:
            self = .agentMessageDelta(try AgentMessageDeltaEvent(from: decoder))
        case .agentReasoning:
            self = .agentReasoning(try AgentReasoningEvent(from: decoder))
        case .agentReasoningDelta:
            self = .agentReasoningDelta(try AgentReasoningDeltaEvent(from: decoder))
        case .agentReasoningRawContent:
            self = .agentReasoningRawContent(try AgentReasoningRawContentEvent(from: decoder))
        case .agentReasoningRawContentDelta:
            self = .agentReasoningRawContentDelta(try AgentReasoningRawContentDeltaEvent(from: decoder))
        case .agentReasoningSectionBreak:
            self = .agentReasoningSectionBreak(try AgentReasoningSectionBreakEvent(from: decoder))
        case .webSearchBegin:
            self = .webSearchBegin(try WebSearchBeginEvent(from: decoder))
        case .webSearchEnd:
            self = .webSearchEnd(try WebSearchEndEvent(from: decoder))
        case .viewImageToolCall:
            self = .viewImageToolCall(try ViewImageToolCallEvent(from: decoder))
        case .imageGenerationBegin:
            self = .imageGenerationBegin(try ImageGenerationBeginEvent(from: decoder))
        case .imageGenerationEnd:
            self = .imageGenerationEnd(try ImageGenerationEndEvent(from: decoder))
        case .contextCompacted:
            self = .contextCompacted(try ContextCompactedEvent(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .agentMessage(event):
            try container.encode(EventType.agentMessage, forKey: .type)
            try event.encode(to: encoder)
        case let .userMessage(event):
            try container.encode(EventType.userMessage, forKey: .type)
            try event.encode(to: encoder)
        case let .agentMessageDelta(event):
            try container.encode(EventType.agentMessageDelta, forKey: .type)
            try event.encode(to: encoder)
        case let .agentReasoning(event):
            try container.encode(EventType.agentReasoning, forKey: .type)
            try event.encode(to: encoder)
        case let .agentReasoningDelta(event):
            try container.encode(EventType.agentReasoningDelta, forKey: .type)
            try event.encode(to: encoder)
        case let .agentReasoningRawContent(event):
            try container.encode(EventType.agentReasoningRawContent, forKey: .type)
            try event.encode(to: encoder)
        case let .agentReasoningRawContentDelta(event):
            try container.encode(EventType.agentReasoningRawContentDelta, forKey: .type)
            try event.encode(to: encoder)
        case let .agentReasoningSectionBreak(event):
            try container.encode(EventType.agentReasoningSectionBreak, forKey: .type)
            try event.encode(to: encoder)
        case let .webSearchBegin(event):
            try container.encode(EventType.webSearchBegin, forKey: .type)
            try event.encode(to: encoder)
        case let .webSearchEnd(event):
            try container.encode(EventType.webSearchEnd, forKey: .type)
            try event.encode(to: encoder)
        case let .viewImageToolCall(event):
            try container.encode(EventType.viewImageToolCall, forKey: .type)
            try event.encode(to: encoder)
        case let .imageGenerationBegin(event):
            try container.encode(EventType.imageGenerationBegin, forKey: .type)
            try event.encode(to: encoder)
        case let .imageGenerationEnd(event):
            try container.encode(EventType.imageGenerationEnd, forKey: .type)
            try event.encode(to: encoder)
        case let .contextCompacted(event):
            try container.encode(EventType.contextCompacted, forKey: .type)
            try event.encode(to: encoder)
        }
    }
}
