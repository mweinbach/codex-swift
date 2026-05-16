import CryptoKit
import Foundation
import Security

public enum AuthCredentialsStoreMode: String, Codable, Equatable, Sendable {
    case file
    case keyring
    case auto
    case ephemeral
}

public enum OAuthCredentialsStoreMode: String, Codable, Equatable, Sendable {
    case auto
    case file
    case keyring
}

public enum KnownChatGPTPlan: Equatable, Codable, Sendable {
    case free
    case go
    case plus
    case pro
    case proLite
    case team
    case selfServeBusinessUsageBased
    case business
    case enterpriseCbpUsageBased
    case enterprise
    case edu

    public var rawValue: String {
        switch self {
        case .free:
            return "free"
        case .go:
            return "go"
        case .plus:
            return "plus"
        case .pro:
            return "pro"
        case .proLite:
            return "prolite"
        case .team:
            return "team"
        case .selfServeBusinessUsageBased:
            return "self_serve_business_usage_based"
        case .business:
            return "business"
        case .enterpriseCbpUsageBased:
            return "enterprise_cbp_usage_based"
        case .enterprise:
            return "enterprise"
        case .edu:
            return "edu"
        }
    }

    public var rustDebugDescription: String {
        switch self {
        case .free: "Free"
        case .go: "Go"
        case .plus: "Plus"
        case .pro: "Pro"
        case .proLite: "Pro Lite"
        case .team: "Team"
        case .selfServeBusinessUsageBased: "Self Serve Business Usage Based"
        case .business: "Business"
        case .enterpriseCbpUsageBased: "Enterprise CBP Usage Based"
        case .enterprise: "Enterprise"
        case .edu: "Edu"
        }
    }

    public var isWorkspaceAccount: Bool {
        switch self {
        case .team, .selfServeBusinessUsageBased, .business, .enterpriseCbpUsageBased, .enterprise, .edu:
            return true
        case .free, .go, .plus, .pro, .proLite:
            return false
        }
    }

    public static func fromRawValue(_ rawValue: String) -> KnownChatGPTPlan? {
        switch rawValue.lowercased() {
        case "free":
            return .free
        case "go":
            return .go
        case "plus":
            return .plus
        case "pro":
            return .pro
        case "prolite":
            return .proLite
        case "team":
            return .team
        case "self_serve_business_usage_based":
            return .selfServeBusinessUsageBased
        case "business":
            return .business
        case "enterprise_cbp_usage_based":
            return .enterpriseCbpUsageBased
        case "enterprise", "hc":
            return .enterprise
        case "education", "edu":
            return .edu
        default:
            return nil
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        if let plan = Self.fromRawValue(value) {
            self = plan
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "unknown ChatGPT plan type: \(value)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum ChatGPTPlanType: Equatable, Sendable {
    case known(KnownChatGPTPlan)
    case unknown(String)

    public var displayValue: String {
        switch self {
        case let .known(plan):
            plan.rustDebugDescription
        case let .unknown(value):
            value
        }
    }
}

public struct IdTokenInfo: Equatable, Sendable {
    public var email: String?
    public var chatGPTPlanType: ChatGPTPlanType?
    public var chatGPTAccountID: String?
    public var rawJWT: String

    public init(
        email: String? = nil,
        chatGPTPlanType: ChatGPTPlanType? = nil,
        chatGPTAccountID: String? = nil,
        rawJWT: String = ""
    ) {
        self.email = email
        self.chatGPTPlanType = chatGPTPlanType
        self.chatGPTAccountID = chatGPTAccountID
        self.rawJWT = rawJWT
    }

    public func getChatGPTPlanType() -> String? {
        chatGPTPlanType?.displayValue
    }
}

public enum IdTokenInfoError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidFormat
    case base64DecodeFailed
    case jsonDecodeFailed(String)

    public var description: String {
        switch self {
        case .invalidFormat:
            return "invalid ID token format"
        case .base64DecodeFailed:
            return "invalid ID token base64 payload"
        case let .jsonDecodeFailed(message):
            return message
        }
    }
}

public enum IdTokenParser {
    public static func parse(_ idToken: String) throws -> IdTokenInfo {
        var parts = idToken.split(separator: ".", omittingEmptySubsequences: false).makeIterator()
        guard let header = parts.next(),
              let payload = parts.next(),
              let signature = parts.next(),
              !header.isEmpty,
              !payload.isEmpty,
              !signature.isEmpty
        else {
            throw IdTokenInfoError.invalidFormat
        }

        let payloadBytes = try base64URLDecode(String(payload))
        let claims: IdClaims
        do {
            claims = try JSONDecoder().decode(IdClaims.self, from: payloadBytes)
        } catch {
            throw IdTokenInfoError.jsonDecodeFailed(String(describing: error))
        }

        return IdTokenInfo(
            email: claims.email,
            chatGPTPlanType: claims.auth?.chatGPTPlanType,
            chatGPTAccountID: claims.auth?.chatGPTAccountID,
            rawJWT: idToken
        )
    }

    private static func base64URLDecode(_ value: String) throws -> Data {
        var standard = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = standard.count % 4
        if remainder > 0 {
            standard.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: standard) else {
            throw IdTokenInfoError.base64DecodeFailed
        }
        return data
    }
}

public struct AuthTokenData: Codable, Equatable, Sendable {
    public let idToken: IdTokenInfo
    public let accessToken: String
    public let refreshToken: String
    public let accountID: String?

    public init(idToken: String, accessToken: String, refreshToken: String, accountID: String?) {
        self.idToken = (try? IdTokenParser.parse(idToken)) ?? IdTokenInfo(rawJWT: idToken)
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accountID = accountID
    }

    public init(idToken: IdTokenInfo, accessToken: String, refreshToken: String, accountID: String?) {
        self.idToken = idToken
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accountID = accountID
    }

    private enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case accountID = "account_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawIDToken = try container.decode(String.self, forKey: .idToken)
        self.idToken = try IdTokenParser.parse(rawIDToken)
        self.accessToken = try container.decode(String.self, forKey: .accessToken)
        self.refreshToken = try container.decode(String.self, forKey: .refreshToken)
        self.accountID = try container.decodeIfPresent(String.self, forKey: .accountID)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(idToken.rawJWT, forKey: .idToken)
        try container.encode(accessToken, forKey: .accessToken)
        try container.encode(refreshToken, forKey: .refreshToken)
        try container.encodeIfPresent(accountID, forKey: .accountID)
    }
}

public struct AuthDotJSON: Codable, Equatable, Sendable {
    public let authMode: AuthMode?
    public let openAIAPIKey: String?
    public let tokens: AuthTokenData?
    public let lastRefresh: String?
    public let agentIdentity: String?

