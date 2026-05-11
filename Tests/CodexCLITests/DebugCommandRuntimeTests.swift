import CodexCLI
import CodexCore
import Foundation
import SQLite3
import XCTest

final class DebugCommandRuntimeTests: XCTestCase {
    func testAppServerSendMessageV2UsesCurrentExecutableAndConfigOverrides() async throws {
        let executable = URL(fileURLWithPath: "/tmp/codex-swift-test", isDirectory: false)
        let overrides = CliConfigOverrides(rawOverrides: ["model=\"gpt-test\"", "features.remote_control=true"])
        var capturedExecutable: URL?
        var capturedOverrides: CliConfigOverrides?
        var capturedMessage: String?

        let result = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(
                action: .appServerSendMessageV2(message: "hello app server"),
                configOverrides: overrides
            ),
            dependencies: DebugCommandRuntime.Dependencies(
                currentExecutable: { executable },
                sendAppServerMessageV2: { executableURL, configOverrides, message in
                    capturedExecutable = executableURL
                    capturedOverrides = configOverrides
                    capturedMessage = message
                    return CodexCLI.CommandExecutionResult(
                        exitCode: 0,
                        stdoutMessage: "< initialize response: {}\n< thread/start response: {}\n< turn/start response: {}\n"
                    )
                }
            )
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(capturedExecutable, executable)
        XCTAssertEqual(capturedOverrides, overrides)
        XCTAssertEqual(capturedMessage, "hello app server")
        XCTAssertTrue(result.stdoutMessage?.contains("< turn/start response:") == true)
    }

    func testPromptInputOutputsEnvironmentImagesAndNormalizedPrompt() async throws {
        let temp = try TemporaryDirectory()
        let imagePath = temp.url.appendingPathComponent("image.png", isDirectory: false)
        try writeTinyPNG(to: imagePath)

        let result = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(
                action: .promptInput(prompt: "hello\r\nworld\ragain", imagePaths: [imagePath.path])
            ),
            dependencies: testDependencies(codexHome: temp.url)
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertNil(result.stderrMessage)
        let output = try XCTUnwrap(result.stdoutMessage)
        XCTAssertTrue(output.hasSuffix("\n"))
        XCTAssertTrue(output.contains("\n  {"))

        let decoded = try JSONDecoder().decode([ResponseItem].self, from: Data(output.utf8))
        XCTAssertEqual(decoded.count, 3)
        guard case let .message(_, permissionsRole, permissionsContent, _) = decoded[0] else {
            return XCTFail("expected permissions developer message")
        }
        XCTAssertEqual(permissionsRole, "developer")
        XCTAssertTrue(permissionsContent.contains {
            guard case let .inputText(text) = $0 else {
                return false
            }
            return text.contains("<permissions instructions>")
        })

        guard case let .message(_, environmentRole, environmentContent, _) = decoded[1] else {
            return XCTFail("expected environment context message")
        }
        XCTAssertEqual(environmentRole, "user")
        guard case let .inputText(environmentText) = environmentContent.first else {
            return XCTFail("expected environment text")
        }
        XCTAssertTrue(environmentText.contains("<environment_context>"))

        guard case let .message(_, userRole, userContent, _) = decoded[2] else {
            return XCTFail("expected user input message")
        }
        XCTAssertEqual(userRole, "user")
        XCTAssertEqual(userContent.count, 4)
        guard case let .inputText(openTag) = userContent[0],
              case .inputImage = userContent[1],
              case let .inputText(closeTag) = userContent[2],
              case let .inputText(promptText) = userContent[3]
        else {
            return XCTFail("expected local image wrapper followed by prompt")
        }
        XCTAssertEqual(openTag, "<image name=[Image #1]>")
        XCTAssertEqual(closeTag, "</image>")
        XCTAssertEqual(promptText, "hello\nworld\nagain")
    }

