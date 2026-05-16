import XCTest
@testable import CodexCore

final class CodeModeTests: XCTestCase {
    func testParseExecSourceWithoutPragma() {
        XCTAssertEqual(
            CodeMode.parseExecSource("text('hi')").successValue,
            ParsedExecSource(code: "text('hi')")
        )
    }

    func testParseExecSourceWithPragma() {
        XCTAssertEqual(
            CodeMode.parseExecSource("// @exec: {\"yield_time_ms\": 10}\ntext('hi')").successValue,
            ParsedExecSource(code: "text('hi')", yieldTimeMS: 10)
        )
    }

    func testParseExecSourceAllowsEmptyPragmaObject() {
        XCTAssertEqual(
            CodeMode.parseExecSource("// @exec: {}\ntext('hi')").successValue,
            ParsedExecSource(code: "text('hi')")
        )
    }

    func testParseExecSourceRejectsEmptyInput() {
        XCTAssertEqual(
            CodeMode.parseExecSource(" \n\t").failureValue,
            "exec expects raw JavaScript source text (non-empty). Provide JS only, optionally with first-line `// @exec: {\"yield_time_ms\": 10000, \"max_output_tokens\": 1000}`."
        )
    }

    func testParseExecSourceRejectsPragmaWithoutCode() {
        XCTAssertEqual(
            CodeMode.parseExecSource("// @exec: {\"yield_time_ms\": 10}\n   ").failureValue,
            "exec pragma must be followed by JavaScript source on subsequent lines"
        )
    }

    func testParseExecSourceRejectsUnsupportedPragmaFields() {
        XCTAssertEqual(
            CodeMode.parseExecSource("// @exec: {\"foo\": 1}\ntext('hi')").failureValue,
            "exec pragma only supports `yield_time_ms` and `max_output_tokens`; got `foo`"
        )
    }

    func testParseExecSourceRejectsUnsafeIntegers() {
        XCTAssertEqual(
            CodeMode.parseExecSource("// @exec: {\"yield_time_ms\": 9007199254740992}\ntext('hi')").failureValue,
            "exec pragma field `yield_time_ms` must be a non-negative safe integer"
        )
        XCTAssertEqual(
            CodeMode.parseExecSource("// @exec: {\"max_output_tokens\": -1}\ntext('hi')").failureValue,
            "exec pragma field `max_output_tokens` must be a non-negative safe integer"
        )
        XCTAssertEqual(
            CodeMode.parseExecSource("// @exec: {\"yield_time_ms\": true}\ntext('hi')").failureValue,
            "exec pragma field `yield_time_ms` must be a non-negative safe integer"
        )
    }

    func testNormalizeIdentifierRewritesInvalidCharacters() {
        XCTAssertEqual(
            CodeMode.normalizeCodeModeIdentifier("mcp__ologs__get_profile"),
            "mcp__ologs__get_profile"
        )
        XCTAssertEqual(
            CodeMode.normalizeCodeModeIdentifier("hidden-dynamic-tool"),
            "hidden_dynamic_tool"
        )
        XCTAssertEqual(
            CodeMode.normalizeCodeModeIdentifier("123 abc"),
            "_23_abc"
        )
        XCTAssertEqual(CodeMode.normalizeCodeModeIdentifier(""), "_")
    }

    func testIsCodeModeNestedToolSkipsPublicTools() {
        XCTAssertFalse(CodeMode.isCodeModeNestedTool("exec"))
        XCTAssertFalse(CodeMode.isCodeModeNestedTool("wait"))
        XCTAssertTrue(CodeMode.isCodeModeNestedTool("mcp__server__tool"))
    }

    func testResponseInputToCodeModeResultJoinsTextAndImagesLikeRustToolContext() {
        let response = ResponseInputItem.message(
            role: "user",
            content: [
                .inputText(text: "line 1"),
                .inputImage(imageURL: "data:image/png;base64,AAA"),
                .outputText(text: "line 2"),
                .inputText(text: "   ")
            ]
        )

        XCTAssertEqual(
            CodeMode.responseInputToCodeModeResult(response),
            .string("line 1\ndata:image/png;base64,AAA\nline 2")
        )
    }

    func testResponseInputToCodeModeResultUsesFunctionAndCustomOutputBodiesLikeRustToolContext() {
        let contentItems: [FunctionCallOutputContentItem] = [
            .inputText(text: "line 1"),
            .inputImage(imageURL: "data:image/png;base64,AAA"),
            .inputText(text: "line 2")
        ]

        XCTAssertEqual(
            CodeMode.responseInputToCodeModeResult(.functionCallOutput(
                callID: "call-1",
                output: FunctionCallOutputPayload(content: "ignored", contentItems: contentItems)
            )),
            .string("line 1\ndata:image/png;base64,AAA\nline 2")
        )
        XCTAssertEqual(
            CodeMode.responseInputToCodeModeResult(.customToolCallOutput(
                callID: "custom-1",
                output: FunctionCallOutputPayload(content: "plain")
            )),
            .string("plain")
        )
    }

    func testResponseInputToCodeModeResultKeepsToolSearchArrayLikeRustToolContext() {
        let tools: [JSONValue] = [
            .object([
                "type": .string("function"),
                "name": .string("create_event")
            ])
        ]

        XCTAssertEqual(
            CodeMode.responseInputToCodeModeResult(.toolSearchOutput(
                callID: "search-1",
                status: "completed",
                execution: "client",
                tools: tools
            )),
            .array(tools)
        )
    }

    func testResponseInputToCodeModeResultSerializesRawMcpCallToolResultLikeRustToolContext() {
        let result = McpCallToolResult(
            content: [.text(McpTextContent(text: "ignored"))],
            isError: false,
            structuredContent: .object([
                "threadId": .string("thread_123"),
                "content": .string("done")
            ]),
            meta: .object(["source": .string("mcp")])
        )

        XCTAssertEqual(
            CodeMode.responseInputToCodeModeResult(.mcpToolCallOutput(
                callID: "mcp-1",
                output: result
            )),
            .object([
                "_meta": .object(["source": .string("mcp")]),
                "content": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string("ignored")
                    ])
                ]),
                "isError": .bool(false),
                "structuredContent": .object([
                    "content": .string("done"),
                    "threadId": .string("thread_123")
                ])
            ])
        )
    }
}

private extension Result where Success == ParsedExecSource, Failure == CodeModeParseError {
    var successValue: ParsedExecSource? {
        guard case let .success(value) = self else {
            return nil
        }
        return value
    }

    var failureValue: String? {
        guard case let .failure(value) = self else {
            return nil
        }
        return value.description
    }
}
