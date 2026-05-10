import CodexCore
import XCTest

final class StatusEventsTests: XCTestCase {
    func testCodexErrorInfoUsesRustStringVariants() throws {
        XCTAssertEqual(try encode(CodexErrorInfo.contextWindowExceeded), #""context_window_exceeded""#)
        XCTAssertEqual(try encode(CodexErrorInfo.usageLimitExceeded), #""usage_limit_exceeded""#)
        XCTAssertEqual(try encode(CodexErrorInfo.serverOverloaded), #""server_overloaded""#)
        XCTAssertEqual(try encode(CodexErrorInfo.cyberPolicy), #""cyber_policy""#)
        XCTAssertEqual(try encode(CodexErrorInfo.internalServerError), #""internal_server_error""#)
        XCTAssertEqual(try encode(CodexErrorInfo.unauthorized), #""unauthorized""#)
        XCTAssertEqual(try encode(CodexErrorInfo.badRequest), #""bad_request""#)
        XCTAssertEqual(try encode(CodexErrorInfo.sandboxError), #""sandbox_error""#)
        XCTAssertEqual(try encode(CodexErrorInfo.threadRollbackFailed), #""thread_rollback_failed""#)
        XCTAssertEqual(try encode(CodexErrorInfo.other), #""other""#)

        XCTAssertEqual(
            try JSONDecoder().decode(CodexErrorInfo.self, from: Data(#""bad_request""#.utf8)),
            .badRequest
        )
    }

    func testCodexErrorInfoUsesRustExternallyTaggedStatusVariants() throws {
        try XCTAssertJSONObjectEqual(CodexErrorInfo.httpConnectionFailed(httpStatusCode: 429), [
            "http_connection_failed": [
                "http_status_code": 429
            ]
        ])
        try XCTAssertJSONObjectEqual(CodexErrorInfo.responseStreamConnectionFailed(httpStatusCode: nil), [
            "response_stream_connection_failed": [
                "http_status_code": NSNull()
            ]
        ])
        try XCTAssertJSONObjectEqual(CodexErrorInfo.responseStreamDisconnected(httpStatusCode: 502), [
            "response_stream_disconnected": [
                "http_status_code": 502
            ]
        ])
        try XCTAssertJSONObjectEqual(CodexErrorInfo.responseTooManyFailedAttempts(httpStatusCode: nil), [
            "response_too_many_failed_attempts": [
                "http_status_code": NSNull()
            ]
        ])
        try XCTAssertJSONObjectEqual(CodexErrorInfo.activeTurnNotSteerable(turnKind: .review), [
            "active_turn_not_steerable": [
                "turn_kind": "review"
            ]
        ])

        let json = #"{"http_connection_failed":{"http_status_code":503}}"#
        XCTAssertEqual(
            try JSONDecoder().decode(CodexErrorInfo.self, from: Data(json.utf8)),
            .httpConnectionFailed(httpStatusCode: 503)
        )

        let nonSteerableJSON = #"{"active_turn_not_steerable":{"turn_kind":"compact"}}"#
        XCTAssertEqual(
            try JSONDecoder().decode(CodexErrorInfo.self, from: Data(nonSteerableJSON.utf8)),
            .activeTurnNotSteerable(turnKind: .compact)
        )
    }

    func testErrorAndStreamErrorEventsIncludeNullOptionalsLikeRust() throws {
        try XCTAssertJSONObjectEqual(ErrorEvent(message: "failed"), [
            "message": "failed",
            "codex_error_info": NSNull()
        ])

        try XCTAssertJSONObjectEqual(ErrorEvent(
            message: "limited",
            codexErrorInfo: .usageLimitExceeded
        ), [
            "message": "limited",
            "codex_error_info": "usage_limit_exceeded"
        ])

        try XCTAssertJSONObjectEqual(StreamErrorEvent(message: "stream failed"), [
            "message": "stream failed",
            "codex_error_info": NSNull(),
            "additional_details": NSNull()
        ])

        try XCTAssertJSONObjectEqual(StreamErrorEvent(
            message: "stream failed",
            codexErrorInfo: .responseStreamDisconnected(httpStatusCode: 500),
            additionalDetails: "retry exhausted"
        ), [
            "message": "stream failed",
            "codex_error_info": [
                "response_stream_disconnected": [
                    "http_status_code": 500
                ]
            ],
            "additional_details": "retry exhausted"
        ])
    }

    func testErrorEventAffectsTurnStatusMatchesRust() {
        XCTAssertFalse(ErrorEvent(
            message: "rollback failed",
            codexErrorInfo: .threadRollbackFailed
        ).affectsTurnStatus)
        XCTAssertFalse(ErrorEvent(
            message: "active turn is not steerable",
            codexErrorInfo: .activeTurnNotSteerable(turnKind: .review)
        ).affectsTurnStatus)
        XCTAssertTrue(ErrorEvent(message: "failed").affectsTurnStatus)
        XCTAssertTrue(ErrorEvent(
            message: "failed",
            codexErrorInfo: .other
        ).affectsTurnStatus)
        XCTAssertTrue(ErrorEvent(
            message: "limited",
            codexErrorInfo: .usageLimitExceeded
        ).affectsTurnStatus)
    }

    func testTaskEventsIncludeNullOptionalsLikeRust() throws {
        try XCTAssertJSONObjectEqual(TaskStartedEvent(turnID: "turn-1", modelContextWindow: nil), [
            "turn_id": "turn-1",
            "model_context_window": NSNull(),
            "collaboration_mode_kind": "default"
        ])
        try XCTAssertJSONObjectEqual(TaskStartedEvent(turnID: "turn-1", modelContextWindow: 128_000), [
            "turn_id": "turn-1",
            "model_context_window": 128_000,
            "collaboration_mode_kind": "default"
        ])
        try XCTAssertJSONObjectEqual(
            TaskStartedEvent(turnID: "turn-1", modelContextWindow: nil, collaborationModeKind: .plan),
            [
                "turn_id": "turn-1",
                "model_context_window": NSNull(),
                "collaboration_mode_kind": "plan"
            ]
        )

        let legacyStarted = try JSONDecoder().decode(
            TaskStartedEvent.self,
            from: Data(#"{"turn_id":"turn-1","model_context_window":null}"#.utf8)
        )
        XCTAssertEqual(legacyStarted.collaborationModeKind, .defaultMode)

        XCTAssertThrowsError(try JSONDecoder().decode(
            TaskStartedEvent.self,
            from: Data(#"{"model_context_window":null}"#.utf8)
        ))
        XCTAssertThrowsError(try JSONDecoder().decode(
            TaskCompleteEvent.self,
            from: Data(#"{"last_agent_message":null}"#.utf8)
        ))

        try XCTAssertJSONObjectEqual(TaskCompleteEvent(turnID: "turn-1", lastAgentMessage: nil), [
            "turn_id": "turn-1",
            "last_agent_message": NSNull()
        ])
        try XCTAssertJSONObjectEqual(TaskCompleteEvent(turnID: "turn-1", lastAgentMessage: "done"), [
            "turn_id": "turn-1",
            "last_agent_message": "done"
        ])
    }

    func testNoticeUndoAndWarningEventsMatchRustOptionalOmissionRules() throws {
        try XCTAssertJSONObjectEqual(WarningEvent(message: "heads up"), [
            "message": "heads up"
        ])
        try XCTAssertJSONObjectEqual(StreamInfoEvent(message: "retrying"), [
            "message": "retrying"
        ])
        try XCTAssertJSONObjectEqual(DeprecationNoticeEvent(summary: "old flag"), [
            "summary": "old flag"
        ])
        try XCTAssertJSONObjectEqual(DeprecationNoticeEvent(summary: "old flag", details: "use --new"), [
            "summary": "old flag",
            "details": "use --new"
        ])
        try XCTAssertJSONObjectEqual(UndoStartedEvent(), [:])
        try XCTAssertJSONObjectEqual(UndoStartedEvent(message: "undoing"), [
            "message": "undoing"
        ])
        try XCTAssertJSONObjectEqual(UndoCompletedEvent(success: true), [
            "success": true
        ])
        try XCTAssertJSONObjectEqual(UndoCompletedEvent(success: false, message: "conflict"), [
            "success": false,
            "message": "conflict"
        ])
    }

    func testTurnAbortedEventAndReasonsUseRustSnakeCaseValues() throws {
        XCTAssertEqual(try encode(TurnAbortReason.interrupted), #""interrupted""#)
        XCTAssertEqual(try encode(TurnAbortReason.replaced), #""replaced""#)
        XCTAssertEqual(try encode(TurnAbortReason.reviewEnded), #""review_ended""#)
        XCTAssertEqual(try encode(TurnAbortReason.budgetLimited), #""budget_limited""#)

        try XCTAssertJSONObjectEqual(TurnAbortedEvent(reason: .budgetLimited), [
            "reason": "budget_limited"
        ])
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        String(data: try JSONEncoder().encode(value), encoding: .utf8) ?? ""
    }
}
