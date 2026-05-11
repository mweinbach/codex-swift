import CodexCore
import CodexMCPServer
import CryptoKit
import Darwin
import Dispatch
import Foundation

public typealias AppServerAuthRefreshTransport = @Sendable (URLRequest) async throws -> AuthRefreshHTTPResponse
public typealias AppServerNotificationSink = @Sendable (Data) async -> Void
public typealias AppServerMcpHTTPTransport = @Sendable (URLRequest) async throws -> URLSessionTransportResponse
public typealias AppServerPluginHTTPTransport = @Sendable (URLRequest) throws -> URLSessionTransportResponse
public typealias AppServerAccessibleConnectorProvider = @Sendable (
    _ runtimeConfig: CodexRuntimeConfig,
    _ usesChatGPTBackend: Bool
) throws -> [DiscoverableConnectorInfo]?
public typealias AppServerMcpOAuthLoginCompletion = @Sendable (_ success: Bool, _ error: String?) async -> Void
public typealias AppServerMcpOAuthLoginStarter = @Sendable (
    AppServerMcpOAuthLoginStartRequest,
    @escaping AppServerMcpOAuthLoginCompletion
) async throws -> AppServerMcpOAuthLoginStarted

public struct AppServerMcpOAuthLoginStartRequest: Sendable {
    public let name: String
    public let serverURL: String
    public let codexHome: URL
    public let storeMode: OAuthCredentialsStoreMode
    public let httpHeaders: [String: String]?
    public let envHttpHeaders: [String: String]?
    public let environment: [String: String]
    public let scopes: [String]?
    public let oauthResource: String?
    public let timeoutSeconds: Int?
    public let callbackPort: UInt16?
    public let callbackURL: String?

    public init(
        name: String,
        serverURL: String,
        codexHome: URL,
        storeMode: OAuthCredentialsStoreMode,
        httpHeaders: [String: String]? = nil,
        envHttpHeaders: [String: String]? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        scopes: [String]? = nil,
        oauthResource: String? = nil,
        timeoutSeconds: Int? = nil,
        callbackPort: UInt16? = nil,
        callbackURL: String? = nil
    ) {
        self.name = name
        self.serverURL = serverURL
        self.codexHome = codexHome
        self.storeMode = storeMode
        self.httpHeaders = httpHeaders
        self.envHttpHeaders = envHttpHeaders
        self.environment = environment
        self.scopes = scopes
        self.oauthResource = oauthResource
        self.timeoutSeconds = timeoutSeconds
        self.callbackPort = callbackPort
        self.callbackURL = callbackURL
    }
}

public struct AppServerMcpOAuthLoginStarted: Sendable {
    public let authorizationURL: String

    public init(authorizationURL: String) {
        self.authorizationURL = authorizationURL
    }
}

private actor AppServerMcpOAuthAuthorizationURLCapture {
    private var continuation: CheckedContinuation<String, Error>?
    private var result: Result<String, Error>?

    func wait() async throws -> String {
        if let result {
            return try result.get()
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func succeed(_ authorizationURL: String) {
        resolve(.success(authorizationURL))
    }

    func fail(_ error: Error) {
        resolve(.failure(error))
    }

    private func resolve(_ next: Result<String, Error>) {
        guard result == nil else {
            return
        }
        result = next
        if let continuation {
            self.continuation = nil
            continuation.resume(with: next)
        }
    }
}

public struct CodexAppServerConfiguration: Equatable, Sendable {
    public let codexHome: URL
    public let cwd: URL
    public let defaultModelProvider: String
    public let originator: String
    public let version: String
    public let requiresOpenAIAuth: Bool
    public let authCredentialsStoreMode: AuthCredentialsStoreMode
    public let environment: [String: String]
    public let activeProfile: String?
    public let feedback: CodexFeedback
    public let feedbackUploadTransport: any FeedbackUploadTransport
    public let acceptedLineAnalyticsUploader: any AcceptedLineAnalyticsUploading
    public let accountRateLimitsFetcher: any AccountRateLimitsFetching
    public let addCreditsNudgeEmailSender: any AddCreditsNudgeEmailSending
    public let authRefreshTransport: AppServerAuthRefreshTransport?
    public let authLoginTransport: ChatGPTLoginTransport?
    public let authDeviceCodeTransport: ChatGPTDeviceCodeLoginTransport?
    public let mcpHTTPTransport: AppServerMcpHTTPTransport
    public let pluginHTTPTransport: AppServerPluginHTTPTransport
    public let accessibleConnectorProvider: AppServerAccessibleConnectorProvider
    public let mcpOAuthLoginStarter: AppServerMcpOAuthLoginStarter
    public let cliConfigOverrides: CliConfigOverrides
    public let configLayerOverrides: ConfigLayerLoaderOverrides
    public let stateStore: SQLiteAgentGraphStore?

    public init(
        codexHome: URL,
        cwd: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
        defaultModelProvider: String = "openai",
        originator: String = "codex_swift",
        version: String = "0.0.0",
        requiresOpenAIAuth: Bool = true,
        authCredentialsStoreMode: AuthCredentialsStoreMode = .file,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        activeProfile: String? = nil,
        feedback: CodexFeedback = CodexFeedback(),
        feedbackUploadTransport: any FeedbackUploadTransport = URLSessionFeedbackUploadTransport(),
        acceptedLineAnalyticsUploader: (any AcceptedLineAnalyticsUploading)? = nil,
        accountRateLimitsFetcher: any AccountRateLimitsFetching = URLSessionAccountRateLimitsFetcher(),
        addCreditsNudgeEmailSender: any AddCreditsNudgeEmailSending = URLSessionAddCreditsNudgeEmailSender(),
        authRefreshTransport: AppServerAuthRefreshTransport? = nil,
        authLoginTransport: ChatGPTLoginTransport? = nil,
        authDeviceCodeTransport: ChatGPTDeviceCodeLoginTransport? = nil,
        mcpHTTPTransport: @escaping AppServerMcpHTTPTransport = CodexAppServer.defaultMcpHTTPTransport,
        pluginHTTPTransport: @escaping AppServerPluginHTTPTransport = CodexAppServer.defaultPluginHTTPTransport,
        accessibleConnectorProvider: @escaping AppServerAccessibleConnectorProvider = CodexAppServer.defaultAccessibleConnectorProvider,
        mcpOAuthLoginStarter: @escaping AppServerMcpOAuthLoginStarter = CodexAppServer.defaultMcpOAuthLoginStarter,
        cliConfigOverrides: CliConfigOverrides = CliConfigOverrides(),
        configLayerOverrides: ConfigLayerLoaderOverrides = ConfigLayerLoaderOverrides(),
        stateStore: SQLiteAgentGraphStore? = nil
    ) {
        self.codexHome = codexHome
        self.cwd = cwd
        self.defaultModelProvider = defaultModelProvider
        self.originator = originator
        self.version = version
        self.requiresOpenAIAuth = requiresOpenAIAuth
        self.authCredentialsStoreMode = authCredentialsStoreMode
        self.environment = environment
        self.activeProfile = activeProfile
        self.feedback = feedback
        self.feedbackUploadTransport = feedbackUploadTransport
        self.acceptedLineAnalyticsUploader = acceptedLineAnalyticsUploader ?? URLSessionAcceptedLineAnalyticsUploader(
            codexHome: codexHome,
            authCredentialsStoreMode: authCredentialsStoreMode,
            baseURL: CodexConfigDefaults.chatgptBaseURL,
            environment: environment,
            refreshTransport: authRefreshTransport
        )
        self.accountRateLimitsFetcher = accountRateLimitsFetcher
        self.addCreditsNudgeEmailSender = addCreditsNudgeEmailSender
        self.authRefreshTransport = authRefreshTransport
        self.authLoginTransport = authLoginTransport
        self.authDeviceCodeTransport = authDeviceCodeTransport
        self.mcpHTTPTransport = mcpHTTPTransport
        self.pluginHTTPTransport = pluginHTTPTransport
        self.accessibleConnectorProvider = accessibleConnectorProvider
        self.mcpOAuthLoginStarter = mcpOAuthLoginStarter
        self.cliConfigOverrides = cliConfigOverrides
        self.configLayerOverrides = configLayerOverrides
        self.stateStore = stateStore
    }

    public static func == (lhs: CodexAppServerConfiguration, rhs: CodexAppServerConfiguration) -> Bool {
        lhs.codexHome == rhs.codexHome &&
            lhs.cwd == rhs.cwd &&
            lhs.defaultModelProvider == rhs.defaultModelProvider &&
            lhs.originator == rhs.originator &&
            lhs.version == rhs.version &&
            lhs.requiresOpenAIAuth == rhs.requiresOpenAIAuth &&
            lhs.authCredentialsStoreMode == rhs.authCredentialsStoreMode &&
            lhs.environment == rhs.environment &&
            lhs.activeProfile == rhs.activeProfile &&
            lhs.cliConfigOverrides == rhs.cliConfigOverrides &&
            lhs.configLayerOverrides == rhs.configLayerOverrides
    }
}

public protocol AccountRateLimitsFetching: Sendable {
    func fetchRateLimits(baseURL: String, accessToken: String, accountID: String) async throws -> AccountRateLimitsResult
}

public protocol AddCreditsNudgeEmailSending: Sendable {
    func send(baseURL: String, accessToken: String, accountID: String, creditType: AddCreditsNudgeCreditType) async throws -> AddCreditsNudgeEmailStatus
}

public struct AccountRateLimitsResult: Equatable, Sendable {
    public let rateLimits: RateLimitSnapshot
    public let rateLimitsByLimitID: [String: RateLimitSnapshot]

    public init(rateLimits: RateLimitSnapshot, rateLimitsByLimitID: [String: RateLimitSnapshot]) {
        self.rateLimits = rateLimits
        self.rateLimitsByLimitID = rateLimitsByLimitID
    }

    public init(rateLimits: RateLimitSnapshot) {
        let limitID = rateLimits.limitID ?? "codex"
        self.init(rateLimits: rateLimits, rateLimitsByLimitID: [limitID: rateLimits])
    }
}

public struct AccountRateLimitsHTTPResponse: Sendable {
    public let statusCode: Int
    public let body: Data

    public init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }
}

public enum AddCreditsNudgeCreditType: String, Sendable {
    case credits
    case usageLimit = "usage_limit"
}

public enum AddCreditsNudgeEmailStatus: String, Sendable {
    case sent
    case cooldownActive = "cooldown_active"
}

private struct AppServerProcessSpawnParams {
    let command: [String]
    let processHandle: String
    let cwd: String
    let tty: Bool
    let streamStdin: Bool
    let streamStdoutStderr: Bool
    let timeoutMs: Int?
    let outputBytesCap: Int?
    let size: AppServerTerminalSize?
    let environmentOverrides: [String: String?]
}

private struct AppServerProcessWriteStdinParams {
    let processHandle: String
    let delta: Data
    let closeStdin: Bool
}

private struct AppServerCommandExecParams {
    let command: [String]
    let processID: String?
    let cwd: String?
    let tty: Bool
    let streamStdin: Bool
    let streamStdoutStderr: Bool
    let timeoutMs: Int?
    let outputBytesCap: Int?
    let size: AppServerTerminalSize?
    let environmentOverrides: [String: String?]
    let sandboxPolicy: SandboxPolicy?
    let permissionProfile: PermissionProfile?
}

private struct AppServerSandboxLaunch {
    let command: [String]
    let environment: [String: String]
}

private struct AppServerCommandExecSandboxConfiguration {
    let legacyPolicy: SandboxPolicy?
    let permissionProfile: PermissionProfile?
    let cwd: URL

    static func legacy(policy: SandboxPolicy, cwd: URL) -> AppServerCommandExecSandboxConfiguration {
        AppServerCommandExecSandboxConfiguration(legacyPolicy: policy, permissionProfile: nil, cwd: cwd)
    }

    static func direct(
        permissionProfile: PermissionProfile,
        cwd: URL
    ) -> AppServerCommandExecSandboxConfiguration {
        AppServerCommandExecSandboxConfiguration(
            legacyPolicy: nil,
            permissionProfile: permissionProfile,
            cwd: cwd
        )
    }
}

private struct AppServerCommandExecWriteParams {
    let processID: String
    let delta: Data
    let closeStdin: Bool
}

private struct AppServerTerminalSize {
    let rows: Int
    let cols: Int
}

private struct AppServerJSONObject: @unchecked Sendable {
    let object: [String: Any]
}

private struct AppServerMcpServerStatusSnapshot: @unchecked Sendable {
    var toolsByServer: [String: [String: Any]] = [:]
    var resources: [String: [[String: Any]]] = [:]
    var resourceTemplates: [String: [[String: Any]]] = [:]
}

private let appServerDefaultExecCommandTimeoutMs = 10_000
private let appServerStandardBase64Bytes = Set(Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=".utf8))

private func decodeAppServerStandardBase64(
    _ value: String,
    error: (String) -> AppServerError
) throws -> Data {
    if let data = Data(base64Encoded: value) {
        return data
    }
    for (offset, byte) in value.utf8.enumerated() where !appServerStandardBase64Bytes.contains(byte) {
        throw error("Invalid byte \(byte), offset \(offset).")
    }
    throw error("Invalid padding")
}

private final class AppServerStdioResponseCapture: @unchecked Sendable {
    private let id: Int
    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()
    private var storedResponse: [String: Any]?

    init(id: Int) {
        self.id = id
    }

    var response: [String: Any]? {
        lock.lock()
        defer { lock.unlock() }
        return storedResponse
    }

    var stderrText: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: stderrData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func appendStdout(_ data: Data) {
        guard !data.isEmpty else {
            return
        }
        lock.lock()
        stdoutData.append(data)
        if storedResponse == nil {
            storedResponse = Self.response(id: id, from: stdoutData)
        }
        lock.unlock()
    }

    func appendStderr(_ data: Data) {
        guard !data.isEmpty else {
            return
        }
        lock.lock()
        stderrData.append(data)
        lock.unlock()
    }

    private static func response(id: Int, from data: Data) -> [String: Any]? {
        let text = String(decoding: data, as: UTF8.self)
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  (object["id"] as? Int) == id else {
                continue
            }
            return object
        }
        return nil
    }
}

public struct URLSessionAccountRateLimitsFetcher: AccountRateLimitsFetching {
    public typealias Transport = @Sendable (URLRequest) async throws -> AccountRateLimitsHTTPResponse

    private let transport: Transport

    public init() {
        self.transport = URLSessionAccountRateLimitsFetcher.urlSessionTransport
    }

    public init(transport: @escaping Transport) {
        self.transport = transport
    }

    public func fetchRateLimits(baseURL: String, accessToken: String, accountID: String) async throws -> AccountRateLimitsResult {
        let normalizedBaseURL = AccountBackendEndpoint.normalizedBaseURL(baseURL)
        let usagePath = AccountBackendEndpoint.isChatGPTPathStyle(normalizedBaseURL) ? "/wham/usage" : "/api/codex/usage"
        let endpointText = normalizedBaseURL + usagePath
        guard let url = URL(string: endpointText) else {
            throw AccountRateLimitsFetchError.invalidURL(endpointText)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(accountID, forHTTPHeaderField: "chatgpt-account-id")

        let response = try await transport(request)
        guard (200..<300).contains(response.statusCode) else {
            throw AccountRateLimitsFetchError.httpStatus(response.statusCode)
        }

        let payload = try JSONDecoder().decode(AccountRateLimitsUsageResponse.self, from: response.body)
        return payload.result
    }

    private static func urlSessionTransport(_ request: URLRequest) async throws -> AccountRateLimitsHTTPResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AccountRateLimitsFetchError.nonHTTPResponse
        }
        return AccountRateLimitsHTTPResponse(statusCode: httpResponse.statusCode, body: data)
    }
}

public struct URLSessionAddCreditsNudgeEmailSender: AddCreditsNudgeEmailSending {
    public typealias Transport = @Sendable (URLRequest) async throws -> AccountRateLimitsHTTPResponse

    private let transport: Transport

    public init() {
        self.transport = URLSessionAddCreditsNudgeEmailSender.urlSessionTransport
    }

    public init(transport: @escaping Transport) {
        self.transport = transport
    }

    public func send(
        baseURL: String,
        accessToken: String,
        accountID: String,
        creditType: AddCreditsNudgeCreditType
    ) async throws -> AddCreditsNudgeEmailStatus {
        let normalizedBaseURL = AccountBackendEndpoint.normalizedBaseURL(baseURL)
        let path = AccountBackendEndpoint.isChatGPTPathStyle(normalizedBaseURL)
            ? "/wham/accounts/send_add_credits_nudge_email"
            : "/api/codex/accounts/send_add_credits_nudge_email"
        let endpointText = normalizedBaseURL + path
        guard let url = URL(string: endpointText) else {
            throw AccountRateLimitsFetchError.invalidURL(endpointText)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(accountID, forHTTPHeaderField: "chatgpt-account-id")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["credit_type": creditType.rawValue])

        let response = try await transport(request)
        if response.statusCode == 429 {
            return .cooldownActive
        }
        guard (200..<300).contains(response.statusCode) else {
            throw AccountRateLimitsFetchError.httpStatus(response.statusCode)
        }
        return .sent
    }

    private static func urlSessionTransport(_ request: URLRequest) async throws -> AccountRateLimitsHTTPResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AccountRateLimitsFetchError.nonHTTPResponse
        }
        return AccountRateLimitsHTTPResponse(statusCode: httpResponse.statusCode, body: data)
    }
}

private enum AccountBackendEndpoint {
    static func normalizedBaseURL(_ baseURL: String) -> String {
        var normalized = baseURL
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        if (normalized.hasPrefix("https://chatgpt.com") || normalized.hasPrefix("https://chat.openai.com"))
            && !normalized.contains("/backend-api")
        {
            normalized += "/backend-api"
        }
        return normalized
    }

    static func isChatGPTPathStyle(_ normalizedBaseURL: String) -> Bool {
        normalizedBaseURL.contains("/backend-api")
    }
}

private enum AccountRateLimitsFetchError: Error, CustomStringConvertible {
    case invalidURL(String)
    case nonHTTPResponse
    case httpStatus(Int)

    var description: String {
        switch self {
        case let .invalidURL(url):
            return "invalid usage URL: \(url)"
        case .nonHTTPResponse:
            return "non-HTTP response"
        case let .httpStatus(status):
            return "HTTP status \(status)"
        }
    }
}

private struct AccountRateLimitsUsageResponse: Decodable {
    let planType: PlanType?
    let rateLimit: AccountUsageRateLimit?
    let rateLimitReachedType: AccountRateLimitReachedTypePayload?
    let additionalRateLimits: [AccountUsageAdditionalRateLimit]

    private enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case rateLimitReachedType = "rate_limit_reached_type"
        case additionalRateLimits = "additional_rate_limits"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.planType = try container.decodeIfPresent(PlanType.self, forKey: .planType)
        self.rateLimit = try container.decodeIfPresent(AccountUsageRateLimit.self, forKey: .rateLimit)
        self.rateLimitReachedType = try container.decodeIfPresent(
            AccountRateLimitReachedTypePayload.self,
            forKey: .rateLimitReachedType
        )
        self.additionalRateLimits = try container.decodeIfPresent(
            [AccountUsageAdditionalRateLimit].self,
            forKey: .additionalRateLimits
        ) ?? []
    }

    var snapshot: RateLimitSnapshot {
        RateLimitSnapshot(
            limitID: "codex",
            primary: rateLimit?.primaryWindow?.rateLimitWindow,
            secondary: rateLimit?.secondaryWindow?.rateLimitWindow,
            credits: nil,
            planType: planType,
            rateLimitReachedType: rateLimitReachedType?.rateLimitReachedType
        )
    }

    var result: AccountRateLimitsResult {
        let primary = snapshot
        var snapshots = [primary] + additionalRateLimits.map { $0.snapshot(planType: planType) }
        if let codex = snapshots.first(where: { $0.limitID == "codex" }) {
            return AccountRateLimitsResult(
                rateLimits: codex,
                rateLimitsByLimitID: Dictionary(uniqueKeysWithValues: snapshots.map {
                    (($0.limitID ?? "codex"), $0)
                })
            )
        }
        let fallback = snapshots.removeFirst()
        return AccountRateLimitsResult(
            rateLimits: fallback,
            rateLimitsByLimitID: Dictionary(uniqueKeysWithValues: ([fallback] + snapshots).map {
                (($0.limitID ?? "codex"), $0)
            })
        )
    }
}

private struct AccountRateLimitReachedTypePayload: Decodable {
    let type: String

    var rateLimitReachedType: RateLimitReachedType? {
        RateLimitReachedType(rawValue: type)
    }
}

private struct AccountUsageRateLimit: Decodable {
    let primaryWindow: AccountUsageWindow?
    let secondaryWindow: AccountUsageWindow?

    private enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

private struct AccountUsageAdditionalRateLimit: Decodable {
    let limitName: String?
    let meteredFeature: String?
    let rateLimit: AccountUsageRateLimit?

    private enum CodingKeys: String, CodingKey {
        case limitName = "limit_name"
        case meteredFeature = "metered_feature"
        case rateLimit = "rate_limit"
    }

    func snapshot(planType: PlanType?) -> RateLimitSnapshot {
        RateLimitSnapshot(
            limitID: meteredFeature ?? limitName,
            limitName: limitName,
            primary: rateLimit?.primaryWindow?.rateLimitWindow,
            secondary: rateLimit?.secondaryWindow?.rateLimitWindow,
            credits: nil,
            planType: planType
        )
    }
}

private struct AccountUsageWindow: Decodable {
    let usedPercent: Double
    let limitWindowSeconds: Int64?
    let resetAt: Int64?

    private enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAt = "reset_at"
    }

    var rateLimitWindow: RateLimitWindow {
        RateLimitWindow(
            usedPercent: usedPercent,
            windowMinutes: Self.windowMinutes(from: limitWindowSeconds),
            resetsAt: resetAt
        )
    }

    private static func windowMinutes(from seconds: Int64?) -> Int64? {
        guard let seconds, seconds > 0 else {
            return nil
        }
        return (seconds + 59) / 60
    }
}

public enum CodexAppServer {
    private static let defaultListLimit = 25
    private static let maxListLimit = 100
    private static let maxUserInputTextScalars = 1 << 20
    private static let pluginTransportFinalURLHeader = "x-codex-plugin-transport-final-url"
    fileprivate static let persistExtendedHistoryDeprecationSummary =
        "persistExtendedHistory is deprecated and ignored"
    fileprivate static let persistExtendedHistoryDeprecationDetails =
        "Remove this parameter. App-server always uses limited history persistence."
    fileprivate static let fuzzyFileSearchLimitPerRoot = 50
    private static let interactiveSessionSources: [SessionSource] = [.cli, .vscode]
    fileprivate static let platformFamily = "unix"
    fileprivate static var platformOS: String {
        #if os(macOS)
            return "macos"
        #elseif os(Linux)
            return "linux"
        #elseif os(Windows)
            return "windows"
        #else
            return "unknown"
        #endif
    }

    public static func defaultMcpOAuthLoginStarter(
        request: AppServerMcpOAuthLoginStartRequest,
        completion: @escaping AppServerMcpOAuthLoginCompletion
    ) async throws -> AppServerMcpOAuthLoginStarted {
        let capture = AppServerMcpOAuthAuthorizationURLCapture()
        Task {
            do {
                try await McpOAuthLogin.perform(
                    request: McpOAuthLoginRequest(
                        serverName: request.name,
                        serverURL: request.serverURL,
                        codexHome: request.codexHome,
                        storeMode: request.storeMode,
                        httpHeaders: request.httpHeaders,
                        envHttpHeaders: request.envHttpHeaders,
                        environment: request.environment,
                        scopes: request.scopes,
                        oauthResource: request.oauthResource,
                        timeoutSeconds: request.timeoutSeconds,
                        launchBrowser: true,
                        callbackPort: request.callbackPort,
                        callbackURL: request.callbackURL
                    ),
                    browserLauncher: { _ in },
                    messageSink: { message in
                        if case let .authorizationURL(_, authURL) = message {
                            await capture.succeed(authURL)
                        }
                    }
                )
                await completion(true, nil)
            } catch {
                await capture.fail(error)
                await completion(false, String(describing: error))
            }
        }
        return AppServerMcpOAuthLoginStarted(authorizationURL: try await capture.wait())
    }

    public static func defaultMcpHTTPTransport(_ request: URLRequest) async throws -> URLSessionTransportResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppServerError.internalError("MCP server returned a non-HTTP response")
        }
        return URLSessionTransportResponse(
            statusCode: httpResponse.statusCode,
            headers: Dictionary(
                uniqueKeysWithValues: httpResponse.allHeaderFields.compactMap { key, value in
                    guard let name = key as? String else {
                        return nil
                    }
                    return (name, String(describing: value))
                }
            ),
            body: data
        )
    }

    public static func defaultAccessibleConnectorProvider(
        runtimeConfig _: CodexRuntimeConfig,
        usesChatGPTBackend _: Bool
    ) throws -> [DiscoverableConnectorInfo]? {
        nil
    }

    public static func defaultPluginHTTPTransport(_ request: URLRequest) throws -> URLSessionTransportResponse {
        let semaphore = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable {
            var result: Result<URLSessionTransportResponse, Error>?
        }
        let box = Box()
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                box.result = .failure(error)
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                box.result = .failure(AppServerError.internalError("plugin service returned a non-HTTP response"))
                return
            }
            var headers: [String: String] = Dictionary(
                uniqueKeysWithValues: httpResponse.allHeaderFields.compactMap { key, value in
                    guard let name = key as? String else {
                        return nil
                    }
                    return (name, String(describing: value))
                }
            )
            if let finalURL = httpResponse.url?.absoluteString {
                headers[Self.pluginTransportFinalURLHeader] = finalURL
            }
            box.result = .success(URLSessionTransportResponse(
                statusCode: httpResponse.statusCode,
                headers: headers,
                body: data ?? Data()
            ))
        }
        task.resume()
        semaphore.wait()
        return try box.result?.get() ?? {
            throw AppServerError.internalError("plugin service request did not complete")
        }()
    }

    fileprivate static func isUnauthorizedBackendError(_ error: Error) -> Bool {
        guard let fetchError = error as? AccountRateLimitsFetchError else {
            return false
        }
        if case .httpStatus(401) = fetchError {
            return true
        }
        return false
    }

    public static func run(
        configuration: CodexAppServerConfiguration,
        stdin: FileHandle = .standardInput,
        stdout: FileHandle = .standardOutput
    ) throws {
        var buffer = Data()
        let processor = CodexAppServerMessageProcessor(
            configuration: configuration,
            notificationSink: { data in
                stdout.write(data)
                stdout.write(Data([0x0A]))
            }
        )
        while true {
            let data = stdin.availableData
            if data.isEmpty {
                break
            }
            buffer.append(data)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newline]
                buffer.removeSubrange(...newline)
                guard !line.isEmpty else {
                    continue
                }
                try write(processor.processLine(Data(line)), to: stdout)
            }
        }

        if !buffer.isEmpty {
            try write(processor.processLine(buffer), to: stdout)
        }
    }

    static func processLine(
        _ data: Data,
        configuration: CodexAppServerConfiguration
    ) -> Data? {
        CodexAppServerMessageProcessor(configuration: configuration).processLine(data)
    }

    fileprivate static func threadListResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        let sourceFilter = try threadListSourceFilter(params?["sourceKinds"])
        let sortKey = try threadListSortKey(params?["sortKey"])
        let sortDirection = try threadListSortDirection(params?["sortDirection"])
        let cursor = try threadListCursor(params?["cursor"])
        let pageSize = try rustU32ListLimit(params?["limit"])
        let modelProviders = modelProviderFilter(params?["modelProviders"], defaultProvider: configuration.defaultModelProvider)
        let cwdFilters = try threadListCwdFilters(params?["cwd"])
        let archivedOnly = try rustOptionalBoolParam(params?["archived"], defaultValue: false)
        let searchTerm = stringParam(params?["searchTerm"])
        let hasExplicitMetadataFilter = params?["cwd"] != nil
            || params?["modelProviders"] != nil
            || params?["sourceKinds"] != nil
            || searchTerm?.isEmpty == false
        if try rustDefaultBoolParam(params?["useStateDbOnly"], defaultValue: false) {
            return try threadListStateDbOnlyResult(
                configuration: configuration,
                pageSize: pageSize,
                cursor: cursor,
                allowedSources: sourceFilter.allowedSources,
                sourceMatcher: sourceFilter.matcher,
                modelProviders: modelProviders,
                archivedOnly: archivedOnly,
                cwdFilters: cwdFilters,
                searchTerm: searchTerm,
                sortKey: sortKey,
                sortDirection: sortDirection
            )
        }

        let page = try RolloutListing.getConversations(
            codexHome: configuration.codexHome,
            pageSize: pageSize,
            cursor: cursor,
            allowedSources: sourceFilter.allowedSources,
            modelProviders: modelProviders,
            archivedOnly: archivedOnly,
            cwdFilters: cwdFilters,
            searchTerm: searchTerm,
            sourceMatcher: sourceFilter.matcher,
            sortKey: sortKey,
            sortDirection: sortDirection,
            defaultProvider: configuration.defaultModelProvider
        )
        try repairStateStoreFromThreadListPage(
            page,
            configuration: configuration,
            archivedOnly: archivedOnly
        )
        try reconcileStateStoreFilteredHits(
            configuration: configuration,
            pageSize: pageSize,
            cursor: cursor,
            allowedSources: sourceFilter.allowedSources,
            sourceMatcher: sourceFilter.matcher,
            modelProviders: modelProviders,
            archivedOnly: archivedOnly,
            cwdFilters: cwdFilters,
            searchTerm: searchTerm,
            sortKey: sortKey,
            sortDirection: sortDirection,
            hasExplicitMetadataFilter: hasExplicitMetadataFilter
        )
        if configuration.stateStore != nil, !hasExplicitMetadataFilter {
            return try threadListStateDbOnlyResult(
                configuration: configuration,
                pageSize: pageSize,
                cursor: cursor,
                allowedSources: sourceFilter.allowedSources,
                sourceMatcher: sourceFilter.matcher,
                modelProviders: modelProviders,
                archivedOnly: archivedOnly,
                cwdFilters: cwdFilters,
                searchTerm: searchTerm,
                sortKey: sortKey,
                sortDirection: sortDirection
            )
        }
        return [
            "data": try threadObjects(for: page.items, configuration: configuration),
            "nextCursor": (page.nextCursor?.token as Any?) ?? NSNull(),
            "backwardsCursor": (page.backwardsCursor?.token as Any?) ?? NSNull()
        ]
    }

    fileprivate static func threadStartResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> (result: [String: Any], sessionStartSource: HookSessionStartSource) {
        try validateTurnEnvironmentSelections(params?["environments"], configuration: configuration)
        let started = try startRolloutConversation(params: params, configuration: configuration)
        let permissionProfile = started.permissionProfile
        let thread: [String: Any]
        if started.ephemeral {
            thread = threadObject(for: started)
        } else {
            guard let rolloutPath = started.rolloutPath else {
                throw AppServerError.internalError("persistent thread start did not create a rollout")
            }
            let item = ConversationItem(path: rolloutPath.path, head: [], createdAt: nil, updatedAt: nil)
            thread = try threadObject(
                for: item,
                defaultProvider: configuration.defaultModelProvider
            )
        }
        let result = [
            "thread": thread,
            "model": started.model,
            "modelProvider": started.modelProvider,
            "serviceTier": nullable(started.serviceTier),
            "cwd": started.cwd.path,
            "instructionSources": [],
            "approvalPolicy": started.approvalPolicy.rawValue,
            "approvalsReviewer": started.approvalsReviewer.appServerRawValue,
            "sandbox": try jsonObject(started.sandbox),
            "permissionProfile": try jsonObject(permissionProfile),
            "activePermissionProfile": activePermissionProfileObject(started.activePermissionProfile),
            "reasoningEffort": started.reasoningEffort ?? NSNull()
        ].nullStripped(keepNulls: true)
        return (result: result, sessionStartSource: started.sessionStartSource)
    }

    fileprivate static func newConversationResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        let started = try startRolloutConversation(params: params, configuration: configuration)
        return [
            "conversationId": started.conversationID.description,
            "model": started.model,
            "reasoningEffort": started.reasoningEffort ?? NSNull(),
            "rolloutPath": started.rolloutPath?.path ?? NSNull()
        ].nullStripped(keepNulls: true)
    }

    private static func startRolloutConversation(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> AppServerStartedConversation {
        let cwd = stringParam(params?["cwd"]).map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let permissionSelection = try permissionProfileSelectionParam(params?["permissions"])
        let runtimeConfig = try loadRuntimeConfigForThreadStartup(
            configuration: configuration,
            cwd: cwd,
            permissionSelection: permissionSelection
        )
        let model = stringParam(params?["model"])
            ?? runtimeConfig.model
            ?? ModelsManager.offlineModel(explicitModel: nil)
        let modelProvider = stringParam(params?["modelProvider"])
            ?? runtimeConfig.selectedModelProviderID
        let approvalPolicy = approvalPolicyParam(params?["approvalPolicy"])
            ?? runtimeConfig.approvalPolicy
            ?? .unlessTrusted
        let approvalsReviewer = try approvalsReviewerParam(params?["approvalsReviewer"])
            ?? runtimeConfig.approvalsReviewer
        let serviceTier = try resolvedServiceTier(
            serviceTierParam(params?["serviceTier"]),
            fallback: runtimeConfig.serviceTier
        )
        let baseSandbox = sandboxModeParam(params?["sandbox"])
            .map(sandboxPolicy(for:))
            ?? runtimeConfig.legacySandboxPolicy()
        let dynamicTools = try dynamicToolsParam(params?["dynamicTools"]) ?? []
        let sessionStartSource = try sessionStartSourceParam(
            params?["sessionStartSource"] ?? params?["session_start_source"]
        )
        do {
            try DynamicToolSpec.validate(dynamicTools)
        } catch let error as DynamicToolValidationError {
            throw AppServerError.invalidRequest(error.description)
        }
        let permissionProfile = runtimeConfig.permissionProfile ?? PermissionProfile.fromLegacySandboxPolicyForCwd(
            baseSandbox,
            cwd: cwd.path
        )
        let sandbox = responseSandboxPolicy(
            for: permissionProfile,
            cwd: cwd.path,
            fallback: baseSandbox
        )
        try persistTrustedProjectForThreadStartIfNeeded(
            params: params,
            cwd: cwd,
            sandbox: sandbox,
            configuration: configuration
        )
        let conversationID = ConversationId()
        if try rustOptionalBoolParam(params?["ephemeral"], defaultValue: false) {
            return AppServerStartedConversation(
                conversationID: conversationID,
                rolloutPath: nil,
                model: model,
                modelProvider: modelProvider,
                cwd: cwd,
                approvalPolicy: approvalPolicy,
                approvalsReviewer: approvalsReviewer,
                serviceTier: serviceTier,
                sandbox: sandbox,
                permissionProfile: permissionProfile,
                activePermissionProfile: runtimeConfig.activePermissionProfile,
                reasoningEffort: runtimeConfig.modelReasoningEffort?.rawValue,
                sessionStartSource: sessionStartSource,
                ephemeral: true
            )
        }
        let recorder = try RolloutRecorder.create(
            codexHome: configuration.codexHome,
            cwd: cwd,
            conversationID: conversationID,
            instructions: stringParam(params?["developerInstructions"])
                ?? stringParam(params?["developer_instructions"])
                ?? stringParam(params?["baseInstructions"])
                ?? stringParam(params?["base_instructions"]),
            source: .mcp,
            originator: "codex_app_server",
            cliVersion: configuration.version,
            modelProvider: modelProvider,
            dynamicTools: dynamicTools.isEmpty ? nil : dynamicTools
        )
        try recorder.shutdown()
        return AppServerStartedConversation(
            conversationID: conversationID,
            rolloutPath: recorder.rolloutPath,
            model: model,
            modelProvider: modelProvider,
            cwd: cwd,
            approvalPolicy: approvalPolicy,
            approvalsReviewer: approvalsReviewer,
            serviceTier: serviceTier,
            sandbox: sandbox,
            permissionProfile: permissionProfile,
            activePermissionProfile: runtimeConfig.activePermissionProfile,
            reasoningEffort: runtimeConfig.modelReasoningEffort?.rawValue,
            sessionStartSource: sessionStartSource,
            ephemeral: false
        )
    }

    private struct DynamicToolsPayload: Decodable {
        let dynamicTools: [DynamicToolSpec]
    }

    private struct PermissionProfileSelection {
        let id: String
        let modifications: [ActivePermissionProfileModification]
        let additionalWritableRoots: [AbsolutePath]
    }

    private static func permissionProfileSelectionParam(_ raw: Any?) throws -> PermissionProfileSelection? {
        guard let raw, !(raw is NSNull) else {
            return nil
        }
        guard let object = raw as? [String: Any],
              stringParam(object["type"]) == "profile",
              let id = try strictStringParam(object["id"], fieldName: "permissions.id")
        else {
            throw AppServerError.invalidRequest("invalid permissions")
        }
        guard let rawModifications = object["modifications"], !(rawModifications is NSNull) else {
            return PermissionProfileSelection(id: id, modifications: [], additionalWritableRoots: [])
        }
        guard let rawModificationObjects = rawModifications as? [[String: Any]] else {
            throw AppServerError.invalidRequest("invalid permissions")
        }

        var modifications: [ActivePermissionProfileModification] = []
        var additionalWritableRoots: [AbsolutePath] = []
        for modificationObject in rawModificationObjects {
            guard stringParam(modificationObject["type"]) == "additionalWritableRoot",
                  let path = try strictStringParam(
                    modificationObject["path"],
                    fieldName: "permissions.modifications.path"
                  )
            else {
                throw AppServerError.invalidRequest("invalid permissions")
            }
            let absolutePath: AbsolutePath
            do {
                absolutePath = try AbsolutePath(absolutePath: path)
            } catch {
                throw AppServerError.invalidRequest("invalid permissions")
            }
            modifications.append(.additionalWritableRoot(path: absolutePath.path))
            additionalWritableRoots.append(absolutePath)
        }
        return PermissionProfileSelection(
            id: id,
            modifications: modifications,
            additionalWritableRoots: additionalWritableRoots
        )
    }

    private static func dynamicToolsParam(_ raw: Any?) throws -> [DynamicToolSpec]? {
        guard let raw, !(raw is NSNull) else {
            return nil
        }
        guard JSONSerialization.isValidJSONObject(["dynamicTools": raw]) else {
            throw AppServerError.invalidRequest("thread/start.dynamicTools is not valid JSON")
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: ["dynamicTools": raw])
            return try JSONDecoder().decode(DynamicToolsPayload.self, from: data).dynamicTools
        } catch {
            throw AppServerError.invalidRequest("thread/start.dynamicTools is invalid: \(error)")
        }
    }

    private static func sessionStartSourceParam(_ raw: Any?) throws -> HookSessionStartSource {
        guard let rawValue = try strictStringParam(raw, fieldName: "sessionStartSource") else {
            return .startup
        }
        guard let source = HookSessionStartSource(rawValue: rawValue), source != .resume else {
            throw unknownVariant(rawValue, expected: ["startup", "clear"])
        }
        return source
    }

    private static func loadRuntimeConfigForThreadStartup(
        configuration: CodexAppServerConfiguration,
        cwd: URL? = nil,
        permissionSelection: PermissionProfileSelection? = nil
    ) throws -> CodexRuntimeConfig {
        var overrides = configuration.cliConfigOverrides
        if let permissionSelection {
            overrides.rawOverrides.append("default_permissions=\(tomlQuotedString(permissionSelection.id))")
        }
        var runtimeConfig = try CodexConfigLoader.load(
            codexHome: configuration.codexHome,
            cwd: cwd,
            overrides: overrides,
            managedConfigOverrides: configuration.configLayerOverrides,
            environment: configuration.environment
        )
        if let permissionSelection, !permissionSelection.additionalWritableRoots.isEmpty {
            let cwdPath = (cwd ?? configuration.codexHome).standardizedFileURL.path
            let baseProfile = runtimeConfig.permissionProfile ?? PermissionProfile.fromLegacySandboxPolicyForCwd(
                runtimeConfig.legacySandboxPolicy(),
                cwd: cwdPath
            )
            let fileSystemPolicy = baseProfile.fileSystemSandboxPolicy.withAdditionalWritableRoots(
                permissionSelection.additionalWritableRoots,
                cwd: cwdPath
            )
            let effectiveProfile = PermissionProfile.fromRuntimePermissionsWithEnforcement(
                baseProfile.enforcement,
                fileSystem: fileSystemPolicy,
                network: baseProfile.networkSandboxPolicy
            )
            runtimeConfig.permissionProfile = effectiveProfile
            runtimeConfig.activePermissionProfile = ActivePermissionProfile(
                id: permissionSelection.id,
                modifications: permissionSelection.modifications
            )
            if let sandbox = try? fileSystemPolicy.toLegacySandboxPolicy(
                networkPolicy: effectiveProfile.networkSandboxPolicy,
                cwd: cwdPath
            ) {
                runtimeConfig.sandboxPolicy = sandbox
            }
        }
        if let message = McpRequiredStartupValidator.requiredStartupFailureMessage(
            mcpServers: runtimeConfig.mcpServers,
            environment: configuration.environment
        ) {
            throw AppServerError.internalError(message)
        }
        return runtimeConfig
    }

    private static func configuredRuntimeHookHandlers(
        configuration: CodexAppServerConfiguration,
        cwd: URL
    ) throws -> [ConfiguredHookHandler] {
        let stack = try CodexConfigLayerLoader.loadConfigLayerStack(
            codexHome: configuration.codexHome,
            cwd: cwd,
            cliOverrides: configuration.cliConfigOverrides,
            overrides: configuration.configLayerOverrides,
            environment: configuration.environment
        )
        return HookConfig.configuredHandlers(
            from: stack,
            codexHome: configuration.codexHome,
            environment: configuration.environment
        )
    }

    private static func hookPermissionMode(_ approvalPolicy: AskForApproval) -> String {
        approvalPolicy == .never ? "bypassPermissions" : "default"
    }

    private static func responseSandboxPolicy(
        for permissionProfile: PermissionProfile,
        cwd: String,
        fallback: SandboxPolicy
    ) -> SandboxPolicy {
        (try? permissionProfile.fileSystemSandboxPolicy.toLegacySandboxPolicy(
            networkPolicy: permissionProfile.networkSandboxPolicy,
            cwd: cwd
        )) ?? fallback
    }

    private static func tomlQuotedString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func persistTrustedProjectForThreadStartIfNeeded(
        params: [String: Any]?,
        cwd: URL,
        sandbox: SandboxPolicy,
        configuration: CodexAppServerConfiguration
    ) throws {
        guard stringParam(params?["cwd"]) != nil,
              threadStartPermissionsTrustProject(sandbox: sandbox)
        else {
            return
        }

        let trustTarget = GitInfoCollector.resolveRootGitProjectForTrust(cwd: cwd) ??
            GitInfoCollector.gitRepoRoot(baseDir: cwd) ??
            cwd
        let stack = try CodexConfigLayerLoader.loadConfigLayerStack(
            codexHome: configuration.codexHome,
            cliOverrides: configuration.cliConfigOverrides,
            overrides: configuration.configLayerOverrides,
            environment: configuration.environment
        )
        guard activeProjectTrustLevel(
            in: stack.effectiveConfig(),
            cwd: cwd,
            trustTarget: trustTarget
        ) == nil else {
            return
        }

        let projectKey = projectTrustKey(for: trustTarget)
        var nextConfig = stack.getUserLayer()?.config ?? .table([:])
        let originalConfig = nextConfig
        setConfigValue(
            .table(["trust_level": .string(TrustLevel.trusted.rawValue)]),
            at: ["projects", projectKey],
            mergeStrategy: .upsert,
            in: &nextConfig
        )
        guard nextConfig != originalConfig else {
            return
        }

        try CodexConfigLoader.validateForConfigWrite(
            nextConfig,
            environment: configuration.environment
        )
        let configFile = configuration.codexHome.appendingPathComponent("config.toml", isDirectory: false)
        try FileManager.default.createDirectory(at: configuration.codexHome, withIntermediateDirectories: true)
        try renderConfigToml(nextConfig).write(to: configFile, atomically: true, encoding: .utf8)
    }

    private static func activeProjectTrustLevel(
        in config: ConfigValue,
        cwd: URL,
        trustTarget: URL
    ) -> TrustLevel? {
        guard let projects = configTable(config)?["projects"].flatMap(configTable) else {
            return nil
        }
        for lookupURL in [cwd, trustTarget] {
            for key in projectTrustLookupKeys(for: lookupURL) {
                guard let project = projects[key].flatMap(configTable),
                      case let .string(rawTrustLevel)? = project["trust_level"],
                      let trustLevel = TrustLevel(rawValue: rawTrustLevel)
                else {
                    continue
                }
                return trustLevel
            }
        }
        return nil
    }

    private static func threadStartPermissionsTrustProject(sandbox: SandboxPolicy) -> Bool {
        switch sandbox {
        case .dangerFullAccess, .externalSandbox, .workspaceWrite:
            return true
        case .readOnly, .readOnlyWithNetworkAccess:
            return false
        }
    }

    private static func projectTrustKey(for url: URL) -> String {
        projectTrustLookupKeys(for: url).first ?? url.standardizedFileURL.path
    }

    private static func projectTrustLookupKeys(for url: URL) -> [String] {
        let standardized = url.standardizedFileURL
        if FileManager.default.fileExists(atPath: standardized.path) {
            let canonical = standardized.resolvingSymlinksInPath().standardizedFileURL.path
            if canonical != standardized.path {
                return [canonical, standardized.path]
            }
            return [canonical]
        }
        return [standardized.path]
    }

    fileprivate static func threadResumeResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        guard let threadID = stringParam(params?["threadId"]) else {
            throw AppServerError.invalidRequest("missing threadId")
        }

        let rolloutPath: String
        if let path = stringParam(params?["path"]) {
            rolloutPath = path
        } else {
            let conversationID: ConversationId
            do {
                conversationID = try ConversationId(string: threadID)
            } catch {
                throw AppServerError.invalidRequest("invalid thread id: \(error)")
            }
            do {
                guard let foundPath = try RolloutListing.findConversationPathByIDString(
                    codexHome: configuration.codexHome,
                    idString: conversationID.description
                ) else {
                    throw AppServerError.invalidRequest("no rollout found for conversation id \(conversationID)")
                }
                rolloutPath = foundPath
            } catch let error as AppServerError {
                throw error
            } catch {
                throw AppServerError.invalidRequest("failed to locate conversation id \(conversationID): \(error)")
            }
        }

        let item = ConversationItem(path: rolloutPath, head: [], createdAt: nil, updatedAt: nil)
        let thread = try threadObject(
            for: item,
            defaultProvider: configuration.defaultModelProvider,
            turns: buildTurnsFromRolloutEvents(at: rolloutPath)
        )
        let summary = try RolloutSummary(path: rolloutPath, defaultProvider: configuration.defaultModelProvider)
        let resumeCwd = URL(
            fileURLWithPath: stringParam(params?["cwd"]) ?? thread["cwd"] as? String ?? summary.cwd,
            isDirectory: true
        )
        let permissionSelection = try permissionProfileSelectionParam(params?["permissions"])
        let runtimeConfig = try loadRuntimeConfigForThreadStartup(
            configuration: configuration,
            cwd: resumeCwd,
            permissionSelection: permissionSelection
        )
        let requestedModel = stringParam(params?["model"])
        let requestedModelProvider = stringParam(params?["modelProvider"])
            ?? stringParam(params?["model_provider"])
        let hasModelResumeOverride = requestedModel != nil || requestedModelProvider != nil
        let model = requestedModel
            ?? (hasModelResumeOverride ? nil : summary.model)
            ?? runtimeConfig.model
            ?? ModelsManager.offlineModel(explicitModel: nil)
        let modelProvider = requestedModelProvider
            ?? (hasModelResumeOverride ? runtimeConfig.selectedModelProviderID : summary.modelProvider)
        let reasoningEffort = hasModelResumeOverride
            ? runtimeConfig.modelReasoningEffort
            : summary.reasoningEffort ?? runtimeConfig.modelReasoningEffort
        let approvalPolicy = runtimeConfig.approvalPolicy ?? .unlessTrusted
        let approvalsReviewer = try approvalsReviewerParam(params?["approvalsReviewer"])
            ?? runtimeConfig.approvalsReviewer
        let serviceTier = try resolvedServiceTier(
            serviceTierParam(params?["serviceTier"]),
            fallback: runtimeConfig.serviceTier
        )
        let baseSandbox = runtimeConfig.legacySandboxPolicy()
        let permissionProfile = runtimeConfig.permissionProfile ?? PermissionProfile.fromLegacySandboxPolicyForCwd(
            baseSandbox,
            cwd: resumeCwd.path
        )
        let sandbox = responseSandboxPolicy(
            for: permissionProfile,
            cwd: resumeCwd.path,
            fallback: baseSandbox
        )

        return [
            "thread": thread,
            "model": model,
            "modelProvider": modelProvider,
            "serviceTier": nullable(serviceTier),
            "cwd": resumeCwd.path,
            "instructionSources": [],
            "approvalPolicy": approvalPolicy.rawValue,
            "approvalsReviewer": approvalsReviewer.appServerRawValue,
            "sandbox": try jsonObject(sandbox),
            "permissionProfile": try jsonObject(permissionProfile),
            "activePermissionProfile": activePermissionProfileObject(runtimeConfig.activePermissionProfile),
            "reasoningEffort": reasoningEffort?.rawValue ?? NSNull()
        ].nullStripped(keepNulls: true)
    }

    fileprivate static func threadForkResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        guard let threadID = stringParam(params?["threadId"]) else {
            throw AppServerError.invalidRequest("missing threadId")
        }

        let sourceRolloutPath: String
        let sourceConversationID: ConversationId
        if let path = stringParam(params?["path"]) {
            sourceRolloutPath = path
            let summary = try RolloutSummary(path: path, defaultProvider: configuration.defaultModelProvider)
            do {
                sourceConversationID = try ConversationId(string: summary.id)
            } catch {
                throw AppServerError.invalidRequest("invalid source rollout conversation id: \(error)")
            }
        } else {
            do {
                sourceConversationID = try ConversationId(string: threadID)
            } catch {
                throw AppServerError.invalidRequest("invalid thread id: \(error)")
            }
            do {
                guard let foundPath = try RolloutListing.findConversationPathByIDString(
                    codexHome: configuration.codexHome,
                    idString: sourceConversationID.description
                ) else {
                    throw AppServerError.invalidRequest("no rollout found for conversation id \(sourceConversationID)")
                }
                sourceRolloutPath = foundPath
            } catch let error as AppServerError {
                throw error
            } catch {
                throw AppServerError.invalidRequest("failed to locate conversation id \(sourceConversationID): \(error)")
            }
        }

        let history: InitialHistory
        do {
            history = try RolloutRecorder.getRolloutHistory(path: URL(fileURLWithPath: sourceRolloutPath))
        } catch {
            throw AppServerError.invalidRequest(
                "failed to load rollout `\(sourceRolloutPath)` for conversation \(sourceConversationID): \(error)"
            )
        }
        let sourceSummary = try RolloutSummary(path: sourceRolloutPath, defaultProvider: configuration.defaultModelProvider)
        let requestedModel = stringParam(params?["model"])
        let requestedModelProvider = stringParam(params?["modelProvider"])
            ?? stringParam(params?["model_provider"])
        let hasModelResumeOverride = requestedModel != nil || requestedModelProvider != nil
        let cwd = URL(
            fileURLWithPath: stringParam(params?["cwd"]) ?? sourceSummary.cwd,
            isDirectory: true
        )
        let permissionSelection = try permissionProfileSelectionParam(params?["permissions"])
        let runtimeConfig = try loadRuntimeConfigForThreadStartup(
            configuration: configuration,
            cwd: cwd,
            permissionSelection: permissionSelection
        )
        let model = requestedModel
            ?? (hasModelResumeOverride ? nil : sourceSummary.model)
            ?? runtimeConfig.model
            ?? ModelsManager.offlineModel(explicitModel: nil)
        let modelProvider = requestedModelProvider
            ?? (hasModelResumeOverride ? runtimeConfig.selectedModelProviderID : sourceSummary.modelProvider)
        let reasoningEffort = hasModelResumeOverride
            ? runtimeConfig.modelReasoningEffort
            : sourceSummary.reasoningEffort ?? runtimeConfig.modelReasoningEffort
        let approvalPolicy = approvalPolicyParam(params?["approvalPolicy"])
            ?? runtimeConfig.approvalPolicy
            ?? .unlessTrusted
        let approvalsReviewer = try approvalsReviewerParam(params?["approvalsReviewer"])
            ?? runtimeConfig.approvalsReviewer
        let serviceTier = try resolvedServiceTier(
            serviceTierParam(params?["serviceTier"]),
            fallback: runtimeConfig.serviceTier
        )
        let baseSandbox = sandboxModeParam(params?["sandbox"])
            .map(sandboxPolicy(for:))
            ?? runtimeConfig.legacySandboxPolicy()
        let permissionProfile = runtimeConfig.permissionProfile ?? PermissionProfile.fromLegacySandboxPolicyForCwd(
            baseSandbox,
            cwd: cwd.path
        )
        let sandbox = responseSandboxPolicy(
            for: permissionProfile,
            cwd: cwd.path,
            fallback: baseSandbox
        )
        let threadSource = threadSourceParam(params?["threadSource"])
        let conversationID = ConversationId()
        let recorder = try RolloutRecorder.create(
            codexHome: configuration.codexHome,
            cwd: cwd,
            conversationID: conversationID,
            instructions: stringParam(params?["developerInstructions"])
                ?? stringParam(params?["developer_instructions"])
                ?? stringParam(params?["baseInstructions"])
                ?? stringParam(params?["base_instructions"]),
            source: .mcp,
            forkedFromID: sourceConversationID,
            threadSource: threadSource,
            originator: "codex_app_server",
            cliVersion: configuration.version,
            modelProvider: modelProvider,
            dynamicTools: history.dynamicTools
        )
        try recorder.recordItems(history.rolloutItems.filter { item in
            if case .sessionMeta = item {
                return false
            }
            return true
        })
        try recorder.shutdown()

        let item = ConversationItem(path: recorder.rolloutPath.path, head: [], createdAt: nil, updatedAt: nil)
        let excludeTurns = try rustDefaultBoolParam(params?["excludeTurns"], defaultValue: false)
        let includeTurns = !excludeTurns
        let thread = try threadObject(
            for: item,
            defaultProvider: configuration.defaultModelProvider,
            turns: includeTurns ? buildTurnsFromRolloutEvents(at: recorder.rolloutPath.path) : []
        )
        return [
            "thread": thread,
            "model": model,
            "modelProvider": modelProvider,
            "serviceTier": nullable(serviceTier),
            "cwd": cwd.path,
            "instructionSources": [],
            "approvalPolicy": approvalPolicy.rawValue,
            "approvalsReviewer": approvalsReviewer.appServerRawValue,
            "sandbox": try jsonObject(sandbox),
            "permissionProfile": try jsonObject(permissionProfile),
            "activePermissionProfile": activePermissionProfileObject(runtimeConfig.activePermissionProfile),
            "reasoningEffort": reasoningEffort?.rawValue ?? NSNull()
        ].nullStripped(keepNulls: true)
    }

    fileprivate static func threadReadResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration,
        loadedEphemeralThread: (String) -> [String: Any]? = { _ in nil }
    ) throws -> [String: Any] {
        guard let threadID = stringParam(params?["threadId"]) else {
            throw AppServerError.invalidRequest("missing threadId")
        }

        let conversationID: ConversationId
        do {
            conversationID = try ConversationId(string: threadID)
        } catch {
            throw AppServerError.invalidRequest("invalid thread id: \(error)")
        }

        let includeTurns = try rustDefaultBoolParam(params?["includeTurns"], defaultValue: false)

        guard let rolloutPath = try RolloutListing.findConversationPathByIDString(
            codexHome: configuration.codexHome,
            idString: conversationID.description,
            includeArchived: true
        ) else {
            if let thread = loadedEphemeralThread(conversationID.description) {
                if includeTurns {
                    throw AppServerError.invalidRequest("ephemeral threads do not support includeTurns")
                }
                return ["thread": thread]
            }
            throw AppServerError.invalidRequest("thread not loaded: \(conversationID)")
        }
        let item = ConversationItem(path: rolloutPath, head: [], createdAt: nil, updatedAt: nil)
        let thread = try threadObject(
            for: item,
            defaultProvider: configuration.defaultModelProvider,
            turns: includeTurns ? buildTurnsFromRolloutEvents(at: rolloutPath) : []
        )
        return ["thread": thread]
    }

    fileprivate static func threadTurnsListResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration,
        experimentalAPIEnabled: Bool
    ) throws -> [String: Any] {
        try requireExperimentalAPI(method: "thread/turns/list", experimentalAPIEnabled: experimentalAPIEnabled)
        guard let threadID = stringParam(params?["threadId"]) else {
            throw AppServerError.invalidRequest("missing threadId")
        }

        let conversationID: ConversationId
        do {
            conversationID = try ConversationId(string: threadID)
        } catch {
            throw AppServerError.invalidRequest("invalid thread id: \(error)")
        }

        guard let rolloutPath = try RolloutListing.findConversationPathByIDString(
            codexHome: configuration.codexHome,
            idString: conversationID.description,
            includeArchived: true
        ) else {
            throw AppServerError.invalidRequest("thread not loaded: \(conversationID)")
        }

        let itemsView = try turnItemsView(params?["itemsView"])
        let turns = try buildTurnsFromRolloutEvents(at: rolloutPath).map { turn in
            turnWithItemsView(turn, itemsView: itemsView)
        }
        let page = try paginateThreadTurns(
            turns,
            cursor: stringParam(params?["cursor"]),
            limit: try rustU32ListLimit(params?["limit"]),
            sortDirection: try threadTurnsSortDirection(params?["sortDirection"])
        )
        return [
            "data": page.turns,
            "nextCursor": page.nextCursor ?? NSNull(),
            "backwardsCursor": page.backwardsCursor ?? NSNull()
        ].nullStripped(keepNulls: true)
    }

    fileprivate static func threadRollbackResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        guard let threadID = stringParam(params?["threadId"]) else {
            throw AppServerError.invalidRequest("missing threadId")
        }
        guard let numTurnsNumber = params?["numTurns"] as? NSNumber else {
            throw AppServerError.invalidRequest("missing numTurns")
        }
        guard CFGetTypeID(numTurnsNumber) != CFBooleanGetTypeID() else {
            throw AppServerError.invalidRequest("numTurns must be an integer")
        }
        let numberType = String(cString: numTurnsNumber.objCType)
        guard ["c", "i", "s", "l", "q", "C", "I", "S", "L", "Q"].contains(numberType) else {
            throw AppServerError.invalidRequest("numTurns must be an integer")
        }
        let rawNumTurns = numTurnsNumber.int64Value
        guard rawNumTurns > 0 && rawNumTurns <= Int64(UInt32.max) else {
            throw AppServerError.invalidRequest("numTurns must be >= 1")
        }
        let numTurns = UInt32(rawNumTurns)

        let conversationID: ConversationId
        do {
            conversationID = try ConversationId(string: threadID)
        } catch {
            throw AppServerError.invalidRequest("invalid thread id: \(error)")
        }

        let rolloutPath = try rolloutPathForConversation(conversationID, configuration: configuration)
        let recorder = try RolloutRecorder.resume(path: URL(fileURLWithPath: rolloutPath))
        try recorder.recordItems([
            .eventMsg(.threadRolledBack(ThreadRolledBackEvent(numTurns: numTurns)))
        ])
        try recorder.shutdown()

        let item = ConversationItem(path: rolloutPath, head: [], createdAt: nil, updatedAt: nil)
        return [
            "thread": try threadObject(
                for: item,
                defaultProvider: configuration.defaultModelProvider,
                turns: buildTurnsFromRolloutEvents(at: rolloutPath)
            )
        ]
    }

    fileprivate static func threadUnsubscribeResult(
        params: [String: Any]?,
        isLoaded: (String) -> Bool,
        unsubscribe: (String) -> Bool
    ) throws -> [String: Any] {
        guard let threadID = stringParam(params?["threadId"]) else {
            throw AppServerError.invalidRequest("missing threadId")
        }

        let conversationID: ConversationId
        do {
            conversationID = try ConversationId(string: threadID)
        } catch {
            throw AppServerError.invalidRequest("invalid thread id: \(error)")
        }

        guard isLoaded(conversationID.description) else {
            return ["status": "notLoaded"]
        }

        if unsubscribe(conversationID.description) {
            return ["status": "unsubscribed"]
        }

        return ["status": "notSubscribed"]
    }

    fileprivate static func threadLoadedListResult(
        params: [String: Any]?,
        loadedThreadIDs: () -> [String]
    ) throws -> [String: Any] {
        let data = loadedThreadIDs().sorted()
        guard !data.isEmpty else {
            return [
                "data": [],
                "nextCursor": NSNull()
            ]
        }

        let start: Int
        if let cursor = stringParam(params?["cursor"]) {
            guard let cursorID = try? ConversationId(string: cursor) else {
                throw AppServerError.invalidRequest("invalid cursor: \(cursor)")
            }
            let normalizedCursor = cursorID.description
            if let index = data.firstIndex(of: normalizedCursor) {
                start = index + 1
            } else {
                start = data.firstIndex { $0 >= normalizedCursor } ?? data.count
            }
        } else {
            start = 0
        }

        let limit = max(try rustU32Param(params?["limit"], defaultValue: data.count), 1)
        let end = min(start + limit, data.count)
        let page = start < end ? Array(data[start..<end]) : []
        let nextCursor: Any = end < data.count ? (page.last ?? "") : NSNull()
        return [
            "data": page,
            "nextCursor": nextCursor
        ].nullStripped(keepNulls: true)
    }

    fileprivate static func resumeConversationResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        let history: InitialHistory
        if let path = stringParam(params?["path"]) {
            do {
                history = try RolloutRecorder.getRolloutHistory(path: URL(fileURLWithPath: path))
            } catch {
                throw AppServerError.invalidRequest("failed to load rollout `\(path)`: \(error)")
            }
        } else if let rawID = stringParam(params?["conversationId"]) ?? stringParam(params?["conversation_id"]) {
            let conversationID: ConversationId
            do {
                conversationID = try ConversationId(string: rawID)
            } catch {
                throw AppServerError.invalidRequest("invalid conversation id: \(error)")
            }
            let path = try rolloutPathForConversation(conversationID, configuration: configuration)
            do {
                history = try RolloutRecorder.getRolloutHistory(path: URL(fileURLWithPath: path))
            } catch {
                throw AppServerError.invalidRequest(
                    "failed to load rollout `\(path)` for conversation \(conversationID): \(error)"
                )
            }
        } else if let rawHistory = params?["history"] as? [Any], !rawHistory.isEmpty {
            history = .forked([])
        } else {
            throw AppServerError.invalidRequest("either path, conversation id or non empty history must be provided")
        }

        let runtimeConfig = try CodexConfigLoader.load(codexHome: configuration.codexHome)
        let overrides = params?["overrides"] as? [String: Any]
        let model = stringParam(overrides?["model"])
            ?? runtimeConfig.model
            ?? ModelsManager.offlineModel(explicitModel: nil)
        let modelProvider = stringParam(overrides?["modelProvider"])
            ?? stringParam(overrides?["model_provider"])
            ?? runtimeConfig.selectedModelProviderID
        let cwd = URL(
            fileURLWithPath: stringParam(overrides?["cwd"]) ?? FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let conversationID = ConversationId()
        let recorder = try RolloutRecorder.create(
            codexHome: configuration.codexHome,
            cwd: cwd,
            conversationID: conversationID,
            instructions: stringParam(overrides?["developerInstructions"])
                ?? stringParam(overrides?["developer_instructions"])
                ?? stringParam(overrides?["baseInstructions"])
                ?? stringParam(overrides?["base_instructions"]),
            source: .mcp,
            originator: "codex_app_server",
            cliVersion: configuration.version,
            modelProvider: modelProvider,
            dynamicTools: history.dynamicTools
        )
        try recorder.recordItems(history.rolloutItems.filter { item in
            if case .sessionMeta = item {
                return false
            }
            return true
        })
        try recorder.shutdown()

        let initialMessages = history.eventMessages ?? []
        return [
            "conversationId": conversationID.description,
            "model": model,
            "initialMessages": initialMessages.isEmpty ? NSNull() : try jsonObject(initialMessages),
            "rolloutPath": recorder.rolloutPath.path
        ].nullStripped(keepNulls: true)
    }

    fileprivate static func turnStartResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration,
        pendingSessionStartSource: HookSessionStartSource?,
        loadedThreadModel: String?,
        loadedThreadApprovalPolicy: AskForApproval?
    ) throws -> (
        result: [String: Any],
        hookStartedEvents: [HookStartedEvent],
        hookCompletedEvents: [HookCompletedEvent]
    ) {
        let input = v2UserInputs(params?["input"])
        try validateV2UserInputLimit(input)
        _ = try approvalsReviewerParam(params?["approvalsReviewer"])
        _ = try serviceTierParam(params?["serviceTier"])
        guard let threadID = stringParam(params?["threadId"]) else {
            throw AppServerError.invalidRequest("missing threadId")
        }
        let conversationID: ConversationId
        do {
            conversationID = try ConversationId(string: threadID)
        } catch {
            throw AppServerError.invalidRequest("invalid thread id: \(error)")
        }
        let rolloutPath = try rolloutPathForConversation(conversationID, configuration: configuration)
        try validateTurnEnvironmentSelections(params?["environments"], configuration: configuration)
        let turnID = UUID().uuidString.lowercased()
        let existing = try RolloutSummary(path: rolloutPath, defaultProvider: configuration.defaultModelProvider)
        let turnContext = try turnStartContextOverrideItem(
            params: params,
            rolloutPath: rolloutPath,
            existing: existing,
            configuration: configuration
        )
        let hookCwd = URL(
            fileURLWithPath: turnContext?.cwd ?? existing.cwd,
            isDirectory: true
        )
        let hookRuntimeConfig = try loadRuntimeConfigForThreadStartup(
            configuration: configuration,
            cwd: hookCwd,
            permissionSelection: try permissionProfileSelectionParam(params?["permissions"])
        )
        let hookModel = turnContext?.model
            ?? loadedThreadModel
            ?? existing.model
            ?? hookRuntimeConfig.model
            ?? ModelsManager.offlineModel(explicitModel: nil)
        let hookApprovalPolicy = turnContext?.approvalPolicy
            ?? loadedThreadApprovalPolicy
            ?? hookRuntimeConfig.approvalPolicy
            ?? .unlessTrusted
        let hookHandlers = try configuredRuntimeHookHandlers(
            configuration: configuration,
            cwd: hookCwd
        )
        var hookStartedEvents: [HookStartedEvent] = []
        var hookCompletedEvents: [HookCompletedEvent] = []
        var sessionStartContexts: [String] = []
        var sessionStartShouldStop = false
        if let pendingSessionStartSource {
            hookStartedEvents.append(contentsOf: HookSessionStart.preview(
                handlers: hookHandlers,
                request: try HookSessionStartRequest(
                    sessionID: ThreadId(uuid: conversationID.uuid),
                    cwd: AbsolutePath(absolutePath: hookCwd.standardizedFileURL.path),
                    model: hookModel,
                    permissionMode: hookPermissionMode(hookApprovalPolicy),
                    source: pendingSessionStartSource
                )
            ).map {
                HookStartedEvent(turnID: turnID, run: $0)
            })
            let request = try HookSessionStartRequest(
                sessionID: ThreadId(uuid: conversationID.uuid),
                cwd: AbsolutePath(absolutePath: hookCwd.standardizedFileURL.path),
                model: hookModel,
                permissionMode: hookPermissionMode(hookApprovalPolicy),
                source: pendingSessionStartSource
            )
            let outcome = try runAsyncBlocking {
                await HookSessionStart.run(
                    handlers: hookHandlers,
                    shell: HookCommandShell(),
                    request: request,
                    turnID: turnID
                )
            }
            hookCompletedEvents.append(contentsOf: outcome.hookEvents)
            sessionStartShouldStop = outcome.shouldStop
            if !outcome.shouldStop {
                sessionStartContexts = HookOutputSpiller().maybeSpillTexts(
                    threadID: ThreadId(uuid: conversationID.uuid),
                    texts: outcome.additionalContexts
                )
            }
        }
        let hookOutcome: HookUserPromptSubmitOutcome
        if input.text.isEmpty || sessionStartShouldStop {
            hookOutcome = HookUserPromptSubmitOutcome(
                hookEvents: [],
                shouldStop: false,
                stopReason: nil,
                additionalContexts: []
            )
        } else {
            hookStartedEvents.append(contentsOf: HookUserPromptSubmit.preview(handlers: hookHandlers).map {
                HookStartedEvent(turnID: turnID, run: $0)
            })
            let request = try HookUserPromptSubmitRequest(
                sessionID: ThreadId(uuid: conversationID.uuid),
                turnID: turnID,
                cwd: AbsolutePath(absolutePath: hookCwd.standardizedFileURL.path),
                model: hookModel,
                permissionMode: hookPermissionMode(hookApprovalPolicy),
                prompt: input.text
            )
            hookOutcome = try runAsyncBlocking {
                await HookUserPromptSubmit.run(
                    handlers: hookHandlers,
                    shell: HookCommandShell(),
                    request: request
                )
            }
        }
        hookCompletedEvents.append(contentsOf: hookOutcome.hookEvents)
        let spilledHookContexts = HookOutputSpiller().maybeSpillTexts(
            threadID: ThreadId(uuid: conversationID.uuid),
            texts: hookOutcome.additionalContexts
        )
        if turnContext != nil || !sessionStartContexts.isEmpty || !input.text.isEmpty || !(input.images?.isEmpty ?? true) {
            let recorder = try RolloutRecorder.resume(path: URL(fileURLWithPath: rolloutPath))
            var items: [RolloutRecordItem] = []
            if let turnContext {
                items.append(.turnContext(turnContext.withTurnID(turnID)))
            }
            items.append(contentsOf: sessionStartContexts.map { context in
                .responseItem(ResponseInputItem(userInputs: [.text(context)]).responseItem())
            })
            if !sessionStartShouldStop,
               !hookOutcome.shouldStop,
               (!input.text.isEmpty || !(input.images?.isEmpty ?? true)) {
                items.append(.eventMsg(.userMessage(UserMessageEvent(message: input.text, images: input.images))))
            }
            items.append(contentsOf: spilledHookContexts.map { context in
                .responseItem(ResponseInputItem(userInputs: [.text(context)]).responseItem())
            })
            try recorder.recordItems(items)
            try recorder.shutdown()
        }
        let turn: [String: Any] = [
            "id": turnID,
            "items": [],
            "status": "inProgress",
            "error": NSNull()
        ]
        return (
            result: ["turn": turn],
            hookStartedEvents: hookStartedEvents,
            hookCompletedEvents: hookCompletedEvents
        )
    }

    private static func turnStartContextOverrideItem(
        params: [String: Any]?,
        rolloutPath: String,
        existing: RolloutSummary? = nil,
        configuration: CodexAppServerConfiguration
    ) throws -> TurnContextItem? {
        let cwd = try optionalAbsolutePathParam(params?["cwd"], name: "cwd")
        let approvalPolicy = try turnStartApprovalPolicyParam(params?["approvalPolicy"])
        let sandboxPolicy = try commandExecSandboxPolicy(params?["sandboxPolicy"])
        let model = stringParam(params?["model"])
        let effort = try turnStartReasoningEffortParam(params?["effort"])
        let summary = try turnStartReasoningSummaryParam(params?["summary"])
        let personality = try turnStartPersonalityParam(params?["personality"])
        let outputSchema = try jsonValueParam(params?["outputSchema"], fieldName: "outputSchema")
        let collaborationMode = try turnStartCollaborationModeParam(params?["collaborationMode"])
        let permissionSelection = try permissionProfileSelectionParam(params?["permissions"])
        guard cwd != nil
            || approvalPolicy != nil
            || sandboxPolicy != nil
            || model != nil
            || effort != nil
            || summary != nil
            || personality != nil
            || outputSchema != nil
            || collaborationMode != nil
            || permissionSelection != nil
        else {
            return nil
        }

        let existing = try existing ?? RolloutSummary(path: rolloutPath, defaultProvider: configuration.defaultModelProvider)
        let contextCwd = cwd ?? existing.cwd
        let runtimeConfig = try loadRuntimeConfigForThreadStartup(
            configuration: configuration,
            cwd: URL(fileURLWithPath: contextCwd, isDirectory: true),
            permissionSelection: permissionSelection
        )
        let baseSandboxPolicy = sandboxPolicy ?? runtimeConfig.legacySandboxPolicy()
        let permissionProfile = permissionSelection == nil
            ? nil
            : runtimeConfig.permissionProfile ?? PermissionProfile.fromLegacySandboxPolicyForCwd(
                baseSandboxPolicy,
                cwd: contextCwd
            )
        let contextSandboxPolicy = permissionProfile.map {
            responseSandboxPolicy(for: $0, cwd: contextCwd, fallback: baseSandboxPolicy)
        } ?? baseSandboxPolicy
        let contextModel = collaborationMode?.settings.model ?? model ?? runtimeConfig.model
            ?? ModelsManager.offlineModel(explicitModel: nil)
        let contextEffort = collaborationMode?.settings.reasoningEffort ?? effort ?? runtimeConfig.modelReasoningEffort
        return TurnContextItem(
            cwd: contextCwd,
            approvalPolicy: approvalPolicy ?? runtimeConfig.approvalPolicy ?? .unlessTrusted,
            sandboxPolicy: contextSandboxPolicy,
            permissionProfile: permissionProfile,
            activePermissionProfile: permissionSelection == nil ? nil : runtimeConfig.activePermissionProfile,
            model: contextModel,
            personality: personality,
            collaborationMode: collaborationMode,
            effort: contextEffort,
            summary: summary ?? runtimeConfig.modelReasoningSummary ?? .auto,
            finalOutputJSONSchema: outputSchema
        )
    }

    private static func turnStartApprovalPolicyParam(_ value: Any?) throws -> AskForApproval? {
        guard let rawValue = try strictStringParam(value, fieldName: "approvalPolicy") else {
            return nil
        }
        guard let approvalPolicy = AskForApproval(rawValue: rawValue) else {
            throw unknownVariant(
                rawValue,
                expected: ["untrusted", "on-failure", "on-request", "never"]
            )
        }
        return approvalPolicy
    }

    private static func turnStartReasoningEffortParam(_ value: Any?) throws -> ReasoningEffort? {
        guard let rawValue = try strictStringParam(value, fieldName: "effort") else {
            return nil
        }
        guard let effort = ReasoningEffort(rawValue: rawValue) else {
            throw unknownVariant(rawValue, expected: ReasoningEffort.allCases.map(\.rawValue))
        }
        return effort
    }

    private static func turnStartReasoningSummaryParam(_ value: Any?) throws -> ReasoningSummary? {
        guard let rawValue = try strictStringParam(value, fieldName: "summary") else {
            return nil
        }
        guard let summary = ReasoningSummary(rawValue: rawValue) else {
            throw unknownVariant(rawValue, expected: ReasoningSummary.allCases.map(\.rawValue))
        }
        return summary
    }

    private static func turnStartPersonalityParam(_ value: Any?) throws -> Personality? {
        guard let rawValue = try strictStringParam(value, fieldName: "personality") else {
            return nil
        }
        guard let personality = Personality(rawValue: rawValue) else {
            throw unknownVariant(rawValue, expected: Personality.allCases.map(\.rawValue))
        }
        return personality
    }

    private static func turnStartCollaborationModeParam(_ value: Any?) throws -> CollaborationMode? {
        guard let value, !(value is NSNull) else {
            return nil
        }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value)
        else {
            throw AppServerError.invalidRequest("invalid value for field `collaborationMode`")
        }
        do {
            let mode = try JSONDecoder().decode(CollaborationMode.self, from: data)
            return mode.withBuiltinDeveloperInstructionsIfNeeded()
        } catch {
            throw AppServerError.invalidRequest("invalid value for field `collaborationMode`")
        }
    }

    private static func strictStringParam(_ value: Any?, fieldName: String) throws -> String? {
        guard let value, !(value is NSNull) else {
            return nil
        }
        guard let rawValue = value as? String else {
            throw AppServerError.invalidRequest("invalid value for field `\(fieldName)`")
        }
        return rawValue
    }

    private static func serviceTierParam(_ value: Any?) throws -> NullableStringPatch {
        guard let value else {
            return .absent
        }
        if value is NSNull {
            return .clear
        }
        guard let rawValue = value as? String else {
            throw AppServerError.invalidRequest("invalid value for field `serviceTier`")
        }
        return .set(normalizedServiceTier(rawValue))
    }

    private static func resolvedServiceTier(_ patch: NullableStringPatch, fallback: String?) -> String? {
        switch patch {
        case .absent:
            return fallback
        case .clear:
            return nil
        case let .set(value):
            return value
        }
    }

    private static func normalizedServiceTier(_ value: String) -> String {
        ServiceTier.fromRequestValue(value)?.requestValue ?? value
    }

    private static func unknownVariant(_ rawValue: String, expected: [String]) -> AppServerError {
        let expectedValues = expected.map { "`\($0)`" }.joined(separator: ", ")
        return .invalidRequest("unknown variant `\(rawValue)`, expected one of \(expectedValues)")
    }

    private static func jsonValueParam(_ value: Any?, fieldName: String) throws -> JSONValue? {
        guard let value else {
            return nil
        }
        do {
            return try jsonValue(fromJSONObject: value)
        } catch {
            throw AppServerError.invalidRequest("invalid value for field `\(fieldName)`")
        }
    }

    private static func jsonValue(fromJSONObject value: Any) throws -> JSONValue {
        if value is NSNull {
            return .null
        }
        if let bool = value as? Bool {
            return .bool(bool)
        }
        if let integer = value as? Int {
            return .integer(Int64(integer))
        }
        if let int64 = value as? Int64 {
            return .integer(int64)
        }
        if let double = value as? Double {
            return .double(double)
        }
        if let string = value as? String {
            return .string(string)
        }
        if let array = value as? [Any] {
            return .array(try array.map(jsonValue(fromJSONObject:)))
        }
        if let object = value as? [String: Any] {
            return .object(try object.mapValues(jsonValue(fromJSONObject:)))
        }
        throw AppServerError.invalidRequest("invalid JSON value")
    }

    fileprivate static func validateTurnEnvironmentSelections(
        _ rawEnvironments: Any?,
        configuration: CodexAppServerConfiguration
    ) throws {
        guard let rawEnvironments, !(rawEnvironments is NSNull),
              let environments = rawEnvironments as? [[String: Any]]
        else {
            return
        }

        let snapshot = try ConfiguredEnvironmentLoader.load(
            codexHome: configuration.codexHome,
            environment: configuration.environment
        )
        var seenEnvironmentIDs = Set<String>()
        for environment in environments {
            let environmentID = stringParam(environment["environment_id"]) ?? ""
            guard seenEnvironmentIDs.insert(environmentID).inserted else {
                throw AppServerError.invalidRequest("duplicate turn environment id `\(environmentID)`")
            }
            guard snapshot.environment(id: environmentID) != nil else {
                throw AppServerError.invalidRequest("unknown turn environment id `\(environmentID)`")
            }
        }
    }

    fileprivate static func requireThreadStartExperimentalFieldsAPI(
        params: [String: Any]?,
        experimentalAPIEnabled: Bool
    ) throws {
        guard !experimentalAPIEnabled else {
            return
        }
        try requireGranularApprovalPolicyExperimentalAPI(params: params, experimentalAPIEnabled: experimentalAPIEnabled)
        if let environments = params?["environments"], !(environments is NSNull) {
            throw AppServerError.invalidRequest("thread/start.environments requires experimentalApi capability")
        }
        if let dynamicTools = params?["dynamicTools"], !(dynamicTools is NSNull) {
            throw AppServerError.invalidRequest("thread/start.dynamicTools requires experimentalApi capability")
        }
        if let permissions = params?["permissions"], !(permissions is NSNull) {
            throw AppServerError.invalidRequest("thread/start.permissions requires experimentalApi capability")
        }
        if let mockExperimentalField = params?["mockExperimentalField"], !(mockExperimentalField is NSNull) {
            throw AppServerError.invalidRequest("thread/start.mockExperimentalField requires experimentalApi capability")
        }
        if try rustDefaultBoolParam(params?["experimentalRawEvents"], defaultValue: false) {
            throw AppServerError.invalidRequest("thread/start.experimentalRawEvents requires experimentalApi capability")
        }
        if try rustDefaultBoolParam(params?["persistFullHistory"], defaultValue: false) {
            throw AppServerError.invalidRequest("thread/start.persistFullHistory requires experimentalApi capability")
        }
        if try rustDefaultBoolParam(params?["persistExtendedHistory"], defaultValue: false) {
            throw AppServerError.invalidRequest("thread/start.persistFullHistory requires experimentalApi capability")
        }
    }

    fileprivate static func requireThreadStartContextOverrideCompatibility(params: [String: Any]?) throws {
        if let sandbox = params?["sandbox"], !(sandbox is NSNull),
           let permissions = params?["permissions"], !(permissions is NSNull) {
            throw AppServerError.invalidRequest("`permissions` cannot be combined with `sandbox`")
        }
    }

    fileprivate static func requireThreadResumeExperimentalFieldsAPI(
        params: [String: Any]?,
        experimentalAPIEnabled: Bool
    ) throws {
        guard !experimentalAPIEnabled else {
            return
        }
        try requireGranularApprovalPolicyExperimentalAPI(params: params, experimentalAPIEnabled: experimentalAPIEnabled)
        if let history = params?["history"], !(history is NSNull) {
            throw AppServerError.invalidRequest("thread/resume.history requires experimentalApi capability")
        }
        if let path = params?["path"], !(path is NSNull) {
            throw AppServerError.invalidRequest("thread/resume.path requires experimentalApi capability")
        }
        if let permissions = params?["permissions"], !(permissions is NSNull) {
            throw AppServerError.invalidRequest("thread/resume.permissions requires experimentalApi capability")
        }
        if try rustDefaultBoolParam(params?["excludeTurns"], defaultValue: false) {
            throw AppServerError.invalidRequest("thread/resume.excludeTurns requires experimentalApi capability")
        }
        if try rustDefaultBoolParam(params?["persistFullHistory"], defaultValue: false) {
            throw AppServerError.invalidRequest("thread/resume.persistFullHistory requires experimentalApi capability")
        }
        if try rustDefaultBoolParam(params?["persistExtendedHistory"], defaultValue: false) {
            throw AppServerError.invalidRequest("thread/resume.persistFullHistory requires experimentalApi capability")
        }
    }

    fileprivate static func requireThreadForkExperimentalFieldsAPI(
        params: [String: Any]?,
        experimentalAPIEnabled: Bool
    ) throws {
        guard !experimentalAPIEnabled else {
            return
        }
        try requireGranularApprovalPolicyExperimentalAPI(params: params, experimentalAPIEnabled: experimentalAPIEnabled)
        if let path = params?["path"], !(path is NSNull) {
            throw AppServerError.invalidRequest("thread/fork.path requires experimentalApi capability")
        }
        if let permissions = params?["permissions"], !(permissions is NSNull) {
            throw AppServerError.invalidRequest("thread/fork.permissions requires experimentalApi capability")
        }
        if try rustDefaultBoolParam(params?["excludeTurns"], defaultValue: false) {
            throw AppServerError.invalidRequest("thread/fork.excludeTurns requires experimentalApi capability")
        }
        if try rustDefaultBoolParam(params?["persistFullHistory"], defaultValue: false) {
            throw AppServerError.invalidRequest("thread/fork.persistFullHistory requires experimentalApi capability")
        }
        if try rustDefaultBoolParam(params?["persistExtendedHistory"], defaultValue: false) {
            throw AppServerError.invalidRequest("thread/fork.persistFullHistory requires experimentalApi capability")
        }
    }

    fileprivate static func persistExtendedHistoryDeprecationNoticeNotification() -> [String: Any] {
        deprecationNoticeNotification(DeprecationNoticeEvent(
            summary: persistExtendedHistoryDeprecationSummary,
            details: persistExtendedHistoryDeprecationDetails
        ))
    }

    fileprivate static func requireThreadContextOverrideCompatibility(params: [String: Any]?) throws {
        if let sandbox = params?["sandbox"], !(sandbox is NSNull),
           let permissions = params?["permissions"], !(permissions is NSNull) {
            throw AppServerError.invalidRequest("`permissions` cannot be combined with `sandbox`")
        }
    }

    fileprivate static func requireTurnStartExperimentalFieldsAPI(
        params: [String: Any]?,
        experimentalAPIEnabled: Bool
    ) throws {
        guard !experimentalAPIEnabled else {
            return
        }
        try requireGranularApprovalPolicyExperimentalAPI(params: params, experimentalAPIEnabled: experimentalAPIEnabled)
        if let metadata = params?["responsesapiClientMetadata"], !(metadata is NSNull) {
            throw AppServerError.invalidRequest("turn/start.responsesapiClientMetadata requires experimentalApi capability")
        }
        if let environments = params?["environments"], !(environments is NSNull) {
            throw AppServerError.invalidRequest("turn/start.environments requires experimentalApi capability")
        }
        if let permissions = params?["permissions"], !(permissions is NSNull) {
            throw AppServerError.invalidRequest("turn/start.permissions requires experimentalApi capability")
        }
        if let collaborationMode = params?["collaborationMode"], !(collaborationMode is NSNull) {
            throw AppServerError.invalidRequest("turn/start.collaborationMode requires experimentalApi capability")
        }
    }

    fileprivate static func requireTurnStartContextOverrideCompatibility(params: [String: Any]?) throws {
        if let sandboxPolicy = params?["sandboxPolicy"], !(sandboxPolicy is NSNull),
           let permissions = params?["permissions"], !(permissions is NSNull) {
            throw AppServerError.invalidRequest("`permissions` cannot be combined with `sandboxPolicy`")
        }
    }

    fileprivate static func requireGranularApprovalPolicyExperimentalAPI(
        params: [String: Any]?,
        experimentalAPIEnabled: Bool
    ) throws {
        guard !experimentalAPIEnabled,
              let approvalPolicy = params?["approvalPolicy"],
              !(approvalPolicy is NSNull),
              !(approvalPolicy is String),
              approvalPolicyParam(approvalPolicy) == nil
        else {
            return
        }
        throw AppServerError.invalidRequest("askForApproval.granular requires experimentalApi capability")
    }

    fileprivate static func turnSteerResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration,
        activeTurnID: String?
    ) throws -> [String: Any] {
        guard let threadID = stringParam(params?["threadId"]) else {
            throw AppServerError.invalidRequest("missing threadId")
        }
        let conversationID: ConversationId
        do {
            conversationID = try ConversationId(string: threadID)
        } catch {
            throw AppServerError.invalidRequest("invalid thread id: \(error)")
        }
        let rolloutPath = try rolloutPathForConversation(conversationID, configuration: configuration)
        guard let expectedTurnID = stringParam(params?["expectedTurnId"]) else {
            throw AppServerError.invalidRequest("missing expectedTurnId")
        }
        guard !expectedTurnID.isEmpty else {
            throw AppServerError.invalidRequest("expectedTurnId must not be empty")
        }
        let input = v2UserInputs(params?["input"])
        try validateV2UserInputLimit(input)
        guard let activeTurnID else {
            throw AppServerError.invalidRequest("no active turn to steer")
        }
        guard activeTurnID == expectedTurnID else {
            throw AppServerError.invalidRequest(
                "expected active turn id `\(expectedTurnID)` but found `\(activeTurnID)`"
            )
        }
        guard !input.text.isEmpty || !(input.images?.isEmpty ?? true) else {
            throw AppServerError.invalidRequest("input must not be empty")
        }
        let recorder = try RolloutRecorder.resume(path: URL(fileURLWithPath: rolloutPath))
        try recorder.recordItems([
            .eventMsg(.userMessage(UserMessageEvent(message: input.text, images: input.images)))
        ])
        try recorder.shutdown()
        return ["turnId": activeTurnID]
    }

    fileprivate static func requireTurnSteerResponsesAPIMetadataExperimentalAPI(
        params: [String: Any]?,
        experimentalAPIEnabled: Bool
    ) throws {
        guard !experimentalAPIEnabled,
              let metadata = params?["responsesapiClientMetadata"],
              !(metadata is NSNull)
        else {
            return
        }
        throw AppServerError.invalidRequest("turn/steer.responsesapiClientMetadata requires experimentalApi capability")
    }

    fileprivate static func requireAccountLoginStartExperimentalFieldsAPI(
        params: [String: Any]?,
        experimentalAPIEnabled: Bool
    ) throws {
        guard !experimentalAPIEnabled,
              stringParam(params?["type"]) == "chatgptAuthTokens"
        else {
            return
        }
        throw AppServerError.invalidRequest("account/login/start.chatgptAuthTokens requires experimentalApi capability")
    }

    fileprivate static func turnInterruptResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        guard let threadID = stringParam(params?["threadId"]) else {
            throw AppServerError.invalidRequest("missing threadId")
        }
        guard let turnID = stringParam(params?["turnId"]), !turnID.isEmpty else {
            throw AppServerError.invalidRequest("missing turnId")
        }
        let conversationID: ConversationId
        do {
            conversationID = try ConversationId(string: threadID)
        } catch {
            throw AppServerError.invalidRequest("invalid thread id: \(error)")
        }
        let rolloutPath = try rolloutPathForConversation(conversationID, configuration: configuration)
        let recorder = try RolloutRecorder.resume(path: URL(fileURLWithPath: rolloutPath))
        try recorder.recordItems([
            .eventMsg(.turnAborted(TurnAbortedEvent(reason: .interrupted)))
        ])
        try recorder.shutdown()
        return [:]
    }

    fileprivate static func reviewStartResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> AppServerReviewStartOutcome {
        guard let threadID = stringParam(params?["threadId"]) else {
            throw AppServerError.invalidRequest("missing threadId")
        }
        let conversationID: ConversationId
        do {
            conversationID = try ConversationId(string: threadID)
        } catch {
            throw AppServerError.invalidRequest("invalid thread id: \(error)")
        }
        let rolloutPath = try rolloutPathForConversation(conversationID, configuration: configuration)
        let summary = try RolloutSummary(path: rolloutPath, defaultProvider: configuration.defaultModelProvider)
        let review = try reviewRequestFromTarget(params?["target"])
        let delivery = stringParam(params?["delivery"]) ?? "inline"
        guard delivery == "inline" || delivery == "detached" else {
            throw AppServerError.invalidRequest("unsupported review delivery: \(delivery)")
        }

        let turnID = UUID().uuidString.lowercased()
        let turn = reviewTurn(id: turnID, displayText: review.displayText)
        let reviewThreadID: String
        var startedThread: [String: Any]?
        if delivery == "detached" {
            let reviewConversationID = ConversationId()
            let recorder = try RolloutRecorder.create(
                codexHome: configuration.codexHome,
                cwd: URL(fileURLWithPath: summary.cwd, isDirectory: true),
                conversationID: reviewConversationID,
                instructions: nil,
                source: .mcp,
                originator: "codex_app_server",
                cliVersion: configuration.version,
                modelProvider: summary.modelProvider
            )
            try recorder.recordItems([
                .eventMsg(.enteredReviewMode(review.request))
            ])
            try recorder.shutdown()
            reviewThreadID = reviewConversationID.description
            let item = ConversationItem(path: recorder.rolloutPath.path, head: [], createdAt: nil, updatedAt: nil)
            startedThread = try threadObject(for: item, defaultProvider: configuration.defaultModelProvider)
        } else {
            let recorder = try RolloutRecorder.resume(path: URL(fileURLWithPath: rolloutPath))
            try recorder.recordItems([
                .eventMsg(.enteredReviewMode(review.request))
            ])
            try recorder.shutdown()
            reviewThreadID = threadID
        }

        let result: [String: Any] = [
            "turn": turn,
            "reviewThreadId": reviewThreadID
        ]
        return AppServerReviewStartOutcome(result: result, startedThread: startedThread)
    }

    fileprivate static func threadArchiveResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> (result: [String: Any], archivedThreadIDs: [String]) {
        guard let threadID = stringParam(params?["threadId"]) else {
            throw AppServerError.invalidRequest("missing threadId")
        }
        let conversationID: ConversationId
        do {
            conversationID = try ConversationId(string: threadID)
        } catch {
            throw AppServerError.invalidRequest("invalid thread id: \(error)")
        }

        let rolloutPath: String
        do {
            rolloutPath = try rolloutPathForConversation(conversationID, configuration: configuration)
        } catch let error as AppServerError {
            throw error
        }

        let archivedPath = try archiveConversation(
            conversationID: conversationID,
            rolloutPath: rolloutPath,
            configuration: configuration
        )
        markStateThreadArchived(
            conversationID: conversationID,
            rolloutPath: archivedPath,
            configuration: configuration
        )
        var archivedThreadIDs = [conversationID.description]
        let descendantIDs = try spawnedDescendantThreadIDs(rootThreadID: conversationID, configuration: configuration)
        for descendantID in descendantIDs.reversed() {
            guard let descendantConversationID = try? ConversationId(string: descendantID.description),
                  let descendantRolloutPath = try? rolloutPathForConversation(
                    descendantConversationID,
                    configuration: configuration
                  )
            else {
                continue
            }
            do {
                let archivedDescendantPath = try archiveConversation(
                    conversationID: descendantConversationID,
                    rolloutPath: descendantRolloutPath,
                    configuration: configuration
                )
                markStateThreadArchived(
                    conversationID: descendantConversationID,
                    rolloutPath: archivedDescendantPath,
                    configuration: configuration
                )
                archivedThreadIDs.append(descendantConversationID.description)
            } catch {
                continue
            }
        }
        return ([:], archivedThreadIDs)
    }

    fileprivate static func threadUnarchiveResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        guard let threadID = stringParam(params?["threadId"]) else {
            throw AppServerError.invalidRequest("missing threadId")
        }
        let conversationID: ConversationId
        do {
            conversationID = try ConversationId(string: threadID)
        } catch {
            throw AppServerError.invalidRequest("invalid thread id: \(error)")
        }

        let rolloutPath = try unarchiveConversation(conversationID: conversationID, configuration: configuration)
        markStateThreadUnarchived(
            conversationID: conversationID,
            rolloutPath: URL(fileURLWithPath: rolloutPath, isDirectory: false),
            configuration: configuration
        )
        let item = ConversationItem(
            path: rolloutPath,
            head: [],
            createdAt: nil,
            updatedAt: modificationDate(forPath: rolloutPath).map(iso8601String)
        )
        return [
            "thread": try threadObject(for: item, defaultProvider: configuration.defaultModelProvider)
        ]
    }

    fileprivate static func listConversationsResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        let page = try RolloutListing.getConversations(
            codexHome: configuration.codexHome,
            pageSize: listLimit(params?["pageSize"]),
            cursor: stringParam(params?["cursor"]).flatMap(RolloutListing.parseCursor),
            allowedSources: interactiveSessionSources,
            modelProviders: modelProviderFilter(params?["modelProviders"], defaultProvider: configuration.defaultModelProvider),
            defaultProvider: configuration.defaultModelProvider
        )
        return [
            "items": try page.items.map { try conversationObject(for: $0, defaultProvider: configuration.defaultModelProvider) },
            "nextCursor": page.nextCursor?.token as Any
        ].nullStripped()
    }

    fileprivate static func getConversationSummaryResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        let rolloutPath: String
        if let path = stringParam(params?["rolloutPath"]) ?? stringParam(params?["rollout_path"]) {
            rolloutPath = resolvedRolloutPath(path, configuration: configuration)
        } else {
            let rawID = stringParam(params?["conversationId"]) ?? stringParam(params?["conversation_id"])
            guard let rawID else {
                throw AppServerError.invalidRequest("missing conversationId")
            }
            let conversationID: ConversationId
            do {
                conversationID = try ConversationId(string: rawID)
            } catch {
                throw AppServerError.invalidRequest("invalid conversation id: \(error)")
            }
            rolloutPath = try rolloutPathForConversation(conversationID, configuration: configuration)
        }
        return [
            "summary": try conversationObject(
                for: ConversationItem(path: rolloutPath, head: [], createdAt: nil, updatedAt: nil),
                defaultProvider: configuration.defaultModelProvider
            )
        ]
    }

    private static func resolvedRolloutPath(
        _ path: String,
        configuration: CodexAppServerConfiguration
    ) -> String {
        if (path as NSString).isAbsolutePath {
            return URL(fileURLWithPath: path).standardizedFileURL.path
        }
        return configuration.codexHome.appendingPathComponent(path).standardizedFileURL.path
    }

    fileprivate static func archiveConversationResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        let rawID = stringParam(params?["conversationId"]) ?? stringParam(params?["conversation_id"])
        guard let rawID else {
            throw AppServerError.invalidRequest("missing conversation_id")
        }
        let conversationID: ConversationId
        do {
            conversationID = try ConversationId(string: rawID)
        } catch {
            throw AppServerError.invalidRequest("invalid conversation id: \(error)")
        }
        let rawPath = stringParam(params?["rolloutPath"]) ?? stringParam(params?["rollout_path"])
        guard let rawPath else {
            throw AppServerError.invalidRequest("missing rollout_path")
        }

        _ = try archiveConversation(conversationID: conversationID, rolloutPath: rawPath, configuration: configuration)
        return [:]
    }

    fileprivate static func sendUserMessageResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        let rawID = stringParam(params?["conversationId"]) ?? stringParam(params?["conversation_id"])
        guard let rawID else {
            throw AppServerError.invalidRequest("missing conversationId")
        }
        let conversationID: ConversationId
        do {
            conversationID = try ConversationId(string: rawID)
        } catch {
            throw AppServerError.invalidRequest("invalid conversation id: \(error)")
        }
        let rolloutPath = try rolloutPathForConversation(conversationID, configuration: configuration)
        let input = v1InputItems(params?["items"])
        if !input.text.isEmpty || !(input.images?.isEmpty ?? true) {
            let recorder = try RolloutRecorder.resume(path: URL(fileURLWithPath: rolloutPath))
            try recorder.recordItems([
                .eventMsg(.userMessage(UserMessageEvent(message: input.text, images: input.images)))
            ])
            try recorder.shutdown()
        }
        return [:]
    }

    fileprivate static func interruptConversationResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        let rawID = stringParam(params?["conversationId"]) ?? stringParam(params?["conversation_id"])
        guard let rawID else {
            throw AppServerError.invalidRequest("missing conversationId")
        }
        let conversationID: ConversationId
        do {
            conversationID = try ConversationId(string: rawID)
        } catch {
            throw AppServerError.invalidRequest("invalid conversation id: \(error)")
        }
        let rolloutPath = try rolloutPathForConversation(conversationID, configuration: configuration)
        let recorder = try RolloutRecorder.resume(path: URL(fileURLWithPath: rolloutPath))
        try recorder.recordItems([
            .eventMsg(.turnAborted(TurnAbortedEvent(reason: .interrupted)))
        ])
        try recorder.shutdown()
        return [
            "abortReason": "interrupted"
        ]
    }

    fileprivate static func threadSetNameResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> (result: [String: Any], threadID: String, threadName: String) {
        guard let rawThreadID = stringParam(params?["threadId"]) else {
            throw AppServerError.invalidRequest("missing threadId")
        }
        let threadID: ConversationId
        do {
            threadID = try ConversationId(string: rawThreadID)
        } catch {
            throw AppServerError.invalidRequest("invalid thread id: \(error)")
        }
        guard let rawName = stringParam(params?["name"]) else {
            throw AppServerError.invalidRequest("missing name")
        }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw AppServerError.invalidRequest("thread name must not be empty")
        }

        _ = try rolloutPathForConversation(threadID, configuration: configuration)
        try appendThreadName(threadID: threadID, name: name, codexHome: configuration.codexHome)
        return ([:], threadID.description, name)
    }

    fileprivate static func threadMetadataUpdateResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        guard let rawThreadID = stringParam(params?["threadId"]) else {
            throw AppServerError.invalidRequest("missing threadId")
        }
        let threadID: ConversationId
        do {
            threadID = try ConversationId(string: rawThreadID)
        } catch {
            throw AppServerError.invalidRequest("invalid thread id: \(error)")
        }
        guard let gitInfo = params?["gitInfo"] as? [String: Any] else {
            throw AppServerError.invalidRequest("gitInfo must include at least one field")
        }
        let patch = try GitInfoPatch(params: gitInfo)
        guard patch.hasAnyField else {
            throw AppServerError.invalidRequest("gitInfo must include at least one field")
        }

        let rolloutPath = try rolloutPathForConversation(
            threadID,
            configuration: configuration,
            includeArchived: true
        )
        let updatedPath = try updateRolloutSessionGitInfo(rolloutPath: rolloutPath, patch: patch)
        let item = ConversationItem(path: updatedPath, head: [], createdAt: nil, updatedAt: nil)
        return [
            "thread": try threadObject(
                for: item,
                defaultProvider: configuration.defaultModelProvider,
                turns: []
            )
        ]
    }

    fileprivate static func threadGoalFeatureGateResult(
        method: String,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        let runtimeConfig = try CodexConfigLoader.load(codexHome: configuration.codexHome)
        guard runtimeConfig.features.isEnabled(.goals) else {
            throw AppServerError.invalidRequest("goals feature is disabled")
        }
        throw AppServerError.methodNotFound("\(method) is not supported yet")
    }

    fileprivate static func threadCompactStartResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        _ = try materializedThreadID(params: params, configuration: configuration)
        return [:]
    }

    fileprivate static func threadShellCommandResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        guard let rawCommand = stringParam(params?["command"]) else {
            throw AppServerError.invalidRequest("missing command")
        }
        let command = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            throw AppServerError.invalidRequest("command must not be empty")
        }
        _ = try materializedThreadID(params: params, configuration: configuration)
        return [:]
    }

    fileprivate static func threadApproveGuardianDeniedActionResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        guard let event = params?["event"] else {
            throw AppServerError.invalidRequest("missing event")
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: event)
            _ = try JSONDecoder().decode(GuardianAssessmentEvent.self, from: data)
        } catch {
            throw AppServerError.invalidRequest("invalid Guardian denial event: \(error)")
        }
        _ = try materializedThreadID(params: params, configuration: configuration)
        return [:]
    }

    fileprivate static func threadBackgroundTerminalsCleanResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration,
        experimentalAPIEnabled: Bool
    ) throws -> [String: Any] {
        guard experimentalAPIEnabled else {
            throw AppServerError.invalidRequest("thread/backgroundTerminals/clean requires experimentalApi capability")
        }
        _ = try materializedThreadID(params: params, configuration: configuration)
        return [:]
    }

    fileprivate static func threadElicitationCounterThreadID(params: [String: Any]?) throws -> String {
        guard let rawThreadID = stringParam(params?["threadId"]) else {
            throw AppServerError.invalidRequest("missing threadId")
        }
        do {
            return try ConversationId(string: rawThreadID).description
        } catch {
            throw AppServerError.invalidRequest("invalid thread id: \(error)")
        }
    }

    fileprivate static func threadElicitationCounterResult(
        method: String,
        params: [String: Any]?,
        experimentalAPIEnabled: Bool,
        update: (String) throws -> AppServerElicitationCounterResult
    ) throws -> [String: Any] {
        guard experimentalAPIEnabled else {
            throw AppServerError.invalidRequest("\(method) requires experimentalApi capability")
        }

        let threadID = try threadElicitationCounterThreadID(params: params)
        switch try update(threadID) {
        case let .success(count):
            return [
                "count": count,
                "paused": count > 0
            ]
        case .threadNotFound:
            throw AppServerError.invalidRequest("thread not found: \(threadID)")
        case .alreadyZero:
            throw AppServerError.invalidRequest("out-of-band elicitation count is already zero")
        case .overflow:
            throw AppServerError.internalError("failed to increment out-of-band elicitation counter: out-of-band elicitation count overflowed")
        }
    }

    fileprivate static func requireExperimentalAPI(method: String, experimentalAPIEnabled: Bool) throws {
        guard experimentalAPIEnabled else {
            throw AppServerError.invalidRequest("\(method) requires experimentalApi capability")
        }
    }

    fileprivate static func threadGoalSetResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration,
        experimentalAPIEnabled: Bool,
        loadedEphemeralThreadIDs: Set<String> = []
    ) throws -> (result: [String: Any], threadID: String, goal: [String: Any]) {
        try requireExperimentalAPI(method: "thread/goal/set", experimentalAPIEnabled: experimentalAPIEnabled)
        try requireGoalsFeature(configuration: configuration)
        try rejectLoadedEphemeralGoalThread(params: params, loadedEphemeralThreadIDs: loadedEphemeralThreadIDs)
        let threadID = try materializedGoalThreadID(params: params, configuration: configuration)
        let thread = try ThreadId(string: threadID)
        let stateStore = try stateStoreForThreadGoals(configuration: configuration)
        let status = try goalStatus(params?["status"])
        let objective = stringParam(params?["objective"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokenBudget = try goalTokenBudget(params: params)
        let tokenBudgetUpdate: ThreadGoalTokenBudgetUpdate = tokenBudget.wasProvided
            ? .set(tokenBudget.value.map(Int64.init))
            : .preserve

        let goal: ThreadGoal
        if let objective {
            try validateGoalObjective(objective)
            if tokenBudget.wasProvided {
                try validateGoalBudget(tokenBudget.value)
            }
            let existing = try runAsyncBlocking {
                try await stateStore.getThreadGoal(threadID: thread)
            }
            if let existing,
               existing.objective == objective,
               existing.status != .complete {
                guard let updated = try runAsyncBlocking({
                    try await stateStore.updateThreadGoal(
                        threadID: thread,
                        status: status,
                        tokenBudget: tokenBudgetUpdate
                    )
                }) else {
                    throw AppServerError.invalidRequest("cannot update goal for thread \(threadID): no goal exists")
                }
                goal = updated
            } else {
                goal = try runAsyncBlocking {
                    try await stateStore.replaceThreadGoal(
                        threadID: thread,
                        objective: objective,
                        status: status ?? .active,
                        tokenBudget: tokenBudget.value.map(Int64.init)
                    )
                }
            }
        } else {
            guard try runAsyncBlocking({
                try await stateStore.getThreadGoal(threadID: thread)
            }) != nil else {
                throw AppServerError.invalidRequest("cannot update goal for thread \(threadID): no goal exists")
            }
            if tokenBudget.wasProvided {
                try validateGoalBudget(tokenBudget.value)
            }
            guard let updated = try runAsyncBlocking({
                try await stateStore.updateThreadGoal(
                    threadID: thread,
                    status: status,
                    tokenBudget: tokenBudgetUpdate
                )
            }) else {
                throw AppServerError.invalidRequest("cannot update goal for thread \(threadID): no goal exists")
            }
            goal = updated
        }

        let goalObject = threadGoalObject(goal)
        return (["goal": goalObject], threadID, goalObject)
    }

    fileprivate static func threadGoalGetResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration,
        experimentalAPIEnabled: Bool,
        loadedEphemeralThreadIDs: Set<String> = []
    ) throws -> [String: Any] {
        try requireExperimentalAPI(method: "thread/goal/get", experimentalAPIEnabled: experimentalAPIEnabled)
        try requireGoalsFeature(configuration: configuration)
        try rejectLoadedEphemeralGoalThread(params: params, loadedEphemeralThreadIDs: loadedEphemeralThreadIDs)
        let threadID = try materializedGoalThreadID(params: params, configuration: configuration)
        let stateStore = try stateStoreForThreadGoals(configuration: configuration)
        let thread = try ThreadId(string: threadID)
        let goal = try runAsyncBlocking {
            try await stateStore.getThreadGoal(threadID: thread)
        }.map(threadGoalObject)
        return ["goal": goal ?? NSNull()]
    }

    fileprivate static func threadGoalClearResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration,
        experimentalAPIEnabled: Bool,
        loadedEphemeralThreadIDs: Set<String> = []
    ) throws -> (result: [String: Any], threadID: String, cleared: Bool) {
        try requireExperimentalAPI(method: "thread/goal/clear", experimentalAPIEnabled: experimentalAPIEnabled)
        try requireGoalsFeature(configuration: configuration)
        try rejectLoadedEphemeralGoalThread(params: params, loadedEphemeralThreadIDs: loadedEphemeralThreadIDs)
        let threadID = try materializedGoalThreadID(params: params, configuration: configuration)
        let stateStore = try stateStoreForThreadGoals(configuration: configuration)
        let thread = try ThreadId(string: threadID)
        let cleared = try runAsyncBlocking {
            try await stateStore.deleteThreadGoal(threadID: thread)
        }
        return (["cleared": cleared], threadID, cleared)
    }

    private static func stateStoreForThreadGoals(configuration: CodexAppServerConfiguration) throws -> SQLiteAgentGraphStore {
        guard let stateStore = configuration.stateStore else {
            throw AppServerError.internalError("sqlite state db unavailable for thread goals")
        }
        return stateStore
    }

    private static func spawnedDescendantThreadIDs(
        rootThreadID: ConversationId,
        configuration: CodexAppServerConfiguration
    ) throws -> [ThreadId] {
        guard let stateStore = configuration.stateStore else {
            return []
        }
        let root = try ThreadId(string: rootThreadID.description)
        do {
            let descendants = try runAsyncBlocking {
                try await stateStore.listThreadSpawnDescendants(rootThreadID: root, statusFilter: nil)
            }
            var seen = Set([root])
            var uniqueDescendants: [ThreadId] = []
            for descendant in descendants where seen.insert(descendant).inserted {
                uniqueDescendants.append(descendant)
            }
            return uniqueDescendants
        } catch {
            throw AppServerError.internalError(
                "failed to list spawned descendants for thread id \(rootThreadID): \(error)"
            )
        }
    }

    private static func threadGoalObject(_ goal: ThreadGoal) -> [String: Any] {
        return [
            "threadId": goal.threadID.description,
            "objective": goal.objective,
            "status": goal.status.rawValue,
            "tokenBudget": goal.tokenBudget.map { Int($0) } ?? NSNull(),
            "tokensUsed": Int(goal.tokensUsed),
            "timeUsedSeconds": Int(goal.timeUsedSeconds),
            "createdAt": Int(goal.createdAt),
            "updatedAt": Int(goal.updatedAt)
        ]
    }

    private static func requireGoalsFeature(configuration: CodexAppServerConfiguration) throws {
        let runtimeConfig = try CodexConfigLoader.load(codexHome: configuration.codexHome)
        guard runtimeConfig.features.isEnabled(.goals) else {
            throw AppServerError.invalidRequest("goals feature is disabled")
        }
    }

    private static func rejectLoadedEphemeralGoalThread(
        params: [String: Any]?,
        loadedEphemeralThreadIDs: Set<String>
    ) throws {
        guard let rawThreadID = stringParam(params?["threadId"]),
              let threadID = try? ConversationId(string: rawThreadID).description,
              loadedEphemeralThreadIDs.contains(threadID)
        else {
            return
        }
        throw AppServerError.invalidRequest("ephemeral thread does not support goals: \(threadID)")
    }

    private static func materializedGoalThreadID(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> String {
        try materializedThreadID(params: params, configuration: configuration)
    }

    private static func materializedThreadID(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> String {
        guard let rawThreadID = stringParam(params?["threadId"]) else {
            throw AppServerError.invalidRequest("missing threadId")
        }
        let threadID: ConversationId
        do {
            threadID = try ConversationId(string: rawThreadID)
        } catch {
            throw AppServerError.invalidRequest("invalid thread id: \(error)")
        }
        do {
            guard try RolloutListing.findConversationPathByIDString(
                codexHome: configuration.codexHome,
                idString: threadID.description
            ) != nil else {
                throw AppServerError.invalidRequest("thread not found: \(threadID)")
            }
        } catch let error as AppServerError {
            throw error
        } catch {
            throw AppServerError.internalError("failed to locate thread id \(threadID): \(error)")
        }
        return threadID.description
    }

    private struct GoalTokenBudget {
        let wasProvided: Bool
        let value: Int?
    }

    private static func goalTokenBudget(params: [String: Any]?) throws -> GoalTokenBudget {
        guard let params, params.keys.contains("tokenBudget") else {
            return GoalTokenBudget(wasProvided: false, value: nil)
        }
        let raw = params["tokenBudget"]
        if raw is NSNull {
            return GoalTokenBudget(wasProvided: true, value: nil)
        }
        guard let value = raw as? Int else {
            throw AppServerError.invalidRequest("goal budget must be an integer or null")
        }
        return GoalTokenBudget(wasProvided: true, value: value)
    }

    private static func goalStatus(_ raw: Any?) throws -> ThreadGoalStatus? {
        guard let raw else {
            return nil
        }
        guard let status = stringParam(raw) else {
            throw AppServerError.invalidRequest("invalid goal status")
        }
        switch status {
        case "active":
            return .active
        case "paused":
            return .paused
        case "budgetLimited":
            return .budgetLimited
        case "complete":
            return .complete
        default:
            throw AppServerError.invalidRequest("invalid goal status: \(status)")
        }
    }

    private static func validateGoalObjective(_ objective: String) throws {
        guard !objective.isEmpty else {
            throw AppServerError.invalidRequest("goal objective must not be empty")
        }
        guard objective.count <= 4_000 else {
            throw AppServerError.invalidRequest("goal objective must be at most 4000 characters")
        }
    }

    private static func validateGoalBudget(_ value: Int?) throws {
        if let value, value <= 0 {
            throw AppServerError.invalidRequest("goal budgets must be positive when provided")
        }
    }

    fileprivate static func threadMemoryModeSetResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration,
        experimentalAPIEnabled: Bool
    ) throws -> [String: Any] {
        try requireExperimentalAPI(method: "thread/memoryMode/set", experimentalAPIEnabled: experimentalAPIEnabled)
        guard let rawThreadID = stringParam(params?["threadId"]) else {
            throw AppServerError.invalidRequest("missing threadId")
        }
        let threadID: ConversationId
        do {
            threadID = try ConversationId(string: rawThreadID)
        } catch {
            throw AppServerError.invalidRequest("invalid thread id: \(error)")
        }
        guard let mode = stringParam(params?["mode"]) else {
            throw AppServerError.invalidRequest("missing mode")
        }
        guard mode == "enabled" || mode == "disabled" else {
            throw AppServerError.invalidRequest("invalid memory mode: \(mode)")
        }

        let rolloutPath = try rolloutPathForConversation(threadID, configuration: configuration)
        let sessionMeta = try readSessionMetaLine(rolloutPath: rolloutPath)
        guard sessionMeta.meta.id == threadID else {
            throw AppServerError.internalError(
                "failed to set thread memory mode: rollout session metadata id mismatch: expected \(threadID), found \(sessionMeta.meta.id)"
            )
        }

        let meta = sessionMeta.meta
        let updatedMeta = SessionMeta(
            id: meta.id,
            forkedFromID: meta.forkedFromID,
            timestamp: meta.timestamp,
            cwd: meta.cwd,
            originator: meta.originator,
            cliVersion: meta.cliVersion,
            instructions: meta.instructions,
            source: meta.source,
            threadSource: meta.threadSource,
            agentNickname: meta.agentNickname,
            agentRole: meta.agentRole,
            agentPath: meta.agentPath,
            modelProvider: meta.modelProvider,
            baseInstructions: meta.baseInstructions,
            dynamicTools: meta.dynamicTools,
            memoryMode: mode
        )
        let recorder = try RolloutRecorder.resume(path: URL(fileURLWithPath: rolloutPath, isDirectory: false))
        try recorder.recordItems([.sessionMeta(SessionMetaLine(meta: updatedMeta, git: nil))])
        try recorder.shutdown()
        try updateStateStoreMemoryModeIfConfigured(
            rolloutPath: rolloutPath,
            memoryMode: mode,
            configuration: configuration
        )
        return [:]
    }

    private static func updateStateStoreMemoryModeIfConfigured(
        rolloutPath: String,
        memoryMode: String,
        configuration: CodexAppServerConfiguration
    ) throws {
        guard let stateStore = configuration.stateStore else {
            return
        }
        let item = ConversationItem(path: rolloutPath, head: [], createdAt: nil, updatedAt: nil)
        let metadata = try threadMetadata(
            for: item,
            defaultProvider: configuration.defaultModelProvider,
            archivedOnly: false
        )
        try runAsyncBlocking {
            try await stateStore.upsertThread(metadata)
            _ = try await stateStore.setThreadMemoryMode(threadID: metadata.id, memoryMode: memoryMode)
        }
    }

    fileprivate static func threadInjectItemsResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        guard let rawThreadID = stringParam(params?["threadId"]) else {
            throw AppServerError.invalidRequest("missing threadId")
        }
        let threadID: ConversationId
        do {
            threadID = try ConversationId(string: rawThreadID)
        } catch {
            throw AppServerError.invalidRequest("invalid thread id: \(error)")
        }
        guard let rawItems = params?["items"] as? [Any] else {
            throw AppServerError.invalidRequest("missing items")
        }
        guard !rawItems.isEmpty else {
            throw AppServerError.invalidRequest("items must not be empty")
        }

        let items = try rawItems.enumerated().map { index, value in
            do {
                guard JSONSerialization.isValidJSONObject(value) else {
                    throw AppServerError.invalidRequest("items[\(index)] is not a valid response item: invalid JSON object")
                }
                let data = try JSONSerialization.data(withJSONObject: value)
                return try JSONDecoder().decode(ResponseItem.self, from: data)
            } catch let error as AppServerError {
                throw error
            } catch {
                throw AppServerError.invalidRequest("items[\(index)] is not a valid response item: \(error)")
            }
        }

        let rolloutPath = try rolloutPathForConversation(threadID, configuration: configuration)
        let recorder = try RolloutRecorder.resume(path: URL(fileURLWithPath: rolloutPath, isDirectory: false))
        try recorder.recordItems(items.map { .responseItem($0) })
        try recorder.shutdown()
        return [:]
    }

    fileprivate static func memoryResetResult(
        configuration: CodexAppServerConfiguration,
        experimentalAPIEnabled: Bool
    ) throws -> [String: Any] {
        try requireExperimentalAPI(method: "memory/reset", experimentalAPIEnabled: experimentalAPIEnabled)
        guard let stateStore = configuration.stateStore else {
            throw AppServerError.internalError("sqlite state db unavailable for memory reset")
        }
        do {
            try runAsyncBlocking {
                try await stateStore.clearMemoryData()
            }
        } catch {
            throw AppServerError.internalError("failed to clear memory rows in state db: \(error)")
        }
        do {
            try clearMemoryRootContents(configuration.codexHome.appendingPathComponent("memories", isDirectory: true))
            try clearMemoryRootContents(configuration.codexHome.appendingPathComponent("memories_extensions", isDirectory: true))
        } catch {
            throw AppServerError.internalError(
                "failed to clear memory directories under \(configuration.codexHome.path): \(error)"
            )
        }
        return [:]
    }

    fileprivate static func fsReadFileResult(params: [String: Any]?) throws -> [String: Any] {
        let path = try absolutePathParam(params?["path"], name: "path")
        let data = try Data(contentsOf: URL(fileURLWithPath: path, isDirectory: false))
        return [
            "dataBase64": data.base64EncodedString()
        ]
    }

    fileprivate static func fsWriteFileResult(params: [String: Any]?) throws -> [String: Any] {
        let path = try absolutePathParam(params?["path"], name: "path")
        guard let dataBase64 = stringParam(params?["dataBase64"]) else {
            throw AppServerError.invalidRequest("missing dataBase64")
        }
        let data = try decodeAppServerStandardBase64(dataBase64) { error in
            AppServerError.invalidRequest("fs/writeFile requires valid base64 dataBase64: \(error)")
        }
        do {
            try data.write(to: URL(fileURLWithPath: path, isDirectory: false))
        } catch {
            throw mapFilesystemError(error)
        }
        return [:]
    }

    fileprivate static func fsCreateDirectoryResult(params: [String: Any]?) throws -> [String: Any] {
        let path = try absolutePathParam(params?["path"], name: "path")
        let recursive = boolParam(params?["recursive"], defaultValue: true)
        do {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: path, isDirectory: true),
                withIntermediateDirectories: recursive
            )
        } catch {
            throw mapFilesystemError(error)
        }
        return [:]
    }

    fileprivate static func fsGetMetadataResult(params: [String: Any]?) throws -> [String: Any] {
        let path = try absolutePathParam(params?["path"], name: "path")
        do {
            let metadata = try filesystemMetadata(path: path)
            return [
                "isDirectory": metadata.isDirectory,
                "isFile": metadata.isFile,
                "isSymlink": metadata.isSymlink,
                "createdAtMs": metadata.createdAtMs,
                "modifiedAtMs": metadata.modifiedAtMs
            ]
        } catch {
            throw mapFilesystemError(error)
        }
    }

    fileprivate static func fsReadDirectoryResult(params: [String: Any]?) throws -> [String: Any] {
        let path = try absolutePathParam(params?["path"], name: "path")
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: path, isDirectory: true),
                includingPropertiesForKeys: nil,
                options: []
            )
            let entries = try contents.map { url in
                let metadata = try filesystemMetadata(path: url.path)
                return [
                    "fileName": url.lastPathComponent,
                    "isDirectory": metadata.isDirectory,
                    "isFile": metadata.isFile
                ]
            }
            return [
                "entries": entries
            ]
        } catch {
            throw mapFilesystemError(error)
        }
    }

    fileprivate static func fsRemoveResult(params: [String: Any]?) throws -> [String: Any] {
        let path = try absolutePathParam(params?["path"], name: "path")
        let recursive = boolParam(params?["recursive"], defaultValue: true)
        let force = boolParam(params?["force"], defaultValue: true)
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) || isSymlink(path: path) else {
            if force {
                return [:]
            }
            throw AppServerError.internalError("No such file or directory")
        }
        do {
            if !recursive, isDirectory(path: path) {
                throw AppServerError.invalidRequest("Directory not empty")
            }
            try FileManager.default.removeItem(at: url)
        } catch let error as AppServerError {
            throw error
        } catch {
            throw mapFilesystemError(error)
        }
        return [:]
    }

    fileprivate static func fsCopyResult(params: [String: Any]?) throws -> [String: Any] {
        let sourcePath = try absolutePathParam(params?["sourcePath"], name: "sourcePath")
        let destinationPath = try absolutePathParam(params?["destinationPath"], name: "destinationPath")
        let recursive = boolParam(params?["recursive"], defaultValue: false)
        do {
            try copyFilesystemItem(
                sourcePath: sourcePath,
                destinationPath: destinationPath,
                recursive: recursive,
                topLevel: true
            )
        } catch let error as AppServerError {
            throw error
        } catch {
            throw mapFilesystemError(error)
        }
        return [:]
    }

    fileprivate static func fsWatchParams(_ params: [String: Any]?) throws -> (watchID: String, path: String) {
        let watchID = try rustRequiredStringParam(params?["watchId"], field: "watchId")
        let path = try rustRequiredAbsolutePathParam(params?["path"], field: "path")
        return (watchID, path)
    }

    fileprivate static func fsUnwatchParams(_ params: [String: Any]?) throws -> String {
        try rustRequiredStringParam(params?["watchId"], field: "watchId")
    }

    fileprivate static func fsChangedNotification(watchID: String, changedPaths: [String]) -> [String: Any] {
        [
            "method": "fs/changed",
            "params": [
                "watchId": watchID,
                "changedPaths": changedPaths
            ]
        ]
    }

    fileprivate static func appListResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration,
        runtimeFeatureEnablement: [String: Bool] = [:],
        loadedThreadAppsFeatureEnabled: ((String) throws -> Bool)? = nil,
        cachedApps: [[String: Any]]? = nil,
        cacheAppList: (([[String: Any]]) -> Void)? = nil
    ) throws -> [String: Any] {
        let forcedAppsFeatureEnabled: Bool?
        if let threadID = stringParam(params?["threadId"]) {
            do {
                _ = try ConversationId(string: threadID)
            } catch {
                throw AppServerError.invalidRequest("invalid thread id: \(error)")
            }
            guard let loadedThreadAppsFeatureEnabled else {
                throw AppServerError.invalidRequest("thread not found: \(threadID)")
            }
            forcedAppsFeatureEnabled = try loadedThreadAppsFeatureEnabled(threadID)
        } else {
            forcedAppsFeatureEnabled = nil
        }
        let forceRefetch = try rustBoolParam(params?["forceRefetch"], defaultValue: false)
        if let cachedApps {
            return try appListPage(apps: cachedApps, params: params)
        }
        let apps = try appList(
            configuration: configuration,
            runtimeFeatureEnablement: runtimeFeatureEnablement,
            forcedAppsFeatureEnabled: forcedAppsFeatureEnabled,
            failOnRemoteConnectorLoadFailure: forceRefetch
        )
        cacheAppList?(apps)
        return try appListPage(apps: apps, params: params)
    }

    private static func appListPage(apps: [[String: Any]], params: [String: Any]?) throws -> [String: Any] {
        let total = apps.count
        var start = 0
        if let cursor = stringParam(params?["cursor"]) {
            guard let parsedStart = Int(cursor), parsedStart >= 0 else {
                throw AppServerError.invalidRequest("invalid cursor: \(cursor)")
            }
            start = parsedStart
            guard start <= total else {
                throw AppServerError.invalidRequest("cursor \(start) exceeds total apps \(total)")
            }
        }
        let limit = try rustU32PaginationLimit(params?["limit"], total: total)
        let end = min(total, start + limit)
        return [
            "data": Array(apps[start..<end]),
            "nextCursor": end < total ? String(end) : NSNull()
        ]
    }

    private static func appList(
        configuration: CodexAppServerConfiguration,
        runtimeFeatureEnablement: [String: Bool] = [:],
        forcedAppsFeatureEnabled: Bool? = nil,
        failOnRemoteConnectorLoadFailure: Bool = false
    ) throws -> [[String: Any]] {
        let configFile = configuration.codexHome.appendingPathComponent("config.toml", isDirectory: false)
        let stack = try? CodexConfigLayerLoader.loadConfigLayerStack(
            codexHome: configuration.codexHome,
            cliOverrides: configuration.cliConfigOverrides,
            overrides: configuration.configLayerOverrides,
            environment: configuration.environment,
            systemConfigFile: nil
        )
        let loadedConfig = try stack?.effectiveConfig() ?? (CodexConfigLayerLoader.readConfig(from: configFile) ?? .table([:]))
        let config = effectiveConfig(loadedConfig, applyingRuntimeFeatureEnablement: runtimeFeatureEnablement)
        var appsByID: [String: [String: Any]] = [:]

        var runtimeConfigForApps = try? CodexConfigLoader.load(
            codexHome: configuration.codexHome,
            systemConfigFile: nil,
            environment: configuration.environment
        )
        if var runtimeConfig = runtimeConfigForApps {
            applyRuntimeFeatureEnablement(
                runtimeFeatureEnablement,
                to: &runtimeConfig.features,
                protectedFeatureKeys: protectedFeatureKeys(in: loadedConfig)
            )
            if let forcedAppsFeatureEnabled {
                runtimeConfig.features.set(.apps, enabled: forcedAppsFeatureEnabled)
                runtimeConfig.features.normalizeDependencies()
            }
            runtimeConfigForApps = runtimeConfig
        }

        if let runtimeConfig = runtimeConfigForApps,
           !runtimeConfig.features.isEnabled(.apps) {
            return []
        }

        if let runtimeConfig = runtimeConfigForApps,
           runtimeConfig.features.isEnabled(.apps),
           let auth = try? currentAuth(configuration: configuration),
           case .chatGPT = auth.kind {
            for app in try connectorDirectoryApps(
                runtimeConfig: runtimeConfig,
                configuration: configuration,
                auth: auth,
                failOnLoadFailure: failOnRemoteConnectorLoadFailure
            ) {
                guard let id = app["id"] as? String else {
                    continue
                }
                appsByID[id] = appInfoByMergingConnectorAppInfo(existing: appsByID[id], incoming: app)
            }
        }

        for app in try localPluginAppList(configuration: configuration, config: config) {
            guard let id = app["id"] as? String else {
                continue
            }
            appsByID[id] = appInfoByMergingConnectorAppInfo(
                existing: appsByID[id],
                incoming: app,
                recomputeInstallURLOnNameMerge: false
            )
        }

        if let runtimeConfig = runtimeConfigForApps {
            let auth = try? currentAuth(configuration: configuration)
            let usesChatGPTBackend: Bool
            if case .chatGPT = auth?.kind {
                usesChatGPTBackend = true
            } else {
                usesChatGPTBackend = false
            }
            if runtimeConfig.features.isEnabled(.apps),
               let accessibleConnectors = try configuration.accessibleConnectorProvider(
                   runtimeConfig,
                   usesChatGPTBackend
               ) {
                let filteredConnectors = filterDisallowedConnectors(
                    accessibleConnectors,
                    originatorValue: configuration.originator
                )
                for app in appInfosForAccessibleConnectors(filteredConnectors) {
                    guard let id = app["id"] as? String else {
                        continue
                    }
                    appsByID[id] = appInfoByMergingConnectorAppInfo(
                        existing: appsByID[id],
                        incoming: app,
                        recomputeInstallURLOnNameMerge: false
                    )
                }
            }
        }

        return sortedAppInfos(applyAppEnabledState(
            to: Array(appsByID.values),
            config: config,
            requirements: stack?.requirementsToml
        ))
    }

    private static func localPluginAppList(
        configuration: CodexAppServerConfiguration,
        config: ConfigValue? = nil
    ) throws -> [[String: Any]] {
        let configFile = configuration.codexHome.appendingPathComponent("config.toml", isDirectory: false)
        let config = try config ?? (CodexConfigLayerLoader.readConfig(from: configFile) ?? .table([:]))
        let roots = localMarketplaceDiscoveryRoots(cwds: [], codexHome: configuration.codexHome, config: config)
        let manifestPaths = localMarketplaceManifestPaths(from: roots)
        var appsByID: [String: [String: Any]] = [:]

        for manifestPath in manifestPaths {
            let marketplaceRoot = try marketplaceRoot(forManifestPath: manifestPath)
            let data = try Data(contentsOf: manifestPath)
            let object = try marketplaceManifestObject(data: data, manifestPath: manifestPath)
            guard let marketplaceName = object["name"] as? String,
                  let plugins = object["plugins"] as? [[String: Any]]
            else {
                continue
            }
            for plugin in plugins {
                guard let pluginName = plugin["name"] as? String,
                      configuredPluginEnabled(id: "\(pluginName)@\(marketplaceName)", in: config),
                      let source = marketplacePluginSource(plugin["source"], marketplaceRoot: marketplaceRoot)
                else {
                    continue
                }
                let root: URL?
                switch source {
                case .local(let sourcePath):
                    root = sourcePath
                case .git:
                    root = activeLocalPluginRoot(id: "\(pluginName)@\(marketplaceName)", codexHome: configuration.codexHome)
                }
                guard let root else {
                    continue
                }
                let manifest = localPluginManifest(root: root)
                for app in localPluginApps(root: root, manifest: manifest) {
                    guard let id = app["id"] as? String else {
                        continue
                    }
                    appsByID[id] = appInfoForPluginApp(app, config: config)
                }
            }
        }

        return sortedAppInfos(Array(appsByID.values))
    }

    private static func appInfoForPluginApp(_ app: [String: Any], config: ConfigValue) -> [String: Any] {
        let id = app["id"] as? String ?? ""
        let name = app["name"] as? String ?? id
        return [
            "id": id,
            "name": name,
            "description": app["description"] as Any? ?? NSNull(),
            "logoUrl": NSNull(),
            "logoUrlDark": NSNull(),
            "distributionChannel": NSNull(),
            "branding": NSNull(),
            "appMetadata": NSNull(),
            "labels": NSNull(),
            "installUrl": stringParam(app["installUrl"]) ?? connectorInstallURL(name: name, connectorID: id),
            "isAccessible": false,
            "isEnabled": configuredAppEnabled(id: id, in: config),
            "pluginDisplayNames": []
        ].nullStripped(keepNulls: true)
    }

    private static func appInfosForAccessibleConnectors(
        _ connectors: [DiscoverableConnectorInfo]
    ) -> [[String: Any]] {
        connectors.compactMap { connector in
            let id = connector.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else {
                return nil
            }
            let name = normalizeConnectorName(connector.name, connectorID: id)
            return [
                "id": id,
                "name": name,
                "description": connector.description as Any? ?? NSNull(),
                "logoUrl": NSNull(),
                "logoUrlDark": NSNull(),
                "distributionChannel": NSNull(),
                "branding": NSNull(),
                "appMetadata": NSNull(),
                "labels": NSNull(),
                "installUrl": connector.installURL ?? connectorInstallURL(name: name, connectorID: id),
                "isAccessible": connector.isAccessible,
                "isEnabled": connector.isEnabled,
                "pluginDisplayNames": Array(Set(connector.pluginDisplayNames)).sorted()
            ].nullStripped(keepNulls: true)
        }
    }

    private static func sortedAppInfos(_ apps: [[String: Any]]) -> [[String: Any]] {
        apps.sorted {
            let leftAccessible = $0["isAccessible"] as? Bool ?? false
            let rightAccessible = $1["isAccessible"] as? Bool ?? false
            if leftAccessible != rightAccessible {
                return leftAccessible && !rightAccessible
            }
            let leftName = $0["name"] as? String ?? $0["id"] as? String ?? ""
            let rightName = $1["name"] as? String ?? $1["id"] as? String ?? ""
            if leftName != rightName {
                return leftName < rightName
            }
            return ($0["id"] as? String ?? "") < ($1["id"] as? String ?? "")
        }
    }

    private static func applyAppEnabledState(
        to apps: [[String: Any]],
        config: ConfigValue,
        requirements: ConfigRequirementsToml?
    ) -> [[String: Any]] {
        apps.map { app in
            guard let id = app["id"] as? String else {
                return app
            }
            var updated = app
            updated["isEnabled"] = configuredAppEnabled(id: id, in: config, requirements: requirements)
            return updated
        }
    }

    private static func configuredAppEnabled(
        id: String,
        in config: ConfigValue,
        requirements: ConfigRequirementsToml? = nil
    ) -> Bool {
        let root = configTable(config)
        let apps = root?["apps"].flatMap(configTable)
        let appEntry = apps?[id].flatMap(configTable)
        let defaultEntry = apps?["_default"].flatMap(configTable)
        var enabled = appEntry.flatMap { boolConfig($0, "enabled") }
            ?? defaultEntry.flatMap { boolConfig($0, "enabled") }
            ?? true
        if requirements?.apps?.apps[id]?.enabled == false {
            enabled = false
        }
        return enabled
    }

    private static func connectorInstallURL(name: String, connectorID: String) -> String {
        "https://chatgpt.com/apps/\(connectorNameSlug(name))/\(connectorID)"
    }

    private static func connectorNameSlug(_ value: String) -> String {
        var slug = ""
        for scalar in value.unicodeScalars {
            if scalar.isASCII && CharacterSet.alphanumerics.contains(scalar) {
                slug.unicodeScalars.append(UnicodeScalar(String(scalar).lowercased())!)
            } else {
                slug.append("-")
            }
        }
        let trimmed = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "app" : trimmed
    }

    fileprivate static func pluginListResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration,
        cachedFeaturedPluginIDs: [String]? = nil,
        cacheFeaturedPluginIDs: (([String]) -> Void)? = nil
    ) throws -> [String: Any] {
        let cwds = try rustStringArrayParam(params?["cwds"]) ?? []
        for cwd in cwds {
            guard URL(fileURLWithPath: cwd, isDirectory: true).path == cwd,
                  cwd.hasPrefix("/")
            else {
                throw AppServerError.invalidRequest("Invalid request: AbsolutePathBuf deserialized without a base path")
            }
        }
        let marketplaceKinds = try rustStringArrayParam(params?["marketplaceKinds"])
        if let kinds = marketplaceKinds {
            let validKinds: Set<String> = ["local", "workspace-directory", "shared-with-me"]
            for kind in kinds where !validKinds.contains(kind) {
                throw AppServerError.invalidParams("unknown variant `\(kind)`, expected one of `local`, `workspace-directory`, `shared-with-me`")
            }
        }
        let empty: [String: Any] = [
            "marketplaces": [],
            "marketplaceLoadErrors": [],
            "featuredPluginIds": []
        ]
        let runtimeConfig: CodexRuntimeConfig
        do {
            runtimeConfig = try CodexConfigLoader.load(
                codexHome: configuration.codexHome,
                systemConfigFile: nil,
                environment: configuration.environment
            )
        } catch {
            throw AppServerError.internalError("failed to reload config: \(error)")
        }
        guard runtimeConfig.features.isEnabled(.plugins) else {
            return empty
        }

        let kinds = marketplaceKinds ?? ["local"]
        var result = kinds.contains("local")
            ? try localPluginListResult(cwds: cwds, configuration: configuration)
            : empty
        let marketplaces = result["marketplaces"] as? [[String: Any]] ?? []
        let includeDefaultRemote = params?["marketplaceKinds"] == nil && runtimeConfig.features.isEnabled(.remotePlugin)
        let includeWorkspaceDirectory = kinds.contains("workspace-directory")
        let includeSharedWithMe = kinds.contains("shared-with-me")
        if includeDefaultRemote || includeWorkspaceDirectory || includeSharedWithMe {
            let remoteMarketplaces = remotePluginMarketplaces(
                includeGlobal: includeDefaultRemote,
                includeWorkspaceDirectory: includeWorkspaceDirectory,
                includeSharedWithMe: includeSharedWithMe,
                runtimeConfig: runtimeConfig,
                configuration: configuration
            )
            if !remoteMarketplaces.isEmpty {
                result["marketplaces"] = mergeRemotePluginMarketplaces(
                    local: marketplaces,
                    remote: remoteMarketplaces
                )
            }
        }
        let updatedMarketplaces = result["marketplaces"] as? [[String: Any]] ?? []
        result["featuredPluginIds"] = featuredPluginIDs(
            for: updatedMarketplaces,
            runtimeConfig: runtimeConfig,
            configuration: configuration,
            cachedFeaturedPluginIDs: cachedFeaturedPluginIDs,
            cacheFeaturedPluginIDs: cacheFeaturedPluginIDs
        )
        return result
    }

    private static func localPluginListResult(
        cwds: [String],
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        let configFile = configuration.codexHome.appendingPathComponent("config.toml", isDirectory: false)
        let config = try CodexConfigLayerLoader.readConfig(from: configFile) ?? .table([:])
        let roots = localMarketplaceDiscoveryRoots(
            cwds: cwds.map { URL(fileURLWithPath: $0, isDirectory: true) },
            codexHome: configuration.codexHome,
            config: config
        )
        let manifestPaths = localMarketplaceManifestPaths(from: roots)
        var marketplaces: [[String: Any]] = []
        var loadErrors: [[String: Any]] = []

        for manifestPath in manifestPaths {
            do {
                marketplaces.append(try pluginMarketplaceEntry(
                    manifestPath: manifestPath,
                    config: config,
                    codexHome: configuration.codexHome
                ))
            } catch {
                loadErrors.append([
                    "marketplacePath": manifestPath.path,
                    "message": (error as? AppServerError)?.description ?? error.localizedDescription
                ])
            }
        }

        return [
            "marketplaces": marketplaces,
            "marketplaceLoadErrors": loadErrors,
            "featuredPluginIds": []
        ]
    }

    private static func mergeRemotePluginMarketplaces(
        local marketplaces: [[String: Any]],
        remote remoteMarketplaces: [[String: Any]]
    ) -> [[String: Any]] {
        var merged = marketplaces
        for remoteMarketplace in remoteMarketplaces {
            guard let name = remoteMarketplace["name"] as? String else {
                continue
            }
            if let index = merged.firstIndex(where: { $0["name"] as? String == name }) {
                merged[index] = remoteMarketplace
            } else {
                merged.append(remoteMarketplace)
            }
        }
        return merged
    }

    private static func remotePluginMarketplaces(
        includeGlobal: Bool,
        includeWorkspaceDirectory: Bool,
        includeSharedWithMe: Bool,
        runtimeConfig: CodexRuntimeConfig,
        configuration: CodexAppServerConfiguration
    ) -> [[String: Any]] {
        guard let auth = try? currentAuth(configuration: configuration),
              case .chatGPT = auth.kind
        else {
            return []
        }

        let workspaceInstalled: [[String: Any]]?
        if includeWorkspaceDirectory || includeSharedWithMe {
            workspaceInstalled = remotePluginPages(
                path: "/ps/plugins/installed",
                queryItems: [URLQueryItem(name: "scope", value: "WORKSPACE")],
                runtimeConfig: runtimeConfig,
                configuration: configuration,
                auth: auth
            )
            guard workspaceInstalled != nil else {
                return []
            }
        } else {
            workspaceInstalled = nil
        }

        var marketplaces: [[String: Any]] = []
        if includeGlobal {
            guard let directory = remotePluginPages(
                path: "/ps/plugins/list",
                queryItems: [
                    URLQueryItem(name: "scope", value: "GLOBAL"),
                    URLQueryItem(name: "limit", value: "200")
                ],
                runtimeConfig: runtimeConfig,
                configuration: configuration,
                auth: auth
            ),
                  let installed = remotePluginPages(
                    path: "/ps/plugins/installed",
                    queryItems: [URLQueryItem(name: "scope", value: "GLOBAL")],
                    runtimeConfig: runtimeConfig,
                    configuration: configuration,
                    auth: auth
                  )
            else {
                return []
            }
            if let marketplace = remotePluginMarketplace(
                name: "chatgpt-global",
                displayName: "ChatGPT Plugins",
                directoryPlugins: directory,
                installedPlugins: installed,
                includeInstalledOnly: true
            ) {
                marketplaces.append(marketplace)
            }
        }
        if includeWorkspaceDirectory {
            guard let directory = remotePluginPages(
                path: "/ps/plugins/list",
                queryItems: [
                    URLQueryItem(name: "scope", value: "WORKSPACE"),
                    URLQueryItem(name: "limit", value: "200")
                ],
                runtimeConfig: runtimeConfig,
                configuration: configuration,
                auth: auth
            ) else {
                return []
            }
            if let marketplace = remotePluginMarketplace(
                name: "workspace-directory",
                displayName: "Workspace Directory",
                directoryPlugins: directory,
                installedPlugins: workspaceInstalled ?? [],
                includeInstalledOnly: false
            ) {
                marketplaces.append(marketplace)
            }
        }
        if includeSharedWithMe {
            guard let directory = remotePluginPages(
                path: "/ps/plugins/workspace/shared",
                queryItems: [URLQueryItem(name: "limit", value: "200")],
                runtimeConfig: runtimeConfig,
                configuration: configuration,
                auth: auth
            ) else {
                return []
            }
            if let marketplace = remotePluginMarketplace(
                name: "shared-with-me",
                displayName: "Shared with me",
                directoryPlugins: directory,
                installedPlugins: workspaceInstalled ?? [],
                includeInstalledOnly: false
            ) {
                marketplaces.append(marketplace)
            }
        }
        return marketplaces
    }

    private static func remotePluginPages(
        path: String,
        queryItems: [URLQueryItem],
        runtimeConfig: CodexRuntimeConfig,
        configuration: CodexAppServerConfiguration,
        auth: AppServerAuth
    ) -> [[String: Any]]? {
        var plugins: [[String: Any]] = []
        var pageToken: String?
        repeat {
            var pageQueryItems = queryItems
            if let pageToken {
                pageQueryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            guard let page = remotePluginPage(
                path: path,
                queryItems: pageQueryItems,
                runtimeConfig: runtimeConfig,
                configuration: configuration,
                auth: auth
            ) else {
                return nil
            }
            plugins.append(contentsOf: page.plugins)
            pageToken = page.nextPageToken
        } while pageToken != nil
        return plugins
    }

    private static func remotePluginPage(
        path: String,
        queryItems: [URLQueryItem],
        runtimeConfig: CodexRuntimeConfig,
        configuration: CodexAppServerConfiguration,
        auth: AppServerAuth
    ) -> (plugins: [[String: Any]], nextPageToken: String?)? {
        let normalizedBaseURL = AccountBackendEndpoint.normalizedBaseURL(runtimeConfig.chatgptBaseURL)
        guard var components = URLComponents(string: normalizedBaseURL + path) else {
            return nil
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(auth.token)", forHTTPHeaderField: "Authorization")
        if let accountID = auth.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "chatgpt-account-id")
        }
        guard let response = try? configuration.pluginHTTPTransport(request),
              (200..<300).contains(response.statusCode),
              let object = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any]
        else {
            return nil
        }
        let pagination = object["pagination"] as? [String: Any]
        return (
            plugins: object["plugins"] as? [[String: Any]] ?? [],
            nextPageToken: pagination?["next_page_token"] as? String
        )
    }

    private static func remotePluginPagesOrThrow(
        path: String,
        queryItems: [URLQueryItem],
        runtimeConfig: CodexRuntimeConfig,
        configuration: CodexAppServerConfiguration,
        auth: AppServerAuth,
        failurePrefix: String
    ) throws -> [[String: Any]] {
        var plugins: [[String: Any]] = []
        var pageToken: String?
        repeat {
            var pageQueryItems = queryItems
            if let pageToken {
                pageQueryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            let object = try remotePluginObject(
                path: path,
                queryItems: pageQueryItems,
                runtimeConfig: runtimeConfig,
                configuration: configuration,
                auth: auth,
                failurePrefix: failurePrefix
            )
            plugins.append(contentsOf: object["plugins"] as? [[String: Any]] ?? [])
            let pagination = object["pagination"] as? [String: Any]
            pageToken = pagination?["next_page_token"] as? String
        } while pageToken != nil
        return plugins
    }

    private static func remotePluginObject(
        path: String,
        queryItems: [URLQueryItem],
        runtimeConfig: CodexRuntimeConfig,
        configuration: CodexAppServerConfiguration,
        auth: AppServerAuth,
        failurePrefix: String,
        method: String = "GET",
        bodyObject: Any? = nil
    ) throws -> [String: Any] {
        let normalizedBaseURL = AccountBackendEndpoint.normalizedBaseURL(runtimeConfig.chatgptBaseURL)
        guard var components = URLComponents(string: normalizedBaseURL + path) else {
            throw AppServerError.invalidRequest("\(failurePrefix): invalid remote plugin catalog base URL")
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw AppServerError.invalidRequest("\(failurePrefix): invalid remote plugin catalog base URL path")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(auth.token)", forHTTPHeaderField: "Authorization")
        if let accountID = auth.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "chatgpt-account-id")
        }
        if let bodyObject {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: bodyObject)
        }
        let response: URLSessionTransportResponse
        do {
            response = try configuration.pluginHTTPTransport(request)
        } catch {
            throw AppServerError.invalidRequest(
                "\(failurePrefix): failed to send remote plugin catalog request to \(url.absoluteString): \(error)"
            )
        }
        guard (200..<300).contains(response.statusCode) else {
            let body = String(data: response.body, encoding: .utf8) ?? ""
            throw AppServerError.invalidRequest(
                "\(failurePrefix): remote plugin catalog request to \(url.absoluteString) failed with status \(response.statusCode): \(body)"
            )
        }
        do {
            guard let object = try JSONSerialization.jsonObject(with: response.body) as? [String: Any] else {
                throw AppServerError.invalidRequest("\(failurePrefix): failed to parse remote plugin catalog response from \(url.absoluteString)")
            }
            return object
        } catch let error as AppServerError {
            throw error
        } catch {
            throw AppServerError.invalidRequest(
                "\(failurePrefix): failed to parse remote plugin catalog response from \(url.absoluteString): \(error)"
            )
        }
    }

    private static func remotePluginEmptyResponseRequest(
        path: String,
        runtimeConfig: CodexRuntimeConfig,
        configuration: CodexAppServerConfiguration,
        auth: AppServerAuth,
        failurePrefix: String,
        method: String
    ) throws {
        let normalizedBaseURL = AccountBackendEndpoint.normalizedBaseURL(runtimeConfig.chatgptBaseURL)
        guard let url = URL(string: normalizedBaseURL + path) else {
            throw AppServerError.invalidRequest("\(failurePrefix): invalid remote plugin catalog base URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(auth.token)", forHTTPHeaderField: "Authorization")
        if let accountID = auth.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "chatgpt-account-id")
        }
        let response: URLSessionTransportResponse
        do {
            response = try configuration.pluginHTTPTransport(request)
        } catch {
            throw AppServerError.invalidRequest(
                "\(failurePrefix): failed to send remote plugin catalog request to \(url.absoluteString): \(error)"
            )
        }
        guard (200..<300).contains(response.statusCode) else {
            let body = String(data: response.body, encoding: .utf8) ?? ""
            throw AppServerError.invalidRequest(
                "\(failurePrefix): remote plugin catalog request to \(url.absoluteString) failed with status \(response.statusCode): \(body)"
            )
        }
    }

    private static func remotePluginMarketplace(
        name: String,
        displayName: String,
        directoryPlugins: [[String: Any]],
        installedPlugins: [[String: Any]],
        includeInstalledOnly: Bool
    ) -> [String: Any]? {
        let directoryByID = remotePluginsByID(directoryPlugins)
        let installedByID = remotePluginsByID(installedPlugins)
        let ids = Set(directoryByID.keys)
            .union(includeInstalledOnly ? Set(installedByID.keys) : [])
            .sorted()
        guard !ids.isEmpty else {
            return nil
        }
        let plugins = ids.compactMap { id -> [String: Any]? in
            let plugin = directoryByID[id] ?? installedByID[id]
            guard let plugin else {
                return nil
            }
            return remotePluginSummary(plugin, installed: installedByID[id])
        }
        .sorted { left, right in
            let leftDisplay = remotePluginDisplayName(left)
            let rightDisplay = remotePluginDisplayName(right)
            let folded = leftDisplay.lowercased().compare(rightDisplay.lowercased())
            if folded != .orderedSame {
                return folded == .orderedAscending
            }
            if leftDisplay != rightDisplay {
                return leftDisplay < rightDisplay
            }
            return (left["id"] as? String ?? "") < (right["id"] as? String ?? "")
        }
        return [
            "name": name,
            "path": NSNull(),
            "interface": ["displayName": displayName],
            "plugins": plugins
        ].nullStripped(keepNulls: true)
    }

    private static func remotePluginsByID(_ plugins: [[String: Any]]) -> [String: [String: Any]] {
        plugins.reduce(into: [:]) { result, plugin in
            guard let id = plugin["id"] as? String else {
                return
            }
            result[id] = plugin
        }
    }

    private static func remotePluginSummary(_ plugin: [String: Any], installed: [String: Any]?) -> [String: Any] {
        [
            "id": plugin["id"] as? String ?? "",
            "name": plugin["name"] as? String ?? "",
            "shareContext": remotePluginShareContext(plugin),
            "source": ["type": "remote"],
            "installed": installed != nil,
            "enabled": installed?["enabled"] as? Bool ?? false,
            "installPolicy": plugin["installation_policy"] as? String ?? "NOT_AVAILABLE",
            "authPolicy": plugin["authentication_policy"] as? String ?? "ON_USE",
            "availability": remotePluginAvailability(plugin["status"] as? String),
            "interface": remotePluginInterface(plugin),
            "keywords": (plugin["release"] as? [String: Any])?["keywords"] as? [String] ?? []
        ].nullStripped()
    }

    private static func remotePluginShareContext(_ plugin: [String: Any]) -> Any {
        guard plugin["scope"] as? String == "WORKSPACE" else {
            return NSNull()
        }
        return [
            "remotePluginId": plugin["id"] as? String ?? "",
            "shareUrl": nullable(plugin["share_url"] as? String),
            "creatorAccountUserId": nullable(plugin["creator_account_user_id"] as? String),
            "creatorName": nullable(plugin["creator_name"] as? String),
            "shareTargets": nullable(remotePluginShareTargets(plugin["share_principals"] as? [[String: Any]]))
        ].nullStripped(keepNulls: true)
    }

    private static func remotePluginShareTargets(_ principals: [[String: Any]]?) -> [[String: Any]]? {
        principals?.compactMap { principal in
            guard principal["role"] as? String == "reader" else {
                return nil
            }
            return [
                "principalType": principal["principal_type"] as? String ?? "",
                "principalId": principal["principal_id"] as? String ?? "",
                "name": principal["name"] as? String ?? ""
            ]
        }
    }

    private static func remotePluginDisplayName(_ plugin: [String: Any]) -> String {
        if let interface = plugin["interface"] as? [String: Any],
           let displayName = interface["displayName"] as? String,
           !displayName.isEmpty {
            return displayName
        }
        return plugin["name"] as? String ?? ""
    }

    private static func remotePluginAvailability(_ status: String?) -> String {
        status == "DISABLED_BY_ADMIN" ? "DISABLED_BY_ADMIN" : "AVAILABLE"
    }

    private static func remotePluginInterface(_ plugin: [String: Any]) -> Any {
        guard let release = plugin["release"] as? [String: Any],
              let interface = release["interface"] as? [String: Any]
        else {
            return NSNull()
        }
        let displayName = (release["display_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            "displayName": nullable(displayName?.isEmpty == false ? displayName : nil),
            "shortDescription": nullable(interface["short_description"] as? String),
            "longDescription": nullable(interface["long_description"] as? String),
            "developerName": nullable(interface["developer_name"] as? String),
            "category": nullable(interface["category"] as? String),
            "capabilities": interface["capabilities"] as? [String] ?? [],
            "websiteUrl": nullable(interface["website_url"] as? String),
            "privacyPolicyUrl": nullable(interface["privacy_policy_url"] as? String),
            "termsOfServiceUrl": nullable(interface["terms_of_service_url"] as? String),
            "defaultPrompt": nullable(remotePluginDefaultPrompt(interface["default_prompt"] as? String)),
            "brandColor": nullable(interface["brand_color"] as? String),
            "composerIcon": NSNull(),
            "composerIconUrl": nullable(interface["composer_icon_url"] as? String),
            "logo": NSNull(),
            "logoUrl": nullable(interface["logo_url"] as? String),
            "screenshots": [],
            "screenshotUrls": interface["screenshot_urls"] as? [String] ?? []
        ].nullStripped()
    }

    private static func remotePluginDefaultPrompt(_ prompt: String?) -> [String]? {
        guard let prompt = prompt?.trimmingCharacters(in: .whitespacesAndNewlines),
              !prompt.isEmpty,
              prompt.count <= 128
        else {
            return nil
        }
        return [prompt]
    }

    private static func featuredPluginIDs(
        for marketplaces: [[String: Any]],
        runtimeConfig: CodexRuntimeConfig,
        configuration: CodexAppServerConfiguration,
        cachedFeaturedPluginIDs: [String]? = nil,
        cacheFeaturedPluginIDs: (([String]) -> Void)? = nil
    ) -> [String] {
        guard marketplaces.contains(where: { $0["name"] as? String == "openai-curated" }) else {
            return []
        }
        if let cachedFeaturedPluginIDs {
            return cachedFeaturedPluginIDs
        }
        let normalizedBaseURL = AccountBackendEndpoint.normalizedBaseURL(runtimeConfig.chatgptBaseURL)
        guard var components = URLComponents(string: normalizedBaseURL + "/plugins/featured") else {
            return []
        }
        components.queryItems = [URLQueryItem(name: "platform", value: "codex")]
        guard let url = components.url else {
            return []
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let auth = try? currentAuth(configuration: configuration),
           case .chatGPT = auth.kind {
            request.setValue("Bearer \(auth.token)", forHTTPHeaderField: "Authorization")
            if let accountID = auth.accountID, !accountID.isEmpty {
                request.setValue(accountID, forHTTPHeaderField: "chatgpt-account-id")
            }
        }

        guard let response = try? configuration.pluginHTTPTransport(request),
              (200..<300).contains(response.statusCode),
              let ids = try? JSONDecoder().decode([String].self, from: response.body)
        else {
            return []
        }
        cacheFeaturedPluginIDs?(ids)
        return ids
    }

    private static func localMarketplaceDiscoveryRoots(
        cwds: [URL],
        codexHome: URL,
        config: ConfigValue
    ) -> [URL] {
        var roots = cwds
        roots.append(contentsOf: configuredMarketplaceRoots(in: config, codexHome: codexHome))
        let curatedRoot = codexHome.appendingPathComponent(".tmp/plugins", isDirectory: true)
        if FileManager.default.fileExists(atPath: curatedRoot.path) {
            roots.append(curatedRoot)
        }
        var seen: Set<String> = []
        return roots.map(\.standardizedFileURL).filter { seen.insert($0.path).inserted }
    }

    private static func configuredMarketplaceRoots(in config: ConfigValue, codexHome: URL) -> [URL] {
        guard let marketplaces = marketplaceConfigTable(in: config) else {
            return []
        }
        let defaultRoot = codexHome.appendingPathComponent(".tmp/marketplaces", isDirectory: true)
        return marketplaces.compactMap { name, value -> URL? in
            guard let entry = configTable(value) else {
                return nil
            }
            let root: URL
            if stringConfig(entry, "source_type") == "local",
               let source = stringConfig(entry, "source"),
               !source.isEmpty {
                root = URL(fileURLWithPath: source, isDirectory: true)
            } else {
                root = defaultRoot.appendingPathComponent(name, isDirectory: true)
            }
            return localMarketplaceManifestPath(in: root) == nil ? nil : root
        }
    }

    private static func localMarketplaceManifestPaths(from roots: [URL]) -> [URL] {
        var paths: [URL] = []
        for root in roots {
            if let path = localMarketplaceManifestPath(in: root), !paths.contains(path) {
                paths.append(path)
                continue
            }
            if let repoRoot = gitRepositoryRoot(containing: root),
               let path = localMarketplaceManifestPath(in: repoRoot),
               !paths.contains(path) {
                paths.append(path)
            }
        }
        return paths
    }

    private static func gitRepositoryRoot(containing url: URL) -> URL? {
        var current = url.standardizedFileURL
        while true {
            let dotGit = current.appendingPathComponent(".git", isDirectory: true)
            if FileManager.default.fileExists(atPath: dotGit.path) {
                return current
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                return nil
            }
            current = parent
        }
    }

    private static func pluginMarketplaceEntry(
        manifestPath: URL,
        config: ConfigValue,
        codexHome: URL? = nil
    ) throws -> [String: Any] {
        let marketplaceRoot = try marketplaceRoot(forManifestPath: manifestPath)
        let data = try Data(contentsOf: manifestPath)
        let object = try marketplaceManifestObject(data: data, manifestPath: manifestPath)
        guard let name = object["name"] as? String else {
            throw AppServerError.invalidRequest("invalid marketplace file `\(manifestPath.path)`: missing field `name`")
        }
        let plugins = try marketplacePluginSummaries(
            object["plugins"],
            marketplaceName: name,
            marketplaceRoot: marketplaceRoot,
            manifestPath: manifestPath,
            config: config,
            codexHome: codexHome
        )
        return [
            "name": name,
            "path": manifestPath.path,
            "interface": marketplaceInterfaceObject(object["interface"]),
            "plugins": plugins
        ].nullStripped()
    }

    private static func marketplaceManifestObject(data: Data, manifestPath: URL) throws -> [String: Any] {
        do {
            return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        } catch {
            throw AppServerError.invalidRequest("invalid marketplace file `\(manifestPath.path)`: \(error)")
        }
    }

    private static func marketplacePluginSummaries(
        _ value: Any?,
        marketplaceName: String,
        marketplaceRoot: URL,
        manifestPath: URL,
        config: ConfigValue,
        codexHome: URL?
    ) throws -> [[String: Any]] {
        guard let plugins = value as? [[String: Any]] else {
            throw AppServerError.invalidRequest("invalid marketplace file `\(manifestPath.path)`: missing field `plugins`")
        }
        var seen: Set<String> = []
        return plugins.compactMap { plugin in
            guard let pluginName = plugin["name"] as? String,
                  let source = marketplacePluginSource(plugin["source"], marketplaceRoot: marketplaceRoot)
            else {
                return nil
            }
            let id = "\(pluginName)@\(marketplaceName)"
            guard seen.insert(id).inserted else {
                return nil
            }
            let manifest: LocalPluginManifest
            if case .local(let sourcePath) = source {
                manifest = localPluginManifest(root: sourcePath)
            } else {
                manifest = .empty
            }
            let policy = plugin["policy"] as? [String: Any] ?? [:]
            return [
                "id": id,
                "name": pluginName,
                "shareContext": NSNull(),
                "source": pluginSourceObject(source),
                "installed": codexHome.map { localPluginInstalled(id: id, codexHome: $0) } ?? false,
                "enabled": configuredPluginEnabled(id: id, in: config),
                "installPolicy": policy["installation"] as? String ?? "AVAILABLE",
                "authPolicy": policy["authentication"] as? String ?? "ON_INSTALL",
                "availability": "AVAILABLE",
                "interface": pluginInterfaceWithMarketplaceCategory(
                    manifest.interface,
                    category: plugin["category"] as? String
                ),
                "keywords": manifest.keywords
            ].nullStripped()
        }
    }

    private static func localPluginReadResult(
        marketplacePath: String,
        pluginName: String,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        let manifestPath = URL(fileURLWithPath: marketplacePath, isDirectory: false)
        let config = try localPluginReadConfig(
            marketplaceManifestPath: manifestPath,
            configuration: configuration
        )
        let marketplace = try pluginMarketplaceEntry(
            manifestPath: manifestPath,
            config: config,
            codexHome: configuration.codexHome
        )
        let marketplaceName = marketplace["name"] as? String ?? ""
        let summaries = marketplace["plugins"] as? [[String: Any]] ?? []
        guard var summary = summaries.first(where: { $0["name"] as? String == pluginName }) else {
            throw AppServerError.invalidRequest(
                "plugin `\(pluginName)` was not found in marketplace `\(marketplaceName)`"
            )
        }
        let pluginID = "\(pluginName)@\(marketplaceName)"
        let source = summary["source"] as? [String: Any]
        let sourceType = source?["type"] as? String
        let sourcePath: URL?
        if sourceType == "local" {
            sourcePath = (source?["path"] as? String).map { URL(fileURLWithPath: $0, isDirectory: true) }
        } else if sourceType == "git", summary["installed"] as? Bool == true {
            sourcePath = activeLocalPluginRoot(id: pluginID, codexHome: configuration.codexHome)
        } else {
            sourcePath = nil
        }
        let manifest = sourcePath.map(localPluginManifest(root:)) ?? LocalPluginManifest.empty
        if sourcePath != nil {
            let marketplaceCategory = (summary["interface"] as? [String: Any])?["category"] as? String
            summary["interface"] = pluginInterfaceWithMarketplaceCategory(
                manifest.interface,
                category: marketplaceCategory
            )
            summary["keywords"] = manifest.keywords
        }
        let skills = sourcePath.map { localPluginSkills(root: $0, pluginName: pluginName, config: config, manifest: manifest) } ?? []
        let hooks = sourcePath.map {
            localPluginHooks(
                root: $0,
                pluginID: pluginID,
                enabled: configFeatureEnabled("plugin_hooks", in: config, defaultValue: false),
                manifest: manifest
            )
        } ?? []
        let apps = sourcePath.map {
            localPluginAppSummariesForRead(
                root: $0,
                manifest: manifest,
                configuration: configuration
            )
        } ?? []
        let mcpServers = sourcePath.map { localPluginMcpServerNames(root: $0, manifest: manifest) } ?? []
        let description: Any
        if sourceType == "git", sourcePath == nil {
            description = remotePluginInstallRequiredDescription(source)
        } else {
            description = manifest.description ?? NSNull()
        }

        return [
            "plugin": [
                "marketplaceName": marketplaceName,
                "marketplacePath": marketplacePath,
                "summary": summary,
                "description": description,
                "skills": skills,
                "hooks": hooks,
                "apps": apps,
                "mcpServers": mcpServers
            ].nullStripped(keepNulls: true)
        ]
    }

    private static func localPluginReadConfig(
        marketplaceManifestPath: URL,
        configuration: CodexAppServerConfiguration
    ) throws -> ConfigValue {
        do {
            return try CodexConfigLayerLoader.loadConfigLayerStack(
                codexHome: configuration.codexHome,
                cwd: marketplaceManifestPath.deletingLastPathComponent(),
                cliOverrides: configuration.cliConfigOverrides,
                overrides: configuration.configLayerOverrides,
                environment: configuration.environment,
                systemConfigFile: nil
            ).effectiveConfig()
        } catch {
            throw AppServerError.internalError("failed to reload config: \(error)")
        }
    }

    private static func remotePluginReadResult(
        remoteMarketplaceName: String,
        pluginID: String,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        let runtimeConfig = try pluginRuntimeConfig(configuration: configuration)
        guard runtimeConfig.features.isEnabled(.plugins) else {
            throw AppServerError.invalidRequest("remote plugin read is not enabled for marketplace \(remoteMarketplaceName)")
        }
        guard isValidRemotePluginID(pluginID) else {
            throw AppServerError.invalidRequest(
                "invalid remote plugin id: only ASCII letters, digits, `_`, `-`, and `~` are allowed"
            )
        }
        guard let auth = try? currentAuth(configuration: configuration),
              case .chatGPT = auth.kind
        else {
            throw AppServerError.invalidRequest("read remote plugin details: chatgpt authentication required for remote plugin catalog")
        }
        let plugin = try remotePluginObject(
            path: "/ps/plugins/\(pluginID)",
            queryItems: [],
            runtimeConfig: runtimeConfig,
            configuration: configuration,
            auth: auth,
            failurePrefix: "read remote plugin details"
        )
        let scope = plugin["scope"] as? String ?? "GLOBAL"
        let marketplaceName = remotePluginMarketplaceName(forScope: scope)
        let installedPlugins = try remotePluginPagesOrThrow(
            path: "/ps/plugins/installed",
            queryItems: [URLQueryItem(name: "scope", value: scope == "WORKSPACE" ? "WORKSPACE" : "GLOBAL")],
            runtimeConfig: runtimeConfig,
            configuration: configuration,
            auth: auth,
            failurePrefix: "read remote plugin details"
        )
        let installedPlugin = installedPlugins.first { $0["id"] as? String == pluginID }
        let disabledSkillNames = Set(installedPlugin?["disabled_skill_names"] as? [String] ?? [])
        let appIDs = (plugin["release"] as? [String: Any])?["app_ids"] as? [String] ?? []
        return [
            "plugin": [
                "marketplaceName": marketplaceName,
                "marketplacePath": NSNull(),
                "summary": remotePluginSummary(plugin, installed: installedPlugin),
                "description": nullable(remotePluginDescription(plugin)),
                "skills": remotePluginSkills(plugin, disabledSkillNames: disabledSkillNames),
                "hooks": [],
                "apps": remotePluginAppSummaries(
                    appIDs: appIDs,
                    runtimeConfig: runtimeConfig,
                    configuration: configuration,
                    auth: auth
                ),
                "mcpServers": []
            ].nullStripped(keepNulls: true)
        ]
    }

    private static func pluginRuntimeConfig(configuration: CodexAppServerConfiguration) throws -> CodexRuntimeConfig {
        do {
            return try CodexConfigLoader.load(
                codexHome: configuration.codexHome,
                systemConfigFile: nil,
                environment: configuration.environment
            )
        } catch {
            throw AppServerError.internalError("failed to reload config: \(error)")
        }
    }

    private static func remotePluginMarketplaceName(forScope scope: String) -> String {
        scope == "WORKSPACE" ? "workspace-directory" : "chatgpt-global"
    }

    private static func remotePluginScope(forMarketplaceName marketplaceName: String) -> String? {
        switch marketplaceName {
        case "chatgpt-global":
            return "GLOBAL"
        case "workspace-directory", "shared-with-me":
            return "WORKSPACE"
        default:
            return nil
        }
    }

    private static func remotePluginDescription(_ plugin: [String: Any]) -> String? {
        let description = ((plugin["release"] as? [String: Any])?["description"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let description, !description.isEmpty else {
            return nil
        }
        return description
    }

    private static func remotePluginSkills(_ plugin: [String: Any], disabledSkillNames: Set<String>) -> [[String: Any]] {
        let skills = (plugin["release"] as? [String: Any])?["skills"] as? [[String: Any]] ?? []
        return skills.map { skill in
            let name = skill["name"] as? String ?? ""
            return [
                "name": name,
                "description": skill["description"] as? String ?? "",
                "shortDescription": nullable((skill["interface"] as? [String: Any])?["short_description"] as? String),
                "interface": remotePluginSkillInterface(skill["interface"] as? [String: Any]),
                "path": NSNull(),
                "enabled": !disabledSkillNames.contains(name)
            ].nullStripped(keepNulls: true)
        }
    }

    private static func remotePluginAppSummaries(
        appIDs: [String],
        runtimeConfig: CodexRuntimeConfig,
        configuration: CodexAppServerConfiguration,
        auth: AppServerAuth
    ) -> [[String: Any]] {
        let pluginAppIDs = Set(appIDs.compactMap { id -> String? in
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || !isConnectorIDAllowed(trimmed, originatorValue: configuration.originator) ? nil : trimmed
        })
        guard !pluginAppIDs.isEmpty else {
            return []
        }

        var appsByID: [String: [String: Any]] = [:]
        var canDetermineAuthState = false
        if runtimeConfig.features.isEnabled(.apps) {
            for app in (try? connectorDirectoryApps(
                runtimeConfig: runtimeConfig,
                configuration: configuration,
                auth: auth
            )) ?? [] {
                guard let id = app["id"] as? String, pluginAppIDs.contains(id) else {
                    continue
                }
                appsByID[id] = appInfoByMergingConnectorAppInfo(existing: appsByID[id], incoming: app)
            }

            if let accessibleConnectors = try? configuration.accessibleConnectorProvider(runtimeConfig, true) {
                canDetermineAuthState = true
                for app in appInfosForAccessibleConnectors(filterDisallowedConnectors(
                    accessibleConnectors,
                    originatorValue: configuration.originator
                )) {
                    guard let id = app["id"] as? String, pluginAppIDs.contains(id) else {
                        continue
                    }
                    appsByID[id] = appInfoByMergingConnectorAppInfo(
                        existing: appsByID[id],
                        incoming: app,
                        recomputeInstallURLOnNameMerge: false
                    )
                }
            }
        }

        for id in pluginAppIDs where appsByID[id] == nil {
            appsByID[id] = placeholderPluginAppInfo(connectorID: id)
        }

        return sortedAppInfos(Array(appsByID.values)).map { app in
            let id = app["id"] as? String ?? ""
            let name = app["name"] as? String ?? id
            return [
                "id": id,
                "name": name,
                "description": app["description"] as Any? ?? NSNull(),
                "installUrl": stringParam(app["installUrl"]) ?? connectorInstallURL(name: name, connectorID: id),
                "needsAuth": canDetermineAuthState ? !(app["isAccessible"] as? Bool ?? false) : false
            ].nullStripped(keepNulls: true)
        }
    }

    private static func placeholderPluginAppInfo(connectorID: String) -> [String: Any] {
        [
            "id": connectorID,
            "name": connectorID,
            "description": NSNull(),
            "logoUrl": NSNull(),
            "logoUrlDark": NSNull(),
            "distributionChannel": NSNull(),
            "branding": NSNull(),
            "appMetadata": NSNull(),
            "labels": NSNull(),
            "installUrl": connectorInstallURL(name: connectorID, connectorID: connectorID),
            "isAccessible": false,
            "isEnabled": true,
            "pluginDisplayNames": []
        ].nullStripped(keepNulls: true)
    }

    private static func remotePluginSkillInterface(_ interface: [String: Any]?) -> Any {
        guard let interface else {
            return NSNull()
        }
        return [
            "displayName": nullable(interface["display_name"] as? String),
            "shortDescription": nullable(interface["short_description"] as? String),
            "iconSmall": NSNull(),
            "iconLarge": NSNull(),
            "brandColor": nullable(interface["brand_color"] as? String),
            "defaultPrompt": nullable(interface["default_prompt"] as? String)
        ].nullStripped()
    }

    private static func localPluginSourcePath(_ value: Any?, marketplaceRoot: URL) -> URL? {
        guard case .local(let path) = marketplacePluginSource(value, marketplaceRoot: marketplaceRoot) else {
            return nil
        }
        return path
    }

    private enum MarketplacePluginSource {
        case local(URL)
        case git(url: String, path: String?, refName: String?, sha: String?)
    }

    private static func pluginSourceObject(_ source: MarketplacePluginSource) -> [String: Any] {
        switch source {
        case .local(let path):
            return [
                "type": "local",
                "path": path.path
            ]
        case .git(let url, let path, let refName, let sha):
            return [
                "type": "git",
                "url": url,
                "path": nullable(path),
                "refName": nullable(refName),
                "sha": nullable(sha)
            ].nullStripped(keepNulls: true)
        }
    }

    private static func pluginInterfaceWithMarketplaceCategory(_ interface: Any, category: String?) -> Any {
        guard let category else {
            return interface
        }
        var object = interface as? [String: Any] ?? [:]
        object["category"] = category
        return object
    }

    private static func remotePluginInstallRequiredDescription(_ source: [String: Any]?) -> String {
        guard source?["type"] as? String == "git" else {
            return "This is a cross-repo plugin. Install it to view more detailed information."
        }
        var parts: [String] = []
        if let url = source?["url"] as? String {
            parts.append(url)
        }
        if let path = source?["path"] as? String {
            parts.append("path `\(path)`")
        }
        if let refName = source?["refName"] as? String {
            parts.append("ref `\(refName)`")
        }
        if let sha = source?["sha"] as? String {
            parts.append("sha `\(sha)`")
        }
        return "This is a cross-repo plugin. Install it to view more detailed information. The source of the plugin is \(parts.joined(separator: ", "))."
    }

    private static func marketplacePluginSource(_ value: Any?, marketplaceRoot: URL) -> MarketplacePluginSource? {
        let rawPath: String?
        if let path = value as? String {
            rawPath = path
        } else if let source = value as? [String: Any],
                  let sourceType = source["source"] as? String,
                  sourceType == "local" {
            rawPath = source["path"] as? String
        } else if let source = value as? [String: Any],
                  let sourceType = source["source"] as? String,
                  sourceType == "git-subdir",
                  let url = source["url"] as? String,
                  let path = source["path"] as? String {
            return .git(
                url: url,
                path: path,
                refName: source["ref"] as? String,
                sha: source["sha"] as? String
            )
        } else if let source = value as? [String: Any],
                  let sourceType = source["source"] as? String,
                  sourceType == "url",
                  let url = source["url"] as? String {
            return .git(
                url: url,
                path: source["path"] as? String,
                refName: source["ref"] as? String,
                sha: source["sha"] as? String
            )
        } else {
            rawPath = nil
        }
        guard let rawPath,
              rawPath.hasPrefix("./"),
              rawPath.count > 2
        else {
            return nil
        }
        let relative = String(rawPath.dropFirst(2))
        let components = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }
        let path = components.reduce(marketplaceRoot) { partial, component in
            partial.appendingPathComponent(String(component), isDirectory: true)
        }.standardizedFileURL
        return .local(path)
    }

    private struct LocalPluginInlineHooks {
        let sourcePath: String
        let hooks: [String: Any]
    }

    private struct LocalPluginHookConfigLoadOutcome {
        var configs: [LocalPluginInlineHooks] = []
        var warnings: [String] = []
    }

    private struct HookState {
        var enabled: Bool?
        var trustedHash: String?
    }

    private struct LocalPluginManifest {
        let name: String?
        let interface: Any
        let keywords: [String]
        let description: String?
        let version: String?
        let skillRoot: URL?
        let appConfig: URL?
        let mcpConfig: URL?
        let hookConfigs: [URL]?
        let inlineHooks: [LocalPluginInlineHooks]

        static var empty: LocalPluginManifest {
            LocalPluginManifest(
                name: nil,
                interface: NSNull(),
                keywords: [],
                description: nil,
                version: nil,
                skillRoot: nil,
                appConfig: nil,
                mcpConfig: nil,
                hookConfigs: nil,
                inlineHooks: []
            )
        }
    }

    private static func localPluginManifest(root: URL) -> LocalPluginManifest {
        let candidates = [
            root.appendingPathComponent(".codex-plugin/plugin.json", isDirectory: false),
            root.appendingPathComponent(".claude-plugin/plugin.json", isDirectory: false)
        ]
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let data = try? Data(contentsOf: path),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return .empty
        }
        let keywords = object["keywords"] as? [String] ?? []
        return LocalPluginManifest(
            name: object["name"] as? String,
            interface: pluginInterfaceObject(object["interface"], pluginRoot: root),
            keywords: keywords,
            description: object["description"] as? String,
            version: object["version"] as? String,
            skillRoot: localPluginManifestPath(root: root, value: object["skills"]),
            appConfig: localPluginManifestPath(root: root, value: object["apps"]),
            mcpConfig: localPluginManifestPath(root: root, value: object["mcpServers"]),
            hookConfigs: localPluginManifestHookPaths(root: root, value: object["hooks"]),
            inlineHooks: localPluginManifestInlineHooks(value: object["hooks"])
        )
    }

    private static func localPluginSkills(root: URL, pluginName: String, config: ConfigValue, manifest: LocalPluginManifest) -> [[String: Any]] {
        let defaultSkillsRoot = root.appendingPathComponent("skills", isDirectory: true)
        var skillRoots: [URL] = []
        if isDirectory(defaultSkillsRoot) {
            skillRoots.append(defaultSkillsRoot)
        }
        if let skillRoot = manifest.skillRoot {
            skillRoots.append(skillRoot)
        }
        skillRoots = Array(Dictionary(grouping: skillRoots.map(\.standardizedFileURL), by: \.path).values.compactMap(\.first))
            .sorted { $0.path < $1.path }

        var outcome = SkillLoadOutcome()
        for skillsRoot in skillRoots {
            discoverSkills(root: skillsRoot, scope: .user, outcome: &outcome)
        }
        let rules = skillConfigRules(from: config)
        return outcome.skills.sorted {
            if $0.name != $1.name {
                return $0.name < $1.name
            }
            return $0.path < $1.path
        }.map { skill in
            [
                "name": "\(pluginName):\(skill.name)",
                "description": skill.description,
                "shortDescription": nullable(skill.shortDescription),
                "interface": NSNull(),
                "path": skill.path,
                "enabled": isSkillEnabled(skill, rules: rules)
            ].nullStripped(keepNulls: true)
        }
    }

    private static func localPluginHooks(root: URL, pluginID: String, enabled: Bool, manifest: LocalPluginManifest) -> [[String: Any]] {
        guard enabled else {
            return []
        }
        var summaries: [[String: Any]] = []
        for config in localPluginHookConfigs(root: root, manifest: manifest) {
            for (eventKey, value) in config.hooks {
                guard let eventName = localPluginHookEventName(eventKey),
                      let groups = value as? [[String: Any]]
                else {
                    continue
                }
                for (groupIndex, group) in groups.enumerated() {
                    let handlers = group["hooks"] as? [[String: Any]] ?? []
                    for handlerIndex in handlers.indices {
                        summaries.append([
                            "key": "\(pluginID):\(config.sourcePath):\(HooksProtocol.hookEventKeyLabel(eventName)):\(groupIndex):\(handlerIndex)",
                            "eventName": appServerHookEventName(eventName)
                        ])
                    }
                }
            }
        }
        summaries.sort {
            ($0["key"] as? String ?? "") < ($1["key"] as? String ?? "")
        }
        return summaries
    }

    private static func localPluginHookMetadata(root: URL, pluginID: String, manifest: LocalPluginManifest) -> [[String: Any]] {
        localPluginHookMetadata(
            root: root,
            pluginID: pluginID,
            manifest: manifest,
            configs: localPluginHookConfigs(root: root, manifest: manifest),
            hookStates: [:]
        )
    }

    private static func localPluginHookMetadata(
        root: URL,
        pluginID: String,
        manifest _: LocalPluginManifest,
        configs: [LocalPluginInlineHooks],
        hookStates: [String: HookState]
    ) -> [[String: Any]] {
        var metadata: [[String: Any]] = []
        var displayOrder = 0
        for config in configs {
            for (eventKey, value) in config.hooks {
                guard let eventName = localPluginHookEventName(eventKey),
                      let groups = value as? [[String: Any]]
                else {
                    continue
                }
                for (groupIndex, group) in groups.enumerated() {
                    let matcher = group["matcher"] as? String
                    let handlers = group["hooks"] as? [[String: Any]] ?? []
                    for (handlerIndex, handler) in handlers.enumerated() {
                        guard (handler["type"] as? String) == "command",
                              let command = handler["command"] as? String
                        else {
                            continue
                        }
                        let timeoutSec = hookTimeoutSec(handler["timeout"] ?? handler["timeoutSec"] ?? handler["timeout_sec"])
                            ?? 600
                        let statusMessage = handler["statusMessage"] as? String ?? handler["status_message"] as? String
                        let key = "\(pluginID):\(config.sourcePath):\(HooksProtocol.hookEventKeyLabel(eventName)):\(groupIndex):\(handlerIndex)"
                        let currentHash = userHookHash(
                            eventName: eventName,
                            matcher: matcher,
                            command: command,
                            timeoutSec: timeoutSec,
                            statusMessage: statusMessage
                        )
                        metadata.append([
                            "key": key,
                            "eventName": appServerHookEventName(eventName),
                            "handlerType": "command",
                            "matcher": matcher as Any? ?? NSNull(),
                            "command": command,
                            "timeoutSec": Int(timeoutSec),
                            "statusMessage": statusMessage as Any? ?? NSNull(),
                            "sourcePath": root.appendingPathComponent(config.sourcePath, isDirectory: false).standardizedFileURL.path,
                            "source": "plugin",
                            "pluginId": pluginID,
                            "displayOrder": displayOrder,
                            "enabled": hookStates[key]?.enabled ?? true,
                            "isManaged": false,
                            "currentHash": currentHash,
                            "trustStatus": hookTrustStatus(currentHash: currentHash, state: hookStates[key])
                        ])
                        displayOrder += 1
                    }
                }
            }
        }
        metadata.sort {
            ($0["key"] as? String ?? "") < ($1["key"] as? String ?? "")
        }
        return metadata
    }

    private static func localPluginHookConfigs(root: URL, manifest: LocalPluginManifest) -> [LocalPluginInlineHooks] {
        localPluginHookConfigLoadOutcome(root: root, manifest: manifest).configs
    }

    private static func localPluginHookConfigLoadOutcome(root: URL, manifest: LocalPluginManifest) -> LocalPluginHookConfigLoadOutcome {
        if !manifest.inlineHooks.isEmpty {
            return LocalPluginHookConfigLoadOutcome(configs: manifest.inlineHooks)
        }
        let hookPaths = manifest.hookConfigs ?? [root.appendingPathComponent("hooks/hooks.json", isDirectory: false)]
        var outcome = LocalPluginHookConfigLoadOutcome()
        for hooksPath in hookPaths {
            guard FileManager.default.fileExists(atPath: hooksPath.path) else {
                continue
            }
            do {
                let data = try Data(contentsOf: hooksPath)
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let hooks = object["hooks"] as? [String: Any]
                else {
                    outcome.warnings.append("failed to parse plugin hooks config at \(hooksPath.standardizedFileURL.path)")
                    continue
                }
                outcome.configs.append(LocalPluginInlineHooks(
                    sourcePath: localPluginRelativePath(root: root, path: hooksPath),
                    hooks: hooks
                ))
            } catch {
                outcome.warnings.append("failed to parse plugin hooks config at \(hooksPath.standardizedFileURL.path): \(error.localizedDescription)")
            }
        }
        return outcome
    }

    private static func hookTimeoutSec(_ value: Any?) -> UInt64? {
        if let value = value as? UInt64 {
            return value
        }
        if let value = value as? Int, value >= 0 {
            return UInt64(value)
        }
        if let value = value as? Double, value >= 0, value.rounded() == value {
            return UInt64(value)
        }
        if let value = value as? String {
            return UInt64(value)
        }
        return nil
    }

    private static func localPluginHookEventName(_ raw: String) -> HookEventName? {
        if let eventName = hookEventName(configLabel: raw) {
            return eventName
        }
        return HookEventName.allCases.first { $0.rawValue == raw }
    }

    private static func localPluginApps(root: URL, manifest: LocalPluginManifest) -> [[String: Any]] {
        let appPaths = [manifest.appConfig ?? root.appendingPathComponent(".app.json", isDirectory: false)]
        var appSummaries: [[String: Any]] = []
        for appPath in appPaths {
            guard let data = try? Data(contentsOf: appPath),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let apps = object["apps"] as? [String: Any]
            else {
                continue
            }
            appSummaries.append(contentsOf: apps.values.compactMap { value -> [String: Any]? in
                guard let app = value as? [String: Any],
                      let id = app["id"] as? String,
                      !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    return nil
                }
                return [
                    "id": id,
                    "name": app["name"] as? String ?? id,
                    "description": nullable(app["description"] as? String),
                    "installUrl": nullable(app["installUrl"] as? String ?? app["installURL"] as? String),
                    "needsAuth": false
                ].nullStripped(keepNulls: true)
            })
        }
        return appSummaries.sorted { ($0["id"] as? String ?? "") < ($1["id"] as? String ?? "") }
    }

    private static func localPluginAppSummariesForRead(
        root: URL,
        manifest: LocalPluginManifest,
        configuration: CodexAppServerConfiguration
    ) -> [[String: Any]] {
        let localApps = localPluginApps(root: root, manifest: manifest)
        let pluginAppIDs = Set(localApps.compactMap { stringParam($0["id"]) })
        guard !pluginAppIDs.isEmpty else {
            return []
        }
        guard let runtimeConfig = try? CodexConfigLoader.load(
            codexHome: configuration.codexHome,
            systemConfigFile: nil,
            environment: configuration.environment
        ), runtimeConfig.features.isEnabled(.apps) else {
            return localApps
        }

        var appsByID = Dictionary(
            uniqueKeysWithValues: localApps.compactMap { app -> (String, [String: Any])? in
                guard let id = stringParam(app["id"]) else {
                    return nil
                }
                return (id, app)
            }
        )
        let auth = try? currentAuth(configuration: configuration)
        if let auth, case .chatGPT = auth.kind {
            let catalogApps = (try? connectorDirectoryApps(
                runtimeConfig: runtimeConfig,
                configuration: configuration,
                auth: auth
            )) ?? []
            for app in catalogApps {
                guard let id = stringParam(app["id"]),
                      pluginAppIDs.contains(id)
                else {
                    continue
                }
                let name = normalizeConnectorName(app["name"] as? String, connectorID: id)
                appsByID[id] = [
                    "id": id,
                    "name": name,
                    "description": app["description"] as Any? ?? NSNull(),
                    "installUrl": stringParam(app["installUrl"]) ?? connectorInstallURL(name: name, connectorID: id),
                    "needsAuth": false
                ].nullStripped(keepNulls: true)
            }
        }

        let usesChatGPTBackend: Bool
        if case .chatGPT = auth?.kind {
            usesChatGPTBackend = true
        } else {
            usesChatGPTBackend = false
        }
        guard let accessibleConnectors = try? configuration.accessibleConnectorProvider(
            runtimeConfig,
            usesChatGPTBackend
        ) else {
            return appsByID.values.sorted { ($0["id"] as? String ?? "") < ($1["id"] as? String ?? "") }
        }
        let accessibleIDs = Set(accessibleConnectors.filter(\.isAccessible).map(\.id))
        for id in pluginAppIDs {
            appsByID[id]?["needsAuth"] = !accessibleIDs.contains(id)
        }
        return appsByID.values.sorted { ($0["id"] as? String ?? "") < ($1["id"] as? String ?? "") }
    }

    private static func pluginAppsNeedingAuthForInstall(
        installedPath: URL,
        runtimeConfig: CodexRuntimeConfig,
        configuration: CodexAppServerConfiguration,
        auth: AppServerAuth?
    ) -> [[String: Any]] {
        guard runtimeConfig.features.isEnabled(.apps),
              let auth,
              case .chatGPT = auth.kind
        else {
            return []
        }
        let manifest = localPluginManifest(root: installedPath)
        let pluginAppIDs = Set(localPluginApps(root: installedPath, manifest: manifest).compactMap { $0["id"] as? String })
        guard !pluginAppIDs.isEmpty else {
            return []
        }
        let connectors = (try? connectorDirectoryApps(
            runtimeConfig: runtimeConfig,
            configuration: configuration,
            auth: auth
        )) ?? []
        let accessibleIDs: Set<String>
        if let accessibleConnectors = try? configuration.accessibleConnectorProvider(runtimeConfig, true) {
            accessibleIDs = Set(accessibleConnectors.filter(\.isAccessible).map(\.id))
        } else {
            accessibleIDs = []
        }
        return connectors
            .filter { connector in
                guard let id = connector["id"] as? String else {
                    return false
                }
                return pluginAppIDs.contains(id)
                    && isConnectorIDAllowed(id, originatorValue: configuration.originator)
                    && !accessibleIDs.contains(id)
            }
            .map { connector in
                let id = connector["id"] as? String ?? ""
                let name = connector["name"] as? String ?? id
                return [
                    "id": id,
                    "name": name,
                    "description": connector["description"] as Any? ?? NSNull(),
                    "installUrl": stringParam(connector["installUrl"]) ?? connectorInstallURL(name: name, connectorID: id),
                    "needsAuth": true
                ].nullStripped(keepNulls: true)
            }
    }

    private static func connectorDirectoryApps(
        runtimeConfig: CodexRuntimeConfig,
        configuration: CodexAppServerConfiguration,
        auth: AppServerAuth,
        failOnLoadFailure: Bool = false
    ) throws -> [[String: Any]] {
        var appsByID: [String: [String: Any]] = [:]
        var token: String?
        repeat {
            var queryItems: [URLQueryItem] = []
            if let token {
                queryItems.append(URLQueryItem(name: "token", value: token))
            }
            queryItems.append(URLQueryItem(name: "external_logos", value: "true"))
            guard let page = connectorDirectoryObject(
                path: "/connectors/directory/list",
                queryItems: queryItems,
                runtimeConfig: runtimeConfig,
                configuration: configuration,
                auth: auth
            ) else {
                if failOnLoadFailure {
                    throw AppServerError.internalError("failed to list apps")
                }
                return []
            }
            mergeConnectorDirectoryApps(
                page["apps"] as? [[String: Any]] ?? [],
                into: &appsByID,
                originatorValue: configuration.originator
            )
            token = (
                (page["next_token"] as? String) ??
                (page["nextToken"] as? String) ??
                (page["pagination"] as? [String: Any])?["next_page_token"] as? String ??
                (page["pagination"] as? [String: Any])?["nextPageToken"] as? String
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
            if token?.isEmpty == true {
                token = nil
            }
        } while token != nil

        if isWorkspaceChatGPTAuth(auth),
           let workspacePage = connectorDirectoryObject(
               path: "/connectors/directory/list_workspace",
               queryItems: [URLQueryItem(name: "external_logos", value: "true")],
               runtimeConfig: runtimeConfig,
               configuration: configuration,
               auth: auth
           ) {
            mergeConnectorDirectoryApps(
                workspacePage["apps"] as? [[String: Any]] ?? [],
                into: &appsByID,
                originatorValue: configuration.originator
            )
        } else if isWorkspaceChatGPTAuth(auth), failOnLoadFailure {
            throw AppServerError.internalError("failed to list apps")
        }

        return sortedAppInfos(Array(appsByID.values))
    }

    private static func mergeConnectorDirectoryApps(
        _ apps: [[String: Any]],
        into appsByID: inout [String: [String: Any]],
        originatorValue: String
    ) {
        for app in apps where (app["visibility"] as? String) != "HIDDEN" {
            guard let id = stringParam(app["id"]) else {
                continue
            }
            guard isConnectorIDAllowed(id, originatorValue: originatorValue) else {
                continue
            }
            let incoming = appInfoForDirectoryApp(app, id: id)
            appsByID[id] = appInfoByMergingConnectorAppInfo(existing: appsByID[id], incoming: incoming)
        }
    }

    private static func appInfoForDirectoryApp(_ app: [String: Any], id: String) -> [String: Any] {
        let normalizedName = normalizeConnectorName(stringParam(app["name"]), connectorID: id)
        let installURL = stringParam(app["installUrl"]) ?? connectorInstallURL(name: normalizedName, connectorID: id)
        return [
            "id": id,
            "name": normalizedName,
            "description": normalizeConnectorString(app["description"]) as Any? ?? NSNull(),
            "logoUrl": normalizeConnectorString(app["logoUrl"]) as Any? ?? NSNull(),
            "logoUrlDark": normalizeConnectorString(app["logoUrlDark"]) as Any? ?? NSNull(),
            "distributionChannel": normalizeConnectorString(app["distributionChannel"]) as Any? ?? NSNull(),
            "branding": app["branding"] as Any? ?? NSNull(),
            "appMetadata": (app["appMetadata"] ?? app["app_metadata"]) as Any? ?? NSNull(),
            "labels": app["labels"] as Any? ?? NSNull(),
            "installUrl": installURL,
            "isAccessible": false,
            "isEnabled": true,
            "pluginDisplayNames": []
        ].nullStripped(keepNulls: true)
    }

    private static func appInfoByMergingConnectorAppInfo(
        existing: [String: Any]?,
        incoming: [String: Any],
        recomputeInstallURLOnNameMerge: Bool = true
    ) -> [String: Any] {
        guard var merged = existing else {
            return incoming
        }
        let id = stringParam(merged["id"]) ?? stringParam(incoming["id"]) ?? ""
        var updatedName = false
        if normalizeConnectorString(merged["name"]) == nil,
           let incomingName = normalizeConnectorString(incoming["name"]) {
            merged["name"] = incomingName
            updatedName = true
        } else if stringParam(merged["name"]) == id,
                  let incomingName = normalizeConnectorString(incoming["name"]),
                  incomingName != id {
            merged["name"] = incomingName
            updatedName = true
        }
        for key in ["description", "logoUrl", "logoUrlDark", "distributionChannel"] {
            if normalizeConnectorString(merged[key]) == nil,
               let incomingValue = normalizeConnectorString(incoming[key]) {
                merged[key] = incomingValue
            }
        }
        for key in ["branding", "appMetadata", "labels"] where isNullish(merged[key]) && !isNullish(incoming[key]) {
            merged[key] = incoming[key]
        }
        if merged["installUrl"] == nil || merged["installUrl"] is NSNull,
           let installURL = stringParam(incoming["installUrl"]) {
            merged["installUrl"] = installURL
        } else if recomputeInstallURLOnNameMerge,
                  updatedName,
                  let mergedName = stringParam(merged["name"]) {
            merged["installUrl"] = connectorInstallURL(name: mergedName, connectorID: id)
        }
        if (incoming["isAccessible"] as? Bool) == true {
            merged["isAccessible"] = true
        }
        if let incomingEnabled = incoming["isEnabled"] as? Bool {
            merged["isEnabled"] = (merged["isEnabled"] as? Bool ?? true) && incomingEnabled
        }
        let pluginDisplayNames = Set((merged["pluginDisplayNames"] as? [String] ?? []) + (incoming["pluginDisplayNames"] as? [String] ?? []))
        merged["pluginDisplayNames"] = pluginDisplayNames.sorted()
        return merged
    }

    private static func normalizeConnectorName(_ value: String?, connectorID: String) -> String {
        guard let normalized = normalizeConnectorString(value) else {
            return connectorID
        }
        return normalized
    }

    private static func normalizeConnectorString(_ value: Any?) -> String? {
        stringParam(value)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmptyString
    }

    private static func isNullish(_ value: Any?) -> Bool {
        value == nil || value is NSNull
    }

    private static func isWorkspaceChatGPTAuth(_ auth: AppServerAuth) -> Bool {
        guard case let .chatGPT(idToken) = auth.kind,
              case let .known(plan)? = idToken.chatGPTPlanType
        else {
            return false
        }
        return plan.isWorkspaceAccount
    }

    private static func connectorDirectoryObject(
        path: String,
        queryItems: [URLQueryItem],
        runtimeConfig: CodexRuntimeConfig,
        configuration: CodexAppServerConfiguration,
        auth: AppServerAuth
    ) -> [String: Any]? {
        let normalizedBaseURL = AccountBackendEndpoint.normalizedBaseURL(runtimeConfig.chatgptBaseURL)
        guard var components = URLComponents(string: normalizedBaseURL + path) else {
            return nil
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(auth.token)", forHTTPHeaderField: "Authorization")
        if let accountID = auth.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "chatgpt-account-id")
        }
        guard let response = try? configuration.pluginHTTPTransport(request),
              (200..<300).contains(response.statusCode),
              let object = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any]
        else {
            return nil
        }
        return object
    }

    private static func localPluginMcpServerNames(root: URL, manifest: LocalPluginManifest) -> [String] {
        let mcpPath = manifest.mcpConfig ?? root.appendingPathComponent(".mcp.json", isDirectory: false)
        guard let data = try? Data(contentsOf: mcpPath) else {
            return []
        }
        return pluginMcpServers(from: data, pluginRoot: root).keys.sorted()
    }

    private static func pluginMcpServers(from data: Data, pluginRoot: URL) -> [String: McpServerConfig] {
        guard case let .object(root) = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return [:]
        }
        let rawServers: [String: JSONValue]
        if case let .object(servers)? = root["mcpServers"] {
            rawServers = servers
        } else {
            rawServers = root
        }
        var servers: [String: McpServerConfig] = [:]
        for name in rawServers.keys.sorted() {
            guard case var .object(serverObject)? = rawServers[name] else {
                continue
            }
            serverObject["type"] = nil
            serverObject["oauth"] = nil
            if case let .string(cwd)? = serverObject["cwd"],
               !cwd.hasPrefix("/") {
                serverObject["cwd"] = .string(pluginRoot.appendingPathComponent(cwd, isDirectory: true).path)
            }
            let configValue = JSONToToml.convert(.object([name: .object(serverObject)]))
            if let parsed = try? McpConfigStore.parseMcpServers(from: configValue)[name] {
                servers[name] = parsed
            }
        }
        return servers
    }

    private static func localPluginManifestPath(root: URL, value: Any?) -> URL? {
        guard let rawPath = value as? String else {
            return nil
        }
        return localPluginResolvedManifestPath(root: root, rawPath: rawPath)
    }

    private static func localPluginManifestHookPaths(root: URL, value: Any?) -> [URL]? {
        if let rawPath = value as? String {
            return localPluginResolvedManifestPath(root: root, rawPath: rawPath).map { [$0] }
        }
        if let rawPaths = value as? [String] {
            let paths = rawPaths.compactMap { localPluginResolvedManifestPath(root: root, rawPath: $0) }
            return paths.isEmpty ? nil : paths
        }
        return nil
    }

    private static func localPluginManifestInlineHooks(value: Any?) -> [LocalPluginInlineHooks] {
        if let object = value as? [String: Any],
           let hooks = object["hooks"] as? [String: Any] {
            return [LocalPluginInlineHooks(sourcePath: "plugin.json#hooks[0]", hooks: hooks)]
        }
        if let objects = value as? [[String: Any]] {
            return objects.enumerated().compactMap { index, object in
                guard let hooks = object["hooks"] as? [String: Any] else {
                    return nil
                }
                return LocalPluginInlineHooks(sourcePath: "plugin.json#hooks[\(index)]", hooks: hooks)
            }
        }
        return []
    }

    private static func localPluginResolvedManifestPath(root: URL, rawPath: String) -> URL? {
        guard rawPath.hasPrefix("./"), rawPath.count > 2 else {
            return nil
        }
        let relative = String(rawPath.dropFirst(2))
        let components = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }
        return components.reduce(root) { partial, component in
            partial.appendingPathComponent(String(component), isDirectory: false)
        }.standardizedFileURL
    }

    private static func localPluginRelativePath(root: URL, path: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = path.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : "\(rootPath)/"
        if path.hasPrefix(prefix) {
            return String(path.dropFirst(prefix.count))
        }
        return path
    }

    private static func configFeatureEnabled(_ key: String, in config: ConfigValue, defaultValue: Bool) -> Bool {
        guard let root = configTable(config),
              let features = root["features"].flatMap(configTable)
        else {
            return defaultValue
        }
        return boolConfig(features, key) ?? defaultValue
    }

    private static func marketplaceInterfaceObject(_ value: Any?) -> Any {
        guard let interface = value as? [String: Any] else {
            return NSNull()
        }
        return ["displayName": nullable(interface["displayName"] as? String)].nullStripped()
    }

    private static func pluginInterfaceObject(_ value: Any?, pluginRoot: URL) -> Any {
        guard let interface = value as? [String: Any] else {
            return NSNull()
        }
        let screenshots = (interface["screenshots"] as? [String] ?? []).compactMap {
            pluginAssetPath($0, pluginRoot: pluginRoot)
        }
        return [
            "displayName": nullable(interface["displayName"] as? String),
            "shortDescription": nullable(interface["shortDescription"] as? String),
            "longDescription": nullable(interface["longDescription"] as? String),
            "developerName": nullable(interface["developerName"] as? String),
            "category": nullable(interface["category"] as? String),
            "capabilities": interface["capabilities"] as? [String] ?? [],
            "websiteUrl": nullable(interface["websiteUrl"] as? String ?? interface["websiteURL"] as? String),
            "privacyPolicyUrl": nullable(interface["privacyPolicyUrl"] as? String ?? interface["privacyPolicyURL"] as? String),
            "termsOfServiceUrl": nullable(interface["termsOfServiceUrl"] as? String ?? interface["termsOfServiceURL"] as? String),
            "defaultPrompt": nullable(interface["defaultPrompt"] as? [String]),
            "brandColor": nullable(interface["brandColor"] as? String),
            "composerIcon": nullable((interface["composerIcon"] as? String).flatMap { pluginAssetPath($0, pluginRoot: pluginRoot) }),
            "composerIconUrl": NSNull(),
            "logo": nullable((interface["logo"] as? String).flatMap { pluginAssetPath($0, pluginRoot: pluginRoot) }),
            "logoUrl": NSNull(),
            "screenshots": screenshots,
            "screenshotUrls": []
        ].nullStripped()
    }

    private static func pluginAssetPath(_ rawPath: String, pluginRoot: URL) -> String? {
        guard rawPath.hasPrefix("./"), rawPath.count > 2 else {
            return nil
        }
        return pluginRoot.appendingPathComponent(String(rawPath.dropFirst(2)), isDirectory: false)
            .standardizedFileURL.path
    }

    private static func configuredPluginEnabled(id: String, in config: ConfigValue) -> Bool {
        guard let root = configTable(config),
              let plugins = root["plugins"].flatMap(configTable),
              let entry = plugins[id].flatMap(configTable)
        else {
            return false
        }
        return boolConfig(entry, "enabled") ?? true
    }

    private static func localPluginInstalled(id: String, codexHome: URL) -> Bool {
        activeLocalPluginVersion(id: id, codexHome: codexHome) != nil
    }

    private static func activeLocalPluginRoot(id: String, codexHome: URL) -> URL? {
        guard let version = activeLocalPluginVersion(id: id, codexHome: codexHome) else {
            return nil
        }
        let parts = id.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            return nil
        }
        return codexHome
            .appendingPathComponent("plugins/cache", isDirectory: true)
            .appendingPathComponent(parts[1], isDirectory: true)
            .appendingPathComponent(parts[0], isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)
    }

    private static func activeLocalPluginVersion(id: String, codexHome: URL) -> String? {
        let parts = id.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            return nil
        }
        let installRoot = codexHome
            .appendingPathComponent("plugins/cache", isDirectory: true)
            .appendingPathComponent(parts[1], isDirectory: true)
            .appendingPathComponent(parts[0], isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: installRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        let versions = entries
            .filter { isDirectory($0) }
            .map { $0.lastPathComponent }
            .filter(isValidPluginVersionSegment)
            .sorted()
        if versions.contains("local") {
            return "local"
        }
        return versions.last
    }

    private static func setLocalPluginEnabled(id: String, enabled: Bool, in config: inout ConfigValue) {
        PluginConfigEditor.setEnabled(id: id, enabled: enabled, in: &config)
    }

    private static func removeLocalPluginConfig(id: String, from config: inout ConfigValue) {
        PluginConfigEditor.clear(id: id, from: &config)
    }

    private static func marketplaceRoot(forManifestPath manifestPath: URL) throws -> URL {
        let suffixes = [
            ".agents/plugins/marketplace.json",
            ".claude-plugin/marketplace.json"
        ]
        for suffix in suffixes where manifestPath.path.hasSuffix("/\(suffix)") {
            var root = manifestPath
            for _ in suffix.split(separator: "/") {
                root.deleteLastPathComponent()
            }
            return root
        }
        throw AppServerError.invalidRequest("invalid marketplace file `\(manifestPath.path)`: marketplace file is not in a supported location")
    }

    fileprivate static func pluginReadResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        let marketplacePath = try rustOptionalAbsolutePathParam(params?["marketplacePath"])
        let remoteMarketplaceName = try rustOptionalStringParam(params?["remoteMarketplaceName"])
        let pluginName = try rustRequiredStringParam(params?["pluginName"], field: "pluginName")
        switch (marketplacePath, remoteMarketplaceName) {
        case (.some, .some), (.none, .none):
            throw AppServerError.invalidRequest("plugin/read requires exactly one of marketplacePath or remoteMarketplaceName")
        case (.some(let marketplacePath), .none):
            return try localPluginReadResult(
                marketplacePath: marketplacePath,
                pluginName: pluginName,
                configuration: configuration
            )
        case (.none, .some(let remoteMarketplaceName)):
            return try remotePluginReadResult(
                remoteMarketplaceName: remoteMarketplaceName,
                pluginID: pluginName,
                configuration: configuration
            )
        }
    }

    fileprivate static func pluginSkillReadResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        let remoteMarketplaceName = try rustRequiredStringParam(
            params?["remoteMarketplaceName"],
            field: "remoteMarketplaceName"
        )
        let remotePluginID = try rustRequiredStringParam(params?["remotePluginId"], field: "remotePluginId")
        let skillName = try rustRequiredStringParam(params?["skillName"], field: "skillName")
        let runtimeConfig = try pluginRuntimeConfig(configuration: configuration)
        guard runtimeConfig.features.isEnabled(.plugins) else {
            throw AppServerError.invalidRequest("remote plugin skill read is not enabled for marketplace \(remoteMarketplaceName)")
        }
        guard isValidRemotePluginID(remotePluginID) else {
            throw AppServerError.invalidRequest(
                "invalid remote plugin id: only ASCII letters, digits, `_`, `-`, and `~` are allowed"
            )
        }
        guard !skillName.isEmpty else {
            throw AppServerError.invalidRequest("invalid remote plugin skill name: cannot be empty")
        }
        guard let auth = try? currentAuth(configuration: configuration),
              case .chatGPT = auth.kind
        else {
            throw AppServerError.invalidRequest("read remote plugin skill details: chatgpt authentication required for remote plugin catalog")
        }
        guard remotePluginScope(forMarketplaceName: remoteMarketplaceName) != nil else {
            throw AppServerError.invalidRequest("read remote plugin skill details: remote marketplace `\(remoteMarketplaceName)` is not supported")
        }
        let object = try remotePluginObject(
            path: "/ps/plugins/\(remotePluginID)/skills/\(remotePluginPathSegment(skillName))",
            queryItems: [],
            runtimeConfig: runtimeConfig,
            configuration: configuration,
            auth: auth,
            failurePrefix: "read remote plugin skill details"
        )
        if let pluginID = object["plugin_id"] as? String, pluginID != remotePluginID {
            throw AppServerError.invalidRequest(
                "read remote plugin skill details: remote plugin mutation returned unexpected plugin id: expected `\(remotePluginID)`, got `\(pluginID)`"
            )
        }
        if let responseSkillName = object["name"] as? String, responseSkillName != skillName {
            throw AppServerError.invalidRequest(
                "read remote plugin skill details: remote plugin skill response returned unexpected skill name: expected `\(skillName)`, got `\(responseSkillName)`"
            )
        }
        return ["contents": nullable(object["skill_md_contents"] as? String)].nullStripped(keepNulls: true)
    }

    fileprivate static func pluginShareSaveResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        guard params?["pluginPath"] != nil else {
            throw AppServerError.invalidParams("missing field `pluginPath`")
        }
        let pluginPath = URL(fileURLWithPath: try rustRequiredAbsolutePathParam(params?["pluginPath"], field: "pluginPath"))
        let remotePluginID = try rustOptionalStringParam(params?["remotePluginId"])
        let discoverability = try pluginShareSaveDiscoverability(params?["discoverability"])
        let shareTargets = params?["shareTargets"]
        let shareTargetsProvided = shareTargets != nil && !(shareTargets is NSNull)
        let validatedShareTargets = try validatePluginShareTargets(shareTargets)
        if let remotePluginID, (remotePluginID.isEmpty || !isValidRemotePluginID(remotePluginID)) {
            throw AppServerError.invalidRequest("invalid remote plugin id")
        }
        if remotePluginID != nil && (discoverability != nil || shareTargets != nil) {
            throw AppServerError.invalidRequest(
                "discoverability and shareTargets are only supported when creating a plugin share; use plugin/share/updateTargets to update share settings"
            )
        }
        if discoverability == "LISTED" {
            throw AppServerError.invalidRequest(
                "discoverability LISTED is not supported for plugin/share/save; use UNLISTED or PRIVATE"
            )
        }
        try validatePluginShareTargetsDoNotIncludeWorkspace(validatedShareTargets)
        let (runtimeConfig, auth) = try pluginShareRuntimeConfigAndAuth(
            configuration: configuration,
            failurePrefix: "save remote plugin share"
        )
        let result = try saveRemotePluginShare(
            pluginPath: pluginPath,
            remotePluginID: remotePluginID,
            discoverability: discoverability,
            shareTargets: validatedShareTargets,
            shareTargetsProvided: shareTargetsProvided,
            runtimeConfig: runtimeConfig,
            configuration: configuration,
            auth: auth
        )
        recordPluginShareLocalPath(
            codexHome: configuration.codexHome,
            remotePluginID: result.remotePluginID,
            pluginPath: pluginPath
        )
        return [
            "remotePluginId": result.remotePluginID,
            "shareUrl": result.shareURL
        ]
    }

    private struct RemotePluginShareSaveResult {
        let remotePluginID: String
        let shareURL: String
    }

    private struct RemotePluginShareArchive {
        let filename: String
        let bytes: Data
    }

    private static let remotePluginShareMaxArchiveBytes = 50 * 1024 * 1024

    private static func saveRemotePluginShare(
        pluginPath: URL,
        remotePluginID: String?,
        discoverability: String?,
        shareTargets: [[String: Any]],
        shareTargetsProvided: Bool,
        runtimeConfig: CodexRuntimeConfig,
        configuration: CodexAppServerConfiguration,
        auth: AppServerAuth
    ) throws -> RemotePluginShareSaveResult {
        let archive = try archiveRemotePluginForShare(
            pluginPath: pluginPath,
            codexHome: configuration.codexHome,
            environment: configuration.environment
        )
        let upload = try remotePluginObject(
            path: "/public/plugins/workspace/upload-url",
            queryItems: [],
            runtimeConfig: runtimeConfig,
            configuration: configuration,
            auth: auth,
            failurePrefix: "save remote plugin share",
            method: "POST",
            bodyObject: [
                "filename": archive.filename,
                "mime_type": "application/gzip",
                "size_bytes": archive.bytes.count,
                "plugin_id": remotePluginID ?? NSNull()
            ].nullStripped(keepNulls: false)
        )
        guard let fileID = upload["file_id"] as? String, !fileID.isEmpty else {
            throw AppServerError.internalError(
                "save remote plugin share: workspace plugin upload response did not include a file id"
            )
        }
        guard let uploadURL = upload["upload_url"] as? String,
              let parsedUploadURL = URL(string: uploadURL)
        else {
            throw AppServerError.internalError(
                "save remote plugin share: workspace plugin upload response did not include a valid upload URL"
            )
        }
        guard let etag = upload["etag"] as? String, !etag.isEmpty else {
            throw AppServerError.internalError(
                "save remote plugin share: workspace plugin upload response did not include an etag"
            )
        }
        try putRemotePluginShareArchive(
            archive.bytes,
            uploadURL: parsedUploadURL,
            configuration: configuration,
            failurePrefix: "save remote plugin share"
        )
        let finalShareTargets = remotePluginShareTargetsForSave(
            shareTargets,
            shareTargetsProvided: shareTargetsProvided,
            discoverability: discoverability,
            auth: auth
        )
        var finalizeBody: [String: Any] = [
            "file_id": fileID,
            "etag": etag
        ]
        if let discoverability {
            finalizeBody["discoverability"] = discoverability
        }
        if let finalShareTargets {
            finalizeBody["share_targets"] = finalShareTargets
        }
        let finalizePath = if let remotePluginID {
            "/public/plugins/workspace/\(remotePluginID)"
        } else {
            "/public/plugins/workspace"
        }
        let response = try remotePluginObject(
            path: finalizePath,
            queryItems: [],
            runtimeConfig: runtimeConfig,
            configuration: configuration,
            auth: auth,
            failurePrefix: "save remote plugin share",
            method: "POST",
            bodyObject: finalizeBody
        )
        guard let responsePluginID = response["plugin_id"] as? String,
              !responsePluginID.isEmpty
        else {
            throw AppServerError.internalError(
                "save remote plugin share: workspace plugin create response did not include a plugin id"
            )
        }
        return RemotePluginShareSaveResult(
            remotePluginID: responsePluginID,
            shareURL: response["share_url"] as? String ?? ""
        )
    }

    private static func archiveRemotePluginForShare(
        pluginPath: URL,
        codexHome: URL,
        environment: [String: String]
    ) throws -> RemotePluginShareArchive {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: pluginPath.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw AppServerError.invalidRequest(
                "save remote plugin share: invalid plugin path `\(pluginPath.path)`: expected a plugin directory"
            )
        }
        guard FileManager.default.fileExists(
            atPath: pluginPath.appendingPathComponent(".codex-plugin/plugin.json", isDirectory: false).path
        ) else {
            throw AppServerError.invalidRequest(
                "save remote plugin share: invalid plugin path `\(pluginPath.path)`: missing .codex-plugin/plugin.json"
            )
        }
        try validateRemotePluginShareArchiveEntries(pluginPath: pluginPath)
        let pluginName = pluginPath.lastPathComponent
        guard !pluginName.isEmpty, pluginName != "/" else {
            throw AppServerError.invalidRequest(
                "save remote plugin share: invalid plugin path `\(pluginPath.path)`: plugin path must end in a valid UTF-8 directory name"
            )
        }
        let archiveRoot = codexHome
            .appendingPathComponent(".tmp", isDirectory: true)
            .appendingPathComponent("plugin-share-archives", isDirectory: true)
        let archivePath = archiveRoot.appendingPathComponent("\(UUID().uuidString).tar.gz", isDirectory: false)
        do {
            try FileManager.default.createDirectory(at: archiveRoot, withIntermediateDirectories: true)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["-czf", archivePath.path, "-C", pluginPath.path, "."]
            process.environment = environment
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let message = [stderr, stdout]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                throw AppServerError.internalError(
                    "save remote plugin share: failed to archive plugin at `\(pluginPath.path)`: \(message)"
                )
            }
            let bytes = try Data(contentsOf: archivePath)
            if bytes.count > remotePluginShareMaxArchiveBytes {
                throw AppServerError.invalidRequest(
                    "save remote plugin share: plugin archive would be \(bytes.count) bytes, exceeding the maximum upload size of \(remotePluginShareMaxArchiveBytes) bytes"
                )
            }
            try? FileManager.default.removeItem(at: archivePath)
            return RemotePluginShareArchive(filename: "\(pluginName).tar.gz", bytes: bytes)
        } catch let error as AppServerError {
            try? FileManager.default.removeItem(at: archivePath)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: archivePath)
            throw AppServerError.internalError(
                "save remote plugin share: failed to archive plugin at `\(pluginPath.path)`: \(error)"
            )
        }
    }

    private static func validateRemotePluginShareArchiveEntries(pluginPath: URL) throws {
        guard let enumerator = FileManager.default.enumerator(
            at: pluginPath,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ) else {
            return
        }
        for case let entry as URL in enumerator {
            let resourceValues = try entry.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            if resourceValues.isSymbolicLink == true {
                throw AppServerError.internalError(
                    "save remote plugin share: failed to archive plugin at `\(pluginPath.path)`: unsupported plugin archive entry type: \(entry.path)"
                )
            }
            if resourceValues.isDirectory == true || resourceValues.isRegularFile == true {
                continue
            }
            throw AppServerError.internalError(
                "save remote plugin share: failed to archive plugin at `\(pluginPath.path)`: unsupported plugin archive entry type: \(entry.path)"
            )
        }
    }

    private static func putRemotePluginShareArchive(
        _ bytes: Data,
        uploadURL: URL,
        configuration: CodexAppServerConfiguration,
        failurePrefix: String
    ) throws {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue("BlockBlob", forHTTPHeaderField: "x-ms-blob-type")
        request.setValue("application/gzip", forHTTPHeaderField: "Content-Type")
        request.httpBody = bytes
        let response: URLSessionTransportResponse
        do {
            response = try configuration.pluginHTTPTransport(request)
        } catch {
            throw AppServerError.internalError(
                "\(failurePrefix): failed to send remote plugin catalog request to workspace plugin upload URL: \(error)"
            )
        }
        guard response.statusCode == 200 || response.statusCode == 201 else {
            let body = String(data: response.body, encoding: .utf8) ?? ""
            throw AppServerError.internalError(
                "\(failurePrefix): remote plugin catalog request to workspace plugin upload URL failed with status \(response.statusCode): \(body)"
            )
        }
    }

    private static func remotePluginShareTargetsForSave(
        _ targets: [[String: Any]],
        shareTargetsProvided: Bool,
        discoverability: String?,
        auth: AppServerAuth
    ) -> [[String: Any]]? {
        guard discoverability == "UNLISTED" else {
            return shareTargetsProvided ? targets : nil
        }
        return remotePluginShareTargets(targets, discoverability: "UNLISTED", auth: auth)
    }

    fileprivate static func pluginShareUpdateTargetsResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        guard params?["remotePluginId"] != nil else {
            throw AppServerError.invalidParams("missing field `remotePluginId`")
        }
        guard params?["discoverability"] != nil else {
            throw AppServerError.invalidParams("missing field `discoverability`")
        }
        let remotePluginID = try rustRequiredStringParam(params?["remotePluginId"], field: "remotePluginId")
        if remotePluginID.isEmpty || !isValidRemotePluginID(remotePluginID) {
            throw AppServerError.invalidRequest("invalid remote plugin id")
        }
        _ = try pluginShareUpdateDiscoverability(params?["discoverability"])
        let shareTargets = try validatePluginShareTargets(params?["shareTargets"], required: true)
        try validatePluginShareTargetsDoNotIncludeWorkspace(shareTargets)
        let (runtimeConfig, auth) = try pluginShareRuntimeConfigAndAuth(
            configuration: configuration,
            failurePrefix: "update remote plugin share targets"
        )
        let requestedTargets = shareTargets
        let discoverability = stringParam(params?["discoverability"]) ?? ""
        let object = try remotePluginObject(
            path: "/ps/plugins/\(remotePluginID)/shares",
            queryItems: [],
            runtimeConfig: runtimeConfig,
            configuration: configuration,
            auth: auth,
            failurePrefix: "update remote plugin share targets",
            method: "PUT",
            bodyObject: [
                "discoverability": discoverability,
                "targets": remotePluginShareTargets(shareTargets, discoverability: discoverability, auth: auth)
            ]
        )
        let returnedPrincipals = object["principals"] as? [[String: Any]] ?? []
        let principals = returnedPrincipals.compactMap { principal -> [String: Any]? in
            let principalType = principal["principal_type"] as? String ?? ""
            let principalID = principal["principal_id"] as? String ?? ""
            guard requestedTargets.contains(where: {
                ($0["principal_type"] as? String) == principalType
                    && ($0["principal_id"] as? String) == principalID
            }) else {
                return nil
            }
            return remotePluginSharePrincipal(principal)
        }
        return [
            "principals": principals,
            "discoverability": object["discoverability"] as? String ?? discoverability
        ]
    }

    fileprivate static func pluginShareListResult(
        params _: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        let (runtimeConfig, auth) = try pluginShareRuntimeConfigAndAuth(
            configuration: configuration,
            failurePrefix: "list remote plugin shares"
        )
        let createdPlugins = try remotePluginPagesOrThrow(
            path: "/ps/plugins/workspace/created",
            queryItems: [URLQueryItem(name: "limit", value: "200")],
            runtimeConfig: runtimeConfig,
            configuration: configuration,
            auth: auth,
            failurePrefix: "list remote plugin shares"
        )
        if createdPlugins.isEmpty {
            return ["data": []]
        }
        let installedPlugins = try remotePluginPagesOrThrow(
            path: "/ps/plugins/installed",
            queryItems: [URLQueryItem(name: "scope", value: "WORKSPACE")],
            runtimeConfig: runtimeConfig,
            configuration: configuration,
            auth: auth,
            failurePrefix: "list remote plugin shares"
        )
        let localPluginPaths = pluginShareLocalPaths(codexHome: configuration.codexHome)
        let items = createdPlugins.map { plugin -> [String: Any] in
            let pluginID = plugin["id"] as? String ?? ""
            let installed = installedPlugins.first { $0["id"] as? String == pluginID }
            return [
                "plugin": remotePluginSummary(plugin, installed: installed),
                "shareUrl": plugin["share_url"] as? String ?? "",
                "localPluginPath": localPluginPaths[pluginID]?.path ?? NSNull()
            ].nullStripped(keepNulls: true)
        }
        return ["data": items]
    }

    fileprivate static func pluginShareDeleteResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        guard params?["remotePluginId"] != nil else {
            throw AppServerError.invalidParams("missing field `remotePluginId`")
        }
        let remotePluginID = try rustRequiredStringParam(params?["remotePluginId"], field: "remotePluginId")
        if remotePluginID.isEmpty || !isValidRemotePluginID(remotePluginID) {
            throw AppServerError.invalidRequest("invalid remote plugin id")
        }
        let (runtimeConfig, auth) = try pluginShareRuntimeConfigAndAuth(
            configuration: configuration,
            failurePrefix: "delete remote plugin share"
        )
        try remotePluginEmptyResponseRequest(
            path: "/public/plugins/workspace/\(remotePluginID)",
            runtimeConfig: runtimeConfig,
            configuration: configuration,
            auth: auth,
            failurePrefix: "delete remote plugin share",
            method: "DELETE"
        )
        removePluginShareLocalPath(codexHome: configuration.codexHome, remotePluginID: remotePluginID)
        return [:]
    }

    private struct PluginShareLocalPathMapping: Codable {
        var localPluginPathsByRemotePluginId: [String: String]
    }

    private static func pluginShareLocalPaths(codexHome: URL) -> [String: URL] {
        guard let data = try? Data(contentsOf: pluginShareLocalPathsURL(codexHome: codexHome)),
              let mapping = try? JSONDecoder().decode(PluginShareLocalPathMapping.self, from: data)
        else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: mapping.localPluginPathsByRemotePluginId.map { key, path in
            (key, URL(fileURLWithPath: path))
        })
    }

    private static func recordPluginShareLocalPath(
        codexHome: URL,
        remotePluginID: String,
        pluginPath: URL
    ) {
        var mapping = pluginShareLocalPaths(codexHome: codexHome).mapValues(\.path)
        mapping[remotePluginID] = pluginPath.path
        writePluginShareLocalPathMapping(codexHome: codexHome, mapping: mapping)
    }

    private static func removePluginShareLocalPath(codexHome: URL, remotePluginID: String) {
        var mapping = pluginShareLocalPaths(codexHome: codexHome).mapValues(\.path)
        mapping.removeValue(forKey: remotePluginID)
        writePluginShareLocalPathMapping(codexHome: codexHome, mapping: mapping)
    }

    private static func writePluginShareLocalPathMapping(codexHome: URL, mapping: [String: String]) {
        let path = pluginShareLocalPathsURL(codexHome: codexHome)
        do {
            if mapping.isEmpty {
                try? FileManager.default.removeItem(at: path)
                return
            }
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(PluginShareLocalPathMapping(localPluginPathsByRemotePluginId: mapping))
            try data.write(to: path, options: [.atomic])
        } catch {
            return
        }
    }

    private static func pluginShareLocalPathsURL(codexHome: URL) -> URL {
        codexHome.appendingPathComponent(".tmp/plugin-share-local-paths-v1.json", isDirectory: false)
    }

    private static func pluginShareUpdateDiscoverability(_ value: Any?) throws -> String {
        let discoverability = try rustRequiredEnumStringParam(
            value,
            field: "discoverability",
            enumName: "PluginShareUpdateDiscoverability"
        )
        guard discoverability == "UNLISTED" || discoverability == "PRIVATE" else {
            throw AppServerError.invalidParams("unknown variant `\(discoverability)`, expected `UNLISTED` or `PRIVATE`")
        }
        return discoverability
    }

    private static func pluginShareSaveDiscoverability(_ value: Any?) throws -> String? {
        guard let discoverability = try rustOptionalEnumStringParam(value, enumName: "PluginShareDiscoverability") else {
            return nil
        }
        let validDiscoverability: Set<String> = ["LISTED", "UNLISTED", "PRIVATE"]
        guard validDiscoverability.contains(discoverability) else {
            throw AppServerError.invalidParams(
                "unknown variant `\(discoverability)`, expected one of `LISTED`, `UNLISTED`, `PRIVATE`"
            )
        }
        return discoverability
    }

    private static func rustRequiredEnumStringParam(_ value: Any?, field: String, enumName: String) throws -> String {
        guard let value else {
            throw AppServerError.invalidRequest("missing field `\(field)`")
        }
        guard !(value is NSNull), let string = value as? String else {
            throw AppServerError.invalidRequest("Invalid request: \(rustInvalidTypeDescription(value)), expected enum \(enumName)")
        }
        return string
    }

    private static func rustOptionalEnumStringParam(_ value: Any?, enumName: String) throws -> String? {
        guard let value, !(value is NSNull) else {
            return nil
        }
        guard let string = value as? String else {
            throw AppServerError.invalidRequest("Invalid request: \(rustInvalidTypeDescription(value)), expected enum \(enumName)")
        }
        return string
    }

    private static func validatePluginShareTargets(_ value: Any?, required: Bool = false) throws -> [[String: Any]] {
        if value == nil, required {
            throw AppServerError.invalidParams("missing field `shareTargets`")
        }
        guard let value, !(value is NSNull) else {
            if required {
                throw AppServerError.invalidRequest("Invalid request: invalid type: null, expected a sequence")
            }
            return []
        }
        guard let targets = value as? [Any] else {
            throw AppServerError.invalidRequest("Invalid request: \(rustInvalidTypeDescription(value)), expected a sequence")
        }
        return try targets.map { value in
            guard let target = value as? [String: Any] else {
                throw AppServerError.invalidRequest(
                    "Invalid request: \(rustInvalidTypeDescription(value)), expected struct PluginShareTarget"
                )
            }
            let principalType = try pluginSharePrincipalType(target["principalType"])
            let principalID = try rustRequiredStringParam(target["principalId"], field: "principalId")
            return [
                "principal_type": principalType,
                "principal_id": principalID
            ]
        }
    }

    private static func pluginSharePrincipalType(_ value: Any?) throws -> String {
        guard let value else {
            throw AppServerError.invalidRequest("missing field `principalType`")
        }
        guard !(value is NSNull), let principalType = value as? String else {
            throw AppServerError.invalidRequest(
                "Invalid request: \(rustInvalidTypeDescription(value)), expected enum PluginSharePrincipalType"
            )
        }
        let validPrincipalTypes: Set<String> = ["user", "group", "workspace"]
        guard validPrincipalTypes.contains(principalType) else {
            throw AppServerError.invalidParams(
                "unknown variant `\(principalType)`, expected one of `user`, `group`, `workspace`"
            )
        }
        return principalType
    }

    private static func validatePluginShareTargetsDoNotIncludeWorkspace(_ targets: [[String: Any]]) throws {
        if targets.contains(where: { $0["principal_type"] as? String == "workspace" }) {
            throw AppServerError.invalidRequest(
                "shareTargets cannot include workspace principals; use discoverability UNLISTED for workspace link access"
            )
        }
    }

    private static func pluginShareRuntimeConfigAndAuth(
        configuration: CodexAppServerConfiguration,
        failurePrefix: String
    ) throws -> (CodexRuntimeConfig, AppServerAuth) {
        let runtimeConfig = try pluginRuntimeConfig(configuration: configuration)
        guard runtimeConfig.features.isEnabled(.plugins) else {
            throw AppServerError.invalidRequest("plugin sharing is not enabled")
        }
        guard let auth = try? currentAuth(configuration: configuration) else {
            throw AppServerError.invalidRequest(
                "\(failurePrefix): chatgpt authentication required for remote plugin catalog"
            )
        }
        guard case .chatGPT = auth.kind else {
            throw AppServerError.invalidRequest(
                "\(failurePrefix): chatgpt authentication required for remote plugin catalog; api key auth is not supported"
            )
        }
        return (runtimeConfig, auth)
    }

    private static func remotePluginShareTargets(
        _ targets: [[String: Any]],
        discoverability: String,
        auth: AppServerAuth
    ) -> [[String: Any]] {
        var targets = targets
        if discoverability == "UNLISTED",
           let accountID = auth.accountID,
           !targets.contains(where: {
               ($0["principal_type"] as? String) == "workspace"
                   && ($0["principal_id"] as? String) == accountID
           }) {
            targets.append([
                "principal_type": "workspace",
                "principal_id": accountID
            ])
        }
        return targets
    }

    private static func remotePluginSharePrincipal(_ principal: [String: Any]) -> [String: Any] {
        [
            "principalType": principal["principal_type"] as? String ?? "",
            "principalId": principal["principal_id"] as? String ?? "",
            "name": principal["name"] as? String ?? ""
        ]
    }

    fileprivate static func pluginInstallResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        let marketplacePath = try rustOptionalAbsolutePathParam(params?["marketplacePath"])
        let remoteMarketplaceName = try rustOptionalStringParam(params?["remoteMarketplaceName"])
        let pluginName = try rustRequiredStringParam(params?["pluginName"], field: "pluginName")
        switch (marketplacePath, remoteMarketplaceName) {
        case (.some, .some), (.none, .none):
            throw AppServerError.invalidRequest("plugin/install requires exactly one of marketplacePath or remoteMarketplaceName")
        case (.some(let marketplacePath), .none):
            return try localPluginInstallResult(
                marketplacePath: marketplacePath,
                pluginName: pluginName,
                configuration: configuration
            )
        case (.none, .some(let remoteMarketplaceName)):
            return try remotePluginInstallResult(
                remoteMarketplaceName: remoteMarketplaceName,
                remotePluginID: pluginName,
                configuration: configuration
            )
        }
    }

    private static func remotePluginInstallResult(
        remoteMarketplaceName: String,
        remotePluginID: String,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        let runtimeConfig = try pluginRuntimeConfig(configuration: configuration)
        guard runtimeConfig.features.isEnabled(.plugins) else {
            throw AppServerError.invalidRequest("remote plugin install is not enabled for marketplace \(remoteMarketplaceName)")
        }
        guard isValidRemotePluginID(remotePluginID) else {
            throw AppServerError.invalidRequest("invalid remote plugin id")
        }
        guard let auth = try? currentAuth(configuration: configuration),
              case .chatGPT = auth.kind
        else {
            throw AppServerError.invalidRequest("install remote plugin: chatgpt authentication required for remote plugin catalog")
        }
        let detail = try remotePluginObject(
            path: "/ps/plugins/\(remotePluginID)",
            queryItems: [URLQueryItem(name: "includeDownloadUrls", value: "true")],
            runtimeConfig: runtimeConfig,
            configuration: configuration,
            auth: auth,
            failurePrefix: "read remote plugin details before install"
        )
        let scope = detail["scope"] as? String ?? "GLOBAL"
        _ = try remotePluginPagesOrThrow(
            path: "/ps/plugins/installed",
            queryItems: [URLQueryItem(name: "scope", value: scope == "WORKSPACE" ? "WORKSPACE" : "GLOBAL")],
            runtimeConfig: runtimeConfig,
            configuration: configuration,
            auth: auth,
            failurePrefix: "read remote plugin details before install"
        )
        if remotePluginAvailability(detail["status"] as? String) == "DISABLED_BY_ADMIN" {
            let pluginID = detail["id"] as? String ?? remotePluginID
            throw AppServerError.invalidRequest("remote plugin \(pluginID) is disabled by admin")
        }
        if detail["installation_policy"] as? String == "NOT_AVAILABLE" {
            let pluginID = detail["id"] as? String ?? remotePluginID
            throw AppServerError.invalidRequest("remote plugin \(pluginID) is not available for install")
        }
        let bundle = try validateRemotePluginBundleMetadata(
            remotePluginID: remotePluginID,
            detail: detail,
            environment: configuration.environment
        )
        let installedPath = try downloadAndInstallRemotePluginBundle(
            bundle,
            configuration: configuration,
            failurePrefix: "install remote plugin bundle"
        )
        let response = try remotePluginObject(
            path: "/ps/plugins/\(remotePluginID)/install",
            queryItems: [],
            runtimeConfig: runtimeConfig,
            configuration: configuration,
            auth: auth,
            failurePrefix: "install remote plugin",
            method: "POST"
        )
        if let responsePluginID = response["id"] as? String, responsePluginID != remotePluginID {
            throw AppServerError.internalError(
                "install remote plugin: remote plugin mutation returned unexpected plugin id: expected `\(remotePluginID)`, got `\(responsePluginID)`"
            )
        }
        if let enabled = response["enabled"] as? Bool, !enabled {
            throw AppServerError.internalError(
                "install remote plugin: remote plugin mutation returned unexpected enabled state for `\(remotePluginID)`: expected true, got false"
            )
        }
        _ = refreshRemoteInstalledPluginCachesAfterMutation(
            runtimeConfig: runtimeConfig,
            configuration: configuration,
            auth: auth,
            currentMutation: (
                marketplaceName: bundle.marketplaceName,
                pluginName: bundle.pluginName
            )
        )
        let appsNeedingAuth = pluginAppsNeedingAuthForInstall(
            installedPath: installedPath,
            runtimeConfig: runtimeConfig,
            configuration: configuration,
            auth: auth
        )
        return [
            "authPolicy": detail["authentication_policy"] as? String ?? "ON_USE",
            "appsNeedingAuth": appsNeedingAuth
        ]
    }

    private struct RemoteInstalledPluginCacheRefreshOutcome {
        var installedPluginIDs: Set<String> = []
        var removedCachePluginIDs: Set<String> = []
        var failedRemotePluginIDs: Set<String> = []
    }

    private static func refreshRemoteInstalledPluginCachesAfterMutation(
        runtimeConfig: CodexRuntimeConfig,
        configuration: CodexAppServerConfiguration,
        auth: AppServerAuth,
        currentMutation: (marketplaceName: String, pluginName: String)? = nil
    ) -> RemoteInstalledPluginCacheRefreshOutcome {
        guard runtimeConfig.features.isEnabled(.plugins),
              runtimeConfig.features.isEnabled(.remotePlugin)
        else {
            return RemoteInstalledPluginCacheRefreshOutcome()
        }
        var outcome = RemoteInstalledPluginCacheRefreshOutcome()
        var installedPluginNamesByMarketplace: [String: Set<String>] = [
            "chatgpt-global": [],
            "workspace-directory": []
        ]
        for scope in ["GLOBAL", "WORKSPACE"] {
            let marketplaceName = remotePluginMarketplaceName(forScope: scope)
            let plugins: [[String: Any]]
            do {
                plugins = try remotePluginPagesOrThrow(
                    path: "/ps/plugins/installed",
                    queryItems: [
                        URLQueryItem(name: "scope", value: scope),
                        URLQueryItem(name: "includeDownloadUrls", value: "true")
                    ],
                    runtimeConfig: runtimeConfig,
                    configuration: configuration,
                    auth: auth,
                    failurePrefix: "refresh remote installed plugin cache"
                )
            } catch {
                return outcome
            }
            for plugin in plugins {
                let remotePluginID = plugin["id"] as? String ?? ""
                guard let pluginName = plugin["name"] as? String,
                      !pluginName.isEmpty
                else {
                    if !remotePluginID.isEmpty {
                        outcome.failedRemotePluginIDs.insert(remotePluginID)
                    }
                    continue
                }
                installedPluginNamesByMarketplace[marketplaceName, default: []].insert(pluginName)
                let localPluginID = "\(pluginName)@\(marketplaceName)"
                let release = plugin["release"] as? [String: Any]
                let releaseVersion = (release?["version"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let releaseVersion,
                   !releaseVersion.isEmpty,
                   activeLocalPluginVersion(id: localPluginID, codexHome: configuration.codexHome) == releaseVersion {
                    continue
                }
                do {
                    let bundle = try validateRemotePluginBundleMetadata(
                        remotePluginID: remotePluginID.isEmpty ? localPluginID : remotePluginID,
                        detail: plugin,
                        environment: configuration.environment
                    )
                    _ = try downloadAndInstallRemotePluginBundle(
                        bundle,
                        configuration: configuration,
                        failurePrefix: "refresh remote installed plugin cache"
                    )
                    outcome.installedPluginIDs.insert(localPluginID)
                } catch {
                    outcome.failedRemotePluginIDs.insert(remotePluginID.isEmpty ? localPluginID : remotePluginID)
                }
            }
        }
        let removed = removeStaleRemotePluginCaches(
            codexHome: configuration.codexHome,
            installedPluginNamesByMarketplace: installedPluginNamesByMarketplace,
            currentMutation: currentMutation
        )
        outcome.removedCachePluginIDs.formUnion(removed)
        return outcome
    }

    private static func removeStaleRemotePluginCaches(
        codexHome: URL,
        installedPluginNamesByMarketplace: [String: Set<String>],
        currentMutation: (marketplaceName: String, pluginName: String)?
    ) -> Set<String> {
        let cacheRoot = codexHome.appendingPathComponent("plugins/cache", isDirectory: true)
        var removed: Set<String> = []
        for marketplaceName in ["chatgpt-global", "workspace-directory"] {
            let marketplaceRoot = cacheRoot.appendingPathComponent(marketplaceName, isDirectory: true)
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: marketplaceRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            let installedPluginNames = installedPluginNamesByMarketplace[marketplaceName] ?? []
            for entry in entries {
                let pluginName = entry.lastPathComponent
                if installedPluginNames.contains(pluginName) {
                    continue
                }
                if currentMutation?.marketplaceName == marketplaceName,
                   currentMutation?.pluginName == pluginName {
                    continue
                }
                do {
                    try FileManager.default.removeItem(at: entry)
                    removed.insert("\(pluginName)@\(marketplaceName)")
                } catch {
                    continue
                }
            }
        }
        return removed
    }

    private struct RemotePluginBundleMetadata {
        let pluginName: String
        let marketplaceName: String
        let version: String
        let downloadURL: URL
    }

    private static func validateRemotePluginBundleMetadata(
        remotePluginID: String,
        detail: [String: Any],
        environment: [String: String]
    ) throws -> RemotePluginBundleMetadata {
        let pluginName = detail["name"] as? String ?? ""
        let marketplaceName = remotePluginMarketplaceName(forScope: detail["scope"] as? String ?? "GLOBAL")
        let release = detail["release"] as? [String: Any]
        let version = (release?["version"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !version.isEmpty else {
            throw AppServerError.internalError(
                "install remote plugin bundle: backend did not return a release version for remote plugin `\(remotePluginID)`"
            )
        }
        if version == "." || version == ".." {
            throw AppServerError.internalError(
                "install remote plugin bundle: backend returned an invalid release version for remote plugin `\(remotePluginID)`: invalid plugin version: path traversal is not allowed"
            )
        }
        if !version.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "+" || $0 == "_" || $0 == "-") }) {
            throw AppServerError.internalError(
                "install remote plugin bundle: backend returned an invalid release version for remote plugin `\(remotePluginID)`: invalid plugin version: only ASCII letters, digits, `.`, `+`, `_`, and `-` are allowed"
            )
        }
        let bundleDownloadURL = (release?["bundle_download_url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !bundleDownloadURL.isEmpty else {
            throw AppServerError.internalError(
                "install remote plugin bundle: backend did not return a download URL for remote plugin `\(remotePluginID)`"
            )
        }
        guard let parsedURL = URL(string: bundleDownloadURL),
              let scheme = parsedURL.scheme
        else {
            throw AppServerError.internalError(
                "install remote plugin bundle: backend returned an invalid download URL for remote plugin `\(remotePluginID)`: \(bundleDownloadURL)"
            )
        }
        guard isAllowedRemotePluginBundleURL(parsedURL, environment: environment) else {
            throw AppServerError.internalError(
                "install remote plugin bundle: backend returned an unsupported download URL scheme for remote plugin `\(remotePluginID)`: \(scheme)"
            )
        }
        return RemotePluginBundleMetadata(
            pluginName: pluginName,
            marketplaceName: marketplaceName,
            version: version,
            downloadURL: parsedURL
        )
    }

    private static func isAllowedRemotePluginBundleURL(
        _ url: URL,
        environment: [String: String]
    ) -> Bool {
        url.scheme == "https" || isAllowedTestLoopbackHTTPRemotePluginBundleURL(url, environment: environment)
    }

    private static func isAllowedTestLoopbackHTTPRemotePluginBundleURL(
        _ url: URL,
        environment: [String: String]
    ) -> Bool {
        guard url.scheme == "http",
              environment["CODEX_TEST_ALLOW_HTTP_REMOTE_PLUGIN_BUNDLE_DOWNLOADS"] == "1",
              let host = url.host?.lowercased()
        else {
            return false
        }
        return isRemotePluginBundleLoopbackHost(host)
    }

    private static func isRemotePluginBundleLoopbackHost(_ host: String) -> Bool {
        if host == "localhost" {
            return true
        }

        var ipv4 = in_addr()
        if host.withCString({ inet_pton(AF_INET, $0, &ipv4) }) == 1 {
            let address = UInt32(bigEndian: ipv4.s_addr)
            return (address & 0xff00_0000) == 0x7f00_0000
        }

        var ipv6 = in6_addr()
        guard host.withCString({ inet_pton(AF_INET6, $0, &ipv6) }) == 1 else {
            return false
        }
        let loopbackBytes = [UInt8](repeating: 0, count: 15) + [1]
        return withUnsafeBytes(of: &ipv6.__u6_addr.__u6_addr8) { bytes in
            Array(bytes) == loopbackBytes
        }
    }

    private static func downloadAndInstallRemotePluginBundle(
        _ bundle: RemotePluginBundleMetadata,
        configuration: CodexAppServerConfiguration,
        failurePrefix: String
    ) throws -> URL {
        var request = URLRequest(url: bundle.downloadURL)
        request.httpMethod = "GET"
        let response: URLSessionTransportResponse
        do {
            response = try configuration.pluginHTTPTransport(request)
        } catch {
            throw AppServerError.internalError(
                "\(failurePrefix): failed to send remote plugin bundle download request to \(bundle.downloadURL.absoluteString): \(error)"
            )
        }
        let finalURL = remotePluginBundleFinalURL(from: response) ?? bundle.downloadURL
        guard isAllowedRemotePluginBundleURL(finalURL, environment: configuration.environment) else {
            throw AppServerError.internalError(
                "\(failurePrefix): remote plugin bundle download from \(bundle.downloadURL.absoluteString) redirected to unsupported URL \(finalURL.absoluteString)"
            )
        }
        guard (200..<300).contains(response.statusCode) else {
            let body = String(data: response.body, encoding: .utf8) ?? ""
            throw AppServerError.internalError(
                "\(failurePrefix): remote plugin bundle download from \(finalURL.absoluteString) failed with status \(response.statusCode): \(body)"
            )
        }
        let maxDownloadBytes = 50 * 1024 * 1024
        guard response.body.count <= maxDownloadBytes else {
            throw AppServerError.internalError(
                "\(failurePrefix): remote plugin bundle download from \(finalURL.absoluteString) exceeded maximum size of \(maxDownloadBytes) bytes"
            )
        }
        return try installRemotePluginBundleBytes(
            response.body,
            bundle: bundle,
            codexHome: configuration.codexHome,
            environment: configuration.environment,
            failurePrefix: failurePrefix
        )
    }

    private static func remotePluginBundleFinalURL(from response: URLSessionTransportResponse) -> URL? {
        response.headers[pluginTransportFinalURLHeader].flatMap { URL(string: $0) }
    }

    private static func installRemotePluginBundleBytes(
        _ bytes: Data,
        bundle: RemotePluginBundleMetadata,
        codexHome: URL,
        environment: [String: String],
        failurePrefix: String
    ) throws -> URL {
        let stagingRoot = codexHome
            .appendingPathComponent("plugins", isDirectory: true)
            .appendingPathComponent(".remote-plugin-install-staging", isDirectory: true)
        let extractionRoot = stagingRoot
            .appendingPathComponent("remote-plugin-bundle-\(UUID().uuidString)", isDirectory: true)
        let archivePath = extractionRoot.appendingPathComponent("bundle.tar.gz", isDirectory: false)
        do {
            try FileManager.default.createDirectory(at: extractionRoot, withIntermediateDirectories: true)
            try bytes.write(to: archivePath)
            try extractRemotePluginBundleArchive(
                archivePath: archivePath,
                destination: extractionRoot,
                environment: environment,
                failurePrefix: failurePrefix
            )
            let pluginRoot = try extractedRemotePluginRoot(
                extractionRoot: extractionRoot,
                failurePrefix: failurePrefix
            )
            let installedPath = try installLocalPluginCacheEntry(
                sourcePath: pluginRoot,
                pluginName: bundle.pluginName,
                marketplaceName: bundle.marketplaceName,
                codexHome: codexHome,
                version: bundle.version
            )
            try? FileManager.default.removeItem(at: extractionRoot)
            return installedPath
        } catch let error as AppServerError {
            try? FileManager.default.removeItem(at: extractionRoot)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: extractionRoot)
            throw AppServerError.internalError("\(failurePrefix): \(error)")
        }
    }

    private static func extractRemotePluginBundleArchive(
        archivePath: URL,
        destination: URL,
        environment: [String: String],
        failurePrefix: String
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xzf", archivePath.path, "-C", destination.path]
        process.environment = environment
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try validateRemotePluginBundleArchive(
            archivePath: archivePath,
            environment: environment,
            failurePrefix: failurePrefix
        )
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let message = [stderr, stdout]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            throw AppServerError.internalError(
                "\(failurePrefix): failed to unpack remote plugin bundle entry: \(message)"
            )
        }
    }

    private static func validateRemotePluginBundleArchive(
        archivePath: URL,
        environment: [String: String],
        failurePrefix: String
    ) throws {
        let listing = try remotePluginBundleArchiveListing(
            archivePath: archivePath,
            environment: environment,
            failurePrefix: failurePrefix
        )
        var extractedBytes = 0
        let maxExtractedBytes = 250 * 1024 * 1024
        for line in listing.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) {
            try validateRemotePluginBundleArchiveEntry(
                line,
                extractedBytes: &extractedBytes,
                maxExtractedBytes: maxExtractedBytes,
                failurePrefix: failurePrefix
            )
        }
    }

    private static func remotePluginBundleArchiveListing(
        archivePath: URL,
        environment: [String: String],
        failurePrefix: String
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-tvzf", archivePath.path]
        process.environment = environment
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()
        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let message = [stderr, stdout]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            throw AppServerError.internalError(
                "\(failurePrefix): failed to read remote plugin bundle tar: \(message)"
            )
        }
        return stdout
    }

    private static func validateRemotePluginBundleArchiveEntry(
        _ line: String,
        extractedBytes: inout Int,
        maxExtractedBytes: Int,
        failurePrefix: String
    ) throws {
        let fields = line.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: true).map(String.init)
        guard fields.count >= 9,
              let mode = fields.first,
              let entryType = mode.first,
              let entrySize = Int(fields[4])
        else {
            throw AppServerError.internalError(
                "\(failurePrefix): failed to read remote plugin bundle tar entry"
            )
        }
        let entryPath = fields[8].components(separatedBy: " -> ").first ?? fields[8]
        if entryType == "l" || entryType == "h" {
            throw AppServerError.internalError(
                "\(failurePrefix): remote plugin bundle tar entry `\(entryPath)` is a link"
            )
        }
        guard entryType == "d" || entryType == "-" else {
            throw AppServerError.internalError(
                "\(failurePrefix): remote plugin bundle tar entry `\(entryPath)` has unsupported type \(entryType)"
            )
        }
        try validateRemotePluginBundleEntryPath(entryPath, failurePrefix: failurePrefix)
        if entryType == "-" {
            let nextTotal = extractedBytes + entrySize
            if nextTotal > maxExtractedBytes {
                throw AppServerError.internalError(
                    "\(failurePrefix): remote plugin bundle extracted size would be \(nextTotal) bytes, exceeding the maximum total size of \(maxExtractedBytes) bytes"
                )
            }
            extractedBytes = nextTotal
        }
    }

    private static func validateRemotePluginBundleEntryPath(
        _ entryPath: String,
        failurePrefix: String
    ) throws {
        let normalized = entryPath
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = normalized
            .split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { $0 != "." }
        if components.isEmpty {
            return
        }
        if entryPath.hasPrefix("/") || components.contains("..") || components.contains("") {
            throw AppServerError.internalError(
                "\(failurePrefix): remote plugin bundle tar entry `\(entryPath)` escapes extraction root"
            )
        }
    }

    private static func extractedRemotePluginRoot(
        extractionRoot: URL,
        failurePrefix: String
    ) throws -> URL {
        if localPluginManifest(root: extractionRoot).name != nil {
            return extractionRoot
        }
        throw AppServerError.internalError(
            "\(failurePrefix): remote plugin bundle did not contain a standard plugin root with plugin.json"
        )
    }

    private static func localPluginInstallResult(
        marketplacePath: String,
        pluginName: String,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        let configFile = configuration.codexHome.appendingPathComponent("config.toml", isDirectory: false)
        var config = try CodexConfigLayerLoader.readConfig(from: configFile) ?? .table([:])
        let manifestPath = URL(fileURLWithPath: marketplacePath, isDirectory: false)
        let marketplace = try pluginMarketplaceEntry(manifestPath: manifestPath, config: config)
        let marketplaceName = marketplace["name"] as? String ?? ""
        let summaries = marketplace["plugins"] as? [[String: Any]] ?? []
        guard let summary = summaries.first(where: { $0["name"] as? String == pluginName }),
              let source = summary["source"] as? [String: Any]
        else {
            throw AppServerError.invalidRequest(
                "plugin `\(pluginName)` was not found in marketplace `\(marketplaceName)`"
            )
        }
        do {
            let materialized = try materializePluginInstallSource(
                source,
                codexHome: configuration.codexHome,
                environment: configuration.environment
            )
            defer {
                if let cleanupRoot = materialized.cleanupRoot,
                   FileManager.default.fileExists(atPath: cleanupRoot.path) {
                    try? FileManager.default.removeItem(at: cleanupRoot)
                }
            }
            guard isDirectory(materialized.path) else {
                throw AppServerError.invalidRequest("path does not exist or is not a directory")
            }
            let installedPath = try installLocalPluginCacheEntry(
                sourcePath: materialized.path,
                pluginName: pluginName,
                marketplaceName: marketplaceName,
                codexHome: configuration.codexHome
            )
            setLocalPluginEnabled(id: "\(pluginName)@\(marketplaceName)", enabled: true, in: &config)
            try renderConfigToml(config).write(to: configFile, atomically: true, encoding: .utf8)
            let appsNeedingAuth = pluginAppsNeedingAuthForInstall(
                installedPath: installedPath,
                runtimeConfig: try pluginRuntimeConfig(configuration: configuration),
                configuration: configuration,
                auth: try? currentAuth(configuration: configuration)
            )
            let summaryPolicy = summary["authPolicy"] as? String
            return [
                "authPolicy": summaryPolicy ?? "ON_INSTALL",
                "appsNeedingAuth": appsNeedingAuth
            ]
        } catch let error as AppServerError {
            throw error
        } catch {
            throw AppServerError.internalError("failed to install local plugin: \(error)")
        }
    }

    private static func materializePluginInstallSource(
        _ source: [String: Any],
        codexHome: URL,
        environment: [String: String]
    ) throws -> MaterializedMarketplacePluginSource {
        let sourceType = source["type"] as? String
        if sourceType == "local",
           let path = source["path"] as? String {
            return MaterializedMarketplacePluginSource(
                path: URL(fileURLWithPath: path, isDirectory: true),
                cleanupRoot: nil
            )
        }
        if sourceType == "git",
           let url = source["url"] as? String {
            return try materializeMarketplacePluginSource(
                .git(
                    url: url,
                    path: source["path"] as? String,
                    refName: source["refName"] as? String,
                    sha: source["sha"] as? String
                ),
                codexHome: codexHome,
                environment: environment
            )
        }
        throw AppServerError.invalidRequest("path does not exist or is not a directory")
    }

    private struct ConfiguredLocalPluginID {
        let key: String
        let pluginName: String
        let marketplaceName: String
    }

    private static func refreshNonCuratedPluginCache(
        codexHome: URL,
        roots: [URL],
        environment: [String: String],
        forceReinstall: Bool
    ) throws -> Bool {
        let configFile = codexHome.appendingPathComponent("config.toml", isDirectory: false)
        let config = try CodexConfigLayerLoader.readConfig(from: configFile) ?? .table([:])
        let configuredPluginIDs = configuredNonCuratedPluginIDs(in: config)
        guard !configuredPluginIDs.isEmpty else {
            return false
        }

        let configuredKeys = Set(configuredPluginIDs.map(\.key))
        var pluginSources: [String: MarketplacePluginSource] = [:]
        for manifestPath in localMarketplaceManifestPaths(from: roots) {
            let marketplaceRoot = try marketplaceRoot(forManifestPath: manifestPath)
            let data = try Data(contentsOf: manifestPath)
            let object = try marketplaceManifestObject(data: data, manifestPath: manifestPath)
            guard let marketplaceName = object["name"] as? String,
                  marketplaceName != "openai-curated",
                  let plugins = object["plugins"] as? [[String: Any]]
            else {
                continue
            }
            for plugin in plugins {
                guard let pluginName = plugin["name"] as? String else {
                    continue
                }
                let key = "\(pluginName)@\(marketplaceName)"
                guard configuredKeys.contains(key),
                      pluginSources[key] == nil,
                      let source = marketplacePluginSource(plugin["source"], marketplaceRoot: marketplaceRoot)
                else {
                    continue
                }
                pluginSources[key] = source
            }
        }

        var refreshed = false
        for pluginID in configuredPluginIDs {
            guard let source = pluginSources[pluginID.key] else {
                continue
            }
            let materialized = try materializeMarketplacePluginSource(
                source,
                codexHome: codexHome,
                environment: environment
            )
            defer {
                if let cleanupRoot = materialized.cleanupRoot,
                   FileManager.default.fileExists(atPath: cleanupRoot.path) {
                    try? FileManager.default.removeItem(at: cleanupRoot)
                }
            }
            let sourcePath = materialized.path
            let version = try localPluginCacheVersion(
                sourcePath: sourcePath,
                pluginName: pluginID.pluginName
            )
            if !forceReinstall,
               activeLocalPluginVersion(id: pluginID.key, codexHome: codexHome) == version {
                continue
            }
            _ = try installLocalPluginCacheEntry(
                sourcePath: sourcePath,
                pluginName: pluginID.pluginName,
                marketplaceName: pluginID.marketplaceName,
                codexHome: codexHome,
                version: version
            )
            refreshed = true
        }
        return refreshed
    }

    private struct MaterializedMarketplacePluginSource {
        let path: URL
        let cleanupRoot: URL?
    }

    private static func materializeMarketplacePluginSource(
        _ source: MarketplacePluginSource,
        codexHome: URL,
        environment: [String: String]
    ) throws -> MaterializedMarketplacePluginSource {
        switch source {
        case .local(let path):
            return MaterializedMarketplacePluginSource(path: path, cleanupRoot: nil)
        case .git(let url, let path, let refName, let sha):
            let stagingRoot = codexHome
                .appendingPathComponent("plugins", isDirectory: true)
                .appendingPathComponent(".marketplace-plugin-source-staging", isDirectory: true)
            let checkoutRoot = stagingRoot.appendingPathComponent(
                "marketplace-plugin-source-\(UUID().uuidString)",
                isDirectory: true
            )
            try cloneGitPluginSource(
                url: url,
                refName: refName,
                sha: sha,
                sparseCheckoutPath: path,
                destination: checkoutRoot,
                environment: environment
            )
            let materializedPath = path.map {
                checkoutRoot.appendingPathComponent($0, isDirectory: true).standardizedFileURL
            } ?? checkoutRoot.standardizedFileURL
            return MaterializedMarketplacePluginSource(path: materializedPath, cleanupRoot: checkoutRoot)
        }
    }

    private static func cloneGitPluginSource(
        url: String,
        refName: String?,
        sha: String?,
        sparseCheckoutPath: String?,
        destination: URL,
        environment: [String: String]
    ) throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let sparseCheckoutPath {
            _ = try runMarketplaceGit(
                ["clone", "--filter=blob:none", "--sparse", "--no-checkout", url, destination.path],
                cwd: nil,
                environment: environment
            )
            _ = try runMarketplaceGit(
                ["sparse-checkout", "set", "--no-cone", "--", sparseCheckoutPath],
                cwd: destination,
                environment: environment
            )
        } else {
            _ = try runMarketplaceGit(
                ["clone", url, destination.path],
                cwd: nil,
                environment: environment
            )
        }
        if let target = sha ?? refName {
            _ = try runMarketplaceGit(
                ["checkout", target],
                cwd: destination,
                environment: environment
            )
        } else if sparseCheckoutPath != nil {
            _ = try runMarketplaceGit(
                ["checkout"],
                cwd: destination,
                environment: environment
            )
        }
    }

    private static func configuredNonCuratedPluginIDs(in config: ConfigValue) -> [ConfiguredLocalPluginID] {
        guard let root = configTable(config),
              let plugins = root["plugins"].flatMap(configTable)
        else {
            return []
        }
        return plugins.keys.sorted().compactMap { key in
            let parts = key.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2,
                  !parts[0].isEmpty,
                  !parts[1].isEmpty,
                  parts[1] != "openai-curated"
            else {
                return nil
            }
            return ConfiguredLocalPluginID(key: key, pluginName: parts[0], marketplaceName: parts[1])
        }
    }

    private static func localPluginCacheVersion(sourcePath: URL, pluginName: String) throws -> String {
        let manifest = localPluginManifest(root: sourcePath)
        guard manifest.name != nil else {
            throw AppServerError.invalidRequest("missing or invalid plugin.json")
        }
        guard manifest.name == pluginName else {
            throw AppServerError.invalidRequest(
                "plugin.json name `\(manifest.name ?? "")` does not match marketplace plugin name `\(pluginName)`"
            )
        }
        let version = manifest.version?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if version.isEmpty {
            return "local"
        }
        guard isValidPluginVersionSegment(version) else {
            throw AppServerError.invalidRequest(
                "invalid plugin version: only ASCII letters, digits, `.`, `+`, `_`, and `-` are allowed"
            )
        }
        return version
    }

    private static func installLocalPluginCacheEntry(
        sourcePath: URL,
        pluginName: String,
        marketplaceName: String,
        codexHome: URL,
        version: String? = nil
    ) throws -> URL {
        let pluginVersion = try version ?? localPluginCacheVersion(sourcePath: sourcePath, pluginName: pluginName)
        let pluginBaseRoot = codexHome
            .appendingPathComponent("plugins/cache", isDirectory: true)
            .appendingPathComponent(marketplaceName, isDirectory: true)
            .appendingPathComponent(pluginName, isDirectory: true)
        let targetRoot = pluginBaseRoot.appendingPathComponent(pluginVersion, isDirectory: true)
        let parent = pluginBaseRoot.deletingLastPathComponent()
        let stagingContainer = parent.appendingPathComponent("plugin-install-\(UUID().uuidString)", isDirectory: true)
        let stagedRoot = stagingContainer.appendingPathComponent(pluginName, isDirectory: true)
        let stagedVersionRoot = stagedRoot.appendingPathComponent(pluginVersion, isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        do {
            try FileManager.default.createDirectory(
                at: stagedVersionRoot.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: sourcePath, to: stagedVersionRoot)
            if FileManager.default.fileExists(atPath: pluginBaseRoot.path) {
                let backupContainer = parent.appendingPathComponent("plugin-backup-\(UUID().uuidString)", isDirectory: true)
                let backupRoot = backupContainer.appendingPathComponent(pluginName, isDirectory: true)
                try FileManager.default.createDirectory(at: backupContainer, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: pluginBaseRoot, to: backupRoot)
                do {
                    try FileManager.default.moveItem(at: stagedRoot, to: pluginBaseRoot)
                    try? FileManager.default.removeItem(at: backupContainer)
                } catch {
                    try? FileManager.default.moveItem(at: backupRoot, to: pluginBaseRoot)
                    throw error
                }
            } else {
                try FileManager.default.moveItem(at: stagedRoot, to: pluginBaseRoot)
            }
        } catch {
            if FileManager.default.fileExists(atPath: stagingContainer.path) {
                try? FileManager.default.removeItem(at: stagingContainer)
            }
            throw error
        }
        try? FileManager.default.removeItem(at: stagingContainer)
        return targetRoot
    }

    private static func isValidPluginVersionSegment(_ version: String) -> Bool {
        guard !version.isEmpty, version != ".", version != ".." else {
            return false
        }
        return version.allSatisfy { character in
            character.isASCII
                && (character.isLetter
                    || character.isNumber
                    || character == "."
                    || character == "+"
                    || character == "_"
                    || character == "-")
        }
    }

    fileprivate static func pluginUninstallResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        let pluginID = try rustRequiredStringParam(params?["pluginId"], field: "pluginId")
        guard isValidRemotePluginID(pluginID) || isLikelyLocalPluginID(pluginID) else {
            throw AppServerError.invalidRequest("invalid remote plugin id")
        }
        if isValidRemotePluginID(pluginID) {
            try remotePluginUninstall(pluginID: pluginID, configuration: configuration)
            return [:]
        }
        try localPluginUninstall(pluginID: pluginID, configuration: configuration)
        return [:]
    }

    private static func remotePluginUninstall(
        pluginID: String,
        configuration: CodexAppServerConfiguration
    ) throws {
        let runtimeConfig = try pluginRuntimeConfig(configuration: configuration)
        guard runtimeConfig.features.isEnabled(.plugins) else {
            throw AppServerError.invalidRequest("remote plugin uninstall is not enabled")
        }
        guard let auth = try? currentAuth(configuration: configuration),
              case .chatGPT = auth.kind
        else {
            throw AppServerError.invalidRequest("uninstall remote plugin: chatgpt authentication required for remote plugin catalog")
        }
        let detail = try remotePluginObject(
            path: "/ps/plugins/\(pluginID)",
            queryItems: [],
            runtimeConfig: runtimeConfig,
            configuration: configuration,
            auth: auth,
            failurePrefix: "uninstall remote plugin"
        )
        let pluginName = detail["name"] as? String ?? pluginID
        let marketplaceName = remotePluginMarketplaceName(forScope: detail["scope"] as? String ?? "GLOBAL")
        let response = try remotePluginObject(
            path: "/plugins/\(pluginID)/uninstall",
            queryItems: [],
            runtimeConfig: runtimeConfig,
            configuration: configuration,
            auth: auth,
            failurePrefix: "uninstall remote plugin",
            method: "POST"
        )
        if let responsePluginID = response["id"] as? String, responsePluginID != pluginID {
            throw AppServerError.internalError(
                "uninstall remote plugin: remote plugin mutation returned unexpected plugin id: expected `\(pluginID)`, got `\(responsePluginID)`"
            )
        }
        if let enabled = response["enabled"] as? Bool, enabled {
            throw AppServerError.internalError(
                "uninstall remote plugin: remote plugin mutation returned unexpected enabled state for `\(pluginID)`: expected false, got true"
            )
        }
        _ = refreshRemoteInstalledPluginCachesAfterMutation(
            runtimeConfig: runtimeConfig,
            configuration: configuration,
            auth: auth
        )
        do {
            try removeRemotePluginCache(
                codexHome: configuration.codexHome,
                marketplaceName: marketplaceName,
                pluginName: pluginName,
                legacyPluginID: pluginID
            )
        } catch {
            throw AppServerError.internalError("uninstall remote plugin: \(error)")
        }
    }

    private static func removeRemotePluginCache(
        codexHome: URL,
        marketplaceName: String,
        pluginName: String,
        legacyPluginID: String
    ) throws {
        let cacheRoot = codexHome.appendingPathComponent("plugins/cache", isDirectory: true)
        let pluginRoot = cacheRoot
            .appendingPathComponent(marketplaceName, isDirectory: true)
            .appendingPathComponent(pluginName, isDirectory: true)
        if FileManager.default.fileExists(atPath: pluginRoot.path) {
            try FileManager.default.removeItem(at: pluginRoot)
        }
        let legacyRoot = cacheRoot
            .appendingPathComponent(marketplaceName, isDirectory: true)
            .appendingPathComponent(legacyPluginID, isDirectory: true)
        if FileManager.default.fileExists(atPath: legacyRoot.path) {
            try FileManager.default.removeItem(at: legacyRoot)
        }
    }

    private static func localPluginUninstall(
        pluginID: String,
        configuration: CodexAppServerConfiguration
    ) throws {
        let parts = pluginID.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            throw AppServerError.invalidRequest("invalid remote plugin id")
        }
        let pluginName = parts[0]
        let marketplaceName = parts[1]
        let cacheRoot = configuration.codexHome
            .appendingPathComponent("plugins/cache", isDirectory: true)
            .appendingPathComponent(marketplaceName, isDirectory: true)
            .appendingPathComponent(pluginName, isDirectory: true)
        do {
            if FileManager.default.fileExists(atPath: cacheRoot.path) {
                try FileManager.default.removeItem(at: cacheRoot)
            }
            let configFile = configuration.codexHome.appendingPathComponent("config.toml", isDirectory: false)
            var config = try CodexConfigLayerLoader.readConfig(from: configFile) ?? .table([:])
            removeLocalPluginConfig(id: pluginID, from: &config)
            try renderConfigToml(config).write(to: configFile, atomically: true, encoding: .utf8)
        } catch {
            throw AppServerError.internalError("failed to uninstall local plugin: \(error)")
        }
    }

    fileprivate static func marketplaceUpgradeResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        let stack = try CodexConfigLayerLoader.loadConfigLayerStack(
            codexHome: configuration.codexHome,
            cliOverrides: configuration.cliConfigOverrides,
            overrides: configuration.configLayerOverrides,
            environment: configuration.environment
        )
        let configuredGitMarketplaces = configuredGitMarketplaces(in: stack)
        if let marketplaceName = stringParam(params?["marketplaceName"]),
           !configuredGitMarketplaces.contains(where: { $0.name == marketplaceName }) {
            throw AppServerError.invalidRequest(
                "marketplace `\(marketplaceName)` is not configured as a Git marketplace"
            )
        }

        let marketplaceName = stringParam(params?["marketplaceName"])
        let selectedMarketplaces = configuredGitMarketplaces
            .filter { marketplaceName == nil || $0.name == marketplaceName }
        if selectedMarketplaces.isEmpty {
            return [
                "selectedMarketplaces": [],
                "upgradedRoots": [],
                "errors": []
            ]
        }

        let outcome = try marketplaceUpgradeGitResult(
            marketplaces: selectedMarketplaces,
            configuration: configuration
        )
        var errors = outcome.errors
        if !outcome.upgradedRoots.isEmpty {
            do {
                _ = try refreshNonCuratedPluginCache(
                    codexHome: configuration.codexHome,
                    roots: outcome.upgradedRoots.map { URL(fileURLWithPath: $0, isDirectory: true) },
                    environment: configuration.environment,
                    forceReinstall: true
                )
            } catch {
                errors.append([
                    "marketplaceName": marketplaceName ?? "all configured marketplaces",
                    "message": "failed to refresh installed plugin cache after marketplace upgrade: \(error)"
                ])
            }
        }
        return [
            "selectedMarketplaces": selectedMarketplaces.map(\.name),
            "upgradedRoots": outcome.upgradedRoots,
            "errors": errors
        ]
    }

    public static func marketplaceUpgradeCommandResult(
        marketplaceName: String?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        var params: [String: Any] = [:]
        if let marketplaceName {
            params["marketplaceName"] = marketplaceName
        }
        return try marketplaceUpgradeResult(params: params, configuration: configuration)
    }

    private static func marketplaceUpgradeGitResult(
        marketplaces: [ConfiguredGitMarketplace],
        configuration: CodexAppServerConfiguration
    ) throws -> (upgradedRoots: [String], errors: [[String: String]]) {
        let installRoot = configuration.codexHome
            .appendingPathComponent(".tmp", isDirectory: true)
            .appendingPathComponent("marketplaces", isDirectory: true)
        var upgradedRoots: [String] = []
        var errors: [[String: String]] = []

        for marketplace in marketplaces {
            do {
                if let upgradedRoot = try upgradeConfiguredGitMarketplace(
                    marketplace,
                    codexHome: configuration.codexHome,
                    installRoot: installRoot,
                    environment: configuration.environment
                ) {
                    upgradedRoots.append(upgradedRoot)
                }
            } catch let error as AppServerError {
                errors.append([
                    "marketplaceName": marketplace.name,
                    "message": error.description
                ])
            } catch {
                errors.append([
                    "marketplaceName": marketplace.name,
                    "message": "\(error)"
                ])
            }
        }

        return (upgradedRoots, errors)
    }

    fileprivate static func marketplaceRemoveResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        let marketplaceName = stringParam(params?["marketplaceName"]) ?? ""
        try validatePluginSegment(marketplaceName, kind: "marketplace name")

        let configFile = configuration.codexHome.appendingPathComponent("config.toml", isDirectory: false)
        var config = try CodexConfigLayerLoader.readConfig(from: configFile) ?? .table([:])
        let removedConfig = try removeMarketplaceConfig(named: marketplaceName, from: &config)
        if removedConfig {
            try renderConfigToml(config).write(to: configFile, atomically: true, encoding: .utf8)
        }

        let installedRoot = configuration.codexHome
            .appendingPathComponent(".tmp", isDirectory: true)
            .appendingPathComponent("marketplaces", isDirectory: true)
            .appendingPathComponent(marketplaceName, isDirectory: true)
            .standardizedFileURL
        let removedInstalledRoot = try removeMarketplaceInstalledRoot(installedRoot)
        if removedInstalledRoot == nil && !removedConfig {
            throw AppServerError.invalidRequest("marketplace `\(marketplaceName)` is not configured or installed")
        }

        return [
            "marketplaceName": marketplaceName,
            "installedRoot": nullable(removedInstalledRoot)
        ]
    }

    public static func marketplaceRemoveCommandResult(
        marketplaceName: String,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        try marketplaceRemoveResult(params: ["marketplaceName": marketplaceName], configuration: configuration)
    }

    fileprivate static func marketplaceAddResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        let source = stringParam(params?["source"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let refName = stringParam(params?["refName"])
        let sparsePaths = stringArrayParam(params?["sparsePaths"]) ?? []
        guard !source.isEmpty else {
            throw AppServerError.invalidRequest("marketplace source must not be empty")
        }

        let parsed = try parseMarketplaceSource(source, explicitRef: refName)
        if !sparsePaths.isEmpty && parsed.kind != .git {
            throw AppServerError.invalidRequest("--sparse is only supported for git marketplace sources")
        }
        if parsed.kind == .git {
            guard let gitURL = parsed.gitURL else {
                throw AppServerError.invalidRequest(
                    "invalid marketplace source format; expected owner/repo, a git URL, or a local marketplace path"
                )
            }
            return try marketplaceAddGitResult(
                source: gitURL,
                refName: parsed.refName,
                sparsePaths: sparsePaths,
                configuration: configuration
            )
        }

        guard let sourcePath = parsed.localPath else {
            throw AppServerError.invalidRequest(
                "invalid marketplace source format; expected owner/repo, a git URL, or a local marketplace path"
            )
        }

        let marketplaceName = try validateLocalMarketplaceSourceRoot(sourcePath)
        if marketplaceName == "openai-curated" {
            throw AppServerError.invalidRequest(
                "marketplace 'openai-curated' is reserved and cannot be added from this source"
            )
        }

        let configFile = configuration.codexHome.appendingPathComponent("config.toml", isDirectory: false)
        var config = try CodexConfigLayerLoader.readConfig(from: configFile) ?? .table([:])
        if let existingRoot = configuredMarketplaceRootForLocalSource(sourcePath.path, in: config),
           (try? validateLocalMarketplaceSourceRoot(URL(fileURLWithPath: existingRoot, isDirectory: true))) != nil {
            try recordMarketplaceConfig(
                name: marketplaceName,
                sourceType: "local",
                source: sourcePath.path,
                refName: nil,
                sparsePaths: [],
                in: &config
            )
            try renderConfigToml(config).write(to: configFile, atomically: true, encoding: .utf8)
            return [
                "marketplaceName": marketplaceName,
                "installedRoot": existingRoot,
                "alreadyAdded": true
            ]
        }

        if let existingRoot = configuredMarketplaceRoot(named: marketplaceName, in: config),
           (try? validateLocalMarketplaceSourceRoot(URL(fileURLWithPath: existingRoot, isDirectory: true))) != nil {
            throw AppServerError.invalidRequest(
                "marketplace '\(marketplaceName)' is already added from a different source; remove it before adding this source"
            )
        }

        try recordMarketplaceConfig(
            name: marketplaceName,
            sourceType: "local",
            source: sourcePath.path,
            refName: nil,
            sparsePaths: [],
            in: &config
        )
        try renderConfigToml(config).write(to: configFile, atomically: true, encoding: .utf8)
        return [
            "marketplaceName": marketplaceName,
            "installedRoot": sourcePath.path,
            "alreadyAdded": false
        ]
    }

    public static func marketplaceAddCommandResult(
        source: String,
        refName: String?,
        sparsePaths: [String],
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        var params: [String: Any] = [
            "source": source,
            "sparsePaths": sparsePaths
        ]
        if let refName {
            params["refName"] = refName
        }
        return try marketplaceAddResult(params: params, configuration: configuration)
    }

    private static func marketplaceAddGitResult(
        source: String,
        refName: String?,
        sparsePaths: [String],
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        let configFile = configuration.codexHome.appendingPathComponent("config.toml", isDirectory: false)
        var config = try CodexConfigLayerLoader.readConfig(from: configFile) ?? .table([:])
        let installRoot = configuration.codexHome
            .appendingPathComponent(".tmp", isDirectory: true)
            .appendingPathComponent("marketplaces", isDirectory: true)
        if let existingRoot = configuredMarketplaceRootForGitSource(
            source: source,
            refName: refName,
            sparsePaths: sparsePaths,
            codexHome: configuration.codexHome,
            in: config
        ),
           (try? validateLocalMarketplaceSourceRoot(URL(fileURLWithPath: existingRoot, isDirectory: true))) != nil {
            let marketplaceName = try validateLocalMarketplaceSourceRoot(URL(fileURLWithPath: existingRoot, isDirectory: true))
            try recordMarketplaceConfig(
                name: marketplaceName,
                sourceType: "git",
                source: source,
                refName: refName,
                sparsePaths: sparsePaths,
                in: &config
            )
            try renderConfigToml(config).write(to: configFile, atomically: true, encoding: .utf8)
            return [
                "marketplaceName": marketplaceName,
                "installedRoot": existingRoot,
                "alreadyAdded": true
            ]
        }

        let stagingParent = installRoot.appendingPathComponent(".staging", isDirectory: true)
        let stagingRoot = stagingParent.appendingPathComponent("marketplace-add-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: stagingParent, withIntermediateDirectories: true)
            _ = try cloneGitMarketplace(
                source: source,
                refName: refName,
                sparsePaths: sparsePaths,
                destination: stagingRoot,
                environment: configuration.environment
            )
        } catch let error as AppServerError {
            throw error
        } catch {
            throw AppServerError.internalError("failed to stage marketplace source: \(error)")
        }
        defer {
            if FileManager.default.fileExists(atPath: stagingRoot.path) {
                try? FileManager.default.removeItem(at: stagingRoot)
            }
        }

        let marketplaceName = try validateLocalMarketplaceSourceRoot(stagingRoot)
        if marketplaceName == "openai-curated" {
            throw AppServerError.invalidRequest(
                "marketplace 'openai-curated' is reserved and cannot be added from this source"
            )
        }
        try validatePluginSegment(marketplaceName, kind: "marketplace name")
        let destination = try installRoot.appendingPathComponent(safeMarketplaceDirectoryName(marketplaceName), isDirectory: true)
        if FileManager.default.fileExists(atPath: destination.path)
            || configuredMarketplaceRootIsValid(named: marketplaceName, codexHome: configuration.codexHome, in: config) {
            throw AppServerError.invalidRequest(
                "marketplace '\(marketplaceName)' is already added from a different source; remove it before adding this source"
            )
        }
        do {
            try FileManager.default.createDirectory(at: installRoot, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: stagingRoot, to: destination)
            try recordMarketplaceConfig(
                name: marketplaceName,
                sourceType: "git",
                source: source,
                refName: refName,
                sparsePaths: sparsePaths,
                in: &config
            )
            try renderConfigToml(config).write(to: configFile, atomically: true, encoding: .utf8)
        } catch {
            if FileManager.default.fileExists(atPath: destination.path),
               !FileManager.default.fileExists(atPath: stagingRoot.path) {
                try? FileManager.default.moveItem(at: destination, to: stagingRoot)
            }
            throw AppServerError.internalError("failed to install marketplace at \(destination.path): \(error)")
        }

        return [
            "marketplaceName": marketplaceName,
            "installedRoot": destination.path,
            "alreadyAdded": false
        ]
    }

    fileprivate static func externalAgentConfigDetectResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        var items: [[String: Any]] = []
        if params?["includeHome"] as? Bool == true,
           let item = try detectExternalAgentConfig(cwd: nil, configuration: configuration) {
            items.append(item)
        }
        if params?["includeHome"] as? Bool == true,
           let item = try detectExternalAgentMcpServerConfig(cwd: nil, configuration: configuration) {
            items.append(item)
        }
        if params?["includeHome"] as? Bool == true,
           let item = try detectExternalAgentPlugins(cwd: nil, configuration: configuration) {
            items.append(item)
        }
        if params?["includeHome"] as? Bool == true,
           let item = try detectExternalAgentHooks(cwd: nil, configuration: configuration) {
            items.append(item)
        }
        if params?["includeHome"] as? Bool == true,
           let item = try detectExternalAgentSkills(cwd: nil, configuration: configuration) {
            items.append(item)
        }
        if params?["includeHome"] as? Bool == true,
           let item = try detectExternalAgentCommands(cwd: nil, configuration: configuration) {
            items.append(item)
        }
        if params?["includeHome"] as? Bool == true,
           let item = try detectExternalAgentSubagents(cwd: nil, configuration: configuration) {
            items.append(item)
        }
        if params?["includeHome"] as? Bool == true,
           let item = try detectExternalAgentAgentsMd(cwd: nil, configuration: configuration) {
            items.append(item)
        }
        if params?["includeHome"] as? Bool == true,
           let item = try detectExternalAgentSessions(configuration: configuration) {
            items.append(item)
        }
        for cwd in params?["cwds"] as? [String] ?? [] {
            guard let repoRoot = gitRepositoryRoot(containing: URL(fileURLWithPath: cwd, isDirectory: true)) else {
                continue
            }
            if let item = try detectExternalAgentConfig(cwd: repoRoot.path, configuration: configuration) {
                items.append(item)
            }
            if let item = try detectExternalAgentMcpServerConfig(cwd: repoRoot.path, configuration: configuration) {
                items.append(item)
            }
            if let item = try detectExternalAgentPlugins(cwd: repoRoot.path, configuration: configuration) {
                items.append(item)
            }
            if let item = try detectExternalAgentHooks(cwd: repoRoot.path, configuration: configuration) {
                items.append(item)
            }
            if let item = try detectExternalAgentSkills(cwd: repoRoot.path, configuration: configuration) {
                items.append(item)
            }
            if let item = try detectExternalAgentCommands(cwd: repoRoot.path, configuration: configuration) {
                items.append(item)
            }
            if let item = try detectExternalAgentSubagents(cwd: repoRoot.path, configuration: configuration) {
                items.append(item)
            }
            if let item = try detectExternalAgentAgentsMd(cwd: repoRoot.path, configuration: configuration) {
                items.append(item)
            }
        }
        return ["items": items]
    }

    fileprivate static func externalAgentConfigImportResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> (result: [String: Any], notifications: [[String: Any]]) {
        guard let items = params?["migrationItems"] as? [[String: Any]] else {
            throw AppServerError.invalidParams("externalAgentConfig/import migrationItems must be an array")
        }
        guard !items.isEmpty else {
            return ([:], [])
        }

        for item in items {
            guard let itemType = item["itemType"] as? String else {
                throw AppServerError.invalidParams("external agent migration item is missing itemType")
            }
            let cwd = stringParam(item["cwd"])
            switch itemType {
            case "AGENTS_MD":
                try importExternalAgentAgentsMd(cwd: cwd, configuration: configuration)
            case "COMMANDS":
                try importExternalAgentCommands(cwd: cwd, configuration: configuration)
            case "CONFIG":
                try importExternalAgentConfig(cwd: cwd, configuration: configuration)
            case "HOOKS":
                try importExternalAgentHooks(cwd: cwd, configuration: configuration)
            case "MCP_SERVER_CONFIG":
                try importExternalAgentMcpServerConfig(cwd: cwd, configuration: configuration)
            case "PLUGINS":
                try importExternalAgentPlugins(item: item, cwd: cwd, configuration: configuration)
            case "SESSIONS":
                try importExternalAgentSessions(item: item, configuration: configuration)
            case "SKILLS":
                try importExternalAgentSkills(cwd: cwd, configuration: configuration)
            case "SUBAGENTS":
                try importExternalAgentSubagents(cwd: cwd, configuration: configuration)
            default:
                throw AppServerError.invalidRequest(
                    "Invalid request: unknown variant `\(itemType)`, expected one of `AGENTS_MD`, `CONFIG`, `SKILLS`, `PLUGINS`, `MCP_SERVER_CONFIG`, `SUBAGENTS`, `HOOKS`, `COMMANDS`, `SESSIONS`"
                )
            }
        }

        return (
            [:],
            [[
                "method": "externalAgentConfig/import/completed",
                "params": [:]
            ]]
        )
    }

    private static func detectExternalAgentConfig(
        cwd: String?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any]? {
        let paths = externalAgentConfigPaths(cwd: cwd, configuration: configuration)
        guard let settings = try effectiveExternalAgentSettings(at: paths.sourceSettings) else {
            return nil
        }

        let migrated = try externalAgentConfigValue(from: settings)
        guard case let .table(migratedTable) = migrated, !migratedTable.isEmpty else {
            return nil
        }

        var existing: ConfigValue = .table([:])
        if FileManager.default.fileExists(atPath: paths.targetConfig.path) {
            let raw = try String(contentsOf: paths.targetConfig, encoding: .utf8)
            existing = raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? .table([:])
                : try parseExternalAgentTargetConfig(raw)
        }
        guard try mergeMissingConfigValues(into: &existing, incoming: migrated) else {
            return nil
        }

        var item: [String: Any] = [
            "itemType": "CONFIG",
            "description": "Migrate \(paths.sourceSettings.path) into \(paths.targetConfig.path)",
            "details": NSNull()
        ]
        item["cwd"] = paths.cwd.map { $0 as Any } ?? NSNull()
        return item
    }

    private static func detectExternalAgentHooks(
        cwd: String?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any]? {
        let paths = externalAgentHooksPaths(cwd: cwd, configuration: configuration)
        let migration = try externalAgentHookMigration(sourceExternalAgentDirectory: paths.sourceExternalAgentDirectory, targetConfigDirectory: paths.targetHooks.deletingLastPathComponent())
        let eventNames = migration.keys.sorted()
        guard !eventNames.isEmpty,
              try isMissingOrEmptyTextFile(paths.targetHooks)
        else {
            return nil
        }
        var item: [String: Any] = [
            "itemType": "HOOKS",
            "description": "Migrate hooks from \(paths.sourceExternalAgentDirectory.path) to \(paths.targetHooks.path)",
            "details": [
                "hooks": eventNames.map { ["name": $0] }
            ]
        ]
        item["cwd"] = paths.cwd.map { $0 as Any } ?? NSNull()
        return item
    }

    private static func detectExternalAgentMcpServerConfig(
        cwd: String?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any]? {
        let paths = try externalAgentMcpServerConfigPaths(cwd: cwd, configuration: configuration)
        let settings = try externalAgentMcpSettings(
            sourceSettings: paths.sourceSettings,
            repoRoot: paths.cwd.map { URL(fileURLWithPath: $0, isDirectory: true) },
            configuration: configuration
        )
        let migrated = try externalAgentMcpConfigValue(
            sourceRoot: paths.sourceRoot,
            externalAgentHome: paths.externalAgentHome,
            settings: settings
        )
        guard case let .table(root) = migrated,
              case let .table(servers)? = root["mcp_servers"],
              !servers.isEmpty
        else {
            return nil
        }

        var existing: ConfigValue = .table([:])
        if FileManager.default.fileExists(atPath: paths.targetConfig.path) {
            let raw = try String(contentsOf: paths.targetConfig, encoding: .utf8)
            existing = raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? .table([:])
                : try parseExternalAgentTargetConfig(raw)
        }
        guard try mergeMissingConfigValues(into: &existing, incoming: migrated) else {
            return nil
        }

        var item: [String: Any] = [
            "itemType": "MCP_SERVER_CONFIG",
            "description": "Migrate MCP servers from \(paths.sourceRoot.path) into \(paths.targetConfig.path)",
            "details": [
                "mcp_servers": servers.keys.sorted().map { ["name": $0] }
            ]
        ]
        item["cwd"] = paths.cwd.map { $0 as Any } ?? NSNull()
        return item
    }

    private static func detectExternalAgentPlugins(
        cwd: String?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any]? {
        let paths = try externalAgentMcpServerConfigPaths(cwd: cwd, configuration: configuration)
        guard let settings = try effectiveExternalAgentSettings(at: paths.sourceSettings) else {
            return nil
        }
        let details = try externalAgentPluginMigrationDetails(
            settings: settings,
            sourceRoot: paths.sourceRoot,
            configuration: configuration
        )
        guard !details.isEmpty else {
            return nil
        }
        var item: [String: Any] = [
            "itemType": "PLUGINS",
            "description": "Migrate enabled plugins from \(paths.sourceSettings.path)",
            "details": [
                "plugins": details.map {
                    [
                        "marketplaceName": $0.marketplaceName,
                        "pluginNames": $0.pluginNames
                    ] as [String: Any]
                }
            ]
        ]
        item["cwd"] = paths.cwd.map { $0 as Any } ?? NSNull()
        return item
    }

    private static func detectExternalAgentSessions(
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any]? {
        let externalAgentHome = externalAgentHome(configuration: configuration)
        let sessions = try detectRecentExternalAgentSessions(
            externalAgentHome: externalAgentHome,
            codexHome: configuration.codexHome
        )
        guard !sessions.isEmpty else {
            return nil
        }
        return [
            "itemType": "SESSIONS",
            "description": "Migrate recent sessions from \(externalAgentHome.appendingPathComponent("projects", isDirectory: true).path)",
            "cwd": NSNull(),
            "details": [
                "sessions": sessions.map { session in
                    [
                        "path": session.path.path,
                        "cwd": session.cwd.path,
                        "title": session.title as Any
                    ].nullStripped(keepNulls: true)
                }
            ]
        ]
    }

    private static func detectExternalAgentAgentsMd(
        cwd: String?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any]? {
        guard let paths = try externalAgentAgentsMdPaths(cwd: cwd, configuration: configuration),
              try isMissingOrEmptyTextFile(paths.targetAgentsMd)
        else {
            return nil
        }
        var item: [String: Any] = [
            "itemType": "AGENTS_MD",
            "description": "Migrate \(paths.sourceAgentsMd.path) to \(paths.targetAgentsMd.path)",
            "details": NSNull()
        ]
        item["cwd"] = paths.cwd.map { $0 as Any } ?? NSNull()
        return item
    }

    private static func detectExternalAgentSkills(
        cwd: String?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any]? {
        let paths = externalAgentSkillsPaths(cwd: cwd, configuration: configuration)
        guard try countMissingExternalAgentSkillDirectories(source: paths.sourceSkills, target: paths.targetSkills) > 0 else {
            return nil
        }
        var item: [String: Any] = [
            "itemType": "SKILLS",
            "description": "Migrate skills from \(paths.sourceSkills.path) to \(paths.targetSkills.path)",
            "details": NSNull()
        ]
        item["cwd"] = paths.cwd.map { $0 as Any } ?? NSNull()
        return item
    }

    private static func detectExternalAgentCommands(
        cwd: String?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any]? {
        let paths = externalAgentCommandsPaths(cwd: cwd, configuration: configuration)
        let names = try missingExternalAgentCommandSkillNames(sourceCommands: paths.sourceCommands, targetSkills: paths.targetSkills)
        guard !names.isEmpty else {
            return nil
        }
        var item: [String: Any] = [
            "itemType": "COMMANDS",
            "description": "Migrate commands from \(paths.sourceCommands.path) to \(paths.targetSkills.path)",
            "details": [
                "commands": names.map { ["name": $0] }
            ]
        ]
        item["cwd"] = paths.cwd.map { $0 as Any } ?? NSNull()
        return item
    }

    private static func detectExternalAgentSubagents(
        cwd: String?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any]? {
        let paths = externalAgentSubagentsPaths(cwd: cwd, configuration: configuration)
        let names = try missingExternalAgentSubagentNames(sourceAgents: paths.sourceAgents, targetAgents: paths.targetAgents)
        guard !names.isEmpty else {
            return nil
        }
        var item: [String: Any] = [
            "itemType": "SUBAGENTS",
            "description": "Migrate subagents from \(paths.sourceAgents.path) to \(paths.targetAgents.path)",
            "details": [
                "subagents": names.map { ["name": $0] }
            ]
        ]
        item["cwd"] = paths.cwd.map { $0 as Any } ?? NSNull()
        return item
    }

    private static func importExternalAgentConfig(cwd: String?, configuration: CodexAppServerConfiguration) throws {
        let paths: (sourceSettings: URL, targetConfig: URL, cwd: String?)
        if let cwd, !cwd.isEmpty,
           gitRepositoryRoot(containing: URL(fileURLWithPath: cwd, isDirectory: true)) == nil {
            return
        }
        paths = externalAgentConfigPaths(cwd: cwd, configuration: configuration)

        guard let settings = try effectiveExternalAgentSettings(at: paths.sourceSettings) else {
            return
        }

        let migrated = try externalAgentConfigValue(from: settings)
        guard case let .table(migratedTable) = migrated, !migratedTable.isEmpty else {
            return
        }

        let existing: ConfigValue
        if FileManager.default.fileExists(atPath: paths.targetConfig.path) {
            let raw = try String(contentsOf: paths.targetConfig, encoding: .utf8)
            existing = raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? .table([:])
                : try parseExternalAgentTargetConfig(raw)
        } else {
            existing = .table([:])
        }
        var next = existing
        guard try mergeMissingConfigValues(into: &next, incoming: migrated) else {
            return
        }
        try FileManager.default.createDirectory(
            at: paths.targetConfig.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try renderConfigToml(next).write(to: paths.targetConfig, atomically: true, encoding: .utf8)
    }

    private static func importExternalAgentHooks(cwd: String?, configuration: CodexAppServerConfiguration) throws {
        if let cwd, !cwd.isEmpty,
           gitRepositoryRoot(containing: URL(fileURLWithPath: cwd, isDirectory: true)) == nil {
            return
        }
        let paths = externalAgentHooksPaths(cwd: cwd, configuration: configuration)
        let targetConfigDirectory = paths.targetHooks.deletingLastPathComponent()
        let migration = try externalAgentHookMigration(
            sourceExternalAgentDirectory: paths.sourceExternalAgentDirectory,
            targetConfigDirectory: targetConfigDirectory
        )
        guard !migration.isEmpty,
              try isMissingOrEmptyTextFile(paths.targetHooks)
        else {
            return
        }
        try FileManager.default.createDirectory(at: targetConfigDirectory, withIntermediateDirectories: true)
        try copyExternalAgentHookScripts(
            sourceExternalAgentDirectory: paths.sourceExternalAgentDirectory,
            targetConfigDirectory: targetConfigDirectory
        )
        let payload = ["hooks": migration]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        let rendered = String(data: data, encoding: .utf8) ?? "{}"
        try (rendered + "\n").write(to: paths.targetHooks, atomically: true, encoding: .utf8)
    }

    private static func importExternalAgentMcpServerConfig(cwd: String?, configuration: CodexAppServerConfiguration) throws {
        if let cwd, !cwd.isEmpty,
           gitRepositoryRoot(containing: URL(fileURLWithPath: cwd, isDirectory: true)) == nil {
            return
        }
        let paths = try externalAgentMcpServerConfigPaths(cwd: cwd, configuration: configuration)
        let settings = try externalAgentMcpSettings(
            sourceSettings: paths.sourceSettings,
            repoRoot: paths.cwd.map { URL(fileURLWithPath: $0, isDirectory: true) },
            configuration: configuration
        )
        let migrated = try externalAgentMcpConfigValue(
            sourceRoot: paths.sourceRoot,
            externalAgentHome: paths.externalAgentHome,
            settings: settings
        )
        guard case let .table(root) = migrated,
              case let .table(servers)? = root["mcp_servers"],
              !servers.isEmpty
        else {
            return
        }

        let existing: ConfigValue
        if FileManager.default.fileExists(atPath: paths.targetConfig.path) {
            let raw = try String(contentsOf: paths.targetConfig, encoding: .utf8)
            existing = raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? .table([:])
                : try parseExternalAgentTargetConfig(raw)
        } else {
            existing = .table([:])
        }
        var next = existing
        guard try mergeMissingConfigValues(into: &next, incoming: migrated) else {
            return
        }
        try FileManager.default.createDirectory(
            at: paths.targetConfig.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try renderConfigToml(next).write(to: paths.targetConfig, atomically: true, encoding: .utf8)
    }

    private static func importExternalAgentPlugins(
        item: [String: Any],
        cwd: String?,
        configuration: CodexAppServerConfiguration
    ) throws {
        if let cwd, !cwd.isEmpty,
           gitRepositoryRoot(containing: URL(fileURLWithPath: cwd, isDirectory: true)) == nil {
            return
        }
        let paths = try externalAgentMcpServerConfigPaths(cwd: cwd, configuration: configuration)
        guard let details = externalAgentPluginMigrationDetails(from: item["details"]) else {
            throw AppServerError.invalidRequest("plugins migration item is missing details")
        }
        guard let settings = try effectiveExternalAgentSettings(at: paths.sourceSettings) else {
            return
        }
        let importSources = externalAgentMarketplaceImportSources(settings: settings, sourceRoot: paths.sourceRoot)
        for group in details {
            guard let source = importSources[group.marketplaceName] else {
                continue
            }
            let marketplacePath: URL
            do {
                marketplacePath = try addExternalAgentMarketplace(source: source, configuration: configuration)
            } catch {
                continue
            }
            for pluginName in group.pluginNames {
                _ = try? localPluginInstallResult(
                    marketplacePath: marketplacePath.path,
                    pluginName: pluginName,
                    configuration: configuration
                )
            }
        }
    }

    private static func importExternalAgentSessions(
        item: [String: Any],
        configuration: CodexAppServerConfiguration
    ) throws {
        let requestedSessions = try externalAgentSessionMigrationDetails(from: item["details"])
        for session in requestedSessions {
            guard try externalAgentSessionSourcePath(
                session.path,
                configuration: configuration
            ) != nil
            else {
                throw AppServerError.invalidParams(
                    "external agent session was not detected for import: \(session.path.path)"
                )
            }
        }

        for session in requestedSessions {
            guard !externalAgentSessionImportLedgerContainsCurrentSource(
                codexHome: configuration.codexHome,
                sourcePath: session.path
            ),
                let imported = try loadExternalAgentSessionForImport(session.path),
                isDirectory(imported.cwd)
            else {
                continue
            }
            let importedThreadID = try importExternalAgentSession(imported, configuration: configuration)
            try recordExternalAgentImportedSession(
                codexHome: configuration.codexHome,
                sourcePath: session.path,
                importedThreadID: importedThreadID
            )
        }
    }

    private static func importExternalAgentAgentsMd(cwd: String?, configuration: CodexAppServerConfiguration) throws {
        if let cwd, !cwd.isEmpty,
           gitRepositoryRoot(containing: URL(fileURLWithPath: cwd, isDirectory: true)) == nil {
            return
        }
        guard let paths = try externalAgentAgentsMdPaths(cwd: cwd, configuration: configuration),
              try isMissingOrEmptyTextFile(paths.targetAgentsMd)
        else {
            return
        }
        try FileManager.default.createDirectory(
            at: paths.targetAgentsMd.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let contents = try String(contentsOf: paths.sourceAgentsMd, encoding: .utf8)
        try rewriteExternalAgentTerms(contents).write(to: paths.targetAgentsMd, atomically: true, encoding: .utf8)
    }

    private static func importExternalAgentCommands(cwd: String?, configuration: CodexAppServerConfiguration) throws {
        if let cwd, !cwd.isEmpty,
           gitRepositoryRoot(containing: URL(fileURLWithPath: cwd, isDirectory: true)) == nil {
            return
        }
        let paths = externalAgentCommandsPaths(cwd: cwd, configuration: configuration)
        guard isDirectory(path: paths.sourceCommands.path) else {
            return
        }
        try FileManager.default.createDirectory(at: paths.targetSkills, withIntermediateDirectories: true)
        for source in try supportedExternalAgentCommandSources(sourceCommands: paths.sourceCommands) {
            let target = paths.targetSkills.appendingPathComponent(source.name, isDirectory: true)
            guard !FileManager.default.fileExists(atPath: target.path),
                  let description = nonEmptyExternalAgentScalar(source.document.frontmatter["description"])
            else {
                continue
            }
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            try renderExternalAgentCommandSkill(
                body: source.document.body,
                name: source.name,
                description: description,
                sourceName: externalAgentCommandSourceName(sourceCommands: paths.sourceCommands, sourceFile: source.file)
            )
            .write(to: target.appendingPathComponent("SKILL.md", isDirectory: false), atomically: true, encoding: .utf8)
        }
    }

    private static func importExternalAgentSubagents(cwd: String?, configuration: CodexAppServerConfiguration) throws {
        if let cwd, !cwd.isEmpty,
           gitRepositoryRoot(containing: URL(fileURLWithPath: cwd, isDirectory: true)) == nil {
            return
        }
        let paths = externalAgentSubagentsPaths(cwd: cwd, configuration: configuration)
        guard isDirectory(path: paths.sourceAgents.path) else {
            return
        }
        try FileManager.default.createDirectory(at: paths.targetAgents, withIntermediateDirectories: true)
        for sourceFile in try externalAgentSubagentSourceFiles(paths.sourceAgents) {
            let target = paths.targetAgents.appendingPathComponent(
                "\(sourceFile.deletingPathExtension().lastPathComponent).toml",
                isDirectory: false
            )
            guard !FileManager.default.fileExists(atPath: target.path) else {
                continue
            }
            let document = try parseExternalAgentCommandDocument(sourceFile)
            guard let metadata = externalAgentSubagentMetadata(document) else {
                continue
            }
            try renderExternalAgentSubagentToml(body: document.body, metadata: metadata)
                .write(to: target, atomically: true, encoding: .utf8)
        }
    }

    private static func importExternalAgentSkills(cwd: String?, configuration: CodexAppServerConfiguration) throws {
        if let cwd, !cwd.isEmpty,
           gitRepositoryRoot(containing: URL(fileURLWithPath: cwd, isDirectory: true)) == nil {
            return
        }
        let paths = externalAgentSkillsPaths(cwd: cwd, configuration: configuration)
        guard isDirectory(path: paths.sourceSkills.path) else {
            return
        }
        try FileManager.default.createDirectory(at: paths.targetSkills, withIntermediateDirectories: true)
        for name in try FileManager.default.contentsOfDirectory(atPath: paths.sourceSkills.path) {
            let source = paths.sourceSkills.appendingPathComponent(name, isDirectory: true)
            guard isDirectory(path: source.path) else {
                continue
            }
            let target = paths.targetSkills.appendingPathComponent(name, isDirectory: true)
            guard !FileManager.default.fileExists(atPath: target.path) else {
                continue
            }
            try copyExternalAgentSkillDirectory(source: source, target: target)
        }
    }

    private static func externalAgentConfigPaths(
        cwd: String?,
        configuration: CodexAppServerConfiguration
    ) -> (sourceSettings: URL, targetConfig: URL, cwd: String?) {
        if let cwd, !cwd.isEmpty,
           let repoRoot = gitRepositoryRoot(containing: URL(fileURLWithPath: cwd, isDirectory: true)) {
            return (
                sourceSettings: repoRoot
                    .appendingPathComponent(".claude", isDirectory: true)
                    .appendingPathComponent("settings.json", isDirectory: false),
                targetConfig: repoRoot
                    .appendingPathComponent(".codex", isDirectory: true)
                    .appendingPathComponent("config.toml", isDirectory: false),
                cwd: repoRoot.path
            )
        }
        let home = configuration.environment["HOME"].flatMap { value in
            value.isEmpty ? nil : URL(fileURLWithPath: value, isDirectory: true)
        } ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        return (
            sourceSettings: home
                .appendingPathComponent(".claude", isDirectory: true)
                .appendingPathComponent("settings.json", isDirectory: false),
            targetConfig: configuration.codexHome.appendingPathComponent("config.toml", isDirectory: false),
            cwd: nil
        )
    }

    private static func externalAgentHooksPaths(
        cwd: String?,
        configuration: CodexAppServerConfiguration
    ) -> (sourceExternalAgentDirectory: URL, targetHooks: URL, cwd: String?) {
        if let cwd, !cwd.isEmpty,
           let repoRoot = gitRepositoryRoot(containing: URL(fileURLWithPath: cwd, isDirectory: true)) {
            return (
                sourceExternalAgentDirectory: repoRoot.appendingPathComponent(".claude", isDirectory: true),
                targetHooks: repoRoot
                    .appendingPathComponent(".codex", isDirectory: true)
                    .appendingPathComponent("hooks.json", isDirectory: false),
                cwd: repoRoot.path
            )
        }
        let home = configuration.environment["HOME"].flatMap { value in
            value.isEmpty ? nil : URL(fileURLWithPath: value, isDirectory: true)
        } ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        return (
            sourceExternalAgentDirectory: home.appendingPathComponent(".claude", isDirectory: true),
            targetHooks: configuration.codexHome.appendingPathComponent("hooks.json", isDirectory: false),
            cwd: nil
        )
    }

    private static func externalAgentMcpServerConfigPaths(
        cwd: String?,
        configuration: CodexAppServerConfiguration
    ) throws -> (sourceSettings: URL, sourceRoot: URL, externalAgentHome: URL, targetConfig: URL, cwd: String?) {
        let configPaths = externalAgentConfigPaths(cwd: cwd, configuration: configuration)
        let externalAgentHome = configPaths.sourceSettings.deletingLastPathComponent()
        let sourceRoot: URL
        if let repoCwd = configPaths.cwd {
            sourceRoot = URL(fileURLWithPath: repoCwd, isDirectory: true)
        } else {
            sourceRoot = externalAgentHome.deletingLastPathComponent()
        }
        return (
            sourceSettings: configPaths.sourceSettings,
            sourceRoot: sourceRoot,
            externalAgentHome: externalAgentHome,
            targetConfig: configPaths.targetConfig,
            cwd: configPaths.cwd
        )
    }

    private static func externalAgentAgentsMdPaths(
        cwd: String?,
        configuration: CodexAppServerConfiguration
    ) throws -> (sourceAgentsMd: URL, targetAgentsMd: URL, cwd: String?)? {
        if let cwd, !cwd.isEmpty,
           let repoRoot = gitRepositoryRoot(containing: URL(fileURLWithPath: cwd, isDirectory: true)) {
            guard let source = try findRepoExternalAgentAgentsMdSource(repoRoot: repoRoot) else {
                return nil
            }
            return (
                sourceAgentsMd: source,
                targetAgentsMd: repoRoot.appendingPathComponent("AGENTS.md", isDirectory: false),
                cwd: repoRoot.path
            )
        }
        let home = configuration.environment["HOME"].flatMap { value in
            value.isEmpty ? nil : URL(fileURLWithPath: value, isDirectory: true)
        } ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let source = home
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("CLAUDE.md", isDirectory: false)
        guard try isNonEmptyTextFile(source) else {
            return nil
        }
        return (
            sourceAgentsMd: source,
            targetAgentsMd: configuration.codexHome.appendingPathComponent("AGENTS.md", isDirectory: false),
            cwd: nil
        )
    }

    private static func findRepoExternalAgentAgentsMdSource(repoRoot: URL) throws -> URL? {
        for candidate in [
            repoRoot.appendingPathComponent("CLAUDE.md", isDirectory: false),
            repoRoot
                .appendingPathComponent(".claude", isDirectory: true)
                .appendingPathComponent("CLAUDE.md", isDirectory: false)
        ] {
            if try isNonEmptyTextFile(candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func isMissingOrEmptyTextFile(_ path: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: path.path) else {
            return true
        }
        guard isRegularFile(path: path.path) else {
            return false
        }
        return try String(contentsOf: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func isNonEmptyTextFile(_ path: URL) throws -> Bool {
        guard isRegularFile(path: path.path) else {
            return false
        }
        return try !String(contentsOf: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func externalAgentHookMigration(
        sourceExternalAgentDirectory: URL,
        targetConfigDirectory: URL?
    ) throws -> [String: [[String: Any]]] {
        var settingsFiles: [[String: Any]] = []
        var disableAllHooks: Bool?
        for settingsName in ["settings.json", "settings.local.json"] {
            let settingsPath = sourceExternalAgentDirectory.appendingPathComponent(settingsName, isDirectory: false)
            guard isRegularFile(path: settingsPath.path) else {
                continue
            }
            let data = try Data(contentsOf: settingsPath)
            guard let settings = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AppServerError.internalError("invalid hooks settings: root must be an object")
            }
            if let disabled = settings["disableAllHooks"] as? Bool {
                disableAllHooks = disabled
            }
            settingsFiles.append(settings)
        }
        guard disableAllHooks != true else {
            return [:]
        }

        var migration: [String: [[String: Any]]] = [:]
        for settings in settingsFiles {
            appendConvertibleExternalAgentHookGroups(
                settings: settings,
                migration: &migration,
                targetConfigDirectory: targetConfigDirectory
            )
        }
        return migration
    }

    private static func appendConvertibleExternalAgentHookGroups(
        settings: [String: Any],
        migration: inout [String: [[String: Any]]],
        targetConfigDirectory: URL?
    ) {
        guard let hooksConfig = settings["hooks"] as? [String: Any] else {
            return
        }
        for eventName in HookEventName.allCases {
            let eventLabel = eventName.configLabel
            guard let groups = hooksConfig[eventLabel] as? [[String: Any]] else {
                continue
            }
            for group in groups {
                if group["if"] != nil ||
                    group.keys.contains(where: { !["matcher", "hooks"].contains($0) }) {
                    continue
                }
                var hookCommands: [[String: Any]] = []
                for hook in group["hooks"] as? [[String: Any]] ?? [] {
                    let hookType = hook["type"] as? String ?? "command"
                    guard hookType == "command",
                          !externalAgentHookHasUnsupportedKeys(hook),
                          hook["async"] as? Bool != true,
                          hook["asyncRewake"] == nil,
                          hook["shell"] == nil,
                          hook["once"] == nil,
                          let rawCommand = hook["command"] as? String
                    else {
                        continue
                    }
                    let command = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !command.isEmpty else {
                        continue
                    }
                    var commandPayload: [String: Any] = [
                        "type": "command",
                        "command": rewriteExternalAgentHookCommand(command, targetConfigDirectory: targetConfigDirectory)
                    ]
                    if let timeout = externalAgentHookUInt(hook["timeout"] ?? hook["timeoutSec"]) {
                        commandPayload["timeout"] = timeout
                    }
                    if let statusMessage = hook["statusMessage"] as? String {
                        commandPayload["statusMessage"] = rewriteExternalAgentTerms(statusMessage)
                    }
                    hookCommands.append(commandPayload)
                }
                guard !hookCommands.isEmpty else {
                    continue
                }
                var groupPayload: [String: Any] = ["hooks": hookCommands]
                if externalAgentHookEventSupportsMatcher(eventName),
                   let matcher = group["matcher"] as? String {
                    groupPayload["matcher"] = matcher
                }
                migration[eventLabel, default: []].append(groupPayload)
            }
        }
    }

    private static func externalAgentHookHasUnsupportedKeys(_ hook: [String: Any]) -> Bool {
        hook.keys.contains { key in
            !["type", "command", "timeout", "timeoutSec", "statusMessage", "async"].contains(key)
        }
    }

    private static func externalAgentHookUInt(_ value: Any?) -> UInt64? {
        switch value {
        case let value as UInt64:
            return value
        case let value as UInt:
            return UInt64(value)
        case let value as Int where value >= 0:
            return UInt64(value)
        case let value as NSNumber where value.int64Value >= 0:
            return UInt64(value.int64Value)
        case let value as String:
            return UInt64(value)
        default:
            return nil
        }
    }

    private static func externalAgentHookEventSupportsMatcher(_ eventName: HookEventName) -> Bool {
        switch eventName {
        case .preToolUse, .permissionRequest, .postToolUse, .preCompact, .postCompact, .sessionStart:
            return true
        case .userPromptSubmit, .stop:
            return false
        }
    }

    private static func rewriteExternalAgentHookCommand(_ command: String, targetConfigDirectory: URL?) -> String {
        guard let targetConfigDirectory else {
            return command
        }
        if command.contains(#".claude\hooks\"#) ||
            command.contains("%CLAUDE_PROJECT_DIR%") ||
            command.contains("$env:CLAUDE_PROJECT_DIR") {
            return command
        }
        let targetHooksDirectory = targetConfigDirectory.appendingPathComponent("hooks", isDirectory: true)
        let sourceHooksPath = ".claude/hooks/"
        var rewritten = replaceQuotedExternalAgentHookPaths(
            command,
            quote: "'",
            sourceHooksPath: sourceHooksPath,
            targetHooksDirectory: targetHooksDirectory
        )
        rewritten = replaceQuotedExternalAgentHookPaths(
            rewritten,
            quote: "\"",
            sourceHooksPath: sourceHooksPath,
            targetHooksDirectory: targetHooksDirectory
        )
        return replaceUnquotedExternalAgentHookPaths(
            rewritten,
            sourceHooksPath: sourceHooksPath,
            targetHooksDirectory: targetHooksDirectory
        )
    }

    private static func replaceQuotedExternalAgentHookPaths(
        _ command: String,
        quote: Character,
        sourceHooksPath: String,
        targetHooksDirectory: URL
    ) -> String {
        let pattern = "\(NSRegularExpression.escapedPattern(for: String(quote)))([^\\\(quote)]*?\(NSRegularExpression.escapedPattern(for: sourceHooksPath))([^\\\(quote)]*?))\(NSRegularExpression.escapedPattern(for: String(quote)))"
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return command
        }
        let nsCommand = command as NSString
        let matches = expression.matches(in: command, range: NSRange(location: 0, length: nsCommand.length)).reversed()
        var rewritten = command
        for match in matches {
            guard match.numberOfRanges >= 3,
                  let fullRange = Range(match.range(at: 0), in: rewritten),
                  let pathRange = Range(match.range(at: 1), in: rewritten),
                  let suffixRange = Range(match.range(at: 2), in: rewritten)
            else {
                continue
            }
            let path = String(rewritten[pathRange])
            let suffix = String(rewritten[suffixRange])
            guard let replacement = externalAgentHookPathReplacement(
                targetHooksDirectory: targetHooksDirectory,
                path: path,
                sourceHooksStart: path.distance(from: path.startIndex, to: path.range(of: sourceHooksPath)!.lowerBound),
                suffix: suffix
            ) else {
                continue
            }
            rewritten.replaceSubrange(fullRange, with: replacement)
        }
        return rewritten
    }

    private static func replaceUnquotedExternalAgentHookPaths(
        _ command: String,
        sourceHooksPath: String,
        targetHooksDirectory: URL
    ) -> String {
        let pattern = #"(?<![=\s;&|<>()])(\.?\.?/?(?:[^=\s;&|<>()]*?/)?\.claude/hooks/([^\s;&|<>()]+))"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return command
        }
        let nsCommand = command as NSString
        let matches = expression.matches(in: command, range: NSRange(location: 0, length: nsCommand.length)).reversed()
        var rewritten = command
        for match in matches {
            guard match.numberOfRanges >= 3,
                  let fullRange = Range(match.range(at: 1), in: rewritten),
                  let pathRange = Range(match.range(at: 1), in: rewritten),
                  let suffixRange = Range(match.range(at: 2), in: rewritten)
            else {
                continue
            }
            let path = String(rewritten[pathRange])
            let suffix = String(rewritten[suffixRange])
            guard let sourceRange = path.range(of: sourceHooksPath),
                  let replacement = externalAgentHookPathReplacement(
                    targetHooksDirectory: targetHooksDirectory,
                    path: path,
                    sourceHooksStart: path.distance(from: path.startIndex, to: sourceRange.lowerBound),
                    suffix: suffix
                  )
            else {
                continue
            }
            rewritten.replaceSubrange(fullRange, with: replacement)
        }
        return rewritten
    }

    private static func externalAgentHookPathReplacement(
        targetHooksDirectory: URL,
        path: String,
        sourceHooksStart: Int,
        suffix: String
    ) -> String? {
        let prefix = String(path.prefix(sourceHooksStart))
        guard (prefix.isEmpty || prefix == "./" || prefix.hasSuffix("/")),
              !prefix.contains(where: externalAgentShellPathBoundary),
              !suffix.isEmpty,
              !suffix.contains(where: { "\\$`*?[{}".contains($0) })
        else {
            return nil
        }
        return shellSingleQuote(targetHooksDirectory.appendingPathComponent(suffix).path)
    }

    private static func externalAgentShellPathBoundary(_ character: Character) -> Bool {
        character.isWhitespace || ["=", ";", "|", "&", "<", ">", "(", ")"].contains(character)
    }

    private static func shellSingleQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func copyExternalAgentHookScripts(sourceExternalAgentDirectory: URL, targetConfigDirectory: URL) throws {
        let sourceHooks = sourceExternalAgentDirectory.appendingPathComponent("hooks", isDirectory: true)
        guard isDirectory(path: sourceHooks.path) else {
            return
        }
        let targetHooks = targetConfigDirectory.appendingPathComponent("hooks", isDirectory: true)
        try copyDirectoryRecursiveSkippingExisting(source: sourceHooks, target: targetHooks)
    }

    private static func copyDirectoryRecursiveSkippingExisting(source: URL, target: URL) throws {
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        for name in try FileManager.default.contentsOfDirectory(atPath: source.path) {
            let sourcePath = source.appendingPathComponent(name)
            let targetPath = target.appendingPathComponent(name)
            if isDirectory(path: sourcePath.path) {
                try copyDirectoryRecursiveSkippingExisting(source: sourcePath, target: targetPath)
            } else if isRegularFile(path: sourcePath.path),
                      !FileManager.default.fileExists(atPath: targetPath.path) {
                try FileManager.default.copyItem(at: sourcePath, to: targetPath)
            }
        }
    }

    private static func externalAgentSkillsPaths(
        cwd: String?,
        configuration: CodexAppServerConfiguration
    ) -> (sourceSkills: URL, targetSkills: URL, cwd: String?) {
        if let cwd, !cwd.isEmpty,
           let repoRoot = gitRepositoryRoot(containing: URL(fileURLWithPath: cwd, isDirectory: true)) {
            return (
                sourceSkills: repoRoot
                    .appendingPathComponent(".claude", isDirectory: true)
                    .appendingPathComponent("skills", isDirectory: true),
                targetSkills: repoRoot
                    .appendingPathComponent(".agents", isDirectory: true)
                    .appendingPathComponent("skills", isDirectory: true),
                cwd: repoRoot.path
            )
        }
        let home = configuration.environment["HOME"].flatMap { value in
            value.isEmpty ? nil : URL(fileURLWithPath: value, isDirectory: true)
        } ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        return (
            sourceSkills: home
                .appendingPathComponent(".claude", isDirectory: true)
                .appendingPathComponent("skills", isDirectory: true),
            targetSkills: homeExternalAgentTargetSkillsDirectory(configuration: configuration),
            cwd: nil
        )
    }

    private static func externalAgentCommandsPaths(
        cwd: String?,
        configuration: CodexAppServerConfiguration
    ) -> (sourceCommands: URL, targetSkills: URL, cwd: String?) {
        let skillPaths = externalAgentSkillsPaths(cwd: cwd, configuration: configuration)
        return (
            sourceCommands: skillPaths.sourceSkills
                .deletingLastPathComponent()
                .appendingPathComponent("commands", isDirectory: true),
            targetSkills: skillPaths.targetSkills,
            cwd: skillPaths.cwd
        )
    }

    private static func externalAgentSubagentsPaths(
        cwd: String?,
        configuration: CodexAppServerConfiguration
    ) -> (sourceAgents: URL, targetAgents: URL, cwd: String?) {
        let skillPaths = externalAgentSkillsPaths(cwd: cwd, configuration: configuration)
        let sourceAgents = skillPaths.sourceSkills
            .deletingLastPathComponent()
            .appendingPathComponent("agents", isDirectory: true)
        let targetAgents: URL
        if let cwd = skillPaths.cwd {
            targetAgents = URL(fileURLWithPath: cwd, isDirectory: true)
                .appendingPathComponent(".codex", isDirectory: true)
                .appendingPathComponent("agents", isDirectory: true)
        } else {
            targetAgents = configuration.codexHome.appendingPathComponent("agents", isDirectory: true)
        }
        return (sourceAgents: sourceAgents, targetAgents: targetAgents, cwd: skillPaths.cwd)
    }

    private static func homeExternalAgentTargetSkillsDirectory(configuration: CodexAppServerConfiguration) -> URL {
        configuration.codexHome
            .deletingLastPathComponent()
            .appendingPathComponent(".agents", isDirectory: true)
            .appendingPathComponent("skills", isDirectory: true)
    }

    private static func countMissingExternalAgentSkillDirectories(source: URL, target: URL) throws -> Int {
        let sourceNames = try externalAgentSkillDirectoryNames(source)
        let targetNames = try externalAgentSkillDirectoryNames(target)
        return sourceNames.filter { !targetNames.contains($0) }.count
    }

    private static func externalAgentSkillDirectoryNames(_ root: URL) throws -> Set<String> {
        guard isDirectory(path: root.path) else {
            return []
        }
        var names: Set<String> = []
        for name in try FileManager.default.contentsOfDirectory(atPath: root.path) {
            if isDirectory(path: root.appendingPathComponent(name, isDirectory: true).path) {
                names.insert(name)
            }
        }
        return names
    }

    private static func missingExternalAgentCommandSkillNames(sourceCommands: URL, targetSkills: URL) throws -> [String] {
        try supportedExternalAgentCommandSources(sourceCommands: sourceCommands).compactMap { source in
            FileManager.default.fileExists(atPath: targetSkills.appendingPathComponent(source.name, isDirectory: true).path)
                ? nil
                : source.name
        }
    }

    private struct ExternalAgentCommandDocument {
        var frontmatter: [String: String]
        var body: String
    }

    private struct ExternalAgentCommandSource {
        var file: URL
        var name: String
        var document: ExternalAgentCommandDocument
    }

    private static func supportedExternalAgentCommandSources(sourceCommands: URL) throws -> [ExternalAgentCommandSource] {
        var byName: [String: [ExternalAgentCommandSource]] = [:]
        for file in try externalAgentCommandSourceFiles(sourceCommands) {
            let document = try parseExternalAgentCommandDocument(file)
            guard let name = externalAgentCommandSkillNameIfSupported(
                sourceCommands: sourceCommands,
                sourceFile: file,
                document: document
            ) else {
                continue
            }
            byName[name, default: []].append(ExternalAgentCommandSource(file: file, name: name, document: document))
        }
        return byName.keys.sorted().compactMap { name in
            guard byName[name]?.count == 1 else {
                return nil
            }
            return byName[name]?[0]
        }
    }

    private static func externalAgentCommandSourceFiles(_ sourceCommands: URL) throws -> [URL] {
        var files: [URL] = []
        try collectExternalAgentMarkdownFiles(in: sourceCommands, files: &files)
        return files.sorted { $0.path < $1.path }
    }

    private static func collectExternalAgentMarkdownFiles(in directory: URL, files: inout [URL]) throws {
        guard isDirectory(path: directory.path) else {
            return
        }
        for name in try FileManager.default.contentsOfDirectory(atPath: directory.path) {
            let path = directory.appendingPathComponent(name)
            if isDirectory(path: path.path) {
                try collectExternalAgentMarkdownFiles(in: path, files: &files)
            } else if isRegularFile(path: path.path), path.pathExtension == "md" {
                files.append(path)
            }
        }
    }

    private static func externalAgentCommandSkillNameIfSupported(
        sourceCommands: URL,
        sourceFile: URL,
        document: ExternalAgentCommandDocument
    ) -> String? {
        guard sourceFile.deletingPathExtension().lastPathComponent != "README" else {
            return nil
        }
        let sourceName = externalAgentCommandSourceName(sourceCommands: sourceCommands, sourceFile: sourceFile)
        guard let description = nonEmptyExternalAgentScalar(document.frontmatter["description"]) else {
            return nil
        }
        let name = slugifyExternalAgentName("source-command-\(sourceName)")
        guard name.count <= 64, description.count <= 1024 else {
            return nil
        }
        guard !hasUnsupportedExternalAgentCommandTemplateFeatures(document.body) else {
            return nil
        }
        return name
    }

    private static func externalAgentCommandSourceName(sourceCommands: URL, sourceFile: URL) -> String {
        let base = sourceCommands.standardizedFileURL.path
        var path = sourceFile.standardizedFileURL.deletingPathExtension().path
        if path == base {
            path = sourceFile.deletingPathExtension().lastPathComponent
        } else if path.hasPrefix(base + "/") {
            path.removeFirst(base.count + 1)
        }
        return path.split(separator: "/").map(String.init).joined(separator: "-")
    }

    private static func parseExternalAgentCommandDocument(_ sourceFile: URL) throws -> ExternalAgentCommandDocument {
        let content = try String(contentsOf: sourceFile, encoding: .utf8)
        let prefixLength: Int
        if content.hasPrefix("---\n") {
            prefixLength = 4
        } else if content.hasPrefix("---\r\n") {
            prefixLength = 5
        } else {
            return ExternalAgentCommandDocument(frontmatter: [:], body: content)
        }
        let restStart = content.index(content.startIndex, offsetBy: prefixLength)
        let rest = String(content[restStart...])
        guard let end = externalAgentFrontmatterEnd(in: rest) else {
            return ExternalAgentCommandDocument(frontmatter: [:], body: content)
        }
        let frontmatter = String(rest[..<end.rawEnd])
        let body = String(rest[end.bodyStart...])
        return ExternalAgentCommandDocument(frontmatter: parseScalarFrontmatter(frontmatter), body: body)
    }

    private static func externalAgentFrontmatterEnd(in rest: String) -> (rawEnd: String.Index, bodyStart: String.Index)? {
        let delimiters = ["\r\n---\r\n", "\r\n---\n", "\n---\r\n", "\n---\n", "\r\n---", "\n---"]
        return delimiters.compactMap { delimiter -> (rawEnd: String.Index, bodyStart: String.Index)? in
            guard let range = rest.range(of: delimiter) else {
                return nil
            }
            return (range.lowerBound, range.upperBound)
        }.min { left, right in
            left.rawEnd < right.rawEnd
        }
    }

    private static func parseScalarFrontmatter(_ frontmatter: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in frontmatter.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), let colon = line.firstIndex(of: ":") else {
                continue
            }
            let key = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                continue
            }
            let rawValue = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawValue.hasPrefix("["),
                  !rawValue.hasPrefix("{"),
                  rawValue != "null",
                  rawValue != "~"
            else {
                continue
            }
            result[key] = unquoteSimpleYAMLScalar(rawValue)
        }
        return result
    }

    private static func unquoteSimpleYAMLScalar(_ value: String) -> String {
        if value.count >= 2,
           let first = value.first,
           let last = value.last,
           (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    private static func nonEmptyExternalAgentScalar(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }

    private static func hasUnsupportedExternalAgentCommandTemplateFeatures(_ template: String) -> Bool {
        template.contains("$ARGUMENTS") ||
            containsNumberedExternalAgentArgumentPlaceholder(template) ||
            (template.contains("{{") && template.contains("}}")) ||
            template.contains("!`") ||
            template.contains("! `") ||
            template.split(whereSeparator: { $0.isWhitespace }).contains { token in
                token.hasPrefix("@") && token.count > 1
            }
    }

    private static func containsNumberedExternalAgentArgumentPlaceholder(_ template: String) -> Bool {
        let bytes = Array(template.utf8)
        guard bytes.count >= 2 else {
            return false
        }
        for index in 0..<(bytes.count - 1)
            where bytes[index] == UInt8(ascii: "$") &&
            bytes[index + 1] >= UInt8(ascii: "0") &&
            bytes[index + 1] <= UInt8(ascii: "9") {
            return true
        }
        return false
    }

    private static func renderExternalAgentCommandSkill(
        body: String,
        name: String,
        description: String,
        sourceName: String
    ) -> String {
        let rewrittenBody = rewriteExternalAgentTerms(body.trimmingCharacters(in: .whitespacesAndNewlines))
        let templateBody = rewrittenBody.isEmpty ? "No command template body was found." : rewrittenBody
        return """
        ---
        name: \(yamlExternalAgentString(name))
        description: \(yamlExternalAgentString(rewriteExternalAgentTerms(description)))
        ---

        # \(name)

        Use this skill when the user asks to run the migrated source command `\(sourceName)`.

        ## Command Template

        \(templateBody)

        """
    }

    private static func yamlExternalAgentString(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private static func slugifyExternalAgentName(_ value: String) -> String {
        var slug = ""
        var lastWasDash = false
        for scalar in value.unicodeScalars {
            if scalar.isASCII && CharacterSet.alphanumerics.contains(scalar) {
                slug.unicodeScalars.append(UnicodeScalar(String(scalar).lowercased())!)
                lastWasDash = false
            } else if !lastWasDash {
                slug.append("-")
                lastWasDash = true
            }
        }
        let trimmed = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "migrated" : trimmed
    }

    private struct ExternalAgentSubagentMetadata {
        var name: String
        var description: String
        var permissionMode: String?
        var effort: String?
    }

    private static func missingExternalAgentSubagentNames(sourceAgents: URL, targetAgents: URL) throws -> [String] {
        var names: [String] = []
        for sourceFile in try externalAgentSubagentSourceFiles(sourceAgents) {
            let document = try parseExternalAgentCommandDocument(sourceFile)
            guard let metadata = externalAgentSubagentMetadata(document) else {
                continue
            }
            let target = targetAgents.appendingPathComponent(
                "\(sourceFile.deletingPathExtension().lastPathComponent).toml",
                isDirectory: false
            )
            if !FileManager.default.fileExists(atPath: target.path) {
                names.append(metadata.name)
            }
        }
        return names
    }

    private static func externalAgentSubagentSourceFiles(_ sourceAgents: URL) throws -> [URL] {
        guard isDirectory(path: sourceAgents.path) else {
            return []
        }
        var files: [URL] = []
        for name in try FileManager.default.contentsOfDirectory(atPath: sourceAgents.path) {
            let path = sourceAgents.appendingPathComponent(name, isDirectory: false)
            guard isRegularFile(path: path.path),
                  path.pathExtension == "md",
                  path.deletingPathExtension().lastPathComponent != "README"
            else {
                continue
            }
            files.append(path)
        }
        return files.sorted { $0.path < $1.path }
    }

    private static func externalAgentSubagentMetadata(_ document: ExternalAgentCommandDocument) -> ExternalAgentSubagentMetadata? {
        guard !document.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let name = nonEmptyExternalAgentScalar(document.frontmatter["name"]),
              let description = nonEmptyExternalAgentScalar(document.frontmatter["description"])
        else {
            return nil
        }
        return ExternalAgentSubagentMetadata(
            name: name,
            description: description,
            permissionMode: document.frontmatter["permissionMode"],
            effort: document.frontmatter["effort"]
        )
    }

    private static func renderExternalAgentSubagentToml(
        body: String,
        metadata: ExternalAgentSubagentMetadata
    ) -> String {
        var table: [String: ConfigValue] = [
            "name": .string(metadata.name),
            "description": .string(rewriteExternalAgentTerms(metadata.description)),
            "developer_instructions": .string(renderExternalAgentSubagentBody(body))
        ]
        if let effort = metadata.effort.flatMap(mapExternalAgentReasoningEffort) {
            table["model_reasoning_effort"] = .string(effort)
        }
        if let sandboxMode = metadata.permissionMode.flatMap(mapExternalAgentPermissionMode) {
            table["sandbox_mode"] = .string(sandboxMode)
        }
        return renderConfigToml(.table(table))
    }

    private static func renderExternalAgentSubagentBody(_ body: String) -> String {
        let body = rewriteExternalAgentTerms(body.trimmingCharacters(in: .whitespacesAndNewlines))
        return body.isEmpty ? "No subagent instructions were found." : body
    }

    private static func mapExternalAgentReasoningEffort(_ effort: String) -> String? {
        let mapped = effort == "max" ? "xhigh" : effort
        return ["none", "minimal", "low", "medium", "high", "xhigh"].contains(mapped) ? mapped : nil
    }

    private static func mapExternalAgentPermissionMode(_ permissionMode: String) -> String? {
        switch permissionMode {
        case "acceptEdits":
            return "workspace-write"
        case "readOnly":
            return "read-only"
        default:
            return nil
        }
    }

    private static func copyExternalAgentSkillDirectory(source: URL, target: URL) throws {
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        for name in try FileManager.default.contentsOfDirectory(atPath: source.path) {
            let sourcePath = source.appendingPathComponent(name)
            let targetPath = target.appendingPathComponent(name)
            if isDirectory(path: sourcePath.path) {
                try copyExternalAgentSkillDirectory(source: sourcePath, target: targetPath)
                continue
            }
            guard isRegularFile(path: sourcePath.path) else {
                continue
            }
            if name.lowercased() == "skill.md" {
                let contents = try String(contentsOf: sourcePath, encoding: .utf8)
                try rewriteExternalAgentTerms(contents).write(to: targetPath, atomically: true, encoding: .utf8)
            } else {
                try FileManager.default.copyItem(at: sourcePath, to: targetPath)
            }
        }
    }

    private static func isRegularFile(path: String) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType) == .typeRegular
    }

    private static func rewriteExternalAgentTerms(_ content: String) -> String {
        var rewritten = replaceCaseInsensitiveTerm(content, needle: "claude.md", replacement: "AGENTS.md")
        for needle in ["claude code", "claude-code", "claude_code", "claudecode", "claude"] {
            rewritten = replaceCaseInsensitiveTerm(rewritten, needle: needle, replacement: "Codex")
        }
        return rewritten
    }

    private static func replaceCaseInsensitiveTerm(_ input: String, needle: String, replacement: String) -> String {
        guard !needle.isEmpty else {
            return input
        }
        let pattern = #"(?<![A-Za-z0-9_])\#(NSRegularExpression.escapedPattern(for: needle))(?![A-Za-z0-9_])"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return input
        }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return expression.stringByReplacingMatches(in: input, range: range, withTemplate: replacement)
    }

    private static func externalAgentSettings(at path: URL) throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: path.path) else {
            return nil
        }
        let data = try Data(contentsOf: path)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppServerError.internalError("external agent settings root must be an object")
        }
        return object
    }

    private static func externalAgentLocalSettings(at path: URL) throws -> [String: Any]? {
        do {
            return try externalAgentSettings(at: path)
        } catch AppServerError.internalError {
            return nil
        } catch {
            throw error
        }
    }

    private static func effectiveExternalAgentSettings(at path: URL) throws -> [String: Any]? {
        var settings = try externalAgentSettings(at: path)
        let localSettingsPath = path
            .deletingLastPathComponent()
            .appendingPathComponent("settings.local.json", isDirectory: false)
        if let localSettings = try externalAgentLocalSettings(at: localSettingsPath) {
            if var existingSettings = settings {
                mergeJSONSettings(into: &existingSettings, incoming: localSettings)
                settings = existingSettings
            } else {
                settings = localSettings
            }
        }
        return settings
    }

    private static func externalAgentMcpSettings(
        sourceSettings: URL,
        repoRoot: URL?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any]? {
        if repoRoot != nil,
           !FileManager.default.fileExists(atPath: sourceSettings.path) {
            let home = configuration.environment["HOME"].flatMap { value in
                value.isEmpty ? nil : URL(fileURLWithPath: value, isDirectory: true)
            } ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            let homeSettings = home
                .appendingPathComponent(".claude", isDirectory: true)
                .appendingPathComponent("settings.json", isDirectory: false)
            do {
                return try effectiveExternalAgentSettings(at: homeSettings)
            } catch AppServerError.internalError {
                return nil
            }
        }
        return try effectiveExternalAgentSettings(at: sourceSettings)
    }

    private static func mergeJSONSettings(into existing: inout [String: Any], incoming: [String: Any]) {
        for (key, incomingValue) in incoming {
            if var existingObject = existing[key] as? [String: Any],
               let incomingObject = incomingValue as? [String: Any] {
                mergeJSONSettings(into: &existingObject, incoming: incomingObject)
                existing[key] = existingObject
            } else {
                existing[key] = incomingValue
            }
        }
    }

    private struct ExternalAgentSessionMigration {
        var path: URL
        var cwd: URL
        var title: String?
    }

    private struct ExternalAgentSessionSummary {
        var latestTimestamp: Int
        var migration: ExternalAgentSessionMigration
    }

    private struct ImportedExternalAgentSession {
        var cwd: URL
        var title: String?
        var rolloutItems: [RolloutRecordItem]
    }

    private struct ExternalAgentConversationMessage {
        enum Role {
            case user
            case assistant
        }

        var role: Role
        var text: String
        var timestamp: Int64?
    }

    private static let externalAgentSessionImportMaxCount = 50
    private static let externalAgentSessionImportMaxAgeSeconds = 30 * 24 * 60 * 60
    private static let externalAgentSessionImportedMarker = "<EXTERNAL SESSION IMPORTED>"

    private static func externalAgentHome(configuration: CodexAppServerConfiguration) -> URL {
        let home = configuration.environment["HOME"].flatMap { value in
            value.isEmpty ? nil : URL(fileURLWithPath: value, isDirectory: true)
        } ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        return home.appendingPathComponent(".claude", isDirectory: true)
    }

    private static func detectRecentExternalAgentSessions(
        externalAgentHome: URL,
        codexHome: URL,
        now: Int = Int(Date().timeIntervalSince1970)
    ) throws -> [ExternalAgentSessionMigration] {
        let projectsRoot = externalAgentHome.appendingPathComponent("projects", isDirectory: true)
        guard isDirectory(projectsRoot) else {
            return []
        }
        var candidates: [ExternalAgentSessionSummary] = []
        for projectDirectory in try directoryContents(projectsRoot) where isDirectory(projectDirectory) {
            for path in try directoryContents(projectDirectory) where path.pathExtension == "jsonl" {
                guard let summary = try summarizeExternalAgentSession(path),
                      !externalAgentSessionImportLedgerContainsCurrentSource(codexHome: codexHome, sourcePath: path),
                      summary.latestTimestamp >= now - externalAgentSessionImportMaxAgeSeconds,
                      isDirectory(summary.migration.cwd)
                else {
                    continue
                }
                candidates.append(summary)
            }
        }
        candidates.sort {
            if $0.latestTimestamp != $1.latestTimestamp {
                return $0.latestTimestamp > $1.latestTimestamp
            }
            return $0.migration.path.path < $1.migration.path.path
        }
        return candidates.prefix(externalAgentSessionImportMaxCount).map(\.migration)
    }

    private static func externalAgentSessionSourcePath(
        _ path: URL,
        configuration: CodexAppServerConfiguration
    ) throws -> URL? {
        guard let canonicalPath = try? canonicalURL(path),
              let projectsRoot = try? canonicalURL(
            externalAgentHome(configuration: configuration)
                .appendingPathComponent("projects", isDirectory: true)
        )
        else {
            return nil
        }
        guard canonicalPath.pathExtension == "jsonl",
              canonicalPath.path.hasPrefix(projectsRoot.path + "/")
        else {
            return nil
        }
        return canonicalPath
    }

    private static func summarizeExternalAgentSession(_ path: URL) throws -> ExternalAgentSessionSummary? {
        let records = try externalAgentSessionRecords(path)
        var cwd: URL?
        var customTitle: String?
        var aiTitle: String?
        var firstUserTitle: String?
        var latestTimestamp: Int?
        var sawMessage = false

        for record in records {
            if cwd == nil,
               let rawCwd = record["cwd"] as? String {
                cwd = URL(fileURLWithPath: rawCwd, isDirectory: true)
            }
            if let title = externalAgentTitle(from: record, type: "custom-title", field: "customTitle") {
                customTitle = title
            }
            if let title = externalAgentTitle(from: record, type: "ai-title", field: "aiTitle") {
                aiTitle = title
            }
            guard let message = externalAgentConversationMessage(from: record) else {
                continue
            }
            sawMessage = true
            if firstUserTitle == nil, message.role == .user {
                firstUserTitle = summarizeExternalAgentSessionLabel(message.text)
            }
            if let timestamp = (record["timestamp"] as? String).flatMap(parseExternalAgentTimestamp) {
                latestTimestamp = max(latestTimestamp ?? timestamp, timestamp)
            }
        }

        guard let cwd, sawMessage, let latestTimestamp else {
            return nil
        }
        return ExternalAgentSessionSummary(
            latestTimestamp: latestTimestamp,
            migration: ExternalAgentSessionMigration(
                path: path,
                cwd: cwd,
                title: customTitle ?? aiTitle ?? firstUserTitle
            )
        )
    }

    private static func loadExternalAgentSessionForImport(_ path: URL) throws -> ImportedExternalAgentSession? {
        let records = try externalAgentSessionRecords(path)
        guard let rawCwd = records.lazy.compactMap({ $0["cwd"] as? String }).first else {
            return nil
        }
        let cwd = URL(fileURLWithPath: rawCwd, isDirectory: true)
        let messages = records.compactMap(externalAgentConversationMessage)
        let rolloutItems = externalAgentRolloutItems(from: messages)
        guard !rolloutItems.isEmpty else {
            return nil
        }
        let title = externalAgentSourceTitle(from: records)
            ?? messages.first(where: { $0.role == .user }).map { summarizeExternalAgentSessionLabel($0.text) }
        return ImportedExternalAgentSession(cwd: cwd, title: title, rolloutItems: rolloutItems)
    }

    private static func externalAgentRolloutItems(
        from messages: [ExternalAgentConversationMessage]
    ) -> [RolloutRecordItem] {
        var items: [RolloutRecordItem] = []
        var responseItems: [ResponseItem] = []
        var currentTurn: (id: String, lastAgentMessage: String?)?
        var userTurnCount = 0
        for message in messages {
            switch message.role {
            case .user:
                if let turn = currentTurn {
                    items.append(.eventMsg(.taskComplete(TaskCompleteEvent(
                        turnID: turn.id,
                        lastAgentMessage: turn.lastAgentMessage
                    ))))
                }
                userTurnCount += 1
                let turnID = "external-import-turn-\(userTurnCount)"
                items.append(.eventMsg(.taskStarted(TaskStartedEvent(
                    turnID: turnID,
                    startedAt: message.timestamp,
                    modelContextWindow: nil
                ))))
                let responseItem = ResponseItem.message(
                    role: "user",
                    content: [.inputText(text: message.text)]
                )
                responseItems.append(responseItem)
                items.append(.responseItem(responseItem))
                items.append(.eventMsg(.userMessage(UserMessageEvent(message: message.text))))
                currentTurn = (turnID, nil)
            case .assistant:
                guard currentTurn != nil else {
                    continue
                }
                let responseItem = ResponseItem.message(
                    role: "assistant",
                    content: [.outputText(text: message.text)]
                )
                responseItems.append(responseItem)
                items.append(.responseItem(responseItem))
                items.append(.eventMsg(.agentMessage(AgentMessageEvent(message: message.text))))
                currentTurn?.lastAgentMessage = message.text
            }
        }
        if let turn = currentTurn {
            items.append(.eventMsg(.agentMessage(AgentMessageEvent(message: externalAgentSessionImportedMarker))))
            items.append(externalAgentTokenCountItem(responseItems))
            items.append(.eventMsg(.taskComplete(TaskCompleteEvent(
                turnID: turn.id,
                lastAgentMessage: turn.lastAgentMessage,
                completedAt: messages.last?.timestamp
            ))))
        }
        return items
    }

    private static func externalAgentTokenCountItem(_ responseItems: [ResponseItem]) -> RolloutRecordItem {
        let lastAssistantIndex = responseItems.lastIndex {
            guard case let .message(_, role, _, _) = $0 else {
                return false
            }
            return role == "assistant"
        }
        let tokens = lastAssistantIndex.map {
            estimateExternalAgentResponseItemsTokenCount(Array(responseItems[...$0]))
        } ?? 0
        let usage = TokenUsage(totalTokens: tokens)
        return .eventMsg(.tokenCount(TokenCountEvent(
            info: TokenUsageInfo(totalTokenUsage: usage, lastTokenUsage: usage),
            rateLimits: nil
        )))
    }

    private static func estimateExternalAgentResponseItemsTokenCount(_ responseItems: [ResponseItem]) -> Int64 {
        responseItems.reduce(Int64(0)) { total, item in
            guard let data = try? JSONEncoder().encode(item) else {
                return total
            }
            let tokens = Int64(clamping: Truncation.approxTokensFromByteCount(data.count))
            let sum = total.addingReportingOverflow(tokens)
            return sum.overflow ? Int64.max : sum.partialValue
        }
    }

    private static func importExternalAgentSession(
        _ session: ImportedExternalAgentSession,
        configuration: CodexAppServerConfiguration
    ) throws -> ConversationId {
        let runtimeConfig = try CodexConfigLoader.load(codexHome: configuration.codexHome)
        let conversationID = ConversationId()
        let recorder = try RolloutRecorder.create(
            codexHome: configuration.codexHome,
            cwd: session.cwd,
            conversationID: conversationID,
            source: .cli,
            originator: "codex_app_server",
            cliVersion: configuration.version,
            modelProvider: runtimeConfig.selectedModelProviderID
        )
        try recorder.recordItems(session.rolloutItems)
        try recorder.shutdown()
        if let title = session.title,
           let name = normalizeExternalAgentThreadName(title) {
            try appendThreadName(threadID: conversationID, name: name, codexHome: configuration.codexHome)
        }
        return conversationID
    }

    private static func externalAgentSessionMigrationDetails(from value: Any?) throws -> [ExternalAgentSessionMigration] {
        guard let value else {
            return []
        }
        guard let details = value as? [String: Any] else {
            throw AppServerError.invalidParams("externalAgentConfig/import sessions details must be an object")
        }
        guard let rawSessions = details["sessions"] else {
            return []
        }
        guard let sessions = rawSessions as? [[String: Any]] else {
            throw AppServerError.invalidParams("externalAgentConfig/import sessions must be an array")
        }
        return try sessions.map { session in
            guard let path = session["path"] as? String, !path.isEmpty else {
                throw AppServerError.invalidParams("externalAgentConfig/import session path must be a non-empty string")
            }
            guard let cwd = session["cwd"] as? String, !cwd.isEmpty else {
                throw AppServerError.invalidParams("externalAgentConfig/import session cwd must be a non-empty string")
            }
            return ExternalAgentSessionMigration(
                path: URL(fileURLWithPath: path, isDirectory: false),
                cwd: URL(fileURLWithPath: cwd, isDirectory: true),
                title: session["title"] as? String
            )
        }
    }

    private static func externalAgentSessionRecords(_ path: URL) throws -> [[String: Any]] {
        let contents = try String(contentsOf: path, encoding: .utf8)
        return contents.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                return nil
            }
            return object
        }
    }

    private static func externalAgentConversationMessage(
        from record: [String: Any]
    ) -> ExternalAgentConversationMessage? {
        guard let type = record["type"] as? String,
              type == "assistant" || type == "user",
              record["isMeta"] as? Bool != true,
              record["isSidechain"] as? Bool != true,
              let message = record["message"] as? [String: Any],
              let extracted = extractExternalAgentMessageText(message["content"])
        else {
            return nil
        }
        return ExternalAgentConversationMessage(
            role: (type == "assistant" || extracted.onlyToolResult) ? .assistant : .user,
            text: extracted.text,
            timestamp: (record["timestamp"] as? String).flatMap(parseExternalAgentTimestamp).map(Int64.init)
        )
    }

    private static func extractExternalAgentMessageText(_ content: Any?) -> (text: String, onlyToolResult: Bool)? {
        let blocks: [[String: Any]]
        if let text = content as? String {
            blocks = [["type": "text", "text": text]]
        } else {
            blocks = (content as? [[String: Any]]) ?? []
        }
        var parts: [String] = []
        var onlyToolResult = !blocks.isEmpty
        for block in blocks {
            switch block["type"] as? String {
            case "text":
                if let text = block["text"] as? String, !text.isEmpty {
                    parts.append(text)
                    onlyToolResult = false
                }
            case "tool_use":
                parts.append(externalAgentToolCallNote(block))
                onlyToolResult = false
            case "tool_result":
                parts.append(externalAgentToolResultNote(block))
            case "thinking":
                continue
            case let other?:
                parts.append("[external unsupported block: \(other)]")
                onlyToolResult = false
            case nil:
                continue
            }
        }
        let text = parts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
        return text.isEmpty ? nil : (text, onlyToolResult)
    }

    private static func externalAgentToolCallNote(_ block: [String: Any]) -> String {
        let name = block["name"] as? String ?? "unknown"
        var lines = ["[external_agent_tool_call: \(name)]"]
        if let input = block["input"] as? [String: Any] {
            if let description = input["description"] as? String {
                lines.append("description: \(description)")
            }
            if let command = input["command"] as? String {
                lines.append("command: \(command)")
            }
            if let file = (input["file_path"] as? String) ?? (input["file"] as? String) {
                lines.append("file: \(file)")
            }
            if lines.count == 1,
               let data = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]),
               let raw = String(data: data, encoding: .utf8) {
                lines.append("input: \(truncateExternalAgentText(raw, maxLength: 2_000))")
            }
        } else if let input = block["input"] {
            lines.append("input: \(truncateExternalAgentText(String(describing: input), maxLength: 2_000))")
        }
        lines.append("[/external_agent_tool_call]")
        return lines.joined(separator: "\n")
    }

    private static func externalAgentToolResultNote(_ block: [String: Any]) -> String {
        let label = block["is_error"] as? Bool == true
            ? "[external_agent_tool_result: error]"
            : "[external_agent_tool_result]"
        let text = externalAgentToolResultText(block["content"])
        guard !text.isEmpty else {
            return "\(label)\n[/external_agent_tool_result]"
        }
        return "\(label)\n\(truncateExternalAgentText(text, maxLength: 4_000))\n[/external_agent_tool_result]"
    }

    private static func externalAgentToolResultText(_ content: Any?) -> String {
        if let text = content as? String {
            return text
        }
        return ((content as? [[String: Any]]) ?? [])
            .compactMap { $0["text"] as? String }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func externalAgentSourceTitle(from records: [[String: Any]]) -> String? {
        for record in records.reversed() {
            if let title = externalAgentTitle(from: record, type: "custom-title", field: "customTitle") {
                return title
            }
        }
        for record in records.reversed() {
            if let title = externalAgentTitle(from: record, type: "ai-title", field: "aiTitle") {
                return title
            }
        }
        return nil
    }

    private static func externalAgentTitle(from record: [String: Any], type: String, field: String) -> String? {
        guard record["type"] as? String == type,
              let title = record[field] as? String
        else {
            return nil
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func summarizeExternalAgentSessionLabel(_ text: String) -> String {
        let firstLine = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return truncateExternalAgentText(firstLine, maxLength: 120)
    }

    private static func truncateExternalAgentText(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else {
            return text
        }
        return String(text.prefix(max(0, maxLength - 3))) + "..."
    }

    private static func parseExternalAgentTimestamp(_ value: String) -> Int? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return Int(date.timeIntervalSince1970)
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value).map { Int($0.timeIntervalSince1970) }
    }

    private static func externalAgentSessionImportLedgerContainsCurrentSource(
        codexHome: URL,
        sourcePath: URL
    ) -> Bool {
        guard let canonicalPath = try? canonicalURL(sourcePath),
              let contentSHA256 = try? externalAgentSessionContentSHA256(canonicalPath),
              let ledger = try? externalAgentSessionImportLedger(codexHome: codexHome)
        else {
            return false
        }
        return ledger.contains { record in
            record["source_path"] as? String == canonicalPath.path &&
                record["content_sha256"] as? String == contentSHA256
        }
    }

    private static func recordExternalAgentImportedSession(
        codexHome: URL,
        sourcePath: URL,
        importedThreadID: ConversationId
    ) throws {
        let canonicalPath = try canonicalURL(sourcePath)
        let contentSHA256 = try externalAgentSessionContentSHA256(canonicalPath)
        var records = try externalAgentSessionImportLedger(codexHome: codexHome)
        guard !records.contains(where: {
            $0["source_path"] as? String == canonicalPath.path &&
                $0["content_sha256"] as? String == contentSHA256
        }) else {
            return
        }
        records.append([
            "source_path": canonicalPath.path,
            "content_sha256": contentSHA256,
            "imported_thread_id": importedThreadID.description,
            "imported_at": Int(Date().timeIntervalSince1970)
        ])
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: ["records": records],
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: externalAgentSessionImportLedgerPath(codexHome: codexHome), options: .atomic)
    }

    private static func externalAgentSessionImportLedger(codexHome: URL) throws -> [[String: Any]] {
        let path = externalAgentSessionImportLedgerPath(codexHome: codexHome)
        guard FileManager.default.fileExists(atPath: path.path) else {
            return []
        }
        let data = try Data(contentsOf: path)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return object?["records"] as? [[String: Any]] ?? []
    }

    private static func externalAgentSessionImportLedgerPath(codexHome: URL) -> URL {
        codexHome.appendingPathComponent("external_agent_session_imports.json", isDirectory: false)
    }

    private static func externalAgentSessionContentSHA256(_ path: URL) throws -> String {
        let data = try Data(contentsOf: path)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func canonicalURL(_ url: URL) throws -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
        }
        return url.resolvingSymlinksInPath().standardizedFileURL
    }

    private static func directoryContents(_ url: URL) throws -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    private static func normalizeExternalAgentThreadName(_ title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : truncateExternalAgentText(trimmed, maxLength: 120)
    }

    private struct ExternalAgentPluginMigration {
        var marketplaceName: String
        var pluginNames: [String]
    }

    private struct ExternalAgentPluginID {
        var pluginName: String
        var marketplaceName: String

        var key: String {
            "\(pluginName)@\(marketplaceName)"
        }
    }

    private struct ExternalAgentMarketplaceImportSource {
        var source: String
        var refName: String?
    }

    private static let externalAgentOfficialMarketplaceName = "claude-plugins-official"
    private static let externalAgentOfficialMarketplaceSource = "anthropics/claude-plugins-official"

    private static func externalAgentPluginMigrationDetails(
        settings: [String: Any],
        sourceRoot: URL,
        configuration: CodexAppServerConfiguration
    ) throws -> [ExternalAgentPluginMigration] {
        let importSources = externalAgentMarketplaceImportSources(settings: settings, sourceRoot: sourceRoot)
        let loadableMarketplaces = Set(importSources.keys)
        let configuredPluginIDs = try configuredExternalAgentPluginIDs(configuration: configuration)
        let configuredMarketplacePlugins = try configuredExternalAgentMarketplacePlugins(configuration: configuration)
        var groups: [String: Set<String>] = [:]

        for pluginID in externalAgentEnabledPluginIDs(settings) where !configuredPluginIDs.contains(pluginID.key) {
            if let installablePlugins = configuredMarketplacePlugins[pluginID.marketplaceName] {
                guard installablePlugins.contains(pluginID.pluginName) else {
                    continue
                }
            } else {
                guard loadableMarketplaces.contains(pluginID.marketplaceName) else {
                    continue
                }
            }
            groups[pluginID.marketplaceName, default: []].insert(pluginID.pluginName)
        }

        return groups.keys.sorted().compactMap { marketplaceName in
            let pluginNames = Array(groups[marketplaceName] ?? []).sorted()
            guard !pluginNames.isEmpty else {
                return nil
            }
            return ExternalAgentPluginMigration(marketplaceName: marketplaceName, pluginNames: pluginNames)
        }
    }

    private static func externalAgentPluginMigrationDetails(from value: Any?) -> [ExternalAgentPluginMigration]? {
        guard let details = value as? [String: Any],
              let plugins = details["plugins"] as? [[String: Any]]
        else {
            return nil
        }
        return plugins.compactMap { plugin in
            guard let marketplaceName = plugin["marketplaceName"] as? String,
                  let pluginNames = plugin["pluginNames"] as? [String],
                  !marketplaceName.isEmpty,
                  !pluginNames.isEmpty
            else {
                return nil
            }
            return ExternalAgentPluginMigration(marketplaceName: marketplaceName, pluginNames: pluginNames)
        }
    }

    private static func externalAgentEnabledPluginIDs(_ settings: [String: Any]) -> [ExternalAgentPluginID] {
        guard let enabledPlugins = settings["enabledPlugins"] as? [String: Any] else {
            return []
        }
        return enabledPlugins.keys.sorted().compactMap { key in
            guard enabledPlugins[key] as? Bool == true else {
                return nil
            }
            return parseExternalAgentPluginID(key)
        }
    }

    private static func parseExternalAgentPluginID(_ raw: String) -> ExternalAgentPluginID? {
        let parts = raw.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2,
              !parts[0].isEmpty,
              !parts[1].isEmpty
        else {
            return nil
        }
        return ExternalAgentPluginID(pluginName: parts[0], marketplaceName: parts[1])
    }

    private static func externalAgentMarketplaceImportSources(
        settings: [String: Any],
        sourceRoot: URL
    ) -> [String: ExternalAgentMarketplaceImportSource] {
        var sources: [String: ExternalAgentMarketplaceImportSource] = [:]
        let marketplaces = settings["extraKnownMarketplaces"] as? [String: Any] ?? [:]
        for name in marketplaces.keys.sorted() {
            guard let value = marketplaces[name] as? [String: Any] else {
                continue
            }
            let sourceFields = (value["source"] as? [String: Any]) ?? value
            let source = (sourceFields["repo"] as? String)
                ?? (sourceFields["url"] as? String)
                ?? (sourceFields["path"] as? String)
                ?? (value["source"] as? String)
            guard let source = source?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !source.isEmpty
            else {
                continue
            }
            let resolvedSource = resolveExternalAgentMarketplaceSource(source, sourceRoot: sourceRoot)
            let refName = ((sourceFields["ref"] as? String) ?? (value["ref"] as? String))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            sources[name] = ExternalAgentMarketplaceImportSource(
                source: resolvedSource,
                refName: refName?.isEmpty == true ? nil : refName
            )
        }
        if externalAgentEnabledPluginIDs(settings).contains(where: { $0.marketplaceName == externalAgentOfficialMarketplaceName }),
           sources[externalAgentOfficialMarketplaceName] == nil {
            sources[externalAgentOfficialMarketplaceName] = ExternalAgentMarketplaceImportSource(
                source: externalAgentOfficialMarketplaceSource,
                refName: nil
            )
        }
        return sources
    }

    private static func resolveExternalAgentMarketplaceSource(_ source: String, sourceRoot: URL) -> String {
        guard looksLikeExternalAgentRelativeLocalPath(source) else {
            return source
        }
        return sourceRoot.appendingPathComponent(source, isDirectory: true)
            .standardizedFileURL
            .path
    }

    private static func looksLikeExternalAgentRelativeLocalPath(_ source: String) -> Bool {
        source.hasPrefix("./") || source.hasPrefix("../") || source == "." || source == ".."
    }

    private static func externalAgentLocalMarketplaceURL(_ source: ExternalAgentMarketplaceImportSource) throws -> URL? {
        guard source.refName == nil,
              looksLikeLocalMarketplacePath(source.source)
        else {
            return nil
        }
        return try resolveLocalMarketplaceSourcePath(source.source)
    }

    private static func configuredExternalAgentPluginIDs(configuration: CodexAppServerConfiguration) throws -> Set<String> {
        let configFile = configuration.codexHome.appendingPathComponent("config.toml", isDirectory: false)
        let config = try CodexConfigLayerLoader.readConfig(from: configFile) ?? .table([:])
        guard let root = configTable(config),
              let plugins = root["plugins"].flatMap(configTable)
        else {
            return []
        }
        return Set(plugins.keys)
    }

    private static func configuredExternalAgentMarketplacePlugins(
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Set<String>] {
        let configFile = configuration.codexHome.appendingPathComponent("config.toml", isDirectory: false)
        let config = try CodexConfigLayerLoader.readConfig(from: configFile) ?? .table([:])
        let roots = configuredMarketplaceRoots(in: config, codexHome: configuration.codexHome)
        var pluginsByMarketplace: [String: Set<String>] = [:]
        for manifestPath in localMarketplaceManifestPaths(from: roots) {
            let marketplace = try pluginMarketplaceEntry(
                manifestPath: manifestPath,
                config: config,
                codexHome: configuration.codexHome
            )
            guard let marketplaceName = marketplace["name"] as? String,
                  let plugins = marketplace["plugins"] as? [[String: Any]]
            else {
                continue
            }
            let installable = plugins.compactMap { plugin -> String? in
                guard plugin["installPolicy"] as? String != "NOT_AVAILABLE" else {
                    return nil
                }
                return plugin["name"] as? String
            }
            pluginsByMarketplace[marketplaceName] = Set(installable)
        }
        return pluginsByMarketplace
    }

    private static func addExternalAgentMarketplace(
        source: ExternalAgentMarketplaceImportSource,
        configuration: CodexAppServerConfiguration
    ) throws -> URL {
        if let sourcePath = try externalAgentLocalMarketplaceURL(source) {
            _ = try marketplaceAddResult(
                params: ["source": sourcePath.path],
                configuration: configuration
            )
            return try unwrapLocalMarketplaceManifestPath(in: sourcePath)
        }
        var params: [String: Any] = ["source": source.source]
        if let refName = source.refName {
            params["refName"] = refName
        }
        _ = try marketplaceAddResult(
            params: params,
            configuration: configuration
        )
        let configFile = configuration.codexHome.appendingPathComponent("config.toml", isDirectory: false)
        let config = try CodexConfigLayerLoader.readConfig(from: configFile) ?? .table([:])
        guard let marketplaceRoot = configuredMarketplaceRootForSource(source, codexHome: configuration.codexHome, in: config),
              let manifestPath = localMarketplaceManifestPath(in: URL(fileURLWithPath: marketplaceRoot, isDirectory: true))
        else {
            throw AppServerError.internalError("failed to locate imported external agent marketplace")
        }
        return manifestPath
    }

    private static func unwrapLocalMarketplaceManifestPath(in sourcePath: URL) throws -> URL {
        guard let manifestPath = localMarketplaceManifestPath(in: sourcePath) else {
            throw AppServerError.internalError("failed to locate local external agent marketplace manifest")
        }
        return manifestPath
    }

    private static func configuredMarketplaceRootForSource(
        _ source: ExternalAgentMarketplaceImportSource,
        codexHome: URL,
        in config: ConfigValue
    ) -> String? {
        if let localPath = try? externalAgentLocalMarketplaceURL(source) {
            return configuredMarketplaceRootForLocalSource(localPath.path, in: config)
        }
        let parsed = try? parseMarketplaceSource(source.source, explicitRef: source.refName)
        guard parsed?.kind == .git,
              let gitURL = parsed?.gitURL
        else {
            return nil
        }
        return configuredMarketplaceRootForGitSource(
            source: gitURL,
            refName: parsed?.refName,
            sparsePaths: [],
            codexHome: codexHome,
            in: config
        )
    }

    private static func externalAgentMcpConfigValue(
        sourceRoot: URL,
        externalAgentHome: URL,
        settings: [String: Any]?
    ) throws -> ConfigValue {
        let enabledServers = stringSet(settings?["enabledMcpjsonServers"])
        let disabledServers = stringSet(settings?["disabledMcpjsonServers"])
        var servers: [String: ConfigValue] = [:]

        let mcpJson = sourceRoot.appendingPathComponent(".mcp.json", isDirectory: false)
        if let object = try externalAgentJSONObject(at: mcpJson) {
            appendExternalAgentMcpServers(
                from: object["mcpServers"],
                enabledServers: enabledServers,
                disabledServers: disabledServers,
                preservingExisting: false,
                to: &servers
            )
        }

        let sourceClaudeJson = sourceRoot.appendingPathComponent(".claude.json", isDirectory: false)
        try appendExternalAgentMcpServers(
            fromClaudeJsonAt: sourceClaudeJson,
            matching: sourceRoot,
            enabledServers: enabledServers,
            disabledServers: disabledServers,
            preservingExisting: false,
            to: &servers
        )

        let externalAgentParent = externalAgentHome.deletingLastPathComponent()
        if !sameFileSystemPath(externalAgentParent, sourceRoot) {
            let homeClaudeJson = externalAgentParent.appendingPathComponent(".claude.json", isDirectory: false)
            try appendExternalAgentMcpServers(
                fromClaudeJsonAt: homeClaudeJson,
                matching: sourceRoot,
                enabledServers: enabledServers,
                disabledServers: disabledServers,
                preservingExisting: true,
                to: &servers
            )
        }

        guard !servers.isEmpty else {
            return .table([:])
        }
        return .table(["mcp_servers": .table(servers)])
    }

    private static func externalAgentJSONObject(at path: URL) throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: path.path) else {
            return nil
        }
        let data = try Data(contentsOf: path)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func appendExternalAgentMcpServers(
        fromClaudeJsonAt path: URL,
        matching sourceRoot: URL,
        enabledServers: Set<String>,
        disabledServers: Set<String>,
        preservingExisting: Bool,
        to servers: inout [String: ConfigValue]
    ) throws {
        guard let object = try externalAgentJSONObject(at: path) else {
            return
        }
        appendExternalAgentMcpServers(
            from: object["mcpServers"],
            enabledServers: enabledServers,
            disabledServers: disabledServers,
            preservingExisting: preservingExisting,
            to: &servers
        )
        guard let projects = object["projects"] as? [String: Any] else {
            return
        }
        for (projectPath, projectValue) in projects where externalAgentProjectPath(projectPath, matches: sourceRoot) {
            guard let project = projectValue as? [String: Any] else {
                continue
            }
            appendExternalAgentMcpServers(
                from: project["mcpServers"],
                enabledServers: enabledServers,
                disabledServers: disabledServers,
                preservingExisting: preservingExisting,
                to: &servers
            )
        }
    }

    private static func appendExternalAgentMcpServers(
        from value: Any?,
        enabledServers: Set<String>,
        disabledServers: Set<String>,
        preservingExisting: Bool,
        to servers: inout [String: ConfigValue]
    ) {
        guard let rawServers = value as? [String: Any] else {
            return
        }
        for name in rawServers.keys.sorted() {
            guard !preservingExisting || servers[name] == nil,
                  let server = rawServers[name] as? [String: Any],
                  let config = externalAgentMcpServerConfig(
                    name: name,
                    server: server,
                    enabledServers: enabledServers,
                    disabledServers: disabledServers
                  )
            else {
                continue
            }
            servers[name] = config
        }
    }

    private static func externalAgentMcpServerConfig(
        name: String,
        server: [String: Any],
        enabledServers: Set<String>,
        disabledServers: Set<String>
    ) -> ConfigValue? {
        guard server["enabled"] as? Bool != false,
              server["disabled"] as? Bool != true,
              (enabledServers.isEmpty || enabledServers.contains(name)),
              !disabledServers.contains(name)
        else {
            return nil
        }

        if let command = externalAgentMcpString(server["command"]),
           !containsEnvPlaceholder(command) {
            let type = server["type"] as? String
            guard type == nil || type == "stdio" else {
                return nil
            }
            var table: [String: ConfigValue] = ["command": .string(command)]
            if let args = externalAgentMcpStringArray(server["args"]) {
                guard !args.contains(where: containsEnvPlaceholder) else {
                    return nil
                }
                if !args.isEmpty {
                    table["args"] = .array(args.map(ConfigValue.string))
                }
            }
            var env: [String: ConfigValue] = [:]
            var envVars: [ConfigValue] = []
            if let rawEnv = server["env"] as? [String: Any] {
                for key in rawEnv.keys.sorted() {
                    guard let value = externalAgentMcpString(rawEnv[key]) else {
                        continue
                    }
                    if let variable = parseExternalAgentEnvPlaceholder(value), variable == key {
                        envVars.append(.string(key))
                    } else if containsEnvPlaceholder(value) {
                        return nil
                    } else {
                        env[key] = .string(value)
                    }
                }
            }
            if !envVars.isEmpty {
                table["env_vars"] = .array(envVars)
            }
            if !env.isEmpty {
                table["env"] = .table(env)
            }
            return .table(table)
        }

        if let url = externalAgentMcpString(server["url"]),
           !containsEnvPlaceholder(url) {
            let type = server["type"] as? String
            guard type == nil || type == "http" || type == "streamable_http" else {
                return nil
            }
            var table: [String: ConfigValue] = ["url": .string(url)]
            var httpHeaders: [String: ConfigValue] = [:]
            var envHttpHeaders: [String: ConfigValue] = [:]
            if let headers = server["headers"] as? [String: Any] {
                for key in headers.keys.sorted() {
                    guard let value = externalAgentMcpString(headers[key]) else {
                        continue
                    }
                    if key.caseInsensitiveCompare("authorization") == .orderedSame,
                       value.hasPrefix("Bearer "),
                       let variable = parseExternalAgentEnvPlaceholder(String(value.dropFirst("Bearer ".count))) {
                        table["bearer_token_env_var"] = .string(variable)
                    } else if let variable = parseExternalAgentEnvPlaceholder(value) {
                        envHttpHeaders[key] = .string(variable)
                    } else if containsEnvPlaceholder(value) {
                        return nil
                    } else {
                        httpHeaders[key] = .string(value)
                    }
                }
            }
            if !httpHeaders.isEmpty {
                table["http_headers"] = .table(httpHeaders)
            }
            if !envHttpHeaders.isEmpty {
                table["env_http_headers"] = .table(envHttpHeaders)
            }
            return .table(table)
        }

        return nil
    }

    private static func externalAgentMcpString(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            return value
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                return value.boolValue ? "true" : "false"
            }
            return value.stringValue
        default:
            return nil
        }
    }

    private static func externalAgentMcpStringArray(_ value: Any?) -> [String]? {
        switch value {
        case let string as String:
            return [string]
        case let array as [Any]:
            return array.compactMap { externalAgentMcpString($0) }
        case let value?:
            return externalAgentMcpString(value).map { [$0] }
        default:
            return nil
        }
    }

    private static func parseExternalAgentEnvPlaceholder(_ value: String) -> String? {
        guard value.hasPrefix("${"), value.hasSuffix("}") else {
            return nil
        }
        let body = String(value.dropFirst(2).dropLast())
        let name = body.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? body
        guard isExternalAgentEnvName(name) else {
            return nil
        }
        if body.count > name.count {
            guard body.dropFirst(name.count).hasPrefix(":-") else {
                return nil
            }
        }
        return name
    }

    private static func containsEnvPlaceholder(_ value: String) -> Bool {
        value.contains("${")
    }

    private static func isExternalAgentEnvName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first,
              first == "_" || isASCIIAlpha(first)
        else {
            return false
        }
        return name.unicodeScalars.dropFirst().allSatisfy { scalar in
            scalar == "_" || isASCIIAlpha(scalar) || (48...57).contains(scalar.value)
        }
    }

    private static func isASCIIAlpha(_ scalar: Unicode.Scalar) -> Bool {
        (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
    }

    private static func stringSet(_ value: Any?) -> Set<String> {
        Set(externalAgentMcpStringArray(value) ?? [])
    }

    private static func externalAgentProjectPath(_ path: String, matches sourceRoot: URL) -> Bool {
        sameFileSystemPath(URL(fileURLWithPath: path, isDirectory: true), sourceRoot)
    }

    private static func sameFileSystemPath(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.resolvingSymlinksInPath().path == rhs.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func externalAgentConfigValue(from settings: [String: Any]) throws -> ConfigValue {
        var root: [String: ConfigValue] = [:]
        if let env = settings["env"] as? [String: Any], !env.isEmpty {
            root["shell_environment_policy"] = .table([
                "inherit": .string("core"),
                "set": .table(externalAgentEnvironmentTable(from: env))
            ])
        }
        if let sandbox = settings["sandbox"] as? [String: Any],
           sandbox["enabled"] as? Bool == true {
            root["sandbox_mode"] = .string("workspace-write")
        }
        return .table(root)
    }

    private static func externalAgentEnvironmentTable(from env: [String: Any]) -> [String: ConfigValue] {
        var table: [String: ConfigValue] = [:]
        for (key, value) in env {
            if let stringValue = externalAgentEnvironmentString(value) {
                table[key] = .string(stringValue)
            }
        }
        return table
    }

    private static func externalAgentEnvironmentString(_ value: Any) -> String? {
        switch value {
        case let string as String:
            return string
        case let bool as Bool:
            return bool ? "true" : "false"
        case let number as NSNumber:
            return number.stringValue
        case _ as NSNull:
            return nil
        default:
            return nil
        }
    }

    private static func mergeMissingConfigValues(into existing: inout ConfigValue, incoming: ConfigValue) throws -> Bool {
        guard case var .table(existingTable) = existing,
              case let .table(incomingTable) = incoming
        else {
            throw AppServerError.internalError("expected TOML table while merging migrated config values")
        }
        var changed = false
        for (key, incomingValue) in incomingTable {
            if var existingValue = existingTable[key] {
                if case .table = existingValue,
                   case .table = incomingValue,
                   try mergeMissingConfigValues(into: &existingValue, incoming: incomingValue) {
                    existingTable[key] = existingValue
                    changed = true
                }
            } else {
                existingTable[key] = incomingValue
                changed = true
            }
        }
        existing = .table(existingTable)
        return changed
    }

    private static func parseExternalAgentTargetConfig(_ raw: String) throws -> ConfigValue {
        var root: [String: ConfigValue] = [:]
        var currentPath: [String] = []
        for rawLine in raw.split(whereSeparator: \.isNewline) {
            let line = stripTomlComment(from: String(rawLine)).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                continue
            }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                let tableName = String(line.dropFirst().dropLast())
                currentPath = try tableName.split(separator: ".").map { segment in
                    try parseExternalAgentConfigKeySegment(String(segment))
                }
                ensureConfigTable(at: currentPath, in: &root)
                continue
            }
            guard let equals = line.firstIndex(of: "=") else {
                throw AppServerError.internalError("invalid existing config.toml")
            }
            let key = line[..<equals].trimmingCharacters(in: .whitespacesAndNewlines)
            let valueText = line[line.index(after: equals)...].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = try ConfigValueParser.parseTomlLiteral(valueText)
            setConfigTableValue(value, keyPath: currentPath + [try parseExternalAgentConfigKeySegment(key)], in: &root)
        }
        return .table(root)
    }

    private static func parseExternalAgentConfigKeySegment(_ raw: String) throws -> String {
        let segment = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !segment.isEmpty else {
            throw AppServerError.internalError("invalid existing config.toml key")
        }
        if segment.hasPrefix("\"") || segment.hasPrefix("'") {
            guard case let .string(value) = try ConfigValueParser.parseTomlLiteral(segment) else {
                throw AppServerError.internalError("invalid existing config.toml key")
            }
            return value
        }
        return segment
    }

    private static func ensureConfigTable(at path: [String], in root: inout [String: ConfigValue]) {
        guard let first = path.first else {
            return
        }
        if path.count == 1 {
            if root[first] == nil {
                root[first] = .table([:])
            }
            return
        }
        var child: [String: ConfigValue]
        if case let .table(existing)? = root[first] {
            child = existing
        } else {
            child = [:]
        }
        ensureConfigTable(at: Array(path.dropFirst()), in: &child)
        root[first] = .table(child)
    }

    private static func setConfigTableValue(_ value: ConfigValue, keyPath: [String], in root: inout [String: ConfigValue]) {
        guard let first = keyPath.first else {
            return
        }
        if keyPath.count == 1 {
            root[first] = value
            return
        }
        var child: [String: ConfigValue]
        if case let .table(existing)? = root[first] {
            child = existing
        } else {
            child = [:]
        }
        setConfigTableValue(value, keyPath: Array(keyPath.dropFirst()), in: &child)
        root[first] = .table(child)
    }

    fileprivate static func addConversationListenerResult() -> [String: Any] {
        [
            "subscriptionId": UUID().uuidString.lowercased()
        ]
    }

    fileprivate static func modelListResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        let runtimeConfig = try CodexConfigLoader.load(
            codexHome: configuration.codexHome,
            cwd: configuration.cwd,
            managedConfigOverrides: configuration.configLayerOverrides,
            environment: configuration.environment
        )
        let configuredCatalog = runtimeConfig.modelCatalog?.models
        let remoteModels = try configuredCatalog
            ?? ModelsCache.load(from: ModelsManager.cachePath(codexHome: configuration.codexHome))?.models
            ?? []
        let chatGPTMode: Bool
        if case .chatGPT = try currentAuth(configuration: configuration)?.kind {
            chatGPTMode = true
        } else {
            chatGPTMode = false
        }
        let availableModels = ModelsManager.buildAvailableModels(
            remoteModels: remoteModels,
            localModels: configuredCatalog == nil ? ModelsManager.builtinModelPresets() : [],
            chatGPTMode: chatGPTMode
        )
        let defaultModel = ModelsManager.defaultModel(
            explicitModel: nil,
            isChatGPT: chatGPTMode,
            availableModels: availableModels
        )
        let includeHidden = try rustBoolParam(params?["includeHidden"], defaultValue: false)
        let models = availableModels
            .map { $0.withIsDefault($0.model == defaultModel) }
            .filter { includeHidden || $0.showInPicker }
        let total = models.count
        let start = try modelListStart(cursor: stringParam(params?["cursor"]), total: total)
        let effectiveLimit = try rustU32PaginationLimit(params?["limit"], total: total)
        let end = min(start + effectiveLimit, total)
        let items = start < end ? Array(models[start..<end]) : []

        return [
            "data": items.map(modelObject),
            "nextCursor": (end < total ? String(end) : nil) as Any
        ].nullStripped()
    }

    fileprivate static func mcpServerStatusListResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        let detail = try mcpServerStatusDetail(params?["detail"])
        let runtimeConfig: CodexRuntimeConfig
        do {
            runtimeConfig = try CodexConfigLoader.load(
                codexHome: configuration.codexHome,
                systemConfigFile: nil,
                environment: configuration.environment
            )
        } catch {
            throw AppServerError.internalError("failed to load MCP server config: \(error)")
        }

        let runtimeMcpConfig = runtimeConfig.runtimeMcpConfig
        let usesCodexBackend: Bool
        if case .chatGPT = try currentAuth(configuration: configuration)?.kind {
            usesCodexBackend = true
        } else {
            usesCodexBackend = false
        }
        let effectiveServers = runtimeMcpConfig.effectiveMcpServers(
            usesCodexBackend: usesCodexBackend,
            environment: configuration.environment
        )
        let serverNames = effectiveServers.keys.sorted()
        let total = serverNames.count
        let start = try mcpServerStatusStart(cursor: stringParam(params?["cursor"]), total: total)
        let effectiveLimit = try rustU32PaginationLimit(params?["limit"], total: total)
        let end = min(start + effectiveLimit, total)
        let configuredEffectiveServers = effectiveServers.compactMapValues(\.configuredConfig)
        let statuses = McpAuthStatusResolver.authStatuses(
            for: configuredEffectiveServers,
            codexHome: configuration.codexHome,
            storeMode: runtimeConfig.mcpOAuthCredentialsStoreMode
        )
        let snapshot = mcpServerStatusSnapshot(
            effectiveServers: effectiveServers,
            detail: detail,
            configuration: configuration
        )
        let data = (start < end ? Array(serverNames[start..<end]) : []).map { name in
            mcpServerStatusObject(
                name: name,
                tools: snapshot.toolsByServer[name] ?? [:],
                resources: snapshot.resources[name] ?? [],
                resourceTemplates: snapshot.resourceTemplates[name] ?? [],
                authStatus: statuses[name] ?? .unsupported
            )
        }

        return [
            "data": data,
            "nextCursor": (end < total ? String(end) : nil) as Any
        ].nullStripped()
    }

    fileprivate static func modelProviderCapabilitiesReadResult(
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        let runtimeConfig: CodexRuntimeConfig
        do {
            runtimeConfig = try CodexConfigLoader.load(
                codexHome: configuration.codexHome,
                systemConfigFile: nil,
                environment: configuration.environment
            )
        } catch {
            throw AppServerError.internalError("failed to reload config: \(error)")
        }

        let capabilities = runtimeConfig.selectedModelProvider?.capabilities()
            ?? ModelProviderCapabilities()
        return [
            "namespaceTools": capabilities.namespaceTools,
            "imageGeneration": capabilities.imageGeneration,
            "webSearch": capabilities.webSearch
        ]
    }

    fileprivate static func windowsSandboxReadinessResult() -> [String: Any] {
        [
            "status": "notConfigured"
        ]
    }

    fileprivate static func windowsSandboxSetupStartResult(params: [String: Any]?) throws -> (result: [String: Any], notification: [String: Any]) {
        let mode = try windowsSandboxSetupModeParam(params?["mode"])
        _ = try optionalAbsolutePathParam(params?["cwd"], name: "cwd")

        let error: String?
        #if os(Windows)
        error = "Windows sandbox setup is not implemented"
        #else
        switch mode {
        case "elevated":
            error = "elevated Windows sandbox setup is only supported on Windows"
        case "unelevated":
            error = "legacy Windows sandbox setup is only supported on Windows"
        default:
            error = nil
        }
        #endif

        return (
            result: ["started": true],
            notification: [
                "method": "windowsSandbox/setupCompleted",
                "params": [
                    "mode": mode,
                    "success": error == nil,
                    "error": nullable(error)
                ]
            ]
        )
    }

    fileprivate static func mcpServerStatusSnapshot(
        effectiveServers: [String: EffectiveMcpServer],
        detail: AppServerMcpServerStatusDetail,
        configuration: CodexAppServerConfiguration
    ) -> AppServerMcpServerStatusSnapshot {
        var snapshot = AppServerMcpServerStatusSnapshot()
        for name in effectiveServers.keys.sorted() {
            guard let server = effectiveServers[name] else {
                continue
            }
            switch server {
            case let .configured(config):
                guard config.enabled else {
                    continue
                }
                do {
                    let inventory = try mcpServerInventorySnapshot(
                        name: name,
                        server: config,
                        detail: detail,
                        configuration: configuration
                    )
                    snapshot.toolsByServer[name] = inventory.toolsByServer[name] ?? [:]
                    if detail == .full {
                        snapshot.resources[name] = inventory.resources[name] ?? []
                        snapshot.resourceTemplates[name] = inventory.resourceTemplates[name] ?? []
                    }
                } catch {
                    continue
                }
            case let .builtin(builtinServer):
                let inventory = mcpBuiltinInventorySnapshot(server: builtinServer, detail: detail)
                snapshot.toolsByServer[name] = inventory.toolsByServer[name] ?? [:]
                if detail == .full {
                    snapshot.resources[name] = inventory.resources[name] ?? []
                    snapshot.resourceTemplates[name] = inventory.resourceTemplates[name] ?? []
                }
            }
        }
        return snapshot
    }

    fileprivate static func mcpBuiltinInventorySnapshot(
        server: BuiltinMcpServer,
        detail _: AppServerMcpServerStatusDetail
    ) -> AppServerMcpServerStatusSnapshot {
        var snapshot = AppServerMcpServerStatusSnapshot()
        switch server {
        case .memories:
            snapshot.toolsByServer[server.name] = toolsByName(MemoriesMCPServer.toolDefinitionsForStatus())
            snapshot.resources[server.name] = []
            snapshot.resourceTemplates[server.name] = []
        }
        return snapshot
    }

    fileprivate static func mcpServerInventorySnapshot(
        name: String,
        server: McpServerConfig,
        detail: AppServerMcpServerStatusDetail,
        configuration: CodexAppServerConfiguration
    ) throws -> AppServerMcpServerStatusSnapshot {
        switch server.transport {
        case let .stdio(command, args, env, envVars, cwd):
            return try mcpStdioInventorySnapshot(
                server: name,
                command: command,
                args: args,
                env: env,
                envVars: envVars,
                cwd: cwd,
                timeoutSeconds: server.toolTimeoutSec ?? server.startupTimeoutSec,
                detail: detail,
                configuration: configuration
            )
        case let .streamableHttp(url, bearerTokenEnvVar, httpHeaders, envHttpHeaders):
            return try runAsyncBlocking {
                try await mcpStreamableHTTPInventorySnapshot(
                    server: name,
                    url: url,
                    bearerTokenEnvVar: bearerTokenEnvVar,
                    httpHeaders: httpHeaders,
                    envHttpHeaders: envHttpHeaders,
                    timeoutSeconds: server.toolTimeoutSec ?? server.startupTimeoutSec,
                    detail: detail,
                    configuration: configuration
                )
            }
        }
    }

    fileprivate static func mcpStdioInventorySnapshot(
        server: String,
        command: String,
        args: [String],
        env: [String: String]?,
        envVars: [String],
        cwd: String?,
        timeoutSeconds: Double?,
        detail: AppServerMcpServerStatusDetail,
        configuration: CodexAppServerConfiguration
    ) throws -> AppServerMcpServerStatusSnapshot {
        let process = Process()
        if command.contains("/") {
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = args
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + args
        }
        if let cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true)
        }
        var environment = configuration.environment
        for name in envVars {
            if let value = configuration.environment[name] {
                environment[name] = value
            }
        }
        for (name, value) in env ?? [:] {
            environment[name] = value
        }
        process.environment = environment

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw AppServerError.internalError("failed to start MCP server \(server): \(error)")
        }
        let timeout = timeoutSeconds.map { max($0, 0.1) } ?? 10
        defer {
            if process.isRunning {
                process.terminate()
            }
        }

        try mcpWriteStdioRequest(mcpInitializeRequest(version: configuration.version), to: stdin.fileHandleForWriting, server: server)
        try mcpWriteStdioRequest(mcpListRequest(id: 1, method: "tools/list"), to: stdin.fileHandleForWriting, server: server)
        let toolsResponse = try mcpReadStdioResponse(
            id: 1,
            stdout: stdout,
            stderr: stderr,
            process: process,
            timeout: timeout,
            server: server
        )

        var snapshot = AppServerMcpServerStatusSnapshot()
        snapshot.toolsByServer[server] = try mcpToolsByRawName(from: toolsResponse, server: server)

        if detail == .full {
            try mcpWriteStdioRequest(mcpListRequest(id: 2, method: "resources/list"), to: stdin.fileHandleForWriting, server: server)
            let resourcesResponse = try mcpReadStdioResponse(
                id: 2,
                stdout: stdout,
                stderr: stderr,
                process: process,
                timeout: timeout,
                server: server
            )
            snapshot.resources[server] = try mcpArrayResult(
                "resources",
                from: resourcesResponse,
                server: server,
                as: McpResource.self
            )

            try mcpWriteStdioRequest(mcpListRequest(id: 3, method: "resources/templates/list"), to: stdin.fileHandleForWriting, server: server)
            let templatesResponse = try mcpReadStdioResponse(
                id: 3,
                stdout: stdout,
                stderr: stderr,
                process: process,
                timeout: timeout,
                server: server
            )
            snapshot.resourceTemplates[server] = try mcpArrayResult(
                "resourceTemplates",
                from: templatesResponse,
                server: server,
                as: McpResourceTemplate.self
            )
        }

        stdin.fileHandleForWriting.closeFile()
        return snapshot
    }

    fileprivate static func mcpStreamableHTTPInventorySnapshot(
        server: String,
        url: String,
        bearerTokenEnvVar: String?,
        httpHeaders: [String: String]?,
        envHttpHeaders: [String: String]?,
        timeoutSeconds: Double?,
        detail: AppServerMcpServerStatusDetail,
        configuration: CodexAppServerConfiguration
    ) async throws -> AppServerMcpServerStatusSnapshot {
        let headers = mcpHTTPHeaders(
            bearerTokenEnvVar: bearerTokenEnvVar,
            httpHeaders: httpHeaders,
            envHttpHeaders: envHttpHeaders,
            environment: configuration.environment
        )
        let initializeResponse = try await mcpStreamableHTTPRequest(
            url: url,
            headers: headers,
            sessionID: nil,
            body: mcpInitializeRequest(version: configuration.version),
            transport: configuration.mcpHTTPTransport,
            timeoutSeconds: timeoutSeconds,
            server: server
        )
        let sessionID = mcpSessionID(from: initializeResponse.headers)
        let toolsResponse = try await mcpStreamableHTTPRequest(
            url: url,
            headers: headers,
            sessionID: sessionID,
            body: mcpListRequest(id: 1, method: "tools/list"),
            transport: configuration.mcpHTTPTransport,
            timeoutSeconds: timeoutSeconds,
            server: server
        )

        var snapshot = AppServerMcpServerStatusSnapshot()
        snapshot.toolsByServer[server] = try mcpToolsByRawName(from: toolsResponse.object, server: server)

        if detail == .full {
            let resourcesResponse = try await mcpStreamableHTTPRequest(
                url: url,
                headers: headers,
                sessionID: sessionID,
                body: mcpListRequest(id: 2, method: "resources/list"),
                transport: configuration.mcpHTTPTransport,
                timeoutSeconds: timeoutSeconds,
                server: server
            )
            snapshot.resources[server] = try mcpArrayResult(
                "resources",
                from: resourcesResponse.object,
                server: server,
                as: McpResource.self
            )
            let templatesResponse = try await mcpStreamableHTTPRequest(
                url: url,
                headers: headers,
                sessionID: sessionID,
                body: mcpListRequest(id: 3, method: "resources/templates/list"),
                transport: configuration.mcpHTTPTransport,
                timeoutSeconds: timeoutSeconds,
                server: server
            )
            snapshot.resourceTemplates[server] = try mcpArrayResult(
                "resourceTemplates",
                from: templatesResponse.object,
                server: server,
                as: McpResourceTemplate.self
            )
        }

        return snapshot
    }

    fileprivate static func mcpInitializeRequest(version: String) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": 0,
            "method": "initialize",
            "params": [
                "protocolVersion": "2025-06-18",
                "capabilities": [:],
                "clientInfo": [
                    "name": "codex-swift",
                    "version": version
                ]
            ]
        ]
    }

    fileprivate static func mcpListRequest(id: Int, method: String) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": [:]
        ]
    }

    fileprivate static func mcpToolsByRawName(from response: [String: Any], server: String) throws -> [String: Any] {
        let tools = try mcpArrayResult("tools", from: response, server: server, as: McpTool.self)
        return toolsByName(tools)
    }

    fileprivate static func toolsByName(_ tools: [[String: Any]]) -> [String: Any] {
        var toolsByName: [String: Any] = [:]
        for tool in tools {
            guard let name = tool["name"] as? String else {
                continue
            }
            toolsByName[name] = tool
        }
        return toolsByName
    }

    fileprivate static func mcpArrayResult<T: Codable>(
        _ key: String,
        from response: [String: Any],
        server: String,
        as type: T.Type
    ) throws -> [[String: Any]] {
        guard let result = response["result"] as? [String: Any] else {
            if let error = response["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw AppServerError.internalError(message)
            }
            throw AppServerError.internalError("MCP server \(server) returned a response without result")
        }
        guard let values = result[key] as? [Any] else {
            throw AppServerError.internalError("MCP server \(server) returned a \(key) result without \(key)")
        }
        return values.compactMap { rawValue in
            guard JSONSerialization.isValidJSONObject(rawValue),
                  let data = try? JSONSerialization.data(withJSONObject: rawValue),
                  let decoded = try? JSONDecoder().decode(type, from: data),
                  let object = encodableJSONObject(decoded) as? [String: Any] else {
                return nil
            }
            return object
        }
    }

    fileprivate static func mcpServerRefreshResult(
        rawParams: Any?,
        configuration: CodexAppServerConfiguration,
        loadedThreadIDs: () -> [String] = { [] },
        queueThreadRefresh: (String, McpServerRefreshConfig) throws -> Void = { _, _ in }
    ) throws -> [String: Any] {
        if let rawParams, !(rawParams is NSNull) {
            throw AppServerError.invalidParams("invalid params for config/mcpServer/reload")
        }
        let runtimeConfig: CodexRuntimeConfig
        do {
            runtimeConfig = try CodexConfigLoader.load(
                codexHome: configuration.codexHome,
                systemConfigFile: nil,
                environment: configuration.environment
            )
        } catch {
            throw AppServerError.internalError("failed to refresh MCP servers: failed to reload config: \(error)")
        }
        let refreshConfig = mcpServerRefreshConfig(runtimeConfig: runtimeConfig)
        for threadID in loadedThreadIDs() {
            do {
                try queueThreadRefresh(threadID, refreshConfig)
            } catch {
                throw AppServerError.internalError(
                    "failed to refresh MCP servers: failed to queue MCP refresh for thread \(threadID): \(error)"
                )
            }
        }
        return [:]
    }

    fileprivate static func mcpServerRefreshConfig(runtimeConfig: CodexRuntimeConfig) -> McpServerRefreshConfig {
        McpServerRefreshConfig(
            mcpServers: mcpServersRefreshJSONValue(runtimeConfig.mcpServers),
            mcpOAuthCredentialsStoreMode: .string(runtimeConfig.mcpOAuthCredentialsStoreMode.rawValue)
        )
    }

    private static func mcpServersRefreshJSONValue(_ servers: [String: McpServerConfig]) -> JSONValue {
        .object(Dictionary(uniqueKeysWithValues: servers.map { name, server in
            (name, mcpServerRefreshJSONValue(server))
        }))
    }

    private static func mcpServerRefreshJSONValue(_ server: McpServerConfig) -> JSONValue {
        var object: [String: JSONValue] = [:]
        switch server.transport {
        case let .stdio(command, args, env, envVars, cwd):
            object["command"] = .string(command)
            if !args.isEmpty {
                object["args"] = .array(args.map(JSONValue.string))
            }
            if let env, !env.isEmpty {
                object["env"] = .object(env.mapValues(JSONValue.string))
            }
            if !envVars.isEmpty {
                object["env_vars"] = .array(envVars.map(JSONValue.string))
            }
            if let cwd {
                object["cwd"] = .string(cwd)
            }
        case let .streamableHttp(url, bearerTokenEnvVar, httpHeaders, envHttpHeaders):
            object["url"] = .string(url)
            if let bearerTokenEnvVar {
                object["bearer_token_env_var"] = .string(bearerTokenEnvVar)
            }
            if let httpHeaders, !httpHeaders.isEmpty {
                object["http_headers"] = .object(httpHeaders.mapValues(JSONValue.string))
            }
            if let envHttpHeaders, !envHttpHeaders.isEmpty {
                object["env_http_headers"] = .object(envHttpHeaders.mapValues(JSONValue.string))
            }
        }
        if !server.enabled {
            object["enabled"] = .bool(false)
        }
        if server.required {
            object["required"] = .bool(true)
        }
        if server.supportsParallelToolCalls {
            object["supports_parallel_tool_calls"] = .bool(true)
        }
        if let startupTimeoutSec = server.startupTimeoutSec {
            object["startup_timeout_sec"] = .double(startupTimeoutSec)
        }
        if let toolTimeoutSec = server.toolTimeoutSec {
            object["tool_timeout_sec"] = .double(toolTimeoutSec)
        }
        if let defaultToolsApprovalMode = server.defaultToolsApprovalMode {
            object["default_tools_approval_mode"] = .string(defaultToolsApprovalMode.rawValue)
        }
        if let enabledTools = server.enabledTools {
            object["enabled_tools"] = .array(enabledTools.map(JSONValue.string))
        }
        if let disabledTools = server.disabledTools {
            object["disabled_tools"] = .array(disabledTools.map(JSONValue.string))
        }
        if let scopes = server.scopes {
            object["scopes"] = .array(scopes.map(JSONValue.string))
        }
        if let oauthResource = server.oauthResource {
            object["oauth_resource"] = .string(oauthResource)
        }
        if !server.tools.isEmpty {
            object["tools"] = .object(server.tools.mapValues(mcpServerToolRefreshJSONValue))
        }
        return .object(object)
    }

    private static func mcpServerToolRefreshJSONValue(_ tool: McpServerToolConfig) -> JSONValue {
        var object: [String: JSONValue] = [:]
        if let approvalMode = tool.approvalMode {
            object["approval_mode"] = .string(approvalMode.rawValue)
        }
        return .object(object)
    }

    fileprivate static func mcpResourceReadResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        let cwdFallback = try mcpThreadCwdFallback(params: params, configuration: configuration)
        guard let server = stringParam(params?["server"]), !server.isEmpty else {
            throw AppServerError.invalidRequest("missing server")
        }
        guard let uri = stringParam(params?["uri"]), !uri.isEmpty else {
            throw AppServerError.invalidRequest("missing uri")
        }
        let runtimeConfig: CodexRuntimeConfig
        do {
            runtimeConfig = try CodexConfigLoader.load(
                codexHome: configuration.codexHome,
                systemConfigFile: nil,
                environment: configuration.environment
            )
        } catch {
            throw AppServerError.internalError("failed to load MCP server config: \(error)")
        }
        guard case let .configured(serverConfig) = try effectiveMcpServer(
            named: server,
            runtimeConfig: runtimeConfig,
            configuration: configuration
        ) else {
            throw AppServerError.internalError("unknown MCP server '\(server)'")
        }
        switch serverConfig.transport {
        case let .stdio(command, args, env, envVars, cwd):
            return try mcpStdioResourceReadResult(
                server: server,
                command: command,
                args: args,
                env: env,
                envVars: envVars,
                cwd: cwd,
                cwdFallback: cwdFallback,
                uri: uri,
                timeoutSeconds: serverConfig.toolTimeoutSec ?? serverConfig.startupTimeoutSec,
                configuration: configuration
            ).object
        case let .streamableHttp(url, bearerTokenEnvVar, httpHeaders, envHttpHeaders):
            return try runAsyncBlocking {
                try await mcpStreamableHTTPResourceReadResult(
                    server: server,
                    url: url,
                    uri: uri,
                    bearerTokenEnvVar: bearerTokenEnvVar,
                    httpHeaders: httpHeaders,
                    envHttpHeaders: envHttpHeaders,
                    configuration: configuration
                )
            }.object
        }
    }

    fileprivate static func mcpStdioResourceReadResult(
        server: String,
        command: String,
        args: [String],
        env: [String: String]?,
        envVars: [String],
        cwd: String?,
        cwdFallback: String,
        uri: String,
        timeoutSeconds: Double?,
        configuration: CodexAppServerConfiguration
    ) throws -> AppServerJSONObject {
        let process = Process()
        if command.contains("/") {
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = args
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + args
        }
        let effectiveCWD = cwd ?? cwdFallback
        if !effectiveCWD.isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: effectiveCWD, isDirectory: true)
        }
        var environment = configuration.environment
        for name in envVars {
            if let value = configuration.environment[name] {
                environment[name] = value
            }
        }
        for (name, value) in env ?? [:] {
            environment[name] = value
        }
        process.environment = environment

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw AppServerError.internalError("failed to start MCP server \(server): \(error)")
        }
        let timeout = timeoutSeconds.map { max($0, 0.1) } ?? 10
        defer {
            if process.isRunning {
                process.terminate()
            }
        }

        try mcpWriteStdioRequest([
            "jsonrpc": "2.0",
            "id": 0,
            "method": "initialize",
            "params": [
                "protocolVersion": "2025-06-18",
                "capabilities": [:],
                "clientInfo": [
                    "name": "codex-swift",
                    "version": configuration.version
                ]
            ]
        ], to: stdin.fileHandleForWriting, server: server)

        try mcpWriteStdioRequest([
            "jsonrpc": "2.0",
            "id": 1,
            "method": "resources/read",
            "params": [
                "uri": uri
            ]
        ], to: stdin.fileHandleForWriting, server: server)
        stdin.fileHandleForWriting.closeFile()
        let resourceResponse = try mcpReadStdioResponse(
            id: 1,
            stdout: stdout,
            stderr: stderr,
            process: process,
            timeout: timeout,
            server: server
        )
        guard let result = resourceResponse["result"] as? [String: Any] else {
            if let error = resourceResponse["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw AppServerError.internalError(message)
            }
            throw AppServerError.internalError("MCP server \(server) returned a response without result")
        }
        guard result["contents"] is [Any] else {
            throw AppServerError.internalError("MCP server \(server) returned a resource read result without contents")
        }
        return AppServerJSONObject(object: result)
    }

    fileprivate static func mcpStdioToolCallResult(
        server: String,
        command: String,
        args: [String],
        env: [String: String]?,
        envVars: [String],
        cwd: String?,
        cwdFallback: String,
        params: [String: Any],
        timeoutSeconds: Double?,
        configuration: CodexAppServerConfiguration
    ) throws -> AppServerJSONObject {
        let process = Process()
        if command.contains("/") {
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = args
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + args
        }
        let effectiveCWD = cwd ?? cwdFallback
        if !effectiveCWD.isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: effectiveCWD, isDirectory: true)
        }
        var environment = configuration.environment
        for name in envVars {
            if let value = configuration.environment[name] {
                environment[name] = value
            }
        }
        for (name, value) in env ?? [:] {
            environment[name] = value
        }
        process.environment = environment

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw AppServerError.internalError("failed to start MCP server \(server): \(error)")
        }
        let timeout = timeoutSeconds.map { max($0, 0.1) } ?? 10
        defer {
            if process.isRunning {
                process.terminate()
            }
        }

        try mcpWriteStdioRequest([
            "jsonrpc": "2.0",
            "id": 0,
            "method": "initialize",
            "params": [
                "protocolVersion": "2025-06-18",
                "capabilities": [:],
                "clientInfo": [
                    "name": "codex-swift",
                    "version": configuration.version
                ]
            ]
        ], to: stdin.fileHandleForWriting, server: server)

        try mcpWriteStdioRequest([
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": params
        ], to: stdin.fileHandleForWriting, server: server)
        stdin.fileHandleForWriting.closeFile()
        let toolResponse = try mcpReadStdioResponse(
            id: 1,
            stdout: stdout,
            stderr: stderr,
            process: process,
            timeout: timeout,
            server: server
        )
        return try mcpToolCallResult(from: toolResponse, server: server)
    }

    fileprivate static func mcpWriteStdioRequest(
        _ object: [String: Any],
        to handle: FileHandle,
        server: String
    ) throws {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw AppServerError.internalError("invalid MCP stdio request body for \(server)")
        }
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        handle.write(data)
    }

    fileprivate static func mcpReadStdioResponse(
        id: Int,
        stdout: Pipe,
        stderr: Pipe,
        process: Process,
        timeout: Double,
        server: String
    ) throws -> [String: Any] {
        let capture = AppServerStdioResponseCapture(id: id)
        let semaphore = DispatchSemaphore(value: 0)
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                semaphore.signal()
                return
            }
            capture.appendStdout(data)
            if capture.response != nil {
                semaphore.signal()
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                capture.appendStderr(data)
            }
        }
        process.terminationHandler = { _ in
            semaphore.signal()
        }
        defer {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            process.terminationHandler = nil
        }

        let deadline = DispatchTime.now() + timeout
        while true {
            if let response = capture.response {
                return response
            }
            if !process.isRunning {
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                capture.appendStdout(stdout.fileHandleForReading.readDataToEndOfFile())
                capture.appendStderr(stderr.fileHandleForReading.readDataToEndOfFile())
                if let response = capture.response {
                    return response
                }
                let stderrText = capture.stderrText
                if !stderrText.isEmpty {
                    throw AppServerError.internalError("MCP server \(server) produced no response: \(stderrText)")
                }
                throw AppServerError.internalError("MCP server \(server) produced no response")
            }
            if semaphore.wait(timeout: deadline) == .timedOut {
                process.terminate()
                throw AppServerError.internalError("timed out reading MCP server \(server) response")
            }
        }
    }

    fileprivate static func mcpStreamableHTTPResourceReadResult(
        server: String,
        url: String,
        uri: String,
        bearerTokenEnvVar: String?,
        httpHeaders: [String: String]?,
        envHttpHeaders: [String: String]?,
        configuration: CodexAppServerConfiguration
    ) async throws -> AppServerJSONObject {
        let initializeResponse = try await mcpStreamableHTTPRequest(
            url: url,
            headers: mcpHTTPHeaders(
                bearerTokenEnvVar: bearerTokenEnvVar,
                httpHeaders: httpHeaders,
                envHttpHeaders: envHttpHeaders,
                environment: configuration.environment
            ),
            sessionID: nil,
            body: [
                "jsonrpc": "2.0",
                "id": 0,
                "method": "initialize",
                "params": [
                    "protocolVersion": "2025-06-18",
                    "capabilities": [:],
                    "clientInfo": [
                        "name": "codex-swift",
                        "version": configuration.version
                    ]
                ]
            ],
            transport: configuration.mcpHTTPTransport,
            server: server
        )
        let sessionID = mcpSessionID(from: initializeResponse.headers)
        let resourceResponse = try await mcpStreamableHTTPRequest(
            url: url,
            headers: mcpHTTPHeaders(
                bearerTokenEnvVar: bearerTokenEnvVar,
                httpHeaders: httpHeaders,
                envHttpHeaders: envHttpHeaders,
                environment: configuration.environment
            ),
            sessionID: sessionID,
            body: [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "resources/read",
                "params": [
                    "uri": uri
                ]
            ],
            transport: configuration.mcpHTTPTransport,
            server: server
        )
        guard let result = resourceResponse.object["result"] as? [String: Any] else {
            if let error = resourceResponse.object["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw AppServerError.internalError(message)
            }
            throw AppServerError.internalError("MCP server \(server) returned a response without result")
        }
        guard result["contents"] is [Any] else {
            throw AppServerError.internalError("MCP server \(server) returned a resource read result without contents")
        }
        return AppServerJSONObject(object: result)
    }

    fileprivate static func mcpStreamableHTTPToolCallResult(
        server: String,
        url: String,
        paramsData: Data,
        bearerTokenEnvVar: String?,
        httpHeaders: [String: String]?,
        envHttpHeaders: [String: String]?,
        configuration: CodexAppServerConfiguration
    ) async throws -> AppServerJSONObject {
        let initializeResponse = try await mcpStreamableHTTPRequest(
            url: url,
            headers: mcpHTTPHeaders(
                bearerTokenEnvVar: bearerTokenEnvVar,
                httpHeaders: httpHeaders,
                envHttpHeaders: envHttpHeaders,
                environment: configuration.environment
            ),
            sessionID: nil,
            body: [
                "jsonrpc": "2.0",
                "id": 0,
                "method": "initialize",
                "params": [
                    "protocolVersion": "2025-06-18",
                    "capabilities": [:],
                    "clientInfo": [
                        "name": "codex-swift",
                        "version": configuration.version
                    ]
                ]
            ],
            transport: configuration.mcpHTTPTransport,
            server: server
        )
        let sessionID = mcpSessionID(from: initializeResponse.headers)
        let params = try mcpJSONObject(from: paramsData, server: server)
        let toolResponse = try await mcpStreamableHTTPRequest(
            url: url,
            headers: mcpHTTPHeaders(
                bearerTokenEnvVar: bearerTokenEnvVar,
                httpHeaders: httpHeaders,
                envHttpHeaders: envHttpHeaders,
                environment: configuration.environment
            ),
            sessionID: sessionID,
            body: [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "tools/call",
                "params": params
            ],
            transport: configuration.mcpHTTPTransport,
            server: server
        )
        return try mcpToolCallResult(from: toolResponse.object, server: server)
    }

    fileprivate static func mcpToolCallRequestParams(tool: String, arguments: Any?, meta: Any) -> [String: Any] {
        var params: [String: Any] = [
            "name": tool,
            "_meta": meta
        ]
        if let arguments {
            params["arguments"] = arguments
        }
        return params
    }

    fileprivate static func mcpToolCallRequestParamsData(_ params: [String: Any], server: String) throws -> Data {
        guard JSONSerialization.isValidJSONObject(params) else {
            throw AppServerError.internalError("invalid MCP tool call params for \(server)")
        }
        return try JSONSerialization.data(withJSONObject: params)
    }

    fileprivate static func mcpToolCallResult(from response: [String: Any], server: String) throws -> AppServerJSONObject {
        guard let result = response["result"] as? [String: Any] else {
            if let error = response["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw AppServerError.internalError(message)
            }
            throw AppServerError.internalError("MCP server \(server) returned a response without result")
        }
        guard result["content"] is [Any] else {
            throw AppServerError.internalError("MCP server \(server) returned a tool call result without content")
        }
        return AppServerJSONObject(object: result)
    }

    fileprivate static func mcpStreamableHTTPRequest(
        url: String,
        headers: [String: String],
        sessionID: String?,
        body: [String: Any],
        transport: AppServerMcpHTTPTransport,
        timeoutSeconds: Double? = nil,
        server: String
    ) async throws -> (object: [String: Any], headers: [String: String]) {
        guard let endpoint = URL(string: url) else {
            throw AppServerError.internalError("invalid MCP server URL for \(server): \(url)")
        }
        guard JSONSerialization.isValidJSONObject(body) else {
            throw AppServerError.internalError("invalid MCP request body for \(server)")
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        if let timeoutSeconds {
            request.timeoutInterval = max(timeoutSeconds, 0.1)
        }
        if let sessionID {
            request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        }
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let response = try await transport(request)
        guard (200..<300).contains(response.statusCode) else {
            throw AppServerError.internalError("MCP server \(server) returned HTTP \(response.statusCode)")
        }
        return (try mcpJSONObject(from: response.body, server: server), response.headers)
    }

    fileprivate static func mcpSessionID(from headers: [String: String]) -> String? {
        for (name, value) in headers where name.caseInsensitiveCompare("mcp-session-id") == .orderedSame {
            return value
        }
        return nil
    }

    fileprivate static func mcpHTTPHeaders(
        bearerTokenEnvVar: String?,
        httpHeaders: [String: String]?,
        envHttpHeaders: [String: String]?,
        environment: [String: String]
    ) -> [String: String] {
        var headers: [String: String] = [:]
        for (name, value) in httpHeaders ?? [:] where isValidHTTPHeaderName(name) && isValidHTTPHeaderValue(value) {
            headers[name] = value
        }
        for (name, envVar) in envHttpHeaders ?? [:] {
            guard let value = environment[envVar], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            guard isValidHTTPHeaderName(name), isValidHTTPHeaderValue(value) else {
                continue
            }
            headers[name] = value
        }
        if let bearerTokenEnvVar,
           let bearerToken = environment[bearerTokenEnvVar],
           !bearerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            headers["Authorization"] = "Bearer \(bearerToken)"
        }
        return headers
    }

    fileprivate static func isValidHTTPHeaderName(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.allSatisfy { byte in
            byte > 32 && byte < 127 && byte != 58
        }
    }

    fileprivate static func isValidHTTPHeaderValue(_ value: String) -> Bool {
        value.utf8.allSatisfy { byte in
            byte == 9 || (byte >= 32 && byte != 127)
        }
    }

    fileprivate static func mcpJSONObject(from data: Data, server: String) throws -> [String: Any] {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return object
        }
        let text = String(decoding: data, as: UTF8.self)
        for event in text.components(separatedBy: "\n\n") {
            let dataLines = event
                .split(separator: "\n")
                .compactMap { line -> String? in
                    guard line.hasPrefix("data:") else {
                        return nil
                    }
                    return String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                }
            guard !dataLines.isEmpty else {
                continue
            }
            let payload = dataLines.joined(separator: "\n")
            if let object = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] {
                return object
            }
        }
        throw AppServerError.internalError("MCP server \(server) returned invalid JSON")
    }

    fileprivate static func mcpServerToolCallResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        let threadID = try materializedThreadID(params: params, configuration: configuration)
        let cwdFallback = try mcpThreadCwdFallback(params: params, configuration: configuration)
        guard let server = stringParam(params?["server"]), !server.isEmpty else {
            throw AppServerError.invalidRequest("missing server")
        }
        guard let tool = stringParam(params?["tool"]), !tool.isEmpty else {
            throw AppServerError.invalidRequest("missing tool")
        }
        let arguments = params?["arguments"]
        let meta = mcpToolCallMeta(params?["_meta"], threadID: threadID)
        let runtimeConfig: CodexRuntimeConfig
        do {
            runtimeConfig = try CodexConfigLoader.load(
                codexHome: configuration.codexHome,
                systemConfigFile: nil,
                environment: configuration.environment
            )
        } catch {
            throw AppServerError.internalError("failed to load MCP server config: \(error)")
        }
        guard let effectiveServer = try effectiveMcpServer(
            named: server,
            runtimeConfig: runtimeConfig,
            configuration: configuration
        ) else {
            throw AppServerError.internalError("unknown MCP server '\(server)'")
        }
        let toolCallParams = mcpToolCallRequestParams(tool: tool, arguments: arguments, meta: meta)
        switch effectiveServer {
        case let .builtin(builtinServer):
            return try mcpBuiltinToolCallResult(
                server: builtinServer,
                name: tool,
                arguments: arguments,
                configuration: configuration
            ).object
        case let .configured(serverConfig):
            let toolCallParamsData = try mcpToolCallRequestParamsData(toolCallParams, server: server)
            return try mcpConfiguredToolCallResult(
                server: server,
                serverConfig: serverConfig,
                toolCallParams: toolCallParams,
                toolCallParamsData: toolCallParamsData,
                cwdFallback: cwdFallback,
                configuration: configuration
            ).object
        }
    }

    fileprivate static func mcpConfiguredToolCallResult(
        server: String,
        serverConfig: McpServerConfig,
        toolCallParams: [String: Any],
        toolCallParamsData: Data,
        cwdFallback: String,
        configuration: CodexAppServerConfiguration
    ) throws -> AppServerJSONObject {
        switch serverConfig.transport {
        case let .stdio(command, args, env, envVars, cwd):
            return try mcpStdioToolCallResult(
                server: server,
                command: command,
                args: args,
                env: env,
                envVars: envVars,
                cwd: cwd,
                cwdFallback: cwdFallback,
                params: toolCallParams,
                timeoutSeconds: serverConfig.toolTimeoutSec ?? serverConfig.startupTimeoutSec,
                configuration: configuration
            )
        case let .streamableHttp(url, bearerTokenEnvVar, httpHeaders, envHttpHeaders):
            return try runAsyncBlocking {
                try await mcpStreamableHTTPToolCallResult(
                    server: server,
                    url: url,
                    paramsData: toolCallParamsData,
                    bearerTokenEnvVar: bearerTokenEnvVar,
                    httpHeaders: httpHeaders,
                    envHttpHeaders: envHttpHeaders,
                    configuration: configuration
                )
            }
        }
    }

    fileprivate static func mcpBuiltinToolCallResult(
        server: BuiltinMcpServer,
        name: String,
        arguments: Any?,
        configuration: CodexAppServerConfiguration
    ) throws -> AppServerJSONObject {
        switch server {
        case .memories:
            let response = try MemoriesMCPServer.toolCallResponse(
                codexHome: configuration.codexHome,
                name: name,
                arguments: arguments as? [String: Any] ?? [:]
            )
            return try mcpToolCallResult(from: response, server: server.name)
        }
    }

    fileprivate static func mcpToolCallMeta(_ rawMeta: Any?, threadID: String) -> Any {
        if var meta = rawMeta as? [String: Any] {
            meta["threadId"] = threadID
            return meta
        }
        if let rawMeta {
            return rawMeta
        }
        return ["threadId": threadID]
    }

    private static func mcpThreadCwdFallback(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> String {
        var cwdFallback = configuration.cwd.path
        if params?["threadId"] != nil {
            let threadID = try materializedThreadID(params: params, configuration: configuration)
            if let rolloutPath = try RolloutListing.findConversationPathByIDString(
                codexHome: configuration.codexHome,
                idString: threadID
            ) {
                let summary = try RolloutSummary(
                    path: rolloutPath,
                    defaultProvider: configuration.defaultModelProvider
                )
                if !summary.cwd.isEmpty {
                    cwdFallback = summary.cwd
                }
            }
        }
        return cwdFallback
    }

    private static func effectiveMcpServer(
        named name: String,
        runtimeConfig: CodexRuntimeConfig,
        configuration: CodexAppServerConfiguration
    ) throws -> EffectiveMcpServer? {
        let usesCodexBackend: Bool
        if case .chatGPT = try currentAuth(configuration: configuration)?.kind {
            usesCodexBackend = true
        } else {
            usesCodexBackend = false
        }
        let effectiveServers = runtimeConfig.runtimeMcpConfig.effectiveMcpServers(
            usesCodexBackend: usesCodexBackend,
            environment: configuration.environment
        )
        guard let server = effectiveServers[name] else {
            return nil
        }
        if case let .configured(serverConfig) = server, !serverConfig.enabled {
            return nil
        }
        return server
    }

    fileprivate static func mcpServerOAuthLoginResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration,
        notificationSink: AppServerNotificationSink?
    ) throws -> [String: Any] {
        guard let name = stringParam(params?["name"]) else {
            throw AppServerError.invalidRequest("missing name")
        }
        let explicitScopes = try rustStringArrayParam(params?["scopes"])
        let timeoutSeconds: Int?
        if params?["timeoutSecs"] != nil {
            timeoutSeconds = try rustI64Param(params?["timeoutSecs"])
        } else {
            timeoutSeconds = nil
        }
        let runtimeConfig: CodexRuntimeConfig
        do {
            runtimeConfig = try CodexConfigLoader.load(
                codexHome: configuration.codexHome,
                systemConfigFile: nil,
                environment: configuration.environment
            )
        } catch {
            throw AppServerError.internalError("failed to load MCP server config: \(error)")
        }

        guard let server = runtimeConfig.mcpServers[name] else {
            throw AppServerError.invalidRequest("No MCP server named '\(name)' found.")
        }
        let serverURL: String
        let httpHeaders: [String: String]?
        let envHttpHeaders: [String: String]?
        switch server.transport {
        case let .streamableHttp(url, _, headers, envHeaders):
            serverURL = url
            httpHeaders = headers
            envHttpHeaders = envHeaders
        case .stdio:
            throw AppServerError.invalidRequest("OAuth login is only supported for streamable HTTP servers.")
        }

        do {
            let started = try runAsyncBlocking {
                try await configuration.mcpOAuthLoginStarter(
                    AppServerMcpOAuthLoginStartRequest(
                        name: name,
                        serverURL: serverURL,
                        codexHome: configuration.codexHome,
                        storeMode: runtimeConfig.mcpOAuthCredentialsStoreMode,
                        httpHeaders: httpHeaders,
                        envHttpHeaders: envHttpHeaders,
                        environment: configuration.environment,
                        scopes: explicitScopes ?? server.scopes,
                        oauthResource: server.oauthResource,
                        timeoutSeconds: timeoutSeconds,
                        callbackPort: runtimeConfig.mcpOAuthCallbackPort,
                        callbackURL: runtimeConfig.mcpOAuthCallbackURL
                    ),
                    { success, error in
                        await sendMcpServerOAuthLoginCompletedNotification(
                            name: name,
                            success: success,
                            error: error,
                            notificationSink: notificationSink
                        )
                    }
                )
            }
            return [
                "authorizationUrl": started.authorizationURL
            ]
        } catch {
            throw AppServerError.internalError("failed to login to MCP server '\(name)': \(error)")
        }
    }

    fileprivate static func threadStartedNotification(thread: [String: Any]) -> [String: Any] {
        [
            "method": "thread/started",
            "params": [
                "thread": thread
            ]
        ]
    }

    fileprivate static func threadUnarchivedNotification(threadID: String) -> [String: Any] {
        [
            "method": "thread/unarchived",
            "params": [
                "threadId": threadID
            ]
        ]
    }

    fileprivate static func threadArchivedNotification(threadID: String) -> [String: Any] {
        [
            "method": "thread/archived",
            "params": [
                "threadId": threadID
            ]
        ]
    }

    fileprivate static func threadGoalUpdatedNotification(
        threadID: String,
        turnID: String? = nil,
        goal: [String: Any]
    ) -> [String: Any] {
        [
            "method": "thread/goal/updated",
            "params": [
                "threadId": threadID,
                "turnId": turnID as Any? ?? NSNull(),
                "goal": goal
            ]
        ]
    }

    fileprivate static func threadGoalClearedNotification(threadID: String) -> [String: Any] {
        [
            "method": "thread/goal/cleared",
            "params": [
                "threadId": threadID
            ]
        ]
    }

    fileprivate static func threadGoalResumeSnapshotNotification(
        threadID: String,
        configuration: CodexAppServerConfiguration
    ) -> [String: Any]? {
        guard let runtimeConfig = try? CodexConfigLoader.load(codexHome: configuration.codexHome),
              runtimeConfig.features.isEnabled(.goals),
              let stateStore = configuration.stateStore,
              let parsedThreadID = try? ThreadId(string: threadID)
        else {
            return nil
        }
        let goal: ThreadGoal?
        do {
            goal = try runAsyncBlocking {
                try await stateStore.getThreadGoal(threadID: parsedThreadID)
            }
        } catch {
            return nil
        }
        guard let goal else {
            return threadGoalClearedNotification(threadID: threadID)
        }
        return threadGoalUpdatedNotification(
            threadID: threadID,
            goal: threadGoalObject(goal)
        )
    }

    fileprivate static func turnStartedNotification(threadID: String, turn: [String: Any]) -> [String: Any] {
        [
            "method": "turn/started",
            "params": [
                "threadId": threadID,
                "turn": turn
            ]
        ]
    }

    fileprivate static func turnCompletedNotification(threadID: String, turnID: String, status: String) -> [String: Any] {
        turnCompletedNotification(
            threadID: threadID,
            turnID: turnID,
            status: status,
            error: nil,
            startedAt: nil,
            completedAt: nil,
            durationMilliseconds: nil
        )
    }

    fileprivate static func turnStartedNotification(
        threadID: String,
        event: TaskStartedEvent,
        fallbackTurnID: String
    ) -> [String: Any] {
        [
            "method": "turn/started",
            "params": [
                "threadId": threadID,
                "turn": turnObject(
                    id: event.turnID,
                    status: "inProgress",
                    error: nil,
                    startedAt: event.startedAt,
                    completedAt: nil,
                    durationMilliseconds: nil
                )
            ]
        ]
    }

    fileprivate static func turnCompletedNotification(
        threadID: String,
        event: TaskCompleteEvent,
        fallbackTurnID: String,
        startedAt: Int64?,
        error: [String: Any]?
    ) -> [String: Any] {
        turnCompletedNotification(
            threadID: threadID,
            turnID: event.turnID,
            status: error == nil ? "completed" : "failed",
            error: error,
            startedAt: startedAt,
            completedAt: event.completedAt,
            durationMilliseconds: event.durationMilliseconds
        )
    }

    fileprivate static func turnAbortedNotification(
        threadID: String,
        event: TurnAbortedEvent,
        fallbackTurnID: String,
        startedAt: Int64?
    ) -> [String: Any] {
        turnCompletedNotification(
            threadID: threadID,
            turnID: event.turnID ?? fallbackTurnID,
            status: "interrupted",
            error: nil,
            startedAt: startedAt,
            completedAt: event.completedAt,
            durationMilliseconds: event.durationMilliseconds
        )
    }

    private static func turnCompletedNotification(
        threadID: String,
        turnID: String,
        status: String,
        error: [String: Any]?,
        startedAt: Int64?,
        completedAt: Int64?,
        durationMilliseconds: Int64?
    ) -> [String: Any] {
        [
            "method": "turn/completed",
            "params": [
                "threadId": threadID,
                "turn": turnObject(
                    id: turnID,
                    status: status,
                    error: error,
                    startedAt: startedAt,
                    completedAt: completedAt,
                    durationMilliseconds: durationMilliseconds
                )
            ]
        ]
    }

    private static func turnObject(
        id: String,
        status: String,
        error: [String: Any]?,
        startedAt: Int64?,
        completedAt: Int64?,
        durationMilliseconds: Int64?
    ) -> [String: Any] {
        [
            "id": id,
            "items": [],
            "itemsView": "notLoaded",
            "status": status,
            "error": error as Any? ?? NSNull(),
            "startedAt": startedAt as Any? ?? NSNull(),
            "completedAt": completedAt as Any? ?? NSNull(),
            "durationMs": durationMilliseconds as Any? ?? NSNull()
        ]
    }

    fileprivate static func threadStatusChangedNotification(threadID: String, status: [String: Any]) -> [String: Any] {
        [
            "method": "thread/status/changed",
            "params": [
                "threadId": threadID,
                "status": status
            ]
        ]
    }

    fileprivate static func activeThreadStatus(activeFlags: [String] = []) -> [String: Any] {
        [
            "type": "active",
            "activeFlags": activeFlags
        ]
    }

    fileprivate static func idleThreadStatus() -> [String: Any] {
        [
            "type": "idle"
        ]
    }

    fileprivate static func systemErrorThreadStatus() -> [String: Any] {
        [
            "type": "systemError"
        ]
    }

    fileprivate static func turnDiffUpdatedNotification(threadID: String, turnID: String, diff: String) -> [String: Any] {
        [
            "method": "turn/diff/updated",
            "params": [
                "threadId": threadID,
                "turnId": turnID,
                "diff": diff
            ]
        ]
    }

    fileprivate static func turnPlanUpdatedNotification(
        threadID: String,
        turnID: String,
        planUpdate: UpdatePlanArguments
    ) -> [String: Any] {
        [
            "method": "turn/plan/updated",
            "params": [
                "threadId": threadID,
                "turnId": turnID,
                "explanation": planUpdate.explanation as Any? ?? NSNull(),
                "plan": planUpdate.plan.map { item in
                    [
                        "step": item.step,
                        "status": turnPlanStepStatus(item.status)
                    ]
                }
            ]
        ]
    }

    private static func turnPlanStepStatus(_ status: StepStatus) -> String {
        switch status {
        case .pending:
            return "pending"
        case .inProgress:
            return "inProgress"
        case .completed:
            return "completed"
        }
    }

    fileprivate static func tokenCountNotifications(
        threadID: String,
        turnID: String,
        event: TokenCountEvent
    ) -> [[String: Any]] {
        var notifications: [[String: Any]] = []
        if let info = event.info {
            notifications.append([
                "method": "thread/tokenUsage/updated",
                "params": [
                    "threadId": threadID,
                    "turnId": turnID,
                    "tokenUsage": tokenUsageInfoObject(info)
                ]
            ])
        }
        if let rateLimits = event.rateLimits {
            notifications.append([
                "method": "account/rateLimits/updated",
                "params": [
                    "rateLimits": rateLimitSnapshotObject(rateLimits)
                ]
            ])
        }
        return notifications
    }

    private static func tokenUsageInfoObject(_ info: TokenUsageInfo) -> [String: Any] {
        [
            "total": tokenUsageBreakdownObject(info.totalTokenUsage),
            "last": tokenUsageBreakdownObject(info.lastTokenUsage),
            "modelContextWindow": info.modelContextWindow as Any? ?? NSNull()
        ]
    }

    private static func tokenUsageBreakdownObject(_ usage: TokenUsage) -> [String: Any] {
        [
            "totalTokens": usage.totalTokens,
            "inputTokens": usage.inputTokens,
            "cachedInputTokens": usage.cachedInputTokens,
            "outputTokens": usage.outputTokens,
            "reasoningOutputTokens": usage.reasoningOutputTokens
        ]
    }

    fileprivate static func agentMessageDeltaNotification(
        threadID: String,
        turnID: String,
        event: AgentMessageContentDeltaEvent
    ) -> [String: Any] {
        [
            "method": "item/agentMessage/delta",
            "params": [
                "threadId": threadID,
                "turnId": turnID,
                "itemId": event.itemID,
                "delta": event.delta
            ]
        ]
    }

    fileprivate static func planDeltaNotification(threadID: String, turnID: String, event: PlanDeltaEvent) -> [String: Any] {
        [
            "method": "item/plan/delta",
            "params": [
                "threadId": threadID,
                "turnId": turnID,
                "itemId": event.itemID,
                "delta": event.delta
            ]
        ]
    }

    fileprivate static func reasoningSummaryTextDeltaNotification(
        threadID: String,
        turnID: String,
        event: ReasoningContentDeltaEvent
    ) -> [String: Any] {
        [
            "method": "item/reasoning/summaryTextDelta",
            "params": [
                "threadId": threadID,
                "turnId": turnID,
                "itemId": event.itemID,
                "delta": event.delta,
                "summaryIndex": event.summaryIndex
            ]
        ]
    }

    fileprivate static func reasoningTextDeltaNotification(
        threadID: String,
        turnID: String,
        event: ReasoningRawContentDeltaEvent
    ) -> [String: Any] {
        [
            "method": "item/reasoning/textDelta",
            "params": [
                "threadId": threadID,
                "turnId": turnID,
                "itemId": event.itemID,
                "delta": event.delta,
                "contentIndex": event.contentIndex
            ]
        ]
    }

    fileprivate static func reasoningSummaryPartAddedNotification(
        threadID: String,
        turnID: String,
        event: AgentReasoningSectionBreakEvent
    ) -> [String: Any] {
        [
            "method": "item/reasoning/summaryPartAdded",
            "params": [
                "threadId": threadID,
                "turnId": turnID,
                "itemId": event.itemID,
                "summaryIndex": event.summaryIndex
            ]
        ]
    }

    fileprivate static func commandExecutionOutputDeltaNotification(
        threadID: String,
        turnID: String,
        event: ExecCommandOutputDeltaEvent
    ) -> [String: Any] {
        [
            "method": "item/commandExecution/outputDelta",
            "params": [
                "threadId": threadID,
                "turnId": turnID,
                "itemId": event.callID,
                "delta": String(decoding: event.chunk, as: UTF8.self)
            ]
        ]
    }

    fileprivate static func commandExecutionStartedNotification(
        threadID: String,
        turnID: String,
        event: ExecCommandBeginEvent
    ) -> [String: Any] {
        [
            "method": "item/started",
            "params": [
                "threadId": threadID,
                "turnId": turnID,
                "item": commandExecutionItemObject(
                    id: event.callID,
                    command: event.command,
                    cwd: event.cwd,
                    processID: event.processID,
                    source: event.source,
                    status: "inProgress",
                    parsedCmd: event.parsedCmd,
                    aggregatedOutput: NSNull(),
                    exitCode: NSNull(),
                    durationMs: NSNull()
                ),
                "startedAtMs": event.startedAtMilliseconds
            ]
        ]
    }

    fileprivate static func commandExecutionCompletedNotification(
        threadID: String,
        turnID: String,
        event: ExecCommandEndEvent
    ) -> [String: Any] {
        [
            "method": "item/completed",
            "params": [
                "threadId": threadID,
                "turnId": turnID,
                "item": commandExecutionItemObject(
                    id: event.callID,
                    command: event.command,
                    cwd: event.cwd,
                    processID: event.processID,
                    source: event.source,
                    status: commandExecutionStatusObject(event.status),
                    parsedCmd: event.parsedCmd,
                    aggregatedOutput: event.aggregatedOutput.isEmpty ? NSNull() : event.aggregatedOutput,
                    exitCode: event.exitCode,
                    durationMs: durationMilliseconds(event.duration)
                ),
                "completedAtMs": event.completedAtMilliseconds
            ]
        ]
    }

    private static func commandExecutionItemObject(
        id: String,
        command: [String],
        cwd: String,
        processID: String?,
        source: ExecCommandSource,
        status: String,
        parsedCmd: [ParsedCommand],
        aggregatedOutput: Any,
        exitCode: Any,
        durationMs: Any
    ) -> [String: Any] {
        [
            "type": "commandExecution",
            "id": id,
            "command": CommandParser.shlexJoin(command),
            "cwd": cwd,
            "processId": processID as Any? ?? NSNull(),
            "source": commandExecutionSourceObject(source),
            "status": status,
            "commandActions": parsedCmd.map { commandActionObject($0, cwd: cwd) },
            "aggregatedOutput": aggregatedOutput,
            "exitCode": exitCode,
            "durationMs": durationMs
        ]
    }

    private static func commandActionObject(_ command: ParsedCommand, cwd: String) -> [String: Any] {
        switch command {
        case let .read(cmd, name, path):
            return [
                "type": "read",
                "command": cmd,
                "name": name,
                "path": commandActionReadPath(path, cwd: cwd)
            ]
        case let .listFiles(cmd, path):
            var object: [String: Any] = [
                "type": "listFiles",
                "command": cmd
            ]
            if let path {
                object["path"] = path
            }
            return object
        case let .search(cmd, query, path):
            var object: [String: Any] = [
                "type": "search",
                "command": cmd
            ]
            if let query {
                object["query"] = query
            }
            if let path {
                object["path"] = path
            }
            return object
        case let .unknown(cmd):
            return [
                "type": "unknown",
                "command": cmd
            ]
        }
    }

    private static func commandActionReadPath(_ path: String, cwd: String) -> String {
        if path.hasPrefix("/") {
            return path
        }
        return (cwd as NSString).appendingPathComponent(path)
    }

    private static func commandExecutionSourceObject(_ source: ExecCommandSource) -> String {
        switch source {
        case .agent:
            return "agent"
        case .userShell:
            return "userShell"
        case .unifiedExecStartup:
            return "unifiedExecStartup"
        case .unifiedExecInteraction:
            return "unifiedExecInteraction"
        }
    }

    private static func commandExecutionStatusObject(_ status: ExecCommandStatus) -> String {
        switch status {
        case .completed:
            return "completed"
        case .failed:
            return "failed"
        case .declined:
            return "declined"
        }
    }

    fileprivate static func terminalInteractionNotification(
        threadID: String,
        turnID: String,
        event: TerminalInteractionEvent
    ) -> [String: Any] {
        [
            "method": "item/commandExecution/terminalInteraction",
            "params": [
                "threadId": threadID,
                "turnId": turnID,
                "itemId": event.callID,
                "processId": event.processID,
                "stdin": event.stdin
            ]
        ]
    }

    fileprivate static func fileChangePatchUpdatedNotification(
        threadID: String,
        turnID: String,
        event: PatchApplyUpdatedEvent
    ) -> [String: Any] {
        [
            "method": "item/fileChange/patchUpdated",
            "params": [
                "threadId": threadID,
                "turnId": turnID,
                "itemId": event.callID,
                "changes": fileUpdateChanges(event.changes)
            ]
        ]
    }

    fileprivate static func itemStartedNotification(
        threadID: String,
        turnID: String,
        event: ItemStartedEvent
    ) -> [String: Any] {
        [
            "method": "item/started",
            "params": [
                "threadId": threadID,
                "turnId": turnID,
                "item": threadItemObject(event.item),
                "startedAtMs": event.startedAtMilliseconds
            ]
        ]
    }

    fileprivate static func itemCompletedNotification(
        threadID: String,
        turnID: String,
        event: ItemCompletedEvent
    ) -> [String: Any] {
        [
            "method": "item/completed",
            "params": [
                "threadId": threadID,
                "turnId": turnID,
                "item": threadItemObject(event.item),
                "completedAtMs": event.completedAtMilliseconds
            ]
        ]
    }

    fileprivate static func rawResponseItemNotifications(
        threadID: String,
        turnID: String,
        event: RawResponseItemEvent
    ) -> [[String: Any]] {
        var notifications: [[String: Any]] = []
        if case let .hookPrompt(hookPrompt) = EventMapping.parseTurnItem(event.item) {
            notifications.append([
                "method": "item/completed",
                "params": [
                    "threadId": threadID,
                    "turnId": turnID,
                    "item": threadItemObject(.hookPrompt(hookPrompt)),
                    "completedAtMs": currentUnixTimestampMilliseconds()
                ]
            ])
        }
        notifications.append([
            "method": "rawResponseItem/completed",
            "params": [
                "threadId": threadID,
                "turnId": turnID,
                "item": encodableJSONObject(event.item)
            ]
        ])
        return notifications
    }

    private static func threadItemObject(_ item: TurnItem) -> [String: Any] {
        switch item {
        case let .userMessage(item):
            return [
                "type": "userMessage",
                "id": item.id,
                "content": item.content.map(userInputObject)
            ]
        case let .hookPrompt(item):
            return [
                "type": "hookPrompt",
                "id": item.id,
                "fragments": item.fragments.map(hookPromptFragmentObject)
            ]
        case let .agentMessage(item):
            return [
                "type": "agentMessage",
                "id": item.id,
                "text": agentMessageText(item),
                "phase": item.phase.map(messagePhaseObject) ?? NSNull(),
                "memoryCitation": item.memoryCitation.map(memoryCitationObject) ?? NSNull()
            ]
        case let .plan(item):
            return [
                "type": "plan",
                "id": item.id,
                "text": item.text
            ]
        case let .reasoning(item):
            return [
                "type": "reasoning",
                "id": item.id,
                "summary": item.summaryText,
                "content": item.rawContent
            ]
        case let .fileChange(item):
            return [
                "type": "fileChange",
                "id": item.id,
                "changes": fileUpdateChanges(item.changes),
                "status": item.status?.rawValue ?? "inProgress"
            ]
        case let .mcpToolCall(item):
            var object: [String: Any] = [
                "type": "mcpToolCall",
                "id": item.id,
                "server": item.server,
                "tool": item.tool,
                "status": item.status.rawValue,
                "arguments": jsonObject(from: item.arguments),
                "result": item.result.map(encodableJSONObject) ?? NSNull(),
                "error": item.error.map(mcpToolCallErrorObject) ?? NSNull(),
                "durationMs": item.duration.map(durationMilliseconds) ?? NSNull()
            ]
            if let mcpAppResourceURI = item.mcpAppResourceURI {
                object["mcpAppResourceUri"] = mcpAppResourceURI
            }
            return object
        case let .webSearch(item):
            return [
                "type": "webSearch",
                "id": item.id,
                "query": item.query,
                "action": encodableJSONObject(item.action)
            ]
        case let .imageView(item):
            return [
                "type": "imageView",
                "id": item.id,
                "path": item.path.path
            ]
        case let .imageGeneration(item):
            var object: [String: Any] = [
                "type": "imageGeneration",
                "id": item.id,
                "status": item.status,
                "revisedPrompt": item.revisedPrompt as Any? ?? NSNull(),
                "result": item.result
            ]
            if let savedPath = item.savedPath {
                object["savedPath"] = savedPath.path
            }
            return object
        case let .contextCompaction(item):
            return [
                "type": "contextCompaction",
                "id": item.id
            ]
        }
    }

    private static func userInputObject(_ input: UserInput) -> [String: Any] {
        switch input {
        case let .text(text, textElements):
            return [
                "type": "text",
                "text": text,
                "textElements": textElements.map(textElementObject)
            ]
        case let .image(imageURL):
            return [
                "type": "image",
                "url": imageURL
            ]
        case let .localImage(path):
            return [
                "type": "localImage",
                "path": path
            ]
        case let .skill(name, path):
            return [
                "type": "skill",
                "name": name,
                "path": path
            ]
        case let .mention(name, path):
            return [
                "type": "mention",
                "name": name,
                "path": path
            ]
        }
    }

    private static func textElementObject(_ element: TextElement) -> [String: Any] {
        [
            "byteRange": byteRangeObject(element.byteRange),
            "placeholder": element.placeholder as Any? ?? NSNull()
        ]
    }

    private static func byteRangeObject(_ range: ByteRange) -> [String: Any] {
        [
            "start": range.start,
            "end": range.end
        ]
    }

    private static func hookPromptFragmentObject(_ fragment: HookPromptFragment) -> [String: Any] {
        [
            "text": fragment.text,
            "hookRunId": fragment.hookRunID
        ]
    }

    private static func agentMessageText(_ item: AgentMessageItem) -> String {
        item.content.map { content in
            switch content {
            case let .text(text):
                return text
            }
        }.joined()
    }

    private static func messagePhaseObject(_ phase: MessagePhase) -> String {
        switch phase {
        case .commentary:
            return "Commentary"
        case .finalAnswer:
            return "FinalAnswer"
        }
    }

    private static func memoryCitationObject(_ citation: MemoryCitation) -> [String: Any] {
        [
            "entries": citation.entries.map(memoryCitationEntryObject),
            "threadIds": citation.rolloutIDs
        ]
    }

    private static func memoryCitationEntryObject(_ entry: MemoryCitationEntry) -> [String: Any] {
        [
            "path": entry.path,
            "lineStart": entry.lineStart,
            "lineEnd": entry.lineEnd,
            "note": entry.note
        ]
    }

    private static func mcpToolCallErrorObject(_ error: McpToolCallError) -> [String: Any] {
        ["message": error.message]
    }

    private static func durationMilliseconds(_ duration: ProtocolDuration) -> Int64 {
        Int64((duration.timeInterval * 1000).rounded(.towardZero))
    }

    private static func currentUnixTimestampMilliseconds() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000).rounded(.towardZero))
    }

    private static func encodableJSONObject<T: Encodable>(_ value: T) -> Any {
        guard let data = try? JSONEncoder().encode(value),
              let object = try? JSONSerialization.jsonObject(with: data)
        else {
            return NSNull()
        }
        return object
    }

    private static func fileUpdateChanges(_ changes: [String: FileChange]) -> [[String: Any]] {
        changes
            .map { path, change in
                [
                    "path": path,
                    "kind": fileUpdateChangeKind(change),
                    "diff": fileUpdateChangeDiff(change)
                ]
            }
            .sorted { lhs, rhs in
                (lhs["path"] as? String ?? "") < (rhs["path"] as? String ?? "")
            }
    }

    private static func fileUpdateChangeKind(_ change: FileChange) -> [String: Any] {
        switch change {
        case .add:
            return ["type": "add"]
        case .delete:
            return ["type": "delete"]
        case let .update(_, movePath):
            return [
                "type": "update",
                "movePath": movePath as Any? ?? NSNull()
            ]
        }
    }

    private static func fileUpdateChangeDiff(_ change: FileChange) -> String {
        switch change {
        case let .add(content), let .delete(content):
            return content
        case let .update(unifiedDiff, movePath):
            guard let movePath else {
                return unifiedDiff
            }
            return "\(unifiedDiff)\n\nMoved to: \(movePath)"
        }
    }

    fileprivate static func mcpServerStatusUpdatedNotification(_ update: McpStartupUpdateEvent) -> [String: Any] {
        let status: String
        let error: Any
        switch update.status {
        case .starting:
            status = "starting"
            error = NSNull()
        case .ready:
            status = "ready"
            error = NSNull()
        case let .failed(message):
            status = "failed"
            error = message
        case .cancelled:
            status = "cancelled"
            error = NSNull()
        }
        return [
            "method": "mcpServer/startupStatus/updated",
            "params": [
                "name": update.server,
                "status": status,
                "error": error
            ]
        ]
    }

    fileprivate static func warningNotification(threadID: String, event: WarningEvent) -> [String: Any] {
        [
            "method": "warning",
            "params": [
                "threadId": threadID,
                "message": event.message
            ]
        ]
    }

    fileprivate static func guardianWarningNotification(threadID: String, event: WarningEvent) -> [String: Any] {
        [
            "method": "guardianWarning",
            "params": [
                "threadId": threadID,
                "message": event.message
            ]
        ]
    }

    fileprivate static func skillsChangedNotification() -> [String: Any] {
        [
            "method": "skills/changed",
            "params": [:]
        ]
    }

    fileprivate static func deprecationNoticeNotification(_ event: DeprecationNoticeEvent) -> [String: Any] {
        [
            "method": "deprecationNotice",
            "params": [
                "summary": event.summary,
                "details": event.details as Any? ?? NSNull()
            ]
        ]
    }

    fileprivate static func hookStartedNotification(threadID: String, event: HookStartedEvent) -> [String: Any] {
        [
            "method": "hook/started",
            "params": [
                "threadId": threadID,
                "turnId": event.turnID as Any? ?? NSNull(),
                "run": hookRunSummary(event.run)
            ]
        ]
    }

    fileprivate static func hookCompletedNotification(threadID: String, event: HookCompletedEvent) -> [String: Any] {
        [
            "method": "hook/completed",
            "params": [
                "threadId": threadID,
                "turnId": event.turnID as Any? ?? NSNull(),
                "run": hookRunSummary(event.run)
            ]
        ]
    }

    private static func hookRunSummary(_ run: HookRunSummary) -> [String: Any] {
        [
            "id": run.id,
            "eventName": hookEventName(run.eventName),
            "handlerType": run.handlerType.rawValue,
            "executionMode": run.executionMode.rawValue,
            "scope": run.scope.rawValue,
            "sourcePath": run.sourcePath.path,
            "source": hookSource(run.source),
            "displayOrder": run.displayOrder,
            "status": run.status.rawValue,
            "statusMessage": run.statusMessage as Any? ?? NSNull(),
            "startedAt": run.startedAt,
            "completedAt": run.completedAt as Any? ?? NSNull(),
            "durationMs": run.durationMs as Any? ?? NSNull(),
            "entries": run.entries.map(hookOutputEntry)
        ]
    }

    private static func hookOutputEntry(_ entry: HookOutputEntry) -> [String: Any] {
        [
            "kind": entry.kind.rawValue,
            "text": entry.text
        ]
    }

    private static func hookEventName(_ eventName: HookEventName) -> String {
        switch eventName {
        case .preToolUse:
            return "preToolUse"
        case .permissionRequest:
            return "permissionRequest"
        case .postToolUse:
            return "postToolUse"
        case .preCompact:
            return "preCompact"
        case .postCompact:
            return "postCompact"
        case .sessionStart:
            return "sessionStart"
        case .userPromptSubmit:
            return "userPromptSubmit"
        case .stop:
            return "stop"
        }
    }

    private static func hookSource(_ source: HookSource) -> String {
        switch source {
        case .system:
            return "system"
        case .user:
            return "user"
        case .project:
            return "project"
        case .mdm:
            return "mdm"
        case .sessionFlags:
            return "sessionFlags"
        case .plugin:
            return "plugin"
        case .cloudRequirements:
            return "cloudRequirements"
        case .legacyManagedConfigFile:
            return "legacyManagedConfigFile"
        case .legacyManagedConfigMdm:
            return "legacyManagedConfigMdm"
        case .unknown:
            return "unknown"
        }
    }

    fileprivate static func modelReroutedNotification(
        threadID: String,
        turnID: String,
        event: ModelRerouteEvent
    ) -> [String: Any] {
        [
            "method": "model/rerouted",
            "params": [
                "threadId": threadID,
                "turnId": turnID,
                "fromModel": event.fromModel,
                "toModel": event.toModel,
                "reason": modelRerouteReason(event.reason)
            ]
        ]
    }

    fileprivate static func modelVerificationNotification(
        threadID: String,
        turnID: String,
        event: ModelVerificationEvent
    ) -> [String: Any] {
        [
            "method": "model/verification",
            "params": [
                "threadId": threadID,
                "turnId": turnID,
                "verifications": event.verifications.map(modelVerification)
            ]
        ]
    }

    private static func modelRerouteReason(_ reason: ModelRerouteReason) -> String {
        switch reason {
        case .highRiskCyberActivity:
            return "highRiskCyberActivity"
        }
    }

    private static func modelVerification(_ verification: ModelVerification) -> String {
        switch verification {
        case .trustedAccessForCyber:
            return "trustedAccessForCyber"
        }
    }

    fileprivate static func errorNotification(
        threadID: String,
        turnID: String,
        event: ErrorEvent
    ) -> [String: Any]? {
        guard event.affectsTurnStatus else {
            return nil
        }
        return errorNotification(
            threadID: threadID,
            turnID: turnID,
            message: event.message,
            codexErrorInfo: event.codexErrorInfo,
            additionalDetails: nil,
            willRetry: false
        )
    }

    fileprivate static func streamErrorNotification(
        threadID: String,
        turnID: String,
        event: StreamErrorEvent
    ) -> [String: Any] {
        errorNotification(
            threadID: threadID,
            turnID: turnID,
            message: event.message,
            codexErrorInfo: event.codexErrorInfo,
            additionalDetails: event.additionalDetails,
            willRetry: true
        )
    }

    private static func errorNotification(
        threadID: String,
        turnID: String,
        message: String,
        codexErrorInfo: CodexErrorInfo?,
        additionalDetails: String?,
        willRetry: Bool
    ) -> [String: Any] {
        [
            "method": "error",
            "params": [
                "threadId": threadID,
                "turnId": turnID,
                "willRetry": willRetry,
                "error": turnErrorObject(
                    message: message,
                    codexErrorInfo: codexErrorInfo,
                    additionalDetails: additionalDetails
                )
            ]
        ]
    }

    fileprivate static func turnErrorObject(
        message: String,
        codexErrorInfo: CodexErrorInfo?,
        additionalDetails: String?
    ) -> [String: Any] {
        [
            "message": message,
            "codexErrorInfo": codexErrorInfo.map(codexErrorInfoObject) ?? NSNull(),
            "additionalDetails": additionalDetails as Any? ?? NSNull()
        ]
    }

    private static func codexErrorInfoObject(_ info: CodexErrorInfo) -> Any {
        switch info {
        case .contextWindowExceeded:
            return "contextWindowExceeded"
        case .usageLimitExceeded:
            return "usageLimitExceeded"
        case .serverOverloaded:
            return "serverOverloaded"
        case .cyberPolicy:
            return "cyberPolicy"
        case let .httpConnectionFailed(httpStatusCode):
            return ["httpConnectionFailed": httpStatusObject(httpStatusCode)]
        case let .responseStreamConnectionFailed(httpStatusCode):
            return ["responseStreamConnectionFailed": httpStatusObject(httpStatusCode)]
        case .internalServerError:
            return "internalServerError"
        case .unauthorized:
            return "unauthorized"
        case .badRequest:
            return "badRequest"
        case .sandboxError:
            return "sandboxError"
        case let .responseStreamDisconnected(httpStatusCode):
            return ["responseStreamDisconnected": httpStatusObject(httpStatusCode)]
        case let .responseTooManyFailedAttempts(httpStatusCode):
            return ["responseTooManyFailedAttempts": httpStatusObject(httpStatusCode)]
        case let .activeTurnNotSteerable(turnKind):
            return ["activeTurnNotSteerable": ["turnKind": turnKind.rawValue]]
        case .threadRollbackFailed:
            return "threadRollbackFailed"
        case .other:
            return "other"
        }
    }

    private static func httpStatusObject(_ httpStatusCode: UInt16?) -> [String: Any] {
        ["httpStatusCode": httpStatusCode as Any? ?? NSNull()]
    }

    fileprivate static func realtimeStartedNotification(
        threadID: String,
        event: RealtimeConversationStartedEvent
    ) -> [String: Any] {
        [
            "method": "thread/realtime/started",
            "params": [
                "threadId": threadID,
                "realtimeSessionId": event.realtimeSessionID as Any? ?? NSNull(),
                "version": event.version.rawValue
            ]
        ]
    }

    fileprivate static func realtimeSdpNotification(
        threadID: String,
        event: RealtimeConversationSdpEvent
    ) -> [String: Any] {
        [
            "method": "thread/realtime/sdp",
            "params": [
                "threadId": threadID,
                "sdp": event.sdp
            ]
        ]
    }

    fileprivate static func realtimeClosedNotification(
        threadID: String,
        event: RealtimeConversationClosedEvent
    ) -> [String: Any] {
        [
            "method": "thread/realtime/closed",
            "params": [
                "threadId": threadID,
                "reason": event.reason as Any? ?? NSNull()
            ]
        ]
    }

    fileprivate static func realtimeNotification(
        threadID: String,
        event: RealtimeConversationRealtimeEvent
    ) -> [String: Any]? {
        switch event.payload {
        case .sessionUpdated:
            return nil
        case let .inputAudioSpeechStarted(event):
            return realtimeItemAddedNotification(
                threadID: threadID,
                item: [
                    "type": "input_audio_buffer.speech_started",
                    "item_id": event.itemID as Any? ?? NSNull()
                ]
            )
        case let .inputTranscriptDelta(event):
            return realtimeTranscriptDeltaNotification(threadID: threadID, role: "user", delta: event.delta)
        case let .inputTranscriptDone(event):
            return realtimeTranscriptDoneNotification(threadID: threadID, role: "user", text: event.text)
        case let .outputTranscriptDelta(event):
            return realtimeTranscriptDeltaNotification(threadID: threadID, role: "assistant", delta: event.delta)
        case let .outputTranscriptDone(event):
            return realtimeTranscriptDoneNotification(threadID: threadID, role: "assistant", text: event.text)
        case let .audioOut(audio):
            return [
                "method": "thread/realtime/outputAudio/delta",
                "params": [
                    "threadId": threadID,
                    "audio": realtimeAudioChunkObject(audio)
                ]
            ]
        case .responseCreated, .responseDone, .conversationItemDone, .noopRequested:
            return nil
        case let .responseCancelled(event):
            return realtimeItemAddedNotification(
                threadID: threadID,
                item: [
                    "type": "response.cancelled",
                    "response_id": event.responseID as Any? ?? NSNull()
                ]
            )
        case let .conversationItemAdded(item):
            return realtimeItemAddedNotification(threadID: threadID, item: jsonObject(from: item))
        case let .handoffRequested(handoff):
            return realtimeItemAddedNotification(
                threadID: threadID,
                item: [
                    "type": "handoff_request",
                    "handoff_id": handoff.handoffID,
                    "item_id": handoff.itemID,
                    "input_transcript": handoff.inputTranscript,
                    "active_transcript": handoff.activeTranscript.map { entry in
                        [
                            "role": entry.role,
                            "text": entry.text
                        ]
                    }
                ]
            )
        case let .error(message):
            return [
                "method": "thread/realtime/error",
                "params": [
                    "threadId": threadID,
                    "message": message
                ]
            ]
        }
    }

    private static func realtimeItemAddedNotification(threadID: String, item: Any) -> [String: Any] {
        [
            "method": "thread/realtime/itemAdded",
            "params": [
                "threadId": threadID,
                "item": item
            ]
        ]
    }

    private static func realtimeTranscriptDeltaNotification(
        threadID: String,
        role: String,
        delta: String
    ) -> [String: Any] {
        [
            "method": "thread/realtime/transcript/delta",
            "params": [
                "threadId": threadID,
                "role": role,
                "delta": delta
            ]
        ]
    }

    private static func realtimeTranscriptDoneNotification(
        threadID: String,
        role: String,
        text: String
    ) -> [String: Any] {
        [
            "method": "thread/realtime/transcript/done",
            "params": [
                "threadId": threadID,
                "role": role,
                "text": text
            ]
        ]
    }

    private static func realtimeAudioChunkObject(_ audio: RealtimeAudioFrame) -> [String: Any] {
        [
            "data": audio.data,
            "sampleRate": audio.sampleRate,
            "numChannels": audio.numChannels,
            "samplesPerChannel": audio.samplesPerChannel as Any? ?? NSNull(),
            "itemId": audio.itemID as Any? ?? NSNull()
        ]
    }

    private static func jsonObject(from value: JSONValue) -> Any {
        switch value {
        case .null:
            return NSNull()
        case let .bool(value):
            return value
        case let .integer(value):
            return value
        case let .double(value):
            return value
        case let .string(value):
            return value
        case let .array(value):
            return value.map(jsonObject(from:))
        case let .object(value):
            return value.mapValues(jsonObject(from:))
        }
    }

    fileprivate static func runtimeEventNotifications(
        threadID: String,
        turnID: String,
        event: EventMessage
    ) -> [[String: Any]] {
        switch event {
        case let .tokenCount(event):
            return tokenCountNotifications(threadID: threadID, turnID: turnID, event: event)
        case let .rawResponseItem(event):
            return rawResponseItemNotifications(threadID: threadID, turnID: turnID, event: event)
        default:
            guard let notification = runtimeEventNotification(threadID: threadID, turnID: turnID, event: event) else {
                return []
            }
            return [notification]
        }
    }

    fileprivate static func runtimeEventNotification(
        threadID: String,
        turnID: String,
        event: EventMessage
    ) -> [String: Any]? {
        switch event {
        case let .error(event):
            return errorNotification(threadID: threadID, turnID: turnID, event: event)
        case let .streamError(event):
            return streamErrorNotification(threadID: threadID, turnID: turnID, event: event)
        case let .turnDiff(turnDiff):
            return turnDiffUpdatedNotification(
                threadID: threadID,
                turnID: turnID,
                diff: turnDiff.unifiedDiff
            )
        case let .planUpdate(planUpdate):
            return turnPlanUpdatedNotification(
                threadID: threadID,
                turnID: turnID,
                planUpdate: planUpdate
            )
        case let .threadGoalUpdated(event):
            return threadGoalUpdatedNotification(
                threadID: event.threadID.description,
                turnID: event.turnID,
                goal: threadGoalObject(event.goal)
            )
        case let .mcpStartupUpdate(update):
            return mcpServerStatusUpdatedNotification(update)
        case let .warning(event):
            return warningNotification(threadID: threadID, event: event)
        case let .guardianWarning(event):
            return guardianWarningNotification(threadID: threadID, event: event)
        case .skillsUpdateAvailable:
            return skillsChangedNotification()
        case let .deprecationNotice(event):
            return deprecationNoticeNotification(event)
        case let .hookStarted(event):
            return hookStartedNotification(threadID: threadID, event: event)
        case let .hookCompleted(event):
            return hookCompletedNotification(threadID: threadID, event: event)
        case let .modelReroute(event):
            return modelReroutedNotification(threadID: threadID, turnID: turnID, event: event)
        case let .modelVerification(event):
            return modelVerificationNotification(threadID: threadID, turnID: turnID, event: event)
        case let .realtimeConversationStarted(event):
            return realtimeStartedNotification(threadID: threadID, event: event)
        case let .realtimeConversationSdp(event):
            return realtimeSdpNotification(threadID: threadID, event: event)
        case let .realtimeConversationRealtime(event):
            return realtimeNotification(threadID: threadID, event: event)
        case let .realtimeConversationClosed(event):
            return realtimeClosedNotification(threadID: threadID, event: event)
        case let .agentMessageContentDelta(event):
            return agentMessageDeltaNotification(threadID: threadID, turnID: turnID, event: event)
        case let .planDelta(event):
            return planDeltaNotification(threadID: threadID, turnID: turnID, event: event)
        case let .reasoningContentDelta(event):
            return reasoningSummaryTextDeltaNotification(threadID: threadID, turnID: turnID, event: event)
        case let .reasoningRawContentDelta(event):
            return reasoningTextDeltaNotification(threadID: threadID, turnID: turnID, event: event)
        case let .agentReasoningSectionBreak(event):
            return reasoningSummaryPartAddedNotification(threadID: threadID, turnID: turnID, event: event)
        case let .execCommandOutputDelta(event):
            return commandExecutionOutputDeltaNotification(threadID: threadID, turnID: turnID, event: event)
        case let .terminalInteraction(event):
            return terminalInteractionNotification(threadID: threadID, turnID: turnID, event: event)
        case let .patchApplyUpdated(event):
            return fileChangePatchUpdatedNotification(threadID: threadID, turnID: turnID, event: event)
        case let .itemStarted(event):
            return itemStartedNotification(threadID: threadID, turnID: turnID, event: event)
        case let .itemCompleted(event):
            return itemCompletedNotification(threadID: threadID, turnID: turnID, event: event)
        default:
            return nil
        }
    }

    private static func reviewTurn(id: String, displayText: String) -> [String: Any] {
        let items: [[String: Any]]
        if displayText.isEmpty {
            items = []
        } else {
            items = [[
                "type": "userMessage",
                "id": id,
                "content": [[
                    "type": "text",
                    "text": displayText
                ]]
            ]]
        }
        return [
            "id": id,
            "items": items,
            "status": "inProgress",
            "error": NSNull()
        ]
    }

    fileprivate static func skillsListResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) -> [String: Any] {
        let rawCwds = stringArrayParam(params?["cwds"]) ?? []
        let cwds = rawCwds.isEmpty ? [configuration.cwd.standardizedFileURL.path] : rawCwds
        let configRules = (try? CodexConfigLayerLoader.loadConfigLayerStack(
            codexHome: configuration.codexHome,
            cliOverrides: configuration.cliConfigOverrides,
            overrides: configuration.configLayerOverrides,
            environment: configuration.environment
        )).map { skillConfigRules(from: $0.effectiveConfig()) } ?? []
        return [
            "data": cwds.map { cwd in
                var outcome = loadSkills(
                    cwd: URL(fileURLWithPath: cwd, isDirectory: true),
                    codexHome: configuration.codexHome
                )
                outcome.skills = outcome.skills.filter { isSkillEnabled($0, rules: configRules) }
                return [
                    "cwd": cwd,
                    "skills": outcome.skills.map(skillObject),
                    "errors": outcome.errors.map(skillErrorObject)
                ]
            }
        ]
    }

    fileprivate static func skillsConfigWriteResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        guard let enabled = params?["enabled"] as? Bool else {
            throw AppServerError.invalidParams("missing enabled")
        }
        let selector: SkillConfigSelector
        switch (stringParam(params?["path"]), stringParam(params?["name"])) {
        case let (path?, nil):
            selector = .path(normalizeSkillConfigPath(path))
        case let (nil, name?) where !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            selector = .name(name.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            throw AppServerError.invalidParams("skills/config/write requires exactly one of path or name")
        }

        let configFile = configuration.codexHome.appendingPathComponent("config.toml", isDirectory: false)
        var config = try CodexConfigLayerLoader.readConfig(from: configFile) ?? .table([:])
        setSkillConfig(selector: selector, enabled: enabled, in: &config)
        try FileManager.default.createDirectory(at: configuration.codexHome, withIntermediateDirectories: true)
        try renderConfigToml(config).write(to: configFile, atomically: true, encoding: .utf8)
        return ["effectiveEnabled": enabled]
    }

    fileprivate static func hooksListResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) -> [String: Any] {
        let rawCwds = stringArrayParam(params?["cwds"]) ?? []
        let cwds = rawCwds.isEmpty ? [configuration.cwd.standardizedFileURL.path] : rawCwds
        return [
            "data": cwds.map { cwd in
                let projection = catalogHookProjection(
                    cwd: URL(fileURLWithPath: cwd, isDirectory: true),
                    configuration: configuration
                )
                return [
                    "cwd": cwd,
                    "hooks": projection.hooks,
                    "warnings": projection.warnings,
                    "errors": []
                ]
            }
        ]
    }

    private struct CatalogHookProjection {
        var hooks: [[String: Any]] = []
        var warnings: [String] = []
    }

    private static func catalogHookObjects(config: ConfigValue, configFile: URL, codexHome: URL) -> [[String: Any]] {
        catalogHookProjection(
            effectiveConfig: config,
            hookLayers: [(config, configFile, "user")],
            codexHome: codexHome
        ).hooks
    }

    private static func catalogHookProjection(
        cwd: URL,
        configuration: CodexAppServerConfiguration
    ) -> CatalogHookProjection {
        guard let stack = try? CodexConfigLayerLoader.loadConfigLayerStack(
            codexHome: configuration.codexHome,
            cwd: cwd,
            cliOverrides: configuration.cliConfigOverrides,
            overrides: configuration.configLayerOverrides,
            environment: configuration.environment
        ) else {
            return CatalogHookProjection()
        }

        let hookLayers: [(ConfigValue, URL, String)] = stack.getLayers(ordering: .lowestPrecedenceFirst).compactMap { layer in
            switch layer.name {
            case let .user(file):
                return (layer.config, URL(fileURLWithPath: file.path, isDirectory: false), "user")
            case let .project(dotCodexFolder):
                return (
                    layer.config,
                    URL(fileURLWithPath: dotCodexFolder.path, isDirectory: true)
                        .appendingPathComponent("config.toml", isDirectory: false),
                    "project"
                )
            case .mdm, .system, .sessionFlags, .legacyManagedConfigTomlFromFile, .legacyManagedConfigTomlFromMdm:
                return nil
            }
        }

        return catalogHookProjection(
            effectiveConfig: stack.effectiveConfig(),
            managedHooks: stack.requirements.managedHooks,
            hookLayers: hookLayers,
            codexHome: configuration.codexHome
        )
    }

    private static func catalogHookProjection(
        effectiveConfig: ConfigValue,
        managedHooks: ManagedHooksRequirement? = nil,
        hookLayers: [(config: ConfigValue, configFile: URL, source: String)],
        codexHome: URL
    ) -> CatalogHookProjection {
        guard configFeatureEnabled("hooks", in: effectiveConfig, defaultValue: true) else {
            return CatalogHookProjection()
        }
        let hookStates = hookStateMap(from: effectiveConfig)
        var projection = CatalogHookProjection()
        if let managedHooks {
            appendManagedHookProjection(
                managedHooks,
                hookStates: hookStates,
                projection: &projection
            )
        }
        for hookLayer in hookLayers {
            projection.hooks.append(contentsOf: configHookObjects(
                config: hookLayer.config,
                configFile: hookLayer.configFile,
                source: hookLayer.source,
                hookStates: hookStates
            ))
        }
        guard configFeatureEnabled("plugins", in: effectiveConfig, defaultValue: false),
              configFeatureEnabled("plugin_hooks", in: effectiveConfig, defaultValue: false)
        else {
            return projection
        }
        for pluginID in enabledLocalPluginIDs(config: effectiveConfig) {
            guard let root = activeLocalPluginRoot(id: pluginID, codexHome: codexHome) else {
                continue
            }
            let manifest = localPluginManifest(root: root)
            let hookOutcome = localPluginHookConfigLoadOutcome(root: root, manifest: manifest)
            projection.warnings.append(contentsOf: hookOutcome.warnings)
            projection.hooks.append(contentsOf: localPluginHookMetadata(
                root: root,
                pluginID: pluginID,
                manifest: manifest,
                configs: hookOutcome.configs,
                hookStates: hookStates
            ))
        }
        return projection
    }

    private static func appendManagedHookProjection(
        _ managedHooks: ManagedHooksRequirement,
        hookStates: [String: HookState],
        projection: inout CatalogHookProjection
    ) {
        guard let managedDir = managedHooks.value.managedDirForCurrentPlatform else {
            projection.warnings.append(
                "skipping managed hooks from \(managedHooks.sourceDescription): no managed hook directory is configured for this platform"
            )
            return
        }
        let sourcePath = URL(fileURLWithPath: managedDir, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sourcePath.path, isDirectory: &isDirectory) else {
            projection.warnings.append(
                "skipping managed hooks from \(managedHooks.sourceDescription): managed hook directory \(managedDir) does not exist"
            )
            return
        }
        guard isDirectory.boolValue else {
            projection.warnings.append(
                "skipping managed hooks from \(managedHooks.sourceDescription): managed hook directory \(managedDir) is not a directory"
            )
            return
        }

        projection.hooks.append(contentsOf: configHookObjects(
            config: .table(["hooks": managedHooks.value.hooks]),
            configFile: sourcePath,
            source: managedHooks.source.rawValue,
            hookStates: hookStates,
            isManaged: true
        ))
    }

    private static func enabledLocalPluginIDs(config: ConfigValue) -> [String] {
        guard let root = configTable(config),
              let plugins = root["plugins"].flatMap(configTable)
        else {
            return []
        }
        return plugins.keys.filter { id in
            guard let pluginConfig = plugins[id].flatMap(configTable) else {
                return false
            }
            return boolConfig(pluginConfig, "enabled") == true
        }.sorted()
    }

    fileprivate static func experimentalFeatureListResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration,
        runtimeFeatureEnablement: [String: Bool] = [:]
    ) throws -> [String: Any] {
        var runtimeConfig: CodexRuntimeConfig
        do {
            runtimeConfig = try CodexConfigLoader.load(
                codexHome: configuration.codexHome,
                systemConfigFile: nil,
                environment: configuration.environment
            )
        } catch {
            throw AppServerError.internalError("failed to reload config: \(error)")
        }
        let stack = try CodexConfigLayerLoader.loadConfigLayerStack(
            codexHome: configuration.codexHome,
            cliOverrides: configuration.cliConfigOverrides,
            overrides: configuration.configLayerOverrides,
            environment: configuration.environment
        )
        applyRuntimeFeatureEnablement(
            runtimeFeatureEnablement,
            to: &runtimeConfig.features,
            protectedFeatureKeys: protectedFeatureKeys(in: stack.effectiveConfig())
        )

        let data = FeatureRegistry.specs.map { spec in
            experimentalFeatureObject(spec: spec, features: runtimeConfig.features)
        }
        let total = data.count
        if total == 0 {
            return [
                "data": [],
                "nextCursor": NSNull()
            ]
        }

        let start = try experimentalFeatureListStart(cursor: stringParam(params?["cursor"]), total: total)
        let effectiveLimit = try rustU32PaginationLimit(params?["limit"], total: total)
        let end = min(start + effectiveLimit, total)
        return [
            "data": start < end ? Array(data[start..<end]) : [],
            "nextCursor": end < total ? String(end) : NSNull()
        ].nullStripped(keepNulls: true)
    }

    fileprivate static func experimentalFeatureEnablementSetResult(
        params: [String: Any]?,
        runtimeFeatureEnablement: inout [String: Bool]
    ) throws -> [String: Any] {
        guard let rawEnablement = params?["enablement"] as? [String: Any] else {
            throw AppServerError.invalidRequest("missing enablement")
        }
        let enablement = try featureEnablementParam(rawEnablement)
        for key in enablement.keys {
            guard let spec = FeatureRegistry.specs.first(where: { $0.key == key }) else {
                if let feature = FeatureRegistry.feature(forKey: key),
                   let canonical = FeatureRegistry.specs.first(where: { $0.id == feature })?.key {
                    throw AppServerError.invalidRequest(
                        "invalid feature enablement `\(key)`: use canonical feature key `\(canonical)`"
                    )
                }
                throw AppServerError.invalidRequest("invalid feature enablement `\(key)`")
            }
            if !supportedExperimentalFeatureEnablement.contains(spec.key) {
                throw AppServerError.invalidRequest(
                    "unsupported feature enablement `\(key)`: currently supported features are \(supportedExperimentalFeatureEnablement.joined(separator: ", "))"
                )
            }
        }
        for (key, value) in enablement {
            runtimeFeatureEnablement[key] = value
        }
        return ["enablement": enablement]
    }

    fileprivate static func collaborationModeListResult() -> [String: Any] {
        [
            "data": CollaborationModeRegistry.builtinPresets.map { preset in
                [
                    "name": preset.name,
                    "mode": preset.mode?.rawValue as Any? ?? NSNull(),
                    "model": preset.model as Any? ?? NSNull(),
                    "reasoning_effort": preset.reasoningEffort?.rawValue as Any? ?? NSNull()
                ]
            }
        ]
    }

    fileprivate static func realtimeListVoicesResult() -> [String: Any] {
        [
            "voices": [
                "v1": ["juniper", "maple", "spruce", "ember", "vale", "breeze", "arbor", "sol", "cove"],
                "v2": ["alloy", "ash", "ballad", "coral", "echo", "sage", "shimmer", "verse", "marin", "cedar"],
                "defaultV1": "cove",
                "defaultV2": "marin"
            ]
        ]
    }

    fileprivate static func realtimeControlResult(
        method: String,
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration,
        runtimeFeatureEnablement: [String: Bool] = [:]
    ) throws -> [String: Any] {
        let threadID = try rustRequiredStringParam(params?["threadId"], field: "threadId")
        let conversationID: ConversationId
        do {
            conversationID = try ConversationId(string: threadID)
        } catch {
            throw AppServerError.invalidRequest("invalid thread id: \(error)")
        }
        _ = try rolloutPathForConversation(conversationID, configuration: configuration)

        var runtimeConfig: CodexRuntimeConfig
        do {
            runtimeConfig = try CodexConfigLoader.load(
                codexHome: configuration.codexHome,
                systemConfigFile: nil,
                environment: configuration.environment
            )
        } catch {
            throw AppServerError.internalError("failed to reload config: \(error)")
        }
        let stack = try CodexConfigLayerLoader.loadConfigLayerStack(
            codexHome: configuration.codexHome,
            cliOverrides: configuration.cliConfigOverrides,
            overrides: configuration.configLayerOverrides,
            environment: configuration.environment
        )
        applyRuntimeFeatureEnablement(
            runtimeFeatureEnablement,
            to: &runtimeConfig.features,
            protectedFeatureKeys: protectedFeatureKeys(in: stack.effectiveConfig())
        )

        guard runtimeConfig.features.isEnabled(.realtimeConversation) else {
            throw AppServerError.invalidRequest("thread \(threadID) does not support realtime conversation")
        }
        try validateRealtimeControlParams(method: method, params: params)
        return [:]
    }

    private static func validateRealtimeControlParams(method: String, params: [String: Any]?) throws {
        guard let params else {
            throw AppServerError.invalidParams("missing field `threadId`")
        }

        switch method {
        case "thread/realtime/start":
            guard let rawOutputModality = params["outputModality"] else {
                throw AppServerError.invalidParams("missing field `outputModality`")
            }
            let outputModality = try rustRequiredStringParam(rawOutputModality, field: "outputModality")
            guard outputModality == "text" || outputModality == "audio" else {
                throw AppServerError.invalidParams(
                    "unknown variant `\(outputModality)`, expected `text` or `audio`"
                )
            }
            try validateRealtimeStartOptionals(params)
        case "thread/realtime/appendAudio":
            let audio = try rustRequiredObjectParam(
                params["audio"],
                field: "audio",
                typeName: "struct ThreadRealtimeAudioChunk"
            )
            try validateRealtimeAudioChunk(audio)
        case "thread/realtime/appendText":
            guard let text = params["text"] else {
                throw AppServerError.invalidParams("missing field `text`")
            }
            _ = try rustRequiredStringParam(text, field: "text")
        case "thread/realtime/stop":
            break
        default:
            break
        }
    }

    private static func validateRealtimeStartOptionals(_ params: [String: Any]) throws {
        if let prompt = params["prompt"] {
            _ = try rustOptionalStringParam(prompt)
        }
        if let realtimeSessionID = params["realtimeSessionId"] {
            _ = try rustOptionalStringParam(realtimeSessionID)
        }
        if let voice = params["voice"], !(voice is NSNull) {
            let voiceString = try rustRealtimeVoiceParam(voice)
            let validVoices: Set<String> = [
                "alloy", "arbor", "ash", "ballad", "breeze", "cedar", "coral", "cove", "echo",
                "ember", "juniper", "maple", "marin", "sage", "shimmer", "sol", "spruce", "vale", "verse"
            ]
            guard validVoices.contains(voiceString) else {
                throw AppServerError.invalidRequest(
                    "Invalid request: unknown variant `\(voiceString)`, expected one of `alloy`, `arbor`, `ash`, `ballad`, `breeze`, `cedar`, `coral`, `cove`, `echo`, `ember`, `juniper`, `maple`, `marin`, `sage`, `shimmer`, `sol`, `spruce`, `vale`, `verse`"
                )
            }
        }
        if let transportValue = params["transport"], !(transportValue is NSNull) {
            let transport = try rustRequiredObjectParam(
                transportValue,
                field: "transport",
                typeName: "internally tagged enum ThreadRealtimeStartTransport"
            )
            let type = try rustRequiredStringParam(transport["type"], field: "type")
            switch type {
            case "websocket":
                break
            case "webrtc":
                guard let sdp = transport["sdp"] else {
                    throw AppServerError.invalidParams("missing field `sdp`")
                }
                _ = try rustRequiredStringParam(sdp, field: "sdp")
            default:
                throw AppServerError.invalidParams(
                    "unknown variant `\(type)`, expected `websocket` or `webrtc`"
                )
            }
        }
    }

    private static func rustRealtimeVoiceParam(_ value: Any) throws -> String {
        guard let string = value as? String else {
            throw AppServerError.invalidRequest(
                "Invalid request: \(rustInvalidTypeDescription(value)), expected string or map"
            )
        }
        return string
    }

    private static func rustRequiredObjectParam(
        _ value: Any?,
        field: String,
        typeName: String
    ) throws -> [String: Any] {
        guard let value else {
            throw AppServerError.invalidParams("missing field `\(field)`")
        }
        guard let object = value as? [String: Any] else {
            throw AppServerError.invalidRequest(
                "Invalid request: \(rustInvalidTypeDescription(value)), expected \(typeName)"
            )
        }
        return object
    }

    private static func validateRealtimeAudioChunk(_ audio: [String: Any]) throws {
        guard let data = audio["data"] else {
            throw AppServerError.invalidParams("missing field `data`")
        }
        _ = try rustRequiredStringParam(data, field: "data")
        _ = try rustRequiredUnsignedIntegerParam(
            audio["sampleRate"],
            field: "sampleRate",
            typeName: "u32",
            upperBound: UInt64(UInt32.max)
        )
        _ = try rustRequiredUnsignedIntegerParam(
            audio["numChannels"],
            field: "numChannels",
            typeName: "u16",
            upperBound: UInt64(UInt16.max)
        )
        if let samplesPerChannel = audio["samplesPerChannel"], !(samplesPerChannel is NSNull) {
            _ = try rustRequiredUnsignedIntegerParam(
                samplesPerChannel,
                field: "samplesPerChannel",
                typeName: "u32",
                upperBound: UInt64(UInt32.max)
            )
        }
        if let itemID = audio["itemId"] {
            _ = try rustOptionalStringParam(itemID)
        }
    }

    private static func rustRequiredUnsignedIntegerParam(
        _ value: Any?,
        field: String,
        typeName: String,
        upperBound: UInt64
    ) throws -> UInt64 {
        guard let value else {
            throw AppServerError.invalidParams("missing field `\(field)`")
        }
        if let number = value as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else {
                throw AppServerError.invalidRequest(
                    "Invalid request: \(rustInvalidTypeDescription(number)), expected \(typeName)"
                )
            }
            let double = number.doubleValue
            guard double.isFinite,
                  double.rounded(.towardZero) == double
            else {
                throw AppServerError.invalidRequest(
                    "Invalid request: \(rustInvalidTypeDescription(number)), expected \(typeName)"
                )
            }
            guard double >= 0,
                  double <= Double(upperBound)
            else {
                throw AppServerError.invalidRequest(
                    "Invalid request: invalid value: integer `\(Int64(double))`, expected \(typeName)"
                )
            }
            return UInt64(double)
        } else if let int = value as? Int, int >= 0 {
            let integer = UInt64(int)
            guard integer <= upperBound else {
                throw AppServerError.invalidRequest(
                    "Invalid request: invalid value: integer `\(int)`, expected \(typeName)"
                )
            }
            return integer
        }
        throw AppServerError.invalidRequest(
            "Invalid request: \(rustInvalidTypeDescription(value)), expected \(typeName)"
        )
    }

    fileprivate static func mockExperimentalMethodResult(params: [String: Any]?) -> [String: Any] {
        [
            "echoed": stringParam(params?["value"]) as Any? ?? NSNull()
        ]
    }

    fileprivate static func configReadResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration,
        runtimeFeatureEnablement: [String: Bool] = [:]
    ) throws -> [String: Any] {
        let stack = try CodexConfigLayerLoader.loadConfigLayerStack(
            codexHome: configuration.codexHome,
            cwd: try optionalAbsolutePathParam(params?["cwd"], name: "cwd").map {
                URL(fileURLWithPath: $0, isDirectory: true)
            },
            cliOverrides: configuration.cliConfigOverrides,
            overrides: configuration.configLayerOverrides,
            environment: configuration.environment
        )
        let includeLayers = boolParam(params?["includeLayers"], defaultValue: false)
        var response: [String: Any] = [
            "config": configReadConfigObject(
                effectiveConfig(
                    stack.effectiveConfig(),
                    applyingRuntimeFeatureEnablement: runtimeFeatureEnablement
                )
            ),
            "origins": metadataObjects(stack.origins())
        ]
        if includeLayers {
            response["layers"] = stack.layersHighToLow().map(layerObject)
        }
        return response
    }

    fileprivate static func configRequirementsReadResult(
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        do {
            let stack = try CodexConfigLayerLoader.loadConfigLayerStack(
                codexHome: configuration.codexHome,
                cliOverrides: configuration.cliConfigOverrides,
                overrides: configuration.configLayerOverrides,
                environment: configuration.environment
            )
            let requirements = stack.requirementsToml
            return [
                "requirements": requirements.isEmpty ? NSNull() : requirements.appServerRequirementsObject()
            ]
        } catch {
            throw AppServerError.internalError("failed to read config requirements: \(error)")
        }
    }

    fileprivate static func configValueWriteResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        guard let keyPath = stringParam(params?["keyPath"]) else {
            throw AppServerError.invalidRequest("missing keyPath")
        }
        guard let mergeStrategy = stringParam(params?["mergeStrategy"]) else {
            throw AppServerError.invalidRequest("missing mergeStrategy")
        }
        let parsedMergeStrategy = try ConfigMergeStrategy(rawValue: mergeStrategy)
        let edit = ConfigWriteEdit(
            keyPath: keyPath,
            value: try configWriteValue(params?["value"]),
            mergeStrategy: parsedMergeStrategy
        )
        return try configWriteResult(
            edits: [edit],
            filePath: stringParam(params?["filePath"]),
            expectedVersion: stringParam(params?["expectedVersion"]),
            configuration: configuration
        )
    }

    fileprivate static func configBatchWriteResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        guard let rawEdits = params?["edits"] as? [[String: Any]] else {
            throw AppServerError.invalidRequest("missing edits")
        }
        let edits = try rawEdits.map { rawEdit in
            guard let keyPath = stringParam(rawEdit["keyPath"]) else {
                throw AppServerError.invalidRequest("missing keyPath")
            }
            guard let mergeStrategy = stringParam(rawEdit["mergeStrategy"]) else {
                throw AppServerError.invalidRequest("missing mergeStrategy")
            }
            return ConfigWriteEdit(
                keyPath: keyPath,
                value: try configWriteValue(rawEdit["value"]),
                mergeStrategy: try ConfigMergeStrategy(rawValue: mergeStrategy)
            )
        }
        return try configWriteResult(
            edits: edits,
            filePath: stringParam(params?["filePath"]),
            expectedVersion: stringParam(params?["expectedVersion"]),
            configuration: configuration
        )
    }

    fileprivate static func effectiveConfigSnapshot(
        configuration: CodexAppServerConfiguration,
        runtimeFeatureEnablement: [String: Bool] = [:]
    ) throws -> ConfigValue {
        do {
            let stack = try CodexConfigLayerLoader.loadConfigLayerStack(
                codexHome: configuration.codexHome,
                cliOverrides: configuration.cliConfigOverrides,
                overrides: configuration.configLayerOverrides,
                environment: configuration.environment
            )
            return effectiveConfig(
                stack.effectiveConfig(),
                applyingRuntimeFeatureEnablement: runtimeFeatureEnablement
            )
        } catch {
            throw AppServerError.internalError("failed to reload config: \(error)")
        }
    }

    fileprivate static func userSavedConfigResult(configuration: CodexAppServerConfiguration) throws -> [String: Any] {
        let configFile = configuration.codexHome.appendingPathComponent("config.toml", isDirectory: false)
        let config = try CodexConfigLayerLoader.readConfig(from: configFile) ?? .table([:])
        return [
            "config": userSavedConfigObject(config)
        ]
    }

    fileprivate static func setDefaultModelResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        try updateDefaultModel(
            codexHome: configuration.codexHome,
            model: stringParam(params?["model"]),
            reasoningEffort: stringParam(params?["reasoningEffort"]),
            activeProfile: configuration.activeProfile
        )
        return [:]
    }

    fileprivate static func gitDiffToRemoteResult(params: [String: Any]?) throws -> [String: Any] {
        guard let cwd = stringParam(params?["cwd"]) else {
            throw AppServerError.invalidRequest("missing cwd")
        }
        let cwdURL = URL(fileURLWithPath: cwd, isDirectory: true)
        guard let state = GitInfoCollector.gitDiffToRemote(cwd: cwdURL) else {
            throw AppServerError.invalidRequest("failed to compute git diff to remote for cwd: \"\(cwd)\"")
        }
        return [
            "sha": state.sha,
            "diff": state.diff
        ]
    }

    fileprivate static func fuzzyFileSearchResult(params: [String: Any]?) throws -> [String: Any] {
        guard let query = stringParam(params?["query"]) else {
            throw AppServerError.invalidRequest("missing query")
        }
        guard !query.isEmpty else {
            return ["files": []]
        }
        let roots = stringArrayParam(params?["roots"]) ?? []
        let files = roots.flatMap { root in
            fuzzyFileSearch(query: query, root: root)
                .prefix(fuzzyFileSearchLimitPerRoot)
        }
        .sorted { lhs, rhs in
            let lhsScore = lhs["score"] as? Int ?? 0
            let rhsScore = rhs["score"] as? Int ?? 0
            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }
            return (lhs["path"] as? String ?? "") < (rhs["path"] as? String ?? "")
        }
        return ["files": files]
    }

    fileprivate static func commandExecResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        let parsed = try commandExecParams(params: params)
        guard parsed.processID == nil,
              !parsed.tty,
              !parsed.streamStdin,
              !parsed.streamStdoutStderr
        else {
            throw AppServerError.invalidRequest("live command/exec session is not implemented")
        }
        let cwd = commandExecCwd(parsed.cwd, configuration: configuration)
        let runtimeConfig = try CodexConfigLoader.load(
            codexHome: configuration.codexHome,
            cwd: configuration.cwd,
            managedConfigOverrides: configuration.configLayerOverrides,
            environment: configuration.environment
        )
        let sandbox = try commandExecSandboxConfiguration(
            parsed: parsed,
            runtimeConfig: runtimeConfig,
            commandCwd: cwd,
            configuration: configuration
        )
        return try runOneOffCommand(
            parsed.command,
            cwd: cwd,
            sandboxConfiguration: sandbox,
            timeoutMilliseconds: parsed.timeoutMs,
            outputBytesCap: parsed.outputBytesCap,
            environment: commandExecEnvironment(
                base: ExecEnvironment.createEnv(
                    policy: runtimeConfig.shellEnvironmentPolicy,
                    environment: configuration.environment
                ),
                overrides: parsed.environmentOverrides
            )
        )
    }

    fileprivate static func commandExecCwd(_ cwd: String?, configuration: CodexAppServerConfiguration) -> URL {
        guard let cwd, !cwd.isEmpty else {
            return configuration.cwd
        }
        if cwd.hasPrefix("/") {
            return URL(fileURLWithPath: cwd, isDirectory: true)
        }
        return configuration.cwd.appendingPathComponent(cwd, isDirectory: true)
    }

    fileprivate static func commandExecParams(params: [String: Any]?) throws -> AppServerCommandExecParams {
        guard let command = stringArrayParam(params?["command"]) else {
            throw AppServerError.invalidRequest("missing command")
        }
        guard !command.isEmpty else {
            throw AppServerError.invalidRequest("command must not be empty")
        }
        let processID = stringParam(params?["processId"])
        let tty = boolParam(params?["tty"], defaultValue: false)
        let streamStdin = boolParam(params?["streamStdin"], defaultValue: false)
        let streamStdoutStderr = boolParam(params?["streamStdoutStderr"], defaultValue: false)
        let disableOutputCap = boolParam(params?["disableOutputCap"], defaultValue: false)
        let disableTimeout = boolParam(params?["disableTimeout"], defaultValue: false)
        let sandboxPolicy = try commandExecSandboxPolicy(params?["sandboxPolicy"])
        try validateRustIntegerParam(params?["outputBytesCap"], expected: "usize")
        try validateRustIntegerParam(params?["timeoutMs"], expected: "i64")
        if sandboxPolicy != nil,
           let permissionProfile = params?["permissionProfile"],
           !(permissionProfile is NSNull)
        {
            throw AppServerError.invalidRequest("`permissionProfile` cannot be combined with `sandboxPolicy`")
        }
        let permissionProfile = try commandExecPermissionProfile(params?["permissionProfile"])
        if processID == nil && (tty || streamStdin || streamStdoutStderr) {
            throw AppServerError.invalidRequest("command/exec tty or streaming requires a client-supplied processId")
        }
        if params?["size"] != nil && !tty {
            throw AppServerError.invalidParams("command/exec size requires tty: true")
        }
        if disableOutputCap && params?["outputBytesCap"] != nil && !(params?["outputBytesCap"] is NSNull) {
            throw AppServerError.invalidParams("command/exec cannot set both outputBytesCap and disableOutputCap")
        }
        if disableTimeout && params?["timeoutMs"] != nil && !(params?["timeoutMs"] is NSNull) {
            throw AppServerError.invalidParams("command/exec cannot set both timeoutMs and disableTimeout")
        }
        let size = try commandExecSize(params?["size"])
        if let timeoutMs = params?["timeoutMs"] as? Int, timeoutMs < 0 {
            throw AppServerError.invalidParams("command/exec timeoutMs must be non-negative, got \(timeoutMs)")
        }
        return AppServerCommandExecParams(
            command: command,
            processID: processID,
            cwd: stringParam(params?["cwd"]),
            tty: tty,
            streamStdin: streamStdin,
            streamStdoutStderr: streamStdoutStderr,
            timeoutMs: disableTimeout ? nil : commandExecTimeoutMs(params?["timeoutMs"]),
            outputBytesCap: disableOutputCap ? nil : commandExecOutputBytesCap(params?["outputBytesCap"]),
            size: size,
            environmentOverrides: processEnvironmentOverrides(params?["env"]),
            sandboxPolicy: sandboxPolicy,
            permissionProfile: permissionProfile
        )
    }

    fileprivate static func commandExecSandboxConfiguration(
        parsed: AppServerCommandExecParams,
        runtimeConfig: CodexRuntimeConfig,
        commandCwd: URL,
        configuration: CodexAppServerConfiguration
    ) throws -> AppServerCommandExecSandboxConfiguration {
        if let permissionProfile = parsed.permissionProfile {
            let permissionProfile = permissionProfilePreservingConfiguredDenyReads(
                permissionProfile,
                runtimeConfig: runtimeConfig,
                configuration: configuration
            )
            if permissionProfile.fileSystemSandboxPolicy.hasDeniedReadRestrictions {
                return .direct(permissionProfile: permissionProfile, cwd: commandCwd)
            }
            return .legacy(
                policy: try legacySandboxPolicy(from: permissionProfile, cwd: commandCwd),
                cwd: commandCwd
            )
        }
        return .legacy(policy: parsed.sandboxPolicy ?? runtimeConfig.legacySandboxPolicy(), cwd: configuration.cwd)
    }

    private static func permissionProfilePreservingConfiguredDenyReads(
        _ permissionProfile: PermissionProfile,
        runtimeConfig: CodexRuntimeConfig,
        configuration: CodexAppServerConfiguration
    ) -> PermissionProfile {
        let configuredFileSystemPolicy = runtimeConfig.permissionProfile?.fileSystemSandboxPolicy
            ?? FileSystemSandboxPolicy.fromLegacySandboxPolicyForCwd(
                runtimeConfig.legacySandboxPolicy(),
                cwd: configuration.cwd.standardizedFileURL.path
            )
        var fileSystemPolicy = permissionProfile.fileSystemSandboxPolicy
        fileSystemPolicy.preserveDenyReadRestrictions(from: configuredFileSystemPolicy)
        return PermissionProfile.fromRuntimePermissionsWithEnforcement(
            permissionProfile.enforcement,
            fileSystem: fileSystemPolicy,
            network: permissionProfile.networkSandboxPolicy
        )
    }

    private static func legacySandboxPolicy(
        from permissionProfile: PermissionProfile,
        cwd: URL
    ) throws -> SandboxPolicy {
        do {
            return try permissionProfile.fileSystemSandboxPolicy.toLegacySandboxPolicy(
                networkPolicy: permissionProfile.networkSandboxPolicy,
                cwd: cwd.standardizedFileURL.path
            )
        } catch {
            throw AppServerError.invalidRequest("invalid permission profile: \(error)")
        }
    }

    fileprivate static func requireCommandExecPermissionProfileExperimentalAPI(
        params: [String: Any]?,
        experimentalAPIEnabled: Bool
    ) throws {
        guard !experimentalAPIEnabled,
              let permissionProfile = params?["permissionProfile"],
              !(permissionProfile is NSNull)
        else {
            return
        }
        throw AppServerError.invalidRequest("command/exec.permissionProfile requires experimentalApi capability")
    }

    fileprivate static func commandExecEnvironment(
        base: [String: String],
        overrides: [String: String?]
    ) -> [String: String] {
        var environment = base
        for (key, value) in overrides {
            if let value {
                environment[key] = value
            } else {
                environment.removeValue(forKey: key)
            }
        }
        return environment
    }

    fileprivate static func sandboxedLaunch(
        command: [String],
        sandboxConfiguration: AppServerCommandExecSandboxConfiguration,
        environment: [String: String]
    ) throws -> AppServerSandboxLaunch {
        if let permissionProfile = sandboxConfiguration.permissionProfile {
            return try sandboxedLaunch(
                command: command,
                permissionProfile: permissionProfile,
                sandboxCwd: sandboxConfiguration.cwd,
                environment: environment
            )
        }
        guard let sandboxPolicy = sandboxConfiguration.legacyPolicy else {
            throw AppServerError.internalError("missing command/exec sandbox configuration")
        }
        return try sandboxedLaunch(
            command: command,
            sandboxPolicy: sandboxPolicy,
            sandboxCwd: sandboxConfiguration.cwd,
            environment: environment
        )
    }

    private static func sandboxedLaunch(
        command: [String],
        permissionProfile: PermissionProfile,
        sandboxCwd: URL,
        environment: [String: String]
    ) throws -> AppServerSandboxLaunch {
        guard permissionProfile.enforcement != .disabled else {
            return AppServerSandboxLaunch(command: command, environment: environment)
        }
        let absoluteCwd: AbsolutePath
        do {
            absoluteCwd = try AbsolutePath(absolutePath: sandboxCwd.standardizedFileURL.path)
        } catch {
            throw AppServerError.internalError("invalid sandbox cwd: \(sandboxCwd.path)")
        }

        var sandboxEnvironment = environment
        sandboxEnvironment["CODEX_SANDBOX"] = SeatbeltSandbox.sandboxEnvironmentValue
        if !permissionProfile.networkSandboxPolicy.isEnabled {
            sandboxEnvironment["CODEX_SANDBOX_NETWORK_DISABLED"] = "1"
        }
        return AppServerSandboxLaunch(
            command: [SeatbeltSandbox.executablePath] + SeatbeltSandbox.commandArguments(
                command: command,
                permissionProfile: permissionProfile,
                sandboxPolicyCwd: absoluteCwd
            ),
            environment: sandboxEnvironment
        )
    }

    private static func sandboxedLaunch(
        command: [String],
        sandboxPolicy: SandboxPolicy,
        sandboxCwd: URL,
        environment: [String: String]
    ) throws -> AppServerSandboxLaunch {
        guard sandboxPolicy != .dangerFullAccess else {
            return AppServerSandboxLaunch(command: command, environment: environment)
        }
        let absoluteCwd: AbsolutePath
        do {
            absoluteCwd = try AbsolutePath(absolutePath: sandboxCwd.standardizedFileURL.path)
        } catch {
            throw AppServerError.internalError("invalid sandbox cwd: \(sandboxCwd.path)")
        }

        var sandboxEnvironment = environment
        sandboxEnvironment["CODEX_SANDBOX"] = SeatbeltSandbox.sandboxEnvironmentValue
        if !sandboxPolicy.hasFullNetworkAccess {
            sandboxEnvironment["CODEX_SANDBOX_NETWORK_DISABLED"] = "1"
        }
        return AppServerSandboxLaunch(
            command: [SeatbeltSandbox.executablePath] + SeatbeltSandbox.commandArguments(
                command: command,
                sandboxPolicy: sandboxPolicy,
                sandboxPolicyCwd: absoluteCwd,
                environment: environment
            ),
            environment: sandboxEnvironment
        )
    }

    fileprivate static func processSpawnEnvironment(
        base: [String: String],
        overrides: [String: String?]
    ) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment.merge(base) { _, new in new }
        for (key, value) in overrides {
            if let value {
                environment[key] = value
            } else {
                environment.removeValue(forKey: key)
            }
        }
        return environment
    }

    fileprivate static func commandExecWriteParams(params: [String: Any]?) throws -> AppServerCommandExecWriteParams {
        let processID = try commandExecProcessID(params: params)
        let deltaBase64 = stringParam(params?["deltaBase64"])
        let closeStdin = boolParam(params?["closeStdin"], defaultValue: false)
        guard deltaBase64 != nil || closeStdin else {
            throw AppServerError.invalidParams("command/exec/write requires deltaBase64 or closeStdin")
        }
        let delta = try deltaBase64.map {
            try decodeAppServerStandardBase64($0) { error in
                AppServerError.invalidParams("invalid deltaBase64: \(error)")
            }
        } ?? Data()
        return AppServerCommandExecWriteParams(
            processID: processID,
            delta: delta,
            closeStdin: closeStdin
        )
    }

    fileprivate static func commandExecWriteResult(params: [String: Any]?) throws -> [String: Any] {
        let parsed = try commandExecWriteParams(params: params)
        throw AppServerError.invalidRequest("no active command/exec for process id \"\(parsed.processID)\"")
    }

    fileprivate static func commandExecNoActiveTerminateResult(params: [String: Any]?) throws -> [String: Any] {
        let processID = try commandExecProcessID(params: params)
        throw AppServerError.invalidRequest("no active command/exec for process id \"\(processID)\"")
    }

    fileprivate static func commandExecTerminateResult(params: [String: Any]?) throws -> [String: Any] {
        let processID = try commandExecProcessID(params: params)
        throw AppServerError.invalidRequest("no active command/exec for process id \"\(processID)\"")
    }

    fileprivate static func commandExecResizeResult(params: [String: Any]?) throws -> [String: Any] {
        let processID = try commandExecProcessID(params: params)
        try validateCommandExecResizeParams(params: params)
        throw AppServerError.invalidRequest("no active command/exec for process id \"\(processID)\"")
    }

    fileprivate static func validateCommandExecResizeParams(params: [String: Any]?) throws {
        _ = try commandExecResizeSize(params: params)
    }

    fileprivate static func commandExecResizeSize(params: [String: Any]?) throws -> AppServerTerminalSize {
        guard let size = params?["size"] as? [String: Any],
              let rows = size["rows"] as? Int,
              let cols = size["cols"] as? Int
        else {
            throw AppServerError.invalidParams("command/exec/resize requires size rows and cols")
        }
        guard rows > 0, cols > 0 else {
            throw AppServerError.invalidParams("command/exec size rows and cols must be greater than 0")
        }
        return AppServerTerminalSize(rows: rows, cols: cols)
    }

    private static func commandExecSize(_ value: Any?) throws -> AppServerTerminalSize? {
        guard let value else {
            return nil
        }
        guard let size = value as? [String: Any] else {
            throw AppServerError.invalidParams("command/exec/resize requires size rows and cols")
        }
        guard let rows = size["rows"] as? Int,
              let cols = size["cols"] as? Int
        else {
            throw AppServerError.invalidParams("command/exec/resize requires size rows and cols")
        }
        guard rows > 0, cols > 0 else {
            throw AppServerError.invalidParams("command/exec size rows and cols must be greater than 0")
        }
        return AppServerTerminalSize(rows: rows, cols: cols)
    }

    private static func commandExecSandboxPolicy(_ value: Any?) throws -> SandboxPolicy? {
        guard let value, !(value is NSNull) else {
            return nil
        }
        guard let object = value as? [String: Any],
              let type = stringParam(object["type"])
        else {
            throw AppServerError.invalidRequest("invalid sandbox policy")
        }

        switch type {
        case "dangerFullAccess":
            return .dangerFullAccess
        case "readOnly":
            if legacyReadOnlyAccessIsRestricted(object["access"]) {
                throw AppServerError.invalidRequest("readOnly.access is no longer supported; use permissionProfile for restricted reads")
            }
            return boolParam(object["networkAccess"], defaultValue: false) ? .readOnlyWithNetworkAccess : .readOnly
        case "externalSandbox":
            let networkAccess = try networkAccessParam(object["networkAccess"]) ?? .restricted
            return .externalSandbox(networkAccess: networkAccess)
        case "workspaceWrite":
            if legacyReadOnlyAccessIsRestricted(object["readOnlyAccess"]) {
                throw AppServerError.invalidRequest("workspaceWrite.readOnlyAccess is no longer supported; use permissionProfile for restricted reads")
            }
            let writableRoots = try stringArrayParam(object["writableRoots"])?.map { path in
                try AbsolutePath(absolutePath: URL(fileURLWithPath: path).standardizedFileURL.path)
            } ?? []
            return .workspaceWrite(
                writableRoots: writableRoots,
                networkAccess: boolParam(object["networkAccess"], defaultValue: false),
                excludeTmpdirEnvVar: boolParam(object["excludeTmpdirEnvVar"], defaultValue: false),
                excludeSlashTmp: boolParam(object["excludeSlashTmp"], defaultValue: false)
            )
        default:
            throw AppServerError.invalidRequest("invalid sandbox policy")
        }
    }

    private static func commandExecPermissionProfile(_ value: Any?) throws -> PermissionProfile? {
        guard let value, !(value is NSNull) else {
            return nil
        }
        guard let object = value as? [String: Any],
              let type = stringParam(object["type"])
        else {
            throw AppServerError.invalidRequest("invalid permission profile")
        }

        switch type {
        case "disabled":
            return .disabled
        case "external":
            return .external(network: try permissionProfileNetworkPolicy(object["network"]))
        case "managed":
            guard let fileSystemObject = object["fileSystem"] as? [String: Any] else {
                throw AppServerError.invalidRequest("invalid permission profile")
            }
            return .managed(
                fileSystem: try permissionProfileFileSystemPermissions(fileSystemObject),
                network: try permissionProfileNetworkPolicy(object["network"])
            )
        default:
            throw AppServerError.invalidRequest("invalid permission profile")
        }
    }

    private static func permissionProfileNetworkPolicy(_ value: Any?) throws -> NetworkSandboxPolicy {
        guard let object = value as? [String: Any],
              let enabled = object["enabled"] as? Bool
        else {
            throw AppServerError.invalidRequest("invalid permission profile")
        }
        return enabled ? .enabled : .restricted
    }

    private static func permissionProfileFileSystemPermissions(
        _ object: [String: Any]
    ) throws -> ManagedFileSystemPermissions {
        guard let type = stringParam(object["type"]) else {
            throw AppServerError.invalidRequest("invalid permission profile")
        }

        switch type {
        case "unrestricted":
            return .unrestricted
        case "restricted":
            let entries = object["entries"] as? [[String: Any]] ?? []
            var coreObject: [String: Any] = [
                "type": "restricted",
                "entries": entries
            ]
            if let globScanMaxDepth = object["globScanMaxDepth"] ?? object["glob_scan_max_depth"],
               !(globScanMaxDepth is NSNull)
            {
                coreObject["glob_scan_max_depth"] = globScanMaxDepth
            }
            do {
                let data = try JSONSerialization.data(withJSONObject: coreObject)
                return try JSONDecoder().decode(ManagedFileSystemPermissions.self, from: data)
            } catch {
                throw AppServerError.invalidRequest("invalid permission profile")
            }
        default:
            throw AppServerError.invalidRequest("invalid permission profile")
        }
    }

    private static func networkAccessParam(_ value: Any?) throws -> NetworkAccess? {
        guard let value, !(value is NSNull) else {
            return nil
        }
        guard let networkAccess = stringParam(value).flatMap(NetworkAccess.init(rawValue:)) else {
            throw AppServerError.invalidRequest("invalid sandbox policy")
        }
        return networkAccess
    }

    private static func legacyReadOnlyAccessIsRestricted(_ value: Any?) -> Bool {
        guard let object = value as? [String: Any] else {
            return false
        }
        return stringParam(object["type"]) == "restricted"
    }

    fileprivate static func commandExecProcessID(params: [String: Any]?) throws -> String {
        guard let processID = stringParam(params?["processId"]), !processID.isEmpty else {
            throw AppServerError.invalidRequest("missing processId")
        }
        return processID
    }

    fileprivate static func processWriteStdinParams(params: [String: Any]?) throws -> AppServerProcessWriteStdinParams {
        let processHandle = try processHandle(params: params)
        let deltaBase64 = stringParam(params?["deltaBase64"])
        let closeStdin = boolParam(params?["closeStdin"], defaultValue: false)
        guard deltaBase64 != nil || closeStdin else {
            throw AppServerError.invalidParams("process/writeStdin requires deltaBase64 or closeStdin")
        }
        let delta = try deltaBase64.map {
            try decodeAppServerStandardBase64($0) { error in
                AppServerError.invalidParams("invalid deltaBase64: \(error)")
            }
        } ?? Data()
        return AppServerProcessWriteStdinParams(
            processHandle: processHandle,
            delta: delta,
            closeStdin: closeStdin
        )
    }

    fileprivate static func processWriteStdinResult(params: [String: Any]?) throws -> [String: Any] {
        let parsed = try processWriteStdinParams(params: params)
        throw AppServerError.invalidRequest("no active process for process handle \"\(parsed.processHandle)\"")
    }

    fileprivate static func processSpawnParams(params: [String: Any]?) throws -> AppServerProcessSpawnParams {
        guard let command = stringArrayParam(params?["command"]) else {
            throw AppServerError.invalidRequest("missing command")
        }
        guard !command.isEmpty else {
            throw AppServerError.invalidRequest("command must not be empty")
        }
        guard let processHandle = stringParam(params?["processHandle"]) else {
            throw AppServerError.invalidRequest("missing processHandle")
        }
        guard !processHandle.isEmpty else {
            throw AppServerError.invalidRequest("processHandle must not be empty")
        }
        let cwd = try absolutePathParam(params?["cwd"], name: "cwd")
        let tty = boolParam(params?["tty"], defaultValue: false)
        if params?["size"] != nil && !tty {
            throw AppServerError.invalidParams("process/spawn size requires tty: true")
        }
        let size = try processSize(params?["size"])
        try validateRustIntegerParam(params?["outputBytesCap"], expected: "usize")
        try validateRustIntegerParam(params?["timeoutMs"], expected: "i64")
        if let timeoutMs = params?["timeoutMs"] as? Int, timeoutMs < 0 {
            throw AppServerError.invalidParams("process/spawn timeoutMs must be non-negative, got \(timeoutMs)")
        }
        return AppServerProcessSpawnParams(
            command: command,
            processHandle: processHandle,
            cwd: cwd,
            tty: tty,
            streamStdin: boolParam(params?["streamStdin"], defaultValue: false),
            streamStdoutStderr: boolParam(params?["streamStdoutStderr"], defaultValue: false),
            timeoutMs: processSpawnTimeoutMs(params?["timeoutMs"]),
            outputBytesCap: processOutputBytesCap(params?["outputBytesCap"]),
            size: size,
            environmentOverrides: processEnvironmentOverrides(params?["env"])
        )
    }

    fileprivate static func processKillResult(params: [String: Any]?) throws -> [String: Any] {
        let processHandle = try processHandle(params: params)
        throw AppServerError.invalidRequest("no active process for process handle \"\(processHandle)\"")
    }

    fileprivate static func processResizePtyResult(params: [String: Any]?) throws -> [String: Any] {
        let processHandle = try processHandle(params: params)
        try validateProcessResizePtyParams(params: params)
        throw AppServerError.invalidRequest("no active process for process handle \"\(processHandle)\"")
    }

    fileprivate static func validateProcessResizePtyParams(params: [String: Any]?) throws {
        _ = try processResizePtySize(params: params)
    }

    fileprivate static func processResizePtySize(params: [String: Any]?) throws -> AppServerTerminalSize {
        guard let size = params?["size"] as? [String: Any],
              let rows = size["rows"] as? Int,
              let cols = size["cols"] as? Int
        else {
            throw AppServerError.invalidParams("process/resizePty requires size rows and cols")
        }
        guard rows > 0, cols > 0 else {
            throw AppServerError.invalidParams("process size rows and cols must be greater than 0")
        }
        return AppServerTerminalSize(rows: rows, cols: cols)
    }

    private static func processSize(_ value: Any?) throws -> AppServerTerminalSize? {
        guard let value else {
            return nil
        }
        guard let size = value as? [String: Any] else {
            throw AppServerError.invalidParams("process/resizePty requires size rows and cols")
        }
        guard let rows = size["rows"] as? Int,
              let cols = size["cols"] as? Int
        else {
            throw AppServerError.invalidParams("process/resizePty requires size rows and cols")
        }
        guard rows > 0, cols > 0 else {
            throw AppServerError.invalidParams("process size rows and cols must be greater than 0")
        }
        return AppServerTerminalSize(rows: rows, cols: cols)
    }

    fileprivate static func processHandle(params: [String: Any]?) throws -> String {
        guard let processHandle = stringParam(params?["processHandle"]), !processHandle.isEmpty else {
            throw AppServerError.invalidRequest("missing processHandle")
        }
        return processHandle
    }

    private static func commandExecTimeoutMs(_ value: Any?) -> Int {
        guard let value, !(value is NSNull) else {
            return appServerDefaultExecCommandTimeoutMs
        }
        return intParam(value, defaultValue: appServerDefaultExecCommandTimeoutMs)
    }

    private static func processSpawnTimeoutMs(_ value: Any?) -> Int? {
        guard let value else {
            return appServerDefaultExecCommandTimeoutMs
        }
        if value is NSNull {
            return nil
        }
        return intParam(value, defaultValue: appServerDefaultExecCommandTimeoutMs)
    }

    private static func processOutputBytesCap(_ value: Any?) -> Int? {
        guard let value else {
            return 1_048_576
        }
        if value is NSNull {
            return nil
        }
        return max(intParam(value, defaultValue: 1_048_576), 0)
    }

    private static func validateRustIntegerParam(_ value: Any?, expected: String) throws {
        guard let value, !(value is NSNull) else {
            return
        }
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            let bool = number.boolValue ? "true" : "false"
            throw AppServerError.invalidRequest("Invalid request: invalid type: boolean `\(bool)`, expected \(expected)")
        }
        if let int = value as? Int {
            if ["u32", "usize"].contains(expected), int < 0 {
                throw AppServerError.invalidRequest("Invalid request: invalid value: integer `\(int)`, expected \(expected)")
            }
            if expected == "u32", int > Int(UInt32.max) {
                throw AppServerError.invalidRequest("Invalid request: invalid value: integer `\(int)`, expected u32")
            }
            return
        }
        if let string = value as? String {
            throw AppServerError.invalidRequest("Invalid request: invalid type: string \"\(string)\", expected \(expected)")
        }
        if value is [Any] {
            throw AppServerError.invalidRequest("Invalid request: invalid type: sequence, expected \(expected)")
        }
        if value is [String: Any] {
            throw AppServerError.invalidRequest("Invalid request: invalid type: map, expected \(expected)")
        }
        if let number = value as? NSNumber {
            let int = number.int64Value
            if Double(int) == number.doubleValue {
                if ["u32", "usize"].contains(expected), int < 0 {
                    throw AppServerError.invalidRequest("Invalid request: invalid value: integer `\(int)`, expected \(expected)")
                }
                if expected == "u32", int > Int64(UInt32.max) {
                    throw AppServerError.invalidRequest("Invalid request: invalid value: integer `\(int)`, expected u32")
                }
                return
            }
            throw AppServerError.invalidRequest("Invalid request: invalid type: floating point `\(number)`, expected \(expected)")
        }
        throw AppServerError.invalidRequest("Invalid request: invalid type for field, expected \(expected)")
    }

    private static func rustU32Param(_ value: Any?, defaultValue: Int) throws -> Int {
        try validateRustIntegerParam(value, expected: "u32")
        guard let value, !(value is NSNull) else {
            return defaultValue
        }
        if let int = value as? Int {
            return int
        }
        if let number = value as? NSNumber {
            return Int(number.uint32Value)
        }
        return defaultValue
    }

    private static func rustI64Param(_ value: Any?) throws -> Int? {
        try validateRustIntegerParam(value, expected: "i64")
        guard let value, !(value is NSNull) else {
            return nil
        }
        if let int = value as? Int {
            return int
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        return nil
    }

    private static func rustBoolParam(_ value: Any?, defaultValue: Bool) throws -> Bool {
        guard let value, !(value is NSNull) else {
            return defaultValue
        }
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue
        }
        throw AppServerError.invalidRequest("Invalid request: \(rustInvalidTypeDescription(value)), expected a boolean")
    }

    fileprivate static func rustDefaultBoolParam(_ value: Any?, defaultValue: Bool) throws -> Bool {
        guard let value else {
            return defaultValue
        }
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue
        }
        throw AppServerError.invalidRequest("Invalid request: \(rustInvalidTypeDescription(value)), expected a boolean")
    }

    fileprivate static func rustOptionalBoolParam(_ value: Any?, defaultValue: Bool) throws -> Bool {
        guard let value, !(value is NSNull) else {
            return defaultValue
        }
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue
        }
        throw AppServerError.invalidRequest("Invalid request: \(rustInvalidTypeDescription(value)), expected a boolean")
    }

    private static func commandExecOutputBytesCap(_ value: Any?) -> Int {
        guard let value, !(value is NSNull) else {
            return 1_048_576
        }
        return max(intParam(value, defaultValue: 1_048_576), 0)
    }

    private static func processEnvironmentOverrides(_ value: Any?) -> [String: String?] {
        guard let object = value as? [String: Any] else {
            return [:]
        }
        var overrides: [String: String?] = [:]
        for (key, value) in object {
            if value is NSNull {
                overrides[key] = .some(nil)
            } else if let value = stringParam(value) {
                overrides[key] = value
            }
        }
        return overrides
    }

    fileprivate static func loginApiKeyResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration,
        cancelActiveLogin: () -> Void = {}
    ) throws -> [String: Any] {
        guard let apiKey = stringParam(params?["apiKey"]) else {
            throw AppServerError.invalidRequest("missing apiKey")
        }
        if try externalChatGPTAuthActive(configuration: configuration) {
            throw externalAuthActiveError()
        }
        if try forcedLoginMethod(configuration: configuration) == "chatgpt" {
            throw AppServerError.invalidRequest("API key login is disabled. Use ChatGPT login instead.")
        }
        cancelActiveLogin()
        do {
            try CodexAuthStorage.loginWithAPIKey(
                codexHome: configuration.codexHome,
                apiKey: apiKey,
                mode: configuration.authCredentialsStoreMode
            )
        } catch {
            throw AppServerError.internalError("failed to save api key: \(error)")
        }
        return [:]
    }

    fileprivate static func loginAccountResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration,
        cancelActiveLogin: () -> Void = {}
    ) throws -> [String: Any] {
        let type = stringParam(params?["type"])
        if type == "chatgptAuthTokens", try forcedLoginMethod(configuration: configuration) == "api" {
            throw AppServerError.invalidRequest("External ChatGPT auth is disabled. Use API key login instead.")
        }
        if type == "chatgpt", try forcedLoginMethod(configuration: configuration) == "api" {
            throw AppServerError.invalidRequest("ChatGPT login is disabled. Use API key login instead.")
        }
        if type == "chatgptAuthTokens" {
            guard let accessToken = stringParam(params?["accessToken"]) else {
                throw AppServerError.invalidRequest("missing accessToken")
            }
            guard let chatGPTAccountID = stringParam(params?["chatgptAccountId"]) else {
                throw AppServerError.invalidRequest("missing chatgptAccountId")
            }
            let chatGPTPlanType = stringParam(params?["chatgptPlanType"])
            cancelActiveLogin()
            if let forcedWorkspace = try forcedChatGPTWorkspaceID(configuration: configuration),
               chatGPTAccountID != forcedWorkspace {
                throw AppServerError.invalidRequest(
                    "External auth must use workspace \(forcedWorkspace), but received \"\(chatGPTAccountID)\"."
                )
            }
            do {
                try CodexAuthStorage.saveChatGPTAuthTokens(
                    codexHome: configuration.codexHome,
                    accessToken: accessToken,
                    chatGPTAccountID: chatGPTAccountID,
                    chatGPTPlanType: chatGPTPlanType,
                    mode: .ephemeral
                )
            } catch {
                throw AppServerError.internalError("failed to set external auth: \(error)")
            }
            return ["type": "chatgptAuthTokens"]
        }
        guard type == "apiKey" else {
            throw AppServerError.invalidRequest("unsupported account login type: \(type ?? "<missing>")")
        }
        _ = try loginApiKeyResult(params: params, configuration: configuration, cancelActiveLogin: cancelActiveLogin)
        return ["type": "apiKey"]
    }

    fileprivate static func externalAuthActiveError() -> AppServerError {
        .invalidRequest(
            "External auth is active. Use account/login/start (chatgptAuthTokens) to update it or account/logout to clear it."
        )
    }

    fileprivate static func externalChatGPTAuthActive(configuration: CodexAppServerConfiguration) throws -> Bool {
        do {
            return try CodexAuthStorage.loadEffectiveAuthDotJSON(
                codexHome: configuration.codexHome,
                mode: configuration.authCredentialsStoreMode
            )?.authMode == .chatGPTAuthTokens
        } catch {
            throw AppServerError.internalError("failed to read auth state: \(error)")
        }
    }

    fileprivate static func cancelLoginAccountResult(params: [String: Any]?) throws -> [String: Any] {
        guard let loginID = stringParam(params?["loginId"]) else {
            throw AppServerError.invalidRequest("missing loginId")
        }
        guard UUID(uuidString: loginID) != nil else {
            throw AppServerError.invalidRequest("invalid login id: \(loginID)")
        }
        return [
            "status": "notFound"
        ]
    }

    fileprivate static func feedbackUploadResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        guard let classification = stringParam(params?["classification"]) else {
            throw AppServerError.invalidRequest("missing classification")
        }
        let reason = stringParam(params?["reason"])
        let threadID = stringParam(params?["threadId"])
        let conversationID: ConversationId?
        if let threadID {
            do {
                conversationID = try ConversationId(string: threadID)
            } catch {
                throw AppServerError.invalidRequest("invalid thread id: \(error)")
            }
        } else {
            conversationID = nil
        }

        let includeLogs = boolParam(params?["includeLogs"], defaultValue: false)
        let snapshot = configuration.feedback.snapshot(sessionID: conversationID)
        let rolloutPath: URL?
        if includeLogs, let conversationID,
           let foundPath = try? RolloutListing.findConversationPathByIDString(
            codexHome: configuration.codexHome,
            idString: conversationID.description
           )
        {
            rolloutPath = URL(fileURLWithPath: foundPath, isDirectory: false)
        } else {
            rolloutPath = nil
        }

        try runAsyncBlocking {
            try await snapshot.uploadFeedback(
                classification: classification,
                reason: reason,
                includeLogs: includeLogs,
                rolloutPath: rolloutPath,
                sessionSource: .mcp,
                cliVersion: configuration.version,
                transport: configuration.feedbackUploadTransport
            )
        }
        return [
            "threadId": snapshot.threadID
        ]
    }

    fileprivate static func logoutResult(configuration: CodexAppServerConfiguration) throws -> [String: Any] {
        do {
            _ = try CodexAuthStorage.logout(
                codexHome: configuration.codexHome,
                mode: configuration.authCredentialsStoreMode
            )
        } catch {
            throw AppServerError.internalError("logout failed: \(error)")
        }
        return [:]
    }

    fileprivate static func authStatusChangeNotification(configuration: CodexAppServerConfiguration) throws -> [String: Any] {
        [
            "method": "authStatusChange",
            "params": [
                "authMethod": try currentAuth(configuration: configuration)?.method ?? NSNull()
            ].nullStripped(keepNulls: true)
        ]
    }

    fileprivate static func accountLoginCompletedNotification(
        loginID: String? = nil,
        success: Bool = true,
        error: String? = nil
    ) -> [String: Any] {
        [
            "method": "account/login/completed",
            "params": [
                "loginId": loginID ?? NSNull(),
                "success": success,
                "error": error ?? NSNull()
            ].nullStripped(keepNulls: true)
        ]
    }

    fileprivate static func accountUpdatedNotification(configuration: CodexAppServerConfiguration) throws -> [String: Any] {
        let auth = try currentAuth(configuration: configuration)
        let planType: Any
        switch auth?.kind {
        case let .chatGPT(idToken):
            planType = planTypeWireValue(idToken.chatGPTPlanType) ?? NSNull()
        case .apiKey, nil:
            planType = NSNull()
        }
        return [
            "method": "account/updated",
            "params": [
                "authMode": auth?.method ?? NSNull(),
                "planType": planType
            ].nullStripped(keepNulls: true)
        ]
    }

    fileprivate static func appListUpdatedNotification(
        configuration: CodexAppServerConfiguration,
        runtimeFeatureEnablement: [String: Bool]
    ) throws -> [String: Any]? {
        guard try appsFeatureEnabledForCurrentAuth(
            configuration: configuration,
            runtimeFeatureEnablement: runtimeFeatureEnablement
        ) else {
            return nil
        }
        return [
            "method": "app/list/updated",
            "params": [
                "data": try appList(
                    configuration: configuration,
                    runtimeFeatureEnablement: runtimeFeatureEnablement
                )
            ]
        ]
    }

    private static func appsFeatureEnabledForCurrentAuth(
        configuration: CodexAppServerConfiguration,
        runtimeFeatureEnablement: [String: Bool]
    ) throws -> Bool {
        guard try appsFeatureEnabledInCurrentConfig(
            configuration: configuration,
            runtimeFeatureEnablement: runtimeFeatureEnablement
        ) else {
            return false
        }
        let auth = try currentAuth(configuration: configuration)
        if case .chatGPT = auth?.kind {
            return true
        }
        return false
    }

    fileprivate static func appsFeatureEnabledInCurrentConfig(
        configuration: CodexAppServerConfiguration,
        runtimeFeatureEnablement: [String: Bool]
    ) throws -> Bool {
        let stack = try? CodexConfigLayerLoader.loadConfigLayerStack(
            codexHome: configuration.codexHome,
            cliOverrides: configuration.cliConfigOverrides,
            overrides: configuration.configLayerOverrides,
            environment: configuration.environment,
            systemConfigFile: nil
        )
        let configFile = configuration.codexHome.appendingPathComponent("config.toml", isDirectory: false)
        let loadedConfig = try stack?.effectiveConfig() ?? (CodexConfigLayerLoader.readConfig(from: configFile) ?? .table([:]))
        var runtimeConfig = try CodexConfigLoader.load(
            codexHome: configuration.codexHome,
            systemConfigFile: nil,
            environment: configuration.environment
        )
        applyRuntimeFeatureEnablement(
            runtimeFeatureEnablement,
            to: &runtimeConfig.features,
            protectedFeatureKeys: protectedFeatureKeys(in: loadedConfig)
        )
        return runtimeConfig.features.isEnabled(.apps)
    }

    fileprivate static func threadNameUpdatedNotification(threadID: String, threadName: String) -> [String: Any] {
        [
            "method": "thread/name/updated",
            "params": [
                "threadId": threadID,
                "threadName": threadName
            ]
        ]
    }

    fileprivate static func sendMcpServerOAuthLoginCompletedNotification(
        name: String,
        success: Bool,
        error: String?,
        notificationSink: AppServerNotificationSink?
    ) async {
        guard let notificationSink else {
            return
        }
        let notification = [
            "method": "mcpServer/oauthLogin/completed",
            "params": [
                "name": name,
                "success": success,
                "error": error as Any
            ].nullStripped()
        ] as [String: Any]
        guard let data = encodeMessages([notification]) else {
            return
        }
        await notificationSink(data)
    }

    fileprivate static func sendAccountLoginCompletedNotification(
        loginID: String?,
        success: Bool,
        error: String?,
        notificationSink: AppServerNotificationSink?
    ) async {
        guard let notificationSink else {
            return
        }
        guard let data = encodeMessages([
            accountLoginCompletedNotification(loginID: loginID, success: success, error: error)
        ]) else {
            return
        }
        await notificationSink(data)
    }

    fileprivate static func sendAccountUpdatedNotification(
        configuration: CodexAppServerConfiguration,
        notificationSink: AppServerNotificationSink?
    ) async {
        guard let notificationSink else {
            return
        }
        guard let notification = try? accountUpdatedNotification(configuration: configuration),
              let data = encodeMessages([notification])
        else {
            return
        }
        await notificationSink(data)
    }

    fileprivate static func forcedLoginMethod(configuration: CodexAppServerConfiguration) throws -> String? {
        let stack = try CodexConfigLayerLoader.loadConfigLayerStack(
            codexHome: configuration.codexHome,
            cliOverrides: configuration.cliConfigOverrides,
            overrides: configuration.configLayerOverrides,
            environment: configuration.environment
        )
        guard let table = configTable(stack.effectiveConfig()) else {
            return nil
        }
        return stringConfig(table, "forced_login_method")
    }

    fileprivate static func forcedChatGPTWorkspaceID(configuration: CodexAppServerConfiguration) throws -> String? {
        let stack = try CodexConfigLayerLoader.loadConfigLayerStack(
            codexHome: configuration.codexHome,
            cliOverrides: configuration.cliConfigOverrides,
            overrides: configuration.configLayerOverrides,
            environment: configuration.environment
        )
        guard let table = configTable(stack.effectiveConfig()) else {
            return nil
        }
        return stringConfig(table, "forced_chatgpt_workspace_id")
    }

    fileprivate static func buildUserAgent(
        configuration: CodexAppServerConfiguration,
        params: [String: Any]?,
        environment: [String: String]? = nil
    ) -> String {
        let clientInfo = params?["clientInfo"] as? [String: Any]
        let clientName = (clientInfo?["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let clientVersion = (clientInfo?["version"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let suffix = clientName.isEmpty && clientVersion.isEmpty ? "" : " (\(clientName); \(clientVersion))"
        return sanitizeHeaderValue(
            "\(configuration.originator)/\(configuration.version) \(Terminal.userAgent(environment: environment ?? configuration.environment))\(suffix)"
        )
    }

    fileprivate static func refreshTokenIfRequested(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) {
        guard boolParam(params?["refreshToken"], defaultValue: false) else {
            return
        }
        do {
            if try externalChatGPTAuthActive(configuration: configuration) {
                return
            }
        } catch {
            return
        }
        do {
            _ = try runAsyncBlocking {
                try await CodexAuthStorage.loadFreshTokenData(
                    codexHome: configuration.codexHome,
                    mode: configuration.authCredentialsStoreMode,
                    environment: configuration.environment,
                    refreshTransport: configuration.authRefreshTransport
                )
            }
        } catch {
            return
        }
    }

    fileprivate static func authStatusResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        refreshTokenIfRequested(params: params, configuration: configuration)

        guard configuration.requiresOpenAIAuth else {
            return [
                "authMethod": NSNull(),
                "authToken": NSNull(),
                "requiresOpenAIAuth": false
            ]
        }

        let includeToken = boolParam(params?["includeToken"], defaultValue: false)
        let auth = try currentAuth(configuration: configuration)
        return [
            "authMethod": auth?.method ?? NSNull(),
            "authToken": includeToken ? (auth?.token ?? NSNull()) : NSNull(),
            "requiresOpenAIAuth": true
        ].nullStripped(keepNulls: true)
    }

    fileprivate static func accountResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        refreshTokenIfRequested(params: params, configuration: configuration)

        guard configuration.requiresOpenAIAuth else {
            return [
                "account": NSNull(),
                "requiresOpenAIAuth": false
            ]
        }

        guard let auth = try currentAuth(configuration: configuration) else {
            return [
                "account": NSNull(),
                "requiresOpenAIAuth": true
            ]
        }

        let account: [String: Any]
        switch auth.kind {
        case .apiKey:
            account = ["type": "apiKey"]
        case let .chatGPT(idToken):
            guard let email = idToken.email,
                  let planType = planTypeWireValue(idToken.chatGPTPlanType)
            else {
                throw AppServerError.invalidRequest("email and plan type are required for chatgpt authentication")
            }
            account = [
                "type": "chatgpt",
                "email": email,
                "planType": planType
            ]
        }

        return [
            "account": account,
            "requiresOpenAIAuth": true
        ]
    }

    fileprivate static func accountRateLimitsResult(configuration: CodexAppServerConfiguration) throws -> [String: Any] {
        try accountRateLimitsResult(configuration: configuration, retryAfterUnauthorized: nil)
    }

    fileprivate static func accountRateLimitsResult(
        configuration: CodexAppServerConfiguration,
        retryAfterUnauthorized: ((AppServerAuth) throws -> AppServerAuth)?
    ) throws -> [String: Any] {
        guard let initialAuth = try currentAuth(configuration: configuration) else {
            throw AppServerError.invalidRequest("codex account authentication required to read rate limits")
        }
        guard case .chatGPT = initialAuth.kind else {
            throw AppServerError.invalidRequest("chatgpt authentication required to read rate limits")
        }
        guard initialAuth.accountID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
            throw AppServerError.internalError("failed to construct backend client: ChatGPT account ID not available")
        }

        let runtimeConfig: CodexRuntimeConfig
        do {
            runtimeConfig = try CodexConfigLoader.load(
                codexHome: configuration.codexHome,
                systemConfigFile: nil,
                environment: configuration.environment
            )
        } catch {
            throw AppServerError.internalError("failed to construct backend client: \(error)")
        }

        func fetch(using auth: AppServerAuth) throws -> AccountRateLimitsResult {
            guard let accountID = auth.accountID?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !accountID.isEmpty
            else {
                throw AppServerError.internalError("failed to construct backend client: ChatGPT account ID not available")
            }
            return try runAsyncBlocking {
                try await configuration.accountRateLimitsFetcher.fetchRateLimits(
                    baseURL: runtimeConfig.chatgptBaseURL,
                    accessToken: auth.token,
                    accountID: accountID
                )
            }
        }

        do {
            let result = try fetch(using: initialAuth)
            return [
                "rateLimits": rateLimitSnapshotObject(result.rateLimits),
                "rateLimitsByLimitId": result.rateLimitsByLimitID.mapValues(rateLimitSnapshotObject)
            ].nullStripped(keepNulls: true)
        } catch let error as AppServerError {
            throw error
        } catch {
            if isUnauthorizedBackendError(error), let retryAfterUnauthorized {
                let refreshedAuth = try retryAfterUnauthorized(initialAuth)
                do {
                    let result = try fetch(using: refreshedAuth)
                    return [
                        "rateLimits": rateLimitSnapshotObject(result.rateLimits),
                        "rateLimitsByLimitId": result.rateLimitsByLimitID.mapValues(rateLimitSnapshotObject)
                    ].nullStripped(keepNulls: true)
                } catch let retryError as AppServerError {
                    throw retryError
                } catch {
                    throw AppServerError.internalError("failed to fetch codex rate limits: \(error)")
                }
            }
            throw AppServerError.internalError("failed to fetch codex rate limits: \(error)")
        }
    }

    fileprivate static func sendAddCreditsNudgeEmailResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        try sendAddCreditsNudgeEmailResult(params: params, configuration: configuration, retryAfterUnauthorized: nil)
    }

    fileprivate static func sendAddCreditsNudgeEmailResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration,
        retryAfterUnauthorized: ((AppServerAuth) throws -> AppServerAuth)?
    ) throws -> [String: Any] {
        guard let initialAuth = try currentAuth(configuration: configuration) else {
            throw AppServerError.invalidRequest("codex account authentication required to notify workspace owner")
        }
        guard case .chatGPT = initialAuth.kind else {
            throw AppServerError.invalidRequest("chatgpt authentication required to notify workspace owner")
        }
        guard initialAuth.accountID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
            throw AppServerError.internalError("failed to construct backend client: ChatGPT account ID not available")
        }
        guard let rawCreditType = stringParam(params?["creditType"]) else {
            throw AppServerError.invalidRequest("missing creditType")
        }
        guard let creditType = AddCreditsNudgeCreditType(rawValue: rawCreditType) else {
            throw AppServerError.invalidRequest(
                "Invalid request: unknown variant `\(rawCreditType)`, expected `credits` or `usage_limit`"
            )
        }

        let runtimeConfig: CodexRuntimeConfig
        do {
            runtimeConfig = try CodexConfigLoader.load(
                codexHome: configuration.codexHome,
                systemConfigFile: nil,
                environment: configuration.environment
            )
        } catch {
            throw AppServerError.internalError("failed to construct backend client: \(error)")
        }

        func send(using auth: AppServerAuth) throws -> AddCreditsNudgeEmailStatus {
            guard let accountID = auth.accountID?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !accountID.isEmpty
            else {
                throw AppServerError.internalError("failed to construct backend client: ChatGPT account ID not available")
            }
            return try runAsyncBlocking {
                try await configuration.addCreditsNudgeEmailSender.send(
                    baseURL: runtimeConfig.chatgptBaseURL,
                    accessToken: auth.token,
                    accountID: accountID,
                    creditType: creditType
                )
            }
        }

        do {
            let status = try send(using: initialAuth)
            return ["status": status.rawValue]
        } catch let error as AppServerError {
            throw error
        } catch {
            if isUnauthorizedBackendError(error), let retryAfterUnauthorized {
                let refreshedAuth = try retryAfterUnauthorized(initialAuth)
                do {
                    let status = try send(using: refreshedAuth)
                    return ["status": status.rawValue]
                } catch let retryError as AppServerError {
                    throw retryError
                } catch {
                    throw AppServerError.internalError("failed to notify workspace owner: \(error)")
                }
            }
            throw AppServerError.internalError("failed to notify workspace owner: \(error)")
        }
    }

    fileprivate static func userInfoResult(configuration: CodexAppServerConfiguration) throws -> [String: Any] {
        let auth = try currentAuth(configuration: configuration)
        let email: String?
        if case let .chatGPT(idToken)? = auth?.kind {
            email = idToken.email
        } else {
            email = nil
        }
        return [
            "allegedUserEmail": email ?? NSNull()
        ].nullStripped(keepNulls: true)
    }

    private static func rateLimitSnapshotObject(_ snapshot: RateLimitSnapshot) -> [String: Any] {
        [
            "limitId": snapshot.limitID ?? NSNull(),
            "limitName": snapshot.limitName ?? NSNull(),
            "primary": rateLimitWindowObject(snapshot.primary),
            "secondary": rateLimitWindowObject(snapshot.secondary),
            "credits": creditsSnapshotObject(snapshot.credits),
            "planType": snapshot.planType?.rawValue ?? NSNull(),
            "rateLimitReachedType": snapshot.rateLimitReachedType?.rawValue ?? NSNull()
        ].nullStripped(keepNulls: true)
    }

    private static func rateLimitWindowObject(_ window: RateLimitWindow?) -> Any {
        guard let window else {
            return NSNull()
        }
        return [
            "usedPercent": Int(window.usedPercent.rounded()),
            "windowDurationMins": window.windowMinutes ?? NSNull(),
            "resetsAt": window.resetsAt ?? NSNull()
        ].nullStripped(keepNulls: true)
    }

    private static func creditsSnapshotObject(_ credits: CreditsSnapshot?) -> Any {
        guard let credits else {
            return NSNull()
        }
        return [
            "hasCredits": credits.hasCredits,
            "unlimited": credits.unlimited,
            "balance": credits.balance ?? NSNull()
        ].nullStripped(keepNulls: true)
    }

    fileprivate static func responseObject(id: Any, result: [String: Any]) -> [String: Any] {
        [
            "id": id,
            "result": result
        ]
    }

    fileprivate static func errorObject(id: Any, code: Int, message: String, data: Any? = nil) -> [String: Any] {
        var error: [String: Any] = [
            "code": code,
            "message": message
        ]
        if let data {
            error["data"] = data
        }
        return [
            "id": id,
            "error": error
        ]
    }

    fileprivate static func encodeResponse(_ response: [String: Any]) -> Data? {
        guard JSONSerialization.isValidJSONObject(response) else {
            return nil
        }
        return try? JSONSerialization.data(withJSONObject: response)
    }

    fileprivate static func runAsyncBlocking<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let result = BlockingAsyncResult<T>()
        Task {
            do {
                result.set(.success(try await operation()))
            } catch {
                result.set(.failure(error))
            }
            semaphore.signal()
        }
        semaphore.wait()
        return try result.get().get()
    }

    fileprivate static func encodeMessages(_ messages: [[String: Any]]) -> Data? {
        let encodedLines = messages.compactMap(encodeResponse)
        guard !encodedLines.isEmpty else {
            return nil
        }
        return encodedLines.enumerated().reduce(into: Data()) { data, item in
            if item.offset > 0 {
                data.append(0x0A)
            }
            data.append(item.element)
        }
    }

    private static func threadObject(
        for item: ConversationItem,
        defaultProvider: String,
        turns: [[String: Any]] = [],
        metadataOverlay: ThreadMetadata? = nil
    ) throws -> [String: Any] {
        let summary = try RolloutSummary(path: item.path, defaultProvider: defaultProvider)
        let updatedAt = item.updatedAt.map(unixSeconds) ?? summary.createdAtUnixSeconds
        let source = metadataOverlay.map { threadListSessionSource(from: $0.source) } ?? summary.source
        let gitInfo = threadListGitInfo(from: metadataOverlay) ?? summary.gitInfo
        let preview = summary.preview.isEmpty ? metadataOverlay?.firstUserMessage ?? "" : summary.preview
        let modelProvider = summary.modelProvider.isEmpty ? metadataOverlay?.modelProvider ?? defaultProvider : summary.modelProvider
        let cwd = summary.cwd.isEmpty ? metadataOverlay?.cwd ?? "" : summary.cwd
        let cliVersion = summary.cliVersion.isEmpty ? metadataOverlay?.cliVersion ?? "" : summary.cliVersion
        let threadSource = summary.threadSource ?? metadataOverlay?.threadSource?.description
        let agentNickname = summary.agentNickname ?? metadataOverlay?.agentNickname
        let agentRole = summary.agentRole ?? metadataOverlay?.agentRole
        return [
            "id": summary.id,
            "sessionId": summary.id,
            "forkedFromId": summary.forkedFromID ?? NSNull(),
            "preview": preview,
            "ephemeral": false,
            "modelProvider": modelProvider,
            "createdAt": summary.createdAtUnixSeconds,
            "updatedAt": updatedAt,
            "status": ["type": "notLoaded"],
            "path": item.path,
            "cwd": cwd,
            "cliVersion": cliVersion,
            "source": appServerSource(source),
            "threadSource": threadSource ?? NSNull(),
            "agentNickname": agentNickname ?? NSNull(),
            "agentRole": agentRole ?? NSNull(),
            "gitInfo": gitInfo ?? NSNull(),
            "name": summary.name ?? NSNull(),
            "turns": turns
        ].nullStripped(keepNulls: true)
    }

    private static func threadObject(
        for metadata: ThreadMetadata,
        defaultProvider: String,
        turns: [[String: Any]] = []
    ) throws -> [String: Any] {
        let source = threadListSessionSource(from: metadata.source)
        return [
            "id": metadata.id.description,
            "sessionId": metadata.id.description,
            "forkedFromId": NSNull(),
            "preview": metadata.firstUserMessage ?? metadata.title,
            "ephemeral": false,
            "modelProvider": metadata.modelProvider.isEmpty ? defaultProvider : metadata.modelProvider,
            "createdAt": Int(metadata.createdAt.timeIntervalSince1970),
            "updatedAt": Int(metadata.updatedAt.timeIntervalSince1970),
            "status": ["type": "notLoaded"],
            "path": metadata.rolloutPath,
            "cwd": metadata.cwd,
            "cliVersion": metadata.cliVersion,
            "source": appServerSource(source),
            "threadSource": metadata.threadSource?.description ?? NSNull(),
            "agentNickname": ((metadata.agentNickname ?? source.nickname) as Any?) ?? NSNull(),
            "agentRole": ((metadata.agentRole ?? source.agentRole) as Any?) ?? NSNull(),
            "gitInfo": threadListGitInfo(from: metadata) ?? NSNull(),
            "name": NSNull(),
            "turns": turns
        ].nullStripped(keepNulls: true)
    }

    private static func threadObject(for started: AppServerStartedConversation) -> [String: Any] {
        let timestamp = Int(Date().timeIntervalSince1970)
        return [
            "id": started.conversationID.description,
            "sessionId": started.conversationID.description,
            "forkedFromId": NSNull(),
            "preview": "",
            "ephemeral": true,
            "modelProvider": started.modelProvider,
            "createdAt": timestamp,
            "updatedAt": timestamp,
            "status": ["type": "notLoaded"],
            "path": NSNull(),
            "cwd": started.cwd.path,
            "cliVersion": "0.0.0",
            "source": "appServer",
            "threadSource": NSNull(),
            "agentNickname": NSNull(),
            "agentRole": NSNull(),
            "gitInfo": NSNull(),
            "name": NSNull(),
            "turns": []
        ].nullStripped(keepNulls: true)
    }

    private static func repairStateStoreFromThreadListPage(
        _ page: ConversationsPage,
        configuration: CodexAppServerConfiguration,
        archivedOnly: Bool
    ) throws {
        guard let stateStore = configuration.stateStore, !page.items.isEmpty else {
            return
        }
        try runAsyncBlocking {
            for item in page.items {
                guard let metadata = try? threadMetadata(
                    for: item,
                    defaultProvider: configuration.defaultModelProvider,
                    archivedOnly: archivedOnly
                ) else {
                    continue
                }
                try? await stateStore.upsertThread(metadata)
            }
        }
    }

    private static func threadMetadata(
        for item: ConversationItem,
        defaultProvider: String,
        archivedOnly: Bool
    ) throws -> ThreadMetadata {
        let summary = try RolloutSummary(path: item.path, defaultProvider: defaultProvider)
        let threadID = try ThreadId(string: summary.id)
        let createdAt = Date(timeIntervalSince1970: TimeInterval(summary.createdAtUnixSeconds))
        let modifiedAt = try? FileManager.default.attributesOfItem(atPath: item.path)[.modificationDate] as? Date
        let updatedAt = modifiedAt
            ?? item.updatedAt.map { Date(timeIntervalSince1970: TimeInterval(unixSeconds($0))) }
            ?? createdAt
        let gitInfo = summary.gitInfo
        return ThreadMetadata(
            id: threadID,
            rolloutPath: item.path,
            createdAt: createdAt,
            updatedAt: updatedAt,
            source: summary.source.description,
            modelProvider: summary.modelProvider,
            cwd: summary.cwd,
            cliVersion: summary.cliVersion,
            title: summary.preview,
            sandboxPolicy: "read-only",
            approvalMode: "on-request",
            tokensUsed: 0,
            firstUserMessage: summary.preview.isEmpty ? nil : summary.preview,
            archivedAt: archivedOnly ? updatedAt : nil,
            gitSHA: gitInfo?["sha"] as? String,
            gitBranch: gitInfo?["branch"] as? String,
            gitOriginURL: gitInfo?["originUrl"] as? String
        )
    }

    private static func threadObjects(
        for items: [ConversationItem],
        configuration: CodexAppServerConfiguration
    ) throws -> [[String: Any]] {
        let overlays = try stateMetadataOverlays(for: items, configuration: configuration)
        return try items.map { item in
            let summary = try RolloutSummary(path: item.path, defaultProvider: configuration.defaultModelProvider)
            return try threadObject(
                for: item,
                defaultProvider: configuration.defaultModelProvider,
                metadataOverlay: overlays[summary.id]
            )
        }
    }

    private static func stateMetadataOverlays(
        for items: [ConversationItem],
        configuration: CodexAppServerConfiguration
    ) throws -> [String: ThreadMetadata] {
        guard let stateStore = configuration.stateStore, !items.isEmpty else {
            return [:]
        }
        return try runAsyncBlocking {
            var overlays: [String: ThreadMetadata] = [:]
            for item in items {
                guard let summary = try? RolloutSummary(path: item.path, defaultProvider: configuration.defaultModelProvider),
                      let threadID = try? ThreadId(string: summary.id),
                      let metadata = try? await stateStore.getThread(threadID: threadID)
                else {
                    continue
                }
                overlays[summary.id] = metadata
            }
            return overlays
        }
    }

    private static func reconcileStateStoreFilteredHits(
        configuration: CodexAppServerConfiguration,
        pageSize: Int,
        cursor: ConversationCursor?,
        allowedSources: [SessionSource],
        sourceMatcher: SessionSourceMatcher?,
        modelProviders: [String]?,
        archivedOnly: Bool,
        cwdFilters: [String]?,
        searchTerm: String?,
        sortKey: ConversationSortKey,
        sortDirection: ConversationSortDirection,
        hasExplicitMetadataFilter: Bool
    ) throws {
        guard let stateStore = configuration.stateStore,
              hasExplicitMetadataFilter
        else {
            return
        }
        let filters = ThreadListFilterOptions(
            archivedOnly: archivedOnly,
            allowedSources: allowedSources.map(\.description),
            modelProviders: modelProviders,
            cwdFilters: cwdFilters?.map { URL(fileURLWithPath: $0, isDirectory: true) },
            anchor: cursor.map { ThreadListAnchor(timestamp: $0.anchorTimestamp) },
            sortKey: threadListStoreSortKey(sortKey),
            sortDirection: threadListStoreSortDirection(sortDirection),
            searchTerm: searchTerm
        )
        try runAsyncBlocking {
            let statePage = try await stateStore.listThreads(pageSize: pageSize, filters: filters)
            for item in statePage.items {
                if let sourceMatcher,
                   !sourceMatcher.matches(threadListSessionSource(from: item.source)) {
                    continue
                }
                guard FileManager.default.fileExists(atPath: item.rolloutPath) else {
                    _ = try? await stateStore.deleteThread(threadID: item.id)
                    continue
                }
                let conversation = ConversationItem(
                    path: item.rolloutPath,
                    head: [],
                    createdAt: nil,
                    updatedAt: nil
                )
                if let metadata = try? threadMetadata(
                    for: conversation,
                    defaultProvider: configuration.defaultModelProvider,
                    archivedOnly: archivedOnly
                ) {
                    try? await stateStore.upsertThread(metadata)
                }
            }
        }
    }

    private static func threadListSessionSource(from persistedSource: String) -> SessionSource {
        if let data = persistedSource.data(using: .utf8),
           let parsed = try? JSONDecoder().decode(SessionSource.self, from: data) {
            return parsed
        }
        if let quoted = try? JSONEncoder().encode(persistedSource),
           let parsed = try? JSONDecoder().decode(SessionSource.self, from: quoted) {
            return parsed
        }
        return .unknown
    }

    private static func threadListGitInfo(from metadata: ThreadMetadata) -> [String: Any]? {
        threadListGitInfo(from: Optional(metadata))
    }

    private static func threadListGitInfo(from metadata: ThreadMetadata?) -> [String: Any]? {
        guard let metadata else {
            return nil
        }
        guard metadata.gitSHA != nil || metadata.gitBranch != nil || metadata.gitOriginURL != nil else {
            return nil
        }
        return [
            "sha": metadata.gitSHA as Any,
            "branch": metadata.gitBranch as Any,
            "originUrl": metadata.gitOriginURL as Any
        ].nullStripped()
    }

    private static func unixSeconds(_ timestamp: String) -> Int {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: timestamp) {
            return Int(date.timeIntervalSince1970)
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: timestamp) {
            return Int(date.timeIntervalSince1970)
        }
        return 0
    }

    private static func buildTurnsFromRolloutEvents(at path: String) throws -> [[String: Any]] {
        let text = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
        let decoder = JSONDecoder()
        var builder = AppServerThreadHistoryBuilder()
        for rawLine in text.split(whereSeparator: \.isNewline) {
            guard let data = rawLine.data(using: .utf8),
                  let line = try? decoder.decode(RolloutLine.self, from: data),
                  case let .eventMsg(event) = line.item
            else {
                continue
            }
            builder.handle(event)
        }
        return builder.finish()
    }

    private static func rolloutPathForConversation(
        _ conversationID: ConversationId,
        configuration: CodexAppServerConfiguration,
        includeArchived: Bool = false
    ) throws -> String {
        do {
            guard let foundPath = try RolloutListing.findConversationPathByIDString(
                codexHome: configuration.codexHome,
                idString: conversationID.description,
                includeArchived: includeArchived
            ) else {
                throw AppServerError.invalidRequest("no rollout found for conversation id \(conversationID)")
            }
            return foundPath
        } catch let error as AppServerError {
            throw error
        } catch {
            throw AppServerError.invalidRequest("failed to locate conversation id \(conversationID): \(error)")
        }
    }

    private static func sandboxPolicy(for mode: SandboxMode) -> SandboxPolicy {
        SandboxPolicy.fromSandboxMode(mode)
    }

    private static func jsonObject<T: Encodable>(_ value: T) throws -> Any {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }

    private static func activePermissionProfileObject(_ profile: ActivePermissionProfile?) -> Any {
        guard let profile else {
            return NSNull()
        }
        return [
            "id": profile.id,
            "extends": profile.extends as Any? ?? NSNull(),
            "modifications": profile.modifications.map { modification -> [String: Any] in
                switch modification {
                case let .additionalWritableRoot(path):
                    return [
                        "type": "additionalWritableRoot",
                        "path": path
                    ]
                }
            }
        ]
    }

    private static func conversationObject(for item: ConversationItem, defaultProvider: String) throws -> [String: Any] {
        let summary = try RolloutSummary(path: item.path, defaultProvider: defaultProvider)
        return [
            "conversationId": summary.id,
            "path": item.path,
            "preview": summary.preview,
            "timestamp": item.createdAt as Any,
            "modelProvider": summary.modelProvider,
            "cwd": summary.cwd,
            "cliVersion": summary.cliVersion,
            "source": summary.source.description,
            "gitInfo": summary.v1GitInfo as Any
        ].nullStripped()
    }

    private static func appServerSource(_ source: SessionSource) -> String {
        switch source {
        case .cli:
            return "cli"
        case .vscode:
            return "vscode"
        case .exec:
            return "exec"
        case .mcp:
            return "appServer"
        case .custom, .internal, .subagent, .unknown:
            return "unknown"
        }
    }

    private static func listLimit(_ value: Any?) -> Int {
        min(max(intParam(value, defaultValue: defaultListLimit), 1), maxListLimit)
    }

    private static func listLimit(_ value: Any?, defaultValue: Int, maximum: Int) -> Int {
        min(max(intParam(value, defaultValue: defaultValue), 1), maximum)
    }

    private static func rustU32ListLimit(_ value: Any?) throws -> Int {
        min(max(try rustU32Param(value, defaultValue: defaultListLimit), 1), maxListLimit)
    }

    private static func rustU32PaginationLimit(_ value: Any?, total: Int) throws -> Int {
        max(try rustU32Param(value, defaultValue: total), 1)
    }

    private static func modelListStart(cursor: String?, total: Int) throws -> Int {
        guard let cursor else {
            return 0
        }
        guard let start = Int(cursor) else {
            throw AppServerError.invalidRequest("invalid cursor: \(cursor)")
        }
        guard start <= total else {
            throw AppServerError.invalidRequest("cursor \(start) exceeds total models \(total)")
        }
        return start
    }

    private static func mcpServerStatusStart(cursor: String?, total: Int) throws -> Int {
        guard let cursor else {
            return 0
        }
        guard let start = Int(cursor) else {
            throw AppServerError.invalidRequest("invalid cursor: \(cursor)")
        }
        guard start <= total else {
            throw AppServerError.invalidRequest("cursor \(start) exceeds total MCP servers \(total)")
        }
        return start
    }

    private static func experimentalFeatureListStart(cursor: String?, total: Int) throws -> Int {
        guard let cursor else {
            return 0
        }
        guard let start = Int(cursor) else {
            throw AppServerError.invalidRequest("invalid cursor: \(cursor)")
        }
        guard start <= total else {
            throw AppServerError.invalidRequest("cursor \(start) exceeds total feature flags \(total)")
        }
        return start
    }

    private static func intParam(_ value: Any?, defaultValue: Int) -> Int {
        if let int = value as? Int {
            return int
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        return defaultValue
    }

    fileprivate static func boolParam(_ value: Any?, defaultValue: Bool) -> Bool {
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        return defaultValue
    }

    private static func featureEnablementParam(_ value: [String: Any]) throws -> [String: Bool] {
        var enablement: [String: Bool] = [:]
        for (key, rawValue) in value {
            guard let boolValue = rawValue as? Bool else {
                throw AppServerError.invalidRequest("invalid feature enablement `\(key)`")
            }
            enablement[key] = boolValue
        }
        return enablement
    }

    fileprivate static func stringParam(_ value: Any?) -> String? {
        value as? String
    }

    private static func absolutePathParam(_ value: Any?, name: String) throws -> String {
        guard let path = stringParam(value) else {
            throw AppServerError.invalidRequest("missing \(name)")
        }
        guard path.hasPrefix("/") else {
            throw AppServerError.invalidRequest("Invalid request: AbsolutePathBuf deserialized without a base path")
        }
        return path
    }

    private static func optionalAbsolutePathParam(_ value: Any?, name _: String) throws -> String? {
        guard let value else {
            return nil
        }
        guard let path = stringParam(value) else {
            return nil
        }
        guard path.hasPrefix("/") else {
            throw AppServerError.invalidRequest("Invalid request: AbsolutePathBuf deserialized without a base path")
        }
        return path
    }

    private static func rustRequiredStringParam(_ value: Any?, field: String) throws -> String {
        guard let value else {
            throw AppServerError.invalidRequest("missing field `\(field)`")
        }
        guard !(value is NSNull) else {
            throw AppServerError.invalidRequest("Invalid request: invalid type: null, expected a string")
        }
        guard let string = value as? String else {
            throw AppServerError.invalidRequest("Invalid request: \(rustInvalidTypeDescription(value)), expected a string")
        }
        return string
    }

    private static func rustOptionalStringParam(_ value: Any?) throws -> String? {
        guard let value, !(value is NSNull) else {
            return nil
        }
        guard let string = value as? String else {
            throw AppServerError.invalidRequest("Invalid request: \(rustInvalidTypeDescription(value)), expected a string")
        }
        return string
    }

    private static func rustOptionalAbsolutePathParam(_ value: Any?) throws -> String? {
        guard let path = try rustOptionalStringParam(value) else {
            return nil
        }
        guard path.hasPrefix("/") else {
            throw AppServerError.invalidRequest("Invalid request: AbsolutePathBuf deserialized without a base path")
        }
        return path
    }

    private static func rustRequiredAbsolutePathParam(_ value: Any?, field: String) throws -> String {
        let path = try rustRequiredStringParam(value, field: field)
        guard path.hasPrefix("/") else {
            throw AppServerError.invalidRequest("Invalid request: AbsolutePathBuf deserialized without a base path")
        }
        return path
    }

    private static func windowsSandboxSetupModeParam(_ value: Any?) throws -> String {
        guard let mode = stringParam(value), !mode.isEmpty else {
            throw AppServerError.invalidRequest("missing mode")
        }
        switch mode {
        case "elevated", "unelevated":
            return mode
        default:
            throw AppServerError.invalidRequest("unknown windows sandbox setup mode: \(mode)")
        }
    }

    private static func isValidRemotePluginID(_ pluginID: String) -> Bool {
        !pluginID.isEmpty && pluginID.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_" || character == "~")
        }
    }

    private static func remotePluginPathSegment(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func isLikelyLocalPluginID(_ pluginID: String) -> Bool {
        let parts = pluginID.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && !parts[1].isEmpty
    }

    private enum MarketplaceSourceKind {
        case local
        case git
    }

    private struct ConfiguredGitMarketplace: Equatable {
        let name: String
        let source: String
        let refName: String?
        let sparsePaths: [String]
        let lastRevision: String?
    }

    private struct ParsedMarketplaceSource {
        let kind: MarketplaceSourceKind
        let localPath: URL?
        let gitURL: String?
        let refName: String?
    }

    private static func configuredGitMarketplaceNames(in stack: ConfigLayerStack) -> [String] {
        configuredGitMarketplaces(in: stack).map(\.name)
    }

    private static func configuredGitMarketplaces(in stack: ConfigLayerStack) -> [ConfiguredGitMarketplace] {
        guard let userLayer = stack.getUserLayer(),
              let userConfig = configTable(userLayer.config),
              let marketplacesValue = userConfig["marketplaces"],
              let marketplaces = configTable(marketplacesValue)
        else {
            return []
        }

        return marketplaces.compactMap { (name: String, value: ConfigValue) -> ConfiguredGitMarketplace? in
            guard let entry = configTable(value),
                  stringConfig(entry, "source_type") == "git",
                  let source = stringConfig(entry, "source")
            else {
                return nil
            }
            return ConfiguredGitMarketplace(
                name: name,
                source: source,
                refName: stringConfig(entry, "ref"),
                sparsePaths: stringArrayConfig(entry, "sparse_paths"),
                lastRevision: stringConfig(entry, "last_revision")
            )
        }.sorted { $0.name < $1.name }
    }

    private static func validatePluginSegment(_ segment: String, kind: String) throws {
        guard !segment.isEmpty else {
            throw AppServerError.invalidRequest("invalid \(kind): must not be empty")
        }
        guard segment.allSatisfy({ character in
            character.isASCII && (character.isLetter || character.isNumber || character == "_" || character == "-")
        }) else {
            throw AppServerError.invalidRequest("invalid \(kind): only ASCII letters, digits, `_`, and `-` are allowed")
        }
    }

    private static func removeMarketplaceConfig(named marketplaceName: String, from config: inout ConfigValue) throws -> Bool {
        guard case var .table(root) = config,
              let marketplacesValue = root["marketplaces"],
              case var .table(marketplaces) = marketplacesValue
        else {
            return false
        }

        if marketplaces.removeValue(forKey: marketplaceName) != nil {
            if marketplaces.isEmpty {
                root.removeValue(forKey: "marketplaces")
            } else {
                root["marketplaces"] = .table(marketplaces)
            }
            config = .table(root)
            return true
        }

        if let configuredName = marketplaces.keys.first(where: { $0.lowercased() == marketplaceName.lowercased() }) {
            throw AppServerError.invalidRequest(
                "marketplace `\(marketplaceName)` does not match configured marketplace `\(configuredName)` exactly"
            )
        }
        return false
    }

    private static func removeMarketplaceInstalledRoot(_ root: URL) throws -> String? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root.path) else {
            return nil
        }

        do {
            try fileManager.removeItem(at: root)
        } catch {
            throw AppServerError.internalError(
                "failed to remove installed marketplace root \(root.path): \(error)"
            )
        }
        return root.path
    }

    private static func parseMarketplaceSource(_ source: String, explicitRef: String?) throws -> ParsedMarketplaceSource {
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            throw AppServerError.invalidRequest("marketplace source must not be empty")
        }
        let split = splitMarketplaceSourceRef(source)
        let baseSource = split.source
        let refName = explicitRef ?? split.refName
        if looksLikeLocalMarketplacePath(baseSource) {
            if refName != nil {
                throw AppServerError.invalidRequest("--ref is only supported for git marketplace sources")
            }
            let path = try resolveLocalMarketplaceSourcePath(baseSource)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path.path, isDirectory: &isDirectory) else {
                throw AppServerError.invalidRequest("failed to resolve local marketplace source path: No such file or directory (os error 2)")
            }
            guard isDirectory.boolValue else {
                throw AppServerError.invalidRequest("local marketplace source must be a directory, not a file")
            }
            return ParsedMarketplaceSource(kind: .local, localPath: path, gitURL: nil, refName: nil)
        }

        if isGitMarketplaceSource(baseSource) {
            return ParsedMarketplaceSource(
                kind: .git,
                localPath: nil,
                gitURL: normalizeGitMarketplaceURL(baseSource),
                refName: refName
            )
        }

        if looksLikeGitHubMarketplaceShorthand(baseSource) {
            return ParsedMarketplaceSource(
                kind: .git,
                localPath: nil,
                gitURL: "https://github.com/\(baseSource).git",
                refName: refName
            )
        }

        throw AppServerError.invalidRequest(
            "invalid marketplace source format; expected owner/repo, a git URL, or a local marketplace path"
        )
    }

    private static func splitMarketplaceSourceRef(_ source: String) -> (source: String, refName: String?) {
        if let range = source.range(of: "#", options: .backwards) {
            let base = String(source[..<range.lowerBound])
            let ref = String(source[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (base, ref.isEmpty ? nil : ref)
        }
        if !source.contains("://"),
           !isSSHGitMarketplaceSource(source),
           let range = source.range(of: "@", options: .backwards) {
            let base = String(source[..<range.lowerBound])
            let ref = String(source[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (base, ref.isEmpty ? nil : ref)
        }
        return (source, nil)
    }

    private static func looksLikeLocalMarketplacePath(_ source: String) -> Bool {
        source.hasPrefix("/")
            || looksLikeWindowsAbsoluteMarketplacePath(source)
            || source.hasPrefix("./")
            || source.hasPrefix(".\\")
            || source.hasPrefix("../")
            || source.hasPrefix("..\\")
            || source.hasPrefix("~/")
            || source == "."
            || source == ".."
    }

    private static func looksLikeWindowsAbsoluteMarketplacePath(_ source: String) -> Bool {
        if source.hasPrefix("\\\\") {
            return true
        }
        let scalars = Array(source.unicodeScalars)
        let first = scalars.first?.value ?? 0
        return scalars.count >= 3
            && ((65...90).contains(Int(first)) || (97...122).contains(Int(first)))
            && scalars[1].value == 58
            && (scalars[2].value == 92 || scalars[2].value == 47)
    }

    private static func resolveLocalMarketplaceSourcePath(_ source: String) throws -> URL {
        let expanded: String
        if source.hasPrefix("~/") {
            expanded = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(String(source.dropFirst(2)))
                .path
        } else {
            expanded = source
        }
        let url = expanded.hasPrefix("/")
            ? URL(fileURLWithPath: expanded, isDirectory: true)
            : URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                .appendingPathComponent(expanded, isDirectory: true)
        return url.resolvingSymlinksInPath().standardizedFileURL
    }

    private static func isGitMarketplaceSource(_ source: String) -> Bool {
        source.hasPrefix("http://") || source.hasPrefix("https://") || isSSHGitMarketplaceSource(source)
    }

    private static func normalizeGitMarketplaceURL(_ source: String) -> String {
        var trimmed = source
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        if trimmed.hasPrefix("https://github.com/") && !trimmed.hasSuffix(".git") {
            return trimmed + ".git"
        }
        return trimmed
    }

    private static func isSSHGitMarketplaceSource(_ source: String) -> Bool {
        source.hasPrefix("ssh://") || (source.hasPrefix("git@") && source.contains(":"))
    }

    private static func looksLikeGitHubMarketplaceShorthand(_ source: String) -> Bool {
        let parts = source.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty }) else {
            return false
        }
        return parts.allSatisfy { part in
            part.allSatisfy { character in
                character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_" || character == ".")
            }
        }
    }

    private static func validateLocalMarketplaceSourceRoot(_ root: URL) throws -> String {
        let manifestPath = localMarketplaceManifestPath(in: root)
        guard let manifestPath else {
            throw AppServerError.invalidRequest(
                "invalid marketplace file `\(root.path)`: marketplace root does not contain a supported manifest"
            )
        }
        let data: Data
        do {
            data = try Data(contentsOf: manifestPath)
        } catch {
            throw AppServerError.internalError("failed to read marketplace file: \(error)")
        }
        let object: [String: Any]
        do {
            object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        } catch {
            throw AppServerError.invalidRequest(
                "invalid marketplace file `\(manifestPath.path)`: \(error)"
            )
        }
        guard let name = object["name"] as? String else {
            throw AppServerError.invalidRequest(
                "invalid marketplace file `\(manifestPath.path)`: missing field `name`"
            )
        }
        guard object["plugins"] is [Any] else {
            throw AppServerError.invalidRequest(
                "invalid marketplace file `\(manifestPath.path)`: missing field `plugins`"
            )
        }
        try validatePluginSegment(name, kind: "marketplace name")
        return name
    }

    private static func localMarketplaceManifestPath(in root: URL) -> URL? {
        let candidates = [
            root.appendingPathComponent(".agents/plugins/marketplace.json", isDirectory: false),
            root.appendingPathComponent(".claude-plugin/marketplace.json", isDirectory: false)
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func configuredMarketplaceRootForLocalSource(_ source: String, in config: ConfigValue) -> String? {
        guard let marketplaces = marketplaceConfigTable(in: config) else {
            return nil
        }
        for (name, value) in marketplaces {
            guard let entry = configTable(value),
                  stringConfig(entry, "source_type") == "local",
                  stringConfig(entry, "source") == source
            else {
                continue
            }
            return configuredMarketplaceRoot(name: name, entry: entry)
        }
        return nil
    }

    private static func configuredMarketplaceRootForGitSource(
        source: String,
        refName: String?,
        sparsePaths: [String],
        codexHome: URL,
        in config: ConfigValue
    ) -> String? {
        guard let marketplaces = marketplaceConfigTable(in: config) else {
            return nil
        }
        for (name, value) in marketplaces {
            guard let entry = configTable(value),
                  stringConfig(entry, "source_type") == "git",
                  stringConfig(entry, "source") == source,
                  stringConfig(entry, "ref") == refName,
                  stringArrayConfig(entry, "sparse_paths") == sparsePaths
            else {
                continue
            }
            return configuredMarketplaceRoot(name: name, entry: entry, codexHome: codexHome)
        }
        return nil
    }

    private static func configuredMarketplaceRoot(named marketplaceName: String, in config: ConfigValue) -> String? {
        guard let marketplaces = marketplaceConfigTable(in: config),
              let value = marketplaces[marketplaceName],
              let entry = configTable(value)
        else {
            return nil
        }
        return configuredMarketplaceRoot(name: marketplaceName, entry: entry)
    }

    private static func configuredMarketplaceRoot(
        named marketplaceName: String,
        codexHome: URL,
        in config: ConfigValue
    ) -> String? {
        guard let marketplaces = marketplaceConfigTable(in: config),
              let value = marketplaces[marketplaceName],
              let entry = configTable(value)
        else {
            return nil
        }
        return configuredMarketplaceRoot(name: marketplaceName, entry: entry, codexHome: codexHome)
    }

    private static func configuredMarketplaceRootIsValid(
        named marketplaceName: String,
        codexHome: URL,
        in config: ConfigValue
    ) -> Bool {
        guard let root = configuredMarketplaceRoot(named: marketplaceName, codexHome: codexHome, in: config) else {
            return false
        }
        return (try? validateLocalMarketplaceSourceRoot(URL(fileURLWithPath: root, isDirectory: true))) != nil
    }

    private static func marketplaceConfigTable(in config: ConfigValue) -> [String: ConfigValue]? {
        guard let root = configTable(config),
              let marketplacesValue = root["marketplaces"],
              let marketplaces = configTable(marketplacesValue)
        else {
            return nil
        }
        return marketplaces
    }

    private static func configuredMarketplaceRoot(name: String, entry: [String: ConfigValue]) -> String? {
        switch stringConfig(entry, "source_type") {
        case "local":
            return stringConfig(entry, "source")
        case "git":
            return stringConfig(entry, "installed_root")
                ?? FileManager.default.currentDirectoryPath + "/.tmp/marketplaces/" + name
        default:
            return nil
        }
    }

    private static func configuredMarketplaceRoot(
        name: String,
        entry: [String: ConfigValue],
        codexHome: URL
    ) -> String? {
        switch stringConfig(entry, "source_type") {
        case "local":
            return stringConfig(entry, "source")
        case "git":
            return stringConfig(entry, "installed_root")
                ?? codexHome
                    .appendingPathComponent(".tmp", isDirectory: true)
                    .appendingPathComponent("marketplaces", isDirectory: true)
                    .appendingPathComponent(name, isDirectory: true)
                    .path
        default:
            return nil
        }
    }

    private static func recordMarketplaceConfig(
        name: String,
        sourceType: String,
        source: String,
        refName: String?,
        sparsePaths: [String],
        lastRevision: String? = nil,
        in config: inout ConfigValue
    ) throws {
        var root = configTable(config) ?? [:]
        var marketplaces = root["marketplaces"].flatMap(configTable) ?? [:]
        var entry: [String: ConfigValue] = [
            "last_updated": .string(marketplaceTimestamp()),
            "source_type": .string(sourceType),
            "source": .string(source)
        ]
        if let refName {
            entry["ref"] = .string(refName)
        }
        if !sparsePaths.isEmpty {
            entry["sparse_paths"] = .array(sparsePaths.map(ConfigValue.string))
        }
        if let lastRevision {
            entry["last_revision"] = .string(lastRevision)
        }
        marketplaces[name] = .table(entry)
        root["marketplaces"] = .table(marketplaces)
        config = .table(root)
    }

    private static func upgradeConfiguredGitMarketplace(
        _ marketplace: ConfiguredGitMarketplace,
        codexHome: URL,
        installRoot: URL,
        environment: [String: String]
    ) throws -> String? {
        try validatePluginSegment(marketplace.name, kind: "marketplace name")
        let remoteRevision = try gitMarketplaceRemoteRevision(
            source: marketplace.source,
            refName: marketplace.refName,
            environment: environment
        )
        let destination = installRoot.appendingPathComponent(marketplace.name, isDirectory: true)
        if FileManager.default.fileExists(
            atPath: destination.appendingPathComponent(".agents/plugins/marketplace.json", isDirectory: false).path
        ),
           marketplace.lastRevision == remoteRevision,
           installedMarketplaceMetadataMatches(
               root: destination,
               marketplace: marketplace,
               revision: remoteRevision
           ) {
            return nil
        }

        let stagingParent = installRoot.appendingPathComponent(".staging", isDirectory: true)
        let stagingRoot = stagingParent.appendingPathComponent(
            "marketplace-upgrade-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try FileManager.default.createDirectory(at: stagingParent, withIntermediateDirectories: true)
            let activatedRevision = try cloneGitMarketplace(
                source: marketplace.source,
                refName: marketplace.refName,
                sparsePaths: marketplace.sparsePaths,
                destination: stagingRoot,
                environment: environment
            )
            let upgradedName = try validateLocalMarketplaceSourceRoot(stagingRoot)
            guard upgradedName == marketplace.name else {
                throw AppServerError.internalError(
                    "upgraded marketplace name `\(upgradedName)` does not match configured marketplace `\(marketplace.name)`"
                )
            }
            try writeInstalledMarketplaceMetadata(
                root: stagingRoot,
                marketplace: marketplace,
                revision: activatedRevision
            )
            try activateUpgradedMarketplaceRoot(
                destination: destination,
                stagedRoot: stagingRoot
            ) {
                try ensureConfiguredGitMarketplaceUnchanged(
                    codexHome: codexHome,
                    expected: marketplace
                )
                let configFile = codexHome.appendingPathComponent("config.toml", isDirectory: false)
                var config = try CodexConfigLayerLoader.readConfig(from: configFile) ?? .table([:])
                try recordMarketplaceConfig(
                    name: marketplace.name,
                    sourceType: "git",
                    source: marketplace.source,
                    refName: marketplace.refName,
                    sparsePaths: marketplace.sparsePaths,
                    lastRevision: activatedRevision,
                    in: &config
                )
                try renderConfigToml(config).write(to: configFile, atomically: true, encoding: .utf8)
            }
            return destination.path
        } catch let error as AppServerError {
            if FileManager.default.fileExists(atPath: stagingRoot.path) {
                try? FileManager.default.removeItem(at: stagingRoot)
            }
            throw error
        } catch {
            if FileManager.default.fileExists(atPath: stagingRoot.path) {
                try? FileManager.default.removeItem(at: stagingRoot)
            }
            throw AppServerError.internalError("\(error)")
        }
    }

    private static func gitMarketplaceRemoteRevision(
        source: String,
        refName: String?,
        environment: [String: String]
    ) throws -> String {
        if let refName, isFullGitSHA(refName) {
            return refName
        }
        let output = try runMarketplaceGit(
            ["ls-remote", source, refName ?? "HEAD"],
            cwd: nil,
            environment: environment
        )
        guard let firstLine = output.split(whereSeparator: \.isNewline).first else {
            throw AppServerError.internalError("git ls-remote returned empty output for marketplace source")
        }
        guard let tabIndex = firstLine.firstIndex(of: "\t") else {
            throw AppServerError.internalError(
                "unexpected git ls-remote output for marketplace source: \(firstLine)"
            )
        }
        let revision = firstLine[..<tabIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !revision.isEmpty else {
            throw AppServerError.internalError("git ls-remote returned empty revision for marketplace source")
        }
        return revision
    }

    private static func activateUpgradedMarketplaceRoot(
        destination: URL,
        stagedRoot: URL,
        afterActivate: () throws -> Void
    ) throws {
        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            let backupRoot = parent.appendingPathComponent("marketplace-backup-\(UUID().uuidString)", isDirectory: true)
                .appendingPathComponent("root", isDirectory: true)
            try FileManager.default.createDirectory(at: backupRoot.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: destination, to: backupRoot)
            do {
                try FileManager.default.moveItem(at: stagedRoot, to: destination)
            } catch {
                try? FileManager.default.moveItem(at: backupRoot, to: destination)
                throw AppServerError.internalError(
                    "failed to activate upgraded marketplace at \(destination.path): \(error)"
                )
            }
            do {
                try afterActivate()
                try? FileManager.default.removeItem(at: backupRoot.deletingLastPathComponent())
            } catch {
                try? FileManager.default.removeItem(at: destination)
                if (try? FileManager.default.moveItem(at: backupRoot, to: destination)) != nil {
                    throw error
                }
                throw AppServerError.internalError(
                    "\(error); failed to restore previous marketplace root at \(destination.path)"
                )
            }
            return
        }

        try FileManager.default.moveItem(at: stagedRoot, to: destination)
        do {
            try afterActivate()
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private static func ensureConfiguredGitMarketplaceUnchanged(
        codexHome: URL,
        expected: ConfiguredGitMarketplace
    ) throws {
        let configFile = codexHome.appendingPathComponent("config.toml", isDirectory: false)
        let config = try CodexConfigLayerLoader.readConfig(from: configFile) ?? .table([:])
        guard let marketplaces = marketplaceConfigTable(in: config),
              let value = marketplaces[expected.name],
              let entry = configTable(value),
              stringConfig(entry, "source_type") == "git",
              let source = stringConfig(entry, "source")
        else {
            throw AppServerError.internalError(
                "configured marketplace `\(expected.name)` was removed or is no longer a Git marketplace"
            )
        }
        let current = ConfiguredGitMarketplace(
            name: expected.name,
            source: source,
            refName: stringConfig(entry, "ref"),
            sparsePaths: stringArrayConfig(entry, "sparse_paths"),
            lastRevision: stringConfig(entry, "last_revision")
        )
        guard current == expected else {
            throw AppServerError.internalError(
                "configured marketplace `\(expected.name)` changed while auto-upgrade was in flight"
            )
        }
    }

    private static func installedMarketplaceMetadataMatches(
        root: URL,
        marketplace: ConfiguredGitMarketplace,
        revision: String
    ) -> Bool {
        let metadataPath = installedMarketplaceMetadataPath(root: root)
        guard let data = try? Data(contentsOf: metadataPath),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return false
        }
        return object["source_type"] as? String == "git"
            && object["source"] as? String == marketplace.source
            && object["ref_name"] as? String == marketplace.refName
            && (object["sparse_paths"] as? [String] ?? []) == marketplace.sparsePaths
            && object["revision"] as? String == revision
    }

    private static func writeInstalledMarketplaceMetadata(
        root: URL,
        marketplace: ConfiguredGitMarketplace,
        revision: String
    ) throws {
        var object: [String: Any] = [
            "source_type": "git",
            "source": marketplace.source,
            "sparse_paths": marketplace.sparsePaths,
            "revision": revision
        ]
        if let refName = marketplace.refName {
            object["ref_name"] = refName
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: installedMarketplaceMetadataPath(root: root))
    }

    private static func installedMarketplaceMetadataPath(root: URL) -> URL {
        root.appendingPathComponent(".codex-marketplace-install.json", isDirectory: false)
    }

    private static func isFullGitSHA(_ value: String) -> Bool {
        value.count == 40 && value.allSatisfy(\.isHexDigit)
    }

    private static func cloneGitMarketplace(
        source: String,
        refName: String?,
        sparsePaths: [String],
        destination: URL,
        environment: [String: String]
    ) throws -> String {
        if sparsePaths.isEmpty {
            try runMarketplaceGit(
                ["clone", source, destination.path],
                cwd: nil,
                environment: environment
            )
            if let refName {
                try runMarketplaceGit(["checkout", refName], cwd: destination, environment: environment)
            }
            return try gitMarketplaceWorktreeRevision(destination: destination, environment: environment)
        }

        try runMarketplaceGit(
            ["clone", "--filter=blob:none", "--no-checkout", source, destination.path],
            cwd: nil,
            environment: environment
        )
        try runMarketplaceGit(
            ["sparse-checkout", "set"] + sparsePaths,
            cwd: destination,
            environment: environment
        )
        try runMarketplaceGit(["checkout", refName ?? "HEAD"], cwd: destination, environment: environment)
        return try gitMarketplaceWorktreeRevision(destination: destination, environment: environment)
    }

    private static func gitMarketplaceWorktreeRevision(
        destination: URL,
        environment: [String: String]
    ) throws -> String {
        let revision = try runMarketplaceGit(
            ["rev-parse", "HEAD"],
            cwd: destination,
            environment: environment
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !revision.isEmpty else {
            throw AppServerError.internalError("git rev-parse returned empty revision for marketplace source")
        }
        return revision
    }

    @discardableResult
    private static func runMarketplaceGit(
        _ args: [String],
        cwd: URL?,
        environment: [String: String]
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        if let cwd {
            process.currentDirectoryURL = cwd
        }
        var processEnvironment = environment
        processEnvironment["GIT_TERMINAL_PROMPT"] = "0"
        processEnvironment["GIT_OPTIONAL_LOCKS"] = "0"
        process.environment = processEnvironment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        do {
            try process.run()
        } catch {
            throw AppServerError.internalError("failed to run git \(args.joined(separator: " ")): \(error)")
        }
        process.waitUntilExit()
        let stdout = String(decoding: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw AppServerError.internalError(
                "git \(args.joined(separator: " ")) failed with status \(process.terminationStatus)\nstdout:\n\(stdout)\nstderr:\n\(stderr)"
            )
        }
        return stdout
    }

    private static func safeMarketplaceDirectoryName(_ marketplaceName: String) throws -> String {
        let safe = String(marketplaceName.map { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_" || character == ".")
                ? character
                : "-"
        }).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !safe.isEmpty, safe != ".." else {
            throw AppServerError.invalidRequest(
                "marketplace name '\(marketplaceName)' cannot be used as an install directory"
            )
        }
        return safe
    }

    private static func marketplaceTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date())
    }

    private struct FilesystemMetadata {
        let isDirectory: Bool
        let isFile: Bool
        let isSymlink: Bool
        let createdAtMs: Int64
        let modifiedAtMs: Int64
    }

    private static func filesystemMetadata(path: String) throws -> FilesystemMetadata {
        let fileManager = FileManager.default
        let linkAttributes = try fileManager.attributesOfItem(atPath: path)
        let isSymlink = (linkAttributes[.type] as? FileAttributeType) == .typeSymbolicLink
        let targetAttributes: [FileAttributeKey: Any]
        if isSymlink {
            let destination = try fileManager.destinationOfSymbolicLink(atPath: path)
            let resolvedPath: String
            if destination.hasPrefix("/") {
                resolvedPath = destination
            } else {
                resolvedPath = URL(fileURLWithPath: path).deletingLastPathComponent()
                    .appendingPathComponent(destination)
                    .standardized
                    .path
            }
            targetAttributes = try fileManager.attributesOfItem(atPath: resolvedPath)
        } else {
            targetAttributes = linkAttributes
        }
        let type = targetAttributes[.type] as? FileAttributeType
        let createdAt = targetAttributes[.creationDate] as? Date
        let modifiedAt = targetAttributes[.modificationDate] as? Date
        return FilesystemMetadata(
            isDirectory: type == .typeDirectory,
            isFile: type == .typeRegular,
            isSymlink: isSymlink,
            createdAtMs: millisecondsSinceEpoch(createdAt),
            modifiedAtMs: millisecondsSinceEpoch(modifiedAt)
        )
    }

    fileprivate static func millisecondsSinceEpoch(_ date: Date?) -> Int64 {
        guard let date else {
            return 0
        }
        return Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    private static func isSymlink(path: String) -> Bool {
        guard let type = try? FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType else {
            return false
        }
        return type == .typeSymbolicLink
    }

    private static func isDirectory(path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func copyFilesystemItem(
        sourcePath: String,
        destinationPath: String,
        recursive: Bool,
        topLevel: Bool
    ) throws {
        let fileManager = FileManager.default
        let sourceAttributes = try fileManager.attributesOfItem(atPath: sourcePath)
        let sourceType = sourceAttributes[.type] as? FileAttributeType

        if sourceType == .typeSymbolicLink {
            let destination = try fileManager.destinationOfSymbolicLink(atPath: sourcePath)
            try fileManager.createSymbolicLink(atPath: destinationPath, withDestinationPath: destination)
            return
        }

        if sourceType == .typeRegular {
            try fileManager.copyItem(atPath: sourcePath, toPath: destinationPath)
            return
        }

        guard sourceType == .typeDirectory else {
            if topLevel {
                throw AppServerError.invalidRequest("fs/copy only supports regular files, directories, and symlinks")
            }
            return
        }

        guard recursive else {
            throw AppServerError.invalidRequest("fs/copy requires recursive: true when sourcePath is a directory")
        }
        if topLevel, isSameOrDescendant(path: destinationPath, of: sourcePath) {
            throw AppServerError.invalidRequest("fs/copy cannot copy a directory to itself or one of its descendants")
        }

        try fileManager.createDirectory(
            atPath: destinationPath,
            withIntermediateDirectories: false
        )
        let childNames = try fileManager.contentsOfDirectory(atPath: sourcePath)
        for childName in childNames {
            try copyFilesystemItem(
                sourcePath: URL(fileURLWithPath: sourcePath, isDirectory: true)
                    .appendingPathComponent(childName)
                    .path,
                destinationPath: URL(fileURLWithPath: destinationPath, isDirectory: true)
                    .appendingPathComponent(childName)
                    .path,
                recursive: true,
                topLevel: false
            )
        }
    }

    private static func isSameOrDescendant(path: String, of ancestor: String) -> Bool {
        let standardizedPath = URL(fileURLWithPath: path).standardized.path
        var standardizedAncestor = URL(fileURLWithPath: ancestor).standardized.path
        if standardizedPath == standardizedAncestor {
            return true
        }
        if !standardizedAncestor.hasSuffix("/") {
            standardizedAncestor += "/"
        }
        return standardizedPath.hasPrefix(standardizedAncestor)
    }

    private static func mapFilesystemError(_ error: Error) -> AppServerError {
        if let error = error as? AppServerError {
            return error
        }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain
            && (
                nsError.code == CocoaError.fileReadInvalidFileName.rawValue
                    || nsError.code == CocoaError.fileWriteInvalidFileName.rawValue
            ) {
            return .invalidRequest(error.localizedDescription)
        }
        return .internalError(error.localizedDescription)
    }

    private static func approvalPolicyParam(_ value: Any?) -> AskForApproval? {
        stringParam(value).flatMap(AskForApproval.init(rawValue:))
    }

    private static func approvalsReviewerParam(_ value: Any?) throws -> ApprovalsReviewer? {
        guard let value, !(value is NSNull) else {
            return nil
        }
        guard let rawValue = stringParam(value) else {
            throw AppServerError.invalidRequest("invalid value for field `approvalsReviewer`")
        }
        switch rawValue {
        case "user":
            return .user
        case "guardian_subagent", "auto_review":
            return .autoReview
        default:
            throw AppServerError.invalidRequest(
                "unknown variant `\(rawValue)`, expected one of `user`, `auto_review`, `guardian_subagent`"
            )
        }
    }

    private static func threadSourceParam(_ value: Any?) -> ThreadSource? {
        stringParam(value).flatMap(ThreadSource.init(rawValue:))
    }

    private static func sandboxModeParam(_ value: Any?) -> SandboxMode? {
        stringParam(value).flatMap(SandboxMode.init(rawValue:))
    }

    private static func v2UserInputs(_ value: Any?) -> (text: String, images: [String]?) {
        guard let items = value as? [[String: Any]] else {
            return ("", nil)
        }
        var texts: [String] = []
        var images: [String] = []
        for item in items {
            switch stringParam(item["type"]) {
            case "text":
                if let text = stringParam(item["text"]), !text.isEmpty {
                    texts.append(text)
                }
            case "image":
                if let url = stringParam(item["url"]), !url.isEmpty {
                    images.append(url)
                }
            default:
                continue
            }
        }
        return (
            texts.joined(),
            images.isEmpty ? nil : images
        )
    }

    private static func validateV2UserInputLimit(_ input: (text: String, images: [String]?)) throws {
        let actualScalars = input.text.unicodeScalars.count
        guard actualScalars <= maxUserInputTextScalars else {
            throw AppServerError.invalidParamsWithInputTooLargeData(
                "Input exceeds the maximum length of \(maxUserInputTextScalars) characters.",
                maxChars: maxUserInputTextScalars,
                actualChars: actualScalars
            )
        }
    }

    private static func v1InputItems(_ value: Any?) -> (text: String, images: [String]?) {
        guard let items = value as? [[String: Any]] else {
            return ("", nil)
        }
        var texts: [String] = []
        var images: [String] = []
        for item in items {
            let data = item["data"] as? [String: Any] ?? item
            switch stringParam(item["type"]) {
            case "text":
                if let text = stringParam(data["text"]), !text.isEmpty {
                    texts.append(text)
                }
            case "image":
                if let url = stringParam(data["imageUrl"]) ?? stringParam(data["image_url"]), !url.isEmpty {
                    images.append(url)
                }
            case "localImage":
                if let path = stringParam(data["path"]), !path.isEmpty {
                    images.append(path)
                }
            default:
                continue
            }
        }
        return (
            texts.joined(),
            images.isEmpty ? nil : images
        )
    }

    private static func reviewRequestFromTarget(_ value: Any?) throws -> (request: ReviewRequest, displayText: String) {
        guard let target = value as? [String: Any],
              let type = stringParam(target["type"])
        else {
            throw AppServerError.invalidRequest("missing review target")
        }

        let reviewTarget: ReviewTarget
        switch type {
        case "uncommittedChanges":
            reviewTarget = .uncommittedChanges
        case "baseBranch":
            let branch = stringParam(target["branch"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !branch.isEmpty else {
                throw AppServerError.invalidRequest("branch must not be empty")
            }
            reviewTarget = .baseBranch(branch: branch)
        case "commit":
            let sha = stringParam(target["sha"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !sha.isEmpty else {
                throw AppServerError.invalidRequest("sha must not be empty")
            }
            let trimmedTitle = stringParam(target["title"])?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let title = trimmedTitle?.isEmpty == true ? nil : trimmedTitle
            reviewTarget = .commit(sha: sha, title: title)
        case "custom":
            let instructions = stringParam(target["instructions"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !instructions.isEmpty else {
                throw AppServerError.invalidRequest("instructions must not be empty")
            }
            reviewTarget = .custom(instructions: instructions)
        default:
            throw AppServerError.invalidRequest("unsupported review target: \(type)")
        }

        let hint = ReviewPrompts.userFacingHint(target: reviewTarget)
        return (ReviewRequest(target: reviewTarget, userFacingHint: hint), hint)
    }

    private static func stringArrayParam(_ value: Any?) -> [String]? {
        value as? [String]
    }

    private static func rustStringArrayParam(_ value: Any?) throws -> [String]? {
        guard let value, !(value is NSNull) else {
            return nil
        }
        guard let values = value as? [Any] else {
            throw AppServerError.invalidRequest("Invalid request: \(rustInvalidTypeDescription(value)), expected a sequence")
        }
        return try values.map { item in
            guard let string = item as? String else {
                throw AppServerError.invalidRequest("Invalid request: \(rustInvalidTypeDescription(item)), expected a string")
            }
            return string
        }
    }

    private static func rustInvalidTypeDescription(_ value: Any) -> String {
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            return "invalid type: boolean `\(number.boolValue ? "true" : "false")`"
        }
        if let string = value as? String {
            return "invalid type: string \"\(string)\""
        }
        if value is NSNull {
            return "invalid type: null"
        }
        if value is [Any] {
            return "invalid type: sequence"
        }
        if value is [String: Any] {
            return "invalid type: map"
        }
        if let int = value as? Int {
            return "invalid type: integer `\(int)`"
        }
        if let number = value as? NSNumber {
            let int = number.int64Value
            if Double(int) == number.doubleValue {
                return "invalid type: integer `\(int)`"
            }
            return "invalid type: floating point `\(number)`"
        }
        return "invalid type"
    }

    private static func modelProviderFilter(_ value: Any?, defaultProvider: String) -> [String]? {
        guard let providers = stringArrayParam(value) else {
            return [defaultProvider]
        }
        return providers.isEmpty ? nil : providers
    }

    private static func threadListCwdFilters(_ value: Any?) throws -> [String]? {
        let rawFilters: [String]
        if let cwd = stringParam(value) {
            rawFilters = [cwd]
        } else if let cwds = stringArrayParam(value) {
            rawFilters = cwds
        } else {
            return nil
        }

        return rawFilters.map { cwd in
            URL(fileURLWithPath: cwd, isDirectory: true).standardizedFileURL.path
        }
    }

    private static func threadListCursor(_ value: Any?) throws -> ConversationCursor? {
        guard let cursor = stringParam(value) else {
            return nil
        }
        guard !cursor.contains("|"), let parsed = RolloutListing.parseCursor(cursor) else {
            throw AppServerError.invalidRequest("invalid cursor: \(cursor)")
        }
        return parsed
    }

    private static func threadListStateDbOnlyResult(
        configuration: CodexAppServerConfiguration,
        pageSize: Int,
        cursor: ConversationCursor?,
        allowedSources: [SessionSource],
        sourceMatcher: SessionSourceMatcher?,
        modelProviders: [String]?,
        archivedOnly: Bool,
        cwdFilters: [String]?,
        searchTerm: String?,
        sortKey: ConversationSortKey,
        sortDirection: ConversationSortDirection
    ) throws -> [String: Any] {
        guard let stateStore = configuration.stateStore else {
            return [
                "data": [],
                "nextCursor": NSNull(),
                "backwardsCursor": NSNull()
            ]
        }

        let filters = ThreadListFilterOptions(
            archivedOnly: archivedOnly,
            allowedSources: allowedSources.map(\.description),
            modelProviders: modelProviders,
            cwdFilters: cwdFilters?.map { URL(fileURLWithPath: $0, isDirectory: true) },
            anchor: cursor.map { ThreadListAnchor(timestamp: $0.anchorTimestamp) },
            sortKey: threadListStoreSortKey(sortKey),
            sortDirection: threadListStoreSortDirection(sortDirection),
            searchTerm: searchTerm
        )
        let page = try runAsyncBlocking {
            let page = try await stateStore.listThreads(pageSize: pageSize, filters: filters)
            var validItems: [ThreadMetadata] = []
            validItems.reserveCapacity(page.items.count)
            for item in page.items {
                if FileManager.default.fileExists(atPath: item.rolloutPath) {
                    validItems.append(item)
                } else {
                    _ = try? await stateStore.deleteThread(threadID: item.id)
                }
            }
            return ThreadsPage(
                items: validItems,
                nextAnchor: page.nextAnchor,
                numScannedRows: page.numScannedRows
            )
        }
        let visibleItems = page.items.filter { item in
            sourceMatcher?.matches(threadListSessionSource(from: item.source)) ?? true
        }
        return [
            "data": try visibleItems.map { try threadObject(for: $0, defaultProvider: configuration.defaultModelProvider) },
            "nextCursor": (page.nextAnchor.map { threadListCursorToken(for: $0.timestamp) } as Any?) ?? NSNull(),
            "backwardsCursor": visibleItems.first.map {
                threadListBackwardsCursorToken(
                    for: $0.timestamp(for: filters.sortKey),
                    sortDirection: sortDirection
                )
            } as Any? ?? NSNull()
        ]
    }

    private static func threadListStoreSortKey(_ sortKey: ConversationSortKey) -> ThreadListSortKey {
        switch sortKey {
        case .createdAt:
            return .createdAt
        case .updatedAt:
            return .updatedAt
        }
    }

    private static func threadListStoreSortDirection(_ sortDirection: ConversationSortDirection) -> ThreadListSortDirection {
        switch sortDirection {
        case .ascending:
            return .ascending
        case .descending:
            return .descending
        }
    }

    private static func threadListBackwardsCursorToken(
        for timestamp: Date,
        sortDirection: ConversationSortDirection
    ) -> String {
        let interval: TimeInterval = sortDirection == .ascending ? 0.001 : -0.001
        return threadListCursorToken(for: timestamp.addingTimeInterval(interval))
    }

    private static func threadListCursorToken(for timestamp: Date) -> String {
        let wholeSeconds = timestamp.timeIntervalSince1970.rounded(.towardZero)
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        if abs(timestamp.timeIntervalSince1970 - wholeSeconds) < 0.000_001 {
            formatter.formatOptions = [.withInternetDateTime]
        } else {
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        }
        return formatter.string(from: timestamp)
    }

    private static func threadListSortKey(_ value: Any?) throws -> ConversationSortKey {
        guard let value = stringParam(value) else {
            return .createdAt
        }
        switch value {
        case "created_at":
            return .createdAt
        case "updated_at":
            return .updatedAt
        default:
            throw AppServerError.invalidParams("invalid thread/list sortKey `\(value)`")
        }
    }

    private static func threadListSortDirection(_ value: Any?) throws -> ConversationSortDirection {
        guard let value = stringParam(value) else {
            return .descending
        }
        switch value {
        case "asc":
            return .ascending
        case "desc":
            return .descending
        default:
            throw AppServerError.invalidParams("invalid thread/list sortDirection `\(value)`")
        }
    }

    private static func threadListSourceFilter(
        _ value: Any?
    ) throws -> (allowedSources: [SessionSource], matcher: SessionSourceMatcher?) {
        guard let values = stringArrayParam(value), !values.isEmpty else {
            return (interactiveSessionSources, nil)
        }

        let kinds = try values.map { value in
            guard let kind = SessionSourceMatcher.SourceKind(rawValue: value) else {
                throw AppServerError.invalidParams("invalid thread/list sourceKind `\(value)`")
            }
            return kind
        }

        let requiresPostFilter = kinds.contains { kind in
            switch kind {
            case .cli, .vscode:
                return false
            case .exec, .appServer, .subAgent, .subAgentReview, .subAgentCompact,
                 .subAgentThreadSpawn, .subAgentOther, .unknown:
                return true
            }
        }

        if requiresPostFilter {
            return ([], SessionSourceMatcher(kinds: kinds))
        }

        let allowedSources = kinds.compactMap { kind -> SessionSource? in
            switch kind {
            case .cli:
                return .cli
            case .vscode:
                return .vscode
            case .exec, .appServer, .subAgent, .subAgentReview, .subAgentCompact,
                 .subAgentThreadSpawn, .subAgentOther, .unknown:
                return nil
            }
        }
        return (allowedSources, SessionSourceMatcher(kinds: kinds))
    }

    private static func sanitizeHeaderValue(_ value: String) -> String {
        value.map { character in
            character.asciiValue.map { (0x20...0x7E).contains($0) } == true ? character : "_"
        }.map(String.init).joined()
    }

    private static func modelObject(_ preset: ModelPreset) -> [String: Any] {
        [
            "id": preset.id,
            "model": preset.model,
            "upgrade": (preset.upgrade?.id as Any?) ?? NSNull(),
            "upgradeInfo": modelUpgradeInfoObject(preset.upgrade),
            "availabilityNux": modelAvailabilityNuxObject(preset.availabilityNux),
            "displayName": preset.displayName,
            "description": preset.description,
            "hidden": !preset.showInPicker,
            "supportedReasoningEfforts": preset.supportedReasoningEfforts.map { effort in
                [
                    "reasoningEffort": effort.effort.rawValue,
                    "description": effort.description
                ]
            },
            "defaultReasoningEffort": preset.defaultReasoningEffort.rawValue,
            "inputModalities": preset.inputModalities.map(\.rawValue),
            "supportsPersonality": preset.supportsPersonality,
            "additionalSpeedTiers": preset.additionalSpeedTiers,
            "serviceTiers": preset.serviceTiers.map { tier in
                [
                    "id": tier.id,
                    "name": tier.name,
                    "description": tier.description
                ]
            },
            "isDefault": preset.isDefault
        ]
    }

    private static func experimentalFeatureObject(
        spec: FeatureSpec,
        features: FeatureStates
    ) -> [String: Any] {
        [
            "name": spec.key,
            "stage": experimentalFeatureStageObject(spec.stage),
            "displayName": spec.displayName ?? NSNull(),
            "description": spec.description ?? NSNull(),
            "announcement": spec.announcement ?? NSNull(),
            "enabled": features.isEnabled(spec.id),
            "defaultEnabled": spec.defaultEnabled
        ].nullStripped(keepNulls: true)
    }

    private static func hookStateMap(from config: ConfigValue) -> [String: HookState] {
        guard let root = configTable(config),
              let hooks = root["hooks"].flatMap(configTable),
              let state = hooks["state"].flatMap(configTable)
        else {
            return [:]
        }
        var output: [String: HookState] = [:]
        for (key, value) in state {
            guard let entry = configTable(value) else {
                continue
            }
            output[key] = HookState(
                enabled: boolConfig(entry, "enabled"),
                trustedHash: stringConfig(entry, "trusted_hash")
            )
        }
        return output
    }

    private static func hookTrustStatus(currentHash: String, state: HookState?) -> String {
        guard let trustedHash = state?.trustedHash else {
            return "untrusted"
        }
        return trustedHash == currentHash ? "trusted" : "modified"
    }

    private static func configHookObjects(
        config: ConfigValue,
        configFile: URL,
        source: String,
        hookStates: [String: HookState],
        isManaged: Bool = false
    ) -> [[String: Any]] {
        guard let root = configTable(config),
              let hooks = root["hooks"].flatMap(configTable)
        else {
            return []
        }

        let sourcePath = configFile.standardizedFileURL.path
        var displayOrder: Int64 = 0
        var output: [[String: Any]] = []
        for eventName in HookEventName.allCases {
            guard case let .array(groups)? = hooks[eventName.configLabel] else {
                continue
            }
            for (groupIndex, groupValue) in groups.enumerated() {
                guard let group = configTable(groupValue) else {
                    continue
                }
                let matcher = stringConfig(group, "matcher")
                guard case let .array(handlerValues)? = group["hooks"] else {
                    continue
                }
                for (handlerIndex, handlerValue) in handlerValues.enumerated() {
                    guard let handler = configTable(handlerValue),
                          stringConfig(handler, "type") == "command",
                          let command = stringConfig(handler, "command")
                    else {
                        continue
                    }
                    let timeoutSec = configHookTimeoutSec(
                        handler["timeout"] ?? handler["timeoutSec"] ?? handler["timeout_sec"]
                    ) ?? 600
                    let statusMessage = stringConfig(handler, "statusMessage") ?? stringConfig(handler, "status_message")
                    let key = HooksProtocol.hookKey(
                        keySource: sourcePath,
                        eventName: eventName,
                        groupIndex: groupIndex,
                        handlerIndex: handlerIndex
                    )
                    let currentHash = userHookHash(
                        eventName: eventName,
                        matcher: matcher,
                        command: command,
                        timeoutSec: timeoutSec,
                        statusMessage: statusMessage
                    )
                    output.append([
                        "key": key,
                        "eventName": appServerHookEventName(eventName),
                        "handlerType": "command",
                        "matcher": matcher as Any? ?? NSNull(),
                        "command": command,
                        "timeoutSec": Int(timeoutSec),
                        "statusMessage": statusMessage as Any? ?? NSNull(),
                        "sourcePath": sourcePath,
                        "source": source,
                        "pluginId": NSNull(),
                        "displayOrder": displayOrder,
                        "enabled": isManaged ? true : hookStates[key]?.enabled ?? true,
                        "isManaged": isManaged,
                        "currentHash": currentHash,
                        "trustStatus": isManaged ? "managed" : hookTrustStatus(currentHash: currentHash, state: hookStates[key])
                    ])
                    displayOrder += 1
                }
            }
        }
        return output
    }

    private static func hookEventName(configLabel: String) -> HookEventName? {
        HookEventName.allCases.first { $0.configLabel == configLabel }
    }

    private static func configHookTimeoutSec(_ value: ConfigValue?) -> UInt64? {
        switch value {
        case let .integer(integer)? where integer >= 0:
            return UInt64(integer)
        case let .double(double)? where double >= 0 && double.rounded() == double:
            return UInt64(double)
        case let .string(string)?:
            return UInt64(string)
        case .bool?, .array?, .table?, .integer?, .double?, .none?, nil:
            return nil
        }
    }

    private static func appServerHookEventName(_ eventName: HookEventName) -> String {
        switch eventName {
        case .preToolUse: return "preToolUse"
        case .permissionRequest: return "permissionRequest"
        case .postToolUse: return "postToolUse"
        case .preCompact: return "preCompact"
        case .postCompact: return "postCompact"
        case .sessionStart: return "sessionStart"
        case .userPromptSubmit: return "userPromptSubmit"
        case .stop: return "stop"
        }
    }

    private static func userHookHash(
        eventName: HookEventName,
        matcher: String?,
        command: String,
        timeoutSec: UInt64,
        statusMessage: String?
    ) -> String {
        let identity = [
            eventName.rawValue,
            matcher ?? "",
            command,
            String(timeoutSec),
            statusMessage ?? ""
        ].joined(separator: "\u{1f}")
        let digest = SHA256.hash(data: Data(identity.utf8))
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func tomlString(_ raw: String) -> String? {
        guard case let .string(value) = try? ConfigValueParser.parseTomlLiteral(raw) else {
            return nil
        }
        return value
    }

    private static func firstEqualsIndex(in line: String) -> String.Index? {
        var quote: Character?
        var previousWasBackslash = false
        for index in line.indices {
            let character = line[index]
            if let activeQuote = quote {
                if character == activeQuote && !previousWasBackslash {
                    quote = nil
                }
                previousWasBackslash = character == "\\" && !previousWasBackslash
                if character != "\\" {
                    previousWasBackslash = false
                }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                previousWasBackslash = false
                continue
            }
            if character == "=" {
                return index
            }
        }
        return nil
    }

    private static func stripTomlComment(from line: String) -> String {
        var quote: Character?
        var previousWasBackslash = false
        for index in line.indices {
            let character = line[index]
            if let activeQuote = quote {
                if character == activeQuote && !previousWasBackslash {
                    quote = nil
                }
                previousWasBackslash = character == "\\" && !previousWasBackslash
                if character != "\\" {
                    previousWasBackslash = false
                }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                previousWasBackslash = false
                continue
            }
            if character == "#" {
                return String(line[..<index])
            }
        }
        return line
    }

    private static func experimentalFeatureStageObject(_ stage: FeatureStage) -> String {
        switch stage {
        case .experimental:
            return "beta"
        case .underDevelopment:
            return "underDevelopment"
        case .stable:
            return "stable"
        case .deprecated:
            return "deprecated"
        case .removed:
            return "removed"
        }
    }

    private static func modelUpgradeInfoObject(_ upgrade: ModelUpgrade?) -> Any {
        guard let upgrade else {
            return NSNull()
        }
        return [
            "model": upgrade.id,
            "upgradeCopy": (upgrade.upgradeCopy as Any?) ?? NSNull(),
            "modelLink": (upgrade.modelLink as Any?) ?? NSNull(),
            "migrationMarkdown": (upgrade.migrationMarkdown as Any?) ?? NSNull()
        ]
    }

    private static func modelAvailabilityNuxObject(_ availabilityNux: ModelAvailabilityNux?) -> Any {
        guard let availabilityNux else {
            return NSNull()
        }
        return [
            "message": availabilityNux.message
        ]
    }

    private static func mcpServerStatusObject(
        name: String,
        tools: [String: Any],
        resources: [[String: Any]],
        resourceTemplates: [[String: Any]],
        authStatus: McpAuthStatus
    ) -> [String: Any] {
        [
            "name": name,
            "tools": tools,
            "resources": resources,
            "resourceTemplates": resourceTemplates,
            "authStatus": authStatus.rawValue
        ]
    }

    fileprivate static func fuzzyFileSearch(query: String, root: String) -> [[String: Any]] {
        let rootURL = URL(fileURLWithPath: root, isDirectory: true).standardizedFileURL
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [[String: Any]] = []
        while let fileURL = enumerator.nextObject() as? URL {
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                continue
            }
            let path = relativePath(fileURL: fileURL.standardizedFileURL, rootURL: rootURL)
            guard let indices = fuzzyMatchIndices(query: query, candidate: path) else {
                continue
            }
            results.append([
                "root": root,
                "path": path,
                "file_name": fileName(fromRelativePath: path),
                "score": fuzzyScore(candidate: path, indices: indices),
                "indices": indices
            ])
        }

        return results.sorted { lhs, rhs in
            let lhsScore = lhs["score"] as? Int ?? 0
            let rhsScore = rhs["score"] as? Int ?? 0
            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }
            return (lhs["path"] as? String ?? "") < (rhs["path"] as? String ?? "")
        }
    }

    private static func fuzzyMatchIndices(query: String, candidate: String) -> [Int]? {
        var indices: [Int] = []
        var searchStart = candidate.startIndex
        for needle in query.lowercased() {
            var found: String.Index?
            var index = searchStart
            while index < candidate.endIndex {
                if Character(String(candidate[index]).lowercased()) == needle {
                    found = index
                    break
                }
                index = candidate.index(after: index)
            }
            guard let found else {
                return nil
            }
            indices.append(candidate.distance(from: candidate.startIndex, to: found))
            searchStart = candidate.index(after: found)
        }
        return indices
    }

    private static func fuzzyScore(candidate: String, indices: [Int]) -> Int {
        guard let first = indices.first, let last = indices.last else {
            return 0
        }
        let span = last - first + 1
        let gaps = max(0, span - indices.count)
        let basenameBonus = first == 0 || candidate[candidate.index(candidate.startIndex, offsetBy: first - 1)] == "/" ? 12 : 0
        return max(1, 100 + basenameBonus - candidate.count * 2 - gaps * 7 - first)
    }

    private static func relativePath(fileURL: URL, rootURL: URL) -> String {
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        if fileURL.path.hasPrefix(rootPath) {
            return String(fileURL.path.dropFirst(rootPath.count))
        }
        return fileURL.lastPathComponent
    }

    private static func fileName(fromRelativePath path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? path
    }

    private static func runOneOffCommand(
        _ command: [String],
        cwd: URL?,
        sandboxConfiguration: AppServerCommandExecSandboxConfiguration,
        timeoutMilliseconds: Int?,
        outputBytesCap: Int?,
        environment: [String: String]
    ) throws -> [String: Any] {
        let launch = try sandboxedLaunch(
            command: command,
            sandboxConfiguration: sandboxConfiguration,
            environment: environment
        )
        let process = Process()
        if launch.command[0].contains("/") {
            process.executableURL = URL(fileURLWithPath: launch.command[0])
            process.arguments = Array(launch.command.dropFirst())
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = launch.command
        }
        if let cwd {
            process.currentDirectoryURL = cwd
        }
        process.environment = launch.environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw AppServerError.internalError("exec failed: \(error)")
        }

        var timedOut = false
        if let timeoutMilliseconds {
            let deadline = Date().addingTimeInterval(TimeInterval(timeoutMilliseconds) / 1000)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            if process.isRunning {
                timedOut = true
                process.terminate()
            }
        }

        process.waitUntilExit()
        let stdoutData = cappedOutputData(
            stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
            outputBytesCap: outputBytesCap
        )
        let stderrData = cappedOutputData(
            stderrPipe.fileHandleForReading.readDataToEndOfFile(),
            outputBytesCap: outputBytesCap
        )
        let stdout = TextEncoding.bytesToStringSmart(stdoutData)
        let stderr = TextEncoding.bytesToStringSmart(stderrData)
        return [
            "exitCode": timedOut ? 124 : Int(process.terminationStatus),
            "stdout": stdout,
            "stderr": stderr
        ]
    }

    private static func cappedOutputData(_ data: Data, outputBytesCap: Int?) -> Data {
        guard let outputBytesCap else {
            return data
        }
        return data.prefix(max(outputBytesCap, 0))
    }

    private static func loadSkills(cwd: URL, codexHome: URL) -> SkillLoadOutcome {
        var outcome = SkillLoadOutcome()
        for root in skillRoots(cwd: cwd, codexHome: codexHome) {
            let standardizedRoot = root.path.resolvingSymlinksInPath().standardizedFileURL
            discoverSkills(root: standardizedRoot, scope: root.scope, outcome: &outcome)
        }

        var seen: Set<String> = []
        outcome.skills = outcome.skills.filter { seen.insert($0.name).inserted }
        let retainedSkillPaths = Set(outcome.skills.map(\.path))
        outcome.skillRootByPath = outcome.skillRootByPath.filter { retainedSkillPaths.contains($0.key) }
        outcome.skills.sort {
            if $0.name != $1.name {
                return $0.name < $1.name
            }
            return $0.path < $1.path
        }
        return outcome
    }

    private static func isSkillEnabled(_ skill: SkillMetadata, rules: [SkillConfigRule]) -> Bool {
        var enabled = true
        let normalizedPath = normalizeSkillConfigPath(skill.path)
        for rule in rules where rule.matches(name: skill.name, path: normalizedPath) {
            enabled = rule.enabled
        }
        return enabled
    }

    private static func skillConfigRules(from config: ConfigValue) -> [SkillConfigRule] {
        guard case let .table(root) = config,
              case let .table(skills)? = root["skills"],
              case let .array(entries)? = skills["config"]
        else {
            return []
        }
        return entries.compactMap { entry in
            guard case let .table(table) = entry,
                  case let .bool(enabled)? = table["enabled"]
            else {
                return nil
            }
            if case let .string(path)? = table["path"],
               table["name"] == nil {
                return SkillConfigRule(selector: .path(normalizeSkillConfigPath(path)), enabled: enabled)
            }
            if case let .string(name)? = table["name"],
               table["path"] == nil {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : SkillConfigRule(selector: .name(trimmed), enabled: enabled)
            }
            return nil
        }
    }

    private static func archiveConversation(
        conversationID: ConversationId,
        rolloutPath rawRolloutPath: String,
        configuration: CodexAppServerConfiguration
    ) throws -> URL {
        let fileManager = FileManager.default
        let sessionsDirectory = configuration.codexHome
            .appendingPathComponent(RolloutListing.sessionsSubdirectory, isDirectory: true)
        guard isDirectory(sessionsDirectory) else {
            throw AppServerError.internalError(
                "failed to archive conversation: unable to resolve sessions directory: sessions directory does not exist"
            )
        }

        let canonicalSessionsDirectory = sessionsDirectory.resolvingSymlinksInPath().standardizedFileURL
        let rolloutURL = URL(fileURLWithPath: rawRolloutPath, isDirectory: false)
        let canonicalRolloutPath = rolloutURL.resolvingSymlinksInPath().standardizedFileURL
        guard canonicalRolloutPath.path.hasPrefix(canonicalSessionsDirectory.path + "/") ||
            canonicalRolloutPath.path == canonicalSessionsDirectory.path
        else {
            throw AppServerError.invalidRequest(
                "rollout path `\(rawRolloutPath)` must be in sessions directory"
            )
        }
        guard fileManager.fileExists(atPath: canonicalRolloutPath.path) else {
            throw AppServerError.invalidRequest(
                "rollout path `\(rawRolloutPath)` must be in sessions directory"
            )
        }

        let fileName = canonicalRolloutPath.lastPathComponent
        guard !fileName.isEmpty else {
            throw AppServerError.invalidRequest("rollout path `\(rawRolloutPath)` missing file name")
        }
        guard fileName.hasSuffix("\(conversationID).jsonl") else {
            throw AppServerError.invalidRequest(
                "rollout path `\(rawRolloutPath)` does not match conversation id \(conversationID)"
            )
        }

        let archivedDirectory = configuration.codexHome
            .appendingPathComponent(RolloutErrors.archivedSessionsSubdirectory, isDirectory: true)
        let archivedPath = archivedDirectory.appendingPathComponent(fileName, isDirectory: false)
        do {
            try fileManager.createDirectory(at: archivedDirectory, withIntermediateDirectories: true)
            try fileManager.moveItem(at: canonicalRolloutPath, to: archivedPath)
        } catch {
            throw AppServerError.internalError("failed to archive conversation: \(error)")
        }
        return archivedPath
    }

    private static func unarchiveConversation(
        conversationID: ConversationId,
        configuration: CodexAppServerConfiguration
    ) throws -> String {
        let archivedPath = try archivedRolloutPathForConversation(
            conversationID,
            configuration: configuration
        )
        let destinationDirectory = try sessionsDirectoryForArchivedRollout(
            archivedPath,
            configuration: configuration
        )
        let destinationPath = destinationDirectory.appendingPathComponent(
            archivedPath.lastPathComponent,
            isDirectory: false
        )
        do {
            try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: archivedPath, to: destinationPath)
            try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: destinationPath.path)
        } catch {
            throw AppServerError.internalError("failed to unarchive thread: \(error)")
        }
        return destinationPath.path
    }

    private static func markStateThreadArchived(
        conversationID: ConversationId,
        rolloutPath: URL,
        configuration: CodexAppServerConfiguration
    ) {
        guard let stateStore = configuration.stateStore,
              let threadID = try? ThreadId(string: conversationID.description)
        else {
            return
        }
        try? runAsyncBlocking {
            _ = try await stateStore.markThreadArchived(
                threadID: threadID,
                rolloutPath: rolloutPath,
                archivedAt: Date()
            )
        }
    }

    private static func markStateThreadUnarchived(
        conversationID: ConversationId,
        rolloutPath: URL,
        configuration: CodexAppServerConfiguration
    ) {
        guard let stateStore = configuration.stateStore,
              let threadID = try? ThreadId(string: conversationID.description)
        else {
            return
        }
        try? runAsyncBlocking {
            _ = try await stateStore.markThreadUnarchived(threadID: threadID, rolloutPath: rolloutPath)
        }
    }

    private static func modificationDate(forPath path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func archivedRolloutPathForConversation(
        _ conversationID: ConversationId,
        configuration: CodexAppServerConfiguration
    ) throws -> URL {
        let archivedDirectory = configuration.codexHome
            .appendingPathComponent(RolloutErrors.archivedSessionsSubdirectory, isDirectory: true)
        guard isDirectory(archivedDirectory) else {
            throw AppServerError.invalidRequest("thread not archived: \(conversationID)")
        }

        let files = try FileManager.default.contentsOfDirectory(
            at: archivedDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        )
        guard let path = files.first(where: { url in
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                return false
            }
            return url.lastPathComponent.hasSuffix("\(conversationID).jsonl")
        }) else {
            throw AppServerError.invalidRequest("thread not archived: \(conversationID)")
        }
        return path
    }

    private static func sessionsDirectoryForArchivedRollout(
        _ archivedPath: URL,
        configuration: CodexAppServerConfiguration
    ) throws -> URL {
        guard let (timestamp, _) = RolloutListing.parseTimestampUUIDFromFilename(archivedPath.lastPathComponent) else {
            throw AppServerError.invalidRequest("archived rollout filename is invalid: \(archivedPath.lastPathComponent)")
        }
        let components = rolloutSessionPathComponents.string(from: timestamp).split(separator: "/").map(String.init)
        return components.reduce(
            configuration.codexHome.appendingPathComponent(RolloutListing.sessionsSubdirectory, isDirectory: true)
        ) { path, component in
            path.appendingPathComponent(component, isDirectory: true)
        }
    }

    private static let rolloutSessionPathComponents: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    private static func skillRoots(cwd: URL, codexHome: URL) -> [(path: URL, scope: SkillScope)] {
        var roots: [(URL, SkillScope)] = []
        if let repoRoot = repoSkillsRoot(cwd: cwd) {
            roots.append((repoRoot, .repo))
        }
        roots.append((codexHome.appendingPathComponent("skills", isDirectory: true), .user))
        roots.append((codexHome.appendingPathComponent("skills/.system", isDirectory: true), .system))
        #if os(Windows)
        #else
        roots.append((URL(fileURLWithPath: "/etc/codex/skills", isDirectory: true), .admin))
        #endif
        return roots
    }

    private static func repoSkillsRoot(cwd: URL) -> URL? {
        let base = isDirectory(cwd) ? cwd : cwd.deletingLastPathComponent()
        let normalizedBase = base.resolvingSymlinksInPath().standardizedFileURL
        let repoRoot = GitInfoCollector.resolveRootGitProjectForTrust(cwd: normalizedBase) ??
            GitInfoCollector.gitRepoRoot(baseDir: normalizedBase)

        if let repoRoot {
            var current = normalizedBase
            while true {
                let candidate = current
                    .appendingPathComponent(".codex", isDirectory: true)
                    .appendingPathComponent("skills", isDirectory: true)
                if isDirectory(candidate) {
                    return candidate
                }
                if current.standardizedFileURL.path == repoRoot.standardizedFileURL.path {
                    return nil
                }
                let parent = current.deletingLastPathComponent()
                if parent.path == current.path {
                    return nil
                }
                current = parent
            }
        }

        let candidate = normalizedBase
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("skills", isDirectory: true)
        return isDirectory(candidate) ? candidate : nil
    }

    private static func discoverSkills(root: URL, scope: SkillScope, outcome: inout SkillLoadOutcome) {
        let fileManager = FileManager.default
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        guard isDirectory(root) else {
            return
        }
        if !outcome.skillRoots.contains(root.path) {
            outcome.skillRoots.append(root.path)
        }

        var queue = [root]
        while !queue.isEmpty {
            let dir = queue.removeFirst()
            guard let entries = try? fileManager.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for entry in entries {
                guard entry.lastPathComponent.first != "." else {
                    continue
                }
                let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
                if values?.isSymbolicLink == true {
                    continue
                }
                if values?.isDirectory == true {
                    queue.append(entry)
                    continue
                }
                if values?.isRegularFile == true, entry.lastPathComponent == "SKILL.md" {
                    do {
                        let skill = try parseSkillFile(entry, scope: scope)
                        outcome.skills.append(skill)
                        outcome.skillRootByPath[skill.path] = root.path
                    } catch {
                        if scope != .system {
                            outcome.errors.append(SkillErrorInfo(path: entry.path, message: String(describing: error)))
                        }
                    }
                }
            }
        }
    }

    private static func parseSkillFile(_ url: URL, scope: SkillScope) throws -> SkillMetadata {
        let contents = try String(contentsOf: url, encoding: .utf8)
        guard let frontmatter = extractSkillFrontmatter(contents) else {
            throw SkillParseError.missingFrontmatter
        }
        let fields = parseSkillFrontmatter(frontmatter)
        let name = sanitizeSkillLine(fields["name"])
        let description = sanitizeSkillLine(fields["description"])
        let shortDescription = sanitizeSkillLine(fields["metadata.short-description"])

        guard let name, !name.isEmpty else {
            throw SkillParseError.missingField("name")
        }
        guard name.count <= 64 else {
            throw SkillParseError.invalidField("name", "exceeds maximum length of 64 characters")
        }
        guard let description, !description.isEmpty else {
            throw SkillParseError.missingField("description")
        }
        guard description.count <= 1024 else {
            throw SkillParseError.invalidField("description", "exceeds maximum length of 1024 characters")
        }
        if let shortDescription, shortDescription.count > 1024 {
            throw SkillParseError.invalidField(
                "metadata.short-description",
                "exceeds maximum length of 1024 characters"
            )
        }

        return SkillMetadata(
            name: name,
            description: description,
            shortDescription: shortDescription?.isEmpty == false ? shortDescription : nil,
            path: url.resolvingSymlinksInPath().standardizedFileURL.path,
            scope: scope
        )
    }

    private static func extractSkillFrontmatter(_ contents: String) -> String? {
        var lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---" else {
            return nil
        }
        lines.removeFirst()
        var frontmatter: [String] = []
        for line in lines {
            if line.trimmingCharacters(in: .whitespacesAndNewlines) == "---" {
                return frontmatter.isEmpty ? nil : frontmatter.joined(separator: "\n")
            }
            frontmatter.append(line)
        }
        return nil
    }

    private static func parseSkillFrontmatter(_ frontmatter: String) -> [String: String] {
        var fields: [String: String] = [:]
        var prefix: String?
        for rawLine in frontmatter.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
                continue
            }
            if !line.hasPrefix(" "), !line.hasPrefix("\t"), trimmed.hasSuffix(":") {
                prefix = String(trimmed.dropLast())
                continue
            }
            guard let colon = trimmed.firstIndex(of: ":") else {
                continue
            }
            let isNested = line.hasPrefix(" ") || line.hasPrefix("\t")
            let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
            let valueStart = trimmed.index(after: colon)
            let value = trimmingMatchingQuotes(
                String(trimmed[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            )
            fields[[isNested ? prefix : nil, key].compactMap(\.self).joined(separator: ".")] = value
            if !isNested {
                prefix = nil
            }
        }
        return fields
    }

    private static func sanitizeSkillLine(_ value: String?) -> String? {
        value?
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func skillObject(_ skill: SkillMetadata) -> [String: Any] {
        [
            "name": skill.name,
            "description": skill.description,
            "shortDescription": skill.shortDescription as Any,
            "path": skill.path,
            "scope": skill.scope.rawValue
        ].nullStripped()
    }

    private static func skillErrorObject(_ error: SkillErrorInfo) -> [String: Any] {
        [
            "path": error.path,
            "message": error.message
        ]
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func layerObject(_ layer: ConfigLayerEntry) -> [String: Any] {
        [
            "name": sourceObject(layer.name),
            "version": layer.version,
            "config": configReadConfigObject(layer.config)
        ]
    }

    private static func metadataObjects(_ origins: [String: ConfigLayerMetadata]) -> [String: Any] {
        origins.mapValues { metadata in
            [
                "name": sourceObject(metadata.name),
                "version": metadata.version
            ]
        }
    }

    private static func sourceObject(_ source: ConfigLayerSource) -> [String: Any] {
        switch source {
        case let .mdm(domain, key):
            return ["type": "mdm", "domain": domain, "key": key]
        case let .system(file):
            return ["type": "system", "file": file.path]
        case let .user(file):
            return ["type": "user", "file": file.path]
        case let .project(dotCodexFolder):
            return ["type": "project", "dotCodexFolder": dotCodexFolder.path]
        case .sessionFlags:
            return ["type": "sessionFlags"]
        case let .legacyManagedConfigTomlFromFile(file):
            return ["type": "legacyManagedConfigTomlFromFile", "file": file.path]
        case .legacyManagedConfigTomlFromMdm:
            return ["type": "legacyManagedConfigTomlFromMdm"]
        }
    }

    private static func configValueObject(_ value: ConfigValue) -> Any {
        switch value {
        case .none:
            return NSNull()
        case let .string(string):
            return string
        case let .integer(integer):
            return integer
        case let .double(double):
            return double
        case let .bool(bool):
            return bool
        case let .array(array):
            return array.map(configValueObject)
        case let .table(table):
            return table.mapValues(configValueObject)
        }
    }

    private static func configReadConfigObject(_ value: ConfigValue) -> Any {
        guard case let .table(table) = value else {
            return configValueObject(value)
        }
        var object = table.mapValues(configValueObject)
        if case let .table(toolsTable)? = table["tools"] {
            object["tools"] = configReadToolsObject(toolsTable)
        }
        if case let .table(appsTable)? = table["apps"] {
            object["apps"] = configReadAppsObject(appsTable)
        }
        return object
    }

    private static func configReadToolsObject(_ table: [String: ConfigValue]) -> [String: Any] {
        var object: [String: Any] = [
            "web_search": NSNull(),
            "view_image": NSNull()
        ]
        if case let .table(webSearchTable)? = table["web_search"] {
            object["web_search"] = configReadWebSearchToolObject(webSearchTable)
        }
        if case let .bool(viewImage)? = table["view_image"] {
            object["view_image"] = viewImage
        }
        return object
    }

    private static func configReadWebSearchToolObject(_ table: [String: ConfigValue]) -> [String: Any] {
        [
            "context_size": stringConfigValue(table["context_size"]) as Any? ?? NSNull(),
            "allowed_domains": stringArrayConfigValue(table["allowed_domains"]) as Any? ?? NSNull(),
            "location": configReadWebSearchLocationObject(table["location"])
        ]
    }

    private static func configReadWebSearchLocationObject(_ value: ConfigValue?) -> Any {
        guard case let .table(table)? = value else {
            return NSNull()
        }
        return [
            "country": stringConfigValue(table["country"]) as Any? ?? NSNull(),
            "region": stringConfigValue(table["region"]) as Any? ?? NSNull(),
            "city": stringConfigValue(table["city"]) as Any? ?? NSNull(),
            "timezone": stringConfigValue(table["timezone"]) as Any? ?? NSNull()
        ]
    }

    private static func stringConfigValue(_ value: ConfigValue?) -> String? {
        guard case let .string(string)? = value else {
            return nil
        }
        return string
    }

    private static func stringArrayConfigValue(_ value: ConfigValue?) -> [String]? {
        guard case let .array(array)? = value else {
            return nil
        }
        let strings = array.compactMap(stringConfigValue)
        return strings.count == array.count ? strings : nil
    }

    private static func configReadAppsObject(_ table: [String: ConfigValue]) -> [String: Any] {
        var object: [String: Any] = [
            "_default": NSNull()
        ]
        if case let .table(defaultTable)? = table["_default"] {
            object["_default"] = configReadAppsDefaultObject(defaultTable)
        }
        for key in table.keys.sorted() where key != "_default" {
            guard case let .table(appTable)? = table[key] else {
                continue
            }
            object[key] = configReadAppObject(appTable)
        }
        return object
    }

    private static func configReadAppsDefaultObject(_ table: [String: ConfigValue]) -> [String: Any] {
        [
            "enabled": boolConfigValue(table["enabled"]) ?? true,
            "destructive_enabled": boolConfigValue(table["destructive_enabled"]) ?? true,
            "open_world_enabled": boolConfigValue(table["open_world_enabled"]) ?? true
        ]
    }

    private static func configReadAppObject(_ table: [String: ConfigValue]) -> [String: Any] {
        [
            "enabled": boolConfigValue(table["enabled"]) ?? true,
            "destructive_enabled": boolConfigValue(table["destructive_enabled"]) as Any? ?? NSNull(),
            "open_world_enabled": boolConfigValue(table["open_world_enabled"]) as Any? ?? NSNull(),
            "default_tools_approval_mode": stringConfigValue(table["default_tools_approval_mode"]) as Any? ?? NSNull(),
            "default_tools_enabled": boolConfigValue(table["default_tools_enabled"]) as Any? ?? NSNull(),
            "tools": configReadAppToolsObject(table["tools"])
        ]
    }

    private static func configReadAppToolsObject(_ value: ConfigValue?) -> Any {
        guard case let .table(table)? = value else {
            return NSNull()
        }
        var object: [String: Any] = [:]
        for key in table.keys.sorted() {
            guard case let .table(toolTable)? = table[key] else {
                continue
            }
            object[key] = [
                "enabled": boolConfigValue(toolTable["enabled"]) as Any? ?? NSNull(),
                "approval_mode": stringConfigValue(toolTable["approval_mode"]) as Any? ?? NSNull()
            ]
        }
        return object
    }

    private static func boolConfigValue(_ value: ConfigValue?) -> Bool? {
        guard case let .bool(bool)? = value else {
            return nil
        }
        return bool
    }

    private static let supportedExperimentalFeatureEnablement = [
        "apps",
        "memories",
        "plugins",
        "remote_control",
        "tool_search",
        "tool_suggest",
        "tool_call_mcp_elicitation"
    ]

    private static func effectiveConfig(
        _ config: ConfigValue,
        applyingRuntimeFeatureEnablement runtimeFeatureEnablement: [String: Bool]
    ) -> ConfigValue {
        let protectedFeatures = protectedFeatureKeys(in: config)
        var featureValues: [String: ConfigValue] = [:]
        for (name, enabled) in runtimeFeatureEnablement where !protectedFeatures.contains(name) {
            guard FeatureRegistry.specs.contains(where: { $0.key == name }) else {
                continue
            }
            featureValues[name] = .bool(enabled)
        }
        guard !featureValues.isEmpty else {
            return config
        }
        return config.merging(overlay: .table([
            "features": .table(featureValues)
        ]))
    }

    private static func applyRuntimeFeatureEnablement(
        _ runtimeFeatureEnablement: [String: Bool],
        to features: inout FeatureStates,
        protectedFeatureKeys: Set<String>
    ) {
        for (name, enabled) in runtimeFeatureEnablement where !protectedFeatureKeys.contains(name) {
            guard let feature = FeatureRegistry.feature(forKey: name) else {
                continue
            }
            features.set(feature, enabled: enabled)
        }
        features.normalizeDependencies()
    }

    private static func protectedFeatureKeys(in config: ConfigValue) -> Set<String> {
        guard case let .table(table) = config,
              case let .table(features)? = table["features"]
        else {
            return []
        }
        return Set(features.keys)
    }

    private static func appendThreadName(threadID: ConversationId, name: String, codexHome: URL) throws {
        let path = sessionIndexPath(codexHome: codexHome)
        let entry: [String: Any] = [
            "id": threadID.description,
            "thread_name": name,
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
        let data = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys])
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: path.path) {
            try Data().write(to: path, options: .atomic)
        }
        let handle = try FileHandle(forWritingTo: path)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.write(contentsOf: Data([0x0A]))
    }

    private static func sessionIndexPath(codexHome: URL) -> URL {
        codexHome.appendingPathComponent("session_index.jsonl", isDirectory: false)
    }

    private static func readSessionMetaLine(rolloutPath: String) throws -> SessionMetaLine {
        let text = try String(contentsOf: URL(fileURLWithPath: rolloutPath, isDirectory: false), encoding: .utf8)
        for rawLine in text.split(whereSeparator: \.isNewline) {
            guard let data = rawLine.data(using: .utf8),
                  let line = try? JSONDecoder().decode(RolloutLine.self, from: data),
                  case let .sessionMeta(sessionMeta) = line.item
            else {
                continue
            }
            return sessionMeta
        }
        throw RolloutRecorderError.missingConversationID
    }

    private static func configWriteResult(
        edits: [ConfigWriteEdit],
        filePath: String?,
        expectedVersion: String?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        let configFile = configuration.codexHome.appendingPathComponent("config.toml", isDirectory: false)
        let allowedPath = configFile.standardizedFileURL.path
        let providedPath = filePath.map { URL(fileURLWithPath: $0, isDirectory: false).standardizedFileURL.path }
            ?? allowedPath
        guard providedPath == allowedPath else {
            throw AppServerError.invalidRequestWithData(
                "Only writes to the user config are allowed",
                data: ["config_write_error_code": "configLayerReadonly"]
            )
        }

        let stack = try CodexConfigLayerLoader.loadConfigLayerStack(
            codexHome: configuration.codexHome,
            cliOverrides: configuration.cliConfigOverrides,
            overrides: configuration.configLayerOverrides,
            environment: configuration.environment
        )
        let userConfig = stack.getUserLayer()?.config ?? .table([:])
        let currentVersion = stack.getUserLayer()?.version ?? ConfigFingerprint.version(for: userConfig)
        if let expectedVersion, expectedVersion != currentVersion {
            throw AppServerError.invalidRequestWithData(
                "Configuration was modified since last read. Fetch latest version and retry.",
                data: ["config_write_error_code": "configVersionConflict"]
            )
        }

        var nextConfig = userConfig
        var editedPaths: [[String]] = []
        for edit in edits {
            editedPaths.append(try applyConfigWriteEdit(edit, to: &nextConfig))
        }

        let updatedStack: ConfigLayerStack
        do {
            try CodexConfigLoader.validateForConfigWrite(
                nextConfig,
                environment: configuration.environment
            )
            try validateFeatureRequirementsForConfigWrite(
                nextConfig,
                featureRequirements: stack.requirementsToml.featureRequirements
            )
            updatedStack = stack.withUserConfig(
                configToml: try AbsolutePath(absolutePath: allowedPath),
                userConfig: nextConfig
            )
            try CodexConfigLoader.validateForConfigWrite(
                updatedStack.effectiveConfig(),
                environment: configuration.environment
            )
        } catch {
            throw AppServerError.invalidRequestWithData(
                "Invalid configuration: \(error)",
                data: ["config_write_error_code": "configValidationError"]
            )
        }

        let overridden = firstOverriddenConfigWrite(
            layers: updatedStack,
            effectiveConfig: updatedStack.effectiveConfig(),
            editedPaths: editedPaths
        )
        try FileManager.default.createDirectory(at: configuration.codexHome, withIntermediateDirectories: true)
        let renderedConfig = configTomlForWrite(
            nextConfig,
            edits: edits,
            existingContents: try? String(contentsOf: configFile, encoding: .utf8)
        )
        try renderedConfig.write(to: configFile, atomically: true, encoding: .utf8)

        return [
            "status": overridden == nil ? "ok" : "okOverridden",
            "version": ConfigFingerprint.version(for: nextConfig),
            "filePath": allowedPath,
            "overriddenMetadata": overridden.map(overriddenMetadataObject) ?? NSNull()
        ]
    }

    private static func setSkillConfig(selector: SkillConfigSelector, enabled: Bool, in config: inout ConfigValue) {
        var root: [String: ConfigValue]
        if case let .table(existing) = config {
            root = existing
        } else {
            root = [:]
        }

        var skills: [String: ConfigValue]
        if case let .table(existing)? = root["skills"] {
            skills = existing
        } else {
            if enabled {
                config = .table(root)
                return
            }
            skills = [:]
        }

        var entries: [ConfigValue]
        if case let .array(existing)? = skills["config"] {
            entries = existing
        } else {
            if enabled {
                config = .table(root)
                return
            }
            entries = []
        }

        let existingIndex = entries.firstIndex { entry in
            guard case let .table(table) = entry else {
                return false
            }
            return skillConfigSelector(from: table) == selector
        }

        if enabled {
            if let existingIndex {
                entries.remove(at: existingIndex)
            }
        } else {
            let entry = skillConfigEntry(selector: selector)
            if let existingIndex {
                entries[existingIndex] = entry
            } else {
                entries.append(entry)
            }
        }

        if entries.isEmpty {
            skills.removeValue(forKey: "config")
        } else {
            skills["config"] = .array(entries)
        }

        if skills.isEmpty {
            root.removeValue(forKey: "skills")
        } else {
            root["skills"] = .table(skills)
        }
        config = .table(root)
    }

    private static func skillConfigEntry(selector: SkillConfigSelector) -> ConfigValue {
        switch selector {
        case let .path(path):
            return .table([
                "path": .string(path),
                "enabled": .bool(false)
            ])
        case let .name(name):
            return .table([
                "name": .string(name),
                "enabled": .bool(false)
            ])
        }
    }

    private static func skillConfigSelector(from table: [String: ConfigValue]) -> SkillConfigSelector? {
        if case let .string(path)? = table["path"],
           table["name"] == nil {
            return .path(normalizeSkillConfigPath(path))
        }
        if case let .string(name)? = table["name"],
           table["path"] == nil {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : .name(trimmed)
        }
        return nil
    }

    private static func normalizeSkillConfigPath(_ path: String) -> String {
        let url = URL(fileURLWithPath: path, isDirectory: false)
        if FileManager.default.fileExists(atPath: url.path) {
            return url.resolvingSymlinksInPath().standardizedFileURL.path
        }
        return url.standardizedFileURL.path
    }

    private static func configWriteValue(_ value: Any?) throws -> ConfigValue? {
        guard let value else {
            throw AppServerError.invalidRequest("missing value")
        }
        if value is NSNull {
            return nil
        }
        return try configValue(fromJSONObject: value)
    }

    private static func configValue(fromJSONObject value: Any) throws -> ConfigValue {
        switch value {
        case let string as String:
            return .string(string)
        case let bool as Bool:
            return .bool(bool)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            let double = number.doubleValue
            if double.rounded() == double {
                return .integer(number.int64Value)
            }
            return .double(double)
        case let array as [Any]:
            return .array(try array.map(configValue(fromJSONObject:)))
        case let object as [String: Any]:
            return .table(try object.mapValues(configValue(fromJSONObject:)))
        default:
            throw AppServerError.invalidRequestWithData(
                "invalid value",
                data: ["config_write_error_code": "configValidationError"]
            )
        }
    }

    private static func applyConfigWriteEdit(_ edit: ConfigWriteEdit, to config: inout ConfigValue) throws -> [String] {
        let path = try configWriteKeyPath(edit.keyPath)

        if let value = edit.value {
            setConfigValue(value, at: path, mergeStrategy: edit.mergeStrategy, in: &config)
        } else {
            _ = removeConfigValue(at: path, in: &config)
        }
        return path
    }

    private static func configTomlForWrite(
        _ nextConfig: ConfigValue,
        edits: [ConfigWriteEdit],
        existingContents: String?
    ) -> String {
        guard let existingContents,
              let edited = sourcePreservingConfigToml(existingContents, edits: edits)
        else {
            return renderConfigToml(nextConfig)
        }
        return edited
    }

    private static func sourcePreservingConfigToml(_ contents: String, edits: [ConfigWriteEdit]) -> String? {
        guard !edits.isEmpty else {
            return contents
        }
        var lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for edit in edits {
            guard edit.mergeStrategy == .replace,
                  let value = edit.value,
                  sourcePreservingTomlLiteral(value) != nil,
                  let path = try? configWriteKeyPath(edit.keyPath),
                  let key = path.last
            else {
                return nil
            }
            let tablePath = Array(path.dropLast())
            applySourcePreservingAssignment(
                key: key,
                value: value,
                tablePath: tablePath,
                lines: &lines
            )
        }
        return trimTrailingBlankLines(lines.joined(separator: "\n")) + "\n"
    }

    private static func applySourcePreservingAssignment(
        key: String,
        value: ConfigValue,
        tablePath: [String],
        lines: inout [String]
    ) {
        let header = tablePath.isEmpty ? nil : tablePath.map(tomlKey).joined(separator: ".")
        var range = configSectionRange(header, in: lines)
        if range.isEmpty, let header {
            if !lines.isEmpty, lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                lines.append("")
            }
            lines.append("[\(header)]")
            let bodyStart = lines.index(before: lines.endIndex)
            range = bodyStart..<bodyStart
        }

        let assignmentKey = tomlKey(key)
        let assignment = "\(assignmentKey) = \(sourcePreservingTomlLiteral(value) ?? tomlLiteral(value))"
        for index in range where tomlAssignmentKey(lines[index]) == assignmentKey {
            lines[index] = assignment
            return
        }

        let insertionIndex = sourcePreservingInsertionIndex(for: range, in: lines)
        lines.insert(assignment, at: insertionIndex)
    }

    private static func sourcePreservingInsertionIndex(for range: Range<Int>, in lines: [String]) -> Int {
        var insertionIndex = range.upperBound
        while insertionIndex > range.lowerBound,
              lines[lines.index(before: insertionIndex)].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            insertionIndex = lines.index(before: insertionIndex)
        }
        return insertionIndex
    }

    private static func sourcePreservingTomlLiteral(_ value: ConfigValue) -> String? {
        switch value {
        case .none, .table:
            return nil
        case .string, .integer, .double, .bool:
            return tomlLiteral(value)
        case let .array(values):
            guard values.allSatisfy({
                if case .none = $0 { return false }
                if case .table = $0 { return false }
                return true
            }) else {
                return nil
            }
            return tomlLiteral(.array(values))
        }
    }

    private static func configWriteKeyPath(_ keyPath: String) throws -> [String] {
        guard !keyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppServerError.invalidRequestWithData(
                "keyPath must not be empty",
                data: ["config_write_error_code": "configValidationError"]
            )
        }
        return keyPath.components(separatedBy: ".")
    }

    private static func setConfigValue(
        _ value: ConfigValue,
        at path: [String],
        mergeStrategy: ConfigMergeStrategy,
        in target: inout ConfigValue
    ) {
        guard let first = path.first else { return }
        var table: [String: ConfigValue]
        if case let .table(existing) = target {
            table = existing
        } else {
            table = [:]
        }

        if path.count == 1 {
            if mergeStrategy == .upsert,
               case let .table(existingTable)? = table[first],
               case let .table(newTable) = value {
                var merged = ConfigValue.table(existingTable)
                merged.merge(overlay: .table(newTable))
                table[first] = merged
            } else {
                table[first] = value
            }
            target = .table(table)
            return
        }

        var child = table[first] ?? .table([:])
        setConfigValue(value, at: Array(path.dropFirst()), mergeStrategy: mergeStrategy, in: &child)
        table[first] = child
        target = .table(table)
    }

    private static func removeConfigValue(at path: [String], in target: inout ConfigValue) -> Bool {
        guard let first = path.first,
              case var .table(table) = target
        else {
            return false
        }
        if path.count == 1 {
            let removed = table.removeValue(forKey: first) != nil
            target = .table(table)
            return removed
        }
        guard var child = table[first] else {
            return false
        }
        let removed = removeConfigValue(at: Array(path.dropFirst()), in: &child)
        if removed {
            table[first] = child
            target = .table(table)
        }
        return removed
    }

    private static func validateFeatureRequirementsForConfigWrite(
        _ config: ConfigValue,
        featureRequirements: [String: Bool]?
    ) throws {
        guard let featureRequirements, !featureRequirements.isEmpty else {
            return
        }
        let root = configTable(config) ?? [:]
        try validateFeatureTable(
            root["features"],
            pathPrefix: "features",
            featureRequirements: featureRequirements
        )
        guard let profiles = root["profiles"].flatMap(configTable) else {
            return
        }
        for profileName in profiles.keys.sorted() {
            guard let profile = profiles[profileName].flatMap(configTable) else {
                continue
            }
            try validateFeatureTable(
                profile["features"],
                pathPrefix: "profiles.\(profileName).features",
                featureRequirements: featureRequirements
            )
        }
    }

    private static func validateFeatureTable(
        _ value: ConfigValue?,
        pathPrefix: String,
        featureRequirements: [String: Bool]
    ) throws {
        guard let features = value.flatMap(configTable) else {
            return
        }
        for feature in features.keys.sorted() {
            guard let required = featureRequirements[feature],
                  case let .bool(enabled)? = features[feature],
                  required != enabled
            else {
                continue
            }
            throw AppServerError.invalidRequest(
                "invalid value for `features`: `\(pathPrefix).\(feature)=\(enabled)`"
            )
        }
    }

    private struct OverriddenConfigWrite {
        var message: String
        var overridingLayer: ConfigLayerMetadata
        var effectiveValue: ConfigValue?
    }

    private static func firstOverriddenConfigWrite(
        layers: ConfigLayerStack,
        effectiveConfig: ConfigValue,
        editedPaths: [[String]]
    ) -> OverriddenConfigWrite? {
        for path in editedPaths {
            if let overridden = overriddenConfigWrite(layers: layers, effectiveConfig: effectiveConfig, path: path) {
                return overridden
            }
        }
        return nil
    }

    private static func overriddenConfigWrite(
        layers: ConfigLayerStack,
        effectiveConfig: ConfigValue,
        path: [String]
    ) -> OverriddenConfigWrite? {
        guard let userLayer = layers.getUserLayer() else {
            return nil
        }
        let userValue = configValue(at: path, in: userLayer.config)
        let effectiveValue = configValue(at: path, in: effectiveConfig)
        if userValue != nil, userValue == effectiveValue {
            return nil
        }
        if userValue == nil, effectiveValue == nil {
            return nil
        }
        guard let overridingLayer = effectiveConfigLayer(layers: layers, path: path) else {
            return nil
        }
        return OverriddenConfigWrite(
            message: overrideMessage(for: overridingLayer.name),
            overridingLayer: overridingLayer,
            effectiveValue: effectiveValue
        )
    }

    private static func effectiveConfigLayer(layers: ConfigLayerStack, path: [String]) -> ConfigLayerMetadata? {
        for layer in layers.layersHighToLow() where configValue(at: path, in: layer.config) != nil {
            return layer.metadata()
        }
        return nil
    }

    private static func configValue(at path: [String], in root: ConfigValue) -> ConfigValue? {
        var current = root
        for segment in path {
            switch current {
            case let .table(table):
                guard let next = table[segment] else {
                    return nil
                }
                current = next
            case let .array(items):
                guard let index = Int(segment), items.indices.contains(index) else {
                    return nil
                }
                current = items[index]
            case .none, .string, .integer, .double, .bool:
                return nil
            }
        }
        return current
    }

    private static func overriddenMetadataObject(_ overridden: OverriddenConfigWrite) -> [String: Any] {
        [
            "message": overridden.message,
            "overridingLayer": [
                "name": sourceObject(overridden.overridingLayer.name),
                "version": overridden.overridingLayer.version
            ],
            "effectiveValue": overridden.effectiveValue.map(configValueObject) ?? NSNull()
        ]
    }

    private static func overrideMessage(for layer: ConfigLayerSource) -> String {
        switch layer {
        case let .mdm(domain, _):
            return "Overridden by managed policy (MDM): \(domain)"
        case let .system(file):
            return "Overridden by managed config (system): \(file.path)"
        case let .project(dotCodexFolder):
            return "Overridden by project config: \(dotCodexFolder.path)/config.toml"
        case .sessionFlags:
            return "Overridden by session flags"
        case let .user(file):
            return "Overridden by user config: \(file.path)"
        case let .legacyManagedConfigTomlFromFile(file):
            return "Overridden by legacy managed_config.toml: \(file.path)"
        case .legacyManagedConfigTomlFromMdm:
            return "Overridden by legacy managed configuration from MDM"
        }
    }

    private static func renderConfigToml(_ value: ConfigValue) -> String {
        guard case let .table(table) = value else {
            return ""
        }
        var lines: [String] = []
        renderConfigTable(table, path: [], lines: &lines)
        guard !lines.isEmpty else {
            return ""
        }
        return trimTrailingBlankLines(lines.joined(separator: "\n")) + "\n"
    }

    private static func renderConfigTable(_ table: [String: ConfigValue], path: [String], lines: inout [String]) {
        let scalarKeys = table.keys.sorted { left, right in
            let leftRank = configScalarSortRank(left, path: path)
            let rightRank = configScalarSortRank(right, path: path)
            if leftRank.rank != rightRank.rank {
                return leftRank.rank < rightRank.rank
            }
            return leftRank.key < rightRank.key
        }.filter { key in
            if case .table = table[key] { return false }
            if isArrayOfTables(table[key]) { return false }
            return true
        }
        for key in scalarKeys {
            guard let value = table[key] else { continue }
            lines.append("\(tomlKey(key)) = \(tomlLiteral(value))")
        }

        let arrayTableKeys = table.keys.sorted().filter { key in
            isArrayOfTables(table[key])
        }
        for key in arrayTableKeys {
            guard case let .array(entries)? = table[key] else { continue }
            let nextPath = path + [key]
            for entry in entries {
                guard case let .table(child) = entry else { continue }
                if !lines.isEmpty, lines.last?.isEmpty == false {
                    lines.append("")
                }
                lines.append("[[\(nextPath.map(tomlKey).joined(separator: "."))]]")
                renderConfigTable(child, path: nextPath, lines: &lines)
            }
        }

        let tableKeys = table.keys.sorted().filter { key in
            if case .table = table[key] { return true }
            return false
        }
        for key in tableKeys {
            guard case let .table(child)? = table[key] else { continue }
            let nextPath = path + [key]
            if !child.isEmpty,
               child.keys.allSatisfy({ isArrayOfTables(child[$0]) }) {
                renderConfigTable(child, path: nextPath, lines: &lines)
                continue
            }
            if !lines.isEmpty, lines.last?.isEmpty == false {
                lines.append("")
            }
            lines.append("[\(nextPath.map(tomlKey).joined(separator: "."))]")
            renderConfigTable(child, path: nextPath, lines: &lines)
        }
    }

    private static func configScalarSortRank(_ key: String, path: [String]) -> (rank: Int, key: String) {
        if path == ["skills", "config"] {
            switch key {
            case "path":
                return (0, key)
            case "name":
                return (1, key)
            case "enabled":
                return (2, key)
            default:
                return (3, key)
            }
        }
        return (0, key)
    }

    private static func isArrayOfTables(_ value: ConfigValue?) -> Bool {
        guard case let .array(values)? = value else {
            return false
        }
        return !values.isEmpty && values.allSatisfy { element in
            if case .table = element {
                return true
            }
            return false
        }
    }

    private static func tomlLiteral(_ value: ConfigValue) -> String {
        switch value {
        case .none:
            return "null"
        case let .string(string):
            return tomlString(string)
        case let .integer(integer):
            return String(integer)
        case let .double(double):
            return String(double)
        case let .bool(bool):
            return bool ? "true" : "false"
        case let .array(array):
            return "[\(array.map(tomlLiteral).joined(separator: ", "))]"
        case let .table(table):
            let body = table.keys.sorted().map { key in
                "\(tomlKey(key)) = \(tomlLiteral(table[key]!))"
            }.joined(separator: ", ")
            return "{\(body)}"
        }
    }

    private static func tomlKey(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        if !value.isEmpty, value.unicodeScalars.allSatisfy({ allowed.contains($0) }) {
            return value
        }
        return tomlString(value)
    }

    private static func userSavedConfigObject(_ value: ConfigValue) -> [String: Any] {
        let table = configTable(value) ?? [:]
        return [
            "approvalPolicy": nullable(stringConfig(table, "approval_policy")),
            "sandboxMode": nullable(stringConfig(table, "sandbox_mode")),
            "sandboxSettings": sandboxSettingsObject(table["sandbox_workspace_write"]) as Any,
            "forcedChatgptWorkspaceId": nullable(stringConfig(table, "forced_chatgpt_workspace_id")),
            "forcedLoginMethod": nullable(stringConfig(table, "forced_login_method")),
            "model": nullable(stringConfig(table, "model")),
            "modelReasoningEffort": nullable(stringConfig(table, "model_reasoning_effort")),
            "modelReasoningSummary": nullable(stringConfig(table, "model_reasoning_summary")),
            "modelVerbosity": nullable(stringConfig(table, "model_verbosity")),
            "tools": toolsObject(table["tools"]) as Any,
            "profile": nullable(stringConfig(table, "profile")),
            "profiles": profilesObject(table["profiles"])
        ]
    }

    private static func sandboxSettingsObject(_ value: ConfigValue?) -> Any {
        guard let table = value.flatMap(configTable) else {
            return NSNull()
        }
        return [
            "writableRoots": stringArrayConfig(table, "writable_roots"),
            "networkAccess": nullable(boolConfig(table, "network_access")),
            "excludeTmpdirEnvVar": nullable(boolConfig(table, "exclude_tmpdir_env_var")),
            "excludeSlashTmp": nullable(boolConfig(table, "exclude_slash_tmp"))
        ]
    }

    private static func toolsObject(_ value: ConfigValue?) -> Any {
        guard let table = value.flatMap(configTable) else {
            return NSNull()
        }
        return [
            "webSearch": nullable(boolConfig(table, "web_search")),
            "viewImage": nullable(boolConfig(table, "view_image"))
        ]
    }

    private static func profilesObject(_ value: ConfigValue?) -> [String: Any] {
        guard let profiles = value.flatMap(configTable) else {
            return [:]
        }
        var output: [String: Any] = [:]
        for (name, profileValue) in profiles {
            let table = configTable(profileValue) ?? [:]
            output[name] = [
                "model": nullable(stringConfig(table, "model")),
                "modelProvider": nullable(stringConfig(table, "model_provider")),
                "approvalPolicy": nullable(stringConfig(table, "approval_policy")),
                "modelReasoningEffort": nullable(stringConfig(table, "model_reasoning_effort")),
                "modelReasoningSummary": nullable(stringConfig(table, "model_reasoning_summary")),
                "modelVerbosity": nullable(stringConfig(table, "model_verbosity")),
                "chatgptBaseUrl": nullable(stringConfig(table, "chatgpt_base_url"))
            ]
        }
        return output
    }

    private static func nullable(_ value: Any?) -> Any {
        value ?? NSNull()
    }

    private static func configTable(_ value: ConfigValue) -> [String: ConfigValue]? {
        guard case let .table(table) = value else {
            return nil
        }
        return table
    }

    private static func stringConfig(_ table: [String: ConfigValue], _ key: String) -> String? {
        guard case let .string(value)? = table[key] else {
            return nil
        }
        return value
    }

    private static func boolConfig(_ table: [String: ConfigValue], _ key: String) -> Bool? {
        guard case let .bool(value)? = table[key] else {
            return nil
        }
        return value
    }

    private static func stringArrayConfig(_ table: [String: ConfigValue], _ key: String) -> [String] {
        guard case let .array(values)? = table[key] else {
            return []
        }
        return values.compactMap { value in
            guard case let .string(string) = value else {
                return nil
            }
            return string
        }
    }

    private static func updateDefaultModel(
        codexHome: URL,
        model: String?,
        reasoningEffort: String?,
        activeProfile: String?
    ) throws {
        let configFile = codexHome.appendingPathComponent("config.toml", isDirectory: false)
        let existing = (try? String(contentsOf: configFile, encoding: .utf8)) ?? ""
        let profile = activeProfile ?? topLevelStringValue("profile", in: existing)
        let updated = rewriteConfigModel(
            existing,
            profile: profile,
            model: model,
            reasoningEffort: reasoningEffort
        )
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try updated.write(to: configFile, atomically: true, encoding: .utf8)
    }

    private static func rewriteConfigModel(
        _ contents: String,
        profile: String?,
        model: String?,
        reasoningEffort: String?
    ) -> String {
        var lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let targetHeader = profile.map { "profiles.\($0)" }
        let range = configSectionRange(targetHeader, in: lines)
        if range.isEmpty {
            if let targetHeader {
                if !lines.isEmpty, lines.last?.isEmpty == false {
                    lines.append("")
                }
                lines.append("[\(targetHeader)]")
                lines.append(contentsOf: modelConfigLines(model: model, reasoningEffort: reasoningEffort))
            } else {
                lines.insert(contentsOf: modelConfigLines(model: model, reasoningEffort: reasoningEffort), at: 0)
            }
        } else {
            rewriteModelLines(in: &lines, range: range, model: model, reasoningEffort: reasoningEffort)
        }
        return trimTrailingBlankLines(lines.joined(separator: "\n")) + "\n"
    }

    private static func rewriteModelLines(
        in lines: inout [String],
        range: Range<Int>,
        model: String?,
        reasoningEffort: String?
    ) {
        var output: [String] = []
        var sawModel = false
        var sawReasoningEffort = false
        for index in lines.indices {
            guard range.contains(index) else {
                output.append(lines[index])
                continue
            }
            let key = tomlAssignmentKey(lines[index])
            if key == "model" {
                sawModel = true
                if let model {
                    output.append("model = \(tomlString(model))")
                }
                continue
            }
            if key == "model_reasoning_effort" {
                sawReasoningEffort = true
                if let reasoningEffort {
                    output.append("model_reasoning_effort = \(tomlString(reasoningEffort))")
                }
                continue
            }
            output.append(lines[index])
        }

        let insertionIndex = outputInsertionIndex(forOriginalRange: range, in: output)
        var additions: [String] = []
        if !sawModel, let model {
            additions.append("model = \(tomlString(model))")
        }
        if !sawReasoningEffort, let reasoningEffort {
            additions.append("model_reasoning_effort = \(tomlString(reasoningEffort))")
        }
        if !additions.isEmpty {
            output.insert(contentsOf: additions, at: insertionIndex)
        }
        lines = output
    }

    private static func outputInsertionIndex(forOriginalRange range: Range<Int>, in output: [String]) -> Int {
        min(range.upperBound, output.count)
    }

    private static func configSectionRange(_ targetHeader: String?, in lines: [String]) -> Range<Int> {
        guard let targetHeader else {
            let end = lines.firstIndex { tomlSectionHeader($0) != nil } ?? lines.endIndex
            return 0..<end
        }

        guard let headerIndex = lines.firstIndex(where: { tomlSectionHeader($0) == targetHeader }) else {
            return lines.endIndex..<lines.endIndex
        }
        let bodyStart = lines.index(after: headerIndex)
        let bodyEnd = lines[bodyStart...].firstIndex { tomlSectionHeader($0) != nil } ?? lines.endIndex
        return bodyStart..<bodyEnd
    }

    private static func topLevelStringValue(_ key: String, in contents: String) -> String? {
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let range = configSectionRange(nil, in: lines)
        for index in range {
            guard tomlAssignmentKey(lines[index]) == key,
                  let equalsIndex = lines[index].firstIndex(of: "=")
            else {
                continue
            }
            let value = String(lines[index][lines[index].index(after: equalsIndex)...])
                .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmingMatchingQuotes(value)
        }
        return nil
    }

    private static func modelConfigLines(model: String?, reasoningEffort: String?) -> [String] {
        [
            model.map { "model = \(tomlString($0))" },
            reasoningEffort.map { "model_reasoning_effort = \(tomlString($0))" }
        ].compactMap(\.self)
    }

    private static func tomlSectionHeader(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else {
            return nil
        }
        return String(trimmed.dropFirst().dropLast())
    }

    private static func tomlAssignmentKey(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("#"),
              let equalsIndex = trimmed.firstIndex(of: "=")
        else {
            return nil
        }
        return String(trimmed[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tomlString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    private static func trimTrailingBlankLines(_ text: String) -> String {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        while let last = lines.last, last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    private static func trimmingMatchingQuotes(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        if (value.first == "\"" && value.last == "\"") || (value.first == "'" && value.last == "'") {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    fileprivate static func currentAuth(configuration: CodexAppServerConfiguration) throws -> AppServerAuth? {
        if let apiKey = CodexAuthStorage.readCodexAPIKeyFromEnvironment(configuration.environment)
            ?? CodexAuthStorage.readOpenAIAPIKeyFromEnvironment(configuration.environment) {
            return AppServerAuth(method: "apikey", token: apiKey, accountID: nil, kind: .apiKey)
        }

        guard let auth = try CodexAuthStorage.loadEffectiveAuthDotJSON(
            codexHome: configuration.codexHome,
            mode: configuration.authCredentialsStoreMode
        ) else {
            return nil
        }
        if let tokens = auth.tokens, !tokens.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AppServerAuth(
                method: auth.authMode == .chatGPTAuthTokens ? "chatgptAuthTokens" : "chatgpt",
                token: tokens.accessToken,
                accountID: tokens.accountID ?? tokens.idToken.chatGPTAccountID,
                kind: .chatGPT(tokens.idToken)
            )
        }
        if let apiKey = auth.openAIAPIKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AppServerAuth(method: "apikey", token: apiKey, accountID: nil, kind: .apiKey)
        }
        return nil
    }

    private static func planTypeWireValue(_ planType: ChatGPTPlanType?) -> String? {
        switch planType {
        case let .known(plan):
            return plan.rawValue
        case .unknown:
            return "unknown"
        case nil:
            return nil
        }
    }

    private static func write(_ data: Data?, to stdout: FileHandle) throws {
        guard let data else {
            return
        }
        try stdout.write(contentsOf: data)
        try stdout.write(contentsOf: Data([0x0A]))
    }
}

private struct AppServerAuth {
    let method: String
    let token: String
    let accountID: String?
    let kind: AppServerAuthKind
}

private enum AppServerAuthKind {
    case apiKey
    case chatGPT(IdTokenInfo)
}

private final class BlockingAsyncResult<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<T, Error>?

    func set(_ result: Result<T, Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
    }

    func get() -> Result<T, Error> {
        lock.lock()
        defer { lock.unlock() }
        return result ?? .failure(AppServerError.internalError("async operation did not complete"))
    }
}

private enum SkillParseError: Error, CustomStringConvertible {
    case missingFrontmatter
    case missingField(String)
    case invalidField(String, String)

    var description: String {
        switch self {
        case .missingFrontmatter:
            return "missing YAML frontmatter delimited by ---"
        case let .missingField(field):
            return "missing field `\(field)`"
        case let .invalidField(field, reason):
            return "invalid \(field): \(reason)"
        }
    }
}

private enum AppServerError: Error, CustomStringConvertible {
    case invalidRequest(String)
    case invalidParams(String)
    case invalidRequestWithData(String, data: [String: String])
    case invalidParamsWithInputTooLargeData(String, maxChars: Int, actualChars: Int)
    case methodNotFound(String)
    case internalError(String)

    var description: String {
        switch self {
        case let .invalidRequest(message),
             let .invalidParams(message),
             let .invalidRequestWithData(message, _),
             let .invalidParamsWithInputTooLargeData(message, _, _):
            return message
        case let .methodNotFound(message):
            return message
        case let .internalError(message):
            return message
        }
    }

    var data: Any? {
        switch self {
        case let .invalidRequestWithData(_, data):
            return data
        case let .invalidParamsWithInputTooLargeData(_, maxChars, actualChars):
            return [
                "input_error_code": "input_too_large",
                "max_chars": maxChars,
                "actual_chars": actualChars
            ]
        case .invalidRequest, .invalidParams, .methodNotFound, .internalError:
            return nil
        }
    }
}

private struct ConfigWriteEdit {
    let keyPath: String
    let value: ConfigValue?
    let mergeStrategy: ConfigMergeStrategy
}

private enum ConfigMergeStrategy {
    case replace
    case upsert

    init(rawValue: String) throws {
        switch rawValue {
        case "replace":
            self = .replace
        case "upsert":
            self = .upsert
        default:
            throw AppServerError.invalidRequest(
                "Invalid request: unknown variant `\(rawValue)`, expected `replace` or `upsert`"
            )
        }
    }
}

private enum SkillConfigSelector: Equatable {
    case path(String)
    case name(String)
}

private struct SkillConfigRule {
    let selector: SkillConfigSelector
    let enabled: Bool

    func matches(name: String, path: String) -> Bool {
        switch selector {
        case let .name(ruleName):
            return ruleName == name
        case let .path(rulePath):
            return rulePath == path
        }
    }
}

private struct AppServerStartedConversation {
    let conversationID: ConversationId
    let rolloutPath: URL?
    let model: String
    let modelProvider: String
    let cwd: URL
    let approvalPolicy: AskForApproval
    let approvalsReviewer: ApprovalsReviewer
    let serviceTier: String?
    let sandbox: SandboxPolicy
    let permissionProfile: PermissionProfile
    let activePermissionProfile: ActivePermissionProfile?
    let reasoningEffort: String?
    let sessionStartSource: HookSessionStartSource
    let ephemeral: Bool
}

fileprivate struct AppServerReviewStartOutcome {
    let result: [String: Any]
    let startedThread: [String: Any]?
}

private struct AppServerFSWatchEntry: Equatable {
    let exists: Bool
    let isDirectory: Bool
    let type: String
    let modifiedAtMs: Int64
    let size: UInt64
    let linkDestination: String?
}

private struct AppServerFSWatchSnapshot: Equatable {
    let root: AppServerFSWatchEntry
    let children: [String: AppServerFSWatchEntry]
}

private final class AppServerFSWatch: @unchecked Sendable {
    private let watchID: String
    private let path: String
    private let notificationSink: AppServerNotificationSink?
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var lastSnapshot: AppServerFSWatchSnapshot
    private var canceled = false

    init(watchID: String, path: String, notificationSink: AppServerNotificationSink?) {
        self.watchID = watchID
        self.path = path
        self.notificationSink = notificationSink
        self.queue = DispatchQueue(label: "codex.app-server.fs-watch.\(watchID)")
        self.lastSnapshot = Self.snapshot(path: path)
    }

    deinit {
        cancel()
    }

    func start() {
        guard notificationSink != nil else {
            return
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(200), repeating: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            self?.poll()
        }
        lock.withLock {
            guard !canceled else {
                timer.cancel()
                return
            }
            self.timer = timer
            timer.resume()
        }
    }

    func cancel() {
        let timer = lock.withLock {
            canceled = true
            let timer = self.timer
            self.timer = nil
            return timer
        }
        timer?.cancel()
    }

    private func poll() {
        let previous = lock.withLock { lastSnapshot }
        let current = Self.snapshot(path: path)
        guard current != previous else {
            return
        }
        let changedPaths = Self.changedPaths(path: path, previous: previous, current: current)
        lock.withLock {
            lastSnapshot = current
        }
        guard !changedPaths.isEmpty,
              let notificationSink,
              let data = CodexAppServer.encodeMessages([
                CodexAppServer.fsChangedNotification(watchID: watchID, changedPaths: changedPaths)
              ])
        else {
            return
        }
        Task { [weak self] in
            guard self?.isCanceled == false else {
                return
            }
            await notificationSink(data)
        }
    }

    private var isCanceled: Bool {
        lock.withLock { canceled }
    }

    private static func snapshot(path: String) -> AppServerFSWatchSnapshot {
        let root = entry(path: path)
        var children: [String: AppServerFSWatchEntry] = [:]
        if root.exists, root.isDirectory {
            let fileManager = FileManager.default
            let names = (try? fileManager.contentsOfDirectory(atPath: path)) ?? []
            for name in names {
                let childPath = URL(fileURLWithPath: path, isDirectory: true)
                    .appendingPathComponent(name)
                    .path
                children[name] = entry(path: childPath)
            }
        }
        return AppServerFSWatchSnapshot(root: root, children: children)
    }

    private static func entry(path: String) -> AppServerFSWatchEntry {
        let fileManager = FileManager.default
        guard let attributes = try? fileManager.attributesOfItem(atPath: path),
              let type = attributes[.type] as? FileAttributeType
        else {
            return AppServerFSWatchEntry(
                exists: false,
                isDirectory: false,
                type: "",
                modifiedAtMs: 0,
                size: 0,
                linkDestination: nil
            )
        }
        let modifiedAt = attributes[.modificationDate] as? Date
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let linkDestination = type == .typeSymbolicLink
            ? try? fileManager.destinationOfSymbolicLink(atPath: path)
            : nil
        return AppServerFSWatchEntry(
            exists: true,
            isDirectory: type == .typeDirectory,
            type: type.rawValue,
            modifiedAtMs: CodexAppServer.millisecondsSinceEpoch(modifiedAt),
            size: size,
            linkDestination: linkDestination
        )
    }

    private static func changedPaths(
        path: String,
        previous: AppServerFSWatchSnapshot,
        current: AppServerFSWatchSnapshot
    ) -> [String] {
        guard previous.root.isDirectory, current.root.isDirectory else {
            return previous.root == current.root ? [] : [path]
        }
        let names = Set(previous.children.keys).union(current.children.keys)
        return names.sorted().compactMap { name in
            previous.children[name] == current.children[name] ? nil : URL(fileURLWithPath: path, isDirectory: true)
                .appendingPathComponent(name)
                .path
        }
    }
}

private struct AppServerProcessOutputCapture {
    let text: String
    let capReached: Bool
}

private final class AppServerProcessExitSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var exited = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        let continuations = lock.withLock {
            guard !exited else {
                return [] as [CheckedContinuation<Void, Never>]
            }
            exited = true
            let continuations = waiters
            waiters.removeAll()
            return continuations
        }
        for continuation in continuations {
            continuation.resume()
        }
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock {
                if exited {
                    return true
                }
                waiters.append(continuation)
                return false
            }
            if shouldResume {
                continuation.resume()
            }
        }
    }
}

private final class AppServerPseudoTerminal: @unchecked Sendable {
    let master: FileHandle
    let stdinHandle: FileHandle
    let stdoutHandle: FileHandle
    let stderrHandle: FileHandle
    private let descriptor: Int32
    private let lock = NSLock()
    private var closed = false

    init(size: AppServerTerminalSize?) throws {
        var masterFD: Int32 = -1
        var slaveFD: Int32 = -1
        var windowSize = winsize(
            ws_row: UInt16(clamping: size?.rows ?? 24),
            ws_col: UInt16(clamping: size?.cols ?? 80),
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        guard openpty(&masterFD, &slaveFD, nil, nil, &windowSize) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        descriptor = masterFD
        master = FileHandle(fileDescriptor: masterFD, closeOnDealloc: true)
        stdinHandle = FileHandle(fileDescriptor: dup(slaveFD), closeOnDealloc: true)
        stdoutHandle = FileHandle(fileDescriptor: dup(slaveFD), closeOnDealloc: true)
        stderrHandle = FileHandle(fileDescriptor: dup(slaveFD), closeOnDealloc: true)
        close(slaveFD)
    }

    deinit {
        closeMaster()
    }

    func write(_ data: Data) throws {
        guard !data.isEmpty else {
            return
        }
        do {
            try master.write(contentsOf: data)
        } catch {
            throw AppServerError.invalidRequest("stdin is already closed")
        }
    }

    func closeStdin() throws {
        try write(Data([4]))
    }

    func resize(_ size: AppServerTerminalSize) throws {
        var windowSize = winsize(
            ws_row: UInt16(clamping: size.rows),
            ws_col: UInt16(clamping: size.cols),
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        if ioctl(descriptor, TIOCSWINSZ, &windowSize) != 0 {
            throw AppServerError.invalidRequest("failed to resize PTY: \(String(cString: strerror(errno)))")
        }
    }

    func closeSlaveHandles() {
        try? stdinHandle.close()
        try? stdoutHandle.close()
        try? stderrHandle.close()
    }

    func closeMaster() {
        let shouldClose = lock.withLock {
            guard !closed else {
                return false
            }
            closed = true
            return true
        }
        if shouldClose {
            try? master.close()
        }
    }
}

private enum AppServerProcessInput {
    case pipe(Pipe)
    case pseudoTerminal(AppServerPseudoTerminal)
}

private final class AppServerCommandExecProcess: @unchecked Sendable {
    private let params: AppServerCommandExecParams
    private let requestID: Any
    private let notificationSink: AppServerNotificationSink?
    private let onExit: @Sendable (String) -> Void
    private let lock = NSLock()
    private let process = Process()
    private let exitSignal = AppServerProcessExitSignal()
    private var stdinPipe: Pipe?
    private var pseudoTerminal: AppServerPseudoTerminal?
    private var stdinClosed = false
    private var terminated = false
    private var timedOut = false

    init(
        params: AppServerCommandExecParams,
        requestID: Any,
        cwd: URL,
        sandboxConfiguration: AppServerCommandExecSandboxConfiguration,
        environment: [String: String],
        notificationSink: AppServerNotificationSink?,
        onExit: @escaping @Sendable (String) -> Void
    ) throws {
        self.params = params
        self.requestID = requestID
        self.notificationSink = notificationSink
        self.onExit = onExit
        let environment = CodexAppServer.commandExecEnvironment(
            base: environment,
            overrides: params.environmentOverrides
        )
        let launch = try CodexAppServer.sandboxedLaunch(
            command: params.command,
            sandboxConfiguration: sandboxConfiguration,
            environment: environment
        )
        if launch.command[0].contains("/") {
            process.executableURL = URL(fileURLWithPath: launch.command[0])
            process.arguments = Array(launch.command.dropFirst())
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = launch.command
        }
        process.currentDirectoryURL = cwd
        process.environment = launch.environment
    }

    deinit {
        terminate()
    }

    func start() throws {
        let stdout = Pipe()
        let stderr = Pipe()
        process.terminationHandler = { [exitSignal] _ in
            exitSignal.signal()
        }
        if params.tty {
            let pty = try AppServerPseudoTerminal(size: params.size)
            pseudoTerminal = pty
            process.standardInput = pty.stdinHandle
            process.standardOutput = pty.stdoutHandle
            process.standardError = pty.stderrHandle
            try process.run()
            Task.detached { [self] in
                await finish(stdout: pty.master, stderr: nil)
            }
            return
        }
        if params.streamStdin {
            let stdin = Pipe()
            stdinPipe = stdin
            process.standardInput = stdin
        }
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        Task.detached { [self] in
            await finish(stdout: stdout, stderr: stderr)
        }
    }

    func writeStdin(delta: Data, closeStdin: Bool) throws {
        let stdin = try lock.withLock { () throws -> AppServerProcessInput in
            guard !stdinClosed else {
                throw AppServerError.invalidRequest("stdin is already closed")
            }
            if let pseudoTerminal {
                return .pseudoTerminal(pseudoTerminal)
            }
            guard let stdinPipe else {
                throw AppServerError.invalidRequest("stdin streaming is not enabled for this command/exec")
            }
            return .pipe(stdinPipe)
        }
        if case let .pseudoTerminal(pty) = stdin {
            if !delta.isEmpty {
                try pty.write(delta)
            }
            if closeStdin {
                lock.withLock {
                    stdinClosed = true
                }
                try pty.closeStdin()
            }
            return
        }
        guard case let .pipe(stdinPipe) = stdin else {
            return
        }
        if !delta.isEmpty {
            do {
                try stdinPipe.fileHandleForWriting.write(contentsOf: delta)
            } catch {
                throw AppServerError.invalidRequest("stdin is already closed")
            }
        }
        if closeStdin {
            lock.withLock {
                stdinClosed = true
            }
            do {
                try stdinPipe.fileHandleForWriting.close()
            } catch {
                stdinPipe.fileHandleForWriting.closeFile()
            }
        }
    }

    func resizePty(size: AppServerTerminalSize) throws {
        guard let pseudoTerminal else {
            throw AppServerError.invalidRequest("failed to resize PTY: process is not attached to a PTY")
        }
        try pseudoTerminal.resize(size)
    }

    func terminate() {
        let shouldTerminate = lock.withLock {
            guard !terminated else {
                return false
            }
            terminated = true
            stdinClosed = true
            return process.isRunning
        }
        try? stdinPipe?.fileHandleForWriting.close()
        if shouldTerminate {
            process.terminate()
        }
    }

    private func finish(stdout: Pipe, stderr: Pipe) async {
        await finish(stdout: stdout.fileHandleForReading, stderr: stderr.fileHandleForReading)
    }

    private func finish(stdout: FileHandle, stderr: FileHandle?) async {
        let streamOutput = params.streamStdoutStderr || params.tty
        let stdoutTask = Task.detached { [self] in
            await collectOutput(stdout, stream: "stdout", streamOutput: streamOutput)
        }
        let stderrTask = stderr.map { handle in
            Task.detached { [self] in
                await collectOutput(handle, stream: "stderr", streamOutput: streamOutput)
            }
        }
        if let timeoutMs = params.timeoutMs {
            let deadline = Date().addingTimeInterval(TimeInterval(timeoutMs) / 1000)
            while process.isRunning && Date() < deadline {
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            if process.isRunning {
                lock.withLock {
                    timedOut = true
                }
                terminate()
            }
        }
        await exitSignal.wait()
        pseudoTerminal?.closeSlaveHandles()
        let stdoutCapture = await stdoutTask.value
        let stderrCapture = await stderrTask?.value ?? AppServerProcessOutputCapture(text: "", capReached: false)
        await sendResponse(stdout: stdoutCapture, stderr: stderrCapture)
        if let processID = params.processID {
            onExit(processID)
        }
    }

    private func sendOutputDelta(stream: String, data: Data, capReached: Bool) async {
        guard let processID = params.processID,
              (!data.isEmpty || capReached)
        else {
            return
        }
        await sendEnvelope([
            "method": "command/exec/outputDelta",
            "params": [
                "processId": processID,
                "stream": stream,
                "deltaBase64": data.base64EncodedString(),
                "capReached": capReached
            ]
        ])
    }

    private func sendResponse(stdout: AppServerProcessOutputCapture, stderr: AppServerProcessOutputCapture) async {
        await sendEnvelope(CodexAppServer.responseObject(
            id: requestID,
            result: [
                "exitCode": lock.withLock { timedOut } ? 124 : Int(process.terminationStatus),
                "stdout": (params.streamStdoutStderr || params.tty) ? "" : stdout.text,
                "stderr": (params.streamStdoutStderr || params.tty) ? "" : stderr.text
            ]
        ))
    }

    private func sendEnvelope(_ envelope: [String: Any]) async {
        guard let notificationSink,
              let data = CodexAppServer.encodeMessages([envelope])
        else {
            return
        }
        await notificationSink(data)
    }

    private func collectOutput(
        _ handle: FileHandle,
        stream: String,
        streamOutput: Bool
    ) async -> AppServerProcessOutputCapture {
        var data = Data()
        var observedBytes = 0
        var capReached = false
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = Darwin.read(handle.fileDescriptor, &buffer, buffer.count)
            if count > 0 {
                let allowedCount: Int
                if let outputBytesCap = params.outputBytesCap {
                    allowedCount = min(max(outputBytesCap - observedBytes, 0), count)
                    observedBytes += allowedCount
                    capReached = observedBytes == outputBytesCap
                } else {
                    allowedCount = count
                }
                let chunk = Data(buffer.prefix(allowedCount))
                if streamOutput {
                    await sendOutputDelta(stream: stream, data: chunk, capReached: capReached)
                } else {
                    data.append(chunk)
                }
                if capReached {
                    break
                }
            } else if count == -1 && errno == EINTR {
                continue
            } else {
                break
            }
        }
        return AppServerProcessOutputCapture(
            text: TextEncoding.bytesToStringSmart(data),
            capReached: capReached
        )
    }
}

private final class AppServerCommandExecRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var activeProcesses: [String: AppServerCommandExecProcess] = [:]

    func contains(_ processID: String) -> Bool {
        lock.withLock { activeProcesses[processID] != nil }
    }

    func insert(_ process: AppServerCommandExecProcess, processID: String) {
        lock.withLock {
            activeProcesses[processID] = process
        }
    }

    func get(_ processID: String) -> AppServerCommandExecProcess? {
        lock.withLock {
            activeProcesses[processID]
        }
    }

    func remove(_ processID: String) -> AppServerCommandExecProcess? {
        lock.withLock {
            activeProcesses.removeValue(forKey: processID)
        }
    }

    func terminateAll() {
        let processes = lock.withLock {
            let processes = Array(activeProcesses.values)
            activeProcesses.removeAll()
            return processes
        }
        for process in processes {
            process.terminate()
        }
    }
}

private final class AppServerSpawnedProcess: @unchecked Sendable {
    private let params: AppServerProcessSpawnParams
    private let notificationSink: AppServerNotificationSink?
    private let onExit: @Sendable (String) -> Void
    private let lock = NSLock()
    private let process = Process()
    private let exitSignal = AppServerProcessExitSignal()
    private var stdinPipe: Pipe?
    private var pseudoTerminal: AppServerPseudoTerminal?
    private var stdinClosed = false
    private var terminated = false
    private var timedOut = false

    init(
        params: AppServerProcessSpawnParams,
        environment: [String: String],
        notificationSink: AppServerNotificationSink?,
        onExit: @escaping @Sendable (String) -> Void
    ) {
        self.params = params
        self.notificationSink = notificationSink
        self.onExit = onExit
        if params.command[0].contains("/") {
            process.executableURL = URL(fileURLWithPath: params.command[0])
            process.arguments = Array(params.command.dropFirst())
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = params.command
        }
        process.currentDirectoryURL = URL(fileURLWithPath: params.cwd, isDirectory: true)
        process.environment = CodexAppServer.processSpawnEnvironment(
            base: environment,
            overrides: params.environmentOverrides
        )
    }

    deinit {
        terminate()
    }

    func start() throws {
        let stdout = Pipe()
        let stderr = Pipe()
        process.terminationHandler = { [exitSignal] _ in
            exitSignal.signal()
        }
        if params.tty {
            let pty = try AppServerPseudoTerminal(size: params.size)
            pseudoTerminal = pty
            process.standardInput = pty.stdinHandle
            process.standardOutput = pty.stdoutHandle
            process.standardError = pty.stderrHandle
            try process.run()
            Task.detached { [self] in
                await finish(stdout: pty.master, stderr: nil)
            }
            return
        }
        if params.streamStdin {
            let stdin = Pipe()
            stdinPipe = stdin
            process.standardInput = stdin
        }
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        Task.detached { [self] in
            await finish(stdout: stdout, stderr: stderr)
        }
    }

    func writeStdin(delta: Data, closeStdin: Bool) throws {
        let stdin = try lock.withLock { () throws -> AppServerProcessInput in
            guard !stdinClosed else {
                throw AppServerError.invalidRequest("stdin is already closed")
            }
            if let pseudoTerminal {
                return .pseudoTerminal(pseudoTerminal)
            }
            guard let stdinPipe else {
                throw AppServerError.invalidRequest("stdin streaming is not enabled for this process")
            }
            return .pipe(stdinPipe)
        }
        if case let .pseudoTerminal(pty) = stdin {
            if !delta.isEmpty {
                try pty.write(delta)
            }
            if closeStdin {
                lock.withLock {
                    stdinClosed = true
                }
                try pty.closeStdin()
            }
            return
        }
        guard case let .pipe(stdinPipe) = stdin else {
            return
        }
        if !delta.isEmpty {
            do {
                try stdinPipe.fileHandleForWriting.write(contentsOf: delta)
            } catch {
                throw AppServerError.invalidRequest("stdin is already closed")
            }
        }
        if closeStdin {
            lock.withLock {
                stdinClosed = true
            }
            do {
                try stdinPipe.fileHandleForWriting.close()
            } catch {
                stdinPipe.fileHandleForWriting.closeFile()
            }
        }
    }

    func resizePty(size: AppServerTerminalSize) throws {
        guard let pseudoTerminal else {
            throw AppServerError.invalidRequest("failed to resize PTY: process is not attached to a PTY")
        }
        try pseudoTerminal.resize(size)
    }

    func terminate() {
        let shouldTerminate = lock.withLock {
            guard !terminated else {
                return false
            }
            terminated = true
            stdinClosed = true
            return process.isRunning
        }
        try? stdinPipe?.fileHandleForWriting.close()
        if shouldTerminate {
            process.terminate()
        }
    }

    private func finish(stdout: Pipe, stderr: Pipe) async {
        await finish(stdout: stdout.fileHandleForReading, stderr: stderr.fileHandleForReading)
    }

    private func finish(stdout: FileHandle, stderr: FileHandle?) async {
        let streamOutput = params.streamStdoutStderr || params.tty
        let stdoutTask = Task.detached { [self] in
            await collectOutput(stdout, stream: "stdout", streamOutput: streamOutput)
        }
        let stderrTask = stderr.map { handle in
            Task.detached { [self] in
                await collectOutput(handle, stream: "stderr", streamOutput: streamOutput)
            }
        }
        if let timeoutMs = params.timeoutMs {
            let deadline = Date().addingTimeInterval(TimeInterval(timeoutMs) / 1000)
            while process.isRunning && Date() < deadline {
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            if process.isRunning {
                lock.withLock {
                    timedOut = true
                }
                terminate()
            }
        }
        await exitSignal.wait()
        pseudoTerminal?.closeSlaveHandles()
        let stdoutCapture = await stdoutTask.value
        let stderrCapture = await stderrTask?.value ?? AppServerProcessOutputCapture(text: "", capReached: false)
        await sendExited(stdout: stdoutCapture, stderr: stderrCapture)
        onExit(params.processHandle)
    }

    private func sendOutputDelta(stream: String, data: Data, capReached: Bool) async {
        guard !data.isEmpty || capReached else {
            return
        }
        await sendNotification([
            "method": "process/outputDelta",
            "params": [
                "processHandle": params.processHandle,
                "stream": stream,
                "deltaBase64": data.base64EncodedString(),
                "capReached": capReached
            ]
        ])
    }

    private func sendExited(stdout: AppServerProcessOutputCapture, stderr: AppServerProcessOutputCapture) async {
        await sendNotification([
            "method": "process/exited",
            "params": [
                "processHandle": params.processHandle,
                "exitCode": lock.withLock { timedOut } ? 124 : Int(process.terminationStatus),
                "stdout": (params.streamStdoutStderr || params.tty) ? "" : stdout.text,
                "stdoutCapReached": stdout.capReached,
                "stderr": (params.streamStdoutStderr || params.tty) ? "" : stderr.text,
                "stderrCapReached": stderr.capReached
            ]
        ])
    }

    private func sendNotification(_ notification: [String: Any]) async {
        guard let notificationSink,
              let data = CodexAppServer.encodeMessages([notification])
        else {
            return
        }
        await notificationSink(data)
    }

    private func collectOutput(
        _ handle: FileHandle,
        stream: String,
        streamOutput: Bool
    ) async -> AppServerProcessOutputCapture {
        var data = Data()
        var observedBytes = 0
        var capReached = false
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = Darwin.read(handle.fileDescriptor, &buffer, buffer.count)
            if count > 0 {
                let allowedCount: Int
                if let outputBytesCap = params.outputBytesCap {
                    allowedCount = min(max(outputBytesCap - observedBytes, 0), count)
                    observedBytes += allowedCount
                    capReached = observedBytes == outputBytesCap
                } else {
                    allowedCount = count
                }
                let chunk = Data(buffer.prefix(allowedCount))
                if streamOutput {
                    await sendOutputDelta(stream: stream, data: chunk, capReached: capReached)
                } else {
                    data.append(chunk)
                }
                if capReached {
                    break
                }
            } else if count == -1 && errno == EINTR {
                continue
            } else {
                break
            }
        }
        return AppServerProcessOutputCapture(
            text: TextEncoding.bytesToStringSmart(data),
            capReached: capReached
        )
    }
}

private final class AppServerProcessRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var activeProcesses: [String: AppServerSpawnedProcess] = [:]

    func contains(_ processHandle: String) -> Bool {
        lock.withLock { activeProcesses[processHandle] != nil }
    }

    func insert(_ process: AppServerSpawnedProcess, processHandle: String) {
        lock.withLock {
            activeProcesses[processHandle] = process
        }
    }

    func remove(_ processHandle: String) -> AppServerSpawnedProcess? {
        lock.withLock {
            activeProcesses.removeValue(forKey: processHandle)
        }
    }

    func get(_ processHandle: String) -> AppServerSpawnedProcess? {
        lock.withLock {
            activeProcesses[processHandle]
        }
    }

    func terminateAll() {
        let processes = lock.withLock {
            let processes = Array(activeProcesses.values)
            activeProcesses.removeAll()
            return processes
        }
        for process in processes {
            process.terminate()
        }
    }
}

private final class AppServerChatGPTLoginRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var servers: [UUID: ChatGPTLoginServer] = [:]

    func replaceAll(with id: UUID, server: ChatGPTLoginServer) {
        let previous = lock.withLock {
            let previous = Array(servers.values)
            servers = [id: server]
            return previous
        }
        for server in previous {
            server.cancel()
        }
    }

    func remove(_ id: UUID) -> ChatGPTLoginServer? {
        lock.withLock {
            servers.removeValue(forKey: id)
        }
    }

    func cancelAll() {
        let previous = lock.withLock {
            let previous = Array(servers.values)
            servers.removeAll()
            return previous
        }
        for server in previous {
            server.cancel()
        }
    }
}

private final class AppServerCancellableLoginRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [UUID: Task<Void, Never>] = [:]

    func replaceAll(with id: UUID, task: Task<Void, Never>) {
        let previous = lock.withLock {
            let previous = Array(tasks.values)
            tasks = [id: task]
            return previous
        }
        for task in previous {
            task.cancel()
        }
    }

    func remove(_ id: UUID) -> Task<Void, Never>? {
        lock.withLock {
            tasks.removeValue(forKey: id)
        }
    }

    func cancelAll() {
        let previous = lock.withLock {
            let previous = Array(tasks.values)
            tasks.removeAll()
            return previous
        }
        for task in previous {
            task.cancel()
        }
    }
}

final class CodexAppServerMessageProcessor {
    private struct ThreadAnalyticsMetadata {
        let modelSlug: String
        let cwd: URL
        let approvalPolicy: AskForApproval?
    }

    private struct FeaturedPluginIDsCache {
        let key: String
        let ids: [String]
    }

    private let connectionID: AppServerConnectionID = 0
    private var initialized = false
    private var requestAttestation = false
    private var experimentalAPIEnabled = false
    private var userAgent: String
    private let configuration: CodexAppServerConfiguration
    private let notificationSink: AppServerNotificationSink?
    private let acceptedLineAnalyticsClient: AcceptedLineAnalyticsClient
    private let threadStateManager: AppServerThreadStateManager
    private let outgoingRequestBroker: AppServerOutgoingRequestBroker
    private var threadAnalyticsMetadata: [String: ThreadAnalyticsMetadata] = [:]
    private let activeChatGPTLogins = AppServerChatGPTLoginRegistry()
    private let activeDeviceCodeLogins = AppServerCancellableLoginRegistry()
    private var runtimeFeatureEnablement: [String: Bool] = [:]
    private var loadedThreadAppsFeatureEnabled: [String: Bool] = [:]
    private var cachedAppList: [[String: Any]]?
    private var lastGlobalAppListRefreshFailed = false
    private var featuredPluginIDsCache: FeaturedPluginIDsCache?
    private var fsWatches: [String: AppServerFSWatch] = [:]
    private var fuzzyFileSearchSessions: [String: [String]] = [:]
    private var activeTurnIDs: [String: String] = [:]
    private var runtimeTurnStartedAt: [String: [String: Int64]] = [:]
    private var runtimeTurnErrors: [String: [String: [String: Any]]] = [:]
    private var runtimePendingApprovalCounts: [String: Int] = [:]
    private var runtimePendingUserInputCounts: [String: Int] = [:]
    private var runtimeCommandExecutionStarted: [String: Set<String>] = [:]
    private var pendingSessionStartSources: [String: HookSessionStartSource] = [:]
    private var ephemeralThreadIDs: Set<String> = []
    private var ephemeralThreadSnapshots: [String: [String: Any]] = [:]
    private var optOutNotificationMethods: Set<String> = []
    private let activeCommandExecs = AppServerCommandExecRegistry()
    private let activeProcesses = AppServerProcessRegistry()

    init(
        configuration: CodexAppServerConfiguration,
        notificationSink: AppServerNotificationSink? = nil,
        threadStateManager: AppServerThreadStateManager = AppServerThreadStateManager(),
        outgoingRequestBroker: AppServerOutgoingRequestBroker? = nil
    ) {
        self.configuration = configuration
        self.notificationSink = notificationSink
        self.acceptedLineAnalyticsClient = AcceptedLineAnalyticsClient(
            uploader: configuration.acceptedLineAnalyticsUploader
        )
        self.threadStateManager = threadStateManager
        self.outgoingRequestBroker = outgoingRequestBroker ?? AppServerOutgoingRequestBroker(notificationSink: notificationSink)
        self.userAgent = CodexAppServer.buildUserAgent(configuration: configuration, params: nil)
    }

    deinit {
        activeChatGPTLogins.cancelAll()
        activeDeviceCodeLogins.cancelAll()
        for watch in fsWatches.values {
            watch.cancel()
        }
        activeCommandExecs.terminateAll()
        activeProcesses.terminateAll()
    }

    func attestationProvider(
        timeoutNanoseconds: UInt64 = AppServerAttestationProvider.defaultTimeoutNanoseconds
    ) -> any AttestationProvider {
        AppServerAttestationProvider(
            outgoing: outgoingRequestBroker,
            threadStateManager: threadStateManager,
            timeoutNanoseconds: timeoutNanoseconds
        )
    }

    private func markCurrentConnectionInitialized(
        requestAttestation: Bool,
        optOutNotificationMethods: Set<String>
    ) {
        let manager = threadStateManager
        let connectionID = connectionID
        _ = try? CodexAppServer.runAsyncBlocking {
            await manager.connectionInitialized(
                connectionID,
                capabilities: AppServerConnectionCapabilities(
                    requestAttestation: requestAttestation,
                    optOutNotificationMethods: optOutNotificationMethods
                )
            )
        }
    }

    private func threadStatusChangedNotification(threadID: String, status: [String: Any]) -> [String: Any]? {
        guard !optOutNotificationMethods.contains("thread/status/changed") else {
            return nil
        }
        return CodexAppServer.threadStatusChangedNotification(threadID: threadID, status: status)
    }

    private func subscribeCurrentConnection(toThreadID threadID: String) {
        rememberLoadedThreadFeatureState(threadID: threadID)
        let manager = threadStateManager
        let connectionID = connectionID
        _ = try? CodexAppServer.runAsyncBlocking {
            await manager.tryAddConnectionToThread(threadID: threadID, connectionID: connectionID)
        }
    }

    private func unsubscribeCurrentConnection(fromThreadID threadID: String) -> Bool {
        let manager = threadStateManager
        let connectionID = connectionID
        return (try? CodexAppServer.runAsyncBlocking {
            await manager.unsubscribeConnectionFromThread(threadID: threadID, connectionID: connectionID)
        }) ?? false
    }

    private func isThreadLoaded(_ threadID: String) -> Bool {
        let manager = threadStateManager
        return (try? CodexAppServer.runAsyncBlocking {
            await manager.isThreadLoaded(threadID)
        }) ?? false
    }

    private func rejectMetadataUpdateForLoadedEphemeralThread(params: [String: Any]?) throws {
        guard let threadID = CodexAppServer.stringParam(params?["threadId"]),
              ephemeralThreadIDs.contains(threadID),
              isThreadLoaded(threadID)
        else {
            return
        }
        throw AppServerError.invalidRequest("ephemeral thread does not support metadata updates: \(threadID)")
    }

    private func loadedEphemeralThreadIDs() -> Set<String> {
        Set(ephemeralThreadIDs.filter { isThreadLoaded($0) })
    }

    private func loadedEphemeralThreadSnapshot(threadID: String) -> [String: Any]? {
        guard ephemeralThreadIDs.contains(threadID), isThreadLoaded(threadID) else {
            return nil
        }
        return ephemeralThreadSnapshots[threadID]
    }

    private func rememberThreadAnalyticsMetadata(threadID: String, result: [String: Any]) {
        guard let modelSlug = CodexAppServer.stringParam(result["model"]),
              let cwd = CodexAppServer.stringParam(result["cwd"])
        else {
            return
        }
        threadAnalyticsMetadata[threadID] = ThreadAnalyticsMetadata(
            modelSlug: modelSlug,
            cwd: URL(fileURLWithPath: cwd, isDirectory: true),
            approvalPolicy: (result["approvalPolicy"] as? String).flatMap(AskForApproval.init(rawValue:))
        )
    }

    private func rememberLoadedThreadFeatureState(threadID: String) {
        loadedThreadAppsFeatureEnabled[threadID] = (try? CodexAppServer.appsFeatureEnabledInCurrentConfig(
            configuration: configuration,
            runtimeFeatureEnablement: runtimeFeatureEnablement
        )) ?? false
    }

    private func appsFeatureEnabledForLoadedThread(_ threadID: String) throws -> Bool {
        guard let enabled = loadedThreadAppsFeatureEnabled[threadID],
              isThreadLoaded(threadID)
        else {
            throw AppServerError.invalidRequest("thread not found: \(threadID)")
        }
        return enabled
    }

    private func appListResult(params: [String: Any]?) throws -> [String: Any] {
        let forceRefetch = CodexAppServer.boolParam(params?["forceRefetch"], defaultValue: false)
        let isThreadScoped = CodexAppServer.stringParam(params?["threadId"]) != nil
        let cachedApps = !forceRefetch && !isThreadScoped && lastGlobalAppListRefreshFailed ? cachedAppList : nil
        do {
            let result = try CodexAppServer.appListResult(
                params: params,
                configuration: configuration,
                runtimeFeatureEnablement: runtimeFeatureEnablement,
                loadedThreadAppsFeatureEnabled: { try self.appsFeatureEnabledForLoadedThread($0) },
                cachedApps: cachedApps,
                cacheAppList: { apps in
                    guard !isThreadScoped else {
                        return
                    }
                    self.cachedAppList = apps
                    self.lastGlobalAppListRefreshFailed = false
                }
            )
            return result
        } catch {
            if forceRefetch && !isThreadScoped {
                lastGlobalAppListRefreshFailed = true
            }
            throw error
        }
    }

    private func pluginListResult(params: [String: Any]?) throws -> [String: Any] {
        let cacheKey = featuredPluginIDsCacheKey()
        let cachedIDs = featuredPluginIDsCache.flatMap { $0.key == cacheKey ? $0.ids : nil }
        return try CodexAppServer.pluginListResult(
            params: params,
            configuration: configuration,
            cachedFeaturedPluginIDs: cachedIDs,
            cacheFeaturedPluginIDs: { ids in
                self.featuredPluginIDsCache = FeaturedPluginIDsCache(key: cacheKey, ids: ids)
            }
        )
    }

    private func featuredPluginIDsCacheKey() -> String {
        let runtimeConfig = try? CodexConfigLoader.load(
            codexHome: configuration.codexHome,
            systemConfigFile: nil,
            environment: configuration.environment
        )
        let baseURL = runtimeConfig?.chatgptBaseURL ?? CodexConfigDefaults.chatgptBaseURL
        guard let auth = try? CodexAppServer.currentAuth(configuration: configuration),
              case let .chatGPT(idToken) = auth.kind
        else {
            return "\(baseURL)|no-auth"
        }
        let workspace: Bool
        if case let .known(plan)? = idToken.chatGPTPlanType {
            workspace = plan.isWorkspaceAccount
        } else {
            workspace = false
        }
        return "\(baseURL)|\(auth.accountID ?? "")|\(idToken.email ?? "")|\(workspace)"
    }

    private func trackResolvedTurnForAnalytics(threadID: String, turn: [String: Any]) {
        guard let turnID = CodexAppServer.stringParam(turn["id"]),
              let metadata = threadAnalyticsMetadata[threadID]
        else {
            return
        }
        let client = acceptedLineAnalyticsClient
        _ = try? CodexAppServer.runAsyncBlocking {
            await client.trackResolvedTurn(
                turnID: turnID,
                threadID: threadID,
                modelSlug: metadata.modelSlug,
                cwd: metadata.cwd
            )
        }
    }

    private func trackTurnCompletedForAnalytics(turnID: String) {
        let client = acceptedLineAnalyticsClient
        _ = try? CodexAppServer.runAsyncBlocking {
            await client.trackTurnCompleted(turnID: turnID)
        }
    }

    func handleRuntimeEvent(threadID: String, turnID: String, event: EventMessage) async {
        let notifications: [[String: Any]]
        switch event {
        case let .taskStarted(event):
            let runtimeTurnID = event.turnID
            activeTurnIDs[threadID] = runtimeTurnID
            if let startedAt = event.startedAt {
                runtimeTurnStartedAt[threadID, default: [:]][runtimeTurnID] = startedAt
            }
            runtimeTurnErrors[threadID]?[runtimeTurnID] = nil
            notifications = [
                threadStatusChangedNotification(
                    threadID: threadID,
                    status: CodexAppServer.activeThreadStatus()
                ),
                CodexAppServer.turnStartedNotification(
                    threadID: threadID,
                    event: event,
                    fallbackTurnID: turnID
                )
            ].compactMap(\.self)
        case let .taskComplete(event):
            let runtimeTurnID = event.turnID
            let startedAt = runtimeTurnStartedAt[threadID]?[runtimeTurnID]
            let error = runtimeTurnErrors[threadID]?[runtimeTurnID]
            runtimeTurnStartedAt[threadID]?[runtimeTurnID] = nil
            runtimeTurnErrors[threadID]?[runtimeTurnID] = nil
            clearRuntimePendingActiveFlags(threadID: threadID)
            if activeTurnIDs[threadID] == runtimeTurnID {
                activeTurnIDs[threadID] = nil
            }
            notifications = [
                threadStatusChangedNotification(
                    threadID: threadID,
                    status: CodexAppServer.idleThreadStatus()
                ),
                CodexAppServer.turnCompletedNotification(
                    threadID: threadID,
                    event: event,
                    fallbackTurnID: turnID,
                    startedAt: startedAt,
                    error: error
                )
            ].compactMap(\.self)
            trackTurnCompletedForAnalytics(turnID: runtimeTurnID)
        case let .turnAborted(event):
            let runtimeTurnID = event.turnID ?? turnID
            let startedAt = runtimeTurnStartedAt[threadID]?[runtimeTurnID]
            runtimeTurnStartedAt[threadID]?[runtimeTurnID] = nil
            runtimeTurnErrors[threadID]?[runtimeTurnID] = nil
            clearRuntimePendingActiveFlags(threadID: threadID)
            if activeTurnIDs[threadID] == runtimeTurnID {
                activeTurnIDs[threadID] = nil
            }
            notifications = [
                threadStatusChangedNotification(
                    threadID: threadID,
                    status: CodexAppServer.idleThreadStatus()
                ),
                CodexAppServer.turnAbortedNotification(
                    threadID: threadID,
                    event: event,
                    fallbackTurnID: turnID,
                    startedAt: startedAt
                )
            ].compactMap(\.self)
            trackTurnCompletedForAnalytics(turnID: runtimeTurnID)
        case let .error(event):
            var projected = CodexAppServer.runtimeEventNotifications(
                threadID: threadID,
                turnID: turnID,
                event: .error(event)
            )
            if let notification = threadStatusChangedNotification(
                threadID: threadID,
                status: CodexAppServer.systemErrorThreadStatus()
            ) {
                projected.insert(notification, at: 0)
            }
            clearRuntimePendingActiveFlags(threadID: threadID)
            if event.affectsTurnStatus {
                runtimeTurnErrors[threadID, default: [:]][turnID] = CodexAppServer.turnErrorObject(
                    message: event.message,
                    codexErrorInfo: event.codexErrorInfo,
                    additionalDetails: nil
                )
            }
            notifications = projected
        case .applyPatchApprovalRequest, .execApprovalRequest, .elicitationRequest, .requestPermissions:
            notifications = [
                markRuntimeApprovalRequested(threadID: threadID)
            ].compactMap(\.self)
        case .requestUserInput:
            notifications = [
                markRuntimeUserInputRequested(threadID: threadID)
            ].compactMap(\.self)
        case let .execCommandBegin(event):
            guard event.source != .unifiedExecInteraction else {
                notifications = []
                break
            }
            var started = runtimeCommandExecutionStarted[threadID, default: []]
            let inserted = started.insert(event.callID).inserted
            runtimeCommandExecutionStarted[threadID] = started
            if inserted {
                notifications = [
                    CodexAppServer.commandExecutionStartedNotification(
                        threadID: threadID,
                        turnID: turnID,
                        event: event
                    )
                ]
            } else {
                notifications = []
            }
        case let .execCommandEnd(event):
            if event.source == .unifiedExecInteraction {
                notifications = []
                break
            }
            runtimeCommandExecutionStarted[threadID]?.remove(event.callID)
            if runtimeCommandExecutionStarted[threadID]?.isEmpty == true {
                runtimeCommandExecutionStarted[threadID] = nil
            }
            notifications = [
                CodexAppServer.commandExecutionCompletedNotification(
                    threadID: threadID,
                    turnID: turnID,
                    event: event
                )
            ]
        default:
            notifications = CodexAppServer.runtimeEventNotifications(
                threadID: threadID,
                turnID: turnID,
                event: event
            )
        }
        guard !notifications.isEmpty else {
            return
        }
        if case let .turnDiff(turnDiff) = event {
            await acceptedLineAnalyticsClient.trackTurnDiff(
                threadID: threadID,
                turnID: turnID,
                unifiedDiff: turnDiff.unifiedDiff
            )
        }
        for notification in notifications {
            await sendNotification(notification)
        }
    }

    private func markRuntimeApprovalRequested(threadID: String) -> [String: Any]? {
        let previousFlags = runtimeActiveFlags(threadID: threadID)
        runtimePendingApprovalCounts[threadID, default: 0] += 1
        return runtimeActiveStatusNotificationIfChanged(threadID: threadID, previousFlags: previousFlags)
    }

    private func markRuntimeUserInputRequested(threadID: String) -> [String: Any]? {
        let previousFlags = runtimeActiveFlags(threadID: threadID)
        runtimePendingUserInputCounts[threadID, default: 0] += 1
        return runtimeActiveStatusNotificationIfChanged(threadID: threadID, previousFlags: previousFlags)
    }

    private func runtimeActiveStatusNotificationIfChanged(
        threadID: String,
        previousFlags: [String]
    ) -> [String: Any]? {
        let flags = runtimeActiveFlags(threadID: threadID)
        guard flags != previousFlags else {
            return nil
        }
        return threadStatusChangedNotification(
            threadID: threadID,
            status: CodexAppServer.activeThreadStatus(activeFlags: flags)
        )
    }

    private func runtimeActiveFlags(threadID: String) -> [String] {
        var flags: [String] = []
        if (runtimePendingApprovalCounts[threadID] ?? 0) > 0 {
            flags.append("waitingOnApproval")
        }
        if (runtimePendingUserInputCounts[threadID] ?? 0) > 0 {
            flags.append("waitingOnUserInput")
        }
        return flags
    }

    private func clearRuntimePendingActiveFlags(threadID: String) {
        runtimePendingApprovalCounts.removeValue(forKey: threadID)
        runtimePendingUserInputCounts.removeValue(forKey: threadID)
    }

    private func sendNotification(_ notification: [String: Any]) async {
        guard let notificationSink,
              let data = CodexAppServer.encodeMessages([notification])
        else {
            return
        }
        await notificationSink(data)
    }

    private func incrementOutOfBandElicitationCount(threadID: String) throws -> AppServerElicitationCounterResult {
        let manager = threadStateManager
        return try CodexAppServer.runAsyncBlocking {
            await manager.incrementOutOfBandElicitationCount(threadID: threadID)
        }
    }

    private func decrementOutOfBandElicitationCount(threadID: String) throws -> AppServerElicitationCounterResult {
        let manager = threadStateManager
        return try CodexAppServer.runAsyncBlocking {
            await manager.decrementOutOfBandElicitationCount(threadID: threadID)
        }
    }

    private func listLoadedThreadIDs() -> [String] {
        let manager = threadStateManager
        return (try? CodexAppServer.runAsyncBlocking {
            await manager.listLoadedThreadIDs()
        }) ?? []
    }

    private func queueMcpServerRefresh(threadID: String, config: McpServerRefreshConfig) throws {
        let manager = threadStateManager
        let queued = try CodexAppServer.runAsyncBlocking {
            await manager.queueMcpServerRefresh(threadID: threadID, config: config)
        }
        if !queued {
            throw AppServerError.invalidRequest("thread not found: \(threadID)")
        }
    }

    private func queueBestEffortMcpServerRefresh() {
        Self.queueBestEffortMcpServerRefresh(
            configuration: configuration,
            threadStateManager: threadStateManager
        )
    }

    private static func queueBestEffortMcpServerRefresh(
        configuration: CodexAppServerConfiguration,
        threadStateManager: AppServerThreadStateManager
    ) {
        let threadIDs = (try? CodexAppServer.runAsyncBlocking {
            await threadStateManager.listLoadedThreadIDs()
        }) ?? []
        guard !threadIDs.isEmpty else {
            return
        }
        let runtimeConfig: CodexRuntimeConfig
        do {
            runtimeConfig = try CodexConfigLoader.load(
                codexHome: configuration.codexHome,
                cwd: configuration.cwd,
                overrides: configuration.cliConfigOverrides,
                managedConfigOverrides: configuration.configLayerOverrides,
                environment: configuration.environment
            )
        } catch {
            return
        }
        let refreshConfig = CodexAppServer.mcpServerRefreshConfig(runtimeConfig: runtimeConfig)
        for threadID in threadIDs {
            _ = try? CodexAppServer.runAsyncBlocking {
                await threadStateManager.queueMcpServerRefresh(threadID: threadID, config: refreshConfig)
            }
        }
    }

    func pendingMcpServerRefreshConfig(threadID: String) throws -> McpServerRefreshConfig? {
        let manager = threadStateManager
        return try CodexAppServer.runAsyncBlocking {
            await manager.pendingMcpServerRefreshConfig(threadID: threadID)
        }
    }

    private func queueUserConfigRefresh(effectiveConfig: ConfigValue) throws {
        for threadID in listLoadedThreadIDs() {
            let manager = threadStateManager
            let queued = try CodexAppServer.runAsyncBlocking {
                await manager.queueUserConfigRefresh(threadID: threadID, effectiveConfig: effectiveConfig)
            }
            if !queued {
                throw AppServerError.invalidRequest("thread not found: \(threadID)")
            }
        }
    }

    func pendingUserConfigRefresh(threadID: String) throws -> ConfigValue? {
        let manager = threadStateManager
        return try CodexAppServer.runAsyncBlocking {
            await manager.pendingUserConfigRefresh(threadID: threadID)
        }
    }

    private func accountRateLimitsResult() throws -> [String: Any] {
        try CodexAppServer.accountRateLimitsResult(
            configuration: configuration,
            retryAfterUnauthorized: refreshExternalAuthAfterUnauthorized
        )
    }

    private func sendAddCreditsNudgeEmailResult(params: [String: Any]?) throws -> [String: Any] {
        try CodexAppServer.sendAddCreditsNudgeEmailResult(
            params: params,
            configuration: configuration,
            retryAfterUnauthorized: refreshExternalAuthAfterUnauthorized
        )
    }

    private func refreshExternalAuthAfterUnauthorized(previousAuth: AppServerAuth) throws -> AppServerAuth {
        guard previousAuth.method == "chatgptAuthTokens" else {
            return previousAuth
        }
        let broker = outgoingRequestBroker
        let result = try CodexAppServer.runAsyncBlocking {
            await broker.requestChatGPTAuthTokensRefresh(
                previousAccountID: previousAuth.accountID,
                timeoutNanoseconds: 30_000_000_000
            )
        }

        let response: AppServerProtocol.ChatGPTAuthTokensRefreshResponse
        switch result {
        case let .success(success):
            response = success
        case .timeout:
            throw AppServerError.internalError("auth refresh request timed out after 30s")
        case let .requestFailed(code, message):
            throw AppServerError.internalError(
                "auth refresh request failed: code=\(code.map(String.init) ?? "<missing>") message=\(message ?? "<missing>")"
            )
        case .requestCanceled:
            throw AppServerError.internalError("auth refresh request canceled")
        case .malformedResponse:
            throw AppServerError.internalError("auth refresh request returned malformed response")
        }

        if let forcedWorkspace = try CodexAppServer.forcedChatGPTWorkspaceID(configuration: configuration),
           response.chatGPTAccountID != forcedWorkspace {
            throw AppServerError.invalidRequest(
                "External auth must use workspace \(forcedWorkspace), but received \"\(response.chatGPTAccountID)\"."
            )
        }

        do {
            try CodexAuthStorage.saveChatGPTAuthTokens(
                codexHome: configuration.codexHome,
                accessToken: response.accessToken,
                chatGPTAccountID: response.chatGPTAccountID,
                chatGPTPlanType: response.chatGPTPlanType,
                mode: .ephemeral
            )
        } catch {
            throw AppServerError.internalError("failed to set external auth: \(error)")
        }
        guard let refreshed = try CodexAppServer.currentAuth(configuration: configuration) else {
            throw AppServerError.internalError("failed to read refreshed external auth")
        }
        return refreshed
    }

    private func receiveClientResponseIfPresent(_ object: [String: Any]) -> Bool {
        guard let rawID = object["id"],
              let requestID = AppServerRequestIDCodec.requestID(from: rawID)
        else {
            return false
        }

        let broker = outgoingRequestBroker
        if let result = object["result"] {
            if JSONSerialization.isValidJSONObject(result),
               let resultData = try? JSONSerialization.data(withJSONObject: result) {
                _ = try? CodexAppServer.runAsyncBlocking {
                    await broker.receiveResponse(id: requestID, resultData: resultData)
                }
            } else {
                _ = try? CodexAppServer.runAsyncBlocking {
                    await broker.receiveMalformedResponse(id: requestID)
                }
            }
            return true
        }
        if let error = object["error"] as? [String: Any] {
            let code = (error["code"] as? NSNumber)?.int64Value
            let message = error["message"] as? String
            _ = try? CodexAppServer.runAsyncBlocking {
                await broker.receiveError(id: requestID, code: code, message: message)
            }
            return true
        }
        if object["method"] as? String == Attestation.generateMethod,
           let response = object["response"] {
            if JSONSerialization.isValidJSONObject(response),
               let responseData = try? JSONSerialization.data(withJSONObject: response) {
                _ = try? CodexAppServer.runAsyncBlocking {
                    await broker.receiveResponse(id: requestID, resultData: responseData)
                }
            } else {
                _ = try? CodexAppServer.runAsyncBlocking {
                    await broker.receiveMalformedResponse(id: requestID)
                }
            }
            return true
        }
        return false
    }

    private func startChatGptLogin(
        codexStreamlinedLogin: Bool = false,
        emitAccountNotifications: Bool = false
    ) throws -> (loginID: UUID, authURL: String) {
        if try CodexAppServer.externalChatGPTAuthActive(configuration: configuration) {
            throw CodexAppServer.externalAuthActiveError()
        }
        if try CodexAppServer.forcedLoginMethod(configuration: configuration) == "api" {
            throw AppServerError.invalidRequest("ChatGPT login is disabled. Use API key login instead.")
        }
        let runtimeConfig = try CodexConfigLoader.load(codexHome: configuration.codexHome)
        let server: ChatGPTLoginServer
        do {
            server = try ChatGPTLoginServer.start(options: ChatGPTLoginOptions(
                codexHome: configuration.codexHome,
                openBrowser: false,
                forcedChatGPTWorkspaceID: runtimeConfig.forcedChatGPTWorkspaceID,
                authCredentialsStoreMode: configuration.authCredentialsStoreMode,
                originator: configuration.originator,
                codexStreamlinedLogin: codexStreamlinedLogin
            ),
                transport: configuration.authLoginTransport
            )
        } catch {
            throw AppServerError.internalError("failed to start login server: \(error)")
        }
        activeDeviceCodeLogins.cancelAll()
        let loginID = UUID()
        activeChatGPTLogins.replaceAll(with: loginID, server: server)
        if emitAccountNotifications {
            let serverConfiguration = configuration
            let notificationSink = notificationSink
            let registry = activeChatGPTLogins
            let threadStateManager = threadStateManager
            Task {
                let (success, error) = await CodexAppServerMessageProcessor.waitForChatGPTLoginCompletion(server: server)
                await CodexAppServer.sendAccountLoginCompletedNotification(
                    loginID: loginID.uuidString.lowercased(),
                    success: success,
                    error: error,
                    notificationSink: notificationSink
                )
                if success {
                    CodexAppServerMessageProcessor.queueBestEffortMcpServerRefresh(
                        configuration: serverConfiguration,
                        threadStateManager: threadStateManager
                    )
                    await CodexAppServer.sendAccountUpdatedNotification(
                        configuration: serverConfiguration,
                        notificationSink: notificationSink
                    )
                }
                _ = registry.remove(loginID)
            }
        }
        return (loginID, server.authURL)
    }

    private static func waitForChatGPTLoginCompletion(server: ChatGPTLoginServer) async -> (success: Bool, error: String?) {
        enum Completion {
            case done(Result<Void, Error>)
            case timeout
        }
        return await withTaskGroup(of: Completion.self, returning: (Bool, String?).self) { group in
            group.addTask {
                do {
                    try await server.waitUntilDone()
                    return .done(.success(()))
                } catch {
                    return .done(.failure(error))
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 600_000_000_000)
                return .timeout
            }

            guard let completion = await group.next() else {
                group.cancelAll()
                return (false, "Login server error: Login was not completed")
            }
            switch completion {
            case .done(.success):
                group.cancelAll()
                return (true, nil)
            case let .done(.failure(error)):
                group.cancelAll()
                return (false, "Login server error: \(String(describing: error))")
            case .timeout:
                server.cancel()
                group.cancelAll()
                return (false, "Login timed out")
            }
        }
    }

    private func chatGPTDeviceCodeLoginOptions() throws -> ChatGPTDeviceCodeLoginOptions {
        if try CodexAppServer.externalChatGPTAuthActive(configuration: configuration) {
            throw CodexAppServer.externalAuthActiveError()
        }
        if try CodexAppServer.forcedLoginMethod(configuration: configuration) == "api" {
            throw AppServerError.invalidRequest("ChatGPT login is disabled. Use API key login instead.")
        }
        let issuerOverride = configuration.environment["CODEX_APP_SERVER_LOGIN_ISSUER"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ChatGPTDeviceCodeLoginOptions(
            codexHome: configuration.codexHome,
            issuer: issuerOverride.flatMap { $0.isEmpty ? nil : $0 } ?? ChatGPTDeviceCodeLogin.defaultIssuer,
            forcedChatGPTWorkspaceID: try CodexAppServer.forcedChatGPTWorkspaceID(configuration: configuration),
            authCredentialsStoreMode: configuration.authCredentialsStoreMode,
            cliVersion: configuration.version
        )
    }

    private func loginChatGptDeviceCodeAccountResult() throws -> [String: Any] {
        let options = try chatGPTDeviceCodeLoginOptions()
        let deviceCodeTransport = configuration.authDeviceCodeTransport
        let deviceCode: ChatGPTDeviceCodeStart
        do {
            deviceCode = try CodexAppServer.runAsyncBlocking {
                try await ChatGPTDeviceCodeLogin.requestDeviceCode(
                    options: options,
                    transport: deviceCodeTransport
                )
            }
        } catch let error as ChatGPTDeviceCodeLoginError {
            switch error {
            case .requestFailed:
                let message = String(describing: error)
                if message.contains("device code login is not enabled") {
                    throw AppServerError.invalidRequest(message)
                }
                throw AppServerError.internalError("failed to request device code: \(message)")
            case .invalidURL, .workspaceRestricted:
                throw AppServerError.internalError("failed to request device code: \(error)")
            }
        } catch {
            throw AppServerError.internalError("failed to request device code: \(error)")
        }

        activeChatGPTLogins.cancelAll()

        let loginID = UUID()
        let loginIDString = loginID.uuidString.lowercased()
        let serverConfiguration = configuration
        let notificationSink = notificationSink
        let registry = activeDeviceCodeLogins
        let threadStateManager = threadStateManager
        let task = Task {
            let success: Bool
            let error: String?
            do {
                try await ChatGPTDeviceCodeLogin.complete(
                    options: options,
                    deviceCode: deviceCode,
                    transport: deviceCodeTransport
                )
                success = true
                error = nil
            } catch let completionError {
                success = false
                error = Task.isCancelled ? "Login was not completed" : String(describing: completionError)
            }

            await CodexAppServer.sendAccountLoginCompletedNotification(
                loginID: loginIDString,
                success: success,
                error: error,
                notificationSink: notificationSink
            )
            if success {
                CodexAppServerMessageProcessor.queueBestEffortMcpServerRefresh(
                    configuration: serverConfiguration,
                    threadStateManager: threadStateManager
                )
                await CodexAppServer.sendAccountUpdatedNotification(
                    configuration: serverConfiguration,
                    notificationSink: notificationSink
                )
            }
            _ = registry.remove(loginID)
        }
        activeDeviceCodeLogins.replaceAll(with: loginID, task: task)

        return [
            "type": "chatgptDeviceCode",
            "loginId": loginIDString,
            "verificationUrl": deviceCode.verificationURL,
            "userCode": deviceCode.userCode
        ]
    }

    private func loginChatGptResult() throws -> [String: Any] {
        let started = try startChatGptLogin()
        return [
            "loginId": started.loginID.uuidString.lowercased(),
            "authUrl": started.authURL
        ]
    }

    private func loginChatGptAccountResult(params: [String: Any]?) throws -> [String: Any] {
        let started = try startChatGptLogin(
            codexStreamlinedLogin: CodexAppServer.boolParam(
                params?["codexStreamlinedLogin"],
                defaultValue: false
            ),
            emitAccountNotifications: true
        )
        return [
            "type": "chatgpt",
            "loginId": started.loginID.uuidString.lowercased(),
            "authUrl": started.authURL
        ]
    }

    private func cancelLoginChatGptResult(params: [String: Any]?) throws -> [String: Any] {
        guard let loginIDString = CodexAppServer.stringParam(params?["loginId"]) else {
            throw AppServerError.invalidRequest("missing loginId")
        }
        guard let loginID = UUID(uuidString: loginIDString) else {
            throw AppServerError.invalidRequest("invalid login id: \(loginIDString)")
        }
        guard let server = activeChatGPTLogins.remove(loginID) else {
            throw AppServerError.invalidRequest("login id not found: \(loginIDString)")
        }
        server.cancel()
        return [:]
    }

    private func cancelActiveAccountLogins() {
        activeChatGPTLogins.cancelAll()
        activeDeviceCodeLogins.cancelAll()
    }

    private func cancelLoginAccountResult(params: [String: Any]?) throws -> [String: Any] {
        guard let loginIDString = CodexAppServer.stringParam(params?["loginId"]) else {
            throw AppServerError.invalidRequest("missing loginId")
        }
        guard let loginID = UUID(uuidString: loginIDString) else {
            throw AppServerError.invalidRequest("invalid login id: \(loginIDString)")
        }
        if let server = activeChatGPTLogins.remove(loginID) {
            server.cancel()
            return ["status": "canceled"]
        }
        if let task = activeDeviceCodeLogins.remove(loginID) {
            task.cancel()
            return ["status": "canceled"]
        }
        return ["status": "notFound"]
    }

    private func fsWatchResult(params: [String: Any]?) throws -> [String: Any] {
        let parsed = try CodexAppServer.fsWatchParams(params)
        guard fsWatches[parsed.watchID] == nil else {
            throw AppServerError.invalidRequest("watchId already exists: \(parsed.watchID)")
        }
        let watch = AppServerFSWatch(
            watchID: parsed.watchID,
            path: parsed.path,
            notificationSink: notificationSink
        )
        fsWatches[parsed.watchID] = watch
        watch.start()
        return [
            "path": parsed.path
        ]
    }

    private func fsUnwatchResult(params: [String: Any]?) throws -> [String: Any] {
        let watchID = try CodexAppServer.fsUnwatchParams(params)
        if let watch = fsWatches.removeValue(forKey: watchID) {
            watch.cancel()
        }
        return [:]
    }

    private func commandExecResult(id: Any, params: [String: Any]?) throws -> [String: Any]? {
        try CodexAppServer.requireCommandExecPermissionProfileExperimentalAPI(
            params: params,
            experimentalAPIEnabled: experimentalAPIEnabled
        )
        let parsed = try CodexAppServer.commandExecParams(params: params)
        guard let processID = parsed.processID else {
            return CodexAppServer.responseObject(
                id: id,
                result: try CodexAppServer.commandExecResult(params: params, configuration: configuration)
            )
        }
        if activeCommandExecs.contains(processID) {
            throw AppServerError.invalidRequest("duplicate active command/exec process id: \"\(processID)\"")
        }
        let runtimeConfig = try CodexConfigLoader.load(
            codexHome: configuration.codexHome,
            cwd: configuration.cwd,
            managedConfigOverrides: configuration.configLayerOverrides,
            environment: configuration.environment
        )
        let commandCwd = CodexAppServer.commandExecCwd(parsed.cwd, configuration: configuration)
        let sandbox = try CodexAppServer.commandExecSandboxConfiguration(
            parsed: parsed,
            runtimeConfig: runtimeConfig,
            commandCwd: commandCwd,
            configuration: configuration
        )
        let registry = activeCommandExecs
        let session = try AppServerCommandExecProcess(
            params: parsed,
            requestID: id,
            cwd: commandCwd,
            sandboxConfiguration: sandbox,
            environment: ExecEnvironment.createEnv(
                policy: runtimeConfig.shellEnvironmentPolicy,
                environment: configuration.environment
            ),
            notificationSink: notificationSink,
            onExit: { processID in
                _ = registry.remove(processID)
            }
        )
        activeCommandExecs.insert(session, processID: processID)
        do {
            try session.start()
        } catch {
            _ = activeCommandExecs.remove(processID)
            throw AppServerError.internalError("failed to spawn command: \(error)")
        }
        return nil
    }

    private func commandExecWriteResult(params: [String: Any]?) throws -> [String: Any] {
        let parsed = try CodexAppServer.commandExecWriteParams(params: params)
        guard let session = activeCommandExecs.get(parsed.processID) else {
            throw AppServerError.invalidRequest("no active command/exec for process id \"\(parsed.processID)\"")
        }
        try session.writeStdin(delta: parsed.delta, closeStdin: parsed.closeStdin)
        return [:]
    }

    private func commandExecTerminateResult(params: [String: Any]?) throws -> [String: Any] {
        let processID = try CodexAppServer.commandExecProcessID(params: params)
        guard let session = activeCommandExecs.remove(processID) else {
            throw AppServerError.invalidRequest("no active command/exec for process id \"\(processID)\"")
        }
        session.terminate()
        return [:]
    }

    private func commandExecResizeResult(params: [String: Any]?) throws -> [String: Any] {
        let processID = try CodexAppServer.commandExecProcessID(params: params)
        let size = try CodexAppServer.commandExecResizeSize(params: params)
        guard let session = activeCommandExecs.get(processID) else {
            throw AppServerError.invalidRequest("no active command/exec for process id \"\(processID)\"")
        }
        try session.resizePty(size: size)
        return [:]
    }

    private func processSpawnResult(params: [String: Any]?) throws -> [String: Any] {
        let parsed = try CodexAppServer.processSpawnParams(params: params)
        if activeProcesses.contains(parsed.processHandle) {
            throw AppServerError.invalidRequest("duplicate active process handle: \"\(parsed.processHandle)\"")
        }
        let registry = activeProcesses
        let session = AppServerSpawnedProcess(
            params: parsed,
            environment: configuration.environment,
            notificationSink: notificationSink,
            onExit: { processHandle in
                _ = registry.remove(processHandle)
            }
        )
        activeProcesses.insert(session, processHandle: parsed.processHandle)
        do {
            try session.start()
        } catch {
            _ = activeProcesses.remove(parsed.processHandle)
            throw AppServerError.internalError("process/spawn failed: \(error)")
        }
        return [:]
    }

    private func processWriteStdinResult(params: [String: Any]?) throws -> [String: Any] {
        let parsed = try CodexAppServer.processWriteStdinParams(params: params)
        guard let session = activeProcesses.get(parsed.processHandle) else {
            throw AppServerError.invalidRequest("no active process for process handle \"\(parsed.processHandle)\"")
        }
        try session.writeStdin(delta: parsed.delta, closeStdin: parsed.closeStdin)
        return [:]
    }

    private func processResizePtyResult(params: [String: Any]?) throws -> [String: Any] {
        let processHandle = try CodexAppServer.processHandle(params: params)
        let size = try CodexAppServer.processResizePtySize(params: params)
        guard let session = activeProcesses.get(processHandle) else {
            throw AppServerError.invalidRequest("no active process for process handle \"\(processHandle)\"")
        }
        try session.resizePty(size: size)
        return [:]
    }

    private func processKillResult(params: [String: Any]?) throws -> [String: Any] {
        let processHandle = try CodexAppServer.processHandle(params: params)
        guard let session = activeProcesses.remove(processHandle) else {
            throw AppServerError.invalidRequest("no active process for process handle \"\(processHandle)\"")
        }
        session.terminate()
        return [:]
    }

    private func fuzzyFileSearchSessionStartResult(params: [String: Any]?) throws -> [String: Any] {
        guard let sessionID = CodexAppServer.stringParam(params?["sessionId"]) else {
            throw AppServerError.invalidRequest("missing sessionId")
        }
        guard !sessionID.isEmpty else {
            throw AppServerError.invalidRequest("sessionId must not be empty")
        }
        fuzzyFileSearchSessions[sessionID] = (params?["roots"] as? [String]) ?? []
        return [:]
    }

    private func fuzzyFileSearchSessionUpdateResult(params: [String: Any]?) throws -> ([String: Any], [[String: Any]]) {
        guard let sessionID = CodexAppServer.stringParam(params?["sessionId"]) else {
            throw AppServerError.invalidRequest("missing sessionId")
        }
        guard let roots = fuzzyFileSearchSessions[sessionID] else {
            throw AppServerError.invalidRequest("fuzzy file search session not found: \(sessionID)")
        }
        guard let query = CodexAppServer.stringParam(params?["query"]) else {
            throw AppServerError.invalidRequest("missing query")
        }
        let files: [[String: Any]]
        if query.isEmpty {
            files = []
        } else {
            files = roots.flatMap { root in
                CodexAppServer.fuzzyFileSearch(query: query, root: root)
                    .prefix(CodexAppServer.fuzzyFileSearchLimitPerRoot)
            }
            .sorted { lhs, rhs in
                let lhsScore = lhs["score"] as? Int ?? 0
                let rhsScore = rhs["score"] as? Int ?? 0
                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }
                return (lhs["path"] as? String ?? "") < (rhs["path"] as? String ?? "")
            }
        }
        return (
            [:],
            [
                [
                    "method": "fuzzyFileSearch/sessionUpdated",
                    "params": [
                        "sessionId": sessionID,
                        "query": query,
                        "files": files
                    ]
                ],
                [
                    "method": "fuzzyFileSearch/sessionCompleted",
                    "params": [
                        "sessionId": sessionID
                    ]
                ]
            ]
        )
    }

    private func fuzzyFileSearchSessionStopResult(params: [String: Any]?) throws -> [String: Any] {
        guard let sessionID = CodexAppServer.stringParam(params?["sessionId"]) else {
            throw AppServerError.invalidRequest("missing sessionId")
        }
        fuzzyFileSearchSessions.removeValue(forKey: sessionID)
        return [:]
    }

    func processLine(_ data: Data) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if receiveClientResponseIfPresent(object) {
            return nil
        }
        guard let id = object["id"],
              let method = object["method"] as? String
        else {
            return nil
        }

        let params = object["params"] as? [String: Any]
        var response: [String: Any]?
        var notifications: [[String: Any]] = []
        if method == "initialize" {
            if initialized {
                response = CodexAppServer.errorObject(id: id, code: -32600, message: "Already initialized")
            } else {
                if let clientName = ((params?["clientInfo"] as? [String: Any])?["name"] as? String),
                   !CodexAppServer.isValidHTTPHeaderValue(clientName) {
                    response = CodexAppServer.errorObject(
                        id: id,
                        code: -32600,
                        message: "Invalid clientInfo.name: '\(clientName)'. Must be a valid HTTP header value."
                    )
                    return CodexAppServer.encodeMessages(response.map { [$0] } ?? [])
                }
                initialized = true
                let capabilities = params?["capabilities"] as? [String: Any]
                requestAttestation = (capabilities?["requestAttestation"] as? Bool) ?? false
                experimentalAPIEnabled = (capabilities?["experimentalApi"] as? Bool) ?? false
                optOutNotificationMethods = Set((capabilities?["optOutNotificationMethods"] as? [String]) ?? [])
                markCurrentConnectionInitialized(
                    requestAttestation: requestAttestation,
                    optOutNotificationMethods: optOutNotificationMethods
                )
                userAgent = CodexAppServer.buildUserAgent(configuration: configuration, params: params)
                response = CodexAppServer.responseObject(id: id, result: [
                    "userAgent": userAgent,
                    "codexHome": configuration.codexHome.standardizedFileURL.path,
                    "platformFamily": CodexAppServer.platformFamily,
                    "platformOs": CodexAppServer.platformOS
                ])
            }
        } else if !initialized {
            response = CodexAppServer.errorObject(id: id, code: -32600, message: "Not initialized")
        } else {
            do {
                switch method {
                case "newConversation":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.newConversationResult(params: params, configuration: configuration)
                    )
                case "thread/start":
                    try CodexAppServer.requireThreadStartExperimentalFieldsAPI(
                        params: params,
                        experimentalAPIEnabled: experimentalAPIEnabled
                    )
                    try CodexAppServer.requireThreadStartContextOverrideCompatibility(params: params)
                    if try CodexAppServer.rustDefaultBoolParam(params?["persistExtendedHistory"], defaultValue: false) {
                        notifications.append(CodexAppServer.persistExtendedHistoryDeprecationNoticeNotification())
                    }
                    let outcome = try CodexAppServer.threadStartResult(params: params, configuration: configuration)
                    let result = outcome.result
                    response = CodexAppServer.responseObject(id: id, result: result)
                    if let thread = result["thread"] as? [String: Any] {
                        if let threadID = thread["id"] as? String {
                            pendingSessionStartSources[threadID] = outcome.sessionStartSource
                            if (thread["ephemeral"] as? Bool) == true {
                                ephemeralThreadIDs.insert(threadID)
                                ephemeralThreadSnapshots[threadID] = thread
                            }
                            rememberThreadAnalyticsMetadata(threadID: threadID, result: result)
                            subscribeCurrentConnection(toThreadID: threadID)
                        }
                        notifications.append(CodexAppServer.threadStartedNotification(thread: thread))
                    }
                case "thread/list":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.threadListResult(params: params, configuration: configuration)
                    )
                case "thread/loaded/list":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.threadLoadedListResult(
                            params: params,
                            loadedThreadIDs: { listLoadedThreadIDs() }
                        )
                    )
                case "thread/read":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.threadReadResult(
                            params: params,
                            configuration: configuration,
                            loadedEphemeralThread: { self.loadedEphemeralThreadSnapshot(threadID: $0) }
                        )
                    )
                case "thread/unsubscribe":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.threadUnsubscribeResult(
                            params: params,
                            isLoaded: { isThreadLoaded($0) },
                            unsubscribe: { unsubscribeCurrentConnection(fromThreadID: $0) }
                        )
                    )
                case "thread/increment_elicitation":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.threadElicitationCounterResult(
                            method: "thread/increment_elicitation",
                            params: params,
                            experimentalAPIEnabled: experimentalAPIEnabled,
                            update: { try incrementOutOfBandElicitationCount(threadID: $0) }
                        )
                    )
                case "thread/decrement_elicitation":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.threadElicitationCounterResult(
                            method: "thread/decrement_elicitation",
                            params: params,
                            experimentalAPIEnabled: experimentalAPIEnabled,
                            update: { try decrementOutOfBandElicitationCount(threadID: $0) }
                        )
                    )
                case "thread/turns/list":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.threadTurnsListResult(
                            params: params,
                            configuration: configuration,
                            experimentalAPIEnabled: experimentalAPIEnabled
                        )
                    )
                case "thread/turns/items/list":
                    try CodexAppServer.requireExperimentalAPI(
                        method: "thread/turns/items/list",
                        experimentalAPIEnabled: experimentalAPIEnabled
                    )
                    response = CodexAppServer.errorObject(
                        id: id,
                        code: -32601,
                        message: "thread/turns/items/list is not supported yet"
                    )
                case "thread/resume":
                    try CodexAppServer.requireThreadResumeExperimentalFieldsAPI(
                        params: params,
                        experimentalAPIEnabled: experimentalAPIEnabled
                    )
                    try CodexAppServer.requireThreadContextOverrideCompatibility(params: params)
                    if try CodexAppServer.rustDefaultBoolParam(params?["persistExtendedHistory"], defaultValue: false) {
                        notifications.append(CodexAppServer.persistExtendedHistoryDeprecationNoticeNotification())
                    }
                    let result = try CodexAppServer.threadResumeResult(params: params, configuration: configuration)
                    response = CodexAppServer.responseObject(id: id, result: result)
                    if let thread = result["thread"] as? [String: Any],
                       let threadID = thread["id"] as? String {
                        pendingSessionStartSources[threadID] = .resume
                        rememberThreadAnalyticsMetadata(threadID: threadID, result: result)
                        subscribeCurrentConnection(toThreadID: threadID)
                        if let notification = CodexAppServer.threadGoalResumeSnapshotNotification(
                            threadID: threadID,
                            configuration: configuration
                        ) {
                            notifications.append(notification)
                        }
                    }
                case "thread/fork":
                    try CodexAppServer.requireThreadForkExperimentalFieldsAPI(
                        params: params,
                        experimentalAPIEnabled: experimentalAPIEnabled
                    )
                    try CodexAppServer.requireThreadContextOverrideCompatibility(params: params)
                    if try CodexAppServer.rustDefaultBoolParam(params?["persistExtendedHistory"], defaultValue: false) {
                        notifications.append(CodexAppServer.persistExtendedHistoryDeprecationNoticeNotification())
                    }
                    let result = try CodexAppServer.threadForkResult(params: params, configuration: configuration)
                    response = CodexAppServer.responseObject(id: id, result: result)
                    if let thread = result["thread"] as? [String: Any] {
                        if let threadID = thread["id"] as? String {
                            pendingSessionStartSources[threadID] = .startup
                            rememberThreadAnalyticsMetadata(threadID: threadID, result: result)
                            subscribeCurrentConnection(toThreadID: threadID)
                        }
                        var notificationThread = thread
                        notificationThread["turns"] = []
                        notifications.append(CodexAppServer.threadStartedNotification(thread: notificationThread))
                    }
                case "turn/start":
                    try CodexAppServer.requireTurnStartExperimentalFieldsAPI(
                        params: params,
                        experimentalAPIEnabled: experimentalAPIEnabled
                    )
                    try CodexAppServer.requireTurnStartContextOverrideCompatibility(params: params)
                    let pendingSessionStartSource = (params?["threadId"] as? String)
                        .flatMap { pendingSessionStartSources[$0] }
                    let loadedThreadMetadata = (params?["threadId"] as? String)
                        .flatMap { threadAnalyticsMetadata[$0] }
                    let outcome = try CodexAppServer.turnStartResult(
                        params: params,
                        configuration: configuration,
                        pendingSessionStartSource: pendingSessionStartSource,
                        loadedThreadModel: loadedThreadMetadata?.modelSlug,
                        loadedThreadApprovalPolicy: loadedThreadMetadata?.approvalPolicy
                    )
                    let result = outcome.result
                    response = CodexAppServer.responseObject(id: id, result: result)
                    if let threadID = params?["threadId"] as? String,
                       let turn = result["turn"] as? [String: Any] {
                        pendingSessionStartSources.removeValue(forKey: threadID)
                        if let turnID = turn["id"] as? String {
                            activeTurnIDs[threadID] = turnID
                        }
                        trackResolvedTurnForAnalytics(threadID: threadID, turn: turn)
                        notifications.append(contentsOf: outcome.hookStartedEvents.map {
                            CodexAppServer.hookStartedNotification(threadID: threadID, event: $0)
                        })
                        notifications.append(contentsOf: outcome.hookCompletedEvents.map {
                            CodexAppServer.hookCompletedNotification(threadID: threadID, event: $0)
                        })
                        notifications.append(CodexAppServer.turnStartedNotification(threadID: threadID, turn: turn))
                        if let notification = threadStatusChangedNotification(
                            threadID: threadID,
                            status: CodexAppServer.activeThreadStatus()
                        ) {
                            notifications.append(notification)
                        }
                    }
                case "turn/steer":
                    try CodexAppServer.requireTurnSteerResponsesAPIMetadataExperimentalAPI(
                        params: params,
                        experimentalAPIEnabled: experimentalAPIEnabled
                    )
                    let threadID = CodexAppServer.stringParam(params?["threadId"])
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.turnSteerResult(
                            params: params,
                            configuration: configuration,
                            activeTurnID: threadID.flatMap { activeTurnIDs[$0] }
                        )
                    )
                case "turn/interrupt":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.turnInterruptResult(params: params, configuration: configuration)
                    )
                    if let threadID = params?["threadId"] as? String,
                       let turnID = params?["turnId"] as? String {
                        activeTurnIDs.removeValue(forKey: threadID)
                        notifications.append(CodexAppServer.turnCompletedNotification(
                            threadID: threadID,
                            turnID: turnID,
                            status: "interrupted"
                        ))
                        if let notification = threadStatusChangedNotification(
                            threadID: threadID,
                            status: CodexAppServer.idleThreadStatus()
                        ) {
                            notifications.append(notification)
                        }
                        trackTurnCompletedForAnalytics(turnID: turnID)
                    }
                case "review/start":
                    let outcome = try CodexAppServer.reviewStartResult(params: params, configuration: configuration)
                    response = CodexAppServer.responseObject(id: id, result: outcome.result)
                    if let thread = outcome.startedThread {
                        if let threadID = thread["id"] as? String {
                            subscribeCurrentConnection(toThreadID: threadID)
                        }
                        notifications.append(CodexAppServer.threadStartedNotification(thread: thread))
                    }
                    if let reviewThreadID = outcome.result["reviewThreadId"] as? String {
                        subscribeCurrentConnection(toThreadID: reviewThreadID)
                    }
                    if let reviewThreadID = outcome.result["reviewThreadId"] as? String,
                       let turn = outcome.result["turn"] as? [String: Any] {
                        notifications.append(CodexAppServer.turnStartedNotification(threadID: reviewThreadID, turn: turn))
                    }
                case "thread/archive":
                    let archive = try CodexAppServer.threadArchiveResult(params: params, configuration: configuration)
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: archive.result
                    )
                    for archivedThreadID in archive.archivedThreadIDs {
                        notifications.append(CodexAppServer.threadArchivedNotification(threadID: archivedThreadID))
                    }
                case "thread/unarchive":
                    let result = try CodexAppServer.threadUnarchiveResult(params: params, configuration: configuration)
                    response = CodexAppServer.responseObject(id: id, result: result)
                    if let thread = result["thread"] as? [String: Any],
                       let threadID = thread["id"] as? String {
                        notifications.append(CodexAppServer.threadUnarchivedNotification(threadID: threadID))
                    }
                case "thread/name/set":
                    let result = try CodexAppServer.threadSetNameResult(params: params, configuration: configuration)
                    response = CodexAppServer.responseObject(id: id, result: result.result)
                    notifications.append(CodexAppServer.threadNameUpdatedNotification(
                        threadID: result.threadID,
                        threadName: result.threadName
                    ))
                case "thread/metadata/update":
                    try rejectMetadataUpdateForLoadedEphemeralThread(params: params)
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.threadMetadataUpdateResult(params: params, configuration: configuration)
                    )
                case "thread/compact/start":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.threadCompactStartResult(params: params, configuration: configuration)
                    )
                case "thread/shellCommand":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.threadShellCommandResult(params: params, configuration: configuration)
                    )
                case "thread/approveGuardianDeniedAction":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.threadApproveGuardianDeniedActionResult(
                            params: params,
                            configuration: configuration
                        )
                    )
                case "thread/rollback":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.threadRollbackResult(params: params, configuration: configuration)
                    )
                case "thread/backgroundTerminals/clean":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.threadBackgroundTerminalsCleanResult(
                            params: params,
                            configuration: configuration,
                            experimentalAPIEnabled: experimentalAPIEnabled
                        )
                    )
                case "thread/goal/set":
                    let result = try CodexAppServer.threadGoalSetResult(
                        params: params,
                        configuration: configuration,
                        experimentalAPIEnabled: experimentalAPIEnabled,
                        loadedEphemeralThreadIDs: loadedEphemeralThreadIDs()
                    )
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: result.result
                    )
                    notifications.append(CodexAppServer.threadGoalUpdatedNotification(
                        threadID: result.threadID,
                        goal: result.goal
                    ))
                case "thread/goal/get":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.threadGoalGetResult(
                            params: params,
                            configuration: configuration,
                            experimentalAPIEnabled: experimentalAPIEnabled,
                            loadedEphemeralThreadIDs: loadedEphemeralThreadIDs()
                        )
                    )
                case "thread/goal/clear":
                    let result = try CodexAppServer.threadGoalClearResult(
                        params: params,
                        configuration: configuration,
                        experimentalAPIEnabled: experimentalAPIEnabled,
                        loadedEphemeralThreadIDs: loadedEphemeralThreadIDs()
                    )
                    response = CodexAppServer.responseObject(id: id, result: result.result)
                    if result.cleared {
                        notifications.append(CodexAppServer.threadGoalClearedNotification(threadID: result.threadID))
                    }
                case "thread/memoryMode/set":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.threadMemoryModeSetResult(
                            params: params,
                            configuration: configuration,
                            experimentalAPIEnabled: experimentalAPIEnabled
                        )
                    )
                case "memory/reset":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.memoryResetResult(
                            configuration: configuration,
                            experimentalAPIEnabled: experimentalAPIEnabled
                        )
                    )
                case "thread/inject_items":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.threadInjectItemsResult(params: params, configuration: configuration)
                    )
                case "fs/readFile":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.fsReadFileResult(params: params)
                    )
                case "fs/writeFile":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.fsWriteFileResult(params: params)
                    )
                case "fs/createDirectory":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.fsCreateDirectoryResult(params: params)
                    )
                case "fs/getMetadata":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.fsGetMetadataResult(params: params)
                    )
                case "fs/readDirectory":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.fsReadDirectoryResult(params: params)
                    )
                case "fs/remove":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.fsRemoveResult(params: params)
                    )
                case "fs/copy":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.fsCopyResult(params: params)
                    )
                case "fs/watch":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try fsWatchResult(params: params)
                    )
                case "fs/unwatch":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try fsUnwatchResult(params: params)
                    )
                case "app/list":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try appListResult(params: params)
                    )
                case "plugin/list":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try pluginListResult(params: params)
                    )
                case "plugin/read":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.pluginReadResult(params: params, configuration: configuration)
                    )
                case "plugin/skill/read":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.pluginSkillReadResult(params: params, configuration: configuration)
                    )
                case "plugin/share/save":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.pluginShareSaveResult(params: params, configuration: configuration)
                    )
                case "plugin/share/updateTargets":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.pluginShareUpdateTargetsResult(params: params, configuration: configuration)
                    )
                case "plugin/share/list":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.pluginShareListResult(params: params, configuration: configuration)
                    )
                case "plugin/share/delete":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.pluginShareDeleteResult(params: params, configuration: configuration)
                    )
                case "plugin/install":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.pluginInstallResult(params: params, configuration: configuration)
                    )
                    queueBestEffortMcpServerRefresh()
                case "plugin/uninstall":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.pluginUninstallResult(params: params, configuration: configuration)
                    )
                    queueBestEffortMcpServerRefresh()
                case "marketplace/add":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.marketplaceAddResult(params: params, configuration: configuration)
                    )
                case "marketplace/remove":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.marketplaceRemoveResult(params: params, configuration: configuration)
                    )
                case "marketplace/upgrade":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.marketplaceUpgradeResult(params: params, configuration: configuration)
                    )
                case "listConversations":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.listConversationsResult(params: params, configuration: configuration)
                    )
                case "getConversationSummary":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.getConversationSummaryResult(params: params, configuration: configuration)
                    )
                case "resumeConversation":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.resumeConversationResult(params: params, configuration: configuration)
                    )
                case "archiveConversation":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.archiveConversationResult(params: params, configuration: configuration)
                    )
                case "sendUserMessage", "sendUserTurn":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.sendUserMessageResult(params: params, configuration: configuration)
                    )
                case "interruptConversation":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.interruptConversationResult(params: params, configuration: configuration)
                    )
                case "addConversationListener":
                    let result = CodexAppServer.addConversationListenerResult()
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: result
                    )
                    if let threadID = CodexAppServer.stringParam(params?["conversationId"])
                        ?? CodexAppServer.stringParam(params?["conversation_id"]) {
                        subscribeCurrentConnection(toThreadID: threadID)
                    }
                case "removeConversationListener":
                    response = CodexAppServer.responseObject(id: id, result: [:])
                case "getUserAgent":
                    response = CodexAppServer.responseObject(id: id, result: [
                        "userAgent": userAgent
                    ])
                case "getAuthStatus":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.authStatusResult(params: params, configuration: configuration)
                    )
                case "account/read":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.accountResult(params: params, configuration: configuration)
                    )
                case "account/rateLimits/read":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try accountRateLimitsResult()
                    )
                case "account/sendAddCreditsNudgeEmail":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try sendAddCreditsNudgeEmailResult(params: params)
                    )
                case "userInfo":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.userInfoResult(configuration: configuration)
                    )
                case "model/list":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.modelListResult(params: params, configuration: configuration)
                    )
                case "modelProvider/capabilities/read":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.modelProviderCapabilitiesReadResult(configuration: configuration)
                    )
                case "windowsSandbox/readiness":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: CodexAppServer.windowsSandboxReadinessResult()
                    )
                case "windowsSandbox/setupStart":
                    let result = try CodexAppServer.windowsSandboxSetupStartResult(params: params)
                    response = CodexAppServer.responseObject(id: id, result: result.result)
                    notifications.append(result.notification)
                case "mcpServerStatus/list":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.mcpServerStatusListResult(params: params, configuration: configuration)
                    )
                case "mcpServer/oauth/login":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.mcpServerOAuthLoginResult(
                            params: params,
                            configuration: configuration,
                            notificationSink: notificationSink
                        )
                    )
                case "config/mcpServer/reload":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.mcpServerRefreshResult(
                            rawParams: object["params"],
                            configuration: configuration,
                            loadedThreadIDs: { self.listLoadedThreadIDs() },
                            queueThreadRefresh: { try self.queueMcpServerRefresh(threadID: $0, config: $1) }
                        )
                    )
                case "mcpServer/resource/read":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.mcpResourceReadResult(params: params, configuration: configuration)
                    )
                case "mcpServer/tool/call":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.mcpServerToolCallResult(params: params, configuration: configuration)
                    )
                case "externalAgentConfig/detect":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.externalAgentConfigDetectResult(
                            params: params,
                            configuration: configuration
                        )
                    )
                case "externalAgentConfig/import":
                    let result = try CodexAppServer.externalAgentConfigImportResult(
                        params: params,
                        configuration: configuration
                    )
                    response = CodexAppServer.responseObject(id: id, result: result.result)
                    notifications.append(contentsOf: result.notifications)
                case "skills/list":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: CodexAppServer.skillsListResult(params: params, configuration: configuration)
                    )
                case "skills/config/write":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.skillsConfigWriteResult(params: params, configuration: configuration)
                    )
                case "hooks/list":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: CodexAppServer.hooksListResult(params: params, configuration: configuration)
                    )
                case "experimentalFeature/list":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.experimentalFeatureListResult(
                            params: params,
                            configuration: configuration,
                            runtimeFeatureEnablement: runtimeFeatureEnablement
                        )
                    )
                case "experimentalFeature/enablement/set":
                    let refreshAppList = ((params?["enablement"] as? [String: Any])?["apps"] as? Bool) == true
                    let shouldReloadUserConfig = ((params?["enablement"] as? [String: Any])?.isEmpty == false)
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.experimentalFeatureEnablementSetResult(
                            params: params,
                            runtimeFeatureEnablement: &runtimeFeatureEnablement
                        )
                    )
                    if shouldReloadUserConfig {
                        try queueUserConfigRefresh(effectiveConfig: CodexAppServer.effectiveConfigSnapshot(
                            configuration: configuration,
                            runtimeFeatureEnablement: runtimeFeatureEnablement
                        ))
                    }
                    if refreshAppList {
                        if let notification = try? CodexAppServer.appListUpdatedNotification(
                            configuration: configuration,
                            runtimeFeatureEnablement: runtimeFeatureEnablement
                        ) {
                            notifications.append(notification)
                        }
                    }
                case "collaborationMode/list":
                    try CodexAppServer.requireExperimentalAPI(
                        method: "collaborationMode/list",
                        experimentalAPIEnabled: experimentalAPIEnabled
                    )
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: CodexAppServer.collaborationModeListResult()
                    )
                case "thread/realtime/listVoices":
                    try CodexAppServer.requireExperimentalAPI(
                        method: "thread/realtime/listVoices",
                        experimentalAPIEnabled: experimentalAPIEnabled
                    )
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: CodexAppServer.realtimeListVoicesResult()
                    )
                case "thread/realtime/start",
                     "thread/realtime/appendAudio",
                     "thread/realtime/appendText",
                     "thread/realtime/stop":
                    try CodexAppServer.requireExperimentalAPI(
                        method: method,
                        experimentalAPIEnabled: experimentalAPIEnabled
                    )
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.realtimeControlResult(
                            method: method,
                            params: params,
                            configuration: configuration,
                            runtimeFeatureEnablement: runtimeFeatureEnablement
                        )
                    )
                case "mock/experimentalMethod":
                    try CodexAppServer.requireExperimentalAPI(
                        method: "mock/experimentalMethod",
                        experimentalAPIEnabled: experimentalAPIEnabled
                    )
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: CodexAppServer.mockExperimentalMethodResult(params: params)
                    )
                case "config/read":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.configReadResult(
                            params: params,
                            configuration: configuration,
                            runtimeFeatureEnablement: runtimeFeatureEnablement
                        )
                    )
                case "configRequirements/read":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.configRequirementsReadResult(configuration: configuration)
                    )
                case "config/value/write":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.configValueWriteResult(params: params, configuration: configuration)
                    )
                case "config/batchWrite":
                    let reloadUserConfig = CodexAppServer.boolParam(params?["reloadUserConfig"], defaultValue: false)
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.configBatchWriteResult(params: params, configuration: configuration)
                    )
                    if reloadUserConfig {
                        try queueUserConfigRefresh(effectiveConfig: CodexAppServer.effectiveConfigSnapshot(
                            configuration: configuration,
                            runtimeFeatureEnablement: runtimeFeatureEnablement
                        ))
                    }
                case "getUserSavedConfig":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.userSavedConfigResult(configuration: configuration)
                    )
                case "gitDiffToRemote":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.gitDiffToRemoteResult(params: params)
                    )
                case "fuzzyFileSearch":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.fuzzyFileSearchResult(params: params)
                    )
                case "fuzzyFileSearch/sessionStart":
                    try CodexAppServer.requireExperimentalAPI(
                        method: "fuzzyFileSearch/sessionStart",
                        experimentalAPIEnabled: experimentalAPIEnabled
                    )
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try fuzzyFileSearchSessionStartResult(params: params)
                    )
                case "fuzzyFileSearch/sessionUpdate":
                    try CodexAppServer.requireExperimentalAPI(
                        method: "fuzzyFileSearch/sessionUpdate",
                        experimentalAPIEnabled: experimentalAPIEnabled
                    )
                    let result = try fuzzyFileSearchSessionUpdateResult(params: params)
                    response = CodexAppServer.responseObject(id: id, result: result.0)
                    notifications.append(contentsOf: result.1)
                case "fuzzyFileSearch/sessionStop":
                    try CodexAppServer.requireExperimentalAPI(
                        method: "fuzzyFileSearch/sessionStop",
                        experimentalAPIEnabled: experimentalAPIEnabled
                    )
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try fuzzyFileSearchSessionStopResult(params: params)
                    )
                case "command/exec", "execOneOffCommand":
                    if method == "command/exec" {
                        response = try commandExecResult(id: id, params: params)
                    } else {
                        response = CodexAppServer.responseObject(
                            id: id,
                            result: try CodexAppServer.commandExecResult(
                                params: params,
                                configuration: configuration
                            )
                        )
                    }
                case "command/exec/write":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try commandExecWriteResult(params: params)
                    )
                case "command/exec/resize":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try commandExecResizeResult(params: params)
                    )
                case "command/exec/terminate":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try commandExecTerminateResult(params: params)
                    )
                case "process/spawn":
                    try CodexAppServer.requireExperimentalAPI(
                        method: "process/spawn",
                        experimentalAPIEnabled: experimentalAPIEnabled
                    )
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try processSpawnResult(params: params)
                    )
                case "process/writeStdin":
                    try CodexAppServer.requireExperimentalAPI(
                        method: "process/writeStdin",
                        experimentalAPIEnabled: experimentalAPIEnabled
                    )
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try processWriteStdinResult(params: params)
                    )
                case "process/resizePty":
                    try CodexAppServer.requireExperimentalAPI(
                        method: "process/resizePty",
                        experimentalAPIEnabled: experimentalAPIEnabled
                    )
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try processResizePtyResult(params: params)
                    )
                case "process/kill":
                    try CodexAppServer.requireExperimentalAPI(
                        method: "process/kill",
                        experimentalAPIEnabled: experimentalAPIEnabled
                    )
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try processKillResult(params: params)
                    )
                case "loginApiKey":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.loginApiKeyResult(params: params, configuration: configuration)
                    )
                    notifications.append(try CodexAppServer.authStatusChangeNotification(configuration: configuration))
                case "loginChatGpt":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try loginChatGptResult()
                    )
                case "cancelLoginChatGpt":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try cancelLoginChatGptResult(params: params)
                    )
                case "logoutChatGpt":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.logoutResult(configuration: configuration)
                    )
                    notifications.append(try CodexAppServer.authStatusChangeNotification(configuration: configuration))
                case "account/login/start":
                    try CodexAppServer.requireAccountLoginStartExperimentalFieldsAPI(
                        params: params,
                        experimentalAPIEnabled: experimentalAPIEnabled
                    )
                    if CodexAppServer.stringParam(params?["type"]) == "chatgpt" {
                        response = CodexAppServer.responseObject(
                            id: id,
                            result: try loginChatGptAccountResult(params: params)
                        )
                    } else if CodexAppServer.stringParam(params?["type"]) == "chatgptDeviceCode" {
                        response = CodexAppServer.responseObject(
                            id: id,
                            result: try loginChatGptDeviceCodeAccountResult()
                        )
                    } else {
                        response = CodexAppServer.responseObject(
                            id: id,
                            result: try CodexAppServer.loginAccountResult(
                                params: params,
                                configuration: configuration,
                                cancelActiveLogin: { self.cancelActiveAccountLogins() }
                            )
                        )
                        notifications.append(CodexAppServer.accountLoginCompletedNotification())
                        notifications.append(try CodexAppServer.accountUpdatedNotification(configuration: configuration))
                        queueBestEffortMcpServerRefresh()
                    }
                case "account/login/cancel":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try cancelLoginAccountResult(params: params)
                    )
                case "feedback/upload":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.feedbackUploadResult(params: params, configuration: configuration)
                    )
                case "account/logout":
                    cancelActiveAccountLogins()
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.logoutResult(configuration: configuration)
                    )
                    notifications.append(try CodexAppServer.accountUpdatedNotification(configuration: configuration))
                    queueBestEffortMcpServerRefresh()
                case "setDefaultModel":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.setDefaultModelResult(params: params, configuration: configuration)
                    )
                default:
                    response = CodexAppServer.errorObject(id: id, code: -32601, message: "method not found: \(method)")
                }
            } catch let error as AppServerError {
                switch error {
                case .invalidRequest, .invalidRequestWithData:
                    response = CodexAppServer.errorObject(
                        id: id,
                        code: -32600,
                        message: error.description,
                        data: error.data
                    )
                case .invalidParams, .invalidParamsWithInputTooLargeData:
                    response = CodexAppServer.errorObject(
                        id: id,
                        code: -32602,
                        message: error.description,
                        data: error.data
                    )
                case .methodNotFound:
                    response = CodexAppServer.errorObject(id: id, code: -32601, message: error.description)
                case .internalError:
                    response = CodexAppServer.errorObject(id: id, code: -32603, message: error.description)
                }
            } catch {
                response = CodexAppServer.errorObject(id: id, code: -32603, message: String(describing: error))
            }
        }
        let envelopes = (response.map { [$0] } ?? []) + notifications
        return CodexAppServer.encodeMessages(envelopes)
    }
}

private struct AppServerThreadHistoryBuilder {
    private var turns: [[String: Any]] = []
    private var currentTurn: [String: Any]?
    private var currentItems: [[String: Any]] = []
    private var currentStatus = "completed"
    private var nextTurnIndex = 1
    private var nextItemIndex = 1

    mutating func handle(_ event: EventMessage) {
        switch event {
        case let .userMessage(payload):
            finishCurrentTurn()
            startTurn()
            var content: [[String: Any]] = []
            if !payload.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                content.append([
                    "type": "text",
                    "text": payload.message
                ])
            }
            for image in payload.images ?? [] {
                content.append([
                    "type": "image",
                    "url": image
                ])
            }
            currentItems.append([
                "type": "userMessage",
                "id": nextItemID(),
                "content": content
            ])
        case let .agentMessage(payload):
            guard !payload.message.isEmpty else {
                return
            }
            ensureTurn()
            currentItems.append([
                "type": "agentMessage",
                "id": nextItemID(),
                "text": payload.message
            ])
        case let .agentReasoning(payload):
            guard !payload.text.isEmpty else {
                return
            }
            ensureTurn()
            appendReasoning(summary: payload.text, content: nil)
        case let .agentReasoningRawContent(payload):
            guard !payload.text.isEmpty else {
                return
            }
            ensureTurn()
            appendReasoning(summary: nil, content: payload.text)
        case let .imageGenerationBegin(payload):
            upsertImageGeneration(
                id: payload.callID,
                status: "",
                revisedPrompt: nil,
                result: "",
                savedPath: nil
            )
        case let .imageGenerationEnd(payload):
            upsertImageGeneration(
                id: payload.callID,
                status: payload.status,
                revisedPrompt: payload.revisedPrompt,
                result: payload.result,
                savedPath: payload.savedPath
            )
        case let .enteredReviewMode(request):
            finishCurrentTurn()
            startTurn()
            let review = request.userFacingHint ?? ReviewPrompts.userFacingHint(target: request.target)
            currentItems.append([
                "type": "enteredReviewMode",
                "id": nextItemID(),
                "review": review
            ])
        case let .exitedReviewMode(event):
            ensureTurn()
            let review = event.reviewOutput.map(ReviewFormat.renderReviewOutputText) ?? ReviewFormat.fallbackMessage
            currentItems.append([
                "type": "exitedReviewMode",
                "id": nextItemID(),
                "review": review
            ])
        case .turnAborted:
            guard currentTurn != nil else {
                return
            }
            currentStatus = "interrupted"
        case let .threadRolledBack(event):
            finishCurrentTurn()
            let count = Int(event.numTurns)
            if count >= turns.count {
                turns.removeAll()
            } else {
                turns.removeLast(count)
            }
        default:
            return
        }
    }

    mutating func finish() -> [[String: Any]] {
        finishCurrentTurn()
        return turns
    }

    private mutating func ensureTurn() {
        if currentTurn == nil {
            startTurn()
        }
    }

    private mutating func startTurn() {
        currentTurn = [
            "id": nextTurnID()
        ]
        currentItems = []
        currentStatus = "completed"
    }

    private mutating func finishCurrentTurn() {
        guard var turn = currentTurn else {
            return
        }
        guard !currentItems.isEmpty else {
            currentTurn = nil
            return
        }
        turn["items"] = currentItems
        turn["status"] = currentStatus
        turn["error"] = NSNull()
        turns.append(turn)
        currentTurn = nil
        currentItems = []
        currentStatus = "completed"
    }

    private mutating func appendReasoning(summary: String?, content: String?) {
        if let last = currentItems.indices.last,
           currentItems[last]["type"] as? String == "reasoning" {
            if let summary {
                var summaries = currentItems[last]["summary"] as? [String] ?? []
                summaries.append(summary)
                currentItems[last]["summary"] = summaries
            }
            if let content {
                var contents = currentItems[last]["content"] as? [String] ?? []
                contents.append(content)
                currentItems[last]["content"] = contents
            }
            return
        }

        currentItems.append([
            "type": "reasoning",
            "id": nextItemID(),
            "summary": summary.map { [$0] } ?? [],
            "content": content.map { [$0] } ?? []
        ])
    }

    private mutating func upsertImageGeneration(
        id: String,
        status: String,
        revisedPrompt: String?,
        result: String,
        savedPath: AbsolutePath?
    ) {
        ensureTurn()
        var item: [String: Any] = [
            "type": "imageGeneration",
            "id": id,
            "status": status,
            "revisedPrompt": revisedPrompt ?? NSNull(),
            "result": result
        ]
        if let savedPath {
            item["savedPath"] = savedPath.path
        }

        if let index = currentItems.firstIndex(where: {
            $0["type"] as? String == "imageGeneration" && $0["id"] as? String == id
        }) {
            currentItems[index] = item
        } else {
            currentItems.append(item)
        }
    }

    private mutating func nextTurnID() -> String {
        defer {
            nextTurnIndex += 1
        }
        return "turn-\(nextTurnIndex)"
    }

    private mutating func nextItemID() -> String {
        defer {
            nextItemIndex += 1
        }
        return "item-\(nextItemIndex)"
    }
}

private struct AppServerThreadTurnsPage {
    let turns: [[String: Any]]
    let nextCursor: String?
    let backwardsCursor: String?
}

private enum AppServerTurnItemsView: String {
    case notLoaded
    case summary
    case full
}

private enum AppServerThreadTurnsSortDirection {
    case asc
    case desc
}

private enum AppServerMcpServerStatusDetail: String {
    case full
    case toolsAndAuthOnly
}

private func mcpServerStatusDetail(_ rawValue: Any?) throws -> AppServerMcpServerStatusDetail {
    guard let value = CodexAppServer.stringParam(rawValue) else {
        return .full
    }
    guard let detail = AppServerMcpServerStatusDetail(rawValue: value) else {
        throw AppServerError.invalidRequest(
            "Invalid request: unknown variant `\(value)`, expected `full` or `toolsAndAuthOnly`"
        )
    }
    return detail
}

private func turnItemsView(_ rawValue: Any?) throws -> AppServerTurnItemsView {
    guard let value = CodexAppServer.stringParam(rawValue) else {
        return .summary
    }
    guard let itemsView = AppServerTurnItemsView(rawValue: value) else {
        throw AppServerError.invalidRequest(
            "Invalid request: unknown variant `\(value)`, expected one of `notLoaded`, `summary`, `full`"
        )
    }
    return itemsView
}

private func threadTurnsSortDirection(_ rawValue: Any?) throws -> AppServerThreadTurnsSortDirection {
    guard let value = CodexAppServer.stringParam(rawValue) else {
        return .desc
    }
    switch value {
    case "asc":
        return .asc
    case "desc":
        return .desc
    default:
        throw AppServerError.invalidRequest(
            "Invalid request: unknown variant `\(value)`, expected `asc` or `desc`"
        )
    }
}

private func turnWithItemsView(_ turn: [String: Any], itemsView: AppServerTurnItemsView) -> [String: Any] {
    var updatedTurn = turn
    let items = (turn["items"] as? [[String: Any]]) ?? []
    switch itemsView {
    case .notLoaded:
        updatedTurn["items"] = []
    case .summary:
        let userMessage = items.first { $0["type"] as? String == "userMessage" }
        let agentMessage = items.reversed().first { $0["type"] as? String == "agentMessage" }
        switch (userMessage, agentMessage) {
        case let (user?, agent?) where (user["id"] as? String) != (agent["id"] as? String):
            updatedTurn["items"] = [user, agent]
        case let (user?, _):
            updatedTurn["items"] = [user]
        case let (nil, agent?):
            updatedTurn["items"] = [agent]
        case (nil, nil):
            updatedTurn["items"] = []
        }
    case .full:
        updatedTurn["items"] = items
    }
    updatedTurn["itemsView"] = itemsView.rawValue
    return updatedTurn
}

private func paginateThreadTurns(
    _ turns: [[String: Any]],
    cursor: String?,
    limit: Int,
    sortDirection: AppServerThreadTurnsSortDirection
) throws -> AppServerThreadTurnsPage {
    guard !turns.isEmpty else {
        return AppServerThreadTurnsPage(turns: [], nextCursor: nil, backwardsCursor: nil)
    }
    let anchor = try cursor.map(parseThreadTurnsCursor)
    let anchorIndex = anchor.flatMap { cursor in
        turns.firstIndex { $0["id"] as? String == cursor.turnID }
    }
    if anchor != nil && anchorIndex == nil {
        throw AppServerError.invalidRequest("invalid cursor: anchor turn is no longer present")
    }

    let descending = sortDirection == .desc
    var keyedTurns = Array(turns.enumerated())
    if descending {
        keyedTurns.reverse()
    }
    if let anchor, let anchorIndex {
        keyedTurns = keyedTurns.filter { index, _ in
            if descending {
                return anchor.includeAnchor ? index <= anchorIndex : index < anchorIndex
            }
            return anchor.includeAnchor ? index >= anchorIndex : index > anchorIndex
        }
    }

    let moreTurnsAvailable = keyedTurns.count > limit
    keyedTurns = Array(keyedTurns.prefix(limit))
    let backwardsCursor = try keyedTurns.first.map { _, turn in
        try serializeThreadTurnsCursor(turnID: turn["id"] as? String ?? "", includeAnchor: true)
    }
    let nextCursor: String?
    if moreTurnsAvailable {
        nextCursor = try keyedTurns.last.map { _, turn in
            try serializeThreadTurnsCursor(turnID: turn["id"] as? String ?? "", includeAnchor: false)
        }
    } else {
        nextCursor = nil
    }
    return AppServerThreadTurnsPage(
        turns: keyedTurns.map(\.element),
        nextCursor: nextCursor,
        backwardsCursor: backwardsCursor
    )
}

private struct AppServerThreadTurnsCursor {
    let turnID: String
    let includeAnchor: Bool
}

private func serializeThreadTurnsCursor(turnID: String, includeAnchor: Bool) throws -> String {
    let object: [String: Any] = [
        "turnId": turnID,
        "includeAnchor": includeAnchor
    ]
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(data: data, encoding: .utf8) ?? "{}"
}

private func parseThreadTurnsCursor(_ cursor: String) throws -> AppServerThreadTurnsCursor {
    guard let data = cursor.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let turnID = object["turnId"] as? String,
          let includeAnchor = object["includeAnchor"] as? Bool
    else {
        throw AppServerError.invalidRequest("invalid cursor: \(cursor)")
    }
    return AppServerThreadTurnsCursor(turnID: turnID, includeAnchor: includeAnchor)
}

private func clearMemoryRootContents(_ root: URL, fileManager: FileManager = .default) throws {
    if let type = try? root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink,
       type == true {
        throw CocoaError(
            .fileWriteInvalidFileName,
            userInfo: [NSFilePathErrorKey: root.path, NSLocalizedDescriptionKey: "refusing to clear symlinked memory root \(root.path)"]
        )
    }
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    let entries = try fileManager.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsSubdirectoryDescendants]
    )
    for entry in entries {
        try fileManager.removeItem(at: entry)
    }
}

private struct RolloutSummary {
    let id: String
    let forkedFromID: String?
    let preview: String
    let model: String?
    let reasoningEffort: ReasoningEffort?
    let modelProvider: String
    let createdAtUnixSeconds: Int
    let cwd: String
    let cliVersion: String
    let source: SessionSource
    let threadSource: String?
    let agentNickname: String?
    let agentRole: String?
    let gitInfo: [String: Any]?
    let v1GitInfo: [String: Any]?
    let name: String?

    init(path: String, defaultProvider: String) throws {
        let text = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
        var meta: SessionMetaLine?
        var preview = ""
        var latestTurnContextCwd: String?
        var latestTurnContextModel: String?
        var latestTurnContextReasoningEffort: ReasoningEffort?

        for rawLine in text.split(whereSeparator: \.isNewline) {
            guard let data = rawLine.data(using: .utf8),
                  let line = try? JSONDecoder().decode(RolloutLine.self, from: data)
            else {
                continue
            }
            switch line.item {
            case let .sessionMeta(value):
                if meta == nil {
                    meta = value
                }
            case let .eventMsg(.userMessage(message)):
                if preview.isEmpty {
                    preview = message.message
                }
            case let .responseItem(item):
                if preview.isEmpty, let text = Self.itemPreview(item) {
                    preview = text
                }
            case let .turnContext(turnContext):
                latestTurnContextCwd = turnContext.cwd
                latestTurnContextModel = turnContext.model
                latestTurnContextReasoningEffort = turnContext.effort
            case .compacted,
                 .eventMsg:
                continue
            }
        }

        guard let meta else {
            throw RolloutRecorderError.missingConversationID
        }

        self.id = meta.meta.id.description
        self.forkedFromID = meta.meta.forkedFromID?.description
        self.preview = preview
        self.model = latestTurnContextModel
        self.reasoningEffort = latestTurnContextReasoningEffort
        self.modelProvider = meta.meta.modelProvider ?? defaultProvider
        self.createdAtUnixSeconds = Self.unixSeconds(meta.meta.timestamp)
        self.cwd = latestTurnContextCwd ?? meta.meta.cwd
        self.cliVersion = meta.meta.cliVersion
        self.source = meta.meta.source
        self.threadSource = meta.meta.threadSource?.description
        self.agentNickname = meta.meta.agentNickname
        self.agentRole = meta.meta.agentRole
        self.name = Self.findThreadName(threadID: meta.meta.id.description, rolloutPath: path)
        if let git = meta.git {
            self.gitInfo = [
                "sha": git.commitHash as Any,
                "branch": git.branch as Any,
                "originUrl": git.repositoryURL as Any
            ].nullStripped()
            self.v1GitInfo = [
                "sha": git.commitHash as Any,
                "branch": git.branch as Any,
                "origin_url": git.repositoryURL as Any
            ].nullStripped()
        } else {
            self.gitInfo = nil
            self.v1GitInfo = nil
        }
    }

    private static func itemPreview(_ item: ResponseItem) -> String? {
        guard case let .message(_, role, content, _) = item,
              role == "user"
        else {
            return nil
        }
        return content.compactMap { content -> String? in
            if case let .inputText(text) = content {
                return text
            }
            return nil
        }.joined(separator: "\n")
    }

    private static func findThreadName(threadID: String, rolloutPath: String) -> String? {
        guard let codexHome = inferCodexHome(fromRolloutPath: rolloutPath) else {
            return nil
        }
        let indexPath = codexHome.appendingPathComponent("session_index.jsonl", isDirectory: false)
        guard let contents = try? String(contentsOf: indexPath, encoding: .utf8) else {
            return nil
        }
        for rawLine in contents.split(whereSeparator: \.isNewline).reversed() {
            guard let data = rawLine.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["id"] as? String == threadID,
                  let name = object["thread_name"] as? String
            else {
                continue
            }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private static func inferCodexHome(fromRolloutPath path: String) -> URL? {
        let url = URL(fileURLWithPath: path, isDirectory: false).standardizedFileURL
        let components = url.pathComponents
        guard let markerIndex = components.firstIndex(where: { $0 == "sessions" || $0 == "archived_sessions" }),
              markerIndex > 0
        else {
            return nil
        }
        let homeComponents = components[..<markerIndex]
        let homePath = NSString.path(withComponents: Array(homeComponents))
        return URL(fileURLWithPath: homePath, isDirectory: true)
    }

    private static func unixSeconds(_ timestamp: String) -> Int {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: timestamp) {
            return Int(date.timeIntervalSince1970)
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: timestamp) {
            return Int(date.timeIntervalSince1970)
        }
        return 0
    }
}

private extension Dictionary where Key == String, Value == Any {
    func nullStripped(keepNulls: Bool = false) -> [String: Any] {
        compactMapValues { value in
            if keepNulls, value is NSNull {
                return value
            }
            if value is NSNull {
                return nil
            }
            let mirror = Mirror(reflecting: value)
            if mirror.displayStyle == .optional, mirror.children.isEmpty {
                return nil
            }
            return value
        }
    }
}

private extension TurnContextItem {
    func withTurnID(_ turnID: String) -> TurnContextItem {
        TurnContextItem(
            turnID: turnID,
            traceID: traceID,
            cwd: cwd,
            currentDate: currentDate,
            timezone: timezone,
            approvalPolicy: approvalPolicy,
            sandboxPolicy: sandboxPolicy,
            permissionProfile: permissionProfile,
            activePermissionProfile: activePermissionProfile,
            network: network,
            fileSystemSandboxPolicy: fileSystemSandboxPolicy,
            model: model,
            personality: personality,
            collaborationMode: collaborationMode,
            realtimeActive: realtimeActive,
            effort: effort,
            summary: summary,
            userInstructions: userInstructions,
            developerInstructions: developerInstructions,
            finalOutputJSONSchema: finalOutputJSONSchema,
            truncationPolicy: truncationPolicy
        )
    }
}

private enum NullableStringPatch {
    case absent
    case clear
    case set(String)

    var isPresent: Bool {
        switch self {
        case .absent:
            return false
        case .clear, .set:
            return true
        }
    }

    func apply(to value: String?) -> String? {
        switch self {
        case .absent:
            return value
        case .clear:
            return nil
        case let .set(value):
            return value
        }
    }
}

private struct GitInfoPatch {
    let sha: NullableStringPatch
    let branch: NullableStringPatch
    let originURL: NullableStringPatch

    var hasAnyField: Bool {
        sha.isPresent || branch.isPresent || originURL.isPresent
    }

    init(params: [String: Any]) throws {
        self.sha = try Self.patch(params: params, key: "sha", name: "gitInfo.sha")
        self.branch = try Self.patch(params: params, key: "branch", name: "gitInfo.branch")
        self.originURL = try Self.patch(params: params, key: "originUrl", name: "gitInfo.originUrl")
    }

    func apply(to git: GitInfo?) -> GitInfo? {
        let updated = GitInfo(
            commitHash: sha.apply(to: git?.commitHash),
            branch: branch.apply(to: git?.branch),
            repositoryURL: originURL.apply(to: git?.repositoryURL)
        )
        if updated.commitHash == nil,
           updated.branch == nil,
           updated.repositoryURL == nil {
            return nil
        }
        return updated
    }

    private static func patch(params: [String: Any], key: String, name: String) throws -> NullableStringPatch {
        guard let rawValue = params[key] else {
            return .absent
        }
        if rawValue is NSNull {
            return .clear
        }
        guard let value = rawValue as? String else {
            throw AppServerError.invalidRequest("\(name) must be a string or null")
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AppServerError.invalidRequest("\(name) must not be empty")
        }
        return .set(trimmed)
    }
}

private func updateRolloutSessionGitInfo(rolloutPath: String, patch: GitInfoPatch) throws -> String {
    let url = URL(fileURLWithPath: rolloutPath, isDirectory: false)
    let text = try String(contentsOf: url, encoding: .utf8)
    let encoder = JSONEncoder()
    var updated = false
    let outputLines = try text.split(separator: "\n", omittingEmptySubsequences: false).map { rawLine -> String in
        let lineText = String(rawLine)
        guard !updated,
              let data = lineText.data(using: .utf8),
              let line = try? JSONDecoder().decode(RolloutLine.self, from: data),
              case let .sessionMeta(sessionMeta) = line.item
        else {
            return lineText
        }

        let updatedLine = RolloutLine(
            timestamp: line.timestamp,
            item: .sessionMeta(SessionMetaLine(
                meta: sessionMeta.meta,
                git: patch.apply(to: sessionMeta.git)
            ))
        )
        updated = true
        return String(data: try encoder.encode(updatedLine), encoding: .utf8) ?? lineText
    }
    guard updated else {
        throw RolloutRecorderError.missingConversationID
    }
    try outputLines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    return rolloutPath
}

private extension String {
    var nonEmptyString: String? {
        isEmpty ? nil : self
    }
}
