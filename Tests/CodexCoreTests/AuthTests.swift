import CodexCore
import XCTest

final class AuthTests: XCTestCase {
    func testAuthCredentialsStoreModeUsesLowercaseWireValues() throws {
        XCTAssertEqual(try JSONDecoder().decode(AuthCredentialsStoreMode.self, from: Data(#""file""#.utf8)), .file)
        XCTAssertEqual(try JSONDecoder().decode(AuthCredentialsStoreMode.self, from: Data(#""keyring""#.utf8)), .keyring)
        XCTAssertEqual(try JSONDecoder().decode(AuthCredentialsStoreMode.self, from: Data(#""auto""#.utf8)), .auto)
        XCTAssertEqual(String(data: try JSONEncoder().encode(AuthCredentialsStoreMode.file), encoding: .utf8), #""file""#)
    }

    func testLoadsFileBackedAuthJSONTokenData() throws {
        let dir = try AuthTemporaryDirectory()
        let jwt = Self.fakeJWT(plan: "pro", accountID: "jwt-account-id")
        let auth = """
        {
          "OPENAI_API_KEY": null,
          "tokens": {
            "id_token": "\(jwt)",
            "access_token": "access-token",
            "refresh_token": "refresh-token",
            "account_id": "account-id"
          },
          "last_refresh": "2026-05-07T00:00:00Z"
        }
        """
        try auth.write(to: dir.url.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)

        let loaded = try CodexAuthStorage.loadAuthDotJSON(codexHome: dir.url, mode: .file)
        XCTAssertEqual(loaded?.tokens?.accessToken, "access-token")
        XCTAssertEqual(loaded?.tokens?.accountID, "account-id")
        XCTAssertEqual(loaded?.tokens?.idToken.email, "user@example.com")
        XCTAssertEqual(loaded?.tokens?.idToken.getChatGPTPlanType(), "Pro")
        XCTAssertEqual(loaded?.tokens?.idToken.chatGPTAccountID, "jwt-account-id")
        XCTAssertEqual(loaded?.lastRefresh, "2026-05-07T00:00:00Z")
    }

    func testLoadFreshTokenDataUsesRecentTokenWithoutRefresh() async throws {
        let dir = try AuthTemporaryDirectory()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try Self.writeAuth(
            to: dir.url,
            accessToken: "recent-access-token",
            refreshToken: "recent-refresh-token",
            lastRefresh: Self.isoString(now)
        )

        let token = try await CodexAuthStorage.loadFreshTokenData(
            codexHome: dir.url,
            now: now,
            refreshTransport: { _ in
                XCTFail("recent tokens should not refresh")
                return AuthRefreshHTTPResponse(statusCode: 500, body: Data())
            }
        )

        XCTAssertEqual(token?.accessToken, "recent-access-token")
        XCTAssertEqual(token?.refreshToken, "recent-refresh-token")
    }

    func testLoadFreshTokenDataRefreshesStaleTokenAndUpdatesStorage() async throws {
        let dir = try AuthTemporaryDirectory()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let staleRefresh = now.addingTimeInterval(-9 * 24 * 60 * 60)
        try Self.writeAuth(
            to: dir.url,
            accessToken: "initial-access-token",
            refreshToken: "initial-refresh-token",
            lastRefresh: Self.isoString(staleRefresh)
        )

        var capturedRequest: URLRequest?
        let token = try await CodexAuthStorage.loadFreshTokenData(
            codexHome: dir.url,
            now: now,
            environment: [CodexAuthStorage.refreshTokenURLEnvironmentOverride: "https://auth.example.test/oauth/token"],
            refreshTransport: { request in
                capturedRequest = request
                return AuthRefreshHTTPResponse(
                    statusCode: 200,
                    body: Data(#"{"access_token":"new-access-token","refresh_token":"new-refresh-token"}"#.utf8)
                )
            }
        )

        XCTAssertEqual(token?.idToken.rawJWT, Self.fakeJWT())
        XCTAssertEqual(token?.accessToken, "new-access-token")
        XCTAssertEqual(token?.refreshToken, "new-refresh-token")
        XCTAssertEqual(token?.accountID, "account-id")
        XCTAssertEqual(capturedRequest?.url?.absoluteString, "https://auth.example.test/oauth/token")
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(capturedRequest?.httpBody)
        let refreshRequest = try JSONDecoder().decode(RefreshRequestBody.self, from: body)
        XCTAssertEqual(refreshRequest.clientID, CodexAuthStorage.refreshClientID)
        XCTAssertEqual(refreshRequest.grantType, "refresh_token")
        XCTAssertEqual(refreshRequest.refreshToken, "initial-refresh-token")
        XCTAssertEqual(refreshRequest.scope, "openid profile email")

        let stored = try CodexAuthStorage.loadAuthDotJSON(codexHome: dir.url, mode: .file)
        XCTAssertEqual(stored?.tokens?.accessToken, "new-access-token")
        XCTAssertEqual(stored?.tokens?.refreshToken, "new-refresh-token")
        XCTAssertEqual(stored?.lastRefresh, Self.isoString(now))
    }

    func testLoadFreshTokenDataReportsPermanentRefreshFailureAndLeavesStorageUnchanged() async throws {
        let dir = try AuthTemporaryDirectory()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let staleRefresh = now.addingTimeInterval(-9 * 24 * 60 * 60)
        try Self.writeAuth(
            to: dir.url,
            accessToken: "initial-access-token",
            refreshToken: "initial-refresh-token",
            lastRefresh: Self.isoString(staleRefresh)
        )

        await XCTAssertThrowsErrorAsync(try await CodexAuthStorage.loadFreshTokenData(
            codexHome: dir.url,
            now: now,
            refreshTransport: { _ in
                AuthRefreshHTTPResponse(
                    statusCode: 401,
                    body: Data(#"{"error":{"code":"refresh_token_expired"}}"#.utf8)
                )
            }
        )) { error in
            XCTAssertEqual(
                (error as? CodexAuthStorageError)?.description,
                "Your access token could not be refreshed because your refresh token has expired. Please log out and sign in again."
            )
        }

        let stored = try CodexAuthStorage.loadAuthDotJSON(codexHome: dir.url, mode: .file)
        XCTAssertEqual(stored?.tokens?.accessToken, "initial-access-token")
        XCTAssertEqual(stored?.tokens?.refreshToken, "initial-refresh-token")
        XCTAssertEqual(stored?.lastRefresh, Self.isoString(staleRefresh))
    }

    func testLoadFreshTokenDataReportsTransientRefreshFailureMessage() async throws {
        let dir = try AuthTemporaryDirectory()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let staleRefresh = now.addingTimeInterval(-9 * 24 * 60 * 60)
        try Self.writeAuth(
            to: dir.url,
            accessToken: "initial-access-token",
            refreshToken: "initial-refresh-token",
            lastRefresh: Self.isoString(staleRefresh)
        )

        await XCTAssertThrowsErrorAsync(try await CodexAuthStorage.loadFreshTokenData(
            codexHome: dir.url,
            now: now,
            refreshTransport: { _ in
                AuthRefreshHTTPResponse(
                    statusCode: 500,
                    body: Data(#"{"error":{"message":"temporary-failure"}}"#.utf8)
                )
            }
        )) { error in
            XCTAssertEqual(
                (error as? CodexAuthStorageError)?.description,
                "Failed to refresh token: 500 Internal Server Error: temporary-failure"
            )
        }
    }

    func testMissingAuthJSONReturnsNil() throws {
        let dir = try AuthTemporaryDirectory()
        XCTAssertNil(try CodexAuthStorage.loadAuthDotJSON(codexHome: dir.url, mode: .file))
        XCTAssertNil(try CodexAuthStorage.loadTokenData(codexHome: dir.url, mode: .auto))
    }

    func testLoginWithAPIKeyClearsChatGPTTokens() throws {
        let dir = try AuthTemporaryDirectory()
        try Self.writeAuth(
            to: dir.url,
            accessToken: "stale-access-token",
            refreshToken: "stale-refresh-token",
            lastRefresh: "2026-05-07T00:00:00Z"
        )

        try CodexAuthStorage.loginWithAPIKey(codexHome: dir.url, apiKey: "sk-new")

        let loaded = try CodexAuthStorage.loadAuthDotJSON(codexHome: dir.url, mode: .file)
        XCTAssertEqual(loaded?.openAIAPIKey, "sk-new")
        XCTAssertNil(loaded?.tokens)
        XCTAssertNil(loaded?.lastRefresh)
        XCTAssertEqual(try CodexAuthStorage.authStatus(codexHome: dir.url), .apiKey("sk-new"))
    }

    func testAuthStatusReportsChatGPTAndNotLoggedIn() throws {
        let dir = try AuthTemporaryDirectory()
        XCTAssertEqual(try CodexAuthStorage.authStatus(codexHome: dir.url), .notLoggedIn)

        try Self.writeAuth(
            to: dir.url,
            accessToken: "access-token",
            refreshToken: "refresh-token",
            lastRefresh: "2026-05-07T00:00:00Z"
        )

        XCTAssertEqual(try CodexAuthStorage.authStatus(codexHome: dir.url), .chatGPT)
    }

    func testLogoutRemovesAuthJSONAndReportsMissingAsNotLoggedIn() throws {
        let dir = try AuthTemporaryDirectory()
        try CodexAuthStorage.loginWithAPIKey(codexHome: dir.url, apiKey: "sk-test")

        XCTAssertTrue(try CodexAuthStorage.logout(codexHome: dir.url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.url.appendingPathComponent("auth.json").path))
        XCTAssertFalse(try CodexAuthStorage.logout(codexHome: dir.url))
    }

    func testKeyringModeReportsUnavailableUntilPorted() throws {
        let dir = try AuthTemporaryDirectory()
        XCTAssertThrowsError(try CodexAuthStorage.loadAuthDotJSON(codexHome: dir.url, mode: .keyring)) { error in
            XCTAssertEqual(error as? CodexAuthStorageError, .keyringStoreNotAvailable)
        }
    }

    func testParsesIDTokenEmailPlanAndAccountID() throws {
        let jwt = Self.fakeJWT(plan: "pro", accountID: "acct-123")

        let info = try IdTokenParser.parse(jwt)

        XCTAssertEqual(info.email, "user@example.com")
        XCTAssertEqual(info.getChatGPTPlanType(), "Pro")
        XCTAssertEqual(info.chatGPTAccountID, "acct-123")
        XCTAssertEqual(info.rawJWT, jwt)
    }

    func testParsesIDTokenMissingAuthFields() throws {
        let jwt = Self.fakeJWT(payload: ["sub": "123"])

        let info = try IdTokenParser.parse(jwt)

        XCTAssertNil(info.email)
        XCTAssertNil(info.getChatGPTPlanType())
        XCTAssertNil(info.chatGPTAccountID)
    }

    func testParsesUnknownPlanAsRawString() throws {
        let jwt = Self.fakeJWT(plan: "mystery-tier", accountID: nil)

        XCTAssertEqual(try IdTokenParser.parse(jwt).getChatGPTPlanType(), "mystery-tier")
    }

    func testIDTokenRejectsInvalidShape() {
        XCTAssertThrowsError(try IdTokenParser.parse("header.payload")) { error in
            XCTAssertEqual(error as? IdTokenInfoError, .invalidFormat)
        }
    }

    func testCodexHomeHonorsExistingEnvironmentPath() throws {
        let dir = try AuthTemporaryDirectory()
        XCTAssertEqual(try CodexHome.find(environment: ["CODEX_HOME": dir.url.path]).path, dir.url.resolvingSymlinksInPath().path)
    }

    func testCodexHomeRejectsMissingEnvironmentPath() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        XCTAssertThrowsError(try CodexHome.find(environment: ["CODEX_HOME": missing])) { error in
            XCTAssertEqual(error as? CodexHomeError, .codexHomeDoesNotExist(missing))
        }
    }

    private static func writeAuth(
        to codexHome: URL,
        accessToken: String,
        refreshToken: String,
        lastRefresh: String
    ) throws {
        let auth = """
        {
          "OPENAI_API_KEY": null,
          "tokens": {
            "id_token": "\(Self.fakeJWT())",
            "access_token": "\(accessToken)",
            "refresh_token": "\(refreshToken)",
            "account_id": "account-id"
          },
          "last_refresh": "\(lastRefresh)"
        }
        """
        try auth.write(to: codexHome.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)
    }

    private static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func fakeJWT(
        plan: String? = "pro",
        accountID: String? = "jwt-account-id",
        payload customPayload: [String: Any]? = nil
    ) -> String {
        let header: [String: Any] = ["alg": "none", "typ": "JWT"]
        let payload: [String: Any]
        if let customPayload {
            payload = customPayload
        } else {
            var auth: [String: Any] = [:]
            if let plan {
                auth["chatgpt_plan_type"] = plan
            }
            if let accountID {
                auth["chatgpt_account_id"] = accountID
            }
            payload = [
                "email": "user@example.com",
                "https://api.openai.com/auth": auth
            ]
        }

        return [
            base64URL(header),
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

private struct RefreshRequestBody: Decodable {
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

private final class AuthTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
