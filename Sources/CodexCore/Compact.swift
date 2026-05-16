import Foundation

public enum Compact {
    public static let compactUserMessageMaxTokens = 20_000

    public static let summarizationPrompt: String = {
        loadResource("compact_prompt", subdirectory: "Compact")
    }()

    public static let summaryPrefix: String = {
        loadResource("compact_summary_prefix", subdirectory: "Compact")
    }()

    public static func contentItemsToText(_ content: [ContentItem]) -> String? {
        let pieces = content.compactMap { item -> String? in
            switch item {
            case let .inputText(text), let .outputText(text):
                return text.isEmpty ? nil : text
            case .inputImage:
                return nil
            }
        }
        return pieces.isEmpty ? nil : pieces.joined(separator: "\n")
    }

    public static func collectUserMessages(_ items: [ResponseItem]) -> [String] {
        items.compactMap { item in
            guard case let .message(_, role, content, _) = item, role == "user" else {
                return nil
            }
            guard shouldKeepUserMessage(content) else {
                return nil
            }
            return contentItemsToText(content) ?? ""
        }.filter { !isSummaryMessage($0) }
    }

    public static func isSummaryMessage(_ message: String) -> Bool {
        message.hasPrefix("\(summaryPrefix)\n")
    }

    public static func buildCompactedHistory(
        initialContext: [ResponseItem],
        userMessages: [String],
        summaryText: String
    ) -> [ResponseItem] {
        buildCompactedHistory(
            initialContext: initialContext,
            userMessages: userMessages,
            summaryText: summaryText,
            maxTokens: compactUserMessageMaxTokens
        )
    }

    public static func buildCompactedHistory(
        initialContext: [ResponseItem],
        userMessages: [String],
        summaryText: String,
        maxTokens: Int
    ) -> [ResponseItem] {
        var history = initialContext
        var selectedMessages: [String] = []

        if maxTokens > 0 {
            var remaining = maxTokens
            for message in userMessages.reversed() {
                if remaining == 0 {
                    break
                }

                let tokens = Truncation.approxTokenCount(message)
                if tokens <= remaining {
                    selectedMessages.append(message)
                    remaining = max(0, remaining - tokens)
                } else {
                    selectedMessages.append(Truncation.truncateText(message, policy: .tokens(remaining)))
                    break
                }
            }
            selectedMessages.reverse()
        }

        for message in selectedMessages {
            history.append(.message(role: "user", content: [.inputText(text: message)]))
        }

        let finalSummary = summaryText.isEmpty ? "(no summary available)" : summaryText
        history.append(.message(role: "user", content: [.inputText(text: finalSummary)]))
        return history
    }

    public static func insertInitialContextBeforeLastRealUserOrSummary(
        compactedHistory: [ResponseItem],
        initialContext: [ResponseItem]
    ) -> [ResponseItem] {
        var lastUserOrSummaryIndex: Int?
        var lastRealUserIndex: Int?

        for index in compactedHistory.indices.reversed() {
            guard case let .message(_, role, content, _) = compactedHistory[index],
                  role == "user"
            else {
                continue
            }

            lastUserOrSummaryIndex = lastUserOrSummaryIndex ?? index
            let message = contentItemsToText(content) ?? ""
            if !isSummaryMessage(message) {
                lastRealUserIndex = index
                break
            }
        }

        let lastCompactionIndex = compactedHistory.indices.reversed().first { index in
            if case .compaction = compactedHistory[index] {
                return true
            }
            if case .contextCompaction = compactedHistory[index] {
                return true
            }
            return false
        }

        let insertionIndex = lastRealUserIndex ?? lastUserOrSummaryIndex ?? lastCompactionIndex
        var history = compactedHistory
        if let insertionIndex {
            history.insert(contentsOf: initialContext, at: insertionIndex)
        } else {
            history.append(contentsOf: initialContext)
        }
        return history
    }

    public static func collectRemoteV2CompactionOutput(
        from events: [Result<ResponseEvent, APIError>]
    ) -> Result<RemoteCompactionV2Output, APIError> {
        var outputItemCount = 0
        var compactionCount = 0
        var compactionOutput: ResponseItem?
        var completedResponseID: String?

        for result in events {
            switch result {
            case let .success(event):
                switch event {
                case let .outputItemDone(item):
                    outputItemCount += 1
                    if case .compaction = item {
                        compactionCount += 1
                        compactionOutput = compactionOutput ?? item
                    }
                case let .completed(responseID, _, _):
                    completedResponseID = responseID
                    break
                default:
                    continue
                }
            case let .failure(error):
                return .failure(error)
            }

            if completedResponseID != nil {
                break
            }
        }

        guard let responseID = completedResponseID else {
            return .failure(.stream("remote compaction v2 stream closed before response.completed"))
        }

        guard compactionCount == 1 else {
            return .failure(.stream(
                "remote compaction v2 expected exactly one compaction output item, got \(compactionCount) from \(outputItemCount) output items"
            ))
        }

        guard let compactionOutput else {
            preconditionFailure("compaction output must exist when count is exactly one")
        }

        return .success(RemoteCompactionV2Output(item: compactionOutput, responseID: responseID))
    }

