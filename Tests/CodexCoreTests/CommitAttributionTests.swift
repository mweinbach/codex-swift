import CodexCore
import XCTest

final class CommitAttributionTests: XCTestCase {
    func testBlankAttributionDisablesTrailerPromptLikeRust() {
        XCTAssertNil(CommitAttribution.commitMessageTrailer(configAttribution: ""))
        XCTAssertNil(CommitAttribution.commitMessageTrailerInstruction(configAttribution: "   "))
    }

    func testDefaultAttributionUsesCodexTrailerLikeRust() {
        XCTAssertEqual(
            CommitAttribution.commitMessageTrailer(configAttribution: nil),
            "Co-authored-by: Codex <noreply@openai.com>"
        )
    }

    func testResolveValueHandlesDefaultCustomAndBlankLikeRust() {
        XCTAssertEqual(
            CommitAttribution.resolvedAttributionValue(configAttribution: nil),
            "Codex <noreply@openai.com>"
        )
        XCTAssertEqual(
            CommitAttribution.resolvedAttributionValue(configAttribution: "MyAgent <me@example.com>"),
            "MyAgent <me@example.com>"
        )
        XCTAssertEqual(
            CommitAttribution.resolvedAttributionValue(configAttribution: "MyAgent"),
            "MyAgent"
        )
        XCTAssertNil(CommitAttribution.resolvedAttributionValue(configAttribution: "   "))
    }

    func testInstructionMentionsTrailerAndOmitsGeneratedWithLikeRust() throws {
        let instruction = try XCTUnwrap(
            CommitAttribution.commitMessageTrailerInstruction(configAttribution: "AgentX <agent@example.com>")
        )
        XCTAssertTrue(instruction.contains("Co-authored-by: AgentX <agent@example.com>"))
        XCTAssertTrue(instruction.contains("exactly once"))
        XCTAssertFalse(instruction.contains("Generated-with"))
    }
}
