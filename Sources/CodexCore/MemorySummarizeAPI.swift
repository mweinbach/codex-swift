import Foundation

public struct MemorySummarizeInput: Equatable, Codable, Sendable {
    public var model: String
    public var rawMemories: [RawMemory]
    public var reasoning: ResponsesAPIReasoning?

    private enum CodingKeys: String, CodingKey {
        case model
        case rawMemories = "traces"
        case reasoning
    }

    public init(
        model: String,
        rawMemories: [RawMemory],
        reasoning: ResponsesAPIReasoning? = nil
    ) {
        self.model = model
        self.rawMemories = rawMemories
        self.reasoning = reasoning
    }
}

public struct RawMemory: Equatable, Codable, Sendable {
    public var id: String
    public var metadata: RawMemoryMetadata
    public var items: [JSONValue]

    public init(id: String, metadata: RawMemoryMetadata, items: [JSONValue]) {
        self.id = id
        self.metadata = metadata
        self.items = items
    }
}

public struct RawMemoryMetadata: Equatable, Codable, Sendable {
    public var sourcePath: String

    private enum CodingKeys: String, CodingKey {
        case sourcePath = "source_path"
    }

    public init(sourcePath: String) {
        self.sourcePath = sourcePath
    }
}

public struct MemorySummarizeOutput: Equatable, Codable, Sendable {
    public var rawMemory: String
    public var memorySummary: String

    private enum CodingKeys: String, CodingKey {
        case traceSummary = "trace_summary"
        case rawMemory = "raw_memory"
        case memorySummary = "memory_summary"
    }

    public init(rawMemory: String, memorySummary: String) {
        self.rawMemory = rawMemory
        self.memorySummary = memorySummary
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.rawMemory = try container.decodeAlias(
            primary: .traceSummary,
            fallback: .rawMemory,
            debugDescription: "Expected trace_summary or raw_memory"
        )
        self.memorySummary = try container.decode(String.self, forKey: .memorySummary)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rawMemory, forKey: .traceSummary)
        try container.encode(memorySummary, forKey: .memorySummary)
    }
}

public struct MemorySummarizeResponse: Equatable, Codable, Sendable {
    public var output: [MemorySummarizeOutput]

    public init(output: [MemorySummarizeOutput]) {
        self.output = output
    }
}

public enum MemorySummarizeAPIError: Error, Equatable, CustomStringConvertible, Sendable {
    case encodeMemorySummarizeInput(String)

    public var description: String {
        switch self {
        case let .encodeMemorySummarizeInput(message):
            return "failed to encode memory summarize input: \(message)"
        }
    }
}

public enum MemorySummarizeAPI {
    public static let path = "memories/trace_summarize"

    public static func body(for input: MemorySummarizeInput) throws -> JSONValue {
        do {
            let data = try JSONEncoder().encode(input)
            return try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw MemorySummarizeAPIError.encodeMemorySummarizeInput(String(describing: error))
        }
    }
}

private extension KeyedDecodingContainer {
    func decodeAlias(
        primary: Key,
        fallback: Key,
        debugDescription: String
    ) throws -> String {
        if let value = try decodeIfPresent(String.self, forKey: primary) {
            return value
        }
        if let value = try decodeIfPresent(String.self, forKey: fallback) {
            return value
        }
        throw DecodingError.keyNotFound(
            primary,
            DecodingError.Context(
                codingPath: codingPath + [primary],
                debugDescription: debugDescription
            )
        )
    }
}
