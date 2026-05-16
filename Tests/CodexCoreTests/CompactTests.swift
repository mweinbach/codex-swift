import XCTest
@testable import CodexCore

final class CompactTests: XCTestCase {
    func testBundledPromptResourcesMatchRustTemplates() {
        XCTAssertTrue(Compact.summarizationPrompt.hasPrefix("You are performing a CONTEXT CHECKPOINT COMPACTION."))
        XCTAssertTrue(Compact.summaryPrefix.hasPrefix("Another language model started to solve this problem"))
        XCTAssertFalse(Compact.summaryPrefix.hasSuffix("\n"))
    }

    func testContentItemsToTextJoinsNonEmptySegments() {
        let items: [ContentItem] = [
            .inputText(text: "hello"),
            .outputText(text: ""),
            .outputText(text: "world")
        ]

        XCTAssertEqual(Compact.contentItemsToText(items), "hello\nworld")
    }

    func testContentItemsToTextIgnoresImageOnlyContent() {
        XCTAssertNil(Compact.contentItemsToText([.inputImage(imageURL: "file://image.png")]))
    }

    func testCollectUserMessagesExtractsUserTextOnly() {
        let items: [ResponseItem] = [
            .message(role: "assistant", content: [.outputText(text: "ignored")]),
            .message(role: "user", content: [.inputText(text: "first")]),
            .other
        ]

        XCTAssertEqual(Compact.collectUserMessages(items), ["first"])
    }

    func testCollectUserMessagesFiltersSessionPrefixEntries() {
        let items: [ResponseItem] = [
            .message(role: "user", content: [
                .inputText(text: "# AGENTS.md instructions for project\n\n<INSTRUCTIONS>\ndo things\n</INSTRUCTIONS>")
            ]),
            .message(role: "user", content: [
                .inputText(text: "<ENVIRONMENT_CONTEXT>cwd=/tmp</ENVIRONMENT_CONTEXT>")
            ]),
            .message(role: "user", content: [
                .inputText(text: "<skill>\n<name>demo</name>\n<path>skills/demo/SKILL.md</path>\nbody\n</skill>")
            ]),
            .message(role: "user", content: [
                .inputText(text: "<user_shell_command>echo 42</user_shell_command>")
            ]),
            .message(role: "user", content: [
                .inputText(text: "<turn_aborted>interrupted</turn_aborted>")
            ]),
            .message(role: "user", content: [
                .inputText(text: "<SUBAGENT_NOTIFICATION>{}</subagent_notification>")
            ]),
            .message(role: "user", content: [.inputText(text: "real user message")])
        ]

        XCTAssertEqual(Compact.collectUserMessages(items), ["real user message"])
    }

    func testCollectUserMessagesFiltersCompactionSummaryMessages() {
        let summary = "\(Compact.summaryPrefix)\nprevious summary"
        let items: [ResponseItem] = [
            .message(role: "user", content: [.inputText(text: summary)]),
            .message(role: "user", content: [.inputText(text: "fresh message")])
        ]

        XCTAssertTrue(Compact.isSummaryMessage(summary))
        XCTAssertEqual(Compact.collectUserMessages(items), ["fresh message"])
    }

    func testBuildTokenLimitedCompactedHistoryTruncatesOverlongUserMessages() {
        let maxTokens = 16
        let big = String(repeating: "word ", count: 200)
        let history = Compact.buildCompactedHistory(
            initialContext: [],
            userMessages: [big],
            summaryText: "SUMMARY",
            maxTokens: maxTokens
        )

        XCTAssertEqual(history.count, 2)
        let truncatedText = messageText(history[0])
        XCTAssertTrue(
            truncatedText.contains("tokens truncated"),
            "expected truncation marker in truncated user message"
        )
        XCTAssertFalse(
            truncatedText.contains(big),
            "truncated user message should not include the full oversized user text"
        )
        XCTAssertEqual(messageText(history[1]), "SUMMARY")
    }

