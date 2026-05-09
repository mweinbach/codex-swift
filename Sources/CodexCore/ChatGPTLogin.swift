import Darwin
import Foundation
import Security

public typealias ChatGPTLoginTransport = @Sendable (URLRequest) async throws -> AuthRefreshHTTPResponse
public typealias ChatGPTLoginBrowserLauncher = @Sendable (String) async throws -> Void
public typealias ChatGPTLoginMessageSink = @Sendable (ChatGPTLoginMessage) async -> Void

public struct ChatGPTLoginOptions: Sendable {
    public let codexHome: URL
    public let clientID: String
    public let issuer: String
    public let port: UInt16
    public let openBrowser: Bool
    public let forceState: String?
    public let forcedChatGPTWorkspaceID: String?
    public let authCredentialsStoreMode: AuthCredentialsStoreMode
    public let originator: String
    public let codexStreamlinedLogin: Bool

    public init(
        codexHome: URL,
        clientID: String = CodexAuthStorage.refreshClientID,
        issuer: String = ChatGPTLogin.defaultIssuer,
        port: UInt16 = ChatGPTLogin.defaultPort,
        openBrowser: Bool = true,
        forceState: String? = nil,
        forcedChatGPTWorkspaceID: String? = nil,
        authCredentialsStoreMode: AuthCredentialsStoreMode = .file,
        originator: String = ChatGPTLogin.defaultOriginator(),
        codexStreamlinedLogin: Bool = false
    ) {
        self.codexHome = codexHome
        self.clientID = clientID
        self.issuer = issuer
        self.port = port
        self.openBrowser = openBrowser
        self.forceState = forceState
        self.forcedChatGPTWorkspaceID = forcedChatGPTWorkspaceID
        self.authCredentialsStoreMode = authCredentialsStoreMode
        self.originator = originator
        self.codexStreamlinedLogin = codexStreamlinedLogin
    }
}

public enum ChatGPTLoginMessage: Equatable, Sendable {
    case localServerStarted(port: UInt16, authURL: String)

    public var renderedText: String {
        switch self {
        case let .localServerStarted(port, authURL):
            return """
            Starting local login server on http://localhost:\(port).
            If your browser did not open, navigate to this URL to authenticate:

            \(authURL)
            """
        }
    }
}

public enum ChatGPTLoginError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidURL(String)
    case listenFailed(String)
    case loginNotCompleted
    case loginCancelled
    case requestFailed(String)
    case workspaceRestricted(String)

    public var description: String {
        switch self {
        case let .invalidURL(url):
            return "invalid URL: \(url)"
        case let .listenFailed(message):
            return message
        case .loginNotCompleted:
            return "Login was not completed"
        case .loginCancelled:
            return "Login cancelled"
        case let .requestFailed(message):
            return message
        case let .workspaceRestricted(message):
            return message
        }
    }
}

public final class ChatGPTLoginServer: @unchecked Sendable {
    public let authURL: String
    public let actualPort: UInt16

    private let queue: DispatchQueue
    private let lock = NSLock()
    private var listenFileDescriptor: Int32?
    private var waitContinuation: CheckedContinuation<Void, Error>?
    private var pendingResult: Result<Void, Error>?
    private var completed = false

    private let codexHome: URL
    private let clientID: String
    private let issuer: String
    private let redirectURI: String
    private let pkce: PKCECodes
    private let state: String
    private let forcedChatGPTWorkspaceID: String?
    private let authCredentialsStoreMode: AuthCredentialsStoreMode
    private let codexStreamlinedLogin: Bool
    private let transport: ChatGPTLoginTransport
    private let keyringStore: AuthKeyringStore
    private let now: @Sendable () -> Date

