import Foundation

public struct ExperimentalFeatureListParams: Equatable, Sendable {
    public let cursor: String?
    public let limit: UInt32?

    public init(cursor: String? = nil, limit: UInt32? = nil) {
        self.cursor = cursor
        self.limit = limit
    }
}

extension ExperimentalFeatureListParams: Codable {
    private enum CodingKeys: String, CodingKey {
        case cursor
        case limit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cursor = try container.decodeIfPresent(String.self, forKey: .cursor)
        limit = try container.decodeIfPresent(UInt32.self, forKey: .limit)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNilOrValue(cursor, forKey: .cursor)
        try container.encodeNilOrValue(limit, forKey: .limit)
    }
}

public enum ExperimentalFeatureStage: String, Codable, Equatable, Sendable {
    case beta
    case underDevelopment
    case stable
    case deprecated
    case removed

    public init(core stage: FeatureStage) {
        switch stage {
        case .experimental:
            self = .beta
        case .underDevelopment:
            self = .underDevelopment
        case .stable:
            self = .stable
        case .deprecated:
            self = .deprecated
        case .removed:
            self = .removed
        }
    }
}

public struct ExperimentalFeature: Equatable, Sendable {
    public let name: String
    public let stage: ExperimentalFeatureStage
    public let displayName: String?
    public let description: String?
    public let announcement: String?
    public let enabled: Bool
    public let defaultEnabled: Bool

    public init(
        name: String,
        stage: ExperimentalFeatureStage,
        displayName: String?,
        description: String?,
        announcement: String?,
        enabled: Bool,
        defaultEnabled: Bool
    ) {
        self.name = name
        self.stage = stage
        self.displayName = displayName
        self.description = description
        self.announcement = announcement
        self.enabled = enabled
        self.defaultEnabled = defaultEnabled
    }

    public init(core spec: FeatureSpec, features: FeatureStates) {
        self.init(
            name: spec.key,
            stage: ExperimentalFeatureStage(core: spec.stage),
            displayName: spec.displayName,
            description: spec.description,
            announcement: spec.announcement,
            enabled: features.isEnabled(spec.id),
            defaultEnabled: spec.defaultEnabled
        )
    }
}

extension ExperimentalFeature: Codable {
    private enum CodingKeys: String, CodingKey {
        case name
        case stage
        case displayName
        case description
        case announcement
        case enabled
        case defaultEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        stage = try container.decode(ExperimentalFeatureStage.self, forKey: .stage)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        announcement = try container.decodeIfPresent(String.self, forKey: .announcement)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        defaultEnabled = try container.decode(Bool.self, forKey: .defaultEnabled)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(stage, forKey: .stage)
        try container.encodeNilOrValue(displayName, forKey: .displayName)
        try container.encodeNilOrValue(description, forKey: .description)
        try container.encodeNilOrValue(announcement, forKey: .announcement)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(defaultEnabled, forKey: .defaultEnabled)
    }
}

public struct ExperimentalFeatureListResponse: Equatable, Sendable {
    public let data: [ExperimentalFeature]
    public let nextCursor: String?

    public init(data: [ExperimentalFeature], nextCursor: String?) {
        self.data = data
        self.nextCursor = nextCursor
    }
}

extension ExperimentalFeatureListResponse: Codable {
    private enum CodingKeys: String, CodingKey {
        case data
        case nextCursor
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decode([ExperimentalFeature].self, forKey: .data)
        nextCursor = try container.decodeIfPresent(String.self, forKey: .nextCursor)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(data, forKey: .data)
        try container.encodeNilOrValue(nextCursor, forKey: .nextCursor)
    }
}

public struct ExperimentalFeatureEnablementSetParams: Equatable, Codable, Sendable {
    public let enablement: [String: Bool]

    public init(enablement: [String: Bool]) {
        self.enablement = enablement
    }
}

public struct ExperimentalFeatureEnablementSetResponse: Equatable, Codable, Sendable {
    public let enablement: [String: Bool]

    public init(enablement: [String: Bool]) {
        self.enablement = enablement
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
