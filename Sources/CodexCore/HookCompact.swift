import Foundation

public struct HookPreCompactRequest: Equatable, Sendable {
    public var sessionID: ThreadId
    public var turnID: String
    public var cwd: AbsolutePath
    public var transcriptPath: String?
    public var model: String
    public var trigger: String

    public init(
        sessionID: ThreadId,
        turnID: String,
        cwd: AbsolutePath,
        transcriptPath: String? = nil,
        model: String,
        trigger: String
    ) {
        self.sessionID = sessionID
        self.turnID = turnID
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.model = model
        self.trigger = trigger
    }
}

public struct HookPostCompactRequest: Equatable, Sendable {
    public var sessionID: ThreadId
    public var turnID: String
    public var cwd: AbsolutePath
    public var transcriptPath: String?
    public var model: String
    public var trigger: String

    public init(
        sessionID: ThreadId,
        turnID: String,
        cwd: AbsolutePath,
        transcriptPath: String? = nil,
        model: String,
        trigger: String
    ) {
        self.sessionID = sessionID
        self.turnID = turnID
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.model = model
        self.trigger = trigger
    }
}

public struct HookCompactOutcome: Equatable, Sendable {
    public var hookEvents: [HookCompletedEvent]
    public var shouldStop: Bool
    public var stopReason: String?

    public init(hookEvents: [HookCompletedEvent], shouldStop: Bool, stopReason: String?) {
        self.hookEvents = hookEvents
        self.shouldStop = shouldStop
        self.stopReason = stopReason
    }
}

public struct HookCompactHandlerData: Equatable, Sendable {
    public var shouldStop: Bool
    public var stopReason: String?

    public init(shouldStop: Bool = false, stopReason: String? = nil) {
        self.shouldStop = shouldStop
        self.stopReason = stopReason
    }
}

public enum HookPreCompact {
    public static func preview(
        handlers: [ConfiguredHookHandler],
        request: HookPreCompactRequest,
        startedAt: Int64 = Int64(Date().timeIntervalSince1970)
    ) -> [HookRunSummary] {
        HookDispatcher
            .selectHandlers(handlers, eventName: .preCompact, matcherInput: request.trigger)
            .map { HookDispatcher.runningSummary(handler: $0, startedAt: startedAt) }
    }

    public static func commandInputJSON(_ request: HookPreCompactRequest) throws -> String {
        let data = try JSONEncoder().encode(CompactCommandInput(
            sessionID: request.sessionID.description,
            turnID: request.turnID,
            transcriptPath: request.transcriptPath,
            cwd: request.cwd.path,
            hookEventName: "PreCompact",
            model: request.model,
            trigger: request.trigger
        ))
        return String(decoding: data, as: UTF8.self)
    }

    public static func run(
        handlers: [ConfiguredHookHandler],
        shell: HookCommandShell,
        request: HookPreCompactRequest
    ) async -> HookCompactOutcome {
        await runCompactHooks(
            handlers: handlers,
            shell: shell,
            eventName: .preCompact,
            eventLabel: "PreCompact",
            matcherInput: request.trigger,
            turnID: request.turnID,
            cwd: request.cwd,
            inputJSON: { try commandInputJSON(request) },
            serializationFailureMessage: { "failed to serialize pre compact hook input: \($0)" },
            parseOutput: HooksProtocol.parsePreCompactOutput
        )
    }

    public static func parseCompleted(
        handler: ConfiguredHookHandler,
        runResult: HookCommandRunResult,
        turnID: String?
    ) -> ParsedHookHandler<HookCompactHandlerData> {
        parseCompactCompleted(
            handler: handler,
            runResult: runResult,
            turnID: turnID,
            eventLabel: "PreCompact",
            parseOutput: HooksProtocol.parsePreCompactOutput
        )
    }
}

public enum HookPostCompact {
    public static func preview(
        handlers: [ConfiguredHookHandler],
        request: HookPostCompactRequest,
        startedAt: Int64 = Int64(Date().timeIntervalSince1970)
    ) -> [HookRunSummary] {
        HookDispatcher
            .selectHandlers(handlers, eventName: .postCompact, matcherInput: request.trigger)
            .map { HookDispatcher.runningSummary(handler: $0, startedAt: startedAt) }
    }

    public static func commandInputJSON(_ request: HookPostCompactRequest) throws -> String {
        let data = try JSONEncoder().encode(CompactCommandInput(
            sessionID: request.sessionID.description,
            turnID: request.turnID,
            transcriptPath: request.transcriptPath,
            cwd: request.cwd.path,
            hookEventName: "PostCompact",
            model: request.model,
            trigger: request.trigger
        ))
        return String(decoding: data, as: UTF8.self)
    }

    public static func run(
        handlers: [ConfiguredHookHandler],
        shell: HookCommandShell,
        request: HookPostCompactRequest
    ) async -> HookCompactOutcome {
        await runCompactHooks(
            handlers: handlers,
            shell: shell,
            eventName: .postCompact,
            eventLabel: "PostCompact",
            matcherInput: request.trigger,
            turnID: request.turnID,
            cwd: request.cwd,
            inputJSON: { try commandInputJSON(request) },
            serializationFailureMessage: { "failed to serialize post compact hook input: \($0)" },
            parseOutput: HooksProtocol.parsePostCompactOutput
        )
    }

