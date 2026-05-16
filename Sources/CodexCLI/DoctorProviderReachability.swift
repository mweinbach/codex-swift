import CodexCore
import Foundation

public enum DoctorProviderAuthReachabilityMode: Equatable, Sendable {
    case notRequired
    case apiKey
    case chatGPT

    public var description: String {
        switch self {
        case .notRequired:
            "provider auth"
        case .apiKey:
            "API key auth"
        case .chatGPT:
            "ChatGPT auth"
        }
    }
}

public struct DoctorProviderReachabilityEndpoint: Equatable, Sendable {
    public let label: String
    public let url: String
    public let required: Bool
    public let routeProbeURL: String?

    public init(label: String, url: String, required: Bool, routeProbeURL: String? = nil) {
        self.label = label
        self.url = url
        self.required = required
        self.routeProbeURL = routeProbeURL
    }
}

public struct DoctorProviderReachabilityPlan: Equatable, Sendable {
    public let modeDescription: String
    public let endpoints: [DoctorProviderReachabilityEndpoint]

    public init(modeDescription: String, endpoints: [DoctorProviderReachabilityEndpoint]) {
        self.modeDescription = modeDescription
        self.endpoints = endpoints
    }
}

public enum DoctorHTTPProbeOutcome: Equatable, Sendable {
    case reachable(String)
    case failed(String)
}

public enum DoctorRouteProbeOutcome: Equatable, Sendable {
    case ok(String)
    case warning(String)
    case fail(String)
    case transportError(String)
}

public struct DoctorProviderReachabilityCheckInputs: Equatable, Sendable {
    public let plan: DoctorProviderReachabilityPlan
    public let baseProbeResults: [String: DoctorHTTPProbeOutcome]
    public let routeProbeResults: [String: DoctorRouteProbeOutcome]

    public init(
        plan: DoctorProviderReachabilityPlan,
        baseProbeResults: [String: DoctorHTTPProbeOutcome],
        routeProbeResults: [String: DoctorRouteProbeOutcome] = [:]
    ) {
        self.plan = plan
        self.baseProbeResults = baseProbeResults
        self.routeProbeResults = routeProbeResults
    }
}

private enum DoctorProbeStatus {
    case success(Int)
    case failure(String)
}

extension DoctorCommandRuntime {
    public static func defaultProviderReachabilityPlan(
        chatGPTBaseURL: String = "https://chatgpt.com/backend-api/"
    ) -> DoctorProviderReachabilityPlan {
        providerReachabilityPlan(
            mode: .chatGPT,
            providerID: "openai",
            providerName: ModelProviderInfo.openAIProviderName,
            providerBaseURL: nil,
            providerQueryParams: nil,
            isAmazonBedrock: false,
            chatGPTBaseURL: chatGPTBaseURL
        )
    }

    public static func defaultProviderReachabilityCheck() -> DoctorCheck {
        providerReachabilityCheck(
            plan: defaultProviderReachabilityPlan(),
            baseProbe: { httpProbeURL($0, method: "HEAD") },
            routeProbe: providerRouteProbe
        )
    }

    public static func providerReachabilityCheck(codexHome: URL, settings: CodexRuntimeConfig) -> DoctorCheck {
        let storedAuth = try? CodexAuthStorage.loadAuthDotJSON(
            codexHome: codexHome,
            mode: settings.cliAuthCredentialsStoreMode
        )
        let plan = providerReachabilityPlan(
            settings: settings,
            environment: ProcessInfo.processInfo.environment,
            storedAuth: storedAuth ?? nil
        )
        return providerReachabilityCheck(
            plan: plan,
            baseProbe: { httpProbeURL($0, method: "HEAD") },
            routeProbe: providerRouteProbe
        )
    }

    public static func providerReachabilityPlan(
        settings: CodexRuntimeConfig,
        environment: [String: String],
        storedAuth: AuthDotJSON?
    ) -> DoctorProviderReachabilityPlan {
        let provider = settings.selectedModelProvider
        let mode = providerAuthReachabilityMode(
            requiresOpenAIAuth: provider?.requiresOpenAIAuth ?? true,
            environment: environment,
            storedAuth: storedAuth
        )
        return providerReachabilityPlan(
            mode: mode,
            providerID: settings.selectedModelProviderID,
            providerName: provider?.name ?? ModelProviderInfo.openAIProviderName,
            providerBaseURL: provider?.baseURL,
            providerQueryParams: provider?.queryParams,
            isAmazonBedrock: provider?.isAmazonBedrock() ?? false,
            chatGPTBaseURL: settings.chatgptBaseURL
        )
    }

