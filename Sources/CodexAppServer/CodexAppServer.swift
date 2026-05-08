import CodexCore
import Foundation

public struct CodexAppServerConfiguration: Equatable, Sendable {
    public let codexHome: URL
    public let defaultModelProvider: String
    public let originator: String
    public let version: String
    public let requiresOpenAIAuth: Bool
    public let authCredentialsStoreMode: AuthCredentialsStoreMode
    public let environment: [String: String]

    public init(
        codexHome: URL,
        defaultModelProvider: String = "openai",
        originator: String = "codex_swift",
        version: String = "0.0.0",
        requiresOpenAIAuth: Bool = true,
        authCredentialsStoreMode: AuthCredentialsStoreMode = .file,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.codexHome = codexHome
        self.defaultModelProvider = defaultModelProvider
        self.originator = originator
        self.version = version
        self.requiresOpenAIAuth = requiresOpenAIAuth
        self.authCredentialsStoreMode = authCredentialsStoreMode
        self.environment = environment
    }
}

public enum CodexAppServer {
    private static let defaultListLimit = 25
    private static let maxListLimit = 100
    private static let interactiveSessionSources: [SessionSource] = [.cli, .vscode]

    public static func run(
        configuration: CodexAppServerConfiguration,
        stdin: FileHandle = .standardInput,
        stdout: FileHandle = .standardOutput
    ) throws {
        var buffer = Data()
        let processor = CodexAppServerMessageProcessor(configuration: configuration)
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
        let models = availableModels.map { $0.withIsDefault($0.model == defaultModel) }
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

    fileprivate static func authStatusResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
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

    fileprivate static func accountResult(configuration: CodexAppServerConfiguration) throws -> [String: Any] {
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

    fileprivate static func responseObject(id: Any, result: [String: Any]) -> [String: Any] {
        [
            "id": id,
            "result": result
        ]
    }

    fileprivate static func errorObject(id: Any, code: Int, message: String) -> [String: Any] {
        [
            "id": id,
            "error": [
                "code": code,
                "message": message
            ]
        ]
    }

    fileprivate static func encodeResponse(_ response: [String: Any]) -> Data? {
        guard JSONSerialization.isValidJSONObject(response) else {
            return nil
        }
        return try? JSONSerialization.data(withJSONObject: response)
    }

    private static func threadObject(for item: ConversationItem, defaultProvider: String) throws -> [String: Any] {
        let summary = try RolloutSummary(path: item.path, defaultProvider: defaultProvider)
        return [
            "id": summary.id,
            "preview": summary.preview,
            "modelProvider": summary.modelProvider,
            "createdAt": summary.createdAtUnixSeconds,
            "path": item.path,
            "cwd": summary.cwd,
            "cliVersion": summary.cliVersion,
            "source": appServerSource(summary.source),
            "gitInfo": summary.gitInfo as Any,
            "turns": []
        ].nullStripped()
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
        case .subagent, .unknown:
            return "unknown"
        }
    }

    private static func listLimit(_ value: Any?) -> Int {
        min(max(intParam(value, defaultValue: defaultListLimit), 1), maxListLimit)
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

    private static func stringParam(_ value: Any?) -> String? {
        value as? String
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
            "displayName": preset.displayName,
            "description": preset.description,
            "supportedReasoningEfforts": preset.supportedReasoningEfforts.map { effort in
                [
                    "reasoningEffort": effort.effort.rawValue,
                    "description": effort.description
                ]
            },
            "defaultReasoningEffort": preset.defaultReasoningEffort.rawValue,
            "isDefault": preset.isDefault
        ]
    }

    private static func currentAuth(configuration: CodexAppServerConfiguration) throws -> AppServerAuth? {
        if let apiKey = CodexAuthStorage.readCodexAPIKeyFromEnvironment(configuration.environment)
            ?? CodexAuthStorage.readOpenAIAPIKeyFromEnvironment(configuration.environment) {
            return AppServerAuth(method: "apikey", token: apiKey, kind: .apiKey)
        }

        guard let auth = try CodexAuthStorage.loadAuthDotJSON(
            codexHome: configuration.codexHome,
            mode: configuration.authCredentialsStoreMode
        ) else {
            return nil
        }
        if let apiKey = auth.openAIAPIKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AppServerAuth(method: "apikey", token: apiKey, kind: .apiKey)
        }
        if let tokens = auth.tokens, !tokens.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AppServerAuth(method: "chatgpt", token: tokens.accessToken, kind: .chatGPT(tokens.idToken))
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
    let kind: AppServerAuthKind
}

private enum AppServerAuthKind {
    case apiKey
    case chatGPT(IdTokenInfo)
}

private enum AppServerError: Error, CustomStringConvertible {
    case invalidRequest(String)

    var description: String {
        switch self {
        case let .invalidRequest(message):
            return message
        }
    }
}

final class CodexAppServerMessageProcessor {
    private var initialized = false
    private var userAgent: String
    private let configuration: CodexAppServerConfiguration

    init(configuration: CodexAppServerConfiguration) {
        self.configuration = configuration
        self.userAgent = CodexAppServer.buildUserAgent(configuration: configuration, params: nil)
    }

    func processLine(_ data: Data) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"],
              let method = object["method"] as? String
        else {
            return nil
        }

        let params = object["params"] as? [String: Any]
        let response: [String: Any]
        if method == "initialize" {
            if initialized {
                response = CodexAppServer.errorObject(id: id, code: -32600, message: "Already initialized")
            } else {
                initialized = true
                userAgent = CodexAppServer.buildUserAgent(configuration: configuration, params: params)
                response = CodexAppServer.responseObject(id: id, result: [
                    "userAgent": userAgent
                ])
            }
        } else if !initialized {
            response = CodexAppServer.errorObject(id: id, code: -32600, message: "Not initialized")
        } else {
            do {
                switch method {
                case "thread/list":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.threadListResult(params: params, configuration: configuration)
                    )
                case "listConversations":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.listConversationsResult(params: params, configuration: configuration)
                    )
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
                        result: try CodexAppServer.accountResult(configuration: configuration)
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
                default:
                    response = CodexAppServer.errorObject(id: id, code: -32601, message: "method not found: \(method)")
                }
            } catch let error as AppServerError {
                response = CodexAppServer.errorObject(id: id, code: -32600, message: error.description)
            } catch {
                response = CodexAppServer.errorObject(id: id, code: -32603, message: String(describing: error))
            }
        }
        return CodexAppServer.encodeResponse(response)
    }
}

private struct RolloutSummary {
    let id: String
    let preview: String
    let modelProvider: String
    let createdAtUnixSeconds: Int
    let cwd: String
    let cliVersion: String
    let source: SessionSource
    let gitInfo: [String: Any]?
    let v1GitInfo: [String: Any]?

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
        self.preview = preview
        self.modelProvider = meta.meta.modelProvider ?? defaultProvider
        self.createdAtUnixSeconds = Self.unixSeconds(meta.meta.timestamp)
        self.cwd = meta.meta.cwd
        self.cliVersion = meta.meta.cliVersion
        self.source = meta.meta.source
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
        guard case let .message(_, role, content) = item,
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
