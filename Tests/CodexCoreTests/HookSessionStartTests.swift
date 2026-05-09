import CodexCore
import XCTest

final class HookSessionStartTests: XCTestCase {
    func testCommandInputIncludesSourceAndOmitsTurnID() throws {
        let inputJSON = try HookSessionStart.commandInputJSON(try request(source: .resume))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(inputJSON.utf8)) as? [String: Any])

        XCTAssertEqual(object["hook_event_name"] as? String, "SessionStart")
        XCTAssertEqual(object["source"] as? String, "resume")
        XCTAssertEqual(object["transcript_path"] as? NSNull, NSNull())
        XCTAssertNil(object["turn_id"])
    }

    func testPreviewMatchesSessionStartSource() throws {
        let handlers = try [
            handler(matcher: "startup"),
            handler(matcher: "resume", displayOrder: 1),
            handler(matcher: nil, displayOrder: 2),
        ]

        let runs = HookSessionStart.preview(handlers: handlers, request: try request(source: .resume), startedAt: 1)

        XCTAssertEqual(runs.map(\.id), [
            "session-start:1:/tmp/hooks.json",
            "session-start:2:/tmp/hooks.json",
        ])
        XCTAssertEqual(runs.map(\.scope), [.thread, .thread])
    }

    func testPlainStdoutBecomesModelContext() throws {
        let parsed = try parseCompleted(stdout: "hello from hook\n")

        XCTAssertEqual(parsed.data, HookSessionStartHandlerData(
            additionalContextsForModel: ["hello from hook"]
        ))
        XCTAssertEqual(parsed.completed.run.status, .completed)
        XCTAssertEqual(parsed.completed.run.entries, [
            HookOutputEntry(kind: .context, text: "hello from hook")
        ])
    }

    func testJSONAdditionalContextAndWarningAreRecorded() throws {
        let parsed = try parseCompleted(
            stdout: #"{"systemMessage":"heads up","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"ctx"}}"#
        )

        XCTAssertEqual(parsed.data, HookSessionStartHandlerData(
            additionalContextsForModel: ["ctx"]
        ))
        XCTAssertEqual(parsed.completed.run.entries, [
            HookOutputEntry(kind: .warning, text: "heads up"),
            HookOutputEntry(kind: .context, text: "ctx"),
        ])
    }

    func testContinueFalsePreservesContextAndStops() throws {
        let parsed = try parseCompleted(
            stdout: #"{"continue":false,"stopReason":"pause","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"do not inject"}}"#
        )

        XCTAssertEqual(parsed.data, HookSessionStartHandlerData(
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

    func testInvalidJSONLikeStdoutFailsInsteadOfBecomingContext() throws {
        let parsed = try parseCompleted(stdout: #"{"hookSpecificOutput":{"hookEventName":"SessionStart""#)

        XCTAssertEqual(parsed.data, HookSessionStartHandlerData())
        XCTAssertEqual(parsed.completed.run.status, .failed)
        XCTAssertEqual(parsed.completed.run.entries, [
            HookOutputEntry(kind: .error, text: "hook returned invalid session start JSON output")
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

    func testRunAggregatesStopAndAdditionalContexts() async throws {
        let handlers = try [
            handler(command: #"printf 'plain ctx'"#),
            handler(
                command: #"printf %s '{"continue":false,"stopReason":"pause","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"json ctx"}}'"#,
                displayOrder: 1
            ),
        ]

        let outcome = await HookSessionStart.run(
            handlers: handlers,
            shell: HookCommandShell(program: "/bin/sh", arguments: ["-c"]),
            request: try request(source: .startup),
            turnID: nil
        )

        XCTAssertTrue(outcome.shouldStop)
        XCTAssertEqual(outcome.stopReason, "pause")
        XCTAssertEqual(outcome.additionalContexts, ["plain ctx", "json ctx"])
        XCTAssertEqual(outcome.hookEvents.map(\.run.status), [.completed, .stopped])
    }

    private func parseCompleted(
        exitCode: Int32? = 0,
        stdout: String,
        stderr: String = ""
    ) throws -> ParsedHookHandler<HookSessionStartHandlerData> {
        try HookSessionStart.parseCompleted(
            handler: handler(),
            runResult: HookCommandRunResult(
                startedAt: 1,
                completedAt: 2,
                durationMs: 1,
                exitCode: exitCode,
                stdout: stdout,
                stderr: stderr
            ),
            turnID: nil
        )
    }

    private func handler(
        matcher: String? = nil,
        command: String = "echo hook",
        displayOrder: Int64 = 0
    ) throws -> ConfiguredHookHandler {
        try ConfiguredHookHandler(
            eventName: .sessionStart,
            matcher: matcher,
            command: command,
            timeoutSec: 5,
            sourcePath: AbsolutePath(absolutePath: "/tmp/hooks.json"),
            source: .user,
            displayOrder: displayOrder
        )
    }

    private func request(source: HookSessionStartSource) throws -> HookSessionStartRequest {
        try HookSessionStartRequest(
            sessionID: ThreadId(),
            cwd: AbsolutePath(absolutePath: "/tmp"),
            model: "gpt-test",
            permissionMode: "default",
            source: source
        )
    }
}
