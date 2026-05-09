import Foundation

public struct HookStopRequest: Equatable, Sendable {
    public var sessionID: ThreadId
    public var turnID: String
    public var cwd: AbsolutePath
    public var transcriptPath: String?
    public var model: String
    public var permissionMode: String
    public var stopHookActive: Bool
    public var lastAssistantMessage: String?

    public init(
        sessionID: ThreadId,
        turnID: String,
        cwd: AbsolutePath,
        transcriptPath: String? = nil,
        model: String,
        permissionMode: String,
        stopHookActive: Bool,
        lastAssistantMessage: String? = nil
    ) {
        self.sessionID = sessionID
        self.turnID = turnID
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.model = model
        self.permissionMode = permissionMode
        self.stopHookActive = stopHookActive
        self.lastAssistantMessage = lastAssistantMessage
    }
}

public struct HookStopOutcome: Equatable, Sendable {
    public var hookEvents: [HookCompletedEvent]
    public var shouldStop: Bool
    public var stopReason: String?
    public var shouldBlock: Bool
    public var blockReason: String?
    public var continuationFragments: [HookPromptFragment]

    public init(
        hookEvents: [HookCompletedEvent],
        shouldStop: Bool,
        stopReason: String?,
        shouldBlock: Bool,
        blockReason: String?,
        continuationFragments: [HookPromptFragment]
    ) {
        self.hookEvents = hookEvents
        self.shouldStop = shouldStop
        self.stopReason = stopReason
        self.shouldBlock = shouldBlock
        self.blockReason = blockReason
        self.continuationFragments = continuationFragments
    }
}

public struct HookStopHandlerData: Equatable, Sendable {
    public var shouldStop: Bool
    public var stopReason: String?
    public var shouldBlock: Bool
    public var blockReason: String?
    public var continuationFragments: [HookPromptFragment]

    public init(
        shouldStop: Bool = false,
        stopReason: String? = nil,
        shouldBlock: Bool = false,
        blockReason: String? = nil,
        continuationFragments: [HookPromptFragment] = []
    ) {
        self.shouldStop = shouldStop
        self.stopReason = stopReason
        self.shouldBlock = shouldBlock
        self.blockReason = blockReason
        self.continuationFragments = continuationFragments
    }
}

public enum HookStop {
    public static func preview(
        handlers: [ConfiguredHookHandler],
        startedAt: Int64 = Int64(Date().timeIntervalSince1970)
    ) -> [HookRunSummary] {
        HookDispatcher
            .selectHandlers(handlers, eventName: .stop, matcherInput: nil)
            .map { HookDispatcher.runningSummary(handler: $0, startedAt: startedAt) }
    }

    public static func commandInputJSON(_ request: HookStopRequest) throws -> String {
        let data = try JSONEncoder().encode(StopCommandInput(request: request))
        return String(decoding: data, as: UTF8.self)
    }

    public static func run(
        handlers: [ConfiguredHookHandler],
        shell: HookCommandShell,
        request: HookStopRequest
    ) async -> HookStopOutcome {
        let matched = HookDispatcher.selectHandlers(handlers, eventName: .stop, matcherInput: nil)
        guard !matched.isEmpty else {
            return HookStopOutcome(
                hookEvents: [],
                shouldStop: false,
                stopReason: nil,
                shouldBlock: false,
                blockReason: nil,
                continuationFragments: []
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
                    message: "failed to serialize stop hook input: \(error)"
                )
            )
        }

        var parsed: [ParsedHookHandler<HookStopHandlerData>] = []
        for handler in matched {
            let result = await HookCommandRunner.runCommand(
                shell: shell,
                handler: handler,
                inputJSON: inputJSON,
                cwd: URL(fileURLWithPath: request.cwd.path)
            )
            parsed.append(parseCompleted(handler: handler, runResult: result, turnID: request.turnID))
        }

