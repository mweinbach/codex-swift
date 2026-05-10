import CodexCore
import XCTest

final class McpRequiredStartupValidatorTests: XCTestCase {
    func testReportsEnabledRequiredMissingStdioCommandsInSortedOrderLikeRust() throws {
        let servers: [String: McpServerConfig] = [
            "z_required": McpServerConfig(
                transport: .stdio(command: "codex-definitely-not-a-real-binary-z", args: [], env: nil, envVars: [], cwd: nil),
                required: true
            ),
            "disabled_required": McpServerConfig(
                transport: .stdio(command: "codex-definitely-not-a-real-binary-disabled", args: [], env: nil, envVars: [], cwd: nil),
                enabled: false,
                required: true
            ),
            "optional": McpServerConfig(
                transport: .stdio(command: "codex-definitely-not-a-real-binary-optional", args: [], env: nil, envVars: [], cwd: nil)
            ),
            "a_required": McpServerConfig(
                transport: .stdio(command: "codex-definitely-not-a-real-binary-a", args: [], env: nil, envVars: [], cwd: nil),
                required: true
            )
        ]

        let failures = McpRequiredStartupValidator.startupFailures(
            mcpServers: servers,
            environment: ["PATH": ""]
        )

        XCTAssertEqual(failures, [
            McpStartupFailure(server: "a_required", error: "command not found: codex-definitely-not-a-real-binary-a"),
            McpStartupFailure(server: "z_required", error: "command not found: codex-definitely-not-a-real-binary-z")
        ])
        XCTAssertEqual(
            McpRequiredStartupValidator.requiredStartupFailureMessage(for: failures),
            "required MCP servers failed to initialize: a_required: command not found: codex-definitely-not-a-real-binary-a; z_required: command not found: codex-definitely-not-a-real-binary-z"
        )
    }

    func testResolvedRequiredStdioCommandsDoNotFail() throws {
        let executable = try XCTUnwrap(ProcessInfo.processInfo.environment["SHELL"])
        let failures = McpRequiredStartupValidator.startupFailures(
            mcpServers: [
                "shell": McpServerConfig(
                    transport: .stdio(command: executable, args: [], env: nil, envVars: [], cwd: nil),
                    required: true
                )
            ],
            environment: [:]
        )

        XCTAssertEqual(failures, [])
    }

    func testRelativeStdioCommandsResolveAgainstConfiguredCwd() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let executable = temp.appendingPathComponent("server", isDirectory: false)
        try "#!/bin/sh\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )

        let failures = McpRequiredStartupValidator.startupFailures(
            mcpServers: [
                "relative": McpServerConfig(
                    transport: .stdio(
                        command: "./server",
                        args: [],
                        env: nil,
                        envVars: [],
                        cwd: temp.path
                    ),
                    required: true
                )
            ],
            environment: ["PATH": ""]
        )

        XCTAssertEqual(failures, [McpStartupFailure]())
    }

    func testStreamableHttpRequiredServersAreNotPreflightedWithoutAConnectionManager() throws {
        let failures = McpRequiredStartupValidator.startupFailures(
            mcpServers: [
                "remote": McpServerConfig(
                    transport: .streamableHttp(
                        url: "https://example.test/mcp",
                        bearerTokenEnvVar: nil,
                        httpHeaders: nil,
                        envHttpHeaders: nil
                    ),
                    required: true
                )
            ],
            environment: ["PATH": ""]
        )

        XCTAssertEqual(failures, [])
    }
}
