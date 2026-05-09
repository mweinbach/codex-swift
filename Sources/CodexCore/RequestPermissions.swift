import Foundation

public enum PermissionGrantScope: String, Codable, Equatable, Sendable {
    case turn
    case session
}

public struct RequestPermissionNetworkPermissions: Codable, Equatable, Sendable {
    public let enabled: Bool?

    public init(enabled: Bool? = nil) {
        self.enabled = enabled
    }
}

public enum FileSystemAccessMode: String, Codable, Equatable, Sendable {
    case read
    case write
    case none

    public var canRead: Bool {
        self != .none
    }

    public var canWrite: Bool {
        self == .write
    }

    fileprivate var precedence: Int {
        switch self {
        case .none:
            return 0
        case .read:
            return 1
        case .write:
            return 2
        }
    }
}

public enum FileSystemSandboxPolicyError: Error, Equatable, CustomStringConvertible, Sendable {
    case unbridgeableWritesOutsideWorkspace

    public var description: String {
        switch self {
        case .unbridgeableWritesOutsideWorkspace:
            return "permissions profile requests filesystem writes outside the workspace root, which is not supported until the runtime enforces FileSystemSandboxPolicy directly"
        }
    }
}

public enum FileSystemPath: Equatable, Codable, Sendable {
    case path(String)
    case globPattern(String)
    case special(JSONValue)

    private enum CodingKeys: String, CodingKey {
        case type
        case path
        case pattern
        case value
    }

