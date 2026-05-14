import Foundation

public enum AppServerRpcTransport: String, Codable, Equatable, Sendable {
    case stdio
    case websocket
    case inProcess = "in_process"
}

public struct CodexAppServerClientMetadata: Equatable, Codable, Sendable {
    public let productClientID: String
    public let clientName: String?
    public let clientVersion: String?
    public let rpcTransport: AppServerRpcTransport
    public let experimentalAPIEnabled: Bool?

    public init(
        productClientID: String,
        clientName: String? = nil,
        clientVersion: String? = nil,
        rpcTransport: AppServerRpcTransport,
        experimentalAPIEnabled: Bool? = nil
    ) {
        self.productClientID = productClientID
        self.clientName = clientName
        self.clientVersion = clientVersion
        self.rpcTransport = rpcTransport
        self.experimentalAPIEnabled = experimentalAPIEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case productClientID = "product_client_id"
        case clientName = "client_name"
        case clientVersion = "client_version"
        case rpcTransport = "rpc_transport"
        case experimentalAPIEnabled = "experimental_api_enabled"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(productClientID, forKey: .productClientID)
        try container.encodeNilOrValue(clientName, forKey: .clientName)
        try container.encodeNilOrValue(clientVersion, forKey: .clientVersion)
        try container.encode(rpcTransport, forKey: .rpcTransport)
        try container.encodeNilOrValue(experimentalAPIEnabled, forKey: .experimentalAPIEnabled)
    }
}

public struct CodexRuntimeMetadata: Equatable, Codable, Sendable {
    public let codexRSVersion: String
    public let runtimeOS: String
    public let runtimeOSVersion: String
    public let runtimeArch: String

    public init(
        codexRSVersion: String,
        runtimeOS: String,
        runtimeOSVersion: String,
        runtimeArch: String
    ) {
        self.codexRSVersion = codexRSVersion
        self.runtimeOS = runtimeOS
        self.runtimeOSVersion = runtimeOSVersion
        self.runtimeArch = runtimeArch
    }

    private enum CodingKeys: String, CodingKey {
        case codexRSVersion = "codex_rs_version"
        case runtimeOS = "runtime_os"
        case runtimeOSVersion = "runtime_os_version"
        case runtimeArch = "runtime_arch"
    }
}

public enum ReviewSubjectKind: String, Codable, Equatable, Sendable {
    case commandExecution = "command_execution"
    case fileChange = "file_change"
    case mcpToolCall = "mcp_tool_call"
    case permissions
    case networkAccess = "network_access"
}

public enum ReviewAnalyticsReviewer: String, Codable, Equatable, Sendable {
    case guardian
    case user
}

public enum ReviewTrigger: String, Codable, Equatable, Sendable {
    case initial
    case sandboxDenial = "sandbox_denial"
    case networkPolicyDenial = "network_policy_denial"
    case execveIntercept = "execve_intercept"
}

public enum ReviewStatus: String, Codable, Equatable, Sendable {
    case approved
    case denied
    case aborted
    case timedOut = "timed_out"
}

public enum ReviewResolution: String, Codable, Equatable, Sendable {
    case none
    case sessionApproval = "session_approval"
    case execPolicyAmendment = "exec_policy_amendment"
    case networkPolicyAmendment = "network_policy_amendment"
}

public enum ToolItemFinalApprovalOutcome: String, Codable, Equatable, Sendable {
    case unknown
    case notNeeded = "not_needed"
    case configAllowed = "config_allowed"
    case policyForbidden = "policy_forbidden"
    case guardianApproved = "guardian_approved"
    case guardianDenied = "guardian_denied"
    case guardianAborted = "guardian_aborted"
    case userApproved = "user_approved"
    case userApprovedForSession = "user_approved_for_session"
    case userDenied = "user_denied"
    case userAborted = "user_aborted"
}

public enum ToolItemTerminalStatus: String, Codable, Equatable, Sendable {
    case completed
    case failed
    case rejected
    case interrupted
}

public enum ToolItemFailureKind: String, Codable, Equatable, Sendable {
    case toolError = "tool_error"
    case approvalDenied = "approval_denied"
    case approvalAborted = "approval_aborted"
    case sandboxDenied = "sandbox_denied"
    case policyForbidden = "policy_forbidden"
}

public enum CommandExecutionSource: String, Codable, Equatable, Sendable {
    case agent
    case userShell = "user_shell"
    case unifiedExecStartup = "unified_exec_startup"
    case unifiedExecInteraction = "unified_exec_interaction"

    public init(_ source: AppServerCommandExecutionSource) {
        switch source {
        case .agent:
            self = .agent
        case .userShell:
            self = .userShell
        case .unifiedExecStartup:
            self = .unifiedExecStartup
        case .unifiedExecInteraction:
            self = .unifiedExecInteraction
        }
    }
}

public enum CompactionTrigger: String, Codable, Equatable, Sendable {
    case manual
    case auto
}

public enum CompactionReason: String, Codable, Equatable, Sendable {
    case userRequested = "user_requested"
    case contextLimit = "context_limit"
    case modelDownshift = "model_downshift"
}

public enum CompactionImplementation: String, Codable, Equatable, Sendable {
    case responses
    case responsesCompact = "responses_compact"
}

public enum CompactionPhase: String, Codable, Equatable, Sendable {
    case standaloneTurn = "standalone_turn"
    case preTurn = "pre_turn"
    case midTurn = "mid_turn"
}

public enum CompactionStrategy: String, Codable, Equatable, Sendable {
    case memento
    case prefixCompaction = "prefix_compaction"
}

public enum CompactionStatus: String, Codable, Equatable, Sendable {
    case completed
    case failed
    case interrupted
}

public struct CodexCompactionEventParams: Equatable, Encodable, Sendable {
    public let threadID: String
    public let turnID: String
    public let appServerClient: CodexAppServerClientMetadata
    public let runtime: CodexRuntimeMetadata
    public let threadSource: ThreadSource?
    public let subagentSource: String?
    public let parentThreadID: String?
    public let trigger: CompactionTrigger
    public let reason: CompactionReason
    public let implementation: CompactionImplementation
    public let phase: CompactionPhase
    public let strategy: CompactionStrategy
    public let status: CompactionStatus
    public let error: String?
    public let activeContextTokensBefore: Int64
    public let activeContextTokensAfter: Int64
    public let startedAt: UInt64
    public let completedAt: UInt64
    public let durationMilliseconds: UInt64?

    public init(
        threadID: String,
        turnID: String,
        appServerClient: CodexAppServerClientMetadata,
        runtime: CodexRuntimeMetadata,
        threadSource: ThreadSource? = nil,
        subagentSource: String? = nil,
        parentThreadID: String? = nil,
        trigger: CompactionTrigger,
        reason: CompactionReason,
        implementation: CompactionImplementation,
        phase: CompactionPhase,
        strategy: CompactionStrategy,
        status: CompactionStatus,
        error: String? = nil,
        activeContextTokensBefore: Int64,
        activeContextTokensAfter: Int64,
        startedAt: UInt64,
        completedAt: UInt64,
        durationMilliseconds: UInt64? = nil
    ) {
        self.threadID = threadID
        self.turnID = turnID
        self.appServerClient = appServerClient
        self.runtime = runtime
        self.threadSource = threadSource
        self.subagentSource = subagentSource
        self.parentThreadID = parentThreadID
        self.trigger = trigger
        self.reason = reason
        self.implementation = implementation
        self.phase = phase
        self.strategy = strategy
        self.status = status
        self.error = error
        self.activeContextTokensBefore = activeContextTokensBefore
        self.activeContextTokensAfter = activeContextTokensAfter
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.durationMilliseconds = durationMilliseconds
    }

