import CodexCore
import Foundation

struct RemoteControlAppServerBridgeOutgoingMessage: Equatable, Sendable {
    var connectionID: RemoteControlVirtualConnectionID
    var message: ExecServerJSONRPCMessage
}

struct RemoteControlAppServerBridgeStep: Equatable, Sendable {
    var outgoingMessages: [RemoteControlAppServerBridgeOutgoingMessage]
    var droppedUnknownConnectionIDs: [RemoteControlVirtualConnectionID]

    init(
        outgoingMessages: [RemoteControlAppServerBridgeOutgoingMessage] = [],
        droppedUnknownConnectionIDs: [RemoteControlVirtualConnectionID] = []
    ) {
        self.outgoingMessages = outgoingMessages
        self.droppedUnknownConnectionIDs = droppedUnknownConnectionIDs
    }

    mutating func append(_ step: RemoteControlAppServerBridgeStep) {
        outgoingMessages.append(contentsOf: step.outgoingMessages)
        droppedUnknownConnectionIDs.append(contentsOf: step.droppedUnknownConnectionIDs)
    }
}

struct RemoteControlAppServerVirtualLoopStep: Equatable, Sendable {
    var transportStep: RemoteControlVirtualTransportStep
    var bridgeStep: RemoteControlAppServerBridgeStep
    var serverEvents: [RemoteControlQueuedServerEnvelope]

    init(
        transportStep: RemoteControlVirtualTransportStep = RemoteControlVirtualTransportStep(),
        bridgeStep: RemoteControlAppServerBridgeStep = RemoteControlAppServerBridgeStep(),
        serverEvents: [RemoteControlQueuedServerEnvelope] = []
    ) {
        self.transportStep = transportStep
        self.bridgeStep = bridgeStep
        self.serverEvents = serverEvents
    }
}

struct RemoteControlAppServerVirtualLoop {
    private var transport: RemoteControlVirtualTransportCore
    private var bridge: RemoteControlAppServerBridge

    init(
        transport: RemoteControlVirtualTransportCore = RemoteControlVirtualTransportCore(),
        bridge: RemoteControlAppServerBridge
    ) {
        self.transport = transport
        self.bridge = bridge
    }

    init(
        configuration: CodexAppServerConfiguration,
        threadStateManager: AppServerThreadStateManager = AppServerThreadStateManager()
    ) {
        self.init(
            bridge: RemoteControlAppServerBridge(
                configuration: configuration,
                threadStateManager: threadStateManager
            )
        )
    }

    mutating func handleClientEnvelope(
        _ envelope: RemoteControlClientEnvelope,
        now: TimeInterval = Date().timeIntervalSinceReferenceDate
    ) async -> RemoteControlAppServerVirtualLoopStep {
        await apply(transport.handleClientEnvelope(envelope, now: now))
    }

    mutating func disconnect(
        connectionID: RemoteControlVirtualConnectionID
    ) async -> RemoteControlAppServerVirtualLoopStep {
        await apply(transport.disconnect(connectionID: connectionID))
    }

    mutating func closeExpiredClients(
        now: TimeInterval
    ) async -> RemoteControlAppServerVirtualLoopStep {
        await apply(transport.closeExpiredClients(now: now))
    }

    mutating func handleClientTrackerEffects(
        _ effects: [RemoteControlClientTrackerEffect]
    ) async -> RemoteControlAppServerVirtualLoopStep {
        await apply(transport.applyClientTrackerEffects(effects))
    }

    mutating func drainPendingNotifications() async -> RemoteControlAppServerVirtualLoopStep {
        let bridgeStep = await bridge.drainPendingNotifications()
        return RemoteControlAppServerVirtualLoopStep(
            bridgeStep: bridgeStep,
            serverEvents: enqueue(bridgeStep.outgoingMessages)
        )
    }

    private mutating func apply(
        _ transportStep: RemoteControlVirtualTransportStep
    ) async -> RemoteControlAppServerVirtualLoopStep {
        let bridgeStep = await bridge.handle(transportStep.transportEvents)
        return RemoteControlAppServerVirtualLoopStep(
            transportStep: transportStep,
            bridgeStep: bridgeStep,
            serverEvents: transportStep.serverEvents + enqueue(bridgeStep.outgoingMessages)
        )
    }

    private mutating func enqueue(
        _ outgoingMessages: [RemoteControlAppServerBridgeOutgoingMessage]
    ) -> [RemoteControlQueuedServerEnvelope] {
        outgoingMessages.compactMap { outgoing in
            transport.enqueueOutgoingMessage(
                connectionID: outgoing.connectionID,
                message: outgoing.message
            )
        }
    }
}

