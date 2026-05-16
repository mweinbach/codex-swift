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
