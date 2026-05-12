import Foundation

public enum CodexConfigDefaults {
    public static let chatgptBaseURL = "https://chatgpt.com/backend-api/"
    public static let modelProviderID = "openai"
    public static let projectRootMarkers = [".git"]
    public static let projectDocMaxBytes = 32 * 1024
    public static let backgroundTerminalMaxTimeoutMS: UInt64 = 300_000
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

public enum TerminalResizeReflowMaxRows: Equatable, Sendable {
    case auto
    case disabled
    case limit(Int)
}

public struct TerminalResizeReflowConfig: Equatable, Sendable {
    public var maxRows: TerminalResizeReflowMaxRows

    public init(maxRows: TerminalResizeReflowMaxRows = .auto) {
        self.maxRows = maxRows
    }
}

public enum TuiAlternateScreenMode: String, Codable, Equatable, Sendable {
    case auto
    case always
    case never
}

public enum TuiSessionPickerViewMode: String, Codable, Equatable, Sendable {
    case comfortable
    case dense
}

public enum TuiNotifications: Equatable, Sendable {
    case enabled(Bool)
    case custom([String])
}

public enum TuiNotificationMethod: String, Codable, Equatable, Sendable {
    case auto
    case osc9
    case bel
}

public enum TuiNotificationCondition: String, Codable, Equatable, Sendable {
    case unfocused
    case always
}

public struct TuiNotificationSettings: Equatable, Sendable {
    public var notifications: TuiNotifications
    public var method: TuiNotificationMethod
    public var condition: TuiNotificationCondition

    public init(
        notifications: TuiNotifications = .enabled(true),
        method: TuiNotificationMethod = .auto,
        condition: TuiNotificationCondition = .unfocused
    ) {
        self.notifications = notifications
        self.method = method
        self.condition = condition
    }
}

public struct TuiRuntimeConfig: Equatable, Sendable {
    public var animations: Bool
    public var showTooltips: Bool
    public var vimModeDefault: Bool
    public var rawOutputMode: Bool
    public var alternateScreen: TuiAlternateScreenMode
    public var statusLine: [String]?
    public var statusLineUseColors: Bool
    public var terminalTitle: [String]?
    public var theme: String?
    public var sessionPickerView: TuiSessionPickerViewMode
    public var modelAvailabilityNuxShownCount: [String: Int]
    public var notifications: TuiNotificationSettings

    public init(
        animations: Bool = true,
        showTooltips: Bool = true,
        vimModeDefault: Bool = false,
        rawOutputMode: Bool = false,
        alternateScreen: TuiAlternateScreenMode = .auto,
        statusLine: [String]? = nil,
        statusLineUseColors: Bool = true,
        terminalTitle: [String]? = nil,
        theme: String? = nil,
        sessionPickerView: TuiSessionPickerViewMode = .dense,
        modelAvailabilityNuxShownCount: [String: Int] = [:],
        notifications: TuiNotificationSettings = TuiNotificationSettings()
    ) {
        self.animations = animations
        self.showTooltips = showTooltips
        self.vimModeDefault = vimModeDefault
        self.rawOutputMode = rawOutputMode
        self.alternateScreen = alternateScreen
        self.statusLine = statusLine
        self.statusLineUseColors = statusLineUseColors
        self.terminalTitle = terminalTitle
        self.theme = theme
        self.sessionPickerView = sessionPickerView
        self.modelAvailabilityNuxShownCount = modelAvailabilityNuxShownCount
        self.notifications = notifications
    }
}

public enum HistoryPersistence: String, Codable, Equatable, Sendable {
    case saveAll = "save-all"
    case none
}

public struct HistoryConfig: Equatable, Sendable {
    public var persistence: HistoryPersistence
    public var maxBytes: Int?

    public init(
        persistence: HistoryPersistence = .saveAll,
        maxBytes: Int? = nil
    ) {
        self.persistence = persistence
        self.maxBytes = maxBytes
    }
}

public struct AgentRuntimeConfig: Equatable, Sendable {
    public static let defaultMaxThreads: Int? = 6
    public static let defaultMaxDepth: Int32 = 1
    public static let defaultJobMaxRuntimeSeconds: UInt64? = nil

    public var maxThreads: Int?
    public var maxDepth: Int32
    public var jobMaxRuntimeSeconds: UInt64?
    public var interruptMessageEnabled: Bool

    public init(
        maxThreads: Int? = Self.defaultMaxThreads,
        maxDepth: Int32 = Self.defaultMaxDepth,
        jobMaxRuntimeSeconds: UInt64? = Self.defaultJobMaxRuntimeSeconds,
        interruptMessageEnabled: Bool = true
    ) {
        self.maxThreads = maxThreads
        self.maxDepth = maxDepth
        self.jobMaxRuntimeSeconds = jobMaxRuntimeSeconds
        self.interruptMessageEnabled = interruptMessageEnabled
    }
}

public struct AgentRoleConfig: Equatable, Sendable {
    public var description: String?
    public var configFile: String?
    public var nicknameCandidates: [String]?

    public init(
        description: String? = nil,
        configFile: String? = nil,
        nicknameCandidates: [String]? = nil
    ) {
        self.description = description
        self.configFile = configFile
        self.nicknameCandidates = nicknameCandidates
    }
}

public enum UriBasedFileOpener: String, Codable, Equatable, Sendable {
    case vsCode = "vscode"
    case vsCodeInsiders = "vscode-insiders"
    case windsurf
    case cursor
    case none

    public var scheme: String? {
        switch self {
        case .vsCode:
            "vscode"
        case .vsCodeInsiders:
            "vscode-insiders"
        case .windsurf:
            "windsurf"
        case .cursor:
            "cursor"
        case .none:
            nil
        }
    }
}

public struct CodexRuntimeConfig: Equatable, Sendable {
    public var model: String?
    public var reviewModel: String?
    public var modelProvider: String?
    public var modelProviders: [String: ModelProviderInfo]
    public var approvalPolicy: AskForApproval?
    public var approvalsReviewer: ApprovalsReviewer
    public var sandboxMode: SandboxMode?
    public var sandboxPolicy: SandboxPolicy?
    public var defaultPermissions: String?
    public var permissionProfile: PermissionProfile?
    public var activePermissionProfile: ActivePermissionProfile?
    public var networkProxy: NetworkProxySpec?
    public var notify: [String]?
    public var allowLoginShell: Bool
    public var hideAgentReasoning: Bool
    public var showRawAgentReasoning: Bool
    public var modelReasoningEffort: ReasoningEffort?
    public var planModeReasoningEffort: ReasoningEffort?
    public var modelReasoningSummary: ReasoningSummary?
    public var modelSupportsReasoningSummaries: Bool?
    public var modelVerbosity: Verbosity?
    public var serviceTier: String?
    public var chatgptBaseURL: String
    public var openAIBaseURL: String?
    public var sqliteHome: String?
    public var logDir: String?
    public var zshPath: String?
    public var modelCatalogJSON: String?
    public var modelCatalog: ModelsResponse?
    public var personality: Personality?
    public var appsMcpPathOverride: String?
    public var realtimeAudio: RealtimeAudioConfig
    public var cliAuthCredentialsStoreMode: AuthCredentialsStoreMode
    public var forcedLoginMethod: ForcedLoginMethod?
    public var forcedChatGPTWorkspaceID: String?
    public var experimentalInstructionsFile: String?
    public var experimentalCompactPromptFile: String?
    public var baseInstructions: String?
    public var developerInstructions: String?
    public var compactPrompt: String?
    public var commitAttribution: String?
    public var includePermissionsInstructions: Bool
    public var includeAppsInstructions: Bool
    public var includeSkillInstructions: Bool
    public var includeEnvironmentContext: Bool
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
    public var memories: MemoriesConfig
    public var mcpServers: [String: McpServerConfig]
    public var mcpOAuthCredentialsStoreMode: OAuthCredentialsStoreMode
    public var mcpOAuthCallbackPort: UInt16?
    public var mcpOAuthCallbackURL: String?
    public var windowsSandboxLevel: WindowsSandboxLevel
    public var windowsSandboxPrivateDesktop: Bool
    public var activeProfile: String?
    public var projectRootMarkers: [String]
    public var projectDocMaxBytes: Int
    public var projectDocFallbackFilenames: [String]
    public var toolOutputTokenLimit: Int?
    public var backgroundTerminalMaxTimeoutMS: UInt64
    public var shellEnvironmentPolicy: ShellEnvironmentPolicy
    public var ossProvider: String?
    public var toolSuggest: ToolSuggestConfig
    public var checkForUpdateOnStartup: Bool
    public var disablePasteBurst: Bool
    public var analyticsEnabled: Bool?
    public var feedbackEnabled: Bool
    public var notices: NoticeConfig
    public var modelContextWindow: Int64?
    public var modelAutoCompactTokenLimit: Int64?
    public var history: HistoryConfig
    public var agents: AgentRuntimeConfig
    public var agentRoles: [String: AgentRoleConfig]
    public var startupWarnings: [String]
    public var fileOpener: UriBasedFileOpener
    public var tui: TuiRuntimeConfig
    public var terminalResizeReflow: TerminalResizeReflowConfig

    public var runtimeMcpConfig: RuntimeMcpConfig {
        let builtinMcpServers = enabledBuiltinMcpServers(options: BuiltinMcpServerOptions(
            memoriesEnabled: features.isEnabled(.builtInMcp)
                && features.isEnabled(.memoryTool)
                && memories.useMemories
        ))
        var configuredMcpServers = mcpServers
        for builtinServer in builtinMcpServers {
            configuredMcpServers.removeValue(forKey: builtinServer.name)
        }
        return RuntimeMcpConfig(
            chatgptBaseURL: chatgptBaseURL,
            appsMcpPathOverride: appsMcpPathOverride,
            appsEnabled: features.isEnabled(.apps),
            configuredMcpServers: configuredMcpServers,
            builtinMcpServers: builtinMcpServers
        )
    }

    public init(
        model: String? = nil,
        reviewModel: String? = nil,
        modelProvider: String? = nil,
        modelProviders: [String: ModelProviderInfo] = [:],
        approvalPolicy: AskForApproval? = nil,
        sandboxMode: SandboxMode? = nil,
        sandboxPolicy: SandboxPolicy? = nil,
        defaultPermissions: String? = nil,
        permissionProfile: PermissionProfile? = nil,
        activePermissionProfile: ActivePermissionProfile? = nil,
        notify: [String]? = nil,
        allowLoginShell: Bool = true,
        hideAgentReasoning: Bool = false,
        showRawAgentReasoning: Bool = false,
        modelReasoningEffort: ReasoningEffort? = nil,
        planModeReasoningEffort: ReasoningEffort? = nil,
        modelReasoningSummary: ReasoningSummary? = nil,
        modelSupportsReasoningSummaries: Bool? = nil,
        modelVerbosity: Verbosity? = nil,
        serviceTier: String? = nil,
        chatgptBaseURL: String = CodexConfigDefaults.chatgptBaseURL,
        openAIBaseURL: String? = nil,
        sqliteHome: String? = nil,
        logDir: String? = nil,
        zshPath: String? = nil,
        modelCatalogJSON: String? = nil,
        modelCatalog: ModelsResponse? = nil,
        personality: Personality? = nil,
        appsMcpPathOverride: String? = nil,
        realtimeAudio: RealtimeAudioConfig = RealtimeAudioConfig(),
        cliAuthCredentialsStoreMode: AuthCredentialsStoreMode = .file,
        forcedLoginMethod: ForcedLoginMethod? = nil,
        forcedChatGPTWorkspaceID: String? = nil,
        experimentalInstructionsFile: String? = nil,
        experimentalCompactPromptFile: String? = nil,
        baseInstructions: String? = nil,
        developerInstructions: String? = nil,
        compactPrompt: String? = nil,
        commitAttribution: String? = nil,
        includePermissionsInstructions: Bool = true,
        includeAppsInstructions: Bool = true,
        includeSkillInstructions: Bool = true,
        includeEnvironmentContext: Bool = true,
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
        memories: MemoriesConfig,
        mcpServers: [String: McpServerConfig] = [:],
        mcpOAuthCredentialsStoreMode: OAuthCredentialsStoreMode = .auto,
        mcpOAuthCallbackPort: UInt16? = nil,
        mcpOAuthCallbackURL: String? = nil,
        windowsSandboxLevel: WindowsSandboxLevel = .disabled,
        windowsSandboxPrivateDesktop: Bool = true,
        activeProfile: String? = nil,
        projectRootMarkers: [String] = CodexConfigDefaults.projectRootMarkers,
        projectDocMaxBytes: Int = CodexConfigDefaults.projectDocMaxBytes,
        projectDocFallbackFilenames: [String] = [],
        toolOutputTokenLimit: Int? = nil,
        backgroundTerminalMaxTimeoutMS: UInt64 = CodexConfigDefaults.backgroundTerminalMaxTimeoutMS,
        shellEnvironmentPolicy: ShellEnvironmentPolicy = ShellEnvironmentPolicy(),
        ossProvider: String? = nil
    ) {
        self.model = model
        self.reviewModel = reviewModel
        self.modelProvider = modelProvider
        self.modelProviders = modelProviders
        self.approvalPolicy = approvalPolicy
        self.approvalsReviewer = .user
        self.sandboxMode = sandboxMode
        self.sandboxPolicy = sandboxPolicy
        self.defaultPermissions = defaultPermissions
        self.permissionProfile = permissionProfile
        self.activePermissionProfile = activePermissionProfile
        self.networkProxy = nil
        self.notify = notify
        self.allowLoginShell = allowLoginShell
        self.hideAgentReasoning = hideAgentReasoning
        self.showRawAgentReasoning = showRawAgentReasoning
        self.modelReasoningEffort = modelReasoningEffort
        self.planModeReasoningEffort = planModeReasoningEffort
        self.modelReasoningSummary = modelReasoningSummary
        self.modelSupportsReasoningSummaries = modelSupportsReasoningSummaries
        self.modelVerbosity = modelVerbosity
        self.serviceTier = serviceTier
        self.chatgptBaseURL = chatgptBaseURL
        self.openAIBaseURL = openAIBaseURL
        self.sqliteHome = sqliteHome
        self.logDir = logDir
        self.zshPath = zshPath
        self.modelCatalogJSON = modelCatalogJSON
        self.modelCatalog = modelCatalog
        self.personality = personality
        self.appsMcpPathOverride = appsMcpPathOverride
        self.realtimeAudio = realtimeAudio
        self.cliAuthCredentialsStoreMode = cliAuthCredentialsStoreMode
        self.forcedLoginMethod = forcedLoginMethod
        self.forcedChatGPTWorkspaceID = forcedChatGPTWorkspaceID
        self.experimentalInstructionsFile = experimentalInstructionsFile
        self.experimentalCompactPromptFile = experimentalCompactPromptFile
        self.baseInstructions = baseInstructions
        self.developerInstructions = developerInstructions
        self.compactPrompt = compactPrompt
        self.commitAttribution = commitAttribution
        self.includePermissionsInstructions = includePermissionsInstructions
        self.includeAppsInstructions = includeAppsInstructions
        self.includeSkillInstructions = includeSkillInstructions
        self.includeEnvironmentContext = includeEnvironmentContext
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
        self.memories = memories
        self.mcpServers = mcpServers
        self.mcpOAuthCredentialsStoreMode = mcpOAuthCredentialsStoreMode
        self.mcpOAuthCallbackPort = mcpOAuthCallbackPort
        self.mcpOAuthCallbackURL = mcpOAuthCallbackURL
        self.windowsSandboxLevel = windowsSandboxLevel
        self.windowsSandboxPrivateDesktop = windowsSandboxPrivateDesktop
        self.activeProfile = activeProfile
        self.projectRootMarkers = projectRootMarkers
        self.projectDocMaxBytes = projectDocMaxBytes
        self.projectDocFallbackFilenames = projectDocFallbackFilenames
        self.toolOutputTokenLimit = toolOutputTokenLimit
        self.backgroundTerminalMaxTimeoutMS = backgroundTerminalMaxTimeoutMS
        self.shellEnvironmentPolicy = shellEnvironmentPolicy
        self.ossProvider = ossProvider
        self.toolSuggest = ToolSuggestConfig()
        self.checkForUpdateOnStartup = true
        self.disablePasteBurst = false
        self.analyticsEnabled = nil
        self.feedbackEnabled = true
        self.notices = NoticeConfig()
        self.modelContextWindow = nil
        self.modelAutoCompactTokenLimit = nil
        self.history = HistoryConfig()
        self.agents = AgentRuntimeConfig()
        self.agentRoles = [:]
        self.startupWarnings = []
        self.fileOpener = .vsCode
        self.tui = TuiRuntimeConfig()
        self.terminalResizeReflow = TerminalResizeReflowConfig()
    }

