import Foundation

private let azureResponsesBaseURLMarkers = [
    "openai.azure.",
    "cognitiveservices.azure.",
    "aoai.azure.",
    "azure-api.",
    "azurefd.",
    "windows.net/openai"
]

private func isAzureResponsesProvider(name: String, baseURL: String?) -> Bool {
    if name.caseInsensitiveCompare("azure") == .orderedSame {
        return true
    }

    guard let baseURL else {
        return false
    }

    let lowercasedBaseURL = baseURL.lowercased()
    return azureResponsesBaseURLMarkers.contains { lowercasedBaseURL.contains($0) }
}

public enum AuthMode: String, Codable, Equatable, Sendable {
    case apiKey = "apikey"
    case chatGPT = "chatgpt"
    case chatGPTAuthTokens = "chatgptAuthTokens"
    case agentIdentity = "agentIdentity"

    public var isChatGPT: Bool {
        switch self {
        case .chatGPT, .chatGPTAuthTokens, .agentIdentity:
            return true
        case .apiKey:
            return false
        }
    }
}

public struct ProviderRetryConfig: Equatable, Sendable {
    public let maxAttempts: UInt64
    public let baseDelayMilliseconds: UInt64
    public let retry429: Bool
    public let retry5xx: Bool
    public let retryTransport: Bool

    public init(
        maxAttempts: UInt64,
        baseDelayMilliseconds: UInt64,
        retry429: Bool,
        retry5xx: Bool,
        retryTransport: Bool
    ) {
        self.maxAttempts = maxAttempts
        self.baseDelayMilliseconds = baseDelayMilliseconds
        self.retry429 = retry429
        self.retry5xx = retry5xx
        self.retryTransport = retryTransport
    }

    public func toPolicy() -> ProviderRetryPolicy {
        ProviderRetryPolicy(
            maxAttempts: maxAttempts,
            baseDelayMilliseconds: baseDelayMilliseconds,
            retryOn: ProviderRetryOn(
                retry429: retry429,
                retry5xx: retry5xx,
                retryTransport: retryTransport
            )
        )
    }
}

public struct ProviderRetryPolicy: Equatable, Sendable {
    public let maxAttempts: UInt64
    public let baseDelayMilliseconds: UInt64
    public let retryOn: ProviderRetryOn

    public init(maxAttempts: UInt64, baseDelayMilliseconds: UInt64, retryOn: ProviderRetryOn) {
        self.maxAttempts = maxAttempts
        self.baseDelayMilliseconds = baseDelayMilliseconds
        self.retryOn = retryOn
    }
}

public struct ProviderRetryOn: Equatable, Sendable {
    public let retry429: Bool
    public let retry5xx: Bool
    public let retryTransport: Bool

    public init(retry429: Bool, retry5xx: Bool, retryTransport: Bool) {
        self.retry429 = retry429
        self.retry5xx = retry5xx
        self.retryTransport = retryTransport
    }
}

public enum HTTPMethod: String, Equatable, Sendable {
    case delete = "DELETE"
    case get = "GET"
    case patch = "PATCH"
    case post = "POST"
    case put = "PUT"
}

public struct APIRequest: Equatable, Sendable {
    public var method: HTTPMethod
    public var url: String
    public var headers: [String: String]
    public var body: JSONValue?
    public var timeoutMilliseconds: UInt64?

    public init(
        method: HTTPMethod,
        url: String,
        headers: [String: String] = [:],
        body: JSONValue? = nil,
        timeoutMilliseconds: UInt64? = nil
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeoutMilliseconds = timeoutMilliseconds
    }

    public func withJSON(_ body: JSONValue) -> APIRequest {
        var copy = self
        copy.body = body
        return copy
    }
}

public struct APIProvider: Equatable, Sendable {
    public let name: String
    public let baseURL: String
    public let queryParams: [String: String]?
    public let wireAPI: WireAPI
    public let headers: [String: String]
    public let retry: ProviderRetryConfig
    public let streamIdleTimeoutMilliseconds: UInt64

    public init(
        name: String,
        baseURL: String,
        queryParams: [String: String]? = nil,
        wireAPI: WireAPI,
        headers: [String: String] = [:],
        retry: ProviderRetryConfig,
        streamIdleTimeoutMilliseconds: UInt64
    ) {
        self.name = name
        self.baseURL = baseURL
        self.queryParams = queryParams
        self.wireAPI = wireAPI
        self.headers = headers
        self.retry = retry
        self.streamIdleTimeoutMilliseconds = streamIdleTimeoutMilliseconds
    }

