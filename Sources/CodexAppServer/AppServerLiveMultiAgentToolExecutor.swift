import Foundation
import CodexCore

struct AppServerLiveMultiAgentToolExecutor {
    let currentThreadID: ThreadId
    let currentSessionSource: SessionSource
    let stateStore: SQLiteAgentGraphStore?
    let waitTimeouts: MultiAgentV2WaitTimeouts
    let hideSpawnAgentMetadata: Bool
    let spawnAgent: @Sendable (LiveSpawnAgentRequest) async throws -> LiveSpawnAgentResult
    let isTurnRunning: @Sendable (String) async -> Bool
    let agentStatus: @Sendable (String) async -> AgentStatus
    let agentLastTaskMessage: @Sendable (String) async -> String?
    let hasPendingMailboxItems: @Sendable (String) async -> Bool
    let waitForMailboxChange: @Sendable (String, Int64) async -> Bool
    let queueMailboxCommunications: @Sendable (String, [InterAgentCommunication]) async -> Void
    let recordAgentLastTaskMessage: @Sendable (String, String) async -> Void
    let submitPendingWorkTurnIfIdle: @Sendable (String) async -> Bool
    let closeAgentThreads: @Sendable ([String]) async -> Void

    init(
        currentThreadID: ThreadId,
        currentSessionSource: SessionSource,
        stateStore: SQLiteAgentGraphStore?,
        waitTimeouts: MultiAgentV2WaitTimeouts,
        hideSpawnAgentMetadata: Bool = false,
        spawnAgent: @escaping @Sendable (LiveSpawnAgentRequest) async throws -> LiveSpawnAgentResult = { _ in
            throw AppServerLiveMultiAgentToolError(message: "spawn_agent is not available in this runtime")
        },
        isTurnRunning: @escaping @Sendable (String) async -> Bool,
        agentStatus: @escaping @Sendable (String) async -> AgentStatus,
        agentLastTaskMessage: @escaping @Sendable (String) async -> String?,
        hasPendingMailboxItems: @escaping @Sendable (String) async -> Bool,
        waitForMailboxChange: @escaping @Sendable (String, Int64) async -> Bool,
        queueMailboxCommunications: @escaping @Sendable (String, [InterAgentCommunication]) async -> Void,
        recordAgentLastTaskMessage: @escaping @Sendable (String, String) async -> Void,
        submitPendingWorkTurnIfIdle: @escaping @Sendable (String) async -> Bool,
        closeAgentThreads: @escaping @Sendable ([String]) async -> Void
    ) {
        self.currentThreadID = currentThreadID
        self.currentSessionSource = currentSessionSource
        self.stateStore = stateStore
        self.waitTimeouts = waitTimeouts
        self.hideSpawnAgentMetadata = hideSpawnAgentMetadata
        self.spawnAgent = spawnAgent
        self.isTurnRunning = isTurnRunning
        self.agentStatus = agentStatus
        self.agentLastTaskMessage = agentLastTaskMessage
        self.hasPendingMailboxItems = hasPendingMailboxItems
        self.waitForMailboxChange = waitForMailboxChange
        self.queueMailboxCommunications = queueMailboxCommunications
        self.recordAgentLastTaskMessage = recordAgentLastTaskMessage
        self.submitPendingWorkTurnIfIdle = submitPendingWorkTurnIfIdle
        self.closeAgentThreads = closeAgentThreads
    }

    func execute(_ item: ResponseItem) async -> NonInteractiveExec.FunctionCallExecutionResult? {
        guard case let .functionCall(_, name, _, arguments, callID) = item else {
            return nil
        }
        switch name {
        case "spawn_agent":
            return await executeSpawnAgent(arguments: arguments, callID: callID)
        case "send_message":
            return await executeMessageTool(
                name: name,
                arguments: arguments,
                callID: callID,
                triggerTurn: false
            )
        case "followup_task":
            return await executeMessageTool(
                name: name,
                arguments: arguments,
                callID: callID,
                triggerTurn: true
            )
        case "list_agents":
            return await executeListAgents(arguments: arguments, callID: callID)
        case "wait_agent":
            return await executeWaitAgent(arguments: arguments, callID: callID)
        case "close_agent":
            return await executeCloseAgent(arguments: arguments, callID: callID)
        default:
            return nil
        }
    }

