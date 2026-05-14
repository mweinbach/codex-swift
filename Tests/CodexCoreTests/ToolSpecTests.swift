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

    func testJSONSchemaDecodesIntegerAsRustInteger() throws {
        let schema = try JSONDecoder().decode(JSONSchema.self, from: Data(#"{"type":"integer"}"#.utf8))
        XCTAssertEqual(schema, .integer(description: nil))
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
                    "mode": .stringEnum(values: [.string("fast"), .string("slow")], description: nil)
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

    func testSanitizedSchemaPreservesNullableUnionsAndAnyOfLikeRust() throws {
        let schema = JSONSchema.sanitized(from: [
            "type": "object",
            "properties": [
                "nickname": [
                    "type": ["string", "null"],
                    "description": "Optional nickname"
                ],
                "open": [
                    "anyOf": [
                        [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "ref_id": ["type": "string"],
                                    "lineno": [
                                        "anyOf": [
                                            ["type": "integer"],
                                            ["type": "null"]
                                        ]
                                    ]
                                ],
                                "required": ["ref_id"],
                                "additionalProperties": false
                            ]
                        ],
                        ["type": "null"]
                    ]
                ]
            ],
            "required": ["nickname"],
            "additionalProperties": false
        ])

        XCTAssertEqual(
            schema,
            .object(
                properties: [
                    "nickname": .typeUnion(
                        types: ["string", "null"],
                        description: "Optional nickname",
                        enumValues: nil,
                        items: nil,
                        properties: nil,
                        required: nil,
                        additionalProperties: nil
                    ),
                    "open": .anyOf(
                        variants: [
                            .array(
                                items: .object(
                                    properties: [
                                        "ref_id": .string(description: nil),
                                        "lineno": .anyOf(
                                            variants: [
                                                .integer(description: nil),
                                                .null(description: nil)
                                            ],
                                            description: nil
                                        )
                                    ],
                                    required: ["ref_id"],
                                    additionalProperties: .boolean(false)
                                ),
                                description: nil
                            ),
                            .null(description: nil)
                        ],
                        description: nil
                    )
                ],
                required: ["nickname"],
                additionalProperties: .boolean(false)
            )
        )
    }

    func testSanitizedSchemaDefaultsNullableObjectAndArrayChildrenLikeRust() {
        XCTAssertEqual(
            JSONSchema.sanitized(from: ["type": ["object", "null"]]),
            .typeUnion(
                types: ["object", "null"],
                description: nil,
                enumValues: nil,
                items: nil,
                properties: [:],
                required: nil,
                additionalProperties: nil
            )
        )
        XCTAssertEqual(
            JSONSchema.sanitized(from: ["type": ["array", "null"]]),
            .typeUnion(
                types: ["array", "null"],
                description: nil,
                enumValues: nil,
                items: .string(description: nil),
                properties: nil,
                required: nil,
                additionalProperties: nil
            )
        )
    }

    func testAgentJobToolSpecsMatchRustSchemas() {
        XCTAssertEqual(
            ToolSpecFactory.createSpawnAgentsOnCSVTool(),
            .function(ResponsesAPITool(
                name: "spawn_agents_on_csv",
                description: "Process a CSV by spawning one worker sub-agent per row. The instruction string is a template where `{column}` placeholders are replaced with row values. Each worker must call `report_agent_job_result` with a JSON object (matching `output_schema` when provided); missing reports are treated as failures. This call blocks until all rows finish and automatically exports results to `output_csv_path` (or a default path).",
                strict: false,
                parameters: .object(
                    properties: [
                        "csv_path": .string(description: "Path to the CSV file containing input rows."),
                        "instruction": .string(description: "Instruction template to apply to each CSV row. Use {column_name} placeholders to inject values from the row."),
                        "id_column": .string(description: "Optional column name to use as stable item id."),
                        "output_csv_path": .string(description: "Optional output CSV path for exported results."),
                        "max_concurrency": .number(description: "Maximum concurrent workers for this job. Defaults to 16 and is capped by config."),
                        "max_workers": .number(description: "Alias for max_concurrency. Set to 1 to run sequentially."),
                        "max_runtime_seconds": .number(description: "Maximum runtime per worker before it is failed. Defaults to 1800 seconds."),
                        "output_schema": .object(properties: [:], required: nil, additionalProperties: nil)
                    ],
                    required: ["csv_path", "instruction"],
                    additionalProperties: .boolean(false)
                )
            ))
        )

        XCTAssertEqual(
            ToolSpecFactory.createReportAgentJobResultTool(),
            .function(ResponsesAPITool(
                name: "report_agent_job_result",
                description: "Worker-only tool to report a result for an agent job item. Main agents should not call this.",
                strict: false,
                parameters: .object(
                    properties: [
                        "job_id": .string(description: "Identifier of the job."),
                        "item_id": .string(description: "Identifier of the job item."),
                        "result": .object(properties: [:], required: nil, additionalProperties: nil),
                        "stop": .boolean(description: "Optional. When true, cancels the remaining job items after this result is recorded.")
                    ],
                    required: ["job_id", "item_id", "result"],
                    additionalProperties: .boolean(false)
                )
            ))
        )
    }

    func testBuildSpecsCanExposeAgentJobTools() {
        let specs = ToolSpecFactory.buildSpecs(config: ToolsConfig(
            shellType: .disabled,
            includeViewImageTool: false,
            experimentalSupportedTools: ["spawn_agents_on_csv", "report_agent_job_result"]
        ))

        XCTAssertTrue(specs.contains {
            $0.spec.name == "spawn_agents_on_csv" && $0.supportsParallelToolCalls == false
        })
        XCTAssertTrue(specs.contains {
            $0.spec.name == "report_agent_job_result" && $0.supportsParallelToolCalls == false
        })
    }

    func testBuildSpecsExposeAgentJobToolsFromRustFeatureFlags() {
        let mainAgentSpecs = ToolSpecFactory.buildSpecs(config: ToolsConfig(
            shellType: .disabled,
            includeViewImageTool: false,
            agentJobTools: true
        ))
        XCTAssertTrue(mainAgentSpecs.contains {
            $0.spec.name == "spawn_agents_on_csv" && $0.supportsParallelToolCalls == false
        })
        XCTAssertFalse(mainAgentSpecs.contains {
            $0.spec.name == "report_agent_job_result"
        })

        let workerSpecs = ToolSpecFactory.buildSpecs(config: ToolsConfig(
            shellType: .disabled,
            includeViewImageTool: false,
            agentJobTools: true,
            agentJobWorkerTools: true
        ))
        XCTAssertTrue(workerSpecs.contains {
            $0.spec.name == "spawn_agents_on_csv" && $0.supportsParallelToolCalls == false
        })
        XCTAssertTrue(workerSpecs.contains {
            $0.spec.name == "report_agent_job_result" && $0.supportsParallelToolCalls == false
        })
    }

    func testBuildSpecsMultiAgentV2UsesTaskNamesAndHidesLegacyToolsLikeRust() throws {
        let specs = ToolSpecFactory.buildSpecs(config: ToolsConfig(
            shellType: .disabled,
            includeViewImageTool: false,
            multiAgentV2Tools: true,
            spawnAgentUsageHint: true,
            spawnAgentUsageHintText: "Custom delegation guidance.",
            maxConcurrentThreadsPerSession: 5,
            waitAgentMinTimeoutMS: 2_500
        ))

        XCTAssertEqual(specs.map(\.spec.name), [
            "list_mcp_resources",
            "list_mcp_resource_templates",
            "read_mcp_resource",
            "update_plan",
            "spawn_agent",
            "send_message",
            "followup_task",
            "wait_agent",
            "close_agent",
            "list_agents"
        ])
        XCTAssertFalse(specs.contains { $0.spec.name == "send_input" })
        XCTAssertFalse(specs.contains { $0.spec.name == "resume_agent" })
        for name in ["spawn_agent", "send_message", "followup_task", "wait_agent", "close_agent", "list_agents"] {
            XCTAssertFalse(try XCTUnwrap(specs.first { $0.spec.name == name }).supportsParallelToolCalls)
        }

        let spawn = try functionTool(named: "spawn_agent", in: specs)
        XCTAssertTrue(spawn.description.contains("Spawns an agent to work on the specified task."))
        XCTAssertTrue(spawn.description.contains("task_name \"task_3\""))
        XCTAssertTrue(spawn.description.contains("max_concurrent_threads_per_session = 5"))
        XCTAssertTrue(spawn.description.contains("Custom delegation guidance."))
        XCTAssertEqual(
            spawn.parameters,
            .object(
                properties: [
                    "message": .string(description: "Initial plain-text task for the new agent."),
                    "agent_type": .string(description: "Optional type name for the new agent. If omitted, `default` is used."),
                    "fork_turns": .string(description: "Optional number of turns to fork. Defaults to `all`. Use `none`, `all`, or a positive integer string such as `3` to fork only the most recent turns."),
                    "model": .string(description: "Optional model override for the new agent. Leave unset to inherit the same model as the parent, which is the preferred default. Only set this when the user explicitly asks for a different model or the task clearly requires one."),
                    "reasoning_effort": .string(description: "Optional reasoning effort override for the new agent. Replaces the inherited reasoning effort."),
                    "task_name": .string(description: "Task name for the new agent. Use lowercase letters, digits, and underscores.")
                ],
                required: ["task_name", "message"],
                additionalProperties: .boolean(false)
            )
        )
        XCTAssertEqual(outputRequiredFields(spawn.outputSchema), ["task_name", "nickname"])

        let sendMessage = try functionTool(named: "send_message", in: specs)
        XCTAssertNil(sendMessage.outputSchema)
        XCTAssertEqual(
            sendMessage.parameters,
            .object(
                properties: [
                    "target": .string(description: "Relative or canonical task name to message (from spawn_agent)."),
                    "message": .string(description: "Message text to queue on the target agent.")
                ],
                required: ["target", "message"],
                additionalProperties: .boolean(false)
            )
        )

        let followupTask = try functionTool(named: "followup_task", in: specs)
        XCTAssertNil(followupTask.outputSchema)
        XCTAssertEqual(
            followupTask.parameters,
            .object(
                properties: [
                    "target": .string(description: "Agent id or canonical task name to message (from spawn_agent)."),
                    "message": .string(description: "Message text to send to the target agent.")
                ],
                required: ["target", "message"],
                additionalProperties: .boolean(false)
            )
        )

        let waitAgent = try functionTool(named: "wait_agent", in: specs)
        XCTAssertEqual(
            waitAgent.parameters,
            .object(
                properties: [
                    "timeout_ms": .number(description: "Optional timeout in milliseconds. Defaults to 30000, min 2500, max 3600000.")
                ],
                required: nil,
                additionalProperties: .boolean(false)
            )
        )
        XCTAssertEqual(outputRequiredFields(waitAgent.outputSchema), ["message", "timed_out"])

        let closeAgent = try functionTool(named: "close_agent", in: specs)
        XCTAssertEqual(
            closeAgent.parameters,
            .object(
                properties: [
                    "target": .string(description: "Agent id or canonical task name to close (from spawn_agent).")
                ],
                required: ["target"],
                additionalProperties: .boolean(false)
            )
        )
        XCTAssertEqual(outputRequiredFields(closeAgent.outputSchema), ["previous_status"])

        let listAgents = try functionTool(named: "list_agents", in: specs)
        XCTAssertEqual(
            listAgents.parameters,
            .object(
                properties: [
                    "path_prefix": .string(description: "Optional task-path prefix (not ending with trailing slash). Accepts the same relative or absolute task-path syntax.")
                ],
                required: nil,
                additionalProperties: .boolean(false)
            )
        )
        XCTAssertEqual(outputRequiredFields(listAgents.outputSchema), ["agents"])
    }

    func testBuildSpecsMultiAgentV2HideMetadataMatchesRustSchema() throws {
        let specs = ToolSpecFactory.buildSpecs(config: ToolsConfig(
            shellType: .disabled,
            includeViewImageTool: false,
            multiAgentV2Tools: true,
            spawnAgentUsageHint: false,
            spawnAgentUsageHintText: "Should not appear.",
            hideSpawnAgentMetadata: true,
            waitAgentMinTimeoutMS: 50_000
        ))

        let spawn = try functionTool(named: "spawn_agent", in: specs)
        XCTAssertFalse(spawn.description.contains("No picker-visible model overrides"))
        XCTAssertFalse(spawn.description.contains("Should not appear."))
        guard case let .object(properties, required, _) = spawn.parameters else {
            return XCTFail("expected object parameters")
        }
        XCTAssertEqual(required, ["task_name", "message"])
        XCTAssertEqual(Set(properties.keys), Set(["message", "fork_turns", "task_name"]))
        XCTAssertEqual(outputRequiredFields(spawn.outputSchema), ["task_name"])

        let waitAgent = try functionTool(named: "wait_agent", in: specs)
        guard case let .object(waitProperties, _, _) = waitAgent.parameters else {
            return XCTFail("expected wait_agent object parameters")
        }
        XCTAssertEqual(
            waitProperties["timeout_ms"],
            .number(description: "Optional timeout in milliseconds. Defaults to 50000, min 50000, max 3600000.")
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

    func testViewImageSpecIncludesDetailAndEnvironmentOnlyWhenConfiguredLikeRust() throws {
        let single = try JSONObject(ToolSpecFactory.createViewImageTool())
        let singleParameters = try XCTUnwrap(single["parameters"] as? [String: Any])
        let singleProperties = try XCTUnwrap(singleParameters["properties"] as? [String: Any])
        XCTAssertNotNil(singleProperties["path"])
        XCTAssertNil(singleProperties["detail"])
        XCTAssertNil(singleProperties["environment_id"])

        let multiple = try JSONObject(ToolSpecFactory.createViewImageTool(
            canRequestOriginalImageDetail: true,
            includeEnvironmentID: true
        ))
        let multipleParameters = try XCTUnwrap(multiple["parameters"] as? [String: Any])
        let multipleProperties = try XCTUnwrap(multipleParameters["properties"] as? [String: Any])
        XCTAssertNotNil(multipleProperties["detail"])
        XCTAssertNotNil(multipleProperties["environment_id"])
        XCTAssertEqual(multipleParameters["required"] as? [String], ["path"])
    }

    func testBuildSpecsAddsViewImageEnvironmentIDOnlyForMultipleEnvironments() throws {
        let single = ToolSpecFactory.buildSpecs(config: ToolsConfig(
            shellType: .disabled,
            includeViewImageTool: true,
            environmentMode: .single
        ))
        let singleTool = try XCTUnwrap(single.first { $0.spec.name == "view_image" }?.spec)
        let singleObject = try JSONObject(singleTool)
        let singleParameters = try XCTUnwrap(singleObject["parameters"] as? [String: Any])
        let singleProperties = try XCTUnwrap(singleParameters["properties"] as? [String: Any])
        XCTAssertNil(singleProperties["environment_id"])

        let multiple = ToolSpecFactory.buildSpecs(config: ToolsConfig(
            shellType: .disabled,
            includeViewImageTool: true,
            environmentMode: .multiple
        ))
        let multipleTool = try XCTUnwrap(multiple.first { $0.spec.name == "view_image" }?.spec)
        let multipleObject = try JSONObject(multipleTool)
        let multipleParameters = try XCTUnwrap(multipleObject["parameters"] as? [String: Any])
        let multipleProperties = try XCTUnwrap(multipleParameters["properties"] as? [String: Any])
        XCTAssertNotNil(multipleProperties["environment_id"])
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

    func testCollectUnavailableCalledToolsDetectsMcpFunctionCallsLikeRust() {
        let input = [
            ResponseItem.functionCall(
                name: "shell",
                arguments: "{}",
                callID: "call-shell"
            ),
            ResponseItem.functionCall(
                name: "mcp__server__lookup",
                arguments: "{}",
                callID: "call-lookup"
            ),
            ResponseItem.functionCall(
                name: "_create_event",
                namespace: "mcp__codex_apps__calendar",
                arguments: "{}",
                callID: "call-create-event"
            ),
            ResponseItem.functionCall(
                name: "mcp__server__lookup",
                arguments: "{}",
                callID: "call-lookup-duplicate"
            )
        ]

        let tools = ToolSpecFactory.collectUnavailableCalledTools(
            input: input,
            exposedToolNames: []
        )

        XCTAssertEqual(tools, [
            .namespaced("mcp__codex_apps__calendar", "_create_event"),
            .plain("mcp__server__lookup")
        ])
    }

    func testCollectUnavailableCalledToolsSkipsExposedFlatNamesLikeRust() {
        let input = [
            ResponseItem.functionCall(
                name: "mcp__server__lookup",
                arguments: "{}",
                callID: "call-lookup"
            ),
            ResponseItem.functionCall(
                name: "mcp__server__missing",
                arguments: "{}",
                callID: "call-missing"
            )
        ]

        XCTAssertEqual(
            ToolSpecFactory.collectUnavailableCalledTools(
                input: input,
                exposedToolNames: [.plain("mcp__server__lookup")]
            ),
            [.plain("mcp__server__missing")]
        )
        XCTAssertEqual(
            ToolSpecFactory.collectUnavailableCalledTools(
                input: [input[0]],
                exposedToolNames: [.namespaced("mcp__server__", "lookup")]
            ),
            []
        )
    }

    func testBuildSpecsAddsUnavailableMcpPlaceholderSpecLikeRust() throws {
        let unavailableTool = UnavailableToolName.namespaced(
            "mcp__codex_apps__calendar",
            "_create_event"
        )
        let specs = ToolSpecFactory.buildSpecs(
            config: ToolsConfig(
                shellType: .disabled,
                includeViewImageTool: false
            ),
            unavailableCalledTools: [unavailableTool]
        )

        XCTAssertEqual(specs.map(\.spec.name), [
            "list_mcp_resources",
            "list_mcp_resource_templates",
            "read_mcp_resource",
            "update_plan",
            "mcp__codex_apps__calendar_create_event"
        ])
        XCTAssertEqual(specs.last?.supportsParallelToolCalls, false)

        let tool = try functionTool(named: "mcp__codex_apps__calendar_create_event", in: specs)
        XCTAssertTrue(tool.description.contains(
            "Tool `mcp__codex_apps__calendar_create_event` is not currently available."
        ))
        XCTAssertEqual(
            tool.parameters,
            .object(
                properties: [:],
                required: nil,
                additionalProperties: .boolean(false)
            )
        )
    }

    func testRequestPluginInstallCanRegisterWithoutSearchTool() {
        let specs = ToolSpecFactory.buildSpecs(
            config: ToolsConfig(
                shellType: .disabled,
                includeViewImageTool: false,
                toolSearch: false,
                toolSuggest: true
            ),
            discoverableTools: [
                .connector(DiscoverableConnectorInfo(
                    id: "connector_2128aebfecb84f64a069897515042a44",
                    name: "Google Calendar",
                    description: "Plan events and schedules.",
                    isAccessible: false,
                    isEnabled: true
                ))
            ]
        )

        XCTAssertEqual(specs.map { $0.spec.name }, [
            "list_mcp_resources",
            "list_mcp_resource_templates",
            "read_mcp_resource",
            "update_plan",
            "request_plugin_install"
        ])
        XCTAssertEqual(specs.last?.supportsParallelToolCalls, true)
    }

    func testRequestPluginInstallDoesNotRegisterWithoutToolSuggest() {
        let specs = ToolSpecFactory.buildSpecs(
            config: ToolsConfig(
                shellType: .disabled,
                toolSuggest: false
            ),
            discoverableTools: [
                .connector(DiscoverableConnectorInfo(
                    id: "connector_2128aebfecb84f64a069897515042a44",
                    name: "Google Calendar",
                    description: "Plan events and schedules.",
                    isAccessible: false,
                    isEnabled: true
                ))
            ]
        )

        XCTAssertFalse(specs.contains { $0.spec.name == requestPluginInstallToolName })
    }

    func testRequestPluginInstallToolUsesRustDescriptionAndSchema() throws {
        let tool = ToolSpecFactory.createRequestPluginInstallTool(entries: [
            RequestPluginInstallEntry(
                id: "slack@openai-curated",
                name: "Slack",
                toolType: .connector,
                hasSkills: false,
                mcpServerNames: [],
                appConnectorIDs: []
            ),
            RequestPluginInstallEntry(
                id: "github",
                name: "GitHub",
                toolType: .plugin,
                hasSkills: true,
                mcpServerNames: ["github-mcp"],
                appConnectorIDs: ["github-app"]
            )
        ])

        guard case let .function(function) = tool else {
            return XCTFail("expected function tool")
        }

        XCTAssertEqual(function.name, "request_plugin_install")
        XCTAssertFalse(function.strict)
        XCTAssertNil(function.outputSchema)
        XCTAssertTrue(function.description.contains("Use this tool only to ask the user to install one known plugin or connector from the list below."))
        XCTAssertTrue(function.description.contains("- GitHub (id: `github`, type: plugin, action: install): skills; MCP servers: github-mcp; app connectors: github-app"))
        XCTAssertTrue(function.description.contains("- Slack (id: `slack@openai-curated`, type: connector, action: install): No description provided."))
        XCTAssertTrue(function.description.contains("IMPORTANT: DO NOT call this tool in parallel with other tools."))
        XCTAssertFalse(function.description.contains("{{discoverable_tools}}"))
        XCTAssertEqual(
            function.parameters,
            .object(
                properties: [
                    "tool_type": .string(description: "Type of discoverable tool to suggest. Use \"connector\" or \"plugin\"."),
                    "action_type": .string(description: "Suggested action for the tool. Use \"install\"."),
                    "tool_id": .string(description: "Connector or plugin id to suggest."),
                    "suggest_reason": .string(description: "Concise one-line user-facing reason why this plugin or connector can help with the current request.")
                ],
                required: ["tool_type", "action_type", "tool_id", "suggest_reason"],
                additionalProperties: .boolean(false)
            )
        )
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

    func testBuildSpecsCoalescesDynamicToolNamespacesLikeRust() throws {
        let specs = ToolSpecFactory.buildSpecs(
            config: ToolsConfig(
                shellType: .disabled,
                applyPatchToolType: nil,
                includeViewImageTool: false
            ),
            dynamicTools: [
                DynamicToolSpec(
                    namespace: "codex_app",
                    name: "automation_update",
                    description: "Create or update automations.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "name": .object(["type": .string("string")])
                        ]),
                        "required": .array([.string("name")]),
                        "additionalProperties": .bool(false)
                    ]),
                    deferLoading: true
                ),
                DynamicToolSpec(
                    namespace: "codex_app",
                    name: "automation_list",
                    description: "List automations.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([:])
                    ]),
                    deferLoading: true
                )
            ]
        )

        XCTAssertEqual(specs.filter { $0.spec.name == "codex_app" }.count, 1)
        let dynamicSpec = try XCTUnwrap(specs.first { $0.spec.name == "codex_app" })
        XCTAssertFalse(dynamicSpec.supportsParallelToolCalls)

        guard case let .namespace(namespace) = dynamicSpec.spec else {
            return XCTFail("expected namespace")
        }
        XCTAssertEqual(namespace.description, "Tools in the codex_app namespace.")
        XCTAssertEqual(namespace.tools.map(namespaceToolName), ["automation_update", "automation_list"])

        guard case let .function(updateTool) = namespace.tools[0] else {
            return XCTFail("expected function")
        }
        XCTAssertEqual(updateTool.description, "Create or update automations.")
        XCTAssertEqual(updateTool.deferLoading, true)
        XCTAssertEqual(
            updateTool.parameters,
            .object(
                properties: ["name": .string(description: nil)],
                required: ["name"],
                additionalProperties: .boolean(false)
            )
        )
    }

    func testModelVisibleSpecsFilterDeferredDynamicToolsLikeRustRouter() throws {
        let dynamicTools = [
            DynamicToolSpec(
                namespace: "codex_app",
                name: "hidden_dynamic_tool",
                description: "Hidden until discovered.",
                inputSchema: .object(["type": .string("object"), "properties": .object([:])]),
                deferLoading: true
            ),
            DynamicToolSpec(
                namespace: "codex_app",
                name: "visible_dynamic_tool",
                description: "Visible immediately.",
                inputSchema: .object(["type": .string("object"), "properties": .object([:])])
            )
        ]
        let specs = ToolSpecFactory.buildSpecs(
            config: ToolsConfig(
                shellType: .disabled,
                applyPatchToolType: nil,
                includeViewImageTool: false
            ),
            dynamicTools: dynamicTools
        )

        let registeredNamespace = try XCTUnwrap(specs.first { $0.spec.name == "codex_app" }?.spec)
        guard case let .namespace(registered) = registeredNamespace else {
            return XCTFail("expected registered namespace")
        }
        XCTAssertEqual(registered.tools.map(namespaceToolName), [
            "hidden_dynamic_tool",
            "visible_dynamic_tool"
        ])

        let visibleSpecs = ToolSpecFactory.modelVisibleSpecs(from: specs, dynamicTools: dynamicTools)
        let visibleNamespace = try XCTUnwrap(visibleSpecs.first { $0.name == "codex_app" })
        guard case let .namespace(namespace) = visibleNamespace else {
            return XCTFail("expected visible namespace")
        }
        XCTAssertEqual(namespace.tools.map(namespaceToolName), ["visible_dynamic_tool"])
    }

    func testModelVisibleSpecsDropEmptyNamespaceAndPlainDeferredDynamicToolLikeRustRouter() {
        let dynamicTools = [
            DynamicToolSpec(
                namespace: "codex_app",
                name: "hidden_dynamic_tool",
                description: "Hidden until discovered.",
                inputSchema: .object(["type": .string("object"), "properties": .object([:])]),
                deferLoading: true
            ),
            DynamicToolSpec(
                name: "plain_dynamic_tool",
                description: "Plain hidden tool.",
                inputSchema: .object(["type": .string("object"), "properties": .object([:])]),
                deferLoading: true
            )
        ]
        let specs = ToolSpecFactory.buildSpecs(
            config: ToolsConfig(
                shellType: .disabled,
                applyPatchToolType: nil,
                includeViewImageTool: false
            ),
            dynamicTools: dynamicTools
        )

        XCTAssertTrue(specs.contains { $0.spec.name == "codex_app" })
        XCTAssertTrue(specs.contains { $0.spec.name == "plain_dynamic_tool" })

        let visibleSpecs = ToolSpecFactory.modelVisibleSpecs(from: specs, dynamicTools: dynamicTools)
        XCTAssertFalse(visibleSpecs.contains { $0.name == "codex_app" })
        XCTAssertFalse(visibleSpecs.contains { $0.name == "plain_dynamic_tool" })
        XCTAssertTrue(visibleSpecs.contains { $0.name == "tool_search" })
    }

    func testBuildSpecsHidesNamespacedDynamicToolsWhenNamespaceToolsDisabledLikeRust() {
        let specs = ToolSpecFactory.buildSpecs(
            config: ToolsConfig(
                shellType: .disabled,
                applyPatchToolType: nil,
                includeViewImageTool: false,
                namespaceTools: false
            ),
            dynamicTools: [
                DynamicToolSpec(
                    namespace: "codex_app",
                    name: "automation_update",
                    description: "Create or update automations.",
                    inputSchema: .object(["type": .string("object"), "properties": .object([:])])
                ),
                DynamicToolSpec(
                    name: "plain_dynamic",
                    description: "Plain dynamic tool.",
                    inputSchema: .object(["type": .string("object"), "properties": .object([:])])
                )
            ]
        )

        XCTAssertFalse(specs.contains { $0.spec.name == "codex_app" })
        XCTAssertTrue(specs.contains { $0.spec.name == "plain_dynamic" })
    }

    func testToolSearchIndexReturnsCoalescedDeferredDynamicNamespaceLikeRust() throws {
        let specs = ToolSpecFactory.buildSpecs(
            config: ToolsConfig(
                shellType: .disabled,
                applyPatchToolType: nil,
                includeViewImageTool: false,
                toolSearch: true
            ),
            dynamicTools: [
                DynamicToolSpec(
                    namespace: "codex_app",
                    name: "automation_update",
                    description: "Create or update recurring automations.",
                    inputSchema: .object(["type": .string("object"), "properties": .object([:])]),
                    deferLoading: true
                ),
                DynamicToolSpec(
                    namespace: "codex_app",
                    name: "automation_list",
                    description: "List recurring automations.",
                    inputSchema: .object(["type": .string("object"), "properties": .object([:])]),
                    deferLoading: true
                )
            ]
        )

        let searchSpec = try XCTUnwrap(specs.first { $0.spec.name == "tool_search" }?.spec)
        guard case let .toolSearch(_, description, _) = searchSpec else {
            return XCTFail("expected tool_search")
        }
        XCTAssertTrue(description.contains("- Dynamic tools: Tools provided by the current Codex thread."))

        let index = ToolSearchIndex.deferredToolIndex(mcpTools: [:], dynamicTools: [
            DynamicToolSpec(
                namespace: "codex_app",
                name: "automation_update",
                description: "Create or update recurring automations.",
                inputSchema: .object(["type": .string("object"), "properties": .object([:])]),
                deferLoading: true
            ),
            DynamicToolSpec(
                namespace: "codex_app",
                name: "automation_list",
                description: "List recurring automations.",
                inputSchema: .object(["type": .string("object"), "properties": .object([:])]),
                deferLoading: true
            )
        ])
        let tools = try index.search(arguments: .object([
            "query": .string("automation"),
            "limit": .integer(8)
        ]))

        XCTAssertEqual(tools.count, 1)
        guard case let .object(namespace) = tools[0],
              case let .array(children)? = namespace["tools"]
        else {
            return XCTFail("expected namespace result")
        }
        XCTAssertEqual(namespace["name"], .string("codex_app"))
        XCTAssertEqual(Set(children.compactMap(toolName)), Set(["automation_update", "automation_list"]))
        XCTAssertEqual(children.compactMap(deferLoading), [true, true])
    }

    func testToolSearchIndexFiltersNamespaceOutputsWhenNamespaceToolsDisabledLikeRust() throws {
        let index = ToolSearchIndex.deferredToolIndex(
            mcpTools: [
                "mcp__calendar__list_events": makeMcpTool(name: "list_events", description: "List calendar events")
            ],
            dynamicTools: [
                DynamicToolSpec(
                    namespace: "codex_app",
                    name: "automation_update",
                    description: "Create or update automations.",
                    inputSchema: .object(["type": .string("object"), "properties": .object([:])]),
                    deferLoading: true
                ),
                DynamicToolSpec(
                    namespace: nil,
                    name: "plain_dynamic",
                    description: "Plain dynamic tool.",
                    inputSchema: .object(["type": .string("object"), "properties": .object([:])]),
                    deferLoading: true
                )
            ],
            namespaceTools: false
        )

        guard case let .toolSearch(_, description, _) = index.toolSpec() else {
            return XCTFail("expected tool_search")
        }
        XCTAssertFalse(description.contains("- calendar"))
        XCTAssertTrue(description.contains("- Dynamic tools: Tools provided by the current Codex thread."))

        let tools = try index.search(arguments: .object([
            "query": .string("dynamic automation calendar"),
            "limit": .integer(8)
        ]))

        XCTAssertEqual(tools.count, 1)
        guard case let .object(tool) = tools[0] else {
            return XCTFail("expected function result")
        }
        XCTAssertEqual(tool["name"], .string("plain_dynamic"))
    }

    func testDynamicToolSearchTextMatchesRustNameDescriptionNamespaceAndProperties() throws {
        let entries = ToolSearchIndex.dynamicEntries(from: [
            DynamicToolSpec(
                namespace: "codex_app",
                name: "later_tool",
                description: "Later tool.",
                inputSchema: .object(["type": .string("object"), "properties": .object([:])]),
                deferLoading: true
            ),
            DynamicToolSpec(
                namespace: "codex_app",
                name: "automation_update",
                description: "Create recurring automations.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "target_id": .object(["type": .string("string")])
                    ])
                ]),
                deferLoading: true
            )
        ])

        XCTAssertEqual(entries.map(\.output.name), ["codex_app", "codex_app"])
        XCTAssertTrue(entries[0].searchText.contains("automation update"))
        XCTAssertTrue(entries[0].searchText.contains("codex_app"))
        XCTAssertTrue(entries[0].searchText.contains("target_id"))
        XCTAssertNil(entries[0].limitBucket)
    }

    func testDynamicToolSearchEntriesUseRustToolNameOrdering() {
        let entries = ToolSearchIndex.dynamicEntries(from: [
            DynamicToolSpec(
                namespace: nil,
                name: "z_plain",
                description: "Plain tool that sorts last.",
                inputSchema: .object(["type": .string("object"), "properties": .object([:])]),
                deferLoading: true
            ),
            DynamicToolSpec(
                namespace: "automation_",
                name: "update",
                description: "Namespaced tool that sorts by namespace.",
                inputSchema: .object(["type": .string("object"), "properties": .object([:])]),
                deferLoading: true
            ),
            DynamicToolSpec(
                namespace: nil,
                name: "alpha_plain",
                description: "Plain tool that sorts by name.",
                inputSchema: .object(["type": .string("object"), "properties": .object([:])]),
                deferLoading: true
            ),
            DynamicToolSpec(
                namespace: "alpha_plain",
                name: "nested",
                description: "Namespaced tool with the same primary key as a plain tool.",
                inputSchema: .object(["type": .string("object"), "properties": .object([:])]),
                deferLoading: true
            )
        ])

        XCTAssertEqual(entries.map(\.output.name), [
            "alpha_plain",
            "alpha_plain",
            "automation_",
            "z_plain"
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

        guard case let .function(tool) = spec else {
            return XCTFail("expected function tool")
        }
        XCTAssertEqual(tool.outputSchema, ToolSpecFactory.mcpCallToolResultOutputSchema())
        XCTAssertNil(object["output_schema"], "Rust keeps MCP tool output_schema internal to ResponsesApiTool")
    }

    func testShellToolSpecsOmitLoginWhenDisallowedLikeRust() throws {
        for spec in [
            ToolSpecFactory.createExecCommandTool(allowLoginShell: false),
            ToolSpecFactory.createShellCommandTool(allowLoginShell: false)
        ] {
            guard case let .function(tool) = spec,
                  case let .object(properties, _, _) = tool.parameters
            else {
                return XCTFail("expected function tool with object parameters")
            }
            XCTAssertNil(properties["login"])
        }
    }

    func testToolsConfigForwardsAllowLoginShellToShellSpecsLikeRust() throws {
        let configured = ToolSpecFactory.buildSpecs(config: ToolsConfig(
            shellType: .unifiedExec,
            allowLoginShell: false
        ))
        let execSpec = try XCTUnwrap(configured.first { $0.spec.name == "exec_command" }?.spec)
        guard case let .function(tool) = execSpec,
              case let .object(properties, _, _) = tool.parameters
        else {
            return XCTFail("expected function tool with object parameters")
        }
        XCTAssertNil(properties["login"])
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
                            "count": .integer(description: nil),
                            "tags": .array(items: .string(description: nil), description: nil),
                            "mode": .stringEnum(values: [.string("fast"), .string("slow")], description: nil)
                        ],
                        required: ["count"],
                        additionalProperties: nil
                    ),
                    outputSchema: ToolSpecFactory.mcpCallToolResultOutputSchema()
                )
            )
        )
    }

    func testMCPToolConversionWrapsStructuredContentOutputSchemaLikeRust() throws {
        let spec = ToolSpecFactory.createMCPTool(
            fullyQualifiedName: "mcp__docs__lookup",
            tool: McpTool(
                name: "lookup",
                inputSchema: McpToolInputSchema(),
                outputSchema: McpToolOutputSchema(
                    properties: .object([
                        "result": .object([
                            "type": .string("string")
                        ])
                    ]),
                    required: ["result"]
                )
            )
        )

        guard case let .function(tool) = spec else {
            return XCTFail("expected function tool")
        }
        XCTAssertEqual(
            tool.outputSchema,
            ToolSpecFactory.mcpCallToolResultOutputSchema(
                structuredContentSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "result": .object([
                            "type": .string("string")
                        ])
                    ]),
                    "required": .array([.string("result")])
                ])
            )
        )

        let object = try JSONObject(spec)
        XCTAssertNil(object["output_schema"], "Rust skips serializing ResponsesApiTool.output_schema")
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

    private func functionTool(named name: String, in specs: [ConfiguredToolSpec]) throws -> ResponsesAPITool {
        let spec = try XCTUnwrap(specs.first { $0.spec.name == name }?.spec)
        guard case let .function(function) = spec else {
            throw NSError(domain: "ToolSpecTests", code: 1)
        }
        return function
    }

    private func outputRequiredFields(_ value: JSONValue?) -> [String]? {
        guard case let .object(object)? = value,
              case let .array(required)? = object["required"]
        else {
            return nil
        }
        return required.compactMap {
            guard case let .string(value) = $0 else {
                return nil
            }
            return value
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
