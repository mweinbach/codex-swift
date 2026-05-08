import Foundation

public enum FeatureToggleError: Error, Equatable, CustomStringConvertible, Sendable {
    case unknownFeature(String)

    public var description: String {
        switch self {
        case let .unknownFeature(feature):
            return "Unknown feature flag: \(feature)"
        }
    }
}

public enum FeatureKey: String, CaseIterable, Hashable, Sendable {
    case undo
    case shellTool = "shell_tool"
    case unifiedExec = "unified_exec"
    case shellZshFork = "shell_zsh_fork"
    case shellSnapshot = "shell_snapshot"
    case jsRepl = "js_repl"
    case codeMode = "code_mode"
    case codeModeOnly = "code_mode_only"
    case jsReplToolsOnly = "js_repl_tools_only"
    case terminalResizeReflow = "terminal_resize_reflow"
    case webSearchRequest = "web_search_request"
    case webSearchCached = "web_search_cached"
    case searchTool = "search_tool"
    case codexGitCommit = "codex_git_commit"
    case runtimeMetrics = "runtime_metrics"
    case sqlite
    case memoryTool = "memories"
    case builtInMcp = "builtin_mcp"
    case chronicle
    case childAgentsMd = "child_agents_md"
    case applyPatchFreeform = "apply_patch_freeform"
    case applyPatchStreamingEvents = "apply_patch_streaming_events"
    case execPermissionApprovals = "exec_permission_approvals"
    case codexHooks = "hooks"
    case requestPermissionsTool = "request_permissions_tool"
    case useLinuxSandboxBwrap = "use_linux_sandbox_bwrap"
    case useLegacyLandlock = "use_legacy_landlock"
    case requestRule = "request_rule"
    case windowsSandbox = "experimental_windows_sandbox"
    case windowsSandboxElevated = "elevated_windows_sandbox"
    case remoteModels = "remote_models"
    case enableRequestCompression = "enable_request_compression"
    case collab = "multi_agent"
    case multiAgentV2 = "multi_agent_v2"
    case spawnCsv = "enable_fanout"
    case apps
    case enableMcpApps = "enable_mcp_apps"
    case appsMcpPathOverride = "apps_mcp_path_override"
    case toolSearch = "tool_search"
    case toolSearchAlwaysDeferMcpTools = "tool_search_always_defer_mcp_tools"
    case unavailableDummyTools = "unavailable_dummy_tools"
    case toolSuggest = "tool_suggest"
    case plugins
    case pluginHooks = "plugin_hooks"
    case inAppBrowser = "in_app_browser"
    case browserUse = "browser_use"
    case browserUseExternal = "browser_use_external"
    case computerUse = "computer_use"
    case remotePlugin = "remote_plugin"
    case externalMigration = "external_migration"
    case imageGeneration = "image_generation"
    case skillMcpDependencyInstall = "skill_mcp_dependency_install"
    case skillEnvVarDependencyPrompt = "skill_env_var_dependency_prompt"
    case steer
    case defaultModeRequestUserInput = "default_mode_request_user_input"
    case guardianApproval = "guardian_approval"
    case goals
    case collaborationModes = "collaboration_modes"
    case toolCallMcpElicitation = "tool_call_mcp_elicitation"
    case authElicitation = "auth_elicitation"
    case personality
    case artifact
    case fastMode = "fast_mode"
    case realtimeConversation = "realtime_conversation"
    case remoteControl = "remote_control"
    case imageDetailOriginal = "image_detail_original"
    case tuiAppServer = "tui_app_server"
    case preventIdleSleep = "prevent_idle_sleep"
    case workspaceOwnerUsageNudge = "workspace_owner_usage_nudge"
    case responsesWebsockets = "responses_websockets"
    case responsesWebsocketsV2 = "responses_websockets_v2"
    case responsesWebsocketResponseProcessed = "responses_websocket_response_processed"
    case remoteCompactionV2 = "remote_compaction_v2"
    case workspaceDependencies = "workspace_dependencies"
}

public enum FeatureStage: Equatable, Sendable {
    case underDevelopment
    case experimental
    case stable
    case deprecated
    case removed

    public var listName: String {
        switch self {
        case .underDevelopment:
            return "under-development"
        case .experimental:
            return "experimental"
        case .stable:
            return "stable"
        case .deprecated:
            return "deprecated"
        case .removed:
            return "removed"
        }
    }
}

