public struct ClientInfo: Equatable, Sendable {
    public let name: String
    public let title: String?
    public let version: String

    public init(name: String, title: String? = nil, version: String) {
        self.name = name
        self.title = title
        self.version = version
    }
}

extension ClientInfo: Codable {
    private enum CodingKeys: String, CodingKey {
        case name
        case title
        case version
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeNilOrValue(title, forKey: .title)
        try container.encode(version, forKey: .version)
    }
}

public struct InitializeCapabilities: Equatable, Sendable {
    public let experimentalAPI: Bool
    public let requestAttestation: Bool
    public let optOutNotificationMethods: [String]?

    public init(
        experimentalAPI: Bool = false,
        requestAttestation: Bool = false,
        optOutNotificationMethods: [String]? = nil
    ) {
        self.experimentalAPI = experimentalAPI
        self.requestAttestation = requestAttestation
        self.optOutNotificationMethods = optOutNotificationMethods
    }
}

extension InitializeCapabilities: Codable {
    private enum CodingKeys: String, CodingKey {
        case experimentalAPI = "experimentalApi"
        case requestAttestation
        case optOutNotificationMethods
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        experimentalAPI = try container.decodeIfPresent(Bool.self, forKey: .experimentalAPI) ?? false
        requestAttestation = try container.decodeIfPresent(Bool.self, forKey: .requestAttestation) ?? false
        optOutNotificationMethods = try container.decodeIfPresent([String].self, forKey: .optOutNotificationMethods)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(experimentalAPI, forKey: .experimentalAPI)
        try container.encode(requestAttestation, forKey: .requestAttestation)
        try container.encodeNilOrValue(optOutNotificationMethods, forKey: .optOutNotificationMethods)
    }
}

public struct InitializeParams: Equatable, Sendable {
    public let clientInfo: ClientInfo
    public let capabilities: InitializeCapabilities?

    public init(clientInfo: ClientInfo, capabilities: InitializeCapabilities? = nil) {
        self.clientInfo = clientInfo
        self.capabilities = capabilities
    }
}

extension InitializeParams: Codable {
    private enum CodingKeys: String, CodingKey {
        case clientInfo
        case capabilities
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clientInfo = try container.decode(ClientInfo.self, forKey: .clientInfo)
        capabilities = try container.decodeIfPresent(InitializeCapabilities.self, forKey: .capabilities)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(clientInfo, forKey: .clientInfo)
        try container.encodeIfPresent(capabilities, forKey: .capabilities)
    }
}

public struct InitializeResponse: Equatable, Codable, Sendable {
    public let userAgent: String
    public let codexHome: AbsolutePath
    public let platformFamily: String
    public let platformOS: String

    private enum CodingKeys: String, CodingKey {
        case userAgent
        case codexHome
        case platformFamily
        case platformOS = "platformOs"
    }

    public init(userAgent: String, codexHome: AbsolutePath, platformFamily: String, platformOS: String) {
        self.userAgent = userAgent
        self.codexHome = codexHome
        self.platformFamily = platformFamily
        self.platformOS = platformOS
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
