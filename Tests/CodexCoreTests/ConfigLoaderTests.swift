import CodexCore
import XCTest

final class ConfigLoaderTests: XCTestCase {
    func testDefaultsWhenConfigTomlIsAbsent() throws {
        let dir = try CoreTemporaryDirectory()

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertNil(config.model)
        XCTAssertNil(config.modelProvider)
        XCTAssertEqual(Set(config.modelProviders.keys), ["openai", "ollama", "lmstudio"])
        XCTAssertTrue(config.modelProviders["openai"]?.requiresOpenAIAuth == true)
        XCTAssertEqual(config.selectedModelProviderID, "openai")
        XCTAssertEqual(config.selectedModelProvider?.name, "OpenAI")
        XCTAssertNil(config.approvalPolicy)
        XCTAssertNil(config.sandboxMode)
        XCTAssertNil(config.modelReasoningEffort)
        XCTAssertNil(config.modelReasoningSummary)
        XCTAssertNil(config.modelVerbosity)
        XCTAssertEqual(config.chatgptBaseURL, "https://chatgpt.com/backend-api/")
        XCTAssertEqual(config.cliAuthCredentialsStoreMode, .file)
        XCTAssertNil(config.forcedLoginMethod)
        XCTAssertNil(config.forcedChatGPTWorkspaceID)
        XCTAssertNil(config.experimentalInstructionsFile)
        XCTAssertNil(config.experimentalCompactPromptFile)
        XCTAssertNil(config.baseInstructions)
        XCTAssertNil(config.developerInstructions)
        XCTAssertNil(config.compactPrompt)
        XCTAssertNil(config.includeApplyPatchTool)
        XCTAssertNil(config.experimentalUseUnifiedExecTool)
        XCTAssertNil(config.experimentalUseFreeformApplyPatch)
        XCTAssertNil(config.toolsWebSearch)
        XCTAssertNil(config.toolsViewImage)
        XCTAssertTrue(config.features.isEnabled(.parallel))
        XCTAssertFalse(config.features.isEnabled(.webSearchRequest))
        XCTAssertEqual(config.mcpServers, [:])
        XCTAssertEqual(config.mcpOAuthCredentialsStoreMode, .auto)
        XCTAssertNil(config.activeProfile)
        XCTAssertEqual(config.projectRootMarkers, [".git"])
        XCTAssertEqual(config.projectDocMaxBytes, 32 * 1024)
        XCTAssertEqual(config.projectDocFallbackFilenames, [])
        XCTAssertNil(config.ossProvider)
    }

