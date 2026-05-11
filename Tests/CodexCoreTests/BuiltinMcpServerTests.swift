import CodexCore
import Foundation
import XCTest

final class BuiltinMcpServerTests: XCTestCase {
    func testEnabledBuiltinMcpServersAddsMemoriesWhenEnabled() {
        XCTAssertEqual(
            enabledBuiltinMcpServers(options: BuiltinMcpServerOptions(memoriesEnabled: true)),
            [.memories]
        )
    }

    func testEnabledBuiltinMcpServersOmitsMemoriesWhenDisabled() {
        XCTAssertEqual(
            enabledBuiltinMcpServers(options: BuiltinMcpServerOptions(memoriesEnabled: false)),
            []
        )
    }

    func testMemoriesMetadataMatchesRustBuiltinMcpServer() {
        XCTAssertEqual(BuiltinMcpServer.memories.name, memoriesMcpServerName)
        XCTAssertTrue(BuiltinMcpServer.memories.supportsParallelToolCalls)
        XCTAssertFalse(BuiltinMcpServer.memories.pollutesMemory)
    }

    func testRuntimeMcpConfigEnablesMemoriesOnlyWhenBothFeaturesAreEnabled() {
        let configuredMemories = McpServerConfig(transport: .stdio(command: "user-memories", args: [], env: nil, envVars: [], cwd: nil))
        var onlyMemoriesFeature = FeatureStates()
        onlyMemoriesFeature.set(.memoryTool, enabled: true)
        XCTAssertEqual(
            CodexRuntimeConfig(features: onlyMemoriesFeature, mcpServers: [
                memoriesMcpServerName: configuredMemories
            ]).runtimeMcpConfig,
            RuntimeMcpConfig(configuredMcpServers: [memoriesMcpServerName: configuredMemories], builtinMcpServers: [])
        )

        var bothFeatures = FeatureStates()
        bothFeatures.set(.builtInMcp, enabled: true)
        bothFeatures.set(.memoryTool, enabled: true)

        XCTAssertEqual(
            CodexRuntimeConfig(
                features: bothFeatures,
                memories: MemoriesConfig(useMemories: false),
                mcpServers: [memoriesMcpServerName: configuredMemories]
            ).runtimeMcpConfig,
            RuntimeMcpConfig(configuredMcpServers: [memoriesMcpServerName: configuredMemories], builtinMcpServers: [])
        )

        XCTAssertEqual(
            CodexRuntimeConfig(features: bothFeatures, mcpServers: [
                memoriesMcpServerName: configuredMemories,
                "docs": McpServerConfig(transport: .stdio(command: "docs", args: [], env: nil, envVars: [], cwd: nil))
            ]).runtimeMcpConfig,
            RuntimeMcpConfig(
                configuredMcpServers: [
                    "docs": McpServerConfig(transport: .stdio(command: "docs", args: [], env: nil, envVars: [], cwd: nil))
                ],
                builtinMcpServers: [.memories]
            )
        )
    }

    func testCodexAppsMcpURLMatchesRustBaseURLRules() {
        XCTAssertEqual(
            RuntimeMcpConfig.codexAppsMcpURL(
                baseURL: "https://chatgpt.com/backend-api",
                appsMcpPathOverride: nil
            ),
            "https://chatgpt.com/backend-api/wham/apps"
        )
        XCTAssertEqual(
            RuntimeMcpConfig.codexAppsMcpURL(
                baseURL: "https://chat.openai.com",
                appsMcpPathOverride: nil
            ),
            "https://chat.openai.com/backend-api/wham/apps"
        )
        XCTAssertEqual(
            RuntimeMcpConfig.codexAppsMcpURL(
                baseURL: "http://localhost:8080/api/codex",
                appsMcpPathOverride: nil
            ),
            "http://localhost:8080/api/codex/apps"
        )
        XCTAssertEqual(
            RuntimeMcpConfig.codexAppsMcpURL(
                baseURL: "http://localhost:8080",
                appsMcpPathOverride: nil
            ),
            "http://localhost:8080/api/codex/apps"
        )
        XCTAssertEqual(
            RuntimeMcpConfig.codexAppsMcpURL(
                baseURL: "https://chatgpt.com/backend-api/",
                appsMcpPathOverride: "/custom/mcp"
            ),
            "https://chatgpt.com/backend-api/custom/mcp"
        )
    }

    func testEffectiveMcpServersPreserveConfiguredBuiltinAndCodexAppsShape() {
        let docs = McpServerConfig(transport: .streamableHttp(
            url: "https://docs.example/mcp",
            bearerTokenEnvVar: nil,
            httpHeaders: nil,
            envHttpHeaders: nil
        ))
        let config = RuntimeMcpConfig(
            chatgptBaseURL: "https://chatgpt.com/backend-api/",
            appsMcpPathOverride: "/custom/mcp",
            appsEnabled: true,
            configuredMcpServers: [
                "docs": docs,
                codexAppsMCPServerName: McpServerConfig(transport: .stdio(
                    command: "user-codex-apps",
                    args: [],
                    env: nil,
                    envVars: [],
                    cwd: nil
                ))
            ],
            builtinMcpServers: [.memories]
        )

        XCTAssertFalse(config.effectiveMcpServers(usesCodexBackend: false).keys.contains(codexAppsMCPServerName))

        let effective = config.effectiveMcpServers(
            usesCodexBackend: true,
            environment: ["CODEX_CONNECTORS_TOKEN": "token"]
        )
        XCTAssertEqual(effective["docs"]?.configuredConfig, docs)
        XCTAssertEqual(effective[memoriesMcpServerName]?.builtinServer, .memories)

        let codexApps = effective[codexAppsMCPServerName]?.configuredConfig
        XCTAssertEqual(codexApps?.startupTimeoutSec, 30)
        XCTAssertEqual(codexApps?.transport, .streamableHttp(
            url: "https://chatgpt.com/backend-api/custom/mcp",
            bearerTokenEnvVar: "CODEX_CONNECTORS_TOKEN",
            httpHeaders: nil,
            envHttpHeaders: nil
        ))
    }
}
