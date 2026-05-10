import CodexCore
import XCTest

final class ContextManagerTests: XCTestCase {
    func testNonLastReasoningTokensReturnZeroWhenNoUserMessagesLikeRust() {
        let history = ContextManager(items: [
            reasoningWithEncryptedContent(length: 800)
        ])

        XCTAssertEqual(history.nonLastReasoningItemsTokens(), 0)
    }

    func testNonLastReasoningTokensIgnoreEntriesAfterLastUserLikeRust() {
        let history = ContextManager(items: [
            reasoningWithEncryptedContent(length: 900),
            userMessage("first"),
            reasoningWithEncryptedContent(length: 1_000),
            userMessage("second"),
            reasoningWithEncryptedContent(length: 2_000)
        ])

        XCTAssertEqual(history.nonLastReasoningItemsTokens(), 32)
    }

    func testItemsAfterLastModelGeneratedItemIncludeUserAndToolOutputLikeRust() {
        let addedUser = userMessage("new user message")
        let addedToolOutput = customToolCallOutput(callID: "call-tail", output: "new tool output")
        let history = ContextManager(items: [
            assistantMessage("already counted by API"),
            addedUser,
            addedToolOutput
        ])

        XCTAssertEqual(history.itemsAfterLastModelGeneratedItem(), [addedUser, addedToolOutput])
        XCTAssertEqual(
            history.itemsAfterLastModelGeneratedItem().reduce(Int64(0)) {
                $0 + ContextManager.estimateItemTokenCount($1)
            },
            ContextManager.estimateItemTokenCount(addedUser)
                + ContextManager.estimateItemTokenCount(addedToolOutput)
        )
    }

    func testItemsAfterLastModelGeneratedItemAreEmptyWithoutModelGeneratedItemsLikeRust() {
        let history = ContextManager(items: [
            userMessage("no model output yet")
        ])

        XCTAssertEqual(history.itemsAfterLastModelGeneratedItem(), [])
    }

    func testInterAgentAssistantMessagesAreTurnBoundariesLikeRust() throws {
        XCTAssertTrue(ContextManager.isUserTurnBoundary(try interAgentAssistantMessage("continue")))
        XCTAssertFalse(ContextManager.isUserTurnBoundary(assistantMessage("plain assistant")))
    }

    func testForPromptPreservesInterAgentAssistantMessagesLikeRust() throws {
        let item = try interAgentAssistantMessage("continue")
        let history = ContextManager(items: [item])

        XCTAssertEqual(history.rawItems, [item])
        XCTAssertEqual(history.forPrompt(), [item])
    }

    func testCodexGeneratedItemClassifierMatchesRust() {
        XCTAssertTrue(ContextManager.isCodexGeneratedItem(developerMessage("developer note")))
        XCTAssertTrue(ContextManager.isCodexGeneratedItem(
            .functionCallOutput(callID: "call-1", output: FunctionCallOutputPayload(content: "ok"))
        ))
        XCTAssertTrue(ContextManager.isCodexGeneratedItem(
            .customToolCallOutput(callID: "tool-1", output: "ok")
        ))
        XCTAssertTrue(ContextManager.isCodexGeneratedItem(
            .toolSearchOutput(callID: "search-1", status: "completed", execution: "client", tools: [])
        ))

        XCTAssertFalse(ContextManager.isCodexGeneratedItem(assistantMessage("assistant response")))
        XCTAssertFalse(ContextManager.isCodexGeneratedItem(userMessage("user input")))
        XCTAssertFalse(ContextManager.isCodexGeneratedItem(functionCall(callID: "call-2")))
        XCTAssertFalse(ContextManager.isCodexGeneratedItem(customToolCall(callID: "tool-2")))
    }

