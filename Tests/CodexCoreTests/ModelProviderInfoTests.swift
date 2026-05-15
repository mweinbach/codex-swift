import XCTest
@testable import CodexCore

final class ModelProviderInfoTests: XCTestCase {
    func testProviderInfoWireShapeMatchesRustSerdeFields() throws {
        let cwd = try AbsolutePath(absolutePath: "/tmp/codex-auth")
        let auth = try ModelProviderAuthInfo(
            command: "./scripts/print-token",
            args: ["--format=text"],
            timeoutMilliseconds: 7_000,
            refreshIntervalMilliseconds: 60_000,
            cwd: cwd
        )
        try XCTAssertJSONObjectEqual(
            ModelProviderInfo(
                name: "Example",
                baseURL: "https://example.com",
                envKey: "API_KEY",
                envKeyInstructions: "Set API_KEY.",
                experimentalBearerToken: "token",
                auth: auth,
                aws: ModelProviderAWSAuthInfo(profile: "codex-bedrock", region: "us-west-2"),
                wireAPI: .responses,
                queryParams: ["api-version": "2025-04-01-preview"],
                httpHeaders: ["X-Example": "value"],
                envHTTPHeaders: ["X-Env": "ENV_VALUE"],
                requestMaxRetries: 7,
                streamMaxRetries: 8,
                streamIdleTimeoutMilliseconds: 9_000,
                websocketConnectTimeoutMilliseconds: 15_000,
                requiresOpenAIAuth: true,
                supportsWebsockets: true
            ),
            [
                "name": "Example",
                "base_url": "https://example.com",
                "env_key": "API_KEY",
                "env_key_instructions": "Set API_KEY.",
                "experimental_bearer_token": "token",
                "auth": [
                    "command": "./scripts/print-token",
                    "args": ["--format=text"],
                    "timeout_ms": 7000,
                    "refresh_interval_ms": 60000,
                    "cwd": cwd.path
                ],
                "aws": [
                    "profile": "codex-bedrock",
                    "region": "us-west-2"
                ],
                "wire_api": "responses",
                "query_params": ["api-version": "2025-04-01-preview"],
                "http_headers": ["X-Example": "value"],
                "env_http_headers": ["X-Env": "ENV_VALUE"],
                "request_max_retries": 7,
                "stream_max_retries": 8,
                "stream_idle_timeout_ms": 9000,
                "websocket_connect_timeout_ms": 15000,
                "requires_openai_auth": true,
                "supports_websockets": true
            ]
        )
    }

    func testProviderInfoSerializesMissingOptionalFieldsAsNull() throws {
        try XCTAssertJSONObjectEqual(
            ModelProviderInfo(name: "Ollama", baseURL: "http://localhost:11434/v1"),
            [
                "name": "Ollama",
                "base_url": "http://localhost:11434/v1",
                "env_key": NSNull(),
                "env_key_instructions": NSNull(),
                "experimental_bearer_token": NSNull(),
                "auth": NSNull(),
                "aws": NSNull(),
                "wire_api": "responses",
                "query_params": NSNull(),
                "http_headers": NSNull(),
                "env_http_headers": NSNull(),
                "request_max_retries": NSNull(),
                "stream_max_retries": NSNull(),
                "stream_idle_timeout_ms": NSNull(),
                "websocket_connect_timeout_ms": NSNull(),
                "requires_openai_auth": false,
                "supports_websockets": false
            ]
        )
    }

