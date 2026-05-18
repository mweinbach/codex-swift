import CodexCore
import Foundation

public typealias AppServerRuntimeEventSink = @Sendable (
    _ threadID: String,
    _ turnID: String,
    _ event: EventMessage
) async -> Void

/// Owns live app-server thread execution.
///
/// Normal app-server transports pass this manager into `CodexAppServerMessageProcessor`
/// as the core-op and live-runtime submitter. The processor remains responsible
/// for JSON-RPC validation and notification projection; this manager owns the
/// running-turn task, cancellation, approval continuations, and the bridge into
/// the Swift Responses/tool loop.
public protocol AppServerRuntimeManaging: AnyObject, Sendable {
    func setEventSink(_ sink: AppServerRuntimeEventSink?)
    func submitCoreOp(requestID: RequestID, threadID: String, op: Op) throws -> String
    func submitLiveRuntime(_ submission: AppServerLiveRuntimeSubmission) throws -> [EventMessage]
    func queueResponseItemsForNextTurn(threadID: String, items: [ResponseInputItem])
    func queueMailboxCommunications(threadID: String, communications: [InterAgentCommunication])
    func shutdown()
}

public final class AppServerLiveRuntimeManager: AppServerRuntimeManaging, @unchecked Sendable {
    private let configuration: CodexAppServerConfiguration
    private let state = AppServerLiveRuntimeState()
    private let commandAuthRunner = ProviderAuthCommandRunner()

    public init(configuration: CodexAppServerConfiguration) {
        self.configuration = configuration
    }

    public func setEventSink(_ sink: AppServerRuntimeEventSink?) {
        AppServerLiveRuntimeBlocking.run {
            await self.state.setEventSink(sink)
        }
    }

    public func submitCoreOp(requestID: RequestID, threadID: String, op: Op) throws -> String {
        switch op {
        case .userInput, .userInputWithTurnContext, .userTurn:
            let turnInput = try LiveTurnInput(op: op)
            if !turnInput.items.isEmpty {
                let inputItem = ResponseInputItem(userInputs: turnInput.items)
                AppServerLiveRuntimeBlocking.run {
                    await self.state.queuePendingInputForCurrentTurn(
                        threadID: threadID,
                        items: [inputItem]
                    )
                }
            }
            return UUID().uuidString.lowercased()

        case .interrupt:
            let cancelledTurnID = AppServerLiveRuntimeBlocking.run {
                await self.state.cancelTurn(threadID: threadID)
            }
            if let turnID = cancelledTurnID {
                Task { [state] in
                    if await state.markAbortEmitted(threadID: threadID, turnID: turnID) {
                        await state.emit(
                            threadID: threadID,
                            turnID: turnID,
                            event: .turnAborted(TurnAbortedEvent(
                                turnID: turnID,
                                reason: .interrupted,
                                completedAt: AppServerLiveRuntimeClock.millisecondsSinceEpoch()
                            ))
                        )
                    }
                }
            }
            return UUID().uuidString.lowercased()

        case let .execApproval(id, _, decision),
            let .patchApproval(id, decision):
            AppServerLiveRuntimeBlocking.run {
                await self.state.resolveApproval(id: id, decision: decision)
            }
            return UUID().uuidString.lowercased()

        case let .requestPermissionsResponse(id, response):
            AppServerLiveRuntimeBlocking.run {
                await self.state.resolvePermissions(id: id, response: response)
            }
            return UUID().uuidString.lowercased()

        case let .userInputAnswer(id, response):
            AppServerLiveRuntimeBlocking.run {
                await self.state.resolveUserInput(id: id, response: response)
            }
            return UUID().uuidString.lowercased()

        case let .dynamicToolResponse(id, response):
            AppServerLiveRuntimeBlocking.run {
                await self.state.resolveDynamicTool(id: id, response: response)
            }
            return UUID().uuidString.lowercased()

        case .shutdown:
            AppServerLiveRuntimeBlocking.run {
                await self.state.cancelThread(threadID: threadID)
            }
            return UUID().uuidString.lowercased()

        case let .refreshRuntimeConfig(config):
            AppServerLiveRuntimeBlocking.run {
                await self.state.refreshRuntimeConfig(threadID: threadID, config: config)
            }
            return UUID().uuidString.lowercased()

        case .refreshMcpServers,
             .addToHistory,
             .compact,
             .threadRollback,
             .cleanBackgroundTerminals,
             .setThreadMemoryMode,
             .runUserShellCommand,
             .approveGuardianDeniedAction,
             .reloadUserConfig,
             .getHistoryEntryRequest,
             .listCustomPrompts,
             .undo,
             .review,
             .interAgentCommunication,
             .overrideTurnContext,
             .resolveElicitation,
             .realtimeConversationStart,
             .realtimeConversationAudio,
             .realtimeConversationText,
             .realtimeConversationClose,
             .realtimeConversationListVoices:
            return UUID().uuidString.lowercased()
        }
    }

    public func submitLiveRuntime(_ submission: AppServerLiveRuntimeSubmission) throws -> [EventMessage] {
        switch submission.op {
        case .userInput, .userInputWithTurnContext, .userTurn:
            let startGate = AppServerLiveRuntimeStartGate()
            let task = Task { [weak self, startGate] in
                await startGate.wait()
                guard !Task.isCancelled else {
                    return
                }
                guard let self else {
                    return
                }
                await self.runTurn(submission)
            }
            AppServerLiveRuntimeBlocking.run {
                await self.state.startTurn(
                    threadID: submission.threadID,
                    turnID: submission.turnID,
                    task: task
                )
                await startGate.open()
            }
            return []

        case let .interAgentCommunication(communication):
            AppServerLiveRuntimeBlocking.run {
                await self.state.queueMailboxCommunications(
                    threadID: submission.threadID,
                    communications: [communication]
                )
                if communication.triggerTurn {
                    _ = await self.submitPendingWorkTurnIfIdle(
                        threadID: submission.threadID,
                        prototype: submission
                    )
                }
            }
            return []

        default:
            return []
        }
    }

    public func queueResponseItemsForNextTurn(threadID: String, items: [ResponseInputItem]) {
        AppServerLiveRuntimeBlocking.run {
            await self.state.queueResponseItemsForNextTurn(threadID: threadID, items: items)
        }
    }

    public func queueMailboxCommunications(threadID: String, communications: [InterAgentCommunication]) {
        AppServerLiveRuntimeBlocking.run {
            await self.state.queueMailboxCommunications(threadID: threadID, communications: communications)
        }
    }

    func canStartGoalContinuation(threadID: String) async -> Bool {
        await state.canStartGoalContinuation(threadID: threadID)
    }

    func takeQueuedResponseItemsForNextTurn(threadID: String) async -> [ResponseInputItem] {
        await state.takeQueuedResponseItemsForNextTurn(threadID: threadID)
    }

    func takeMailboxCommunications(threadID: String) async -> [InterAgentCommunication] {
        await state.takeMailboxCommunications(threadID: threadID)
    }

    func takePendingInputForCurrentTurn(threadID: String) async -> [ResponseInputItem] {
        await state.takePendingInputForCurrentTurn(threadID: threadID)
    }

    func deferMailboxDeliveryToNextTurn(threadID: String) async {
        await state.deferMailboxDeliveryToNextTurn(threadID: threadID)
    }

    func acceptMailboxDeliveryForCurrentTurn(threadID: String) async {
        await state.acceptMailboxDeliveryForCurrentTurn(threadID: threadID)
    }

    func isTurnRunning(threadID: String) async -> Bool {
        await state.isTurnRunning(threadID: threadID)
    }

    func agentStatus(threadID: String) async -> AgentStatus {
        await state.agentStatus(threadID: threadID)
    }

    func recordSessionSource(threadID: String, source: SessionSource) async {
        await state.recordSessionSource(threadID: threadID, source: source)
    }

    func emitRuntimeEvent(threadID: String, turnID: String, event: EventMessage) async {
        await state.emit(threadID: threadID, turnID: turnID, event: event)
    }

    private func submitGoalContinuation(
        threadID: String,
        features: FeatureStates,
        collaborationModeKind: CollaborationModeKind?,
        prototype: AppServerLiveRuntimeSubmission
    ) async {
        guard await state.canStartGoalContinuation(threadID: threadID),
              let inputItems = await Self.liveGoalContinuationInputItems(
                stateStore: configuration.stateStore,
                features: features,
                threadID: threadID,
                collaborationModeKind: collaborationModeKind
              )
        else {
            return
        }
        let turnID = UUID().uuidString.lowercased()
        let startGate = AppServerLiveRuntimeStartGate()
        let submission = AppServerLiveRuntimeSubmission(
            requestID: .string("goal-continuation-\(turnID)"),
            threadID: threadID,
            turnID: turnID,
            op: Op.userInput(items: []),
            turnMetadataHeader: nil,
            mcpElicitationsAutoDeny: prototype.mcpElicitationsAutoDeny,
            mcpTools: prototype.mcpTools,
            mcpToolCallHandler: prototype.mcpToolCallHandler,
            extensionPromptFragments: prototype.extensionPromptFragments,
            extensionToolSpecs: prototype.extensionToolSpecs,
            extensionRegisteredToolExecutor: prototype.extensionRegisteredToolExecutor,
            extensionApprovalReviewer: prototype.extensionApprovalReviewer,
            additionalInputItems: inputItems
        )
        let task = Task { [weak self, startGate] in
            await startGate.wait()
            guard !Task.isCancelled else {
                return
            }
            guard let self else {
                return
            }
            await self.runTurn(submission)
        }
        guard await state.startTurnIfIdle(threadID: threadID, turnID: turnID, task: task) else {
            task.cancel()
            await startGate.open()
            return
        }
        let goalIsCurrent = await Self.liveGoalContinuationInputItems(
            stateStore: configuration.stateStore,
            features: features,
            threadID: threadID,
            collaborationModeKind: collaborationModeKind
        ) == inputItems
        guard goalIsCurrent else {
            await state.cancelTurnIfMatching(threadID: threadID, turnID: turnID)
            await startGate.open()
            return
        }
        await startGate.open()
    }

    public func shutdown() {
        AppServerLiveRuntimeBlocking.run {
            await self.state.cancelAll()
        }
    }

    private static func mcpToolInfos(from tools: [String: McpTool]) -> [McpToolInfo] {
        tools.compactMap { qualifiedName, tool in
            guard let split = McpToolName.splitQualifiedToolName(qualifiedName) else {
                return nil
            }
            return McpToolInfo(
                serverName: split.serverName,
                namespaceDescription: tool.namespaceDescription,
                tool: tool
            )
        }
    }

