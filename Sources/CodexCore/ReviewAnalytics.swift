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
