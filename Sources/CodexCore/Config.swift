import Foundation

public enum CodexConfigDefaults {
    public static let chatgptBaseURL = "https://chatgpt.com/backend-api/"
    public static let modelProviderID = "openai"
    public static let projectRootMarkers = [".git"]
    public static let projectDocMaxBytes = 32 * 1024
}

public enum WebSearchMode: String, Codable, Equatable, Sendable {
    case disabled
    case cached
    case live
}

public enum ThreadStoreConfig: Equatable, Sendable {
    case local
    case inMemory(id: String)
}

public struct RealtimeAudioConfig: Equatable, Sendable {
    public var microphone: String?
    public var speaker: String?

    public init(microphone: String? = nil, speaker: String? = nil) {
        self.microphone = microphone
        self.speaker = speaker
    }
}

public enum RealtimeWsMode: String, Codable, Equatable, Sendable {
    case conversational
    case transcription
}

public enum RealtimeTransport: String, Codable, Equatable, Sendable {
    case webrtc
    case websocket
}

public struct RealtimeConfig: Equatable, Sendable {
    public var version: RealtimeConversationVersion
    public var sessionType: RealtimeWsMode
    public var transport: RealtimeTransport
    public var voice: RealtimeVoice?

    public init(
        version: RealtimeConversationVersion = .v2,
        sessionType: RealtimeWsMode = .conversational,
        transport: RealtimeTransport = .webrtc,
        voice: RealtimeVoice? = nil
    ) {
        self.version = version
        self.sessionType = sessionType
        self.transport = transport
        self.voice = voice
    }
}

