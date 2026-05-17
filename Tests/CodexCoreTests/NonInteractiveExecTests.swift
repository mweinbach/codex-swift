import CodexCore
import Foundation
import XCTest

final class NonInteractiveExecTests: XCTestCase {
    func testUnifiedExecTimingMatchesRustClampRules() {
        XCTAssertEqual(UnifiedExecTiming.clampInitialYieldTimeMS(0), 250)
        XCTAssertEqual(UnifiedExecTiming.clampInitialYieldTimeMS(10_000), 10_000)
        XCTAssertEqual(UnifiedExecTiming.clampInitialYieldTimeMS(60_000), 30_000)

        XCTAssertEqual(
            UnifiedExecTiming.clampWriteStdinYieldTimeMS(0, inputIsEmpty: false, maxEmptyYieldTimeMS: 300_000),
            250
        )
        XCTAssertEqual(
            UnifiedExecTiming.clampWriteStdinYieldTimeMS(60_000, inputIsEmpty: false, maxEmptyYieldTimeMS: 300_000),
            30_000
        )
        XCTAssertEqual(
            UnifiedExecTiming.clampWriteStdinYieldTimeMS(250, inputIsEmpty: true, maxEmptyYieldTimeMS: 300_000),
            5_000
        )
        XCTAssertEqual(
            UnifiedExecTiming.clampWriteStdinYieldTimeMS(600_000, inputIsEmpty: true, maxEmptyYieldTimeMS: 12_000),
            12_000
        )
        XCTAssertEqual(
            UnifiedExecTiming.clampWriteStdinYieldTimeMS(600_000, inputIsEmpty: true, maxEmptyYieldTimeMS: 1),
            5_000
        )
    }

    func testMakePromptBuildsEnvironmentAndUserInput() {
        let schema = JSONValue.object(["type": .string("object")])
        let prompt = NonInteractiveExec.makePrompt(
            prompt: "ship it",
            imagePaths: ["/tmp/screenshot.png"],
            outputSchema: schema,
            cwd: URL(fileURLWithPath: "/tmp/project", isDirectory: true),
            approvalPolicy: .never,
            sandboxPolicy: .readOnly,
            shell: Shell(shellType: .zsh, shellPath: "/bin/zsh")
        )

        XCTAssertEqual(prompt.tools, [])
        XCTAssertEqual(prompt.outputSchema, schema)
        XCTAssertTrue(prompt.outputSchemaStrict)
        XCTAssertEqual(prompt.input.count, 3)

        guard case let .message(_, developerRole, developerContent, _) = prompt.input[0] else {
            return XCTFail("expected permissions developer message")
        }
        XCTAssertEqual(developerRole, "developer")
        XCTAssertTrue(developerContent.contains {
            guard case let .inputText(text) = $0 else {
                return false
            }
            return text.contains("<permissions instructions>")
                && text.contains("`sandbox_mode` is `read-only`")
        })

        guard case let .message(_, environmentRole, environmentContent, _) = prompt.input[1] else {
            return XCTFail("expected environment message")
        }
        XCTAssertEqual(environmentRole, "user")
        XCTAssertTrue(environmentContent.contains {
            guard case let .inputText(text) = $0 else {
                return false
            }
            return text.contains("<environment_context>")
                && text.contains("<cwd>/tmp/project</cwd>")
        })

        guard case let .message(_, role, content, _) = prompt.input[2] else {
            return XCTFail("expected user message")
        }
        XCTAssertEqual(role, "user")
        XCTAssertEqual(content.count, 2)
        guard case let .inputText(text) = content[1] else {
            return XCTFail("expected prompt text")
        }
        XCTAssertEqual(text, "ship it")
    }

    func testMakePromptBuildsPermissionsFromEffectiveProfileLikeRust() {
        let prompt = NonInteractiveExec.makePrompt(
            prompt: "ship it",
            imagePaths: [],
            outputSchema: nil,
            cwd: URL(fileURLWithPath: "/tmp/project", isDirectory: true),
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            permissionProfile: .readOnly(),
            shell: Shell(shellType: .zsh, shellPath: "/bin/zsh")
        )

        guard case let .message(_, "developer", developerContent, _) = prompt.input.first,
              case let .inputText(permissionsText) = developerContent.first
        else {
            return XCTFail("expected permissions developer message")
        }

        XCTAssertTrue(permissionsText.contains("`sandbox_mode` is `read-only`"))
        XCTAssertFalse(permissionsText.contains("`sandbox_mode` is `danger-full-access`"))
    }