    func testBuildCompactedHistoryAppendsSummaryMessage() {
        let initialContext: [ResponseItem] = [
            .message(role: "system", content: [.inputText(text: "initial")])
        ]
        let history = Compact.buildCompactedHistory(
            initialContext: initialContext,
            userMessages: ["first user message"],
            summaryText: "summary text"
        )

        XCTAssertEqual(history.first, initialContext.first)
        XCTAssertEqual(messageText(history.last!), "summary text")
    }

    func testBuildCompactedHistoryUsesFallbackForEmptySummary() {
        let history = Compact.buildCompactedHistory(
            initialContext: [],
            userMessages: [],
            summaryText: "",
            maxTokens: 1
        )

        XCTAssertEqual(history, [
            .message(role: "user", content: [.inputText(text: "(no summary available)")])
        ])
    }

    func testInsertInitialContextBeforeLastRealUserKeepsSummaryLast() {
        let summary = "\(Compact.summaryPrefix)\nsummary text"
        let compactedHistory: [ResponseItem] = [
            .message(role: "user", content: [.inputText(text: "older user")]),
            .message(role: "user", content: [.inputText(text: "latest user")]),
            .message(role: "user", content: [.inputText(text: summary)]),
        ]
        let initialContext: [ResponseItem] = [
            .message(role: "developer", content: [.inputText(text: "fresh permissions")])
        ]

        let refreshed = Compact.insertInitialContextBeforeLastRealUserOrSummary(
            compactedHistory: compactedHistory,
            initialContext: initialContext
        )

        XCTAssertEqual(refreshed, [
            .message(role: "user", content: [.inputText(text: "older user")]),
            .message(role: "developer", content: [.inputText(text: "fresh permissions")]),
            .message(role: "user", content: [.inputText(text: "latest user")]),
            .message(role: "user", content: [.inputText(text: summary)]),
        ])
    }

    func testInsertInitialContextFallsBackToSummaryWhenNoRealUserRemains() {
        let summary = "\(Compact.summaryPrefix)\nsummary text"
        let initialContext: [ResponseItem] = [
            .message(role: "developer", content: [.inputText(text: "fresh permissions")])
        ]

        let refreshed = Compact.insertInitialContextBeforeLastRealUserOrSummary(
            compactedHistory: [.message(role: "user", content: [.inputText(text: summary)])],
            initialContext: initialContext
        )

        XCTAssertEqual(refreshed, [
            .message(role: "developer", content: [.inputText(text: "fresh permissions")]),
            .message(role: "user", content: [.inputText(text: summary)]),
        ])
    }

    func testInsertInitialContextFallsBackToCompactionItem() {
        let initialContext: [ResponseItem] = [
            .message(role: "developer", content: [.inputText(text: "fresh permissions")])
        ]

        let refreshed = Compact.insertInitialContextBeforeLastRealUserOrSummary(
            compactedHistory: [.compaction(encryptedContent: "encrypted")],
            initialContext: initialContext
        )

        XCTAssertEqual(refreshed, [
            .message(role: "developer", content: [.inputText(text: "fresh permissions")]),
            .compaction(encryptedContent: "encrypted"),
        ])
    }

    func testInsertInitialContextFallsBackToContextCompactionItem() {
        let initialContext: [ResponseItem] = [
            .message(role: "developer", content: [.inputText(text: "fresh permissions")])
        ]

        let refreshed = Compact.insertInitialContextBeforeLastRealUserOrSummary(
            compactedHistory: [.contextCompaction(encryptedContent: "encrypted")],
            initialContext: initialContext
        )

        XCTAssertEqual(refreshed, [
            .message(role: "developer", content: [.inputText(text: "fresh permissions")]),
            .contextCompaction(encryptedContent: "encrypted"),
        ])
    }