struct RemoteControlAppServerWebSocketSessionStep: Equatable, Sendable {
    var connectionStep: RemoteControlWebsocketConnectionStep
    var appServerStep: RemoteControlAppServerVirtualLoopStep
    var writerSteps: [RemoteControlWebsocketConnectionStep]

    init(
        connectionStep: RemoteControlWebsocketConnectionStep = RemoteControlWebsocketConnectionStep(),
        appServerStep: RemoteControlAppServerVirtualLoopStep = RemoteControlAppServerVirtualLoopStep(),
        writerSteps: [RemoteControlWebsocketConnectionStep] = []
    ) {
        self.connectionStep = connectionStep
        self.appServerStep = appServerStep
        self.writerSteps = writerSteps
    }

    var terminalEnd: RemoteControlWebsocketConnectionEnd? {
        if let end = connectionStep.end {
            return end
        }
        return writerSteps.first { $0.end != nil }?.end
    }
}

struct RemoteControlAppServerWebSocketSession<Transport: RemoteControlWebSocketTransport> {
    private var runner: RemoteControlWebSocketSessionRunner<Transport>
    private var state = RemoteControlWebsocketState()
    private var clientTracker = RemoteControlClientTracker()
    private var appServerLoop: RemoteControlAppServerVirtualLoop

    init(
        transport: Transport,
        statusPublisher: RemoteControlStatusPublisherCore,
        appServerLoop: RemoteControlAppServerVirtualLoop
    ) {
        runner = RemoteControlWebSocketSessionRunner(
            transport: transport,
            statusPublisher: statusPublisher
        )
        self.appServerLoop = appServerLoop
    }

    init(
        transport: Transport,
        statusPublisher: RemoteControlStatusPublisherCore,
        configuration: CodexAppServerConfiguration,
        threadStateManager: AppServerThreadStateManager = AppServerThreadStateManager()
    ) {
        self.init(
            transport: transport,
            statusPublisher: statusPublisher,
            appServerLoop: RemoteControlAppServerVirtualLoop(
                configuration: configuration,
                threadStateManager: threadStateManager
            )
        )
    }

    mutating func receive(
        now: TimeInterval = Date().timeIntervalSinceReferenceDate
    ) async throws -> RemoteControlAppServerWebSocketSessionStep {
        try await process(.receive(now: now))
    }

    mutating func runUntilTerminal(
        now: @Sendable () -> TimeInterval = { Date().timeIntervalSinceReferenceDate },
        maxReceives: Int? = nil
    ) async throws -> [RemoteControlAppServerWebSocketSessionStep] {
        var steps: [RemoteControlAppServerWebSocketSessionStep] = []
        var receiveCount = 0
        while maxReceives.map({ receiveCount < $0 }) ?? true {
            let step = try await receive(now: now())
            steps.append(step)
            receiveCount += 1
            if step.terminalEnd != nil {
                break
            }
        }
        return steps
    }

    mutating func process(
        _ input: RemoteControlAppServerWebSocketSessionInput
    ) async throws -> RemoteControlAppServerWebSocketSessionStep {
        let connectionStep: RemoteControlWebsocketConnectionStep
        switch input {
        case let .receive(now):
            connectionStep = try await runner.receive(
                state: &state,
                clientTracker: &clientTracker,
                now: now
            )
        case let .connection(input):
            connectionStep = try await runner.process(
                input,
                state: &state,
                clientTracker: &clientTracker
            )
        }

        let appServerStep = await appServerLoop.handleClientTrackerEffects(connectionStep.trackerEffects)
        let writerSteps = try await writeServerEvents(appServerStep.serverEvents)
        return RemoteControlAppServerWebSocketSessionStep(
            connectionStep: connectionStep,
            appServerStep: appServerStep,
            writerSteps: writerSteps
        )
    }

    mutating func drainPendingNotifications() async throws -> RemoteControlAppServerWebSocketSessionStep {
        let appServerStep = await appServerLoop.drainPendingNotifications()
        let writerSteps = try await writeServerEvents(appServerStep.serverEvents)
        return RemoteControlAppServerWebSocketSessionStep(
            appServerStep: appServerStep,
            writerSteps: writerSteps
        )
    }