    private func executeSpawnAgent(
        arguments: String,
        callID: String
    ) async -> NonInteractiveExec.FunctionCallExecutionResult {
        let args: SpawnAgentToolArguments
        do {
            args = try JSONDecoder().decode(SpawnAgentToolArguments.self, from: Data(arguments.utf8))
        } catch {
            return Self.output(callID: callID, content: "failed to parse spawn_agent arguments: \(error)", success: false)
        }

        let forkMode: LiveSpawnAgentForkMode
        do {
            forkMode = try args.resolvedForkMode()
        } catch let error as AppServerLiveMultiAgentToolError {
            return Self.output(callID: callID, content: error.message, success: false)
        } catch {
            return Self.output(callID: callID, content: String(describing: error), success: false)
        }

        let currentAgentPath = currentSessionSource.agentPath ?? .root
        let childAgentPath: AgentPath
        do {
            childAgentPath = try currentAgentPath.join(args.taskName)
        } catch {
            return Self.output(callID: callID, content: String(describing: error), success: false)
        }

        let prompt = args.message
        let requestedModel = args.model ?? ""
        let requestedReasoningEffort = args.reasoningEffort ?? .medium
        var runtimeEvents: [EventMessage] = [
            .collabAgentSpawnBegin(CollabAgentSpawnBeginEvent(
                callID: callID,
                startedAtMilliseconds: AppServerLiveMultiAgentToolClock.millisecondsSinceEpoch(),
                senderThreadID: currentThreadID,
                prompt: prompt,
                model: requestedModel,
                reasoningEffort: requestedReasoningEffort
            ))
        ]

        do {
            let result = try await spawnAgent(LiveSpawnAgentRequest(
                callID: callID,
                message: prompt,
                taskName: args.taskName,
                agentType: args.agentType?.trimmingCharacters(in: .whitespacesAndNewlines),
                model: args.model,
                reasoningEffort: args.reasoningEffort,
                serviceTier: args.serviceTier,
                forkMode: forkMode,
                childAgentPath: childAgentPath
            ))
            runtimeEvents.append(.collabAgentSpawnEnd(CollabAgentSpawnEndEvent(
                callID: callID,
                completedAtMilliseconds: AppServerLiveMultiAgentToolClock.millisecondsSinceEpoch(),
                senderThreadID: currentThreadID,
                newThreadID: result.threadID,
                newAgentNickname: result.nickname,
                newAgentRole: result.role,
                prompt: prompt,
                model: result.model ?? requestedModel,
                reasoningEffort: result.reasoningEffort ?? requestedReasoningEffort,
                status: result.status
            )))
            let output = SpawnAgentToolResult(
                taskName: result.agentPath.description,
                nickname: hideSpawnAgentMetadata ? nil : result.nickname,
                hidesMetadata: hideSpawnAgentMetadata
            )
            return Self.jsonOutput(callID: callID, value: output, success: true, runtimeEvents: runtimeEvents)
        } catch let error as AppServerLiveMultiAgentToolError {
            runtimeEvents.append(.collabAgentSpawnEnd(CollabAgentSpawnEndEvent(
                callID: callID,
                completedAtMilliseconds: AppServerLiveMultiAgentToolClock.millisecondsSinceEpoch(),
                senderThreadID: currentThreadID,
                prompt: prompt,
                model: requestedModel,
                reasoningEffort: requestedReasoningEffort,
                status: .notFound
            )))
            return Self.output(callID: callID, content: error.message, success: false, runtimeEvents: runtimeEvents)
        } catch {
            runtimeEvents.append(.collabAgentSpawnEnd(CollabAgentSpawnEndEvent(
                callID: callID,
                completedAtMilliseconds: AppServerLiveMultiAgentToolClock.millisecondsSinceEpoch(),
                senderThreadID: currentThreadID,
                prompt: prompt,
                model: requestedModel,
                reasoningEffort: requestedReasoningEffort,
                status: .notFound
            )))
            return Self.output(callID: callID, content: String(describing: error), success: false, runtimeEvents: runtimeEvents)
        }
    }

    private func executeMessageTool(
        name: String,
        arguments: String,
        callID: String,
        triggerTurn: Bool
    ) async -> NonInteractiveExec.FunctionCallExecutionResult {
        let args: AgentMessageToolArguments
        do {
            args = try JSONDecoder().decode(AgentMessageToolArguments.self, from: Data(arguments.utf8))
        } catch {
            return Self.output(callID: callID, content: "failed to parse \(name) arguments: \(error)", success: false)
        }

        let prompt = args.message
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Self.output(callID: callID, content: "Empty message can't be sent to an agent", success: false)
        }