    func testMakePromptExpandsConfiguredEnvironmentSnapshotDefaultFirstLikeRust() throws {
        let cwd = URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        let snapshot = ConfiguredEnvironmentSnapshot(
            environments: [
                ConfiguredEnvironmentEntry(id: "local", transport: .local),
                ConfiguredEnvironmentEntry(
                    id: "dev",
                    transport: .stdio(StdioConfiguredEnvironmentCommand(program: "ssh", args: ["dev"]))
                ),
                ConfiguredEnvironmentEntry(id: "qa", transport: .websocketURL("ws://127.0.0.1:4512"))
            ],
            defaultEnvironment: .environmentID("dev")
        )

        let prompt = NonInteractiveExec.makePrompt(
            prompt: "ship it",
            imagePaths: [],
            outputSchema: nil,
            cwd: cwd,
            approvalPolicy: .never,
            sandboxPolicy: .readOnly,
            shell: Shell(shellType: .zsh, shellPath: "/bin/zsh"),
            environmentContextEnvironments: snapshot.environmentContextEnvironments(
                cwd: cwd.path,
                shell: Shell(shellType: .zsh, shellPath: "/bin/zsh")
            )
        )

        guard case let .message(_, "user", content, _) = prompt.input[1],
              case let .inputText(environmentText) = content.first
        else {
            return XCTFail("expected contextual environment message")
        }
        let devRange = try XCTUnwrap(environmentText.range(of: #"<environment id="dev">"#))
        let localRange = try XCTUnwrap(environmentText.range(of: #"<environment id="local">"#))
        let qaRange = try XCTUnwrap(environmentText.range(of: #"<environment id="qa">"#))
        XCTAssertLessThan(devRange.lowerBound, localRange.lowerBound)
        XCTAssertLessThan(localRange.lowerBound, qaRange.lowerBound)
        XCTAssertTrue(environmentText.contains("<environments>"))
        XCTAssertFalse(environmentText.contains("\n  <cwd>/tmp/project</cwd>"))
        XCTAssertFalse(environmentText.contains("\n  <shell>zsh</shell>"))
    }

    func testMakePromptHonorsInitialContextInstructionGatesLikeRust() {
        let prompt = NonInteractiveExec.makePrompt(
            prompt: "ship it",
            imagePaths: [],
            outputSchema: nil,
            cwd: URL(fileURLWithPath: "/tmp/project", isDirectory: true),
            approvalPolicy: .never,
            sandboxPolicy: .readOnly,
            shell: Shell(shellType: .zsh, shellPath: "/bin/zsh"),
            includeEnvironmentContext: false,
            includePermissionsInstructions: false
        )

        XCTAssertEqual(prompt.input.count, 1)
        guard case let .message(_, role, content, _) = prompt.input[0] else {
            return XCTFail("expected user message")
        }
        XCTAssertEqual(role, "user")
        XCTAssertEqual(content, [.inputText(text: "ship it")])
    }

    func testMakePromptIncludesDeveloperAndUserInstructionsInInitialContext() {
        let prompt = NonInteractiveExec.makePrompt(
            prompt: "ship it",
            imagePaths: [],
            outputSchema: nil,
            cwd: URL(fileURLWithPath: "/tmp/project", isDirectory: true),
            approvalPolicy: .never,
            sandboxPolicy: .readOnly,
            shell: Shell(shellType: .zsh, shellPath: "/bin/zsh"),
            developerInstructions: "Follow developer notes.",
            userInstructions: UserInstructions(directory: "/tmp/project", text: "Project notes.")
        )

        XCTAssertEqual(prompt.input.count, 3)
        guard case let .message(_, developerRole, developerContent, _) = prompt.input[0] else {
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
        XCTAssertEqual(developerText, "Follow developer notes.")

        guard case let .message(_, userRole, userContent, _) = prompt.input[1] else {
            return XCTFail("expected contextual user message")
        }
        XCTAssertEqual(userRole, "user")
        XCTAssertEqual(userContent.count, 2)
        guard case let .inputText(userInstructionsText) = userContent[0],
              case let .inputText(environmentText) = userContent[1]
        else {
            return XCTFail("expected user instructions followed by environment context")
        }
        XCTAssertTrue(userInstructionsText.contains("Project notes."))
        XCTAssertTrue(environmentText.contains("<environment_context>"))
    }

    func testMakePromptAddsMultiAgentV2UsageHintAsStandaloneDeveloperMessageLikeRust() {
        let prompt = NonInteractiveExec.makePrompt(
            prompt: "ship it",
            imagePaths: [],
            outputSchema: nil,
            cwd: URL(fileURLWithPath: "/tmp/project", isDirectory: true),
            approvalPolicy: .never,
            sandboxPolicy: .readOnly,
            shell: Shell(shellType: .zsh, shellPath: "/bin/zsh"),
            developerInstructions: "Follow developer notes.",
            multiAgentV2UsageHintText: "Root guidance."
        )

        XCTAssertEqual(prompt.input.count, 4)
        guard case let .message(_, developerRole, developerContent, _) = prompt.input[0] else {
            return XCTFail("expected aggregated developer context message")
        }
        XCTAssertEqual(developerRole, "developer")
        XCTAssertEqual(developerContent.count, 2)
        guard case let .inputText(permissionsText) = developerContent[0],
              case let .inputText(developerText) = developerContent[1]
        else {
            return XCTFail("expected permissions followed by developer instructions")
        }
        XCTAssertTrue(permissionsText.contains("<permissions instructions>"))
        XCTAssertEqual(developerText, "Follow developer notes.")

        guard case let .message(_, hintRole, hintContent, _) = prompt.input[1] else {
            return XCTFail("expected standalone usage hint developer message")
        }
        XCTAssertEqual(hintRole, "developer")
        XCTAssertEqual(hintContent, [.inputText(text: "Root guidance.")])

        guard case let .message(_, environmentRole, environmentContent, _) = prompt.input[2] else {
            return XCTFail("expected contextual user message after usage hint")
        }
        XCTAssertEqual(environmentRole, "user")
        XCTAssertTrue(environmentContent.contains {
            guard case let .inputText(text) = $0 else {
                return false
            }
            return text.contains("<environment_context>")
        })
    }

    func testMemoryToolInstructionsRenderRustReadPathTemplate() throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let memories = temp.url.appendingPathComponent("memories", isDirectory: true)
        try FileManager.default.createDirectory(at: memories, withIntermediateDirectories: true)
        try "Short memory summary for tests.\n".write(
            to: memories.appendingPathComponent("memory_summary.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let instructions = try XCTUnwrap(MemoryToolInstructions.build(codexHome: temp.url))

        XCTAssertTrue(instructions.contains(
            "- \(memories.path)/memory_summary.md (already provided below; do NOT open again)"
        ))
        XCTAssertTrue(instructions.contains("Short memory summary for tests."))
        XCTAssertEqual(instructions.components(separatedBy: "========= MEMORY_SUMMARY BEGINS =========").count - 1, 1)
    }

    func testMemoryToolInstructionsRequireFeatureAndUseMemoriesConfig() throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let memories = temp.url.appendingPathComponent("memories", isDirectory: true)
        try FileManager.default.createDirectory(at: memories, withIntermediateDirectories: true)
        try "Configured memory summary.".write(
            to: memories.appendingPathComponent("memory_summary.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        var features = FeatureStates.withDefaults()
        features.set(.memoryTool, enabled: true)

        XCTAssertNil(MemoryToolInstructions.build(
            codexHome: temp.url,
            config: CodexRuntimeConfig(modelProvider: "test-provider")
        ))
        XCTAssertNil(MemoryToolInstructions.build(
            codexHome: temp.url,
            config: CodexRuntimeConfig(
                modelProvider: "test-provider",
                features: features,
                memories: MemoriesConfig(useMemories: false)
            )
        ))
        XCTAssertNotNil(MemoryToolInstructions.build(
            codexHome: temp.url,
            config: CodexRuntimeConfig(
                modelProvider: "test-provider",
                features: features
            )
        ))
    }

    func testMakePromptIncludesMemoryToolInstructionsBetweenDeveloperAndSkillsLikeRust() throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let memories = temp.url.appendingPathComponent("memories", isDirectory: true)
        try FileManager.default.createDirectory(at: memories, withIntermediateDirectories: true)
        try "Prompt memory summary.".write(
            to: memories.appendingPathComponent("memory_summary.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let memoryInstructions = try XCTUnwrap(MemoryToolInstructions.build(codexHome: temp.url))
        let availableSkills = try XCTUnwrap(Skills.buildAvailableSkills(
            outcome: SkillLoadOutcome(
                skills: [
                    SkillMetadata(
                        name: "linting",
                        description: "run swiftlint",
                        path: "/tmp/skills/linting/SKILL.md",
                        scope: .user
                    )
                ],
                skillRoots: ["/tmp/skills"],
                skillRootByPath: ["/tmp/skills/linting/SKILL.md": "/tmp/skills"]
            ),
            budget: .characters(120)
        ))
        let prompt = NonInteractiveExec.makePrompt(
            prompt: "ship it",
            imagePaths: [],
            outputSchema: nil,
            cwd: URL(fileURLWithPath: "/tmp/project", isDirectory: true),
            approvalPolicy: .never,
            sandboxPolicy: .readOnly,
            shell: Shell(shellType: .zsh, shellPath: "/bin/zsh"),
            developerInstructions: "Follow developer notes.",
            memoryToolDeveloperInstructions: memoryInstructions,
            availableSkills: availableSkills
        )

        guard case let .message(_, developerRole, developerContent, _) = prompt.input[0] else {
            return XCTFail("expected developer context message")
        }
        XCTAssertEqual(developerRole, "developer")
        XCTAssertEqual(developerContent.count, 4)
        guard case let .inputText(developerText) = developerContent[1],
              case let .inputText(memoryText) = developerContent[2],
              case let .inputText(skillsText) = developerContent[3]
        else {
            return XCTFail("expected developer, memory, and skills instructions")
        }
        XCTAssertEqual(developerText, "Follow developer notes.")
        XCTAssertTrue(memoryText.contains("========= MEMORY_SUMMARY BEGINS ========="))
        XCTAssertTrue(skillsText.contains("### Available skills"))
    }

    func testMakePromptKeepsSkillsAsLastDeveloperContextAfterGitAttributionRemovalLikeRust() throws {
        let availableSkills = try XCTUnwrap(Skills.buildAvailableSkills(
            outcome: SkillLoadOutcome(
                skills: [
                    SkillMetadata(
                        name: "commits",
                        description: "write commit messages",
                        path: "/tmp/skills/commits/SKILL.md",
                        scope: .user
                    )
                ],
                skillRoots: ["/tmp/skills"],
                skillRootByPath: ["/tmp/skills/commits/SKILL.md": "/tmp/skills"]
            ),
            budget: .characters(120)
        ))
        let prompt = NonInteractiveExec.makePrompt(
            prompt: "ship it",
            imagePaths: [],
            outputSchema: nil,
            cwd: URL(fileURLWithPath: "/tmp/project", isDirectory: true),
            approvalPolicy: .never,
            sandboxPolicy: .readOnly,
            shell: Shell(shellType: .zsh, shellPath: "/bin/zsh"),
            developerInstructions: "Follow developer notes.",
            availableSkills: availableSkills
        )

        guard case let .message(_, developerRole, developerContent, _) = prompt.input[0] else {
            return XCTFail("expected developer context message")
        }
        XCTAssertEqual(developerRole, "developer")
        XCTAssertEqual(developerContent.count, 3)
        guard case let .inputText(skillsText) = developerContent[2] else {
            return XCTFail("expected skills as final developer context")
        }
        XCTAssertTrue(skillsText.contains("### Available skills"))
        let developerText = developerContent.compactMap { item -> String? in
            guard case let .inputText(text) = item else { return nil }
            return text
        }.joined(separator: "\n")
        XCTAssertFalse(developerText.contains("Co-authored-by:"))
    }

    func testMakePromptIncludesAvailableSkillsAsDeveloperContextLikeRust() throws {
        let root = "/tmp/skills"
        let skill = SkillMetadata(
            name: "linting",
            description: "run swiftlint",
            path: "\(root)/linting/SKILL.md",
            scope: .user
        )
        let availableSkills = try XCTUnwrap(
            Skills.buildAvailableSkills(
                outcome: SkillLoadOutcome(
                    skills: [skill],
                    skillRoots: [root],
                    skillRootByPath: [skill.path: root]
                ),
                budget: .characters(120)
            ),
            "expected skills to render"
        )
        let prompt = NonInteractiveExec.makePrompt(
            prompt: "ship it",
            imagePaths: [],
            outputSchema: nil,
            cwd: URL(fileURLWithPath: "/tmp/project", isDirectory: true),
            approvalPolicy: .never,
            sandboxPolicy: .readOnly,
            shell: Shell(shellType: .zsh, shellPath: "/bin/zsh"),
            developerInstructions: "Follow developer notes.",
            availableSkills: availableSkills,
            userInstructions: UserInstructions(directory: "/tmp/project", text: "Project notes.")
        )

        XCTAssertEqual(prompt.input.count, 3)
        guard case let .message(_, developerRole, developerContent, _) = prompt.input[0] else {
            return XCTFail("expected developer context message")
        }
        XCTAssertEqual(developerRole, "developer")
        XCTAssertEqual(developerContent.count, 3)
        guard case let .inputText(permissionsText) = developerContent[0],
              case let .inputText(developerText) = developerContent[1],
              case let .inputText(skillsText) = developerContent[2]
        else {
            return XCTFail("expected permissions, developer instructions, and available skills")
        }
        XCTAssertTrue(permissionsText.contains("<permissions instructions>"))
        XCTAssertEqual(developerText, "Follow developer notes.")
        XCTAssertTrue(skillsText.contains("### Available skills"))
        XCTAssertTrue(skillsText.contains("- linting: run swiftlint (file: /tmp/skills/linting/SKILL.md)"))
        XCTAssertTrue(skillsText.contains("How to use skills"))

        guard case let .message(_, userRole, userContent, _) = prompt.input[1] else {
            return XCTFail("expected contextual user message")
        }
        XCTAssertEqual(userRole, "user")
        XCTAssertTrue(userContent.contains { item in
            guard case let .inputText(text) = item else {
                return false
            }
            return text.contains("Project notes.")
        })
    }

    func testMakePromptPlacesResumeHistoryBeforeNewUserInput() {
        let history: [ResponseItem] = [
            .message(role: "user", content: [.inputText(text: "previous request")]),
            .message(role: "assistant", content: [.outputText(text: "previous answer")])
        ]
        let prompt = NonInteractiveExec.makePrompt(
            prompt: "continue",
            imagePaths: [],
            outputSchema: nil,
            cwd: URL(fileURLWithPath: "/tmp/project", isDirectory: true),
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .zsh, shellPath: "/bin/zsh"),
            history: history
        )

        XCTAssertEqual(prompt.input.count, 5)
        XCTAssertEqual(Array(prompt.input[2...3]), history)
        guard case let .message(_, role, content, _) = prompt.input[4] else {
            return XCTFail("expected user message")
        }
        XCTAssertEqual(role, "user")
        XCTAssertEqual(content, [.inputText(text: "continue")])
    }

    func testMakePromptAcceptsToolsAndParallelToolCalls() {
        let shellTool = ToolSpecFactory.createShellCommandTool()
        let prompt = NonInteractiveExec.makePrompt(
            prompt: "ship it",
            imagePaths: [],
            outputSchema: nil,
            cwd: URL(fileURLWithPath: "/tmp/project", isDirectory: true),
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .zsh, shellPath: "/bin/zsh"),
            tools: [shellTool],
            parallelToolCalls: true
        )

        XCTAssertEqual(prompt.tools, [shellTool])
        XCTAssertTrue(prompt.parallelToolCalls)
    }

    func testToolSpecsFollowModelFamilyAndFeatureOverrides() {
        var features = FeatureStates.withDefaults()
        features.set(.unifiedExec, enabled: true)
        features.set(.webSearchRequest, enabled: true)
        let config = CodexRuntimeConfig(features: features)
        let modelFamily = ModelFamily(
            slug: "test-model",
            family: "test",
            supportsParallelToolCalls: true,
            applyPatchToolType: .freeform,
            experimentalSupportedTools: ["grep_files", "read_file", "list_dir", "test_sync_tool"],
            shellType: .shellCommand
        )

        let names = NonInteractiveExec.toolSpecs(modelFamily: modelFamily, config: config).map(\.spec.name)

        XCTAssertTrue(names.contains("exec_command"))
        XCTAssertTrue(names.contains("write_stdin"))
        XCTAssertTrue(names.contains("apply_patch"))
        XCTAssertTrue(names.contains("test_sync_tool"))
        XCTAssertTrue(names.contains("web_search"))
        XCTAssertFalse(names.contains("grep_files"))
        XCTAssertFalse(names.contains("read_file"))
        XCTAssertFalse(names.contains("list_dir"))
        XCTAssertFalse(names.contains("shell_command"))
        XCTAssertTrue(names.contains("view_image"))
    }

    func testToolsConfigRequiresUnifiedExecFeatureForModelProvidedUnifiedExecLikeRust() {
        var features = FeatureStates.withDefaults()
        features.set(.unifiedExec, enabled: false)
        let config = CodexRuntimeConfig(features: features)
        let modelFamily = ModelFamily(
            slug: "test-model",
            family: "test",
            shellType: .unifiedExec
        )

        let toolsConfig = NonInteractiveExec.toolsConfig(modelFamily: modelFamily, config: config)

        XCTAssertEqual(toolsConfig.shellType, .shellCommand)
    }

    func testToolsConfigShellZshForkPrefersShellCommandOverUnifiedExecLikeRust() {
        var features = FeatureStates.withDefaults()
        features.set(.unifiedExec, enabled: true)
        features.set(.shellZshFork, enabled: true)
        let config = CodexRuntimeConfig(features: features)
        let modelFamily = ModelFamily(
            slug: "test-model",
            family: "test",
            shellType: .unifiedExec
        )

        let toolsConfig = NonInteractiveExec.toolsConfig(modelFamily: modelFamily, config: config)

        XCTAssertEqual(toolsConfig.shellType, .shellCommand)
    }

    func testFallbackApplyPatchModelsDoNotUseRemovedFreeformToolByDefaultLikeRust() throws {
        let modelFamily = ModelFamily(
            slug: "fallback-model",
            family: "fallback",
            shellType: .disabled
        )

        let defaultConfig = CodexRuntimeConfig(features: .withDefaults())
        let defaultToolsConfig = NonInteractiveExec.toolsConfig(modelFamily: modelFamily, config: defaultConfig)
        XCTAssertNil(defaultToolsConfig.applyPatchToolType)

        let disabledFeatures = FeatureStates.withDefaults()
        let disabledToolsConfig = NonInteractiveExec.toolsConfig(
            modelFamily: modelFamily,
            config: CodexRuntimeConfig(features: disabledFeatures)
        )
        XCTAssertNil(disabledToolsConfig.applyPatchToolType)

        var removedFeatures = FeatureStates.withDefaults()
        removedFeatures.set(.applyPatchFreeform, enabled: true)
        let removedFeatureToolsConfig = NonInteractiveExec.toolsConfig(
            modelFamily: modelFamily,
            config: CodexRuntimeConfig(features: removedFeatures)
        )
        XCTAssertNil(removedFeatureToolsConfig.applyPatchToolType)

        let configuredModelFamily = ModelFamily(
            slug: "apply-patch-model",
            family: "apply-patch",
            applyPatchToolType: .freeform,
            shellType: .disabled
        )
        let modelToolsConfig = NonInteractiveExec.toolsConfig(
            modelFamily: configuredModelFamily,
            config: CodexRuntimeConfig(features: disabledFeatures)
        )
        XCTAssertEqual(modelToolsConfig.applyPatchToolType, .freeform)

        let specs = ToolSpecFactory.buildSpecs(config: modelToolsConfig).map(\.spec)
        let applyPatchSpec = try XCTUnwrap(specs.first { $0.name == "apply_patch" })
        guard case let .freeform(tool) = applyPatchSpec else {
            return XCTFail("expected apply_patch to use the freeform custom tool shape")
        }
        XCTAssertEqual(tool.name, "apply_patch")
        let chatToolNames = try ToolSpecFactory.createToolsJSONForChatCompletionsAPI(specs).compactMap { toolJSON in
            (toolJSON as? [String: Any])?["name"] as? String
        }
        XCTAssertFalse(chatToolNames.contains("apply_patch"))
    }

    func testToolSpecsExposeAgentJobToolsForFanoutWorkersLikeRust() {
        var features = FeatureStates.withDefaults()
        features.set(.spawnCsv, enabled: true)
        let config = CodexRuntimeConfig(features: features)
        let modelFamily = ModelFamily(
            slug: "test-model",
            family: "test",
            shellType: .disabled
        )

        let mainNames = NonInteractiveExec.toolSpecs(
            modelFamily: modelFamily,
            config: config,
            sessionSource: .cli
        ).map(\.spec.name)
        XCTAssertTrue(mainNames.contains("spawn_agents_on_csv"))
        XCTAssertFalse(mainNames.contains("report_agent_job_result"))

        let workerNames = NonInteractiveExec.toolSpecs(
            modelFamily: modelFamily,
            config: config,
            sessionSource: .subagent(.other("agent_job:test"))
        ).map(\.spec.name)
        XCTAssertTrue(workerNames.contains("spawn_agents_on_csv"))
        XCTAssertTrue(workerNames.contains("report_agent_job_result"))
    }

    func testToolSpecsForwardMultiAgentV2ConfigLikeRust() throws {
        var features = FeatureStates.withDefaults()
        features.set(.multiAgentV2, enabled: true)
        var config = CodexRuntimeConfig(features: features)
        config.multiAgentV2 = MultiAgentV2Config(
            maxConcurrentThreadsPerSession: 7,
            minWaitTimeoutMS: 60_000,
            maxWaitTimeoutMS: 120_000,
            defaultWaitTimeoutMS: 90_000,
            usageHintEnabled: true,
            usageHintText: "Runtime delegation hint.",
            hideSpawnAgentMetadata: true
        )
        let modelFamily = ModelFamily(
            slug: "test-model",
            family: "test",
            shellType: .disabled
        )

        let specs = NonInteractiveExec.toolSpecs(
            modelFamily: modelFamily,
            config: config,
            sessionSource: .cli
        )
        let names = specs.map(\.spec.name)
        XCTAssertTrue(names.contains("spawn_agent"))
        XCTAssertTrue(names.contains("send_message"))
        XCTAssertTrue(names.contains("followup_task"))
        XCTAssertTrue(names.contains("wait_agent"))
        XCTAssertTrue(names.contains("close_agent"))
        XCTAssertTrue(names.contains("list_agents"))
        XCTAssertFalse(names.contains("send_input"))
        XCTAssertFalse(names.contains("resume_agent"))

        let spawn = try functionTool(named: "spawn_agent", in: specs)
        XCTAssertTrue(spawn.description.contains("Runtime delegation hint."))
        XCTAssertTrue(spawn.description.contains("max_concurrent_threads_per_session = 7"))
        guard case let .object(spawnProperties, _, _) = spawn.parameters else {
            return XCTFail("expected spawn_agent object parameters")
        }
        XCTAssertNil(spawnProperties["agent_type"])
        XCTAssertNil(spawnProperties["model"])
        XCTAssertNil(spawnProperties["reasoning_effort"])
        XCTAssertNil(spawnProperties["service_tier"])

        let waitAgent = try functionTool(named: "wait_agent", in: specs)
        guard case let .object(waitProperties, _, _) = waitAgent.parameters else {
            return XCTFail("expected wait_agent object parameters")
        }
        XCTAssertEqual(
            waitProperties["timeout_ms"],
            .number(description: "Optional timeout in milliseconds. Defaults to 90000, min 60000, max 120000.")
        )
    }

    func testToolSpecsForwardAvailableModelsToMultiAgentV2DescriptionLikeRust() throws {
        var features = FeatureStates.withDefaults()
        features.set(.multiAgentV2, enabled: true)
        var config = CodexRuntimeConfig(features: features)
        config.multiAgentV2 = MultiAgentV2Config(usageHintEnabled: false)
        let modelFamily = ModelFamily(
            slug: "test-model",
            family: "test",
            shellType: .disabled
        )

        let specs = NonInteractiveExec.toolSpecs(
            modelFamily: modelFamily,
            config: config,
            sessionSource: .cli
        )

        let spawn = try functionTool(named: "spawn_agent", in: specs)
        XCTAssertTrue(spawn.description.contains(
            "Available model overrides (optional; inherited parent model is preferred):"
        ))
        XCTAssertTrue(spawn.description.contains("Reasoning efforts:"))
        XCTAssertFalse(spawn.description.contains("No picker-visible model overrides"))
    }

    func testResponsesOptionsCarriesServiceTier() {
        let options = NonInteractiveExec.responsesOptions(
            conversationID: ConversationId(),
            modelFamily: ModelFamily(slug: "gpt-test", family: "test"),
            reasoningEffort: nil,
            reasoningSummary: nil,
            verbosity: nil,
            serviceTier: "flex",
            outputSchema: nil
        )

        XCTAssertEqual(options.serviceTier, "flex")
    }

    func testResponsesOptionsCarriesModelSupportedServiceTiersLikeRust() {
        let modelFamily = ModelFamily(
            slug: "gpt-test",
            family: "test",
            serviceTiers: [
                ModelServiceTier(id: "flex", name: "flex", description: "Flexible processing.")
            ]
        )

        let options = NonInteractiveExec.responsesOptions(
            conversationID: ConversationId(),
            modelFamily: modelFamily,
            reasoningEffort: nil,
            reasoningSummary: nil,
            verbosity: nil,
            serviceTier: "priority",
            outputSchema: nil
        )

        XCTAssertEqual(options.serviceTier, "priority")
        XCTAssertEqual(options.supportedServiceTierIDs, ["flex"])
    }

    func testResponsesOptionsHonorsReasoningSummarySupportOverrideLikeRust() {
        let stillEnabledFamily = ModelFamily(
            slug: "still-enabled",
            family: "test",
            supportsReasoningSummaries: true,
            defaultReasoningSummary: .auto
        )
        .withConfigOverrides(ModelFamilyConfigOverrides(supportsReasoningSummaries: false))
        let stillEnabledOptions = NonInteractiveExec.responsesOptions(
            conversationID: ConversationId(),
            modelFamily: stillEnabledFamily,
            reasoningEffort: nil,
            reasoningSummary: nil,
            verbosity: nil,
            outputSchema: nil
        )
        XCTAssertEqual(stillEnabledOptions.reasoning?.summary, .auto)

        let enabledFamily = ModelFamily(
            slug: "forced-enabled",
            family: "test",
            supportsReasoningSummaries: false,
            defaultReasoningSummary: .auto
        )
        .withConfigOverrides(ModelFamilyConfigOverrides(supportsReasoningSummaries: true))
        let enabledOptions = NonInteractiveExec.responsesOptions(
            conversationID: ConversationId(),
            modelFamily: enabledFamily,
            reasoningEffort: nil,
            reasoningSummary: nil,
            verbosity: nil,
            outputSchema: nil
        )
        XCTAssertEqual(enabledOptions.reasoning?.summary, .auto)
    }

    func testResponsesOptionsCarriesModelInputModalities() {
        let options = NonInteractiveExec.responsesOptions(
            conversationID: ConversationId(),
            modelFamily: ModelFamily(slug: "text-only", family: "test", inputModalities: [.text]),
            reasoningEffort: nil,
            reasoningSummary: nil,
            verbosity: nil,
            outputSchema: nil
        )

        XCTAssertEqual(options.inputModalities, [.text])
    }

    func testResponsesOptionsCarriesRequestTraceClientMetadataLikeRust() {
        let options = NonInteractiveExec.responsesOptions(
            conversationID: ConversationId(),
            modelFamily: ModelFamily(slug: "gpt-test", family: "test"),
            reasoningEffort: nil,
            reasoningSummary: nil,
            verbosity: nil,
            outputSchema: nil,
            requestTrace: W3CTraceContext(
                traceparent: "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
                tracestate: "vendor=value"
            )
        )

        XCTAssertEqual(
            options.clientMetadata[ResponsesClientMetadata.wsRequestHeaderTraceparentKey],
            "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
        )
        XCTAssertEqual(
            options.clientMetadata[ResponsesClientMetadata.wsRequestHeaderTracestateKey],
            "vendor=value"
        )
    }

    func testUserPromptSubmitHooksAppendAdditionalContextToPrompt() async throws {
        let cwd = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-hook-context-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cwd) }

        var prompt = NonInteractiveExec.makePrompt(
            prompt: "ship it",
            imagePaths: [],
            outputSchema: nil,
            cwd: cwd,
            approvalPolicy: .never,
            sandboxPolicy: .readOnly,
            shell: Shell(shellType: .zsh, shellPath: "/bin/zsh")
        )
        let inputCountBeforeHook = prompt.input.count
        let outcome = await NonInteractiveExec.runUserPromptSubmitHooks(
            handlers: [
                ConfiguredHookHandler(
                    eventName: .userPromptSubmit,
                    matcher: nil,
                    command: "printf '%s' 'remember hook context'",
                    timeoutSec: 5,
                    sourcePath: try AbsolutePath(absolutePath: "/tmp/hooks.json"),
                    displayOrder: 0
                )
            ],
            prompt: &prompt,
            userPrompt: "ship it",
            conversationID: ConversationId(),
            turnID: "turn-1",
            cwd: cwd,
            model: "gpt-test",
            approvalPolicy: .never
        )

        XCTAssertEqual(outcome.additionalContexts, ["remember hook context"])
        XCTAssertEqual(prompt.input.count, inputCountBeforeHook + 1)
        guard case let .message(_, role, content, _) = prompt.input[inputCountBeforeHook] else {
            return XCTFail("expected hook context message")
        }
        XCTAssertEqual(role, "developer")
        XCTAssertEqual(content, [.inputText(text: "remember hook context")])
    }

    func testUserPromptSubmitHookSpillsLargeAdditionalContext() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let largeContext = String(repeating: "large hook context ", count: 3_000)
        let hookOutput = try JSONSerialization.data(withJSONObject: [
            "hookSpecificOutput": [
                "hookEventName": "UserPromptSubmit",
                "additionalContext": largeContext
            ]
        ])
        let hookOutputPath = temp.url.appendingPathComponent("hook-output.json", isDirectory: false)
        try String(decoding: hookOutput, as: UTF8.self).write(to: hookOutputPath, atomically: true, encoding: .utf8)

        var prompt = NonInteractiveExec.makePrompt(
            prompt: "ship it",
            imagePaths: [],
            outputSchema: nil,
            cwd: temp.url,
            approvalPolicy: .never,
            sandboxPolicy: .readOnly,
            shell: Shell(shellType: .zsh, shellPath: "/bin/zsh")
        )
        let outcome = await NonInteractiveExec.runUserPromptSubmitHooks(
            handlers: [
                ConfiguredHookHandler(
                    eventName: .userPromptSubmit,
                    matcher: nil,
                    command: "cat '\(hookOutputPath.path)'",
                    timeoutSec: 5,
                    sourcePath: try AbsolutePath(absolutePath: "/tmp/hooks.json"),
                    displayOrder: 0
                )
            ],
            prompt: &prompt,
            userPrompt: "ship it",
            conversationID: ConversationId(),
            turnID: "turn-1",
            cwd: temp.url,
            model: "gpt-test",
            approvalPolicy: .never
        )

        let spilledContext = try XCTUnwrap(outcome.additionalContexts.first)
        let marker = "Full hook output saved to: "
        XCTAssertTrue(spilledContext.contains(marker), spilledContext)
        XCTAssertNotEqual(spilledContext, largeContext)
        let savedPath = try XCTUnwrap(spilledContext.components(separatedBy: marker).last)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(try String(contentsOfFile: savedPath, encoding: .utf8), largeContext)

        guard case let .message(_, role, content, _) = prompt.input.last else {
            return XCTFail("expected spilled hook context message")
        }
        XCTAssertEqual(role, "developer")
        XCTAssertEqual(content, [.inputText(text: spilledContext)])
    }

    func testSessionStartHooksAppendAdditionalContextToPrompt() async throws {
        let cwd = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-session-hook-context-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cwd) }

        var prompt = NonInteractiveExec.makePrompt(
            prompt: "ship it",
            imagePaths: [],
            outputSchema: nil,
            cwd: cwd,
            approvalPolicy: .onRequest,
            sandboxPolicy: .readOnly,
            shell: Shell(shellType: .zsh, shellPath: "/bin/zsh")
        )
        let inputCountBeforeHook = prompt.input.count
        let outcome = await NonInteractiveExec.runSessionStartHooks(
            handlers: [
                ConfiguredHookHandler(
                    eventName: .sessionStart,
                    matcher: "resume",
                    command: "printf '%s' 'session hook context'",
                    timeoutSec: 5,
                    sourcePath: try AbsolutePath(absolutePath: "/tmp/hooks.json"),
                    displayOrder: 0
                )
            ],
            prompt: &prompt,
            conversationID: ConversationId(),
            cwd: cwd,
            model: "gpt-test",
            approvalPolicy: .onRequest,
            source: .resume
        )

        XCTAssertEqual(outcome.additionalContexts, ["session hook context"])
        XCTAssertEqual(prompt.input.count, inputCountBeforeHook + 1)
        guard case let .message(_, role, content, _) = prompt.input[inputCountBeforeHook] else {
            return XCTFail("expected hook context message")
        }
        XCTAssertEqual(role, "developer")
        XCTAssertEqual(content, [.inputText(text: "session hook context")])
    }

    func testResponsesLoopExecutesFunctionCallAndContinues() async throws {
        let initial = Prompt(input: [
            .message(role: "user", content: [.inputText(text: "run echo")])
        ])
        let script = ExecLoopScript()

        let events = await NonInteractiveExec.runResponsesLoop(
            initialPrompt: initial,
            streamPrompt: { prompt in
                .success(await script.next(prompt))
            },
            executeFunctionCall: { item in
                guard case let .functionCall(_, name, _, _, callID) = item else {
                    return .functionCallOutput(
                        callID: "bad",
                        output: FunctionCallOutputPayload(content: "bad", success: false)
                    )
                }
                return .functionCallOutput(
                    callID: callID,
                    output: FunctionCallOutputPayload(content: "\(name) ok", success: true)
                )
            }
        )

        let prompts = await script.prompts()
        XCTAssertEqual(prompts.count, 2)
        XCTAssertTrue(prompts[1].input.contains {
            if case let .functionCallOutput(callID, output) = $0 {
                return callID == "call-1" && output.content == "shell_command ok"
            }
            return false
        })

        let result = NonInteractiveExec.finish(
            responseEvents: events,
            outputMode: .human,
            conversationID: ConversationId(),
            lastMessageFile: nil
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdoutMessage, "done")
    }

    func testResponsesLoopExposesUnavailableMcpToolPlaceholderOnNextRequestLikeRust() async throws {
        var features = FeatureStates.withDefaults()
        features.set(.unavailableDummyTools, enabled: true)
        let initial = Prompt(input: [
            .message(role: "user", content: [.inputText(text: "retry prior MCP call")])
        ])
        let toolCall = ResponseItem.functionCall(
            name: "_create_event",
            namespace: "mcp__codex_apps__calendar",
            arguments: "{}",
            callID: "call-mcp"
        )
        let script = RegisteredToolLoopScript(
            toolCall: toolCall,
            finalMessage: .message(role: "assistant", content: [.outputText(text: "done")])
        )

        _ = await NonInteractiveExec.runResponsesLoopWithTranscript(
            initialPrompt: initial,
            features: features,
            streamPrompt: { prompt in
                .success(await script.next(prompt))
            },
            executeFunctionCall: { item in
                guard case let .functionCall(_, name, namespace, _, callID) = item else {
                    return .functionCallOutput(
                        callID: "bad",
                        output: FunctionCallOutputPayload(content: "bad", success: false)
                    )
                }
                return .functionCallOutput(
                    callID: callID,
                    output: FunctionCallOutputPayload(
                        content: ToolSpecFactory.unavailableToolMessage(
                            toolName: UnavailableToolName(namespace: namespace, name: name).flatName,
                            nextStep: "Retry after the tool becomes available or ask the user to re-enable it."
                        ),
                        success: false
                    )
                )
            }
        )

        let prompts = await script.prompts()
        XCTAssertEqual(prompts.count, 2)
        XCTAssertEqual(prompts[0].tools.map(\.name), [])
        XCTAssertEqual(prompts[1].tools.map(\.name), ["mcp__codex_apps__calendar_create_event"])
        guard case let .function(tool) = prompts[1].tools[0] else {
            return XCTFail("expected unavailable placeholder function tool")
        }
        XCTAssertTrue(tool.description.contains(
            "Tool `mcp__codex_apps__calendar_create_event` is not currently available."
        ))
        XCTAssertEqual(
            tool.parameters,
            .object(properties: [:], required: nil, additionalProperties: .boolean(false))
        )
    }

    func testResponsesLoopHandlesModelsETagEventsLikeRust() async throws {
        let initial = Prompt(input: [
            .message(role: "user", content: [.inputText(text: "run echo")])
        ])
        let capture = ModelsETagCapture()
        let script = ExecLoopScript(modelsETags: [#""models-etag-1""#, #""models-etag-2""#])

        let result = await NonInteractiveExec.runResponsesLoopWithTranscript(
            initialPrompt: initial,
            handleModelsETag: { etag in
                await capture.append(etag)
            },
            streamPrompt: { prompt in
                .success(await script.next(prompt))
            },
            executeFunctionCall: { item in
                guard case let .functionCall(_, _, _, _, callID) = item else {
                    return .functionCallOutput(
                        callID: "bad",
                        output: FunctionCallOutputPayload(content: "bad", success: false)
                    )
                }
                return .functionCallOutput(
                    callID: callID,
                    output: FunctionCallOutputPayload(content: "ok", success: true)
                )
            }
        )

        let capturedETags = await capture.values()
        XCTAssertEqual(capturedETags, [#""models-etag-1""#, #""models-etag-2""#])
        XCTAssertEqual(result.transcriptItems.last, .message(role: "assistant", content: [.outputText(text: "done")]))
    }

    func testResponsesLoopContinuesWhenCompletedEndTurnFalseWithoutToolCalls() async throws {
        let initial = Prompt(input: [
            .message(role: "user", content: [.inputText(text: "continue")])
        ])
        let script = EndTurnFalseLoopScript()

        let events = await NonInteractiveExec.runResponsesLoop(
            initialPrompt: initial,
            streamPrompt: { prompt in
                .success(await script.next(prompt))
            },
            executeFunctionCall: { _ in
                .functionCallOutput(
                    callID: "unused",
                    output: FunctionCallOutputPayload(content: "unused", success: false)
                )
            }
        )

        let prompts = await script.prompts()
        XCTAssertEqual(prompts.count, 2)
        XCTAssertTrue(prompts[1].input.contains {
            if case let .message(_, role, content, _) = $0 {
                return role == "assistant" && content == [.outputText(text: "still working")]
            }
            return false
        })

        let result = NonInteractiveExec.finish(
            responseEvents: events,
            outputMode: .human,
            conversationID: ConversationId(),
            lastMessageFile: nil
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdoutMessage, "done")
    }

    func testResponsesLoopWithTranscriptIncludesToolCallsOutputsAndFinalMessage() async throws {
        let initial = Prompt(input: [
            .message(role: "user", content: [.inputText(text: "run echo")])
        ])
        let script = ExecLoopScript()

        let result = await NonInteractiveExec.runResponsesLoopWithTranscript(
            initialPrompt: initial,
            streamPrompt: { prompt in
                .success(await script.next(prompt))
            },
            executeFunctionCall: { item in
                guard case let .functionCall(_, _, _, _, callID) = item else {
                    return .functionCallOutput(
                        callID: "bad",
                        output: FunctionCallOutputPayload(content: "bad", success: false)
                    )
                }
                return .functionCallOutput(
                    callID: callID,
                    output: FunctionCallOutputPayload(content: "ok", success: true)
                )
            }
        )

        XCTAssertEqual(result.transcriptItems, [
            .functionCall(name: "shell_command", arguments: #"{"command":"echo hi"}"#, callID: "call-1"),
            .functionCallOutput(callID: "call-1", output: FunctionCallOutputPayload(content: "ok", success: true)),
            .message(role: "assistant", content: [.outputText(text: "done")])
        ])
    }

    func testResponsesLoopDispatchesRegisteredHandlerAndContinuesWithNormalizedHistoryLikeRust() async throws {
        let orphanOutput = ResponseItem.functionCallOutput(
            callID: "orphan-call",
            output: FunctionCallOutputPayload(content: "drop me", success: false)
        )
        let userMessage = ResponseItem.message(
            role: "user",
            content: [.inputText(text: "call the registered echo tool")]
        )
        let toolCall = ResponseItem.functionCall(
            name: "registered_echo",
            arguments: #"{"value":7}"#,
            callID: "call-registered"
        )
        let toolOutput = ResponseItem.functionCallOutput(
            callID: "call-registered",
            output: FunctionCallOutputPayload(content: #"{"echoed":7}"#, success: true)
        )
        let finalMessage = ResponseItem.message(role: "assistant", content: [.outputText(text: "done")])
        let script = RegisteredToolLoopScript(toolCall: toolCall, finalMessage: finalMessage)
        let handler = RegisteredFunctionToolHandler(output: toolOutput)

        let result = await NonInteractiveExec.runResponsesLoopWithTranscript(
            initialPrompt: Prompt(input: [orphanOutput, userMessage]),
            streamPrompt: { prompt in
                .success(await script.next(prompt))
            },
            executeFunctionCall: { item in
                await handler.execute(item)
            }
        )

        let handledCalls = await handler.calls()
        XCTAssertEqual(handledCalls, [toolCall])
        XCTAssertEqual(result.transcriptItems, [toolCall, toolOutput, finalMessage])

        let prompts = await script.prompts()
        XCTAssertEqual(prompts.count, 2)
        XCTAssertEqual(prompts[0].input, [userMessage])
        XCTAssertEqual(prompts[1].input, [userMessage, toolCall, toolOutput])

        let id = try ConversationId(string: "018f7a2d-4c5b-7abc-8def-0123456789ab")
        let finished = NonInteractiveExec.finish(
            responseEvents: result.events,
            outputMode: .jsonLines,
            conversationID: id,
            lastMessageFile: nil
        )

        XCTAssertEqual(finished.exitCode, 0)
        let lines = try XCTUnwrap(finished.stdoutMessage?.split(separator: "\n").map(String.init))
        XCTAssertEqual(lines.count, 4)
        let objects = try lines.map(jsonObject)
        XCTAssertEqual(objects[0]["type"], .string("thread.started"))
        XCTAssertEqual(objects[1]["type"], .string("turn.started"))
        XCTAssertEqual(objects[2]["type"], .string("item.completed"))
        XCTAssertEqual(objects[3]["type"], .string("turn.completed"))
        guard case let .object(item)? = objects[2]["item"] else {
            return XCTFail("expected completed item")
        }
        XCTAssertEqual(item["type"], .string("agent_message"))
        XCTAssertEqual(item["text"], .string("done"))
    }

    func testGenericFunctionHookInputUsesExtensionToolJSONRulesLikeRust() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let objectLog = temp.url.appendingPathComponent("extension-object-hook.json")
        let emptyLog = temp.url.appendingPathComponent("extension-empty-hook.json")
        let stringLog = temp.url.appendingPathComponent("extension-string-hook.json")

        _ = try await Self.executeGenericFunctionForHookLog(
            name: "extension_echo",
            arguments: #"{"message":"hello"}"#,
            log: objectLog,
            temp: temp
        )
        var object = try hookInputObject(at: objectLog)
        XCTAssertEqual(object["tool_name"] as? String, "extension_echo")
        XCTAssertEqual((object["tool_input"] as? [String: Any])?["message"] as? String, "hello")

        _ = try await Self.executeGenericFunctionForHookLog(
            name: "extension_echo",
            arguments: " \n\t ",
            log: emptyLog,
            temp: temp
        )
        object = try hookInputObject(at: emptyLog)
        XCTAssertEqual(object["tool_name"] as? String, "extension_echo")
        XCTAssertEqual((object["tool_input"] as? [String: Any])?.isEmpty, true)

        _ = try await Self.executeGenericFunctionForHookLog(
            name: "extension_echo",
            arguments: "not json",
            log: stringLog,
            temp: temp
        )
        object = try hookInputObject(at: stringLog)
        XCTAssertEqual(object["tool_name"] as? String, "extension_echo")
        XCTAssertEqual(object["tool_input"] as? String, "not json")
    }

    func testResponsesLoopCarriesHookAdditionalContextAfterToolOutput() async throws {
        let initial = Prompt(input: [
            .message(role: "user", content: [.inputText(text: "run echo")])
        ])
        let script = ExecLoopScript()

        let result = await NonInteractiveExec.runResponsesLoopWithTranscript(
            initialPrompt: initial,
            streamPrompt: { prompt in
                .success(await script.next(prompt))
            },
            executeFunctionCall: { item -> NonInteractiveExec.FunctionCallExecutionResult in
                guard case let .functionCall(_, _, _, _, callID) = item else {
                    return NonInteractiveExec.FunctionCallExecutionResult(
                        output: .functionCallOutput(
                            callID: "bad",
                            output: FunctionCallOutputPayload(content: "bad", success: false)
                        )
                    )
                }
                return NonInteractiveExec.FunctionCallExecutionResult(
                    output: .functionCallOutput(
                        callID: callID,
                        output: FunctionCallOutputPayload(content: "ok", success: true)
                    ),
                    additionalContextItems: [
                        .message(role: "developer", content: [.inputText(text: "hook context")])
                    ]
                )
            }
        )

        let prompts = await script.prompts()
        XCTAssertEqual(prompts.count, 2)
        XCTAssertTrue(prompts[1].input.contains {
            if case let .message(_, role, content, _) = $0 {
                return role == "developer" && content == [.inputText(text: "hook context")]
            }
            return false
        })
        XCTAssertEqual(result.transcriptItems, [
            .functionCall(name: "shell_command", arguments: #"{"command":"echo hi"}"#, callID: "call-1"),
            .functionCallOutput(callID: "call-1", output: FunctionCallOutputPayload(content: "ok", success: true)),
            .message(role: "developer", content: [.inputText(text: "hook context")]),
            .message(role: "assistant", content: [.outputText(text: "done")])
        ])
    }

    func testPreToolUseHooksBlockShellCommandAndAppendAdditionalContext() async throws {
        let item = ResponseItem.functionCall(
            name: "shell_command",
            arguments: #"{"command":"printf should-not-run","login":false}"#,
            callID: "call-shell"
        )

        let result = await NonInteractiveExec.executeFunctionCallWithHooks(
            item,
            handlers: [
                ConfiguredHookHandler(
                    eventName: .preToolUse,
                    matcher: "Bash",
                    command: #"printf %s '{"decision":"block","reason":"policy","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"pre ctx"}}'"#,
                    timeoutSec: 5,
                    sourcePath: try AbsolutePath(absolutePath: "/tmp/hooks.json"),
                    displayOrder: 0
                )
            ],
            conversationID: ConversationId(),
            turnID: "turn-1",
            cwd: FileManager.default.temporaryDirectory,
            model: "gpt-test",
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000)
        )

        guard case let .functionCallOutput(callID, payload) = result.output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-shell")
        XCTAssertEqual(payload.success, false)
        XCTAssertEqual(
            payload.content,
            "Command blocked by PreToolUse hook: policy. Command: printf should-not-run"
        )
        XCTAssertEqual(result.additionalContextItems, [
            .message(role: "developer", content: [.inputText(text: "pre ctx")])
        ])
    }

    func testPreToolUseHooksSpillLargeAdditionalContextLikeRust() async throws {
        let item = ResponseItem.functionCall(
            name: "shell_command",
            arguments: #"{"command":"printf should-not-run","login":false}"#,
            callID: "call-shell"
        )
        let largeContext = String(repeating: "remember the pre tool context ", count: 800)

        let result = await NonInteractiveExec.executeFunctionCallWithHooks(
            item,
            handlers: [
                ConfiguredHookHandler(
                    eventName: .preToolUse,
                    matcher: "Bash",
                    command: "cat <<'JSON'\n"
                        + #"{"decision":"block","reason":"policy","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"#
                        + (try Self.jsonString(largeContext))
                        + #"}}"#
                        + "\nJSON",
                    timeoutSec: 5,
                    sourcePath: try AbsolutePath(absolutePath: "/tmp/hooks.json"),
                    displayOrder: 0
                )
            ],
            conversationID: ConversationId(),
            turnID: "turn-1",
            cwd: FileManager.default.temporaryDirectory,
            model: "gpt-test",
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000)
        )

        let itemMessage = try XCTUnwrap(result.additionalContextItems.first)
        guard case let .message(_, role, content, _) = itemMessage else {
            return XCTFail("expected developer message")
        }
        XCTAssertEqual(role, "developer")
        XCTAssertEqual(content.count, 1)
        guard case let .inputText(spilledContext) = content[0] else {
            return XCTFail("expected spilled context text")
        }

        let marker = "Full hook output saved to: "
        XCTAssertTrue(spilledContext.contains(marker), spilledContext)
        XCTAssertNotEqual(spilledContext, largeContext)
        let savedPath = try XCTUnwrap(spilledContext.components(separatedBy: marker).last)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(try String(contentsOfFile: savedPath, encoding: .utf8), largeContext)
    }

    func testPostToolUseHooksAppendAdditionalContextAndReplaceFeedback() async throws {
        let item = ResponseItem.functionCall(
            name: "shell_command",
            arguments: #"{"command":"printf tool-output","login":false}"#,
            callID: "call-shell"
        )

        let result = await NonInteractiveExec.executeFunctionCallWithHooks(
            item,
            handlers: [
                ConfiguredHookHandler(
                    eventName: .postToolUse,
                    matcher: "Bash",
                    command: #"printf %s '{"decision":"block","reason":"post feedback","hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"post ctx"}}'"#,
                    timeoutSec: 5,
                    sourcePath: try AbsolutePath(absolutePath: "/tmp/hooks.json"),
                    displayOrder: 0
                )
            ],
            conversationID: ConversationId(),
            turnID: "turn-1",
            cwd: FileManager.default.temporaryDirectory,
            model: "gpt-test",
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000)
        )

        guard case let .functionCallOutput(callID, payload) = result.output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-shell")
        XCTAssertEqual(payload.success, true)
        XCTAssertEqual(payload.content, "post feedback")
        XCTAssertEqual(result.additionalContextItems, [
            .message(role: "developer", content: [.inputText(text: "post ctx")])
        ])
    }

    func testPostToolUseHookReceivesRawShellOutputLikeRust() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let hookLog = temp.url.appendingPathComponent("post-hook.json")
        let item = ResponseItem.functionCall(
            name: "shell_command",
            arguments: #"{"command":"printf tool-output","login":false}"#,
            callID: "call-shell"
        )

        let result = await NonInteractiveExec.executeFunctionCallWithHooks(
            item,
            handlers: [
                ConfiguredHookHandler(
                    eventName: .postToolUse,
                    matcher: "Bash",
                    command: "cat > \(shellSingleQuote(hookLog.path)); printf '{}'",
                    timeoutSec: 5,
                    sourcePath: try AbsolutePath(absolutePath: "/tmp/hooks.json"),
                    displayOrder: 0
                )
            ],
            conversationID: ConversationId(),
            turnID: "turn-1",
            cwd: temp.url,
            model: "gpt-test",
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000)
        )

        guard case let .functionCallOutput(_, payload) = result.output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(payload.success, true)
        XCTAssertTrue(payload.content.contains("Exit code: 0"))

        let object = try hookInputObject(at: hookLog)
        XCTAssertEqual(object["tool_response"] as? String, "tool-output")
    }

    func testPostToolUseHookReceivesRawExecCommandOutputLikeRust() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let hookLog = temp.url.appendingPathComponent("post-hook.json")
        let item = ResponseItem.functionCall(
            name: "exec_command",
            arguments: #"{"cmd":"printf unified-output","yield_time_ms":1000}"#,
            callID: "call-exec"
        )

        let result = await NonInteractiveExec.executeFunctionCallWithHooks(
            item,
            handlers: [
                ConfiguredHookHandler(
                    eventName: .postToolUse,
                    matcher: "Bash",
                    command: "cat > \(shellSingleQuote(hookLog.path)); printf '{}'",
                    timeoutSec: 5,
                    sourcePath: try AbsolutePath(absolutePath: "/tmp/hooks.json"),
                    displayOrder: 0
                )
            ],
            conversationID: ConversationId(),
            turnID: "turn-1",
            cwd: temp.url,
            model: "gpt-test",
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000)
        )

        guard case let .functionCallOutput(_, payload) = result.output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(payload.success, true)
        XCTAssertTrue(payload.content.contains("Process exited with code 0"))

        let object = try hookInputObject(at: hookLog)
        XCTAssertEqual(object["tool_response"] as? String, "unified-output")
    }

    func testPostToolUseHookReceivesCompletedExecOutputThatLooksLikeRunningHeader() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let hookLog = temp.url.appendingPathComponent("post-hook.json")
        let item = ResponseItem.functionCall(
            name: "exec_command",
            arguments: #"{"cmd":"printf 'Process running with session ID 45\nfinished'","yield_time_ms":1000}"#,
            callID: "call-exec"
        )

        let result = await NonInteractiveExec.executeFunctionCallWithHooks(
            item,
            handlers: [
                ConfiguredHookHandler(
                    eventName: .postToolUse,
                    matcher: "Bash",
                    command: "cat > \(shellSingleQuote(hookLog.path)); printf '{}'",
                    timeoutSec: 5,
                    sourcePath: try AbsolutePath(absolutePath: "/tmp/hooks.json"),
                    displayOrder: 0
                )
            ],
            conversationID: ConversationId(),
            turnID: "turn-1",
            cwd: temp.url,
            model: "gpt-test",
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000)
        )

        guard case let .functionCallOutput(_, payload) = result.output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(payload.success, true)
        XCTAssertTrue(payload.content.contains("Process exited with code 0"))

        let object = try hookInputObject(at: hookLog)
        XCTAssertEqual(
            object["tool_response"] as? String,
            "Process running with session ID 45\nfinished"
        )
    }

