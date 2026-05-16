import Foundation

public struct ConfigSummaryEntry: Equatable, Sendable {
    public let key: String
    public let value: String

    public init(_ key: String, _ value: String) {
        self.key = key
        self.value = value
    }
}

public struct ConfigSummaryInput: Equatable, Sendable {
    public let workdir: String
    public let modelProviderID: String
    public let approvalPolicy: AskForApproval
    public let sandboxPolicy: SandboxPolicy
    public let permissionProfile: PermissionProfile?
    public let effectiveWorkspaceRoots: [String]
    public let modelProviderWireAPI: WireAPI
    public let modelReasoningEffort: ReasoningEffort?
    public let modelReasoningSummary: ReasoningSummary

    public init(
        workdir: String,
        modelProviderID: String,
        approvalPolicy: AskForApproval,
        sandboxPolicy: SandboxPolicy,
        permissionProfile: PermissionProfile? = nil,
        effectiveWorkspaceRoots: [String] = [],
        modelProviderWireAPI: WireAPI,
        modelReasoningEffort: ReasoningEffort?,
        modelReasoningSummary: ReasoningSummary
    ) {
        self.workdir = workdir
        self.modelProviderID = modelProviderID
        self.approvalPolicy = approvalPolicy
        self.sandboxPolicy = sandboxPolicy
        self.permissionProfile = permissionProfile
        self.effectiveWorkspaceRoots = effectiveWorkspaceRoots
        self.modelProviderWireAPI = modelProviderWireAPI
        self.modelReasoningEffort = modelReasoningEffort
        self.modelReasoningSummary = modelReasoningSummary
    }
}

public enum ConfigSummary {
    public static func resolveEffectiveWorkspaceRoots(
        config: CodexRuntimeConfig,
        cwd: URL,
        additionalWritableRootArguments: [String]
    ) -> [AbsolutePath] {
        var roots = config.effectiveWorkspaceRoots
        if roots.isEmpty,
           let cwdRoot = try? AbsolutePath(absolutePath: cwd.standardizedFileURL.path)
        {
            roots.append(cwdRoot)
        }

        for argument in additionalWritableRootArguments {
            guard let root = try? AbsolutePath.resolve(argument, against: cwd.standardizedFileURL.path),
                  !roots.contains(root)
            else {
                continue
            }
            roots.append(root)
        }
        return roots
    }

    public static func renderStartupBanner(version: String, entries: [ConfigSummaryEntry]) -> String {
        var lines = [
            "OpenAI Codex v\(version)",
            "--------"
        ]
        lines.append(contentsOf: entries.map { "\($0.key): \($0.value)" })
        return lines.joined(separator: "\n")
    }

    public static func createEntries(config: ConfigSummaryInput, model: String) -> [ConfigSummaryEntry] {
        let sandboxSummary = config.permissionProfile.map {
            SandboxSummary.summarize(
                permissionProfile: $0,
                cwd: config.workdir,
                effectiveWorkspaceRoots: config.effectiveWorkspaceRoots.isEmpty
                    ? [config.workdir]
                    : config.effectiveWorkspaceRoots
            )
        } ?? SandboxSummary.summarize(config.sandboxPolicy)

        var entries = [
            ConfigSummaryEntry("workdir", config.workdir),
            ConfigSummaryEntry("model", model),
            ConfigSummaryEntry("provider", config.modelProviderID),
            ConfigSummaryEntry("approval", config.approvalPolicy.rawValue),
            ConfigSummaryEntry("sandbox", sandboxSummary)
        ]

        if config.modelProviderWireAPI == .responses {
            entries.append(ConfigSummaryEntry("reasoning effort", config.modelReasoningEffort?.rawValue ?? "none"))
            entries.append(ConfigSummaryEntry("reasoning summaries", config.modelReasoningSummary.rawValue))
        }

        return entries
    }
}