    public init(
        authMode: AuthMode? = nil,
        openAIAPIKey: String?,
        tokens: AuthTokenData?,
        lastRefresh: String?,
        agentIdentity: String? = nil
    ) {
        self.authMode = authMode
        self.openAIAPIKey = openAIAPIKey
        self.tokens = tokens
        self.lastRefresh = lastRefresh
        self.agentIdentity = agentIdentity
    }

    private enum CodingKeys: String, CodingKey {
        case authMode = "auth_mode"
        case openAIAPIKey = "OPENAI_API_KEY"
        case tokens
        case lastRefresh = "last_refresh"
        case agentIdentity = "agent_identity"
    }
}

private struct IdClaims: Decodable {
    let email: String?
    let auth: AuthClaims?

    private enum CodingKeys: String, CodingKey {
        case email
        case auth = "https://api.openai.com/auth"
    }
}

private struct AuthClaims: Decodable {
    let chatGPTPlanType: ChatGPTPlanType?
    let chatGPTAccountID: String?

    private enum CodingKeys: String, CodingKey {
        case chatGPTPlanType = "chatgpt_plan_type"
        case chatGPTAccountID = "chatgpt_account_id"
    }
}

extension ChatGPTPlanType: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        if let known = KnownChatGPTPlan.fromRawValue(value) {
            self = .known(known)
        } else {
            self = .unknown(value)
        }
    }
}

public enum CodexAuthStatus: Equatable, Sendable {
    case apiKey(String)
    case chatGPT
    case notLoggedIn
}

public enum CodexAuthRestrictionError: Error, Equatable, CustomStringConvertible, Sendable {
    case violation(String)

    public var description: String {
        switch self {
        case let .violation(message):
            return message
        }
    }
}

public protocol AuthKeyringStore: Sendable {
    func load(service: String, account: String) throws -> String?
    func save(service: String, account: String, value: String) throws
    func delete(service: String, account: String) throws -> Bool
}

public struct SystemAuthKeyringStore: AuthKeyringStore {
    public init() {}

    public func load(service: String, account: String) throws -> String? {
        var query = keychainQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw SystemAuthKeyringError.status(status)
        }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            throw SystemAuthKeyringError.invalidUTF8
        }
        return value
    }

    public func save(service: String, account: String, value: String) throws {
        let data = Data(value.utf8)
        var attributes = keychainQuery(service: service, account: account)
        attributes[kSecValueData as String] = data

        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(
                keychainQuery(service: service, account: account) as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw SystemAuthKeyringError.status(updateStatus)
            }
            return
        }
        guard addStatus == errSecSuccess else {
            throw SystemAuthKeyringError.status(addStatus)
        }
    }

    public func delete(service: String, account: String) throws -> Bool {
        let status = SecItemDelete(keychainQuery(service: service, account: account) as CFDictionary)
        if status == errSecItemNotFound {
            return false
        }
        guard status == errSecSuccess else {
            throw SystemAuthKeyringError.status(status)
        }
        return true
    }

    private func keychainQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

private enum SystemAuthKeyringError: Error, CustomStringConvertible {
    case status(OSStatus)
    case invalidUTF8

    var description: String {
        switch self {
        case let .status(status):
            return SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        case .invalidUTF8:
            return "keyring item was not valid UTF-8"
        }
    }
}

