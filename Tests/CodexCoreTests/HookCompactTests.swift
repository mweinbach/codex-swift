import CodexCore
import XCTest

final class HookCompactTests: XCTestCase {
    func testPreCompactCommandInputIncludesLifecycleMetadata() throws {
        let inputJSON = try HookPreCompact.commandInputJSON(try preRequest())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(inputJSON.utf8)) as? [String: Any])

        XCTAssertEqual(object["session_id"] as? String, "00000000-0000-4000-8000-000000000001")
        XCTAssertEqual(object["turn_id"] as? String, "turn-1")
        XCTAssertEqual(object["transcript_path"] as? NSNull, NSNull())
        XCTAssertEqual(object["cwd"] as? String, "/tmp")
        XCTAssertEqual(object["hook_event_name"] as? String, "PreCompact")
        XCTAssertEqual(object["model"] as? String, "gpt-test")
        XCTAssertEqual(object["trigger"] as? String, "manual")
    }

    func testPostCompactCommandInputIncludesLifecycleMetadata() throws {
        let inputJSON = try HookPostCompact.commandInputJSON(try postRequest())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(inputJSON.utf8)) as? [String: Any])

        XCTAssertEqual(object["session_id"] as? String, "00000000-0000-4000-8000-000000000002")
        XCTAssertEqual(object["turn_id"] as? String, "turn-1")
        XCTAssertEqual(object["transcript_path"] as? NSNull, NSNull())
        XCTAssertEqual(object["cwd"] as? String, "/tmp")
        XCTAssertEqual(object["hook_event_name"] as? String, "PostCompact")
        XCTAssertEqual(object["model"] as? String, "gpt-test")
        XCTAssertEqual(object["trigger"] as? String, "manual")
    }

    func testPreviewMatchesCompactTriggerAndUsesTurnScope() throws {
        let handlers = try [
            preHandler(matcher: "auto"),
            preHandler(matcher: "manual", displayOrder: 1),
            preHandler(matcher: nil, displayOrder: 2),
        ]

        let runs = HookPreCompact.preview(handlers: handlers, request: try preRequest(), startedAt: 1)

        XCTAssertEqual(runs.map(\.id), [
            "pre-compact:1:/tmp/hooks.json",
            "pre-compact:2:/tmp/hooks.json",
        ])
        XCTAssertEqual(runs.map(\.scope), [.turn, .turn])
    }

    func testPreCompactRejectsBlockDecisionAsInvalidJSONShape() throws {
        let parsed = try HookPreCompact.parseCompleted(
            handler: preHandler(),
            runResult: runResult(
                exitCode: 0,
                stdout: #"{"decision":"block","reason":"policy blocked compaction"}"#
            ),
            turnID: "turn-1"
        )

        XCTAssertEqual(parsed.data, HookCompactHandlerData())
        XCTAssertEqual(parsed.completed.run.status, .failed)
        XCTAssertEqual(parsed.completed.run.entries, [
            HookOutputEntry(kind: .error, text: "hook returned invalid PreCompact hook JSON output")
        ])
    }

    func testPreCompactContinueFalseStopsBeforeCompaction() throws {
        let parsed = try HookPreCompact.parseCompleted(
            handler: preHandler(),
            runResult: runResult(exitCode: 0, stdout: #"{"continue":false,"stopReason":"nope"}"#),
            turnID: "turn-1"
        )

        XCTAssertEqual(parsed.data, HookCompactHandlerData(shouldStop: true, stopReason: "nope"))
        XCTAssertEqual(parsed.completed.run.status, .stopped)
        XCTAssertEqual(parsed.completed.run.entries, [
            HookOutputEntry(kind: .stop, text: "nope")
        ])
    }

    func testPostCompactContinueFalseStopsAfterCompaction() throws {
        let parsed = try HookPostCompact.parseCompleted(
            handler: postHandler(),
            runResult: runResult(exitCode: 0, stdout: #"{"continue":false,"stopReason":"pause after compact"}"#),
            turnID: "turn-1"
        )

        XCTAssertEqual(parsed.data, HookCompactHandlerData(shouldStop: true, stopReason: "pause after compact"))
        XCTAssertEqual(parsed.completed.run.status, .stopped)
        XCTAssertEqual(parsed.completed.run.entries, [
            HookOutputEntry(kind: .stop, text: "pause after compact")
        ])
    }

    func testCompactHooksIgnorePlainStdout() throws {
        let pre = try HookPreCompact.parseCompleted(
            handler: preHandler(),
            runResult: runResult(exitCode: 0, stdout: "checking compact policy\n"),
            turnID: "turn-1"
        )
        let post = try HookPostCompact.parseCompleted(
            handler: postHandler(),
            runResult: runResult(exitCode: 0, stdout: "logged compact summary\n"),
            turnID: "turn-1"
        )

        XCTAssertEqual(pre.completed.run.status, .completed)
        XCTAssertEqual(pre.completed.run.entries, [])
        XCTAssertEqual(post.completed.run.status, .completed)
        XCTAssertEqual(post.completed.run.entries, [])
    }

    func testCompactHooksUseStderrForNonzeroExitAndRustMissingStatusText() throws {
        let nonzero = try HookPreCompact.parseCompleted(
            handler: preHandler(),
            runResult: runResult(exitCode: 7, stdout: "", stderr: "bad compact\n"),
            turnID: "turn-1"
        )
        let missing = try HookPostCompact.parseCompleted(
            handler: postHandler(),
            runResult: runResult(exitCode: nil, stdout: ""),
            turnID: "turn-1"
        )

        XCTAssertEqual(nonzero.completed.run.entries, [
            HookOutputEntry(kind: .error, text: "bad compact")
        ])
        XCTAssertEqual(missing.completed.run.entries, [
            HookOutputEntry(kind: .error, text: "hook process terminated without an exit code")
        ])
    }

    func testRunAggregatesStopStateAcrossMatchingCompactHooks() async throws {
        let handlers = try [
            preHandler(command: #"printf %s '{"systemMessage":"heads up"}'"#),
            preHandler(
                command: #"printf %s '{"continue":false,"stopReason":"pause compact"}'"#,
                displayOrder: 1
            ),
        ]

        let outcome = await HookPreCompact.run(
            handlers: handlers,
            shell: HookCommandShell(program: "/bin/sh", arguments: ["-c"]),
            request: try preRequest()
        )

        XCTAssertTrue(outcome.shouldStop)
        XCTAssertEqual(outcome.stopReason, "pause compact")
        XCTAssertEqual(outcome.hookEvents.map(\.run.status), [.completed, .stopped])
        XCTAssertEqual(outcome.hookEvents.first?.run.entries, [
            HookOutputEntry(kind: .warning, text: "heads up")
        ])
    }

    private func preRequest() throws -> HookPreCompactRequest {
        try HookPreCompactRequest(
            sessionID: ThreadId(string: "00000000-0000-4000-8000-000000000001"),
            turnID: "turn-1",
            cwd: AbsolutePath(absolutePath: "/tmp"),
            model: "gpt-test",
            trigger: "manual"
        )
    }

    private func postRequest() throws -> HookPostCompactRequest {
        try HookPostCompactRequest(
            sessionID: ThreadId(string: "00000000-0000-4000-8000-000000000002"),
            turnID: "turn-1",
            cwd: AbsolutePath(absolutePath: "/tmp"),
            model: "gpt-test",
            trigger: "manual"
        )
    }

    private func preHandler(
        matcher: String? = nil,
        command: String = "python3 compact_hook.py",
        displayOrder: Int64 = 0
    ) throws -> ConfiguredHookHandler {
        try handler(eventName: .preCompact, matcher: matcher, command: command, displayOrder: displayOrder)
    }

    private func postHandler(
        matcher: String? = nil,
        command: String = "python3 compact_hook.py",
        displayOrder: Int64 = 0
    ) throws -> ConfiguredHookHandler {
        try handler(eventName: .postCompact, matcher: matcher, command: command, displayOrder: displayOrder)
    }

    private func handler(
        eventName: HookEventName,
        matcher: String?,
        command: String,
        displayOrder: Int64
    ) throws -> ConfiguredHookHandler {
        try ConfiguredHookHandler(
            eventName: eventName,
            matcher: matcher,
            command: command,
            timeoutSec: 5,
            statusMessage: "running compact hook",
            sourcePath: AbsolutePath(absolutePath: "/tmp/hooks.json"),
            source: .user,
            displayOrder: displayOrder
        )
    }

    private func runResult(exitCode: Int32?, stdout: String, stderr: String = "") -> HookCommandRunResult {
        HookCommandRunResult(
            startedAt: 1_700_000_000,
            completedAt: 1_700_000_001,
            durationMs: 12,
            exitCode: exitCode,
            stdout: stdout,
            stderr: stderr
        )
    }
}
