import Foundation

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

public enum NonInteractiveExec {
    public static func makePrompt(
        prompt: String,
        imagePaths: [String],
        outputSchema: JSONValue?,
        cwd: URL,
        approvalPolicy: AskForApproval,
        sandboxPolicy: SandboxPolicy,
        shell: Shell
    ) -> Prompt {
        let context = TurnContext(
            cwd: cwd.path,
            approvalPolicy: approvalPolicy,
            sandboxPolicy: sandboxPolicy
        )
        var input = [
            EnvironmentContext
                .fromTurnContext(context, shell: shell)
                .asResponseItem()
        ]

        let userInputs = imagePaths.map { UserInput.localImage(path: $0) } + [.text(prompt)]
        input.append(ResponseInputItem(userInputs: userInputs).responseItem())

        return Prompt(
            input: input,
            tools: [],
            parallelToolCalls: false,
            outputSchema: outputSchema
        )
    }

    public static func responsesOptions(
        conversationID: ConversationId,
        modelFamily: ModelFamily,
        reasoningEffort: ReasoningEffort?,
        reasoningSummary: ReasoningSummary?,
        verbosity: Verbosity?,
        outputSchema: JSONValue?
    ) -> ResponsesOptions {
        let effort = reasoningEffort ?? modelFamily.defaultReasoningEffort
        let summary = reasoningSummary ?? (modelFamily.supportsReasoningSummaries ? .auto : nil)
        let reasoning = effort == nil && summary == nil
            ? nil
            : ResponsesAPIReasoning(effort: effort, summary: summary)

        return ResponsesOptions(
            reasoning: reasoning,
            text: ResponsesAPITextControls.createForRequest(
                verbosity: verbosity ?? modelFamily.defaultVerbosity,
                outputSchema: outputSchema
            ),
            conversationID: conversationID.description,
            sessionSource: .exec
        )
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
                        if outputMode == .jsonLines {
                            jsonLines.append(encodeJSONLine(
                                ExecJSONItemCompletedEvent(
                                    item: CompletedItem(
                                        id: "item_\(itemIndex)",
                                        type: "agent_message",
                                        text: message
                                    )
                                ),
                                using: jsonEncoder
                            ))
                            itemIndex += 1
                        }
                    } else if outputMode == .jsonLines,
                              let reasoningText = reasoningText(from: item)
                    {
                        jsonLines.append(encodeJSONLine(
                            ExecJSONItemCompletedEvent(
                                item: CompletedItem(
                                    id: "item_\(itemIndex)",
                                    type: "reasoning",
                                    text: reasoningText
                                )
                            ),
                            using: jsonEncoder
                        ))
                        itemIndex += 1
                    }

                case let .completed(_, usage):
                    sawCompletion = true
                    tokenUsage = usage

                case .created,
                     .outputItemAdded,
                     .outputTextDelta,
                     .reasoningSummaryDelta,
                     .reasoningContentDelta,
                     .reasoningSummaryPartAdded,
                     .rateLimits:
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
                jsonLines.append(encodeJSONLine(TurnCompletedEvent(usage: tokenUsage.map(JSONUsage.init)), using: jsonEncoder))
            } else {
                jsonLines.append(encodeJSONLine(TurnFailedEvent(error: errors.last ?? "unknown error"), using: jsonEncoder))
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
    let text: String
}

private struct ExecJSONItemCompletedEvent: Encodable {
    let type = "item.completed"
    let item: CompletedItem
}

private struct TurnCompletedEvent: Encodable {
    let type = "turn.completed"
    let usage: JSONUsage?
}

private struct TurnFailedEvent: Encodable {
    let type = "turn.failed"
    let error: String
}

private struct ErrorJSONEvent: Encodable {
    let type = "error"
    let message: String
}

private struct JSONUsage: Encodable, Equatable, Sendable {
    let inputTokens: Int64
    let cachedInputTokens: Int64
    let outputTokens: Int64
    let reasoningOutputTokens: Int64
    let totalTokens: Int64

    init(_ usage: TokenUsage) {
        inputTokens = usage.inputTokens
        cachedInputTokens = usage.cachedInputTokens
        outputTokens = usage.outputTokens
        reasoningOutputTokens = usage.reasoningOutputTokens
        totalTokens = usage.totalTokens
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cachedInputTokens = "cached_input_tokens"
        case outputTokens = "output_tokens"
        case reasoningOutputTokens = "reasoning_output_tokens"
        case totalTokens = "total_tokens"
    }
}
