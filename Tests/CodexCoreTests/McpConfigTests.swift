import CodexCore
import XCTest

final class McpConfigTests: XCTestCase {
    func testLoadGlobalMcpServersReturnsEmptyWhenConfigIsMissing() throws {
        let temp = try McpConfigTemporaryDirectory()

        XCTAssertEqual(try McpConfigStore.loadGlobalMcpServers(codexHome: temp.url), [:])
    }

    func testParseGlobalMcpServersSupportsStdioAndStreamableHTTP() throws {
        let servers = try McpConfigStore.parseMcpServers(from: """
        [mcp_servers.docs]
        command = "docs-server"
        args = ["--port", "4000"]
        env_vars = ["APP_TOKEN"]
        startup_timeout_ms = 2500

        [mcp_servers.docs.env]
        TOKEN = "secret"

        [mcp_servers.github]
        url = "https://example.com/mcp"
        bearer_token_env_var = "GITHUB_TOKEN"
        tool_timeout_sec = 5.5
        enabled_tools = ["search"]

        [mcp_servers.github.http_headers]
        X_Static = "value"

        [mcp_servers.github.env_http_headers]
        Authorization = "TOKEN_ENV"
        """)

        XCTAssertEqual(
            servers["docs"],
            McpServerConfig(
                transport: .stdio(
                    command: "docs-server",
                    args: ["--port", "4000"],
                    env: ["TOKEN": "secret"],
                    envVars: ["APP_TOKEN"],
                    cwd: nil
                ),
                startupTimeoutSec: 2.5
            )
        )
        XCTAssertEqual(
            servers["github"],
            McpServerConfig(
                transport: .streamableHttp(
                    url: "https://example.com/mcp",
                    bearerTokenEnvVar: "GITHUB_TOKEN",
                    httpHeaders: ["X_Static": "value"],
                    envHttpHeaders: ["Authorization": "TOKEN_ENV"]
                ),
                toolTimeoutSec: 5.5,
                enabledTools: ["search"]
            )
        )
    }

    func testReplaceGlobalMcpServersPreservesUnrelatedConfigAndSerializesSorted() throws {
        let temp = try McpConfigTemporaryDirectory()
        let configFile = temp.url.appendingPathComponent("config.toml")
        try """
        model = "gpt-5"

        [mcp_servers.old]
        command = "old"

        [features]
        web_search = true
        """.write(to: configFile, atomically: true, encoding: .utf8)

        try McpConfigStore.replaceGlobalMcpServers(codexHome: temp.url, servers: [
            "docs": McpServerConfig(
                transport: .stdio(
                    command: "docs-server",
                    args: ["--verbose"],
                    env: ["ZIG_VAR": "3", "ALPHA_VAR": "1"],
                    envVars: [],
                    cwd: nil
                )
            ),
            "http": McpServerConfig(
                transport: .streamableHttp(
                    url: "https://example.com/mcp",
                    bearerTokenEnvVar: "MCP_TOKEN",
                    httpHeaders: nil,
                    envHttpHeaders: nil
                ),
                startupTimeoutSec: 2
            )
        ])

        let serialized = try String(contentsOf: configFile, encoding: .utf8)
        XCTAssertEqual(serialized, """
        model = "gpt-5"

        [features]
        web_search = true

        [mcp_servers.docs]
        command = "docs-server"
        args = ["--verbose"]

        [mcp_servers.docs.env]
        ALPHA_VAR = "1"
        ZIG_VAR = "3"

        [mcp_servers.http]
        url = "https://example.com/mcp"
        bearer_token_env_var = "MCP_TOKEN"
        startup_timeout_sec = 2.0

        """)

        let loaded = try McpConfigStore.loadGlobalMcpServers(codexHome: temp.url)
        XCTAssertEqual(loaded["docs"]?.transport, .stdio(
            command: "docs-server",
            args: ["--verbose"],
            env: ["ALPHA_VAR": "1", "ZIG_VAR": "3"],
            envVars: [],
            cwd: nil
        ))
    }

    func testLoadRejectsInlineBearerTokenLikeRust() throws {
        XCTAssertThrowsError(try McpConfigStore.parseMcpServers(from: """
        [mcp_servers.docs]
        url = "https://example.com/mcp"
        bearer_token = "secret"
        """)) { error in
            XCTAssertEqual(
                String(describing: error),
                "mcp_servers.docs uses unsupported `bearer_token`; set `bearer_token_env_var`."
            )
        }
    }

    func testFormatListAndGetTextRedactsSecrets() throws {
        let servers = [
            "docs": McpServerConfig(
                transport: .stdio(
                    command: "docs-server",
                    args: ["--port", "4000"],
                    env: ["TOKEN": "secret"],
                    envVars: ["APP_TOKEN"],
                    cwd: nil
                )
            )
        ]

        let list = try McpCommandFormatter.list(servers: servers, json: false)
        XCTAssertTrue(list.contains("Name"))
        XCTAssertTrue(list.contains("docs"))
        XCTAssertTrue(list.contains("TOKEN=*****"))
        XCTAssertTrue(list.contains("APP_TOKEN=*****"))
        XCTAssertTrue(list.contains("Unsupported"))

        let get = try McpCommandFormatter.get(name: "docs", server: servers["docs"]!, json: false)
        XCTAssertTrue(get.contains("transport: stdio"))
        XCTAssertTrue(get.contains("command: docs-server"))
        XCTAssertTrue(get.contains("args: --port 4000"))
        XCTAssertTrue(get.contains("env: TOKEN=*****, APP_TOKEN=*****"))
        XCTAssertTrue(get.contains("remove: codex mcp remove docs"))
    }

    func testFormatListJSONIncludesRustNullFields() throws {
        let output = try McpCommandFormatter.list(
            servers: [
                "docs": McpServerConfig(
                    transport: .stdio(command: "echo", args: [], env: nil, envVars: [], cwd: nil)
                )
            ],
            json: true
        )
        let data = try XCTUnwrap(output.data(using: .utf8))
        let parsed = try JSONDecoder().decode(JSONValue.self, from: data)

        XCTAssertEqual(parsed, .array([
            .object([
                "name": .string("docs"),
                "enabled": .bool(true),
                "transport": .object([
                    "type": .string("stdio"),
                    "command": .string("echo"),
                    "args": .array([]),
                    "env": .null,
                    "env_vars": .array([]),
                    "cwd": .null
                ]),
                "startup_timeout_sec": .null,
                "tool_timeout_sec": .null,
                "auth_status": .string("unsupported")
            ])
        ]))
    }

    func testValidateServerNameMatchesRustAllowedCharacters() {
        XCTAssertNoThrow(try McpServerName.validate("docs-1_server"))
        XCTAssertThrowsError(try McpServerName.validate("docs.server")) { error in
            XCTAssertEqual(
                String(describing: error),
                "invalid server name 'docs.server' (use letters, numbers, '-', '_')"
            )
        }
    }
}

private final class McpConfigTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-swift-mcp-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
