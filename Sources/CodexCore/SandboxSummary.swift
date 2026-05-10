import Foundation

public enum SandboxSummary {
    public static func summarize(_ sandboxPolicy: SandboxPolicy) -> String {
        switch sandboxPolicy {
        case .dangerFullAccess:
            return "danger-full-access"
        case .readOnly, .readOnlyWithNetworkAccess:
            return "read-only"
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
}
