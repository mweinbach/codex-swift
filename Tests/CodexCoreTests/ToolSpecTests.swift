import CodexCore
import XCTest

final class ToolSpecTests: XCTestCase {
    func testToolConfigEnumsUseRustWireValues() throws {
        XCTAssertEqual(try encode(ConfigShellToolType.unifiedExec), #""unified_exec""#)
        XCTAssertEqual(try encode(ConfigShellToolType.shellCommand), #""shell_command""#)
        XCTAssertEqual(try encode(ApplyPatchToolType.freeform), #""freeform""#)
        XCTAssertEqual(try encode(ApplyPatchToolType.function), #""function""#)
    }

    func testJSONSchemaEncodesSerdeTaggedShape() throws {
        let schema = JSONSchema.object(
            properties: [
                "items": .array(items: .string(description: nil), description: "values"),
                "meta": .object(
                    properties: ["count": .number(description: nil)],
                    required: ["count"],
                    additionalProperties: .boolean(false)
                )
            ],
            required: ["items"],
            additionalProperties: .schema(.string(description: nil))
        )

        let object = try JSONObject(schema)
        XCTAssertEqual(object["type"] as? String, "object")
        XCTAssertEqual(object["required"] as? [String], ["items"])

        let additionalProperties = try XCTUnwrap(object["additionalProperties"] as? [String: Any])
        XCTAssertEqual(additionalProperties["type"] as? String, "string")

        let properties = try XCTUnwrap(object["properties"] as? [String: Any])
        let items = try XCTUnwrap(properties["items"] as? [String: Any])
        XCTAssertEqual(items["type"] as? String, "array")
        XCTAssertEqual(items["description"] as? String, "values")
    }

    func testJSONSchemaDecodesIntegerAsNumber() throws {
        let schema = try JSONDecoder().decode(JSONSchema.self, from: Data(#"{"type":"integer"}"#.utf8))
        XCTAssertEqual(schema, .number(description: nil))
    }

    func testSanitizedSchemaDefaultsMissingTypesAndArrayItems() throws {
        let schema = JSONSchema.sanitized(from: [
            "type": "object",
            "properties": [
                "query": ["description": "search query"],
                "tags": ["type": "array"],
                "limit": ["minimum": 1],
                "mode": ["enum": ["fast", "slow"]]
            ],
            "additionalProperties": [
                "properties": ["label": ["type": "string"]],
                "required": ["label"],
                "additionalProperties": false
            ]
        ])

        XCTAssertEqual(
            schema,
            .object(
                properties: [
                    "query": .string(description: "search query"),
                    "tags": .array(items: .string(description: nil), description: nil),
                    "limit": .number(description: nil),
                    "mode": .string(description: nil)
                ],
                required: nil,
                additionalProperties: .schema(
                    .object(
                        properties: ["label": .string(description: nil)],
                        required: ["label"],
                        additionalProperties: .boolean(false)
                    )
                )
            )
        )
    }

    func testResponsesToolJSONShapeMatchesRustSerde() throws {
        let tool = ToolSpecFactory.createViewImageTool()
        let object = try JSONObject(tool)

        XCTAssertEqual(object["type"] as? String, "function")
        XCTAssertEqual(object["name"] as? String, "view_image")
        XCTAssertEqual(object["strict"] as? Bool, false)

        let parameters = try XCTUnwrap(object["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["type"] as? String, "object")
        XCTAssertEqual(parameters["required"] as? [String], ["path"])
        XCTAssertEqual(parameters["additionalProperties"] as? Bool, false)
    }

    func testFreeformApplyPatchToolShapeIncludesGrammar() throws {
        let tool = ToolSpecFactory.createApplyPatchFreeformTool()
        let object = try JSONObject(tool)

        XCTAssertEqual(object["type"] as? String, "custom")
        XCTAssertEqual(object["name"] as? String, "apply_patch")

        let format = try XCTUnwrap(object["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "grammar")
        XCTAssertEqual(format["syntax"] as? String, "lark")
        XCTAssertTrue((format["definition"] as? String)?.contains("start: begin_patch hunk+ end_patch") == true)
    }

    func testBuildSpecsUsesRustOrderAndParallelFlags() {
        let specs = ToolSpecFactory.buildSpecs(
            config: ToolsConfig(
                shellType: .unifiedExec,
                applyPatchToolType: .freeform,
                webSearchRequest: true,
                includeViewImageTool: true,
                includeComputerUseTools: true,
                experimentalSupportedTools: ["grep_files", "read_file", "list_dir", "test_sync_tool"]
            )
        )

        XCTAssertEqual(specs.map { $0.spec.name }, [
            "exec_command",
            "write_stdin",
            "list_mcp_resources",
            "list_mcp_resource_templates",
            "read_mcp_resource",
            "update_plan",
            "apply_patch",
            "grep_files",
            "read_file",
            "list_dir",
            "test_sync_tool",
            "web_search",
            "view_image",
            "computer_screenshot",
            "computer_click",
            "computer_drag",
            "computer_scroll",
            "computer_type",
            "computer_key"
        ])

        let parallelSpecs = Dictionary(uniqueKeysWithValues: specs.map { ($0.spec.name, $0.supportsParallelToolCalls) })
        XCTAssertEqual(parallelSpecs["exec_command"], false)
        XCTAssertEqual(parallelSpecs["grep_files"], true)
        XCTAssertEqual(parallelSpecs["view_image"], true)
        XCTAssertEqual(parallelSpecs["computer_key"], true)
    }

    func testChatCompletionsJSONWrapsFunctionToolsOnly() throws {
        let tools: [ToolSpec] = [
            ToolSpecFactory.createViewImageTool(),
            .webSearch,
            ToolSpecFactory.createApplyPatchFreeformTool()
        ]
        let chatTools = try ToolSpecFactory.createToolsJSONForChatCompletionsAPI(tools)
        XCTAssertEqual(chatTools.count, 1)

        let object = try XCTUnwrap(chatTools.first as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "function")
        XCTAssertEqual(object["name"] as? String, "view_image")

        let function = try XCTUnwrap(object["function"] as? [String: Any])
        XCTAssertEqual(function["name"] as? String, "view_image")
        XCTAssertNil(function["type"])
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        String(data: try JSONEncoder().encode(value), encoding: .utf8)!
    }
}
