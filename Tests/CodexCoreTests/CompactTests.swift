import XCTest
@testable import CodexCore

final class CompactTests: XCTestCase {
    func testBundledPromptResourcesMatchRustTemplates() {
        XCTAssertTrue(Compact.summarizationPrompt.hasPrefix("You are performing a CONTEXT CHECKPOINT COMPACTION."))
        XCTAssertTrue(Compact.summaryPrefix.hasPrefix("Another language model started to solve this problem"))
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

    private func messageText(_ item: ResponseItem) -> String {
        guard case let .message(_, role, content, _) = item, role == "user" else {
            XCTFail("expected user message, got \(item)")
            return ""
        }
        return Compact.contentItemsToText(content) ?? ""
    }
}
