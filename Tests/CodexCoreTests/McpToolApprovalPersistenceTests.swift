import XCTest
@testable import CodexCore

final class McpToolApprovalPersistenceTests: XCTestCase {
    func testPersistCodexAppToolApprovalWritesRustToolOverride() throws {
        let temp = try TemporaryCodexHome()

        try McpToolApprovalPersistence.persistCodexAppToolApproval(
            codexHome: temp.url,
            connectorID: "calendar",
            toolName: "calendar/list_events"
        )

        let contents = try String(contentsOf: temp.configFile, encoding: .utf8)
        XCTAssertTrue(contents.contains("[apps.calendar]"))
        XCTAssertTrue(contents.contains("enabled = true"))
        XCTAssertTrue(contents.contains("[apps.calendar.tools.\"calendar/list_events\"]"))
        XCTAssertTrue(contents.contains("approval_mode = \"approve\""))
    }

    func testPersistCodexAppToolApprovalReplacesExistingModeAndPreservesOtherConfig() throws {
        let temp = try TemporaryCodexHome()
        try """
        model = "gpt-5"

        [apps.calendar]
        enabled = false

        [apps.calendar.tools."calendar/list_events"]
        approval_mode = "prompt"
        """.write(to: temp.configFile, atomically: true, encoding: .utf8)

        try McpToolApprovalPersistence.persistCodexAppToolApproval(
            codexHome: temp.url,
            connectorID: "calendar",
            toolName: "calendar/list_events"
        )

        let contents = try String(contentsOf: temp.configFile, encoding: .utf8)
        XCTAssertTrue(contents.contains("model = \"gpt-5\""))
        XCTAssertTrue(contents.contains("[apps.calendar]\nenabled = true"))
        XCTAssertTrue(contents.contains("[apps.calendar.tools.\"calendar/list_events\"]\napproval_mode = \"approve\""))
        XCTAssertFalse(contents.contains("enabled = false"))
        XCTAssertFalse(contents.contains("approval_mode = \"prompt\""))
    }

    func testPersistCustomMcpToolApprovalWritesToolOverride() throws {
        let temp = try TemporaryCodexHome()
        try """
        [mcp_servers.docs]
        command = "docs-server"
        """.write(to: temp.configFile, atomically: true, encoding: .utf8)

        try McpToolApprovalPersistence.persistCustomMcpToolApproval(
            codexHome: temp.url,
            serverName: "docs",
            toolName: "search"
        )

        let contents = try String(contentsOf: temp.configFile, encoding: .utf8)
        XCTAssertTrue(contents.contains("[mcp_servers.docs.tools.search]"))
        XCTAssertTrue(contents.contains("approval_mode = \"approve\""))

        let loaded = try McpConfigStore.loadGlobalMcpServers(codexHome: temp.url)
        XCTAssertEqual(loaded["docs"]?.tools["search"]?.approvalMode, .approve)
    }