public enum CodexHomeError: Error, Equatable, CustomStringConvertible, Sendable {
    case homeDirectoryNotFound
    case codexHomeDoesNotExist(String)

    public var description: String {
        switch self {
        case .homeDirectoryNotFound:
            return "Could not find home directory"
        case let .codexHomeDoesNotExist(path):
            return "CODEX_HOME path does not exist: \(path)"
        }
    }
}

public enum CodexHome {
    public static func find(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> URL {
        if let raw = environment["CODEX_HOME"], !raw.isEmpty {
            guard FileManager.default.fileExists(atPath: raw) else {
                throw CodexHomeError.codexHomeDoesNotExist(raw)
            }
            return URL(fileURLWithPath: raw, isDirectory: true).resolvingSymlinksInPath()
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        guard !home.path.isEmpty else {
            throw CodexHomeError.homeDirectoryNotFound
        }
        return home.appendingPathComponent(".codex", isDirectory: true)
    }
}

public enum CodexAuthStorageError: Error, Equatable, CustomStringConvertible, Sendable {
    case keyringStoreNotAvailable
    case keyringOperationFailed(String)
    case tokenDataNotAvailable
    case tokenDataNotAvailableAfterRefresh
    case invalidRefreshTokenEndpoint(String)
    case refreshTokenExpired
    case refreshTokenReused
    case refreshTokenInvalidated
    case refreshTokenUnknown
    case refreshTokenFailed(String)

    public var description: String {
        switch self {
        case .keyringStoreNotAvailable:
            return "keyring auth storage is not available on this platform"
        case let .keyringOperationFailed(message):
            return message
        case .tokenDataNotAvailable:
            return "Token data is not available."
        case .tokenDataNotAvailableAfterRefresh:
            return "Token data is not available after refresh."
        case let .invalidRefreshTokenEndpoint(endpoint):
            return "Invalid refresh token endpoint: \(endpoint)"
        case .refreshTokenExpired:
            return "Your access token could not be refreshed because your refresh token has expired. Please log out and sign in again."
        case .refreshTokenReused:
            return "Your access token could not be refreshed because your refresh token was already used. Please log out and sign in again."
        case .refreshTokenInvalidated:
            return "Your access token could not be refreshed because your refresh token was revoked. Please log out and sign in again."
        case .refreshTokenUnknown:
            return "Your access token could not be refreshed. Please log out and sign in again."
        case let .refreshTokenFailed(message):
            return message
        }
    }
}

public struct AuthRefreshHTTPResponse: Equatable, Sendable {
    public let statusCode: Int
    public let body: Data

    public init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }
}

public enum CodexAuthStorage {
    public static let refreshTokenURLEnvironmentOverride = "CODEX_REFRESH_TOKEN_URL_OVERRIDE"
    public static let defaultRefreshTokenURL = "https://auth.openai.com/oauth/token"
    public static let refreshClientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    public static let tokenRefreshIntervalDays = 8
    public static let keyringService = "Codex Auth"
    public static let openAIAPIKeyEnvironmentVariable = "OPENAI_API_KEY"
    public static let codexAPIKeyEnvironmentVariable = "CODEX_API_KEY"
    public static let codexAccessTokenEnvironmentVariable = "CODEX_ACCESS_TOKEN"
    private static let ephemeralAuthStore = EphemeralAuthStore()

    public typealias RefreshTransport = (URLRequest) async throws -> AuthRefreshHTTPResponse

    private enum CurrentAuthMode: Equatable {
        case apiKey
        case chatGPT
    }

    public static func loadAuthDotJSON(
        codexHome: URL,
        mode: AuthCredentialsStoreMode = .file,
        decoder: JSONDecoder = JSONDecoder(),
        keyringStore: AuthKeyringStore = SystemAuthKeyringStore()
    ) throws -> AuthDotJSON? {
        switch mode {
        case .file:
            return try loadFileAuthDotJSON(codexHome: codexHome, decoder: decoder)
        case .keyring:
            return try loadKeyringAuthDotJSON(codexHome: codexHome, decoder: decoder, keyringStore: keyringStore)
        case .auto:
            do {
                if let auth = try loadKeyringAuthDotJSON(
                    codexHome: codexHome,
                    decoder: decoder,
                    keyringStore: keyringStore
                ) {
                    return auth
                }
            } catch {
                // Rust logs this and falls back to file-backed auth in auto mode.
            }
            return try loadFileAuthDotJSON(codexHome: codexHome, decoder: decoder)
        case .ephemeral:
            return ephemeralAuthStore.load(key: computeKeyringStoreKey(codexHome: codexHome))
        }
    }

    public static func loadEffectiveAuthDotJSON(
        codexHome: URL,
        mode: AuthCredentialsStoreMode = .file,
        decoder: JSONDecoder = JSONDecoder(),
        keyringStore: AuthKeyringStore = SystemAuthKeyringStore()
    ) throws -> AuthDotJSON? {
        if let auth = try loadAuthDotJSON(codexHome: codexHome, mode: .ephemeral, decoder: decoder, keyringStore: keyringStore) {
            return auth
        }
        guard mode != .ephemeral else {
            return nil
        }
        return try loadAuthDotJSON(codexHome: codexHome, mode: mode, decoder: decoder, keyringStore: keyringStore)
    }

