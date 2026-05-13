import Foundation

/// Returns a warning for additional writable roots ignored by the resolved permission profile.
public func addDirWarningMessage(
    additionalDirs: [String],
    permissionProfile: PermissionProfile,
    cwd: String
) -> String? {
    guard !additionalDirs.isEmpty else {
        return nil
    }

    switch permissionProfile {
    case .disabled, .external:
        return nil
    case .managed:
        break
    }

    let fileSystemPolicy = permissionProfile.fileSystemSandboxPolicy
    if fileSystemPolicy.hasFullDiskWriteAccess {
        return nil
    }
    if fileSystemPolicy.canWritePathWithCwd(cwd, cwd: cwd) {
        return nil
    }

    return formatAddDirWarning(additionalDirs: additionalDirs)
}

/// Returns a warning for additional writable roots ignored by a legacy sandbox policy.
public func addDirWarningMessage(
    additionalDirs: [String],
    sandboxPolicy: SandboxPolicy,
    cwd: String = FileManager.default.currentDirectoryPath
) -> String? {
    addDirWarningMessage(
        additionalDirs: additionalDirs,
        permissionProfile: .fromLegacySandboxPolicyForCwd(sandboxPolicy, cwd: cwd),
        cwd: cwd
    )
}

private func formatAddDirWarning(additionalDirs: [String]) -> String {
    let joinedPaths = additionalDirs.joined(separator: ", ")
    return "Ignoring --add-dir (\(joinedPaths)) because the effective permissions do not allow additional writable roots. Switch to workspace-write or danger-full-access to allow them."
}
