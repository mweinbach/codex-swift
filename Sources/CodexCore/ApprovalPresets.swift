import Foundation

public struct ApprovalPreset: Equatable, Sendable {
    public let id: String
    public let label: String
    public let description: String
    public let approval: AskForApproval
    public let activePermissionProfile: ActivePermissionProfile
    public let permissionProfile: PermissionProfile
    public let sandbox: SandboxPolicy

    public init(
        id: String,
        label: String,
        description: String,
        approval: AskForApproval,
        activePermissionProfile: ActivePermissionProfile,
        permissionProfile: PermissionProfile,
        sandbox: SandboxPolicy
    ) {
        self.id = id
        self.label = label
        self.description = description
        self.approval = approval
        self.activePermissionProfile = activePermissionProfile
        self.permissionProfile = permissionProfile
        self.sandbox = sandbox
    }
}

public enum ApprovalPresets {
    public static let readOnlyActivePermissionProfileID = ":read-only"
    public static let workspaceActivePermissionProfileID = ":workspace"
    public static let dangerFullAccessActivePermissionProfileID = ":danger-full-access"

    public static func builtIn() -> [ApprovalPreset] {
        [
            ApprovalPreset(
                id: "read-only",
                label: "Read Only",
                description: "Codex can read files in the current workspace. Approval is required to edit files or access the internet.",
                approval: .onRequest,
                activePermissionProfile: ActivePermissionProfile(id: readOnlyActivePermissionProfileID),
                permissionProfile: .readOnly(),
                sandbox: .readOnly
            ),
            ApprovalPreset(
                id: "auto",
                label: "Default",
                description: "Codex can read and edit files in the current workspace, and run commands. Approval is required to access the internet or edit other files. (Identical to Agent mode)",
                approval: .onRequest,
                activePermissionProfile: ActivePermissionProfile(id: workspaceActivePermissionProfileID),
                permissionProfile: .workspaceWrite(),
                sandbox: .newWorkspaceWritePolicy()
            ),
            ApprovalPreset(
                id: "full-access",
                label: "Full Access",
                description: "Codex can edit files outside this workspace and run commands with network access. Exercise caution when using.",
                approval: .never,
                activePermissionProfile: ActivePermissionProfile(id: dangerFullAccessActivePermissionProfileID),
                permissionProfile: .disabled,
                sandbox: .dangerFullAccess
            )
        ]
    }

    public static func permissionProfile(for activePermissionProfile: ActivePermissionProfile) -> PermissionProfile? {
        guard activePermissionProfile.extends == nil else {
            return nil
        }

        switch activePermissionProfile.id {
        case readOnlyActivePermissionProfileID:
            return .readOnly()
        case workspaceActivePermissionProfileID:
            return .workspaceWrite()
        case dangerFullAccessActivePermissionProfileID:
            return .disabled
        default:
            return nil
        }
    }
}
