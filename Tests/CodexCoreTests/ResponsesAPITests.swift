import CodexCore
import XCTest

final class ResponsesAPITests: XCTestCase {
    func testCreateTextParamReturnsNilWhenNoControls() {
        XCTAssertNil(ResponsesAPITextControls.createForRequest(verbosity: nil, outputSchema: nil))
    }

    func testCreateTextParamBuildsVerbosityAndSchemaFormat() throws {
        let schema = JSONValue.object([
            "type": .string("object"),
            "properties": .object([
                "answer": .object(["type": .string("string")])
            ])
        ])

        let text = try XCTUnwrap(ResponsesAPITextControls.createForRequest(
            verbosity: .high,
            outputSchema: schema
        ))
        let object = try JSONObject(text)

        XCTAssertEqual(object["verbosity"] as? String, "high")
        let format = try XCTUnwrap(object["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertEqual(format["strict"] as? Bool, true)
        XCTAssertEqual(format["name"] as? String, "codex_output_schema")
        XCTAssertNotNil(format["schema"] as? [String: Any])
    }

    func testResponsesAPIRequestWireShapeSkipsNilOptionals() throws {
        let request = ResponsesAPIRequest(
            model: "gpt-test",
            instructions: "inst",
            input: [.message(role: "user", content: [.inputText(text: "hi")])],
            tools: [.object(["type": .string("web_search_preview")])],
            parallelToolCalls: true,
            reasoning: ResponsesAPIReasoning(effort: .medium, summary: .auto),
            store: false,
            include: ["reasoning.encrypted_content"],
            promptCacheKey: nil,
            text: nil
        )

        let object = try JSONObject(request)
        XCTAssertEqual(object["model"] as? String, "gpt-test")
        XCTAssertEqual(object["instructions"] as? String, "inst")
        XCTAssertEqual(object["tool_choice"] as? String, "auto")
        XCTAssertEqual(object["parallel_tool_calls"] as? Bool, true)
        XCTAssertEqual(object["store"] as? Bool, false)
        XCTAssertEqual(object["stream"] as? Bool, true)
        XCTAssertNil(object["service_tier"])
        XCTAssertNil(object["prompt_cache_key"])
        XCTAssertNil(object["text"])

        let reasoning = try XCTUnwrap(object["reasoning"] as? [String: Any])
        XCTAssertEqual(reasoning["effort"] as? String, "medium")
        XCTAssertEqual(reasoning["summary"] as? String, "auto")
    }

    func testResponsesAPIRequestSerializesServiceTierWhenSet() throws {
        let request = ResponsesAPIRequest(
            model: "gpt-test",
            instructions: "inst",
            input: [],
            store: false,
            serviceTier: "flex"
        )

        let object = try JSONObject(request)
        XCTAssertEqual(object["service_tier"] as? String, "flex")
    }

    func testBuilderCanFilterUnsupportedServiceTierWithModelInfo() throws {
        let provider = apiProvider(name: "openai", baseURL: "https://api.openai.com/v1")
        let modelInfo = ModelInfo(
            slug: "gpt-test",
            displayName: "GPT Test",
            defaultReasoningLevel: .medium,
            supportedReasoningLevels: [],
            shellType: .default,
            visibility: .list,
            supportedInAPI: true,
            priority: 1,
            serviceTiers: [
                ModelServiceTier(id: "flex", name: "Flex", description: "Flexible processing.")
            ],
            supportsReasoningSummaries: false,
            supportVerbosity: false,
            truncationPolicy: .bytes(4096),
            supportsParallelToolCalls: false,
            experimentalSupportedTools: []
        )

        let supported = try ResponsesRequestBuilder(model: "gpt-test", instructions: "inst", input: [])
            .serviceTier("flex", modelInfo: modelInfo)
            .build(provider: provider)
        XCTAssertEqual(try JSONObject(supported.body)["service_tier"] as? String, "flex")

        let unsupported = try ResponsesRequestBuilder(model: "gpt-test", instructions: "inst", input: [])
            .serviceTier("priority", modelInfo: modelInfo)
            .build(provider: provider)
        XCTAssertNil(try JSONObject(unsupported.body)["service_tier"])
    }

    func testBuilderUsesAzureStoreDefaultAndConversationHeaders() throws {
        let provider = apiProvider(name: "azure", baseURL: "https://example.openai.azure.com/v1")
        let input: [ResponseItem] = [
            .message(id: "m1", role: "assistant", content: []),
            .message(id: nil, role: "assistant", content: [])
        ]

        let request = try ResponsesRequestBuilder(model: "gpt-test", instructions: "inst", input: input)
            .conversation("conv-1")
            .sessionSource(.subagent(.review))
            .build(provider: provider)

        let body = try JSONObject(request.body)
        XCTAssertEqual(body["store"] as? Bool, true)

        let items = try XCTUnwrap(body["input"] as? [[String: Any]])
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0]["id"] as? String, "m1")
        XCTAssertNil(items[1]["id"])

        XCTAssertEqual(request.headers["conversation_id"], "conv-1")
        XCTAssertEqual(request.headers["session_id"], "conv-1")
        XCTAssertEqual(request.headers["x-openai-subagent"], "review")
    }

    func testBuilderHonorsStoreOverrideAndExtraHeaders() throws {
        let provider = apiProvider(name: "openai", baseURL: "https://api.openai.com/v1")

        let request = try ResponsesRequestBuilder(
            model: "gpt-test",
            instructions: "inst",
            input: [.message(id: "m1", role: "assistant", content: [])]
        )
        .storeOverride(true)
        .extraHeaders(["x-extra": "1"])
        .build(provider: provider)

        let body = try JSONObject(request.body)
        let items = try XCTUnwrap(body["input"] as? [[String: Any]])
        XCTAssertEqual(body["store"] as? Bool, true)
        XCTAssertEqual(items[0]["id"] as? String, "m1")
        XCTAssertEqual(request.headers["x-extra"], "1")
        XCTAssertNil(request.headers["conversation_id"])
    }

    private func apiProvider(name: String, baseURL: String) -> APIProvider {
        APIProvider(
            name: name,
            baseURL: baseURL,
            wireAPI: .responses,
            retry: ProviderRetryConfig(
                maxAttempts: 1,
                baseDelayMilliseconds: 50,
                retry429: false,
                retry5xx: true,
                retryTransport: true
            ),
            streamIdleTimeoutMilliseconds: 5_000
        )
    }
}
