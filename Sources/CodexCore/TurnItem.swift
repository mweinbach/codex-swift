import Foundation

public enum TurnItem: Equatable, Codable, Sendable {
    case userMessage(UserMessageItem)
    case agentMessage(AgentMessageItem)
    case plan(PlanItem)
    case reasoning(ReasoningItem)
    case webSearch(WebSearchItem)
    case imageGeneration(ImageGenerationItem)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    private enum ItemType: String, Codable {
        case userMessage = "UserMessage"
        case agentMessage = "AgentMessage"
        case plan = "Plan"
        case reasoning = "Reasoning"
        case webSearch = "WebSearch"
        case imageGeneration = "ImageGeneration"
    }

    public var id: String {
        switch self {
        case let .userMessage(item):
            return item.id
        case let .agentMessage(item):
            return item.id
        case let .plan(item):
            return item.id
        case let .reasoning(item):
            return item.id
        case let .webSearch(item):
            return item.id
        case let .imageGeneration(item):
            return item.id
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ItemType.self, forKey: .type) {
        case .userMessage:
            self = .userMessage(try UserMessageItem(from: decoder))
        case .agentMessage:
            self = .agentMessage(try AgentMessageItem(from: decoder))
        case .plan:
            self = .plan(try PlanItem(from: decoder))
        case .reasoning:
            self = .reasoning(try ReasoningItem(from: decoder))
        case .webSearch:
            self = .webSearch(try WebSearchItem(from: decoder))
        case .imageGeneration:
            self = .imageGeneration(try ImageGenerationItem(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .userMessage(item):
            try container.encode(ItemType.userMessage, forKey: .type)
            try item.encode(to: encoder)
        case let .agentMessage(item):
            try container.encode(ItemType.agentMessage, forKey: .type)
            try item.encode(to: encoder)
        case let .plan(item):
            try container.encode(ItemType.plan, forKey: .type)
            try item.encode(to: encoder)
        case let .reasoning(item):
            try container.encode(ItemType.reasoning, forKey: .type)
            try item.encode(to: encoder)
        case let .webSearch(item):
            try container.encode(ItemType.webSearch, forKey: .type)
            try item.encode(to: encoder)
        case let .imageGeneration(item):
            try container.encode(ItemType.imageGeneration, forKey: .type)
            try item.encode(to: encoder)
        }
    }

    public func asLegacyEvents(showRawAgentReasoning: Bool) -> [LegacyEventMessage] {
        switch self {
        case let .userMessage(item):
            return [item.asLegacyEvent()]
        case let .agentMessage(item):
            return item.asLegacyEvents()
        case .plan:
            return []
        case let .reasoning(item):
            return item.asLegacyEvents(showRawAgentReasoning: showRawAgentReasoning)
        case let .webSearch(item):
            return [item.asLegacyEvent()]
        case let .imageGeneration(item):
            return [item.asLegacyEvent()]
        }
    }
}

public struct PlanItem: Equatable, Codable, Sendable {
    public let id: String
    public let text: String

    public init(id: String = UUID().uuidString.lowercased(), text: String) {
        self.id = id
        self.text = text
    }
}

public struct UserMessageItem: Equatable, Codable, Sendable {
    public let id: String
    public let content: [UserInput]

    public init(id: String = UUID().uuidString.lowercased(), content: [UserInput]) {
        self.id = id
        self.content = content
    }

    public var message: String {
        content.map { input in
            if case let .text(text) = input {
                return text
            }
            return ""
        }.joined()
    }

    public var imageURLs: [String] {
        content.compactMap { input in
            if case let .image(imageURL) = input {
                return imageURL
            }
            return nil
        }
    }

    public func asLegacyEvent() -> LegacyEventMessage {
        .userMessage(UserMessageEvent(message: message, images: imageURLs))
    }
}

public enum AgentMessageContent: Equatable, Codable, Sendable {
    case text(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
    }

    private enum ContentType: String, Codable {
        case text = "Text"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ContentType.self, forKey: .type) {
        case .text:
            self = .text(try container.decode(String.self, forKey: .text))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try container.encode(ContentType.text, forKey: .type)
            try container.encode(text, forKey: .text)
        }
    }
}

public struct AgentMessageItem: Equatable, Codable, Sendable {
    public let id: String
    public let content: [AgentMessageContent]
    public let phase: MessagePhase?
    public let memoryCitation: MemoryCitation?

    private enum CodingKeys: String, CodingKey {
        case id
        case content
        case phase
        case memoryCitation = "memory_citation"
    }

    public init(
        id: String = UUID().uuidString.lowercased(),
        content: [AgentMessageContent],
        phase: MessagePhase? = nil,
        memoryCitation: MemoryCitation? = nil
    ) {
        self.id = id
        self.content = content
        self.phase = phase
        self.memoryCitation = memoryCitation
    }