    func testDropLastUserTurnsPreservesPrefixLikeRust() {
        var history = ContextManager(items: [
            assistantMessage("session prefix item"),
            userMessage("u1"),
            assistantMessage("a1"),
            userMessage("u2"),
            assistantMessage("a2")
        ])

        history.dropLastUserTurns(count: 1)
        XCTAssertEqual(history.forPrompt(), [
            assistantMessage("session prefix item"),
            userMessage("u1"),
            assistantMessage("a1")
        ])

        history = ContextManager(items: [
            assistantMessage("session prefix item"),
            userMessage("u1"),
            assistantMessage("a1"),
            userMessage("u2"),
            assistantMessage("a2")
        ])

        history.dropLastUserTurns(count: 99)
        XCTAssertEqual(history.forPrompt(), [
            assistantMessage("session prefix item")
        ])
    }

    func testDropLastUserTurnsIgnoresContextualUserMessagesLikeRust() {
        let prefixItems = [
            userMessage("<environment_context>ctx</environment_context>"),
            userMessage("# AGENTS.md instructions for test_directory\n\n<INSTRUCTIONS>\ntest_text\n</INSTRUCTIONS>"),
            userMessage("<skill>\n<name>demo</name>\n<path>skills/demo/SKILL.md</path>\nbody\n</skill>"),
            userMessage("<user_shell_command>echo 42</user_shell_command>"),
            userMessage("<SUBAGENT_NOTIFICATION>{\"agent_id\":\"a\",\"status\":\"completed\"}</subagent_notification>"),
            userMessage("<turn_aborted>interrupted</turn_aborted>")
        ]
        let firstTurn = [
            userMessage("turn 1 user"),
            assistantMessage("turn 1 assistant")
        ]
        let secondTurn = [
            userMessage("turn 2 user"),
            assistantMessage("turn 2 assistant")
        ]

        var history = ContextManager(items: prefixItems + firstTurn + secondTurn)
        history.dropLastUserTurns(count: 1)
        XCTAssertEqual(history.forPrompt(), prefixItems + firstTurn)

        history = ContextManager(items: prefixItems + firstTurn + secondTurn)
        history.dropLastUserTurns(count: 3)
        XCTAssertEqual(history.forPrompt(), prefixItems)
    }

    func testDropLastUserTurnsTrimsContextUpdatesAboveRolledBackTurnLikeRust() {
        let reference = referenceContextItem()
        var history = ContextManager(items: [
            assistantMessage("session prefix item"),
            userMessage("turn 1 user"),
            assistantMessage("turn 1 assistant"),
            developerMessage("Generated images are saved to /tmp as /tmp/image-1.png by default."),
            developerMessage("<collaboration_mode>ROLLED_BACK_DEV_INSTRUCTIONS</collaboration_mode>"),
            userMessage("<environment_context><cwd>PRETURN_CONTEXT_DIFF_CWD</cwd></environment_context>"),
            userMessage("turn 2 user"),
            assistantMessage("turn 2 assistant")
        ])
        history.setReferenceContextItem(reference)

        history.dropLastUserTurns(count: 1)

        XCTAssertEqual(history.forPrompt(), [
            assistantMessage("session prefix item"),
            userMessage("turn 1 user"),
            assistantMessage("turn 1 assistant"),
            developerMessage("Generated images are saved to /tmp as /tmp/image-1.png by default.")
        ])
        XCTAssertEqual(history.currentReferenceContextItem(), reference)
    }

    func testDropLastUserTurnsClearsReferenceContextForMixedDeveloperContextBundlesLikeRust() {
        var history = ContextManager(items: [
            userMessage("turn 1 user"),
            assistantMessage("turn 1 assistant"),
            developerMessage([
                "<permissions instructions>contextual permissions</permissions instructions>",
                "persistent plugin instructions"
            ]),
            userMessage("<environment_context><cwd>PRETURN_CONTEXT_DIFF_CWD</cwd></environment_context>"),
            userMessage("turn 2 user"),
            assistantMessage("turn 2 assistant")
        ])
        history.setReferenceContextItem(referenceContextItem())

        history.dropLastUserTurns(count: 1)

        XCTAssertEqual(history.forPrompt(), [
            userMessage("turn 1 user"),
            assistantMessage("turn 1 assistant")
        ])
        XCTAssertNil(history.currentReferenceContextItem())
    }

