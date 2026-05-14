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

    func testListToolsResponseWireShape() throws {
        let event = McpListToolsResponseEvent(
            tools: [
                "filesystem/read_file": McpTool(
                    name: "read_file",
                    inputSchema: McpToolInputSchema(
                        properties: .object([
                            "path": .object([
                                "type": .string("string")
                            ])
                        ]),
                        required: ["path"]
                    ),
                    annotations: McpToolAnnotations(
                        destructiveHint: false,
                        readOnlyHint: true,
                        title: "Read file"
                    ),
                    description: "Read a file",
                    outputSchema: McpToolOutputSchema(properties: .object([
                        "content": .object([
                            "type": .string("string")
                        ])
                    ])),
                    title: "Read File"
                )
            ],
            resources: [
                "filesystem": [
                    McpResource(
                        name: "readme",
                        uri: "file:///tmp/README.md",
                        annotations: McpAnnotations(
                            audience: [.assistant, .user],
                            lastModified: "2026-05-08T00:00:00Z",
                            priority: 0.5
                        ),
                        description: "docs",
                        mimeType: "text/markdown",
                        size: 42,
                        title: "README"
                    )
                ]
            ],
            resourceTemplates: [
                "filesystem": [
                    McpResourceTemplate(
                        name: "workspace-file",
                        uriTemplate: "file:///workspace/{path}",
                        description: "workspace files",
                        mimeType: "text/plain",
                        title: "Workspace file"
                    )
                ]
            ],
            authStatuses: [
                "filesystem": .oauth,
                "github": .notLoggedIn
            ]
        )

        try XCTAssertJSONObjectEqual(event, [
            "tools": [
                "filesystem/read_file": [
                    "annotations": [
                        "destructiveHint": false,
                        "readOnlyHint": true,
                        "title": "Read file"
                    ],
                    "description": "Read a file",
                    "inputSchema": [
                        "properties": [
                            "path": [
                                "type": "string"
                            ]
                        ],
                        "required": ["path"],
                        "type": "object"
                    ],
                    "name": "read_file",
                    "outputSchema": [
                        "properties": [
                            "content": [
                                "type": "string"
                            ]
                        ],
                        "type": "object"
                    ],
                    "title": "Read File"
                ]
            ],
            "resources": [
                "filesystem": [
                    [
                        "annotations": [
                            "audience": ["assistant", "user"],
                            "lastModified": "2026-05-08T00:00:00Z",
                            "priority": 0.5
                        ],
                        "description": "docs",
                        "mimeType": "text/markdown",
                        "name": "readme",
                        "size": 42,
                        "title": "README",
                        "uri": "file:///tmp/README.md"
                    ]
                ]
            ],
            "resource_templates": [
                "filesystem": [
                    [
                        "description": "workspace files",
                        "mimeType": "text/plain",
                        "name": "workspace-file",
                        "title": "Workspace file",
                        "uriTemplate": "file:///workspace/{path}"
                    ]
                ]
            ],
            "auth_statuses": [
                "filesystem": "oauth",
                "github": "not_logged_in"
            ]
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

    func testMcpResourceTemplateDecodesRustSnakeCaseAliases() throws {
        let decoded = try JSONDecoder().decode(McpResourceTemplate.self, from: Data("""
        {
          "name": "workspace-file",
          "uri_template": "file:///workspace/{path}",
          "mime_type": "text/plain"
        }
        """.utf8))

        XCTAssertEqual(decoded.name, "workspace-file")
        XCTAssertEqual(decoded.uriTemplate, "file:///workspace/{path}")
        XCTAssertEqual(decoded.mimeType, "text/plain")
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

    func testToolSchemasDefaultTypeOnDecodeAndAlwaysEncodeType() throws {
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
            "type": "object"
        ])

        let outputSchema = try JSONDecoder().decode(McpToolOutputSchema.self, from: Data(#"{}"#.utf8))
        XCTAssertEqual(outputSchema, McpToolOutputSchema())
        try XCTAssertJSONObjectEqual(outputSchema, [
            "type": "object"
        ])
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

    func testMcpContentBlockDecodingFollowsRustUntaggedOrder() throws {
        let block = try JSONDecoder().decode(McpContentBlock.self, from: Data("""
        {
          "type": "audio",
          "data": "AAAA",
          "mimeType": "audio/wav"
        }
        """.utf8))

        XCTAssertEqual(block, .image(McpImageContent(data: "AAAA", mimeType: "audio/wav", type: "audio")))
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
