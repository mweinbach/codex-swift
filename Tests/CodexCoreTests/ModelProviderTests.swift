import XCTest
@testable import CodexCore

final class ModelProviderTests: XCTestCase {
    func testConfiguredProviderUsesDefaultCapabilities() {
        let provider = ModelProviderFactory.create(
            providerInfo: .createOpenAIProvider(environment: [:])
        )

        XCTAssertEqual(provider.capabilities(), ModelProviderCapabilities())
    }

    func testConfiguredProviderRuntimeBaseURLUsesConfiguredBaseURL() throws {
        let provider = ModelProviderFactory.create(
            providerInfo: providerInfo(baseURL: "https://example.test/v1")
        )

        XCTAssertEqual(try provider.runtimeBaseURL(), "https://example.test/v1")
    }

    func testOpenAIProviderReturnsUnauthenticatedOpenAIAccountState() throws {
        let provider = ModelProviderFactory.create(
            providerInfo: .createOpenAIProvider(environment: [:])
        )

        XCTAssertEqual(
            try provider.accountState(),
            ProviderAccountState(account: nil, requiresOpenAIAuth: true)
        )
    }

    func testOpenAIProviderReturnsAPIKeyAccountState() throws {
        let provider = ModelProviderFactory.create(
            providerInfo: .createOpenAIProvider(environment: [:]),
            auth: AuthDotJSON(authMode: .apiKey, openAIAPIKey: "openai-api-key", tokens: nil, lastRefresh: nil)
        )

        XCTAssertEqual(
            try provider.accountState(),
            ProviderAccountState(account: .apiKey, requiresOpenAIAuth: true)
        )
    }

    func testOpenAIProviderReturnsChatGPTAccountState() throws {
        let provider = ModelProviderFactory.create(
            providerInfo: .createOpenAIProvider(environment: [:]),
            auth: AuthDotJSON(
                authMode: .chatGPT,
                openAIAPIKey: nil,
                tokens: tokenData(email: "user@example.com", plan: "pro", accountID: "acct-123"),
                lastRefresh: nil
            )
        )

        XCTAssertEqual(
            try provider.accountState(),
            ProviderAccountState(
                account: .chatGPT(email: "user@example.com", planType: .pro),
                requiresOpenAIAuth: true
            )
        )
    }

    func testOpenAIProviderTreatsLegacyTokenAuthWithoutModeAsChatGPT() throws {
        let provider = ModelProviderFactory.create(
            providerInfo: .createOpenAIProvider(environment: [:]),
            auth: AuthDotJSON(
                authMode: nil,
                openAIAPIKey: nil,
                tokens: tokenData(email: "user@example.com", plan: "plus", accountID: "acct-123"),
                lastRefresh: nil
            )
        )

        XCTAssertEqual(
            try provider.accountState(),
            ProviderAccountState(
                account: .chatGPT(email: "user@example.com", planType: .plus),
                requiresOpenAIAuth: true
            )
        )
        XCTAssertTrue(provider.supportsAttestation())
        XCTAssertEqual(
            try provider.apiProvider(environment: [:]).baseURL,
            "https://chatgpt.com/backend-api/codex"
        )
    }

    func testOpenAIProviderMissingChatGPTDetailsReportsRustError() {
        let provider = ModelProviderFactory.create(
            providerInfo: .createOpenAIProvider(environment: [:]),
            auth: AuthDotJSON(
                authMode: .chatGPT,
                openAIAPIKey: nil,
                tokens: tokenData(email: nil, plan: "pro", accountID: "acct-123"),
                lastRefresh: nil
            )
        )

        XCTAssertThrowsError(try provider.accountState()) { error in
            XCTAssertEqual(error as? ProviderAccountError, .missingChatGPTAccountDetails)
            XCTAssertEqual(
                String(describing: error),
                "email and plan type are required for chatgpt authentication"
            )
        }
    }

    func testConfiguredProviderAttestationRequiresChatGPTAuth() {
        let unauthenticated = ModelProviderFactory.create(
            providerInfo: .createOpenAIProvider(environment: [:])
        )
        let apiKey = ModelProviderFactory.create(
            providerInfo: .createOpenAIProvider(environment: [:]),
            auth: AuthDotJSON(authMode: .apiKey, openAIAPIKey: "openai-api-key", tokens: nil, lastRefresh: nil)
        )
        let chatGPT = ModelProviderFactory.create(
            providerInfo: .createOpenAIProvider(environment: [:]),
            auth: AuthDotJSON(
                authMode: .chatGPTAuthTokens,
                openAIAPIKey: nil,
                tokens: tokenData(email: "user@example.com", plan: "team", accountID: "acct-123"),
                lastRefresh: nil
            )
        )

        XCTAssertFalse(unauthenticated.supportsAttestation())
        XCTAssertFalse(apiKey.supportsAttestation())
        XCTAssertTrue(chatGPT.supportsAttestation())
    }