    private func runTurn(_ submission: AppServerLiveRuntimeSubmission) async {
        let startedAt = AppServerLiveRuntimeClock.millisecondsSinceEpoch()
        var goalAccounting: LiveThreadGoalAccountingSession?
        var goalContinuationFeatures: FeatureStates?
        var goalContinuationCollaborationModeKind: CollaborationModeKind?
        do {
            let setup = try await prepareTurn(submission)
            await state.recordSessionSource(threadID: submission.threadID, source: setup.sessionSource)
            goalContinuationFeatures = setup.settings.features
            goalContinuationCollaborationModeKind = setup.collaborationModeKind
            await state.emit(
                threadID: submission.threadID,
                turnID: submission.turnID,
                event: .taskStarted(TaskStartedEvent(
                    turnID: submission.turnID,
                    startedAt: startedAt,
                    modelContextWindow: setup.modelFamily.contextWindow.map { Int64($0) }
                ))
            )

            var prompt = setup.prompt
            let sessionStartHookInputCount = prompt.input.count
            let sessionStartOutcome = await NonInteractiveExec.runSessionStartHooks(
                handlers: setup.hookHandlers,
                prompt: &prompt,
                conversationID: setup.conversationID,
                cwd: setup.cwd,
                model: setup.model,
                approvalPolicy: setup.approvalPolicy,
                source: setup.sessionStartSource
            )
            let sessionStartItems = Array(prompt.input.dropFirst(sessionStartHookInputCount))
            if !sessionStartItems.isEmpty {
                try setup.recorder?.recordItems(sessionStartItems.map(RolloutRecordItem.responseItem))
            }
            guard !sessionStartOutcome.shouldStop else {
                await completeTurn(
                    submission: submission,
                    startedAt: startedAt,
                    recorder: setup.recorder,
                    lastAssistantMessage: sessionStartOutcome.stopReason
                )
                return
            }

            let userPromptSubmitHookInputCount = prompt.input.count
            let userPromptSubmitOutcome = await NonInteractiveExec.runUserPromptSubmitHooks(
                handlers: setup.hookHandlers,
                prompt: &prompt,
                userPrompt: setup.userPromptText,
                conversationID: setup.conversationID,
                turnID: submission.turnID,
                cwd: setup.cwd,
                model: setup.model,
                approvalPolicy: setup.approvalPolicy
            )
            let userPromptSubmitItems = Array(prompt.input.dropFirst(userPromptSubmitHookInputCount))
            if !userPromptSubmitItems.isEmpty {
                try setup.recorder?.recordItems(userPromptSubmitItems.map(RolloutRecordItem.responseItem))
            }
            guard !userPromptSubmitOutcome.shouldStop else {
                await completeTurn(
                    submission: submission,
                    startedAt: startedAt,
                    recorder: setup.recorder,
                    lastAssistantMessage: userPromptSubmitOutcome.stopReason
                )
                return
            }

            let goalAccountingSnapshot = await Self.liveThreadGoalAccountingSnapshot(
                stateStore: configuration.stateStore,
                features: setup.settings.features,
                threadID: submission.threadID,
                tokenUsage: TokenUsage()
            )
            let turnGoalAccounting = LiveThreadGoalAccountingSession(
                stateStore: configuration.stateStore,
                features: setup.settings.features,
                threadID: submission.threadID,
                snapshot: goalAccountingSnapshot,
                lastAccountingAtMilliseconds: startedAt
            )
            goalAccounting = turnGoalAccounting
            let loopResult = await runResponsesLoop(
                submission: submission,
                setup: setup,
                prompt: prompt,
                goalAccounting: turnGoalAccounting
            )
            try setup.recorder?.recordItems(loopResult.transcriptItems.map(RolloutRecordItem.responseItem))
            for item in loopResult.transcriptItems {
                if Task.isCancelled {
                    throw CancellationError()
                }
                await emitCompletedTurnItem(
                    item,
                    threadID: setup.conversationID,
                    turnID: submission.turnID
                )
            }
            if let goal = await turnGoalAccounting.accountTurnCompletion(
                tokenUsage: loopResult.tokenUsage,
                completedAtMilliseconds: AppServerLiveRuntimeClock.millisecondsSinceEpoch()
            ) {
                await state.emit(
                    threadID: submission.threadID,
                    turnID: submission.turnID,
                    event: .threadGoalUpdated(ThreadGoalUpdatedEvent(
                        threadID: goal.threadID,
                        turnID: submission.turnID,
                        goal: goal
                    ))
                )
            }
            try setup.recorder?.flush()
            await completeTurn(
                submission: submission,
                startedAt: startedAt,
                recorder: setup.recorder,
                lastAssistantMessage: Self.lastAssistantMessage(from: loopResult.transcriptItems)
            )
        } catch is CancellationError {
            let completedAt = AppServerLiveRuntimeClock.millisecondsSinceEpoch()
            if let goal = await goalAccounting?.accountInterruptBeforePause(
                tokenUsage: nil,
                completedAtMilliseconds: completedAt
            ) {
                await state.emit(
                    threadID: submission.threadID,
                    turnID: submission.turnID,
                    event: .threadGoalUpdated(ThreadGoalUpdatedEvent(
                        threadID: goal.threadID,
                        turnID: submission.turnID,
                        goal: goal
                    ))
                )
            }
            if await state.markAbortEmitted(threadID: submission.threadID, turnID: submission.turnID) {
                await state.emit(
                    threadID: submission.threadID,
                    turnID: submission.turnID,
                    event: .turnAborted(TurnAbortedEvent(
                        turnID: submission.turnID,
                        reason: .interrupted,
                        completedAt: completedAt,
                        durationMilliseconds: completedAt - startedAt
                    ))
                )
            }
        } catch {
            await state.emit(
                threadID: submission.threadID,
                turnID: submission.turnID,
                event: .error(ErrorEvent(message: String(describing: error)))
            )
            await completeTurn(
                submission: submission,
                startedAt: startedAt,
                recorder: nil,
                lastAssistantMessage: nil
            )
        }
        await state.finishTurn(threadID: submission.threadID, turnID: submission.turnID)
        if await submitPendingWorkTurnIfIdle(threadID: submission.threadID, prototype: submission) {
            return
        }
        if let goalContinuationFeatures {
            await submitGoalContinuation(
                threadID: submission.threadID,
                features: goalContinuationFeatures,
                collaborationModeKind: goalContinuationCollaborationModeKind,
                prototype: submission
            )
        }
    }

    private func submitPendingWorkTurnIfIdle(
        threadID: String,
        prototype: AppServerLiveRuntimeSubmission
    ) async -> Bool {
        let turnID = UUID().uuidString.lowercased()
        let startGate = AppServerLiveRuntimeStartGate()
        let submission = AppServerLiveRuntimeSubmission(
            requestID: .string("pending-work-\(turnID)"),
            threadID: threadID,
            turnID: turnID,
            op: Op.userInput(items: []),
            turnMetadataHeader: nil,
            mcpElicitationsAutoDeny: prototype.mcpElicitationsAutoDeny,
            mcpTools: prototype.mcpTools,
            mcpToolCallHandler: prototype.mcpToolCallHandler,
            extensionPromptFragments: prototype.extensionPromptFragments,
            extensionToolSpecs: prototype.extensionToolSpecs,
            extensionRegisteredToolExecutor: prototype.extensionRegisteredToolExecutor,
            extensionApprovalReviewer: prototype.extensionApprovalReviewer
        )
        let task = Task { [weak self, startGate] in
            await startGate.wait()
            guard !Task.isCancelled else {
                return
            }
            guard let self else {
                return
            }
            await self.runTurn(submission)
        }
        guard await state.startPendingWorkTurnIfIdle(threadID: threadID, turnID: turnID, task: task) else {
            task.cancel()
            await startGate.open()
            return false
        }
        await startGate.open()
        return true
    }

    private func prepareTurn(_ submission: AppServerLiveRuntimeSubmission) async throws -> PreparedLiveTurn {
        let conversationID = try ConversationId(string: submission.threadID)
        guard let rolloutPath = try RolloutListing.findConversationPathByIDString(
            codexHome: configuration.codexHome,
            idString: conversationID.description
        ) else {
            throw AppServerLiveRuntimeError("no rollout found for conversation id \(conversationID)")
        }
        let rolloutURL = URL(fileURLWithPath: rolloutPath)
        let initialHistory = try RolloutRecorder.getRolloutHistory(path: rolloutURL)
        let responseHistory = RolloutRecorder.reconstructResponseHistory(from: initialHistory.rolloutItems)
        let summary = try LiveRolloutSummary(
            items: initialHistory.rolloutItems,
            defaultProvider: configuration.defaultModelProvider
        )
        let turnInput = try LiveTurnInput(op: submission.op)
        let cwd = URL(fileURLWithPath: turnInput.cwd ?? summary.cwd, isDirectory: true)
        var settings = try CodexConfigLoader.load(
            codexHome: configuration.codexHome,
            cwd: cwd,
            overrides: configuration.cliConfigOverrides,
            threadConfigSources: configuration.threadConfigSources,
            managedConfigOverrides: configuration.configLayerOverrides,
            environment: configuration.environment
        )
        settings.modelProvider = summary.modelProvider
        if let requestedApprovalPolicy = turnInput.approvalPolicy {
            settings.approvalPolicy = requestedApprovalPolicy
        }
        if let requestedSandbox = turnInput.sandboxPolicy {
            settings.sandboxPolicy = requestedSandbox
        }
        if let requestedModel = turnInput.model {
            settings.model = requestedModel
        }
        if let requestedSummary = turnInput.summary {
            settings.modelReasoningSummary = requestedSummary
        }
        let runtimeRefreshSnapshot = await state.runtimeConfigSnapshot(threadID: submission.threadID)
        let refreshedConfigStack = try runtimeRefreshSnapshot.map {
            try AppServerRuntimeConfigRefresh.applyRuntimeRefreshableSnapshot(
                $0,
                to: &settings,
                codexHome: configuration.codexHome,
                cwd: cwd,
                environment: configuration.environment
            )
        }

        try await CodexAuthStorage.enforceLoginRestrictions(
            codexHome: configuration.codexHome,
            config: settings,
            environment: configuration.environment
        )

        let providerID = settings.selectedModelProviderID
        guard let providerInfo = settings.selectedModelProvider else {
            throw AppServerLiveRuntimeError("model provider `\(providerID)` not found")
        }
        guard providerInfo.wireAPI == WireAPI.responses else {
            throw AppServerLiveRuntimeError("app-server live runtime currently supports Responses API model providers only")
        }
        let authResolution = try await resolveAuth(settings: settings, providerInfo: providerInfo)
        let provider = providerInfo.toAPIProvider(
            authMode: authResolution.authMode,
            environment: configuration.environment
        )
        let model = turnInput.model
            ?? summary.model
            ?? settings.model
            ?? (authResolution.authMode?.isChatGPT == true
                ? ModelsManager.openAIDefaultChatGPTModel
                : ModelsManager.openAIDefaultAPIModel)
        let modelFamily = ModelsManager.constructModelFamilyOffline(
            model: model,
            configOverrides: settings.modelFamilyConfigOverrides
        )
        let approvalPolicy = turnInput.approvalPolicy ?? settings.approvalPolicy ?? .unlessTrusted
        let sandboxPolicy = turnInput.sandboxPolicy ?? settings.legacySandboxPolicy()
        let permissionProfile = turnInput.permissionProfile
            ?? settings.permissionProfile
            ?? PermissionProfile.fromLegacySandboxPolicyForCwd(sandboxPolicy, cwd: cwd.path)
        let shell = ShellResolver.defaultUserShell()
        let turnEnvironmentSelections = turnInput.environments ?? []
        let mcpToolInfos = Self.mcpToolInfos(from: submission.mcpTools)
        let configuredTools = NonInteractiveExec.toolSpecs(
            modelFamily: modelFamily,
            config: settings,
            sessionSource: summary.sessionSource,
            environmentMode: .fromCount(turnEnvironmentSelections.count),
            dynamicTools: summary.dynamicTools,
            mcpToolInfos: mcpToolInfos,
            mcpTools: submission.mcpTools
        )
        var input = NonInteractiveExec.makeInitialPromptInput(
            cwd: cwd,
            approvalPolicy: approvalPolicy,
            sandboxPolicy: sandboxPolicy,
            permissionProfile: permissionProfile,
            shell: shell,
            includeEnvironmentContext: settings.includeEnvironmentContext,
            includePermissionsInstructions: settings.includePermissionsInstructions,
            developerInstructions: settings.developerInstructions,
            memoryToolDeveloperInstructions: MemoryToolInstructions.build(
                codexHome: configuration.codexHome,
                config: settings
            ),
            multiAgentV2UsageHintText: settings.multiAgentV2.usageHintText(
                features: settings.features,
                sessionSource: configuration.sessionSource
            )
        )
        input.append(contentsOf: responseHistory)
        let queuedInputItems = await state.takeQueuedResponseItemsForNextTurn(threadID: submission.threadID)
        let mailboxInputItems = await state.takeMailboxCommunications(threadID: submission.threadID)
            .map { $0.toResponseInputItem() }
        var newInputItems: [ResponseItem] = (queuedInputItems + mailboxInputItems).map { $0.responseItem() }
        if !turnInput.items.isEmpty {
            newInputItems.append(ResponseInputItem(userInputs: turnInput.items).responseItem())
        }
        newInputItems.append(contentsOf: submission.additionalInputItems)
        input.append(contentsOf: newInputItems)
        let prompt = Prompt(
            input: input,
            tools: configuredTools.map { $0.spec } + submission.extensionToolSpecs.map { $0.spec },
            parallelToolCalls: modelFamily.supportsParallelToolCalls,
            outputSchema: turnInput.outputSchema
        )
        let recorder = try RolloutRecorder.resume(path: rolloutURL)
        try recorder.recordItems([
            .turnContext(TurnContextItem(
                cwd: cwd.path,
                approvalPolicy: approvalPolicy,
                sandboxPolicy: sandboxPolicy,
                model: model,
                collaborationMode: turnInput.collaborationMode,
                effort: settings.modelReasoningEffort ?? modelFamily.defaultReasoningEffort,
                summary: turnInput.summary
                    ?? settings.modelReasoningSummary
                    ?? (modelFamily.supportsReasoningSummaries ? .auto : .none),
                finalOutputJSONSchema: turnInput.outputSchema,
                truncationPolicy: modelFamily.truncationPolicy
            )),
        ] + newInputItems.map(RolloutRecordItem.responseItem))
        let hookConfigStack = try refreshedConfigStack ?? CodexConfigLayerLoader.loadConfigLayerStack(
            codexHome: configuration.codexHome,
            cwd: cwd,
            cliOverrides: configuration.cliConfigOverrides,
            threadConfigSources: configuration.threadConfigSources,
            overrides: configuration.configLayerOverrides,
            environment: configuration.environment
        )
        let hookHandlers = HookConfig.configuredHandlers(
            from: hookConfigStack,
            codexHome: configuration.codexHome,
            environment: configuration.environment
        )
        return PreparedLiveTurn(
            conversationID: conversationID,
            rolloutPath: rolloutURL,
            recorder: recorder,
            cwd: cwd,
            model: model,
            modelFamily: modelFamily,
            providerInfo: providerInfo,
            provider: provider,
            auth: authResolution.auth,
            authMode: authResolution.authMode,
            settings: settings,
            approvalPolicy: approvalPolicy,
            sandboxPolicy: sandboxPolicy,
            permissionProfile: permissionProfile,
            shell: shell,
            turnEnvironmentSelections: turnEnvironmentSelections,
            prompt: prompt,
            mcpToolInfos: mcpToolInfos,
            dynamicTools: summary.dynamicTools,
            sessionSource: summary.sessionSource,
            collaborationModeKind: turnInput.collaborationMode?.mode ?? summary.collaborationModeKind,
            userPromptText: turnInput.promptText,
            outputSchema: turnInput.outputSchema,
            serviceTier: turnInput.serviceTier ?? settings.serviceTier,
            metadata: turnInput.responsesAPIClientMetadata ?? [:],
            hookHandlers: hookHandlers,
            sessionStartSource: .resume
        )
    }

