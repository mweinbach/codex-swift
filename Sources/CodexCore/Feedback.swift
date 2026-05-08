import Foundation

private let defaultFeedbackMaxBytes = 4 * 1024 * 1024
private let sentryFeedbackDSN = "https://ae32ed50620d7a7792c1ce5df38b3e3e@o33249.ingest.us.sentry.io/4510195390611458"
private let feedbackUploadTimeout: TimeInterval = 10

public final class CodexFeedback: @unchecked Sendable {
    private let lock = NSLock()
    private var ring: FeedbackRingBuffer

    public convenience init() {
        self.init(capacity: defaultFeedbackMaxBytes)
    }

    init(capacity: Int) {
        self.ring = FeedbackRingBuffer(capacity: capacity)
    }

    public func makeWriter() -> FeedbackWriter {
        FeedbackWriter(feedback: self)
    }

    public func snapshot(sessionID: ConversationId?) -> CodexLogSnapshot {
        let bytes = withLockedRing { $0.snapshotBytes() }
        let threadID = sessionID?.description ?? "no-active-thread-\(ConversationId())"
        return CodexLogSnapshot(bytes: bytes, threadID: threadID)
    }

    fileprivate func write(_ bytes: [UInt8]) -> Int {
        withLockedRing { $0.push(bytes) }
        return bytes.count
    }

    private func withLockedRing<T>(_ body: (inout FeedbackRingBuffer) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&ring)
    }
}

public final class FeedbackWriter: @unchecked Sendable {
    private let feedback: CodexFeedback

    fileprivate init(feedback: CodexFeedback) {
        self.feedback = feedback
    }

    @discardableResult
    public func write(_ data: Data) -> Int {
        feedback.write(Array(data))
    }

    @discardableResult
    public func write(_ bytes: [UInt8]) -> Int {
        feedback.write(bytes)
    }

    public func flush() {}
}

struct FeedbackRingBuffer: Equatable, Sendable {
    private let max: Int
    private var bytes: [UInt8] = []

    init(capacity: Int) {
        self.max = Swift.max(0, capacity)
        self.bytes.reserveCapacity(self.max)
    }

    var count: Int {
        bytes.count
    }

    mutating func push(_ data: [UInt8]) {
        guard !data.isEmpty, max > 0 else {
            return
        }

        if data.count >= max {
            bytes = Array(data.suffix(max))
            return
        }

        let needed = bytes.count + data.count
        if needed > max {
            bytes.removeFirst(needed - max)
        }
        bytes.append(contentsOf: data)
    }

    func snapshotBytes() -> [UInt8] {
        bytes
    }
}

public struct CodexLogSnapshot: Equatable, Sendable {
    public let bytes: [UInt8]
    public let threadID: String

    public init(bytes: [UInt8], threadID: String) {
        self.bytes = bytes
        self.threadID = threadID
    }

    public var data: Data {
        Data(bytes)
    }

    public func saveToTempFile(
        fileManager: FileManager = .default,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) throws -> URL {
        let path = temporaryDirectory.appendingPathComponent("codex-feedback-\(threadID).log")
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        try data.write(to: path)
        return path
    }

    public func makeUploadRequest(
        classification: String,
        reason: String? = nil,
        includeLogs: Bool,
        rolloutPath: URL? = nil,
        sessionSource: SessionSource? = nil,
        cliVersion: String = "0.0.0",
        eventID: String = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    ) throws -> FeedbackUploadRequest {
        let dsn = try SentryFeedbackDSN.parse(sentryFeedbackDSN)
        let title = "[\(displayClassification(classification))]: Codex session \(threadID)"

        var tags: [String: String] = [
            "thread_id": threadID,
            "classification": classification,
            "cli_version": cliVersion
        ]
        if let sessionSource {
            tags["session_source"] = sessionSource.description
        }
        if let reason {
            tags["reason"] = reason
        }

        var event: [String: Any] = [
            "event_id": eventID,
            "level": level(for: classification),
            "message": title,
            "tags": tags
        ]
        if let reason {
            event["exception"] = [
                "values": [
                    [
                        "type": title,
                        "value": reason
                    ]
                ]
            ]
        }

        var envelope = Data()
        try appendJSONLine(["dsn": sentryFeedbackDSN], to: &envelope)
        try appendItem(payload: jsonData(event), type: "event", to: &envelope)

        if includeLogs {
            try appendItem(
                payload: data,
                type: "attachment",
                filename: "codex-logs.log",
                contentType: "text/plain",
                to: &envelope
            )
        }

        if let rolloutPath,
           let rolloutData = try? Data(contentsOf: rolloutPath)
        {
            let filename = rolloutPath.lastPathComponent.isEmpty ? "rollout.jsonl" : rolloutPath.lastPathComponent
            try appendItem(
                payload: rolloutData,
                type: "attachment",
                filename: filename,
                contentType: "text/plain",
                to: &envelope
            )
        }

        return FeedbackUploadRequest(
            endpoint: dsn.envelopeURL,
            authHeader: dsn.authHeader(clientVersion: cliVersion),
            envelope: envelope,
            timeout: feedbackUploadTimeout
        )
    }