    public static func saveAuthDotJSON(
        _ auth: AuthDotJSON,
        codexHome: URL,
        mode: AuthCredentialsStoreMode = .file,
        encoder: JSONEncoder = JSONEncoder(),
        keyringStore: AuthKeyringStore = SystemAuthKeyringStore()
    ) throws {
        switch mode {
        case .file:
            try saveFileAuthDotJSON(auth, codexHome: codexHome, encoder: encoder)
        case .keyring:
            try saveKeyringAuthDotJSON(auth, codexHome: codexHome, encoder: encoder, keyringStore: keyringStore)
        case .auto:
            do {
                try saveKeyringAuthDotJSON(auth, codexHome: codexHome, encoder: encoder, keyringStore: keyringStore)
            } catch {
                try saveFileAuthDotJSON(auth, codexHome: codexHome, encoder: encoder)
            }
        case .ephemeral:
            ephemeralAuthStore.save(auth, key: computeKeyringStoreKey(codexHome: codexHome))
        }
    }

    public static func loadTokenData(
        codexHome: URL,
        mode: AuthCredentialsStoreMode = .file,
        decoder: JSONDecoder = JSONDecoder(),
        keyringStore: AuthKeyringStore = SystemAuthKeyringStore()
    ) throws -> AuthTokenData? {
        try loadAuthDotJSON(codexHome: codexHome, mode: mode, decoder: decoder, keyringStore: keyringStore)?.tokens
    }

    public static func loginWithAPIKey(
        codexHome: URL,
        apiKey: String,
        mode: AuthCredentialsStoreMode = .file,
        encoder: JSONEncoder = JSONEncoder(),
        keyringStore: AuthKeyringStore = SystemAuthKeyringStore()
    ) throws {
        try saveAuthDotJSON(
            AuthDotJSON(openAIAPIKey: apiKey, tokens: nil, lastRefresh: nil),
            codexHome: codexHome,
            mode: mode,
            encoder: encoder,
            keyringStore: keyringStore
        )
    }

    public static func loginWithAccessToken<Transport: APITransport>(
        codexHome: URL,
        accessToken: String,
        chatGPTBaseURL: String,
        mode: AuthCredentialsStoreMode = .file,
        transport: Transport,
        encoder: JSONEncoder = JSONEncoder(),
        keyringStore: AuthKeyringStore = SystemAuthKeyringStore()
    ) async throws {
        _ = try await verifiedAgentIdentityClaims(
            accessToken: accessToken,
            chatGPTBaseURL: chatGPTBaseURL,
            transport: transport
        )
        try saveAuthDotJSON(
            AuthDotJSON(
                authMode: .agentIdentity,
                openAIAPIKey: nil,
                tokens: nil,
                lastRefresh: nil,
                agentIdentity: accessToken
            ),
            codexHome: codexHome,
            mode: mode,
            encoder: encoder,
            keyringStore: keyringStore
        )
    }

    public static func loginWithAccessToken(
        codexHome: URL,
        accessToken: String,
        chatGPTBaseURL: String,
        mode: AuthCredentialsStoreMode = .file,
        encoder: JSONEncoder = JSONEncoder(),
        keyringStore: AuthKeyringStore = SystemAuthKeyringStore()
    ) async throws {
        try await loginWithAccessToken(
            codexHome: codexHome,
            accessToken: accessToken,
            chatGPTBaseURL: chatGPTBaseURL,
            mode: mode,
            transport: URLSessionAPITransport(),
            encoder: encoder,
            keyringStore: keyringStore
        )
    }

    public static func saveChatGPTTokens(
        codexHome: URL,
        apiKey: String?,
        idToken: String,
        accessToken: String,
        refreshToken: String,
        mode: AuthCredentialsStoreMode = .file,
        now: Date = Date(),
        encoder: JSONEncoder = JSONEncoder(),
        keyringStore: AuthKeyringStore = SystemAuthKeyringStore()
    ) throws {
        let parsedIDToken = try IdTokenParser.parse(idToken)
        let auth = AuthDotJSON(
            authMode: nil,
            openAIAPIKey: apiKey,
            tokens: AuthTokenData(
                idToken: parsedIDToken,
                accessToken: accessToken,
                refreshToken: refreshToken,
                accountID: parsedIDToken.chatGPTAccountID
            ),
            lastRefresh: formatDate(now)
        )
        try saveAuthDotJSON(auth, codexHome: codexHome, mode: mode, encoder: encoder, keyringStore: keyringStore)
    }

