import Foundation

public enum CodexConfigDefaults {
    public static let chatgptBaseURL = "https://chatgpt.com/backend-api/"
    public static let modelProviderID = "openai"
    public static let projectRootMarkers = [".git"]
    public static let projectDocMaxBytes = 32 * 1024
}

public struct CodexRuntimeConfig: Equatable, Sendable {
    public var model: String?
    public var modelProvider: String?
    public var modelProviders: [String: ModelProviderInfo]
    public var approvalPolicy: AskForApproval?
    public var sandboxMode: SandboxMode?
    public var modelReasoningEffort: ReasoningEffort?
    public var modelReasoningSummary: ReasoningSummary?
    public var modelVerbosity: Verbosity?
    public var chatgptBaseURL: String
    public var cliAuthCredentialsStoreMode: AuthCredentialsStoreMode
    public var forcedLoginMethod: ForcedLoginMethod?
    public var forcedChatGPTWorkspaceID: String?
    public var experimentalInstructionsFile: String?
    public var experimentalCompactPromptFile: String?
    public var baseInstructions: String?
    public var developerInstructions: String?
    public var compactPrompt: String?
    public var includeApplyPatchTool: Bool?
    public var experimentalUseUnifiedExecTool: Bool?
    public var experimentalUseFreeformApplyPatch: Bool?
    public var toolsWebSearch: Bool?
    public var toolsViewImage: Bool?
    public var features: FeatureStates
    public var mcpServers: [String: McpServerConfig]
    public var mcpOAuthCredentialsStoreMode: OAuthCredentialsStoreMode
    public var activeProfile: String?
    public var projectRootMarkers: [String]
    public var projectDocMaxBytes: Int
    public var projectDocFallbackFilenames: [String]
    public var toolOutputTokenLimit: Int?
    public var ossProvider: String?

    public init(
        model: String? = nil,
        modelProvider: String? = nil,
        modelProviders: [String: ModelProviderInfo] = [:],
        approvalPolicy: AskForApproval? = nil,
        sandboxMode: SandboxMode? = nil,
        modelReasoningEffort: ReasoningEffort? = nil,
        modelReasoningSummary: ReasoningSummary? = nil,
        modelVerbosity: Verbosity? = nil,
        chatgptBaseURL: String = CodexConfigDefaults.chatgptBaseURL,
        cliAuthCredentialsStoreMode: AuthCredentialsStoreMode = .file,
        forcedLoginMethod: ForcedLoginMethod? = nil,
        forcedChatGPTWorkspaceID: String? = nil,
        experimentalInstructionsFile: String? = nil,
        experimentalCompactPromptFile: String? = nil,
        baseInstructions: String? = nil,
        developerInstructions: String? = nil,
        compactPrompt: String? = nil,
        includeApplyPatchTool: Bool? = nil,
        experimentalUseUnifiedExecTool: Bool? = nil,
        experimentalUseFreeformApplyPatch: Bool? = nil,
        toolsWebSearch: Bool? = nil,
        toolsViewImage: Bool? = nil,
        features: FeatureStates = .withDefaults(),
        mcpServers: [String: McpServerConfig] = [:],
        mcpOAuthCredentialsStoreMode: OAuthCredentialsStoreMode = .auto,
        activeProfile: String? = nil,
        projectRootMarkers: [String] = CodexConfigDefaults.projectRootMarkers,
        projectDocMaxBytes: Int = CodexConfigDefaults.projectDocMaxBytes,
        projectDocFallbackFilenames: [String] = [],
        toolOutputTokenLimit: Int? = nil,
        ossProvider: String? = nil
    ) {
        self.model = model
        self.modelProvider = modelProvider
        self.modelProviders = modelProviders
        self.approvalPolicy = approvalPolicy
        self.sandboxMode = sandboxMode
        self.modelReasoningEffort = modelReasoningEffort
        self.modelReasoningSummary = modelReasoningSummary
        self.modelVerbosity = modelVerbosity
        self.chatgptBaseURL = chatgptBaseURL
        self.cliAuthCredentialsStoreMode = cliAuthCredentialsStoreMode
        self.forcedLoginMethod = forcedLoginMethod
        self.forcedChatGPTWorkspaceID = forcedChatGPTWorkspaceID
        self.experimentalInstructionsFile = experimentalInstructionsFile
        self.experimentalCompactPromptFile = experimentalCompactPromptFile
        self.baseInstructions = baseInstructions
        self.developerInstructions = developerInstructions
        self.compactPrompt = compactPrompt
        self.includeApplyPatchTool = includeApplyPatchTool
        self.experimentalUseUnifiedExecTool = experimentalUseUnifiedExecTool
        self.experimentalUseFreeformApplyPatch = experimentalUseFreeformApplyPatch
        self.toolsWebSearch = toolsWebSearch
        self.toolsViewImage = toolsViewImage
        self.features = features
        self.mcpServers = mcpServers
        self.mcpOAuthCredentialsStoreMode = mcpOAuthCredentialsStoreMode
        self.activeProfile = activeProfile
        self.projectRootMarkers = projectRootMarkers
        self.projectDocMaxBytes = projectDocMaxBytes
        self.projectDocFallbackFilenames = projectDocFallbackFilenames
        self.toolOutputTokenLimit = toolOutputTokenLimit
        self.ossProvider = ossProvider
    }