    private enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case turnID = "turn_id"
        case appServerClient = "app_server_client"
        case runtime
        case threadSource = "thread_source"
        case subagentSource = "subagent_source"
        case parentThreadID = "parent_thread_id"
        case trigger
        case reason
        case implementation
        case phase
        case strategy
        case status
        case error
        case activeContextTokensBefore = "active_context_tokens_before"
        case activeContextTokensAfter = "active_context_tokens_after"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case durationMilliseconds = "duration_ms"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(threadID, forKey: .threadID)
        try container.encode(turnID, forKey: .turnID)
        try container.encode(appServerClient, forKey: .appServerClient)
        try container.encode(runtime, forKey: .runtime)
        try container.encodeNilOrValue(threadSource, forKey: .threadSource)
        try container.encodeNilOrValue(subagentSource, forKey: .subagentSource)
        try container.encodeNilOrValue(parentThreadID, forKey: .parentThreadID)
        try container.encode(trigger, forKey: .trigger)
        try container.encode(reason, forKey: .reason)
        try container.encode(implementation, forKey: .implementation)
        try container.encode(phase, forKey: .phase)
        try container.encode(strategy, forKey: .strategy)
        try container.encode(status, forKey: .status)
        try container.encodeNilOrValue(error, forKey: .error)
        try container.encode(activeContextTokensBefore, forKey: .activeContextTokensBefore)
        try container.encode(activeContextTokensAfter, forKey: .activeContextTokensAfter)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(completedAt, forKey: .completedAt)
        try container.encodeNilOrValue(durationMilliseconds, forKey: .durationMilliseconds)
    }
}

public struct CodexCompactionEventRequest: Equatable, Encodable, Sendable {
    public let eventType: String
    public let eventParams: CodexCompactionEventParams

    public init(eventType: String, eventParams: CodexCompactionEventParams) {
        self.eventType = eventType
        self.eventParams = eventParams
    }

    private enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case eventParams = "event_params"
    }
}

public struct CodexToolItemEventBase: Equatable, Encodable, Sendable {
    public let threadID: String
    public let turnID: String
    public let itemID: String
    public let appServerClient: CodexAppServerClientMetadata
    public let runtime: CodexRuntimeMetadata
    public let threadSource: ThreadSource?
    public let subagentSource: String?
    public let parentThreadID: String?
    public let toolName: String
    public let startedAtMilliseconds: UInt64
    public let completedAtMilliseconds: UInt64
    public let durationMilliseconds: UInt64?
    public let executionDurationMilliseconds: UInt64?
    public let reviewCount: UInt64
    public let guardianReviewCount: UInt64
    public let userReviewCount: UInt64
    public let finalApprovalOutcome: ToolItemFinalApprovalOutcome
    public let terminalStatus: ToolItemTerminalStatus
    public let failureKind: ToolItemFailureKind?
    public let requestedAdditionalPermissions: Bool
    public let requestedNetworkAccess: Bool

    public init(
        threadID: String,
        turnID: String,
        itemID: String,
        appServerClient: CodexAppServerClientMetadata,
        runtime: CodexRuntimeMetadata,
        threadSource: ThreadSource? = nil,
        subagentSource: String? = nil,
        parentThreadID: String? = nil,
        toolName: String,
        startedAtMilliseconds: UInt64,
        completedAtMilliseconds: UInt64,
        durationMilliseconds: UInt64? = nil,
        executionDurationMilliseconds: UInt64? = nil,
        reviewCount: UInt64,
        guardianReviewCount: UInt64,
        userReviewCount: UInt64,
        finalApprovalOutcome: ToolItemFinalApprovalOutcome,
        terminalStatus: ToolItemTerminalStatus,
        failureKind: ToolItemFailureKind? = nil,
        requestedAdditionalPermissions: Bool,
        requestedNetworkAccess: Bool
    ) {
        self.threadID = threadID
        self.turnID = turnID
        self.itemID = itemID
        self.appServerClient = appServerClient
        self.runtime = runtime
        self.threadSource = threadSource
        self.subagentSource = subagentSource
        self.parentThreadID = parentThreadID
        self.toolName = toolName
        self.startedAtMilliseconds = startedAtMilliseconds
        self.completedAtMilliseconds = completedAtMilliseconds
        self.durationMilliseconds = durationMilliseconds
        self.executionDurationMilliseconds = executionDurationMilliseconds
        self.reviewCount = reviewCount
        self.guardianReviewCount = guardianReviewCount
        self.userReviewCount = userReviewCount
        self.finalApprovalOutcome = finalApprovalOutcome
        self.terminalStatus = terminalStatus
        self.failureKind = failureKind
        self.requestedAdditionalPermissions = requestedAdditionalPermissions
        self.requestedNetworkAccess = requestedNetworkAccess
    }

    private enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case turnID = "turn_id"
        case itemID = "item_id"
        case appServerClient = "app_server_client"
        case runtime
        case threadSource = "thread_source"
        case subagentSource = "subagent_source"
        case parentThreadID = "parent_thread_id"
        case toolName = "tool_name"
        case startedAtMilliseconds = "started_at_ms"
        case completedAtMilliseconds = "completed_at_ms"
        case durationMilliseconds = "duration_ms"
        case executionDurationMilliseconds = "execution_duration_ms"
        case reviewCount = "review_count"
        case guardianReviewCount = "guardian_review_count"
        case userReviewCount = "user_review_count"
        case finalApprovalOutcome = "final_approval_outcome"
        case terminalStatus = "terminal_status"
        case failureKind = "failure_kind"
        case requestedAdditionalPermissions = "requested_additional_permissions"
        case requestedNetworkAccess = "requested_network_access"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(threadID, forKey: .threadID)
        try container.encode(turnID, forKey: .turnID)
        try container.encode(itemID, forKey: .itemID)
        try container.encode(appServerClient, forKey: .appServerClient)
        try container.encode(runtime, forKey: .runtime)
        try container.encodeNilOrValue(threadSource, forKey: .threadSource)
        try container.encodeNilOrValue(subagentSource, forKey: .subagentSource)
        try container.encodeNilOrValue(parentThreadID, forKey: .parentThreadID)
        try container.encode(toolName, forKey: .toolName)
        try container.encode(startedAtMilliseconds, forKey: .startedAtMilliseconds)
        try container.encode(completedAtMilliseconds, forKey: .completedAtMilliseconds)
        try container.encodeNilOrValue(durationMilliseconds, forKey: .durationMilliseconds)
        try container.encodeNilOrValue(executionDurationMilliseconds, forKey: .executionDurationMilliseconds)
        try container.encode(reviewCount, forKey: .reviewCount)
        try container.encode(guardianReviewCount, forKey: .guardianReviewCount)
        try container.encode(userReviewCount, forKey: .userReviewCount)
        try container.encode(finalApprovalOutcome, forKey: .finalApprovalOutcome)
        try container.encode(terminalStatus, forKey: .terminalStatus)
        try container.encodeNilOrValue(failureKind, forKey: .failureKind)
        try container.encode(requestedAdditionalPermissions, forKey: .requestedAdditionalPermissions)
        try container.encode(requestedNetworkAccess, forKey: .requestedNetworkAccess)
    }
}

public struct CodexCommandActionCounts: Equatable, Sendable {
    public let total: UInt64
    public let read: UInt64
    public let listFiles: UInt64
    public let search: UInt64
    public let unknown: UInt64

    public init(total: UInt64, read: UInt64, listFiles: UInt64, search: UInt64, unknown: UInt64) {
        self.total = total
        self.read = read
        self.listFiles = listFiles
        self.search = search
        self.unknown = unknown
    }

    public init(actions: [AppServerProtocol.CommandAction]) {
        var read: UInt64 = 0
        var listFiles: UInt64 = 0
        var search: UInt64 = 0
        var unknown: UInt64 = 0

        for action in actions {
            switch action {
            case .read:
                read += 1
            case .listFiles:
                listFiles += 1
            case .search:
                search += 1
            case .unknown:
                unknown += 1
            }
        }

        self.init(
            total: UInt64(actions.count),
            read: read,
            listFiles: listFiles,
            search: search,
            unknown: unknown
        )
    }
}