    private enum PathType: String, Codable {
        case path
        case globPattern = "glob_pattern"
        case special
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(PathType.self, forKey: .type) {
        case .path:
            self = .path(try container.decode(String.self, forKey: .path))
        case .globPattern:
            self = .globPattern(try container.decode(String.self, forKey: .pattern))
        case .special:
            self = .special(try container.decode(JSONValue.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .path(path):
            try container.encode(PathType.path, forKey: .type)
            try container.encode(path, forKey: .path)
        case let .globPattern(pattern):
            try container.encode(PathType.globPattern, forKey: .type)
            try container.encode(pattern, forKey: .pattern)
        case let .special(value):
            try container.encode(PathType.special, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}

public enum FileSystemSpecialPath: Equatable, Sendable {
    case root
    case minimal
    case projectRoots(subpath: String?)
    case tmpdir
    case slashTmp
    case unknown(path: String, subpath: String?)

    public init(jsonValue: JSONValue) {
        guard case let .object(object) = jsonValue,
              case let .string(kind)? = object["kind"]
        else {
            self = .unknown(path: "unknown", subpath: nil)
            return
        }

        let subpath: String? = {
            guard case let .string(value)? = object["subpath"] else {
                return nil
            }
            return value
        }()

        switch kind {
        case "root":
            self = .root
        case "minimal":
            self = .minimal
        case "project_roots", "current_working_directory":
            self = .projectRoots(subpath: subpath)
        case "tmpdir":
            self = .tmpdir
        case "slash_tmp":
            self = .slashTmp
        default:
            let path: String
            if case let .string(value)? = object["path"] {
                path = value
            } else {
                path = kind
            }
            self = .unknown(path: path, subpath: subpath)
        }
    }

    public var jsonValue: JSONValue {
        switch self {
        case .root:
            return .object(["kind": .string("root")])
        case .minimal:
            return .object(["kind": .string("minimal")])
        case let .projectRoots(subpath):
            return Self.object(kind: "project_roots", subpath: subpath)
        case .tmpdir:
            return .object(["kind": .string("tmpdir")])
        case .slashTmp:
            return .object(["kind": .string("slash_tmp")])
        case let .unknown(path, subpath):
            var object: [String: JSONValue] = [
                "kind": .string("unknown"),
                "path": .string(path)
            ]
            if let subpath {
                object["subpath"] = .string(subpath)
            }
            return .object(object)
        }
    }

    private static func object(kind: String, subpath: String?) -> JSONValue {
        var object: [String: JSONValue] = ["kind": .string(kind)]
        if let subpath {
            object["subpath"] = .string(subpath)
        }
        return .object(object)
    }
}

public struct FileSystemSandboxEntry: Codable, Equatable, Sendable {
    public let path: FileSystemPath
    public let access: FileSystemAccessMode

    public init(path: FileSystemPath, access: FileSystemAccessMode) {
        self.path = path
        self.access = access
    }
}

public struct FileSystemPermissions: Codable, Equatable, Sendable {
    public let entries: [FileSystemSandboxEntry]
    public let globScanMaxDepth: Int?

    private enum CodingKeys: String, CodingKey {
        case entries
        case globScanMaxDepth = "glob_scan_max_depth"
        case read
        case write
    }

    public init(entries: [FileSystemSandboxEntry] = [], globScanMaxDepth: Int? = nil) {
        if let globScanMaxDepth {
            precondition(globScanMaxDepth > 0, "globScanMaxDepth must be nonzero")
        }
        self.entries = entries
        self.globScanMaxDepth = globScanMaxDepth
    }

    public init(read: [String]? = nil, write: [String]? = nil) {
        var entries: [FileSystemSandboxEntry] = []
        entries += (read ?? []).map { FileSystemSandboxEntry(path: .path($0), access: .read) }
        entries += (write ?? []).map { FileSystemSandboxEntry(path: .path($0), access: .write) }
        self.init(entries: entries)
    }

    public var isEmpty: Bool {
        entries.isEmpty
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.entries) || container.contains(.globScanMaxDepth) {
            try Self.rejectUnknownKeys(in: decoder, allowed: ["entries", "glob_scan_max_depth"])
            let globScanMaxDepth = try container.decodeIfPresent(Int.self, forKey: .globScanMaxDepth)
            if let globScanMaxDepth, globScanMaxDepth <= 0 {
                throw DecodingError.dataCorruptedError(
                    forKey: .globScanMaxDepth,
                    in: container,
                    debugDescription: "glob_scan_max_depth must be nonzero"
                )
            }
            self.init(
                entries: try container.decodeIfPresent([FileSystemSandboxEntry].self, forKey: .entries) ?? [],
                globScanMaxDepth: globScanMaxDepth
            )
            return
        }

        try Self.rejectUnknownKeys(in: decoder, allowed: ["read", "write"])
        self.init(
            read: try container.decodeIfPresent([String].self, forKey: .read),
            write: try container.decodeIfPresent([String].self, forKey: .write)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let legacy = legacyReadWriteRoots {
            try container.encodeIfPresent(legacy.read, forKey: .read)
            try container.encodeIfPresent(legacy.write, forKey: .write)
            return
        }

        if !entries.isEmpty {
            try container.encode(entries, forKey: .entries)
        }
        try container.encodeIfPresent(globScanMaxDepth, forKey: .globScanMaxDepth)
    }

    public var legacyReadWriteRoots: (read: [String]?, write: [String]?)? {
        guard globScanMaxDepth == nil else {
            return nil
        }

        var read: [String] = []
        var write: [String] = []
        for entry in entries {
            guard case let .path(path) = entry.path else {
                return nil
            }
            switch entry.access {
            case .read:
                read.append(path)
            case .write:
                write.append(path)
            case .none:
                return nil
            }
        }

        return (read.isEmpty ? nil : read, write.isEmpty ? nil : write)
    }

    private static func rejectUnknownKeys(in decoder: Decoder, allowed: Set<String>) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        if let unknown = container.allKeys.first(where: { !allowed.contains($0.stringValue) }) {
            throw DecodingError.keyNotFound(
                unknown,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown field '\(unknown.stringValue)'"
                )
            )
        }
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

public enum ActivePermissionProfileModification: Equatable, Codable, Sendable {
    case additionalWritableRoot(path: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case path
    }

    private enum ModificationType: String, Codable {
        case additionalWritableRoot = "additional_writable_root"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ModificationType.self, forKey: .type) {
        case .additionalWritableRoot:
            self = .additionalWritableRoot(path: try container.decode(String.self, forKey: .path))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .additionalWritableRoot(path):
            try container.encode(ModificationType.additionalWritableRoot, forKey: .type)
            try container.encode(path, forKey: .path)
        }
    }
}

public struct ActivePermissionProfile: Codable, Equatable, Sendable {
    public let id: String
    public let extends: String?
    public let modifications: [ActivePermissionProfileModification]

    private enum CodingKeys: String, CodingKey {
        case id
        case extends
        case modifications
    }

    public init(
        id: String,
        extends: String? = nil,
        modifications: [ActivePermissionProfileModification] = []
    ) {
        self.id = id
        self.extends = extends
        self.modifications = modifications
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        extends = try container.decodeIfPresent(String.self, forKey: .extends)
        modifications = try container.decodeIfPresent(
            [ActivePermissionProfileModification].self,
            forKey: .modifications
        ) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(extends, forKey: .extends)
        if !modifications.isEmpty {
            try container.encode(modifications, forKey: .modifications)
        }
    }
}

public enum NetworkSandboxPolicy: String, Codable, Equatable, Sendable {
    case restricted
    case enabled

    public var isEnabled: Bool {
        self == .enabled
    }

    public static func fromLegacySandboxPolicy(_ sandboxPolicy: SandboxPolicy) -> NetworkSandboxPolicy {
        sandboxPolicy.hasFullNetworkAccess ? .enabled : .restricted
    }
}

public enum SandboxEnforcement: String, Codable, Equatable, Sendable {
    case managed
    case disabled
    case external

    public static func fromLegacySandboxPolicy(_ sandboxPolicy: SandboxPolicy) -> SandboxEnforcement {
        switch sandboxPolicy {
        case .dangerFullAccess:
            return .disabled
        case .externalSandbox:
            return .external
        case .readOnly, .workspaceWrite:
            return .managed
        }
    }
}

public enum ManagedFileSystemPermissions: Equatable, Codable, Sendable {
    case restricted(entries: [FileSystemSandboxEntry], globScanMaxDepth: Int? = nil)
    case unrestricted

    private enum CodingKeys: String, CodingKey {
        case type
        case entries
        case globScanMaxDepth = "glob_scan_max_depth"
    }

    private enum PermissionType: String, Codable {
        case restricted
        case unrestricted
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(PermissionType.self, forKey: .type) {
        case .restricted:
            self = .restricted(
                entries: try container.decode([FileSystemSandboxEntry].self, forKey: .entries),
                globScanMaxDepth: try container.decodeIfPresent(Int.self, forKey: .globScanMaxDepth)
            )
        case .unrestricted:
            self = .unrestricted
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .restricted(entries, globScanMaxDepth):
            try container.encode(PermissionType.restricted, forKey: .type)
            try container.encode(entries, forKey: .entries)
            try container.encodeIfPresent(globScanMaxDepth, forKey: .globScanMaxDepth)
        case .unrestricted:
            try container.encode(PermissionType.unrestricted, forKey: .type)
        }
    }

    public static func readOnly() -> ManagedFileSystemPermissions {
        .restricted(entries: [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .read)
        ])
    }

    public static func workspaceWrite(
        writableRoots: [AbsolutePath] = [],
        excludeTmpdirEnvVar: Bool = false,
        excludeSlashTmp: Bool = false
    ) -> ManagedFileSystemPermissions {
        var entries: [FileSystemSandboxEntry] = [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .read),
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.projectRoots(subpath: nil).jsonValue), access: .write)
        ]

