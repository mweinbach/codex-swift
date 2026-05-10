import Darwin
import Foundation

public struct ExecServerFileSystem: Sendable {
    private static let maxReadFileBytes: UInt64 = 512 * 1024 * 1024

    public init() {}

    public func readFile(_ params: ExecServerFsReadFileParams) throws -> ExecServerFsReadFileResponse {
        try rejectSandboxHelperRequirement(params.sandbox)
        let attributes = try fileAttributes(at: params.path)
        if let size = attributes[.size] as? NSNumber, size.uint64Value > Self.maxReadFileBytes {
            throw ExecServerFileSystemError(
                kind: .invalidInput,
                message: "file is too large to read: limit is \(Self.maxReadFileBytes) bytes"
            )
        }
        let data = try fileSystemCall { try Data(contentsOf: fileURL(params.path), options: []) }
        return ExecServerFsReadFileResponse(dataBase64: data.base64EncodedString())
    }

    public func writeFile(_ params: ExecServerFsWriteFileParams) throws -> ExecServerFsWriteFileResponse {
        try rejectSandboxHelperRequirement(params.sandbox)
        guard let data = Data(base64Encoded: params.dataBase64) else {
            throw ExecServerRPC.invalidRequest(
                "\(execServerFsWriteFileMethod) requires valid base64 dataBase64: \(base64DecodeError(params.dataBase64))"
            )
        }
        try fileSystemCall { try data.write(to: fileURL(params.path), options: []) }
        return ExecServerFsWriteFileResponse()
    }

    public func createDirectory(_ params: ExecServerFsCreateDirectoryParams) throws -> ExecServerFsCreateDirectoryResponse {
        try rejectSandboxHelperRequirement(params.sandbox)
        try fileSystemCall {
            try FileManager.default.createDirectory(
                at: fileURL(params.path),
                withIntermediateDirectories: params.recursive ?? true
            )
        }
        return ExecServerFsCreateDirectoryResponse()
    }

    public func getMetadata(_ params: ExecServerFsGetMetadataParams) throws -> ExecServerFsGetMetadataResponse {
        try rejectSandboxHelperRequirement(params.sandbox)
        let attributes = try fileAttributes(at: params.path)
        let symlinkAttributes = try symlinkAttributes(at: params.path)
        let type = attributes[.type] as? FileAttributeType
        let symlinkType = symlinkAttributes[.type] as? FileAttributeType
        return ExecServerFsGetMetadataResponse(
            isDirectory: type == .typeDirectory,
            isFile: type == .typeRegular,
            isSymlink: symlinkType == .typeSymbolicLink,
            createdAtMs: unixMilliseconds(attributes[.creationDate] as? Date),
            modifiedAtMs: unixMilliseconds(attributes[.modificationDate] as? Date)
        )
    }

    public func readDirectory(_ params: ExecServerFsReadDirectoryParams) throws -> ExecServerFsReadDirectoryResponse {
        try rejectSandboxHelperRequirement(params.sandbox)
        let contents = try fileSystemCall {
            try FileManager.default.contentsOfDirectory(
                at: fileURL(params.path),
                includingPropertiesForKeys: nil
            )
        }
        let entries = contents.compactMap { url -> ExecServerFsReadDirectoryEntry? in
            guard let attributes = try? statAttributes(atPath: url.path, followSymlinks: true),
                  let type = attributes[.type] as? FileAttributeType else {
                return nil
            }
            return ExecServerFsReadDirectoryEntry(
                fileName: url.lastPathComponent,
                isDirectory: type == .typeDirectory,
                isFile: type == .typeRegular
            )
        }
        return ExecServerFsReadDirectoryResponse(entries: entries)
    }

    public func remove(_ params: ExecServerFsRemoveParams) throws -> ExecServerFsRemoveResponse {
        try rejectSandboxHelperRequirement(params.sandbox)
        do {
            let symlinkAttributes = try symlinkAttributes(at: params.path)
            let type = symlinkAttributes[.type] as? FileAttributeType
            if type == .typeDirectory, params.recursive ?? true {
                try fileSystemCall { try FileManager.default.removeItem(at: fileURL(params.path)) }
            } else {
                try fileSystemCall { try FileManager.default.removeItem(at: fileURL(params.path)) }
            }
        } catch let error as ExecServerFileSystemError where error.kind == .notFound && params.force ?? true {
            return ExecServerFsRemoveResponse()
        }
        return ExecServerFsRemoveResponse()
    }

