import Foundation

public enum RolloutEventMessageKind: String, Codable, CaseIterable, Equatable, Sendable {
    case error
    case warning
    case guardianWarning = "guardian_warning"
    case realtimeConversationStarted = "realtime_conversation_started"
    case realtimeConversationRealtime = "realtime_conversation_realtime"
    case realtimeConversationClosed = "realtime_conversation_closed"
    case realtimeConversationSdp = "realtime_conversation_sdp"
    case modelReroute = "model_reroute"
    case modelVerification = "model_verification"
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
    case imageGenerationBegin = "image_generation_begin"
    case imageGenerationEnd = "image_generation_end"
    case execCommandBegin = "exec_command_begin"
    case execCommandOutputDelta = "exec_command_output_delta"
    case terminalInteraction = "terminal_interaction"
    case execCommandEnd = "exec_command_end"
    case viewImageToolCall = "view_image_tool_call"
    case execApprovalRequest = "exec_approval_request"
    case requestPermissions = "request_permissions"
    case requestUserInput = "request_user_input"
    case dynamicToolCallRequest = "dynamic_tool_call_request"
    case dynamicToolCallResponse = "dynamic_tool_call_response"
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
    case guardianAssessment = "guardian_assessment"
    case getHistoryEntryResponse = "get_history_entry_response"
    case mcpListToolsResponse = "mcp_list_tools_response"
    case listCustomPromptsResponse = "list_custom_prompts_response"
    case listSkillsResponse = "list_skills_response"
    case skillsUpdateAvailable = "skills_update_available"
    case planUpdate = "plan_update"
    case turnAborted = "turn_aborted"
    case threadRolledBack = "thread_rolled_back"
    case shutdownComplete = "shutdown_complete"
    case enteredReviewMode = "entered_review_mode"
    case exitedReviewMode = "exited_review_mode"
    case rawResponseItem = "raw_response_item"
    case itemStarted = "item_started"
    case itemCompleted = "item_completed"
    case agentMessageContentDelta = "agent_message_content_delta"
    case reasoningContentDelta = "reasoning_content_delta"
    case reasoningRawContentDelta = "reasoning_raw_content_delta"
    case realtimeConversationListVoicesResponse = "realtime_conversation_list_voices_response"
}

public enum RolloutItem: Equatable, Sendable {
    case sessionMeta
    case responseItem(ResponseItem)
    case compacted
    case turnContext
    case eventMessage(RolloutEventMessageKind)
}

public enum EventPersistenceMode: Equatable, Sendable {
    case limited
    case extended
}

