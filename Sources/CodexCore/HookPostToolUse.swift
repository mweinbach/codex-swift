import Foundation

public struct HookPostToolUseRequest: Equatable, Sendable {
    public var sessionID: ThreadId
    public var turnID: String
    public var cwd: AbsolutePath
    public var transcriptPath: String?
    public var model: String
    public var permissionMode: String
    public var toolName: String
    public var matcherAliases: [String]
    public var toolUseID: String
    public var toolInput: JSONValue
    public var toolResponse: JSONValue

    public init(
        sessionID: ThreadId,
        turnID: String,
        cwd: AbsolutePath,
        transcriptPath: String? = nil,
        model: String,
        permissionMode: String,
        toolName: String,
        matcherAliases: [String] = [],
        toolUseID: String,
        toolInput: JSONValue,
        toolResponse: JSONValue
    ) {
        self.sessionID = sessionID
        self.turnID = turnID
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.model = model
        self.permissionMode = permissionMode
        self.toolName = toolName
        self.matcherAliases = matcherAliases
        self.toolUseID = toolUseID
        self.toolInput = toolInput
        self.toolResponse = toolResponse
    }
}

public struct HookPostToolUseOutcome: Equatable, Sendable {
    public var hookEvents: [HookCompletedEvent]
    public var shouldStop: Bool
    public var stopReason: String?
    public var additionalContexts: [String]
    public var feedbackMessage: String?

    public init(
        hookEvents: [HookCompletedEvent],
        shouldStop: Bool,
        stopReason: String?,
        additionalContexts: [String],
        feedbackMessage: String?
    ) {
        self.hookEvents = hookEvents
        self.shouldStop = shouldStop
        self.stopReason = stopReason
        self.additionalContexts = additionalContexts
        self.feedbackMessage = feedbackMessage
    }
}

public struct HookPostToolUseHandlerData: Equatable, Sendable {
    public var shouldStop: Bool
    public var stopReason: String?
    public var additionalContextsForModel: [String]
    public var feedbackMessagesForModel: [String]

    public init(
        shouldStop: Bool = false,
        stopReason: String? = nil,
        additionalContextsForModel: [String] = [],
        feedbackMessagesForModel: [String] = []
    ) {
        self.shouldStop = shouldStop
        self.stopReason = stopReason
        self.additionalContextsForModel = additionalContextsForModel
        self.feedbackMessagesForModel = feedbackMessagesForModel
    }
}

public enum HookPostToolUse {
    public static func preview(
        handlers: [ConfiguredHookHandler],
        request: HookPostToolUseRequest,
        startedAt: Int64 = Int64(Date().timeIntervalSince1970)
    ) -> [HookRunSummary] {
        let matcherInputs = HookDispatcher.matcherInputs(
            toolName: request.toolName,
            matcherAliases: request.matcherAliases
        )
        return HookDispatcher
            .selectHandlers(handlers, eventName: .postToolUse, matcherInputs: matcherInputs)
            .map { HookToolUseRunID.add(HookDispatcher.runningSummary(handler: $0, startedAt: startedAt), toolUseID: request.toolUseID) }
    }

    public static func commandInputJSON(_ request: HookPostToolUseRequest) throws -> String {
        let data = try JSONEncoder().encode(PostToolUseCommandInput(request: request))
        return String(decoding: data, as: UTF8.self)
    }

    public static func run(
        handlers: [ConfiguredHookHandler],
        shell: HookCommandShell,
        request: HookPostToolUseRequest
    ) async -> HookPostToolUseOutcome {
        let matcherInputs = HookDispatcher.matcherInputs(
            toolName: request.toolName,
            matcherAliases: request.matcherAliases
        )
        let matched = HookDispatcher.selectHandlers(handlers, eventName: .postToolUse, matcherInputs: matcherInputs)
        guard !matched.isEmpty else {
            return HookPostToolUseOutcome(
                hookEvents: [],
                shouldStop: false,
                stopReason: nil,
                additionalContexts: [],
                feedbackMessage: nil
            )
        }

        let inputJSON: String
        do {
            inputJSON = try commandInputJSON(request)
        } catch {
            let hookEvents = HookPreToolUse.serializationFailureHookEventsForToolUse(
                handlers: matched,
                turnID: request.turnID,
                message: "failed to serialize post tool use hook input: \(error)",
                toolUseID: request.toolUseID
            )
            return HookPostToolUseOutcome(
                hookEvents: hookEvents,
                shouldStop: false,
                stopReason: nil,
                additionalContexts: [],
                feedbackMessage: nil
            )
        }

        let parsed = await HookDispatcher.executeHandlers(
            handlers: matched,
            shell: shell,
            inputJSON: inputJSON,
            cwd: URL(fileURLWithPath: request.cwd.path)
        ) { handler, result in
            parseCompleted(handler: handler, runResult: result, turnID: request.turnID)
        }

        let shouldStop = parsed.contains { $0.data.shouldStop }
        let stopReason = parsed.compactMap(\.data.stopReason).first
        let additionalContexts = parsed.flatMap(\.data.additionalContextsForModel)
        let feedbackMessage = joinTextChunks(parsed.flatMap(\.data.feedbackMessagesForModel))

        return HookPostToolUseOutcome(
            hookEvents: parsed.map { HookPreToolUse.hookCompletedForToolUse($0.completed, toolUseID: request.toolUseID) },
            shouldStop: shouldStop,
            stopReason: stopReason,
            additionalContexts: additionalContexts,
            feedbackMessage: feedbackMessage
        )
    }

