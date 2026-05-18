import XCTest
@testable import CodexCore

final class ToolDiscoveryTests: XCTestCase {
    func testDiscoverableToolEnumsUseExpectedWireNames() throws {
        try XCTAssertJSONObjectEqual(
            ToolDiscoveryEnumProbe(toolType: .connector, actionType: .install),
            [
                "tool_type": "connector",
                "action_type": "install"
            ]
        )
    }

    func testFilterRequestPluginInstallDiscoverableToolsForCodexTUIOmitsPlugins() {
        let connector = DiscoverableTool.connector(DiscoverableConnectorInfo(
            id: "connector_google_calendar",
            name: "Google Calendar",
            description: "Plan events and schedules.",
            installURL: "https://example.test/google-calendar",
            isAccessible: false,
            isEnabled: true
        ))
        let plugin = DiscoverableTool.plugin(DiscoverablePluginInfo(
            id: "slack@openai-curated",
            name: "Slack",
            description: "Search Slack messages",
            hasSkills: true,
            mcpServerNames: ["slack"],
            appConnectorIDs: ["connector_slack"]
        ))

        XCTAssertEqual(
            filterRequestPluginInstallDiscoverableToolsForClient(
                [connector, plugin],
                appServerClientName: "codex-tui"
            ),
            [connector]
        )
        XCTAssertEqual(
            filterRequestPluginInstallDiscoverableToolsForClient(
                [connector, plugin],
                appServerClientName: "codex-vscode"
            ),
            [connector, plugin]
        )
    }

    func testCollectRequestPluginInstallEntriesMatchesRustMapping() {
        let connector = DiscoverableTool.connector(DiscoverableConnectorInfo(
            id: "connector_google_calendar",
            name: "Google Calendar",
            description: "Plan events and schedules.",
            installURL: "https://example.test/google-calendar",
            isAccessible: false,
            isEnabled: true,
            pluginDisplayNames: ["Calendar Plugin"]
        ))
        let plugin = DiscoverableTool.plugin(DiscoverablePluginInfo(
            id: "slack@openai-curated",
            name: "Slack",
            description: "Search Slack messages",
            hasSkills: true,
            mcpServerNames: ["slack"],
            appConnectorIDs: ["connector_slack"]
        ))

        XCTAssertEqual(
            collectRequestPluginInstallEntries([connector, plugin]),
            [
                RequestPluginInstallEntry(
                    id: "connector_google_calendar",
                    name: "Google Calendar",
                    description: "Plan events and schedules.",
                    toolType: .connector,
                    hasSkills: false,
                    mcpServerNames: [],
                    appConnectorIDs: []
                ),
                RequestPluginInstallEntry(
                    id: "slack@openai-curated",
                    name: "Slack",
                    description: "Search Slack messages",
                    toolType: .plugin,
                    hasSkills: true,
                    mcpServerNames: ["slack"],
                    appConnectorIDs: ["connector_slack"]
                )
            ]
        )
    }

    func testPromptSafePluginDescriptionMatchesRustCapabilitySummary() {
        XCTAssertNil(promptSafePluginDescription(nil))
        XCTAssertNil(promptSafePluginDescription(" \n\t "))
        XCTAssertEqual(
            promptSafePluginDescription("  Reads\n\nlocal\tweather   and\r\ncalendars  "),
            "Reads local weather and calendars"
        )

        let longDescription = String(repeating: "a", count: maxPluginCapabilitySummaryDescriptionLength + 10)
        XCTAssertEqual(
            promptSafePluginDescription(longDescription),
            String(repeating: "a", count: maxPluginCapabilitySummaryDescriptionLength)
        )
    }

    func testCollectRequestPluginInstallEntriesNormalizesPluginDescriptionsLikeRust() {
        let plugin = DiscoverableTool.plugin(DiscoverablePluginInfo(
            id: "weather@local",
            name: "Weather",
            description: "  Reads\n\nlocal\tweather   ",
            hasSkills: true,
            mcpServerNames: [],
            appConnectorIDs: []
        ))

        XCTAssertEqual(
            collectRequestPluginInstallEntries([plugin]),
            [
                RequestPluginInstallEntry(
                    id: "weather@local",
                    name: "Weather",
                    description: "Reads local weather",
                    toolType: .plugin,
                    hasSkills: true,
                    mcpServerNames: [],
                    appConnectorIDs: []
                )
            ]
        )
    }

