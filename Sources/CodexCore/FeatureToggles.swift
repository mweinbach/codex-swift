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
    case parallel
    case viewImageTool = "view_image_tool"
    case shellTool = "shell_tool"
    case warnings
    case webSearchRequest = "web_search_request"
    case unifiedExec = "unified_exec"
    case shellSnapshot = "shell_snapshot"
    case applyPatchFreeform = "apply_patch_freeform"
    case computerUseGui = "computer_use_gui"
    case execPolicy = "exec_policy"
    case experimentalWindowsSandbox = "experimental_windows_sandbox"
    case elevatedWindowsSandbox = "elevated_windows_sandbox"
    case remoteCompaction = "remote_compaction"
    case remoteModels = "remote_models"
    case skills
    case powershellUtf8 = "powershell_utf8"
    case toolSearch = "tool_search"
    case tui2
}

public enum FeatureStage: Equatable, Sendable {
    case experimental
    case beta(name: String, menuDescription: String, announcement: String)
    case stable
    case deprecated
    case removed

    public var listName: String {
        switch self {
        case .experimental:
            return "experimental"
        case .beta:
            return "beta"
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
    }
}

public enum FeatureKeys {
    public static let legacyAliases: [String: FeatureKey] = [
        "enable_experimental_windows_sandbox": .experimentalWindowsSandbox,
        "experimental_use_unified_exec_tool": .unifiedExec,
        "experimental_use_freeform_apply_patch": .applyPatchFreeform,
        "include_apply_patch_tool": .applyPatchFreeform,
        "web_search": .webSearchRequest
    ]

    public static func isKnown(_ key: String) -> Bool {
        FeatureRegistry.feature(forKey: key) != nil
    }
}

public enum FeatureRegistry {
    public static let specs: [FeatureSpec] = [
        FeatureSpec(id: .undo, key: "undo", stage: .stable, defaultEnabled: false),
        FeatureSpec(id: .parallel, key: "parallel", stage: .stable, defaultEnabled: true),
        FeatureSpec(id: .viewImageTool, key: "view_image_tool", stage: .stable, defaultEnabled: true),
        FeatureSpec(id: .shellTool, key: "shell_tool", stage: .stable, defaultEnabled: true),
        FeatureSpec(id: .warnings, key: "warnings", stage: .stable, defaultEnabled: true),
        FeatureSpec(id: .webSearchRequest, key: "web_search_request", stage: .stable, defaultEnabled: false),
        FeatureSpec(
            id: .unifiedExec,
            key: "unified_exec",
            stage: .beta(
                name: "Background terminal",
                menuDescription: "Run long-running terminal commands in the background.",
                announcement: "NEW! Try Background terminals for long running processes. Enable in /experimental!"
            ),
            defaultEnabled: false
        ),
        FeatureSpec(
            id: .shellSnapshot,
            key: "shell_snapshot",
            stage: .beta(
                name: "Shell snapshot",
                menuDescription: "Snapshot your shell environment to avoid re-running login scripts for every command.",
                announcement: "NEW! Try shell snapshotting to make your Codex faster. Enable in /experimental!"
            ),
            defaultEnabled: false
        ),
        FeatureSpec(id: .applyPatchFreeform, key: "apply_patch_freeform", stage: .experimental, defaultEnabled: false),
        FeatureSpec(id: .computerUseGui, key: "computer_use_gui", stage: .experimental, defaultEnabled: false),
        FeatureSpec(id: .execPolicy, key: "exec_policy", stage: .experimental, defaultEnabled: true),
        FeatureSpec(id: .experimentalWindowsSandbox, key: "experimental_windows_sandbox", stage: .experimental, defaultEnabled: false),
        FeatureSpec(id: .elevatedWindowsSandbox, key: "elevated_windows_sandbox", stage: .experimental, defaultEnabled: false),
        FeatureSpec(id: .remoteCompaction, key: "remote_compaction", stage: .experimental, defaultEnabled: true),
        FeatureSpec(id: .remoteModels, key: "remote_models", stage: .experimental, defaultEnabled: false),
        FeatureSpec(id: .skills, key: "skills", stage: .experimental, defaultEnabled: true),
        FeatureSpec(id: .powershellUtf8, key: "powershell_utf8", stage: .experimental, defaultEnabled: false),
        FeatureSpec(id: .toolSearch, key: "tool_search", stage: .stable, defaultEnabled: true),
        FeatureSpec(id: .tui2, key: "tui2", stage: .experimental, defaultEnabled: false)
    ]

    public static func feature(forKey key: String) -> FeatureKey? {
        if let feature = specs.first(where: { $0.key == key })?.id {
            return feature
        }
        return FeatureKeys.legacyAliases[key]
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
