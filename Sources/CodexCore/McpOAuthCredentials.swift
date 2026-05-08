import CryptoKit
import Foundation

public enum McpOAuthCredentialStoreError: Error, Equatable, CustomStringConvertible, Sendable {
    case keyringOperationFailed(String)
    case fallbackReadFailed(String)
    case fallbackParseFailed(String)
    case fallbackWriteFailed(String)
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
        case .storeKeyEncodingFailed:
            return "failed to serialize MCP OAuth key payload"
        }
    }
}

public enum McpOAuthCredentialStore {
    public static let keyringService = "Codex MCP Credentials"
    public static let fallbackFilename = ".credentials.json"

    public static func hasOAuthTokens(
        serverName: String,
        url: String,
        codexHome: URL,
        mode: OAuthCredentialsStoreMode = .auto,
        keyringStore: AuthKeyringStore = SystemAuthKeyringStore()
    ) throws -> Bool {
        switch mode {
        case .file:
            return try hasFallbackTokens(serverName: serverName, url: url, codexHome: codexHome)
        case .keyring:
            return try hasKeyringTokens(serverName: serverName, url: url, keyringStore: keyringStore)
        case .auto:
            do {
                if try hasKeyringTokens(serverName: serverName, url: url, keyringStore: keyringStore) {
                    return true
                }
            } catch {
                // Rust logs keyring read errors in auto mode and then tries fallback storage.
            }
            return try hasFallbackTokens(serverName: serverName, url: url, codexHome: codexHome)
        }
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

    private static func hasKeyringTokens(
        serverName: String,
        url: String,
        keyringStore: AuthKeyringStore
    ) throws -> Bool {
        let key = try storeKey(serverName: serverName, url: url)
        do {
            return try keyringStore.load(service: keyringService, account: key) != nil
        } catch {
            throw McpOAuthCredentialStoreError.keyringOperationFailed(
                "failed to read OAuth tokens from keyring: \(String(describing: error))"
            )
        }
    }

    private static func hasFallbackTokens(serverName: String, url: String, codexHome: URL) throws -> Bool {
        guard let store = try readFallbackFile(codexHome: codexHome) else {
            return false
        }
        let key = try storeKey(serverName: serverName, url: url)
        for entry in store.values {
            let entryKey = try storeKey(serverName: entry.serverName, url: entry.serverURL)
            if entryKey == key {
                return true
            }
        }
        return false
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
            encoder.outputFormatting = [.sortedKeys]
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
        self.scopes = try container.decodeIfPresent([String].self, forKey: .scopes) ?? []
    }
}
