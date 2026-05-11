import CodexApplyPatch
import Darwin
import Foundation

public enum UnifiedExecTiming {
    public static let minYieldTimeMS: UInt64 = 250
    public static let minEmptyYieldTimeMS: UInt64 = 5_000
    public static let maxYieldTimeMS: UInt64 = 30_000

    public static func clampInitialYieldTimeMS(_ yieldTimeMS: UInt64) -> UInt64 {
        min(max(yieldTimeMS, minYieldTimeMS), maxYieldTimeMS)
    }

    public static func clampWriteStdinYieldTimeMS(
        _ yieldTimeMS: UInt64,
        inputIsEmpty: Bool,
        maxEmptyYieldTimeMS: UInt64
    ) -> UInt64 {
        let timeMS = max(yieldTimeMS, minYieldTimeMS)
        if inputIsEmpty {
            return min(max(timeMS, minEmptyYieldTimeMS), max(maxEmptyYieldTimeMS, minEmptyYieldTimeMS))
        }
        return min(timeMS, maxYieldTimeMS)
    }
}

public enum NonInteractiveExecOutputMode: Equatable, Sendable {
    case human
    case jsonLines
}

public struct NonInteractiveExecRunResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdoutMessage: String?
    public let stderrMessages: [String]
    public let lastAgentMessage: String?
    public let tokenUsage: TokenUsage?

    public init(
        exitCode: Int32,
        stdoutMessage: String?,
        stderrMessages: [String],
        lastAgentMessage: String?,
        tokenUsage: TokenUsage?
    ) {
        self.exitCode = exitCode
        self.stdoutMessage = stdoutMessage
        self.stderrMessages = stderrMessages
        self.lastAgentMessage = lastAgentMessage
        self.tokenUsage = tokenUsage
    }
}

public struct NonInteractiveExecLoopResult: Equatable, Sendable {
    public let events: ResponseEventResults
    public let transcriptItems: [ResponseItem]

    public init(events: ResponseEventResults, transcriptItems: [ResponseItem]) {
        self.events = events
        self.transcriptItems = transcriptItems
    }
}

public enum NonInteractiveExec {
    private static let unifiedExecSessions = UnifiedExecSessionRegistry()

    public static func makeInitialPromptInput(
        cwd: URL,
        approvalPolicy: AskForApproval,
        sandboxPolicy: SandboxPolicy,
        shell: Shell,
        includeEnvironmentContext: Bool = true,
        includePermissionsInstructions: Bool = true,
        developerInstructions: String? = nil,
        memoryToolDeveloperInstructions: String? = nil,
        availableSkills: AvailableSkills? = nil,
        userInstructions: UserInstructions? = nil,
        environmentContextEnvironments: [EnvironmentContextEnvironment]? = nil,
        environmentContextCurrentDate: String? = nil,
        environmentContextTimezone: String? = nil,
        environmentContextNetwork: EnvironmentContextNetwork? = nil
    ) -> [ResponseItem] {
        let context = TurnContext(
            cwd: cwd.path,
            approvalPolicy: approvalPolicy,
            sandboxPolicy: sandboxPolicy
        )
        var input: [ResponseItem] = []
        var developerContent: [ContentItem] = []
        if includePermissionsInstructions {
            developerContent.append(
                .inputText(text: PermissionsInstructions.fromPolicy(
                    sandboxPolicy,
                    config: PermissionsPromptConfig(approvalPolicy: approvalPolicy),
                    cwd: cwd.path
                ).render())
            )
        }
        if let developerInstructions, !developerInstructions.isEmpty {
            developerContent.append(.inputText(text: developerInstructions))
        }
        if let memoryToolDeveloperInstructions, !memoryToolDeveloperInstructions.isEmpty {
            developerContent.append(.inputText(text: memoryToolDeveloperInstructions))
        }
        if let availableSkills {
            developerContent.append(.inputText(text: Skills.renderAvailableSkillsBody(
                skillRootLines: availableSkills.skillRootLines,
                skillLines: availableSkills.skillLines
            )))
        }
        if !developerContent.isEmpty {
            input.append(.message(role: "developer", content: developerContent))
        }

        var contextualUserContent: [ContentItem] = []
        if let userInstructions {
            contextualUserContent.append(.inputText(text: userInstructions.intoText()))
        }
        if includeEnvironmentContext {
            contextualUserContent.append(
                .inputText(text: EnvironmentContext(
                    cwd: context.cwd,
                    approvalPolicy: context.approvalPolicy,
                    sandboxPolicy: context.sandboxPolicy,
                    shell: shell,
                    environments: environmentContextEnvironments,
                    currentDate: environmentContextCurrentDate,
                    timezone: environmentContextTimezone,
                    network: environmentContextNetwork
                ).serializeToXML())
            )
        }
        if !contextualUserContent.isEmpty {
            input.append(.message(role: "user", content: contextualUserContent))
        }
        return input
    }

    public static func makePrompt(
        prompt: String,
        imagePaths: [String],
        outputSchema: JSONValue?,
        cwd: URL,
        approvalPolicy: AskForApproval,
        sandboxPolicy: SandboxPolicy,
        shell: Shell,
        includeEnvironmentContext: Bool = true,
        includePermissionsInstructions: Bool = true,
        developerInstructions: String? = nil,
        memoryToolDeveloperInstructions: String? = nil,
        availableSkills: AvailableSkills? = nil,
        userInstructions: UserInstructions? = nil,
        environmentContextEnvironments: [EnvironmentContextEnvironment]? = nil,
        environmentContextCurrentDate: String? = nil,
        environmentContextTimezone: String? = nil,
        environmentContextNetwork: EnvironmentContextNetwork? = nil,
        history: [ResponseItem] = [],
        tools: [ToolSpec] = [],
        parallelToolCalls: Bool = false
    ) -> Prompt {
        var input = makeInitialPromptInput(
            cwd: cwd,
            approvalPolicy: approvalPolicy,
            sandboxPolicy: sandboxPolicy,
            shell: shell,
            includeEnvironmentContext: includeEnvironmentContext,
            includePermissionsInstructions: includePermissionsInstructions,
            developerInstructions: developerInstructions,
            memoryToolDeveloperInstructions: memoryToolDeveloperInstructions,
            availableSkills: availableSkills,
            userInstructions: userInstructions,
            environmentContextEnvironments: environmentContextEnvironments,
            environmentContextCurrentDate: environmentContextCurrentDate,
            environmentContextTimezone: environmentContextTimezone,
            environmentContextNetwork: environmentContextNetwork
        )
        input.append(contentsOf: history)

        let userInputs = imagePaths.map { UserInput.localImage(path: $0) } + [.text(prompt)]
        input.append(ResponseInputItem(userInputs: userInputs).responseItem())

        return Prompt(
            input: input,
            tools: tools,
            parallelToolCalls: parallelToolCalls,
            outputSchema: outputSchema
        )
    }

    public static func toolsConfig(
        modelFamily: ModelFamily,
        config: CodexRuntimeConfig
    ) -> ToolsConfig {
        let shellType: ConfigShellToolType
        if !config.features.isEnabled(.shellTool) {
            shellType = .disabled
        } else if config.features.isEnabled(.unifiedExec) || config.experimentalUseUnifiedExecTool == true {
            shellType = .unifiedExec
        } else {
            shellType = modelFamily.shellType
        }

        let applyPatchToolType = modelFamily.applyPatchToolType
            ?? ((config.features.isEnabled(.applyPatchFreeform)
                 || config.includeApplyPatchTool == true
                 || config.experimentalUseFreeformApplyPatch == true)
                ? .freeform
                : nil)

        return ToolsConfig(
            shellType: shellType,
            applyPatchToolType: applyPatchToolType,
            webSearchMode: webSearchMode(for: config),
            webSearchConfig: config.webSearchConfig,
            includeViewImageTool: config.toolsViewImage ?? true,
            includeComputerUseTools: config.features.isEnabled(.computerUse),
            experimentalSupportedTools: modelFamily.experimentalSupportedTools,
            toolSearch: config.features.isEnabled(.toolSearch),
            toolSuggest: config.features.isEnabled(.toolSuggest),
            allowLoginShell: config.allowLoginShell
        )
    }

    public static func toolSpecs(
        modelFamily: ModelFamily,
        config: CodexRuntimeConfig
    ) -> [ConfiguredToolSpec] {
        ToolSpecFactory.buildSpecs(config: toolsConfig(modelFamily: modelFamily, config: config))
    }

    private static func webSearchMode(for config: CodexRuntimeConfig) -> WebSearchMode? {
        if let mode = config.webSearchMode {
            return mode
        }
        if config.features.isEnabled(.webSearchCached) {
            return .cached
        }
        if let legacyEnabled = config.toolsWebSearch {
            return legacyEnabled ? .live : .disabled
        }
        if config.features.isEnabled(.webSearchRequest) {
            return .live
        }
        return nil
    }

    public static func responsesOptions(
        conversationID: ConversationId,
        modelFamily: ModelFamily,
        reasoningEffort: ReasoningEffort?,
        reasoningSummary: ReasoningSummary?,
        verbosity: Verbosity?,
        serviceTier: String? = nil,
        outputSchema: JSONValue?,
        requestTrace: W3CTraceContext? = nil
    ) -> ResponsesOptions {
        let effort = reasoningEffort ?? modelFamily.defaultReasoningEffort
        let summary = reasoningSummary ?? (modelFamily.supportsReasoningSummaries
            ? modelFamily.defaultReasoningSummary
            : nil)
        let reasoning = effort == nil && summary == nil
            ? nil
            : ResponsesAPIReasoning(effort: effort, summary: summary)

        return ResponsesOptions(
            reasoning: reasoning,
            serviceTier: serviceTier,
            text: ResponsesAPITextControls.createForRequest(
                verbosity: verbosity ?? modelFamily.defaultVerbosity,
                outputSchema: outputSchema
            ),
            inputModalities: modelFamily.inputModalities,
            conversationID: conversationID.description,
            sessionSource: .exec,
            clientMetadata: ResponsesClientMetadata.create(trace: requestTrace) ?? [:]
        )
    }

