import Foundation

public struct FeaturesToml: Codable, Equatable, Sendable {
    public var entries: [String: Bool]

    public init(entries: [String: Bool] = [:]) {
        self.entries = entries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.entries = try container.decode([String: Bool].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(entries)
    }
}

public struct ConfigProfileTools: Codable, Equatable, Sendable {
    public var webSearch: AppServerProtocol.WebSearchToolConfig?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case webSearch = "web_search"
    }

    public init(
        webSearch: AppServerProtocol.WebSearchToolConfig? = nil
    ) {
        self.webSearch = webSearch
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownConfigProfileKeys(
            in: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.stringValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.webSearch),
           (try? container.decode(Bool.self, forKey: .webSearch)) != nil {
            self.webSearch = nil
        } else {
            self.webSearch = try container.decodeIfPresent(
                AppServerProtocol.WebSearchToolConfig.self,
                forKey: .webSearch
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encodeOptional(webSearch, into: &container, forKey: .webSearch)
    }
}

public struct ConfigProfileAnalytics: Codable, Equatable, Sendable {
    public var enabled: Bool?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case enabled
    }

    public init(enabled: Bool? = nil) {
        self.enabled = enabled
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownConfigProfileKeys(
            in: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.stringValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encodeOptional(enabled, into: &container, forKey: .enabled)
    }
}

public struct ConfigProfileTui: Codable, Equatable, Sendable {
    public var sessionPickerView: TuiSessionPickerViewMode?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sessionPickerView = "session_picker_view"
    }

    public init(sessionPickerView: TuiSessionPickerViewMode? = nil) {
        self.sessionPickerView = sessionPickerView
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownConfigProfileKeys(
            in: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.stringValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sessionPickerView = try container.decodeIfPresent(
            TuiSessionPickerViewMode.self,
            forKey: .sessionPickerView
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encodeOptional(sessionPickerView, into: &container, forKey: .sessionPickerView)
    }
}

public enum ConfigProfileWindowsSandboxMode: String, Codable, Equatable, Sendable {
    case elevated
    case unelevated
}

public struct ConfigProfileWindows: Codable, Equatable, Sendable {
    public var sandbox: ConfigProfileWindowsSandboxMode?
    public var sandboxPrivateDesktop: Bool?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sandbox
        case sandboxPrivateDesktop = "sandbox_private_desktop"
    }

    public init(
        sandbox: ConfigProfileWindowsSandboxMode? = nil,
        sandboxPrivateDesktop: Bool? = nil
    ) {
        self.sandbox = sandbox
        self.sandboxPrivateDesktop = sandboxPrivateDesktop
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownConfigProfileKeys(
            in: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.stringValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sandbox = try container.decodeIfPresent(ConfigProfileWindowsSandboxMode.self, forKey: .sandbox)
        self.sandboxPrivateDesktop = try container.decodeIfPresent(Bool.self, forKey: .sandboxPrivateDesktop)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encodeOptional(sandbox, into: &container, forKey: .sandbox)
        try encodeOptional(sandboxPrivateDesktop, into: &container, forKey: .sandboxPrivateDesktop)
    }
}

private struct ConfigProfileAnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        nil
    }
}

private func rejectUnknownConfigProfileKeys(in decoder: Decoder, allowedKeys: Set<String>) throws {
    let container = try decoder.container(keyedBy: ConfigProfileAnyCodingKey.self)
    if let unknown = container.allKeys.first(where: { !allowedKeys.contains($0.stringValue) }) {
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: decoder.codingPath + [unknown],
                debugDescription: "Unknown field '\(unknown.stringValue)'"
            )
        )
    }
}