    public static func parseCompleted(
        handler: ConfiguredHookHandler,
        runResult: HookCommandRunResult,
        turnID: String?
    ) -> ParsedHookHandler<HookPostToolUseHandlerData> {
        var entries: [HookOutputEntry] = []
        var status = HookRunStatus.completed
        var shouldStop = false
        var stopReason: String?
        var additionalContextsForModel: [String] = []
        var feedbackMessagesForModel: [String] = []

        if let error = runResult.error {
            status = .failed
            entries.append(HookOutputEntry(kind: .error, text: error))
        } else {
            switch runResult.exitCode {
            case 0:
                let trimmedStdout = runResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedStdout.isEmpty {
                    break
                } else if let parsed = HooksProtocol.parsePostToolUseOutput(runResult.stdout) {
                    if let systemMessage = parsed.universal.systemMessage {
                        entries.append(HookOutputEntry(kind: .warning, text: systemMessage))
                    }
                    if parsed.invalidReason == nil,
                       parsed.invalidBlockReason == nil,
                       let additionalContext = parsed.additionalContext {
                        entries.append(HookOutputEntry(kind: .context, text: additionalContext))
                        additionalContextsForModel.append(additionalContext)
                    }
                    if !parsed.universal.continueProcessing {
                        status = .stopped
                        shouldStop = true
                        stopReason = parsed.universal.stopReason
                        let stopText = parsed.universal.stopReason ?? "PostToolUse hook stopped execution"
                        entries.append(HookOutputEntry(kind: .stop, text: stopText))
                        feedbackMessagesForModel.append(trimmedNonEmpty(parsed.reason) ?? stopText)
                    } else if let invalidReason = parsed.invalidReason {
                        status = .failed
                        entries.append(HookOutputEntry(kind: .error, text: invalidReason))
                    } else if let invalidBlockReason = parsed.invalidBlockReason {
                        status = .failed
                        entries.append(HookOutputEntry(kind: .error, text: invalidBlockReason))
                    } else if parsed.shouldBlock {
                        status = .blocked
                        if let reason = parsed.reason {
                            entries.append(HookOutputEntry(kind: .feedback, text: reason))
                            feedbackMessagesForModel.append(reason)
                        }
                    }
                } else if HooksProtocol.looksLikeJSON(runResult.stdout) {
                    status = .failed
                    entries.append(HookOutputEntry(kind: .error, text: "hook returned invalid post-tool-use JSON output"))
                }
            case 2:
                if let reason = trimmedNonEmpty(runResult.stderr) {
                    entries.append(HookOutputEntry(kind: .feedback, text: reason))
                    feedbackMessagesForModel.append(reason)
                } else {
                    status = .failed
                    entries.append(HookOutputEntry(
                        kind: .error,
                        text: "PostToolUse hook exited with code 2 but did not write feedback to stderr"
                    ))
                }
            case let exitCode?:
                status = .failed
                entries.append(HookOutputEntry(kind: .error, text: "hook exited with code \(exitCode)"))
            case nil:
                status = .failed
                entries.append(HookOutputEntry(kind: .error, text: "hook exited without a status code"))
            }
        }

        return ParsedHookHandler(
            completed: HookCompletedEvent(
                turnID: turnID,
                run: HookDispatcher.completedSummary(
                    handler: handler,
                    runResult: runResult,
                    status: status,
                    entries: entries
                )
            ),
            data: HookPostToolUseHandlerData(
                shouldStop: shouldStop,
                stopReason: stopReason,
                additionalContextsForModel: additionalContextsForModel,
                feedbackMessagesForModel: feedbackMessagesForModel
            )
        )
    }

    private static func joinTextChunks(_ chunks: [String]) -> String? {
        chunks.isEmpty ? nil : chunks.joined(separator: "\n\n")
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct PostToolUseCommandInput: Encodable {
    let request: HookPostToolUseRequest

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(request.sessionID.description, forKey: .sessionID)
        try container.encode(request.turnID, forKey: .turnID)
        try container.encodeNilOrValue(request.transcriptPath, forKey: .transcriptPath)
        try container.encode(request.cwd.path, forKey: .cwd)
        try container.encode("PostToolUse", forKey: .hookEventName)
        try container.encode(request.model, forKey: .model)
        try container.encode(request.permissionMode, forKey: .permissionMode)
        try container.encode(request.toolName, forKey: .toolName)
        try container.encode(request.toolInput, forKey: .toolInput)
        try container.encode(request.toolResponse, forKey: .toolResponse)
        try container.encode(request.toolUseID, forKey: .toolUseID)
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case turnID = "turn_id"
        case transcriptPath = "transcript_path"
        case cwd
        case hookEventName = "hook_event_name"
        case model
        case permissionMode = "permission_mode"
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case toolResponse = "tool_response"
        case toolUseID = "tool_use_id"
    }
}

public enum HookToolUseRunID {
    public static func add(_ run: HookRunSummary, toolUseID: String) -> HookRunSummary {
        HookRunSummary(
            id: "\(run.id):\(toolUseID)",
            eventName: run.eventName,
            handlerType: run.handlerType,
            executionMode: run.executionMode,
            scope: run.scope,
            sourcePath: run.sourcePath,
            source: run.source,
            displayOrder: run.displayOrder,
            status: run.status,
            statusMessage: run.statusMessage,
            startedAt: run.startedAt,
            completedAt: run.completedAt,
            durationMs: run.durationMs,
            entries: run.entries
        )
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
