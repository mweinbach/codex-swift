import CodexCore
import XCTest

final class McpEventsTests: XCTestCase {
    func testStartupStatusUsesRustInternallyTaggedStateShape() throws {
        try XCTAssertJSONObjectEqual(McpStartupStatus.starting, [
            "state": "starting"
        ])
        try XCTAssertJSONObjectEqual(McpStartupStatus.ready, [
            "state": "ready"
        ])
        try XCTAssertJSONObjectEqual(McpStartupStatus.failed(error: "boom"), [
            "state": "failed",
            "error": "boom"
        ])
        try XCTAssertJSONObjectEqual(McpStartupStatus.cancelled, [
            "state": "cancelled"
        ])

        let data = try JSONEncoder().encode(McpStartupStatus.failed(error: "boom"))
        XCTAssertEqual(try JSONDecoder().decode(McpStartupStatus.self, from: data), .failed(error: "boom"))
    }

    func testStartupUpdateEventWireShape() throws {
        try XCTAssertJSONObjectEqual(McpStartupUpdateEvent(
            server: "srv",
            status: .failed(error: "boom")
        ), [
            "server": "srv",
            "status": [
                "state": "failed",
                "error": "boom"
            ]
        ])
    }

    func testStartupCompleteEventWireShapeAndDefault() throws {
        let event = McpStartupCompleteEvent(
            ready: ["a"],
            failed: [McpStartupFailure(server: "b", error: "bad")],
            cancelled: ["c"]
        )

        try XCTAssertJSONObjectEqual(event, [
            "ready": ["a"],
            "failed": [
                [
                    "server": "b",
                    "error": "bad"
                ]
            ],
            "cancelled": ["c"]
        ])

        try XCTAssertJSONObjectEqual(McpStartupCompleteEvent(), [
            "ready": [],
            "failed": [],
            "cancelled": []
        ])
    }

    func testMcpToolMetadataRoundTripsRustToolInfoFields() throws {
        let tool = McpTool(
            name: "calendar_create_event",
            inputSchema: McpToolInputSchema(),
            connectorID: "calendar",
            connectorName: "Calendar",
            description: "Create an event",
            namespaceDescription: "Plan events",
            pluginDisplayNames: ["calendar-plugin"],
            title: "Create Event"
        )

        try XCTAssertJSONObjectEqual(tool, [
            "connector_id": "calendar",
            "connector_name": "Calendar",
            "description": "Create an event",
            "inputSchema": [
                "type": "object"
            ],
            "name": "calendar_create_event",
            "namespace_description": "Plan events",
            "plugin_display_names": ["calendar-plugin"],
            "title": "Create Event"
        ])

        let decoded = try JSONDecoder().decode(McpTool.self, from: Data("""
        {
          "connector_id": "calendar",
          "connector_name": "Calendar",
          "description": "Create an event",
          "inputSchema": {"type": "object"},
          "name": "calendar_create_event",
          "namespace_description": "Plan events",
          "plugin_display_names": ["calendar-plugin"],
          "title": "Create Event"
        }
        """.utf8))
        XCTAssertEqual(decoded, tool)
    }

    func testMcpToolDecodesRustSnakeCaseSchemaAliases() throws {
        let decoded = try JSONDecoder().decode(McpTool.self, from: Data("""
        {
          "name": "search",
          "input_schema": {
            "properties": {
              "query": {
                "type": "string"
              }
            },
            "required": ["query"]
          },
          "output_schema": {
            "properties": {
              "results": {
                "type": "array"
              }
            }
          }
        }
        """.utf8))

        XCTAssertEqual(decoded.name, "search")
        XCTAssertEqual(decoded.inputSchema.required, ["query"])
        XCTAssertEqual(decoded.outputSchema?.properties, .object([
            "results": .object([
                "type": .string("array")
            ])
        ]))
    }

    func testMcpToolRejectsDuplicateRustSchemaAliases() throws {
        XCTAssertThrowsError(try JSONDecoder().decode(McpTool.self, from: Data("""
        {
          "name": "search",
          "inputSchema": {"type": "object"},
          "input_schema": {"type": "object"}
        }
        """.utf8)))

        XCTAssertThrowsError(try JSONDecoder().decode(McpTool.self, from: Data("""
        {
          "name": "search",
          "outputSchema": {"type": "object"},
          "output_schema": null
        }
        """.utf8)))
    }

    func testMcpToolDefaultsMissingPluginDisplayNamesLikeRustSerdeDefault() throws {
        let decoded = try JSONDecoder().decode(McpTool.self, from: Data("""
        {
          "name": "search",
          "inputSchema": {"type": "object"}
        }
        """.utf8))

        XCTAssertEqual(decoded.pluginDisplayNames, [])
    }

    func testMcpToolRejectsNullPluginDisplayNamesLikeRustSerdeDefault() throws {
        XCTAssertThrowsError(try JSONDecoder().decode(McpTool.self, from: Data("""
        {
          "name": "search",
          "inputSchema": {"type": "object"},
          "plugin_display_names": null
        }
        """.utf8)))
    }

