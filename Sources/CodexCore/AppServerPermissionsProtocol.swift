import Foundation

public struct AppServerAdditionalNetworkPermissions: Codable, Equatable, Sendable {
    public let enabled: Bool?

    private enum CodingKeys: String, CodingKey {
        case enabled
    }

    public init(enabled: Bool? = nil) {
        self.enabled = enabled
    }

    public init(_ permissions: RequestPermissionNetworkPermissions) {
        self.init(enabled: permissions.enabled)
    }

    public var requestPermissions: RequestPermissionNetworkPermissions {
        RequestPermissionNetworkPermissions(enabled: enabled)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNilOrValue(enabled, forKey: .enabled)
    }
}

public struct AppServerPermissionProfileNetworkPermissions: Codable, Equatable, Sendable {
    public let enabled: Bool

    public init(enabled: Bool) {
        self.enabled = enabled
    }
}

public struct AppServerAdditionalFileSystemPermissions: Codable, Equatable, Sendable {
    public let read: [String]?
    public let write: [String]?
    public let globScanMaxDepth: Int?
    public let entries: [FileSystemSandboxEntry]?

    private enum CodingKeys: String, CodingKey {
        case read
        case write
        case globScanMaxDepth
        case entries
    }

    public init(
        read: [String]? = nil,
        write: [String]? = nil,
        globScanMaxDepth: Int? = nil,
        entries: [FileSystemSandboxEntry]? = nil
    ) {
        if let globScanMaxDepth {
            precondition(globScanMaxDepth > 0, "globScanMaxDepth must be nonzero")
        }
        self.read = read
        self.write = write
        self.globScanMaxDepth = globScanMaxDepth
        self.entries = entries
    }

    public init(_ permissions: FileSystemPermissions) {
        if let legacy = permissions.legacyReadWriteRoots {
            var entries: [FileSystemSandboxEntry] = []
            entries += (legacy.read ?? []).map { FileSystemSandboxEntry(path: .path($0), access: .read) }
            entries += (legacy.write ?? []).map { FileSystemSandboxEntry(path: .path($0), access: .write) }
            self.init(read: legacy.read, write: legacy.write, entries: entries)
        } else {
            self.init(
                globScanMaxDepth: permissions.globScanMaxDepth,
                entries: permissions.entries
            )
        }
    }

    public var fileSystemPermissions: FileSystemPermissions {
        if entries == nil, globScanMaxDepth == nil {
            return FileSystemPermissions(read: read, write: write)
        }

        let materializedEntries: [FileSystemSandboxEntry]
        if let entries {
            materializedEntries = entries
        } else {
            materializedEntries =
                (read ?? []).map { FileSystemSandboxEntry(path: .path($0), access: .read) }
                + (write ?? []).map { FileSystemSandboxEntry(path: .path($0), access: .write) }
        }
        return FileSystemPermissions(entries: materializedEntries, globScanMaxDepth: globScanMaxDepth)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let globScanMaxDepth = try container.decodeIfPresent(Int.self, forKey: .globScanMaxDepth)
        if let globScanMaxDepth, globScanMaxDepth <= 0 {
            throw DecodingError.dataCorruptedError(
                forKey: .globScanMaxDepth,
                in: container,
                debugDescription: "globScanMaxDepth must be nonzero"
            )
        }
        self.init(
            read: try container.decodeIfPresent([String].self, forKey: .read),
            write: try container.decodeIfPresent([String].self, forKey: .write),
            globScanMaxDepth: globScanMaxDepth,
            entries: try container.decodeIfPresent([FileSystemSandboxEntry].self, forKey: .entries)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNilOrValue(read, forKey: .read)
        try container.encodeNilOrValue(write, forKey: .write)
        try container.encodeIfPresent(globScanMaxDepth, forKey: .globScanMaxDepth)
        try container.encodeIfPresent(entries, forKey: .entries)
    }
}

public enum AppServerPermissionProfileFileSystemPermissions: Codable, Equatable, Sendable {
    case restricted(entries: [FileSystemSandboxEntry], globScanMaxDepth: Int? = nil)
    case unrestricted

    private enum CodingKeys: String, CodingKey {
        case type
        case entries
        case globScanMaxDepth
    }

