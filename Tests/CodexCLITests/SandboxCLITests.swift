import CodexCLI
import CodexCore
import XCTest

final class SandboxCLITests: XCTestCase {
    func testRunAsyncSandboxMacosDelegatesToRunnerWithFlagsAndOverrides() async {
        var stdout: [String] = []
        var stderr: [String] = []
        var receivedRequest: CodexCLI.SandboxCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: [
                "-c",
                "sandbox_mode=\"read-only\"",
                "sandbox",
                "macos",
                "--log-denials",
                "echo",
                "hello"
            ],
            stdout: { stdout.append($0) },
            stderr: { stderr.append($0) },
            sandboxRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0, stdoutMessage: "hello")
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(stdout, ["hello"])
        XCTAssertTrue(stderr.isEmpty)
        XCTAssertEqual(
            receivedRequest,
            CodexCLI.SandboxCommandRequest(
                action: .macos(
                    profile: CodexCLI.SandboxProfileOptions(),
                    allowUnixSockets: [],
                    logDenials: true,
                    command: ["echo", "hello"]
                ),
                configOverrides: CliConfigOverrides(rawOverrides: ["sandbox_mode=\"read-only\""])
            )
        )
    }

    func testRunAsyncSandboxAliasesMatchRustSubcommands() async {
        var receivedActions: [CodexCLI.SandboxCommandAction] = []

        let seatbeltExitCode = await CodexCLI().runAsync(
            arguments: ["sandbox", "seatbelt", "echo", "ok"],
            stderr: { _ in XCTFail("stderr should not be written") },
            sandboxRunner: { request in
                receivedActions.append(request.action)
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        let landlockExitCode = await CodexCLI().runAsync(
            arguments: ["sandbox", "landlock", "echo", "ok"],
            stderr: { _ in XCTFail("stderr should not be written") },
            sandboxRunner: { request in
                receivedActions.append(request.action)
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(seatbeltExitCode, 0)
        XCTAssertEqual(landlockExitCode, 0)
        XCTAssertEqual(receivedActions, [
            .macos(
                profile: CodexCLI.SandboxProfileOptions(),
                allowUnixSockets: [],
                logDenials: false,
                command: ["echo", "ok"]
            ),
            .linux(profile: CodexCLI.SandboxProfileOptions(), command: ["echo", "ok"])
        ])
    }

    func testRunAsyncSandboxParsesRustPermissionProfileOptions() async {
        var receivedActions: [CodexCLI.SandboxCommandAction] = []

        let macosExitCode = await CodexCLI().runAsync(
            arguments: [
                "sandbox",
                "macos",
                "--permissions-profile",
                ":workspace",
                "-C",
                "/tmp/work",
                "--include-managed-config",
                "--allow-unix-socket",
                "/tmp/socket",
                "--",
                "echo",
                "ok"
            ],
            stderr: { _ in XCTFail("stderr should not be written") },
            sandboxRunner: { request in
                receivedActions.append(request.action)
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        let linuxExitCode = await CodexCLI().runAsync(
            arguments: [
                "sandbox",
                "linux",
                "--permissions-profile=:workspace",
                "--cd=/tmp/work",
                "echo",
                "ok"
            ],
            stderr: { _ in XCTFail("stderr should not be written") },
            sandboxRunner: { request in
                receivedActions.append(request.action)
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(macosExitCode, 0)
        XCTAssertEqual(linuxExitCode, 0)
        XCTAssertEqual(receivedActions, [
            .macos(
                profile: CodexCLI.SandboxProfileOptions(
                    permissionsProfile: ":workspace",
                    cwd: "/tmp/work",
                    includeManagedConfig: true
                ),
                allowUnixSockets: ["/tmp/socket"],
                logDenials: false,
                command: ["echo", "ok"]
            ),
            .linux(
                profile: CodexCLI.SandboxProfileOptions(
                    permissionsProfile: ":workspace",
                    cwd: "/tmp/work"
                ),
                command: ["echo", "ok"]
            )
        ])
    }

    func testRunAsyncSandboxWindowsDelegatesToRunner() async {
        var receivedRequest: CodexCLI.SandboxCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["sandbox", "windows", "cmd", "/c", "echo", "ok"],
            stderr: { _ in XCTFail("stderr should not be written") },
            sandboxRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(
            receivedRequest?.action,
            .windows(
                profile: CodexCLI.SandboxProfileOptions(),
                command: ["cmd", "/c", "echo", "ok"]
            )
        )
    }

    func testRunAsyncSandboxPreservesFlagLikeCommandAfterDoubleDash() async {
        var receivedRequest: CodexCLI.SandboxCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["sandbox", "macos", "--", "-weird"],
            stderr: { _ in XCTFail("stderr should not be written") },
            sandboxRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(
            receivedRequest?.action,
            .macos(
                profile: CodexCLI.SandboxProfileOptions(),
                allowUnixSockets: [],
                logDenials: false,
                command: ["-weird"]
            )
        )
    }

    func testRunAsyncSandboxRejectsInvalidFormsBeforeRunner() async {
        let cases: [([String], String)] = [
            (
                ["sandbox"],
                "codex-swift: missing required subcommand for command 'sandbox': macos|linux|windows"
            ),
            (
                ["sandbox", "freebsd", "echo", "ok"],
                "codex-swift: unsupported sandbox subcommand: freebsd"
            ),
            (
                ["sandbox", "macos"],
                "codex-swift: missing required argument for command 'sandbox macos': <COMMAND>"
            ),
            (
                ["sandbox", "linux", "--log-denials", "echo", "ok"],
                "codex-swift: unsupported option for command 'sandbox linux': --log-denials"
            ),
            (
                ["sandbox", "linux", "--full-auto", "echo", "ok"],
                "codex-swift: unsupported option for command 'sandbox linux': --full-auto"
            ),
            (
                ["sandbox", "macos", "-C", "/tmp", "echo", "ok"],
                "codex-swift: --cd and --include-managed-config require --permissions-profile"
            ),
            (
                ["sandbox", "linux", "--allow-unix-socket", "/tmp/socket", "echo", "ok"],
                "codex-swift: unsupported option for command 'sandbox linux': --allow-unix-socket"
            )
        ]

        for (arguments, expectedMessage) in cases {
            var stderr: [String] = []
            let exitCode = await CodexCLI().runAsync(
                arguments: arguments,
                stdout: { _ in XCTFail("stdout should not be written for \(arguments)") },
                stderr: { stderr.append($0) },
                sandboxRunner: { _ in
                    XCTFail("runner should not be called for \(arguments)")
                    return CodexCLI.CommandExecutionResult(exitCode: 0)
                }
            )

            XCTAssertEqual(exitCode, 64, "\(arguments)")
            XCTAssertEqual(stderr, [expectedMessage], "\(arguments)")
        }
    }

    func testRunAsyncSandboxWithoutRunnerStillReportsUnimplemented() async {
        var stderr: [String] = []

        let exitCode = await CodexCLI().runAsync(
            arguments: ["sandbox", "macos", "echo", "ok"],
            stdout: { _ in XCTFail("stdout should not be written") },
            stderr: { stderr.append($0) }
        )

        XCTAssertEqual(exitCode, 78)
        XCTAssertEqual(stderr, ["codex-swift: command 'sandbox' is registered but its runtime port is not complete yet."])
    }
}
