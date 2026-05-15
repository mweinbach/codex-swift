import CryptoKit
import Foundation

public enum McpOAuthCredentialStoreError: Error, Equatable, CustomStringConvertible, Sendable {
    case keyringOperationFailed(String)
    case fallbackReadFailed(String)
    case fallbackParseFailed(String)
    case fallbackWriteFailed(String)
    case tokenEncodingFailed(String)
    case tokenDecodingFailed(String)
    case storeKeyEncodingFailed

    public var description: String {
        switch self {
        case let .keyringOperationFailed(message):
            return message
        case let .fallbackReadFailed(message):
            return message
        case let .fallbackParseFailed(message):
            return message
        case let .fallbackWriteFailed(message):
            return message
        case let .tokenEncodingFailed(message):
            return message
        case let .tokenDecodingFailed(message):
            return message
        case .storeKeyEncodingFailed:
            return "failed to serialize MCP OAuth key payload"
        }
    }
}

public struct McpOAuthTokenResponse: Codable, Equatable, Sendable {
    public let accessToken: String
    public let tokenType: String
    public var expiresIn: UInt64?
    public let refreshToken: String?
    public let scopes: [String]

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scopes = "scope"
    }

    public init(
        accessToken: String,
        tokenType: String = "bearer",
        expiresIn: UInt64? = nil,
        refreshToken: String? = nil,
        scopes: [String] = []
    ) {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn
        self.refreshToken = refreshToken
        self.scopes = scopes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.accessToken = try container.decode(String.self, forKey: .accessToken)
        self.tokenType = try container.decode(String.self, forKey: .tokenType)
        self.expiresIn = try container.decodeIfPresent(UInt64.self, forKey: .expiresIn)
        self.refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        if let scope = try? container.decodeIfPresent(String.self, forKey: .scopes) {
            self.scopes = scope.split(separator: " ").map(String.init)
        } else {
            self.scopes = try container.decodeIfPresent([String].self, forKey: .scopes) ?? []
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accessToken, forKey: .accessToken)
        try container.encode(tokenType, forKey: .tokenType)
        try container.encodeIfPresent(expiresIn, forKey: .expiresIn)
        try container.encodeIfPresent(refreshToken, forKey: .refreshToken)
        if !scopes.isEmpty {
            try container.encode(scopes.joined(separator: " "), forKey: .scopes)
        }
    }
}

public struct McpOAuthStoredTokens: Codable, Equatable, Sendable {
    public let serverName: String
    public let url: String
    public let clientID: String
    public var tokenResponse: McpOAuthTokenResponse
    public let expiresAt: UInt64?

    private enum CodingKeys: String, CodingKey {
        case serverName = "server_name"
        case url
        case clientID = "client_id"
        case tokenResponse = "token_response"
        case expiresAt = "expires_at"
    }

    public init(
        serverName: String,
        url: String,
        clientID: String,
        tokenResponse: McpOAuthTokenResponse,
        expiresAt: UInt64? = nil
    ) {
        self.serverName = serverName
        self.url = url
        self.clientID = clientID
        self.tokenResponse = tokenResponse
        self.expiresAt = expiresAt
    }
}

public enum McpOAuthCredentialStore {
    public static let keyringService = "Codex MCP Credentials"
    public static let fallbackFilename = ".credentials.json"
    private static let refreshSkewMillis: UInt64 = 30_000

    public static func loadOAuthTokens(
        serverName: String,
        url: String,
        codexHome: URL,
        mode: OAuthCredentialsStoreMode = .auto,
        keyringStore: AuthKeyringStore = SystemAuthKeyringStore(),
        now: Date = Date()
    ) throws -> McpOAuthStoredTokens? {
        switch mode {
        case .file:
            return try loadFallbackTokens(serverName: serverName, url: url, codexHome: codexHome, now: now)
        case .keyring:
            return try loadKeyringTokens(serverName: serverName, url: url, keyringStore: keyringStore, now: now)
        case .auto:
            do {
                if let tokens = try loadKeyringTokens(
                    serverName: serverName,
                    url: url,
                    keyringStore: keyringStore,
                    now: now
                ) {
                    return tokens
                }
            } catch {
                // Rust logs keyring read errors in auto mode and then tries fallback storage.
            }
            return try loadFallbackTokens(serverName: serverName, url: url, codexHome: codexHome, now: now)
        }
    }

