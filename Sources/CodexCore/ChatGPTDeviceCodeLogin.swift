import Foundation

public typealias ChatGPTDeviceCodeLoginTransport = @Sendable (URLRequest) async throws -> AuthRefreshHTTPResponse
public typealias ChatGPTDeviceCodeLoginSleeper = @Sendable (TimeInterval) async throws -> Void
public typealias ChatGPTDeviceCodeLoginMessageSink = @Sendable (ChatGPTDeviceCodeLoginMessage) async -> Void

public struct ChatGPTDeviceCodeLoginOptions: Sendable {
    public let codexHome: URL
    public let issuer: String
    public let clientID: String
    public let forcedChatGPTWorkspaceIDs: [String]?
    public var forcedChatGPTWorkspaceID: String? { forcedChatGPTWorkspaceIDs?.first }
    public let authCredentialsStoreMode: AuthCredentialsStoreMode
    public let cliVersion: String

    public init(
        codexHome: URL,
        issuer: String = ChatGPTDeviceCodeLogin.defaultIssuer,
        clientID: String = CodexAuthStorage.refreshClientID,
        forcedChatGPTWorkspaceID: String? = nil,
        forcedChatGPTWorkspaceIDs: [String]? = nil,
        authCredentialsStoreMode: AuthCredentialsStoreMode = .file,
        cliVersion: String = "0.0.0"
    ) {
        self.codexHome = codexHome
        self.issuer = issuer
        self.clientID = clientID
        self.forcedChatGPTWorkspaceIDs = forcedChatGPTWorkspaceIDs ?? forcedChatGPTWorkspaceID.map { [$0] }
        self.authCredentialsStoreMode = authCredentialsStoreMode
        self.cliVersion = cliVersion
    }
}

public enum ChatGPTDeviceCodeLoginMessage: Equatable, Sendable {
    case userCodePrompt(code: String, version: String)

    public var renderedText: String {
        switch self {
        case let .userCodePrompt(code, version):
            return """

            Welcome to Codex [v\(Self.ansiGray)\(version)\(Self.ansiReset)]
            \(Self.ansiGray)OpenAI's command-line coding agent\(Self.ansiReset)

            Follow these steps to sign in with ChatGPT using device code authorization:

            1. Open this link in your browser and sign in to your account
               \(Self.ansiBlue)https://auth.openai.com/codex/device\(Self.ansiReset)

            2. Enter this one-time code \(Self.ansiGray)(expires in 15 minutes)\(Self.ansiReset)
               \(Self.ansiBlue)\(code)\(Self.ansiReset)

            \(Self.ansiGray)Device codes are a common phishing target. Never share this code.\(Self.ansiReset)

            """
        }
    }

    private static let ansiBlue = "\u{001B}[94m"
    private static let ansiGray = "\u{001B}[90m"
    private static let ansiReset = "\u{001B}[0m"
}

public enum ChatGPTDeviceCodeLoginError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidURL(String)
    case requestFailed(String)
    case workspaceRestricted(String)

    public var description: String {
        switch self {
        case let .invalidURL(url):
            return "invalid URL: \(url)"
        case let .requestFailed(message):
            return message
        case let .workspaceRestricted(message):
            return message
        }
    }
}

public struct ChatGPTDeviceCodeStart: Equatable, Sendable {
    public let deviceAuthID: String
    public let userCode: String
    public let verificationURL: String
    public let interval: UInt64

    public init(deviceAuthID: String, userCode: String, verificationURL: String, interval: UInt64) {
        self.deviceAuthID = deviceAuthID
        self.userCode = userCode
        self.verificationURL = verificationURL
        self.interval = interval
    }
}

public enum ChatGPTDeviceCodeLogin {
    public static let defaultIssuer = "https://auth.openai.com"
    public static let maxWaitSeconds: TimeInterval = 15 * 60

    public static func run(
        options: ChatGPTDeviceCodeLoginOptions,
        transport: ChatGPTDeviceCodeLoginTransport? = nil,
        sleeper: @escaping ChatGPTDeviceCodeLoginSleeper = { seconds in
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        },
        messageSink: @escaping ChatGPTDeviceCodeLoginMessageSink = { _ in },
        now: @escaping @Sendable () -> Date = { Date() },
        keyringStore: AuthKeyringStore = SystemAuthKeyringStore()
    ) async throws {
        let send = transport ?? urlSessionTransport

        let deviceCode = try await requestDeviceCode(
            options: options,
            transport: send
        )

        await messageSink(.userCodePrompt(code: deviceCode.userCode, version: options.cliVersion))

        try await complete(
            options: options,
            deviceCode: deviceCode,
            transport: send,
            sleeper: sleeper,
            now: now,
            keyringStore: keyringStore
        )
    }

