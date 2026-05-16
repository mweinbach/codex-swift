import CodexCore
import Foundation

public struct DoctorSandboxHelperPaths: Equatable, Sendable {
    public let codexLinuxSandbox: String?
    public let execveWrapper: String?

    public init(codexLinuxSandbox: String? = nil, execveWrapper: String? = nil) {
        self.codexLinuxSandbox = codexLinuxSandbox
        self.execveWrapper = execveWrapper
    }

    public static func detect() -> DoctorSandboxHelperPaths {
        DoctorSandboxHelperPaths()
    }
}

extension DoctorCommandRuntime {
    public static func sandboxHelpersCheck(
        approvalPolicy: AskForApproval?,
        sandboxPolicy: SandboxPolicy,
        permissionProfile: PermissionProfile?,
        cwd: String,
        effectiveWorkspaceRoots: [String],
        helperPaths: DoctorSandboxHelperPaths = .detect()
    ) -> DoctorCheck {
        let resolvedApprovalPolicy = approvalPolicy ?? AskForApproval.defaultValue
        let resolvedPermissionProfile = permissionProfile ?? .fromLegacySandboxPolicy(sandboxPolicy)
        let fileSystemSandboxPolicy = resolvedPermissionProfile.fileSystemSandboxPolicy
        var details = [
            "approval policy: \(resolvedApprovalPolicy.rawValue)",
            "filesystem sandbox: \(fileSystemSandboxKind(fileSystemSandboxPolicy))",
            "network sandbox: \(resolvedPermissionProfile.networkSandboxPolicy.rawValue)"
        ]
        pushPathDetail(
            into: &details,
            label: "codex-linux-sandbox helper",
            path: helperPaths.codexLinuxSandbox
        )
        pushPathDetail(
            into: &details,
            label: "execve wrapper helper",
            path: helperPaths.execveWrapper
        )

        var status = DoctorCheckStatus.ok
        var summary = "sandbox configuration is readable"
        if let helperPath = helperPaths.codexLinuxSandbox,
           !FileManager.default.fileExists(atPath: helperPath)
        {
            status = .warning
            summary = "Linux sandbox helper path does not exist"
        }

        return DoctorCheck(
            id: "sandbox.helpers",
            category: "sandbox",
            status: status,
            summary: summary,
            details: details
        )
    }

    private static func fileSystemSandboxKind(_ policy: FileSystemSandboxPolicy) -> String {
        switch policy {
        case .restricted:
            "restricted"
        case .unrestricted:
            "unrestricted"
        case .externalSandbox:
            "external-sandbox"
        }
    }

    private static func pushPathDetail(into details: inout [String], label: String, path: String?) {
        details.append("\(label): \(path ?? "none")")
    }
}
