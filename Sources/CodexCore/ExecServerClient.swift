import Foundation

public struct ExecServerClientConnectOptions: Equatable, Sendable {
    public let clientName: String
    public let initializeTimeoutSeconds: TimeInterval
    public let resumeSessionID: String?

    public init(
        clientName: String = "codex-environment",
        initializeTimeoutSeconds: TimeInterval = 5,
        resumeSessionID: String? = nil
    ) {
        self.clientName = clientName
        self.initializeTimeoutSeconds = initializeTimeoutSeconds
        self.resumeSessionID = resumeSessionID
    }
}

public enum ExecServerClientError: Error, Equatable, CustomStringConvertible, Sendable {
    case initializeTimedOut(timeoutSeconds: TimeInterval)
    case closed
    case json(String)
    case protocolError(String)
    case server(code: Int, message: String)
    case disconnected(String)

    public var description: String {
        switch self {
        case let .initializeTimedOut(timeoutSeconds):
            return "timed out waiting for exec-server initialize handshake after \(Self.formatSeconds(timeoutSeconds))"
        case .closed:
            return "exec-server transport closed"
        case let .json(message):
            return "failed to serialize or deserialize exec-server JSON: \(message)"
        case let .protocolError(message):
            return "exec-server protocol error: \(message)"
        case let .server(code, message):
            return "exec-server rejected request (\(code)): \(message)"
        case let .disconnected(message):
            return message
        }
    }

    private static func formatSeconds(_ seconds: TimeInterval) -> String {
        if seconds.rounded() == seconds {
            return "\(Int(seconds))s"
        }
        return "\(seconds)s"
    }
}

/// Transport boundary used by `ExecServerClient` to exchange JSON-RPC messages with an exec-server.
///
/// Concrete adopters own the websocket, stdio, or test transport mechanics. Implementations must preserve
/// request/response ordering for calls made through one client actor, return `nil` when the transport has
/// closed before a response is available, and be safe to invoke across Swift concurrency domains.
public protocol ExecServerClientTransport: Sendable {
    func send(_ message: ExecServerJSONRPCMessage) async throws -> ExecServerJSONRPCMessage?
}

public struct ClosureExecServerClientTransport: ExecServerClientTransport {
    public typealias Send = @Sendable (ExecServerJSONRPCMessage) async throws -> ExecServerJSONRPCMessage?

    private let sendMessage: Send

    public init(send: @escaping Send) {
        self.sendMessage = send
    }

    public func send(_ message: ExecServerJSONRPCMessage) async throws -> ExecServerJSONRPCMessage? {
        try await sendMessage(message)
    }
}

public actor ExecServerLineClientTransport: ExecServerClientTransport {
    public typealias ReadLine = @Sendable () async throws -> String?
    public typealias WriteLine = @Sendable (Data) async throws -> Void
    public typealias NotificationHandler = @Sendable (ExecServerJSONRPCNotification) async throws -> Void

    private let readLine: ReadLine
    private let writeLine: WriteLine
    private let notificationHandler: NotificationHandler
    private let connectionLabel: String

    public init(
        connectionLabel: String = "exec-server stdio command",
        readLine: @escaping ReadLine,
        writeLine: @escaping WriteLine,
        notificationHandler: @escaping NotificationHandler = { _ in }
    ) {
        self.connectionLabel = connectionLabel
        self.readLine = readLine
        self.writeLine = writeLine
        self.notificationHandler = notificationHandler
    }

    public func send(_ message: ExecServerJSONRPCMessage) async throws -> ExecServerJSONRPCMessage? {
        do {
            try await writeLine(try ExecServerJSONRPCCodec.encodeLine(message))
        } catch let error as ExecServerClientError {
            throw error
        } catch {
            throw ExecServerClientError.disconnected(
                "exec-server transport disconnected: failed to write JSON-RPC message to \(connectionLabel): \(error)"
            )
        }

        guard case .request = message else {
            return nil
        }

        while true {
            let line: String?
            do {
                line = try await readLine()
            } catch let error as ExecServerClientError {
                throw error
            } catch {
                throw ExecServerClientError.disconnected(
                    "exec-server transport disconnected: failed to read JSON-RPC message from \(connectionLabel): \(error)"
                )
            }

            guard let line else {
                return nil
            }
            guard let event = ExecServerJSONRPCCodec.stdioEvent(fromLine: line, connectionLabel: connectionLabel) else {
                continue
            }
            switch event {
            case let .message(.notification(notification)):
                do {
                    try await notificationHandler(notification)
                } catch {
                    throw ExecServerClientError.disconnected(
                        "exec-server notification handling failed: \(error)"
                    )
                }
            case let .message(message):
                return message
            case let .malformedMessage(reason):
                throw ExecServerClientError.protocolError(reason)
            case let .disconnected(reason):
                throw ExecServerClientError.disconnected(disconnectedMessage(reason: reason))
            }
        }
    }

    private func disconnectedMessage(reason: String?) -> String {
        if let reason, !reason.isEmpty {
            return "exec-server transport disconnected: \(reason)"
        }
        return "exec-server transport disconnected"
    }
}

