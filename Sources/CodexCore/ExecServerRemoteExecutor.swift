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