    func testProviderInfoDecodesMissingDefaultsLikeRust() throws {
        let provider = try JSONDecoder().decode(ModelProviderInfo.self, from: Data("""
        {
          "name": "Azure",
          "base_url": "https://xxxxx.openai.azure.com/openai",
          "env_key": "AZURE_OPENAI_API_KEY",
          "query_params": { "api-version": "2025-04-01-preview" }
        }
        """.utf8))

        XCTAssertEqual(provider.name, "Azure")
        XCTAssertEqual(provider.baseURL, "https://xxxxx.openai.azure.com/openai")
        XCTAssertEqual(provider.envKey, "AZURE_OPENAI_API_KEY")
        XCTAssertNil(provider.auth)
        XCTAssertNil(provider.aws)
        XCTAssertEqual(provider.wireAPI, .responses)
        XCTAssertEqual(provider.queryParams, ["api-version": "2025-04-01-preview"])
        XCTAssertNil(provider.websocketConnectTimeoutMilliseconds)
        XCTAssertFalse(provider.requiresOpenAIAuth)
        XCTAssertFalse(provider.supportsWebsockets)
    }

    func testProviderInfoRejectsExplicitNullForRustDefaultedFields() {
        let nullDefaultedFields = [
            "name",
            "wire_api",
            "requires_openai_auth",
            "supports_websockets"
        ]

        for field in nullDefaultedFields {
            XCTAssertThrowsError(
                try JSONDecoder().decode(
                    ModelProviderInfo.self,
                    from: Data(#"{"\#(field)":null}"#.utf8)
                ),
                field
            )
        }
    }

    func testProviderInfoReportsCommandAuthLikeRust() throws {
        let provider = try ModelProviderInfo(
            name: "Provider",
            auth: ModelProviderAuthInfo(
                command: "print-token",
                timeoutMilliseconds: 5_000,
                cwd: AbsolutePath.currentDirectory()
            )
        )

        XCTAssertTrue(provider.hasCommandAuth())
        XCTAssertFalse(ModelProviderInfo.createOpenAIProvider().hasCommandAuth())
    }

    func testRetryAndTimeoutDefaultsAndCaps() {
        let defaults = ModelProviderInfo(name: "defaults")
        XCTAssertEqual(defaults.requestMaxRetryCount(), 4)
        XCTAssertEqual(defaults.streamMaxRetryCount(), 5)
        XCTAssertEqual(defaults.streamIdleTimeoutMS(), 300_000)
        XCTAssertEqual(defaults.websocketConnectTimeoutMS(), 15_000)

        let capped = ModelProviderInfo(
            name: "capped",
            requestMaxRetries: 10_000,
            streamMaxRetries: 10_000,
            streamIdleTimeoutMilliseconds: 123,
            websocketConnectTimeoutMilliseconds: 456
        )
        XCTAssertEqual(capped.requestMaxRetryCount(), 100)
        XCTAssertEqual(capped.streamMaxRetryCount(), 100)
        XCTAssertEqual(capped.streamIdleTimeoutMS(), 123)
        XCTAssertEqual(capped.websocketConnectTimeoutMS(), 456)
    }

    func testProviderAuthConfigDefaultsMatchRust() throws {
        let provider = try JSONDecoder().decode(ModelProviderInfo.self, from: Data("""
        {
          "name": "Corp",
          "auth": {
            "command": "./scripts/print-token",
            "args": ["--format=text"]
          }
        }
        """.utf8))

        let auth = try XCTUnwrap(provider.auth)
        XCTAssertEqual(auth.command, "./scripts/print-token")
        XCTAssertEqual(auth.args, ["--format=text"])
        XCTAssertEqual(auth.timeoutMilliseconds, 5_000)
        XCTAssertEqual(auth.refreshIntervalMilliseconds, 300_000)
        XCTAssertEqual(auth.refreshIntervalMS, 300_000)
        XCTAssertEqual(auth.cwd, try AbsolutePath.currentDirectory())
    }

    func testProviderAuthConfigAllowsZeroRefreshIntervalLikeRust() throws {
        let provider = try JSONDecoder().decode(ModelProviderInfo.self, from: Data("""
        {
          "name": "Corp",
          "auth": {
            "command": "./scripts/print-token",
            "refresh_interval_ms": 0
          }
        }
        """.utf8))

        XCTAssertEqual(provider.auth?.refreshIntervalMilliseconds, 0)
        XCTAssertNil(provider.auth?.refreshIntervalMS)
    }

    func testProviderValidationMatchesRustAuthAndAWSConflicts() throws {
        let auth = try ModelProviderAuthInfo(command: "print-token")
        XCTAssertThrowsError(try ModelProviderInfo(
            name: "Corp",
            envKey: "API_KEY",
            auth: auth
        ).validate()) { error in
            XCTAssertEqual(String(describing: error), "provider auth cannot be combined with env_key")
        }

        XCTAssertThrowsError(try ModelProviderInfo(
            name: "Corp",
            auth: auth,
            requiresOpenAIAuth: true
        ).validate()) { error in
            XCTAssertEqual(
                String(describing: error),
                "provider auth cannot be combined with requires_openai_auth"
            )
        }

        XCTAssertThrowsError(try ModelProviderInfo(
            name: "Corp",
            aws: ModelProviderAWSAuthInfo(),
            supportsWebsockets: true
        ).validate()) { error in
            XCTAssertEqual(String(describing: error), "provider aws cannot be combined with supports_websockets")
        }

        XCTAssertThrowsError(try ModelProviderInfo(
            name: "Corp",
            envKey: "AWS_BEARER_TOKEN_BEDROCK",
            aws: ModelProviderAWSAuthInfo(),
            requiresOpenAIAuth: true
        ).validate()) { error in
            XCTAssertEqual(
                String(describing: error),
                "provider aws cannot be combined with env_key, requires_openai_auth"
            )
        }
    }

    func testAPIKeyUsesNonEmptyEnvironmentValue() throws {
        let provider = ModelProviderInfo(
            name: "Example",
            envKey: "API_KEY",
            envKeyInstructions: "Export API_KEY first."
        )

        XCTAssertEqual(try provider.apiKey(environment: ["API_KEY": " secret "]), " secret ")
        XCTAssertThrowsError(try provider.apiKey(environment: ["API_KEY": " \n "])) { error in
            XCTAssertEqual(
                error as? ModelProviderError,
                .missingEnvironmentVariable(name: "API_KEY", instructions: "Export API_KEY first.")
            )
        }
        XCTAssertNil(try ModelProviderInfo(name: "No key").apiKey(environment: [:]))
    }

    func testBuildHeaderMapCombinesStaticAndEnvironmentHeaders() {
        let provider = ModelProviderInfo(
            name: "Example",
            httpHeaders: [
                "X-Static": "static",
                "Bad Header": "ignored"
            ],
            envHTTPHeaders: [
                "X-Env": "ENV_VALUE",
                "X-Blank": "BLANK_VALUE",
                "Bad:Env": "ENV_VALUE"
            ]
        )

        XCTAssertEqual(
            provider.buildHeaderMap(environment: [
                "ENV_VALUE": "dynamic",
                "BLANK_VALUE": "  "
            ]),
            [
                "X-Static": "static",
                "X-Env": "dynamic"
            ]
        )
    }

    func testToAPIProviderUsesRustDefaultsAndAuthModeBaseURL() {
        let provider = ModelProviderInfo(
            name: "OpenAI",
            queryParams: ["a": "b"],
            httpHeaders: ["X-Test": "1"]
        )

        let api = provider.toAPIProvider(authMode: nil, environment: [:])
        XCTAssertEqual(api.baseURL, "https://api.openai.com/v1")
        XCTAssertEqual(api.wireAPI, .responses)
        XCTAssertEqual(api.headers, ["X-Test": "1"])
        XCTAssertEqual(api.retry, ProviderRetryConfig(
            maxAttempts: 4,
            baseDelayMilliseconds: 200,
            retry429: false,
            retry5xx: true,
            retryTransport: true
        ))
        XCTAssertEqual(api.streamIdleTimeoutMilliseconds, 300_000)
        XCTAssertEqual(provider.toAPIProvider(authMode: .chatGPT, environment: [:]).baseURL, "https://chatgpt.com/backend-api/codex")
        XCTAssertEqual(provider.toAPIProvider(authMode: .chatGPTAuthTokens, environment: [:]).baseURL, "https://chatgpt.com/backend-api/codex")
    }

    func testAPIProviderURLRendering() {
        let provider = APIProvider(
            name: "test",
            baseURL: "https://example.com/v1/",
            queryParams: ["api-version": "2025-04-01-preview"],
            wireAPI: .responses,
            retry: ProviderRetryConfig(
                maxAttempts: 1,
                baseDelayMilliseconds: 200,
                retry429: false,
                retry5xx: true,
                retryTransport: true
            ),
            streamIdleTimeoutMilliseconds: 300_000
        )

        XCTAssertEqual(
            provider.urlForPath("/responses"),
            "https://example.com/v1/responses?api-version=2025-04-01-preview"
        )
        XCTAssertEqual(provider.urlForPath(""), "https://example.com/v1?api-version=2025-04-01-preview")
    }

    func testAPIProviderURLRenderingMatchesRustTrimRules() {
        let provider = APIProvider(
            name: "test",
            baseURL: "/proxy/",
            wireAPI: .responses,
            retry: ProviderRetryConfig(
                maxAttempts: 1,
                baseDelayMilliseconds: 200,
                retry429: false,
                retry5xx: true,
                retryTransport: true
            ),
            streamIdleTimeoutMilliseconds: 300_000
        )

        XCTAssertEqual(provider.urlForPath("/responses/"), "/proxy/responses/")
        XCTAssertEqual(provider.urlForPath(""), "/proxy")
    }

    func testAPIProviderBuildRequestMatchesRustDefaults() {
        let provider = APIProvider(
            name: "test",
            baseURL: "https://example.com/v1/",
            queryParams: ["api-version": "2025-04-01-preview"],
            wireAPI: .responses,
            headers: [
                "authorization": "Bearer token",
                "content-type": "application/json"
            ],
            retry: ProviderRetryConfig(
                maxAttempts: 2,
                baseDelayMilliseconds: 200,
                retry429: true,
                retry5xx: true,
                retryTransport: false
            ),
            streamIdleTimeoutMilliseconds: 300_000
        )

        let request = provider.buildRequest(method: .post, path: "/responses")
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.url, "https://example.com/v1/responses?api-version=2025-04-01-preview")
        XCTAssertEqual(request.headers, [
            "authorization": "Bearer token",
            "content-type": "application/json"
        ])
        XCTAssertNil(request.body)
        XCTAssertNil(request.timeoutMilliseconds)

        XCTAssertEqual(
            request.withJSON(.object(["model": .string("gpt-5.4")])).body,
            .object(["model": .string("gpt-5.4")])
        )
    }