        if !excludeSlashTmp {
            entries.append(FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.slashTmp.jsonValue), access: .write))
        }
        if !excludeTmpdirEnvVar {
            entries.append(FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.tmpdir.jsonValue), access: .write))
        }
        entries.append(contentsOf: writableRoots.map {
            FileSystemSandboxEntry(path: .path($0.path), access: .write)
        })

        appendDefaultReadOnlyProjectRootSubpath(".git", to: &entries)
        appendDefaultReadOnlyProjectRootSubpath(".agents", to: &entries)
        appendDefaultReadOnlyProjectRootSubpath(".codex", to: &entries)
        for writableRoot in writableRoots {
            appendDefaultReadOnlyPath(writableRoot.path + "/.git", to: &entries)
            appendDefaultReadOnlyPath(writableRoot.path + "/.agents", to: &entries)
            appendDefaultReadOnlyPath(writableRoot.path + "/.codex", to: &entries)
        }

        return .restricted(entries: entries)
    }

    private static func appendDefaultReadOnlyProjectRootSubpath(_ subpath: String, to entries: inout [FileSystemSandboxEntry]) {
        let path = FileSystemPath.special(FileSystemSpecialPath.projectRoots(subpath: subpath).jsonValue)
        appendReadOnlyPath(path, to: &entries)
    }

    private static func appendDefaultReadOnlyPath(_ path: String, to entries: inout [FileSystemSandboxEntry]) {
        appendReadOnlyPath(.path(path), to: &entries)
    }

    private static func appendReadOnlyPath(_ path: FileSystemPath, to entries: inout [FileSystemSandboxEntry]) {
        guard !entries.contains(where: { $0.path == path }) else {
            return
        }
        entries.append(FileSystemSandboxEntry(path: path, access: .read))
    }
}

public enum FileSystemSandboxPolicy: Equatable, Sendable {
    case restricted(entries: [FileSystemSandboxEntry], globScanMaxDepth: Int? = nil)
    case unrestricted
    case externalSandbox

    private static let protectedMetadataGitPathName = ".git"
    private static let protectedMetadataAgentsPathName = ".agents"
    private static let protectedMetadataCodexPathName = ".codex"

    public var hasDeniedReadRestrictions: Bool {
        guard case let .restricted(entries, _) = self else {
            return false
        }
        return entries.contains { $0.access == .none }
    }

    public mutating func preserveDenyReadRestrictions(from existing: FileSystemSandboxPolicy) {
        guard existing.hasDeniedReadRestrictions else {
            return
        }

        if self == .unrestricted {
            self = .restricted(entries: [
                FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .write)
            ])
        }

        guard case let .restricted(currentEntries, globScanMaxDepth) = self,
              case let .restricted(existingEntries, existingGlobScanMaxDepth) = existing
        else {
            return
        }