    public static func saveChatGPTAuthTokens(
        codexHome: URL,
        accessToken: String,
        chatGPTAccountID: String,
        chatGPTPlanType: String?,
        mode: AuthCredentialsStoreMode = .file,
        now: Date = Date(),
        encoder: JSONEncoder = JSONEncoder(),
        keyringStore: AuthKeyringStore = SystemAuthKeyringStore()
    ) throws {
        var parsedToken = try IdTokenParser.parse(accessToken)
        parsedToken.chatGPTAccountID = chatGPTAccountID
        if let chatGPTPlanType {
            if let known = KnownChatGPTPlan.fromRawValue(chatGPTPlanType) {
                parsedToken.chatGPTPlanType = .known(known)
            } else {
                parsedToken.chatGPTPlanType = .unknown(chatGPTPlanType)
            }
        } else if parsedToken.chatGPTPlanType == nil {
            parsedToken.chatGPTPlanType = .unknown("unknown")
        }
        parsedToken.rawJWT = accessToken
        let auth = AuthDotJSON(
            authMode: .chatGPTAuthTokens,
            openAIAPIKey: nil,
            tokens: AuthTokenData(
                idToken: parsedToken,
                accessToken: accessToken,
                refreshToken: "",
                accountID: chatGPTAccountID
            ),
            lastRefresh: formatDate(now)
        )
        try saveAuthDotJSON(auth, codexHome: codexHome, mode: mode, encoder: encoder, keyringStore: keyringStore)
    }

    public static func logout(
        codexHome: URL,
        mode: AuthCredentialsStoreMode = .file,
        keyringStore: AuthKeyringStore = SystemAuthKeyringStore()
    ) throws -> Bool {
        switch mode {
        case .file:
            let ephemeralRemoved = ephemeralAuthStore.delete(key: computeKeyringStoreKey(codexHome: codexHome))
            let fileRemoved = try deleteAuthFile(codexHome: codexHome)
            return ephemeralRemoved || fileRemoved
        case .keyring, .auto:
            let ephemeralRemoved = ephemeralAuthStore.delete(key: computeKeyringStoreKey(codexHome: codexHome))
            let keyringRemoved = try deleteKeyringAuth(codexHome: codexHome, keyringStore: keyringStore)
            let fileRemoved = try deleteAuthFile(codexHome: codexHome)
            return ephemeralRemoved || keyringRemoved || fileRemoved
        case .ephemeral:
            return ephemeralAuthStore.delete(key: computeKeyringStoreKey(codexHome: codexHome))
        }
    }

    public static func authStatus(
        codexHome: URL,
        mode: AuthCredentialsStoreMode = .file,
        decoder: JSONDecoder = JSONDecoder(),
        keyringStore: AuthKeyringStore = SystemAuthKeyringStore()
    ) throws -> CodexAuthStatus {
        guard let auth = try loadEffectiveAuthDotJSON(
            codexHome: codexHome,
            mode: mode,
            decoder: decoder,
            keyringStore: keyringStore
        ) else {
            return .notLoggedIn
        }
        if let apiKey = auth.openAIAPIKey {
            return .apiKey(apiKey)
        }
        if auth.tokens != nil {
            return .chatGPT
        }
        if auth.authMode == .agentIdentity, auth.agentIdentity != nil {
            return .chatGPT
        }
        return .notLoggedIn
    }

    public static func readOpenAIAPIKeyFromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        trimmedEnvironmentValue(environment[openAIAPIKeyEnvironmentVariable])
    }