    func testProviderRetryConfigToPolicyMatchesRustShape() {
        let retry = ProviderRetryConfig(
            maxAttempts: 4,
            baseDelayMilliseconds: 200,
            retry429: false,
            retry5xx: true,
            retryTransport: true
        )

        XCTAssertEqual(
            retry.toPolicy(),
            ProviderRetryPolicy(
                maxAttempts: 4,
                baseDelayMilliseconds: 200,
                retryOn: ProviderRetryOn(
                    retry429: false,
                    retry5xx: true,
                    retryTransport: true
                )
            )
        )
    }

    func testCreateOpenAIProviderHonorsBaseURLEnvironment() {
        let provider = ModelProviderInfo.createOpenAIProvider(
            environment: [
                "OPENAI_BASE_URL": " https://proxy.example/v1 ",
                "OPENAI_ORGANIZATION": "org",
                "OPENAI_PROJECT": "project"
            ],
            packageVersion: "1.2.3"
        )

        XCTAssertEqual(provider.name, "OpenAI")
        XCTAssertEqual(provider.baseURL, " https://proxy.example/v1 ")
        XCTAssertEqual(provider.wireAPI, .responses)
        XCTAssertEqual(provider.httpHeaders, ["version": "1.2.3"])
        XCTAssertEqual(provider.envHTTPHeaders, [
            "OpenAI-Organization": "OPENAI_ORGANIZATION",
            "OpenAI-Project": "OPENAI_PROJECT"
        ])
        XCTAssertTrue(provider.requiresOpenAIAuth)
        XCTAssertTrue(provider.supportsWebsockets)
        XCTAssertTrue(provider.isOpenAI())
        XCTAssertEqual(provider.buildHeaderMap(environment: [
            "OPENAI_ORGANIZATION": "org",
            "OPENAI_PROJECT": "project"
        ]), [
            "version": "1.2.3",
            "OpenAI-Organization": "org",
            "OpenAI-Project": "project"
        ])
    }

