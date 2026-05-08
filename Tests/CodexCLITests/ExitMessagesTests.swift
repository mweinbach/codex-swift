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
}