    private init(
        listenFileDescriptor: Int32,
        actualPort: UInt16,
        authURL: String,
        options: ChatGPTLoginOptions,
        redirectURI: String,
        pkce: PKCECodes,
        state: String,
        transport: @escaping ChatGPTLoginTransport,
        keyringStore: AuthKeyringStore,
        now: @escaping @Sendable () -> Date
    ) {
        self.listenFileDescriptor = listenFileDescriptor
        self.actualPort = actualPort
        self.authURL = authURL
        self.codexHome = options.codexHome
        self.clientID = options.clientID
        self.issuer = options.issuer
        self.redirectURI = redirectURI
        self.pkce = pkce
        self.state = state
        self.forcedChatGPTWorkspaceID = options.forcedChatGPTWorkspaceID
        self.authCredentialsStoreMode = options.authCredentialsStoreMode
        self.codexStreamlinedLogin = options.codexStreamlinedLogin
        self.transport = transport
        self.keyringStore = keyringStore
        self.now = now
        self.queue = DispatchQueue(label: "codex.chatgpt-login.callback.\(actualPort)")
    }

    deinit {
        cancel()
    }

    public static func start(
        options: ChatGPTLoginOptions,
        transport: ChatGPTLoginTransport? = nil,
        pkceGenerator: @Sendable () throws -> PKCECodes = { try PKCE.generate() },
        stateGenerator: @Sendable () throws -> String = { try ChatGPTLogin.generateState() },
        keyringStore: AuthKeyringStore = SystemAuthKeyringStore(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws -> ChatGPTLoginServer {
        let pkce = try pkceGenerator()
        let state = try options.forceState ?? stateGenerator()
        let socket = try bindServer(port: options.port)
        let redirectURI = "http://localhost:\(socket.port)/auth/callback"
        let authURL = ChatGPTLogin.buildAuthorizeURL(
            issuer: options.issuer,
            clientID: options.clientID,
            redirectURI: redirectURI,
            pkce: pkce,
            state: state,
            forcedChatGPTWorkspaceID: options.forcedChatGPTWorkspaceID,
            originator: options.originator
        )
        let server = ChatGPTLoginServer(
            listenFileDescriptor: socket.fileDescriptor,
            actualPort: socket.port,
            authURL: authURL,
            options: options,
            redirectURI: redirectURI,
            pkce: pkce,
            state: state,
            transport: transport ?? ChatGPTLogin.urlSessionTransport,
            keyringStore: keyringStore,
            now: now
        )
        server.queue.async { [server] in
            server.acceptLoop()
        }
        return server
    }

    public func waitUntilDone() async throws {
        try await withCheckedThrowingContinuation { continuation in
            let immediate: Result<Void, Error>? = lock.withLock {
                if let pendingResult {
                    self.pendingResult = nil
                    return pendingResult
                }
                if completed {
                    return .failure(ChatGPTLoginError.loginNotCompleted)
                }
                if waitContinuation == nil {
                    waitContinuation = continuation
                    return nil
                }
                return .failure(ChatGPTLoginError.loginNotCompleted)
            }

            if let immediate {
                continuation.resume(with: immediate)
            }
        }
    }

    public func cancel() {
        finish(.failure(ChatGPTLoginError.loginNotCompleted))
    }

    private func acceptLoop() {
        while true {
            guard let listenFD = currentListenFileDescriptor() else {
                return
            }
            let clientFD = Darwin.accept(listenFD, nil, nil)
            if clientFD < 0 {
                if currentListenFileDescriptor() == nil {
                    return
                }
                continue
            }
            handleConnection(fileDescriptor: clientFD)
        }
    }

    private func currentListenFileDescriptor() -> Int32? {
        lock.withLock {
            listenFileDescriptor
        }
    }

    private func handleConnection(fileDescriptor: Int32) {
        guard let path = readRequestPath(fileDescriptor: fileDescriptor) else {
            writeHTTPResponse(
                fileDescriptor: fileDescriptor,
                statusCode: 400,
                reason: "Bad Request",
                body: Data("Bad Request".utf8)
            )
            Darwin.close(fileDescriptor)
            return
        }

        Task { [self] in
            let response = await processRequest(path: path)
            writeHTTPResponse(
                fileDescriptor: fileDescriptor,
                statusCode: response.statusCode,
                reason: response.reason,
                headers: response.headers,
                body: response.body
            )
            Darwin.close(fileDescriptor)
            if let completion = response.completion {
                finish(completion)
            }
        }
    }

    private func processRequest(path: String) async -> ChatGPTLoginHTTPResponse {
        guard let components = URLComponents(string: "http://localhost\(path)") else {
            return .text(statusCode: 400, reason: "Bad Request", body: "Bad Request")
        }

        switch components.path {
        case "/auth/callback":
            var query: [String: String] = [:]
            for item in components.queryItems ?? [] {
                query[item.name] = item.value ?? ""
            }
            guard query["state"] == state else {
                return .text(statusCode: 400, reason: "Bad Request", body: "State mismatch")
            }
            guard let code = query["code"], !code.isEmpty else {
                return .text(statusCode: 400, reason: "Bad Request", body: "Missing authorization code")
            }

            do {
                let tokens = try await ChatGPTLogin.exchangeCodeForTokens(
                    issuer: issuer,
                    clientID: clientID,
                    redirectURI: redirectURI,
                    codeVerifier: pkce.codeVerifier,
                    authorizationCode: code,
                    transport: transport
                )
                do {
                    try ChatGPTLogin.ensureWorkspaceAllowed(expected: forcedChatGPTWorkspaceID, idToken: tokens.idToken)
                } catch {
                    let message = String(describing: error)
                    return .text(
                        statusCode: 200,
                        reason: "OK",
                        body: message,
                        completion: .failure(error)
                    )
                }

                let apiKey = try? await ChatGPTLogin.obtainAPIKey(
                    issuer: issuer,
                    clientID: clientID,
                    idToken: tokens.idToken,
                    transport: transport
                )
                do {
                    try CodexAuthStorage.saveChatGPTTokens(
                        codexHome: codexHome,
                        apiKey: apiKey,
                        idToken: tokens.idToken,
                        accessToken: tokens.accessToken,
                        refreshToken: tokens.refreshToken,
                        mode: authCredentialsStoreMode,
                        now: now(),
                        keyringStore: keyringStore
                    )
                } catch {
                    return .text(
                        statusCode: 500,
                        reason: "Internal Server Error",
                        body: "Unable to persist auth file: \(String(describing: error))"
                    )
                }

                return .redirect(
                    to: ChatGPTLogin.composeSuccessURL(
                        port: actualPort,
                        issuer: issuer,
                        idToken: tokens.idToken,
                        accessToken: tokens.accessToken,
                        codexStreamlinedLogin: codexStreamlinedLogin
                    )
                )
            } catch {
                return .text(
                    statusCode: 500,
                    reason: "Internal Server Error",
                    body: "Token exchange failed: \(String(describing: error))"
                )
            }

        case "/success":
            return ChatGPTLoginHTTPResponse(
                statusCode: 200,
                reason: "OK",
                headers: [("Content-Type", "text/html; charset=utf-8")],
                body: Data(ChatGPTLogin.successHTML.utf8),
                completion: .success(())
            )

        case "/cancel":
            return .text(
                statusCode: 200,
                reason: "OK",
                body: "Login cancelled",
                completion: .failure(ChatGPTLoginError.loginCancelled)
            )

        default:
            return .text(statusCode: 404, reason: "Not Found", body: "Not Found")
        }
    }

    private func readRequestPath(fileDescriptor: Int32) -> String? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        let headerEnd = Data("\r\n\r\n".utf8)
        let fallbackHeaderEnd = Data("\n\n".utf8)

        while data.count < 8192 {
            let count = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.recv(fileDescriptor, rawBuffer.baseAddress, rawBuffer.count, 0)
            }
            guard count > 0 else {
                break
            }
            data.append(buffer, count: count)
            if data.range(of: headerEnd) != nil || data.range(of: fallbackHeaderEnd) != nil {
                break
            }
        }

        guard let request = String(data: data, encoding: .utf8),
              let firstLine = request.split(whereSeparator: \.isNewline).first
        else {
            return nil
        }
        let parts = firstLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2, parts[0] == "GET" else {
            return nil
        }
        return String(parts[1])
    }

