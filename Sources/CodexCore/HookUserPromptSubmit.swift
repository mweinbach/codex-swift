import Foundation

public struct HookUserPromptSubmitRequest: Equatable, Sendable {
    public var sessionID: ThreadId
    public var turnID: String
    public var cwd: AbsolutePath
    public var transcriptPath: String?
    public var model: String
    public var permissionMode: String
    public var prompt: String

    public init(
        sessionID: ThreadId,
        turnID: String,
        cwd: AbsolutePath,
        transcriptPath: String? = nil,
        model: String,
        permissionMode: String,
        prompt: String
    ) {
        self.sessionID = sessionID
        self.turnID = turnID
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.model = model
        self.permissionMode = permissionMode
        self.prompt = prompt
    }
}

public struct HookUserPromptSubmitOutcome: Equatable, Sendable {
    public var hookEvents: [HookCompletedEvent]
    public var shouldStop: Bool
    public var stopReason: String?
    public var additionalContexts: [String]

    public init(
        hookEvents: [HookCompletedEvent],
        shouldStop: Bool,
        stopReason: String?,
        additionalContexts: [String]
    ) {
        self.hookEvents = hookEvents
        self.shouldStop = shouldStop
        self.stopReason = stopReason
        self.additionalContexts = additionalContexts
    }
}

public struct HookUserPromptSubmitHandlerData: Equatable, Sendable {
    public var shouldStop: Bool
    public var stopReason: String?
    public var additionalContextsForModel: [String]

    public init(
        shouldStop: Bool = false,
        stopReason: String? = nil,
        additionalContextsForModel: [String] = []
    ) {
        self.shouldStop = shouldStop
        self.stopReason = stopReason
        self.additionalContextsForModel = additionalContextsForModel
    }
}

public enum HookUserPromptSubmit {
    public static func preview(
        handlers: [ConfiguredHookHandler],
        startedAt: Int64 = Int64(Date().timeIntervalSince1970)
    ) -> [HookRunSummary] {
        HookDispatcher
            .selectHandlers(handlers, eventName: .userPromptSubmit, matcherInput: nil)
            .map { HookDispatcher.runningSummary(handler: $0, startedAt: startedAt) }
    }

    public static func commandInputJSON(_ request: HookUserPromptSubmitRequest) throws -> String {
        let data = try JSONEncoder().encode(UserPromptSubmitCommandInput(request: request))
        return String(decoding: data, as: UTF8.self)
    }

    public static func run(
        handlers: [ConfiguredHookHandler],
        shell: HookCommandShell,
        request: HookUserPromptSubmitRequest
    ) async -> HookUserPromptSubmitOutcome {
        let matched = HookDispatcher.selectHandlers(handlers, eventName: .userPromptSubmit, matcherInput: nil)
        guard !matched.isEmpty else {
            return HookUserPromptSubmitOutcome(
                hookEvents: [],
                shouldStop: false,
                stopReason: nil,
                additionalContexts: []
            )
        }

        let inputJSON: String
        do {
            inputJSON = try commandInputJSON(request)
        } catch {
            return serializationFailureOutcome(
                hookEvents: serializationFailureHookEvents(
                    handlers: matched,
                    turnID: request.turnID,
                    message: "failed to serialize user prompt submit hook input: \(error)"
                )
            )
        }

        var parsed: [ParsedHookHandler<HookUserPromptSubmitHandlerData>] = []
        for handler in matched {
            let result = await HookCommandRunner.runCommand(
                shell: shell,
                handler: handler,
                inputJSON: inputJSON,
                cwd: URL(fileURLWithPath: request.cwd.path)
            )
            parsed.append(parseCompleted(handler: handler, runResult: result, turnID: request.turnID))
        }

        return HookUserPromptSubmitOutcome(
            hookEvents: parsed.map(\.completed),
            shouldStop: parsed.contains { $0.data.shouldStop },
            stopReason: parsed.compactMap(\.data.stopReason).first,
            additionalContexts: parsed.flatMap(\.data.additionalContextsForModel)
        )
    }