    public func asLegacyEvents() -> [LegacyEventMessage] {
        content.map { content in
            switch content {
            case let .text(text):
                return .agentMessage(AgentMessageEvent(message: text))
            }
        }
    }
}

public struct ReasoningItem: Equatable, Codable, Sendable {
    public let id: String
    public let summaryText: [String]
    public let rawContent: [String]

    private enum CodingKeys: String, CodingKey {
        case id
        case summaryText = "summary_text"
        case rawContent = "raw_content"
    }

    public init(id: String = UUID().uuidString.lowercased(), summaryText: [String], rawContent: [String] = []) {
        self.id = id
        self.summaryText = summaryText
        self.rawContent = rawContent
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.summaryText = try container.decode([String].self, forKey: .summaryText)
        self.rawContent = try container.decodeIfPresent([String].self, forKey: .rawContent) ?? []
    }

    public func asLegacyEvents(showRawAgentReasoning: Bool) -> [LegacyEventMessage] {
        var events = summaryText.map { summary in
            LegacyEventMessage.agentReasoning(AgentReasoningEvent(text: summary))
        }

        if showRawAgentReasoning {
            events += rawContent.map { entry in
                LegacyEventMessage.agentReasoningRawContent(AgentReasoningRawContentEvent(text: entry))
            }
        }

        return events
    }
}

public struct WebSearchItem: Equatable, Codable, Sendable {
    public let id: String
    public let query: String
    public let action: WebSearchAction

    public init(id: String, query: String, action: WebSearchAction? = nil) {
        self.id = id
        self.query = query
        self.action = action ?? .search(query: query)
    }

    public func asLegacyEvent() -> LegacyEventMessage {
        .webSearchEnd(WebSearchEndEvent(callID: id, query: query, action: action))
    }
}

public struct ImageGenerationItem: Equatable, Codable, Sendable {
    public let id: String
    public let status: String
    public let revisedPrompt: String?
    public let result: String
    public let savedPath: AbsolutePath?

    private enum CodingKeys: String, CodingKey {
        case id
        case status
        case revisedPrompt = "revised_prompt"
        case result
        case savedPath = "saved_path"
    }

    public init(
        id: String,
        status: String,
        revisedPrompt: String? = nil,
        result: String,
        savedPath: AbsolutePath? = nil
    ) {
        self.id = id
        self.status = status
        self.revisedPrompt = revisedPrompt
        self.result = result
        self.savedPath = savedPath
    }

    public func asLegacyEvent() -> LegacyEventMessage {
        .imageGenerationEnd(ImageGenerationEndEvent(
            callID: id,
            status: status,
            revisedPrompt: revisedPrompt,
            result: result,
            savedPath: savedPath
        ))
    }
}

public struct ItemStartedEvent: Equatable, Codable, Sendable {
    public let threadID: ConversationId
    public let turnID: String
    public let item: TurnItem
    public let startedAtMilliseconds: Int64

    private enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case turnID = "turn_id"
        case item
        case startedAtMilliseconds = "started_at_ms"
    }

    public init(threadID: ConversationId, turnID: String, item: TurnItem, startedAtMilliseconds: Int64 = 0) {
        self.threadID = threadID
        self.turnID = turnID
        self.item = item
        self.startedAtMilliseconds = startedAtMilliseconds
    }

    public func asLegacyEvents(showRawAgentReasoning _: Bool = false) -> [LegacyEventMessage] {
        switch item {
        case let .webSearch(item):
            return [.webSearchBegin(WebSearchBeginEvent(callID: item.id))]
        case let .imageGeneration(item):
            return [.imageGenerationBegin(ImageGenerationBeginEvent(callID: item.id))]
        default:
            return []
        }
    }
}

public struct ItemCompletedEvent: Equatable, Codable, Sendable {
    public let threadID: ConversationId
    public let turnID: String
    public let item: TurnItem
    public let completedAtMilliseconds: Int64

    private enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case turnID = "turn_id"
        case item
        case completedAtMilliseconds = "completed_at_ms"
    }

    public init(threadID: ConversationId, turnID: String, item: TurnItem, completedAtMilliseconds: Int64 = 0) {
        self.threadID = threadID
        self.turnID = turnID
        self.item = item
        self.completedAtMilliseconds = completedAtMilliseconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.threadID = try container.decode(ConversationId.self, forKey: .threadID)
        self.turnID = try container.decode(String.self, forKey: .turnID)
        self.item = try container.decode(TurnItem.self, forKey: .item)
        self.completedAtMilliseconds = try container.decodeIfPresent(Int64.self, forKey: .completedAtMilliseconds) ?? 0
    }

    public func asLegacyEvents(showRawAgentReasoning: Bool) -> [LegacyEventMessage] {
        item.asLegacyEvents(showRawAgentReasoning: showRawAgentReasoning)
    }
}
