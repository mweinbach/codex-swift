import CodexCore
import XCTest

final class ConfigLayerLoaderTests: XCTestCase {
    func testManagedConfigDefaultPathHonorsEnvironmentOverride() throws {
        let dir = try ConfigLayerTemporaryDirectory()
        let managedPath = dir.url.appendingPathComponent("managed_config.toml")

        XCTAssertEqual(
            CodexConfigLayerLoader.managedConfigDefaultPath(
                codexHome: dir.url,
                environment: ["CODEX_MANAGED_CONFIG_PATH": managedPath.path]
            ).path,
            managedPath.path
        )
    }

    func testReadConfigReturnsNilForMissingFileAndParsesNestedTables() throws {
        let dir = try ConfigLayerTemporaryDirectory()
        let missing = dir.url.appendingPathComponent("missing.toml")
        XCTAssertNil(try CodexConfigLayerLoader.readConfig(from: missing))

        let file = dir.url.appendingPathComponent("config.toml")
        try """
        foo = 1

        [nested]
        value = "base"
        flag = true
        """.write(to: file, atomically: true, encoding: .utf8)

        XCTAssertEqual(
            try CodexConfigLayerLoader.readConfig(from: file),
            .table([
                "foo": .integer(1),
                "nested": .table([
                    "value": .string("base"),
                    "flag": .bool(true)
                ])
            ])
        )
    }

    func testReadConfigParsesArrayOfTables() throws {
        let dir = try ConfigLayerTemporaryDirectory()
        let file = dir.url.appendingPathComponent("config.toml")
        try """
        [[skills.config]]
        path = "/tmp/skills/demo/SKILL.md"
        enabled = false

        [[skills.config]]
        name = "github:yeet"
        enabled = true
        """.write(to: file, atomically: true, encoding: .utf8)

        XCTAssertEqual(
            try CodexConfigLayerLoader.readConfig(from: file),
            .table([
                "skills": .table([
                    "config": .array([
                        .table([
                            "path": .string("/tmp/skills/demo/SKILL.md"),
                            "enabled": .bool(false)
                        ]),
                        .table([
                            "name": .string("github:yeet"),
                            "enabled": .bool(true)
                        ])
                    ])
                ])
            ])
        )
    }

    func testReadConfigParsesNestedHookArrayTables() throws {
        let dir = try ConfigLayerTemporaryDirectory()
        let file = dir.url.appendingPathComponent("config.toml")
        try """
        [hooks]

        [[hooks.PreToolUse]]
        matcher = "Bash"

        [[hooks.PreToolUse.hooks]]
        type = "command"
        command = "echo hook"
        timeout = 5
        """.write(to: file, atomically: true, encoding: .utf8)

        XCTAssertEqual(
            try CodexConfigLayerLoader.readConfig(from: file),
            .table([
                "hooks": .table([
                    "PreToolUse": .array([
                        .table([
                            "matcher": .string("Bash"),
                            "hooks": .array([
                                .table([
                                    "type": .string("command"),
                                    "command": .string("echo hook"),
                                    "timeout": .integer(5)
                                ])
                            ])
                        ])
                    ])
                ])
            ])
        )
    }

    func testReadConfigResolvesRelativePathFieldsAndPreservesUnknownFieldsLikeRust() throws {
        let dir = try ConfigLayerTemporaryDirectory()
        let file = dir.url.appendingPathComponent("config.toml")
        try """
        experimental_instructions_file = "./some_file.md"
        experimental_compact_prompt_file = "../compact.md"
        model = "gpt-1000"
        foo = "xyzzy"

        [profiles.work]
        experimental_instructions_file = "profile.md"
        """.write(to: file, atomically: true, encoding: .utf8)

        XCTAssertEqual(
            try CodexConfigLayerLoader.readConfig(from: file),
            .table([
                "experimental_instructions_file": .string(dir.url.appendingPathComponent("some_file.md").path),
                "experimental_compact_prompt_file": .string(dir.url.deletingLastPathComponent().appendingPathComponent("compact.md").path),
                "model": .string("gpt-1000"),
                "foo": .string("xyzzy"),
                "profiles": .table([
                    "work": .table([
                        "experimental_instructions_file": .string(dir.url.appendingPathComponent("profile.md").path)
                    ])
                ])
            ])
        )
    }

