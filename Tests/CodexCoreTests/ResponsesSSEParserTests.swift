import CodexCore
import XCTest

final class ResponsesSSEParserTests: XCTestCase {
    func testParsesItemsAndCompletedOnStreamClose() {
        let text = sse([
            #"{"type":"response.output_item.done","item":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Hello"}]}}"#,
            #"{"type":"response.output_item.done","item":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"World"}]}}"#,
            #"{"type":"response.completed","response":{"id":"resp1"}}"#
        ])

        let events = ResponsesSSEParser.collectEvents(fromSSEText: text)

        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0], .success(.outputItemDone(.message(role: "assistant", content: [
            .outputText(text: "Hello")
        ]))))
        XCTAssertEqual(events[1], .success(.outputItemDone(.message(role: "assistant", content: [
            .outputText(text: "World")
        ]))))
        XCTAssertEqual(events[2], .success(.completed(responseID: "resp1", tokenUsage: nil)))
    }

    func testCompletedUsageMapsTokenDetails() {
        let text = sse([
            #"{"type":"response.completed","response":{"id":"resp_usage","usage":{"input_tokens":10,"input_tokens_details":{"cached_tokens":4},"output_tokens":8,"output_tokens_details":{"reasoning_tokens":3},"total_tokens":18}}}"#
        ])

        let events = ResponsesSSEParser.collectEvents(fromSSEText: text)

        XCTAssertEqual(events, [
            .success(.completed(
                responseID: "resp_usage",
                tokenUsage: TokenUsage(
                    inputTokens: 10,
                    cachedInputTokens: 4,
                    outputTokens: 8,
                    reasoningOutputTokens: 3,
                    totalTokens: 18
                )
            ))
        ])
    }

    func testCompletedEndTurnMapsRustOptionalBool() {
        let falseEvents = ResponsesSSEParser.collectEvents(fromSSEText: sse([
            #"{"type":"response.completed","response":{"id":"resp_end_false","end_turn":false}}"#
        ]))
        let trueEvents = ResponsesSSEParser.collectEvents(fromSSEText: sse([
            #"{"type":"response.completed","response":{"id":"resp_end_true","end_turn":true}}"#
        ]))
        let nullEvents = ResponsesSSEParser.collectEvents(fromSSEText: sse([
            #"{"type":"response.completed","response":{"id":"resp_end_null","end_turn":null}}"#
        ]))
        let omittedEvents = ResponsesSSEParser.collectEvents(fromSSEText: sse([
            #"{"type":"response.completed","response":{"id":"resp_end_omitted"}}"#
        ]))

        XCTAssertEqual(falseEvents, [
            .success(.completed(responseID: "resp_end_false", tokenUsage: nil, endTurn: false))
        ])
        XCTAssertEqual(trueEvents, [
            .success(.completed(responseID: "resp_end_true", tokenUsage: nil, endTurn: true))
        ])
        XCTAssertEqual(nullEvents, [
            .success(.completed(responseID: "resp_end_null", tokenUsage: nil, endTurn: nil))
        ])
        XCTAssertEqual(omittedEvents, [
            .success(.completed(responseID: "resp_end_omitted", tokenUsage: nil, endTurn: nil))
        ])
    }

    func testMetadataEventEmitsDedupedModelVerificationsLikeRust() {
        let text = sse([
            #"{"type":"response.metadata","metadata":{"openai_verification_recommendation":["trusted_access_for_cyber","unknown","trusted_access_for_cyber"]}}"#,
            #"{"type":"response.completed","response":{"id":"resp_verify"}}"#
        ])

        let events = ResponsesSSEParser.collectEvents(fromSSEText: text)

        XCTAssertEqual(events, [
            .success(.modelVerifications([.trustedAccessForCyber])),
            .success(.completed(responseID: "resp_verify", tokenUsage: nil))
        ])
    }

    func testCustomToolInputDeltaUsesItemIDAndCallIDLikeRust() {
        let text = sse([
            #"{"type":"response.custom_tool_call_input.delta","item_id":"item-1","call_id":"call-1","delta":"{\"cmd\""}"#,
            #"{"type":"response.completed","response":{"id":"resp_tool_delta"}}"#
        ])

        let events = ResponsesSSEParser.collectEvents(fromSSEText: text)

        XCTAssertEqual(events, [
            .success(.toolCallInputDelta(itemID: "item-1", callID: "call-1", delta: #"{"cmd""#)),
            .success(.completed(responseID: "resp_tool_delta", tokenUsage: nil))
        ])
    }

    func testCustomToolInputDeltaFallsBackToCallIDLikeRust() {
        let text = sse([
            #"{"type":"response.custom_tool_call_input.delta","call_id":"call-only","delta":":\"echo\"}"}"#,
            #"{"type":"response.completed","response":{"id":"resp_tool_delta_fallback"}}"#
        ])

        let events = ResponsesSSEParser.collectEvents(fromSSEText: text)

        XCTAssertEqual(events, [
            .success(.toolCallInputDelta(itemID: "call-only", callID: "call-only", delta: #":"echo"}"#)),
            .success(.completed(responseID: "resp_tool_delta_fallback", tokenUsage: nil))
        ])
    }

    func testCustomToolInputDeltaWithoutIDOrDeltaIsIgnoredLikeRust() {
        let text = sse([
            #"{"type":"response.custom_tool_call_input.delta","delta":"ignored"}"#,
            #"{"type":"response.custom_tool_call_input.delta","item_id":"item-ignored"}"#,
            #"{"type":"response.completed","response":{"id":"resp_tool_delta_ignored"}}"#
        ])

        let events = ResponsesSSEParser.collectEvents(fromSSEText: text)

        XCTAssertEqual(events, [
            .success(.completed(responseID: "resp_tool_delta_ignored", tokenUsage: nil))
        ])
    }

    func testMissingCompletedReturnsStreamErrorAfterPriorEvents() {
        let text = sse([
            #"{"type":"response.output_item.done","item":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Hello"}]}}"#
        ])

        let events = ResponsesSSEParser.collectEvents(fromSSEText: text)

        XCTAssertEqual(events, [
            .success(.outputItemDone(.message(role: "assistant", content: [.outputText(text: "Hello")]))),
            .failure(.stream("stream closed before response.completed"))
        ])
    }

    func testIncompleteResponseReturnsRustStreamErrorOnClose() {
        let text = sse([
            #"{"type":"response.incomplete","response":{"incomplete_details":{"reason":"max_output_tokens"}}}"#
        ])

        let events = ResponsesSSEParser.collectEvents(fromSSEText: text)

        XCTAssertEqual(events, [
            .failure(.stream("Incomplete response returned, reason: max_output_tokens"))
        ])
    }

    func testIncompleteResponseDefaultsUnknownReasonLikeRust() {
        let text = sse([
            #"{"type":"response.incomplete","response":{}}"#
        ])

        let events = ResponsesSSEParser.collectEvents(fromSSEText: text)

        XCTAssertEqual(events, [
            .failure(.stream("Incomplete response returned, reason: unknown"))
        ])
    }

    func testFailedRateLimitBecomesRetryableOnStreamClose() {
        let message = "Rate limit reached for gpt-5.1. Please try again in 11.054s."
        let text = sse([
            #"{"type":"response.failed","response":{"error":{"code":"rate_limit_exceeded","message":"\#(message)"}}}"#
        ])

        let events = ResponsesSSEParser.collectEvents(fromSSEText: text)

        XCTAssertEqual(events, [
            .failure(.retryable(message: message, delay: .milliseconds(11_054)))
        ])
    }

    func testFailedFatalErrorCodesMatchRustMapping() {
        XCTAssertEqual(failure(forCode: "context_length_exceeded"), .contextWindowExceeded)
        XCTAssertEqual(failure(forCode: "insufficient_quota"), .quotaExceeded)
        XCTAssertEqual(failure(forCode: "usage_not_included"), .usageNotIncluded)
        XCTAssertEqual(failure(forCode: "server_is_overloaded"), .serverOverloaded)
        XCTAssertEqual(failure(forCode: "slow_down"), .serverOverloaded)
        XCTAssertEqual(failure(forCode: "invalid_prompt"), .invalidRequest(message: "boom"))
        XCTAssertEqual(failure(forCode: "cyber_policy"), .cyberPolicy(message: "boom"))
    }

    func testFailedCyberPolicyUsesRustFallbackForEmptyMessage() {
        let events = ResponsesSSEParser.collectEvents(fromSSEText: sse([
            #"{"type":"response.failed","response":{"error":{"code":"cyber_policy","message":"   "}}}"#
        ]))

        XCTAssertEqual(events, [
            .failure(.cyberPolicy(message: "This request has been flagged for possible cybersecurity risk."))
        ])
    }

    func testFailedInvalidPromptUsesRustFallbackForMissingMessage() {
        let events = ResponsesSSEParser.collectEvents(fromSSEText: sse([
            #"{"type":"response.failed","response":{"error":{"code":"invalid_prompt"}}}"#
        ]))

        XCTAssertEqual(events, [
            .failure(.invalidRequest(message: "Invalid request."))
        ])
    }

    func testParsesRetryAfterMillisecondsAndAzureSeconds() {
        XCTAssertEqual(
            retryDelay(fromMessage: "Rate limited. Please try again in 28ms."),
            .retryable(message: "Rate limited. Please try again in 28ms.", delay: .milliseconds(28))
        )
        XCTAssertEqual(
            retryDelay(fromMessage: "Rate limit exceeded. Try again in 35 seconds."),
            .retryable(message: "Rate limit exceeded. Try again in 35 seconds.", delay: .milliseconds(35_000))
        )
    }

    func testTableDrivenEventKinds() {
        let completed = #"{"type":"response.completed","response":{"id":"c","usage":{"input_tokens":0,"input_tokens_details":null,"output_tokens":0,"output_tokens_details":null,"total_tokens":0},"output":[]}}"#
        let cases: [(String, String, ResponseEvent?, Int)] = [
            ("created", #"{"type":"response.created","response":{}}"#, .created, 2),
            (
                "output_item.done",
                #"{"type":"response.output_item.done","item":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"hi"}]}}"#,
                .outputItemDone(.message(role: "assistant", content: [.outputText(text: "hi")])),
                2
            ),
            ("output_text.delta", #"{"type":"response.output_text.delta","delta":"abc"}"#, .outputTextDelta("abc"), 2),
            (
                "custom_tool_call_input.delta",
                #"{"type":"response.custom_tool_call_input.delta","item_id":"item-table","call_id":"call-table","delta":"abc"}"#,
                .toolCallInputDelta(itemID: "item-table", callID: "call-table", delta: "abc"),
                2
            ),
            (
                "reasoning_summary_text.delta",
                #"{"type":"response.reasoning_summary_text.delta","delta":"sum","summary_index":2}"#,
                .reasoningSummaryDelta(delta: "sum", summaryIndex: 2),
                2
            ),
            (
                "reasoning_text.delta",
                #"{"type":"response.reasoning_text.delta","delta":"raw","content_index":3}"#,
                .reasoningContentDelta(delta: "raw", contentIndex: 3),
                2
            ),
            (
                "output_item.added",
                #"{"type":"response.output_item.added","item":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"draft"}]}}"#,
                .outputItemAdded(.message(role: "assistant", content: [.outputText(text: "draft")])),
                2
            ),
            (
                "reasoning_summary_part.added",
                #"{"type":"response.reasoning_summary_part.added","summary_index":4}"#,
                .reasoningSummaryPartAdded(summaryIndex: 4),
                2
            ),
            ("unknown", #"{"type":"response.new_tool_event"}"#, nil, 1)
        ]

        for (name, eventJSON, expectedFirst, expectedCount) in cases {
            let events = ResponsesSSEParser.collectEvents(fromSSEText: sse([eventJSON, completed]))
            XCTAssertEqual(events.count, expectedCount, name)
            if let expectedFirst {
                XCTAssertEqual(events.first, .success(expectedFirst), name)
            } else {
                XCTAssertEqual(events.first, .success(.completed(
                    responseID: "c",
                    tokenUsage: TokenUsage()
                )), name)
            }
        }
    }

    func testIgnoresMalformedJSONAndMalformedItems() {
        let text = """
        event: response.output_text.delta
        data: not-json

        event: response.output_item.done
        data: {"type":"response.output_item.done","item":{"type":"message"}}

        event: response.completed
        data: {"type":"response.completed","response":{"id":"ok"}}

        """

        XCTAssertEqual(
            ResponsesSSEParser.collectEvents(fromSSEText: text),
            [.success(.completed(responseID: "ok", tokenUsage: nil))]
        )
    }

    func testDataFramesJoinMultilineDataAndStripOneLeadingSpace() {
        let text = """
        event: response.output_text.delta
        data: {"type":"response.output_text.delta",
        data: "delta":"hi"}

        """

        XCTAssertEqual(
            ResponsesSSEParser.dataFrames(fromSSEText: text),
            [#"{"type":"response.output_text.delta","# + "\n" + #""delta":"hi"}"#]
        )
    }

    private func failure(forCode code: String) -> APIError {
        let events = ResponsesSSEParser.collectEvents(fromSSEText: sse([
            #"{"type":"response.failed","response":{"error":{"code":"\#(code)","message":"boom"}}}"#
        ]))
        guard case let .failure(error) = events.first else {
            return .stream("missing error")
        }
        return error
    }

    private func retryDelay(fromMessage message: String) -> APIError {
        let events = ResponsesSSEParser.collectEvents(fromSSEText: sse([
            #"{"type":"response.failed","response":{"error":{"code":"rate_limit_exceeded","message":"\#(message)"}}}"#
        ]))
        guard case let .failure(error) = events.first else {
            return .stream("missing error")
        }
        return error
    }

    private func sse(_ events: [String]) -> String {
        events.map { event in
            let type = eventType(from: event)
            return "event: \(type)\ndata: \(event)\n\n"
        }.joined()
    }

    private func eventType(from event: String) -> String {
        let data = Data(event.utf8)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String
        else {
            return "message"
        }
        return type
    }
}
