import Foundation

public struct CompactionInput: Equatable, Codable, Sendable {
    public var model: String
    public var input: [ResponseItem]
    public var instructions: String
    public var tools: [JSONValue]
    public var parallelToolCalls: Bool
    public var reasoning: ResponsesAPIReasoning?
    public var serviceTier: String?
    public var promptCacheKey: String?
    public var text: ResponsesAPITextControls?

    private enum CodingKeys: String, CodingKey {
        case model
        case input
        case instructions
        case tools
        case parallelToolCalls = "parallel_tool_calls"
        case reasoning
        case serviceTier = "service_tier"
        case promptCacheKey = "prompt_cache_key"
        case text
    }

    public init(
        model: String,
        input: [ResponseItem],
        instructions: String,
        tools: [JSONValue] = [],
        parallelToolCalls: Bool = false,
        reasoning: ResponsesAPIReasoning? = nil,
        serviceTier: String? = nil,
        promptCacheKey: String? = nil,
        text: ResponsesAPITextControls? = nil
    ) {
        self.model = model
        self.input = input
        self.instructions = instructions
        self.tools = tools
        self.parallelToolCalls = parallelToolCalls
        self.reasoning = reasoning
        self.serviceTier = serviceTier
        self.promptCacheKey = promptCacheKey
        self.text = text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.model = try container.decode(String.self, forKey: .model)
        self.input = try container.decode([ResponseItem].self, forKey: .input)
        self.instructions = try container.decodeIfPresent(String.self, forKey: .instructions) ?? ""
        self.tools = try container.decodeIfPresent([JSONValue].self, forKey: .tools) ?? []
        self.parallelToolCalls = try container.decodeIfPresent(Bool.self, forKey: .parallelToolCalls) ?? false
        self.reasoning = try container.decodeIfPresent(ResponsesAPIReasoning.self, forKey: .reasoning)
        self.serviceTier = try container.decodeIfPresent(String.self, forKey: .serviceTier)
        self.promptCacheKey = try container.decodeIfPresent(String.self, forKey: .promptCacheKey)
        self.text = try container.decodeIfPresent(ResponsesAPITextControls.self, forKey: .text)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(input, forKey: .input)
        if !instructions.isEmpty {
            try container.encode(instructions, forKey: .instructions)
        }
        try container.encode(tools, forKey: .tools)
        try container.encode(parallelToolCalls, forKey: .parallelToolCalls)
        try container.encodeIfPresent(reasoning, forKey: .reasoning)
        try container.encodeIfPresent(serviceTier, forKey: .serviceTier)
        try container.encodeIfPresent(promptCacheKey, forKey: .promptCacheKey)
        try container.encodeIfPresent(text, forKey: .text)
    }
}

public struct CompactHistoryResponse: Equatable, Codable, Sendable {
    public var output: [ResponseItem]

    public init(output: [ResponseItem]) {
        self.output = output
    }
}

public enum CompactAPIError: Error, Equatable, CustomStringConvertible, Sendable {
    case requiresResponsesWireAPI
    case encodeCompactionInput(String)

    public var description: String {
        switch self {
        case .requiresResponsesWireAPI:
            return "compact endpoint requires responses wire api"
        case let .encodeCompactionInput(message):
            return "failed to encode compaction input: \(message)"
        }
    }
}

public enum CompactAPI {
    public static let path = "responses/compact"

    public static func path(for provider: APIProvider) throws -> String {
        switch provider.wireAPI {
        case .responses,
             .compact:
            return path
        case .chat:
            throw CompactAPIError.requiresResponsesWireAPI
        }
    }

    public static func body(for input: CompactionInput) throws -> JSONValue {
        do {
            let data = try JSONEncoder().encode(input)
            return try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw CompactAPIError.encodeCompactionInput(String(describing: error))
        }
    }
}