    public func uploadFeedback(
        classification: String,
        reason: String? = nil,
        includeLogs: Bool,
        rolloutPath: URL? = nil,
        sessionSource: SessionSource? = nil,
        cliVersion: String = "0.0.0",
        transport: FeedbackUploadTransport = URLSessionFeedbackUploadTransport()
    ) async throws {
        let request = try makeUploadRequest(
            classification: classification,
            reason: reason,
            includeLogs: includeLogs,
            rolloutPath: rolloutPath,
            sessionSource: sessionSource,
            cliVersion: cliVersion
        )
        try await transport.upload(request)
    }

    private func displayClassification(_ classification: String) -> String {
        switch classification {
        case "bug":
            return "Bug"
        case "bad_result":
            return "Bad result"
        case "good_result":
            return "Good result"
        default:
            return "Other"
        }
    }

    private func level(for classification: String) -> String {
        switch classification {
        case "bug", "bad_result":
            return "error"
        default:
            return "info"
        }
    }

    private func appendItem(
        payload: Data,
        type: String,
        filename: String? = nil,
        contentType: String? = nil,
        to envelope: inout Data
    ) throws {
        var header: [String: Any] = [
            "type": type,
            "length": payload.count
        ]
        if let filename {
            header["filename"] = filename
        }
        if let contentType {
            header["content_type"] = contentType
        }
        try appendJSONLine(header, to: &envelope)
        envelope.append(payload)
        envelope.append(0x0A)
    }

    private func appendJSONLine(_ object: [String: Any], to envelope: inout Data) throws {
        envelope.append(try jsonData(object))
        envelope.append(0x0A)
    }

    private func jsonData(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

public struct FeedbackUploadRequest: Equatable, Sendable {
    public let endpoint: URL
    public let authHeader: String
    public let envelope: Data
    public let timeout: TimeInterval

    public init(endpoint: URL, authHeader: String, envelope: Data, timeout: TimeInterval) {
        self.endpoint = endpoint
        self.authHeader = authHeader
        self.envelope = envelope
        self.timeout = timeout
    }
}

public protocol FeedbackUploadTransport: Sendable {
    func upload(_ request: FeedbackUploadRequest) async throws
}

public struct URLSessionFeedbackUploadTransport: FeedbackUploadTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func upload(_ request: FeedbackUploadRequest) async throws {
        var urlRequest = URLRequest(url: request.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = request.timeout
        urlRequest.httpBody = request.envelope
        urlRequest.setValue("application/x-sentry-envelope", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(request.authHeader, forHTTPHeaderField: "X-Sentry-Auth")

        let (body, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FeedbackUploadError.nonHTTPResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw FeedbackUploadError.httpStatus(
                httpResponse.statusCode,
                String(decoding: body, as: UTF8.self)
            )
        }
    }
}

public enum FeedbackUploadError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidDSN(String)
    case invalidEnvelopeURL(String)
    case nonHTTPResponse
    case httpStatus(Int, String)

    public var description: String {
        switch self {
        case let .invalidDSN(value):
            return "invalid DSN: \(value)"
        case let .invalidEnvelopeURL(value):
            return "invalid Sentry envelope URL: \(value)"
        case .nonHTTPResponse:
            return "Sentry upload did not return an HTTP response"
        case let .httpStatus(status, body):
            if body.isEmpty {
                return "Sentry upload failed with HTTP \(status)"
            }
            return "Sentry upload failed with HTTP \(status): \(body)"
        }
    }
}

private struct SentryFeedbackDSN: Equatable, Sendable {
    let publicKey: String
    let envelopeURL: URL

    static func parse(_ raw: String) throws -> SentryFeedbackDSN {
        guard var components = URLComponents(string: raw),
              let publicKey = components.user,
              let host = components.host,
              !publicKey.isEmpty,
              !host.isEmpty
        else {
            throw FeedbackUploadError.invalidDSN(raw)
        }

        let pathParts = components.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let projectID = pathParts.last, !projectID.isEmpty else {
            throw FeedbackUploadError.invalidDSN(raw)
        }

        let pathPrefix = pathParts.dropLast().joined(separator: "/")
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        components.path = (pathPrefix.isEmpty ? "" : "/\(pathPrefix)") + "/api/\(projectID)/envelope/"

        guard let envelopeURL = components.url else {
            throw FeedbackUploadError.invalidEnvelopeURL(raw)
        }

        return SentryFeedbackDSN(publicKey: publicKey, envelopeURL: envelopeURL)
    }

    func authHeader(clientVersion: String) -> String {
        "Sentry sentry_version=7, sentry_key=\(publicKey), sentry_client=codex-swift/\(clientVersion)"
    }
}
