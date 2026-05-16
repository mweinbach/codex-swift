import CodexCore
import Foundation

public struct DoctorWebsocketHandshakeResult: Equatable, Sendable {
    public let httpStatus: Int
    public let reasoningHeaderPresent: Bool
    public let modelsETagPresent: Bool
    public let serverModelPresent: Bool

    public init(
        httpStatus: Int,
        reasoningHeaderPresent: Bool,
        modelsETagPresent: Bool,
        serverModelPresent: Bool
    ) {
        self.httpStatus = httpStatus
        self.reasoningHeaderPresent = reasoningHeaderPresent
        self.modelsETagPresent = modelsETagPresent
        self.serverModelPresent = serverModelPresent
    }
}

public enum DoctorWebsocketProbeOutcome: Equatable, Sendable {
    case notAttempted(String)
    case handshakeSucceeded(DoctorWebsocketHandshakeResult)
    case closedImmediately(DoctorWebsocketHandshakeResult, code: UInt16, reason: String)
    case transportError(String)
    case apiError(status: Int, message: String)
    case streamError(String)
    case failed(String)
    case timedOut
}

public struct DoctorWebsocketReachabilityInputs: Equatable, Sendable {
    public let providerID: String
    public let providerName: String
    public let wireAPI: WireAPI
    public let supportsWebsockets: Bool
    public let proxyEnvironment: [String: String]
    public let connectTimeoutMilliseconds: UInt64?
    public let authModeDescription: String?
    public let endpoint: String?
    public let dnsDetails: String?
    public let outcome: DoctorWebsocketProbeOutcome?

    public init(
        providerID: String,
        providerName: String,
        wireAPI: WireAPI,
        supportsWebsockets: Bool,
        proxyEnvironment: [String: String] = [:],
        connectTimeoutMilliseconds: UInt64? = nil,
        authModeDescription: String? = nil,
        endpoint: String? = nil,
        dnsDetails: String? = nil,
        outcome: DoctorWebsocketProbeOutcome? = nil
    ) {
        self.providerID = providerID
        self.providerName = providerName
        self.wireAPI = wireAPI
        self.supportsWebsockets = supportsWebsockets
        self.proxyEnvironment = proxyEnvironment
        self.connectTimeoutMilliseconds = connectTimeoutMilliseconds
        self.authModeDescription = authModeDescription
        self.endpoint = endpoint
        self.dnsDetails = dnsDetails
        self.outcome = outcome
    }
}

extension DoctorCommandRuntime {
    public static func websocketReachabilityCheck(
        codexHome: URL,
        settings: CodexRuntimeConfig
    ) -> DoctorCheck {
        let storedAuth = try? CodexAuthStorage.loadAuthDotJSON(
            codexHome: codexHome,
            mode: settings.cliAuthCredentialsStoreMode
        )
        let environment = ProcessInfo.processInfo.environment
        let provider = settings.selectedModelProvider ?? ModelProviderInfo.createOpenAIProvider(
            openAIBaseURL: settings.openAIBaseURL,
            environment: environment
        )
        let authMode = websocketAuthMode(
            providerRequiresOpenAIAuth: provider.requiresOpenAIAuth,
            environment: environment,
            storedAuth: storedAuth ?? nil
        )
        let apiProvider = provider.toAPIProvider(authMode: authMode, environment: environment)
        let endpoint = websocketURLForResponsesPath(apiProvider: apiProvider)
        return websocketReachabilityCheck(inputs: DoctorWebsocketReachabilityInputs(
            providerID: settings.selectedModelProviderID,
            providerName: provider.name,
            wireAPI: provider.wireAPI,
            supportsWebsockets: provider.supportsWebsockets,
            proxyEnvironment: environment,
            connectTimeoutMilliseconds: provider.websocketConnectTimeoutMS(),
            authModeDescription: websocketAuthModeDescription(authMode),
            endpoint: endpoint,
            outcome: .notAttempted("handshake probe is not implemented in Swift doctor yet")
        ))
    }

