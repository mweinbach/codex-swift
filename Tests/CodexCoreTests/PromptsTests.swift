import XCTest
@testable import CodexCore

final class PromptsTests: XCTestCase {
    func testComputerUsePromptLoadsBundledRustPrompt() {
        let prompt = CodexPrompts.computerUsePrompt

        XCTAssertTrue(prompt.hasPrefix("You are a computer-use agent running in the Computex CLI on Ubuntu."))
        XCTAssertTrue(prompt.contains("Before any GUI action, take a `computer_screenshot`."))
        XCTAssertTrue(prompt.contains("# AGENTS.md spec"))
    }
}