public enum RolloutPolicy {
    public static func eventKind(for event: EventMessage) -> RolloutEventMessageKind {
        switch event {
        case .error:
            return .error
        case .warning:
            return .warning
        case .guardianWarning:
            return .guardianWarning
        case .realtimeConversationStarted:
            return .realtimeConversationStarted
        case .realtimeConversationRealtime:
            return .realtimeConversationRealtime
        case .realtimeConversationClosed:
            return .realtimeConversationClosed
        case .realtimeConversationSdp:
            return .realtimeConversationSdp
        case .modelReroute:
            return .modelReroute
        case .modelVerification:
            return .modelVerification
        case .contextCompacted:
            return .contextCompacted
        case .taskStarted:
            return .taskStarted
        case .taskComplete:
            return .taskComplete
        case .tokenCount:
            return .tokenCount
        case .agentMessage:
            return .agentMessage
        case .userMessage:
            return .userMessage
        case .agentMessageDelta:
            return .agentMessageDelta
        case .agentReasoning:
            return .agentReasoning
        case .agentReasoningDelta:
            return .agentReasoningDelta
        case .agentReasoningRawContent:
            return .agentReasoningRawContent
        case .agentReasoningRawContentDelta:
            return .agentReasoningRawContentDelta
        case .agentReasoningSectionBreak:
            return .agentReasoningSectionBreak
        case .sessionConfigured:
            return .sessionConfigured
        case .mcpStartupUpdate:
            return .mcpStartupUpdate
        case .mcpStartupComplete:
            return .mcpStartupComplete
        case .mcpToolCallBegin:
            return .mcpToolCallBegin
        case .mcpToolCallEnd:
            return .mcpToolCallEnd
        case .mcpListToolsResponse:
            return .mcpListToolsResponse
        case .webSearchBegin:
            return .webSearchBegin
        case .webSearchEnd:
            return .webSearchEnd
        case .imageGenerationBegin:
            return .imageGenerationBegin
        case .imageGenerationEnd:
            return .imageGenerationEnd
        case .execCommandBegin:
            return .execCommandBegin
        case .execCommandOutputDelta:
            return .execCommandOutputDelta
        case .terminalInteraction:
            return .terminalInteraction
        case .execCommandEnd:
            return .execCommandEnd
        case .viewImageToolCall:
            return .viewImageToolCall
        case .execApprovalRequest:
            return .execApprovalRequest
        case .requestPermissions:
            return .requestPermissions
        case .requestUserInput:
            return .requestUserInput
        case .dynamicToolCallRequest:
            return .dynamicToolCallRequest
        case .dynamicToolCallResponse:
            return .dynamicToolCallResponse
        case .elicitationRequest:
            return .elicitationRequest
        case .applyPatchApprovalRequest:
            return .applyPatchApprovalRequest
        case .deprecationNotice:
            return .deprecationNotice
        case .backgroundEvent:
            return .backgroundEvent
        case .undoStarted:
            return .undoStarted
        case .undoCompleted:
            return .undoCompleted
        case .streamError:
            return .streamError
        case .patchApplyBegin:
            return .patchApplyBegin
        case .patchApplyEnd:
            return .patchApplyEnd
        case .turnDiff:
            return .turnDiff
        case .guardianAssessment:
            return .guardianAssessment
        case .getHistoryEntryResponse:
            return .getHistoryEntryResponse
        case .listSkillsResponse:
            return .listSkillsResponse
        case .listCustomPromptsResponse:
            return .listCustomPromptsResponse
        case .skillsUpdateAvailable:
            return .skillsUpdateAvailable
        case .planUpdate:
            return .planUpdate
        case .turnAborted:
            return .turnAborted
        case .threadRolledBack:
            return .threadRolledBack
        case .shutdownComplete:
            return .shutdownComplete
        case .enteredReviewMode:
            return .enteredReviewMode
        case .exitedReviewMode:
            return .exitedReviewMode
        case .rawResponseItem:
            return .rawResponseItem
        case .itemStarted:
            return .itemStarted
        case .itemCompleted:
            return .itemCompleted
        case .agentMessageContentDelta:
            return .agentMessageContentDelta
        case .reasoningContentDelta:
            return .reasoningContentDelta
        case .reasoningRawContentDelta:
            return .reasoningRawContentDelta
        case .realtimeConversationListVoicesResponse:
            return .realtimeConversationListVoicesResponse
        }
    }

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
             .localShellCall,
             .functionCall,
             .functionCallOutput,
             .customToolCall,
             .customToolCallOutput,
             .toolSearchCall,
             .toolSearchOutput,
             .webSearchCall,
             .imageGenerationCall,
             .compaction,
             .contextCompaction,
             .knownPersisted:
            return true
        case .ghostSnapshot,
             .other:
            return false
        }
    }

    public static func shouldPersistResponseItemForMemories(_ item: ResponseItem) -> Bool {
        switch item {
        case let .message(_, role, _, _):
            return role != "developer"
        case .localShellCall,
             .functionCall,
             .functionCallOutput,
             .customToolCall,
             .customToolCallOutput,
             .toolSearchCall,
             .toolSearchOutput,
             .webSearchCall:
            return true
        case let .knownPersisted(type):
            return [
                "local_shell_call",
                "function_call",
                "function_call_output",
                "custom_tool_call",
                "custom_tool_call_output",
                "tool_search_call",
                "tool_search_output",
                "web_search_call",
            ].contains(type)
        case .reasoning,
             .imageGenerationCall,
             .compaction,
             .contextCompaction,
             .ghostSnapshot,
             .other:
            return false
        }
    }

    public static func shouldPersistEventMessage(
        _ event: RolloutEventMessageKind,
        mode: EventPersistenceMode = .limited
    ) -> Bool {
        switch (eventMessagePersistenceMode(event), mode) {
        case (.limited?, _),
             (.extended?, .extended):
            return true
        case (.extended?, .limited),
             (nil, _):
            return false
        }
    }

    public static func eventMessagePersistenceMode(
        _ event: RolloutEventMessageKind
    ) -> EventPersistenceMode? {
        switch event {
        case .userMessage,
             .agentMessage,
             .agentReasoning,
             .agentReasoningRawContent,
             .patchApplyEnd,
             .tokenCount,
             .contextCompacted,
             .enteredReviewMode,
             .exitedReviewMode,
             .mcpToolCallEnd,
             .undoCompleted,
             .turnAborted,
             .taskStarted,
             .taskComplete,
             .threadRolledBack,
             .webSearchEnd,
             .imageGenerationEnd:
            return .limited
        case .error,
             .guardianAssessment,
             .execCommandEnd,
             .viewImageToolCall,
             .dynamicToolCallResponse:
            return .extended
        case .warning,
             .guardianWarning,
             .realtimeConversationStarted,
             .realtimeConversationRealtime,
             .realtimeConversationClosed,
             .realtimeConversationSdp,
             .modelReroute,
             .modelVerification,
             .agentMessageDelta,
             .agentReasoningDelta,
             .agentReasoningRawContentDelta,
             .agentReasoningSectionBreak,
             .rawResponseItem,
             .sessionConfigured,
             .mcpToolCallBegin,
             .webSearchBegin,
             .imageGenerationBegin,
             .execCommandBegin,
             .terminalInteraction,
             .execCommandOutputDelta,
             .execApprovalRequest,
             .requestPermissions,
             .requestUserInput,
             .dynamicToolCallRequest,
             .elicitationRequest,
             .applyPatchApprovalRequest,
             .backgroundEvent,
             .streamError,
             .patchApplyBegin,
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
             .deprecationNotice,
             .itemStarted,
             .itemCompleted,
             .agentMessageContentDelta,
             .reasoningContentDelta,
             .reasoningRawContentDelta,
             .realtimeConversationListVoicesResponse,
             .skillsUpdateAvailable:
            return nil
        }
    }

    public static func shouldPersistEventMessage(
        _ event: EventMessage,
        mode: EventPersistenceMode = .limited
    ) -> Bool {
        if case let .itemCompleted(itemCompletedEvent) = event,
           case .plan = itemCompletedEvent.item {
            return true
        }
        return shouldPersistEventMessage(eventKind(for: event), mode: mode)
    }
}
