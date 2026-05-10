import Foundation

public actor ExecServerSessionRegistry {
    public typealias IDGenerator = @Sendable () -> String

    private struct SessionEntry: Sendable {
        let sessionID: String
        let processStore: ExecServerProcessStore
        var currentConnectionID: String?
        var detachedConnectionID: String?
        var detachedExpiresAt: Date?
    }

    private var sessions: [String: SessionEntry] = [:]
    private let detachedSessionTTL: TimeInterval
    private let makeID: IDGenerator
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async -> Void

    public init(
        detachedSessionTTL: TimeInterval = 10,
        makeID: @escaping IDGenerator = { UUID().uuidString.lowercased() },
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async -> Void = ExecServerSessionRegistry.defaultSleep
    ) {
        self.detachedSessionTTL = detachedSessionTTL
        self.makeID = makeID
        self.now = now
        self.sleep = sleep
    }

    public func attach(
        resumeSessionID: String? = nil,
        processStore suppliedProcessStore: ExecServerProcessStore? = nil,
        outboundNotification: @escaping ExecServerProcessStore.OutboundNotification = { _ in }
    ) async throws -> ExecServerSessionHandle {
        let connectionID = makeID()
        let sessionID: String
        let processStore: ExecServerProcessStore

        if let resumeSessionID {
            guard var entry = sessions[resumeSessionID] else {
                throw ExecServerRPC.invalidRequest("unknown session id \(resumeSessionID)")
            }
            if isExpired(entry, at: now()) {
                sessions.removeValue(forKey: resumeSessionID)
                await entry.processStore.shutdown()
                throw ExecServerRPC.invalidRequest("unknown session id \(resumeSessionID)")
            }
            if entry.currentConnectionID != nil {
                throw ExecServerRPC.invalidRequest("session \(resumeSessionID) is already attached to another connection")
            }
            entry.currentConnectionID = connectionID
            entry.detachedConnectionID = nil
            entry.detachedExpiresAt = nil
            sessions[resumeSessionID] = entry
            sessionID = resumeSessionID
            processStore = entry.processStore
        } else {
            sessionID = makeID()
            processStore = suppliedProcessStore ?? ExecServerProcessStore(outboundNotification: outboundNotification)
            sessions[sessionID] = SessionEntry(
                sessionID: sessionID,
                processStore: processStore,
                currentConnectionID: connectionID,
                detachedConnectionID: nil,
                detachedExpiresAt: nil
            )
        }

        await processStore.setOutboundNotification(outboundNotification)
        return ExecServerSessionHandle(
            registry: self,
            sessionID: sessionID,
            connectionID: connectionID,
            processStore: processStore
        )
    }

    public func contains(sessionID: String) -> Bool {
        sessions[sessionID] != nil
    }

    fileprivate func isAttached(sessionID: String, connectionID: String) -> Bool {
        sessions[sessionID]?.currentConnectionID == connectionID
    }

    fileprivate func detach(sessionID: String, connectionID: String) {
        guard var entry = sessions[sessionID],
              entry.currentConnectionID == connectionID else {
            return
        }

        entry.currentConnectionID = nil
        entry.detachedConnectionID = connectionID
        entry.detachedExpiresAt = now().addingTimeInterval(detachedSessionTTL)
        sessions[sessionID] = entry

        Task { [weak self] in
            guard let self else {
                return
            }
            await self.sleep(detachedSessionTTL)
            await self.expireIfDetached(sessionID: sessionID, connectionID: connectionID)
        }
    }

    private func expireIfDetached(sessionID: String, connectionID: String) {
        guard let entry = sessions[sessionID],
              entry.currentConnectionID == nil,
              entry.detachedConnectionID == connectionID,
              isExpired(entry, at: now()) else {
            return
        }
        sessions.removeValue(forKey: sessionID)
        Task {
            await entry.processStore.shutdown()
        }
    }

    private func isExpired(_ entry: SessionEntry, at date: Date) -> Bool {
        entry.detachedExpiresAt.map { date >= $0 } ?? false
    }

    public static func defaultSleep(_ seconds: TimeInterval) async {
        let nanoseconds = UInt64(max(seconds, 0) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
    }
}

public struct ExecServerSessionHandle: Sendable {
    private let registry: ExecServerSessionRegistry
    public let sessionID: String
    public let connectionID: String
    public let processStore: ExecServerProcessStore

    fileprivate init(
        registry: ExecServerSessionRegistry,
        sessionID: String,
        connectionID: String,
        processStore: ExecServerProcessStore
    ) {
        self.registry = registry
        self.sessionID = sessionID
        self.connectionID = connectionID
        self.processStore = processStore
    }

    public func isSessionAttached() async -> Bool {
        await registry.isAttached(sessionID: sessionID, connectionID: connectionID)
    }

    public func detach() async {
        await processStore.setOutboundNotification { _ in }
        await registry.detach(sessionID: sessionID, connectionID: connectionID)
    }
}
