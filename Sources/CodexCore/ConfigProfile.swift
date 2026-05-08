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
    public var sandboxMode: SandboxMode?
    public var modelReasoningEffort: ReasoningEffort?
    public var modelReasoningSummary: ReasoningSummary?
    public var modelVerbosity: Verbosity?
    public var serviceTier: String?
    public var chatgptBaseURL: String?
    public var experimentalInstructionsFile: String?
    public var experimentalCompactPromptFile: String?
    public var includeApplyPatchTool: Bool?
    public var experimentalUseUnifiedExecTool: Bool?
    public var experimentalUseFreeformApplyPatch: Bool?
    public var toolsWebSearch: Bool?
    public var toolsViewImage: Bool?
    public var features: FeaturesToml?
    public var ossProvider: String?

    private enum CodingKeys: String, CodingKey {
        case model
        case modelProvider = "model_provider"
        case approvalPolicy = "approval_policy"
        case sandboxMode = "sandbox_mode"
        case modelReasoningEffort = "model_reasoning_effort"
        case modelReasoningSummary = "model_reasoning_summary"
        case modelVerbosity = "model_verbosity"
        case serviceTier = "service_tier"
        case chatgptBaseURL = "chatgpt_base_url"
        case experimentalInstructionsFile = "experimental_instructions_file"
        case experimentalCompactPromptFile = "experimental_compact_prompt_file"
        case includeApplyPatchTool = "include_apply_patch_tool"
        case experimentalUseUnifiedExecTool = "experimental_use_unified_exec_tool"
        case experimentalUseFreeformApplyPatch = "experimental_use_freeform_apply_patch"
        case toolsWebSearch = "tools_web_search"
        case toolsViewImage = "tools_view_image"
        case features
        case ossProvider = "oss_provider"
    }

    public init(
        model: String? = nil,
        modelProvider: String? = nil,
        approvalPolicy: AskForApproval? = nil,
        sandboxMode: SandboxMode? = nil,
        modelReasoningEffort: ReasoningEffort? = nil,
        modelReasoningSummary: ReasoningSummary? = nil,
        modelVerbosity: Verbosity? = nil,
        serviceTier: String? = nil,
        chatgptBaseURL: String? = nil,
        experimentalInstructionsFile: String? = nil,
        experimentalCompactPromptFile: String? = nil,
        includeApplyPatchTool: Bool? = nil,
        experimentalUseUnifiedExecTool: Bool? = nil,
        experimentalUseFreeformApplyPatch: Bool? = nil,
        toolsWebSearch: Bool? = nil,
        toolsViewImage: Bool? = nil,
        features: FeaturesToml? = nil,
        ossProvider: String? = nil
    ) {
        self.model = model
        self.modelProvider = modelProvider
        self.approvalPolicy = approvalPolicy
        self.sandboxMode = sandboxMode
        self.modelReasoningEffort = modelReasoningEffort
        self.modelReasoningSummary = modelReasoningSummary
        self.modelVerbosity = modelVerbosity
        self.serviceTier = serviceTier
        self.chatgptBaseURL = chatgptBaseURL
        self.experimentalInstructionsFile = experimentalInstructionsFile
        self.experimentalCompactPromptFile = experimentalCompactPromptFile
        self.includeApplyPatchTool = includeApplyPatchTool
        self.experimentalUseUnifiedExecTool = experimentalUseUnifiedExecTool
        self.experimentalUseFreeformApplyPatch = experimentalUseFreeformApplyPatch
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
        self.sandboxMode = try container.decodeIfPresent(SandboxMode.self, forKey: .sandboxMode)
        self.modelReasoningEffort = try container.decodeIfPresent(ReasoningEffort.self, forKey: .modelReasoningEffort)
        self.modelReasoningSummary = try container.decodeIfPresent(ReasoningSummary.self, forKey: .modelReasoningSummary)
        self.modelVerbosity = try container.decodeIfPresent(Verbosity.self, forKey: .modelVerbosity)
        self.serviceTier = try container.decodeIfPresent(String.self, forKey: .serviceTier)
        self.chatgptBaseURL = try container.decodeIfPresent(String.self, forKey: .chatgptBaseURL)
        self.experimentalInstructionsFile = try container.decodeIfPresent(String.self, forKey: .experimentalInstructionsFile)
        self.experimentalCompactPromptFile = try container.decodeIfPresent(String.self, forKey: .experimentalCompactPromptFile)
        self.includeApplyPatchTool = try container.decodeIfPresent(Bool.self, forKey: .includeApplyPatchTool)
        self.experimentalUseUnifiedExecTool = try container.decodeIfPresent(Bool.self, forKey: .experimentalUseUnifiedExecTool)
        self.experimentalUseFreeformApplyPatch = try container.decodeIfPresent(Bool.self, forKey: .experimentalUseFreeformApplyPatch)
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
        try encodeOptional(sandboxMode, into: &container, forKey: .sandboxMode)
        try encodeOptional(modelReasoningEffort, into: &container, forKey: .modelReasoningEffort)
        try encodeOptional(modelReasoningSummary, into: &container, forKey: .modelReasoningSummary)
        try encodeOptional(modelVerbosity, into: &container, forKey: .modelVerbosity)
        try encodeOptional(serviceTier, into: &container, forKey: .serviceTier)
        try encodeOptional(chatgptBaseURL, into: &container, forKey: .chatgptBaseURL)
        try encodeOptional(experimentalInstructionsFile, into: &container, forKey: .experimentalInstructionsFile)
        try encodeOptional(experimentalCompactPromptFile, into: &container, forKey: .experimentalCompactPromptFile)
        try encodeOptional(includeApplyPatchTool, into: &container, forKey: .includeApplyPatchTool)
        try encodeOptional(experimentalUseUnifiedExecTool, into: &container, forKey: .experimentalUseUnifiedExecTool)
        try encodeOptional(experimentalUseFreeformApplyPatch, into: &container, forKey: .experimentalUseFreeformApplyPatch)
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
            modelReasoningEffort: modelReasoningEffort,
            modelReasoningSummary: modelReasoningSummary,
            modelVerbosity: modelVerbosity,
            serviceTier: serviceTier,
            chatgptBaseURL: chatgptBaseURL
        )
    }
}