    public var selectedModelProviderID: String {
        modelProvider ?? CodexConfigDefaults.modelProviderID
    }

    public var selectedModelProvider: ModelProviderInfo? {
        modelProviders[selectedModelProviderID]
    }
}

public enum CodexConfigLoadError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidStringValue(String)
    case invalidBoolValue(String)
    case invalidAuthCredentialsStoreMode
    case invalidOAuthCredentialsStoreMode
    case invalidForcedLoginMethod
    case invalidProjectRootMarkers
    case modelProviderNotFound(String)
    case invalidConfigLine(String)
    case invalidTableHeader(String)
    case profileNotFound(String)

    public var description: String {
        switch self {
        case let .invalidStringValue(key):
            return "Invalid value for \(key): expected string"
        case let .invalidBoolValue(key):
            return "Invalid value for \(key): expected bool"
        case .invalidAuthCredentialsStoreMode:
            return "Invalid override value for cli_auth_credentials_store"
        case .invalidOAuthCredentialsStoreMode:
            return "Invalid override value for mcp_oauth_credentials_store"
        case .invalidForcedLoginMethod:
            return "Invalid override value for forced_login_method"
        case .invalidProjectRootMarkers:
            return "project_root_markers must be an array of strings"
        case let .modelProviderNotFound(providerID):
            return "Model provider `\(providerID)` not found"
        case let .invalidConfigLine(line):
            return "Invalid config line: \(line)"
        case let .invalidTableHeader(header):
            return "Invalid TOML table header: \(header)"
        case let .profileNotFound(profile):
            return "config profile `\(profile)` not found"
        }
    }
}

public enum CodexConfigLoader {
    public static func defaultSystemConfigFile() -> URL? {
        URL(fileURLWithPath: "/etc/codex/config.toml", isDirectory: false)
    }

