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
                "--full-auto",
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
                action: .macos(fullAuto: true, logDenials: true, command: ["echo", "hello"]),
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
            arguments: ["debug", "landlock", "--full-auto", "echo", "ok"],
            stderr: { _ in XCTFail("stderr should not be written") },
            sandboxRunner: { request in
                receivedActions.append(request.action)
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(seatbeltExitCode, 0)
        XCTAssertEqual(landlockExitCode, 0)
        XCTAssertEqual(receivedActions, [
            .macos(fullAuto: false, logDenials: false, command: ["echo", "ok"]),
            .linux(fullAuto: true, command: ["echo", "ok"])
        ])
    }

    func testRunAsyncSandboxWindowsDelegatesToRunner() async {
        var receivedRequest: CodexCLI.SandboxCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["sandbox", "windows", "--full-auto", "cmd", "/c", "echo", "ok"],
            stderr: { _ in XCTFail("stderr should not be written") },
            sandboxRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(receivedRequest?.action, .windows(fullAuto: true, command: ["cmd", "/c", "echo", "ok"]))
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
        XCTAssertEqual(receivedRequest?.action, .macos(fullAuto: false, logDenials: false, command: ["-weird"]))
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
