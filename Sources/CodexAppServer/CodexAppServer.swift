import CodexCore
import CryptoKit
import Dispatch
import Foundation

public typealias AppServerAuthRefreshTransport = @Sendable (URLRequest) async throws -> AuthRefreshHTTPResponse
public typealias AppServerNotificationSink = @Sendable (Data) async -> Void
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
    public let scopes: [String]
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
        scopes: [String] = [],
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
    public let defaultModelProvider: String
    public let originator: String
    public let version: String
    public let requiresOpenAIAuth: Bool
    public let authCredentialsStoreMode: AuthCredentialsStoreMode
    public let environment: [String: String]
    public let activeProfile: String?
    public let feedback: CodexFeedback
    public let feedbackUploadTransport: any FeedbackUploadTransport
    public let accountRateLimitsFetcher: any AccountRateLimitsFetching
    public let authRefreshTransport: AppServerAuthRefreshTransport?
    public let mcpOAuthLoginStarter: AppServerMcpOAuthLoginStarter
    public let configLayerOverrides: ConfigLayerLoaderOverrides

    public init(
        codexHome: URL,
        defaultModelProvider: String = "openai",
        originator: String = "codex_swift",
        version: String = "0.0.0",
        requiresOpenAIAuth: Bool = true,
        authCredentialsStoreMode: AuthCredentialsStoreMode = .file,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        activeProfile: String? = nil,
        feedback: CodexFeedback = CodexFeedback(),
        feedbackUploadTransport: any FeedbackUploadTransport = URLSessionFeedbackUploadTransport(),
        accountRateLimitsFetcher: any AccountRateLimitsFetching = URLSessionAccountRateLimitsFetcher(),
        authRefreshTransport: AppServerAuthRefreshTransport? = nil,
        mcpOAuthLoginStarter: @escaping AppServerMcpOAuthLoginStarter = CodexAppServer.defaultMcpOAuthLoginStarter,
        configLayerOverrides: ConfigLayerLoaderOverrides = ConfigLayerLoaderOverrides()
    ) {
        self.codexHome = codexHome
        self.defaultModelProvider = defaultModelProvider
        self.originator = originator
        self.version = version
        self.requiresOpenAIAuth = requiresOpenAIAuth
        self.authCredentialsStoreMode = authCredentialsStoreMode
        self.environment = environment
        self.activeProfile = activeProfile
        self.feedback = feedback
        self.feedbackUploadTransport = feedbackUploadTransport
        self.accountRateLimitsFetcher = accountRateLimitsFetcher
        self.authRefreshTransport = authRefreshTransport
        self.mcpOAuthLoginStarter = mcpOAuthLoginStarter
        self.configLayerOverrides = configLayerOverrides
    }

    public static func == (lhs: CodexAppServerConfiguration, rhs: CodexAppServerConfiguration) -> Bool {
        lhs.codexHome == rhs.codexHome &&
            lhs.defaultModelProvider == rhs.defaultModelProvider &&
            lhs.originator == rhs.originator &&
            lhs.version == rhs.version &&
            lhs.requiresOpenAIAuth == rhs.requiresOpenAIAuth &&
            lhs.authCredentialsStoreMode == rhs.authCredentialsStoreMode &&
            lhs.environment == rhs.environment &&
            lhs.activeProfile == rhs.activeProfile &&
            lhs.configLayerOverrides == rhs.configLayerOverrides
    }
}

public protocol AccountRateLimitsFetching: Sendable {
    func fetchRateLimits(baseURL: String, accessToken: String, accountID: String) async throws -> RateLimitSnapshot
}

public struct AccountRateLimitsHTTPResponse: Sendable {
    public let statusCode: Int
    public let body: Data

    public init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
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

    public func fetchRateLimits(baseURL: String, accessToken: String, accountID: String) async throws -> RateLimitSnapshot {
        let normalizedBaseURL = Self.normalizedBaseURL(baseURL)
        let usagePath = normalizedBaseURL.contains("/backend-api") ? "/wham/usage" : "/api/codex/usage"
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
        return payload.snapshot
    }

