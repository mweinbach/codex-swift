import CodexApplyPatch
import Foundation

public enum SandboxType: Equatable, Sendable {
    case none
    case macosSeatbelt
    case linuxSeccomp
    case windowsRestrictedToken
}

public enum SafetyCheck: Equatable, Sendable {
    case autoApprove(sandboxType: SandboxType, userExplicitlyApproved: Bool)
    case askUser
    case reject(reason: String)
}

public struct WritableRoot: Equatable, Sendable {
    public let root: AbsolutePath
    public let readOnlySubpaths: [AbsolutePath]
    public let protectedMetadataNames: [String]

    public init(
        root: AbsolutePath,
        readOnlySubpaths: [AbsolutePath] = [],
        protectedMetadataNames: [String] = []
    ) {
        self.root = root
        self.readOnlySubpaths = readOnlySubpaths
        self.protectedMetadataNames = protectedMetadataNames
    }

    public func isPathWritable(_ path: AbsolutePath) -> Bool {
        guard path.isUnderOrEqual(root) else {
            return false
        }

        guard !readOnlySubpaths.contains(where: { path.isUnderOrEqual($0) }) else {
            return false
        }

        return !pathContainsProtectedMetadataName(path)
    }

    private func pathContainsProtectedMetadataName(_ path: AbsolutePath) -> Bool {
        guard let relativePath = path.path.pathSuffix(after: root.path),
              let firstComponent = relativePath.split(separator: "/", omittingEmptySubsequences: true).first
        else {
            return false
        }
        return protectedMetadataNames.contains(String(firstComponent))
    }
}

public enum PatchSafety {
    public static func assessPatchSafety(
        hunks: [Hunk],
        approvalPolicy: AskForApproval,
        sandboxPolicy: SandboxPolicy,
        cwd: AbsolutePath,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> SafetyCheck {
        if hunks.isEmpty {
            return .reject(reason: "empty patch")
        }

        if approvalPolicy == .unlessTrusted {
            return .askUser
        }

        if isWritePatchConstrainedToWritablePaths(
            hunks: hunks,
            sandboxPolicy: sandboxPolicy,
            cwd: cwd,
            environment: environment,
            fileManager: fileManager
        ) || approvalPolicy == .onFailure {
            switch sandboxPolicy {
            case .dangerFullAccess,
                 .externalSandbox:
                return .autoApprove(sandboxType: .none, userExplicitlyApproved: false)
            case .readOnly,
                 .readOnlyWithNetworkAccess,
                 .workspaceWrite:
                guard let sandboxType = getPlatformSandbox() else {
                    return .askUser
                }
                return .autoApprove(sandboxType: sandboxType, userExplicitlyApproved: false)
            }
        }

        if approvalPolicy == .never {
            return .reject(reason: "writing outside of the project; rejected by user approval settings")
        }

        return .askUser
    }

    public static func getPlatformSandbox() -> SandboxType? {
        #if os(macOS)
        return .macosSeatbelt
        #elseif os(Linux)
        return .linuxSeccomp
        #else
        return nil
        #endif
    }

    public static func isWritePatchConstrainedToWritablePaths(
        hunks: [Hunk],
        sandboxPolicy: SandboxPolicy,
        cwd: AbsolutePath,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> Bool {
        let writableRoots: [WritableRoot]
        switch sandboxPolicy {
        case .readOnly, .readOnlyWithNetworkAccess:
            return false
        case .dangerFullAccess,
             .externalSandbox:
            return true
        case .workspaceWrite:
            writableRoots = writableRootsWithCwd(
                sandboxPolicy: sandboxPolicy,
                cwd: cwd,
                environment: environment,
                fileManager: fileManager
            )
        }

        for hunk in hunks {
            switch hunk {
            case let .addFile(path, _),
                 let .deleteFile(path):
                guard isPathWritable(path, cwd: cwd, writableRoots: writableRoots) else {
                    return false
                }
            case let .updateFile(path, movePath, _):
                guard isPathWritable(path, cwd: cwd, writableRoots: writableRoots) else {
                    return false
                }
                if let movePath,
                   !isPathWritable(movePath, cwd: cwd, writableRoots: writableRoots)
                {
                    return false
                }
            }
        }

        return true
    }

    public static func writableRootsWithCwd(
        sandboxPolicy: SandboxPolicy,
        cwd: AbsolutePath,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> [WritableRoot] {
        guard case let .workspaceWrite(
            configuredRoots,
            _,
            excludeTmpdirEnvVar,
            excludeSlashTmp
        ) = sandboxPolicy else {
            return []
        }

        var roots = configuredRoots
        roots.append(cwd)

        #if os(macOS) || os(Linux)
        var slashTmpIsDirectory: ObjCBool = false
        if !excludeSlashTmp,
           fileManager.fileExists(atPath: "/tmp", isDirectory: &slashTmpIsDirectory),
           slashTmpIsDirectory.boolValue
        {
            if let slashTmp = try? AbsolutePath(absolutePath: "/tmp") {
                roots.append(slashTmp)
            }
        }
        #endif

        if !excludeTmpdirEnvVar,
           let tmpdir = environment["TMPDIR"],
           !tmpdir.isEmpty,
           let tmpdirPath = try? AbsolutePath(absolutePath: tmpdir)
        {
            roots.append(tmpdirPath)
        }

        return roots.map { root in
            WritableRoot(
                root: root,
                readOnlySubpaths: readOnlySubpaths(for: root, fileManager: fileManager)
            )
        }
    }

    private static func isPathWritable(
        _ path: String,
        cwd: AbsolutePath,
        writableRoots: [WritableRoot]
    ) -> Bool {
        guard let resolved = try? AbsolutePath.resolve(path, against: cwd.path) else {
            return false
        }

        return writableRoots.contains { $0.isPathWritable(resolved) }
    }

    private static func readOnlySubpaths(
        for root: AbsolutePath,
        fileManager: FileManager
    ) -> [AbsolutePath] {
        [".git", ".codex"].compactMap { path in
            var isDirectory: ObjCBool = false
            guard let child = try? root.join(path),
                  fileManager.fileExists(atPath: child.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                return nil
            }
            return child
        }
    }
}

private extension AbsolutePath {
    func isUnderOrEqual(_ root: AbsolutePath) -> Bool {
        path == root.path || path.hasPrefix(root.path.withTrailingSlash)
    }
}

private extension String {
    var withTrailingSlash: String {
        hasSuffix("/") ? self : self + "/"
    }

    func pathSuffix(after ancestor: String) -> String? {
        if self == ancestor {
            return ""
        }
        let prefix = ancestor.withTrailingSlash
        guard hasPrefix(prefix) else {
            return nil
        }
        return String(dropFirst(prefix.count))
    }
}
