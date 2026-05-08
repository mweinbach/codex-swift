import CodexCore
import XCTest

final class StreamEventUtilsTests: XCTestCase {
    func testLastAssistantMessageUsesLastOutputText() {
        let item = ResponseItem.message(role: "assistant", content: [
            .outputText(text: "first"),
            .inputText(text: "ignored"),
            .outputText(text: "last")
        ])

        XCTAssertEqual(StreamEventUtils.lastAssistantMessage(from: item), "last")
    }

    func testLastAssistantMessageIgnoresNonAssistantMessages() {
        let item = ResponseItem.message(role: "user", content: [
            .outputText(text: "not-agent")
        ])

        XCTAssertNil(StreamEventUtils.lastAssistantMessage(from: item))
    }

    func testHandleNonToolResponseItemDelegatesTurnItems() {
        let assistant = ResponseItem.message(id: "msg1", role: "assistant", content: [
            .outputText(text: "done")
        ])
        let toolOutput = ResponseItem.functionCallOutput(
            callID: "call1",
            output: FunctionCallOutputPayload(content: "done")
        )

        XCTAssertEqual(
            StreamEventUtils.handleNonToolResponseItem(assistant),
            .agentMessage(AgentMessageItem(id: "msg1", content: [.text("done")]))
        )
        XCTAssertNil(StreamEventUtils.handleNonToolResponseItem(toolOutput))
    }

    func testResponseInputToResponseItemConvertsOutputVariants() {
        XCTAssertEqual(
            StreamEventUtils.responseInputToResponseItem(.functionCallOutput(
                callID: "fn1",
                output: FunctionCallOutputPayload(content: "ok")
            )),
            .functionCallOutput(callID: "fn1", output: FunctionCallOutputPayload(content: "ok"))
        )
        XCTAssertEqual(
            StreamEventUtils.responseInputToResponseItem(.customToolCallOutput(
                callID: "custom1",
                output: "ok"
            )),
            .customToolCallOutput(callID: "custom1", output: "ok")
        )
        XCTAssertEqual(
            StreamEventUtils.responseInputToResponseItem(.toolSearchOutput(
                callID: "search1",
                status: "completed",
                execution: "client",
                tools: [.object(["name": .string("calendar")])]
            )),
            .toolSearchOutput(
                callID: "search1",
                status: "completed",
                execution: "client",
                tools: [.object(["name": .string("calendar")])]
            )
        )
        XCTAssertNil(StreamEventUtils.responseInputToResponseItem(.message(role: "user", content: [])))
    }

    func testResponseInputToResponseItemConvertsMcpResults() {
        let input = ResponseInputItem.mcpToolCallOutput(
            callID: "mcp1",
            result: .ok(McpCallToolResult(
                content: [
                    .text(McpTextContent(text: "caption")),
                    .image(McpImageContent(data: "data:image/jpeg;base64,ABC", mimeType: "image/jpeg"))
                ]
            ))
        )

        guard case let .functionCallOutput(callID, output) = StreamEventUtils.responseInputToResponseItem(input) else {
            return XCTFail("Expected function call output")
        }

        XCTAssertEqual(callID, "mcp1")
        XCTAssertEqual(output.success, true)
        XCTAssertEqual(output.contentItems, [
            .inputText(text: "caption"),
            .inputImage(imageURL: "data:image/jpeg;base64,ABC")
        ])
    }

    func testResponseInputToResponseItemUsesRawMcpErrorString() {
        XCTAssertEqual(
            StreamEventUtils.responseInputToResponseItem(.mcpToolCallOutput(
                callID: "mcp1",
                result: .err("failed")
            )),
            .functionCallOutput(
                callID: "mcp1",
                output: FunctionCallOutputPayload(content: "failed", success: false)
            )
        )
    }

    func testResponseInputItemResponseItemConversionMatchesProtocolFromImpl() {
        XCTAssertEqual(
            ResponseInputItem.mcpToolCallOutput(callID: "mcp1", result: .err("failed")).responseItem(),
            .functionCallOutput(
                callID: "mcp1",
                output: FunctionCallOutputPayload(content: #"err: "failed""#, success: false)
            )
        )
    }
}