    public static func websocketReachabilityCheck(inputs: DoctorWebsocketReachabilityInputs) -> DoctorCheck {
        var details = [
            "model provider: \(inputs.providerID)",
            "provider name: \(inputs.providerName)",
            "wire API: \(inputs.wireAPI.rawValue)",
            "supports websockets: \(rustBool(inputs.supportsWebsockets))"
        ]
        details.append(contentsOf: websocketProxyEnvironmentDetails(inputs.proxyEnvironment))

        guard inputs.supportsWebsockets else {
            return DoctorCheck(
                id: "network.websocket_reachability",
                category: "websocket",
                status: .ok,
                summary: "Responses WebSocket is not enabled for the active provider",
                details: details
            )
        }

        if let connectTimeoutMilliseconds = inputs.connectTimeoutMilliseconds {
            details.append("connect timeout: \(connectTimeoutMilliseconds) ms")
        }
        if let authModeDescription = inputs.authModeDescription {
            details.append("auth mode: \(authModeDescription)")
        }
        guard let endpoint = inputs.endpoint else {
            details.append("endpoint build failed: invalid URL")
            return DoctorCheck(
                id: "network.websocket_reachability",
                category: "websocket",
                status: .warning,
                summary: "Responses WebSocket endpoint could not be built",
                details: details,
                remediation: websocketReachabilityRemediation
            )
        }
        details.append("endpoint: \(endpoint)")
        if let dnsDetails = inputs.dnsDetails {
            details.append(dnsDetails)
        }

        switch inputs.outcome {
        case let .handshakeSucceeded(result):
            details.append(contentsOf: websocketHandshakeDetails(result))
            return DoctorCheck(
                id: "network.websocket_reachability",
                category: "websocket",
                status: .ok,
                summary: "Responses WebSocket handshake succeeded",
                details: details
            )
        case let .closedImmediately(result, code, reason):
            details.append(contentsOf: websocketHandshakeDetails(result))
            details.append("immediate close code: \(code)")
            details.append("immediate close reason: \(reason)")
            return DoctorCheck(
                id: "network.websocket_reachability",
                category: "websocket",
                status: .warning,
                summary: "Responses WebSocket closed immediately after handshake",
                details: details,
                remediation: websocketReachabilityRemediation
            )
        case let .failed(message):
            details.append("handshake error: \(message)")
            return DoctorCheck(
                id: "network.websocket_reachability",
                category: "websocket",
                status: .warning,
                summary: "Responses WebSocket failed; HTTPS fallback may still work",
                details: details,
                remediation: websocketReachabilityRemediation
            )
        case let .transportError(message):
            details.append("handshake transport error: \(message)")
            return DoctorCheck(
                id: "network.websocket_reachability",
                category: "websocket",
                status: .warning,
                summary: "Responses WebSocket failed; HTTPS fallback may still work",
                details: details,
                remediation: websocketReachabilityRemediation
            )
        case let .apiError(status, message):
            details.append("handshake API error: \(status) \(message)")
            return DoctorCheck(
                id: "network.websocket_reachability",
                category: "websocket",
                status: .warning,
                summary: "Responses WebSocket failed; HTTPS fallback may still work",
                details: details,
                remediation: websocketReachabilityRemediation
            )
        case let .streamError(message):
            details.append("handshake stream error: \(message)")
            return DoctorCheck(
                id: "network.websocket_reachability",
                category: "websocket",
                status: .warning,
                summary: "Responses WebSocket failed; HTTPS fallback may still work",
                details: details,
                remediation: websocketReachabilityRemediation
            )
        case .timedOut:
            details.append("handshake timed out")
            return DoctorCheck(
                id: "network.websocket_reachability",
                category: "websocket",
                status: .warning,
                summary: "Responses WebSocket timed out; HTTPS fallback may still work",
                details: details,
                remediation: websocketReachabilityRemediation
            )
        case let .notAttempted(reason):
            details.append("handshake stream error: \(reason)")
            return DoctorCheck(
                id: "network.websocket_reachability",
                category: "websocket",
                status: .warning,
                summary: "Responses WebSocket failed; HTTPS fallback may still work",
                details: details,
                remediation: websocketReachabilityRemediation
            )
        case .none:
            details.append("handshake stream error: not attempted")
            return DoctorCheck(
                id: "network.websocket_reachability",
                category: "websocket",
                status: .warning,
                summary: "Responses WebSocket failed; HTTPS fallback may still work",
                details: details,
                remediation: websocketReachabilityRemediation
            )
        }
    }

