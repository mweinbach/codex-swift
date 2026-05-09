import Foundation

public struct DynamicToolSpec: Codable, Equatable, Sendable {
    public let namespace: String?
    public let name: String
    public let description: String
    public let inputSchema: JSONValue
    public let deferLoading: Bool

    private enum CodingKeys: String, CodingKey {
        case namespace
        case name
        case description
        case inputSchema
        case deferLoading
        case exposeToContext
    }

    public init(
        namespace: String? = nil,
        name: String,
        description: String,
        inputSchema: JSONValue,
        deferLoading: Bool = false
    ) {
        self.namespace = namespace
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.deferLoading = deferLoading
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        namespace = try container.decodeIfPresent(String.self, forKey: .namespace)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        inputSchema = try container.decode(JSONValue.self, forKey: .inputSchema)
        if let deferLoading = try container.decodeIfPresent(Bool.self, forKey: .deferLoading) {
            self.deferLoading = deferLoading
        } else if let exposeToContext = try container.decodeIfPresent(Bool.self, forKey: .exposeToContext) {
            self.deferLoading = !exposeToContext
        } else {
            self.deferLoading = false
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(namespace, forKey: .namespace)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(inputSchema, forKey: .inputSchema)
        try container.encode(deferLoading, forKey: .deferLoading)
    }
}

public struct DynamicToolCallRequest: Codable, Equatable, Sendable {
    public let callID: String
    public let turnID: String
    public let startedAtMilliseconds: Int64
    public let namespace: String?
    public let tool: String
    public let arguments: JSONValue

    private enum CodingKeys: String, CodingKey {
        case callID = "callId"
        case turnID = "turnId"
        case startedAtMilliseconds = "startedAtMs"
        case namespace
        case tool
        case arguments
    }

    public init(
        callID: String,
        turnID: String,
        startedAtMilliseconds: Int64 = 0,
        namespace: String? = nil,
        tool: String,
        arguments: JSONValue
    ) {
        self.callID = callID
        self.turnID = turnID
        self.startedAtMilliseconds = startedAtMilliseconds
        self.namespace = namespace
        self.tool = tool
        self.arguments = arguments
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callID = try container.decode(String.self, forKey: .callID)
        turnID = try container.decode(String.self, forKey: .turnID)
        startedAtMilliseconds = try container.decodeIfPresent(Int64.self, forKey: .startedAtMilliseconds) ?? 0
        namespace = try container.decodeIfPresent(String.self, forKey: .namespace)
        tool = try container.decode(String.self, forKey: .tool)
        arguments = try container.decode(JSONValue.self, forKey: .arguments)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(callID, forKey: .callID)
        try container.encode(turnID, forKey: .turnID)
        try container.encode(startedAtMilliseconds, forKey: .startedAtMilliseconds)
        try container.encodeIfPresentOrNull(namespace, forKey: .namespace)
        try container.encode(tool, forKey: .tool)
        try container.encode(arguments, forKey: .arguments)
    }
}

public struct DynamicToolResponse: Codable, Equatable, Sendable {
    public let contentItems: [DynamicToolCallOutputContentItem]
    public let success: Bool

    private enum CodingKeys: String, CodingKey {
        case contentItems
        case success
    }

    public init(contentItems: [DynamicToolCallOutputContentItem], success: Bool) {
        self.contentItems = contentItems
        self.success = success
    }
}

public struct DynamicToolCallResponseEvent: Codable, Equatable, Sendable {
    public let callID: String
    public let turnID: String
    public let completedAtMilliseconds: Int64
    public let namespace: String?
    public let tool: String
    public let arguments: JSONValue
    public let contentItems: [DynamicToolCallOutputContentItem]
    public let success: Bool
    public let error: String?
    public let duration: ProtocolDuration

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case turnID = "turn_id"
        case completedAtMilliseconds = "completed_at_ms"
        case namespace
        case tool
        case arguments
        case contentItems = "content_items"
        case success
        case error
        case duration
    }

    public init(
        callID: String,
        turnID: String,
        completedAtMilliseconds: Int64 = 0,
        namespace: String? = nil,
        tool: String,
        arguments: JSONValue,
        contentItems: [DynamicToolCallOutputContentItem],
        success: Bool,
        error: String? = nil,
        duration: ProtocolDuration
    ) {
        self.callID = callID
        self.turnID = turnID
        self.completedAtMilliseconds = completedAtMilliseconds
        self.namespace = namespace
        self.tool = tool
        self.arguments = arguments
        self.contentItems = contentItems
        self.success = success
        self.error = error
        self.duration = duration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callID = try container.decode(String.self, forKey: .callID)
        turnID = try container.decode(String.self, forKey: .turnID)
        completedAtMilliseconds = try container.decodeIfPresent(Int64.self, forKey: .completedAtMilliseconds) ?? 0
        namespace = try container.decodeIfPresent(String.self, forKey: .namespace)
        tool = try container.decode(String.self, forKey: .tool)
        arguments = try container.decode(JSONValue.self, forKey: .arguments)
        contentItems = try container.decode([DynamicToolCallOutputContentItem].self, forKey: .contentItems)
        success = try container.decode(Bool.self, forKey: .success)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        duration = try container.decode(ProtocolDuration.self, forKey: .duration)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(callID, forKey: .callID)
        try container.encode(turnID, forKey: .turnID)
        try container.encode(completedAtMilliseconds, forKey: .completedAtMilliseconds)
        try container.encodeIfPresentOrNull(namespace, forKey: .namespace)
        try container.encode(tool, forKey: .tool)
        try container.encode(arguments, forKey: .arguments)
        try container.encode(contentItems, forKey: .contentItems)
        try container.encode(success, forKey: .success)
        try container.encodeIfPresentOrNull(error, forKey: .error)
        try container.encode(duration, forKey: .duration)
    }
}

public enum DynamicToolCallOutputContentItem: Codable, Equatable, Sendable {
    case text(String)
    case imageURL(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "imageUrl"
    }

    private enum ItemType: String, Codable {
        case inputText
        case inputImage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ItemType.self, forKey: .type) {
        case .inputText:
            self = .text(try container.decode(String.self, forKey: .text))
        case .inputImage:
            self = .imageURL(try container.decode(String.self, forKey: .imageURL))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try container.encode(ItemType.inputText, forKey: .type)
            try container.encode(text, forKey: .text)
        case let .imageURL(imageURL):
            try container.encode(ItemType.inputImage, forKey: .type)
            try container.encode(imageURL, forKey: .imageURL)
        }
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeIfPresentOrNull<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}
