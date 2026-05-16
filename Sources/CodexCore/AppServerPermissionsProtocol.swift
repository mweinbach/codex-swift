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
        let read = try container.decodeIfPresent([String].self, forKey: .read)
        let write = try container.decodeIfPresent([String].self, forKey: .write)
        try Self.validateAbsolutePaths(read, forKey: .read, in: container)
        try Self.validateAbsolutePaths(write, forKey: .write, in: container)
        self.init(
            read: read,
            write: write,
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

    private static func validateAbsolutePaths(
        _ paths: [String]?,
        forKey key: CodingKeys,
        in container: KeyedDecodingContainer<CodingKeys>
    ) throws {
        guard let paths else {
            return
        }

        for path in paths {
            try FileSystemPath.validateAbsolutePath(path, forKey: key, in: container)
        }
    }
}

public struct AppServerActivePermissionProfile: Codable, Equatable, Sendable {
    public let id: String
    public let extends: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case extends
    }

    public init(
        id: String,
        extends: String? = nil
    ) {
        self.id = id
        self.extends = extends
    }

    public init(_ profile: ActivePermissionProfile) {
        self.init(
            id: profile.id,
            extends: profile.extends
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        extends = try container.decodeIfPresent(String.self, forKey: .extends)
    }

    public var activePermissionProfile: ActivePermissionProfile {
        ActivePermissionProfile(
            id: id,
            extends: extends
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeNilOrValue(extends, forKey: .extends)
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
        if let id = try? decoder.singleValueContainer().decode(String.self) {
            self = .profile(id: id)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _ = try container.decode(SelectionType.self, forKey: .type)
        self = .profile(
            id: try container.decode(String.self, forKey: .id),
            modifications: try container.decodeIfPresent(
                [AppServerPermissionProfileModificationParams].self,
                forKey: .modifications
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .profile(id, _):
            try container.encode(id)
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
