import Foundation

public enum PluginShareDiscoverability: String, Codable, Equatable, Sendable {
    case listed = "LISTED"
    case unlisted = "UNLISTED"
    case `private` = "PRIVATE"
}

public enum PluginShareUpdateDiscoverability: String, Codable, Equatable, Sendable {
    case unlisted = "UNLISTED"
    case `private` = "PRIVATE"
}

public enum PluginSharePrincipalType: String, Codable, Equatable, Sendable {
    case user
    case group
    case workspace
}

public struct PluginShareTarget: Equatable, Codable, Sendable {
    public let principalType: PluginSharePrincipalType
    public let principalID: String

    private enum CodingKeys: String, CodingKey {
        case principalType
        case principalID = "principalId"
    }

    public init(principalType: PluginSharePrincipalType, principalID: String) {
        self.principalType = principalType
        self.principalID = principalID
    }
}

public struct PluginSharePrincipal: Equatable, Codable, Sendable {
    public let principalType: PluginSharePrincipalType
    public let principalID: String
    public let name: String

    private enum CodingKeys: String, CodingKey {
        case principalType
        case principalID = "principalId"
        case name
    }

    public init(principalType: PluginSharePrincipalType, principalID: String, name: String) {
        self.principalType = principalType
        self.principalID = principalID
        self.name = name
    }
}

public struct PluginShareSaveParams: Equatable, Sendable {
    public let pluginPath: AbsolutePath
    public let remotePluginID: String?
    public let discoverability: PluginShareDiscoverability?
    public let shareTargets: [PluginShareTarget]?

    private enum CodingKeys: String, CodingKey {
        case pluginPath
        case remotePluginID = "remotePluginId"
        case discoverability
        case shareTargets
    }

    public init(
        pluginPath: AbsolutePath,
        remotePluginID: String? = nil,
        discoverability: PluginShareDiscoverability? = nil,
        shareTargets: [PluginShareTarget]? = nil
    ) {
        self.pluginPath = pluginPath
        self.remotePluginID = remotePluginID
        self.discoverability = discoverability
        self.shareTargets = shareTargets
    }
}

extension PluginShareSaveParams: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pluginPath = try container.decode(AbsolutePath.self, forKey: .pluginPath)
        remotePluginID = try container.decodeIfPresent(String.self, forKey: .remotePluginID)
        discoverability = try container.decodeIfPresent(PluginShareDiscoverability.self, forKey: .discoverability)
        shareTargets = try container.decodeIfPresent([PluginShareTarget].self, forKey: .shareTargets)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pluginPath, forKey: .pluginPath)
        try container.encodeNilOrValue(remotePluginID, forKey: .remotePluginID)
        try container.encodeNilOrValue(discoverability, forKey: .discoverability)
        try container.encodeNilOrValue(shareTargets, forKey: .shareTargets)
    }
}

public struct PluginShareSaveResponse: Equatable, Codable, Sendable {
    public let remotePluginID: String
    public let shareURL: String

    private enum CodingKeys: String, CodingKey {
        case remotePluginID = "remotePluginId"
        case shareURL = "shareUrl"
    }

    public init(remotePluginID: String, shareURL: String) {
        self.remotePluginID = remotePluginID
        self.shareURL = shareURL
    }
}

public struct PluginShareUpdateTargetsParams: Equatable, Codable, Sendable {
    public let remotePluginID: String
    public let discoverability: PluginShareUpdateDiscoverability
    public let shareTargets: [PluginShareTarget]

    private enum CodingKeys: String, CodingKey {
        case remotePluginID = "remotePluginId"
        case discoverability
        case shareTargets
    }

    public init(
        remotePluginID: String,
        discoverability: PluginShareUpdateDiscoverability,
        shareTargets: [PluginShareTarget]
    ) {
        self.remotePluginID = remotePluginID
        self.discoverability = discoverability
        self.shareTargets = shareTargets
    }
}

public struct PluginShareUpdateTargetsResponse: Equatable, Codable, Sendable {
    public let principals: [PluginSharePrincipal]
    public let discoverability: PluginShareDiscoverability

    public init(principals: [PluginSharePrincipal], discoverability: PluginShareDiscoverability) {
        self.principals = principals
        self.discoverability = discoverability
    }
}

public struct PluginShareListParams: Equatable, Codable, Sendable {
    public init() {}
}

public struct PluginShareDeleteParams: Equatable, Codable, Sendable {
    public let remotePluginID: String

    private enum CodingKeys: String, CodingKey {
        case remotePluginID = "remotePluginId"
    }

    public init(remotePluginID: String) {
        self.remotePluginID = remotePluginID
    }
}

public struct PluginShareDeleteResponse: Equatable, Codable, Sendable {
    public init() {}
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
