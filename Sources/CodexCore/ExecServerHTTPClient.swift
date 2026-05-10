import Foundation

public struct ExecServerHTTPClient: Sendable {
    public typealias Send = @Sendable (URLRequest) async throws -> URLSessionTransportResponse
    public typealias Stream = @Sendable (URLRequest) async throws -> APIStreamResponse

    private let send: Send
    private let stream: Stream

    public init() {
        self.init(send: ExecServerHTTPClient.urlSessionSend, stream: ExecServerHTTPClient.urlSessionStream)
    }

    public init(send: @escaping Send) {
        self.init(send: send) { request in
            let response = try await send(request)
            return APIStreamResponse(
                statusCode: response.statusCode,
                headers: response.headers,
                byteStream: APIByteStream { continuation in
                    continuation.yield(.success(response.body))
                    continuation.finish()
                }
            )
        }
    }

    public init(send: @escaping Send, stream: @escaping Stream) {
        self.send = send
        self.stream = stream
    }

    public func run(_ params: ExecServerHttpRequestParams) async throws -> ExecServerHttpRequestResponse {
        var request = try buildRequest(params)

        if let timeoutMs = params.timeoutMs {
            request.timeoutInterval = Double(timeoutMs) / 1_000
        }

        do {
            let response = try await send(request)
            guard let status = UInt16(exactly: response.statusCode) else {
                throw ExecServerRPC.internalError("http/request response status is invalid: \(response.statusCode)")
            }
            let headers = response.headers
                .map { ExecServerHttpHeader(name: $0.key, value: $0.value) }
                .sorted { lhs, rhs in
                    lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
            return ExecServerHttpRequestResponse(
                status: status,
                headers: headers,
                body: ExecServerByteChunk(Array(response.body))
            )
        } catch let error as ExecServerJSONRPCErrorDetail {
            throw error
        } catch {
            throw ExecServerRPC.internalError("http/request failed: \(Self.errorDescription(error))")
        }
    }

    public func startStreaming(_ params: ExecServerHttpRequestParams) async throws -> ExecServerHTTPStreamResponse {
        var request = try buildRequest(params)

        if let timeoutMs = params.timeoutMs {
            request.timeoutInterval = Double(timeoutMs) / 1_000
        }

        do {
            let response = try await stream(request)
            guard let status = UInt16(exactly: response.statusCode) else {
                throw ExecServerRPC.internalError("http/request response status is invalid: \(response.statusCode)")
            }
            let headers = response.headers
                .map { ExecServerHttpHeader(name: $0.key, value: $0.value) }
                .sorted { lhs, rhs in
                    lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
            return ExecServerHTTPStreamResponse(
                response: ExecServerHttpRequestResponse(
                    status: status,
                    headers: headers,
                    body: ExecServerByteChunk([])
                ),
                bodyStream: response.byteStream
            )
        } catch let error as ExecServerJSONRPCErrorDetail {
            throw error
        } catch {
            throw ExecServerRPC.internalError("http/request failed: \(Self.errorDescription(error))")
        }
    }

    private func buildRequest(_ params: ExecServerHttpRequestParams) throws -> URLRequest {
        guard Self.isHTTPToken(params.method) else {
            throw ExecServerRPC.invalidParams("http/request method is invalid: invalid HTTP method")
        }
        guard let url = URL(string: params.url), let scheme = url.scheme else {
            throw ExecServerRPC.invalidParams("http/request url is invalid: relative URL without a base")
        }

        let normalizedScheme = scheme.lowercased()
        guard normalizedScheme == "http" || normalizedScheme == "https" else {
            throw ExecServerRPC.invalidParams("http/request only supports http and https URLs, got \(scheme)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = params.method
        request.httpBody = params.body.map { Data($0.bytes) }

        for header in params.headers {
            guard Self.isHTTPToken(header.name) else {
                throw ExecServerRPC.invalidParams("http/request header name is invalid: invalid HTTP header name")
            }
            guard Self.isHeaderValue(header.value) else {
                throw ExecServerRPC.invalidParams("http/request header value is invalid for \(header.name): invalid HTTP header value")
            }
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }

        return request
    }

    private static func isHTTPToken(_ value: String) -> Bool {
        guard !value.isEmpty else {
            return false
        }
        return value.utf8.allSatisfy { byte in
            switch byte {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A:
                return true
            case 0x21, 0x23...0x27, 0x2A, 0x2B, 0x2D, 0x2E, 0x5E, 0x5F, 0x60, 0x7C, 0x7E:
                return true
            default:
                return false
            }
        }
    }

    private static func isHeaderValue(_ value: String) -> Bool {
        value.utf8.allSatisfy { byte in
            switch byte {
            case 0x09, 0x20...0x7E, 0x80...0xFF:
                return true
            default:
                return false
            }
        }
    }

    private static func errorDescription(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }

    private static func urlSessionSend(_ request: URLRequest) async throws -> URLSessionTransportResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ExecServerHTTPClientError.nonHTTPResponse
        }

        return URLSessionTransportResponse(
            statusCode: http.statusCode,
            headers: headers(from: http),
            body: data
        )
    }

    private static func urlSessionStream(_ request: URLRequest) async throws -> APIStreamResponse {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ExecServerHTTPClientError.nonHTTPResponse
        }

        let byteStream = APIByteStream { continuation in
            let task = Task {
                do {
                    var buffer = Data()
                    buffer.reserveCapacity(8_192)
                    for try await byte in bytes {
                        buffer.append(byte)
                        if buffer.count >= 8_192 {
                            continuation.yield(.success(buffer))
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }
                    if !buffer.isEmpty {
                        continuation.yield(.success(buffer))
                    }
                    continuation.finish()
                } catch {
                    continuation.yield(.failure(.network(Self.errorDescription(error))))
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }

        return APIStreamResponse(
            statusCode: http.statusCode,
            headers: headers(from: http),
            byteStream: byteStream
        )
    }

    private static func headers(from response: HTTPURLResponse) -> [String: String] {
        response.allHeaderFields.reduce(into: [String: String]()) { result, entry in
            guard let name = entry.key as? String else {
                return
            }
            result[name] = String(describing: entry.value)
        }
    }
}

public struct ExecServerHTTPStreamResponse: Sendable {
    public let response: ExecServerHttpRequestResponse
    public let bodyStream: APIByteStream

    public init(response: ExecServerHttpRequestResponse, bodyStream: APIByteStream) {
        self.response = response
        self.bodyStream = bodyStream
    }
}

private enum ExecServerHTTPClientError: Error {
    case nonHTTPResponse
}
