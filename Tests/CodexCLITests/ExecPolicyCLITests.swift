import CodexCLI
import XCTest

final class ExecPolicyCLITests: XCTestCase {
    func testRunAsyncExecPolicyCheckDelegatesToRunner() async {
        var stdout: [String] = []
        var stderr: [String] = []
        var receivedRequest: CodexCLI.ExecPolicyCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: [
                "execpolicy",
                "check",
                "--rules",
                "first.rules",
                "-r",
                "second.rules",
                "--pretty",
                "git",
                "--push",
                "origin"
            ],
            stdout: { stdout.append($0) },
            stderr: { stderr.append($0) },
            execPolicyRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0, stdoutMessage: #"{"matchedRules":[]}"#)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(stdout, [#"{"matchedRules":[]}"#])
        XCTAssertTrue(stderr.isEmpty)
        XCTAssertEqual(
            receivedRequest?.action,
            .check(
                rules: ["first.rules", "second.rules"],
                pretty: true,
                command: ["git", "--push", "origin"]
            )
        )
    }

    func testRunAsyncExecPolicyCheckAllowsHyphenCommandAfterDoubleDash() async {
        var receivedRequest: CodexCLI.ExecPolicyCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["execpolicy", "check", "--rules=policy.rules", "--", "-weird"],
            stdout: { _ in },
            stderr: { _ in },
            execPolicyRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(
            receivedRequest?.action,
            .check(rules: ["policy.rules"], pretty: false, command: ["-weird"])
        )
    }

    func testRunAsyncExecPolicyCheckAllowsHyphenCommandWithoutDoubleDash() async {
        var receivedRequest: CodexCLI.ExecPolicyCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["execpolicy", "check", "--rules=policy.rules", "--flaggy"],
            stdout: { _ in },
            stderr: { _ in },
            execPolicyRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(
            receivedRequest?.action,
            .check(rules: ["policy.rules"], pretty: false, command: ["--flaggy"])
        )
    }

    func testRunAsyncExecPolicyCheckRejectsCompactShortRulesLikeRustClap() async {
        var stderr: [String] = []

        let exitCode = await CodexCLI().runAsync(
            arguments: ["execpolicy", "check", "-rpolicy.rules", "--flaggy"],
            stdout: { _ in XCTFail("stdout should not be written") },
            stderr: { stderr.append($0) },
            execPolicyRunner: { _ in
                XCTFail("runner should not be called without Rust-recognized rules")
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 2)
        XCTAssertEqual(stderr, [
            """
            error: the following required arguments were not provided:
              --rules <PATH>

            Usage: codex execpolicy check --rules <PATH> <COMMAND>...

            For more information, try '--help'.
            """
        ])
    }

    func testRunAsyncExecPolicyCheckRequiresRules() async {
        var stderr: [String] = []

        let exitCode = await CodexCLI().runAsync(
            arguments: ["execpolicy", "check", "git", "status"],
            stdout: { _ in XCTFail("stdout should not be written") },
            stderr: { stderr.append($0) },
            execPolicyRunner: { _ in
                XCTFail("runner should not be called without rules")
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 2)
        XCTAssertEqual(stderr, [
            """
            error: the following required arguments were not provided:
              --rules <PATH>

            Usage: codex execpolicy check --rules <PATH> <COMMAND>...

            For more information, try '--help'.
            """
        ])
    }

    func testRunAsyncExecPolicyCheckRequiresCommand() async {
        var stderr: [String] = []

        let exitCode = await CodexCLI().runAsync(
            arguments: ["execpolicy", "check", "--rules", "policy.rules"],
            stdout: { _ in XCTFail("stdout should not be written") },
            stderr: { stderr.append($0) },
            execPolicyRunner: { _ in
                XCTFail("runner should not be called without command")
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 2)
        XCTAssertEqual(stderr, [
            """
            error: the following required arguments were not provided:
              <COMMAND>...

            Usage: codex execpolicy check --rules <PATH> <COMMAND>...

            For more information, try '--help'.
            """
        ])
    }
}
