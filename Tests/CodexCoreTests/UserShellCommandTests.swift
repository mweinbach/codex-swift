import CodexCore
import XCTest

final class UserShellCommandTests: XCTestCase {
    func testDetectsUserShellCommandTextVariants() {
        XCTAssertTrue(UserShellCommand.isUserShellCommandText(
            "<user_shell_command>\necho hi\n</user_shell_command>"
        ))
        XCTAssertTrue(UserShellCommand.isUserShellCommandText(
            " \n\t<USER_SHELL_COMMAND>\necho hi\n</USER_SHELL_COMMAND>"
        ))
        XCTAssertFalse(UserShellCommand.isUserShellCommandText("echo hi"))
    }

    func testFormatsBasicRecordItem() throws {
        let execOutput = ExecToolCallOutput(
            exitCode: 0,
            stdout: "hi",
            stderr: "",
            aggregatedOutput: "hi",
            duration: 1
        )

        let item = UserShellCommand.recordItem(
            command: "echo hi",
            execOutput: execOutput,
            truncationPolicy: .bytes(10_000)
        )

        guard case let .message(role, content) = item else {
            return XCTFail("Expected message item")
        }
        XCTAssertEqual(role, "user")
        XCTAssertEqual(content, [
            .inputText(text: "<user_shell_command>\n<command>\necho hi\n</command>\n<result>\nExit code: 0\nDuration: 1.0000 seconds\nOutput:\nhi\n</result>\n</user_shell_command>")
        ])
    }

    func testUsesAggregatedOutputOverStreams() {
        let execOutput = ExecToolCallOutput(
            exitCode: 42,
            stdout: "stdout-only",
            stderr: "stderr-only",
            aggregatedOutput: "combined output wins",
            duration: 0.120
        )

        XCTAssertEqual(
            UserShellCommand.formatRecord(
                command: "false",
                execOutput: execOutput,
                truncationPolicy: .bytes(10_000)
            ),
            "<user_shell_command>\n<command>\nfalse\n</command>\n<result>\nExit code: 42\nDuration: 0.1200 seconds\nOutput:\ncombined output wins\n</result>\n</user_shell_command>"
        )
    }

    func testTimedOutOutputMatchesRustPrefix() {
        let execOutput = ExecToolCallOutput(
            exitCode: 124,
            stdout: "",
            stderr: "",
            aggregatedOutput: "partial",
            duration: 1.2349,
            timedOut: true
        )

        XCTAssertEqual(
            ExecOutputFormatter.buildContentWithTimeout(execOutput),
            "command timed out after 1234 milliseconds\npartial"
        )
    }

    func testRecordOutputIsTruncatedWithPolicy() {
        let execOutput = ExecToolCallOutput(
            exitCode: 0,
            stdout: "stdout-only",
            stderr: "stderr-only",
            aggregatedOutput: "this is an example of a long output that should be truncated",
            duration: 0.25
        )

        XCTAssertEqual(
            UserShellCommand.formatRecord(
                command: "generate-output",
                execOutput: execOutput,
                truncationPolicy: .bytes(30)
            ),
            "<user_shell_command>\n<command>\ngenerate-output\n</command>\n<result>\nExit code: 0\nDuration: 0.2500 seconds\nOutput:\nTotal output lines: 1\n\nthis is an exam…30 chars truncated…ld be truncated\n</result>\n</user_shell_command>"
        )
    }

    func testResponseItemMessageWireShape() throws {
        let item = UserShellCommand.recordItem(
            command: "echo hi",
            execOutput: ExecToolCallOutput(
                exitCode: 0,
                stdout: "hi",
                stderr: "",
                aggregatedOutput: "hi",
                duration: 1
            ),
            truncationPolicy: .bytes(10_000)
        )

        let data = try JSONEncoder().encode(item)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "message")
        XCTAssertEqual(object["role"] as? String, "user")

        let decoded = try JSONDecoder().decode(ResponseItem.self, from: data)
        XCTAssertEqual(decoded, item)
    }
}