    private static func liveSpawnAgentAvailableModels(
        settings: CodexRuntimeConfig,
        authMode: AuthMode?
    ) -> [ModelPreset] {
        if let modelCatalog = settings.modelCatalog {
            return modelCatalog.models
                .sorted { $0.priority < $1.priority }
                .map(\.preset)
        }
        return ModelsManager.builtinModelPresets(authMode: authMode)
    }

    private func spawnLiveAgent(
        _ request: LiveSpawnAgentRequest,
        parentThreadID: ThreadId,
        parentSessionSource: SessionSource,
        setup: PreparedLiveTurn,
        prototype: AppServerLiveRuntimeSubmission
    ) async throws -> LiveSpawnAgentResult {
        let childConversationID = ConversationId()
        let childThreadID = try ThreadId(string: childConversationID.description)
        let childDepth = Self.nextThreadSpawnDepth(parentSessionSource)
        let childSource = SessionSource.subagent(.threadSpawn(
            parentThreadID: parentThreadID,
            depth: childDepth,
            agentPath: request.childAgentPath,
            agentNickname: nil,
            agentRole: request.agentType
        ))
        let childRollout: RolloutRecorder
        switch request.forkMode {
        case .none:
            childRollout = try RolloutRecorder.create(
                codexHome: configuration.codexHome,
                cwd: setup.cwd,
                conversationID: childConversationID,
                instructions: nil,
                source: childSource,
                forkedFromID: nil,
                threadSource: .subagent,
                originator: configuration.originator,
                cliVersion: configuration.version,
                modelProvider: setup.settings.modelProvider ?? configuration.defaultModelProvider,
                dynamicTools: setup.dynamicTools
            )

        case .fullHistory, .lastNTurns:
            let parentHistory = try RolloutRecorder.getRolloutHistory(path: setup.rolloutPath)
            childRollout = try RolloutRecorder.createFork(
                codexHome: configuration.codexHome,
                cwd: setup.cwd,
                conversationID: childConversationID,
                forkedFromID: setup.conversationID,
                initialHistory: request.forkMode.initialHistory(from: parentHistory),
                instructions: nil,
                source: childSource,
                threadSource: .subagent,
                originator: configuration.originator,
                cliVersion: configuration.version,
                modelProvider: setup.settings.modelProvider ?? configuration.defaultModelProvider,
                dynamicTools: setup.dynamicTools,
                usageHintTextsToFilter: Self.configuredMultiAgentV2UsageHintTexts(settings: setup.settings)
            )
        }

        try childRollout.recordItems([
            .turnContext(TurnContextItem(
                cwd: setup.cwd.path,
                approvalPolicy: setup.approvalPolicy,
                sandboxPolicy: setup.sandboxPolicy,
                model: request.model ?? setup.model,
                effort: request.reasoningEffort ?? setup.settings.modelReasoningEffort ?? setup.modelFamily.defaultReasoningEffort,
                summary: setup.settings.modelReasoningSummary
                    ?? (setup.modelFamily.supportsReasoningSummaries ? .auto : .none),
                truncationPolicy: setup.modelFamily.truncationPolicy
            ))
        ])
        try childRollout.flush()
        try childRollout.shutdown()

        if let stateStore = configuration.stateStore {
            let createdAt = Date()
            _ = try await stateStore.insertThreadIfAbsent(ThreadMetadata(
                id: childThreadID,
                rolloutPath: childRollout.rolloutPath.path,
                createdAt: createdAt,
                updatedAt: createdAt,
                source: Self.persistedSessionSource(childSource),
                threadSource: .subagent,
                agentNickname: childSource.nickname,
                agentRole: childSource.agentRole,
                agentPath: request.childAgentPath.description,
                modelProvider: setup.settings.modelProvider ?? configuration.defaultModelProvider,
                model: request.model ?? setup.model,
                reasoningEffort: request.reasoningEffort ?? setup.settings.modelReasoningEffort,
                cwd: setup.cwd.path,
                cliVersion: configuration.version,
                title: request.taskName,
                sandboxPolicy: Self.persistedSandboxPolicy(setup.sandboxPolicy),
                approvalMode: setup.approvalPolicy.rawValue,
                tokensUsed: 0
            ))
        }
        await state.recordSessionSource(threadID: childThreadID.description, source: childSource)
        await state.recordAgentLastTaskMessage(threadID: childThreadID.description, message: request.message)

        let communication = InterAgentCommunication(
            author: parentSessionSource.agentPath ?? .root,
            recipient: request.childAgentPath,
            content: request.message,
            triggerTurn: true
        )
        _ = try submitLiveRuntime(AppServerLiveRuntimeSubmission(
            requestID: .string("spawn-agent-\(childConversationID)"),
            threadID: childThreadID.description,
            turnID: UUID().uuidString.lowercased(),
            op: .interAgentCommunication(communication: communication),
            turnMetadataHeader: prototype.turnMetadataHeader,
            mcpElicitationsAutoDeny: prototype.mcpElicitationsAutoDeny,
            mcpTools: prototype.mcpTools,
            mcpToolCallHandler: prototype.mcpToolCallHandler,
            extensionPromptFragments: prototype.extensionPromptFragments,
            extensionToolSpecs: prototype.extensionToolSpecs,
            extensionRegisteredToolExecutor: prototype.extensionRegisteredToolExecutor,
            extensionApprovalReviewer: prototype.extensionApprovalReviewer,
            additionalInputItems: []
        ))

        let status = await state.agentStatus(threadID: childThreadID.description)
        return LiveSpawnAgentResult(
            threadID: childThreadID,
            agentPath: request.childAgentPath,
            nickname: childSource.nickname,
            role: childSource.agentRole,
            model: request.model ?? setup.model,
            reasoningEffort: request.reasoningEffort ?? setup.settings.modelReasoningEffort,
            status: status
        )
    }

    private func spawnLiveAgentJobWorker(
        _ request: AgentJobWorkerSpawnRequest,
        setup: PreparedLiveTurn,
        prototype: AppServerLiveRuntimeSubmission
    ) async -> AgentJobWorkerSpawnResult {
        do {
            let childConversationID = ConversationId()
            let childThreadID = try ThreadId(string: childConversationID.description)
            let childSource = request.sessionSource ?? .subagent(.other("agent_job:\(request.jobID)"))
            let spawnConfig = request.spawnConfig
            let childCwd = URL(
                fileURLWithPath: spawnConfig?.cwd ?? setup.cwd.path,
                isDirectory: true
            )
            let childModel = spawnConfig?.model ?? setup.model
            let childReasoningEffort = spawnConfig?.modelReasoningEffort
                ?? setup.settings.modelReasoningEffort
                ?? setup.modelFamily.defaultReasoningEffort
            let childReasoningSummary = spawnConfig?.modelReasoningSummary
                ?? setup.settings.modelReasoningSummary
                ?? (setup.modelFamily.supportsReasoningSummaries ? .auto : .none)
            let childApprovalPolicy = spawnConfig?.approvalPolicy ?? setup.approvalPolicy
            let childSandboxPolicy = spawnConfig?.sandboxPolicy ?? setup.sandboxPolicy
            let childRollout = try RolloutRecorder.create(
                codexHome: configuration.codexHome,
                cwd: childCwd,
                conversationID: childConversationID,
                instructions: nil,
                source: childSource,
                forkedFromID: nil,
                threadSource: .subagent,
                originator: configuration.originator,
                cliVersion: configuration.version,
                modelProvider: spawnConfig?.modelProviderID
                    ?? setup.settings.modelProvider
                    ?? configuration.defaultModelProvider,
                dynamicTools: setup.dynamicTools
            )
            try childRollout.recordItems([
                .turnContext(TurnContextItem(
                    cwd: childCwd.path,
                    approvalPolicy: childApprovalPolicy,
                    sandboxPolicy: childSandboxPolicy,
                    model: childModel,
                    effort: childReasoningEffort,
                    summary: childReasoningSummary,
                    truncationPolicy: setup.modelFamily.truncationPolicy
                ))
            ])
            try childRollout.flush()
            try childRollout.shutdown()

            if let stateStore = configuration.stateStore {
                let createdAt = Date()
                _ = try await stateStore.insertThreadIfAbsent(ThreadMetadata(
                    id: childThreadID,
                    rolloutPath: childRollout.rolloutPath.path,
                    createdAt: createdAt,
                    updatedAt: createdAt,
                    source: Self.persistedSessionSource(childSource),
                    threadSource: .subagent,
                    agentNickname: childSource.nickname,
                    agentRole: childSource.agentRole,
                    agentPath: childSource.agentPath?.description,
                    modelProvider: spawnConfig?.modelProviderID
                        ?? setup.settings.modelProvider
                        ?? configuration.defaultModelProvider,
                    model: childModel,
                    reasoningEffort: childReasoningEffort,
                    cwd: childCwd.path,
                    cliVersion: configuration.version,
                    title: request.itemID,
                    sandboxPolicy: Self.persistedSandboxPolicy(childSandboxPolicy),
                    approvalMode: childApprovalPolicy.rawValue,
                    tokensUsed: 0,
                    firstUserMessage: request.prompt
                ))
            }
            await state.recordSessionSource(threadID: childThreadID.description, source: childSource)

            _ = try submitLiveRuntime(AppServerLiveRuntimeSubmission(
                requestID: .string("agent-job-\(request.jobID)-\(request.itemID)-\(childConversationID)"),
                threadID: childThreadID.description,
                turnID: UUID().uuidString.lowercased(),
                op: .userInput(items: [.text(request.prompt)], environments: request.environments),
                turnMetadataHeader: prototype.turnMetadataHeader,
                mcpElicitationsAutoDeny: prototype.mcpElicitationsAutoDeny,
                mcpTools: prototype.mcpTools,
                mcpToolCallHandler: prototype.mcpToolCallHandler,
                extensionPromptFragments: prototype.extensionPromptFragments,
                extensionToolSpecs: prototype.extensionToolSpecs,
                extensionRegisteredToolExecutor: prototype.extensionRegisteredToolExecutor,
                extensionApprovalReviewer: prototype.extensionApprovalReviewer
            ))
            return .spawned(childThreadID)
        } catch {
            return .failed(String(describing: error))
        }
    }