    public typealias ResponseStreamer = (Prompt) async -> Result<ResponseEventResults, APIError>
    public typealias FunctionCallExecutor = (ResponseItem) async -> ResponseItem
    public typealias FunctionCallResultExecutor = (ResponseItem) async -> FunctionCallExecutionResult

    public struct FunctionCallExecutionResult: Equatable, Sendable {
        public var output: ResponseItem
        public var additionalContextItems: [ResponseItem]

        public init(output: ResponseItem, additionalContextItems: [ResponseItem] = []) {
            self.output = output
            self.additionalContextItems = additionalContextItems
        }
    }

    public struct StopHookContext: Equatable, Sendable {
        public var handlers: [ConfiguredHookHandler]
        public var conversationID: ConversationId
        public var turnID: String
        public var cwd: URL
        public var model: String
        public var approvalPolicy: AskForApproval

        public init(
            handlers: [ConfiguredHookHandler],
            conversationID: ConversationId,
            turnID: String,
            cwd: URL,
            model: String,
            approvalPolicy: AskForApproval
        ) {
            self.handlers = handlers
            self.conversationID = conversationID
            self.turnID = turnID
            self.cwd = cwd
            self.model = model
            self.approvalPolicy = approvalPolicy
        }
    }

    public struct AgentJobToolContext: Sendable {
        public var store: SQLiteAgentJobStore
        public var reportingThreadID: String
        public var maxThreads: Int?
        public var configuredMaxRuntimeSeconds: UInt64?
        public var statusForThread: (@Sendable (ThreadId) async -> AgentStatus)?
        public var spawnWorker: (@Sendable (AgentJobWorkerSpawnRequest) async -> AgentJobWorkerSpawnResult)?
        public var shutdownThread: (@Sendable (ThreadId) async -> Void)?
        public var waitWhenIdle: (@Sendable () async -> Void)?

        public init(
            store: SQLiteAgentJobStore,
            reportingThreadID: String,
            maxThreads: Int? = nil,
            configuredMaxRuntimeSeconds: UInt64? = nil,
            statusForThread: (@Sendable (ThreadId) async -> AgentStatus)? = nil,
            spawnWorker: (@Sendable (AgentJobWorkerSpawnRequest) async -> AgentJobWorkerSpawnResult)? = nil,
            shutdownThread: (@Sendable (ThreadId) async -> Void)? = nil,
            waitWhenIdle: (@Sendable () async -> Void)? = nil
        ) {
            self.store = store
            self.reportingThreadID = reportingThreadID
            self.maxThreads = maxThreads
            self.configuredMaxRuntimeSeconds = configuredMaxRuntimeSeconds
            self.statusForThread = statusForThread
            self.spawnWorker = spawnWorker
            self.shutdownThread = shutdownThread
            self.waitWhenIdle = waitWhenIdle
        }
    }

    public static func runResponsesLoop(
        initialPrompt: Prompt,
        maxToolIterations: Int = 20,
        streamPrompt: ResponseStreamer,
        executeFunctionCall: FunctionCallExecutor
    ) async -> ResponseEventResults {
        await runResponsesLoopWithTranscript(
            initialPrompt: initialPrompt,
            maxToolIterations: maxToolIterations,
            streamPrompt: streamPrompt,
            executeFunctionCall: executeFunctionCall
        ).events
    }

    public static func runResponsesLoopWithTranscript(
        initialPrompt: Prompt,
        maxToolIterations: Int = 20,
        streamPrompt: ResponseStreamer,
        executeFunctionCall: FunctionCallExecutor
    ) async -> NonInteractiveExecLoopResult {
        await runResponsesLoopWithTranscript(
            initialPrompt: initialPrompt,
            maxToolIterations: maxToolIterations,
            streamPrompt: streamPrompt,
            executeFunctionCall: { item in
                FunctionCallExecutionResult(output: await executeFunctionCall(item))
            }
        )
    }

    public static func runResponsesLoopWithTranscript(
        initialPrompt: Prompt,
        maxToolIterations: Int = 20,
        streamPrompt: ResponseStreamer,
        stopHookContext: StopHookContext? = nil,
        executeFunctionCall: FunctionCallResultExecutor
    ) async -> NonInteractiveExecLoopResult {
        var prompt = initialPrompt
        var allEvents: ResponseEventResults = []
        var transcriptItems: [ResponseItem] = []
        var stopHookActive = false

        for _ in 0..<maxToolIterations {
            let streamResult = await streamPrompt(prompt)
            let turnEvents: ResponseEventResults
            switch streamResult {
            case let .success(results):
                turnEvents = results
            case let .failure(error):
                turnEvents = [.failure(error)]
            }

            allEvents.append(contentsOf: turnEvents)
            if containsFailure(turnEvents) {
                return NonInteractiveExecLoopResult(events: allEvents, transcriptItems: transcriptItems)
            }

            let completedItems = completedOutputItems(from: turnEvents)
            transcriptItems.append(contentsOf: completedItems)
            prompt.input.append(contentsOf: completedItems)

            let toolCalls = toolCalls(from: completedItems)
            if toolCalls.isEmpty {
                if completedResponseNeedsFollowUp(turnEvents) {
                    continue
                }
                if let stopHookContext {
                    let stopOutcome = await runStopHooks(
                        context: stopHookContext,
                        stopHookActive: stopHookActive,
                        lastAssistantMessage: lastAssistantMessage(from: transcriptItems)
                    )
                    if stopOutcome.shouldBlock {
                        let continuationItems = stopContinuationItems(stopOutcome.continuationFragments)
                        prompt.input.append(contentsOf: continuationItems)
                        transcriptItems.append(contentsOf: continuationItems)
                        stopHookActive = true
                        continue
                    }
                    if stopOutcome.shouldStop {
                        return NonInteractiveExecLoopResult(events: allEvents, transcriptItems: transcriptItems)
                    }
                }
                return NonInteractiveExecLoopResult(events: allEvents, transcriptItems: transcriptItems)
            }

            for call in toolCalls {
                let result = await executeFunctionCall(call)
                prompt.input.append(result.output)
                transcriptItems.append(result.output)
                if !result.additionalContextItems.isEmpty {
                    prompt.input.append(contentsOf: result.additionalContextItems)
                    transcriptItems.append(contentsOf: result.additionalContextItems)
                }
            }
        }

        allEvents.append(.failure(.stream("too many tool call iterations")))
        return NonInteractiveExecLoopResult(events: allEvents, transcriptItems: transcriptItems)
    }

    public static func runUserPromptSubmitHooks(
        handlers: [ConfiguredHookHandler],
        prompt: inout Prompt,
        userPrompt: String,
        conversationID: ConversationId,
        turnID: String,
        cwd: URL,
        model: String,
        approvalPolicy: AskForApproval
    ) async -> HookUserPromptSubmitOutcome {
        let request: HookUserPromptSubmitRequest
        do {
            request = try HookUserPromptSubmitRequest(
                sessionID: ThreadId(uuid: conversationID.uuid),
                turnID: turnID,
                cwd: AbsolutePath(absolutePath: cwd.standardizedFileURL.path),
                model: model,
                permissionMode: hookPermissionMode(approvalPolicy),
                prompt: userPrompt
            )
        } catch {
            return HookUserPromptSubmitOutcome(
                hookEvents: [],
                shouldStop: false,
                stopReason: nil,
                additionalContexts: []
            )
        }

        var outcome = await HookUserPromptSubmit.run(
            handlers: handlers,
            shell: HookCommandShell(),
            request: request
        )
        outcome.additionalContexts = HookOutputSpiller().maybeSpillTexts(
            threadID: ThreadId(uuid: conversationID.uuid),
            texts: outcome.additionalContexts
        )
        guard !outcome.shouldStop else {
            return outcome
        }
        prompt.input.append(contentsOf: outcome.additionalContexts.map { context in
            ResponseInputItem(userInputs: [.text(context)]).responseItem()
        })
        return outcome
    }

    public static func runSessionStartHooks(
        handlers: [ConfiguredHookHandler],
        prompt: inout Prompt,
        conversationID: ConversationId,
        cwd: URL,
        model: String,
        approvalPolicy: AskForApproval,
        source: HookSessionStartSource
    ) async -> HookSessionStartOutcome {
        let request: HookSessionStartRequest
        do {
            request = try HookSessionStartRequest(
                sessionID: ThreadId(uuid: conversationID.uuid),
                cwd: AbsolutePath(absolutePath: cwd.standardizedFileURL.path),
                model: model,
                permissionMode: hookPermissionMode(approvalPolicy),
                source: source
            )
        } catch {
            return HookSessionStartOutcome(
                hookEvents: [],
                shouldStop: false,
                stopReason: nil,
                additionalContexts: []
            )
        }

        var outcome = await HookSessionStart.run(
            handlers: handlers,
            shell: HookCommandShell(),
            request: request,
            turnID: nil
        )
        outcome.additionalContexts = HookOutputSpiller().maybeSpillTexts(
            threadID: ThreadId(uuid: conversationID.uuid),
            texts: outcome.additionalContexts
        )
        guard !outcome.shouldStop else {
            return outcome
        }
        prompt.input.append(contentsOf: outcome.additionalContexts.map { context in
            ResponseInputItem(userInputs: [.text(context)]).responseItem()
        })
        return outcome
    }