    public static func load(
        codexHome: URL,
        cwd: URL? = nil,
        overrides: CliConfigOverrides = CliConfigOverrides(),
        fileManager: FileManager = .default,
        systemConfigFile: URL? = defaultSystemConfigFile(),
        managedConfigOverrides: ConfigLayerLoaderOverrides = ConfigLayerLoaderOverrides(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> CodexRuntimeConfig {
        var parsed = ParsedCodexConfigToml()
        for configFile in baseConfigLayerFiles(
            codexHome: codexHome,
            systemConfigFile: systemConfigFile
        ) {
            if fileManager.fileExists(atPath: configFile.path) {
                let contents = try String(contentsOf: configFile, encoding: .utf8)
                parsed.merge(try ParsedCodexConfigToml.parse(
                    contents,
                    baseURL: configFile.deletingLastPathComponent()
                ))
            }
        }

        if let cwd {
            let projectRootMarkers = try parsed.projectRootMarkersForDiscovery()
            for configFile in projectConfigFiles(
                cwd: cwd,
                projectRootMarkers: projectRootMarkers,
                fileManager: fileManager
            ) {
                if fileManager.fileExists(atPath: configFile.path) {
                    let contents = try String(contentsOf: configFile, encoding: .utf8)
                    parsed.merge(try ParsedCodexConfigToml.parse(
                        contents,
                        baseURL: configFile.deletingLastPathComponent()
                    ))
                }
            }
        }

        try parsed.apply(overrides: overrides)
        let managedConfigLayers = try CodexConfigLayerLoader.loadConfigLayers(
            codexHome: codexHome,
            overrides: managedConfigOverrides,
            environment: environment,
            fileManager: fileManager
        )
        try parsed.merge(managedConfigLayers)

        var requirementsToml = ConfigRequirementsToml()
        if let requirementsPath = managedConfigOverrides.requirementsPath
            ?? CodexConfigLayerLoader.defaultRequirementsTomlFile()
        {
            try CodexConfigLayerLoader.loadRequirementsToml(
                into: &requirementsToml,
                from: requirementsPath,
                fileManager: fileManager
            )
        }
        try CodexConfigLayerLoader.loadRequirementsFromLegacyScheme(
            into: &requirementsToml,
            loadedConfigLayers: managedConfigLayers
        )

        var config = try parsed.resolvedConfig(environment: environment)
        try applyRequirements(try requirementsToml.requirements(), to: &config)
        return config
    }

    private static func applyRequirements(
        _ requirements: ConfigRequirements,
        to config: inout CodexRuntimeConfig
    ) throws {
        let approvalPolicy = config.approvalPolicy ?? AskForApproval.defaultValue
        try requirements.approvalPolicy.canSet(approvalPolicy).get()

        let sandboxPolicy = sandboxPolicy(for: config.sandboxMode ?? .readOnly)
        try requirements.sandboxPolicy.canSet(sandboxPolicy).get()
    }

    private static func sandboxPolicy(for mode: SandboxMode) -> SandboxPolicy {
        switch mode {
        case .readOnly:
            return .readOnly
        case .workspaceWrite:
            return .newWorkspaceWritePolicy()
        case .dangerFullAccess:
            return .dangerFullAccess
        }
    }

    private static func baseConfigLayerFiles(
        codexHome: URL,
        systemConfigFile: URL?
    ) -> [URL] {
        var files: [URL] = []
        if let systemConfigFile {
            files.append(systemConfigFile)
        }
        files.append(codexHome.appendingPathComponent("config.toml", isDirectory: false))
        return files
    }

    private static func projectConfigFiles(
        cwd: URL,
        projectRootMarkers: [String],
        fileManager: FileManager
    ) -> [URL] {
        let cwdPath = cwd.standardizedFileURL.path
        let cwdURL = URL(fileURLWithPath: cwdPath, isDirectory: true)
        let ancestors = ancestorDirectories(from: cwdURL)
        let projectRoot: URL
        if projectRootMarkers.isEmpty {
            projectRoot = cwdURL
        } else {
            projectRoot = ancestors.first { ancestor in
                projectRootMarkers.contains { marker in
                    fileManager.fileExists(atPath: ancestor.appendingPathComponent(marker).path)
                }
            } ?? cwdURL
        }

        guard let projectRootIndex = ancestors.firstIndex(of: projectRoot),
              let cwdIndex = ancestors.firstIndex(of: cwdURL)
        else {
            return []
        }

        let dirs = ancestors[cwdIndex...projectRootIndex].reversed()
        return dirs.compactMap { directory in
            let dotCodex = directory.appendingPathComponent(".codex", isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: dotCodex.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                return nil
            }
            return dotCodex.appendingPathComponent("config.toml", isDirectory: false)
        }
    }

    private static func ancestorDirectories(from url: URL) -> [URL] {
        var directories: [URL] = []
        var current = url.standardizedFileURL
        while true {
            directories.append(current)
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                break
            }
            current = parent
        }
        return directories
    }
}

private struct ParsedCodexConfigToml {
    var topLevel: [String: ConfigValue] = [:]
    var profiles: [String: [String: ConfigValue]] = [:]
    var features: [String: Bool] = [:]
    var profileFeatures: [String: [String: Bool]] = [:]
    var mcpServers: [String: McpServerConfig] = [:]
    var modelProviders: [String: ConfigValue] = [:]