    private mutating func writeServerEvents(
        _ serverEvents: [RemoteControlQueuedServerEnvelope]
    ) async throws -> [RemoteControlWebsocketConnectionStep] {
        var writerSteps: [RemoteControlWebsocketConnectionStep] = []
        for serverEvent in serverEvents {
            let writerStep = try await runner.process(
                .queuedServerEvent(serverEvent),
                state: &state,
                clientTracker: &clientTracker
            )
            writerSteps.append(writerStep)
            if writerStep.end != nil {
                break
            }
        }
        return writerSteps
    }
}

enum RemoteControlAppServerWebSocketSessionInput: Equatable, Sendable {
    case receive(now: TimeInterval)
    case connection(RemoteControlWebsocketConnectionInput)
}

struct RemoteControlAppServerBridge {
    private let configuration: CodexAppServerConfiguration
    private let threadStateManager: AppServerThreadStateManager
    private let notificationBuffer = RemoteControlAppServerBridgeNotificationBuffer()
    private var processors: [RemoteControlVirtualConnectionID: CodexAppServerMessageProcessor] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        configuration: CodexAppServerConfiguration,
        threadStateManager: AppServerThreadStateManager = AppServerThreadStateManager()
    ) {
        self.configuration = configuration
        self.threadStateManager = threadStateManager
    }

    mutating func handle(_ events: [RemoteControlVirtualTransportEvent]) async -> RemoteControlAppServerBridgeStep {
        var combined = RemoteControlAppServerBridgeStep()
        for event in events {
            combined.append(await handle(event))
        }
        return combined
    }

    mutating func handle(_ event: RemoteControlVirtualTransportEvent) async -> RemoteControlAppServerBridgeStep {
        switch event {
        case let .connectionOpened(connectionID, _, _):
            processors.removeValue(forKey: connectionID)?.closeConnection()
            processors[connectionID] = CodexAppServerMessageProcessor(
                configuration: configuration,
                connectionID: Self.appServerConnectionID(for: connectionID),
                notificationSink: { [notificationBuffer] data in
                    await notificationBuffer.append(data, connectionID: connectionID)
                },
                threadStateManager: threadStateManager
            )
            return RemoteControlAppServerBridgeStep()

        case let .incomingMessage(connectionID, message):
            guard let processor = processors[connectionID] else {
                return RemoteControlAppServerBridgeStep(droppedUnknownConnectionIDs: [connectionID])
            }
            guard let line = try? encoder.encode(message) else {
                return RemoteControlAppServerBridgeStep()
            }
            return RemoteControlAppServerBridgeStep(
                outgoingMessages: Self.decodeOutgoingMessages(
                    processor.processLine(line),
                    connectionID: connectionID,
                    decoder: decoder
                )
            )

        case let .connectionClosed(connectionID):
            processors.removeValue(forKey: connectionID)?.closeConnection()
            return RemoteControlAppServerBridgeStep()
        }
    }

    func drainPendingNotifications() async -> RemoteControlAppServerBridgeStep {
        let payloads = await notificationBuffer.drain()
        return RemoteControlAppServerBridgeStep(
            outgoingMessages: payloads.flatMap { connectionID, data in
                Self.decodeOutgoingMessages(data, connectionID: connectionID, decoder: decoder)
            }
        )
    }

    private static func appServerConnectionID(
        for connectionID: RemoteControlVirtualConnectionID
    ) -> AppServerConnectionID {
        let boundedValue = min(connectionID.rawValue, UInt64(Int64.max))
        return AppServerConnectionID(boundedValue)
    }

    private static func decodeOutgoingMessages(
        _ data: Data?,
        connectionID: RemoteControlVirtualConnectionID,
        decoder: JSONDecoder
    ) -> [RemoteControlAppServerBridgeOutgoingMessage] {
        guard let data, !data.isEmpty else {
            return []
        }
        let payload = String(decoding: data, as: UTF8.self)
        return payload.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            guard let message = try? decoder.decode(
                ExecServerJSONRPCMessage.self,
                from: Data(line.utf8)
            ) else {
                return nil
            }
            return RemoteControlAppServerBridgeOutgoingMessage(connectionID: connectionID, message: message)
        }
    }
}

private actor RemoteControlAppServerBridgeNotificationBuffer {
    private var payloads: [(RemoteControlVirtualConnectionID, Data)] = []

    func append(_ data: Data, connectionID: RemoteControlVirtualConnectionID) {
        payloads.append((connectionID, data))
    }

    func drain() -> [(RemoteControlVirtualConnectionID, Data)] {
        let drained = payloads
        payloads.removeAll()
        return drained
    }
}
