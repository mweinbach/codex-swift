@testable import CodexCore
import Foundation
import XCTest

final class ChatGPTLoginTests: XCTestCase {
    func testBuildAuthorizeURLMatchesRustQueryShape() {
        let authURL = ChatGPTLogin.buildAuthorizeURL(
            issuer: "https://auth.example",
            clientID: "client-id",
            redirectURI: "http://localhost:1455/auth/callback",
            pkce: PKCECodes(codeVerifier: "verifier", codeChallenge: "challenge"),
            state: "state/123",
            forcedChatGPTWorkspaceID: "workspace-123",
            originator: "codex_cli_rs"
        )

        XCTAssertEqual(
            authURL,
            "https://auth.example/oauth/authorize?response_type=code&client_id=client-id&redirect_uri=http%3A%2F%2Flocalhost%3A1455%2Fauth%2Fcallback&scope=openid%20profile%20email%20offline_access%20api.connectors.read%20api.connectors.invoke&code_challenge=challenge&code_challenge_method=S256&id_token_add_organizations=true&codex_cli_simplified_flow=true&state=state%2F123&originator=codex_cli_rs&allowed_workspace_id=workspace-123"
        )
    }

    func testComposeSuccessURLIncludesStreamlinedFlagWhenRequested() throws {
        let idToken = Self.fakeJWT(authClaims: [
            "organization_id": "org-123",
            "project_id": "proj-123",
            "completed_platform_onboarding": true,
            "is_org_owner": true
        ])
        let accessToken = Self.fakeJWT(authClaims: ["chatgpt_plan_type": "pro"])

        let legacyURL = ChatGPTLogin.composeSuccessURL(
            port: 1455,
            issuer: ChatGPTLogin.defaultIssuer,
            idToken: idToken,
            accessToken: accessToken
        )
        XCTAssertNil(URLComponents(string: legacyURL)?.queryItems?.first { $0.name == "codex_streamlined_login" })

        let streamlinedURL = ChatGPTLogin.composeSuccessURL(
            port: 1455,
            issuer: ChatGPTLogin.defaultIssuer,
            idToken: idToken,
            accessToken: accessToken,
            codexStreamlinedLogin: true
        )
        XCTAssertEqual(
            URLComponents(string: streamlinedURL)?.queryItems?.first { $0.name == "codex_streamlined_login" }?.value,
            "true"
        )
    }

    func testLocalServerCallbackExchangesTokensPersistsAuthAndCompletesOnSuccess() async throws {
        let temp = try LoginTemporaryDirectory()
        let now = Date(timeIntervalSince1970: 1_800_000_100)
        let idToken = Self.fakeJWT(authClaims: [
            "chatgpt_account_id": "acct-123",
            "organization_id": "org-123",
            "project_id": "proj-123",
            "completed_platform_onboarding": false,
            "is_org_owner": true
        ])
        let accessToken = Self.fakeJWT(authClaims: ["chatgpt_plan_type": "pro"])
        let probe = ChatGPTLoginProbe(idToken: idToken, accessToken: accessToken)

        let server = try ChatGPTLoginServer.start(
            options: ChatGPTLoginOptions(
                codexHome: temp.url,
                issuer: "https://issuer.example",
                port: 0,
                openBrowser: false,
                forceState: "state-ok",
                forcedChatGPTWorkspaceID: "acct-123",
                authCredentialsStoreMode: .file,
                originator: "codex_cli_rs"
            ),
            transport: { request in try await probe.handle(request) },
            pkceGenerator: { PKCECodes(codeVerifier: "verifier", codeChallenge: "challenge") },
            now: { now }
        )

        XCTAssertTrue(server.authURL.contains("redirect_uri=http%3A%2F%2Flocalhost%3A\(server.actualPort)%2Fauth%2Fcallback"))
        XCTAssertTrue(server.authURL.contains("allowed_workspace_id=acct-123"))

        let callbackURL = try XCTUnwrap(URL(string: "http://127.0.0.1:\(server.actualPort)/auth/callback?code=auth-code&state=state-ok"))
        let (body, response) = try await URLSession.shared.data(from: callbackURL)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)
        XCTAssertTrue(String(data: body, encoding: .utf8)?.contains("Signed in to Codex") == true)

        try await server.waitUntilDone()

        let requests = await probe.requests()
        XCTAssertEqual(requests.map(\.url), [
            "https://issuer.example/oauth/token",
            "https://issuer.example/oauth/token"
        ])
        XCTAssertEqual(
            requests[0].body,
            "grant_type=authorization_code&code=auth-code&redirect_uri=http%3A%2F%2Flocalhost%3A\(server.actualPort)%2Fauth%2Fcallback&client_id=app_EMoamEEZ73f0CkXaXp7hrann&code_verifier=verifier"
        )
        XCTAssertEqual(
            requests[1].body,
            "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Atoken-exchange&client_id=app_EMoamEEZ73f0CkXaXp7hrann&requested_token=openai-api-key&subject_token=\(Self.formEncode(idToken))&subject_token_type=urn%3Aietf%3Aparams%3Aoauth%3Atoken-type%3Aid_token"
        )