    private func liveAgentJobToolContext(
        setup: PreparedLiveTurn,
        sessionSource: SessionSource,
        submission: AppServerLiveRuntimeSubmission
    ) async -> AgentJobToolContext? {
        guard let agentJobStore = configuration.agentJobStore else {
            return nil
        }
        let configuredEnvironmentSnapshot = await configuration.environmentRegistry.applying(
            to: ConfiguredEnvironmentLoader.legacyEnvironmentSnapshot(environment: configuration.environment)
        )
        return AgentJobToolContext(
            store: agentJobStore,
            reportingThreadID: submission.threadID,
            maxThreads: setup.settings.agents.maxThreads,
            sessionSource: sessionSource,
            maxDepth: setup.settings.agents.maxDepth,
            spawnConfigSource: AgentJobSpawnConfigSource(
                parentConfig: setup.settings,
                baseInstructions: setup.settings.baseInstructions ?? setup.modelFamily.baseInstructions,
                model: setup.model,
                modelProviderID: setup.settings.modelProvider ?? configuration.defaultModelProvider,
                reasoningEffort: setup.settings.modelReasoningEffort ?? setup.modelFamily.defaultReasoningEffort,
                reasoningSummary: setup.settings.modelReasoningSummary
                    ?? (setup.modelFamily.supportsReasoningSummaries ? .auto : .none),
                developerInstructions: setup.settings.developerInstructions,
                compactPrompt: setup.settings.compactPrompt,
                turnContext: TurnContext(
                    cwd: setup.cwd.path,
                    approvalPolicy: setup.approvalPolicy,
                    sandboxPolicy: setup.sandboxPolicy
                ),
                shellEnvironmentPolicy: setup.settings.shellEnvironmentPolicy
            ),
            environments: setup.turnEnvironmentSelections,
            remoteEnvironmentIDs: Self.remoteEnvironmentIDs(from: configuredEnvironmentSnapshot),
            configuredMaxRuntimeSeconds: setup.settings.agents.jobMaxRuntimeSeconds,
            statusForThread: { [state] threadID in
                await state.agentStatus(threadID: threadID.description)
            },
            spawnWorker: { [self, setup, submission] request in
                await self.spawnLiveAgentJobWorker(request, setup: setup, prototype: submission)
            },
            shutdownThread: { [state] threadID in
                await state.cancelThread(threadID: threadID.description)
            },
            waitWhenIdle: {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        )
    }

    private static func remoteEnvironmentIDs(from snapshot: ConfiguredEnvironmentSnapshot) -> Set<String> {
        Set(snapshot.environments.filter(\.isRemote).map(\.id))
    }

    private func runResponsesLoop(
        submission: AppServerLiveRuntimeSubmission,
        setup: PreparedLiveTurn,
        prompt: Prompt,
        goalAccounting: LiveThreadGoalAccountingSession
    ) async -> NonInteractiveExecLoopResult {
        let client = ResponsesClient(
            transport: URLSessionAPITransport(),
            provider: setup.provider,
            auth: setup.auth
        )
        let requestTrace = W3CTraceContext.fromEnvironment(configuration.environment)
        let clientVersion = ModelsManager.formatClientVersion(packageVersion: configuration.version)
        let permissionGrantState = AppServerLiveRuntimePermissionGrantState(
            grantedPermissions: await state.sessionGrantedPermissions(threadID: submission.threadID)
        )
        let stopHookContext = NonInteractiveExec.StopHookContext(
            handlers: setup.hookHandlers,
            conversationID: setup.conversationID,
            turnID: submission.turnID,
            cwd: setup.cwd,
            model: setup.model,
            approvalPolicy: setup.approvalPolicy
        )
        let planMode = setup.collaborationModeKind == .plan
        let sessionSource = setup.sessionSource
        let multiAgentV2WaitTimeouts = MultiAgentV2WaitTimeouts(config: setup.settings.multiAgentV2)
        let toolRouter = NonInteractiveExec.ToolRouter(
            hookContext: stopHookContext,
            cwd: setup.cwd,
            model: setup.model,
            approvalPolicy: setup.approvalPolicy,
            sandboxPolicy: setup.sandboxPolicy,
            shell: setup.shell,
            truncationPolicy: setup.modelFamily.truncationPolicy,
            environment: configuration.environment,
            shellEnvironmentPolicy: setup.settings.shellEnvironmentPolicy,
            explicitEnvOverrides: setup.settings.shellEnvironmentPolicy.set,
            allowLoginShell: setup.settings.allowLoginShell,
            canRequestOriginalImageDetail: setup.modelFamily.supportsImageDetailOriginal,
            backgroundTerminalMaxTimeoutMS: setup.settings.backgroundTerminalMaxTimeoutMS,
            goalToolContext: Self.goalToolContext(
                threadID: submission.threadID,
                stateStore: configuration.stateStore
            ),
            turnEnvironmentSelections: setup.turnEnvironmentSelections,
            configuredEnvironmentSnapshot: ConfiguredEnvironmentLoader.legacyEnvironmentSnapshot(
                environment: configuration.environment
            ),
            features: setup.settings.features,
            execPolicyManager: ExecPolicyManager(),
            windowsSandboxLevel: setup.settings.windowsSandboxLevel,
            mcpToolInfos: setup.mcpToolInfos,
            dynamicTools: setup.dynamicTools,
            registeredToolExecutor: { [self, configuration, state, sessionSource, submission] item in
                guard let currentThreadID = try? ThreadId(string: submission.threadID) else {
                    return await submission.extensionRegisteredToolExecutor?(item)
                }
                let multiAgentExecutor = AppServerLiveMultiAgentToolExecutor(
                    currentThreadID: currentThreadID,
                    currentSessionSource: sessionSource,
                    stateStore: configuration.stateStore,
                    waitTimeouts: multiAgentV2WaitTimeouts,
                    hideSpawnAgentMetadata: setup.settings.multiAgentV2.hideSpawnAgentMetadata,
                    resolveSpawnAgentOverrides: { request in
                        let selectedAgentRoles: [String: AgentRoleConfig]
                        if let agentType = request.agentType,
                           let agentRoleConfig = setup.settings.agentRoles[agentType] {
                            selectedAgentRoles = [agentType: agentRoleConfig]
                        } else {
                            selectedAgentRoles = [:]
                        }
                        let roleConfigOverrides = try LiveSpawnAgentOverrideResolver.roleConfigOverrides(
                            configuredAgentRoles: selectedAgentRoles
                        )
                        let resolver = LiveSpawnAgentOverrideResolver(
                            availableModels: Self.liveSpawnAgentAvailableModels(
                                settings: setup.settings,
                                authMode: setup.authMode
                            ),
                            currentModel: setup.model,
                            currentModelDefaultReasoningEffort: setup.modelFamily.defaultReasoningEffort,
                            parentServiceTier: setup.serviceTier,
                            configuredAgentRoles: Set(setup.settings.agentRoles.keys),
                            roleConfigOverrides: roleConfigOverrides
                        )
                        return try resolver.resolve(request)
                    },
                    spawnAgent: { request in
                        try await self.spawnLiveAgent(
                            request,
                            parentThreadID: currentThreadID,
                            parentSessionSource: sessionSource,
                            setup: setup,
                            prototype: submission
                        )
                    },
                    isTurnRunning: { threadID in
                        await state.isTurnRunning(threadID: threadID)
                    },
                    agentStatus: { threadID in
                        await state.agentStatus(threadID: threadID)
                    },
                    agentLastTaskMessage: { threadID in
                        await state.agentLastTaskMessage(threadID: threadID)
                    },
                    hasPendingMailboxItems: { threadID in
                        await state.hasPendingMailboxItems(threadID: threadID)
                    },
                    waitForMailboxChange: { threadID, timeoutMS in
                        await state.waitForMailboxChange(threadID: threadID, timeoutMilliseconds: timeoutMS)
                    },
                    queueMailboxCommunications: { threadID, communications in
                        await state.queueMailboxCommunications(
                            threadID: threadID,
                            communications: communications
                        )
                    },
                    recordAgentLastTaskMessage: { threadID, message in
                        await state.recordAgentLastTaskMessage(threadID: threadID, message: message)
                    },
                    submitPendingWorkTurnIfIdle: { threadID in
                        return await self.submitPendingWorkTurnIfIdle(
                            threadID: threadID,
                            prototype: submission
                        )
                    },
                    closeAgentThreads: { threadIDs in
                        await state.cancelThreads(threadIDs: threadIDs)
                    }
                )
                if let result = await multiAgentExecutor.execute(item) {
                    return result
                }
                if case let .functionCall(_, name, _, arguments, callID) = item,
                   let agentJobOutput = await AgentJobToolExecutor.execute(
                       name: name,
                       arguments: arguments,
                       callID: callID,
                       cwd: setup.cwd,
                       context: await self.liveAgentJobToolContext(
                           setup: setup,
                           sessionSource: sessionSource,
                           submission: submission
                       )
                   ) {
                    return NonInteractiveExec.FunctionCallExecutionResult(output: agentJobOutput)
                }
                return await submission.extensionRegisteredToolExecutor?(item)
            },
            approvalHandler: { [state, submission] request in
                await Self.resolveApprovalRequest(
                    request,
                    state: state,
                    threadID: submission.threadID,
                    turnID: submission.turnID
                )
            },
            requestUserInputHandler: { [state, submission] request in
                await Self.resolveRequestUserInputRequest(
                    request,
                    state: state,
                    threadID: submission.threadID,
                    turnID: submission.turnID
                )
            },
            requestPermissionsHandler: { [state, submission] request in
                await Self.resolveRequestPermissionsRequest(
                    request,
                    state: state,
                    threadID: submission.threadID,
                    turnID: submission.turnID
                )
            },
            mcpToolCallHandler: submission.mcpToolCallHandler,
            dynamicToolHandler: { [state, submission] request in
                await Self.resolveDynamicToolRequest(
                    request,
                    state: state,
                    threadID: submission.threadID,
                    turnID: submission.turnID
                )
            },
            grantedPermissionsProvider: {
                await permissionGrantState.grantedPermissions()
            }
        )
        return await NonInteractiveExec.runResponsesLoopWithTranscript(
            initialPrompt: prompt,
            features: setup.settings.features,
            handleModelsETag: { [configuration, setup] etag in
                _ = try? await ModelsManager.refreshCachedModelsIfNewETag(
                    codexHome: configuration.codexHome,
                    config: setup.settings,
                    provider: setup.provider,
                    auth: setup.auth,
                    transport: URLSessionAPITransport(),
                    clientVersion: clientVersion,
                    modelsETag: etag
                )
            },
            streamPrompt: { [configuration, state, commandAuthRunner, setup, submission] nextPrompt in
                let options = Self.responsesOptions(
                    conversationID: setup.conversationID,
                    modelFamily: setup.modelFamily,
                    settings: setup.settings,
                    serviceTier: setup.serviceTier,
                    outputSchema: setup.outputSchema,
                    metadata: setup.metadata,
                    turnMetadataHeader: submission.turnMetadataHeader,
                    requestTrace: requestTrace,
                    sessionSource: configuration.sessionSource
                )
                switch await client.streamPromptEventsRetryingProviderCommandAuth(
                    model: setup.model,
                    instructions: nextPrompt.fullInstructions(for: setup.modelFamily),
                    prompt: nextPrompt,
                    options: options,
                    providerInfo: setup.providerInfo,
                    commandRunner: commandAuthRunner
                ) {
                case let .success(stream):
                    var results: ResponseEventResults = []
                    for await result in ResponseEventAggregator.aggregate(stream, mode: .streaming) {
                        if Task.isCancelled {
                            return .failure(.stream("turn interrupted"))
                        }
                        results.append(result)
                        if case let .success(.runtimeEvent(event)) = result {
                            await state.emit(
                                threadID: submission.threadID,
                                turnID: submission.turnID,
                                event: event
                            )
                        }
                    }
                    return .success(results)
                case let .failure(error):
                    return .failure(error)
                }
            },
            stopHookContext: stopHookContext,
            handleCompletedOutputItem: { [state, submission, planMode] item in
                await Self.updateMailboxDeliveryPhase(
                    afterCompletedOutputItem: item,
                    state: state,
                    threadID: submission.threadID,
                    planMode: planMode
                )
            },
            takePendingInput: { [state, submission] in
                await state.takePendingInputForCurrentTurn(threadID: submission.threadID)
            },
            handleToolPreExecution: { [state, submission, goalAccounting] item, tokenUsage in
                guard Self.shouldAccountLiveThreadGoalCompletionTool(item) else {
                    return nil
                }
                guard let result = await goalAccounting.accountGoalToolCompletion(
                    tokenUsage: tokenUsage,
                    completedAtMilliseconds: AppServerLiveRuntimeClock.millisecondsSinceEpoch()
                ) else {
                    return nil
                }
                await state.emit(
                    threadID: submission.threadID,
                    turnID: submission.turnID,
                    event: .threadGoalUpdated(ThreadGoalUpdatedEvent(
                        threadID: result.goal.threadID,
                        turnID: submission.turnID,
                        goal: result.goal
                    ))
                )
                return NonInteractiveExecToolCompletionResult()
            },
            handleToolCompletion: { [state, submission, goalAccounting] item, tokenUsage in
                guard Self.shouldAccountLiveThreadGoalToolCompletion(item) else {
                    return nil
                }
                guard let result = await goalAccounting.accountToolCompletion(
                    tokenUsage: tokenUsage,
                    completedAtMilliseconds: AppServerLiveRuntimeClock.millisecondsSinceEpoch()
                ) else {
                    return nil
                }
                await state.emit(
                    threadID: submission.threadID,
                    turnID: submission.turnID,
                    event: .threadGoalUpdated(ThreadGoalUpdatedEvent(
                        threadID: result.goal.threadID,
                        turnID: submission.turnID,
                        goal: result.goal
                    ))
                )
                return NonInteractiveExecToolCompletionResult(
                    additionalContextItems: result.additionalContextItems
                )
            },
            executeFunctionCall: { [state, submission] item in
                let result = await toolRouter.execute(item)
                for event in result.runtimeEvents {
                    await state.emit(
                        threadID: submission.threadID,
                        turnID: submission.turnID,
                        event: event
                    )
                }
                if let response = result.requestPermissionsResponse {
                    await permissionGrantState.record(response)
                    if response.scope == .session {
                        await state.recordSessionGrantedPermissions(
                            threadID: submission.threadID,
                            permissions: response.permissions
                        )
                    }
                }
                return result
            }
        )
    }

    private static func shouldAccountLiveThreadGoalCompletionTool(_ item: ResponseItem) -> Bool {
        if case let .functionCall(_, name, _, _, _) = item {
            return name == "update_goal"
        }
        return false
    }

    private static func shouldAccountLiveThreadGoalToolCompletion(_ item: ResponseItem) -> Bool {
        switch item {
        case let .functionCall(_, name, _, _, _):
            return name != "update_goal"
        case .customToolCall,
             .localShellCall,
             .toolSearchCall:
            return true
        default:
            return false
        }
    }

    private static func updateMailboxDeliveryPhase(
        afterCompletedOutputItem item: ResponseItem,
        state: AppServerLiveRuntimeState,
        threadID: String,
        planMode: Bool
    ) async {
        if completedOutputItemAcceptsMailboxDeliveryForCurrentTurn(item) {
            await state.acceptMailboxDeliveryForCurrentTurn(threadID: threadID)
            return
        }
        if completedOutputItemDefersMailboxDeliveryToNextTurn(item, planMode: planMode) {
            await state.deferMailboxDeliveryToNextTurn(threadID: threadID)
        }
    }

    private static func completedOutputItemAcceptsMailboxDeliveryForCurrentTurn(_ item: ResponseItem) -> Bool {
        switch item {
        case .functionCall,
             .customToolCall,
             .localShellCall:
            return true
        case let .toolSearchCall(_, callID, _, execution, _):
            return callID != nil && execution == "client"
        default:
            return false
        }
    }

    private static func completedOutputItemDefersMailboxDeliveryToNextTurn(
        _ item: ResponseItem,
        planMode: Bool
    ) -> Bool {
        switch item {
        case let .message(_, role, _, phase):
            guard role == "assistant", phase != .commentary else {
                return false
            }
            return StreamEventUtils.lastAssistantMessage(from: item, planMode: planMode) != nil
        case .imageGenerationCall:
            return true
        default:
            return false
        }
    }

    private static func goalToolContext(
        threadID: String,
        stateStore: SQLiteAgentGraphStore?
    ) -> NonInteractiveExec.GoalToolContext? {
        guard let stateStore,
              let parsedThreadID = try? ThreadId(string: threadID)
        else {
            return nil
        }
        return NonInteractiveExec.GoalToolContext(threadID: parsedThreadID, stateStore: stateStore)
    }

    struct LiveThreadGoalAccountingSnapshot: Equatable, Sendable {
        var expectedGoalID: String?
        var tokenUsageBaseline: TokenUsage

        var activeThisTurn: Bool {
            expectedGoalID != nil
        }

        func tokenDelta(since current: TokenUsage?) -> Int64 {
            max((current?.totalTokens ?? 0) - tokenUsageBaseline.totalTokens, 0)
        }
    }

    struct LiveThreadGoalAccountingResult: Equatable, Sendable {
        var goal: ThreadGoal
        var additionalContextItems: [ResponseItem]
    }

    actor LiveThreadGoalAccountingSession {
        private let stateStore: SQLiteAgentGraphStore?
        private let features: FeatureStates
        private let threadID: String
        private var snapshot: LiveThreadGoalAccountingSnapshot
        private var lastAccountingAtMilliseconds: Int64
        private var budgetLimitReportedGoalID: String?

        init(
            stateStore: SQLiteAgentGraphStore?,
            features: FeatureStates,
            threadID: String,
            snapshot: LiveThreadGoalAccountingSnapshot,
            lastAccountingAtMilliseconds: Int64
        ) {
            self.stateStore = stateStore
            self.features = features
            self.threadID = threadID
            self.snapshot = snapshot
            self.lastAccountingAtMilliseconds = lastAccountingAtMilliseconds
        }

        func accountToolCompletion(
            tokenUsage: TokenUsage?,
            completedAtMilliseconds: Int64
        ) async -> LiveThreadGoalAccountingResult? {
            await accountUsage(
                tokenUsage: tokenUsage,
                completedAtMilliseconds: completedAtMilliseconds,
                budgetLimitSteeringAllowed: true
            )
        }

        func accountGoalToolCompletion(
            tokenUsage: TokenUsage?,
            completedAtMilliseconds: Int64
        ) async -> LiveThreadGoalAccountingResult? {
            await accountUsage(
                tokenUsage: tokenUsage,
                completedAtMilliseconds: completedAtMilliseconds,
                budgetLimitSteeringAllowed: false
            )
        }

        func accountTurnCompletion(
            tokenUsage: TokenUsage?,
            completedAtMilliseconds: Int64
        ) async -> ThreadGoal? {
            let result = await accountUsage(
                tokenUsage: tokenUsage,
                completedAtMilliseconds: completedAtMilliseconds,
                budgetLimitSteeringAllowed: false
            )
            return result?.goal
        }

        func accountInterruptBeforePause(
            tokenUsage: TokenUsage?,
            completedAtMilliseconds: Int64
        ) async -> ThreadGoal? {
            _ = await accountUsage(
                tokenUsage: tokenUsage,
                completedAtMilliseconds: completedAtMilliseconds,
                budgetLimitSteeringAllowed: false
            )
            return await AppServerLiveRuntimeManager.pauseActiveLiveThreadGoal(
                stateStore: stateStore,
                features: features,
                threadID: threadID
            )
        }

        private func accountUsage(
            tokenUsage: TokenUsage?,
            completedAtMilliseconds: Int64,
            budgetLimitSteeringAllowed: Bool
        ) async -> LiveThreadGoalAccountingResult? {
            let durationMilliseconds = max(completedAtMilliseconds - lastAccountingAtMilliseconds, 0)
            guard let result = await AppServerLiveRuntimeManager.accountLiveThreadGoalUsage(
                stateStore: stateStore,
                features: features,
                threadID: threadID,
                snapshot: snapshot,
                tokenUsage: tokenUsage,
                durationMilliseconds: durationMilliseconds,
                budgetLimitSteeringAllowed: budgetLimitSteeringAllowed,
                budgetLimitReportedGoalID: budgetLimitReportedGoalID
            ) else {
                return nil
            }
            snapshot.tokenUsageBaseline = tokenUsage ?? snapshot.tokenUsageBaseline
            lastAccountingAtMilliseconds = completedAtMilliseconds
            if result.goal.status == .budgetLimited {
                if !result.additionalContextItems.isEmpty {
                    budgetLimitReportedGoalID = snapshot.expectedGoalID
                }
            } else {
                budgetLimitReportedGoalID = nil
            }
            return result
        }
    }

    static func pauseActiveLiveThreadGoal(
        stateStore: SQLiteAgentGraphStore?,
        features: FeatureStates,
        threadID: String
    ) async -> ThreadGoal? {
        guard features.isEnabled(.goals),
              let stateStore,
              let parsedThreadID = try? ThreadId(string: threadID)
        else {
            return nil
        }
        do {
            return try await stateStore.pauseActiveThreadGoal(threadID: parsedThreadID)
        } catch {
            return nil
        }
    }

    static func liveGoalContinuationInputItems(
        stateStore: SQLiteAgentGraphStore?,
        features: FeatureStates,
        threadID: String,
        collaborationModeKind: CollaborationModeKind? = nil
    ) async -> [ResponseItem]? {
        guard features.isEnabled(.goals),
              collaborationModeKind != .plan,
              let stateStore,
              let parsedThreadID = try? ThreadId(string: threadID)
        else {
            return nil
        }
        do {
            guard let goal = try await stateStore.getThreadGoal(threadID: parsedThreadID),
                  goal.status == .active
            else {
                return nil
            }
            return [ThreadGoalRuntimeContext.continuationInputItem(for: goal)]
        } catch {
            return nil
        }
    }

    static func liveThreadGoalAccountingSnapshot(
        stateStore: SQLiteAgentGraphStore?,
        features: FeatureStates,
        threadID: String,
        tokenUsage: TokenUsage
    ) async -> LiveThreadGoalAccountingSnapshot {
        guard features.isEnabled(.goals),
              let stateStore,
              let parsedThreadID = try? ThreadId(string: threadID)
        else {
            return LiveThreadGoalAccountingSnapshot(expectedGoalID: nil, tokenUsageBaseline: tokenUsage)
        }
        do {
            return LiveThreadGoalAccountingSnapshot(
                expectedGoalID: try await stateStore.getAccountableThreadGoalID(threadID: parsedThreadID),
                tokenUsageBaseline: tokenUsage
            )
        } catch {
            return LiveThreadGoalAccountingSnapshot(expectedGoalID: nil, tokenUsageBaseline: tokenUsage)
        }
    }

    static func accountCompletedLiveThreadGoalUsage(
        stateStore: SQLiteAgentGraphStore?,
        features: FeatureStates,
        threadID: String,
        snapshot: LiveThreadGoalAccountingSnapshot,
        tokenUsage: TokenUsage?,
        durationMilliseconds: Int64
    ) async -> ThreadGoal? {
        await accountLiveThreadGoalUsage(
            stateStore: stateStore,
            features: features,
            threadID: threadID,
            snapshot: snapshot,
            tokenUsage: tokenUsage,
            durationMilliseconds: durationMilliseconds,
            budgetLimitSteeringAllowed: false,
            budgetLimitReportedGoalID: nil
        )?.goal
    }

    static func accountLiveThreadGoalUsage(
        stateStore: SQLiteAgentGraphStore?,
        features: FeatureStates,
        threadID: String,
        snapshot: LiveThreadGoalAccountingSnapshot,
        tokenUsage: TokenUsage?,
        durationMilliseconds: Int64,
        budgetLimitSteeringAllowed: Bool,
        budgetLimitReportedGoalID: String?
    ) async -> LiveThreadGoalAccountingResult? {
        guard features.isEnabled(.goals),
              let stateStore,
              let parsedThreadID = try? ThreadId(string: threadID),
              snapshot.activeThisTurn
        else {
            return nil
        }
        let tokenDelta = snapshot.tokenDelta(since: tokenUsage)
        let timeDeltaSeconds = max(durationMilliseconds / 1_000, 0)
        guard tokenDelta > 0 || timeDeltaSeconds > 0 else {
            return nil
        }
        do {
            switch try await stateStore.accountThreadGoalUsage(
                threadID: parsedThreadID,
                timeDeltaSeconds: timeDeltaSeconds,
                tokenDelta: tokenDelta,
                mode: .activeOnly,
                expectedGoalID: snapshot.expectedGoalID
            ) {
            case let .updated(goal):
                let shouldSteerBudgetLimit = budgetLimitSteeringAllowed
                    && goal.status == .budgetLimited
                    && budgetLimitReportedGoalID != snapshot.expectedGoalID
                return LiveThreadGoalAccountingResult(
                    goal: goal,
                    additionalContextItems: shouldSteerBudgetLimit
                        ? [ThreadGoalRuntimeContext.budgetLimitInputItem(for: goal)]
                        : []
                )
            case .unchanged:
                return nil
            }
        } catch {
            return nil
        }
    }

    private func completeTurn(
        submission: AppServerLiveRuntimeSubmission,
        startedAt: Int64,
        recorder: RolloutRecorder?,
        lastAssistantMessage: String?
    ) async {
        try? recorder?.flush()
        try? recorder?.shutdown()
        let completedAt = AppServerLiveRuntimeClock.millisecondsSinceEpoch()
        await state.emit(
            threadID: submission.threadID,
            turnID: submission.turnID,
            event: .taskComplete(TaskCompleteEvent(
                turnID: submission.turnID,
                lastAgentMessage: lastAssistantMessage,
                completedAt: completedAt,
                durationMilliseconds: completedAt - startedAt
            ))
        )
    }

    private func emitCompletedTurnItem(
        _ item: ResponseItem,
        threadID: ConversationId,
        turnID: String
    ) async {
        guard let turnItem = StreamEventUtils.handleNonToolResponseItem(
            item,
            codexHome: configuration.codexHome,
            sessionID: threadID.description
        ) else {
            return
        }
        await state.emit(
            threadID: threadID.description,
            turnID: turnID,
            event: .itemCompleted(ItemCompletedEvent(
                threadID: threadID,
                turnID: turnID,
                item: turnItem,
                completedAtMilliseconds: AppServerLiveRuntimeClock.millisecondsSinceEpoch()
            ))
        )
    }

    private func resolveAuth(
        settings: CodexRuntimeConfig,
        providerInfo: ModelProviderInfo
    ) async throws -> AppServerRuntimeAuthResolution {
        if providerInfo.envKey != nil || providerInfo.experimentalBearerToken != nil || providerInfo.auth != nil {
            let auth = try await APIAuthResolver.authProvider(
                auth: nil,
                provider: providerInfo,
                environment: configuration.environment,
                commandRunner: commandAuthRunner
            )
            return AppServerRuntimeAuthResolution(
                auth: auth,
                authMode: auth.accountID == nil || providerInfo.auth != nil ? .apiKey : .chatGPT
            )
        }

        if let apiKey = CodexAuthStorage.readCodexAPIKeyFromEnvironment(configuration.environment) {
            return AppServerRuntimeAuthResolution(auth: StaticAPIAuthProvider(bearerToken: apiKey), authMode: .apiKey)
        }

        let storedAuth = try CodexAuthStorage.loadAuthDotJSON(
            codexHome: configuration.codexHome,
            mode: settings.cliAuthCredentialsStoreMode
        )
        if let apiKey = storedAuth?.openAIAPIKey {
            return AppServerRuntimeAuthResolution(auth: StaticAPIAuthProvider(bearerToken: apiKey), authMode: .apiKey)
        }
        if storedAuth?.tokens != nil {
            guard let tokenData = try await CodexAuthStorage.loadFreshTokenData(
                codexHome: configuration.codexHome,
                mode: settings.cliAuthCredentialsStoreMode,
                environment: configuration.environment
            ) else {
                throw AppServerLiveRuntimeError("Stored ChatGPT credentials are missing token data.")
            }
            return AppServerRuntimeAuthResolution(
                auth: StaticAPIAuthProvider(
                    bearerToken: tokenData.accessToken,
                    accountID: tokenData.accountID
                ),
                authMode: .chatGPT
            )
        }
        if providerInfo.requiresOpenAIAuth || configuration.requiresOpenAIAuth {
            throw AppServerLiveRuntimeError("Not logged in. Run `codex login` or set CODEX_API_KEY.")
        }
        return AppServerRuntimeAuthResolution(auth: StaticAPIAuthProvider(), authMode: nil)
    }

    private static func responsesOptions(
        conversationID: ConversationId,
        modelFamily: ModelFamily,
        settings: CodexRuntimeConfig,
        serviceTier: String?,
        outputSchema: JSONValue?,
        metadata: [String: String],
        turnMetadataHeader: String?,
        requestTrace: W3CTraceContext?,
        sessionSource: SessionSource
    ) -> ResponsesOptions {
        var options = NonInteractiveExec.responsesOptions(
            conversationID: conversationID,
            modelFamily: modelFamily,
            reasoningEffort: settings.modelReasoningEffort,
            reasoningSummary: settings.modelReasoningSummary,
            verbosity: settings.modelVerbosity,
            serviceTier: serviceTier,
            outputSchema: outputSchema,
            requestTrace: requestTrace
        )
        options.sessionSource = sessionSource
        options.clientMetadata.merge(metadata) { _, new in new }
        options.turnMetadataHeader = turnMetadataHeader
        return options
    }

    private static func resolveApprovalRequest(
        _ request: NonInteractiveExec.FunctionCallApprovalRequest,
        state: AppServerLiveRuntimeState,
        threadID: String,
        turnID: String
    ) async -> ReviewDecision {
        let approvalID: String
        let event: EventMessage
        switch request {
        case let .exec(exec):
            approvalID = exec.effectiveApprovalID
            event = .execApprovalRequest(exec)
        case let .applyPatch(applyPatch):
            approvalID = applyPatch.callID
            event = .applyPatchApprovalRequest(applyPatch)
        }
        return await withTaskCancellationHandler {
            await state.pendingApproval(id: approvalID) {
                await state.emit(threadID: threadID, turnID: turnID, event: event)
            }
        } onCancel: {
            Task {
                await state.resolveApproval(id: approvalID, decision: .denied)
            }
        }
    }

    private static func resolveRequestPermissionsRequest(
        _ request: NonInteractiveExec.RequestPermissionsToolRequest,
        state: AppServerLiveRuntimeState,
        threadID: String,
        turnID: String
    ) async -> RequestPermissionsResponse? {
        let event = EventMessage.requestPermissions(RequestPermissionsEvent(
            callID: request.callID,
            turnID: turnID,
            startedAtMilliseconds: AppServerLiveRuntimeClock.millisecondsSinceEpoch(),
            reason: request.reason,
            permissions: request.permissions,
            cwd: try? AbsolutePath(absolutePath: request.cwd.standardizedFileURL.path)
        ))
        let response = await withTaskCancellationHandler {
            await state.pendingPermissions(id: request.callID) {
                await state.emit(threadID: threadID, turnID: turnID, event: event)
            }
        } onCancel: {
            Task {
                await state.resolvePermissions(
                    id: request.callID,
                    response: RequestPermissionsResponse(permissions: RequestPermissionProfile())
                )
            }
        }
        return normalizeRequestPermissionsResponse(
            response,
            requested: request.permissions,
            cwd: request.cwd.standardizedFileURL.path
        )
    }

    private static func resolveRequestUserInputRequest(
        _ request: RequestUserInputEvent,
        state: AppServerLiveRuntimeState,
        threadID: String,
        turnID fallbackTurnID: String
    ) async -> RequestUserInputResponse? {
        let turnID = request.turnID.isEmpty ? fallbackTurnID : request.turnID
        let event = RequestUserInputEvent(
            callID: request.callID,
            turnID: turnID,
            questions: request.questions
        )
        return await withTaskCancellationHandler {
            await state.pendingUserInput(id: turnID) {
                await state.emit(threadID: threadID, turnID: turnID, event: .requestUserInput(event))
            }
        } onCancel: {
            Task {
                await state.cancelUserInput(id: turnID)
            }
        }
    }

    private static func resolveDynamicToolRequest(
        _ request: DynamicToolCallRequest,
        state: AppServerLiveRuntimeState,
        threadID: String,
        turnID fallbackTurnID: String
    ) async -> DynamicToolResponse? {
        let turnID = request.turnID.isEmpty ? fallbackTurnID : request.turnID
        let event = DynamicToolCallRequest(
            callID: request.callID,
            turnID: turnID,
            startedAtMilliseconds: request.startedAtMilliseconds,
            namespace: request.namespace,
            tool: request.tool,
            arguments: request.arguments
        )
        return await withTaskCancellationHandler {
            await state.pendingDynamicTool(id: request.callID, turnID: turnID) {
                await state.emit(threadID: threadID, turnID: turnID, event: .dynamicToolCallRequest(event))
            }
        } onCancel: {
            Task {
                await state.cancelDynamicTool(id: request.callID)
            }
        }
    }

    private static func normalizeRequestPermissionsResponse(
        _ response: RequestPermissionsResponse,
        requested: RequestPermissionProfile,
        cwd: String
    ) -> RequestPermissionsResponse {
        if response.strictAutoReview && response.scope == .session {
            return RequestPermissionsResponse(permissions: RequestPermissionProfile())
        }
        if response.permissions.isEmpty {
            return response
        }
        return RequestPermissionsResponse(
            permissions: RequestPermissionProfile.intersectAdditionalPermissionProfiles(
                requested: requested,
                granted: response.permissions,
                cwd: cwd
            ),
            scope: response.scope,
            strictAutoReview: response.strictAutoReview
        )
    }

    private static func lastAssistantMessage(from items: [ResponseItem]) -> String? {
        items.reversed().compactMap { item -> String? in
            guard case let .message(_, role, content, _) = item, role == "assistant" else {
                return nil
            }
            let text = content.compactMap { contentItem -> String? in
                if case let .outputText(text) = contentItem {
                    return text
                }
                return nil
            }.joined()
            return text.isEmpty ? nil : text
        }.first
    }

    private static func nextThreadSpawnDepth(_ source: SessionSource) -> Int32 {
        guard case let .subagent(.threadSpawn(_, depth, _, _, _)) = source else {
            return 1
        }
        return depth + 1
    }

    private static func configuredMultiAgentV2UsageHintTexts(settings: CodexRuntimeConfig) -> [String] {
        guard settings.features.isEnabled(.multiAgentV2) else {
            return []
        }
        return [
            settings.multiAgentV2.rootAgentUsageHintText,
            settings.multiAgentV2.subagentUsageHintText,
        ].compactMap(\.self)
    }

    private static func persistedSessionSource(_ source: SessionSource) -> String {
        guard let data = try? JSONEncoder().encode(source),
              let text = String(data: data, encoding: .utf8)
        else {
            return source.description
        }
        return text
    }

    private static func persistedSandboxPolicy(_ policy: SandboxPolicy) -> String {
        switch policy {
        case .dangerFullAccess:
            return "danger-full-access"
        case .readOnly, .readOnlyWithNetworkAccess:
            return "read-only"
        case .externalSandbox:
            return "external-sandbox"
        case .workspaceWrite:
            return "workspace-write"
        }
    }
}

private actor AppServerLiveRuntimeStartGate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen {
            return
        }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func open() {
        guard !isOpen else {
            return
        }
        isOpen = true
        let pending = continuations
        continuations.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }
}

