public struct FuzzyFileSearchParams: Equatable, Sendable {
    public let query: String
    public let roots: [String]
    public let cancellationToken: String?

    public init(query: String, roots: [String], cancellationToken: String? = nil) {
        self.query = query
        self.roots = roots
        self.cancellationToken = cancellationToken
    }
}

extension FuzzyFileSearchParams: Codable {
    private enum CodingKeys: String, CodingKey {
        case query
        case roots
        case cancellationToken
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(query, forKey: .query)
        try container.encode(roots, forKey: .roots)
        try container.encodeNilOrValue(cancellationToken, forKey: .cancellationToken)
    }
}

public enum FuzzyFileSearchMatchType: String, Codable, Equatable, Sendable {
    case file
    case directory
}

public struct FuzzyFileSearchResult: Equatable, Sendable {
    public let root: String
    public let path: String
    public let matchType: FuzzyFileSearchMatchType
    public let fileName: String
    public let score: UInt32
    public let indices: [UInt32]?

    public init(
        root: String,
        path: String,
        matchType: FuzzyFileSearchMatchType,
        fileName: String,
        score: UInt32,
        indices: [UInt32]? = nil
    ) {
        self.root = root
        self.path = path
        self.matchType = matchType
        self.fileName = fileName
        self.score = score
        self.indices = indices
    }
}

extension FuzzyFileSearchResult: Codable {
    private enum CodingKeys: String, CodingKey {
        case root
        case path
        case matchType = "match_type"
        case fileName = "file_name"
        case score
        case indices
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(root, forKey: .root)
        try container.encode(path, forKey: .path)
        try container.encode(matchType, forKey: .matchType)
        try container.encode(fileName, forKey: .fileName)
        try container.encode(score, forKey: .score)
        try container.encodeNilOrValue(indices, forKey: .indices)
    }
}

public struct FuzzyFileSearchResponse: Equatable, Codable, Sendable {
    public let files: [FuzzyFileSearchResult]

    public init(files: [FuzzyFileSearchResult]) {
        self.files = files
    }
}

public struct FuzzyFileSearchSessionStartParams: Equatable, Codable, Sendable {
    public let sessionID: String
    public let roots: [String]

    private enum CodingKeys: String, CodingKey {
        case sessionID = "sessionId"
        case roots
    }

    public init(sessionID: String, roots: [String]) {
        self.sessionID = sessionID
        self.roots = roots
    }
}

public struct FuzzyFileSearchSessionStartResponse: Equatable, Codable, Sendable {
    public init() {}
}

public struct FuzzyFileSearchSessionUpdateParams: Equatable, Codable, Sendable {
    public let sessionID: String
    public let query: String

    private enum CodingKeys: String, CodingKey {
        case sessionID = "sessionId"
        case query
    }

    public init(sessionID: String, query: String) {
        self.sessionID = sessionID
        self.query = query
    }
}

public struct FuzzyFileSearchSessionUpdateResponse: Equatable, Codable, Sendable {
    public init() {}
}

public struct FuzzyFileSearchSessionStopParams: Equatable, Codable, Sendable {
    public let sessionID: String

    private enum CodingKeys: String, CodingKey {
        case sessionID = "sessionId"
    }

    public init(sessionID: String) {
        self.sessionID = sessionID
    }
}

public struct FuzzyFileSearchSessionStopResponse: Equatable, Codable, Sendable {
    public init() {}
}

public struct FuzzyFileSearchSessionUpdatedNotification: Equatable, Codable, Sendable {
    public let sessionID: String
    public let query: String
    public let files: [FuzzyFileSearchResult]

    private enum CodingKeys: String, CodingKey {
        case sessionID = "sessionId"
        case query
        case files
    }

    public init(sessionID: String, query: String, files: [FuzzyFileSearchResult]) {
        self.sessionID = sessionID
        self.query = query
        self.files = files
    }
}

public struct FuzzyFileSearchSessionCompletedNotification: Equatable, Codable, Sendable {
    public let sessionID: String

    private enum CodingKeys: String, CodingKey {
        case sessionID = "sessionId"
    }

    public init(sessionID: String) {
        self.sessionID = sessionID
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
