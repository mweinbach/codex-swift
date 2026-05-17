import Foundation

public struct HookPreToolUseRequest: Equatable, Sendable {
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
        toolInput: JSONValue
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
    }
}

public struct HookPreToolUseOutcome: Equatable, Sendable {
    public var hookEvents: [HookCompletedEvent]
    public var shouldBlock: Bool
    public var blockReason: String?
    public var additionalContexts: [String]
    public var updatedInput: JSONValue?

    public init(
        hookEvents: [HookCompletedEvent],
        shouldBlock: Bool,
        blockReason: String?,
        additionalContexts: [String],
        updatedInput: JSONValue? = nil
    ) {
        self.hookEvents = hookEvents
        self.shouldBlock = shouldBlock
        self.blockReason = blockReason
        self.additionalContexts = additionalContexts
        self.updatedInput = updatedInput
    }
}

public struct HookPreToolUseHandlerData: Equatable, Sendable {
    public var shouldBlock: Bool
    public var blockReason: String?
    public var additionalContextsForModel: [String]
    public var updatedInput: JSONValue?

    public init(
        shouldBlock: Bool = false,
        blockReason: String? = nil,
        additionalContextsForModel: [String] = [],
        updatedInput: JSONValue? = nil
    ) {
        self.shouldBlock = shouldBlock
        self.blockReason = blockReason
        self.additionalContextsForModel = additionalContextsForModel
        self.updatedInput = updatedInput
    }
}

public struct ParsedHookHandler<Data: Equatable & Sendable>: Equatable, Sendable {
    public var completed: HookCompletedEvent
    public var data: Data
    public var completionOrder: Int

    public init(completed: HookCompletedEvent, data: Data, completionOrder: Int = 0) {
        self.completed = completed
        self.data = data
        self.completionOrder = completionOrder
    }
}

public enum HookPreToolUse {
    public static func preview(
        handlers: [ConfiguredHookHandler],
        request: HookPreToolUseRequest,
        startedAt: Int64 = Int64(Date().timeIntervalSince1970)
    ) -> [HookRunSummary] {
        let matcherInputs = HookDispatcher.matcherInputs(
            toolName: request.toolName,
            matcherAliases: request.matcherAliases
        )
        return HookDispatcher
            .selectHandlers(handlers, eventName: .preToolUse, matcherInputs: matcherInputs)
            .map { HookDispatcher.runningSummary(handler: $0, startedAt: startedAt).addingToolUseID(request.toolUseID) }
    }

    public static func commandInputJSON(_ request: HookPreToolUseRequest) throws -> String {
        let data = try JSONEncoder().encode(PreToolUseCommandInput(request: request))
        return String(decoding: data, as: UTF8.self)
    }

