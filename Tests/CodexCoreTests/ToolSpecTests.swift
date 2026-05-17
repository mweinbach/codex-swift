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
            multiAgentV2Tools: true,
            spawnAgentUsageHint: true,
            spawnAgentUsageHintText: "Custom delegation guidance.",
            maxConcurrentThreadsPerSession: 5,
            waitAgentMinTimeoutMS: 2_500,
            waitAgentMaxTimeoutMS: 120_000,
            waitAgentDefaultTimeoutMS: 45_000
        ))

        XCTAssertEqual(specs.map(\.spec.name), [
            "list_mcp_resources",
            "list_mcp_resource_templates",
            "read_mcp_resource",
            "update_plan",
            "view_image",
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
                    "service_tier": .string(description: "Optional service tier override for the new agent. Leave unset unless the user explicitly asks for one."),
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
                    "timeout_ms": .number(description: "Optional timeout in milliseconds. Defaults to 45000, min 2500, max 120000.")
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
            multiAgentV2Tools: true,
            spawnAgentUsageHint: false,
            spawnAgentUsageHintText: "Should not appear.",
            hideSpawnAgentMetadata: true,
            waitAgentMinTimeoutMS: 5_000,
            waitAgentMaxTimeoutMS: 50_000,
            waitAgentDefaultTimeoutMS: 10_000
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
            .number(description: "Optional timeout in milliseconds. Defaults to 10000, min 5000, max 50000.")
        )
    }

    func testBuildSpecsMultiAgentV2RendersCompactTopFiveModelOverridesLikeRust() throws {
        let visibleModels = (1...6).map { index in
            makeModelPreset(
                model: "model-\(index)",
                description: "Model \(index) description.",
                defaultReasoningEffort: .medium,
                supportedReasoningEfforts: [.low, .medium, .high],
                serviceTiers: index == 1
                    ? [ModelServiceTier(id: "priority", name: "fast", description: "Fast")]
                    : []
            )
        }
        let hiddenModel = makeModelPreset(model: "hidden-model", showInPicker: false)
        let specs = ToolSpecFactory.buildSpecs(config: ToolsConfig(
            shellType: .disabled,
            multiAgentV2Tools: true,
            availableModels: [hiddenModel] + visibleModels,
            spawnAgentUsageHint: false
        ))

        let spawn = try functionTool(named: "spawn_agent", in: specs)
        XCTAssertTrue(spawn.description.contains(
            "Available model overrides (optional; inherited parent model is preferred):"
        ))
        XCTAssertTrue(spawn.description.contains(
            "- `model-1`: Model 1 description. Reasoning efforts: low, medium (default), high. Service tiers: priority."
        ))
        XCTAssertTrue(spawn.description.contains(
            "- `model-5`: Model 5 description. Reasoning efforts: low, medium (default), high."
        ))
        XCTAssertFalse(spawn.description.contains("model-6"))
        XCTAssertFalse(spawn.description.contains("hidden-model"))
        XCTAssertFalse(spawn.description.contains("Default reasoning effort"))
        XCTAssertFalse(spawn.description.contains("Supported service tiers"))
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
        let detail = try XCTUnwrap(multipleProperties["detail"] as? [String: Any])
        XCTAssertEqual(detail["type"] as? String, "string")
        XCTAssertEqual(detail["enum"] as? [String], ["high", "original"])
        XCTAssertNotNil(multipleProperties["environment_id"])
        XCTAssertEqual(multipleParameters["required"] as? [String], ["path"])

        guard case let .function(tool) = ToolSpecFactory.createViewImageTool(
            canRequestOriginalImageDetail: true,
            includeEnvironmentID: true
        ) else {
            return XCTFail("expected view_image function tool")
        }
        guard case let .object(outputSchema)? = tool.outputSchema,
              case let .object(outputProperties)? = outputSchema["properties"],
              case let .object(outputDetail)? = outputProperties["detail"]
        else {
            return XCTFail("expected view_image output schema with detail property")
        }
        XCTAssertEqual(outputDetail["type"], .string("string"))
        XCTAssertEqual(outputDetail["enum"], .array([.string("high"), .string("original")]))
        XCTAssertEqual(outputSchema["required"], .array([.string("image_url"), .string("detail")]))
    }

    func testBuildSpecsAddsViewImageEnvironmentIDOnlyForMultipleEnvironments() throws {
        let single = ToolSpecFactory.buildSpecs(config: ToolsConfig(
            shellType: .disabled,
            environmentMode: .single
        ))
        let singleTool = try XCTUnwrap(single.first { $0.spec.name == "view_image" }?.spec)
        let singleObject = try JSONObject(singleTool)
        let singleParameters = try XCTUnwrap(singleObject["parameters"] as? [String: Any])
        let singleProperties = try XCTUnwrap(singleParameters["properties"] as? [String: Any])
        XCTAssertNil(singleProperties["environment_id"])

        let multiple = ToolSpecFactory.buildSpecs(config: ToolsConfig(
            shellType: .disabled,
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

    func testNamespaceToolSpecPreservesExtensionSlashNamespaceLikeRust() throws {
        let spec = ToolSpec.namespace(
            ResponsesAPINamespace(
                name: "extension/",
                description: "Tools in the extension/ namespace.",
                tools: [
                    .function(
                        ResponsesAPITool(
                            name: "echo",
                            description: "Echoes arguments through an extension tool.",
                            strict: true,
                            parameters: .object(
                                properties: [
                                    "message": .string(description: nil)
                                ],
                                required: ["message"],
                                additionalProperties: .boolean(false)
                            )
                        )
                    )
                ]
            )
        )

        try XCTAssertJSONObjectEqual(spec, [
            "type": "namespace",
            "name": "extension/",
            "description": "Tools in the extension/ namespace.",
            "tools": [
                [
                    "type": "function",
                    "name": "echo",
                    "description": "Echoes arguments through an extension tool.",
                    "strict": true,
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "message": ["type": "string"]
                        ],
                        "required": ["message"],
                        "additionalProperties": false
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
        XCTAssertNil(parallelSpecs["grep_files"])
        XCTAssertNil(parallelSpecs["read_file"])
        XCTAssertNil(parallelSpecs["list_dir"])
        XCTAssertEqual(parallelSpecs["test_sync_tool"], true)
        XCTAssertEqual(parallelSpecs["view_image"], true)
        XCTAssertEqual(parallelSpecs["computer_key"], true)
    }

    func testBuildSpecsOmitEnvironmentBackedToolsWhenEnvironmentDisabledLikeRust() {
        let specs = ToolSpecFactory.buildSpecs(
            config: ToolsConfig(
                shellType: .unifiedExec,
                applyPatchToolType: .freeform,
                environmentMode: .none
            )
        )
        let names = specs.map(\.spec.name)

        XCTAssertFalse(names.contains("exec_command"))
        XCTAssertFalse(names.contains("write_stdin"))
        XCTAssertFalse(names.contains("apply_patch"))
        XCTAssertFalse(names.contains("view_image"))
        XCTAssertTrue(names.contains("list_mcp_resources"))
        XCTAssertTrue(names.contains("update_plan"))
    }

    func testBuildSpecsDoesNotBackfillUnavailableMcpPlaceholdersLikeCurrentRust() {
        let specs = ToolSpecFactory.buildSpecs(config: ToolsConfig(shellType: .disabled))

        XCTAssertEqual(specs.map(\.spec.name), [
            "list_mcp_resources",
            "list_mcp_resource_templates",
            "read_mcp_resource",
            "update_plan",
            "view_image"
        ])
        XCTAssertFalse(specs.contains { $0.spec.name == "mcp__codex_apps__calendar_create_event" })
    }

    func testBuildSpecsNormalizesRemovedLegacyShellSelectionsLikeRust() {
        for shellType in [ConfigShellToolType.default, .local, .shellCommand] {
            let specs = ToolSpecFactory.buildSpecs(config: ToolsConfig(shellType: shellType))
            XCTAssertEqual(specs.first?.spec.name, "shell_command")
            XCTAssertFalse(specs.contains { $0.spec.name == "shell" })
            XCTAssertFalse(specs.contains { $0.spec.name == "local_shell" })
        }
    }

    func testRequestPluginInstallCanRegisterWithoutSearchTool() {
        let specs = ToolSpecFactory.buildSpecs(
            config: ToolsConfig(
                shellType: .disabled,
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
            "request_plugin_install",
            "view_image"
        ])
        XCTAssertTrue(specs.first { $0.spec.name == requestPluginInstallToolName }?.supportsParallelToolCalls == true)
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

    func testRequestPluginInstallDescriptionIncludesOpenAIDevelopersAllowlistedPluginLikeRust() throws {
        let specs = ToolSpecFactory.buildSpecs(
            config: ToolsConfig(
                shellType: .disabled,
                toolSuggest: true
            ),
            discoverableTools: [
                .plugin(DiscoverablePluginInfo(
                    id: "openai-developers@openai-curated",
                    name: "OpenAI Developers",
                    description: "Build with OpenAI APIs, Agents SDK, and ChatGPT Apps.",
                    hasSkills: true,
                    mcpServerNames: ["openai-developers"],
                    appConnectorIDs: []
                ))
            ]
        )

        let tool = try XCTUnwrap(specs.first { $0.spec.name == requestPluginInstallToolName }?.spec)
        guard case let .function(function) = tool else {
            return XCTFail("expected request_plugin_install function tool")
        }

        XCTAssertTrue(function.description.contains(
            "- OpenAI Developers (id: `openai-developers@openai-curated`, type: plugin, action: install): Build with OpenAI APIs, Agents SDK, and ChatGPT Apps."
        ))
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

    func testBuildSpecsIncludesImageGenerationToolWhenEnabledLikeRust() throws {
        let specs = ToolSpecFactory.buildSpecs(config: ToolsConfig(
            shellType: .disabled,
            webSearchMode: .cached,
            includeImageGenerationTool: true
        ))

        XCTAssertEqual(
            specs.map(\.spec.name),
            [
                "list_mcp_resources",
                "list_mcp_resource_templates",
                "read_mcp_resource",
                "update_plan",
                "web_search",
                "image_generation",
                "view_image"
            ]
        )
        let imageGeneration = specs.first { $0.spec.name == "image_generation" }
        XCTAssertEqual(imageGeneration?.spec, .imageGeneration(outputFormat: "png"))
        XCTAssertEqual(imageGeneration?.supportsParallelToolCalls, false)
    }

    func testProviderCapabilitiesDisableProviderBoundToolSurfacesLikeRust() throws {
        let config = ToolsConfig(
            shellType: .disabled,
            webSearchMode: .cached,
            webSearchRequest: true,
            includeImageGenerationTool: true,
            namespaceTools: true,
            toolSearch: true,
            toolSuggest: true
        ).applyingProviderCapabilities(ModelProviderCapabilities(
            namespaceTools: false,
            imageGeneration: false,
            webSearch: false
        ))

        XCTAssertNil(config.webSearchMode)
        XCTAssertFalse(config.webSearchRequest)
        XCTAssertFalse(config.includeImageGenerationTool)
        XCTAssertFalse(config.namespaceTools)
        XCTAssertTrue(config.toolSearch)
        XCTAssertTrue(config.toolSuggest)

        let specs = ToolSpecFactory.buildSpecs(
            config: config,
            mcpTools: [
                "mcp__docs__search": makeMcpTool(name: "search")
            ],
            deferredMcpTools: [
                "mcp__deferred__lookup": makeMcpTool(name: "lookup")
            ],
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

        XCTAssertFalse(specs.contains { $0.spec.name == "web_search" })
        XCTAssertFalse(specs.contains { $0.spec.name == "image_generation" })
        XCTAssertFalse(specs.contains { $0.spec.name == "mcp__docs__" })
        XCTAssertFalse(specs.contains { $0.spec.name == "tool_search" })
        XCTAssertTrue(specs.contains { $0.spec.name == requestPluginInstallToolName })
    }

    private func webSearchSpecs(in specs: [ConfiguredToolSpec]) -> [ToolSpec] {
        specs.map(\.spec).filter { $0.name == "web_search" }
    }

    func testBuildSpecsAppendsMCPToolsAsSortedNamespaceLikeRust() throws {
        let specs = ToolSpecFactory.buildSpecs(
            config: ToolsConfig(
                shellType: .disabled,
                applyPatchToolType: nil
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

    func testBuildSpecsDerivesMCPNamespaceFromToolInfoLikeRust() throws {
        let specs = ToolSpecFactory.buildSpecs(
            config: ToolsConfig(
                shellType: .disabled,
                applyPatchToolType: nil
            ),
            mcpToolInfos: [
                McpToolInfo(serverName: "docs", tool: makeMcpTool(name: "search")),
                McpToolInfo(serverName: "docs", tool: makeMcpTool(name: "search", description: "Duplicate")),
                McpToolInfo(serverName: "calendar", tool: makeMcpTool(name: "list_events"))
            ]
        )

        let namespaceSpecs = specs.compactMap { configured -> ResponsesAPINamespace? in
            guard case let .namespace(namespace) = configured.spec,
                  namespace.name.hasPrefix("mcp__")
            else {
                return nil
            }
            return namespace
        }

        XCTAssertEqual(namespaceSpecs.map(\.name), ["mcp__calendar__", "mcp__docs__"])
        XCTAssertEqual(namespaceSpecs.map { $0.tools.map(namespaceToolName) }, [
            ["list_events"],
            ["search"]
        ])
    }

    func testBuildSpecsUsesMCPNamespaceDescriptionLikeRust() throws {
        let specs = ToolSpecFactory.buildSpecs(
            config: ToolsConfig(
                shellType: .disabled,
                applyPatchToolType: nil
            ),
            mcpToolInfos: [
                McpToolInfo(
                    serverName: "rmcp",
                    namespaceDescription: "Use this server for durable workspace notes.",
                    tool: makeMcpTool(name: "remember")
                )
            ]
        )

        let mcpSpec = try XCTUnwrap(specs.first { $0.spec.name == "mcp__rmcp__" })
        guard case let .namespace(namespace) = mcpSpec.spec else {
            return XCTFail("expected namespace")
        }
        XCTAssertEqual(namespace.description, "Use this server for durable workspace notes.")
    }

    func testBuildSpecsUsesRustSanitizedMCPCallableNames() throws {
        let specs = ToolSpecFactory.buildSpecs(
            config: ToolsConfig(
                shellType: .disabled,
                applyPatchToolType: nil
            ),
            mcpToolInfos: [
                McpToolInfo(serverName: "server.one", tool: makeMcpTool(name: "tool.two-three"))
            ]
        )

        let mcpSpec = try XCTUnwrap(specs.first { $0.spec.name == "mcp__server_one__" })
        guard case let .namespace(namespace) = mcpSpec.spec else {
            return XCTFail("expected namespace")
        }
        XCTAssertEqual(namespace.name, "mcp__server_one__")
        XCTAssertEqual(namespace.tools.map(namespaceToolName), ["tool_two_three"])
    }

    func testBuildSpecsCoalescesDynamicToolNamespacesLikeRust() throws {
        let specs = ToolSpecFactory.buildSpecs(
            config: ToolsConfig(
                shellType: .disabled,
                applyPatchToolType: nil
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
                    ])
                ),
                DynamicToolSpec(
                    namespace: "codex_app",
                    name: "automation_list",
                    description: "List automations.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([:])
                    ])
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
        XCTAssertEqual(namespace.tools.map(namespaceToolName), ["automation_list", "automation_update"])

        let updateNamespaceTool = try XCTUnwrap(namespace.tools.first { namespaceToolName($0) == "automation_update" })
        guard case let .function(updateTool) = updateNamespaceTool else {
            return XCTFail("expected automation_update function")
        }
        XCTAssertEqual(updateTool.description, "Create or update automations.")
        XCTAssertNil(updateTool.deferLoading)
        XCTAssertEqual(
            updateTool.parameters,
            .object(
                properties: ["name": .string(description: nil)],
                required: ["name"],
                additionalProperties: .boolean(false)
            )
        )
    }

    func testBuildSpecsPreservesDynamicSlashNamespaceLikeRustExtensions() throws {
        let specs = ToolSpecFactory.buildSpecs(
            config: ToolsConfig(
                shellType: .disabled,
                applyPatchToolType: nil
            ),
            dynamicTools: [
                DynamicToolSpec(
                    namespace: "extension/",
                    name: "echo",
                    description: "Echoes arguments through an extension tool.",
                    inputSchema: .object(["type": .string("object"), "properties": .object([:])])
                )
            ]
        )

        let dynamicSpec = try XCTUnwrap(specs.first { $0.spec.name == "extension/" })
        guard case let .namespace(namespace) = dynamicSpec.spec else {
            return XCTFail("expected extension namespace")
        }
        XCTAssertEqual(namespace.name, "extension/")
        XCTAssertEqual(namespace.description, "Tools in the extension/ namespace.")
        XCTAssertEqual(namespace.tools.map(namespaceToolName), ["echo"])
    }

    func testBuildSpecsAppendsExtensionToolSpecsLikeRust() throws {
        let extensionTool = ConfiguredToolSpec(
            spec: .function(ResponsesAPITool(
                name: "extension_echo",
                description: "Echoes arguments through an extension tool.",
                parameters: .object(
                    properties: ["message": .string(description: "Message to echo.")],
                    required: ["message"],
                    additionalProperties: .boolean(false)
                )
            )),
            supportsParallelToolCalls: true
        )

        let specs = ToolSpecFactory.buildSpecs(
            config: ToolsConfig(shellType: .disabled),
            extensionToolSpecs: [extensionTool]
        )

        let configuredTool = try XCTUnwrap(specs.last)
        XCTAssertEqual(configuredTool, extensionTool)
        XCTAssertTrue(configuredTool.supportsParallelToolCalls)
    }

    func testExtensionToolSpecsDoNotReplaceBuiltinToolsLikeRust() throws {
        let extensionUpdatePlan = ConfiguredToolSpec(
            spec: .function(ResponsesAPITool(
                name: "update_plan",
                description: "Extension replacement that Rust must skip.",
                parameters: .object(properties: [:], required: nil, additionalProperties: .boolean(false))
            )),
            supportsParallelToolCalls: true
        )

        let specs = ToolSpecFactory.buildSpecs(
            config: ToolsConfig(shellType: .disabled),
            extensionToolSpecs: [extensionUpdatePlan]
        )

        XCTAssertEqual(specs.filter { $0.spec.name == "update_plan" }.count, 1)
        XCTAssertEqual(try functionTool(named: "update_plan", in: specs), try updatePlanTool())
        XCTAssertFalse(try XCTUnwrap(specs.first { $0.spec.name == "update_plan" }).supportsParallelToolCalls)
    }

    func testExtensionToolSpecsDoNotUseCodeModeReservedExecAndWaitLikeRust() throws {
        let extensionExec = ConfiguredToolSpec(
            spec: .function(ResponsesAPITool(
                name: "exec",
                description: "Extension replacement that Rust must skip while code mode is enabled.",
                parameters: .object(properties: [:], required: nil, additionalProperties: .boolean(false))
            )),
            supportsParallelToolCalls: true
        )
        let extensionWait = ConfiguredToolSpec(
            spec: .function(ResponsesAPITool(
                name: "wait",
                description: "Extension replacement that Rust must skip while code mode is enabled.",
                parameters: .object(properties: [:], required: nil, additionalProperties: .boolean(false))
            )),
            supportsParallelToolCalls: true
        )
        let extensionEcho = ConfiguredToolSpec(
            spec: .function(ResponsesAPITool(
                name: "extension_echo",
                description: "Echoes arguments through an extension tool.",
                parameters: .object(properties: [:], required: nil, additionalProperties: .boolean(false))
            )),
            supportsParallelToolCalls: true
        )

        let specs = ToolSpecFactory.buildSpecs(
            config: ToolsConfig(shellType: .disabled, codeModeEnabled: true),
            extensionToolSpecs: [extensionExec, extensionWait, extensionEcho]
        )

        XCTAssertEqual(specs.first { $0.spec.name == "exec" }?.spec, ToolSpecFactory.createCodeModeExecTool())
        XCTAssertEqual(specs.first { $0.spec.name == "wait" }?.spec, ToolSpecFactory.createCodeModeWaitTool())
        guard case let .function(echoTool)? = specs.last?.spec else {
            return XCTFail("expected extension_echo function tool")
        }
        XCTAssertEqual(echoTool.name, "extension_echo")
        XCTAssertTrue(echoTool.description.contains("Echoes arguments through an extension tool."))
        XCTAssertTrue(echoTool.description.contains("declare const tools: { extension_echo"))
    }

    func testCodeModeOnlyExposesMultiAgentV2AsDirectModelOnlyToolsLikeRust() throws {
        let specs = ToolSpecFactory.buildSpecs(config: ToolsConfig(
            shellType: .disabled,
            codeModeEnabled: true,
            codeModeOnlyEnabled: true,
            multiAgentV2Tools: true,
            multiAgentV2NonCodeModeOnly: true
        ))
        XCTAssertEqual(
            specs.map(\.spec.name),
            [
                "exec",
                "wait",
                "spawn_agent",
                "send_message",
                "followup_task",
                "wait_agent",
                "close_agent",
                "list_agents"
            ]
        )

        let execSpec = try XCTUnwrap(specs.first { $0.spec.name == "exec" }?.spec)
        guard case let .freeform(execTool) = execSpec else {
            return XCTFail("expected code-mode exec to be a freeform tool")
        }
        XCTAssertTrue(execTool.description.contains("Run JavaScript code"))
        XCTAssertTrue(execTool.format.definition.contains("pragma_source"))
        XCTAssertFalse(execTool.description.contains("spawn_agent"))
        XCTAssertFalse(execTool.description.contains("wait_agent"))
        XCTAssertFalse(execTool.description.contains("do not attempt to use any other tools directly"))

        guard case let .function(spawnAgent) = try XCTUnwrap(specs.first { $0.spec.name == "spawn_agent" }?.spec) else {
            return XCTFail("expected spawn_agent function tool")
        }
        XCTAssertFalse(spawnAgent.description.contains("exec tool declaration"))
    }

    func testCodeModeOnlyExecDescriptionIncludesHiddenNestedToolDetailsLikeRust() throws {
        let specs = ToolSpecFactory.buildSpecs(config: ToolsConfig(
            shellType: .disabled,
            codeModeEnabled: true,
            codeModeOnlyEnabled: true
        ))

        let execSpec = try XCTUnwrap(specs.first { $0.spec.name == "exec" }?.spec)
        guard case let .freeform(execTool) = execSpec else {
            return XCTFail("expected code-mode exec to be a freeform tool")
        }

        XCTAssertTrue(execTool.description.starts(with: "Run JavaScript code to orchestrate/compose tool calls"))
        XCTAssertTrue(execTool.description.contains("### `update_plan`"))
        XCTAssertTrue(execTool.description.contains("declare const tools: { update_plan(args:"))
        XCTAssertTrue(execTool.description.contains("### `view_image`"))
        XCTAssertTrue(execTool.description.contains("declare const tools: { view_image(args:"))
    }

    func testCodeModeAugmentsMCPNamespaceToolDescriptionsLikeRust() throws {
        let specs = ToolSpecFactory.buildSpecs(
            config: ToolsConfig(shellType: .disabled, namespaceTools: true, codeModeEnabled: true),
            mcpTools: [
                "mcp__sample__echo": McpTool(
                    name: "echo",
                    inputSchema: McpToolInputSchema(rawValue: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "message": .object(["type": .string("string")]),
                            "response-length": .object(["type": .string("integer")])
                        ]),
                        "required": .array([.string("message")]),
                        "additionalProperties": .bool(false)
                    ])),
                    description: "Echo text",
                    outputSchema: McpToolOutputSchema(
                        properties: .object([
                            "echo-value": .object(["type": .string("string")])
                        ]),
                        required: ["echo-value"]
                    )
                )
            ]
        )

        guard case let .namespace(namespace)? = specs.first(where: { $0.spec.name == "mcp__sample__" })?.spec,
              case let .function(echoTool)? = namespace.tools.first
        else {
            return XCTFail("expected namespaced MCP function tool")
        }

        XCTAssertEqual(echoTool.name, "echo")
        XCTAssertTrue(echoTool.description.contains("Echo text"))
        XCTAssertTrue(echoTool.description.contains(#"declare const tools: { mcp__sample__echo(args: { message: string; "response-length"?: number; }): Promise<CallToolResult<{ "echo-value": string; }>>;"#))
    }

    func testCodeModeOnlyExecDescriptionIncludesFullMCPPreambleLikeRust() throws {
        let specs = ToolSpecFactory.buildSpecs(
            config: ToolsConfig(
                shellType: .disabled,
                namespaceTools: true,
                codeModeEnabled: true,
                codeModeOnlyEnabled: true
            ),
            mcpTools: [
                "mcp__sample__echo": McpTool(
                    name: "echo",
                    inputSchema: McpToolInputSchema(rawValue: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "message": .object(["type": .string("string")])
                        ]),
                        "required": .array([.string("message")]),
                        "additionalProperties": .bool(false)
                    ])),
                    description: "Echo text",
                    outputSchema: McpToolOutputSchema(
                        properties: .object([
                            "echo": .object(["type": .string("string")])
                        ]),
                        required: ["echo"]
                    )
                )
            ]
        )

        let execSpec = try XCTUnwrap(specs.first { $0.spec.name == "exec" }?.spec)
        guard case let .freeform(execTool) = execSpec else {
            return XCTFail("expected code-mode exec to be a freeform tool")
        }

        XCTAssertTrue(execTool.description.contains("Shared MCP Types:"))
        XCTAssertTrue(execTool.description.contains("type Icon = {"))
        XCTAssertTrue(execTool.description.contains("type AudioContent = {"))
        XCTAssertTrue(execTool.description.contains("type ResourceLink = {"))
        XCTAssertTrue(execTool.description.contains("type EmbeddedResource = {"))
        XCTAssertTrue(execTool.description.contains("declare const tools: { mcp__sample__echo(args: { message: string; }): Promise<CallToolResult<{ echo: string; }>>; };"))
    }

    func testExtensionToolSpecsMayUseExecAndWaitWhenCodeModeIsDisabledLikeRust() throws {
        let extensionExec = ConfiguredToolSpec(
            spec: .function(ResponsesAPITool(
                name: "exec",
                description: "Extension exec tool.",
                parameters: .object(properties: [:], required: nil, additionalProperties: .boolean(false))
            )),
            supportsParallelToolCalls: true
        )
        let extensionWait = ConfiguredToolSpec(
            spec: .function(ResponsesAPITool(
                name: "wait",
                description: "Extension wait tool.",
                parameters: .object(properties: [:], required: nil, additionalProperties: .boolean(false))
            )),
            supportsParallelToolCalls: true
        )

        let specs = ToolSpecFactory.buildSpecs(
            config: ToolsConfig(shellType: .disabled, codeModeEnabled: false),
            extensionToolSpecs: [extensionExec, extensionWait]
        )

        XCTAssertEqual(specs.suffix(2), [extensionExec, extensionWait])
    }

    func testBuildSpecsExposesOnlyDirectDynamicToolsLikeRustExposure() throws {
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
                applyPatchToolType: nil
            ),
            dynamicTools: dynamicTools
        )

        let visibleNamespace = try XCTUnwrap(specs.first { $0.spec.name == "codex_app" }?.spec)
        guard case let .namespace(namespace) = visibleNamespace else {
            return XCTFail("expected visible namespace")
        }
        XCTAssertEqual(namespace.tools.map(namespaceToolName), ["visible_dynamic_tool"])
    }

    func testDynamicNamespaceToolsSortLikeRustSpecPlan() throws {
        let specs = ToolSpecFactory.buildSpecs(
            config: ToolsConfig(
                shellType: .disabled,
                applyPatchToolType: nil
            ),
            dynamicTools: [
                DynamicToolSpec(
                    namespace: "codex_app",
                    name: "zeta",
                    description: "Last alphabetically.",
                    inputSchema: .object(["type": .string("object"), "properties": .object([:])])
                ),
                DynamicToolSpec(
                    namespace: "codex_app",
                    name: "alpha",
                    description: "First alphabetically.",
                    inputSchema: .object(["type": .string("object"), "properties": .object([:])])
                )
            ]
        )

        let registeredNamespace = try XCTUnwrap(specs.first { $0.spec.name == "codex_app" }?.spec)
        guard case let .namespace(namespace) = registeredNamespace else {
            return XCTFail("expected registered namespace")
        }
        XCTAssertEqual(namespace.tools.map(namespaceToolName), ["alpha", "zeta"])
    }

    func testBuildSpecsKeepsDeferredDynamicToolsSearchOnlyLikeRustExposure() {
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
                applyPatchToolType: nil
            ),
            dynamicTools: dynamicTools
        )

        XCTAssertFalse(specs.contains { $0.spec.name == "codex_app" })
        XCTAssertFalse(specs.contains { $0.spec.name == "plain_dynamic_tool" })
        XCTAssertTrue(specs.contains { $0.spec.name == "tool_search" })
    }

    func testBuildSpecsHidesNamespacedDynamicToolsWhenNamespaceToolsDisabledLikeRust() {
        let specs = ToolSpecFactory.buildSpecs(
            config: ToolsConfig(
                shellType: .disabled,
                applyPatchToolType: nil,
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

    func testMCPToolSearchEntriesUseRustStructuralToolNameOrdering() {
        let entries = ToolSearchIndex.mcpEntries(from: [
            McpToolInfo(
                serverName: "alpha_a",
                tool: makeMcpTool(name: "tool"),
                callableNamespace: "mcp__alpha__a__",
                callableName: "tool"
            ),
            McpToolInfo(
                serverName: "alpha",
                tool: makeMcpTool(name: "z"),
                callableNamespace: "mcp__alpha__",
                callableName: "z"
            )
        ])

        XCTAssertEqual(entries.map(\.output.name), [
            "mcp__alpha__",
            "mcp__alpha__a__"
        ])
    }

    func testToolSearchIndexReturnsCoalescedDeferredMCPNamespace() throws {
        let index = ToolSearchIndex.mcpIndex(from: [
            McpToolInfo(serverName: "calendar", tool: makeMcpTool(name: "create_event", description: "Create events")),
            McpToolInfo(serverName: "calendar", tool: makeMcpTool(name: "list_events", description: "List events"))
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

    func testToolSearchIndexDerivesMCPIdentityFromToolInfoLikeRust() throws {
        let index = ToolSearchIndex.deferredToolIndex(
            mcpTools: [
                McpToolInfo(serverName: "docs", tool: makeMcpTool(name: "search", description: "Search docs")),
                McpToolInfo(serverName: "docs", tool: makeMcpTool(name: "search", description: "Duplicate docs")),
                McpToolInfo(serverName: "calendar", tool: makeMcpTool(name: "list_events", description: "List events"))
            ],
            dynamicTools: []
        )

        XCTAssertEqual(index.sourceInfos.map(\.name), ["calendar", "docs"])

        let tools = try index.search(arguments: .object([
            "query": .string("docs search"),
            "limit": .integer(8)
        ]))

        XCTAssertEqual(tools.count, 1)
        guard case let .object(namespace) = tools[0],
              case let .array(children)? = namespace["tools"]
        else {
            return XCTFail("expected namespace result")
        }
        XCTAssertEqual(namespace["name"], .string("mcp__docs__"))
        XCTAssertEqual(children.compactMap(toolName), ["search"])
    }

    func testToolSearchUsesRustSanitizedMCPCallableNames() throws {
        let index = ToolSearchIndex.deferredToolIndex(
            mcpTools: [
                McpToolInfo(serverName: "server.one", tool: makeMcpTool(name: "tool.two-three", description: "Search dotted tools"))
            ],
            dynamicTools: []
        )

        let tools = try index.search(arguments: .object([
            "query": .string("dotted tools"),
            "limit": .integer(8)
        ]))

        XCTAssertEqual(tools.count, 1)
        guard case let .object(namespace) = tools[0],
              case let .array(children)? = namespace["tools"]
        else {
            return XCTFail("expected namespace result")
        }
        XCTAssertEqual(namespace["name"], .string("mcp__server_one__"))
        XCTAssertEqual(children.compactMap(toolName), ["tool_two_three"])
    }

    func testToolSearchUsesMCPNamespaceDescriptionLikeRust() throws {
        let index = ToolSearchIndex.deferredToolIndex(
            mcpTools: [
                McpToolInfo(
                    serverName: "rmcp",
                    namespaceDescription: "Use this server for durable workspace notes.",
                    tool: makeMcpTool(name: "remember", description: "Store a note")
                )
            ],
            dynamicTools: []
        )

        let description = try XCTUnwrap(JSONObject(index.toolSpec())["description"] as? String)
        XCTAssertTrue(description.contains("- rmcp: Use this server for durable workspace notes."))

        let tools = try index.search(arguments: .object([
            "query": .string("durable workspace"),
            "limit": .integer(8)
        ]))

        XCTAssertEqual(tools.count, 1)
        guard case let .object(namespace) = tools[0] else {
            return XCTFail("expected namespace result")
        }
        XCTAssertEqual(namespace["name"], .string("mcp__rmcp__"))
        XCTAssertEqual(namespace["description"], .string("Use this server for durable workspace notes."))
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

    func testToolSearchOmittedLimitUsesDefaultResultLimitLikeRust() throws {
        let entries = (0..<20).map { index in
            makeToolSearchEntry(
                name: "computer_action_\(index)",
                searchText: "computer use action"
            )
        }
        let index = ToolSearchIndex(entries: entries)

        let tools = try index.search(arguments: .object([
            "query": .string("computer use")
        ]))

        XCTAssertEqual(tools.compactMap(toolName).count, ToolSearchIndex.defaultLimit)
        XCTAssertEqual(tools.compactMap(toolName).first, "computer_action_0")
        XCTAssertEqual(tools.compactMap(toolName).last, "computer_action_7")
    }

    func testToolSearchExplicitLimitControlsResultCountLikeRust() throws {
        let entries = (0..<12).map { index in
            makeToolSearchEntry(
                name: "docs_tool_\(index)",
                searchText: "calendar docs tool"
            )
        }
        let index = ToolSearchIndex(entries: entries)

        let defaultTools = try index.search(arguments: .object([
            "query": .string("calendar docs")
        ]))
        let explicitTools = try index.search(arguments: .object([
            "query": .string("calendar docs"),
            "limit": .integer(12)
        ]))

        XCTAssertEqual(defaultTools.compactMap(toolName).count, 8)
        XCTAssertEqual(explicitTools.compactMap(toolName).count, 12)
        XCTAssertEqual(explicitTools.compactMap(toolName).last, "docs_tool_11")
    }

    func testBuildSpecsHidesMCPNamespaceSpecsWhenNamespaceToolsDisabled() {
        let specs = ToolSpecFactory.buildSpecs(
            config: ToolsConfig(
                shellType: .disabled,
                applyPatchToolType: nil,
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

    func testMCPToolConversionPreservesArbitraryRustInputSchemaFields() throws {
        let spec = ToolSpecFactory.createMCPTool(
            fullyQualifiedName: "mcp__docs__search",
            tool: McpTool(
                name: "search",
                inputSchema: McpToolInputSchema(rawValue: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "query": .object([
                            "description": .string("Search query"),
                            "type": .string("string")
                        ])
                    ]),
                    "additionalProperties": .bool(false)
                ]))
            )
        )

        let object = try JSONObject(spec)
        let parameters = try XCTUnwrap(object["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["type"] as? String, "object")
        XCTAssertEqual(parameters["additionalProperties"] as? Bool, false)
        let properties = try XCTUnwrap(parameters["properties"] as? [String: Any])
        let query = try XCTUnwrap(properties["query"] as? [String: Any])
        XCTAssertEqual(query["description"] as? String, "Search query")
        XCTAssertEqual(query["type"] as? String, "string")
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

    func testMCPToolConversionPreservesOutputSchemaWithoutInferredTypeLikeRust() throws {
        let spec = ToolSpecFactory.createMCPTool(
            fullyQualifiedName: "mcp__docs__classify",
            tool: McpTool(
                name: "classify",
                inputSchema: McpToolInputSchema(),
                outputSchema: McpToolOutputSchema(rawValue: .object([
                    "enum": .array([.string("ok"), .string("error")])
                ]))
            )
        )

        guard case let .function(tool) = spec else {
            return XCTFail("expected function tool")
        }
        XCTAssertEqual(
            tool.outputSchema,
            ToolSpecFactory.mcpCallToolResultOutputSchema(
                structuredContentSchema: .object([
                    "enum": .array([.string("ok"), .string("error")])
                ])
            )
        )
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        String(data: try JSONEncoder().encode(value), encoding: .utf8)!
    }

    private func makeMcpTool(name: String, description: String? = nil) -> McpTool {
        McpTool(name: name, inputSchema: McpToolInputSchema(), description: description)
    }

    private func makeToolSearchEntry(name: String, searchText: String) -> ToolSearchEntry {
        ToolSearchEntry(
            searchText: searchText,
            output: .function(ResponsesAPITool(
                name: name,
                description: "Deferred \(name)",
                parameters: .object(properties: [:], required: nil, additionalProperties: .boolean(false))
            ))
        )
    }

    private func makeModelPreset(
        model: String,
        description: String = "Description.",
        defaultReasoningEffort: ReasoningEffort = .medium,
        supportedReasoningEfforts: [ReasoningEffort] = [],
        serviceTiers: [ModelServiceTier] = [],
        showInPicker: Bool = true
    ) -> ModelPreset {
        ModelPreset(
            id: model,
            model: model,
            displayName: model,
            description: description,
            defaultReasoningEffort: defaultReasoningEffort,
            supportedReasoningEfforts: supportedReasoningEfforts.map {
                ReasoningEffortPreset(effort: $0, description: "\($0.rawValue) effort")
            },
            serviceTiers: serviceTiers,
            isDefault: false,
            showInPicker: showInPicker,
            supportedInAPI: true
        )
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

    private func updatePlanTool() throws -> ResponsesAPITool {
        guard case let .function(function) = ToolSpecFactory.createPlanTool() else {
            throw NSError(domain: "ToolSpecTests", code: 2)
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