    func testManagedPreferencesBase64DecodesTomlTable() throws {
        let payload = """
        [nested]
        value = "managed"
        enabled = false
        """
        let encoded = Data(payload.utf8).base64EncodedString()

        XCTAssertEqual(
            try CodexConfigLayerLoader.parseManagedPreferencesBase64(encoded),
            .table([
                "nested": .table([
                    "value": .string("managed"),
                    "enabled": .bool(false)
                ])
            ])
        )
        XCTAssertNil(try CodexConfigLayerLoader.loadManagedAdminConfigLayer(overrideBase64: "   "))
    }

    func testLayerStackMergesManagedConfigAboveCLIAndUser() throws {
        let dir = try ConfigLayerTemporaryDirectory()
        let home = dir.url.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try """
        foo = 1

        [nested]
        value = "user"
        """.write(to: home.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let managedPath = dir.url.appendingPathComponent("managed_config.toml")
        try """
        foo = 2

        [nested]
        value = "managed_config"
        extra = true
        """.write(to: managedPath, atomically: true, encoding: .utf8)

        let stack = try CodexConfigLayerLoader.loadConfigLayerStack(
            codexHome: home,
            cliOverrides: CliConfigOverrides(rawOverrides: ["nested.value=\"cli\""]),
            overrides: ConfigLayerLoaderOverrides(managedConfigPath: managedPath),
            systemConfigFile: nil
        )

        XCTAssertEqual(
            stack.effectiveConfig(),
            .table([
                "foo": .integer(2),
                "nested": .table([
                    "value": .string("managed_config"),
                    "extra": .bool(true)
                ])
            ])
        )
        XCTAssertEqual(
            stack.layersHighToLow().map(\.name),
            [
                .legacyManagedConfigTomlFromFile(file: try AbsolutePath(absolutePath: managedPath.path)),
                .sessionFlags,
                .user(file: try AbsolutePath(absolutePath: home.appendingPathComponent("config.toml").path))
            ]
        )
    }

    func testIgnoreUserConfigKeepsEmptyUserLayerLikeRust() throws {
        let dir = try ConfigLayerTemporaryDirectory()
        let home = dir.url.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try """
        model = "from-user-config"
        invalid = [
        """.write(to: home.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let stack = try CodexConfigLayerLoader.loadConfigLayerStack(
            codexHome: home,
            overrides: ConfigLayerLoaderOverrides(ignoreUserConfig: true),
            systemConfigFile: nil
        )

        let userLayer = try XCTUnwrap(stack.getUserLayer())
        XCTAssertEqual(userLayer.config, .table([:]))
        guard case let .table(effectiveConfig) = stack.effectiveConfig() else {
            return XCTFail("expected table config")
        }
        XCTAssertNil(effectiveConfig["model"])
    }

    func testIgnoreRulesMarksConfigStackLikeRust() throws {
        let dir = try ConfigLayerTemporaryDirectory()
        let home = dir.url.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

        let stack = try CodexConfigLayerLoader.loadConfigLayerStack(
            codexHome: home,
            overrides: ConfigLayerLoaderOverrides(ignoreUserAndProjectExecPolicyRules: true),
            systemConfigFile: nil
        )

        XCTAssertTrue(stack.ignoreUserAndProjectExecPolicyRules)
    }

    func testManagedPreferencesTakeHighestPrecedence() throws {
        let dir = try ConfigLayerTemporaryDirectory()
        let home = dir.url.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try """
        [nested]
        value = "user"
        """.write(
            to: home.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )

        let managedPath = dir.url.appendingPathComponent("managed_config.toml")
        try """
        [nested]
        value = "managed_config"
        flag = true
        """.write(
            to: managedPath,
            atomically: true,
            encoding: .utf8
        )
        let managedPreferences = Data("""
        [nested]
        value = "mdm"
        flag = false
        """.utf8)
            .base64EncodedString()

        let stack = try CodexConfigLayerLoader.loadConfigLayerStack(
            codexHome: home,
            overrides: ConfigLayerLoaderOverrides(
                managedConfigPath: managedPath,
                managedPreferencesBase64: managedPreferences
            ),
            systemConfigFile: nil
        )

        XCTAssertEqual(
            stack.effectiveConfig(),
            .table([
                "nested": .table([
                    "value": .string("mdm"),
                    "flag": .bool(false)
                ])
            ])
        )
        XCTAssertEqual(stack.layersHighToLow().first?.name, .legacyManagedConfigTomlFromMdm)
    }

    func testThreadConfigSourceTranslatesSessionToSessionFlagsLayerLikeRust() throws {
        let provider = ModelProviderInfo(
            name: "local",
            baseURL: "http://127.0.0.1:8061/api/codex",
            wireAPI: .responses,
            streamMaxRetries: 7,
            streamIdleTimeoutMilliseconds: 123,
            requiresOpenAIAuth: false
        )

        let layer = try XCTUnwrap(ThreadConfigSource.session(SessionThreadConfig(
            modelProvider: "local",
            modelProviders: ["local": provider],
            features: ["plugins": false]
        )).configLayerEntry())

        XCTAssertEqual(layer.name, .sessionFlags)
        XCTAssertEqual(
            layer.config,
            .table([
                "model_provider": .string("local"),
                "model_providers": .table([
                    "local": .table([
                        "name": .string("local"),
                        "base_url": .string("http://127.0.0.1:8061/api/codex"),
                        "wire_api": .string("responses"),
                        "stream_max_retries": .integer(7),
                        "stream_idle_timeout_ms": .integer(123),
                        "requires_openai_auth": .bool(false)
                    ])
                ]),
                "features": .table(["plugins": .bool(false)])
            ])
        )
        XCTAssertNil(try ThreadConfigSource.user(UserThreadConfig()).configLayerEntry())
        XCTAssertNil(try ThreadConfigSource.session(SessionThreadConfig()).configLayerEntry())
    }

    func testLayerStackIncludesThreadConfigLayersAboveCLIOverridesLikeRust() throws {
        let dir = try ConfigLayerTemporaryDirectory()
        let home = dir.url.appendingPathComponent("home", isDirectory: true)
        let cwd = dir.url.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)

        let stack = try CodexConfigLayerLoader.loadConfigLayerStack(
            codexHome: home,
            cwd: cwd,
            cliOverrides: CliConfigOverrides(rawOverrides: ["features.plugins=true"]),
            threadConfigSources: [
                .session(SessionThreadConfig(features: ["plugins": false])),
                .user(UserThreadConfig())
            ],
            overrides: ConfigLayerLoaderOverrides(
                managedConfigPath: dir.url.appendingPathComponent("missing-managed.toml")
            ),
            systemConfigFile: nil
        )

        XCTAssertEqual(
            stack.effectiveConfig(),
            .table([
                "features": .table(["plugins": .bool(false)])
            ])
        )
        XCTAssertEqual(
            stack.layersHighToLow().map(\.name),
            [
                .sessionFlags,
                .sessionFlags,
                .user(file: try AbsolutePath(absolutePath: home.appendingPathComponent("config.toml").path))
            ]
        )
        XCTAssertEqual(stack.layersHighToLow().first?.config, .table([
            "features": .table(["plugins": .bool(false)])
        ]))
    }

    func testRequirementsTomlConstrainLayerStackLikeRust() throws {
        let dir = try ConfigLayerTemporaryDirectory()
        let home = dir.url.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

        let requirementsPath = dir.url.appendingPathComponent("requirements.toml")
        try """
        allowed_approval_policies = ["never", "on-request"]
        allowed_sandbox_modes = ["read-only", "workspace-write"]
        """.write(to: requirementsPath, atomically: true, encoding: .utf8)

        let stack = try CodexConfigLayerLoader.loadConfigLayerStack(
            codexHome: home,
            overrides: ConfigLayerLoaderOverrides(
                managedConfigPath: dir.url.appendingPathComponent("missing-managed.toml"),
                requirementsPath: requirementsPath
            ),
            systemConfigFile: nil
        )

        XCTAssertEqual(stack.requirements.approvalPolicy.value, .never)
        XCTAssertNoThrow(try stack.requirements.approvalPolicy.canSet(.onRequest).get())
        XCTAssertConstraintFailure(
            stack.requirements.approvalPolicy.canSet(.onFailure),
            .invalidValue(candidate: "OnFailure", allowed: "[Never, OnRequest]")
        )
        XCTAssertNoThrow(try stack.requirements.sandboxPolicy.canSet(.workspaceWrite(
            writableRoots: [try AbsolutePath(absolutePath: "/repo")],
            networkAccess: false,
            excludeTmpdirEnvVar: false,
            excludeSlashTmp: false
        )).get())
        XCTAssertConstraintFailure(
            stack.requirements.sandboxPolicy.canSet(.dangerFullAccess),
            .invalidValue(candidate: "DangerFullAccess", allowed: "[ReadOnly, WorkspaceWrite]")
        )
    }

    func testLegacyManagedConfigFillsUnsetRequirementsWithoutOverridingRequirementsToml() throws {
        let dir = try ConfigLayerTemporaryDirectory()
        let home = dir.url.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

        let requirementsPath = dir.url.appendingPathComponent("requirements.toml")
        try """
        allowed_approval_policies = ["on-request"]
        """.write(to: requirementsPath, atomically: true, encoding: .utf8)

        let managedPath = dir.url.appendingPathComponent("managed_config.toml")
        try """
        approval_policy = "never"
        sandbox_mode = "read-only"
        """.write(to: managedPath, atomically: true, encoding: .utf8)

        let stack = try CodexConfigLayerLoader.loadConfigLayerStack(
            codexHome: home,
            overrides: ConfigLayerLoaderOverrides(
                managedConfigPath: managedPath,
                requirementsPath: requirementsPath
            ),
            systemConfigFile: nil
        )

        XCTAssertEqual(stack.requirements.approvalPolicy.value, .onRequest)
        XCTAssertConstraintFailure(
            stack.requirements.approvalPolicy.canSet(.never),
            .invalidValue(candidate: "Never", allowed: "[OnRequest]")
        )
        XCTAssertNoThrow(try stack.requirements.sandboxPolicy.canSet(.readOnly).get())
        XCTAssertConstraintFailure(
            stack.requirements.sandboxPolicy.canSet(.dangerFullAccess),
            .invalidValue(candidate: "DangerFullAccess", allowed: "[ReadOnly]")
        )
    }

    func testLegacyMdmRequirementsWinOverLegacyManagedConfigFileForUnsetFields() throws {
        let dir = try ConfigLayerTemporaryDirectory()
        let home = dir.url.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

        let managedPath = dir.url.appendingPathComponent("managed_config.toml")
        try """
        approval_policy = "never"
        sandbox_mode = "danger-full-access"
        """.write(to: managedPath, atomically: true, encoding: .utf8)

        let managedPreferences = Data("""
        approval_policy = "on-request"
        sandbox_mode = "read-only"
        """.utf8)
            .base64EncodedString()

        let stack = try CodexConfigLayerLoader.loadConfigLayerStack(
            codexHome: home,
            overrides: ConfigLayerLoaderOverrides(
                managedConfigPath: managedPath,
                managedPreferencesBase64: managedPreferences
            ),
            systemConfigFile: nil
        )

        XCTAssertEqual(stack.requirements.approvalPolicy.value, .onRequest)
        XCTAssertConstraintFailure(
            stack.requirements.approvalPolicy.canSet(.never),
            .invalidValue(candidate: "Never", allowed: "[OnRequest]")
        )
        XCTAssertNoThrow(try stack.requirements.sandboxPolicy.canSet(.readOnly).get())
        XCTAssertConstraintFailure(
            stack.requirements.sandboxPolicy.canSet(.dangerFullAccess),
            .invalidValue(candidate: "DangerFullAccess", allowed: "[ReadOnly]")
        )
    }

    func testLayerStackReturnsEmptyUserLayerWhenAllFilesMissing() throws {
        let dir = try ConfigLayerTemporaryDirectory()
        let home = dir.url.appendingPathComponent("home", isDirectory: true)
        let cwd = dir.url.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)

        let stack = try CodexConfigLayerLoader.loadConfigLayerStack(
            codexHome: home,
            cwd: cwd,
            overrides: ConfigLayerLoaderOverrides(
                managedConfigPath: dir.url.appendingPathComponent("missing-managed.toml")
            ),
            systemConfigFile: nil
        )

        XCTAssertEqual(stack.effectiveConfig(), .table([:]))
        XCTAssertEqual(stack.getUserLayer()?.config, .table([:]))
        XCTAssertEqual(
            stack.getUserLayer()?.name,
            .user(file: try AbsolutePath(absolutePath: home.appendingPathComponent("config.toml").path))
        )
        XCTAssertTrue(stack.layersHighToLow().allSatisfy { layer in
            if case .project = layer.name {
                return false
            }
            return true
        })
    }

