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
            .success(.completed(responseID: "resp_1", tokenUsage: TokenUsage(totalTokens: 12)))
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
            .success(.completed(responseID: "resp_1", tokenUsage: TokenUsage(totalTokens: 12)))
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
}
