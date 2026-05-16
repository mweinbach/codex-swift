import Foundation
@testable import CodexCore
import XCTest

final class McpOAuthLoginTests: XCTestCase {
    func testPerformRunsBrowserCallbackTokenExchangeAndPersistsTokens() async throws {
        let temp = try OAuthLoginTemporaryDirectory()
        let callbackID = try McpOAuthLogin.callbackID(fromServerURL: "https://mcp.example")
        let redirectURI = "http://127.0.0.1:4321/callback/\(callbackID)"
        let callbackServer = StubOAuthCallbackServer(
            redirectURI: redirectURI,
            callback: McpOAuthCallbackResult(code: "auth-code", state: "csrf")
        )
        let probe = OAuthLoginProbe()
        let recorder = OAuthLoginRecorder()

        try await McpOAuthLogin.perform(
            request: McpOAuthLoginRequest(
                serverName: "github",
                serverURL: "https://mcp.example",
                codexHome: temp.url,
                storeMode: .file,
                httpHeaders: ["X-Static": "static"],
                envHttpHeaders: ["X-Env": "TOKEN"],
                environment: ["TOKEN": "secret"],
                scopes: ["repo", "user"],
                oauthResource: "https://api.example.com",
                timeoutSeconds: 9
            ),
            callbackServerFactory: { _, _, _ in callbackServer },
            browserLauncher: { url in
                await recorder.recordBrowserURL(url)
            },
            messageSink: { message in
                await recorder.recordMessage(message)
            },
            transport: { request in
                try await probe.handle(request)
            },
            pkceGenerator: { PKCECodes(codeVerifier: "verifier", codeChallenge: "challenge") },
            csrfTokenGenerator: { "csrf" }
        )

        XCTAssertEqual(callbackServer.waitedTimeout, 9)
        XCTAssertTrue(callbackServer.stopped)
        let browserURLs = await recorder.browserURLs()
        let messages = await recorder.messages()
        XCTAssertEqual(browserURLs.count, 1)
        let authURL = try XCTUnwrap(browserURLs.first)
        XCTAssertEqual(messages, [.authorizationURL(serverName: "github", authURL: authURL)])
        XCTAssertEqual(
            authURL,
            "https://auth.example/authorize?response_type=code&client_id=client-id&state=csrf&code_challenge=challenge&code_challenge_method=S256&redirect_uri=http%3A%2F%2F127.0.0.1%3A4321%2Fcallback%2F\(callbackID)&scope=repo+user&resource=https%3A%2F%2Fapi.example.com"
        )

        let requests = await probe.requests()
        XCTAssertEqual(requests.map(\.method), ["GET", "POST", "POST"])
        XCTAssertEqual(requests[0].url, "https://mcp.example/.well-known/oauth-authorization-server")
        XCTAssertEqual(requests[1].url, "https://auth.example/register")
        XCTAssertEqual(requests[2].url, "https://auth.example/token")
        XCTAssertEqual(requests[2].headers["X-Static"], "static")
        XCTAssertEqual(requests[2].headers["X-Env"], "secret")

        let stored = try XCTUnwrap(McpOAuthCredentialStore.loadOAuthTokens(
            serverName: "github",
            url: "https://mcp.example",
            codexHome: temp.url,
            mode: .file
        ))
        XCTAssertEqual(stored.serverName, "github")
        XCTAssertEqual(stored.url, "https://mcp.example")
        XCTAssertEqual(stored.clientID, "client-id")
        XCTAssertEqual(stored.tokenResponse.accessToken, "access")
        XCTAssertEqual(stored.tokenResponse.refreshToken, "refresh")
        XCTAssertEqual(stored.tokenResponse.scopes, ["repo", "user"])
    }

    func testPerformUsesDiscoveredScopesWhenRequestScopesAreMissing() async throws {
        let temp = try OAuthLoginTemporaryDirectory()
        let callbackID = try McpOAuthLogin.callbackID(fromServerURL: "https://mcp.example")
        let callbackServer = StubOAuthCallbackServer(
            redirectURI: "http://127.0.0.1:4321/callback/\(callbackID)",
            callback: McpOAuthCallbackResult(code: "auth-code", state: "csrf")
        )
        let probe = OAuthLoginProbe()
        let recorder = OAuthLoginRecorder()

        try await McpOAuthLogin.perform(
            request: McpOAuthLoginRequest(
                serverName: "github",
                serverURL: "https://mcp.example",
                codexHome: temp.url,
                storeMode: .file
            ),
            callbackServerFactory: { _, _, _ in callbackServer },
            browserLauncher: { url in
                await recorder.recordBrowserURL(url)
            },
            transport: { request in
                try await probe.handle(request)
            },
            pkceGenerator: { PKCECodes(codeVerifier: "verifier", codeChallenge: "challenge") },
            csrfTokenGenerator: { "csrf" }
        )

        let browserURL = await recorder.browserURLs().first
        XCTAssertEqual(
            browserURL,
            "https://auth.example/authorize?response_type=code&client_id=client-id&state=csrf&code_challenge=challenge&code_challenge_method=S256&redirect_uri=http%3A%2F%2F127.0.0.1%3A4321%2Fcallback%2F\(callbackID)&scope=profile+email"
        )
    }

