import CodexCore
import XCTest

final class CustomPromptTests: XCTestCase {
    func testPromptPrefixMatchesRustConstant() {
        XCTAssertEqual(CustomPromptConstants.promptsCommandPrefix, "prompts")
    }

    func testCustomPromptWireShape() throws {
        let prompt = CustomPrompt(
            name: "fix",
            path: "/tmp/SKILL.md",
            content: "do it",
            description: "Fix things",
            argumentHint: "file"
        )
        try XCTAssertJSONObjectEqual(prompt, [
            "name": "fix",
            "path": "/tmp/SKILL.md",
            "content": "do it",
            "description": "Fix things",
            "argument_hint": "file"
        ])
    }
}