    public static func websocketURLForResponsesPath(apiProvider: APIProvider) -> String? {
        guard var components = URLComponents(string: apiProvider.urlForPath("responses")) else {
            return nil
        }
        switch components.scheme {
        case "http":
            components.scheme = "ws"
        case "https":
            components.scheme = "wss"
        default:
            break
        }
        return components.string
    }

    private static let websocketReachabilityRemediation =
        "Check proxy, VPN, firewall, DNS, custom CA, and WebSocket policy support."

    private static func websocketAuthMode(
        providerRequiresOpenAIAuth: Bool,
        environment: [String: String],
        storedAuth: AuthDotJSON?
    ) -> AuthMode? {
        guard providerRequiresOpenAIAuth else {
            return nil
        }
        if authEnvironmentVariablePresent(CodexAuthStorage.openAIAPIKeyEnvironmentVariable, in: environment)
            || authEnvironmentVariablePresent(CodexAuthStorage.codexAPIKeyEnvironmentVariable, in: environment)
        {
            return .apiKey
        }
        if authEnvironmentVariablePresent(CodexAuthStorage.codexAccessTokenEnvironmentVariable, in: environment) {
            return .chatGPT
        }
        if storedAuth?.openAIAPIKey?.isEmpty == false {
            return .apiKey
        }
        if let authMode = storedAuth?.authMode {
            return authMode
        }
        if storedAuth?.tokens != nil {
            return .chatGPT
        }
        return nil
    }

    private static func websocketAuthModeDescription(_ authMode: AuthMode?) -> String {
        switch authMode {
        case .apiKey:
            "api_key"
        case .chatGPT:
            "chatgpt"
        case .chatGPTAuthTokens:
            "chatgpt_auth_tokens"
        case .agentIdentity:
            "agent_identity"
        case .none:
            "none"
        }
    }

    private static func websocketProxyEnvironmentDetails(_ environment: [String: String]) -> [String] {
        let names = [
            "HTTP_PROXY",
            "HTTPS_PROXY",
            "ALL_PROXY",
            "NO_PROXY",
            "http_proxy",
            "https_proxy",
            "all_proxy",
            "no_proxy"
        ]
        let present = names.compactMap { name -> String? in
            guard environment[name]?.isEmpty == false else {
                return nil
            }
            return name
        }
        if present.isEmpty {
            return ["proxy env vars: none"]
        }
        return ["proxy env vars present: \(present.joined(separator: ", "))"]
    }

    private static func websocketHandshakeDetails(_ result: DoctorWebsocketHandshakeResult) -> [String] {
        [
            "handshake result: HTTP \(result.httpStatus)",
            "reasoning header: \(rustBool(result.reasoningHeaderPresent))",
            "models etag present: \(rustBool(result.modelsETagPresent))",
            "server model present: \(rustBool(result.serverModelPresent))"
        ]
    }

    private static func authEnvironmentVariablePresent(_ name: String, in environment: [String: String]) -> Bool {
        environment[name]?.isEmpty == false
    }

    private static func rustBool(_ value: Bool) -> String {
        value ? "true" : "false"
    }

}
