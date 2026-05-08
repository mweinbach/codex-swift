import Foundation

public struct GetHistoryEntryResponseEvent: Equatable, Codable, Sendable {
    public let offset: Int
    public let logID: UInt64
    public let entry: HistoryEntry?

    private enum CodingKeys: String, CodingKey {
        case offset
        case logID = "log_id"
        case entry
    }

    public init(offset: Int, logID: UInt64, entry: HistoryEntry? = nil) {
        self.offset = offset
        self.logID = logID
        self.entry = entry
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.offset = try container.decode(Int.self, forKey: .offset)
        self.logID = try container.decode(UInt64.self, forKey: .logID)
        self.entry = try container.decodeIfPresent(HistoryEntry.self, forKey: .entry)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(offset, forKey: .offset)
        try container.encode(logID, forKey: .logID)
        try container.encodeIfPresent(entry, forKey: .entry)
    }
}

public struct ListCustomPromptsResponseEvent: Equatable, Codable, Sendable {
    public let customPrompts: [CustomPrompt]

    private enum CodingKeys: String, CodingKey {
        case customPrompts = "custom_prompts"
    }

    public init(customPrompts: [CustomPrompt]) {
        self.customPrompts = customPrompts
    }
}

public struct RawResponseItemEvent: Equatable, Codable, Sendable {
    public let item: ResponseItem

    public init(item: ResponseItem) {
        self.item = item
    }
}