    func testAccessibleConnectorsFromMCPToolsCarriesPluginDisplayNames() {
        let tools = [
            "mcp__codex_apps__calendar_list_events": McpTool(
                name: "calendar_list_events",
                inputSchema: McpToolInputSchema(),
                connectorID: "calendar",
                pluginDisplayNames: ["sample", "sample"]
            ),
            "mcp__codex_apps__calendar_create_event": McpTool(
                name: "calendar_create_event",
                inputSchema: McpToolInputSchema(),
                connectorID: "calendar",
                connectorName: "Google Calendar",
                pluginDisplayNames: ["beta", "sample"]
            ),
            "mcp__sample__echo": McpTool(
                name: "echo",
                inputSchema: McpToolInputSchema(),
                connectorID: "ignored",
                connectorName: "Ignored",
                pluginDisplayNames: ["ignored"]
            )
        ]

        XCTAssertEqual(
            accessibleConnectorsFromMCPTools(tools),
            [
                DiscoverableConnectorInfo(
                    id: "calendar",
                    name: "Google Calendar",
                    installURL: "https://chatgpt.com/apps/google-calendar/calendar",
                    isAccessible: true,
                    isEnabled: true,
                    pluginDisplayNames: ["beta", "sample"]
                )
            ]
        )
    }

    func testAccessibleConnectorsFromMCPToolsPreservesDescriptionAndSlashQualifiedServerNames() {
        let tools = [
            "codex_apps/calendar_create_event": McpTool(
                name: "calendar_create_event",
                inputSchema: McpToolInputSchema(),
                connectorID: "calendar",
                connectorName: "Calendar",
                namespaceDescription: "Plan events"
            )
        ]

        XCTAssertEqual(
            accessibleConnectorsFromMCPTools(tools),
            [
                DiscoverableConnectorInfo(
                    id: "calendar",
                    name: "Calendar",
                    description: "Plan events",
                    installURL: "https://chatgpt.com/apps/calendar/calendar",
                    isAccessible: true,
                    isEnabled: true
                )
            ]
        )
    }

    func testAccessibleConnectorsFromMCPToolsUsesRustInstallURLSlugs() {
        let tools = [
            "mcp__codex_apps__punctuation": McpTool(
                name: "punctuation",
                inputSchema: McpToolInputSchema(),
                connectorID: "connector_punctuation",
                connectorName: "A + B"
            ),
            "mcp__codex_apps__symbol": McpTool(
                name: "symbol",
                inputSchema: McpToolInputSchema(),
                connectorID: "connector_symbol",
                connectorName: "$$$"
            )
        ]

        let connectors = accessibleConnectorsFromMCPTools(tools)

        XCTAssertEqual(
            connectors.map { $0.installURL },
            [
                "https://chatgpt.com/apps/app/connector_symbol",
                "https://chatgpt.com/apps/a---b/connector_punctuation"
            ]
        )
    }

    func testFilterDisallowedConnectorsMatchesRustOriginatorRules() {
        let connectors = [
            DiscoverableConnectorInfo(
                id: "alpha",
                name: "Alpha",
                isAccessible: false,
                isEnabled: true
            ),
            DiscoverableConnectorInfo(
                id: "connector_openai_hidden",
                name: "OpenAI Hidden",
                isAccessible: false,
                isEnabled: true
            ),
            DiscoverableConnectorInfo(
                id: "asdk_app_6938a94a61d881918ef32cb999ff937c",
                name: "Default Hidden",
                isAccessible: false,
                isEnabled: true
            ),
            DiscoverableConnectorInfo(
                id: "connector_0f9c9d4592e54d0a9a12b3f44a1e2010",
                name: "First Party Hidden",
                isAccessible: false,
                isEnabled: true
            )
        ]

        XCTAssertEqual(
            filterDisallowedConnectors(connectors, originatorValue: "codex_cli").map(\.id),
            ["alpha", "connector_openai_hidden", "connector_0f9c9d4592e54d0a9a12b3f44a1e2010"]
        )
        XCTAssertEqual(
            filterDisallowedConnectors(connectors, originatorValue: "codex_chatgpt_desktop").map(\.id),
            ["alpha", "connector_openai_hidden", "asdk_app_6938a94a61d881918ef32cb999ff937c"]
        )
    }