private actor AppServerLiveRuntimePermissionGrantState {
    private var current: RequestPermissionProfile?

    init(grantedPermissions: RequestPermissionProfile?) {
        self.current = grantedPermissions
    }

    func grantedPermissions() -> RequestPermissionProfile? {
        current
    }

    func record(_ response: RequestPermissionsResponse) {
        current = RequestPermissionProfile.mergeAdditionalPermissionProfiles(
            base: current,
            permissions: response.permissions
        )
    }
}

private actor AppServerLiveRuntimeState {
    private var eventSink: AppServerRuntimeEventSink?
    private var runningTurns: [String: RunningTurn] = [:]
    private var approvalContinuations: [String: CheckedContinuation<ReviewDecision, Never>] = [:]
    private var permissionContinuations: [String: CheckedContinuation<RequestPermissionsResponse, Never>] = [:]
    private var userInputContinuations: [String: CheckedContinuation<RequestUserInputResponse?, Never>] = [:]
    private var dynamicToolContinuations: [String: PendingDynamicTool] = [:]
    private var sessionGrantedPermissionProfiles: [String: RequestPermissionProfile] = [:]
    private var runtimeConfigSnapshots: [String: ConfigValue] = [:]
    private var idlePendingInput: [String: [ResponseInputItem]] = [:]
    private var activePendingInput: [String: [ResponseInputItem]] = [:]
    private var mailboxCommunications: [String: [InterAgentCommunication]] = [:]
    private var mailboxDeliveryPhases: [String: MailboxDeliveryPhase] = [:]
    private var mailboxChangeWaiters: [String: [String: CheckedContinuation<Bool, Never>]] = [:]
    private var agentLastTaskMessages: [String: String] = [:]
    private var agentStatuses: [String: AgentStatus] = [:]
    private var sessionSources: [String: SessionSource] = [:]
    private var emittedAbortKeys: Set<String> = []

    func setEventSink(_ sink: AppServerRuntimeEventSink?) {
        eventSink = sink
    }

    func startTurn(threadID: String, turnID: String, task: Task<Void, Never>) {
        runningTurns[threadID]?.task.cancel()
        runningTurns[threadID] = RunningTurn(turnID: turnID, task: task)
        agentStatuses[threadID] = .running
        activePendingInput.removeValue(forKey: threadID)
        mailboxDeliveryPhases[threadID] = .currentTurn
    }

    func startTurnIfIdle(threadID: String, turnID: String, task: Task<Void, Never>) -> Bool {
        guard runningTurns[threadID] == nil,
              userInputContinuations.isEmpty,
              dynamicToolContinuations.isEmpty
        else {
            return false
        }
        runningTurns[threadID] = RunningTurn(turnID: turnID, task: task)
        agentStatuses[threadID] = .running
        activePendingInput.removeValue(forKey: threadID)
        mailboxDeliveryPhases[threadID] = .currentTurn
        return true
    }

    func startPendingWorkTurnIfIdle(threadID: String, turnID: String, task: Task<Void, Never>) -> Bool {
        guard hasPendingWorkForNextTurn(threadID: threadID),
              runningTurns[threadID] == nil,
              userInputContinuations.isEmpty,
              dynamicToolContinuations.isEmpty
        else {
            return false
        }
        runningTurns[threadID] = RunningTurn(turnID: turnID, task: task)
        agentStatuses[threadID] = .running
        activePendingInput.removeValue(forKey: threadID)
        mailboxDeliveryPhases[threadID] = .currentTurn
        return true
    }

    func isTurnRunning(threadID: String) -> Bool {
        runningTurns[threadID] != nil
    }

    func agentStatus(threadID: String) -> AgentStatus {
        if let status = agentStatuses[threadID] {
            return status
        }
        return runningTurns[threadID] == nil ? .completed(nil) : .running
    }

    func recordSessionSource(threadID: String, source: SessionSource) {
        sessionSources[threadID] = source
    }

    func finishTurn(threadID: String, turnID: String) {
        if runningTurns[threadID]?.turnID == turnID {
            runningTurns.removeValue(forKey: threadID)
        }
        activePendingInput.removeValue(forKey: threadID)
        mailboxDeliveryPhases[threadID] = .currentTurn
        cancelPendingContinuations(turnID: turnID)
        emittedAbortKeys.remove(Self.abortKey(threadID: threadID, turnID: turnID))
    }

    func cancelTurn(threadID: String) -> String? {
        guard let running = runningTurns[threadID] else {
            return nil
        }
        running.task.cancel()
        runningTurns.removeValue(forKey: threadID)
        activePendingInput.removeValue(forKey: threadID)
        mailboxDeliveryPhases[threadID] = .currentTurn
        cancelPendingContinuations(turnID: running.turnID)
        return running.turnID
    }

    func cancelTurnIfMatching(threadID: String, turnID: String) {
        guard runningTurns[threadID]?.turnID == turnID else {
            return
        }
        runningTurns.removeValue(forKey: threadID)?.task.cancel()
        activePendingInput.removeValue(forKey: threadID)
        mailboxDeliveryPhases[threadID] = .currentTurn
        cancelPendingContinuations(turnID: turnID)
        emittedAbortKeys.remove(Self.abortKey(threadID: threadID, turnID: turnID))
    }

    func canStartGoalContinuation(threadID: String) -> Bool {
        runningTurns[threadID] == nil
            && !hasQueuedResponseItemsForNextTurn(threadID: threadID)
            && !hasTriggerTurnMailboxCommunications(threadID: threadID)
            && userInputContinuations.isEmpty
            && dynamicToolContinuations.isEmpty
    }

    func queueResponseItemsForNextTurn(threadID: String, items: [ResponseInputItem]) {
        guard !items.isEmpty else {
            return
        }
        idlePendingInput[threadID, default: []].append(contentsOf: items)
    }

    func queuePendingInputForCurrentTurn(threadID: String, items: [ResponseInputItem]) {
        guard !items.isEmpty,
              runningTurns[threadID] != nil
        else {
            return
        }
        activePendingInput[threadID, default: []].append(contentsOf: items)
        mailboxDeliveryPhases[threadID] = .currentTurn
    }

    func takeQueuedResponseItemsForNextTurn(threadID: String) -> [ResponseInputItem] {
        guard let items = idlePendingInput.removeValue(forKey: threadID) else {
            return []
        }
        return items
    }

    func queueMailboxCommunications(threadID: String, communications: [InterAgentCommunication]) {
        guard !communications.isEmpty else {
            return
        }
        mailboxCommunications[threadID, default: []].append(contentsOf: communications)
        finishMailboxWaiters(threadID: threadID, result: true)
    }

    func recordAgentLastTaskMessage(threadID: String, message: String) {
        agentLastTaskMessages[threadID] = message
    }

    func agentLastTaskMessage(threadID: String) -> String? {
        agentLastTaskMessages[threadID]
    }

    func hasPendingMailboxItems(threadID: String) -> Bool {
        mailboxCommunications[threadID]?.isEmpty == false
    }

    func waitForMailboxChange(threadID: String, timeoutMilliseconds: Int64) async -> Bool {
        if hasPendingMailboxItems(threadID: threadID) {
            return true
        }
        let waiterID = UUID().uuidString
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                mailboxChangeWaiters[threadID, default: [:]][waiterID] = continuation
                Task {
                    let timeoutNanoseconds = max(timeoutMilliseconds, 0) * 1_000_000
                    try? await Task.sleep(nanoseconds: UInt64(timeoutNanoseconds))
                    self.finishMailboxWaiter(threadID: threadID, waiterID: waiterID, result: false)
                }
            }
        } onCancel: {
            Task {
                await self.finishMailboxWaiter(threadID: threadID, waiterID: waiterID, result: false)
            }
        }
    }

    func takeMailboxCommunications(threadID: String) -> [InterAgentCommunication] {
        guard let communications = mailboxCommunications.removeValue(forKey: threadID) else {
            return []
        }
        mailboxDeliveryPhases[threadID] = .currentTurn
        return communications
    }

    func takePendingInputForCurrentTurn(threadID: String) -> [ResponseInputItem] {
        let pendingInput = activePendingInput.removeValue(forKey: threadID) ?? []
        guard mailboxDeliveryPhases[threadID, default: .currentTurn] == .currentTurn else {
            return pendingInput
        }
        let mailboxInput = takeMailboxCommunications(threadID: threadID).map { $0.toResponseInputItem() }
        guard !pendingInput.isEmpty else {
            return mailboxInput
        }
        return pendingInput + mailboxInput
    }

    func deferMailboxDeliveryToNextTurn(threadID: String) {
        guard activePendingInput[threadID]?.isEmpty != false else {
            return
        }
        mailboxDeliveryPhases[threadID] = .nextTurn
    }

    func acceptMailboxDeliveryForCurrentTurn(threadID: String) {
        mailboxDeliveryPhases[threadID] = .currentTurn
    }

    private func hasPendingWorkForNextTurn(threadID: String) -> Bool {
        hasQueuedResponseItemsForNextTurn(threadID: threadID)
            || hasTriggerTurnMailboxCommunications(threadID: threadID)
    }

    private func hasQueuedResponseItemsForNextTurn(threadID: String) -> Bool {
        idlePendingInput[threadID]?.isEmpty == false
    }

    private func hasTriggerTurnMailboxCommunications(threadID: String) -> Bool {
        mailboxCommunications[threadID]?.contains { $0.triggerTurn } == true
    }

    func cancelThread(threadID: String) {
        if let running = runningTurns.removeValue(forKey: threadID) {
            running.task.cancel()
            cancelPendingContinuations(turnID: running.turnID)
        }
        sessionGrantedPermissionProfiles.removeValue(forKey: threadID)
        runtimeConfigSnapshots.removeValue(forKey: threadID)
        let status = AgentStatus.notFound
        agentStatuses[threadID] = status
        maybeNotifyParentOfFinalStatus(threadID: threadID, status: status)
        sessionSources.removeValue(forKey: threadID)
        idlePendingInput.removeValue(forKey: threadID)
        activePendingInput.removeValue(forKey: threadID)
        mailboxCommunications.removeValue(forKey: threadID)
        mailboxDeliveryPhases.removeValue(forKey: threadID)
        finishMailboxWaiters(threadID: threadID, result: true)
        agentLastTaskMessages.removeValue(forKey: threadID)
    }

    func cancelThreads(threadIDs: [String]) {
        for threadID in threadIDs {
            cancelThread(threadID: threadID)
        }
    }

    func cancelAll() {
        let turns = runningTurns.values
        runningTurns.removeAll()
        sessionGrantedPermissionProfiles.removeAll()
        runtimeConfigSnapshots.removeAll()
        agentStatuses.removeAll()
        sessionSources.removeAll()
        idlePendingInput.removeAll()
        activePendingInput.removeAll()
        mailboxCommunications.removeAll()
        mailboxDeliveryPhases.removeAll()
        finishAllMailboxWaiters(result: true)
        agentLastTaskMessages.removeAll()
        emittedAbortKeys.removeAll()
        for turn in turns {
            turn.task.cancel()
        }
        for continuation in approvalContinuations.values {
            continuation.resume(returning: .denied)
        }
        approvalContinuations.removeAll()
        for continuation in permissionContinuations.values {
            continuation.resume(returning: RequestPermissionsResponse(permissions: RequestPermissionProfile()))
        }
        permissionContinuations.removeAll()
        for continuation in userInputContinuations.values {
            continuation.resume(returning: nil)
        }
        userInputContinuations.removeAll()
        for pending in dynamicToolContinuations.values {
            pending.continuation.resume(returning: nil)
        }
        dynamicToolContinuations.removeAll()
    }

    func emit(threadID: String, turnID: String, event: EventMessage) async {
        let status = AgentStatus.from(eventMessage: event)
        if let status {
            agentStatuses[threadID] = status
        }
        await eventSink?(threadID, turnID, event)
        if let status {
            maybeNotifyParentOfFinalStatus(threadID: threadID, status: status)
        }
    }

    func markAbortEmitted(threadID: String, turnID: String) -> Bool {
        let key = Self.abortKey(threadID: threadID, turnID: turnID)
        guard !emittedAbortKeys.contains(key) else {
            return false
        }
        emittedAbortKeys.insert(key)
        return true
    }

    func pendingApproval(
        id: String,
        notify: @escaping @Sendable () async -> Void
    ) async -> ReviewDecision {
        await notify()
        return await withCheckedContinuation { continuation in
            approvalContinuations[id] = continuation
        }
    }

    func resolveApproval(id: String, decision: ReviewDecision) {
        approvalContinuations.removeValue(forKey: id)?.resume(returning: decision)
    }

    func pendingPermissions(
        id: String,
        notify: @escaping @Sendable () async -> Void
    ) async -> RequestPermissionsResponse {
        await notify()
        return await withCheckedContinuation { continuation in
            permissionContinuations[id] = continuation
        }
    }

    func resolvePermissions(id: String, response: RequestPermissionsResponse) {
        permissionContinuations.removeValue(forKey: id)?.resume(returning: response)
    }

    func pendingUserInput(
        id: String,
        notify: @escaping @Sendable () async -> Void
    ) async -> RequestUserInputResponse? {
        await withCheckedContinuation { continuation in
            userInputContinuations.removeValue(forKey: id)?.resume(returning: nil)
            userInputContinuations[id] = continuation
            Task {
                await notify()
            }
        }
    }

    func resolveUserInput(id: String, response: RequestUserInputResponse) {
        userInputContinuations.removeValue(forKey: id)?.resume(returning: response)
    }

    func cancelUserInput(id: String) {
        userInputContinuations.removeValue(forKey: id)?.resume(returning: nil)
    }

    func pendingDynamicTool(
        id: String,
        turnID: String,
        notify: @escaping @Sendable () async -> Void
    ) async -> DynamicToolResponse? {
        await withCheckedContinuation { continuation in
            dynamicToolContinuations.removeValue(forKey: id)?.continuation.resume(returning: nil)
            dynamicToolContinuations[id] = PendingDynamicTool(turnID: turnID, continuation: continuation)
            Task {
                await notify()
            }
        }
    }

    func resolveDynamicTool(id: String, response: DynamicToolResponse) {
        dynamicToolContinuations.removeValue(forKey: id)?.continuation.resume(returning: response)
    }

    func cancelDynamicTool(id: String) {
        dynamicToolContinuations.removeValue(forKey: id)?.continuation.resume(returning: nil)
    }

    func sessionGrantedPermissions(threadID: String) -> RequestPermissionProfile? {
        sessionGrantedPermissionProfiles[threadID]
    }

    func recordSessionGrantedPermissions(threadID: String, permissions: RequestPermissionProfile) {
        sessionGrantedPermissionProfiles[threadID] = RequestPermissionProfile.mergeAdditionalPermissionProfiles(
            base: sessionGrantedPermissionProfiles[threadID],
            permissions: permissions
        )
    }

    func refreshRuntimeConfig(threadID: String, config: ConfigValue) {
        runtimeConfigSnapshots[threadID] = config
    }

    func runtimeConfigSnapshot(threadID: String) -> ConfigValue? {
        runtimeConfigSnapshots[threadID]
    }

    private struct RunningTurn {
        let turnID: String
        let task: Task<Void, Never>
    }

    private struct PendingDynamicTool {
        let turnID: String
        let continuation: CheckedContinuation<DynamicToolResponse?, Never>
    }

    private func finishMailboxWaiter(threadID: String, waiterID: String, result: Bool) {
        mailboxChangeWaiters[threadID]?.removeValue(forKey: waiterID)?.resume(returning: result)
        if mailboxChangeWaiters[threadID]?.isEmpty == true {
            mailboxChangeWaiters.removeValue(forKey: threadID)
        }
    }

    private func finishMailboxWaiters(threadID: String, result: Bool) {
        guard let waiters = mailboxChangeWaiters.removeValue(forKey: threadID) else {
            return
        }
        for waiter in waiters.values {
            waiter.resume(returning: result)
        }
    }

    private func finishAllMailboxWaiters(result: Bool) {
        let waiters = mailboxChangeWaiters.values.flatMap(\.values)
        mailboxChangeWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: result)
        }
    }

    private func maybeNotifyParentOfFinalStatus(threadID: String, status: AgentStatus) {
        guard status.isFinal,
              case let .subagent(.threadSpawn(parentThreadID, _, childAgentPath, _, _)) = sessionSources[threadID],
              let childAgentPath,
              let parentAgentPath = Self.parentAgentPath(of: childAgentPath)
        else {
            return
        }
        let communication = InterAgentCommunication(
            author: childAgentPath,
            recipient: parentAgentPath,
            content: Self.subagentNotificationMessage(
                agentPath: childAgentPath,
                status: status
            ),
            triggerTurn: false
        )
        queueMailboxCommunications(
            threadID: parentThreadID.description,
            communications: [communication]
        )
    }

    private static func parentAgentPath(of childAgentPath: AgentPath) -> AgentPath? {
        let path = childAgentPath.description
        guard let slashIndex = path.lastIndex(of: "/"),
              slashIndex != path.startIndex
        else {
            return nil
        }
        return try? AgentPath(validating: String(path[..<slashIndex]))
    }

    private static func subagentNotificationMessage(agentPath: AgentPath, status: AgentStatus) -> String {
        let statusData = (try? JSONEncoder().encode(status)) ?? Data()
        let statusJSON = String(data: statusData, encoding: .utf8)?.replacingOccurrences(of: "\\/", with: "/")
            ?? "null"
        let body = #"{"agent_path":"\#(agentPath.description)","status":\#(statusJSON)}"#
        return "<subagent_notification>\n\(body)\n</subagent_notification>"
    }

    private func cancelPendingContinuations(turnID: String) {
        userInputContinuations.removeValue(forKey: turnID)?.resume(returning: nil)
        let dynamicIDs = dynamicToolContinuations.compactMap { id, pending in
            pending.turnID == turnID ? id : nil
        }
        for id in dynamicIDs {
            dynamicToolContinuations.removeValue(forKey: id)?.continuation.resume(returning: nil)
        }
    }

    private static func abortKey(threadID: String, turnID: String) -> String {
        "\(threadID):\(turnID)"
    }
}