        var entries = currentEntries
        let effectiveGlobScanMaxDepth = globScanMaxDepth ?? existingGlobScanMaxDepth
        for entry in existingEntries where entry.access == .none && !entries.contains(entry) {
            entries.append(entry)
        }
        self = .restricted(entries: entries, globScanMaxDepth: effectiveGlobScanMaxDepth)
    }

    public static func fromLegacySandboxPolicyForCwd(
        _ sandboxPolicy: SandboxPolicy,
        cwd: String
    ) -> FileSystemSandboxPolicy {
        switch sandboxPolicy {
        case .dangerFullAccess:
            return .unrestricted
        case .externalSandbox:
            return .externalSandbox
        case .readOnly:
            return .restricted(entries: [
                FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .read)
            ])
        case let .workspaceWrite(writableRoots, _, excludeTmpdirEnvVar, excludeSlashTmp):
            var entries: [FileSystemSandboxEntry] = [
                FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .read),
                FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.projectRoots(subpath: nil).jsonValue), access: .write)
            ]

            if !excludeSlashTmp {
                entries.append(FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.slashTmp.jsonValue), access: .write))
            }
            if !excludeTmpdirEnvVar {
                entries.append(FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.tmpdir.jsonValue), access: .write))
            }

            entries.append(contentsOf: writableRoots.map {
                FileSystemSandboxEntry(path: .path($0.path), access: .write)
            })

            appendDefaultReadOnlyProjectRootSubpathIfNoExplicitRule(".git", to: &entries)
            appendDefaultReadOnlyProjectRootSubpathIfNoExplicitRule(".agents", to: &entries)
            appendDefaultReadOnlyProjectRootSubpathIfNoExplicitRule(".codex", to: &entries)

            for writableRoot in writableRoots {
                for protectedPath in defaultReadOnlySubpathsForWritableRoot(writableRoot, protectMissingDotCodex: false) {
                    appendDefaultReadOnlyPathIfNoExplicitRule(protectedPath, to: &entries)
                }
            }

            if let cwdRoot = absolutePathForLegacyCwd(cwd) {
                for protectedPath in defaultReadOnlySubpathsForWritableRoot(cwdRoot, protectMissingDotCodex: true) {
                    appendDefaultReadOnlyPathIfNoExplicitRule(protectedPath, to: &entries)
                }
            }

            for writableRoot in writableRoots {
                for protectedPath in defaultReadOnlySubpathsForWritableRoot(writableRoot, protectMissingDotCodex: false) {
                    appendDefaultReadOnlyPathIfNoExplicitRule(protectedPath, to: &entries)
                }
            }

            return .restricted(entries: entries)
        }
    }

    public static func fromLegacySandboxPolicyPreservingDenyEntries(
        _ sandboxPolicy: SandboxPolicy,
        cwd: String,
        existing: FileSystemSandboxPolicy
    ) -> FileSystemSandboxPolicy {
        let rebuilt = fromLegacySandboxPolicyForCwd(sandboxPolicy, cwd: cwd)
        guard case let .restricted(entries, _) = rebuilt else {
            return rebuilt
        }

        var preservedEntries = entries
        let existingGlobScanMaxDepth: Int?
        if case let .restricted(existingEntries, globScanMaxDepth) = existing {
            existingGlobScanMaxDepth = globScanMaxDepth
            for denyEntry in existingEntries where denyEntry.access == .none && !preservedEntries.contains(denyEntry) {
                preservedEntries.append(denyEntry)
            }
        } else {
            existingGlobScanMaxDepth = nil
        }

        return .restricted(entries: preservedEntries, globScanMaxDepth: existingGlobScanMaxDepth)
    }

    public var hasFullDiskReadAccess: Bool {
        switch self {
        case .unrestricted, .externalSandbox:
            return true
        case let .restricted(entries, _):
            return entries.contains(where: { entry in
                entry.access.canRead && entry.path.isRootSpecialPath
            }) && !hasDeniedReadRestrictions
        }
    }

    public var hasFullDiskWriteAccess: Bool {
        switch self {
        case .unrestricted, .externalSandbox:
            return true
        case let .restricted(entries, _):
            return entries.contains(where: { entry in
                entry.access.canWrite && entry.path.isRootSpecialPath
            }) && !hasWriteNarrowingEntries(entries)
        }
    }

    public var includePlatformDefaults: Bool {
        guard case let .restricted(entries, _) = self,
              !hasFullDiskReadAccess
        else {
            return false
        }

        return entries.contains { entry in
            entry.access.canRead && entry.path.isMinimalSpecialPath
        }
    }

    public func resolveAccessWithCwd(path: String, cwd: String) -> FileSystemAccessMode {
        switch self {
        case .unrestricted, .externalSandbox:
            return .write
        case let .restricted(entries, _):
            guard let target = Self.resolveCandidatePath(path, cwd: cwd) else {
                return .none
            }

            return resolvedEntriesWithCwd(entries, cwd: cwd)
                .filter { target.isUnderOrEqual($0.path) }
                .max { lhs, rhs in
                    let lhsKey = (lhs.path.pathComponentCount, lhs.access.precedence)
                    let rhsKey = (rhs.path.pathComponentCount, rhs.access.precedence)
                    return lhsKey < rhsKey
                }?
                .access ?? .none
        }
    }

    public func canReadPathWithCwd(_ path: String, cwd: String) -> Bool {
        resolveAccessWithCwd(path: path, cwd: cwd).canRead
    }

    public func canWritePathWithCwd(_ path: String, cwd: String) -> Bool {
        guard resolveAccessWithCwd(path: path, cwd: cwd).canWrite else {
            return false
        }
        if hasFullDiskWriteAccess {
            return true
        }
        return !isMetadataWriteDenied(path, cwd: cwd)
    }

    public func getReadableRootsWithCwd(_ cwd: String) -> [AbsolutePath] {
        guard case let .restricted(entries, _) = self,
              !hasFullDiskReadAccess
        else {
            return []
        }

        let roots = resolvedEntriesWithCwd(entries, cwd: cwd)
            .filter { $0.access.canRead }
            .filter { canReadPathWithCwd($0.path.path, cwd: cwd) }
            .map(\.path)
        return Self.deduplicated(roots)
    }

    public func getUnreadableRootsWithCwd(_ cwd: String) -> [AbsolutePath] {
        guard case let .restricted(entries, _) = self else {
            return []
        }

        let root = try? AbsolutePath(absolutePath: "/")
        let roots = resolvedEntriesWithCwd(entries, cwd: cwd)
            .filter { $0.access == .none }
            .filter { !canReadPathWithCwd($0.path.path, cwd: cwd) }
            .filter { root != $0.path }
            .map(\.path)
        return Self.deduplicated(roots)
    }

    public func getUnreadableGlobsWithCwd(_ cwd: String) -> [String] {
        guard case let .restricted(entries, _) = self else {
            return []
        }

        var patterns = entries.compactMap { entry -> String? in
            guard entry.access == .none,
                  case let .globPattern(pattern) = entry.path,
                  let resolved = try? AbsolutePath.resolve(pattern, against: cwd)
            else {
                return nil
            }
            return resolved.path
        }
        patterns.sort()
        return patterns.reduce(into: []) { result, pattern in
            if result.last != pattern {
                result.append(pattern)
            }
        }
    }

    public func toLegacySandboxPolicy(
        networkPolicy: NetworkSandboxPolicy,
        cwd: String
    ) throws -> SandboxPolicy {
        switch self {
        case .externalSandbox:
            return .externalSandbox(networkAccess: networkPolicy.isEnabled ? .enabled : .restricted)
        case .unrestricted:
            if networkPolicy.isEnabled {
                return .dangerFullAccess
            }
            return .externalSandbox(networkAccess: .restricted)
        case let .restricted(entries, _):
            let cwdPath = Self.absolutePathForLegacyCwd(cwd)
            let fullDiskWrite = hasFullDiskWriteAccess
            var workspaceRootWritable = false
            var writableRoots: [AbsolutePath] = []
            var tmpdirWritable = false
            var slashTmpWritable = false
            var unbridgeableRootWrite = false

            for entry in entries {
                switch entry.path {
                case .globPattern:
                    continue
                case let .path(path):
                    guard entry.access.canWrite,
                          let absolutePath = try? AbsolutePath(absolutePath: path)
                    else {
                        continue
                    }
                    if cwdPath == absolutePath {
                        workspaceRootWritable = true
                    } else {
                        writableRoots.append(absolutePath)
                    }
                case let .special(value):
                    switch FileSystemSpecialPath(jsonValue: value) {
                    case .root:
                        if entry.access.canWrite {
                            unbridgeableRootWrite = true
                        }
                    case .minimal, .unknown:
                        continue
                    case let .projectRoots(subpath):
                        if subpath == nil && entry.access.canWrite {
                            workspaceRootWritable = true
                        } else if entry.access.canWrite,
                                  let resolvedPath = Self.resolveFileSystemPath(entry.path, cwd: cwdPath)
                        {
                            writableRoots.append(resolvedPath)
                        }
                    case .tmpdir:
                        if entry.access.canWrite {
                            tmpdirWritable = true
                        }
                    case .slashTmp:
                        if entry.access.canWrite {
                            slashTmpWritable = true
                        }
                    }
                }
            }

            if fullDiskWrite {
                if networkPolicy.isEnabled {
                    return .dangerFullAccess
                }
                return .externalSandbox(networkAccess: .restricted)
            }

            if workspaceRootWritable {
                return .workspaceWrite(
                    writableRoots: Self.deduplicated(writableRoots),
                    networkAccess: networkPolicy.isEnabled,
                    excludeTmpdirEnvVar: !tmpdirWritable,
                    excludeSlashTmp: !slashTmpWritable
                )
            }

            if unbridgeableRootWrite || !writableRoots.isEmpty || tmpdirWritable || slashTmpWritable {
                throw FileSystemSandboxPolicyError.unbridgeableWritesOutsideWorkspace
            }

            return .readOnly
        }
    }

    public func withAdditionalReadableRoots(
        _ additionalReadableRoots: [AbsolutePath],
        cwd: String
    ) -> FileSystemSandboxPolicy {
        guard case let .restricted(currentEntries, globScanMaxDepth) = self,
              !hasFullDiskReadAccess
        else {
            return self
        }

        var entries = currentEntries
        for path in additionalReadableRoots where !canReadPathWithCwd(path.path, cwd: cwd) {
            entries.append(FileSystemSandboxEntry(path: .path(path.path), access: .read))
        }

        return .restricted(entries: entries, globScanMaxDepth: globScanMaxDepth)
    }

    public func withAdditionalWritableRoots(
        _ additionalWritableRoots: [AbsolutePath],
        cwd: String
    ) -> FileSystemSandboxPolicy {
        guard case let .restricted(currentEntries, globScanMaxDepth) = self else {
            return self
        }

        var entries = currentEntries
        for path in additionalWritableRoots where !canWritePathWithCwd(path.path, cwd: cwd) {
            entries.append(FileSystemSandboxEntry(path: .path(path.path), access: .write))
        }

        return .restricted(entries: entries, globScanMaxDepth: globScanMaxDepth)
    }

    public func withAdditionalLegacyWorkspaceWritableRoots(_ additionalWritableRoots: [AbsolutePath]) -> FileSystemSandboxPolicy {
        guard case let .restricted(currentEntries, globScanMaxDepth) = self else {
            return self
        }

        var entries = currentEntries
        for path in additionalWritableRoots {
            let rootEntry = FileSystemSandboxEntry(path: .path(path.path), access: .write)
            if !entries.contains(where: { $0.access.canWrite && $0.path == rootEntry.path }) {
                entries.append(rootEntry)
            }

            for protectedPath in Self.defaultReadOnlySubpathsForWritableRoot(path, protectMissingDotCodex: false) {
                Self.appendDefaultReadOnlyPathIfNoExplicitRule(protectedPath, to: &entries)
            }
        }

        return .restricted(entries: entries, globScanMaxDepth: globScanMaxDepth)
    }

    public func materializeProjectRootsWithCwd(_ cwd: String) -> FileSystemSandboxPolicy {
        guard case let .restricted(currentEntries, globScanMaxDepth) = self,
              let cwdPath = Self.absolutePathForLegacyCwd(cwd)
        else {
            return self
        }

        let entries = currentEntries.map { entry in
            guard case let .special(value) = entry.path,
                  case let .projectRoots(subpath) = FileSystemSpecialPath(jsonValue: value)
            else {
                return entry
            }

            let resolvedPath = subpath.flatMap { try? cwdPath.join($0) } ?? cwdPath
            return FileSystemSandboxEntry(path: .path(resolvedPath.path), access: entry.access)
        }

        return .restricted(entries: entries, globScanMaxDepth: globScanMaxDepth)
    }

    private static func appendDefaultReadOnlyProjectRootSubpathIfNoExplicitRule(
        _ subpath: String,
        to entries: inout [FileSystemSandboxEntry]
    ) {
        let path = FileSystemPath.special(FileSystemSpecialPath.projectRoots(subpath: subpath).jsonValue)
        guard !entries.contains(where: { $0.path == path }) else {
            return
        }
        entries.append(FileSystemSandboxEntry(path: path, access: .read))
    }

    private func isMetadataWriteDenied(_ path: String, cwd: String) -> Bool {
        guard case let .restricted(entries, _) = self,
              let target = Self.resolveCandidatePath(path, cwd: cwd)
        else {
            return false
        }

        let resolvedEntries = resolvedEntriesWithCwd(entries, cwd: cwd)
        for writableRoot in resolvedEntries where writableRoot.access.canWrite {
            for metadataName in Self.protectedMetadataPathNames {
                guard let protectedPath = try? writableRoot.path.join(metadataName),
                      target.isUnderOrEqual(protectedPath)
                else {
                    continue
                }

                if hasExplicitWriteEntryForMetadataPath(
                    protectedPath,
                    target: target,
                    resolvedEntries: resolvedEntries
                ) {
                    return false
                }
                return true
            }
        }

        return false
    }

    private func hasExplicitWriteEntryForMetadataPath(
        _ protectedPath: AbsolutePath,
        target: AbsolutePath,
        resolvedEntries: [ResolvedFileSystemEntry]
    ) -> Bool {
        resolvedEntries.contains { entry in
            entry.access.canWrite
                && entry.path.isUnderOrEqual(protectedPath)
                && target.isUnderOrEqual(entry.path)
        }
    }

    private static func defaultReadOnlySubpathsForWritableRoot(
        _ writableRoot: AbsolutePath,
        protectMissingDotCodex: Bool
    ) -> [AbsolutePath] {
        var subpaths: [AbsolutePath] = []

        if let topLevelGit = try? writableRoot.join(protectedMetadataGitPathName),
           fileExists(atPath: topLevelGit.path) {
            if isFile(atPath: topLevelGit.path),
               let gitDir = resolveGitDirFromFile(topLevelGit) {
                subpaths.append(gitDir)
            }
            subpaths.append(topLevelGit)
        }

        if let topLevelAgents = try? writableRoot.join(protectedMetadataAgentsPathName),
           isDirectory(atPath: topLevelAgents.path) {
            subpaths.append(topLevelAgents)
        }

        if let topLevelCodex = try? writableRoot.join(protectedMetadataCodexPathName),
           protectMissingDotCodex || isDirectory(atPath: topLevelCodex.path) {
            subpaths.append(topLevelCodex)
        }

        return deduplicated(subpaths)
    }

    private static func appendDefaultReadOnlyPathIfNoExplicitRule(
        _ path: AbsolutePath,
        to entries: inout [FileSystemSandboxEntry]
    ) {
        let fileSystemPath = FileSystemPath.path(path.path)
        guard !entries.contains(where: { $0.path == fileSystemPath }) else {
            return
        }
        entries.append(FileSystemSandboxEntry(path: fileSystemPath, access: .read))
    }

    private static func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    private static func isFile(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    private static func isDirectory(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func resolveGitDirFromFile(_ dotGit: AbsolutePath) -> AbsolutePath? {
        guard let contents = try? String(contentsOfFile: dotGit.path, encoding: .utf8) else {
            return nil
        }

        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0].trimmingCharacters(in: .whitespaces) == "gitdir"
        else {
            return nil
        }

        let rawGitDir = parts[1].trimmingCharacters(in: .whitespaces)
        guard !rawGitDir.isEmpty,
              let base = dotGit.parent,
              let gitDir = try? AbsolutePath.resolve(rawGitDir, against: base.path),
              fileExists(atPath: gitDir.path)
        else {
            return nil
        }

        return gitDir
    }

    private static func absolutePathForLegacyCwd(_ cwd: String) -> AbsolutePath? {
        if cwd.hasPrefix("/") {
            return try? AbsolutePath(absolutePath: cwd)
        }
        return try? AbsolutePath.resolve(cwd, against: FileManager.default.currentDirectoryPath)
    }

    private static func resolveCandidatePath(_ path: String, cwd: String) -> AbsolutePath? {
        try? AbsolutePath.resolve(path, against: cwd)
    }

    private func resolvedEntriesWithCwd(
        _ entries: [FileSystemSandboxEntry],
        cwd: String
    ) -> [ResolvedFileSystemEntry] {
        let cwdPath = Self.absolutePathForLegacyCwd(cwd)
        return entries.compactMap { entry in
            guard let resolvedPath = Self.resolveEntryPath(entry.path, cwd: cwdPath) else {
                return nil
            }
            return ResolvedFileSystemEntry(path: resolvedPath, access: entry.access)
        }
    }

    private static func resolveEntryPath(_ path: FileSystemPath, cwd: AbsolutePath?) -> AbsolutePath? {
        if path.isRootSpecialPath {
            return try? AbsolutePath(absolutePath: "/")
        }
        return resolveFileSystemPath(path, cwd: cwd)
    }

    private static func resolveFileSystemPath(_ path: FileSystemPath, cwd: AbsolutePath?) -> AbsolutePath? {
        switch path {
        case let .path(path):
            return try? AbsolutePath(absolutePath: path)
        case .globPattern:
            return nil
        case let .special(value):
            switch FileSystemSpecialPath(jsonValue: value) {
            case .root, .minimal, .unknown:
                return nil
            case let .projectRoots(subpath):
                guard let cwd else {
                    return nil
                }
                return subpath.flatMap { try? cwd.join($0) } ?? cwd
            case .tmpdir:
                guard let tmpdir = ProcessInfo.processInfo.environment["TMPDIR"],
                      !tmpdir.isEmpty
                else {
                    return nil
                }
                return try? AbsolutePath(absolutePath: tmpdir)
            case .slashTmp:
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: "/tmp", isDirectory: &isDirectory),
                      isDirectory.boolValue
                else {
                    return nil
                }
                return try? AbsolutePath(absolutePath: "/tmp")
            }
        }
    }

    private func hasWriteNarrowingEntries(_ entries: [FileSystemSandboxEntry]) -> Bool {
        entries.contains { entry in
            guard !entry.access.canWrite else {
                return false
            }

            switch entry.path {
            case .path:
                return !hasSameTargetWriteOverride(for: entry, in: entries)
            case .globPattern:
                return true
            case let .special(value):
                switch FileSystemSpecialPath(jsonValue: value) {
                case .root:
                    return entry.access == .none
                case .minimal, .unknown:
                    return false
                case .projectRoots, .tmpdir, .slashTmp:
                    return !hasSameTargetWriteOverride(for: entry, in: entries)
                }
            }
        }
    }

    private func hasSameTargetWriteOverride(
        for entry: FileSystemSandboxEntry,
        in entries: [FileSystemSandboxEntry]
    ) -> Bool {
        entries.contains { candidate in
            candidate.access.canWrite
                && candidate.access.precedence > entry.access.precedence
                && candidate.path.sharesTarget(with: entry.path)
        }
    }

    private static func deduplicated(_ paths: [AbsolutePath]) -> [AbsolutePath] {
        var seen: Set<AbsolutePath> = []
        var result: [AbsolutePath] = []
        for path in paths where seen.insert(path).inserted {
            result.append(path)
        }
        return result
    }

    private static let protectedMetadataPathNames = [
        protectedMetadataGitPathName,
        protectedMetadataAgentsPathName,
        protectedMetadataCodexPathName
    ]
}

