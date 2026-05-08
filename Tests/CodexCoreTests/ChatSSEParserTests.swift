import CodexCore
import XCTest

final class ChatSSEParserTests: XCTestCase {
    func testConcatenatesToolCallArgumentsAcrossDeltas() {
        let events = collect([
            json(["choices": [[
                "delta": [
                    "tool_calls": [[
                        "id": "call_a",
                        "index": 0,
                        "function": ["name": "do_a"]
                    ]]
                ]
            ]]]),
            json(["choices": [[
                "delta": [
                    "tool_calls": [[
                        "index": 0,
                        "function": ["arguments": "{ \"foo\":"]
                    ]]
                ]
            ]]]),
            json(["choices": [[
                "delta": [
                    "tool_calls": [[
                        "index": 0,
                        "function": ["arguments": "1}"]
                    ]]
                ]
            ]]]),
            json(["choices": [["finish_reason": "tool_calls"]]])
        ])

        XCTAssertEqual(events, [
            .success(.outputItemDone(.functionCall(name: "do_a", arguments: "{ \"foo\":1}", callID: "call_a"))),
            .success(.completed(responseID: "", tokenUsage: nil))
        ])
    }

    func testEmitsMultipleToolCallsInRustOrder() {
        let events = collect([
            json(["choices": [[
                "delta": [
                    "tool_calls": [[
                        "id": "call_a",
                        "function": ["name": "do_a", "arguments": #"{"foo":1}"#]
                    ]]
                ]
            ]]]),
            json(["choices": [[
                "delta": [
                    "tool_calls": [[
                        "id": "call_b",
                        "function": ["name": "do_b", "arguments": #"{"bar":2}"#]
                    ]]
                ]
            ]]]),
            json(["choices": [["finish_reason": "tool_calls"]]])
        ])

        XCTAssertEqual(events, [
            .success(.outputItemDone(.functionCall(name: "do_a", arguments: #"{"foo":1}"#, callID: "call_a"))),
            .success(.outputItemDone(.functionCall(name: "do_b", arguments: #"{"bar":2}"#, callID: "call_b"))),
            .success(.completed(responseID: "", tokenUsage: nil))
        ])
    }

    func testEmitsToolCallsForMultipleChoices() {
        let events = collect([
            json(["choices": [
                [
                    "delta": [
                        "tool_calls": [[
                            "id": "call_a",
                            "index": 0,
                            "function": ["name": "do_a", "arguments": "{}"]
                        ]]
                    ],
                    "finish_reason": "tool_calls"
                ],
                [
                    "delta": [
                        "tool_calls": [[
                            "id": "call_b",
                            "index": 0,
                            "function": ["name": "do_b", "arguments": "{}"]
                        ]]
                    ],
                    "finish_reason": "tool_calls"
                ]
            ]])
        ])

        XCTAssertEqual(events, [
            .success(.outputItemDone(.functionCall(name: "do_a", arguments: "{}", callID: "call_a"))),
            .success(.outputItemDone(.functionCall(name: "do_b", arguments: "{}", callID: "call_b"))),
            .success(.completed(responseID: "", tokenUsage: nil))
        ])
    }

    func testMergesToolCallsByIndexAndKeepsOriginalNameWhenEmptyDeltasArrive() {
        let events = collect([
            json(["choices": [[
                "delta": [
                    "tool_calls": [[
                        "index": 0,
                        "id": "call_a",
                        "function": ["name": "do_a", "arguments": "{ \"foo\":"]
                    ]]
                ]
            ]]]),
            json(["choices": [[
                "delta": [
                    "tool_calls": [[
                        "index": 0,
                        "function": ["name": "", "arguments": "1}"]
                    ]]
                ]
            ]]]),
            json(["choices": [["finish_reason": "tool_calls"]]])
        ])

        XCTAssertEqual(events, [
            .success(.outputItemDone(.functionCall(name: "do_a", arguments: "{ \"foo\":1}", callID: "call_a"))),
            .success(.completed(responseID: "", tokenUsage: nil))
        ])
    }

    func testEmitsContentReasoningToolCallsAndFlushesAssistantAtEOF() {
        let events = collect([
            json(["choices": [[
                "delta": [
                    "content": [["text": "hi"]],
                    "reasoning": "because",
                    "tool_calls": [[
                        "id": "call_a",
                        "function": ["name": "do_a", "arguments": "{}"]
                    ]]
                ]
            ]]]),
            json(["choices": [["finish_reason": "tool_calls"]]])
        ])

        XCTAssertEqual(events, [
            .success(.outputItemAdded(.reasoning(id: "", summary: [], content: [], encryptedContent: nil))),
            .success(.reasoningContentDelta(delta: "because", contentIndex: 0)),
            .success(.outputItemAdded(.message(role: "assistant", content: []))),
            .success(.outputTextDelta("hi")),
            .success(.outputItemDone(.reasoning(
                id: "",
                summary: [],
                content: [.reasoningText(text: "because")],
                encryptedContent: nil
            ))),
            .success(.outputItemDone(.functionCall(name: "do_a", arguments: "{}", callID: "call_a"))),
            .success(.outputItemDone(.message(role: "assistant", content: [.outputText(text: "hi")]))),
            .success(.completed(responseID: "", tokenUsage: nil))
        ])
    }

    func testStopDropsPartialToolCallsAndCompletesImmediately() {
        let events = collect([
            json(["choices": [[
                "delta": [
                    "tool_calls": [[
                        "id": "call_a",
                        "function": ["name": "do_a", "arguments": "{}"]
                    ]]
                ]
            ]]]),
            json(["choices": [["finish_reason": "stop"]]])
        ])

        XCTAssertEqual(events, [
            .success(.completed(responseID: "", tokenUsage: nil))
        ])
    }

    func testLengthFinishReasonReturnsContextWindowErrorAndTerminates() {
        let events = collect([
            json(["choices": [["finish_reason": "length"]]]),
            json(["choices": [["delta": ["content": "ignored"]]]])
        ])

        XCTAssertEqual(events, [
            .failure(.contextWindowExceeded)
        ])
    }

    func testContentAndReasoningVariants() {
        let events = collect([
            json(["choices": [[
                "delta": [
                    "content": "hello ",
                    "reasoning": ["text": "think"]
                ],
                "message": [
                    "reasoning": ["content": " more"]
                ],
                "finish_reason": "stop"
            ]]])
        ])

        XCTAssertEqual(events, [
            .success(.outputItemAdded(.reasoning(id: "", summary: [], content: [], encryptedContent: nil))),
            .success(.reasoningContentDelta(delta: "think", contentIndex: 0)),
            .success(.outputItemAdded(.message(role: "assistant", content: []))),
            .success(.outputTextDelta("hello ")),
            .success(.reasoningContentDelta(delta: " more", contentIndex: 1)),
            .success(.outputItemDone(.reasoning(
                id: "",
                summary: [],
                content: [.reasoningText(text: "think"), .reasoningText(text: " more")],
                encryptedContent: nil
            ))),
            .success(.outputItemDone(.message(role: "assistant", content: [.outputText(text: "hello ")]))),
            .success(.completed(responseID: "", tokenUsage: nil))
        ])
    }

    private func collect(_ payloads: [String]) -> [Result<ResponseEvent, APIError>] {
        ChatSSEParser.collectEvents(fromSSEText: payloads.map { payload in
            "event: message\ndata: \(payload)\n\n"
        }.joined())
    }

    private func json(_ object: Any) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }
}