    private static func runStopHooks(
        context: StopHookContext,
        stopHookActive: Bool,
        lastAssistantMessage: String?
    ) async -> HookStopOutcome {
        do {
            let request = try HookStopRequest(
                sessionID: ThreadId(uuid: context.conversationID.uuid),
                turnID: context.turnID,
                cwd: AbsolutePath(absolutePath: context.cwd.standardizedFileURL.path),
                model: context.model,
                permissionMode: hookPermissionMode(context.approvalPolicy),
                stopHookActive: stopHookActive,
                lastAssistantMessage: lastAssistantMessage
            )
            var outcome = await HookStop.run(
                handlers: context.handlers,
                shell: HookCommandShell(),
                request: request
            )
            outcome.continuationFragments = HookOutputSpiller().maybeSpillPromptFragments(
                threadID: ThreadId(uuid: context.conversationID.uuid),
                fragments: outcome.continuationFragments
            )
            return outcome
        } catch {
            return HookStopOutcome(
                hookEvents: [],
                shouldStop: false,
                stopReason: nil,
                shouldBlock: false,
                blockReason: nil,
                continuationFragments: []
            )
        }
    }

    private static func stopContinuationItems(_ fragments: [HookPromptFragment]) -> [ResponseItem] {
        HookPromptItem.buildMessage(fragments: fragments).map { [$0] } ?? []
    }

    private static func lastAssistantMessage(from items: [ResponseItem]) -> String? {
        items.reversed().compactMap(StreamEventUtils.lastAssistantMessage(from:)).first
    }

    public static func executeFunctionCall(
        _ item: ResponseItem,
        cwd: URL,
        approvalPolicy: AskForApproval,
        sandboxPolicy: SandboxPolicy,
        shell: Shell,
        truncationPolicy: TruncationPolicy,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        explicitEnvOverrides: [String: String] = [:],
        allowLoginShell: Bool = true,
        backgroundTerminalMaxTimeoutMS: UInt64 = CodexConfigDefaults.backgroundTerminalMaxTimeoutMS,
        toolSearchIndex: ToolSearchIndex? = nil,
        agentJobContext: AgentJobToolContext? = nil
    ) async -> ResponseItem {
        switch item {
        case let .functionCall(_, name, _, arguments, callID):
            return await executeFunctionCall(
                name: name,
                arguments: arguments,
                callID: callID,
                cwd: cwd,
                approvalPolicy: approvalPolicy,
                sandboxPolicy: sandboxPolicy,
                shell: shell,
                truncationPolicy: truncationPolicy,
                environment: environment,
                explicitEnvOverrides: explicitEnvOverrides,
                allowLoginShell: allowLoginShell,
                backgroundTerminalMaxTimeoutMS: backgroundTerminalMaxTimeoutMS,
                agentJobContext: agentJobContext
            )

        case let .customToolCall(_, _, callID, name, input):
            return executeCustomToolCall(
                name: name,
                input: input,
                callID: callID,
                cwd: cwd,
                approvalPolicy: approvalPolicy,
                sandboxPolicy: sandboxPolicy,
                environment: environment
            )

        case let .localShellCall(id, callID, _, action):
            guard case let .exec(params) = action else {
                return functionOutput(
                    callID: callID ?? id ?? "local_shell",
                    content: "unsupported local_shell action",
                    success: false
                )
            }
            return await executeShellCommand(
                toolName: "local_shell",
                command: params.command,
                sessionShell: shell,
                workdir: params.workingDirectory,
                timeoutMS: params.timeoutMS,
                sandboxPermissions: .useDefault,
                callID: callID ?? id ?? "local_shell",
                cwd: cwd,
                approvalPolicy: approvalPolicy,
                sandboxPolicy: sandboxPolicy,
                truncationPolicy: truncationPolicy,
                environment: environment,
                explicitEnvOverrides: explicitEnvOverrides,
                responseFormat: .structured
            )

        case let .toolSearchCall(_, callID, _, execution, arguments):
            guard let callID, execution == "client" else {
                return .toolSearchOutput(callID: callID, status: "completed", execution: execution, tools: [])
            }
            guard let toolSearchIndex else {
                return .toolSearchOutput(callID: callID, status: "completed", execution: "client", tools: [])
            }
            do {
                return .toolSearchOutput(
                    callID: callID,
                    status: "completed",
                    execution: "client",
                    tools: try toolSearchIndex.search(arguments: arguments)
                )
            } catch {
                return functionOutput(callID: callID, content: String(describing: error), success: false)
            }

        default:
            return functionOutput(
                callID: "unknown",
                content: "unsupported tool response item",
                success: false
            )
        }
    }

    public static func executeFunctionCallWithHooks(
        _ item: ResponseItem,
        handlers: [ConfiguredHookHandler],
        conversationID: ConversationId,
        turnID: String,
        cwd: URL,
        model: String,
        approvalPolicy: AskForApproval,
        sandboxPolicy: SandboxPolicy,
        shell: Shell,
        truncationPolicy: TruncationPolicy,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        explicitEnvOverrides: [String: String] = [:],
        allowLoginShell: Bool = true,
        backgroundTerminalMaxTimeoutMS: UInt64 = CodexConfigDefaults.backgroundTerminalMaxTimeoutMS,
        toolSearchIndex: ToolSearchIndex? = nil,
        agentJobContext: AgentJobToolContext? = nil
    ) async -> FunctionCallExecutionResult {
        let hookPayload = toolHookPayload(for: item)
        if let hookPayload {
            let preOutcome = await runPreToolUseHooks(
                handlers: handlers,
                hookPayload: hookPayload,
                conversationID: conversationID,
                turnID: turnID,
                cwd: cwd,
                model: model,
                approvalPolicy: approvalPolicy
            )
            var additionalItems = hookAdditionalContextItems(preOutcome.additionalContexts)
            if preOutcome.shouldBlock {
                return FunctionCallExecutionResult(
                    output: blockedToolOutput(for: item, hookPayload: hookPayload, reason: preOutcome.blockReason),
                    additionalContextItems: additionalItems
                )
            }
            if hookPayload.sandboxPermissions.requiresEscalatedPermissions,
               let permissionDecision = await runPermissionRequestHooks(
                   handlers: handlers,
                   hookPayload: hookPayload,
                   conversationID: conversationID,
                   turnID: turnID,
                   cwd: cwd,
                   model: model,
                   approvalPolicy: approvalPolicy
               )
            {
                switch permissionDecision {
                case .allow:
                    break
                case let .deny(message):
                    return FunctionCallExecutionResult(
                        output: deniedPermissionOutput(for: item, hookPayload: hookPayload, message: message),
                        additionalContextItems: additionalItems
                    )
                }
            }

            let output = await executeFunctionCall(
                item,
                cwd: cwd,
                approvalPolicy: approvalPolicy,
                sandboxPolicy: sandboxPolicy,
                shell: shell,
                truncationPolicy: truncationPolicy,
                environment: environment,
                explicitEnvOverrides: explicitEnvOverrides,
                allowLoginShell: allowLoginShell,
                backgroundTerminalMaxTimeoutMS: backgroundTerminalMaxTimeoutMS,
                toolSearchIndex: toolSearchIndex,
                agentJobContext: agentJobContext
            )
            guard toolOutputSucceeded(output),
                  let postPayload = postToolHookPayload(for: item, output: output, prePayload: hookPayload)
            else {
                return FunctionCallExecutionResult(output: output, additionalContextItems: additionalItems)
            }

            let postOutcome = await runPostToolUseHooks(
                handlers: handlers,
                hookPayload: postPayload,
                conversationID: conversationID,
                turnID: turnID,
                cwd: cwd,
                model: model,
                approvalPolicy: approvalPolicy
            )
            additionalItems.append(contentsOf: hookAdditionalContextItems(postOutcome.additionalContexts))
            return FunctionCallExecutionResult(
                output: replacingToolOutputIfNeeded(output, with: postOutcome),
                additionalContextItems: additionalItems
            )
        }

        let output = await executeFunctionCall(
            item,
            cwd: cwd,
            approvalPolicy: approvalPolicy,
            sandboxPolicy: sandboxPolicy,
            shell: shell,
            truncationPolicy: truncationPolicy,
            environment: environment,
            explicitEnvOverrides: explicitEnvOverrides,
            allowLoginShell: allowLoginShell,
            backgroundTerminalMaxTimeoutMS: backgroundTerminalMaxTimeoutMS,
            toolSearchIndex: toolSearchIndex,
            agentJobContext: agentJobContext
        )
        return FunctionCallExecutionResult(output: output)
    }

    public static func finish(
        responseEvents: ResponseEventResults,
        outputMode: NonInteractiveExecOutputMode,
        conversationID: ConversationId,
        lastMessageFile: String?,
        writeFile: NonInteractiveInput.FileWriter? = nil
    ) -> NonInteractiveExecRunResult {
        let events = ResponseEventAggregator.aggregate(responseEvents, mode: .aggregatedOnly)
        var lastAgentMessage: String?
        var tokenUsage: TokenUsage?
        var errors: [String] = []
        var sawCompletion = false
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.withoutEscapingSlashes]
        var jsonLines: [String] = []

        if outputMode == .jsonLines {
            jsonLines.append(encodeJSONLine(ThreadStartedEvent(threadID: conversationID.description), using: jsonEncoder))
            jsonLines.append(encodeJSONLine(TurnStartedEvent(), using: jsonEncoder))
        }

        var itemIndex = 0
        for result in events {
            switch result {
            case let .failure(error):
                let message = String(describing: error)
                errors.append(message)
                if outputMode == .jsonLines {
                    jsonLines.append(encodeJSONLine(ErrorJSONEvent(message: message), using: jsonEncoder))
                }

            case let .success(event):
                switch event {
                case let .outputItemDone(item):
                    if let message = StreamEventUtils.lastAssistantMessage(from: item) {
                        lastAgentMessage = message
                    }
                    if outputMode == .jsonLines,
                       let completedItem = execJSONCompletedItem(from: item, itemIndex: itemIndex)
                    {
                        jsonLines.append(encodeJSONLine(
                            ExecJSONItemCompletedEvent(item: completedItem),
                            using: jsonEncoder
                        ))
                        itemIndex += 1
                    }

                case let .completed(_, usage, _):
                    sawCompletion = true
                    tokenUsage = usage

                case .created,
                     .outputItemAdded,
                     .outputTextDelta,
                     .reasoningSummaryDelta,
                     .reasoningContentDelta,
                     .reasoningSummaryPartAdded,
                     .toolCallInputDelta,
                     .rateLimits,
                     .serverModel,
                     .modelVerifications,
                     .serverReasoningIncluded,
                     .modelsETag:
                    continue
                }
            }
        }