    func testPerformContinuesWhenBrowserLaunchFails() async throws {
        let temp = try OAuthLoginTemporaryDirectory()
        let callbackID = try McpOAuthLogin.callbackID(fromServerURL: "https://mcp.example")
        let callbackServer = StubOAuthCallbackServer(
            redirectURI: "http://127.0.0.1:4321/callback/\(callbackID)",
            callback: McpOAuthCallbackResult(code: "auth-code", state: "csrf")
        )
        let probe = OAuthLoginProbe()
        let recorder = OAuthLoginRecorder()

        try await McpOAuthLogin.perform(
            request: McpOAuthLoginRequest(
                serverName: "github",
                serverURL: "https://mcp.example",
                codexHome: temp.url,
                storeMode: .file
            ),
            callbackServerFactory: { _, _, _ in callbackServer },
            browserLauncher: { _ in throw McpOAuthBrowserError.openFailed(1) },
            messageSink: { message in await recorder.recordMessage(message) },
            transport: { request in try await probe.handle(request) },
            pkceGenerator: { PKCECodes(codeVerifier: "verifier", codeChallenge: "challenge") },
            csrfTokenGenerator: { "csrf" }
        )

        let messages = await recorder.messages()
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages.last, .browserLaunchFailed)
        XCTAssertNotNil(try McpOAuthCredentialStore.loadOAuthTokens(
            serverName: "github",
            url: "https://mcp.example",
            codexHome: temp.url,
            mode: .file
        ))
    }

    func testPerformPassesConfiguredCallbackPortAndURLToServerFactory() async throws {
        let temp = try OAuthLoginTemporaryDirectory()
        let callbackID = try McpOAuthLogin.callbackID(fromServerURL: "https://mcp.example")
        let redirectURI = try McpOAuthLogin.redirectURI(
            "https://oauth.example/custom/callback",
            appendingCallbackID: callbackID
        )
        let callbackServer = StubOAuthCallbackServer(
            redirectURI: redirectURI,
            callback: McpOAuthCallbackResult(code: "auth-code", state: "csrf")
        )
        let probe = OAuthLoginProbe()
        let capture = CallbackServerFactoryCapture()

        try await McpOAuthLogin.perform(
            request: McpOAuthLoginRequest(
                serverName: "github",
                serverURL: "https://mcp.example",
                codexHome: temp.url,
                storeMode: .file,
                callbackPort: 5678,
                callbackURL: "https://oauth.example/custom/callback"
            ),
            callbackServerFactory: { callbackPort, callbackURL, callbackID in
                capture.record(callbackPort: callbackPort, callbackURL: callbackURL, callbackID: callbackID)
                return callbackServer
            },
            browserLauncher: { _ in },
            transport: { request in try await probe.handle(request) },
            pkceGenerator: { PKCECodes(codeVerifier: "verifier", codeChallenge: "challenge") },
            csrfTokenGenerator: { "csrf" }
        )

        XCTAssertEqual(capture.callbackPort, 5678)
        XCTAssertEqual(capture.callbackURL, "https://oauth.example/custom/callback")
        XCTAssertEqual(capture.callbackID, callbackID)
        let requests = await probe.requests()
        let registrationBody = try XCTUnwrap(requests[1].body)
        let registrationJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(registrationBody.utf8)) as? [String: Any]
        )
        XCTAssertEqual(
            registrationJSON["redirect_uris"] as? [String],
            ["https://oauth.example/custom/callback/\(callbackID)"]
        )
    }

    func testCallbackIDIsBoundToServerURLLikeRust() throws {
        let callbackID = try McpOAuthLogin.callbackID(
            fromServerURL: "https://mcp.example.com/mcp?tenant=one"
        )
        let sameWithoutFragment = try McpOAuthLogin.callbackID(
            fromServerURL: "https://mcp.example.com/mcp?tenant=one#unused"
        )
        let differentPath = try McpOAuthLogin.callbackID(
            fromServerURL: "https://mcp.example.com/sse?tenant=one"
        )
        let differentQuery = try McpOAuthLogin.callbackID(
            fromServerURL: "https://mcp.example.com/mcp?tenant=two"
        )
        let differentOrigin = try McpOAuthLogin.callbackID(
            fromServerURL: "https://mcp.example.com:8443/mcp"
        )

        XCTAssertEqual(callbackID, sameWithoutFragment)
        XCTAssertNotEqual(callbackID, differentPath)
        XCTAssertNotEqual(callbackID, differentQuery)
        XCTAssertNotEqual(callbackID, differentOrigin)
        XCTAssertEqual(callbackID.count, 12)
        XCTAssertTrue(callbackID.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_")
        })
    }

    func testCallbackIDIsAppendedToRedirectURIPathBeforeQueryLikeRust() throws {
        XCTAssertEqual(
            try McpOAuthLogin.redirectURI("http://127.0.0.1:1234/callback", appendingCallbackID: "abc123"),
            "http://127.0.0.1:1234/callback/abc123"
        )
        XCTAssertEqual(
            try McpOAuthLogin.redirectURI(
                "https://callbacks.example.com/oauth/callback?provider=github",
                appendingCallbackID: "abc123"
            ),
            "https://callbacks.example.com/oauth/callback/abc123?provider=github"
        )
    }
}