        do {
            let target = try await resolveAgentTarget(args.target)
            guard let receiverAgentPath = target.agentPath else {
                return Self.output(callID: callID, content: "target agent is missing an agent_path", success: false)
            }
            if triggerTurn, receiverAgentPath.isRoot {
                return Self.output(callID: callID, content: "Tasks can't be assigned to the root agent", success: false)
            }

            let startedAt = AppServerLiveMultiAgentToolClock.millisecondsSinceEpoch()
            var runtimeEvents: [EventMessage] = [
                .collabAgentInteractionBegin(CollabAgentInteractionBeginEvent(
                    callID: callID,
                    startedAtMilliseconds: startedAt,
                    senderThreadID: currentThreadID,
                    receiverThreadID: target.threadID,
                    prompt: prompt
                ))
            ]
            let communication = InterAgentCommunication(
                author: currentSessionSource.agentPath ?? .root,
                recipient: receiverAgentPath,
                content: prompt,
                triggerTurn: triggerTurn
            )
            await queueMailboxCommunications(target.threadID.description, [communication])
            await recordAgentLastTaskMessage(target.threadID.description, prompt)
            if triggerTurn {
                _ = await submitPendingWorkTurnIfIdle(target.threadID.description)
            }

            let status: AgentStatus = await isTurnRunning(target.threadID.description)
                ? .running
                : .completed(nil)
            runtimeEvents.append(.collabAgentInteractionEnd(CollabAgentInteractionEndEvent(
                callID: callID,
                completedAtMilliseconds: AppServerLiveMultiAgentToolClock.millisecondsSinceEpoch(),
                senderThreadID: currentThreadID,
                receiverThreadID: target.threadID,
                receiverAgentNickname: target.metadata?.agentNickname,
                receiverAgentRole: target.metadata?.agentRole,
                prompt: prompt,
                status: status
            )))
            return Self.output(callID: callID, content: "", success: true, runtimeEvents: runtimeEvents)
        } catch let error as AppServerLiveMultiAgentToolError {
            return Self.output(callID: callID, content: error.message, success: false)
        } catch {
            return Self.output(callID: callID, content: String(describing: error), success: false)
        }
    }

    private func executeWaitAgent(
        arguments: String,
        callID: String
    ) async -> NonInteractiveExec.FunctionCallExecutionResult {
        let args: WaitAgentToolArguments
        do {
            args = try JSONDecoder().decode(WaitAgentToolArguments.self, from: Data(arguments.utf8))
        } catch {
            return Self.output(callID: callID, content: "failed to parse wait_agent arguments: \(error)", success: false)
        }

        let timeoutMS: Int64
        if let requestedTimeout = args.timeoutMS {
            guard requestedTimeout >= waitTimeouts.min else {
                return Self.output(
                    callID: callID,
                    content: "timeout_ms must be at least \(waitTimeouts.min)",
                    success: false
                )
            }
            guard requestedTimeout <= waitTimeouts.max else {
                return Self.output(
                    callID: callID,
                    content: "timeout_ms must be at most \(waitTimeouts.max)",
                    success: false
                )
            }
            timeoutMS = requestedTimeout
        } else {
            timeoutMS = waitTimeouts.default
        }

        let startedAt = AppServerLiveMultiAgentToolClock.millisecondsSinceEpoch()
        var runtimeEvents: [EventMessage] = [
            .collabWaitingBegin(CollabWaitingBeginEvent(
                startedAtMilliseconds: startedAt,
                senderThreadID: currentThreadID,
                receiverThreadIDs: [],
                receiverAgents: [],
                callID: callID
            ))
        ]
        let hasMailboxUpdate: Bool
        if await hasPendingMailboxItems(currentThreadID.description) {
            hasMailboxUpdate = true
        } else {
            hasMailboxUpdate = await waitForMailboxChange(currentThreadID.description, timeoutMS)
        }
        let result = WaitAgentToolResult(timedOut: !hasMailboxUpdate)
        runtimeEvents.append(.collabWaitingEnd(CollabWaitingEndEvent(
            senderThreadID: currentThreadID,
            callID: callID,
            completedAtMilliseconds: AppServerLiveMultiAgentToolClock.millisecondsSinceEpoch(),
            agentStatuses: [],
            statuses: [:]
        )))
        return Self.jsonOutput(callID: callID, value: result, success: nil, runtimeEvents: runtimeEvents)
    }

    private func executeCloseAgent(
        arguments: String,
        callID: String
    ) async -> NonInteractiveExec.FunctionCallExecutionResult {
        let args: CloseAgentToolArguments
        do {
            args = try JSONDecoder().decode(CloseAgentToolArguments.self, from: Data(arguments.utf8))
        } catch {
            return Self.output(callID: callID, content: "failed to parse close_agent arguments: \(error)", success: false)
        }

        do {
            let target = try await resolveAgentTarget(args.target)
            if target.threadID == currentThreadID || target.agentPath?.isRoot == true {
                return Self.output(callID: callID, content: "root is not a spawned agent", success: false)
            }
            guard target.metadata != nil else {
                return Self.output(
                    callID: callID,
                    content: "live agent thread `\(target.threadID)` not found",
                    success: false
                )
            }

            let previousStatus = await status(for: target.threadID)
            var runtimeEvents: [EventMessage] = [
                .collabCloseBegin(CollabCloseBeginEvent(
                    callID: callID,
                    startedAtMilliseconds: AppServerLiveMultiAgentToolClock.millisecondsSinceEpoch(),
                    senderThreadID: currentThreadID,
                    receiverThreadID: target.threadID
                ))
            ]
            let threadIDsToClose = try await closeThreadIDs(target.threadID)
            await closeAgentThreads(threadIDsToClose.map(\.description))
            runtimeEvents.append(.collabCloseEnd(CollabCloseEndEvent(
                callID: callID,
                completedAtMilliseconds: AppServerLiveMultiAgentToolClock.millisecondsSinceEpoch(),
                senderThreadID: currentThreadID,
                receiverThreadID: target.threadID,
                receiverAgentNickname: target.metadata?.agentNickname,
                receiverAgentRole: target.metadata?.agentRole,
                status: previousStatus
            )))
            return Self.jsonOutput(
                callID: callID,
                value: CloseAgentToolResult(previousStatus: previousStatus),
                success: true,
                runtimeEvents: runtimeEvents
            )
        } catch let error as AppServerLiveMultiAgentToolError {
            return Self.output(callID: callID, content: error.message, success: false)
        } catch {
            return Self.output(callID: callID, content: String(describing: error), success: false)
        }
    }

    private func closeThreadIDs(_ targetThreadID: ThreadId) async throws -> [ThreadId] {
        var threadIDs = [targetThreadID]
        if let stateStore {
            let descendants = try await stateStore.listThreadSpawnDescendants(
                rootThreadID: targetThreadID,
                statusFilter: .open
            )
            threadIDs.append(contentsOf: descendants)
            for threadID in threadIDs {
                try await stateStore.setThreadSpawnEdgeStatus(childThreadID: threadID, status: .closed)
            }
        }
        return threadIDs
    }

    private func executeListAgents(
        arguments: String,
        callID: String
    ) async -> NonInteractiveExec.FunctionCallExecutionResult {
        let args: ListAgentsToolArguments
        do {
            args = try JSONDecoder().decode(ListAgentsToolArguments.self, from: Data(arguments.utf8))
        } catch {
            return Self.output(callID: callID, content: "failed to parse list_agents arguments: \(error)", success: false)
        }

        do {
            let prefix = try resolvedListPrefix(args.pathPrefix)
            let rootPath = AgentPath.root
            var agents: [ListedLiveAgent] = []
            if Self.agentPath(rootPath, matchesPrefix: prefix) {
                agents.append(ListedLiveAgent(
                    agentName: rootPath.description,
                    agentStatus: await status(for: currentThreadID),
                    lastTaskMessage: "Main thread"
                ))
            }
            if let stateStore {
                let threadMetadata = try await stateStore.listThreadsWithAgentPaths()
                for metadata in threadMetadata {
                    guard metadata.id != currentThreadID,
                          let rawPath = metadata.agentPath,
                          let agentPath = try? AgentPath(validating: rawPath),
                          !agentPath.isRoot,
                          Self.agentPath(agentPath, matchesPrefix: prefix)
                    else {
                        continue
                    }
                    agents.append(ListedLiveAgent(
                        agentName: agentPath.description,
                        agentStatus: await status(for: metadata.id),
                        lastTaskMessage: await agentLastTaskMessage(metadata.id.description)
                    ))
                }
            }
            return Self.jsonOutput(callID: callID, value: ListAgentsToolResult(agents: agents), success: true)
        } catch let error as AppServerLiveMultiAgentToolError {
            return Self.output(callID: callID, content: error.message, success: false)
        } catch {
            return Self.output(callID: callID, content: String(describing: error), success: false)
        }
    }

    private func resolvedListPrefix(_ pathPrefix: String?) throws -> AgentPath? {
        guard let pathPrefix else {
            return nil
        }
        let currentAgentPath = currentSessionSource.agentPath ?? .root
        do {
            return try currentAgentPath.resolve(pathPrefix)
        } catch {
            throw AppServerLiveMultiAgentToolError(message: String(describing: error))
        }
    }

    private func resolveAgentTarget(_ target: String) async throws -> ResolvedLiveAgentTarget {
        if let threadID = try? ThreadId(string: target) {
            let metadata = try await stateStore?.getThread(threadID: threadID)
            return ResolvedLiveAgentTarget(threadID: threadID, metadata: metadata)
        }

        let currentAgentPath = currentSessionSource.agentPath ?? .root
        let agentPath: AgentPath
        do {
            agentPath = try currentAgentPath.resolve(target)
        } catch {
            throw AppServerLiveMultiAgentToolError(message: String(describing: error))
        }
        guard let stateStore else {
            throw AppServerLiveMultiAgentToolError(message: "live agent path `\(agentPath)` not found")
        }
        guard let threadID = try await stateStore.findThreadByAgentPath(agentPath: agentPath) else {
            throw AppServerLiveMultiAgentToolError(message: "live agent path `\(agentPath)` not found")
        }
        let metadata = try await stateStore.getThread(threadID: threadID)
        return ResolvedLiveAgentTarget(threadID: threadID, metadata: metadata)
    }

    private func status(for threadID: ThreadId) async -> AgentStatus {
        await agentStatus(threadID.description)
    }

    private static func agentPath(_ agentPath: AgentPath, matchesPrefix prefix: AgentPath?) -> Bool {
        guard let prefix else {
            return true
        }
        if agentPath == prefix {
            return true
        }
        return agentPath.description.hasPrefix("\(prefix.description)/")
    }

    private static func output(
        callID: String,
        content: String,
        success: Bool?,
        runtimeEvents: [EventMessage] = []
    ) -> NonInteractiveExec.FunctionCallExecutionResult {
        NonInteractiveExec.FunctionCallExecutionResult(
            output: .functionCallOutput(
                callID: callID,
                output: FunctionCallOutputPayload(content: content, success: success)
            ),
            runtimeEvents: runtimeEvents
        )
    }

    private static func jsonOutput<T: Encodable>(
        callID: String,
        value: T,
        success: Bool?,
        runtimeEvents: [EventMessage] = []
    ) -> NonInteractiveExec.FunctionCallExecutionResult {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            return output(
                callID: callID,
                content: String(decoding: try encoder.encode(value), as: UTF8.self),
                success: success,
                runtimeEvents: runtimeEvents
            )
        } catch {
            return output(
                callID: callID,
                content: "failed to encode list_agents result: \(error)",
                success: false
            )
        }
    }
}

