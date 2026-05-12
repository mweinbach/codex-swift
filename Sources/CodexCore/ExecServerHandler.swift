import Foundation

public actor ExecServerHandler {
    public typealias OutboundNotification = @Sendable (ExecServerJSONRPCNotification) async -> Void

    private let sessionRegistry: ExecServerSessionRegistry
    private let fileSystem: ExecServerFileSystem
    private let suppliedProcessStore: ExecServerProcessStore?
    private let httpClient: ExecServerHTTPClient
    private let outboundNotification: OutboundNotification
    private var session: ExecServerSessionHandle?
    private var initializeRequested = false
    private var initialized = false
    private var activeHTTPBodyStreams: [String: Task<Void, Never>] = [:]

    public init(
        sessionRegistry: ExecServerSessionRegistry = ExecServerSessionRegistry(),
        fileSystem: ExecServerFileSystem = ExecServerFileSystem(),
        processStore: ExecServerProcessStore? = nil,
        httpClient: ExecServerHTTPClient = ExecServerHTTPClient(),
        outboundNotification: @escaping OutboundNotification = { _ in }
    ) {
        self.sessionRegistry = sessionRegistry
        self.fileSystem = fileSystem
        self.suppliedProcessStore = processStore
        self.httpClient = httpClient
        self.outboundNotification = outboundNotification
    }

    public func initialize(_ params: ExecServerInitializeParams) async throws -> ExecServerInitializeResponse {
        if initializeRequested {
            throw ExecServerRPC.invalidRequest("initialize may only be sent once per connection")
        }

        initializeRequested = true
        do {
            let session = try await sessionRegistry.attach(
                resumeSessionID: params.resumeSessionId,
                processStore: suppliedProcessStore,
                outboundNotification: outboundNotification
            )
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
            cancelHTTPBodyStreams()
            await suppliedProcessStore?.shutdown()
            return
        }
        cancelHTTPBodyStreams()
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

    public func startProcess(_ params: ExecServerExecParams) async throws -> ExecServerExecResponse {
        let session = try await requireInitialized(for: "exec")
        return try await session.processStore.start(params)
    }

    public func readProcess(_ params: ExecServerReadParams) async throws -> ExecServerReadResponse {
        let session = try await requireInitialized(for: "exec")
        let response = try await session.processStore.read(params)
        _ = try await requireSessionAttached()
        return response
    }

    public func writeProcess(_ params: ExecServerWriteParams) async throws -> ExecServerWriteResponse {
        let session = try await requireInitialized(for: "exec")
        return try await session.processStore.write(params)
    }

    public func terminateProcess(_ params: ExecServerTerminateParams) async throws -> ExecServerTerminateResponse {
        let session = try await requireInitialized(for: "exec")
        return try await session.processStore.terminate(params)
    }

    public func httpRequest(_ params: ExecServerHttpRequestParams) async throws -> ExecServerHttpRequestResponse {
        _ = try await requireInitialized(for: "http")
        guard params.streamResponse else {
            return try await httpClient.run(params)
        }
        if activeHTTPBodyStreams[params.requestId] != nil {
            throw ExecServerRPC.invalidParams(
                "http/request streamResponse requestId `\(params.requestId)` is already active"
            )
        }
        let streamResponse = try await httpClient.startStreaming(params)
        activeHTTPBodyStreams[params.requestId] = Task {
            await self.sendHTTPBodyDeltas(requestId: params.requestId, bodyStream: streamResponse.bodyStream)
        }
        return streamResponse.response
    }

    private func sendHTTPBodyDeltas(requestId: String, bodyStream: APIByteStream) async {
        var seq: UInt64 = 1
        for await result in bodyStream {
            switch result {
            case let .success(data):
                guard !data.isEmpty else {
                    continue
                }
                await sendHTTPBodyDelta(
                    requestId: requestId,
                    seq: seq,
                    delta: ExecServerByteChunk(Array(data)),
                    done: false
                )
                seq += 1
            case let .failure(error):
                await sendHTTPBodyDelta(
                    requestId: requestId,
                    seq: seq,
                    delta: ExecServerByteChunk([]),
                    done: true,
                    error: String(describing: error)
                )
                activeHTTPBodyStreams[requestId] = nil
                return
            }
        }

        await sendHTTPBodyDelta(
            requestId: requestId,
            seq: seq,
            delta: ExecServerByteChunk([]),
            done: true
        )
        activeHTTPBodyStreams[requestId] = nil
    }

    private func sendHTTPBodyDelta(
        requestId: String,
        seq: UInt64,
        delta: ExecServerByteChunk,
        done: Bool,
        error: String? = nil
    ) async {
        let notification = ExecServerHttpRequestBodyDeltaNotification(
            requestId: requestId,
            seq: seq,
            delta: delta,
            done: done,
            error: error
        )
        let params = try? ExecServerRPC.jsonValue(from: notification)
        await outboundNotification(ExecServerJSONRPCNotification(
            method: execServerHttpRequestBodyDeltaMethod,
            params: params
        ))
    }

    private func cancelHTTPBodyStreams() {
        for task in activeHTTPBodyStreams.values {
            task.cancel()
        }
        activeHTTPBodyStreams.removeAll()
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