    func testMcpToolDefaultsMissingInputSchemaLikeRustSerdeDefault() throws {
        let omitted = try JSONDecoder().decode(McpTool.self, from: Data("""
        {
          "name": "search"
        }
        """.utf8))
        XCTAssertEqual(omitted.inputSchema, McpToolInputSchema(rawValue: .null))

        let explicitNull = try JSONDecoder().decode(McpTool.self, from: Data("""
        {
          "name": "search",
          "inputSchema": null
        }
        """.utf8))
        XCTAssertEqual(explicitNull.inputSchema, McpToolInputSchema(rawValue: .null))

        try XCTAssertJSONObjectEqual(explicitNull, [
            "inputSchema": NSNull(),
            "name": "search"
        ])
    }

    func testMcpToolInputSchemaPreservesArbitraryRustJsonSchema() throws {
        let decoded = try JSONDecoder().decode(McpTool.self, from: Data("""
        {
          "name": "search",
          "inputSchema": {
            "type": "object",
            "properties": {
              "query": {
                "type": "string",
                "description": "Search query"
              }
            },
            "additionalProperties": false,
            "x-custom": {
              "rank": 7
            }
          }
        }
        """.utf8))

        XCTAssertEqual(decoded.inputSchema.type, "object")
        XCTAssertEqual(decoded.inputSchema.properties, .object([
            "query": .object([
                "description": .string("Search query"),
                "type": .string("string")
            ])
        ]))
        try XCTAssertJSONObjectEqual(decoded, [
            "inputSchema": [
                "additionalProperties": false,
                "properties": [
                    "query": [
                        "description": "Search query",
                        "type": "string"
                    ]
                ],
                "type": "object",
                "x-custom": [
                    "rank": 7
                ]
            ],
            "name": "search"
        ])
    }

    func testMcpToolOutputSchemaPreservesArbitraryRustJsonSchemaWithoutInferredType() throws {
        let decoded = try JSONDecoder().decode(McpTool.self, from: Data("""
        {
          "name": "classify",
          "inputSchema": {
            "type": "object"
          },
          "outputSchema": {
            "enum": ["ok", "error"],
            "x-custom": {
              "rank": 3
            }
          }
        }
        """.utf8))

        XCTAssertEqual(decoded.outputSchema?.type, "object")
        XCTAssertEqual(decoded.outputSchema?.rawValue, .object([
            "enum": .array([.string("ok"), .string("error")]),
            "x-custom": .object(["rank": .integer(3)])
        ]))
        try XCTAssertJSONObjectEqual(decoded, [
            "inputSchema": [
                "type": "object"
            ],
            "name": "classify",
            "outputSchema": [
                "enum": ["ok", "error"],
                "x-custom": [
                    "rank": 3
                ]
            ]
        ])
    }

    func testMcpToolPreservesRustIconsAndMetaFields() throws {
        let decoded = try JSONDecoder().decode(McpTool.self, from: Data("""
        {
          "name": "search",
          "inputSchema": {"type": "object"},
          "icons": [
            {
              "src": "https://example.test/icon.png",
              "mimeType": "image/png"
            }
          ],
          "_meta": {
            "openai/outputTemplate": "ui://widget/search.html",
            "openai/toolInvocation/invoking": "Searching"
          }
        }
        """.utf8))

        XCTAssertEqual(decoded.icons, [
            .object([
                "src": .string("https://example.test/icon.png"),
                "mimeType": .string("image/png")
            ])
        ])
        XCTAssertEqual(decoded.meta, .object([
            "openai/outputTemplate": .string("ui://widget/search.html"),
            "openai/toolInvocation/invoking": .string("Searching")
        ]))

        try XCTAssertJSONObjectEqual(decoded, [
            "_meta": [
                "openai/outputTemplate": "ui://widget/search.html",
                "openai/toolInvocation/invoking": "Searching"
            ],
            "icons": [
                [
                    "src": "https://example.test/icon.png",
                    "mimeType": "image/png"
                ]
            ],
            "inputSchema": [
                "type": "object"
            ],
            "name": "search"
        ])
    }

    func testMcpToolAnnotationsPreserveUnknownRustJsonMembers() throws {
        let decoded = try JSONDecoder().decode(McpTool.self, from: Data("""
        {
          "name": "search",
          "inputSchema": {"type": "object"},
          "annotations": {
            "readOnlyHint": true,
            "progressiveDisclosure": {
              "preview": true
            },
            "title": null
          }
        }
        """.utf8))

        XCTAssertEqual(decoded.annotations?.readOnlyHint, true)
        XCTAssertEqual(decoded.annotations?.title, nil)
        XCTAssertEqual(decoded.annotations?.additionalProperties, [
            "progressiveDisclosure": .object([
                "preview": .bool(true)
            ]),
            "title": .null
        ])

        try XCTAssertJSONObjectEqual(decoded, [
            "annotations": [
                "progressiveDisclosure": [
                    "preview": true
                ],
                "readOnlyHint": true,
                "title": NSNull()
            ],
            "inputSchema": [
                "type": "object"
            ],
            "name": "search"
        ])
    }