public struct CodexRuntimeConfig: Equatable, Sendable {
    public var model: String?
    public var modelProvider: String?
    public var modelProviders: [String: ModelProviderInfo]
    public var approvalPolicy: AskForApproval?
    public var sandboxMode: SandboxMode?
    public var sandboxPolicy: SandboxPolicy?
    public var modelReasoningEffort: ReasoningEffort?
    public var modelReasoningSummary: ReasoningSummary?
    public var modelVerbosity: Verbosity?
    public var serviceTier: String?
    public var chatgptBaseURL: String
    public var realtimeAudio: RealtimeAudioConfig
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
    public var experimentalRealtimeWSBaseURL: String?
    public var experimentalRealtimeWSModel: String?
    public var realtime: RealtimeConfig
    public var experimentalRealtimeWSBackendPrompt: String?
    public var experimentalRealtimeWSStartupContext: String?
    public var experimentalRealtimeStartInstructions: String?
    public var experimentalThreadConfigEndpoint: String?
    public var experimentalThreadStore: ThreadStoreConfig
    public var webSearchMode: WebSearchMode?
    public var webSearchConfig: WebSearchConfig?
    public var toolsWebSearch: Bool?
    public var toolsViewImage: Bool?
    public var features: FeatureStates
    public var mcpServers: [String: McpServerConfig]
    public var mcpOAuthCredentialsStoreMode: OAuthCredentialsStoreMode
    public var mcpOAuthCallbackPort: UInt16?
    public var mcpOAuthCallbackURL: String?
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
        sandboxPolicy: SandboxPolicy? = nil,
        modelReasoningEffort: ReasoningEffort? = nil,
        modelReasoningSummary: ReasoningSummary? = nil,
        modelVerbosity: Verbosity? = nil,
        serviceTier: String? = nil,
        chatgptBaseURL: String = CodexConfigDefaults.chatgptBaseURL,
        realtimeAudio: RealtimeAudioConfig = RealtimeAudioConfig(),
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
        experimentalRealtimeWSBaseURL: String? = nil,
        experimentalRealtimeWSModel: String? = nil,
        realtime: RealtimeConfig = RealtimeConfig(),
        experimentalRealtimeWSBackendPrompt: String? = nil,
        experimentalRealtimeWSStartupContext: String? = nil,
        experimentalRealtimeStartInstructions: String? = nil,
        experimentalThreadConfigEndpoint: String? = nil,
        experimentalThreadStore: ThreadStoreConfig = .local,
        webSearchMode: WebSearchMode? = nil,
        webSearchConfig: WebSearchConfig? = nil,
        toolsWebSearch: Bool? = nil,
        toolsViewImage: Bool? = nil,
        features: FeatureStates = .withDefaults(),
        mcpServers: [String: McpServerConfig] = [:],
        mcpOAuthCredentialsStoreMode: OAuthCredentialsStoreMode = .auto,
        mcpOAuthCallbackPort: UInt16? = nil,
        mcpOAuthCallbackURL: String? = nil,
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
        self.sandboxPolicy = sandboxPolicy
        self.modelReasoningEffort = modelReasoningEffort
        self.modelReasoningSummary = modelReasoningSummary
        self.modelVerbosity = modelVerbosity
        self.serviceTier = serviceTier
        self.chatgptBaseURL = chatgptBaseURL
        self.realtimeAudio = realtimeAudio
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
        self.experimentalRealtimeWSBaseURL = experimentalRealtimeWSBaseURL
        self.experimentalRealtimeWSModel = experimentalRealtimeWSModel
        self.realtime = realtime
        self.experimentalRealtimeWSBackendPrompt = experimentalRealtimeWSBackendPrompt
        self.experimentalRealtimeWSStartupContext = experimentalRealtimeWSStartupContext
        self.experimentalRealtimeStartInstructions = experimentalRealtimeStartInstructions
        self.experimentalThreadConfigEndpoint = experimentalThreadConfigEndpoint
        self.experimentalThreadStore = experimentalThreadStore
        self.webSearchMode = webSearchMode
        self.webSearchConfig = webSearchConfig
        self.toolsWebSearch = toolsWebSearch
        self.toolsViewImage = toolsViewImage
        self.features = features
        self.mcpServers = mcpServers
        self.mcpOAuthCredentialsStoreMode = mcpOAuthCredentialsStoreMode
        self.mcpOAuthCallbackPort = mcpOAuthCallbackPort
        self.mcpOAuthCallbackURL = mcpOAuthCallbackURL
        self.activeProfile = activeProfile
        self.projectRootMarkers = projectRootMarkers
        self.projectDocMaxBytes = projectDocMaxBytes
        self.projectDocFallbackFilenames = projectDocFallbackFilenames
        self.toolOutputTokenLimit = toolOutputTokenLimit
        self.ossProvider = ossProvider
    }

    public init(
        model: String?,
        modelProvider: String?,
        modelProviders: [String: ModelProviderInfo],
        approvalPolicy: AskForApproval?,
        sandboxMode: SandboxMode?,
        sandboxPolicy: SandboxPolicy?,
        modelReasoningEffort: ReasoningEffort?,
        modelReasoningSummary: ReasoningSummary?,
        modelVerbosity: Verbosity?,
        serviceTier: String?,
        chatgptBaseURL: String,
        cliAuthCredentialsStoreMode: AuthCredentialsStoreMode,
        forcedLoginMethod: ForcedLoginMethod?,
        forcedChatGPTWorkspaceID: String?,
        experimentalInstructionsFile: String?,
        experimentalCompactPromptFile: String?,
        baseInstructions: String?,
        developerInstructions: String?,
        compactPrompt: String?,
        includeApplyPatchTool: Bool?,
        experimentalUseUnifiedExecTool: Bool?,
        experimentalUseFreeformApplyPatch: Bool?,
        webSearchMode: WebSearchMode?,
        webSearchConfig: WebSearchConfig?,
        toolsWebSearch: Bool?,
        toolsViewImage: Bool?,
        features: FeatureStates,
        mcpServers: [String: McpServerConfig],
        mcpOAuthCredentialsStoreMode: OAuthCredentialsStoreMode,
        mcpOAuthCallbackPort: UInt16?,
        mcpOAuthCallbackURL: String?,
        activeProfile: String?,
        projectRootMarkers: [String],
        projectDocMaxBytes: Int,
        projectDocFallbackFilenames: [String],
        toolOutputTokenLimit: Int?,
        ossProvider: String?
    ) {
        self.init(
            model: model,
            modelProvider: modelProvider,
            modelProviders: modelProviders,
            approvalPolicy: approvalPolicy,
            sandboxMode: sandboxMode,
            sandboxPolicy: sandboxPolicy,
            modelReasoningEffort: modelReasoningEffort,
            modelReasoningSummary: modelReasoningSummary,
            modelVerbosity: modelVerbosity,
            serviceTier: serviceTier,
            chatgptBaseURL: chatgptBaseURL,
            cliAuthCredentialsStoreMode: cliAuthCredentialsStoreMode,
            forcedLoginMethod: forcedLoginMethod,
            forcedChatGPTWorkspaceID: forcedChatGPTWorkspaceID,
            experimentalInstructionsFile: experimentalInstructionsFile,
            experimentalCompactPromptFile: experimentalCompactPromptFile,
            baseInstructions: baseInstructions,
            developerInstructions: developerInstructions,
            compactPrompt: compactPrompt,
            includeApplyPatchTool: includeApplyPatchTool,
            experimentalUseUnifiedExecTool: experimentalUseUnifiedExecTool,
            experimentalUseFreeformApplyPatch: experimentalUseFreeformApplyPatch,
            experimentalRealtimeWSBaseURL: nil,
            experimentalRealtimeWSModel: nil,
            experimentalRealtimeWSBackendPrompt: nil,
            experimentalRealtimeWSStartupContext: nil,
            experimentalRealtimeStartInstructions: nil,
            experimentalThreadConfigEndpoint: nil,
            experimentalThreadStore: .local,
            webSearchMode: webSearchMode,
            webSearchConfig: webSearchConfig,
            toolsWebSearch: toolsWebSearch,
            toolsViewImage: toolsViewImage,
            features: features,
            mcpServers: mcpServers,
            mcpOAuthCredentialsStoreMode: mcpOAuthCredentialsStoreMode,
            mcpOAuthCallbackPort: mcpOAuthCallbackPort,
            mcpOAuthCallbackURL: mcpOAuthCallbackURL,
            activeProfile: activeProfile,
            projectRootMarkers: projectRootMarkers,
            projectDocMaxBytes: projectDocMaxBytes,
            projectDocFallbackFilenames: projectDocFallbackFilenames,
            toolOutputTokenLimit: toolOutputTokenLimit,
            ossProvider: ossProvider
        )
    }

    public init(
        model: String?,
        modelProvider: String?,
        modelProviders: [String: ModelProviderInfo],
        approvalPolicy: AskForApproval?,
        sandboxMode: SandboxMode?,
        sandboxPolicy: SandboxPolicy?,
        modelReasoningEffort: ReasoningEffort?,
        modelReasoningSummary: ReasoningSummary?,
        modelVerbosity: Verbosity?,
        serviceTier: String?,
        chatgptBaseURL: String,
        cliAuthCredentialsStoreMode: AuthCredentialsStoreMode,
        forcedLoginMethod: ForcedLoginMethod?,
        forcedChatGPTWorkspaceID: String?,
        experimentalInstructionsFile: String?,
        experimentalCompactPromptFile: String?,
        baseInstructions: String?,
        developerInstructions: String?,
        compactPrompt: String?,
        includeApplyPatchTool: Bool?,
        experimentalUseUnifiedExecTool: Bool?,
        experimentalUseFreeformApplyPatch: Bool?,
        experimentalRealtimeWSBaseURL: String?,
        experimentalRealtimeWSModel: String?,
        experimentalRealtimeWSBackendPrompt: String?,
        experimentalRealtimeWSStartupContext: String?,
        experimentalRealtimeStartInstructions: String?,
        experimentalThreadConfigEndpoint: String?,
        webSearchMode: WebSearchMode?,
        webSearchConfig: WebSearchConfig?,
        toolsWebSearch: Bool?,
        toolsViewImage: Bool?,
        features: FeatureStates,
        mcpServers: [String: McpServerConfig],
        mcpOAuthCredentialsStoreMode: OAuthCredentialsStoreMode,
        mcpOAuthCallbackPort: UInt16?,
        mcpOAuthCallbackURL: String?,
        activeProfile: String?,
        projectRootMarkers: [String],
        projectDocMaxBytes: Int,
        projectDocFallbackFilenames: [String],
        toolOutputTokenLimit: Int?,
        ossProvider: String?
    ) {
        self.init(
            model: model,
            modelProvider: modelProvider,
            modelProviders: modelProviders,
            approvalPolicy: approvalPolicy,
            sandboxMode: sandboxMode,
            sandboxPolicy: sandboxPolicy,
            modelReasoningEffort: modelReasoningEffort,
            modelReasoningSummary: modelReasoningSummary,
            modelVerbosity: modelVerbosity,
            serviceTier: serviceTier,
            chatgptBaseURL: chatgptBaseURL,
            cliAuthCredentialsStoreMode: cliAuthCredentialsStoreMode,
            forcedLoginMethod: forcedLoginMethod,
            forcedChatGPTWorkspaceID: forcedChatGPTWorkspaceID,
            experimentalInstructionsFile: experimentalInstructionsFile,
            experimentalCompactPromptFile: experimentalCompactPromptFile,
            baseInstructions: baseInstructions,
            developerInstructions: developerInstructions,
            compactPrompt: compactPrompt,
            includeApplyPatchTool: includeApplyPatchTool,
            experimentalUseUnifiedExecTool: experimentalUseUnifiedExecTool,
            experimentalUseFreeformApplyPatch: experimentalUseFreeformApplyPatch,
            experimentalRealtimeWSBaseURL: experimentalRealtimeWSBaseURL,
            experimentalRealtimeWSModel: experimentalRealtimeWSModel,
            experimentalRealtimeWSBackendPrompt: experimentalRealtimeWSBackendPrompt,
            experimentalRealtimeWSStartupContext: experimentalRealtimeWSStartupContext,
            experimentalRealtimeStartInstructions: experimentalRealtimeStartInstructions,
            experimentalThreadConfigEndpoint: experimentalThreadConfigEndpoint,
            experimentalThreadStore: .local,
            webSearchMode: webSearchMode,
            webSearchConfig: webSearchConfig,
            toolsWebSearch: toolsWebSearch,
            toolsViewImage: toolsViewImage,
            features: features,
            mcpServers: mcpServers,
            mcpOAuthCredentialsStoreMode: mcpOAuthCredentialsStoreMode,
            mcpOAuthCallbackPort: mcpOAuthCallbackPort,
            mcpOAuthCallbackURL: mcpOAuthCallbackURL,
            activeProfile: activeProfile,
            projectRootMarkers: projectRootMarkers,
            projectDocMaxBytes: projectDocMaxBytes,
            projectDocFallbackFilenames: projectDocFallbackFilenames,
            toolOutputTokenLimit: toolOutputTokenLimit,
            ossProvider: ossProvider
        )
    }

    public var selectedModelProviderID: String {
        modelProvider ?? CodexConfigDefaults.modelProviderID
    }

    public var selectedModelProvider: ModelProviderInfo? {
        modelProviders[selectedModelProviderID]
    }

    public func legacySandboxPolicy(defaultMode: SandboxMode = .readOnly) -> SandboxPolicy {
        sandboxPolicy ?? SandboxPolicy.fromSandboxMode(sandboxMode ?? defaultMode)
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
    case reservedModelProviderOverride([String])
    case invalidConfigLine(String)
    case invalidTableHeader(String)
    case profileNotFound(String)
    case unsupportedExperimentalThreadStoreEndpoint

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
        case let .reservedModelProviderOverride(providerIDs):
            let conflicts = providerIDs.map { "`\($0)`" }.joined(separator: ", ")
            return "model_providers contains reserved built-in provider IDs: \(conflicts). Built-in providers cannot be overridden. Rename your custom provider (for example, `openai-custom`)."
        case let .invalidConfigLine(line):
            return "Invalid config line: \(line)"
        case let .invalidTableHeader(header):
            return "Invalid TOML table header: \(header)"
        case let .profileNotFound(profile):
            return "config profile `\(profile)` not found"
        case .unsupportedExperimentalThreadStoreEndpoint:
            return "`experimental_thread_store_endpoint` is no longer supported; remove it from config.toml"
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
        let userConfigFile = codexHome.appendingPathComponent("config.toml", isDirectory: false).standardizedFileURL
        for configFile in baseConfigLayerFiles(
            codexHome: codexHome,
            systemConfigFile: systemConfigFile
        ) {
            if managedConfigOverrides.ignoreUserConfig,
               configFile.standardizedFileURL == userConfigFile
            {
                continue
            }
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
        config.sandboxPolicy = try parsed.resolvedSandboxPolicy(
            codexHome: codexHome,
            fileManager: fileManager,
            sandboxMode: config.sandboxMode
        )
        return config
    }

    public static func validateForConfigWrite(
        _ config: ConfigValue,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        var parsed = ParsedCodexConfigToml()
        try parsed.merge(config.removingConfigWriteRuntimeOnlyTables())
        try parsed.validateForConfigWrite(environment: environment)
    }

    private static func applyRequirements(
        _ requirements: ConfigRequirements,
        to config: inout CodexRuntimeConfig
    ) throws {
        let approvalPolicy = config.approvalPolicy ?? AskForApproval.defaultValue
        try requirements.approvalPolicy.canSet(approvalPolicy).get()

        let sandboxPolicy = config.legacySandboxPolicy()
        try requirements.sandboxPolicy.canSet(sandboxPolicy).get()
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
    private static let webSearchToolConfigKey = "__tools_web_search_config"

    var topLevel: [String: ConfigValue] = [:]
    var profiles: [String: [String: ConfigValue]] = [:]
    var features: [String: Bool] = [:]
    var profileFeatures: [String: [String: Bool]] = [:]
    var mcpServers: [String: McpServerConfig] = [:]
    var modelProviders: [String: ConfigValue] = [:]
    var sandboxWorkspaceWrite: [String: ConfigValue] = [:]
    var realtimeAudio: [String: ConfigValue] = [:]
    var realtime: [String: ConfigValue] = [:]

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
                if case let .profileToolsWebSearch(name) = section {
                    if parsed.profiles[name] == nil {
                        parsed.profiles[name] = [:]
                    }
                }
                if case let .profileToolsWebSearchLocation(name) = section {
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
            case .sandboxWorkspaceWrite:
                parsed.sandboxWorkspaceWrite[key] = try ConfigValueParser.parseTomlLiteral(valueText)
            case .audio:
                parsed.realtimeAudio[key] = try ConfigValueParser.parseTomlLiteral(valueText)
            case .realtime:
                parsed.realtime[key] = try ConfigValueParser.parseTomlLiteral(valueText)
            case let .profileFeatures(name):
                parsed.profileFeatures[name, default: [:]][key] = try Self.boolValue(
                    ConfigValueParser.parseTomlLiteral(valueText),
                    key: "profiles.\(name).features.\(key)"
                )
            case .toolsWebSearch:
                Self.mergeWebSearchToolConfigField(
                    key: key,
                    value: try ConfigValueParser.parseTomlLiteral(valueText),
                    into: &parsed.topLevel
                )
            case .toolsWebSearchLocation:
                Self.mergeWebSearchToolConfigField(
                    key: "location.\(key)",
                    value: try ConfigValueParser.parseTomlLiteral(valueText),
                    into: &parsed.topLevel
                )
            case let .profileToolsWebSearch(name):
                Self.mergeWebSearchToolConfigField(
                    key: key,
                    value: try ConfigValueParser.parseTomlLiteral(valueText),
                    into: &parsed.profiles[name, default: [:]]
                )
            case let .profileToolsWebSearchLocation(name):
                Self.mergeWebSearchToolConfigField(
                    key: "location.\(key)",
                    value: try ConfigValueParser.parseTomlLiteral(valueText),
                    into: &parsed.profiles[name, default: [:]]
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

            if parts.count == 2, parts[0] == "sandbox_workspace_write" {
                sandboxWorkspaceWrite[parts[1]] = value
                continue
            }

            if parts.count == 2, parts[0] == "audio" {
                realtimeAudio[parts[1]] = value
                continue
            }

            if parts.count == 2, parts[0] == "realtime" {
                realtime[parts[1]] = value
                continue
            }

            if parts.count == 3, parts[0] == "tools", parts[1] == "web_search" {
                Self.mergeWebSearchToolConfigField(key: parts[2], value: value, into: &topLevel)
                continue
            }

            if parts.count == 4, parts[0] == "tools", parts[1] == "web_search", parts[2] == "location" {
                Self.mergeWebSearchToolConfigField(key: "location.\(parts[3])", value: value, into: &topLevel)
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
                continue
            }

            if parts.count == 5, parts[0] == "profiles", parts[2] == "tools", parts[3] == "web_search" {
                Self.mergeWebSearchToolConfigField(key: parts[4], value: value, into: &profiles[parts[1], default: [:]])
                continue
            }

            if parts.count == 6,
               parts[0] == "profiles",
               parts[2] == "tools",
               parts[3] == "web_search",
               parts[4] == "location"
            {
                Self.mergeWebSearchToolConfigField(
                    key: "location.\(parts[5])",
                    value: value,
                    into: &profiles[parts[1], default: [:]]
                )
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

        for (key, value) in overlay.sandboxWorkspaceWrite {
            sandboxWorkspaceWrite[key] = value
        }

        for (key, value) in overlay.realtimeAudio {
            realtimeAudio[key] = value
        }

        for (key, value) in overlay.realtime {
            realtime[key] = value
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

        if case let .table(workspaceWrite) = table["sandbox_workspace_write"] {
            for (key, value) in workspaceWrite {
                sandboxWorkspaceWrite[key] = value
            }
        }

        if case let .table(audioTable) = table["audio"] {
            for (key, value) in audioTable {
                realtimeAudio[key] = value
            }
        }

        if case let .table(realtimeTable) = table["realtime"] {
            for (key, value) in realtimeTable {
                realtime[key] = value
            }
        }

        if case let .table(featureTable) = table["features"] {
            for (key, value) in featureTable {
                features[key] = try Self.boolValue(value, key: "features.\(key)")
            }
        }

        if case let .table(toolsTable) = table["tools"],
           let webSearchValue = toolsTable["web_search"]
        {
            Self.mergeWebSearchToolConfig(value: webSearchValue, into: &topLevel)
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

                    if key == "tools",
                       case let .table(toolsTable) = value,
                       let webSearchValue = toolsTable["web_search"]
                    {
                        Self.mergeWebSearchToolConfig(value: webSearchValue, into: &profiles[profileName, default: [:]])
                    }
                }
            }
        }
    }

    func resolvedConfig(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> CodexRuntimeConfig {
        var config = CodexRuntimeConfig()

        try Self.applyRuntimeFields(from: topLevel, to: &config, keyPrefix: "")
        config.realtimeAudio = try Self.realtimeAudioConfigValue(realtimeAudio, key: "audio")
        config.realtime = try Self.realtimeConfigValue(realtime, key: "realtime")

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

        if let callbackPort = topLevel["mcp_oauth_callback_port"] {
            config.mcpOAuthCallbackPort = try Self.uint16Value(
                callbackPort,
                key: "mcp_oauth_callback_port"
            )
        }

        if let callbackURL = topLevel["mcp_oauth_callback_url"] {
            config.mcpOAuthCallbackURL = try Self.stringValue(
                callbackURL,
                key: "mcp_oauth_callback_url"
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
        config.serviceTier = Self.normalizedServiceTier(
            config.serviceTier,
            features: featureStates
        )

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

    func resolvedSandboxPolicy(
        codexHome: URL,
        fileManager: FileManager,
        sandboxMode: SandboxMode?
    ) throws -> SandboxPolicy? {
        let memoriesRoot = codexHome
            .appendingPathComponent("memories", isDirectory: true)
            .standardizedFileURL
        try fileManager.createDirectory(at: memoriesRoot, withIntermediateDirectories: true)

        guard sandboxMode == .workspaceWrite else {
            return sandboxMode.map(SandboxPolicy.fromSandboxMode)
        }

        var workspaceWrite = try sandboxWorkspaceWriteConfig()
        let memoriesPath = try AbsolutePath(absolutePath: memoriesRoot.path)
        if !workspaceWrite.writableRoots.contains(memoriesPath) {
            workspaceWrite.writableRoots.append(memoriesPath)
        }

        return .workspaceWrite(
            writableRoots: workspaceWrite.writableRoots,
            networkAccess: workspaceWrite.networkAccess,
            excludeTmpdirEnvVar: workspaceWrite.excludeTmpdirEnvVar,
            excludeSlashTmp: workspaceWrite.excludeSlashTmp
        )
    }

    private func sandboxWorkspaceWriteConfig() throws -> SandboxWorkspaceWriteConfig {
        SandboxWorkspaceWriteConfig(
            writableRoots: try Self.absolutePathArrayValue(
                sandboxWorkspaceWrite["writable_roots"],
                key: "sandbox_workspace_write.writable_roots"
            ),
            networkAccess: try sandboxWorkspaceWrite["network_access"].map {
                try Self.boolValue($0, key: "sandbox_workspace_write.network_access")
            } ?? false,
            excludeTmpdirEnvVar: try sandboxWorkspaceWrite["exclude_tmpdir_env_var"].map {
                try Self.boolValue($0, key: "sandbox_workspace_write.exclude_tmpdir_env_var")
            } ?? false,
            excludeSlashTmp: try sandboxWorkspaceWrite["exclude_slash_tmp"].map {
                try Self.boolValue($0, key: "sandbox_workspace_write.exclude_slash_tmp")
            } ?? false
        )
    }

    func projectRootMarkersForDiscovery() throws -> [String] {
        guard let value = topLevel["project_root_markers"] else {
            return CodexConfigDefaults.projectRootMarkers
        }
        return try Self.stringArrayValue(value, key: "project_root_markers")
    }

    func validateForConfigWrite(environment: [String: String]) throws {
        var parsed = self
        parsed.mcpServers = [:]
        _ = try parsed.resolvedConfig(environment: environment)
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
        let reservedConflicts = configuredProviders.keys
            .filter { $0 != ModelProviderInfo.amazonBedrockProviderID && providers[$0] != nil }
            .sorted()
        if !reservedConflicts.isEmpty {
            throw CodexConfigLoadError.reservedModelProviderOverride(reservedConflicts)
        }
        for (name, value) in configuredProviders {
            let provider = try modelProviderInfoValue(value, key: "model_providers.\(name)")
            providers[name] = provider
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
        if let serviceTier = values["service_tier"] {
            config.serviceTier = try stringValue(serviceTier, key: "\(keyPrefix)service_tier")
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
        if values["experimental_thread_store_endpoint"] != nil {
            throw CodexConfigLoadError.unsupportedExperimentalThreadStoreEndpoint
        }
        if let baseURL = values["experimental_realtime_ws_base_url"] {
            config.experimentalRealtimeWSBaseURL = try stringValue(
                baseURL,
                key: "\(keyPrefix)experimental_realtime_ws_base_url"
            )
        }
        if let model = values["experimental_realtime_ws_model"] {
            config.experimentalRealtimeWSModel = try stringValue(
                model,
                key: "\(keyPrefix)experimental_realtime_ws_model"
            )
        }
        if let backendPrompt = values["experimental_realtime_ws_backend_prompt"] {
            config.experimentalRealtimeWSBackendPrompt = try stringValue(
                backendPrompt,
                key: "\(keyPrefix)experimental_realtime_ws_backend_prompt"
            )
        }
        if let startupContext = values["experimental_realtime_ws_startup_context"] {
            config.experimentalRealtimeWSStartupContext = try stringValue(
                startupContext,
                key: "\(keyPrefix)experimental_realtime_ws_startup_context"
            )
        }
        if let startInstructions = values["experimental_realtime_start_instructions"] {
            config.experimentalRealtimeStartInstructions = try stringValue(
                startInstructions,
                key: "\(keyPrefix)experimental_realtime_start_instructions"
            )
        }
        if let endpoint = values["experimental_thread_config_endpoint"] {
            config.experimentalThreadConfigEndpoint = try stringValue(
                endpoint,
                key: "\(keyPrefix)experimental_thread_config_endpoint"
            )
        }
        if let threadStore = values["experimental_thread_store"] {
            config.experimentalThreadStore = try threadStoreConfigValue(
                threadStore,
                key: "\(keyPrefix)experimental_thread_store"
            )
        }
        if let webSearch = values["web_search"] {
            config.webSearchMode = try stringEnumValue(
                WebSearchMode.self,
                webSearch,
                key: "\(keyPrefix)web_search"
            )
        }
        if let webSearchConfig = values[webSearchToolConfigKey] {
            let parsedConfig = try Self.webSearchConfigValue(
                webSearchConfig,
                key: "\(keyPrefix)tools.web_search"
            )
            config.webSearchConfig = config.webSearchConfig?.merging(overlay: parsedConfig) ?? parsedConfig
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
            || key == "service_tier"
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
            || key == "experimental_realtime_ws_base_url"
            || key == "experimental_realtime_ws_model"
            || key == "experimental_realtime_ws_backend_prompt"
            || key == "experimental_realtime_ws_startup_context"
            || key == "experimental_realtime_start_instructions"
            || key == "experimental_thread_config_endpoint"
            || key == "experimental_thread_store_endpoint"
            || key == "experimental_thread_store"
            || key == "web_search"
            || key == "tools_web_search"
            || key == "tools_view_image"
            || key == "mcp_oauth_credentials_store"
            || key == "mcp_oauth_callback_port"
            || key == "mcp_oauth_callback_url"
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
            || key == "service_tier"
            || key == "chatgpt_base_url"
            || key == "experimental_instructions_file"
            || key == "experimental_compact_prompt_file"
            || key == "include_apply_patch_tool"
            || key == "experimental_use_unified_exec_tool"
            || key == "experimental_use_freeform_apply_patch"
            || key == "web_search"
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

    private static func normalizedServiceTier(_ value: String?, features: FeatureStates) -> String? {
        guard let value else {
            return nil
        }
        switch ServiceTier.fromRequestValue(value) {
        case .fast:
            return features.isEnabled(.fastMode) ? ServiceTier.fast.requestValue : nil
        case .flex:
            return ServiceTier.flex.requestValue
        case nil:
            return value
        }
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

    private static func realtimeAudioConfigValue(_ table: [String: ConfigValue], key: String) throws -> RealtimeAudioConfig {
        for field in table.keys where !["microphone", "speaker"].contains(field) {
            throw CodexConfigLoadError.invalidConfigLine("\(key).\(field)")
        }
        return RealtimeAudioConfig(
            microphone: try table["microphone"].map { try stringValue($0, key: "\(key).microphone") },
            speaker: try table["speaker"].map { try stringValue($0, key: "\(key).speaker") }
        )
    }

    private static func realtimeConfigValue(_ table: [String: ConfigValue], key: String) throws -> RealtimeConfig {
        for field in table.keys where !["version", "type", "transport", "voice"].contains(field) {
            throw CodexConfigLoadError.invalidConfigLine("\(key).\(field)")
        }
        let defaults = RealtimeConfig()
        return RealtimeConfig(
            version: try table["version"].map {
                try stringEnumValue(RealtimeConversationVersion.self, $0, key: "\(key).version")
            } ?? defaults.version,
            sessionType: try table["type"].map {
                try stringEnumValue(RealtimeWsMode.self, $0, key: "\(key).type")
            } ?? defaults.sessionType,
            transport: try table["transport"].map {
                try stringEnumValue(RealtimeTransport.self, $0, key: "\(key).transport")
            } ?? defaults.transport,
            voice: try table["voice"].map {
                try stringEnumValue(RealtimeVoice.self, $0, key: "\(key).voice")
            } ?? defaults.voice
        )
    }

    private static func threadStoreConfigValue(_ value: ConfigValue, key: String) throws -> ThreadStoreConfig {
        guard case let .table(table) = value else {
            throw CodexConfigLoadError.invalidStringValue(key)
        }

        let type = try stringValue(table["type"] ?? .none, key: "\(key).type")
        switch type {
        case "local":
            return .local
        case "in_memory":
            let id = try stringValue(table["id"] ?? .none, key: "\(key).id")
            return .inMemory(id: id)
        default:
            throw CodexConfigLoadError.invalidStringValue("\(key).type")
        }
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

    private static func absolutePathArrayValue(_ value: ConfigValue?, key: String) throws -> [AbsolutePath] {
        guard let value else {
            return []
        }
        return try stringArrayValue(value, key: key).map { try AbsolutePath(absolutePath: $0) }
    }

    private static func nonNegativeIntValue(_ value: ConfigValue, key: String) throws -> Int {
        guard case let .integer(integer) = value, integer >= 0 else {
            throw CodexConfigLoadError.invalidStringValue(key)
        }
        return Int(integer)
    }

    private static func uint16Value(_ value: ConfigValue, key: String) throws -> UInt16 {
        guard case let .integer(integer) = value,
              integer >= 0,
              integer <= Int64(UInt16.max)
        else {
            throw CodexConfigLoadError.invalidStringValue(key)
        }
        return UInt16(integer)
    }

    private static func mergeWebSearchToolConfigField(
        key: String,
        value: ConfigValue,
        into values: inout [String: ConfigValue]
    ) {
        let overlay: ConfigValue
        if key.hasPrefix("location.") {
            overlay = .table([
                "location": .table([String(key.dropFirst("location.".count)): value])
            ])
        } else {
            overlay = .table([key: value])
        }
        mergeWebSearchToolConfig(value: overlay, into: &values)
    }

    private static func mergeWebSearchToolConfig(
        value: ConfigValue,
        into values: inout [String: ConfigValue]
    ) {
        if var existing = values[Self.webSearchToolConfigKey] {
            existing.merge(overlay: value)
            values[Self.webSearchToolConfigKey] = existing
        } else {
            values[Self.webSearchToolConfigKey] = value
        }
    }

    private static func webSearchConfigValue(_ value: ConfigValue, key: String) throws -> WebSearchConfig {
        guard case let .table(table) = value else {
            throw CodexConfigLoadError.invalidStringValue(key)
        }
        for field in table.keys where !["context_size", "allowed_domains", "location"].contains(field) {
            throw CodexConfigLoadError.invalidConfigLine("\(key).\(field)")
        }

        let filters: ResponsesAPIWebSearchFilters?
        if let allowedDomains = table["allowed_domains"] {
            filters = ResponsesAPIWebSearchFilters(
                allowedDomains: try stringArrayValue(allowedDomains, key: "\(key).allowed_domains")
            )
        } else {
            filters = nil
        }

        let location = try table["location"].map {
            try webSearchLocationValue($0, key: "\(key).location")
        }
        let contextSize = try table["context_size"].map {
            try stringEnumValue(WebSearchContextSize.self, $0, key: "\(key).context_size")
        }

        return WebSearchConfig(
            filters: filters,
            userLocation: location,
            searchContextSize: contextSize
        )
    }

    private static func webSearchLocationValue(
        _ value: ConfigValue,
        key: String
    ) throws -> ResponsesAPIWebSearchUserLocation {
        guard case let .table(table) = value else {
            throw CodexConfigLoadError.invalidStringValue(key)
        }
        for field in table.keys where !["country", "region", "city", "timezone"].contains(field) {
            throw CodexConfigLoadError.invalidConfigLine("\(key).\(field)")
        }
        return ResponsesAPIWebSearchUserLocation(
            country: try table["country"].map { try stringValue($0, key: "\(key).country") },
            region: try table["region"].map { try stringValue($0, key: "\(key).region") },
            city: try table["city"].map { try stringValue($0, key: "\(key).city") },
            timezone: try table["timezone"].map { try stringValue($0, key: "\(key).timezone") }
        )
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
        if parts.count == 1, parts[0] == "sandbox_workspace_write" {
            return .sandboxWorkspaceWrite
        }
        if parts.count == 1, parts[0] == "audio" {
            return .audio
        }
        if parts.count == 1, parts[0] == "realtime" {
            return .realtime
        }
        if parts.count == 2, parts[0] == "tools", parts[1] == "web_search" {
            return .toolsWebSearch
        }
        if parts.count == 3, parts[0] == "tools", parts[1] == "web_search", parts[2] == "location" {
            return .toolsWebSearchLocation
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
        if parts.count == 4, parts[0] == "profiles", parts[2] == "tools", parts[3] == "web_search" {
            return .profileToolsWebSearch(parts[1])
        }
        if parts.count == 5,
           parts[0] == "profiles",
           parts[2] == "tools",
           parts[3] == "web_search",
           parts[4] == "location"
        {
            return .profileToolsWebSearchLocation(parts[1])
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

private extension ConfigValue {
    func removingConfigWriteRuntimeOnlyTables() -> ConfigValue {
        guard case var .table(table) = self else {
            return self
        }
        table.removeValue(forKey: "mcp_servers")
        return .table(table)
    }
}

private struct SandboxWorkspaceWriteConfig {
    var writableRoots: [AbsolutePath]
    var networkAccess: Bool
    var excludeTmpdirEnvVar: Bool
    var excludeSlashTmp: Bool
}

private enum ConfigSection {
    case topLevel
    case profile(String)
    case modelProvider(String)
    case modelProviderMap(String, String)
    case features
    case sandboxWorkspaceWrite
    case audio
    case realtime
    case toolsWebSearch
    case toolsWebSearchLocation
    case profileFeatures(String)
    case profileToolsWebSearch(String)
    case profileToolsWebSearchLocation(String)
    case ignored
}
