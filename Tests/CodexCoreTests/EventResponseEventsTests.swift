import CodexCore
import XCTest

final class EventResponseEventsTests: XCTestCase {
    func testGetHistoryEntryResponseWireShapeOmitsMissingEntry() throws {
        try XCTAssertJSONObjectEqual(GetHistoryEntryResponseEvent(offset: 3, logID: 99), [
            "offset": 3,
            "log_id": 99
        ])
    }

    func testGetHistoryEntryResponseWireShapeWithEntry() throws {
        try XCTAssertJSONObjectEqual(GetHistoryEntryResponseEvent(
            offset: 4,
            logID: 100,
            entry: HistoryEntry(conversationID: "conv-1", ts: 123, text: "hello")
        ), [
            "offset": 4,
            "log_id": 100,
            "entry": [
                "conversation_id": "conv-1",
                "ts": 123,
                "text": "hello"
            ]
        ])
    }

    func testListCustomPromptsResponseWireShape() throws {
        try XCTAssertJSONObjectEqual(ListCustomPromptsResponseEvent(customPrompts: [
            CustomPrompt(
                name: "review",
                path: "/tmp/review.md",
                content: "Review this",
                description: "Review prompt",
                argumentHint: "<target>"
            ),
            CustomPrompt(name: "summarize", path: "/tmp/summarize.md", content: "Summarize")
        ]), [
            "custom_prompts": [
                [
                    "name": "review",
                    "path": "/tmp/review.md",
                    "content": "Review this",
                    "description": "Review prompt",
                    "argument_hint": "<target>"
                ],
                [
                    "name": "summarize",
                    "path": "/tmp/summarize.md",
                    "content": "Summarize"
                ]
            ]
        ])
    }

    func testRawResponseItemWireShape() throws {
        try XCTAssertJSONObjectEqual(RawResponseItemEvent(item: .message(
            role: "assistant",
            content: [.outputText(text: "done")]
        )), [
            "item": [
                "type": "message",
                "role": "assistant",
                "content": [
                    [
                        "type": "output_text",
                        "text": "done"
                    ]
                ]
            ]
        ])
    }

    func testResponseEventsAreEventMessages() throws {
        try XCTAssertJSONObjectEqual(EventMessage.getHistoryEntryResponse(GetHistoryEntryResponseEvent(
            offset: 1,
            logID: 2
        )), [
            "type": "get_history_entry_response",
            "offset": 1,
            "log_id": 2
        ])

        try XCTAssertJSONObjectEqual(EventMessage.listCustomPromptsResponse(ListCustomPromptsResponseEvent(
            customPrompts: []
        )), [
            "type": "list_custom_prompts_response",
            "custom_prompts": []
        ])

        let message = try JSONDecoder().decode(EventMessage.self, from: Data("""
        {
          "type": "raw_response_item",
          "item": {
            "type": "message",
            "role": "assistant",
            "content": [
              {
                "type": "output_text",
                "text": "done"
              }
            ]
          }
        }
        """.utf8))

        XCTAssertEqual(message, .rawResponseItem(RawResponseItemEvent(item: .message(
            role: "assistant",
            content: [.outputText(text: "done")]
        ))))
    }
}