    func testInsertInitialContextAppendsWhenNoBoundaryExists() {
        let initialContext: [ResponseItem] = [
            .message(role: "developer", content: [.inputText(text: "fresh permissions")])
        ]

        let refreshed = Compact.insertInitialContextBeforeLastRealUserOrSummary(
            compactedHistory: [.message(role: "assistant", content: [.outputText(text: "answer")])],
            initialContext: initialContext
        )

        XCTAssertEqual(refreshed, [
            .message(role: "assistant", content: [.outputText(text: "answer")]),
            .message(role: "developer", content: [.inputText(text: "fresh permissions")]),
        ])
    }

    func testBuildRemoteV2CompactedHistoryMatchesRustRetentionShape() {
        let input: [ResponseItem] = [
            .message(role: "developer", content: [.inputText(text: "dev")]),
            .message(role: "system", content: [.inputText(text: "sys")]),
            .message(role: "user", content: [.inputText(text: "user")]),
            .message(role: "assistant", content: [.outputText(text: "commentary")], phase: .commentary),
            .message(role: "assistant", content: [.outputText(text: "final")], phase: .finalAnswer),
            .functionCall(name: "shell", arguments: "{}", callID: "call_1"),
            .compaction(encryptedContent: "old"),
        ]
        let output = ResponseItem.compaction(encryptedContent: "new")

        XCTAssertEqual(
            Compact.buildRemoteV2CompactedHistory(promptInput: input, compactionOutput: output),
            [
                .message(role: "developer", content: [.inputText(text: "dev")]),
                .message(role: "system", content: [.inputText(text: "sys")]),
                .message(role: "user", content: [.inputText(text: "user")]),
                output,
            ]
        )
    }

    func testCollectRemoteV2CompactionOutputReturnsResponseIDAndIgnoresOtherItems() {
        let compaction = ResponseItem.compaction(encryptedContent: "encrypted")
        let result = Compact.collectRemoteV2CompactionOutput(from: [
            .success(.created),
            .success(.outputItemDone(.message(role: "assistant", content: [.outputText(text: "ignored")], phase: .finalAnswer))),
            .success(.outputItemDone(compaction)),
            .success(.completed(responseID: "resp-compact", tokenUsage: nil, endTurn: true)),
            .success(.outputItemDone(.compaction(encryptedContent: "ignored-after-complete"))),
        ])

        XCTAssertEqual(
            try XCTUnwrap(result.successValue),
            RemoteCompactionV2Output(item: compaction, responseID: "resp-compact")
        )
    }

    func testRemoteV2ResponseProcessedRequestIsFeatureGatedLikeRust() throws {
        let output = RemoteCompactionV2Output(
            item: .compaction(encryptedContent: "encrypted"),
            responseID: "resp-compact"
        )
        var features = FeatureStates.withDefaults()

        XCTAssertNil(Compact.remoteV2ResponseProcessedRequest(output: output, features: features))

        features.set(.responsesWebsocketResponseProcessed, enabled: true)
        let request = try XCTUnwrap(Compact.remoteV2ResponseProcessedRequest(output: output, features: features))
        XCTAssertEqual(
            request,
            .responseProcessed(ResponseProcessedWebSocketRequest(responseID: "resp-compact"))
        )
    }

    func testRemoteV2ResponseProcessedRequestUsesCollectedCompletedResponseIDLikeRust() throws {
        let compaction = ResponseItem.compaction(encryptedContent: "encrypted")
        let output = try XCTUnwrap(Compact.collectRemoteV2CompactionOutput(from: [
            .success(.outputItemDone(compaction)),
            .success(.completed(responseID: "resp-compact", tokenUsage: nil)),
            .failure(.stream("ignored after response.completed")),
        ]).successValue)
        var features = FeatureStates.withDefaults()
        features.set(.responsesWebsocketResponseProcessed, enabled: true)

        XCTAssertEqual(output, RemoteCompactionV2Output(item: compaction, responseID: "resp-compact"))
        XCTAssertEqual(
            Compact.remoteV2ResponseProcessedRequest(output: output, features: features),
            .responseProcessed(ResponseProcessedWebSocketRequest(responseID: "resp-compact"))
        )
    }