    func testCustomNonOpenAIProviderReturnsNoAccountState() throws {
        let provider = ModelProviderFactory.create(
            providerInfo: ModelProviderInfo(
                name: "Custom",
                baseURL: "http://localhost:1234/v1",
                wireAPI: .responses,
                requiresOpenAIAuth: false
            )
        )

        XCTAssertEqual(
            try provider.accountState(),
            ProviderAccountState(account: nil, requiresOpenAIAuth: false)
        )
    }

    func testAmazonBedrockProviderReturnsBedrockAccountStateAndIgnoresOpenAIAuth() throws {
        let provider = ModelProviderFactory.create(
            providerInfo: .createAmazonBedrockProvider(),
            auth: AuthDotJSON(authMode: .apiKey, openAIAPIKey: "openai-api-key", tokens: nil, lastRefresh: nil)
        )

        XCTAssertEqual(
            try provider.accountState(),
            ProviderAccountState(account: .amazonBedrock, requiresOpenAIAuth: false)
        )
        XCTAssertFalse(provider.supportsAttestation())
        XCTAssertEqual(
            try provider.apiAuth(environment: ["CODEX_API_KEY": "ignored-openai-key"]),
            StaticAPIAuthProvider()
        )
    }

    func testConfiguredProviderAPIProviderAndAuthUseProviderConfiguration() throws {
        let provider = ModelProviderFactory.create(
            providerInfo: ModelProviderInfo(
                name: "Custom",
                baseURL: nil,
                envKey: "CUSTOM_API_KEY",
                experimentalBearerToken: "fallback-token",
                wireAPI: .responses,
                httpHeaders: ["X-Test": "1"],
                requiresOpenAIAuth: false
            ),
            auth: AuthDotJSON(authMode: .apiKey, openAIAPIKey: "openai-api-key", tokens: nil, lastRefresh: nil)
        )

        XCTAssertEqual(try provider.apiProvider(environment: [:]).baseURL, "https://api.openai.com/v1")
        XCTAssertEqual(try provider.apiProvider(environment: [:]).headers, ["X-Test": "1"])
        XCTAssertEqual(
            try provider.apiAuth(environment: ["CUSTOM_API_KEY": "provider-token"]),
            StaticAPIAuthProvider(bearerToken: "provider-token")
        )
    }

    func testAmazonBedrockProviderUsesConfiguredRegionEndpointLikeRust() throws {
        var info = ModelProviderInfo.createAmazonBedrockProvider()
        info.aws = ModelProviderAWSAuthInfo(profile: "codex-bedrock", region: " eu-central-1 ")
        let provider = ModelProviderFactory.create(providerInfo: info)

        XCTAssertEqual(
            try provider.runtimeBaseURL(),
            "https://bedrock-mantle.eu-central-1.api.aws/openai/v1"
        )
        XCTAssertEqual(
            try provider.apiProvider(environment: [:]).baseURL,
            "https://bedrock-mantle.eu-central-1.api.aws/openai/v1"
        )
    }

    func testAmazonBedrockProviderRejectsUnsupportedRegionLikeRust() {
        var info = ModelProviderInfo.createAmazonBedrockProvider()
        info.aws = ModelProviderAWSAuthInfo(region: "us-west-1")
        let provider = ModelProviderFactory.create(providerInfo: info)

        XCTAssertThrowsError(try provider.runtimeBaseURL()) { error in
            XCTAssertEqual(
                String(describing: error),
                "Fatal error: Amazon Bedrock Mantle does not support region `us-west-1`"
            )
        }
    }

    func testAmazonBedrockBearerTokenAuthRequiresConfiguredRegionLikeRust() throws {
        let provider = ModelProviderFactory.create(providerInfo: .createAmazonBedrockProvider())

        XCTAssertThrowsError(try provider.apiAuth(environment: ["AWS_BEARER_TOKEN_BEDROCK": " bearer-token "])) { error in
            XCTAssertEqual(
                String(describing: error),
                "Fatal error: Amazon Bedrock bearer token auth requires `model_providers.amazon-bedrock.aws.region`"
            )
        }

        var info = ModelProviderInfo.createAmazonBedrockProvider()
        info.aws = ModelProviderAWSAuthInfo(region: "us-west-2")
        let regionProvider = ModelProviderFactory.create(providerInfo: info)

        XCTAssertEqual(
            try regionProvider.apiAuth(environment: ["AWS_BEARER_TOKEN_BEDROCK": " bearer-token "]),
            StaticAPIAuthProvider(bearerToken: "bearer-token")
        )
    }

    private func providerInfo(baseURL: String) -> ModelProviderInfo {
        ModelProviderInfo(
            name: "mock",
            baseURL: baseURL,
            wireAPI: .responses,
            requestMaxRetries: 0,
            streamMaxRetries: 0,
            streamIdleTimeoutMilliseconds: 5_000,
            requiresOpenAIAuth: false
        )
    }

    private func tokenData(email: String?, plan: String?, accountID: String?) -> AuthTokenData {
        AuthTokenData(
            idToken: IdTokenInfo(
                email: email,
                chatGPTPlanType: plan.map { .unknown($0) },
                chatGPTAccountID: accountID,
                rawJWT: "id-token"
            ),
            accessToken: "chatgpt-token",
            refreshToken: "refresh-token",
            accountID: accountID
        )
    }
}