    func testFilterToolSuggestDiscoverableConnectorsKeepsPluginBackedUninstalledApps() {
        let directoryConnectors = [
            DiscoverableConnectorInfo(
                id: "connector_gamma",
                name: "Gamma",
                isAccessible: false,
                isEnabled: true
            ),
            DiscoverableConnectorInfo(
                id: "connector_alpha",
                name: "Alpha",
                isAccessible: false,
                isEnabled: true
            ),
            DiscoverableConnectorInfo(
                id: "connector_beta",
                name: "Beta",
                isAccessible: false,
                isEnabled: true
            ),
            DiscoverableConnectorInfo(
                id: "connector_openai_hidden",
                name: "OpenAI Hidden",
                isAccessible: false,
                isEnabled: true
            )
        ]
        let accessibleConnectors = [
            DiscoverableConnectorInfo(
                id: "connector_beta",
                name: "Beta",
                isAccessible: true,
                isEnabled: false
            )
        ]

        let filtered = filterToolSuggestDiscoverableConnectors(
            directoryConnectors: directoryConnectors,
            accessibleConnectors: accessibleConnectors,
            discoverableConnectorIDs: ["connector_gamma", "connector_alpha", "connector_beta", "connector_openai_hidden"],
            originatorValue: "codex_cli"
        )

        XCTAssertEqual(filtered.map(\.id), ["connector_alpha", "connector_gamma", "connector_openai_hidden"])
    }

    func testToolSuggestConnectorIDsIncludeConfiguredDiscoverables() {
        let ids = toolSuggestConnectorIDs(
            pluginConnectorIDs: [],
            toolSuggest: ToolSuggestConfig(discoverables: [
                ToolSuggestDiscoverable(
                    type: .connector,
                    id: "connector_2128aebfecb84f64a069897515042a44"
                ),
                ToolSuggestDiscoverable(type: .plugin, id: "slack@openai-curated"),
                ToolSuggestDiscoverable(type: .connector, id: "   ")
            ])
        )

        XCTAssertEqual(ids, ["connector_2128aebfecb84f64a069897515042a44"])
    }

    func testToolSuggestConnectorIDsExcludeDisabledToolSuggestions() {
        let ids = toolSuggestConnectorIDs(
            pluginConnectorIDs: ["connector_calendar"],
            toolSuggest: ToolSuggestConfig(
                discoverables: [
                    ToolSuggestDiscoverable(type: .connector, id: "connector_gmail")
                ],
                disabledTools: [
                    ToolSuggestDisabledTool(type: .connector, id: "connector_calendar"),
                    ToolSuggestDisabledTool(type: .plugin, id: "slack@openai-curated")
                ]
            )
        )

        XCTAssertEqual(ids, ["connector_gmail"])
    }

    func testFilterToolSuggestDiscoverablePluginsMatchesRustSelectionRules() {
        let candidates = [
            DiscoverablePluginInfo(
                id: "sample@openai-curated",
                name: "Sample",
                description: "Configured plugin",
                hasSkills: true,
                mcpServerNames: ["sample-docs"],
                appConnectorIDs: ["connector_calendar"]
            ),
            DiscoverablePluginInfo(
                id: "slack@openai-curated",
                name: "Slack",
                description: "Allowlisted plugin",
                hasSkills: true,
                mcpServerNames: ["slack"],
                appConnectorIDs: []
            ),
            DiscoverablePluginInfo(
                id: "openai-developers@openai-curated",
                name: "OpenAI Developers",
                description: "Allowlisted developer plugin",
                hasSkills: true,
                mcpServerNames: ["openai-developers"],
                appConnectorIDs: []
            ),
            DiscoverablePluginInfo(
                id: "installed@openai-curated",
                name: "Installed",
                description: nil,
                hasSkills: false,
                mcpServerNames: [],
                appConnectorIDs: []
            ),
            DiscoverablePluginInfo(
                id: "other@openai-curated",
                name: "Other",
                description: nil,
                hasSkills: false,
                mcpServerNames: [],
                appConnectorIDs: []
            )
        ]

        let filtered = filterToolSuggestDiscoverablePlugins(
            candidates: candidates,
            installedPluginIDs: ["installed@openai-curated"],
            allowlistedPluginIDs: toolSuggestDiscoverablePluginAllowlist,
            toolSuggest: ToolSuggestConfig(
                discoverables: [
                    ToolSuggestDiscoverable(type: .plugin, id: "sample@openai-curated")
                ],
                disabledTools: [
                    ToolSuggestDisabledTool(type: .plugin, id: "other@openai-curated")
                ]
            ),
            pluginsEnabled: true
        )

        XCTAssertEqual(
            filtered.map(\.id),
            [
                "openai-developers@openai-curated",
                "sample@openai-curated",
                "slack@openai-curated"
            ]
        )
    }

