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
            return "keyring auth storage is not available in codex-swift yet"
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

    public typealias RefreshTransport = (URLRequest) async throws -> AuthRefreshHTTPResponse

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

    public static func saveAuthDotJSON(
        _ auth: AuthDotJSON,
        codexHome: URL,
        mode: AuthCredentialsStoreMode = .file,
        encoder: JSONEncoder = JSONEncoder()
    ) throws {
        switch mode {
        case .file, .auto:
            let authFile = codexHome.appendingPathComponent("auth.json", isDirectory: false)
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

    public static func loadFreshTokenData(
        codexHome: URL,
        mode: AuthCredentialsStoreMode = .file,
        now: Date = Date(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        refreshTransport: RefreshTransport? = nil,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder()
    ) async throws -> AuthTokenData? {
        guard let auth = try loadAuthDotJSON(codexHome: codexHome, mode: mode, decoder: decoder) else {
            return nil
        }
        guard let tokens = auth.tokens,
              let lastRefreshText = auth.lastRefresh,
              let lastRefresh = parseDate(lastRefreshText)
        else {
            throw CodexAuthStorageError.tokenDataNotAvailable
        }

        let refreshThreshold = now.addingTimeInterval(-Double(tokenRefreshIntervalDays) * 24 * 60 * 60)
        guard lastRefresh < refreshThreshold else {
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
            encoder: encoder
        )
        guard let updatedTokens = updated.tokens else {
            throw CodexAuthStorageError.tokenDataNotAvailableAfterRefresh
        }
        return updatedTokens
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
        encoder: JSONEncoder
    ) throws -> AuthDotJSON {
        guard let current = try loadAuthDotJSON(codexHome: codexHome, mode: mode, decoder: decoder),
              let currentTokens = current.tokens
        else {
            throw CodexAuthStorageError.tokenDataNotAvailable
        }

        let updatedTokens = AuthTokenData(
            idToken: idToken ?? currentTokens.idToken,
            accessToken: accessToken ?? currentTokens.accessToken,
            refreshToken: refreshToken ?? currentTokens.refreshToken,
            accountID: currentTokens.accountID
        )
        let updated = AuthDotJSON(
            openAIAPIKey: current.openAIAPIKey,
            tokens: updatedTokens,
            lastRefresh: formatDate(now)
        )
        try saveAuthDotJSON(updated, codexHome: codexHome, mode: mode, encoder: encoder)
        return updated
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

private extension URL {
    var deletingLastPathComponentIfPossible: URL? {
        let parent = deletingLastPathComponent()
        return parent.path.isEmpty ? nil : parent
    }
}
