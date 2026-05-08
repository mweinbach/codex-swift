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

public enum FeatureKey: String, CaseIterable, Sendable {
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
    case tui2
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
        FeatureKey(rawValue: key) != nil || legacyAliases[key] != nil
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