    func testBuiltInProvidersMatchRustDefaults() {
        let providers = ModelProviderInfo.builtInModelProviders(
            environment: [:],
            packageVersion: "0.55.0"
        )

        XCTAssertEqual(Set(providers.keys), ["openai", "amazon-bedrock", "ollama", "lmstudio"])
        XCTAssertEqual(providers["openai"]?.wireAPI, .responses)
        XCTAssertEqual(providers["openai"]?.requiresOpenAIAuth, true)
        XCTAssertEqual(providers["openai"]?.supportsWebsockets, true)
        XCTAssertEqual(providers["amazon-bedrock"], ModelProviderInfo.createAmazonBedrockProvider())
        XCTAssertEqual(providers["amazon-bedrock"]?.aws, ModelProviderAWSAuthInfo())
        XCTAssertEqual(providers["ollama"], ModelProviderInfo.createOSSProvider(
            baseURL: "http://localhost:11434/v1",
            wireAPI: .responses
        ))
        XCTAssertEqual(providers["lmstudio"], ModelProviderInfo.createOSSProvider(
            baseURL: "http://localhost:1234/v1",
            wireAPI: .responses
        ))
    }

    func testModelProviderWireAPIRejectsRemovedChatValueLikeRust() {
        XCTAssertThrowsError(try JSONDecoder().decode(ModelProviderInfo.self, from: Data("""
        {
          "name": "Legacy Chat",
          "base_url": "https://example.com/v1",
          "wire_api": "chat"
        }
        """.utf8))) { error in
            guard case let DecodingError.dataCorrupted(context) = error else {
                return XCTFail("expected data corrupted error, got \(error)")
            }
            XCTAssertEqual(context.debugDescription, ModelProviderInfo.chatWireAPIRemovedError)
        }
    }

