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

    func testFunctionCallOutputTextContentMatchesRustFallback() {
        XCTAssertEqual(FunctionCallOutputPayload(content: "ok").textContent, "ok")

        let payload = FunctionCallOutputPayload(
            content: "ignored when content items exist",
            contentItems: [
                .inputText(text: "line 1"),
                .inputImage(imageURL: "data:image/png;base64,BASE64", detail: defaultImageDetail),
                .inputText(text: "   "),
                .inputText(text: "line 2")
            ]
        )
        XCTAssertEqual(payload.textContent, "line 1\nline 2")

        let imagesOnly = FunctionCallOutputPayload(
            content: "ignored when content items exist",
            contentItems: [
                .inputText(text: "\n\t "),
                .inputImage(imageURL: "data:image/png;base64,BASE64", detail: defaultImageDetail)
            ]
        )
        XCTAssertNil(imagesOnly.textContent)
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

    func testContentItemInputImagePreservesOptionalDetailLikeRust() throws {
        let json = #"{"type":"input_image","image_url":"data:image/png;base64,abc","detail":"high"}"#
        let item = try JSONDecoder().decode(ContentItem.self, from: Data(json.utf8))
        XCTAssertEqual(item, .inputImage(imageURL: "data:image/png;base64,abc", detail: .high))

        try XCTAssertJSONObjectEqual(item, [
            "type": "input_image",
            "image_url": "data:image/png;base64,abc",
            "detail": "high"
        ])

        try XCTAssertJSONObjectEqual(ContentItem.inputImage(imageURL: "data:image/png;base64,abc"), [
            "type": "input_image",
            "image_url": "data:image/png;base64,abc"
        ])
    }

    func testOriginalImageDetailIsAllowedWhenModelSupportsItLikeRustToolsHelper() throws {
        let modelInfo = try imageDetailModelInfo(supportsOriginal: true)

        XCTAssertTrue(canRequestOriginalImageDetail(modelInfo))
        XCTAssertEqual(normalizeOutputImageDetail(modelInfo: modelInfo, detail: .original), .original)
        XCTAssertNil(normalizeOutputImageDetail(modelInfo: modelInfo, detail: nil))
    }

    func testOriginalImageDetailIsDroppedWithoutModelSupportLikeRustToolsHelper() throws {
        let modelInfo = try imageDetailModelInfo(supportsOriginal: false)

        XCTAssertFalse(canRequestOriginalImageDetail(modelInfo))
        XCTAssertNil(normalizeOutputImageDetail(modelInfo: modelInfo, detail: .original))
    }

    func testNonOriginalImageDetailIsPreservedLikeRustToolsHelper() throws {
        let modelInfo = try imageDetailModelInfo(supportsOriginal: true)

        XCTAssertEqual(normalizeOutputImageDetail(modelInfo: modelInfo, detail: .low), .low)
        XCTAssertEqual(normalizeOutputImageDetail(modelInfo: modelInfo, detail: .high), .high)
        XCTAssertEqual(normalizeOutputImageDetail(modelInfo: modelInfo, detail: .auto), .auto)
    }

    func testSanitizeOriginalImageDetailFallsBackToHighWithoutSupportLikeRustToolsHelper() {
        let items: [FunctionCallOutputContentItem] = [
            .inputText(text: "header"),
            .inputImage(imageURL: "data:image/png;base64,AAA", detail: .original),
            .inputImage(imageURL: "data:image/png;base64,BBB", detail: .low),
            .inputImage(imageURL: "data:image/png;base64,CCC")
        ]

        XCTAssertEqual(sanitizeOriginalImageDetail(
            canRequestOriginalImageDetail: false,
            items: items
        ), [
            .inputText(text: "header"),
            .inputImage(imageURL: "data:image/png;base64,AAA", detail: defaultImageDetail),
            .inputImage(imageURL: "data:image/png;base64,BBB", detail: .low),
            .inputImage(imageURL: "data:image/png;base64,CCC")
        ])

        XCTAssertEqual(sanitizeOriginalImageDetail(
            canRequestOriginalImageDetail: true,
            items: items
        ), items)
    }

    func testReasoningSummaryRejectsUnknownTypeLikeRustSerdeTag() throws {
        let json = #"{"type":"summary_markdown","text":"notes"}"#
        XCTAssertThrowsError(try JSONDecoder().decode(
            ReasoningItemReasoningSummary.self,
            from: Data(json.utf8)
        ))
    }

    func testReasoningContentRejectsUnknownTypeLikeRustSerdeTag() throws {
        let json = #"{"type":"redacted_reasoning","text":"hidden"}"#
        XCTAssertThrowsError(try JSONDecoder().decode(
            ReasoningItemContent.self,
            from: Data(json.utf8)
        ))
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
            .inputImage(imageURL: "data:image/png;base64,BASE64", detail: defaultImageDetail)
        ])
    }

    func testMcpCallToolResultImageContentPreservesDetailMetadataLikeRust() {
        let payload = FunctionCallOutputPayload(callToolResult: McpCallToolResult(
            content: [
                .image(McpImageContent(
                    data: "BASE64",
                    mimeType: "image/png",
                    meta: .object([McpImageContent.imageDetailMetaKey: .string("original")])
                ))
            ]
        ))

        XCTAssertEqual(payload.success, true)
        XCTAssertEqual(payload.contentItems, [
            .inputImage(imageURL: "data:image/png;base64,BASE64", detail: .original)
        ])
    }

    func testMcpCallToolResultImageContentPreservesStandardDetailMetadataLikeRust() {
        let payload = FunctionCallOutputPayload(callToolResult: McpCallToolResult(
            content: [
                .image(McpImageContent(
                    data: "BASE64",
                    mimeType: "image/png",
                    meta: .object([McpImageContent.imageDetailMetaKey: .string("high")])
                ))
            ]
        ))

        XCTAssertEqual(payload.success, true)
        XCTAssertEqual(payload.contentItems, [
            .inputImage(imageURL: "data:image/png;base64,BASE64", detail: .high)
        ])
    }

    func testMcpCallToolResultImageContentPreservesExistingDataURLsLikeRust() {
        let payload = FunctionCallOutputPayload(callToolResult: McpCallToolResult(
            content: [
                .image(McpImageContent(
                    data: "data:image/png;base64,BASE64",
                    mimeType: "image/png"
                ))
            ]
        ))

        XCTAssertEqual(payload.success, true)
        XCTAssertEqual(payload.contentItems, [
            .inputImage(imageURL: "data:image/png;base64,BASE64", detail: defaultImageDetail)
        ])
    }

    func testMcpCallToolResultImageContentDefaultsMissingMimeLikeRust() throws {
        let json = #"""
        {
            "content": [
                {
                    "type": "image",
                    "data": "BASE64"
                }
            ]
        }
        """#
        let result = try JSONDecoder().decode(McpCallToolResult.self, from: Data(json.utf8))
        let payload = FunctionCallOutputPayload(callToolResult: result)

        XCTAssertEqual(payload.success, true)
        XCTAssertEqual(payload.contentItems, [
            .inputImage(imageURL: "data:application/octet-stream;base64,BASE64", detail: defaultImageDetail)
        ])
    }

    func testMcpCallToolResultMixedUnsupportedBlocksBecomeTextWhenImagePresentLikeRust() throws {
        let resource = McpResourceLink(
            name: "readme",
            uri: "file:///tmp/README.md",
            description: "docs",
            mimeType: "text/markdown",
            size: 42,
            title: "README"
        )
        let payload = FunctionCallOutputPayload(callToolResult: McpCallToolResult(
            content: [
                .text(McpTextContent(text: "caption")),
                .image(McpImageContent(data: "BASE64", mimeType: "image/png")),
                .resourceLink(resource)
            ]
        ))

        XCTAssertEqual(payload.success, true)
        let items = try XCTUnwrap(payload.contentItems)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(Array(items.dropLast()), [
            .inputText(text: "caption"),
            .inputImage(imageURL: "data:image/png;base64,BASE64", detail: defaultImageDetail)
        ])

        guard case let .inputText(resourceText) = items.last else {
            return XCTFail("expected resource fallback text")
        }
        let resourceObject = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(resourceText.utf8)) as? [String: Any])
        XCTAssertEqual(resourceObject["type"] as? String, "resource_link")
        XCTAssertEqual(resourceObject["name"] as? String, "readme")
        XCTAssertEqual(resourceObject["uri"] as? String, "file:///tmp/README.md")
        XCTAssertEqual(resourceObject["mimeType"] as? String, "text/markdown")
    }

    func testMcpCallToolResultUnknownTaggedBlocksBecomeTextWhenImagePresentLikeRust() throws {
        let json = #"""
        {
            "content": [
                {
                    "type": "diagram",
                    "text": "shape-compatible but unknown",
                    "nodes": 3
                },
                {
                    "type": "image",
                    "data": "BASE64",
                    "mimeType": "image/png"
                }
            ]
        }
        """#
        let result = try JSONDecoder().decode(McpCallToolResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.content.first, .unknown(.object([
            "type": .string("diagram"),
            "text": .string("shape-compatible but unknown"),
            "nodes": .integer(3)
        ])))

        let payload = FunctionCallOutputPayload(callToolResult: result)
        XCTAssertEqual(payload.success, true)
        let items = try XCTUnwrap(payload.contentItems)
        XCTAssertEqual(items.count, 2)

        guard case let .inputText(unknownText) = items[0] else {
            return XCTFail("expected unknown block fallback text")
        }
        let unknownObject = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(unknownText.utf8)) as? [String: Any])
        XCTAssertEqual(unknownObject["type"] as? String, "diagram")
        XCTAssertEqual(unknownObject["text"] as? String, "shape-compatible but unknown")
        XCTAssertEqual(unknownObject["nodes"] as? Int, 3)
        XCTAssertEqual(items[1], .inputImage(imageURL: "data:image/png;base64,BASE64", detail: defaultImageDetail))
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
            output: McpCallToolResult(content: [.text(McpTextContent(text: "hello"))])
        )

        let data = try JSONEncoder().encode(item)
        XCTAssertEqual(try JSONDecoder().decode(ResponseInputItem.self, from: data), item)
        let object = try JSONObject(item)
        XCTAssertEqual(object["type"] as? String, "mcp_tool_call_output")
        XCTAssertEqual(object["call_id"] as? String, "call-mcp")
        let output = try XCTUnwrap(object["output"] as? [String: Any])
        let content = try XCTUnwrap(output["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 1)
        XCTAssertEqual(content[0]["type"] as? String, "text")
        XCTAssertEqual(content[0]["text"] as? String, "hello")
        XCTAssertNil(object["result"])
        XCTAssertNil(output["Ok"])
    }

    func testResponseInputItemDecodesMcpToolCallOutputLikeRust() throws {
        let json = #"""
        {
            "type": "mcp_tool_call_output",
            "call_id": "call-mcp",
            "output": {
                "content": [
                    {
                        "type": "text",
                        "text": "hello"
                    }
                ],
                "_meta": {
                    "trace": "kept"
                }
            }
        }
        """#

        let item = try JSONDecoder().decode(ResponseInputItem.self, from: Data(json.utf8))
        XCTAssertEqual(item, .mcpToolCallOutput(
            callID: "call-mcp",
            output: McpCallToolResult(
                content: [.text(McpTextContent(text: "hello"))],
                meta: .object(["trace": .string("kept")])
            )
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

    func testUserInputsBecomeMessageAndSkipToolBodyInputs() throws {
        let item = ResponseInputItem(userInputs: [
            .text("hello"),
            .image(imageURL: "data:image/png;base64,abc"),
            .skill(name: "sample", path: "/tmp/SKILL.md"),
            .mention(name: "drive", path: "app://google_drive")
        ])

        guard case let .message(role, content, _) = item else {
            return XCTFail("expected user message")
        }
        XCTAssertEqual(role, "user")
        XCTAssertEqual(content, [
            .inputText(text: "hello"),
            .inputText(text: "<image>"),
            .inputImage(imageURL: "data:image/png;base64,abc", detail: defaultImageDetail),
            .inputText(text: "</image>")
        ])
    }

    func testMixedRemoteAndLocalImagesShareLabelSequenceLikeRust() throws {
        let temp = try TemporaryDirectory()
        let path = temp.url.appendingPathComponent("local.png")
        _ = try writePNG(width: 1, height: 1, to: path)

        let item = ResponseInputItem(userInputs: [
            .image(imageURL: "data:image/png;base64,remote"),
            .localImage(path: path.path)
        ])

        guard case let .message(_, content, _) = item else {
            return XCTFail("expected user message")
        }

        XCTAssertEqual(content[0], .inputText(text: "<image>"))
        XCTAssertEqual(content[1], .inputImage(imageURL: "data:image/png;base64,remote", detail: defaultImageDetail))
        XCTAssertEqual(content[2], .inputText(text: "</image>"))
        XCTAssertEqual(content[3], .inputText(text: "<image name=[Image #2]>"))
        guard case let .inputImage(_, detail) = content[4] else {
            return XCTFail("expected local image at index 4")
        }
        XCTAssertEqual(detail, defaultImageDetail)
        XCTAssertEqual(content[5], .inputText(text: "</image>"))
    }

    func testLocalImagePNGBecomesDataURLAndKeepsOriginalWhenSmall() throws {
        let temp = try TemporaryDirectory()
        let path = temp.url.appendingPathComponent("small.png")
        let original = try writePNG(width: 64, height: 32, to: path)

        let item = ResponseInputItem(userInputs: [.localImage(path: path.path)])

        guard case let .message(_, content, _) = item,
              case let .inputImage(imageURL, detail) = content.dropFirst().first
        else {
            return XCTFail("expected local image to become an input image")
        }

        XCTAssertEqual(content.first, .inputText(text: "<image name=[Image #1]>"))
        XCTAssertEqual(content.last, .inputText(text: "</image>"))
        XCTAssertEqual(detail, defaultImageDetail)
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

        XCTAssertTrue(text.contains("unsupported image `application/json`"))
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
            "Codex cannot attach image at `\(path.path)`: unsupported image `image/svg+xml`."
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
            "name": "mcp__codex_apps__gmail_get_recent_emails",
            "namespace": "mcp__codex_apps__gmail",
            "arguments": "{\"top_k\":5}",
            "call_id": "call-1"
        }
        """#

        let item = try JSONDecoder().decode(ResponseItem.self, from: Data(json.utf8))
        XCTAssertEqual(
            item,
            .functionCall(
                name: "mcp__codex_apps__gmail_get_recent_emails",
                namespace: "mcp__codex_apps__gmail",
                arguments: #"{"top_k":5}"#,
                callID: "call-1"
            )
        )

        try XCTAssertJSONObjectEqual(item, [
            "type": "function_call",
            "name": "mcp__codex_apps__gmail_get_recent_emails",
            "namespace": "mcp__codex_apps__gmail",
            "arguments": #"{"top_k":5}"#,
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
        XCTAssertEqual(decodedOutput.description, #"[{"type":"input_text","text":"patched"}]"#)
        XCTAssertEqual(itemOutputDescription(item), #"[{"type":"input_text","text":"patched"}]"#)

        try XCTAssertJSONObjectEqual(ResponseItem.customToolCallOutput(callID: "custom-2", output: "done"), [
            "type": "custom_tool_call_output",
            "call_id": "custom-2",
            "output": "done"
        ])
    }

    func testRoundTripsWebSearchCallActions() throws {
        let cases: [(String, ResponseItem, [String: Any])] = [
            (
                #"""
                {
                    "type": "web_search_call",
                    "status": "completed",
                    "action": {
                        "type": "search",
                        "query": "weather seattle",
                        "queries": ["weather seattle", "seattle weather now"]
                    }
                }
                """#,
                .webSearchCall(
                    status: "completed",
                    action: .search(
                        query: "weather seattle",
                        queries: ["weather seattle", "seattle weather now"]
                    )
                ),
                [
                    "type": "web_search_call",
                    "status": "completed",
                    "action": [
                        "type": "search",
                        "query": "weather seattle",
                        "queries": ["weather seattle", "seattle weather now"]
                    ]
                ]
            ),
            (
                #"""
                {
                    "type": "web_search_call",
                    "status": "open",
                    "action": {
                        "type": "open_page",
                        "url": "https://example.com"
                    }
                }
                """#,
                .webSearchCall(status: "open", action: .openPage(url: "https://example.com")),
                [
                    "type": "web_search_call",
                    "status": "open",
                    "action": [
                        "type": "open_page",
                        "url": "https://example.com"
                    ]
                ]
            ),
            (
                #"""
                {
                    "type": "web_search_call",
                    "status": "in_progress",
                    "action": {
                        "type": "find_in_page",
                        "url": "https://example.com/docs",
                        "pattern": "installation"
                    }
                }
                """#,
                .webSearchCall(
                    status: "in_progress",
                    action: .findInPage(url: "https://example.com/docs", pattern: "installation")
                ),
                [
                    "type": "web_search_call",
                    "status": "in_progress",
                    "action": [
                        "type": "find_in_page",
                        "url": "https://example.com/docs",
                        "pattern": "installation"
                    ]
                ]
            ),
            (
                #"""
                {
                    "type": "web_search_call",
                    "status": "in_progress",
                    "id": "ws_partial"
                }
                """#,
                .webSearchCall(id: "ws_partial", status: "in_progress", action: nil),
                [
                    "type": "web_search_call",
                    "status": "in_progress"
                ]
            )
        ]

        for (json, expectedItem, expectedSerialized) in cases {
            let item = try JSONDecoder().decode(ResponseItem.self, from: Data(json.utf8))
            XCTAssertEqual(item, expectedItem)
            try XCTAssertJSONObjectEqual(item, expectedSerialized)
        }
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

    func testDecodesImageGenerationCallWithoutRevisedPromptLikeRust() throws {
        let json = #"""
        {
            "id": "ig_123",
            "type": "image_generation_call",
            "status": "completed",
            "result": "Zm9v"
        }
        """#

        let item = try JSONDecoder().decode(ResponseItem.self, from: Data(json.utf8))
        XCTAssertEqual(item, .imageGenerationCall(
            id: "ig_123",
            status: "completed",
            revisedPrompt: nil,
            result: "Zm9v"
        ))

        try XCTAssertJSONObjectEqual(item, [
            "id": "ig_123",
            "type": "image_generation_call",
            "status": "completed",
            "result": "Zm9v"
        ])
    }

    func testDeserializesLegacyGhostSnapshotAsOtherLikeRust() throws {
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
        XCTAssertEqual(item, .other)
    }

    func testUnknownResponseItemFallsBackToOtherLikeRust() throws {
        let json = #"""
        {
            "type": "future_response_item",
            "payload": "kept by provider"
        }
        """#

        let item = try JSONDecoder().decode(ResponseItem.self, from: Data(json.utf8))
        XCTAssertEqual(item, .other)
    }

    func testKnownResponseItemMalformedPayloadThrowsLikeRustSerde() throws {
        let decoder = JSONDecoder()
        let malformedKnownItems = [
            #"{ "type": "function_call", "name": "search", "arguments": "{}" }"#,
            #"{ "type": "tool_search_call", "execution": "search" }"#,
            #"{ "type": "function_call_output", "call_id": "call-1", "output": { "unexpected": true } }"#,
            #"{ "type": "custom_tool_call", "call_id": "custom-1", "name": "tool" }"#,
            #"{ "type": "tool_search_output", "status": "completed", "execution": "search" }"#,
            #"{ "type": "image_generation_call", "id": "ig_1", "status": "completed" }"#,
        ]

        for json in malformedKnownItems {
            XCTAssertThrowsError(try decoder.decode(ResponseItem.self, from: Data(json.utf8)))
        }
    }

    func testKnownResponseItemNestedUnknownTagsThrowLikeRustSerde() throws {
        let decoder = JSONDecoder()
        let malformedNestedItems = [
            #"""
            {
                "type": "reasoning",
                "summary": [
                    {"type": "future_summary", "text": "Step 1"}
                ]
            }
            """#,
            #"""
            {
                "type": "reasoning",
                "summary": [],
                "content": [
                    {"type": "future_content", "text": "raw details"}
                ]
            }
            """#,
            #"""
            {
                "type": "local_shell_call",
                "status": "completed",
                "action": {
                    "type": "future_action",
                    "command": ["echo", "hi"]
                }
            }
            """#,
        ]

        for json in malformedNestedItems {
            XCTAssertThrowsError(try decoder.decode(ResponseItem.self, from: Data(json.utf8)))
        }
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
            "content": NSNull(),
            "encrypted_content": NSNull()
        ])
    }

    func testRejectsReasoningNullIDLikeRustSerde() throws {
        let json = #"""
        {
            "type": "reasoning",
            "id": null,
            "summary": [
                {"type": "summary_text", "text": "Step 1"}
            ]
        }
        """#

        XCTAssertThrowsError(try JSONDecoder().decode(ResponseItem.self, from: Data(json.utf8)))
    }

    func testResponseItemSerializesRustNullOptionals() throws {
        try XCTAssertJSONObjectEqual(ResponseItem.reasoning(id: "rs_1", summary: []), [
            "type": "reasoning",
            "summary": [],
            "content": NSNull(),
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

    func testShellToolCallParamsRejectsDuplicateTimeoutAliasesLikeRust() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                ShellToolCallParams.self,
                from: Data(#"{"command":["ls"],"workdir":"/tmp","timeout_ms":1000,"timeout":2000}"#.utf8)
            )
        )
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
        XCTAssertEqual(params.additionalPermissions?.fileSystem, FileSystemPermissions(read: ["/repo"]))
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

    func testShellCommandToolCallParamsRejectsDuplicateTimeoutAliasesLikeRust() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                ShellCommandToolCallParams.self,
                from: Data(#"{"command":"git status","workdir":"/repo","timeout_ms":1000,"timeout":2000}"#.utf8)
            )
        )
    }

    func testExecCommandToolCallParamsDecodeApprovalHintsLikeRust() throws {
        let json = #"""
        {
            "cmd": "git push origin main",
            "workdir": "/repo",
            "login": false,
            "tty": true,
            "yield_time_ms": 750,
            "max_output_tokens": 1200,
            "sandbox_permissions": "require_escalated",
            "prefix_rule": ["git", "push"],
            "additional_permissions": {
                "network": {
                    "enabled": true
                }
            },
            "justification": "publish branch"
        }
        """#

        let params = try JSONDecoder().decode(ExecCommandToolCallParams.self, from: Data(json.utf8))
        XCTAssertEqual(params.cmd, "git push origin main")
        XCTAssertEqual(params.workdir, "/repo")
        XCTAssertEqual(params.requestedLogin, false)
        XCTAssertTrue(params.tty)
        XCTAssertEqual(params.yieldTimeMS, 750)
        XCTAssertEqual(params.maxOutputTokens, 1200)
        XCTAssertEqual(params.sandboxPermissions, .requireEscalated)
        XCTAssertEqual(params.prefixRule, ["git", "push"])
        XCTAssertEqual(params.additionalPermissions?.network, RequestPermissionNetworkPermissions(enabled: true))
        XCTAssertEqual(params.justification, "publish branch")
    }

    func testUnifiedExecToolParamsUseRustDefaultsAndRejectNulls() throws {
        let execDefaults = try JSONDecoder().decode(ExecCommandToolCallParams.self, from: Data(#"""
        {
            "cmd": "pwd"
        }
        """#.utf8))
        XCTAssertEqual(execDefaults.login, true)
        XCTAssertEqual(execDefaults.tty, false)
        XCTAssertEqual(execDefaults.yieldTimeMS, 10_000)
        XCTAssertEqual(execDefaults.sandboxPermissions, .useDefault)

        for json in [
            #"{"cmd":"pwd","tty":null}"#,
            #"{"cmd":"pwd","yield_time_ms":null}"#,
            #"{"cmd":"pwd","sandbox_permissions":null}"#
        ] {
            XCTAssertThrowsError(try JSONDecoder().decode(ExecCommandToolCallParams.self, from: Data(json.utf8)))
        }

        let writeDefaults = try JSONDecoder().decode(WriteStdinToolCallParams.self, from: Data(#"""
        {
            "session_id": 7
        }
        """#.utf8))
        XCTAssertEqual(writeDefaults.chars, "")
        XCTAssertEqual(writeDefaults.yieldTimeMS, 250)

        for json in [
            #"{"session_id":7,"chars":null}"#,
            #"{"session_id":7,"yield_time_ms":null}"#
        ] {
            XCTAssertThrowsError(try JSONDecoder().decode(WriteStdinToolCallParams.self, from: Data(json.utf8)))
        }
    }

    func testSandboxPermissionsAdditionalPermissionsWireValueLikeRust() throws {
        let json = #"""
        {
            "command": ["mkdir", "cache"],
            "sandbox_permissions": "with_additional_permissions",
            "additional_permissions": {
                "file_system": {
                    "write": ["/repo/cache"]
                }
            }
        }
        """#

        let params = try JSONDecoder().decode(ShellToolCallParams.self, from: Data(json.utf8))
        XCTAssertEqual(params.sandboxPermissions, .withAdditionalPermissions)
        XCTAssertFalse(params.sandboxPermissions?.requiresEscalatedPermissions ?? true)
        XCTAssertTrue(params.sandboxPermissions?.requestsSandboxOverride ?? false)
        XCTAssertTrue(params.sandboxPermissions?.usesAdditionalPermissions ?? false)
        XCTAssertEqual(params.additionalPermissions?.fileSystem, FileSystemPermissions(write: ["/repo/cache"]))
    }

    func testFileSystemPermissionsCanonicalWireShapeLikeRust() throws {
        let json = #"""
        {
            "entries": [
                {
                    "path": {
                        "type": "glob_pattern",
                        "pattern": "**/*.secret"
                    },
                    "access": "none"
                }
            ],
            "glob_scan_max_depth": 3
        }
        """#

        let permissions = try JSONDecoder().decode(FileSystemPermissions.self, from: Data(json.utf8))
        XCTAssertEqual(
            permissions,
            FileSystemPermissions(
                entries: [
                    FileSystemSandboxEntry(path: .globPattern("**/*.secret"), access: .none)
                ],
                globScanMaxDepth: 3
            )
        )
        XCTAssertNil(permissions.legacyReadWriteRoots)

        try XCTAssertJSONObjectEqual(permissions, [
            "entries": [
                [
                    "path": [
                        "type": "glob_pattern",
                        "pattern": "**/*.secret"
                    ],
                    "access": "none"
                ]
            ],
            "glob_scan_max_depth": 3
        ])

        let missingEntries = try JSONDecoder().decode(FileSystemPermissions.self, from: Data(#"""
        {
            "glob_scan_max_depth": 3
        }
        """#.utf8))
        XCTAssertEqual(missingEntries, FileSystemPermissions(entries: [], globScanMaxDepth: 3))
    }

    func testFileSystemPermissionsRejectsNullCanonicalEntriesLikeRustSerdeDefault() {
        XCTAssertThrowsError(try JSONDecoder().decode(FileSystemPermissions.self, from: Data(#"""
        {
            "entries": null,
            "glob_scan_max_depth": 3
        }
        """#.utf8)))
    }

    func testFileSystemPermissionsLegacyWireShapeLikeRust() throws {
        let permissions = try JSONDecoder().decode(
            FileSystemPermissions.self,
            from: Data(#"{"read":["/repo"],"write":["/repo/Sources"]}"#.utf8)
        )

        XCTAssertEqual(permissions, FileSystemPermissions(read: ["/repo"], write: ["/repo/Sources"]))
        XCTAssertEqual(permissions.legacyReadWriteRoots?.read, ["/repo"])
        XCTAssertEqual(permissions.legacyReadWriteRoots?.write, ["/repo/Sources"])

        try XCTAssertJSONObjectEqual(permissions, [
            "read": ["/repo"],
            "write": ["/repo/Sources"]
        ])
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
        XCTAssertFalse(SandboxPermissions.withAdditionalPermissions.requiresEscalatedPermissions)
        XCTAssertFalse(SandboxPermissions.useDefault.requestsSandboxOverride)
        XCTAssertTrue(SandboxPermissions.requireEscalated.requestsSandboxOverride)
        XCTAssertTrue(SandboxPermissions.withAdditionalPermissions.requestsSandboxOverride)
        XCTAssertFalse(SandboxPermissions.requireEscalated.usesAdditionalPermissions)
        XCTAssertTrue(SandboxPermissions.withAdditionalPermissions.usesAdditionalPermissions)
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

    private func itemOutputDescription(_ item: ResponseItem) -> String? {
        guard case let .customToolCallOutput(_, _, output) = item else {
            return nil
        }
        return output.description
    }
}

private func imageDetailModelInfo(supportsOriginal: Bool) throws -> ModelInfo {
    try JSONDecoder().decode(ModelInfo.self, from: Data("""
    {
      "slug": "test-model",
      "display_name": "Test Model",
      "description": null,
      "supported_reasoning_levels": [],
      "shell_type": "shell_command",
      "visibility": "list",
      "supported_in_api": true,
      "priority": 1,
      "availability_nux": null,
      "upgrade": null,
      "base_instructions": "base",
      "model_messages": null,
      "supports_reasoning_summaries": false,
      "default_reasoning_summary": "auto",
      "support_verbosity": false,
      "default_verbosity": null,
      "apply_patch_tool_type": null,
      "truncation_policy": {
        "mode": "bytes",
        "limit": 10000
      },
      "supports_parallel_tool_calls": false,
      "supports_image_detail_original": \(supportsOriginal),
      "context_window": null,
      "auto_compact_token_limit": null,
      "effective_context_window_percent": 95,
      "experimental_supported_tools": [],
      "input_modalities": ["text", "image"],
      "supports_search_tool": false
    }
    """.utf8))
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
