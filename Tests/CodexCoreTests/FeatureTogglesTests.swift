import CodexCore
import Foundation
import XCTest

final class FeatureTogglesTests: XCTestCase {
    func testFeatureRegistryMatchesRustListOrderStagesAndDefaults() {
        XCTAssertEqual(FeatureRegistry.specs.map(\.key), [
            "undo",
            "shell_tool",
            "unified_exec",
            "shell_zsh_fork",
            "shell_snapshot",
            "js_repl",
            "code_mode",
            "code_mode_only",
            "js_repl_tools_only",
            "terminal_resize_reflow",
            "web_search_request",
            "web_search_cached",
            "search_tool",
            "codex_git_commit",
            "runtime_metrics",
            "sqlite",
            "memories",
            "builtin_mcp",
            "chronicle",
            "child_agents_md",
            "apply_patch_freeform",
            "apply_patch_streaming_events",
            "exec_permission_approvals",
            "hooks",
            "request_permissions_tool",
            "use_linux_sandbox_bwrap",
            "use_legacy_landlock",
            "request_rule",
            "experimental_windows_sandbox",
            "elevated_windows_sandbox",
            "remote_models",
            "enable_request_compression",
            "multi_agent",
            "multi_agent_v2",
            "enable_fanout",
            "apps",
            "enable_mcp_apps",
            "apps_mcp_path_override",
            "tool_search",
            "tool_search_always_defer_mcp_tools",
            "unavailable_dummy_tools",
            "tool_suggest",
            "plugins",
            "plugin_hooks",
            "in_app_browser",
            "browser_use",
            "browser_use_external",
            "computer_use",
            "remote_plugin",
            "external_migration",
            "image_generation",
            "skill_mcp_dependency_install",
            "skill_env_var_dependency_prompt",
            "steer",
            "default_mode_request_user_input",
            "guardian_approval",
            "goals",
            "collaboration_modes",
            "tool_call_mcp_elicitation",
            "auth_elicitation",
            "personality",
            "artifact",
            "fast_mode",
            "realtime_conversation",
            "remote_control",
            "image_detail_original",
            "tui_app_server",
            "prevent_idle_sleep",
            "workspace_owner_usage_nudge",
            "responses_websockets",
            "responses_websockets_v2",
            "responses_websocket_response_processed",
            "remote_compaction_v2",
            "workspace_dependencies"
        ])
        XCTAssertEqual(FeatureRegistry.specs.map(\.stage.listName), [
            "removed",
            "stable",
            "stable",
            "under development",
            "stable",
            "removed",
            "under development",
            "under development",
            "removed",
            "experimental",
            "deprecated",
            "deprecated",
            "removed",
            "under development",
            "under development",
            "removed",
            "experimental",
            "under development",
            "under development",
            "under development",
            "stable",
            "under development",
            "under development",
            "stable",
            "under development",
            "removed",
            "deprecated",
            "removed",
            "removed",
            "removed",
            "removed",
            "stable",
            "stable",
            "under development",
            "under development",
            "stable",
            "under development",
            "under development",
            "stable",
            "under development",
            "stable",
            "stable",
            "stable",
            "under development",
            "stable",
            "stable",
            "stable",
            "stable",
            "under development",
            "experimental",
            "stable",
            "stable",
            "under development",
            "removed",
            "under development",
            "stable",
            "experimental",
            "removed",
            "stable",
            "under development",
            "stable",
            "under development",
            "stable",
            "under development",
            "under development",
            "removed",
            "removed",
            "experimental",
            "under development",
            "removed",
            "removed",
            "under development",
            "under development",
            "stable"
        ])
        XCTAssertTrue(FeatureStates.withDefaults().isEnabled(.shellTool))
        XCTAssertTrue(FeatureStates.withDefaults().isEnabled(.unifiedExec))
        XCTAssertTrue(FeatureStates.withDefaults().isEnabled(.applyPatchFreeform))
        XCTAssertTrue(FeatureStates.withDefaults().isEnabled(.toolSearch))
        XCTAssertFalse(FeatureStates.withDefaults().isEnabled(.webSearchRequest))
    }

    func testFeatureTogglesBecomeConfigOverrides() throws {
        let toggles = FeatureToggles(enable: ["web_search_request"], disable: ["unified_exec"])
        XCTAssertEqual(
            try toggles.toOverrides(),
            [
                "features.web_search_request=true",
                "features.unified_exec=false"
            ]
        )
    }

    func testLegacyFeatureAliasesAreKnown() throws {
        let toggles = FeatureToggles(enable: ["experimental_use_unified_exec_tool", "telepathy"])
        XCTAssertEqual(try toggles.toOverrides(), [
            "features.experimental_use_unified_exec_tool=true",
            "features.telepathy=true"
        ])
    }

    func testFeatureDependenciesNormalizeLikeRust() {
        var states = FeatureStates()
        states.apply(featureValues: ["enable_fanout": true, "code_mode_only": true])
        XCTAssertTrue(states.isEnabled(.spawnCsv))
        XCTAssertTrue(states.isEnabled(.collab))
        XCTAssertTrue(states.isEnabled(.codeModeOnly))
        XCTAssertTrue(states.isEnabled(.codeMode))
    }

    func testUnknownFeatureThrows() {
        XCTAssertThrowsError(try FeatureToggles(enable: ["definitely_not_real"]).toOverrides())
    }

    func testConfigFeatureEditorAppendsRootFeatureTable() throws {
        let temp = try FeatureToggleTemporaryDirectory()
        try ConfigFeatureEditor.setFeatureEnabled(codexHome: temp.url, feature: "unified_exec", enabled: true)

        let config = try String(contentsOf: temp.url.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertEqual(config, """
        [features]
        unified_exec = true

        """)
    }

    func testConfigFeatureEditorUpdatesExistingFeatureTable() throws {
        let input = """
        model = "gpt-5"

        [features]
        shell_tool = true
        unified_exec = false

        [mcp_servers.docs]
        command = "docs"
        """

        XCTAssertEqual(
            ConfigFeatureEditor.setFeatureEnabled(in: input, feature: "unified_exec", enabled: true),
            """
            model = "gpt-5"

            [features]
            shell_tool = true
            unified_exec = true

            [mcp_servers.docs]
            command = "docs"

            """
        )
    }

    func testConfigFeatureEditorWritesProfileFeatureTable() {
        XCTAssertEqual(
            ConfigFeatureEditor.setFeatureEnabled(in: #"profile = "work""#, feature: "shell_tool", enabled: false, profile: "work"),
            """
            profile = "work"

            [profiles.work.features]
            shell_tool = false

            """
        )
    }

    func testConfigFeatureEditorClearsRootDefaultFalseFeatureOnDisable() {
        let input = """
        [features]
        runtime_metrics = true
        shell_tool = true

        """

        XCTAssertEqual(
            ConfigFeatureEditor.setFeatureEnabled(in: input, feature: "runtime_metrics", enabled: false),
            """
            [features]
            shell_tool = true

            """
        )

        XCTAssertEqual(
            ConfigFeatureEditor.setFeatureEnabled(in: "", feature: "runtime_metrics", enabled: false),
            ""
        )
    }

    func testConfigFeatureEditorPersistsRootDefaultTrueFeatureOnDisable() {
        XCTAssertEqual(
            ConfigFeatureEditor.setFeatureEnabled(in: "", feature: "shell_tool", enabled: false),
            """
            [features]
            shell_tool = false

            """
        )
    }
}

private final class FeatureToggleTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-swift-feature-toggle-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