    private func writeHTTPResponse(
        fileDescriptor: Int32,
        statusCode: Int,
        reason: String,
        headers: [(String, String)] = [],
        body: Data
    ) {
        var responseHeaders = headers.filter { $0.0.caseInsensitiveCompare("Connection") != .orderedSame }
        responseHeaders.append(("Connection", "close"))
        if !responseHeaders.contains(where: { $0.0.caseInsensitiveCompare("Content-Length") == .orderedSame }) {
            responseHeaders.append(("Content-Length", "\(body.count)"))
        }

        var header = "HTTP/1.1 \(statusCode) \(reason)\r\n"
        for (name, value) in responseHeaders {
            header += "\(name): \(value)\r\n"
        }
        header += "\r\n"

        var response = Data(header.utf8)
        response.append(body)
        response.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }
            _ = Darwin.send(fileDescriptor, baseAddress, rawBuffer.count, 0)
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        let continuation: CheckedContinuation<Void, Error>?
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        continuation = waitContinuation
        waitContinuation = nil
        if continuation == nil {
            pendingResult = result
        }
        closeListenFileDescriptorLocked()
        lock.unlock()

        continuation?.resume(with: result)
    }

    private func closeListenFileDescriptorLocked() {
        guard let fd = listenFileDescriptor else {
            return
        }
        listenFileDescriptor = nil
        Darwin.shutdown(fd, SHUT_RDWR)
        Darwin.close(fd)
    }

    private static func bindServer(port: UInt16) throws -> (fileDescriptor: Int32, port: UInt16) {
        let bindAddress = "127.0.0.1:\(port)"
        var cancelAttempted = false
        var attempts: UInt32 = 0
        let maxAttempts: UInt32 = 10

        while true {
            do {
                return try bindSocket(port: port)
            } catch ChatGPTLoginBindError.addressInUse {
                attempts += 1
                if port == 0 || attempts >= maxAttempts {
                    throw ChatGPTLoginError.listenFailed("Port \(bindAddress) is already in use")
                }
                if !cancelAttempted {
                    cancelAttempted = true
                    try? sendCancelRequest(port: port)
                }
                Darwin.usleep(200_000)
                continue
            } catch {
                throw error
            }
        }
    }

    private static func bindSocket(port: UInt16) throws -> (fileDescriptor: Int32, port: UInt16) {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw ChatGPTLoginError.listenFailed(posixMessage(operation: "socket"))
        }

        do {
            var reuse: Int32 = 1
            guard Darwin.setsockopt(
                fd,
                SOL_SOCKET,
                SO_REUSEADDR,
                &reuse,
                socklen_t(MemoryLayout<Int32>.size)
            ) == 0 else {
                throw ChatGPTLoginError.listenFailed(posixMessage(operation: "setsockopt"))
            }

            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = in_port_t(port).bigEndian
            address.sin_addr = in_addr(s_addr: Darwin.inet_addr("127.0.0.1"))

            let bindResult = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    Darwin.bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard bindResult == 0 else {
                if errno == EADDRINUSE {
                    throw ChatGPTLoginBindError.addressInUse
                }
                throw ChatGPTLoginError.listenFailed(posixMessage(operation: "bind"))
            }

            guard Darwin.listen(fd, SOMAXCONN) == 0 else {
                throw ChatGPTLoginError.listenFailed(posixMessage(operation: "listen"))
            }

            var actualAddress = sockaddr_in()
            var actualLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let nameResult = withUnsafeMutablePointer(to: &actualAddress) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    Darwin.getsockname(fd, sockaddrPointer, &actualLength)
                }
            }
            guard nameResult == 0 else {
                throw ChatGPTLoginError.listenFailed(posixMessage(operation: "getsockname"))
            }

            return (fd, UInt16(bigEndian: actualAddress.sin_port))
        } catch {
            Darwin.close(fd)
            throw error
        }
    }

    private static func sendCancelRequest(port: UInt16) throws {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw ChatGPTLoginError.listenFailed(posixMessage(operation: "socket"))
        }
        defer {
            Darwin.close(fd)
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr = in_addr(s_addr: Darwin.inet_addr("127.0.0.1"))

        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connectResult == 0 else {
            throw ChatGPTLoginError.listenFailed(posixMessage(operation: "connect"))
        }

        let request = "GET /cancel HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nConnection: close\r\n\r\n"
        request.withCString { pointer in
            _ = Darwin.send(fd, pointer, strlen(pointer), 0)
        }
    }

    private static func posixMessage(operation: String) -> String {
        "\(operation) failed: \(String(cString: Darwin.strerror(errno)))"
    }
}