    public static func requestDeviceCode(
        options: ChatGPTDeviceCodeLoginOptions,
        transport: ChatGPTDeviceCodeLoginTransport? = nil
    ) async throws -> ChatGPTDeviceCodeStart {
        let send = transport ?? urlSessionTransport
        let issuer = options.issuer.trimmedTrailingSlashes()
        let userCode = try await requestUserCode(
            apiBaseURL: "\(issuer)/api/accounts",
            clientID: options.clientID,
            transport: send
        )
        return ChatGPTDeviceCodeStart(
            deviceAuthID: userCode.deviceAuthID,
            userCode: userCode.userCode,
            verificationURL: "\(issuer)/codex/device",
            interval: userCode.interval
        )
    }

    public static func complete(
        options: ChatGPTDeviceCodeLoginOptions,
        deviceCode: ChatGPTDeviceCodeStart,
        transport: ChatGPTDeviceCodeLoginTransport? = nil,
        sleeper: @escaping ChatGPTDeviceCodeLoginSleeper = { seconds in
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        },
        now: @escaping @Sendable () -> Date = { Date() },
        keyringStore: AuthKeyringStore = SystemAuthKeyringStore()
    ) async throws {
        let send = transport ?? urlSessionTransport
        let issuer = options.issuer.trimmedTrailingSlashes()
        let apiBaseURL = "\(issuer)/api/accounts"
        let code = try await pollForAuthorizationCode(
            apiBaseURL: apiBaseURL,
            deviceAuthID: deviceCode.deviceAuthID,
            userCode: deviceCode.userCode,
            interval: deviceCode.interval,
            transport: send,
            sleeper: sleeper,
            now: now
        )

        let redirectURI = "\(issuer)/deviceauth/callback"
        let tokens = try await exchangeCodeForTokens(
            issuer: issuer,
            clientID: options.clientID,
            redirectURI: redirectURI,
            codeVerifier: code.codeVerifier,
            authorizationCode: code.authorizationCode,
            transport: send
        )

        try ensureWorkspaceAllowed(
            expected: options.forcedChatGPTWorkspaceIDs,
            idToken: tokens.idToken
        )

        try CodexAuthStorage.saveChatGPTTokens(
            codexHome: options.codexHome,
            apiKey: nil,
            idToken: tokens.idToken,
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            mode: options.authCredentialsStoreMode,
            now: now(),
            keyringStore: keyringStore
        )
    }