    public init(
        model: String? = nil,
        modelProvider: String? = nil,
        modelProviders: [String: ModelProviderInfo] = [:],
        approvalPolicy: AskForApproval? = nil,
        sandboxMode: SandboxMode? = nil,
        sandboxPolicy: SandboxPolicy? = nil,
        defaultPermissions: String? = nil,
        permissionProfile: PermissionProfile? = nil,
        activePermissionProfile: ActivePermissionProfile? = nil,
        allowLoginShell: Bool = true,
        hideAgentReasoning: Bool = false,
        showRawAgentReasoning: Bool = false,
        modelReasoningEffort: ReasoningEffort? = nil,
        planModeReasoningEffort: ReasoningEffort? = nil,
        modelReasoningSummary: ReasoningSummary? = nil,
        modelSupportsReasoningSummaries: Bool? = nil,
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
        includePermissionsInstructions: Bool = true,
        includeAppsInstructions: Bool = true,
        includeSkillInstructions: Bool = true,
        includeEnvironmentContext: Bool = true,
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
        backgroundTerminalMaxTimeoutMS: UInt64 = CodexConfigDefaults.backgroundTerminalMaxTimeoutMS,
        shellEnvironmentPolicy: ShellEnvironmentPolicy = ShellEnvironmentPolicy(),
        ossProvider: String? = nil
    ) {
        self.init(
            model: model,
            modelProvider: modelProvider,
            modelProviders: modelProviders,
            approvalPolicy: approvalPolicy,
            sandboxMode: sandboxMode,
            sandboxPolicy: sandboxPolicy,
            defaultPermissions: defaultPermissions,
            permissionProfile: permissionProfile,
            activePermissionProfile: activePermissionProfile,
            notify: nil,
            allowLoginShell: allowLoginShell,
            hideAgentReasoning: hideAgentReasoning,
            showRawAgentReasoning: showRawAgentReasoning,
            modelReasoningEffort: modelReasoningEffort,
            planModeReasoningEffort: planModeReasoningEffort,
            modelReasoningSummary: modelReasoningSummary,
            modelSupportsReasoningSummaries: modelSupportsReasoningSummaries,
            modelVerbosity: modelVerbosity,
            serviceTier: serviceTier,
            chatgptBaseURL: chatgptBaseURL,
            realtimeAudio: realtimeAudio,
            cliAuthCredentialsStoreMode: cliAuthCredentialsStoreMode,
            forcedLoginMethod: forcedLoginMethod,
            forcedChatGPTWorkspaceID: forcedChatGPTWorkspaceID,
            experimentalInstructionsFile: experimentalInstructionsFile,
            experimentalCompactPromptFile: experimentalCompactPromptFile,
            baseInstructions: baseInstructions,
            developerInstructions: developerInstructions,
            compactPrompt: compactPrompt,
            includePermissionsInstructions: includePermissionsInstructions,
            includeAppsInstructions: includeAppsInstructions,
            includeSkillInstructions: includeSkillInstructions,
            includeEnvironmentContext: includeEnvironmentContext,
            includeApplyPatchTool: includeApplyPatchTool,
            experimentalUseUnifiedExecTool: experimentalUseUnifiedExecTool,
            experimentalUseFreeformApplyPatch: experimentalUseFreeformApplyPatch,
            experimentalRealtimeWSBaseURL: experimentalRealtimeWSBaseURL,
            experimentalRealtimeWSModel: experimentalRealtimeWSModel,
            realtime: realtime,
            experimentalRealtimeWSBackendPrompt: experimentalRealtimeWSBackendPrompt,
            experimentalRealtimeWSStartupContext: experimentalRealtimeWSStartupContext,
            experimentalRealtimeStartInstructions: experimentalRealtimeStartInstructions,
            experimentalThreadConfigEndpoint: experimentalThreadConfigEndpoint,
            experimentalThreadStore: experimentalThreadStore,
            webSearchMode: webSearchMode,
            webSearchConfig: webSearchConfig,
            toolsWebSearch: toolsWebSearch,
            toolsViewImage: toolsViewImage,
            features: features,
            memories: MemoriesConfig(),
            mcpServers: mcpServers,
            mcpOAuthCredentialsStoreMode: mcpOAuthCredentialsStoreMode,
            mcpOAuthCallbackPort: mcpOAuthCallbackPort,
            mcpOAuthCallbackURL: mcpOAuthCallbackURL,
            activeProfile: activeProfile,
            projectRootMarkers: projectRootMarkers,
            projectDocMaxBytes: projectDocMaxBytes,
            projectDocFallbackFilenames: projectDocFallbackFilenames,
            toolOutputTokenLimit: toolOutputTokenLimit,
            backgroundTerminalMaxTimeoutMS: backgroundTerminalMaxTimeoutMS,
            shellEnvironmentPolicy: shellEnvironmentPolicy,
            ossProvider: ossProvider
        )
    }

