import Darwin
import Foundation

public struct RemoteControlTarget: Equatable, Sendable {
    public var websocketURL: String
    public var enrollURL: String

    public init(websocketURL: String, enrollURL: String) {
        self.websocketURL = websocketURL
        self.enrollURL = enrollURL
    }
}

public struct RemoteControlEnrollmentRecord: Equatable, Sendable {
    public var websocketURL: String
    public var accountID: String
    public var appServerClientName: String?
    public var serverID: String
    public var environmentID: String
    public var serverName: String

    public init(
        websocketURL: String,
        accountID: String,
        appServerClientName: String?,
        serverID: String,
        environmentID: String,
        serverName: String
    ) {
        self.websocketURL = websocketURL
        self.accountID = accountID
        self.appServerClientName = appServerClientName
        self.serverID = serverID
        self.environmentID = environmentID
        self.serverName = serverName
    }
}

public struct RemoteControlEnrollment: Equatable, Sendable {
    public var accountID: String
    public var environmentID: String
    public var serverID: String
    public var serverName: String

    public init(accountID: String, environmentID: String, serverID: String, serverName: String) {
        self.accountID = accountID
        self.environmentID = environmentID
        self.serverID = serverID
        self.serverName = serverName
    }
}

public struct RemoteControlConnectionAuth<Auth: APIAuthProvider>: Sendable {
    public var authProvider: Auth
    public var accountID: String

    public init(authProvider: Auth, accountID: String) {
        self.authProvider = authProvider
        self.accountID = accountID
    }
}

public enum RemoteControlConnectionStatus: String, Equatable, Sendable {
    case disabled
    case connecting
    case connected
    case errored
}

public struct RemoteControlStatusSnapshot: Equatable, Sendable {
    public var status: RemoteControlConnectionStatus
    public var installationID: String
    public var environmentID: String?

    public init(
        status: RemoteControlConnectionStatus,
        installationID: String,
        environmentID: String?
    ) {
        self.status = status
        self.installationID = installationID
        self.environmentID = environmentID
    }
}

public struct RemoteControlStatusPublisherCore: Equatable, Sendable {
    public private(set) var snapshot: RemoteControlStatusSnapshot

    public init(snapshot: RemoteControlStatusSnapshot) {
        self.snapshot = snapshot
    }

    @discardableResult
    public mutating func publishStatus(_ status: RemoteControlConnectionStatus) -> RemoteControlStatusSnapshot? {
        let nextSnapshot = RemoteControlStatusSnapshot(
            status: status,
            installationID: snapshot.installationID,
            environmentID: status == .disabled ? nil : snapshot.environmentID
        )
        guard nextSnapshot != snapshot else {
            return nil
        }
        snapshot = nextSnapshot
        return nextSnapshot
    }

    @discardableResult
    public mutating func publishEnvironmentID(_ environmentID: String?) -> RemoteControlStatusSnapshot? {
        guard snapshot.status != .disabled else {
            return nil
        }
        let nextSnapshot = RemoteControlStatusSnapshot(
            status: snapshot.status,
            installationID: snapshot.installationID,
            environmentID: environmentID
        )
        guard nextSnapshot != snapshot else {
            return nil
        }
        snapshot = nextSnapshot
        return nextSnapshot
    }
}

public struct RemoteControlStartState: Equatable, Sendable {
    public var remoteControlURL: String
    public var requestedEnabled: Bool
    public var stateDatabaseAvailable: Bool
    public var target: RemoteControlTarget?
    public var statusPublisher: RemoteControlStatusPublisherCore

    public var enabled: Bool {
        requestedEnabled && stateDatabaseAvailable
    }

    public var statusSnapshot: RemoteControlStatusSnapshot {
        statusPublisher.snapshot
    }

    public init(
        remoteControlURL: String,
        installationID: String,
        requestedEnabled: Bool,
        stateDatabaseAvailable: Bool
    ) throws {
        let enabled = requestedEnabled && stateDatabaseAvailable
        self.remoteControlURL = remoteControlURL
        self.requestedEnabled = requestedEnabled
        self.stateDatabaseAvailable = stateDatabaseAvailable
        target = enabled ? try RemoteControlURLNormalizer.normalize(remoteControlURL) : nil
        statusPublisher = RemoteControlStatusPublisherCore(snapshot: RemoteControlStatusSnapshot(
            status: enabled ? .connecting : .disabled,
            installationID: installationID,
            environmentID: nil
        ))
    }

    @discardableResult
    public mutating func setRequestedEnabled(_ requestedEnabled: Bool) throws -> RemoteControlStatusSnapshot? {
        let enabled = requestedEnabled && stateDatabaseAvailable
        self.requestedEnabled = requestedEnabled
        if enabled, target == nil {
            target = try RemoteControlURLNormalizer.normalize(remoteControlURL)
        }
        return statusPublisher.publishStatus(enabled ? .connecting : .disabled)
    }
}

public struct RemoteControlReconnectDelay: Equatable, Sendable {
    public var attempt: UInt64
    public var baseMilliseconds: UInt64
    public var minimumMilliseconds: UInt64
    public var maximumMilliseconds: UInt64

    public init(attempt: UInt64, baseMilliseconds: UInt64, minimumMilliseconds: UInt64, maximumMilliseconds: UInt64) {
        self.attempt = attempt
        self.baseMilliseconds = baseMilliseconds
        self.minimumMilliseconds = minimumMilliseconds
        self.maximumMilliseconds = maximumMilliseconds
    }
}

public enum RemoteControlConnectLoopFailure: Equatable, Sendable {
    case waitingForAccountID
    case failed(String)
}

public enum RemoteControlConnectLoopAction: Equatable, Sendable {
    case connect(RemoteControlTarget)
    case waitForDisableAfterInvalidURL(String)
    case connected
    case disabled
    case retryAfterAccountID
    case retryAfterBackoff(RemoteControlReconnectDelay)
}

public struct RemoteControlConnectLoopStep: Equatable, Sendable {
    public var action: RemoteControlConnectLoopAction
    public var statusUpdates: [RemoteControlStatusSnapshot]

    public init(action: RemoteControlConnectLoopAction, statusUpdates: [RemoteControlStatusSnapshot]) {
        self.action = action
        self.statusUpdates = statusUpdates
    }
}

public struct RemoteControlConnectLoopCore: Equatable, Sendable {
    public static var accountIDRetryIntervalSeconds: TimeInterval { 1 }
    public static var initialBackoffMilliseconds: UInt64 { 200 }
    public static var backoffJitterLowerBound: Double { 0.9 }
    public static var backoffJitterUpperBound: Double { 1.1 }

    public var remoteControlURL: String
    public var target: RemoteControlTarget?
    public var reconnectAttempt: UInt64
    public var statusPublisher: RemoteControlStatusPublisherCore

    public init(
        remoteControlURL: String,
        target: RemoteControlTarget? = nil,
        reconnectAttempt: UInt64 = 0,
        statusPublisher: RemoteControlStatusPublisherCore
    ) {
        self.remoteControlURL = remoteControlURL
        self.target = target
        self.reconnectAttempt = reconnectAttempt
        self.statusPublisher = statusPublisher
    }

    public mutating func beginConnect() -> RemoteControlConnectLoopStep {
        var updates = [RemoteControlStatusSnapshot]()
        if let update = statusPublisher.publishStatus(.connecting) {
            updates.append(update)
        }
        if let target {
            return RemoteControlConnectLoopStep(action: .connect(target), statusUpdates: updates)
        }
        do {
            let normalizedTarget = try RemoteControlURLNormalizer.normalize(remoteControlURL)
            target = normalizedTarget
            return RemoteControlConnectLoopStep(action: .connect(normalizedTarget), statusUpdates: updates)
        } catch {
            if let update = statusPublisher.publishStatus(.errored) {
                updates.append(update)
            }
            return RemoteControlConnectLoopStep(
                action: .waitForDisableAfterInvalidURL(String(describing: error)),
                statusUpdates: updates
            )
        }
    }

    public mutating func connectionEstablished(environmentID: String?) -> RemoteControlConnectLoopStep {
        reconnectAttempt = 0
        var updates = [RemoteControlStatusSnapshot]()
        if let update = statusPublisher.publishEnvironmentID(environmentID) {
            updates.append(update)
        }
        if let update = statusPublisher.publishStatus(.connected) {
            updates.append(update)
        }
        return RemoteControlConnectLoopStep(action: .connected, statusUpdates: updates)
    }

    public mutating func connectionFailed(_ failure: RemoteControlConnectLoopFailure) -> RemoteControlConnectLoopStep {
        switch failure {
        case .waitingForAccountID:
            return RemoteControlConnectLoopStep(action: .retryAfterAccountID, statusUpdates: [])
        case .failed:
            var updates = [RemoteControlStatusSnapshot]()
            if let update = statusPublisher.publishStatus(.errored) {
                updates.append(update)
            }
            let delay = Self.backoffDelay(for: reconnectAttempt)
            reconnectAttempt = reconnectAttempt == UInt64.max ? UInt64.max : reconnectAttempt + 1
            return RemoteControlConnectLoopStep(action: .retryAfterBackoff(delay), statusUpdates: updates)
        }
    }

