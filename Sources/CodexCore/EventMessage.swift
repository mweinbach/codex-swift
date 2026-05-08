import Foundation

public struct Event: Equatable, Codable, Sendable {
    public let id: String
    public let msg: EventMessage

    public init(id: String, msg: EventMessage) {
        self.id = id
        self.msg = msg
    }
}

public struct ContextCompactedEvent: Equatable, Codable, Sendable {
    public init() {}
}

public enum EventMessage: Equatable, Codable, Sendable {
    case error(ErrorEvent)
    case warning(WarningEvent)
    case contextCompacted(ContextCompactedEvent)
    case taskStarted(TaskStartedEvent)
    case taskComplete(TaskCompleteEvent)
    case tokenCount(TokenCountEvent)
    case agentMessage(AgentMessageEvent)
    case userMessage(UserMessageEvent)
    case agentMessageDelta(AgentMessageDeltaEvent)
    case agentReasoning(AgentReasoningEvent)
    case agentReasoningDelta(AgentReasoningDeltaEvent)
    case agentReasoningRawContent(AgentReasoningRawContentEvent)
    case agentReasoningRawContentDelta(AgentReasoningRawContentDeltaEvent)
    case agentReasoningSectionBreak(AgentReasoningSectionBreakEvent)
    case sessionConfigured(SessionConfiguredEvent)
    case mcpStartupUpdate(McpStartupUpdateEvent)
    case mcpStartupComplete(McpStartupCompleteEvent)
    case mcpToolCallBegin(McpToolCallBeginEvent)
    case mcpToolCallEnd(McpToolCallEndEvent)
    case mcpListToolsResponse(McpListToolsResponseEvent)
    case webSearchBegin(WebSearchBeginEvent)
    case webSearchEnd(WebSearchEndEvent)
    case imageGenerationBegin(ImageGenerationBeginEvent)
    case imageGenerationEnd(ImageGenerationEndEvent)
    case execCommandBegin(ExecCommandBeginEvent)
    case execCommandOutputDelta(ExecCommandOutputDeltaEvent)
    case terminalInteraction(TerminalInteractionEvent)
    case execCommandEnd(ExecCommandEndEvent)
    case viewImageToolCall(ViewImageToolCallEvent)
    case execApprovalRequest(ExecApprovalRequestEvent)
    case elicitationRequest(ElicitationRequestEvent)
    case applyPatchApprovalRequest(ApplyPatchApprovalRequestEvent)
    case deprecationNotice(DeprecationNoticeEvent)
    case backgroundEvent(BackgroundEventEvent)
    case undoStarted(UndoStartedEvent)
    case undoCompleted(UndoCompletedEvent)
    case streamError(StreamErrorEvent)
    case patchApplyBegin(PatchApplyBeginEvent)
    case patchApplyEnd(PatchApplyEndEvent)
    case turnDiff(TurnDiffEvent)
    case getHistoryEntryResponse(GetHistoryEntryResponseEvent)
    case listSkillsResponse(ListSkillsResponseEvent)
    case listCustomPromptsResponse(ListCustomPromptsResponseEvent)
    case skillsUpdateAvailable
    case planUpdate(UpdatePlanArguments)
    case turnAborted(TurnAbortedEvent)
    case shutdownComplete
    case enteredReviewMode(ReviewRequest)
    case exitedReviewMode(ExitedReviewModeEvent)
    case rawResponseItem(RawResponseItemEvent)
    case itemStarted(ItemStartedEvent)
    case itemCompleted(ItemCompletedEvent)
    case agentMessageContentDelta(AgentMessageContentDeltaEvent)
    case reasoningContentDelta(ReasoningContentDeltaEvent)
    case reasoningRawContentDelta(ReasoningRawContentDeltaEvent)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    private enum EventType: String, Codable {
        case error
        case warning
        case contextCompacted = "context_compacted"
        case taskStarted = "task_started"
        case taskComplete = "task_complete"
        case tokenCount = "token_count"
        case agentMessage = "agent_message"
        case userMessage = "user_message"
        case agentMessageDelta = "agent_message_delta"
        case agentReasoning = "agent_reasoning"
        case agentReasoningDelta = "agent_reasoning_delta"
        case agentReasoningRawContent = "agent_reasoning_raw_content"
        case agentReasoningRawContentDelta = "agent_reasoning_raw_content_delta"
        case agentReasoningSectionBreak = "agent_reasoning_section_break"
        case sessionConfigured = "session_configured"
        case mcpStartupUpdate = "mcp_startup_update"
        case mcpStartupComplete = "mcp_startup_complete"
        case mcpToolCallBegin = "mcp_tool_call_begin"
        case mcpToolCallEnd = "mcp_tool_call_end"
        case mcpListToolsResponse = "mcp_list_tools_response"
        case webSearchBegin = "web_search_begin"
        case webSearchEnd = "web_search_end"
        case imageGenerationBegin = "image_generation_begin"
        case imageGenerationEnd = "image_generation_end"
        case execCommandBegin = "exec_command_begin"
        case execCommandOutputDelta = "exec_command_output_delta"
        case terminalInteraction = "terminal_interaction"
        case execCommandEnd = "exec_command_end"
        case viewImageToolCall = "view_image_tool_call"
        case execApprovalRequest = "exec_approval_request"
        case elicitationRequest = "elicitation_request"
        case applyPatchApprovalRequest = "apply_patch_approval_request"
        case deprecationNotice = "deprecation_notice"
        case backgroundEvent = "background_event"
        case undoStarted = "undo_started"
        case undoCompleted = "undo_completed"
        case streamError = "stream_error"
        case patchApplyBegin = "patch_apply_begin"
        case patchApplyEnd = "patch_apply_end"
        case turnDiff = "turn_diff"
        case getHistoryEntryResponse = "get_history_entry_response"
        case listSkillsResponse = "list_skills_response"
        case listCustomPromptsResponse = "list_custom_prompts_response"
        case skillsUpdateAvailable = "skills_update_available"
        case planUpdate = "plan_update"
        case turnAborted = "turn_aborted"
        case shutdownComplete = "shutdown_complete"
        case enteredReviewMode = "entered_review_mode"
        case exitedReviewMode = "exited_review_mode"
        case rawResponseItem = "raw_response_item"
        case itemStarted = "item_started"
        case itemCompleted = "item_completed"
        case agentMessageContentDelta = "agent_message_content_delta"
        case reasoningContentDelta = "reasoning_content_delta"
        case reasoningRawContentDelta = "reasoning_raw_content_delta"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(EventType.self, forKey: .type) {
        case .error:
            self = .error(try ErrorEvent(from: decoder))
        case .warning:
            self = .warning(try WarningEvent(from: decoder))
        case .contextCompacted:
            self = .contextCompacted(try ContextCompactedEvent(from: decoder))
        case .taskStarted:
            self = .taskStarted(try TaskStartedEvent(from: decoder))
        case .taskComplete:
            self = .taskComplete(try TaskCompleteEvent(from: decoder))
        case .tokenCount:
            self = .tokenCount(try TokenCountEvent(from: decoder))
        case .agentMessage:
            self = .agentMessage(try AgentMessageEvent(from: decoder))
        case .userMessage:
            self = .userMessage(try UserMessageEvent(from: decoder))
        case .agentMessageDelta:
            self = .agentMessageDelta(try AgentMessageDeltaEvent(from: decoder))
        case .agentReasoning:
            self = .agentReasoning(try AgentReasoningEvent(from: decoder))
        case .agentReasoningDelta:
            self = .agentReasoningDelta(try AgentReasoningDeltaEvent(from: decoder))
        case .agentReasoningRawContent:
            self = .agentReasoningRawContent(try AgentReasoningRawContentEvent(from: decoder))
        case .agentReasoningRawContentDelta:
            self = .agentReasoningRawContentDelta(try AgentReasoningRawContentDeltaEvent(from: decoder))
        case .agentReasoningSectionBreak:
            self = .agentReasoningSectionBreak(try AgentReasoningSectionBreakEvent(from: decoder))
        case .sessionConfigured:
            self = .sessionConfigured(try SessionConfiguredEvent(from: decoder))
        case .mcpStartupUpdate:
            self = .mcpStartupUpdate(try McpStartupUpdateEvent(from: decoder))
        case .mcpStartupComplete:
            self = .mcpStartupComplete(try McpStartupCompleteEvent(from: decoder))
        case .mcpToolCallBegin:
            self = .mcpToolCallBegin(try McpToolCallBeginEvent(from: decoder))
        case .mcpToolCallEnd:
            self = .mcpToolCallEnd(try McpToolCallEndEvent(from: decoder))
        case .mcpListToolsResponse:
            self = .mcpListToolsResponse(try McpListToolsResponseEvent(from: decoder))
        case .webSearchBegin:
            self = .webSearchBegin(try WebSearchBeginEvent(from: decoder))
        case .webSearchEnd:
            self = .webSearchEnd(try WebSearchEndEvent(from: decoder))
        case .imageGenerationBegin:
            self = .imageGenerationBegin(try ImageGenerationBeginEvent(from: decoder))
        case .imageGenerationEnd:
            self = .imageGenerationEnd(try ImageGenerationEndEvent(from: decoder))
        case .execCommandBegin:
            self = .execCommandBegin(try ExecCommandBeginEvent(from: decoder))
        case .execCommandOutputDelta:
            self = .execCommandOutputDelta(try ExecCommandOutputDeltaEvent(from: decoder))
        case .terminalInteraction:
            self = .terminalInteraction(try TerminalInteractionEvent(from: decoder))
        case .execCommandEnd:
            self = .execCommandEnd(try ExecCommandEndEvent(from: decoder))
        case .viewImageToolCall:
            self = .viewImageToolCall(try ViewImageToolCallEvent(from: decoder))
        case .execApprovalRequest:
            self = .execApprovalRequest(try ExecApprovalRequestEvent(from: decoder))
        case .elicitationRequest:
            self = .elicitationRequest(try ElicitationRequestEvent(from: decoder))
        case .applyPatchApprovalRequest:
            self = .applyPatchApprovalRequest(try ApplyPatchApprovalRequestEvent(from: decoder))
        case .deprecationNotice:
            self = .deprecationNotice(try DeprecationNoticeEvent(from: decoder))
        case .backgroundEvent:
            self = .backgroundEvent(try BackgroundEventEvent(from: decoder))
        case .undoStarted:
            self = .undoStarted(try UndoStartedEvent(from: decoder))
        case .undoCompleted:
            self = .undoCompleted(try UndoCompletedEvent(from: decoder))
        case .streamError:
            self = .streamError(try StreamErrorEvent(from: decoder))
        case .patchApplyBegin:
            self = .patchApplyBegin(try PatchApplyBeginEvent(from: decoder))
        case .patchApplyEnd:
            self = .patchApplyEnd(try PatchApplyEndEvent(from: decoder))
        case .turnDiff:
            self = .turnDiff(try TurnDiffEvent(from: decoder))
        case .getHistoryEntryResponse:
            self = .getHistoryEntryResponse(try GetHistoryEntryResponseEvent(from: decoder))
        case .listSkillsResponse:
            self = .listSkillsResponse(try ListSkillsResponseEvent(from: decoder))
        case .listCustomPromptsResponse:
            self = .listCustomPromptsResponse(try ListCustomPromptsResponseEvent(from: decoder))
        case .skillsUpdateAvailable:
            self = .skillsUpdateAvailable
        case .planUpdate:
            self = .planUpdate(try UpdatePlanArguments(from: decoder))
        case .turnAborted:
            self = .turnAborted(try TurnAbortedEvent(from: decoder))
        case .shutdownComplete:
            self = .shutdownComplete
        case .enteredReviewMode:
            self = .enteredReviewMode(try ReviewRequest(from: decoder))
        case .exitedReviewMode:
            self = .exitedReviewMode(try ExitedReviewModeEvent(from: decoder))
        case .rawResponseItem:
            self = .rawResponseItem(try RawResponseItemEvent(from: decoder))
        case .itemStarted:
            self = .itemStarted(try ItemStartedEvent(from: decoder))
        case .itemCompleted:
            self = .itemCompleted(try ItemCompletedEvent(from: decoder))
        case .agentMessageContentDelta:
            self = .agentMessageContentDelta(try AgentMessageContentDeltaEvent(from: decoder))
        case .reasoningContentDelta:
            self = .reasoningContentDelta(try ReasoningContentDeltaEvent(from: decoder))
        case .reasoningRawContentDelta:
            self = .reasoningRawContentDelta(try ReasoningRawContentDeltaEvent(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .error(event):
            try container.encode(EventType.error, forKey: .type)
            try event.encode(to: encoder)
        case let .warning(event):
            try container.encode(EventType.warning, forKey: .type)
            try event.encode(to: encoder)
        case let .contextCompacted(event):
            try container.encode(EventType.contextCompacted, forKey: .type)
            try event.encode(to: encoder)
        case let .taskStarted(event):
            try container.encode(EventType.taskStarted, forKey: .type)
            try event.encode(to: encoder)
        case let .taskComplete(event):
            try container.encode(EventType.taskComplete, forKey: .type)
            try event.encode(to: encoder)
        case let .tokenCount(event):
            try container.encode(EventType.tokenCount, forKey: .type)
            try event.encode(to: encoder)
        case let .agentMessage(event):
            try container.encode(EventType.agentMessage, forKey: .type)
            try event.encode(to: encoder)
        case let .userMessage(event):
            try container.encode(EventType.userMessage, forKey: .type)
            try event.encode(to: encoder)
        case let .agentMessageDelta(event):
            try container.encode(EventType.agentMessageDelta, forKey: .type)
            try event.encode(to: encoder)
        case let .agentReasoning(event):
            try container.encode(EventType.agentReasoning, forKey: .type)
            try event.encode(to: encoder)
        case let .agentReasoningDelta(event):
            try container.encode(EventType.agentReasoningDelta, forKey: .type)
            try event.encode(to: encoder)
        case let .agentReasoningRawContent(event):
            try container.encode(EventType.agentReasoningRawContent, forKey: .type)
            try event.encode(to: encoder)
        case let .agentReasoningRawContentDelta(event):
            try container.encode(EventType.agentReasoningRawContentDelta, forKey: .type)
            try event.encode(to: encoder)
        case let .agentReasoningSectionBreak(event):
            try container.encode(EventType.agentReasoningSectionBreak, forKey: .type)
            try event.encode(to: encoder)
        case let .sessionConfigured(event):
            try container.encode(EventType.sessionConfigured, forKey: .type)
            try event.encode(to: encoder)
        case let .mcpStartupUpdate(event):
            try container.encode(EventType.mcpStartupUpdate, forKey: .type)
            try event.encode(to: encoder)
        case let .mcpStartupComplete(event):
            try container.encode(EventType.mcpStartupComplete, forKey: .type)
            try event.encode(to: encoder)
        case let .mcpToolCallBegin(event):
            try container.encode(EventType.mcpToolCallBegin, forKey: .type)
            try event.encode(to: encoder)
        case let .mcpToolCallEnd(event):
            try container.encode(EventType.mcpToolCallEnd, forKey: .type)
            try event.encode(to: encoder)
        case let .mcpListToolsResponse(event):
            try container.encode(EventType.mcpListToolsResponse, forKey: .type)
            try event.encode(to: encoder)
        case let .webSearchBegin(event):
            try container.encode(EventType.webSearchBegin, forKey: .type)
            try event.encode(to: encoder)
        case let .webSearchEnd(event):
            try container.encode(EventType.webSearchEnd, forKey: .type)
            try event.encode(to: encoder)
        case let .imageGenerationBegin(event):
            try container.encode(EventType.imageGenerationBegin, forKey: .type)
            try event.encode(to: encoder)
        case let .imageGenerationEnd(event):
            try container.encode(EventType.imageGenerationEnd, forKey: .type)
            try event.encode(to: encoder)
        case let .execCommandBegin(event):
            try container.encode(EventType.execCommandBegin, forKey: .type)
            try event.encode(to: encoder)
        case let .execCommandOutputDelta(event):
            try container.encode(EventType.execCommandOutputDelta, forKey: .type)
            try event.encode(to: encoder)
        case let .terminalInteraction(event):
            try container.encode(EventType.terminalInteraction, forKey: .type)
            try event.encode(to: encoder)
        case let .execCommandEnd(event):
            try container.encode(EventType.execCommandEnd, forKey: .type)
            try event.encode(to: encoder)
        case let .viewImageToolCall(event):
            try container.encode(EventType.viewImageToolCall, forKey: .type)
            try event.encode(to: encoder)
        case let .execApprovalRequest(event):
            try container.encode(EventType.execApprovalRequest, forKey: .type)
            try event.encode(to: encoder)
        case let .elicitationRequest(event):
            try container.encode(EventType.elicitationRequest, forKey: .type)
            try event.encode(to: encoder)
        case let .applyPatchApprovalRequest(event):
            try container.encode(EventType.applyPatchApprovalRequest, forKey: .type)
            try event.encode(to: encoder)
        case let .deprecationNotice(event):
            try container.encode(EventType.deprecationNotice, forKey: .type)
            try event.encode(to: encoder)
        case let .backgroundEvent(event):
            try container.encode(EventType.backgroundEvent, forKey: .type)
            try event.encode(to: encoder)
        case let .undoStarted(event):
            try container.encode(EventType.undoStarted, forKey: .type)
            try event.encode(to: encoder)
        case let .undoCompleted(event):
            try container.encode(EventType.undoCompleted, forKey: .type)
            try event.encode(to: encoder)
        case let .streamError(event):
            try container.encode(EventType.streamError, forKey: .type)
            try event.encode(to: encoder)
        case let .patchApplyBegin(event):
            try container.encode(EventType.patchApplyBegin, forKey: .type)
            try event.encode(to: encoder)
        case let .patchApplyEnd(event):
            try container.encode(EventType.patchApplyEnd, forKey: .type)
            try event.encode(to: encoder)
        case let .turnDiff(event):
            try container.encode(EventType.turnDiff, forKey: .type)
            try event.encode(to: encoder)
        case let .getHistoryEntryResponse(event):
            try container.encode(EventType.getHistoryEntryResponse, forKey: .type)
            try event.encode(to: encoder)
        case let .listSkillsResponse(event):
            try container.encode(EventType.listSkillsResponse, forKey: .type)
            try event.encode(to: encoder)
        case let .listCustomPromptsResponse(event):
            try container.encode(EventType.listCustomPromptsResponse, forKey: .type)
            try event.encode(to: encoder)
        case .skillsUpdateAvailable:
            try container.encode(EventType.skillsUpdateAvailable, forKey: .type)
        case let .planUpdate(event):
            try container.encode(EventType.planUpdate, forKey: .type)
            try event.encode(to: encoder)
        case let .turnAborted(event):
            try container.encode(EventType.turnAborted, forKey: .type)
            try event.encode(to: encoder)
        case .shutdownComplete:
            try container.encode(EventType.shutdownComplete, forKey: .type)
        case let .enteredReviewMode(event):
            try container.encode(EventType.enteredReviewMode, forKey: .type)
            try event.encode(to: encoder)
        case let .exitedReviewMode(event):
            try container.encode(EventType.exitedReviewMode, forKey: .type)
            try event.encode(to: encoder)
        case let .rawResponseItem(event):
            try container.encode(EventType.rawResponseItem, forKey: .type)
            try event.encode(to: encoder)
        case let .itemStarted(event):
            try container.encode(EventType.itemStarted, forKey: .type)
            try event.encode(to: encoder)
        case let .itemCompleted(event):
            try container.encode(EventType.itemCompleted, forKey: .type)
            try event.encode(to: encoder)
        case let .agentMessageContentDelta(event):
            try container.encode(EventType.agentMessageContentDelta, forKey: .type)
            try event.encode(to: encoder)
        case let .reasoningContentDelta(event):
            try container.encode(EventType.reasoningContentDelta, forKey: .type)
            try event.encode(to: encoder)
        case let .reasoningRawContentDelta(event):
            try container.encode(EventType.reasoningRawContentDelta, forKey: .type)
            try event.encode(to: encoder)
        }
    }
}