public struct CodexCommandExecutionEventParams: Equatable, Encodable, Sendable {
    public let base: CodexToolItemEventBase
    public let commandExecutionSource: CommandExecutionSource
    public let exitCode: Int32?
    public let commandActionCounts: CodexCommandActionCounts

    public init(
        base: CodexToolItemEventBase,
        commandExecutionSource: CommandExecutionSource,
        exitCode: Int32? = nil,
        commandActionCounts: CodexCommandActionCounts
    ) {
        self.base = base
        self.commandExecutionSource = commandExecutionSource
        self.exitCode = exitCode
        self.commandActionCounts = commandActionCounts
    }

    private enum CodingKeys: String, CodingKey {
        case commandExecutionSource = "command_execution_source"
        case exitCode = "exit_code"
        case commandTotalActionCount = "command_total_action_count"
        case commandReadActionCount = "command_read_action_count"
        case commandListFilesActionCount = "command_list_files_action_count"
        case commandSearchActionCount = "command_search_action_count"
        case commandUnknownActionCount = "command_unknown_action_count"
    }

    public func encode(to encoder: Encoder) throws {
        try base.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(commandExecutionSource, forKey: .commandExecutionSource)
        try container.encodeNilOrValue(exitCode, forKey: .exitCode)
        try container.encode(commandActionCounts.total, forKey: .commandTotalActionCount)
        try container.encode(commandActionCounts.read, forKey: .commandReadActionCount)
        try container.encode(commandActionCounts.listFiles, forKey: .commandListFilesActionCount)
        try container.encode(commandActionCounts.search, forKey: .commandSearchActionCount)
        try container.encode(commandActionCounts.unknown, forKey: .commandUnknownActionCount)
    }
}

public struct CodexCommandExecutionEventRequest: Equatable, Encodable, Sendable {
    public let eventType: String
    public let eventParams: CodexCommandExecutionEventParams

    public init(eventType: String, eventParams: CodexCommandExecutionEventParams) {
        self.eventType = eventType
        self.eventParams = eventParams
    }

    private enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case eventParams = "event_params"
    }
}

public struct CodexFileChangeCounts: Equatable, Sendable {
    public let total: UInt64
    public let add: UInt64
    public let update: UInt64
    public let delete: UInt64
    public let move: UInt64

    public init(total: UInt64, add: UInt64, update: UInt64, delete: UInt64, move: UInt64) {
        self.total = total
        self.add = add
        self.update = update
        self.delete = delete
        self.move = move
    }

    public init(changes: [AppServerFileUpdateChange]) {
        var add: UInt64 = 0
        var update: UInt64 = 0
        var delete: UInt64 = 0
        var move: UInt64 = 0

        for change in changes {
            switch change.kind {
            case .add:
                add += 1
            case .delete:
                delete += 1
            case .update(movePath: .some):
                move += 1
            case .update(movePath: .none):
                update += 1
            }
        }

        self.init(total: UInt64(changes.count), add: add, update: update, delete: delete, move: move)
    }
}

public struct CodexFileChangeEventParams: Equatable, Encodable, Sendable {
    public let base: CodexToolItemEventBase
    public let fileChangeCounts: CodexFileChangeCounts

    public init(base: CodexToolItemEventBase, fileChangeCounts: CodexFileChangeCounts) {
        self.base = base
        self.fileChangeCounts = fileChangeCounts
    }

    private enum CodingKeys: String, CodingKey {
        case fileChangeCount = "file_change_count"
        case fileAddCount = "file_add_count"
        case fileUpdateCount = "file_update_count"
        case fileDeleteCount = "file_delete_count"
        case fileMoveCount = "file_move_count"
    }

    public func encode(to encoder: Encoder) throws {
        try base.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fileChangeCounts.total, forKey: .fileChangeCount)
        try container.encode(fileChangeCounts.add, forKey: .fileAddCount)
        try container.encode(fileChangeCounts.update, forKey: .fileUpdateCount)
        try container.encode(fileChangeCounts.delete, forKey: .fileDeleteCount)
        try container.encode(fileChangeCounts.move, forKey: .fileMoveCount)
    }
}

public struct CodexFileChangeEventRequest: Equatable, Encodable, Sendable {
    public let eventType: String
    public let eventParams: CodexFileChangeEventParams

    public init(eventType: String, eventParams: CodexFileChangeEventParams) {
        self.eventType = eventType
        self.eventParams = eventParams
    }

    private enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case eventParams = "event_params"
    }
}

public struct CodexMcpToolCallEventParams: Equatable, Encodable, Sendable {
    public let base: CodexToolItemEventBase
    public let mcpServerName: String
    public let mcpToolName: String
    public let mcpErrorPresent: Bool

    public init(
        base: CodexToolItemEventBase,
        mcpServerName: String,
        mcpToolName: String,
        mcpErrorPresent: Bool
    ) {
        self.base = base
        self.mcpServerName = mcpServerName
        self.mcpToolName = mcpToolName
        self.mcpErrorPresent = mcpErrorPresent
    }

    private enum CodingKeys: String, CodingKey {
        case mcpServerName = "mcp_server_name"
        case mcpToolName = "mcp_tool_name"
        case mcpErrorPresent = "mcp_error_present"
    }

    public func encode(to encoder: Encoder) throws {
        try base.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mcpServerName, forKey: .mcpServerName)
        try container.encode(mcpToolName, forKey: .mcpToolName)
        try container.encode(mcpErrorPresent, forKey: .mcpErrorPresent)
    }
}

public struct CodexMcpToolCallEventRequest: Equatable, Encodable, Sendable {
    public let eventType: String
    public let eventParams: CodexMcpToolCallEventParams

    public init(eventType: String, eventParams: CodexMcpToolCallEventParams) {
        self.eventType = eventType
        self.eventParams = eventParams
    }

    private enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case eventParams = "event_params"
    }
}

public struct CodexDynamicToolCallContentCounts: Equatable, Sendable {
    public let total: UInt64
    public let text: UInt64
    public let image: UInt64

    public init(total: UInt64, text: UInt64, image: UInt64) {
        self.total = total
        self.text = text
        self.image = image
    }

    public init(contentItems: [DynamicToolCallOutputContentItem]) {
        var text: UInt64 = 0
        var image: UInt64 = 0

        for item in contentItems {
            switch item {
            case .text:
                text += 1
            case .imageURL:
                image += 1
            }
        }

        self.init(total: UInt64(contentItems.count), text: text, image: image)
    }
}

public struct CodexDynamicToolCallEventParams: Equatable, Encodable, Sendable {
    public let base: CodexToolItemEventBase
    public let dynamicToolName: String
    public let success: Bool?
    public let outputContentItemCount: UInt64?
    public let outputTextItemCount: UInt64?
    public let outputImageItemCount: UInt64?

    public init(
        base: CodexToolItemEventBase,
        dynamicToolName: String,
        success: Bool? = nil,
        outputContentItemCount: UInt64? = nil,
        outputTextItemCount: UInt64? = nil,
        outputImageItemCount: UInt64? = nil
    ) {
        self.base = base
        self.dynamicToolName = dynamicToolName
        self.success = success
        self.outputContentItemCount = outputContentItemCount
        self.outputTextItemCount = outputTextItemCount
        self.outputImageItemCount = outputImageItemCount
    }

    public init(
        base: CodexToolItemEventBase,
        dynamicToolName: String,
        success: Bool? = nil,
        contentCounts: CodexDynamicToolCallContentCounts?
    ) {
        self.init(
            base: base,
            dynamicToolName: dynamicToolName,
            success: success,
            outputContentItemCount: contentCounts?.total,
            outputTextItemCount: contentCounts?.text,
            outputImageItemCount: contentCounts?.image
        )
    }