    private static func urlSessionTransport(_ request: URLRequest) async throws -> AccountRateLimitsHTTPResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AccountRateLimitsFetchError.nonHTTPResponse
        }
        return AccountRateLimitsHTTPResponse(statusCode: httpResponse.statusCode, body: data)
    }

    private static func normalizedBaseURL(_ baseURL: String) -> String {
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

    private enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
    }

    var snapshot: RateLimitSnapshot {
        RateLimitSnapshot(
            primary: rateLimit?.primaryWindow?.rateLimitWindow,
            secondary: rateLimit?.secondaryWindow?.rateLimitWindow,
            credits: nil,
            planType: planType
        )
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
    private static let fuzzyFileSearchLimitPerRoot = 50
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
        let page = try RolloutListing.getConversations(
            codexHome: configuration.codexHome,
            pageSize: listLimit(params?["limit"]),
            cursor: stringParam(params?["cursor"]).flatMap(RolloutListing.parseCursor),
            allowedSources: interactiveSessionSources,
            modelProviders: modelProviderFilter(params?["modelProviders"], defaultProvider: configuration.defaultModelProvider),
            defaultProvider: configuration.defaultModelProvider
        )
        return [
            "data": try page.items.map { try threadObject(for: $0, defaultProvider: configuration.defaultModelProvider) },
            "nextCursor": page.nextCursor?.token as Any
        ].nullStripped()
    }

    fileprivate static func threadStartResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        let started = try startRolloutConversation(params: params, configuration: configuration)
        let item = ConversationItem(path: started.rolloutPath.path, head: [], createdAt: nil, updatedAt: nil)
        let thread = try threadObject(
            for: item,
            defaultProvider: configuration.defaultModelProvider
        )
        return [
            "thread": thread,
            "model": started.model,
            "modelProvider": started.modelProvider,
            "cwd": started.cwd.path,
            "approvalPolicy": started.approvalPolicy.rawValue,
            "sandbox": try jsonObject(started.sandbox),
            "reasoningEffort": started.reasoningEffort ?? NSNull()
        ].nullStripped(keepNulls: true)
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
            "rolloutPath": started.rolloutPath.path
        ].nullStripped(keepNulls: true)
    }

    private static func startRolloutConversation(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> AppServerStartedConversation {
        let runtimeConfig = try CodexConfigLoader.load(codexHome: configuration.codexHome)
        let model = stringParam(params?["model"])
            ?? runtimeConfig.model
            ?? ModelsManager.offlineModel(explicitModel: nil)
        let modelProvider = stringParam(params?["modelProvider"])
            ?? runtimeConfig.selectedModelProviderID
        let approvalPolicy = approvalPolicyParam(params?["approvalPolicy"])
            ?? runtimeConfig.approvalPolicy
            ?? .unlessTrusted
        let sandboxMode = sandboxModeParam(params?["sandbox"])
            ?? runtimeConfig.sandboxMode
            ?? .readOnly
        let sandbox = sandboxPolicy(for: sandboxMode)
        let cwd = stringParam(params?["cwd"]).map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
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
            originator: "codex_app_server",
            cliVersion: configuration.version,
            modelProvider: modelProvider
        )
        try recorder.shutdown()
        return AppServerStartedConversation(
            conversationID: conversationID,
            rolloutPath: recorder.rolloutPath,
            model: model,
            modelProvider: modelProvider,
            cwd: cwd,
            approvalPolicy: approvalPolicy,
            sandbox: sandbox,
            reasoningEffort: runtimeConfig.modelReasoningEffort?.rawValue
        )
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
        let runtimeConfig = try CodexConfigLoader.load(codexHome: configuration.codexHome)
        let model = runtimeConfig.model ?? ModelsManager.offlineModel(explicitModel: nil)
        let modelProvider = runtimeConfig.selectedModelProviderID
        let approvalPolicy = runtimeConfig.approvalPolicy ?? .unlessTrusted
        let sandbox = sandboxPolicy(for: runtimeConfig.sandboxMode ?? .readOnly)

        return [
            "thread": thread,
            "model": model,
            "modelProvider": modelProvider,
            "cwd": thread["cwd"] ?? "/",
            "approvalPolicy": approvalPolicy.rawValue,
            "sandbox": try jsonObject(sandbox),
            "reasoningEffort": runtimeConfig.modelReasoningEffort?.rawValue ?? NSNull()
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
        let runtimeConfig = try CodexConfigLoader.load(codexHome: configuration.codexHome)
        let model = stringParam(params?["model"])
            ?? runtimeConfig.model
            ?? ModelsManager.offlineModel(explicitModel: nil)
        let modelProvider = stringParam(params?["modelProvider"])
            ?? sourceSummary.modelProvider
        let approvalPolicy = approvalPolicyParam(params?["approvalPolicy"])
            ?? runtimeConfig.approvalPolicy
            ?? .unlessTrusted
        let sandboxMode = sandboxModeParam(params?["sandbox"])
            ?? runtimeConfig.sandboxMode
            ?? .readOnly
        let sandbox = sandboxPolicy(for: sandboxMode)
        let cwd = URL(
            fileURLWithPath: stringParam(params?["cwd"]) ?? sourceSummary.cwd,
            isDirectory: true
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
            modelProvider: modelProvider
        )
        try recorder.recordItems(history.rolloutItems.filter { item in
            if case .sessionMeta = item {
                return false
            }
            return true
        })
        try recorder.shutdown()

        let item = ConversationItem(path: recorder.rolloutPath.path, head: [], createdAt: nil, updatedAt: nil)
        let includeTurns = !boolParam(params?["excludeTurns"], defaultValue: false)
        let thread = try threadObject(
            for: item,
            defaultProvider: configuration.defaultModelProvider,
            turns: includeTurns ? buildTurnsFromRolloutEvents(at: recorder.rolloutPath.path) : []
        )
        return [
            "thread": thread,
            "model": model,
            "modelProvider": modelProvider,
            "serviceTier": nullable(stringParam(params?["serviceTier"])),
            "cwd": cwd.path,
            "instructionSources": [],
            "approvalPolicy": approvalPolicy.rawValue,
            "approvalsReviewer": "user",
            "sandbox": try jsonObject(sandbox),
            "permissionProfile": NSNull(),
            "activePermissionProfile": NSNull(),
            "reasoningEffort": runtimeConfig.modelReasoningEffort?.rawValue ?? NSNull()
        ].nullStripped(keepNulls: true)
    }

    fileprivate static func threadReadResult(
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

        guard let rolloutPath = try RolloutListing.findConversationPathByIDString(
            codexHome: configuration.codexHome,
            idString: conversationID.description
        ) else {
            throw AppServerError.invalidRequest("thread not loaded: \(conversationID)")
        }
        let includeTurns = boolParam(params?["includeTurns"], defaultValue: false)
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

        guard let rolloutPath = try RolloutListing.findConversationPathByIDString(
            codexHome: configuration.codexHome,
            idString: conversationID.description
        ) else {
            throw AppServerError.invalidRequest("thread not loaded: \(conversationID)")
        }

        let itemsView = turnItemsView(params?["itemsView"])
        let turns = try buildTurnsFromRolloutEvents(at: rolloutPath).map { turn in
            turnWithItemsView(turn, itemsView: itemsView)
        }
        let page = try paginateThreadTurns(
            turns,
            cursor: stringParam(params?["cursor"]),
            limit: listLimit(params?["limit"], defaultValue: 25, maximum: 100),
            sortDirection: stringParam(params?["sortDirection"])
        )
        return [
            "data": page.turns,
            "nextCursor": page.nextCursor ?? NSNull(),
            "backwardsCursor": page.backwardsCursor ?? NSNull()
        ].nullStripped(keepNulls: true)
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

        let limit = max(intParam(params?["limit"], defaultValue: data.count), 1)
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
            modelProvider: modelProvider
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
        let rolloutPath = try rolloutPathForConversation(conversationID, configuration: configuration)
        let input = v2UserInputs(params?["input"])
        if !input.text.isEmpty || !(input.images?.isEmpty ?? true) {
            let recorder = try RolloutRecorder.resume(path: URL(fileURLWithPath: rolloutPath))
            try recorder.recordItems([
                .eventMsg(.userMessage(UserMessageEvent(message: input.text, images: input.images)))
            ])
            try recorder.shutdown()
        }
        let turn: [String: Any] = [
            "id": UUID().uuidString.lowercased(),
            "items": [],
            "status": "inProgress",
            "error": NSNull()
        ]
        return [
            "turn": turn
        ]
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

        let rolloutPath: String
        do {
            rolloutPath = try rolloutPathForConversation(conversationID, configuration: configuration)
        } catch let error as AppServerError {
            throw error
        }

        try archiveConversation(conversationID: conversationID, rolloutPath: rolloutPath, configuration: configuration)
        return [:]
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
        let item = ConversationItem(path: rolloutPath, head: [], createdAt: nil, updatedAt: nil)
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
            rolloutPath = path
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

        try archiveConversation(conversationID: conversationID, rolloutPath: rawPath, configuration: configuration)
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

        let rolloutPath = try rolloutPathForConversation(threadID, configuration: configuration)
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

    fileprivate static func threadGoalSetResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> (result: [String: Any], threadID: String, goal: [String: Any]) {
        try requireGoalsFeature(configuration: configuration)
        let threadID = try materializedGoalThreadID(params: params, configuration: configuration)
        var goals = try readThreadGoals(codexHome: configuration.codexHome)
        let status = try goalStatus(params?["status"])
        let objective = stringParam(params?["objective"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokenBudget = try goalTokenBudget(params: params)

        if let objective {
            try validateGoalObjective(objective)
            if tokenBudget.wasProvided {
                try validateGoalBudget(tokenBudget.value)
            }
            if var existing = goals[threadID],
               existing.objective == objective,
               existing.status != "complete" {
                existing.status = status ?? existing.status
                if tokenBudget.wasProvided {
                    existing.tokenBudget = tokenBudget.value
                }
                existing.updatedAt = currentUnixTimestamp()
                goals[threadID] = existing
            } else {
                goals[threadID] = StoredThreadGoal(
                    threadID: threadID,
                    objective: objective,
                    status: status ?? "active",
                    tokenBudget: tokenBudget.wasProvided ? tokenBudget.value : nil,
                    tokensUsed: 0,
                    timeUsedSeconds: 0,
                    createdAt: currentUnixTimestamp(),
                    updatedAt: currentUnixTimestamp()
                )
            }
        } else {
            guard var existing = goals[threadID] else {
                throw AppServerError.invalidRequest("cannot update goal for thread \(threadID): no goal exists")
            }
            if tokenBudget.wasProvided {
                try validateGoalBudget(tokenBudget.value)
            }
            existing.status = status ?? existing.status
            if tokenBudget.wasProvided {
                existing.tokenBudget = tokenBudget.value
            }
            existing.updatedAt = currentUnixTimestamp()
            goals[threadID] = existing
        }

        try writeThreadGoals(goals, codexHome: configuration.codexHome)
        let goal = goals[threadID]!.object
        return (["goal": goal], threadID, goal)
    }

    fileprivate static func threadGoalGetResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        try requireGoalsFeature(configuration: configuration)
        let threadID = try materializedGoalThreadID(params: params, configuration: configuration)
        let goal = try readThreadGoals(codexHome: configuration.codexHome)[threadID]?.object
        return ["goal": goal ?? NSNull()]
    }

    fileprivate static func threadGoalClearResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> (result: [String: Any], threadID: String, cleared: Bool) {
        try requireGoalsFeature(configuration: configuration)
        let threadID = try materializedGoalThreadID(params: params, configuration: configuration)
        var goals = try readThreadGoals(codexHome: configuration.codexHome)
        let cleared = goals.removeValue(forKey: threadID) != nil
        if cleared {
            try writeThreadGoals(goals, codexHome: configuration.codexHome)
        }
        return (["cleared": cleared], threadID, cleared)
    }

    private static func requireGoalsFeature(configuration: CodexAppServerConfiguration) throws {
        let runtimeConfig = try CodexConfigLoader.load(codexHome: configuration.codexHome)
        guard runtimeConfig.features.isEnabled(.goals) else {
            throw AppServerError.invalidRequest("goals feature is disabled")
        }
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

    private static func goalStatus(_ raw: Any?) throws -> String? {
        guard let raw else {
            return nil
        }
        guard let status = stringParam(raw) else {
            throw AppServerError.invalidRequest("invalid goal status")
        }
        switch status {
        case "active", "paused", "budgetLimited", "complete":
            return status
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

    private struct StoredThreadGoal: Codable {
        let threadID: String
        let objective: String
        var status: String
        var tokenBudget: Int?
        var tokensUsed: Int
        var timeUsedSeconds: Int
        let createdAt: Int
        var updatedAt: Int

        private enum CodingKeys: String, CodingKey {
            case threadID = "threadId"
            case objective
            case status
            case tokenBudget
            case tokensUsed
            case timeUsedSeconds
            case createdAt
            case updatedAt
        }

        var object: [String: Any] {
            [
                "threadId": threadID,
                "objective": objective,
                "status": status,
                "tokenBudget": tokenBudget ?? NSNull(),
                "tokensUsed": tokensUsed,
                "timeUsedSeconds": timeUsedSeconds,
                "createdAt": createdAt,
                "updatedAt": updatedAt
            ]
        }
    }

    private static func readThreadGoals(codexHome: URL) throws -> [String: StoredThreadGoal] {
        let path = threadGoalsPath(codexHome: codexHome)
        guard FileManager.default.fileExists(atPath: path.path) else {
            return [:]
        }
        let data = try Data(contentsOf: path)
        guard !data.isEmpty else {
            return [:]
        }
        return try JSONDecoder().decode([String: StoredThreadGoal].self, from: data)
    }

    private static func writeThreadGoals(_ goals: [String: StoredThreadGoal], codexHome: URL) throws {
        let path = threadGoalsPath(codexHome: codexHome)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(goals).write(to: path, options: .atomic)
    }

    private static func threadGoalsPath(codexHome: URL) -> URL {
        codexHome.appendingPathComponent("thread_goals.json", isDirectory: false)
    }

    private static func currentUnixTimestamp() -> Int {
        Int(Date().timeIntervalSince1970)
    }

    fileprivate static func threadMemoryModeSetResult(
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
        return [:]
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

    fileprivate static func memoryResetResult(configuration: CodexAppServerConfiguration) throws -> [String: Any] {
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
        guard let data = Data(base64Encoded: dataBase64) else {
            throw AppServerError.invalidRequest("fs/writeFile requires valid base64 dataBase64: invalid base64 data")
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
        guard let watchID = stringParam(params?["watchId"]) else {
            throw AppServerError.invalidRequest("missing watchId")
        }
        let path = try absolutePathParam(params?["path"], name: "path")
        return (watchID, path)
    }

    fileprivate static func fsUnwatchParams(_ params: [String: Any]?) throws -> String {
        guard let watchID = stringParam(params?["watchId"]) else {
            throw AppServerError.invalidRequest("missing watchId")
        }
        return watchID
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

    fileprivate static func appListResult(params: [String: Any]?) throws -> [String: Any] {
        let total = 0
        if let cursor = stringParam(params?["cursor"]) {
            guard let start = Int(cursor), start >= 0 else {
                throw AppServerError.invalidRequest("invalid cursor: \(cursor)")
            }
            guard start <= total else {
                throw AppServerError.invalidRequest("cursor \(start) exceeds total apps \(total)")
            }
        }
        return [
            "data": [],
            "nextCursor": NSNull()
        ]
    }

    fileprivate static func pluginListResult(params: [String: Any]?) throws -> [String: Any] {
        if let cwds = stringArrayParam(params?["cwds"]) {
            for cwd in cwds {
                guard URL(fileURLWithPath: cwd, isDirectory: true).path == cwd,
                      cwd.hasPrefix("/")
                else {
                    throw AppServerError.invalidRequest("Invalid request: AbsolutePathBuf deserialized without a base path")
                }
            }
        }
        if let kinds = stringArrayParam(params?["marketplaceKinds"]) {
            let validKinds: Set<String> = ["local", "workspace-directory", "shared-with-me"]
            for kind in kinds where !validKinds.contains(kind) {
                throw AppServerError.invalidParams("unknown variant `\(kind)`, expected one of `local`, `workspace-directory`, `shared-with-me`")
            }
        }
        return [
            "marketplaces": [],
            "marketplaceLoadErrors": [],
            "featuredPluginIds": []
        ]
    }

    fileprivate static func pluginReadResult(params: [String: Any]?) throws -> [String: Any] {
        let marketplacePath = try optionalAbsolutePathParam(params?["marketplacePath"], name: "marketplacePath")
        let remoteMarketplaceName = stringParam(params?["remoteMarketplaceName"])
        _ = stringParam(params?["pluginName"]) ?? ""
        switch (marketplacePath, remoteMarketplaceName) {
        case (.some, .some), (.none, .none):
            throw AppServerError.invalidRequest("plugin/read requires exactly one of marketplacePath or remoteMarketplaceName")
        case (.some, .none):
            throw AppServerError.invalidRequest("local plugin read is not implemented")
        case (.none, .some(let remoteMarketplaceName)):
            throw AppServerError.invalidRequest("remote plugin read is not enabled for marketplace \(remoteMarketplaceName)")
        }
    }

    fileprivate static func pluginSkillReadResult(params: [String: Any]?) throws -> [String: Any] {
        let remoteMarketplaceName = stringParam(params?["remoteMarketplaceName"]) ?? ""
        _ = stringParam(params?["remotePluginId"]) ?? ""
        _ = stringParam(params?["skillName"]) ?? ""
        throw AppServerError.invalidRequest("remote plugin skill read is not enabled for marketplace \(remoteMarketplaceName)")
    }

    fileprivate static func pluginShareSaveResult(params: [String: Any]?) throws -> [String: Any] {
        _ = try absolutePathParam(params?["pluginPath"], name: "pluginPath")
        throw AppServerError.invalidRequest("plugin sharing is not enabled")
    }

    fileprivate static func pluginShareUpdateTargetsResult(params _: [String: Any]?) throws -> [String: Any] {
        throw AppServerError.invalidRequest("plugin sharing is not enabled")
    }

    fileprivate static func pluginShareListResult(params _: [String: Any]?) throws -> [String: Any] {
        throw AppServerError.invalidRequest("plugin sharing is not enabled")
    }

    fileprivate static func pluginShareDeleteResult(params _: [String: Any]?) throws -> [String: Any] {
        throw AppServerError.invalidRequest("plugin sharing is not enabled")
    }

    fileprivate static func pluginInstallResult(params: [String: Any]?) throws -> [String: Any] {
        let marketplacePath = try optionalAbsolutePathParam(params?["marketplacePath"], name: "marketplacePath")
        let remoteMarketplaceName = stringParam(params?["remoteMarketplaceName"])
        _ = stringParam(params?["pluginName"]) ?? ""
        switch (marketplacePath, remoteMarketplaceName) {
        case (.some, .some), (.none, .none):
            throw AppServerError.invalidRequest("plugin/install requires exactly one of marketplacePath or remoteMarketplaceName")
        case (.some, .none):
            throw AppServerError.invalidRequest("local plugin install is not implemented")
        case (.none, .some(let remoteMarketplaceName)):
            throw AppServerError.invalidRequest("remote plugin install is not enabled for marketplace \(remoteMarketplaceName)")
        }
    }

    fileprivate static func pluginUninstallResult(params: [String: Any]?) throws -> [String: Any] {
        let pluginID = stringParam(params?["pluginId"]) ?? ""
        guard isValidRemotePluginID(pluginID) || isLikelyLocalPluginID(pluginID) else {
            throw AppServerError.invalidRequest("invalid remote plugin id")
        }
        if isValidRemotePluginID(pluginID) {
            throw AppServerError.invalidRequest("remote plugin uninstall is not enabled")
        }
        throw AppServerError.invalidRequest("local plugin uninstall is not implemented")
    }

    fileprivate static func externalAgentConfigDetectResult(params _: [String: Any]?) -> [String: Any] {
        ["items": []]
    }

    fileprivate static func externalAgentConfigImportResult(params: [String: Any]?) throws -> [String: Any] {
        let items = params?["migrationItems"] as? [Any] ?? []
        guard items.isEmpty else {
            throw AppServerError.invalidRequest("external agent config import is not implemented")
        }
        return [:]
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
        let remoteModels = try ModelsCache.load(from: ModelsManager.cachePath(codexHome: configuration.codexHome))?.models ?? []
        let chatGPTMode = (try currentAuth(configuration: configuration))?.method == "chatgpt"
        let availableModels = ModelsManager.buildAvailableModels(
            remoteModels: remoteModels,
            localModels: ModelsManager.builtinModelPresets(),
            chatGPTMode: chatGPTMode
        )
        let defaultModel = ModelsManager.defaultModel(
            explicitModel: nil,
            isChatGPT: chatGPTMode,
            availableModels: availableModels
        )
        let includeHidden = boolParam(params?["includeHidden"], defaultValue: false)
        let models = availableModels
            .map { $0.withIsDefault($0.model == defaultModel) }
            .filter { includeHidden || $0.showInPicker }
        let total = models.count
        let start = try modelListStart(cursor: stringParam(params?["cursor"]), total: total)
        let effectiveLimit = min(max(intParam(params?["limit"], defaultValue: total), 1), max(total, 1))
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

        let serverNames = runtimeConfig.mcpServers.keys.sorted()
        let total = serverNames.count
        let start = try mcpServerStatusStart(cursor: stringParam(params?["cursor"]), total: total)
        let effectiveLimit = min(max(intParam(params?["limit"], defaultValue: total), 1), max(total, 1))
        let end = min(start + effectiveLimit, total)
        let statuses = McpAuthStatusResolver.authStatuses(
            for: runtimeConfig.mcpServers,
            codexHome: configuration.codexHome,
            storeMode: runtimeConfig.mcpOAuthCredentialsStoreMode
        )
        let data = (start < end ? Array(serverNames[start..<end]) : []).map { name in
            mcpServerStatusObject(name: name, authStatus: statuses[name] ?? .unsupported)
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

    fileprivate static func mcpServerRefreshResult() -> [String: Any] {
        [:]
    }

    fileprivate static func mcpResourceReadResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        if params?["threadId"] != nil {
            _ = try materializedThreadID(params: params, configuration: configuration)
        }
        guard let server = stringParam(params?["server"]), !server.isEmpty else {
            throw AppServerError.invalidRequest("missing server")
        }
        guard let uri = stringParam(params?["uri"]), !uri.isEmpty else {
            throw AppServerError.invalidRequest("missing uri")
        }
        throw AppServerError.internalError("MCP resource read is not implemented for server \(server)")
    }

    fileprivate static func mcpServerToolCallResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        _ = try materializedThreadID(params: params, configuration: configuration)
        guard let server = stringParam(params?["server"]), !server.isEmpty else {
            throw AppServerError.invalidRequest("missing server")
        }
        guard let tool = stringParam(params?["tool"]), !tool.isEmpty else {
            throw AppServerError.invalidRequest("missing tool")
        }
        throw AppServerError.internalError("MCP tool call is not implemented for server \(server) tool \(tool)")
    }

    fileprivate static func mcpServerOAuthLoginResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration,
        notificationSink: AppServerNotificationSink?
    ) throws -> [String: Any] {
        guard let name = stringParam(params?["name"]) else {
            throw AppServerError.invalidRequest("missing name")
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

        let scopes = stringArrayParam(params?["scopes"]) ?? []
        let timeoutSeconds: Int?
        if params?["timeoutSecs"] != nil {
            timeoutSeconds = intParam(params?["timeoutSecs"], defaultValue: 0)
        } else if params?["timeout_secs"] != nil {
            timeoutSeconds = intParam(params?["timeout_secs"], defaultValue: 0)
        } else {
            timeoutSeconds = nil
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
                        scopes: scopes,
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

    fileprivate static func threadGoalUpdatedNotification(threadID: String, goal: [String: Any]) -> [String: Any] {
        [
            "method": "thread/goal/updated",
            "params": [
                "threadId": threadID,
                "turnId": NSNull(),
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
        [
            "method": "turn/completed",
            "params": [
                "threadId": threadID,
                "turn": [
                    "id": turnID,
                    "items": [],
                    "status": status,
                    "error": NSNull()
                ]
            ]
        ]
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
        let cwds = rawCwds.isEmpty ? [FileManager.default.currentDirectoryPath] : rawCwds
        let configRules = (try? CodexConfigLayerLoader.loadConfigLayerStack(
            codexHome: configuration.codexHome,
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
        let cwds = rawCwds.isEmpty ? [FileManager.default.currentDirectoryPath] : rawCwds
        let configFile = configuration.codexHome.appendingPathComponent("config.toml", isDirectory: false)
        let hooks = userHookObjects(configFile: configFile)
        return [
            "data": cwds.map { cwd in
                [
                    "cwd": cwd,
                    "hooks": hooks,
                    "warnings": [],
                    "errors": []
                ]
            }
        ]
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
        let effectiveLimit = min(max(intParam(params?["limit"], defaultValue: total), 1), total)
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

    fileprivate static func configReadResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration,
        runtimeFeatureEnablement: [String: Bool] = [:]
    ) throws -> [String: Any] {
        let stack = try CodexConfigLayerLoader.loadConfigLayerStack(
            codexHome: configuration.codexHome,
            overrides: configuration.configLayerOverrides,
            environment: configuration.environment
        )
        let includeLayers = boolParam(params?["includeLayers"], defaultValue: false)
        var response: [String: Any] = [
            "config": configValueObject(
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
        let requirementsPath = configuration.configLayerOverrides.requirementsPath
            ?? CodexConfigLayerLoader.defaultRequirementsTomlFile()
        guard let requirementsPath else {
            return ["requirements": NSNull()]
        }
        guard FileManager.default.fileExists(atPath: requirementsPath.path) else {
            return ["requirements": NSNull()]
        }
        let requirements: ConfigRequirementsToml
        do {
            let contents = try String(contentsOf: requirementsPath, encoding: .utf8)
            requirements = try ConfigRequirementsToml.parse(contents)
        } catch {
            throw AppServerError.internalError("failed to read config requirements: \(error)")
        }
        return [
            "requirements": requirements.isEmpty ? NSNull() : requirements.appServerRequirementsObject()
        ]
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
        let edit = ConfigWriteEdit(
            keyPath: keyPath,
            value: try configWriteValue(params?["value"]),
            mergeStrategy: mergeStrategy
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
                mergeStrategy: mergeStrategy
            )
        }
        return try configWriteResult(
            edits: edits,
            filePath: stringParam(params?["filePath"]),
            expectedVersion: stringParam(params?["expectedVersion"]),
            configuration: configuration
        )
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
        guard let command = stringArrayParam(params?["command"]) else {
            throw AppServerError.invalidRequest("missing command")
        }
        guard !command.isEmpty else {
            throw AppServerError.invalidRequest("command must not be empty")
        }

        let cwd = stringParam(params?["cwd"]).map { URL(fileURLWithPath: $0, isDirectory: true) }
        let timeout = intParam(params?["timeoutMs"] ?? params?["timeout_ms"], defaultValue: 0)
        return try runOneOffCommand(
            command,
            cwd: cwd,
            timeoutMilliseconds: timeout > 0 ? timeout : nil,
            environment: configuration.environment
        )
    }

    fileprivate static func commandExecWriteResult(params: [String: Any]?) throws -> [String: Any] {
        let processID = try commandExecProcessID(params: params)
        let deltaBase64 = stringParam(params?["deltaBase64"])
        let closeStdin = boolParam(params?["closeStdin"], defaultValue: false)
        guard deltaBase64 != nil || closeStdin else {
            throw AppServerError.invalidParams("command/exec/write requires deltaBase64 or closeStdin")
        }
        if let deltaBase64, Data(base64Encoded: deltaBase64) == nil {
            throw AppServerError.invalidParams("invalid deltaBase64: invalid base64 data")
        }
        throw AppServerError.invalidRequest("no active command/exec for process id \"\(processID)\"")
    }

    fileprivate static func commandExecTerminateResult(params: [String: Any]?) throws -> [String: Any] {
        let processID = try commandExecProcessID(params: params)
        throw AppServerError.invalidRequest("no active command/exec for process id \"\(processID)\"")
    }

    fileprivate static func commandExecResizeResult(params: [String: Any]?) throws -> [String: Any] {
        let processID = try commandExecProcessID(params: params)
        guard let size = params?["size"] as? [String: Any],
              let rows = size["rows"] as? Int,
              let cols = size["cols"] as? Int
        else {
            throw AppServerError.invalidParams("command/exec/resize requires size rows and cols")
        }
        guard rows > 0, cols > 0 else {
            throw AppServerError.invalidParams("command/exec size rows and cols must be greater than 0")
        }
        throw AppServerError.invalidRequest("no active command/exec for process id \"\(processID)\"")
    }

    private static func commandExecProcessID(params: [String: Any]?) throws -> String {
        guard let processID = stringParam(params?["processId"]), !processID.isEmpty else {
            throw AppServerError.invalidRequest("missing processId")
        }
        return processID
    }

    fileprivate static func processWriteStdinResult(params: [String: Any]?) throws -> [String: Any] {
        let processHandle = try processHandle(params: params)
        let deltaBase64 = stringParam(params?["deltaBase64"])
        let closeStdin = boolParam(params?["closeStdin"], defaultValue: false)
        guard deltaBase64 != nil || closeStdin else {
            throw AppServerError.invalidParams("process/writeStdin requires deltaBase64 or closeStdin")
        }
        if let deltaBase64, Data(base64Encoded: deltaBase64) == nil {
            throw AppServerError.invalidParams("invalid deltaBase64: invalid base64 data")
        }
        throw AppServerError.invalidRequest("no active process for process handle \"\(processHandle)\"")
    }

    fileprivate static func processSpawnResult(params: [String: Any]?) throws -> [String: Any] {
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
        _ = try absolutePathParam(params?["cwd"], name: "cwd")
        let tty = boolParam(params?["tty"], defaultValue: false)
        if params?["size"] != nil && !tty {
            throw AppServerError.invalidParams("process/spawn size requires tty: true")
        }
        if let size = params?["size"] as? [String: Any] {
            try validateProcessSize(size)
        }
        if let timeoutMs = params?["timeoutMs"] as? Int, timeoutMs < 0 {
            throw AppServerError.invalidParams("process/spawn timeoutMs must be non-negative, got \(timeoutMs)")
        }
        throw AppServerError.invalidRequest("process/spawn live process lifecycle is not implemented")
    }

    fileprivate static func processKillResult(params: [String: Any]?) throws -> [String: Any] {
        let processHandle = try processHandle(params: params)
        throw AppServerError.invalidRequest("no active process for process handle \"\(processHandle)\"")
    }

    fileprivate static func processResizePtyResult(params: [String: Any]?) throws -> [String: Any] {
        let processHandle = try processHandle(params: params)
        guard let size = params?["size"] as? [String: Any],
              let rows = size["rows"] as? Int,
              let cols = size["cols"] as? Int
        else {
            throw AppServerError.invalidParams("process/resizePty requires size rows and cols")
        }
        guard rows > 0, cols > 0 else {
            throw AppServerError.invalidParams("process size rows and cols must be greater than 0")
        }
        throw AppServerError.invalidRequest("no active process for process handle \"\(processHandle)\"")
    }

    private static func validateProcessSize(_ size: [String: Any]) throws {
        guard let rows = size["rows"] as? Int,
              let cols = size["cols"] as? Int
        else {
            throw AppServerError.invalidParams("process/resizePty requires size rows and cols")
        }
        guard rows > 0, cols > 0 else {
            throw AppServerError.invalidParams("process size rows and cols must be greater than 0")
        }
    }

    private static func processHandle(params: [String: Any]?) throws -> String {
        guard let processHandle = stringParam(params?["processHandle"]), !processHandle.isEmpty else {
            throw AppServerError.invalidRequest("missing processHandle")
        }
        return processHandle
    }

    fileprivate static func loginApiKeyResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        guard let apiKey = stringParam(params?["apiKey"]) else {
            throw AppServerError.invalidRequest("missing apiKey")
        }
        if try forcedLoginMethod(configuration: configuration) == "chatgpt" {
            throw AppServerError.invalidRequest("API key login is disabled. Use ChatGPT login instead.")
        }
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
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        let type = stringParam(params?["type"])
        if type == "chatgpt", try forcedLoginMethod(configuration: configuration) == "api" {
            throw AppServerError.invalidRequest("ChatGPT login is disabled. Use API key login instead.")
        }
        guard type == "apiKey" else {
            throw AppServerError.invalidRequest("unsupported account login type: \(type ?? "<missing>")")
        }
        _ = try loginApiKeyResult(params: params, configuration: configuration)
        return ["type": "apiKey"]
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

    fileprivate static func accountLoginCompletedNotification() -> [String: Any] {
        [
            "method": "account/login/completed",
            "params": [
                "loginId": NSNull(),
                "success": true,
                "error": NSNull()
            ].nullStripped(keepNulls: true)
        ]
    }

    fileprivate static func accountUpdatedNotification(configuration: CodexAppServerConfiguration) throws -> [String: Any] {
        [
            "method": "account/updated",
            "params": [
                "authMode": try currentAuth(configuration: configuration)?.method ?? NSNull()
            ].nullStripped(keepNulls: true)
        ]
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

    fileprivate static func forcedLoginMethod(configuration: CodexAppServerConfiguration) throws -> String? {
        let stack = try CodexConfigLayerLoader.loadConfigLayerStack(
            codexHome: configuration.codexHome,
            environment: configuration.environment
        )
        guard let table = configTable(stack.effectiveConfig()) else {
            return nil
        }
        return stringConfig(table, "forced_login_method")
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
        guard let auth = try currentAuth(configuration: configuration) else {
            throw AppServerError.invalidRequest("codex account authentication required to read rate limits")
        }
        guard case .chatGPT = auth.kind else {
            throw AppServerError.invalidRequest("chatgpt authentication required to read rate limits")
        }
        guard let accountID = auth.accountID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !accountID.isEmpty
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

        do {
            let snapshot = try runAsyncBlocking {
                try await configuration.accountRateLimitsFetcher.fetchRateLimits(
                    baseURL: runtimeConfig.chatgptBaseURL,
                    accessToken: auth.token,
                    accountID: accountID
                )
            }
            return [
                "rateLimits": rateLimitSnapshotObject(snapshot)
            ].nullStripped(keepNulls: true)
        } catch let error as AppServerError {
            throw error
        } catch {
            throw AppServerError.internalError("failed to fetch codex rate limits: \(error)")
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
            "primary": rateLimitWindowObject(snapshot.primary),
            "secondary": rateLimitWindowObject(snapshot.secondary),
            "credits": creditsSnapshotObject(snapshot.credits),
            "planType": snapshot.planType?.rawValue ?? NSNull()
        ].nullStripped(keepNulls: true)
    }

    private static func rateLimitWindowObject(_ window: RateLimitWindow?) -> Any {
        guard let window else {
            return NSNull()
        }
        return [
            "usedPercent": window.usedPercent,
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
        turns: [[String: Any]] = []
    ) throws -> [String: Any] {
        let summary = try RolloutSummary(path: item.path, defaultProvider: defaultProvider)
        let updatedAt = item.updatedAt.map(unixSeconds) ?? summary.createdAtUnixSeconds
        return [
            "id": summary.id,
            "sessionId": summary.id,
            "forkedFromId": summary.forkedFromID ?? NSNull(),
            "preview": summary.preview,
            "ephemeral": false,
            "modelProvider": summary.modelProvider,
            "createdAt": summary.createdAtUnixSeconds,
            "updatedAt": updatedAt,
            "status": ["type": "notLoaded"],
            "path": item.path,
            "cwd": summary.cwd,
            "cliVersion": summary.cliVersion,
            "source": appServerSource(summary.source),
            "threadSource": summary.threadSource ?? NSNull(),
            "agentNickname": summary.agentNickname ?? NSNull(),
            "agentRole": summary.agentRole ?? NSNull(),
            "gitInfo": summary.gitInfo ?? NSNull(),
            "name": summary.name ?? NSNull(),
            "turns": turns
        ].nullStripped(keepNulls: true)
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
        configuration: CodexAppServerConfiguration
    ) throws -> String {
        do {
            guard let foundPath = try RolloutListing.findConversationPathByIDString(
                codexHome: configuration.codexHome,
                idString: conversationID.description
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
        switch mode {
        case .dangerFullAccess:
            return .dangerFullAccess
        case .readOnly:
            return .readOnly
        case .workspaceWrite:
            return .newWorkspaceWritePolicy()
        }
    }

    private static func jsonObject<T: Encodable>(_ value: T) throws -> Any {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data)
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

    private static func boolParam(_ value: Any?, defaultValue: Bool) -> Bool {
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

    private static func isValidRemotePluginID(_ pluginID: String) -> Bool {
        !pluginID.isEmpty && pluginID.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_" || character == "~")
        }
    }

    private static func isLikelyLocalPluginID(_ pluginID: String) -> Bool {
        let parts = pluginID.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && !parts[1].isEmpty
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

    private static func modelProviderFilter(_ value: Any?, defaultProvider: String) -> [String]? {
        guard let providers = stringArrayParam(value) else {
            return [defaultProvider]
        }
        return providers.isEmpty ? nil : providers
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

    private struct ParsedUserHookGroup {
        var eventName: HookEventName
        var matcher: String?
        var handlers: [ParsedUserHookHandler] = []
    }

    private struct ParsedUserHookHandler {
        var type: String?
        var command: String?
        var timeoutSec: UInt64?
        var statusMessage: String?
    }

    private static func userHookObjects(configFile: URL) -> [[String: Any]] {
        guard let contents = try? String(contentsOf: configFile, encoding: .utf8) else {
            return []
        }
        let parsed = parseUserHookConfig(contents)
        guard parsed.enabled else {
            return []
        }
        let sourcePath = configFile.standardizedFileURL.path
        var displayOrder: Int64 = 0
        var output: [[String: Any]] = []
        for (groupIndex, group) in parsed.groups.enumerated() {
            for (handlerIndex, handler) in group.handlers.enumerated() {
                guard handler.type == "command", let command = handler.command else {
                    continue
                }
                let timeoutSec = handler.timeoutSec ?? 600
                output.append([
                    "key": HooksProtocol.hookKey(
                        keySource: sourcePath,
                        eventName: group.eventName,
                        groupIndex: groupIndex,
                        handlerIndex: handlerIndex
                    ),
                    "eventName": appServerHookEventName(group.eventName),
                    "handlerType": "command",
                    "matcher": group.matcher as Any? ?? NSNull(),
                    "command": command,
                    "timeoutSec": Int(timeoutSec),
                    "statusMessage": handler.statusMessage as Any? ?? NSNull(),
                    "sourcePath": sourcePath,
                    "source": "user",
                    "pluginId": NSNull(),
                    "displayOrder": displayOrder,
                    "enabled": true,
                    "isManaged": false,
                    "currentHash": userHookHash(
                        eventName: group.eventName,
                        matcher: group.matcher,
                        command: command,
                        timeoutSec: timeoutSec,
                        statusMessage: handler.statusMessage
                    ),
                    "trustStatus": "untrusted"
                ])
                displayOrder += 1
            }
        }
        return output
    }

    private static func parseUserHookConfig(_ contents: String) -> (enabled: Bool, groups: [ParsedUserHookGroup]) {
        var enabled = true
        var groups: [ParsedUserHookGroup] = []
        var table: [String] = []
        var currentGroupIndex: Int?
        var currentHandlerIndex: Int?

        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = stripTomlComment(from: String(rawLine)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("[["), line.hasSuffix("]]") {
                let body = String(line.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                table = body.split(separator: ".").map(String.init)
                currentHandlerIndex = nil
                if table.count == 2, table[0] == "hooks", let eventName = hookEventName(configLabel: table[1]) {
                    groups.append(ParsedUserHookGroup(eventName: eventName))
                    currentGroupIndex = groups.count - 1
                } else if table.count == 3, table[0] == "hooks", table[2] == "hooks",
                          let groupIndex = currentGroupIndex {
                    groups[groupIndex].handlers.append(ParsedUserHookHandler())
                    currentHandlerIndex = groups[groupIndex].handlers.count - 1
                }
                continue
            }

            if line.hasPrefix("["), line.hasSuffix("]") {
                let body = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                table = body.split(separator: ".").map(String.init)
                currentGroupIndex = nil
                currentHandlerIndex = nil
                continue
            }

            guard let equalsIndex = firstEqualsIndex(in: line) else {
                continue
            }
            let key = String(line[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let valueText = String(line[line.index(after: equalsIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)

            if table == ["features"], key == "hooks", valueText == "false" {
                enabled = false
                continue
            }
            guard table.first == "hooks", let groupIndex = currentGroupIndex else {
                continue
            }

            if let handlerIndex = currentHandlerIndex {
                if key == "type" {
                    groups[groupIndex].handlers[handlerIndex].type = tomlString(valueText)
                } else if key == "command" {
                    groups[groupIndex].handlers[handlerIndex].command = tomlString(valueText)
                } else if key == "timeout" || key == "timeoutSec" || key == "timeout_sec" {
                    groups[groupIndex].handlers[handlerIndex].timeoutSec = UInt64(valueText)
                } else if key == "statusMessage" || key == "status_message" {
                    groups[groupIndex].handlers[handlerIndex].statusMessage = tomlString(valueText)
                }
            } else if key == "matcher" {
                groups[groupIndex].matcher = tomlString(valueText)
            }
        }

        return (enabled, groups)
    }

    private static func hookEventName(configLabel: String) -> HookEventName? {
        HookEventName.allCases.first { $0.configLabel == configLabel }
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

    private static func mcpServerStatusObject(name: String, authStatus: McpAuthStatus) -> [String: Any] {
        [
            "name": name,
            "tools": [String: Any](),
            "resources": [Any](),
            "resourceTemplates": [Any](),
            "authStatus": authStatus.rawValue
        ]
    }

    private static func fuzzyFileSearch(query: String, root: String) -> [[String: Any]] {
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
        timeoutMilliseconds: Int?,
        environment: [String: String]
    ) throws -> [String: Any] {
        let process = Process()
        if command[0].contains("/") {
            process.executableURL = URL(fileURLWithPath: command[0])
            process.arguments = Array(command.dropFirst())
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = command
        }
        if let cwd {
            process.currentDirectoryURL = cwd
        }
        process.environment = environment

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
        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        var stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if timedOut, stderr.isEmpty {
            stderr = "command timed out"
        }
        return [
            "exitCode": timedOut ? -1 : Int(process.terminationStatus),
            "stdout": stdout,
            "stderr": stderr
        ]
    }

    private static func loadSkills(cwd: URL, codexHome: URL) -> SkillLoadOutcome {
        var outcome = SkillLoadOutcome()
        for root in skillRoots(cwd: cwd, codexHome: codexHome) {
            discoverSkills(root: root.path, scope: root.scope, outcome: &outcome)
        }

        var seen: Set<String> = []
        outcome.skills = outcome.skills.filter { seen.insert($0.name).inserted }
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
    ) throws {
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
        } catch {
            throw AppServerError.internalError("failed to unarchive thread: \(error)")
        }
        return destinationPath.path
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
                        outcome.skills.append(try parseSkillFile(entry, scope: scope))
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
            "config": configValueObject(layer.config)
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
        for edit in edits {
            try applyConfigWriteEdit(edit, to: &nextConfig)
        }

        try FileManager.default.createDirectory(at: configuration.codexHome, withIntermediateDirectories: true)
        try renderConfigToml(nextConfig).write(to: configFile, atomically: true, encoding: .utf8)

        return [
            "status": "ok",
            "version": ConfigFingerprint.version(for: nextConfig),
            "filePath": allowedPath,
            "overriddenMetadata": NSNull()
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

    private static func applyConfigWriteEdit(_ edit: ConfigWriteEdit, to config: inout ConfigValue) throws {
        let path = edit.keyPath.split(separator: ".").map(String.init)
        guard !path.isEmpty else {
            throw AppServerError.invalidRequestWithData(
                "keyPath must not be empty",
                data: ["config_write_error_code": "configValidationError"]
            )
        }

        if let value = edit.value {
            setConfigValue(value, at: path, mergeStrategy: edit.mergeStrategy, in: &config)
        } else if !removeConfigValue(at: path, in: &config) {
            throw AppServerError.invalidRequestWithData(
                "Path not found",
                data: ["config_write_error_code": "configPathNotFound"]
            )
        }
    }

    private static func setConfigValue(
        _ value: ConfigValue,
        at path: [String],
        mergeStrategy: String,
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
            if mergeStrategy == "upsert",
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

    private static func currentAuth(configuration: CodexAppServerConfiguration) throws -> AppServerAuth? {
        if let apiKey = CodexAuthStorage.readCodexAPIKeyFromEnvironment(configuration.environment)
            ?? CodexAuthStorage.readOpenAIAPIKeyFromEnvironment(configuration.environment) {
            return AppServerAuth(method: "apikey", token: apiKey, accountID: nil, kind: .apiKey)
        }

        guard let auth = try CodexAuthStorage.loadAuthDotJSON(
            codexHome: configuration.codexHome,
            mode: configuration.authCredentialsStoreMode
        ) else {
            return nil
        }
        if let apiKey = auth.openAIAPIKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AppServerAuth(method: "apikey", token: apiKey, accountID: nil, kind: .apiKey)
        }
        if let tokens = auth.tokens, !tokens.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AppServerAuth(
                method: "chatgpt",
                token: tokens.accessToken,
                accountID: tokens.accountID ?? tokens.idToken.chatGPTAccountID,
                kind: .chatGPT(tokens.idToken)
            )
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
    case methodNotFound(String)
    case internalError(String)

    var description: String {
        switch self {
        case let .invalidRequest(message), let .invalidParams(message), let .invalidRequestWithData(message, _):
            return message
        case let .methodNotFound(message):
            return message
        case let .internalError(message):
            return message
        }
    }

    var data: [String: String]? {
        switch self {
        case let .invalidRequestWithData(_, data):
            return data
        case .invalidRequest, .invalidParams, .methodNotFound, .internalError:
            return nil
        }
    }
}

private struct ConfigWriteEdit {
    let keyPath: String
    let value: ConfigValue?
    let mergeStrategy: String
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
    let rolloutPath: URL
    let model: String
    let modelProvider: String
    let cwd: URL
    let approvalPolicy: AskForApproval
    let sandbox: SandboxPolicy
    let reasoningEffort: String?
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

final class CodexAppServerMessageProcessor {
    private let connectionID: AppServerConnectionID = 0
    private var initialized = false
    private var requestAttestation = false
    private var experimentalAPIEnabled = false
    private var userAgent: String
    private let configuration: CodexAppServerConfiguration
    private let notificationSink: AppServerNotificationSink?
    private let threadStateManager: AppServerThreadStateManager
    private let outgoingRequestBroker: AppServerOutgoingRequestBroker
    private var activeChatGPTLogins: [UUID: ChatGPTLoginServer] = [:]
    private var runtimeFeatureEnablement: [String: Bool] = [:]
    private var fsWatches: [String: AppServerFSWatch] = [:]

    init(
        configuration: CodexAppServerConfiguration,
        notificationSink: AppServerNotificationSink? = nil,
        threadStateManager: AppServerThreadStateManager = AppServerThreadStateManager(),
        outgoingRequestBroker: AppServerOutgoingRequestBroker? = nil
    ) {
        self.configuration = configuration
        self.notificationSink = notificationSink
        self.threadStateManager = threadStateManager
        self.outgoingRequestBroker = outgoingRequestBroker ?? AppServerOutgoingRequestBroker(notificationSink: notificationSink)
        self.userAgent = CodexAppServer.buildUserAgent(configuration: configuration, params: nil)
    }

    deinit {
        for server in activeChatGPTLogins.values {
            server.cancel()
        }
        for watch in fsWatches.values {
            watch.cancel()
        }
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

    private func markCurrentConnectionInitialized(requestAttestation: Bool) {
        let manager = threadStateManager
        let connectionID = connectionID
        _ = try? CodexAppServer.runAsyncBlocking {
            await manager.connectionInitialized(
                connectionID,
                capabilities: AppServerConnectionCapabilities(requestAttestation: requestAttestation)
            )
        }
    }

    private func subscribeCurrentConnection(toThreadID threadID: String) {
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

    private func startChatGptLogin() throws -> (loginID: UUID, authURL: String) {
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
                originator: configuration.originator
            ))
        } catch {
            throw AppServerError.internalError("failed to start login server: \(error)")
        }
        for active in activeChatGPTLogins.values {
            active.cancel()
        }
        activeChatGPTLogins.removeAll()
        let loginID = UUID()
        activeChatGPTLogins[loginID] = server
        return (loginID, server.authURL)
    }

    private func loginChatGptResult() throws -> [String: Any] {
        let started = try startChatGptLogin()
        return [
            "loginId": started.loginID.uuidString.lowercased(),
            "authUrl": started.authURL
        ]
    }

    private func loginChatGptAccountResult() throws -> [String: Any] {
        let started = try startChatGptLogin()
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
        guard let server = activeChatGPTLogins.removeValue(forKey: loginID) else {
            throw AppServerError.invalidRequest("login id not found: \(loginIDString)")
        }
        server.cancel()
        return [:]
    }

    private func cancelLoginAccountResult(params: [String: Any]?) throws -> [String: Any] {
        guard let loginIDString = CodexAppServer.stringParam(params?["loginId"]) else {
            throw AppServerError.invalidRequest("missing loginId")
        }
        guard let loginID = UUID(uuidString: loginIDString) else {
            throw AppServerError.invalidRequest("invalid login id: \(loginIDString)")
        }
        if let server = activeChatGPTLogins.removeValue(forKey: loginID) {
            server.cancel()
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
        var response: [String: Any]
        var notifications: [[String: Any]] = []
        if method == "initialize" {
            if initialized {
                response = CodexAppServer.errorObject(id: id, code: -32600, message: "Already initialized")
            } else {
                initialized = true
                let capabilities = params?["capabilities"] as? [String: Any]
                requestAttestation = (capabilities?["requestAttestation"] as? Bool) ?? false
                experimentalAPIEnabled = (capabilities?["experimentalApi"] as? Bool) ?? false
                markCurrentConnectionInitialized(requestAttestation: requestAttestation)
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
                    let result = try CodexAppServer.threadStartResult(params: params, configuration: configuration)
                    response = CodexAppServer.responseObject(id: id, result: result)
                    if let thread = result["thread"] as? [String: Any] {
                        if let threadID = thread["id"] as? String {
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
                        result: try CodexAppServer.threadReadResult(params: params, configuration: configuration)
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
                        result: try CodexAppServer.threadTurnsListResult(params: params, configuration: configuration)
                    )
                case "thread/turns/items/list":
                    response = CodexAppServer.errorObject(
                        id: id,
                        code: -32601,
                        message: "thread/turns/items/list is not supported yet"
                    )
                case "thread/resume":
                    let result = try CodexAppServer.threadResumeResult(params: params, configuration: configuration)
                    response = CodexAppServer.responseObject(id: id, result: result)
                    if let thread = result["thread"] as? [String: Any],
                       let threadID = thread["id"] as? String {
                        subscribeCurrentConnection(toThreadID: threadID)
                    }
                case "thread/fork":
                    let result = try CodexAppServer.threadForkResult(params: params, configuration: configuration)
                    response = CodexAppServer.responseObject(id: id, result: result)
                    if let thread = result["thread"] as? [String: Any] {
                        if let threadID = thread["id"] as? String {
                            subscribeCurrentConnection(toThreadID: threadID)
                        }
                        var notificationThread = thread
                        notificationThread["turns"] = []
                        notifications.append(CodexAppServer.threadStartedNotification(thread: notificationThread))
                    }
                case "turn/start":
                    let result = try CodexAppServer.turnStartResult(params: params, configuration: configuration)
                    response = CodexAppServer.responseObject(id: id, result: result)
                    if let threadID = params?["threadId"] as? String,
                       let turn = result["turn"] as? [String: Any] {
                        notifications.append(CodexAppServer.turnStartedNotification(threadID: threadID, turn: turn))
                    }
                case "turn/interrupt":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.turnInterruptResult(params: params, configuration: configuration)
                    )
                    if let threadID = params?["threadId"] as? String,
                       let turnID = params?["turnId"] as? String {
                        notifications.append(CodexAppServer.turnCompletedNotification(
                            threadID: threadID,
                            turnID: turnID,
                            status: "interrupted"
                        ))
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
                    let archivedThreadID = CodexAppServer.stringParam(params?["threadId"])
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.threadArchiveResult(params: params, configuration: configuration)
                    )
                    if let archivedThreadID,
                       let normalizedThreadID = (try? ConversationId(string: archivedThreadID))?.description {
                        notifications.append(CodexAppServer.threadArchivedNotification(threadID: normalizedThreadID))
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
                    let result = try CodexAppServer.threadGoalSetResult(params: params, configuration: configuration)
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
                        result: try CodexAppServer.threadGoalGetResult(params: params, configuration: configuration)
                    )
                case "thread/goal/clear":
                    let result = try CodexAppServer.threadGoalClearResult(params: params, configuration: configuration)
                    response = CodexAppServer.responseObject(id: id, result: result.result)
                    if result.cleared {
                        notifications.append(CodexAppServer.threadGoalClearedNotification(threadID: result.threadID))
                    }
                case "thread/memoryMode/set":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.threadMemoryModeSetResult(params: params, configuration: configuration)
                    )
                case "memory/reset":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.memoryResetResult(configuration: configuration)
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
                        result: try CodexAppServer.appListResult(params: params)
                    )
                case "plugin/list":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.pluginListResult(params: params)
                    )
                case "plugin/read":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.pluginReadResult(params: params)
                    )
                case "plugin/skill/read":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.pluginSkillReadResult(params: params)
                    )
                case "plugin/share/save":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.pluginShareSaveResult(params: params)
                    )
                case "plugin/share/updateTargets":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.pluginShareUpdateTargetsResult(params: params)
                    )
                case "plugin/share/list":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.pluginShareListResult(params: params)
                    )
                case "plugin/share/delete":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.pluginShareDeleteResult(params: params)
                    )
                case "plugin/install":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.pluginInstallResult(params: params)
                    )
                case "plugin/uninstall":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.pluginUninstallResult(params: params)
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
                        result: try CodexAppServer.accountRateLimitsResult(configuration: configuration)
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
                        result: CodexAppServer.mcpServerRefreshResult()
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
                        result: CodexAppServer.externalAgentConfigDetectResult(params: params)
                    )
                case "externalAgentConfig/import":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.externalAgentConfigImportResult(params: params)
                    )
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
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.experimentalFeatureEnablementSetResult(
                            params: params,
                            runtimeFeatureEnablement: &runtimeFeatureEnablement
                        )
                    )
                case "collaborationMode/list":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: CodexAppServer.collaborationModeListResult()
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
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.configBatchWriteResult(params: params, configuration: configuration)
                    )
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
                case "command/exec", "execOneOffCommand":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.commandExecResult(
                            params: params,
                            configuration: configuration
                        )
                    )
                case "command/exec/write":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.commandExecWriteResult(params: params)
                    )
                case "command/exec/resize":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.commandExecResizeResult(params: params)
                    )
                case "command/exec/terminate":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.commandExecTerminateResult(params: params)
                    )
                case "process/spawn":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.processSpawnResult(params: params)
                    )
                case "process/writeStdin":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.processWriteStdinResult(params: params)
                    )
                case "process/resizePty":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.processResizePtyResult(params: params)
                    )
                case "process/kill":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.processKillResult(params: params)
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
                    if CodexAppServer.stringParam(params?["type"]) == "chatgpt" {
                        response = CodexAppServer.responseObject(
                            id: id,
                            result: try loginChatGptAccountResult()
                        )
                    } else {
                        response = CodexAppServer.responseObject(
                            id: id,
                            result: try CodexAppServer.loginAccountResult(params: params, configuration: configuration)
                        )
                        notifications.append(CodexAppServer.accountLoginCompletedNotification())
                        notifications.append(try CodexAppServer.accountUpdatedNotification(configuration: configuration))
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
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.logoutResult(configuration: configuration)
                    )
                    notifications.append(try CodexAppServer.accountUpdatedNotification(configuration: configuration))
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
                case .invalidParams:
                    response = CodexAppServer.errorObject(id: id, code: -32602, message: error.description)
                case .methodNotFound:
                    response = CodexAppServer.errorObject(id: id, code: -32601, message: error.description)
                case .internalError:
                    response = CodexAppServer.errorObject(id: id, code: -32603, message: error.description)
                }
            } catch {
                response = CodexAppServer.errorObject(id: id, code: -32603, message: String(describing: error))
            }
        }
        return CodexAppServer.encodeMessages([response] + notifications)
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

private func turnItemsView(_ rawValue: Any?) -> AppServerTurnItemsView {
    guard let value = CodexAppServer.stringParam(rawValue) else {
        return .summary
    }
    return AppServerTurnItemsView(rawValue: value) ?? .summary
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
    sortDirection: String?
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

    let descending = sortDirection != "asc"
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
            case .compacted,
                 .turnContext,
                 .eventMsg:
                continue
            }
            if meta != nil, !preview.isEmpty {
                break
            }
        }

        guard let meta else {
            throw RolloutRecorderError.missingConversationID
        }

        self.id = meta.meta.id.description
        self.forkedFromID = meta.meta.forkedFromID?.description
        self.preview = preview
        self.modelProvider = meta.meta.modelProvider ?? defaultProvider
        self.createdAtUnixSeconds = Self.unixSeconds(meta.meta.timestamp)
        self.cwd = meta.meta.cwd
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