    public static func run(
        handlers: [ConfiguredHookHandler],
        shell: HookCommandShell,
        request: HookPreToolUseRequest
    ) async -> HookPreToolUseOutcome {
        let matcherInputs = HookDispatcher.matcherInputs(
            toolName: request.toolName,
            matcherAliases: request.matcherAliases
        )
        let matched = HookDispatcher.selectHandlers(handlers, eventName: .preToolUse, matcherInputs: matcherInputs)
        guard !matched.isEmpty else {
            return HookPreToolUseOutcome(
                hookEvents: [],
                shouldBlock: false,
                blockReason: nil,
                additionalContexts: [],
                updatedInput: nil
            )
        }

        let inputJSON: String
        do {
            inputJSON = try commandInputJSON(request)
        } catch {
            let hookEvents = serializationFailureHookEventsForToolUse(
                handlers: matched,
                turnID: request.turnID,
                message: "failed to serialize pre tool use hook input: \(error)",
                toolUseID: request.toolUseID
            )
            return HookPreToolUseOutcome(
                hookEvents: hookEvents,
                shouldBlock: false,
                blockReason: nil,
                additionalContexts: [],
                updatedInput: nil
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

        let shouldBlock = parsed.contains { $0.data.shouldBlock }
        let blockReason = parsed.compactMap(\.data.blockReason).first
        let additionalContexts = flattenAdditionalContexts(
            parsed.map(\.data.additionalContextsForModel)
        )
        let updatedInput = shouldBlock ? nil : latestUpdatedInput(parsed)

        return HookPreToolUseOutcome(
            hookEvents: parsed.map { hookCompletedForToolUse($0.completed, toolUseID: request.toolUseID) },
            shouldBlock: shouldBlock,
            blockReason: blockReason,
            additionalContexts: additionalContexts,
            updatedInput: updatedInput
        )
    }

    public static func parseCompleted(
        handler: ConfiguredHookHandler,
        runResult: HookCommandRunResult,
        turnID: String?
    ) -> ParsedHookHandler<HookPreToolUseHandlerData> {
        var entries: [HookOutputEntry] = []
        var status = HookRunStatus.completed
        var shouldBlock = false
        var blockReason: String?
        var additionalContextsForModel: [String] = []
        var updatedInput: JSONValue?

        if let error = runResult.error {
            status = .failed
            entries.append(HookOutputEntry(kind: .error, text: error))
        } else {
            switch runResult.exitCode {
            case 0:
                let trimmedStdout = runResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedStdout.isEmpty {
                    break
                } else if let parsed = HooksProtocol.parsePreToolUseOutput(runResult.stdout) {
                    if let systemMessage = parsed.universal.systemMessage {
                        entries.append(HookOutputEntry(kind: .warning, text: systemMessage))
                    }
                    if let invalidReason = parsed.invalidReason {
                        status = .failed
                        entries.append(HookOutputEntry(kind: .error, text: invalidReason))
                    } else {
                        if let additionalContext = parsed.additionalContext {
                            appendAdditionalContext(
                                additionalContext,
                                entries: &entries,
                                contexts: &additionalContextsForModel
                            )
                        }
                        if let reason = parsed.blockReason {
                            status = .blocked
                            shouldBlock = true
                            blockReason = reason
                            entries.append(HookOutputEntry(kind: .feedback, text: reason))
                        }
                        if !shouldBlock {
                            updatedInput = parsed.updatedInput
                        }
                    }
                } else if HooksProtocol.looksLikeJSON(runResult.stdout) {
                    status = .failed
                    entries.append(HookOutputEntry(kind: .error, text: "hook returned invalid pre-tool-use JSON output"))
                }
            case 2:
                if let reason = trimmedNonEmpty(runResult.stderr) {
                    status = .blocked
                    shouldBlock = true
                    blockReason = reason
                    entries.append(HookOutputEntry(kind: .feedback, text: reason))
                } else {
                    status = .failed
                    entries.append(HookOutputEntry(
                        kind: .error,
                        text: "PreToolUse hook exited with code 2 but did not write a blocking reason to stderr"
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
            data: HookPreToolUseHandlerData(
                shouldBlock: shouldBlock,
                blockReason: blockReason,
                additionalContextsForModel: additionalContextsForModel,
                updatedInput: updatedInput
            )
        )
    }

    public static func hookCompletedForToolUse(
        _ completed: HookCompletedEvent,
        toolUseID: String
    ) -> HookCompletedEvent {
        HookCompletedEvent(
            turnID: completed.turnID,
            run: completed.run.addingToolUseID(toolUseID)
        )
    }

    public static func serializationFailureHookEventsForToolUse(
        handlers: [ConfiguredHookHandler],
        turnID: String?,
        message: String,
        toolUseID: String
    ) -> [HookCompletedEvent] {
        handlers.map { handler in
            HookCompletedEvent(
                turnID: turnID,
                run: HookDispatcher.completedSummary(
                    handler: handler,
                    runResult: HookCommandRunResult(startedAt: 0, completedAt: 0, durationMs: 0),
                    status: .failed,
                    entries: [HookOutputEntry(kind: .error, text: message)]
                ).addingToolUseID(toolUseID)
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

    private static func flattenAdditionalContexts(_ groups: [[String]]) -> [String] {
        groups.flatMap { $0 }
    }

    private static func latestUpdatedInput(_ results: [ParsedHookHandler<HookPreToolUseHandlerData>]) -> JSONValue? {
        results
            .compactMap { result -> (Int, JSONValue)? in
                result.data.updatedInput.map { (result.completionOrder, $0) }
            }
            .max { left, right in left.0 < right.0 }?
            .1
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct PreToolUseCommandInput: Encodable {
    let request: HookPreToolUseRequest

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(request.sessionID.description, forKey: .sessionID)
        try container.encode(request.turnID, forKey: .turnID)
        try container.encodeNilOrValue(request.transcriptPath, forKey: .transcriptPath)
        try container.encode(request.cwd.path, forKey: .cwd)
        try container.encode("PreToolUse", forKey: .hookEventName)
        try container.encode(request.model, forKey: .model)
        try container.encode(request.permissionMode, forKey: .permissionMode)
        try container.encode(request.toolName, forKey: .toolName)
        try container.encode(request.toolInput, forKey: .toolInput)
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
        case toolUseID = "tool_use_id"
    }
}

private extension HookRunSummary {
    func addingToolUseID(_ toolUseID: String) -> HookRunSummary {
        HookRunSummary(
            id: "\(id):\(toolUseID)",
            eventName: eventName,
            handlerType: handlerType,
            executionMode: executionMode,
            scope: scope,
            sourcePath: sourcePath,
            source: source,
            displayOrder: displayOrder,
            status: status,
            statusMessage: statusMessage,
            startedAt: startedAt,
            completedAt: completedAt,
            durationMs: durationMs,
            entries: entries
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