        let aggregate = aggregateResults(parsed.map(\.data))
        return HookStopOutcome(
            hookEvents: parsed.map(\.completed),
            shouldStop: aggregate.shouldStop,
            stopReason: aggregate.stopReason,
            shouldBlock: aggregate.shouldBlock,
            blockReason: aggregate.blockReason,
            continuationFragments: aggregate.continuationFragments
        )
    }

    public static func parseCompleted(
        handler: ConfiguredHookHandler,
        runResult: HookCommandRunResult,
        turnID: String?
    ) -> ParsedHookHandler<HookStopHandlerData> {
        var entries: [HookOutputEntry] = []
        var status = HookRunStatus.completed
        var shouldStop = false
        var stopReason: String?
        var shouldBlock = false
        var blockReason: String?
        var continuationPrompt: String?

        if let error = runResult.error {
            status = .failed
            entries.append(HookOutputEntry(kind: .error, text: error))
        } else {
            switch runResult.exitCode {
            case 0:
                let trimmedStdout = runResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedStdout.isEmpty {
                    break
                } else if let parsed = HooksProtocol.parseStopOutput(runResult.stdout) {
                    if let systemMessage = parsed.universal.systemMessage {
                        entries.append(HookOutputEntry(kind: .warning, text: systemMessage))
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
                        if let reason = trimmedNonEmpty(parsed.reason) {
                            status = .blocked
                            shouldBlock = true
                            blockReason = reason
                            continuationPrompt = reason
                            entries.append(HookOutputEntry(kind: .feedback, text: reason))
                        } else {
                            status = .failed
                            entries.append(HookOutputEntry(
                                kind: .error,
                                text: "Stop hook returned decision:block without a non-empty reason"
                            ))
                        }
                    }
                } else {
                    status = .failed
                    entries.append(HookOutputEntry(kind: .error, text: "hook returned invalid stop hook JSON output"))
                }
            case 2:
                if let reason = trimmedNonEmpty(runResult.stderr) {
                    status = .blocked
                    shouldBlock = true
                    blockReason = reason
                    continuationPrompt = reason
                    entries.append(HookOutputEntry(kind: .feedback, text: reason))
                } else {
                    status = .failed
                    entries.append(HookOutputEntry(
                        kind: .error,
                        text: "Stop hook exited with code 2 but did not write a continuation prompt to stderr"
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

        let completed = HookCompletedEvent(
            turnID: turnID,
            run: HookDispatcher.completedSummary(
                handler: handler,
                runResult: runResult,
                status: status,
                entries: entries
            )
        )
        let continuationFragments = continuationPrompt.map {
            [HookPromptFragment(text: $0, hookRunID: completed.run.id)]
        } ?? []

        return ParsedHookHandler(
            completed: completed,
            data: HookStopHandlerData(
                shouldStop: shouldStop,
                stopReason: stopReason,
                shouldBlock: shouldBlock,
                blockReason: blockReason,
                continuationFragments: continuationFragments
            )
        )
    }

    public static func aggregateResults(_ results: [HookStopHandlerData]) -> HookStopHandlerData {
        let shouldStop = results.contains { $0.shouldStop }
        let stopReason = results.compactMap(\.stopReason).first
        let shouldBlock = !shouldStop && results.contains { $0.shouldBlock }
        let blockReason = shouldBlock
            ? joinTextChunks(results.compactMap(\.blockReason))
            : nil
        let continuationFragments = shouldBlock
            ? results.filter(\.shouldBlock).flatMap(\.continuationFragments)
            : []

        return HookStopHandlerData(
            shouldStop: shouldStop,
            stopReason: stopReason,
            shouldBlock: shouldBlock,
            blockReason: blockReason,
            continuationFragments: continuationFragments
        )
    }

    private static func serializationFailureOutcome(hookEvents: [HookCompletedEvent]) -> HookStopOutcome {
        HookStopOutcome(
            hookEvents: hookEvents,
            shouldStop: false,
            stopReason: nil,
            shouldBlock: false,
            blockReason: nil,
            continuationFragments: []
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

private struct StopCommandInput: Encodable {
    let request: HookStopRequest

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(request.sessionID.description, forKey: .sessionID)
        try container.encode(request.turnID, forKey: .turnID)
        try container.encodeNilOrValue(request.transcriptPath, forKey: .transcriptPath)
        try container.encode(request.cwd.path, forKey: .cwd)
        try container.encode("Stop", forKey: .hookEventName)
        try container.encode(request.model, forKey: .model)
        try container.encode(request.permissionMode, forKey: .permissionMode)
        try container.encode(request.stopHookActive, forKey: .stopHookActive)
        try container.encodeNilOrValue(request.lastAssistantMessage, forKey: .lastAssistantMessage)
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case turnID = "turn_id"
        case transcriptPath = "transcript_path"
        case cwd
        case hookEventName = "hook_event_name"
        case model
        case permissionMode = "permission_mode"
        case stopHookActive = "stop_hook_active"
        case lastAssistantMessage = "last_assistant_message"
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
