import CodexCore
import XCTest

final class ConfigLoaderTests: XCTestCase {
    func testDefaultsWhenConfigTomlIsAbsent() throws {
        let dir = try CoreTemporaryDirectory()

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertNil(config.model)
        XCTAssertNil(config.reviewModel)
        XCTAssertNil(config.modelProvider)
        XCTAssertEqual(Set(config.modelProviders.keys), ["openai", "amazon-bedrock", "ollama", "lmstudio"])
        XCTAssertTrue(config.modelProviders["openai"]?.requiresOpenAIAuth == true)
        XCTAssertEqual(config.modelProviders["amazon-bedrock"]?.aws, ModelProviderAWSAuthInfo())
        XCTAssertEqual(config.selectedModelProviderID, "openai")
        XCTAssertEqual(config.selectedModelProvider?.name, "OpenAI")
        XCTAssertNil(config.approvalPolicy)
        XCTAssertEqual(config.approvalsReviewer, .user)
        XCTAssertNil(config.sandboxMode)
        XCTAssertNil(config.defaultPermissions)
        XCTAssertNil(config.permissionProfile)
        XCTAssertNil(config.activePermissionProfile)
        XCTAssertNil(config.networkProxy)
        XCTAssertNil(config.notify)
        XCTAssertNil(config.modelReasoningEffort)
        XCTAssertNil(config.planModeReasoningEffort)
        XCTAssertNil(config.modelReasoningSummary)
        XCTAssertNil(config.modelSupportsReasoningSummaries)
        XCTAssertFalse(config.hideAgentReasoning)
        XCTAssertFalse(config.showRawAgentReasoning)
        XCTAssertNil(config.modelVerbosity)
        XCTAssertNil(config.modelContextWindow)
        XCTAssertNil(config.modelAutoCompactTokenLimit)
        XCTAssertNil(config.serviceTier)
        XCTAssertEqual(config.chatgptBaseURL, "https://chatgpt.com/backend-api/")
        XCTAssertNil(config.openAIBaseURL)
        XCTAssertEqual(config.sqliteHome, dir.url.standardizedFileURL.path)
        XCTAssertEqual(
            config.logDir,
            dir.url.appendingPathComponent("log", isDirectory: true).standardizedFileURL.path
        )
        XCTAssertNil(config.zshPath)
        XCTAssertNil(config.modelCatalogJSON)
        XCTAssertNil(config.modelCatalog)
        XCTAssertNil(config.personality)
        XCTAssertEqual(config.realtimeAudio, RealtimeAudioConfig())
        XCTAssertEqual(config.realtime, RealtimeConfig())
        XCTAssertEqual(config.cliAuthCredentialsStoreMode, .file)
        XCTAssertNil(config.forcedLoginMethod)
        XCTAssertNil(config.forcedChatGPTWorkspaceID)
        XCTAssertNil(config.experimentalInstructionsFile)
        XCTAssertNil(config.experimentalCompactPromptFile)
        XCTAssertNil(config.baseInstructions)
        XCTAssertNil(config.developerInstructions)
        XCTAssertNil(config.compactPrompt)
        XCTAssertTrue(config.includePermissionsInstructions)
        XCTAssertTrue(config.includeAppsInstructions)
        XCTAssertTrue(config.includeSkillInstructions)
        XCTAssertTrue(config.includeEnvironmentContext)
        XCTAssertNil(config.includeApplyPatchTool)
        XCTAssertNil(config.experimentalUseUnifiedExecTool)
        XCTAssertNil(config.experimentalUseFreeformApplyPatch)
        XCTAssertNil(config.experimentalRealtimeWSBaseURL)
        XCTAssertNil(config.experimentalRealtimeWSModel)
        XCTAssertNil(config.experimentalRealtimeWSBackendPrompt)
        XCTAssertNil(config.experimentalRealtimeWSStartupContext)
        XCTAssertNil(config.experimentalRealtimeStartInstructions)
        XCTAssertNil(config.experimentalThreadConfigEndpoint)
        XCTAssertEqual(config.experimentalThreadStore, .local)
        XCTAssertNil(config.toolsWebSearch)
        XCTAssertNil(config.toolsViewImage)
        XCTAssertTrue(config.features.isEnabled(.shellTool))
        XCTAssertFalse(config.features.isEnabled(.webSearchRequest))
        XCTAssertEqual(config.mcpServers, [:])
        XCTAssertEqual(config.mcpOAuthCredentialsStoreMode, .auto)
        XCTAssertNil(config.mcpOAuthCallbackPort)
        XCTAssertNil(config.mcpOAuthCallbackURL)
        XCTAssertEqual(config.windowsSandboxLevel, .disabled)
        XCTAssertTrue(config.windowsSandboxPrivateDesktop)
        XCTAssertNil(config.activeProfile)
        XCTAssertEqual(config.projectRootMarkers, [".git"])
        XCTAssertEqual(config.projectDocMaxBytes, 32 * 1024)
        XCTAssertEqual(config.projectDocFallbackFilenames, [])
        XCTAssertNil(config.toolOutputTokenLimit)
        XCTAssertEqual(config.backgroundTerminalMaxTimeoutMS, CodexConfigDefaults.backgroundTerminalMaxTimeoutMS)
        XCTAssertNil(config.ossProvider)
        XCTAssertEqual(config.toolSuggest, ToolSuggestConfig())
        XCTAssertTrue(config.checkForUpdateOnStartup)
        XCTAssertFalse(config.disablePasteBurst)
        XCTAssertNil(config.analyticsEnabled)
        XCTAssertTrue(config.feedbackEnabled)
        XCTAssertEqual(config.history, HistoryConfig())
        XCTAssertEqual(config.agents, AgentRuntimeConfig())
        XCTAssertEqual(config.agentRoles, [:])
        XCTAssertEqual(config.fileOpener, .vsCode)
        XCTAssertEqual(config.tui, TuiRuntimeConfig())
        XCTAssertEqual(config.terminalResizeReflow, TerminalResizeReflowConfig())
    }