    public static func saveOAuthTokens(
        _ tokens: McpOAuthStoredTokens,
        codexHome: URL,
        mode: OAuthCredentialsStoreMode = .auto,
        keyringStore: AuthKeyringStore = SystemAuthKeyringStore(),
        now: Date = Date()
    ) throws {
        switch mode {
        case .file:
            try saveFallbackTokens(tokens, codexHome: codexHome, now: now)
        case .keyring:
            try saveKeyringTokens(tokens, codexHome: codexHome, keyringStore: keyringStore)
        case .auto:
            do {
                try saveKeyringTokens(tokens, codexHome: codexHome, keyringStore: keyringStore)
            } catch {
                // Rust falls back to CODEX_HOME/.credentials.json when the keyring is unavailable.
                try saveFallbackTokens(tokens, codexHome: codexHome, now: now)
            }
        }
    }

    public static func hasOAuthTokens(
        serverName: String,
        url: String,
        codexHome: URL,
        mode: OAuthCredentialsStoreMode = .auto,
        keyringStore: AuthKeyringStore = SystemAuthKeyringStore()
    ) throws -> Bool {
        try loadOAuthTokens(
            serverName: serverName,
            url: url,
            codexHome: codexHome,
            mode: mode,
            keyringStore: keyringStore
        ) != nil
    }

    public static func deleteOAuthTokens(
        serverName: String,
        url: String,
        codexHome: URL,
        mode: OAuthCredentialsStoreMode = .auto,
        keyringStore: AuthKeyringStore = SystemAuthKeyringStore()
    ) throws -> Bool {
        let key = try storeKey(serverName: serverName, url: url)
        let keyringRemoved: Bool
        do {
            keyringRemoved = try keyringStore.delete(service: keyringService, account: key)
        } catch {
            switch mode {
            case .auto, .keyring:
                throw McpOAuthCredentialStoreError.keyringOperationFailed(
                    "failed to delete OAuth tokens from keyring: \(String(describing: error))"
                )
            case .file:
                keyringRemoved = false
            }
        }

        let fileRemoved = try deleteFallbackTokens(key: key, codexHome: codexHome)
        return keyringRemoved || fileRemoved
    }