    public static func providerReachabilityPlan(
        mode: DoctorProviderAuthReachabilityMode,
        providerID: String,
        providerName: String,
        providerBaseURL: String?,
        providerQueryParams: [String: String]?,
        isAmazonBedrock: Bool,
        chatGPTBaseURL: String
    ) -> DoctorProviderReachabilityPlan {
        let routeProbeURL = (providerBaseURL ?? (mode == .apiKey ? "https://api.openai.com/v1" : nil))
            .flatMap { baseURL -> String? in
                guard shouldProbeProviderModelsRoute(
                    providerName: providerName,
                    baseURL: baseURL,
                    isAmazonBedrock: isAmazonBedrock
                ) else {
                    return nil
                }
                return providerURLForPath(baseURL: baseURL, path: "models", queryParams: providerQueryParams)
            }
        let endpoints: [DoctorProviderReachabilityEndpoint]
        switch mode {
        case .apiKey:
            endpoints = [
                DoctorProviderReachabilityEndpoint(
                    label: "\(providerID) API",
                    url: providerBaseURL ?? "https://api.openai.com/v1",
                    required: true,
                    routeProbeURL: routeProbeURL
                )
            ]
        case .chatGPT:
            endpoints = [
                DoctorProviderReachabilityEndpoint(
                    label: "ChatGPT",
                    url: chatGPTBaseURL,
                    required: true
                )
            ]
        case .notRequired:
            endpoints = providerBaseURL.map {
                [
                    DoctorProviderReachabilityEndpoint(
                        label: "\(providerID) API",
                        url: $0,
                        required: true,
                        routeProbeURL: routeProbeURL
                    )
                ]
            } ?? []
        }
        return DoctorProviderReachabilityPlan(modeDescription: mode.description, endpoints: endpoints)
    }

    public static func providerReachabilityCheck(inputs: DoctorProviderReachabilityCheckInputs) -> DoctorCheck {
        providerReachabilityCheck(
            plan: inputs.plan,
            baseProbe: { inputs.baseProbeResults[$0] ?? .failed("missing probe result") },
            routeProbe: { inputs.routeProbeResults[$0] ?? .transportError("missing route probe result") }
        )
    }

    private static func providerReachabilityCheck(
        plan: DoctorProviderReachabilityPlan,
        baseProbe: (String) -> DoctorHTTPProbeOutcome,
        routeProbe: (String) -> DoctorRouteProbeOutcome
    ) -> DoctorCheck {
        var details = ["reachability mode: \(plan.modeDescription)"]
        guard !plan.endpoints.isEmpty else {
            details.append("active provider endpoint: none configured")
            return DoctorCheck(
                id: "network.provider_reachability",
                category: "reachability",
                status: .ok,
                summary: "active provider has no HTTP endpoint to probe",
                details: details
            )
        }

        var requiredFailures = 0
        var warnings = 0
        var issues: [DoctorIssue] = []
        for endpoint in plan.endpoints {
            switch baseProbe(endpoint.url) {
            case let .reachable(status):
                details.append("\(endpoint.label) base URL: \(endpoint.url) reachable (\(status))")
            case let .failed(error):
                let requirement = endpoint.required ? "required" : "optional"
                details.append("\(endpoint.label) base URL: \(endpoint.url) \(error) (\(requirement))")
                if endpoint.required {
                    requiredFailures += 1
                } else {
                    warnings += 1
                }
                continue
            }

            guard let routeProbeURL = endpoint.routeProbeURL else {
                continue
            }
            switch routeProbe(routeProbeURL) {
            case let .ok(status):
                details.append("\(endpoint.label) route probe: \(routeProbeURL) route exists (\(status))")
            case let .warning(status):
                details.append("\(endpoint.label) route probe: \(routeProbeURL) returned \(status) (warning)")
                warnings += 1
            case let .fail(status):
                details.append("\(endpoint.label) route probe: \(routeProbeURL) returned \(status) (required)")
                requiredFailures += 1
                issues.append(DoctorIssue(
                    severity: .fail,
                    cause: "provider base URL route returned 404 - verify the configured API prefix",
                    measured: "\(routeProbeURL) returned \(status)",
                    expected: "GET /models returns 2xx, 401, or 403",
                    remedy: "Set base_url to the provider API root, for example https://api.openai.com/v1",
                    fields: ["route probe"]
                ))
            case let .transportError(error):
                details.append("\(endpoint.label) route probe: \(routeProbeURL) \(error) (required)")
                requiredFailures += 1
                issues.append(DoctorIssue(
                    severity: .fail,
                    cause: "provider route probe could not connect - verify network access to the provider API",
                    measured: "\(routeProbeURL) \(error)",
                    expected: "GET /models completes",
                    remedy: "Check proxy, VPN, firewall, DNS, and custom CA configuration.",
                    fields: ["route probe"]
                ))
            }
        }

        let (status, summary) = providerReachabilityOutcome(
            requiredFailures: requiredFailures,
            warnings: warnings
        )
        return DoctorCheck(
            id: "network.provider_reachability",
            category: "reachability",
            status: status,
            summary: summary,
            details: details,
            issues: issues,
            remediation: status == .ok
                ? nil
                : "Check proxy, VPN, firewall, DNS, and custom CA configuration."
        )
    }