    func testTotalTokenUsageIncludesItemsAfterLastModelGeneratedItemLikeRust() {
        var history = ContextManager(items: [
            assistantMessage("already counted by API")
        ])
        history.updateTokenInfo(
            usage: TokenUsage(totalTokens: 100),
            modelContextWindow: nil
        )
        let addedUser = userMessage("new user message")
        let addedToolOutput = customToolCallOutput(callID: "tool-tail", output: "new tool output")

        history.recordItems([addedUser, addedToolOutput], policy: .tokens(10_000))

        XCTAssertEqual(
            history.totalTokenUsage(serverReasoningIncluded: true),
            100
                + ContextManager.estimateItemTokenCount(addedUser)
                + ContextManager.estimateItemTokenCount(addedToolOutput)
        )
    }

    func testTotalTokenUsageAddsNonLastReasoningWhenServerDidNotIncludeItLikeRust() {
        var history = ContextManager(items: [
            reasoningWithEncryptedContent(length: 1_000),
            userMessage("first"),
            assistantMessage("already counted by API"),
            userMessage("tail")
        ])
        history.updateTokenInfo(
            usage: TokenUsage(totalTokens: 100),
            modelContextWindow: nil
        )

        let tailTokens = ContextManager.estimateItemTokenCount(userMessage("tail"))
        XCTAssertEqual(
            history.totalTokenUsage(serverReasoningIncluded: false),
            100 + 25 + tailTokens
        )
        XCTAssertEqual(
            history.totalTokenUsage(serverReasoningIncluded: true),
            100 + tailTokens
        )
    }

    func testTotalTokenUsageBreakdownMatchesRustFields() {
        var history = ContextManager(items: [
            assistantMessage("already counted by API")
        ])
        history.updateTokenInfo(
            usage: TokenUsage(totalTokens: 100),
            modelContextWindow: nil
        )
        let addedUser = userMessage("new user message")
        let addedToolOutput = customToolCallOutput(callID: "tool-tail", output: "new tool output")
        history.recordItems([addedUser, addedToolOutput], policy: .tokens(10_000))

        let breakdown = history.totalTokenUsageBreakdown()
        let tailItems = [addedUser, addedToolOutput]
        let allItems = [assistantMessage("already counted by API")] + tailItems
        let expectedTailBytes = tailItems.reduce(Int64(0)) {
            $0 + Int64(ContextTokenEstimator.estimateResponseItemModelVisibleBytes($1))
        }
        let expectedTailTokens = tailItems.reduce(Int64(0)) {
            $0 + ContextManager.estimateItemTokenCount($1)
        }
        let expectedAllBytes = allItems.reduce(Int64(0)) {
            $0 + Int64(ContextTokenEstimator.estimateResponseItemModelVisibleBytes($1))
        }

        XCTAssertEqual(breakdown.lastAPIResponseTotalTokens, 100)
        XCTAssertEqual(breakdown.allHistoryItemsModelVisibleBytes, expectedAllBytes)
        XCTAssertEqual(
            breakdown.estimatedTokensOfItemsAddedSinceLastSuccessfulAPIResponse,
            expectedTailTokens
        )
        XCTAssertEqual(
            breakdown.estimatedBytesOfItemsAddedSinceLastSuccessfulAPIResponse,
            expectedTailBytes
        )
    }

    func testEstimateTokenCountWithBaseInstructionsUsesProvidedTextLikeRust() {
        let history = ContextManager(items: [
            assistantMessage("hello from history")
        ])
        let shortBase = "short"
        let longBase = String(repeating: "x", count: 1_000)

        let shortEstimate = history.estimateTokenCount(baseInstructionsText: shortBase)
        let longEstimate = history.estimateTokenCount(baseInstructionsText: longBase)
        let expectedDelta = Int64(Truncation.approxTokenCount(longBase))
            - Int64(Truncation.approxTokenCount(shortBase))

        XCTAssertEqual(longEstimate - shortEstimate, expectedDelta)
    }