    private enum CodingKeys: String, CodingKey {
        case dynamicToolName = "dynamic_tool_name"
        case success
        case outputContentItemCount = "output_content_item_count"
        case outputTextItemCount = "output_text_item_count"
        case outputImageItemCount = "output_image_item_count"
    }

    public func encode(to encoder: Encoder) throws {
        try base.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dynamicToolName, forKey: .dynamicToolName)
        try container.encodeNilOrValue(success, forKey: .success)
        try container.encodeNilOrValue(outputContentItemCount, forKey: .outputContentItemCount)
        try container.encodeNilOrValue(outputTextItemCount, forKey: .outputTextItemCount)
        try container.encodeNilOrValue(outputImageItemCount, forKey: .outputImageItemCount)
    }
}

public struct CodexDynamicToolCallEventRequest: Equatable, Encodable, Sendable {
    public let eventType: String
    public let eventParams: CodexDynamicToolCallEventParams

    public init(eventType: String, eventParams: CodexDynamicToolCallEventParams) {
        self.eventType = eventType
        self.eventParams = eventParams
    }

    private enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case eventParams = "event_params"
    }
}

public struct CodexCollabAgentStateCounts: Equatable, Sendable {
    public let total: UInt64
    public let completed: UInt64
    public let failed: UInt64

    public init(total: UInt64, completed: UInt64, failed: UInt64) {
        self.total = total
        self.completed = completed
        self.failed = failed
    }

    public init(states: [String: AppServerCollabAgentState]) {
        var completed: UInt64 = 0
        var failed: UInt64 = 0

        for state in states.values {
            switch state.status {
            case .completed:
                completed += 1
            case .errored, .shutdown, .notFound:
                failed += 1
            case .pendingInit, .running, .interrupted:
                break
            }
        }

        self.init(total: UInt64(states.count), completed: completed, failed: failed)
    }
}

public struct CodexCollabAgentToolCallEventParams: Equatable, Encodable, Sendable {
    public let base: CodexToolItemEventBase
    public let senderThreadID: String
    public let receiverThreadCount: UInt64
    public let receiverThreadIDs: [String]?
    public let requestedModel: String?
    public let requestedReasoningEffort: String?
    public let agentStateCount: UInt64?
    public let completedAgentCount: UInt64?
    public let failedAgentCount: UInt64?

    public init(
        base: CodexToolItemEventBase,
        senderThreadID: String,
        receiverThreadCount: UInt64,
        receiverThreadIDs: [String]? = nil,
        requestedModel: String? = nil,
        requestedReasoningEffort: String? = nil,
        agentStateCount: UInt64? = nil,
        completedAgentCount: UInt64? = nil,
        failedAgentCount: UInt64? = nil
    ) {
        self.base = base
        self.senderThreadID = senderThreadID
        self.receiverThreadCount = receiverThreadCount
        self.receiverThreadIDs = receiverThreadIDs
        self.requestedModel = requestedModel
        self.requestedReasoningEffort = requestedReasoningEffort
        self.agentStateCount = agentStateCount
        self.completedAgentCount = completedAgentCount
        self.failedAgentCount = failedAgentCount
    }

    public init(
        base: CodexToolItemEventBase,
        senderThreadID: String,
        receiverThreadIDs: [String],
        requestedModel: String? = nil,
        requestedReasoningEffort: String? = nil,
        stateCounts: CodexCollabAgentStateCounts
    ) {
        self.init(
            base: base,
            senderThreadID: senderThreadID,
            receiverThreadCount: UInt64(receiverThreadIDs.count),
            receiverThreadIDs: receiverThreadIDs,
            requestedModel: requestedModel,
            requestedReasoningEffort: requestedReasoningEffort,
            agentStateCount: stateCounts.total,
            completedAgentCount: stateCounts.completed,
            failedAgentCount: stateCounts.failed
        )
    }

    private enum CodingKeys: String, CodingKey {
        case senderThreadID = "sender_thread_id"
        case receiverThreadCount = "receiver_thread_count"
        case receiverThreadIDs = "receiver_thread_ids"
        case requestedModel = "requested_model"
        case requestedReasoningEffort = "requested_reasoning_effort"
        case agentStateCount = "agent_state_count"
        case completedAgentCount = "completed_agent_count"
        case failedAgentCount = "failed_agent_count"
    }

    public func encode(to encoder: Encoder) throws {
        try base.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(senderThreadID, forKey: .senderThreadID)
        try container.encode(receiverThreadCount, forKey: .receiverThreadCount)
        try container.encodeNilOrValue(receiverThreadIDs, forKey: .receiverThreadIDs)
        try container.encodeNilOrValue(requestedModel, forKey: .requestedModel)
        try container.encodeNilOrValue(requestedReasoningEffort, forKey: .requestedReasoningEffort)
        try container.encodeNilOrValue(agentStateCount, forKey: .agentStateCount)
        try container.encodeNilOrValue(completedAgentCount, forKey: .completedAgentCount)
        try container.encodeNilOrValue(failedAgentCount, forKey: .failedAgentCount)
    }
}

public struct CodexCollabAgentToolCallEventRequest: Equatable, Encodable, Sendable {
    public let eventType: String
    public let eventParams: CodexCollabAgentToolCallEventParams

    public init(eventType: String, eventParams: CodexCollabAgentToolCallEventParams) {
        self.eventType = eventType
        self.eventParams = eventParams
    }

    private enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case eventParams = "event_params"
    }
}

public enum WebSearchActionKind: String, Codable, Equatable, Sendable {
    case search
    case openPage = "open_page"
    case findInPage = "find_in_page"
    case other

    public init(_ action: AppServerWebSearchAction) {
        switch action {
        case .search:
            self = .search
        case .openPage:
            self = .openPage
        case .findInPage:
            self = .findInPage
        case .other:
            self = .other
        }
    }
}

public struct CodexWebSearchEventParams: Equatable, Encodable, Sendable {
    public let base: CodexToolItemEventBase
    public let webSearchAction: WebSearchActionKind?
    public let queryPresent: Bool
    public let queryCount: UInt64?

    public init(
        base: CodexToolItemEventBase,
        webSearchAction: WebSearchActionKind? = nil,
        queryPresent: Bool,
        queryCount: UInt64? = nil
    ) {
        self.base = base
        self.webSearchAction = webSearchAction
        self.queryPresent = queryPresent
        self.queryCount = queryCount
    }

    private enum CodingKeys: String, CodingKey {
        case webSearchAction = "web_search_action"
        case queryPresent = "query_present"
        case queryCount = "query_count"
    }

    public func encode(to encoder: Encoder) throws {
        try base.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNilOrValue(webSearchAction, forKey: .webSearchAction)
        try container.encode(queryPresent, forKey: .queryPresent)
        try container.encodeNilOrValue(queryCount, forKey: .queryCount)
    }
}

public struct CodexWebSearchEventRequest: Equatable, Encodable, Sendable {
    public let eventType: String
    public let eventParams: CodexWebSearchEventParams

    public init(eventType: String, eventParams: CodexWebSearchEventParams) {
        self.eventType = eventType
        self.eventParams = eventParams
    }

    private enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case eventParams = "event_params"
    }
}

public struct CodexImageGenerationEventParams: Equatable, Encodable, Sendable {
    public let base: CodexToolItemEventBase
    public let revisedPromptPresent: Bool
    public let savedPathPresent: Bool

    public init(
        base: CodexToolItemEventBase,
        revisedPromptPresent: Bool,
        savedPathPresent: Bool
    ) {
        self.base = base
        self.revisedPromptPresent = revisedPromptPresent
        self.savedPathPresent = savedPathPresent
    }

    private enum CodingKeys: String, CodingKey {
        case revisedPromptPresent = "revised_prompt_present"
        case savedPathPresent = "saved_path_present"
    }

    public func encode(to encoder: Encoder) throws {
        try base.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(revisedPromptPresent, forKey: .revisedPromptPresent)
        try container.encode(savedPathPresent, forKey: .savedPathPresent)
    }
}

