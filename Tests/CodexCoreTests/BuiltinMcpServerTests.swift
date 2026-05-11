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
}
