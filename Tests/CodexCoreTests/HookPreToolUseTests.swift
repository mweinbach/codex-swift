import CodexCore
import XCTest

final class HookPreToolUseTests: XCTestCase {
    func testCommandInputUsesRequestToolName() throws {
        var request = try requestForToolUse("call-apply-patch")
        request.toolName = "apply_patch"

        let inputJSON = try HookPreToolUse.commandInputJSON(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(inputJSON.utf8)) as? [String: Any])

        XCTAssertEqual(object["hook_event_name"] as? String, "PreToolUse")
        XCTAssertEqual(object["tool_name"] as? String, "apply_patch")
        XCTAssertEqual(object["tool_use_id"] as? String, "call-apply-patch")
        XCTAssertEqual(object["transcript_path"] as? NSNull, NSNull())
        XCTAssertEqual((object["tool_input"] as? [String: Any])?["command"] as? String, "echo hello")
    }

    func testPermissionDecisionDenyBlocksProcessing() throws {
        let parsed = try parseCompleted(
            stdout: #"{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"do not run that"}}"#
        )

        XCTAssertEqual(parsed.data, HookPreToolUseHandlerData(shouldBlock: true, blockReason: "do not run that"))
        XCTAssertEqual(parsed.completed.run.status, .blocked)
        XCTAssertEqual(parsed.completed.run.entries, [
            HookOutputEntry(kind: .feedback, text: "do not run that")
        ])
    }

    func testDeprecatedBlockDecisionWithAdditionalContextBlocksProcessing() throws {
        let parsed = try parseCompleted(
            stdout: #"{"decision":"block","reason":"do not run that","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"remember this"}}"#
        )

        XCTAssertEqual(parsed.data, HookPreToolUseHandlerData(
            shouldBlock: true,
            blockReason: "do not run that",
            additionalContextsForModel: ["remember this"]
        ))
        XCTAssertEqual(parsed.completed.run.status, .blocked)
        XCTAssertEqual(parsed.completed.run.entries, [
            HookOutputEntry(kind: .context, text: "remember this"),
            HookOutputEntry(kind: .feedback, text: "do not run that")
        ])
    }

    func testUnsupportedPermissionDecisionFailsOpen() throws {
        let parsed = try parseCompleted(
            stdout: #"{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"please confirm"}}"#
        )

        XCTAssertEqual(parsed.data, HookPreToolUseHandlerData())
        XCTAssertEqual(parsed.completed.run.status, .failed)
        XCTAssertEqual(parsed.completed.run.entries, [
            HookOutputEntry(kind: .error, text: "PreToolUse hook returned unsupported permissionDecision:ask")
        ])
    }

    func testPlainStdoutIsIgnored() throws {
        let parsed = try parseCompleted(stdout: "hook ran successfully\n")

        XCTAssertEqual(parsed.data, HookPreToolUseHandlerData())
        XCTAssertEqual(parsed.completed.run.status, .completed)
        XCTAssertEqual(parsed.completed.run.entries, [])
    }

    func testInvalidJSONLikeStdoutFailsInsteadOfBecomingNoop() throws {
        let parsed = try parseCompleted(stdout: "{\"decision\":\n")

        XCTAssertEqual(parsed.data, HookPreToolUseHandlerData())
        XCTAssertEqual(parsed.completed.run.status, .failed)
        XCTAssertEqual(parsed.completed.run.entries, [
            HookOutputEntry(kind: .error, text: "hook returned invalid pre-tool-use JSON output")
        ])
    }

    func testExitCodeTwoBlocksProcessing() throws {
        let parsed = try parseCompleted(exitCode: 2, stdout: "", stderr: "blocked by policy\n")

        XCTAssertEqual(parsed.data, HookPreToolUseHandlerData(shouldBlock: true, blockReason: "blocked by policy"))
        XCTAssertEqual(parsed.completed.run.status, .blocked)
        XCTAssertEqual(parsed.completed.run.entries, [
            HookOutputEntry(kind: .feedback, text: "blocked by policy")
        ])
    }

    func testExitCodeTwoWithoutStderrFails() throws {
        let parsed = try parseCompleted(exitCode: 2, stdout: "", stderr: "  \n")

        XCTAssertEqual(parsed.data, HookPreToolUseHandlerData())
        XCTAssertEqual(parsed.completed.run.status, .failed)
        XCTAssertEqual(parsed.completed.run.entries, [
            HookOutputEntry(
                kind: .error,
                text: "PreToolUse hook exited with code 2 but did not write a blocking reason to stderr"
            )
        ])
    }

    func testNonzeroExitAndMissingStatusFail() throws {
        let nonzero = try parseCompleted(exitCode: 7, stdout: "", stderr: "")
        let missing = try parseCompleted(exitCode: nil, stdout: "", stderr: "")

        XCTAssertEqual(nonzero.completed.run.status, .failed)
        XCTAssertEqual(nonzero.completed.run.entries, [
            HookOutputEntry(kind: .error, text: "hook exited with code 7")
        ])
        XCTAssertEqual(missing.completed.run.status, .failed)
        XCTAssertEqual(missing.completed.run.entries, [
            HookOutputEntry(kind: .error, text: "hook exited without a status code")
        ])
    }

    func testPreviewAndCompletedRunIDsIncludeToolUseID() throws {
        let request = try requestForToolUse("tool-call-123")
        let runs = try HookPreToolUse.preview(handlers: [handler()], request: request, startedAt: 1)

        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].id, "pre-tool-use:0:/tmp/hooks.json:tool-call-123")

        let parsed = try parseCompleted(stdout: "")
        let completed = HookPreToolUse.hookCompletedForToolUse(parsed.completed, toolUseID: request.toolUseID)

        XCTAssertEqual(completed.run.id, runs[0].id)
    }

    func testRunAggregatesBlockingAndAdditionalContexts() async throws {
        let handlers = try [
            handler(command: #"printf %s '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"ctx"}}'"#),
            handler(command: #"printf %s '{"decision":"block","reason":"nope"}'"#, displayOrder: 1)
        ]

        let outcome = await HookPreToolUse.run(
            handlers: handlers,
            shell: HookCommandShell(program: "/bin/sh", arguments: ["-c"]),
            request: try requestForToolUse("tool-call-123")
        )

        XCTAssertTrue(outcome.shouldBlock)
        XCTAssertEqual(outcome.blockReason, "nope")
        XCTAssertEqual(outcome.additionalContexts, ["ctx"])
        XCTAssertEqual(outcome.hookEvents.map(\.run.status), [.completed, .blocked])
        XCTAssertEqual(outcome.hookEvents.map(\.run.id), [
            "pre-tool-use:0:/tmp/hooks.json:tool-call-123",
            "pre-tool-use:1:/tmp/hooks.json:tool-call-123"
        ])
    }

    private func parseCompleted(
        exitCode: Int32? = 0,
        stdout: String,
        stderr: String = ""
    ) throws -> ParsedHookHandler<HookPreToolUseHandlerData> {
        try HookPreToolUse.parseCompleted(
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
            eventName: .preToolUse,
            matcher: "^Bash$",
            command: command,
            timeoutSec: 5,
            sourcePath: AbsolutePath(absolutePath: "/tmp/hooks.json"),
            source: .user,
            displayOrder: displayOrder
        )
    }

    private func requestForToolUse(_ toolUseID: String) throws -> HookPreToolUseRequest {
        try HookPreToolUseRequest(
            sessionID: ThreadId(),
            turnID: "turn-1",
            cwd: AbsolutePath(absolutePath: "/tmp"),
            model: "gpt-test",
            permissionMode: "default",
            toolName: "Bash",
            toolUseID: toolUseID,
            toolInput: .object(["command": .string("echo hello")])
        )
    }
}
