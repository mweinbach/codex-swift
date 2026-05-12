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
