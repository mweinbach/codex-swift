import CodexCore
import XCTest

final class HookPostToolUseTests: XCTestCase {
    func testCommandInputUsesRequestToolName() throws {
        var request = try requestForToolUse("call-apply-patch")
        request.toolName = "apply_patch"

        let inputJSON = try HookPostToolUse.commandInputJSON(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(inputJSON.utf8)) as? [String: Any])

        XCTAssertEqual(object["hook_event_name"] as? String, "PostToolUse")
        XCTAssertEqual(object["tool_name"] as? String, "apply_patch")
        XCTAssertEqual(object["tool_use_id"] as? String, "call-apply-patch")
        XCTAssertEqual((object["tool_response"] as? [String: Any])?["ok"] as? Bool, true)
    }

    func testBlockDecisionSurfacesFeedbackWithoutStopping() throws {
        let parsed = try parseCompleted(stdout: #"{"decision":"block","reason":"bash output looked sketchy"}"#)

        XCTAssertEqual(parsed.data, HookPostToolUseHandlerData(
            feedbackMessagesForModel: ["bash output looked sketchy"]
        ))
        XCTAssertEqual(parsed.completed.run.status, .blocked)
        XCTAssertEqual(parsed.completed.run.entries, [
            HookOutputEntry(kind: .feedback, text: "bash output looked sketchy")
        ])
    }

    func testAdditionalContextIsRecorded() throws {
        let parsed = try parseCompleted(
            stdout: #"{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"Remember the bash cleanup note."}}"#
        )

        XCTAssertEqual(parsed.data, HookPostToolUseHandlerData(
            additionalContextsForModel: ["Remember the bash cleanup note."]
        ))
        XCTAssertEqual(parsed.completed.run.entries, [
            HookOutputEntry(kind: .context, text: "Remember the bash cleanup note.")
        ])
    }

    func testUnsupportedUpdatedMCPToolOutputFailsOpen() throws {
        let parsed = try parseCompleted(
            stdout: #"{"hookSpecificOutput":{"hookEventName":"PostToolUse","updatedMCPToolOutput":{"ok":true}}}"#
        )

        XCTAssertEqual(parsed.data, HookPostToolUseHandlerData())
        XCTAssertEqual(parsed.completed.run.status, .failed)
        XCTAssertEqual(parsed.completed.run.entries, [
            HookOutputEntry(kind: .error, text: "PostToolUse hook returned unsupported updatedMCPToolOutput")
        ])
    }

    func testExitTwoSurfacesFeedbackToModelWithoutBlocking() throws {
        let parsed = try parseCompleted(exitCode: 2, stdout: "", stderr: "post hook says pause")

        XCTAssertEqual(parsed.data, HookPostToolUseHandlerData(
            feedbackMessagesForModel: ["post hook says pause"]
        ))
        XCTAssertEqual(parsed.completed.run.status, .completed)
        XCTAssertEqual(parsed.completed.run.entries, [
            HookOutputEntry(kind: .feedback, text: "post hook says pause")
        ])
    }

    func testContinueFalseStopsWithReason() throws {
        let parsed = try parseCompleted(
            stdout: #"{"continue":false,"stopReason":"halt after bash output","reason":"post-tool hook says stop"}"#
        )

        XCTAssertEqual(parsed.data, HookPostToolUseHandlerData(
            shouldStop: true,
            stopReason: "halt after bash output",
            feedbackMessagesForModel: ["post-tool hook says stop"]
        ))
        XCTAssertEqual(parsed.completed.run.status, .stopped)
        XCTAssertEqual(parsed.completed.run.entries, [
            HookOutputEntry(kind: .stop, text: "halt after bash output")
        ])
    }

    func testInvalidAndPlainStdoutHandling() throws {
        let plain = try parseCompleted(stdout: "plain text only")
        let invalid = try parseCompleted(stdout: "{\"decision\":\n")

        XCTAssertEqual(plain.data, HookPostToolUseHandlerData())
        XCTAssertEqual(plain.completed.run.status, .completed)
        XCTAssertEqual(plain.completed.run.entries, [])
        XCTAssertEqual(invalid.completed.run.status, .failed)
        XCTAssertEqual(invalid.completed.run.entries, [
            HookOutputEntry(kind: .error, text: "hook returned invalid post-tool-use JSON output")
        ])
    }

    func testExitCodeTwoWithoutStderrAndNonzeroFailures() throws {
        let missingFeedback = try parseCompleted(exitCode: 2, stdout: "", stderr: " ")
        let nonzero = try parseCompleted(exitCode: 7, stdout: "", stderr: "")
        let missingStatus = try parseCompleted(exitCode: nil, stdout: "", stderr: "")

        XCTAssertEqual(missingFeedback.completed.run.status, .failed)
        XCTAssertEqual(missingFeedback.completed.run.entries, [
            HookOutputEntry(kind: .error, text: "PostToolUse hook exited with code 2 but did not write feedback to stderr")
        ])
        XCTAssertEqual(nonzero.completed.run.entries, [
            HookOutputEntry(kind: .error, text: "hook exited with code 7")
        ])
        XCTAssertEqual(missingStatus.completed.run.entries, [
            HookOutputEntry(kind: .error, text: "hook exited without a status code")
        ])
    }

    func testPreviewAndCompletedRunIDsIncludeToolUseID() throws {
        let request = try requestForToolUse("tool-call-456")
        let runs = try HookPostToolUse.preview(handlers: [handler()], request: request, startedAt: 1)

        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].id, "post-tool-use:0:/tmp/hooks.json:tool-call-456")

        let parsed = try parseCompleted(stdout: "")
        let completed = HookPreToolUse.hookCompletedForToolUse(parsed.completed, toolUseID: request.toolUseID)

        XCTAssertEqual(completed.run.id, runs[0].id)
    }

    func testRunAggregatesFeedbackStopAndAdditionalContexts() async throws {
        let handlers = try [
            handler(command: #"printf %s '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"ctx"}}'"#),
            handler(command: #"printf %s '{"decision":"block","reason":"feedback"}'"#, displayOrder: 1),
            handler(command: #"printf %s '{"continue":false,"stopReason":"stop now"}'"#, displayOrder: 2)
        ]

        let outcome = await HookPostToolUse.run(
            handlers: handlers,
            shell: HookCommandShell(program: "/bin/sh", arguments: ["-c"]),
            request: try requestForToolUse("tool-call-456")
        )

        XCTAssertTrue(outcome.shouldStop)
        XCTAssertEqual(outcome.stopReason, "stop now")
        XCTAssertEqual(outcome.additionalContexts, ["ctx"])
        XCTAssertEqual(outcome.feedbackMessage, "feedback\n\nstop now")
        XCTAssertEqual(outcome.hookEvents.map(\.run.status), [.completed, .blocked, .stopped])
    }

    private func parseCompleted(
        exitCode: Int32? = 0,
        stdout: String,
        stderr: String = ""
    ) throws -> ParsedHookHandler<HookPostToolUseHandlerData> {
        try HookPostToolUse.parseCompleted(
            handler: handler(),
            runResult: HookCommandRunResult(
                startedAt: 1,
                completedAt: 2,
                durationMs: 1,
                exitCode: exitCode,
                stdout: stdout,
                stderr: stderr
            ),
            turnID: "turn-1"
        )
    }

    private func handler(
        command: String = "echo hook",
        displayOrder: Int64 = 0
    ) throws -> ConfiguredHookHandler {
        try ConfiguredHookHandler(
            eventName: .postToolUse,
            matcher: "^Bash$",
            command: command,
            timeoutSec: 5,
            statusMessage: "running post tool use hook",
            sourcePath: AbsolutePath(absolutePath: "/tmp/hooks.json"),
            source: .user,
            displayOrder: displayOrder
        )
    }

    private func requestForToolUse(_ toolUseID: String) throws -> HookPostToolUseRequest {
        try HookPostToolUseRequest(
            sessionID: ThreadId(),
            turnID: "turn-1",
            cwd: AbsolutePath(absolutePath: "/tmp"),
            model: "gpt-test",
            permissionMode: "default",
            toolName: "Bash",
            toolUseID: toolUseID,
            toolInput: .object(["command": .string("echo hello")]),
            toolResponse: .object(["ok": .bool(true)])
        )
    }
}