private struct PreparedLiveTurn: @unchecked Sendable {
    let conversationID: ConversationId
    let rolloutPath: URL
    let recorder: RolloutRecorder?
    let cwd: URL
    let model: String
    let modelFamily: ModelFamily
    let providerInfo: ModelProviderInfo
    let provider: APIProvider
    let auth: StaticAPIAuthProvider
    let authMode: AuthMode?
    let settings: CodexRuntimeConfig
    let approvalPolicy: AskForApproval
    let sandboxPolicy: SandboxPolicy
    let permissionProfile: PermissionProfile
    let shell: Shell
    let turnEnvironmentSelections: [TurnEnvironmentSelection]
    let prompt: Prompt
    let mcpToolInfos: [McpToolInfo]
    let dynamicTools: [DynamicToolSpec]
    let sessionSource: SessionSource
    let collaborationModeKind: CollaborationModeKind?
    let userPromptText: String
    let outputSchema: JSONValue?
    let serviceTier: String?
    let metadata: [String: String]
    let hookHandlers: [ConfiguredHookHandler]
    let sessionStartSource: HookSessionStartSource
}

private struct AppServerRuntimeAuthResolution {
    let auth: StaticAPIAuthProvider
    let authMode: AuthMode?
}

private struct LiveRolloutSummary {
    let id: String
    let cwd: String
    let model: String?
    let modelProvider: String
    let dynamicTools: [DynamicToolSpec]
    let sessionSource: SessionSource
    let collaborationModeKind: CollaborationModeKind?