        let auth = try XCTUnwrap(CodexAuthStorage.loadAuthDotJSON(codexHome: temp.url, mode: .file))
        XCTAssertEqual(auth.openAIAPIKey, "sk-exchanged")
        XCTAssertEqual(auth.tokens?.idToken.rawJWT, idToken)
        XCTAssertEqual(auth.tokens?.accessToken, accessToken)
        XCTAssertEqual(auth.tokens?.refreshToken, "refresh-token")
        XCTAssertEqual(auth.tokens?.accountID, "acct-123")
        XCTAssertEqual(auth.lastRefresh, Self.isoString(now))
    }

    func testWorkspaceMismatchReturnsBodyStopsServerAndDoesNotPersistAuth() async throws {
        let temp = try LoginTemporaryDirectory()
        let probe = ChatGPTLoginProbe(idToken: Self.fakeJWT(authClaims: ["chatgpt_account_id": "acct-actual"]))
        let server = try ChatGPTLoginServer.start(
            options: ChatGPTLoginOptions(
                codexHome: temp.url,
                issuer: "https://issuer.example",
                port: 0,
                openBrowser: false,
                forceState: "state-workspace",
                forcedChatGPTWorkspaceID: "acct-required",
                authCredentialsStoreMode: .file
            ),
            transport: { request in try await probe.handle(request) },
            pkceGenerator: { PKCECodes(codeVerifier: "verifier", codeChallenge: "challenge") }
        )

        let callbackURL = try XCTUnwrap(URL(string: "http://127.0.0.1:\(server.actualPort)/auth/callback?code=auth-code&state=state-workspace"))
        let (body, response) = try await URLSession.shared.data(from: callbackURL)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)
        XCTAssertEqual(String(data: body, encoding: .utf8), "Login is restricted to workspace id acct-required.")

        await XCTAssertThrowsErrorAsync(try await server.waitUntilDone()) { error in
            XCTAssertEqual(String(describing: error), "Login is restricted to workspace id acct-required.")
        }
        XCTAssertNil(try CodexAuthStorage.loadAuthDotJSON(codexHome: temp.url, mode: .file))
    }

    func testStartingServerOnBusyPortCancelsPreviousLoginServer() async throws {
        let firstTemp = try LoginTemporaryDirectory()
        let firstServer = try ChatGPTLoginServer.start(
            options: ChatGPTLoginOptions(
                codexHome: firstTemp.url,
                issuer: "https://issuer.example",
                port: 0,
                openBrowser: false,
                forceState: "first-state"
            ),
            transport: { _ in AuthRefreshHTTPResponse(statusCode: 500, body: Data()) },
            pkceGenerator: { PKCECodes(codeVerifier: "verifier", codeChallenge: "challenge") }
        )

        let firstTask = Task {
            try await firstServer.waitUntilDone()
        }

        let secondTemp = try LoginTemporaryDirectory()
        let secondServer = try ChatGPTLoginServer.start(
            options: ChatGPTLoginOptions(
                codexHome: secondTemp.url,
                issuer: "https://issuer.example",
                port: firstServer.actualPort,
                openBrowser: false,
                forceState: "second-state"
            ),
            transport: { _ in AuthRefreshHTTPResponse(statusCode: 500, body: Data()) },
            pkceGenerator: { PKCECodes(codeVerifier: "verifier", codeChallenge: "challenge") }
        )
        XCTAssertEqual(secondServer.actualPort, firstServer.actualPort)

        await XCTAssertThrowsErrorAsync(try await firstTask.value) { error in
            XCTAssertEqual(String(describing: error), "Login cancelled")
        }

        let cancelURL = try XCTUnwrap(URL(string: "http://127.0.0.1:\(secondServer.actualPort)/cancel"))
        _ = try await URLSession.shared.data(from: cancelURL)
        await XCTAssertThrowsErrorAsync(try await secondServer.waitUntilDone()) { error in
            XCTAssertEqual(String(describing: error), "Login cancelled")
        }
    }

    private static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func fakeJWT(authClaims: [String: Any]) -> String {
        let payload: [String: Any] = [
            "email": "user@example.com",
            "https://api.openai.com/auth": authClaims
        ]
        return [
            base64URL(["alg": "none", "typ": "JWT"]),
            base64URL(payload),
            base64URL(Data("sig".utf8))
        ].joined(separator: ".")
    }

    private static func base64URL(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return base64URL(data)
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

private actor ChatGPTLoginProbe {
    private let idToken: String
    private let accessToken: String
    private var recordedRequests: [RecordedChatGPTLoginRequest] = []

    init(idToken: String, accessToken: String = "access-token") {
        self.idToken = idToken
        self.accessToken = accessToken
    }

    func handle(_ request: URLRequest) throws -> AuthRefreshHTTPResponse {
        let recorded = RecordedChatGPTLoginRequest(request: request)
        recordedRequests.append(recorded)
        guard recorded.url == "https://issuer.example/oauth/token",
              let body = recorded.body
        else {
            return AuthRefreshHTTPResponse(statusCode: 404, body: Data())
        }

        if body.contains("grant_type=authorization_code") {
            return AuthRefreshHTTPResponse(
                statusCode: 200,
                body: Data("""
                {
                  "id_token": "\(idToken)",
                  "access_token": "\(accessToken)",
                  "refresh_token": "refresh-token"
                }
                """.utf8)
            )
        }

        if body.contains("requested_token=openai-api-key") {
            return AuthRefreshHTTPResponse(
                statusCode: 200,
                body: Data(#"{"access_token":"sk-exchanged"}"#.utf8)
            )
        }

        return AuthRefreshHTTPResponse(statusCode: 400, body: Data())
    }

    func requests() -> [RecordedChatGPTLoginRequest] {
        recordedRequests
    }
}

private struct RecordedChatGPTLoginRequest: Equatable, Sendable {
    let method: String
    let url: String
    let headers: [String: String]
    let body: String?

    init(request: URLRequest) {
        method = request.httpMethod ?? "GET"
        url = request.url?.absoluteString ?? ""
        headers = request.allHTTPHeaderFields ?? [:]
        body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) }
    }
}

private final class LoginTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-browser-login-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
