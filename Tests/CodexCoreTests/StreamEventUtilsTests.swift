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

    func testHandleNonToolResponseItemSavesImageGenerationResult() throws {
        let codexHome = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: codexHome) }

        let item = ResponseItem.imageGenerationCall(
            id: "../ig/..",
            status: "completed",
            revisedPrompt: "A tiny blue square",
            result: "Zm9v"
        )

        let expectedPath = try StreamEventUtils.imageGenerationArtifactPath(
            codexHome: codexHome,
            sessionID: "session-1",
            callID: "../ig/.."
        )
        let turnItem = StreamEventUtils.handleNonToolResponseItem(
            item,
            codexHome: codexHome,
            sessionID: "session-1"
        )

        XCTAssertEqual(turnItem, .imageGeneration(ImageGenerationItem(
            id: "../ig/..",
            status: "completed",
            revisedPrompt: "A tiny blue square",
            result: "Zm9v",
            savedPath: expectedPath
        )))
        XCTAssertEqual(
            try Data(contentsOf: URL(fileURLWithPath: expectedPath.path)),
            Data("foo".utf8)
        )
        XCTAssertTrue(expectedPath.path.hasSuffix("/generated_images/session-1/___ig___.png"))
    }

    func testSaveImageGenerationResultRejectsNonStandardBase64() throws {
        let codexHome = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: codexHome) }

        XCTAssertThrowsError(try StreamEventUtils.saveImageGenerationResult(
            codexHome: codexHome,
            sessionID: "session-1",
            callID: "ig_urlsafe",
            result: "_-8"
        )) { error in
            XCTAssertEqual(error as? ImageGenerationArtifactError, .invalidPayload)
        }
    }

    func testSaveImageGenerationResultRejectsDataURLPayloads() throws {
        let codexHome = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: codexHome) }

        XCTAssertThrowsError(try StreamEventUtils.saveImageGenerationResult(
            codexHome: codexHome,
            sessionID: "session-1",
            callID: "ig_456",
            result: "data:image/jpeg;base64,Zm9v"
        )) { error in
            XCTAssertEqual(error as? ImageGenerationArtifactError, .invalidPayload)
        }

        XCTAssertThrowsError(try StreamEventUtils.saveImageGenerationResult(
            codexHome: codexHome,
            sessionID: "session-1",
            callID: "ig_svg",
            result: "data:image/svg+xml,<svg/>"
        )) { error in
            XCTAssertEqual(error as? ImageGenerationArtifactError, .invalidPayload)
        }
    }

    func testSaveImageGenerationResultOverwritesExistingFile() throws {
        let codexHome = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: codexHome) }
        let expectedPath = try StreamEventUtils.imageGenerationArtifactPath(
            codexHome: codexHome,
            sessionID: "session-1",
            callID: "ig_overwrite"
        )
        let expectedURL = URL(fileURLWithPath: expectedPath.path)
        try FileManager.default.createDirectory(
            at: expectedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("existing".utf8).write(to: expectedURL)

        let savedPath = try StreamEventUtils.saveImageGenerationResult(
            codexHome: codexHome,
            sessionID: "session-1",
            callID: "ig_overwrite",
            result: "Zm9v"
        )

        XCTAssertEqual(savedPath, expectedPath)
        XCTAssertEqual(try Data(contentsOf: expectedURL), Data("foo".utf8))
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
