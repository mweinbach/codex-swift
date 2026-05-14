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

public enum LoginAccountParams: Equatable, Sendable {
    case apiKey(apiKey: String)
    case chatGPT(codexStreamlinedLogin: Bool)
    case chatGPTDeviceCode
    case chatGPTAuthTokens(accessToken: String, chatGPTAccountID: String, chatGPTPlanType: String?)

    private enum CodingKeys: String, CodingKey {
        case type
        case apiKey
        case codexStreamlinedLogin
        case accessToken
        case chatGPTAccountID = "chatgptAccountId"
        case chatGPTPlanType = "chatgptPlanType"
    }

    private enum LoginType: String, Codable {
        case apiKey
        case chatGPT = "chatgpt"
        case chatGPTDeviceCode = "chatgptDeviceCode"
        case chatGPTAuthTokens = "chatgptAuthTokens"
    }
}

extension LoginAccountParams: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(LoginType.self, forKey: .type) {
        case .apiKey:
            self = .apiKey(apiKey: try container.decode(String.self, forKey: .apiKey))
        case .chatGPT:
            self = .chatGPT(
                codexStreamlinedLogin: try container.decodeIfPresent(
                    Bool.self,
                    forKey: .codexStreamlinedLogin
                ) ?? false
            )
        case .chatGPTDeviceCode:
            self = .chatGPTDeviceCode
        case .chatGPTAuthTokens:
            self = .chatGPTAuthTokens(
                accessToken: try container.decode(String.self, forKey: .accessToken),
                chatGPTAccountID: try container.decode(String.self, forKey: .chatGPTAccountID),
                chatGPTPlanType: try container.decodeIfPresent(String.self, forKey: .chatGPTPlanType)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .apiKey(apiKey):
            try container.encode(LoginType.apiKey, forKey: .type)
            try container.encode(apiKey, forKey: .apiKey)
        case let .chatGPT(codexStreamlinedLogin):
            try container.encode(LoginType.chatGPT, forKey: .type)
            if codexStreamlinedLogin {
                try container.encode(codexStreamlinedLogin, forKey: .codexStreamlinedLogin)
            }
        case .chatGPTDeviceCode:
            try container.encode(LoginType.chatGPTDeviceCode, forKey: .type)
        case let .chatGPTAuthTokens(accessToken, chatGPTAccountID, chatGPTPlanType):
            try container.encode(LoginType.chatGPTAuthTokens, forKey: .type)
            try container.encode(accessToken, forKey: .accessToken)
            try container.encode(chatGPTAccountID, forKey: .chatGPTAccountID)
            try container.encodeNilOrValue(chatGPTPlanType, forKey: .chatGPTPlanType)
        }
    }
}

public enum LoginAccountResponse: Equatable, Sendable {
    case apiKey
    case chatGPT(loginID: String, authURL: String)
    case chatGPTDeviceCode(loginID: String, verificationURL: String, userCode: String)
    case chatGPTAuthTokens

    private enum CodingKeys: String, CodingKey {
        case type
        case loginID = "loginId"
        case authURL = "authUrl"
        case verificationURL = "verificationUrl"
        case userCode
    }

    private enum LoginType: String, Codable {
        case apiKey
        case chatGPT = "chatgpt"
        case chatGPTDeviceCode = "chatgptDeviceCode"
        case chatGPTAuthTokens = "chatgptAuthTokens"
    }
}

extension LoginAccountResponse: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(LoginType.self, forKey: .type) {
        case .apiKey:
            self = .apiKey
        case .chatGPT:
            self = .chatGPT(
                loginID: try container.decode(String.self, forKey: .loginID),
                authURL: try container.decode(String.self, forKey: .authURL)
            )
        case .chatGPTDeviceCode:
            self = .chatGPTDeviceCode(
                loginID: try container.decode(String.self, forKey: .loginID),
                verificationURL: try container.decode(String.self, forKey: .verificationURL),
                userCode: try container.decode(String.self, forKey: .userCode)
            )
        case .chatGPTAuthTokens:
            self = .chatGPTAuthTokens
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .apiKey:
            try container.encode(LoginType.apiKey, forKey: .type)
        case let .chatGPT(loginID, authURL):
            try container.encode(LoginType.chatGPT, forKey: .type)
            try container.encode(loginID, forKey: .loginID)
            try container.encode(authURL, forKey: .authURL)
        case let .chatGPTDeviceCode(loginID, verificationURL, userCode):
            try container.encode(LoginType.chatGPTDeviceCode, forKey: .type)
            try container.encode(loginID, forKey: .loginID)
            try container.encode(verificationURL, forKey: .verificationURL)
            try container.encode(userCode, forKey: .userCode)
        case .chatGPTAuthTokens:
            try container.encode(LoginType.chatGPTAuthTokens, forKey: .type)
        }
    }
}

public struct CancelLoginAccountParams: Equatable, Codable, Sendable {
    public let loginID: String

    private enum CodingKeys: String, CodingKey {
        case loginID = "loginId"
    }

    public init(loginID: String) {
        self.loginID = loginID
    }
}

public enum CancelLoginAccountStatus: String, Codable, Equatable, Sendable {
    case canceled
    case notFound
}

public struct CancelLoginAccountResponse: Equatable, Codable, Sendable {
    public let status: CancelLoginAccountStatus

    public init(status: CancelLoginAccountStatus) {
        self.status = status
    }
}

public struct LogoutAccountResponse: Equatable, Codable, Sendable {
    public init() {}
}

public enum ChatGPTAuthTokensRefreshReason: String, Codable, Equatable, Sendable {
    case unauthorized
}

public struct ChatGPTAuthTokensRefreshParams: Equatable, Sendable {
    public let reason: ChatGPTAuthTokensRefreshReason
    public let previousAccountID: String?

    private enum CodingKeys: String, CodingKey {
        case reason
        case previousAccountID = "previousAccountId"
    }

    public init(reason: ChatGPTAuthTokensRefreshReason, previousAccountID: String?) {
        self.reason = reason
        self.previousAccountID = previousAccountID
    }
}

extension ChatGPTAuthTokensRefreshParams: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reason = try container.decode(ChatGPTAuthTokensRefreshReason.self, forKey: .reason)
        previousAccountID = try container.decodeIfPresent(String.self, forKey: .previousAccountID)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(reason, forKey: .reason)
        try container.encodeNilOrValue(previousAccountID, forKey: .previousAccountID)
    }
}

public struct ChatGPTAuthTokensRefreshResponse: Equatable, Sendable {
    public let accessToken: String
    public let chatGPTAccountID: String
    public let chatGPTPlanType: String?

    private enum CodingKeys: String, CodingKey {
        case accessToken
        case chatGPTAccountID = "chatgptAccountId"
        case chatGPTPlanType = "chatgptPlanType"
    }

    public init(accessToken: String, chatGPTAccountID: String, chatGPTPlanType: String?) {
        self.accessToken = accessToken
        self.chatGPTAccountID = chatGPTAccountID
        self.chatGPTPlanType = chatGPTPlanType
    }
}

extension ChatGPTAuthTokensRefreshResponse: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        chatGPTAccountID = try container.decode(String.self, forKey: .chatGPTAccountID)
        chatGPTPlanType = try container.decodeIfPresent(String.self, forKey: .chatGPTPlanType)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accessToken, forKey: .accessToken)
        try container.encode(chatGPTAccountID, forKey: .chatGPTAccountID)
        try container.encodeNilOrValue(chatGPTPlanType, forKey: .chatGPTPlanType)
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