    public mutating func disabled() -> RemoteControlConnectLoopStep {
        let updates = statusPublisher.publishStatus(.disabled).map { [$0] } ?? []
        return RemoteControlConnectLoopStep(action: .disabled, statusUpdates: updates)
    }

    public static func backoffDelay(for attempt: UInt64) -> RemoteControlReconnectDelay {
        let exponent = attempt == 0 ? 0 : min(attempt - 1, 56)
        let base = initialBackoffMilliseconds * (UInt64(1) << exponent)
        return RemoteControlReconnectDelay(
            attempt: attempt,
            baseMilliseconds: base,
            minimumMilliseconds: UInt64(Double(base) * backoffJitterLowerBound),
            maximumMilliseconds: UInt64(Double(base) * backoffJitterUpperBound)
        )
    }
}

public struct RemoteControlClientID: Codable, Equatable, Hashable, Sendable {
    public var rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        rawValue = try String(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try rawValue.encode(to: encoder)
    }
}

public struct RemoteControlStreamID: Codable, Equatable, Hashable, Sendable {
    public var rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static func newRandom() -> Self {
        Self(UUID().uuidString.lowercased())
    }

    public init(from decoder: Decoder) throws {
        rawValue = try String(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try rawValue.encode(to: encoder)
    }
}

public enum RemoteControlPongStatus: String, Codable, Equatable, Sendable {
    case active
    case unknown
}

public enum RemoteControlClientEvent: Codable, Equatable, Sendable {
    case clientMessage(message: ExecServerJSONRPCMessage)
    case clientMessageChunk(
        segmentID: Int,
        segmentCount: Int,
        messageSizeBytes: Int,
        messageChunkBase64: String
    )
    case ack(segmentID: Int?)
    case ping
    case clientClosed

    private enum CodingKeys: String, CodingKey {
        case type
        case message
        case segmentID = "segment_id"
        case segmentCount = "segment_count"
        case messageSizeBytes = "message_size_bytes"
        case messageChunkBase64 = "message_chunk_base64"
    }

    private enum EventType: String, Codable {
        case clientMessage = "client_message"
        case clientMessageChunk = "client_message_chunk"
        case ack
        case ping
        case clientClosed = "client_closed"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(EventType.self, forKey: .type) {
        case .clientMessage:
            self = .clientMessage(message: try container.decode(ExecServerJSONRPCMessage.self, forKey: .message))
        case .clientMessageChunk:
            self = .clientMessageChunk(
                segmentID: try container.decode(Int.self, forKey: .segmentID),
                segmentCount: try container.decode(Int.self, forKey: .segmentCount),
                messageSizeBytes: try container.decode(Int.self, forKey: .messageSizeBytes),
                messageChunkBase64: try container.decode(String.self, forKey: .messageChunkBase64)
            )
        case .ack:
            self = .ack(segmentID: try container.decodeIfPresent(Int.self, forKey: .segmentID))
        case .ping:
            self = .ping
        case .clientClosed:
            self = .clientClosed
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .clientMessage(message):
            try container.encode(EventType.clientMessage, forKey: .type)
            try container.encode(message, forKey: .message)
        case let .clientMessageChunk(segmentID, segmentCount, messageSizeBytes, messageChunkBase64):
            try container.encode(EventType.clientMessageChunk, forKey: .type)
            try container.encode(segmentID, forKey: .segmentID)
            try container.encode(segmentCount, forKey: .segmentCount)
            try container.encode(messageSizeBytes, forKey: .messageSizeBytes)
            try container.encode(messageChunkBase64, forKey: .messageChunkBase64)
        case let .ack(segmentID):
            try container.encode(EventType.ack, forKey: .type)
            try container.encodeIfPresent(segmentID, forKey: .segmentID)
        case .ping:
            try container.encode(EventType.ping, forKey: .type)
        case .clientClosed:
            try container.encode(EventType.clientClosed, forKey: .type)
        }
    }
}

public struct RemoteControlClientEnvelope: Codable, Equatable, Sendable {
    public var event: RemoteControlClientEvent
    public var clientID: RemoteControlClientID
    public var streamID: RemoteControlStreamID?
    public var seqID: UInt64?
    public var cursor: String?

    private enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case streamID = "stream_id"
        case seqID = "seq_id"
        case cursor
    }

    public init(
        event: RemoteControlClientEvent,
        clientID: RemoteControlClientID,
        streamID: RemoteControlStreamID?,
        seqID: UInt64?,
        cursor: String?
    ) {
        self.event = event
        self.clientID = clientID
        self.streamID = streamID
        self.seqID = seqID
        self.cursor = cursor
    }

    public init(from decoder: Decoder) throws {
        event = try RemoteControlClientEvent(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clientID = try container.decode(RemoteControlClientID.self, forKey: .clientID)
        streamID = try container.decodeIfPresent(RemoteControlStreamID.self, forKey: .streamID)
        seqID = try container.decodeIfPresent(UInt64.self, forKey: .seqID)
        cursor = try container.decodeIfPresent(String.self, forKey: .cursor)
    }

    public func encode(to encoder: Encoder) throws {
        try event.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(clientID, forKey: .clientID)
        try container.encodeIfPresent(streamID, forKey: .streamID)
        try container.encodeIfPresent(seqID, forKey: .seqID)
        try container.encodeIfPresent(cursor, forKey: .cursor)
    }
}

public enum RemoteControlServerEvent: Codable, Equatable, Sendable {
    case serverMessage(message: ExecServerJSONRPCMessage)
    case serverMessageChunk(
        segmentID: Int,
        segmentCount: Int,
        messageSizeBytes: Int,
        messageChunkBase64: String
    )
    case ack
    case pong(status: RemoteControlPongStatus)

    private enum CodingKeys: String, CodingKey {
        case type
        case message
        case segmentID = "segment_id"
        case segmentCount = "segment_count"
        case messageSizeBytes = "message_size_bytes"
        case messageChunkBase64 = "message_chunk_base64"
        case status
    }

    private enum EventType: String, Codable {
        case serverMessage = "server_message"
        case serverMessageChunk = "server_message_chunk"
        case ack
        case pong
    }

    public var segmentID: Int? {
        switch self {
        case let .serverMessageChunk(segmentID, _, _, _):
            return segmentID
        case .serverMessage, .ack, .pong:
            return nil
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(EventType.self, forKey: .type) {
        case .serverMessage:
            self = .serverMessage(message: try container.decode(ExecServerJSONRPCMessage.self, forKey: .message))
        case .serverMessageChunk:
            self = .serverMessageChunk(
                segmentID: try container.decode(Int.self, forKey: .segmentID),
                segmentCount: try container.decode(Int.self, forKey: .segmentCount),
                messageSizeBytes: try container.decode(Int.self, forKey: .messageSizeBytes),
                messageChunkBase64: try container.decode(String.self, forKey: .messageChunkBase64)
            )
        case .ack:
            self = .ack
        case .pong:
            self = .pong(status: try container.decode(RemoteControlPongStatus.self, forKey: .status))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .serverMessage(message):
            try container.encode(EventType.serverMessage, forKey: .type)
            try container.encode(message, forKey: .message)
        case let .serverMessageChunk(segmentID, segmentCount, messageSizeBytes, messageChunkBase64):
            try container.encode(EventType.serverMessageChunk, forKey: .type)
            try container.encode(segmentID, forKey: .segmentID)
            try container.encode(segmentCount, forKey: .segmentCount)
            try container.encode(messageSizeBytes, forKey: .messageSizeBytes)
            try container.encode(messageChunkBase64, forKey: .messageChunkBase64)
        case .ack:
            try container.encode(EventType.ack, forKey: .type)
        case let .pong(status):
            try container.encode(EventType.pong, forKey: .type)
            try container.encode(status, forKey: .status)
        }
    }
}

public struct RemoteControlServerEnvelope: Codable, Equatable, Sendable {
    public var event: RemoteControlServerEvent
    public var clientID: RemoteControlClientID
    public var streamID: RemoteControlStreamID
    public var seqID: UInt64

    private enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case streamID = "stream_id"
        case seqID = "seq_id"
    }

    public init(
        event: RemoteControlServerEvent,
        clientID: RemoteControlClientID,
        streamID: RemoteControlStreamID,
        seqID: UInt64
    ) {
        self.event = event
        self.clientID = clientID
        self.streamID = streamID
        self.seqID = seqID
    }

    public init(from decoder: Decoder) throws {
        event = try RemoteControlServerEvent(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clientID = try container.decode(RemoteControlClientID.self, forKey: .clientID)
        streamID = try container.decode(RemoteControlStreamID.self, forKey: .streamID)
        seqID = try container.decode(UInt64.self, forKey: .seqID)
    }

    public func encode(to encoder: Encoder) throws {
        try event.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(clientID, forKey: .clientID)
        try container.encode(streamID, forKey: .streamID)
        try container.encode(seqID, forKey: .seqID)
    }
}

public struct RemoteControlOutboundBuffer: Equatable, Sendable {
    private struct StreamKey: Hashable, Sendable {
        var clientID: RemoteControlClientID
        var streamID: RemoteControlStreamID
    }

