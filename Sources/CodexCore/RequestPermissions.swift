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
            self.init(
                entries: try container.decodeIfPresent([FileSystemSandboxEntry].self, forKey: .entries) ?? [],
                globScanMaxDepth: try container.decodeIfPresent(Int.self, forKey: .globScanMaxDepth)
            )
            return
        }

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
