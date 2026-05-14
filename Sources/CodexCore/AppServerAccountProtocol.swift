public enum Account: Equatable, Sendable {
    case apiKey
    case chatGPT(email: String, planType: PlanType)
    case amazonBedrock

    private enum CodingKeys: String, CodingKey {
        case type
        case email
        case planType
    }

    private enum AccountType: String, Codable {
        case apiKey
        case chatGPT = "chatgpt"
        case amazonBedrock
    }
}

extension Account: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(AccountType.self, forKey: .type) {
        case .apiKey:
            self = .apiKey
        case .chatGPT:
            self = .chatGPT(
                email: try container.decode(String.self, forKey: .email),
                planType: try container.decode(PlanType.self, forKey: .planType)
            )
        case .amazonBedrock:
            self = .amazonBedrock
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .apiKey:
            try container.encode(AccountType.apiKey, forKey: .type)
        case let .chatGPT(email, planType):
            try container.encode(AccountType.chatGPT, forKey: .type)
            try container.encode(email, forKey: .email)
            try container.encode(planType, forKey: .planType)
        case .amazonBedrock:
            try container.encode(AccountType.amazonBedrock, forKey: .type)
        }
    }
}

public struct GetAccountParams: Equatable, Sendable {
    public let refreshToken: Bool

    private enum CodingKeys: String, CodingKey {
        case refreshToken
    }

    public init(refreshToken: Bool = false) {
        self.refreshToken = refreshToken
    }
}

extension GetAccountParams: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        refreshToken = try container.decodeIfPresent(Bool.self, forKey: .refreshToken) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(refreshToken, forKey: .refreshToken)
    }
}

public struct GetAccountResponse: Equatable, Sendable {
    public let account: Account?
    public let requiresOpenAIAuth: Bool

    private enum CodingKeys: String, CodingKey {
        case account
        case requiresOpenAIAuth
    }

    public init(account: Account?, requiresOpenAIAuth: Bool) {
        self.account = account
        self.requiresOpenAIAuth = requiresOpenAIAuth
    }
}

extension GetAccountResponse: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        account = try container.decodeIfPresent(Account.self, forKey: .account)
        requiresOpenAIAuth = try container.decode(Bool.self, forKey: .requiresOpenAIAuth)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNilOrValue(account, forKey: .account)
        try container.encode(requiresOpenAIAuth, forKey: .requiresOpenAIAuth)
    }
}

public struct AccountUpdatedNotification: Equatable, Sendable {
    public let authMode: AuthMode?
    public let planType: PlanType?

    private enum CodingKeys: String, CodingKey {
        case authMode
        case planType
    }

    public init(authMode: AuthMode?, planType: PlanType?) {
        self.authMode = authMode
        self.planType = planType
    }
}

extension AccountUpdatedNotification: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        authMode = try container.decodeIfPresent(AuthMode.self, forKey: .authMode)
        planType = try container.decodeIfPresent(PlanType.self, forKey: .planType)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNilOrValue(authMode, forKey: .authMode)
        try container.encodeNilOrValue(planType, forKey: .planType)
    }
}

public struct AccountLoginCompletedNotification: Equatable, Sendable {
    public let loginID: String?
    public let success: Bool
    public let error: String?

    private enum CodingKeys: String, CodingKey {
        case loginID = "loginId"
        case success
        case error
    }

    public init(loginID: String?, success: Bool, error: String?) {
        self.loginID = loginID
        self.success = success
        self.error = error
    }
}

extension AccountLoginCompletedNotification: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        loginID = try container.decodeIfPresent(String.self, forKey: .loginID)
        success = try container.decode(Bool.self, forKey: .success)
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNilOrValue(loginID, forKey: .loginID)
        try container.encode(success, forKey: .success)
        try container.encodeNilOrValue(error, forKey: .error)
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