    private var envelopesByStream: [StreamKey: [RemoteControlServerEnvelope]] = [:]
    public private(set) var usedCount: Int = 0

    public init() {}

    public mutating func insert(_ envelope: RemoteControlServerEnvelope) {
        let key = StreamKey(clientID: envelope.clientID, streamID: envelope.streamID)
        envelopesByStream[key, default: []].append(envelope)
        usedCount += 1
    }

    public mutating func ack(
        clientID: RemoteControlClientID,
        streamID: RemoteControlStreamID,
        ackedSeqID: UInt64,
        ackedSegmentID: Int?
    ) {
        let key = StreamKey(clientID: clientID, streamID: streamID)
        guard var envelopes = envelopesByStream[key] else {
            return
        }
        let ackedCursor = (ackedSeqID, ackedSegmentID ?? Int.max)
        envelopes.removeAll { envelope in
            let envelopeCursor = (envelope.seqID, envelope.event.segmentID ?? 0)
            if envelopeCursor <= ackedCursor {
                usedCount -= 1
                return true
            }
            return false
        }
        if envelopes.isEmpty {
            envelopesByStream.removeValue(forKey: key)
        } else {
            envelopesByStream[key] = envelopes
        }
    }

    public func serverEnvelopes() -> [RemoteControlServerEnvelope] {
        envelopesByStream.values.flatMap { $0 }
    }
}

public struct RemoteControlQueuedServerEnvelope: Equatable, Sendable {
    public var event: RemoteControlServerEvent
    public var clientID: RemoteControlClientID
    public var streamID: RemoteControlStreamID

    public init(
        event: RemoteControlServerEvent,
        clientID: RemoteControlClientID,
        streamID: RemoteControlStreamID
    ) {
        self.event = event
        self.clientID = clientID
        self.streamID = streamID
    }
}

public struct RemoteControlVirtualConnectionID: Equatable, Hashable, Sendable {
    public var rawValue: UInt64

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

public enum RemoteControlClientTrackerEffect: Equatable, Sendable {
    case connectionOpened(
        connectionID: RemoteControlVirtualConnectionID,
        clientID: RemoteControlClientID,
        streamID: RemoteControlStreamID
    )
    case incomingMessage(
        connectionID: RemoteControlVirtualConnectionID,
        message: ExecServerJSONRPCMessage
    )
    case connectionClosed(connectionID: RemoteControlVirtualConnectionID)
    case serverEvent(RemoteControlQueuedServerEnvelope)
}

public struct RemoteControlClientTracker: Equatable, Sendable {
    public static var idleTimeoutSeconds: TimeInterval { 10 * 60 }

    private struct ClientKey: Hashable, Sendable {
        var clientID: RemoteControlClientID
        var streamID: RemoteControlStreamID
    }

    private struct ClientState: Equatable, Sendable {
        var connectionID: RemoteControlVirtualConnectionID
        var lastActivityAt: TimeInterval
        var lastInboundSeqID: UInt64?
    }

    private var clients: [ClientKey: ClientState] = [:]
    private var legacyStreamIDs: [RemoteControlClientID: RemoteControlStreamID] = [:]
    private var nextConnectionID: UInt64

    public var activeConnectionCount: Int {
        clients.count
    }

    public init(nextConnectionID: UInt64 = 1) {
        self.nextConnectionID = nextConnectionID
    }

    public mutating func handleClientEnvelope(
        _ envelope: RemoteControlClientEnvelope,
        now: TimeInterval = Date().timeIntervalSinceReferenceDate
    ) -> [RemoteControlClientTrackerEffect] {
        let isLegacyStreamID = envelope.streamID == nil
        let isInitialize = Self.messageStartsConnection(envelope.event)
        let streamID = resolvedStreamID(
            for: envelope,
            startsConnection: isInitialize
        )
        guard !streamID.rawValue.isEmpty else {
            return []
        }

        let clientKey = ClientKey(clientID: envelope.clientID, streamID: streamID)
        switch envelope.event {
        case let .clientMessage(message):
            if let seqID = envelope.seqID,
               let client = clients[clientKey],
               let lastSeqID = client.lastInboundSeqID,
               lastSeqID >= seqID,
               !isInitialize
            {
                return []
            }

            var effects: [RemoteControlClientTrackerEffect] = []
            if isInitialize, clients[clientKey] != nil {
                effects.append(contentsOf: closeClient(clientID: envelope.clientID, streamID: streamID))
            }

            if var client = clients[clientKey] {
                client.lastActivityAt = now
                if let seqID = envelope.seqID {
                    client.lastInboundSeqID = seqID
                }
                clients[clientKey] = client
                effects.append(.incomingMessage(connectionID: client.connectionID, message: message))
                return effects
            }

            guard isInitialize else {
                return effects
            }

            let connectionID = RemoteControlVirtualConnectionID(nextConnectionID)
            nextConnectionID = nextConnectionID == UInt64.max ? UInt64.max : nextConnectionID + 1
            clients[clientKey] = ClientState(
                connectionID: connectionID,
                lastActivityAt: now,
                lastInboundSeqID: isLegacyStreamID ? nil : envelope.seqID
            )
            if isLegacyStreamID {
                legacyStreamIDs[envelope.clientID] = streamID
            }
            effects.append(.connectionOpened(
                connectionID: connectionID,
                clientID: envelope.clientID,
                streamID: streamID
            ))
            effects.append(.incomingMessage(connectionID: connectionID, message: message))
            return effects

        case .clientMessageChunk, .ack:
            return []

        case .ping:
            if var client = clients[clientKey] {
                client.lastActivityAt = now
                clients[clientKey] = client
                return [.serverEvent(RemoteControlQueuedServerEnvelope(
                    event: .pong(status: .active),
                    clientID: envelope.clientID,
                    streamID: streamID
                ))]
            }
            return [.serverEvent(RemoteControlQueuedServerEnvelope(
                event: .pong(status: .unknown),
                clientID: envelope.clientID,
                streamID: streamID
            ))]

        case .clientClosed:
            return closeClient(clientID: envelope.clientID, streamID: streamID)
        }
    }

    public mutating func enqueueOutgoingMessage(
        connectionID: RemoteControlVirtualConnectionID,
        message: ExecServerJSONRPCMessage
    ) -> RemoteControlQueuedServerEnvelope? {
        guard let entry = clients.first(where: { $0.value.connectionID == connectionID }) else {
            return nil
        }
        return RemoteControlQueuedServerEnvelope(
            event: .serverMessage(message: message),
            clientID: entry.key.clientID,
            streamID: entry.key.streamID
        )
    }

    public mutating func closeClient(
        clientID: RemoteControlClientID,
        streamID: RemoteControlStreamID
    ) -> [RemoteControlClientTrackerEffect] {
        let key = ClientKey(clientID: clientID, streamID: streamID)
        guard let client = clients.removeValue(forKey: key) else {
            return []
        }
        if legacyStreamIDs[clientID] == streamID {
            legacyStreamIDs.removeValue(forKey: clientID)
        }
        return [.connectionClosed(connectionID: client.connectionID)]
    }

    public mutating func closeExpiredClients(
        now: TimeInterval
    ) -> [RemoteControlClientTrackerEffect] {
        let expiredKeys = clients.compactMap { key, client in
            now - client.lastActivityAt >= Self.idleTimeoutSeconds ? key : nil
        }
        return expiredKeys.flatMap { key in
            closeClient(clientID: key.clientID, streamID: key.streamID)
        }
    }

    private mutating func resolvedStreamID(
        for envelope: RemoteControlClientEnvelope,
        startsConnection: Bool
    ) -> RemoteControlStreamID {
        if let streamID = envelope.streamID {
            return streamID
        }
        if startsConnection {
            if let existingStreamID = legacyStreamIDs.removeValue(forKey: envelope.clientID) {
                return existingStreamID
            }
            return .newRandom()
        }
        if let existingStreamID = legacyStreamIDs[envelope.clientID] {
            return existingStreamID
        }
        if case .ping = envelope.event {
            return .newRandom()
        }
        return RemoteControlStreamID("")
    }

    private static func messageStartsConnection(_ event: RemoteControlClientEvent) -> Bool {
        guard case let .clientMessage(message) = event,
              case let .request(request) = message
        else {
            return false
        }
        return request.method == "initialize"
    }
}

public struct RemoteControlWebsocketState: Equatable, Sendable {
    public static var channelCapacity: Int { 128 }

    private struct StreamKey: Hashable, Sendable {
        var clientID: RemoteControlClientID
        var streamID: RemoteControlStreamID
    }

    private var outboundBuffer = RemoteControlOutboundBuffer()
    private var nextSeqIDByStream: [StreamKey: UInt64] = [:]
    private var clientMessageObserver = RemoteControlClientMessageObserver()
    public private(set) var subscribeCursor: String?

    public var bufferedEnvelopeCount: Int {
        outboundBuffer.usedCount
    }

    public var outboundHasCapacity: Bool {
        outboundBuffer.usedCount < Self.channelCapacity
    }

    public init() {}

    public func replayBufferedServerEnvelopes() -> [RemoteControlServerEnvelope] {
        outboundBuffer.serverEnvelopes()
    }