    func testCreateOSSProviderUsesBaseURLOrPortEnvironment() {
        XCTAssertEqual(
            ModelProviderInfo.createOSSProvider(
                defaultProviderPort: 9999,
                wireAPI: .responses,
                environment: ["CODEX_OSS_BASE_URL": "http://remote/v1", "CODEX_OSS_PORT": "1111"]
            ),
            ModelProviderInfo.createOSSProvider(baseURL: "http://remote/v1", wireAPI: .responses)
        )
        XCTAssertEqual(
            ModelProviderInfo.createOSSProvider(
                defaultProviderPort: 9999,
                wireAPI: .responses,
                environment: ["CODEX_OSS_PORT": "not-a-port"]
            ).baseURL,
            "http://localhost:9999/v1"
        )
        XCTAssertEqual(
            ModelProviderInfo.createOSSProvider(
                defaultProviderPort: 9999,
                wireAPI: .responses,
                environment: ["CODEX_OSS_PORT": "1234"]
            ).baseURL,
            "http://localhost:1234/v1"
        )
    }

    func testProviderCapabilitiesMatchRustDefaultsAndAmazonBedrock() {
        XCTAssertEqual(ModelProviderInfo(name: "Custom").capabilities(), ModelProviderCapabilities())
        XCTAssertEqual(
            ModelProviderInfo.createAmazonBedrockProvider().capabilities(),
            ModelProviderCapabilities(namespaceTools: false, imageGeneration: false, webSearch: false)
        )
    }

