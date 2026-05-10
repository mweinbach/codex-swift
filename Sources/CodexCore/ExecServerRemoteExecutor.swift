import CryptoKit
import Foundation

private let execServerRemoteProtocolVersion = "codex-exec-server-v1"
private let execServerRegistryErrorPreviewBytes = 4096

public enum ExecServerRemoteExecutorError: Error, CustomStringConvertible, Equatable, Sendable {
    case registryHTTP(status: Int, code: String?, message: String)
    case registryAuth(String)
    case registryRequest(String)

    public var description: String {
        switch self {
        case let .registryHTTP(status, code, message):
            let codeSuffix = code.map { ", \($0)" } ?? ""
            return "executor registry request failed (\(status)\(codeSuffix)): \(message)"
        case let .registryAuth(message):
            return "executor registry authentication error: \(message)"
        case let .registryRequest(message):
            return "executor registry request failed: \(message)"
        }
    }
}

public struct ExecServerRemoteExecutorRegistrationRequest: Codable, Equatable, Sendable {
    public let idempotencyId: String
    public let executorId: String
    public let name: String?
    public let labels: [String: String]
    public let metadata: JSONValue

    public init(
        idempotencyId: String,
        executorId: String,
        name: String?,
        labels: [String: String] = [:],
        metadata: JSONValue = .object([:])
    ) {
        self.idempotencyId = idempotencyId
        self.executorId = executorId
        self.name = name
        self.labels = labels
        self.metadata = metadata
    }

    private enum CodingKeys: String, CodingKey {
        case idempotencyId = "idempotency_id"
        case executorId = "executor_id"
        case name
        case labels
        case metadata
    }
}

public struct ExecServerRemoteExecutorRegistrationResponse: Codable, Equatable, Sendable {
    public let id: String
    public let executorId: String
    public let url: String

    public init(id: String, executorId: String, url: String) {
        self.id = id
        self.executorId = executorId
        self.url = url
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case executorId = "executor_id"
        case url
    }
}

public struct ExecServerRemoteExecutorRegistryClient: Sendable {
    public typealias Send = @Sendable (URLRequest) async throws -> URLSessionTransportResponse

    private let baseURL: String
    private let bearerToken: String
    private let send: Send

    public init(
        baseURL: String,
        bearerToken: String
    ) throws {
        try self.init(
            baseURL: baseURL,
            bearerToken: bearerToken,
            send: ExecServerRemoteExecutorRegistryClient.urlSessionSend
        )
    }

    public init(
        baseURL: String,
        bearerToken: String,
        send: @escaping Send
    ) throws {
        self.baseURL = try ExecServerRemoteExecutorConfiguration.normalizedBaseURL(baseURL)
        self.bearerToken = bearerToken
        self.send = send
    }

    public func registerExecutor(
        _ request: ExecServerRemoteExecutorRegistrationRequest
    ) async throws -> ExecServerRemoteExecutorRegistrationResponse {
        let endpoint = "\(baseURL)/cloud/executor/\(request.executorId)/register"
        guard let url = URL(string: endpoint) else {
            throw ExecServerRemoteExecutorError.registryRequest("bad URL: \(endpoint)")
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let response: URLSessionTransportResponse
        do {
            response = try await send(urlRequest)
        } catch let error as ExecServerRemoteExecutorError {
            throw error
        } catch {
            throw ExecServerRemoteExecutorError.registryRequest(String(describing: error))
        }

        if (200..<300).contains(response.statusCode) {
            do {
                return try JSONDecoder().decode(
                    ExecServerRemoteExecutorRegistrationResponse.self,
                    from: response.body
                )
            } catch {
                throw ExecServerRemoteExecutorError.registryRequest(String(describing: error))
            }
        }

        if response.statusCode == 401 || response.statusCode == 403 {
            throw ExecServerRemoteExecutorError.registryAuth(
                "executor registry authentication failed (\(response.statusCode)): \(Self.registryAuthMessage(response.body))"
            )
        }

        let error = Self.registryHTTPError(status: response.statusCode, body: response.body)
        throw ExecServerRemoteExecutorError.registryHTTP(
            status: response.statusCode,
            code: error.code,
            message: error.message
        )
    }

    private static func registryAuthMessage(_ body: Data) -> String {
        registryErrorMessage(body) ?? "empty error body"
    }

    private static func registryHTTPError(status: Int, body: Data) -> (code: String?, message: String) {
        if let registryBody = try? JSONDecoder().decode(RegistryErrorBody.self, from: body),
           let error = registryBody.error {
            return (
                error.code,
                error.message ?? previewErrorBody(body) ?? "empty error body"
            )
        }
        return (nil, previewErrorBody(body) ?? "empty or malformed error body")
    }

    private static func registryErrorMessage(_ body: Data) -> String? {
        if let registryBody = try? JSONDecoder().decode(RegistryErrorBody.self, from: body),
           let message = registryBody.error?.message {
            return message
        }
        return previewErrorBody(body)
    }

    private static func previewErrorBody(_ body: Data) -> String? {
        let text = String(decoding: body, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return nil
        }
        return String(text.prefix(execServerRegistryErrorPreviewBytes))
    }

    static func urlSessionSend(_ request: URLRequest) async throws -> URLSessionTransportResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExecServerRemoteExecutorError.registryRequest("non-HTTP response")
        }
        return URLSessionTransportResponse(
            statusCode: httpResponse.statusCode,
            headers: httpResponse.allHeaderFields.reduce(into: [String: String]()) { result, pair in
                if let key = pair.key as? String {
                    result[key] = String(describing: pair.value)
                }
            },
            body: data
        )
    }
}