    func testPersistCustomMcpToolApprovalPrefersProjectLayerLikeRust() throws {
        let temp = try TemporaryCodexHome()
        let project = temp.url.appendingPathComponent("project/.codex", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try """
        model = "gpt-5"

        [mcp_servers.docs]
        command = "project-docs"
        """.write(to: project.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        try """
        [mcp_servers.docs]
        command = "global-docs"
        """.write(to: temp.configFile, atomically: true, encoding: .utf8)

        let stack = try ConfigLayerStack(layers: [
            ConfigLayerEntry(
                name: .user(file: try AbsolutePath(absolutePath: temp.configFile.path)),
                config: .table([
                    "mcp_servers": .table([
                        "docs": .table([
                            "command": .string("global-docs"),
                        ]),
                    ]),
                ])
            ),
            ConfigLayerEntry(
                name: .project(dotCodexFolder: try AbsolutePath(absolutePath: project.path)),
                config: .table([
                    "mcp_servers": .table([
                        "docs": .table([
                            "command": .string("project-docs"),
                        ]),
                    ]),
                ])
            ),
        ])

        try McpToolApprovalPersistence.persistCustomMcpToolApproval(
            codexHome: temp.url,
            serverName: "docs",
            toolName: "search",
            configLayerStack: stack
        )

        let projectContents = try String(
            contentsOf: project.appendingPathComponent("config.toml"),
            encoding: .utf8
        )
        let globalContents = try String(contentsOf: temp.configFile, encoding: .utf8)
        XCTAssertTrue(projectContents.contains("model = \"gpt-5\""))
        XCTAssertTrue(projectContents.contains("[mcp_servers.docs.tools.search]"))
        XCTAssertTrue(projectContents.contains("approval_mode = \"approve\""))
        XCTAssertFalse(globalContents.contains("approval_mode = \"approve\""))
    }

    func testPersistCustomMcpToolApprovalUsesHighestPrecedenceProjectLayerLikeRust() throws {
        let temp = try TemporaryCodexHome()
        let rootProject = temp.url.appendingPathComponent("repo/.codex", isDirectory: true)
        let childProject = temp.url.appendingPathComponent("repo/child/.codex", isDirectory: true)
        try FileManager.default.createDirectory(at: rootProject, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: childProject, withIntermediateDirectories: true)
        try """
        [mcp_servers.docs]
        command = "root-docs"
        """.write(to: rootProject.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        try """
        [mcp_servers.docs]
        command = "child-docs"
        """.write(to: childProject.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let stack = try ConfigLayerStack(layers: [
            ConfigLayerEntry(
                name: .project(dotCodexFolder: try AbsolutePath(absolutePath: rootProject.path)),
                config: .table([
                    "mcp_servers": .table([
                        "docs": .table([
                            "command": .string("root-docs"),
                        ]),
                    ]),
                ])
            ),
            ConfigLayerEntry(
                name: .project(dotCodexFolder: try AbsolutePath(absolutePath: childProject.path)),
                config: .table([
                    "mcp_servers": .table([
                        "docs": .table([
                            "command": .string("child-docs"),
                        ]),
                    ]),
                ])
            ),
        ])

        try McpToolApprovalPersistence.persistCustomMcpToolApproval(
            codexHome: temp.url,
            serverName: "docs",
            toolName: "search",
            configLayerStack: stack
        )

        let childContents = try String(
            contentsOf: childProject.appendingPathComponent("config.toml"),
            encoding: .utf8
        )
        let rootContents = try String(
            contentsOf: rootProject.appendingPathComponent("config.toml"),
            encoding: .utf8
        )
        XCTAssertTrue(childContents.contains("[mcp_servers.docs.tools.search]"))
        XCTAssertFalse(rootContents.contains("approval_mode = \"approve\""))
    }

    func testPersistCustomMcpToolApprovalRejectsUnknownServerLikeRust() throws {
        let temp = try TemporaryCodexHome()

        XCTAssertThrowsError(try McpToolApprovalPersistence.persistCustomMcpToolApproval(
            codexHome: temp.url,
            serverName: "docs",
            toolName: "search"
        )) { error in
            XCTAssertEqual(
                String(describing: error),
                "MCP server `docs` is not configured in config.toml"
            )
        }
    }

    func testPersistCustomMcpToolApprovalWritesEnabledPluginOverrideLikeRust() throws {
        let temp = try TemporaryCodexHome()
        try """
        model = "gpt-5"

        [plugins."sample@test"]
        enabled = true
        """.write(to: temp.configFile, atomically: true, encoding: .utf8)

        try McpToolApprovalPersistence.persistCustomMcpToolApproval(
            codexHome: temp.url,
            serverName: "weather",
            toolName: "forecast/search",
            enabledPluginMcpServerSources: [
                PluginMcpToolApprovalSource(
                    pluginConfigName: "sample@test",
                    mcpServers: ["weather"]
                ),
            ]
        )

        let contents = try String(contentsOf: temp.configFile, encoding: .utf8)
        XCTAssertTrue(contents.contains("model = \"gpt-5\""))
        XCTAssertTrue(contents.contains("[plugins.\"sample@test\"]\nenabled = true"))
        XCTAssertTrue(contents.contains("[plugins.\"sample@test\".mcp_servers.weather.tools.\"forecast/search\"]"))
        XCTAssertTrue(contents.contains("approval_mode = \"approve\""))
    }

    func testPersistCustomMcpToolApprovalPrefersConfiguredServerOverPluginLikeRust() throws {
        let temp = try TemporaryCodexHome()
        try """
        [mcp_servers.weather]
        command = "local-weather"

        [plugins."sample@test"]
        enabled = true
        """.write(to: temp.configFile, atomically: true, encoding: .utf8)

        try McpToolApprovalPersistence.persistCustomMcpToolApproval(
            codexHome: temp.url,
            serverName: "weather",
            toolName: "search",
            enabledPluginMcpServerSources: [
                PluginMcpToolApprovalSource(
                    pluginConfigName: "sample@test",
                    mcpServers: ["weather"]
                ),
            ]
        )

        let contents = try String(contentsOf: temp.configFile, encoding: .utf8)
        XCTAssertTrue(contents.contains("[mcp_servers.weather.tools.search]"))
        XCTAssertFalse(contents.contains("[plugins.\"sample@test\".mcp_servers.weather.tools.search]"))
    }

    func testPersistCustomMcpToolApprovalRejectsUnknownPluginBackedServerLikeRust() throws {
        let temp = try TemporaryCodexHome()

        XCTAssertThrowsError(try McpToolApprovalPersistence.persistCustomMcpToolApproval(
            codexHome: temp.url,
            serverName: "weather",
            toolName: "search",
            enabledPluginMcpServerSources: [
                PluginMcpToolApprovalSource(
                    pluginConfigName: "sample@test",
                    mcpServers: ["docs"]
                ),
            ]
        )) { error in
            XCTAssertEqual(
                String(describing: error),
                "MCP server `weather` is not configured in config.toml or an enabled plugin"
            )
        }
    }

    func testPersistMcpToolApprovalDispatchesCodexAppsAndRequiresConnectorID() throws {
        let temp = try TemporaryCodexHome()

        try McpToolApprovalPersistence.persistMcpToolApproval(
            codexHome: temp.url,
            key: McpToolApprovalKey(
                server: codexAppsMCPServerName,
                connectorID: "calendar",
                toolName: "calendar/list_events"
            )
        )
        var contents = try String(contentsOf: temp.configFile, encoding: .utf8)
        XCTAssertTrue(contents.contains("[apps.calendar.tools.\"calendar/list_events\"]"))

        XCTAssertThrowsError(try McpToolApprovalPersistence.persistMcpToolApproval(
            codexHome: temp.url,
            key: McpToolApprovalKey(
                server: codexAppsMCPServerName,
                connectorID: nil,
                toolName: "calendar/list_events"
            )
        )) { error in
            XCTAssertEqual(
                String(describing: error),
                "codex_apps MCP tool approval persistence requires a connector_id"
            )
        }

        try """
        [mcp_servers.docs]
        command = "docs-server"
        """.write(to: temp.configFile, atomically: true, encoding: .utf8)
        try McpToolApprovalPersistence.persistMcpToolApproval(
            codexHome: temp.url,
            key: McpToolApprovalKey(server: "docs", connectorID: nil, toolName: "search")
        )
        contents = try String(contentsOf: temp.configFile, encoding: .utf8)
        XCTAssertTrue(contents.contains("[mcp_servers.docs.tools.search]"))
    }
}

private final class TemporaryCodexHome {
    let url: URL

    var configFile: URL {
        url.appendingPathComponent("config.toml", isDirectory: false)
    }

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-swift-mcp-tool-approval-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
