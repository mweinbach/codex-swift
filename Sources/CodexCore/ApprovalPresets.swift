import Foundation

public struct ApprovalPreset: Equatable, Sendable {
    public let id: String
    public let label: String
    public let description: String
    public let approval: AskForApproval
    public let sandbox: SandboxPolicy

    public init(
        id: String,
        label: String,
        description: String,
        approval: AskForApproval,
        sandbox: SandboxPolicy
    ) {
        self.id = id
        self.label = label
        self.description = description
        self.approval = approval
        self.sandbox = sandbox
    }
}

public enum ApprovalPresets {
    public static func builtIn() -> [ApprovalPreset] {
        [
            ApprovalPreset(
                id: "read-only",
                label: "Read Only",
                description: "Requires approval to edit files and run commands.",
                approval: .onRequest,
                sandbox: .readOnly
            ),
            ApprovalPreset(
                id: "auto",
                label: "Agent",
                description: "Read and edit files, and run commands.",
                approval: .onRequest,
                sandbox: .newWorkspaceWritePolicy()
            ),
            ApprovalPreset(
                id: "full-access",
                label: "Agent (full access)",
                description: "Codex can edit files outside this workspace and run commands with network access. Exercise caution when using.",
                approval: .never,
                sandbox: .dangerFullAccess
            )
        ]
    }
}