    func testMcpToolAnnotationsPreserveNonObjectRustJsonValues() throws {
        let decoded = try JSONDecoder().decode(McpTool.self, from: Data("""
        {
          "name": "search",
          "inputSchema": {"type": "object"},
          "annotations": ["experimental", {"rank": 1}]
        }
        """.utf8))

        XCTAssertEqual(decoded.annotations?.rawValue, .array([
            .string("experimental"),
            .object(["rank": .integer(1)])
        ]))
        XCTAssertNil(decoded.annotations?.readOnlyHint)

        try XCTAssertJSONObjectEqual(decoded, [
            "annotations": [
                "experimental",
                [
                    "rank": 1
                ]
            ],
            "inputSchema": [
                "type": "object"
            ],
            "name": "search"
        ])
    }

    func testMcpResourceDecodesRustAliasesAndLossySizes() throws {
        let resource = try JSONDecoder().decode(McpResource.self, from: Data("""
        {
          "name": "readme",
          "uri": "file:///tmp/README.md",
          "mime_type": "text/markdown",
          "size": 5000000000
        }
        """.utf8))

        XCTAssertEqual(resource.mimeType, "text/markdown")
        XCTAssertEqual(resource.size, 5_000_000_000)

        let negative = try JSONDecoder().decode(McpResource.self, from: Data("""
        {
          "name": "negative",
          "uri": "file:///tmp/negative",
          "size": -1
        }
        """.utf8))
        XCTAssertEqual(negative.size, -1)

        let tooBig = try JSONDecoder().decode(McpResource.self, from: Data("""
        {
          "name": "too_big_for_i64",
          "uri": "file:///tmp/too_big_for_i64",
          "size": 18446744073709551615
        }
        """.utf8))
        XCTAssertNil(tooBig.size)
    }

    func testMcpResourceRejectsDuplicateRustMimeTypeAliases() throws {
        XCTAssertThrowsError(try JSONDecoder().decode(McpResource.self, from: Data("""
        {
          "name": "readme",
          "uri": "file:///tmp/README.md",
          "mimeType": "text/plain",
          "mime_type": "text/markdown"
        }
        """.utf8)))
    }

    func testMcpResourcePreservesRustIconsAndMetaFields() throws {
        let decoded = try JSONDecoder().decode(McpResource.self, from: Data("""
        {
          "name": "readme",
          "uri": "file:///tmp/README.md",
          "icons": [
            {
              "src": "file:///tmp/icon.svg"
            }
          ],
          "_meta": {
            "codex/source": "fixture"
          }
        }
        """.utf8))

        XCTAssertEqual(decoded.icons, [
            .object([
                "src": .string("file:///tmp/icon.svg")
            ])
        ])
        XCTAssertEqual(decoded.meta, .object([
            "codex/source": .string("fixture")
        ]))

        try XCTAssertJSONObjectEqual(decoded, [
            "_meta": [
                "codex/source": "fixture"
            ],
            "icons": [
                [
                    "src": "file:///tmp/icon.svg"
                ]
            ],
            "name": "readme",
            "uri": "file:///tmp/README.md"
        ])
    }

    func testMcpResourceAnnotationsPreserveUnknownRustJsonMembers() throws {
        let decoded = try JSONDecoder().decode(McpResource.self, from: Data("""
        {
          "name": "readme",
          "uri": "file:///tmp/README.md",
          "annotations": {
            "audience": ["assistant"],
            "lastModified": null,
            "experimental": {
              "rank": 7
            }
          }
        }
        """.utf8))

        XCTAssertEqual(decoded.annotations?.audience, [.assistant])
        XCTAssertEqual(decoded.annotations?.lastModified, nil)
        XCTAssertEqual(decoded.annotations?.additionalProperties, [
            "experimental": .object([
                "rank": .integer(7)
            ]),
            "lastModified": .null
        ])

        try XCTAssertJSONObjectEqual(decoded, [
            "annotations": [
                "audience": ["assistant"],
                "experimental": [
                    "rank": 7
                ],
                "lastModified": NSNull()
            ],
            "name": "readme",
            "uri": "file:///tmp/README.md"
        ])
    }

    func testMcpResourceAnnotationsPreserveNonObjectRustJsonValues() throws {
        let decoded = try JSONDecoder().decode(McpResource.self, from: Data("""
        {
          "name": "readme",
          "uri": "file:///tmp/README.md",
          "annotations": "opaque"
        }
        """.utf8))

        XCTAssertEqual(decoded.annotations?.rawValue, .string("opaque"))
        XCTAssertNil(decoded.annotations?.audience)

        try XCTAssertJSONObjectEqual(decoded, [
            "annotations": "opaque",
            "name": "readme",
            "uri": "file:///tmp/README.md"
        ])
    }

    func testMcpResourceTemplateDecodesRustSnakeCaseAliases() throws {
        let decoded = try JSONDecoder().decode(McpResourceTemplate.self, from: Data("""
        {
          "name": "workspace-file",
          "uri_template": "file:///workspace/{path}",
          "mime_type": "text/plain",
          "annotations": {
            "priority": 0.25,
            "custom": ["alpha", "beta"]
          }
        }
        """.utf8))

        XCTAssertEqual(decoded.name, "workspace-file")
        XCTAssertEqual(decoded.uriTemplate, "file:///workspace/{path}")
        XCTAssertEqual(decoded.mimeType, "text/plain")
        XCTAssertEqual(decoded.annotations?.priority, 0.25)
        XCTAssertEqual(decoded.annotations?.additionalProperties, [
            "custom": .array([.string("alpha"), .string("beta")])
        ])
    }

