import Foundation

public struct URLSessionTransportResponse: Equatable, Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

public struct URLSessionAPITransport: APITransport {
    public typealias Send = @Sendable (URLRequest) async throws -> URLSessionTransportResponse

    private let send: Send

    public init() {
        self.init(send: URLSessionAPITransport.urlSessionSend)
    }

    public init(send: @escaping Send) {
        self.send = send
    }

    public func execute(_ request: APIRequest) async -> Result<APIResponse, TransportError> {
        let result = await send(request)
        switch result {
        case let .success(response):
            guard (200..<300).contains(response.statusCode) else {
                return .failure(.http(
                    statusCode: response.statusCode,
                    headers: response.headers,
                    body: String(data: response.body, encoding: .utf8)
                ))
            }
            return .success(APIResponse(
                statusCode: response.statusCode,
                headers: response.headers,
                body: response.body
            ))
        case let .failure(error):
            return .failure(error)
        }
    }

    public func stream(_ request: APIRequest) async -> Result<APIStreamResponse, TransportError> {
        let result = await send(request)
        switch result {
        case let .success(response):
            guard (200..<300).contains(response.statusCode) else {
                return .failure(.http(
                    statusCode: response.statusCode,
                    headers: response.headers,
                    body: String(data: response.body, encoding: .utf8)
                ))
            }
            return .success(APIStreamResponse(
                statusCode: response.statusCode,
                headers: response.headers,
                sseText: String(decoding: response.body, as: UTF8.self)
            ))
        case let .failure(error):
            return .failure(error)
        }
    }

    public func urlRequest(for request: APIRequest) -> Result<URLRequest, TransportError> {
        guard let url = URL(string: request.url) else {
            return .failure(.build("invalid URL: \(request.url)"))
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        if let timeoutMilliseconds = request.timeoutMilliseconds {
            urlRequest.timeoutInterval = Double(timeoutMilliseconds) / 1_000
        }

        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        if let body = request.body {
            do {
                urlRequest.httpBody = try JSONEncoder().encode(body)
            } catch {
                return .failure(.build("failed to encode JSON body: \(error)"))
            }
            if !request.headers.keys.contains(where: { $0.caseInsensitiveCompare("content-type") == .orderedSame }) {
                urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
            }
        }

        return .success(urlRequest)
    }

    private func send(_ request: APIRequest) async -> Result<URLSessionTransportResponse, TransportError> {
        switch urlRequest(for: request) {
        case let .failure(error):
            return .failure(error)
        case let .success(urlRequest):
            do {
                return .success(try await send(urlRequest))
            } catch {
                return .failure(Self.mapError(error))
            }
        }
    }

    private static func urlSessionSend(_ request: URLRequest) async throws -> URLSessionTransportResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLSessionAPITransportError.nonHTTPResponse
        }

        return URLSessionTransportResponse(
            statusCode: http.statusCode,
            headers: headers(from: http),
            body: data
        )
    }

    private static func headers(from response: HTTPURLResponse) -> [String: String] {
        response.allHeaderFields.reduce(into: [String: String]()) { result, entry in
            guard let key = entry.key as? String else {
                return
            }
            result[key] = String(describing: entry.value)
        }
    }

    private static func mapError(_ error: Error) -> TransportError {
        if let transportError = error as? TransportError {
            return transportError
        }
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return .timeout
        }
        return .network(error.localizedDescription)
    }
}

private enum URLSessionAPITransportError: Error {
    case nonHTTPResponse
}
