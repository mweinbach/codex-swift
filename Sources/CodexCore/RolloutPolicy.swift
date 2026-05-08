import Foundation

public enum RolloutEventMessageKind: String, Codable, CaseIterable, Equatable, Sendable {
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
    case webSearchBegin = "web_search_begin"
    case webSearchEnd = "web_search_end"
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
    case mcpListToolsResponse = "mcp_list_tools_response"
    case listCustomPromptsResponse = "list_custom_prompts_response"
    case listSkillsResponse = "list_skills_response"
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

public enum RolloutItem: Equatable, Sendable {
    case sessionMeta
    case responseItem(ResponseItem)
    case compacted
    case turnContext
    case eventMessage(RolloutEventMessageKind)
}

public enum RolloutPolicy {
    public static func isPersistedResponseItem(_ item: RolloutItem) -> Bool {
        switch item {
        case let .responseItem(responseItem):
            return shouldPersistResponseItem(responseItem)
        case let .eventMessage(event):
            return shouldPersistEventMessage(event)
        case .sessionMeta, .compacted, .turnContext:
            return true
        }
    }

    public static func shouldPersistResponseItem(_ item: ResponseItem) -> Bool {
        switch item {
        case .message,
             .reasoning,
             .webSearchCall,
             .compaction,
             .knownPersisted:
            return true
        case .other:
            return false
        }
    }

    public static func shouldPersistEventMessage(_ event: RolloutEventMessageKind) -> Bool {
        switch event {
        case .userMessage,
             .agentMessage,
             .agentReasoning,
             .agentReasoningRawContent,
             .tokenCount,
             .contextCompacted,
             .enteredReviewMode,
             .exitedReviewMode,
             .undoCompleted,
             .turnAborted:
            return true
        case .error,
             .warning,
             .taskStarted,
             .taskComplete,
             .agentMessageDelta,
             .agentReasoningDelta,
             .agentReasoningRawContentDelta,
             .agentReasoningSectionBreak,
             .rawResponseItem,
             .sessionConfigured,
             .mcpToolCallBegin,
             .mcpToolCallEnd,
             .webSearchBegin,
             .webSearchEnd,
             .execCommandBegin,
             .terminalInteraction,
             .execCommandOutputDelta,
             .execCommandEnd,
             .execApprovalRequest,
             .elicitationRequest,
             .applyPatchApprovalRequest,
             .backgroundEvent,
             .streamError,
             .patchApplyBegin,
             .patchApplyEnd,
             .turnDiff,
             .getHistoryEntryResponse,
             .undoStarted,
             .mcpListToolsResponse,
             .mcpStartupUpdate,
             .mcpStartupComplete,
             .listCustomPromptsResponse,
             .listSkillsResponse,
             .planUpdate,
             .shutdownComplete,
             .viewImageToolCall,
             .deprecationNotice,
             .itemStarted,
             .itemCompleted,
             .agentMessageContentDelta,
             .reasoningContentDelta,
             .reasoningRawContentDelta,
             .skillsUpdateAvailable:
            return false
        }
    }
}
