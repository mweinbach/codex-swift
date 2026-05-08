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

    private func output(exitCode: Int = 1) -> ExecToolCallOutput {
        ExecToolCallOutput(
            exitCode: exitCode,
            stdout: "stdout",
            stderr: "stderr",
            aggregatedOutput: "output",
            duration: 0.2
        )
    }
}
