import CodexCLI
import CodexCore
import XCTest

final class ExitMessagesTests: XCTestCase {
    func testFormatExitMessagesSkipsZeroUsage() {
        let lines = ExitMessages.formatExitMessages(
            AppExitInfo(tokenUsage: TokenUsage(), conversationID: nil, updateAction: nil),
            colorEnabled: false
        )

        XCTAssertTrue(lines.isEmpty)
    }

    func testFormatExitMessagesIncludesResumeHintWhenUsageIsZeroLikeRust() throws {
        let exitInfo = AppExitInfo(
            tokenUsage: TokenUsage(),
            conversationID: try ConversationId(string: "123e4567-e89b-12d3-a456-426614174000")
        )

        let lines = ExitMessages.formatExitMessages(exitInfo, colorEnabled: false)

        XCTAssertEqual(lines, [
            "To continue this session, run codex resume 123e4567-e89b-12d3-a456-426614174000"
        ])
    }

    func testFormatExitMessagesIncludesResumeHintWithoutColor() throws {
        let exitInfo = AppExitInfo(
            tokenUsage: TokenUsage(outputTokens: 2, totalTokens: 2),
            conversationID: try ConversationId(string: "123e4567-e89b-12d3-a456-426614174000")
        )

        let lines = ExitMessages.formatExitMessages(exitInfo, colorEnabled: false)

        XCTAssertEqual(lines, [
            "Token usage: total=2 input=0 output=2",
            "To continue this session, run codex resume 123e4567-e89b-12d3-a456-426614174000"
        ])
    }

    func testFormatExitMessagesAppliesColorWhenEnabled() throws {
        let exitInfo = AppExitInfo(
            tokenUsage: TokenUsage(outputTokens: 2, totalTokens: 2),
            conversationID: try ConversationId(string: "123e4567-e89b-12d3-a456-426614174000")
        )

        let lines = ExitMessages.formatExitMessages(exitInfo, colorEnabled: true)

        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[1].contains("\u{1B}[36m"))
        XCTAssertTrue(lines[1].hasSuffix("\u{1B}[0m"))
    }

    func testResumeCommandPrefersNameOverIDLikeRust() throws {
        let command = ExitMessages.resumeCommand(
            threadName: "my-thread",
            conversationID: try ConversationId(string: "123e4567-e89b-12d3-a456-426614174000")
        )

        XCTAssertEqual(command, "codex resume my-thread")
    }

    func testResumeCommandQuotesThreadNameWhenNeededLikeRust() {
        XCTAssertEqual(
            ExitMessages.resumeCommand(threadName: "-starts-with-dash", conversationID: nil),
            "codex resume -- -starts-with-dash"
        )
        XCTAssertEqual(
            ExitMessages.resumeCommand(threadName: "two words", conversationID: nil),
            "codex resume 'two words'"
        )
        XCTAssertEqual(
            ExitMessages.resumeCommand(threadName: "quote'case", conversationID: nil),
            #"codex resume "quote'case""#
        )
        XCTAssertEqual(
            ExitMessages.resumeCommand(threadName: "price$tag'case", conversationID: nil),
            #"codex resume 'price$tag'"'case""#
        )
        XCTAssertEqual(
            ExitMessages.resumeCommand(threadName: "a,b", conversationID: nil),
            "codex resume 'a,b'"
        )
        XCTAssertEqual(
            ExitMessages.resumeCommand(threadName: #"slash\case"#, conversationID: nil),
            #"codex resume "slash\\case""#
        )
    }
}
