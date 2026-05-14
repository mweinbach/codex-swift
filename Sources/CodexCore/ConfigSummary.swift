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
    public let modelProviderWireAPI: WireAPI
    public let modelReasoningEffort: ReasoningEffort?
    public let modelReasoningSummary: ReasoningSummary

    public init(
        workdir: String,
        modelProviderID: String,
        approvalPolicy: AskForApproval,
        sandboxPolicy: SandboxPolicy,
        modelProviderWireAPI: WireAPI,
        modelReasoningEffort: ReasoningEffort?,
        modelReasoningSummary: ReasoningSummary
    ) {
        self.workdir = workdir
        self.modelProviderID = modelProviderID
        self.approvalPolicy = approvalPolicy
        self.sandboxPolicy = sandboxPolicy
        self.modelProviderWireAPI = modelProviderWireAPI
        self.modelReasoningEffort = modelReasoningEffort
        self.modelReasoningSummary = modelReasoningSummary
    }
}

public enum ConfigSummary {
    public static func renderStartupBanner(version: String, entries: [ConfigSummaryEntry]) -> String {
        var lines = [
            "OpenAI Codex v\(version)",
            "--------"
        ]
        lines.append(contentsOf: entries.map { "\($0.key): \($0.value)" })
        return lines.joined(separator: "\n")
    }

    public static func createEntries(config: ConfigSummaryInput, model: String) -> [ConfigSummaryEntry] {
        var entries = [
            ConfigSummaryEntry("workdir", config.workdir),
            ConfigSummaryEntry("model", model),
            ConfigSummaryEntry("provider", config.modelProviderID),
            ConfigSummaryEntry("approval", config.approvalPolicy.rawValue),
            ConfigSummaryEntry("sandbox", SandboxSummary.summarize(config.sandboxPolicy))
        ]

        if config.modelProviderWireAPI == .responses {
            entries.append(ConfigSummaryEntry("reasoning effort", config.modelReasoningEffort?.rawValue ?? "none"))
            entries.append(ConfigSummaryEntry("reasoning summaries", config.modelReasoningSummary.rawValue))
        }

        return entries
    }
}
