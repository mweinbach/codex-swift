import CodexCLI
import CodexCore
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
            "plugin",
            "mcp-server",
            "app-server",
            "remote-control",
            "app",
            "completion",
            "update",
            "doctor",
            "sandbox",
            "debug",
            "execpolicy",
            "apply",
            "resume",
            "fork",
            "cloud",
            "responses-api-proxy",
            "stdio-to-uds",
            "exec-server",
            "features"
        ])
    }

    func testAliasesResolveToCanonicalCommands() {
        XCTAssertEqual(CodexCommandRegistry.command(matching: "e")?.name, "exec")
        XCTAssertEqual(CodexCommandRegistry.command(matching: "cu")?.name, "computer-use")
        XCTAssertEqual(CodexCommandRegistry.command(matching: "debug")?.name, "debug")
        XCTAssertEqual(CodexCommandRegistry.command(matching: "a")?.name, "apply")
        XCTAssertEqual(CodexCommandRegistry.command(matching: "cloud-tasks")?.name, "cloud")
    }

    func testHelpShowsVisibleCommandsButNotHiddenCommands() {
        let help = CodexCLI().renderHelp()
        XCTAssertTrue(help.contains("exec            Run Codex non-interactively [aliases: e]"))
        XCTAssertTrue(help.contains("app-server"))
        XCTAssertTrue(help.contains("exec-server"))
        XCTAssertTrue(help.contains("help            Print this message or the help of the given subcommand(s)"))
        XCTAssertFalse(help.contains("--full-auto"))
        XCTAssertFalse(help.contains("computer-use"))
        XCTAssertFalse(help.contains("execpolicy"))
        XCTAssertFalse(help.contains("responses-api-proxy"))
    }

    func testVersionMatchesWorkspaceVersion() {
        XCTAssertEqual(CodexCLI().renderVersion(), "codex \(CodexBuildMetadata.version)")
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
        XCTAssertTrue(stdout[0].contains("exec e review"))
        XCTAssertFalse(stdout[0].contains("computer-use"))
        XCTAssertTrue(stdout[0].contains("update doctor sandbox"))
        XCTAssertFalse(stdout[0].contains("--full-auto"))
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
            XCTAssertFalse(stdout[0].contains("full-auto"), shell)
            XCTAssertFalse(stdout[0].contains("responses-api-proxy"), shell)
        }
    }

    func testRunAsyncRejectsRemovedFullAutoAtTopLevelLikeRust() async {
        let cases = [
            ["--full-auto"],
            ["--full-auto", "exec", "summarize"],
            ["--model", "gpt-5.4", "--full-auto", "exec", "summarize"]
        ]

        for arguments in cases {
            var stderr: [String] = []
            let exitCode = await CodexCLI().runAsync(
                arguments: arguments,
                stdout: { _ in XCTFail("stdout should not be written for \(arguments)") },
                stderr: { stderr.append($0) },
                execRunner: { _ in
                    XCTFail("runner should not be called for \(arguments)")
                    return CodexCLI.CommandExecutionResult(exitCode: 0)
                }
            )

            XCTAssertEqual(exitCode, 64, "\(arguments)")
            XCTAssertEqual(stderr, ["codex-swift: unsupported option at top level: --full-auto"], "\(arguments)")
        }
    }

    func testRunAsyncRejectsRootInteractivePermissionConflictLikeRust() async {
        let cases: [([String], String)] = [
            (
                ["--dangerously-bypass-approvals-and-sandbox", "--ask-for-approval", "on-request"],
                "codex-swift: argument conflict: the argument '--ask-for-approval <APPROVAL_POLICY>' cannot be used with '--dangerously-bypass-approvals-and-sandbox'"
            ),
            (
                ["--ask-for-approval=on-request", "--yolo"],
                "codex-swift: argument conflict: the argument '--dangerously-bypass-approvals-and-sandbox' cannot be used with '--ask-for-approval <APPROVAL_POLICY>'"
            )
        ]

        for (arguments, expectedMessage) in cases {
            var stderr: [String] = []
            let exitCode = await CodexCLI().runAsync(
                arguments: arguments,
                stdout: { _ in XCTFail("stdout should not be written for \(arguments)") },
                stderr: { stderr.append($0) }
            )

            XCTAssertEqual(exitCode, 64, "\(arguments)")
            XCTAssertEqual(stderr, [expectedMessage], "\(arguments)")
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

    func testCommandHelpTargetsSubcommandLikeRust() async throws {
        XCTAssertEqual(
            CodexCLI().parseInvocation(arguments: ["exec", "--help"]),
            .commandHelp(CommandSpec(name: "exec", aliases: ["e"], summary: "Run Codex non-interactively."), arguments: ["--help"])
        )
        XCTAssertEqual(
            CodexCLI().parseInvocation(arguments: ["help", "exec"]),
            .commandHelp(CommandSpec(name: "exec", aliases: ["e"], summary: "Run Codex non-interactively."), arguments: [])
        )

        var stdout: [String] = []
        let exitCode = await CodexCLI().runAsync(
            arguments: ["exec", "--help"],
            stdout: { stdout.append($0) },
            stderr: { _ in XCTFail("stderr should not be written") }
        )

        XCTAssertEqual(exitCode, 0)
        let help = try XCTUnwrap(stdout.first)
        XCTAssertTrue(help.hasPrefix("Run Codex non-interactively\n\nUsage: codex exec [OPTIONS] [PROMPT]"))
        XCTAssertTrue(help.contains("  resume  Resume a previous session by id or pick the most recent with --last"))
        XCTAssertTrue(help.contains("      --output-schema <FILE>"))

        stdout.removeAll()
        let reviewExitCode = await CodexCLI().runAsync(
            arguments: ["review", "--help"],
            stdout: { stdout.append($0) },
            stderr: { _ in XCTFail("stderr should not be written") }
        )

        XCTAssertEqual(reviewExitCode, 0)
        let reviewHelp = try XCTUnwrap(stdout.first)
        XCTAssertTrue(reviewHelp.hasPrefix("Run a code review non-interactively\n\nUsage: codex review [OPTIONS] [PROMPT]"))
        XCTAssertTrue(reviewHelp.contains("      --uncommitted"))
        XCTAssertTrue(reviewHelp.contains("      --commit <SHA>"))

        stdout.removeAll()
        let completionExitCode = await CodexCLI().runAsync(
            arguments: ["completion", "--help"],
            stdout: { stdout.append($0) },
            stderr: { _ in XCTFail("stderr should not be written") }
        )

        XCTAssertEqual(completionExitCode, 0)
        let completionHelp = try XCTUnwrap(stdout.first)
        XCTAssertTrue(completionHelp.hasPrefix("Generate shell completion scripts\n\nUsage: codex completion [OPTIONS] [SHELL]"))
        XCTAssertTrue(completionHelp.contains("[possible values: bash, elvish, fish, powershell, zsh]"))

        stdout.removeAll()
        let loginExitCode = await CodexCLI().runAsync(
            arguments: ["login", "--help"],
            stdout: { stdout.append($0) },
            stderr: { _ in XCTFail("stderr should not be written") }
        )

        XCTAssertEqual(loginExitCode, 0)
        let loginHelp = try XCTUnwrap(stdout.first)
        XCTAssertTrue(loginHelp.hasPrefix("Manage login\n\nUsage: codex login [OPTIONS] [COMMAND]"))
        XCTAssertTrue(loginHelp.contains("  status  Show login status"))
        XCTAssertTrue(loginHelp.contains("      --with-access-token"))

        stdout.removeAll()
        let logoutExitCode = await CodexCLI().runAsync(
            arguments: ["logout", "--help"],
            stdout: { stdout.append($0) },
            stderr: { _ in XCTFail("stderr should not be written") }
        )

        XCTAssertEqual(logoutExitCode, 0)
        let logoutHelp = try XCTUnwrap(stdout.first)
        XCTAssertTrue(logoutHelp.hasPrefix("Remove stored authentication credentials\n\nUsage: codex logout [OPTIONS]"))
        XCTAssertTrue(logoutHelp.contains("      --disable <FEATURE>"))

        stdout.removeAll()
        let mcpExitCode = await CodexCLI().runAsync(
            arguments: ["mcp", "--help"],
            stdout: { stdout.append($0) },
            stderr: { _ in XCTFail("stderr should not be written") }
        )

        XCTAssertEqual(mcpExitCode, 0)
        let mcpHelp = try XCTUnwrap(stdout.first)
        XCTAssertTrue(mcpHelp.hasPrefix("Manage external MCP servers for Codex\n\nUsage: codex mcp [OPTIONS] <COMMAND>"))
        XCTAssertTrue(mcpHelp.contains("  remove"))

        stdout.removeAll()
        let pluginExitCode = await CodexCLI().runAsync(
            arguments: ["plugin", "--help"],
            stdout: { stdout.append($0) },
            stderr: { _ in XCTFail("stderr should not be written") }
        )

        XCTAssertEqual(pluginExitCode, 0)
        let pluginHelp = try XCTUnwrap(stdout.first)
        XCTAssertTrue(pluginHelp.hasPrefix("Manage Codex plugins\n\nUsage: codex plugin [OPTIONS] <COMMAND>"))
        XCTAssertTrue(pluginHelp.contains("  marketplace  Add, list, upgrade, or remove configured plugin marketplaces"))

        stdout.removeAll()
        let updateExitCode = await CodexCLI().runAsync(
            arguments: ["update", "--help"],
            stdout: { stdout.append($0) },
            stderr: { _ in XCTFail("stderr should not be written") }
        )

        XCTAssertEqual(updateExitCode, 0)
        let updateHelp = try XCTUnwrap(stdout.first)
        XCTAssertTrue(updateHelp.hasPrefix("Update Codex to the latest version\n\nUsage: codex update [OPTIONS]"))

        stdout.removeAll()
        let doctorExitCode = await CodexCLI().runAsync(
            arguments: ["doctor", "--help"],
            stdout: { stdout.append($0) },
            stderr: { _ in XCTFail("stderr should not be written") }
        )

        XCTAssertEqual(doctorExitCode, 0)
        let doctorHelp = try XCTUnwrap(stdout.first)
        XCTAssertTrue(doctorHelp.hasPrefix("Diagnose local Codex installation, config, auth, and runtime health\n\nUsage: codex doctor [OPTIONS]"))
        XCTAssertTrue(doctorHelp.contains("      --json"))
        XCTAssertTrue(doctorHelp.contains("      --ascii"))

        stdout.removeAll()
        let sandboxExitCode = await CodexCLI().runAsync(
            arguments: ["sandbox", "--help"],
            stdout: { stdout.append($0) },
            stderr: { _ in XCTFail("stderr should not be written") }
        )

        XCTAssertEqual(sandboxExitCode, 0)
        let sandboxHelp = try XCTUnwrap(stdout.first)
        XCTAssertTrue(sandboxHelp.hasPrefix("Run commands within a Codex-provided sandbox\n\nUsage: codex sandbox [OPTIONS] <COMMAND>"))
        XCTAssertTrue(sandboxHelp.contains("  windows  Run a command under Windows restricted token (Windows only)"))

        stdout.removeAll()
        let debugExitCode = await CodexCLI().runAsync(
            arguments: ["debug", "--help"],
            stdout: { stdout.append($0) },
            stderr: { _ in XCTFail("stderr should not be written") }
        )

        XCTAssertEqual(debugExitCode, 0)
        let debugHelp = try XCTUnwrap(stdout.first)
        XCTAssertTrue(debugHelp.hasPrefix("Debugging tools\n\nUsage: codex debug [OPTIONS] <COMMAND>"))
        XCTAssertTrue(debugHelp.contains("  prompt-input  Render the model-visible prompt input list as JSON"))

        stdout.removeAll()
        let applyExitCode = await CodexCLI().runAsync(
            arguments: ["apply", "--help"],
            stdout: { stdout.append($0) },
            stderr: { _ in XCTFail("stderr should not be written") }
        )

        XCTAssertEqual(applyExitCode, 0)
        let applyHelp = try XCTUnwrap(stdout.first)
        XCTAssertTrue(applyHelp.hasPrefix("Apply the latest diff produced by Codex agent as a `git apply` to your local working tree\n\nUsage: codex apply [OPTIONS] <TASK_ID>"))
        XCTAssertTrue(applyHelp.contains("Arguments:\n  <TASK_ID>"))

        stdout.removeAll()
        let appServerExitCode = await CodexCLI().runAsync(
            arguments: ["app-server", "--help"],
            stdout: { stdout.append($0) },
            stderr: { _ in XCTFail("stderr should not be written") }
        )

        XCTAssertEqual(appServerExitCode, 0)
        let appServerHelp = try XCTUnwrap(stdout.first)
        XCTAssertTrue(appServerHelp.hasPrefix("[experimental] Run the app server or related tooling\n\nUsage: codex app-server [OPTIONS] [COMMAND]"))
        XCTAssertTrue(appServerHelp.contains("  generate-json-schema  [experimental] Generate JSON Schema for the app server protocol"))
        XCTAssertTrue(appServerHelp.contains("      --ws-max-clock-skew-seconds <SECONDS>"))

        stdout.removeAll()
        let remoteControlExitCode = await CodexCLI().runAsync(
            arguments: ["remote-control", "--help"],
            stdout: { stdout.append($0) },
            stderr: { _ in XCTFail("stderr should not be written") }
        )

        XCTAssertEqual(remoteControlExitCode, 0)
        let remoteControlHelp = try XCTUnwrap(stdout.first)
        XCTAssertTrue(remoteControlHelp.hasPrefix("[experimental] Manage the app-server daemon with remote control enabled\n\nUsage: codex remote-control [OPTIONS] [COMMAND]"))
        XCTAssertTrue(remoteControlHelp.contains("  start  Start the app-server daemon with remote control enabled"))

        stdout.removeAll()
        let featuresExitCode = await CodexCLI().runAsync(
            arguments: ["features", "--help"],
            stdout: { stdout.append($0) },
            stderr: { _ in XCTFail("stderr should not be written") }
        )

        XCTAssertEqual(featuresExitCode, 0)
        let featuresHelp = try XCTUnwrap(stdout.first)
        XCTAssertTrue(featuresHelp.hasPrefix("Inspect feature flags\n\nUsage: codex features [OPTIONS] <COMMAND>"))
        XCTAssertTrue(featuresHelp.contains("  disable  Disable a feature in config.toml"))

        stdout.removeAll()
        let mcpServerExitCode = await CodexCLI().runAsync(
            arguments: ["mcp-server", "--help"],
            stdout: { stdout.append($0) },
            stderr: { _ in XCTFail("stderr should not be written") }
        )

        XCTAssertEqual(mcpServerExitCode, 0)
        let mcpServerHelp = try XCTUnwrap(stdout.first)
        XCTAssertTrue(mcpServerHelp.hasPrefix("Start Codex as an MCP server (stdio)\n\nUsage: codex mcp-server [OPTIONS]"))
        XCTAssertTrue(mcpServerHelp.contains("      --strict-config"))

        stdout.removeAll()
        let appExitCode = await CodexCLI().runAsync(
            arguments: ["app", "--help"],
            stdout: { stdout.append($0) },
            stderr: { _ in XCTFail("stderr should not be written") }
        )

        XCTAssertEqual(appExitCode, 0)
        let appHelp = try XCTUnwrap(stdout.first)
        XCTAssertTrue(appHelp.hasPrefix("Launch the Codex desktop app (opens the app installer if missing)\n\nUsage: codex app [OPTIONS] [PATH]"))
        XCTAssertTrue(appHelp.contains("      --download-url <DOWNLOAD_URL_OVERRIDE>"))

        stdout.removeAll()
        let execServerExitCode = await CodexCLI().runAsync(
            arguments: ["exec-server", "--help"],
            stdout: { stdout.append($0) },
            stderr: { _ in XCTFail("stderr should not be written") }
        )

        XCTAssertEqual(execServerExitCode, 0)
        let execServerHelp = try XCTUnwrap(stdout.first)
        XCTAssertTrue(execServerHelp.hasPrefix("[EXPERIMENTAL] Run the standalone exec-server service\n\nUsage: codex exec-server [OPTIONS]"))
        XCTAssertTrue(execServerHelp.contains("      --use-agent-identity-auth"))

        stdout.removeAll()
        let resumeExitCode = await CodexCLI().runAsync(
            arguments: ["resume", "--help"],
            stdout: { stdout.append($0) },
            stderr: { _ in XCTFail("stderr should not be written") }
        )

        XCTAssertEqual(resumeExitCode, 0)
        let resumeHelp = try XCTUnwrap(stdout.first)
        XCTAssertTrue(resumeHelp.hasPrefix("Resume a previous interactive session (picker by default; use --last to continue the most recent)\n\nUsage: codex resume [OPTIONS] [SESSION_ID] [PROMPT]"))
        XCTAssertTrue(resumeHelp.contains("      --include-non-interactive"))
        XCTAssertTrue(resumeHelp.contains("  -V, --version"))

        stdout.removeAll()
        let forkExitCode = await CodexCLI().runAsync(
            arguments: ["fork", "--help"],
            stdout: { stdout.append($0) },
            stderr: { _ in XCTFail("stderr should not be written") }
        )

        XCTAssertEqual(forkExitCode, 0)
        let forkHelp = try XCTUnwrap(stdout.first)
        XCTAssertTrue(forkHelp.hasPrefix("Fork a previous interactive session (picker by default; use --last to fork the most recent)\n\nUsage: codex fork [OPTIONS] [SESSION_ID] [PROMPT]"))
        XCTAssertTrue(forkHelp.contains("      --last\n          Fork the most recent session without showing the picker"))
        XCTAssertTrue(forkHelp.contains("  -V, --version"))

        stdout.removeAll()
        let cloudExitCode = await CodexCLI().runAsync(
            arguments: ["cloud", "--help"],
            stdout: { stdout.append($0) },
            stderr: { _ in XCTFail("stderr should not be written") }
        )

        XCTAssertEqual(cloudExitCode, 0)
        let cloudHelp = try XCTUnwrap(stdout.first)
        XCTAssertTrue(cloudHelp.hasPrefix("[EXPERIMENTAL] Browse tasks from Codex Cloud and apply changes locally\n\nUsage: codex cloud [OPTIONS] [COMMAND]"))
        XCTAssertTrue(cloudHelp.contains("  diff    Show the unified diff for a Codex Cloud task"))
    }

    func testCommandVersionTargetsSubcommandLikeRust() async {
        let execSpec = CommandSpec(name: "exec", aliases: ["e"], summary: "Run Codex non-interactively.")
        XCTAssertEqual(
            CodexCLI().parseInvocation(arguments: ["exec", "--version"]),
            .commandVersion(execSpec)
        )
        XCTAssertEqual(
            CodexCLI().parseInvocation(arguments: ["exec", "-V"]),
            .commandVersion(execSpec)
        )
        XCTAssertEqual(
            CodexCLI().parseInvocation(arguments: ["--version", "exec"]),
            .version
        )
        let reviewSpec = CommandSpec(name: "review", summary: "Run a code review non-interactively.")
        XCTAssertEqual(
            CodexCLI().parseInvocation(arguments: ["review", "--version"]),
            .commandUnsupportedVersion(reviewSpec, flag: "--version")
        )

        var stdout: [String] = []
        let exitCode = await CodexCLI().runAsync(
            arguments: ["exec", "--version"],
            stdout: { stdout.append($0) },
            stderr: { _ in XCTFail("stderr should not be written") }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(stdout, ["codex-cli-exec \(CodexBuildMetadata.version)"])

        var stderr: [String] = []
        let unsupportedExitCode = await CodexCLI().runAsync(
            arguments: ["review", "-V"],
            stdout: { _ in XCTFail("stdout should not be written") },
            stderr: { stderr.append($0) }
        )

        XCTAssertEqual(unsupportedExitCode, 2)
        XCTAssertEqual(
            stderr,
            [
                """
                error: unexpected argument '-V' found

                  tip: to pass '-V' as a value, use '-- -V'

                Usage: codex review [OPTIONS] [PROMPT]

                For more information, try '--help'.
                """
            ]
        )
    }

    func testPromptWithoutSubcommandIsInteractiveInvocation() {
        XCTAssertEqual(CodexCLI().parseInvocation(arguments: ["hello codex"]), .interactive(prompt: "hello codex"))
    }

    func testRunAsyncInteractiveDelegatesRootFlagsLikeRust() async {
        var receivedRequest: CodexCLI.InteractiveCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: [
                "--remote",
                "ws://root.example.test",
                "--remote-auth-token-env",
                "ROOT_TOKEN",
                "--oss",
                "--image",
                "root.png,/tmp/a.png",
                "--add-dir",
                "/root-extra",
                "-m",
                "gpt-5.1-test",
                "--local-provider",
                "ollama",
                "--search",
                "--sandbox",
                "workspace-write",
                "--ask-for-approval",
                "on-request",
                "-p",
                "my-profile",
                "-C",
                "/tmp",
                "-c",
                #"model="override""#,
                "--no-alt-screen",
                "--ephemeral",
                "--ignore-user-config",
                "--ignore-rules",
                "hello\r\ncodex"
            ],
            stderr: { _ in XCTFail("stderr should not be written") },
            interactiveRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(receivedRequest, CodexCLI.InteractiveCommandRequest(
            prompt: "hello\ncodex",
            remote: "ws://root.example.test",
            remoteAuthTokenEnv: "ROOT_TOKEN",
            interactiveOptions: CodexCLI.InteractiveCommandOptions(
                imagePaths: ["root.png", "/tmp/a.png"],
                model: "gpt-5.1-test",
                useOSSProvider: true,
                localProvider: "ollama",
                configProfile: "my-profile",
                sandboxMode: "workspace-write",
                cwd: "/tmp",
                additionalWritableRoots: ["/root-extra"],
                approvalPolicy: "on-request",
                searchEnabled: true,
                noAltScreen: true,
                ephemeral: true,
                ignoreUserConfig: true,
                ignoreRules: true
            ),
            configOverrides: .init(rawOverrides: [
                #"model="override""#,
                #"profile="my-profile""#,
                #"web_search="live""#
            ])
        ))
    }

    func testRunAsyncInteractiveRejectsExtraPromptArgumentsBeforeRunner() async {
        var stderr: [String] = []

        let exitCode = await CodexCLI().runAsync(
            arguments: ["first", "second"],
            stdout: { _ in XCTFail("stdout should not be written") },
            stderr: { stderr.append($0) },
            interactiveRunner: { _ in
                XCTFail("runner should not be called with extra prompt arguments")
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 64)
        XCTAssertEqual(stderr, ["codex-swift: unexpected argument for interactive prompt: second"])
    }

    func testRunAsyncInteractiveTreatsDoubleDashRemainderAsPrompt() async {
        var receivedRequest: CodexCLI.InteractiveCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["--", "--search"],
            stderr: { _ in XCTFail("stderr should not be written") },
            interactiveRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(receivedRequest?.prompt, "--search")
        XCTAssertEqual(receivedRequest?.remote, nil)
        XCTAssertEqual(receivedRequest?.configOverrides.rawOverrides, [])
        XCTAssertEqual(receivedRequest?.interactiveOptions.searchEnabled, false)
    }

    func testLineModeInteractiveRuntimeRunsInitialPromptAndInputLoop() async {
        let harness = LineModeIOHarness(inputs: ["second prompt", "/quit"])
        let recorder = LineModeTurnRecorder()
        let runtime = LineModeInteractiveRuntime(
            request: CodexCLI.InteractiveCommandRequest(prompt: "first prompt"),
            io: harness.io()
        ) { turn in
            await recorder.record(prompt: turn.prompt, turnIndex: turn.turnIndex)
            return CodexCLI.CommandExecutionResult(exitCode: 0, stdoutMessage: "ok \(turn.turnIndex)")
        }

        let result = await runtime.run()

        XCTAssertEqual(result.exitCode, 0)
        let recordedTurns = await recorder.values()
        XCTAssertEqual(recordedTurns, [
            LineModeRecordedTurn(prompt: "first prompt", turnIndex: 1),
            LineModeRecordedTurn(prompt: "second prompt", turnIndex: 2)
        ])
        XCTAssertEqual(harness.stdoutLines(), ["ok 1", "ok 2"])
        XCTAssertEqual(harness.prompts(), ["codex> ", "codex> "])
    }

    func testLineModeInteractiveRuntimePreservesLastThreadIDOnQuit() async {
        let harness = LineModeIOHarness(inputs: ["second prompt", "/quit"])
        let runtime = LineModeInteractiveRuntime(
            request: CodexCLI.InteractiveCommandRequest(prompt: "first prompt"),
            io: harness.io()
        ) { turn in
            CodexCLI.CommandExecutionResult(exitCode: 0, threadID: "thread-\(turn.turnIndex)")
        }

        let result = await runtime.run()

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.threadID, "thread-2")
    }

    func testLineModeInteractiveRuntimePreservesLastThreadIDOnEOF() async {
        let harness = LineModeIOHarness(inputs: [])
        let runtime = LineModeInteractiveRuntime(
            request: CodexCLI.InteractiveCommandRequest(prompt: "first prompt"),
            io: harness.io()
        ) { _ in
            CodexCLI.CommandExecutionResult(exitCode: 0, threadID: "thread-after-initial-prompt")
        }

        let result = await runtime.run()

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.threadID, "thread-after-initial-prompt")
    }

    func testLineModeInteractiveRuntimeReturnsInitialThreadIDOnQuitWithoutTurns() async {
        let harness = LineModeIOHarness(inputs: ["/quit"])
        let runtime = LineModeInteractiveRuntime(
            request: CodexCLI.InteractiveCommandRequest(),
            initialThreadID: "resolved-thread",
            io: harness.io()
        ) { _ in
            XCTFail("turn runner should not be called before /quit")
            return CodexCLI.CommandExecutionResult(exitCode: 0)
        }

        let result = await runtime.run()

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.threadID, "resolved-thread")
    }

    func testLineModeInteractiveRuntimePropagatesTurnFailure() async {
        let harness = LineModeIOHarness(inputs: ["ignored"])
        let runtime = LineModeInteractiveRuntime(
            request: CodexCLI.InteractiveCommandRequest(prompt: "fail"),
            io: harness.io()
        ) { _ in
            CodexCLI.CommandExecutionResult(exitCode: 2, stderrMessage: "failed turn")
        }

        let result = await runtime.run()

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertEqual(result.stderrMessage, "failed turn")
        XCTAssertEqual(Array(harness.stderrLines().suffix(1)), ["failed turn"])
        XCTAssertEqual(harness.prompts(), [])
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

    func testRunAsyncLoginStatusIgnoresCredentialFlagsLikeRust() async {
        var receivedAction: CodexCLI.LoginCommandAction?

        let exitCode = await CodexCLI().runAsync(
            arguments: [
                "login",
                "--api-key=sk-ignored",
                "--with-api-key",
                "--with-access-token",
                "status"
            ],
            stderr: { _ in },
            loginRunner: { request in
                receivedAction = request.action
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(receivedAction, .status)
    }

    func testRunAsyncLoginDeviceAuthTakesPrecedenceOverDeprecatedAPIKeyLikeRust() async {
        var stderr: [String] = []
        var receivedAction: CodexCLI.LoginCommandAction?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["login", "--device-auth", "--api-key=sk-ignored"],
            stderr: { stderr.append($0) },
            loginRunner: { request in
                receivedAction = request.action
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(stderr.isEmpty)
        XCTAssertEqual(receivedAction, .deviceCode(issuerBaseURL: nil, clientID: nil))
    }

    func testRunAsyncLoginWithAccessTokenDelegatesToRunnerLikeRust() async {
        var receivedAction: CodexCLI.LoginCommandAction?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["login", "--with-access-token"],
            stderr: { _ in },
            loginRunner: { request in
                receivedAction = request.action
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(receivedAction, .withAccessTokenFromStdin)
    }

    func testRunAsyncLoginRejectsMultipleCredentialSourcesLikeRust() async {
        var stderr: [String] = []

        let exitCode = await CodexCLI().runAsync(
            arguments: ["login", "--with-api-key", "--with-access-token"],
            stdout: { _ in XCTFail("stdout should not be written") },
            stderr: { stderr.append($0) },
            loginRunner: { _ in
                XCTFail("runner should not be called when credential sources conflict")
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 1)
        XCTAssertEqual(stderr, ["Choose one login credential source: --with-api-key or --with-access-token."])
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
                "memories",
                "--disable=shell_tool",
                "features",
                "list"
            ],
            stdout: { stdout.append($0) },
            stderr: { stderr.append($0) },
            featuresRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0, stdoutMessage: "web_search_request\tstable\ttrue")
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(stdout, ["web_search_request\tstable\ttrue"])
        XCTAssertTrue(stderr.isEmpty)
        XCTAssertEqual(receivedRequest?.action, .list)
        XCTAssertNil(receivedRequest?.configProfile)
        XCTAssertEqual(receivedRequest?.configOverrides.rawOverrides, [
            "features.web_search_request=true",
            "features.memories=true",
            "features.shell_tool=false"
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
                return CodexCLI.CommandExecutionResult(exitCode: 0)
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
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 64)
        XCTAssertEqual(stderr, ["codex-swift: missing required subcommand for command 'features': list, enable, or disable"])
    }

    func testRunAsyncFeaturesRejectsInvalidFormsBeforeRunner() async {
        let cases: [([String], String)] = [
            (
                ["features", "bogus"],
                "codex-swift: unsupported features subcommand: bogus"
            ),
            (
                ["features", "list", "extra"],
                "codex-swift: unexpected argument for command 'features list': extra"
            ),
            (
                ["features", "enable"],
                "codex-swift: missing required argument for command 'features enable': <FEATURE>"
            ),
            (
                ["features", "enable", "runtime_metrics", "extra"],
                "codex-swift: unexpected argument for command 'features enable': extra"
            ),
            (
                ["features", "disable"],
                "codex-swift: missing required argument for command 'features disable': <FEATURE>"
            ),
            (
                ["features", "disable", "shell_tool", "extra"],
                "codex-swift: unexpected argument for command 'features disable': extra"
            )
        ]

        for (arguments, expectedMessage) in cases {
            var stderr: [String] = []
            let exitCode = await CodexCLI().runAsync(
                arguments: arguments,
                stdout: { _ in XCTFail("stdout should not be written for \(arguments)") },
                stderr: { stderr.append($0) },
                featuresRunner: { _ in
                    XCTFail("runner should not be called for \(arguments)")
                    return CodexCLI.CommandExecutionResult(exitCode: 0)
                }
            )

            XCTAssertEqual(exitCode, 64, "\(arguments)")
            XCTAssertEqual(stderr, [expectedMessage], "\(arguments)")
        }
    }

    func testRunAsyncFeaturesEnableDelegatesToRunner() async {
        var stdout: [String] = []
        var stderr: [String] = []
        var receivedRequest: CodexCLI.FeaturesCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["--profile", "work", "features", "enable", "runtime_metrics"],
            stdout: { stdout.append($0) },
            stderr: { stderr.append($0) },
            featuresRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(
                    exitCode: 0,
                    stdoutMessage: "Enabled feature `runtime_metrics` in config.toml.",
                    stderrMessage: "warn"
                )
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(stdout, ["Enabled feature `runtime_metrics` in config.toml."])
        XCTAssertEqual(stderr, ["warn"])
        XCTAssertEqual(receivedRequest?.action, .enable(feature: "runtime_metrics"))
        XCTAssertEqual(receivedRequest?.configProfile, "work")
        XCTAssertEqual(receivedRequest?.configOverrides.rawOverrides, ["profile=\"work\""])
    }

    func testRunAsyncProfileV2IsRejectedForConfigManagementCommandsLikeRust() async {
        var stderr: [String] = []

        let exitCode = await CodexCLI().runAsync(
            arguments: ["--profile-v2", "work", "features", "list"],
            stdout: { _ in XCTFail("stdout should not be written") },
            stderr: { stderr.append($0) },
            featuresRunner: { _ in
                XCTFail("runner should not be called")
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 64)
        XCTAssertEqual(stderr, [
            "--profile-v2 only applies to runtime commands: `codex`, `codex exec`, `codex review`, `codex resume`, `codex fork`, `codex exec-server`, and `codex debug prompt-input`."
        ])
    }

    func testRunAsyncProfileV2RejectsPathLikeRust() async {
        var stderr: [String] = []

        let exitCode = await CodexCLI().runAsync(
            arguments: ["--profile-v2", "nested/work", "exec", "hello"],
            stdout: { _ in XCTFail("stdout should not be written") },
            stderr: { stderr.append($0) },
            execRunner: { _ in
                XCTFail("runner should not be called")
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 64)
        XCTAssertEqual(stderr, ["invalid --profile-v2 value `nested/work`; pass a plain name such as `work`"])
    }

    func testRunAsyncProfileV2IsCarriedForRuntimeCommandsLikeRust() async {
        var execRequest: CodexCLI.ExecCommandRequest?
        var reviewRequest: CodexCLI.ReviewCommandRequest?
        var debugRequest: CodexCLI.DebugCommandRequest?

        let execExitCode = await CodexCLI().runAsync(
            arguments: ["--profile-v2", "work", "exec", "hello"],
            stdout: { _ in },
            stderr: { _ in },
            execRunner: { request in
                execRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )
        let reviewExitCode = await CodexCLI().runAsync(
            arguments: ["--profile-v2=research", "review", "--uncommitted"],
            stdout: { _ in },
            stderr: { _ in },
            reviewRunner: { request in
                reviewRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )
        let debugExitCode = await CodexCLI().runAsync(
            arguments: ["--profile-v2", "debug-work", "debug", "prompt-input"],
            stdout: { _ in },
            stderr: { _ in },
            debugRunner: { request in
                debugRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(execExitCode, 0)
        XCTAssertEqual(reviewExitCode, 0)
        XCTAssertEqual(debugExitCode, 0)
        XCTAssertEqual(execRequest?.options.configProfileV2, "work")
        XCTAssertEqual(execRequest?.configOverrides.rawOverrides, [])
        XCTAssertEqual(reviewRequest?.configProfileV2, "research")
        XCTAssertEqual(reviewRequest?.configOverrides.rawOverrides, [])
        XCTAssertEqual(debugRequest?.configProfileV2, "debug-work")
        XCTAssertEqual(debugRequest?.configOverrides.rawOverrides, [])
    }

    func testRunAsyncExecAcceptsSubcommandProfileV2LikeRustSharedOptions() async {
        var receivedRequest: CodexCLI.ExecCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["exec", "--profile-v2=work", "hello"],
            stdout: { _ in },
            stderr: { _ in },
            execRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(receivedRequest?.options.configProfileV2, "work")
        XCTAssertEqual(receivedRequest?.configOverrides.rawOverrides, [])
    }

    func testRunAsyncFeaturesDisableDelegatesToRunner() async {
        var receivedRequest: CodexCLI.FeaturesCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["features", "disable", "shell_tool"],
            stdout: { _ in },
            stderr: { _ in },
            featuresRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(receivedRequest?.action, .disable(feature: "shell_tool"))
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

    func testRunAsyncCloudStatusAllowsDashPrefixedTaskAfterDelimiterLikeRustClap() async {
        var receivedRequest: CodexCLI.CloudCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["cloud", "status", "--", "-task_123"],
            stderr: { _ in XCTFail("stderr should not be written") },
            cloudRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(receivedRequest?.action, .status(taskID: "-task_123"))
    }

    func testRunAsyncCloudListParsesRustFlags() async {
        var stdout: [String] = []
        var receivedRequest: CodexCLI.CloudCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["cloud", "list", "--env=Env A", "--limit", "7", "--cursor=next-page", "--json"],
            stdout: { stdout.append($0) },
            stderr: { _ in XCTFail("stderr should not be written") },
            cloudRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0, stdoutMessage: #"{"tasks":[]}"#)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(stdout, [#"{"tasks":[]}"#])
        XCTAssertEqual(
            receivedRequest?.action,
            .list(environment: "Env A", limit: 7, cursor: "next-page", json: true)
        )
    }

    func testRunAsyncCloudListRejectsInvalidLimitBeforeRunner() async {
        var stderr: [String] = []

        let exitCode = await CodexCLI().runAsync(
            arguments: ["cloud", "list", "--limit", "0"],
            stdout: { _ in XCTFail("stdout should not be written") },
            stderr: { stderr.append($0) },
            cloudRunner: { _ in
                XCTFail("runner should not be called with invalid limit")
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 64)
        XCTAssertEqual(stderr, ["limit must be between 1 and 20"])
    }

    func testRunAsyncCloudListAcceptsBareDelimiterLikeRustClap() async {
        var receivedRequest: CodexCLI.CloudCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["cloud", "list", "--env=Env A", "--"],
            stderr: { _ in XCTFail("stderr should not be written") },
            cloudRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(receivedRequest?.action, .list(environment: "Env A", limit: 20, cursor: nil, json: false))
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

    func testRunAsyncCloudDiffAllowsDashPrefixedTaskAfterDelimiterLikeRustClap() async {
        var receivedRequest: CodexCLI.CloudCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["cloud", "diff", "--attempt=2", "--", "-task_123"],
            stderr: { _ in XCTFail("stderr should not be written") },
            cloudRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(receivedRequest?.action, .diff(taskID: "-task_123", attempt: 2))
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

    func testRunAsyncCloudApplyAllowsDashPrefixedTaskAfterDelimiterLikeRustClap() async {
        var receivedRequest: CodexCLI.CloudCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["cloud", "apply", "--attempt", "3", "--", "-task_123"],
            stderr: { _ in XCTFail("stderr should not be written") },
            cloudRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(receivedRequest?.action, .apply(taskID: "-task_123", attempt: 3))
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

    func testRunAsyncCloudExecAllowsDashQueryForForcedStdinLikeRust() async {
        var receivedRequest: CodexCLI.CloudCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["cloud", "exec", "--env=env_123", "-"],
            stderr: { _ in XCTFail("stderr should not be written") },
            cloudRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(receivedRequest?.action, .exec(query: "-", environment: "env_123", branch: nil, attempts: 1))
    }

    func testRunAsyncCloudExecAllowsDashPrefixedQueryAfterDelimiterLikeRustClap() async {
        var receivedRequest: CodexCLI.CloudCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["cloud", "exec", "--env=env_123", "--", "--write-tests"],
            stderr: { _ in XCTFail("stderr should not be written") },
            cloudRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(receivedRequest?.action, .exec(query: "--write-tests", environment: "env_123", branch: nil, attempts: 1))
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

    func testRunAsyncResponsesAPIProxyDelegatesToRunnerWithRustFlags() async {
        var receivedRequest: CodexCLI.ResponsesAPIProxyCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: [
                "responses-api-proxy",
                "--port=4321",
                "--server-info",
                "/tmp/proxy.json",
                "--http-shutdown",
                "--upstream-url",
                "https://example.test/v1/responses",
                "--dump-dir=/tmp/proxy-dumps"
            ],
            stderr: { _ in XCTFail("stderr should not be written") },
            responsesAPIProxyRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(receivedRequest, CodexCLI.ResponsesAPIProxyCommandRequest(
            port: 4321,
            serverInfoPath: "/tmp/proxy.json",
            httpShutdown: true,
            upstreamURL: "https://example.test/v1/responses",
            dumpDir: "/tmp/proxy-dumps"
        ))
    }

    func testRunAsyncResponsesAPIProxyRejectsInvalidArgumentsBeforeRunner() async {
        let cases: [([String], String)] = [
            (
                ["responses-api-proxy", "--port"],
                "codex-swift: missing value for --port"
            ),
            (
                ["responses-api-proxy", "--port", "70000"],
                "codex-swift: invalid value for --port: 70000"
            ),
            (
                ["responses-api-proxy", "--bogus"],
                "codex-swift: unsupported option for command 'responses-api-proxy': --bogus"
            ),
            (
                ["responses-api-proxy", "extra"],
                "codex-swift: unexpected argument for command 'responses-api-proxy': extra"
            )
        ]

        for (arguments, expectedMessage) in cases {
            var stderr: [String] = []
            let exitCode = await CodexCLI().runAsync(
                arguments: arguments,
                stdout: { _ in XCTFail("stdout should not be written for \(arguments)") },
                stderr: { stderr.append($0) },
                responsesAPIProxyRunner: { _ in
                    XCTFail("runner should not be called for \(arguments)")
                    return CodexCLI.CommandExecutionResult(exitCode: 0)
                }
            )

            XCTAssertEqual(exitCode, 64, "\(arguments)")
            XCTAssertEqual(stderr, [expectedMessage], "\(arguments)")
        }
    }
}

private struct LineModeRecordedTurn: Equatable {
    let prompt: String
    let turnIndex: Int
}

private actor LineModeTurnRecorder {
    private var turns: [LineModeRecordedTurn] = []

    func record(prompt: String, turnIndex: Int) {
        turns.append(LineModeRecordedTurn(prompt: prompt, turnIndex: turnIndex))
    }

    func values() -> [LineModeRecordedTurn] {
        turns
    }
}

private final class LineModeIOHarness: @unchecked Sendable {
    private let lock = NSLock()
    private var inputs: [String]
    private var stdout: [String] = []
    private var stderr: [String] = []
    private var promptValues: [String] = []

    init(inputs: [String]) {
        self.inputs = inputs
    }

    func io() -> LineModeInteractiveRuntime.IO {
        LineModeInteractiveRuntime.IO(
            readLine: { [weak self] in
                self?.nextInput()
            },
            writeStdout: { [weak self] line in
                self?.appendStdout(line)
            },
            writeStderr: { [weak self] line in
                self?.appendStderr(line)
            },
            writePrompt: { [weak self] prompt in
                self?.appendPrompt(prompt)
            }
        )
    }

    func stdoutLines() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return stdout
    }

    func stderrLines() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return stderr
    }

    func prompts() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return promptValues
    }

    private func nextInput() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard !inputs.isEmpty else {
            return nil
        }
        return inputs.removeFirst()
    }

    private func appendStdout(_ line: String) {
        lock.lock()
        stdout.append(line)
        lock.unlock()
    }

    private func appendStderr(_ line: String) {
        lock.lock()
        stderr.append(line)
        lock.unlock()
    }

    private func appendPrompt(_ prompt: String) {
        lock.lock()
        promptValues.append(prompt)
        lock.unlock()
    }
}
