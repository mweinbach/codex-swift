import CodexCore
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
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

    func testFunctionCallOutputContentItemSupportsImageDetailLikeCodeMode() throws {
        XCTAssertEqual(defaultImageDetail, .high)
        let json = #"{"type":"input_image","image_url":"data:image/png;base64,abc","detail":"original"}"#
        let item = try JSONDecoder().decode(FunctionCallOutputContentItem.self, from: Data(json.utf8))
        XCTAssertEqual(item, .inputImage(imageURL: "data:image/png;base64,abc", detail: .original))

        try XCTAssertJSONObjectEqual(item, [
            "type": "input_image",
            "image_url": "data:image/png;base64,abc",
            "detail": "original"
        ])

        try XCTAssertJSONObjectEqual(
            FunctionCallOutputContentItem.inputImage(imageURL: "data:image/png;base64,abc"),
            [
                "type": "input_image",
                "image_url": "data:image/png;base64,abc"
            ]
        )
    }

    func testMcpCallToolResultStructuredContentBecomesOutputPayload() throws {
        let payload = FunctionCallOutputPayload(callToolResult: McpCallToolResult(
            content: [.text(McpTextContent(text: "ignored"))],
            structuredContent: .object(["answer": .integer(42)])
        ))

        XCTAssertEqual(payload.success, true)
        XCTAssertNil(payload.contentItems)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payload.content.utf8)) as? [String: Any])
        XCTAssertEqual(object["answer"] as? Int, 42)
    }

    func testMcpCallToolResultImageContentBecomesContentItems() throws {
        let payload = FunctionCallOutputPayload(callToolResult: McpCallToolResult(
            content: [
                .text(McpTextContent(text: "caption")),
                .image(McpImageContent(data: "BASE64", mimeType: "image/png"))
            ]
        ))

        XCTAssertEqual(payload.success, true)
        XCTAssertEqual(payload.contentItems, [
            .inputText(text: "caption"),
            .inputImage(imageURL: "data:image/png;base64,BASE64")
        ])
    }

    func testMcpCallToolResultUnsupportedBlocksSkipContentItems() {
        let payload = FunctionCallOutputPayload(callToolResult: McpCallToolResult(
            content: [
                .text(McpTextContent(text: "caption")),
                .resourceLink(McpResourceLink(name: "doc", uri: "file:///tmp/doc.md"))
            ],
            isError: true
        ))

        XCTAssertEqual(payload.success, false)
        XCTAssertNil(payload.contentItems)
    }

    func testResponseInputItemRoundTripsMcpToolCallOutput() throws {
        let item = ResponseInputItem.mcpToolCallOutput(
            callID: "call-mcp",
            result: .ok(McpCallToolResult(content: [.text(McpTextContent(text: "hello"))]))
        )

        let data = try JSONEncoder().encode(item)
        XCTAssertEqual(try JSONDecoder().decode(ResponseInputItem.self, from: data), item)
        let object = try JSONObject(item)
        XCTAssertEqual(object["type"] as? String, "mcp_tool_call_output")
        XCTAssertEqual(object["call_id"] as? String, "call-mcp")
        XCTAssertNotNil(object["output"])
        XCTAssertNil(object["result"])
    }

    func testResponseInputItemDecodesMcpToolCallOutputLikeRust() throws {
        let json = #"""
        {
            "type": "mcp_tool_call_output",
            "call_id": "call-mcp",
            "output": {
                "Ok": {
                    "content": [
                        {
                            "type": "text",
                            "text": "hello"
                        }
                    ]
                }
            }
        }
        """#

        let item = try JSONDecoder().decode(ResponseInputItem.self, from: Data(json.utf8))
        XCTAssertEqual(item, .mcpToolCallOutput(
            callID: "call-mcp",
            result: .ok(McpCallToolResult(content: [.text(McpTextContent(text: "hello"))]))
        ))
    }

    func testMessagePhaseRoundTripsOnMessages() throws {
        let input = ResponseInputItem.message(
            role: "assistant",
            content: [.outputText(text: "thinking")],
            phase: .commentary
        )

        try XCTAssertJSONObjectEqual(input, [
            "type": "message",
            "role": "assistant",
            "content": [
                [
                    "type": "output_text",
                    "text": "thinking"
                ]
            ],
            "phase": "commentary"
        ])
        XCTAssertEqual(try JSONDecoder().decode(ResponseInputItem.self, from: JSONEncoder().encode(input)), input)

        let output = ResponseItem.message(
            role: "assistant",
            content: [.outputText(text: "done")],
            phase: .finalAnswer
        )

        try XCTAssertJSONObjectEqual(output, [
            "type": "message",
            "role": "assistant",
            "content": [
                [
                    "type": "output_text",
                    "text": "done"
                ]
            ],
            "phase": "final_answer"
        ])
        XCTAssertEqual(try JSONDecoder().decode(ResponseItem.self, from: JSONEncoder().encode(output)), output)
    }

    func testUserInputsBecomeMessageAndSkipSkills() throws {
        let item = ResponseInputItem(userInputs: [
            .text("hello"),
            .image(imageURL: "data:image/png;base64,abc"),
            .skill(name: "sample", path: "/tmp/SKILL.md")
        ])

        guard case let .message(role, content, _) = item else {
            return XCTFail("expected user message")
        }
        XCTAssertEqual(role, "user")
        XCTAssertEqual(content, [
            .inputText(text: "hello"),
            .inputImage(imageURL: "data:image/png;base64,abc")
        ])
    }

    func testLocalImagePNGBecomesDataURLAndKeepsOriginalWhenSmall() throws {
        let temp = try TemporaryDirectory()
        let path = temp.url.appendingPathComponent("small.png")
        let original = try writePNG(width: 64, height: 32, to: path)

        let item = ResponseInputItem(userInputs: [.localImage(path: path.path)])

        guard case let .message(_, content, _) = item,
              case let .inputImage(imageURL) = content.first
        else {
            return XCTFail("expected local image to become an input image")
        }

        let prefix = "data:image/png;base64,"
        XCTAssertTrue(imageURL.hasPrefix(prefix))
        let encoded = String(imageURL.dropFirst(prefix.count))
        XCTAssertEqual(Data(base64Encoded: encoded), original)
    }

    func testLocalImageLargePNGDownscalesToBounds() throws {
        let temp = try TemporaryDirectory()
        let path = temp.url.appendingPathComponent("large.png")
        _ = try writePNG(width: 4_096, height: 2_048, to: path)

        let processed = try LocalImageProcessor.loadAndResizeToFit(path: path)
        let dimensions = try imageDimensions(processed.bytes)

        XCTAssertLessThanOrEqual(processed.width, LocalImageProcessor.maxWidth)
        XCTAssertLessThanOrEqual(processed.height, LocalImageProcessor.maxHeight)
        XCTAssertEqual(processed.width, 2_048)
        XCTAssertEqual(processed.height, 1_024)
        XCTAssertEqual(dimensions.width, processed.width)
        XCTAssertEqual(dimensions.height, processed.height)
        XCTAssertEqual(processed.mime, "image/png")
    }

    func testLocalImageGIFTranscodesToPNGWithoutUpscalingLikeRust() throws {
        let temp = try TemporaryDirectory()
        let path = temp.url.appendingPathComponent("small.gif")
        let original = try writeImage(width: 64, height: 32, type: UTType.gif.identifier, to: path)

        let processed = try LocalImageProcessor.loadAndResizeToFit(path: path)
        let dimensions = try imageDimensions(processed.bytes)

        XCTAssertNotEqual(processed.bytes, original)
        XCTAssertEqual(processed.mime, "image/png")
        XCTAssertEqual(processed.width, 64)
        XCTAssertEqual(processed.height, 32)
        XCTAssertEqual(dimensions.width, 64)
        XCTAssertEqual(dimensions.height, 32)
    }

    func testLocalImageReadErrorAddsPlaceholder() throws {
        let temp = try TemporaryDirectory()
        let missingPath = temp.url.appendingPathComponent("missing-image.png")

        let item = ResponseInputItem(userInputs: [.localImage(path: missingPath.path)])

        guard case let .message(_, content, _) = item,
              case let .inputText(text) = content.first
        else {
            return XCTFail("expected local image read failure to become placeholder text")
        }

        XCTAssertTrue(text.contains(missingPath.path))
        XCTAssertTrue(text.contains("could not read"))
    }

    func testLocalImageNonImageAddsPlaceholder() throws {
        let temp = try TemporaryDirectory()
        let path = temp.url.appendingPathComponent("example.json")
        try #"{"hello":"world"}"#.write(to: path, atomically: true, encoding: .utf8)

        let item = ResponseInputItem(userInputs: [.localImage(path: path.path)])

        guard case let .message(_, content, _) = item,
              case let .inputText(text) = content.first
        else {
            return XCTFail("expected non-image file to become placeholder text")
        }

        XCTAssertTrue(text.contains("unsupported MIME type `application/json`"))
        XCTAssertTrue(text.contains(path.path))
    }

    func testLocalImageUnsupportedImageFormatAddsPlaceholder() throws {
        let temp = try TemporaryDirectory()
        let path = temp.url.appendingPathComponent("example.svg")
        try #"<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"></svg>"#
            .write(to: path, atomically: true, encoding: .utf8)

        let item = ResponseInputItem(userInputs: [.localImage(path: path.path)])

        guard case let .message(_, content, _) = item,
              case let .inputText(text) = content.first
        else {
            return XCTFail("expected unsupported image file to become placeholder text")
        }

        XCTAssertEqual(
            text,
            "Codex cannot attach image at `\(path.path)`: unsupported image format `image/svg+xml`."
        )
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

    func testRoundTripsContextCompactionLikeRust() throws {
        let json = #"{"type":"context_compaction","encrypted_content":"abc"}"#
        let item = try JSONDecoder().decode(ResponseItem.self, from: Data(json.utf8))
        XCTAssertEqual(item, .contextCompaction(encryptedContent: "abc"))

        try XCTAssertJSONObjectEqual(ResponseItem.contextCompaction(), [
            "type": "context_compaction"
        ])
    }

    func testRoundTripsFunctionCallNamespaceLikeRust() throws {
        let json = #"""
        {
            "type": "function_call",
            "name": "search",
            "namespace": "browser",
            "arguments": "{\"query\":\"swift\"}",
            "call_id": "call-1"
        }
        """#

        let item = try JSONDecoder().decode(ResponseItem.self, from: Data(json.utf8))
        XCTAssertEqual(item, .functionCall(name: "search", namespace: "browser", arguments: #"{"query":"swift"}"#, callID: "call-1"))

        try XCTAssertJSONObjectEqual(item, [
            "type": "function_call",
            "name": "search",
            "namespace": "browser",
            "arguments": #"{"query":"swift"}"#,
            "call_id": "call-1"
        ])

        try XCTAssertJSONObjectEqual(ResponseItem.functionCall(name: "search", arguments: "{}", callID: "call-2"), [
            "type": "function_call",
            "name": "search",
            "arguments": "{}",
            "call_id": "call-2"
        ])
    }

    func testResponseItemSkipsRuntimeIDsLikeRust() throws {
        let messageJSON = #"""
        {"type":"message","id":"msg-1","role":"assistant","content":[]}
        """#
        let message = try JSONDecoder().decode(ResponseItem.self, from: Data(messageJSON.utf8))
        XCTAssertEqual(message, .message(id: "msg-1", role: "assistant", content: []))
        try XCTAssertJSONObjectEqual(message, [
            "type": "message",
            "role": "assistant",
            "content": []
        ])

        let items: [ResponseItem] = [
            .reasoning(id: "rs_1", summary: [], content: nil, encryptedContent: nil),
            .localShellCall(
                id: "shell-id",
                callID: "shell-call",
                status: .completed,
                action: .exec(LocalShellExecAction(command: ["echo", "hi"]))
            ),
            .functionCall(id: "fc-id", name: "do_it", arguments: #"{"ok":true}"#, callID: "call-1"),
            .toolSearchCall(id: "ts-id", callID: "search-1", status: "completed", execution: "client", arguments: .object(["query": .string("docs")])),
            .customToolCall(id: "ct-id", status: "completed", callID: "tool-1", name: "custom", input: "{}"),
            .webSearchCall(id: "ws-id", status: "completed", action: .search(query: "weather"))
        ]

        for item in items {
            let object = try JSONObject(item)
            XCTAssertNil(object["id"], "expected id to be skipped for \(object["type"] ?? item)")
        }

        try XCTAssertJSONObjectEqual(ResponseItem.imageGenerationCall(id: "ig-1", status: "completed", result: "base64"), [
            "type": "image_generation_call",
            "id": "ig-1",
            "status": "completed",
            "result": "base64"
        ])
    }

    func testRoundTripsCustomToolCallOutputPayloadLikeRust() throws {
        let item = ResponseItem.customToolCallOutput(
            callID: "custom-1",
            name: "apply_patch",
            output: FunctionCallOutputPayload(
                content: "ignored when content items exist",
                contentItems: [.inputText(text: "patched")],
                success: true
            )
        )

        try XCTAssertJSONObjectEqual(item, [
            "type": "custom_tool_call_output",
            "call_id": "custom-1",
            "name": "apply_patch",
            "output": [
                [
                    "type": "input_text",
                    "text": "patched"
                ]
            ]
        ])
        guard case let .customToolCallOutput(decodedCallID, decodedName, decodedOutput) =
            try JSONDecoder().decode(ResponseItem.self, from: JSONEncoder().encode(item))
        else {
            return XCTFail("expected custom tool output")
        }
        XCTAssertEqual(decodedCallID, "custom-1")
        XCTAssertEqual(decodedName, "apply_patch")
        XCTAssertEqual(decodedOutput.contentItems, [.inputText(text: "patched")])

        try XCTAssertJSONObjectEqual(ResponseItem.customToolCallOutput(callID: "custom-2", output: "done"), [
            "type": "custom_tool_call_output",
            "call_id": "custom-2",
            "output": "done"
        ])
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
        XCTAssertNil(object["id"])
        XCTAssertEqual(object["status"] as? String, "completed")
    }

    func testRoundTripsWebSearchSearchQueriesLikeRust() throws {
        let json = #"""
        {
            "type": "search",
            "queries": ["first", "second"]
        }
        """#
        let action = try JSONDecoder().decode(WebSearchAction.self, from: Data(json.utf8))
        XCTAssertEqual(action, .search(query: nil, queries: ["first", "second"]))

        try XCTAssertJSONObjectEqual(action, [
            "type": "search",
            "queries": ["first", "second"]
        ])
    }

    func testRoundTripsToolSearchCallLikeRust() throws {
        let json = #"""
        {
            "type": "tool_search_call",
            "call_id": "search-1",
            "execution": "client",
            "arguments": {
                "query": "calendar create",
                "limit": 1
            }
        }
        """#

        let item = try JSONDecoder().decode(ResponseItem.self, from: Data(json.utf8))
        XCTAssertEqual(item, .toolSearchCall(
            callID: "search-1",
            execution: "client",
            arguments: .object([
                "query": .string("calendar create"),
                "limit": .integer(1)
            ])
        ))

        try XCTAssertJSONObjectEqual(item, [
            "type": "tool_search_call",
            "call_id": "search-1",
            "execution": "client",
            "arguments": [
                "query": "calendar create",
                "limit": 1
            ]
        ])
    }

    func testRoundTripsToolSearchOutputLikeRust() throws {
        let tool: JSONValue = .object([
            "type": .string("function"),
            "name": .string("mcp__codex_apps__calendar_create_event"),
            "description": .string("Create a calendar event."),
            "defer_loading": .bool(true),
            "parameters": .object([
                "type": .string("object"),
                "properties": .object([
                    "title": .object(["type": .string("string")])
                ]),
                "required": .array([.string("title")]),
                "additionalProperties": .bool(false)
            ])
        ])
        let input = ResponseInputItem.toolSearchOutput(
            callID: "search-1",
            status: "completed",
            execution: "client",
            tools: [tool]
        )

        XCTAssertEqual(
            input.responseItem(),
            .toolSearchOutput(callID: "search-1", status: "completed", execution: "client", tools: [tool])
        )

        try XCTAssertJSONObjectEqual(input, [
            "type": "tool_search_output",
            "call_id": "search-1",
            "status": "completed",
            "execution": "client",
            "tools": [[
                "type": "function",
                "name": "mcp__codex_apps__calendar_create_event",
                "description": "Create a calendar event.",
                "defer_loading": true,
                "parameters": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string"]
                    ],
                    "required": ["title"],
                    "additionalProperties": false
                ]
            ]]
        ])
    }

    func testToolSearchServerItemsAllowNullCallID() throws {
        let call = try JSONDecoder().decode(ResponseItem.self, from: Data(#"""
        {
            "type": "tool_search_call",
            "execution": "server",
            "call_id": null,
            "status": "completed",
            "arguments": {
                "paths": ["crm"]
            }
        }
        """#.utf8))
        XCTAssertEqual(call, .toolSearchCall(
            callID: nil,
            status: "completed",
            execution: "server",
            arguments: .object(["paths": .array([.string("crm")])])
        ))

        let output = try JSONDecoder().decode(ResponseItem.self, from: Data(#"""
        {
            "type": "tool_search_output",
            "execution": "server",
            "call_id": null,
            "status": "completed",
            "tools": []
        }
        """#.utf8))
        XCTAssertEqual(output, .toolSearchOutput(
            callID: nil,
            status: "completed",
            execution: "server",
            tools: []
        ))

        try XCTAssertJSONObjectEqual(call, [
            "type": "tool_search_call",
            "call_id": NSNull(),
            "status": "completed",
            "execution": "server",
            "arguments": [
                "paths": ["crm"]
            ]
        ])
        try XCTAssertJSONObjectEqual(output, [
            "type": "tool_search_output",
            "call_id": NSNull(),
            "status": "completed",
            "execution": "server",
            "tools": []
        ])
    }

    func testRoundTripsImageGenerationCallLikeRust() throws {
        let json = #"""
        {
            "id": "ig_123",
            "type": "image_generation_call",
            "status": "completed",
            "revised_prompt": "A gray tabby cat",
            "result": "Zm9v"
        }
        """#

        let item = try JSONDecoder().decode(ResponseItem.self, from: Data(json.utf8))
        XCTAssertEqual(item, .imageGenerationCall(
            id: "ig_123",
            status: "completed",
            revisedPrompt: "A gray tabby cat",
            result: "Zm9v"
        ))

        try XCTAssertJSONObjectEqual(item, [
            "id": "ig_123",
            "type": "image_generation_call",
            "status": "completed",
            "revised_prompt": "A gray tabby cat",
            "result": "Zm9v"
        ])
    }

    func testRoundTripsGhostSnapshotPayloadLikeRust() throws {
        let json = #"""
        {
            "type": "ghost_snapshot",
            "ghost_commit": {
                "id": "ghost-1",
                "parent": "parent-1",
                "preexisting_untracked_files": ["notes.txt"],
                "preexisting_untracked_dirs": ["scratch"]
            }
        }
        """#

        let item = try JSONDecoder().decode(ResponseItem.self, from: Data(json.utf8))
        XCTAssertEqual(item, .ghostSnapshot(ghostCommit: GhostCommit(
            id: "ghost-1",
            parent: "parent-1",
            preexistingUntrackedFiles: ["notes.txt"],
            preexistingUntrackedDirs: ["scratch"]
        )))

        let object = try JSONObject(item)
        XCTAssertEqual(object["type"] as? String, "ghost_snapshot")
        let ghostCommit = try XCTUnwrap(object["ghost_commit"] as? [String: Any])
        XCTAssertEqual(ghostCommit["id"] as? String, "ghost-1")
        XCTAssertEqual(ghostCommit["parent"] as? String, "parent-1")
        XCTAssertEqual(ghostCommit["preexisting_untracked_files"] as? [String], ["notes.txt"])
        XCTAssertEqual(ghostCommit["preexisting_untracked_dirs"] as? [String], ["scratch"])
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
        XCTAssertNil(object["id"])
        let content = try XCTUnwrap(object["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 2)
        XCTAssertEqual(content[0]["type"] as? String, "reasoning_text")
        XCTAssertEqual(content[0]["text"] as? String, "raw details")
        XCTAssertEqual(object["encrypted_content"] as? String, "encrypted")
    }

    func testReasoningPayloadSkipsNonRawContentLikeRust() throws {
        let item = ResponseItem.reasoning(
            id: "reasoning_1",
            summary: [.summaryText(text: "Step 1")],
            content: [.text("visible thought")]
        )

        let object = try JSONObject(item)
        XCTAssertNil(object["content"])
        XCTAssertTrue(object["encrypted_content"] is NSNull)
    }

    func testDecodesReasoningMissingIDLikeRustDefault() throws {
        let json = #"""
        {
            "type": "reasoning",
            "summary": [
                {"type": "summary_text", "text": "Step 1"}
            ]
        }
        """#

        let item = try JSONDecoder().decode(ResponseItem.self, from: Data(json.utf8))
        XCTAssertEqual(item, .reasoning(id: "", summary: [.summaryText(text: "Step 1")]))

        try XCTAssertJSONObjectEqual(item, [
            "type": "reasoning",
            "summary": [
                [
                    "type": "summary_text",
                    "text": "Step 1"
                ]
            ],
            "encrypted_content": NSNull()
        ])
    }

    func testResponseItemSerializesRustNullOptionals() throws {
        try XCTAssertJSONObjectEqual(ResponseItem.reasoning(id: "rs_1", summary: []), [
            "type": "reasoning",
            "summary": [],
            "encrypted_content": NSNull()
        ])

        try XCTAssertJSONObjectEqual(ResponseItem.localShellCall(
            callID: nil,
            status: .completed,
            action: .exec(LocalShellExecAction(command: ["echo", "hi"]))
        ), [
            "type": "local_shell_call",
            "call_id": NSNull(),
            "status": "completed",
            "action": [
                "type": "exec",
                "command": ["echo", "hi"]
            ]
        ])
    }

    func testRoundTripsCallPairResponseItems() throws {
        let items: [ResponseItem] = [
            .localShellCall(
                callID: "shell-call",
                status: .completed,
                action: .exec(LocalShellExecAction(command: ["echo", "hi"]))
            ),
            .functionCall(name: "do_it", arguments: #"{"ok":true}"#, callID: "call-1"),
            .functionCallOutput(callID: "call-1", output: FunctionCallOutputPayload(content: "done")),
            .customToolCall(status: "completed", callID: "tool-1", name: "custom", input: "{}"),
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

    func testShellToolCallParamsDecodeApprovalHintsLikeRust() throws {
        let json = #"""
        {
            "command": ["git", "push"],
            "workdir": "/repo",
            "timeout_ms": 1000,
            "sandbox_permissions": "require_escalated",
            "prefix_rule": ["git", "push"],
            "additional_permissions": {
                "network": {
                    "enabled": true
                },
                "file_system": {
                    "read": ["/repo"]
                }
            },
            "justification": "publish branch"
        }
        """#

        let params = try JSONDecoder().decode(ShellToolCallParams.self, from: Data(json.utf8))
        XCTAssertEqual(params.command, ["git", "push"])
        XCTAssertEqual(params.timeoutMS, 1000)
        XCTAssertEqual(params.sandboxPermissions, .requireEscalated)
        XCTAssertEqual(params.prefixRule, ["git", "push"])
        XCTAssertEqual(params.additionalPermissions?.network, RequestPermissionNetworkPermissions(enabled: true))
        XCTAssertEqual(params.additionalPermissions?.fileSystem, .object([
            "read": .array([.string("/repo")])
        ]))
        XCTAssertEqual(params.justification, "publish branch")
    }

    func testShellCommandToolCallParamsDecodeApprovalHintsLikeRust() throws {
        let json = #"""
        {
            "command": "git status",
            "workdir": "/repo",
            "login": false,
            "timeout": 2000,
            "sandbox_permissions": "use_default",
            "prefix_rule": ["git"],
            "additional_permissions": {
                "network": {
                    "enabled": false
                }
            },
            "justification": "inspect repo"
        }
        """#

        let params = try JSONDecoder().decode(ShellCommandToolCallParams.self, from: Data(json.utf8))
        XCTAssertEqual(params.command, "git status")
        XCTAssertEqual(params.workdir, "/repo")
        XCTAssertEqual(params.login, false)
        XCTAssertEqual(params.timeoutMS, 2000)
        XCTAssertEqual(params.sandboxPermissions, .useDefault)
        XCTAssertEqual(params.prefixRule, ["git"])
        XCTAssertEqual(params.additionalPermissions?.network, RequestPermissionNetworkPermissions(enabled: false))
        XCTAssertNil(params.additionalPermissions?.fileSystem)
        XCTAssertEqual(params.justification, "inspect repo")
    }

    func testSearchToolCallParamsWireShapeLikeRust() throws {
        let json = #"{"query":"calendar create","limit":2}"#
        let params = try JSONDecoder().decode(SearchToolCallParams.self, from: Data(json.utf8))
        XCTAssertEqual(params, SearchToolCallParams(query: "calendar create", limit: 2))

        try XCTAssertJSONObjectEqual(params, [
            "query": "calendar create",
            "limit": 2
        ])

        try XCTAssertJSONObjectEqual(SearchToolCallParams(query: "calendar create"), [
            "query": "calendar create"
        ])
    }

    func testSandboxPermissionsWireValues() {
        XCTAssertTrue(SandboxPermissions.requireEscalated.requiresEscalatedPermissions)
        XCTAssertFalse(SandboxPermissions.useDefault.requiresEscalatedPermissions)
    }

    private func writePNG(width: Int, height: Int, to path: URL) throws -> Data {
        try writeImage(width: width, height: height, type: UTType.png.identifier, to: path)
    }

    private func writeImage(width: Int, height: Int, type: String, to path: URL) throws -> Data {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TestImageError.contextCreation
        }

        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(path as CFURL, type as CFString, 1, nil)
        else {
            throw TestImageError.imageEncoding
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TestImageError.imageEncoding
        }

        return try Data(contentsOf: path)
    }

    private func imageDimensions(_ data: Data) throws -> (width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw TestImageError.imageDecoding
        }
        return (image.width, image.height)
    }
}

private enum TestImageError: Error {
    case contextCreation
    case imageEncoding
    case imageDecoding
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
