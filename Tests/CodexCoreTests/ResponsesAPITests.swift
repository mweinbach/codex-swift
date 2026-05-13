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

    func testResponsesAPIRequestSerializesClientMetadataWhenSet() throws {
        let request = ResponsesAPIRequest(
            model: "gpt-test",
            instructions: "inst",
            input: [],
            store: false,
            clientMetadata: [
                "fiber_run_id": "fiber-123",
                CodexRequestHeaders.turnMetadataHeaderName: #"{"turn_id":"turn-123"}"#
            ]
        )

        let object = try JSONObject(request)
        let metadata = try XCTUnwrap(object["client_metadata"] as? [String: String])
        XCTAssertEqual(metadata["fiber_run_id"], "fiber-123")
        XCTAssertEqual(metadata[CodexRequestHeaders.turnMetadataHeaderName], #"{"turn_id":"turn-123"}"#)
    }

    func testResponseCreateWebSocketRequestMatchesRustWireShape() throws {
        let request = ResponsesWebSocketRequest.responseCreate(ResponseCreateWebSocketRequest(
            model: "gpt-test",
            instructions: "inst",
            previousResponseID: "resp-prev",
            input: [.message(role: "user", content: [.inputText(text: "hi")])],
            tools: [.object(["type": .string("web_search_preview")])],
            parallelToolCalls: true,
            reasoning: ResponsesAPIReasoning(effort: .medium, summary: .auto),
            store: false,
            include: ["reasoning.encrypted_content"],
            serviceTier: "flex",
            promptCacheKey: "cache-key",
            text: ResponsesAPITextControls(verbosity: .high),
            generate: true,
            clientMetadata: ["traceparent": "00-abc"]
        ))

        let object = try JSONObject(request)
        XCTAssertEqual(object["type"] as? String, "response.create")
        XCTAssertEqual(object["model"] as? String, "gpt-test")
        XCTAssertEqual(object["instructions"] as? String, "inst")
        XCTAssertEqual(object["previous_response_id"] as? String, "resp-prev")
        XCTAssertEqual(object["tool_choice"] as? String, "auto")
        XCTAssertEqual(object["parallel_tool_calls"] as? Bool, true)
        XCTAssertEqual(object["store"] as? Bool, false)
        XCTAssertEqual(object["stream"] as? Bool, true)
        XCTAssertEqual(object["include"] as? [String], ["reasoning.encrypted_content"])
        XCTAssertEqual(object["service_tier"] as? String, "flex")
        XCTAssertEqual(object["prompt_cache_key"] as? String, "cache-key")
        XCTAssertEqual(object["generate"] as? Bool, true)
        XCTAssertEqual((object["input"] as? [[String: Any]])?.first?["type"] as? String, "message")
        XCTAssertEqual((object["tools"] as? [[String: Any]])?.first?["type"] as? String, "web_search_preview")
        XCTAssertEqual((object["reasoning"] as? [String: Any])?["effort"] as? String, "medium")
        XCTAssertEqual((object["text"] as? [String: Any])?["verbosity"] as? String, "high")
        XCTAssertEqual((object["client_metadata"] as? [String: String])?["traceparent"], "00-abc")
    }

    func testResponseCreateWebSocketRequestSkipsEmptyAndNilFieldsLikeRust() throws {
        let request = ResponsesWebSocketRequest.responseCreate(ResponseCreateWebSocketRequest(
            model: "gpt-test",
            instructions: "",
            input: [],
            tools: [],
            store: true
        ))

        let object = try JSONObject(request)
        XCTAssertEqual(object["type"] as? String, "response.create")
        XCTAssertNil(object["instructions"])
        XCTAssertNil(object["previous_response_id"])
        XCTAssertNil(object["service_tier"])
        XCTAssertNil(object["prompt_cache_key"])
        XCTAssertNil(object["text"])
        XCTAssertNil(object["generate"])
        XCTAssertNil(object["client_metadata"])
    }

    func testResponseCreateWebSocketRequestCopiesResponsesAPIRequest() throws {
        let httpRequest = ResponsesAPIRequest(
            model: "gpt-test",
            instructions: "inst",
            input: [.message(role: "user", content: [.inputText(text: "hi")])],
            tools: [.object(["type": .string("function")])],
            parallelToolCalls: true,
            reasoning: ResponsesAPIReasoning(effort: .low, summary: .concise),
            store: true,
            include: ["reasoning.encrypted_content"],
            serviceTier: "priority",
            promptCacheKey: "prompt-cache",
            text: ResponsesAPITextControls(verbosity: .medium),
            clientMetadata: ["turn": "turn-1"]
        )

        let websocketRequest = ResponseCreateWebSocketRequest(
            httpRequest,
            previousResponseID: "resp-prev",
            generate: false
        )

        XCTAssertEqual(websocketRequest.model, httpRequest.model)
        XCTAssertEqual(websocketRequest.instructions, httpRequest.instructions)
        XCTAssertEqual(websocketRequest.previousResponseID, "resp-prev")
        XCTAssertEqual(websocketRequest.input, httpRequest.input)
        XCTAssertEqual(websocketRequest.tools, httpRequest.tools)
        XCTAssertEqual(websocketRequest.toolChoice, httpRequest.toolChoice)
        XCTAssertEqual(websocketRequest.parallelToolCalls, httpRequest.parallelToolCalls)
        XCTAssertEqual(websocketRequest.reasoning, httpRequest.reasoning)
        XCTAssertEqual(websocketRequest.store, httpRequest.store)
        XCTAssertEqual(websocketRequest.stream, httpRequest.stream)
        XCTAssertEqual(websocketRequest.include, httpRequest.include)
        XCTAssertEqual(websocketRequest.serviceTier, httpRequest.serviceTier)
        XCTAssertEqual(websocketRequest.promptCacheKey, httpRequest.promptCacheKey)
        XCTAssertEqual(websocketRequest.text, httpRequest.text)
        XCTAssertEqual(websocketRequest.generate, false)
        XCTAssertEqual(websocketRequest.clientMetadata, httpRequest.clientMetadata)
    }

    func testResponseProcessedWebSocketRequestMatchesRustWireShape() throws {
        let request = ResponsesWebSocketRequest.responseProcessed(
            ResponseProcessedWebSocketRequest(responseID: "resp-compact")
        )

        try XCTAssertJSONObjectEqual(request, [
            "type": "response.processed",
            "response_id": "resp-compact",
        ])
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
        XCTAssertEqual(request.headers["thread_id"], "conv-1")
        XCTAssertEqual(request.headers["thread-id"], "conv-1")
        XCTAssertEqual(request.headers["session_id"], "conv-1")
        XCTAssertEqual(request.headers["session-id"], "conv-1")
        XCTAssertEqual(request.headers["x-openai-subagent"], "review")
    }

    func testBuilderReattachesAzureStoredItemIDsForRustSkippedRuntimeVariants() throws {
        let provider = apiProvider(name: "azure", baseURL: "https://example.openai.azure.com/v1")
        let request = try ResponsesRequestBuilder(model: "gpt-test", instructions: "inst", input: [
            .message(id: "msg-1", role: "assistant", content: []),
            .reasoning(id: "rs-1", summary: []),
            .localShellCall(
                id: "shell-1",
                callID: "shell-call",
                status: .completed,
                action: .exec(LocalShellExecAction(command: ["echo", "hi"]))
            ),
            .functionCall(id: "fc-1", name: "run", arguments: "{}", callID: "call-1"),
            .toolSearchCall(
                id: "ts-1",
                callID: "search-1",
                status: "completed",
                execution: "client",
                arguments: .object(["query": .string("docs")])
            ),
            .customToolCall(id: "ct-1", status: "completed", callID: "custom-1", name: "patch", input: "{}"),
            .webSearchCall(id: "ws-1", status: "completed", action: .search(query: "weather")),
            .message(id: "", role: "assistant", content: []),
            .reasoning(id: "", summary: []),
            .functionCallOutput(callID: "call-1", output: FunctionCallOutputPayload(content: "done")),
            .imageGenerationCall(id: "ig-1", status: "completed", result: "base64")
        ])
        .build(provider: provider)

        let body = try JSONObject(request.body)
        let items = try XCTUnwrap(body["input"] as? [[String: Any]])
        XCTAssertEqual(items.map { $0["id"] as? String }, [
            "msg-1",
            "rs-1",
            "shell-1",
            "fc-1",
            "ts-1",
            "ct-1",
            "ws-1",
            nil,
            nil,
            nil,
            "ig-1"
        ])
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
        XCTAssertNil(items[0]["id"])
        XCTAssertEqual(request.headers["x-extra"], "1")
        XCTAssertNil(request.headers["conversation_id"])
    }

    func testBuilderForwardsValidTurnMetadataToHeaderAndClientMetadataLikeRust() throws {
        let provider = apiProvider(name: "openai", baseURL: "https://api.openai.com/v1")
        let turnMetadata = #"{"turn_id":"turn-123"}"#

        let request = try ResponsesRequestBuilder(model: "gpt-test", instructions: "inst", input: [])
            .clientMetadata([
                "fiber_run_id": "fiber-123",
                CodexRequestHeaders.turnMetadataHeaderName: "client-supplied"
            ])
            .turnMetadataHeader(turnMetadata)
            .extraHeaders([CodexRequestHeaders.turnMetadataHeaderName: "extra-supplied"])
            .build(provider: provider)

        let body = try JSONObject(request.body)
        let metadata = try XCTUnwrap(body["client_metadata"] as? [String: String])
        XCTAssertEqual(request.headers[CodexRequestHeaders.turnMetadataHeaderName], turnMetadata)
        XCTAssertEqual(metadata["fiber_run_id"], "fiber-123")
        XCTAssertEqual(metadata[CodexRequestHeaders.turnMetadataHeaderName], turnMetadata)
    }

    func testBuilderSkipsInvalidTurnMetadataHeaderLikeRustHeaderValueParsing() throws {
        let provider = apiProvider(name: "openai", baseURL: "https://api.openai.com/v1")

        let request = try ResponsesRequestBuilder(model: "gpt-test", instructions: "inst", input: [])
            .turnMetadataHeader("東京")
            .build(provider: provider)

        XCTAssertNil(request.headers[CodexRequestHeaders.turnMetadataHeaderName])
        XCTAssertNil(try JSONObject(request.body)["client_metadata"])
    }

    func testBuilderStripsSnakeCaseHeadersForAmazonBedrockMantleLikeRustSigV4Auth() throws {
        let provider = apiProvider(
            name: ModelProviderInfo.amazonBedrockProviderName,
            baseURL: ModelProviderInfo.amazonBedrockDefaultBaseURL
        )

        let request = try ResponsesRequestBuilder(model: "gpt-test", instructions: "inst", input: [])
            .conversation("conv-1")
            .turnMetadataHeader(#"{"turn_id":"turn-123"}"#)
            .extraHeaders([
                "future_identity_header": "future",
                "x-client-request-id": "request-1"
            ])
            .build(provider: provider)

        XCTAssertNil(request.headers["conversation_id"])
        XCTAssertNil(request.headers["thread_id"])
        XCTAssertNil(request.headers["session_id"])
        XCTAssertNil(request.headers["future_identity_header"])
        XCTAssertEqual(request.headers["thread-id"], "conv-1")
        XCTAssertEqual(request.headers["session-id"], "conv-1")
        XCTAssertEqual(request.headers["x-client-request-id"], "request-1")
        XCTAssertEqual(request.headers[CodexRequestHeaders.turnMetadataHeaderName], #"{"turn_id":"turn-123"}"#)
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