    init(items: [RolloutRecordItem], defaultProvider: String) throws {
        var sessionMeta: SessionMeta?
        var latestCwd: String?
        var latestModel: String?
        var latestCollaborationModeKind: CollaborationModeKind?
        for item in items {
            switch item {
            case let .sessionMeta(line):
                if sessionMeta == nil {
                    sessionMeta = line.meta
                }
            case let .turnContext(context):
                latestCwd = context.cwd
                latestModel = context.model
                latestCollaborationModeKind = context.collaborationMode?.mode
            case .responseItem, .compacted, .eventMsg:
                continue
            }
        }
        guard let sessionMeta else {
            throw AppServerLiveRuntimeError("failed to parse conversation metadata from rollout")
        }
        self.id = sessionMeta.id.description
        self.cwd = latestCwd ?? sessionMeta.cwd
        self.model = latestModel
        self.modelProvider = sessionMeta.modelProvider ?? defaultProvider
        self.dynamicTools = sessionMeta.dynamicTools ?? []
        self.sessionSource = sessionMeta.source
        self.collaborationModeKind = latestCollaborationModeKind
    }
}

private struct LiveTurnInput {
    let items: [UserInput]
    let environments: [TurnEnvironmentSelection]?
    let outputSchema: JSONValue?
    let responsesAPIClientMetadata: [String: String]?
    let cwd: String?
    let approvalPolicy: AskForApproval?
    let sandboxPolicy: SandboxPolicy?
    let permissionProfile: PermissionProfile?
    let model: String?
    let summary: ReasoningSummary?
    let serviceTier: String?
    let collaborationMode: CollaborationMode?