public struct CodexImageGenerationEventRequest: Equatable, Encodable, Sendable {
    public let eventType: String
    public let eventParams: CodexImageGenerationEventParams

    public init(eventType: String, eventParams: CodexImageGenerationEventParams) {
        self.eventType = eventType
        self.eventParams = eventParams
    }

    private enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case eventParams = "event_params"
    }
}

public struct CodexCommandExecutionAnalyticsContext: Equatable, Sendable {
    public let appServerClient: CodexAppServerClientMetadata
    public let runtime: CodexRuntimeMetadata
    public let threadSource: ThreadSource?
    public let subagentSource: String?
    public let parentThreadID: String?

    public init(
        appServerClient: CodexAppServerClientMetadata,
        runtime: CodexRuntimeMetadata,
        threadSource: ThreadSource? = nil,
        subagentSource: String? = nil,
        parentThreadID: String? = nil
    ) {
        self.appServerClient = appServerClient
        self.runtime = runtime
        self.threadSource = threadSource
        self.subagentSource = subagentSource
        self.parentThreadID = parentThreadID
    }
}

public typealias CodexFileChangeAnalyticsContext = CodexCommandExecutionAnalyticsContext
public typealias CodexMcpToolCallAnalyticsContext = CodexCommandExecutionAnalyticsContext
public typealias CodexDynamicToolCallAnalyticsContext = CodexCommandExecutionAnalyticsContext
public typealias CodexCollabAgentToolCallAnalyticsContext = CodexCommandExecutionAnalyticsContext
public typealias CodexWebSearchAnalyticsContext = CodexCommandExecutionAnalyticsContext
public typealias CodexImageGenerationAnalyticsContext = CodexCommandExecutionAnalyticsContext

public struct CodexCommandExecutionAnalyticsReducer: Sendable {
    private var startedAtMilliseconds: [CommandExecutionItemKey: UInt64] = [:]

    public init() {}

    public mutating func ingestStarted(_ notification: ItemStartedNotification) {
        guard case .commandExecution = notification.item,
              let startedAtMilliseconds = Self.unsignedMilliseconds(notification.startedAtMilliseconds)
        else {
            return
        }

        self.startedAtMilliseconds[CommandExecutionItemKey(notification)] = startedAtMilliseconds
    }

    public mutating func ingestCompleted(
        _ notification: ItemCompletedNotification,
        context: CodexCommandExecutionAnalyticsContext
    ) -> CodexCommandExecutionEventRequest? {
        let key = CommandExecutionItemKey(notification)
        guard let startedAtMilliseconds = startedAtMilliseconds.removeValue(forKey: key),
              let completedAtMilliseconds = Self.unsignedMilliseconds(notification.completedAtMilliseconds)
        else {
            return nil
        }

        guard case let .commandExecution(
            id,
            _,
            _,
            _,
            source,
            status,
            commandActions,
            _,
            exitCode,
            durationMs
        ) = notification.item,
            let outcome = CodexCommandExecutionAnalyticsReducer.outcome(for: status)
        else {
            return nil
        }

        return CodexCommandExecutionEventRequest(
            eventType: "codex_command_execution_event",
            eventParams: CodexCommandExecutionEventParams(
                base: CodexToolItemEventBase(
                    threadID: notification.threadID,
                    turnID: notification.turnID,
                    itemID: id,
                    appServerClient: context.appServerClient,
                    runtime: context.runtime,
                    threadSource: context.threadSource,
                    subagentSource: context.subagentSource,
                    parentThreadID: context.parentThreadID,
                    toolName: Self.toolName(for: source),
                    startedAtMilliseconds: startedAtMilliseconds,
                    completedAtMilliseconds: completedAtMilliseconds,
                    durationMilliseconds: completedAtMilliseconds >= startedAtMilliseconds
                        ? completedAtMilliseconds - startedAtMilliseconds
                        : nil,
                    executionDurationMilliseconds: Self.unsignedMilliseconds(durationMs),
                    reviewCount: 0,
                    guardianReviewCount: 0,
                    userReviewCount: 0,
                    finalApprovalOutcome: .unknown,
                    terminalStatus: outcome.terminalStatus,
                    failureKind: outcome.failureKind,
                    requestedAdditionalPermissions: false,
                    requestedNetworkAccess: false
                ),
                commandExecutionSource: CommandExecutionSource(source),
                exitCode: exitCode,
                commandActionCounts: CodexCommandActionCounts(actions: commandActions)
            )
        )
    }

    private static func toolName(for source: AppServerCommandExecutionSource) -> String {
        switch source {
        case .agent:
            return "shell"
        case .userShell:
            return "user_shell"
        case .unifiedExecStartup, .unifiedExecInteraction:
            return "unified_exec"
        }
    }

    private static func outcome(
        for status: AppServerCommandExecutionStatus
    ) -> (terminalStatus: ToolItemTerminalStatus, failureKind: ToolItemFailureKind?)? {
        switch status {
        case .inProgress:
            return nil
        case .completed:
            return (.completed, nil)
        case .failed:
            return (.failed, .toolError)
        case .declined:
            return (.rejected, .approvalDenied)
        }
    }

    private static func unsignedMilliseconds(_ milliseconds: Int64?) -> UInt64? {
        guard let milliseconds, milliseconds >= 0 else {
            return nil
        }
        return UInt64(milliseconds)
    }
}

public struct CodexFileChangeAnalyticsReducer: Sendable {
    private var startedAtMilliseconds: [FileChangeItemKey: UInt64] = [:]

    public init() {}

    public mutating func ingestStarted(_ notification: ItemStartedNotification) {
        guard case .fileChange = notification.item,
              let startedAtMilliseconds = Self.unsignedMilliseconds(notification.startedAtMilliseconds)
        else {
            return
        }

        self.startedAtMilliseconds[FileChangeItemKey(notification)] = startedAtMilliseconds
    }

    public mutating func ingestCompleted(
        _ notification: ItemCompletedNotification,
        context: CodexFileChangeAnalyticsContext
    ) -> CodexFileChangeEventRequest? {
        let key = FileChangeItemKey(notification)
        guard let startedAtMilliseconds = startedAtMilliseconds.removeValue(forKey: key),
              let completedAtMilliseconds = Self.unsignedMilliseconds(notification.completedAtMilliseconds)
        else {
            return nil
        }

        guard case let .fileChange(id, changes, status) = notification.item,
              let outcome = Self.outcome(for: status)
        else {
            return nil
        }

        return CodexFileChangeEventRequest(
            eventType: "codex_file_change_event",
            eventParams: CodexFileChangeEventParams(
                base: CodexToolItemEventBase(
                    threadID: notification.threadID,
                    turnID: notification.turnID,
                    itemID: id,
                    appServerClient: context.appServerClient,
                    runtime: context.runtime,
                    threadSource: context.threadSource,
                    subagentSource: context.subagentSource,
                    parentThreadID: context.parentThreadID,
                    toolName: "apply_patch",
                    startedAtMilliseconds: startedAtMilliseconds,
                    completedAtMilliseconds: completedAtMilliseconds,
                    durationMilliseconds: completedAtMilliseconds >= startedAtMilliseconds
                        ? completedAtMilliseconds - startedAtMilliseconds
                        : nil,
                    executionDurationMilliseconds: nil,
                    reviewCount: 0,
                    guardianReviewCount: 0,
                    userReviewCount: 0,
                    finalApprovalOutcome: .unknown,
                    terminalStatus: outcome.terminalStatus,
                    failureKind: outcome.failureKind,
                    requestedAdditionalPermissions: false,
                    requestedNetworkAccess: false
                ),
                fileChangeCounts: CodexFileChangeCounts(changes: changes)
            )
        )
    }

    private static func outcome(
        for status: AppServerPatchApplyStatus
    ) -> (terminalStatus: ToolItemTerminalStatus, failureKind: ToolItemFailureKind?)? {
        switch status {
        case .inProgress:
            return nil
        case .completed:
            return (.completed, nil)
        case .failed:
            return (.failed, .toolError)
        case .declined:
            return (.rejected, .approvalDenied)
        }
    }