public enum ChatGPTLogin {
    public static let defaultIssuer = "https://auth.openai.com"
    public static let defaultPort: UInt16 = 1455
    public static let defaultOriginatorValue = "codex_cli_rs"
    public static let originatorOverrideEnvironmentVariable = "CODEX_INTERNAL_ORIGINATOR_OVERRIDE"

    public static func run(
        options: ChatGPTLoginOptions,
        transport: ChatGPTLoginTransport? = nil,
        browserLauncher: @escaping ChatGPTLoginBrowserLauncher = ChatGPTLoginBrowser.open,
        messageSink: @escaping ChatGPTLoginMessageSink = { _ in },
        pkceGenerator: @Sendable () throws -> PKCECodes = { try PKCE.generate() },
        stateGenerator: @Sendable () throws -> String = { try generateState() },
        keyringStore: AuthKeyringStore = SystemAuthKeyringStore(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) async throws {
        let server = try ChatGPTLoginServer.start(
            options: options,
            transport: transport,
            pkceGenerator: pkceGenerator,
            stateGenerator: stateGenerator,
            keyringStore: keyringStore,
            now: now
        )
        defer {
            server.cancel()
        }

        if options.openBrowser {
            try? await browserLauncher(server.authURL)
        }
        await messageSink(.localServerStarted(port: server.actualPort, authURL: server.authURL))
        try await server.waitUntilDone()
    }

    public static func defaultOriginator(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        let value = environment[originatorOverrideEnvironmentVariable] ?? defaultOriginatorValue
        guard !value.isEmpty, value.unicodeScalars.allSatisfy({ scalar in
            scalar.value >= 0x20 && scalar.value <= 0x7E
        }) else {
            return defaultOriginatorValue
        }
        return value
    }

    public static func generateState() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw PKCEError.randomBytesFailed(status)
        }
        return PKCE.base64URLEncodedNoPadding(Data(bytes))
    }

    static func buildAuthorizeURL(
        issuer: String,
        clientID: String,
        redirectURI: String,
        pkce: PKCECodes,
        state: String,
        forcedChatGPTWorkspaceID: String?,
        originator: String
    ) -> String {
        var query = [
            ("response_type", "code"),
            ("client_id", clientID),
            ("redirect_uri", redirectURI),
            ("scope", "openid profile email offline_access"),
            ("code_challenge", pkce.codeChallenge),
            ("code_challenge_method", "S256"),
            ("id_token_add_organizations", "true"),
            ("codex_cli_simplified_flow", "true"),
            ("state", state),
            ("originator", originator)
        ]
        if let forcedChatGPTWorkspaceID {
            query.append(("allowed_workspace_id", forcedChatGPTWorkspaceID))
        }
        return "\(issuer)/oauth/authorize?\(formBody(query))"
    }

    static func exchangeCodeForTokens(
        issuer: String,
        clientID: String,
        redirectURI: String,
        codeVerifier: String,
        authorizationCode: String,
        transport: ChatGPTLoginTransport
    ) async throws -> ChatGPTLoginTokens {
        guard let url = URL(string: "\(issuer)/oauth/token") else {
            throw ChatGPTLoginError.invalidURL("\(issuer)/oauth/token")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            ("grant_type", "authorization_code"),
            ("code", authorizationCode),
            ("redirect_uri", redirectURI),
            ("client_id", clientID),
            ("code_verifier", codeVerifier)
        ]).data(using: .utf8)

        let response = try await perform(request, transport: transport)
        guard (200..<300).contains(response.statusCode) else {
            throw ChatGPTLoginError.requestFailed(
                "token endpoint returned status \(HTTPStatus.description(for: response.statusCode))"
            )
        }
        do {
            return try JSONDecoder().decode(ChatGPTLoginTokens.self, from: response.body)
        } catch {
            throw ChatGPTLoginError.requestFailed(String(describing: error))
        }
    }

    static func obtainAPIKey(
        issuer: String,
        clientID: String,
        idToken: String,
        transport: ChatGPTLoginTransport
    ) async throws -> String {
        guard let url = URL(string: "\(issuer)/oauth/token") else {
            throw ChatGPTLoginError.invalidURL("\(issuer)/oauth/token")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            ("grant_type", "urn:ietf:params:oauth:grant-type:token-exchange"),
            ("client_id", clientID),
            ("requested_token", "openai-api-key"),
            ("subject_token", idToken),
            ("subject_token_type", "urn:ietf:params:oauth:token-type:id_token")
        ]).data(using: .utf8)

        let response = try await perform(request, transport: transport)
        guard (200..<300).contains(response.statusCode) else {
            throw ChatGPTLoginError.requestFailed(
                "api key exchange failed with status \(HTTPStatus.description(for: response.statusCode))"
            )
        }
        do {
            return try JSONDecoder().decode(ChatGPTAPIKeyExchangeResponse.self, from: response.body).accessToken
        } catch {
            throw ChatGPTLoginError.requestFailed(String(describing: error))
        }
    }

    static func ensureWorkspaceAllowed(expected: String?, idToken: String) throws {
        guard let expected else {
            return
        }
        let claims = jwtAuthClaims(idToken)
        guard let actual = claims["chatgpt_account_id"] as? String else {
            throw ChatGPTLoginError.workspaceRestricted(
                "Login is restricted to a specific workspace, but the token did not include an chatgpt_account_id claim."
            )
        }
        guard actual == expected else {
            throw ChatGPTLoginError.workspaceRestricted("Login is restricted to workspace id \(expected).")
        }
    }

    static func composeSuccessURL(
        port: UInt16,
        issuer: String,
        idToken: String,
        accessToken: String,
        codexStreamlinedLogin: Bool = false
    ) -> String {
        let tokenClaims = jwtAuthClaims(idToken)
        let accessClaims = jwtAuthClaims(accessToken)
        let completedOnboarding = tokenClaims["completed_platform_onboarding"] as? Bool ?? false
        let isOrgOwner = tokenClaims["is_org_owner"] as? Bool ?? false
        let needsSetup = (!completedOnboarding) && isOrgOwner
        let platformURL = issuer == defaultIssuer ? "https://platform.openai.com" : "https://platform.api.openai.org"

        var queryItems = [
            ("id_token", idToken),
            ("needs_setup", needsSetup ? "true" : "false"),
            ("org_id", tokenClaims["organization_id"] as? String ?? ""),
            ("project_id", tokenClaims["project_id"] as? String ?? ""),
            ("plan_type", accessClaims["chatgpt_plan_type"] as? String ?? ""),
            ("platform_url", platformURL)
        ]
        if codexStreamlinedLogin {
            queryItems.append(("codex_streamlined_login", "true"))
        }
        let query = formBody(queryItems)
        return "http://localhost:\(port)/success?\(query)"
    }

    static func urlSessionTransport(_ request: URLRequest) async throws -> AuthRefreshHTTPResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ChatGPTLoginError.requestFailed("non-HTTP response")
        }
        return AuthRefreshHTTPResponse(statusCode: http.statusCode, body: data)
    }

    private static func perform(
        _ request: URLRequest,
        transport: ChatGPTLoginTransport
    ) async throws -> AuthRefreshHTTPResponse {
        do {
            return try await transport(request)
        } catch {
            throw ChatGPTLoginError.requestFailed(String(describing: error))
        }
    }

    private static func jwtAuthClaims(_ jwt: String) -> [String: Any] {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              !parts[0].isEmpty,
              !parts[1].isEmpty,
              !parts[2].isEmpty,
              let payload = try? base64URLDecode(String(parts[1])),
              let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let auth = json["https://api.openai.com/auth"] as? [String: Any]
        else {
            return [:]
        }
        return auth
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

    private static func formBody(_ pairs: [(String, String)]) -> String {
        pairs.map { "\(formEncode($0.0))=\(formEncode($0.1))" }.joined(separator: "&")
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    fileprivate static let successHTML = """
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <title>Sign into Codex</title>
      </head>
      <body>
        <div>Signed in to Codex</div>
        <script>
          (function () {
            const params = new URLSearchParams(window.location.search);
            const needsSetup = params.get('needs_setup') === 'true';
            const platformUrl = params.get('platform_url') || 'https://platform.openai.com';
            const orgId = params.get('org_id');
            const projectId = params.get('project_id');
            const planType = params.get('plan_type');
            const idToken = params.get('id_token');
            if (needsSetup) {
              const redirectUrlObj = new URL('/org-setup', platformUrl);
              redirectUrlObj.searchParams.set('p', planType);
              redirectUrlObj.searchParams.set('t', idToken);
              redirectUrlObj.searchParams.set('with_org', orgId);
              redirectUrlObj.searchParams.set('project_id', projectId);
              window.setTimeout(function () {
                window.location.replace(redirectUrlObj.toString());
              }, 3000);
            }
          })();
        </script>
      </body>
    </html>
    """
}

public enum ChatGPTLoginBrowser {
    public static func open(_ url: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ChatGPTLoginBrowserError.openFailed(process.terminationStatus)
        }
    }
}