    public static func readCodexAPIKeyFromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        trimmedEnvironmentValue(environment[codexAPIKeyEnvironmentVariable])
    }

    public static func readCodexAccessTokenFromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        trimmedEnvironmentValue(environment[codexAccessTokenEnvironmentVariable])
    }

    public static func loadFreshTokenData(
        codexHome: URL,
        mode: AuthCredentialsStoreMode = .file,
        now: Date = Date(),
        forceRefresh: Bool = false,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        refreshTransport: RefreshTransport? = nil,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder(),
        keyringStore: AuthKeyringStore = SystemAuthKeyringStore()
    ) async throws -> AuthTokenData? {
        guard let auth = try loadEffectiveAuthDotJSON(
            codexHome: codexHome,
            mode: mode,
            decoder: decoder,
            keyringStore: keyringStore
        ) else {
            return nil
        }
        guard let tokens = auth.tokens,
              let lastRefreshText = auth.lastRefresh,
              let lastRefresh = parseDate(lastRefreshText)
        else {
            throw CodexAuthStorageError.tokenDataNotAvailable
        }

        let refreshThreshold = now.addingTimeInterval(-Double(tokenRefreshIntervalDays) * 24 * 60 * 60)
        guard forceRefresh || lastRefresh < refreshThreshold else {
            return tokens
        }

        let response = try await refreshToken(
            refreshToken: tokens.refreshToken,
            environment: environment,
            transport: refreshTransport ?? urlSessionRefreshTransport
        )
        let updated = try updateTokens(
            idToken: response.idToken,
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            codexHome: codexHome,
            mode: mode,
            now: now,
            decoder: decoder,
            encoder: encoder,
            keyringStore: keyringStore
        )
        guard let updatedTokens = updated.tokens else {
            throw CodexAuthStorageError.tokenDataNotAvailableAfterRefresh
        }
        return updatedTokens
    }

    public static func enforceLoginRestrictions(
        codexHome: URL,
        config: CodexRuntimeConfig,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        refreshTransport: RefreshTransport? = nil,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder(),
        keyringStore: AuthKeyringStore = SystemAuthKeyringStore()
    ) async throws {
        guard let authMode = try currentAuthMode(
            codexHome: codexHome,
            mode: config.cliAuthCredentialsStoreMode,
            environment: environment,
            decoder: decoder,
            keyringStore: keyringStore
        ) else {
            return
        }

        if let requiredMethod = config.forcedLoginMethod {
            let violation: String? = switch (requiredMethod, authMode) {
            case (.api, .apiKey), (.chatgpt, .chatGPT):
                nil
            case (.api, .chatGPT):
                "API key login is required, but ChatGPT is currently being used. Logging out."
            case (.chatgpt, .apiKey):
                "ChatGPT login is required, but an API key is currently being used. Logging out."
            }

            if let violation {
                throw restrictionErrorAfterLogout(
                    message: violation,
                    codexHome: codexHome,
                    mode: config.cliAuthCredentialsStoreMode,
                    keyringStore: keyringStore
                )
            }
        }

        guard let expectedAccountIDs = config.forcedChatGPTWorkspaceIDs,
              authMode == .chatGPT
        else {
            return
        }

        let tokenData: AuthTokenData
        do {
            guard let loaded = try await loadFreshTokenData(
                codexHome: codexHome,
                mode: config.cliAuthCredentialsStoreMode,
                environment: environment,
                refreshTransport: refreshTransport,
                decoder: decoder,
                encoder: encoder,
                keyringStore: keyringStore
            ) else {
                throw CodexAuthStorageError.tokenDataNotAvailable
            }
            tokenData = loaded
        } catch {
            throw restrictionErrorAfterLogout(
                message: "Failed to load ChatGPT credentials while enforcing workspace restrictions: \(String(describing: error)). Logging out.",
                codexHome: codexHome,
                mode: config.cliAuthCredentialsStoreMode,
                keyringStore: keyringStore
            )
        }

        let actualAccountID = tokenData.idToken.chatGPTAccountID
        guard actualAccountID.map({ expectedAccountIDs.contains($0) }) == true else {
            let expectedWorkspaces = expectedAccountIDs.joined(separator: ", ")
            let message: String
            if let actualAccountID {
                message = "Login is restricted to workspace(s) \(expectedWorkspaces), but current credentials belong to \(actualAccountID). Logging out."
            } else {
                message = "Login is restricted to workspace(s) \(expectedWorkspaces), but current credentials lack a workspace identifier. Logging out."
            }
            throw restrictionErrorAfterLogout(
                message: message,
                codexHome: codexHome,
                mode: config.cliAuthCredentialsStoreMode,
                keyringStore: keyringStore
            )
        }
    }

    private static func refreshToken(
        refreshToken: String,
        environment: [String: String],
        transport: RefreshTransport
    ) async throws -> RefreshTokenResponse {
        let endpoint = environment[refreshTokenURLEnvironmentOverride] ?? defaultRefreshTokenURL
        guard let url = URL(string: endpoint) else {
            throw CodexAuthStorageError.invalidRefreshTokenEndpoint(endpoint)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RefreshTokenRequest(
            clientID: refreshClientID,
            grantType: "refresh_token",
            refreshToken: refreshToken,
            scope: "openid profile email"
        ))

        let response: AuthRefreshHTTPResponse
        do {
            response = try await transport(request)
        } catch {
            throw CodexAuthStorageError.refreshTokenFailed(String(describing: error))
        }

        if (200..<300).contains(response.statusCode) {
            do {
                return try JSONDecoder().decode(RefreshTokenResponse.self, from: response.body)
            } catch {
                throw CodexAuthStorageError.refreshTokenFailed(String(describing: error))
            }
        }

        let body = String(data: response.body, encoding: .utf8) ?? ""
        if response.statusCode == 401 {
            throw classifyRefreshTokenFailure(body)
        }

        let message = tryParseErrorMessage(body)
        throw CodexAuthStorageError.refreshTokenFailed(
            "Failed to refresh token: \(statusText(response.statusCode)): \(message)"
        )
    }

    private static func updateTokens(
        idToken: String?,
        accessToken: String?,
        refreshToken: String?,
        codexHome: URL,
        mode: AuthCredentialsStoreMode,
        now: Date,
        decoder: JSONDecoder,
        encoder: JSONEncoder,
        keyringStore: AuthKeyringStore
    ) throws -> AuthDotJSON {
        guard let current = try loadAuthDotJSON(
            codexHome: codexHome,
            mode: mode,
            decoder: decoder,
            keyringStore: keyringStore
        ),
              let currentTokens = current.tokens
        else {
            throw CodexAuthStorageError.tokenDataNotAvailable
        }

        let updatedIDToken = try idToken.map { try IdTokenParser.parse($0) } ?? currentTokens.idToken
        let updatedTokens = AuthTokenData(
            idToken: updatedIDToken,
            accessToken: accessToken ?? currentTokens.accessToken,
            refreshToken: refreshToken ?? currentTokens.refreshToken,
            accountID: currentTokens.accountID
        )
        let updated = AuthDotJSON(
            openAIAPIKey: current.openAIAPIKey,
            tokens: updatedTokens,
            lastRefresh: formatDate(now)
        )
        try saveAuthDotJSON(updated, codexHome: codexHome, mode: mode, encoder: encoder, keyringStore: keyringStore)
        return updated
    }

    private static func currentAuthMode(
        codexHome: URL,
        mode: AuthCredentialsStoreMode,
        environment: [String: String],
        decoder: JSONDecoder,
        keyringStore: AuthKeyringStore
    ) throws -> CurrentAuthMode? {
        if readCodexAPIKeyFromEnvironment(environment) != nil {
            return .apiKey
        }

        if let ephemeralAuth = try loadAuthDotJSON(
            codexHome: codexHome,
            mode: .ephemeral,
            decoder: decoder,
            keyringStore: keyringStore
        ) {
            return currentAuthMode(from: ephemeralAuth)
        }

        if mode != .ephemeral, readCodexAccessTokenFromEnvironment(environment) != nil {
            return .chatGPT
        }

        guard mode != .ephemeral,
              let auth = try loadAuthDotJSON(
            codexHome: codexHome,
            mode: mode,
            decoder: decoder,
            keyringStore: keyringStore
        ) else {
            return nil
        }

        return currentAuthMode(from: auth)
    }

    private static func currentAuthMode(from auth: AuthDotJSON) -> CurrentAuthMode {
        if auth.openAIAPIKey != nil {
            return .apiKey
        }
        if auth.authMode == .agentIdentity, auth.agentIdentity != nil {
            return .chatGPT
        }
        return .chatGPT
    }

    private static func verifiedAgentIdentityClaims<Transport: APITransport>(
        accessToken: String,
        chatGPTBaseURL: String,
        transport: Transport
    ) async throws -> AgentIdentityJWTClaims {
        _ = try AgentIdentity.decodeJWTClaims(accessToken)

        let request = APIRequest(method: .get, url: AgentIdentity.agentIdentityJWKSURL(chatGPTBaseURL: chatGPTBaseURL))
        let response: APIResponse
        switch await transport.execute(request) {
        case let .success(success):
            response = success
        case let .failure(error):
            throw CodexAuthStorageError.refreshTokenFailed(String(describing: error))
        }
        guard (200..<300).contains(response.statusCode) else {
            throw CodexAuthStorageError.refreshTokenFailed("agent identity JWKS endpoint returned HTTP \(response.statusCode)")
        }
        let jwks = try JSONDecoder().decode(AgentIdentityJWKS.self, from: response.body)
        return try AgentIdentity.decodeJWTClaims(accessToken, jwks: jwks)
    }

    private static func restrictionErrorAfterLogout(
        message: String,
        codexHome: URL,
        mode: AuthCredentialsStoreMode,
        keyringStore: AuthKeyringStore
    ) -> CodexAuthRestrictionError {
        do {
            _ = try logout(codexHome: codexHome, mode: mode, keyringStore: keyringStore)
            return .violation(message)
        } catch {
            return .violation("\(message). Failed to remove auth.json: \(String(describing: error))")
        }
    }

    public static func computeKeyringStoreKey(codexHome: URL) -> String {
        let path = canonicalCodexHomePath(codexHome)
        let digest = SHA256.hash(data: Data(path.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "cli|\(hex.prefix(16))"
    }

    private static func loadFileAuthDotJSON(
        codexHome: URL,
        decoder: JSONDecoder
    ) throws -> AuthDotJSON? {
        let authFile = authFileURL(codexHome: codexHome)
        guard FileManager.default.fileExists(atPath: authFile.path) else {
            return nil
        }
        let data = try Data(contentsOf: authFile)
        return try decoder.decode(AuthDotJSON.self, from: data)
    }

    private static func saveFileAuthDotJSON(
        _ auth: AuthDotJSON,
        codexHome: URL,
        encoder: JSONEncoder
    ) throws {
        let authFile = authFileURL(codexHome: codexHome)
        if let parent = authFile.deletingLastPathComponentIfPossible {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(auth)
        if FileManager.default.fileExists(atPath: authFile.path) {
            try data.write(to: authFile, options: .atomic)
        } else {
            FileManager.default.createFile(
                atPath: authFile.path,
                contents: data,
                attributes: [.posixPermissions: 0o600]
            )
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: authFile.path)
    }

    private static func deleteAuthFile(codexHome: URL) throws -> Bool {
        let authFile = authFileURL(codexHome: codexHome)
        do {
            try FileManager.default.removeItem(at: authFile)
            return true
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return false
        } catch {
            throw error
        }
    }

    private static func loadKeyringAuthDotJSON(
        codexHome: URL,
        decoder: JSONDecoder,
        keyringStore: AuthKeyringStore
    ) throws -> AuthDotJSON? {
        let serialized: String
        do {
            guard let value = try keyringStore.load(service: keyringService, account: computeKeyringStoreKey(codexHome: codexHome)) else {
                return nil
            }
            serialized = value
        } catch {
            throw CodexAuthStorageError.keyringOperationFailed(
                "failed to load CLI auth from keyring: \(String(describing: error))"
            )
        }

        do {
            return try decoder.decode(AuthDotJSON.self, from: Data(serialized.utf8))
        } catch {
            throw CodexAuthStorageError.keyringOperationFailed(
                "failed to deserialize CLI auth from keyring: \(String(describing: error))"
            )
        }
    }

    private static func saveKeyringAuthDotJSON(
        _ auth: AuthDotJSON,
        codexHome: URL,
        encoder: JSONEncoder,
        keyringStore: AuthKeyringStore
    ) throws {
        encoder.outputFormatting = []
        let data = try encoder.encode(auth)
        guard let serialized = String(data: data, encoding: .utf8) else {
            throw CodexAuthStorageError.keyringOperationFailed("failed to serialize CLI auth for keyring")
        }

        do {
            try keyringStore.save(
                service: keyringService,
                account: computeKeyringStoreKey(codexHome: codexHome),
                value: serialized
            )
        } catch {
            throw CodexAuthStorageError.keyringOperationFailed(
                "failed to write OAuth tokens to keyring: \(String(describing: error))"
            )
        }
        _ = try? deleteAuthFile(codexHome: codexHome)
    }

    private static func deleteKeyringAuth(codexHome: URL, keyringStore: AuthKeyringStore) throws -> Bool {
        do {
            return try keyringStore.delete(service: keyringService, account: computeKeyringStoreKey(codexHome: codexHome))
        } catch {
            throw CodexAuthStorageError.keyringOperationFailed(
                "failed to delete auth from keyring: \(String(describing: error))"
            )
        }
    }

    private static func authFileURL(codexHome: URL) -> URL {
        codexHome.appendingPathComponent("auth.json", isDirectory: false)
    }

    private static func canonicalCodexHomePath(_ codexHome: URL) -> String {
        let path = codexHome.path
        guard FileManager.default.fileExists(atPath: path) else {
            return path
        }
        return codexHome.resolvingSymlinksInPath().path
    }

    private static func trimmedEnvironmentValue(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func urlSessionRefreshTransport(_ request: URLRequest) async throws -> AuthRefreshHTTPResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CodexAuthStorageError.refreshTokenFailed("non-HTTP response")
        }
        return AuthRefreshHTTPResponse(statusCode: http.statusCode, body: data)
    }

    private static func classifyRefreshTokenFailure(_ body: String) -> CodexAuthStorageError {
        switch extractRefreshTokenErrorCode(body)?.lowercased() {
        case "refresh_token_expired":
            return .refreshTokenExpired
        case "refresh_token_reused":
            return .refreshTokenReused
        case "refresh_token_invalidated":
            return .refreshTokenInvalidated
        default:
            return .refreshTokenUnknown
        }
    }

    private static func extractRefreshTokenErrorCode(_ body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        if let error = json["error"] as? [String: Any],
           let code = error["code"] as? String
        {
            return code
        }
        if let error = json["error"] as? String {
            return error
        }
        return json["code"] as? String
    }

    private static func tryParseErrorMessage(_ body: String) -> String {
        guard !body.isEmpty else {
            return "Unknown error"
        }
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String
        else {
            return body
        }
        return message
    }

    private static func parseDate(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func statusText(_ statusCode: Int) -> String {
        let reason = HTTPURLResponse.localizedString(forStatusCode: statusCode)
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
        guard !reason.isEmpty else {
            return "\(statusCode)"
        }
        return "\(statusCode) \(reason)"
    }
}

private struct RefreshTokenRequest: Encodable {
    let clientID: String
    let grantType: String
    let refreshToken: String
    let scope: String

    private enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case grantType = "grant_type"
        case refreshToken = "refresh_token"
        case scope
    }
}

private struct RefreshTokenResponse: Decodable {
    let idToken: String?
    let accessToken: String?
    let refreshToken: String?

    private enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

private final class EphemeralAuthStore: @unchecked Sendable {
    private let lock = NSLock()
    // Mirrors Rust's process-local credential store; every access is serialized by lock.
    private var values: [String: AuthDotJSON] = [:]

    func load(key: String) -> AuthDotJSON? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func save(_ auth: AuthDotJSON, key: String) {
        lock.lock()
        defer { lock.unlock() }
        values[key] = auth
    }

    func delete(key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return values.removeValue(forKey: key) != nil
    }
}

private extension URL {
    var deletingLastPathComponentIfPossible: URL? {
        let parent = deletingLastPathComponent()
        return parent.path.isEmpty ? nil : parent
    }
}
