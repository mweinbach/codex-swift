import CodexCore
import XCTest

final class SlashCommandTests: XCTestCase {
    func testBuiltInCommandsPreserveRustPresentationOrder() {
        let commands = SlashCommand.builtInCommands(includeDebugCommands: true).map(\.0)
        XCTAssertEqual(commands, [
            "model",
            "approvals",
            "experimental",
            "skills",
            "review",
            "new",
            "resume",
            "init",
            "compact",
            "diff",
            "mention",
            "status",
            "mcp",
            "logout",
            "quit",
            "exit",
            "feedback",
            "rollout",
            "ps",
            "test-approval"
        ])
    }

    func testDebugCommandsAreHiddenWhenRequested() {
        let commands = SlashCommand.builtInCommands(includeDebugCommands: false).map(\.0)
        XCTAssertFalse(commands.contains("rollout"))
        XCTAssertFalse(commands.contains("test-approval"))
    }

    func testAvailabilityDuringTaskMatchesRustLogic() {
        XCTAssertFalse(SlashCommand.model.availableDuringTask)
        XCTAssertFalse(SlashCommand.review.availableDuringTask)
        XCTAssertTrue(SlashCommand.diff.availableDuringTask)
        XCTAssertTrue(SlashCommand.quit.availableDuringTask)
    }
}