    static func requestUserCode(
        apiBaseURL: String,
        clientID: String,
        transport: ChatGPTDeviceCodeLoginTransport
    ) async throws -> UserCodeResponse {
        let request = try jsonPost(
            urlText: "\(apiBaseURL)/deviceauth/usercode",
            body: UserCodeRequest(clientID: clientID)
        )
        let response = try await perform(request, transport: transport)
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 404 {
                throw ChatGPTDeviceCodeLoginError.requestFailed(
                    "device code login is not enabled for this Codex server. Use the browser login or verify the server URL."
                )
            }
            throw ChatGPTDeviceCodeLoginError.requestFailed(
                "device code request failed with status \(HTTPStatus.description(for: response.statusCode))"
            )
        }
        do {
            return try JSONDecoder().decode(UserCodeResponse.self, from: response.body)
        } catch {
            throw ChatGPTDeviceCodeLoginError.requestFailed(String(describing: error))
        }
    }

    static func pollForAuthorizationCode(
        apiBaseURL: String,
        deviceAuthID: String,
        userCode: String,
        interval: UInt64,
        transport: ChatGPTDeviceCodeLoginTransport,
        sleeper: @escaping ChatGPTDeviceCodeLoginSleeper,
        now: @escaping @Sendable () -> Date
    ) async throws -> DeviceAuthorizationCodeResponse {
        let urlText = "\(apiBaseURL)/deviceauth/token"
        let start = now()

        while true {
            let request = try jsonPost(
                urlText: urlText,
                body: TokenPollRequest(deviceAuthID: deviceAuthID, userCode: userCode)
            )
            let response = try await perform(request, transport: transport)

            if (200..<300).contains(response.statusCode) {
                do {
                    return try JSONDecoder().decode(DeviceAuthorizationCodeResponse.self, from: response.body)
                } catch {
                    throw ChatGPTDeviceCodeLoginError.requestFailed(String(describing: error))
                }
            }

            if response.statusCode == 403 || response.statusCode == 404 {
                let elapsed = now().timeIntervalSince(start)
                if elapsed >= maxWaitSeconds {
                    throw ChatGPTDeviceCodeLoginError.requestFailed("device auth timed out after 15 minutes")
                }
                let sleepFor = min(TimeInterval(interval), maxWaitSeconds - elapsed)
                if sleepFor > 0 {
                    try await sleeper(sleepFor)
                } else {
                    await Task.yield()
                }
                continue
            }

            throw ChatGPTDeviceCodeLoginError.requestFailed(
                "device auth failed with status \(HTTPStatus.description(for: response.statusCode))"
            )
        }
    }

    static func exchangeCodeForTokens(
        issuer: String,
        clientID: String,
        redirectURI: String,
        codeVerifier: String,
        authorizationCode: String,
        transport: ChatGPTDeviceCodeLoginTransport
    ) async throws -> ExchangedChatGPTTokens {
        guard let url = URL(string: "\(issuer)/oauth/token") else {
            throw ChatGPTDeviceCodeLoginError.invalidURL("\(issuer)/oauth/token")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = [
            ("grant_type", "authorization_code"),
            ("code", authorizationCode),
            ("redirect_uri", redirectURI),
            ("client_id", clientID),
            ("code_verifier", codeVerifier)
        ]
        .map { "\(formEncode($0.0))=\(formEncode($0.1))" }
        .joined(separator: "&")
        .data(using: .utf8)

        let response = try await perform(request, transport: transport)
        guard (200..<300).contains(response.statusCode) else {
            throw ChatGPTDeviceCodeLoginError.requestFailed(
                "token endpoint returned status \(HTTPStatus.description(for: response.statusCode))"
            )
        }

        do {
            return try JSONDecoder().decode(ExchangedChatGPTTokens.self, from: response.body)
        } catch {
            throw ChatGPTDeviceCodeLoginError.requestFailed(String(describing: error))
        }
    }

    static func ensureWorkspaceAllowed(expected: [String]?, idToken: String) throws {
        guard let expected else {
            return
        }
        let info: IdTokenInfo
        do {
            info = try IdTokenParser.parse(idToken)
        } catch {
            throw ChatGPTDeviceCodeLoginError.workspaceRestricted(
                "Login is restricted to a specific workspace, but the token did not include an chatgpt_account_id claim."
            )
        }
        guard let actual = info.chatGPTAccountID else {
            throw ChatGPTDeviceCodeLoginError.workspaceRestricted(
                "Login is restricted to a specific workspace, but the token did not include an chatgpt_account_id claim."
            )
        }
        guard expected.contains(actual) else {
            throw ChatGPTDeviceCodeLoginError.workspaceRestricted(
                "Login is restricted to workspace id(s) \(expected.joined(separator: ", "))."
            )
        }
    }

    private static func jsonPost<Body: Encodable>(urlText: String, body: Body) throws -> URLRequest {
        guard let url = URL(string: urlText) else {
            throw ChatGPTDeviceCodeLoginError.invalidURL(urlText)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private static func perform(
        _ request: URLRequest,
        transport: ChatGPTDeviceCodeLoginTransport
    ) async throws -> AuthRefreshHTTPResponse {
        do {
            return try await transport(request)
        } catch {
            throw ChatGPTDeviceCodeLoginError.requestFailed(String(describing: error))
        }
    }

    private static func urlSessionTransport(_ request: URLRequest) async throws -> AuthRefreshHTTPResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ChatGPTDeviceCodeLoginError.requestFailed("non-HTTP response")
        }
        return AuthRefreshHTTPResponse(statusCode: http.statusCode, body: data)
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

struct UserCodeResponse: Decodable, Equatable, Sendable {
    let deviceAuthID: String
    let userCode: String
    let interval: UInt64

    private enum CodingKeys: String, CodingKey {
        case deviceAuthID = "device_auth_id"
        case userCode = "user_code"
        case usercode
        case interval
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceAuthID = try container.decode(String.self, forKey: .deviceAuthID)
        if container.contains(.userCode), container.contains(.usercode) {
            throw DecodingError.dataCorruptedError(
                forKey: .usercode,
                in: container,
                debugDescription: "duplicate field `user_code`"
            )
        }
        userCode = try container.decodeIfPresent(String.self, forKey: .userCode)
            ?? container.decode(String.self, forKey: .usercode)
        if container.contains(.interval), try container.decodeNil(forKey: .interval) {
            throw DecodingError.dataCorruptedError(
                forKey: .interval,
                in: container,
                debugDescription: "invalid type: null, expected a string"
            )
        }
        let rawInterval = try container.decodeIfPresent(String.self, forKey: .interval) ?? "0"
        guard let parsed = UInt64(rawInterval.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw DecodingError.dataCorruptedError(
                forKey: .interval,
                in: container,
                debugDescription: "invalid u64 string"
            )
        }
        interval = parsed
    }
}

private struct UserCodeRequest: Encodable {
    let clientID: String

    private enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
    }
}

private struct TokenPollRequest: Encodable {
    let deviceAuthID: String
    let userCode: String

    private enum CodingKeys: String, CodingKey {
        case deviceAuthID = "device_auth_id"
        case userCode = "user_code"
    }
}

struct DeviceAuthorizationCodeResponse: Decodable, Equatable, Sendable {
    let authorizationCode: String
    let codeChallenge: String
    let codeVerifier: String

    private enum CodingKeys: String, CodingKey {
        case authorizationCode = "authorization_code"
        case codeChallenge = "code_challenge"
        case codeVerifier = "code_verifier"
    }
}

struct ExchangedChatGPTTokens: Decodable, Equatable, Sendable {
    let idToken: String
    let accessToken: String
    let refreshToken: String

    private enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

private extension String {
    func trimmedTrailingSlashes() -> String {
        var copy = self
        while copy.last == "/" {
            copy.removeLast()
        }
        return copy
    }
}