    private static func unsignedMilliseconds(_ milliseconds: Int64?) -> UInt64? {
        guard let milliseconds, milliseconds >= 0 else {
            return nil
        }
        return UInt64(milliseconds)
    }
}

public struct CodexMcpToolCallAnalyticsReducer: Sendable {
    private var startedAtMilliseconds: [McpToolCallItemKey: UInt64] = [:]

    public init() {}

    public mutating func ingestStarted(_ notification: ItemStartedNotification) {
        guard case .mcpToolCall = notification.item,
              let startedAtMilliseconds = Self.unsignedMilliseconds(notification.startedAtMilliseconds)
        else {
            return
        }

        self.startedAtMilliseconds[McpToolCallItemKey(notification)] = startedAtMilliseconds
    }

    public mutating func ingestCompleted(
        _ notification: ItemCompletedNotification,
        context: CodexMcpToolCallAnalyticsContext
    ) -> CodexMcpToolCallEventRequest? {
        let key = McpToolCallItemKey(notification)
        guard let startedAtMilliseconds = startedAtMilliseconds.removeValue(forKey: key),
              let completedAtMilliseconds = Self.unsignedMilliseconds(notification.completedAtMilliseconds)
        else {
            return nil
        }

        guard case let .mcpToolCall(
            id,
            server,
            tool,
            status,
            _,
            _,
            _,
            error,
            durationMs
        ) = notification.item,
            let outcome = Self.outcome(for: status)
        else {
            return nil
        }

        return CodexMcpToolCallEventRequest(
            eventType: "codex_mcp_tool_call_event",
            eventParams: CodexMcpToolCallEventParams(
                base: CodexToolItemEventBase(
                    threadID: notification.threadID,
                    turnID: notification.turnID,
                    itemID: id,
                    appServerClient: context.appServerClient,
                    runtime: context.runtime,
                    threadSource: context.threadSource,
                    subagentSource: context.subagentSource,
                    parentThreadID: context.parentThreadID,
                    toolName: tool,
                    startedAtMilliseconds: startedAtMilliseconds,
                    completedAtMilliseconds: completedAtMilliseconds,
                    durationMilliseconds: completedAtMilliseconds >= startedAtMilliseconds
                        ? completedAtMilliseconds - startedAtMilliseconds
                        : nil,
                    executionDurationMilliseconds: Self.unsignedMilliseconds(durationMs),
                    reviewCount: 0,
                    guardianReviewCount: 0,
                    userReviewCount: 0,
                    finalApprovalOutcome: .unknown,
                    terminalStatus: outcome.terminalStatus,
                    failureKind: outcome.failureKind,
                    requestedAdditionalPermissions: false,
                    requestedNetworkAccess: false
                ),
                mcpServerName: server,
                mcpToolName: tool,
                mcpErrorPresent: error != nil
            )
        )
    }

    private static func outcome(
        for status: McpToolCallStatus
    ) -> (terminalStatus: ToolItemTerminalStatus, failureKind: ToolItemFailureKind?)? {
        switch status {
        case .inProgress:
            return nil
        case .completed:
            return (.completed, nil)
        case .failed:
            return (.failed, .toolError)
        }
    }

    private static func unsignedMilliseconds(_ milliseconds: Int64?) -> UInt64? {
        guard let milliseconds, milliseconds >= 0 else {
            return nil
        }
        return UInt64(milliseconds)
    }
}

public struct CodexDynamicToolCallAnalyticsReducer: Sendable {
    private var startedAtMilliseconds: [DynamicToolCallItemKey: UInt64] = [:]

    public init() {}

    public mutating func ingestStarted(_ notification: ItemStartedNotification) {
        guard case .dynamicToolCall = notification.item,
              let startedAtMilliseconds = Self.unsignedMilliseconds(notification.startedAtMilliseconds)
        else {
            return
        }

        self.startedAtMilliseconds[DynamicToolCallItemKey(notification)] = startedAtMilliseconds
    }

    public mutating func ingestCompleted(
        _ notification: ItemCompletedNotification,
        context: CodexDynamicToolCallAnalyticsContext
    ) -> CodexDynamicToolCallEventRequest? {
        let key = DynamicToolCallItemKey(notification)
        guard let startedAtMilliseconds = startedAtMilliseconds.removeValue(forKey: key),
              let completedAtMilliseconds = Self.unsignedMilliseconds(notification.completedAtMilliseconds)
        else {
            return nil
        }

        guard case let .dynamicToolCall(
            id,
            _,
            tool,
            _,
            status,
            contentItems,
            success,
            durationMs
        ) = notification.item,
            let outcome = Self.outcome(for: status)
        else {
            return nil
        }

        return CodexDynamicToolCallEventRequest(
            eventType: "codex_dynamic_tool_call_event",
            eventParams: CodexDynamicToolCallEventParams(
                base: CodexToolItemEventBase(
                    threadID: notification.threadID,
                    turnID: notification.turnID,
                    itemID: id,
                    appServerClient: context.appServerClient,
                    runtime: context.runtime,
                    threadSource: context.threadSource,
                    subagentSource: context.subagentSource,
                    parentThreadID: context.parentThreadID,
                    toolName: tool,
                    startedAtMilliseconds: startedAtMilliseconds,
                    completedAtMilliseconds: completedAtMilliseconds,
                    durationMilliseconds: completedAtMilliseconds >= startedAtMilliseconds
                        ? completedAtMilliseconds - startedAtMilliseconds
                        : nil,
                    executionDurationMilliseconds: Self.unsignedMilliseconds(durationMs),
                    reviewCount: 0,
                    guardianReviewCount: 0,
                    userReviewCount: 0,
                    finalApprovalOutcome: .unknown,
                    terminalStatus: outcome.terminalStatus,
                    failureKind: outcome.failureKind,
                    requestedAdditionalPermissions: false,
                    requestedNetworkAccess: false
                ),
                dynamicToolName: tool,
                success: success,
                contentCounts: contentItems.map(CodexDynamicToolCallContentCounts.init(contentItems:))
            )
        )
    }

    private static func outcome(
        for status: AppServerDynamicToolCallStatus
    ) -> (terminalStatus: ToolItemTerminalStatus, failureKind: ToolItemFailureKind?)? {
        switch status {
        case .inProgress:
            return nil
        case .completed:
            return (.completed, nil)
        case .failed:
            return (.failed, .toolError)
        }
    }

    private static func unsignedMilliseconds(_ milliseconds: Int64?) -> UInt64? {
        guard let milliseconds, milliseconds >= 0 else {
            return nil
        }
        return UInt64(milliseconds)
    }
}

public struct CodexCollabAgentToolCallAnalyticsReducer: Sendable {
    private var startedAtMilliseconds: [CollabAgentToolCallItemKey: UInt64] = [:]

    public init() {}

    public mutating func ingestStarted(_ notification: ItemStartedNotification) {
        guard case .collabAgentToolCall = notification.item,
              let startedAtMilliseconds = Self.unsignedMilliseconds(notification.startedAtMilliseconds)
        else {
            return
        }

        self.startedAtMilliseconds[CollabAgentToolCallItemKey(notification)] = startedAtMilliseconds
    }

