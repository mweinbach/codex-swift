import CodexCore
import XCTest

final class ChatAPITests: XCTestCase {
    func testAttachesConversationAndSubagentHeaders() throws {
        let input: [ResponseItem] = [
            .message(role: "user", content: [.inputText(text: "hi")])
        ]

        let request = ChatRequestBuilder(
            model: "gpt-test",
            instructions: "inst",
            input: input
        )
        .conversationID("conv-1")
        .sessionSource(.subagent(.review))
        .build(provider: provider())

        XCTAssertEqual(request.headers["conversation_id"], "conv-1")
        XCTAssertEqual(request.headers["session_id"], "conv-1")
        XCTAssertEqual(request.headers["x-openai-subagent"], "review")
    }

    func testUserImagesBecomeChatImageURLContent() throws {
        let request = ChatRequestBuilder(
            model: "gpt-test",
            instructions: "inst",
            input: [
                .message(role: "user", content: [
                    .inputText(text: "look"),
                    .inputImage(imageURL: "data:image/png;base64,abc")
                ])
            ],
            tools: [.object(["type": .string("function"), "name": .string("noop")])]
        )
        .build(provider: provider())

        let body = try JSONObject(request.body)
        XCTAssertEqual(body["model"] as? String, "gpt-test")
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual((body["tools"] as? [[String: Any]])?.first?["name"] as? String, "noop")

        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages[0]["role"] as? String, "system")
        XCTAssertEqual(messages[0]["content"] as? String, "inst")
        XCTAssertEqual(messages[1]["role"] as? String, "user")

        let content = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        XCTAssertEqual(content[0]["type"] as? String, "text")
        XCTAssertEqual(content[0]["text"] as? String, "look")
        XCTAssertEqual(content[1]["type"] as? String, "image_url")
        let imageURL = try XCTUnwrap(content[1]["image_url"] as? [String: Any])
        XCTAssertEqual(imageURL["url"] as? String, "data:image/png;base64,abc")
    }

    func testFunctionCallAndOutputMapToChatToolMessages() throws {
        let output = FunctionCallOutputPayload(
            content: "ignored",
            contentItems: [
                .inputText(text: "caption"),
                .inputImage(imageURL: "data:image/png;base64,abc")
            ]
        )

        let request = ChatRequestBuilder(
            model: "gpt-test",
            instructions: "inst",
            input: [
                .functionCall(name: "run", arguments: #"{"cmd":"date"}"#, callID: "call-1"),
                .functionCallOutput(callID: "call-1", output: output)
            ]
        )
        .build(provider: provider())

        let messages = try XCTUnwrap(JSONObject(request.body)["messages"] as? [[String: Any]])
        XCTAssertEqual(messages[1]["role"] as? String, "assistant")
        XCTAssertTrue(messages[1]["content"] is NSNull)
        let toolCalls = try XCTUnwrap(messages[1]["tool_calls"] as? [[String: Any]])
        XCTAssertEqual(toolCalls[0]["id"] as? String, "call-1")
        XCTAssertEqual(toolCalls[0]["type"] as? String, "function")
        let function = try XCTUnwrap(toolCalls[0]["function"] as? [String: Any])
        XCTAssertEqual(function["name"] as? String, "run")
        XCTAssertEqual(function["arguments"] as? String, #"{"cmd":"date"}"#)

        XCTAssertEqual(messages[2]["role"] as? String, "tool")
        XCTAssertEqual(messages[2]["tool_call_id"] as? String, "call-1")
        let content = try XCTUnwrap(messages[2]["content"] as? [[String: Any]])
        XCTAssertEqual(content[0]["type"] as? String, "text")
        XCTAssertEqual(content[0]["text"] as? String, "caption")
        XCTAssertEqual(content[1]["type"] as? String, "image_url")
    }

    func testReasoningContentAttachesToAssistantAnchorWhenLastRoleIsNotUser() throws {
        let request = ChatRequestBuilder(
            model: "gpt-test",
            instructions: "inst",
            input: [
                .message(role: "user", content: [.inputText(text: "why")]),
                .message(role: "assistant", content: [.outputText(text: "answer")]),
                .reasoning(
                    id: "rs_1",
                    summary: [],
                    content: [.reasoningText(text: "because")],
                    encryptedContent: nil
                )
            ]
        )
        .build(provider: provider())

        let messages = try XCTUnwrap(JSONObject(request.body)["messages"] as? [[String: Any]])
        XCTAssertEqual(messages[2]["role"] as? String, "assistant")
        XCTAssertEqual(messages[2]["content"] as? String, "answer")
        XCTAssertEqual(messages[2]["reasoning"] as? String, "because")
    }

    func testDuplicateAssistantTextIsSkipped() throws {
        let request = ChatRequestBuilder(
            model: "gpt-test",
            instructions: "inst",
            input: [
                .message(role: "assistant", content: [.outputText(text: "same")]),
                .message(role: "assistant", content: [.outputText(text: "same")])
            ]
        )
        .build(provider: provider())

        let messages = try XCTUnwrap(JSONObject(request.body)["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[1]["role"] as? String, "assistant")
        XCTAssertEqual(messages[1]["content"] as? String, "same")
    }

    private func provider() -> APIProvider {
        APIProvider(
            name: "openai",
            baseURL: "https://api.openai.com/v1",
            wireAPI: .chat,
            retry: ProviderRetryConfig(
                maxAttempts: 1,
                baseDelayMilliseconds: 10,
                retry429: false,
                retry5xx: true,
                retryTransport: true
            ),
            streamIdleTimeoutMilliseconds: 1_000
        )
    }
}
