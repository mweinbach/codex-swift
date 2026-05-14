import CodexCore
import XCTest

final class AuthTests: XCTestCase {
    func testAuthCredentialsStoreModeUsesLowercaseWireValues() throws {
        XCTAssertEqual(try JSONDecoder().decode(AuthCredentialsStoreMode.self, from: Data(#""file""#.utf8)), .file)
        XCTAssertEqual(try JSONDecoder().decode(AuthCredentialsStoreMode.self, from: Data(#""keyring""#.utf8)), .keyring)
        XCTAssertEqual(try JSONDecoder().decode(AuthCredentialsStoreMode.self, from: Data(#""auto""#.utf8)), .auto)
        XCTAssertEqual(try JSONDecoder().decode(AuthCredentialsStoreMode.self, from: Data(#""ephemeral""#.utf8)), .ephemeral)
        XCTAssertEqual(String(data: try JSONEncoder().encode(AuthCredentialsStoreMode.file), encoding: .utf8), #""file""#)
        XCTAssertEqual(String(data: try JSONEncoder().encode(AuthCredentialsStoreMode.ephemeral), encoding: .utf8), #""ephemeral""#)
    }

    func testKnownChatGPTPlanWireValuesAndAliasesMatchRust() throws {
        let cases: [(KnownChatGPTPlan, String, String)] = [
            (.free, "free", "Free"),
            (.go, "go", "Go"),
            (.plus, "plus", "Plus"),
            (.pro, "pro", "Pro"),
            (.proLite, "prolite", "Pro Lite"),
            (.team, "team", "Team"),
            (.selfServeBusinessUsageBased, "self_serve_business_usage_based", "Self Serve Business Usage Based"),
            (.business, "business", "Business"),
            (.enterpriseCbpUsageBased, "enterprise_cbp_usage_based", "Enterprise CBP Usage Based"),
            (.enterprise, "enterprise", "Enterprise"),
            (.edu, "edu", "Edu")
        ]

        for (plan, rawValue, displayName) in cases {
            XCTAssertEqual(try JSONDecoder().decode(KnownChatGPTPlan.self, from: Data("\"\(rawValue)\"".utf8)), plan)
            XCTAssertEqual(String(data: try JSONEncoder().encode(plan), encoding: .utf8), "\"\(rawValue)\"")
            XCTAssertEqual(plan.rustDebugDescription, displayName)
        }

        XCTAssertEqual(KnownChatGPTPlan.fromRawValue("hc"), .enterprise)
        XCTAssertEqual(KnownChatGPTPlan.fromRawValue("education"), .edu)
        XCTAssertNil(KnownChatGPTPlan.fromRawValue("future-plan"))
    }

    func testKnownChatGPTPlanWorkspaceHelperMatchesRust() {
        XCTAssertTrue(KnownChatGPTPlan.team.isWorkspaceAccount)
        XCTAssertTrue(KnownChatGPTPlan.selfServeBusinessUsageBased.isWorkspaceAccount)
        XCTAssertTrue(KnownChatGPTPlan.business.isWorkspaceAccount)
        XCTAssertTrue(KnownChatGPTPlan.enterpriseCbpUsageBased.isWorkspaceAccount)
        XCTAssertTrue(KnownChatGPTPlan.enterprise.isWorkspaceAccount)
        XCTAssertTrue(KnownChatGPTPlan.edu.isWorkspaceAccount)
        XCTAssertFalse(KnownChatGPTPlan.pro.isWorkspaceAccount)
        XCTAssertFalse(KnownChatGPTPlan.go.isWorkspaceAccount)
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

    func testLoadsFileBackedAgentIdentityAuthLikeRust() throws {
        let dir = try AuthTemporaryDirectory()
        let agentIdentity = Self.fakeAgentIdentityJWT()
        let auth = """
        {
          "auth_mode": "agentIdentity",
          "OPENAI_API_KEY": null,
          "tokens": null,
          "last_refresh": null,
          "agent_identity": "\(agentIdentity)"
        }
        """
        try auth.write(to: dir.url.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)

        let loaded = try XCTUnwrap(CodexAuthStorage.loadAuthDotJSON(codexHome: dir.url, mode: .file))
        XCTAssertEqual(loaded.authMode, .agentIdentity)
        XCTAssertNil(loaded.openAIAPIKey)
        XCTAssertNil(loaded.tokens)
        XCTAssertNil(loaded.lastRefresh)
        XCTAssertEqual(loaded.agentIdentity, agentIdentity)
        XCTAssertEqual(try CodexAuthStorage.authStatus(codexHome: dir.url, mode: .file), .chatGPT)
    }

    func testLoginWithAccessTokenRejectsInvalidAgentIdentityJWTBeforePersisting() async throws {
        let dir = try AuthTemporaryDirectory()

        await XCTAssertThrowsErrorAsync(
            try await CodexAuthStorage.loginWithAccessToken(
                codexHome: dir.url,
                accessToken: "not-a-jwt",
                chatGPTBaseURL: "https://chatgpt.com/backend-api",
                transport: AuthFailingTransport()
            )
        ) { error in
            XCTAssertEqual((error as? AgentIdentityError)?.description, "invalid agent identity JWT format")
        }
        XCTAssertNil(try CodexAuthStorage.loadAuthDotJSON(codexHome: dir.url, mode: .file))
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
        let keyringStore = InMemoryAuthKeyringStore()
        XCTAssertNil(try CodexAuthStorage.loadAuthDotJSON(codexHome: dir.url, mode: .file))
        XCTAssertNil(try CodexAuthStorage.loadTokenData(codexHome: dir.url, mode: .auto, keyringStore: keyringStore))
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

    func testEphemeralAuthTakesPrecedenceAndLogoutClearsBothStores() throws {
        let dir = try AuthTemporaryDirectory()
        let accessToken = Self.fakeJWT(plan: "pro", accountID: "org-embedded")

        try CodexAuthStorage.loginWithAPIKey(codexHome: dir.url, apiKey: "sk-file")
        try CodexAuthStorage.saveChatGPTAuthTokens(
            codexHome: dir.url,
            accessToken: accessToken,
            chatGPTAccountID: "org-embedded",
            chatGPTPlanType: "pro",
            mode: .ephemeral
        )

        XCTAssertEqual(try CodexAuthStorage.loadAuthDotJSON(codexHome: dir.url, mode: .file)?.openAIAPIKey, "sk-file")
        let effective = try XCTUnwrap(CodexAuthStorage.loadEffectiveAuthDotJSON(codexHome: dir.url, mode: .file))
        XCTAssertEqual(effective.authMode, .chatGPTAuthTokens)
        XCTAssertEqual(effective.tokens?.accessToken, accessToken)
        XCTAssertEqual(try CodexAuthStorage.authStatus(codexHome: dir.url, mode: .file), .chatGPT)

        XCTAssertTrue(try CodexAuthStorage.logout(codexHome: dir.url, mode: .file))
        XCTAssertNil(try CodexAuthStorage.loadAuthDotJSON(codexHome: dir.url, mode: .ephemeral))
        XCTAssertNil(try CodexAuthStorage.loadAuthDotJSON(codexHome: dir.url, mode: .file))
        XCTAssertNil(try CodexAuthStorage.loadEffectiveAuthDotJSON(codexHome: dir.url, mode: .file))
    }

    func testKeyringStoreKeyMatchesRustHash() {
        let codexHome = URL(string: "file:~/.codex")!
        XCTAssertEqual(CodexAuthStorage.computeKeyringStoreKey(codexHome: codexHome), "cli|940db7b1d0e4eb40")
    }

    func testKeyringModeLoadsSavesAndRemovesFallbackFile() throws {
        let dir = try AuthTemporaryDirectory()
        let keyringStore = InMemoryAuthKeyringStore()
        try CodexAuthStorage.loginWithAPIKey(codexHome: dir.url, apiKey: "sk-file")

        let keyringAuth = AuthDotJSON(openAIAPIKey: "sk-keyring", tokens: nil, lastRefresh: nil)
        try CodexAuthStorage.saveAuthDotJSON(
            keyringAuth,
            codexHome: dir.url,
            mode: .keyring,
            keyringStore: keyringStore
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.url.appendingPathComponent("auth.json").path))
        XCTAssertEqual(
            try CodexAuthStorage.loadAuthDotJSON(codexHome: dir.url, mode: .keyring, keyringStore: keyringStore),
            keyringAuth
        )
        XCTAssertEqual(
            try CodexAuthStorage.authStatus(codexHome: dir.url, mode: .keyring, keyringStore: keyringStore),
            .apiKey("sk-keyring")
        )

        try CodexAuthStorage.loginWithAPIKey(codexHome: dir.url, apiKey: "sk-fallback-file")
        XCTAssertTrue(try CodexAuthStorage.logout(codexHome: dir.url, mode: .keyring, keyringStore: keyringStore))
        XCTAssertNil(keyringStore.value(service: CodexAuthStorage.keyringService, account: Self.keyringAccount(for: dir.url)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.url.appendingPathComponent("auth.json").path))
        XCTAssertFalse(try CodexAuthStorage.logout(codexHome: dir.url, mode: .keyring, keyringStore: keyringStore))
    }

    func testAutoModePrefersKeyringAndFallsBackToFile() throws {
        let dir = try AuthTemporaryDirectory()
        let keyringStore = InMemoryAuthKeyringStore()
        try CodexAuthStorage.loginWithAPIKey(codexHome: dir.url, apiKey: "sk-file")
        try CodexAuthStorage.saveAuthDotJSON(
            AuthDotJSON(openAIAPIKey: "sk-keyring", tokens: nil, lastRefresh: nil),
            codexHome: dir.url,
            mode: .keyring,
            keyringStore: keyringStore
        )
        try CodexAuthStorage.loginWithAPIKey(codexHome: dir.url, apiKey: "sk-file")

        XCTAssertEqual(
            try CodexAuthStorage.authStatus(codexHome: dir.url, mode: .auto, keyringStore: keyringStore),
            .apiKey("sk-keyring")
        )

        keyringStore.set(nil, service: CodexAuthStorage.keyringService, account: Self.keyringAccount(for: dir.url))
        XCTAssertEqual(
            try CodexAuthStorage.authStatus(codexHome: dir.url, mode: .auto, keyringStore: keyringStore),
            .apiKey("sk-file")
        )
    }

    func testAutoModeFallsBackToFileWhenKeyringLoadFails() throws {
        let dir = try AuthTemporaryDirectory()
        let keyringStore = InMemoryAuthKeyringStore()
        keyringStore.loadError = KeyringTestError("boom")
        try CodexAuthStorage.loginWithAPIKey(codexHome: dir.url, apiKey: "sk-file")

        XCTAssertEqual(
            try CodexAuthStorage.authStatus(codexHome: dir.url, mode: .auto, keyringStore: keyringStore),
            .apiKey("sk-file")
        )
    }

    func testAutoModeSaveFallsBackToFileWhenKeyringSaveFails() throws {
        let dir = try AuthTemporaryDirectory()
        let keyringStore = InMemoryAuthKeyringStore()
        keyringStore.saveError = KeyringTestError("boom")

        try CodexAuthStorage.loginWithAPIKey(
            codexHome: dir.url,
            apiKey: "sk-auto",
            mode: .auto,
            keyringStore: keyringStore
        )

        XCTAssertNil(keyringStore.value(service: CodexAuthStorage.keyringService, account: Self.keyringAccount(for: dir.url)))
        XCTAssertEqual(try CodexAuthStorage.authStatus(codexHome: dir.url, mode: .file), .apiKey("sk-auto"))
    }

    func testAutoModeDeleteRemovesKeyringAndFile() throws {
        let dir = try AuthTemporaryDirectory()
        let keyringStore = InMemoryAuthKeyringStore()
        try CodexAuthStorage.saveAuthDotJSON(
            AuthDotJSON(openAIAPIKey: "sk-keyring", tokens: nil, lastRefresh: nil),
            codexHome: dir.url,
            mode: .keyring,
            keyringStore: keyringStore
        )
        try CodexAuthStorage.loginWithAPIKey(codexHome: dir.url, apiKey: "sk-file")

        XCTAssertTrue(try CodexAuthStorage.logout(codexHome: dir.url, mode: .auto, keyringStore: keyringStore))
        XCTAssertNil(keyringStore.value(service: CodexAuthStorage.keyringService, account: Self.keyringAccount(for: dir.url)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.url.appendingPathComponent("auth.json").path))
        XCTAssertFalse(try CodexAuthStorage.logout(codexHome: dir.url, mode: .auto, keyringStore: keyringStore))
    }

    func testEnforceLoginRestrictionsLogsOutForMethodMismatch() async throws {
        let dir = try AuthTemporaryDirectory()
        try CodexAuthStorage.loginWithAPIKey(codexHome: dir.url, apiKey: "sk-test")

        await XCTAssertThrowsErrorAsync(try await CodexAuthStorage.enforceLoginRestrictions(
            codexHome: dir.url,
            config: CodexRuntimeConfig(forcedLoginMethod: .chatgpt),
            environment: [:]
        )) { error in
            XCTAssertEqual(
                (error as? CodexAuthRestrictionError)?.description,
                "ChatGPT login is required, but an API key is currently being used. Logging out."
            )
        }
        XCTAssertNil(try CodexAuthStorage.loadAuthDotJSON(codexHome: dir.url, mode: .file))
    }

    func testEnforceLoginRestrictionsAllowsMatchingMethod() async throws {
        let dir = try AuthTemporaryDirectory()
        try CodexAuthStorage.loginWithAPIKey(codexHome: dir.url, apiKey: "sk-test")

        try await CodexAuthStorage.enforceLoginRestrictions(
            codexHome: dir.url,
            config: CodexRuntimeConfig(forcedLoginMethod: .api),
            environment: [:]
        )

        XCTAssertEqual(try CodexAuthStorage.authStatus(codexHome: dir.url), .apiKey("sk-test"))
    }

    func testEnforceLoginRestrictionsLogsOutForWorkspaceMismatch() async throws {
        let dir = try AuthTemporaryDirectory()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try Self.writeAuth(
            to: dir.url,
            accessToken: "access-token",
            refreshToken: "refresh-token",
            lastRefresh: Self.isoString(now),
            jwtAccountID: "org_other"
        )

        await XCTAssertThrowsErrorAsync(try await CodexAuthStorage.enforceLoginRestrictions(
            codexHome: dir.url,
            config: CodexRuntimeConfig(forcedChatGPTWorkspaceID: "org_mine"),
            environment: [:]
        )) { error in
            XCTAssertEqual(
                (error as? CodexAuthRestrictionError)?.description,
                "Login is restricted to workspace org_mine, but current credentials belong to org_other. Logging out."
            )
        }
        XCTAssertNil(try CodexAuthStorage.loadAuthDotJSON(codexHome: dir.url, mode: .file))
    }

    func testEnforceLoginRestrictionsAllowsMatchingWorkspace() async throws {
        let dir = try AuthTemporaryDirectory()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try Self.writeAuth(
            to: dir.url,
            accessToken: "access-token",
            refreshToken: "refresh-token",
            lastRefresh: Self.isoString(now),
            jwtAccountID: "org_mine"
        )

        try await CodexAuthStorage.enforceLoginRestrictions(
            codexHome: dir.url,
            config: CodexRuntimeConfig(forcedChatGPTWorkspaceID: "org_mine"),
            environment: [:]
        )

        XCTAssertEqual(try CodexAuthStorage.authStatus(codexHome: dir.url), .chatGPT)
    }

    func testEnforceLoginRestrictionsAllowsAPIKeyWhenOnlyWorkspaceIsForced() async throws {
        let dir = try AuthTemporaryDirectory()
        try CodexAuthStorage.loginWithAPIKey(codexHome: dir.url, apiKey: "sk-test")

        try await CodexAuthStorage.enforceLoginRestrictions(
            codexHome: dir.url,
            config: CodexRuntimeConfig(forcedChatGPTWorkspaceID: "org_mine"),
            environment: [:]
        )

        XCTAssertEqual(try CodexAuthStorage.authStatus(codexHome: dir.url), .apiKey("sk-test"))
    }

    func testEnforceLoginRestrictionsBlocksEnvironmentAPIKeyWhenChatGPTRequired() async throws {
        let dir = try AuthTemporaryDirectory()

        await XCTAssertThrowsErrorAsync(try await CodexAuthStorage.enforceLoginRestrictions(
            codexHome: dir.url,
            config: CodexRuntimeConfig(forcedLoginMethod: .chatgpt),
            environment: [CodexAuthStorage.codexAPIKeyEnvironmentVariable: " sk-env\n"]
        )) { error in
            XCTAssertEqual(
                (error as? CodexAuthRestrictionError)?.description,
                "ChatGPT login is required, but an API key is currently being used. Logging out."
            )
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

    func testParsesIDTokenPlanAliasesAndUsageBasedPlans() throws {
        XCTAssertEqual(try IdTokenParser.parse(Self.fakeJWT(plan: "hc", accountID: nil)).getChatGPTPlanType(), "Enterprise")
        XCTAssertEqual(try IdTokenParser.parse(Self.fakeJWT(plan: "education", accountID: nil)).getChatGPTPlanType(), "Edu")
        XCTAssertEqual(try IdTokenParser.parse(Self.fakeJWT(plan: "prolite", accountID: nil)).getChatGPTPlanType(), "Pro Lite")
        XCTAssertEqual(
            try IdTokenParser.parse(Self.fakeJWT(plan: "self_serve_business_usage_based", accountID: nil))
                .getChatGPTPlanType(),
            "Self Serve Business Usage Based"
        )
        XCTAssertEqual(
            try IdTokenParser.parse(Self.fakeJWT(plan: "enterprise_cbp_usage_based", accountID: nil))
                .getChatGPTPlanType(),
            "Enterprise CBP Usage Based"
        )
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
        lastRefresh: String,
        jwtAccountID: String? = "jwt-account-id"
    ) throws {
        let auth = """
        {
          "OPENAI_API_KEY": null,
          "tokens": {
            "id_token": "\(Self.fakeJWT(accountID: jwtAccountID))",
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

    private static func fakeAgentIdentityJWT() -> String {
        fakeJWT(payload: [
            "iss": AgentIdentity.jwtIssuer,
            "aud": AgentIdentity.jwtAudience,
            "iat": 1_800_000_000,
            "exp": 1_800_003_600,
            "agent_runtime_id": "agent-runtime-123",
            "agent_private_key": "private-key",
            "account_id": "account-123",
            "chatgpt_user_id": "user-123",
            "email": "agent@example.com",
            "plan_type": "business",
            "chatgpt_account_is_fedramp": false
        ])
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

    private static func keyringAccount(for codexHome: URL) -> String {
        CodexAuthStorage.computeKeyringStoreKey(codexHome: codexHome)
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

private struct AuthFailingTransport: APITransport {
    func execute(_ request: APIRequest) async -> Result<APIResponse, TransportError> {
        XCTFail("invalid agent identity JWT should fail before fetching JWKS")
        return .success(APIResponse(statusCode: 500))
    }

    func stream(_ request: APIRequest) async -> Result<APIStreamResponse, TransportError> {
        XCTFail("auth tests should not stream")
        return .failure(.network("unexpected stream"))
    }
}

private struct KeyringTestError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private final class InMemoryAuthKeyringStore: AuthKeyringStore, @unchecked Sendable {
    private struct Key: Hashable {
        let service: String
        let account: String
    }

    private let lock = NSLock()
    private var entries: [Key: String] = [:]

    var loadError: Error?
    var saveError: Error?
    var deleteError: Error?

    func load(service: String, account: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        if let loadError {
            throw loadError
        }
        return entries[Key(service: service, account: account)]
    }

    func save(service: String, account: String, value: String) throws {
        lock.lock()
        defer { lock.unlock() }
        if let saveError {
            throw saveError
        }
        entries[Key(service: service, account: account)] = value
    }

    func delete(service: String, account: String) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let deleteError {
            throw deleteError
        }
        return entries.removeValue(forKey: Key(service: service, account: account)) != nil
    }

    func value(service: String, account: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return entries[Key(service: service, account: account)]
    }

    func set(_ value: String?, service: String, account: String) {
        lock.lock()
        defer { lock.unlock() }
        if let value {
            entries[Key(service: service, account: account)] = value
        } else {
            entries.removeValue(forKey: Key(service: service, account: account))
        }
    }
}