    func testRemoveFirstItemRemovesMatchingFunctionOutputLikeRust() {
        var history = ContextManager(items: [
            functionCall(callID: "call-1"),
            .functionCallOutput(callID: "call-1", output: FunctionCallOutputPayload(content: "ok"))
        ])

        history.removeFirstItem()

        XCTAssertEqual(history.rawItems, [])
        XCTAssertEqual(history.historyVersion, 0)
    }

    func testRemoveFirstItemRemovesMatchingFunctionCallForOutputLikeRust() {
        var history = ContextManager(items: [
            .functionCallOutput(callID: "call-2", output: FunctionCallOutputPayload(content: "ok")),
            functionCall(callID: "call-2")
        ])

        history.removeFirstItem()

        XCTAssertEqual(history.rawItems, [])
    }

    func testRemoveFirstItemHandlesLocalShellPairLikeRust() {
        var history = ContextManager(items: [
            localShellCall(callID: "call-3"),
            .functionCallOutput(callID: "call-3", output: FunctionCallOutputPayload(content: "ok"))
        ])

        history.removeFirstItem()

        XCTAssertEqual(history.rawItems, [])
    }

    func testRemoveFirstItemHandlesCustomToolPairLikeRust() {
        var history = ContextManager(items: [
            customToolCall(callID: "tool-1"),
            .customToolCallOutput(callID: "tool-1", output: "ok")
        ])

        history.removeFirstItem()

        XCTAssertEqual(history.rawItems, [])
    }

    func testRemoveLastItemRemovesMatchingFunctionCallForOutputLikeRust() {
        var history = ContextManager(items: [
            userMessage("before tool call"),
            functionCall(callID: "call-delete-last"),
            .functionCallOutput(callID: "call-delete-last", output: FunctionCallOutputPayload(content: "ok"))
        ])

        XCTAssertTrue(history.removeLastItem())
        XCTAssertEqual(history.rawItems, [userMessage("before tool call")])
        XCTAssertEqual(history.historyVersion, 1)
    }

    func testRecordItemsDropsSystemAndOtherItemsAndTruncatesToolOutputsLikeRust() {
        var history = ContextManager()
        let longOutput = String(repeating: "tokenized content repeated many times ", count: 200)

        history.recordItems([
            .message(role: "system", content: [.inputText(text: "skip")]),
            .other,
            .functionCallOutput(callID: "call-1", output: FunctionCallOutputPayload(content: longOutput))
        ], policy: .tokens(4))

        XCTAssertEqual(history.rawItems.count, 1)
        guard case let .functionCallOutput(_, output) = history.rawItems[0] else {
            return XCTFail("expected function call output")
        }
        XCTAssertTrue(output.content.contains("tokens truncated"))
        XCTAssertLessThan(output.content.count, longOutput.count)
    }

    func testRecordItemsTruncatesCustomToolCallOutputContentLikeRust() {
        var history = ContextManager()
        let longOutput = String(repeating: "custom output that is very long\n", count: 2_500)

        history.recordItems([
            .customToolCallOutput(callID: "tool-200", output: longOutput)
        ], policy: .tokens(1_000))

        XCTAssertEqual(history.rawItems.count, 1)
        guard case let .customToolCallOutput(_, _, output) = history.rawItems[0] else {
            return XCTFail("expected custom tool call output")
        }
        XCTAssertNotEqual(output.content, longOutput)
        XCTAssertTrue(output.content.contains("tokens truncated"))
    }

