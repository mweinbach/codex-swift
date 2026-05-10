import Foundation

public struct ExecServerRemoteHTTPClient: Sendable {
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

    public func run(_ params: ExecServerHttpRequestParams) async throws -> ExecServerHttpRequestResponse {
        try await client.get().httpRequest(params)
    }

    public func startStreaming(_ params: ExecServerHttpRequestParams) async throws -> ExecServerHTTPStreamResponse {
        try await client.get().httpRequestStream(params)
    }
}

public actor ExecServerRemoteHTTPBodyStreamLog {
    private let requestId: String
    private var nextSeq: UInt64 = 1
    private var pending: [Result<Data, TransportError>] = []
    private var continuations: [UUID: APIByteStream.Continuation] = [:]
    private var finished = false

    public init(requestId: String) {
        self.requestId = requestId
    }

    public func byteStream(client: ExecServerClient) -> APIByteStream {
        let requestId = requestId
        return APIByteStream { continuation in
            let id = UUID()
            addContinuation(continuation, id: id)
            continuation.onTermination = { _ in
                Task {
                    await client.removeHTTPBodyStream(requestId: requestId)
                    await self.removeContinuation(id)
                }
            }
        }
    }

    public func publish(_ delta: ExecServerHttpRequestBodyDeltaNotification) {
        guard !finished else {
            return
        }
        guard delta.seq == nextSeq else {
            finish(.failure(.network(
                "http response stream `\(requestId)` received seq \(delta.seq), expected \(nextSeq)"
            )))
            return
        }
        nextSeq += 1

        if !delta.delta.bytes.isEmpty {
            yield(.success(Data(delta.delta.bytes)))
        }
        if let error = delta.error {
            finish(.failure(.network("http response stream `\(requestId)` failed: \(error)")))
        } else if delta.done {
            finish(nil)
        }
    }

    public func finishWithoutDelivery() {
        guard !finished else {
            return
        }
        finished = true
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }

    private func addContinuation(_ continuation: APIByteStream.Continuation, id: UUID) {
        for event in pending {
            continuation.yield(event)
        }
        if finished {
            continuation.finish()
            return
        }
        continuations[id] = continuation
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func yield(_ event: Result<Data, TransportError>) {
        pending.append(event)
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    private func finish(_ terminalEvent: Result<Data, TransportError>?) {
        guard !finished else {
            return
        }
        if let terminalEvent {
            yield(terminalEvent)
        }
        finished = true
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }
}
