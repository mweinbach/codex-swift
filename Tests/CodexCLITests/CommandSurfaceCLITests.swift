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
            action: .run(prompt: "ship it"),
            options: CodexCLI.ExecCommandOptions(json: true),
            configOverrides: CliConfigOverrides(rawOverrides: ["model=\"gpt-5\""])
        ))
    }

    func testRunAsyncExecParsesPreflightOptions() async {
        var receivedRequest: CodexCLI.ExecCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: [
                "exec",
                "--skip-git-repo-check",
                "--output-schema",
                "/tmp/schema.json",
                "--output-last-message=/tmp/last.txt",
                "--image",
                "one.png,two.png",
                "--ephemeral",
                "--ignore-user-config",
                "--ignore-rules",
                "ship it"
            ],
            stderr: { _ in XCTFail("stderr should not be written") },
            execRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(receivedRequest?.action, .run(prompt: "ship it"))
        XCTAssertEqual(receivedRequest?.options, CodexCLI.ExecCommandOptions(
            imagePaths: ["one.png", "two.png"],
            outputSchemaPath: "/tmp/schema.json",
            lastMessageFile: "/tmp/last.txt",
            skipGitRepoCheck: true,
            ephemeral: true,
            ignoreUserConfig: true,
            ignoreRules: true
        ))
    }

    func testRunAsyncExecResumeAcceptsRustGlobalFlagsAfterSubcommand() async {
        var receivedRequest: CodexCLI.ExecCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: [
                "exec",
                "resume",
                "--last",
                "--json",
                "--model",
                "gpt-5.2-codex",
                "--dangerously-bypass-approvals-and-sandbox",
                "--skip-git-repo-check",
                "--ephemeral",
                "--ignore-user-config",
                "--ignore-rules",
                "-o",
                "/tmp/resume-output.md",
                "echo resume-with-global-flags-after-subcommand"
            ],
            stderr: { _ in XCTFail("stderr should not be written") },
            execRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(receivedRequest?.action, .resume(CodexCLI.ExecResumeCommand(
            sessionID: "echo resume-with-global-flags-after-subcommand",
            last: true,
            prompt: nil
        )))
        XCTAssertEqual(receivedRequest?.options, CodexCLI.ExecCommandOptions(
            json: true,
            lastMessageFile: "/tmp/resume-output.md",
            skipGitRepoCheck: true,
            ephemeral: true,
            ignoreUserConfig: true,
            ignoreRules: true
        ))
    }

    func testRunAsyncExecResumeParsesImageOptionsLikeRust() async {
        var receivedRequest: CodexCLI.ExecCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: [
                "exec",
                "--image",
                "before.png",
                "resume",
                "--last",
                "--image",
                "one.png,two.png",
                "-ithree.png",
                "follow up"
            ],
            stderr: { _ in XCTFail("stderr should not be written") },
            execRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(receivedRequest?.action, .resume(CodexCLI.ExecResumeCommand(
            sessionID: "follow up",
            last: true,
            prompt: nil
        )))
        XCTAssertEqual(receivedRequest?.options.imagePaths, [
            "before.png",
            "one.png",
            "two.png",
            "three.png"
        ])
    }

    func testRunAsyncExecParsesReviewSubcommand() async {
        var receivedRequest: CodexCLI.ExecCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["exec", "review", "--base", "main"],
            stderr: { _ in XCTFail("stderr should not be written") },
            execRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(receivedRequest?.action, .review(.baseBranch(branch: "main")))
    }

    func testRunAsyncExecResumePreservesRustLastPromptSemantics() async {
        var receivedRequests: [CodexCLI.ExecCommandRequest] = []

        for arguments in [
            ["exec", "resume", "--last", "fix it"],
            ["exec", "resume", "--last", "--all", "fix it everywhere"],
            ["exec", "resume", "123e4567-e89b-12d3-a456-426614174000", "follow up"]
        ] {
            let exitCode = await CodexCLI().runAsync(
                arguments: arguments,
                stderr: { _ in XCTFail("stderr should not be written for \(arguments)") },
                execRunner: { request in
                    receivedRequests.append(request)
                    return CodexCLI.CommandExecutionResult(exitCode: 0)
                }
            )
            XCTAssertEqual(exitCode, 0)
        }

        XCTAssertEqual(receivedRequests.map(\.action), [
            .resume(CodexCLI.ExecResumeCommand(sessionID: "fix it", last: true, prompt: nil)),
            .resume(CodexCLI.ExecResumeCommand(
                sessionID: "fix it everywhere",
                last: true,
                all: true,
                prompt: nil
            )),
            .resume(CodexCLI.ExecResumeCommand(
                sessionID: "123e4567-e89b-12d3-a456-426614174000",
                last: false,
                prompt: "follow up"
            ))
        ])
    }

    func testRunAsyncExecResumeUsesRootPromptBeforeSubcommand() async {
        var receivedRequests: [CodexCLI.ExecCommandRequest] = []

        for arguments in [
            ["exec", "follow up", "resume", "--last"],
            ["exec", "follow up", "resume", "123e4567-e89b-12d3-a456-426614174000"],
            ["exec", "root prompt", "resume", "--last", "subcommand prompt"]
        ] {
            let exitCode = await CodexCLI().runAsync(
                arguments: arguments,
                stderr: { _ in XCTFail("stderr should not be written for \(arguments)") },
                execRunner: { request in
                    receivedRequests.append(request)
                    return CodexCLI.CommandExecutionResult(exitCode: 0)
                }
            )
            XCTAssertEqual(exitCode, 0)
        }

        XCTAssertEqual(receivedRequests.map(\.action), [
            .resume(CodexCLI.ExecResumeCommand(sessionID: nil, last: true, prompt: "follow up")),
            .resume(CodexCLI.ExecResumeCommand(
                sessionID: "123e4567-e89b-12d3-a456-426614174000",
                last: false,
                prompt: "follow up"
            )),
            .resume(CodexCLI.ExecResumeCommand(sessionID: "subcommand prompt", last: true, prompt: nil))
        ])
    }

    func testExecCommandRequestResolvesPromptAndOutputSchema() throws {
        let request = CodexCLI.ExecCommandRequest(
            arguments: [],
            action: .run(prompt: nil),
            options: CodexCLI.ExecCommandOptions(outputSchemaPath: "/tmp/schema.json")
        )

        let operation = try request.resolvedInitialOperation(
            stdinIsTerminal: false,
            readStdin: { "from pipe" },
            readFile: { path in
                XCTAssertEqual(path, "/tmp/schema.json")
                return Data(#"{"type":"object"}"#.utf8)
            }
        )

        XCTAssertEqual(operation, .userTurn(
            prompt: NonInteractivePromptResolution(
                prompt: "from pipe",
                stderrMessage: "Reading prompt from stdin..."
            ),
            outputSchema: .object(["type": .string("object")])
        ))
    }

    func testExecCommandRequestResolvesResumePromptAndSchema() throws {
        let request = CodexCLI.ExecCommandRequest(
            arguments: [],
            action: .resume(CodexCLI.ExecResumeCommand(sessionID: "fix it", last: true, prompt: nil)),
            options: CodexCLI.ExecCommandOptions(outputSchemaPath: "/tmp/schema.json")
        )

        let operation = try request.resolvedInitialOperation(
            stdinIsTerminal: true,
            readStdin: { throw TestError("stdin should not be read") },
            readFile: { _ in Data(#"{"type":"string"}"#.utf8) }
        )

        XCTAssertEqual(operation, .resume(
            sessionID: nil,
            last: true,
            all: false,
            prompt: NonInteractivePromptResolution(prompt: "fix it"),
            outputSchema: .object(["type": .string("string")])
        ))
    }

    func testExecCommandRequestResolvesResumeAllLikeRust() throws {
        let request = CodexCLI.ExecCommandRequest(
            arguments: [],
            action: .resume(CodexCLI.ExecResumeCommand(
                sessionID: "123e4567-e89b-12d3-a456-426614174000",
                last: false,
                all: true,
                prompt: "follow up"
            ))
        )

        let operation = try request.resolvedInitialOperation(
            stdinIsTerminal: true,
            readStdin: { throw TestError("stdin should not be read") },
            readFile: { _ in throw TestError("schema should not be read") }
        )

        XCTAssertEqual(operation, .resume(
            sessionID: "123e4567-e89b-12d3-a456-426614174000",
            last: false,
            all: true,
            prompt: NonInteractivePromptResolution(prompt: "follow up"),
            outputSchema: nil
        ))
    }

    func testRunAsyncExecRejectsInvalidPreflightArgumentsBeforeRunner() async {
        let cases: [([String], String)] = [
            (["exec", "--output-schema"], "codex-swift: missing value for --output-schema"),
            (["exec", "ship", "extra"], "codex-swift: unexpected argument for command 'exec': extra"),
            (["exec", "resume", "--bogus"], "codex-swift: unsupported option for command 'exec resume': --bogus")
        ]

        for (arguments, expectedMessage) in cases {
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
            XCTAssertEqual(stderr, [expectedMessage], "\(arguments)")
        }
    }

    func testRunAsyncComputerUseParsesGuiFlagAndDelegatesExecArguments() async {
        var receivedRequest: CodexCLI.ComputerUseCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["--enable", "memories", "computer-use", "--gui", "--json", "inspect screen"],
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
                "features.memories=true",
                "features.computer_use=true"
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

    func testRunAsyncForkParsesTargetFlagsRemoteAndOverrides() async {
        var requests: [CodexCLI.ForkCommandRequest] = []

        for arguments in [
            ["-c", "model=\"gpt-5.4\"", "fork", "--last", "--all"],
            ["--remote", "ws://root.example.test", "fork", "123e4567-e89b-12d3-a456-426614174000"],
            [
                "--remote",
                "ws://root.example.test",
                "--remote-auth-token-env",
                "ROOT_TOKEN",
                "fork",
                "--remote=ws://fork.example.test",
                "--remote-auth-token-env",
                "FORK_TOKEN"
            ]
        ] {
            let exitCode = await CodexCLI().runAsync(
                arguments: arguments,
                stderr: { _ in XCTFail("stderr should not be written for \(arguments)") },
                forkRunner: { request in
                    requests.append(request)
                    return CodexCLI.CommandExecutionResult(exitCode: 0)
                }
            )
            XCTAssertEqual(exitCode, 0, "\(arguments)")
        }

        XCTAssertEqual(requests, [
            CodexCLI.ForkCommandRequest(
                sessionID: nil,
                last: true,
                all: true,
                configOverrides: CliConfigOverrides(rawOverrides: ["model=\"gpt-5.4\""])
            ),
            CodexCLI.ForkCommandRequest(
                sessionID: "123e4567-e89b-12d3-a456-426614174000",
                last: false,
                all: false,
                remote: "ws://root.example.test"
            ),
            CodexCLI.ForkCommandRequest(
                sessionID: nil,
                last: false,
                all: false,
                remote: "ws://fork.example.test",
                remoteAuthTokenEnv: "FORK_TOKEN"
            )
        ])
    }

    func testRunAsyncForkRejectsInvalidFormsBeforeRunner() async {
        let cases: [([String], String)] = [
            (
                ["fork", "--last", "123e4567-e89b-12d3-a456-426614174000"],
                "codex-swift: argument conflict for command 'fork': SESSION_ID conflicts with --last"
            ),
            (
                ["fork", "123e4567-e89b-12d3-a456-426614174000", "--last"],
                "codex-swift: argument conflict for command 'fork': --last conflicts with SESSION_ID"
            ),
            (
                ["fork", "--bogus"],
                "codex-swift: unsupported option for command 'fork': --bogus"
            ),
            (
                ["fork", "--remote"],
                "codex-swift: missing value for --remote"
            ),
            (
                ["fork", "one", "two"],
                "codex-swift: unexpected argument for command 'fork': two"
            )
        ]

        for (arguments, expectedMessage) in cases {
            var stderr: [String] = []
            let exitCode = await CodexCLI().runAsync(
                arguments: arguments,
                stdout: { _ in XCTFail("stdout should not be written for \(arguments)") },
                stderr: { stderr.append($0) },
                forkRunner: { _ in
                    XCTFail("runner should not be called for \(arguments)")
                    return CodexCLI.CommandExecutionResult(exitCode: 0)
                }
            )

            XCTAssertEqual(exitCode, 64, "\(arguments)")
            XCTAssertEqual(stderr, [expectedMessage], "\(arguments)")
        }
    }

    func testRunAsyncExecServerParsesListenAndRemoteFlags() async {
        var requests: [CodexCLI.ExecServerCommandRequest] = []

        for arguments in [
            ["exec-server"],
            ["exec-server", "--listen", "stdio"],
            ["exec-server", "--listen=ws://127.0.0.1:4500"],
            ["exec-server", "--remote", "https://registry.example.test", "--executor-id", "exec-123"],
            [
                "exec-server",
                "--remote=https://registry.example.test/",
                "--executor-id=exec-123",
                "--name",
                "Local Executor"
            ]
        ] {
            let exitCode = await CodexCLI().runAsync(
                arguments: arguments,
                stderr: { _ in XCTFail("stderr should not be written for \(arguments)") },
                execServerRunner: { request in
                    requests.append(request)
                    return CodexCLI.CommandExecutionResult(exitCode: 0)
                }
            )
            XCTAssertEqual(exitCode, 0, "\(arguments)")
        }

        XCTAssertEqual(requests, [
            CodexCLI.ExecServerCommandRequest(action: .listen(url: defaultExecServerListenURL)),
            CodexCLI.ExecServerCommandRequest(action: .listen(url: "stdio")),
            CodexCLI.ExecServerCommandRequest(action: .listen(url: "ws://127.0.0.1:4500")),
            CodexCLI.ExecServerCommandRequest(action: .remote(
                baseURL: "https://registry.example.test",
                executorID: "exec-123",
                name: nil
            )),
            CodexCLI.ExecServerCommandRequest(action: .remote(
                baseURL: "https://registry.example.test/",
                executorID: "exec-123",
                name: "Local Executor"
            ))
        ])
    }

    func testRunAsyncExecServerRejectsInvalidFormsBeforeRunner() async {
        let cases: [([String], String, Int32)] = [
            (
                ["--remote", "ws://root.example.test", "exec-server"],
                "`--remote ws://root.example.test` is only supported for interactive TUI commands, not `codex exec-server`",
                1
            ),
            (
                ["--remote-auth-token-env", "ROOT_TOKEN", "exec-server"],
                "`--remote-auth-token-env` is only supported for interactive TUI commands, not `codex exec-server`",
                1
            ),
            (
                ["exec-server", "--listen"],
                "codex-swift: missing value for --listen",
                64
            ),
            (
                ["exec-server", "--remote", "https://registry.example.test"],
                "codex-swift: --executor-id is required when --remote is set",
                64
            ),
            (
                ["exec-server", "--listen", "stdio", "--remote", "https://registry.example.test"],
                "codex-swift: argument conflict for command 'exec-server': --remote conflicts with --listen",
                64
            ),
            (
                ["exec-server", "--bogus"],
                "codex-swift: unsupported option for command 'exec-server': --bogus",
                64
            ),
            (
                ["exec-server", "extra"],
                "codex-swift: unexpected argument for command 'exec-server': extra",
                64
            )
        ]

        for (arguments, expectedMessage, expectedExitCode) in cases {
            var stderr: [String] = []
            let exitCode = await CodexCLI().runAsync(
                arguments: arguments,
                stdout: { _ in XCTFail("stdout should not be written for \(arguments)") },
                stderr: { stderr.append($0) },
                execServerRunner: { _ in
                    XCTFail("runner should not be called for \(arguments)")
                    return CodexCLI.CommandExecutionResult(exitCode: 0)
                }
            )

            XCTAssertEqual(exitCode, expectedExitCode, "\(arguments)")
            XCTAssertEqual(stderr, [expectedMessage], "\(arguments)")
        }
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
            ["app-server", "generate-json-schema", "--out=/tmp/schema", "--experimental"]
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
            .generateTS(outDir: "/tmp/ts", prettier: "prettier", experimental: false),
            .generateJSONSchema(outDir: "/tmp/schema", experimental: true)
        ])
    }

    func testRunAsyncAppServerParsesExperimentalFlags() async {
        var action: CodexCLI.AppServerCommandAction?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["app-server", "generate-ts", "--out", "/tmp/ts", "--experimental"],
            stderr: { _ in XCTFail("stderr should not be written") },
            appServerRunner: { request in
                action = request.action
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(action, .generateTS(outDir: "/tmp/ts", prettier: nil, experimental: true))
    }

    func testRunAsyncRemoteControlAppendsFeatureOverrideAfterRootOverrides() async {
        var request: CodexCLI.AppServerCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: [
                "-c",
                "features.remote_control=false",
                "--enable",
                "web_search_request",
                "remote-control"
            ],
            stderr: { _ in XCTFail("stderr should not be written") },
            appServerRunner: {
                request = $0
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(request?.action, .remoteControl)
        XCTAssertEqual(request?.configOverrides.rawOverrides, [
            "features.remote_control=false",
            "features.web_search_request=true",
            "features.remote_control=true"
        ])
    }

    func testRunAsyncRemoteControlRejectsRootRemoteFlagsBeforeRunner() async {
        let cases: [([String], String)] = [
            (
                ["--remote", "ws://127.0.0.1:8080", "remote-control"],
                "`--remote ws://127.0.0.1:8080` is only supported for interactive TUI commands, not `codex remote-control`"
            ),
            (
                ["--remote-auth-token-env", "CODEX_REMOTE_TOKEN", "remote-control"],
                "`--remote-auth-token-env` is only supported for interactive TUI commands, not `codex remote-control`"
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

            XCTAssertEqual(exitCode, 1, "\(arguments)")
            XCTAssertEqual(stderr, [expectedMessage], "\(arguments)")
        }
    }

    func testRunAsyncRemoteControlRejectsArgumentsBeforeRunner() async {
        let cases: [([String], String)] = [
            (
                ["remote-control", "extra"],
                "codex-swift: unexpected argument for command 'remote-control': extra"
            ),
            (
                ["remote-control", "--listen"],
                "codex-swift: unsupported option for command 'remote-control': --listen"
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

    func testRunAsyncAppParsesPathAndDownloadURLLikeRust() async {
        var requests: [CodexCLI.AppCommandRequest] = []

        for arguments in [
            ["app"],
            ["app", "/repo"],
            ["app", "--download-url", "https://example.test/Codex.dmg", "/repo"],
            ["app", "--download-url=https://example.test/Codex.dmg"]
        ] {
            let exitCode = await CodexCLI().runAsync(
                arguments: arguments,
                stderr: { _ in XCTFail("stderr should not be written for \(arguments)") },
                appRunner: { request in
                    requests.append(request)
                    return CodexCLI.CommandExecutionResult(exitCode: 0)
                }
            )
            XCTAssertEqual(exitCode, 0, "\(arguments)")
        }

        XCTAssertEqual(requests, [
            CodexCLI.AppCommandRequest(path: ".", downloadURLOverride: nil),
            CodexCLI.AppCommandRequest(path: "/repo", downloadURLOverride: nil),
            CodexCLI.AppCommandRequest(path: "/repo", downloadURLOverride: "https://example.test/Codex.dmg"),
            CodexCLI.AppCommandRequest(path: ".", downloadURLOverride: "https://example.test/Codex.dmg")
        ])
    }

    func testRunAsyncAppRejectsInvalidFormsBeforeRunner() async {
        let cases: [([String], String)] = [
            (
                ["app", "--download-url"],
                "codex-swift: missing value for --download-url"
            ),
            (
                ["app", "--verbose"],
                "codex-swift: unsupported option for command 'app': --verbose"
            ),
            (
                ["app", "/repo", "extra"],
                "codex-swift: unexpected argument for command 'app': extra"
            )
        ]

        for (arguments, expectedMessage) in cases {
            var stderr: [String] = []
            let exitCode = await CodexCLI().runAsync(
                arguments: arguments,
                stdout: { _ in XCTFail("stdout should not be written for \(arguments)") },
                stderr: { stderr.append($0) },
                appRunner: { _ in
                    XCTFail("runner should not be called for \(arguments)")
                    return CodexCLI.CommandExecutionResult(exitCode: 0)
                }
            )

            XCTAssertEqual(exitCode, 64, "\(arguments)")
            XCTAssertEqual(stderr, [expectedMessage], "\(arguments)")
        }
    }

    func testRunAsyncDebugModelsParsesBundledFlagAndOverrides() async {
        var stdout: [String] = []
        var receivedRequest: CodexCLI.DebugCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["--search", "-c", "model=\"gpt-5\"", "debug", "models", "--bundled"],
            stdout: { stdout.append($0) },
            stderr: { _ in XCTFail("stderr should not be written") },
            debugRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0, stdoutMessage: "models")
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(stdout, ["models"])
        XCTAssertEqual(receivedRequest, CodexCLI.DebugCommandRequest(
            action: .models(bundled: true),
            configOverrides: CliConfigOverrides(rawOverrides: [
                "model=\"gpt-5\"",
                "web_search=\"live\""
            ])
        ))
    }

    func testRunAsyncDebugPromptInputParsesPromptAndImagesLikeRust() async {
        var receivedAction: CodexCLI.DebugCommandAction?

        let exitCode = await CodexCLI().runAsync(
            arguments: [
                "-i",
                "root-a.png,root-b.png",
                "--image=root-c.png",
                "debug",
                "prompt-input",
                "hello",
                "--image",
                "a.png,b.png",
                "-i",
                "c.png"
            ],
            stderr: { _ in XCTFail("stderr should not be written") },
            debugRunner: { request in
                receivedAction = request.action
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(receivedAction, .promptInput(
            prompt: "hello",
            imagePaths: ["root-a.png", "root-b.png", "root-c.png", "a.png", "b.png", "c.png"]
        ))
    }

    func testRunAsyncDebugAppServerSendMessageV2ParsesMessage() async {
        var receivedAction: CodexCLI.DebugCommandAction?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["debug", "app-server", "send-message-v2", "hi"],
            stderr: { _ in XCTFail("stderr should not be written") },
            debugRunner: { request in
                receivedAction = request.action
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(receivedAction, .appServerSendMessageV2(message: "hi"))
    }

    func testRunAsyncDebugTraceReduceParsesOutput() async {
        var receivedAction: CodexCLI.DebugCommandAction?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["debug", "trace-reduce", "/tmp/trace", "-o", "/tmp/state.json"],
            stderr: { _ in XCTFail("stderr should not be written") },
            debugRunner: { request in
                receivedAction = request.action
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(receivedAction, .traceReduce(traceBundle: "/tmp/trace", output: "/tmp/state.json"))
    }

    func testRunAsyncDebugClearMemoriesParsesEmptySubcommand() async {
        var receivedAction: CodexCLI.DebugCommandAction?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["debug", "clear-memories"],
            stderr: { _ in XCTFail("stderr should not be written") },
            debugRunner: { request in
                receivedAction = request.action
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(receivedAction, .clearMemories)
    }

    func testRunAsyncDebugRejectsInvalidFormsBeforeRunner() async {
        let cases: [([String], String)] = [
            (
                ["debug"],
                "codex-swift: missing required subcommand for command 'debug': models|app-server|prompt-input|trace-reduce|clear-memories"
            ),
            (
                ["debug", "models", "extra"],
                "codex-swift: unexpected argument for command 'debug models': extra"
            ),
            (
                ["debug", "app-server"],
                "codex-swift: missing required subcommand for command 'debug app-server': send-message-v2"
            ),
            (
                ["debug", "app-server", "send-message-v2"],
                "codex-swift: missing required argument for command 'debug app-server send-message-v2': <USER_MESSAGE>"
            ),
            (
                ["debug", "prompt-input", "a", "b"],
                "codex-swift: unexpected argument for command 'debug prompt-input': b"
            ),
            (
                ["debug", "trace-reduce"],
                "codex-swift: missing required argument for command 'debug trace-reduce': <TRACE_BUNDLE>"
            )
        ]

        for (arguments, expectedMessage) in cases {
            var stderr: [String] = []
            let exitCode = await CodexCLI().runAsync(
                arguments: arguments,
                stdout: { _ in XCTFail("stdout should not be written for \(arguments)") },
                stderr: { stderr.append($0) },
                debugRunner: { _ in
                    XCTFail("runner should not be called for \(arguments)")
                    return CodexCLI.CommandExecutionResult(exitCode: 0)
                }
            )

            XCTAssertEqual(exitCode, 64, "\(arguments)")
            XCTAssertEqual(stderr, [expectedMessage], "\(arguments)")
        }
    }

    func testDebugRuntimeModelsBundledOutputsBundledCatalog() async throws {
        // Match the online variant below: Swift 6.2 XCTest can crash when
        // adjacent async tests complete entirely synchronously.
        await Task.yield()

        let result = try await DebugCommandRuntime.run(CodexCLI.DebugCommandRequest(
            action: .models(bundled: true)
        ))

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertNil(result.stderrMessage)

        let output = try XCTUnwrap(result.stdoutMessage)
        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: Data(output.utf8))
        XCTAssertEqual(decoded, try ModelsManager.bundledModelsResponse())
    }

    func testDebugRuntimeModelsOnlineUsesRawCatalogLoader() async throws {
        let expected = ModelsResponse(models: [])
        let result = try await DebugCommandRuntime.run(CodexCLI.DebugCommandRequest(
            action: .models(bundled: false)
        ), dependencies: DebugCommandRuntime.Dependencies(
            findCodexHome: { URL(fileURLWithPath: "/tmp/codex-home", isDirectory: true) },
            loadConfig: { _, _ in CodexRuntimeConfig(modelProvider: "openai") },
            loadRawModelCatalog: { _, _ in
                // Keep this async path suspended at least once; Swift 6.2 XCTest can crash
                // when this focused test completes entirely synchronously.
                await Task.yield()
                return expected
            }
        ))

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertNil(result.stderrMessage)
        let output = try XCTUnwrap(result.stdoutMessage)
        XCTAssertEqual(try JSONDecoder().decode(ModelsResponse.self, from: Data(output.utf8)), expected)
    }

    func testRunAsyncNewCommandHooksWithoutRunnersStillReportUnimplemented() async {
        for command in [
            "exec",
            "computer-use",
            "review",
            "plugin",
            "mcp-server",
            "app-server",
            "debug",
            "resume"
        ] {
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

    func testRunAsyncUpdateDelegatesToRunner() async {
        var receivedRequest: CodexCLI.UpdateCommandRequest?
        var stdout: [String] = []

        let exitCode = await CodexCLI().runAsync(
            arguments: ["update"],
            stdout: { stdout.append($0) },
            stderr: { _ in XCTFail("stderr should not be written") },
            updateRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0, stdoutMessage: "updated")
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(stdout, ["updated"])
        XCTAssertEqual(receivedRequest, CodexCLI.UpdateCommandRequest())
    }

    func testRunAsyncUpdateRejectsArguments() async {
        var stderr: [String] = []

        let exitCode = await CodexCLI().runAsync(
            arguments: ["update", "now"],
            stdout: { _ in XCTFail("stdout should not be written") },
            stderr: { stderr.append($0) },
            updateRunner: { _ in
                XCTFail("runner should not be called")
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 64)
        XCTAssertEqual(stderr, ["codex-swift: unexpected argument for command 'update': now"])
    }

    private struct TestError: Error, Equatable, CustomStringConvertible, Sendable {
        let description: String

        init(_ description: String) {
            self.description = description
        }
    }
}