        if !sawCompletion, errors.isEmpty {
            errors.append("stream closed before response.completed")
        }

        let lastMessageWrite = NonInteractiveInput.writeLastMessage(
            lastAgentMessage,
            path: lastMessageFile,
            writeFile: writeFile ?? defaultWriteFile
        )

        let exitCode: Int32 = errors.isEmpty ? 0 : 1
        var stderrMessages = errors
        stderrMessages.append(contentsOf: lastMessageWrite.stderrMessages)

        if outputMode == .jsonLines {
            if errors.isEmpty {
                jsonLines.append(encodeJSONLine(TurnCompletedEvent(usage: JSONUsage(tokenUsage)), using: jsonEncoder))
            } else {
                jsonLines.append(encodeJSONLine(
                    TurnFailedEvent(error: ThreadErrorJSONEvent(message: errors.last ?? "unknown error")),
                    using: jsonEncoder
                ))
            }
        }

        let stdoutMessage: String?
        switch outputMode {
        case .human:
            stdoutMessage = lastAgentMessage
        case .jsonLines:
            stdoutMessage = jsonLines.joined(separator: "\n")
        }

        return NonInteractiveExecRunResult(
            exitCode: exitCode,
            stdoutMessage: stdoutMessage,
            stderrMessages: stderrMessages,
            lastAgentMessage: lastAgentMessage,
            tokenUsage: tokenUsage
        )
    }

    private static func execJSONCompletedItem(from item: ResponseItem, itemIndex: Int) -> CompletedItem? {
        let id = "item_\(itemIndex)"
        if let message = StreamEventUtils.lastAssistantMessage(from: item) {
            return CompletedItem(id: id, type: "agent_message", text: message)
        }
        if let reasoningText = reasoningText(from: item) {
            return CompletedItem(id: id, type: "reasoning", text: reasoningText)
        }
        if case let .webSearchCall(_, _, action) = item {
            return CompletedItem(id: id, type: "web_search", query: action?.detail ?? "")
        }
        return nil
    }

    private enum ShellResponseFormat {
        case structured
        case freeform
        case unifiedExec
    }

    private static func executeFunctionCall(
        name: String,
        arguments: String,
        callID: String,
        cwd: URL,
        approvalPolicy: AskForApproval,
        sandboxPolicy: SandboxPolicy,
        shell: Shell,
        truncationPolicy: TruncationPolicy,
        environment: [String: String],
        explicitEnvOverrides: [String: String],
        allowLoginShell: Bool,
        backgroundTerminalMaxTimeoutMS: UInt64,
        agentJobContext: AgentJobToolContext?
    ) async -> ResponseItem {
        let decoder = JSONDecoder()
        do {
            switch name {
            case "exec_command":
                let params = try decoder.decode(ExecCommandToolCallParams.self, from: Data(arguments.utf8))
                let useLoginShell = try resolveUseLoginShell(params.requestedLogin, allowLoginShell: allowLoginShell)
                let requestedShell = params.shell.map(ShellResolver.getShellByModelProvidedPath) ?? shell
                let snapshotShell = params.shell == nil ? shell : nil
                let command = ShellResolver.prefixPowerShellScriptWithUTF8(
                    requestedShell.deriveExecArgs(command: params.cmd, useLoginShell: useLoginShell)
                )
                return await executeUnifiedExecCommand(
                    command: command,
                    sessionShell: snapshotShell,
                    workdir: params.workdir,
                    timeoutMS: params.yieldTimeMS,
                    sandboxPermissions: params.sandboxPermissions,
                    callID: callID,
                    cwd: cwd,
                    approvalPolicy: approvalPolicy,
                    sandboxPolicy: sandboxPolicy,
                    truncationPolicy: params.maxOutputTokens.map { .tokens($0) } ?? truncationPolicy,
                    environment: environment,
                    explicitEnvOverrides: explicitEnvOverrides
                )

            case "shell_command":
                let params = try decoder.decode(ShellCommandToolCallParams.self, from: Data(arguments.utf8))
                let useLoginShell = try resolveUseLoginShell(params.login, allowLoginShell: allowLoginShell)
                let command = ShellResolver.prefixPowerShellScriptWithUTF8(
                    shell.deriveExecArgs(command: params.command, useLoginShell: useLoginShell)
                )
                return await executeShellCommand(
                    toolName: name,
                    command: command,
                    sessionShell: shell,
                    workdir: params.workdir,
                    timeoutMS: params.timeoutMS,
                    sandboxPermissions: params.sandboxPermissions ?? .useDefault,
                    callID: callID,
                    cwd: cwd,
                    approvalPolicy: approvalPolicy,
                    sandboxPolicy: sandboxPolicy,
                    truncationPolicy: truncationPolicy,
                    environment: environment,
                    explicitEnvOverrides: explicitEnvOverrides,
                    responseFormat: .freeform
                )

            case "shell", "container.exec":
                let params = try decoder.decode(ShellToolCallParams.self, from: Data(arguments.utf8))
                return await executeShellCommand(
                    toolName: name,
                    command: params.command,
                    sessionShell: shell,
                    workdir: params.workdir,
                    timeoutMS: params.timeoutMS,
                    sandboxPermissions: params.sandboxPermissions ?? .useDefault,
                    callID: callID,
                    cwd: cwd,
                    approvalPolicy: approvalPolicy,
                    sandboxPolicy: sandboxPolicy,
                    truncationPolicy: truncationPolicy,
                    environment: environment,
                    explicitEnvOverrides: explicitEnvOverrides,
                    responseFormat: .structured
                )

            case "write_stdin":
                let params = try decoder.decode(WriteStdinToolCallParams.self, from: Data(arguments.utf8))
                do {
                    let output = try await unifiedExecSessions.writeStdin(
                        sessionID: String(params.sessionID),
                        chars: params.chars,
                        yieldTimeMS: params.yieldTimeMS,
                        maxEmptyYieldTimeMS: backgroundTerminalMaxTimeoutMS,
                        truncationPolicy: params.maxOutputTokens.map { .tokens($0) } ?? truncationPolicy
                    )
                    return functionOutput(
                        callID: callID,
                        content: formatUnifiedExecResponse(output),
                        success: true
                    )
                } catch {
                    return functionOutput(
                        callID: callID,
                        content: "write_stdin failed: \(String(describing: error))",
                        success: false
                    )
                }

            case "spawn_agents_on_csv":
                guard let agentJobContext,
                      let statusForThread = agentJobContext.statusForThread,
                      let spawnWorker = agentJobContext.spawnWorker,
                      let shutdownThread = agentJobContext.shutdownThread
                else {
                    return functionOutput(
                        callID: callID,
                        content: "unsupported tool: \(name)",
                        success: false
                    )
                }
                do {
                    let inputCSVPath = resolveAgentJobPath(
                        try AgentJobRuntime.decodeSpawnAgentsOnCSVArguments(arguments).csvPath,
                        cwd: cwd
                    )
                    let csvContent: String
                    do {
                        csvContent = try String(contentsOfFile: inputCSVPath, encoding: .utf8)
                    } catch {
                        throw FunctionCallError.respondToModel(
                            "failed to read csv input \(inputCSVPath): \(error)"
                        )
                    }
                    let prepared = try await AgentJobRuntime.createSpawnAgentsOnCSVJob(
                        argumentsJSON: arguments,
                        csvContent: csvContent,
                        cwd: cwd.path,
                        store: agentJobContext.store,
                        maxThreads: agentJobContext.maxThreads,
                        configuredMaxRuntimeSeconds: agentJobContext.configuredMaxRuntimeSeconds
                    )
                    let finalJob: AgentJob
                    do {
                        finalJob = try await AgentJobRuntime.runAgentJobLoop(
                            store: agentJobContext.store,
                            jobID: prepared.job.id,
                            maxConcurrency: prepared.concurrency,
                            spawnConfig: prepared.spawnConfig,
                            statusForThread: statusForThread,
                            spawnWorker: spawnWorker,
                            shutdownThread: shutdownThread,
                            waitWhenIdle: agentJobContext.waitWhenIdle ?? {}
                        )
                    } catch {
                        let errorMessage = "job runner failed: \(error)"
                        try? await agentJobContext.store.markAgentJobFailed(
                            prepared.job.id,
                            errorMessage: errorMessage
                        )
                        throw FunctionCallError.respondToModel(
                            "agent job \(prepared.job.id) failed: \(error)"
                        )
                    }
                    let result = try await AgentJobRuntime.makeSpawnAgentsOnCSVResult(
                        store: agentJobContext.store,
                        job: finalJob
                    )
                    let data = try JSONEncoder().encode(result)
                    return functionOutput(
                        callID: callID,
                        content: String(decoding: data, as: UTF8.self),
                        success: true
                    )
                } catch let error as FunctionCallError {
                    return functionOutput(callID: callID, content: error.description, success: false)
                } catch {
                    return functionOutput(
                        callID: callID,
                        content: "failed to handle \(name): \(String(describing: error))",
                        success: false
                    )
                }

            case "report_agent_job_result":
                guard let agentJobContext else {
                    return functionOutput(
                        callID: callID,
                        content: "unsupported tool: \(name)",
                        success: false
                    )
                }
                do {
                    let result = try await AgentJobRuntime.recordReportAgentJobResult(
                        argumentsJSON: arguments,
                        reportingThreadID: agentJobContext.reportingThreadID,
                        store: agentJobContext.store
                    )
                    let data = try JSONEncoder().encode(result)
                    return functionOutput(
                        callID: callID,
                        content: String(decoding: data, as: UTF8.self),
                        success: true
                    )
                } catch let error as FunctionCallError {
                    return functionOutput(callID: callID, content: error.description, success: false)
                } catch {
                    return functionOutput(
                        callID: callID,
                        content: "failed to handle \(name): \(String(describing: error))",
                        success: false
                    )
                }

            default:
                return functionOutput(
                    callID: callID,
                    content: "unsupported tool: \(name)",
                    success: false
                )
            }
        } catch let error as FunctionCallError {
            return functionOutput(callID: callID, content: error.description, success: false)
        } catch {
            return functionOutput(
                callID: callID,
                content: "failed to parse \(name) arguments: \(String(describing: error))",
                success: false
            )
        }
    }

    private static func resolveUseLoginShell(
        _ login: Bool?,
        allowLoginShell: Bool
    ) throws -> Bool {
        if !allowLoginShell, login == true {
            throw FunctionCallError.respondToModel(
                "login shell is disabled by config; omit `login` or set it to false."
            )
        }
        return login ?? allowLoginShell
    }

    private static func resolveAgentJobPath(_ path: String, cwd: URL) -> String {
        let url = path.hasPrefix("/")
            ? URL(fileURLWithPath: path)
            : cwd.appendingPathComponent(path)
        return url.standardizedFileURL.path
    }

    private static func executeShellCommand(
        toolName: String,
        command: [String],
        sessionShell: Shell?,
        workdir: String?,
        timeoutMS: UInt64?,
        sandboxPermissions: SandboxPermissions,
        callID: String,
        cwd: URL,
        approvalPolicy: AskForApproval,
        sandboxPolicy: SandboxPolicy,
        truncationPolicy: TruncationPolicy,
        environment: [String: String],
        explicitEnvOverrides: [String: String],
        responseFormat: ShellResponseFormat
    ) async -> ResponseItem {
        if sandboxPermissions.requiresEscalatedPermissions, approvalPolicy != .onRequest {
            return functionOutput(
                callID: callID,
                content: "approval policy is \(approvalPolicy); reject command — you cannot ask for escalated permissions if the approval policy is \(approvalPolicy)",
                success: false
            )
        }

        guard !command.isEmpty else {
            return functionOutput(callID: callID, content: "\(toolName) command is empty", success: false)
        }

        let commandCwd = resolveWorkdir(workdir, relativeTo: cwd)
        switch maybeParseApplyPatchVerified(command, cwd: commandCwd) {
        case let .body(action):
            let result = executeApplyPatch(
                patch: action.patch,
                cwd: URL(fileURLWithPath: action.cwd, isDirectory: true),
                approvalPolicy: approvalPolicy,
                sandboxPolicy: sandboxPolicy,
                environment: environment
            )
            let output = ExecToolCallOutput(
                exitCode: result.success ? 0 : 1,
                stdout: result.success ? result.content : "",
                stderr: result.success ? "" : result.content,
                aggregatedOutput: result.content,
                duration: 0
            )
            return functionOutput(
                callID: callID,
                content: formatShellResponse(output, truncationPolicy: truncationPolicy, format: responseFormat),
                success: result.success
            )
        case let .shellParseError(error):
            return functionOutput(
                callID: callID,
                content: "failed to parse apply_patch shell command: \(String(describing: error))",
                success: false
            )
        case let .correctnessError(error):
            return functionOutput(
                callID: callID,
                content: "invalid apply_patch command: \(error.description)",
                success: false
            )
        case .notApplyPatch:
            break
        }

        let command = sessionShell.map {
            ShellSnapshotCommandWrapper.maybeWrapShellLCWithSnapshot(
                command: command,
                sessionShell: $0,
                cwd: commandCwd,
                explicitEnvOverrides: explicitEnvOverrides,
                environment: environment
            )
        } ?? command

        let output = await Task.detached(priority: .userInitiated) {
            runCommandSync(
                command: command,
                cwd: commandCwd,
                sandboxPolicy: sandboxPermissions.requiresEscalatedPermissions ? .dangerFullAccess : sandboxPolicy,
                timeoutMS: timeoutMS,
                environment: environment
            )
        }.value

        return functionOutput(
            callID: callID,
            content: formatShellResponse(output, truncationPolicy: truncationPolicy, format: responseFormat),
            success: output.exitCode == 0 && !output.timedOut
        )
    }

    private static func executeUnifiedExecCommand(
        command: [String],
        sessionShell: Shell?,
        workdir: String?,
        timeoutMS: UInt64?,
        sandboxPermissions: SandboxPermissions,
        callID: String,
        cwd: URL,
        approvalPolicy: AskForApproval,
        sandboxPolicy: SandboxPolicy,
        truncationPolicy: TruncationPolicy,
        environment: [String: String],
        explicitEnvOverrides: [String: String]
    ) async -> ResponseItem {
        if sandboxPermissions.requiresEscalatedPermissions, approvalPolicy != .onRequest {
            return functionOutput(
                callID: callID,
                content: "approval policy is \(approvalPolicy); reject command — you cannot ask for escalated permissions if the approval policy is \(approvalPolicy)",
                success: false
            )
        }

        guard !command.isEmpty else {
            return functionOutput(callID: callID, content: "exec_command command is empty", success: false)
        }

        let commandCwd = resolveWorkdir(workdir, relativeTo: cwd)
        let command = sessionShell.map {
            ShellSnapshotCommandWrapper.maybeWrapShellLCWithSnapshot(
                command: command,
                sessionShell: $0,
                cwd: commandCwd,
                explicitEnvOverrides: explicitEnvOverrides,
                environment: environment
            )
        } ?? command
        do {
            let output = try await unifiedExecSessions.start(
                command: command,
                cwd: commandCwd,
                sandboxPolicy: sandboxPermissions.requiresEscalatedPermissions ? .dangerFullAccess : sandboxPolicy,
                yieldTimeMS: UnifiedExecTiming.clampInitialYieldTimeMS(timeoutMS ?? 10_000),
                truncationPolicy: truncationPolicy,
                environment: environment
            )
            return functionOutput(
                callID: callID,
                content: formatUnifiedExecResponse(output),
                success: output.exitCode.map { $0 == 0 } ?? true
            )
        } catch {
            return functionOutput(
                callID: callID,
                content: "exec_command failed: \(String(describing: error))",
                success: false
            )
        }
    }

    private static func completedOutputItems(from events: ResponseEventResults) -> [ResponseItem] {
        ResponseEventAggregator.aggregate(events, mode: .aggregatedOnly).compactMap { result in
            guard case let .success(.outputItemDone(item)) = result else {
                return nil
            }
            return item
        }
    }

    private static func toolCalls(from items: [ResponseItem]) -> [ResponseItem] {
        items.filter { item in
            switch item {
            case .functionCall, .customToolCall, .localShellCall:
                return true
            case let .toolSearchCall(_, callID, _, execution, _):
                return callID != nil && execution == "client"
            case .message,
                 .reasoning,
                 .functionCallOutput,
                 .customToolCallOutput,
                 .toolSearchOutput,
                 .webSearchCall,
                 .imageGenerationCall,
                 .ghostSnapshot,
                 .compaction,
                 .contextCompaction,
                 .knownPersisted,
                 .other:
                return false
            }
        }
    }

    private static func completedResponseNeedsFollowUp(_ events: ResponseEventResults) -> Bool {
        events.contains { result in
            guard case let .success(.completed(_, _, endTurn)) = result else {
                return false
            }
            return endTurn == false
        }
    }

    private static func containsFailure(_ events: ResponseEventResults) -> Bool {
        events.contains { result in
            if case .failure = result {
                return true
            }
            return false
        }
    }

    private static func hookPermissionMode(_ approvalPolicy: AskForApproval) -> String {
        approvalPolicy == .never ? "bypassPermissions" : "default"
    }

    private struct ToolHookPayload: Equatable, Sendable {
        var toolName: String
        var matcherAliases: [String]
        var toolUseID: String
        var toolInput: JSONValue
        var sandboxPermissions: SandboxPermissions = .useDefault
        var approvalDescription: String?
    }

    private struct PostToolHookPayload: Equatable, Sendable {
        var prePayload: ToolHookPayload
        var toolResponse: JSONValue
    }

    private static func runPreToolUseHooks(
        handlers: [ConfiguredHookHandler],
        hookPayload: ToolHookPayload,
        conversationID: ConversationId,
        turnID: String,
        cwd: URL,
        model: String,
        approvalPolicy: AskForApproval
    ) async -> HookPreToolUseOutcome {
        do {
            let request = try HookPreToolUseRequest(
                sessionID: ThreadId(uuid: conversationID.uuid),
                turnID: turnID,
                cwd: AbsolutePath(absolutePath: cwd.standardizedFileURL.path),
                model: model,
                permissionMode: hookPermissionMode(approvalPolicy),
                toolName: hookPayload.toolName,
                matcherAliases: hookPayload.matcherAliases,
                toolUseID: hookPayload.toolUseID,
                toolInput: hookPayload.toolInput
            )
            return await HookPreToolUse.run(handlers: handlers, shell: HookCommandShell(), request: request)
        } catch {
            return HookPreToolUseOutcome(
                hookEvents: [],
                shouldBlock: false,
                blockReason: nil,
                additionalContexts: []
            )
        }
    }

    private static func runPostToolUseHooks(
        handlers: [ConfiguredHookHandler],
        hookPayload: PostToolHookPayload,
        conversationID: ConversationId,
        turnID: String,
        cwd: URL,
        model: String,
        approvalPolicy: AskForApproval
    ) async -> HookPostToolUseOutcome {
        do {
            let request = try HookPostToolUseRequest(
                sessionID: ThreadId(uuid: conversationID.uuid),
                turnID: turnID,
                cwd: AbsolutePath(absolutePath: cwd.standardizedFileURL.path),
                model: model,
                permissionMode: hookPermissionMode(approvalPolicy),
                toolName: hookPayload.prePayload.toolName,
                matcherAliases: hookPayload.prePayload.matcherAliases,
                toolUseID: hookPayload.prePayload.toolUseID,
                toolInput: hookPayload.prePayload.toolInput,
                toolResponse: hookPayload.toolResponse
            )
            var outcome = await HookPostToolUse.run(handlers: handlers, shell: HookCommandShell(), request: request)
            let threadID = ThreadId(uuid: conversationID.uuid)
            outcome.additionalContexts = HookOutputSpiller().maybeSpillTexts(
                threadID: threadID,
                texts: outcome.additionalContexts
            )
            if let feedbackMessage = outcome.feedbackMessage {
                outcome.feedbackMessage = HookOutputSpiller().maybeSpillText(threadID: threadID, text: feedbackMessage)
            }
            return outcome
        } catch {
            return HookPostToolUseOutcome(
                hookEvents: [],
                shouldStop: false,
                stopReason: nil,
                additionalContexts: [],
                feedbackMessage: nil
            )
        }
    }

    private static func runPermissionRequestHooks(
        handlers: [ConfiguredHookHandler],
        hookPayload: ToolHookPayload,
        conversationID: ConversationId,
        turnID: String,
        cwd: URL,
        model: String,
        approvalPolicy: AskForApproval
    ) async -> HookPermissionRequestDecision? {
        do {
            let request = try HookPermissionRequestRequest(
                sessionID: ThreadId(uuid: conversationID.uuid),
                turnID: turnID,
                cwd: AbsolutePath(absolutePath: cwd.standardizedFileURL.path),
                model: model,
                permissionMode: hookPermissionMode(approvalPolicy),
                toolName: hookPayload.toolName,
                matcherAliases: hookPayload.matcherAliases,
                runIDSuffix: hookPayload.toolUseID,
                toolInput: permissionToolInput(from: hookPayload)
            )
            return await HookPermissionRequest.run(handlers: handlers, shell: HookCommandShell(), request: request).decision
        } catch {
            return nil
        }
    }

    private static func permissionToolInput(from hookPayload: ToolHookPayload) -> JSONValue {
        guard let approvalDescription = hookPayload.approvalDescription,
              case var .object(input) = hookPayload.toolInput
        else {
            return hookPayload.toolInput
        }
        input["description"] = .string(approvalDescription)
        return .object(input)
    }

    private static func hookAdditionalContextItems(_ contexts: [String]) -> [ResponseItem] {
        contexts.map { context in
            ResponseInputItem(userInputs: [.text(context)]).responseItem()
        }
    }

    private static func toolHookPayload(for item: ResponseItem) -> ToolHookPayload? {
        let decoder = JSONDecoder()
        switch item {
        case let .functionCall(_, name, _, arguments, callID):
            switch name {
            case "exec_command":
                guard let params = try? decoder.decode(ExecCommandToolCallParams.self, from: Data(arguments.utf8)) else {
                    return nil
                }
                return ToolHookPayload(
                    toolName: "Bash",
                    matcherAliases: [],
                    toolUseID: callID,
                    toolInput: .object(["command": .string(params.cmd)]),
                    sandboxPermissions: params.sandboxPermissions,
                    approvalDescription: params.justification
                )

            case "shell_command":
                guard let params = try? decoder.decode(ShellCommandToolCallParams.self, from: Data(arguments.utf8)) else {
                    return nil
                }
                return ToolHookPayload(
                    toolName: "Bash",
                    matcherAliases: [],
                    toolUseID: callID,
                    toolInput: .object(["command": .string(params.command)]),
                    sandboxPermissions: params.sandboxPermissions ?? .useDefault,
                    approvalDescription: params.justification
                )

            case "shell", "container.exec":
                guard let params = try? decoder.decode(ShellToolCallParams.self, from: Data(arguments.utf8)) else {
                    return nil
                }
                return ToolHookPayload(
                    toolName: "Bash",
                    matcherAliases: [],
                    toolUseID: callID,
                    toolInput: .object(["command": .string(params.command.joined(separator: " "))]),
                    sandboxPermissions: params.sandboxPermissions ?? .useDefault,
                    approvalDescription: params.justification
                )

            default:
                guard let toolInput = try? JSONDecoder().decode(JSONValue.self, from: Data(arguments.utf8)) else {
                    return ToolHookPayload(
                        toolName: name,
                        matcherAliases: [],
                        toolUseID: callID,
                        toolInput: .object([:])
                    )
                }
                return ToolHookPayload(toolName: name, matcherAliases: [], toolUseID: callID, toolInput: toolInput)
            }

        case let .customToolCall(_, _, callID, name, input):
            guard name == "apply_patch" else {
                return nil
            }
            return ToolHookPayload(
                toolName: "apply_patch",
                matcherAliases: ["Write", "Edit"],
                toolUseID: callID,
                toolInput: .object(["command": .string(input)])
            )

        case let .localShellCall(id, callID, _, action):
            guard case let .exec(params) = action else {
                return nil
            }
            return ToolHookPayload(
                toolName: "Bash",
                matcherAliases: [],
                toolUseID: callID ?? id ?? "local_shell",
                toolInput: .object(["command": .string(params.command.joined(separator: " "))])
            )

        default:
            return nil
        }
    }

    private static func postToolHookPayload(
        for item: ResponseItem,
        output: ResponseItem,
        prePayload: ToolHookPayload
    ) -> PostToolHookPayload? {
        switch output {
        case let .functionCallOutput(_, payload):
            return PostToolHookPayload(prePayload: prePayload, toolResponse: .string(payload.content))
        case let .customToolCallOutput(_, _, output):
            return PostToolHookPayload(prePayload: prePayload, toolResponse: .string(output.content))
        default:
            if case .toolSearchCall = item {
                return nil
            }
            return nil
        }
    }

    private static func toolOutputSucceeded(_ output: ResponseItem) -> Bool {
        switch output {
        case let .functionCallOutput(_, payload):
            return payload.success != false
        case .customToolCallOutput:
            return true
        default:
            return false
        }
    }

    private static func blockedToolOutput(
        for item: ResponseItem,
        hookPayload: ToolHookPayload,
        reason: String?
    ) -> ResponseItem {
        let message = blockedToolMessage(hookPayload: hookPayload, reason: reason)
        switch item {
        case let .functionCall(_, _, _, _, callID):
            return functionOutput(callID: callID, content: message, success: false)
        case let .customToolCall(_, _, callID, _, _):
            return .customToolCallOutput(callID: callID, output: message)
        case let .localShellCall(id, callID, _, _):
            return functionOutput(callID: callID ?? id ?? "local_shell", content: message, success: false)
        default:
            return functionOutput(callID: hookPayload.toolUseID, content: message, success: false)
        }
    }

    private static func deniedPermissionOutput(
        for item: ResponseItem,
        hookPayload: ToolHookPayload,
        message: String
    ) -> ResponseItem {
        switch item {
        case let .functionCall(_, _, _, _, callID):
            return functionOutput(callID: callID, content: message, success: false)
        case let .customToolCall(_, _, callID, _, _):
            return .customToolCallOutput(callID: callID, output: message)
        case let .localShellCall(id, callID, _, _):
            return functionOutput(callID: callID ?? id ?? "local_shell", content: message, success: false)
        default:
            return functionOutput(callID: hookPayload.toolUseID, content: message, success: false)
        }
    }

    private static func blockedToolMessage(hookPayload: ToolHookPayload, reason: String?) -> String {
        let reason = reason ?? "blocked by PreToolUse hook"
        if (hookPayload.toolName == "Bash" || hookPayload.toolName == "apply_patch"),
           case let .object(input) = hookPayload.toolInput,
           case let .string(command)? = input["command"]
        {
            return "Command blocked by PreToolUse hook: \(reason). Command: \(command)"
        }
        return "Tool call blocked by PreToolUse hook: \(reason). Tool: \(hookPayload.toolName)"
    }

    private static func replacingToolOutputIfNeeded(
        _ output: ResponseItem,
        with outcome: HookPostToolUseOutcome
    ) -> ResponseItem {
        let replacement = outcome.shouldStop
            ? (outcome.feedbackMessage ?? outcome.stopReason ?? "PostToolUse hook stopped execution")
            : outcome.feedbackMessage
        guard let replacement else {
            return output
        }
        switch output {
        case let .functionCallOutput(callID, payload):
            return .functionCallOutput(
                callID: callID,
                output: FunctionCallOutputPayload(content: replacement, success: payload.success)
            )
        case let .customToolCallOutput(callID, name, _):
            return .customToolCallOutput(callID: callID, name: name, output: replacement)
        default:
            return output
        }
    }

    private static func functionOutput(callID: String, content: String, success: Bool) -> ResponseItem {
        .functionCallOutput(
            callID: callID,
            output: FunctionCallOutputPayload(content: content, success: success)
        )
    }

    private static func executeCustomToolCall(
        name: String,
        input: String,
        callID: String,
        cwd: URL,
        approvalPolicy: AskForApproval,
        sandboxPolicy: SandboxPolicy,
        environment: [String: String]
    ) -> ResponseItem {
        guard name == "apply_patch" else {
            return .customToolCallOutput(callID: callID, output: "unsupported custom tool: \(name)")
        }

        let result = executeApplyPatch(
            patch: input,
            cwd: cwd,
            approvalPolicy: approvalPolicy,
            sandboxPolicy: sandboxPolicy,
            environment: environment
        )
        return .customToolCallOutput(callID: callID, output: result.content)
    }

    private static func executeApplyPatch(
        patch: String,
        cwd: URL,
        approvalPolicy: AskForApproval,
        sandboxPolicy: SandboxPolicy,
        environment: [String: String]
    ) -> (content: String, success: Bool) {
        let parsed: ApplyPatchArgs
        do {
            parsed = try ApplyPatch.parsePatch(patch)
        } catch {
            let result = ApplyPatch.apply(patch, cwd: cwd)
            return (result.stderr.isEmpty ? result.stdout : result.stderr, result.stderr.isEmpty)
        }

        guard let absoluteCwd = try? AbsolutePath(absolutePath: cwd.standardizedFileURL.path) else {
            return ("invalid sandbox cwd: \(cwd.path)", false)
        }

        switch PatchSafety.assessPatchSafety(
            hunks: parsed.hunks,
            approvalPolicy: approvalPolicy,
            sandboxPolicy: sandboxPolicy,
            cwd: absoluteCwd,
            environment: environment
        ) {
        case .autoApprove:
            let result = ApplyPatch.apply(patch, cwd: cwd)
            return (result.stderr.isEmpty ? result.stdout : result.stderr, result.stderr.isEmpty)
        case let .reject(reason):
            return ("apply_patch rejected: \(reason)", false)
        case .askUser:
            return ("apply_patch requires approval", false)
        }
    }

    private static func resolveWorkdir(_ workdir: String?, relativeTo cwd: URL) -> URL {
        guard let workdir, !workdir.isEmpty else {
            return cwd.standardizedFileURL
        }
        if workdir.hasPrefix("/") {
            return URL(fileURLWithPath: workdir, isDirectory: true).standardizedFileURL
        }
        return cwd.appendingPathComponent(workdir, isDirectory: true).standardizedFileURL
    }

    private static func runCommandSync(
        command: [String],
        cwd: URL,
        sandboxPolicy: SandboxPolicy,
        timeoutMS: UInt64?,
        environment: [String: String]
    ) -> ExecToolCallOutput {
        let start = Date()
        let launch: [String]
        var childEnvironment = ExecEnvironment.createEnv(policy: ShellEnvironmentPolicy(), environment: environment)

        if sandboxPolicy == .dangerFullAccess {
            launch = command
        } else {
            guard let absoluteCwd = try? AbsolutePath(absolutePath: cwd.standardizedFileURL.path) else {
                return ExecToolCallOutput(
                    exitCode: -1,
                    stdout: "",
                    stderr: "invalid sandbox cwd: \(cwd.path)",
                    aggregatedOutput: "invalid sandbox cwd: \(cwd.path)",
                    duration: 0
                )
            }
            launch = [SeatbeltSandbox.executablePath] + SeatbeltSandbox.commandArguments(
                command: command,
                sandboxPolicy: sandboxPolicy,
                sandboxPolicyCwd: absoluteCwd,
                environment: environment
            )
            childEnvironment["CODEX_SANDBOX"] = SeatbeltSandbox.sandboxEnvironmentValue
            if !sandboxPolicy.hasFullNetworkAccess {
                childEnvironment["CODEX_SANDBOX_NETWORK_DISABLED"] = "1"
            }
        }

        guard let executable = launch.first else {
            return ExecToolCallOutput(
                exitCode: -1,
                stdout: "",
                stderr: "command is empty",
                aggregatedOutput: "command is empty",
                duration: 0
            )
        }

        let process = Process()
        if executable.contains("/") {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = Array(launch.dropFirst())
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = launch
        }
        process.currentDirectoryURL = cwd
        process.environment = childEnvironment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdoutCapture = DataCapture()
        let stderrCapture = DataCapture()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                stdoutCapture.append(data)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                stderrCapture.append(data)
            }
        }

        var timedOut = false
        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            let message = "failed to launch command: \(String(describing: error))"
            return ExecToolCallOutput(
                exitCode: -1,
                stdout: "",
                stderr: message,
                aggregatedOutput: message,
                duration: Date().timeIntervalSince(start)
            )
        }

        let timeoutSeconds = timeoutMS.map { TimeInterval($0) / 1_000 }
        while process.isRunning {
            if let timeoutSeconds, Date().timeIntervalSince(start) >= timeoutSeconds {
                timedOut = true
                process.terminate()
                Thread.sleep(forTimeInterval: 0.2)
                if process.isRunning {
                    Darwin.kill(process.processIdentifier, SIGKILL)
                }
                break
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        process.waitUntilExit()

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        var stdoutData = stdoutCapture.snapshot()
        stdoutData.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
        var stderrData = stderrCapture.snapshot()
        stderrData.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())

        let stdout = String(decoding: stdoutData, as: UTF8.self)
        let stderr = String(decoding: stderrData, as: UTF8.self)
        let aggregatedOutput: String
        if stdout.isEmpty {
            aggregatedOutput = stderr
        } else if stderr.isEmpty {
            aggregatedOutput = stdout
        } else {
            aggregatedOutput = stdout + stderr
        }

        return ExecToolCallOutput(
            exitCode: Int(process.terminationStatus),
            stdout: stdout,
            stderr: stderr,
            aggregatedOutput: aggregatedOutput,
            duration: Date().timeIntervalSince(start),
            timedOut: timedOut
        )
    }

    private static func formatShellResponse(
        _ output: ExecToolCallOutput,
        truncationPolicy: TruncationPolicy,
        format: ShellResponseFormat
    ) -> String {
        switch format {
        case .structured:
            return formatStructuredShellResponse(output, truncationPolicy: truncationPolicy)
        case .freeform:
            return formatFreeformShellResponse(output, truncationPolicy: truncationPolicy)
        case .unifiedExec:
            return formatUnifiedExecResponse(output, truncationPolicy: truncationPolicy)
        }
    }

    private static func formatStructuredShellResponse(
        _ output: ExecToolCallOutput,
        truncationPolicy: TruncationPolicy
    ) -> String {
        struct Metadata: Encodable {
            let exitCode: Int
            let durationSeconds: Double

            enum CodingKeys: String, CodingKey {
                case exitCode = "exit_code"
                case durationSeconds = "duration_seconds"
            }
        }
        struct Payload: Encodable {
            let output: String
            let metadata: Metadata
        }

        let payload = Payload(
            output: ExecOutputFormatter.formatOutputString(output, truncationPolicy: truncationPolicy),
            metadata: Metadata(
                exitCode: output.exitCode,
                durationSeconds: roundedDurationSeconds(output.duration)
            )
        )
        guard let data = try? JSONEncoder().encode(payload),
              let text = String(data: data, encoding: .utf8)
        else {
            return ExecOutputFormatter.formatOutputString(output, truncationPolicy: truncationPolicy)
        }
        return text
    }

    private static func formatFreeformShellResponse(
        _ output: ExecToolCallOutput,
        truncationPolicy: TruncationPolicy
    ) -> String {
        let content = ExecOutputFormatter.buildContentWithTimeout(output)
        let formattedOutput = Truncation.truncateText(content, policy: truncationPolicy)
        let totalLines = lineCount(content)
        var sections = [
            "Exit code: \(output.exitCode)",
            "Wall time: \(roundedDurationSeconds(output.duration)) seconds"
        ]
        if totalLines != lineCount(formattedOutput) {
            sections.append("Total output lines: \(totalLines)")
        }
        sections.append("Output:")
        sections.append(formattedOutput)
        return sections.joined(separator: "\n")
    }

    private static func formatUnifiedExecResponse(
        _ output: ExecToolCallOutput,
        truncationPolicy: TruncationPolicy
    ) -> String {
        [
            "Wall time: \(String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), output.duration)) seconds",
            "Process exited with code \(output.exitCode)",
            "Output:",
            ExecOutputFormatter.formatOutputString(output, truncationPolicy: truncationPolicy)
        ].joined(separator: "\n")
    }

    private static func formatUnifiedExecResponse(_ output: UnifiedExecToolOutput) -> String {
        var sections: [String] = []
        if !output.chunkID.isEmpty {
            sections.append("Chunk ID: \(output.chunkID)")
        }
        sections.append("Wall time: \(String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), output.duration)) seconds")
        if let exitCode = output.exitCode {
            sections.append("Process exited with code \(exitCode)")
        }
        if let processID = output.processID {
            sections.append("Process running with session ID \(processID)")
        }
        if let originalTokenCount = output.originalTokenCount {
            sections.append("Original token count: \(originalTokenCount)")
        }
        sections.append("Output:")
        sections.append(output.output)
        return sections.joined(separator: "\n")
    }

    private static func roundedDurationSeconds(_ duration: TimeInterval) -> Double {
        (duration * 10).rounded() / 10
    }

    private static func lineCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isNewline).count
    }

    private static func reasoningText(from item: ResponseItem) -> String? {
        guard case let .reasoning(_, _, content, _) = item else {
            return nil
        }
        let text = content?.compactMap { item -> String? in
            if case let .reasoningText(text) = item {
                return text
            }
            return nil
        }.joined()
        return text?.isEmpty == false ? text : nil
    }

    private static func defaultWriteFile(path: String, contents: String) throws {
        try contents.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
    }

    private static func encodeJSONLine<T: Encodable>(_ value: T, using encoder: JSONEncoder) -> String {
        do {
            return String(decoding: try encoder.encode(value), as: UTF8.self)
        } catch {
            return #"{"type":"error","message":"failed to encode exec event"}"#
        }
    }
}

