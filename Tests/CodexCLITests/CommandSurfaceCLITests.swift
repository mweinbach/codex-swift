import CodexCLI
import CodexCore
import XCTest

final class CommandSurfaceCLITests: XCTestCase {
    func testRunAsyncExecDelegatesRawArgumentsAndOverrides() async {
        var stdout: [String] = []
        var receivedRequest: CodexCLI.ExecCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["-c", "model=\"gpt-5\"", "exec", "--json", "ship it"],
            stdout: { stdout.append($0) },
            stderr: { _ in XCTFail("stderr should not be written") },
            execRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0, stdoutMessage: "done")
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(stdout, ["done"])
        XCTAssertEqual(receivedRequest, CodexCLI.ExecCommandRequest(
            arguments: ["--json", "ship it"],
            configOverrides: CliConfigOverrides(rawOverrides: ["model=\"gpt-5\""])
        ))
    }

    func testRunAsyncComputerUseParsesGuiFlagAndDelegatesExecArguments() async {
        var receivedRequest: CodexCLI.ComputerUseCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["--enable", "skills", "computer-use", "--gui", "--json", "inspect screen"],
            stderr: { _ in XCTFail("stderr should not be written") },
            computerUseRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(receivedRequest, CodexCLI.ComputerUseCommandRequest(
            arguments: ["--json", "inspect screen"],
            enableGUI: true,
            configOverrides: CliConfigOverrides(rawOverrides: [
                "features.skills=true",
                "features.computer_use_gui=true"
            ])
        ))
    }

    func testRunAsyncComputerUseRejectsGuiHeadlessConflictBeforeRunner() async {
        var stderr: [String] = []

        let exitCode = await CodexCLI().runAsync(
            arguments: ["computer-use", "--gui", "--headless", "inspect"],
            stdout: { _ in XCTFail("stdout should not be written") },
            stderr: { stderr.append($0) },
            computerUseRunner: { _ in
                XCTFail("runner should not be called with conflicting GUI flags")
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 64)
        XCTAssertEqual(stderr, [
            "codex-swift: argument conflict for command 'computer-use': --headless conflicts with --gui"
        ])
    }

    func testRunAsyncReviewParsesCommitTargetAndOverrides() async {
        var receivedRequest: CodexCLI.ReviewCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: [
                "-c",
                "review_model=\"gpt-5\"",
                "review",
                "--commit",
                "abcdef1234567890",
                "--title=Parser fix"
            ],
            stderr: { _ in XCTFail("stderr should not be written") },
            reviewRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(receivedRequest, CodexCLI.ReviewCommandRequest(
            target: .commit(sha: "abcdef1234567890", title: "Parser fix"),
            configOverrides: CliConfigOverrides(rawOverrides: ["review_model=\"gpt-5\""])
        ))
    }

    func testRunAsyncReviewParsesCustomStdinTarget() async {
        var receivedRequest: CodexCLI.ReviewCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["review", "-"],
            stderr: { _ in XCTFail("stderr should not be written") },
            reviewRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(receivedRequest?.target, .customFromStdin)
    }

    func testRunAsyncReviewRejectsConflictingTargetsBeforeRunner() async {
        var stderr: [String] = []

        let exitCode = await CodexCLI().runAsync(
            arguments: ["review", "--uncommitted", "--base", "main"],
            stdout: { _ in XCTFail("stdout should not be written") },
            stderr: { stderr.append($0) },
            reviewRunner: { _ in
                XCTFail("runner should not be called with conflicting review targets")
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 64)
        XCTAssertEqual(stderr, [
            "codex-swift: argument conflict for command 'review': --base cannot be used with another review target"
        ])
    }

    func testRunAsyncReviewRejectsTitleWithoutCommitBeforeRunner() async {
        var stderr: [String] = []

        let exitCode = await CodexCLI().runAsync(
            arguments: ["review", "--title", "Parser fix"],
            stdout: { _ in XCTFail("stdout should not be written") },
            stderr: { stderr.append($0) },
            reviewRunner: { _ in
                XCTFail("runner should not be called without a commit target")
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 64)
        XCTAssertEqual(stderr, ["codex-swift: --title requires --commit"])
    }

    func testRunAsyncResumeParsesLastAllAndOverrides() async {
        var receivedRequest: CodexCLI.ResumeCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["-c", "model=\"gpt-5.4\"", "resume", "--last", "--all"],
            stderr: { _ in XCTFail("stderr should not be written") },
            resumeRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(receivedRequest, CodexCLI.ResumeCommandRequest(
            sessionID: nil,
            last: true,
            all: true,
            configOverrides: CliConfigOverrides(rawOverrides: ["model=\"gpt-5.4\""])
        ))
    }

    func testRunAsyncResumeRejectsLastWithSessionIDBeforeRunner() async {
        var stderr: [String] = []

        let exitCode = await CodexCLI().runAsync(
            arguments: ["resume", "--last", "123e4567-e89b-12d3-a456-426614174000"],
            stdout: { _ in XCTFail("stdout should not be written") },
            stderr: { stderr.append($0) },
            resumeRunner: { _ in
                XCTFail("runner should not be called with conflicting resume arguments")
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 64)
        XCTAssertEqual(stderr, [
            "codex-swift: argument conflict for command 'resume': SESSION_ID conflicts with --last"
        ])
    }

    func testRunAsyncMcpServerDelegatesWithOverrides() async {
        var receivedRequest: CodexCLI.McpServerCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["-c", "approval_policy=\"never\"", "mcp-server"],
            stderr: { _ in XCTFail("stderr should not be written") },
            mcpServerRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(
            receivedRequest,
            CodexCLI.McpServerCommandRequest(
                configOverrides: CliConfigOverrides(rawOverrides: ["approval_policy=\"never\""])
            )
        )
    }

    func testRunAsyncMcpServerRejectsArgumentsBeforeRunner() async {
        var stderr: [String] = []

        let exitCode = await CodexCLI().runAsync(
            arguments: ["mcp-server", "extra"],
            stdout: { _ in XCTFail("stdout should not be written") },
            stderr: { stderr.append($0) },
            mcpServerRunner: { _ in
                XCTFail("runner should not be called with mcp-server arguments")
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 64)
        XCTAssertEqual(stderr, ["codex-swift: unexpected argument for command 'mcp-server': extra"])
    }

    func testRunAsyncAppServerParsesRunAndGenerators() async {
        var actions: [CodexCLI.AppServerCommandAction] = []

        for arguments in [
            ["app-server"],
            ["app-server", "generate-ts", "-o", "/tmp/ts", "--prettier", "prettier"],
            ["app-server", "generate-json-schema", "--out=/tmp/schema"]
        ] {
            let exitCode = await CodexCLI().runAsync(
                arguments: arguments,
                stderr: { _ in XCTFail("stderr should not be written for \(arguments)") },
                appServerRunner: { request in
                    actions.append(request.action)
                    return CodexCLI.CommandExecutionResult(exitCode: 0)
                }
            )
            XCTAssertEqual(exitCode, 0, "\(arguments)")
        }

        XCTAssertEqual(actions, [
            .run,
            .generateTS(outDir: "/tmp/ts", prettier: "prettier"),
            .generateJSONSchema(outDir: "/tmp/schema")
        ])
    }

    func testRunAsyncAppServerRejectsInvalidGeneratorFormsBeforeRunner() async {
        let cases: [([String], String)] = [
            (
                ["app-server", "generate-ts"],
                "codex-swift: missing required option for command 'app-server generate-ts': --out <DIR>"
            ),
            (
                ["app-server", "generate-json-schema", "--prettier", "prettier", "--out", "/tmp/schema"],
                "codex-swift: unsupported option for command 'app-server generate-json-schema': --prettier"
            ),
            (
                ["app-server", "bogus"],
                "codex-swift: unsupported app-server subcommand: bogus"
            )
        ]

        for (arguments, expectedMessage) in cases {
            var stderr: [String] = []
            let exitCode = await CodexCLI().runAsync(
                arguments: arguments,
                stdout: { _ in XCTFail("stdout should not be written for \(arguments)") },
                stderr: { stderr.append($0) },
                appServerRunner: { _ in
                    XCTFail("runner should not be called for \(arguments)")
                    return CodexCLI.CommandExecutionResult(exitCode: 0)
                }
            )

            XCTAssertEqual(exitCode, 64, "\(arguments)")
            XCTAssertEqual(stderr, [expectedMessage], "\(arguments)")
        }
    }

    func testRunAsyncNewCommandHooksWithoutRunnersStillReportUnimplemented() async {
        for command in ["exec", "computer-use", "review", "resume", "mcp-server", "app-server"] {
            var stderr: [String] = []
            let exitCode = await CodexCLI().runAsync(
                arguments: [command],
                stdout: { _ in XCTFail("stdout should not be written for \(command)") },
                stderr: { stderr.append($0) }
            )

            XCTAssertEqual(exitCode, 78, command)
            XCTAssertEqual(
                stderr,
                ["codex-swift: command '\(command)' is registered but its runtime port is not complete yet."],
                command
            )
        }
    }
}
