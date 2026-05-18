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

        default:
            return []
        }
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
        do {
            let setup = try await prepareTurn(submission)
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
            sessionSource: configuration.sessionSource,
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
        let userItem = ResponseInputItem(userInputs: turnInput.items).responseItem()
        input.append(userItem)
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
                effort: settings.modelReasoningEffort ?? modelFamily.defaultReasoningEffort,
                summary: turnInput.summary
                    ?? settings.modelReasoningSummary
                    ?? (modelFamily.supportsReasoningSummaries ? .auto : .none),
                finalOutputJSONSchema: turnInput.outputSchema,
                truncationPolicy: modelFamily.truncationPolicy
            )),
            .responseItem(userItem)
        ])
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
            userPromptText: turnInput.promptText,
            outputSchema: turnInput.outputSchema,
            serviceTier: turnInput.serviceTier ?? settings.serviceTier,
            metadata: turnInput.responsesAPIClientMetadata ?? [:],
            hookHandlers: hookHandlers,
            sessionStartSource: .resume
        )
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
            registeredToolExecutor: submission.extensionRegisteredToolExecutor,
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
    private var emittedAbortKeys: Set<String> = []

    func setEventSink(_ sink: AppServerRuntimeEventSink?) {
        eventSink = sink
    }

    func startTurn(threadID: String, turnID: String, task: Task<Void, Never>) {
        runningTurns[threadID]?.task.cancel()
        runningTurns[threadID] = RunningTurn(turnID: turnID, task: task)
    }

    func finishTurn(threadID: String, turnID: String) {
        if runningTurns[threadID]?.turnID == turnID {
            runningTurns.removeValue(forKey: threadID)
        }
        cancelPendingContinuations(turnID: turnID)
        emittedAbortKeys.remove(Self.abortKey(threadID: threadID, turnID: turnID))
    }

    func cancelTurn(threadID: String) -> String? {
        guard let running = runningTurns[threadID] else {
            return nil
        }
        running.task.cancel()
        runningTurns.removeValue(forKey: threadID)
        cancelPendingContinuations(turnID: running.turnID)
        return running.turnID
    }

    func cancelThread(threadID: String) {
        if let running = runningTurns.removeValue(forKey: threadID) {
            running.task.cancel()
            cancelPendingContinuations(turnID: running.turnID)
        }
        sessionGrantedPermissionProfiles.removeValue(forKey: threadID)
        runtimeConfigSnapshots.removeValue(forKey: threadID)
    }

    func cancelAll() {
        let turns = runningTurns.values
        runningTurns.removeAll()
        sessionGrantedPermissionProfiles.removeAll()
        runtimeConfigSnapshots.removeAll()
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
        await eventSink?(threadID, turnID, event)
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

private struct PreparedLiveTurn {
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

    init(items: [RolloutRecordItem], defaultProvider: String) throws {
        var sessionMeta: SessionMeta?
        var latestCwd: String?
        var latestModel: String?
        for item in items {
            switch item {
            case let .sessionMeta(line):
                if sessionMeta == nil {
                    sessionMeta = line.meta
                }
            case let .turnContext(context):
                latestCwd = context.cwd
                latestModel = context.model
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
            collaborationMode: _,
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
        default:
            throw AppServerLiveRuntimeError("unsupported live runtime op: \(op)")
        }
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