    func testPermissionRequestHookDeniesEscalatedShellCommandBeforeExecution() async throws {
        let item = ResponseItem.functionCall(
            name: "shell_command",
            arguments: #"{"command":"printf should-not-run","login":false,"sandbox_permissions":"require_escalated","justification":"need broader access"}"#,
            callID: "call-shell"
        )

        let result = await NonInteractiveExec.executeFunctionCallWithHooks(
            item,
            handlers: [
                ConfiguredHookHandler(
                    eventName: .permissionRequest,
                    matcher: "Bash",
                    command: #"printf %s '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"denied by hook"}}}'"#,
                    timeoutSec: 5,
                    sourcePath: try AbsolutePath(absolutePath: "/tmp/hooks.json"),
                    displayOrder: 0
                )
            ],
            conversationID: ConversationId(),
            turnID: "turn-1",
            cwd: FileManager.default.temporaryDirectory,
            model: "gpt-test",
            approvalPolicy: .onRequest,
            sandboxPolicy: .readOnly,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000)
        )

        guard case let .functionCallOutput(callID, payload) = result.output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-shell")
        XCTAssertEqual(payload.success, false)
        XCTAssertEqual(payload.content, "denied by hook")
    }

    func testPermissionRequestHookAllowFallsThroughToEscalatedShellCommand() async throws {
        let item = ResponseItem.functionCall(
            name: "shell_command",
            arguments: #"{"command":"printf allowed","login":false,"sandbox_permissions":"require_escalated","justification":"need broader access"}"#,
            callID: "call-shell"
        )

        let result = await NonInteractiveExec.executeFunctionCallWithHooks(
            item,
            handlers: [
                ConfiguredHookHandler(
                    eventName: .permissionRequest,
                    matcher: "Bash",
                    command: #"printf %s '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'"#,
                    timeoutSec: 5,
                    sourcePath: try AbsolutePath(absolutePath: "/tmp/hooks.json"),
                    displayOrder: 0
                )
            ],
            conversationID: ConversationId(),
            turnID: "turn-1",
            cwd: FileManager.default.temporaryDirectory,
            model: "gpt-test",
            approvalPolicy: .onRequest,
            sandboxPolicy: .readOnly,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000)
        )

        guard case let .functionCallOutput(callID, payload) = result.output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-shell")
        XCTAssertEqual(payload.success, true)
        XCTAssertTrue(payload.content.contains("allowed"), payload.content)
    }

    func testStopHookContinuationAppendsPromptAndRerunsModel() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let marker = temp.url.appendingPathComponent("blocked-once")
        let log = temp.url.appendingPathComponent("stop-hook-inputs.jsonl")
        let continuation = "retry with tests"
        let command = """
        cat >> '\(log.path)'; printf '\\n' >> '\(log.path)'; if [ -f '\(marker.path)' ]; then :; else touch '\(marker.path)'; printf %s '{"decision":"block","reason":"\(continuation)"}'; fi
        """
        let script = StopHookLoopScript(messages: ["draft one", "final draft"])

        let result = await NonInteractiveExec.runResponsesLoopWithTranscript(
            initialPrompt: Prompt(input: [
                .message(role: "user", content: [.inputText(text: "start")])
            ]),
            streamPrompt: { prompt in
                .success(await script.next(prompt))
            },
            stopHookContext: NonInteractiveExec.StopHookContext(
                handlers: [
                    ConfiguredHookHandler(
                        eventName: .stop,
                        matcher: nil,
                        command: command,
                        timeoutSec: 5,
                        sourcePath: try AbsolutePath(absolutePath: "/tmp/hooks.json"),
                        displayOrder: 0
                    )
                ],
                conversationID: ConversationId(),
                turnID: "turn-1",
                cwd: temp.url,
                model: "gpt-test",
                approvalPolicy: .never
            ),
            executeFunctionCall: { _ in
                NonInteractiveExec.FunctionCallExecutionResult(
                    output: .functionCallOutput(
                        callID: "unused",
                        output: FunctionCallOutputPayload(content: "unused", success: true)
                    )
                )
            }
        )

        let prompts = await script.prompts()
        XCTAssertEqual(prompts.count, 2)
        let continuationFragment = try XCTUnwrap(prompts[1].input.compactMap { item -> HookPromptFragment? in
            if case let .message(_, role, content, _) = item {
                guard role == "user" else {
                    return nil
                }
                return HookPromptItem.parseMessage(id: nil, content: content)?.fragments.first
            }
            return nil
        }.first)
        XCTAssertEqual(continuationFragment.text, continuation)
        XCTAssertFalse(continuationFragment.hookRunID.isEmpty)
        XCTAssertEqual(result.transcriptItems.count, 3)
        XCTAssertEqual(result.transcriptItems[0], .message(role: "assistant", content: [.outputText(text: "draft one")]))
        guard case let .message(_, transcriptRole, transcriptContent, _) = result.transcriptItems[1] else {
            return XCTFail("expected hook prompt transcript item")
        }
        XCTAssertEqual(transcriptRole, "user")
        XCTAssertEqual(
            HookPromptItem.parseMessage(id: nil, content: transcriptContent)?.fragments.first,
            continuationFragment
        )
        XCTAssertEqual(result.transcriptItems[2], .message(role: "assistant", content: [.outputText(text: "final draft")]))

        let hookInputs = try String(contentsOf: log, encoding: .utf8)
        XCTAssertTrue(hookInputs.contains(#""stop_hook_active":false"#), hookInputs)
        XCTAssertTrue(hookInputs.contains(#""stop_hook_active":true"#), hookInputs)
        XCTAssertTrue(hookInputs.contains(#""last_assistant_message":"draft one""#), hookInputs)
        XCTAssertTrue(hookInputs.contains(#""last_assistant_message":"final draft""#), hookInputs)
    }

    func testResponsesLoopExecutesCustomToolCallAndContinues() async throws {
        let initial = Prompt(input: [
            .message(role: "user", content: [.inputText(text: "patch")])
        ])
        let script = CustomToolLoopScript()

        let result = await NonInteractiveExec.runResponsesLoopWithTranscript(
            initialPrompt: initial,
            streamPrompt: { prompt in
                .success(await script.next(prompt))
            },
            executeFunctionCall: { item in
                guard case let .customToolCall(_, _, callID, name, _) = item else {
                    return .customToolCallOutput(callID: "bad", output: "bad")
                }
                return .customToolCallOutput(callID: callID, output: "\(name) ok")
            }
        )

        let prompts = await script.prompts()
        XCTAssertEqual(prompts.count, 2)
        XCTAssertTrue(prompts[1].input.contains(.customToolCallOutput(callID: "custom-1", output: "apply_patch ok")))
        XCTAssertEqual(result.transcriptItems, [
            .customToolCall(callID: "custom-1", name: "apply_patch", input: "*** Begin Patch\n*** End Patch"),
            .customToolCallOutput(callID: "custom-1", output: "apply_patch ok"),
            .message(role: "assistant", content: [.outputText(text: "done")])
        ])
    }

    func testResponsesLoopCollectsApplyPatchStreamingEventsLikeRustTurn() async throws {
        let initial = Prompt(input: [
            .message(role: "user", content: [.inputText(text: "patch")])
        ])
        var features = FeatureStates.withDefaults()
        features.set(.applyPatchStreamingEvents, enabled: true)
        let script = StreamingApplyPatchToolLoopScript()

        let result = await NonInteractiveExec.runResponsesLoopWithTranscript(
            initialPrompt: initial,
            features: features,
            streamPrompt: { prompt in
                .success(await script.next(prompt))
            },
            executeFunctionCall: { item in
                guard case let .customToolCall(_, _, callID, name, _) = item else {
                    return .customToolCallOutput(callID: "bad", output: "bad")
                }
                return .customToolCallOutput(callID: callID, output: "\(name) ok")
            }
        )

        XCTAssertEqual(result.runtimeEvents, [
            .patchApplyUpdated(PatchApplyUpdatedEvent(
                callID: "custom-1",
                changes: ["hello.txt": .add(content: "")]
            )),
            .patchApplyUpdated(PatchApplyUpdatedEvent(
                callID: "custom-1",
                changes: ["hello.txt": .add(content: "hello\nworld\n")]
            ))
        ])
        XCTAssertEqual(result.transcriptItems, [
            .customToolCall(
                callID: "custom-1",
                name: "apply_patch",
                input: "*** Begin Patch\n*** Add File: hello.txt\n+hello\n+world\n*** End Patch"
            ),
            .customToolCallOutput(callID: "custom-1", output: "apply_patch ok"),
            .message(role: "assistant", content: [.outputText(text: "done")])
        ])
    }

    func testResponsesLoopDoesNotCollectApplyPatchStreamingEventsWhenFeatureDisabled() async throws {
        let initial = Prompt(input: [
            .message(role: "user", content: [.inputText(text: "patch")])
        ])
        let script = StreamingApplyPatchToolLoopScript()

        let result = await NonInteractiveExec.runResponsesLoopWithTranscript(
            initialPrompt: initial,
            streamPrompt: { prompt in
                .success(await script.next(prompt))
            },
            executeFunctionCall: { item in
                guard case let .customToolCall(_, _, callID, name, _) = item else {
                    return .customToolCallOutput(callID: "bad", output: "bad")
                }
                return .customToolCallOutput(callID: callID, output: "\(name) ok")
            }
        )

        XCTAssertEqual(result.runtimeEvents, [])
    }

    func testResponsesLoopDoesNotExecuteHostedImageGenerationCall() async throws {
        let initial = Prompt(input: [
            .message(role: "user", content: [.inputText(text: "generate an image")])
        ])
        let counter = ToolCallCounter()
        let imageItem = ResponseItem.imageGenerationCall(
            id: "ig-1",
            status: "completed",
            revisedPrompt: "A tiny blue square",
            result: "Zm9v"
        )

        let result = await NonInteractiveExec.runResponsesLoopWithTranscript(
            initialPrompt: initial,
            streamPrompt: { _ in
                .success([
                    .success(.outputItemDone(imageItem)),
                    .success(.completed(responseID: "resp-1", tokenUsage: nil))
                ])
            },
            executeFunctionCall: { item in
                await counter.increment()
                return .functionCallOutput(
                    callID: "bad",
                    output: FunctionCallOutputPayload(content: "\(item)", success: false)
                )
            }
        )

        let toolCallCount = await counter.value()
        XCTAssertEqual(toolCallCount, 0)
        XCTAssertEqual(result.transcriptItems, [imageItem])
    }

    func testResponsesLoopExecutesClientToolSearchCallAndContinues() async throws {
        let initial = Prompt(input: [
            .message(role: "user", content: [.inputText(text: "find calendar tools")])
        ])
        let script = ToolSearchLoopScript()
        let index = Self.makeToolSearchIndex()

        let result = await NonInteractiveExec.runResponsesLoopWithTranscript(
            initialPrompt: initial,
            streamPrompt: { prompt in
                .success(await script.next(prompt))
            },
            executeFunctionCall: { item in
                await NonInteractiveExec.executeFunctionCall(
                    item,
                    cwd: URL(fileURLWithPath: "/tmp", isDirectory: true),
                    approvalPolicy: .never,
                    sandboxPolicy: .dangerFullAccess,
                    shell: Shell(shellType: .zsh, shellPath: "/bin/zsh"),
                    truncationPolicy: .bytes(10_000),
                    toolSearchIndex: index
                )
            }
        )

        let prompts = await script.prompts()
        XCTAssertEqual(prompts.count, 2)
        XCTAssertTrue(prompts[1].input.contains { item in
            guard case let .toolSearchOutput(callID, status, execution, tools) = item else {
                return false
            }
            return callID == "search-1"
                && status == "completed"
                && execution == "client"
                && tools.count == 1
        })
        XCTAssertEqual(result.transcriptItems.last, .message(role: "assistant", content: [.outputText(text: "done")]))
    }

    func testResponsesLoopDoesNotExecuteServerToolSearchCall() async throws {
        let initial = Prompt(input: [
            .message(role: "user", content: [.inputText(text: "find tools")])
        ])
        let counter = ToolCallCounter()
        let searchItem = ResponseItem.toolSearchCall(
            callID: nil,
            execution: "server",
            arguments: .object(["query": .string("calendar")])
        )

        let result = await NonInteractiveExec.runResponsesLoopWithTranscript(
            initialPrompt: initial,
            streamPrompt: { _ in
                .success([
                    .success(.outputItemDone(searchItem)),
                    .success(.completed(responseID: "resp-1", tokenUsage: nil))
                ])
            },
            executeFunctionCall: { item in
                await counter.increment()
                return .functionCallOutput(
                    callID: "bad",
                    output: FunctionCallOutputPayload(content: "\(item)", success: false)
                )
            }
        )

        let toolCallCount = await counter.value()
        XCTAssertEqual(toolCallCount, 0)
        XCTAssertEqual(result.transcriptItems, [searchItem])
    }

    func testShellCommandFunctionCallRunsUserShellCommand() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let item = ResponseItem.functionCall(
            name: "shell_command",
            arguments: #"{"command":"printf hello","login":false}"#,
            callID: "call-shell"
        )

        let output = await NonInteractiveExec.executeFunctionCall(
            item,
            cwd: temp.url,
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: ["PATH": "/bin:/usr/bin", "HOME": temp.url.path]
        )

        guard case let .functionCallOutput(callID, payload) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-shell")
        XCTAssertEqual(payload.success, true)
        XCTAssertTrue(payload.content.contains("Exit code: 0"))
        XCTAssertTrue(payload.content.contains("Output:\nhello"))
    }

    func testShellCommandPromptRequirementRejectsWithoutApprovalLikeRust() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let item = ResponseItem.functionCall(
            name: "shell_command",
            arguments: #"{"command":"touch denied-by-policy.txt","login":false}"#,
            callID: "call-shell-policy"
        )

        let output = await NonInteractiveExec.executeFunctionCall(
            item,
            cwd: temp.url,
            approvalPolicy: .unlessTrusted,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: ["PATH": "/bin:/usr/bin", "HOME": temp.url.path]
        )

        guard case let .functionCallOutput(callID, payload) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-shell-policy")
        XCTAssertEqual(payload.success, false)
        XCTAssertEqual(payload.content, "command requires approval")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: temp.url.appendingPathComponent("denied-by-policy.txt").path
        ))
    }

    func testPermissionRequestHookAllowsPolicyPromptedShellCommandLikeRust() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let hookInputLog = temp.url.appendingPathComponent("permission-hook-input.json")
        let item = ResponseItem.functionCall(
            name: "shell_command",
            arguments: #"{"command":"touch allowed-by-hook.txt","login":false,"justification":"create marker"}"#,
            callID: "call-shell-policy-hook"
        )

        let result = await NonInteractiveExec.executeFunctionCallWithHooks(
            item,
            handlers: [
                ConfiguredHookHandler(
                    eventName: .permissionRequest,
                    matcher: "Bash",
                    command: #"cat > '\#(hookInputLog.path)'; printf %s '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'"#,
                    timeoutSec: 5,
                    sourcePath: try AbsolutePath(absolutePath: "/tmp/hooks.json"),
                    displayOrder: 0
                )
            ],
            conversationID: ConversationId(),
            turnID: "turn-1",
            cwd: temp.url,
            model: "gpt-test",
            approvalPolicy: .unlessTrusted,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: ["PATH": "/bin:/usr/bin", "HOME": temp.url.path]
        )

        guard case let .functionCallOutput(callID, payload) = result.output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-shell-policy-hook")
        XCTAssertEqual(payload.success, true)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: temp.url.appendingPathComponent("allowed-by-hook.txt").path
        ))

        let hookInput = try Data(contentsOf: hookInputLog)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: hookInput) as? [String: Any])
        let toolInput = try XCTUnwrap(object["tool_input"] as? [String: Any])
        XCTAssertEqual(toolInput["command"] as? String, "touch allowed-by-hook.txt")
        XCTAssertEqual(toolInput["description"] as? String, "create marker")
    }

    func testExecPolicyAllowPrefixBypassesReadOnlySandboxLikeRust() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        var policy = ExecPolicy()
        try policy.addPrefixRule(["touch"], decision: .allow)
        let item = ResponseItem.functionCall(
            name: "shell_command",
            arguments: #"{"command":"touch allow-prefix.txt","login":false}"#,
            callID: "call-shell-allow-prefix"
        )

        let output = await NonInteractiveExec.executeFunctionCall(
            item,
            cwd: temp.url,
            approvalPolicy: .onRequest,
            sandboxPolicy: .readOnly,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: ["PATH": "/bin:/usr/bin", "HOME": temp.url.path],
            execPolicyManager: ExecPolicyManager(policy: policy)
        )

        guard case let .functionCallOutput(callID, payload) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-shell-allow-prefix")
        XCTAssertEqual(payload.success, true)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: temp.url.appendingPathComponent("allow-prefix.txt").path
        ))
    }

    func testViewImageRoutesThroughSelectedEnvironmentLikeRust() async throws {
        let primary = try NonInteractiveExecTemporaryDirectory()
        let selected = try NonInteractiveExecTemporaryDirectory()
        try Self.writeTinyPNG(to: selected.url.appendingPathComponent("selected.png"))

        let output = await NonInteractiveExec.executeFunctionCall(
            .functionCall(
                name: "view_image",
                arguments: #"{"path":"selected.png","environment_id":"remote-dev"}"#,
                callID: "call-view"
            ),
            cwd: primary.url,
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: [:],
            turnEnvironmentSelections: [
                TurnEnvironmentSelection(environmentID: "local", cwd: primary.url.path),
                TurnEnvironmentSelection(environmentID: "remote-dev", cwd: selected.url.path)
            ]
        )

        guard case let .functionCallOutput(callID, payload) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-view")
        XCTAssertEqual(payload.success, true)
        XCTAssertEqual(payload.contentItems?.count, 1)
        guard case let .inputImage(imageURL, detail)? = payload.contentItems?.first else {
            return XCTFail("expected image output")
        }
        XCTAssertTrue(imageURL.starts(with: "data:image/png;base64,"))
        XCTAssertEqual(detail, defaultImageDetail)
    }

    func testViewImageReadsRemoteEnvironmentFilesystemLikeRust() async throws {
        let primary = try NonInteractiveExecTemporaryDirectory()
        let imageBytes = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="))
        let transport = NonInteractiveExecScriptedExecServerClientTransport { message in
            guard case let .request(request) = message else {
                return nil
            }
            switch request.method {
            case execServerFsGetMetadataMethod:
                XCTAssertEqual(request.params?["path"], .string("/workspace/remote.png"))
                return ExecServerRPC.response(
                    id: request.id,
                    result: try ExecServerRPC.jsonValue(from: ExecServerFsGetMetadataResponse(
                        isDirectory: false,
                        isFile: true,
                        isSymlink: false,
                        createdAtMs: 0,
                        modifiedAtMs: 0
                    ))
                )
            case execServerFsReadFileMethod:
                XCTAssertEqual(request.params?["path"], .string("/workspace/remote.png"))
                return ExecServerRPC.response(
                    id: request.id,
                    result: try ExecServerRPC.jsonValue(from: ExecServerFsReadFileResponse(
                        dataBase64: imageBytes.base64EncodedString()
                    ))
                )
            default:
                XCTFail("unexpected exec-server method \(request.method)")
                return nil
            }
        }
        let remoteFileSystem = ExecServerRemoteFileSystem(client: ExecServerClient(transport: transport))
        let snapshot = ConfiguredEnvironmentSnapshot(
            environments: [
                ConfiguredEnvironmentEntry(id: "local", transport: .local),
                ConfiguredEnvironmentEntry(id: "remote-dev", transport: .websocketURL("wss://example.com/exec"))
            ],
            defaultEnvironment: .environmentID("local")
        )

        let output = await NonInteractiveExec.executeFunctionCall(
            .functionCall(
                name: "view_image",
                arguments: #"{"path":"remote.png","environment_id":"remote-dev"}"#,
                callID: "call-remote-view"
            ),
            cwd: primary.url,
            approvalPolicy: .never,
            sandboxPolicy: .readOnly,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: [:],
            turnEnvironmentSelections: [
                TurnEnvironmentSelection(environmentID: "local", cwd: primary.url.path),
                TurnEnvironmentSelection(environmentID: "remote-dev", cwd: "/workspace")
            ],
            configuredEnvironmentSnapshot: snapshot,
            remoteEnvironmentFileSystems: ["remote-dev": remoteFileSystem]
        )

        guard case let .functionCallOutput(callID, payload) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-remote-view")
        XCTAssertEqual(payload.success, true)
        guard case let .inputImage(imageURL, detail)? = payload.contentItems?.first else {
            return XCTFail("expected image output")
        }
        XCTAssertTrue(imageURL.starts(with: "data:image/png;base64,"))
        XCTAssertEqual(detail, defaultImageDetail)
        let methods = await transport.snapshot().compactMap { message -> String? in
            guard case let .request(request) = message else {
                return nil
            }
            return request.method
        }
        XCTAssertEqual(methods, [execServerFsGetMetadataMethod, execServerFsReadFileMethod])
    }

    func testViewImageOriginalDetailPreservesSourceWhenAllowedLikeRust() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let imagePath = temp.url.appendingPathComponent("original.png")
        let original = try Self.writeTinyPNG(to: imagePath)

        let output = await NonInteractiveExec.executeFunctionCall(
            .functionCall(
                name: "view_image",
                arguments: #"{"path":"original.png","detail":"original"}"#,
                callID: "call-original"
            ),
            cwd: temp.url,
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: [:],
            canRequestOriginalImageDetail: true
        )

        guard case let .functionCallOutput(_, payload) = output,
              case let .inputImage(imageURL, detail)? = payload.contentItems?.first
        else {
            return XCTFail("expected image output")
        }
        XCTAssertEqual(detail, .original)
        let prefix = "data:image/png;base64,"
        XCTAssertTrue(imageURL.starts(with: prefix))
        XCTAssertEqual(Data(base64Encoded: String(imageURL.dropFirst(prefix.count))), original)
    }

    func testViewImageAcceptsExplicitHighDetailLikeRust() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        try Self.writeTinyPNG(to: temp.url.appendingPathComponent("image.png"))

        let output = await NonInteractiveExec.executeFunctionCall(
            .functionCall(
                name: "view_image",
                arguments: #"{"path":"image.png","detail":"high"}"#,
                callID: "call-high"
            ),
            cwd: temp.url,
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: [:],
            canRequestOriginalImageDetail: true
        )

        guard case let .functionCallOutput(_, payload) = output,
              case let .inputImage(_, detail)? = payload.contentItems?.first
        else {
            return XCTFail("expected image output")
        }
        XCTAssertEqual(detail, defaultImageDetail)
    }

    func testViewImageRejectsUnknownDetailLikeRust() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        try Self.writeTinyPNG(to: temp.url.appendingPathComponent("image.png"))

        let output = await NonInteractiveExec.executeFunctionCall(
            .functionCall(
                name: "view_image",
                arguments: #"{"path":"image.png","detail":"full"}"#,
                callID: "call-invalid-detail"
            ),
            cwd: temp.url,
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: [:]
        )

        guard case let .functionCallOutput(_, payload) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(payload.success, false)
        XCTAssertEqual(
            payload.content,
            "view_image.detail only supports `high` or `original`; omit `detail` for default high resized behavior, got `full`"
        )
    }

    func testShellCommandAppliesConfiguredShellEnvironmentPolicyLikeRust() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let command = try Self.jsonString(
            #"printf '%s|%s|%s' "${VISIBLE-unset}" "${SECRET_TOKEN-unset}" "${DROP_ME-unset}""#
        )
        let item = ResponseItem.functionCall(
            name: "shell_command",
            arguments: #"{"command":\#(command),"login":false}"#,
            callID: "call-shell-env-policy"
        )
        let policy = ShellEnvironmentPolicy(
            inherit: .none,
            set: [
                "VISIBLE": "yes",
                "SECRET_TOKEN": "hidden",
                "DROP_ME": "no"
            ],
            includeOnly: [.newCaseInsensitive("VISIBLE")]
        )

        let output = await NonInteractiveExec.executeFunctionCall(
            item,
            cwd: temp.url,
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: [
                "PATH": "/bin:/usr/bin",
                "VISIBLE": "inherited",
                "SECRET_TOKEN": "inherited",
                "DROP_ME": "inherited"
            ],
            shellEnvironmentPolicy: policy,
            explicitEnvOverrides: policy.set
        )

        guard case let .functionCallOutput(callID, payload) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-shell-env-policy")
        XCTAssertEqual(payload.success, true)
        XCTAssertTrue(payload.content.contains("Output:\nyes|unset|unset"), payload.content)
    }

    func testUnifiedExecAppliesConfiguredShellEnvironmentPolicyLikeRust() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let command = try Self.jsonString(
            #"printf '%s|%s|%s' "${VISIBLE-unset}" "${SECRET_TOKEN-unset}" "${DROP_ME-unset}""#
        )
        let item = ResponseItem.functionCall(
            name: "exec_command",
            arguments: #"{"cmd":\#(command),"login":false,"yield_time_ms":1000}"#,
            callID: "call-unified-env-policy"
        )
        let policy = ShellEnvironmentPolicy(
            inherit: .none,
            set: [
                "VISIBLE": "yes",
                "SECRET_TOKEN": "hidden",
                "DROP_ME": "no"
            ],
            includeOnly: [.newCaseInsensitive("VISIBLE")]
        )

        let output = await NonInteractiveExec.executeFunctionCall(
            item,
            cwd: temp.url,
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: [
                "PATH": "/bin:/usr/bin",
                "VISIBLE": "inherited",
                "SECRET_TOKEN": "inherited",
                "DROP_ME": "inherited"
            ],
            shellEnvironmentPolicy: policy,
            explicitEnvOverrides: policy.set
        )

        guard case let .functionCallOutput(callID, payload) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-unified-env-policy")
        XCTAssertEqual(payload.success, true)
        XCTAssertTrue(payload.content.contains("Output:\nyes|unset|unset"), payload.content)
    }

    func testShellCommandSnapshotRestoresExplicitEnvironmentOverrides() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let snapshotPath = temp.url.appendingPathComponent("snapshot.sh")
        try """
        # Snapshot file
        export CODEX_SWIFT_POLICY_SET=from-snapshot
        """.write(to: snapshotPath, atomically: true, encoding: .utf8)
        let snapshot = ShellSnapshot(path: snapshotPath, cwd: temp.url)
        let shell = Shell(shellType: .bash, shellPath: "/bin/bash", shellSnapshot: snapshot)
        let command = try Self.jsonString(#"printf '%s' "$CODEX_SWIFT_POLICY_SET""#)
        let item = ResponseItem.functionCall(
            name: "shell_command",
            arguments: #"{"command":\#(command),"login":true}"#,
            callID: "call-shell-snapshot-env"
        )

        let output = await NonInteractiveExec.executeFunctionCall(
            item,
            cwd: temp.url,
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: shell,
            truncationPolicy: .bytes(10_000),
            environment: [
                "PATH": "/bin:/usr/bin",
                "HOME": temp.url.path,
                "CODEX_SWIFT_POLICY_SET": "from-policy"
            ],
            explicitEnvOverrides: ["CODEX_SWIFT_POLICY_SET": "from-policy"]
        )

        guard case let .functionCallOutput(callID, payload) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-shell-snapshot-env")
        XCTAssertEqual(payload.success, true)
        XCTAssertTrue(payload.content.contains("Output:\nfrom-policy"))
        XCTAssertFalse(payload.content.contains("from-snapshot"))
    }

    func testUnifiedExecModelProvidedShellDoesNotUseSessionSnapshotLikeRust() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let snapshotPath = temp.url.appendingPathComponent("snapshot.sh")
        try """
        # Snapshot file
        export CODEX_SWIFT_MODEL_SHELL_SNAPSHOT=from-snapshot
        """.write(to: snapshotPath, atomically: true, encoding: .utf8)
        let snapshot = ShellSnapshot(path: snapshotPath, cwd: temp.url)
        let shell = Shell(shellType: .sh, shellPath: "/bin/sh", shellSnapshot: snapshot)
        let command = try Self.jsonString(#"printf '%s' "${CODEX_SWIFT_MODEL_SHELL_SNAPSHOT-unset}""#)
        let inheritedSnapshot = ResponseItem.functionCall(
            name: "exec_command",
            arguments: #"{"cmd":\#(command),"login":true,"yield_time_ms":1000}"#,
            callID: "call-exec-inherited-snapshot"
        )

        let inheritedOutput = await NonInteractiveExec.executeFunctionCall(
            inheritedSnapshot,
            cwd: temp.url,
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: shell,
            truncationPolicy: .bytes(10_000),
            environment: ["PATH": "/bin:/usr/bin", "HOME": temp.url.path]
        )

        guard case let .functionCallOutput(inheritedCallID, inheritedPayload) = inheritedOutput else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(inheritedCallID, "call-exec-inherited-snapshot")
        XCTAssertEqual(inheritedPayload.success, true)
        XCTAssertTrue(inheritedPayload.content.contains("Output:\nfrom-snapshot"), inheritedPayload.content)

        let modelProvidedShell = ResponseItem.functionCall(
            name: "exec_command",
            arguments: #"{"cmd":\#(command),"shell":"/bin/sh","login":true,"yield_time_ms":1000}"#,
            callID: "call-exec-model-shell"
        )

        let modelShellOutput = await NonInteractiveExec.executeFunctionCall(
            modelProvidedShell,
            cwd: temp.url,
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: shell,
            truncationPolicy: .bytes(10_000),
            environment: ["PATH": "/bin:/usr/bin", "HOME": temp.url.path]
        )

        guard case let .functionCallOutput(modelCallID, modelPayload) = modelShellOutput else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(modelCallID, "call-exec-model-shell")
        XCTAssertEqual(modelPayload.success, true)
        XCTAssertTrue(modelPayload.content.contains("Output:\nunset"), modelPayload.content)
        XCTAssertFalse(modelPayload.content.contains("from-snapshot"))
    }

    func testShellCommandDefaultsToNonLoginAndRejectsLoginWhenDisallowedLikeRust() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let snapshotPath = temp.url.appendingPathComponent("snapshot.sh")
        try """
        # Snapshot file
        export CODEX_SWIFT_LOGIN_POLICY=from-snapshot
        """.write(to: snapshotPath, atomically: true, encoding: .utf8)
        let snapshot = ShellSnapshot(path: snapshotPath, cwd: temp.url)
        let shell = Shell(shellType: .sh, shellPath: "/bin/sh", shellSnapshot: snapshot)
        let command = try Self.jsonString(#"printf '%s' "${CODEX_SWIFT_LOGIN_POLICY-unset}""#)
        let omittedLogin = ResponseItem.functionCall(
            name: "shell_command",
            arguments: #"{"command":\#(command)}"#,
            callID: "call-shell-login-omitted"
        )

        let omittedOutput = await NonInteractiveExec.executeFunctionCall(
            omittedLogin,
            cwd: temp.url,
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: shell,
            truncationPolicy: .bytes(10_000),
            environment: ["PATH": "/bin:/usr/bin", "HOME": temp.url.path],
            allowLoginShell: false
        )

        guard case let .functionCallOutput(omittedCallID, omittedPayload) = omittedOutput else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(omittedCallID, "call-shell-login-omitted")
        XCTAssertEqual(omittedPayload.success, true)
        XCTAssertTrue(omittedPayload.content.contains("Output:\nunset"), omittedPayload.content)
        XCTAssertFalse(omittedPayload.content.contains("from-snapshot"))

        let explicitLogin = ResponseItem.functionCall(
            name: "shell_command",
            arguments: #"{"command":"printf should-not-run","login":true}"#,
            callID: "call-shell-login-explicit"
        )
        let explicitOutput = await NonInteractiveExec.executeFunctionCall(
            explicitLogin,
            cwd: temp.url,
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: shell,
            truncationPolicy: .bytes(10_000),
            environment: ["PATH": "/bin:/usr/bin", "HOME": temp.url.path],
            allowLoginShell: false
        )

        guard case let .functionCallOutput(explicitCallID, explicitPayload) = explicitOutput else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(explicitCallID, "call-shell-login-explicit")
        XCTAssertEqual(explicitPayload.success, false)
        XCTAssertEqual(
            explicitPayload.content,
            "login shell is disabled by config; omit `login` or set it to false."
        )
    }

    func testUnifiedExecDefaultsToNonLoginAndRejectsLoginWhenDisallowedLikeRust() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let snapshotPath = temp.url.appendingPathComponent("snapshot.sh")
        try """
        # Snapshot file
        export CODEX_SWIFT_UNIFIED_LOGIN_POLICY=from-snapshot
        """.write(to: snapshotPath, atomically: true, encoding: .utf8)
        let snapshot = ShellSnapshot(path: snapshotPath, cwd: temp.url)
        let shell = Shell(shellType: .sh, shellPath: "/bin/sh", shellSnapshot: snapshot)
        let command = try Self.jsonString(#"printf '%s' "${CODEX_SWIFT_UNIFIED_LOGIN_POLICY-unset}""#)
        let omittedLogin = ResponseItem.functionCall(
            name: "exec_command",
            arguments: #"{"cmd":\#(command),"yield_time_ms":1000}"#,
            callID: "call-exec-login-omitted"
        )

        let omittedOutput = await NonInteractiveExec.executeFunctionCall(
            omittedLogin,
            cwd: temp.url,
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: shell,
            truncationPolicy: .bytes(10_000),
            environment: ["PATH": "/bin:/usr/bin", "HOME": temp.url.path],
            allowLoginShell: false
        )

        guard case let .functionCallOutput(omittedCallID, omittedPayload) = omittedOutput else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(omittedCallID, "call-exec-login-omitted")
        XCTAssertEqual(omittedPayload.success, true)
        XCTAssertTrue(omittedPayload.content.contains("Output:\nunset"), omittedPayload.content)
        XCTAssertFalse(omittedPayload.content.contains("from-snapshot"))

        let explicitLogin = ResponseItem.functionCall(
            name: "exec_command",
            arguments: #"{"cmd":"printf should-not-run","login":true,"yield_time_ms":1000}"#,
            callID: "call-exec-login-explicit"
        )
        let explicitOutput = await NonInteractiveExec.executeFunctionCall(
            explicitLogin,
            cwd: temp.url,
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: shell,
            truncationPolicy: .bytes(10_000),
            environment: ["PATH": "/bin:/usr/bin", "HOME": temp.url.path],
            allowLoginShell: false
        )

        guard case let .functionCallOutput(explicitCallID, explicitPayload) = explicitOutput else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(explicitCallID, "call-exec-login-explicit")
        XCTAssertEqual(explicitPayload.success, false)
        XCTAssertEqual(
            explicitPayload.content,
            "login shell is disabled by config; omit `login` or set it to false."
        )
    }

    func testEscalatedSandboxRequestReturnsFailureOutput() async throws {
        let item = ResponseItem.functionCall(
            name: "exec_command",
            arguments: #"{"cmd":"echo no","sandbox_permissions":"require_escalated"}"#,
            callID: "call-escalated"
        )

        let output = await NonInteractiveExec.executeFunctionCall(
            item,
            cwd: URL(fileURLWithPath: "/tmp", isDirectory: true),
            approvalPolicy: .never,
            sandboxPolicy: .readOnly,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: ["PATH": "/bin:/usr/bin"]
        )

        guard case let .functionCallOutput(callID, payload) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-escalated")
        XCTAssertEqual(payload.success, false)
        XCTAssertTrue(payload.content.contains("reject command"))
    }

    func testAdditionalPermissionsDisabledRejectsWithRustMessage() async throws {
        let item = ResponseItem.functionCall(
            name: "shell_command",
            arguments: #"{"command":"echo no","login":false,"sandbox_permissions":"with_additional_permissions","additional_permissions":{"network":{"enabled":true}}}"#,
            callID: "call-additional-disabled"
        )

        let output = await NonInteractiveExec.executeFunctionCall(
            item,
            cwd: URL(fileURLWithPath: "/tmp", isDirectory: true),
            approvalPolicy: .onRequest,
            sandboxPolicy: .readOnly,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: ["PATH": "/bin:/usr/bin"]
        )

        guard case let .functionCallOutput(callID, payload) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-additional-disabled")
        XCTAssertEqual(payload.success, false)
        XCTAssertEqual(
            payload.content,
            "additional permissions are disabled; enable `features.exec_permission_approvals` before using `with_additional_permissions`"
        )
    }

    func testAdditionalPermissionsRequireWithAdditionalSandboxPermissionLikeRust() async throws {
        let item = ResponseItem.functionCall(
            name: "exec_command",
            arguments: #"{"cmd":"echo no","login":false,"yield_time_ms":1000,"additional_permissions":{"network":{"enabled":true}}}"#,
            callID: "call-additional-requires-sandbox-permission"
        )

        let output = await NonInteractiveExec.executeFunctionCall(
            item,
            cwd: URL(fileURLWithPath: "/tmp", isDirectory: true),
            approvalPolicy: .onRequest,
            sandboxPolicy: .readOnly,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: ["PATH": "/bin:/usr/bin"],
            features: Self.execPermissionApprovalFeatures()
        )

        guard case let .functionCallOutput(callID, payload) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-additional-requires-sandbox-permission")
        XCTAssertEqual(payload.success, false)
        XCTAssertEqual(
            payload.content,
            "`additional_permissions` requires `sandbox_permissions` set to `with_additional_permissions`"
        )
    }

    func testAdditionalPermissionsRequireNonEmptyProfileLikeRust() async throws {
        let item = ResponseItem.functionCall(
            name: "shell_command",
            arguments: #"{"command":"echo no","login":false,"sandbox_permissions":"with_additional_permissions","additional_permissions":{}}"#,
            callID: "call-additional-empty"
        )

        let output = await NonInteractiveExec.executeFunctionCall(
            item,
            cwd: URL(fileURLWithPath: "/tmp", isDirectory: true),
            approvalPolicy: .onRequest,
            sandboxPolicy: .readOnly,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: ["PATH": "/bin:/usr/bin"],
            features: Self.execPermissionApprovalFeatures()
        )

        guard case let .functionCallOutput(callID, payload) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-additional-empty")
        XCTAssertEqual(payload.success, false)
        XCTAssertEqual(
            payload.content,
            "`additional_permissions` must include at least one requested permission in `network` or `file_system`"
        )
    }

    func testAdditionalPermissionsRejectNonDenyGlobGrantsLikeRust() async throws {
        let pattern = try Self.jsonString("/tmp/**/*.secret")
        let item = ResponseItem.functionCall(
            name: "shell_command",
            arguments: #"{"command":"echo no","login":false,"sandbox_permissions":"with_additional_permissions","additional_permissions":{"file_system":{"entries":[{"path":{"type":"glob_pattern","pattern":\#(pattern)},"access":"read"}]}}}"#,
            callID: "call-additional-glob-grant"
        )

        let output = await NonInteractiveExec.executeFunctionCall(
            item,
            cwd: URL(fileURLWithPath: "/tmp", isDirectory: true),
            approvalPolicy: .onRequest,
            sandboxPolicy: .readOnly,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: ["PATH": "/bin:/usr/bin"],
            features: Self.execPermissionApprovalFeatures()
        )

        guard case let .functionCallOutput(callID, payload) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-additional-glob-grant")
        XCTAssertEqual(payload.success, false)
        XCTAssertEqual(payload.content, "glob file system permissions only support deny-read entries")
    }

    func testAdditionalPermissionsWidenNetworkSandboxLikeRust() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let command = try Self.jsonString(#"printf '%s' "${CODEX_SANDBOX_NETWORK_DISABLED-unset}""#)
        let item = ResponseItem.functionCall(
            name: "shell_command",
            arguments: #"{"command":\#(command),"login":false,"sandbox_permissions":"with_additional_permissions","additional_permissions":{"network":{"enabled":true}}}"#,
            callID: "call-additional-network"
        )

        let result = await NonInteractiveExec.executeFunctionCallWithHooks(
            item,
            handlers: [try Self.allowPermissionRequestHook()],
            conversationID: ConversationId(),
            turnID: "turn-1",
            cwd: temp.url,
            model: "gpt-test",
            approvalPolicy: .onRequest,
            sandboxPolicy: .readOnly,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: ["PATH": "/bin:/usr/bin", "HOME": temp.url.path],
            features: Self.execPermissionApprovalFeatures()
        )

        guard case let .functionCallOutput(callID, payload) = result.output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-additional-network")
        XCTAssertEqual(payload.success, true, payload.content)
        XCTAssertTrue(payload.content.contains("Output:\nunset"), payload.content)
    }

    func testAdditionalPermissionsWidenShellCommandSandboxLikeRust() async throws {
        let workspace = try NonInteractiveExecTemporaryDirectory()
        let outside = try NonInteractiveExecTemporaryDirectory()
        let allowedFile = outside.url.appendingPathComponent("allowed-shell.txt")
        let commandPath = allowedFile.resolvingSymlinksInPath().standardizedFileURL.path
        let command = try Self.jsonString("printf shell-ok > '\(commandPath)'")
        let outsidePath = try Self.jsonString(outside.url.path)
        let item = ResponseItem.functionCall(
            name: "shell_command",
            arguments: #"{"command":\#(command),"login":false,"sandbox_permissions":"with_additional_permissions","additional_permissions":{"file_system":{"write":[\#(outsidePath)]}}}"#,
            callID: "call-additional-shell-write"
        )

        let result = await NonInteractiveExec.executeFunctionCallWithHooks(
            item,
            handlers: [try Self.allowPermissionRequestHook()],
            conversationID: ConversationId(),
            turnID: "turn-1",
            cwd: workspace.url,
            model: "gpt-test",
            approvalPolicy: .onRequest,
            sandboxPolicy: .workspaceWrite(
                writableRoots: [],
                networkAccess: false,
                excludeTmpdirEnvVar: true,
                excludeSlashTmp: true
            ),
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: ["PATH": "/bin:/usr/bin", "HOME": workspace.url.path],
            features: Self.execPermissionApprovalFeatures()
        )

        guard case let .functionCallOutput(callID, payload) = result.output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-additional-shell-write")
        XCTAssertEqual(payload.success, true, payload.content)
        XCTAssertEqual(try String(contentsOf: allowedFile, encoding: .utf8), "shell-ok")
    }

    func testAdditionalPermissionsWidenUnifiedExecSandboxLikeRust() async throws {
        let workspace = try NonInteractiveExecTemporaryDirectory()
        let outside = try NonInteractiveExecTemporaryDirectory()
        let allowedFile = outside.url.appendingPathComponent("allowed-exec.txt")
        let commandPath = allowedFile.resolvingSymlinksInPath().standardizedFileURL.path
        let command = try Self.jsonString("printf exec-ok > '\(commandPath)'")
        let outsidePath = try Self.jsonString(outside.url.path)
        let item = ResponseItem.functionCall(
            name: "exec_command",
            arguments: #"{"cmd":\#(command),"login":false,"yield_time_ms":1000,"sandbox_permissions":"with_additional_permissions","additional_permissions":{"file_system":{"write":[\#(outsidePath)]}}}"#,
            callID: "call-additional-exec-write"
        )

        let result = await NonInteractiveExec.executeFunctionCallWithHooks(
            item,
            handlers: [try Self.allowPermissionRequestHook()],
            conversationID: ConversationId(),
            turnID: "turn-1",
            cwd: workspace.url,
            model: "gpt-test",
            approvalPolicy: .onRequest,
            sandboxPolicy: .workspaceWrite(
                writableRoots: [],
                networkAccess: false,
                excludeTmpdirEnvVar: true,
                excludeSlashTmp: true
            ),
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: ["PATH": "/bin:/usr/bin", "HOME": workspace.url.path],
            features: Self.execPermissionApprovalFeatures()
        )

        guard case let .functionCallOutput(callID, payload) = result.output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-additional-exec-write")
        XCTAssertEqual(payload.success, true, payload.content)
        XCTAssertEqual(try String(contentsOf: allowedFile, encoding: .utf8), "exec-ok")
    }

    func testApplyPatchFunctionCallIsNoLongerExecutable() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let patch = """
        *** Begin Patch
        *** Add File: created.txt
        +hello
        *** End Patch
        """
        let encodedPatch = try Self.jsonString(patch)
        let item = ResponseItem.functionCall(
            name: "apply_patch",
            arguments: #"{"input":\#(encodedPatch)}"#,
            callID: "call-patch"
        )

        let output = await NonInteractiveExec.executeFunctionCall(
            item,
            cwd: temp.url,
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: [:]
        )

        guard case let .functionCallOutput(callID, payload) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-patch")
        XCTAssertEqual(payload.success, false)
        XCTAssertEqual(payload.content, "unsupported call: apply_patch")
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.url.appendingPathComponent("created.txt").path))
    }

    func testApplyPatchFunctionCallDoesNotRunHooksAfterRustFreeformDeletion() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let hookLog = temp.url.appendingPathComponent("pre-hook.json")
        let patch = """
        *** Begin Patch
        *** Add File: created.txt
        +hello
        *** End Patch
        """
        let encodedPatch = try Self.jsonString(patch)
        let item = ResponseItem.functionCall(
            name: "apply_patch",
            arguments: #"{"input":\#(encodedPatch)}"#,
            callID: "call-patch"
        )

        let result = await NonInteractiveExec.executeFunctionCallWithHooks(
            item,
            handlers: [
                ConfiguredHookHandler(
                    eventName: .preToolUse,
                    matcher: "apply_patch",
                    command: "cat > \(shellSingleQuote(hookLog.path)); printf %s '{\"decision\":\"block\",\"reason\":\"legacy function path\"}'",
                    timeoutSec: 5,
                    sourcePath: try AbsolutePath(absolutePath: "/tmp/hooks.json"),
                    displayOrder: 0
                )
            ],
            conversationID: ConversationId(),
            turnID: "turn-1",
            cwd: temp.url,
            model: "gpt-test",
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: [:]
        )

        guard case let .functionCallOutput(callID, payload) = result.output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-patch")
        XCTAssertEqual(payload.success, false)
        XCTAssertEqual(payload.content, "unsupported call: apply_patch")
        XCTAssertEqual(result.additionalContextItems, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: hookLog.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.url.appendingPathComponent("created.txt").path))
    }

    func testUnavailableMcpToolCallFallsBackToUnsupportedByDefaultLikeRustRemovedFeature() async throws {
        let output = await NonInteractiveExec.executeFunctionCall(
            .functionCall(
                name: "_create_event",
                namespace: "mcp__codex_apps__calendar",
                arguments: "{}",
                callID: "call-mcp"
            ),
            cwd: URL(fileURLWithPath: "/tmp", isDirectory: true),
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: [:]
        )

        guard case let .functionCallOutput(callID, payload) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-mcp")
        XCTAssertEqual(payload.success, false)
        XCTAssertEqual(payload.content, "unsupported call: mcp__codex_apps__calendar_create_event")
    }

    func testUnavailableMcpToolCallUsesRustPlaceholderMessageWhenFeatureEnabled() async throws {
        var features = FeatureStates.withDefaults()
        features.set(.unavailableDummyTools, enabled: true)

        let output = await NonInteractiveExec.executeFunctionCall(
            .functionCall(
                name: "_create_event",
                namespace: "mcp__codex_apps__calendar",
                arguments: "{}",
                callID: "call-mcp"
            ),
            cwd: URL(fileURLWithPath: "/tmp", isDirectory: true),
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: [:],
            features: features
        )

        guard case let .functionCallOutput(callID, payload) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-mcp")
        XCTAssertEqual(payload.success, false)
        XCTAssertEqual(
            payload.content,
            "Tool `mcp__codex_apps__calendar_create_event` is not currently available. It appeared in earlier tool calls in this conversation, but its implementation is not available in the current request. Retry after the tool becomes available or ask the user to re-enable it."
        )
    }

    func testReportAgentJobResultRequiresAgentJobContext() async throws {
        let output = await NonInteractiveExec.executeFunctionCall(
            .functionCall(
                name: "report_agent_job_result",
                arguments: #"{"job_id":"job-1","item_id":"row-1","result":{"ok":true}}"#,
                callID: "call-report"
            ),
            cwd: URL(fileURLWithPath: "/tmp", isDirectory: true),
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: [:]
        )

        guard case let .functionCallOutput(callID, payload) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-report")
        XCTAssertEqual(payload.success, false)
        XCTAssertEqual(payload.content, "unsupported call: report_agent_job_result")
    }

    func testReportAgentJobResultRequiresAgentJobWorkerSessionLikeRustRegistry() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let store = try SQLiteAgentJobStore(databaseURL: temp.url.appendingPathComponent("state.sqlite3"))

        let output = await NonInteractiveExec.executeFunctionCall(
            .functionCall(
                name: "report_agent_job_result",
                arguments: #"{"job_id":"job-1","item_id":"row-1","result":{"ok":true}}"#,
                callID: "call-report"
            ),
            cwd: temp.url,
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: [:],
            agentJobContext: NonInteractiveExec.AgentJobToolContext(
                store: store,
                reportingThreadID: "thread-1",
                sessionSource: .cli
            )
        )

        guard case let .functionCallOutput(callID, payload) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-report")
        XCTAssertEqual(payload.success, false)
        XCTAssertEqual(payload.content, "unsupported call: report_agent_job_result")
    }

    func testReportAgentJobResultRecordsAcceptedResultLikeRustHandler() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let store = try SQLiteAgentJobStore(databaseURL: temp.url.appendingPathComponent("state.sqlite3"))
        _ = try await store.createAgentJob(
            params: AgentJobCreateParams(
                id: "job-1",
                name: "job",
                instruction: "do it",
                outputSchemaJSON: nil,
                inputHeaders: ["id"],
                inputCSVPath: "/tmp/input.csv",
                outputCSVPath: temp.url.appendingPathComponent("output.csv").path,
                autoExport: true,
                maxRuntimeSeconds: nil
            ),
            items: [
                AgentJobItemCreateParams(
                    itemID: "row-1",
                    rowIndex: 0,
                    sourceID: nil,
                    rowJSON: .object(["id": .string("1")])
                ),
            ]
        )
        try await store.markAgentJobRunning("job-1")
        let markedRunning = try await store.markAgentJobItemRunningWithThread(
            jobID: "job-1",
            itemID: "row-1",
            threadID: "thread-1"
        )
        XCTAssertTrue(markedRunning)

        let output = await NonInteractiveExec.executeFunctionCall(
            .functionCall(
                name: "report_agent_job_result",
                arguments: #"{"job_id":"job-1","item_id":"row-1","result":{"ok":true},"stop":true}"#,
                callID: "call-report"
            ),
            cwd: temp.url,
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: [:],
            agentJobContext: NonInteractiveExec.AgentJobToolContext(
                store: store,
                reportingThreadID: "thread-1",
                sessionSource: .subagent(.other("agent_job:job-1"))
            )
        )

        guard case let .functionCallOutput(callID, payload) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-report")
        XCTAssertEqual(payload.success, true)
        XCTAssertEqual(payload.content, #"{"accepted":true}"#)

        let persistedItem = try await store.getAgentJobItem(jobID: "job-1", itemID: "row-1")
        let item = try XCTUnwrap(persistedItem)
        XCTAssertEqual(item.status, .completed)
        XCTAssertEqual(item.resultJSON, .object(["ok": .bool(true)]))
        let persistedJob = try await store.getAgentJob("job-1")
        let job = try XCTUnwrap(persistedJob)
        XCTAssertEqual(job.status, .cancelled)
        XCTAssertEqual(job.lastError, "cancelled by worker request")
    }

    func testSpawnAgentsOnCSVRequiresAgentJobRunnerContext() async throws {
        let output = await NonInteractiveExec.executeFunctionCall(
            .functionCall(
                name: "spawn_agents_on_csv",
                arguments: #"{"csv_path":"input.csv","instruction":"check {id}"}"#,
                callID: "call-spawn"
            ),
            cwd: URL(fileURLWithPath: "/tmp", isDirectory: true),
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: [:]
        )

        guard case let .functionCallOutput(callID, payload) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-spawn")
        XCTAssertEqual(payload.success, false)
        XCTAssertEqual(payload.content, "unsupported call: spawn_agents_on_csv")
    }

    func testSpawnAgentsOnCSVRunsJobLoopAndReturnsRustShapedResult() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let environmentCwd = temp.url.appendingPathComponent("selected-env", isDirectory: true)
        try FileManager.default.createDirectory(at: environmentCwd, withIntermediateDirectories: true)
        let inputURL = environmentCwd.appendingPathComponent("input.csv")
        let outputURL = environmentCwd.appendingPathComponent("results.csv")
        try "id,value\nalpha,one\n".write(to: inputURL, atomically: true, encoding: .utf8)
        let store = try SQLiteAgentJobStore(databaseURL: temp.url.appendingPathComponent("state.sqlite3"))
        let workerThreadID = try ThreadId(string: "00000000-0000-4000-8000-000000000061")
        let parentThreadID = try ThreadId(string: "00000000-0000-4000-8000-000000000060")
        let statusStore = NonInteractiveAgentStatusStore(statuses: [workerThreadID: .running])
        let spawnRecorder = NonInteractiveAgentSpawnRecorder(results: [.spawned(workerThreadID)])
        let shutdownRecorder = NonInteractiveThreadRecorder()
        let shellEnvironmentPolicy = ShellEnvironmentPolicy(inherit: .all, set: ["JOB": "1"])
        let spawnConfigSource = AgentJobSpawnConfigSource(
            parentConfig: CodexRuntimeConfig(
                modelProvider: "parent-provider",
                shellEnvironmentPolicy: ShellEnvironmentPolicy(inherit: .core, set: ["PARENT": "1"])
            ),
            baseInstructions: "agent job base",
            model: "gpt-job",
            modelProviderID: "job-provider",
            reasoningEffort: .medium,
            reasoningSummary: .concise,
            developerInstructions: "job developer",
            compactPrompt: "job compact",
            turnContext: TurnContext(
                cwd: temp.url.path,
                approvalPolicy: .onRequest,
                sandboxPolicy: .readOnlyWithNetworkAccess
            ),
            shellEnvironmentPolicy: shellEnvironmentPolicy
        )
        let environments = [
            TurnEnvironmentSelection(environmentID: "local", cwd: environmentCwd.path)
        ]

        let output = await NonInteractiveExec.executeFunctionCall(
            .functionCall(
                name: "spawn_agents_on_csv",
                arguments: #"{"csv_path":"input.csv","instruction":"check {id}","id_column":"id","output_csv_path":"results.csv","max_concurrency":1}"#,
                callID: "call-spawn"
            ),
            cwd: temp.url,
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: [:],
            agentJobContext: NonInteractiveExec.AgentJobToolContext(
                store: store,
                reportingThreadID: "parent-thread",
                sessionSource: .subagent(.threadSpawn(parentThreadID: parentThreadID, depth: 1)),
                maxDepth: 2,
                spawnConfigSource: spawnConfigSource,
                environments: environments,
                statusForThread: { threadID in
                    await statusStore.status(for: threadID)
                },
                spawnWorker: { request in
                    await spawnRecorder.spawn(request)
                },
                shutdownThread: { threadID in
                    await shutdownRecorder.append(threadID)
                },
                waitWhenIdle: {
                    let jobs = await spawnRecorder.jobIDs()
                    if let jobID = jobs.first {
                        _ = try? await store.reportAgentJobItemResult(
                            jobID: jobID,
                            itemID: "alpha",
                            reportingThreadID: workerThreadID.description,
                            resultJSON: .object(["passed": .bool(true)])
                        )
                    }
                    await statusStore.set(.completed(nil), for: workerThreadID)
                }
            )
        )

        guard case let .functionCallOutput(callID, payload) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-spawn")
        XCTAssertEqual(payload.success, true)
        let data = try XCTUnwrap(payload.content.data(using: .utf8))
        let decoded = try JSONDecoder().decode(SpawnAgentsOnCSVResult.self, from: data)
        XCTAssertEqual(decoded.status, "completed")
        XCTAssertEqual(decoded.outputCSVPath, outputURL.path)
        XCTAssertEqual(decoded.totalItems, 1)
        XCTAssertEqual(decoded.completedItems, 1)
        XCTAssertEqual(decoded.failedItems, 0)
        XCTAssertNil(decoded.jobError)
        XCTAssertNil(decoded.failedItemErrors)

        let requests = await spawnRecorder.requests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].itemID, "alpha")
        XCTAssertEqual(requests[0].spawnConfig, AgentJobRuntime.buildAgentSpawnConfig(source: spawnConfigSource))
        XCTAssertEqual(requests[0].sessionSource, .subagent(.other("agent_job:\(decoded.jobID)")))
        XCTAssertEqual(requests[0].environments, environments)
        XCTAssertTrue(requests[0].prompt.contains("check alpha"))
        let shutdownThreads = await shutdownRecorder.values()
        XCTAssertEqual(shutdownThreads, [workerThreadID])
        let exported = try String(contentsOf: outputURL, encoding: .utf8)
        XCTAssertTrue(exported.contains(#"alpha,one,"#))
        XCTAssertTrue(exported.contains(#"alpha,completed,1,,"{""passed"":true}""#))
    }

    func testSpawnAgentsOnCSVRejectsMultipleTurnEnvironmentsLikeRust() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let inputURL = temp.url.appendingPathComponent("input.csv")
        try "id,value\nalpha,one\n".write(to: inputURL, atomically: true, encoding: .utf8)
        let store = try SQLiteAgentJobStore(databaseURL: temp.url.appendingPathComponent("state.sqlite3"))

        let output = await NonInteractiveExec.executeFunctionCall(
            .functionCall(
                name: "spawn_agents_on_csv",
                arguments: #"{"csv_path":"input.csv","instruction":"check {id}"}"#,
                callID: "call-spawn-multiple-envs"
            ),
            cwd: temp.url,
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: [:],
            agentJobContext: NonInteractiveExec.AgentJobToolContext(
                store: store,
                reportingThreadID: "parent-thread",
                environments: [
                    TurnEnvironmentSelection(environmentID: "local", cwd: temp.url.path),
                    TurnEnvironmentSelection(environmentID: "remote-dev", cwd: "/workspace")
                ],
                statusForThread: { _ in .running },
                spawnWorker: { _ in .agentLimitReached },
                shutdownThread: { _ in }
            )
        )

        guard case let .functionCallOutput(callID, payload) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-spawn-multiple-envs")
        XCTAssertEqual(payload.success, false)
        XCTAssertEqual(payload.content, "spawn_agents_on_csv requires exactly one local environment")
    }

    func testUnsupportedCustomToolCallUsesRustRegistryMessage() async throws {
        let item = ResponseItem.customToolCall(callID: "custom-unknown", name: "missing_tool", input: "")

        let output = await NonInteractiveExec.executeFunctionCall(
            item,
            cwd: URL(fileURLWithPath: "/tmp", isDirectory: true),
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: [:]
        )

        XCTAssertEqual(
            output,
            .customToolCallOutput(
                callID: "custom-unknown",
                output: "unsupported custom tool call: missing_tool"
            )
        )
    }

    func testApplyPatchCustomToolCallAppliesFreeformInput() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let patch = """
        *** Begin Patch
        *** Add File: custom.txt
        +custom
        *** End Patch
        """
        let item = ResponseItem.customToolCall(callID: "custom-patch", name: "apply_patch", input: patch)

        let output = await NonInteractiveExec.executeFunctionCall(
            item,
            cwd: temp.url,
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: [:]
        )

        XCTAssertEqual(
            output,
            .customToolCallOutput(
                callID: "custom-patch",
                output: "Success. Updated the following files:\nA custom.txt\n"
            )
        )
        XCTAssertEqual(
            try String(contentsOf: temp.url.appendingPathComponent("custom.txt"), encoding: .utf8),
            "custom\n"
        )
    }

    func testApplyPatchCustomToolCallRejectsReadOnlySandboxWithNeverApproval() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let patch = """
        *** Begin Patch
        *** Add File: blocked.txt
        +blocked
        *** End Patch
        """
        let item = ResponseItem.customToolCall(callID: "custom-patch", name: "apply_patch", input: patch)

        let output = await NonInteractiveExec.executeFunctionCall(
            item,
            cwd: temp.url,
            approvalPolicy: .never,
            sandboxPolicy: .readOnly,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: [:]
        )

        XCTAssertEqual(
            output,
            .customToolCallOutput(
                callID: "custom-patch",
                output: "apply_patch rejected: writing is blocked by read-only sandbox; rejected by user approval settings"
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.url.appendingPathComponent("blocked.txt").path))
    }

    func testApplyPatchShellCommandInterceptAppliesVerifiedHeredoc() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let script = """
        apply_patch <<'PATCH'
        *** Begin Patch
        *** Add File: shell.txt
        +shell
        *** End Patch
        PATCH
        """
        let encodedScript = try Self.jsonString(script)
        let item = ResponseItem.functionCall(
            name: "shell_command",
            arguments: #"{"command":\#(encodedScript),"login":false}"#,
            callID: "call-shell-patch"
        )

        let output = await NonInteractiveExec.executeFunctionCall(
            item,
            cwd: temp.url,
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: ["PATH": "/bin:/usr/bin"]
        )

        guard case let .functionCallOutput(callID, payload) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-shell-patch")
        XCTAssertEqual(payload.success, true)
        XCTAssertTrue(payload.content.contains("Exit code: 0"))
        XCTAssertTrue(payload.content.contains("A shell.txt"))
        XCTAssertEqual(
            try String(contentsOf: temp.url.appendingPathComponent("shell.txt"), encoding: .utf8),
            "shell\n"
        )
    }

    func testApplyPatchShellCommandInterceptRejectsReadOnlySandboxWithNeverApproval() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let script = """
        apply_patch <<'PATCH'
        *** Begin Patch
        *** Add File: blocked-shell.txt
        +blocked
        *** End Patch
        PATCH
        """
        let encodedScript = try Self.jsonString(script)
        let item = ResponseItem.functionCall(
            name: "shell_command",
            arguments: #"{"command":\#(encodedScript),"login":false}"#,
            callID: "call-shell-patch"
        )

        let output = await NonInteractiveExec.executeFunctionCall(
            item,
            cwd: temp.url,
            approvalPolicy: .never,
            sandboxPolicy: .readOnly,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: ["PATH": "/bin:/usr/bin"]
        )

        guard case let .functionCallOutput(_, payload) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(payload.success, false)
        XCTAssertTrue(payload.content.contains("apply_patch rejected"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.url.appendingPathComponent("blocked-shell.txt").path))
    }

    func testUnifiedExecCommandPersistsSessionAndWriteStdinContinuesIt() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let start = ResponseItem.functionCall(
            name: "exec_command",
            arguments: #"{"cmd":"read line; echo got:$line","tty":true,"yield_time_ms":100}"#,
            callID: "call-start"
        )

        let startOutput = await NonInteractiveExec.executeFunctionCall(
            start,
            cwd: temp.url,
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: ["PATH": "/bin:/usr/bin", "HOME": temp.url.path]
        )

        guard case let .functionCallOutput(_, startPayload) = startOutput else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(startPayload.success, true)
        let sessionID = try XCTUnwrap(Self.sessionID(from: startPayload.content))

        let write = ResponseItem.functionCall(
            name: "write_stdin",
            arguments: #"{"session_id":\#(sessionID),"chars":"hello\n","yield_time_ms":2500}"#,
            callID: "call-write"
        )
        let writeOutput = await NonInteractiveExec.executeFunctionCall(
            write,
            cwd: temp.url,
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: ["PATH": "/bin:/usr/bin", "HOME": temp.url.path]
        )

        guard case let .functionCallOutput(callID, payload) = writeOutput else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-write")
        XCTAssertEqual(payload.success, true)
        XCTAssertTrue(payload.content.contains("Process exited with code 0"))
        XCTAssertTrue(payload.content.contains("got:hello"))
    }

    func testWriteStdinPostToolUseUsesOriginalExecCommandLikeRust() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let preHookMarker = temp.url.appendingPathComponent("pre-hook-ran")
        let postHookLog = temp.url.appendingPathComponent("post-hook.json")
        let start = ResponseItem.functionCall(
            name: "exec_command",
            arguments: #"{"cmd":"read line; echo got:$line","tty":true,"yield_time_ms":100}"#,
            callID: "call-start"
        )

        let startOutput = await NonInteractiveExec.executeFunctionCallWithHooks(
            start,
            handlers: [],
            conversationID: ConversationId(),
            turnID: "turn-1",
            cwd: temp.url,
            model: "gpt-test",
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: ["PATH": "/bin:/usr/bin", "HOME": temp.url.path]
        )

        guard case let .functionCallOutput(_, startPayload) = startOutput.output else {
            return XCTFail("expected function call output")
        }
        let sessionID = try XCTUnwrap(Self.sessionID(from: startPayload.content))

        let write = ResponseItem.functionCall(
            name: "write_stdin",
            arguments: #"{"session_id":\#(sessionID),"chars":"hello\n","yield_time_ms":2500}"#,
            callID: "call-write"
        )
        let writeOutput = await NonInteractiveExec.executeFunctionCallWithHooks(
            write,
            handlers: [
                ConfiguredHookHandler(
                    eventName: .preToolUse,
                    matcher: "write_stdin",
                    command: "touch \(shellSingleQuote(preHookMarker.path)); printf '{}'",
                    timeoutSec: 5,
                    sourcePath: try AbsolutePath(absolutePath: "/tmp/hooks.json"),
                    displayOrder: 0
                ),
                ConfiguredHookHandler(
                    eventName: .postToolUse,
                    matcher: "Bash",
                    command: "cat > \(shellSingleQuote(postHookLog.path)); printf '{}'",
                    timeoutSec: 5,
                    sourcePath: try AbsolutePath(absolutePath: "/tmp/hooks.json"),
                    displayOrder: 1
                )
            ],
            conversationID: ConversationId(),
            turnID: "turn-1",
            cwd: temp.url,
            model: "gpt-test",
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: ["PATH": "/bin:/usr/bin", "HOME": temp.url.path]
        )

        guard case let .functionCallOutput(callID, payload) = writeOutput.output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-write")
        XCTAssertEqual(payload.success, true)
        XCTAssertTrue(payload.content.contains("got:hello"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: preHookMarker.path))

        let object = try hookInputObject(at: postHookLog)
        XCTAssertEqual(object["tool_name"] as? String, "Bash")
        XCTAssertEqual(object["tool_use_id"] as? String, "call-start")
        XCTAssertEqual(object["tool_response"] as? String, "hello\r\ngot:hello\r\n")
        let input = try XCTUnwrap(object["tool_input"] as? [String: Any])
        XCTAssertEqual(input["command"] as? String, "read line; echo got:$line")
    }

    func testUnifiedExecRejectsNonTTYStdinWritesLikeRust() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let start = ResponseItem.functionCall(
            name: "exec_command",
            arguments: #"{"cmd":"sleep 2","yield_time_ms":100}"#,
            callID: "call-non-tty-start"
        )

        let startOutput = await NonInteractiveExec.executeFunctionCall(
            start,
            cwd: temp.url,
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: ["PATH": "/bin:/usr/bin", "HOME": temp.url.path]
        )

        guard case let .functionCallOutput(_, startPayload) = startOutput else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(startPayload.success, true)
        let sessionID = try XCTUnwrap(Self.sessionID(from: startPayload.content))

        let write = ResponseItem.functionCall(
            name: "write_stdin",
            arguments: #"{"session_id":\#(sessionID),"chars":"hello\n","yield_time_ms":250}"#,
            callID: "call-non-tty-write"
        )
        let writeOutput = await NonInteractiveExec.executeFunctionCall(
            write,
            cwd: temp.url,
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: ["PATH": "/bin:/usr/bin", "HOME": temp.url.path]
        )

        guard case let .functionCallOutput(callID, payload) = writeOutput else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-non-tty-write")
        XCTAssertEqual(payload.success, false)
        XCTAssertEqual(
            payload.content,
            "write_stdin failed: stdin is closed for this session; rerun exec_command with tty=true to keep stdin open"
        )

        let poll = ResponseItem.functionCall(
            name: "write_stdin",
            arguments: #"{"session_id":\#(sessionID),"chars":"","yield_time_ms":2500}"#,
            callID: "call-non-tty-poll"
        )
        _ = await NonInteractiveExec.executeFunctionCall(
            poll,
            cwd: temp.url,
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: ["PATH": "/bin:/usr/bin", "HOME": temp.url.path]
        )
    }

    func testUnifiedExecTtyRunsCommandInPseudoTerminalLikeRust() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let item = ResponseItem.functionCall(
            name: "exec_command",
            arguments: #"{"cmd":"test -t 0 && printf tty || printf notty","tty":true,"yield_time_ms":1000}"#,
            callID: "call-tty"
        )

        let output = await NonInteractiveExec.executeFunctionCall(
            item,
            cwd: temp.url,
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: ["PATH": "/bin:/usr/bin", "HOME": temp.url.path]
        )

        guard case let .functionCallOutput(callID, payload) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-tty")
        XCTAssertEqual(payload.success, true)
        XCTAssertTrue(payload.content.contains("Output:\ntty"), payload.content)
        XCTAssertFalse(payload.content.contains("notty"), payload.content)
    }

    func testPermissionRequestHookAllowsPolicyPromptedExecCommandLikeRust() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let hookInputLog = temp.url.appendingPathComponent("exec-permission-hook-input.json")
        let item = ResponseItem.functionCall(
            name: "exec_command",
            arguments: #"{"cmd":"touch unified-by-hook.txt","login":false,"justification":"create marker","prefix_rule":["touch"]}"#,
            callID: "call-exec-policy-hook"
        )

        let result = await NonInteractiveExec.executeFunctionCallWithHooks(
            item,
            handlers: [
                ConfiguredHookHandler(
                    eventName: .permissionRequest,
                    matcher: "Bash",
                    command: #"cat > '\#(hookInputLog.path)'; printf %s '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'"#,
                    timeoutSec: 5,
                    sourcePath: try AbsolutePath(absolutePath: "/tmp/hooks.json"),
                    displayOrder: 0
                )
            ],
            conversationID: ConversationId(),
            turnID: "turn-1",
            cwd: temp.url,
            model: "gpt-test",
            approvalPolicy: .unlessTrusted,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: ["PATH": "/bin:/usr/bin", "HOME": temp.url.path]
        )

        guard case let .functionCallOutput(callID, payload) = result.output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-exec-policy-hook")
        XCTAssertEqual(payload.success, true)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: temp.url.appendingPathComponent("unified-by-hook.txt").path
        ))

        let hookInput = try Data(contentsOf: hookInputLog)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: hookInput) as? [String: Any])
        let toolInput = try XCTUnwrap(object["tool_input"] as? [String: Any])
        XCTAssertEqual(toolInput["command"] as? String, "touch unified-by-hook.txt")
        XCTAssertEqual(toolInput["description"] as? String, "create marker")
    }

    func testHumanOutputReturnsFinalAssistantMessageAndWritesLastMessage() throws {
        let id = try ConversationId(string: "018f7a2d-4c5b-7abc-8def-0123456789ab")
        let writes = WriteSink()

        let result = NonInteractiveExec.finish(
            responseEvents: [
                .success(.outputTextDelta("do")),
                .success(.outputTextDelta("ne")),
                .success(.completed(responseID: "resp_1", tokenUsage: TokenUsage(totalTokens: 12)))
            ],
            outputMode: .human,
            conversationID: id,
            lastMessageFile: "/tmp/last.txt",
            writeFile: { path, contents in
                writes.write(path: path, contents: contents)
            }
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdoutMessage, "done")
        XCTAssertEqual(result.stderrMessages, [])
        XCTAssertEqual(result.lastAgentMessage, "done")
        XCTAssertEqual(writes.contents(at: "/tmp/last.txt"), "done")
    }

    func testJSONLinesOutputUsesExecEventEnvelope() throws {
        let id = try ConversationId(string: "018f7a2d-4c5b-7abc-8def-0123456789ab")
        let result = NonInteractiveExec.finish(
            responseEvents: [
                .success(.outputItemDone(.message(role: "assistant", content: [.outputText(text: "done")]))),
                .success(.completed(
                    responseID: "resp_1",
                    tokenUsage: TokenUsage(
                        inputTokens: 3,
                        cachedInputTokens: 1,
                        outputTokens: 5,
                        reasoningOutputTokens: 2,
                        totalTokens: 8
                    )
                ))
            ],
            outputMode: .jsonLines,
            conversationID: id,
            lastMessageFile: nil
        )

        XCTAssertEqual(result.exitCode, 0)
        let lines = try XCTUnwrap(result.stdoutMessage?.split(separator: "\n").map(String.init))
        XCTAssertEqual(lines.count, 4)
        let objects = try lines.map(jsonObject)
        XCTAssertEqual(objects[0]["type"], .string("thread.started"))
        XCTAssertEqual(objects[0]["thread_id"], .string(id.description))
        XCTAssertEqual(objects[1]["type"], .string("turn.started"))
        XCTAssertEqual(objects[2]["type"], .string("item.completed"))
        XCTAssertEqual(objects[3]["type"], .string("turn.completed"))
        guard case let .object(item)? = objects[2]["item"] else {
            return XCTFail("expected completed item")
        }
        XCTAssertEqual(item["type"], .string("agent_message"))
        XCTAssertEqual(item["text"], .string("done"))
        guard case let .object(usage)? = objects[3]["usage"] else {
            return XCTFail("expected usage")
        }
        XCTAssertEqual(usage["input_tokens"], .integer(3))
        XCTAssertEqual(usage["cached_input_tokens"], .integer(1))
        XCTAssertEqual(usage["output_tokens"], .integer(5))
        XCTAssertEqual(usage["reasoning_output_tokens"], .integer(2))
        XCTAssertNil(usage["total_tokens"])
    }

    func testJSONLinesReasoningItemUsesSummaryTextLikeRust() throws {
        let id = try ConversationId(string: "018f7a2d-4c5b-7abc-8def-0123456789ab")
        let result = NonInteractiveExec.finish(
            responseEvents: [
                .success(.outputItemDone(.reasoning(
                    id: "reasoning-1",
                    summary: [.summaryText(text: "summary one"), .summaryText(text: "summary two")],
                    content: [.reasoningText(text: "raw hidden")],
                    encryptedContent: nil
                ))),
                .success(.completed(responseID: "resp_1", tokenUsage: nil))
            ],
            outputMode: .jsonLines,
            conversationID: id,
            lastMessageFile: nil
        )

        XCTAssertEqual(result.exitCode, 0)
        let lines = try XCTUnwrap(result.stdoutMessage?.split(separator: "\n").map(String.init))
        XCTAssertEqual(lines.count, 4)
        let objects = try lines.map(jsonObject)
        XCTAssertEqual(objects[2]["type"], .string("item.completed"))
        guard case let .object(item)? = objects[2]["item"] else {
            return XCTFail("expected completed item")
        }
        XCTAssertEqual(item["id"], .string("item_0"))
        XCTAssertEqual(item["type"], .string("reasoning"))
        XCTAssertEqual(item["text"], .string("summary one\nsummary two"))
    }

    func testJSONLinesReasoningItemSkipsEmptySummaryLikeRust() throws {
        let id = try ConversationId(string: "018f7a2d-4c5b-7abc-8def-0123456789ab")
        let result = NonInteractiveExec.finish(
            responseEvents: [
                .success(.outputItemDone(.reasoning(
                    id: "reasoning-1",
                    summary: [],
                    content: [.reasoningText(text: "raw hidden")],
                    encryptedContent: nil
                ))),
                .success(.completed(responseID: "resp_1", tokenUsage: nil))
            ],
            outputMode: .jsonLines,
            conversationID: id,
            lastMessageFile: nil
        )

        XCTAssertEqual(result.exitCode, 0)
        let lines = try XCTUnwrap(result.stdoutMessage?.split(separator: "\n").map(String.init))
        XCTAssertEqual(lines.count, 3)
        let objects = try lines.map(jsonObject)
        XCTAssertEqual(objects.map { $0["type"] }, [
            .string("thread.started"),
            .string("turn.started"),
            .string("turn.completed")
        ])
    }

    func testJSONLinesOutputEmitsWebSearchCompletedItem() throws {
        let id = try ConversationId(string: "018f7a2d-4c5b-7abc-8def-0123456789ab")
        let result = NonInteractiveExec.finish(
            responseEvents: [
                .success(.outputItemDone(.webSearchCall(
                    id: "web-search-1",
                    status: "completed",
                    action: .search(query: "rust async await")
                ))),
                .success(.completed(responseID: "resp_1", tokenUsage: nil))
            ],
            outputMode: .jsonLines,
            conversationID: id,
            lastMessageFile: nil
        )

        XCTAssertEqual(result.exitCode, 0)
        let lines = try XCTUnwrap(result.stdoutMessage?.split(separator: "\n").map(String.init))
        XCTAssertEqual(lines.count, 4)
        let objects = try lines.map(jsonObject)
        XCTAssertEqual(objects[2]["type"], .string("item.completed"))
        guard case let .object(item)? = objects[2]["item"] else {
            return XCTFail("expected completed item")
        }
        XCTAssertEqual(item["id"], .string("item_0"))
        XCTAssertEqual(item["type"], .string("web_search"))
        XCTAssertEqual(item["query"], .string("rust async await"))
        XCTAssertEqual(item["action"]?["type"], .string("search"))
        XCTAssertEqual(item["action"]?["query"], .string("rust async await"))
        guard case let .object(usage)? = objects[3]["usage"] else {
            return XCTFail("expected default usage")
        }
        XCTAssertEqual(usage["input_tokens"], .integer(0))
        XCTAssertEqual(usage["cached_input_tokens"], .integer(0))
        XCTAssertEqual(usage["output_tokens"], .integer(0))
        XCTAssertEqual(usage["reasoning_output_tokens"], .integer(0))
        XCTAssertNil(result.lastAgentMessage)
    }

    func testJSONLinesOutputEmitsWebSearchStartedAndCompletedItemsLikeRust() throws {
        let id = try ConversationId(string: "018f7a2d-4c5b-7abc-8def-0123456789ab")
        let result = NonInteractiveExec.finish(
            responseEvents: [
                .success(.outputItemAdded(.webSearchCall(
                    id: "ws_1",
                    status: "in_progress",
                    action: nil
                ))),
                .success(.outputItemDone(.webSearchCall(
                    id: "ws_1",
                    status: "completed",
                    action: .findInPage(url: "https://example.com", pattern: "needle")
                ))),
                .success(.completed(responseID: "resp_1", tokenUsage: nil))
            ],
            outputMode: .jsonLines,
            conversationID: id,
            lastMessageFile: nil
        )

        XCTAssertEqual(result.exitCode, 0)
        let lines = try XCTUnwrap(result.stdoutMessage?.split(separator: "\n").map(String.init))
        XCTAssertEqual(lines.count, 5)
        let objects = try lines.map(jsonObject)
        XCTAssertEqual(objects.map { $0["type"] }, [
            .string("thread.started"),
            .string("turn.started"),
            .string("item.started"),
            .string("item.completed"),
            .string("turn.completed")
        ])
        guard case let .object(startedItem)? = objects[2]["item"],
              case let .object(completedItem)? = objects[3]["item"]
        else {
            return XCTFail("expected web search items")
        }
        XCTAssertEqual(startedItem["id"], .string("item_0"))
        XCTAssertEqual(startedItem["type"], .string("web_search"))
        XCTAssertEqual(startedItem["query"], .string(""))
        XCTAssertEqual(startedItem["action"]?["type"], .string("other"))
        XCTAssertEqual(completedItem["id"], .string("item_0"))
        XCTAssertEqual(completedItem["type"], .string("web_search"))
        XCTAssertEqual(completedItem["query"], .string("'needle' in https://example.com"))
        XCTAssertEqual(completedItem["action"]?["type"], .string("find_in_page"))
        XCTAssertEqual(completedItem["action"]?["url"], .string("https://example.com"))
        XCTAssertEqual(completedItem["action"]?["pattern"], .string("needle"))
    }

    func testFailureOutputReturnsExitOneAndWritesEmptyLastMessage() throws {
        let id = try ConversationId(string: "018f7a2d-4c5b-7abc-8def-0123456789ab")
        let writes = WriteSink()

        let result = NonInteractiveExec.finish(
            responseEvents: [.failure(.quotaExceeded)],
            outputMode: .human,
            conversationID: id,
            lastMessageFile: "/tmp/last.txt",
            writeFile: { path, contents in
                writes.write(path: path, contents: contents)
            }
        )

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertNil(result.stdoutMessage)
        XCTAssertEqual(result.stderrMessages.first, "quota exceeded")
        XCTAssertEqual(writes.contents(at: "/tmp/last.txt"), "")
        XCTAssertEqual(result.stderrMessages.last, "Warning: no last agent message; wrote empty content to /tmp/last.txt")
    }

    func testJSONLinesFailureUsesRustTurnFailedErrorShape() throws {
        let id = try ConversationId(string: "018f7a2d-4c5b-7abc-8def-0123456789ab")
        let result = NonInteractiveExec.finish(
            responseEvents: [.failure(.quotaExceeded)],
            outputMode: .jsonLines,
            conversationID: id,
            lastMessageFile: nil
        )

        XCTAssertEqual(result.exitCode, 1)
        let lines = try XCTUnwrap(result.stdoutMessage?.split(separator: "\n").map(String.init))
        XCTAssertEqual(lines.count, 4)
        let objects = try lines.map(jsonObject)
        XCTAssertEqual(objects[2]["type"], .string("error"))
        XCTAssertEqual(objects[2]["message"], .string("quota exceeded"))
        XCTAssertEqual(objects[3]["type"], .string("turn.failed"))
        guard case let .object(error)? = objects[3]["error"] else {
            return XCTFail("expected Rust-shaped turn.failed error object")
        }
        XCTAssertEqual(error["message"], .string("quota exceeded"))
    }

    private func jsonObject(_ line: String) throws -> [String: JSONValue] {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))
        guard case let .object(object) = value else {
            throw XCTSkip("expected object")
        }
        return object
    }
}