    public mutating func ingestCompleted(
        _ notification: ItemCompletedNotification,
        context: CodexCollabAgentToolCallAnalyticsContext
    ) -> CodexCollabAgentToolCallEventRequest? {
        let key = CollabAgentToolCallItemKey(notification)
        guard let startedAtMilliseconds = startedAtMilliseconds.removeValue(forKey: key),
              let completedAtMilliseconds = Self.unsignedMilliseconds(notification.completedAtMilliseconds)
        else {
            return nil
        }

        guard case let .collabAgentToolCall(
            id,
            tool,
            status,
            senderThreadID,
            receiverThreadIDs,
            _,
            model,
            reasoningEffort,
            agentsStates
        ) = notification.item,
            let outcome = Self.outcome(for: status)
        else {
            return nil
        }

        return CodexCollabAgentToolCallEventRequest(
            eventType: "codex_collab_agent_tool_call_event",
            eventParams: CodexCollabAgentToolCallEventParams(
                base: CodexToolItemEventBase(
                    threadID: notification.threadID,
                    turnID: notification.turnID,
                    itemID: id,
                    appServerClient: context.appServerClient,
                    runtime: context.runtime,
                    threadSource: context.threadSource,
                    subagentSource: context.subagentSource,
                    parentThreadID: context.parentThreadID,
                    toolName: Self.toolName(for: tool),
                    startedAtMilliseconds: startedAtMilliseconds,
                    completedAtMilliseconds: completedAtMilliseconds,
                    durationMilliseconds: completedAtMilliseconds >= startedAtMilliseconds
                        ? completedAtMilliseconds - startedAtMilliseconds
                        : nil,
                    executionDurationMilliseconds: nil,
                    reviewCount: 0,
                    guardianReviewCount: 0,
                    userReviewCount: 0,
                    finalApprovalOutcome: .unknown,
                    terminalStatus: outcome.terminalStatus,
                    failureKind: outcome.failureKind,
                    requestedAdditionalPermissions: false,
                    requestedNetworkAccess: false
                ),
                senderThreadID: senderThreadID,
                receiverThreadIDs: receiverThreadIDs,
                requestedModel: model,
                requestedReasoningEffort: reasoningEffort?.rawValue,
                stateCounts: CodexCollabAgentStateCounts(states: agentsStates)
            )
        )
    }

    private static func outcome(
        for status: AppServerCollabAgentToolCallStatus
    ) -> (terminalStatus: ToolItemTerminalStatus, failureKind: ToolItemFailureKind?)? {
        switch status {
        case .inProgress:
            return nil
        case .completed:
            return (.completed, nil)
        case .failed:
            return (.failed, .toolError)
        }
    }

    private static func toolName(for tool: AppServerCollabAgentTool) -> String {
        switch tool {
        case .spawnAgent:
            return "spawn_agent"
        case .sendInput:
            return "send_input"
        case .resumeAgent:
            return "resume_agent"
        case .wait:
            return "wait_agent"
        case .closeAgent:
            return "close_agent"
        }
    }

    private static func unsignedMilliseconds(_ milliseconds: Int64?) -> UInt64? {
        guard let milliseconds, milliseconds >= 0 else {
            return nil
        }
        return UInt64(milliseconds)
    }
}

public struct CodexWebSearchAnalyticsReducer: Sendable {
    private var startedAtMilliseconds: [WebSearchItemKey: UInt64] = [:]

    public init() {}

    public mutating func ingestStarted(_ notification: ItemStartedNotification) {
        guard case .webSearch = notification.item,
              let startedAtMilliseconds = Self.unsignedMilliseconds(notification.startedAtMilliseconds)
        else {
            return
        }

        self.startedAtMilliseconds[WebSearchItemKey(notification)] = startedAtMilliseconds
    }

    public mutating func ingestCompleted(
        _ notification: ItemCompletedNotification,
        context: CodexWebSearchAnalyticsContext
    ) -> CodexWebSearchEventRequest? {
        let key = WebSearchItemKey(notification)
        guard let startedAtMilliseconds = startedAtMilliseconds.removeValue(forKey: key),
              let completedAtMilliseconds = Self.unsignedMilliseconds(notification.completedAtMilliseconds)
        else {
            return nil
        }

        guard case let .webSearch(id, query, action) = notification.item else {
            return nil
        }

        return CodexWebSearchEventRequest(
            eventType: "codex_web_search_event",
            eventParams: CodexWebSearchEventParams(
                base: CodexToolItemEventBase(
                    threadID: notification.threadID,
                    turnID: notification.turnID,
                    itemID: id,
                    appServerClient: context.appServerClient,
                    runtime: context.runtime,
                    threadSource: context.threadSource,
                    subagentSource: context.subagentSource,
                    parentThreadID: context.parentThreadID,
                    toolName: "web_search",
                    startedAtMilliseconds: startedAtMilliseconds,
                    completedAtMilliseconds: completedAtMilliseconds,
                    durationMilliseconds: completedAtMilliseconds >= startedAtMilliseconds
                        ? completedAtMilliseconds - startedAtMilliseconds
                        : nil,
                    executionDurationMilliseconds: nil,
                    reviewCount: 0,
                    guardianReviewCount: 0,
                    userReviewCount: 0,
                    finalApprovalOutcome: .unknown,
                    terminalStatus: .completed,
                    failureKind: nil,
                    requestedAdditionalPermissions: false,
                    requestedNetworkAccess: false
                ),
                webSearchAction: action.map(WebSearchActionKind.init),
                queryPresent: !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                queryCount: Self.queryCount(query: query, action: action)
            )
        )
    }

    private static func queryCount(query: String, action: AppServerWebSearchAction?) -> UInt64? {
        switch action {
        case let .search(query: actionQuery, queries: queries):
            if let queries {
                return UInt64(queries.count)
            }
            return actionQuery == nil ? nil : 1
        case .openPage, .findInPage, .other:
            return nil
        case nil:
            return query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : 1
        }
    }

    private static func unsignedMilliseconds(_ milliseconds: Int64?) -> UInt64? {
        guard let milliseconds, milliseconds >= 0 else {
            return nil
        }
        return UInt64(milliseconds)
    }
}

public struct CodexImageGenerationAnalyticsReducer: Sendable {
    private var startedAtMilliseconds: [ImageGenerationItemKey: UInt64] = [:]

    public init() {}

    public mutating func ingestStarted(_ notification: ItemStartedNotification) {
        guard case .imageGeneration = notification.item,
              let startedAtMilliseconds = Self.unsignedMilliseconds(notification.startedAtMilliseconds)
        else {
            return
        }

        self.startedAtMilliseconds[ImageGenerationItemKey(notification)] = startedAtMilliseconds
    }

    public mutating func ingestCompleted(
        _ notification: ItemCompletedNotification,
        context: CodexImageGenerationAnalyticsContext
    ) -> CodexImageGenerationEventRequest? {
        let key = ImageGenerationItemKey(notification)
        guard let startedAtMilliseconds = startedAtMilliseconds.removeValue(forKey: key),
              let completedAtMilliseconds = Self.unsignedMilliseconds(notification.completedAtMilliseconds)
        else {
            return nil
        }

        guard case let .imageGeneration(id, status, revisedPrompt, _, savedPath) = notification.item else {
            return nil
        }

        let outcome = Self.outcome(for: status)
        return CodexImageGenerationEventRequest(
            eventType: "codex_image_generation_event",
            eventParams: CodexImageGenerationEventParams(
                base: CodexToolItemEventBase(
                    threadID: notification.threadID,
                    turnID: notification.turnID,
                    itemID: id,
                    appServerClient: context.appServerClient,
                    runtime: context.runtime,
                    threadSource: context.threadSource,
                    subagentSource: context.subagentSource,
                    parentThreadID: context.parentThreadID,
                    toolName: "image_generation",
                    startedAtMilliseconds: startedAtMilliseconds,
                    completedAtMilliseconds: completedAtMilliseconds,
                    durationMilliseconds: completedAtMilliseconds >= startedAtMilliseconds
                        ? completedAtMilliseconds - startedAtMilliseconds
                        : nil,
                    executionDurationMilliseconds: nil,
                    reviewCount: 0,
                    guardianReviewCount: 0,
                    userReviewCount: 0,
                    finalApprovalOutcome: .unknown,
                    terminalStatus: outcome.terminalStatus,
                    failureKind: outcome.failureKind,
                    requestedAdditionalPermissions: false,
                    requestedNetworkAccess: false
                ),
                revisedPromptPresent: revisedPrompt != nil,
                savedPathPresent: savedPath != nil
            )
        )
    }