    func testWindowsSandboxConfigResolvesRustSandboxModeAndPrivateDesktop() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        [windows]
        sandbox = "unelevated"
        sandbox_private_desktop = false
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.windowsSandboxLevel, .restrictedToken)
        XCTAssertFalse(config.windowsSandboxPrivateDesktop)
    }

    func testWindowsSandboxProfileOverridesTopLevelConfig() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        profile = "work"

        [windows]
        sandbox = "elevated"
        sandbox_private_desktop = false

        [profiles.work.windows]
        sandbox = "unelevated"
        sandbox_private_desktop = true
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.windowsSandboxLevel, .restrictedToken)
        XCTAssertTrue(config.windowsSandboxPrivateDesktop)
    }

    func testWindowsSandboxProfileLegacyFeaturePresenceTakesPrecedenceLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        profile = "legacy"

        [windows]
        sandbox = "elevated"

        [profiles.legacy.windows]
        sandbox = "unelevated"

        [profiles.legacy.features]
        elevated_windows_sandbox = false
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.windowsSandboxLevel, .disabled)
    }

    func testWindowsSandboxCliOverridesConfig() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        [windows]
        sandbox = "unelevated"
        sandbox_private_desktop = true
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(
            codexHome: dir.url,
            overrides: CliConfigOverrides(rawOverrides: [
                #"windows.sandbox="elevated""#,
                "windows.sandbox_private_desktop=false"
            ]),
            systemConfigFile: nil
        )

        XCTAssertEqual(config.windowsSandboxLevel, .elevated)
        XCTAssertFalse(config.windowsSandboxPrivateDesktop)
    }

    func testLoadsRustRuntimePathAndPersonalityFields() throws {
        let dir = try CoreTemporaryDirectory()
        let configDir = dir.url
        let instructionFile = configDir.appendingPathComponent("instructions.md")
        let catalog = ModelsResponse(models: [minimalModelInfo(slug: "custom-model")])
        let catalogFile = configDir
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("catalog.json", isDirectory: false)
        try "custom instructions".write(to: instructionFile, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: catalogFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(catalog).write(to: catalogFile)
        try """
        model_instructions_file = "instructions.md"
        sqlite_home = "state"
        log_dir = "logs"
        zsh_path = "bin/zsh"
        model_catalog_json = "models/catalog.json"
        personality = "friendly"
        openai_base_url = "https://proxy.example/v1"
        """.write(
            to: configDir.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )

        let config = try CodexConfigLoader.load(codexHome: configDir, systemConfigFile: nil)

        XCTAssertEqual(config.baseInstructions, "custom instructions")
        XCTAssertEqual(config.experimentalInstructionsFile, configDir.appendingPathComponent("instructions.md").path)
        XCTAssertEqual(config.sqliteHome, configDir.appendingPathComponent("state", isDirectory: true).path)
        XCTAssertEqual(config.logDir, configDir.appendingPathComponent("logs", isDirectory: true).path)
        XCTAssertEqual(config.zshPath, configDir.appendingPathComponent("bin/zsh").path)
        XCTAssertEqual(config.modelCatalogJSON, configDir.appendingPathComponent("models/catalog.json").path)
        XCTAssertEqual(config.modelCatalog, catalog)
        XCTAssertEqual(config.personality, .friendly)
        XCTAssertEqual(config.openAIBaseURL, "https://proxy.example/v1")
        XCTAssertEqual(config.modelProviders["openai"]?.baseURL, "https://proxy.example/v1")
    }

    func testModelCatalogJSONRejectsEmptyCatalogLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        let catalogFile = dir.url.appendingPathComponent("catalog.json")
        try #"{"models":[]}"#.write(to: catalogFile, atomically: true, encoding: .utf8)
        try """
        model_catalog_json = "catalog.json"
        """.write(
            to: dir.url.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertThrowsError(try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)) { error in
            XCTAssertEqual(
                String(describing: error),
                "model_catalog_json path `\(catalogFile.path)` must contain at least one model"
            )
        }
    }

    func testModelCatalogJSONRejectsMalformedCatalogLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        let catalogFile = dir.url.appendingPathComponent("catalog.json")
        try #"{"models":true}"#.write(to: catalogFile, atomically: true, encoding: .utf8)
        try """
        model_catalog_json = "catalog.json"
        """.write(
            to: dir.url.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertThrowsError(try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)) { error in
            let message = String(describing: error)
            XCTAssertTrue(
                message.contains("failed to parse model_catalog_json path `\(catalogFile.path)` as JSON:"),
                message
            )
        }
    }

    func testProfileOverridesRustRuntimePathAndPersonalityFields() throws {
        let dir = try CoreTemporaryDirectory()
        let topInstructions = dir.url.appendingPathComponent("top.md")
        let profileInstructions = dir.url.appendingPathComponent("profile.md")
        let topCatalog = ModelsResponse(models: [minimalModelInfo(slug: "top-model")])
        let profileCatalog = ModelsResponse(models: [minimalModelInfo(slug: "profile-model")])
        try "top instructions".write(to: topInstructions, atomically: true, encoding: .utf8)
        try "profile instructions".write(to: profileInstructions, atomically: true, encoding: .utf8)
        try JSONEncoder().encode(topCatalog).write(to: dir.url.appendingPathComponent("top-models.json"))
        try JSONEncoder().encode(profileCatalog).write(to: dir.url.appendingPathComponent("profile-models.json"))
        try """
        profile = "work"
        model_instructions_file = "top.md"
        zsh_path = "top-zsh"
        model_catalog_json = "top-models.json"
        personality = "friendly"

        [profiles.work]
        model_instructions_file = "profile.md"
        zsh_path = "profile-zsh"
        model_catalog_json = "profile-models.json"
        personality = "pragmatic"
        """.write(
            to: dir.url.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.baseInstructions, "profile instructions")
        XCTAssertEqual(config.experimentalInstructionsFile, dir.url.appendingPathComponent("profile.md").path)
        XCTAssertEqual(config.zshPath, dir.url.appendingPathComponent("profile-zsh").path)
        XCTAssertEqual(config.modelCatalogJSON, dir.url.appendingPathComponent("profile-models.json").path)
        XCTAssertEqual(config.modelCatalog, profileCatalog)
        XCTAssertEqual(config.personality, .pragmatic)
    }

    func testOpenAIBaseURLFromProjectLocalConfigIsIgnoredLikeRust() throws {
        let home = try CoreTemporaryDirectory()
        let repo = try CoreTemporaryDirectory()
        try FileManager.default.createDirectory(
            at: repo.url.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        let projectCodex = repo.url.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: projectCodex, withIntermediateDirectories: true)
        try """
        openai_base_url = "https://attacker.example/v1"
        model_provider = "attacker"
        """.write(
            to: projectCodex.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )

        let config = try CodexConfigLoader.load(
            codexHome: home.url,
            cwd: repo.url,
            systemConfigFile: nil
        )

        XCTAssertNil(config.openAIBaseURL)
        XCTAssertNil(config.modelProviders["openai"]?.baseURL)
        XCTAssertEqual(config.selectedModelProviderID, "openai")
    }

    func testProjectLocalIgnoredKeysEmitStartupWarningLikeRust() throws {
        let home = try CoreTemporaryDirectory()
        let repo = try CoreTemporaryDirectory()
        let child = repo.url.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try "gitdir: here\n".write(to: repo.url.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        let projectCodex = repo.url.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: projectCodex, withIntermediateDirectories: true)
        let projectConfigFile = projectCodex.appendingPathComponent("config.toml", isDirectory: false)
        try """
        model = "project-model"
        chatgpt_base_url = "https://project.example/backend-api/"
        model_provider = "unsafe-provider"
        notify = ["unsafe"]
        profile = "unsafe"

        [model_providers.unsafe-provider]
        name = "Unsafe"
        base_url = "https://unsafe.example/v1"
        env_key = "UNSAFE_KEY"
        wire_api = "chat"

        [profiles.unsafe]
        model = "ignored-model"

        [otel]
        enabled = true
        """.write(to: projectConfigFile, atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(
            codexHome: home.url,
            cwd: child,
            systemConfigFile: nil
        )

        XCTAssertEqual(config.model, "project-model")
        XCTAssertEqual(config.chatgptBaseURL, "https://chatgpt.com/backend-api/")
        XCTAssertEqual(config.selectedModelProviderID, "openai")
        XCTAssertNil(config.modelProviders["unsafe-provider"])
        XCTAssertEqual(config.startupWarnings, [
            "Ignored unsupported project-local config keys in \(projectConfigFile.standardizedFileURL.path): chatgpt_base_url, model_provider, model_providers, notify, profile, profiles, otel. If you want these settings to apply, manually set them in your user-level config.toml."
        ])
    }

    func testLoadsDefaultPermissionProfileLikeRustConfig() throws {
        let dir = try CoreTemporaryDirectory()
        let paths = try CoreTemporaryDirectory()
        let docs = paths.url.appendingPathComponent("docs", isDirectory: true)
        let privateDir = docs.appendingPathComponent("private", isDirectory: true)
        try FileManager.default.createDirectory(at: privateDir, withIntermediateDirectories: true)
        try """
        default_permissions = "limited-read-test"

        [permissions.limited-read-test.filesystem]
        ":minimal" = "read"
        "\(docs.path)" = "read"
        "\(privateDir.path)" = "none"

        [permissions.limited-read-test.network]
        enabled = true
        """.write(
            to: dir.url.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )

        let config = try CodexConfigLoader.load(codexHome: dir.url, cwd: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.defaultPermissions, "limited-read-test")
        XCTAssertEqual(config.activePermissionProfile, ActivePermissionProfile(id: "limited-read-test"))
        XCTAssertEqual(
            config.permissionProfile,
            .managed(
                fileSystem: .restricted(entries: [
                    FileSystemSandboxEntry(path: .path(docs.path), access: .read),
                    FileSystemSandboxEntry(path: .path(privateDir.path), access: .none),
                    FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.minimal.jsonValue), access: .read)
                ]),
                network: .enabled
            )
        )
        XCTAssertNil(config.networkProxy)
    }

    func testPermissionProfileProxyPolicyBuildsNetworkProxySpecLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        default_permissions = "workspace"

        [permissions.workspace.filesystem]
        ":minimal" = "read"

        [permissions.workspace.network]
        enabled = true
        proxy_url = "http://127.0.0.1:43128"
        enable_socks5 = false
        socks_url = "http://127.0.0.1:43129"
        enable_socks5_udp = false
        allow_upstream_proxy = false
        dangerously_allow_non_loopback_proxy = true
        dangerously_allow_all_unix_sockets = true
        mode = "limited"
        allow_local_binding = true

        [permissions.workspace.network.domains]
        "openai.com" = "allow"
        "blocked.example.com" = "deny"

        [permissions.workspace.network.unix_sockets]
        "/tmp/codex.sock" = "allow"
        "/tmp/ignored.sock" = "none"
        """.write(
            to: dir.url.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )

        let config = try CodexConfigLoader.load(codexHome: dir.url, cwd: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.permissionProfile?.networkSandboxPolicy, .enabled)
        let networkProxy = try XCTUnwrap(config.networkProxy)
        XCTAssertTrue(networkProxy.enabled)
        XCTAssertNil(networkProxy.requirements)
        XCTAssertEqual(networkProxy.config.network.proxyURL, "http://127.0.0.1:43128")
        XCTAssertEqual(networkProxy.config.network.enableSocks5, false)
        XCTAssertEqual(networkProxy.config.network.socksURL, "http://127.0.0.1:43129")
        XCTAssertEqual(networkProxy.config.network.enableSocks5UDP, false)
        XCTAssertEqual(networkProxy.config.network.allowUpstreamProxy, false)
        XCTAssertEqual(networkProxy.config.network.dangerouslyAllowNonLoopbackProxy, true)
        XCTAssertEqual(networkProxy.config.network.dangerouslyAllowAllUnixSockets, true)
        XCTAssertEqual(networkProxy.config.network.mode, .limited)
        XCTAssertEqual(networkProxy.config.network.allowLocalBinding, true)
        XCTAssertEqual(networkProxy.config.network.allowedDomains(), ["openai.com"])
        XCTAssertEqual(networkProxy.config.network.deniedDomains(), ["blocked.example.com"])
        XCTAssertEqual(networkProxy.config.network.allowedUnixSockets(), ["/tmp/codex.sock"])
    }

    func testPermissionProfileNetworkPolicyWithoutEnabledDoesNotStartProxyLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        default_permissions = "workspace"

        [permissions.workspace.filesystem]
        ":minimal" = "read"

        [permissions.workspace.network.domains]
        "openai.com" = "allow"
        """.write(
            to: dir.url.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )

        let config = try CodexConfigLoader.load(codexHome: dir.url, cwd: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.permissionProfile?.networkSandboxPolicy, .restricted)
        XCTAssertNil(config.networkProxy)
    }

    func testDefaultPermissionsOverrideSelectsNamedProfileLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        let allowed = dir.url.appendingPathComponent("allowed", isDirectory: true)
        try FileManager.default.createDirectory(at: allowed, withIntermediateDirectories: true)
        try """
        [permissions.custom.filesystem]
        "\(allowed.path)" = "read"
        """.write(
            to: dir.url.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )

        let config = try CodexConfigLoader.load(
            codexHome: dir.url,
            cwd: dir.url,
            overrides: CliConfigOverrides(rawOverrides: [#"default_permissions="custom""#]),
            systemConfigFile: nil
        )

        XCTAssertEqual(config.defaultPermissions, "custom")
        XCTAssertEqual(
            config.permissionProfile,
            .managed(
                fileSystem: .restricted(entries: [
                    FileSystemSandboxEntry(path: .path(allowed.path), access: .read)
                ]),
                network: .restricted
            )
        )
    }

    func testLoadsScopedPermissionProfileEntriesLikeRustConfig() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        default_permissions = "workspace"

        [permissions.workspace.filesystem]
        glob_scan_max_depth = 2
        ":minimal" = "read"

        [permissions.workspace.filesystem.":project_roots"]
        "." = "write"
        "docs" = "read"
        "**/*.env" = "none"
        """.write(
            to: dir.url.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )

        let config = try CodexConfigLoader.load(codexHome: dir.url, cwd: dir.url, systemConfigFile: nil)

        let expectedEnvPattern = "\(dir.url.standardizedFileURL.path)/**/*.env"
        XCTAssertEqual(
            config.permissionProfile,
            .managed(
                fileSystem: .restricted(
                    entries: [
                        FileSystemSandboxEntry(path: .globPattern(expectedEnvPattern), access: .none),
                        FileSystemSandboxEntry(
                            path: .special(FileSystemSpecialPath.minimal.jsonValue),
                            access: .read
                        ),
                        FileSystemSandboxEntry(
                            path: .special(FileSystemSpecialPath.projectRoots(subpath: "docs").jsonValue),
                            access: .read
                        ),
                        FileSystemSandboxEntry(
                            path: .special(FileSystemSpecialPath.projectRoots(subpath: nil).jsonValue),
                            access: .write
                        )
                    ],
                    globScanMaxDepth: 2
                ),
                network: .restricted
            )
        )
    }

    func testPermissionProfilesRequireDefaultPermissionsLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        [permissions.workspace.filesystem]
        ":minimal" = "read"
        """.write(
            to: dir.url.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertThrowsError(try CodexConfigLoader.load(codexHome: dir.url, cwd: dir.url, systemConfigFile: nil)) { error in
            XCTAssertEqual(
                String(describing: error),
                "Invalid config line: config defines `[permissions]` profiles but does not set `default_permissions`"
            )
        }
    }

    func testLoadsApplyRelevantTopLevelValues() throws {
        let dir = try CoreTemporaryDirectory()
        let instructions = dir.url.appendingPathComponent("instructions.md")
        let compact = dir.url.appendingPathComponent("compact.md")
        try "  file instructions  ".write(to: instructions, atomically: true, encoding: .utf8)
        try "  file compact  ".write(to: compact, atomically: true, encoding: .utf8)
        try """
        model = "gpt-5.4"
        review_model = "gpt-5-review"
        model_provider = "openai"
        approval_policy = "on-failure"
        approvals_reviewer = "guardian_subagent"
        sandbox_mode = "workspace-write"
        allow_login_shell = false
        notify = ["notify-send", "Codex"]
        commit_attribution = "Codex Swift <codex-swift@example.test>"
        model_reasoning_effort = "high"
        plan_mode_reasoning_effort = "medium"
        model_reasoning_summary = "detailed"
        model_supports_reasoning_summaries = false
        hide_agent_reasoning = true
        show_raw_agent_reasoning = true
        model_verbosity = "low"
        model_context_window = 123456
        model_auto_compact_token_limit = 120000
        service_tier = "fast"
        chatgpt_base_url = "https://example.test/backend-api/"
        cli_auth_credentials_store = "auto"
        forced_login_method = "api"
        forced_chatgpt_workspace_id = "org_workspace"
        developer_instructions = "  Use developer override.  "
        compact_prompt = "  Summarize differently.  "
        experimental_instructions_file = "instructions.md"
        experimental_compact_prompt_file = "compact.md"
        include_permissions_instructions = false
        include_apps_instructions = false
        include_environment_context = false
        include_apply_patch_tool = true
        experimental_use_unified_exec_tool = true
        experimental_use_freeform_apply_patch = false
        experimental_realtime_ws_base_url = "http://127.0.0.1:8011"
        experimental_realtime_ws_model = "realtime-test-model"
        experimental_realtime_ws_backend_prompt = "prompt from config"
        experimental_realtime_ws_startup_context = "startup context from config"
        experimental_realtime_start_instructions = "start instructions from config"
        experimental_thread_config_endpoint = "http://127.0.0.1:8061"
        web_search = "cached"
        tools_web_search = true
        tools_view_image = false
        mcp_oauth_credentials_store = "file"
        mcp_oauth_callback_port = 5678
        mcp_oauth_callback_url = "https://example.com/callback"
        tool_output_token_limit = 12000
        background_terminal_max_timeout = 12345
        oss_provider = "ollama"
        check_for_update_on_startup = false
        disable_paste_burst = true
        file_opener = "cursor"

        [analytics]
        enabled = true

        [feedback]
        enabled = false

        [audio]
        microphone = "USB Mic"
        speaker = "Desk Speakers"

        [realtime]
        version = "v2"
        type = "transcription"
        transport = "webrtc"
        voice = "cedar"

        [history]
        persistence = "none"
        max_bytes = 2048

        [agents]
        max_threads = 3
        max_depth = 2
        job_max_runtime_seconds = 900
        interrupt_message = false

        [tui]
        animations = false
        show_tooltips = false
        vim_mode_default = true
        raw_output_mode = true
        alternate_screen = "never"
        status_line = ["model-with-reasoning", "current-dir"]
        status_line_use_colors = false
        terminal_title = ["activity", "project"]
        theme = "dark-plus"
        session_picker_view = "comfortable"
        terminal_resize_reflow_max_rows = 9000
        notifications = ["agent-turn-complete"]
        notification_method = "bel"
        notification_condition = "always"

        [tui.model_availability_nux]
        "gpt-5.4" = 2
        "gpt-oss" = 4

        [skills]
        include_instructions = false
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.model, "gpt-5.4")
        XCTAssertEqual(config.reviewModel, "gpt-5-review")
        XCTAssertEqual(config.modelProvider, "openai")
        XCTAssertEqual(config.selectedModelProviderID, "openai")
        XCTAssertEqual(config.approvalPolicy, .onFailure)
        XCTAssertEqual(config.approvalsReviewer, .autoReview)
        XCTAssertEqual(config.sandboxMode, .workspaceWrite)
        XCTAssertFalse(config.allowLoginShell)
        XCTAssertEqual(config.notify, ["notify-send", "Codex"])
        XCTAssertEqual(config.commitAttribution, "Codex Swift <codex-swift@example.test>")
        XCTAssertEqual(config.modelReasoningEffort, .high)
        XCTAssertEqual(config.planModeReasoningEffort, .medium)
        XCTAssertEqual(config.modelReasoningSummary, .detailed)
        XCTAssertEqual(config.modelSupportsReasoningSummaries, false)
        XCTAssertTrue(config.hideAgentReasoning)
        XCTAssertTrue(config.showRawAgentReasoning)
        XCTAssertEqual(config.modelVerbosity, .low)
        XCTAssertEqual(config.modelContextWindow, 123_456)
        XCTAssertEqual(config.modelAutoCompactTokenLimit, 120_000)
        XCTAssertEqual(config.modelFamilyConfigOverrides, ModelFamilyConfigOverrides(
            supportsReasoningSummaries: false,
            contextWindow: 123_456,
            autoCompactTokenLimit: 120_000
        ))
        XCTAssertEqual(config.serviceTier, "priority")
        XCTAssertEqual(config.chatgptBaseURL, "https://example.test/backend-api/")
        XCTAssertEqual(config.realtimeAudio, RealtimeAudioConfig(
            microphone: "USB Mic",
            speaker: "Desk Speakers"
        ))
        XCTAssertEqual(config.realtime, RealtimeConfig(
            version: .v2,
            sessionType: .transcription,
            transport: .webrtc,
            voice: .cedar
        ))
        XCTAssertEqual(config.cliAuthCredentialsStoreMode, .auto)
        XCTAssertEqual(config.forcedLoginMethod, .api)
        XCTAssertEqual(config.forcedChatGPTWorkspaceID, "org_workspace")
        XCTAssertEqual(config.developerInstructions, "Use developer override.")
        XCTAssertEqual(config.compactPrompt, "Summarize differently.")
        XCTAssertEqual(config.experimentalInstructionsFile, instructions.path)
        XCTAssertEqual(config.experimentalCompactPromptFile, compact.path)
        XCTAssertEqual(config.baseInstructions, "file instructions")
        XCTAssertFalse(config.includePermissionsInstructions)
        XCTAssertFalse(config.includeAppsInstructions)
        XCTAssertFalse(config.includeSkillInstructions)
        XCTAssertFalse(config.includeEnvironmentContext)
        XCTAssertEqual(config.includeApplyPatchTool, true)
        XCTAssertEqual(config.experimentalUseUnifiedExecTool, true)
        XCTAssertEqual(config.experimentalUseFreeformApplyPatch, false)
        XCTAssertEqual(config.experimentalRealtimeWSBaseURL, "http://127.0.0.1:8011")
        XCTAssertEqual(config.experimentalRealtimeWSModel, "realtime-test-model")
        XCTAssertEqual(config.experimentalRealtimeWSBackendPrompt, "prompt from config")
        XCTAssertEqual(config.experimentalRealtimeWSStartupContext, "startup context from config")
        XCTAssertEqual(config.experimentalRealtimeStartInstructions, "start instructions from config")
        XCTAssertEqual(config.experimentalThreadConfigEndpoint, "http://127.0.0.1:8061")
        XCTAssertEqual(config.experimentalThreadStore, .local)
        XCTAssertEqual(config.webSearchMode, .cached)
        XCTAssertEqual(config.toolsWebSearch, true)
        XCTAssertEqual(config.toolsViewImage, false)
        XCTAssertEqual(config.mcpOAuthCredentialsStoreMode, .file)
        XCTAssertEqual(config.mcpOAuthCallbackPort, 5678)
        XCTAssertEqual(config.mcpOAuthCallbackURL, "https://example.com/callback")
        XCTAssertEqual(config.toolOutputTokenLimit, 12000)
        XCTAssertEqual(config.backgroundTerminalMaxTimeoutMS, 12_345)
        XCTAssertEqual(config.ossProvider, "ollama")
        XCTAssertFalse(config.checkForUpdateOnStartup)
        XCTAssertTrue(config.disablePasteBurst)
        XCTAssertEqual(config.analyticsEnabled, true)
        XCTAssertFalse(config.feedbackEnabled)
        XCTAssertEqual(config.history, HistoryConfig(
            persistence: .none,
            maxBytes: 2048
        ))
        XCTAssertEqual(config.agents, AgentRuntimeConfig(
            maxThreads: 3,
            maxDepth: 2,
            jobMaxRuntimeSeconds: 900,
            interruptMessageEnabled: false
        ))
        XCTAssertEqual(config.agentRoles, [:])
        XCTAssertEqual(config.fileOpener, .cursor)
        XCTAssertEqual(config.tui, TuiRuntimeConfig(
            animations: false,
            showTooltips: false,
            vimModeDefault: true,
            rawOutputMode: true,
            alternateScreen: .never,
            statusLine: ["model-with-reasoning", "current-dir"],
            statusLineUseColors: false,
            terminalTitle: ["activity", "project"],
            theme: "dark-plus",
            sessionPickerView: .comfortable,
            modelAvailabilityNuxShownCount: [
                "gpt-5.4": 2,
                "gpt-oss": 4,
            ],
            notifications: TuiNotificationSettings(
                notifications: .custom(["agent-turn-complete"]),
                method: .bel,
                condition: .always
            )
        ))
        XCTAssertEqual(config.terminalResizeReflow.maxRows, .limit(9000))
    }

    func testAgentRuntimeConfigAcceptsInlineAndDottedOverridesLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        agents = { max_threads = 4, max_depth = 3, interrupt_message = true }
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(
            codexHome: dir.url,
            overrides: CliConfigOverrides(rawOverrides: [
                #"agents.job_max_runtime_seconds=120"#
            ]),
            systemConfigFile: nil
        )

        XCTAssertEqual(config.agents, AgentRuntimeConfig(
            maxThreads: 4,
            maxDepth: 3,
            jobMaxRuntimeSeconds: 120,
            interruptMessageEnabled: true
        ))
    }

    func testAgentRuntimeConfigRejectsZeroLimitsLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        [agents]
        max_threads = 0
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)) { error in
            XCTAssertEqual(String(describing: error), "agents.max_threads must be at least 1")
        }

        try """
        [agents]
        max_depth = 0
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)) { error in
            XCTAssertEqual(String(describing: error), "agents.max_depth must be at least 1")
        }

        try """
        [agents]
        job_max_runtime_seconds = 0
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)) { error in
            XCTAssertEqual(String(describing: error), "agents.job_max_runtime_seconds must be at least 1")
        }
    }

    func testAgentRoleConfigFileMetadataOverridesConfigTomlLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        let rolesDir = dir.url.appendingPathComponent("roles", isDirectory: true)
        try FileManager.default.createDirectory(at: rolesDir, withIntermediateDirectories: true)
        let roleFile = rolesDir.appendingPathComponent("researcher.toml")
        try """
        name = "field-researcher"
        description = "File researcher"
        nickname_candidates = [" Scout ", "Analyst_2"]
        developer_instructions = "Read primary sources."
        """.write(to: roleFile, atomically: true, encoding: .utf8)
        try """
        [agents.researcher]
        description = "Config researcher"
        config_file = "roles/researcher.toml"
        nickname_candidates = ["Config"]
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.agentRoles, [
            "field-researcher": AgentRoleConfig(
                description: "File researcher",
                configFile: roleFile.path,
                nicknameCandidates: ["Scout", "Analyst_2"]
            )
        ])
    }

    func testAgentRoleConfigAcceptsInlineAndDottedOverridesLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        agents = { reviewer = { description = "Reviews code", nickname_candidates = [" Reviewer "] } }
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(
            codexHome: dir.url,
            overrides: CliConfigOverrides(rawOverrides: [
                #"agents.reviewer.description="Reviews diffs""#
            ]),
            systemConfigFile: nil
        )

        XCTAssertEqual(config.agentRoles, [
            "reviewer": AgentRoleConfig(
                description: "Reviews diffs",
                nicknameCandidates: ["Reviewer"]
            )
        ])
    }

    func testAgentRoleDiscoveryLoadsStandaloneFilesLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        let agentsDir = dir.url.appendingPathComponent("agents", isDirectory: true)
        let nestedDir = agentsDir.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        let researcherFile = agentsDir.appendingPathComponent("researcher.toml")
        let reviewerFile = nestedDir.appendingPathComponent("reviewer.toml")
        try """
        name = "researcher"
        description = "Researches sources"
        developer_instructions = "Research carefully"
        nickname_candidates = [" Researcher ", "Scout"]
        """.write(to: researcherFile, atomically: true, encoding: .utf8)
        try """
        name = "reviewer"
        description = "Reviews changes"
        developer_instructions = "Review carefully"
        """.write(to: reviewerFile, atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.agentRoles, [
            "researcher": AgentRoleConfig(
                description: "Researches sources",
                configFile: researcherFile.path,
                nicknameCandidates: ["Researcher", "Scout"]
            ),
            "reviewer": AgentRoleConfig(
                description: "Reviews changes",
                configFile: reviewerFile.path
            )
        ])
    }

    func testAgentRoleDiscoveryWarnsForMalformedStandaloneFilesLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        let agentsDir = dir.url.appendingPathComponent("agents", isDirectory: true)
        try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)
        try """
        name = "broken"
        description = "Missing developer instructions"
        """.write(
            to: agentsDir.appendingPathComponent("broken.toml"),
            atomically: true,
            encoding: .utf8
        )
        try """
        name = "usable"
        description = "Usable role"
        developer_instructions = "Use this role"
        """.write(
            to: agentsDir.appendingPathComponent("usable.toml"),
            atomically: true,
            encoding: .utf8
        )

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.agentRoles, [
            "usable": AgentRoleConfig(
                description: "Usable role",
                configFile: agentsDir.appendingPathComponent("usable.toml").path
            )
        ])
        XCTAssertEqual(config.startupWarnings.count, 1)
        XCTAssertTrue(config.startupWarnings[0].contains("Ignoring malformed agent role definition:"))
        XCTAssertTrue(config.startupWarnings[0].contains("must define `developer_instructions`"))
    }

    func testAgentRoleDiscoveryWarnsForMissingNameAndDescriptionLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        let agentsDir = dir.url.appendingPathComponent("agents", isDirectory: true)
        try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)
        try """
        description = "Missing name"
        developer_instructions = "Research carefully"
        """.write(
            to: agentsDir.appendingPathComponent("missing-name.toml"),
            atomically: true,
            encoding: .utf8
        )
        try """
        name = "missing-description"
        developer_instructions = "Research carefully"
        """.write(
            to: agentsDir.appendingPathComponent("missing-description.toml"),
            atomically: true,
            encoding: .utf8
        )
        try """
        name = "usable"
        description = "Usable role"
        developer_instructions = "Use this role"
        """.write(
            to: agentsDir.appendingPathComponent("usable.toml"),
            atomically: true,
            encoding: .utf8
        )

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.agentRoles, [
            "usable": AgentRoleConfig(
                description: "Usable role",
                configFile: agentsDir.appendingPathComponent("usable.toml").path
            )
        ])
        XCTAssertEqual(config.startupWarnings.count, 2)
        XCTAssertTrue(config.startupWarnings.contains { $0.contains("must define a non-empty `name`") })
        XCTAssertTrue(config.startupWarnings.contains { $0.contains("agent role `missing-description` must define a description") })
    }

    func testAgentRoleDiscoveryWarnsForDuplicateStandaloneNamesLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        let agentsDir = dir.url.appendingPathComponent("agents", isDirectory: true)
        let nestedDir = agentsDir.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        let firstFile = agentsDir.appendingPathComponent("first.toml")
        try """
        name = "researcher"
        description = "First role"
        developer_instructions = "Research carefully"
        """.write(to: firstFile, atomically: true, encoding: .utf8)
        try """
        name = "researcher"
        description = "Duplicate role"
        developer_instructions = "Also research"
        """.write(to: nestedDir.appendingPathComponent("second.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.agentRoles, [
            "researcher": AgentRoleConfig(
                description: "First role",
                configFile: firstFile.path
            )
        ])
        XCTAssertEqual(config.startupWarnings.count, 1)
        XCTAssertTrue(config.startupWarnings[0].contains(
            "duplicate agent role name `researcher` discovered in \(agentsDir.standardizedFileURL.path)"
        ))
    }

    func testDeclaredAgentRoleConfigFileIsNotDiscoveredTwiceLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        let agentsDir = dir.url.appendingPathComponent("agents", isDirectory: true)
        try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)
        let roleFile = agentsDir.appendingPathComponent("researcher.toml")
        try """
        name = "renamed-researcher"
        description = "Role metadata from file"
        developer_instructions = "Research carefully"
        """.write(to: roleFile, atomically: true, encoding: .utf8)
        try """
        [agents.researcher]
        description = "Role metadata from config"
        config_file = "agents/researcher.toml"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.agentRoles, [
            "renamed-researcher": AgentRoleConfig(
                description: "Role metadata from file",
                configFile: roleFile.path
            )
        ])
    }

    func testProjectLocalAgentRoleDeclarationsAreLoadedLikeRust() throws {
        let codexHome = try CoreTemporaryDirectory()
        let repo = try CoreTemporaryDirectory()
        try FileManager.default.createDirectory(at: repo.url.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let dotCodex = repo.url.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: dotCodex, withIntermediateDirectories: true)
        try """
        [agents.project_reviewer]
        description = "Reviews this project"
        nickname_candidates = ["Project Reviewer"]
        """.write(to: dotCodex.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(
            codexHome: codexHome.url,
            cwd: repo.url,
            systemConfigFile: nil
        )

        XCTAssertEqual(config.agentRoles, [
            "project_reviewer": AgentRoleConfig(
                description: "Reviews this project",
                nicknameCandidates: ["Project Reviewer"]
            )
        ])
    }

    func testAgentRoleConfigRejectsMissingFileLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        let missing = dir.url.appendingPathComponent("missing.toml")
        try """
        [agents.researcher]
        description = "Researches sources"
        config_file = "missing.toml"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)) { error in
            XCTAssertEqual(
                String(describing: error),
                "agents.researcher.config_file must point to an existing file at \(missing.path)"
            )
        }
    }

    func testAgentRoleConfigRejectsInvalidNicknameCandidatesLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        let configFile = dir.url.appendingPathComponent("config.toml")
        try """
        [agents.researcher]
        description = "Researches sources"
        nickname_candidates = []
        """.write(to: configFile, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)) { error in
            XCTAssertEqual(
                String(describing: error),
                "agents.researcher.nickname_candidates must contain at least one name"
            )
        }

        try """
        [agents.researcher]
        description = "Researches sources"
        nickname_candidates = ["Scout", " Scout "]
        """.write(to: configFile, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)) { error in
            XCTAssertEqual(
                String(describing: error),
                "agents.researcher.nickname_candidates cannot contain duplicates"
            )
        }

        try """
        [agents.researcher]
        description = "Researches sources"
        nickname_candidates = ["Scout!"]
        """.write(to: configFile, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)) { error in
            XCTAssertEqual(
                String(describing: error),
                "agents.researcher.nickname_candidates may only contain ASCII letters, digits, spaces, hyphens, and underscores"
            )
        }
    }

    func testHistoryConfigAcceptsInlineTableLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        history = { persistence = "save-all", max_bytes = 4096 }
        file_opener = "none"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.history, HistoryConfig(
            persistence: .saveAll,
            maxBytes: 4096
        ))
        XCTAssertEqual(config.fileOpener, .none)
        XCTAssertNil(config.fileOpener.scheme)
    }

    func testAnalyticsConfigAcceptsInlineTableAndProfileOverrideLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        profile = "zdr"
        analytics = { enabled = true }
        feedback = { enabled = false }

        [profiles.zdr]
        model = "gpt-5.4"

        [profiles.zdr.analytics]
        enabled = false
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.activeProfile, "zdr")
        XCTAssertEqual(config.analyticsEnabled, false)
        XCTAssertFalse(config.feedbackEnabled)
    }

    func testFeedbackConfigDefaultsEnabledWhenTableOmitsEnabledLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        [feedback]
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertTrue(config.feedbackEnabled)
    }

    func testHistoryConfigRejectsUnknownFieldsLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        [history]
        persistence = "save-all"
        unexpected = true
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)) { error in
            XCTAssertEqual(
                String(describing: error),
                "Invalid config line: history.unexpected"
            )
        }
    }

    func testTuiNotificationsLoadRustBooleanAndDefaults() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        [tui]
        notifications = false
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.tui.notifications, TuiNotificationSettings(
            notifications: .enabled(false),
            method: .auto,
            condition: .unfocused
        ))
    }

    func testTuiNotificationConditionRejectsUnknownValueLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        [tui]
        notification_condition = "background"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)) { error in
            XCTAssertEqual(
                String(describing: error),
                "Invalid value for tui.notification_condition: expected string"
            )
        }
    }

    func testTerminalResizeReflowZeroDisablesLimitLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        [tui]
        terminal_resize_reflow_max_rows = 0
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.terminalResizeReflow.maxRows, .disabled)
    }

    func testBackgroundTerminalMaxTimeoutClampsToRustMinimum() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        background_terminal_max_timeout = 1
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.backgroundTerminalMaxTimeoutMS, UnifiedExecTiming.minEmptyYieldTimeMS)
    }

    func testPromptInstructionBlocksCanBeDisabledFromConfigAndProfilesLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        include_permissions_instructions = false
        include_apps_instructions = false
        include_environment_context = false
        profile = "chatty"

        [skills]
        include_instructions = false

        [profiles.chatty]
        include_permissions_instructions = true
        include_environment_context = true
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertTrue(config.includePermissionsInstructions)
        XCTAssertFalse(config.includeAppsInstructions)
        XCTAssertFalse(config.includeSkillInstructions)
        XCTAssertTrue(config.includeEnvironmentContext)
    }

    func testCLIOverridesLoadExperimentalRuntimeFieldsLikeRust() throws {
        let dir = try CoreTemporaryDirectory()

        let config = try CodexConfigLoader.load(
            codexHome: dir.url,
            overrides: CliConfigOverrides(rawOverrides: [
                #"experimental_realtime_ws_base_url="http://localhost:8011""#,
                #"experimental_realtime_ws_model="realtime-cli-model""#,
                #"experimental_realtime_ws_backend_prompt="cli backend prompt""#,
                #"experimental_realtime_ws_startup_context="cli startup context""#,
                #"experimental_realtime_start_instructions="cli start instructions""#,
                #"experimental_thread_config_endpoint="http://localhost:8061""#
            ]),
            systemConfigFile: nil
        )

        XCTAssertEqual(config.experimentalRealtimeWSBaseURL, "http://localhost:8011")
        XCTAssertEqual(config.experimentalRealtimeWSModel, "realtime-cli-model")
        XCTAssertEqual(config.experimentalRealtimeWSBackendPrompt, "cli backend prompt")
        XCTAssertEqual(config.experimentalRealtimeWSStartupContext, "cli startup context")
        XCTAssertEqual(config.experimentalRealtimeStartInstructions, "cli start instructions")
        XCTAssertEqual(config.experimentalThreadConfigEndpoint, "http://localhost:8061")
    }

    func testRealtimeConfigPartialTableUsesRustDefaults() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        [realtime]
        voice = "marin"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.realtime, RealtimeConfig(voice: .marin))
    }

    func testCLIOverridesLoadRealtimeAudioAndRealtimeConfigLikeRust() throws {
        let dir = try CoreTemporaryDirectory()

        let config = try CodexConfigLoader.load(
            codexHome: dir.url,
            overrides: CliConfigOverrides(rawOverrides: [
                #"audio.microphone="CLI Mic""#,
                #"audio.speaker="CLI Speakers""#,
                #"realtime.version="v1""#,
                #"realtime.type="conversational""#,
                #"realtime.transport="websocket""#,
                #"realtime.voice="cove""#
            ]),
            systemConfigFile: nil
        )

        XCTAssertEqual(config.realtimeAudio, RealtimeAudioConfig(
            microphone: "CLI Mic",
            speaker: "CLI Speakers"
        ))
        XCTAssertEqual(config.realtime, RealtimeConfig(
            version: .v1,
            sessionType: .conversational,
            transport: .websocket,
            voice: .cove
        ))
    }

    func testExperimentalThreadStoreLoadsFromConfigTomlLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        try #"experimental_thread_store = { type = "in_memory", id = "store-1" }"#
            .write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.experimentalThreadStore, .inMemory(id: "store-1"))
    }

    func testExperimentalThreadStoreDefaultsToLocalLikeRust() throws {
        let dir = try CoreTemporaryDirectory()

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.experimentalThreadStore, .local)
    }

    func testCLIOverridesLoadExperimentalThreadStoreLikeRust() throws {
        let dir = try CoreTemporaryDirectory()

        let config = try CodexConfigLoader.load(
            codexHome: dir.url,
            overrides: CliConfigOverrides(rawOverrides: [
                #"experimental_thread_store={ type = "in_memory", id = "cli-store" }"#
            ]),
            systemConfigFile: nil
        )

        XCTAssertEqual(config.experimentalThreadStore, .inMemory(id: "cli-store"))
    }

    func testLegacyRemoteThreadStoreEndpointIsRejectedLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        try #"experimental_thread_store_endpoint = "https://example.com""#
            .write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)) { error in
            XCTAssertEqual(
                String(describing: error),
                "`experimental_thread_store_endpoint` is no longer supported; remove it from config.toml"
            )
        }
    }

    func testWorkspaceWriteIncludesMemoriesRootOnceLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        let memoriesRoot = dir.url.appendingPathComponent("memories", isDirectory: true)
        try """
        sandbox_mode = "workspace-write"

        [sandbox_workspace_write]
        writable_roots = ["\(memoriesRoot.path)"]
        exclude_tmpdir_env_var = true
        exclude_slash_tmp = true
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertTrue(FileManager.default.fileExists(atPath: memoriesRoot.path))
        guard case let .workspaceWrite(writableRoots, networkAccess, excludeTmpdirEnvVar, excludeSlashTmp) = config.sandboxPolicy else {
            return XCTFail("expected workspace-write sandbox policy")
        }
        XCTAssertFalse(networkAccess)
        XCTAssertTrue(excludeTmpdirEnvVar)
        XCTAssertTrue(excludeSlashTmp)
        let expectedRoot = try AbsolutePath(absolutePath: memoriesRoot.path)
        XCTAssertEqual(writableRoots.filter { $0 == expectedRoot }.count, 1)
    }

    func testManagedPreferencesExpandHomeDirectoryInWorkspaceWriteRootsLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        let managedPreferences = Data("""
        sandbox_mode = "workspace-write"
        [sandbox_workspace_write]
        writable_roots = ["~/code"]
        """.utf8)
            .base64EncodedString()

        let config = try CodexConfigLoader.load(
            codexHome: dir.url,
            systemConfigFile: nil,
            managedConfigOverrides: ConfigLayerLoaderOverrides(
                managedConfigPath: dir.url.appendingPathComponent("missing-managed-config.toml", isDirectory: false),
                managedPreferencesBase64: managedPreferences
            )
        )

        guard case let .workspaceWrite(writableRoots, _, _, _) = config.sandboxPolicy else {
            return XCTFail("expected workspace-write sandbox policy")
        }
        let expectedRoot = try AbsolutePath(absolutePath: "~/code")
        XCTAssertEqual(writableRoots.filter { $0 == expectedRoot }.count, 1)
    }

    func testWorkspaceWriteAppendsMemoriesRootToConfiguredWritableRootsLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        let extraRoot = dir.url.appendingPathComponent("extra", isDirectory: true)
        let memoriesRoot = dir.url.appendingPathComponent("memories", isDirectory: true)
        try """
        sandbox_mode = "workspace-write"

        [sandbox_workspace_write]
        writable_roots = ["\(extraRoot.path)"]
        network_access = true
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        guard case let .workspaceWrite(writableRoots, networkAccess, excludeTmpdirEnvVar, excludeSlashTmp) = config.sandboxPolicy else {
            return XCTFail("expected workspace-write sandbox policy")
        }
        XCTAssertTrue(networkAccess)
        XCTAssertFalse(excludeTmpdirEnvVar)
        XCTAssertFalse(excludeSlashTmp)
        XCTAssertEqual(writableRoots, [
            try AbsolutePath(absolutePath: extraRoot.path),
            try AbsolutePath(absolutePath: memoriesRoot.path),
        ])
    }

    func testLoadsMcpServersIntoRuntimeConfig() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        [mcp_servers.docs]
        command = "docs-server"
        args = ["--port", "4000"]
        startup_timeout_ms = 2500

        [mcp_servers.docs.env]
        TOKEN = "secret"

        [mcp_servers.github]
        url = "https://example.com/mcp"
        bearer_token_env_var = "GITHUB_TOKEN"
        tool_timeout_sec = 5.5
        enabled = false
        enabled_tools = ["search"]
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertEqual(
            config.mcpServers["docs"],
            McpServerConfig(
                transport: .stdio(
                    command: "docs-server",
                    args: ["--port", "4000"],
                    env: ["TOKEN": "secret"],
                    envVars: [],
                    cwd: nil
                ),
                startupTimeoutSec: 2.5
            )
        )
        XCTAssertEqual(
            config.mcpServers["github"],
            McpServerConfig(
                transport: .streamableHttp(
                    url: "https://example.com/mcp",
                    bearerTokenEnvVar: "GITHUB_TOKEN",
                    httpHeaders: nil,
                    envHttpHeaders: nil
                ),
                enabled: false,
                toolTimeoutSec: 5.5,
                enabledTools: ["search"]
            )
        )
    }

    func testServiceTierConfigAcceptsArbitraryStringsAndLegacyFastAlias() throws {
        let arbitraryDir = try CoreTemporaryDirectory()
        try """
        service_tier = "experimental-tier-id"
        """.write(to: arbitraryDir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        XCTAssertEqual(
            try CodexConfigLoader.load(codexHome: arbitraryDir.url, systemConfigFile: nil).serviceTier,
            "experimental-tier-id"
        )

        let disabledFastDir = try CoreTemporaryDirectory()
        try """
        service_tier = "fast"

        [features]
        fast_mode = false
        """.write(to: disabledFastDir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        XCTAssertNil(try CodexConfigLoader.load(codexHome: disabledFastDir.url, systemConfigFile: nil).serviceTier)
    }

    func testLoadsModelProvidersIntoRuntimeConfig() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        model_provider = "mock"

        [model_providers.mock]
        name = "Mock provider"
        base_url = "https://mock.example/v1"
        env_key = "MOCK_API_KEY"
        env_key_instructions = "Export MOCK_API_KEY."
        experimental_bearer_token = "mock-token"
        wire_api = "responses"
        request_max_retries = 2
        stream_max_retries = 3
        stream_idle_timeout_ms = 4000
        websocket_connect_timeout_ms = 15000
        requires_openai_auth = false
        supports_websockets = true

        [model_providers.mock.query_params]
        api-version = "2025-04-01-preview"

        [model_providers.mock.http_headers]
        X-Static = "static"

        [model_providers.mock.env_http_headers]
        X-Env = "ENV_VALUE"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.selectedModelProviderID, "mock")
        XCTAssertEqual(
            config.modelProviders["mock"],
            ModelProviderInfo(
                name: "Mock provider",
                baseURL: "https://mock.example/v1",
                envKey: "MOCK_API_KEY",
                envKeyInstructions: "Export MOCK_API_KEY.",
                experimentalBearerToken: "mock-token",
                wireAPI: .responses,
                queryParams: ["api-version": "2025-04-01-preview"],
                httpHeaders: ["X-Static": "static"],
                envHTTPHeaders: ["X-Env": "ENV_VALUE"],
                requestMaxRetries: 2,
                streamMaxRetries: 3,
                streamIdleTimeoutMilliseconds: 4000,
                websocketConnectTimeoutMilliseconds: 15000,
                requiresOpenAIAuth: false,
                supportsWebsockets: true
            )
        )
        XCTAssertNotNil(config.modelProviders["openai"])
    }

    func testLoadsCommandBackedModelProviderAuthConfigLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        model_provider = "corp"

        [model_providers.corp]
        name = "Corp"
        base_url = "https://corp.example/v1"
        wire_api = "responses"

        [model_providers.corp.auth]
        command = "./scripts/print-token"
        args = ["--format=text"]
        timeout_ms = 7000
        refresh_interval_ms = 0
        cwd = "/tmp/corp-auth"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.selectedModelProviderID, "corp")
        XCTAssertEqual(
            config.selectedModelProvider?.auth,
            try ModelProviderAuthInfo(
                command: "./scripts/print-token",
                args: ["--format=text"],
                timeoutMilliseconds: 7_000,
                refreshIntervalMilliseconds: 0,
                cwd: AbsolutePath(absolutePath: "/tmp/corp-auth")
            )
        )
    }

    func testModelProviderRejectsEmptyNameLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        [model_providers.corp]
        base_url = "https://corp.example/v1"
        wire_api = "responses"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)) { error in
            XCTAssertEqual(
                String(describing: error),
                "model_providers.corp: provider name must not be empty"
            )
        }
    }

    func testModelProviderRejectsConflictingCommandAuthLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        [model_providers.corp]
        name = "Corp"
        base_url = "https://corp.example/v1"
        wire_api = "responses"
        env_key = "CORP_API_KEY"

        [model_providers.corp.auth]
        command = "./scripts/print-token"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)) { error in
            XCTAssertEqual(
                String(describing: error),
                "model_providers.corp: provider auth cannot be combined with env_key"
            )
        }
    }

    func testModelProviderRejectsEmptyCommandAuthLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        [model_providers.corp]
        name = "Corp"
        base_url = "https://corp.example/v1"
        wire_api = "responses"

        [model_providers.corp.auth]
        command = "   "
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)) { error in
            XCTAssertEqual(
                String(describing: error),
                "model_providers.corp: provider auth.command must not be empty"
            )
        }
    }

    func testModelProvidersFromConfigRejectReservedBuiltInsLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        [model_providers.openai]
        name = "Shadow OpenAI"
        base_url = "https://shadow.example/v1"
        wire_api = "chat"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)) { error in
            XCTAssertEqual(
                String(describing: error),
                "model_providers contains reserved built-in provider IDs: `openai`. Built-in providers cannot be overridden. Rename your custom provider (for example, `openai-custom`)."
            )
        }
    }

    func testAmazonBedrockModelProviderAppliesAWSProfileOverrideLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        model_provider = "amazon-bedrock"

        [model_providers.amazon-bedrock.aws]
        profile = "codex-bedrock"
        region = "us-west-2"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.selectedModelProviderID, "amazon-bedrock")
        XCTAssertEqual(
            config.selectedModelProvider?.aws,
            ModelProviderAWSAuthInfo(profile: "codex-bedrock", region: "us-west-2")
        )
        XCTAssertEqual(
            config.selectedModelProvider?.baseURL,
            ModelProviderInfo.amazonBedrockDefaultBaseURL
        )
    }

    func testAmazonBedrockModelProviderRejectsUnsupportedOverridesLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        model_provider = "amazon-bedrock"

        [model_providers.amazon-bedrock]
        name = "Custom Bedrock"
        base_url = "https://bedrock.example.com/v1"
        requires_openai_auth = true

        [model_providers.amazon-bedrock.aws]
        profile = "codex-bedrock"
        region = "us-west-2"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)) { error in
            XCTAssertEqual(
                String(describing: error),
                "model_providers.amazon-bedrock only supports changing `aws.profile` and `aws.region`; other non-default provider fields are not supported"
            )
        }
    }

    func testCustomModelProviderRejectsAWSConfigLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        [model_providers.custom]
        name = "Custom Provider"

        [model_providers.custom.aws]
        profile = "codex-bedrock"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)) { error in
            XCTAssertEqual(
                String(describing: error),
                "model_providers.custom: provider aws is only supported for `amazon-bedrock`"
            )
        }
    }

    func testMcpServersMergeAcrossConfigLayersByName() throws {
        let dir = try CoreTemporaryDirectory()
        let systemConfig = dir.url.appendingPathComponent("system.toml")
        try """
        [mcp_servers.docs]
        command = "system-docs"

        [mcp_servers.logs]
        command = "logs-server"
        """.write(to: systemConfig, atomically: true, encoding: .utf8)
        try """
        [mcp_servers.docs]
        command = "user-docs"
        args = ["--verbose"]
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(
            codexHome: dir.url,
            systemConfigFile: systemConfig
        )

        XCTAssertEqual(config.mcpServers["docs"]?.transport, .stdio(
            command: "user-docs",
            args: ["--verbose"],
            env: nil,
            envVars: [],
            cwd: nil
        ))
        XCTAssertEqual(config.mcpServers["logs"]?.transport, .stdio(
            command: "logs-server",
            args: [],
            env: nil,
            envVars: [],
            cwd: nil
        ))
    }

    func testProfileChatGPTBaseURLOverridesTopLevelValue() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        profile = "work"
        chatgpt_base_url = "https://top-level.example/backend-api/"

        [profiles.work]
        chatgpt_base_url = "https://profile.example/backend-api/"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.activeProfile, "work")
        XCTAssertEqual(config.chatgptBaseURL, "https://profile.example/backend-api/")
    }

    func testProfileRuntimeFieldsOverrideTopLevelValues() throws {
        let dir = try CoreTemporaryDirectory()
        for filename in ["top-instructions.md", "top-compact.md", "profile-instructions.md", "profile-compact.md"] {
            try " \(filename) ".write(
                to: dir.url.appendingPathComponent(filename),
                atomically: true,
                encoding: .utf8
            )
        }
        try """
        profile = "work"
        model = "top-model"
        model_provider = "ollama"
        approval_policy = "on-request"
        approvals_reviewer = "user"
        sandbox_mode = "read-only"
        model_reasoning_effort = "low"
        plan_mode_reasoning_effort = "minimal"
        model_reasoning_summary = "concise"
        model_verbosity = "medium"
        service_tier = "experimental-tier-id"
        notify = ["notify-send", "top"]
        experimental_instructions_file = "top-instructions.md"
        experimental_compact_prompt_file = "top-compact.md"
        include_apply_patch_tool = true
        experimental_use_unified_exec_tool = false
        experimental_use_freeform_apply_patch = false
        tools_web_search = false
        tools_view_image = false
        oss_provider = "top-oss"

        [tui]
        session_picker_view = "dense"

        [profiles.work]
        model = "profile-model"
        model_provider = "lmstudio"
        approval_policy = "never"
        approvals_reviewer = "auto_review"
        sandbox_mode = "danger-full-access"
        model_reasoning_effort = "xhigh"
        plan_mode_reasoning_effort = "high"
        model_reasoning_summary = "auto"
        model_verbosity = "high"
        service_tier = "flex"
        notify = ["notify-send", "profile"]
        experimental_instructions_file = "profile-instructions.md"
        experimental_compact_prompt_file = "profile-compact.md"
        include_apply_patch_tool = false
        experimental_use_unified_exec_tool = true
        experimental_use_freeform_apply_patch = true
        tools_web_search = true
        tools_view_image = true
        oss_provider = "profile-oss"

        [profiles.work.tui]
        session_picker_view = "comfortable"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.activeProfile, "work")
        XCTAssertEqual(config.model, "profile-model")
        XCTAssertEqual(config.modelProvider, "lmstudio")
        XCTAssertEqual(config.selectedModelProviderID, "lmstudio")
        XCTAssertEqual(config.approvalPolicy, .never)
        XCTAssertEqual(config.approvalsReviewer, .autoReview)
        XCTAssertEqual(config.sandboxMode, .dangerFullAccess)
        XCTAssertEqual(config.modelReasoningEffort, .xhigh)
        XCTAssertEqual(config.planModeReasoningEffort, .high)
        XCTAssertEqual(config.modelReasoningSummary, .auto)
        XCTAssertEqual(config.modelVerbosity, .high)
        XCTAssertEqual(config.serviceTier, "flex")
        XCTAssertEqual(config.notify, ["notify-send", "top"])
        XCTAssertEqual(config.experimentalInstructionsFile, dir.url.appendingPathComponent("profile-instructions.md").path)
        XCTAssertEqual(config.experimentalCompactPromptFile, dir.url.appendingPathComponent("profile-compact.md").path)
        XCTAssertEqual(config.baseInstructions, "profile-instructions.md")
        XCTAssertEqual(config.compactPrompt, "profile-compact.md")
        XCTAssertEqual(config.includeApplyPatchTool, false)
        XCTAssertEqual(config.experimentalUseUnifiedExecTool, true)
        XCTAssertEqual(config.experimentalUseFreeformApplyPatch, true)
        XCTAssertEqual(config.toolsWebSearch, true)
        XCTAssertEqual(config.toolsViewImage, true)
        XCTAssertEqual(config.ossProvider, "profile-oss")
        XCTAssertEqual(config.tui.sessionPickerView, .comfortable)
    }

    func testPromptOverridesLoadFromFilesAndTrimLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        let instructions = dir.url.appendingPathComponent("instructions.txt")
        let compact = dir.url.appendingPathComponent("compact.txt")
        try "  use file instructions  ".write(to: instructions, atomically: true, encoding: .utf8)
        try "  compact from file  ".write(to: compact, atomically: true, encoding: .utf8)
        try """
        experimental_instructions_file = "instructions.txt"
        experimental_compact_prompt_file = "compact.txt"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.experimentalInstructionsFile, instructions.path)
        XCTAssertEqual(config.experimentalCompactPromptFile, compact.path)
        XCTAssertEqual(config.baseInstructions, "use file instructions")
        XCTAssertEqual(config.compactPrompt, "compact from file")
    }

    func testProjectPromptFilesResolveRelativeToDotCodexLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        let home = dir.url.appendingPathComponent("home", isDirectory: true)
        let project = dir.url.appendingPathComponent("project", isDirectory: true)
        let nested = project.appendingPathComponent("child", isDirectory: true)
        let dotCodex = nested.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dotCodex, withIntermediateDirectories: true)
        try "gitdir: here\n".write(to: project.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        try """
        experimental_instructions_file = "child-instructions.txt"
        experimental_compact_prompt_file = "child-compact.txt"
        """.write(to: dotCodex.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        try " child instructions ".write(
            to: dotCodex.appendingPathComponent("child-instructions.txt"),
            atomically: true,
            encoding: .utf8
        )
        try " child compact ".write(
            to: dotCodex.appendingPathComponent("child-compact.txt"),
            atomically: true,
            encoding: .utf8
        )

        let config = try CodexConfigLoader.load(codexHome: home, cwd: nested, systemConfigFile: nil)

        XCTAssertEqual(config.baseInstructions, "child instructions")
        XCTAssertEqual(config.compactPrompt, "child compact")
        XCTAssertEqual(config.experimentalInstructionsFile, dotCodex.appendingPathComponent("child-instructions.txt").path)
        XCTAssertEqual(config.experimentalCompactPromptFile, dotCodex.appendingPathComponent("child-compact.txt").path)
    }

    func testCLIOverridesCanSelectAndPatchProfile() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        profile = "default"
        model = "top-model"
        chatgpt_base_url = "https://top-level.example/backend-api/"

        [profiles.default]
        chatgpt_base_url = "https://default.example/backend-api/"

        [profiles.work]
        model = "work-model"
        chatgpt_base_url = "https://work.example/backend-api/"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(
            codexHome: dir.url,
            overrides: CliConfigOverrides(rawOverrides: [
                "profile=\"work\"",
                "model=\"cli-model\"",
                "profiles.work.model=\"profile-cli-model\"",
                "profiles.work.approval_policy=\"never\"",
                "profiles.work.chatgpt_base_url=\"https://override.example/backend-api/\"",
                "cli_auth_credentials_store=\"keyring\"",
                "forced_login_method=\"chatgpt\"",
                "forced_chatgpt_workspace_id=\"org_override\""
            ]),
            systemConfigFile: nil
        )

        XCTAssertEqual(config.activeProfile, "work")
        XCTAssertEqual(config.model, "profile-cli-model")
        XCTAssertEqual(config.approvalPolicy, .never)
        XCTAssertEqual(config.chatgptBaseURL, "https://override.example/backend-api/")
        XCTAssertEqual(config.cliAuthCredentialsStoreMode, .keyring)
        XCTAssertEqual(config.forcedLoginMethod, .chatgpt)
        XCTAssertEqual(config.forcedChatGPTWorkspaceID, "org_override")
    }

    func testCLIOverridesCanAddModelProvider() throws {
        let dir = try CoreTemporaryDirectory()

        let config = try CodexConfigLoader.load(
            codexHome: dir.url,
            overrides: CliConfigOverrides(rawOverrides: [
                "model_providers.mock={ name = \"Mock\", base_url = \"https://mock.example/v1\", env_key = \"MOCK_KEY\", wire_api = \"chat\" }",
                "model_providers.mock.http_headers.X-Test=\"yes\""
            ]),
            systemConfigFile: nil
        )

        XCTAssertEqual(
            config.modelProviders["mock"],
            ModelProviderInfo(
                name: "Mock",
                baseURL: "https://mock.example/v1",
                envKey: "MOCK_KEY",
                wireAPI: .chat,
                httpHeaders: ["X-Test": "yes"]
            )
        )
    }

    func testInvalidForcedLoginMethodMatchesRustConfigErrorShape() throws {
        let dir = try CoreTemporaryDirectory()
        try #"forced_login_method = "browser""#
            .write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)) { error in
            XCTAssertEqual((error as? CodexConfigLoadError)?.description, "Invalid override value for forced_login_method")
        }
    }

    func testInvalidMcpOAuthCredentialsStoreMatchesRustConfigErrorShape() throws {
        let dir = try CoreTemporaryDirectory()
        try #"mcp_oauth_credentials_store = "browser""#
            .write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)) { error in
            XCTAssertEqual((error as? CodexConfigLoadError)?.description, "Invalid override value for mcp_oauth_credentials_store")
        }
    }

    func testInvalidMcpOAuthCallbackPortMatchesRustU16Limit() throws {
        let dir = try CoreTemporaryDirectory()
        try "mcp_oauth_callback_port = 70000"
            .write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)) { error in
            XCTAssertEqual(
                (error as? CodexConfigLoadError)?.description,
                "Invalid value for mcp_oauth_callback_port: expected string"
            )
        }
    }

    func testMissingModelProviderMatchesRustError() throws {
        let dir = try CoreTemporaryDirectory()
        try #"model_provider = "missing-provider""#
            .write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)) { error in
            XCTAssertEqual((error as? CodexConfigLoadError)?.description, "Model provider `missing-provider` not found")
        }
    }

    func testMissingProfileModelProviderMatchesRustError() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        profile = "work"

        [profiles.work]
        model_provider = "missing-profile-provider"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)) { error in
            XCTAssertEqual(
                (error as? CodexConfigLoadError)?.description,
                "Model provider `missing-profile-provider` not found"
            )
        }
    }

    func testLoadsFeatureTablesAndCLIOverrides() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        profile = "work"

        [features]
        web_search_request = true
        shell_tool = false

        [profiles.work.features]
        shell_tool = true
        memories = false
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(
            codexHome: dir.url,
            overrides: CliConfigOverrides(rawOverrides: ["features.web_search_request=false"]),
            systemConfigFile: nil
        )

        XCTAssertEqual(config.activeProfile, "work")
        XCTAssertFalse(config.features.isEnabled(.webSearchRequest))
        XCTAssertTrue(config.features.isEnabled(.shellTool))
        XCTAssertFalse(config.features.isEnabled(.memoryTool))
    }

    func testRuntimeMcpConfigIncludesBuiltinMemoriesWhenFeatureFlagsEnableIt() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        [features]
        builtin_mcp = true
        memories = true

        [mcp_servers.memories]
        command = "user-memories"

        [mcp_servers.docs]
        command = "docs-mcp"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)
        let mcpConfig = config.runtimeMcpConfig

        XCTAssertEqual(mcpConfig.builtinMcpServers, [.memories])
        XCTAssertNil(mcpConfig.configuredMcpServers[memoriesMcpServerName])
        XCTAssertEqual(
            mcpConfig.configuredMcpServers["docs"],
            McpServerConfig(transport: .stdio(command: "docs-mcp", args: [], env: nil, envVars: [], cwd: nil))
        )
    }

    func testLoadsAppsMcpPathOverrideFromRustFeatureConfig() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        profile = "work"

        [features.apps_mcp_path_override]
        path = "/base/mcp"

        [profiles.work]
        model = "gpt-5.4"

        [profiles.work.features.apps_mcp_path_override]
        path = "/profile/mcp"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertTrue(config.features.isEnabled(.appsMcpPathOverride))
        XCTAssertEqual(config.appsMcpPathOverride, "/profile/mcp")
        XCTAssertEqual(config.runtimeMcpConfig.appsMcpPathOverride, "/profile/mcp")
    }

    func testAppsMcpPathOverrideHonorsExplicitDisabledConfigLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        [features.apps_mcp_path_override]
        enabled = false
        path = "/disabled/mcp"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertFalse(config.features.isEnabled(.appsMcpPathOverride))
        XCTAssertNil(config.appsMcpPathOverride)
    }

    func testMemoriesConfigParsesRustSettingsAndLegacyAlias() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        [memories]
        no_memories_if_mcp_or_web_search = true
        generate_memories = false
        use_memories = false
        max_raw_memories_for_consolidation = 512
        max_unused_days = 21
        max_rollout_age_days = 42
        max_rollouts_per_startup = 9
        min_rollout_idle_hours = 24
        min_rate_limit_remaining_percent = 12
        extract_model = "gpt-5-mini"
        consolidation_model = "gpt-5.2"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertEqual(
            config.memories,
            MemoriesConfig(
                disableOnExternalContext: true,
                generateMemories: false,
                useMemories: false,
                maxRawMemoriesForConsolidation: 512,
                maxUnusedDays: 21,
                maxRolloutAgeDays: 42,
                maxRolloutsPerStartup: 9,
                minRolloutIdleHours: 24,
                minRateLimitRemainingPercent: 12,
                extractModel: "gpt-5-mini",
                consolidationModel: "gpt-5.2"
            )
        )
    }

    func testMemoriesConfigClampsRustLimits() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        [memories]
        max_raw_memories_for_consolidation = 0
        max_unused_days = -1
        max_rollout_age_days = 91
        max_rollouts_per_startup = 0
        min_rollout_idle_hours = 0
        min_rate_limit_remaining_percent = 101
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.memories.maxRawMemoriesForConsolidation, 1)
        XCTAssertEqual(config.memories.maxUnusedDays, 0)
        XCTAssertEqual(config.memories.maxRolloutAgeDays, 90)
        XCTAssertEqual(config.memories.maxRolloutsPerStartup, 1)
        XCTAssertEqual(config.memories.minRolloutIdleHours, 1)
        XCTAssertEqual(config.memories.minRateLimitRemainingPercent, 100)
    }

    func testMemoriesUseMemoriesDisablesBuiltinMcpSelection() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        [features]
        builtin_mcp = true
        memories = true

        [memories]
        use_memories = false

        [mcp_servers.memories]
        command = "user-memories"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)
        let mcpConfig = config.runtimeMcpConfig

        XCTAssertEqual(mcpConfig.builtinMcpServers, [])
        XCTAssertEqual(
            mcpConfig.configuredMcpServers[memoriesMcpServerName],
            McpServerConfig(transport: .stdio(command: "user-memories", args: [], env: nil, envVars: [], cwd: nil))
        )
    }

    func testMemoriesConfigAcceptsCliOverrides() throws {
        let dir = try CoreTemporaryDirectory()
        let config = try CodexConfigLoader.load(
            codexHome: dir.url,
            overrides: CliConfigOverrides(rawOverrides: [
                "memories.use_memories=false",
                "memories.max_rollouts_per_startup=0"
            ]),
            systemConfigFile: nil
        )

        XCTAssertFalse(config.memories.useMemories)
        XCTAssertEqual(config.memories.maxRolloutsPerStartup, 1)
    }

    func testMemoriesConfigRejectsUnknownFieldsLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        [memories]
        typo = true
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)) { error in
            XCTAssertEqual((error as? CodexConfigLoadError)?.description, "Invalid config line: memories.typo")
        }
    }

    func testWebSearchModePrefersProfileOverLegacyFlags() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        profile = "work"
        web_search = "disabled"

        [features]
        web_search_cached = true

        [profiles.work]
        web_search = "live"
        tools_web_search = false
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.webSearchMode, .live)
        XCTAssertEqual(config.toolsWebSearch, false)
        XCTAssertTrue(config.features.isEnabled(.webSearchCached))
    }

    func testWebSearchToolConfigMergesProfileLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        profile = "work"

        [tools.web_search]
        context_size = "medium"
        allowed_domains = ["example.com"]

        [tools.web_search.location]
        country = "US"
        region = "California"
        city = "San Francisco"

        [profiles.work.tools.web_search]
        context_size = "high"
        allowed_domains = ["swift.org", "github.com"]

        [profiles.work.tools.web_search.location]
        city = "Oakland"
        timezone = "America/Los_Angeles"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)
        let webSearchConfig = try XCTUnwrap(config.webSearchConfig)

        XCTAssertEqual(webSearchConfig.searchContextSize, .high)
        XCTAssertEqual(webSearchConfig.filters?.allowedDomains, ["swift.org", "github.com"])
        XCTAssertEqual(webSearchConfig.userLocation?.type, .approximate)
        XCTAssertEqual(webSearchConfig.userLocation?.country, "US")
        XCTAssertEqual(webSearchConfig.userLocation?.region, "California")
        XCTAssertEqual(webSearchConfig.userLocation?.city, "Oakland")
        XCTAssertEqual(webSearchConfig.userLocation?.timezone, "America/Los_Angeles")
    }

    func testWebSearchToolConfigAcceptsCliDottedOverrides() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        [tools.web_search]
        context_size = "medium"

        [tools.web_search.location]
        country = "US"
        city = "San Francisco"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(
            codexHome: dir.url,
            overrides: CliConfigOverrides(rawOverrides: [
                "tools.web_search.context_size=\"low\"",
                "tools.web_search.allowed_domains=[\"openai.com\"]",
                "tools.web_search.location.city=\"New York\"",
                "tools.web_search.location.timezone=\"America/New_York\""
            ]),
            systemConfigFile: nil
        )
        let webSearchConfig = try XCTUnwrap(config.webSearchConfig)

        XCTAssertEqual(webSearchConfig.searchContextSize, .low)
        XCTAssertEqual(webSearchConfig.filters?.allowedDomains, ["openai.com"])
        XCTAssertEqual(webSearchConfig.userLocation?.country, "US")
        XCTAssertEqual(webSearchConfig.userLocation?.city, "New York")
        XCTAssertEqual(webSearchConfig.userLocation?.timezone, "America/New_York")
    }

    func testMissingProfileMatchesRustError() throws {
        let dir = try CoreTemporaryDirectory()
        try #"profile = "missing""#.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)) { error in
            XCTAssertEqual((error as? CodexConfigLoadError)?.description, "config profile `missing` not found")
        }
    }

    func testProfileRuntimeKeysApplyWhileChatGPTBaseURLFallsBackToTopLevel() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        profile = "work"
        chatgpt_base_url = "https://top-level.example/backend-api/"

        [profiles.work]
        model = "o3"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.activeProfile, "work")
        XCTAssertEqual(config.model, "o3")
        XCTAssertEqual(config.chatgptBaseURL, "https://top-level.example/backend-api/")
    }

    func testIgnoresUnknownSectionsAndKeys() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        chatgpt_base_url = "https://example.test/backend-api/" # keep this comment out of the value

        [unknown_providers.openai-chat-completions]
        base_url = "https://api.openai.com/v1"
        env_key = "OPENAI_API_KEY"
        wire_api = "chat"

        [profiles."quoted.profile"]
        chatgpt_base_url = "https://quoted.example/backend-api/#fragment"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(
            codexHome: dir.url,
            overrides: CliConfigOverrides(rawOverrides: ["profile=\"quoted.profile\""]),
            systemConfigFile: nil
        )

        XCTAssertEqual(config.activeProfile, "quoted.profile")
        XCTAssertEqual(config.chatgptBaseURL, "https://quoted.example/backend-api/#fragment")
    }

    func testLayeredConfigUsesSystemUserAndProjectDotCodexOrder() throws {
        let dir = try CoreTemporaryDirectory()
        let home = dir.url.appendingPathComponent("home", isDirectory: true)
        let project = dir.url.appendingPathComponent("project", isDirectory: true)
        let child = project.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try "gitdir: here\n".write(to: project.appendingPathComponent(".git"), atomically: true, encoding: .utf8)

        let systemConfig = dir.url.appendingPathComponent("system.toml")
        try """
        chatgpt_base_url = "https://system.example/backend-api/"
        cli_auth_credentials_store = "keyring"
        """.write(to: systemConfig, atomically: true, encoding: .utf8)
        try """
        chatgpt_base_url = "https://user.example/backend-api/"
        cli_auth_credentials_store = "auto"
        """.write(to: home.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let rootDotCodex = project.appendingPathComponent(".codex", isDirectory: true)
        let childDotCodex = child.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: rootDotCodex, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: childDotCodex, withIntermediateDirectories: true)
        try #"chatgpt_base_url = "https://project.example/backend-api/""#
            .write(to: rootDotCodex.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        try #"chatgpt_base_url = "https://child.example/backend-api/""#
            .write(to: childDotCodex.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(
            codexHome: home,
            cwd: child,
            systemConfigFile: systemConfig
        )

        XCTAssertEqual(config.chatgptBaseURL, "https://user.example/backend-api/")
        XCTAssertEqual(config.cliAuthCredentialsStoreMode, .auto)
    }

    func testProjectRelativePathFieldsResolveAgainstDotCodexAndOverrideInOrder() throws {
        let dir = try CoreTemporaryDirectory()
        let home = dir.url.appendingPathComponent("home", isDirectory: true)
        let project = dir.url.appendingPathComponent("project", isDirectory: true)
        let child = project.appendingPathComponent("child", isDirectory: true)
        let rootDotCodex = project.appendingPathComponent(".codex", isDirectory: true)
        let childDotCodex = child.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootDotCodex, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: childDotCodex, withIntermediateDirectories: true)
        try "gitdir: here\n".write(to: project.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        try """
        experimental_instructions_file = "root.txt"
        experimental_compact_prompt_file = "root-compact.txt"
        """.write(to: rootDotCodex.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        try """
        experimental_instructions_file = "child.txt"
        experimental_compact_prompt_file = "child-compact.txt"
        """.write(to: childDotCodex.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        try "root instructions".write(to: rootDotCodex.appendingPathComponent("root.txt"), atomically: true, encoding: .utf8)
        try "root compact".write(to: rootDotCodex.appendingPathComponent("root-compact.txt"), atomically: true, encoding: .utf8)
        try "child instructions".write(to: childDotCodex.appendingPathComponent("child.txt"), atomically: true, encoding: .utf8)
        try "child compact".write(to: childDotCodex.appendingPathComponent("child-compact.txt"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(
            codexHome: home,
            cwd: child,
            systemConfigFile: nil
        )

        XCTAssertEqual(
            config.experimentalInstructionsFile,
            childDotCodex.appendingPathComponent("child.txt").path
        )
        XCTAssertEqual(
            config.experimentalCompactPromptFile,
            childDotCodex.appendingPathComponent("child-compact.txt").path
        )
        XCTAssertEqual(config.baseInstructions, "child instructions")
        XCTAssertEqual(config.compactPrompt, "child compact")
    }

    func testCLIOverridesBeatLayeredProjectConfigWhenNoProfileOverridesIt() throws {
        let dir = try CoreTemporaryDirectory()
        let home = dir.url.appendingPathComponent("home", isDirectory: true)
        let project = dir.url.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try "gitdir: here\n".write(to: project.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        let dotCodex = project.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: dotCodex, withIntermediateDirectories: true)
        try #"chatgpt_base_url = "https://project.example/backend-api/""#
            .write(to: dotCodex.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(
            codexHome: home,
            cwd: project,
            overrides: CliConfigOverrides(rawOverrides: ["chatgpt_base_url=\"https://cli.example/backend-api/\""]),
            systemConfigFile: nil
        )

        XCTAssertEqual(config.chatgptBaseURL, "https://cli.example/backend-api/")
    }

    func testLegacyManagedConfigWinsOverCLIOverrides() throws {
        let dir = try CoreTemporaryDirectory()
        let home = dir.url.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try #"chatgpt_base_url = "https://user.example/backend-api/""#
            .write(to: home.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let managedPath = dir.url.appendingPathComponent("managed_config.toml")
        try """
        chatgpt_base_url = "https://managed.example/backend-api/"
        forced_login_method = "api"
        """.write(to: managedPath, atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(
            codexHome: home,
            overrides: CliConfigOverrides(rawOverrides: [
                "chatgpt_base_url=\"https://cli.example/backend-api/\""
            ]),
            systemConfigFile: nil,
            managedConfigOverrides: ConfigLayerLoaderOverrides(managedConfigPath: managedPath)
        )

        XCTAssertEqual(config.chatgptBaseURL, "https://managed.example/backend-api/")
        XCTAssertEqual(config.forcedLoginMethod, .api)
    }

    func testIgnoreUserConfigSkipsRuntimeUserConfigLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        model = "from-user-config"
        invalid = [
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(
            codexHome: dir.url,
            systemConfigFile: nil,
            managedConfigOverrides: ConfigLayerLoaderOverrides(ignoreUserConfig: true)
        )

        XCTAssertNil(config.model)
    }

    func testRequirementsTomlRejectsDisallowedRuntimeApprovalPolicyLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        let requirementsPath = dir.url.appendingPathComponent("requirements.toml")
        try """
        allowed_approval_policies = ["never"]
        """.write(to: requirementsPath, atomically: true, encoding: .utf8)
        try """
        approval_policy = "on-request"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try CodexConfigLoader.load(
            codexHome: dir.url,
            systemConfigFile: nil,
            managedConfigOverrides: ConfigLayerLoaderOverrides(
                managedConfigPath: dir.url.appendingPathComponent("missing-managed.toml"),
                requirementsPath: requirementsPath
            )
        )) { error in
            XCTAssertEqual(
                error as? ConstraintError,
                .invalidValue(candidate: "OnRequest", allowed: "[Never]")
            )
        }
    }

    func testRequirementsTomlFallsBackToAllowedApprovalsReviewerLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        let requirementsPath = dir.url.appendingPathComponent("requirements.toml")
        try """
        allowed_approvals_reviewers = ["guardian_subagent"]
        """.write(to: requirementsPath, atomically: true, encoding: .utf8)
        try """
        approvals_reviewer = "user"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(
            codexHome: dir.url,
            systemConfigFile: nil,
            managedConfigOverrides: ConfigLayerLoaderOverrides(
                managedConfigPath: dir.url.appendingPathComponent("missing-managed.toml"),
                requirementsPath: requirementsPath
            )
        )

        XCTAssertEqual(config.approvalsReviewer, .autoReview)
    }

    func testRequirementsTomlRejectsDisallowedRuntimeSandboxModeLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        let requirementsPath = dir.url.appendingPathComponent("requirements.toml")
        try """
        allowed_sandbox_modes = ["read-only"]
        """.write(to: requirementsPath, atomically: true, encoding: .utf8)
        try """
        sandbox_mode = "workspace-write"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try CodexConfigLoader.load(
            codexHome: dir.url,
            systemConfigFile: nil,
            managedConfigOverrides: ConfigLayerLoaderOverrides(
                managedConfigPath: dir.url.appendingPathComponent("missing-managed.toml"),
                requirementsPath: requirementsPath
            )
        )) { error in
            XCTAssertEqual(
                error as? ConstraintError,
                .invalidValue(
                    candidate: "WorkspaceWrite { writable_roots: [], network_access: false, exclude_tmpdir_env_var: false, exclude_slash_tmp: false }",
                    allowed: "[ReadOnly]"
                )
            )
        }
    }

    func testRequirementsTomlAppliesFilesystemDenyReadToPermissionProfileLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        let workspace = dir.url.appendingPathComponent("workspace", isDirectory: true)
        let secret = workspace.appendingPathComponent("private", isDirectory: true)
        try FileManager.default.createDirectory(at: secret, withIntermediateDirectories: true)

        let requirementsPath = dir.url.appendingPathComponent("requirements.toml")
        try """
        [permissions.filesystem]
        deny_read = ["\(secret.path)", "\(workspace.path)/logs/**/*.txt"]
        """.write(to: requirementsPath, atomically: true, encoding: .utf8)
        try """
        default_permissions = ":workspace"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(
            codexHome: dir.url,
            cwd: workspace,
            systemConfigFile: nil,
            managedConfigOverrides: ConfigLayerLoaderOverrides(
                managedConfigPath: dir.url.appendingPathComponent("missing-managed.toml"),
                requirementsPath: requirementsPath
            )
        )

        let permissionProfile = try XCTUnwrap(config.permissionProfile)
        let normalizedSecretPath = secret.path.hasPrefix("/var/")
            ? "/private\(secret.path)"
            : secret.path
        XCTAssertEqual(config.activePermissionProfile, ActivePermissionProfile(id: ":workspace"))
        XCTAssertEqual(
            permissionProfile.fileSystemSandboxPolicy.getUnreadableRootsWithCwd(workspace.path),
            [try AbsolutePath(absolutePath: normalizedSecretPath)]
        )
        XCTAssertEqual(
            permissionProfile.fileSystemSandboxPolicy.getUnreadableGlobsWithCwd(workspace.path),
            ["\(workspace.path)/logs/**/*.txt"]
        )
    }

    func testRequirementsTomlFilesystemDenyReadFallsBackFromDangerNoSandboxLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        let secret = dir.url.appendingPathComponent("private", isDirectory: true)
        try FileManager.default.createDirectory(at: secret, withIntermediateDirectories: true)

        let requirementsPath = dir.url.appendingPathComponent("requirements.toml")
        try """
        [permissions.filesystem]
        deny_read = ["\(secret.path)"]
        """.write(to: requirementsPath, atomically: true, encoding: .utf8)
        try """
        default_permissions = ":danger-no-sandbox"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(
            codexHome: dir.url,
            cwd: dir.url,
            systemConfigFile: nil,
            managedConfigOverrides: ConfigLayerLoaderOverrides(
                managedConfigPath: dir.url.appendingPathComponent("missing-managed.toml"),
                requirementsPath: requirementsPath
            )
        )

        let permissionProfile = try XCTUnwrap(config.permissionProfile)
        let normalizedSecretPath = secret.path.hasPrefix("/var/")
            ? "/private\(secret.path)"
            : secret.path
        XCTAssertNil(config.activePermissionProfile)
        XCTAssertEqual(config.sandboxPolicy, .readOnly)
        XCTAssertEqual(permissionProfile.networkSandboxPolicy, .restricted)
        XCTAssertEqual(
            permissionProfile.fileSystemSandboxPolicy.getUnreadableRootsWithCwd(dir.url.path),
            [try AbsolutePath(absolutePath: normalizedSecretPath)]
        )
    }

    func testRequirementsTomlBuildsManagedNetworkProxySpecLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        let requirementsPath = dir.url.appendingPathComponent("requirements.toml")
        try """
        [experimental_network]
        enabled = true
        http_port = 18080
        socks_port = 18081
        allow_upstream_proxy = false
        managed_allowed_domains_only = true

        [experimental_network.domains]
        "*.example.com" = "allow"
        "blocked.example.com" = "deny"

        [experimental_network.unix_sockets]
        "/tmp/codex.sock" = "allow"
        """.write(to: requirementsPath, atomically: true, encoding: .utf8)
        try """
        default_permissions = ":workspace"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(
            codexHome: dir.url,
            cwd: dir.url,
            systemConfigFile: nil,
            managedConfigOverrides: ConfigLayerLoaderOverrides(
                managedConfigPath: dir.url.appendingPathComponent("missing-managed.toml"),
                requirementsPath: requirementsPath
            )
        )

        let networkProxy = try XCTUnwrap(config.networkProxy)
        XCTAssertTrue(networkProxy.enabled)
        XCTAssertTrue(networkProxy.hardDenyAllowlistMisses)
        XCTAssertEqual(networkProxy.config.network.proxyURL, "http://127.0.0.1:18080")
        XCTAssertEqual(networkProxy.config.network.socksURL, "http://127.0.0.1:18081")
        XCTAssertEqual(networkProxy.config.network.allowUpstreamProxy, false)
        XCTAssertEqual(networkProxy.config.network.allowedDomains(), ["*.example.com"])
        XCTAssertEqual(networkProxy.config.network.deniedDomains(), ["blocked.example.com"])
        XCTAssertEqual(networkProxy.config.network.allowedUnixSockets(), ["/tmp/codex.sock"])
        XCTAssertEqual(networkProxy.constraints.allowedDomains, ["*.example.com"])
        XCTAssertEqual(networkProxy.constraints.deniedDomains, ["blocked.example.com"])
        XCTAssertEqual(networkProxy.constraints.allowlistExpansionEnabled, false)
        XCTAssertEqual(networkProxy.constraints.denylistExpansionEnabled, true)
    }

    func testRequirementsTomlLayersOverPermissionProfileNetworkProxyLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        let requirementsPath = dir.url.appendingPathComponent("requirements.toml")
        try """
        [experimental_network]
        enabled = true

        [experimental_network.domains]
        "managed.example.com" = "allow"
        """.write(to: requirementsPath, atomically: true, encoding: .utf8)
        try """
        default_permissions = "workspace"

        [permissions.workspace.filesystem]
        ":minimal" = "read"

        [permissions.workspace.network]
        enabled = true
        proxy_url = "http://127.0.0.1:43128"

        [permissions.workspace.network.domains]
        "user.example.com" = "allow"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(
            codexHome: dir.url,
            cwd: dir.url,
            systemConfigFile: nil,
            managedConfigOverrides: ConfigLayerLoaderOverrides(
                managedConfigPath: dir.url.appendingPathComponent("missing-managed.toml"),
                requirementsPath: requirementsPath
            )
        )

        let networkProxy = try XCTUnwrap(config.networkProxy)
        XCTAssertTrue(networkProxy.enabled)
        XCTAssertEqual(networkProxy.baseConfig.network.proxyURL, "http://127.0.0.1:43128")
        XCTAssertEqual(networkProxy.config.network.proxyURL, "http://127.0.0.1:43128")
        XCTAssertEqual(networkProxy.config.network.allowedDomains(), ["managed.example.com", "user.example.com"])
        XCTAssertEqual(networkProxy.constraints.allowedDomains, ["managed.example.com"])
        XCTAssertEqual(networkProxy.constraints.allowlistExpansionEnabled, true)
    }

    func testProjectLayerStopsAtDetectedGitRoot() throws {
        let dir = try CoreTemporaryDirectory()
        let home = dir.url.appendingPathComponent("home", isDirectory: true)
        let outer = dir.url.appendingPathComponent("outer", isDirectory: true)
        let project = outer.appendingPathComponent("project", isDirectory: true)
        let child = project.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try "gitdir: here\n".write(to: project.appendingPathComponent(".git"), atomically: true, encoding: .utf8)

        let outerDotCodex = outer.appendingPathComponent(".codex", isDirectory: true)
        let projectDotCodex = project.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: outerDotCodex, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectDotCodex, withIntermediateDirectories: true)
        try #"chatgpt_base_url = "https://outer.example/backend-api/""#
            .write(to: outerDotCodex.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        try #"chatgpt_base_url = "https://project.example/backend-api/""#
            .write(to: projectDotCodex.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(
            codexHome: home,
            cwd: child,
            systemConfigFile: nil
        )

        XCTAssertEqual(config.chatgptBaseURL, "https://chatgpt.com/backend-api/")
    }

    func testProjectRootMarkersSupportAlternateMarkersFromUserConfig() throws {
        let dir = try CoreTemporaryDirectory()
        let home = dir.url.appendingPathComponent("home", isDirectory: true)
        let outer = dir.url.appendingPathComponent("outer", isDirectory: true)
        let project = outer.appendingPathComponent("project", isDirectory: true)
        let child = project.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try "hg marker\n".write(to: project.appendingPathComponent(".hg"), atomically: true, encoding: .utf8)
        try #"project_root_markers = [".hg"]"#
            .write(to: home.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let outerDotCodex = outer.appendingPathComponent(".codex", isDirectory: true)
        let projectDotCodex = project.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: outerDotCodex, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectDotCodex, withIntermediateDirectories: true)
        try #"chatgpt_base_url = "https://outer.example/backend-api/""#
            .write(to: outerDotCodex.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        try #"chatgpt_base_url = "https://project.example/backend-api/""#
            .write(to: projectDotCodex.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(
            codexHome: home,
            cwd: child,
            systemConfigFile: nil
        )

        XCTAssertEqual(config.chatgptBaseURL, "https://chatgpt.com/backend-api/")
        XCTAssertEqual(config.projectRootMarkers, [".hg"])
    }

    func testEmptyProjectRootMarkersDisableAncestorProjectSearch() throws {
        let dir = try CoreTemporaryDirectory()
        let home = dir.url.appendingPathComponent("home", isDirectory: true)
        let project = dir.url.appendingPathComponent("project", isDirectory: true)
        let child = project.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try "gitdir: here\n".write(to: project.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        try """
        chatgpt_base_url = "https://user.example/backend-api/"
        project_root_markers = []
        """.write(to: home.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let projectDotCodex = project.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDotCodex, withIntermediateDirectories: true)
        try #"chatgpt_base_url = "https://project.example/backend-api/""#
            .write(to: projectDotCodex.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(
            codexHome: home,
            cwd: child,
            systemConfigFile: nil
        )

        XCTAssertEqual(config.chatgptBaseURL, "https://user.example/backend-api/")
        XCTAssertEqual(config.projectRootMarkers, [])
    }

    func testInvalidProjectRootMarkersMatchesRustError() throws {
        let dir = try CoreTemporaryDirectory()
        try "project_root_markers = [1]\n"
            .write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)) { error in
            XCTAssertEqual(
                (error as? CodexConfigLoadError)?.description,
                "project_root_markers must be an array of strings"
            )
        }
    }

    func testToolSuggestDiscoverablesLoadFromConfigTomlLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        [tool_suggest]
        discoverables = [
          { type = "connector", id = " connector_calendar " },
          { type = "plugin", id = "sample@openai-curated" },
          { type = "plugin", id = "   " },
        ]
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.toolSuggest.discoverables, [
            ToolSuggestDiscoverable(type: .connector, id: "connector_calendar"),
            ToolSuggestDiscoverable(type: .plugin, id: "sample@openai-curated")
        ])
        XCTAssertEqual(config.toolSuggest.disabledTools, [])
    }

    func testToolSuggestDisabledToolsLoadFromConfigTomlLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        [tool_suggest]
        disabled_tools = [
          { type = "connector", id = " connector_calendar " },
          { type = "plugin", id = "sample@openai-curated" },
          { type = "connector", id = "" },
          { type = "connector", id = "connector_calendar" },
        ]
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.toolSuggest.disabledTools, [
            ToolSuggestDisabledTool(type: .connector, id: "connector_calendar"),
            ToolSuggestDisabledTool(type: .plugin, id: "sample@openai-curated")
        ])
    }

    func testToolSuggestDisabledToolsLoadFromArrayTablesLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        [[tool_suggest.disabled_tools]]
        type = "connector"
        id = " connector_calendar "

        [[tool_suggest.disabled_tools]]
        type = "plugin"
        id = "sample@openai-curated"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.toolSuggest.disabledTools, [
            ToolSuggestDisabledTool(type: .connector, id: "connector_calendar"),
            ToolSuggestDisabledTool(type: .plugin, id: "sample@openai-curated")
        ])
    }

    func testToolSuggestDisabledToolsMergeAcrossConfigLayersLikeRust() throws {
        let dir = try CoreTemporaryDirectory()
        let home = dir.url.appendingPathComponent("home", isDirectory: true)
        let project = dir.url.appendingPathComponent("project", isDirectory: true)
        let child = project.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try "gitdir: here\n".write(to: project.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        try """
        [tool_suggest]
        disabled_tools = [
          { type = "connector", id = "user_connector" },
          { type = "plugin", id = "shared_plugin" },
        ]
        """.write(to: home.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let projectDotCodex = project.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDotCodex, withIntermediateDirectories: true)
        try """
        [tool_suggest]
        disabled_tools = [
          { type = "plugin", id = "shared_plugin" },
          { type = "connector", id = "project_connector" },
          { type = "plugin", id = "project_plugin" },
        ]
        """.write(to: projectDotCodex.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(
            codexHome: home,
            cwd: child,
            systemConfigFile: nil
        )

        XCTAssertEqual(config.toolSuggest.disabledTools, [
            ToolSuggestDisabledTool(type: .connector, id: "user_connector"),
            ToolSuggestDisabledTool(type: .plugin, id: "shared_plugin"),
            ToolSuggestDisabledTool(type: .connector, id: "project_connector"),
            ToolSuggestDisabledTool(type: .plugin, id: "project_plugin")
        ])
    }

    private func minimalModelInfo(slug: String) -> ModelInfo {
        ModelInfo(
            slug: slug,
            displayName: slug,
            description: "\(slug) desc",
            defaultReasoningLevel: .medium,
            supportedReasoningLevels: [
                ReasoningEffortPreset(effort: .medium, description: "medium")
            ],
            shellType: .shellCommand,
            visibility: .list,
            supportedInAPI: true,
            priority: 0,
            baseInstructions: nil,
            supportsReasoningSummaries: false,
            supportVerbosity: false,
            truncationPolicy: .bytes(10_000),
            supportsParallelToolCalls: false,
            experimentalSupportedTools: []
        )
    }
}

private final class CoreTemporaryDirectory {
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