private final class WriteSink: @unchecked Sendable {
    private let lock = NSLock()
    private var writes: [String: String] = [:]

    func write(path: String, contents: String) {
        lock.withLock {
            writes[path] = contents
        }
    }

    func contents(at path: String) -> String? {
        lock.withLock {
            writes[path]
        }
    }
}

private extension NonInteractiveExecTests {
    func functionTool(named name: String, in specs: [ConfiguredToolSpec]) throws -> ResponsesAPITool {
        let spec = try XCTUnwrap(specs.first { $0.spec.name == name }?.spec)
        guard case let .function(function) = spec else {
            throw NSError(domain: "NonInteractiveExecTests", code: 1)
        }
        return function
    }

    static func makeToolSearchIndex() -> ToolSearchIndex {
        ToolSearchIndex.mcpIndex(from: [
            "mcp__calendar__create_event": McpTool(
                name: "create_event",
                inputSchema: McpToolInputSchema(),
                description: "Create calendar events"
            )
        ])
    }

    static func sessionID(from content: String) -> Int? {
        let prefix = "Process running with session ID "
        guard let line = content
            .split(separator: "\n")
            .first(where: { $0.hasPrefix(prefix) })
        else {
            return nil
        }
        return Int(line.dropFirst(prefix.count))
    }