    func testReplaceLastTurnImagesOnlyRewritesLatestToolOutputLikeRust() {
        var history = ContextManager(items: [
            .functionCallOutput(
                callID: "old",
                output: FunctionCallOutputPayload(content: "old", contentItems: [
                    .inputImage(imageURL: "data:image/png;base64,AAAA")
                ])
            ),
            userMessage("after old"),
            .functionCallOutput(
                callID: "latest",
                output: FunctionCallOutputPayload(content: "latest", contentItems: [
                    .inputText(text: "before"),
                    .inputImage(imageURL: "data:image/png;base64,BBBB")
                ])
            )
        ])

        XCTAssertTrue(history.replaceLastTurnImages(placeholder: "Invalid image"))
        XCTAssertEqual(history.historyVersion, 1)
        XCTAssertEqual(
            history.rawItems[2],
            .functionCallOutput(
                callID: "latest",
                output: FunctionCallOutputPayload(content: "latest", contentItems: [
                    .inputText(text: "before"),
                    .inputText(text: "Invalid image")
                ])
            )
        )
    }

    func testReplaceLastTurnImagesDoesNotTouchUserImagesLikeRust() {
        let items = [
            ResponseItem.message(role: "user", content: [
                .inputImage(imageURL: "data:image/png;base64,AAAA")
            ])
        ]
        var history = ContextManager(items: items)

        XCTAssertFalse(history.replaceLastTurnImages(placeholder: "Invalid image"))
        XCTAssertEqual(history.rawItems, items)
        XCTAssertEqual(history.historyVersion, 0)
    }

    func testForPromptRetainsLocalShellOutputsLikeRust() {
        let items: [ResponseItem] = [
            localShellCall(callID: "shell-1"),
            .functionCallOutput(
                callID: "shell-1",
                output: FunctionCallOutputPayload(content: "Total output lines: 1\n\nok")
            )
        ]
        let history = ContextManager(items: items)

        XCTAssertEqual(history.forPrompt(), items)
    }
}

private func reasoningWithEncryptedContent(length: Int) -> ResponseItem {
    .reasoning(
        id: "rs-\(length)",
        summary: [],
        encryptedContent: String(repeating: "A", count: length)
    )
}

private func userMessage(_ text: String) -> ResponseItem {
    .message(role: "user", content: [.inputText(text: text)])
}

private func assistantMessage(_ text: String) -> ResponseItem {
    .message(role: "assistant", content: [.outputText(text: text)])
}

private func developerMessage(_ text: String) -> ResponseItem {
    developerMessage([text])
}

private func developerMessage(_ texts: [String]) -> ResponseItem {
    .message(role: "developer", content: texts.map { .inputText(text: $0) })
}

private func customToolCallOutput(callID: String, output: String) -> ResponseItem {
    .customToolCallOutput(callID: callID, output: output)
}

private func functionCall(callID: String) -> ResponseItem {
    .functionCall(name: "do_it", arguments: "{}", callID: callID)
}

private func customToolCall(callID: String) -> ResponseItem {
    .customToolCall(callID: callID, name: "my_tool", input: "{}")
}

private func localShellCall(callID: String) -> ResponseItem {
    .localShellCall(
        callID: callID,
        status: .completed,
        action: .exec(LocalShellExecAction(command: ["echo", "hi"]))
    )
}

private func interAgentAssistantMessage(_ text: String) throws -> ResponseItem {
    try InterAgentCommunication(
        author: .root,
        recipient: AgentPath.root.join("worker"),
        content: text,
        triggerTurn: true
    ).toResponseInputItem().responseItem()
}

private func referenceContextItem() -> TurnContextItem {
    TurnContextItem(
        turnID: "reference-turn",
        cwd: "/tmp/reference-cwd",
        currentDate: "2026-03-23",
        timezone: "America/Los_Angeles",
        approvalPolicy: .onRequest,
        sandboxPolicy: .readOnly,
        model: "gpt-test",
        realtimeActive: false,
        summary: .auto,
        truncationPolicy: .tokens(10_000)
    )
}