    public mutating func enqueueServerEvent(
        _ queuedEnvelope: RemoteControlQueuedServerEnvelope
    ) throws -> [RemoteControlServerEnvelope] {
        let key = StreamKey(clientID: queuedEnvelope.clientID, streamID: queuedEnvelope.streamID)
        let seqID = nextSeqIDByStream[key] ?? 1
        let envelope = RemoteControlServerEnvelope(
            event: queuedEnvelope.event,
            clientID: queuedEnvelope.clientID,
            streamID: queuedEnvelope.streamID,
            seqID: seqID
        )
        let transportEnvelopes = try RemoteControlServerEnvelopeSplitter.splitForTransport(envelope)
        for transportEnvelope in transportEnvelopes {
            outboundBuffer.insert(transportEnvelope)
        }
        nextSeqIDByStream[key] = seqID == UInt64.max ? UInt64.max : seqID + 1
        return transportEnvelopes
    }

    public mutating func observeClientEnvelope(
        _ envelope: RemoteControlClientEnvelope,
        wireSizeBytes: Int
    ) -> RemoteControlClientSegmentObservation {
        let observation = clientMessageObserver.observe(envelope, wireSizeBytes: wireSizeBytes)
        guard case let .forward(forwardedEnvelope) = observation else {
            return observation
        }
        if let cursor = forwardedEnvelope.cursor {
            subscribeCursor = cursor
        }
        if case let .ack(segmentID) = forwardedEnvelope.event,
           let ackedSeqID = forwardedEnvelope.seqID,
           let streamID = forwardedEnvelope.streamID
        {
            outboundBuffer.ack(
                clientID: forwardedEnvelope.clientID,
                streamID: streamID,
                ackedSeqID: ackedSeqID,
                ackedSegmentID: segmentID
            )
        }
        return observation
    }

    public mutating func invalidateClientMessageStream(
        clientID: RemoteControlClientID,
        streamID: RemoteControlStreamID
    ) {
        clientMessageObserver.invalidateStream(clientID: clientID, streamID: streamID)
    }

    public mutating func invalidateClientMessageClient(clientID: RemoteControlClientID) {
        clientMessageObserver.invalidateClient(clientID: clientID)
    }
}

public enum RemoteControlWebsocketWriterFrame: Equatable, Sendable {
    case text(String)
    case ping
}

public enum RemoteControlWebsocketWriterInput: Equatable, Sendable {
    case connectionOpened
    case queuedServerEvent(RemoteControlQueuedServerEnvelope)
    case pingTick
}

public enum RemoteControlWebsocketWriterError: Error, CustomStringConvertible, Equatable, Sendable {
    case serializationFailed(String)

    public var description: String {
        switch self {
        case let .serializationFailed(message):
            return "failed to serialize remote-control server event: \(message)"
        }
    }
}

public struct RemoteControlWebsocketWriterCore: Equatable, Sendable {
    public static var pingIntervalSeconds: TimeInterval { 10 }

    public init() {}

    public mutating func process(
        _ input: RemoteControlWebsocketWriterInput,
        state: inout RemoteControlWebsocketState
    ) throws -> [RemoteControlWebsocketWriterFrame] {
        switch input {
        case .connectionOpened:
            return try state.replayBufferedServerEnvelopes().map { try textFrame(for: $0) }
        case let .queuedServerEvent(queuedEnvelope):
            guard state.outboundHasCapacity else {
                return []
            }
            return try state.enqueueServerEvent(queuedEnvelope).map { try textFrame(for: $0) }
        case .pingTick:
            return [.ping]
        }
    }

    private func textFrame(for envelope: RemoteControlServerEnvelope) throws -> RemoteControlWebsocketWriterFrame {
        do {
            return .text(String(decoding: try JSONEncoder().encode(envelope), as: UTF8.self))
        } catch {
            throw RemoteControlWebsocketWriterError.serializationFailed(Self.errorDescription(error))
        }
    }

    private static func errorDescription(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }
}

public enum RemoteControlWebsocketIncomingMessage: Equatable, Sendable {
    case text(String)
    case binary(Data)
    case ping
    case pong
    case close
    case streamEnded
    case readError(String)
}

public enum RemoteControlWebsocketReaderError: Error, CustomStringConvertible, Equatable, Sendable {
    case unexpectedEOF
    case connectionAborted
    case invalidData(String)

    public var description: String {
        switch self {
        case .unexpectedEOF:
            return "websocket stream ended"
        case .connectionAborted:
            return "websocket disconnected"
        case let .invalidData(message):
            return "failed to read from websocket: \(message)"
        }
    }
}

public struct RemoteControlWebsocketReaderCore: Equatable, Sendable {
    public static var idleSweepIntervalSeconds: TimeInterval { 30 }
    public static var pongTimeoutSeconds: TimeInterval { 60 }

    public init() {}

    public mutating func process(
        _ incomingMessage: RemoteControlWebsocketIncomingMessage,
        state: inout RemoteControlWebsocketState,
        clientTracker: inout RemoteControlClientTracker,
        now: TimeInterval = Date().timeIntervalSinceReferenceDate
    ) throws -> [RemoteControlClientTrackerEffect] {
        let clientEnvelope: RemoteControlClientEnvelope
        let wireSizeBytes: Int
        switch incomingMessage {
        case let .text(text):
            wireSizeBytes = text.utf8.count
            guard let data = text.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(RemoteControlClientEnvelope.self, from: data)
            else {
                return []
            }
            clientEnvelope = decoded
        case .pong, .ping, .binary:
            return []
        case .close:
            throw RemoteControlWebsocketReaderError.connectionAborted
        case .streamEnded:
            throw RemoteControlWebsocketReaderError.unexpectedEOF
        case let .readError(message):
            throw RemoteControlWebsocketReaderError.invalidData(message)
        }

        let observation = state.observeClientEnvelope(clientEnvelope, wireSizeBytes: wireSizeBytes)
        guard case let .forward(forwardedEnvelope) = observation else {
            return []
        }

        let closedClient = closedClientKey(for: forwardedEnvelope)
        let effects = clientTracker.handleClientEnvelope(forwardedEnvelope, now: now)
        if let closedClient {
            switch closedClient.streamID {
            case let .some(streamID):
                state.invalidateClientMessageStream(clientID: closedClient.clientID, streamID: streamID)
            case .none:
                state.invalidateClientMessageClient(clientID: closedClient.clientID)
            }
        }
        return effects
    }

    private func closedClientKey(
        for envelope: RemoteControlClientEnvelope
    ) -> (clientID: RemoteControlClientID, streamID: RemoteControlStreamID?)? {
        guard case .clientClosed = envelope.event else {
            return nil
        }
        return (envelope.clientID, envelope.streamID)
    }
}

public enum RemoteControlClientSegmentObservation: Equatable, Sendable {
    case forward(RemoteControlClientEnvelope)
    case pending
    case dropped
}

public struct RemoteControlClientMessageObserver: Equatable, Sendable {
    public static var segmentTargetBytes: Int { 100 * 1024 }
    public static var segmentMaxBytes: Int { 150 * 1024 }
    public static var reassembledMaxBytes: Int { 100 * 1024 * 1024 }
    public static var segmentCountMax: Int { 1_024 }
    private static var segmentAssemblyMaxCount: Int { 128 }

    private struct ClientStreamKey: Hashable, Sendable {
        var clientID: RemoteControlClientID
        var streamID: RemoteControlStreamID?
    }

    private struct SegmentAssembly: Equatable, Sendable {
        var streamID: RemoteControlStreamID
        var metadata: SegmentMetadata
        var raw: Data
        var nextSegmentID: Int
        var lastChunkSeenOrder: UInt64
    }

    private struct SegmentMetadata: Equatable, Sendable {
        var seqID: UInt64
        var segmentCount: Int
        var messageSizeBytes: Int
    }

    private enum AssemblyUpdate: Equatable, Sendable {
        case pending
        case ignore
        case drop
        case complete(ExecServerJSONRPCMessage)
    }

    private var assembliesByClientID: [RemoteControlClientID: SegmentAssembly] = [:]
    private var lastCompletedSeqIDByStream: [ClientStreamKey: UInt64] = [:]
    private var chunkOrder: UInt64 = 0

    public init() {}

    public mutating func observe(
        _ envelope: RemoteControlClientEnvelope,
        wireSizeBytes: Int
    ) -> RemoteControlClientSegmentObservation {
        let messageKey = clientMessageKey(for: envelope)
        if let (key, seqID) = messageKey,
           let lastSeqID = lastCompletedSeqIDByStream[key],
           lastSeqID >= seqID
        {
            return .dropped
        }

        if let (_, seqID) = messageKey,
           let streamID = envelope.streamID,
           case let .clientMessageChunk(segmentID, _, _, _) = envelope.event,
           shouldIgnoreChunk(
               clientID: envelope.clientID,
               streamID: streamID,
               seqID: seqID,
               segmentID: segmentID
           )
        {
            return .dropped
        }

        if messageKey != nil, wireSizeBytes > Self.segmentMaxBytes {
            if let streamID = envelope.streamID {
                invalidateStream(clientID: envelope.clientID, streamID: streamID)
            }
            return .dropped
        }

        let observation = observeSegment(envelope)
        if case .forward = observation, let (key, seqID) = messageKey {
            lastCompletedSeqIDByStream[key] = seqID
        }
        return observation
    }