    private enum ProfileType: String, Codable {
        case restricted
        case unrestricted
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ProfileType.self, forKey: .type) {
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
            try container.encode(ProfileType.restricted, forKey: .type)
            try container.encode(entries, forKey: .entries)
            try container.encodeIfPresent(globScanMaxDepth, forKey: .globScanMaxDepth)
        case .unrestricted:
            try container.encode(ProfileType.unrestricted, forKey: .type)
        }
    }
}

public enum AppServerPermissionProfile: Codable, Equatable, Sendable {
    case managed(
        network: AppServerPermissionProfileNetworkPermissions,
        fileSystem: AppServerPermissionProfileFileSystemPermissions
    )
    case disabled
    case external(network: AppServerPermissionProfileNetworkPermissions)

    private enum CodingKeys: String, CodingKey {
        case type
        case network
        case fileSystem
    }

    private enum ProfileType: String, Codable {
        case managed
        case disabled
        case external
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ProfileType.self, forKey: .type) {
        case .managed:
            self = .managed(
                network: try container.decode(AppServerPermissionProfileNetworkPermissions.self, forKey: .network),
                fileSystem: try container.decode(AppServerPermissionProfileFileSystemPermissions.self, forKey: .fileSystem)
            )
        case .disabled:
            self = .disabled
        case .external:
            self = .external(
                network: try container.decode(AppServerPermissionProfileNetworkPermissions.self, forKey: .network)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .managed(network, fileSystem):
            try container.encode(ProfileType.managed, forKey: .type)
            try container.encode(network, forKey: .network)
            try container.encode(fileSystem, forKey: .fileSystem)
        case .disabled:
            try container.encode(ProfileType.disabled, forKey: .type)
        case let .external(network):
            try container.encode(ProfileType.external, forKey: .type)
            try container.encode(network, forKey: .network)
        }
    }
}

public struct AppServerActivePermissionProfile: Codable, Equatable, Sendable {
    public let id: String
    public let extends: String?
    public let modifications: [AppServerActivePermissionProfileModification]

    private enum CodingKeys: String, CodingKey {
        case id
        case extends
        case modifications
    }

    public init(
        id: String,
        extends: String? = nil,
        modifications: [AppServerActivePermissionProfileModification] = []
    ) {
        self.id = id
        self.extends = extends
        self.modifications = modifications
    }

    public init(_ profile: ActivePermissionProfile) {
        self.init(
            id: profile.id,
            extends: profile.extends,
            modifications: profile.modifications.map(AppServerActivePermissionProfileModification.init)
        )
    }

    public var activePermissionProfile: ActivePermissionProfile {
        ActivePermissionProfile(
            id: id,
            extends: extends,
            modifications: modifications.map(\.activePermissionProfileModification)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeNilOrValue(extends, forKey: .extends)
        try container.encode(modifications, forKey: .modifications)
    }
}

public enum AppServerActivePermissionProfileModification: Codable, Equatable, Sendable {
    case additionalWritableRoot(path: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case path
    }

    private enum ModificationType: String, Codable {
        case additionalWritableRoot
    }

    public init(_ modification: ActivePermissionProfileModification) {
        switch modification {
        case let .additionalWritableRoot(path):
            self = .additionalWritableRoot(path: path)
        }
    }

    public var activePermissionProfileModification: ActivePermissionProfileModification {
        switch self {
        case let .additionalWritableRoot(path):
            return .additionalWritableRoot(path: path)
        }
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

public enum AppServerPermissionProfileSelectionParams: Codable, Equatable, Sendable {
    case profile(id: String, modifications: [AppServerPermissionProfileModificationParams]? = nil)

    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case modifications
    }

    private enum SelectionType: String, Codable {
        case profile
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(SelectionType.self, forKey: .type) {
        case .profile:
            self = .profile(
                id: try container.decode(String.self, forKey: .id),
                modifications: try container.decodeIfPresent(
                    [AppServerPermissionProfileModificationParams].self,
                    forKey: .modifications
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .profile(id, modifications):
            try container.encode(SelectionType.profile, forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encodeNilOrValue(modifications, forKey: .modifications)
        }
    }
}

public enum AppServerPermissionProfileModificationParams: Codable, Equatable, Sendable {
    case additionalWritableRoot(path: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case path
    }

    private enum ModificationType: String, Codable {
        case additionalWritableRoot
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

private extension KeyedEncodingContainer {
    mutating func encodeNilOrValue<Value: Encodable>(_ value: Value?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}
