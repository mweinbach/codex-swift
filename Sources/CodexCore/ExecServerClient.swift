import Darwin
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

public struct StdioExecServerCommand: Equatable, Sendable {
    public let program: String
    public let args: [String]
    public let env: [String: String]
    public let cwd: String?

    public init(
        program: String,
        args: [String] = [],
        env: [String: String] = [:],
        cwd: String? = nil
    ) {
        self.program = program
        self.args = args
        self.env = env
        self.cwd = cwd
    }
}

public struct StdioExecServerConnectArgs: Equatable, Sendable {
    public let command: StdioExecServerCommand
    public let clientName: String
    public let initializeTimeoutSeconds: TimeInterval
    public let resumeSessionID: String?

    public init(
        command: StdioExecServerCommand,
        clientName: String = "codex-environment",
        initializeTimeoutSeconds: TimeInterval = 5,
        resumeSessionID: String? = nil
    ) {
        self.command = command
        self.clientName = clientName
        self.initializeTimeoutSeconds = initializeTimeoutSeconds
        self.resumeSessionID = resumeSessionID
    }
}

public struct RemoteExecServerConnectArgs: Equatable, Sendable {
    public let websocketURL: String
    public let clientName: String
    public let connectTimeoutSeconds: TimeInterval
    public let initializeTimeoutSeconds: TimeInterval
    public let resumeSessionID: String?

    public init(
        websocketURL: String,
        clientName: String,
        connectTimeoutSeconds: TimeInterval = 10,
        initializeTimeoutSeconds: TimeInterval = 10,
        resumeSessionID: String? = nil
    ) {
        self.websocketURL = websocketURL
        self.clientName = clientName
        self.connectTimeoutSeconds = connectTimeoutSeconds
        self.initializeTimeoutSeconds = initializeTimeoutSeconds
        self.resumeSessionID = resumeSessionID
    }
}

public enum ExecServerTransportParams: Equatable, Sendable {
    case webSocketURL(String)
    case stdioCommand(StdioExecServerCommand)
}

public enum ExecServerClientError: Error, Equatable, CustomStringConvertible, Sendable {
    case initializeTimedOut(timeoutSeconds: TimeInterval)
    case webSocketConnectTimedOut(url: String, timeoutSeconds: TimeInterval)
    case webSocketConnect(url: String, message: String)
    case closed
    case json(String)
    case protocolError(String)
    case server(code: Int, message: String)
    case disconnected(String)

