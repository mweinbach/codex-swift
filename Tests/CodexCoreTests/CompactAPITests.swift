import CodexCore
import XCTest

final class CompactAPITests: XCTestCase {
    func testCompactionInputWireShape() throws {
        let input = CompactionInput(
            model: "gpt-test",
            input: [
                .message(role: "user", content: [.inputText(text: "hello")])
            ],
            instructions: "summarize"
        )

        let object = try JSONObject(input)
        XCTAssertEqual(object["model"] as? String, "gpt-test")
        XCTAssertEqual(object["instructions"] as? String, "summarize")
        XCTAssertEqual((object["tools"] as? [Any])?.count, 0)
        XCTAssertEqual(object["parallel_tool_calls"] as? Bool, false)
        XCTAssertNil(object["reasoning"])
        XCTAssertNil(object["service_tier"])
        XCTAssertNil(object["prompt_cache_key"])
        XCTAssertNil(object["text"])

        let items = try XCTUnwrap(object["input"] as? [[String: Any]])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0]["type"] as? String, "message")
        XCTAssertEqual(items[0]["role"] as? String, "user")
    }

    func testCompactPathAcceptsResponsesAndCompactWireAPIs() throws {
        XCTAssertEqual(
            try CompactAPI.path(for: provider(wireAPI: .responses)),
            "responses/compact"
        )
        XCTAssertEqual(
            try CompactAPI.path(for: provider(wireAPI: .compact)),
            "responses/compact"
        )
    }

    func testCompactPathRejectsChatWireAPIWithRustMessage() {
        XCTAssertThrowsError(try CompactAPI.path(for: provider(wireAPI: .chat))) { error in
            XCTAssertEqual(
                (error as? CompactAPIError)?.description,
                "compact endpoint requires responses wire api"
            )
        }
    }

    func testCompactionInputBodyMatchesJSONEncoding() throws {
        let body = try CompactAPI.body(for: CompactionInput(
            model: "gpt-test",
            input: [],
            instructions: "inst"
        ))

        XCTAssertEqual(body, .object([
            "model": .string("gpt-test"),
            "input": .array([]),
            "instructions": .string("inst"),
            "tools": .array([]),
            "parallel_tool_calls": .bool(false)
        ]))
    }

    func testCompactionInputOmissionRulesMatchRust() throws {
        let body = try CompactAPI.body(for: CompactionInput(
            model: "gpt-test",
            input: [],
            instructions: "",
            tools: [.object(["type": .string("function"), "name": .string("noop")])],
            parallelToolCalls: true,
            reasoning: ResponsesAPIReasoning(effort: .medium, summary: ReasoningSummary.none),
            serviceTier: nil,
            promptCacheKey: "cache-key",
            text: ResponsesAPITextControls(verbosity: .low)
        ))

        XCTAssertEqual(body, .object([
            "model": .string("gpt-test"),
            "input": .array([]),
            "tools": .array([
                .object(["type": .string("function"), "name": .string("noop")])
            ]),
            "parallel_tool_calls": .bool(true),
            "reasoning": .object([
                "effort": .string("medium"),
                "summary": .string("none")
            ]),
            "prompt_cache_key": .string("cache-key"),
            "text": .object([
                "verbosity": .string("low")
            ])
        ]))
    }

    func testCompactHistoryResponseDecodesOutputItems() throws {
        let data = Data(#"""
        {
          "output": [
            {
              "type": "message",
              "role": "assistant",
              "content": [{"type": "output_text", "text": "summary"}]
            }
          ]
        }
        """#.utf8)

        let response = try JSONDecoder().decode(CompactHistoryResponse.self, from: data)
        XCTAssertEqual(response.output, [
            .message(role: "assistant", content: [.outputText(text: "summary")])
        ])
    }

    private func provider(wireAPI: WireAPI) -> APIProvider {
        APIProvider(
            name: "test",
            baseURL: "https://example.com/v1",
            wireAPI: wireAPI,
            retry: ProviderRetryConfig(
                maxAttempts: 1,
                baseDelayMilliseconds: 1,
                retry429: false,
                retry5xx: true,
                retryTransport: true
            ),
            streamIdleTimeoutMilliseconds: 1_000
        )
    }
}
