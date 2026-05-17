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

    func testConfiguredPluginMcpToolApprovalSourcesDiscoverInstalledPluginServersWithoutRemotePluginFlagLikeRust() throws {
        let temp = try TemporaryCodexHome()
        try """
        [features]
        plugins = true
        remote_plugin = true

        [plugins."sample@test"]
        enabled = true

        [plugins."disabled@test"]
        enabled = false
        """.write(to: temp.configFile, atomically: true, encoding: .utf8)
        try writePluginMcpConfig(
            codexHome: temp.url,
            pluginID: "sample@test",
            version: "1.0.0",
            contents: """
            {
              "mcpServers": {
                "weather": {
                  "command": "weather-mcp"
                }
              }
            }
            """
        )
        try writePluginMcpConfig(
            codexHome: temp.url,
            pluginID: "disabled@test",
            version: "1.0.0",
            contents: """
            {
              "mcpServers": {
                "ignored": {
                  "command": "ignored-mcp"
                }
              }
            }
            """
        )
        let remotePluginRoot = try pluginCacheRoot(codexHome: temp.url, pluginID: "remote@market", version: "2.0.0")
        let manifestDirectory = remotePluginRoot.appendingPathComponent(".codex-plugin", isDirectory: true)
        let mcpDirectory = remotePluginRoot.appendingPathComponent("config", isDirectory: true)
        try FileManager.default.createDirectory(at: manifestDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mcpDirectory, withIntermediateDirectories: true)
        try #"{"name":"remote","mcpServers":"./config/mcp.json"}"#.write(
            to: manifestDirectory.appendingPathComponent("plugin.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try """
        {
          "radar": {
            "command": "radar-mcp"
          }
        }
        """.write(
            to: mcpDirectory.appendingPathComponent("mcp.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let stack = try userConfigLayerStack(codexHome: temp.url, config: .table([
            "features": .table([
                "plugins": .bool(true),
                "remote_plugin": .bool(false),
            ]),
            "plugins": .table([
                "sample@test": .table(["enabled": .bool(true)]),
                "disabled@test": .table(["enabled": .bool(false)]),
            ]),
        ]))

        XCTAssertEqual(
            McpToolApprovalPersistence.configuredPluginMcpToolApprovalSources(
                codexHome: temp.url,
                configLayerStack: stack,
                remoteInstalledPlugins: [
                    RemoteInstalledPluginReference(
                        marketplaceName: "market",
                        pluginName: "remote",
                        enabled: true
                    ),
                ]
            ),
            [
                PluginMcpToolApprovalSource(
                    pluginConfigName: "remote@market",
                    mcpServers: ["radar"]
                ),
                PluginMcpToolApprovalSource(
                    pluginConfigName: "sample@test",
                    mcpServers: ["weather"]
                ),
            ]
        )

        let pluginsDisabledStack = try userConfigLayerStack(codexHome: temp.url, config: .table([
            "features": .table([
                "plugins": .bool(false),
                "remote_plugin": .bool(true),
            ]),
        ]))
        XCTAssertTrue(McpToolApprovalPersistence.configuredPluginMcpToolApprovalSources(
            codexHome: temp.url,
            configLayerStack: pluginsDisabledStack,
            remoteInstalledPlugins: [
                RemoteInstalledPluginReference(
                    marketplaceName: "market",
                    pluginName: "remote",
                    enabled: true
                ),
            ]
        ).isEmpty)
    }

    func testPersistCustomMcpToolApprovalDiscoversConfiguredPluginServerLikeRust() throws {
        let temp = try TemporaryCodexHome()
        try """
        model = "gpt-5"

        [features]
        plugins = true

        [plugins."sample@test"]
        enabled = true
        """.write(to: temp.configFile, atomically: true, encoding: .utf8)
        try writePluginMcpConfig(
            codexHome: temp.url,
            pluginID: "sample@test",
            version: "1.0.0",
            contents: """
            {
              "mcpServers": {
                "weather": {
                  "command": "weather-mcp"
                }
              }
            }
            """
        )
        let stack = try userConfigLayerStack(codexHome: temp.url, config: .table([
            "features": .table(["plugins": .bool(true)]),
            "plugins": .table([
                "sample@test": .table(["enabled": .bool(true)]),
            ]),
        ]))

        try McpToolApprovalPersistence.persistCustomMcpToolApproval(
            codexHome: temp.url,
            serverName: "weather",
            toolName: "forecast/search",
            configLayerStack: stack
        )

        let contents = try String(contentsOf: temp.configFile, encoding: .utf8)
        XCTAssertTrue(contents.contains("model = \"gpt-5\""))
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

private func userConfigLayerStack(codexHome: URL, config: ConfigValue) throws -> ConfigLayerStack {
    try ConfigLayerStack(layers: [
        ConfigLayerEntry(
            name: .user(file: try AbsolutePath(
                absolutePath: codexHome.appendingPathComponent("config.toml", isDirectory: false).path
            )),
            config: config
        ),
    ])
}

private func writePluginMcpConfig(
    codexHome: URL,
    pluginID: String,
    version: String,
    contents: String
) throws {
    let pluginRoot = try pluginCacheRoot(codexHome: codexHome, pluginID: pluginID, version: version)
    try FileManager.default.createDirectory(at: pluginRoot, withIntermediateDirectories: true)
    try contents.write(
        to: pluginRoot.appendingPathComponent(".mcp.json", isDirectory: false),
        atomically: true,
        encoding: .utf8
    )
}

private func pluginCacheRoot(codexHome: URL, pluginID: String, version: String) throws -> URL {
    let parts = pluginID.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
    guard parts.count == 2 else {
        throw NSError(domain: "McpToolApprovalPersistenceTests", code: 1)
    }
    return codexHome
        .appendingPathComponent("plugins/cache", isDirectory: true)
        .appendingPathComponent(parts[1], isDirectory: true)
        .appendingPathComponent(parts[0], isDirectory: true)
        .appendingPathComponent(version, isDirectory: true)
}
