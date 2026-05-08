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

public struct AgentReasoningEvent: Equatable, Codable, Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

public struct AgentReasoningRawContentEvent: Equatable, Codable, Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
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

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case query
    }

    public init(callID: String, query: String) {
        self.callID = callID
        self.query = query
    }
}

public enum LegacyEventMessage: Equatable, Codable, Sendable {
    case agentMessage(AgentMessageEvent)
    case userMessage(UserMessageEvent)
    case agentReasoning(AgentReasoningEvent)
    case agentReasoningRawContent(AgentReasoningRawContentEvent)
    case webSearchBegin(WebSearchBeginEvent)
    case webSearchEnd(WebSearchEndEvent)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    private enum EventType: String, Codable {
        case agentMessage = "agent_message"
        case userMessage = "user_message"
        case agentReasoning = "agent_reasoning"
        case agentReasoningRawContent = "agent_reasoning_raw_content"
        case webSearchBegin = "web_search_begin"
        case webSearchEnd = "web_search_end"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(EventType.self, forKey: .type) {
        case .agentMessage:
            self = .agentMessage(try AgentMessageEvent(from: decoder))
        case .userMessage:
            self = .userMessage(try UserMessageEvent(from: decoder))
        case .agentReasoning:
            self = .agentReasoning(try AgentReasoningEvent(from: decoder))
        case .agentReasoningRawContent:
            self = .agentReasoningRawContent(try AgentReasoningRawContentEvent(from: decoder))
        case .webSearchBegin:
            self = .webSearchBegin(try WebSearchBeginEvent(from: decoder))
        case .webSearchEnd:
            self = .webSearchEnd(try WebSearchEndEvent(from: decoder))
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
        case let .agentReasoning(event):
            try container.encode(EventType.agentReasoning, forKey: .type)
            try event.encode(to: encoder)
        case let .agentReasoningRawContent(event):
            try container.encode(EventType.agentReasoningRawContent, forKey: .type)
            try event.encode(to: encoder)
        case let .webSearchBegin(event):
            try container.encode(EventType.webSearchBegin, forKey: .type)
            try event.encode(to: encoder)
        case let .webSearchEnd(event):
            try container.encode(EventType.webSearchEnd, forKey: .type)
            try event.encode(to: encoder)
        }
    }
}
