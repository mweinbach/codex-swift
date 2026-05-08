import Foundation

public struct SessionConfiguredEvent: Equatable, Codable, Sendable {
    public let sessionID: ConversationId
    public let model: String
    public let modelProviderID: String
    public let approvalPolicy: AskForApproval
    public let sandboxPolicy: SandboxPolicy
    public let cwd: String
    public let reasoningEffort: ReasoningEffort?
    public let historyLogID: UInt64
    public let historyEntryCount: Int
    public let initialMessages: [EventMessage]?
    public let rolloutPath: String

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case model
        case modelProviderID = "model_provider_id"
        case approvalPolicy = "approval_policy"
        case sandboxPolicy = "sandbox_policy"
        case cwd
        case reasoningEffort = "reasoning_effort"
        case historyLogID = "history_log_id"
        case historyEntryCount = "history_entry_count"
        case initialMessages = "initial_messages"
        case rolloutPath = "rollout_path"
    }

    public init(
        sessionID: ConversationId,
        model: String,
        modelProviderID: String,
        approvalPolicy: AskForApproval,
        sandboxPolicy: SandboxPolicy,
        cwd: String,
        reasoningEffort: ReasoningEffort? = nil,
        historyLogID: UInt64,
        historyEntryCount: Int,
        initialMessages: [EventMessage]? = nil,
        rolloutPath: String
    ) {
        self.sessionID = sessionID
        self.model = model
        self.modelProviderID = modelProviderID
        self.approvalPolicy = approvalPolicy
        self.sandboxPolicy = sandboxPolicy
        self.cwd = cwd
        self.reasoningEffort = reasoningEffort
        self.historyLogID = historyLogID
        self.historyEntryCount = historyEntryCount
        self.initialMessages = initialMessages
        self.rolloutPath = rolloutPath
    }
}