struct MultiAgentV2WaitTimeouts: Equatable, Sendable {
    let min: Int64
    let max: Int64
    let `default`: Int64

    init(config: MultiAgentV2Config) {
        self.min = config.minWaitTimeoutMS
        self.max = config.maxWaitTimeoutMS
        self.default = config.defaultWaitTimeoutMS
    }
}

struct LiveSpawnAgentRequest: Equatable, Sendable {
    let callID: String
    let message: String
    let taskName: String
    let agentType: String?
    let model: String?
    let reasoningEffort: ReasoningEffort?
    let serviceTier: String?
    let forkMode: LiveSpawnAgentForkMode
    let childAgentPath: AgentPath
}

struct LiveSpawnAgentResult: Equatable, Sendable {
    let threadID: ThreadId
    let agentPath: AgentPath
    let nickname: String?
    let role: String?
    let model: String?
    let reasoningEffort: ReasoningEffort?
    let status: AgentStatus
}

enum LiveSpawnAgentForkMode: Equatable, Sendable {
    case none
    case fullHistory
    case lastNTurns(Int)

    func initialHistory(from parentHistory: InitialHistory) -> InitialHistory {
        switch self {
        case .none:
            return .forked([])
        case .fullHistory:
            return parentHistory
        case let .lastNTurns(count):
            return .forked(
                RolloutTruncation.truncateToLastNForkTurns(
                    parentHistory.rolloutItems,
                    nFromEnd: count
                )
            )
        }
    }
}