private final class DataCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.withLock {
            data.append(chunk)
        }
    }

    func snapshot() -> Data {
        lock.withLock {
            data
        }
    }

    func snapshot(from offset: Int) -> Data {
        lock.withLock {
            guard offset < data.count else {
                return Data()
            }
            return data.subdata(in: offset..<data.count)
        }
    }

    var count: Int {
        lock.withLock {
            data.count
        }
    }
}

private struct UnifiedExecToolOutput: Sendable {
    let chunkID: String
    let duration: TimeInterval
    let output: String
    let processID: String?
    let exitCode: Int?
    let originalTokenCount: Int?
}

private actor UnifiedExecSessionRegistry {
    private struct Session {
        let id: String
        let process: Process
        let stdinPipe: Pipe
        let stdoutPipe: Pipe
        let stderrPipe: Pipe
        let stdoutCapture: DataCapture
        let stderrCapture: DataCapture
        var stdoutOffset: Int
        var stderrOffset: Int
        let startedAt: Date
    }

    private var sessions: [String: Session] = [:]

    func start(
        command: [String],
        cwd: URL,
        sandboxPolicy: SandboxPolicy,
        yieldTimeMS: UInt64,
        truncationPolicy: TruncationPolicy,
        environment: [String: String]
    ) throws -> UnifiedExecToolOutput {
        let start = Date()
        let sessionID = allocateSessionID()
        let launch = try launchCommand(command: command, cwd: cwd, sandboxPolicy: sandboxPolicy, environment: environment)
        let process = Process()
        if launch.executable.contains("/") {
            process.executableURL = URL(fileURLWithPath: launch.executable)
            process.arguments = launch.arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [launch.executable] + launch.arguments
        }
        process.currentDirectoryURL = cwd
        process.environment = launch.environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdoutCapture = DataCapture()
        let stderrCapture = DataCapture()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        attachCapture(stdoutPipe, to: stdoutCapture)
        attachCapture(stderrPipe, to: stderrCapture)

        do {
            try process.run()
        } catch {
            detach(stdoutPipe, stderrPipe)
            throw UnifiedExecError.createSession(String(describing: error))
        }

        waitUntilDeadlineOrExit(process: process, startedAt: start, yieldTimeMS: yieldTimeMS)

        if process.isRunning {
            let stdout = stdoutCapture.snapshot()
            let stderr = stderrCapture.snapshot()
            sessions[sessionID] = Session(
                id: sessionID,
                process: process,
                stdinPipe: stdinPipe,
                stdoutPipe: stdoutPipe,
                stderrPipe: stderrPipe,
                stdoutCapture: stdoutCapture,
                stderrCapture: stderrCapture,
                stdoutOffset: stdout.count,
                stderrOffset: stderr.count,
                startedAt: start
            )
            return makeOutput(
                stdout: stdout,
                stderr: stderr,
                duration: Date().timeIntervalSince(start),
                processID: sessionID,
                exitCode: nil,
                truncationPolicy: truncationPolicy
            )
        }

        detach(stdoutPipe, stderrPipe)
        let stdout = readFinalData(pipe: stdoutPipe, capture: stdoutCapture)
        let stderr = readFinalData(pipe: stderrPipe, capture: stderrCapture)
        return makeOutput(
            stdout: stdout,
            stderr: stderr,
            duration: Date().timeIntervalSince(start),
            processID: nil,
            exitCode: Int(process.terminationStatus),
            truncationPolicy: truncationPolicy
        )
    }

    func writeStdin(
        sessionID: String,
        chars: String,
        yieldTimeMS: UInt64,
        maxEmptyYieldTimeMS: UInt64 = CodexConfigDefaults.backgroundTerminalMaxTimeoutMS,
        truncationPolicy: TruncationPolicy
    ) throws -> UnifiedExecToolOutput {
        guard var session = sessions[sessionID] else {
            throw UnifiedExecError.unknownSessionID(processID: sessionID)
        }

        let start = Date()
        if !chars.isEmpty {
            guard let data = chars.data(using: .utf8) else {
                throw UnifiedExecError.writeToStdin
            }
            do {
                try session.stdinPipe.fileHandleForWriting.write(contentsOf: data)
            } catch {
                throw UnifiedExecError.writeToStdin
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        let clampedYieldTimeMS = UnifiedExecTiming.clampWriteStdinYieldTimeMS(
            yieldTimeMS,
            inputIsEmpty: chars.isEmpty,
            maxEmptyYieldTimeMS: maxEmptyYieldTimeMS
        )
        waitUntilDeadlineOrExit(process: session.process, startedAt: start, yieldTimeMS: clampedYieldTimeMS)

        let stdout = session.stdoutCapture.snapshot(from: session.stdoutOffset)
        let stderr = session.stderrCapture.snapshot(from: session.stderrOffset)
        session.stdoutOffset = session.stdoutCapture.count
        session.stderrOffset = session.stderrCapture.count

        if session.process.isRunning {
            sessions[sessionID] = session
            return makeOutput(
                stdout: stdout,
                stderr: stderr,
                duration: Date().timeIntervalSince(start),
                processID: sessionID,
                exitCode: nil,
                truncationPolicy: truncationPolicy
            )
        }

        detach(session.stdoutPipe, session.stderrPipe)
        var finalStdout = stdout
        finalStdout.append(session.stdoutPipe.fileHandleForReading.readDataToEndOfFile())
        var finalStderr = stderr
        finalStderr.append(session.stderrPipe.fileHandleForReading.readDataToEndOfFile())
        sessions.removeValue(forKey: sessionID)
        return makeOutput(
            stdout: finalStdout,
            stderr: finalStderr,
            duration: Date().timeIntervalSince(start),
            processID: nil,
            exitCode: Int(session.process.terminationStatus),
            truncationPolicy: truncationPolicy
        )
    }

    private func allocateSessionID() -> String {
        var candidate: String
        repeat {
            candidate = String(Int.random(in: 1_000..<100_000))
        } while sessions[candidate] != nil
        return candidate
    }

    private func launchCommand(
        command: [String],
        cwd: URL,
        sandboxPolicy: SandboxPolicy,
        environment: [String: String]
    ) throws -> (executable: String, arguments: [String], environment: [String: String]) {
        var childEnvironment = ExecEnvironment.createEnv(policy: ShellEnvironmentPolicy(), environment: environment)
        let launch: [String]
        if sandboxPolicy == .dangerFullAccess {
            launch = command
        } else {
            let absoluteCwd = try AbsolutePath(absolutePath: cwd.standardizedFileURL.path)
            launch = [SeatbeltSandbox.executablePath] + SeatbeltSandbox.commandArguments(
                command: command,
                sandboxPolicy: sandboxPolicy,
                sandboxPolicyCwd: absoluteCwd,
                environment: environment
            )
            childEnvironment["CODEX_SANDBOX"] = SeatbeltSandbox.sandboxEnvironmentValue
            if !sandboxPolicy.hasFullNetworkAccess {
                childEnvironment["CODEX_SANDBOX_NETWORK_DISABLED"] = "1"
            }
        }

        guard let executable = launch.first else {
            throw UnifiedExecError.missingCommandLine
        }
        return (executable, Array(launch.dropFirst()), childEnvironment)
    }

    private func attachCapture(_ pipe: Pipe, to capture: DataCapture) {
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                capture.append(data)
            }
        }
    }

    private func detach(_ pipes: Pipe...) {
        for pipe in pipes {
            pipe.fileHandleForReading.readabilityHandler = nil
        }
    }

    private func waitUntilDeadlineOrExit(process: Process, startedAt: Date, yieldTimeMS: UInt64) {
        let deadline = startedAt.addingTimeInterval(TimeInterval(yieldTimeMS) / 1_000)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if !process.isRunning {
            process.waitUntilExit()
        }
    }

    private func readFinalData(pipe: Pipe, capture: DataCapture) -> Data {
        var data = capture.snapshot()
        data.append(pipe.fileHandleForReading.readDataToEndOfFile())
        return data
    }

    private func makeOutput(
        stdout: Data,
        stderr: Data,
        duration: TimeInterval,
        processID: String?,
        exitCode: Int?,
        truncationPolicy: TruncationPolicy
    ) -> UnifiedExecToolOutput {
        let stdoutText = String(decoding: stdout, as: UTF8.self)
        let stderrText = String(decoding: stderr, as: UTF8.self)
        let rawOutput = stdoutText.isEmpty ? stderrText : (stderrText.isEmpty ? stdoutText : stdoutText + stderrText)
        let output = Truncation.formattedTruncateText(rawOutput, policy: truncationPolicy)
        return UnifiedExecToolOutput(
            chunkID: randomChunkID(),
            duration: duration,
            output: output,
            processID: processID,
            exitCode: exitCode,
            originalTokenCount: rawOutput.split(whereSeparator: \.isWhitespace).count
        )
    }

    private func randomChunkID() -> String {
        String((0..<6).map { _ in "0123456789abcdef".randomElement()! })
    }
}

