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