    func testFilterToolSuggestDiscoverablePluginsOmitsDisabledAndFeatureDisabled() {
        let slack = DiscoverablePluginInfo(
            id: "slack@openai-curated",
            name: "Slack",
            description: nil,
            hasSkills: true,
            mcpServerNames: [],
            appConnectorIDs: []
        )

        XCTAssertEqual(
            filterToolSuggestDiscoverablePlugins(
                candidates: [slack],
                installedPluginIDs: [],
                allowlistedPluginIDs: ["slack@openai-curated"],
                toolSuggest: ToolSuggestConfig(disabledTools: [
                    ToolSuggestDisabledTool(type: .plugin, id: "slack@openai-curated")
                ]),
                pluginsEnabled: true
            ),
            []
        )
        XCTAssertEqual(
            filterToolSuggestDiscoverablePlugins(
                candidates: [slack],
                installedPluginIDs: [],
                allowlistedPluginIDs: ["slack@openai-curated"],
                toolSuggest: ToolSuggestConfig(),
                pluginsEnabled: false
            ),
            []
        )
    }

    func testBuildRequestPluginInstallElicitationRequestUsesExpectedShape() throws {
        let args = RequestPluginInstallArgs(
            toolType: .connector,
            actionType: .install,
            toolID: "connector_2128aebfecb84f64a069897515042a44",
            suggestReason: "Plan and reference events from your calendar"
        )
        let connector = DiscoverableTool.connector(DiscoverableConnectorInfo(
            id: "connector_2128aebfecb84f64a069897515042a44",
            name: "Google Calendar",
            description: "Plan events and schedules.",
            installURL: "https://chatgpt.com/apps/google-calendar/connector_2128aebfecb84f64a069897515042a44",
            isAccessible: false,
            isEnabled: true
        ))

        let request = try buildRequestPluginInstallElicitationRequest(
            serverName: "codex-apps",
            threadID: "thread-1",
            turnID: "turn-1",
            args: args,
            suggestReason: "Plan and reference events from your calendar",
            tool: connector
        )

        try XCTAssertJSONObjectEqual(request, [
            "threadId": "thread-1",
            "turnId": "turn-1",
            "serverName": "codex-apps",
            "mode": "form",
            "_meta": [
                "codex_approval_kind": "tool_suggestion",
                "persist": "always",
                "tool_type": "connector",
                "suggest_type": "install",
                "suggest_reason": "Plan and reference events from your calendar",
                "tool_id": "connector_2128aebfecb84f64a069897515042a44",
                "tool_name": "Google Calendar",
                "install_url": "https://chatgpt.com/apps/google-calendar/connector_2128aebfecb84f64a069897515042a44"
            ],
            "message": "Plan and reference events from your calendar",
            "requestedSchema": [
                "type": "object",
                "properties": [:]
            ]
        ])
    }

    func testBuildRequestPluginInstallElicitationRequestForPluginOmitsInstallURL() throws {
        let args = RequestPluginInstallArgs(
            toolType: .plugin,
            actionType: .install,
            toolID: "sample@openai-curated",
            suggestReason: "Use the sample plugin's skills and MCP server"
        )
        let plugin = DiscoverableTool.plugin(DiscoverablePluginInfo(
            id: "sample@openai-curated",
            name: "Sample Plugin",
            description: "Includes skills, MCP servers, and apps.",
            hasSkills: true,
            mcpServerNames: ["sample-docs"],
            appConnectorIDs: ["connector_calendar"]
        ))

        let request = try buildRequestPluginInstallElicitationRequest(
            serverName: "codex-apps",
            threadID: "thread-1",
            turnID: "turn-1",
            args: args,
            suggestReason: "Use the sample plugin's skills and MCP server",
            tool: plugin
        )

        guard case let .form(meta, message, requestedSchema) = request.request else {
            return XCTFail("expected form request")
        }
        XCTAssertEqual(message, "Use the sample plugin's skills and MCP server")
        XCTAssertEqual(requestedSchema, AppServerProtocol.McpElicitationSchema(properties: [:]))
        guard case let .object(metaObject)? = meta else {
            return XCTFail("expected metadata object")
        }
        XCTAssertNil(metaObject["install_url"])
        XCTAssertEqual(metaObject["tool_type"], .string("plugin"))
        XCTAssertEqual(metaObject["tool_name"], .string("Sample Plugin"))
    }