    public func urlForPath(_ path: String) -> String {
        let base = Self.trimmingTrailingSlashes(baseURL)
        let normalizedPath = Self.trimmingLeadingSlashes(path)
        var url = normalizedPath.isEmpty ? base : "\(base)/\(normalizedPath)"

        if let queryParams, !queryParams.isEmpty {
            let query = queryParams.map { key, value in "\(key)=\(value)" }.joined(separator: "&")
            url.append("?\(query)")
        }

        return url
    }

    public func buildRequest(method: HTTPMethod, path: String) -> APIRequest {
        APIRequest(method: method, url: urlForPath(path), headers: headers)
    }

    public func isAzureResponsesEndpoint() -> Bool {
        isAzureResponsesProvider(name: name, baseURL: baseURL)
    }

    private static func trimmingTrailingSlashes(_ value: String) -> String {
        var trimmed = value
        while trimmed.last == "/" {
            trimmed.removeLast()
        }
        return trimmed
    }

    private static func trimmingLeadingSlashes(_ value: String) -> String {
        var trimmed = value
        while trimmed.first == "/" {
            trimmed.removeFirst()
        }
        return trimmed
    }
}

public enum ModelProviderError: Error, Equatable, CustomStringConvertible, Sendable {
    case missingEnvironmentVariable(name: String, instructions: String?)
    case amazonBedrockBearerTokenMissingRegion
    case unsupportedAmazonBedrockRegion(String)
    case validation(String)

    public var description: String {
        switch self {
        case let .missingEnvironmentVariable(name, instructions):
            if let instructions {
                return "Missing environment variable \(name). \(instructions)"
            }
            return "Missing environment variable \(name)"
        case .amazonBedrockBearerTokenMissingRegion:
            return "Fatal error: Amazon Bedrock bearer token auth requires `model_providers.amazon-bedrock.aws.region`"
        case let .unsupportedAmazonBedrockRegion(region):
            return "Fatal error: Amazon Bedrock Mantle does not support region `\(region)`"
        case let .validation(message):
            return message
        }
    }
}

public struct ModelProviderInfo: Codable, Equatable, Sendable {
    public static let amazonBedrockProviderID = "amazon-bedrock"
    public static let amazonBedrockProviderName = "Amazon Bedrock"
    public static let amazonBedrockDefaultBaseURL = "https://bedrock-mantle.us-east-1.api.aws/openai/v1"
    public static let defaultStreamIdleTimeoutMilliseconds: UInt64 = 300_000
    public static let defaultStreamMaxRetries: UInt64 = 5
    public static let defaultRequestMaxRetries: UInt64 = 4
    public static let maxStreamMaxRetries: UInt64 = 100
    public static let maxRequestMaxRetries: UInt64 = 100
    public static let chatWireAPIDeprecationSummary =
        #"Support for the "chat" wire API is deprecated and will soon be removed. Update your model provider definition in config.toml to use wire_api = "responses"."#
    public static let openAIProviderName = "OpenAI"
    public static let defaultLMStudioPort: UInt16 = 1234
    public static let defaultOllamaPort: UInt16 = 11434
    public static let lmStudioOSSProviderID = "lmstudio"
    public static let ollamaOSSProviderID = "ollama"

    public let name: String
    public let baseURL: String?
    public let envKey: String?
    public let envKeyInstructions: String?
    public let experimentalBearerToken: String?
    public let auth: ModelProviderAuthInfo?
    public var aws: ModelProviderAWSAuthInfo?
    public let wireAPI: WireAPI
    public let queryParams: [String: String]?
    public let httpHeaders: [String: String]?
    public let envHTTPHeaders: [String: String]?
    public let requestMaxRetries: UInt64?
    public let streamMaxRetries: UInt64?
    public let streamIdleTimeoutMilliseconds: UInt64?
    public let websocketConnectTimeoutMilliseconds: UInt64?
    public let requiresOpenAIAuth: Bool
    public let supportsWebsockets: Bool