    static func parse(_ contents: String, baseURL: URL? = nil) throws -> ParsedCodexConfigToml {
        var parsed = ParsedCodexConfigToml()
        var section = ConfigSection.topLevel

        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = stripComment(from: String(rawLine)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("[") {
                section = try parseSectionHeader(line)
                if case let .profile(name) = section {
                    if parsed.profiles[name] == nil {
                        parsed.profiles[name] = [:]
                    }
                }
                if case let .profileFeatures(name) = section {
                    if parsed.profiles[name] == nil {
                        parsed.profiles[name] = [:]
                    }
                }
                continue
            }

            guard let equalsIndex = firstEqualsIndex(in: line) else {
                if case .ignored = section {
                    continue
                }
                throw CodexConfigLoadError.invalidConfigLine(line)
            }

            let key = String(line[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let valueStart = line.index(after: equalsIndex)
            let valueText = String(line[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)

            switch section {
            case .topLevel:
                if key == "model_providers" {
                    try parsed.mergeModelProviders(from: ConfigValueParser.parseTomlLiteral(valueText), key: key)
                    continue
                }
                guard isRelevantTopLevelKey(key) else { continue }
                parsed.topLevel[key] = try normalizePathLikeValue(
                    ConfigValueParser.parseTomlLiteral(valueText),
                    key: key,
                    baseURL: baseURL
                )
            case let .profile(name):
                guard isRelevantProfileKey(key) else { continue }
                parsed.profiles[name, default: [:]][key] = try normalizePathLikeValue(
                    ConfigValueParser.parseTomlLiteral(valueText),
                    key: key,
                    baseURL: baseURL
                )
            case let .modelProvider(name):
                parsed.mergeModelProvider(
                    name: name,
                    overlay: .table([key: try ConfigValueParser.parseTomlLiteral(valueText)])
                )
            case let .modelProviderMap(name, tableKey):
                parsed.mergeModelProvider(
                    name: name,
                    overlay: .table([
                        tableKey: .table([key: try ConfigValueParser.parseTomlLiteral(valueText)])
                    ])
                )
            case .features:
                parsed.features[key] = try Self.boolValue(
                    ConfigValueParser.parseTomlLiteral(valueText),
                    key: "features.\(key)"
                )
            case let .profileFeatures(name):
                parsed.profileFeatures[name, default: [:]][key] = try Self.boolValue(
                    ConfigValueParser.parseTomlLiteral(valueText),
                    key: "profiles.\(name).features.\(key)"
                )
            case .ignored:
                continue
            }
        }

        parsed.mcpServers = try McpConfigStore.parseMcpServers(from: contents)
        return parsed
    }

    private static func normalizePathLikeValue(_ value: ConfigValue, key: String, baseURL: URL?) throws -> ConfigValue {
        guard ["experimental_instructions_file", "experimental_compact_prompt_file"].contains(key),
              let baseURL,
              case let .string(path) = value,
              !(path as NSString).isAbsolutePath
        else {
            return value
        }

        return .string(baseURL.appendingPathComponent(path).standardizedFileURL.path)
    }

    mutating func apply(overrides: CliConfigOverrides) throws {
        for (path, value) in try overrides.parseOverrides() {
            let parts = try Self.parseDottedKey(path)
            guard let first = parts.first else { continue }

            if parts.count == 1, Self.isRelevantTopLevelKey(first) {
                topLevel[first] = value
                continue
            }

            if parts.count == 2, parts[0] == "features" {
                features[parts[1]] = try Self.boolValue(value, key: path)
                continue
            }

            if parts.count == 2, parts[0] == "model_providers" {
                mergeModelProvider(name: parts[1], overlay: value)
                continue
            }

            if parts.count == 3, parts[0] == "model_providers" {
                mergeModelProvider(name: parts[1], overlay: .table([parts[2]: value]))
                continue
            }

            if parts.count == 4, parts[0] == "model_providers", Self.isModelProviderMapKey(parts[2]) {
                mergeModelProvider(name: parts[1], overlay: .table([parts[2]: .table([parts[3]: value])]))
                continue
            }

            if parts.count >= 2, parts[0] == "profiles" {
                if profiles[parts[1]] == nil {
                    profiles[parts[1]] = [:]
                }
            }

            if parts.count == 3, parts[0] == "profiles", Self.isRelevantProfileKey(parts[2]) {
                profiles[parts[1], default: [:]][parts[2]] = value
            }

            if parts.count == 4, parts[0] == "profiles", parts[2] == "features" {
                profileFeatures[parts[1], default: [:]][parts[3]] = try Self.boolValue(value, key: path)
            }
        }
    }

    mutating func merge(_ overlay: ParsedCodexConfigToml) {
        for (key, value) in overlay.topLevel {
            topLevel[key] = value
        }

        for (profileName, profileValues) in overlay.profiles {
            var mergedProfile = profiles[profileName] ?? [:]
            for (key, value) in profileValues {
                mergedProfile[key] = value
            }
            profiles[profileName] = mergedProfile
        }

        for (key, value) in overlay.features {
            features[key] = value
        }

        for (key, value) in overlay.mcpServers {
            mcpServers[key] = value
        }

        for (key, value) in overlay.modelProviders {
            mergeModelProvider(name: key, overlay: value)
        }

        for (profileName, profileValues) in overlay.profileFeatures {
            var mergedProfile = profileFeatures[profileName] ?? [:]
            for (key, value) in profileValues {
                mergedProfile[key] = value
            }
            profileFeatures[profileName] = mergedProfile
        }
    }

    mutating func merge(_ layers: LoadedConfigLayers) throws {
        if let managedConfig = layers.managedConfig {
            try merge(managedConfig.managedConfig)
        }
        if let managedConfigFromMDM = layers.managedConfigFromMDM {
            try merge(managedConfigFromMDM)
        }
    }

    mutating func merge(_ config: ConfigValue) throws {
        guard case let .table(table) = config else {
            return
        }

        for (key, value) in table where Self.isRelevantTopLevelKey(key) {
            topLevel[key] = value
        }

        if let mcpServersValue = table["mcp_servers"] {
            for (key, value) in try McpConfigStore.parseMcpServers(from: mcpServersValue) {
                mcpServers[key] = value
            }
        }

        if let modelProvidersValue = table["model_providers"] {
            try mergeModelProviders(from: modelProvidersValue, key: "model_providers")
        }

        if case let .table(featureTable) = table["features"] {
            for (key, value) in featureTable {
                features[key] = try Self.boolValue(value, key: "features.\(key)")
            }
        }

        if case let .table(profileTable) = table["profiles"] {
            for (profileName, profileValue) in profileTable {
                guard case let .table(profileValues) = profileValue else {
                    continue
                }

                if profiles[profileName] == nil {
                    profiles[profileName] = [:]
                }

                for (key, value) in profileValues {
                    if Self.isRelevantProfileKey(key) {
                        profiles[profileName, default: [:]][key] = value
                        continue
                    }

                    if key == "features", case let .table(featuresTable) = value {
                        for (featureKey, featureValue) in featuresTable {
                            profileFeatures[profileName, default: [:]][featureKey] = try Self.boolValue(
                                featureValue,
                                key: "profiles.\(profileName).features.\(featureKey)"
                            )
                        }
                    }
                }
            }
        }
    }

    func resolvedConfig(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> CodexRuntimeConfig {
        var config = CodexRuntimeConfig()

        try Self.applyRuntimeFields(from: topLevel, to: &config, keyPrefix: "")

        if let authStore = topLevel["cli_auth_credentials_store"] {
            let rawMode = try Self.stringValue(authStore, key: "cli_auth_credentials_store")
            guard let mode = AuthCredentialsStoreMode(rawValue: rawMode) else {
                throw CodexConfigLoadError.invalidAuthCredentialsStoreMode
            }
            config.cliAuthCredentialsStoreMode = mode
        }

        if let forcedLoginMethod = topLevel["forced_login_method"] {
            let rawMethod = try Self.stringValue(forcedLoginMethod, key: "forced_login_method")
            guard let method = ForcedLoginMethod(rawValue: rawMethod) else {
                throw CodexConfigLoadError.invalidForcedLoginMethod
            }
            config.forcedLoginMethod = method
        }

        if let developerInstructions = topLevel["developer_instructions"] {
            config.developerInstructions = try Self.trimmedNonEmptyStringValue(
                developerInstructions,
                key: "developer_instructions"
            )
        }

        if let compactPrompt = topLevel["compact_prompt"] {
            config.compactPrompt = try Self.trimmedNonEmptyStringValue(compactPrompt, key: "compact_prompt")
        }

        if let workspaceID = topLevel["forced_chatgpt_workspace_id"] {
            config.forcedChatGPTWorkspaceID = try Self.stringValue(workspaceID, key: "forced_chatgpt_workspace_id")
        }

        if let projectRootMarkers = topLevel["project_root_markers"] {
            config.projectRootMarkers = try Self.stringArrayValue(projectRootMarkers, key: "project_root_markers")
        }

        if let projectDocMaxBytes = topLevel["project_doc_max_bytes"] {
            config.projectDocMaxBytes = try Self.nonNegativeIntValue(projectDocMaxBytes, key: "project_doc_max_bytes")
        }

        if let fallbackFilenames = topLevel["project_doc_fallback_filenames"] {
            config.projectDocFallbackFilenames = try Self.stringArrayValue(
                fallbackFilenames,
                key: "project_doc_fallback_filenames"
            )
        }

        if let toolOutputTokenLimit = topLevel["tool_output_token_limit"] {
            config.toolOutputTokenLimit = try Self.nonNegativeIntValue(
                toolOutputTokenLimit,
                key: "tool_output_token_limit"
            )
        }

        let activeProfile = try topLevel["profile"].map { try Self.stringValue($0, key: "profile") }
        if let activeProfile {
            guard let profile = profiles[activeProfile] else {
                throw CodexConfigLoadError.profileNotFound(activeProfile)
            }

            config.activeProfile = activeProfile
            try Self.applyRuntimeFields(
                from: profile,
                to: &config,
                keyPrefix: "profiles.\(activeProfile)."
            )
        }

        config.baseInstructions = try config.baseInstructions ?? Self.readNonEmptyFile(
            config.experimentalInstructionsFile,
            description: "experimental instructions file"
        )
        config.compactPrompt = try config.compactPrompt ?? Self.readNonEmptyFile(
            config.experimentalCompactPromptFile,
            description: "experimental compact prompt file"
        )

        var featureStates = FeatureStates.withDefaults()
        featureStates.apply(featureValues: features)
        if let activeProfile = config.activeProfile {
            featureStates.apply(featureValues: profileFeatures[activeProfile] ?? [:])
        }

        let mcpOAuthCredentialsStoreMode: OAuthCredentialsStoreMode
        if let rawStore = topLevel["mcp_oauth_credentials_store"] {
            let rawMode = try Self.stringValue(rawStore, key: "mcp_oauth_credentials_store")
            guard let mode = OAuthCredentialsStoreMode(rawValue: rawMode) else {
                throw CodexConfigLoadError.invalidOAuthCredentialsStoreMode
            }
            mcpOAuthCredentialsStoreMode = mode
        } else {
            mcpOAuthCredentialsStoreMode = .auto
        }

        config.features = featureStates
        config.mcpServers = mcpServers
        config.mcpOAuthCredentialsStoreMode = mcpOAuthCredentialsStoreMode
        config.modelProviders = try Self.combinedModelProviders(from: modelProviders, environment: environment)
        guard config.selectedModelProvider != nil else {
            throw CodexConfigLoadError.modelProviderNotFound(config.selectedModelProviderID)
        }

        return config
    }

    func projectRootMarkersForDiscovery() throws -> [String] {
        guard let value = topLevel["project_root_markers"] else {
            return CodexConfigDefaults.projectRootMarkers
        }
        return try Self.stringArrayValue(value, key: "project_root_markers")
    }

    private mutating func mergeModelProviders(from value: ConfigValue, key: String) throws {
        guard case let .table(providers) = value else {
            throw CodexConfigLoadError.invalidStringValue(key)
        }
        for (name, providerValue) in providers {
            mergeModelProvider(name: name, overlay: providerValue)
        }
    }

    private mutating func mergeModelProvider(name: String, overlay: ConfigValue) {
        guard let existing = modelProviders[name] else {
            modelProviders[name] = overlay
            return
        }
        modelProviders[name] = existing.merging(overlay: overlay)
    }

    private static func combinedModelProviders(
        from configuredProviders: [String: ConfigValue],
        environment: [String: String]
    ) throws -> [String: ModelProviderInfo] {
        var providers = ModelProviderInfo.builtInModelProviders(environment: environment)
        for (name, value) in configuredProviders {
            let provider = try modelProviderInfoValue(value, key: "model_providers.\(name)")
            if providers[name] == nil {
                providers[name] = provider
            }
        }
        return providers
    }

    private static func modelProviderInfoValue(_ value: ConfigValue, key: String) throws -> ModelProviderInfo {
        guard case .table = value else {
            throw CodexConfigLoadError.invalidStringValue(key)
        }

        let data = try JSONEncoder().encode(value)
        do {
            return try JSONDecoder().decode(ModelProviderInfo.self, from: data)
        } catch {
            throw CodexConfigLoadError.invalidConfigLine(key)
        }
    }

    private static func applyRuntimeFields(
        from values: [String: ConfigValue],
        to config: inout CodexRuntimeConfig,
        keyPrefix: String
    ) throws {
        if let model = values["model"] {
            config.model = try stringValue(model, key: "\(keyPrefix)model")
        }
        if let provider = values["model_provider"] {
            config.modelProvider = try stringValue(provider, key: "\(keyPrefix)model_provider")
        }
        if let approvalPolicy = values["approval_policy"] {
            config.approvalPolicy = try stringEnumValue(
                AskForApproval.self,
                approvalPolicy,
                key: "\(keyPrefix)approval_policy"
            )
        }
        if let sandboxMode = values["sandbox_mode"] {
            config.sandboxMode = try stringEnumValue(
                SandboxMode.self,
                sandboxMode,
                key: "\(keyPrefix)sandbox_mode"
            )
        }
        if let effort = values["model_reasoning_effort"] {
            config.modelReasoningEffort = try stringEnumValue(
                ReasoningEffort.self,
                effort,
                key: "\(keyPrefix)model_reasoning_effort"
            )
        }
        if let summary = values["model_reasoning_summary"] {
            config.modelReasoningSummary = try stringEnumValue(
                ReasoningSummary.self,
                summary,
                key: "\(keyPrefix)model_reasoning_summary"
            )
        }
        if let verbosity = values["model_verbosity"] {
            config.modelVerbosity = try stringEnumValue(
                Verbosity.self,
                verbosity,
                key: "\(keyPrefix)model_verbosity"
            )
        }
        if let baseURL = values["chatgpt_base_url"] {
            config.chatgptBaseURL = try stringValue(baseURL, key: "\(keyPrefix)chatgpt_base_url")
        }
        if let instructionsFile = values["experimental_instructions_file"] {
            config.experimentalInstructionsFile = try stringValue(
                instructionsFile,
                key: "\(keyPrefix)experimental_instructions_file"
            )
        }
        if let compactPromptFile = values["experimental_compact_prompt_file"] {
            config.experimentalCompactPromptFile = try stringValue(
                compactPromptFile,
                key: "\(keyPrefix)experimental_compact_prompt_file"
            )
        }
        if let includeApplyPatchTool = values["include_apply_patch_tool"] {
            config.includeApplyPatchTool = try boolValue(
                includeApplyPatchTool,
                key: "\(keyPrefix)include_apply_patch_tool"
            )
        }
        if let unifiedExecTool = values["experimental_use_unified_exec_tool"] {
            config.experimentalUseUnifiedExecTool = try boolValue(
                unifiedExecTool,
                key: "\(keyPrefix)experimental_use_unified_exec_tool"
            )
        }
        if let freeformApplyPatch = values["experimental_use_freeform_apply_patch"] {
            config.experimentalUseFreeformApplyPatch = try boolValue(
                freeformApplyPatch,
                key: "\(keyPrefix)experimental_use_freeform_apply_patch"
            )
        }
        if let webSearch = values["tools_web_search"] {
            config.toolsWebSearch = try boolValue(webSearch, key: "\(keyPrefix)tools_web_search")
        }
        if let viewImage = values["tools_view_image"] {
            config.toolsViewImage = try boolValue(viewImage, key: "\(keyPrefix)tools_view_image")
        }
        if let ossProvider = values["oss_provider"] {
            config.ossProvider = try stringValue(ossProvider, key: "\(keyPrefix)oss_provider")
        }
    }

    private static func isRelevantTopLevelKey(_ key: String) -> Bool {
        key == "model"
            || key == "model_provider"
            || key == "approval_policy"
            || key == "sandbox_mode"
            || key == "model_reasoning_effort"
            || key == "model_reasoning_summary"
            || key == "model_verbosity"
            || key == "chatgpt_base_url"
            || key == "cli_auth_credentials_store"
            || key == "forced_login_method"
            || key == "forced_chatgpt_workspace_id"
            || key == "developer_instructions"
            || key == "compact_prompt"
            || key == "experimental_instructions_file"
            || key == "experimental_compact_prompt_file"
            || key == "include_apply_patch_tool"
            || key == "experimental_use_unified_exec_tool"
            || key == "experimental_use_freeform_apply_patch"
            || key == "tools_web_search"
            || key == "tools_view_image"
            || key == "mcp_oauth_credentials_store"
            || key == "profile"
            || key == "project_root_markers"
            || key == "project_doc_max_bytes"
            || key == "project_doc_fallback_filenames"
            || key == "tool_output_token_limit"
            || key == "oss_provider"
    }

    private static func isRelevantProfileKey(_ key: String) -> Bool {
        key == "model"
            || key == "model_provider"
            || key == "approval_policy"
            || key == "sandbox_mode"
            || key == "model_reasoning_effort"
            || key == "model_reasoning_summary"
            || key == "model_verbosity"
            || key == "chatgpt_base_url"
            || key == "experimental_instructions_file"
            || key == "experimental_compact_prompt_file"
            || key == "include_apply_patch_tool"
            || key == "experimental_use_unified_exec_tool"
            || key == "experimental_use_freeform_apply_patch"
            || key == "tools_web_search"
            || key == "tools_view_image"
            || key == "oss_provider"
    }

    private static func isModelProviderMapKey(_ key: String) -> Bool {
        key == "query_params"
            || key == "http_headers"
            || key == "env_http_headers"
    }

    private static func trimmedNonEmptyStringValue(_ value: ConfigValue, key: String) throws -> String? {
        let trimmed = try stringValue(value, key: key).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func readNonEmptyFile(_ path: String?, description: String) throws -> String? {
        guard let path else {
            return nil
        }

        let contents: String
        do {
            contents = try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            throw ConfigLayerLoadError.readFailed(path: path, message: "Failed to read \(description): \(error)")
        }

        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func stringValue(_ value: ConfigValue, key: String) throws -> String {
        guard case let .string(string) = value else {
            throw CodexConfigLoadError.invalidStringValue(key)
        }
        return string
    }

    private static func boolValue(_ value: ConfigValue, key: String) throws -> Bool {
        guard case let .bool(bool) = value else {
            throw CodexConfigLoadError.invalidBoolValue(key)
        }
        return bool
    }

    private static func stringEnumValue<T: RawRepresentable>(
        _ type: T.Type,
        _ value: ConfigValue,
        key: String
    ) throws -> T where T.RawValue == String {
        let rawValue = try stringValue(value, key: key)
        guard let enumValue = type.init(rawValue: rawValue) else {
            throw CodexConfigLoadError.invalidStringValue(key)
        }
        return enumValue
    }

    private static func stringArrayValue(_ value: ConfigValue, key: String) throws -> [String] {
        guard case let .array(values) = value else {
            if key == "project_root_markers" {
                throw CodexConfigLoadError.invalidProjectRootMarkers
            }
            throw CodexConfigLoadError.invalidStringValue(key)
        }

        var strings: [String] = []
        for value in values {
            guard case let .string(string) = value else {
                if key == "project_root_markers" {
                    throw CodexConfigLoadError.invalidProjectRootMarkers
                }
                throw CodexConfigLoadError.invalidStringValue(key)
            }
            strings.append(string)
        }
        return strings
    }

    private static func nonNegativeIntValue(_ value: ConfigValue, key: String) throws -> Int {
        guard case let .integer(integer) = value, integer >= 0 else {
            throw CodexConfigLoadError.invalidStringValue(key)
        }
        return Int(integer)
    }

    private static func parseSectionHeader(_ line: String) throws -> ConfigSection {
        guard line.hasSuffix("]") else {
            throw CodexConfigLoadError.invalidTableHeader(line)
        }
        let body = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = try parseDottedKey(body)
        if parts.count == 1, parts[0] == "features" {
            return .features
        }
        if parts.count == 2, parts[0] == "model_providers" {
            return .modelProvider(parts[1])
        }
        if parts.count == 3,
           parts[0] == "model_providers",
           isModelProviderMapKey(parts[2])
        {
            return .modelProviderMap(parts[1], parts[2])
        }
        if parts.count == 2, parts[0] == "profiles" {
            return .profile(parts[1])
        }
        if parts.count == 3, parts[0] == "profiles", parts[2] == "features" {
            return .profileFeatures(parts[1])
        }
        return .ignored
    }

    private static func parseDottedKey(_ raw: String) throws -> [String] {
        var parts: [String] = []
        var current = String()
        var quote: Character?
        var previousWasBackslash = false

        for character in raw {
            if let activeQuote = quote {
                current.append(character)
                if character == activeQuote && !previousWasBackslash {
                    quote = nil
                }
                previousWasBackslash = character == "\\" && !previousWasBackslash
                if character != "\\" {
                    previousWasBackslash = false
                }
                continue
            }

            switch character {
            case "\"", "'":
                quote = character
                current.append(character)
            case ".":
                parts.append(try parseKeySegment(current))
                current = ""
            default:
                current.append(character)
            }
        }

        if quote != nil {
            throw CodexConfigLoadError.invalidConfigLine(raw)
        }

        parts.append(try parseKeySegment(current))
        return parts
    }

    private static func parseKeySegment(_ raw: String) throws -> String {
        let segment = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !segment.isEmpty else {
            throw CodexConfigLoadError.invalidConfigLine(raw)
        }
        if segment.hasPrefix("\"") || segment.hasPrefix("'") {
            guard case let .string(value) = try ConfigValueParser.parseTomlLiteral(segment) else {
                throw CodexConfigLoadError.invalidConfigLine(raw)
            }
            return value
        }
        return segment
    }

    private static func stripComment(from line: String) -> String {
        var result = String()
        var quote: Character?
        var previousWasBackslash = false

        for character in line {
            if let activeQuote = quote {
                result.append(character)
                if character == activeQuote && !previousWasBackslash {
                    quote = nil
                }
                previousWasBackslash = character == "\\" && !previousWasBackslash
                if character != "\\" {
                    previousWasBackslash = false
                }
                continue
            }

            switch character {
            case "\"", "'":
                quote = character
                result.append(character)
            case "#":
                return result
            default:
                result.append(character)
            }
        }

        return result
    }

    private static func firstEqualsIndex(in line: String) -> String.Index? {
        var quote: Character?
        var squareDepth = 0
        var braceDepth = 0
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

            switch character {
            case "\"", "'":
                quote = character
            case "[":
                squareDepth += 1
            case "]":
                squareDepth -= 1
            case "{":
                braceDepth += 1
            case "}":
                braceDepth -= 1
            case "=" where squareDepth == 0 && braceDepth == 0:
                return index
            default:
                continue
            }
        }

        return nil
    }
}

private enum ConfigSection {
    case topLevel
    case profile(String)
    case modelProvider(String)
    case modelProviderMap(String, String)
    case features
    case profileFeatures(String)
    case ignored
}