    func testRunRemoteV2CompactionWithHooksRunsPrePostAroundSuccessLikeRust() async throws {
        let compaction = ResponseItem.compaction(encryptedContent: "encrypted")
        var features = FeatureStates.withDefaults()
        features.set(.responsesWebsocketResponseProcessed, enabled: true)

        let result = await Compact.runRemoteV2CompactionWithHooks(
            handlers: try [
                compactHook(eventName: .preCompact, command: #"printf %s '{"systemMessage":"pre"}'"#),
                compactHook(eventName: .postCompact, command: #"printf %s '{"systemMessage":"post"}'"#),
            ],
            shell: HookCommandShell(program: "/bin/sh", arguments: ["-c"]),
            request: try remoteV2HookRequest(),
            features: features
        ) {
            [
                .success(.outputItemDone(compaction)),
                .success(.completed(responseID: "resp-compact", tokenUsage: nil)),
            ]
        }

        let output = try XCTUnwrap(result.successValue)
        XCTAssertEqual(output.output, RemoteCompactionV2Output(item: compaction, responseID: "resp-compact"))
        XCTAssertEqual(
            output.responseProcessedRequest,
            .responseProcessed(ResponseProcessedWebSocketRequest(responseID: "resp-compact"))
        )
        XCTAssertEqual(output.hookEvents.map(\.run.eventName), [.preCompact, .postCompact])
        XCTAssertEqual(output.hookEvents.map(\.run.status), [.completed, .completed])
        XCTAssertEqual(output.hookEvents.map(\.run.entries.first?.text), ["pre", "post"])
    }

    func testRunRemoteV2CompactionWithHooksStopsBeforeRequestWhenPreHookStopsLikeRust() async throws {
        let calls = RemoteV2CompactionCallCounter()

        let result = await Compact.runRemoteV2CompactionWithHooks(
            handlers: try [
                compactHook(
                    eventName: .preCompact,
                    command: #"printf %s '{"continue":false,"stopReason":"pause before compact"}'"#
                ),
                compactHook(eventName: .postCompact, command: #"printf %s '{"systemMessage":"post"}'"#),
            ],
            shell: HookCommandShell(program: "/bin/sh", arguments: ["-c"]),
            request: try remoteV2HookRequest(),
            features: .withDefaults()
        ) {
            await calls.record()
            return [
                .success(.outputItemDone(.compaction(encryptedContent: "should-not-run"))),
                .success(.completed(responseID: "resp-compact", tokenUsage: nil)),
            ]
        }

        let callCount = await calls.count
        XCTAssertEqual(callCount, 0)
        guard case let .preCompactStopped(reason, hookEvents)? = result.failureValue else {
            return XCTFail("expected pre compact stop, got \(String(describing: result.failureValue))")
        }
        XCTAssertEqual(reason, "pause before compact")
        XCTAssertEqual(hookEvents.map(\.run.eventName), [.preCompact])
        XCTAssertEqual(hookEvents.map(\.run.status), [.stopped])
    }

    func testRunRemoteV2CompactionWithHooksStopsAfterSuccessfulPostHookStopLikeRust() async throws {
        let calls = RemoteV2CompactionCallCounter()

        let result = await Compact.runRemoteV2CompactionWithHooks(
            handlers: try [
                compactHook(eventName: .preCompact, command: #"printf %s '{"systemMessage":"pre"}'"#),
                compactHook(eventName: .postCompact, command: #"printf %s '{"continue":false}'"#),
            ],
            shell: HookCommandShell(program: "/bin/sh", arguments: ["-c"]),
            request: try remoteV2HookRequest(),
            features: .withDefaults()
        ) {
            await calls.record()
            return [
                .success(.outputItemDone(.compaction(encryptedContent: "encrypted"))),
                .success(.completed(responseID: "resp-compact", tokenUsage: nil)),
            ]
        }

        let callCount = await calls.count
        XCTAssertEqual(callCount, 1)
        guard case let .postCompactStopped(hookEvents)? = result.failureValue else {
            return XCTFail("expected post compact stop, got \(String(describing: result.failureValue))")
        }
        XCTAssertEqual(hookEvents.map(\.run.eventName), [.preCompact, .postCompact])
        XCTAssertEqual(hookEvents.map(\.run.status), [.completed, .stopped])
        XCTAssertEqual(hookEvents.last?.run.entries, [
            HookOutputEntry(kind: .stop, text: "PostCompact hook stopped execution")
        ])
    }

    func testCollectRemoteV2CompactionOutputIgnoresLegacyContextCompaction() {
        let result = Compact.collectRemoteV2CompactionOutput(from: [
            .success(.outputItemDone(.contextCompaction())),
            .success(.completed(responseID: "resp-compact", tokenUsage: nil)),
        ])

        XCTAssertEqual(
            result.failureValue,
            .stream("remote compaction v2 expected exactly one compaction output item, got 0 from 1 output items")
        )
    }

    func testCollectRemoteV2CompactionOutputRequiresCompletion() {
        let result = Compact.collectRemoteV2CompactionOutput(from: [
            .success(.outputItemDone(.compaction(encryptedContent: "encrypted"))),
        ])

        XCTAssertEqual(
            result.failureValue,
            .stream("remote compaction v2 stream closed before response.completed")
        )
    }

    func testCollectRemoteV2CompactionOutputRequiresExactlyOneCompactionItem() {
        let none = Compact.collectRemoteV2CompactionOutput(from: [
            .success(.outputItemDone(.message(role: "assistant", content: [.outputText(text: "ignored")]))),
            .success(.completed(responseID: "resp-compact", tokenUsage: nil)),
        ])
        XCTAssertEqual(
            none.failureValue,
            .stream("remote compaction v2 expected exactly one compaction output item, got 0 from 1 output items")
        )

        let two = Compact.collectRemoteV2CompactionOutput(from: [
            .success(.outputItemDone(.compaction(encryptedContent: "first"))),
            .success(.outputItemDone(.compaction(encryptedContent: "second"))),
            .success(.completed(responseID: "resp-compact", tokenUsage: nil)),
        ])
        XCTAssertEqual(
            two.failureValue,
            .stream("remote compaction v2 expected exactly one compaction output item, got 2 from 2 output items")
        )
    }

    private func messageText(_ item: ResponseItem) -> String {
        guard case let .message(_, role, content, _) = item, role == "user" else {
            XCTFail("expected user message, got \(item)")
            return ""
        }
        return Compact.contentItemsToText(content) ?? ""
    }

    private func remoteV2HookRequest() throws -> RemoteCompactionV2HookRequest {
        try RemoteCompactionV2HookRequest(
            sessionID: ThreadId(string: "00000000-0000-4000-8000-0000000000c0"),
            turnID: "turn-compact",
            cwd: AbsolutePath(absolutePath: "/tmp"),
            model: "gpt-test",
            trigger: "manual"
        )
    }

    private func compactHook(eventName: HookEventName, command: String) throws -> ConfiguredHookHandler {
        try ConfiguredHookHandler(
            eventName: eventName,
            matcher: "manual",
            command: command,
            timeoutSec: 5,
            statusMessage: "running compact hook",
            sourcePath: AbsolutePath(absolutePath: "/tmp/hooks.json"),
            source: .user,
            displayOrder: eventName == .preCompact ? 0 : 1
        )
    }
}

private extension Result {
    var successValue: Success? {
        if case let .success(value) = self {
            return value
        }
        return nil
    }

    var failureValue: Failure? {
        if case let .failure(error) = self {
            return error
        }
        return nil
    }
}

private actor RemoteV2CompactionCallCounter {
    private var value = 0

    var count: Int {
        value
    }

    func record() {
        value += 1
    }
}
