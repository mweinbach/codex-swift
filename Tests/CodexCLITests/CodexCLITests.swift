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

    func testRunAsyncCompletionDefaultsToBash() async {
        var stdout: [String] = []
        var stderr: [String] = []

        let exitCode = await CodexCLI().runAsync(
            arguments: ["completion"],
            stdout: { stdout.append($0) },
            stderr: { stderr.append($0) }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(stderr.isEmpty)
        XCTAssertEqual(stdout.count, 1)
        XCTAssertTrue(stdout[0].contains("_codex()"))
        XCTAssertTrue(stdout[0].contains("complete -F _codex codex"))
        XCTAssertTrue(stdout[0].contains("exec e computer-use cu review"))
        XCTAssertFalse(stdout[0].contains("execpolicy"))
    }

    func testRunAsyncCompletionSupportsRustShellNames() async {
        for shell in ["elvish", "fish", "powershell", "zsh"] {
            var stdout: [String] = []
            var stderr: [String] = []

            let exitCode = await CodexCLI().runAsync(
                arguments: ["completion", shell],
                stdout: { stdout.append($0) },
                stderr: { stderr.append($0) }
            )

            XCTAssertEqual(exitCode, 0, shell)
            XCTAssertTrue(stderr.isEmpty, shell)
            XCTAssertEqual(stdout.count, 1, shell)
            XCTAssertTrue(stdout[0].contains("codex"), shell)
            XCTAssertTrue(stdout[0].contains("exec"), shell)
            XCTAssertFalse(stdout[0].contains("responses-api-proxy"), shell)
        }
    }

    func testRunAsyncCompletionRejectsUnknownShell() async {
        var stderr: [String] = []

        let exitCode = await CodexCLI().runAsync(
            arguments: ["completion", "tcsh"],
            stdout: { _ in XCTFail("stdout should not be written") },
            stderr: { stderr.append($0) }
        )

        XCTAssertEqual(exitCode, 64)
        XCTAssertEqual(stderr, ["unsupported completion shell: tcsh"])
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

    func testRunAsyncLoginStatusDelegatesToRunnerAndPrintsStatus() async {
        var stdout: [String] = []
        var stderr: [String] = []
        var receivedRequest: CodexCLI.LoginCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["-c", "cli_auth_credentials_store=\"file\"", "login", "status"],
            stdout: { stdout.append($0) },
            stderr: { stderr.append($0) },
            loginRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(
                    exitCode: 0,
                    stderrMessage: "Logged in using an API key - sk-test1***abcde"
                )
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(stdout.isEmpty)
        XCTAssertEqual(stderr, ["Logged in using an API key - sk-test1***abcde"])
        XCTAssertEqual(receivedRequest?.action, .status)
        XCTAssertEqual(receivedRequest?.configOverrides.rawOverrides, ["cli_auth_credentials_store=\"file\""])
    }

    func testRunAsyncLoginWithAPIKeyDelegatesToRunner() async {
        var stdout: [String] = []
        var stderr: [String] = []
        var receivedRequest: CodexCLI.LoginCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["login", "--with-api-key"],
            stdout: { stdout.append($0) },
            stderr: { stderr.append($0) },
            loginRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0, stderrMessage: "Successfully logged in")
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(stdout.isEmpty)
        XCTAssertEqual(stderr, ["Successfully logged in"])
        XCTAssertEqual(receivedRequest?.action, .withAPIKeyFromStdin)
    }

    func testRunAsyncLoginDefaultAndDeviceAuthActionsDelegateToRunner() async {
        var receivedActions: [CodexCLI.LoginCommandAction] = []

        let defaultExitCode = await CodexCLI().runAsync(
            arguments: ["login"],
            stderr: { _ in },
            loginRunner: { request in
                receivedActions.append(request.action)
                return CodexCLI.CommandExecutionResult(exitCode: 78)
            }
        )
        let deviceExitCode = await CodexCLI().runAsync(
            arguments: [
                "login",
                "--device-auth",
                "--experimental_issuer",
                "https://issuer.example",
                "--experimental_client-id=client-123"
            ],
            stderr: { _ in },
            loginRunner: { request in
                receivedActions.append(request.action)
                return CodexCLI.CommandExecutionResult(exitCode: 78)
            }
        )

        XCTAssertEqual(defaultExitCode, 78)
        XCTAssertEqual(deviceExitCode, 78)
        XCTAssertEqual(receivedActions, [
            .chatGPT,
            .deviceCode(issuerBaseURL: "https://issuer.example", clientID: "client-123")
        ])
    }

    func testRunAsyncLoginRejectsDeprecatedAPIKeyFlagBeforeRunner() async {
        let message = "The --api-key flag is no longer supported. Pipe the key instead, e.g. `printenv OPENAI_API_KEY | codex login --with-api-key`."

        for arguments in [["login", "--api-key"], ["login", "--api-key=sk-test"]] {
            var stderr: [String] = []
            let exitCode = await CodexCLI().runAsync(
                arguments: arguments,
                stdout: { _ in XCTFail("stdout should not be written") },
                stderr: { stderr.append($0) },
                loginRunner: { _ in
                    XCTFail("runner should not be called for deprecated --api-key")
                    return CodexCLI.CommandExecutionResult(exitCode: 0)
                }
            )

            XCTAssertEqual(exitCode, 1)
            XCTAssertEqual(stderr, [message])
        }

        var stderrWithoutRunner: [String] = []
        let exitCodeWithoutRunner = await CodexCLI().runAsync(
            arguments: ["login", "--api-key"],
            stdout: { _ in XCTFail("stdout should not be written") },
            stderr: { stderrWithoutRunner.append($0) }
        )

        XCTAssertEqual(exitCodeWithoutRunner, 1)
        XCTAssertEqual(stderrWithoutRunner, [message])
    }

    func testRunAsyncLogoutDelegatesToRunnerAndPrintsStatus() async {
        var stdout: [String] = []
        var stderr: [String] = []
        var receivedRequest: CodexCLI.LogoutCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["-c", "cli_auth_credentials_store=\"file\"", "logout"],
            stdout: { stdout.append($0) },
            stderr: { stderr.append($0) },
            logoutRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0, stderrMessage: "Successfully logged out")
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(stdout.isEmpty)
        XCTAssertEqual(stderr, ["Successfully logged out"])
        XCTAssertEqual(receivedRequest?.configOverrides.rawOverrides, ["cli_auth_credentials_store=\"file\""])
    }

    func testRunAsyncFeaturesListDelegatesToRunnerAndPrintsOutput() async {
        var stdout: [String] = []
        var stderr: [String] = []
        var receivedRequest: CodexCLI.FeaturesCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: [
                "-c",
                "features.web_search_request=true",
                "--enable",
                "skills",
                "--disable=parallel",
                "features",
                "list"
            ],
            stdout: { stdout.append($0) },
            stderr: { stderr.append($0) },
            featuresRunner: { request in
                receivedRequest = request
                return "web_search_request\tstable\ttrue"
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(stdout, ["web_search_request\tstable\ttrue"])
        XCTAssertTrue(stderr.isEmpty)
        XCTAssertEqual(receivedRequest?.configOverrides.rawOverrides, [
            "features.web_search_request=true",
            "features.skills=true",
            "features.parallel=false"
        ])
    }

    func testRunAsyncReportsUnknownFeatureToggleBeforeRunner() async {
        var stderr: [String] = []

        let exitCode = await CodexCLI().runAsync(
            arguments: ["--enable", "not_real", "features", "list"],
            stdout: { _ in XCTFail("stdout should not be written") },
            stderr: { stderr.append($0) },
            featuresRunner: { _ in
                XCTFail("runner should not be called when feature toggle validation fails")
                return ""
            }
        )

        XCTAssertEqual(exitCode, 1)
        XCTAssertEqual(stderr, ["Unknown feature flag: not_real"])
    }

    func testRunAsyncFeaturesListRequiresListSubcommand() async {
        var stderr: [String] = []

        let exitCode = await CodexCLI().runAsync(
            arguments: ["features"],
            stdout: { _ in XCTFail("stdout should not be written") },
            stderr: { stderr.append($0) },
            featuresRunner: { _ in
                XCTFail("runner should not be called without list subcommand")
                return ""
            }
        )

        XCTAssertEqual(exitCode, 64)
        XCTAssertEqual(stderr, ["codex-swift: missing required subcommand for command 'features': list"])
    }

    func testRunAsyncStdioToUDSDelegatesToRunner() async {
        var stderr: [String] = []
        var receivedRequest: CodexCLI.StdioToUDSCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["stdio-to-uds", "/tmp/codex.sock"],
            stdout: { _ in XCTFail("stdout should not be written") },
            stderr: { stderr.append($0) },
            stdioToUDSRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(stderr.isEmpty)
        XCTAssertEqual(receivedRequest?.socketPath, "/tmp/codex.sock")
    }

    func testRunAsyncStdioToUDSRequiresSocketPath() async {
        var stderr: [String] = []

        let exitCode = await CodexCLI().runAsync(
            arguments: ["stdio-to-uds"],
            stdout: { _ in XCTFail("stdout should not be written") },
            stderr: { stderr.append($0) },
            stdioToUDSRunner: { _ in
                XCTFail("runner should not be called without socket path")
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 64)
        XCTAssertEqual(stderr, ["codex-swift: missing required argument for command 'stdio-to-uds': <SOCKET_PATH>"])
    }

    func testRunAsyncCloudStatusDelegatesToRunnerAndPrintsOutput() async {
        var stdout: [String] = []
        var stderr: [String] = []
        var receivedRequest: CodexCLI.CloudCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["-c", "chatgpt_base_url=\"https://example.test\"", "cloud", "status", "https://chatgpt.com/codex/tasks/task_123?x=1"],
            stdout: { stdout.append($0) },
            stderr: { stderr.append($0) },
            cloudRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0, stdoutMessage: "[READY] task")
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(stdout, ["[READY] task"])
        XCTAssertTrue(stderr.isEmpty)
        XCTAssertEqual(receivedRequest?.action, .status(taskID: "https://chatgpt.com/codex/tasks/task_123?x=1"))
        XCTAssertEqual(receivedRequest?.configOverrides.rawOverrides, ["chatgpt_base_url=\"https://example.test\""])
    }

    func testRunAsyncCloudStatusRejectsUnsupportedOptionBeforeRunner() async {
        var stderr: [String] = []

        let exitCode = await CodexCLI().runAsync(
            arguments: ["cloud", "status", "--attempt", "2", "task_123"],
            stdout: { _ in XCTFail("stdout should not be written") },
            stderr: { stderr.append($0) },
            cloudRunner: { _ in
                XCTFail("runner should not be called with invalid status options")
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 64)
        XCTAssertEqual(stderr, ["codex-swift: unsupported option for command 'cloud status': --attempt"])
    }

    func testRunAsyncCloudDiffParsesAttemptFlag() async {
        var stdout: [String] = []
        var receivedRequest: CodexCLI.CloudCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["cloud", "diff", "--attempt=2", "task_123"],
            stdout: { stdout.append($0) },
            stderr: { _ in XCTFail("stderr should not be written") },
            cloudRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0, stdoutMessage: "diff --git\n")
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(stdout, ["diff --git\n"])
        XCTAssertEqual(receivedRequest?.action, .diff(taskID: "task_123", attempt: 2))
    }

    func testRunAsyncCloudApplyParsesSeparateAttemptFlag() async {
        var stdout: [String] = []
        var receivedRequest: CodexCLI.CloudCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["cloud", "apply", "task_123", "--attempt", "3"],
            stdout: { stdout.append($0) },
            stderr: { _ in },
            cloudRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0, stdoutMessage: "Applied task task_123 locally (1 files)")
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(stdout, ["Applied task task_123 locally (1 files)"])
        XCTAssertEqual(receivedRequest?.action, .apply(taskID: "task_123", attempt: 3))
    }

    func testRunAsyncCloudRejectsInvalidAttemptBeforeRunner() async {
        var stderr: [String] = []

        let exitCode = await CodexCLI().runAsync(
            arguments: ["cloud", "diff", "--attempt", "5", "task_123"],
            stdout: { _ in XCTFail("stdout should not be written") },
            stderr: { stderr.append($0) },
            cloudRunner: { _ in
                XCTFail("runner should not be called with invalid attempt")
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 64)
        XCTAssertEqual(stderr, ["attempts must be between 1 and 4"])
    }

    func testRunAsyncCloudExecParsesEnvAttemptsBranchAndQuery() async {
        var stdout: [String] = []
        var receivedRequest: CodexCLI.CloudCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: [
                "-c",
                "chatgpt_base_url=\"https://example.test\"",
                "cloud",
                "exec",
                "--env",
                "Env A",
                "--attempts=3",
                "--branch",
                "feature/x",
                "ship it"
            ],
            stdout: { stdout.append($0) },
            stderr: { _ in XCTFail("stderr should not be written") },
            cloudRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0, stdoutMessage: "https://chatgpt.com/codex/tasks/task_123")
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(stdout, ["https://chatgpt.com/codex/tasks/task_123"])
        XCTAssertEqual(
            receivedRequest?.action,
            .exec(query: "ship it", environment: "Env A", branch: "feature/x", attempts: 3)
        )
        XCTAssertEqual(receivedRequest?.configOverrides.rawOverrides, ["chatgpt_base_url=\"https://example.test\""])
    }

    func testRunAsyncCloudExecAllowsMissingQueryForStdinResolutionByRunner() async {
        var receivedRequest: CodexCLI.CloudCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["cloud", "exec", "--env=env_123"],
            stderr: { _ in XCTFail("stderr should not be written") },
            cloudRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(receivedRequest?.action, .exec(query: nil, environment: "env_123", branch: nil, attempts: 1))
    }

    func testRunAsyncCloudExecRequiresEnvAndRejectsInvalidAttemptsBeforeRunner() async {
        var missingEnvStderr: [String] = []
        let missingEnvExit = await CodexCLI().runAsync(
            arguments: ["cloud", "exec", "ship it"],
            stdout: { _ in XCTFail("stdout should not be written") },
            stderr: { missingEnvStderr.append($0) },
            cloudRunner: { _ in
                XCTFail("runner should not be called without env")
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )
        XCTAssertEqual(missingEnvExit, 64)
        XCTAssertEqual(missingEnvStderr, ["codex-swift: missing required option for command 'cloud exec': --env <ENV_ID>"])

        var invalidAttemptsStderr: [String] = []
        let invalidAttemptsExit = await CodexCLI().runAsync(
            arguments: ["cloud", "exec", "--env", "env_123", "--attempts", "0", "ship it"],
            stdout: { _ in XCTFail("stdout should not be written") },
            stderr: { invalidAttemptsStderr.append($0) },
            cloudRunner: { _ in
                XCTFail("runner should not be called with invalid attempts")
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )
        XCTAssertEqual(invalidAttemptsExit, 64)
        XCTAssertEqual(invalidAttemptsStderr, ["attempts must be between 1 and 4"])
    }

    func testRunAsyncCloudWithoutRunnerStillReportsUnimplemented() async {
        var stderr: [String] = []

        let exitCode = await CodexCLI().runAsync(
            arguments: ["cloud", "status", "task_123"],
            stdout: { _ in XCTFail("stdout should not be written") },
            stderr: { stderr.append($0) }
        )

        XCTAssertEqual(exitCode, 78)
        XCTAssertEqual(stderr, ["codex-swift: command 'cloud' is registered but its runtime port is not complete yet."])
    }
}