    func testLoadsApplyRelevantTopLevelValues() throws {
        let dir = try CoreTemporaryDirectory()
        let instructions = dir.url.appendingPathComponent("instructions.md")
        let compact = dir.url.appendingPathComponent("compact.md")
        try "  file instructions  ".write(to: instructions, atomically: true, encoding: .utf8)
        try "  file compact  ".write(to: compact, atomically: true, encoding: .utf8)
        try """
        model = "gpt-5.4"
        model_provider = "openai"
        approval_policy = "on-failure"
        sandbox_mode = "workspace-write"
        model_reasoning_effort = "high"
        model_reasoning_summary = "detailed"
        model_verbosity = "low"
        chatgpt_base_url = "https://example.test/backend-api/"
        cli_auth_credentials_store = "auto"
        forced_login_method = "api"
        forced_chatgpt_workspace_id = "org_workspace"
        developer_instructions = "  Use developer override.  "
        compact_prompt = "  Summarize differently.  "
        experimental_instructions_file = "instructions.md"
        experimental_compact_prompt_file = "compact.md"
        include_apply_patch_tool = true
        experimental_use_unified_exec_tool = true
        experimental_use_freeform_apply_patch = false
        tools_web_search = true
        tools_view_image = false
        mcp_oauth_credentials_store = "file"
        oss_provider = "ollama"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.model, "gpt-5.4")
        XCTAssertEqual(config.modelProvider, "openai")
        XCTAssertEqual(config.selectedModelProviderID, "openai")
        XCTAssertEqual(config.approvalPolicy, .onFailure)
        XCTAssertEqual(config.sandboxMode, .workspaceWrite)
        XCTAssertEqual(config.modelReasoningEffort, .high)
        XCTAssertEqual(config.modelReasoningSummary, .detailed)
        XCTAssertEqual(config.modelVerbosity, .low)
        XCTAssertEqual(config.chatgptBaseURL, "https://example.test/backend-api/")
        XCTAssertEqual(config.cliAuthCredentialsStoreMode, .auto)
        XCTAssertEqual(config.forcedLoginMethod, .api)
        XCTAssertEqual(config.forcedChatGPTWorkspaceID, "org_workspace")
        XCTAssertEqual(config.developerInstructions, "Use developer override.")
        XCTAssertEqual(config.compactPrompt, "Summarize differently.")
        XCTAssertEqual(config.experimentalInstructionsFile, instructions.path)
        XCTAssertEqual(config.experimentalCompactPromptFile, compact.path)
        XCTAssertEqual(config.baseInstructions, "file instructions")
        XCTAssertEqual(config.includeApplyPatchTool, true)
        XCTAssertEqual(config.experimentalUseUnifiedExecTool, true)
        XCTAssertEqual(config.experimentalUseFreeformApplyPatch, false)
        XCTAssertEqual(config.toolsWebSearch, true)
        XCTAssertEqual(config.toolsViewImage, false)
        XCTAssertEqual(config.mcpOAuthCredentialsStoreMode, .file)
        XCTAssertEqual(config.ossProvider, "ollama")
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
        requires_openai_auth = false

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
                requiresOpenAIAuth: false
            )
        )
        XCTAssertNotNil(config.modelProviders["openai"])
    }

    func testModelProvidersFromConfigDoNotReplaceBuiltIns() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        [model_providers.openai]
        name = "Shadow OpenAI"
        base_url = "https://shadow.example/v1"
        wire_api = "chat"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.modelProviders["openai"]?.name, "OpenAI")
        XCTAssertEqual(config.modelProviders["openai"]?.wireAPI, .responses)
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
        sandbox_mode = "read-only"
        model_reasoning_effort = "low"
        model_reasoning_summary = "concise"
        model_verbosity = "medium"
        experimental_instructions_file = "top-instructions.md"
        experimental_compact_prompt_file = "top-compact.md"
        include_apply_patch_tool = true
        experimental_use_unified_exec_tool = false
        experimental_use_freeform_apply_patch = false
        tools_web_search = false
        tools_view_image = false
        oss_provider = "top-oss"

        [profiles.work]
        model = "profile-model"
        model_provider = "lmstudio"
        approval_policy = "never"
        sandbox_mode = "danger-full-access"
        model_reasoning_effort = "xhigh"
        model_reasoning_summary = "auto"
        model_verbosity = "high"
        experimental_instructions_file = "profile-instructions.md"
        experimental_compact_prompt_file = "profile-compact.md"
        include_apply_patch_tool = false
        experimental_use_unified_exec_tool = true
        experimental_use_freeform_apply_patch = true
        tools_web_search = true
        tools_view_image = true
        oss_provider = "profile-oss"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.activeProfile, "work")
        XCTAssertEqual(config.model, "profile-model")
        XCTAssertEqual(config.modelProvider, "lmstudio")
        XCTAssertEqual(config.selectedModelProviderID, "lmstudio")
        XCTAssertEqual(config.approvalPolicy, .never)
        XCTAssertEqual(config.sandboxMode, .dangerFullAccess)
        XCTAssertEqual(config.modelReasoningEffort, .xhigh)
        XCTAssertEqual(config.modelReasoningSummary, .auto)
        XCTAssertEqual(config.modelVerbosity, .high)
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
        parallel = false

        [profiles.work.features]
        parallel = true
        skills = false
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(
            codexHome: dir.url,
            overrides: CliConfigOverrides(rawOverrides: ["features.web_search_request=false"]),
            systemConfigFile: nil
        )

        XCTAssertEqual(config.activeProfile, "work")
        XCTAssertFalse(config.features.isEnabled(.webSearchRequest))
        XCTAssertTrue(config.features.isEnabled(.parallel))
        XCTAssertFalse(config.features.isEnabled(.skills))
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

        XCTAssertEqual(config.chatgptBaseURL, "https://child.example/backend-api/")
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

        XCTAssertEqual(config.chatgptBaseURL, "https://project.example/backend-api/")
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

        XCTAssertEqual(config.chatgptBaseURL, "https://project.example/backend-api/")
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