    init(op: Op) throws {
        switch op {
        case let .userInput(items, environments, outputSchema, metadata):
            self.items = items
            self.environments = environments
            self.outputSchema = outputSchema
            self.responsesAPIClientMetadata = metadata
            self.cwd = nil
            self.approvalPolicy = nil
            self.sandboxPolicy = nil
            self.permissionProfile = nil
            self.model = nil
            self.summary = nil
            self.serviceTier = nil
            self.collaborationMode = nil
        case let .userInputWithTurnContext(params):
            self.items = params.items
            self.environments = params.environments
            self.outputSchema = params.finalOutputJSONSchema
            self.responsesAPIClientMetadata = params.responsesAPIClientMetadata
            self.cwd = params.cwd
            self.approvalPolicy = params.approvalPolicy
            self.sandboxPolicy = params.sandboxPolicy
            self.permissionProfile = params.permissionProfile
            self.model = params.model
            self.summary = params.summary
            self.serviceTier = params.serviceTier?.stringValue
            self.collaborationMode = nil
        case let .userTurn(
            items: items,
            cwd: cwd,
            approvalPolicy: approvalPolicy,
            approvalsReviewer: _,
            sandboxPolicy: sandboxPolicy,
            permissionProfile: permissionProfile,
            model: model,
            effort: _,
            summary: summary,
            serviceTier: serviceTier,
            finalOutputJSONSchema: finalOutputJSONSchema,
            collaborationMode: collaborationMode,
            personality: _,
            environments: environments
        ):
            self.items = items
            self.environments = environments
            self.outputSchema = finalOutputJSONSchema
            self.responsesAPIClientMetadata = nil
            self.cwd = cwd
            self.approvalPolicy = approvalPolicy
            self.sandboxPolicy = sandboxPolicy
            self.permissionProfile = permissionProfile
            self.model = model
            self.summary = summary
            self.serviceTier = serviceTier?.stringValue
            self.collaborationMode = try Self.decodeCollaborationMode(collaborationMode)
        default:
            throw AppServerLiveRuntimeError("unsupported live runtime op: \(op)")
        }
    }

    private static func decodeCollaborationMode(_ value: JSONValue?) throws -> CollaborationMode? {
        guard let value else {
            return nil
        }
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(CollaborationMode.self, from: data)
    }

    var promptText: String {
        items.compactMap { item -> String? in
            if case let .text(text, _) = item {
                return text
            }
            return nil
        }.joined(separator: "\n")
    }
}

private struct AppServerLiveRuntimeError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private enum AppServerLiveRuntimeClock {
    static func millisecondsSinceEpoch() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000).rounded())
    }
}

private enum AppServerLiveRuntimeBlocking {
    static func run<T: Sendable>(_ operation: @escaping @Sendable () async -> T) -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let box = BlockingBox<T>()
        Task {
            box.set(await operation())
            semaphore.signal()
        }
        semaphore.wait()
        return box.value()
    }
}

private final class BlockingBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T?

    func set(_ value: T) {
        lock.withLock {
            stored = value
        }
    }

    func value() -> T {
        lock.withLock {
            stored!
        }
    }
}

private extension JSONValue {
    var stringValue: String? {
        if case let .string(value) = self {
            return value
        }
        return nil
    }
}