private struct ResolvedFileSystemEntry: Equatable {
    let path: AbsolutePath
    let access: FileSystemAccessMode
}

private extension FileSystemPath {
    var isRootSpecialPath: Bool {
        guard case let .special(value) = self,
              case .root = FileSystemSpecialPath(jsonValue: value)
        else {
            return false
        }
        return true
    }

    var isMinimalSpecialPath: Bool {
        guard case let .special(value) = self,
              case .minimal = FileSystemSpecialPath(jsonValue: value)
        else {
            return false
        }
        return true
    }

    func sharesTarget(with other: FileSystemPath) -> Bool {
        switch (self, other) {
        case let (.path(left), .path(right)):
            return left == right
        case let (.special(left), .special(right)):
            return FileSystemSpecialPath(jsonValue: left) == FileSystemSpecialPath(jsonValue: right)
        case let (.globPattern(left), .globPattern(right)):
            return left == right
        default:
            return false
        }
    }
}

private extension AbsolutePath {
    func isUnderOrEqual(_ root: AbsolutePath) -> Bool {
        path == root.path || path.hasPrefix(root.path.withTrailingSlash)
    }

    var pathComponentCount: Int {
        path.split(separator: "/", omittingEmptySubsequences: true).count
    }
}

private extension String {
    var withTrailingSlash: String {
        hasSuffix("/") ? self : self + "/"
    }
}