    private enum CodingKeys: String, CodingKey {
        case name
        case baseURL = "base_url"
        case envKey = "env_key"
        case envKeyInstructions = "env_key_instructions"
        case experimentalBearerToken = "experimental_bearer_token"
        case auth
        case aws
        case wireAPI = "wire_api"
        case queryParams = "query_params"
        case httpHeaders = "http_headers"
        case envHTTPHeaders = "env_http_headers"
        case requestMaxRetries = "request_max_retries"
        case streamMaxRetries = "stream_max_retries"
        case streamIdleTimeoutMilliseconds = "stream_idle_timeout_ms"
        case websocketConnectTimeoutMilliseconds = "websocket_connect_timeout_ms"
        case requiresOpenAIAuth = "requires_openai_auth"
        case supportsWebsockets = "supports_websockets"
    }

    public init(
        name: String = "",
        baseURL: String? = nil,
        envKey: String? = nil,
        envKeyInstructions: String? = nil,
        experimentalBearerToken: String? = nil,
        auth: ModelProviderAuthInfo? = nil,
        aws: ModelProviderAWSAuthInfo? = nil,
        wireAPI: WireAPI = .responses,
        queryParams: [String: String]? = nil,
        httpHeaders: [String: String]? = nil,
        envHTTPHeaders: [String: String]? = nil,
        requestMaxRetries: UInt64? = nil,
        streamMaxRetries: UInt64? = nil,
        streamIdleTimeoutMilliseconds: UInt64? = nil,
        websocketConnectTimeoutMilliseconds: UInt64? = nil,
        requiresOpenAIAuth: Bool = false,
        supportsWebsockets: Bool = false
    ) {
        self.name = name
        self.baseURL = baseURL
        self.envKey = envKey
        self.envKeyInstructions = envKeyInstructions
        self.experimentalBearerToken = experimentalBearerToken
        self.auth = auth
        self.aws = aws
        self.wireAPI = wireAPI
        self.queryParams = queryParams
        self.httpHeaders = httpHeaders
        self.envHTTPHeaders = envHTTPHeaders
        self.requestMaxRetries = requestMaxRetries
        self.streamMaxRetries = streamMaxRetries
        self.streamIdleTimeoutMilliseconds = streamIdleTimeoutMilliseconds
        self.websocketConnectTimeoutMilliseconds = websocketConnectTimeoutMilliseconds
        self.requiresOpenAIAuth = requiresOpenAIAuth
        self.supportsWebsockets = supportsWebsockets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL)
        self.envKey = try container.decodeIfPresent(String.self, forKey: .envKey)
        self.envKeyInstructions = try container.decodeIfPresent(String.self, forKey: .envKeyInstructions)
        self.experimentalBearerToken = try container.decodeIfPresent(String.self, forKey: .experimentalBearerToken)
        self.auth = try container.decodeIfPresent(ModelProviderAuthInfo.self, forKey: .auth)
        self.aws = try container.decodeIfPresent(ModelProviderAWSAuthInfo.self, forKey: .aws)
        self.wireAPI = try container.decodeIfPresent(WireAPI.self, forKey: .wireAPI) ?? .responses
        self.queryParams = try container.decodeIfPresent([String: String].self, forKey: .queryParams)
        self.httpHeaders = try container.decodeIfPresent([String: String].self, forKey: .httpHeaders)
        self.envHTTPHeaders = try container.decodeIfPresent([String: String].self, forKey: .envHTTPHeaders)
        self.requestMaxRetries = try container.decodeIfPresent(UInt64.self, forKey: .requestMaxRetries)
        self.streamMaxRetries = try container.decodeIfPresent(UInt64.self, forKey: .streamMaxRetries)
        self.streamIdleTimeoutMilliseconds = try container.decodeIfPresent(UInt64.self, forKey: .streamIdleTimeoutMilliseconds)
        self.websocketConnectTimeoutMilliseconds = try container.decodeIfPresent(
            UInt64.self,
            forKey: .websocketConnectTimeoutMilliseconds
        )
        self.requiresOpenAIAuth = try container.decodeIfPresent(Bool.self, forKey: .requiresOpenAIAuth) ?? false
        self.supportsWebsockets = try container.decodeIfPresent(Bool.self, forKey: .supportsWebsockets) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try encodeOptional(baseURL, into: &container, forKey: .baseURL)
        try encodeOptional(envKey, into: &container, forKey: .envKey)
        try encodeOptional(envKeyInstructions, into: &container, forKey: .envKeyInstructions)
        try encodeOptional(experimentalBearerToken, into: &container, forKey: .experimentalBearerToken)
        try encodeOptional(auth, into: &container, forKey: .auth)
        try encodeOptional(aws, into: &container, forKey: .aws)
        try container.encode(wireAPI, forKey: .wireAPI)
        try encodeOptional(queryParams, into: &container, forKey: .queryParams)
        try encodeOptional(httpHeaders, into: &container, forKey: .httpHeaders)
        try encodeOptional(envHTTPHeaders, into: &container, forKey: .envHTTPHeaders)
        try encodeOptional(requestMaxRetries, into: &container, forKey: .requestMaxRetries)
        try encodeOptional(streamMaxRetries, into: &container, forKey: .streamMaxRetries)
        try encodeOptional(streamIdleTimeoutMilliseconds, into: &container, forKey: .streamIdleTimeoutMilliseconds)
        try encodeOptional(
            websocketConnectTimeoutMilliseconds,
            into: &container,
            forKey: .websocketConnectTimeoutMilliseconds
        )
        try container.encode(requiresOpenAIAuth, forKey: .requiresOpenAIAuth)
        try container.encode(supportsWebsockets, forKey: .supportsWebsockets)
    }

    public func apiKey(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> String? {
        guard let envKey else {
            return nil
        }

        guard let value = environment[envKey], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ModelProviderError.missingEnvironmentVariable(name: envKey, instructions: envKeyInstructions)
        }

        return value
    }

    public func requestMaxRetryCount() -> UInt64 {
        min(requestMaxRetries ?? Self.defaultRequestMaxRetries, Self.maxRequestMaxRetries)
    }

    public func streamMaxRetryCount() -> UInt64 {
        min(streamMaxRetries ?? Self.defaultStreamMaxRetries, Self.maxStreamMaxRetries)
    }

    public func streamIdleTimeoutMS() -> UInt64 {
        streamIdleTimeoutMilliseconds ?? Self.defaultStreamIdleTimeoutMilliseconds
    }

    public func websocketConnectTimeoutMS() -> UInt64 {
        websocketConnectTimeoutMilliseconds ?? 10_000
    }

    public func validate() throws {
        if aws != nil {
            if supportsWebsockets {
                throw ModelProviderError.validation("provider aws cannot be combined with supports_websockets")
            }

            var conflicts: [String] = []
            if envKey != nil {
                conflicts.append("env_key")
            }
            if experimentalBearerToken != nil {
                conflicts.append("experimental_bearer_token")
            }
            if auth != nil {
                conflicts.append("auth")
            }
            if requiresOpenAIAuth {
                conflicts.append("requires_openai_auth")
            }
            if !conflicts.isEmpty {
                throw ModelProviderError.validation("provider aws cannot be combined with \(conflicts.joined(separator: ", "))")
            }
        }

        guard let auth else {
            return
        }
        if auth.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ModelProviderError.validation("provider auth.command must not be empty")
        }

        var conflicts: [String] = []
        if envKey != nil {
            conflicts.append("env_key")
        }
        if experimentalBearerToken != nil {
            conflicts.append("experimental_bearer_token")
        }
        if requiresOpenAIAuth {
            conflicts.append("requires_openai_auth")
        }
        if !conflicts.isEmpty {
            throw ModelProviderError.validation("provider auth cannot be combined with \(conflicts.joined(separator: ", "))")
        }
    }

    public func buildHeaderMap(environment: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var headers: [String: String] = [:]
        if let httpHeaders {
            for (name, value) in httpHeaders where Self.isValidHeader(name: name, value: value) {
                headers[name] = value
            }
        }
        if let envHTTPHeaders {
            for (header, envVar) in envHTTPHeaders {
                guard let value = environment[envVar],
                      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      Self.isValidHeader(name: header, value: value)
                else {
                    continue
                }
                headers[header] = value
            }
        }
        return headers
    }

    public func toAPIProvider(
        authMode: AuthMode? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> APIProvider {
        let defaultBaseURL = authMode?.isChatGPT == true
            ? "https://chatgpt.com/backend-api/codex"
            : "https://api.openai.com/v1"

        return APIProvider(
            name: name,
            baseURL: baseURL ?? defaultBaseURL,
            queryParams: queryParams,
            wireAPI: wireAPI,
            headers: buildHeaderMap(environment: environment),
            retry: ProviderRetryConfig(
                maxAttempts: requestMaxRetryCount(),
                baseDelayMilliseconds: 200,
                retry429: false,
                retry5xx: true,
                retryTransport: true
            ),
            streamIdleTimeoutMilliseconds: streamIdleTimeoutMS()
        )
    }

    public static func createOpenAIProvider(
        openAIBaseURL: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        packageVersion: String = "0.0.0"
    ) -> ModelProviderInfo {
        let environmentBaseURL = environment["OPENAI_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? environment["OPENAI_BASE_URL"]
            : nil
        let baseURL = openAIBaseURL?.isEmpty == false ? openAIBaseURL : environmentBaseURL

        return ModelProviderInfo(
            name: openAIProviderName,
            baseURL: baseURL,
            wireAPI: .responses,
            httpHeaders: ["version": packageVersion],
            envHTTPHeaders: [
                "OpenAI-Organization": "OPENAI_ORGANIZATION",
                "OpenAI-Project": "OPENAI_PROJECT"
            ],
            requiresOpenAIAuth: true
        )
    }

    public static func builtInModelProviders(
        openAIBaseURL: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        packageVersion: String = "0.0.0"
    ) -> [String: ModelProviderInfo] {
        [
            "openai": createOpenAIProvider(
                openAIBaseURL: openAIBaseURL,
                environment: environment,
                packageVersion: packageVersion
            ),
            amazonBedrockProviderID: createAmazonBedrockProvider(),
            ollamaOSSProviderID: createOSSProvider(
                defaultProviderPort: defaultOllamaPort,
                wireAPI: .chat,
                environment: environment
            ),
            lmStudioOSSProviderID: createOSSProvider(
                defaultProviderPort: defaultLMStudioPort,
                wireAPI: .responses,
                environment: environment
            )
        ]
    }

    public static func createAmazonBedrockProvider() -> ModelProviderInfo {
        ModelProviderInfo(
            name: amazonBedrockProviderName,
            baseURL: amazonBedrockDefaultBaseURL,
            aws: ModelProviderAWSAuthInfo(),
            wireAPI: .responses,
            requiresOpenAIAuth: false
        )
    }

    public static func createOSSProvider(
        defaultProviderPort: UInt16,
        wireAPI: WireAPI,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ModelProviderInfo {
        let baseURL: String
        if let override = environment["CODEX_OSS_BASE_URL"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            baseURL = override
        } else {
            let configuredPort = environment["CODEX_OSS_PORT"]
                .flatMap { UInt16($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            baseURL = "http://localhost:\(configuredPort ?? defaultProviderPort)/v1"
        }
        return createOSSProvider(baseURL: baseURL, wireAPI: wireAPI)
    }

    public static func createOSSProvider(baseURL: String, wireAPI: WireAPI) -> ModelProviderInfo {
        ModelProviderInfo(
            name: "gpt-oss",
            baseURL: baseURL,
            wireAPI: wireAPI,
            requiresOpenAIAuth: false
        )
    }

    public func isOpenAI() -> Bool {
        name == Self.openAIProviderName
    }

    public func isAmazonBedrock() -> Bool {
        name == Self.amazonBedrockProviderName
    }

    public func hasCommandAuth() -> Bool {
        auth != nil
    }

    public func supportsRemoteCompaction() -> Bool {
        isOpenAI() || isAzureResponsesProvider(name: name, baseURL: baseURL)
    }

    public func capabilities() -> ModelProviderCapabilities {
        if isAmazonBedrock() {
            return ModelProviderCapabilities(
                namespaceTools: false,
                imageGeneration: false,
                webSearch: false
            )
        }
        return ModelProviderCapabilities()
    }

    func isAmazonBedrockAWSOnlyOverride() -> Bool {
        name.isEmpty
            && baseURL == nil
            && envKey == nil
            && envKeyInstructions == nil
            && experimentalBearerToken == nil
            && auth == nil
            && queryParams == nil
            && httpHeaders == nil
            && envHTTPHeaders == nil
            && requestMaxRetries == nil
            && streamMaxRetries == nil
            && streamIdleTimeoutMilliseconds == nil
            && websocketConnectTimeoutMilliseconds == nil
            && requiresOpenAIAuth == false
            && supportsWebsockets == false
            && (wireAPI == .chat || wireAPI == .responses)
    }

    private static func isValidHeader(name: String, value: String) -> Bool {
        !name.isEmpty
            && !name.contains { $0.isWhitespace || $0.isNewline || $0 == ":" }
            && !value.contains { $0.isNewline }
    }
}

public struct ModelProviderAuthInfo: Codable, Equatable, Hashable, Sendable {
    public static let defaultTimeoutMilliseconds: UInt64 = 5_000
    public static let defaultRefreshIntervalMilliseconds: UInt64 = 300_000

    public let command: String
    public let args: [String]
    public let timeoutMilliseconds: UInt64
    public let refreshIntervalMilliseconds: UInt64
    public let cwd: AbsolutePath

    private enum CodingKeys: String, CodingKey {
        case command
        case args
        case timeoutMilliseconds = "timeout_ms"
        case refreshIntervalMilliseconds = "refresh_interval_ms"
        case cwd
    }

    public init(
        command: String,
        args: [String] = [],
        timeoutMilliseconds: UInt64 = defaultTimeoutMilliseconds,
        refreshIntervalMilliseconds: UInt64 = defaultRefreshIntervalMilliseconds,
        cwd: AbsolutePath? = nil
    ) throws {
        guard timeoutMilliseconds > 0 else {
            throw ModelProviderError.validation("model_providers.<id>.auth.timeout_ms must be non-zero")
        }
        self.command = command
        self.args = args
        self.timeoutMilliseconds = timeoutMilliseconds
        self.refreshIntervalMilliseconds = refreshIntervalMilliseconds
        self.cwd = try cwd ?? AbsolutePath.currentDirectory()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.command = try container.decode(String.self, forKey: .command)
        self.args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        self.timeoutMilliseconds = try container.decodeIfPresent(
            UInt64.self,
            forKey: .timeoutMilliseconds
        ) ?? Self.defaultTimeoutMilliseconds
        guard timeoutMilliseconds > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .timeoutMilliseconds,
                in: container,
                debugDescription: "model_providers.<id>.auth.timeout_ms must be non-zero"
            )
        }
        self.refreshIntervalMilliseconds = try container.decodeIfPresent(
            UInt64.self,
            forKey: .refreshIntervalMilliseconds
        ) ?? Self.defaultRefreshIntervalMilliseconds
        if let cwdText = try container.decodeIfPresent(String.self, forKey: .cwd) {
            self.cwd = try AbsolutePath.resolve(cwdText, against: FileManager.default.currentDirectoryPath)
        } else {
            self.cwd = try AbsolutePath.currentDirectory()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(command, forKey: .command)
        try container.encode(args, forKey: .args)
        try container.encode(timeoutMilliseconds, forKey: .timeoutMilliseconds)
        try container.encode(refreshIntervalMilliseconds, forKey: .refreshIntervalMilliseconds)
        try container.encode(cwd, forKey: .cwd)
    }

    public var refreshIntervalMS: UInt64? {
        refreshIntervalMilliseconds == 0 ? nil : refreshIntervalMilliseconds
    }
}

public struct ModelProviderAWSAuthInfo: Codable, Equatable, Sendable {
    public var profile: String?
    public var region: String?

    public init(profile: String? = nil, region: String? = nil) {
        self.profile = profile
        self.region = region
    }

    public var regionFromConfig: String? {
        guard let trimmed = region?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }
}

public struct ModelProviderCapabilities: Equatable, Sendable {
    public var namespaceTools: Bool
    public var imageGeneration: Bool
    public var webSearch: Bool

    public init(
        namespaceTools: Bool = true,
        imageGeneration: Bool = true,
        webSearch: Bool = true
    ) {
        self.namespaceTools = namespaceTools
        self.imageGeneration = imageGeneration
        self.webSearch = webSearch
    }
}

private func encodeOptional<T: Encodable, K: CodingKey>(
    _ value: T?,
    into container: inout KeyedEncodingContainer<K>,
    forKey key: K
) throws {
    if let value {
        try container.encode(value, forKey: key)
    } else {
        try container.encodeNil(forKey: key)
    }
}
