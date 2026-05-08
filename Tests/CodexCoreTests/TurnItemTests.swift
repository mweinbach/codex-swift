import XCTest
@testable import CodexCore

final class TurnItemTests: XCTestCase {
    func testUserMessageItemBuildsLegacyMessageAndImageURLs() throws {
        let item = UserMessageItem(
            id: "user-1",
            content: [
                .text("hello"),
                .image(imageURL: "data:image/png;base64,aaa"),
                .localImage(path: "/tmp/local.png"),
                .text(" world"),
                .skill(name: "swift", path: "/skills/swift/SKILL.md")
            ]
        )

        XCTAssertEqual(item.message, "hello world")
        XCTAssertEqual(item.imageURLs, ["data:image/png;base64,aaa"])
        XCTAssertEqual(item.asLegacyEvent(), .userMessage(UserMessageEvent(
            message: "hello world",
            images: ["data:image/png;base64,aaa"]
        )))
    }

    func testUserMessageLegacyEventKeepsEmptyImagesArray() throws {
        let event = UserMessageItem(id: "user-1", content: [.text("hello")]).asLegacyEvent()

        try XCTAssertJSONObjectEqual(event, [
            "type": "user_message",
            "message": "hello",
            "images": []
        ])
    }

    func testUserMessageEventOmitsNilImages() throws {
        let event = LegacyEventMessage.userMessage(UserMessageEvent(message: "hello", images: nil))

        try XCTAssertJSONObjectEqual(event, [
            "type": "user_message",
            "message": "hello"
        ])
    }

    func testAgentMessageItemSplitsLegacyTextEvents() {
        let item = AgentMessageItem(id: "agent-1", content: [.text("one"), .text("two")])

        XCTAssertEqual(item.asLegacyEvents(), [
            .agentMessage(AgentMessageEvent(message: "one")),
            .agentMessage(AgentMessageEvent(message: "two"))
        ])
    }

    func testReasoningItemHonorsRawReasoningFlag() {
        let item = ReasoningItem(
            id: "reason-1",
            summaryText: ["summary 1", "summary 2"],
            rawContent: ["raw"]
        )

        XCTAssertEqual(item.asLegacyEvents(showRawAgentReasoning: false), [
            .agentReasoning(AgentReasoningEvent(text: "summary 1")),
            .agentReasoning(AgentReasoningEvent(text: "summary 2"))
        ])
        XCTAssertEqual(item.asLegacyEvents(showRawAgentReasoning: true), [
            .agentReasoning(AgentReasoningEvent(text: "summary 1")),
            .agentReasoning(AgentReasoningEvent(text: "summary 2")),
            .agentReasoningRawContent(AgentReasoningRawContentEvent(text: "raw"))
        ])
    }

    func testReasoningItemDefaultsMissingRawContentToEmptyArray() throws {
        let json = #"{"id":"reason-1","summary_text":["summary"]}"#
        let item = try JSONDecoder().decode(ReasoningItem.self, from: Data(json.utf8))

        XCTAssertEqual(item, ReasoningItem(id: "reason-1", summaryText: ["summary"], rawContent: []))
    }

    func testWebSearchAndTurnItemIDs() {
        let item = TurnItem.webSearch(WebSearchItem(id: "search-1", query: "find docs"))

        XCTAssertEqual(item.id, "search-1")
        XCTAssertEqual(item.asLegacyEvents(showRawAgentReasoning: false), [
            .webSearchEnd(WebSearchEndEvent(callID: "search-1", query: "find docs"))
        ])
    }

    func testTurnItemWireShapeUsesRustTags() throws {
        let item = TurnItem.agentMessage(AgentMessageItem(id: "agent-1", content: [.text("hello")]))

        try XCTAssertJSONObjectEqual(item, [
            "type": "AgentMessage",
            "id": "agent-1",
            "content": [
                [
                    "type": "Text",
                    "text": "hello"
                ]
            ]
        ])

        let data = try JSONEncoder().encode(item)
        XCTAssertEqual(try JSONDecoder().decode(TurnItem.self, from: data), item)
    }

    func testLegacyEventWireShapeUsesRustSnakeCaseTags() throws {
        let event = LegacyEventMessage.webSearchEnd(WebSearchEndEvent(callID: "search-1", query: "docs"))

        try XCTAssertJSONObjectEqual(event, [
            "type": "web_search_end",
            "call_id": "search-1",
            "query": "docs"
        ])

        let data = try JSONEncoder().encode(event)
        XCTAssertEqual(try JSONDecoder().decode(LegacyEventMessage.self, from: data), event)
    }

    func testItemStartedEventEmitsWebSearchBeginOnlyForWebSearch() throws {
        let threadID = try ConversationId(string: "018f7a2d-4c5b-7abc-8def-0123456789ab")
        let webSearch = ItemStartedEvent(
            threadID: threadID,
            turnID: "turn-1",
            item: .webSearch(WebSearchItem(id: "search-1", query: "docs"))
        )
        let userMessage = ItemStartedEvent(
            threadID: threadID,
            turnID: "turn-1",
            item: .userMessage(UserMessageItem(id: "user-1", content: []))
        )

        XCTAssertEqual(webSearch.asLegacyEvents(), [
            .webSearchBegin(WebSearchBeginEvent(callID: "search-1"))
        ])
        XCTAssertEqual(userMessage.asLegacyEvents(), [])
    }

    func testItemCompletedEventDelegatesToTurnItemLegacyEvents() throws {
        let threadID = try ConversationId(string: "018f7a2d-4c5b-7abc-8def-0123456789ab")
        let completed = ItemCompletedEvent(
            threadID: threadID,
            turnID: "turn-1",
            item: .reasoning(ReasoningItem(id: "reason-1", summaryText: ["summary"], rawContent: ["raw"]))
        )

        XCTAssertEqual(completed.asLegacyEvents(showRawAgentReasoning: true), [
            .agentReasoning(AgentReasoningEvent(text: "summary")),
            .agentReasoningRawContent(AgentReasoningRawContentEvent(text: "raw"))
        ])
    }
}
