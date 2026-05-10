import Foundation

public struct ExecServerHTTPClient: Sendable {
    public typealias Send = @Sendable (URLRequest) async throws -> URLSessionTransportResponse

    private let send: Send

    public init() {
        self.init(send: ExecServerHTTPClient.urlSessionSend)
    }

    public init(send: @escaping Send) {
        self.send = send
    }

    public func run(_ params: ExecServerHttpRequestParams) async throws -> ExecServerHttpRequestResponse {
        guard !params.streamResponse else {
            throw ExecServerRPC.internalError("http/request streamResponse is not implemented")
        }

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

        let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, entry in
            guard let name = entry.key as? String else {
                return
            }
            result[name] = String(describing: entry.value)
        }

        return URLSessionTransportResponse(
            statusCode: http.statusCode,
            headers: headers,
            body: data
        )
    }
}

private enum ExecServerHTTPClientError: Error {
    case nonHTTPResponse
}
