import XCTest
@testable import CodexCore

final class UnifiedExecErrorTests: XCTestCase {
    func testDescriptionsMatchRustThisErrorMessages() {
        XCTAssertEqual(
            String(describing: UnifiedExecError.createSession("pty failed")),
            "Failed to create unified exec session: pty failed"
        )
        XCTAssertEqual(
            String(describing: UnifiedExecError.unknownSessionID(processID: "42")),
            "Unknown session id 42"
        )
        XCTAssertEqual(
            String(describing: UnifiedExecError.writeToStdin),
            "failed to write to stdin"
        )
        XCTAssertEqual(
            String(describing: UnifiedExecError.stdinClosed),
            "stdin is closed for this session; rerun exec_command with tty=true to keep stdin open"
        )
        XCTAssertEqual(
            String(describing: UnifiedExecError.missingCommandLine),
            "missing command line for unified exec request"
        )
        XCTAssertEqual(
            String(describing: UnifiedExecError.sandboxDenied(
                message: "blocked",
                output: output()
            )),
            "Command denied by sandbox: blocked"
        )
    }

    func testConvenienceConstructorsPreserveAssociatedValues() {
        let execOutput = output(exitCode: 126)
        XCTAssertEqual(
            UnifiedExecError.createSession("no tty"),
            .createSession(message: "no tty")
        )
        XCTAssertEqual(
            UnifiedExecError.makeSandboxDenied(message: "no", output: execOutput),
            .sandboxDenied(message: "no", output: execOutput)
        )
    }

    func testSandboxDeniedUserFacingMessageUsesAggregatedOutputLikeRust() {
        let error = UnifiedExecError.sandboxDenied(
            message: "blocked",
            output: output(
                exitCode: 77,
                stdout: "",
                stderr: "",
                aggregatedOutput: "aggregate detail"
            )
        )

        XCTAssertEqual(error.userFacingMessage, "aggregate detail")
    }

    func testSandboxDeniedUserFacingMessageReportsBothStreamsLikeRust() {
        let error = UnifiedExecError.sandboxDenied(
            message: "blocked",
            output: output(
                exitCode: 9,
                stdout: "stdout detail",
                stderr: "stderr detail",
                aggregatedOutput: ""
            )
        )

        XCTAssertEqual(error.userFacingMessage, "stderr detail\nstdout detail")
    }

    func testSandboxDeniedUserFacingMessageReportsStdoutWhenNoStderrLikeRust() {
        let error = UnifiedExecError.sandboxDenied(
            message: "blocked",
            output: output(
                exitCode: 11,
                stdout: "stdout only",
                stderr: "",
                aggregatedOutput: ""
            )
        )

        XCTAssertEqual(error.userFacingMessage, "stdout only")
    }

    func testSandboxDeniedUserFacingMessageReportsExitCodeWhenOutputIsUnavailableLikeRust() {
        let error = UnifiedExecError.sandboxDenied(
            message: "blocked",
            output: output(
                exitCode: 13,
                stdout: "",
                stderr: "",
                aggregatedOutput: ""
            )
        )

        XCTAssertEqual(
            error.userFacingMessage,
            "command failed inside sandbox with exit code 13"
        )
    }

    func testSandboxDeniedUserFacingMessageTruncatesLikeRust() {
        let longOutput = String(repeating: "a", count: 3_000)
        let error = UnifiedExecError.sandboxDenied(
            message: "blocked",
            output: output(
                exitCode: 1,
                stdout: "",
                stderr: "",
                aggregatedOutput: longOutput
            )
        )

        XCTAssertLessThan(error.userFacingMessage.utf8.count, longOutput.utf8.count)
        XCTAssertTrue(error.userFacingMessage.contains("chars truncated"))
    }

    private func output(exitCode: Int = 1) -> ExecToolCallOutput {
        output(
            exitCode: exitCode,
            stdout: "stdout",
            stderr: "stderr",
            aggregatedOutput: "output"
        )
    }

    private func output(
        exitCode: Int,
        stdout: String,
        stderr: String,
        aggregatedOutput: String
    ) -> ExecToolCallOutput {
        ExecToolCallOutput(
            exitCode: exitCode,
            stdout: stdout,
            stderr: stderr,
            aggregatedOutput: aggregatedOutput,
            duration: 0.2
        )
    }
}