public struct ExecServerRemoteExecutor: Sendable {
    public typealias RegisterExecutor = @Sendable (
        ExecServerRemoteExecutorRegistrationRequest
    ) async throws -> ExecServerRemoteExecutorRegistrationResponse
    public typealias ConnectAndServe = @Sendable (
        String,
        ExecServerConnectionProcessor
    ) async throws -> Void
    public typealias Sleep = @Sendable (TimeInterval) async throws -> Void
    public typealias MessageSink = @Sendable (String) async -> Void

    private let config: ExecServerRemoteExecutorConfiguration
    private let registrationID: UUID
    private let processor: ExecServerConnectionProcessor
    private let registerExecutor: RegisterExecutor
    private let connectAndServe: ConnectAndServe
    private let sleep: Sleep
    private let messageSink: MessageSink

    public init(
        config: ExecServerRemoteExecutorConfiguration,
        registrationID: UUID = UUID(),
        processor: ExecServerConnectionProcessor = ExecServerConnectionProcessor(),
        registerExecutor: @escaping RegisterExecutor,
        connectAndServe: @escaping ConnectAndServe = ExecServerRemoteExecutor.urlSessionConnectAndServe,
        sleep: @escaping Sleep = ExecServerRemoteExecutor.taskSleep,
        messageSink: @escaping MessageSink = ExecServerRemoteExecutor.standardErrorMessageSink
    ) {
        self.config = config
        self.registrationID = registrationID
        self.processor = processor
        self.registerExecutor = registerExecutor
        self.connectAndServe = connectAndServe
        self.sleep = sleep
        self.messageSink = messageSink
    }

    public init(
        config: ExecServerRemoteExecutorConfiguration,
        registrationID: UUID = UUID(),
        processor: ExecServerConnectionProcessor = ExecServerConnectionProcessor(),
        connectAndServe: @escaping ConnectAndServe = ExecServerRemoteExecutor.urlSessionConnectAndServe,
        sleep: @escaping Sleep = ExecServerRemoteExecutor.taskSleep,
        messageSink: @escaping MessageSink = ExecServerRemoteExecutor.standardErrorMessageSink
    ) throws {
        let client = try ExecServerRemoteExecutorRegistryClient(
            baseURL: config.baseURL,
            bearerToken: config.bearerToken
        )
        self.init(
            config: config,
            registrationID: registrationID,
            processor: processor,
            registerExecutor: { request in try await client.registerExecutor(request) },
            connectAndServe: connectAndServe,
            sleep: sleep,
            messageSink: messageSink
        )
    }