private final class CallbackServerFactoryCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var _callbackPort: UInt16?
    private var _callbackURL: String?
    private var _callbackID: String?

    var callbackPort: UInt16? {
        lock.withLock { _callbackPort }
    }

    var callbackURL: String? {
        lock.withLock { _callbackURL }
    }

    var callbackID: String? {
        lock.withLock { _callbackID }
    }

    func record(callbackPort: UInt16?, callbackURL: String?, callbackID: String) {
        lock.withLock {
            _callbackPort = callbackPort
            _callbackURL = callbackURL
            _callbackID = callbackID
        }
    }
}

private actor OAuthLoginRecorder {
    private var recordedBrowserURLs: [String] = []
    private var recordedMessages: [McpOAuthLoginMessage] = []

    func recordBrowserURL(_ url: String) {
        recordedBrowserURLs.append(url)
    }

    func recordMessage(_ message: McpOAuthLoginMessage) {
        recordedMessages.append(message)
    }

    func browserURLs() -> [String] {
        recordedBrowserURLs
    }

    func messages() -> [McpOAuthLoginMessage] {
        recordedMessages
    }
}

private final class StubOAuthCallbackServer: McpOAuthCallbackServing, @unchecked Sendable {
    let redirectURI: String

    private let lock = NSLock()
    private let callback: McpOAuthCallbackResult
    private var _waitedTimeout: TimeInterval?
    private var _stopped = false

    var waitedTimeout: TimeInterval? {
        lock.withLock {
            _waitedTimeout
        }
    }

    var stopped: Bool {
        lock.withLock {
            _stopped
        }
    }

    init(redirectURI: String, callback: McpOAuthCallbackResult) {
        self.redirectURI = redirectURI
        self.callback = callback
    }

    func waitForCallback(timeout: TimeInterval) async throws -> McpOAuthCallbackResult {
        lock.withLock {
            _waitedTimeout = timeout
        }
        return callback
    }

    func stop() {
        lock.withLock {
            _stopped = true
        }
    }
}

private actor OAuthLoginProbe {
    private var recordedRequests: [RecordedOAuthLoginRequest] = []

    func handle(_ request: URLRequest) throws -> McpOAuthDiscoveryHTTPResponse {
        let recorded = RecordedOAuthLoginRequest(request: request)
        recordedRequests.append(recorded)

        switch (recorded.method, recorded.url) {
        case ("GET", "https://mcp.example/.well-known/oauth-authorization-server"):
            return McpOAuthDiscoveryHTTPResponse(
                statusCode: 200,
                body: Data("""
                {
                  "authorization_endpoint": "https://auth.example/authorize",
                  "token_endpoint": "https://auth.example/token",
                  "registration_endpoint": "https://auth.example/register",
                  "scopes_supported": ["profile", " email ", "profile", "", "   "],
                  "response_types_supported": ["code"]
                }
                """.utf8)
            )
        case ("POST", "https://auth.example/register"):
            return McpOAuthDiscoveryHTTPResponse(
                statusCode: 200,
                body: Data("""
                {
                  "client_id": "client-id",
                  "redirect_uris": ["http://127.0.0.1:4321/callback"]
                }
                """.utf8)
            )
        case ("POST", "https://auth.example/token"):
            return McpOAuthDiscoveryHTTPResponse(
                statusCode: 200,
                body: Data("""
                {
                  "access_token": "access",
                  "token_type": "Bearer",
                  "refresh_token": "refresh",
                  "expires_in": 3600,
                  "scope": "repo user"
                }
                """.utf8)
            )
        default:
            return McpOAuthDiscoveryHTTPResponse(statusCode: 404, body: Data())
        }
    }

    func requests() -> [RecordedOAuthLoginRequest] {
        recordedRequests
    }
}

private struct RecordedOAuthLoginRequest: Equatable, Sendable {
    let method: String
    let url: String
    let headers: [String: String]
    let body: String?

    init(request: URLRequest) {
        self.method = request.httpMethod ?? "GET"
        self.url = request.url?.absoluteString ?? ""
        self.headers = request.allHTTPHeaderFields ?? [:]
        self.body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) }
    }
}

private final class OAuthLoginTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-oauth-login-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
