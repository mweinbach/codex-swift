import CodexCLI
import XCTest

final class CodexCLITests: XCTestCase {
    func testCommandRegistryMatchesRustTopLevelOrder() {
        XCTAssertEqual(CodexCommandRegistry.commands.map(\.name), [
            "exec",
            "computer-use",
            "review",
            "login",
            "logout",
            "mcp",
            "mcp-server",
            "app-server",
            "completion",
            "sandbox",
            "execpolicy",
            "apply",
            "resume",
            "cloud",
            "responses-api-proxy",
            "stdio-to-uds",
            "features"
        ])
    }

    func testAliasesResolveToCanonicalCommands() {
        XCTAssertEqual(CodexCommandRegistry.command(matching: "e")?.name, "exec")
        XCTAssertEqual(CodexCommandRegistry.command(matching: "cu")?.name, "computer-use")
        XCTAssertEqual(CodexCommandRegistry.command(matching: "debug")?.name, "sandbox")
        XCTAssertEqual(CodexCommandRegistry.command(matching: "a")?.name, "apply")
        XCTAssertEqual(CodexCommandRegistry.command(matching: "cloud-tasks")?.name, "cloud")
    }

    func testHelpShowsVisibleCommandsButNotHiddenCommands() {
        let help = CodexCLI().renderHelp()
        XCTAssertTrue(help.contains("exec [alias: e]"))
        XCTAssertTrue(help.contains("app-server"))
        XCTAssertFalse(help.contains("execpolicy"))
        XCTAssertFalse(help.contains("responses-api-proxy"))
    }

    func testVersionMatchesWorkspaceVersion() {
        XCTAssertEqual(CodexCLI().renderVersion(), "codex 0.0.0")
    }

    func testInvocationSkipsOptionValuesBeforeCommand() {
        XCTAssertEqual(
            CodexCLI().parseInvocation(arguments: ["--model", "gpt-5.4", "exec"]),
            .command(CommandSpec(name: "exec", aliases: ["e"], summary: "Run Codex non-interactively."), arguments: [])
        )
    }

    func testPromptWithoutSubcommandIsInteractiveInvocation() {
        XCTAssertEqual(CodexCLI().parseInvocation(arguments: ["hello codex"]), .interactive(prompt: "hello codex"))
    }

    func testApplyInvocationCarriesTaskIDArgument() {
        XCTAssertEqual(
            CodexCLI().parseInvocation(arguments: ["-c", "chatgpt_base_url=\"https://example.test\"", "apply", "task_123"]),
            .command(
                CommandSpec(name: "apply", aliases: ["a"], summary: "Apply the latest diff produced by Codex agent as a git apply to your local working tree."),
                arguments: ["task_123"]
            )
        )
    }

    func testRunAsyncApplyDelegatesToRunnerAndPrintsSuccessMessage() async {
        var stdout: [String] = []
        var stderr: [String] = []
        var receivedRequest: CodexCLI.ApplyCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["-c", "chatgpt_base_url=\"https://example.test\"", "apply", "task_123"],
            stdout: { stdout.append($0) },
            stderr: { stderr.append($0) },
            applyRunner: { request in
                receivedRequest = request
                return "Successfully applied diff"
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(stdout, ["Successfully applied diff"])
        XCTAssertTrue(stderr.isEmpty)
        XCTAssertEqual(receivedRequest?.taskID, "task_123")
        XCTAssertEqual(receivedRequest?.configOverrides.rawOverrides, ["chatgpt_base_url=\"https://example.test\""])
    }

    func testRunAsyncApplyRequiresTaskID() async {
        var stderr: [String] = []
        let exitCode = await CodexCLI().runAsync(
            arguments: ["apply"],
            stdout: { _ in XCTFail("stdout should not be written") },
            stderr: { stderr.append($0) },
            applyRunner: { _ in
                XCTFail("runner should not be called without task id")
                return nil
            }
        )

        XCTAssertEqual(exitCode, 64)
        XCTAssertEqual(stderr, ["codex-swift: missing required argument for command 'apply': <TASK_ID>"])
    }

    func testRunAsyncApplyReportsRunnerError() async {
        struct TestError: Error, CustomStringConvertible {
            let description = "apply failed"
        }

        var stderr: [String] = []
        let exitCode = await CodexCLI().runAsync(
            arguments: ["apply", "task_123"],
            stdout: { _ in XCTFail("stdout should not be written") },
            stderr: { stderr.append($0) },
            applyRunner: { _ in throw TestError() }
        )

        XCTAssertEqual(exitCode, 1)
        XCTAssertEqual(stderr, ["apply failed"])
    }
}
