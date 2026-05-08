import CodexCore
import XCTest

final class ApprovalsTests: XCTestCase {
    func testExecPolicyAmendmentIsTransparentArray() throws {
        let amendment = ExecPolicyAmendment(command: ["git", "status"])
        let encoded = try String(data: JSONEncoder().encode(amendment), encoding: .utf8)
        XCTAssertEqual(encoded, #"["git","status"]"#)
        XCTAssertEqual(try JSONDecoder().decode(ExecPolicyAmendment.self, from: Data(encoded!.utf8)), amendment)
    }

    func testReviewDecisionUnitVariantsUseRustSnakeCaseStrings() throws {
        let cases: [(ReviewDecision, String)] = [
            (.approved, #""approved""#),
            (.approvedForSession, #""approved_for_session""#),
            (.denied, #""denied""#),
            (.abort, #""abort""#)
        ]

        for (decision, json) in cases {
            let encoded = try String(data: JSONEncoder().encode(decision), encoding: .utf8)
            XCTAssertEqual(encoded, json)
            XCTAssertEqual(try JSONDecoder().decode(ReviewDecision.self, from: Data(json.utf8)), decision)
        }
    }

    func testReviewDecisionExecPolicyAmendmentUsesExternallyTaggedRustShape() throws {
        let decision = ReviewDecision.approvedExecpolicyAmendment(
            proposedExecpolicyAmendment: ExecPolicyAmendment(command: ["git", "status"])
        )
        let json = #"{"approved_execpolicy_amendment":{"proposed_execpolicy_amendment":["git","status"]}}"#

        let encoded = try String(data: JSONEncoder().encode(decision), encoding: .utf8)
        XCTAssertEqual(encoded, json)
        XCTAssertEqual(try JSONDecoder().decode(ReviewDecision.self, from: Data(json.utf8)), decision)
    }

    func testReviewDecisionDefaultIsDenied() {
        XCTAssertEqual(ReviewDecision.default, .denied)
    }

    func testRequestIDUsesUntaggedStringOrIntegerShape() throws {
        XCTAssertEqual(try encode(RequestID.string("abc")), #""abc""#)
        XCTAssertEqual(try encode(RequestID.integer(42)), #"42"#)
        XCTAssertEqual(try JSONDecoder().decode(RequestID.self, from: Data(#""abc""#.utf8)), .string("abc"))
        XCTAssertEqual(try JSONDecoder().decode(RequestID.self, from: Data(#"42"#.utf8)), .integer(42))
    }

    func testExecApprovalRequestWireShapeAndDefaultTurnID() throws {
        let event = ExecApprovalRequestEvent(
            callID: "exec-1",
            turnID: "turn-1",
            command: ["git", "status"],
            cwd: "/repo",
            reason: "needs unsandboxed retry",
            proposedExecPolicyAmendment: ExecPolicyAmendment(command: ["git", "status"]),
            parsedCmd: [.unknown(cmd: "git status")]
        )

        try XCTAssertJSONObjectEqual(event, [
            "call_id": "exec-1",
            "turn_id": "turn-1",
            "command": ["git", "status"],
            "cwd": "/repo",
            "reason": "needs unsandboxed retry",
            "proposed_execpolicy_amendment": ["git", "status"],
            "parsed_cmd": [
                [
                    "type": "unknown",
                    "cmd": "git status"
                ]
            ]
        ])

        let missingDefault = """
        {
          "call_id": "exec-1",
          "command": ["pwd"],
          "cwd": "/repo",
          "parsed_cmd": []
        }
        """
        XCTAssertEqual(
            try JSONDecoder().decode(ExecApprovalRequestEvent.self, from: Data(missingDefault.utf8)),
            ExecApprovalRequestEvent(callID: "exec-1", command: ["pwd"], cwd: "/repo", parsedCmd: [])
        )
    }

    func testElicitationRequestAndActionWireShapes() throws {
        try XCTAssertJSONObjectEqual(ElicitationRequestEvent(
            serverName: "mcp",
            id: .integer(7),
            message: "Confirm?"
        ), [
            "server_name": "mcp",
            "id": 7,
            "message": "Confirm?"
        ])

        XCTAssertEqual(try encode(ElicitationAction.accept), #""accept""#)
        XCTAssertEqual(try encode(ElicitationAction.decline), #""decline""#)
        XCTAssertEqual(try encode(ElicitationAction.cancel), #""cancel""#)
    }

    func testApplyPatchApprovalRequestWireShapeAndDefaultTurnID() throws {
        let event = ApplyPatchApprovalRequestEvent(
            callID: "patch-1",
            turnID: "turn-1",
            changes: [
                "Sources/App.swift": .update(unifiedDiff: "@@ -1 +1 @@\n-old\n+new\n", movePath: nil)
            ],
            reason: "needs write access",
            grantRoot: "/repo/Sources"
        )

        try XCTAssertJSONObjectEqual(event, [
            "call_id": "patch-1",
            "turn_id": "turn-1",
            "changes": [
                "Sources/App.swift": [
                    "type": "update",
                    "unified_diff": "@@ -1 +1 @@\n-old\n+new\n",
                    "move_path": NSNull()
                ]
            ],
            "reason": "needs write access",
            "grant_root": "/repo/Sources"
        ])

        let missingDefault = """
        {
          "call_id": "patch-1",
          "changes": {}
        }
        """
        XCTAssertEqual(
            try JSONDecoder().decode(ApplyPatchApprovalRequestEvent.self, from: Data(missingDefault.utf8)),
            ApplyPatchApprovalRequestEvent(callID: "patch-1", changes: [:])
        )
    }

    func testApprovalRequestsAreEventMessages() throws {
        try XCTAssertJSONObjectEqual(EventMessage.execApprovalRequest(ExecApprovalRequestEvent(
            callID: "exec-1",
            command: ["pwd"],
            cwd: "/repo",
            parsedCmd: []
        )), [
            "type": "exec_approval_request",
            "call_id": "exec-1",
            "turn_id": "",
            "command": ["pwd"],
            "cwd": "/repo",
            "parsed_cmd": []
        ])

        try XCTAssertJSONObjectEqual(EventMessage.elicitationRequest(ElicitationRequestEvent(
            serverName: "mcp",
            id: .string("request-1"),
            message: "Continue?"
        )), [
            "type": "elicitation_request",
            "server_name": "mcp",
            "id": "request-1",
            "message": "Continue?"
        ])
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        String(data: try JSONEncoder().encode(value), encoding: .utf8) ?? ""
    }
}