public struct FeatureSpec: Equatable, Sendable {
    public let id: FeatureKey
    public let key: String
    public let stage: FeatureStage
    public let defaultEnabled: Bool

    public init(id: FeatureKey, key: String, stage: FeatureStage, defaultEnabled: Bool) {
        self.id = id
        self.key = key
        self.stage = stage
        self.defaultEnabled = defaultEnabled
    }
}

public struct FeatureStates: Equatable, Sendable {
    private var enabled: Set<FeatureKey>

    public init(enabled: Set<FeatureKey> = []) {
        self.enabled = enabled
    }

    public static func withDefaults() -> FeatureStates {
        FeatureStates(enabled: Set(FeatureRegistry.specs.filter(\.defaultEnabled).map(\.id)))
    }

    public func isEnabled(_ feature: FeatureKey) -> Bool {
        enabled.contains(feature)
    }

    public mutating func set(_ feature: FeatureKey, enabled isEnabled: Bool) {
        if isEnabled {
            enabled.insert(feature)
        } else {
            enabled.remove(feature)
        }
    }

    public mutating func apply(featureValues: [String: Bool]) {
        for (key, isEnabled) in featureValues {
            guard let feature = FeatureRegistry.feature(forKey: key) else { continue }
            set(feature, enabled: isEnabled)
        }
        normalizeDependencies()
    }

    public mutating func normalizeDependencies() {
        if isEnabled(.spawnCsv), !isEnabled(.collab) {
            set(.collab, enabled: true)
        }
        if isEnabled(.codeModeOnly), !isEnabled(.codeMode) {
            set(.codeMode, enabled: true)
        }
    }
}

public enum FeatureKeys {
    public static let legacyAliases: [String: FeatureKey] = [
        "connectors": .apps,
        "enable_experimental_windows_sandbox": .windowsSandbox,
        "experimental_use_unified_exec_tool": .unifiedExec,
        "experimental_use_freeform_apply_patch": .applyPatchFreeform,
        "include_apply_patch_tool": .applyPatchFreeform,
        "request_permissions": .execPermissionApprovals,
        "web_search": .webSearchRequest,
        "collab": .collab,
        "memory_tool": .memoryTool,
        "telepathy": .chronicle,
        "codex_hooks": .codexHooks
    ]

    public static func isKnown(_ key: String) -> Bool {
        FeatureRegistry.feature(forKey: key) != nil
    }
}

