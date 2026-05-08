import CodexCore
import XCTest

final class ResponseModelsTests: XCTestCase {
    func testFunctionCallOutputSerializesSuccessAsPlainString() throws {
        let item = ResponseInputItem.functionCallOutput(
            callID: "call1",
            output: FunctionCallOutputPayload(content: "ok")
        )
        let object = try JSONObject(item)
        XCTAssertEqual(object["output"] as? String, "ok")
    }

    func testFunctionCallOutputSerializesImageOutputsAsArray() throws {
        let payload = FunctionCallOutputPayload(
            content: "ignored when content items exist",
            contentItems: [
                .inputText(text: "caption"),
                .inputImage(imageURL: "data:image/png;base64,BASE64")
            ],
            success: true
        )
        let item = ResponseInputItem.functionCallOutput(callID: "call1", output: payload)
        let object = try JSONObject(item)
        let output = try XCTUnwrap(object["output"] as? [[String: Any]])
        XCTAssertEqual(output.count, 2)
        XCTAssertEqual(output[0]["type"] as? String, "input_text")
        XCTAssertEqual(output[1]["image_url"] as? String, "data:image/png;base64,BASE64")
    }

    func testDeserializesArrayPayloadIntoItems() throws {
        let json = #"""
        [
            {"type": "input_text", "text": "note"},
            {"type": "input_image", "image_url": "data:image/png;base64,XYZ"}
        ]
        """#
        let payload = try JSONDecoder().decode(FunctionCallOutputPayload.self, from: Data(json.utf8))
        XCTAssertEqual(payload.success, nil)
        XCTAssertEqual(payload.contentItems, [
            .inputText(text: "note"),
            .inputImage(imageURL: "data:image/png;base64,XYZ")
        ])
    }

    func testDeserializesCompactionAlias() throws {
        let json = #"{"type":"compaction_summary","encrypted_content":"abc"}"#
        let item = try JSONDecoder().decode(ResponseItem.self, from: Data(json.utf8))
        XCTAssertEqual(item, .compaction(encryptedContent: "abc"))
    }

    func testRoundTripsWebSearchCallActions() throws {
        let json = #"""
        {
            "type": "web_search_call",
            "id": "ws_1",
            "status": "completed",
            "action": {
                "type": "search",
                "query": "weather seattle"
            }
        }
        """#
        let item = try JSONDecoder().decode(ResponseItem.self, from: Data(json.utf8))
        XCTAssertEqual(item, .webSearchCall(id: "ws_1", status: "completed", action: .search(query: "weather seattle")))
        let object = try JSONObject(item)
        XCTAssertEqual(object["type"] as? String, "web_search_call")
        XCTAssertEqual(object["id"] as? String, "ws_1")
        XCTAssertEqual(object["status"] as? String, "completed")
    }

    func testDecodesReasoningPayload() throws {
        let json = #"""
        {
            "type": "reasoning",
            "id": "reasoning_1",
            "summary": [
                {"type": "summary_text", "text": "Step 1"}
            ],
            "content": [
                {"type": "reasoning_text", "text": "raw details"},
                {"type": "text", "text": "final thought"}
            ],
            "encrypted_content": "encrypted"
        }
        """#
        let item = try JSONDecoder().decode(ResponseItem.self, from: Data(json.utf8))

        XCTAssertEqual(item, .reasoning(
            id: "reasoning_1",
            summary: [.summaryText(text: "Step 1")],
            content: [
                .reasoningText(text: "raw details"),
                .text("final thought")
            ],
            encryptedContent: "encrypted"
        ))
        let object = try JSONObject(item)
        XCTAssertEqual(object["type"] as? String, "reasoning")
        XCTAssertEqual(object["id"] as? String, "reasoning_1")
        XCTAssertEqual(object["encrypted_content"] as? String, "encrypted")
    }

    func testRoundTripsCallPairResponseItems() throws {
        let items: [ResponseItem] = [
            .localShellCall(
                id: "shell-id",
                callID: "shell-call",
                status: .completed,
                action: .exec(LocalShellExecAction(command: ["echo", "hi"]))
            ),
            .functionCall(id: "fc-id", name: "do_it", arguments: #"{"ok":true}"#, callID: "call-1"),
            .functionCallOutput(callID: "call-1", output: FunctionCallOutputPayload(content: "done")),
            .customToolCall(id: "ct-id", status: "completed", callID: "tool-1", name: "custom", input: "{}"),
            .customToolCallOutput(callID: "tool-1", output: "done")
        ]

        for item in items {
            let data = try JSONEncoder().encode(item)
            XCTAssertEqual(try JSONDecoder().decode(ResponseItem.self, from: data), item)
        }
    }

    func testShellToolCallParamsAcceptTimeoutAlias() throws {
        let json = #"{"command":["ls","-l"],"workdir":"/tmp","timeout":1000}"#
        let params = try JSONDecoder().decode(ShellToolCallParams.self, from: Data(json.utf8))
        XCTAssertEqual(params.command, ["ls", "-l"])
        XCTAssertEqual(params.workdir, "/tmp")
        XCTAssertEqual(params.timeoutMS, 1000)
    }

    func testSandboxPermissionsWireValues() {
        XCTAssertTrue(SandboxPermissions.requireEscalated.requiresEscalatedPermissions)
        XCTAssertFalse(SandboxPermissions.useDefault.requiresEscalatedPermissions)
    }
}