public struct ConfigProfile: Codable, Equatable, Sendable {
    public var model: String?
    public var modelProvider: String?
    public var approvalPolicy: AskForApproval?
    public var approvalsReviewer: ApprovalsReviewer?
    public var sandboxMode: SandboxMode?
    public var modelReasoningEffort: ReasoningEffort?
    public var planModeReasoningEffort: ReasoningEffort?
    public var modelReasoningSummary: ReasoningSummary?
    public var modelVerbosity: Verbosity?
    public var serviceTier: String?
    public var modelCatalogJSON: String?
    public var personality: Personality?
    public var chatgptBaseURL: String?
    public var modelInstructionsFile: String?
    public var jsReplNodePath: String?
    public var jsReplNodeModuleDirs: [String]?
    public var zshPath: String?
    public var experimentalCompactPromptFile: String?
    public var includePermissionsInstructions: Bool?
    public var includeAppsInstructions: Bool?
    public var includeCollaborationModeInstructions: Bool?
    public var includeEnvironmentContext: Bool?
    public var experimentalUseUnifiedExecTool: Bool?
    public var webSearchMode: WebSearchMode?
    public var toolsWebSearch: Bool?
    public var tools: ConfigProfileTools?
    public var analytics: ConfigProfileAnalytics?
    public var tui: ConfigProfileTui?
    public var windows: ConfigProfileWindows?
    public var features: FeaturesToml?
    public var ossProvider: String?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case model
        case modelProvider = "model_provider"
        case approvalPolicy = "approval_policy"
        case approvalsReviewer = "approvals_reviewer"
        case sandboxMode = "sandbox_mode"
        case modelReasoningEffort = "model_reasoning_effort"
        case planModeReasoningEffort = "plan_mode_reasoning_effort"
        case modelReasoningSummary = "model_reasoning_summary"
        case modelVerbosity = "model_verbosity"
        case serviceTier = "service_tier"
        case modelCatalogJSON = "model_catalog_json"
        case personality
        case chatgptBaseURL = "chatgpt_base_url"
        case modelInstructionsFile = "model_instructions_file"
        case jsReplNodePath = "js_repl_node_path"
        case jsReplNodeModuleDirs = "js_repl_node_module_dirs"
        case zshPath = "zsh_path"
        case experimentalCompactPromptFile = "experimental_compact_prompt_file"
        case includePermissionsInstructions = "include_permissions_instructions"
        case includeAppsInstructions = "include_apps_instructions"
        case includeCollaborationModeInstructions = "include_collaboration_mode_instructions"
        case includeEnvironmentContext = "include_environment_context"
        case experimentalUseUnifiedExecTool = "experimental_use_unified_exec_tool"
        case webSearchMode = "web_search"
        case toolsWebSearch = "tools_web_search"
        case tools
        case analytics
        case tui
        case windows
        case features
        case ossProvider = "oss_provider"
    }

    public init(
        model: String? = nil,
        modelProvider: String? = nil,
        approvalPolicy: AskForApproval? = nil,
        approvalsReviewer: ApprovalsReviewer? = nil,
        sandboxMode: SandboxMode? = nil,
        modelReasoningEffort: ReasoningEffort? = nil,
        planModeReasoningEffort: ReasoningEffort? = nil,
        modelReasoningSummary: ReasoningSummary? = nil,
        modelVerbosity: Verbosity? = nil,
        serviceTier: String? = nil,
        modelCatalogJSON: String? = nil,
        personality: Personality? = nil,
        chatgptBaseURL: String? = nil,
        modelInstructionsFile: String? = nil,
        jsReplNodePath: String? = nil,
        jsReplNodeModuleDirs: [String]? = nil,
        zshPath: String? = nil,
        experimentalCompactPromptFile: String? = nil,
        includePermissionsInstructions: Bool? = nil,
        includeAppsInstructions: Bool? = nil,
        includeCollaborationModeInstructions: Bool? = nil,
        includeEnvironmentContext: Bool? = nil,
        experimentalUseUnifiedExecTool: Bool? = nil,
        webSearchMode: WebSearchMode? = nil,
        toolsWebSearch: Bool? = nil,
        tools: ConfigProfileTools? = nil,
        analytics: ConfigProfileAnalytics? = nil,
        tui: ConfigProfileTui? = nil,
        windows: ConfigProfileWindows? = nil,
        features: FeaturesToml? = nil,
        ossProvider: String? = nil
    ) {
        self.model = model
        self.modelProvider = modelProvider
        self.approvalPolicy = approvalPolicy
        self.approvalsReviewer = approvalsReviewer
        self.sandboxMode = sandboxMode
        self.modelReasoningEffort = modelReasoningEffort
        self.planModeReasoningEffort = planModeReasoningEffort
        self.modelReasoningSummary = modelReasoningSummary
        self.modelVerbosity = modelVerbosity
        self.serviceTier = serviceTier
        self.modelCatalogJSON = modelCatalogJSON
        self.personality = personality
        self.chatgptBaseURL = chatgptBaseURL
        self.modelInstructionsFile = modelInstructionsFile
        self.jsReplNodePath = jsReplNodePath
        self.jsReplNodeModuleDirs = jsReplNodeModuleDirs
        self.zshPath = zshPath
        self.experimentalCompactPromptFile = experimentalCompactPromptFile
        self.includePermissionsInstructions = includePermissionsInstructions
        self.includeAppsInstructions = includeAppsInstructions
        self.includeCollaborationModeInstructions = includeCollaborationModeInstructions
        self.includeEnvironmentContext = includeEnvironmentContext
        self.experimentalUseUnifiedExecTool = experimentalUseUnifiedExecTool
        self.webSearchMode = webSearchMode
        self.toolsWebSearch = toolsWebSearch
        self.tools = tools
        self.analytics = analytics
        self.tui = tui
        self.windows = windows
        self.features = features
        self.ossProvider = ossProvider
    }

    public init(from decoder: Decoder) throws {
        try Self.rejectUnknownKeys(in: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.model = try container.decodeIfPresent(String.self, forKey: .model)
        self.modelProvider = try container.decodeIfPresent(String.self, forKey: .modelProvider)
        self.approvalPolicy = try container.decodeIfPresent(AskForApproval.self, forKey: .approvalPolicy)
        self.approvalsReviewer = try container.decodeIfPresent(ApprovalsReviewer.self, forKey: .approvalsReviewer)
        self.sandboxMode = try container.decodeIfPresent(SandboxMode.self, forKey: .sandboxMode)
        self.modelReasoningEffort = try container.decodeIfPresent(ReasoningEffort.self, forKey: .modelReasoningEffort)
        self.planModeReasoningEffort = try container.decodeIfPresent(ReasoningEffort.self, forKey: .planModeReasoningEffort)
        self.modelReasoningSummary = try container.decodeIfPresent(ReasoningSummary.self, forKey: .modelReasoningSummary)
        self.modelVerbosity = try container.decodeIfPresent(Verbosity.self, forKey: .modelVerbosity)
        self.serviceTier = try container.decodeIfPresent(String.self, forKey: .serviceTier)
        self.modelCatalogJSON = try container.decodeIfPresent(String.self, forKey: .modelCatalogJSON)
        self.personality = try container.decodeIfPresent(Personality.self, forKey: .personality)
        self.chatgptBaseURL = try container.decodeIfPresent(String.self, forKey: .chatgptBaseURL)
        self.modelInstructionsFile = try container.decodeIfPresent(String.self, forKey: .modelInstructionsFile)
        self.jsReplNodePath = try container.decodeIfPresent(String.self, forKey: .jsReplNodePath)
        self.jsReplNodeModuleDirs = try container.decodeIfPresent([String].self, forKey: .jsReplNodeModuleDirs)
        self.zshPath = try container.decodeIfPresent(String.self, forKey: .zshPath)
        self.experimentalCompactPromptFile = try container.decodeIfPresent(String.self, forKey: .experimentalCompactPromptFile)
        self.includePermissionsInstructions = try container.decodeIfPresent(Bool.self, forKey: .includePermissionsInstructions)
        self.includeAppsInstructions = try container.decodeIfPresent(Bool.self, forKey: .includeAppsInstructions)
        self.includeCollaborationModeInstructions = try container.decodeIfPresent(
            Bool.self,
            forKey: .includeCollaborationModeInstructions
        )
        self.includeEnvironmentContext = try container.decodeIfPresent(Bool.self, forKey: .includeEnvironmentContext)
        self.experimentalUseUnifiedExecTool = try container.decodeIfPresent(Bool.self, forKey: .experimentalUseUnifiedExecTool)
        self.webSearchMode = try container.decodeIfPresent(WebSearchMode.self, forKey: .webSearchMode)
        self.toolsWebSearch = try container.decodeIfPresent(Bool.self, forKey: .toolsWebSearch)
        self.tools = try container.decodeIfPresent(ConfigProfileTools.self, forKey: .tools)
        self.analytics = try container.decodeIfPresent(ConfigProfileAnalytics.self, forKey: .analytics)
        self.tui = try container.decodeIfPresent(ConfigProfileTui.self, forKey: .tui)
        self.windows = try container.decodeIfPresent(ConfigProfileWindows.self, forKey: .windows)
        self.features = try container.decodeIfPresent(FeaturesToml.self, forKey: .features)
        self.ossProvider = try container.decodeIfPresent(String.self, forKey: .ossProvider)
    }

    private static func rejectUnknownKeys(in decoder: Decoder) throws {
        try rejectUnknownConfigProfileKeys(
            in: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.stringValue))
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encodeOptional(model, into: &container, forKey: .model)
        try encodeOptional(modelProvider, into: &container, forKey: .modelProvider)
        try encodeOptional(approvalPolicy, into: &container, forKey: .approvalPolicy)
        try encodeOptional(approvalsReviewer, into: &container, forKey: .approvalsReviewer)
        try encodeOptional(sandboxMode, into: &container, forKey: .sandboxMode)
        try encodeOptional(modelReasoningEffort, into: &container, forKey: .modelReasoningEffort)
        try encodeOptional(planModeReasoningEffort, into: &container, forKey: .planModeReasoningEffort)
        try encodeOptional(modelReasoningSummary, into: &container, forKey: .modelReasoningSummary)
        try encodeOptional(modelVerbosity, into: &container, forKey: .modelVerbosity)
        try encodeOptional(serviceTier, into: &container, forKey: .serviceTier)
        try encodeOptional(modelCatalogJSON, into: &container, forKey: .modelCatalogJSON)
        try encodeOptional(personality, into: &container, forKey: .personality)
        try encodeOptional(chatgptBaseURL, into: &container, forKey: .chatgptBaseURL)
        try encodeOptional(modelInstructionsFile, into: &container, forKey: .modelInstructionsFile)
        try encodeOptional(jsReplNodePath, into: &container, forKey: .jsReplNodePath)
        try encodeOptional(jsReplNodeModuleDirs, into: &container, forKey: .jsReplNodeModuleDirs)
        try encodeOptional(zshPath, into: &container, forKey: .zshPath)
        try encodeOptional(experimentalCompactPromptFile, into: &container, forKey: .experimentalCompactPromptFile)
        try encodeOptional(includePermissionsInstructions, into: &container, forKey: .includePermissionsInstructions)
        try encodeOptional(includeAppsInstructions, into: &container, forKey: .includeAppsInstructions)
        try encodeOptional(
            includeCollaborationModeInstructions,
            into: &container,
            forKey: .includeCollaborationModeInstructions
        )
        try encodeOptional(includeEnvironmentContext, into: &container, forKey: .includeEnvironmentContext)
        try encodeOptional(experimentalUseUnifiedExecTool, into: &container, forKey: .experimentalUseUnifiedExecTool)
        try encodeOptional(webSearchMode, into: &container, forKey: .webSearchMode)
        try encodeOptional(toolsWebSearch, into: &container, forKey: .toolsWebSearch)
        try encodeOptional(tools, into: &container, forKey: .tools)
        try encodeOptional(analytics, into: &container, forKey: .analytics)
        try encodeOptional(tui, into: &container, forKey: .tui)
        try encodeOptional(windows, into: &container, forKey: .windows)
        try encodeOptional(features, into: &container, forKey: .features)
        try encodeOptional(ossProvider, into: &container, forKey: .ossProvider)
    }

    public func appServerProfile() -> AppServerProfile {
        AppServerProfile(
            model: model,
            modelProvider: modelProvider,
            approvalPolicy: approvalPolicy,
            approvalsReviewer: approvalsReviewer,
            modelReasoningEffort: modelReasoningEffort,
            modelReasoningSummary: modelReasoningSummary,
            modelVerbosity: modelVerbosity,
            chatgptBaseURL: chatgptBaseURL
        )
    }
}

