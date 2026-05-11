import Foundation

public struct HookPermissionRequestRequest: Equatable, Sendable {
    public var sessionID: ThreadId
    public var turnID: String
    public var cwd: AbsolutePath
    public var transcriptPath: String?
    public var model: String
    public var permissionMode: String
    public var toolName: String
    public var matcherAliases: [String]
    public var runIDSuffix: String
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
        runIDSuffix: String,
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
        self.runIDSuffix = runIDSuffix
        self.toolInput = toolInput
    }
}

public struct HookPermissionRequestOutcome: Equatable, Sendable {
    public var hookEvents: [HookCompletedEvent]
    public var decision: HookPermissionRequestDecision?

    public init(
        hookEvents: [HookCompletedEvent],
        decision: HookPermissionRequestDecision?
    ) {
        self.hookEvents = hookEvents
        self.decision = decision
    }
}

public struct HookPermissionRequestHandlerData: Equatable, Sendable {
    public var decision: HookPermissionRequestDecision?

    public init(decision: HookPermissionRequestDecision? = nil) {
        self.decision = decision
    }
}

public enum HookPermissionRequest {
    public static func preview(
        handlers: [ConfiguredHookHandler],
        request: HookPermissionRequestRequest,
        startedAt: Int64 = Int64(Date().timeIntervalSince1970)
    ) -> [HookRunSummary] {
        let matcherInputs = HookDispatcher.matcherInputs(
            toolName: request.toolName,
            matcherAliases: request.matcherAliases
        )
        return HookDispatcher
            .selectHandlers(handlers, eventName: .permissionRequest, matcherInputs: matcherInputs)
            .map {
                HookToolUseRunID.add(
                    HookDispatcher.runningSummary(handler: $0, startedAt: startedAt),
                    toolUseID: request.runIDSuffix
                )
            }
    }

    public static func commandInputJSON(_ request: HookPermissionRequestRequest) throws -> String {
        let data = try JSONEncoder().encode(PermissionRequestCommandInput(request: request))
        return String(decoding: data, as: UTF8.self)
    }

    public static func run(
        handlers: [ConfiguredHookHandler],
        shell: HookCommandShell,
        request: HookPermissionRequestRequest
    ) async -> HookPermissionRequestOutcome {
        let matcherInputs = HookDispatcher.matcherInputs(
            toolName: request.toolName,
            matcherAliases: request.matcherAliases
        )
        let matched = HookDispatcher.selectHandlers(handlers, eventName: .permissionRequest, matcherInputs: matcherInputs)
        guard !matched.isEmpty else {
            return HookPermissionRequestOutcome(hookEvents: [], decision: nil)
        }

        let inputJSON: String
        do {
            inputJSON = try commandInputJSON(request)
        } catch {
            let hookEvents = serializationFailureHookEventsForToolUse(
                handlers: matched,
                turnID: request.turnID,
                message: "failed to serialize permission request hook input: \(error)",
                runIDSuffix: request.runIDSuffix
            )
            return HookPermissionRequestOutcome(hookEvents: hookEvents, decision: nil)
        }

        let parsed = await HookDispatcher.executeHandlers(
            handlers: matched,
            shell: shell,
            inputJSON: inputJSON,
            cwd: URL(fileURLWithPath: request.cwd.path)
        ) { handler, result in
            parseCompleted(handler: handler, runResult: result, turnID: request.turnID)
        }

        let decision = resolveDecision(parsed.compactMap(\.data.decision))
        return HookPermissionRequestOutcome(
            hookEvents: parsed.map { hookCompletedForRunSuffix($0.completed, runIDSuffix: request.runIDSuffix) },
            decision: decision
        )
    }

    public static func resolveDecision(
        _ decisions: [HookPermissionRequestDecision]
    ) -> HookPermissionRequestDecision? {
        var resolvedAllow: HookPermissionRequestDecision?
        for decision in decisions {
            switch decision {
            case .allow:
                resolvedAllow = .allow
            case .deny:
                return decision
            }
        }
        return resolvedAllow
    }

    public static func parseCompleted(
        handler: ConfiguredHookHandler,
        runResult: HookCommandRunResult,
        turnID: String?
    ) -> ParsedHookHandler<HookPermissionRequestHandlerData> {
        var entries: [HookOutputEntry] = []
        var status = HookRunStatus.completed
        var decision: HookPermissionRequestDecision?

        if let error = runResult.error {
            status = .failed
            entries.append(HookOutputEntry(kind: .error, text: error))
        } else {
            switch runResult.exitCode {
            case 0:
                let trimmedStdout = runResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedStdout.isEmpty {
                    break
                } else if let parsed = HooksProtocol.parsePermissionRequestOutput(runResult.stdout) {
                    if let systemMessage = parsed.universal.systemMessage {
                        entries.append(HookOutputEntry(kind: .warning, text: systemMessage))
                    }
                    if let invalidReason = parsed.invalidReason {
                        status = .failed
                        entries.append(HookOutputEntry(kind: .error, text: invalidReason))
                    } else if let parsedDecision = parsed.decision {
                        switch parsedDecision {
                        case .allow:
                            decision = .allow
                        case .deny(let message):
                            status = .blocked
                            entries.append(HookOutputEntry(kind: .feedback, text: message))
                            decision = .deny(message: message)
                        }
                    }
                } else if HooksProtocol.looksLikeJSON(runResult.stdout) {
                    status = .failed
                    entries.append(HookOutputEntry(kind: .error, text: "hook returned invalid permission-request JSON output"))
                }
            case 2:
                if let message = trimmedNonEmpty(runResult.stderr) {
                    status = .blocked
                    entries.append(HookOutputEntry(kind: .feedback, text: message))
                    decision = .deny(message: message)
                } else {
                    status = .failed
                    entries.append(HookOutputEntry(
                        kind: .error,
                        text: "PermissionRequest hook exited with code 2 but did not write a denial reason to stderr"
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
            data: HookPermissionRequestHandlerData(decision: decision)
        )
    }

    public static func hookCompletedForRunSuffix(
        _ completed: HookCompletedEvent,
        runIDSuffix: String
    ) -> HookCompletedEvent {
        HookCompletedEvent(
            turnID: completed.turnID,
            run: HookToolUseRunID.add(completed.run, toolUseID: runIDSuffix)
        )
    }

    public static func serializationFailureHookEventsForToolUse(
        handlers: [ConfiguredHookHandler],
        turnID: String?,
        message: String,
        runIDSuffix: String
    ) -> [HookCompletedEvent] {
        handlers.map { handler in
            HookCompletedEvent(
                turnID: turnID,
                run: HookToolUseRunID.add(
                    HookDispatcher.completedSummary(
                        handler: handler,
                        runResult: HookCommandRunResult(startedAt: 0, completedAt: 0, durationMs: 0),
                        status: .failed,
                        entries: [HookOutputEntry(kind: .error, text: message)]
                    ),
                    toolUseID: runIDSuffix
                )
            )
        }
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct PermissionRequestCommandInput: Encodable {
    let request: HookPermissionRequestRequest

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(request.sessionID.description, forKey: .sessionID)
        try container.encode(request.turnID, forKey: .turnID)
        try container.encodeNilOrValue(request.transcriptPath, forKey: .transcriptPath)
        try container.encode(request.cwd.path, forKey: .cwd)
        try container.encode("PermissionRequest", forKey: .hookEventName)
        try container.encode(request.model, forKey: .model)
        try container.encode(request.permissionMode, forKey: .permissionMode)
        try container.encode(request.toolName, forKey: .toolName)
        try container.encode(request.toolInput, forKey: .toolInput)
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