    func testAmazonBedrockProviderIncludesDefaultAWSConfigLikeRust() {
        let provider = ModelProviderInfo.createAmazonBedrockProvider()

        XCTAssertEqual(provider.aws, ModelProviderAWSAuthInfo(profile: nil, region: nil))
        XCTAssertEqual(provider.baseURL, "https://bedrock-mantle.us-east-1.api.aws/openai/v1")
        XCTAssertEqual(provider.wireAPI, .responses)
        XCTAssertFalse(provider.requiresOpenAIAuth)
    }

    func testSupportsRemoteCompactionMatchesRustProviderRules() {
        XCTAssertTrue(ModelProviderInfo.createOpenAIProvider(environment: [:]).supportsRemoteCompaction())
        XCTAssertTrue(ModelProviderInfo(
            name: "Azure",
            baseURL: "https://example.com/openai",
            envKey: "AZURE_OPENAI_API_KEY",
            wireAPI: .responses
        ).supportsRemoteCompaction())
        XCTAssertTrue(ModelProviderInfo(
            name: "test",
            baseURL: "https://foo.openai.azure.com/openai",
            wireAPI: .chat
        ).supportsRemoteCompaction())
        XCTAssertFalse(ModelProviderInfo(
            name: "Example",
            baseURL: "https://example.com/v1",
            envKey: "API_KEY",
            wireAPI: .responses
        ).supportsRemoteCompaction())
    }

    func testAzureResponsesEndpointDetectionMatchesRustCases() {
        let positiveCases = [
            "https://foo.openai.azure.com/openai",
            "https://foo.openai.azure.us/openai/deployments/bar",
            "https://foo.cognitiveservices.azure.cn/openai",
            "https://foo.aoai.azure.com/openai",
            "https://foo.openai.azure-api.net/openai",
            "https://foo.z01.azurefd.net/",
            "https://foo.windows.net/openai"
        ]

        for baseURL in positiveCases {
            XCTAssertTrue(apiProvider(name: "test", baseURL: baseURL, wireAPI: .responses).isAzureResponsesEndpoint(), baseURL)
        }

        XCTAssertTrue(apiProvider(name: "Azure", baseURL: "https://example.com", wireAPI: .responses).isAzureResponsesEndpoint())

        let negativeCases = [
            "https://api.openai.com/v1",
            "https://example.com/openai",
            "https://myproxy.azurewebsites.net/openai"
        ]
        for baseURL in negativeCases {
            XCTAssertFalse(apiProvider(name: "test", baseURL: baseURL, wireAPI: .responses).isAzureResponsesEndpoint(), baseURL)
        }
        XCTAssertTrue(apiProvider(name: "Azure", baseURL: "https://example.com", wireAPI: .chat).isAzureResponsesEndpoint())
    }

    func testAuthModeWireValues() throws {
        XCTAssertEqual(try JSONEncoder().encode(AuthMode.apiKey), Data(#""apikey""#.utf8))
        XCTAssertEqual(try JSONEncoder().encode(AuthMode.chatGPT), Data(#""chatgpt""#.utf8))
        XCTAssertEqual(try JSONEncoder().encode(AuthMode.chatGPTAuthTokens), Data(#""chatgptAuthTokens""#.utf8))
    }

    private func apiProvider(name: String, baseURL: String, wireAPI: WireAPI) -> APIProvider {
        APIProvider(
            name: name,
            baseURL: baseURL,
            wireAPI: wireAPI,
            retry: ProviderRetryConfig(
                maxAttempts: 1,
                baseDelayMilliseconds: 200,
                retry429: false,
                retry5xx: true,
                retryTransport: true
            ),
            streamIdleTimeoutMilliseconds: 300_000
        )
    }
}
