import CodexCore
import XCTest

final class EventMessageTests: XCTestCase {
    func testEventWrapperUsesRustIDAndMsgShape() throws {
        let event = Event(id: "submission-1", msg: .taskStarted(TaskStartedEvent(modelContextWindow: nil)))

        try XCTAssertJSONObjectEqual(event, [
            "id": "submission-1",
            "msg": [
                "type": "task_started",
                "model_context_window": NSNull()
            ]
        ])

        let data = try JSONEncoder().encode(event)
        XCTAssertEqual(try JSONDecoder().decode(Event.self, from: data), event)
    }

    func testEventMessageFlattensPayloadFieldsBesideType() throws {
        let msg = EventMessage.error(ErrorEvent(
            message: "stream disconnected",
            codexErrorInfo: .responseStreamDisconnected(httpStatusCode: nil)
        ))

        try XCTAssertJSONObjectEqual(msg, [
            "type": "error",
            "message": "stream disconnected",
            "codex_error_info": [
                "response_stream_disconnected": [
                    "http_status_code": NSNull()
                ]
            ]
        ])

        let data = try JSONEncoder().encode(msg)
        XCTAssertEqual(try JSONDecoder().decode(EventMessage.self, from: data), msg)
    }

    func testUnitEventMessagesUseTypeOnlyRustShape() throws {
        try XCTAssertJSONObjectEqual(EventMessage.contextCompacted(ContextCompactedEvent()), [
            "type": "context_compacted"
        ])
        try XCTAssertJSONObjectEqual(EventMessage.skillsUpdateAvailable, [
            "type": "skills_update_available"
        ])
        try XCTAssertJSONObjectEqual(EventMessage.shutdownComplete, [
            "type": "shutdown_complete"
        ])
    }

    func testEventMessageCoversPortedStreamingAndToolPayloads() throws {
        try XCTAssertJSONObjectEqual(EventMessage.execCommandOutputDelta(ExecCommandOutputDeltaEvent(
            callID: "exec-1",
            stream: .stderr,
            chunk: [0xde, 0xad]
        )), [
            "type": "exec_command_output_delta",
            "call_id": "exec-1",
            "stream": "stderr",
            "chunk": "3q0="
        ])

        try XCTAssertJSONObjectEqual(EventMessage.agentMessageContentDelta(AgentMessageContentDeltaEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            itemID: "item-1",
            delta: "hi"
        )), [
            "type": "agent_message_content_delta",
            "thread_id": "thread-1",
            "turn_id": "turn-1",
            "item_id": "item-1",
            "delta": "hi"
        ])

        let message = try JSONDecoder().decode(EventMessage.self, from: Data("""
        {
          "type": "reasoning_content_delta",
          "thread_id": "thread-1",
          "turn_id": "turn-1",
          "item_id": "item-1",
          "delta": "thinking"
        }
        """.utf8))

        XCTAssertEqual(message, .reasoningContentDelta(ReasoningContentDeltaEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            itemID: "item-1",
            delta: "thinking"
        )))
    }

    func testEventMessageDecodesReviewAndPlanPayloads() throws {
        let plan = EventMessage.planUpdate(UpdatePlanArguments(
            explanation: "next",
            plan: [PlanItemArgument(step: "port", status: .inProgress)]
        ))

        try XCTAssertJSONObjectEqual(plan, [
            "type": "plan_update",
            "explanation": "next",
            "plan": [
                [
                    "step": "port",
                    "status": "in_progress"
                ]
            ]
        ])

        let review = try JSONDecoder().decode(EventMessage.self, from: Data("""
        {
          "type": "entered_review_mode",
          "target": {
            "type": "uncommittedChanges"
          }
        }
        """.utf8))

        XCTAssertEqual(review, .enteredReviewMode(ReviewRequest(target: .uncommittedChanges)))
    }

    func testUnsupportedEventMessageVariantThrows() {
        XCTAssertThrowsError(try JSONDecoder().decode(
            EventMessage.self,
            from: Data(#"{"type":"mcp_tool_call_begin","call_id":"tool-1"}"#.utf8)
        ))
    }
}
