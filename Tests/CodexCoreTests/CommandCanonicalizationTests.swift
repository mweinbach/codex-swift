import XCTest
import CodexCore

final class CommandCanonicalizationTests: XCTestCase {
    func testCanonicalizesWordOnlyShellScriptsToInnerCommandLikeRust() {
        let commandA = ["/bin/bash", "-lc", "cargo test -p codex-core"]
        let commandB = ["bash", "-lc", "cargo   test   -p codex-core"]

        XCTAssertEqual(
            CommandCanonicalization.canonicalizeCommandForApproval(commandA),
            ["cargo", "test", "-p", "codex-core"]
        )
        XCTAssertEqual(
            CommandCanonicalization.canonicalizeCommandForApproval(commandA),
            CommandCanonicalization.canonicalizeCommandForApproval(commandB)
        )
    }

    func testCanonicalizesHeredocScriptsToStableScriptKeyLikeRust() {
        let script = "python3 <<'PY'\nprint('hello')\nPY"
        let commandA = ["/bin/zsh", "-lc", script]
        let commandB = ["zsh", "-lc", script]

        XCTAssertEqual(
            CommandCanonicalization.canonicalizeCommandForApproval(commandA),
            ["__codex_shell_script__", "-lc", script]
        )
        XCTAssertEqual(
            CommandCanonicalization.canonicalizeCommandForApproval(commandA),
            CommandCanonicalization.canonicalizeCommandForApproval(commandB)
        )
    }

    func testCanonicalizesPowerShellWrappersToStableScriptKeyLikeRust() {
        let script = "Write-Host hi"
        let commandA = ["powershell.exe", "-NoProfile", "-Command", script]
        let commandB = ["powershell", "-Command", script]

        XCTAssertEqual(
            CommandCanonicalization.canonicalizeCommandForApproval(commandA),
            ["__codex_powershell_script__", script]
        )
        XCTAssertEqual(
            CommandCanonicalization.canonicalizeCommandForApproval(commandA),
            CommandCanonicalization.canonicalizeCommandForApproval(commandB)
        )
    }

    func testPreservesNonShellCommandsLikeRust() {
        let command = ["cargo", "fmt"]
        XCTAssertEqual(CommandCanonicalization.canonicalizeCommandForApproval(command), command)
    }
}
