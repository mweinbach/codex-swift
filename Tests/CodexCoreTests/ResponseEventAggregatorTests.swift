import CodexCore
import XCTest

final class ResponseEventAggregatorTests: XCTestCase {
    func testAggregatedOnlyModeBuildsFinalAssistantAndReasoningItems() {
        let rateLimits = RateLimitSnapshot(
            primary: RateLimitWindow(usedPercent: 1, windowMinutes: 60, resetsAt: nil),
            secondary: nil,
            credits: nil,
            planType: nil
        )
        let events: [Result<ResponseEvent, APIError>] = [
            .success(.created),
            .success(.rateLimits(rateLimits)),
            .success(.outputItemAdded(.message(role: "assistant", content: []))),
            .success(.outputTextDelta("hel")),
            .success(.outputTextDelta("lo")),
            .success(.reasoningSummaryPartAdded(summaryIndex: 0)),
            .success(.reasoningSummaryDelta(delta: "summary", summaryIndex: 0)),
            .success(.reasoningContentDelta(delta: "bec", contentIndex: 0)),
            .success(.reasoningContentDelta(delta: "ause", contentIndex: 1)),
            .success(.outputItemDone(.message(role: "assistant", content: [.outputText(text: "ignored final")]))),
            .success(.completed(responseID: "resp_1", tokenUsage: TokenUsage(totalTokens: 12), endTurn: false))
        ]

        XCTAssertEqual(ResponseEventAggregator.aggregate(events), [
            .success(.rateLimits(rateLimits)),
            .success(.outputItemAdded(.message(role: "assistant", content: []))),
            .success(.outputItemDone(.reasoning(
                id: "",
                summary: [],
                content: [.reasoningText(text: "because")],
                encryptedContent: nil
            ))),
            .success(.outputItemDone(.message(role: "assistant", content: [.outputText(text: "hello")]))),
            .success(.completed(responseID: "resp_1", tokenUsage: TokenUsage(totalTokens: 12), endTurn: false))
        ])
    }

    func testAggregatedOnlyModeSeedsTextFromAssistantDoneWhenNoDeltasArrive() {
        let events: [Result<ResponseEvent, APIError>] = [
            .success(.outputItemDone(.message(role: "assistant", content: [
                .outputText(text: "done")
            ]))),
            .success(.completed(responseID: "", tokenUsage: nil))
        ]

        XCTAssertEqual(ResponseEventAggregator.aggregate(events), [
            .success(.outputItemDone(.message(role: "assistant", content: [
                .outputText(text: "done")
            ]))),
            .success(.completed(responseID: "", tokenUsage: nil))
        ])
    }

    func testStreamingModeForwardsDeltasAndEmitsAggregatedItemsBeforeCompletion() {
        let events: [Result<ResponseEvent, APIError>] = [
            .success(.outputTextDelta("a")),
            .success(.outputTextDelta("b")),
            .success(.reasoningContentDelta(delta: "r", contentIndex: 0)),
            .success(.outputItemDone(.message(role: "assistant", content: [.outputText(text: "ignored final")]))),
            .success(.completed(responseID: "resp_stream", tokenUsage: nil))
        ]

        XCTAssertEqual(ResponseEventAggregator.aggregate(events, mode: .streaming), [
            .success(.outputTextDelta("a")),
            .success(.outputTextDelta("b")),
            .success(.reasoningContentDelta(delta: "r", contentIndex: 0)),
            .success(.outputItemDone(.reasoning(
                id: "",
                summary: [],
                content: [.reasoningText(text: "r")],
                encryptedContent: nil
            ))),
            .success(.outputItemDone(.message(role: "assistant", content: [.outputText(text: "ab")]))),
            .success(.completed(responseID: "resp_stream", tokenUsage: nil))
        ])
    }

    func testStreamingModeForwardsAssistantDoneWhenNoDeltasArrive() {
        let events: [Result<ResponseEvent, APIError>] = [
            .success(.outputItemDone(.message(role: "assistant", content: [
                .outputText(text: "direct")
            ]))),
            .success(.completed(responseID: "resp", tokenUsage: nil))
        ]

        XCTAssertEqual(ResponseEventAggregator.aggregate(events, mode: .streaming), [
            .success(.outputItemDone(.message(role: "assistant", content: [
                .outputText(text: "direct")
            ]))),
            .success(.completed(responseID: "resp", tokenUsage: nil))
        ])
    }

    func testForwardsErrorsAndNonAssistantDoneItems() {
        let events: [Result<ResponseEvent, APIError>] = [
            .success(.outputItemDone(.functionCall(name: "run", arguments: "{}", callID: "call_1"))),
            .failure(.contextWindowExceeded),
            .success(.completed(responseID: "resp", tokenUsage: nil))
        ]

        XCTAssertEqual(ResponseEventAggregator.aggregate(events), [
            .success(.outputItemDone(.functionCall(name: "run", arguments: "{}", callID: "call_1"))),
            .failure(.contextWindowExceeded),
            .success(.completed(responseID: "resp", tokenUsage: nil))
        ])
    }

    func testForwardsRustServerMetadataEvents() {
        let events: [Result<ResponseEvent, APIError>] = [
            .success(.serverModel("gpt-rerouted")),
            .success(.modelVerifications([.trustedAccessForCyber])),
            .success(.serverReasoningIncluded(true)),
            .success(.modelsETag("etag-1")),
            .success(.toolCallInputDelta(itemID: "item-1", callID: "call-1", delta: "abc"))
        ]

        XCTAssertEqual(ResponseEventAggregator.aggregate(events), events)
    }

    func testAggregatesAsyncEventStream() async {
        let stream = responseEventStream([
            .success(.outputTextDelta("hel")),
            .success(.outputTextDelta("lo")),
            .success(.completed(responseID: "resp_stream", tokenUsage: nil))
        ])

        let events = await collect(ResponseEventAggregator.aggregate(stream, mode: .streaming))

        XCTAssertEqual(events, [
            .success(.outputTextDelta("hel")),
            .success(.outputTextDelta("lo")),
            .success(.outputItemDone(.message(role: "assistant", content: [.outputText(text: "hello")]))),
            .success(.completed(responseID: "resp_stream", tokenUsage: nil))
        ])
    }
}

private func responseEventStream(_ events: ResponseEventResults) -> ResponseEventStream {
    ResponseEventStream { continuation in
        for event in events {
            continuation.yield(event)
        }
        continuation.finish()
    }
}

private func collect(_ stream: ResponseEventStream) async -> ResponseEventResults {
    var events: ResponseEventResults = []
    for await event in stream {
        events.append(event)
    }
    return events
}
