public struct FeedbackUploadParams: Equatable, Sendable {
    public let classification: String
    public let reason: String?
    public let threadID: String?
    public let includeLogs: Bool
    public let extraLogFiles: [String]?
    public let tags: [String: String]?

    private enum CodingKeys: String, CodingKey {
        case classification
        case reason
        case threadID = "threadId"
        case includeLogs
        case extraLogFiles
        case tags
    }

    public init(
        classification: String,
        reason: String? = nil,
        threadID: String? = nil,
        includeLogs: Bool,
        extraLogFiles: [String]? = nil,
        tags: [String: String]? = nil
    ) {
        self.classification = classification
        self.reason = reason
        self.threadID = threadID
        self.includeLogs = includeLogs
        self.extraLogFiles = extraLogFiles
        self.tags = tags
    }
}

extension FeedbackUploadParams: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        classification = try container.decode(String.self, forKey: .classification)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        threadID = try container.decodeIfPresent(String.self, forKey: .threadID)
        includeLogs = try container.decode(Bool.self, forKey: .includeLogs)
        extraLogFiles = try container.decodeIfPresent([String].self, forKey: .extraLogFiles)
        tags = try container.decodeIfPresent([String: String].self, forKey: .tags)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(classification, forKey: .classification)
        try container.encodeNilOrValue(reason, forKey: .reason)
        try container.encodeNilOrValue(threadID, forKey: .threadID)
        try container.encode(includeLogs, forKey: .includeLogs)
        try container.encodeNilOrValue(extraLogFiles, forKey: .extraLogFiles)
        try container.encodeNilOrValue(tags, forKey: .tags)
    }
}

public struct FeedbackUploadResponse: Equatable, Codable, Sendable {
    public let threadID: String

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
    }

    public init(threadID: String) {
        self.threadID = threadID
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