extension FileSystemSandboxPolicy: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case globScanMaxDepth = "glob_scan_max_depth"
        case entries
    }

    private enum Kind: String, Codable {
        case restricted
        case unrestricted
        case externalSandbox = "external-sandbox"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .restricted:
            self = .restricted(
                entries: try container.decodeIfPresent([FileSystemSandboxEntry].self, forKey: .entries) ?? [],
                globScanMaxDepth: try container.decodeIfPresent(Int.self, forKey: .globScanMaxDepth)
            )
        case .unrestricted:
            self = .unrestricted
        case .externalSandbox:
            self = .externalSandbox
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .restricted(entries, globScanMaxDepth):
            try container.encode(Kind.restricted, forKey: .kind)
            try container.encodeIfPresent(globScanMaxDepth, forKey: .globScanMaxDepth)
            try container.encode(entries, forKey: .entries)
        case .unrestricted:
            try container.encode(Kind.unrestricted, forKey: .kind)
        case .externalSandbox:
            try container.encode(Kind.externalSandbox, forKey: .kind)
        }
    }
}

public extension ManagedFileSystemPermissions {
    static func fromSandboxPolicy(_ policy: FileSystemSandboxPolicy) -> ManagedFileSystemPermissions? {
        switch policy {
        case let .restricted(entries, globScanMaxDepth):
            return .restricted(entries: entries, globScanMaxDepth: globScanMaxDepth)
        case .unrestricted:
            return .unrestricted
        case .externalSandbox:
            return nil
        }
    }

