import CodexCore
import XCTest

final class HookEventsTests: XCTestCase {
    func testHookEnumsUseRustSnakeCaseWireValues() throws {
        XCTAssertEqual(try jsonString(HookEventName.preToolUse), #""pre_tool_use""#)
        XCTAssertEqual(try jsonString(HookEventName.permissionRequest), #""permission_request""#)
        XCTAssertEqual(try jsonString(HookHandlerType.command), #""command""#)
        XCTAssertEqual(try jsonString(HookHandlerType.prompt), #""prompt""#)
        XCTAssertEqual(try jsonString(HookHandlerType.agent), #""agent""#)
        XCTAssertEqual(try jsonString(HookExecutionMode.sync), #""sync""#)
        XCTAssertEqual(try jsonString(HookExecutionMode.async), #""async""#)
        XCTAssertEqual(try jsonString(HookScope.thread), #""thread""#)
        XCTAssertEqual(try jsonString(HookScope.turn), #""turn""#)
        XCTAssertEqual(try jsonString(HookSource.cloudRequirements), #""cloud_requirements""#)
        XCTAssertEqual(try jsonString(HookTrustStatus.modified), #""modified""#)
        XCTAssertEqual(try jsonString(HookRunStatus.blocked), #""blocked""#)
        XCTAssertEqual(try jsonString(HookOutputEntryKind.feedback), #""feedback""#)
    }

    func testHookConstantsAndKeyHelpersMatchRustHooksCrate() {
        XCTAssertEqual(
            HooksProtocol.eventNames,
            [
                "PreToolUse",
                "PermissionRequest",
                "PostToolUse",
                "PreCompact",
                "PostCompact",
                "SessionStart",
                "UserPromptSubmit",
                "Stop",
            ]
        )
        XCTAssertEqual(
            HooksProtocol.eventNamesWithMatchers,
            [
                "PreToolUse",
                "PermissionRequest",
                "PostToolUse",
                "PreCompact",
                "PostCompact",
                "SessionStart",
            ]
        )
        XCTAssertEqual(HooksProtocol.hookEventKeyLabel(.postToolUse), "post_tool_use")
        XCTAssertEqual(
            HooksProtocol.hookKey(
                keySource: "plugin:example:hooks.json",
                eventName: .permissionRequest,
                groupIndex: 2,
                handlerIndex: 3
            ),
            "plugin:example:hooks.json:permission_request:2:3"
        )
    }

    func testHookRunSummaryEncodesRustSnakeCaseShapeWithExplicitNullOptionals() throws {
        let run = try HookRunSummary(
            id: "run-1",
            eventName: .preToolUse,
            handlerType: .command,
            executionMode: .sync,
            scope: .turn,
            sourcePath: AbsolutePath(absolutePath: "/tmp/hooks.json"),
            source: .project,
            displayOrder: 7,
            status: .running,
            statusMessage: nil,
            startedAt: 10,
            completedAt: nil,
            durationMs: nil,
            entries: [
                HookOutputEntry(kind: .warning, text: "careful"),
                HookOutputEntry(kind: .context, text: "note"),
            ]
        )

        let object = try jsonObject(run)
        XCTAssertEqual(object["id"], .string("run-1"))
        XCTAssertEqual(object["event_name"], .string("pre_tool_use"))
        XCTAssertEqual(object["handler_type"], .string("command"))
        XCTAssertEqual(object["execution_mode"], .string("sync"))
        XCTAssertEqual(object["scope"], .string("turn"))
        XCTAssertEqual(object["source_path"], .string("/tmp/hooks.json"))
        XCTAssertEqual(object["source"], .string("project"))
        XCTAssertEqual(object["display_order"], .integer(7))
        XCTAssertEqual(object["status"], .string("running"))
        XCTAssertEqual(object["status_message"], .null)
        XCTAssertEqual(object["started_at"], .integer(10))
        XCTAssertEqual(object["completed_at"], .null)
        XCTAssertEqual(object["duration_ms"], .null)
        XCTAssertEqual(object["entries"], .array([
            .object(["kind": .string("warning"), "text": .string("careful")]),
            .object(["kind": .string("context"), "text": .string("note")]),
        ]))
    }

    func testHookRunSummaryDefaultsMissingSourceToUnknown() throws {
        let json = """
        {
          "id": "run-2",
          "event_name": "stop",
          "handler_type": "agent",
          "execution_mode": "async",
          "scope": "thread",
          "source_path": "/tmp/hook.json",
          "display_order": 1,
          "status": "completed",
          "status_message": null,
          "started_at": 10,
          "completed_at": 15,
          "duration_ms": 5,
          "entries": []
        }
        """

        let run = try JSONDecoder().decode(HookRunSummary.self, from: Data(json.utf8))
        XCTAssertEqual(run.source, .unknown)
        XCTAssertEqual(run.executionMode, .async)
        XCTAssertEqual(run.completedAt, 15)
        XCTAssertEqual(run.durationMs, 5)
    }

    func testHookStartedAndCompletedEventsUseTurnIDWireName() throws {
        let run = try HookRunSummary(
            id: "run-3",
            eventName: .postCompact,
            handlerType: .prompt,
            executionMode: .async,
            scope: .thread,
            sourcePath: AbsolutePath(absolutePath: "/tmp/hook.json"),
            displayOrder: 0,
            status: .completed,
            statusMessage: "done",
            startedAt: 100,
            completedAt: 120,
            durationMs: 20,
            entries: []
        )

        let started = try jsonObject(HookStartedEvent(turnID: nil, run: run))
        XCTAssertEqual(started["turn_id"], .null)
        XCTAssertNotNil(started["run"])

        let completed = try jsonObject(HookCompletedEvent(turnID: "turn-1", run: run))
        XCTAssertEqual(completed["turn_id"], .string("turn-1"))
        XCTAssertNotNil(completed["run"])
    }

    func testCompactOutputParsersReadUniversalFieldsLikeRust() throws {
        let pre = try XCTUnwrap(HooksProtocol.parsePreCompactOutput("""
          {"continue":false,"stopReason":"nope","suppressOutput":true,"systemMessage":"heads up"}
        """))
        XCTAssertEqual(pre.universal.continueProcessing, false)
        XCTAssertEqual(pre.universal.stopReason, "nope")
        XCTAssertEqual(pre.universal.suppressOutput, true)
        XCTAssertEqual(pre.universal.systemMessage, "heads up")
        XCTAssertNil(pre.invalidReason)

        let post = try XCTUnwrap(HooksProtocol.parsePostCompactOutput(#"{"stopReason":null,"systemMessage":null}"#))
        XCTAssertEqual(post.universal, HookUniversalOutput())
    }

    func testCompactOutputParsersRejectUnknownFieldsLikeSerdeDenyUnknownFields() {
        XCTAssertNil(HooksProtocol.parsePreCompactOutput(#"{"decision":"block","reason":"policy"}"#))
        XCTAssertNil(HooksProtocol.parsePostCompactOutput(#"{"continue":true,"extra":1}"#))
    }

    func testCompactOutputParsersRejectInvalidOrNonObjectJSONLikeRust() {
        XCTAssertNil(HooksProtocol.parsePreCompactOutput(""))
        XCTAssertNil(HooksProtocol.parsePreCompactOutput("checking compact policy\n"))
        XCTAssertNil(HooksProtocol.parsePreCompactOutput(#"["not","object"]"#))
        XCTAssertNil(HooksProtocol.parsePreCompactOutput(#"{"continue":"false"}"#))
        XCTAssertNil(HooksProtocol.parsePostCompactOutput(#"{"stopReason":7}"#))
    }

    func testLooksLikeJSONMatchesRustTrimStartHeuristic() {
        XCTAssertTrue(HooksProtocol.looksLikeJSON("  {\"continue\":false}"))
        XCTAssertTrue(HooksProtocol.looksLikeJSON("\n[1,2]"))
        XCTAssertFalse(HooksProtocol.looksLikeJSON("plain { text"))
        XCTAssertFalse(HooksProtocol.looksLikeJSON("   \n\t"))
    }

    private func jsonString<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> [String: JSONValue] {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        guard case let .object(object) = decoded else {
            XCTFail("expected object JSON")
            return [:]
        }
        return object
    }
}
