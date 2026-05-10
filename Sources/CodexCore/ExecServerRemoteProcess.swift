import Foundation

public struct StartedExecProcess: Sendable {
    public let process: ExecServerRemoteProcessSession

    public init(process: ExecServerRemoteProcessSession) {
        self.process = process
    }
}

public enum ExecServerProcessEvent: Equatable, Sendable {
    case output(ExecServerProcessOutputChunk)
    case exited(seq: UInt64, exitCode: Int32)
    case closed(seq: UInt64)
    case failed(String)

    var seq: UInt64? {
        switch self {
        case let .output(chunk):
            return chunk.seq
        case let .exited(seq, _), let .closed(seq):
            return seq
        case .failed:
            return nil
        }
    }
}

public struct ExecServerRemoteProcess: Sendable {
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

    public func start(_ params: ExecServerExecParams) async throws -> StartedExecProcess {
        let client = try await client.get()
        let session = try await client.registerProcessSession(processId: params.processId)
        do {
            _ = try await client.startProcess(params)
            return StartedExecProcess(process: session)
        } catch {
            await session.unregister()
            throw error
        }
    }
}

public final class ExecServerRemoteProcessSession: Sendable {
    public let processId: String

    private let client: ExecServerClient
    private let events: ExecServerRemoteProcessEventLog

    init(processId: String, client: ExecServerClient, events: ExecServerRemoteProcessEventLog) {
        self.processId = processId
        self.client = client
        self.events = events
    }

    deinit {
        let client = client
        let processId = processId
        Task { [client, processId] in
            await client.unregisterProcessSession(processId: processId)
        }
    }

    public func subscribeEvents() async -> AsyncStream<ExecServerProcessEvent> {
        await events.subscribe()
    }

    public func eventSnapshot() async -> [ExecServerProcessEvent] {
        await events.snapshot()
    }

    public func read(
        afterSeq: UInt64? = nil,
        maxBytes: Int? = nil,
        waitMs: UInt64? = nil
    ) async throws -> ExecServerReadResponse {
        if let response = await events.failedResponse() {
            return response
        }
        do {
            return try await client.readProcess(ExecServerReadParams(
                processId: processId,
                afterSeq: afterSeq,
                maxBytes: maxBytes,
                waitMs: waitMs
            ))
        } catch let error as ExecServerClientError where error.isTransportClosedLikeRust {
            let message = "exec-server transport disconnected"
            await events.setFailure(message)
            return await events.synthesizedFailure(message: message)
        }
    }

    public func write(_ chunk: Data) async throws -> ExecServerWriteResponse {
        try await client.writeProcess(ExecServerWriteParams(
            processId: processId,
            chunk: ExecServerByteChunk(data: chunk)
        ))
    }

    public func terminate() async throws {
        _ = try await client.terminateProcess(ExecServerTerminateParams(processId: processId))
    }

    public func unregister() async {
        await client.unregisterProcessSession(processId: processId)
    }
}

public actor ExecServerRemoteProcessEventLog {
    private var history: [ExecServerProcessEvent] = []
    private var pending: [UInt64: ExecServerProcessEvent] = [:]
    private var lastPublishedSeq: UInt64 = 0
    private var failureMessage: String?
    private var continuations: [UUID: AsyncStream<ExecServerProcessEvent>.Continuation] = [:]

    public init() {}

    public func subscribe() -> AsyncStream<ExecServerProcessEvent> {
        let id = UUID()
        let replay = history
        return AsyncStream { continuation in
            for event in replay {
                continuation.yield(event)
            }
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    public func snapshot() -> [ExecServerProcessEvent] {
        history
    }

    @discardableResult
    public func publishOrdered(_ event: ExecServerProcessEvent) -> Bool {
        guard let seq = event.seq else {
            publish(event)
            return false
        }
        guard seq > lastPublishedSeq else {
            return false
        }

        pending[seq] = event
        var deliveredClosed = false
        while let ready = pending.removeValue(forKey: lastPublishedSeq + 1) {
            lastPublishedSeq += 1
            deliveredClosed = deliveredClosed || ready.isClosed
            publish(ready)
        }
        return deliveredClosed
    }

    public func setFailure(_ message: String) {
        guard failureMessage == nil else {
            return
        }
        failureMessage = message
        publish(.failed(message))
    }

    public func failedResponse() -> ExecServerReadResponse? {
        failureMessage.map { synthesizedFailure(message: $0) }
    }

    public func synthesizedFailure(message: String) -> ExecServerReadResponse {
        ExecServerReadResponse(
            chunks: [],
            nextSeq: lastPublishedSeq + 1,
            exited: true,
            exitCode: nil,
            closed: true,
            failure: message
        )
    }

    private func publish(_ event: ExecServerProcessEvent) {
        history.append(event)
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }
}

private extension ExecServerProcessEvent {
    var isClosed: Bool {
        guard case .closed = self else {
            return false
        }
        return true
    }
}

extension ExecServerClientError {
    var isTransportClosedLikeRust: Bool {
        switch self {
        case .closed, .disconnected:
            return true
        case let .server(code, message):
            return code == -32000 && message == "JSON-RPC transport closed"
        default:
            return false
        }
    }
}