    public mutating func invalidateStream(
        clientID: RemoteControlClientID,
        streamID: RemoteControlStreamID
    ) {
        lastCompletedSeqIDByStream.removeValue(forKey: ClientStreamKey(clientID: clientID, streamID: streamID))
        removeAssembly(clientID: clientID, streamID: streamID)
    }

    public mutating func invalidateClient(clientID: RemoteControlClientID) {
        lastCompletedSeqIDByStream = lastCompletedSeqIDByStream.filter { key, _ in
            key.clientID != clientID
        }
        assembliesByClientID.removeValue(forKey: clientID)
    }

    private func clientMessageKey(
        for envelope: RemoteControlClientEnvelope
    ) -> (ClientStreamKey, UInt64)? {
        guard case .clientMessageChunk = envelope.event,
              let seqID = envelope.seqID
        else {
            return nil
        }
        return (ClientStreamKey(clientID: envelope.clientID, streamID: envelope.streamID), seqID)
    }

    private mutating func observeSegment(_ envelope: RemoteControlClientEnvelope) -> RemoteControlClientSegmentObservation {
        guard case let .clientMessageChunk(segmentID, segmentCount, messageSizeBytes, messageChunkBase64) = envelope.event else {
            return .forward(envelope)
        }
        guard let metadata = segmentMetadata(for: envelope) else {
            return .dropped
        }
        guard let streamID = envelope.streamID else {
            return .dropped
        }
        if shouldIgnoreChunk(
            clientID: envelope.clientID,
            streamID: streamID,
            seqID: metadata.seqID,
            segmentID: segmentID
        ) {
            return .dropped
        }
        if segmentCount == 0
            || segmentCount > Self.segmentCountMax
            || segmentID >= segmentCount
            || messageSizeBytes == 0
            || messageSizeBytes > Self.reassembledMaxBytes
            || messageChunkBase64.isEmpty
        {
            removeAssembly(clientID: envelope.clientID, streamID: streamID)
            return .dropped
        }

        chunkOrder &+= 1
        if let assembly = assembliesByClientID[envelope.clientID] {
            if assembly.streamID != streamID {
                assembliesByClientID[envelope.clientID] = SegmentAssembly(
                    streamID: streamID,
                    metadata: metadata,
                    raw: Data(),
                    nextSegmentID: 0,
                    lastChunkSeenOrder: chunkOrder
                )
            }
        } else {
            evictAssembliesIfFull()
            assembliesByClientID[envelope.clientID] = SegmentAssembly(
                streamID: streamID,
                metadata: metadata,
                raw: Data(),
                nextSegmentID: 0,
                lastChunkSeenOrder: chunkOrder
            )
        }

        let update = applyChunk(
            envelope: envelope,
            metadata: metadata,
            segmentID: segmentID,
            messageChunkBase64: messageChunkBase64
        )
        switch update {
        case .pending:
            return .pending
        case .ignore:
            return .dropped
        case .drop:
            removeAssembly(clientID: envelope.clientID, streamID: streamID)
            return .dropped
        case let .complete(message):
            removeAssembly(clientID: envelope.clientID, streamID: streamID)
            return .forward(RemoteControlClientEnvelope(
                event: .clientMessage(message: message),
                clientID: envelope.clientID,
                streamID: envelope.streamID,
                seqID: envelope.seqID,
                cursor: envelope.cursor
            ))
        }
    }

    private mutating func applyChunk(
        envelope: RemoteControlClientEnvelope,
        metadata: SegmentMetadata,
        segmentID: Int,
        messageChunkBase64: String
    ) -> AssemblyUpdate {
        guard var assembly = assembliesByClientID[envelope.clientID] else {
            return .drop
        }
        if metadata.seqID < assembly.metadata.seqID {
            return .ignore
        }
        if assembly.metadata != metadata {
            return .drop
        }
        if segmentID < assembly.nextSegmentID {
            return .pending
        }
        if segmentID != assembly.nextSegmentID {
            return .drop
        }
        guard let chunk = Data(base64Encoded: messageChunkBase64) else {
            return .drop
        }
        let nextRawCount = assembly.raw.count + chunk.count
        guard nextRawCount <= metadata.messageSizeBytes else {
            return .drop
        }

        assembly.raw.append(chunk)
        assembly.nextSegmentID += 1
        assembly.lastChunkSeenOrder = chunkOrder
        assembliesByClientID[envelope.clientID] = assembly

        if assembly.nextSegmentID < metadata.segmentCount {
            return .pending
        }
        guard assembly.raw.count == metadata.messageSizeBytes else {
            return .drop
        }
        do {
            let message = try JSONDecoder().decode(ExecServerJSONRPCMessage.self, from: assembly.raw)
            return .complete(message)
        } catch {
            return .drop
        }
    }

    private func segmentMetadata(for envelope: RemoteControlClientEnvelope) -> SegmentMetadata? {
        guard case let .clientMessageChunk(_, segmentCount, messageSizeBytes, _) = envelope.event,
              let seqID = envelope.seqID
        else {
            return nil
        }
        return SegmentMetadata(seqID: seqID, segmentCount: segmentCount, messageSizeBytes: messageSizeBytes)
    }

    private func shouldIgnoreChunk(
        clientID: RemoteControlClientID,
        streamID: RemoteControlStreamID,
        seqID: UInt64,
        segmentID: Int
    ) -> Bool {
        guard let assembly = assembliesByClientID[clientID], assembly.streamID == streamID else {
            return false
        }
        return seqID < assembly.metadata.seqID
            || (seqID == assembly.metadata.seqID && segmentID < assembly.nextSegmentID)
    }

    private mutating func removeAssembly(
        clientID: RemoteControlClientID,
        streamID: RemoteControlStreamID
    ) {
        if assembliesByClientID[clientID]?.streamID == streamID {
            assembliesByClientID.removeValue(forKey: clientID)
        }
    }

    private mutating func evictAssembliesIfFull() {
        while assembliesByClientID.count >= Self.segmentAssemblyMaxCount {
            guard let oldestClientID = assembliesByClientID.min(by: {
                $0.value.lastChunkSeenOrder < $1.value.lastChunkSeenOrder
            })?.key else {
                return
            }
            assembliesByClientID.removeValue(forKey: oldestClientID)
        }
    }
}

public enum RemoteControlServerEnvelopeSplitter {
    public static func splitForTransport(_ envelope: RemoteControlServerEnvelope) throws -> [RemoteControlServerEnvelope] {
        guard case let .serverMessage(message) = envelope.event else {
            return [envelope]
        }

        let envelopeSizeBytes = try serializedLength(envelope)
        if envelopeSizeBytes <= RemoteControlClientMessageObserver.segmentMaxBytes {
            return [envelope]
        }

        let raw = try JSONEncoder().encode(message)
        let messageSizeBytes = raw.count
        if messageSizeBytes > RemoteControlClientMessageObserver.reassembledMaxBytes {
            return []
        }

        let minimalSegmentCount = min(max(messageSizeBytes, 1), RemoteControlClientMessageObserver.segmentCountMax)
        let minimalChunk = raw.prefix(min(raw.count, 1))
        if try serializedChunkLength(
            envelope: envelope,
            segmentID: 0,
            segmentCount: minimalSegmentCount,
            messageSizeBytes: messageSizeBytes,
            chunk: minimalChunk
        ) > RemoteControlClientMessageObserver.segmentMaxBytes {
            return []
        }

        var segmentCount = max(
            2,
            ceilDiv(messageSizeBytes, RemoteControlClientMessageObserver.segmentTargetBytes)
        )
        while true {
            let chunkSize = max(1, ceilDiv(messageSizeBytes, segmentCount))
            segmentCount = ceilDiv(messageSizeBytes, chunkSize)
            var segmentsFit = true
            for (segmentID, chunk) in chunks(raw, chunkSize: chunkSize).enumerated() {
                let chunkLength = try serializedChunkLength(
                    envelope: envelope,
                    segmentID: segmentID,
                    segmentCount: segmentCount,
                    messageSizeBytes: messageSizeBytes,
                    chunk: chunk
                )
                if chunkLength > RemoteControlClientMessageObserver.segmentMaxBytes {
                    segmentsFit = false
                    break
                }
            }
            if segmentsFit {
                return try chunks(raw, chunkSize: chunkSize).enumerated().map { segmentID, chunk in
                    try buildChunkEnvelope(
                        envelope: envelope,
                        segmentID: segmentID,
                        segmentCount: segmentCount,
                        messageSizeBytes: messageSizeBytes,
                        chunk: chunk
                    )
                }
            }
            if chunkSize == 1 {
                return []
            }
            let nextSegmentCount = segmentCount + 1
            let nextChunkSize = max(1, ceilDiv(messageSizeBytes, nextSegmentCount))
            segmentCount = nextChunkSize == chunkSize ? messageSizeBytes : nextSegmentCount
        }
    }