    public static func buildRemoteV2CompactedHistory(
        promptInput: [ResponseItem],
        compactionOutput: ResponseItem
    ) -> [ResponseItem] {
        promptInput.filter(isRetainedForRemoteV2Compaction) + [compactionOutput]
    }

    public static func remoteV2ResponseProcessedRequest(
        output: RemoteCompactionV2Output,
        features: FeatureStates
    ) -> ResponsesWebSocketRequest? {
        guard features.isEnabled(.responsesWebsocketResponseProcessed) else {
            return nil
        }
        return .responseProcessed(ResponseProcessedWebSocketRequest(responseID: output.responseID))
    }

    public static func runRemoteV2CompactionWithHooks(
        handlers: [ConfiguredHookHandler],
        shell: HookCommandShell,
        request: RemoteCompactionV2HookRequest,
        features: FeatureStates,
        collectEvents: @Sendable () async -> [Result<ResponseEvent, APIError>]
    ) async -> Result<RemoteCompactionV2HookedOutput, RemoteCompactionV2HookError> {
        var hookEvents: [HookCompletedEvent] = []

        let preOutcome = await HookPreCompact.run(
            handlers: handlers,
            shell: shell,
            request: request.preCompactRequest
        )
        hookEvents.append(contentsOf: preOutcome.hookEvents)
        if preOutcome.shouldStop {
            return .failure(.preCompactStopped(
                reason: preOutcome.stopReason ?? "PreCompact hook stopped execution",
                hookEvents: hookEvents
            ))
        }

        let output: RemoteCompactionV2Output
        switch collectRemoteV2CompactionOutput(from: await collectEvents()) {
        case let .success(collected):
            output = collected
        case let .failure(error):
            return .failure(.compactionFailed(error: error, hookEvents: hookEvents))
        }

        let postOutcome = await HookPostCompact.run(
            handlers: handlers,
            shell: shell,
            request: request.postCompactRequest
        )
        hookEvents.append(contentsOf: postOutcome.hookEvents)
        if postOutcome.shouldStop {
            return .failure(.postCompactStopped(hookEvents: hookEvents))
        }

        return .success(RemoteCompactionV2HookedOutput(
            output: output,
            responseProcessedRequest: remoteV2ResponseProcessedRequest(output: output, features: features),
            hookEvents: hookEvents
        ))
    }

    private static func shouldKeepUserMessage(_ content: [ContentItem]) -> Bool {
        if UserInstructions.isUserInstructions(message: content)
            || SkillInstructions.isSkillInstructions(message: content)
        {
            return false
        }

        for item in content {
            switch item {
            case let .inputText(text), let .outputText(text):
                if ContextualUserFragments.isStandardText(text) {
                    return false
                }
            case .inputImage:
                continue
            }
        }

        return true
    }

    private static func isRetainedForRemoteV2Compaction(_ item: ResponseItem) -> Bool {
        guard case let .message(_, role, _, _) = item else {
            return false
        }
        return role == "developer" || role == "system" || role == "user"
    }

    private static func loadResource(_ name: String, subdirectory: String) -> String {
        let url = Bundle.module.url(forResource: name, withExtension: "md", subdirectory: subdirectory)
            ?? Bundle.module.url(forResource: name, withExtension: "md")
        guard let url else {
            preconditionFailure("Missing bundled compact resource \(subdirectory)/\(name).md")
        }

        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            preconditionFailure("Unable to load compact resource \(subdirectory)/\(name).md: \(error)")
        }
    }
}

public struct RemoteCompactionV2Output: Equatable, Sendable {
    public let item: ResponseItem
    public let responseID: String

    public init(item: ResponseItem, responseID: String) {
        self.item = item
        self.responseID = responseID
    }
}

public struct RemoteCompactionV2HookRequest: Equatable, Sendable {
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

    fileprivate var preCompactRequest: HookPreCompactRequest {
        HookPreCompactRequest(
            sessionID: sessionID,
            turnID: turnID,
            cwd: cwd,
            transcriptPath: transcriptPath,
            model: model,
            trigger: trigger
        )
    }

    fileprivate var postCompactRequest: HookPostCompactRequest {
        HookPostCompactRequest(
            sessionID: sessionID,
            turnID: turnID,
            cwd: cwd,
            transcriptPath: transcriptPath,
            model: model,
            trigger: trigger
        )
    }
}

public struct RemoteCompactionV2HookedOutput: Equatable, Sendable {
    public var output: RemoteCompactionV2Output
    public var responseProcessedRequest: ResponsesWebSocketRequest?
    public var hookEvents: [HookCompletedEvent]

    public init(
        output: RemoteCompactionV2Output,
        responseProcessedRequest: ResponsesWebSocketRequest?,
        hookEvents: [HookCompletedEvent]
    ) {
        self.output = output
        self.responseProcessedRequest = responseProcessedRequest
        self.hookEvents = hookEvents
    }
}

public enum RemoteCompactionV2HookError: Error, Equatable, Sendable {
    case preCompactStopped(reason: String, hookEvents: [HookCompletedEvent])
    case compactionFailed(error: APIError, hookEvents: [HookCompletedEvent])
    case postCompactStopped(hookEvents: [HookCompletedEvent])
}