private struct SpawnAgentToolArguments: Decodable {
    let message: String
    let taskName: String
    let agentType: String?
    let model: String?
    let reasoningEffort: ReasoningEffort?
    let serviceTier: String?
    let forkTurns: String?
    let forkContext: Bool?

    private enum CodingKeys: String, CodingKey {
        case message
        case taskName = "task_name"
        case agentType = "agent_type"
        case model
        case reasoningEffort = "reasoning_effort"
        case serviceTier = "service_tier"
        case forkTurns = "fork_turns"
        case forkContext = "fork_context"
    }

    func resolvedForkMode() throws -> LiveSpawnAgentForkMode {
        if forkContext != nil {
            throw AppServerLiveMultiAgentToolError(
                message: "fork_context is not supported in MultiAgentV2; use fork_turns instead"
            )
        }

        let value = forkTurns?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
            ?? "all"
        if value.caseInsensitiveCompare("none") == .orderedSame {
            return .none
        }
        if value.caseInsensitiveCompare("all") == .orderedSame {
            return .fullHistory
        }
        guard let count = Int(value), count > 0 else {
            throw AppServerLiveMultiAgentToolError(
                message: "fork_turns must be `none`, `all`, or a positive integer string"
            )
        }
        return .lastNTurns(count)
    }
}

