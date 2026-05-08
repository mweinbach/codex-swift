import Foundation

public enum AuthCredentialsStoreMode: String, Codable, Equatable, Sendable {
    case file
    case keyring
    case auto
}

public struct AuthTokenData: Codable, Equatable, Sendable {
    public let idToken: String
    public let accessToken: String
    public let refreshToken: String
    public let accountID: String?

    public init(idToken: String, accessToken: String, refreshToken: String, accountID: String?) {
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
}

public struct AuthDotJSON: Codable, Equatable, Sendable {
    public let openAIAPIKey: String?
    public let tokens: AuthTokenData?
    public let lastRefresh: String?

    public init(openAIAPIKey: String?, tokens: AuthTokenData?, lastRefresh: String?) {
        self.openAIAPIKey = openAIAPIKey
        self.tokens = tokens
        self.lastRefresh = lastRefresh
    }

    private enum CodingKeys: String, CodingKey {
        case openAIAPIKey = "OPENAI_API_KEY"
        case tokens
        case lastRefresh = "last_refresh"
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

    public var description: String {
        switch self {
        case .keyringStoreNotAvailable:
            return "keyring auth storage is not available in codex-swift yet"
        }
    }
}

public enum CodexAuthStorage {
    public static func loadAuthDotJSON(
        codexHome: URL,
        mode: AuthCredentialsStoreMode = .file,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> AuthDotJSON? {
        switch mode {
        case .file, .auto:
            let authFile = codexHome.appendingPathComponent("auth.json", isDirectory: false)
            guard FileManager.default.fileExists(atPath: authFile.path) else {
                return nil
            }
            let data = try Data(contentsOf: authFile)
            return try decoder.decode(AuthDotJSON.self, from: data)
        case .keyring:
            throw CodexAuthStorageError.keyringStoreNotAvailable
        }
    }

    public static func loadTokenData(
        codexHome: URL,
        mode: AuthCredentialsStoreMode = .file,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> AuthTokenData? {
        try loadAuthDotJSON(codexHome: codexHome, mode: mode, decoder: decoder)?.tokens
    }
}
