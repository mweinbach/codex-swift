@testable import CodexCore
import Foundation
import XCTest

final class ChatGPTDeviceCodeLoginTests: XCTestCase {
    func testUserCodeResponseAcceptsRustUsercodeAlias() throws {
        let decoded = try JSONDecoder().decode(UserCodeResponse.self, from: Data(#"""
        {
          "device_auth_id": "device-auth-123",
          "usercode": "CODE-12345"
        }
        """#.utf8))

        XCTAssertEqual(decoded.deviceAuthID, "device-auth-123")
        XCTAssertEqual(decoded.userCode, "CODE-12345")
        XCTAssertEqual(decoded.interval, 0)
    }

    func testUserCodeResponseRejectsDuplicateRustUserCodeAlias() throws {
        XCTAssertThrowsError(try JSONDecoder().decode(UserCodeResponse.self, from: Data(#"""
        {
          "device_auth_id": "device-auth-123",
          "user_code": "CODE-12345",
          "usercode": "CODE-67890"
        }
        """#.utf8))) { error in
            guard case let DecodingError.dataCorrupted(context) = error else {
                return XCTFail("expected dataCorrupted error, got \(error)")
            }
            XCTAssertEqual(context.debugDescription, "duplicate field `user_code`")
        }
    }

    func testUserCodeResponseRejectsExplicitNullIntervalLikeRustDeserializeWithDefault() throws {
        XCTAssertThrowsError(try JSONDecoder().decode(UserCodeResponse.self, from: Data(#"""
        {
          "device_auth_id": "device-auth-123",
          "user_code": "CODE-12345",
          "interval": null
        }
        """#.utf8))) { error in
            guard case let DecodingError.dataCorrupted(context) = error else {
                return XCTFail("expected dataCorrupted error, got \(error)")
            }
            XCTAssertEqual(context.debugDescription, "invalid type: null, expected a string")
        }
    }

    func testDeviceCodeLoginPollsExchangesAndPersistsChatGPTTokens() async throws {
        let temp = try DeviceLoginTemporaryDirectory()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let jwt = Self.fakeJWT(accountID: "acct_321")
        let probe = DeviceLoginProbe(scenario: .success(idToken: jwt))
        let messages = DeviceLoginMessageRecorder()

        try await ChatGPTDeviceCodeLogin.run(
            options: ChatGPTDeviceCodeLoginOptions(
                codexHome: temp.url,
                issuer: "https://issuer.example/",
                clientID: "client-id",
                authCredentialsStoreMode: .file,
                cliVersion: "9.9.9"
            ),
            transport: { request in try await probe.handle(request) },
            sleeper: { _ in },
            messageSink: { message in await messages.append(message) },
            now: { now }
        )

        let recordedMessages = await messages.values()
        XCTAssertEqual(recordedMessages, [.userCodePrompt(code: "CODE-12345", version: "9.9.9")])
        XCTAssertTrue(recordedMessages.first?.renderedText.contains("CODE-12345") == true)

        let requests = await probe.requests()
        XCTAssertEqual(requests.map(\.method), ["POST", "POST", "POST", "POST"])
        XCTAssertEqual(requests.map(\.url), [
            "https://issuer.example/api/accounts/deviceauth/usercode",
            "https://issuer.example/api/accounts/deviceauth/token",
            "https://issuer.example/api/accounts/deviceauth/token",
            "https://issuer.example/oauth/token"
        ])
        XCTAssertEqual(try jsonObject(from: requests[0].body)?["client_id"] as? String, "client-id")
        XCTAssertEqual(try jsonObject(from: requests[1].body)?["device_auth_id"] as? String, "device-auth-123")
        XCTAssertEqual(try jsonObject(from: requests[1].body)?["user_code"] as? String, "CODE-12345")
        XCTAssertEqual(
            requests[3].body,
            "grant_type=authorization_code&code=poll-code-321&redirect_uri=https%3A%2F%2Fissuer.example%2Fdeviceauth%2Fcallback&client_id=client-id&code_verifier=code-verifier-321"
        )

        let auth = try XCTUnwrap(CodexAuthStorage.loadAuthDotJSON(codexHome: temp.url, mode: .file))
        XCTAssertNil(auth.openAIAPIKey)
        XCTAssertEqual(auth.lastRefresh, Self.isoString(now))
        XCTAssertEqual(auth.tokens?.accessToken, "access-token-123")
        XCTAssertEqual(auth.tokens?.refreshToken, "refresh-token-123")
        XCTAssertEqual(auth.tokens?.idToken.rawJWT, jwt)
        XCTAssertEqual(auth.tokens?.accountID, "acct_321")
    }

    func testDeviceCodeLoginRejectsWorkspaceMismatchWithoutPersistingAuth() async throws {
        let temp = try DeviceLoginTemporaryDirectory()
        let probe = DeviceLoginProbe(scenario: .success(idToken: Self.fakeJWT(accountID: "acct_actual")))

        await XCTAssertThrowsErrorAsync(try await ChatGPTDeviceCodeLogin.run(
            options: ChatGPTDeviceCodeLoginOptions(
                codexHome: temp.url,
                issuer: "https://issuer.example",
                clientID: "client-id",
                forcedChatGPTWorkspaceID: "acct_required",
                authCredentialsStoreMode: .file
            ),
            transport: { request in try await probe.handle(request) },
            sleeper: { _ in },
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )) { error in
            XCTAssertEqual(
                String(describing: error),
                "Login is restricted to workspace id(s) acct_required."
            )
        }

        XCTAssertNil(try CodexAuthStorage.loadAuthDotJSON(codexHome: temp.url, mode: .file))
    }

    func testDeviceCodeLoginReportsUserCodeHTTPFailures() async throws {
        let temp = try DeviceLoginTemporaryDirectory()
        let probe = DeviceLoginProbe(scenario: .userCodeFailure(statusCode: 503))

        await XCTAssertThrowsErrorAsync(try await ChatGPTDeviceCodeLogin.run(
            options: ChatGPTDeviceCodeLoginOptions(
                codexHome: temp.url,
                issuer: "https://issuer.example",
                clientID: "client-id",
                authCredentialsStoreMode: .file
            ),
            transport: { request in try await probe.handle(request) }
        )) { error in
            XCTAssertEqual(
                String(describing: error),
                "device code request failed with status 503 Service Unavailable"
            )
        }

        XCTAssertNil(try CodexAuthStorage.loadAuthDotJSON(codexHome: temp.url, mode: .file))
    }

    func testDeviceCodeLoginReportsDisabledServerForUserCode404() async throws {
        let temp = try DeviceLoginTemporaryDirectory()
        let probe = DeviceLoginProbe(scenario: .userCodeFailure(statusCode: 404))

        await XCTAssertThrowsErrorAsync(try await ChatGPTDeviceCodeLogin.run(
            options: ChatGPTDeviceCodeLoginOptions(
                codexHome: temp.url,
                issuer: "https://issuer.example",
                clientID: "client-id",
                authCredentialsStoreMode: .file
            ),
            transport: { request in try await probe.handle(request) }
        )) { error in
            XCTAssertEqual(
                String(describing: error),
                "device code login is not enabled for this Codex server. Use the browser login or verify the server URL."
            )
        }
    }

    func testDeviceCodeLoginReportsPollingFailure() async throws {
        let temp = try DeviceLoginTemporaryDirectory()
        let probe = DeviceLoginProbe(scenario: .pollFailure(statusCode: 401))

        await XCTAssertThrowsErrorAsync(try await ChatGPTDeviceCodeLogin.run(
            options: ChatGPTDeviceCodeLoginOptions(
                codexHome: temp.url,
                issuer: "https://issuer.example",
                clientID: "client-id",
                authCredentialsStoreMode: .file
            ),
            transport: { request in try await probe.handle(request) },
            sleeper: { _ in }
        )) { error in
            XCTAssertEqual(String(describing: error), "device auth failed with status 401 Unauthorized")
        }
    }

    private static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func fakeJWT(accountID: String?) -> String {
        var auth: [String: Any] = [:]
        if let accountID {
            auth["chatgpt_account_id"] = accountID
        }
        let payload: [String: Any] = [
            "https://api.openai.com/auth": auth
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
}

private actor DeviceLoginProbe {
    enum Scenario {
        case success(idToken: String)
        case userCodeFailure(statusCode: Int)
        case pollFailure(statusCode: Int)
    }

    private let scenario: Scenario
    private var recordedRequests: [RecordedDeviceLoginRequest] = []
    private var pollCount = 0

    init(scenario: Scenario) {
        self.scenario = scenario
    }

    func handle(_ request: URLRequest) throws -> AuthRefreshHTTPResponse {
        let recorded = RecordedDeviceLoginRequest(request: request)
        recordedRequests.append(recorded)

        switch recorded.url {
        case "https://issuer.example/api/accounts/deviceauth/usercode":
            if case let .userCodeFailure(statusCode) = scenario {
                return AuthRefreshHTTPResponse(statusCode: statusCode, body: Data())
            }
            return AuthRefreshHTTPResponse(
                statusCode: 200,
                body: Data(#"{"device_auth_id":"device-auth-123","user_code":"CODE-12345","interval":"0"}"#.utf8)
            )

        case "https://issuer.example/api/accounts/deviceauth/token":
            if case let .pollFailure(statusCode) = scenario {
                return AuthRefreshHTTPResponse(statusCode: statusCode, body: Data())
            }
            pollCount += 1
            if pollCount == 1 {
                return AuthRefreshHTTPResponse(statusCode: 404, body: Data())
            }
            return AuthRefreshHTTPResponse(
                statusCode: 200,
                body: Data(#"{"authorization_code":"poll-code-321","code_challenge":"code-challenge-321","code_verifier":"code-verifier-321"}"#.utf8)
            )

        case "https://issuer.example/oauth/token":
            guard case let .success(idToken) = scenario else {
                return AuthRefreshHTTPResponse(statusCode: 500, body: Data())
            }
            return AuthRefreshHTTPResponse(
                statusCode: 200,
                body: Data("""
                {
                  "id_token": "\(idToken)",
                  "access_token": "access-token-123",
                  "refresh_token": "refresh-token-123"
                }
                """.utf8)
            )

        default:
            return AuthRefreshHTTPResponse(statusCode: 404, body: Data())
        }
    }

    func requests() -> [RecordedDeviceLoginRequest] {
        recordedRequests
    }
}

private struct RecordedDeviceLoginRequest: Equatable, Sendable {
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

private actor DeviceLoginMessageRecorder {
    private var recorded: [ChatGPTDeviceCodeLoginMessage] = []

    func append(_ message: ChatGPTDeviceCodeLoginMessage) {
        recorded.append(message)
    }

    func values() -> [ChatGPTDeviceCodeLoginMessage] {
        recorded
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

private final class DeviceLoginTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-device-login-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

private func jsonObject(from body: String?) throws -> [String: Any]? {
    guard let data = body?.data(using: .utf8) else {
        return nil
    }
    return try JSONSerialization.jsonObject(with: data) as? [String: Any]
}