private struct AgentMessageToolArguments: Decodable {
    let target: String
    let message: String
}

private struct ListAgentsToolArguments: Decodable {
    let pathPrefix: String?

    private enum CodingKeys: String, CodingKey {
        case pathPrefix = "path_prefix"
    }
}

private struct WaitAgentToolArguments: Decodable {
    let timeoutMS: Int64?

    private enum CodingKeys: String, CodingKey {
        case timeoutMS = "timeout_ms"
    }
}

private struct CloseAgentToolArguments: Decodable {
    let target: String
}

private struct WaitAgentToolResult: Encodable, Equatable {
    let message: String
    let timedOut: Bool

    init(timedOut: Bool) {
        self.timedOut = timedOut
        self.message = timedOut ? "Wait timed out." : "Wait completed."
    }

    private enum CodingKeys: String, CodingKey {
        case message
        case timedOut = "timed_out"
    }
}

private struct CloseAgentToolResult: Encodable, Equatable {
    let previousStatus: AgentStatus

    private enum CodingKeys: String, CodingKey {
        case previousStatus = "previous_status"
    }
}

private struct SpawnAgentToolResult: Encodable, Equatable {
    let taskName: String
    let nickname: String?
    let hidesMetadata: Bool

    private enum CodingKeys: String, CodingKey {
        case taskName = "task_name"
        case nickname
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(taskName, forKey: .taskName)
        if !hidesMetadata {
            try container.encodeIfPresent(nickname, forKey: .nickname)
        }
    }
}

private struct ListAgentsToolResult: Encodable {
    let agents: [ListedLiveAgent]
}

private struct ListedLiveAgent: Encodable, Equatable {
    let agentName: String
    let agentStatus: AgentStatus
    let lastTaskMessage: String?

    private enum CodingKeys: String, CodingKey {
        case agentName = "agent_name"
        case agentStatus = "agent_status"
        case lastTaskMessage = "last_task_message"
    }
}

private struct ResolvedLiveAgentTarget {
    let threadID: ThreadId
    let metadata: ThreadMetadata?

    var agentPath: AgentPath? {
        guard let rawPath = metadata?.agentPath else {
            return nil
        }
        return try? AgentPath(validating: rawPath)
    }
}

struct AppServerLiveMultiAgentToolError: Error {
    let message: String
}

private enum AppServerLiveMultiAgentToolClock {
    static func millisecondsSinceEpoch() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000).rounded())
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