    static func jsonString(_ value: String) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    static func execPermissionApprovalFeatures() -> FeatureStates {
        var features = FeatureStates.withDefaults()
        features.set(.execPermissionApprovals, enabled: true)
        return features
    }

    static func allowPermissionRequestHook() throws -> ConfiguredHookHandler {
        ConfiguredHookHandler(
            eventName: .permissionRequest,
            matcher: "Bash",
            command: #"printf %s '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'"#,
            timeoutSec: 5,
            sourcePath: try AbsolutePath(absolutePath: "/tmp/hooks.json"),
            displayOrder: 0
        )
    }

    static func executeGenericFunctionForHookLog(
        name: String,
        arguments: String,
        log: URL,
        temp: NonInteractiveExecTemporaryDirectory
    ) async throws -> NonInteractiveExec.FunctionCallExecutionResult {
        await NonInteractiveExec.executeFunctionCallWithHooks(
            .functionCall(name: name, arguments: arguments, callID: "call-\(name)"),
            handlers: [
                ConfiguredHookHandler(
                    eventName: .preToolUse,
                    matcher: name,
                    command: "cat > \(shellSingleQuote(log.path)); printf '{}'",
                    timeoutSec: 5,
                    sourcePath: try AbsolutePath(absolutePath: "/tmp/hooks.json"),
                    displayOrder: 0
                )
            ],
            conversationID: ConversationId(),
            turnID: "turn-1",
            cwd: temp.url,
            model: "gpt-test",
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: ["PATH": "/bin:/usr/bin", "HOME": temp.url.path]
        )
    }

