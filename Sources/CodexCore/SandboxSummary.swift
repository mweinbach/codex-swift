import Foundation

public enum SandboxSummary {
    public static func summarize(_ sandboxPolicy: SandboxPolicy) -> String {
        switch sandboxPolicy {
        case .dangerFullAccess:
            return "danger-full-access"
        case .readOnly:
            return "read-only"
        case .readOnlyWithNetworkAccess:
            return "read-only (network access enabled)"
        case let .externalSandbox(networkAccess):
            var summary = "external-sandbox"
            if networkAccess == .enabled {
                summary += " (network access enabled)"
            }
            return summary
        case let .workspaceWrite(writableRoots, networkAccess, excludeTmpdirEnvVar, excludeSlashTmp):
            var writableEntries = ["workdir"]
            if !excludeSlashTmp {
                writableEntries.append("/tmp")
            }
            if !excludeTmpdirEnvVar {
                writableEntries.append("$TMPDIR")
            }
            writableEntries.append(contentsOf: writableRoots.map(\.description))

            var summary = "workspace-write [\(writableEntries.joined(separator: ", "))]"
            if networkAccess {
                summary += " (network access enabled)"
            }
            return summary
        }
    }

    public static func summarize(
        permissionProfile: PermissionProfile,
        cwd: String,
        effectiveWorkspaceRoots: [String]
    ) -> String {
        do {
            let sandboxPolicy = try permissionProfile.fileSystemSandboxPolicy.toLegacySandboxPolicy(
                networkPolicy: permissionProfile.networkSandboxPolicy,
                cwd: cwd
            )
            if case let .workspaceWrite(_, networkAccess, excludeTmpdirEnvVar, excludeSlashTmp) = sandboxPolicy {
                return summarizeWorkspaceWrite(
                    networkAccess: networkAccess,
                    excludeTmpdirEnvVar: excludeTmpdirEnvVar,
                    excludeSlashTmp: excludeSlashTmp,
                    cwd: cwd,
                    effectiveWorkspaceRoots: effectiveWorkspaceRoots
                )
            }
            return summarize(sandboxPolicy)
        } catch {
            var summary = "custom permissions"
            if permissionProfile.networkSandboxPolicy.isEnabled {
                summary += " (network access enabled)"
            }
            return summary
        }
    }

    private static func summarizeWorkspaceWrite(
        networkAccess: Bool,
        excludeTmpdirEnvVar: Bool,
        excludeSlashTmp: Bool,
        cwd: String,
        effectiveWorkspaceRoots: [String]
    ) -> String {
        var writableEntries = ["workdir"]
        if !excludeSlashTmp {
            writableEntries.append("/tmp")
        }
        if !excludeTmpdirEnvVar {
            writableEntries.append("$TMPDIR")
        }
        writableEntries.append(contentsOf: effectiveWorkspaceRoots.filter { !samePath($0, cwd) })

        var summary = "workspace-write [\(writableEntries.joined(separator: ", "))]"
        if networkAccess {
            summary += " (network access enabled)"
        }
        return summary
    }

    private static func samePath(_ lhs: String, _ rhs: String) -> Bool {
        normalizedPath(lhs) == normalizedPath(rhs)
    }

    private static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