    public func copy(_ params: ExecServerFsCopyParams) throws -> ExecServerFsCopyResponse {
        try rejectSandboxHelperRequirement(params.sandbox)
        let sourceAttributes = try symlinkAttributes(at: params.sourcePath)
        let sourceType = sourceAttributes[.type] as? FileAttributeType
        if sourceType == .typeDirectory {
            if !params.recursive {
                throw ExecServerFileSystemError(
                    kind: .invalidInput,
                    message: "fs/copy requires recursive: true when sourcePath is a directory"
                )
            }
            if try destinationIsSameOrDescendantOfSource(
                source: params.sourcePath.path,
                destination: params.destinationPath.path
            ) {
                throw ExecServerFileSystemError(
                    kind: .invalidInput,
                    message: "fs/copy cannot copy a directory to itself or one of its descendants"
                )
            }
            try copyDirectory(source: params.sourcePath.path, destination: params.destinationPath.path)
            return ExecServerFsCopyResponse()
        }
        if sourceType == .typeSymbolicLink {
            try copySymlink(source: params.sourcePath.path, destination: params.destinationPath.path)
            return ExecServerFsCopyResponse()
        }
        if sourceType == .typeRegular {
            try fileSystemCall {
                try FileManager.default.copyItem(
                    at: fileURL(params.sourcePath),
                    to: fileURL(params.destinationPath)
                )
            }
            return ExecServerFsCopyResponse()
        }
        throw ExecServerFileSystemError(
            kind: .invalidInput,
            message: "fs/copy only supports regular files, directories, and symlinks"
        )
    }

    private func rejectSandboxHelperRequirement(_ sandbox: FileSystemSandboxContext?) throws {
        guard sandbox?.shouldRunInSandbox == true else {
            return
        }
        throw ExecServerFileSystemError(
            kind: .invalidInput,
            message: "sandboxed filesystem operations require configured runtime paths"
        )
    }

    private func fileAttributes(at path: AbsolutePath) throws -> [FileAttributeKey: Any] {
        try statAttributes(atPath: path.path, followSymlinks: true)
    }

    private func symlinkAttributes(at path: AbsolutePath) throws -> [FileAttributeKey: Any] {
        try statAttributes(atPath: path.path, followSymlinks: false)
    }

    private func copyDirectory(source: String, destination: String) throws {
        try fileSystemCall {
            try FileManager.default.createDirectory(
                atPath: destination,
                withIntermediateDirectories: true
            )
            let entries = try FileManager.default.contentsOfDirectory(atPath: source)
            for entry in entries {
                let sourcePath = (source as NSString).appendingPathComponent(entry)
                let destinationPath = (destination as NSString).appendingPathComponent(entry)
                let attributes = try statAttributes(atPath: sourcePath, followSymlinks: false)
                let type = attributes[.type] as? FileAttributeType
                if type == .typeDirectory {
                    try copyDirectory(source: sourcePath, destination: destinationPath)
                } else if type == .typeSymbolicLink {
                    try copySymlink(source: sourcePath, destination: destinationPath)
                } else if type == .typeRegular {
                    try FileManager.default.copyItem(
                        atPath: sourcePath,
                        toPath: destinationPath
                    )
                }
            }
        }
    }

    private func copySymlink(source: String, destination: String) throws {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let count = readlink(source, &buffer, buffer.count)
        if count < 0 {
            throw posixFileSystemError()
        }
        let target = String(decoding: buffer.prefix(count).map(UInt8.init(bitPattern:)), as: UTF8.self)
        try fileSystemCall {
            try FileManager.default.createSymbolicLink(atPath: destination, withDestinationPath: target)
        }
    }

    private func statAttributes(atPath path: String, followSymlinks: Bool) throws -> [FileAttributeKey: Any] {
        var statBuffer = stat()
        let result = path.withCString { pathPointer in
            followSymlinks ? stat(pathPointer, &statBuffer) : lstat(pathPointer, &statBuffer)
        }
        guard result == 0 else {
            throw posixFileSystemError()
        }
        return [
            .type: fileAttributeType(mode: statBuffer.st_mode),
            .creationDate: Date(
                timeIntervalSince1970: TimeInterval(statBuffer.st_birthtimespec.tv_sec)
                    + TimeInterval(statBuffer.st_birthtimespec.tv_nsec) / 1_000_000_000
            ),
            .modificationDate: Date(
                timeIntervalSince1970: TimeInterval(statBuffer.st_mtimespec.tv_sec)
                    + TimeInterval(statBuffer.st_mtimespec.tv_nsec) / 1_000_000_000
            ),
            .size: NSNumber(value: statBuffer.st_size)
        ]
    }

