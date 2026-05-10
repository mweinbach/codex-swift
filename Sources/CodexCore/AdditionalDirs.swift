import Foundation

/// Returns a warning for additional writable roots ignored by the resolved sandbox policy.
public func addDirWarningMessage(additionalDirs: [String], sandboxPolicy: SandboxPolicy) -> String? {
    guard !additionalDirs.isEmpty else {
        return nil
    }

    switch sandboxPolicy {
    case .workspaceWrite, .dangerFullAccess, .externalSandbox:
        return nil
    case .readOnly, .readOnlyWithNetworkAccess:
        return formatAddDirWarning(additionalDirs: additionalDirs)
    }
}

private func formatAddDirWarning(additionalDirs: [String]) -> String {
    let joinedPaths = additionalDirs.joined(separator: ", ")
    return "Ignoring --add-dir (\(joinedPaths)) because the effective sandbox mode is read-only. Switch to workspace-write or danger-full-access to allow additional writable roots."
}
