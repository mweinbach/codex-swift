import CodexCore
import XCTest

final class APIAuthTests: XCTestCase {
    func testAddAuthHeadersAddsBearerAndAccountHeaders() {
        let request = APIRequest(
            method: .get,
            url: "https://example.com/models",
            headers: ["x-existing": "1"]
        )

        let authed = request.addingAuthHeaders(from: StaticAPIAuthProvider(
            bearerToken: "token",
            accountID: "account-id"
        ))

        XCTAssertEqual(authed.method, .get)
        XCTAssertEqual(authed.url, request.url)
        XCTAssertEqual(authed.headers, [
            "x-existing": "1",
            "authorization": "Bearer token",
            "ChatGPT-Account-ID": "account-id"
        ])
        XCTAssertNil(authed.body)
        XCTAssertNil(authed.timeoutMilliseconds)
    }

    func testAddAuthHeadersSkipsMissingValues() {
        let request = APIRequest(method: .get, url: "https://example.com/models")

        XCTAssertEqual(
            request.addingAuthHeaders(from: StaticAPIAuthProvider()).headers,
            [:]
        )
    }

    func testAddAuthHeadersSkipsInvalidHeaderValuesLikeRustParseFailures() {
        let request = APIRequest(
            method: .get,
            url: "https://example.com/models",
            headers: ["authorization": "original", "ChatGPT-Account-ID": "original-account"]
        )

        let authed = request.addingAuthHeaders(from: StaticAPIAuthProvider(
            bearerToken: "bad\nvalue",
            accountID: "bad\rvalue"
        ))

        XCTAssertEqual(authed.headers, [
            "authorization": "original",
            "ChatGPT-Account-ID": "original-account"
        ])
    }

    func testAuthResolverUsesProviderEnvironmentAPIKeyFirst() throws {
        let provider = ModelProviderInfo(
            name: "Provider",
            envKey: "PROVIDER_KEY",
            experimentalBearerToken: "experimental"
        )
        let auth = AuthDotJSON(
            openAIAPIKey: "auth-json-key",
            tokens: tokenData(accessToken: "chatgpt-token", accountID: "acct"),
            lastRefresh: nil
        )

        XCTAssertEqual(
            try APIAuthResolver.authProvider(
                auth: auth,
                provider: provider,
                environment: ["PROVIDER_KEY": "provider-key"]
            ),
            StaticAPIAuthProvider(bearerToken: "provider-key")
        )
    }

    func testAuthResolverUsesExperimentalBearerBeforeAuthJSON() throws {
        let provider = ModelProviderInfo(
            name: "Provider",
            experimentalBearerToken: "experimental"
        )
        let auth = AuthDotJSON(
            openAIAPIKey: "auth-json-key",
            tokens: tokenData(accessToken: "chatgpt-token", accountID: "acct"),
            lastRefresh: nil
        )

        XCTAssertEqual(
            try APIAuthResolver.authProvider(auth: auth, provider: provider, environment: [:]),
            StaticAPIAuthProvider(bearerToken: "experimental")
        )
    }

    func testAuthResolverUsesAuthJSONAPIKeyBeforeChatGPTTokens() throws {
        let auth = AuthDotJSON(
            openAIAPIKey: "auth-json-key",
            tokens: tokenData(accessToken: "chatgpt-token", accountID: "acct"),
            lastRefresh: nil
        )

        XCTAssertEqual(
            try APIAuthResolver.authProvider(
                auth: auth,
                provider: ModelProviderInfo(name: "OpenAI"),
                environment: [:]
            ),
            StaticAPIAuthProvider(bearerToken: "auth-json-key")
        )
    }

    func testAuthResolverUsesChatGPTAccessTokenAndAccountID() throws {
        let auth = AuthDotJSON(
            openAIAPIKey: nil,
            tokens: tokenData(accessToken: "chatgpt-token", accountID: "acct"),
            lastRefresh: nil
        )

        XCTAssertEqual(
            try APIAuthResolver.authProvider(
                auth: auth,
                provider: ModelProviderInfo(name: "OpenAI"),
                environment: [:]
            ),
            StaticAPIAuthProvider(bearerToken: "chatgpt-token", accountID: "acct")
        )
    }

    func testAuthResolverReturnsEmptyProviderWhenNoAuthMaterialExists() throws {
        XCTAssertEqual(
            try APIAuthResolver.authProvider(
                auth: nil,
                provider: ModelProviderInfo(name: "OpenAI"),
                environment: [:]
            ),
            StaticAPIAuthProvider()
        )
    }

    func testAuthResolverPropagatesMissingProviderEnvironmentKey() {
        let provider = ModelProviderInfo(
            name: "Provider",
            envKey: "PROVIDER_KEY",
            envKeyInstructions: "Export PROVIDER_KEY."
        )

        XCTAssertThrowsError(
            try APIAuthResolver.authProvider(auth: nil, provider: provider, environment: [:])
        ) { error in
            XCTAssertEqual(
                error as? ModelProviderError,
                .missingEnvironmentVariable(name: "PROVIDER_KEY", instructions: "Export PROVIDER_KEY.")
            )
        }
    }
}

private func tokenData(accessToken: String, accountID: String?) -> AuthTokenData {
    AuthTokenData(
        idToken: IdTokenInfo(rawJWT: "header.payload.signature"),
        accessToken: accessToken,
        refreshToken: "refresh-token",
        accountID: accountID
    )
}