    func testMcpResourceTemplateAnnotationsPreserveNonObjectRustJsonValues() throws {
        let decoded = try JSONDecoder().decode(McpResourceTemplate.self, from: Data("""
        {
          "name": "workspace-file",
          "uriTemplate": "file:///workspace/{path}",
          "annotations": 7
        }
        """.utf8))

        XCTAssertEqual(decoded.annotations?.rawValue, .integer(7))
        XCTAssertNil(decoded.annotations?.priority)

        try XCTAssertJSONObjectEqual(decoded, [
            "annotations": 7,
            "name": "workspace-file",
            "uriTemplate": "file:///workspace/{path}"
        ])
    }

    func testMcpResourceTemplateRejectsDuplicateRustAliases() throws {
        XCTAssertThrowsError(try JSONDecoder().decode(McpResourceTemplate.self, from: Data("""
        {
          "name": "workspace-file",
          "uriTemplate": "file:///workspace/{path}",
          "uri_template": "file:///other/{path}"
        }
        """.utf8)))

        XCTAssertThrowsError(try JSONDecoder().decode(McpResourceTemplate.self, from: Data("""
        {
          "name": "workspace-file",
          "uriTemplate": "file:///workspace/{path}",
          "mimeType": "text/plain",
          "mime_type": null
        }
        """.utf8)))
    }

    func testSplitQualifiedToolNameReturnsServerAndTool() throws {
        let split = try XCTUnwrap(McpToolName.splitQualifiedToolName("mcp__alpha__do_thing"))
        XCTAssertEqual(split.serverName, "alpha")
        XCTAssertEqual(split.toolName, "do_thing")
    }

    func testSplitQualifiedToolNameRejectsInvalidNames() {
        XCTAssertNil(McpToolName.splitQualifiedToolName("other__alpha__do_thing"))
        XCTAssertNil(McpToolName.splitQualifiedToolName("mcp__alpha__"))
    }

    func testGroupToolsByServerStripsPrefixAndGroups() {
        let tools = [
            "mcp__alpha__do_thing": makeMcpTool(name: "do_thing"),
            "mcp__alpha__nested__op": makeMcpTool(name: "nested__op"),
            "mcp__beta__do_other": makeMcpTool(name: "do_other")
        ]

        XCTAssertEqual(McpToolName.groupToolsByServer(tools), [
            "alpha": [
                "do_thing": makeMcpTool(name: "do_thing"),
                "nested__op": makeMcpTool(name: "nested__op")
            ],
            "beta": [
                "do_other": makeMcpTool(name: "do_other")
            ]
        ])
    }

    func testQualifiedToolNameMatchesRustPrefix() {
        XCTAssertEqual(
            McpToolName.qualifiedToolName(serverName: "server1", toolName: "tool1"),
            "mcp__server1__tool1"
        )
    }

    func testQualifiedToolNameTruncatesLongNamesWithRustSHA1Suffix() {
        let first = McpToolName.qualifiedToolName(
            serverName: "my_server",
            toolName: "extremely_lengthy_function_name_that_absolutely_surpasses_all_reasonable_limits"
        )
        let second = McpToolName.qualifiedToolName(
            serverName: "my_server",
            toolName: "yet_another_extremely_lengthy_function_name_that_absolutely_surpasses_all_reasonable_limits"
        )

        XCTAssertEqual(first.count, 64)
        XCTAssertEqual(first, "mcp__my_server__extremel119a2b97664e41363932dc84de21e2ff1b93b3e9")
        XCTAssertEqual(second.count, 64)
        XCTAssertEqual(second, "mcp__my_server__yet_anot419a82a89325c1b477274a41f8c65ea5f3a7f341")
    }

    func testQualifyToolsSkipsDuplicateQualifiedNamesLikeRust() {
        let tools = McpToolName.qualifyTools([
            (serverName: "server1", tool: makeMcpTool(name: "duplicate_tool")),
            (serverName: "server1", tool: makeMcpTool(name: "duplicate_tool")),
            (serverName: "server1", tool: makeMcpTool(name: "unique_tool"))
        ])

        XCTAssertEqual(tools.count, 2)
        XCTAssertEqual(tools["mcp__server1__duplicate_tool"], makeMcpTool(name: "duplicate_tool"))
        XCTAssertEqual(tools["mcp__server1__unique_tool"], makeMcpTool(name: "unique_tool"))
    }

    func testNormalizeToolsForModelDedupesByCanonicalToolNameLikeRust() {
        let tools = McpToolName.normalizeToolsForModel([
            McpToolInfo(
                serverName: "server",
                tool: McpTool(name: "lookup", inputSchema: McpToolInputSchema(), description: "first")
            ),
            McpToolInfo(
                serverName: "server",
                tool: McpTool(name: "lookup", inputSchema: McpToolInputSchema(), description: "second")
            ),
            McpToolInfo(serverName: "server", tool: makeMcpTool(name: "search"))
        ])

        XCTAssertEqual(tools.map(\.canonicalToolName), [
            "mcp__server__lookup",
            "mcp__server__search"
        ])
        XCTAssertEqual(tools.first?.tool.description, "first")
    }