    public static func storeKey(serverName: String, url: String) throws -> String {
        let payload: [String: Any] = [
            "headers": [String: String](),
            "type": "http",
            "url": url
        ]
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw McpOAuthCredentialStoreError.storeKeyEncodingFailed
        }
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .withoutEscapingSlashes])
        } catch {
            throw McpOAuthCredentialStoreError.storeKeyEncodingFailed
        }
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(serverName)|\(hex.prefix(16))"
    }

    public static func computeExpiresAtMillis(tokenResponse: McpOAuthTokenResponse, now: Date = Date()) -> UInt64? {
        guard let expiresIn = tokenResponse.expiresIn else {
            return nil
        }
        let nowMilliseconds = unixMillis(now)
        let addMilliseconds: UInt64
        if expiresIn > UInt64.max / 1000 {
            addMilliseconds = UInt64.max
        } else {
            addMilliseconds = expiresIn * 1000
        }
        let (expiresAt, overflow) = nowMilliseconds.addingReportingOverflow(addMilliseconds)
        return overflow ? UInt64.max : expiresAt
    }

    public static func expiresInFromTimestamp(_ expiresAt: UInt64, now: Date = Date()) -> UInt64? {
        let nowMilliseconds = unixMillis(now)
        guard expiresAt > nowMilliseconds else {
            return nil
        }
        return (expiresAt - nowMilliseconds) / 1000
    }

    public static func tokenNeedsRefresh(expiresAt: UInt64?, now: Date = Date()) -> Bool {
        guard let expiresAt else {
            return false
        }
        let nowMilliseconds = unixMillis(now)
        let (refreshAt, overflow) = nowMilliseconds.addingReportingOverflow(refreshSkewMillis)
        return overflow || refreshAt >= expiresAt
    }

    private static func loadKeyringTokens(
        serverName: String,
        url: String,
        keyringStore: AuthKeyringStore,
        now: Date
    ) throws -> McpOAuthStoredTokens? {
        let key = try storeKey(serverName: serverName, url: url)
        let serialized: String
        do {
            guard let value = try keyringStore.load(service: keyringService, account: key) else {
                return nil
            }
            serialized = value
        } catch {
            throw McpOAuthCredentialStoreError.keyringOperationFailed(
                "failed to read OAuth tokens from keyring: \(String(describing: error))"
            )
        }

        do {
            let tokens = try JSONDecoder().decode(McpOAuthStoredTokens.self, from: Data(serialized.utf8))
            return tokens.withRefreshedExpiresIn(now: now)
        } catch {
            throw McpOAuthCredentialStoreError.tokenDecodingFailed(
                "failed to deserialize OAuth tokens from keyring: \(String(describing: error))"
            )
        }
    }

    private static func saveKeyringTokens(
        _ tokens: McpOAuthStoredTokens,
        codexHome: URL,
        keyringStore: AuthKeyringStore
    ) throws {
        let key = try storeKey(serverName: tokens.serverName, url: tokens.url)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data: Data
        do {
            data = try encoder.encode(tokens)
        } catch {
            throw McpOAuthCredentialStoreError.tokenEncodingFailed("failed to serialize OAuth tokens")
        }
        guard let serialized = String(data: data, encoding: .utf8) else {
            throw McpOAuthCredentialStoreError.tokenEncodingFailed("failed to serialize OAuth tokens")
        }

        do {
            try keyringStore.save(service: keyringService, account: key, value: serialized)
        } catch {
            throw McpOAuthCredentialStoreError.keyringOperationFailed(
                "failed to write OAuth tokens to keyring: \(String(describing: error))"
            )
        }
        _ = try? deleteFallbackTokens(key: key, codexHome: codexHome)
    }

    private static func loadFallbackTokens(
        serverName: String,
        url: String,
        codexHome: URL,
        now: Date
    ) throws -> McpOAuthStoredTokens? {
        guard let store = try readFallbackFile(codexHome: codexHome) else {
            return nil
        }
        let key = try storeKey(serverName: serverName, url: url)
        for entry in store.values {
            let entryKey = try storeKey(serverName: entry.serverName, url: entry.serverURL)
            if entryKey == key {
                return McpOAuthStoredTokens(
                    serverName: entry.serverName,
                    url: entry.serverURL,
                    clientID: entry.clientID,
                    tokenResponse: McpOAuthTokenResponse(
                        accessToken: entry.accessToken,
                        expiresIn: entry.expiresAt.flatMap { expiresInFromTimestamp($0, now: now) },
                        refreshToken: entry.refreshToken,
                        scopes: entry.scopes
                    ),
                    expiresAt: entry.expiresAt
                )
            }
        }
        return nil
    }

    private static func saveFallbackTokens(
        _ tokens: McpOAuthStoredTokens,
        codexHome: URL,
        now: Date
    ) throws {
        let key = try storeKey(serverName: tokens.serverName, url: tokens.url)
        var store = try readFallbackFile(codexHome: codexHome) ?? [:]
        store[key] = McpOAuthFallbackTokenEntry(
            serverName: tokens.serverName,
            serverURL: tokens.url,
            clientID: tokens.clientID,
            accessToken: tokens.tokenResponse.accessToken,
            expiresAt: tokens.expiresAt ?? computeExpiresAtMillis(tokenResponse: tokens.tokenResponse, now: now),
            refreshToken: tokens.tokenResponse.refreshToken,
            scopes: tokens.tokenResponse.scopes
        )
        try writeFallbackFile(store, codexHome: codexHome)
    }

    private static func deleteFallbackTokens(key: String, codexHome: URL) throws -> Bool {
        guard var store = try readFallbackFile(codexHome: codexHome) else {
            return false
        }
        let removed = store.removeValue(forKey: key) != nil
        if removed {
            try writeFallbackFile(store, codexHome: codexHome)
        }
        return removed
    }

    private static func readFallbackFile(codexHome: URL) throws -> [String: McpOAuthFallbackTokenEntry]? {
        let url = fallbackFileURL(codexHome: codexHome)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw McpOAuthCredentialStoreError.fallbackReadFailed(
                "failed to read credentials file at \(url.path): \(String(describing: error))"
            )
        }
        do {
            return try JSONDecoder().decode([String: McpOAuthFallbackTokenEntry].self, from: data)
        } catch {
            throw McpOAuthCredentialStoreError.fallbackParseFailed(
                "failed to parse credentials file at \(url.path): \(String(describing: error))"
            )
        }
    }

    private static func writeFallbackFile(
        _ store: [String: McpOAuthFallbackTokenEntry],
        codexHome: URL
    ) throws {
        let url = fallbackFileURL(codexHome: codexHome)
        if store.isEmpty {
            if FileManager.default.fileExists(atPath: url.path) {
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    throw McpOAuthCredentialStoreError.fallbackWriteFailed(
                        "failed to remove credentials file at \(url.path): \(String(describing: error))"
                    )
                }
            }
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: codexHome,
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(store)
            try data.write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            throw McpOAuthCredentialStoreError.fallbackWriteFailed(
                "failed to write credentials file at \(url.path): \(String(describing: error))"
            )
        }
    }

    private static func fallbackFileURL(codexHome: URL) -> URL {
        codexHome.appendingPathComponent(fallbackFilename, isDirectory: false)
    }

    private static func unixMillis(_ date: Date) -> UInt64 {
        let milliseconds = date.timeIntervalSince1970 * 1000
        guard milliseconds > 0 else {
            return 0
        }
        if milliseconds >= Double(UInt64.max) {
            return UInt64.max
        }
        return UInt64(milliseconds)
    }
}