    private static func serializedChunkLength(
        envelope: RemoteControlServerEnvelope,
        segmentID: Int,
        segmentCount: Int,
        messageSizeBytes: Int,
        chunk: Data.SubSequence
    ) throws -> Int {
        try serializedLength(buildChunkEnvelope(
            envelope: envelope,
            segmentID: segmentID,
            segmentCount: segmentCount,
            messageSizeBytes: messageSizeBytes,
            chunk: chunk
        ))
    }

    private static func serializedLength<T: Encodable>(_ value: T) throws -> Int {
        try JSONEncoder().encode(value).count
    }

    private static func buildChunkEnvelope(
        envelope: RemoteControlServerEnvelope,
        segmentID: Int,
        segmentCount: Int,
        messageSizeBytes: Int,
        chunk: Data.SubSequence
    ) throws -> RemoteControlServerEnvelope {
        if segmentCount > RemoteControlClientMessageObserver.segmentCountMax {
            throw RemoteControlServerEnvelopeSplitterError.segmentCountExceedsMaximum
        }
        return RemoteControlServerEnvelope(
            event: .serverMessageChunk(
                segmentID: segmentID,
                segmentCount: segmentCount,
                messageSizeBytes: messageSizeBytes,
                messageChunkBase64: Data(chunk).base64EncodedString()
            ),
            clientID: envelope.clientID,
            streamID: envelope.streamID,
            seqID: envelope.seqID
        )
    }

    private static func chunks(_ data: Data, chunkSize: Int) -> [Data.SubSequence] {
        stride(from: 0, to: data.count, by: chunkSize).map { start in
            let end = min(start + chunkSize, data.count)
            return data[start..<end]
        }
    }

    private static func ceilDiv(_ lhs: Int, _ rhs: Int) -> Int {
        guard rhs > 0 else {
            return 0
        }
        return (lhs + rhs - 1) / rhs
    }
}

public enum RemoteControlServerEnvelopeSplitterError: Error, CustomStringConvertible, Equatable, Sendable {
    case segmentCountExceedsMaximum

    public var description: String {
        switch self {
        case .segmentCountExceedsMaximum:
            return "remote-control segment count exceeds maximum"
        }
    }
}

public enum RemoteControlAuthLoadError: Error, CustomStringConvertible, Equatable, Sendable {
    case requiresChatGPTAuthentication
    case apiKeyUnsupported
    case waitingForChatGPTAccountID
    case loadFailed(String)

    public var description: String {
        switch self {
        case .requiresChatGPTAuthentication:
            return "remote control requires ChatGPT authentication"
        case .apiKeyUnsupported:
            return "remote control requires ChatGPT authentication; API key auth is not supported"
        case .waitingForChatGPTAccountID:
            return "remote control enrollment is waiting for a ChatGPT account id"
        case let .loadFailed(message):
            return message
        }
    }
}

public struct RemoteControlAuthLoader: Sendable {
    public typealias LoadAuth = @Sendable () async throws -> AuthDotJSON?
    public typealias ReloadAuth = @Sendable () async throws -> Void

    private let loadAuth: LoadAuth
    private let reloadAuth: ReloadAuth

    public init(
        loadAuth: @escaping LoadAuth,
        reloadAuth: @escaping ReloadAuth
    ) {
        self.loadAuth = loadAuth
        self.reloadAuth = reloadAuth
    }

    public func load() async throws -> RemoteControlConnectionAuth<StaticAPIAuthProvider> {
        var reloaded = false
        let auth: AuthDotJSON
        while true {
            let loadedAuth: AuthDotJSON?
            do {
                loadedAuth = try await loadAuth()
            } catch {
                throw RemoteControlAuthLoadError.loadFailed(Self.errorDescription(error))
            }
            guard let loadedAuth else {
                if reloaded {
                    throw RemoteControlAuthLoadError.requiresChatGPTAuthentication
                }
                try await reload()
                reloaded = true
                continue
            }

            if !Self.isChatGPTAuth(loadedAuth) {
                if Self.hasUsableAuthMaterial(loadedAuth) {
                    throw RemoteControlAuthLoadError.apiKeyUnsupported
                }
                if reloaded {
                    throw RemoteControlAuthLoadError.requiresChatGPTAuthentication
                }
                try await reload()
                reloaded = true
                continue
            }

            if loadedAuth.tokens?.accountID == nil, !reloaded {
                try await reload()
                reloaded = true
                continue
            }

            auth = loadedAuth
            break
        }

        guard Self.isChatGPTAuth(auth), let tokens = auth.tokens else {
            throw RemoteControlAuthLoadError.apiKeyUnsupported
        }
        guard let accountID = tokens.accountID else {
            throw RemoteControlAuthLoadError.waitingForChatGPTAccountID
        }
        return RemoteControlConnectionAuth(
            authProvider: StaticAPIAuthProvider(
                bearerToken: tokens.accessToken,
                accountID: tokens.accountID
            ),
            accountID: accountID
        )
    }

    private func reload() async throws {
        do {
            try await reloadAuth()
        } catch {
            throw RemoteControlAuthLoadError.loadFailed(Self.errorDescription(error))
        }
    }

    private static func isChatGPTAuth(_ auth: AuthDotJSON) -> Bool {
        auth.openAIAPIKey == nil
            && auth.tokens != nil
            && auth.authMode != .apiKey
    }

    private static func hasUsableAuthMaterial(_ auth: AuthDotJSON) -> Bool {
        auth.openAIAPIKey != nil || auth.tokens != nil
    }

    private static func errorDescription(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }
}

/// Stores remote-control enrollments using Rust's `(websocket_url, account_id, app_server_client_name)` key.
///
/// Implementers provide the durable state database used by the remote-control
/// connect loop. Callers may rely on nil client names being represented through
/// the same key normalization as the Swift SQLite store, and on failures being
/// surfaced without retry side effects.
public protocol RemoteControlEnrollmentStore: Sendable {
    func getRemoteControlEnrollment(
        websocketURL: String,
        accountID: String,
        appServerClientName: String?
    ) async throws -> RemoteControlEnrollmentRecord?

    func upsertRemoteControlEnrollment(_ enrollment: RemoteControlEnrollmentRecord) async throws

    @discardableResult
    func deleteRemoteControlEnrollment(
        websocketURL: String,
        accountID: String,
        appServerClientName: String?
    ) async throws -> Int
}

extension SQLiteAgentGraphStore: RemoteControlEnrollmentStore {}

public enum RemoteControlEnrollmentPersistenceError: Error, CustomStringConvertible, Equatable, Sendable {
    case cacheUnavailable(websocketURL: String, accountID: String, appServerClientName: String?)
    case persistenceUnavailable(websocketURL: String, accountID: String, appServerClientName: String?, hasEnrollment: Bool)
    case accountIDMismatch(expectedAccountID: String)
    case storeFailed(String)

    public var description: String {
        switch self {
        case let .cacheUnavailable(websocketURL, accountID, appServerClientName):
            return "remote control enrollment cache unavailable because sqlite state db is disabled: websocket_url=\(websocketURL), account_id=\(accountID), app_server_client_name=\(Self.rustOptionalString(appServerClientName))"
        case let .persistenceUnavailable(websocketURL, accountID, appServerClientName, hasEnrollment):
            return "remote control enrollment persistence unavailable because sqlite state db is disabled: websocket_url=\(websocketURL), account_id=\(accountID), app_server_client_name=\(Self.rustOptionalString(appServerClientName)), has_enrollment=\(hasEnrollment)"
        case let .accountIDMismatch(expectedAccountID):
            return "enrollment account_id does not match expected account_id `\(expectedAccountID)`"
        case let .storeFailed(message):
            return message
        }
    }

    private static func rustOptionalString(_ value: String?) -> String {
        switch value {
        case let .some(value):
            return "Some(\"\(value)\")"
        case .none:
            return "None"
        }
    }
}

public enum RemoteControlEnrollmentPersistence {
    public static func load(
        store: RemoteControlEnrollmentStore?,
        target: RemoteControlTarget,
        accountID: String,
        appServerClientName: String?
    ) async throws -> RemoteControlEnrollment? {
        guard let store else {
            throw RemoteControlEnrollmentPersistenceError.cacheUnavailable(
                websocketURL: target.websocketURL,
                accountID: accountID,
                appServerClientName: appServerClientName
            )
        }
        do {
            guard let record = try await store.getRemoteControlEnrollment(
                websocketURL: target.websocketURL,
                accountID: accountID,
                appServerClientName: appServerClientName
            ) else {
                return nil
            }
            return RemoteControlEnrollment(
                accountID: record.accountID,
                environmentID: record.environmentID,
                serverID: record.serverID,
                serverName: record.serverName
            )
        } catch let error as RemoteControlEnrollmentPersistenceError {
            throw error
        } catch {
            throw RemoteControlEnrollmentPersistenceError.storeFailed(Self.errorDescription(error))
        }
    }