    public static func parseCompleted(
        handler: ConfiguredHookHandler,
        runResult: HookCommandRunResult,
        turnID: String?
    ) -> ParsedHookHandler<HookCompactHandlerData> {
        parseCompactCompleted(
            handler: handler,
            runResult: runResult,
            turnID: turnID,
            eventLabel: "PostCompact",
            parseOutput: HooksProtocol.parsePostCompactOutput
        )
    }
}

private func runCompactHooks(
    handlers: [ConfiguredHookHandler],
    shell: HookCommandShell,
    eventName: HookEventName,
    eventLabel: String,
    matcherInput: String,
    turnID: String,
    cwd: AbsolutePath,
    inputJSON: () throws -> String,
    serializationFailureMessage: (Error) -> String,
    parseOutput: @escaping @Sendable (String) -> HookStatelessOutput?
) async -> HookCompactOutcome {
    let matched = HookDispatcher.selectHandlers(handlers, eventName: eventName, matcherInput: matcherInput)
    guard !matched.isEmpty else {
        return HookCompactOutcome(hookEvents: [], shouldStop: false, stopReason: nil)
    }

    let commandInput: String
    do {
        commandInput = try inputJSON()
    } catch {
        let hookEvents = matched.map { handler in
            HookCompletedEvent(
                turnID: turnID,
                run: HookDispatcher.completedSummary(
                    handler: handler,
                    runResult: HookCommandRunResult(startedAt: 0, completedAt: 0, durationMs: 0),
                    status: .failed,
                    entries: [HookOutputEntry(kind: .error, text: serializationFailureMessage(error))]
                )
            )
        }
        return HookCompactOutcome(hookEvents: hookEvents, shouldStop: false, stopReason: nil)
    }

    let parsed = await HookDispatcher.executeHandlers(
        handlers: matched,
        shell: shell,
        inputJSON: commandInput,
        cwd: URL(fileURLWithPath: cwd.path)
    ) { handler, result in
        parseCompactCompleted(
            handler: handler,
            runResult: result,
            turnID: turnID,
            eventLabel: eventLabel,
            parseOutput: parseOutput
        )
    }

    return HookCompactOutcome(
        hookEvents: parsed.map(\.completed),
        shouldStop: parsed.contains { $0.data.shouldStop },
        stopReason: parsed.compactMap(\.data.stopReason).first
    )
}

private func parseCompactCompleted(
    handler: ConfiguredHookHandler,
    runResult: HookCommandRunResult,
    turnID: String?,
    eventLabel: String,
    parseOutput: (String) -> HookStatelessOutput?
) -> ParsedHookHandler<HookCompactHandlerData> {
    var entries: [HookOutputEntry] = []
    var status = HookRunStatus.completed
    var shouldStop = false
    var stopReason: String?

    if let error = runResult.error {
        status = .failed
        entries.append(HookOutputEntry(kind: .error, text: error))
    } else {
        switch runResult.exitCode {
        case 0:
            let trimmedStdout = runResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedStdout.isEmpty {
                break
            } else if let parsed = parseOutput(runResult.stdout) {
                if let systemMessage = parsed.universal.systemMessage {
                    entries.append(HookOutputEntry(kind: .warning, text: systemMessage))
                }
                if !parsed.universal.continueProcessing {
                    status = .stopped
                    shouldStop = true
                    stopReason = parsed.universal.stopReason
                    entries.append(HookOutputEntry(
                        kind: .stop,
                        text: parsed.universal.stopReason ?? "\(eventLabel) hook stopped execution"
                    ))
                } else if let invalidReason = parsed.invalidReason {
                    status = .failed
                    entries.append(HookOutputEntry(kind: .error, text: invalidReason))
                }
            } else if HooksProtocol.looksLikeJSON(runResult.stdout) {
                status = .failed
                entries.append(HookOutputEntry(
                    kind: .error,
                    text: "hook returned invalid \(eventLabel) hook JSON output"
                ))
            }
        case let exitCode?:
            status = .failed
            entries.append(HookOutputEntry(
                kind: .error,
                text: trimmedNonEmpty(runResult.stderr) ?? "hook exited with code \(exitCode)"
            ))
        case nil:
            status = .failed
            entries.append(HookOutputEntry(kind: .error, text: "hook process terminated without an exit code"))
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
        data: HookCompactHandlerData(shouldStop: shouldStop, stopReason: stopReason)
    )
}

private struct CompactCommandInput: Encodable {
    var sessionID: String
    var turnID: String
    var transcriptPath: String?
    var cwd: String
    var hookEventName: String
    var model: String
    var trigger: String

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case turnID = "turn_id"
        case transcriptPath = "transcript_path"
        case cwd
        case hookEventName = "hook_event_name"
        case model
        case trigger
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(turnID, forKey: .turnID)
        if let transcriptPath {
            try container.encode(transcriptPath, forKey: .transcriptPath)
        } else {
            try container.encodeNil(forKey: .transcriptPath)
        }
        try container.encode(cwd, forKey: .cwd)
        try container.encode(hookEventName, forKey: .hookEventName)
        try container.encode(model, forKey: .model)
        try container.encode(trigger, forKey: .trigger)
    }
}

private func trimmedNonEmpty(_ text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
