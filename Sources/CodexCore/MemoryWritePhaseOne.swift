import Foundation

public struct MemoryStageOneOutput: Equatable, Decodable, Sendable {
    public let rawMemory: String
    public let rolloutSummary: String
    public let rolloutSlug: String?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case rawMemory = "raw_memory"
        case rolloutSummary = "rollout_summary"
        case rolloutSlug = "rollout_slug"
    }

    public init(rawMemory: String, rolloutSummary: String, rolloutSlug: String?) {
        self.rawMemory = rawMemory
        self.rolloutSummary = rolloutSummary
        self.rolloutSlug = rolloutSlug
    }

    public init(from decoder: Decoder) throws {
        let dynamicContainer = try decoder.container(keyedBy: MemoryStageOneOutputDynamicCodingKey.self)
        let knownKeys = Set(CodingKeys.allCases.map(\.stringValue))
        let unknownKeys = Set(dynamicContainer.allKeys.map(\.stringValue)).subtracting(knownKeys)
        if let unknownKey = unknownKeys.sorted().first {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "unknown field `\(unknownKey)`"
                )
            )
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        rawMemory = try container.decode(String.self, forKey: .rawMemory)
        rolloutSummary = try container.decode(String.self, forKey: .rolloutSummary)
        rolloutSlug = try container.decodeIfPresent(String.self, forKey: .rolloutSlug)
    }
}

private struct MemoryStageOneOutputDynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

public enum MemoryWritePhaseOneError: Error, Equatable, CustomStringConvertible, Sendable {
    case serializeRolloutMemory(String)

    public var description: String {
        switch self {
        case let .serializeRolloutMemory(message):
            return "failed to serialize rollout memory: \(message)"
        }
    }
}

public func memoryStageOneOutputSchema() -> JSONValue {
    .object([
        "type": .string("object"),
        "properties": .object([
            "rollout_summary": .object(["type": .string("string")]),
            "rollout_slug": .object(["type": .array([.string("string"), .string("null")])]),
            "raw_memory": .object(["type": .string("string")])
        ]),
        "required": .array([
            .string("rollout_summary"),
            .string("rollout_slug"),
            .string("raw_memory")
        ]),
        "additionalProperties": .bool(false)
    ])
}

public func serializeFilteredRolloutResponseItemsForMemories(_ items: [RolloutItem]) throws -> String {
    let filtered = items.compactMap { item -> ResponseItem? in
        guard case let .responseItem(responseItem) = item else {
            return nil
        }
        return sanitizeResponseItemForMemories(responseItem)
    }

    do {
        let data = try JSONEncoder().encode(filtered)
        guard let json = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(
                filtered,
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "encoded rollout memory was not valid UTF-8"
                )
            )
        }
        return redactSecretsForMemories(json)
    } catch {
        throw MemoryWritePhaseOneError.serializeRolloutMemory(String(describing: error))
    }
}

func sanitizeResponseItemForMemories(_ item: ResponseItem) -> ResponseItem? {
    switch item {
    case let .message(id, role, content, phase):
        if role == "developer" {
            return nil
        }
        if role != "user" {
            return item
        }

        let filteredContent = content.filter { !isMemoryExcludedContextualUserFragment($0) }
        if filteredContent.isEmpty {
            return nil
        }
        return .message(id: id, role: role, content: filteredContent, phase: phase)

    default:
        return RolloutPolicy.shouldPersistResponseItemForMemories(item) ? item : nil
    }
}

func isMemoryExcludedContextualUserFragment(_ item: ContentItem) -> Bool {
    guard case let .inputText(text) = item else {
        return false
    }
    return UserInstructions.matchesText(text) || SkillInstructions.matchesText(text)
}

private func redactSecretsForMemories(_ input: String) -> String {
    input.replacing(
        /sk-[A-Za-z0-9]{20,}/,
        with: "[REDACTED_SECRET]"
    )
}
