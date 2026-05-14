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

public struct GetAccountRateLimitsResponse: Equatable, Sendable {
    public let rateLimits: AccountRateLimitSnapshot
    public let rateLimitsByLimitID: [String: AccountRateLimitSnapshot]?

    private enum CodingKeys: String, CodingKey {
        case rateLimits
        case rateLimitsByLimitID = "rateLimitsByLimitId"
    }

    public init(
        rateLimits: AccountRateLimitSnapshot,
        rateLimitsByLimitID: [String: AccountRateLimitSnapshot]?
    ) {
        self.rateLimits = rateLimits
        self.rateLimitsByLimitID = rateLimitsByLimitID
    }
}

extension GetAccountRateLimitsResponse: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rateLimits = try container.decode(AccountRateLimitSnapshot.self, forKey: .rateLimits)
        rateLimitsByLimitID = try container.decodeIfPresent(
            [String: AccountRateLimitSnapshot].self,
            forKey: .rateLimitsByLimitID
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rateLimits, forKey: .rateLimits)
        try container.encodeNilOrValue(rateLimitsByLimitID, forKey: .rateLimitsByLimitID)
    }
}

public struct AccountRateLimitsUpdatedNotification: Equatable, Codable, Sendable {
    public let rateLimits: AccountRateLimitSnapshot

    public init(rateLimits: AccountRateLimitSnapshot) {
        self.rateLimits = rateLimits
    }
}

public struct AccountRateLimitSnapshot: Equatable, Sendable {
    public let limitID: String?
    public let limitName: String?
    public let primary: AccountRateLimitWindow?
    public let secondary: AccountRateLimitWindow?
    public let credits: AccountCreditsSnapshot?
    public let planType: PlanType?
    public let rateLimitReachedType: RateLimitReachedType?

    private enum CodingKeys: String, CodingKey {
        case limitID = "limitId"
        case limitName
        case primary
        case secondary
        case credits
        case planType
        case rateLimitReachedType
    }

    public init(
        limitID: String? = nil,
        limitName: String? = nil,
        primary: AccountRateLimitWindow?,
        secondary: AccountRateLimitWindow?,
        credits: AccountCreditsSnapshot?,
        planType: PlanType?,
        rateLimitReachedType: RateLimitReachedType? = nil
    ) {
        self.limitID = limitID
        self.limitName = limitName
        self.primary = primary
        self.secondary = secondary
        self.credits = credits
        self.planType = planType
        self.rateLimitReachedType = rateLimitReachedType
    }

    public init(core snapshot: RateLimitSnapshot) {
        self.init(
            limitID: snapshot.limitID,
            limitName: snapshot.limitName,
            primary: snapshot.primary.map(AccountRateLimitWindow.init(core:)),
            secondary: snapshot.secondary.map(AccountRateLimitWindow.init(core:)),
            credits: snapshot.credits.map(AccountCreditsSnapshot.init(core:)),
            planType: snapshot.planType,
            rateLimitReachedType: snapshot.rateLimitReachedType
        )
    }
}

extension AccountRateLimitSnapshot: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        limitID = try container.decodeIfPresent(String.self, forKey: .limitID)
        limitName = try container.decodeIfPresent(String.self, forKey: .limitName)
        primary = try container.decodeIfPresent(AccountRateLimitWindow.self, forKey: .primary)
        secondary = try container.decodeIfPresent(AccountRateLimitWindow.self, forKey: .secondary)
        credits = try container.decodeIfPresent(AccountCreditsSnapshot.self, forKey: .credits)
        planType = try container.decodeIfPresent(PlanType.self, forKey: .planType)
        rateLimitReachedType = try container.decodeIfPresent(
            RateLimitReachedType.self,
            forKey: .rateLimitReachedType
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNilOrValue(limitID, forKey: .limitID)
        try container.encodeNilOrValue(limitName, forKey: .limitName)
        try container.encodeNilOrValue(primary, forKey: .primary)
        try container.encodeNilOrValue(secondary, forKey: .secondary)
        try container.encodeNilOrValue(credits, forKey: .credits)
        try container.encodeNilOrValue(planType, forKey: .planType)
        try container.encodeNilOrValue(rateLimitReachedType, forKey: .rateLimitReachedType)
    }
}

public struct AccountRateLimitWindow: Equatable, Sendable {
    public let usedPercent: Int
    public let windowDurationMinutes: Int64?
    public let resetsAt: Int64?

    private enum CodingKeys: String, CodingKey {
        case usedPercent
        case windowDurationMinutes = "windowDurationMins"
        case resetsAt
    }

    public init(usedPercent: Int, windowDurationMinutes: Int64?, resetsAt: Int64?) {
        self.usedPercent = usedPercent
        self.windowDurationMinutes = windowDurationMinutes
        self.resetsAt = resetsAt
    }

    public init(core window: RateLimitWindow) {
        self.init(
            usedPercent: Int(window.usedPercent.rounded()),
            windowDurationMinutes: window.windowMinutes,
            resetsAt: window.resetsAt
        )
    }
}

extension AccountRateLimitWindow: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usedPercent = try container.decode(Int.self, forKey: .usedPercent)
        windowDurationMinutes = try container.decodeIfPresent(Int64.self, forKey: .windowDurationMinutes)
        resetsAt = try container.decodeIfPresent(Int64.self, forKey: .resetsAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(usedPercent, forKey: .usedPercent)
        try container.encodeNilOrValue(windowDurationMinutes, forKey: .windowDurationMinutes)
        try container.encodeNilOrValue(resetsAt, forKey: .resetsAt)
    }
}

public struct AccountCreditsSnapshot: Equatable, Sendable {
    public let hasCredits: Bool
    public let unlimited: Bool
    public let balance: String?

    private enum CodingKeys: String, CodingKey {
        case hasCredits
        case unlimited
        case balance
    }

    public init(hasCredits: Bool, unlimited: Bool, balance: String?) {
        self.hasCredits = hasCredits
        self.unlimited = unlimited
        self.balance = balance
    }

    public init(core credits: CreditsSnapshot) {
        self.init(hasCredits: credits.hasCredits, unlimited: credits.unlimited, balance: credits.balance)
    }
}

extension AccountCreditsSnapshot: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasCredits = try container.decode(Bool.self, forKey: .hasCredits)
        unlimited = try container.decode(Bool.self, forKey: .unlimited)
        balance = try container.decodeIfPresent(String.self, forKey: .balance)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hasCredits, forKey: .hasCredits)
        try container.encode(unlimited, forKey: .unlimited)
        try container.encodeNilOrValue(balance, forKey: .balance)
    }
}

public struct SendAddCreditsNudgeEmailParams: Equatable, Codable, Sendable {
    public let creditType: AccountAddCreditsNudgeCreditType

    public init(creditType: AccountAddCreditsNudgeCreditType) {
        self.creditType = creditType
    }
}

public enum AccountAddCreditsNudgeCreditType: String, Codable, Equatable, Sendable {
    case credits
    case usageLimit = "usage_limit"
}

public struct SendAddCreditsNudgeEmailResponse: Equatable, Codable, Sendable {
    public let status: AccountAddCreditsNudgeEmailStatus

    public init(status: AccountAddCreditsNudgeEmailStatus) {
        self.status = status
    }
}

public enum AccountAddCreditsNudgeEmailStatus: String, Codable, Equatable, Sendable {
    case sent
    case cooldownActive = "cooldown_active"
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