    func testRequestPluginInstallResponsePersistsOnlyDeclineAlwaysMode() {
        XCTAssertTrue(requestPluginInstallResponseRequestsPersistentDisable(
            action: "decline",
            meta: .object([requestPluginInstallPersistKey: .string(requestPluginInstallPersistAlwaysValue)])
        ))
        XCTAssertFalse(requestPluginInstallResponseRequestsPersistentDisable(
            action: "accept",
            meta: .object([requestPluginInstallPersistKey: .string(requestPluginInstallPersistAlwaysValue)])
        ))
        XCTAssertFalse(requestPluginInstallResponseRequestsPersistentDisable(
            action: "decline",
            meta: .object([requestPluginInstallPersistKey: .string("session")])
        ))
        XCTAssertFalse(requestPluginInstallResponseRequestsPersistentDisable(
            action: "decline",
            meta: nil
        ))
    }

    func testPersistDisabledInstallRequestWritesConnectorConfig() throws {
        let dir = try ToolDiscoveryTemporaryDirectory()
        let tool = DiscoverableTool.connector(DiscoverableConnectorInfo(
            id: "connector_calendar",
            name: "Google Calendar",
            isAccessible: false,
            isEnabled: true
        ))

        try persistDisabledInstallRequest(codexHome: dir.url, tool: tool)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)
        XCTAssertEqual(
            config.toolSuggest,
            ToolSuggestConfig(disabledTools: [
                ToolSuggestDisabledTool(type: .connector, id: "connector_calendar")
            ])
        )
    }

    func testPersistDisabledInstallRequestWritesPluginConfig() throws {
        let dir = try ToolDiscoveryTemporaryDirectory()
        let tool = DiscoverableTool.plugin(DiscoverablePluginInfo(
            id: "slack@openai-curated",
            name: "Slack",
            description: nil,
            hasSkills: true,
            mcpServerNames: [],
            appConnectorIDs: []
        ))

        try persistDisabledInstallRequest(codexHome: dir.url, tool: tool)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)
        XCTAssertEqual(
            config.toolSuggest,
            ToolSuggestConfig(disabledTools: [
                ToolSuggestDisabledTool(type: .plugin, id: "slack@openai-curated")
            ])
        )
    }

    func testPersistDisabledInstallRequestDedupesExistingDisabledTools() throws {
        let dir = try ToolDiscoveryTemporaryDirectory()
        try """
        [tool_suggest]
        discoverables = [{ type = "plugin", id = "sample@openai-curated" }]

        [[tool_suggest.disabled_tools]]
        type = "connector"
        id = " connector_calendar "

        [[tool_suggest.disabled_tools]]
        type = "connector"
        id = "connector_calendar"

        [[tool_suggest.disabled_tools]]
        type = "connector"
        id = "   "

        [[tool_suggest.disabled_tools]]
        type = "plugin"
        id = "slack@openai-curated"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let tool = DiscoverableTool.connector(DiscoverableConnectorInfo(
            id: "connector_calendar",
            name: "Google Calendar",
            isAccessible: false,
            isEnabled: true
        ))

        try persistDisabledInstallRequest(codexHome: dir.url, tool: tool)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)
        XCTAssertEqual(
            config.toolSuggest,
            ToolSuggestConfig(
                discoverables: [
                    ToolSuggestDiscoverable(type: .plugin, id: "sample@openai-curated")
                ],
                disabledTools: [
                    ToolSuggestDisabledTool(type: .connector, id: "connector_calendar"),
                    ToolSuggestDisabledTool(type: .plugin, id: "slack@openai-curated")
                ]
            )
        )
    }

    func testConnectorCompletionRequiresAccessibleConnector() {
        let accessibleConnectors = [
            DiscoverableConnectorInfo(
                id: "calendar",
                name: "Google Calendar",
                isAccessible: true,
                isEnabled: false
            )
        ]

        XCTAssertTrue(verifiedConnectorInstallCompleted(
            toolID: "calendar",
            accessibleConnectors: accessibleConnectors
        ))
        XCTAssertFalse(verifiedConnectorInstallCompleted(
            toolID: "gmail",
            accessibleConnectors: accessibleConnectors
        ))
        XCTAssertTrue(allRequestedConnectorsPickedUp(
            expectedConnectorIDs: ["calendar"],
            accessibleConnectors: accessibleConnectors
        ))
        XCTAssertFalse(allRequestedConnectorsPickedUp(
            expectedConnectorIDs: ["calendar", "gmail"],
            accessibleConnectors: accessibleConnectors
        ))
    }
}

private struct ToolDiscoveryEnumProbe: Encodable {
    let toolType: DiscoverableToolType
    let actionType: DiscoverableToolAction

    private enum CodingKeys: String, CodingKey {
        case toolType = "tool_type"
        case actionType = "action_type"
    }
}

private final class ToolDiscoveryTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ToolDiscoveryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
