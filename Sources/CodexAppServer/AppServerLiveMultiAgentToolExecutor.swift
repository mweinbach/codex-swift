import Foundation
import CodexCore

struct AppServerLiveMultiAgentToolExecutor {
    let currentThreadID: ThreadId
    let currentSessionSource: SessionSource
    let stateStore: SQLiteAgentGraphStore?
    let waitTimeouts: MultiAgentV2WaitTimeouts
    let hideSpawnAgentMetadata: Bool
    let resolveSpawnAgentOverrides: @Sendable (LiveSpawnAgentOverrideRequest) async throws -> LiveSpawnAgentResolvedOverrides
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
        resolveSpawnAgentOverrides: @escaping @Sendable (LiveSpawnAgentOverrideRequest) async throws -> LiveSpawnAgentResolvedOverrides = {
            LiveSpawnAgentResolvedOverrides(
                agentType: $0.agentType,
                model: $0.model,
                reasoningEffort: $0.reasoningEffort,
                serviceTier: $0.serviceTier,
                developerInstructions: nil,
                reasoningSummary: nil,
                verbosity: nil,
                compactPrompt: nil,
                modelProvider: nil,
                modelContextWindow: nil,
                modelAutoCompactTokenLimit: nil,
                toolOutputTokenLimit: nil
            )
        },
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
        self.resolveSpawnAgentOverrides = resolveSpawnAgentOverrides
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
            return Self.output(
                callID: callID,
                content: "failed to parse function arguments: \(Self.toolArgumentParseDescription(error))",
                success: false
            )
        }

        let forkMode: LiveSpawnAgentForkMode
        do {
            forkMode = try args.resolvedForkMode()
        } catch let error as AppServerLiveMultiAgentToolError {
            return Self.output(callID: callID, content: error.message, success: false)
        } catch {
            return Self.output(callID: callID, content: String(describing: error), success: false)
        }

        let prompt = args.message
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Self.output(callID: callID, content: "Empty message can't be sent to an agent", success: false)
        }

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
        let agentType = args.agentType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        if forkMode == .fullHistory,
           agentType != nil || args.model != nil || args.reasoningEffort != nil
        {
            return Self.output(
                callID: callID,
                content: "Full-history forked agents inherit the parent agent type, model, and reasoning effort; omit agent_type, model, and reasoning_effort, or spawn without a full-history fork.",
                success: false,
                runtimeEvents: runtimeEvents
            )
        }

        let resolvedOverrides: LiveSpawnAgentResolvedOverrides
        do {
            resolvedOverrides = try await resolveSpawnAgentOverrides(LiveSpawnAgentOverrideRequest(
                agentType: agentType,
                model: args.model,
                reasoningEffort: args.reasoningEffort,
                serviceTier: args.serviceTier,
                forkMode: forkMode
            ))
        } catch let error as AppServerLiveMultiAgentToolError {
            return Self.output(
                callID: callID,
                content: error.message,
                success: false,
                runtimeEvents: runtimeEvents
            )
        } catch {
            return Self.output(
                callID: callID,
                content: String(describing: error),
                success: false,
                runtimeEvents: runtimeEvents
            )
        }

        let currentAgentPath = currentSessionSource.agentPath ?? .root
        let childAgentPath: AgentPath
        do {
            childAgentPath = try currentAgentPath.join(args.taskName)
        } catch {
            return Self.output(
                callID: callID,
                content: String(describing: error),
                success: false,
                runtimeEvents: runtimeEvents
            )
        }

        do {
            let result = try await spawnAgent(LiveSpawnAgentRequest(
                callID: callID,
                message: prompt,
                taskName: args.taskName,
                agentType: resolvedOverrides.agentType,
                model: resolvedOverrides.model,
                reasoningEffort: resolvedOverrides.reasoningEffort,
                serviceTier: resolvedOverrides.serviceTier,
                developerInstructions: resolvedOverrides.developerInstructions,
                reasoningSummary: resolvedOverrides.reasoningSummary,
                verbosity: resolvedOverrides.verbosity,
                compactPrompt: resolvedOverrides.compactPrompt,
                modelProvider: resolvedOverrides.modelProvider,
                modelContextWindow: resolvedOverrides.modelContextWindow,
                modelAutoCompactTokenLimit: resolvedOverrides.modelAutoCompactTokenLimit,
                toolOutputTokenLimit: resolvedOverrides.toolOutputTokenLimit,
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
            guard let agentPath = result.agentPath else {
                return Self.output(
                    callID: callID,
                    content: "spawned agent is missing a canonical task name",
                    success: false,
                    runtimeEvents: runtimeEvents
                )
            }
            let output = SpawnAgentToolResult(
                taskName: agentPath.description,
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
            return Self.output(
                callID: callID,
                content: "failed to parse function arguments: \(Self.toolArgumentParseDescription(error))",
                success: false
            )
        }

        let prompt = args.message
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Self.output(callID: callID, content: "Empty message can't be sent to an agent", success: false)
        }

        do {
            let target = try await resolveAgentTarget(args.target)
            let receiverAgentPath = target.agentPath
            if triggerTurn, receiverAgentPath?.isRoot == true {
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
            guard let receiverAgentPath else {
                return Self.output(
                    callID: callID,
                    content: "target agent is missing an agent_path",
                    success: false,
                    runtimeEvents: runtimeEvents
                )
            }
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

            let status = await status(for: target.threadID)
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
            return Self.output(
                callID: callID,
                content: "failed to parse function arguments: \(Self.toolArgumentParseDescription(error))",
                success: false
            )
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
            return Self.output(
                callID: callID,
                content: "failed to parse function arguments: \(Self.toolArgumentParseDescription(error))",
                success: false
            )
        }

        do {
            let target = try await resolveAgentTarget(args.target)
            if try await targetIsCurrentRootAgent(target) {
                return Self.output(callID: callID, content: "root is not a spawned agent", success: false)
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
            if target.metadata == nil, previousStatus == .notFound {
                runtimeEvents.append(.collabCloseEnd(CollabCloseEndEvent(
                    callID: callID,
                    completedAtMilliseconds: AppServerLiveMultiAgentToolClock.millisecondsSinceEpoch(),
                    senderThreadID: currentThreadID,
                    receiverThreadID: target.threadID,
                    status: previousStatus
                )))
                return Self.output(
                    callID: callID,
                    content: "agent with id \(target.threadID) not found",
                    success: false,
                    runtimeEvents: runtimeEvents
                )
            }
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
            return Self.output(
                callID: callID,
                content: "failed to parse function arguments: \(Self.toolArgumentParseDescription(error))",
                success: false
            )
        }

        do {
            let prefix = try resolvedListPrefix(args.pathPrefix)
            let rootPath = AgentPath.root
            var agents: [ListedLiveAgent] = []
            if Self.agentPath(rootPath, matchesPrefix: prefix) {
                let rootThreadID = try await rootThreadID()
                agents.append(ListedLiveAgent(
                    agentName: rootPath.description,
                    agentStatus: await status(for: rootThreadID),
                    lastTaskMessage: "Main thread"
                ))
            }
            if let stateStore {
                if prefix == nil {
                    let unnamedThreads = try await stateStore.listOpenThreadSpawnThreadsWithoutAgentPaths()
                    for metadata in unnamedThreads {
                        agents.append(ListedLiveAgent(
                            agentName: metadata.id.description,
                            agentStatus: await status(for: metadata.id),
                            lastTaskMessage: await agentLastTaskMessage(metadata.id.description)
                        ))
                    }
                }
                let threadMetadata = try await stateStore.listThreadsWithAgentPaths()
                for metadata in threadMetadata {
                    guard let rawPath = metadata.agentPath,
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
        if agentPath.isRoot {
            let threadID = try await rootThreadID()
            let metadata = try await stateStore.getThread(threadID: threadID)
            return ResolvedLiveAgentTarget(threadID: threadID, metadata: metadata, agentPathOverride: .root)
        }
        guard let threadID = try await stateStore.findOpenThreadByAgentPath(agentPath: agentPath) else {
            throw AppServerLiveMultiAgentToolError(message: "live agent path `\(agentPath)` not found")
        }
        let metadata = try await stateStore.getThread(threadID: threadID)
        return ResolvedLiveAgentTarget(threadID: threadID, metadata: metadata)
    }

    private func rootThreadID() async throws -> ThreadId {
        guard currentSessionSource.agentPath != nil else {
            return currentThreadID
        }
        if let stateStore,
           let rootThreadID = try await stateStore.findThreadSpawnRootAncestor(childThreadID: currentThreadID) {
            return rootThreadID
        }
        guard case let .subagent(.threadSpawn(parentThreadID, _, _, _, _)) = currentSessionSource else {
            return currentThreadID
        }
        return parentThreadID
    }

    private func targetIsCurrentRootAgent(_ target: ResolvedLiveAgentTarget) async throws -> Bool {
        if target.agentPath?.isRoot == true {
            return true
        }
        return target.threadID == (try await rootThreadID())
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

    private static func toolArgumentParseDescription(_ error: Error) -> String {
        switch error {
        case DecodingError.dataCorrupted(let context):
            return context.debugDescription
        case DecodingError.keyNotFound(let key, _):
            return "missing field `\(key.stringValue)`"
        case DecodingError.typeMismatch(_, let context),
             DecodingError.valueNotFound(_, let context):
            return context.debugDescription
        default:
            return String(describing: error)
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
    let developerInstructions: String?
    let reasoningSummary: ReasoningSummary?
    let verbosity: Verbosity?
    let compactPrompt: String?
    let modelProvider: String?
    let modelContextWindow: Int64?
    let modelAutoCompactTokenLimit: Int64?
    let toolOutputTokenLimit: Int?
    let forkMode: LiveSpawnAgentForkMode
    let childAgentPath: AgentPath
}

struct LiveSpawnAgentOverrideRequest: Equatable, Sendable {
    let agentType: String?
    let model: String?
    let reasoningEffort: ReasoningEffort?
    let serviceTier: String?
    let forkMode: LiveSpawnAgentForkMode
}

struct LiveSpawnAgentResolvedOverrides: Equatable, Sendable {
    let agentType: String?
    let model: String?
    let reasoningEffort: ReasoningEffort?
    let serviceTier: String?
    let developerInstructions: String?
    let reasoningSummary: ReasoningSummary?
    let verbosity: Verbosity?
    let compactPrompt: String?
    let modelProvider: String?
    let modelContextWindow: Int64?
    let modelAutoCompactTokenLimit: Int64?
    let toolOutputTokenLimit: Int?
}

struct LiveSpawnAgentRoleConfigOverrides: Equatable, Sendable {
    let model: String?
    let reasoningEffort: ReasoningEffort?
    let serviceTier: String?
    let developerInstructions: String?
    let reasoningSummary: ReasoningSummary?
    let verbosity: Verbosity?
    let compactPrompt: String?
    let modelProvider: String?
    let modelContextWindow: Int64?
    let modelAutoCompactTokenLimit: Int64?
    let toolOutputTokenLimit: Int?
}

struct LiveSpawnAgentOverrideResolver: Sendable {
    let availableModels: [ModelPreset]
    let currentModel: String
    let currentModelDefaultReasoningEffort: ReasoningEffort?
    let parentServiceTier: String?
    let configuredAgentRoles: Set<String>
    let roleConfigOverrides: [String: LiveSpawnAgentRoleConfigOverrides]

    init(
        availableModels: [ModelPreset],
        currentModel: String,
        currentModelDefaultReasoningEffort: ReasoningEffort?,
        parentServiceTier: String?,
        configuredAgentRoles: Set<String>,
        roleConfigOverrides: [String: LiveSpawnAgentRoleConfigOverrides] = [:]
    ) {
        self.availableModels = availableModels
        self.currentModel = currentModel
        self.currentModelDefaultReasoningEffort = currentModelDefaultReasoningEffort
        self.parentServiceTier = parentServiceTier
        self.configuredAgentRoles = configuredAgentRoles
        self.roleConfigOverrides = roleConfigOverrides
    }

    func resolve(_ request: LiveSpawnAgentOverrideRequest) throws -> LiveSpawnAgentResolvedOverrides {
        if let agentType = request.agentType {
            let builtinRoles: Set<String> = ["default", "explorer", "worker"]
            guard configuredAgentRoles.contains(agentType) || builtinRoles.contains(agentType) else {
                throw AppServerLiveMultiAgentToolError(message: "unknown agent_type '\(agentType)'")
            }
        }

        var selectedModel: ModelPreset
        let resolvedModel: String?
        var resolvedReasoningEffort: ReasoningEffort?
        if let requestedModel = request.model {
            guard let model = availableModels.first(where: { $0.model == requestedModel }) else {
                let available = availableModels.map(\.model).joined(separator: ", ")
                throw AppServerLiveMultiAgentToolError(
                    message: "Unknown model `\(requestedModel)` for spawn_agent. Available models: \(available)"
                )
            }
            try Self.validateReasoningEffort(request.reasoningEffort, model: model)
            selectedModel = model
            resolvedModel = requestedModel
            resolvedReasoningEffort = request.reasoningEffort ?? model.defaultReasoningEffort
        } else {
            selectedModel = availableModels.first(where: { $0.model == currentModel })
                ?? ModelPreset(
                    id: currentModel,
                    model: currentModel,
                    displayName: currentModel,
                    description: currentModel,
                    defaultReasoningEffort: currentModelDefaultReasoningEffort ?? .medium,
                    supportedReasoningEfforts: ReasoningEffort.allCases.map {
                        ReasoningEffortPreset(effort: $0, description: "")
                    },
                    isDefault: false,
                    showInPicker: false,
                    supportedInAPI: true
                )
            try Self.validateReasoningEffort(request.reasoningEffort, model: selectedModel)
            resolvedModel = nil
            resolvedReasoningEffort = request.reasoningEffort
        }

        var roleResolvedModel = resolvedModel
        var roleServiceTier: String?
        var roleDeveloperInstructions: String?
        var roleReasoningSummary: ReasoningSummary?
        var roleVerbosity: Verbosity?
        var roleCompactPrompt: String?
        var roleModelProvider: String?
        var roleModelContextWindow: Int64?
        var roleModelAutoCompactTokenLimit: Int64?
        var roleToolOutputTokenLimit: Int?
        if let agentType = request.agentType,
           let overrides = roleConfigOverrides[agentType] {
            if let roleModel = overrides.model {
                guard let model = availableModels.first(where: { $0.model == roleModel }) else {
                    throw Self.roleUnavailableError()
                }
                selectedModel = model
                roleResolvedModel = roleModel == currentModel ? nil : roleModel
            }
            if let roleReasoningEffort = overrides.reasoningEffort {
                resolvedReasoningEffort = roleReasoningEffort
            }
            roleServiceTier = overrides.serviceTier
            roleDeveloperInstructions = overrides.developerInstructions
            roleReasoningSummary = overrides.reasoningSummary
            roleVerbosity = overrides.verbosity
            roleCompactPrompt = overrides.compactPrompt
            roleModelProvider = overrides.modelProvider
            roleModelContextWindow = overrides.modelContextWindow
            roleModelAutoCompactTokenLimit = overrides.modelAutoCompactTokenLimit
            roleToolOutputTokenLimit = overrides.toolOutputTokenLimit
            try Self.validateReasoningEffort(resolvedReasoningEffort, model: selectedModel)
        }

        let resolvedServiceTier = try resolveServiceTier(
            requestedServiceTier: request.serviceTier,
            roleServiceTier: roleServiceTier,
            model: selectedModel
        )
        return LiveSpawnAgentResolvedOverrides(
            agentType: request.agentType,
            model: roleResolvedModel,
            reasoningEffort: resolvedReasoningEffort,
            serviceTier: resolvedServiceTier,
            developerInstructions: roleDeveloperInstructions,
            reasoningSummary: roleReasoningSummary,
            verbosity: roleVerbosity,
            compactPrompt: roleCompactPrompt,
            modelProvider: roleModelProvider,
            modelContextWindow: roleModelContextWindow,
            modelAutoCompactTokenLimit: roleModelAutoCompactTokenLimit,
            toolOutputTokenLimit: roleToolOutputTokenLimit
        )
    }

    static func roleConfigOverrides(
        configuredAgentRoles: [String: AgentRoleConfig],
        fileManager: FileManager = .default
    ) throws -> [String: LiveSpawnAgentRoleConfigOverrides] {
        var overrides: [String: LiveSpawnAgentRoleConfigOverrides] = [:]
        for (roleName, roleConfig) in configuredAgentRoles {
            guard let configFile = roleConfig.configFile else {
                continue
            }
            let configValue: ConfigValue
            do {
                configValue = try CodexConfigLayerLoader.readConfig(
                    from: URL(fileURLWithPath: configFile, isDirectory: false),
                    fileManager: fileManager
                ) ?? .table([:])
            } catch {
                throw roleUnavailableError()
            }
            guard case let .table(table) = configValue else {
                throw roleUnavailableError()
            }
            overrides[roleName] = try roleConfigOverrides(from: table)
        }
        return overrides
    }

    private static func roleConfigOverrides(from table: [String: ConfigValue]) throws -> LiveSpawnAgentRoleConfigOverrides {
        do {
            return LiveSpawnAgentRoleConfigOverrides(
                model: try optionalString(table["model"]),
                reasoningEffort: try optionalReasoningEffort(table["model_reasoning_effort"]),
                serviceTier: try optionalString(table["service_tier"]),
                developerInstructions: try optionalString(table["developer_instructions"]),
                reasoningSummary: try optionalReasoningSummary(table["model_reasoning_summary"]),
                verbosity: try optionalVerbosity(table["model_verbosity"]),
                compactPrompt: try optionalString(table["compact_prompt"]),
                modelProvider: try optionalString(table["model_provider"]),
                modelContextWindow: try optionalInt64(table["model_context_window"]),
                modelAutoCompactTokenLimit: try optionalInt64(table["model_auto_compact_token_limit"]),
                toolOutputTokenLimit: try optionalNonNegativeInt(table["tool_output_token_limit"])
            )
        } catch {
            throw roleUnavailableError()
        }
    }

    private static func optionalString(_ value: ConfigValue?) throws -> String? {
        guard let value else {
            return nil
        }
        guard case let .string(string) = value else {
            throw roleUnavailableError()
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func optionalInt64(_ value: ConfigValue?) throws -> Int64? {
        guard let value else {
            return nil
        }
        guard case let .integer(integer) = value else {
            throw roleUnavailableError()
        }
        return integer
    }

    private static func optionalNonNegativeInt(_ value: ConfigValue?) throws -> Int? {
        guard let integer = try optionalInt64(value),
              integer >= 0,
              integer <= Int64(Int.max)
        else {
            if value == nil {
                return nil
            }
            throw roleUnavailableError()
        }
        return Int(integer)
    }

    private static func optionalReasoningEffort(_ value: ConfigValue?) throws -> ReasoningEffort? {
        guard let rawValue = try optionalString(value) else {
            return nil
        }
        guard let effort = ReasoningEffort(rawValue: rawValue) else {
            throw roleUnavailableError()
        }
        return effort
    }

    private static func optionalReasoningSummary(_ value: ConfigValue?) throws -> ReasoningSummary? {
        guard let rawValue = try optionalString(value) else {
            return nil
        }
        guard let summary = ReasoningSummary(rawValue: rawValue) else {
            throw roleUnavailableError()
        }
        return summary
    }

    private static func optionalVerbosity(_ value: ConfigValue?) throws -> Verbosity? {
        guard let rawValue = try optionalString(value) else {
            return nil
        }
        guard let verbosity = Verbosity(rawValue: rawValue) else {
            throw roleUnavailableError()
        }
        return verbosity
    }

    private static func roleUnavailableError() -> AppServerLiveMultiAgentToolError {
        AppServerLiveMultiAgentToolError(message: "agent type is currently not available")
    }

    private static func validateReasoningEffort(
        _ reasoningEffort: ReasoningEffort?,
        model: ModelPreset
    ) throws {
        guard let reasoningEffort else {
            return
        }
        if model.supportedReasoningEfforts.contains(where: { $0.effort == reasoningEffort }) {
            return
        }
        let supported = model.supportedReasoningEfforts
            .map { $0.effort.rawValue }
            .joined(separator: ", ")
        throw AppServerLiveMultiAgentToolError(
            message: "Reasoning effort `\(reasoningEffort.rawValue)` is not supported for model `\(model.model)`. Supported reasoning efforts: \(supported)"
        )
    }

    private func resolveServiceTier(
        requestedServiceTier: String?,
        roleServiceTier: String?,
        model: ModelPreset
    ) throws -> String? {
        guard let candidateServiceTier = requestedServiceTier ?? parentServiceTier else {
            return roleServiceTier
        }
        if model.serviceTiers.contains(where: { $0.id == candidateServiceTier }) {
            return candidateServiceTier
        }
        guard requestedServiceTier != nil else {
            return nil
        }
        let supportedServiceTiers = model.serviceTiers.isEmpty
            ? "none"
            : model.serviceTiers.map(\.id).joined(separator: ", ")
        throw AppServerLiveMultiAgentToolError(
            message: "Service tier `\(candidateServiceTier)` is not supported for model `\(model.model)`. Supported service tiers: \(supportedServiceTiers)"
        )
    }
}

struct LiveSpawnAgentResult: Equatable, Sendable {
    let threadID: ThreadId
    let agentPath: AgentPath?
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

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case message
        case taskName = "task_name"
        case agentType = "agent_type"
        case model
        case reasoningEffort = "reasoning_effort"
        case serviceTier = "service_tier"
        case forkTurns = "fork_turns"
        case forkContext = "fork_context"
    }

    init(from decoder: Decoder) throws {
        try StrictToolArgumentFields.rejectUnknownFields(
            in: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.stringValue)),
            expected: "`message`, `task_name`, `agent_type`, `model`, `reasoning_effort`, `service_tier`, `fork_turns`, or `fork_context`"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decode(String.self, forKey: .message)
        taskName = try container.decode(String.self, forKey: .taskName)
        agentType = try container.decodeIfPresent(String.self, forKey: .agentType)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        reasoningEffort = try container.decodeIfPresent(ReasoningEffort.self, forKey: .reasoningEffort)
        serviceTier = try container.decodeIfPresent(String.self, forKey: .serviceTier)
        forkTurns = try container.decodeIfPresent(String.self, forKey: .forkTurns)
        forkContext = try container.decodeIfPresent(Bool.self, forKey: .forkContext)
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

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case target
        case message
    }

    init(from decoder: Decoder) throws {
        try StrictToolArgumentFields.rejectUnknownFields(
            in: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.stringValue)),
            expected: "`target` or `message`"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        target = try container.decode(String.self, forKey: .target)
        message = try container.decode(String.self, forKey: .message)
    }
}

private struct ListAgentsToolArguments: Decodable {
    let pathPrefix: String?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case pathPrefix = "path_prefix"
    }

    init(from decoder: Decoder) throws {
        try StrictToolArgumentFields.rejectUnknownFields(
            in: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.stringValue)),
            expected: "`path_prefix`"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pathPrefix = try container.decodeIfPresent(String.self, forKey: .pathPrefix)
    }
}

private struct WaitAgentToolArguments: Decodable {
    let timeoutMS: Int64?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case timeoutMS = "timeout_ms"
    }

    init(from decoder: Decoder) throws {
        try StrictToolArgumentFields.rejectUnknownFields(
            in: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.stringValue)),
            expected: "`timeout_ms`"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timeoutMS = try container.decodeIfPresent(Int64.self, forKey: .timeoutMS)
    }
}

private struct CloseAgentToolArguments: Decodable {
    let target: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case target
    }

    init(from decoder: Decoder) throws {
        try StrictToolArgumentFields.rejectUnknownFields(
            in: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.stringValue)),
            expected: "`target`"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        target = try container.decode(String.self, forKey: .target)
    }
}

private enum StrictToolArgumentFields {
    static func rejectUnknownFields(
        in decoder: Decoder,
        allowedKeys: Set<String>,
        expected: String
    ) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        guard let unknown = container.allKeys.first(where: { !allowedKeys.contains($0.stringValue) }) else {
            return
        }
        throw DecodingError.dataCorrupted(DecodingError.Context(
            codingPath: decoder.codingPath,
            debugDescription: "unknown field `\(unknown.stringValue)`, expected \(expected)"
        ))
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
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
    var agentPathOverride: AgentPath?

    var agentPath: AgentPath? {
        if let agentPathOverride {
            return agentPathOverride
        }
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
