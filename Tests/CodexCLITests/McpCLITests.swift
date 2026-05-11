import CodexCLI
import CodexCore
import XCTest

final class McpCLITests: XCTestCase {
    func testRunAsyncMcpAddStdioDelegatesToRunnerWithEnvAndOverrides() async {
        var stdout: [String] = []
        var stderr: [String] = []
        var receivedRequest: CodexCLI.McpCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: [
                "-c",
                "model=\"gpt-5\"",
                "mcp",
                "add",
                "docs",
                "--env",
                "TOKEN=secret",
                "--",
                "docs-server",
                "--port",
                "4000"
            ],
            stdout: { stdout.append($0) },
            stderr: { stderr.append($0) },
            mcpRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0, stdoutMessage: "Added global MCP server 'docs'.")
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(stdout, ["Added global MCP server 'docs'."])
        XCTAssertTrue(stderr.isEmpty)
        XCTAssertEqual(
            receivedRequest,
            CodexCLI.McpCommandRequest(
                action: .add(
                    name: "docs",
                    transport: .stdio(
                        command: ["docs-server", "--port", "4000"],
                        env: [CodexCLI.McpEnvPair(key: "TOKEN", value: "secret")]
                    )
                ),
                configOverrides: CliConfigOverrides(rawOverrides: ["model=\"gpt-5\""])
            )
        )
    }

    func testRunAsyncMcpAddStreamableHTTPDelegatesToRunner() async {
        var receivedRequest: CodexCLI.McpCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: [
                "mcp",
                "add",
                "github",
                "--url",
                "https://example.com/mcp",
                "--bearer-token-env-var",
                "GITHUB_TOKEN"
            ],
            stderr: { _ in XCTFail("stderr should not be written") },
            mcpRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(
            receivedRequest?.action,
            .add(
                name: "github",
                transport: .streamableHttp(
                    url: "https://example.com/mcp",
                    bearerTokenEnvVar: "GITHUB_TOKEN"
                )
            )
        )
    }

    func testRunAsyncMcpListGetRemoveLoginLogoutDelegatesToRunner() async {
        var actions: [CodexCLI.McpCommandAction] = []

        for arguments in [
            ["mcp", "list", "--json"],
            ["mcp", "get", "docs", "--json"],
            ["mcp", "remove", "docs"],
            ["mcp", "login", "github", "--scopes", "repo,user"],
            ["mcp", "logout", "github"]
        ] {
            let exitCode = await CodexCLI().runAsync(
                arguments: arguments,
                stderr: { _ in XCTFail("stderr should not be written for \(arguments)") },
                mcpRunner: { request in
                    actions.append(request.action)
                    return CodexCLI.CommandExecutionResult(exitCode: 0)
                }
            )
            XCTAssertEqual(exitCode, 0, "\(arguments)")
        }

        XCTAssertEqual(actions, [
            .list(json: true),
            .get(name: "docs", json: true),
            .remove(name: "docs"),
            .login(name: "github", scopes: ["repo", "user"]),
            .logout(name: "github")
        ])
    }

    func testRunAsyncMcpRejectsInvalidFormsBeforeRunner() async {
        let cases: [([String], String)] = [
            (
                ["mcp"],
                "codex-swift: missing required subcommand for command 'mcp': list|get|add|remove|login|logout"
            ),
            (
                ["mcp", "bogus"],
                "codex-swift: unsupported mcp subcommand: bogus"
            ),
            (
                ["mcp", "get"],
                "codex-swift: missing required argument for command 'mcp get': <NAME>"
            ),
            (
                ["mcp", "add", "docs"],
                "codex-swift: missing required argument for command 'mcp add': <COMMAND>"
            ),
            (
                ["mcp", "add", "docs", "--url", "https://example.com/mcp", "--", "echo"],
                "codex-swift: exactly one of command or --url must be provided"
            ),
            (
                ["mcp", "add", "docs", "--env", "BROKEN"],
                "environment entries must be in KEY=VALUE form"
            )
        ]

        for (arguments, expectedMessage) in cases {
            var stderr: [String] = []
            let exitCode = await CodexCLI().runAsync(
                arguments: arguments,
                stdout: { _ in XCTFail("stdout should not be written for \(arguments)") },
                stderr: { stderr.append($0) },
                mcpRunner: { _ in
                    XCTFail("runner should not be called for \(arguments)")
                    return CodexCLI.CommandExecutionResult(exitCode: 0)
                }
            )

            XCTAssertEqual(exitCode, 64, "\(arguments)")
            XCTAssertEqual(stderr, [expectedMessage], "\(arguments)")
        }
    }

    func testRunAsyncMcpWithoutRunnerStillReportsUnimplemented() async {
        var stderr: [String] = []

        let exitCode = await CodexCLI().runAsync(
            arguments: ["mcp", "list"],
            stdout: { _ in XCTFail("stdout should not be written") },
            stderr: { stderr.append($0) }
        )

        XCTAssertEqual(exitCode, 78)
        XCTAssertEqual(stderr, ["codex-swift: command 'mcp' is registered but its runtime port is not complete yet."])
    }

    func testMcpCommandRuntimeAddsStdioServerToGlobalConfig() async throws {
        let temp = try TemporaryMcpRuntimeDirectory()
        let request = CodexCLI.McpCommandRequest(action: .add(
            name: "docs",
            transport: .stdio(
                command: ["docs-server", "--port", "4000"],
                env: [CodexCLI.McpEnvPair(key: "TOKEN", value: "secret")]
            )
        ))

        let result = try await McpCommandRuntime.run(request, dependencies: runtimeDependencies(codexHome: temp.url))

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdoutMessage, "Added global MCP server 'docs'.")
        XCTAssertEqual(try McpConfigStore.loadGlobalMcpServers(codexHome: temp.url), [
            "docs": McpServerConfig(
                transport: .stdio(
                    command: "docs-server",
                    args: ["--port", "4000"],
                    env: ["TOKEN": "secret"],
                    envVars: [],
                    cwd: nil
                )
            )
        ])
    }

    func testMcpCommandRuntimeValidatesConfigBeforeAddWrites() async throws {
        let temp = try TemporaryMcpRuntimeDirectory()
        let configFile = temp.url.appendingPathComponent("config.toml", isDirectory: false)
        try #"model = "original""#.write(to: configFile, atomically: true, encoding: .utf8)
        let request = CodexCLI.McpCommandRequest(
            action: .add(name: "docs", transport: .stdio(command: ["docs-server"], env: [])),
            configOverrides: CliConfigOverrides(rawOverrides: ["missing"])
        )

        do {
            _ = try await McpCommandRuntime.run(request, dependencies: runtimeDependencies(codexHome: temp.url))
            XCTFail("mcp add should reject invalid root overrides before writing")
        } catch {
            XCTAssertEqual(String(describing: error), "Invalid override (missing '='): missing")
        }

        XCTAssertEqual(try String(contentsOf: configFile, encoding: .utf8), #"model = "original""#)
    }

    func testMcpCommandRuntimeListGetRemoveAndLogout() async throws {
        let temp = try TemporaryMcpRuntimeDirectory()
        let docs = McpServerConfig(transport: .stdio(command: "docs-server", args: [], env: nil, envVars: [], cwd: nil))
        let github = McpServerConfig(transport: .streamableHttp(
            url: "https://example.com/mcp",
            bearerTokenEnvVar: nil,
            httpHeaders: nil,
            envHttpHeaders: nil
        ))
        try McpConfigStore.replaceGlobalMcpServers(codexHome: temp.url, servers: [
            "docs": docs,
            "github": github
        ])
        nonisolated(unsafe) var deletedOAuth: (name: String, url: String)?
        let dependencies = runtimeDependencies(
            codexHome: temp.url,
            deleteOAuthTokens: { name, url, _, _ in
                deletedOAuth = (name, url)
                return true
            }
        )

        let list = try await McpCommandRuntime.run(
            CodexCLI.McpCommandRequest(action: .list(json: false)),
            dependencies: dependencies
        )
        XCTAssertTrue(list.stdoutMessage?.contains("docs-server") == true)
        XCTAssertTrue(list.stdoutMessage?.contains("https://example.com/mcp") == true)

        let get = try await McpCommandRuntime.run(
            CodexCLI.McpCommandRequest(action: .get(name: "docs", json: false)),
            dependencies: dependencies
        )
        XCTAssertTrue(get.stdoutMessage?.contains("command: docs-server") == true)

        let logout = try await McpCommandRuntime.run(
            CodexCLI.McpCommandRequest(action: .logout(name: "github")),
            dependencies: dependencies
        )
        XCTAssertEqual(logout.stdoutMessage, "Removed OAuth credentials for 'github'.")
        XCTAssertEqual(deletedOAuth?.name, "github")
        XCTAssertEqual(deletedOAuth?.url, "https://example.com/mcp")

        let remove = try await McpCommandRuntime.run(
            CodexCLI.McpCommandRequest(action: .remove(name: "docs")),
            dependencies: dependencies
        )
        XCTAssertEqual(remove.stdoutMessage, "Removed global MCP server 'docs'.")
        XCTAssertNil(try McpConfigStore.loadGlobalMcpServers(codexHome: temp.url)["docs"])
    }

    private func runtimeDependencies(
        codexHome: URL,
        deleteOAuthTokens: @escaping @Sendable (String, String, URL, OAuthCredentialsStoreMode) throws -> Bool = { _, _, _, _ in false }
    ) -> McpCommandRuntime.Dependencies {
        McpCommandRuntime.Dependencies(
            findCodexHome: { codexHome },
            loadConfig: { codexHome, overrides in
                _ = try overrides.applying()
                return CodexRuntimeConfig(
                    mcpServers: try McpConfigStore.loadGlobalMcpServers(codexHome: codexHome),
                    mcpOAuthCredentialsStoreMode: .file
                )
            },
            authStatuses: { servers, _, _, _ in
                McpAuthStatusResolver.authStatuses(for: servers)
            },
            supportsOAuthLogin: { _, _, _, _ in false },
            performOAuthLogin: { _, _ in },
            deleteOAuthTokens: deleteOAuthTokens,
            environment: { [:] },
            messageSink: { _ in }
        )
    }
}

private final class TemporaryMcpRuntimeDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-swift-mcp-runtime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
