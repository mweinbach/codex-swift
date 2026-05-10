import Foundation

public struct CreateDirectoryOptions: Equatable, Sendable {
    public let recursive: Bool

    public init(recursive: Bool) {
        self.recursive = recursive
    }
}

public struct RemoveOptions: Equatable, Sendable {
    public let recursive: Bool
    public let force: Bool

    public init(recursive: Bool, force: Bool) {
        self.recursive = recursive
        self.force = force
    }
}

public struct CopyOptions: Equatable, Sendable {
    public let recursive: Bool

    public init(recursive: Bool) {
        self.recursive = recursive
    }
}

public struct FileMetadata: Equatable, Sendable {
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

    public init(_ response: ExecServerFsGetMetadataResponse) {
        self.init(
            isDirectory: response.isDirectory,
            isFile: response.isFile,
            isSymlink: response.isSymlink,
            createdAtMs: response.createdAtMs,
            modifiedAtMs: response.modifiedAtMs
        )
    }
}

public struct ReadDirectoryEntry: Equatable, Sendable {
    public let fileName: String
    public let isDirectory: Bool
    public let isFile: Bool

    public init(fileName: String, isDirectory: Bool, isFile: Bool) {
        self.fileName = fileName
        self.isDirectory = isDirectory
        self.isFile = isFile
    }

    public init(_ response: ExecServerFsReadDirectoryEntry) {
        self.init(
            fileName: response.fileName,
            isDirectory: response.isDirectory,
            isFile: response.isFile
        )
    }
}

public actor LazyRemoteExecServerClient {
    public typealias Connect = @Sendable () async throws -> ExecServerClient

    private let connect: Connect
    private var cachedClient: ExecServerClient?

    public init(
        transportParams: ExecServerTransportParams,
        notificationHandler: @escaping ExecServerLineClientTransport.NotificationHandler = { _ in }
    ) {
        self.connect = {
            try await ExecServerClient.connectForTransport(
                transportParams,
                notificationHandler: notificationHandler
            )
        }
    }

    public init(client: ExecServerClient) {
        self.cachedClient = client
        self.connect = { client }
    }

    public func get() async throws -> ExecServerClient {
        if let cachedClient {
            return cachedClient
        }
        let client = try await connect()
        cachedClient = client
        return client
    }
}

public struct ExecServerRemoteFileSystem: Sendable {
    private let client: LazyRemoteExecServerClient

    public init(client: ExecServerClient) {
        self.client = LazyRemoteExecServerClient(client: client)
    }

    public init(lazyClient: LazyRemoteExecServerClient) {
        self.client = lazyClient
    }

    public init(transportParams: ExecServerTransportParams) {
        self.client = LazyRemoteExecServerClient(transportParams: transportParams)
    }

    public func readFile(
        _ path: AbsolutePath,
        sandbox: FileSystemSandboxContext? = nil
    ) async throws -> Data {
        let client = try await client.get()
        let response = try await mapRemoteFileSystemError {
            try await client.readFile(ExecServerFsReadFileParams(
                path: path,
                sandbox: remoteSandboxContext(sandbox)
            ))
        }
        guard let data = Data(base64Encoded: response.dataBase64) else {
            throw ExecServerFileSystemError(
                kind: .invalidInput,
                message: "remote fs/readFile returned invalid base64 dataBase64: \(base64DecodeError(response.dataBase64))"
            )
        }
        return data
    }