public enum FeatureRegistry {
    public static let specs: [FeatureSpec] = [
        FeatureSpec(id: .undo, key: "undo", stage: .removed, defaultEnabled: false),
        FeatureSpec(id: .shellTool, key: "shell_tool", stage: .stable, defaultEnabled: true),
        FeatureSpec(id: .unifiedExec, key: "unified_exec", stage: .stable, defaultEnabled: PlatformDefaults.unifiedExecEnabled),
        FeatureSpec(id: .shellZshFork, key: "shell_zsh_fork", stage: .underDevelopment, defaultEnabled: false),
        FeatureSpec(id: .shellSnapshot, key: "shell_snapshot", stage: .stable, defaultEnabled: true),
        FeatureSpec(id: .jsRepl, key: "js_repl", stage: .removed, defaultEnabled: false),
        FeatureSpec(id: .codeMode, key: "code_mode", stage: .underDevelopment, defaultEnabled: false),
        FeatureSpec(id: .codeModeOnly, key: "code_mode_only", stage: .underDevelopment, defaultEnabled: false),
        FeatureSpec(id: .jsReplToolsOnly, key: "js_repl_tools_only", stage: .removed, defaultEnabled: false),
        FeatureSpec(id: .terminalResizeReflow, key: "terminal_resize_reflow", stage: .experimental, defaultEnabled: true),
        FeatureSpec(id: .webSearchRequest, key: "web_search_request", stage: .deprecated, defaultEnabled: false),
        FeatureSpec(id: .webSearchCached, key: "web_search_cached", stage: .deprecated, defaultEnabled: false),
        FeatureSpec(id: .searchTool, key: "search_tool", stage: .removed, defaultEnabled: false),
        FeatureSpec(id: .codexGitCommit, key: "codex_git_commit", stage: .underDevelopment, defaultEnabled: false),
        FeatureSpec(id: .runtimeMetrics, key: "runtime_metrics", stage: .underDevelopment, defaultEnabled: false),
        FeatureSpec(id: .sqlite, key: "sqlite", stage: .removed, defaultEnabled: true),
        FeatureSpec(id: .memoryTool, key: "memories", stage: .experimental, defaultEnabled: false),
        FeatureSpec(id: .builtInMcp, key: "builtin_mcp", stage: .underDevelopment, defaultEnabled: false),
        FeatureSpec(id: .chronicle, key: "chronicle", stage: .underDevelopment, defaultEnabled: false),
        FeatureSpec(id: .childAgentsMd, key: "child_agents_md", stage: .underDevelopment, defaultEnabled: false),
        FeatureSpec(id: .applyPatchFreeform, key: "apply_patch_freeform", stage: .stable, defaultEnabled: true),
        FeatureSpec(id: .applyPatchStreamingEvents, key: "apply_patch_streaming_events", stage: .underDevelopment, defaultEnabled: false),
        FeatureSpec(id: .execPermissionApprovals, key: "exec_permission_approvals", stage: .underDevelopment, defaultEnabled: false),
        FeatureSpec(id: .codexHooks, key: "hooks", stage: .stable, defaultEnabled: true),
        FeatureSpec(id: .requestPermissionsTool, key: "request_permissions_tool", stage: .underDevelopment, defaultEnabled: false),
        FeatureSpec(id: .useLinuxSandboxBwrap, key: "use_linux_sandbox_bwrap", stage: .removed, defaultEnabled: false),
        FeatureSpec(id: .useLegacyLandlock, key: "use_legacy_landlock", stage: .deprecated, defaultEnabled: false),
        FeatureSpec(id: .requestRule, key: "request_rule", stage: .removed, defaultEnabled: false),
        FeatureSpec(id: .windowsSandbox, key: "experimental_windows_sandbox", stage: .removed, defaultEnabled: false),
        FeatureSpec(id: .windowsSandboxElevated, key: "elevated_windows_sandbox", stage: .removed, defaultEnabled: false),
        FeatureSpec(id: .remoteModels, key: "remote_models", stage: .removed, defaultEnabled: false),
        FeatureSpec(id: .enableRequestCompression, key: "enable_request_compression", stage: .stable, defaultEnabled: true),
        FeatureSpec(id: .collab, key: "multi_agent", stage: .stable, defaultEnabled: true),
        FeatureSpec(id: .multiAgentV2, key: "multi_agent_v2", stage: .underDevelopment, defaultEnabled: false),
        FeatureSpec(id: .spawnCsv, key: "enable_fanout", stage: .underDevelopment, defaultEnabled: false),
        FeatureSpec(id: .apps, key: "apps", stage: .stable, defaultEnabled: true),
        FeatureSpec(id: .enableMcpApps, key: "enable_mcp_apps", stage: .underDevelopment, defaultEnabled: false),
        FeatureSpec(id: .appsMcpPathOverride, key: "apps_mcp_path_override", stage: .underDevelopment, defaultEnabled: false),
        FeatureSpec(id: .toolSearch, key: "tool_search", stage: .stable, defaultEnabled: true),
        FeatureSpec(id: .toolSearchAlwaysDeferMcpTools, key: "tool_search_always_defer_mcp_tools", stage: .underDevelopment, defaultEnabled: false),
        FeatureSpec(id: .unavailableDummyTools, key: "unavailable_dummy_tools", stage: .stable, defaultEnabled: true),
        FeatureSpec(id: .toolSuggest, key: "tool_suggest", stage: .stable, defaultEnabled: true),
        FeatureSpec(id: .plugins, key: "plugins", stage: .stable, defaultEnabled: true),
        FeatureSpec(id: .pluginHooks, key: "plugin_hooks", stage: .underDevelopment, defaultEnabled: false),
        FeatureSpec(id: .inAppBrowser, key: "in_app_browser", stage: .stable, defaultEnabled: true),
        FeatureSpec(id: .browserUse, key: "browser_use", stage: .stable, defaultEnabled: true),
        FeatureSpec(id: .browserUseExternal, key: "browser_use_external", stage: .stable, defaultEnabled: true),
        FeatureSpec(id: .computerUse, key: "computer_use", stage: .stable, defaultEnabled: true),
        FeatureSpec(id: .remotePlugin, key: "remote_plugin", stage: .underDevelopment, defaultEnabled: false),
        FeatureSpec(id: .externalMigration, key: "external_migration", stage: .experimental, defaultEnabled: false),
        FeatureSpec(id: .imageGeneration, key: "image_generation", stage: .stable, defaultEnabled: true),
        FeatureSpec(id: .skillMcpDependencyInstall, key: "skill_mcp_dependency_install", stage: .stable, defaultEnabled: true),
        FeatureSpec(id: .skillEnvVarDependencyPrompt, key: "skill_env_var_dependency_prompt", stage: .underDevelopment, defaultEnabled: false),
        FeatureSpec(id: .steer, key: "steer", stage: .removed, defaultEnabled: true),
        FeatureSpec(id: .defaultModeRequestUserInput, key: "default_mode_request_user_input", stage: .underDevelopment, defaultEnabled: false),
        FeatureSpec(id: .guardianApproval, key: "guardian_approval", stage: .stable, defaultEnabled: true),
        FeatureSpec(id: .goals, key: "goals", stage: .experimental, defaultEnabled: false),
        FeatureSpec(id: .collaborationModes, key: "collaboration_modes", stage: .removed, defaultEnabled: true),
        FeatureSpec(id: .toolCallMcpElicitation, key: "tool_call_mcp_elicitation", stage: .stable, defaultEnabled: true),
        FeatureSpec(id: .authElicitation, key: "auth_elicitation", stage: .underDevelopment, defaultEnabled: false),
        FeatureSpec(id: .personality, key: "personality", stage: .stable, defaultEnabled: true),
        FeatureSpec(id: .artifact, key: "artifact", stage: .underDevelopment, defaultEnabled: false),
        FeatureSpec(id: .fastMode, key: "fast_mode", stage: .stable, defaultEnabled: true),
        FeatureSpec(id: .realtimeConversation, key: "realtime_conversation", stage: .underDevelopment, defaultEnabled: false),
        FeatureSpec(id: .remoteControl, key: "remote_control", stage: .underDevelopment, defaultEnabled: false),
        FeatureSpec(id: .imageDetailOriginal, key: "image_detail_original", stage: .removed, defaultEnabled: false),
        FeatureSpec(id: .tuiAppServer, key: "tui_app_server", stage: .removed, defaultEnabled: true),
        FeatureSpec(id: .preventIdleSleep, key: "prevent_idle_sleep", stage: .experimental, defaultEnabled: false),
        FeatureSpec(id: .workspaceOwnerUsageNudge, key: "workspace_owner_usage_nudge", stage: .underDevelopment, defaultEnabled: false),
        FeatureSpec(id: .responsesWebsockets, key: "responses_websockets", stage: .removed, defaultEnabled: false),
        FeatureSpec(id: .responsesWebsocketsV2, key: "responses_websockets_v2", stage: .removed, defaultEnabled: false),
        FeatureSpec(id: .responsesWebsocketResponseProcessed, key: "responses_websocket_response_processed", stage: .underDevelopment, defaultEnabled: false),
        FeatureSpec(id: .remoteCompactionV2, key: "remote_compaction_v2", stage: .underDevelopment, defaultEnabled: false),
        FeatureSpec(id: .workspaceDependencies, key: "workspace_dependencies", stage: .stable, defaultEnabled: true)
    ]

    public static func feature(forKey key: String) -> FeatureKey? {
        if let feature = specs.first(where: { $0.key == key })?.id {
            return feature
        }
        return FeatureKeys.legacyAliases[key]
    }
}

private enum PlatformDefaults {
    static var unifiedExecEnabled: Bool {
        #if os(Windows)
            false
        #else
            true
        #endif
    }
}

public struct FeatureToggles: Equatable, Sendable {
    public var enable: [String]
    public var disable: [String]

    public init(enable: [String] = [], disable: [String] = []) {
        self.enable = enable
        self.disable = disable
    }

    public func toOverrides() throws -> [String] {
        var overrides: [String] = []
        for feature in enable {
            try validate(feature)
            overrides.append("features.\(feature)=true")
        }
        for feature in disable {
            try validate(feature)
            overrides.append("features.\(feature)=false")
        }
        return overrides
    }

    private func validate(_ feature: String) throws {
        guard FeatureKeys.isKnown(feature) else {
            throw FeatureToggleError.unknownFeature(feature)
        }
    }
}