private struct ThreadStartedEvent: Encodable {
    let type = "thread.started"
    let threadID: String

    enum CodingKeys: String, CodingKey {
        case type
        case threadID = "thread_id"
    }
}

private struct TurnStartedEvent: Encodable {
    let type = "turn.started"
}

private struct CompletedItem: Encodable {
    let id: String
    let type: String
    let text: String?
    let query: String?

    init(id: String, type: String, text: String? = nil, query: String? = nil) {
        self.id = id
        self.type = type
        self.text = text
        self.query = query
    }
}

private struct ExecJSONItemCompletedEvent: Encodable {
    let type = "item.completed"
    let item: CompletedItem
}

private struct TurnCompletedEvent: Encodable {
    let type = "turn.completed"
    let usage: JSONUsage
}

private struct TurnFailedEvent: Encodable {
    let type = "turn.failed"
    let error: ThreadErrorJSONEvent
}

private struct ThreadErrorJSONEvent: Encodable {
    let message: String
}

private struct ErrorJSONEvent: Encodable {
    let type = "error"
    let message: String
}

private struct JSONUsage: Encodable, Equatable, Sendable {
    let inputTokens: Int64
    let cachedInputTokens: Int64
    let outputTokens: Int64

    init(_ usage: TokenUsage?) {
        inputTokens = usage?.inputTokens ?? 0
        cachedInputTokens = usage?.cachedInputTokens ?? 0
        outputTokens = usage?.outputTokens ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cachedInputTokens = "cached_input_tokens"
        case outputTokens = "output_tokens"
    }
}