    func testNormalizeToolsForModelSanitizesInvalidCharactersLikeRust() {
        let tools = McpToolName.normalizeToolsForModel([
            McpToolInfo(serverName: "server.one", tool: makeMcpTool(name: "tool.two-three"))
        ])

        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools[0].serverName, "server.one")
        XCTAssertEqual(tools[0].tool.name, "tool.two-three")
        XCTAssertEqual(tools[0].callableNamespace, "mcp__server_one__")
        XCTAssertEqual(tools[0].callableName, "tool_two_three")
        XCTAssertEqual(tools[0].canonicalToolName, "mcp__server_one__tool_two_three")
    }

    func testNormalizeToolsForModelDisambiguatesSanitizedCollisionsLikeRust() {
        let tools = McpToolName.normalizeToolsForModel([
            McpToolInfo(serverName: "basic-server", tool: makeMcpTool(name: "lookup")),
            McpToolInfo(serverName: "basic_server", tool: makeMcpTool(name: "query")),
            McpToolInfo(serverName: "server", tool: makeMcpTool(name: "tool-name")),
            McpToolInfo(serverName: "server", tool: makeMcpTool(name: "tool_name"))
        ])

        XCTAssertEqual(tools.count, 4)
        let namespaces = Set(tools.filter { $0.serverName.hasPrefix("basic") }.map(\.callableNamespace))
        XCTAssertEqual(namespaces.count, 2)
        XCTAssertTrue(namespaces.allSatisfy { $0.hasPrefix("mcp__basic_server_") && $0.hasSuffix("__") })

        let callableNames = Set(tools.filter { $0.serverName == "server" }.map(\.callableName))
        XCTAssertEqual(callableNames.count, 2)
        XCTAssertTrue(callableNames.allSatisfy { $0.hasPrefix("tool_name_") })
        XCTAssertFalse(callableNames.contains("tool_name"))
    }

    func testNormalizeToolsForModelFitsLongNamesWithRustHashSuffix() {
        let tools = McpToolName.normalizeToolsForModel([
            McpToolInfo(
                serverName: "my_server",
                tool: makeMcpTool(name: "extremely_lengthy_function_name_that_absolutely_surpasses_all_reasonable_limits")
            ),
            McpToolInfo(
                serverName: "my_server",
                tool: makeMcpTool(name: "yet_another_extremely_lengthy_function_name_that_absolutely_surpasses_all_reasonable_limits")
            )
        ])

        XCTAssertEqual(tools.count, 2)
        XCTAssertTrue(tools.allSatisfy { $0.callableNamespace == "mcp__my_server__" })
        XCTAssertTrue(tools.allSatisfy { $0.canonicalToolName.count == McpToolName.maximumLength })
        XCTAssertTrue(tools.allSatisfy { $0.callableName.contains("_") })
        XCTAssertEqual(Set(tools.map(\.canonicalToolName)).count, 2)
    }

    func testToolFilterAllowsByDefault() {
        XCTAssertTrue(McpToolFilter().allows("any"))
    }

    func testToolFilterAppliesEnabledList() {
        let filter = McpToolFilter(enabled: ["allowed"])

        XCTAssertTrue(filter.allows("allowed"))
        XCTAssertFalse(filter.allows("denied"))
    }

    func testToolFilterAppliesDisabledList() {
        let filter = McpToolFilter(disabled: ["blocked"])

        XCTAssertFalse(filter.allows("blocked"))
        XCTAssertTrue(filter.allows("open"))
    }

    func testToolFilterAppliesEnabledThenDisabled() {
        let filter = McpToolFilter(enabled: ["keep", "remove"], disabled: ["remove"])

        XCTAssertTrue(filter.allows("keep"))
        XCTAssertFalse(filter.allows("remove"))
        XCTAssertFalse(filter.allows("unknown"))
    }

    func testToolFilterFromConfigAndFilterToolsApplyPerServerFilters() {
        let server1Filter = McpToolFilter(config: McpServerConfig(
            transport: .stdio(command: "server1", args: [], env: nil, envVars: [], cwd: nil),
            enabledTools: ["tool_a", "tool_b"],
            disabledTools: ["tool_b"]
        ))
        let server2Filter = McpToolFilter(config: McpServerConfig(
            transport: .stdio(command: "server2", args: [], env: nil, envVars: [], cwd: nil),
            disabledTools: ["tool_a"]
        ))

        let filtered = server1Filter.filterTools([
            (serverName: "server1", tool: makeMcpTool(name: "tool_a")),
            (serverName: "server1", tool: makeMcpTool(name: "tool_b"))
        ]) + server2Filter.filterTools([
            (serverName: "server2", tool: makeMcpTool(name: "tool_a"))
        ])

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].serverName, "server1")
        XCTAssertEqual(filtered[0].tool.name, "tool_a")
    }

    func testInputSchemaAccessorsDefaultTypeWithoutChangingRustWireShape() throws {
        let inputSchema = try JSONDecoder().decode(McpToolInputSchema.self, from: Data("""
        {
          "properties": {
            "query": {
              "type": "string"
            }
          }
        }
        """.utf8))

        XCTAssertEqual(inputSchema.type, "object")
        try XCTAssertJSONObjectEqual(inputSchema, [
            "properties": [
                "query": [
                    "type": "string"
                ]
            ],
        ])
    }

    func testOutputSchemaAccessorsDefaultTypeWithoutChangingRustWireShape() throws {
        let outputSchema = try JSONDecoder().decode(McpToolOutputSchema.self, from: Data(#"{}"#.utf8))
        XCTAssertEqual(outputSchema.type, "object")
        try XCTAssertJSONObjectEqual(outputSchema, [:])
    }

    func testInvocationEncodesMissingArgumentsAsNull() throws {
        try XCTAssertJSONObjectEqual(McpInvocation(server: "filesystem", tool: "read_file"), [
            "server": "filesystem",
            "tool": "read_file",
            "arguments": NSNull()
        ])
    }

    func testToolCallBeginEventWireShape() throws {
        let event = McpToolCallBeginEvent(
            callID: "mcp-1",
            invocation: McpInvocation(
                server: "filesystem",
                tool: "read_file",
                arguments: .object([
                    "path": .string("/tmp/notes.txt"),
                    "limit": .integer(100)
                ])
            )
        )

        try XCTAssertJSONObjectEqual(event, [
            "call_id": "mcp-1",
            "invocation": [
                "server": "filesystem",
                "tool": "read_file",
                "arguments": [
                    "path": "/tmp/notes.txt",
                    "limit": 100
                ]
            ]
        ])
    }

    func testToolCallBeginCarriesMcpAppResourceURIWhenPresent() throws {
        let event = McpToolCallBeginEvent(
            callID: "mcp-1",
            invocation: McpInvocation(server: "filesystem", tool: "read_file"),
            mcpAppResourceURI: "plugin://filesystem"
        )

        try XCTAssertJSONObjectEqual(event, [
            "call_id": "mcp-1",
            "invocation": [
                "server": "filesystem",
                "tool": "read_file",
                "arguments": NSNull()
            ],
            "mcp_app_resource_uri": "plugin://filesystem"
        ])
    }

    func testToolCallEndEventOkWireShapeAndSuccess() throws {
        let event = McpToolCallEndEvent(
            callID: "mcp-1",
            invocation: McpInvocation(server: "filesystem", tool: "read_file"),
            mcpAppResourceURI: "plugin://filesystem",
            duration: ProtocolDuration(secs: 2, nanos: 500),
            result: .ok(McpCallToolResult(
                content: [
                    .text(McpTextContent(text: "done"))
                ],
                isError: false,
                structuredContent: .object([
                    "exit": .integer(0),
                    "cached": .bool(true)
                ])
            ))
        )

        try XCTAssertJSONObjectEqual(event, [
            "call_id": "mcp-1",
            "invocation": [
                "server": "filesystem",
                "tool": "read_file",
                "arguments": NSNull()
            ],
            "mcp_app_resource_uri": "plugin://filesystem",
            "duration": [
                "secs": 2,
                "nanos": 500
            ],
            "result": [
                "Ok": [
                    "content": [
                        [
                            "text": "done",
                            "type": "text"
                        ]
                    ],
                    "isError": false,
                    "structuredContent": [
                        "exit": 0,
                        "cached": true
                    ]
                ]
            ]
        ])
        XCTAssertTrue(event.isSuccess)
    }

    func testToolCallEndEventErrWireShapeAndFailure() throws {
        let json = """
        {
          "call_id": "mcp-2",
          "invocation": {
            "server": "github",
            "tool": "search",
            "arguments": null
          },
          "duration": {
            "secs": 0,
            "nanos": 1
          },
          "result": {
            "Err": "server disconnected"
          }
        }
        """

        let event = try JSONDecoder().decode(McpToolCallEndEvent.self, from: Data(json.utf8))
        XCTAssertEqual(event, McpToolCallEndEvent(
            callID: "mcp-2",
            invocation: McpInvocation(server: "github", tool: "search"),
            duration: ProtocolDuration(secs: 0, nanos: 1),
            result: .err("server disconnected")
        ))
        XCTAssertFalse(event.isSuccess)
    }

    func testToolCallEndTreatsMcpErrorResultAsFailure() {
        let event = McpToolCallEndEvent(
            callID: "mcp-3",
            invocation: McpInvocation(server: "github", tool: "search"),
            duration: ProtocolDuration(secs: 0),
            result: .ok(McpCallToolResult(
                content: [.text(McpTextContent(text: "not found"))],
                isError: true
            ))
        )

        XCTAssertFalse(event.isSuccess)
    }

    func testToolCallResultTruncatesLargeSuccessForEventLikeRust() throws {
        let original = McpCallToolResult(
            content: [
                .text(McpTextContent(text: String(repeating: "long-message-with-newlines-\n", count: 1_000)))
            ],
            isError: false,
            structuredContent: .object([
                "structured": .string(String(repeating: "structured-value-", count: 1_000))
            ]),
            meta: .object([
                "meta": .string(String(repeating: "meta-value-", count: 1_000))
            ])
        )

        let truncated = original.truncatedForEvent(maxBytes: 512)
        let encoded = try JSONEncoder().encode(truncated)

        XCTAssertLessThan(encoded.count, 512 * 2 + 1_024)
        XCTAssertEqual(truncated.structuredContent, nil)
        XCTAssertEqual(truncated.meta, nil)
        XCTAssertEqual(truncated.isError, false)
        guard case let .text(text) = try XCTUnwrap(truncated.content.first) else {
            return XCTFail("expected text preview")
        }
        XCTAssertTrue(text.text.contains("truncated"), "large event result should contain a truncation marker")
    }

    func testToolCallResultTruncatesLargeErrorForEventLikeRust() throws {
        let result = McpToolCallResult.err(String(repeating: "error-message-", count: 1_000))
            .truncatedForEvent(maxBytes: 512)

        guard case let .err(message) = result else {
            return XCTFail("expected error result")
        }
        XCTAssertLessThan(message.utf8.count, 512 + 1_024)
        XCTAssertTrue(message.contains("truncated"))
    }

    func testCallToolResultSanitizesImagesForTextOnlyModelsLikeRust() {
        let original = McpCallToolResult(
            content: [
                .image(McpImageContent(data: "Zm9v", mimeType: "image/png")),
                .text(McpTextContent(text: "hello"))
            ],
            isError: false
        )

        let sanitized = original.sanitizedForModel(supportsImageInput: false)

        XCTAssertEqual(sanitized, McpCallToolResult(
            content: [
                .text(McpTextContent(text: McpCallToolResult.imageContentOmittedForModelPlaceholder)),
                .text(McpTextContent(text: "hello"))
            ],
            isError: false
        ))
    }

    func testCallToolResultPreservesImagesWhenModelSupportsImageInputLikeRust() {
        let original = McpCallToolResult(
            content: [
                .image(McpImageContent(data: "Zm9v", mimeType: "image/png"))
            ],
            isError: false,
            structuredContent: .object(["x": .integer(1)]),
            meta: .object(["k": .string("v")])
        )

        XCTAssertEqual(original.sanitizedForModel(supportsImageInput: true), original)
    }

    func testMcpContentBlocksCoverRustUntaggedVariantEncoding() throws {
        let result = McpCallToolResult(content: [
            .image(McpImageContent(data: "iVBORw0=", mimeType: "image/png")),
            .audio(McpAudioContent(data: "AAAA", mimeType: "audio/wav")),
            .resourceLink(McpResourceLink(
                name: "readme",
                uri: "file:///tmp/README.md",
                description: "docs",
                mimeType: "text/markdown",
                size: 42,
                title: "README"
            )),
            .embeddedResource(McpEmbeddedResource(resource: .text(McpTextResourceContents(
                text: "hello",
                uri: "file:///tmp/hello.txt",
                mimeType: "text/plain"
            )))),
            .embeddedResource(McpEmbeddedResource(resource: .blob(McpBlobResourceContents(
                blob: "AAEC",
                uri: "file:///tmp/blob.bin",
                mimeType: "application/octet-stream"
            ))))
        ])

        try XCTAssertJSONObjectEqual(result, [
            "content": [
                [
                    "data": "iVBORw0=",
                    "mimeType": "image/png",
                    "type": "image"
                ],
                [
                    "data": "AAAA",
                    "mimeType": "audio/wav",
                    "type": "audio"
                ],
                [
                    "description": "docs",
                    "mimeType": "text/markdown",
                    "name": "readme",
                    "size": 42,
                    "title": "README",
                    "type": "resource_link",
                    "uri": "file:///tmp/README.md"
                ],
                [
                    "resource": [
                        "mimeType": "text/plain",
                        "text": "hello",
                        "uri": "file:///tmp/hello.txt"
                    ],
                    "type": "resource"
                ],
                [
                    "resource": [
                        "blob": "AAEC",
                        "mimeType": "application/octet-stream",
                        "uri": "file:///tmp/blob.bin"
                    ],
                    "type": "resource"
                ]
            ]
        ])
    }

    func testMcpContentBlocksPreserveRustMetaFields() throws {
        let result = try JSONDecoder().decode(McpCallToolResult.self, from: Data("""
        {
          "content": [
            {
              "type": "text",
              "text": "caption",
              "_meta": {
                "textSource": "fixture"
              }
            },
            {
              "type": "audio",
              "data": "AAAA",
              "mimeType": "audio/wav",
              "_meta": {
                "duration": 1
              }
            },
            {
              "type": "resource_link",
              "name": "readme",
              "uri": "file:///tmp/README.md",
              "icons": [
                {
                  "src": "file:///tmp/icon.svg"
                }
              ],
              "_meta": {
                "linkSource": "fixture"
              }
            },
            {
              "type": "resource",
              "resource": {
                "uri": "file:///tmp/text.txt",
                "mimeType": "text/plain",
                "text": "hello",
                "_meta": {
                  "textResource": true
                }
              },
              "_meta": {
                "embeddedSource": "text"
              }
            },
            {
              "type": "resource",
              "resource": {
                "uri": "file:///tmp/blob.bin",
                "mimeType": "application/octet-stream",
                "blob": "AAEC",
                "_meta": {
                  "blobResource": true
                }
              },
              "_meta": {
                "embeddedSource": "blob"
              }
            }
          ]
        }
        """.utf8))

        XCTAssertEqual(result.content, [
            .text(McpTextContent(
                text: "caption",
                meta: .object(["textSource": .string("fixture")])
            )),
            .audio(McpAudioContent(
                data: "AAAA",
                mimeType: "audio/wav",
                meta: .object(["duration": .integer(1)])
            )),
            .resourceLink(McpResourceLink(
                name: "readme",
                uri: "file:///tmp/README.md",
                icons: [
                    .object(["src": .string("file:///tmp/icon.svg")])
                ],
                meta: .object(["linkSource": .string("fixture")])
            )),
            .embeddedResource(McpEmbeddedResource(
                resource: .text(McpTextResourceContents(
                    text: "hello",
                    uri: "file:///tmp/text.txt",
                    mimeType: "text/plain",
                    meta: .object(["textResource": .bool(true)])
                )),
                meta: .object(["embeddedSource": .string("text")])
            )),
            .embeddedResource(McpEmbeddedResource(
                resource: .blob(McpBlobResourceContents(
                    blob: "AAEC",
                    uri: "file:///tmp/blob.bin",
                    mimeType: "application/octet-stream",
                    meta: .object(["blobResource": .bool(true)])
                )),
                meta: .object(["embeddedSource": .string("blob")])
            ))
        ])

        try XCTAssertJSONObjectEqual(result, [
            "content": [
                [
                    "_meta": [
                        "textSource": "fixture"
                    ],
                    "text": "caption",
                    "type": "text"
                ],
                [
                    "_meta": [
                        "duration": 1
                    ],
                    "data": "AAAA",
                    "mimeType": "audio/wav",
                    "type": "audio"
                ],
                [
                    "_meta": [
                        "linkSource": "fixture"
                    ],
                    "icons": [
                        [
                            "src": "file:///tmp/icon.svg"
                        ]
                    ],
                    "name": "readme",
                    "type": "resource_link",
                    "uri": "file:///tmp/README.md"
                ],
                [
                    "_meta": [
                        "embeddedSource": "text"
                    ],
                    "resource": [
                        "_meta": [
                            "textResource": true
                        ],
                        "mimeType": "text/plain",
                        "text": "hello",
                        "uri": "file:///tmp/text.txt"
                    ],
                    "type": "resource"
                ],
                [
                    "_meta": [
                        "embeddedSource": "blob"
                    ],
                    "resource": [
                        "_meta": [
                            "blobResource": true
                        ],
                        "blob": "AAEC",
                        "mimeType": "application/octet-stream",
                        "uri": "file:///tmp/blob.bin"
                    ],
                    "type": "resource"
                ]
            ]
        ])

        try XCTAssertJSONObjectEqual(McpCallToolResult(content: [
            .audio(McpAudioContent(
                data: "BBBB",
                mimeType: "audio/mpeg",
                meta: .object(["codec": .string("mp3")])
            ))
        ]), [
            "content": [
                [
                    "_meta": [
                        "codec": "mp3"
                    ],
                    "data": "BBBB",
                    "mimeType": "audio/mpeg",
                    "type": "audio"
                ]
            ]
        ])
    }

    func testMcpContentBlockDecodingUsesRustTypeTags() throws {
        let block = try JSONDecoder().decode(McpContentBlock.self, from: Data("""
        {
          "type": "audio",
          "data": "AAAA",
          "mimeType": "audio/wav"
        }
        """.utf8))

        XCTAssertEqual(block, .audio(McpAudioContent(data: "AAAA", mimeType: "audio/wav")))
    }

    func testMcpImageContentDecodesRustMimeAliasesAndDefault() throws {
        let snake = try JSONDecoder().decode(McpContentBlock.self, from: Data("""
        {
          "type": "image",
          "data": "AAAA",
          "mime_type": "image/jpeg"
        }
        """.utf8))
        XCTAssertEqual(snake, .image(McpImageContent(data: "AAAA", mimeType: "image/jpeg")))

        let missing = try JSONDecoder().decode(McpContentBlock.self, from: Data("""
        {
          "type": "image",
          "data": "BBBB"
        }
        """.utf8))
        XCTAssertEqual(missing, .image(McpImageContent(data: "BBBB", mimeType: "application/octet-stream")))
    }

    func testMcpImageContentRejectsDuplicateRustMimeTypeAliases() throws {
        XCTAssertThrowsError(try JSONDecoder().decode(McpContentBlock.self, from: Data("""
        {
          "type": "image",
          "data": "AAAA",
          "mimeType": "image/png",
          "mime_type": "image/jpeg"
        }
        """.utf8)))
    }

    func testAuthStatusWireValuesAndDisplayMatchRust() throws {
        XCTAssertEqual(try encode(McpAuthStatus.unsupported), #""unsupported""#)
        XCTAssertEqual(try encode(McpAuthStatus.notLoggedIn), #""not_logged_in""#)
        XCTAssertEqual(try encode(McpAuthStatus.bearerToken), #""bearer_token""#)
        XCTAssertEqual(try encode(McpAuthStatus.oauth), #""oauth""#)

        XCTAssertEqual(McpAuthStatus.unsupported.description, "Unsupported")
        XCTAssertEqual(McpAuthStatus.notLoggedIn.description, "Not logged in")
        XCTAssertEqual(McpAuthStatus.bearerToken.description, "Bearer token")
        XCTAssertEqual(McpAuthStatus.oauth.description, "OAuth")
    }

    private func makeMcpTool(name: String) -> McpTool {
        McpTool(name: name, inputSchema: McpToolInputSchema())
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        String(data: try JSONEncoder().encode(value), encoding: .utf8) ?? ""
    }
}