    private static func providerAuthReachabilityMode(
        requiresOpenAIAuth: Bool,
        environment: [String: String],
        storedAuth: AuthDotJSON?
    ) -> DoctorProviderAuthReachabilityMode {
        guard requiresOpenAIAuth else {
            return .notRequired
        }
        if authEnvironmentVariablePresent(CodexAuthStorage.openAIAPIKeyEnvironmentVariable, in: environment)
            || authEnvironmentVariablePresent(CodexAuthStorage.codexAPIKeyEnvironmentVariable, in: environment)
        {
            return .apiKey
        }
        if authEnvironmentVariablePresent(CodexAuthStorage.codexAccessTokenEnvironmentVariable, in: environment) {
            return .chatGPT
        }
        switch storedAuth?.authMode {
        case .apiKey:
            return .apiKey
        case .chatGPT, .chatGPTAuthTokens, .agentIdentity, .none:
            return .chatGPT
        }
    }

    private static func providerReachabilityOutcome(
        requiredFailures: Int,
        warnings: Int
    ) -> (DoctorCheckStatus, String) {
        switch (requiredFailures, warnings) {
        case (0, 0):
            (.ok, "active provider endpoints are reachable over HTTP")
        case (0, _):
            (.warning, "provider endpoint checks returned warnings")
        default:
            (.fail, "one or more required provider endpoints are unreachable over HTTP")
        }
    }

    private static func providerRouteProbe(url: String) -> DoctorRouteProbeOutcome {
        switch httpProbeStatus(url) {
        case let .success(status) where (200..<300).contains(status) || status == 401 || status == 403:
            return .ok("HTTP \(status)")
        case .success(404):
            return .fail("HTTP 404")
        case let .success(status):
            return .warning("HTTP \(status)")
        case let .failure(error):
            return .transportError(error)
        }
    }

    private static func httpProbeURL(_ url: String, method: String) -> DoctorHTTPProbeOutcome {
        switch httpProbeStatus(url, method: method) {
        case let .success(status):
            return .reachable("HTTP \(status)")
        case let .failure(error):
            return .failed(error)
        }
    }

    private static func httpProbeStatus(_ url: String, method: String = "GET") -> DoctorProbeStatus {
        guard let requestURL = URL(string: url) else {
            return .failure("request could not be built")
        }
        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        request.timeoutInterval = 3
        let semaphore = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable {
            var result: DoctorProbeStatus = .failure("request timed out")
        }
        let box = Box()
        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            defer { semaphore.signal() }
            if let error = error as NSError? {
                if error.domain == NSURLErrorDomain, error.code == NSURLErrorTimedOut {
                    box.result = .failure("request timed out")
                } else if error.domain == NSURLErrorDomain,
                          [
                              NSURLErrorCannotConnectToHost,
                              NSURLErrorCannotFindHost,
                              NSURLErrorDNSLookupFailed,
                              NSURLErrorNetworkConnectionLost,
                              NSURLErrorNotConnectedToInternet
                          ].contains(error.code)
                {
                    box.result = .failure("connect failed")
                } else {
                    box.result = .failure(error.localizedDescription)
                }
                return
            }
            guard let http = response as? HTTPURLResponse else {
                box.result = .failure("request could not be built")
                return
            }
            box.result = .success(http.statusCode)
        }
        task.resume()
        if semaphore.wait(timeout: .now() + 4) == .timedOut {
            task.cancel()
            return .failure("request timed out")
        }
        return box.result
    }

    private static func shouldProbeProviderModelsRoute(
        providerName: String,
        baseURL: String,
        isAmazonBedrock: Bool
    ) -> Bool {
        !isAmazonBedrock && !isAzureResponsesProvider(name: providerName, baseURL: baseURL)
    }

    private static func isAzureResponsesProvider(name: String, baseURL: String?) -> Bool {
        if name.caseInsensitiveCompare("azure") == .orderedSame {
            return true
        }
        guard let baseURL else {
            return false
        }
        let markers = [
            "openai.azure.",
            "cognitiveservices.azure.",
            "aoai.azure.",
            "azure-api.",
            "azurefd.",
            "windows.net/openai"
        ]
        let lowercasedBaseURL = baseURL.lowercased()
        return markers.contains { lowercasedBaseURL.contains($0) }
    }

    private static func providerURLForPath(
        baseURL: String,
        path: String,
        queryParams: [String: String]?
    ) -> String {
        var url = trimTrailingSlashes(baseURL)
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !normalizedPath.isEmpty {
            url += "/\(normalizedPath)"
        }
        if let queryParams, !queryParams.isEmpty {
            let separator = url.contains("?") ? "&" : "?"
            let query = queryParams
                .map { key, value in "\(key)=\(value)" }
                .joined(separator: "&")
            url += separator + query
        }
        return url
    }

    private static func authEnvironmentVariablePresent(_ name: String, in environment: [String: String]) -> Bool {
        guard let value = environment[name] else {
            return false
        }
        return !value.isEmpty
    }

    private static func trimTrailingSlashes(_ value: String) -> String {
        var trimmed = value
        while trimmed.last == "/" {
            trimmed.removeLast()
        }
        return trimmed
    }
}