public enum ChatGPTLoginBrowserError: Error, Equatable, CustomStringConvertible, Sendable {
    case openFailed(Int32)

    public var description: String {
        switch self {
        case let .openFailed(status):
            return "browser launch failed with exit status \(status)"
        }
    }
}

struct ChatGPTLoginTokens: Decodable, Equatable, Sendable {
    let idToken: String
    let accessToken: String
    let refreshToken: String

    private enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

private struct ChatGPTAPIKeyExchangeResponse: Decodable {
    let accessToken: String

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

private struct ChatGPTLoginHTTPResponse {
    let statusCode: Int
    let reason: String
    let headers: [(String, String)]
    let body: Data
    let completion: Result<Void, Error>?

    static func text(
        statusCode: Int,
        reason: String,
        body: String,
        completion: Result<Void, Error>? = nil
    ) -> ChatGPTLoginHTTPResponse {
        ChatGPTLoginHTTPResponse(
            statusCode: statusCode,
            reason: reason,
            headers: [("Content-Type", "text/plain; charset=utf-8")],
            body: Data(body.utf8),
            completion: completion
        )
    }

    static func redirect(to url: String) -> ChatGPTLoginHTTPResponse {
        ChatGPTLoginHTTPResponse(
            statusCode: 302,
            reason: "Found",
            headers: [("Location", url)],
            body: Data(),
            completion: nil
        )
    }
}

private enum ChatGPTLoginBindError: Error {
    case addressInUse
}