    @discardableResult
    static func writeTinyPNG(to url: URL) throws -> Data {
        let bytes = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="))
        try bytes.write(to: url)
        return bytes
    }
}

private actor NonInteractiveThreadRecorder {
    private var recordedThreads: [ThreadId] = []

    func append(_ threadID: ThreadId) {
        recordedThreads.append(threadID)
    }

    func values() -> [ThreadId] {
        recordedThreads
    }
}

private actor NonInteractiveAgentSpawnRecorder {
    private var recordedRequests: [AgentJobWorkerSpawnRequest] = []
    private var results: [AgentJobWorkerSpawnResult]

    init(results: [AgentJobWorkerSpawnResult]) {
        self.results = results
    }

    func spawn(_ request: AgentJobWorkerSpawnRequest) -> AgentJobWorkerSpawnResult {
        recordedRequests.append(request)
        guard !results.isEmpty else {
            return .failed("missing test spawn result")
        }
        return results.removeFirst()
    }

    func requests() -> [AgentJobWorkerSpawnRequest] {
        recordedRequests
    }

    func jobIDs() -> [String] {
        recordedRequests.map(\.jobID)
    }
}

private actor NonInteractiveAgentStatusStore {
    private var statuses: [ThreadId: AgentStatus]

    init(statuses: [ThreadId: AgentStatus]) {
        self.statuses = statuses
    }

    func set(_ status: AgentStatus, for threadID: ThreadId) {
        statuses[threadID] = status
    }

    func status(for threadID: ThreadId) -> AgentStatus {
        statuses[threadID] ?? .running
    }
}

