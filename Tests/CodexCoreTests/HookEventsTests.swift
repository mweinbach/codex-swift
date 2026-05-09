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

    func testPreToolUseOutputParsesLegacyBlockDecisionLikeRust() throws {
        let parsed = try XCTUnwrap(HooksProtocol.parsePreToolUseOutput("""
        {"decision":"block","reason":"  policy blocked  ","systemMessage":"visible"}
        """))
        XCTAssertEqual(parsed.universal.systemMessage, "visible")
        XCTAssertEqual(parsed.blockReason, "policy blocked")
        XCTAssertNil(parsed.additionalContext)
        XCTAssertNil(parsed.invalidReason)
    }

    func testPreToolUseOutputParsesHookSpecificDenyAndAdditionalContextLikeRust() throws {
        let parsed = try XCTUnwrap(HooksProtocol.parsePreToolUseOutput("""
        {
          "decision": "block",
          "reason": "legacy ignored",
          "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": "  hook denied  ",
            "additionalContext": "remember this"
          }
        }
        """))
        XCTAssertEqual(parsed.blockReason, "hook denied")
        XCTAssertEqual(parsed.additionalContext, "remember this")
        XCTAssertNil(parsed.invalidReason)
    }

    func testPreToolUseOutputUsesLegacyDecisionWhenHookSpecificOnlyAddsContextLikeRust() throws {
        let parsed = try XCTUnwrap(HooksProtocol.parsePreToolUseOutput("""
        {
          "decision": "block",
          "reason": "legacy reason",
          "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "additionalContext": "context only"
          }
        }
        """))
        XCTAssertEqual(parsed.blockReason, "legacy reason")
        XCTAssertEqual(parsed.additionalContext, "context only")
        XCTAssertNil(parsed.invalidReason)
    }

    func testPreToolUseOutputReportsUnsupportedUniversalAndLegacyFieldsLikeRust() throws {
        let stopped = try XCTUnwrap(HooksProtocol.parsePreToolUseOutput(#"{"continue":false}"#))
        XCTAssertNil(stopped.blockReason)
        XCTAssertEqual(stopped.invalidReason, "PreToolUse hook returned unsupported continue:false")

        let approve = try XCTUnwrap(HooksProtocol.parsePreToolUseOutput(#"{"decision":"approve"}"#))
        XCTAssertNil(approve.blockReason)
        XCTAssertEqual(approve.invalidReason, "PreToolUse hook returned unsupported decision:approve")

        let missingReason = try XCTUnwrap(HooksProtocol.parsePreToolUseOutput(#"{"decision":"block","reason":"  "}"#))
        XCTAssertNil(missingReason.blockReason)
        XCTAssertEqual(
            missingReason.invalidReason,
            "PreToolUse hook returned decision:block without a non-empty reason"
        )

        let reasonOnly = try XCTUnwrap(HooksProtocol.parsePreToolUseOutput(#"{"reason":""}"#))
        XCTAssertNil(reasonOnly.blockReason)
        XCTAssertEqual(reasonOnly.invalidReason, "PreToolUse hook returned reason without decision")
    }

    func testPreToolUseOutputReportsUnsupportedHookSpecificFieldsLikeRust() throws {
        let allow = try XCTUnwrap(HooksProtocol.parsePreToolUseOutput("""
        {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}
        """))
        XCTAssertEqual(allow.invalidReason, "PreToolUse hook returned unsupported permissionDecision:allow")

        let ask = try XCTUnwrap(HooksProtocol.parsePreToolUseOutput("""
        {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask"}}
        """))
        XCTAssertEqual(ask.invalidReason, "PreToolUse hook returned unsupported permissionDecision:ask")

        let denyWithoutReason = try XCTUnwrap(HooksProtocol.parsePreToolUseOutput("""
        {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"  "}}
        """))
        XCTAssertEqual(
            denyWithoutReason.invalidReason,
            "PreToolUse hook returned permissionDecision:deny without a non-empty permissionDecisionReason"
        )

        let reasonWithoutDecision = try XCTUnwrap(HooksProtocol.parsePreToolUseOutput("""
        {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecisionReason":"why"}}
        """))
        XCTAssertEqual(
            reasonWithoutDecision.invalidReason,
            "PreToolUse hook returned permissionDecisionReason without permissionDecision"
        )

        let updatedInput = try XCTUnwrap(HooksProtocol.parsePreToolUseOutput("""
        {"hookSpecificOutput":{"hookEventName":"PreToolUse","updatedInput":{}}}
        """))
        XCTAssertEqual(updatedInput.invalidReason, "PreToolUse hook returned unsupported updatedInput")
    }

    func testPreToolUseOutputRejectsUnknownFieldsAndMalformedShapesLikeRust() {
        XCTAssertNil(HooksProtocol.parsePreToolUseOutput(#"{"decision":"deny"}"#))
        XCTAssertNil(HooksProtocol.parsePreToolUseOutput(#"{"decision":"block","extra":1}"#))
        XCTAssertNil(HooksProtocol.parsePreToolUseOutput(#"{"hookSpecificOutput":{"permissionDecision":"deny"}}"#))
        XCTAssertNil(HooksProtocol.parsePreToolUseOutput(#"{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"block"}}"#))
        XCTAssertNil(HooksProtocol.parsePreToolUseOutput(#"{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":7}}"#))
        XCTAssertNil(HooksProtocol.parsePreToolUseOutput(#"{"hookSpecificOutput":{"hookEventName":"Nope"}}"#))
    }

    func testPostToolUseOutputParsesBlockAndAdditionalContextLikeRust() throws {
        let parsed = try XCTUnwrap(HooksProtocol.parsePostToolUseOutput("""
        {
          "decision": "block",
          "reason": "  failed validation  ",
          "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": "tool note"
          }
        }
        """))
        XCTAssertTrue(parsed.shouldBlock)
        XCTAssertEqual(parsed.reason, "  failed validation  ")
        XCTAssertNil(parsed.invalidBlockReason)
        XCTAssertEqual(parsed.additionalContext, "tool note")
        XCTAssertNil(parsed.invalidReason)
    }

    func testPostToolUseOutputAllowsContinueFalseAndStopReasonLikeRust() throws {
        let parsed = try XCTUnwrap(HooksProtocol.parsePostToolUseOutput("""
        {"continue":false,"stopReason":"done","reason":"ignored because stopped"}
        """))
        XCTAssertEqual(parsed.universal.continueProcessing, false)
        XCTAssertEqual(parsed.universal.stopReason, "done")
        XCTAssertFalse(parsed.shouldBlock)
        XCTAssertNil(parsed.invalidBlockReason)
        XCTAssertEqual(parsed.reason, "ignored because stopped")
        XCTAssertNil(parsed.invalidReason)
    }

    func testPostToolUseOutputReportsInvalidBlockReasonLikeRust() throws {
        let missing = try XCTUnwrap(HooksProtocol.parsePostToolUseOutput(#"{"decision":"block"}"#))
        XCTAssertFalse(missing.shouldBlock)
        XCTAssertEqual(
            missing.invalidBlockReason,
            "PostToolUse hook returned decision:block without a non-empty reason"
        )
        XCTAssertNil(missing.invalidReason)

        let empty = try XCTUnwrap(HooksProtocol.parsePostToolUseOutput(#"{"decision":"block","reason":"  "}"#))
        XCTAssertFalse(empty.shouldBlock)
        XCTAssertEqual(
            empty.invalidBlockReason,
            "PostToolUse hook returned decision:block without a non-empty reason"
        )
    }

    func testPostToolUseOutputReportsReasonWithoutDecisionOnlyWhenContinuingLikeRust() throws {
        let parsed = try XCTUnwrap(HooksProtocol.parsePostToolUseOutput(#"{"reason":"because"}"#))
        XCTAssertFalse(parsed.shouldBlock)
        XCTAssertEqual(parsed.invalidBlockReason, "PostToolUse hook returned reason without decision")
        XCTAssertNil(parsed.invalidReason)
    }

    func testPostToolUseOutputReportsUnsupportedUniversalAndHookSpecificFieldsLikeRust() throws {
        let suppressOutput = try XCTUnwrap(HooksProtocol.parsePostToolUseOutput(#"{"suppressOutput":true}"#))
        XCTAssertFalse(suppressOutput.shouldBlock)
        XCTAssertEqual(suppressOutput.invalidReason, "PostToolUse hook returned unsupported suppressOutput")
        XCTAssertNil(suppressOutput.invalidBlockReason)

        let updatedOutput = try XCTUnwrap(HooksProtocol.parsePostToolUseOutput("""
        {
          "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "updatedMCPToolOutput": {}
          }
        }
        """))
        XCTAssertFalse(updatedOutput.shouldBlock)
        XCTAssertEqual(updatedOutput.invalidReason, "PostToolUse hook returned unsupported updatedMCPToolOutput")
    }

    func testPostToolUseOutputRejectsUnknownFieldsAndMalformedShapesLikeRust() {
        XCTAssertNil(HooksProtocol.parsePostToolUseOutput(#"{"decision":"approve"}"#))
        XCTAssertNil(HooksProtocol.parsePostToolUseOutput(#"{"decision":"block","extra":1}"#))
        XCTAssertNil(HooksProtocol.parsePostToolUseOutput(#"{"hookSpecificOutput":{"additionalContext":"missing event"}}"#))
        XCTAssertNil(HooksProtocol.parsePostToolUseOutput(#"{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":3}}"#))
        XCTAssertNil(HooksProtocol.parsePostToolUseOutput(#"{"hookSpecificOutput":{"hookEventName":"PostToolUse","extra":1}}"#))
        XCTAssertNil(HooksProtocol.parsePostToolUseOutput(#"{"hookSpecificOutput":{"hookEventName":"Nope"}}"#))
    }

    func testUserPromptSubmitOutputParsesBlockAndAdditionalContextLikeRust() throws {
        let parsed = try XCTUnwrap(HooksProtocol.parseUserPromptSubmitOutput("""
        {
          "decision": "block",
          "reason": "  no prompt  ",
          "hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": "prompt note"
          }
        }
        """))
        XCTAssertTrue(parsed.shouldBlock)
        XCTAssertEqual(parsed.reason, "  no prompt  ")
        XCTAssertNil(parsed.invalidBlockReason)
        XCTAssertEqual(parsed.additionalContext, "prompt note")
    }

    func testUserPromptSubmitOutputKeepsReasonWithoutDecisionLikeRust() throws {
        let parsed = try XCTUnwrap(HooksProtocol.parseUserPromptSubmitOutput(#"{"reason":"context only"}"#))
        XCTAssertFalse(parsed.shouldBlock)
        XCTAssertEqual(parsed.reason, "context only")
        XCTAssertNil(parsed.invalidBlockReason)
        XCTAssertNil(parsed.additionalContext)
    }

    func testUserPromptSubmitOutputReportsInvalidBlockReasonLikeRust() throws {
        let missing = try XCTUnwrap(HooksProtocol.parseUserPromptSubmitOutput(#"{"decision":"block"}"#))
        XCTAssertFalse(missing.shouldBlock)
        XCTAssertEqual(
            missing.invalidBlockReason,
            "UserPromptSubmit hook returned decision:block without a non-empty reason"
        )

        let empty = try XCTUnwrap(HooksProtocol.parseUserPromptSubmitOutput(#"{"decision":"block","reason":"  "}"#))
        XCTAssertFalse(empty.shouldBlock)
        XCTAssertEqual(
            empty.invalidBlockReason,
            "UserPromptSubmit hook returned decision:block without a non-empty reason"
        )
    }

    func testUserPromptSubmitOutputRejectsUnknownFieldsAndMalformedShapesLikeRust() {
        XCTAssertNil(HooksProtocol.parseUserPromptSubmitOutput(#"{"decision":"approve"}"#))
        XCTAssertNil(HooksProtocol.parseUserPromptSubmitOutput(#"{"decision":"block","extra":1}"#))
        XCTAssertNil(HooksProtocol.parseUserPromptSubmitOutput(#"{"hookSpecificOutput":{"additionalContext":"missing event"}}"#))
        XCTAssertNil(HooksProtocol.parseUserPromptSubmitOutput(#"{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":3}}"#))
        XCTAssertNil(HooksProtocol.parseUserPromptSubmitOutput(#"{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","extra":1}}"#))
        XCTAssertNil(HooksProtocol.parseUserPromptSubmitOutput(#"{"hookSpecificOutput":{"hookEventName":"Nope"}}"#))
    }

    func testStopOutputParsesBlockDecisionLikeRust() throws {
        let parsed = try XCTUnwrap(HooksProtocol.parseStopOutput(#"{"decision":"block","reason":"  keep running  "}"#))
        XCTAssertTrue(parsed.shouldBlock)
        XCTAssertEqual(parsed.reason, "  keep running  ")
        XCTAssertNil(parsed.invalidBlockReason)
    }

    func testStopOutputKeepsReasonWithoutDecisionAndUniversalFieldsLikeRust() throws {
        let parsed = try XCTUnwrap(HooksProtocol.parseStopOutput("""
        {"continue":false,"stopReason":"done","suppressOutput":true,"reason":"context only"}
        """))
        XCTAssertEqual(parsed.universal.continueProcessing, false)
        XCTAssertEqual(parsed.universal.stopReason, "done")
        XCTAssertEqual(parsed.universal.suppressOutput, true)
        XCTAssertFalse(parsed.shouldBlock)
        XCTAssertEqual(parsed.reason, "context only")
        XCTAssertNil(parsed.invalidBlockReason)
    }

    func testStopOutputReportsInvalidBlockReasonLikeRust() throws {
        let missing = try XCTUnwrap(HooksProtocol.parseStopOutput(#"{"decision":"block"}"#))
        XCTAssertFalse(missing.shouldBlock)
        XCTAssertEqual(missing.invalidBlockReason, "Stop hook returned decision:block without a non-empty reason")

        let empty = try XCTUnwrap(HooksProtocol.parseStopOutput(#"{"decision":"block","reason":"  "}"#))
        XCTAssertFalse(empty.shouldBlock)
        XCTAssertEqual(empty.invalidBlockReason, "Stop hook returned decision:block without a non-empty reason")
    }

    func testStopOutputRejectsUnknownFieldsAndMalformedShapesLikeRust() {
        XCTAssertNil(HooksProtocol.parseStopOutput(#"{"decision":"approve"}"#))
        XCTAssertNil(HooksProtocol.parseStopOutput(#"{"decision":"block","extra":1}"#))
        XCTAssertNil(HooksProtocol.parseStopOutput(#"{"hookSpecificOutput":{"hookEventName":"Stop"}}"#))
        XCTAssertNil(HooksProtocol.parseStopOutput(#"{"reason":7}"#))
    }

    func testSessionStartOutputParsesAdditionalContextAndUniversalFieldsLikeRust() throws {
        let parsed = try XCTUnwrap(HooksProtocol.parseSessionStartOutput("""
        {
          "continue": false,
          "stopReason": "stop now",
          "suppressOutput": true,
          "systemMessage": "hello",
          "hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": "session note"
          }
        }
        """))
        XCTAssertEqual(parsed.universal.continueProcessing, false)
        XCTAssertEqual(parsed.universal.stopReason, "stop now")
        XCTAssertEqual(parsed.universal.suppressOutput, true)
        XCTAssertEqual(parsed.universal.systemMessage, "hello")
        XCTAssertEqual(parsed.additionalContext, "session note")
    }

    func testSessionStartOutputDefaultsWithoutHookSpecificOutputLikeRust() throws {
        let parsed = try XCTUnwrap(HooksProtocol.parseSessionStartOutput("{}"))
        XCTAssertEqual(parsed.universal, HookUniversalOutput())
        XCTAssertNil(parsed.additionalContext)
    }

    func testSessionStartOutputRejectsUnknownFieldsAndMalformedShapesLikeRust() {
        XCTAssertNil(HooksProtocol.parseSessionStartOutput(#"{"decision":"block"}"#))
        XCTAssertNil(HooksProtocol.parseSessionStartOutput(#"{"hookSpecificOutput":{"additionalContext":"missing event"}}"#))
        XCTAssertNil(HooksProtocol.parseSessionStartOutput(#"{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":3}}"#))
        XCTAssertNil(HooksProtocol.parseSessionStartOutput(#"{"hookSpecificOutput":{"hookEventName":"SessionStart","extra":1}}"#))
        XCTAssertNil(HooksProtocol.parseSessionStartOutput(#"{"hookSpecificOutput":{"hookEventName":"Nope"}}"#))
        XCTAssertNil(HooksProtocol.parseSessionStartOutput(#"{"hookSpecificOutput":1}"#))
    }

    func testPermissionRequestOutputParsesAllowAndDenyDecisionsLikeRust() throws {
        let allowed = try XCTUnwrap(HooksProtocol.parsePermissionRequestOutput("""
        {
          "hookSpecificOutput": {
            "hookEventName": "PermissionRequest",
            "decision": {"behavior": "allow"}
          }
        }
        """))
        XCTAssertEqual(allowed.universal, HookUniversalOutput())
        XCTAssertEqual(allowed.decision, .allow)
        XCTAssertNil(allowed.invalidReason)

        let denied = try XCTUnwrap(HooksProtocol.parsePermissionRequestOutput("""
        {
          "hookSpecificOutput": {
            "hookEventName": "PermissionRequest",
            "decision": {"behavior": "deny", "message": "  no thanks  "}
          }
        }
        """))
        XCTAssertEqual(denied.decision, .deny(message: "no thanks"))
        XCTAssertNil(denied.invalidReason)
    }

    func testPermissionRequestOutputUsesRustDenyDefaultMessage() throws {
        let parsed = try XCTUnwrap(HooksProtocol.parsePermissionRequestOutput("""
        {
          "hookSpecificOutput": {
            "hookEventName": "PermissionRequest",
            "decision": {"behavior": "deny", "message": "  "}
          }
        }
        """))
        XCTAssertEqual(parsed.decision, .deny(message: "PermissionRequest hook denied approval"))
        XCTAssertNil(parsed.invalidReason)
    }

    func testPermissionRequestOutputReportsUnsupportedUniversalFieldsLikeRust() throws {
        let parsed = try XCTUnwrap(HooksProtocol.parsePermissionRequestOutput("""
        {
          "continue": false,
          "hookSpecificOutput": {
            "hookEventName": "PermissionRequest",
            "decision": {"behavior": "allow"}
          }
        }
        """))
        XCTAssertNil(parsed.decision)
        XCTAssertEqual(parsed.invalidReason, "PermissionRequest hook returned unsupported continue:false")
    }

    func testPermissionRequestOutputReportsUnsupportedReservedFieldsLikeRust() throws {
        let updatedInput = try XCTUnwrap(HooksProtocol.parsePermissionRequestOutput("""
        {
          "hookSpecificOutput": {
            "hookEventName": "PermissionRequest",
            "decision": {"behavior": "allow", "updatedInput": {}}
          }
        }
        """))
        XCTAssertEqual(updatedInput.invalidReason, "PermissionRequest hook returned unsupported updatedInput")
        XCTAssertNil(updatedInput.decision)

        let updatedPermissions = try XCTUnwrap(HooksProtocol.parsePermissionRequestOutput("""
        {
          "hookSpecificOutput": {
            "hookEventName": "PermissionRequest",
            "decision": {"behavior": "allow", "updatedPermissions": {}}
          }
        }
        """))
        XCTAssertEqual(updatedPermissions.invalidReason, "PermissionRequest hook returned unsupported updatedPermissions")
        XCTAssertNil(updatedPermissions.decision)

        let interrupt = try XCTUnwrap(HooksProtocol.parsePermissionRequestOutput("""
        {
          "hookSpecificOutput": {
            "hookEventName": "PermissionRequest",
            "decision": {"behavior": "allow", "interrupt": true}
          }
        }
        """))
        XCTAssertEqual(interrupt.invalidReason, "PermissionRequest hook returned unsupported interrupt:true")
        XCTAssertNil(interrupt.decision)
    }

    func testPermissionRequestOutputRejectsUnknownFieldsAndMalformedShapesLikeRust() {
        XCTAssertNil(HooksProtocol.parsePermissionRequestOutput(#"{"hookSpecificOutput":{"decision":{"behavior":"allow"}}}"#))
        XCTAssertNil(HooksProtocol.parsePermissionRequestOutput(#"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","extra":1}}}"#))
        XCTAssertNil(HooksProtocol.parsePermissionRequestOutput(#"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"ask"}}}"#))
        XCTAssertNil(HooksProtocol.parsePermissionRequestOutput(#"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","interrupt":null}}}"#))
        XCTAssertNil(HooksProtocol.parsePermissionRequestOutput(#"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","extra":1}}"#))
        XCTAssertNil(HooksProtocol.parsePermissionRequestOutput(#"{"hookSpecificOutput":{"hookEventName":"Nope"}}"#))
        XCTAssertNil(HooksProtocol.parsePermissionRequestOutput(#"{"hookSpecificOutput":1}"#))
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