    func testPromptInputWithoutUserItemsOnlyOutputsEnvironment() async throws {
        let temp = try TemporaryDirectory()

        let result = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .promptInput(prompt: nil, imagePaths: [])),
            dependencies: testDependencies(codexHome: temp.url)
        )

        let output = try XCTUnwrap(result.stdoutMessage)
        let decoded = try JSONDecoder().decode([ResponseItem].self, from: Data(output.utf8))
        XCTAssertEqual(decoded.count, 2)
        guard case let .message(_, permissionsRole, permissionsContent, _) = decoded[0] else {
            return XCTFail("expected permissions developer message")
        }
        XCTAssertEqual(permissionsRole, "developer")
        XCTAssertTrue(permissionsContent.contains {
            guard case let .inputText(text) = $0 else {
                return false
            }
            return text.contains("<permissions instructions>")
        })

        guard case let .message(_, role, content, _) = decoded[1] else {
            return XCTFail("expected environment context message")
        }
        XCTAssertEqual(role, "user")
        guard case let .inputText(text) = content.first else {
            return XCTFail("expected environment text")
        }
        XCTAssertTrue(text.contains("<environment_context>"))
    }

    func testPromptInputHonorsInitialContextInstructionGates() async throws {
        let temp = try TemporaryDirectory()

        let result = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .promptInput(prompt: nil, imagePaths: [])),
            dependencies: testDependencies(
                codexHome: temp.url,
                config: CodexRuntimeConfig(
                    modelProvider: "test-provider",
                    includePermissionsInstructions: false,
                    includeEnvironmentContext: false,
                    projectDocMaxBytes: 0
                )
            )
        )

        let output = try XCTUnwrap(result.stdoutMessage)
        let decoded = try JSONDecoder().decode([ResponseItem].self, from: Data(output.utf8))
        XCTAssertEqual(decoded, [])
    }

    func testPromptInputIncludesDeveloperAndProjectInstructions() async throws {
        let temp = try TemporaryDirectory()
        let previousCWD = FileManager.default.currentDirectoryPath
        try "Project-specific debug instructions".write(
            to: temp.url.appendingPathComponent(ProjectDoc.defaultFilename, isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        XCTAssertTrue(FileManager.default.changeCurrentDirectoryPath(temp.url.path))
        defer {
            XCTAssertTrue(FileManager.default.changeCurrentDirectoryPath(previousCWD))
        }

        let result = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .promptInput(prompt: "hello", imagePaths: [])),
            dependencies: testDependencies(
                codexHome: temp.url,
                config: CodexRuntimeConfig(
                    modelProvider: "test-provider",
                    developerInstructions: "Debug developer instructions"
                )
            )
        )

        let output = try XCTUnwrap(result.stdoutMessage)
        let decoded = try JSONDecoder().decode([ResponseItem].self, from: Data(output.utf8))
        XCTAssertEqual(decoded.count, 3)

        guard case let .message(_, developerRole, developerContent, _) = decoded[0] else {
            return XCTFail("expected developer context message")
        }
        XCTAssertEqual(developerRole, "developer")
        XCTAssertEqual(developerContent.count, 2)
        guard case let .inputText(permissionsText) = developerContent[0],
              case let .inputText(developerText) = developerContent[1]
        else {
            return XCTFail("expected permissions followed by developer instructions")
        }
        XCTAssertTrue(permissionsText.contains("<permissions instructions>"))
        XCTAssertEqual(developerText, "Debug developer instructions")

        guard case let .message(_, contextualRole, contextualContent, _) = decoded[1] else {
            return XCTFail("expected contextual user message")
        }
        XCTAssertEqual(contextualRole, "user")
        XCTAssertEqual(contextualContent.count, 2)
        guard case let .inputText(projectText) = contextualContent[0],
              case let .inputText(environmentText) = contextualContent[1]
        else {
            return XCTFail("expected project instructions followed by environment context")
        }
        XCTAssertTrue(projectText.contains("Project-specific debug instructions"))
        XCTAssertTrue(environmentText.contains("<environment_context>"))

        guard case let .message(_, promptRole, promptContent, _) = decoded[2] else {
            return XCTFail("expected prompt user message")
        }
        XCTAssertEqual(promptRole, "user")
        XCTAssertEqual(promptContent, [.inputText(text: "hello")])
    }

    func testPromptInputIncludesMemoryToolInstructionsWhenEnabled() async throws {
        let temp = try TemporaryDirectory()
        let memories = temp.url.appendingPathComponent("memories", isDirectory: true)
        try FileManager.default.createDirectory(at: memories, withIntermediateDirectories: true)
        try "Remember the debug prompt path.".write(
            to: memories.appendingPathComponent("memory_summary.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        var features = FeatureStates.withDefaults()
        features.set(.memoryTool, enabled: true)

        let result = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .promptInput(prompt: nil, imagePaths: [])),
            dependencies: testDependencies(
                codexHome: temp.url,
                config: CodexRuntimeConfig(
                    modelProvider: "test-provider",
                    features: features,
                    projectDocMaxBytes: 0
                )
            )
        )

        let output = try XCTUnwrap(result.stdoutMessage)
        let decoded = try JSONDecoder().decode([ResponseItem].self, from: Data(output.utf8))
        guard case let .message(_, developerRole, developerContent, _) = decoded[0] else {
            return XCTFail("expected developer context message")
        }
        XCTAssertEqual(developerRole, "developer")
        XCTAssertEqual(developerContent.count, 2)
        guard case let .inputText(memoryText) = developerContent[1] else {
            return XCTFail("expected memory instructions after permissions")
        }
        XCTAssertTrue(memoryText.contains("Remember the debug prompt path."))
        XCTAssertTrue(memoryText.contains("\(memories.path)/MEMORY.md"))
    }

    func testPromptInputIncludesAvailableSkillsWhenEnabled() async throws {
        let temp = try TemporaryDirectory()
        let skill = temp.url.appendingPathComponent("skills/debug-helper/SKILL.md", isDirectory: false)
        try FileManager.default.createDirectory(
            at: skill.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        ---
        name: debug-helper
        description: Inspect debug prompt payloads.
        ---

        Use this when checking debug prompt JSON.
        """.write(to: skill, atomically: true, encoding: .utf8)

        let result = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .promptInput(prompt: "inspect", imagePaths: [])),
            dependencies: testDependencies(
                codexHome: temp.url,
                config: CodexRuntimeConfig(
                    model: "gpt-test",
                    modelProvider: "test-provider",
                    includeSkillInstructions: true,
                    projectDocMaxBytes: 0
                )
            )
        )

        let output = try XCTUnwrap(result.stdoutMessage)
        let decoded = try JSONDecoder().decode([ResponseItem].self, from: Data(output.utf8))
        guard case let .message(_, developerRole, developerContent, _) = decoded[0] else {
            return XCTFail("expected developer context message")
        }
        XCTAssertEqual(developerRole, "developer")
        XCTAssertEqual(developerContent.count, 2)
        guard case let .inputText(skillsText) = developerContent[1] else {
            return XCTFail("expected skills instructions after permissions")
        }
        XCTAssertTrue(skillsText.contains("### Available skills"))
        XCTAssertTrue(skillsText.contains("- debug-helper: Inspect debug prompt payloads."))
        XCTAssertTrue(skillsText.contains("### How to use skills"))
        XCTAssertTrue(skillsText.contains(skill.path))
    }

    func testPromptInputAvailableSkillsHonorConfigRules() async throws {
        let temp = try TemporaryDirectory()
        let disabledSkill = temp.url.appendingPathComponent("skills/disabled-helper/SKILL.md", isDirectory: false)
        let keptSkill = temp.url.appendingPathComponent("skills/kept-helper/SKILL.md", isDirectory: false)
        try writeDebugSkill(
            name: "disabled-helper",
            description: "Should not be shown.",
            to: disabledSkill
        )
        try writeDebugSkill(
            name: "kept-helper",
            description: "Should stay visible.",
            to: keptSkill
        )
        let stack = try ConfigLayerStack(layers: [
            ConfigLayerEntry(
                name: .user(file: try AbsolutePath(absolutePath: temp.url.appendingPathComponent("config.toml").path)),
                config: .table([
                    "skills": .table([
                        "config": .array([
                            .table([
                                "name": .string("disabled-helper"),
                                "enabled": .bool(false)
                            ])
                        ])
                    ])
                ])
            )
        ])

        let result = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .promptInput(prompt: "inspect", imagePaths: [])),
            dependencies: testDependencies(
                codexHome: temp.url,
                config: CodexRuntimeConfig(
                    model: "gpt-test",
                    modelProvider: "test-provider",
                    includeSkillInstructions: true,
                    projectDocMaxBytes: 0
                ),
                configLayerStack: stack
            )
        )

        let output = try XCTUnwrap(result.stdoutMessage)
        XCTAssertTrue(output.contains("### Available skills"))
        XCTAssertTrue(output.contains("- kept-helper: Should stay visible."))
        XCTAssertFalse(output.contains("disabled-helper"))
        XCTAssertFalse(output.contains("Should not be shown."))
    }

    func testPromptInputExpandsConfiguredEnvironments() async throws {
        let temp = try TemporaryDirectory()

        let result = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .promptInput(prompt: nil, imagePaths: [])),
            dependencies: testDependencies(
                codexHome: temp.url,
                configLayerStack: try ConfigLayerStack(
                    layers: [
                        ConfigLayerEntry(
                            name: .user(file: try AbsolutePath(
                                absolutePath: temp.url.appendingPathComponent("config.toml").path
                            )),
                            config: .table([:])
                        )
                    ],
                    requirements: ConfigRequirements(
                        network: NetworkRequirementsToml(
                            domains: [
                                "api.example.com": .allow,
                                "*.openai.com": .allow,
                                "blocked.example.com": .deny
                            ]
                        )
                    )
                ),
                configuredEnvironments: [
                    TurnEnvironmentSelection(environmentID: "dev", cwd: "/repo/dev"),
                    TurnEnvironmentSelection(environmentID: "local", cwd: "/repo/local")
                ]
            )
        )

        let output = try XCTUnwrap(result.stdoutMessage)
        let decoded = try JSONDecoder().decode([ResponseItem].self, from: Data(output.utf8))
        guard case let .message(_, role, content, _) = decoded[1] else {
            return XCTFail("expected contextual user message")
        }
        XCTAssertEqual(role, "user")
        guard case let .inputText(environmentText) = content.first else {
            return XCTFail("expected environment text")
        }
        XCTAssertTrue(environmentText.contains("<environments>"))
        XCTAssertTrue(environmentText.contains(#"<environment id="dev">"#))
        XCTAssertTrue(environmentText.contains("      <cwd>/repo/dev</cwd>"))
        XCTAssertTrue(environmentText.contains(#"<environment id="local">"#))
        XCTAssertTrue(environmentText.contains("      <cwd>/repo/local</cwd>"))
        XCTAssertTrue(environmentText.contains("  <current_date>2026-02-26</current_date>"))
        XCTAssertTrue(environmentText.contains("  <timezone>America/Los_Angeles</timezone>"))
        XCTAssertTrue(environmentText.contains("  <network enabled=\"true\">"))
        XCTAssertTrue(environmentText.contains("    <allowed>*.openai.com</allowed>"))
        XCTAssertTrue(environmentText.contains("    <allowed>api.example.com</allowed>"))
        XCTAssertTrue(environmentText.contains("    <denied>blocked.example.com</denied>"))
        XCTAssertFalse(environmentText.contains("\n  <cwd>"))
        XCTAssertFalse(environmentText.contains("\n  <shell>"))
    }

    func testPromptInputRendersSingleConfiguredEnvironmentLikeRustSession() async throws {
        let temp = try TemporaryDirectory()

        let result = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .promptInput(prompt: nil, imagePaths: [])),
            dependencies: testDependencies(
                codexHome: temp.url,
                configuredEnvironments: [
                    TurnEnvironmentSelection(environmentID: "local", cwd: "/repo/local")
                ]
            )
        )

        let output = try XCTUnwrap(result.stdoutMessage)
        let decoded = try JSONDecoder().decode([ResponseItem].self, from: Data(output.utf8))
        guard case let .message(_, role, content, _) = decoded[1] else {
            return XCTFail("expected contextual user message")
        }
        XCTAssertEqual(role, "user")
        guard case let .inputText(environmentText) = content.first else {
            return XCTFail("expected environment text")
        }
        XCTAssertTrue(environmentText.contains("  <cwd>/repo/local</cwd>"))
        XCTAssertTrue(environmentText.contains("  <shell>"))
        XCTAssertTrue(environmentText.contains("  <current_date>2026-02-26</current_date>"))
        XCTAssertFalse(environmentText.contains("<approval_policy>"))
        XCTAssertFalse(environmentText.contains("<sandbox_mode>"))
    }

    func testPromptInputHonorsDisabledConfiguredEnvironmentDefault() async throws {
        let temp = try TemporaryDirectory()

        let result = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .promptInput(prompt: nil, imagePaths: [])),
            dependencies: testDependencies(
                codexHome: temp.url,
                configuredEnvironments: []
            )
        )

        let output = try XCTUnwrap(result.stdoutMessage)
        let decoded = try JSONDecoder().decode([ResponseItem].self, from: Data(output.utf8))
        guard case let .message(_, role, content, _) = decoded[1] else {
            return XCTFail("expected contextual user message")
        }
        XCTAssertEqual(role, "user")
        guard case let .inputText(environmentText) = content.first else {
            return XCTFail("expected environment text")
        }
        XCTAssertTrue(environmentText.contains("<environment_context>"))
        XCTAssertTrue(environmentText.contains("  <current_date>2026-02-26</current_date>"))
        XCTAssertFalse(environmentText.contains("<cwd>"))
        XCTAssertFalse(environmentText.contains("<shell>"))
        XCTAssertFalse(environmentText.contains("<approval_policy>"))
        XCTAssertFalse(environmentText.contains("<sandbox_mode>"))
    }

    func testPromptInputOmitsAvailableSkillsWhenDisabled() async throws {
        let temp = try TemporaryDirectory()
        let skill = temp.url.appendingPathComponent("skills/debug-helper/SKILL.md", isDirectory: false)
        try FileManager.default.createDirectory(
            at: skill.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        ---
        name: debug-helper
        description: Inspect debug prompt payloads.
        ---

        Use this when checking debug prompt JSON.
        """.write(to: skill, atomically: true, encoding: .utf8)

        let result = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .promptInput(prompt: nil, imagePaths: [])),
            dependencies: testDependencies(
                codexHome: temp.url,
                config: CodexRuntimeConfig(
                    modelProvider: "test-provider",
                    includeSkillInstructions: false,
                    projectDocMaxBytes: 0
                )
            )
        )

        let output = try XCTUnwrap(result.stdoutMessage)
        let decoded = try JSONDecoder().decode([ResponseItem].self, from: Data(output.utf8))
        guard case let .message(_, _, developerContent, _) = decoded[0] else {
            return XCTFail("expected developer context message")
        }
        XCTAssertEqual(developerContent.count, 1)
        guard case let .inputText(permissionsText) = developerContent[0] else {
            return XCTFail("expected only permissions instructions")
        }
        XCTAssertTrue(permissionsText.contains("<permissions instructions>"))
        XCTAssertFalse(output.contains("### Available skills"))
        XCTAssertFalse(output.contains("debug-helper"))
    }

    func testClearMemoriesClearsStateRowsAndMemoryRoots() async throws {
        let temp = try TemporaryDirectory()
        let statePath = temp.url.appendingPathComponent("state_5.sqlite", isDirectory: false)
        try createMemoryTables(databaseURL: statePath)
        try insertMemoryRows(databaseURL: statePath)

        let memoryRoot = temp.url.appendingPathComponent("memories", isDirectory: true)
        let memoryExtensionRoot = temp.url.appendingPathComponent("memories_extensions", isDirectory: true)
        try FileManager.default.createDirectory(
            at: memoryRoot.appendingPathComponent("rollout_summaries", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: memoryExtensionRoot.appendingPathComponent("ad_hoc/resources", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "stale".write(
            to: memoryRoot.appendingPathComponent("MEMORY.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try "stale".write(
            to: memoryExtensionRoot.appendingPathComponent("ad_hoc/resources/stale.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        // Keep this async test from completing entirely synchronously under Swift 6.2 XCTest.
        await Task.yield()
        let result = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .clearMemories),
            dependencies: testDependencies(codexHome: temp.url)
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(
            result.stdoutMessage,
            "Cleared memory state from \(statePath.path). Cleared memory directories under \(temp.url.path).\n"
        )
        XCTAssertNil(result.stderrMessage)
        XCTAssertEqual(try sqliteCount(databaseURL: statePath, query: "SELECT COUNT(*) FROM stage1_outputs"), 0)
        XCTAssertEqual(
            try sqliteCount(
                databaseURL: statePath,
                query: "SELECT COUNT(*) FROM jobs WHERE kind = 'memory_stage1' OR kind = 'memory_consolidate_global'"
            ),
            0
        )
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: memoryRoot.path), [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: memoryExtensionRoot.path), [])
    }

    func testClearMemoriesReportsMissingStateDBAndStillClearsMemoryRoots() async throws {
        let temp = try TemporaryDirectory()
        let memoryRoot = temp.url.appendingPathComponent("memories", isDirectory: true)
        let memoryExtensionRoot = temp.url.appendingPathComponent("memories_extensions", isDirectory: true)
        try FileManager.default.createDirectory(at: memoryRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: memoryExtensionRoot, withIntermediateDirectories: true)
        try "stale".write(
            to: memoryRoot.appendingPathComponent("MEMORY.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try "stale".write(
            to: memoryExtensionRoot.appendingPathComponent("extension.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        // Keep this async test from completing entirely synchronously under Swift 6.2 XCTest.
        await Task.yield()
        let result = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .clearMemories),
            dependencies: testDependencies(codexHome: temp.url)
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(
            result.stdoutMessage,
            "No state db found at \(temp.url.appendingPathComponent("state_5.sqlite").path). Cleared memory directories under \(temp.url.path).\n"
        )
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: memoryRoot.path), [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: memoryExtensionRoot.path), [])
    }

    func testTraceReduceWritesRustShapedLifecycleStateToDefaultOutput() async throws {
        let temp = try TemporaryDirectory()
        let bundle = temp.url.appendingPathComponent("trace-bundle", isDirectory: true)
        try writeLifecycleTraceBundle(at: bundle)

        let result = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .traceReduce(traceBundle: bundle.path, output: nil)),
            dependencies: testDependencies(codexHome: temp.url)
        )

        let stateURL = bundle.appendingPathComponent("state.json", isDirectory: false)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdoutMessage, "\(stateURL.path)\n")

        let state = try loadJSONObject(at: stateURL)
        XCTAssertEqual(state["schema_version"] as? Int, 1)
        XCTAssertEqual(state["trace_id"] as? String, "trace-1")
        XCTAssertEqual(state["rollout_id"] as? String, "rollout-1")
        XCTAssertEqual(state["root_thread_id"] as? String, "thread-root")
        XCTAssertEqual(state["started_at_unix_ms"] as? Int, 100)
        XCTAssertEqual(state["ended_at_unix_ms"] as? Int, 106)
        XCTAssertEqual(state["status"] as? String, "completed")

        let threads = try XCTUnwrap(state["threads"] as? [String: Any])
        let rootThread = try XCTUnwrap(threads["thread-root"] as? [String: Any])
        XCTAssertEqual(rootThread["agent_path"] as? String, "/root")
        XCTAssertEqual(rootThread["nickname"] as? String, "Main")
        XCTAssertEqual(rootThread["default_model"] as? String, "gpt-test")
        XCTAssertEqual((rootThread["origin"] as? [String: Any])?["type"] as? String, "root")
        let threadExecution = try XCTUnwrap(rootThread["execution"] as? [String: Any])
        XCTAssertEqual(threadExecution["started_seq"] as? Int, 2)
        XCTAssertEqual(threadExecution["ended_seq"] as? Int, 5)
        XCTAssertEqual(threadExecution["status"] as? String, "completed")

        let turns = try XCTUnwrap(state["codex_turns"] as? [String: Any])
        let turn = try XCTUnwrap(turns["turn-1"] as? [String: Any])
        XCTAssertEqual(turn["thread_id"] as? String, "thread-root")
        let turnExecution = try XCTUnwrap(turn["execution"] as? [String: Any])
        XCTAssertEqual(turnExecution["started_at_unix_ms"] as? Int, 103)
        XCTAssertEqual(turnExecution["ended_at_unix_ms"] as? Int, 105)
        XCTAssertEqual(turnExecution["status"] as? String, "completed")

        let rawPayloads = try XCTUnwrap(state["raw_payloads"] as? [String: Any])
        let metadataPayload = try XCTUnwrap(rawPayloads["payload-session"] as? [String: Any])
        XCTAssertEqual(metadataPayload["path"] as? String, "payloads/session.json")
    }

    func testTraceReduceUsesCustomOutputAndSpawnMetadata() async throws {
        let temp = try TemporaryDirectory()
        let bundle = temp.url.appendingPathComponent("trace-bundle", isDirectory: true)
        try writeLifecycleTraceBundle(at: bundle, includeSpawnedThread: true)
        let output = temp.url.appendingPathComponent("custom-state.json", isDirectory: false)

        let result = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .traceReduce(traceBundle: bundle.path, output: output.path)),
            dependencies: testDependencies(codexHome: temp.url)
        )

        XCTAssertEqual(result.stdoutMessage, "\(output.path)\n")
        let state = try loadJSONObject(at: output)
        let threads = try XCTUnwrap(state["threads"] as? [String: Any])
        let childThread = try XCTUnwrap(threads["thread-child"] as? [String: Any])
        XCTAssertEqual(childThread["agent_path"] as? String, "/root/repo_file_counter")
        XCTAssertEqual(childThread["nickname"] as? String, "Kepler")
        let origin = try XCTUnwrap(childThread["origin"] as? [String: Any])
        XCTAssertEqual(origin["type"] as? String, "spawned")
        XCTAssertEqual(origin["parent_thread_id"] as? String, "thread-root")
        XCTAssertEqual(origin["spawn_edge_id"] as? String, "edge:spawn:thread-root:thread-child")
        XCTAssertEqual(origin["task_name"] as? String, "repo_file_counter")
        XCTAssertEqual(origin["agent_role"] as? String, "worker")
    }

    func testTraceReduceRecordsInferenceLifecycleAndUsage() async throws {
        let temp = try TemporaryDirectory()
        let bundle = temp.url.appendingPathComponent("trace-bundle", isDirectory: true)
        let requestPayload: [String: Any] = [
            "raw_payload_id": "payload-request",
            "kind": ["type": "inference_request"],
            "path": "payloads/request.json"
        ]
        let responsePayload: [String: Any] = [
            "raw_payload_id": "payload-response",
            "kind": ["type": "inference_response"],
            "path": "payloads/response.json"
        ]

        try writeTraceBundle(at: bundle, events: [
            traceEvent(seq: 1, wallTime: 101, payload: [
                "type": "rollout_started",
                "trace_id": "trace-1",
                "root_thread_id": "thread-root"
            ]),
            traceEvent(seq: 2, wallTime: 102, payload: [
                "type": "thread_started",
                "thread_id": "thread-root",
                "agent_path": "/root"
            ]),
            traceEvent(seq: 3, wallTime: 103, threadID: "thread-root", payload: [
                "type": "codex_turn_started",
                "codex_turn_id": "turn-1",
                "thread_id": "thread-root"
            ]),
            traceEvent(seq: 4, wallTime: 104, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "inference_started",
                "inference_call_id": "inference-1",
                "thread_id": "thread-root",
                "codex_turn_id": "turn-1",
                "model": "gpt-test",
                "provider_name": "openai",
                "request_payload": requestPayload
            ]),
            traceEvent(seq: 5, wallTime: 106, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "inference_completed",
                "inference_call_id": "inference-1",
                "response_id": "resp-1",
                "upstream_request_id": "req-1",
                "response_payload": responsePayload
            ]),
            traceEvent(seq: 6, wallTime: 107, threadID: "thread-root", payload: [
                "type": "codex_turn_ended",
                "codex_turn_id": "turn-1",
                "status": "completed"
            ])
        ])
        try writeJSONObject(["input": []], to: bundle.appendingPathComponent("payloads/request.json", isDirectory: false))
        try writeJSONObject([
            "response_id": "resp-1",
            "token_usage": [
                "input_tokens": 11,
                "cached_input_tokens": 3,
                "output_tokens": 7,
                "reasoning_output_tokens": 2
            ],
            "output_items": []
        ], to: bundle.appendingPathComponent("payloads/response.json", isDirectory: false))

        let result = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .traceReduce(traceBundle: bundle.path, output: nil)),
            dependencies: testDependencies(codexHome: temp.url)
        )

        XCTAssertEqual(result.exitCode, 0)
        let state = try loadJSONObject(at: bundle.appendingPathComponent("state.json", isDirectory: false))
        let inferences = try XCTUnwrap(state["inference_calls"] as? [String: Any])
        let inference = try XCTUnwrap(inferences["inference-1"] as? [String: Any])
        XCTAssertEqual(inference["thread_id"] as? String, "thread-root")
        XCTAssertEqual(inference["codex_turn_id"] as? String, "turn-1")
        XCTAssertEqual(inference["model"] as? String, "gpt-test")
        XCTAssertEqual(inference["provider_name"] as? String, "openai")
        XCTAssertEqual(inference["response_id"] as? String, "resp-1")
        XCTAssertEqual(inference["upstream_request_id"] as? String, "req-1")
        XCTAssertEqual(inference["raw_request_payload_id"] as? String, "payload-request")
        XCTAssertEqual(inference["raw_response_payload_id"] as? String, "payload-response")
        XCTAssertEqual(inference["request_item_ids"] as? [String], [])
        XCTAssertEqual(inference["response_item_ids"] as? [String], [])

        let execution = try XCTUnwrap(inference["execution"] as? [String: Any])
        XCTAssertEqual(execution["started_seq"] as? Int, 4)
        XCTAssertEqual(execution["ended_seq"] as? Int, 5)
        XCTAssertEqual(execution["status"] as? String, "completed")

        let usage = try XCTUnwrap(inference["usage"] as? [String: Any])
        XCTAssertEqual(usage["input_tokens"] as? Int, 11)
        XCTAssertEqual(usage["cached_input_tokens"] as? Int, 3)
        XCTAssertEqual(usage["output_tokens"] as? Int, 7)
        XCTAssertEqual(usage["reasoning_output_tokens"] as? Int, 2)

        let rawPayloads = try XCTUnwrap(state["raw_payloads"] as? [String: Any])
        XCTAssertNotNil(rawPayloads["payload-request"])
        XCTAssertNotNil(rawPayloads["payload-response"])
    }

    func testTraceReduceReducesConversationSnapshotsAndResponseOutputs() async throws {
        let temp = try TemporaryDirectory()
        let bundle = temp.url.appendingPathComponent("trace-bundle", isDirectory: true)
        let requestPayload: [String: Any] = [
            "raw_payload_id": "payload-request",
            "kind": ["type": "inference_request"],
            "path": "payloads/request.json"
        ]
        let responsePayload: [String: Any] = [
            "raw_payload_id": "payload-response",
            "kind": ["type": "inference_response"],
            "path": "payloads/response.json"
        ]
        try writeTraceBundle(at: bundle, events: [
            traceEvent(seq: 1, wallTime: 101, payload: [
                "type": "rollout_started",
                "trace_id": "trace-1",
                "root_thread_id": "thread-root"
            ]),
            traceEvent(seq: 2, wallTime: 102, payload: [
                "type": "thread_started",
                "thread_id": "thread-root",
                "agent_path": "/root"
            ]),
            traceEvent(seq: 3, wallTime: 103, threadID: "thread-root", payload: [
                "type": "codex_turn_started",
                "codex_turn_id": "turn-1",
                "thread_id": "thread-root"
            ]),
            traceEvent(seq: 4, wallTime: 104, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "inference_started",
                "inference_call_id": "inference-1",
                "thread_id": "thread-root",
                "codex_turn_id": "turn-1",
                "model": "gpt-test",
                "provider_name": "openai",
                "request_payload": requestPayload
            ]),
            traceEvent(seq: 5, wallTime: 105, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "inference_completed",
                "inference_call_id": "inference-1",
                "response_id": "resp-1",
                "response_payload": responsePayload
            ])
        ])
        try writeJSONObject([
            "input": [
                [
                    "type": "message",
                    "role": "user",
                    "content": [["type": "input_text", "text": "run tests"]]
                ]
            ]
        ], to: bundle.appendingPathComponent("payloads/request.json", isDirectory: false))
        try writeJSONObject([
            "response_id": "resp-1",
            "output_items": [
                [
                    "type": "message",
                    "role": "assistant",
                    "content": [["type": "output_text", "text": "tests passed"]]
                ]
            ]
        ], to: bundle.appendingPathComponent("payloads/response.json", isDirectory: false))

        let result = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .traceReduce(traceBundle: bundle.path, output: nil)),
            dependencies: testDependencies(codexHome: temp.url)
        )

        XCTAssertEqual(result.exitCode, 0)
        let state = try loadJSONObject(at: bundle.appendingPathComponent("state.json", isDirectory: false))
        let inferences = try XCTUnwrap(state["inference_calls"] as? [String: Any])
        let inference = try XCTUnwrap(inferences["inference-1"] as? [String: Any])
        XCTAssertEqual(inference["request_item_ids"] as? [String], ["conversation_item:1"])
        XCTAssertEqual(inference["response_item_ids"] as? [String], ["conversation_item:2"])

        let threads = try XCTUnwrap(state["threads"] as? [String: Any])
        let thread = try XCTUnwrap(threads["thread-root"] as? [String: Any])
        XCTAssertEqual(thread["conversation_item_ids"] as? [String], ["conversation_item:1", "conversation_item:2"])

        let items = try XCTUnwrap(state["conversation_items"] as? [String: Any])
        let userItem = try XCTUnwrap(items["conversation_item:1"] as? [String: Any])
        XCTAssertEqual(userItem["role"] as? String, "user")
        XCTAssertEqual(userItem["kind"] as? String, "message")
        let userBody = try XCTUnwrap(userItem["body"] as? [String: Any])
        let userParts = try XCTUnwrap(userBody["parts"] as? [[String: Any]])
        XCTAssertEqual(userParts.first?["text"] as? String, "run tests")

        let assistantItem = try XCTUnwrap(items["conversation_item:2"] as? [String: Any])
        XCTAssertEqual(assistantItem["role"] as? String, "assistant")
        XCTAssertEqual(assistantItem["kind"] as? String, "message")
        let producers = try XCTUnwrap(assistantItem["produced_by"] as? [[String: Any]])
        XCTAssertEqual(producers.first?["type"] as? String, "inference")
        XCTAssertEqual(producers.first?["inference_call_id"] as? String, "inference-1")
        let assistantBody = try XCTUnwrap(assistantItem["body"] as? [String: Any])
        let assistantParts = try XCTUnwrap(assistantBody["parts"] as? [[String: Any]])
        XCTAssertEqual(assistantParts.first?["text"] as? String, "tests passed")
    }

    func testTraceReduceReusesFullSnapshotHistoryWithoutDedupingNewIdenticalItems() async throws {
        let temp = try TemporaryDirectory()
        let bundle = temp.url.appendingPathComponent("trace-bundle", isDirectory: true)
        let firstRequest: [String: Any] = [
            "raw_payload_id": "payload-request-1",
            "kind": ["type": "inference_request"],
            "path": "payloads/request-1.json"
        ]
        let secondRequest: [String: Any] = [
            "raw_payload_id": "payload-request-2",
            "kind": ["type": "inference_request"],
            "path": "payloads/request-2.json"
        ]
        try writeTraceBundle(at: bundle, events: [
            traceEvent(seq: 1, wallTime: 101, payload: [
                "type": "rollout_started",
                "trace_id": "trace-1",
                "root_thread_id": "thread-root"
            ]),
            traceEvent(seq: 2, wallTime: 102, payload: [
                "type": "thread_started",
                "thread_id": "thread-root",
                "agent_path": "/root"
            ]),
            traceEvent(seq: 3, wallTime: 103, threadID: "thread-root", payload: [
                "type": "codex_turn_started",
                "codex_turn_id": "turn-1",
                "thread_id": "thread-root"
            ]),
            traceEvent(seq: 4, wallTime: 104, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "inference_started",
                "inference_call_id": "inference-1",
                "thread_id": "thread-root",
                "codex_turn_id": "turn-1",
                "model": "gpt-test",
                "provider_name": "openai",
                "request_payload": firstRequest
            ]),
            traceEvent(seq: 5, wallTime: 105, threadID: "thread-root", payload: [
                "type": "codex_turn_started",
                "codex_turn_id": "turn-2",
                "thread_id": "thread-root"
            ]),
            traceEvent(seq: 6, wallTime: 106, threadID: "thread-root", codexTurnID: "turn-2", payload: [
                "type": "inference_started",
                "inference_call_id": "inference-2",
                "thread_id": "thread-root",
                "codex_turn_id": "turn-2",
                "model": "gpt-test",
                "provider_name": "openai",
                "request_payload": secondRequest
            ])
        ])
        let okMessage: [String: Any] = [
            "type": "message",
            "role": "user",
            "content": [["type": "input_text", "text": "ok"]]
        ]
        try writeJSONObject(["input": [okMessage]], to: bundle.appendingPathComponent("payloads/request-1.json", isDirectory: false))
        try writeJSONObject([
            "input": [
                okMessage,
                [
                    "type": "message",
                    "role": "assistant",
                    "content": [["type": "output_text", "text": "ack"]]
                ],
                okMessage
            ]
        ], to: bundle.appendingPathComponent("payloads/request-2.json", isDirectory: false))

        let result = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .traceReduce(traceBundle: bundle.path, output: nil)),
            dependencies: testDependencies(codexHome: temp.url)
        )

        XCTAssertEqual(result.exitCode, 0)
        let state = try loadJSONObject(at: bundle.appendingPathComponent("state.json", isDirectory: false))
        let inferences = try XCTUnwrap(state["inference_calls"] as? [String: Any])
        let first = try XCTUnwrap(inferences["inference-1"] as? [String: Any])
        let second = try XCTUnwrap(inferences["inference-2"] as? [String: Any])
        XCTAssertEqual(first["request_item_ids"] as? [String], ["conversation_item:1"])
        XCTAssertEqual(
            second["request_item_ids"] as? [String],
            ["conversation_item:1", "conversation_item:2", "conversation_item:3"]
        )
        let items = try XCTUnwrap(state["conversation_items"] as? [String: Any])
        XCTAssertEqual(items.count, 3)
        let threads = try XCTUnwrap(state["threads"] as? [String: Any])
        let thread = try XCTUnwrap(threads["thread-root"] as? [String: Any])
        XCTAssertEqual(
            thread["conversation_item_ids"] as? [String],
            ["conversation_item:1", "conversation_item:2", "conversation_item:3"]
        )
    }

    func testTraceReduceIncrementalRequestCarriesPriorRequestAndResponseItems() async throws {
        let temp = try TemporaryDirectory()
        let bundle = temp.url.appendingPathComponent("trace-bundle", isDirectory: true)
        let firstRequest: [String: Any] = [
            "raw_payload_id": "payload-request-1",
            "kind": ["type": "inference_request"],
            "path": "payloads/request-1.json"
        ]
        let firstResponse: [String: Any] = [
            "raw_payload_id": "payload-response-1",
            "kind": ["type": "inference_response"],
            "path": "payloads/response-1.json"
        ]
        let secondRequest: [String: Any] = [
            "raw_payload_id": "payload-request-2",
            "kind": ["type": "inference_request"],
            "path": "payloads/request-2.json"
        ]
        try writeTraceBundle(at: bundle, events: [
            traceEvent(seq: 1, wallTime: 101, payload: [
                "type": "rollout_started",
                "trace_id": "trace-1",
                "root_thread_id": "thread-root"
            ]),
            traceEvent(seq: 2, wallTime: 102, payload: [
                "type": "thread_started",
                "thread_id": "thread-root",
                "agent_path": "/root"
            ]),
            traceEvent(seq: 3, wallTime: 103, threadID: "thread-root", payload: [
                "type": "codex_turn_started",
                "codex_turn_id": "turn-1",
                "thread_id": "thread-root"
            ]),
            traceEvent(seq: 4, wallTime: 104, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "inference_started",
                "inference_call_id": "inference-1",
                "thread_id": "thread-root",
                "codex_turn_id": "turn-1",
                "model": "gpt-test",
                "provider_name": "openai",
                "request_payload": firstRequest
            ]),
            traceEvent(seq: 5, wallTime: 105, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "inference_completed",
                "inference_call_id": "inference-1",
                "response_id": "resp-1",
                "response_payload": firstResponse
            ]),
            traceEvent(seq: 6, wallTime: 106, threadID: "thread-root", payload: [
                "type": "codex_turn_started",
                "codex_turn_id": "turn-2",
                "thread_id": "thread-root"
            ]),
            traceEvent(seq: 7, wallTime: 107, threadID: "thread-root", codexTurnID: "turn-2", payload: [
                "type": "inference_started",
                "inference_call_id": "inference-2",
                "thread_id": "thread-root",
                "codex_turn_id": "turn-2",
                "model": "gpt-test",
                "provider_name": "openai",
                "request_payload": secondRequest
            ])
        ])
        try writeJSONObject([
            "input": [
                [
                    "type": "message",
                    "role": "user",
                    "content": [["type": "input_text", "text": "run tests"]]
                ]
            ]
        ], to: bundle.appendingPathComponent("payloads/request-1.json", isDirectory: false))
        try writeJSONObject([
            "response_id": "resp-1",
            "output_items": [
                [
                    "type": "function_call",
                    "name": "shell",
                    "arguments": "{\"cmd\":\"swift test\"}",
                    "call_id": "call-1"
                ]
            ]
        ], to: bundle.appendingPathComponent("payloads/response-1.json", isDirectory: false))
        try writeJSONObject([
            "type": "response.create",
            "previous_response_id": "resp-1",
            "input": [
                [
                    "type": "function_call_output",
                    "call_id": "call-1",
                    "output": "tests passed"
                ]
            ]
        ], to: bundle.appendingPathComponent("payloads/request-2.json", isDirectory: false))

        let result = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .traceReduce(traceBundle: bundle.path, output: nil)),
            dependencies: testDependencies(codexHome: temp.url)
        )

        XCTAssertEqual(result.exitCode, 0)
        let state = try loadJSONObject(at: bundle.appendingPathComponent("state.json", isDirectory: false))
        let inferences = try XCTUnwrap(state["inference_calls"] as? [String: Any])
        let first = try XCTUnwrap(inferences["inference-1"] as? [String: Any])
        let second = try XCTUnwrap(inferences["inference-2"] as? [String: Any])
        XCTAssertEqual(first["request_item_ids"] as? [String], ["conversation_item:1"])
        XCTAssertEqual(first["response_item_ids"] as? [String], ["conversation_item:2"])
        XCTAssertEqual(
            second["request_item_ids"] as? [String],
            ["conversation_item:1", "conversation_item:2", "conversation_item:3"]
        )

        let items = try XCTUnwrap(state["conversation_items"] as? [String: Any])
        let outputItem = try XCTUnwrap(items["conversation_item:3"] as? [String: Any])
        XCTAssertEqual(outputItem["role"] as? String, "tool")
        XCTAssertEqual(outputItem["kind"] as? String, "function_call_output")
        XCTAssertEqual(outputItem["call_id"] as? String, "call-1")
        let threads = try XCTUnwrap(state["threads"] as? [String: Any])
        let thread = try XCTUnwrap(threads["thread-root"] as? [String: Any])
        XCTAssertEqual(
            thread["conversation_item_ids"] as? [String],
            ["conversation_item:1", "conversation_item:2", "conversation_item:3"]
        )
    }

    func testTraceReduceReasoningPreservesTextSummaryAndEncryptedContent() async throws {
        let temp = try TemporaryDirectory()
        let bundle = temp.url.appendingPathComponent("trace-bundle", isDirectory: true)
        let requestPayload: [String: Any] = [
            "raw_payload_id": "payload-request",
            "kind": ["type": "inference_request"],
            "path": "payloads/request.json"
        ]
        let responsePayload: [String: Any] = [
            "raw_payload_id": "payload-response",
            "kind": ["type": "inference_response"],
            "path": "payloads/response.json"
        ]
        try writeTraceBundle(at: bundle, events: [
            traceEvent(seq: 1, wallTime: 101, payload: [
                "type": "rollout_started",
                "trace_id": "trace-1",
                "root_thread_id": "thread-root"
            ]),
            traceEvent(seq: 2, wallTime: 102, payload: [
                "type": "thread_started",
                "thread_id": "thread-root",
                "agent_path": "/root"
            ]),
            traceEvent(seq: 3, wallTime: 103, threadID: "thread-root", payload: [
                "type": "codex_turn_started",
                "codex_turn_id": "turn-1",
                "thread_id": "thread-root"
            ]),
            traceEvent(seq: 4, wallTime: 104, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "inference_started",
                "inference_call_id": "inference-1",
                "thread_id": "thread-root",
                "codex_turn_id": "turn-1",
                "model": "gpt-test",
                "provider_name": "openai",
                "request_payload": requestPayload
            ]),
            traceEvent(seq: 5, wallTime: 105, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "inference_completed",
                "inference_call_id": "inference-1",
                "response_id": "resp-1",
                "response_payload": responsePayload
            ])
        ])
        try writeJSONObject([
            "input": [
                [
                    "type": "message",
                    "role": "user",
                    "content": [["type": "input_text", "text": "think visibly"]]
                ]
            ]
        ], to: bundle.appendingPathComponent("payloads/request.json", isDirectory: false))
        try writeJSONObject([
            "response_id": "resp-1",
            "output_items": [
                [
                    "type": "reasoning",
                    "content": [["type": "reasoning_text", "text": "raw reasoning"]],
                    "summary": [["type": "summary_text", "text": "brief summary"]],
                    "encrypted_content": "encoded-reasoning"
                ]
            ]
        ], to: bundle.appendingPathComponent("payloads/response.json", isDirectory: false))

        let result = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .traceReduce(traceBundle: bundle.path, output: nil)),
            dependencies: testDependencies(codexHome: temp.url)
        )

        XCTAssertEqual(result.exitCode, 0)
        let state = try loadJSONObject(at: bundle.appendingPathComponent("state.json", isDirectory: false))
        let items = try XCTUnwrap(state["conversation_items"] as? [String: Any])
        let reasoning = try XCTUnwrap(items["conversation_item:2"] as? [String: Any])
        XCTAssertEqual(reasoning["role"] as? String, "assistant")
        XCTAssertEqual(reasoning["channel"] as? String, "analysis")
        XCTAssertEqual(reasoning["kind"] as? String, "reasoning")
        let body = try XCTUnwrap(reasoning["body"] as? [String: Any])
        let parts = try XCTUnwrap(body["parts"] as? [[String: Any]])
        XCTAssertEqual(parts.count, 3)
        XCTAssertEqual(parts[0]["type"] as? String, "text")
        XCTAssertEqual(parts[0]["text"] as? String, "raw reasoning")
        XCTAssertEqual(parts[1]["type"] as? String, "summary")
        XCTAssertEqual(parts[1]["text"] as? String, "brief summary")
        XCTAssertEqual(parts[2]["type"] as? String, "encoded")
        XCTAssertEqual(parts[2]["label"] as? String, "encrypted_content")
        XCTAssertEqual(parts[2]["value"] as? String, "encoded-reasoning")
    }

    func testTraceReduceEncryptedReasoningMergesComplementaryReadableSightings() async throws {
        let temp = try TemporaryDirectory()
        let bundle = temp.url.appendingPathComponent("trace-bundle", isDirectory: true)
        let firstRequest: [String: Any] = [
            "raw_payload_id": "payload-request-1",
            "kind": ["type": "inference_request"],
            "path": "payloads/request-1.json"
        ]
        let secondRequest: [String: Any] = [
            "raw_payload_id": "payload-request-2",
            "kind": ["type": "inference_request"],
            "path": "payloads/request-2.json"
        ]
        try writeTraceBundle(at: bundle, events: [
            traceEvent(seq: 1, wallTime: 101, payload: [
                "type": "rollout_started",
                "trace_id": "trace-1",
                "root_thread_id": "thread-root"
            ]),
            traceEvent(seq: 2, wallTime: 102, payload: [
                "type": "thread_started",
                "thread_id": "thread-root",
                "agent_path": "/root"
            ]),
            traceEvent(seq: 3, wallTime: 103, threadID: "thread-root", payload: [
                "type": "codex_turn_started",
                "codex_turn_id": "turn-1",
                "thread_id": "thread-root"
            ]),
            traceEvent(seq: 4, wallTime: 104, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "inference_started",
                "inference_call_id": "inference-1",
                "thread_id": "thread-root",
                "codex_turn_id": "turn-1",
                "model": "gpt-test",
                "provider_name": "openai",
                "request_payload": firstRequest
            ]),
            traceEvent(seq: 5, wallTime: 105, threadID: "thread-root", payload: [
                "type": "codex_turn_started",
                "codex_turn_id": "turn-2",
                "thread_id": "thread-root"
            ]),
            traceEvent(seq: 6, wallTime: 106, threadID: "thread-root", codexTurnID: "turn-2", payload: [
                "type": "inference_started",
                "inference_call_id": "inference-2",
                "thread_id": "thread-root",
                "codex_turn_id": "turn-2",
                "model": "gpt-test",
                "provider_name": "openai",
                "request_payload": secondRequest
            ])
        ])
        let user: [String: Any] = [
            "type": "message",
            "role": "user",
            "content": [["type": "input_text", "text": "count files"]]
        ]
        try writeJSONObject([
            "input": [
                user,
                [
                    "type": "reasoning",
                    "content": [["type": "text", "text": "need count"]],
                    "summary": [],
                    "encrypted_content": "encoded-reasoning"
                ]
            ]
        ], to: bundle.appendingPathComponent("payloads/request-1.json", isDirectory: false))
        try writeJSONObject([
            "input": [
                user,
                [
                    "type": "reasoning",
                    "summary": [["type": "summary_text", "text": "counting files"]],
                    "encrypted_content": "encoded-reasoning"
                ]
            ]
        ], to: bundle.appendingPathComponent("payloads/request-2.json", isDirectory: false))

        let result = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .traceReduce(traceBundle: bundle.path, output: nil)),
            dependencies: testDependencies(codexHome: temp.url)
        )

        XCTAssertEqual(result.exitCode, 0)
        let state = try loadJSONObject(at: bundle.appendingPathComponent("state.json", isDirectory: false))
        let inferences = try XCTUnwrap(state["inference_calls"] as? [String: Any])
        let first = try XCTUnwrap(inferences["inference-1"] as? [String: Any])
        let second = try XCTUnwrap(inferences["inference-2"] as? [String: Any])
        XCTAssertEqual(first["request_item_ids"] as? [String], ["conversation_item:1", "conversation_item:2"])
        XCTAssertEqual(second["request_item_ids"] as? [String], ["conversation_item:1", "conversation_item:2"])

        let items = try XCTUnwrap(state["conversation_items"] as? [String: Any])
        XCTAssertEqual(items.count, 2)
        let reasoning = try XCTUnwrap(items["conversation_item:2"] as? [String: Any])
        let body = try XCTUnwrap(reasoning["body"] as? [String: Any])
        let parts = try XCTUnwrap(body["parts"] as? [[String: Any]])
        XCTAssertEqual(parts.count, 3)
        XCTAssertEqual(parts[0]["type"] as? String, "text")
        XCTAssertEqual(parts[0]["text"] as? String, "need count")
        XCTAssertEqual(parts[1]["type"] as? String, "summary")
        XCTAssertEqual(parts[1]["text"] as? String, "counting files")
        XCTAssertEqual(parts[2]["type"] as? String, "encoded")
        XCTAssertEqual(parts[2]["value"] as? String, "encoded-reasoning")
    }

    func testTraceReduceClosesRunningInferenceOnTurnEndAndPreservesLatePartialPayload() async throws {
        let temp = try TemporaryDirectory()
        let bundle = temp.url.appendingPathComponent("trace-bundle", isDirectory: true)
        let requestPayload: [String: Any] = [
            "raw_payload_id": "payload-request",
            "kind": ["type": "inference_request"],
            "path": "payloads/request.json"
        ]
        let partialResponsePayload: [String: Any] = [
            "raw_payload_id": "payload-partial-response",
            "kind": ["type": "inference_response"],
            "path": "payloads/partial-response.json"
        ]

        try writeTraceBundle(at: bundle, events: [
            traceEvent(seq: 1, wallTime: 101, payload: [
                "type": "thread_started",
                "thread_id": "thread-root",
                "agent_path": "/root"
            ]),
            traceEvent(seq: 2, wallTime: 102, threadID: "thread-root", payload: [
                "type": "codex_turn_started",
                "codex_turn_id": "turn-1",
                "thread_id": "thread-root"
            ]),
            traceEvent(seq: 3, wallTime: 103, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "inference_started",
                "inference_call_id": "inference-1",
                "thread_id": "thread-root",
                "codex_turn_id": "turn-1",
                "model": "gpt-test",
                "provider_name": "openai",
                "request_payload": requestPayload
            ]),
            traceEvent(seq: 4, wallTime: 104, threadID: "thread-root", payload: [
                "type": "codex_turn_ended",
                "codex_turn_id": "turn-1",
                "status": "failed"
            ]),
            traceEvent(seq: 5, wallTime: 105, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "inference_cancelled",
                "inference_call_id": "inference-1",
                "upstream_request_id": "req-late",
                "reason": "stream mapper noticed cancellation after turn end",
                "partial_response_payload": partialResponsePayload
            ])
        ])
        try writeJSONObject(["input": []], to: bundle.appendingPathComponent("payloads/request.json", isDirectory: false))
        try writeJSONObject([
            "response_id": NSNull(),
            "token_usage": NSNull(),
            "output_items": []
        ], to: bundle.appendingPathComponent("payloads/partial-response.json", isDirectory: false))

        _ = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .traceReduce(traceBundle: bundle.path, output: nil)),
            dependencies: testDependencies(codexHome: temp.url)
        )

        let state = try loadJSONObject(at: bundle.appendingPathComponent("state.json", isDirectory: false))
        let inferences = try XCTUnwrap(state["inference_calls"] as? [String: Any])
        let inference = try XCTUnwrap(inferences["inference-1"] as? [String: Any])
        let execution = try XCTUnwrap(inference["execution"] as? [String: Any])
        XCTAssertEqual(execution["status"] as? String, "failed")
        XCTAssertEqual(execution["ended_seq"] as? Int, 4)
        XCTAssertEqual(inference["upstream_request_id"] as? String, "req-late")
        XCTAssertEqual(inference["raw_response_payload_id"] as? String, "payload-partial-response")
    }

    func testTraceReduceRecordsToolCallLifecycleAndRawPayloads() async throws {
        let temp = try TemporaryDirectory()
        let bundle = temp.url.appendingPathComponent("trace-bundle", isDirectory: true)
        let invocationPayload: [String: Any] = [
            "raw_payload_id": "payload-tool-invocation",
            "kind": ["type": "tool_invocation"],
            "path": "payloads/tool-invocation.json"
        ]
        let runtimeStartPayload: [String: Any] = [
            "raw_payload_id": "payload-tool-runtime-start",
            "kind": ["type": "tool_runtime_event"],
            "path": "payloads/tool-runtime-start.json"
        ]
        let runtimeEndPayload: [String: Any] = [
            "raw_payload_id": "payload-tool-runtime-end",
            "kind": ["type": "tool_runtime_event"],
            "path": "payloads/tool-runtime-end.json"
        ]
        let resultPayload: [String: Any] = [
            "raw_payload_id": "payload-tool-result",
            "kind": ["type": "tool_result"],
            "path": "payloads/tool-result.json"
        ]

        try writeTraceBundle(at: bundle, events: [
            traceEvent(seq: 1, wallTime: 101, payload: [
                "type": "thread_started",
                "thread_id": "thread-root",
                "agent_path": "/root"
            ]),
            traceEvent(seq: 2, wallTime: 102, threadID: "thread-root", payload: [
                "type": "codex_turn_started",
                "codex_turn_id": "turn-1",
                "thread_id": "thread-root"
            ]),
            traceEvent(seq: 3, wallTime: 103, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "tool_call_started",
                "tool_call_id": "tool-1",
                "model_visible_call_id": "call-1",
                "code_mode_runtime_tool_id": NSNull(),
                "requester": ["type": "model"],
                "kind": ["type": "other", "name": "lookup"],
                "summary": [
                    "type": "generic",
                    "label": "lookup",
                    "input_preview": "find",
                    "output_preview": NSNull()
                ],
                "invocation_payload": invocationPayload
            ]),
            traceEvent(seq: 4, wallTime: 104, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "tool_call_runtime_started",
                "tool_call_id": "tool-1",
                "runtime_payload": runtimeStartPayload
            ]),
            traceEvent(seq: 5, wallTime: 105, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "tool_call_runtime_ended",
                "tool_call_id": "tool-1",
                "status": "completed",
                "runtime_payload": runtimeEndPayload
            ]),
            traceEvent(seq: 6, wallTime: 106, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "tool_call_ended",
                "tool_call_id": "tool-1",
                "status": "completed",
                "result_payload": resultPayload
            ])
        ])

        let result = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .traceReduce(traceBundle: bundle.path, output: nil)),
            dependencies: testDependencies(codexHome: temp.url)
        )

        XCTAssertEqual(result.exitCode, 0)
        let state = try loadJSONObject(at: bundle.appendingPathComponent("state.json", isDirectory: false))
        let toolCalls = try XCTUnwrap(state["tool_calls"] as? [String: Any])
        let toolCall = try XCTUnwrap(toolCalls["tool-1"] as? [String: Any])
        XCTAssertEqual(toolCall["model_visible_call_id"] as? String, "call-1")
        XCTAssertEqual(toolCall["thread_id"] as? String, "thread-root")
        XCTAssertEqual(toolCall["started_by_codex_turn_id"] as? String, "turn-1")
        XCTAssertEqual(toolCall["raw_invocation_payload_id"] as? String, "payload-tool-invocation")
        XCTAssertEqual(toolCall["raw_result_payload_id"] as? String, "payload-tool-result")
        XCTAssertEqual(
            toolCall["raw_runtime_payload_ids"] as? [String],
            ["payload-tool-runtime-start", "payload-tool-runtime-end"]
        )
        XCTAssertEqual(toolCall["model_visible_call_item_ids"] as? [String], [])
        XCTAssertEqual(toolCall["model_visible_output_item_ids"] as? [String], [])
        XCTAssertNil(toolCall["terminal_operation_id"] as? String)

        let requester = try XCTUnwrap(toolCall["requester"] as? [String: Any])
        XCTAssertEqual(requester["type"] as? String, "model")
        let kind = try XCTUnwrap(toolCall["kind"] as? [String: Any])
        XCTAssertEqual(kind["type"] as? String, "other")
        XCTAssertEqual(kind["name"] as? String, "lookup")
        let summary = try XCTUnwrap(toolCall["summary"] as? [String: Any])
        XCTAssertEqual(summary["type"] as? String, "generic")
        XCTAssertEqual(summary["label"] as? String, "lookup")

        let execution = try XCTUnwrap(toolCall["execution"] as? [String: Any])
        XCTAssertEqual(execution["started_seq"] as? Int, 3)
        XCTAssertEqual(execution["ended_seq"] as? Int, 6)
        XCTAssertEqual(execution["status"] as? String, "completed")

        let rawPayloads = try XCTUnwrap(state["raw_payloads"] as? [String: Any])
        XCTAssertNotNil(rawPayloads["payload-tool-invocation"])
        XCTAssertNotNil(rawPayloads["payload-tool-runtime-start"])
        XCTAssertNotNil(rawPayloads["payload-tool-runtime-end"])
        XCTAssertNotNil(rawPayloads["payload-tool-result"])
    }

    func testTraceReduceRecordsAgentInteractionEdges() async throws {
        let temp = try TemporaryDirectory()
        let bundle = temp.url.appendingPathComponent("trace-bundle", isDirectory: true)
        let spawnInvocation = rawPayloadRef("payload-spawn-invocation", kind: "tool_invocation")
        let spawnRuntimeStart = rawPayloadRef("payload-spawn-runtime-start", kind: "tool_runtime_event")
        let spawnRuntimeEnd = rawPayloadRef("payload-spawn-runtime-end", kind: "tool_runtime_event")
        let spawnResult = rawPayloadRef("payload-spawn-result", kind: "tool_result")
        let childFirstRequest = rawPayloadRef("payload-child-first-request", kind: "inference_request")
        let childSecondRequest = rawPayloadRef("payload-child-second-request", kind: "inference_request")
        let childAnswerRequest = rawPayloadRef("payload-child-answer-request", kind: "inference_request")
        let childAnswerResponse = rawPayloadRef("payload-child-answer-response", kind: "inference_response")
        let sendInvocation = rawPayloadRef("payload-send-invocation", kind: "tool_invocation")
        let sendRuntimeStart = rawPayloadRef("payload-send-runtime-start", kind: "tool_runtime_event")
        let sendRuntimeEnd = rawPayloadRef("payload-send-runtime-end", kind: "tool_runtime_event")
        let sendResult = rawPayloadRef("payload-send-result", kind: "tool_result")
        let closeInvocation = rawPayloadRef("payload-close-invocation", kind: "tool_invocation")
        let closeRuntimeStart = rawPayloadRef("payload-close-runtime-start", kind: "tool_runtime_event")
        let closeRuntimeEnd = rawPayloadRef("payload-close-runtime-end", kind: "tool_runtime_event")
        let closeResult = rawPayloadRef("payload-close-result", kind: "tool_result")
        let carriedResult = rawPayloadRef("payload-agent-result", kind: "agent_result")
        let parentNotificationRequest = rawPayloadRef("payload-parent-notification-request", kind: "inference_request")

        try writeTraceBundle(at: bundle, events: [
            traceEvent(seq: 1, wallTime: 101, payload: [
                "type": "rollout_started",
                "trace_id": "trace-1",
                "root_thread_id": "thread-root"
            ]),
            traceEvent(seq: 2, wallTime: 102, payload: [
                "type": "thread_started",
                "thread_id": "thread-root",
                "agent_path": "/root"
            ]),
            traceEvent(seq: 3, wallTime: 103, threadID: "thread-root", payload: [
                "type": "codex_turn_started",
                "codex_turn_id": "turn-root",
                "thread_id": "thread-root"
            ]),
            traceEvent(seq: 4, wallTime: 104, threadID: "thread-root", codexTurnID: "turn-root", payload: [
                "type": "tool_call_started",
                "tool_call_id": "call-spawn",
                "model_visible_call_id": NSNull(),
                "code_mode_runtime_tool_id": NSNull(),
                "requester": ["type": "model"],
                "kind": ["type": "spawn_agent"],
                "summary": ["type": "generic", "label": "spawn_agent"],
                "invocation_payload": spawnInvocation
            ]),
            traceEvent(seq: 5, wallTime: 105, threadID: "thread-root", codexTurnID: "turn-root", payload: [
                "type": "tool_call_runtime_started",
                "tool_call_id": "call-spawn",
                "runtime_payload": spawnRuntimeStart
            ]),
            traceEvent(seq: 6, wallTime: 106, threadID: "thread-root", codexTurnID: "turn-root", payload: [
                "type": "tool_call_runtime_ended",
                "tool_call_id": "call-spawn",
                "status": "completed",
                "runtime_payload": spawnRuntimeEnd
            ]),
            traceEvent(seq: 7, wallTime: 107, threadID: "thread-root", codexTurnID: "turn-root", payload: [
                "type": "tool_call_ended",
                "tool_call_id": "call-spawn",
                "status": "completed",
                "result_payload": spawnResult
            ]),
            traceEvent(seq: 8, wallTime: 108, payload: [
                "type": "thread_started",
                "thread_id": "thread-child",
                "agent_path": "/root/child"
            ]),
            traceEvent(seq: 9, wallTime: 109, threadID: "thread-child", payload: [
                "type": "codex_turn_started",
                "codex_turn_id": "turn-child",
                "thread_id": "thread-child"
            ]),
            traceEvent(seq: 10, wallTime: 110, threadID: "thread-child", codexTurnID: "turn-child", payload: [
                "type": "inference_started",
                "inference_call_id": "child-first",
                "thread_id": "thread-child",
                "codex_turn_id": "turn-child",
                "model": "gpt-test",
                "provider_name": "openai",
                "request_payload": childFirstRequest
            ]),
            traceEvent(seq: 11, wallTime: 111, threadID: "thread-root", codexTurnID: "turn-root", payload: [
                "type": "tool_call_started",
                "tool_call_id": "call-send",
                "model_visible_call_id": NSNull(),
                "code_mode_runtime_tool_id": NSNull(),
                "requester": ["type": "model"],
                "kind": ["type": "send_message"],
                "summary": ["type": "generic", "label": "send_message"],
                "invocation_payload": sendInvocation
            ]),
            traceEvent(seq: 12, wallTime: 112, threadID: "thread-root", codexTurnID: "turn-root", payload: [
                "type": "tool_call_runtime_started",
                "tool_call_id": "call-send",
                "runtime_payload": sendRuntimeStart
            ]),
            traceEvent(seq: 13, wallTime: 113, threadID: "thread-root", codexTurnID: "turn-root", payload: [
                "type": "tool_call_runtime_ended",
                "tool_call_id": "call-send",
                "status": "completed",
                "runtime_payload": sendRuntimeEnd
            ]),
            traceEvent(seq: 14, wallTime: 114, threadID: "thread-root", codexTurnID: "turn-root", payload: [
                "type": "tool_call_ended",
                "tool_call_id": "call-send",
                "status": "completed",
                "result_payload": sendResult
            ]),
            traceEvent(seq: 15, wallTime: 115, threadID: "thread-child", codexTurnID: "turn-child", payload: [
                "type": "inference_started",
                "inference_call_id": "child-second",
                "thread_id": "thread-child",
                "codex_turn_id": "turn-child",
                "model": "gpt-test",
                "provider_name": "openai",
                "request_payload": childSecondRequest
            ]),
            traceEvent(seq: 16, wallTime: 116, threadID: "thread-child", codexTurnID: "turn-child", payload: [
                "type": "inference_started",
                "inference_call_id": "child-answer",
                "thread_id": "thread-child",
                "codex_turn_id": "turn-child",
                "model": "gpt-test",
                "provider_name": "openai",
                "request_payload": childAnswerRequest
            ]),
            traceEvent(seq: 17, wallTime: 117, threadID: "thread-child", codexTurnID: "turn-child", payload: [
                "type": "inference_completed",
                "inference_call_id": "child-answer",
                "response_id": "resp-child-answer",
                "response_payload": childAnswerResponse
            ]),
            traceEvent(seq: 18, wallTime: 118, threadID: "thread-root", codexTurnID: "turn-root", payload: [
                "type": "tool_call_started",
                "tool_call_id": "call-close",
                "model_visible_call_id": NSNull(),
                "code_mode_runtime_tool_id": NSNull(),
                "requester": ["type": "model"],
                "kind": ["type": "close_agent"],
                "summary": ["type": "generic", "label": "close_agent"],
                "invocation_payload": closeInvocation
            ]),
            traceEvent(seq: 19, wallTime: 119, threadID: "thread-root", codexTurnID: "turn-root", payload: [
                "type": "tool_call_runtime_started",
                "tool_call_id": "call-close",
                "runtime_payload": closeRuntimeStart
            ]),
            traceEvent(seq: 20, wallTime: 120, threadID: "thread-root", codexTurnID: "turn-root", payload: [
                "type": "tool_call_runtime_ended",
                "tool_call_id": "call-close",
                "status": "completed",
                "runtime_payload": closeRuntimeEnd
            ]),
            traceEvent(seq: 21, wallTime: 121, threadID: "thread-root", codexTurnID: "turn-root", payload: [
                "type": "tool_call_ended",
                "tool_call_id": "call-close",
                "status": "completed",
                "result_payload": closeResult
            ]),
            traceEvent(seq: 22, wallTime: 122, payload: [
                "type": "agent_result_observed",
                "edge_id": "edge:agent-result:thread-child:turn-child:thread-root",
                "child_thread_id": "thread-child",
                "child_codex_turn_id": "turn-child",
                "parent_thread_id": "thread-root",
                "message": "done",
                "carried_payload": carriedResult
            ]),
            traceEvent(seq: 23, wallTime: 123, threadID: "thread-root", codexTurnID: "turn-root", payload: [
                "type": "inference_started",
                "inference_call_id": "parent-notification",
                "thread_id": "thread-root",
                "codex_turn_id": "turn-root",
                "model": "gpt-test",
                "provider_name": "openai",
                "request_payload": parentNotificationRequest
            ])
        ])

        let payloads = bundle.appendingPathComponent("payloads", isDirectory: true)
        try writeJSONObject([
            "sender_thread_id": "thread-root",
            "new_thread_id": "thread-child",
            "prompt": "count files"
        ], to: payloads.appendingPathComponent("payload-spawn-runtime-end.json", isDirectory: false))
        try writeJSONObject([
            "input": [
                interAgentMessage(author: "/root", recipient: "/root/child", content: "count files")
            ]
        ], to: payloads.appendingPathComponent("payload-child-first-request.json", isDirectory: false))
        try writeJSONObject([
            "input": [
                interAgentMessage(author: "/root", recipient: "/root/child", content: "count files"),
                interAgentMessage(author: "/root", recipient: "/root/child", content: "status?")
            ]
        ], to: payloads.appendingPathComponent("payload-child-second-request.json", isDirectory: false))
        try writeJSONObject([
            "input": [
                interAgentMessage(author: "/root", recipient: "/root/child", content: "count files"),
                interAgentMessage(author: "/root", recipient: "/root/child", content: "status?")
            ]
        ], to: payloads.appendingPathComponent("payload-child-answer-request.json", isDirectory: false))
        try writeJSONObject([
            "response_id": "resp-child-answer",
            "output_items": [
                [
                    "type": "message",
                    "role": "assistant",
                    "content": [["type": "output_text", "text": "done"]]
                ]
            ]
        ], to: payloads.appendingPathComponent("payload-child-answer-response.json", isDirectory: false))
        try writeJSONObject([
            "receiver_thread_id": "thread-child",
            "prompt": "status?"
        ], to: payloads.appendingPathComponent("payload-send-runtime-start.json", isDirectory: false))
        try writeJSONObject([
            "receiver_thread_id": "thread-child",
            "prompt": "status?"
        ], to: payloads.appendingPathComponent("payload-send-runtime-end.json", isDirectory: false))
        try writeJSONObject([
            "receiver_thread_id": "thread-child"
        ], to: payloads.appendingPathComponent("payload-close-runtime-start.json", isDirectory: false))
        try writeJSONObject([
            "receiver_thread_id": "thread-child"
        ], to: payloads.appendingPathComponent("payload-close-runtime-end.json", isDirectory: false))
        try writeJSONObject([
            "input": [
                interAgentMessage(author: "/root/child", recipient: "/root", content: "done")
            ]
        ], to: payloads.appendingPathComponent("payload-parent-notification-request.json", isDirectory: false))

        _ = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .traceReduce(traceBundle: bundle.path, output: nil)),
            dependencies: testDependencies(codexHome: temp.url)
        )

        let state = try loadJSONObject(at: bundle.appendingPathComponent("state.json", isDirectory: false))
        let edges = try XCTUnwrap(state["interaction_edges"] as? [String: Any])

        let spawnEdge = try XCTUnwrap(edges["edge:spawn:thread-root:thread-child"] as? [String: Any])
        XCTAssertEqual(spawnEdge["kind"] as? String, "spawn_agent")
        XCTAssertEqual((spawnEdge["source"] as? [String: Any])?["tool_call_id"] as? String, "call-spawn")
        XCTAssertEqual((spawnEdge["target"] as? [String: Any])?["item_id"] as? String, "conversation_item:1")
        XCTAssertEqual(spawnEdge["started_at_unix_ms"] as? Int, 104)
        XCTAssertEqual(spawnEdge["ended_at_unix_ms"] as? Int, 106)
        XCTAssertEqual(spawnEdge["carried_item_ids"] as? [String], ["conversation_item:1"])
        XCTAssertEqual(spawnEdge["carried_raw_payload_ids"] as? [String], [
            "payload-spawn-invocation",
            "payload-spawn-runtime-start",
            "payload-spawn-runtime-end",
            "payload-spawn-result"
        ])

        let sendEdge = try XCTUnwrap(edges["edge:tool:call-send"] as? [String: Any])
        XCTAssertEqual(sendEdge["kind"] as? String, "send_message")
        XCTAssertEqual((sendEdge["target"] as? [String: Any])?["item_id"] as? String, "conversation_item:2")
        XCTAssertEqual(sendEdge["ended_at_unix_ms"] as? Int, 113)
        XCTAssertEqual(sendEdge["carried_raw_payload_ids"] as? [String], [
            "payload-send-invocation",
            "payload-send-runtime-start",
            "payload-send-runtime-end",
            "payload-send-result"
        ])

        let closeEdge = try XCTUnwrap(edges["edge:tool:call-close"] as? [String: Any])
        XCTAssertEqual(closeEdge["kind"] as? String, "close_agent")
        XCTAssertEqual((closeEdge["target"] as? [String: Any])?["type"] as? String, "thread")
        XCTAssertEqual((closeEdge["target"] as? [String: Any])?["thread_id"] as? String, "thread-child")
        XCTAssertEqual(closeEdge["carried_item_ids"] as? [String], [])
        XCTAssertEqual(closeEdge["ended_at_unix_ms"] as? Int, 120)

        let resultEdge = try XCTUnwrap(edges["edge:agent-result:thread-child:turn-child:thread-root"] as? [String: Any])
        XCTAssertEqual(resultEdge["kind"] as? String, "agent_result")
        XCTAssertEqual((resultEdge["source"] as? [String: Any])?["item_id"] as? String, "conversation_item:3")
        XCTAssertEqual((resultEdge["target"] as? [String: Any])?["item_id"] as? String, "conversation_item:4")
        XCTAssertEqual(resultEdge["carried_item_ids"] as? [String], ["conversation_item:4"])
        XCTAssertEqual(resultEdge["carried_raw_payload_ids"] as? [String], ["payload-agent-result"])

        let rawPayloads = try XCTUnwrap(state["raw_payloads"] as? [String: Any])
        XCTAssertNotNil(rawPayloads["payload-agent-result"])
    }

    func testTraceReduceFallsBackSpawnInteractionEdgeToChildThread() async throws {
        let temp = try TemporaryDirectory()
        let bundle = temp.url.appendingPathComponent("trace-bundle", isDirectory: true)
        let invocationPayload = rawPayloadRef("payload-spawn-invocation", kind: "tool_invocation")
        let runtimePayload = rawPayloadRef("payload-spawn-runtime-end", kind: "tool_runtime_event")

        try writeTraceBundle(at: bundle, events: [
            traceEvent(seq: 1, wallTime: 101, payload: [
                "type": "thread_started",
                "thread_id": "thread-root",
                "agent_path": "/root"
            ]),
            traceEvent(seq: 2, wallTime: 102, threadID: "thread-root", payload: [
                "type": "codex_turn_started",
                "codex_turn_id": "turn-root",
                "thread_id": "thread-root"
            ]),
            traceEvent(seq: 3, wallTime: 103, threadID: "thread-root", codexTurnID: "turn-root", payload: [
                "type": "tool_call_started",
                "tool_call_id": "call-spawn",
                "model_visible_call_id": NSNull(),
                "code_mode_runtime_tool_id": NSNull(),
                "requester": ["type": "model"],
                "kind": ["type": "spawn_agent"],
                "summary": ["type": "generic", "label": "spawn_agent"],
                "invocation_payload": invocationPayload
            ]),
            traceEvent(seq: 4, wallTime: 104, threadID: "thread-root", codexTurnID: "turn-root", payload: [
                "type": "tool_call_runtime_ended",
                "tool_call_id": "call-spawn",
                "status": "completed",
                "runtime_payload": runtimePayload
            ]),
            traceEvent(seq: 5, wallTime: 105, payload: [
                "type": "thread_started",
                "thread_id": "thread-child",
                "agent_path": "/root/child"
            ])
        ])

        try writeJSONObject([
            "sender_thread_id": "thread-root",
            "new_thread_id": "thread-child",
            "prompt": "count files"
        ], to: bundle.appendingPathComponent("payloads/payload-spawn-runtime-end.json", isDirectory: false))

        _ = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .traceReduce(traceBundle: bundle.path, output: nil)),
            dependencies: testDependencies(codexHome: temp.url)
        )

        let state = try loadJSONObject(at: bundle.appendingPathComponent("state.json", isDirectory: false))
        let edges = try XCTUnwrap(state["interaction_edges"] as? [String: Any])
        let edge = try XCTUnwrap(edges["edge:spawn:thread-root:thread-child"] as? [String: Any])
        XCTAssertEqual(edge["kind"] as? String, "spawn_agent")
        XCTAssertEqual((edge["target"] as? [String: Any])?["type"] as? String, "thread")
        XCTAssertEqual((edge["target"] as? [String: Any])?["thread_id"] as? String, "thread-child")
        XCTAssertEqual(edge["carried_item_ids"] as? [String], [])
    }

    func testTraceReduceRecordsExecTerminalOperationAndSession() async throws {
        let temp = try TemporaryDirectory()
        let bundle = temp.url.appendingPathComponent("trace-bundle", isDirectory: true)
        let invocationPayload: [String: Any] = [
            "raw_payload_id": "payload-tool-invocation",
            "kind": ["type": "tool_invocation"],
            "path": "payloads/tool-invocation.json"
        ]
        let runtimeStartPayload: [String: Any] = [
            "raw_payload_id": "payload-terminal-start",
            "kind": ["type": "tool_runtime_event"],
            "path": "payloads/terminal-start.json"
        ]
        let runtimeEndPayload: [String: Any] = [
            "raw_payload_id": "payload-terminal-end",
            "kind": ["type": "tool_runtime_event"],
            "path": "payloads/terminal-end.json"
        ]
        let resultPayload: [String: Any] = [
            "raw_payload_id": "payload-tool-result",
            "kind": ["type": "tool_result"],
            "path": "payloads/tool-result.json"
        ]
        let firstRequestPayload: [String: Any] = [
            "raw_payload_id": "payload-request-1",
            "kind": ["type": "inference_request"],
            "path": "payloads/request-1.json"
        ]
        let firstResponsePayload: [String: Any] = [
            "raw_payload_id": "payload-response-1",
            "kind": ["type": "inference_response"],
            "path": "payloads/response-1.json"
        ]
        let secondRequestPayload: [String: Any] = [
            "raw_payload_id": "payload-request-2",
            "kind": ["type": "inference_request"],
            "path": "payloads/request-2.json"
        ]

        try writeTraceBundle(at: bundle, events: [
            traceEvent(seq: 1, wallTime: 101, payload: [
                "type": "thread_started",
                "thread_id": "thread-root",
                "agent_path": "/root"
            ]),
            traceEvent(seq: 2, wallTime: 102, threadID: "thread-root", payload: [
                "type": "codex_turn_started",
                "codex_turn_id": "turn-1",
                "thread_id": "thread-root"
            ]),
            traceEvent(seq: 3, wallTime: 103, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "tool_call_started",
                "tool_call_id": "tool-1",
                "model_visible_call_id": "call-1",
                "code_mode_runtime_tool_id": NSNull(),
                "requester": ["type": "model"],
                "kind": ["type": "exec_command"],
                "summary": [
                    "type": "generic",
                    "label": "exec_command",
                    "input_preview": "cargo test",
                    "output_preview": NSNull()
                ],
                "invocation_payload": invocationPayload
            ]),
            traceEvent(seq: 4, wallTime: 104, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "tool_call_runtime_started",
                "tool_call_id": "tool-1",
                "runtime_payload": runtimeStartPayload
            ]),
            traceEvent(seq: 5, wallTime: 105, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "tool_call_runtime_ended",
                "tool_call_id": "tool-1",
                "status": "completed",
                "runtime_payload": runtimeEndPayload
            ]),
            traceEvent(seq: 6, wallTime: 106, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "tool_call_ended",
                "tool_call_id": "tool-1",
                "status": "completed",
                "result_payload": resultPayload
            ]),
            traceEvent(seq: 7, wallTime: 107, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "inference_started",
                "inference_call_id": "inference-1",
                "thread_id": "thread-root",
                "codex_turn_id": "turn-1",
                "model": "gpt-test",
                "provider_name": "openai",
                "request_payload": firstRequestPayload
            ]),
            traceEvent(seq: 8, wallTime: 108, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "inference_completed",
                "inference_call_id": "inference-1",
                "response_id": "resp-1",
                "response_payload": firstResponsePayload
            ]),
            traceEvent(seq: 9, wallTime: 109, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "inference_started",
                "inference_call_id": "inference-2",
                "thread_id": "thread-root",
                "codex_turn_id": "turn-1",
                "model": "gpt-test",
                "provider_name": "openai",
                "request_payload": secondRequestPayload
            ])
        ])
        try writeJSONObject([
            "tool_name": "exec_command",
            "tool_namespace": NSNull(),
            "payload": [
                "type": "function",
                "arguments": "{\"cmd\":\"cargo test\"}"
            ]
        ], to: bundle.appendingPathComponent("payloads/tool-invocation.json", isDirectory: false))
        try writeJSONObject([
            "call_id": "tool-1",
            "turn_id": "turn-1",
            "command": ["cargo", "test"],
            "cwd": "/repo"
        ], to: bundle.appendingPathComponent("payloads/terminal-start.json", isDirectory: false))
        try writeJSONObject([
            "call_id": "tool-1",
            "process_id": "pty-1",
            "turn_id": "turn-1",
            "command": ["cargo", "test"],
            "cwd": "/repo",
            "stdout": "ok\n",
            "stderr": "",
            "exit_code": 0,
            "formatted_output": "ok\n",
            "status": "completed"
        ], to: bundle.appendingPathComponent("payloads/terminal-end.json", isDirectory: false))
        try writeJSONObject([
            "type": "direct_response",
            "response_item": [
                "type": "function_call_output",
                "call_id": "call-1",
                "output": "ok\n"
            ]
        ], to: bundle.appendingPathComponent("payloads/tool-result.json", isDirectory: false))
        try writeJSONObject([
            "input": []
        ], to: bundle.appendingPathComponent("payloads/request-1.json", isDirectory: false))
        try writeJSONObject([
            "response_id": "resp-1",
            "output_items": [
                [
                    "type": "function_call",
                    "name": "exec_command",
                    "arguments": "{\"cmd\":\"cargo test\"}",
                    "call_id": "call-1"
                ]
            ]
        ], to: bundle.appendingPathComponent("payloads/response-1.json", isDirectory: false))
        try writeJSONObject([
            "type": "response.create",
            "previous_response_id": "resp-1",
            "input": [
                [
                    "type": "function_call_output",
                    "call_id": "call-1",
                    "output": "ok\n"
                ]
            ]
        ], to: bundle.appendingPathComponent("payloads/request-2.json", isDirectory: false))

        _ = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .traceReduce(traceBundle: bundle.path, output: nil)),
            dependencies: testDependencies(codexHome: temp.url)
        )

        let state = try loadJSONObject(at: bundle.appendingPathComponent("state.json", isDirectory: false))
        let toolCalls = try XCTUnwrap(state["tool_calls"] as? [String: Any])
        let toolCall = try XCTUnwrap(toolCalls["tool-1"] as? [String: Any])
        XCTAssertEqual(toolCall["terminal_operation_id"] as? String, "terminal_operation:1")
        XCTAssertEqual(
            toolCall["raw_runtime_payload_ids"] as? [String],
            ["payload-terminal-start", "payload-terminal-end"]
        )
        let summary = try XCTUnwrap(toolCall["summary"] as? [String: Any])
        XCTAssertEqual(summary["type"] as? String, "terminal")
        XCTAssertEqual(summary["operation_id"] as? String, "terminal_operation:1")

        let operations = try XCTUnwrap(state["terminal_operations"] as? [String: Any])
        let operation = try XCTUnwrap(operations["terminal_operation:1"] as? [String: Any])
        XCTAssertEqual(operation["operation_id"] as? String, "terminal_operation:1")
        XCTAssertEqual(operation["terminal_id"] as? String, "pty-1")
        XCTAssertEqual(operation["tool_call_id"] as? String, "tool-1")
        XCTAssertEqual(operation["kind"] as? String, "exec_command")
        XCTAssertEqual(operation["raw_payload_ids"] as? [String], ["payload-terminal-start", "payload-terminal-end"])
        let observations = try XCTUnwrap(operation["model_observations"] as? [[String: Any]])
        XCTAssertEqual(observations.count, 1)
        XCTAssertEqual(observations[0]["source"] as? String, "direct_tool_call")
        XCTAssertEqual(observations[0]["call_item_ids"] as? [String], ["conversation_item:1"])
        XCTAssertEqual(observations[0]["output_item_ids"] as? [String], ["conversation_item:2"])

        let execution = try XCTUnwrap(operation["execution"] as? [String: Any])
        XCTAssertEqual(execution["started_seq"] as? Int, 4)
        XCTAssertEqual(execution["ended_seq"] as? Int, 5)
        XCTAssertEqual(execution["status"] as? String, "completed")

        let request = try XCTUnwrap(operation["request"] as? [String: Any])
        XCTAssertEqual(request["type"] as? String, "exec_command")
        XCTAssertEqual(request["command"] as? [String], ["cargo", "test"])
        XCTAssertEqual(request["display_command"] as? String, "cargo test")
        XCTAssertEqual(request["cwd"] as? String, "/repo")
        XCTAssertNil(request["yield_time_ms"] as? Int)
        XCTAssertNil(request["max_output_tokens"] as? Int)

        let terminalResult = try XCTUnwrap(operation["result"] as? [String: Any])
        XCTAssertEqual(terminalResult["exit_code"] as? Int, 0)
        XCTAssertEqual(terminalResult["stdout"] as? String, "ok\n")
        XCTAssertEqual(terminalResult["stderr"] as? String, "")
        XCTAssertEqual(terminalResult["formatted_output"] as? String, "ok\n")
        XCTAssertNil(terminalResult["original_token_count"] as? Int)
        XCTAssertNil(terminalResult["chunk_id"] as? String)

        let sessions = try XCTUnwrap(state["terminal_sessions"] as? [String: Any])
        let session = try XCTUnwrap(sessions["pty-1"] as? [String: Any])
        XCTAssertEqual(session["terminal_id"] as? String, "pty-1")
        XCTAssertEqual(session["thread_id"] as? String, "thread-root")
        XCTAssertEqual(session["created_by_operation_id"] as? String, "terminal_operation:1")
        XCTAssertEqual(session["operation_ids"] as? [String], ["terminal_operation:1"])
        let sessionExecution = try XCTUnwrap(session["execution"] as? [String: Any])
        XCTAssertEqual(sessionExecution["started_seq"] as? Int, 4)
        XCTAssertNil(sessionExecution["ended_seq"] as? Int)
        XCTAssertEqual(sessionExecution["status"] as? String, "running")
    }

    func testTraceReduceReusesTerminalSessionForWriteStdinRuntimeOperation() async throws {
        let temp = try TemporaryDirectory()
        let bundle = temp.url.appendingPathComponent("trace-bundle", isDirectory: true)
        let execStartPayload: [String: Any] = [
            "raw_payload_id": "payload-exec-start",
            "kind": ["type": "tool_runtime_event"],
            "path": "payloads/exec-start.json"
        ]
        let stdinStartPayload: [String: Any] = [
            "raw_payload_id": "payload-stdin-start",
            "kind": ["type": "tool_runtime_event"],
            "path": "payloads/stdin-start.json"
        ]
        let stdinEndPayload: [String: Any] = [
            "raw_payload_id": "payload-stdin-end",
            "kind": ["type": "tool_runtime_event"],
            "path": "payloads/stdin-end.json"
        ]

        try writeTraceBundle(at: bundle, events: [
            traceEvent(seq: 1, wallTime: 101, payload: [
                "type": "thread_started",
                "thread_id": "thread-root",
                "agent_path": "/root"
            ]),
            traceEvent(seq: 2, wallTime: 102, threadID: "thread-root", payload: [
                "type": "codex_turn_started",
                "codex_turn_id": "turn-1",
                "thread_id": "thread-root"
            ]),
            traceEvent(seq: 3, wallTime: 103, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "tool_call_started",
                "tool_call_id": "tool-start",
                "model_visible_call_id": NSNull(),
                "code_mode_runtime_tool_id": NSNull(),
                "requester": ["type": "model"],
                "kind": ["type": "exec_command"],
                "summary": ["type": "generic", "label": "exec_command", "input_preview": NSNull(), "output_preview": NSNull()],
                "invocation_payload": NSNull()
            ]),
            traceEvent(seq: 4, wallTime: 104, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "tool_call_runtime_started",
                "tool_call_id": "tool-start",
                "runtime_payload": execStartPayload
            ]),
            traceEvent(seq: 5, wallTime: 105, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "tool_call_started",
                "tool_call_id": "tool-stdin",
                "model_visible_call_id": NSNull(),
                "code_mode_runtime_tool_id": NSNull(),
                "requester": ["type": "model"],
                "kind": ["type": "write_stdin"],
                "summary": ["type": "generic", "label": "write_stdin", "input_preview": NSNull(), "output_preview": NSNull()],
                "invocation_payload": NSNull()
            ]),
            traceEvent(seq: 6, wallTime: 106, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "tool_call_runtime_started",
                "tool_call_id": "tool-stdin",
                "runtime_payload": stdinStartPayload
            ]),
            traceEvent(seq: 7, wallTime: 107, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "tool_call_runtime_ended",
                "tool_call_id": "tool-stdin",
                "status": "completed",
                "runtime_payload": stdinEndPayload
            ])
        ])
        try writeJSONObject([
            "call_id": "tool-start",
            "process_id": "pty-1",
            "turn_id": "turn-1",
            "command": ["bash"],
            "cwd": "/repo"
        ], to: bundle.appendingPathComponent("payloads/exec-start.json", isDirectory: false))
        try writeJSONObject([
            "call_id": "tool-stdin",
            "process_id": "pty-1",
            "turn_id": "turn-1",
            "command": ["bash"],
            "cwd": "/repo",
            "interaction_input": "echo hi\n"
        ], to: bundle.appendingPathComponent("payloads/stdin-start.json", isDirectory: false))
        try writeJSONObject([
            "call_id": "tool-stdin",
            "process_id": "pty-1",
            "turn_id": "turn-1",
            "command": ["bash"],
            "cwd": "/repo",
            "stdout": "hi\n",
            "stderr": "",
            "exit_code": 0,
            "formatted_output": "hi\n",
            "status": "completed"
        ], to: bundle.appendingPathComponent("payloads/stdin-end.json", isDirectory: false))

        _ = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .traceReduce(traceBundle: bundle.path, output: nil)),
            dependencies: testDependencies(codexHome: temp.url)
        )

        let state = try loadJSONObject(at: bundle.appendingPathComponent("state.json", isDirectory: false))
        let sessions = try XCTUnwrap(state["terminal_sessions"] as? [String: Any])
        let session = try XCTUnwrap(sessions["pty-1"] as? [String: Any])
        XCTAssertEqual(session["operation_ids"] as? [String], ["terminal_operation:1", "terminal_operation:2"])

        let operations = try XCTUnwrap(state["terminal_operations"] as? [String: Any])
        let stdinOperation = try XCTUnwrap(operations["terminal_operation:2"] as? [String: Any])
        XCTAssertEqual(stdinOperation["kind"] as? String, "write_stdin")
        XCTAssertEqual(stdinOperation["terminal_id"] as? String, "pty-1")
        let request = try XCTUnwrap(stdinOperation["request"] as? [String: Any])
        XCTAssertEqual(request["type"] as? String, "write_stdin")
        XCTAssertEqual(request["stdin"] as? String, "echo hi\n")
        let result = try XCTUnwrap(stdinOperation["result"] as? [String: Any])
        XCTAssertEqual(result["stdout"] as? String, "hi\n")
    }

    func testTraceReduceRecordsDispatchOnlyWriteStdinTerminalOperation() async throws {
        let temp = try TemporaryDirectory()
        let bundle = temp.url.appendingPathComponent("trace-bundle", isDirectory: true)
        let invocationPayload: [String: Any] = [
            "raw_payload_id": "payload-stdin-invocation",
            "kind": ["type": "tool_invocation"],
            "path": "payloads/stdin-invocation.json"
        ]
        let resultPayload: [String: Any] = [
            "raw_payload_id": "payload-stdin-result",
            "kind": ["type": "tool_result"],
            "path": "payloads/stdin-result.json"
        ]

        try writeTraceBundle(at: bundle, events: [
            traceEvent(seq: 1, wallTime: 101, payload: [
                "type": "thread_started",
                "thread_id": "thread-root",
                "agent_path": "/root"
            ]),
            traceEvent(seq: 2, wallTime: 102, threadID: "thread-root", payload: [
                "type": "codex_turn_started",
                "codex_turn_id": "turn-1",
                "thread_id": "thread-root"
            ]),
            traceEvent(seq: 3, wallTime: 103, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "tool_call_started",
                "tool_call_id": "tool-stdin",
                "model_visible_call_id": "call-stdin",
                "code_mode_runtime_tool_id": NSNull(),
                "requester": ["type": "model"],
                "kind": ["type": "write_stdin"],
                "summary": ["type": "generic", "label": "write_stdin", "input_preview": NSNull(), "output_preview": NSNull()],
                "invocation_payload": invocationPayload
            ]),
            traceEvent(seq: 4, wallTime: 104, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "tool_call_ended",
                "tool_call_id": "tool-stdin",
                "status": "completed",
                "result_payload": resultPayload
            ])
        ])
        try writeJSONObject([
            "tool_name": "write_stdin",
            "tool_namespace": NSNull(),
            "payload": [
                "type": "function",
                "arguments": #"{"session_id":123,"chars":"echo hi\n","yield_time_ms":250,"max_output_tokens":2000}"#
            ]
        ], to: bundle.appendingPathComponent("payloads/stdin-invocation.json", isDirectory: false))
        try writeJSONObject([
            "type": "direct_response",
            "response_item": [
                "type": "function_call_output",
                "call_id": "call-stdin",
                "output": "hi\n"
            ]
        ], to: bundle.appendingPathComponent("payloads/stdin-result.json", isDirectory: false))

        _ = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .traceReduce(traceBundle: bundle.path, output: nil)),
            dependencies: testDependencies(codexHome: temp.url)
        )

        let state = try loadJSONObject(at: bundle.appendingPathComponent("state.json", isDirectory: false))
        let toolCalls = try XCTUnwrap(state["tool_calls"] as? [String: Any])
        let toolCall = try XCTUnwrap(toolCalls["tool-stdin"] as? [String: Any])
        XCTAssertEqual(toolCall["terminal_operation_id"] as? String, "terminal_operation:1")
        XCTAssertEqual(toolCall["raw_invocation_payload_id"] as? String, "payload-stdin-invocation")
        XCTAssertEqual(toolCall["raw_result_payload_id"] as? String, "payload-stdin-result")
        XCTAssertEqual(toolCall["raw_runtime_payload_ids"] as? [String], [])
        let summary = try XCTUnwrap(toolCall["summary"] as? [String: Any])
        XCTAssertEqual(summary["type"] as? String, "terminal")
        XCTAssertEqual(summary["operation_id"] as? String, "terminal_operation:1")

        let operations = try XCTUnwrap(state["terminal_operations"] as? [String: Any])
        let operation = try XCTUnwrap(operations["terminal_operation:1"] as? [String: Any])
        XCTAssertEqual(operation["terminal_id"] as? String, "123")
        XCTAssertEqual(operation["tool_call_id"] as? String, "tool-stdin")
        XCTAssertEqual(operation["kind"] as? String, "write_stdin")
        XCTAssertEqual(operation["raw_payload_ids"] as? [String], ["payload-stdin-invocation", "payload-stdin-result"])
        let execution = try XCTUnwrap(operation["execution"] as? [String: Any])
        XCTAssertEqual(execution["started_seq"] as? Int, 3)
        XCTAssertEqual(execution["ended_seq"] as? Int, 4)
        XCTAssertEqual(execution["status"] as? String, "completed")
        let request = try XCTUnwrap(operation["request"] as? [String: Any])
        XCTAssertEqual(request["type"] as? String, "write_stdin")
        XCTAssertEqual(request["stdin"] as? String, "echo hi\n")
        XCTAssertEqual(request["yield_time_ms"] as? Int, 250)
        XCTAssertEqual(request["max_output_tokens"] as? Int, 2000)
        let terminalResult = try XCTUnwrap(operation["result"] as? [String: Any])
        XCTAssertNil(terminalResult["exit_code"] as? Int)
        XCTAssertEqual(terminalResult["stdout"] as? String, "hi\n")
        XCTAssertEqual(terminalResult["stderr"] as? String, "")
        XCTAssertEqual(terminalResult["formatted_output"] as? String, "hi\n")

        let sessions = try XCTUnwrap(state["terminal_sessions"] as? [String: Any])
        let session = try XCTUnwrap(sessions["123"] as? [String: Any])
        XCTAssertEqual(session["created_by_operation_id"] as? String, "terminal_operation:1")
        XCTAssertEqual(session["operation_ids"] as? [String], ["terminal_operation:1"])
    }

    func testTraceReduceProjectsCodeModeWriteStdinResultFields() async throws {
        let temp = try TemporaryDirectory()
        let bundle = temp.url.appendingPathComponent("trace-bundle", isDirectory: true)
        let invocationPayload: [String: Any] = [
            "raw_payload_id": "payload-stdin-invocation",
            "kind": ["type": "tool_invocation"],
            "path": "payloads/stdin-invocation.json"
        ]
        let resultPayload: [String: Any] = [
            "raw_payload_id": "payload-stdin-result",
            "kind": ["type": "tool_result"],
            "path": "payloads/stdin-result.json"
        ]

        try writeTraceBundle(at: bundle, events: [
            traceEvent(seq: 1, wallTime: 101, payload: [
                "type": "thread_started",
                "thread_id": "thread-root",
                "agent_path": "/root"
            ]),
            traceEvent(seq: 2, wallTime: 102, threadID: "thread-root", payload: [
                "type": "codex_turn_started",
                "codex_turn_id": "turn-1",
                "thread_id": "thread-root"
            ]),
            traceEvent(seq: 3, wallTime: 103, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "tool_call_started",
                "tool_call_id": "tool-stdin",
                "model_visible_call_id": NSNull(),
                "code_mode_runtime_tool_id": "runtime-tool-1",
                "requester": ["type": "code_cell", "code_cell_id": "code_cell:call-code"],
                "kind": ["type": "write_stdin"],
                "summary": ["type": "generic", "label": "write_stdin", "input_preview": NSNull(), "output_preview": NSNull()],
                "invocation_payload": invocationPayload
            ]),
            traceEvent(seq: 4, wallTime: 104, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "tool_call_ended",
                "tool_call_id": "tool-stdin",
                "status": "completed",
                "result_payload": resultPayload
            ])
        ])
        try writeJSONObject([
            "tool_name": "write_stdin",
            "tool_namespace": NSNull(),
            "payload": [
                "type": "function",
                "arguments": #"{"session_id":456,"chars":"","yield_time_ms":1000,"max_output_tokens":4000}"#
            ]
        ], to: bundle.appendingPathComponent("payloads/stdin-invocation.json", isDirectory: false))
        try writeJSONObject([
            "type": "code_mode_response",
            "value": [
                "chunk_id": "abc123",
                "wall_time_seconds": 1.25,
                "exit_code": 0,
                "original_token_count": 3,
                "output": "done\n"
            ]
        ], to: bundle.appendingPathComponent("payloads/stdin-result.json", isDirectory: false))

        _ = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .traceReduce(traceBundle: bundle.path, output: nil)),
            dependencies: testDependencies(codexHome: temp.url)
        )

        let state = try loadJSONObject(at: bundle.appendingPathComponent("state.json", isDirectory: false))
        let operations = try XCTUnwrap(state["terminal_operations"] as? [String: Any])
        let operation = try XCTUnwrap(operations["terminal_operation:1"] as? [String: Any])
        let terminalResult = try XCTUnwrap(operation["result"] as? [String: Any])
        XCTAssertEqual(terminalResult["exit_code"] as? Int, 0)
        XCTAssertEqual(terminalResult["stdout"] as? String, "done\n")
        XCTAssertEqual(terminalResult["stderr"] as? String, "")
        XCTAssertEqual(terminalResult["formatted_output"] as? String, "done\n")
        XCTAssertEqual(terminalResult["original_token_count"] as? Int, 3)
        XCTAssertEqual(terminalResult["chunk_id"] as? String, "abc123")
    }

    func testTraceReduceDerivesToolCallThreadFromTurnContext() async throws {
        let temp = try TemporaryDirectory()
        let bundle = temp.url.appendingPathComponent("trace-bundle", isDirectory: true)
        try writeTraceBundle(at: bundle, events: [
            traceEvent(seq: 1, wallTime: 101, payload: [
                "type": "thread_started",
                "thread_id": "thread-root",
                "agent_path": "/root"
            ]),
            traceEvent(seq: 2, wallTime: 102, threadID: "thread-root", payload: [
                "type": "codex_turn_started",
                "codex_turn_id": "turn-1",
                "thread_id": "thread-root"
            ]),
            traceEvent(seq: 3, wallTime: 103, codexTurnID: "turn-1", payload: [
                "type": "tool_call_started",
                "tool_call_id": "tool-1",
                "model_visible_call_id": NSNull(),
                "code_mode_runtime_tool_id": NSNull(),
                "requester": ["type": "model"],
                "kind": ["type": "other", "name": "lookup"],
                "summary": [
                    "type": "generic",
                    "label": "lookup",
                    "input_preview": NSNull(),
                    "output_preview": NSNull()
                ],
                "invocation_payload": NSNull()
            ])
        ])

        _ = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .traceReduce(traceBundle: bundle.path, output: nil)),
            dependencies: testDependencies(codexHome: temp.url)
        )

        let state = try loadJSONObject(at: bundle.appendingPathComponent("state.json", isDirectory: false))
        let toolCalls = try XCTUnwrap(state["tool_calls"] as? [String: Any])
        let toolCall = try XCTUnwrap(toolCalls["tool-1"] as? [String: Any])
        XCTAssertEqual(toolCall["thread_id"] as? String, "thread-root")
        XCTAssertEqual(toolCall["started_by_codex_turn_id"] as? String, "turn-1")
    }

    func testTraceReduceRecordsCompactionRequestCompletion() async throws {
        let temp = try TemporaryDirectory()
        let bundle = temp.url.appendingPathComponent("trace-bundle", isDirectory: true)
        let requestPayload: [String: Any] = [
            "raw_payload_id": "payload-compaction-request",
            "kind": ["type": "compaction_request"],
            "path": "payloads/compaction-request.json"
        ]
        let responsePayload: [String: Any] = [
            "raw_payload_id": "payload-compaction-response",
            "kind": ["type": "compaction_response"],
            "path": "payloads/compaction-response.json"
        ]

        try writeTraceBundle(at: bundle, events: [
            traceEvent(seq: 1, wallTime: 101, payload: [
                "type": "thread_started",
                "thread_id": "thread-root",
                "agent_path": "/root"
            ]),
            traceEvent(seq: 2, wallTime: 102, threadID: "thread-root", payload: [
                "type": "codex_turn_started",
                "codex_turn_id": "turn-1",
                "thread_id": "thread-root"
            ]),
            traceEvent(seq: 3, wallTime: 103, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "compaction_request_started",
                "compaction_id": "compaction-1",
                "compaction_request_id": "compaction_request:1",
                "thread_id": "thread-root",
                "codex_turn_id": "turn-1",
                "model": "gpt-test",
                "provider_name": "openai",
                "request_payload": requestPayload
            ]),
            traceEvent(seq: 4, wallTime: 108, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "compaction_request_completed",
                "compaction_id": "compaction-1",
                "compaction_request_id": "compaction_request:1",
                "response_payload": responsePayload
            ])
        ])

        _ = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .traceReduce(traceBundle: bundle.path, output: nil)),
            dependencies: testDependencies(codexHome: temp.url)
        )

        let state = try loadJSONObject(at: bundle.appendingPathComponent("state.json", isDirectory: false))
        let requests = try XCTUnwrap(state["compaction_requests"] as? [String: Any])
        let request = try XCTUnwrap(requests["compaction_request:1"] as? [String: Any])
        XCTAssertEqual(request["compaction_id"] as? String, "compaction-1")
        XCTAssertEqual(request["thread_id"] as? String, "thread-root")
        XCTAssertEqual(request["codex_turn_id"] as? String, "turn-1")
        XCTAssertEqual(request["model"] as? String, "gpt-test")
        XCTAssertEqual(request["provider_name"] as? String, "openai")
        XCTAssertEqual(request["raw_request_payload_id"] as? String, "payload-compaction-request")
        XCTAssertEqual(request["raw_response_payload_id"] as? String, "payload-compaction-response")
        let execution = try XCTUnwrap(request["execution"] as? [String: Any])
        XCTAssertEqual(execution["started_seq"] as? Int, 3)
        XCTAssertEqual(execution["ended_seq"] as? Int, 4)
        XCTAssertEqual(execution["status"] as? String, "completed")

        let rawPayloads = try XCTUnwrap(state["raw_payloads"] as? [String: Any])
        XCTAssertNotNil(rawPayloads["payload-compaction-request"])
        XCTAssertNotNil(rawPayloads["payload-compaction-response"])
    }

    func testTraceReduceRecordsCompactionRequestFailureWithoutResponsePayload() async throws {
        let temp = try TemporaryDirectory()
        let bundle = temp.url.appendingPathComponent("trace-bundle", isDirectory: true)
        let requestPayload: [String: Any] = [
            "raw_payload_id": "payload-compaction-request",
            "kind": ["type": "compaction_request"],
            "path": "payloads/compaction-request.json"
        ]

        try writeTraceBundle(at: bundle, events: [
            traceEvent(seq: 1, wallTime: 101, payload: [
                "type": "thread_started",
                "thread_id": "thread-root",
                "agent_path": "/root"
            ]),
            traceEvent(seq: 2, wallTime: 102, threadID: "thread-root", payload: [
                "type": "codex_turn_started",
                "codex_turn_id": "turn-1",
                "thread_id": "thread-root"
            ]),
            traceEvent(seq: 3, wallTime: 103, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "compaction_request_started",
                "compaction_id": "compaction-1",
                "compaction_request_id": "compaction_request:1",
                "thread_id": "thread-root",
                "codex_turn_id": "turn-1",
                "model": "gpt-test",
                "provider_name": "openai",
                "request_payload": requestPayload
            ]),
            traceEvent(seq: 4, wallTime: 108, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "compaction_request_failed",
                "compaction_id": "compaction-1",
                "compaction_request_id": "compaction_request:1",
                "error": "compact endpoint failed"
            ])
        ])

        _ = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .traceReduce(traceBundle: bundle.path, output: nil)),
            dependencies: testDependencies(codexHome: temp.url)
        )

        let state = try loadJSONObject(at: bundle.appendingPathComponent("state.json", isDirectory: false))
        let requests = try XCTUnwrap(state["compaction_requests"] as? [String: Any])
        let request = try XCTUnwrap(requests["compaction_request:1"] as? [String: Any])
        XCTAssertEqual(request["raw_request_payload_id"] as? String, "payload-compaction-request")
        XCTAssertNil(request["raw_response_payload_id"] as? String)
        let execution = try XCTUnwrap(request["execution"] as? [String: Any])
        XCTAssertEqual(execution["ended_seq"] as? Int, 4)
        XCTAssertEqual(execution["status"] as? String, "failed")
    }

    func testTraceReduceRejectsCompactionRequestForMismatchedTurnThread() async throws {
        let temp = try TemporaryDirectory()
        let bundle = temp.url.appendingPathComponent("trace-bundle", isDirectory: true)
        try writeTraceBundle(at: bundle, events: [
            traceEvent(seq: 1, wallTime: 101, payload: [
                "type": "thread_started",
                "thread_id": "thread-root",
                "agent_path": "/root"
            ]),
            traceEvent(seq: 2, wallTime: 102, payload: [
                "type": "thread_started",
                "thread_id": "thread-child",
                "agent_path": "/root/child"
            ]),
            traceEvent(seq: 3, wallTime: 103, threadID: "thread-root", payload: [
                "type": "codex_turn_started",
                "codex_turn_id": "turn-1",
                "thread_id": "thread-root"
            ]),
            traceEvent(seq: 4, wallTime: 104, threadID: "thread-child", codexTurnID: "turn-1", payload: [
                "type": "compaction_request_started",
                "compaction_id": "compaction-1",
                "compaction_request_id": "compaction_request:1",
                "thread_id": "thread-child",
                "codex_turn_id": "turn-1",
                "model": "gpt-test",
                "provider_name": "openai",
                "request_payload": [
                    "raw_payload_id": "payload-compaction-request",
                    "kind": ["type": "compaction_request"],
                    "path": "payloads/compaction-request.json"
                ]
            ])
        ])

        do {
            _ = try await DebugCommandRuntime.run(
                CodexCLI.DebugCommandRequest(action: .traceReduce(traceBundle: bundle.path, output: nil)),
                dependencies: testDependencies(codexHome: temp.url)
            )
            XCTFail("expected mismatched compaction request turn thread to fail")
        } catch {
            XCTAssertEqual(
                String(describing: error),
                "compaction request compaction_request:1 used thread thread-child, but codex turn turn-1 belongs to thread-root"
            )
        }
    }

    func testTraceReduceRecordsCompactionInstallAndPostCompactionSnapshot() async throws {
        let temp = try TemporaryDirectory()
        let bundle = temp.url.appendingPathComponent("trace-bundle", isDirectory: true)
        let requestPayload: [String: Any] = [
            "raw_payload_id": "payload-request-1",
            "kind": ["type": "inference_request"],
            "path": "payloads/request-1.json"
        ]
        let compactionRequestPayload: [String: Any] = [
            "raw_payload_id": "payload-compaction-request",
            "kind": ["type": "compaction_request"],
            "path": "payloads/compaction-request.json"
        ]
        let checkpointPayload: [String: Any] = [
            "raw_payload_id": "payload-compaction-checkpoint",
            "kind": ["type": "compaction_checkpoint"],
            "path": "payloads/compaction-checkpoint.json"
        ]
        let postCompactionPayload: [String: Any] = [
            "raw_payload_id": "payload-request-2",
            "kind": ["type": "inference_request"],
            "path": "payloads/request-2.json"
        ]

        try writeTraceBundle(at: bundle, events: [
            traceEvent(seq: 1, wallTime: 101, payload: [
                "type": "thread_started",
                "thread_id": "thread-root",
                "agent_path": "/root"
            ]),
            traceEvent(seq: 2, wallTime: 102, threadID: "thread-root", payload: [
                "type": "codex_turn_started",
                "codex_turn_id": "turn-1",
                "thread_id": "thread-root"
            ]),
            traceEvent(seq: 3, wallTime: 103, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "inference_started",
                "inference_call_id": "inference-1",
                "thread_id": "thread-root",
                "codex_turn_id": "turn-1",
                "model": "gpt-test",
                "provider_name": "openai",
                "request_payload": requestPayload
            ]),
            traceEvent(seq: 4, wallTime: 104, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "compaction_request_started",
                "compaction_id": "compaction-1",
                "compaction_request_id": "compaction_request:1",
                "thread_id": "thread-root",
                "codex_turn_id": "turn-1",
                "model": "gpt-test",
                "provider_name": "openai",
                "request_payload": compactionRequestPayload
            ]),
            traceEvent(seq: 5, wallTime: 105, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "compaction_installed",
                "compaction_id": "compaction-1",
                "checkpoint_payload": checkpointPayload
            ]),
            traceEvent(seq: 6, wallTime: 106, threadID: "thread-root", payload: [
                "type": "codex_turn_started",
                "codex_turn_id": "turn-2",
                "thread_id": "thread-root"
            ]),
            traceEvent(seq: 7, wallTime: 107, threadID: "thread-root", codexTurnID: "turn-2", payload: [
                "type": "inference_started",
                "inference_call_id": "inference-2",
                "thread_id": "thread-root",
                "codex_turn_id": "turn-2",
                "model": "gpt-test",
                "provider_name": "openai",
                "request_payload": postCompactionPayload
            ])
        ])
        let developer: [String: Any] = ["type": "message", "role": "developer", "content": [["type": "input_text", "text": "follow repo rules"]]]
        let user: [String: Any] = ["type": "message", "role": "user", "content": [["type": "input_text", "text": "count files"]]]
        let summary: [String: Any] = ["type": "message", "role": "user", "content": [["type": "input_text", "text": "summary from compacted history"]]]
        let compactionSummary: [String: Any] = ["type": "compaction", "encrypted_content": "encrypted-summary"]
        try writeJSONObject(["input": [developer, user]], to: bundle.appendingPathComponent("payloads/request-1.json", isDirectory: false))
        try writeJSONObject(["input": []], to: bundle.appendingPathComponent("payloads/compaction-request.json", isDirectory: false))
        try writeJSONObject([
            "input_history": [developer, user],
            "replacement_history": [user, summary, compactionSummary]
        ], to: bundle.appendingPathComponent("payloads/compaction-checkpoint.json", isDirectory: false))
        try writeJSONObject(["input": [developer, user, summary, compactionSummary]], to: bundle.appendingPathComponent("payloads/request-2.json", isDirectory: false))

        _ = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .traceReduce(traceBundle: bundle.path, output: nil)),
            dependencies: testDependencies(codexHome: temp.url)
        )

        let state = try loadJSONObject(at: bundle.appendingPathComponent("state.json", isDirectory: false))
        let inferences = try XCTUnwrap(state["inference_calls"] as? [String: Any])
        let firstInference = try XCTUnwrap(inferences["inference-1"] as? [String: Any])
        let secondInference = try XCTUnwrap(inferences["inference-2"] as? [String: Any])
        let compactions = try XCTUnwrap(state["compactions"] as? [String: Any])
        let compaction = try XCTUnwrap(compactions["compaction-1"] as? [String: Any])

        XCTAssertEqual(compaction["thread_id"] as? String, "thread-root")
        XCTAssertEqual(compaction["codex_turn_id"] as? String, "turn-1")
        XCTAssertEqual(compaction["installed_at_unix_ms"] as? Int, 105)
        XCTAssertEqual(compaction["request_ids"] as? [String], ["compaction_request:1"])
        XCTAssertEqual(compaction["input_item_ids"] as? [String], firstInference["request_item_ids"] as? [String])
        XCTAssertEqual(compaction["replacement_item_ids"] as? [String], ["conversation_item:4", "conversation_item:5", "conversation_item:6"])
        XCTAssertEqual(secondInference["request_item_ids"] as? [String], ["conversation_item:7", "conversation_item:4", "conversation_item:5", "conversation_item:6"])

        let conversation = try XCTUnwrap(state["conversation_items"] as? [String: Any])
        let markerID = try XCTUnwrap(compaction["marker_item_id"] as? String)
        let marker = try XCTUnwrap(conversation[markerID] as? [String: Any])
        XCTAssertEqual(marker["kind"] as? String, "compaction_marker")
        XCTAssertEqual(((marker["body"] as? [String: Any])?["parts"] as? [Any])?.count, 0)
        XCTAssertEqual(marker["produced_by"] as? [[String: String]], [["type": "compaction", "compaction_id": "compaction-1"]])

        let replacementUser = try XCTUnwrap(conversation["conversation_item:4"] as? [String: Any])
        XCTAssertEqual(replacementUser["produced_by"] as? [[String: String]], [["type": "compaction", "compaction_id": "compaction-1"]])
        let summaryItem = try XCTUnwrap(conversation["conversation_item:6"] as? [String: Any])
        XCTAssertEqual(summaryItem["channel"] as? String, "summary")
        XCTAssertEqual(summaryItem["kind"] as? String, "message")
        let parts = try XCTUnwrap((summaryItem["body"] as? [String: Any])?["parts"] as? [[String: String]])
        XCTAssertEqual(parts, [["type": "encoded", "label": "encrypted_content", "value": "encrypted-summary"]])
    }

    func testTraceReduceRecordsCodeCellLifecycleNestedToolsAndOutputs() async throws {
        let temp = try TemporaryDirectory()
        let bundle = temp.url.appendingPathComponent("trace-bundle", isDirectory: true)
        let requestPayload: [String: Any] = [
            "raw_payload_id": "payload-request-1",
            "kind": ["type": "inference_request"],
            "path": "payloads/request-1.json"
        ]
        let responsePayload: [String: Any] = [
            "raw_payload_id": "payload-response-1",
            "kind": ["type": "inference_response"],
            "path": "payloads/response-1.json"
        ]
        let followupPayload: [String: Any] = [
            "raw_payload_id": "payload-request-2",
            "kind": ["type": "inference_request"],
            "path": "payloads/request-2.json"
        ]
        let waitPayload: [String: Any] = [
            "raw_payload_id": "payload-wait-invocation",
            "kind": ["type": "tool_invocation"],
            "path": "payloads/wait-invocation.json"
        ]

        try writeTraceBundle(at: bundle, events: [
            traceEvent(seq: 1, wallTime: 101, payload: [
                "type": "thread_started",
                "thread_id": "thread-root",
                "agent_path": "/root"
            ]),
            traceEvent(seq: 2, wallTime: 102, threadID: "thread-root", payload: [
                "type": "codex_turn_started",
                "codex_turn_id": "turn-1",
                "thread_id": "thread-root"
            ]),
            traceEvent(seq: 3, wallTime: 103, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "inference_started",
                "inference_call_id": "inference-1",
                "thread_id": "thread-root",
                "codex_turn_id": "turn-1",
                "model": "gpt-test",
                "provider_name": "openai",
                "request_payload": requestPayload
            ]),
            traceEvent(seq: 4, wallTime: 104, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "code_cell_started",
                "runtime_cell_id": "1",
                "model_visible_call_id": "call-code",
                "source_js": "text('hi')"
            ]),
            traceEvent(seq: 5, wallTime: 105, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "inference_completed",
                "inference_call_id": "inference-1",
                "response_id": "resp-1",
                "response_payload": responsePayload
            ]),
            traceEvent(seq: 6, wallTime: 106, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "code_cell_initial_response",
                "runtime_cell_id": "1",
                "status": "yielded"
            ]),
            traceEvent(seq: 7, wallTime: 107, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "tool_call_started",
                "tool_call_id": "nested-tool-1",
                "model_visible_call_id": NSNull(),
                "code_mode_runtime_tool_id": "tool-1",
                "requester": ["type": "code_cell", "runtime_cell_id": "1"],
                "kind": ["type": "exec_command"],
                "summary": ["type": "generic", "label": "exec_command", "input_preview": "pwd", "output_preview": NSNull()]
            ]),
            traceEvent(seq: 8, wallTime: 108, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "tool_call_ended",
                "tool_call_id": "nested-tool-1",
                "status": "completed"
            ]),
            traceEvent(seq: 9, wallTime: 109, threadID: "thread-root", payload: [
                "type": "codex_turn_started",
                "codex_turn_id": "turn-2",
                "thread_id": "thread-root"
            ]),
            traceEvent(seq: 10, wallTime: 110, threadID: "thread-root", codexTurnID: "turn-2", payload: [
                "type": "inference_started",
                "inference_call_id": "inference-2",
                "thread_id": "thread-root",
                "codex_turn_id": "turn-2",
                "model": "gpt-test",
                "provider_name": "openai",
                "request_payload": followupPayload
            ]),
            traceEvent(seq: 11, wallTime: 111, threadID: "thread-root", codexTurnID: "turn-2", payload: [
                "type": "tool_call_started",
                "tool_call_id": "wait-tool-1",
                "model_visible_call_id": "wait-call",
                "code_mode_runtime_tool_id": NSNull(),
                "requester": ["type": "model"],
                "kind": ["type": "other", "name": "wait"],
                "summary": ["type": "generic", "label": "wait", "input_preview": #"{"cell_id":"1"}"#, "output_preview": NSNull()],
                "invocation_payload": waitPayload
            ]),
            traceEvent(seq: 12, wallTime: 112, threadID: "thread-root", codexTurnID: "turn-2", payload: [
                "type": "code_cell_ended",
                "runtime_cell_id": "1",
                "status": "completed"
            ])
        ])
        try writeJSONObject(["input": [["type": "message", "role": "user", "content": [["type": "input_text", "text": "count files"]]]]], to: bundle.appendingPathComponent("payloads/request-1.json", isDirectory: false))
        try writeJSONObject([
            "response_id": "resp-1",
            "output_items": [[
                "type": "custom_tool_call",
                "name": "exec",
                "call_id": "call-code",
                "input": "text('hi')"
            ]]
        ], to: bundle.appendingPathComponent("payloads/response-1.json", isDirectory: false))
        try writeJSONObject([
            "previous_response_id": "resp-1",
            "input": [[
                "type": "custom_tool_call_output",
                "call_id": "call-code",
                "output": "Script running with cell ID 1"
            ]]
        ], to: bundle.appendingPathComponent("payloads/request-2.json", isDirectory: false))
        try writeJSONObject([
            "tool_name": "wait",
            "tool_namespace": NSNull(),
            "payload": [
                "type": "function",
                "arguments": #"{"cell_id":"1"}"#
            ]
        ], to: bundle.appendingPathComponent("payloads/wait-invocation.json", isDirectory: false))

        _ = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .traceReduce(traceBundle: bundle.path, output: nil)),
            dependencies: testDependencies(codexHome: temp.url)
        )

        let state = try loadJSONObject(at: bundle.appendingPathComponent("state.json", isDirectory: false))
        let codeCells = try XCTUnwrap(state["code_cells"] as? [String: Any])
        let cell = try XCTUnwrap(codeCells["code_cell:call-code"] as? [String: Any])
        XCTAssertEqual(cell["thread_id"] as? String, "thread-root")
        XCTAssertEqual(cell["codex_turn_id"] as? String, "turn-1")
        XCTAssertEqual(cell["runtime_cell_id"] as? String, "1")
        XCTAssertEqual(cell["model_visible_call_id"] as? String, "call-code")
        XCTAssertEqual(cell["runtime_status"] as? String, "completed")
        XCTAssertEqual(cell["source_js"] as? String, "text('hi')")
        XCTAssertEqual(cell["source_item_id"] as? String, "conversation_item:2")
        XCTAssertEqual(cell["output_item_ids"] as? [String], ["conversation_item:3"])
        XCTAssertEqual(cell["nested_tool_call_ids"] as? [String], ["nested-tool-1"])
        XCTAssertEqual(cell["wait_tool_call_ids"] as? [String], ["wait-tool-1"])
        XCTAssertEqual(cell["initial_response_seq"] as? Int, 6)
        XCTAssertEqual(cell["yielded_seq"] as? Int, 6)
        let execution = try XCTUnwrap(cell["execution"] as? [String: Any])
        XCTAssertEqual(execution["started_seq"] as? Int, 4)
        XCTAssertEqual(execution["ended_seq"] as? Int, 12)
        XCTAssertEqual(execution["status"] as? String, "completed")

        let conversation = try XCTUnwrap(state["conversation_items"] as? [String: Any])
        let output = try XCTUnwrap(conversation["conversation_item:3"] as? [String: Any])
        let producers = try XCTUnwrap(output["produced_by"] as? [[String: String]])
        XCTAssertTrue(producers.contains(["type": "code_cell", "code_cell_id": "code_cell:call-code"]))

        let tools = try XCTUnwrap(state["tool_calls"] as? [String: Any])
        let nestedTool = try XCTUnwrap(tools["nested-tool-1"] as? [String: Any])
        XCTAssertEqual((nestedTool["requester"] as? [String: Any])?["code_cell_id"] as? String, "code_cell:call-code")
    }

    private func testDependencies(
        codexHome: URL,
        config: CodexRuntimeConfig = CodexRuntimeConfig(modelProvider: "test-provider", projectDocMaxBytes: 0),
        configLayerStack: ConfigLayerStack? = nil,
        configuredEnvironments: [TurnEnvironmentSelection]? = nil,
        currentDateAndTimezone: @escaping () -> (currentDate: String, timezone: String) = {
            ("2026-02-26", "America/Los_Angeles")
        }
    ) -> DebugCommandRuntime.Dependencies {
        DebugCommandRuntime.Dependencies(
            findCodexHome: { codexHome },
            loadConfig: { _, _ in
                config
            },
            loadConfigLayerStack: { _, _ in
                if let configLayerStack {
                    return configLayerStack
                }
                return try self.emptyConfigLayerStack(codexHome: codexHome)
            },
            loadConfiguredEnvironments: { _, cwd in
                configuredEnvironments ?? [TurnEnvironmentSelection(environmentID: "local", cwd: cwd)]
            },
            currentDateAndTimezone: currentDateAndTimezone
        )
    }

    private func emptyConfigLayerStack(codexHome: URL) throws -> ConfigLayerStack {
        try ConfigLayerStack(layers: [
            ConfigLayerEntry(
                name: .user(file: try AbsolutePath(absolutePath: codexHome.appendingPathComponent("config.toml").path)),
                config: .table([:])
            )
        ])
    }

    private func writeDebugSkill(name: String, description: String, to skill: URL) throws {
        try FileManager.default.createDirectory(
            at: skill.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        ---
        name: \(name)
        description: \(description)
        ---

        Use this when checking debug prompt JSON.
        """.write(to: skill, atomically: true, encoding: .utf8)
    }

    private func createMemoryTables(databaseURL: URL) throws {
        try withSQLiteDatabase(databaseURL: databaseURL) { database in
            try execute(
                """
                CREATE TABLE stage1_outputs (
                    thread_id TEXT PRIMARY KEY,
                    source_updated_at INTEGER NOT NULL,
                    raw_memory TEXT NOT NULL,
                    rollout_summary TEXT NOT NULL,
                    generated_at INTEGER NOT NULL
                )
                """,
                database: database
            )
            try execute(
                """
                CREATE TABLE jobs (
                    kind TEXT NOT NULL,
                    job_key TEXT NOT NULL,
                    status TEXT NOT NULL,
                    worker_id TEXT,
                    ownership_token TEXT,
                    started_at INTEGER,
                    finished_at INTEGER,
                    lease_until INTEGER,
                    retry_at INTEGER,
                    retry_remaining INTEGER NOT NULL,
                    last_error TEXT,
                    input_watermark INTEGER,
                    last_success_watermark INTEGER,
                    PRIMARY KEY (kind, job_key)
                )
                """,
                database: database
            )
        }
    }

    private func insertMemoryRows(databaseURL: URL) throws {
        try withSQLiteDatabase(databaseURL: databaseURL) { database in
            try execute(
                """
                INSERT INTO stage1_outputs (
                    thread_id,
                    source_updated_at,
                    raw_memory,
                    rollout_summary,
                    generated_at
                ) VALUES ('thread-1', 1, 'raw', 'summary', 1)
                """,
                database: database
            )
            try execute(
                """
                INSERT INTO jobs (
                    kind,
                    job_key,
                    status,
                    retry_remaining
                ) VALUES
                    ('memory_stage1', 'thread-1', 'completed', 3),
                    ('memory_consolidate_global', 'global', 'completed', 3),
                    ('not_memory', 'other', 'completed', 3)
                """,
                database: database
            )
        }
    }

    private func sqliteCount(databaseURL: URL, query: String) throws -> Int {
        try withSQLiteDatabase(databaseURL: databaseURL) { database in
            var statement: OpaquePointer?
            XCTAssertEqual(sqlite3_prepare_v2(database, query, -1, &statement, nil), SQLITE_OK)
            defer { sqlite3_finalize(statement) }
            XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
            return Int(sqlite3_column_int(statement, 0))
        }
    }

    private func withSQLiteDatabase<T>(
        databaseURL: URL,
        _ body: (OpaquePointer) throws -> T
    ) throws -> T {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        guard let database else {
            throw NSError(domain: "DebugCommandRuntimeTests", code: 1)
        }
        defer { sqlite3_close(database) }
        return try body(database)
    }

    private func execute(_ sql: String, database: OpaquePointer) throws {
        var error: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &error)
        defer { sqlite3_free(error) }
        if result != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "sqlite error \(result)"
            XCTFail(message)
            throw NSError(domain: "DebugCommandRuntimeTests", code: Int(result))
        }
    }

    private func writeTinyPNG(to path: URL) throws {
        let encoded = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
        let data = try XCTUnwrap(Data(base64Encoded: encoded))
        try data.write(to: path)
    }

    private func writeLifecycleTraceBundle(
        at bundle: URL,
        includeSpawnedThread: Bool = false
    ) throws {
        let sessionPayload: [String: Any] = [
            "raw_payload_id": "payload-session",
            "kind": ["type": "session_metadata"],
            "path": "payloads/session.json"
        ]
        var events: [[String: Any]] = [
            traceEvent(seq: 1, wallTime: 101, payload: [
                "type": "rollout_started",
                "trace_id": "trace-1",
                "root_thread_id": "thread-root"
            ]),
            traceEvent(seq: 2, wallTime: 102, payload: [
                "type": "thread_started",
                "thread_id": "thread-root",
                "agent_path": "/root-from-event",
                "metadata_payload": sessionPayload
            ]),
            traceEvent(seq: 3, wallTime: 103, threadID: "thread-root", payload: [
                "type": "codex_turn_started",
                "codex_turn_id": "turn-1",
                "thread_id": "thread-root"
            ]),
            traceEvent(seq: 4, wallTime: 105, threadID: "thread-root", payload: [
                "type": "codex_turn_ended",
                "codex_turn_id": "turn-1",
                "status": "completed"
            ])
        ]
        if includeSpawnedThread {
            let childPayload: [String: Any] = [
                "raw_payload_id": "payload-child-session",
                "kind": ["type": "session_metadata"],
                "path": "payloads/child-session.json"
            ]
            events.append(traceEvent(seq: 5, wallTime: 105, payload: [
                "type": "thread_started",
                "thread_id": "thread-child",
                "agent_path": "/event-child",
                "metadata_payload": childPayload
            ]))
        }
        events.append(contentsOf: [
            traceEvent(seq: includeSpawnedThread ? 6 : 5, wallTime: 105, payload: [
                "type": "thread_ended",
                "thread_id": "thread-root",
                "status": "completed"
            ]),
            traceEvent(seq: includeSpawnedThread ? 7 : 6, wallTime: 106, payload: [
                "type": "rollout_ended",
                "status": "completed"
            ])
        ])
        try writeTraceBundle(at: bundle, events: events)

        let payloads = bundle.appendingPathComponent("payloads", isDirectory: true)
        try writeJSONObject([
            "agent_path": "/root",
            "nickname": "Main",
            "model": "gpt-test",
            "session_source": ["exec": [:]]
        ], to: payloads.appendingPathComponent("session.json", isDirectory: false))
        if includeSpawnedThread {
            try writeJSONObject([
                "agent_path": "/root/repo_file_counter",
                "nickname": "Kepler",
                "agent_role": "worker",
                "session_source": [
                    "subagent": [
                        "thread_spawn": [
                            "parent_thread_id": "thread-root",
                            "agent_path": "/root/repo_file_counter",
                            "task_name": "repo_file_counter",
                            "agent_role": "worker"
                        ]
                    ]
                ]
            ], to: payloads.appendingPathComponent("child-session.json", isDirectory: false))
        }
    }

    private func writeTraceBundle(at bundle: URL, events: [[String: Any]]) throws {
        try FileManager.default.createDirectory(
            at: bundle.appendingPathComponent("payloads", isDirectory: true),
            withIntermediateDirectories: true
        )
        try writeJSONObject([
            "schema_version": 1,
            "trace_id": "trace-1",
            "rollout_id": "rollout-1",
            "root_thread_id": "thread-root",
            "started_at_unix_ms": 100,
            "raw_event_log": "trace.jsonl",
            "payloads_dir": "payloads"
        ], to: bundle.appendingPathComponent("manifest.json", isDirectory: false))
        let lines = try events.map { event -> String in
            let data = try JSONSerialization.data(withJSONObject: event, options: [.sortedKeys])
            return String(data: data, encoding: .utf8) ?? ""
        }
        try lines.joined(separator: "\n").write(
            to: bundle.appendingPathComponent("trace.jsonl", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
    }

    private func traceEvent(
        seq: Int,
        wallTime: Int,
        threadID: String? = nil,
        codexTurnID: String? = nil,
        payload: [String: Any]
    ) -> [String: Any] {
        [
            "schema_version": 1,
            "seq": seq,
            "wall_time_unix_ms": wallTime,
            "rollout_id": "rollout-1",
            "thread_id": threadID ?? NSNull(),
            "codex_turn_id": codexTurnID ?? NSNull(),
            "payload": payload
        ]
    }

    private func rawPayloadRef(_ rawPayloadID: String, kind: String) -> [String: Any] {
        [
            "raw_payload_id": rawPayloadID,
            "kind": ["type": kind],
            "path": "payloads/\(rawPayloadID).json"
        ]
    }

    private func interAgentMessage(author: String, recipient: String, content: String) throws -> [String: Any] {
        let message = [
            "author": author,
            "recipient": recipient,
            "content": content,
            "trigger_turn": true
        ] as [String: Any]
        let data = try JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        return [
            "type": "message",
            "role": "assistant",
            "content": [["type": "output_text", "text": text]]
        ]
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }

    private func loadJSONObject(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-swift-debug-runtime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