    func testProjectLayerAddedWhenDotCodexExistsWithoutConfig() throws {
        let dir = try ConfigLayerTemporaryDirectory()
        let home = dir.url.appendingPathComponent("home", isDirectory: true)
        let project = dir.url.appendingPathComponent("project", isDirectory: true)
        let nested = project.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        try "gitdir: here\n".write(to: project.appendingPathComponent(".git"), atomically: true, encoding: .utf8)

        let stack = try CodexConfigLayerLoader.loadConfigLayerStack(
            codexHome: home,
            cwd: nested,
            overrides: ConfigLayerLoaderOverrides(
                managedConfigPath: dir.url.appendingPathComponent("missing-managed.toml")
            ),
            systemConfigFile: nil
        )

        let projectLayers = stack.layersHighToLow().filter {
            if case .project = $0.name {
                return true
            }
            return false
        }
        XCTAssertEqual(projectLayers.count, 1)
        XCTAssertEqual(projectLayers.first?.config, .table([:]))
        XCTAssertEqual(
            projectLayers.first?.name,
            .project(dotCodexFolder: try AbsolutePath(absolutePath: project.appendingPathComponent(".codex").path))
        )
    }

    func testProjectLayersPreferClosestCwd() throws {
        let dir = try ConfigLayerTemporaryDirectory()
        let home = dir.url.appendingPathComponent("home", isDirectory: true)
        let project = dir.url.appendingPathComponent("project", isDirectory: true)
        let nested = project.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nested.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        try "gitdir: here\n".write(to: project.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        try #"foo = "root""#.write(
            to: project.appendingPathComponent(".codex/config.toml"),
            atomically: true,
            encoding: .utf8
        )
        try #"foo = "child""#.write(
            to: nested.appendingPathComponent(".codex/config.toml"),
            atomically: true,
            encoding: .utf8
        )