    var fileSystemSandboxPolicy: FileSystemSandboxPolicy {
        switch self {
        case let .restricted(entries, globScanMaxDepth):
            return .restricted(entries: entries, globScanMaxDepth: globScanMaxDepth)
        case .unrestricted:
            return .unrestricted
        }
    }
}

public enum PermissionProfile: Equatable, Codable, Sendable {
    case managed(fileSystem: ManagedFileSystemPermissions, network: NetworkSandboxPolicy)
    case disabled
    case external(network: NetworkSandboxPolicy)

    private enum CodingKeys: String, CodingKey {
        case type
        case fileSystem = "file_system"
        case network
    }

    private enum ProfileType: String, Codable {
        case managed
        case disabled
        case external
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let type = try container.decodeIfPresent(ProfileType.self, forKey: .type) {
            switch type {
            case .managed:
                self = .managed(
                    fileSystem: try container.decode(ManagedFileSystemPermissions.self, forKey: .fileSystem),
                    network: try container.decode(NetworkSandboxPolicy.self, forKey: .network)
                )
            case .disabled:
                self = .disabled
            case .external:
                self = .external(network: try container.decode(NetworkSandboxPolicy.self, forKey: .network))
            }
            return
        }

        let network = try container.decodeIfPresent(
            RequestPermissionNetworkPermissions.self,
            forKey: .network
        )
        let fileSystem = try container.decodeIfPresent(FileSystemPermissions.self, forKey: .fileSystem)
        let entries = fileSystem?.entries ?? []
        let globScanMaxDepth = fileSystem?.globScanMaxDepth
        let networkPolicy: NetworkSandboxPolicy = network?.enabled == true ? .enabled : .restricted
        self = .managed(
            fileSystem: .restricted(entries: entries, globScanMaxDepth: globScanMaxDepth),
            network: networkPolicy
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .managed(fileSystem, network):
            try container.encode(ProfileType.managed, forKey: .type)
            try container.encode(fileSystem, forKey: .fileSystem)
            try container.encode(network, forKey: .network)
        case .disabled:
            try container.encode(ProfileType.disabled, forKey: .type)
        case let .external(network):
            try container.encode(ProfileType.external, forKey: .type)
            try container.encode(network, forKey: .network)
        }
    }

    public var enforcement: SandboxEnforcement {
        switch self {
        case .managed:
            return .managed
        case .disabled:
            return .disabled
        case .external:
            return .external
        }
    }

    public var networkSandboxPolicy: NetworkSandboxPolicy {
        switch self {
        case let .managed(_, network),
             let .external(network):
            return network
        case .disabled:
            return .enabled
        }
    }

    public var fileSystemSandboxPolicy: FileSystemSandboxPolicy {
        switch self {
        case let .managed(fileSystem, _):
            return fileSystem.fileSystemSandboxPolicy
        case .disabled:
            return .unrestricted
        case .external:
            return .externalSandbox
        }
    }

    public var runtimePermissions: (fileSystem: FileSystemSandboxPolicy, network: NetworkSandboxPolicy) {
        (fileSystemSandboxPolicy, networkSandboxPolicy)
    }

    public static func readOnly() -> PermissionProfile {
        .managed(fileSystem: .readOnly(), network: .restricted)
    }

    public static func workspaceWrite() -> PermissionProfile {
        workspaceWriteWith()
    }

