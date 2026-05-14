import Foundation

public enum SandboxTags {
    public static func sandboxTag(
        sandboxPolicy: SandboxPolicy,
        windowsSandboxLevel: WindowsSandboxLevel
    ) -> String {
        permissionProfileSandboxTag(
            profile: .fromLegacySandboxPolicy(sandboxPolicy),
            windowsSandboxLevel: windowsSandboxLevel,
            enforceManagedNetwork: false
        )
    }

    public static func permissionProfileSandboxTag(
        profile: PermissionProfile,
        windowsSandboxLevel: WindowsSandboxLevel,
        enforceManagedNetwork: Bool
    ) -> String {
        switch profile {
        case .disabled:
            return "none"
        case .external:
            return "external"
        case let .managed(fileSystem, network):
            if !shouldRequirePlatformSandbox(
                fileSystemPolicy: fileSystem.fileSystemSandboxPolicy,
                networkPolicy: network,
                enforceManagedNetwork: enforceManagedNetwork
            ) {
                return "none"
            }
        }

        #if os(Windows)
        if windowsSandboxLevel == .elevated {
            return "windows_elevated"
        }
        #endif

        return PatchSafety.getPlatformSandbox()?.metricTag ?? "none"
    }

    public static func permissionProfilePolicyTag(
        profile: PermissionProfile,
        cwd: String
    ) -> String {
        switch profile {
        case .disabled:
            return "danger-full-access"
        case .external:
            return "external-sandbox"
        case .managed:
            let fileSystemPolicy = profile.fileSystemSandboxPolicy
            if fileSystemPolicy.hasFullDiskWriteAccess {
                return "danger-full-access"
            }
            if fileSystemPolicy.getWritableRootsWithCwd(cwd).isEmpty {
                return "read-only"
            }
            return "workspace-write"
        }
    }

    private static func shouldRequirePlatformSandbox(
        fileSystemPolicy: FileSystemSandboxPolicy,
        networkPolicy: NetworkSandboxPolicy,
        enforceManagedNetwork: Bool
    ) -> Bool {
        if enforceManagedNetwork {
            return true
        }

        if !networkPolicy.isEnabled {
            if case .externalSandbox = fileSystemPolicy {
                return false
            }
            return true
        }

        switch fileSystemPolicy {
        case .restricted:
            return !fileSystemPolicy.hasFullDiskWriteAccess
        case .unrestricted, .externalSandbox:
            return false
        }
    }
}

extension SandboxType {
    var metricTag: String {
        switch self {
        case .none:
            return "none"
        case .macosSeatbelt:
            return "seatbelt"
        case .linuxSeccomp:
            return "seccomp"
        case .windowsRestrictedToken:
            return "windows_sandbox"
        }
    }
}
