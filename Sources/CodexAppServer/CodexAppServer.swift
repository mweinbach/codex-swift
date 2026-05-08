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

private enum AppServerError: Error, CustomStringConvertible {
    case invalidRequest(String)
    case internalError(String)

    var description: String {
        switch self {
        case let .invalidRequest(message):
            return message
        case let .internalError(message):
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
                case "config/read":
                    response = CodexAppServer.responseObject(
                        id: id,
                        result: try CodexAppServer.configReadResult(params: params, configuration: configuration)
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
                case .invalidRequest:
                    response = CodexAppServer.errorObject(id: id, code: -32600, message: error.description)
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
