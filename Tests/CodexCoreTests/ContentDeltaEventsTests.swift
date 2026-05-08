import CodexCore
import XCTest

final class ContentDeltaEventsTests: XCTestCase {
    func testLegacyDeltaEventWireShapesUseRustTags() throws {
        try XCTAssertJSONObjectEqual(LegacyEventMessage.agentMessageDelta(
            AgentMessageDeltaEvent(delta: "hel")
        ), [
            "type": "agent_message_delta",
            "delta": "hel"
        ])

        try XCTAssertJSONObjectEqual(LegacyEventMessage.agentReasoningDelta(
            AgentReasoningDeltaEvent(delta: "thinking")
        ), [
            "type": "agent_reasoning_delta",
            "delta": "thinking"
        ])

        try XCTAssertJSONObjectEqual(LegacyEventMessage.agentReasoningRawContentDelta(
            AgentReasoningRawContentDeltaEvent(delta: "raw")
        ), [
            "type": "agent_reasoning_raw_content_delta",
            "delta": "raw"
        ])
    }

    func testReasoningSectionBreakDefaultsMissingFieldsLikeRust() throws {
        let json = #"{"type":"agent_reasoning_section_break"}"#
        let event = try JSONDecoder().decode(LegacyEventMessage.self, from: Data(json.utf8))

        XCTAssertEqual(event, .agentReasoningSectionBreak(AgentReasoningSectionBreakEvent()))
        try XCTAssertJSONObjectEqual(event, [
            "type": "agent_reasoning_section_break",
            "item_id": "",
            "summary_index": 0
        ])
    }

    func testModernContentDeltaEventsUseRustWireShapeAndLegacyProjection() throws {
        let message = AgentMessageContentDeltaEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            itemID: "item-1",
            delta: "hi"
        )

        try XCTAssertJSONObjectEqual(message, [
            "thread_id": "thread-1",
            "turn_id": "turn-1",
            "item_id": "item-1",
            "delta": "hi"
        ])
        XCTAssertEqual(message.asLegacyEvents(), [
            .agentMessageDelta(AgentMessageDeltaEvent(delta: "hi"))
        ])
    }

    func testReasoningContentDeltaDefaultsSummaryIndexLikeRust() throws {
        let json = #"{"thread_id":"thread-1","turn_id":"turn-1","item_id":"item-1","delta":"step"}"#
        let event = try JSONDecoder().decode(ReasoningContentDeltaEvent.self, from: Data(json.utf8))

        XCTAssertEqual(event, ReasoningContentDeltaEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            itemID: "item-1",
            delta: "step",
            summaryIndex: 0
        ))
        XCTAssertEqual(event.asLegacyEvents(), [
            .agentReasoningDelta(AgentReasoningDeltaEvent(delta: "step"))
        ])
        try XCTAssertJSONObjectEqual(event, [
            "thread_id": "thread-1",
            "turn_id": "turn-1",
            "item_id": "item-1",
            "delta": "step",
            "summary_index": 0
        ])
    }

    func testReasoningRawContentDeltaDefaultsContentIndexLikeRust() throws {
        let json = #"{"thread_id":"thread-1","turn_id":"turn-1","item_id":"item-1","delta":"raw"}"#
        let event = try JSONDecoder().decode(ReasoningRawContentDeltaEvent.self, from: Data(json.utf8))

        XCTAssertEqual(event, ReasoningRawContentDeltaEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            itemID: "item-1",
            delta: "raw",
            contentIndex: 0
        ))
        XCTAssertEqual(event.asLegacyEvents(), [
            .agentReasoningRawContentDelta(AgentReasoningRawContentDeltaEvent(delta: "raw"))
        ])
        try XCTAssertJSONObjectEqual(event, [
            "thread_id": "thread-1",
            "turn_id": "turn-1",
            "item_id": "item-1",
            "delta": "raw",
            "content_index": 0
        ])
    }

    func testLegacyDeltaEventsRoundTrip() throws {
        let event = LegacyEventMessage.agentReasoningSectionBreak(AgentReasoningSectionBreakEvent(
            itemID: "item-1",
            summaryIndex: 2
        ))

        let data = try JSONEncoder().encode(event)
        XCTAssertEqual(try JSONDecoder().decode(LegacyEventMessage.self, from: data), event)
    }
}