public struct AppServerProfile: Codable, Equatable, Sendable {
    public var model: String?
    public var modelProvider: String?
    public var approvalPolicy: AskForApproval?
    public var modelReasoningEffort: ReasoningEffort?
    public var modelReasoningSummary: ReasoningSummary?
    public var modelVerbosity: Verbosity?
    public var serviceTier: String?
    public var chatgptBaseURL: String?

    private enum CodingKeys: String, CodingKey {
        case model
        case modelProvider
        case approvalPolicy
        case modelReasoningEffort
        case modelReasoningSummary
        case modelVerbosity
        case serviceTier
        case chatgptBaseURL
    }

    public init(
        model: String? = nil,
        modelProvider: String? = nil,
        approvalPolicy: AskForApproval? = nil,
        modelReasoningEffort: ReasoningEffort? = nil,
        modelReasoningSummary: ReasoningSummary? = nil,
        modelVerbosity: Verbosity? = nil,
        serviceTier: String? = nil,
        chatgptBaseURL: String? = nil
    ) {
        self.model = model
        self.modelProvider = modelProvider
        self.approvalPolicy = approvalPolicy
        self.modelReasoningEffort = modelReasoningEffort
        self.modelReasoningSummary = modelReasoningSummary
        self.modelVerbosity = modelVerbosity
        self.serviceTier = serviceTier
        self.chatgptBaseURL = chatgptBaseURL
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.model = try container.decodeIfPresent(String.self, forKey: .model)
        self.modelProvider = try container.decodeIfPresent(String.self, forKey: .modelProvider)
        self.approvalPolicy = try container.decodeIfPresent(AskForApproval.self, forKey: .approvalPolicy)
        self.modelReasoningEffort = try container.decodeIfPresent(ReasoningEffort.self, forKey: .modelReasoningEffort)
        self.modelReasoningSummary = try container.decodeIfPresent(ReasoningSummary.self, forKey: .modelReasoningSummary)
        self.modelVerbosity = try container.decodeIfPresent(Verbosity.self, forKey: .modelVerbosity)
        self.serviceTier = try container.decodeIfPresent(String.self, forKey: .serviceTier)
        self.chatgptBaseURL = try container.decodeIfPresent(String.self, forKey: .chatgptBaseURL)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encodeOptional(model, into: &container, forKey: .model)
        try encodeOptional(modelProvider, into: &container, forKey: .modelProvider)
        try encodeOptional(approvalPolicy, into: &container, forKey: .approvalPolicy)
        try encodeOptional(modelReasoningEffort, into: &container, forKey: .modelReasoningEffort)
        try encodeOptional(modelReasoningSummary, into: &container, forKey: .modelReasoningSummary)
        try encodeOptional(modelVerbosity, into: &container, forKey: .modelVerbosity)
        try encodeOptional(serviceTier, into: &container, forKey: .serviceTier)
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
