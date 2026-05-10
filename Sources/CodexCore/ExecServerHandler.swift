import Foundation

public actor ExecServerHandler {
    private let sessionRegistry: ExecServerSessionRegistry
    private let fileSystem: ExecServerFileSystem
    private var session: ExecServerSessionHandle?
    private var initializeRequested = false
    private var initialized = false

    public init(
        sessionRegistry: ExecServerSessionRegistry = ExecServerSessionRegistry(),
        fileSystem: ExecServerFileSystem = ExecServerFileSystem()
    ) {
        self.sessionRegistry = sessionRegistry
        self.fileSystem = fileSystem
    }

    public func initialize(_ params: ExecServerInitializeParams) async throws -> ExecServerInitializeResponse {
        if initializeRequested {
            throw ExecServerRPC.invalidRequest("initialize may only be sent once per connection")
        }

        initializeRequested = true
        do {
            let session = try await sessionRegistry.attach(resumeSessionID: params.resumeSessionId)
            self.session = session
            return ExecServerInitializeResponse(sessionId: session.sessionID)
        } catch {
            initializeRequested = false
            throw error
        }
    }

    public func markInitialized() async throws {
        if !initializeRequested {
            throw ExecServerHandlerNotificationError("received `initialized` notification before `initialize`")
        }

        do {
            _ = try await requireSessionAttached()
        } catch let error as ExecServerJSONRPCErrorDetail {
            throw ExecServerHandlerNotificationError(error.message)
        }

        initialized = true
    }

    public func isSessionAttached() async -> Bool {
        guard let session else {
            return true
        }
        return await session.isSessionAttached()
    }

    public func shutdown() async {
        guard let session else {
            return
        }
        await session.detach()
    }

    public func requireInitialized(for methodFamily: String) async throws -> ExecServerSessionHandle {
        if !initializeRequested {
            throw ExecServerRPC.invalidRequest("client must call initialize before using \(methodFamily) methods")
        }

        let session = try await requireSessionAttached()
        if !initialized {
            throw ExecServerRPC.invalidRequest("client must send initialized before using \(methodFamily) methods")
        }
        return session
    }

    private func requireSessionAttached() async throws -> ExecServerSessionHandle {
        guard let session else {
            throw ExecServerRPC.invalidRequest("client must call initialize before using methods")
        }
        if await session.isSessionAttached() {
            return session
        }
        throw ExecServerRPC.invalidRequest("session has been resumed by another connection")
    }

    public func readFile(_ params: ExecServerFsReadFileParams) async throws -> ExecServerFsReadFileResponse {
        _ = try await requireInitialized(for: "filesystem")
        return try fileSystem.readFile(params)
    }

    public func writeFile(_ params: ExecServerFsWriteFileParams) async throws -> ExecServerFsWriteFileResponse {
        _ = try await requireInitialized(for: "filesystem")
        return try fileSystem.writeFile(params)
    }

    public func createDirectory(_ params: ExecServerFsCreateDirectoryParams) async throws -> ExecServerFsCreateDirectoryResponse {
        _ = try await requireInitialized(for: "filesystem")
        return try fileSystem.createDirectory(params)
    }

    public func getMetadata(_ params: ExecServerFsGetMetadataParams) async throws -> ExecServerFsGetMetadataResponse {
        _ = try await requireInitialized(for: "filesystem")
        return try fileSystem.getMetadata(params)
    }

    public func readDirectory(_ params: ExecServerFsReadDirectoryParams) async throws -> ExecServerFsReadDirectoryResponse {
        _ = try await requireInitialized(for: "filesystem")
        return try fileSystem.readDirectory(params)
    }

    public func remove(_ params: ExecServerFsRemoveParams) async throws -> ExecServerFsRemoveResponse {
        _ = try await requireInitialized(for: "filesystem")
        return try fileSystem.remove(params)
    }

    public func copy(_ params: ExecServerFsCopyParams) async throws -> ExecServerFsCopyResponse {
        _ = try await requireInitialized(for: "filesystem")
        return try fileSystem.copy(params)
    }
}

public struct ExecServerHandlerNotificationError: Error, Equatable, CustomStringConvertible, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String {
        message
    }
}