    public func run() async throws {
        var backoffSeconds = 1.0

        while !Task.isCancelled {
            let request = config.registrationRequest(registrationID: registrationID)
            let response = try await registerExecutor(request)
            await messageSink(
                "codex exec-server remote executor \(response.id) registered with executor_id \(response.executorId)"
            )

            do {
                try await connectAndServe(response.url, processor)
                backoffSeconds = 1.0
            } catch {
                await messageSink("failed to connect remote exec-server websocket: \(error)")
            }

            try await sleep(backoffSeconds)
            backoffSeconds = min(backoffSeconds * 2, 30.0)
        }
    }

    public static func taskSleep(seconds: TimeInterval) async throws {
        guard seconds > 0 else {
            return
        }
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    public static func standardErrorMessageSink(_ message: String) async {
        fputs("\(message)\n", stderr)
    }

    public static func urlSessionConnectAndServe(
        url: String,
        processor: ExecServerConnectionProcessor
    ) async throws {
        guard let endpoint = URL(string: url) else {
            throw ExecServerRemoteExecutorError.registryRequest("bad URL: \(url)")
        }

        let socket = URLSessionExecServerWebSocket(url: endpoint)
        defer {
            Task {
                await socket.close()
            }
        }

        let connection = await processor.makeConnection()
        let outboundTask = Task {
            while !Task.isCancelled {
                guard let outbound = await connection.waitForOutbound() else {
                    break
                }
                let text = try ExecServerJSONRPCCodec.encodeWebSocketText(outbound.jsonRPCMessage)
                try await socket.sendText(text)
            }
        }

        do {
            while !Task.isCancelled {
                let incoming = try await socket.receive()
                let outbound: ExecServerOutboundMessage?
                switch incoming {
                case let .text(text):
                    outbound = await connection.handleWebSocketText(
                        text,
                        connectionLabel: "remote exec-server websocket"
                    )
                case let .data(data):
                    outbound = await connection.handleWebSocketBinary(
                        data,
                        connectionLabel: "remote exec-server websocket"
                    )
                }
                if let outbound {
                    let text = try ExecServerJSONRPCCodec.encodeWebSocketText(outbound.jsonRPCMessage)
                    try await socket.sendText(text)
                }
            }
        } catch {
            outboundTask.cancel()
            _ = await connection.handle(.disconnected(reason: nil))
            throw error
        }

        outboundTask.cancel()
        _ = await connection.handle(.disconnected(reason: nil))
        try? await outboundTask.value
    }
}

private enum URLSessionExecServerWebSocketIncoming: Sendable {
    case text(String)
    case data(Data)
}

private actor URLSessionExecServerWebSocket {
    private let task: URLSessionWebSocketTask

    init(url: URL) {
        self.task = URLSession.shared.webSocketTask(with: url)
        task.resume()
    }

    func receive() async throws -> URLSessionExecServerWebSocketIncoming {
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

    func close() {
        task.cancel(with: .normalClosure, reason: nil)
    }
}

private struct RegistryErrorBody: Decodable {
    let error: RegistryError?
}

private struct RegistryError: Decodable {
    let code: String?
    let message: String?
}

extension ExecServerRemoteExecutorConfiguration {
    public func registrationRequest(registrationID: UUID) -> ExecServerRemoteExecutorRegistrationRequest {
        ExecServerRemoteExecutorRegistrationRequest(
            idempotencyId: defaultIdempotencyID(registrationID: registrationID),
            executorId: executorID,
            name: name,
            labels: [:],
            metadata: .object([:])
        )
    }

    public func defaultIdempotencyID(registrationID: UUID) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(executorID.utf8))
        hasher.update(data: Data([0]))
        hasher.update(data: Data(name.utf8))
        hasher.update(data: Data([0]))
        hasher.update(data: Data(execServerRemoteProtocolVersion.utf8))
        hasher.update(data: Data([0]))
        hasher.update(data: Data(registrationID.uuidBytes))
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return "codex-exec-server-\(digest)"
    }

    static func normalizedBaseURL(_ baseURL: String) throws -> String {
        try normalizeBaseURL(baseURL)
    }
}

private extension UUID {
    var uuidBytes: [UInt8] {
        [
            uuid.0, uuid.1, uuid.2, uuid.3,
            uuid.4, uuid.5,
            uuid.6, uuid.7,
            uuid.8, uuid.9,
            uuid.10, uuid.11, uuid.12, uuid.13, uuid.14, uuid.15
        ]
    }
}
