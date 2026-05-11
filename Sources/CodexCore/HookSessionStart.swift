import Foundation

public enum HookSessionStartSource: String, Equatable, Sendable {
    case startup
    case resume
    case clear
}

public struct HookSessionStartRequest: Equatable, Sendable {
    public var sessionID: ThreadId
    public var cwd: AbsolutePath
    public var transcriptPath: String?
    public var model: String
    public var permissionMode: String
    public var source: HookSessionStartSource

    public init(
        sessionID: ThreadId,
        cwd: AbsolutePath,
        transcriptPath: String? = nil,
        model: String,
        permissionMode: String,
        source: HookSessionStartSource
    ) {
        self.sessionID = sessionID
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.model = model
        self.permissionMode = permissionMode
        self.source = source
    }
}

public struct HookSessionStartOutcome: Equatable, Sendable {
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

public struct HookSessionStartHandlerData: Equatable, Sendable {
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

public enum HookSessionStart {
    public static func preview(
        handlers: [ConfiguredHookHandler],
        request: HookSessionStartRequest,
        startedAt: Int64 = Int64(Date().timeIntervalSince1970)
    ) -> [HookRunSummary] {
        HookDispatcher
            .selectHandlers(handlers, eventName: .sessionStart, matcherInput: request.source.rawValue)
            .map { HookDispatcher.runningSummary(handler: $0, startedAt: startedAt) }
    }

    public static func commandInputJSON(_ request: HookSessionStartRequest) throws -> String {
        let data = try JSONEncoder().encode(SessionStartCommandInput(request: request))
        return String(decoding: data, as: UTF8.self)
    }

    public static func run(
        handlers: [ConfiguredHookHandler],
        shell: HookCommandShell,
        request: HookSessionStartRequest,
        turnID: String?
    ) async -> HookSessionStartOutcome {
        let matched = HookDispatcher.selectHandlers(
            handlers,
            eventName: .sessionStart,
            matcherInput: request.source.rawValue
        )
        guard !matched.isEmpty else {
            return HookSessionStartOutcome(
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
                    turnID: turnID,
                    message: "failed to serialize session start hook input: \(error)"
                )
            )
        }

        let parsed = await HookDispatcher.executeHandlers(
            handlers: matched,
            shell: shell,
            inputJSON: inputJSON,
            cwd: URL(fileURLWithPath: request.cwd.path)
        ) { handler, result in
            parseCompleted(handler: handler, runResult: result, turnID: turnID)
        }

        return HookSessionStartOutcome(
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
    ) -> ParsedHookHandler<HookSessionStartHandlerData> {
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
                } else if let parsed = HooksProtocol.parseSessionStartOutput(runResult.stdout) {
                    if let systemMessage = parsed.universal.systemMessage {
                        entries.append(HookOutputEntry(kind: .warning, text: systemMessage))
                    }
                    if let additionalContext = parsed.additionalContext {
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
                    }
                } else if HooksProtocol.looksLikeJSON(runResult.stdout) {
                    status = .failed
                    entries.append(HookOutputEntry(kind: .error, text: "hook returned invalid session start JSON output"))
                } else {
                    appendAdditionalContext(
                        trimmedStdout,
                        entries: &entries,
                        contexts: &additionalContextsForModel
                    )
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
            data: HookSessionStartHandlerData(
                shouldStop: shouldStop,
                stopReason: stopReason,
                additionalContextsForModel: additionalContextsForModel
            )
        )
    }

    private static func serializationFailureOutcome(hookEvents: [HookCompletedEvent]) -> HookSessionStartOutcome {
        HookSessionStartOutcome(
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
}

private struct SessionStartCommandInput: Encodable {
    let request: HookSessionStartRequest

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(request.sessionID.description, forKey: .sessionID)
        try container.encodeNilOrValue(request.transcriptPath, forKey: .transcriptPath)
        try container.encode(request.cwd.path, forKey: .cwd)
        try container.encode("SessionStart", forKey: .hookEventName)
        try container.encode(request.model, forKey: .model)
        try container.encode(request.permissionMode, forKey: .permissionMode)
        try container.encode(request.source.rawValue, forKey: .source)
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case transcriptPath = "transcript_path"
        case cwd
        case hookEventName = "hook_event_name"
        case model
        case permissionMode = "permission_mode"
        case source
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
