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
