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

    func testLoadGlobalMcpServersAcceptsLegacyStartupTimeoutMsField() throws {
        let temp = try McpConfigTemporaryDirectory()
        let configFile = temp.url.appendingPathComponent("config.toml")
        try """
        [mcp_servers.docs]
        command = "echo"
        startup_timeout_ms = 2500
        """.write(to: configFile, atomically: true, encoding: .utf8)

        let servers = try McpConfigStore.loadGlobalMcpServers(codexHome: temp.url)
        XCTAssertEqual(servers["docs"]?.startupTimeoutSec, 2.5)
    }

    func testReplaceGlobalMcpServersRoundTripsRustEditShape() throws {
        let temp = try McpConfigTemporaryDirectory()
        let configFile = temp.url.appendingPathComponent("config.toml")

        try McpConfigStore.replaceGlobalMcpServers(codexHome: temp.url, servers: [
            "stdio": McpServerConfig(
                transport: .stdio(
                    command: "cmd",
                    args: ["--flag"],
                    env: ["B": "2", "A": "1"],
                    envVars: ["FOO"],
                    cwd: nil
                ),
                enabledTools: ["one", "two"]
            ),
            "http": McpServerConfig(
                transport: .streamableHttp(
                    url: "https://example.com",
                    bearerTokenEnvVar: "TOKEN",
                    httpHeaders: ["Z-Header": "z"],
                    envHttpHeaders: nil
                ),
                enabled: false,
                startupTimeoutSec: 5,
                disabledTools: ["forbidden"]
            )
        ])

        let serialized = try String(contentsOf: configFile, encoding: .utf8)
        XCTAssertEqual(serialized, """
        [mcp_servers.http]
        url = "https://example.com"
        bearer_token_env_var = "TOKEN"
        enabled = false
        startup_timeout_sec = 5.0
        disabled_tools = ["forbidden"]

        [mcp_servers.http.http_headers]
        Z-Header = "z"

        [mcp_servers.stdio]
        command = "cmd"
        args = ["--flag"]
        env_vars = ["FOO"]
        enabled_tools = ["one", "two"]

        [mcp_servers.stdio.env]
        A = "1"
        B = "2"

        """)

        let loaded = try McpConfigStore.loadGlobalMcpServers(codexHome: temp.url)
        XCTAssertEqual(loaded["stdio"], McpServerConfig(
            transport: .stdio(
                command: "cmd",
                args: ["--flag"],
                env: ["A": "1", "B": "2"],
                envVars: ["FOO"],
                cwd: nil
            ),
            enabledTools: ["one", "two"]
        ))
        XCTAssertEqual(loaded["http"], McpServerConfig(
            transport: .streamableHttp(
                url: "https://example.com",
                bearerTokenEnvVar: "TOKEN",
                httpHeaders: ["Z-Header": "z"],
                envHttpHeaders: nil
            ),
            enabled: false,
            startupTimeoutSec: 5,
            disabledTools: ["forbidden"]
        ))
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

    func testReplaceGlobalMcpServersSerializesEnvVarsAndCwd() throws {
        let temp = try McpConfigTemporaryDirectory()
        let configFile = temp.url.appendingPathComponent("config.toml")

        try McpConfigStore.replaceGlobalMcpServers(codexHome: temp.url, servers: [
            "docs": McpServerConfig(
                transport: .stdio(
                    command: "docs-server",
                    args: [],
                    env: nil,
                    envVars: ["ALPHA", "BETA"],
                    cwd: "/tmp/codex-mcp"
                )
            )
        ])

        let serialized = try String(contentsOf: configFile, encoding: .utf8)
        XCTAssertTrue(serialized.contains(#"env_vars = ["ALPHA", "BETA"]"#))
        XCTAssertTrue(serialized.contains(#"cwd = "/tmp/codex-mcp""#))

        XCTAssertEqual(
            try McpConfigStore.loadGlobalMcpServers(codexHome: temp.url)["docs"]?.transport,
            .stdio(
                command: "docs-server",
                args: [],
                env: nil,
                envVars: ["ALPHA", "BETA"],
                cwd: "/tmp/codex-mcp"
            )
        )
    }

    func testReplaceGlobalMcpServersStreamableHTTPRemovesOptionalSections() throws {
        let temp = try McpConfigTemporaryDirectory()
        let configFile = temp.url.appendingPathComponent("config.toml")

        try McpConfigStore.replaceGlobalMcpServers(codexHome: temp.url, servers: [
            "docs": McpServerConfig(
                transport: .streamableHttp(
                    url: "https://example.com/mcp",
                    bearerTokenEnvVar: "MCP_TOKEN",
                    httpHeaders: ["X-Doc": "42"],
                    envHttpHeaders: ["X-Auth": "DOCS_AUTH"]
                ),
                startupTimeoutSec: 2
            )
        ])

        let serializedWithOptional = try String(contentsOf: configFile, encoding: .utf8)
        XCTAssertTrue(serializedWithOptional.contains(#"bearer_token_env_var = "MCP_TOKEN""#))
        XCTAssertTrue(serializedWithOptional.contains("[mcp_servers.docs.http_headers]"))
        XCTAssertTrue(serializedWithOptional.contains("[mcp_servers.docs.env_http_headers]"))

        try McpConfigStore.replaceGlobalMcpServers(codexHome: temp.url, servers: [
            "docs": McpServerConfig(
                transport: .streamableHttp(
                    url: "https://example.com/mcp",
                    bearerTokenEnvVar: nil,
                    httpHeaders: nil,
                    envHttpHeaders: nil
                )
            )
        ])

        let serialized = try String(contentsOf: configFile, encoding: .utf8)
        XCTAssertEqual(serialized, """
        [mcp_servers.docs]
        url = "https://example.com/mcp"

        """)

        XCTAssertEqual(try McpConfigStore.loadGlobalMcpServers(codexHome: temp.url)["docs"], McpServerConfig(
            transport: .streamableHttp(
                url: "https://example.com/mcp",
                bearerTokenEnvVar: nil,
                httpHeaders: nil,
                envHttpHeaders: nil
            )
        ))
    }

    func testReplaceGlobalMcpServersStreamableHTTPIsolatesHeadersBetweenServers() throws {
        let temp = try McpConfigTemporaryDirectory()
        let configFile = temp.url.appendingPathComponent("config.toml")

        try McpConfigStore.replaceGlobalMcpServers(codexHome: temp.url, servers: [
            "docs": McpServerConfig(
                transport: .streamableHttp(
                    url: "https://example.com/mcp",
                    bearerTokenEnvVar: "MCP_TOKEN",
                    httpHeaders: ["X-Doc": "42"],
                    envHttpHeaders: ["X-Auth": "DOCS_AUTH"]
                ),
                startupTimeoutSec: 2
            ),
            "logs": McpServerConfig(
                transport: .stdio(
                    command: "logs-server",
                    args: ["--follow"],
                    env: nil,
                    envVars: [],
                    cwd: nil
                )
            )
        ])

        let serialized = try String(contentsOf: configFile, encoding: .utf8)
        XCTAssertTrue(serialized.contains("[mcp_servers.docs.http_headers]"))
        XCTAssertFalse(serialized.contains("[mcp_servers.logs.http_headers]"))
        XCTAssertFalse(serialized.contains("[mcp_servers.logs.env_http_headers]"))
        XCTAssertFalse(serialized.contains("mcp_servers.logs.bearer_token_env_var"))

        let loaded = try McpConfigStore.loadGlobalMcpServers(codexHome: temp.url)
        XCTAssertEqual(loaded["docs"]?.transport, .streamableHttp(
            url: "https://example.com/mcp",
            bearerTokenEnvVar: "MCP_TOKEN",
            httpHeaders: ["X-Doc": "42"],
            envHttpHeaders: ["X-Auth": "DOCS_AUTH"]
        ))
        XCTAssertEqual(loaded["logs"]?.transport, .stdio(
            command: "logs-server",
            args: ["--follow"],
            env: nil,
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
                "disabled_reason": .null,
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

    func testFormatMcpDisabledReasonMatchesRustListAndGet() throws {
        let server = McpServerConfig(
            transport: .stdio(command: "echo", args: [], env: nil, envVars: [], cwd: nil),
            enabled: false,
            disabledReason: "requirements"
        )

        let list = try McpCommandFormatter.list(servers: ["docs": server], json: false)
        XCTAssertTrue(list.contains("disabled: requirements"))

        let listJSON = try JSONDecoder().decode(
            JSONValue.self,
            from: Data(try McpCommandFormatter.list(servers: ["docs": server], json: true).utf8)
        )
        XCTAssertEqual(
            listJSON,
            .array([
                .object([
                    "name": .string("docs"),
                    "enabled": .bool(false),
                    "disabled_reason": .string("requirements"),
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
            ])
        )

        XCTAssertEqual(
            try McpCommandFormatter.get(name: "docs", server: server, json: false),
            "docs (disabled: requirements)"
        )

        let getJSON = try JSONDecoder().decode(
            JSONValue.self,
            from: Data(try McpCommandFormatter.get(name: "docs", server: server, json: true).utf8)
        )
        XCTAssertEqual(
            getJSON,
            .object([
                "name": .string("docs"),
                "enabled": .bool(false),
                "disabled_reason": .string("requirements"),
                "transport": .object([
                    "type": .string("stdio"),
                    "command": .string("echo"),
                    "args": .array([]),
                    "env": .null,
                    "env_vars": .array([]),
                    "cwd": .null
                ]),
                "enabled_tools": .null,
                "disabled_tools": .null,
                "startup_timeout_sec": .null,
                "tool_timeout_sec": .null
            ])
        )
    }

    func testAuthStatusResolverMarksBearerTokenHTTPServers() throws {
        let servers = [
            "docs": McpServerConfig(
                transport: .stdio(command: "echo", args: [], env: nil, envVars: [], cwd: nil)
            ),
            "github": McpServerConfig(
                transport: .streamableHttp(
                    url: "https://example.com/mcp",
                    bearerTokenEnvVar: "GITHUB_TOKEN",
                    httpHeaders: nil,
                    envHttpHeaders: nil
                )
            ),
            "figma": McpServerConfig(
                transport: .streamableHttp(
                    url: "https://figma.example/mcp",
                    bearerTokenEnvVar: nil,
                    httpHeaders: nil,
                    envHttpHeaders: nil
                )
            )
        ]

        XCTAssertEqual(McpAuthStatusResolver.authStatuses(for: servers), [
            "docs": .unsupported,
            "github": .bearerToken,
            "figma": .unsupported
        ])

        let text = try McpCommandFormatter.list(servers: servers, json: false)
        XCTAssertTrue(text.contains("github"))
        XCTAssertTrue(text.contains("Bearer token"))

        let json = try McpCommandFormatter.list(servers: servers, json: true)
        XCTAssertTrue(json.contains(#""auth_status": "bearer_token""#))
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