    public static func parseCompleted(
        handler: ConfiguredHookHandler,
        runResult: HookCommandRunResult,
        turnID: String?
    ) -> ParsedHookHandler<HookUserPromptSubmitHandlerData> {
        var entries: [HookOutputEntry] = []
        var status = HookRunStatus.completed
        var shouldStop = false
        var stopReason: String?
        var additionalContextsForModel: [String] = []

        if let error = runResult.error {
            status = .failed
            entries.append(HookOutputEntry(kind: .error, text: error))
        } else {
            switch runResult.exitCode {
            case 0:
                let trimmedStdout = runResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedStdout.isEmpty {
                    break
                } else if let parsed = HooksProtocol.parseUserPromptSubmitOutput(runResult.stdout) {
                    if let systemMessage = parsed.universal.systemMessage {
                        entries.append(HookOutputEntry(kind: .warning, text: systemMessage))
                    }
                    if parsed.invalidBlockReason == nil,
                       let additionalContext = parsed.additionalContext {
                        appendAdditionalContext(
                            additionalContext,
                            entries: &entries,
                            contexts: &additionalContextsForModel
                        )
                    }
                    if !parsed.universal.continueProcessing {
                        status = .stopped
                        shouldStop = true
                        stopReason = parsed.universal.stopReason
                        if let stopReasonText = parsed.universal.stopReason {
                            entries.append(HookOutputEntry(kind: .stop, text: stopReasonText))
                        }
                    } else if let invalidBlockReason = parsed.invalidBlockReason {
                        status = .failed
                        entries.append(HookOutputEntry(kind: .error, text: invalidBlockReason))
                    } else if parsed.shouldBlock {
                        status = .blocked
                        shouldStop = true
                        stopReason = parsed.reason
                        if let reason = parsed.reason {
                            entries.append(HookOutputEntry(kind: .feedback, text: reason))
                        }
                    }
                } else if HooksProtocol.looksLikeJSON(runResult.stdout) {
                    status = .failed
                    entries.append(HookOutputEntry(kind: .error, text: "hook returned invalid user prompt submit JSON output"))
                } else {
                    appendAdditionalContext(
                        trimmedStdout,
                        entries: &entries,
                        contexts: &additionalContextsForModel
                    )
                }
            case 2:
                if let reason = trimmedNonEmpty(runResult.stderr) {
                    status = .blocked
                    shouldStop = true
                    stopReason = reason
                    entries.append(HookOutputEntry(kind: .feedback, text: reason))
                } else {
                    status = .failed
                    entries.append(HookOutputEntry(
                        kind: .error,
                        text: "UserPromptSubmit hook exited with code 2 but did not write a blocking reason to stderr"
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
            data: HookUserPromptSubmitHandlerData(
                shouldStop: shouldStop,
                stopReason: stopReason,
                additionalContextsForModel: additionalContextsForModel
            )
        )
    }

    private static func serializationFailureOutcome(hookEvents: [HookCompletedEvent]) -> HookUserPromptSubmitOutcome {
        HookUserPromptSubmitOutcome(
            hookEvents: hookEvents,
            shouldStop: false,
            stopReason: nil,
            additionalContexts: []
        )
    }

    private static func serializationFailureHookEvents(
        handlers: [ConfiguredHookHandler],
        turnID: String?,
        message: String
    ) -> [HookCompletedEvent] {
        handlers.map { handler in
            HookCompletedEvent(
                turnID: turnID,
                run: HookDispatcher.completedSummary(
                    handler: handler,
                    runResult: HookCommandRunResult(startedAt: 0, completedAt: 0, durationMs: 0),
                    status: .failed,
                    entries: [HookOutputEntry(kind: .error, text: message)]
                )
            )
        }
    }

    private static func appendAdditionalContext(
        _ additionalContext: String,
        entries: inout [HookOutputEntry],
        contexts: inout [String]
    ) {
        entries.append(HookOutputEntry(kind: .context, text: additionalContext))
        contexts.append(additionalContext)
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct UserPromptSubmitCommandInput: Encodable {
    let request: HookUserPromptSubmitRequest

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(request.sessionID.description, forKey: .sessionID)
        try container.encode(request.turnID, forKey: .turnID)
        try container.encodeNilOrValue(request.transcriptPath, forKey: .transcriptPath)
        try container.encode(request.cwd.path, forKey: .cwd)
        try container.encode("UserPromptSubmit", forKey: .hookEventName)
        try container.encode(request.model, forKey: .model)
        try container.encode(request.permissionMode, forKey: .permissionMode)
        try container.encode(request.prompt, forKey: .prompt)
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case turnID = "turn_id"
        case transcriptPath = "transcript_path"
        case cwd
        case hookEventName = "hook_event_name"
        case model
        case permissionMode = "permission_mode"
        case prompt
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