    private static func outcome(
        for status: String
    ) -> (terminalStatus: ToolItemTerminalStatus, failureKind: ToolItemFailureKind?) {
        switch status {
        case "failed", "error":
            return (.failed, .toolError)
        default:
            return (.completed, nil)
        }
    }

    private static func unsignedMilliseconds(_ milliseconds: Int64?) -> UInt64? {
        guard let milliseconds, milliseconds >= 0 else {
            return nil
        }
        return UInt64(milliseconds)
    }
}

private struct CommandExecutionItemKey: Hashable {
    let threadID: String
    let turnID: String
    let itemID: String

    init(_ notification: ItemStartedNotification) {
        self.threadID = notification.threadID
        self.turnID = notification.turnID
        self.itemID = notification.item.id
    }

    init(_ notification: ItemCompletedNotification) {
        self.threadID = notification.threadID
        self.turnID = notification.turnID
        self.itemID = notification.item.id
    }
}

private struct FileChangeItemKey: Hashable {
    let threadID: String
    let turnID: String
    let itemID: String

    init(_ notification: ItemStartedNotification) {
        self.threadID = notification.threadID
        self.turnID = notification.turnID
        self.itemID = notification.item.id
    }

    init(_ notification: ItemCompletedNotification) {
        self.threadID = notification.threadID
        self.turnID = notification.turnID
        self.itemID = notification.item.id
    }
}

private struct McpToolCallItemKey: Hashable {
    let threadID: String
    let turnID: String
    let itemID: String

    init(_ notification: ItemStartedNotification) {
        self.threadID = notification.threadID
        self.turnID = notification.turnID
        self.itemID = notification.item.id
    }

    init(_ notification: ItemCompletedNotification) {
        self.threadID = notification.threadID
        self.turnID = notification.turnID
        self.itemID = notification.item.id
    }
}

private struct DynamicToolCallItemKey: Hashable {
    let threadID: String
    let turnID: String
    let itemID: String

    init(_ notification: ItemStartedNotification) {
        self.threadID = notification.threadID
        self.turnID = notification.turnID
        self.itemID = notification.item.id
    }

    init(_ notification: ItemCompletedNotification) {
        self.threadID = notification.threadID
        self.turnID = notification.turnID
        self.itemID = notification.item.id
    }
}

private struct CollabAgentToolCallItemKey: Hashable {
    let threadID: String
    let turnID: String
    let itemID: String

    init(_ notification: ItemStartedNotification) {
        self.threadID = notification.threadID
        self.turnID = notification.turnID
        self.itemID = notification.item.id
    }

    init(_ notification: ItemCompletedNotification) {
        self.threadID = notification.threadID
        self.turnID = notification.turnID
        self.itemID = notification.item.id
    }
}

private struct WebSearchItemKey: Hashable {
    let threadID: String
    let turnID: String
    let itemID: String

    init(_ notification: ItemStartedNotification) {
        self.threadID = notification.threadID
        self.turnID = notification.turnID
        self.itemID = notification.item.id
    }

    init(_ notification: ItemCompletedNotification) {
        self.threadID = notification.threadID
        self.turnID = notification.turnID
        self.itemID = notification.item.id
    }
}

private struct ImageGenerationItemKey: Hashable {
    let threadID: String
    let turnID: String
    let itemID: String

    init(_ notification: ItemStartedNotification) {
        self.threadID = notification.threadID
        self.turnID = notification.turnID
        self.itemID = notification.item.id
    }

    init(_ notification: ItemCompletedNotification) {
        self.threadID = notification.threadID
        self.turnID = notification.turnID
        self.itemID = notification.item.id
    }
}

public struct CodexReviewEventParams: Equatable, Codable, Sendable {
    public let threadID: String
    public let turnID: String
    public let itemID: String?
    public let reviewID: String
    public let appServerClient: CodexAppServerClientMetadata
    public let runtime: CodexRuntimeMetadata
    public let threadSource: ThreadSource?
    public let subagentSource: String?
    public let parentThreadID: String?
    public let toolKind: ReviewSubjectKind
    public let toolName: String
    public let reviewer: ReviewAnalyticsReviewer
    public let trigger: ReviewTrigger
    public let status: ReviewStatus
    public let resolution: ReviewResolution
    public let startedAtMilliseconds: UInt64
    public let completedAtMilliseconds: UInt64
    public let durationMilliseconds: UInt64?

    public init(
        threadID: String,
        turnID: String,
        itemID: String? = nil,
        reviewID: String,
        appServerClient: CodexAppServerClientMetadata,
        runtime: CodexRuntimeMetadata,
        threadSource: ThreadSource? = nil,
        subagentSource: String? = nil,
        parentThreadID: String? = nil,
        toolKind: ReviewSubjectKind,
        toolName: String,
        reviewer: ReviewAnalyticsReviewer,
        trigger: ReviewTrigger,
        status: ReviewStatus,
        resolution: ReviewResolution,
        startedAtMilliseconds: UInt64,
        completedAtMilliseconds: UInt64,
        durationMilliseconds: UInt64? = nil
    ) {
        self.threadID = threadID
        self.turnID = turnID
        self.itemID = itemID
        self.reviewID = reviewID
        self.appServerClient = appServerClient
        self.runtime = runtime
        self.threadSource = threadSource
        self.subagentSource = subagentSource
        self.parentThreadID = parentThreadID
        self.toolKind = toolKind
        self.toolName = toolName
        self.reviewer = reviewer
        self.trigger = trigger
        self.status = status
        self.resolution = resolution
        self.startedAtMilliseconds = startedAtMilliseconds
        self.completedAtMilliseconds = completedAtMilliseconds
        self.durationMilliseconds = durationMilliseconds
    }

    private enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case turnID = "turn_id"
        case itemID = "item_id"
        case reviewID = "review_id"
        case appServerClient = "app_server_client"
        case runtime
        case threadSource = "thread_source"
        case subagentSource = "subagent_source"
        case parentThreadID = "parent_thread_id"
        case toolKind = "tool_kind"
        case toolName = "tool_name"
        case reviewer
        case trigger
        case status
        case resolution
        case startedAtMilliseconds = "started_at_ms"
        case completedAtMilliseconds = "completed_at_ms"
        case durationMilliseconds = "duration_ms"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(threadID, forKey: .threadID)
        try container.encode(turnID, forKey: .turnID)
        try container.encodeNilOrValue(itemID, forKey: .itemID)
        try container.encode(reviewID, forKey: .reviewID)
        try container.encode(appServerClient, forKey: .appServerClient)
        try container.encode(runtime, forKey: .runtime)
        try container.encodeNilOrValue(threadSource, forKey: .threadSource)
        try container.encodeNilOrValue(subagentSource, forKey: .subagentSource)
        try container.encodeNilOrValue(parentThreadID, forKey: .parentThreadID)
        try container.encode(toolKind, forKey: .toolKind)
        try container.encode(toolName, forKey: .toolName)
        try container.encode(reviewer, forKey: .reviewer)
        try container.encode(trigger, forKey: .trigger)
        try container.encode(status, forKey: .status)
        try container.encode(resolution, forKey: .resolution)
        try container.encode(startedAtMilliseconds, forKey: .startedAtMilliseconds)
        try container.encode(completedAtMilliseconds, forKey: .completedAtMilliseconds)
        try container.encodeNilOrValue(durationMilliseconds, forKey: .durationMilliseconds)
    }
}

public struct CodexReviewEventRequest: Equatable, Codable, Sendable {
    public let eventType: String
    public let eventParams: CodexReviewEventParams

    public init(eventType: String, eventParams: CodexReviewEventParams) {
        self.eventType = eventType
        self.eventParams = eventParams
    }

    private enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case eventParams = "event_params"
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeNilOrValue<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}
