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
    public var chatgptBaseURL: String?
    public var experimentalInstructionsFile: String?
    public var experimentalCompactPromptFile: String?
    public var includePermissionsInstructions: Bool?
    public var includeAppsInstructions: Bool?
    public var includeEnvironmentContext: Bool?
    public var includeApplyPatchTool: Bool?
    public var experimentalUseUnifiedExecTool: Bool?
    public var experimentalUseFreeformApplyPatch: Bool?
    public var webSearchMode: WebSearchMode?
    public var toolsWebSearch: Bool?
    public var toolsViewImage: Bool?
    public var features: FeaturesToml?
    public var ossProvider: String?

    private enum CodingKeys: String, CodingKey {
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
        case chatgptBaseURL = "chatgpt_base_url"
        case experimentalInstructionsFile = "experimental_instructions_file"
        case experimentalCompactPromptFile = "experimental_compact_prompt_file"
        case includePermissionsInstructions = "include_permissions_instructions"
        case includeAppsInstructions = "include_apps_instructions"
        case includeEnvironmentContext = "include_environment_context"
        case includeApplyPatchTool = "include_apply_patch_tool"
        case experimentalUseUnifiedExecTool = "experimental_use_unified_exec_tool"
        case experimentalUseFreeformApplyPatch = "experimental_use_freeform_apply_patch"
        case webSearchMode = "web_search"
        case toolsWebSearch = "tools_web_search"
        case toolsViewImage = "tools_view_image"
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
        chatgptBaseURL: String? = nil,
        experimentalInstructionsFile: String? = nil,
        experimentalCompactPromptFile: String? = nil,
        includePermissionsInstructions: Bool? = nil,
        includeAppsInstructions: Bool? = nil,
        includeEnvironmentContext: Bool? = nil,
        includeApplyPatchTool: Bool? = nil,
        experimentalUseUnifiedExecTool: Bool? = nil,
        experimentalUseFreeformApplyPatch: Bool? = nil,
        webSearchMode: WebSearchMode? = nil,
        toolsWebSearch: Bool? = nil,
        toolsViewImage: Bool? = nil,
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
        self.chatgptBaseURL = chatgptBaseURL
        self.experimentalInstructionsFile = experimentalInstructionsFile
        self.experimentalCompactPromptFile = experimentalCompactPromptFile
        self.includePermissionsInstructions = includePermissionsInstructions
        self.includeAppsInstructions = includeAppsInstructions
        self.includeEnvironmentContext = includeEnvironmentContext
        self.includeApplyPatchTool = includeApplyPatchTool
        self.experimentalUseUnifiedExecTool = experimentalUseUnifiedExecTool
        self.experimentalUseFreeformApplyPatch = experimentalUseFreeformApplyPatch
        self.webSearchMode = webSearchMode
        self.toolsWebSearch = toolsWebSearch
        self.toolsViewImage = toolsViewImage
        self.features = features
        self.ossProvider = ossProvider
    }

    public init(from decoder: Decoder) throws {
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
        self.chatgptBaseURL = try container.decodeIfPresent(String.self, forKey: .chatgptBaseURL)
        self.experimentalInstructionsFile = try container.decodeIfPresent(String.self, forKey: .experimentalInstructionsFile)
        self.experimentalCompactPromptFile = try container.decodeIfPresent(String.self, forKey: .experimentalCompactPromptFile)
        self.includePermissionsInstructions = try container.decodeIfPresent(Bool.self, forKey: .includePermissionsInstructions)
        self.includeAppsInstructions = try container.decodeIfPresent(Bool.self, forKey: .includeAppsInstructions)
        self.includeEnvironmentContext = try container.decodeIfPresent(Bool.self, forKey: .includeEnvironmentContext)
        self.includeApplyPatchTool = try container.decodeIfPresent(Bool.self, forKey: .includeApplyPatchTool)
        self.experimentalUseUnifiedExecTool = try container.decodeIfPresent(Bool.self, forKey: .experimentalUseUnifiedExecTool)
        self.experimentalUseFreeformApplyPatch = try container.decodeIfPresent(Bool.self, forKey: .experimentalUseFreeformApplyPatch)
        self.webSearchMode = try container.decodeIfPresent(WebSearchMode.self, forKey: .webSearchMode)
        self.toolsWebSearch = try container.decodeIfPresent(Bool.self, forKey: .toolsWebSearch)
        self.toolsViewImage = try container.decodeIfPresent(Bool.self, forKey: .toolsViewImage)
        self.features = try container.decodeIfPresent(FeaturesToml.self, forKey: .features)
        self.ossProvider = try container.decodeIfPresent(String.self, forKey: .ossProvider)
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
        try encodeOptional(chatgptBaseURL, into: &container, forKey: .chatgptBaseURL)
        try encodeOptional(experimentalInstructionsFile, into: &container, forKey: .experimentalInstructionsFile)
        try encodeOptional(experimentalCompactPromptFile, into: &container, forKey: .experimentalCompactPromptFile)
        try encodeOptional(includePermissionsInstructions, into: &container, forKey: .includePermissionsInstructions)
        try encodeOptional(includeAppsInstructions, into: &container, forKey: .includeAppsInstructions)
        try encodeOptional(includeEnvironmentContext, into: &container, forKey: .includeEnvironmentContext)
        try encodeOptional(includeApplyPatchTool, into: &container, forKey: .includeApplyPatchTool)
        try encodeOptional(experimentalUseUnifiedExecTool, into: &container, forKey: .experimentalUseUnifiedExecTool)
        try encodeOptional(experimentalUseFreeformApplyPatch, into: &container, forKey: .experimentalUseFreeformApplyPatch)
        try encodeOptional(webSearchMode, into: &container, forKey: .webSearchMode)
        try encodeOptional(toolsWebSearch, into: &container, forKey: .toolsWebSearch)
        try encodeOptional(toolsViewImage, into: &container, forKey: .toolsViewImage)
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