    public static func update(
        store: RemoteControlEnrollmentStore?,
        target: RemoteControlTarget,
        accountID: String,
        appServerClientName: String?,
        enrollment: RemoteControlEnrollment?
    ) async throws {
        guard let store else {
            throw RemoteControlEnrollmentPersistenceError.persistenceUnavailable(
                websocketURL: target.websocketURL,
                accountID: accountID,
                appServerClientName: appServerClientName,
                hasEnrollment: enrollment != nil
            )
        }
        if let enrollment, enrollment.accountID != accountID {
            throw RemoteControlEnrollmentPersistenceError.accountIDMismatch(expectedAccountID: accountID)
        }
        do {
            if let enrollment {
                try await store.upsertRemoteControlEnrollment(RemoteControlEnrollmentRecord(
                    websocketURL: target.websocketURL,
                    accountID: accountID,
                    appServerClientName: appServerClientName,
                    serverID: enrollment.serverID,
                    environmentID: enrollment.environmentID,
                    serverName: enrollment.serverName
                ))
            } else {
                _ = try await store.deleteRemoteControlEnrollment(
                    websocketURL: target.websocketURL,
                    accountID: accountID,
                    appServerClientName: appServerClientName
                )
            }
        } catch let error as RemoteControlEnrollmentPersistenceError {
            throw error
        } catch {
            throw RemoteControlEnrollmentPersistenceError.storeFailed(Self.errorDescription(error))
        }
    }

    private static func errorDescription(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }
}

public enum RemoteControlURLNormalizationError: Error, CustomStringConvertible, Equatable, Sendable {
    case invalidURL(remoteControlURL: String, message: String)
    case unsupportedURL(remoteControlURL: String)

    public var description: String {
        switch self {
        case let .invalidURL(remoteControlURL, message):
            return "invalid remote control URL `\(remoteControlURL)`: \(message)"
        case let .unsupportedURL(remoteControlURL):
            return "invalid remote control URL `\(remoteControlURL)`; expected HTTPS URL for chatgpt.com or chatgpt-staging.com, or HTTP/HTTPS URL for localhost"
        }
    }
}

public enum RemoteControlEnrollmentError: Error, CustomStringConvertible, Equatable, Sendable {
    case requestFailed(enrollURL: String, message: String)
    case enrollmentFailed(enrollURL: String, statusCode: Int, headers: [String: String], bodyPreview: String)
    case decodeFailed(enrollURL: String, statusCode: Int, headers: [String: String], bodyPreview: String, message: String)

    public var description: String {
        switch self {
        case let .requestFailed(enrollURL, message):
            return "failed to enroll remote control server at `\(enrollURL)`: \(message)"
        case let .enrollmentFailed(enrollURL, statusCode, headers, bodyPreview):
            return "remote control server enrollment failed at `\(enrollURL)`: HTTP \(RemoteControlHTTPFormatting.statusDescription(statusCode)), \(RemoteControlHTTPFormatting.formattedHeaders(headers)), body: \(bodyPreview)"
        case let .decodeFailed(enrollURL, statusCode, headers, bodyPreview, message):
            return "failed to parse remote control enrollment response from `\(enrollURL)`: HTTP \(RemoteControlHTTPFormatting.statusDescription(statusCode)), \(RemoteControlHTTPFormatting.formattedHeaders(headers)), body: \(bodyPreview), decode error: \(message)"
        }
    }

    public var isPermissionDenied: Bool {
        switch self {
        case let .enrollmentFailed(_, statusCode, _, _):
            return statusCode == 401 || statusCode == 403
        case .requestFailed, .decodeFailed:
            return false
        }
    }
}

private enum RemoteControlHTTPFormatting {
    static func formattedHeaders(_ headers: [String: String]) -> String {
        let normalized = Dictionary(uniqueKeysWithValues: headers.map { key, value in
            (key.lowercased(), value)
        })
        let requestID = normalized["x-request-id"] ?? normalized["x-oai-request-id"] ?? "<none>"
        let cfRay = normalized["cf-ray"] ?? "<none>"
        return "request-id: \(requestID), cf-ray: \(cfRay)"
    }

    static func statusDescription(_ statusCode: Int) -> String {
        switch statusCode {
        case 400:
            return "400 Bad Request"
        case 401:
            return "401 Unauthorized"
        case 403:
            return "403 Forbidden"
        case 404:
            return "404 Not Found"
        case 429:
            return "429 Too Many Requests"
        case 500:
            return "500 Internal Server Error"
        case 502:
            return "502 Bad Gateway"
        case 503:
            return "503 Service Unavailable"
        case 504:
            return "504 Gateway Timeout"
        default:
            return "\(statusCode)"
        }
    }

    static func previewResponseBody(_ body: Data) -> String {
        let trimmed = String(decoding: body, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "<empty>"
        }
        guard trimmed.utf8.count > 4_096 else {
            return trimmed
        }
        let bytes = Array(trimmed.utf8)
        var end = 4_096
        while end > 0, String(data: Data(bytes.prefix(end)), encoding: .utf8) == nil {
            end -= 1
        }
        return "\(String(decoding: bytes.prefix(end), as: UTF8.self))..."
    }
}

public enum RemoteControlWebSocketRequestError: Error, CustomStringConvertible, Equatable, Sendable {
    case invalidWebSocketURL(websocketURL: String, message: String)
    case invalidHeader(name: String, message: String)

    public var description: String {
        switch self {
        case let .invalidWebSocketURL(websocketURL, message):
            return "invalid remote control websocket URL `\(websocketURL)`: \(message)"
        case let .invalidHeader(name, message):
            return "invalid remote control header `\(name)`: \(message)"
        }
    }
}

public struct RemoteControlWebSocketRequestBuilder<Auth: APIAuthProvider>: Sendable {
    public static var protocolVersion: String { "3" }
    public static var serverIDHeader: String { "x-codex-server-id" }
    public static var serverNameHeader: String { "x-codex-name" }
    public static var protocolVersionHeader: String { "x-codex-protocol-version" }
    public static var accountIDHeader: String { "chatgpt-account-id" }
    public static var installationIDHeader: String { "x-codex-installation-id" }
    public static var subscribeCursorHeader: String { "x-codex-subscribe-cursor" }

    private let auth: RemoteControlConnectionAuth<Auth>
    private let installationID: String

    public init(auth: RemoteControlConnectionAuth<Auth>, installationID: String) {
        self.auth = auth
        self.installationID = installationID
    }