private actor ToolCallCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}

private actor ExecLoopScript {
    private var calls = 0
    private var recordedPrompts: [Prompt] = []
    private let modelsETags: [String]

    init(modelsETags: [String] = []) {
        self.modelsETags = modelsETags
    }

    func next(_ prompt: Prompt) -> ResponseEventResults {
        calls += 1
        recordedPrompts.append(prompt)

        if calls == 1 {
            var events = modelsETags.prefix(1).map { Result<ResponseEvent, APIError>.success(.modelsETag($0)) }
            events.append(contentsOf: [
                .success(.outputItemDone(.functionCall(
                    name: "shell_command",
                    arguments: #"{"command":"echo hi"}"#,
                    callID: "call-1"
                ))),
                .success(.completed(responseID: "resp-1", tokenUsage: nil))
            ])
            return events
        }

        var events = modelsETags.dropFirst().prefix(1).map { Result<ResponseEvent, APIError>.success(.modelsETag($0)) }
        events.append(contentsOf: [
            .success(.outputItemDone(.message(role: "assistant", content: [.outputText(text: "done")]))),
            .success(.completed(responseID: "resp-2", tokenUsage: nil))
        ])
        return events
    }

    func prompts() -> [Prompt] {
        recordedPrompts
    }
}

private actor RegisteredToolLoopScript {
    private var calls = 0
    private var recordedPrompts: [Prompt] = []
    private let toolCall: ResponseItem
    private let finalMessage: ResponseItem

    init(toolCall: ResponseItem, finalMessage: ResponseItem) {
        self.toolCall = toolCall
        self.finalMessage = finalMessage
    }

    func next(_ prompt: Prompt) -> ResponseEventResults {
        calls += 1
        recordedPrompts.append(prompt)

        if calls == 1 {
            return [
                .success(.outputItemDone(toolCall)),
                .success(.completed(responseID: "resp-registered-1", tokenUsage: nil))
            ]
        }

        return [
            .success(.outputItemDone(finalMessage)),
            .success(.completed(responseID: "resp-registered-2", tokenUsage: nil))
        ]
    }

    func prompts() -> [Prompt] {
        recordedPrompts
    }
}

