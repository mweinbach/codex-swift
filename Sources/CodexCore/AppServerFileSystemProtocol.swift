public struct FsReadFileParams: Equatable, Codable, Sendable {
    public let path: AbsolutePath

    public init(path: AbsolutePath) {
        self.path = path
    }
}

public struct FsReadFileResponse: Equatable, Codable, Sendable {
    public let dataBase64: String

    public init(dataBase64: String) {
        self.dataBase64 = dataBase64
    }
}

public struct FsWriteFileParams: Equatable, Codable, Sendable {
    public let path: AbsolutePath
    public let dataBase64: String

    public init(path: AbsolutePath, dataBase64: String) {
        self.path = path
        self.dataBase64 = dataBase64
    }
}

public struct FsWriteFileResponse: Equatable, Codable, Sendable {
    public init() {}
}

public struct FsCreateDirectoryParams: Equatable, Sendable {
    public let path: AbsolutePath
    public let recursive: Bool?

    public init(path: AbsolutePath, recursive: Bool? = nil) {
        self.path = path
        self.recursive = recursive
    }
}

extension FsCreateDirectoryParams: Codable {
    private enum CodingKeys: String, CodingKey {
        case path
        case recursive
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(AbsolutePath.self, forKey: .path)
        recursive = try container.decodeIfPresent(Bool.self, forKey: .recursive)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encodeNilOrValue(recursive, forKey: .recursive)
    }
}

public struct FsCreateDirectoryResponse: Equatable, Codable, Sendable {
    public init() {}
}

public struct FsGetMetadataParams: Equatable, Codable, Sendable {
    public let path: AbsolutePath

    public init(path: AbsolutePath) {
        self.path = path
    }
}

public struct FsGetMetadataResponse: Equatable, Codable, Sendable {
    public let isDirectory: Bool
    public let isFile: Bool
    public let isSymlink: Bool
    public let createdAtMs: Int64
    public let modifiedAtMs: Int64

    public init(
        isDirectory: Bool,
        isFile: Bool,
        isSymlink: Bool,
        createdAtMs: Int64,
        modifiedAtMs: Int64
    ) {
        self.isDirectory = isDirectory
        self.isFile = isFile
        self.isSymlink = isSymlink
        self.createdAtMs = createdAtMs
        self.modifiedAtMs = modifiedAtMs
    }
}

public struct FsReadDirectoryParams: Equatable, Codable, Sendable {
    public let path: AbsolutePath

    public init(path: AbsolutePath) {
        self.path = path
    }
}

public struct FsReadDirectoryEntry: Equatable, Codable, Sendable {
    public let fileName: String
    public let isDirectory: Bool
    public let isFile: Bool

    public init(fileName: String, isDirectory: Bool, isFile: Bool) {
        self.fileName = fileName
        self.isDirectory = isDirectory
        self.isFile = isFile
    }
}

public struct FsReadDirectoryResponse: Equatable, Codable, Sendable {
    public let entries: [FsReadDirectoryEntry]

    public init(entries: [FsReadDirectoryEntry]) {
        self.entries = entries
    }
}

public struct FsRemoveParams: Equatable, Sendable {
    public let path: AbsolutePath
    public let recursive: Bool?
    public let force: Bool?

    public init(path: AbsolutePath, recursive: Bool? = nil, force: Bool? = nil) {
        self.path = path
        self.recursive = recursive
        self.force = force
    }
}

extension FsRemoveParams: Codable {
    private enum CodingKeys: String, CodingKey {
        case path
        case recursive
        case force
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(AbsolutePath.self, forKey: .path)
        recursive = try container.decodeIfPresent(Bool.self, forKey: .recursive)
        force = try container.decodeIfPresent(Bool.self, forKey: .force)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encodeNilOrValue(recursive, forKey: .recursive)
        try container.encodeNilOrValue(force, forKey: .force)
    }
}

public struct FsRemoveResponse: Equatable, Codable, Sendable {
    public init() {}
}

public struct FsCopyParams: Equatable, Sendable {
    public let sourcePath: AbsolutePath
    public let destinationPath: AbsolutePath
    public let recursive: Bool

    public init(sourcePath: AbsolutePath, destinationPath: AbsolutePath, recursive: Bool = false) {
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.recursive = recursive
    }
}

extension FsCopyParams: Codable {
    private enum CodingKeys: String, CodingKey {
        case sourcePath
        case destinationPath
        case recursive
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourcePath = try container.decode(AbsolutePath.self, forKey: .sourcePath)
        destinationPath = try container.decode(AbsolutePath.self, forKey: .destinationPath)
        recursive = try container.decodeIfPresent(Bool.self, forKey: .recursive) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourcePath, forKey: .sourcePath)
        try container.encode(destinationPath, forKey: .destinationPath)
        if recursive {
            try container.encode(recursive, forKey: .recursive)
        }
    }
}

public struct FsCopyResponse: Equatable, Codable, Sendable {
    public init() {}
}

public struct FsWatchParams: Equatable, Codable, Sendable {
    public let watchID: String
    public let path: AbsolutePath

    private enum CodingKeys: String, CodingKey {
        case watchID = "watchId"
        case path
    }

    public init(watchID: String, path: AbsolutePath) {
        self.watchID = watchID
        self.path = path
    }
}

public struct FsWatchResponse: Equatable, Codable, Sendable {
    public let path: AbsolutePath

    public init(path: AbsolutePath) {
        self.path = path
    }
}

public struct FsUnwatchParams: Equatable, Codable, Sendable {
    public let watchID: String

    private enum CodingKeys: String, CodingKey {
        case watchID = "watchId"
    }

    public init(watchID: String) {
        self.watchID = watchID
    }
}

public struct FsUnwatchResponse: Equatable, Codable, Sendable {
    public init() {}
}

public struct FsChangedNotification: Equatable, Codable, Sendable {
    public let watchID: String
    public let changedPaths: [AbsolutePath]

    private enum CodingKeys: String, CodingKey {
        case watchID = "watchId"
        case changedPaths
    }

    public init(watchID: String, changedPaths: [AbsolutePath]) {
        self.watchID = watchID
        self.changedPaths = changedPaths
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeNilOrValue<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}