    public func buildRequest(
        websocketURL: String,
        enrollment: RemoteControlEnrollment,
        subscribeCursor: String? = nil
    ) throws -> URLRequest {
        guard let components = URLComponents(string: websocketURL),
              let scheme = components.scheme,
              scheme == "ws" || scheme == "wss",
              let url = components.url
        else {
            throw RemoteControlWebSocketRequestError.invalidWebSocketURL(
                websocketURL: websocketURL,
                message: "expected ws:// or wss:// URL"
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        try setHeader(name: Self.serverIDHeader, value: enrollment.serverID, on: &request)
        try setHeader(
            name: Self.serverNameHeader,
            value: Data(enrollment.serverName.utf8).base64EncodedString(),
            on: &request
        )
        try setHeader(name: Self.protocolVersionHeader, value: Self.protocolVersion, on: &request)
        try addAuthHeaders(to: &request)
        try setHeader(name: Self.accountIDHeader, value: enrollment.accountID, on: &request)
        try setHeader(name: Self.installationIDHeader, value: installationID, on: &request)
        if let subscribeCursor {
            try setHeader(name: Self.subscribeCursorHeader, value: subscribeCursor, on: &request)
        }
        return request
    }

    private func addAuthHeaders(to request: inout URLRequest) throws {
        if let bearerToken = auth.authProvider.bearerToken {
            try setHeader(name: APIAuthHeaders.authorization, value: "Bearer \(bearerToken)", on: &request)
        }
        if let providerAccountID = auth.authProvider.accountID {
            try setHeader(name: APIAuthHeaders.chatGPTAccountID, value: providerAccountID, on: &request)
        }
    }

    private func setHeader(name: String, value: String, on request: inout URLRequest) throws {
        guard isHeaderName(name) else {
            throw RemoteControlWebSocketRequestError.invalidHeader(name: name, message: "invalid header name")
        }
        guard isHeaderValue(value) else {
            throw RemoteControlWebSocketRequestError.invalidHeader(name: name, message: "invalid header value")
        }
        request.setValue(value, forHTTPHeaderField: name)
    }

    private func isHeaderName(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { scalar in
            scalar.value >= 0x21 && scalar.value <= 0x7E && !"()<>@,;:\\\"/[]?={} \t".unicodeScalars.contains(scalar)
        }
    }

    private func isHeaderValue(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { scalar in
            scalar.value == 0x09 || (scalar.value >= 0x20 && scalar.value != 0x7F)
        }
    }
}

public enum RemoteControlWebSocketConnectErrorFormatter {
    public static func formatHTTPError(
        websocketURL: String,
        statusCode: Int,
        headers: [String: String],
        body: Data
    ) -> String {
        var message = "failed to connect app-server remote control websocket `\(websocketURL)`: HTTP error: \(RemoteControlHTTPFormatting.statusDescription(statusCode)), \(RemoteControlHTTPFormatting.formattedHeaders(headers))"
        if !body.isEmpty {
            message += ", body: \(RemoteControlHTTPFormatting.previewResponseBody(body))"
        }
        return message
    }
}

public struct RemoteControlEnrollmentClient<Auth: APIAuthProvider>: Sendable {
    public typealias Send = @Sendable (URLRequest) async throws -> URLSessionTransportResponse

    public static var enrollTimeout: TimeInterval { 30 }
    public static var accountIDHeader: String { "chatgpt-account-id" }
    public static var installationIDHeader: String { "x-codex-installation-id" }

    private let auth: RemoteControlConnectionAuth<Auth>
    private let installationID: String
    private let appServerVersion: String
    private let serverName: String
    private let os: String
    private let arch: String
    private let send: Send

    public init(
        auth: RemoteControlConnectionAuth<Auth>,
        installationID: String,
        appServerVersion: String,
        serverName: String = Host.current().localizedName ?? "unknown",
        os: String = RemoteControlEnrollmentClient.defaultOS,
        arch: String = RemoteControlEnrollmentClient.defaultArch,
        send: @escaping Send = RemoteControlEnrollmentClient.urlSessionSend
    ) {
        self.auth = auth
        self.installationID = installationID
        self.appServerVersion = appServerVersion
        self.serverName = serverName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.os = os
        self.arch = arch
        self.send = send
    }

    public func enroll(target: RemoteControlTarget) async throws -> RemoteControlEnrollment {
        let enrollURL = target.enrollURL
        let request = try buildEnrollmentRequest(enrollURL: enrollURL)
        let response: URLSessionTransportResponse
        do {
            response = try await send(request)
        } catch {
            throw RemoteControlEnrollmentError.requestFailed(
                enrollURL: enrollURL,
                message: Self.errorDescription(error)
            )
        }

        let bodyPreview = Self.previewResponseBody(response.body)
        guard (200..<300).contains(response.statusCode) else {
            throw RemoteControlEnrollmentError.enrollmentFailed(
                enrollURL: enrollURL,
                statusCode: response.statusCode,
                headers: response.headers,
                bodyPreview: bodyPreview
            )
        }

        do {
            let payload = try JSONDecoder().decode(EnrollRemoteServerResponse.self, from: response.body)
            return RemoteControlEnrollment(
                accountID: auth.accountID,
                environmentID: payload.environmentID,
                serverID: payload.serverID,
                serverName: serverName
            )
        } catch {
            throw RemoteControlEnrollmentError.decodeFailed(
                enrollURL: enrollURL,
                statusCode: response.statusCode,
                headers: response.headers,
                bodyPreview: bodyPreview,
                message: Self.errorDescription(error)
            )
        }
    }

    public func buildEnrollmentRequest(enrollURL: String) throws -> URLRequest {
        guard let url = URL(string: enrollURL) else {
            throw RemoteControlEnrollmentError.requestFailed(
                enrollURL: enrollURL,
                message: "invalid URL"
            )
        }
        var request = URLRequest(url: url, timeoutInterval: Self.enrollTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        addAuthHeaders(to: &request)
        request.setValue(auth.accountID, forHTTPHeaderField: Self.accountIDHeader)
        request.setValue(installationID, forHTTPHeaderField: Self.installationIDHeader)
        request.httpBody = try JSONEncoder().encode(EnrollRemoteServerRequest(
            name: serverName,
            os: os,
            arch: arch,
            appServerVersion: appServerVersion,
            installationID: installationID
        ))
        return request
    }

    public static func previewResponseBody(_ body: Data) -> String {
        RemoteControlHTTPFormatting.previewResponseBody(body)
    }

    private func addAuthHeaders(to request: inout URLRequest) {
        if let bearerToken = auth.authProvider.bearerToken {
            let value = "Bearer \(bearerToken)"
            if Self.isHeaderValue(value) {
                request.setValue(value, forHTTPHeaderField: APIAuthHeaders.authorization)
            }
        }
        if let providerAccountID = auth.authProvider.accountID, Self.isHeaderValue(providerAccountID) {
            request.setValue(providerAccountID, forHTTPHeaderField: APIAuthHeaders.chatGPTAccountID)
        }
    }

    public static var defaultOS: String {
        #if os(macOS)
        return "macos"
        #elseif os(Linux)
        return "linux"
        #elseif os(Windows)
        return "windows"
        #else
        return "unknown"
        #endif
    }

    public static var defaultArch: String {
        #if arch(arm64)
        return "aarch64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private static func isHeaderValue(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { scalar in
            scalar.value == 0x09 || (scalar.value >= 0x20 && scalar.value != 0x7F)
        }
    }

    private static func errorDescription(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }

    public static func urlSessionSend(_ request: URLRequest) async throws -> URLSessionTransportResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RemoteControlEnrollmentError.requestFailed(
                enrollURL: request.url?.absoluteString ?? "<unknown>",
                message: "non-HTTP response"
            )
        }
        return URLSessionTransportResponse(
            statusCode: http.statusCode,
            headers: http.allHeaderFields.reduce(into: [:]) { headers, entry in
                if let key = entry.key as? String, let value = entry.value as? String {
                    headers[key] = value
                }
            },
            body: data
        )
    }

    private struct EnrollRemoteServerRequest: Encodable {
        var name: String
        var os: String
        var arch: String
        var appServerVersion: String
        var installationID: String

        enum CodingKeys: String, CodingKey {
            case name
            case os
            case arch
            case appServerVersion = "app_server_version"
            case installationID = "installation_id"
        }
    }

    private struct EnrollRemoteServerResponse: Decodable {
        var serverID: String
        var environmentID: String

        enum CodingKeys: String, CodingKey {
            case serverID = "server_id"
            case environmentID = "environment_id"
        }
    }
}

public enum RemoteControlURLNormalizer {
    public static func normalize(_ remoteControlURL: String) throws -> RemoteControlTarget {
        guard var components = URLComponents(string: remoteControlURL),
              let scheme = components.scheme,
              let host = components.host,
              !host.isEmpty
        else {
            throw RemoteControlURLNormalizationError.invalidURL(
                remoteControlURL: remoteControlURL,
                message: "relative URL without a base"
            )
        }
        guard scheme == "http" || scheme == "https" else {
            throw RemoteControlURLNormalizationError.unsupportedURL(remoteControlURL: remoteControlURL)
        }

        let normalizedPath = normalizedBasePath(components.percentEncodedPath)
        components.percentEncodedPath = normalizedPath
        components.percentEncodedQuery = nil
        components.percentEncodedFragment = nil
        guard components.url != nil else {
            throw RemoteControlURLNormalizationError.invalidURL(
                remoteControlURL: remoteControlURL,
                message: "invalid path"
            )
        }

        let localhost = isLocalhost(normalizedHost(host))
        switch scheme {
        case "https" where localhost || isAllowedChatGPTHost(host):
            break
        case "http" where localhost:
            break
        default:
            throw RemoteControlURLNormalizationError.unsupportedURL(remoteControlURL: remoteControlURL)
        }

        let enrollURL = try joinedURL(
            components: components,
            pathSuffix: "wham/remote/control/server/enroll",
            remoteControlURL: remoteControlURL
        )
        var websocketComponents = components
        websocketComponents.scheme = scheme == "https" ? "wss" : "ws"
        let websocketURL = try joinedURL(
            components: websocketComponents,
            pathSuffix: "wham/remote/control/server",
            remoteControlURL: remoteControlURL
        )
        return RemoteControlTarget(websocketURL: websocketURL, enrollURL: enrollURL)
    }

    private static func normalizedBasePath(_ path: String) -> String {
        let basePath = path.isEmpty ? "/" : path
        return basePath.hasSuffix("/") ? basePath : "\(basePath)/"
    }

    private static func joinedURL(
        components: URLComponents,
        pathSuffix: String,
        remoteControlURL: String
    ) throws -> String {
        var joinedComponents = components
        joinedComponents.percentEncodedPath = "\(normalizedBasePath(components.percentEncodedPath))\(pathSuffix)"
        guard let url = joinedComponents.url else {
            throw RemoteControlURLNormalizationError.invalidURL(
                remoteControlURL: remoteControlURL,
                message: "invalid URL components"
            )
        }
        return url.absoluteString
    }

    private static func isAllowedChatGPTHost(_ host: String) -> Bool {
        host == "chatgpt.com"
            || host == "chatgpt-staging.com"
            || host.hasSuffix(".chatgpt.com")
            || host.hasSuffix(".chatgpt-staging.com")
    }

    private static func normalizedHost(_ host: String) -> String {
        if host.hasPrefix("[") && host.hasSuffix("]") {
            return String(host.dropFirst().dropLast())
        }
        return host
    }

    private static func isLocalhost(_ host: String) -> Bool {
        if host == "localhost" {
            return true
        }
        var ipv4 = in_addr()
        if host.withCString({ inet_pton(AF_INET, $0, &ipv4) }) == 1 {
            return UInt32(bigEndian: ipv4.s_addr) >> 24 == 127
        }
        var ipv6 = in6_addr()
        if host.withCString({ inet_pton(AF_INET6, $0, &ipv6) }) == 1 {
            var loopback = in6_addr()
            _ = "::1".withCString { inet_pton(AF_INET6, $0, &loopback) }
            return withUnsafeBytes(of: &ipv6) { candidateBytes in
                withUnsafeBytes(of: &loopback) { loopbackBytes in
                    candidateBytes.elementsEqual(loopbackBytes)
                }
            }
        }
        return false
    }
}