public actor ExecServerClient {
    private let transport: any ExecServerClientTransport
    private var nextRequestID: Int64 = 1
    private var storedSessionID: String?
    private var disconnectedMessage: String?

    public init(transport: any ExecServerClientTransport) {
        self.transport = transport
    }

    public var sessionID: String? {
        storedSessionID
    }

    @discardableResult
    public func initialize(
        options: ExecServerClientConnectOptions = ExecServerClientConnectOptions()
    ) async throws -> ExecServerInitializeResponse {
        let response: ExecServerInitializeResponse = try await withInitializeTimeout(
            seconds: options.initializeTimeoutSeconds
        ) {
            let params = ExecServerInitializeParams(
                clientName: options.clientName,
                resumeSessionId: options.resumeSessionID
            )
            return try await self.call(execServerInitializeMethod, params: params)
        }
        storedSessionID = response.sessionId
        try await notifyInitialized()
        return response
    }

    public func startProcess(_ params: ExecServerExecParams) async throws -> ExecServerExecResponse {
        try await call(execServerProcessStartMethod, params: params)
    }

    public func readProcess(_ params: ExecServerReadParams) async throws -> ExecServerReadResponse {
        try await call(execServerProcessReadMethod, params: params)
    }

    public func writeProcess(_ params: ExecServerWriteParams) async throws -> ExecServerWriteResponse {
        try await call(execServerProcessWriteMethod, params: params)
    }

    public func terminateProcess(_ params: ExecServerTerminateParams) async throws -> ExecServerTerminateResponse {
        try await call(execServerProcessTerminateMethod, params: params)
    }

    public func readFile(_ params: ExecServerFsReadFileParams) async throws -> ExecServerFsReadFileResponse {
        try await call(execServerFsReadFileMethod, params: params)
    }

    public func writeFile(_ params: ExecServerFsWriteFileParams) async throws -> ExecServerFsWriteFileResponse {
        try await call(execServerFsWriteFileMethod, params: params)
    }

    public func createDirectory(
        _ params: ExecServerFsCreateDirectoryParams
    ) async throws -> ExecServerFsCreateDirectoryResponse {
        try await call(execServerFsCreateDirectoryMethod, params: params)
    }

    public func getMetadata(
        _ params: ExecServerFsGetMetadataParams
    ) async throws -> ExecServerFsGetMetadataResponse {
        try await call(execServerFsGetMetadataMethod, params: params)
    }

    public func readDirectory(
        _ params: ExecServerFsReadDirectoryParams
    ) async throws -> ExecServerFsReadDirectoryResponse {
        try await call(execServerFsReadDirectoryMethod, params: params)
    }

    public func remove(_ params: ExecServerFsRemoveParams) async throws -> ExecServerFsRemoveResponse {
        try await call(execServerFsRemoveMethod, params: params)
    }

    public func copy(_ params: ExecServerFsCopyParams) async throws -> ExecServerFsCopyResponse {
        try await call(execServerFsCopyMethod, params: params)
    }

    public func httpRequest(_ params: ExecServerHttpRequestParams) async throws -> ExecServerHttpRequestResponse {
        try await call(execServerHttpRequestMethod, params: params)
    }

    private func notifyInitialized() async throws {
        _ = try await send(.notification(ExecServerJSONRPCNotification(
            method: execServerInitializedMethod,
            params: .object([:])
        )))
    }

    private func call<P: Encodable, R: Decodable>(_ method: String, params: P) async throws -> R {
        if let disconnectedMessage {
            throw ExecServerClientError.disconnected(disconnectedMessage)
        }
        let requestID = RequestID.integer(nextRequestID)
        nextRequestID += 1
        let message = ExecServerJSONRPCMessage.request(ExecServerJSONRPCRequest(
            id: requestID,
            method: method,
            params: try jsonValue(from: params)
        ))
        let response = try await send(message)
        guard let response else {
            let message = disconnectedMessage(reason: nil)
            disconnectedMessage = message
            throw ExecServerClientError.disconnected(message)
        }
        return try decodeResponse(response, requestID: requestID, as: R.self)
    }

    private func send(_ message: ExecServerJSONRPCMessage) async throws -> ExecServerJSONRPCMessage? {
        do {
            return try await transport.send(message)
        } catch let error as ExecServerClientError {
            throw error
        } catch {
            throw ExecServerClientError.protocolError(String(describing: error))
        }
    }

    private func decodeResponse<R: Decodable>(
        _ message: ExecServerJSONRPCMessage,
        requestID: RequestID,
        as type: R.Type
    ) throws -> R {
        switch message {
        case let .response(response):
            guard response.id == requestID else {
                throw ExecServerClientError.protocolError(
                    "exec-server response id \(response.id) did not match request id \(requestID)"
                )
            }
            do {
                return try ExecServerRPC.decodeRequestParams(response.result, as: R.self)
            } catch {
                throw ExecServerClientError.json(String(describing: error))
            }
        case let .error(error):
            guard error.id == requestID else {
                throw ExecServerClientError.protocolError(
                    "exec-server error id \(error.id) did not match request id \(requestID)"
                )
            }
            throw ExecServerClientError.server(code: error.error.code, message: error.error.message)
        case .request:
            throw ExecServerClientError.protocolError("exec-server sent an unexpected request")
        case .notification:
            throw ExecServerClientError.protocolError("exec-server sent an unexpected notification")
        }
    }

    private func jsonValue<P: Encodable>(from params: P) throws -> JSONValue {
        do {
            return try ExecServerRPC.jsonValue(from: params)
        } catch {
            throw ExecServerClientError.json(String(describing: error))
        }
    }

    private func withInitializeTimeout<R: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> R
    ) async throws -> R {
        guard seconds > 0 else {
            return try await operation()
        }
        return try await withThrowingTaskGroup(of: R.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw ExecServerClientError.initializeTimedOut(timeoutSeconds: seconds)
            }
            guard let result = try await group.next() else {
                throw ExecServerClientError.closed
            }
            group.cancelAll()
            return result
        }
    }

    private func disconnectedMessage(reason: String?) -> String {
        if let reason, !reason.isEmpty {
            return "exec-server transport disconnected: \(reason)"
        }
        return "exec-server transport disconnected"
    }
}
