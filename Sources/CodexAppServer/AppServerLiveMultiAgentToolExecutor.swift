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
                serviceTier: $0.serviceTier
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

        do {
            let result = try await spawnAgent(LiveSpawnAgentRequest(
                callID: callID,
                message: prompt,
                taskName: args.taskName,
                agentType: resolvedOverrides.agentType,
                model: resolvedOverrides.model,
                reasoningEffort: resolvedOverrides.reasoningEffort,
                serviceTier: resolvedOverrides.serviceTier,
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
}

struct LiveSpawnAgentRoleConfigOverrides: Equatable, Sendable {
    let model: String?
    let reasoningEffort: ReasoningEffort?
    let serviceTier: String?
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
            serviceTier: resolvedServiceTier
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
                serviceTier: try optionalString(table["service_tier"])
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

    private static func optionalReasoningEffort(_ value: ConfigValue?) throws -> ReasoningEffort? {
        guard let rawValue = try optionalString(value) else {
            return nil
        }
        guard let effort = ReasoningEffort(rawValue: rawValue) else {
            throw roleUnavailableError()
        }
        return effort
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