private actor RegisteredFunctionToolHandler {
    private let output: ResponseItem
    private var handledCalls: [ResponseItem] = []

    init(output: ResponseItem) {
        self.output = output
    }

    func execute(_ item: ResponseItem) -> ResponseItem {
        handledCalls.append(item)
        return output
    }

    func calls() -> [ResponseItem] {
        handledCalls
    }
}

private actor ModelsETagCapture {
    private var etags: [String] = []

    func append(_ etag: String) {
        etags.append(etag)
    }

    func values() -> [String] {
        etags
    }
}

private actor EndTurnFalseLoopScript {
    private var calls = 0
    private var recordedPrompts: [Prompt] = []

    func next(_ prompt: Prompt) -> ResponseEventResults {
        calls += 1
        recordedPrompts.append(prompt)

        if calls == 1 {
            return [
                .success(.outputItemDone(.message(role: "assistant", content: [
                    .outputText(text: "still working")
                ]))),
                .success(.completed(responseID: "resp-1", tokenUsage: nil, endTurn: false))
            ]
        }

        return [
            .success(.outputItemDone(.message(role: "assistant", content: [
                .outputText(text: "done")
            ]))),
            .success(.completed(responseID: "resp-2", tokenUsage: nil))
        ]
    }

    func prompts() -> [Prompt] {
        recordedPrompts
    }
}

private actor CustomToolLoopScript {
    private var calls = 0
    private var recordedPrompts: [Prompt] = []

    func next(_ prompt: Prompt) -> ResponseEventResults {
        calls += 1
        recordedPrompts.append(prompt)

        if calls == 1 {
            return [
                .success(.outputItemDone(.customToolCall(
                    callID: "custom-1",
                    name: "apply_patch",
                    input: "*** Begin Patch\n*** End Patch"
                ))),
                .success(.completed(responseID: "resp-1", tokenUsage: nil))
            ]
        }

        return [
            .success(.outputItemDone(.message(role: "assistant", content: [.outputText(text: "done")]))),
            .success(.completed(responseID: "resp-2", tokenUsage: nil))
        ]
    }

    func prompts() -> [Prompt] {
        recordedPrompts
    }
}

private actor StreamingApplyPatchToolLoopScript {
    private var calls = 0

    func next(_ prompt: Prompt) -> ResponseEventResults {
        calls += 1

        if calls == 1 {
            return [
                .success(.outputItemAdded(.customToolCall(
                    callID: "custom-1",
                    name: "apply_patch",
                    input: ""
                ))),
                .success(.toolCallInputDelta(itemID: "item-1", callID: "other-call", delta: "*** ignored\n")),
                .success(.toolCallInputDelta(itemID: "item-1", callID: "custom-1", delta: "*** Begin Patch\n")),
                .success(.toolCallInputDelta(itemID: "item-1", callID: nil, delta: "*** Add File: hello.txt\n+hello")),
                .success(.toolCallInputDelta(itemID: "item-1", callID: "custom-1", delta: "\n+world")),
                .success(.toolCallInputDelta(itemID: "item-1", callID: "custom-1", delta: "\n*** End Patch")),
                .success(.outputItemDone(.customToolCall(
                    callID: "custom-1",
                    name: "apply_patch",
                    input: "*** Begin Patch\n*** Add File: hello.txt\n+hello\n+world\n*** End Patch"
                ))),
                .success(.completed(responseID: "resp-1", tokenUsage: nil))
            ]
        }

        return [
            .success(.outputItemDone(.message(role: "assistant", content: [.outputText(text: "done")]))),
            .success(.completed(responseID: "resp-2", tokenUsage: nil))
        ]
    }
}

private actor ToolSearchLoopScript {
    private var calls = 0
    private var recordedPrompts: [Prompt] = []

    func next(_ prompt: Prompt) -> ResponseEventResults {
        calls += 1
        recordedPrompts.append(prompt)

        if calls == 1 {
            return [
                .success(.outputItemDone(.toolSearchCall(
                    callID: "search-1",
                    execution: "client",
                    arguments: .object(["query": .string("calendar")])
                ))),
                .success(.completed(responseID: "resp-1", tokenUsage: nil))
            ]
        }

        return [
            .success(.outputItemDone(.message(role: "assistant", content: [.outputText(text: "done")]))),
            .success(.completed(responseID: "resp-2", tokenUsage: nil))
        ]
    }

    func prompts() -> [Prompt] {
        recordedPrompts
    }
}

private actor StopHookLoopScript {
    private let messages: [String]
    private var calls = 0
    private var recordedPrompts: [Prompt] = []

    init(messages: [String]) {
        self.messages = messages
    }

    func next(_ prompt: Prompt) -> ResponseEventResults {
        recordedPrompts.append(prompt)
        let index = min(calls, messages.count - 1)
        calls += 1
        return [
            .success(.outputItemDone(.message(role: "assistant", content: [.outputText(text: messages[index])]))),
            .success(.completed(responseID: "resp-\(calls)", tokenUsage: nil))
        ]
    }

    func prompts() -> [Prompt] {
        recordedPrompts
    }
}

private func hookInputObject(at url: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: url)
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func shellSingleQuote(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
}

private final class NonInteractiveExecTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-swift-noninteractive-exec-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

private actor NonInteractiveExecScriptedExecServerClientTransport: ExecServerClientTransport {
    typealias Handler = @Sendable (ExecServerJSONRPCMessage) async throws -> ExecServerJSONRPCMessage?

    private let handler: Handler
    private var messages: [ExecServerJSONRPCMessage] = []

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func send(_ message: ExecServerJSONRPCMessage) async throws -> ExecServerJSONRPCMessage? {
        messages.append(message)
        return try await handler(message)
    }

    func snapshot() -> [ExecServerJSONRPCMessage] {
        messages
    }
}

private extension JSONValue {
    subscript(key: String) -> JSONValue? {
        guard case let .object(object) = self else {
            return nil
        }
        return object[key]
    }
}