    public static func workspaceWriteWith(
        writableRoots: [AbsolutePath] = [],
        network: NetworkSandboxPolicy = .restricted,
        excludeTmpdirEnvVar: Bool = false,
        excludeSlashTmp: Bool = false
    ) -> PermissionProfile {
        .managed(
            fileSystem: .workspaceWrite(
                writableRoots: writableRoots,
                excludeTmpdirEnvVar: excludeTmpdirEnvVar,
                excludeSlashTmp: excludeSlashTmp
            ),
            network: network
        )
    }

    public static func fromLegacySandboxPolicy(_ sandboxPolicy: SandboxPolicy) -> PermissionProfile {
        switch sandboxPolicy {
        case .dangerFullAccess:
            return .disabled
        case let .externalSandbox(networkAccess):
            return .external(network: networkAccess.isEnabled ? .enabled : .restricted)
        case .readOnly:
            return .readOnly()
        case let .workspaceWrite(writableRoots, networkAccess, excludeTmpdirEnvVar, excludeSlashTmp):
            return .workspaceWriteWith(
                writableRoots: writableRoots,
                network: networkAccess ? .enabled : .restricted,
                excludeTmpdirEnvVar: excludeTmpdirEnvVar,
                excludeSlashTmp: excludeSlashTmp
            )
        }
    }

    public static func fromLegacySandboxPolicyForCwd(
        _ sandboxPolicy: SandboxPolicy,
        cwd: String
    ) -> PermissionProfile {
        fromRuntimePermissionsWithEnforcement(
            SandboxEnforcement.fromLegacySandboxPolicy(sandboxPolicy),
            fileSystem: FileSystemSandboxPolicy.fromLegacySandboxPolicyForCwd(sandboxPolicy, cwd: cwd),
            network: NetworkSandboxPolicy.fromLegacySandboxPolicy(sandboxPolicy)
        )
    }

    public static func fromRuntimePermissions(
        fileSystem: FileSystemSandboxPolicy,
        network: NetworkSandboxPolicy
    ) -> PermissionProfile {
        let enforcement: SandboxEnforcement
        switch fileSystem {
        case .restricted, .unrestricted:
            enforcement = .managed
        case .externalSandbox:
            enforcement = .external
        }
        return fromRuntimePermissionsWithEnforcement(enforcement, fileSystem: fileSystem, network: network)
    }

    public static func fromRuntimePermissionsWithEnforcement(
        _ enforcement: SandboxEnforcement,
        fileSystem: FileSystemSandboxPolicy,
        network: NetworkSandboxPolicy
    ) -> PermissionProfile {
        switch fileSystem {
        case .externalSandbox:
            return .external(network: network)
        case .unrestricted where enforcement == .disabled:
            return .disabled
        case .restricted, .unrestricted:
            return .managed(
                fileSystem: ManagedFileSystemPermissions.fromSandboxPolicy(fileSystem) ?? .unrestricted,
                network: network
            )
        }
    }
}

public struct RequestPermissionProfile: Codable, Equatable, Sendable {
    public let network: RequestPermissionNetworkPermissions?
    public let fileSystem: FileSystemPermissions?

    private enum CodingKeys: String, CodingKey {
        case network
        case fileSystem = "file_system"
    }

    public init(network: RequestPermissionNetworkPermissions? = nil, fileSystem: FileSystemPermissions? = nil) {
        self.network = network
        self.fileSystem = fileSystem
    }

    public var isEmpty: Bool {
        network == nil && fileSystem == nil
    }
}

public struct RequestPermissionsArgs: Codable, Equatable, Sendable {
    public let reason: String?
    public let permissions: RequestPermissionProfile

    public init(reason: String? = nil, permissions: RequestPermissionProfile) {
        self.reason = reason
        self.permissions = permissions
    }
}

public struct RequestPermissionsResponse: Codable, Equatable, Sendable {
    public let permissions: RequestPermissionProfile
    public let scope: PermissionGrantScope
    public let strictAutoReview: Bool

    private enum CodingKeys: String, CodingKey {
        case permissions
        case scope
        case strictAutoReview = "strict_auto_review"
    }

    public init(
        permissions: RequestPermissionProfile,
        scope: PermissionGrantScope = .turn,
        strictAutoReview: Bool = false
    ) {
        self.permissions = permissions
        self.scope = scope
        self.strictAutoReview = strictAutoReview
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        permissions = try container.decode(RequestPermissionProfile.self, forKey: .permissions)
        scope = try container.decodeIfPresent(PermissionGrantScope.self, forKey: .scope) ?? .turn
        strictAutoReview = try container.decodeIfPresent(Bool.self, forKey: .strictAutoReview) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(permissions, forKey: .permissions)
        try container.encode(scope, forKey: .scope)
        if strictAutoReview {
            try container.encode(strictAutoReview, forKey: .strictAutoReview)
        }
    }
}

public struct RequestPermissionsEvent: Codable, Equatable, Sendable {
    public let callID: String
    public let turnID: String
    public let startedAtMilliseconds: Int64
    public let reason: String?
    public let permissions: RequestPermissionProfile
    public let cwd: String?

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case turnID = "turn_id"
        case startedAtMilliseconds = "started_at_ms"
        case reason
        case permissions
        case cwd
    }

    public init(
        callID: String,
        turnID: String = "",
        startedAtMilliseconds: Int64,
        reason: String? = nil,
        permissions: RequestPermissionProfile,
        cwd: String? = nil
    ) {
        self.callID = callID
        self.turnID = turnID
        self.startedAtMilliseconds = startedAtMilliseconds
        self.reason = reason
        self.permissions = permissions
        self.cwd = cwd
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callID = try container.decode(String.self, forKey: .callID)
        turnID = try container.decodeIfPresent(String.self, forKey: .turnID) ?? ""
        startedAtMilliseconds = try container.decode(Int64.self, forKey: .startedAtMilliseconds)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        permissions = try container.decode(RequestPermissionProfile.self, forKey: .permissions)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
    }
}
