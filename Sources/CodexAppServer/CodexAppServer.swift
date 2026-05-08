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
    public let activeProfile: String?

    public init(
        codexHome: URL,
        defaultModelProvider: String = "openai",
        originator: String = "codex_swift",
        version: String = "0.0.0",
        requiresOpenAIAuth: Bool = true,
        authCredentialsStoreMode: AuthCredentialsStoreMode = .file,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        activeProfile: String? = nil
    ) {
        self.codexHome = codexHome
        self.defaultModelProvider = defaultModelProvider
        self.originator = originator
        self.version = version
        self.requiresOpenAIAuth = requiresOpenAIAuth
        self.authCredentialsStoreMode = authCredentialsStoreMode
        self.environment = environment
        self.activeProfile = activeProfile
    }
}

public enum CodexAppServer {
    private static let defaultListLimit = 25
    private static let maxListLimit = 100
    private static let fuzzyFileSearchLimitPerRoot = 50
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

        try archiveConversation(conversationID: conversationID, rolloutPath: rolloutPath, configuration: configuration)
        return [:]
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

    fileprivate static func skillsListResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) -> [String: Any] {
        let rawCwds = stringArrayParam(params?["cwds"]) ?? []
        let cwds = rawCwds.isEmpty ? [FileManager.default.currentDirectoryPath] : rawCwds
        return [
            "data": cwds.map { cwd in
                let outcome = loadSkills(
                    cwd: URL(fileURLWithPath: cwd, isDirectory: true),
                    codexHome: configuration.codexHome
                )
                return [
                    "cwd": cwd,
                    "skills": outcome.skills.map(skillObject),
                    "errors": outcome.errors.map(skillErrorObject)
                ]
            }
        ]
    }

    fileprivate static func configReadResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        let stack = try CodexConfigLayerLoader.loadConfigLayerStack(
            codexHome: configuration.codexHome,
            environment: configuration.environment
        )
        let includeLayers = boolParam(params?["includeLayers"], defaultValue: false)
        var response: [String: Any] = [
            "config": configValueObject(stack.effectiveConfig()),
            "origins": metadataObjects(stack.origins())
        ]
        if includeLayers {
            response["layers"] = stack.layersHighToLow().map(layerObject)
        }
        return response
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
        guard type == "apiKey" else {
            throw AppServerError.invalidRequest("ChatGPT login is not yet supported")
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

    private static func forcedLoginMethod(configuration: CodexAppServerConfiguration) throws -> String? {
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
        return trimTrailingBlankLines(lines.joined(separator: "\n")) + "\n"
    }

    private static func renderConfigTable(_ table: [String: ConfigValue], path: [String], lines: inout [String]) {
        let scalarKeys = table.keys.sorted().filter { key in
            if case .table = table[key] { return false }
            return true
        }
        for key in scalarKeys {
            guard let value = table[key] else { continue }
            lines.append("\(tomlKey(key)) = \(tomlLiteral(value))")
        }

        let tableKeys = table.keys.sorted().filter { key in
            if case .table = table[key] { return true }
            return false
        }
        for key in tableKeys {
            guard case let .table(child)? = table[key] else { continue }
            if !lines.isEmpty, lines.last?.isEmpty == false {
                lines.append("")
            }
            let nextPath = path + [key]
            lines.append("[\(nextPath.map(tomlKey).joined(separator: "."))]")
            renderConfigTable(child, path: nextPath, lines: &lines)
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
    case invalidRequestWithData(String, data: [String: String])
    case internalError(String)

    var description: String {
        switch self {
        case let .invalidRequest(message), let .invalidRequestWithData(message, _):
            return message
        case let .internalError(message):
            return message
        }
    }

    var data: [String: String]? {
        switch self {
        case let .invalidRequestWithData(_, data):
            return data
        case .invalidRequest, .internalError:
            return nil
        }
    }
}

private struct ConfigWriteEdit {
    let keyPath: String
    let value: ConfigValue?
    let mergeStrategy: String
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
        var response: [String: Any]
        var notifications: [[String: Any]] = []
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
                case "thread/archive":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.threadArchiveResult(params: params, configuration: configuration)
                    )
                case "listConversations":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.listConversationsResult(params: params, configuration: configuration)
                    )
                case "archiveConversation":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.archiveConversationResult(params: params, configuration: configuration)
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
                case "mcpServerStatus/list":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.mcpServerStatusListResult(params: params, configuration: configuration)
                    )
                case "skills/list":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: CodexAppServer.skillsListResult(params: params, configuration: configuration)
                    )
                case "config/read":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.configReadResult(params: params, configuration: configuration)
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
                case "loginApiKey":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.loginApiKeyResult(params: params, configuration: configuration)
                    )
                    notifications.append(try CodexAppServer.authStatusChangeNotification(configuration: configuration))
                case "logoutChatGpt":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.logoutResult(configuration: configuration)
                    )
                    notifications.append(try CodexAppServer.authStatusChangeNotification(configuration: configuration))
                case "account/login/start":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.loginAccountResult(params: params, configuration: configuration)
                    )
                    notifications.append(CodexAppServer.accountLoginCompletedNotification())
                    notifications.append(try CodexAppServer.accountUpdatedNotification(configuration: configuration))
                case "account/login/cancel":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.cancelLoginAccountResult(params: params)
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
