import Foundation

public enum AuthMode: String, Codable, Equatable, Sendable {
    case apiKey = "apikey"
    case chatGPT = "chatgpt"
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
        guard wireAPI == .responses else {
            return false
        }

        if name.caseInsensitiveCompare("azure") == .orderedSame {
            return true
        }

        let lowercasedBaseURL = baseURL.lowercased()
        return lowercasedBaseURL.contains("openai.azure.")
            || Self.matchesAzureResponsesBaseURL(lowercasedBaseURL)
    }

    private static func matchesAzureResponsesBaseURL(_ lowercasedBaseURL: String) -> Bool {
        [
            "cognitiveservices.azure.",
            "aoai.azure.",
            "azure-api.",
            "azurefd.",
            "windows.net/openai"
        ].contains { lowercasedBaseURL.contains($0) }
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

    public var description: String {
        switch self {
        case let .missingEnvironmentVariable(name, instructions):
            if let instructions {
                return "Missing environment variable \(name). \(instructions)"
            }
            return "Missing environment variable \(name)"
        }
    }
}

public struct ModelProviderInfo: Codable, Equatable, Sendable {
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
    public let wireAPI: WireAPI
    public let queryParams: [String: String]?
    public let httpHeaders: [String: String]?
    public let envHTTPHeaders: [String: String]?
    public let requestMaxRetries: UInt64?
    public let streamMaxRetries: UInt64?
    public let streamIdleTimeoutMilliseconds: UInt64?
    public let requiresOpenAIAuth: Bool

    private enum CodingKeys: String, CodingKey {
        case name
        case baseURL = "base_url"
        case envKey = "env_key"
        case envKeyInstructions = "env_key_instructions"
        case experimentalBearerToken = "experimental_bearer_token"
        case wireAPI = "wire_api"
        case queryParams = "query_params"
        case httpHeaders = "http_headers"
        case envHTTPHeaders = "env_http_headers"
        case requestMaxRetries = "request_max_retries"
        case streamMaxRetries = "stream_max_retries"
        case streamIdleTimeoutMilliseconds = "stream_idle_timeout_ms"
        case requiresOpenAIAuth = "requires_openai_auth"
    }

    public init(
        name: String,
        baseURL: String? = nil,
        envKey: String? = nil,
        envKeyInstructions: String? = nil,
        experimentalBearerToken: String? = nil,
        wireAPI: WireAPI = .chat,
        queryParams: [String: String]? = nil,
        httpHeaders: [String: String]? = nil,
        envHTTPHeaders: [String: String]? = nil,
        requestMaxRetries: UInt64? = nil,
        streamMaxRetries: UInt64? = nil,
        streamIdleTimeoutMilliseconds: UInt64? = nil,
        requiresOpenAIAuth: Bool = false
    ) {
        self.name = name
        self.baseURL = baseURL
        self.envKey = envKey
        self.envKeyInstructions = envKeyInstructions
        self.experimentalBearerToken = experimentalBearerToken
        self.wireAPI = wireAPI
        self.queryParams = queryParams
        self.httpHeaders = httpHeaders
        self.envHTTPHeaders = envHTTPHeaders
        self.requestMaxRetries = requestMaxRetries
        self.streamMaxRetries = streamMaxRetries
        self.streamIdleTimeoutMilliseconds = streamIdleTimeoutMilliseconds
        self.requiresOpenAIAuth = requiresOpenAIAuth
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL)
        self.envKey = try container.decodeIfPresent(String.self, forKey: .envKey)
        self.envKeyInstructions = try container.decodeIfPresent(String.self, forKey: .envKeyInstructions)
        self.experimentalBearerToken = try container.decodeIfPresent(String.self, forKey: .experimentalBearerToken)
        self.wireAPI = try container.decodeIfPresent(WireAPI.self, forKey: .wireAPI) ?? .chat
        self.queryParams = try container.decodeIfPresent([String: String].self, forKey: .queryParams)
        self.httpHeaders = try container.decodeIfPresent([String: String].self, forKey: .httpHeaders)
        self.envHTTPHeaders = try container.decodeIfPresent([String: String].self, forKey: .envHTTPHeaders)
        self.requestMaxRetries = try container.decodeIfPresent(UInt64.self, forKey: .requestMaxRetries)
        self.streamMaxRetries = try container.decodeIfPresent(UInt64.self, forKey: .streamMaxRetries)
        self.streamIdleTimeoutMilliseconds = try container.decodeIfPresent(UInt64.self, forKey: .streamIdleTimeoutMilliseconds)
        self.requiresOpenAIAuth = try container.decodeIfPresent(Bool.self, forKey: .requiresOpenAIAuth) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try encodeOptional(baseURL, into: &container, forKey: .baseURL)
        try encodeOptional(envKey, into: &container, forKey: .envKey)
        try encodeOptional(envKeyInstructions, into: &container, forKey: .envKeyInstructions)
        try encodeOptional(experimentalBearerToken, into: &container, forKey: .experimentalBearerToken)
        try container.encode(wireAPI, forKey: .wireAPI)
        try encodeOptional(queryParams, into: &container, forKey: .queryParams)
        try encodeOptional(httpHeaders, into: &container, forKey: .httpHeaders)
        try encodeOptional(envHTTPHeaders, into: &container, forKey: .envHTTPHeaders)
        try encodeOptional(requestMaxRetries, into: &container, forKey: .requestMaxRetries)
        try encodeOptional(streamMaxRetries, into: &container, forKey: .streamMaxRetries)
        try encodeOptional(streamIdleTimeoutMilliseconds, into: &container, forKey: .streamIdleTimeoutMilliseconds)
        try container.encode(requiresOpenAIAuth, forKey: .requiresOpenAIAuth)
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
        let defaultBaseURL = authMode == .chatGPT
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
        environment: [String: String] = ProcessInfo.processInfo.environment,
        packageVersion: String = "0.0.0"
    ) -> ModelProviderInfo {
        let baseURL = environment["OPENAI_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? environment["OPENAI_BASE_URL"]
            : nil

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
        environment: [String: String] = ProcessInfo.processInfo.environment,
        packageVersion: String = "0.0.0"
    ) -> [String: ModelProviderInfo] {
        [
            "openai": createOpenAIProvider(environment: environment, packageVersion: packageVersion),
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

    private static func isValidHeader(name: String, value: String) -> Bool {
        !name.isEmpty
            && !name.contains { $0.isWhitespace || $0.isNewline || $0 == ":" }
            && !value.contains { $0.isNewline }
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
