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

private func customToolCallOutput(callID: String, output: String) -> ResponseItem {
    .customToolCallOutput(callID: callID, output: output)
}

private func interAgentAssistantMessage(_ text: String) throws -> ResponseItem {
    try InterAgentCommunication(
        author: .root,
        recipient: AgentPath.root.join("worker"),
        content: text,
        triggerTurn: true
    ).toResponseInputItem().responseItem()
}