        let stack = try CodexConfigLayerLoader.loadConfigLayerStack(
            codexHome: home,
            cwd: nested,
            overrides: ConfigLayerLoaderOverrides(
                managedConfigPath: dir.url.appendingPathComponent("missing-managed.toml")
            ),
            systemConfigFile: nil
        )

        XCTAssertEqual(stack.effectiveConfig(), .table(["foo": .string("child")]))
        let projectLayerNames = stack.layersHighToLow().compactMap { layer -> AbsolutePath? in
            if case let .project(dotCodexFolder) = layer.name {
                return dotCodexFolder
            }
            return nil
        }
        XCTAssertEqual(projectLayerNames, [
            try AbsolutePath(absolutePath: nested.appendingPathComponent(".codex").path),
            try AbsolutePath(absolutePath: project.appendingPathComponent(".codex").path)
        ])
    }

    func testProjectLayersIgnoreRustDenylistedLocalKeysAndWarn() throws {
        let dir = try ConfigLayerTemporaryDirectory()
        let home = dir.url.appendingPathComponent("home", isDirectory: true)
        let project = dir.url.appendingPathComponent("project", isDirectory: true)
        let nested = project.appendingPathComponent("child", isDirectory: true)
        let dotCodex = project.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dotCodex, withIntermediateDirectories: true)
        try "gitdir: here\n".write(to: project.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        try """
        model = "project-model"
        chatgpt_base_url = "https://project.invalid/backend-api/"
        model_provider = "unsafe-provider"
        notify = ["unsafe"]
        profile = "unsafe"

        [profiles.unsafe]
        model = "ignored"

        [otel]
        enabled = true
        """.write(
            to: dotCodex.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )

        let stack = try CodexConfigLayerLoader.loadConfigLayerStack(
            codexHome: home,
            cwd: nested,
            overrides: ConfigLayerLoaderOverrides(
                managedConfigPath: dir.url.appendingPathComponent("missing-managed.toml")
            ),
            systemConfigFile: nil
        )

        XCTAssertEqual(stack.effectiveConfig(), .table([
            "model": .string("project-model")
        ]))
        XCTAssertEqual(stack.startupWarnings, [
            "Ignored unsupported project-local config keys in \(dotCodex.path)/config.toml: chatgpt_base_url, model_provider, notify, profile, profiles, otel. If you want these settings to apply, manually set them in your user-level config.toml."
        ])
    }

    func testProjectLayerSkipsCodexHomeDotCodexLikeRust() throws {
        let dir = try ConfigLayerTemporaryDirectory()
        let project = dir.url.appendingPathComponent("project", isDirectory: true)
        let codexHome = project.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try "gitdir: here\n".write(to: project.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        try """
        model = "user-home-model"
        """.write(
            to: codexHome.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )

        let stack = try CodexConfigLayerLoader.loadConfigLayerStack(
            codexHome: codexHome,
            cwd: project,
            overrides: ConfigLayerLoaderOverrides(
                managedConfigPath: dir.url.appendingPathComponent("missing-managed.toml")
            ),
            systemConfigFile: nil
        )

        XCTAssertEqual(stack.effectiveConfig(), .table([
            "model": .string("user-home-model")
        ]))
        XCTAssertEqual(
            stack.layersHighToLow().filter {
                if case .project = $0.name {
                    return true
                }
                return false
            },
            []
        )
    }

    func testProjectRootMarkersSupportAlternateMarkersLikeRust() throws {
        let dir = try ConfigLayerTemporaryDirectory()
        let home = dir.url.appendingPathComponent("home", isDirectory: true)
        let project = dir.url.appendingPathComponent("project", isDirectory: true)
        let nested = project.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nested.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        try "hg\n".write(to: project.appendingPathComponent(".hg"), atomically: true, encoding: .utf8)
        try """
        project_root_markers = [".hg"]
        """.write(
            to: home.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )
        try #"foo = "root""#.write(
            to: project.appendingPathComponent(".codex/config.toml"),
            atomically: true,
            encoding: .utf8
        )
        try #"foo = "child""#.write(
            to: nested.appendingPathComponent(".codex/config.toml"),
            atomically: true,
            encoding: .utf8
        )

        let stack = try CodexConfigLayerLoader.loadConfigLayerStack(
            codexHome: home,
            cwd: nested,
            overrides: ConfigLayerLoaderOverrides(
                managedConfigPath: dir.url.appendingPathComponent("missing-managed.toml")
            ),
            systemConfigFile: nil
        )

        XCTAssertEqual(stack.effectiveConfig(), .table([
            "project_root_markers": .array([.string(".hg")]),
            "foo": .string("child")
        ]))
        let projectLayerNames = stack.layersHighToLow().compactMap { layer -> AbsolutePath? in
            if case let .project(dotCodexFolder) = layer.name {
                return dotCodexFolder
            }
            return nil
        }
        XCTAssertEqual(projectLayerNames, [
            try AbsolutePath(absolutePath: nested.appendingPathComponent(".codex").path),
            try AbsolutePath(absolutePath: project.appendingPathComponent(".codex").path)
        ])
    }
}

private final class ConfigLayerTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

private func XCTAssertConstraintFailure(
    _ result: ConstraintResult<Void>,
    _ expected: ConstraintError,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    switch result {
    case .success:
        XCTFail("expected constraint failure", file: file, line: line)
    case let .failure(error):
        XCTAssertEqual(error, expected, file: file, line: line)
    }
}