    public var description: String {
        switch self {
        case let .initializeTimedOut(timeoutSeconds):
            return "timed out waiting for exec-server initialize handshake after \(Self.formatSeconds(timeoutSeconds))"
        case let .webSocketConnectTimedOut(url, timeoutSeconds):
            return "timed out connecting to exec-server websocket `\(url)` after \(Self.formatSeconds(timeoutSeconds))"
        case let .webSocketConnect(url, message):
            return "failed to connect to exec-server websocket `\(url)`: \(message)"
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

public actor ExecServerWebSocketClientTransport: ExecServerClientTransport {
    public typealias NotificationHandler = @Sendable (ExecServerJSONRPCNotification) async throws -> Void

    private let socket: ExecServerClientURLSessionWebSocket
    private let connectionLabel: String
    private let websocketURL: String
    private let notificationHandler: NotificationHandler

    public init(
        websocketURL: String,
        notificationHandler: @escaping NotificationHandler = { _ in }
    ) throws {
        guard let url = URL(string: websocketURL) else {
            throw ExecServerClientError.webSocketConnect(url: websocketURL, message: "invalid URL")
        }
        self.socket = ExecServerClientURLSessionWebSocket(url: url)
        self.connectionLabel = "exec-server websocket \(websocketURL)"
        self.websocketURL = websocketURL
        self.notificationHandler = notificationHandler
    }

    deinit {
        let socket = socket
        Task { [socket] in
            await socket.close()
        }
    }

    public func send(_ message: ExecServerJSONRPCMessage) async throws -> ExecServerJSONRPCMessage? {
        do {
            try await socket.sendText(try ExecServerJSONRPCCodec.encodeWebSocketText(message))
        } catch let error as ExecServerClientError {
            throw error
        } catch {
            throw ExecServerClientError.webSocketConnect(url: websocketURL, message: String(describing: error))
        }

        guard case .request = message else {
            return nil
        }

        while true {
            let event: ExecServerConnectionEvent
            do {
                switch try await socket.receive() {
                case let .text(text):
                    event = ExecServerJSONRPCCodec.webSocketTextEvent(text, connectionLabel: connectionLabel)
                case let .data(data):
                    event = ExecServerJSONRPCCodec.webSocketBinaryEvent(data, connectionLabel: connectionLabel)
                }
            } catch {
                throw ExecServerClientError.disconnected(
                    "exec-server transport disconnected: failed to read JSON-RPC message from \(connectionLabel): \(error)"
                )
            }

            switch event {
            case let .message(.notification(notification)):
                do {
                    try await notificationHandler(notification)
                    continue
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

    public func waitUntilConnected() async throws {
        do {
            try await socket.sendPing()
        } catch {
            throw ExecServerClientError.webSocketConnect(url: websocketURL, message: String(describing: error))
        }
    }

    public func close() async {
        await socket.close()
    }

    private func disconnectedMessage(reason: String?) -> String {
        if let reason, !reason.isEmpty {
            return "exec-server transport disconnected: \(reason)"
        }
        return "exec-server transport disconnected"
    }
}

private actor ExecServerClientNotificationRouter {
    private let userHandler: ExecServerLineClientTransport.NotificationHandler
    private weak var client: ExecServerClient?

    init(userHandler: @escaping ExecServerLineClientTransport.NotificationHandler) {
        self.userHandler = userHandler
    }

    func setClient(_ client: ExecServerClient) {
        self.client = client
    }

    func handle(_ notification: ExecServerJSONRPCNotification) async throws {
        try await client?.handleServerNotification(notification)
        try await userHandler(notification)
    }
}

private enum ExecServerClientWebSocketIncoming: Sendable {
    case text(String)
    case data(Data)
}

private actor ExecServerClientURLSessionWebSocket {
    private let task: URLSessionWebSocketTask

    init(url: URL) {
        task = URLSession.shared.webSocketTask(with: url)
        task.resume()
    }

    func receive() async throws -> ExecServerClientWebSocketIncoming {
        switch try await task.receive() {
        case let .string(text):
            return .text(text)
        case let .data(data):
            return .data(data)
        @unknown default:
            return .data(Data())
        }
    }

    func sendText(_ text: String) async throws {
        try await task.send(.string(text))
    }

    func sendPing() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func close() {
        task.cancel(with: .normalClosure, reason: nil)
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

public final class ExecServerStdioCommandTransport: ExecServerClientTransport, @unchecked Sendable {
    private let process: Process
    private let supervisor: ExecServerStdioProcessSupervisor
    private let stdin: FileHandleLineWriter
    private let stdout: FileHandleLineReader
    private let stderrDrain: FileHandleDrain
    private let lineTransport: ExecServerLineClientTransport

    public init(
        command: StdioExecServerCommand,
        notificationHandler: @escaping ExecServerLineClientTransport.NotificationHandler = { _ in }
    ) throws {
        let process = Process()
        if command.program.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: command.program)
            process.arguments = command.args
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command.program] + command.args
        }
        process.environment = command.env.isEmpty
            ? ProcessInfo.processInfo.environment
            : ProcessInfo.processInfo.environment.merging(command.env) { _, override in override }
        if let cwd = command.cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdin = FileHandleLineWriter(stdinPipe.fileHandleForWriting)
        let stdout = FileHandleLineReader(stdoutPipe.fileHandleForReading)
        let stderrDrain = FileHandleDrain(stderrPipe.fileHandleForReading)
        let supervisor = ExecServerStdioProcessSupervisor(process: process)
        self.process = process
        self.supervisor = supervisor
        self.stdin = stdin
        self.stdout = stdout
        self.stderrDrain = stderrDrain
        self.lineTransport = ExecServerLineClientTransport(
            readLine: { try await stdout.readLine() },
            writeLine: { try await stdin.write($0) },
            notificationHandler: notificationHandler
        )

        do {
            try process.run()
        } catch {
            closePipes()
            throw ExecServerClientError.disconnected(
                "exec-server transport disconnected: failed to spawn exec-server stdio command: \(error)"
            )
        }
        supervisor.startTracking()
        stderrDrain.start()
    }

    deinit {
        terminate()
    }

    public func send(_ message: ExecServerJSONRPCMessage) async throws -> ExecServerJSONRPCMessage? {
        try await lineTransport.send(message)
    }

    public func terminate() {
        stderrDrain.stop()
        supervisor.terminate()
        closePipes()
    }

    private func closePipes() {
        stdin.close()
        stdout.close()
        stderrDrain.close()
    }
}

private final class ExecServerStdioProcessSupervisor: @unchecked Sendable {
    private static let terminationGracePeriod: TimeInterval = 2

    private let process: Process
    private let lock = NSLock()
    private var tracker: SeatbeltPidTracker?
    private var terminateRequested = false

    init(process: Process) {
        self.process = process
    }

    func startTracking() {
        let pid = process.processIdentifier
        lock.withLock {
            tracker = SeatbeltPidTracker(rootPID: pid)
        }
        process.terminationHandler = { [weak self] _ in
            self?.killTrackedProcessTree(signal: SIGKILL, includeRoot: false)
        }
    }

    func terminate() {
        let shouldTerminate = lock.withLock {
            if terminateRequested {
                return false
            }
            terminateRequested = true
            process.terminationHandler = nil
            return true
        }
        guard shouldTerminate else {
            return
        }

        let pids = signalTrackedProcessTree(signal: SIGTERM, includeRoot: true)
        guard !pids.isEmpty else {
            return
        }
        if waitForExit(of: pids, timeout: Self.terminationGracePeriod) {
            return
        }
        signalPIDs(pids, signal: SIGKILL)
        _ = waitForExit(of: pids, timeout: Self.terminationGracePeriod)
    }

    private func killTrackedProcessTree(signal: Int32, includeRoot: Bool) {
        _ = signalTrackedProcessTree(signal: signal, includeRoot: includeRoot)
    }

    private func signalTrackedProcessTree(signal: Int32, includeRoot: Bool) -> Set<pid_t> {
        let pids = trackedProcessTree(includeRoot: includeRoot)
        signalPIDs(pids, signal: signal)
        return pids
    }

    private func trackedProcessTree(includeRoot: Bool) -> Set<pid_t> {
        let rootPID = process.processIdentifier
        var pids = lock.withLock {
            let tracked = tracker?.stop() ?? []
            tracker = nil
            return tracked
        }
        collectDescendants(of: rootPID, into: &pids)
        if includeRoot {
            pids.insert(rootPID)
        } else {
            pids.remove(rootPID)
        }
        return pids.filter { $0 > 0 && execServerPIDIsAlive($0) }
    }

    private func collectDescendants(of parent: pid_t, into pids: inout Set<pid_t>) {
        for child in listChildPIDs(parent: parent) {
            if pids.insert(child).inserted {
                collectDescendants(of: child, into: &pids)
            }
        }
    }

    private func signalPIDs(_ pids: Set<pid_t>, signal: Int32) {
        for pid in pids.sorted(by: >) where execServerPIDIsAlive(pid) {
            _ = Darwin.kill(pid, signal)
        }
    }

    private func waitForExit(of pids: Set<pid_t>, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if pids.allSatisfy({ !execServerPIDIsAlive($0) }) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return pids.allSatisfy { !execServerPIDIsAlive($0) }
    }
}

public actor ExecServerClient {
    private let transport: any ExecServerClientTransport
    private var nextRequestID: Int64 = 1
    private var storedSessionID: String?
    private var disconnectedMessage: String?
    private var processSessions: [String: ExecServerRemoteProcessEventLog] = [:]

    public init(transport: any ExecServerClientTransport) {
        self.transport = transport
    }

    public static func connectForTransport(
        _ transportParams: ExecServerTransportParams,
        notificationHandler: @escaping ExecServerLineClientTransport.NotificationHandler = { _ in }
    ) async throws -> ExecServerClient {
        switch transportParams {
        case let .webSocketURL(websocketURL):
            return try await connectWebSocket(RemoteExecServerConnectArgs(
                websocketURL: websocketURL,
                clientName: "codex-environment",
                connectTimeoutSeconds: 5,
                initializeTimeoutSeconds: 5
            ), notificationHandler: notificationHandler)
        case let .stdioCommand(command):
            return try await connectStdioCommand(StdioExecServerConnectArgs(
                command: command,
                clientName: "codex-environment",
                initializeTimeoutSeconds: 5
            ), notificationHandler: notificationHandler)
        }
    }

    public static func connectWebSocket(
        _ args: RemoteExecServerConnectArgs,
        notificationHandler: @escaping ExecServerWebSocketClientTransport.NotificationHandler = { _ in }
    ) async throws -> ExecServerClient {
        let router = ExecServerClientNotificationRouter(userHandler: notificationHandler)
        let transport = try ExecServerWebSocketClientTransport(
            websocketURL: args.websocketURL,
            notificationHandler: { try await router.handle($0) }
        )
        let client = ExecServerClient(transport: transport)
        await router.setClient(client)
        do {
            try await withTimeout(
                seconds: args.connectTimeoutSeconds,
                timeoutError: .webSocketConnectTimedOut(
                    url: args.websocketURL,
                    timeoutSeconds: args.connectTimeoutSeconds
                )
            ) {
                try await transport.waitUntilConnected()
            }
            _ = try await client.initialize(options: ExecServerClientConnectOptions(
                clientName: args.clientName,
                initializeTimeoutSeconds: args.initializeTimeoutSeconds,
                resumeSessionID: args.resumeSessionID
            ))
            return client
        } catch {
            await transport.close()
            throw error
        }
    }

    public static func connectStdioCommand(
        _ args: StdioExecServerConnectArgs,
        notificationHandler: @escaping ExecServerLineClientTransport.NotificationHandler = { _ in }
    ) async throws -> ExecServerClient {
        let router = ExecServerClientNotificationRouter(userHandler: notificationHandler)
        let transport = try ExecServerStdioCommandTransport(
            command: args.command,
            notificationHandler: { try await router.handle($0) }
        )
        let client = ExecServerClient(transport: transport)
        await router.setClient(client)
        do {
            _ = try await client.initialize(options: ExecServerClientConnectOptions(
                clientName: args.clientName,
                initializeTimeoutSeconds: args.initializeTimeoutSeconds,
                resumeSessionID: args.resumeSessionID
            ))
            return client
        } catch {
            transport.terminate()
            throw error
        }
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

    public func registerProcessSession(processId: String) throws -> ExecServerRemoteProcessSession {
        if let disconnectedMessage {
            throw ExecServerClientError.disconnected(disconnectedMessage)
        }
        guard processSessions[processId] == nil else {
            throw ExecServerClientError.protocolError("session already registered for process \(processId)")
        }
        let log = ExecServerRemoteProcessEventLog()
        processSessions[processId] = log
        return ExecServerRemoteProcessSession(processId: processId, client: self, events: log)
    }

    public func unregisterProcessSession(processId: String) {
        processSessions.removeValue(forKey: processId)
    }

    public func handleServerNotification(_ notification: ExecServerJSONRPCNotification) async throws {
        switch notification.method {
        case execServerProcessOutputDeltaMethod:
            let params = try decodeNotification(notification, as: ExecServerOutputDeltaNotification.self)
            if let session = processSessions[params.processId] {
                let publishedClosed = await session.publishOrdered(.output(ExecServerProcessOutputChunk(
                    seq: params.seq,
                    stream: params.stream,
                    chunk: params.chunk
                )))
                if publishedClosed {
                    processSessions.removeValue(forKey: params.processId)
                }
            }
        case execServerProcessExitedMethod:
            let params = try decodeNotification(notification, as: ExecServerExitedNotification.self)
            if let session = processSessions[params.processId] {
                let publishedClosed = await session.publishOrdered(.exited(
                    seq: params.seq,
                    exitCode: params.exitCode
                ))
                if publishedClosed {
                    processSessions.removeValue(forKey: params.processId)
                }
            }
        case execServerProcessClosedMethod:
            let params = try decodeNotification(notification, as: ExecServerClosedNotification.self)
            if let session = processSessions[params.processId] {
                let publishedClosed = await session.publishOrdered(.closed(seq: params.seq))
                if publishedClosed {
                    processSessions.removeValue(forKey: params.processId)
                }
            }
        default:
            return
        }
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
        let response: ExecServerJSONRPCMessage?
        do {
            response = try await send(message)
        } catch let error as ExecServerClientError where error.isTransportClosedLikeRust {
            let message = recordDisconnected(reason: nil)
            await failAllProcessSessions(message)
            throw ExecServerClientError.disconnected(message)
        }
        guard let response else {
            let message = recordDisconnected(reason: nil)
            await failAllProcessSessions(message)
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

    private func decodeNotification<R: Decodable>(
        _ notification: ExecServerJSONRPCNotification,
        as type: R.Type
    ) throws -> R {
        do {
            return try ExecServerRPC.decodeNotificationParams(notification.params, as: R.self)
        } catch {
            throw ExecServerClientError.json(String(describing: error))
        }
    }

    private func recordDisconnected(reason: String?) -> String {
        let message = disconnectedMessage(reason: reason)
        if let disconnectedMessage {
            return disconnectedMessage
        }
        disconnectedMessage = message
        return message
    }

    private func failAllProcessSessions(_ message: String) async {
        let sessions = processSessions
        processSessions.removeAll()
        for session in sessions.values {
            await session.setFailure(message)
        }
    }

    private func withInitializeTimeout<R: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> R
    ) async throws -> R {
        try await Self.withTimeout(
            seconds: seconds,
            timeoutError: .initializeTimedOut(timeoutSeconds: seconds),
            operation: operation
        )
    }

    private func disconnectedMessage(reason: String?) -> String {
        if let reason, !reason.isEmpty {
            return "exec-server transport disconnected: \(reason)"
        }
        return "exec-server transport disconnected"
    }

    private static func withTimeout<R: Sendable>(
        seconds: TimeInterval,
        timeoutError: ExecServerClientError,
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
                throw timeoutError
            }
            guard let result = try await group.next() else {
                throw ExecServerClientError.closed
            }
            group.cancelAll()
            return result
        }
    }
}

private final class FileHandleLineReader: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    private var isClosed = false

    init(_ handle: FileHandle) {
        self.handle = handle
    }

    func readLine() async throws -> String? {
        try await Task.detached {
            try self.readLineBlocking()
        }.value
    }

    func close() {
        lock.withLock {
            guard !isClosed else {
                return
            }
            isClosed = true
            try? handle.close()
        }
    }

    private func readLineBlocking() throws -> String? {
        lock.lock()
        let closed = isClosed
        lock.unlock()
        guard !closed else {
            return nil
        }
        var data = Data()
        while true {
            let byte = handle.readData(ofLength: 1)
            if byte.isEmpty {
                guard !data.isEmpty else {
                    return nil
                }
                break
            }
            if byte[byte.startIndex] == 0x0A {
                break
            }
            data.append(byte)
        }
        if data.last == 0x0D {
            data.removeLast()
        }
        guard let line = String(data: data, encoding: .utf8) else {
            throw ExecServerClientError.disconnected(
                "exec-server transport disconnected: failed to read JSON-RPC message from exec-server stdio command: input is not valid UTF-8"
            )
        }
        return line
    }
}

private final class FileHandleLineWriter: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    private var isClosed = false

    init(_ handle: FileHandle) {
        self.handle = handle
    }

    func write(_ data: Data) async throws {
        try await Task.detached {
            try self.writeBlocking(data)
        }.value
    }

    func close() {
        lock.withLock {
            guard !isClosed else {
                return
            }
            isClosed = true
            try? handle.close()
        }
    }

    private func writeBlocking(_ data: Data) throws {
        try lock.withLock {
            guard !isClosed else {
                throw ExecServerClientError.disconnected("exec-server transport disconnected")
            }
            try handle.write(contentsOf: data)
        }
    }
}

private final class FileHandleDrain: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var isClosed = false

    init(_ handle: FileHandle) {
        self.handle = handle
    }

    func start() {
        lock.withLock {
            guard task == nil else {
                return
            }
            task = Task.detached { [handle] in
                _ = handle.readDataToEndOfFile()
            }
        }
    }

    func stop() {
        lock.withLock {
            task?.cancel()
            task = nil
        }
    }

    func close() {
        lock.withLock {
            guard !isClosed else {
                return
            }
            isClosed = true
            try? handle.close()
        }
    }
}

private func execServerPIDIsAlive(_ pid: pid_t) -> Bool {
    guard pid > 0 else {
        return false
    }
    let result = Darwin.kill(pid, 0)
    if result == 0 {
        return true
    }
    return errno == EPERM
}
