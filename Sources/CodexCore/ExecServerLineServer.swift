import Foundation

public enum ExecServerLineDrainMode: Sendable {
    case includeQueued
    case directOnly
}

public actor ExecServerLineServer {
    private let connection: ExecServerConnection
    private let connectionLabel: String

    public init(
        sessionRegistry: ExecServerSessionRegistry = ExecServerSessionRegistry(),
        router: ExecServerRouter = ExecServerRouter(),
        httpClient: ExecServerHTTPClient = ExecServerHTTPClient(),
        connectionLabel: String = "exec-server stdio"
    ) {
        self.connection = ExecServerConnection(
            sessionRegistry: sessionRegistry,
            router: router,
            httpClient: httpClient
        )
        self.connectionLabel = connectionLabel
    }

    public func receiveLine(
        _ line: String,
        drainMode: ExecServerLineDrainMode = .includeQueued
    ) async throws -> [Data] {
        let direct = await connection.handleStdioLine(line, connectionLabel: connectionLabel)
        var lines = try encode(direct)
        if drainMode == .includeQueued {
            lines += try await drainQueuedLines()
        }
        return lines
    }

    public func disconnect(reason: String? = nil) async throws -> [Data] {
        let direct = await connection.handle(ExecServerJSONRPCCodec.disconnected(reason: reason))
        var lines = try encode(direct)
        lines += try await drainQueuedLines()
        return lines
    }

    public func drainQueuedLines() async throws -> [Data] {
        var lines: [Data] = []
        while let outbound = await connection.nextOutbound() {
            lines.append(try ExecServerJSONRPCCodec.encodeLine(outbound.jsonRPCMessage))
        }
        return lines
    }

    public func nextQueuedLine() async throws -> Data? {
        guard let outbound = await connection.waitForOutbound() else {
            return nil
        }
        return try ExecServerJSONRPCCodec.encodeLine(outbound.jsonRPCMessage)
    }

    public func isClosed() async -> Bool {
        await connection.isClosed()
    }

    private func encode(_ outbound: ExecServerOutboundMessage?) throws -> [Data] {
        guard let outbound else {
            return []
        }
        return [try ExecServerJSONRPCCodec.encodeLine(outbound.jsonRPCMessage)]
    }
}