    private func fileAttributeType(mode: mode_t) -> FileAttributeType {
        switch mode & S_IFMT {
        case S_IFDIR:
            return .typeDirectory
        case S_IFREG:
            return .typeRegular
        case S_IFLNK:
            return .typeSymbolicLink
        default:
            return .typeUnknown
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

    private func destinationIsSameOrDescendantOfSource(source: String, destination: String) throws -> Bool {
        let resolvedSource = try resolveExistingPath(source)
        let resolvedDestination = try resolveExistingPath(destination)
        return resolvedDestination == resolvedSource || resolvedDestination.hasPrefix(resolvedSource + "/")
    }

    private func resolveExistingPath(_ path: String) throws -> String {
        var suffix: [String] = []
        var existing = path
        while !FileManager.default.fileExists(atPath: existing) {
            let name = (existing as NSString).lastPathComponent
            if name.isEmpty || name == "/" {
                break
            }
            suffix.append(name)
            let parent = (existing as NSString).deletingLastPathComponent
            if parent == existing || parent.isEmpty {
                break
            }
            existing = parent
        }
        let resolved = try fileSystemCall {
            URL(fileURLWithPath: existing).resolvingSymlinksInPath().path
        }
        return suffix.reversed().reduce(resolved) { partial, name in
            (partial as NSString).appendingPathComponent(name)
        }
    }

    private func fileURL(_ path: AbsolutePath) -> URL {
        URL(fileURLWithPath: path.path)
    }

    private func unixMilliseconds(_ date: Date?) -> Int64 {
        guard let date else {
            return 0
        }
        return Int64((date.timeIntervalSince1970 * 1000).rounded(.down))
    }

    private func fileSystemCall<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let error as ExecServerFileSystemError {
            throw error
        } catch {
            throw mapFileSystemError(error)
        }
    }

    private func posixFileSystemError() -> ExecServerFileSystemError {
        ExecServerFileSystemError(kind: .other, message: String(cString: strerror(errno)))
    }

    private func mapFileSystemError(_ error: Error) -> ExecServerFileSystemError {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileNoSuchFileError:
                return ExecServerFileSystemError(kind: .notFound, message: nsError.localizedDescription)
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
                return ExecServerFileSystemError(kind: .permissionDenied, message: nsError.localizedDescription)
            default:
                return ExecServerFileSystemError(kind: .other, message: nsError.localizedDescription)
            }
        }
        if nsError.domain == NSPOSIXErrorDomain {
            switch nsError.code {
            case Int(ENOENT):
                return ExecServerFileSystemError(kind: .notFound, message: String(cString: strerror(ENOENT)))
            case Int(EINVAL):
                return ExecServerFileSystemError(kind: .invalidInput, message: String(cString: strerror(EINVAL)))
            case Int(EACCES), Int(EPERM):
                return ExecServerFileSystemError(kind: .permissionDenied, message: String(cString: strerror(Int32(nsError.code))))
            default:
                return ExecServerFileSystemError(kind: .other, message: nsError.localizedDescription)
            }
        }
        return ExecServerFileSystemError(kind: .other, message: String(describing: error))
    }
}

public struct ExecServerFileSystemError: Error, Equatable, CustomStringConvertible, Sendable {
    public enum Kind: Equatable, Sendable {
        case notFound
        case invalidInput
        case permissionDenied
        case other
    }

    public let kind: Kind
    public let message: String

    public init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }

    public var description: String {
        message
    }

    public var rpcError: ExecServerJSONRPCErrorDetail {
        switch kind {
        case .notFound:
            return ExecServerRPC.notFound(message)
        case .invalidInput, .permissionDenied:
            return ExecServerRPC.invalidRequest(message)
        case .other:
            return ExecServerRPC.internalError(message)
        }
    }
}

extension FileSystemSandboxContext {
    public var shouldRunInSandbox: Bool {
        permissions.enforcement == .managed
    }
}