    public func readFileText(
        _ path: AbsolutePath,
        sandbox: FileSystemSandboxContext? = nil
    ) async throws -> String {
        let data = try await readFile(path, sandbox: sandbox)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ExecServerFileSystemError(
                kind: .invalidInput,
                message: "remote fs/readFile returned invalid UTF-8 data"
            )
        }
        return text
    }

    public func writeFile(
        _ path: AbsolutePath,
        contents: Data,
        sandbox: FileSystemSandboxContext? = nil
    ) async throws {
        let client = try await client.get()
        _ = try await mapRemoteFileSystemError {
            try await client.writeFile(ExecServerFsWriteFileParams(
                path: path,
                dataBase64: contents.base64EncodedString(),
                sandbox: remoteSandboxContext(sandbox)
            ))
        }
    }

    public func createDirectory(
        _ path: AbsolutePath,
        options: CreateDirectoryOptions,
        sandbox: FileSystemSandboxContext? = nil
    ) async throws {
        let client = try await client.get()
        _ = try await mapRemoteFileSystemError {
            try await client.createDirectory(ExecServerFsCreateDirectoryParams(
                path: path,
                recursive: options.recursive,
                sandbox: remoteSandboxContext(sandbox)
            ))
        }
    }

    public func getMetadata(
        _ path: AbsolutePath,
        sandbox: FileSystemSandboxContext? = nil
    ) async throws -> FileMetadata {
        let client = try await client.get()
        let response = try await mapRemoteFileSystemError {
            try await client.getMetadata(ExecServerFsGetMetadataParams(
                path: path,
                sandbox: remoteSandboxContext(sandbox)
            ))
        }
        return FileMetadata(response)
    }

    public func readDirectory(
        _ path: AbsolutePath,
        sandbox: FileSystemSandboxContext? = nil
    ) async throws -> [ReadDirectoryEntry] {
        let client = try await client.get()
        let response = try await mapRemoteFileSystemError {
            try await client.readDirectory(ExecServerFsReadDirectoryParams(
                path: path,
                sandbox: remoteSandboxContext(sandbox)
            ))
        }
        return response.entries.map(ReadDirectoryEntry.init)
    }

    public func remove(
        _ path: AbsolutePath,
        options: RemoveOptions,
        sandbox: FileSystemSandboxContext? = nil
    ) async throws {
        let client = try await client.get()
        _ = try await mapRemoteFileSystemError {
            try await client.remove(ExecServerFsRemoveParams(
                path: path,
                recursive: options.recursive,
                force: options.force,
                sandbox: remoteSandboxContext(sandbox)
            ))
        }
    }

    public func copy(
        from sourcePath: AbsolutePath,
        to destinationPath: AbsolutePath,
        options: CopyOptions,
        sandbox: FileSystemSandboxContext? = nil
    ) async throws {
        let client = try await client.get()
        _ = try await mapRemoteFileSystemError {
            try await client.copy(ExecServerFsCopyParams(
                sourcePath: sourcePath,
                destinationPath: destinationPath,
                recursive: options.recursive,
                sandbox: remoteSandboxContext(sandbox)
            ))
        }
    }

    private func remoteSandboxContext(
        _ sandbox: FileSystemSandboxContext?
    ) -> FileSystemSandboxContext? {
        sandbox?.droppingCwdIfUnused()
    }

    private func mapRemoteFileSystemError<T>(
        _ operation: () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch let error as ExecServerClientError {
            switch error {
            case let .server(code, message) where code == -32004:
                throw ExecServerFileSystemError(kind: .notFound, message: message)
            case let .server(code, message) where code == -32600:
                throw ExecServerFileSystemError(kind: .invalidInput, message: message)
            case let .server(_, message):
                throw ExecServerFileSystemError(kind: .other, message: message)
            case .closed, .disconnected:
                throw ExecServerFileSystemError(kind: .other, message: "exec-server transport closed")
            default:
                throw ExecServerFileSystemError(kind: .other, message: error.description)
            }
        }
    }

    private func base64DecodeError(_ encoded: String) -> String {
        for (offset, byte) in encoded.utf8.enumerated() where !isBase64Byte(byte) {
            return "Invalid byte \(byte), offset \(offset)."
        }
        return "Invalid padding"
    }

    private func isBase64Byte(_ byte: UInt8) -> Bool {
        (byte >= 65 && byte <= 90)
            || (byte >= 97 && byte <= 122)
            || (byte >= 48 && byte <= 57)
            || byte == 43
            || byte == 47
            || byte == 61
    }
}

extension FileSystemSandboxContext {
    public func droppingCwdIfUnused() -> FileSystemSandboxContext {
        guard hasCwdDependentPermissions else {
            return FileSystemSandboxContext(
                permissions: permissions,
                cwd: nil,
                windowsSandboxLevel: windowsSandboxLevel,
                windowsSandboxPrivateDesktop: windowsSandboxPrivateDesktop,
                useLegacyLandlock: useLegacyLandlock
            )
        }
        return self
    }

    public var hasCwdDependentPermissions: Bool {
        guard case let .restricted(entries, _) = permissions.fileSystemSandboxPolicy else {
            return false
        }
        return entries.contains { entry in
            switch entry.path {
            case let .globPattern(pattern):
                return !pattern.hasPrefix("/")
            case let .special(value):
                guard case .projectRoots = FileSystemSpecialPath(jsonValue: value) else {
                    return false
                }
                return true
            case .path:
                return false
            }
        }
    }
}