    public init(
        model: String? = nil,
        modelProvider: String? = nil,
        modelProviders: [String: ModelProviderInfo] = [:],
        approvalPolicy: AskForApproval? = nil,
        sandboxMode: SandboxMode? = nil,
        sandboxPolicy: SandboxPolicy? = nil,
        modelReasoningEffort: ReasoningEffort? = nil,
        planModeReasoningEffort: ReasoningEffort? = nil,
        modelReasoningSummary: ReasoningSummary? = nil,
        modelSupportsReasoningSummaries: Bool? = nil,
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
        shellEnvironmentPolicy: ShellEnvironmentPolicy = ShellEnvironmentPolicy(),
        ossProvider: String? = nil
    ) {
        self.init(
            model: model,
            modelProvider: modelProvider,
            modelProviders: modelProviders,
            approvalPolicy: approvalPolicy,
            sandboxMode: sandboxMode,
            sandboxPolicy: sandboxPolicy,
            modelReasoningEffort: modelReasoningEffort,
            planModeReasoningEffort: planModeReasoningEffort,
            modelReasoningSummary: modelReasoningSummary,
            modelSupportsReasoningSummaries: modelSupportsReasoningSummaries,
            modelVerbosity: modelVerbosity,
            serviceTier: serviceTier,
            chatgptBaseURL: chatgptBaseURL,
            realtimeAudio: realtimeAudio,
            cliAuthCredentialsStoreMode: cliAuthCredentialsStoreMode,
            forcedLoginMethod: forcedLoginMethod,
            forcedChatGPTWorkspaceID: forcedChatGPTWorkspaceID,
            experimentalInstructionsFile: experimentalInstructionsFile,
            experimentalCompactPromptFile: experimentalCompactPromptFile,
            baseInstructions: baseInstructions,
            developerInstructions: developerInstructions,
            compactPrompt: compactPrompt,
            includePermissionsInstructions: true,
            includeAppsInstructions: true,
            includeSkillInstructions: true,
            includeEnvironmentContext: true,
            includeApplyPatchTool: includeApplyPatchTool,
            experimentalUseUnifiedExecTool: experimentalUseUnifiedExecTool,
            experimentalUseFreeformApplyPatch: experimentalUseFreeformApplyPatch,
            experimentalRealtimeWSBaseURL: experimentalRealtimeWSBaseURL,
            experimentalRealtimeWSModel: experimentalRealtimeWSModel,
            realtime: realtime,
            experimentalRealtimeWSBackendPrompt: experimentalRealtimeWSBackendPrompt,
            experimentalRealtimeWSStartupContext: experimentalRealtimeWSStartupContext,
            experimentalRealtimeStartInstructions: experimentalRealtimeStartInstructions,
            experimentalThreadConfigEndpoint: experimentalThreadConfigEndpoint,
            experimentalThreadStore: experimentalThreadStore,
            webSearchMode: webSearchMode,
            webSearchConfig: webSearchConfig,
            toolsWebSearch: toolsWebSearch,
            toolsViewImage: toolsViewImage,
            features: features,
            memories: MemoriesConfig(),
            mcpServers: mcpServers,
            mcpOAuthCredentialsStoreMode: mcpOAuthCredentialsStoreMode,
            mcpOAuthCallbackPort: mcpOAuthCallbackPort,
            mcpOAuthCallbackURL: mcpOAuthCallbackURL,
            activeProfile: activeProfile,
            projectRootMarkers: projectRootMarkers,
            projectDocMaxBytes: projectDocMaxBytes,
            projectDocFallbackFilenames: projectDocFallbackFilenames,
            toolOutputTokenLimit: toolOutputTokenLimit,
            shellEnvironmentPolicy: shellEnvironmentPolicy,
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
        planModeReasoningEffort: ReasoningEffort? = nil,
        modelReasoningSummary: ReasoningSummary?,
        modelSupportsReasoningSummaries: Bool? = nil,
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
        memories: MemoriesConfig = MemoriesConfig(),
        mcpServers: [String: McpServerConfig],
        mcpOAuthCredentialsStoreMode: OAuthCredentialsStoreMode,
        mcpOAuthCallbackPort: UInt16?,
        mcpOAuthCallbackURL: String?,
        activeProfile: String?,
        projectRootMarkers: [String],
        projectDocMaxBytes: Int,
        projectDocFallbackFilenames: [String],
        toolOutputTokenLimit: Int?,
        shellEnvironmentPolicy: ShellEnvironmentPolicy = ShellEnvironmentPolicy(),
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
            planModeReasoningEffort: planModeReasoningEffort,
            modelReasoningSummary: modelReasoningSummary,
            modelSupportsReasoningSummaries: modelSupportsReasoningSummaries,
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
            memories: memories,
            mcpServers: mcpServers,
            mcpOAuthCredentialsStoreMode: mcpOAuthCredentialsStoreMode,
            mcpOAuthCallbackPort: mcpOAuthCallbackPort,
            mcpOAuthCallbackURL: mcpOAuthCallbackURL,
            activeProfile: activeProfile,
            projectRootMarkers: projectRootMarkers,
            projectDocMaxBytes: projectDocMaxBytes,
            projectDocFallbackFilenames: projectDocFallbackFilenames,
            toolOutputTokenLimit: toolOutputTokenLimit,
            shellEnvironmentPolicy: shellEnvironmentPolicy,
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
        planModeReasoningEffort: ReasoningEffort? = nil,
        modelReasoningSummary: ReasoningSummary?,
        modelSupportsReasoningSummaries: Bool? = nil,
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
        shellEnvironmentPolicy: ShellEnvironmentPolicy = ShellEnvironmentPolicy(),
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
            planModeReasoningEffort: planModeReasoningEffort,
            modelReasoningSummary: modelReasoningSummary,
            modelSupportsReasoningSummaries: modelSupportsReasoningSummaries,
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
            shellEnvironmentPolicy: shellEnvironmentPolicy,
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

    public var modelFamilyConfigOverrides: ModelFamilyConfigOverrides {
        ModelFamilyConfigOverrides(
            supportsReasoningSummaries: modelSupportsReasoningSummaries,
            contextWindow: modelContextWindow,
            autoCompactTokenLimit: modelAutoCompactTokenLimit
        )
    }
}

public struct ExternalConfigMigrationPromptsConfig: Equatable, Sendable {
    public var home: Bool?
    public var homeLastPromptedAt: Int64?
    public var projects: [String: Bool]
    public var projectLastPromptedAt: [String: Int64]

    public init(
        home: Bool? = nil,
        homeLastPromptedAt: Int64? = nil,
        projects: [String: Bool] = [:],
        projectLastPromptedAt: [String: Int64] = [:]
    ) {
        self.home = home
        self.homeLastPromptedAt = homeLastPromptedAt
        self.projects = projects
        self.projectLastPromptedAt = projectLastPromptedAt
    }
}

public struct NoticeConfig: Equatable, Sendable {
    public var hideFullAccessWarning: Bool?
    public var hideWorldWritableWarning: Bool?
    public var fastDefaultOptOut: Bool?
    public var hideRateLimitModelNudge: Bool?
    public var hideGPT51MigrationPrompt: Bool?
    public var hideGPT51CodexMaxMigrationPrompt: Bool?
    public var modelMigrations: [String: String]
    public var externalConfigMigrationPrompts: ExternalConfigMigrationPromptsConfig

    public init(
        hideFullAccessWarning: Bool? = nil,
        hideWorldWritableWarning: Bool? = nil,
        fastDefaultOptOut: Bool? = nil,
        hideRateLimitModelNudge: Bool? = nil,
        hideGPT51MigrationPrompt: Bool? = nil,
        hideGPT51CodexMaxMigrationPrompt: Bool? = nil,
        modelMigrations: [String: String] = [:],
        externalConfigMigrationPrompts: ExternalConfigMigrationPromptsConfig = ExternalConfigMigrationPromptsConfig()
    ) {
        self.hideFullAccessWarning = hideFullAccessWarning
        self.hideWorldWritableWarning = hideWorldWritableWarning
        self.fastDefaultOptOut = fastDefaultOptOut
        self.hideRateLimitModelNudge = hideRateLimitModelNudge
        self.hideGPT51MigrationPrompt = hideGPT51MigrationPrompt
        self.hideGPT51CodexMaxMigrationPrompt = hideGPT51CodexMaxMigrationPrompt
        self.modelMigrations = modelMigrations
        self.externalConfigMigrationPrompts = externalConfigMigrationPrompts
    }
}

public enum CodexConfigLoadError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidConfig(String)
    case invalidStringValue(String)
    case invalidBoolValue(String)
    case invalidAuthCredentialsStoreMode
    case invalidOAuthCredentialsStoreMode
    case invalidForcedLoginMethod
    case invalidProjectRootMarkers
    case modelProviderNotFound(String)
    case reservedModelProviderOverride([String])
    case unsupportedProviderAWS(String)
    case unsupportedAmazonBedrockOverride
    case invalidModelProvider(String)
    case invalidConfigLine(String)
    case invalidTableHeader(String)
    case profileNotFound(String)
    case unsupportedExperimentalThreadStoreEndpoint

    public var description: String {
        switch self {
        case let .invalidConfig(message):
            return message
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
        case let .unsupportedProviderAWS(providerID):
            return "model_providers.\(providerID): provider aws is only supported for `amazon-bedrock`"
        case .unsupportedAmazonBedrockOverride:
            return "model_providers.amazon-bedrock only supports changing `aws.profile` and `aws.region`; other non-default provider fields are not supported"
        case let .invalidModelProvider(message):
            return message
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
        threadConfigSources: [ThreadConfigSource] = [],
        fileManager: FileManager = .default,
        systemConfigFile: URL? = defaultSystemConfigFile(),
        managedConfigOverrides: ConfigLayerLoaderOverrides = ConfigLayerLoaderOverrides(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> CodexRuntimeConfig {
        var parsed = ParsedCodexConfigToml()
        let userConfigFile = codexHome.appendingPathComponent("config.toml", isDirectory: false).standardizedFileURL
        parsed.agentRoleDiscoveryDirs.append(codexHome.appendingPathComponent("agents", isDirectory: true))
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
                    var projectConfig = try ParsedCodexConfigToml.parse(
                        contents,
                        baseURL: configFile.deletingLastPathComponent()
                    )
                    let ignoredKeys = projectConfig.removeProjectLocalDenylistedKeys()
                    if !ignoredKeys.isEmpty {
                        parsed.startupWarnings.append(ParsedCodexConfigToml.projectIgnoredConfigKeysWarning(
                            configFile: configFile,
                            ignoredKeys: ignoredKeys
                        ))
                    }
                    parsed.merge(projectConfig)
                }
            }
        }

        try parsed.apply(overrides: overrides)
        for source in threadConfigSources {
            if let layer = try source.configLayerEntry() {
                try parsed.merge(layer.config)
            }
        }
        let managedConfigLayers = try CodexConfigLayerLoader.loadConfigLayers(
            codexHome: codexHome,
            overrides: managedConfigOverrides,
            environment: environment,
            fileManager: fileManager
        )
        try parsed.merge(managedConfigLayers)

        var requirementsToml = ConfigRequirementsToml()
        if !managedConfigOverrides.ignoreManagedRequirements {
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
        }

        let requirements = try requirementsToml.requirements()
        var config = try parsed.resolvedConfig(environment: environment)
        config.sqliteHome = config.sqliteHome ?? {
            let sqliteHome = environment["CODEX_SQLITE_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            return sqliteHome?.isEmpty == false ? environment["CODEX_SQLITE_HOME"] : codexHome.standardizedFileURL.path
        }()
        config.logDir = config.logDir ?? codexHome
            .appendingPathComponent("log", isDirectory: true)
            .standardizedFileURL
            .path
        config.modelCatalog = try loadModelCatalog(from: config.modelCatalogJSON)
        try applyRequirements(requirements, to: &config)
        config.sandboxPolicy = try parsed.resolvedSandboxPolicy(
            codexHome: codexHome,
            fileManager: fileManager,
            sandboxMode: config.sandboxMode
        )
        if let defaultPermissions = config.defaultPermissions {
            config.permissionProfile = try parsed.permissionProfile(
                named: defaultPermissions,
                codexHome: codexHome,
                cwd: cwd ?? codexHome,
                fileManager: fileManager
            )
            config.activePermissionProfile = ActivePermissionProfile(id: defaultPermissions)
            let networkProxyConfig = try parsed.networkProxyConfig(named: defaultPermissions)
            if networkProxyConfig.network.enabled {
                config.networkProxy = NetworkProxySpec.fromConfigAndRequirements(
                    networkProxyConfig,
                    requirements: nil,
                    permissionProfile: config.permissionProfile ?? .readOnly()
                )
            }
        } else if parsed.permissions.isEmpty == false {
            throw CodexConfigLoadError.invalidConfigLine(
                "config defines `[permissions]` profiles but does not set `default_permissions`"
            )
        }
        try applyPermissionRequirements(
            requirements,
            to: &config,
            cwd: cwd ?? codexHome
        )
        applyNetworkRequirements(requirements, to: &config)
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

    private static func loadModelCatalog(from path: String?) throws -> ModelsResponse? {
        guard let path else {
            return nil
        }
        let url = URL(fileURLWithPath: path, isDirectory: false)
        let data = try Data(contentsOf: url)
        let catalog: ModelsResponse
        do {
            catalog = try JSONDecoder().decode(ModelsResponse.self, from: data)
        } catch {
            throw CodexConfigLoadError.invalidConfig(
                "failed to parse model_catalog_json path `\(path)` as JSON: \(error)"
            )
        }
        guard !catalog.models.isEmpty else {
            throw CodexConfigLoadError.invalidConfig(
                "model_catalog_json path `\(path)` must contain at least one model"
            )
        }
        return catalog
    }

    private static func applyRequirements(
        _ requirements: ConfigRequirements,
        to config: inout CodexRuntimeConfig
    ) throws {
        let approvalPolicy = config.approvalPolicy ?? AskForApproval.defaultValue
        try requirements.approvalPolicy.canSet(approvalPolicy).get()

        if case .failure = requirements.approvalsReviewer.canSet(config.approvalsReviewer) {
            config.approvalsReviewer = requirements.approvalsReviewer.value
        }

        let sandboxPolicy = config.legacySandboxPolicy()
        try requirements.sandboxPolicy.canSet(sandboxPolicy).get()
    }

    private static func applyPermissionRequirements(
        _ requirements: ConfigRequirements,
        to config: inout CodexRuntimeConfig,
        cwd: URL
    ) throws {
        guard let filesystem = requirements.filesystem,
              !filesystem.denyRead.isEmpty
        else {
            return
        }

        let cwdPath = cwd.standardizedFileURL.path
        var activeProfileWasForcedToFallback = false
        var profile = config.permissionProfile ?? .fromLegacySandboxPolicyForCwd(
            config.legacySandboxPolicy(),
            cwd: cwdPath
        )

        if !profile.allowsManagedFilesystemRequirements {
            profile = .readOnly()
            activeProfileWasForcedToFallback = true
        }

        var fileSystemPolicy = profile.fileSystemSandboxPolicy
        applyManagedFilesystemConstraints(filesystem, to: &fileSystemPolicy)
        let effectiveProfile = PermissionProfile.fromRuntimePermissionsWithEnforcement(
            profile.enforcement,
            fileSystem: fileSystemPolicy,
            network: profile.networkSandboxPolicy
        )

        config.permissionProfile = effectiveProfile
        if activeProfileWasForcedToFallback {
            config.activePermissionProfile = nil
        }
        if let legacyPolicy = try? fileSystemPolicy.toLegacySandboxPolicy(
            networkPolicy: effectiveProfile.networkSandboxPolicy,
            cwd: cwdPath
        ) {
            config.sandboxPolicy = legacyPolicy
        }
    }

    private static func applyManagedFilesystemConstraints(
        _ constraints: FilesystemConstraints,
        to fileSystemPolicy: inout FileSystemSandboxPolicy
    ) {
        guard case let .restricted(currentEntries, globScanMaxDepth) = fileSystemPolicy else {
            return
        }

        var entries = currentEntries
        for denyRead in constraints.denyRead {
            let entry: FileSystemSandboxEntry
            if denyRead.value.contains(where: isGlobMetacharacter) {
                entry = FileSystemSandboxEntry(path: .globPattern(denyRead.value), access: .none)
            } else {
                guard let absolutePath = try? AbsolutePath(absolutePath: denyRead.value) else {
                    continue
                }
                entry = FileSystemSandboxEntry(path: .path(absolutePath.path), access: .none)
            }
            if !entries.contains(entry) {
                entries.append(entry)
            }
        }
        fileSystemPolicy = .restricted(entries: entries, globScanMaxDepth: globScanMaxDepth)
    }

    private static func isGlobMetacharacter(_ character: Character) -> Bool {
        character == "*" || character == "?" || character == "["
    }

    private static func applyNetworkRequirements(
        _ requirements: ConfigRequirements,
        to config: inout CodexRuntimeConfig
    ) {
        guard let network = requirements.network else {
            return
        }
        let permissionProfile = config.permissionProfile ?? .fromLegacySandboxPolicy(config.legacySandboxPolicy())
        let spec = NetworkProxySpec.fromConfigAndRequirements(
            config.networkProxy?.config ?? NetworkProxyConfig(),
            requirements: network,
            permissionProfile: permissionProfile
        )
        config.networkProxy = spec
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

private struct ParsedPermissionProfileToml: Equatable, Sendable {
    var filesystem: [String: ConfigValue] = [:]
    var network: [String: ConfigValue] = [:]

    mutating func merge(_ overlay: ParsedPermissionProfileToml) {
        for (key, value) in overlay.filesystem {
            filesystem[key] = value
        }
        for (key, value) in overlay.network {
            network[key] = value
        }
    }

    func permissionProfile(profileName: String, cwd: URL) throws -> PermissionProfile {
        let entries = try filesystem.flatMap { key, value -> [FileSystemSandboxEntry] in
            guard key != "glob_scan_max_depth" else {
                return []
            }
            return try filesystemEntries(
                key,
                value: value,
                profileName: profileName,
                cwd: cwd
            )
        }.sorted { left, right in
            filesystemSortKey(left.path) < filesystemSortKey(right.path)
        }
        let globScanMaxDepth = try filesystem["glob_scan_max_depth"].map {
            try nonNegativeInt($0, key: "permissions.\(profileName).filesystem.glob_scan_max_depth")
        }
        let networkEnabled = try network["enabled"].map {
            try boolValue($0, key: "permissions.\(profileName).network.enabled")
        } ?? false
        return .managed(
            fileSystem: .restricted(entries: entries, globScanMaxDepth: globScanMaxDepth),
            network: networkEnabled ? .enabled : .restricted
        )
    }

    func networkProxyConfig(profileName: String) throws -> NetworkProxyConfig {
        var config = NetworkProxyConfig()
        try applyNetworkFields(profileName: profileName, to: &config)
        config.network.enabled = try networkRequiresProxy(profileName: profileName)
        return config
    }

    private func networkRequiresProxy(profileName: String) throws -> Bool {
        guard try network["enabled"].map({
            try boolValue($0, key: "permissions.\(profileName).network.enabled")
        }) == true else {
            return false
        }
        if network["proxy_url"] != nil
            || network["socks_url"] != nil
            || network["mode"] != nil
        {
            return true
        }
        if try network["domains"].map({
            try !tableValue($0, key: "permissions.\(profileName).network.domains").isEmpty
        }) == true {
            return true
        }
        if try network["unix_sockets"].map({
            try !tableValue($0, key: "permissions.\(profileName).network.unix_sockets").isEmpty
        }) == true {
            return true
        }
        for key in [
            "enable_socks5",
            "enable_socks5_udp",
            "allow_upstream_proxy",
            "dangerously_allow_non_loopback_proxy",
            "dangerously_allow_all_unix_sockets",
            "allow_local_binding"
        ] {
            if try network[key].map({ try boolValue($0, key: "permissions.\(profileName).network.\(key)") }) == true {
                return true
            }
        }
        return false
    }

    private func applyNetworkFields(profileName: String, to config: inout NetworkProxyConfig) throws {
        if let enabled = network["enabled"] {
            config.network.enabled = try boolValue(enabled, key: "permissions.\(profileName).network.enabled")
        }
        if let proxyURL = network["proxy_url"] {
            config.network.proxyURL = try stringValue(proxyURL, key: "permissions.\(profileName).network.proxy_url")
        }
        if let enableSocks5 = network["enable_socks5"] {
            config.network.enableSocks5 = try boolValue(
                enableSocks5,
                key: "permissions.\(profileName).network.enable_socks5"
            )
        }
        if let socksURL = network["socks_url"] {
            config.network.socksURL = try stringValue(socksURL, key: "permissions.\(profileName).network.socks_url")
        }
        if let enableSocks5UDP = network["enable_socks5_udp"] {
            config.network.enableSocks5UDP = try boolValue(
                enableSocks5UDP,
                key: "permissions.\(profileName).network.enable_socks5_udp"
            )
        }
        if let allowUpstreamProxy = network["allow_upstream_proxy"] {
            config.network.allowUpstreamProxy = try boolValue(
                allowUpstreamProxy,
                key: "permissions.\(profileName).network.allow_upstream_proxy"
            )
        }
        if let allowNonLoopback = network["dangerously_allow_non_loopback_proxy"] {
            config.network.dangerouslyAllowNonLoopbackProxy = try boolValue(
                allowNonLoopback,
                key: "permissions.\(profileName).network.dangerously_allow_non_loopback_proxy"
            )
        }
        if let allowAllUnixSockets = network["dangerously_allow_all_unix_sockets"] {
            config.network.dangerouslyAllowAllUnixSockets = try boolValue(
                allowAllUnixSockets,
                key: "permissions.\(profileName).network.dangerously_allow_all_unix_sockets"
            )
        }
        if let mode = network["mode"] {
            config.network.mode = try stringEnumValue(
                NetworkMode.self,
                mode,
                key: "permissions.\(profileName).network.mode"
            )
        }
        if let domains = network["domains"] {
            try applyNetworkDomainPermissions(domains, profileName: profileName, to: &config)
        }
        if let unixSockets = network["unix_sockets"] {
            try applyNetworkUnixSocketPermissions(unixSockets, profileName: profileName, to: &config)
        }
        if let allowLocalBinding = network["allow_local_binding"] {
            config.network.allowLocalBinding = try boolValue(
                allowLocalBinding,
                key: "permissions.\(profileName).network.allow_local_binding"
            )
        }
    }

    private func applyNetworkDomainPermissions(
        _ value: ConfigValue,
        profileName: String,
        to config: inout NetworkProxyConfig
    ) throws {
        let table = try tableValue(value, key: "permissions.\(profileName).network.domains")
        for pattern in table.keys.sorted() {
            guard let rawPermission = try? stringValue(
                table[pattern] ?? .string(""),
                key: "permissions.\(profileName).network.domains.\(pattern)"
            ),
                let permission = NetworkDomainPermission(rawValue: rawPermission)
            else {
                throw CodexConfigLoadError.invalidStringValue(
                    "permissions.\(profileName).network.domains.\(pattern)"
                )
            }
            config.network.upsertDomainPermission(pattern, permission: permission)
        }
    }

    private func applyNetworkUnixSocketPermissions(
        _ value: ConfigValue,
        profileName: String,
        to config: inout NetworkProxyConfig
    ) throws {
        let table = try tableValue(value, key: "permissions.\(profileName).network.unix_sockets")
        var sockets = config.network.unixSockets ?? [:]
        for path in table.keys.sorted() {
            guard let rawPermission = try? stringValue(
                table[path] ?? .string(""),
                key: "permissions.\(profileName).network.unix_sockets.\(path)"
            ),
                let permission = NetworkUnixSocketPermission(rawValue: rawPermission)
            else {
                throw CodexConfigLoadError.invalidStringValue(
                    "permissions.\(profileName).network.unix_sockets.\(path)"
                )
            }
            sockets[path] = permission
        }
        config.network.unixSockets = sockets.isEmpty ? nil : sockets
    }

    private func filesystemEntries(
        _ rawPath: String,
        value: ConfigValue,
        profileName: String,
        cwd: URL
    ) throws -> [FileSystemSandboxEntry] {
        let key = "permissions.\(profileName).filesystem.\(rawPath)"
        if case let .table(scopedEntries) = value {
            return try scopedEntries.map { subpath, scopedValue in
                let access = try filesystemAccess(scopedValue, key: "\(key).\(subpath)")
                if containsGlobCharacters(subpath),
                   access == .none,
                   canCompileScopedGlobPattern(basePath: rawPath)
                {
                    return FileSystemSandboxEntry(
                        path: .globPattern(try scopedFilesystemPattern(rawPath, subpath: subpath, cwd: cwd)),
                        access: access
                    )
                }
                let compiledSubpath = try compileReadWriteGlobSubpath(subpath, access: access)
                return FileSystemSandboxEntry(
                    path: try scopedFilesystemPath(rawPath, subpath: compiledSubpath, cwd: cwd),
                    access: access
                )
            }
        }

        let access = try filesystemAccess(value, key: key)
        return [
            FileSystemSandboxEntry(
                path: try filesystemAccessPath(rawPath, access: access, cwd: cwd),
                access: access
            )
        ]
    }

    private func filesystemAccessPath(_ raw: String, access: FileSystemAccessMode, cwd: URL) throws -> FileSystemPath {
        if !containsGlobCharacters(raw) {
            return try filesystemPath(raw, cwd: cwd)
        }
        if access == .none {
            return .globPattern(try absolutePathString(raw, cwd: cwd))
        }
        return try filesystemPath(compileReadWriteGlobSubpath(raw, access: access), cwd: cwd)
    }

    private func filesystemPath(_ raw: String, cwd: URL) throws -> FileSystemPath {
        if let special = filesystemSpecialPath(raw) {
            return .special(special.jsonValue)
        }
        return .path(try absolutePathString(raw, cwd: cwd))
    }

    private func scopedFilesystemPath(_ raw: String, subpath: String, cwd: URL) throws -> FileSystemPath {
        if subpath == "." {
            return try filesystemPath(raw, cwd: cwd)
        }

        let relativeSubpath = try parseRelativeSubpath(subpath)
        if let special = filesystemSpecialPath(raw) {
            switch special {
            case .projectRoots:
                return .special(FileSystemSpecialPath.projectRoots(subpath: relativeSubpath).jsonValue)
            case let .unknown(path, _):
                return .special(FileSystemSpecialPath.unknown(path: path, subpath: relativeSubpath).jsonValue)
            case .root, .minimal, .tmpdir, .slashTmp:
                throw CodexConfigLoadError.invalidConfigLine(
                    "filesystem path `\(raw)` does not support nested entries"
                )
            }
        }

        let base = try absolutePathString(raw, cwd: cwd)
        return .path(try AbsolutePath.resolve(relativeSubpath, against: base).path)
    }

    private func scopedFilesystemPattern(_ raw: String, subpath: String, cwd: URL) throws -> String {
        let relativeSubpath = try parseRelativeSubpath(subpath)
        if let special = filesystemSpecialPath(raw) {
            switch special {
            case .projectRoots:
                return try AbsolutePath.resolve(relativeSubpath, against: cwd.standardizedFileURL.path).path
            case .root, .minimal, .tmpdir, .slashTmp, .unknown:
                throw CodexConfigLoadError.invalidConfigLine(
                    "filesystem path `\(raw)` does not support nested entries"
                )
            }
        }

        let base = try absolutePathString(raw, cwd: cwd)
        return try AbsolutePath.resolve(relativeSubpath, against: base).path
    }

    private func absolutePathString(_ raw: String, cwd: URL) throws -> String {
        guard raw.hasPrefix("/") else {
            throw CodexConfigLoadError.invalidConfigLine(
                "filesystem path `\(raw)` must be absolute, use `~/...`, or start with `:`"
            )
        }
        return try AbsolutePath.resolve(raw, against: cwd.standardizedFileURL.path).path
    }

    private func filesystemSpecialPath(_ raw: String) -> FileSystemSpecialPath? {
        switch raw {
        case ":minimal":
            return .minimal
        case ":root":
            return .root
        case ":project_roots", ":cwd":
            return .projectRoots(subpath: nil)
        case ":tmpdir":
            return .tmpdir
        case ":slash_tmp":
            return .slashTmp
        default:
            return raw.hasPrefix(":") ? .unknown(path: raw, subpath: nil) : nil
        }
    }

    private func canCompileScopedGlobPattern(basePath: String) -> Bool {
        guard let special = filesystemSpecialPath(basePath) else {
            return true
        }
        switch special {
        case .projectRoots:
            return true
        case .root, .minimal, .tmpdir, .slashTmp, .unknown:
            return false
        }
    }

    private func compileReadWriteGlobSubpath(_ path: String, access: FileSystemAccessMode) throws -> String {
        guard containsGlobCharacters(path), access != .none else {
            return path
        }
        if path.hasSuffix("/**") {
            let withoutTrailingGlob = String(path.dropLast(3))
            if !containsGlobCharacters(withoutTrailingGlob) {
                return withoutTrailingGlob
            }
        }
        throw CodexConfigLoadError.invalidConfigLine(
            "filesystem glob path `\(path)` only supports `none` access; use an exact path or trailing `/**` for `\(access.rawValue)` subtree access"
        )
    }

    private func parseRelativeSubpath(_ subpath: String) throws -> String {
        guard !subpath.isEmpty,
              subpath.hasPrefix("/") == false,
              subpath.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ component in
                  component.isEmpty == false && component != "." && component != ".."
              })
        else {
            throw CodexConfigLoadError.invalidConfigLine(
                "filesystem subpath `\(subpath)` must be a descendant path without `.` or `..` components"
            )
        }
        return subpath
    }

    private func containsGlobCharacters(_ path: String) -> Bool {
        path.contains { character in
            character == "*" || character == "?" || character == "[" || character == "]"
        }
    }

    private func filesystemAccess(_ value: ConfigValue, key: String) throws -> FileSystemAccessMode {
        guard case let .string(raw) = value,
              let access = FileSystemAccessMode(rawValue: raw)
        else {
            throw CodexConfigLoadError.invalidStringValue(key)
        }
        return access
    }

    private func boolValue(_ value: ConfigValue, key: String) throws -> Bool {
        guard case let .bool(bool) = value else {
            throw CodexConfigLoadError.invalidBoolValue(key)
        }
        return bool
    }

    private func stringValue(_ value: ConfigValue, key: String) throws -> String {
        guard case let .string(string) = value else {
            throw CodexConfigLoadError.invalidStringValue(key)
        }
        return string
    }

    private func tableValue(_ value: ConfigValue, key: String) throws -> [String: ConfigValue] {
        guard case let .table(table) = value else {
            throw CodexConfigLoadError.invalidStringValue(key)
        }
        return table
    }

    private func stringEnumValue<T: RawRepresentable>(
        _ type: T.Type,
        _ value: ConfigValue,
        key: String
    ) throws -> T where T.RawValue == String {
        let raw = try stringValue(value, key: key)
        guard let parsed = T(rawValue: raw) else {
            throw CodexConfigLoadError.invalidConfigLine(key)
        }
        return parsed
    }

    private func nonNegativeInt(_ value: ConfigValue, key: String) throws -> Int {
        guard case let .integer(integer) = value, integer > 0, integer <= Int64(Int.max) else {
            throw CodexConfigLoadError.invalidConfigLine(key)
        }
        return Int(integer)
    }

    private func filesystemSortKey(_ path: FileSystemPath) -> String {
        switch path {
        case let .path(path):
            return "0:\(path)"
        case let .globPattern(pattern):
            return "1:\(pattern)"
        case let .special(value):
            switch FileSystemSpecialPath(jsonValue: value) {
            case .minimal:
                return "2:0:minimal"
            case let .projectRoots(subpath?):
                return "2:1:project_roots:\(subpath)"
            case .projectRoots(nil):
                return "2:2:project_roots"
            case .root:
                return "2:3:root"
            case .tmpdir:
                return "2:4:tmpdir"
            case .slashTmp:
                return "2:5:slash_tmp"
            case let .unknown(path, subpath):
                return "2:6:\(path):\(subpath ?? "")"
            }
        }
    }
}

private struct ParsedCodexConfigToml {
    private static let webSearchToolConfigKey = "__tools_web_search_config"
    private static let projectLocalConfigDenylist: [String] = [
        "openai_base_url",
        "chatgpt_base_url",
        "model_provider",
        "model_providers",
        "notify",
        "profile",
        "profiles",
        "experimental_realtime_ws_base_url",
        "otel"
    ]

    var topLevel: [String: ConfigValue] = [:]
    var profiles: [String: [String: ConfigValue]] = [:]
    var features: [String: Bool] = [:]
    var profileFeatures: [String: [String: Bool]] = [:]
    var appsMcpPathOverride: [String: ConfigValue] = [:]
    var profileAppsMcpPathOverride: [String: [String: ConfigValue]] = [:]
    var memories: [String: ConfigValue] = [:]
    var windows: [String: ConfigValue] = [:]
    var profileWindows: [String: [String: ConfigValue]] = [:]
    var mcpServers: [String: McpServerConfig] = [:]
    var modelProviders: [String: ConfigValue] = [:]
    var sandboxWorkspaceWrite: [String: ConfigValue] = [:]
    var history: [String: ConfigValue] = [:]
    var notice: [String: ConfigValue] = [:]
    var analytics: [String: ConfigValue] = [:]
    var feedback: [String: ConfigValue] = [:]
    var profileAnalytics: [String: [String: ConfigValue]] = [:]
    var agents: [String: ConfigValue] = [:]
    var agentRoles: [String: [String: ConfigValue]] = [:]
    var agentRoleDiscoveryDirs: [URL] = []
    var ignoredDenylistedTables: Set<String> = []
    var startupWarnings: [String] = []
    var realtimeAudio: [String: ConfigValue] = [:]
    var realtime: [String: ConfigValue] = [:]
    var tui: [String: ConfigValue] = [:]
    var tuiModelAvailabilityNux: [String: ConfigValue] = [:]
    var profileTui: [String: [String: ConfigValue]] = [:]
    var shellEnvironmentPolicy: [String: ConfigValue] = [:]
    var toolSuggest: [String: ConfigValue] = [:]
    var toolSuggestDisabledToolLayers: [[ToolSuggestDisabledTool]] = []
    var skillsIncludeInstructions: Bool?
    var permissions: [String: ParsedPermissionProfileToml] = [:]

    mutating func removeProjectLocalDenylistedKeys() -> [String] {
        let hasModelProviders = !modelProviders.isEmpty
        let hasProfiles = !profiles.isEmpty
            || !profileFeatures.isEmpty
            || !profileAppsMcpPathOverride.isEmpty
            || !profileAnalytics.isEmpty
            || !profileTui.isEmpty
        var ignoredKeys: [String] = []
        for key in Self.projectLocalConfigDenylist {
            let removedTopLevel = topLevel.removeValue(forKey: key) != nil
            let removedNested = (key == "model_providers" && hasModelProviders)
                || (key == "profiles" && hasProfiles)
                || ignoredDenylistedTables.contains(key)
            if removedTopLevel || removedNested {
                ignoredKeys.append(key)
            }
        }
        modelProviders.removeAll()
        profiles.removeAll()
        profileFeatures.removeAll()
        profileAppsMcpPathOverride.removeAll()
        profileAnalytics.removeAll()
        profileTui.removeAll()
        ignoredDenylistedTables.removeAll()
        return ignoredKeys
    }

    static func projectIgnoredConfigKeysWarning(configFile: URL, ignoredKeys: [String]) -> String {
        "Ignored unsupported project-local config keys in \(configFile.standardizedFileURL.path): \(ignoredKeys.joined(separator: ", ")). If you want these settings to apply, manually set them in your user-level config.toml."
    }

    static func parse(_ contents: String, baseURL: URL? = nil) throws -> ParsedCodexConfigToml {
        var parsed = ParsedCodexConfigToml()
        var section = ConfigSection.topLevel
        if let baseURL {
            parsed.agentRoleDiscoveryDirs.append(baseURL.appendingPathComponent("agents", isDirectory: true))
        }

        for line in try logicalTomlLines(contents) {
            if line.hasPrefix("[") {
                section = try parseSectionHeader(line)
                if case let .ignoredDenylistedTable(key) = section {
                    parsed.ignoredDenylistedTables.insert(key)
                }
                if case .toolSuggestDisabledToolsArray = section {
                    parsed.appendToolSuggestDisabledToolTable()
                }
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
                if case let .profileTui(name) = section {
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
                if case let .profileAnalytics(name) = section {
                    if parsed.profiles[name] == nil {
                        parsed.profiles[name] = [:]
                    }
                }
                if case let .profileWindows(name) = section {
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
                if key == "memories" {
                    let value = try ConfigValueParser.parseTomlLiteral(valueText)
                    guard case let .table(table) = value else {
                        throw CodexConfigLoadError.invalidConfigLine(key)
                    }
                    for (memoryKey, memoryValue) in table {
                        parsed.memories[canonicalMemoriesConfigKey(memoryKey)] = memoryValue
                    }
                    continue
                }
                if key == "history" {
                    let value = try ConfigValueParser.parseTomlLiteral(valueText)
                    guard case let .table(table) = value else {
                        throw CodexConfigLoadError.invalidConfigLine(key)
                    }
                    for (historyKey, historyValue) in table {
                        parsed.history[historyKey] = historyValue
                    }
                    continue
                }
                if key == "notice" {
                    let value = try ConfigValueParser.parseTomlLiteral(valueText)
                    guard case let .table(table) = value else {
                        throw CodexConfigLoadError.invalidConfigLine(key)
                    }
                    parsed.mergeNotice(table)
                    continue
                }
                if key == "windows" {
                    let value = try ConfigValueParser.parseTomlLiteral(valueText)
                    guard case let .table(table) = value else {
                        throw CodexConfigLoadError.invalidConfigLine(key)
                    }
                    for (windowsKey, windowsValue) in table {
                        parsed.windows[windowsKey] = windowsValue
                    }
                    continue
                }
                if key == "analytics" {
                    let value = try ConfigValueParser.parseTomlLiteral(valueText)
                    guard case let .table(table) = value else {
                        throw CodexConfigLoadError.invalidConfigLine(key)
                    }
                    for (analyticsKey, analyticsValue) in table {
                        parsed.analytics[analyticsKey] = analyticsValue
                    }
                    continue
                }
                if key == "feedback" {
                    let value = try ConfigValueParser.parseTomlLiteral(valueText)
                    guard case let .table(table) = value else {
                        throw CodexConfigLoadError.invalidConfigLine(key)
                    }
                    for (feedbackKey, feedbackValue) in table {
                        parsed.feedback[feedbackKey] = feedbackValue
                    }
                    continue
                }
                if key == "agents" {
                    let value = try ConfigValueParser.parseTomlLiteral(valueText)
                    guard case let .table(table) = value else {
                        throw CodexConfigLoadError.invalidConfigLine(key)
                    }
                    for (agentKey, agentValue) in table {
                        if Self.isRelevantAgentKey(agentKey) {
                            parsed.agents[agentKey] = agentValue
                            continue
                        }
                        if case let .table(roleTable) = agentValue {
                            try parsed.mergeAgentRole(
                                name: agentKey,
                                table: roleTable,
                                keyPrefix: "agents.\(agentKey)",
                                baseURL: baseURL
                            )
                        }
                    }
                    continue
                }
                guard isRelevantTopLevelKey(key) else { continue }
                parsed.topLevel[key] = try normalizePathLikeValue(
                    ConfigValueParser.parseTomlLiteral(valueText),
                    key: key,
                    baseURL: baseURL
                )
            case let .profile(name):
                if key == "tui",
                   case let .table(tuiTable) = try ConfigValueParser.parseTomlLiteral(valueText)
                {
                    for (tuiKey, tuiValue) in tuiTable {
                        parsed.profileTui[name, default: [:]][tuiKey] = tuiValue
                    }
                    continue
                }
                if key == "analytics",
                   case let .table(analyticsTable) = try ConfigValueParser.parseTomlLiteral(valueText)
                {
                    for (analyticsKey, analyticsValue) in analyticsTable {
                        parsed.profileAnalytics[name, default: [:]][analyticsKey] = analyticsValue
                    }
                    continue
                }
                if key == "windows",
                   case let .table(windowsTable) = try ConfigValueParser.parseTomlLiteral(valueText)
                {
                    for (windowsKey, windowsValue) in windowsTable {
                        parsed.profileWindows[name, default: [:]][windowsKey] = windowsValue
                    }
                    continue
                }
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
                try parsed.mergeFeatureValue(
                    key: key,
                    value: ConfigValueParser.parseTomlLiteral(valueText),
                    path: "features.\(key)",
                    profileName: nil
                )
            case .featuresAppsMcpPathOverride:
                try parsed.mergeAppsMcpPathOverrideConfig(
                    key: key,
                    value: ConfigValueParser.parseTomlLiteral(valueText),
                    path: "features.apps_mcp_path_override.\(key)",
                    profileName: nil
                )
            case .memories:
                parsed.memories[canonicalMemoriesConfigKey(key)] = try ConfigValueParser.parseTomlLiteral(valueText)
            case .sandboxWorkspaceWrite:
                parsed.sandboxWorkspaceWrite[key] = try ConfigValueParser.parseTomlLiteral(valueText)
            case .history:
                parsed.history[key] = try ConfigValueParser.parseTomlLiteral(valueText)
            case .notice:
                parsed.notice[try parseDottedKey(key).joined(separator: ".")] =
                    try ConfigValueParser.parseTomlLiteral(valueText)
            case .noticeModelMigrations:
                var migrations = parsed.notice["model_migrations"] ?? .table([:])
                migrations.merge(overlay: .table([
                    try parseDottedKey(key).joined(separator: "."): try ConfigValueParser.parseTomlLiteral(valueText)
                ]))
                parsed.notice["model_migrations"] = migrations
            case .noticeExternalConfigMigrationPrompts:
                var prompts = parsed.notice["external_config_migration_prompts"] ?? .table([:])
                prompts.merge(overlay: .table([
                    try parseDottedKey(key).joined(separator: "."): try ConfigValueParser.parseTomlLiteral(valueText)
                ]))
                parsed.notice["external_config_migration_prompts"] = prompts
            case .noticeExternalConfigMigrationPromptProjects:
                parsed.mergeNoticeExternalConfigMigrationPromptMap(
                    mapKey: "projects",
                    entryKey: try parseDottedKey(key).joined(separator: "."),
                    value: try ConfigValueParser.parseTomlLiteral(valueText)
                )
            case .noticeExternalConfigMigrationPromptProjectLastPromptedAt:
                parsed.mergeNoticeExternalConfigMigrationPromptMap(
                    mapKey: "project_last_prompted_at",
                    entryKey: try parseDottedKey(key).joined(separator: "."),
                    value: try ConfigValueParser.parseTomlLiteral(valueText)
                )
            case .windows:
                parsed.windows[key] = try ConfigValueParser.parseTomlLiteral(valueText)
            case .analytics:
                parsed.analytics[key] = try ConfigValueParser.parseTomlLiteral(valueText)
            case .feedback:
                parsed.feedback[key] = try ConfigValueParser.parseTomlLiteral(valueText)
            case let .profileAnalytics(name):
                parsed.profileAnalytics[name, default: [:]][key] = try ConfigValueParser.parseTomlLiteral(valueText)
            case let .profileWindows(name):
                parsed.profileWindows[name, default: [:]][key] = try ConfigValueParser.parseTomlLiteral(valueText)
            case .agents:
                if Self.isRelevantAgentKey(key) {
                    parsed.agents[key] = try ConfigValueParser.parseTomlLiteral(valueText)
                }
            case let .agentRole(name):
                try parsed.mergeAgentRole(
                    name: name,
                    key: key,
                    value: ConfigValueParser.parseTomlLiteral(valueText),
                    keyPrefix: "agents.\(name).\(key)",
                    baseURL: baseURL
                )
            case let .permissionFilesystem(name):
                let filesystemKey = try parseDottedKey(key).joined(separator: ".")
                parsed.permissions[name, default: ParsedPermissionProfileToml()]
                    .filesystem[filesystemKey] = try ConfigValueParser.parseTomlLiteral(valueText)
            case let .permissionFilesystemScoped(name, path):
                let scopedKey = try parseDottedKey(key).joined(separator: ".")
                let scopedValue = try ConfigValueParser.parseTomlLiteral(valueText)
                var existing = parsed.permissions[name, default: ParsedPermissionProfileToml()]
                    .filesystem[path] ?? .table([:])
                existing.merge(overlay: .table([scopedKey: scopedValue]))
                parsed.permissions[name, default: ParsedPermissionProfileToml()]
                    .filesystem[path] = existing
            case let .permissionNetwork(name):
                let networkKey = try parseDottedKey(key).joined(separator: ".")
                parsed.permissions[name, default: ParsedPermissionProfileToml()]
                    .network[networkKey] = try ConfigValueParser.parseTomlLiteral(valueText)
            case let .permissionNetworkMap(name, tableKey):
                let networkKey = try parseDottedKey(key).joined(separator: ".")
                var existing = parsed.permissions[name, default: ParsedPermissionProfileToml()]
                    .network[tableKey] ?? .table([:])
                existing.merge(overlay: .table([networkKey: try ConfigValueParser.parseTomlLiteral(valueText)]))
                parsed.permissions[name, default: ParsedPermissionProfileToml()]
                    .network[tableKey] = existing
            case .audio:
                parsed.realtimeAudio[key] = try ConfigValueParser.parseTomlLiteral(valueText)
            case .realtime:
                parsed.realtime[key] = try ConfigValueParser.parseTomlLiteral(valueText)
            case .tui:
                let value = try ConfigValueParser.parseTomlLiteral(valueText)
                if key == "model_availability_nux", case let .table(nuxTable) = value {
                    for (nuxKey, nuxValue) in nuxTable {
                        parsed.tuiModelAvailabilityNux[try parseDottedKey(nuxKey).joined(separator: ".")] = nuxValue
                    }
                    continue
                }
                parsed.tui[key] = value
            case .tuiModelAvailabilityNux:
                parsed.tuiModelAvailabilityNux[try parseDottedKey(key).joined(separator: ".")] =
                    try ConfigValueParser.parseTomlLiteral(valueText)
            case let .profileTui(name):
                parsed.profileTui[name, default: [:]][key] = try ConfigValueParser.parseTomlLiteral(valueText)
            case .shellEnvironmentPolicy:
                parsed.shellEnvironmentPolicy[key] = try ConfigValueParser.parseTomlLiteral(valueText)
            case .shellEnvironmentPolicySet:
                var setTable = parsed.shellEnvironmentPolicy["set"] ?? .table([:])
                setTable.merge(overlay: .table([key: try ConfigValueParser.parseTomlLiteral(valueText)]))
                parsed.shellEnvironmentPolicy["set"] = setTable
            case .skills:
                if key == "include_instructions" {
                    parsed.skillsIncludeInstructions = try Self.boolValue(
                        ConfigValueParser.parseTomlLiteral(valueText),
                        key: "skills.include_instructions"
                    )
                }
            case .toolSuggest:
                parsed.toolSuggest[key] = try ConfigValueParser.parseTomlLiteral(valueText)
            case .toolSuggestDisabledToolsArray:
                parsed.mergeIntoLastToolSuggestDisabledToolTable(
                    key: key,
                    value: try ConfigValueParser.parseTomlLiteral(valueText)
                )
            case let .profileFeatures(name):
                try parsed.mergeFeatureValue(
                    key: key,
                    value: ConfigValueParser.parseTomlLiteral(valueText),
                    path: "profiles.\(name).features.\(key)",
                    profileName: name
                )
            case let .profileFeaturesAppsMcpPathOverride(name):
                try parsed.mergeAppsMcpPathOverrideConfig(
                    key: key,
                    value: ConfigValueParser.parseTomlLiteral(valueText),
                    path: "profiles.\(name).features.apps_mcp_path_override.\(key)",
                    profileName: name
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
            case .ignored, .ignoredDenylistedTable:
                continue
            }
        }

        parsed.mcpServers = try McpConfigStore.parseMcpServers(from: contents)
        try parsed.recordToolSuggestDisabledToolLayer()
        return parsed
    }

    private static func logicalTomlLines(_ contents: String) throws -> [String] {
        var logicalLines: [String] = []
        var pending: String?

        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = stripComment(from: String(rawLine)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if let current = pending {
                let combined = current + "\n" + line
                if isCompleteTomlLine(combined) {
                    logicalLines.append(combined)
                    pending = nil
                } else {
                    pending = combined
                }
                continue
            }

            if isCompleteTomlLine(line) {
                logicalLines.append(line)
            } else {
                pending = line
            }
        }

        if let pending {
            throw CodexConfigLoadError.invalidConfigLine(pending)
        }
        return logicalLines
    }

    private static func isCompleteTomlLine(_ line: String) -> Bool {
        var quote: Character?
        var squareDepth = 0
        var braceDepth = 0
        var previousWasBackslash = false

        for character in line {
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
            default:
                continue
            }
        }

        return quote == nil && squareDepth <= 0 && braceDepth <= 0
    }

    private static func normalizePathLikeValue(_ value: ConfigValue, key: String, baseURL: URL?) throws -> ConfigValue {
        guard [
            "model_instructions_file",
            "experimental_instructions_file",
            "experimental_compact_prompt_file",
            "zsh_path",
            "sqlite_home",
            "log_dir",
            "model_catalog_json",
            "config_file"
        ].contains(key),
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

            if parts.count == 2, parts[0] == "memories" {
                memories[Self.canonicalMemoriesConfigKey(parts[1])] = value
                continue
            }

            if parts.count == 2, parts[0] == "notice" {
                notice[parts[1]] = value
                continue
            }

            if parts.count == 3, parts[0] == "notice", parts[1] == "model_migrations" {
                var migrations = notice["model_migrations"] ?? .table([:])
                migrations.merge(overlay: .table([parts[2]: value]))
                notice["model_migrations"] = migrations
                continue
            }

            if parts.count == 3, parts[0] == "notice", parts[1] == "external_config_migration_prompts" {
                var prompts = notice["external_config_migration_prompts"] ?? .table([:])
                prompts.merge(overlay: .table([parts[2]: value]))
                notice["external_config_migration_prompts"] = prompts
                continue
            }

            if parts.count == 4,
               parts[0] == "notice",
               parts[1] == "external_config_migration_prompts",
               ["projects", "project_last_prompted_at"].contains(parts[2])
            {
                mergeNoticeExternalConfigMigrationPromptMap(mapKey: parts[2], entryKey: parts[3], value: value)
                continue
            }

            if parts.count == 2, parts[0] == "sandbox_workspace_write" {
                sandboxWorkspaceWrite[parts[1]] = value
                continue
            }

            if parts.count == 2, parts[0] == "windows" {
                windows[parts[1]] = value
                continue
            }

            if parts.count == 2, parts[0] == "analytics" {
                analytics[parts[1]] = value
                continue
            }

            if parts.count == 2, parts[0] == "feedback" {
                feedback[parts[1]] = value
                continue
            }

            if parts.count == 1, parts[0] == "default_permissions" {
                topLevel[parts[0]] = value
                continue
            }

            if parts.count == 4, parts[0] == "permissions", parts[2] == "filesystem" {
                permissions[parts[1], default: ParsedPermissionProfileToml()].filesystem[parts[3]] = value
                continue
            }

            if parts.count == 5, parts[0] == "permissions", parts[2] == "filesystem" {
                var existing = permissions[parts[1], default: ParsedPermissionProfileToml()]
                    .filesystem[parts[3]] ?? .table([:])
                existing.merge(overlay: .table([parts[4]: value]))
                permissions[parts[1], default: ParsedPermissionProfileToml()].filesystem[parts[3]] = existing
                continue
            }

            if parts.count == 4, parts[0] == "permissions", parts[2] == "network" {
                permissions[parts[1], default: ParsedPermissionProfileToml()].network[parts[3]] = value
                continue
            }

            if parts.count == 5, parts[0] == "permissions", parts[2] == "network" {
                var existing = permissions[parts[1], default: ParsedPermissionProfileToml()]
                    .network[parts[3]] ?? .table([:])
                existing.merge(overlay: .table([parts[4]: value]))
                permissions[parts[1], default: ParsedPermissionProfileToml()].network[parts[3]] = existing
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

            if parts.count == 2, parts[0] == "tui" {
                tui[parts[1]] = value
                continue
            }

            if parts.count == 2, parts[0] == "agents" {
                if Self.isRelevantAgentKey(parts[1]) {
                    agents[parts[1]] = value
                }
                continue
            }

            if parts.count == 3, parts[0] == "agents" {
                try mergeAgentRole(
                    name: parts[1],
                    key: parts[2],
                    value: value,
                    keyPrefix: path,
                    baseURL: nil
                )
                continue
            }

            if parts.count == 3, parts[0] == "tui", parts[1] == "model_availability_nux" {
                tuiModelAvailabilityNux[try Self.parseDottedKey(path).dropFirst(2).joined(separator: ".")] = value
                continue
            }

            if parts.count == 4, parts[0] == "profiles", parts[2] == "tui" {
                profileTui[parts[1], default: [:]][parts[3]] = value
                continue
            }

            if parts.count == 4, parts[0] == "profiles", parts[2] == "analytics" {
                profileAnalytics[parts[1], default: [:]][parts[3]] = value
                continue
            }

            if parts.count == 4, parts[0] == "profiles", parts[2] == "windows" {
                profileWindows[parts[1], default: [:]][parts[3]] = value
                continue
            }

            if parts.count == 2, parts[0] == "skills", parts[1] == "include_instructions" {
                skillsIncludeInstructions = try Self.boolValue(value, key: path)
                continue
            }

            if parts.count == 2, parts[0] == "tool_suggest" {
                toolSuggest[parts[1]] = value
                if parts[1] == "disabled_tools" {
                    try recordToolSuggestDisabledToolLayer()
                }
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

        for (key, value) in overlay.appsMcpPathOverride {
            appsMcpPathOverride[key] = value
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

        for (key, value) in overlay.history {
            history[key] = value
        }

        mergeNotice(overlay.notice)

        for (key, value) in overlay.windows {
            windows[key] = value
        }

        for (key, value) in overlay.analytics {
            analytics[key] = value
        }

        for (key, value) in overlay.feedback {
            feedback[key] = value
        }

        for (profileName, profileValue) in overlay.profileAnalytics {
            var mergedProfile = profileAnalytics[profileName] ?? [:]
            for (key, value) in profileValue {
                mergedProfile[key] = value
            }
            profileAnalytics[profileName] = mergedProfile
        }

        for (profileName, profileValue) in overlay.profileWindows {
            var mergedProfile = profileWindows[profileName] ?? [:]
            for (key, value) in profileValue {
                mergedProfile[key] = value
            }
            profileWindows[profileName] = mergedProfile
        }

        for (key, value) in overlay.agents {
            agents[key] = value
        }

        for (roleName, roleValues) in overlay.agentRoles {
            var mergedRole = agentRoles[roleName] ?? [:]
            for (key, value) in roleValues {
                mergedRole[key] = value
            }
            agentRoles[roleName] = mergedRole
        }
        agentRoleDiscoveryDirs.append(contentsOf: overlay.agentRoleDiscoveryDirs)
        startupWarnings.append(contentsOf: overlay.startupWarnings)

        for (profileName, profileValue) in overlay.permissions {
            permissions[profileName, default: ParsedPermissionProfileToml()].merge(profileValue)
        }

        for (key, value) in overlay.realtimeAudio {
            realtimeAudio[key] = value
        }

        for (key, value) in overlay.realtime {
            realtime[key] = value
        }

        for (key, value) in overlay.tui {
            tui[key] = value
        }

        for (key, value) in overlay.tuiModelAvailabilityNux {
            tuiModelAvailabilityNux[key] = value
        }

        for (profileName, profileValue) in overlay.profileTui {
            var mergedProfile = profileTui[profileName] ?? [:]
            for (key, value) in profileValue {
                mergedProfile[key] = value
            }
            profileTui[profileName] = mergedProfile
        }

        for (key, value) in overlay.shellEnvironmentPolicy {
            shellEnvironmentPolicy[key] = value
        }

        for (key, value) in overlay.memories {
            memories[key] = value
        }

        for (key, value) in overlay.toolSuggest {
            toolSuggest[key] = value
        }
        toolSuggestDisabledToolLayers.append(contentsOf: overlay.toolSuggestDisabledToolLayers)

        if let skillsIncludeInstructions = overlay.skillsIncludeInstructions {
            self.skillsIncludeInstructions = skillsIncludeInstructions
        }

        for (profileName, profileValues) in overlay.profileFeatures {
            var mergedProfile = profileFeatures[profileName] ?? [:]
            for (key, value) in profileValues {
                mergedProfile[key] = value
            }
            profileFeatures[profileName] = mergedProfile
        }

        for (profileName, profileValues) in overlay.profileAppsMcpPathOverride {
            var mergedProfile = profileAppsMcpPathOverride[profileName] ?? [:]
            for (key, value) in profileValues {
                mergedProfile[key] = value
            }
            profileAppsMcpPathOverride[profileName] = mergedProfile
        }
    }

    mutating func merge(_ layers: LoadedConfigLayers) throws {
        if let managedConfig = layers.managedConfig {
            try merge(managedConfig.managedConfig)
        }
        if let managedConfigFromMDM = layers.managedConfigFromMDM {
            try merge(managedConfigFromMDM.managedConfig)
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

        if case let .table(windowsTable) = table["windows"] {
            for (key, value) in windowsTable {
                windows[key] = value
            }
        }

        if case let .table(permissionTable) = table["permissions"] {
            for (profileName, profileValue) in permissionTable {
                guard case let .table(profileTable) = profileValue else { continue }
                var parsedProfile = permissions[profileName] ?? ParsedPermissionProfileToml()
                if case let .table(filesystemTable)? = profileTable["filesystem"] {
                    for (key, value) in filesystemTable {
                        parsedProfile.filesystem[key] = value
                    }
                }
                if case let .table(networkTable)? = profileTable["network"] {
                    for (key, value) in networkTable {
                        parsedProfile.network[key] = value
                    }
                }
                permissions[profileName] = parsedProfile
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

        if case let .table(tuiTable) = table["tui"] {
            for (key, value) in tuiTable {
                if key == "model_availability_nux", case let .table(nuxTable) = value {
                    for (nuxKey, nuxValue) in nuxTable {
                        tuiModelAvailabilityNux[try Self.parseDottedKey(nuxKey).joined(separator: ".")] = nuxValue
                    }
                    continue
                }
                tui[key] = value
            }
        }

        if case let .table(agentsTable) = table["agents"] {
            for (key, value) in agentsTable {
                if Self.isRelevantAgentKey(key) {
                    agents[key] = value
                    continue
                }
                if case let .table(roleTable) = value {
                    try mergeAgentRole(
                        name: key,
                        table: roleTable,
                        keyPrefix: "agents.\(key)",
                        baseURL: nil
                    )
                }
            }
        }

        if case let .table(analyticsTable) = table["analytics"] {
            for (key, value) in analyticsTable {
                analytics[key] = value
            }
        }

        if case let .table(feedbackTable) = table["feedback"] {
            for (key, value) in feedbackTable {
                feedback[key] = value
            }
        }

        if case let .table(shellEnvironmentPolicyTable) = table["shell_environment_policy"] {
            for (key, value) in shellEnvironmentPolicyTable {
                shellEnvironmentPolicy[key] = value
            }
        }

        if case let .table(featureTable) = table["features"] {
            for (key, value) in featureTable {
                try mergeFeatureValue(key: key, value: value, path: "features.\(key)", profileName: nil)
            }
        }

        if case let .table(memoriesTable) = table["memories"] {
            for (key, value) in memoriesTable {
                memories[Self.canonicalMemoriesConfigKey(key)] = value
            }
        }

        if case let .table(noticeTable) = table["notice"] {
            mergeNotice(noticeTable)
        }

        if case let .table(skillsTable) = table["skills"],
           let includeInstructions = skillsTable["include_instructions"]
        {
            skillsIncludeInstructions = try Self.boolValue(
                includeInstructions,
                key: "skills.include_instructions"
            )
        }

        if case let .table(toolSuggestTable) = table["tool_suggest"] {
            for (key, value) in toolSuggestTable {
                toolSuggest[key] = value
            }
            try recordToolSuggestDisabledToolLayer(from: toolSuggestTable)
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
                            try mergeFeatureValue(
                                key: featureKey,
                                value: featureValue,
                                path: "profiles.\(profileName).features.\(featureKey)",
                                profileName: profileName
                            )
                        }
                    }

                    if key == "tools",
                       case let .table(toolsTable) = value,
                       let webSearchValue = toolsTable["web_search"]
                    {
                        Self.mergeWebSearchToolConfig(value: webSearchValue, into: &profiles[profileName, default: [:]])
                    }

                    if key == "tui", case let .table(tuiTable) = value {
                        for (tuiKey, tuiValue) in tuiTable {
                            profileTui[profileName, default: [:]][tuiKey] = tuiValue
                        }
                    }

                    if key == "analytics", case let .table(analyticsTable) = value {
                        for (analyticsKey, analyticsValue) in analyticsTable {
                            profileAnalytics[profileName, default: [:]][analyticsKey] = analyticsValue
                        }
                    }

                    if key == "windows", case let .table(windowsTable) = value {
                        for (windowsKey, windowsValue) in windowsTable {
                            profileWindows[profileName, default: [:]][windowsKey] = windowsValue
                        }
                    }
                }
            }
        }
    }

    func resolvedConfig(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> CodexRuntimeConfig {
        var config = CodexRuntimeConfig()
        config.notices = try Self.noticeConfigValue(notice, key: "notice")

        try Self.applyRuntimeFields(from: topLevel, to: &config, keyPrefix: "")
        config.realtimeAudio = try Self.realtimeAudioConfigValue(realtimeAudio, key: "audio")
        config.realtime = try Self.realtimeConfigValue(realtime, key: "realtime")
        config.history = try Self.historyConfigValue(history, key: "history")
        config.analyticsEnabled = try Self.enabledConfigValue(analytics, key: "analytics") ?? config.analyticsEnabled
        config.feedbackEnabled = try Self.enabledConfigValue(feedback, key: "feedback") ?? true
        config.agents = try Self.agentRuntimeConfigValue(agents, key: "agents")
        var startupWarnings = startupWarnings
        config.agentRoles = try Self.agentRoleConfigsValue(
            declaredRoles: agentRoles,
            discoveryDirs: agentRoleDiscoveryDirs,
            startupWarnings: &startupWarnings
        )
        config.startupWarnings = startupWarnings
        let activeProfileName = try topLevel["profile"].map { try Self.stringValue($0, key: "profile") }
        config.tui = try Self.tuiRuntimeConfigValue(
            tui,
            modelAvailabilityNux: tuiModelAvailabilityNux,
            profile: activeProfileName.flatMap { profileTui[$0] },
            key: "tui"
        )
        config.terminalResizeReflow = try Self.terminalResizeReflowConfigValue(tui, key: "tui")
        config.shellEnvironmentPolicy = try Self.shellEnvironmentPolicyValue(
            shellEnvironmentPolicy,
            key: "shell_environment_policy"
        )
        config.toolSuggest = try Self.toolSuggestConfigValue(
            table: toolSuggest,
            disabledToolLayers: toolSuggestDisabledToolLayers
        )
        config.memories = try Self.memoriesConfigValue(memories, key: "memories")

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

        if let maxTimeout = topLevel["background_terminal_max_timeout"] {
            let parsed = try Self.nonNegativeIntValue(maxTimeout, key: "background_terminal_max_timeout")
            config.backgroundTerminalMaxTimeoutMS = max(UInt64(parsed), UnifiedExecTiming.minEmptyYieldTimeMS)
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

        let activeProfile = activeProfileName
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
            config.analyticsEnabled = try Self.enabledConfigValue(
                profileAnalytics[activeProfile] ?? [:],
                key: "profiles.\(activeProfile).analytics"
            ) ?? config.analyticsEnabled
        }

        config.baseInstructions = try config.baseInstructions ?? Self.readNonEmptyFile(
            config.experimentalInstructionsFile,
            description: "experimental instructions file"
        )
        config.compactPrompt = try config.compactPrompt ?? Self.readNonEmptyFile(
            config.experimentalCompactPromptFile,
            description: "experimental compact prompt file"
        )
        config.includeSkillInstructions = skillsIncludeInstructions ?? true

        var featureStates = FeatureStates.withDefaults()
        featureStates.apply(featureValues: features)
        if let activeProfile = config.activeProfile {
            featureStates.apply(featureValues: profileFeatures[activeProfile] ?? [:])
        }
        config.appsMcpPathOverride = try Self.appsMcpPathOverrideValue(
            base: appsMcpPathOverride,
            profile: config.activeProfile.flatMap { profileAppsMcpPathOverride[$0] },
            features: featureStates
        )
        config.serviceTier = Self.normalizedServiceTier(
            config.serviceTier,
            features: featureStates
        )
        config.windowsSandboxLevel = try Self.windowsSandboxLevelValue(
            base: windows,
            profile: config.activeProfile.flatMap { profileWindows[$0] },
            profileFeatures: config.activeProfile.flatMap { profileFeatures[$0] } ?? [:],
            resolvedFeatures: featureStates
        )
        config.windowsSandboxPrivateDesktop = try Self.windowsSandboxPrivateDesktopValue(
            base: windows,
            profile: config.activeProfile.flatMap { profileWindows[$0] }
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
        config.modelProviders = try Self.combinedModelProviders(
            from: modelProviders,
            openAIBaseURL: config.openAIBaseURL,
            environment: environment
        )
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

    func permissionProfile(
        named profileName: String,
        codexHome: URL,
        cwd: URL,
        fileManager: FileManager
    ) throws -> PermissionProfile {
        switch profileName {
        case ":read-only":
            return .readOnly()
        case ":workspace":
            let policy = try resolvedSandboxPolicy(
                codexHome: codexHome,
                fileManager: fileManager,
                sandboxMode: .workspaceWrite
            ) ?? .newWorkspaceWritePolicy()
            return .fromLegacySandboxPolicyForCwd(policy, cwd: cwd.standardizedFileURL.path)
        case ":danger-no-sandbox":
            return .disabled
        default:
            if profileName.hasPrefix(":") {
                throw CodexConfigLoadError.invalidConfigLine(
                    "default_permissions refers to unknown built-in profile `\(profileName)`"
                )
            }
            guard let profile = permissions[profileName] else {
                let message = permissions.isEmpty
                    ? "default_permissions requires a `[permissions]` table"
                    : "default_permissions refers to undefined profile `\(profileName)`"
                throw CodexConfigLoadError.invalidConfigLine(message)
            }
            return try profile.permissionProfile(profileName: profileName, cwd: cwd)
        }
    }

    func networkProxyConfig(named profileName: String) throws -> NetworkProxyConfig {
        switch profileName {
        case ":read-only", ":workspace", ":danger-no-sandbox":
            return NetworkProxyConfig()
        default:
            if profileName.hasPrefix(":") {
                throw CodexConfigLoadError.invalidConfigLine(
                    "default_permissions refers to unknown built-in profile `\(profileName)`"
                )
            }
            guard let profile = permissions[profileName] else {
                let message = permissions.isEmpty
                    ? "default_permissions requires a `[permissions]` table"
                    : "default_permissions refers to undefined profile `\(profileName)`"
                throw CodexConfigLoadError.invalidConfigLine(message)
            }
            return try profile.networkProxyConfig(profileName: profileName)
        }
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

    private mutating func mergeNotice(_ table: [String: ConfigValue]) {
        var noticeValue = ConfigValue.table(notice)
        noticeValue.merge(overlay: .table(table))
        if case let .table(merged) = noticeValue {
            notice = merged
        }
    }

    private mutating func mergeNoticeExternalConfigMigrationPromptMap(
        mapKey: String,
        entryKey: String,
        value: ConfigValue
    ) {
        var prompts = notice["external_config_migration_prompts"] ?? .table([:])
        var mapValue: ConfigValue
        if case let .table(promptTable) = prompts,
           case let .table(existingMap)? = promptTable[mapKey]
        {
            mapValue = .table(existingMap)
        } else {
            mapValue = .table([:])
        }
        mapValue.merge(overlay: .table([entryKey: value]))
        prompts.merge(overlay: .table([mapKey: mapValue]))
        notice["external_config_migration_prompts"] = prompts
    }

    private mutating func mergeAgentRole(
        name: String,
        table: [String: ConfigValue],
        keyPrefix: String,
        baseURL: URL?
    ) throws {
        for (key, value) in table {
            try mergeAgentRole(
                name: name,
                key: key,
                value: value,
                keyPrefix: "\(keyPrefix).\(key)",
                baseURL: baseURL
            )
        }
    }

    private mutating func mergeAgentRole(
        name: String,
        key: String,
        value: ConfigValue,
        keyPrefix: String,
        baseURL: URL?
    ) throws {
        guard Self.isRelevantAgentRoleKey(key) else {
            throw CodexConfigLoadError.invalidConfigLine(keyPrefix)
        }
        agentRoles[name, default: [:]][key] = try Self.normalizePathLikeValue(
            value,
            key: key,
            baseURL: baseURL
        )
    }

    private mutating func mergeFeatureValue(
        key: String,
        value: ConfigValue,
        path: String,
        profileName: String?
    ) throws {
        if key == "apps_mcp_path_override", case let .table(table) = value {
            try mergeAppsMcpPathOverrideFeatureConfig(table, path: path, profileName: profileName)
            return
        }

        let enabled = try Self.boolValue(value, key: path)
        if let profileName {
            profileFeatures[profileName, default: [:]][key] = enabled
        } else {
            features[key] = enabled
        }
    }

    private mutating func mergeAppsMcpPathOverrideConfig(
        key: String,
        value: ConfigValue,
        path: String,
        profileName: String?
    ) throws {
        switch key {
        case "enabled":
            let enabled = try Self.boolValue(value, key: path)
            if let profileName {
                profileFeatures[profileName, default: [:]][FeatureKey.appsMcpPathOverride.rawValue] = enabled
            } else {
                features[FeatureKey.appsMcpPathOverride.rawValue] = enabled
            }
        case "path":
            if let profileName {
                profileAppsMcpPathOverride[profileName, default: [:]][key] = value
                if profileFeatures[profileName, default: [:]][FeatureKey.appsMcpPathOverride.rawValue] == nil {
                    profileFeatures[profileName, default: [:]][FeatureKey.appsMcpPathOverride.rawValue] = true
                }
            } else {
                appsMcpPathOverride[key] = value
                if features[FeatureKey.appsMcpPathOverride.rawValue] == nil {
                    features[FeatureKey.appsMcpPathOverride.rawValue] = true
                }
            }
        default:
            throw CodexConfigLoadError.invalidConfigLine(path)
        }
    }

    private mutating func mergeAppsMcpPathOverrideFeatureConfig(
        _ table: [String: ConfigValue],
        path: String,
        profileName: String?
    ) throws {
        for (key, value) in table {
            try mergeAppsMcpPathOverrideConfig(
                key: key,
                value: value,
                path: "\(path).\(key)",
                profileName: profileName
            )
        }
        if table["enabled"] == nil, table["path"] != nil {
            if let profileName {
                profileFeatures[profileName, default: [:]][FeatureKey.appsMcpPathOverride.rawValue] = true
            } else {
                features[FeatureKey.appsMcpPathOverride.rawValue] = true
            }
        }
    }

    private mutating func appendToolSuggestDisabledToolTable() {
        var array: [ConfigValue]
        if case let .array(existing) = toolSuggest["disabled_tools"] {
            array = existing
        } else {
            array = []
        }
        array.append(.table([:]))
        toolSuggest["disabled_tools"] = .array(array)
    }

    private mutating func mergeIntoLastToolSuggestDisabledToolTable(key: String, value: ConfigValue) {
        var array: [ConfigValue]
        if case let .array(existing) = toolSuggest["disabled_tools"] {
            array = existing
        } else {
            array = [.table([:])]
        }
        guard let lastIndex = array.indices.last else { return }
        var table: [String: ConfigValue]
        if case let .table(existing) = array[lastIndex] {
            table = existing
        } else {
            table = [:]
        }
        table[key] = value
        array[lastIndex] = .table(table)
        toolSuggest["disabled_tools"] = .array(array)
    }

    private mutating func recordToolSuggestDisabledToolLayer() throws {
        try recordToolSuggestDisabledToolLayer(from: toolSuggest)
    }

    private mutating func recordToolSuggestDisabledToolLayer(from table: [String: ConfigValue]) throws {
        guard let disabledToolsValue = table["disabled_tools"] else { return }
        let disabledTools = try Self.toolSuggestDisabledToolsValue(
            disabledToolsValue,
            key: "tool_suggest.disabled_tools"
        )
        guard !disabledTools.isEmpty else { return }
        toolSuggestDisabledToolLayers.append(disabledTools)
    }

    private static func toolSuggestConfigValue(
        table: [String: ConfigValue],
        disabledToolLayers: [[ToolSuggestDisabledTool]]
    ) throws -> ToolSuggestConfig {
        for field in table.keys where !["discoverables", "disabled_tools"].contains(field) {
            throw CodexConfigLoadError.invalidConfigLine("tool_suggest.\(field)")
        }

        let discoverables = try table["discoverables"].map {
            try toolSuggestDiscoverablesValue($0, key: "tool_suggest.discoverables")
        } ?? []

        var disabledTools: [ToolSuggestDisabledTool] = []
        var seen = Set<ToolSuggestDisabledTool>()
        for layer in disabledToolLayers {
            for disabledTool in layer {
                guard let normalized = disabledTool.normalized(),
                      seen.insert(normalized).inserted
                else {
                    continue
                }
                disabledTools.append(normalized)
            }
        }

        return ToolSuggestConfig(
            discoverables: discoverables,
            disabledTools: disabledTools
        )
    }

    private static func toolSuggestDiscoverablesValue(
        _ value: ConfigValue,
        key: String
    ) throws -> [ToolSuggestDiscoverable] {
        try toolSuggestItemsValue(value, key: key).compactMap { item in
            ToolSuggestDiscoverable(type: item.type, id: item.id).normalized()
        }
    }

    private static func toolSuggestDisabledToolsValue(
        _ value: ConfigValue,
        key: String
    ) throws -> [ToolSuggestDisabledTool] {
        try toolSuggestItemsValue(value, key: key).map { item in
            ToolSuggestDisabledTool(type: item.type, id: item.id)
        }
    }

    private static func toolSuggestItemsValue(
        _ value: ConfigValue,
        key: String
    ) throws -> [(type: DiscoverableToolType, id: String)] {
        guard case let .array(values) = value else {
            throw CodexConfigLoadError.invalidStringValue(key)
        }

        return try values.enumerated().map { index, value in
            let itemKey = "\(key)[\(index)]"
            guard case let .table(table) = value else {
                throw CodexConfigLoadError.invalidStringValue(itemKey)
            }
            for field in table.keys where !["type", "id"].contains(field) {
                throw CodexConfigLoadError.invalidConfigLine("\(itemKey).\(field)")
            }
            let type = try stringEnumValue(
                DiscoverableToolType.self,
                table["type"] ?? .none,
                key: "\(itemKey).type"
            )
            let id = try stringValue(table["id"] ?? .none, key: "\(itemKey).id")
            return (type: type, id: id)
        }
    }

    private static func combinedModelProviders(
        from configuredProviders: [String: ConfigValue],
        openAIBaseURL: String?,
        environment: [String: String]
    ) throws -> [String: ModelProviderInfo] {
        var providers = ModelProviderInfo.builtInModelProviders(
            openAIBaseURL: openAIBaseURL,
            environment: environment
        )
        let reservedConflicts = configuredProviders.keys
            .filter { $0 != ModelProviderInfo.amazonBedrockProviderID && providers[$0] != nil }
            .sorted()
        if !reservedConflicts.isEmpty {
            throw CodexConfigLoadError.reservedModelProviderOverride(reservedConflicts)
        }
        for (name, value) in configuredProviders {
            let provider = try modelProviderInfoValue(value, key: "model_providers.\(name)")
            if name == ModelProviderInfo.amazonBedrockProviderID {
                try mergeAmazonBedrockAWSOverride(provider, into: &providers)
                continue
            }
            if provider.aws != nil {
                throw CodexConfigLoadError.unsupportedProviderAWS(name)
            }
            if provider.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw CodexConfigLoadError.invalidModelProvider("model_providers.\(name): provider name must not be empty")
            }
            do {
                try provider.validate()
            } catch {
                throw CodexConfigLoadError.invalidModelProvider(
                    "model_providers.\(name): \(String(describing: error))"
                )
            }
            providers[name] = provider
        }
        return providers
    }

    private static func mergeAmazonBedrockAWSOverride(
        _ provider: ModelProviderInfo,
        into providers: inout [String: ModelProviderInfo]
    ) throws {
        guard provider.isAmazonBedrockAWSOnlyOverride() else {
            throw CodexConfigLoadError.unsupportedAmazonBedrockOverride
        }
        guard var builtIn = providers[ModelProviderInfo.amazonBedrockProviderID] else {
            return
        }

        if let profile = provider.aws?.profile {
            builtIn.aws?.profile = profile
        }
        if let region = provider.aws?.region {
            builtIn.aws?.region = region
        }
        providers[ModelProviderInfo.amazonBedrockProviderID] = builtIn
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
        if let reviewModel = values["review_model"] {
            config.reviewModel = try stringValue(reviewModel, key: "\(keyPrefix)review_model")
        }
        if let contextWindow = values["model_context_window"] {
            config.modelContextWindow = try int64Value(
                contextWindow,
                key: "\(keyPrefix)model_context_window"
            )
        }
        if let autoCompactTokenLimit = values["model_auto_compact_token_limit"] {
            config.modelAutoCompactTokenLimit = try int64Value(
                autoCompactTokenLimit,
                key: "\(keyPrefix)model_auto_compact_token_limit"
            )
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
        if let approvalsReviewer = values["approvals_reviewer"] {
            config.approvalsReviewer = try approvalsReviewerValue(
                approvalsReviewer,
                key: "\(keyPrefix)approvals_reviewer"
            )
        }
        if let sandboxMode = values["sandbox_mode"] {
            config.sandboxMode = try stringEnumValue(
                SandboxMode.self,
                sandboxMode,
                key: "\(keyPrefix)sandbox_mode"
            )
        }
        if let defaultPermissions = values["default_permissions"] {
            config.defaultPermissions = try stringValue(
                defaultPermissions,
                key: "\(keyPrefix)default_permissions"
            )
        }
        if let allowLoginShell = values["allow_login_shell"] {
            config.allowLoginShell = try boolValue(
                allowLoginShell,
                key: "\(keyPrefix)allow_login_shell"
            )
        }
        if let notify = values["notify"] {
            config.notify = try stringArrayValue(notify, key: "\(keyPrefix)notify")
        }
        if let commitAttribution = values["commit_attribution"] {
            config.commitAttribution = try stringValue(
                commitAttribution,
                key: "\(keyPrefix)commit_attribution"
            )
        }
        if let hideAgentReasoning = values["hide_agent_reasoning"] {
            config.hideAgentReasoning = try boolValue(
                hideAgentReasoning,
                key: "\(keyPrefix)hide_agent_reasoning"
            )
        }
        if let showRawAgentReasoning = values["show_raw_agent_reasoning"] {
            config.showRawAgentReasoning = try boolValue(
                showRawAgentReasoning,
                key: "\(keyPrefix)show_raw_agent_reasoning"
            )
        }
        if let effort = values["model_reasoning_effort"] {
            config.modelReasoningEffort = try stringEnumValue(
                ReasoningEffort.self,
                effort,
                key: "\(keyPrefix)model_reasoning_effort"
            )
        }
        if let planModeEffort = values["plan_mode_reasoning_effort"] {
            config.planModeReasoningEffort = try stringEnumValue(
                ReasoningEffort.self,
                planModeEffort,
                key: "\(keyPrefix)plan_mode_reasoning_effort"
            )
        }
        if let summary = values["model_reasoning_summary"] {
            config.modelReasoningSummary = try stringEnumValue(
                ReasoningSummary.self,
                summary,
                key: "\(keyPrefix)model_reasoning_summary"
            )
        }
        if let supportsReasoningSummaries = values["model_supports_reasoning_summaries"] {
            config.modelSupportsReasoningSummaries = try boolValue(
                supportsReasoningSummaries,
                key: "\(keyPrefix)model_supports_reasoning_summaries"
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
            if serviceTier == .none {
                config.serviceTier = nil
                config.notices.fastDefaultOptOut = true
            } else {
                config.serviceTier = try stringValue(serviceTier, key: "\(keyPrefix)service_tier")
            }
        }
        if let baseURL = values["chatgpt_base_url"] {
            config.chatgptBaseURL = try stringValue(baseURL, key: "\(keyPrefix)chatgpt_base_url")
        }
        if let baseURL = values["openai_base_url"] {
            let value = try stringValue(baseURL, key: "\(keyPrefix)openai_base_url")
            config.openAIBaseURL = value.isEmpty ? nil : value
        }
        if let sqliteHome = values["sqlite_home"] {
            config.sqliteHome = try stringValue(sqliteHome, key: "\(keyPrefix)sqlite_home")
        }
        if let logDir = values["log_dir"] {
            config.logDir = try stringValue(logDir, key: "\(keyPrefix)log_dir")
        }
        if let zshPath = values["zsh_path"] {
            config.zshPath = try stringValue(zshPath, key: "\(keyPrefix)zsh_path")
        }
        if let modelCatalogJSON = values["model_catalog_json"] {
            config.modelCatalogJSON = try stringValue(
                modelCatalogJSON,
                key: "\(keyPrefix)model_catalog_json"
            )
        }
        if let personality = values["personality"] {
            config.personality = try stringEnumValue(
                Personality.self,
                personality,
                key: "\(keyPrefix)personality"
            )
        }
        if let instructionsFile = values["experimental_instructions_file"] {
            config.experimentalInstructionsFile = try stringValue(
                instructionsFile,
                key: "\(keyPrefix)experimental_instructions_file"
            )
        }
        if let instructionsFile = values["model_instructions_file"] {
            config.experimentalInstructionsFile = try stringValue(
                instructionsFile,
                key: "\(keyPrefix)model_instructions_file"
            )
        }
        if let compactPromptFile = values["experimental_compact_prompt_file"] {
            config.experimentalCompactPromptFile = try stringValue(
                compactPromptFile,
                key: "\(keyPrefix)experimental_compact_prompt_file"
            )
        }
        if let includePermissionsInstructions = values["include_permissions_instructions"] {
            config.includePermissionsInstructions = try boolValue(
                includePermissionsInstructions,
                key: "\(keyPrefix)include_permissions_instructions"
            )
        }
        if let includeAppsInstructions = values["include_apps_instructions"] {
            config.includeAppsInstructions = try boolValue(
                includeAppsInstructions,
                key: "\(keyPrefix)include_apps_instructions"
            )
        }
        if let includeEnvironmentContext = values["include_environment_context"] {
            config.includeEnvironmentContext = try boolValue(
                includeEnvironmentContext,
                key: "\(keyPrefix)include_environment_context"
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
        if let checkForUpdate = values["check_for_update_on_startup"] {
            config.checkForUpdateOnStartup = try boolValue(
                checkForUpdate,
                key: "\(keyPrefix)check_for_update_on_startup"
            )
        }
        if let disablePasteBurst = values["disable_paste_burst"] {
            config.disablePasteBurst = try boolValue(
                disablePasteBurst,
                key: "\(keyPrefix)disable_paste_burst"
            )
        }
        if let fileOpener = values["file_opener"] {
            config.fileOpener = try stringEnumValue(
                UriBasedFileOpener.self,
                fileOpener,
                key: "\(keyPrefix)file_opener"
            )
        }
        if let shellEnvironmentPolicy = values["shell_environment_policy"] {
            guard case let .table(table) = shellEnvironmentPolicy else {
                throw CodexConfigLoadError.invalidConfigLine("\(keyPrefix)shell_environment_policy")
            }
            config.shellEnvironmentPolicy = try shellEnvironmentPolicyValue(
                table,
                key: "\(keyPrefix)shell_environment_policy"
            )
        }
    }

    private static func isRelevantTopLevelKey(_ key: String) -> Bool {
        key == "model"
            || key == "review_model"
            || key == "model_context_window"
            || key == "model_auto_compact_token_limit"
            || key == "model_provider"
            || key == "approval_policy"
            || key == "approvals_reviewer"
            || key == "sandbox_mode"
            || key == "default_permissions"
            || key == "allow_login_shell"
            || key == "notify"
            || key == "commit_attribution"
            || key == "hide_agent_reasoning"
            || key == "show_raw_agent_reasoning"
            || key == "model_reasoning_effort"
            || key == "plan_mode_reasoning_effort"
            || key == "model_reasoning_summary"
            || key == "model_supports_reasoning_summaries"
            || key == "model_verbosity"
            || key == "model_catalog_json"
            || key == "personality"
            || key == "service_tier"
            || key == "chatgpt_base_url"
            || key == "openai_base_url"
            || key == "sqlite_home"
            || key == "log_dir"
            || key == "zsh_path"
            || key == "cli_auth_credentials_store"
            || key == "forced_login_method"
            || key == "forced_chatgpt_workspace_id"
            || key == "model_instructions_file"
            || key == "developer_instructions"
            || key == "compact_prompt"
            || key == "experimental_instructions_file"
            || key == "experimental_compact_prompt_file"
            || key == "include_permissions_instructions"
            || key == "include_apps_instructions"
            || key == "include_environment_context"
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
            || key == "background_terminal_max_timeout"
            || key == "tool_output_token_limit"
            || key == "shell_environment_policy"
            || key == "oss_provider"
            || key == "check_for_update_on_startup"
            || key == "disable_paste_burst"
            || key == "file_opener"
    }

    private static func isRelevantProfileKey(_ key: String) -> Bool {
        key == "model"
            || key == "model_provider"
            || key == "approval_policy"
            || key == "approvals_reviewer"
            || key == "sandbox_mode"
            || key == "default_permissions"
            || key == "model_reasoning_effort"
            || key == "plan_mode_reasoning_effort"
            || key == "model_reasoning_summary"
            || key == "model_verbosity"
            || key == "model_catalog_json"
            || key == "personality"
            || key == "service_tier"
            || key == "chatgpt_base_url"
            || key == "zsh_path"
            || key == "model_instructions_file"
            || key == "experimental_instructions_file"
            || key == "experimental_compact_prompt_file"
            || key == "include_permissions_instructions"
            || key == "include_apps_instructions"
            || key == "include_environment_context"
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
            || key == "auth"
            || key == "aws"
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

    private static func appsMcpPathOverrideValue(
        base: [String: ConfigValue],
        profile: [String: ConfigValue]?,
        features: FeatureStates
    ) throws -> String? {
        guard features.isEnabled(.appsMcpPathOverride) else {
            return nil
        }
        let value = profile?["path"] ?? base["path"]
        return try value.map { try stringValue($0, key: "features.apps_mcp_path_override.path") }
    }

    private static func windowsSandboxLevelValue(
        base: [String: ConfigValue],
        profile: [String: ConfigValue]?,
        profileFeatures: [String: Bool],
        resolvedFeatures: FeatureStates
    ) throws -> WindowsSandboxLevel {
        if let profileMode = legacyWindowsSandboxMode(from: profileFeatures) {
            return profileMode
        }
        if legacyWindowsSandboxKeysPresent(in: profileFeatures) {
            return windowsSandboxLevel(from: resolvedFeatures)
        }
        if let profileSandbox = profile?["sandbox"] {
            return try windowsSandboxLevel(profileSandbox, key: "profiles.<active>.windows.sandbox")
        }
        if let baseSandbox = base["sandbox"] {
            return try windowsSandboxLevel(baseSandbox, key: "windows.sandbox")
        }
        return windowsSandboxLevel(from: resolvedFeatures)
    }

    private static func windowsSandboxPrivateDesktopValue(
        base: [String: ConfigValue],
        profile: [String: ConfigValue]?
    ) throws -> Bool {
        if let profileValue = profile?["sandbox_private_desktop"] {
            return try boolValue(profileValue, key: "profiles.<active>.windows.sandbox_private_desktop")
        }
        if let baseValue = base["sandbox_private_desktop"] {
            return try boolValue(baseValue, key: "windows.sandbox_private_desktop")
        }
        return true
    }

    private static func windowsSandboxLevel(_ value: ConfigValue, key: String) throws -> WindowsSandboxLevel {
        let raw = try stringValue(value, key: key)
        switch raw {
        case "elevated":
            return .elevated
        case "unelevated":
            return .restrictedToken
        default:
            throw CodexConfigLoadError.invalidConfigLine(key)
        }
    }

    private static func legacyWindowsSandboxMode(from features: [String: Bool]) -> WindowsSandboxLevel? {
        if features[FeatureKey.windowsSandboxElevated.rawValue] == true {
            return .elevated
        }
        if features[FeatureKey.windowsSandbox.rawValue] == true
            || features["enable_experimental_windows_sandbox"] == true
        {
            return .restrictedToken
        }
        return nil
    }

    private static func legacyWindowsSandboxKeysPresent(in features: [String: Bool]) -> Bool {
        features.keys.contains(FeatureKey.windowsSandboxElevated.rawValue)
            || features.keys.contains(FeatureKey.windowsSandbox.rawValue)
            || features.keys.contains("enable_experimental_windows_sandbox")
    }

    private static func windowsSandboxLevel(from features: FeatureStates) -> WindowsSandboxLevel {
        if features.isEnabled(.windowsSandboxElevated) {
            return .elevated
        }
        if features.isEnabled(.windowsSandbox) {
            return .restrictedToken
        }
        return .disabled
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

    private static func approvalsReviewerValue(_ value: ConfigValue, key: String) throws -> ApprovalsReviewer {
        let rawValue = try stringValue(value, key: key)
        switch rawValue {
        case "user":
            return .user
        case "guardian_subagent", "auto_review":
            return .autoReview
        default:
            throw CodexConfigLoadError.invalidStringValue(key)
        }
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

    private static func canonicalMemoriesConfigKey(_ key: String) -> String {
        key == "no_memories_if_mcp_or_web_search" ? "disable_on_external_context" : key
    }

    private static func memoriesConfigValue(
        _ table: [String: ConfigValue],
        key: String
    ) throws -> MemoriesConfig {
        let knownFields = Set([
            "disable_on_external_context",
            "generate_memories",
            "use_memories",
            "max_raw_memories_for_consolidation",
            "max_unused_days",
            "max_rollout_age_days",
            "max_rollouts_per_startup",
            "min_rollout_idle_hours",
            "min_rate_limit_remaining_percent",
            "extract_model",
            "consolidation_model"
        ])
        for field in table.keys where !knownFields.contains(field) {
            throw CodexConfigLoadError.invalidConfigLine("\(key).\(field)")
        }

        let defaults = MemoriesConfig()
        return MemoriesConfig(
            disableOnExternalContext: try table["disable_on_external_context"].map {
                try boolValue($0, key: "\(key).disable_on_external_context")
            } ?? defaults.disableOnExternalContext,
            generateMemories: try table["generate_memories"].map {
                try boolValue($0, key: "\(key).generate_memories")
            } ?? defaults.generateMemories,
            useMemories: try table["use_memories"].map {
                try boolValue($0, key: "\(key).use_memories")
            } ?? defaults.useMemories,
            maxRawMemoriesForConsolidation: try table["max_raw_memories_for_consolidation"].map {
                try nonNegativeIntValue($0, key: "\(key).max_raw_memories_for_consolidation")
                    .clamped(to: 1...4096)
            } ?? defaults.maxRawMemoriesForConsolidation,
            maxUnusedDays: try table["max_unused_days"].map {
                try int64Value($0, key: "\(key).max_unused_days").clamped(to: 0...365)
            } ?? defaults.maxUnusedDays,
            maxRolloutAgeDays: try table["max_rollout_age_days"].map {
                try int64Value($0, key: "\(key).max_rollout_age_days").clamped(to: 0...90)
            } ?? defaults.maxRolloutAgeDays,
            maxRolloutsPerStartup: try table["max_rollouts_per_startup"].map {
                try nonNegativeIntValue($0, key: "\(key).max_rollouts_per_startup")
                    .clamped(to: 1...128)
            } ?? defaults.maxRolloutsPerStartup,
            minRolloutIdleHours: try table["min_rollout_idle_hours"].map {
                try int64Value($0, key: "\(key).min_rollout_idle_hours").clamped(to: 1...48)
            } ?? defaults.minRolloutIdleHours,
            minRateLimitRemainingPercent: try table["min_rate_limit_remaining_percent"].map {
                try int64Value($0, key: "\(key).min_rate_limit_remaining_percent").clamped(to: 0...100)
            } ?? defaults.minRateLimitRemainingPercent,
            extractModel: try table["extract_model"].map {
                try stringValue($0, key: "\(key).extract_model")
            },
            consolidationModel: try table["consolidation_model"].map {
                try stringValue($0, key: "\(key).consolidation_model")
            }
        )
    }

    private static func noticeConfigValue(
        _ table: [String: ConfigValue],
        key: String
    ) throws -> NoticeConfig {
        let knownFields = Set([
            "hide_full_access_warning",
            "hide_world_writable_warning",
            "fast_default_opt_out",
            "hide_rate_limit_model_nudge",
            "hide_gpt5_1_migration_prompt",
            "hide_gpt-5.1-codex-max_migration_prompt",
            "model_migrations",
            "external_config_migration_prompts"
        ])
        for field in table.keys where !knownFields.contains(field) {
            throw CodexConfigLoadError.invalidConfigLine("\(key).\(field)")
        }

        return NoticeConfig(
            hideFullAccessWarning: try table["hide_full_access_warning"].map {
                try boolValue($0, key: "\(key).hide_full_access_warning")
            },
            hideWorldWritableWarning: try table["hide_world_writable_warning"].map {
                try boolValue($0, key: "\(key).hide_world_writable_warning")
            },
            fastDefaultOptOut: try table["fast_default_opt_out"].map {
                try boolValue($0, key: "\(key).fast_default_opt_out")
            },
            hideRateLimitModelNudge: try table["hide_rate_limit_model_nudge"].map {
                try boolValue($0, key: "\(key).hide_rate_limit_model_nudge")
            },
            hideGPT51MigrationPrompt: try table["hide_gpt5_1_migration_prompt"].map {
                try boolValue($0, key: "\(key).hide_gpt5_1_migration_prompt")
            },
            hideGPT51CodexMaxMigrationPrompt: try table["hide_gpt-5.1-codex-max_migration_prompt"].map {
                try boolValue($0, key: "\(key).hide_gpt-5.1-codex-max_migration_prompt")
            },
            modelMigrations: try table["model_migrations"].map {
                try stringMapValue($0, key: "\(key).model_migrations")
            } ?? [:],
            externalConfigMigrationPrompts: try table["external_config_migration_prompts"].map {
                try externalConfigMigrationPromptsValue($0, key: "\(key).external_config_migration_prompts")
            } ?? ExternalConfigMigrationPromptsConfig()
        )
    }

    private static func externalConfigMigrationPromptsValue(
        _ value: ConfigValue,
        key: String
    ) throws -> ExternalConfigMigrationPromptsConfig {
        guard case let .table(table) = value else {
            throw CodexConfigLoadError.invalidConfigLine(key)
        }
        let knownFields = Set(["home", "home_last_prompted_at", "projects", "project_last_prompted_at"])
        for field in table.keys where !knownFields.contains(field) {
            throw CodexConfigLoadError.invalidConfigLine("\(key).\(field)")
        }
        return ExternalConfigMigrationPromptsConfig(
            home: try table["home"].map { try boolValue($0, key: "\(key).home") },
            homeLastPromptedAt: try table["home_last_prompted_at"].map {
                try int64Value($0, key: "\(key).home_last_prompted_at")
            },
            projects: try table["projects"].map {
                try boolMapValue($0, key: "\(key).projects")
            } ?? [:],
            projectLastPromptedAt: try table["project_last_prompted_at"].map {
                try int64MapValue($0, key: "\(key).project_last_prompted_at")
            } ?? [:]
        )
    }

    private static func historyConfigValue(
        _ table: [String: ConfigValue],
        key: String
    ) throws -> HistoryConfig {
        guard !table.isEmpty else {
            return HistoryConfig()
        }
        for field in table.keys where !["persistence", "max_bytes"].contains(field) {
            throw CodexConfigLoadError.invalidConfigLine("\(key).\(field)")
        }
        return HistoryConfig(
            persistence: try table["persistence"].map {
                try stringEnumValue(HistoryPersistence.self, $0, key: "\(key).persistence")
            } ?? .saveAll,
            maxBytes: try table["max_bytes"].map {
                try nonNegativeIntValue($0, key: "\(key).max_bytes")
            }
        )
    }

    private static func enabledConfigValue(_ table: [String: ConfigValue], key: String) throws -> Bool? {
        guard !table.isEmpty else {
            return nil
        }
        for field in table.keys where field != "enabled" {
            throw CodexConfigLoadError.invalidConfigLine("\(key).\(field)")
        }
        return try table["enabled"].map { try boolValue($0, key: "\(key).enabled") }
    }

    private static func agentRuntimeConfigValue(
        _ table: [String: ConfigValue],
        key: String
    ) throws -> AgentRuntimeConfig {
        guard !table.isEmpty else {
            return AgentRuntimeConfig()
        }
        for field in table.keys where !isRelevantAgentKey(field) {
            throw CodexConfigLoadError.invalidConfigLine("\(key).\(field)")
        }

        let maxThreads = try table["max_threads"].map {
            try positiveIntValue(
                $0,
                key: "\(key).max_threads",
                message: "agents.max_threads must be at least 1"
            )
        } ?? AgentRuntimeConfig.defaultMaxThreads
        let maxDepth = try table["max_depth"].map {
            let value = try positiveIntValue(
                $0,
                key: "\(key).max_depth",
                message: "agents.max_depth must be at least 1"
            )
            guard value <= Int(Int32.max) else {
                throw CodexConfigLoadError.invalidConfig("agents.max_depth must fit within a 32-bit signed integer")
            }
            return Int32(value)
        } ?? AgentRuntimeConfig.defaultMaxDepth
        let jobMaxRuntimeSeconds = try table["job_max_runtime_seconds"].map {
            try positiveUInt64Value(
                $0,
                key: "\(key).job_max_runtime_seconds",
                message: "agents.job_max_runtime_seconds must be at least 1"
            )
        } ?? AgentRuntimeConfig.defaultJobMaxRuntimeSeconds

        if let jobMaxRuntimeSeconds, jobMaxRuntimeSeconds > UInt64(Int64.max) {
            throw CodexConfigLoadError.invalidConfig(
                "agents.job_max_runtime_seconds must fit within a 64-bit signed integer"
            )
        }

        return AgentRuntimeConfig(
            maxThreads: maxThreads,
            maxDepth: maxDepth,
            jobMaxRuntimeSeconds: jobMaxRuntimeSeconds,
            interruptMessageEnabled: try table["interrupt_message"].map {
                try boolValue($0, key: "\(key).interrupt_message")
            } ?? true
        )
    }

    private static func isRelevantAgentKey(_ key: String) -> Bool {
        key == "max_threads"
            || key == "max_depth"
            || key == "job_max_runtime_seconds"
            || key == "interrupt_message"
    }

    private static func isRelevantAgentRoleKey(_ key: String) -> Bool {
        key == "description"
            || key == "config_file"
            || key == "nickname_candidates"
    }

    private static func agentRoleConfigsValue(
        declaredRoles roles: [String: [String: ConfigValue]],
        discoveryDirs: [URL],
        startupWarnings: inout [String]
    ) throws -> [String: AgentRoleConfig] {
        var configs: [String: AgentRoleConfig] = [:]
        var declaredConfigFiles = Set<String>()
        for roleName in roles.keys.sorted() {
            guard let values = roles[roleName] else { continue }
            var config = AgentRoleConfig(
                description: try values["description"].flatMap {
                    try agentRoleDescriptionValue($0, key: "agents.\(roleName).description")
                },
                configFile: try values["config_file"].map {
                    try stringValue($0, key: "agents.\(roleName).config_file")
                },
                nicknameCandidates: try values["nickname_candidates"].map {
                    try agentRoleNicknameCandidatesValue($0, key: "agents.\(roleName).nickname_candidates")
                }
            )

            if let configFile = config.configFile {
                declaredConfigFiles.insert(URL(fileURLWithPath: configFile).standardizedFileURL.path)
                let fileMetadata = try agentRoleFileConfigValue(
                    path: configFile,
                    roleNameHint: roleName
                )
                if let name = fileMetadata.name {
                    if configs[name] != nil {
                        throw CodexConfigLoadError.invalidConfig(
                            "duplicate agent role name `\(name)` declared in config"
                        )
                    }
                    config.description = fileMetadata.config.description ?? config.description
                    config.nicknameCandidates = fileMetadata.config.nicknameCandidates ?? config.nicknameCandidates
                    guard config.description != nil else {
                        throw CodexConfigLoadError.invalidConfig(
                            "agent role `\(name)` must define a description"
                        )
                    }
                    configs[name] = config
                    continue
                }
                config.description = fileMetadata.config.description ?? config.description
                config.nicknameCandidates = fileMetadata.config.nicknameCandidates ?? config.nicknameCandidates
            }

            guard config.description != nil else {
                throw CodexConfigLoadError.invalidConfig(
                    "agent role `\(roleName)` must define a description"
                )
            }
            if configs[roleName] != nil {
                throw CodexConfigLoadError.invalidConfig(
                    "duplicate agent role name `\(roleName)` declared in config"
                )
            }
            configs[roleName] = config
        }

        for roleFile in discoveredAgentRoleFiles(in: discoveryDirs) where !declaredConfigFiles.contains(roleFile.url.path) {
            let fileMetadata: (name: String?, config: AgentRoleConfig)
            do {
                fileMetadata = try agentRoleFileConfigValue(path: roleFile.url.path, roleNameHint: nil)
            } catch {
                appendAgentRoleWarning(error, to: &startupWarnings)
                continue
            }
            guard let roleName = fileMetadata.name else { continue }
            guard configs[roleName] == nil else {
                appendAgentRoleWarning(
                    CodexConfigLoadError.invalidConfig(
                        "duplicate agent role name `\(roleName)` discovered in \(roleFile.agentsDir.path)"
                    ),
                    to: &startupWarnings
                )
                continue
            }
            guard fileMetadata.config.description != nil else {
                appendAgentRoleWarning(
                    CodexConfigLoadError.invalidConfig(
                        "agent role `\(roleName)` must define a description"
                    ),
                    to: &startupWarnings
                )
                continue
            }
            configs[roleName] = AgentRoleConfig(
                description: fileMetadata.config.description,
                configFile: roleFile.url.path,
                nicknameCandidates: fileMetadata.config.nicknameCandidates
            )
        }
        return configs
    }

    private static func appendAgentRoleWarning(_ error: Error, to startupWarnings: inout [String]) {
        startupWarnings.append("Ignoring malformed agent role definition: \(error)")
    }

    private struct DiscoveredAgentRoleFile {
        var url: URL
        var agentsDir: URL
    }

    private static func discoveredAgentRoleFiles(in directories: [URL]) -> [DiscoveredAgentRoleFile] {
        var seenDirectories = Set<String>()
        var files: [DiscoveredAgentRoleFile] = []
        for directory in directories {
            let standardizedDirectory = directory.standardizedFileURL
            guard seenDirectories.insert(standardizedDirectory.path).inserted else {
                continue
            }
            collectAgentRoleFiles(in: standardizedDirectory, agentsDir: standardizedDirectory, into: &files)
        }
        return files.sorted { $0.url.path < $1.url.path }
    }

    private static func collectAgentRoleFiles(
        in directory: URL,
        agentsDir: URL,
        into files: inout [DiscoveredAgentRoleFile]
    ) {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else {
            return
        }
        for case let file as URL in enumerator where file.pathExtension == "toml" {
            let resourceValues = try? file.resourceValues(forKeys: [.isRegularFileKey])
            if resourceValues?.isRegularFile == true {
                files.append(DiscoveredAgentRoleFile(
                    url: file.standardizedFileURL,
                    agentsDir: agentsDir
                ))
            }
        }
    }

    private static func agentRoleFileConfigValue(
        path: String,
        roleNameHint: String?
    ) throws -> (name: String?, config: AgentRoleConfig) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw CodexConfigLoadError.invalidConfig(
                "agents.\(roleNameHint ?? "<unknown>").config_file must point to an existing file at \(path)"
            )
        }
        if isDirectory.boolValue {
            throw CodexConfigLoadError.invalidConfig(
                "agents.\(roleNameHint ?? "<unknown>").config_file must point to a file: \(path)"
            )
        }

        let contents: String
        do {
            contents = try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            throw CodexConfigLoadError.invalidConfig(
                "failed to read agent role file at \(path): \(error)"
            )
        }

        let values: [String: ConfigValue]
        do {
            values = try agentRoleFileMetadataValues(contents)
        } catch {
            throw CodexConfigLoadError.invalidConfig(
                "failed to parse agent role file at \(path): \(error)"
            )
        }

        let name = try values["name"].flatMap {
            try agentRoleOptionalTrimmedNameValue($0, fieldLabel: "name")
        }
        if roleNameHint == nil, name == nil {
            throw CodexConfigLoadError.invalidConfig(
                "agent role file at \(path) must define a non-empty `name`"
            )
        }
        let description = try values["description"].flatMap {
            try agentRoleDescriptionValue($0, key: "agent role file \(path).description")
        }
        let nicknameCandidates = try values["nickname_candidates"].map {
            try agentRoleNicknameCandidatesValue($0, key: "agent role file \(path).nickname_candidates")
        }
        if let developerInstructions = values["developer_instructions"] {
            _ = try agentRoleDescriptionValue(
                developerInstructions,
                key: "agent role file \(path).developer_instructions"
            )
        } else if roleNameHint == nil {
            throw CodexConfigLoadError.invalidConfig(
                "agent role file at \(path) must define `developer_instructions`"
            )
        }
        return (name, AgentRoleConfig(
            description: description,
            configFile: path,
            nicknameCandidates: nicknameCandidates
        ))
    }

    private static func agentRoleFileMetadataValues(_ contents: String) throws -> [String: ConfigValue] {
        var values: [String: ConfigValue] = [:]
        var inTopLevel = true
        for line in try logicalTomlLines(contents) {
            if line.hasPrefix("[") {
                inTopLevel = false
                continue
            }
            guard inTopLevel else { continue }
            guard let equalsIndex = firstEqualsIndex(in: line) else {
                throw CodexConfigLoadError.invalidConfigLine(line)
            }
            let key = String(line[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let valueStart = line.index(after: equalsIndex)
            let valueText = String(line[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if ["name", "description", "nickname_candidates", "developer_instructions"].contains(key) {
                values[key] = try ConfigValueParser.parseTomlLiteral(valueText)
            }
        }
        return values
    }

    private static func agentRoleDescriptionValue(_ value: ConfigValue, key: String) throws -> String? {
        try agentRoleOptionalTrimmedStringValue(value, fieldLabel: key)
    }

    private static func agentRoleOptionalTrimmedNameValue(
        _ value: ConfigValue,
        fieldLabel: String
    ) throws -> String? {
        let trimmed = try stringValue(value, key: fieldLabel).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func agentRoleOptionalTrimmedStringValue(
        _ value: ConfigValue,
        fieldLabel: String
    ) throws -> String? {
        let trimmed = try stringValue(value, key: fieldLabel).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CodexConfigLoadError.invalidConfig("\(fieldLabel) cannot be blank")
        }
        return trimmed
    }

    private static func agentRoleNicknameCandidatesValue(
        _ value: ConfigValue,
        key: String
    ) throws -> [String] {
        let candidates = try stringArrayValue(value, key: key)
        guard !candidates.isEmpty else {
            throw CodexConfigLoadError.invalidConfig("\(key) must contain at least one name")
        }
        var seen = Set<String>()
        var normalized: [String] = []
        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw CodexConfigLoadError.invalidConfig("\(key) cannot contain blank names")
            }
            guard seen.insert(trimmed).inserted else {
                throw CodexConfigLoadError.invalidConfig("\(key) cannot contain duplicates")
            }
            guard trimmed.unicodeScalars.allSatisfy({ scalar in
                scalar.value < 128
                    && (CharacterSet.alphanumerics.contains(scalar)
                        || scalar == " "
                        || scalar == "-"
                        || scalar == "_")
            }) else {
                throw CodexConfigLoadError.invalidConfig(
                    "\(key) may only contain ASCII letters, digits, spaces, hyphens, and underscores"
                )
            }
            normalized.append(trimmed)
        }
        return normalized
    }

    private static func tuiRuntimeConfigValue(
        _ table: [String: ConfigValue],
        modelAvailabilityNux: [String: ConfigValue],
        profile: [String: ConfigValue]?,
        key: String
    ) throws -> TuiRuntimeConfig {
        let knownFields = Set([
            "animations",
            "show_tooltips",
            "vim_mode_default",
            "raw_output_mode",
            "alternate_screen",
            "status_line",
            "status_line_use_colors",
            "terminal_title",
            "theme",
            "session_picker_view",
            "terminal_resize_reflow_max_rows",
            "notifications",
            "notification_method",
            "notification_condition"
        ])
        for field in table.keys where !knownFields.contains(field) {
            throw CodexConfigLoadError.invalidConfigLine("\(key).\(field)")
        }
        if let profile {
            for field in profile.keys where field != "session_picker_view" {
                throw CodexConfigLoadError.invalidConfigLine("profiles.\(field)")
            }
        }

        let defaults = TuiRuntimeConfig()
        let sessionPickerValue = profile?["session_picker_view"] ?? table["session_picker_view"]
        return TuiRuntimeConfig(
            animations: try table["animations"].map {
                try boolValue($0, key: "\(key).animations")
            } ?? defaults.animations,
            showTooltips: try table["show_tooltips"].map {
                try boolValue($0, key: "\(key).show_tooltips")
            } ?? defaults.showTooltips,
            vimModeDefault: try table["vim_mode_default"].map {
                try boolValue($0, key: "\(key).vim_mode_default")
            } ?? defaults.vimModeDefault,
            rawOutputMode: try table["raw_output_mode"].map {
                try boolValue($0, key: "\(key).raw_output_mode")
            } ?? defaults.rawOutputMode,
            alternateScreen: try table["alternate_screen"].map {
                try stringEnumValue(TuiAlternateScreenMode.self, $0, key: "\(key).alternate_screen")
            } ?? defaults.alternateScreen,
            statusLine: try table["status_line"].map {
                try stringArrayValue($0, key: "\(key).status_line")
            },
            statusLineUseColors: try table["status_line_use_colors"].map {
                try boolValue($0, key: "\(key).status_line_use_colors")
            } ?? defaults.statusLineUseColors,
            terminalTitle: try table["terminal_title"].map {
                try stringArrayValue($0, key: "\(key).terminal_title")
            },
            theme: try table["theme"].map {
                try stringValue($0, key: "\(key).theme")
            },
            sessionPickerView: try sessionPickerValue.map {
                try stringEnumValue(TuiSessionPickerViewMode.self, $0, key: "\(key).session_picker_view")
            } ?? defaults.sessionPickerView,
            modelAvailabilityNuxShownCount: try modelAvailabilityNuxCountValue(
                modelAvailabilityNux,
                key: "\(key).model_availability_nux"
            ),
            notifications: try tuiNotificationSettingsValue(table, key: key)
        )
    }

    private static func tuiNotificationSettingsValue(
        _ table: [String: ConfigValue],
        key: String
    ) throws -> TuiNotificationSettings {
        let defaults = TuiNotificationSettings()
        return TuiNotificationSettings(
            notifications: try table["notifications"].map {
                try tuiNotificationsValue($0, key: "\(key).notifications")
            } ?? defaults.notifications,
            method: try table["notification_method"].map {
                try stringEnumValue(TuiNotificationMethod.self, $0, key: "\(key).notification_method")
            } ?? defaults.method,
            condition: try table["notification_condition"].map {
                try stringEnumValue(TuiNotificationCondition.self, $0, key: "\(key).notification_condition")
            } ?? defaults.condition
        )
    }

    private static func tuiNotificationsValue(_ value: ConfigValue, key: String) throws -> TuiNotifications {
        switch value {
        case let .bool(enabled):
            return .enabled(enabled)
        case .array:
            return .custom(try stringArrayValue(value, key: key))
        default:
            throw CodexConfigLoadError.invalidStringValue(key)
        }
    }

    private static func terminalResizeReflowConfigValue(
        _ table: [String: ConfigValue],
        key: String
    ) throws -> TerminalResizeReflowConfig {
        guard let maxRows = table["terminal_resize_reflow_max_rows"] else {
            return TerminalResizeReflowConfig()
        }
        let rows = try nonNegativeIntValue(maxRows, key: "\(key).terminal_resize_reflow_max_rows")
        return TerminalResizeReflowConfig(maxRows: rows == 0 ? .disabled : .limit(rows))
    }

    private static func modelAvailabilityNuxCountValue(
        _ table: [String: ConfigValue],
        key: String
    ) throws -> [String: Int] {
        try table.reduce(into: [:]) { result, pair in
            result[pair.key] = try nonNegativeIntValue(pair.value, key: "\(key).\(pair.key)")
        }
    }

    private static func shellEnvironmentPolicyValue(
        _ table: [String: ConfigValue],
        key: String
    ) throws -> ShellEnvironmentPolicy {
        guard !table.isEmpty else {
            return ShellEnvironmentPolicy()
        }
        for field in table.keys where ![
            "inherit",
            "ignore_default_excludes",
            "exclude",
            "set",
            "include_only",
            "experimental_use_profile"
        ].contains(field) {
            throw CodexConfigLoadError.invalidConfigLine("\(key).\(field)")
        }
        return ShellEnvironmentPolicy(toml: ShellEnvironmentPolicyToml(
            inherit: try table["inherit"].map {
                try stringEnumValue(ShellEnvironmentPolicyInherit.self, $0, key: "\(key).inherit")
            },
            ignoreDefaultExcludes: try table["ignore_default_excludes"].map {
                try boolValue($0, key: "\(key).ignore_default_excludes")
            },
            exclude: try table["exclude"].map {
                try stringArrayValue($0, key: "\(key).exclude")
            },
            set: try table["set"].map {
                try stringMapValue($0, key: "\(key).set")
            },
            includeOnly: try table["include_only"].map {
                try stringArrayValue($0, key: "\(key).include_only")
            },
            experimentalUseProfile: try table["experimental_use_profile"].map {
                try boolValue($0, key: "\(key).experimental_use_profile")
            }
        ))
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

    private static func stringMapValue(_ value: ConfigValue, key: String) throws -> [String: String] {
        guard case let .table(table) = value else {
            throw CodexConfigLoadError.invalidStringValue(key)
        }
        return try table.reduce(into: [:]) { result, pair in
            result[pair.key] = try stringValue(pair.value, key: "\(key).\(pair.key)")
        }
    }

    private static func boolMapValue(_ value: ConfigValue, key: String) throws -> [String: Bool] {
        guard case let .table(table) = value else {
            throw CodexConfigLoadError.invalidConfigLine(key)
        }
        return try table.reduce(into: [:]) { result, pair in
            result[pair.key] = try boolValue(pair.value, key: "\(key).\(pair.key)")
        }
    }

    private static func int64MapValue(_ value: ConfigValue, key: String) throws -> [String: Int64] {
        guard case let .table(table) = value else {
            throw CodexConfigLoadError.invalidConfigLine(key)
        }
        return try table.reduce(into: [:]) { result, pair in
            result[pair.key] = try int64Value(pair.value, key: "\(key).\(pair.key)")
        }
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

    private static func positiveIntValue(_ value: ConfigValue, key: String, message: String) throws -> Int {
        guard case let .integer(integer) = value else {
            throw CodexConfigLoadError.invalidStringValue(key)
        }
        guard integer >= 1 else {
            throw CodexConfigLoadError.invalidConfig(message)
        }
        guard integer <= Int64(Int.max) else {
            throw CodexConfigLoadError.invalidStringValue(key)
        }
        return Int(integer)
    }

    private static func positiveUInt64Value(_ value: ConfigValue, key: String, message: String) throws -> UInt64 {
        guard case let .integer(integer) = value else {
            throw CodexConfigLoadError.invalidStringValue(key)
        }
        guard integer >= 1 else {
            throw CodexConfigLoadError.invalidConfig(message)
        }
        return UInt64(integer)
    }

    private static func int64Value(_ value: ConfigValue, key: String) throws -> Int64 {
        guard case let .integer(integer) = value else {
            throw CodexConfigLoadError.invalidStringValue(key)
        }
        return integer
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
        let isArrayTable = line.hasPrefix("[[")
        let body = isArrayTable
            ? String(line.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            : String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = try parseDottedKey(body)
        if parts.count == 1, parts[0] == "features" {
            return .features
        }
        if parts.count == 2, parts[0] == "features", parts[1] == "apps_mcp_path_override" {
            return .featuresAppsMcpPathOverride
        }
        if parts.count == 1, parts[0] == "memories" {
            return .memories
        }
        if parts.count == 1, parts[0] == "sandbox_workspace_write" {
            return .sandboxWorkspaceWrite
        }
        if parts.count == 1, parts[0] == "history" {
            return .history
        }
        if parts.count == 1, parts[0] == "notice" {
            return .notice
        }
        if parts.count == 2, parts[0] == "notice", parts[1] == "model_migrations" {
            return .noticeModelMigrations
        }
        if parts.count == 2, parts[0] == "notice", parts[1] == "external_config_migration_prompts" {
            return .noticeExternalConfigMigrationPrompts
        }
        if parts.count == 3,
           parts[0] == "notice",
           parts[1] == "external_config_migration_prompts",
           parts[2] == "projects"
        {
            return .noticeExternalConfigMigrationPromptProjects
        }
        if parts.count == 3,
           parts[0] == "notice",
           parts[1] == "external_config_migration_prompts",
           parts[2] == "project_last_prompted_at"
        {
            return .noticeExternalConfigMigrationPromptProjectLastPromptedAt
        }
        if parts.count == 1, parts[0] == "windows" {
            return .windows
        }
        if parts.count == 1, parts[0] == "analytics" {
            return .analytics
        }
        if parts.count == 1, parts[0] == "feedback" {
            return .feedback
        }
        if parts.count == 1, parts[0] == "otel" {
            return .ignoredDenylistedTable("otel")
        }
        if parts.count == 1, parts[0] == "agents" {
            return .agents
        }
        if parts.count == 2, parts[0] == "agents" {
            return .agentRole(parts[1])
        }
        if parts.count == 3, parts[0] == "permissions", parts[2] == "filesystem" {
            return .permissionFilesystem(parts[1])
        }
        if parts.count == 4, parts[0] == "permissions", parts[2] == "filesystem" {
            return .permissionFilesystemScoped(parts[1], parts[3])
        }
        if parts.count == 3, parts[0] == "permissions", parts[2] == "network" {
            return .permissionNetwork(parts[1])
        }
        if parts.count == 4, parts[0] == "permissions", parts[2] == "network" {
            return .permissionNetworkMap(parts[1], parts[3])
        }
        if parts.count == 1, parts[0] == "audio" {
            return .audio
        }
        if parts.count == 1, parts[0] == "realtime" {
            return .realtime
        }
        if parts.count == 1, parts[0] == "tui" {
            return .tui
        }
        if parts.count == 2, parts[0] == "tui", parts[1] == "model_availability_nux" {
            return .tuiModelAvailabilityNux
        }
        if parts.count == 1, parts[0] == "shell_environment_policy" {
            return .shellEnvironmentPolicy
        }
        if parts.count == 2, parts[0] == "shell_environment_policy", parts[1] == "set" {
            return .shellEnvironmentPolicySet
        }
        if parts.count == 1, parts[0] == "skills" {
            return .skills
        }
        if parts.count == 1, parts[0] == "tool_suggest" {
            return .toolSuggest
        }
        if parts.count == 2, parts[0] == "tool_suggest", parts[1] == "disabled_tools" {
            return isArrayTable ? .toolSuggestDisabledToolsArray : .ignored
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
        if parts.count == 3, parts[0] == "profiles", parts[2] == "tui" {
            return .profileTui(parts[1])
        }
        if parts.count == 3, parts[0] == "profiles", parts[2] == "analytics" {
            return .profileAnalytics(parts[1])
        }
        if parts.count == 3, parts[0] == "profiles", parts[2] == "windows" {
            return .profileWindows(parts[1])
        }
        if parts.count == 3, parts[0] == "profiles", parts[2] == "features" {
            return .profileFeatures(parts[1])
        }
        if parts.count == 4,
           parts[0] == "profiles",
           parts[2] == "features",
           parts[3] == "apps_mcp_path_override"
        {
            return .profileFeaturesAppsMcpPathOverride(parts[1])
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

private extension PermissionProfile {
    var allowsManagedFilesystemRequirements: Bool {
        guard enforcement == .managed else {
            return false
        }
        switch fileSystemSandboxPolicy {
        case .restricted:
            return true
        case .unrestricted, .externalSandbox:
            return false
        }
    }
}

private enum ConfigSection {
    case topLevel
    case profile(String)
    case modelProvider(String)
    case modelProviderMap(String, String)
    case features
    case featuresAppsMcpPathOverride
    case memories
    case sandboxWorkspaceWrite
    case history
    case notice
    case noticeModelMigrations
    case noticeExternalConfigMigrationPrompts
    case noticeExternalConfigMigrationPromptProjects
    case noticeExternalConfigMigrationPromptProjectLastPromptedAt
    case windows
    case analytics
    case feedback
    case profileAnalytics(String)
    case profileWindows(String)
    case agents
    case agentRole(String)
    case permissionFilesystem(String)
    case permissionFilesystemScoped(String, String)
    case permissionNetwork(String)
    case permissionNetworkMap(String, String)
    case audio
    case realtime
    case tui
    case tuiModelAvailabilityNux
    case profileTui(String)
    case shellEnvironmentPolicy
    case shellEnvironmentPolicySet
    case skills
    case toolSuggest
    case toolSuggestDisabledToolsArray
    case toolsWebSearch
    case toolsWebSearchLocation
    case profileFeatures(String)
    case profileFeaturesAppsMcpPathOverride(String)
    case profileToolsWebSearch(String)
    case profileToolsWebSearchLocation(String)
    case ignoredDenylistedTable(String)
    case ignored
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
