import CodexCore
import XCTest

final class HookUserPromptSubmitTests: XCTestCase {
    func testCommandInputIncludesPromptAndTurnID() throws {
        let inputJSON = try HookUserPromptSubmit.commandInputJSON(try request(prompt: "run tests"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(inputJSON.utf8)) as? [String: Any])

        XCTAssertEqual(object["hook_event_name"] as? String, "UserPromptSubmit")
        XCTAssertEqual(object["turn_id"] as? String, "turn-1")
        XCTAssertEqual(object["prompt"] as? String, "run tests")
        XCTAssertEqual(object["transcript_path"] as? NSNull, NSNull())
    }

    func testPreviewIgnoresMatchers() throws {
        let handlers = try [
            handler(matcher: "^never$", displayOrder: 0),
            handler(matcher: nil, displayOrder: 1),
        ]

        let runs = HookUserPromptSubmit.preview(handlers: handlers, startedAt: 1)

        XCTAssertEqual(runs.map(\.id), [
            "user-prompt-submit:0:/tmp/hooks.json",
            "user-prompt-submit:1:/tmp/hooks.json",
        ])
    }

    func testPlainStdoutBecomesModelContext() throws {
        let parsed = try parseCompleted(stdout: "remember project context\n")

        XCTAssertEqual(parsed.data, HookUserPromptSubmitHandlerData(
            additionalContextsForModel: ["remember project context"]
        ))
        XCTAssertEqual(parsed.completed.run.entries, [
            HookOutputEntry(kind: .context, text: "remember project context")
        ])
    }

    func testContinueFalsePreservesContextForLaterTurns() throws {
        let parsed = try parseCompleted(
            stdout: #"{"continue":false,"stopReason":"pause","hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"do not inject"}}"#
        )

        XCTAssertEqual(parsed.data, HookUserPromptSubmitHandlerData(
            shouldStop: true,
            stopReason: "pause",
            additionalContextsForModel: ["do not inject"]
        ))
        XCTAssertEqual(parsed.completed.run.status, .stopped)
        XCTAssertEqual(parsed.completed.run.entries, [
            HookOutputEntry(kind: .context, text: "do not inject"),
            HookOutputEntry(kind: .stop, text: "pause"),
        ])
    }

    func testBlockDecisionBlocksProcessing() throws {
        let parsed = try parseCompleted(
            stdout: #"{"decision":"block","reason":"slow down","hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"do not inject"}}"#
        )

        XCTAssertEqual(parsed.data, HookUserPromptSubmitHandlerData(
            shouldStop: true,
            stopReason: "slow down",
            additionalContextsForModel: ["do not inject"]
        ))
        XCTAssertEqual(parsed.completed.run.status, .blocked)
        XCTAssertEqual(parsed.completed.run.entries, [
            HookOutputEntry(kind: .context, text: "do not inject"),
            HookOutputEntry(kind: .feedback, text: "slow down"),
        ])
    }

    func testBlockDecisionRequiresReasonAndSkipsContext() throws {
        let parsed = try parseCompleted(
            stdout: #"{"decision":"block","hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"do not inject"}}"#
        )

        XCTAssertEqual(parsed.data, HookUserPromptSubmitHandlerData())
        XCTAssertEqual(parsed.completed.run.status, .failed)
        XCTAssertEqual(parsed.completed.run.entries, [
            HookOutputEntry(
                kind: .error,
                text: "UserPromptSubmit hook returned decision:block without a non-empty reason"
            )
        ])
    }

    func testInvalidJSONLikeStdoutFailsInsteadOfBecomingContext() throws {
        let parsed = try parseCompleted(stdout: #"{"decision":"#)

        XCTAssertEqual(parsed.data, HookUserPromptSubmitHandlerData())
        XCTAssertEqual(parsed.completed.run.status, .failed)
        XCTAssertEqual(parsed.completed.run.entries, [
            HookOutputEntry(kind: .error, text: "hook returned invalid user prompt submit JSON output")
        ])
    }

    func testExitCodeTwoBlocksProcessing() throws {
        let parsed = try parseCompleted(exitCode: 2, stdout: "", stderr: "blocked by policy\n")

        XCTAssertEqual(parsed.data, HookUserPromptSubmitHandlerData(
            shouldStop: true,
            stopReason: "blocked by policy"
        ))
        XCTAssertEqual(parsed.completed.run.status, .blocked)
        XCTAssertEqual(parsed.completed.run.entries, [
            HookOutputEntry(kind: .feedback, text: "blocked by policy")
        ])
    }

    func testExitCodeTwoWithoutStderrAndNonzeroFailures() throws {
        let missingReason = try parseCompleted(exitCode: 2, stdout: "", stderr: " ")
        let nonzero = try parseCompleted(exitCode: 7, stdout: "", stderr: "")
        let missingStatus = try parseCompleted(exitCode: nil, stdout: "", stderr: "")

        XCTAssertEqual(missingReason.completed.run.status, .failed)
        XCTAssertEqual(missingReason.completed.run.entries, [
            HookOutputEntry(
                kind: .error,
                text: "UserPromptSubmit hook exited with code 2 but did not write a blocking reason to stderr"
            )
        ])
        XCTAssertEqual(nonzero.completed.run.entries, [
            HookOutputEntry(kind: .error, text: "hook exited with code 7")
        ])
        XCTAssertEqual(missingStatus.completed.run.entries, [
            HookOutputEntry(kind: .error, text: "hook exited without a status code")
        ])
    }

    func testRunAggregatesStopAndAdditionalContexts() async throws {
        let handlers = try [
            handler(command: #"printf 'plain ctx'"#),
            handler(
                command: #"printf %s '{"decision":"block","reason":"slow down","hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"json ctx"}}'"#,
                displayOrder: 1
            ),
        ]

        let outcome = await HookUserPromptSubmit.run(
            handlers: handlers,
            shell: HookCommandShell(program: "/bin/sh", arguments: ["-c"]),
            request: try request(prompt: "do the thing")
        )

        XCTAssertTrue(outcome.shouldStop)
        XCTAssertEqual(outcome.stopReason, "slow down")
        XCTAssertEqual(outcome.additionalContexts, ["plain ctx", "json ctx"])
        XCTAssertEqual(outcome.hookEvents.map(\.run.status), [.completed, .blocked])
    }

    private func parseCompleted(
        exitCode: Int32? = 0,
        stdout: String,
        stderr: String = ""
    ) throws -> ParsedHookHandler<HookUserPromptSubmitHandlerData> {
        try HookUserPromptSubmit.parseCompleted(
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
        matcher: String? = nil,
        command: String = "echo hook",
        displayOrder: Int64 = 0
    ) throws -> ConfiguredHookHandler {
        try ConfiguredHookHandler(
            eventName: .userPromptSubmit,
            matcher: matcher,
            command: command,
            timeoutSec: 5,
            sourcePath: AbsolutePath(absolutePath: "/tmp/hooks.json"),
            source: .user,
            displayOrder: displayOrder
        )
    }

    private func request(prompt: String) throws -> HookUserPromptSubmitRequest {
        try HookUserPromptSubmitRequest(
            sessionID: ThreadId(),
            turnID: "turn-1",
            cwd: AbsolutePath(absolutePath: "/tmp"),
            model: "gpt-test",
            permissionMode: "default",
            prompt: prompt
        )
    }
}
