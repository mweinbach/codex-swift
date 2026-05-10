import CodexCore
import XCTest

final class ToolSpecTests: XCTestCase {
    func testToolConfigEnumsUseRustWireValues() throws {
        XCTAssertEqual(try encode(ConfigShellToolType.unifiedExec), #""unified_exec""#)
        XCTAssertEqual(try encode(ConfigShellToolType.shellCommand), #""shell_command""#)
        XCTAssertEqual(try encode(ApplyPatchToolType.freeform), #""freeform""#)
        XCTAssertThrowsError(
            try JSONDecoder().decode(ApplyPatchToolType.self, from: Data(#""function""#.utf8))
        )
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

    func testNamespaceToolSpecSerializesExpectedWireShape() throws {
        let spec = ToolSpec.namespace(
            ResponsesAPINamespace(
                name: "mcp__demo__",
                description: "Demo tools",
                tools: [
                    .function(
                        ResponsesAPITool(
                            name: "lookup_order",
                            description: "Look up an order",
                            strict: false,
                            parameters: .object(
                                properties: [
                                    "order_id": .string(description: nil)
                                ],
                                required: nil,
                                additionalProperties: nil
                            )
                        )
                    )
                ]
            )
        )

        try XCTAssertJSONObjectEqual(spec, [
            "type": "namespace",
            "name": "mcp__demo__",
            "description": "Demo tools",
            "tools": [
                [
                    "type": "function",
                    "name": "lookup_order",
                    "description": "Look up an order",
                    "strict": false,
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "order_id": ["type": "string"]
                        ]
                    ]
                ]
            ]
        ])
    }

    func testWebSearchToolSpecSerializesExpectedWireShape() throws {
        let spec = ToolSpec.webSearch(
            externalWebAccess: true,
            filters: ResponsesAPIWebSearchFilters(allowedDomains: ["example.com"]),
            userLocation: ResponsesAPIWebSearchUserLocation(
                country: "US",
                region: "California",
                city: "San Francisco",
                timezone: "America/Los_Angeles"
            ),
            searchContextSize: .high,
            searchContentTypes: ["text", "image"]
        )

        try XCTAssertJSONObjectEqual(spec, [
            "type": "web_search",
            "external_web_access": true,
            "filters": [
                "allowed_domains": ["example.com"]
            ],
            "user_location": [
                "type": "approximate",
                "country": "US",
                "region": "California",
                "city": "San Francisco",
                "timezone": "America/Los_Angeles"
            ],
            "search_context_size": "high",
            "search_content_types": ["text", "image"]
        ])
    }

    func testToolSearchToolSpecSerializesExpectedWireShape() throws {
        let spec = ToolSpec.toolSearch(
            execution: "sync",
            description: "Search app tools",
            parameters: .object(
                properties: [
                    "query": .string(description: "Tool search query")
                ],
                required: ["query"],
                additionalProperties: .boolean(false)
            )
        )

        try XCTAssertJSONObjectEqual(spec, [
            "type": "tool_search",
            "execution": "sync",
            "description": "Search app tools",
            "parameters": [
                "type": "object",
                "properties": [
                    "query": [
                        "type": "string",
                        "description": "Tool search query"
                    ]
                ],
                "required": ["query"],
                "additionalProperties": false
            ]
        ])
    }

    func testToolSearchToolFactoryMatchesRustDescriptionAndSchema() {
        let index = ToolSearchIndex(
            entries: [],
            sourceInfos: [
                ToolSearchSourceInfo(
                    name: "Google Drive",
                    description: "Use Google Drive as the single entrypoint for Drive, Docs, Sheets, and Slides work."
                ),
                ToolSearchSourceInfo(name: "Google Drive"),
                ToolSearchSourceInfo(name: "docs")
            ]
        )

        XCTAssertEqual(
            index.toolSpec(),
            .toolSearch(
                execution: "client",
                description: "# Tool discovery\n\nSearches over deferred tool metadata with BM25 and exposes matching tools for the next model call.\n\nYou have access to tools from the following sources:\n- Google Drive: Use Google Drive as the single entrypoint for Drive, Docs, Sheets, and Slides work.\n- docs\nSome of the tools may not have been provided to you upfront, and you should use this tool (`tool_search`) to search for the required tools. For MCP tool discovery, always use `tool_search` instead of `list_mcp_resources` or `list_mcp_resource_templates`.",
                parameters: .object(
                    properties: [
                        "limit": .number(description: "Maximum number of tools to return (defaults to 8)."),
                        "query": .string(description: "Search query for deferred tools.")
                    ],
                    required: ["query"],
                    additionalProperties: .boolean(false)
                )
            )
        )
    }

    func testImageGenerationToolSpecSerializesExpectedWireShape() throws {
        try XCTAssertJSONObjectEqual(ToolSpec.imageGeneration(outputFormat: "png"), [
            "type": "image_generation",
            "output_format": "png"
        ])
    }

    func testToolSpecNameCoversHostedVariantsLikeRust() {
        XCTAssertEqual(
            ToolSpec.toolSearch(
                execution: "sync",
                description: "Search",
                parameters: .object(properties: [:], required: nil, additionalProperties: nil)
            ).name,
            "tool_search"
        )
        XCTAssertEqual(ToolSpec.imageGeneration(outputFormat: "png").name, "image_generation")
        XCTAssertEqual(ToolSpec.webSearch(externalWebAccess: true).name, "web_search")
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

    func testWebSearchModeControlsExternalWebAccessLikeRust() throws {
        let live = ToolSpecFactory.buildSpecs(config: ToolsConfig(shellType: .disabled, webSearchMode: .live))
        XCTAssertEqual(webSearchSpecs(in: live), [.webSearch(externalWebAccess: true)])

        let cached = ToolSpecFactory.buildSpecs(config: ToolsConfig(shellType: .disabled, webSearchMode: .cached))
        XCTAssertEqual(webSearchSpecs(in: cached), [.webSearch(externalWebAccess: false)])

        let disabled = ToolSpecFactory.buildSpecs(config: ToolsConfig(
            shellType: .disabled,
            webSearchMode: .disabled,
            webSearchRequest: true
        ))
        XCTAssertEqual(webSearchSpecs(in: disabled), [])
    }

    func testWebSearchConfigIsForwardedToToolSpecLikeRust() throws {
        let specs = ToolSpecFactory.buildSpecs(config: ToolsConfig(
            shellType: .disabled,
            webSearchMode: .live,
            webSearchConfig: WebSearchConfig(
                filters: ResponsesAPIWebSearchFilters(allowedDomains: ["example.com"]),
                userLocation: ResponsesAPIWebSearchUserLocation(
                    country: "US",
                    region: "California",
                    city: "San Francisco",
                    timezone: "America/Los_Angeles"
                ),
                searchContextSize: .high
            )
        ))

        XCTAssertEqual(webSearchSpecs(in: specs), [
            .webSearch(
                externalWebAccess: true,
                filters: ResponsesAPIWebSearchFilters(allowedDomains: ["example.com"]),
                userLocation: ResponsesAPIWebSearchUserLocation(
                    country: "US",
                    region: "California",
                    city: "San Francisco",
                    timezone: "America/Los_Angeles"
                ),
                searchContextSize: .high
            )
        ])
    }

    private func webSearchSpecs(in specs: [ConfiguredToolSpec]) -> [ToolSpec] {
        specs.map(\.spec).filter { $0.name == "web_search" }
    }

    func testBuildSpecsAppendsMCPToolsAsSortedNamespaceLikeRust() throws {
        let specs = ToolSpecFactory.buildSpecs(
            config: ToolsConfig(
                shellType: .disabled,
                applyPatchToolType: nil,
                includeViewImageTool: false
            ),
            mcpTools: [
                "mcp__test_server__something": makeMcpTool(name: "something"),
                "mcp__test_server__cool": makeMcpTool(name: "cool"),
                "mcp__test_server__do": makeMcpTool(name: "do")
            ]
        )

        let mcpSpec = try XCTUnwrap(specs.first { $0.spec.name == "mcp__test_server__" })
        XCTAssertFalse(mcpSpec.supportsParallelToolCalls)

        guard case let .namespace(namespace) = mcpSpec.spec else {
            return XCTFail("Expected MCP tools to be exposed as a namespace")
        }

        XCTAssertEqual(namespace.name, "mcp__test_server__")
        XCTAssertEqual(namespace.description, "Tools in the mcp__test_server__ namespace.")
        XCTAssertEqual(namespace.tools.map(namespaceToolName), [
            "cool",
            "do",
            "something"
        ])
    }

    func testToolSearchIndexReturnsCoalescedDeferredMCPNamespace() throws {
        let index = ToolSearchIndex.mcpIndex(from: [
            "mcp__calendar__create_event": makeMcpTool(name: "create_event", description: "Create events"),
            "mcp__calendar__list_events": makeMcpTool(name: "list_events", description: "List events")
        ])

        let tools = try index.search(arguments: .object([
            "query": .string("calendar events"),
            "limit": .integer(8)
        ]))

        XCTAssertEqual(tools.count, 1)
        guard case let .object(namespace) = tools[0],
              case let .array(children)? = namespace["tools"]
        else {
            return XCTFail("expected namespace result")
        }
        XCTAssertEqual(namespace["type"], .string("namespace"))
        XCTAssertEqual(namespace["name"], .string("mcp__calendar__"))
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual(Set(children.compactMap(toolName)), Set(["create_event", "list_events"]))
        XCTAssertEqual(children.compactMap(deferLoading), [true, true])
    }

    func testToolSearchIndexRejectsEmptyQueryAndZeroLimitLikeRust() throws {
        let index = ToolSearchIndex.mcpIndex(from: [
            "mcp__calendar__create_event": makeMcpTool(name: "create_event")
        ])

        XCTAssertThrowsError(try index.search(arguments: .object(["query": .string(" ")]))) { error in
            XCTAssertEqual(error as? ToolSearchError, .emptyQuery)
        }
        XCTAssertThrowsError(try index.search(arguments: .object([
            "query": .string("calendar"),
            "limit": .integer(0)
        ]))) { error in
            XCTAssertEqual(error as? ToolSearchError, .invalidLimit)
        }
    }

    func testBuildSpecsHidesMCPNamespaceSpecsWhenNamespaceToolsDisabled() {
        let specs = ToolSpecFactory.buildSpecs(
            config: ToolsConfig(
                shellType: .disabled,
                applyPatchToolType: nil,
                includeViewImageTool: false,
                namespaceTools: false
            ),
            mcpTools: [
                "mcp__test_server__do": makeMcpTool(name: "do")
            ]
        )

        XCTAssertFalse(specs.contains { $0.spec.name == "mcp__test_server__" })
    }

    func testChatCompletionsJSONWrapsFunctionToolsOnly() throws {
        let tools: [ToolSpec] = [
            ToolSpecFactory.createViewImageTool(),
            .webSearch(),
            .toolSearch(
                execution: "client",
                description: "Search tools",
                parameters: .object(properties: [:], required: nil, additionalProperties: nil)
            ),
            .imageGeneration(outputFormat: "png"),
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

    func testMCPToolConversionDefaultsDescriptionAndObjectPropertiesLikeRust() throws {
        let spec = ToolSpecFactory.createMCPTool(
            fullyQualifiedName: "mcp__docs__search",
            tool: McpTool(name: "search", inputSchema: McpToolInputSchema())
        )

        let object = try JSONObject(spec)
        XCTAssertEqual(object["type"] as? String, "function")
        XCTAssertEqual(object["name"] as? String, "mcp__docs__search")
        XCTAssertEqual(object["description"] as? String, "")
        XCTAssertEqual(object["strict"] as? Bool, false)

        let parameters = try XCTUnwrap(object["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["type"] as? String, "object")
        XCTAssertEqual((parameters["properties"] as? [String: Any])?.isEmpty, true)
    }

    func testMCPToolConversionSanitizesSchemaLikeRust() throws {
        let spec = ToolSpecFactory.createMCPTool(
            fullyQualifiedName: "mcp__docs__lookup",
            tool: McpTool(
                name: "lookup",
                inputSchema: McpToolInputSchema(
                    properties: .object([
                        "count": .object(["type": .string("integer")]),
                        "tags": .object(["type": .string("array")]),
                        "mode": .object(["enum": .array([.string("fast"), .string("slow")])])
                    ]),
                    required: ["count"],
                    type: "object"
                ),
                description: "Look up docs"
            )
        )

        XCTAssertEqual(
            spec,
            .function(
                ResponsesAPITool(
                    name: "mcp__docs__lookup",
                    description: "Look up docs",
                    strict: false,
                    parameters: .object(
                        properties: [
                            "count": .number(description: nil),
                            "tags": .array(items: .string(description: nil), description: nil),
                            "mode": .string(description: nil)
                        ],
                        required: ["count"],
                        additionalProperties: nil
                    )
                )
            )
        )
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        String(data: try JSONEncoder().encode(value), encoding: .utf8)!
    }

    private func makeMcpTool(name: String, description: String? = nil) -> McpTool {
        McpTool(name: name, inputSchema: McpToolInputSchema(), description: description)
    }

    private func namespaceToolName(_ tool: ResponsesAPINamespaceTool) -> String {
        switch tool {
        case let .function(function):
            return function.name
        }
    }

    private func toolName(_ value: JSONValue) -> String? {
        guard case let .object(tool) = value,
              case let .string(name)? = tool["name"]
        else {
            return nil
        }
        return name
    }

    private func deferLoading(_ value: JSONValue) -> Bool? {
        guard case let .object(tool) = value,
              case let .bool(deferLoading)? = tool["defer_loading"]
        else {
            return nil
        }
        return deferLoading
    }
}
