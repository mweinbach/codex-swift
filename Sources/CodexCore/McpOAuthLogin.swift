import Foundation

public typealias McpOAuthCallbackServerFactory = @Sendable (
    _ callbackPort: UInt16?,
    _ callbackURL: String?
) throws -> any McpOAuthCallbackServing
public typealias McpOAuthBrowserLauncher = @Sendable (String) async throws -> Void
public typealias McpOAuthLoginMessageSink = @Sendable (McpOAuthLoginMessage) async -> Void

public struct McpOAuthLoginRequest: Sendable {
    public let serverName: String
    public let serverURL: String
    public let codexHome: URL
    public let storeMode: OAuthCredentialsStoreMode
    public let httpHeaders: [String: String]?
    public let envHttpHeaders: [String: String]?
    public let environment: [String: String]
    public let scopes: [String]?
    public let oauthResource: String?
    public let timeoutSeconds: Int?
    public let launchBrowser: Bool
    public let callbackPort: UInt16?
    public let callbackURL: String?

    public init(
        serverName: String,
        serverURL: String,
        codexHome: URL,
        storeMode: OAuthCredentialsStoreMode,
        httpHeaders: [String: String]? = nil,
        envHttpHeaders: [String: String]? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        scopes: [String]? = nil,
        oauthResource: String? = nil,
        timeoutSeconds: Int? = nil,
        launchBrowser: Bool = true,
        callbackPort: UInt16? = nil,
        callbackURL: String? = nil
    ) {
        self.serverName = serverName
        self.serverURL = serverURL
        self.codexHome = codexHome
        self.storeMode = storeMode
        self.httpHeaders = httpHeaders
        self.envHttpHeaders = envHttpHeaders
        self.environment = environment
        self.scopes = scopes
        self.oauthResource = oauthResource
        self.timeoutSeconds = timeoutSeconds
        self.launchBrowser = launchBrowser
        self.callbackPort = callbackPort
        self.callbackURL = callbackURL
    }
}

public enum McpOAuthLoginMessage: Equatable, Sendable {
    case authorizationURL(serverName: String, authURL: String)
    case browserLaunchFailed
}

public enum McpOAuthLoginError: Error, Equatable, CustomStringConvertible, Sendable {
    case metadataNotFound

    public var description: String {
        switch self {
        case .metadataNotFound:
            return "OAuth authorization metadata was not found"
        }
    }
}

public enum McpOAuthLogin {
    public static let defaultTimeoutSeconds = 300

    public static func perform(
        request: McpOAuthLoginRequest,
        callbackServerFactory: McpOAuthCallbackServerFactory = { callbackPort, callbackURL in
            try McpOAuthLocalCallbackServer.start(port: callbackPort, redirectURI: callbackURL)
        },
        browserLauncher: @escaping McpOAuthBrowserLauncher = McpOAuthBrowser.open,
        messageSink: @escaping McpOAuthLoginMessageSink = { _ in },
        keyringStore: AuthKeyringStore = SystemAuthKeyringStore(),
        transport: McpOAuthDiscoveryTransport? = nil,
        pkceGenerator: @Sendable () throws -> PKCECodes = { try PKCE.generate() },
        csrfTokenGenerator: @Sendable () throws -> String = { try McpOAuthAuthorizationSession.generateCSRFToken() }
    ) async throws {
        let callbackServer = try callbackServerFactory(request.callbackPort, request.callbackURL)
        defer {
            callbackServer.stop()
        }

        guard let metadata = try await McpOAuthAuthorizationMetadataDiscovery.discoverMetadata(
            url: request.serverURL,
            httpHeaders: request.httpHeaders,
            envHttpHeaders: request.envHttpHeaders,
            environment: request.environment,
            transport: transport
        ) else {
            throw McpOAuthLoginError.metadataNotFound
        }

        let scopes = request.scopes ?? normalizedScopes(metadata.scopesSupported)
        let session = try await McpOAuthAuthorizationSession.start(
            metadata: metadata,
            scopes: scopes,
            oauthResource: request.oauthResource,
            redirectURI: callbackServer.redirectURI,
            clientName: "Codex",
            httpHeaders: request.httpHeaders,
            envHttpHeaders: request.envHttpHeaders,
            environment: request.environment,
            transport: transport,
            pkceGenerator: pkceGenerator,
            csrfTokenGenerator: csrfTokenGenerator
        )

        if request.launchBrowser {
            await messageSink(.authorizationURL(serverName: request.serverName, authURL: session.authURL))
            do {
                try await browserLauncher(session.authURL)
            } catch {
                await messageSink(.browserLaunchFailed)
            }
        }

        let callback = try await callbackServer.waitForCallback(
            timeout: TimeInterval(max(request.timeoutSeconds ?? defaultTimeoutSeconds, 1))
        )
        let tokenResponse = try await session.exchangeCodeForToken(
            code: callback.code,
            state: callback.state,
            httpHeaders: request.httpHeaders,
            envHttpHeaders: request.envHttpHeaders,
            environment: request.environment,
            transport: transport
        )
        try McpOAuthCredentialStore.saveOAuthTokens(
            session.storedTokens(
                serverName: request.serverName,
                serverURL: request.serverURL,
                tokenResponse: tokenResponse
            ),
            codexHome: request.codexHome,
            mode: request.storeMode,
            keyringStore: keyringStore
        )
    }

    private static func normalizedScopes(_ scopes: [String]?) -> [String] {
        var normalized: [String] = []
        for scope in scopes ?? [] {
            let trimmed = scope.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !normalized.contains(trimmed) else {
                continue
            }
            normalized.append(trimmed)
        }
        return normalized
    }
}

public enum McpOAuthBrowser {
    public static func open(_ url: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw McpOAuthBrowserError.openFailed(process.terminationStatus)
        }
    }
}

public enum McpOAuthBrowserError: Error, Equatable, CustomStringConvertible, Sendable {
    case openFailed(Int32)

    public var description: String {
        switch self {
        case let .openFailed(status):
            return "browser launch failed with exit status \(status)"
        }
    }
}
