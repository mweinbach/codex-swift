import CodexCore
import XCTest

final class HookStopTests: XCTestCase {
    func testCommandInputIncludesStopFields() throws {
        let inputJSON = try HookStop.commandInputJSON(try request(lastAssistantMessage: "done"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(inputJSON.utf8)) as? [String: Any])

        XCTAssertEqual(object["hook_event_name"] as? String, "Stop")
        XCTAssertEqual(object["turn_id"] as? String, "turn-1")
        XCTAssertEqual(object["stop_hook_active"] as? Bool, true)
        XCTAssertEqual(object["last_assistant_message"] as? String, "done")
        XCTAssertEqual(object["transcript_path"] as? NSNull, NSNull())
    }

    func testPreviewIgnoresMatchers() throws {
        let handlers = try [
            handler(matcher: "^never$", displayOrder: 0),
            handler(matcher: nil, displayOrder: 1),
        ]

        let runs = HookStop.preview(handlers: handlers, startedAt: 1)

        XCTAssertEqual(runs.map(\.id), [
            "stop:0:/tmp/hooks.json",
            "stop:1:/tmp/hooks.json",
        ])
    }

    func testBlockDecisionWithReasonSetsContinuationPrompt() throws {
        let parsed = try parseCompleted(stdout: #"{"decision":"block","reason":"retry with tests"}"#)

        XCTAssertEqual(parsed.data, HookStopHandlerData(
            shouldBlock: true,
            blockReason: "retry with tests",
            continuationFragments: [HookPromptFragment(text: "retry with tests", hookRunID: parsed.completed.run.id)]
        ))
        XCTAssertEqual(parsed.completed.run.status, .blocked)
        XCTAssertEqual(parsed.completed.run.entries, [
            HookOutputEntry(kind: .feedback, text: "retry with tests")
        ])
    }

    func testBlockDecisionWithoutReasonIsInvalid() throws {
        let parsed = try parseCompleted(stdout: #"{"decision":"block"}"#)

        XCTAssertEqual(parsed.data, HookStopHandlerData())
        XCTAssertEqual(parsed.completed.run.status, .failed)
        XCTAssertEqual(parsed.completed.run.entries, [
            HookOutputEntry(kind: .error, text: "Stop hook returned decision:block without a non-empty reason")
        ])
    }

    func testContinueFalseOverridesBlockDecision() throws {
        let parsed = try parseCompleted(
            stdout: #"{"continue":false,"stopReason":"done","decision":"block","reason":"keep going"}"#
        )

        XCTAssertEqual(parsed.data, HookStopHandlerData(
            shouldStop: true,
            stopReason: "done"
        ))
        XCTAssertEqual(parsed.completed.run.status, .stopped)
        XCTAssertEqual(parsed.completed.run.entries, [
            HookOutputEntry(kind: .stop, text: "done")
        ])
    }

    func testExitCodeTwoUsesStderrFeedbackOnly() throws {
        let parsed = try parseCompleted(exitCode: 2, stdout: "ignored stdout", stderr: "retry with tests")

        XCTAssertEqual(parsed.data, HookStopHandlerData(
            shouldBlock: true,
            blockReason: "retry with tests",
            continuationFragments: [HookPromptFragment(text: "retry with tests", hookRunID: parsed.completed.run.id)]
        ))
        XCTAssertEqual(parsed.completed.run.status, .blocked)
    }

    func testExitCodeTwoWithoutStderrDoesNotBlock() throws {
        let parsed = try parseCompleted(exitCode: 2, stdout: "", stderr: "   ")

        XCTAssertEqual(parsed.data, HookStopHandlerData())
        XCTAssertEqual(parsed.completed.run.status, .failed)
        XCTAssertEqual(parsed.completed.run.entries, [
            HookOutputEntry(
                kind: .error,
                text: "Stop hook exited with code 2 but did not write a continuation prompt to stderr"
            )
        ])
    }

    func testInvalidStdoutFailsInsteadOfSilentlyNooping() throws {
        let parsed = try parseCompleted(stdout: "not json")

        XCTAssertEqual(parsed.data, HookStopHandlerData())
        XCTAssertEqual(parsed.completed.run.status, .failed)
        XCTAssertEqual(parsed.completed.run.entries, [
            HookOutputEntry(kind: .error, text: "hook returned invalid stop hook JSON output")
        ])
    }

    func testNonzeroExitAndMissingStatusFail() throws {
        let nonzero = try parseCompleted(exitCode: 7, stdout: "", stderr: "")
        let missing = try parseCompleted(exitCode: nil, stdout: "", stderr: "")

        XCTAssertEqual(nonzero.completed.run.entries, [
            HookOutputEntry(kind: .error, text: "hook exited with code 7")
        ])
        XCTAssertEqual(missing.completed.run.entries, [
            HookOutputEntry(kind: .error, text: "hook exited without a status code")
        ])
    }

    func testAggregateResultsConcatenatesBlockingReasonsInDeclarationOrder() {
        let aggregate = HookStop.aggregateResults([
            HookStopHandlerData(
                shouldBlock: true,
                blockReason: "first",
                continuationFragments: [HookPromptFragment(text: "first", hookRunID: "run-1")]
            ),
            HookStopHandlerData(
                shouldBlock: true,
                blockReason: "second",
                continuationFragments: [HookPromptFragment(text: "second", hookRunID: "run-2")]
            ),
        ])

        XCTAssertEqual(aggregate, HookStopHandlerData(
            shouldBlock: true,
            blockReason: "first\n\nsecond",
            continuationFragments: [
                HookPromptFragment(text: "first", hookRunID: "run-1"),
                HookPromptFragment(text: "second", hookRunID: "run-2"),
            ]
        ))
    }

    func testAggregateResultsStopSuppressesBlockingFragments() {
        let aggregate = HookStop.aggregateResults([
            HookStopHandlerData(shouldBlock: true, blockReason: "retry"),
            HookStopHandlerData(shouldStop: true, stopReason: "done"),
        ])

        XCTAssertEqual(aggregate, HookStopHandlerData(
            shouldStop: true,
            stopReason: "done"
        ))
    }

    func testRunAggregatesBlockingContinuations() async throws {
        let handlers = try [
            handler(command: #"printf %s '{"decision":"block","reason":"first"}'"#),
            handler(command: #"printf %s '{"decision":"block","reason":"second"}'"#, displayOrder: 1),
        ]

        let outcome = await HookStop.run(
            handlers: handlers,
            shell: HookCommandShell(program: "/bin/sh", arguments: ["-c"]),
            request: try request()
        )

        XCTAssertFalse(outcome.shouldStop)
        XCTAssertTrue(outcome.shouldBlock)
        XCTAssertEqual(outcome.blockReason, "first\n\nsecond")
        XCTAssertEqual(outcome.continuationFragments.map(\.text), ["first", "second"])
        XCTAssertEqual(outcome.continuationFragments.map(\.hookRunID), [
            "stop:0:/tmp/hooks.json",
            "stop:1:/tmp/hooks.json",
        ])
    }

    private func parseCompleted(
        exitCode: Int32? = 0,
        stdout: String,
        stderr: String = ""
    ) throws -> ParsedHookHandler<HookStopHandlerData> {
        try HookStop.parseCompleted(
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
            eventName: .stop,
            matcher: matcher,
            command: command,
            timeoutSec: 5,
            sourcePath: AbsolutePath(absolutePath: "/tmp/hooks.json"),
            source: .user,
            displayOrder: displayOrder
        )
    }

    private func request(lastAssistantMessage: String? = nil) throws -> HookStopRequest {
        try HookStopRequest(
            sessionID: ThreadId(),
            turnID: "turn-1",
            cwd: AbsolutePath(absolutePath: "/tmp"),
            model: "gpt-test",
            permissionMode: "default",
            stopHookActive: true,
            lastAssistantMessage: lastAssistantMessage
        )
    }
}