private extension McpOAuthStoredTokens {
    func withRefreshedExpiresIn(now: Date) -> McpOAuthStoredTokens {
        guard let expiresAt else {
            return self
        }
        var copy = self
        copy.tokenResponse.expiresIn = McpOAuthCredentialStore.expiresInFromTimestamp(expiresAt, now: now)
        return copy
    }
}

private struct McpOAuthFallbackTokenEntry: Codable, Equatable, Sendable {
    let serverName: String
    let serverURL: String
    let clientID: String
    let accessToken: String
    let expiresAt: UInt64?
    let refreshToken: String?
    let scopes: [String]

    private enum CodingKeys: String, CodingKey {
        case serverName = "server_name"
        case serverURL = "server_url"
        case clientID = "client_id"
        case accessToken = "access_token"
        case expiresAt = "expires_at"
        case refreshToken = "refresh_token"
        case scopes
    }

    init(
        serverName: String,
        serverURL: String,
        clientID: String,
        accessToken: String,
        expiresAt: UInt64? = nil,
        refreshToken: String? = nil,
        scopes: [String] = []
    ) {
        self.serverName = serverName
        self.serverURL = serverURL
        self.clientID = clientID
        self.accessToken = accessToken
        self.expiresAt = expiresAt
        self.refreshToken = refreshToken
        self.scopes = scopes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.serverName = try container.decode(String.self, forKey: .serverName)
        self.serverURL = try container.decode(String.self, forKey: .serverURL)
        self.clientID = try container.decode(String.self, forKey: .clientID)
        self.accessToken = try container.decode(String.self, forKey: .accessToken)
        self.expiresAt = try container.decodeIfPresent(UInt64.self, forKey: .expiresAt)
        self.refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        self.scopes = try container.decodeRustDefaulted([String].self, forKey: .scopes, defaultValue: [])
    }
}
