import Foundation

public enum ExecServerConnectionEvent: Equatable, Sendable {
    case message(ExecServerJSONRPCMessage)
    case malformedMessage(reason: String)
    case disconnected(reason: String?)
}

public actor ExecServerConnectionProcessor {
    private let sessionRegistry: ExecServerSessionRegistry
    private let router: ExecServerRouter

    public init(
        sessionRegistry: ExecServerSessionRegistry = ExecServerSessionRegistry(),
        router: ExecServerRouter = ExecServerRouter()
    ) {
        self.sessionRegistry = sessionRegistry
        self.router = router
    }

    public func makeConnection() -> ExecServerConnection {
        ExecServerConnection(
            sessionRegistry: sessionRegistry,
            router: router
        )
    }
}

public actor ExecServerConnection {
    private let handler: ExecServerHandler
    private let router: ExecServerRouter
    private let outboundQueue: ExecServerOutboundQueue
    private var closed = false

    public init(
        sessionRegistry: ExecServerSessionRegistry = ExecServerSessionRegistry(),
        router: ExecServerRouter = ExecServerRouter(),
        httpClient: ExecServerHTTPClient = ExecServerHTTPClient()
    ) {
        let outboundQueue = ExecServerOutboundQueue()
        self.outboundQueue = outboundQueue
        self.handler = ExecServerHandler(
            sessionRegistry: sessionRegistry,
            httpClient: httpClient,
            outboundNotification: { notification in
                await outboundQueue.enqueue(.notification(notification))
            }
        )
        self.router = router
    }

    public func handle(_ event: ExecServerConnectionEvent) async -> ExecServerOutboundMessage? {
        guard !closed else {
            return nil
        }

        guard await handler.isSessionAttached() else {
            await close()
            return nil
        }

        switch event {
        case let .malformedMessage(reason):
            return .error(requestID: .integer(-1), error: ExecServerRPC.invalidRequest(reason))
        case let .message(message):
            return await handle(message)
        case .disconnected:
            await close()
            return nil
        }
    }

    public func handleStdioLine(_ line: String, connectionLabel: String) async -> ExecServerOutboundMessage? {
        guard let event = ExecServerJSONRPCCodec.stdioEvent(fromLine: line, connectionLabel: connectionLabel) else {
            return nil
        }
        return await handle(event)
    }

    public func handleWebSocketText(_ text: String, connectionLabel: String) async -> ExecServerOutboundMessage? {
        await handle(ExecServerJSONRPCCodec.webSocketTextEvent(text, connectionLabel: connectionLabel))
    }

    public func handleWebSocketBinary(_ data: Data, connectionLabel: String) async -> ExecServerOutboundMessage? {
        await handle(ExecServerJSONRPCCodec.webSocketBinaryEvent(data, connectionLabel: connectionLabel))
    }

    public func shutdown() async {
        await close()
    }

    public func isClosed() -> Bool {
        closed
    }

    public func nextOutbound() async -> ExecServerOutboundMessage? {
        await outboundQueue.dequeue()
    }

    public func waitForOutbound() async -> ExecServerOutboundMessage? {
        await outboundQueue.next()
    }

    private func handle(_ message: ExecServerJSONRPCMessage) async -> ExecServerOutboundMessage? {
        switch message {
        case let .request(request):
            return await router.handleRequest(request, using: handler)
        case let .notification(notification):
            do {
                try await router.handleNotification(notification, using: handler)
            } catch {
                await close()
            }
            return nil
        case .response, .error:
            await close()
            return nil
        }
    }

    private func close() async {
        guard !closed else {
            return
        }
        closed = true
        await handler.shutdown()
        await outboundQueue.finish()
    }
}

private actor ExecServerOutboundQueue {
    private var messages: [ExecServerOutboundMessage] = []
    private var waiters: [CheckedContinuation<ExecServerOutboundMessage?, Never>] = []
    private var finished = false

    func enqueue(_ message: ExecServerOutboundMessage) {
        guard !finished else {
            return
        }
        if !waiters.isEmpty {
            waiters.removeFirst().resume(returning: message)
            return
        }
        messages.append(message)
    }

    func dequeue() -> ExecServerOutboundMessage? {
        guard !messages.isEmpty else {
            return nil
        }
        return messages.removeFirst()
    }

    func next() async -> ExecServerOutboundMessage? {
        if !messages.isEmpty {
            return messages.removeFirst()
        }
        if finished {
            return nil
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func finish() {
        finished = true
        let pending = waiters
        waiters.removeAll()
        for continuation in pending {
            continuation.resume(returning: nil)
        }
    }
}