public struct AppServerProfile: Codable, Equatable, Sendable {
    public var model: String?
    public var modelProvider: String?
    public var approvalPolicy: AskForApproval?
    public var approvalsReviewer: ApprovalsReviewer?
    public var modelReasoningEffort: ReasoningEffort?
    public var modelReasoningSummary: ReasoningSummary?
    public var modelVerbosity: Verbosity?
    public var chatgptBaseURL: String?

    private enum CodingKeys: String, CodingKey {
        case model
        case modelProvider
        case approvalPolicy
        case approvalsReviewer
        case modelReasoningEffort
        case modelReasoningSummary
        case modelVerbosity
        case chatgptBaseURL
    }

    public init(
        model: String? = nil,
        modelProvider: String? = nil,
        approvalPolicy: AskForApproval? = nil,
        approvalsReviewer: ApprovalsReviewer? = nil,
        modelReasoningEffort: ReasoningEffort? = nil,
        modelReasoningSummary: ReasoningSummary? = nil,
        modelVerbosity: Verbosity? = nil,
        chatgptBaseURL: String? = nil
    ) {
        self.model = model
        self.modelProvider = modelProvider
        self.approvalPolicy = approvalPolicy
        self.approvalsReviewer = approvalsReviewer
        self.modelReasoningEffort = modelReasoningEffort
        self.modelReasoningSummary = modelReasoningSummary
        self.modelVerbosity = modelVerbosity
        self.chatgptBaseURL = chatgptBaseURL
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.model = try container.decodeIfPresent(String.self, forKey: .model)
        self.modelProvider = try container.decodeIfPresent(String.self, forKey: .modelProvider)
        self.approvalPolicy = try container.decodeIfPresent(AskForApproval.self, forKey: .approvalPolicy)
        self.approvalsReviewer = try container.decodeIfPresent(ApprovalsReviewer.self, forKey: .approvalsReviewer)
        self.modelReasoningEffort = try container.decodeIfPresent(ReasoningEffort.self, forKey: .modelReasoningEffort)
        self.modelReasoningSummary = try container.decodeIfPresent(ReasoningSummary.self, forKey: .modelReasoningSummary)
        self.modelVerbosity = try container.decodeIfPresent(Verbosity.self, forKey: .modelVerbosity)
        self.chatgptBaseURL = try container.decodeIfPresent(String.self, forKey: .chatgptBaseURL)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encodeOptional(model, into: &container, forKey: .model)
        try encodeOptional(modelProvider, into: &container, forKey: .modelProvider)
        try encodeOptional(approvalPolicy, into: &container, forKey: .approvalPolicy)
        try encodeOptional(approvalsReviewer, into: &container, forKey: .approvalsReviewer)
        try encodeOptional(modelReasoningEffort, into: &container, forKey: .modelReasoningEffort)
        try encodeOptional(modelReasoningSummary, into: &container, forKey: .modelReasoningSummary)
        try encodeOptional(modelVerbosity, into: &container, forKey: .modelVerbosity)
        try encodeOptional(chatgptBaseURL, into: &container, forKey: .chatgptBaseURL)
    }
}

private func encodeOptional<T: Encodable, K: CodingKey>(
    _ value: T?,
    into container: inout KeyedEncodingContainer<K>,
    forKey key: K
) throws {
    if let value {
        try container.encode(value, forKey: key)
    } else {
        try container.encodeNil(forKey: key)
    }
}
