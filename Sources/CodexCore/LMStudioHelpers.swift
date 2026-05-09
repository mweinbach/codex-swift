import Foundation

public struct LMStudioHTTPResponse: Equatable, Sendable {
    public let statusCode: Int
    public let data: Data

    public init(statusCode: Int, data: Data = Data()) {
        self.statusCode = statusCode
        self.data = data
    }

    public var isSuccess: Bool {
        (200..<300).contains(statusCode)
    }
}

public enum LMStudioClientError: Error, Equatable, CustomStringConvertible, LocalizedError, Sendable {
    public static let connectionErrorMessage = "LM Studio is not responding. Install from https://lmstudio.ai/download and run 'lms server start'."

    case connectionUnavailable
    case missingBaseURL
    case serverReturnedError(statusCode: Int)
    case requestFailed(String)
    case jsonParseError(String)
    case missingDataArray
    case fetchModelsFailed(statusCode: Int)
    case loadModelFailed(statusCode: Int)

    public var description: String {
        switch self {
        case .connectionUnavailable:
            return Self.connectionErrorMessage
        case .missingBaseURL:
            return "oss provider must have a base_url"
        case let .serverReturnedError(statusCode):
            return "Server returned error: \(statusCode) \(Self.connectionErrorMessage)"
        case let .requestFailed(message):
            return "Request failed: \(message)"
        case let .jsonParseError(message):
            return "JSON parse error: \(message)"
        case .missingDataArray:
            return "No 'data' array in response"
        case let .fetchModelsFailed(statusCode):
            return "Failed to fetch models: \(statusCode)"
        case let .loadModelFailed(statusCode):
            return "Failed to load model: \(statusCode)"
        }
    }

    public var errorDescription: String? {
        description
    }
}

public struct LMStudioClient {
    public typealias Send = (URLRequest) async throws -> LMStudioHTTPResponse

    public let baseURL: String
    private let send: Send

    init(
        baseURL: String,
        send: @escaping Send = LMStudioClient.urlSessionSend
    ) {
        self.baseURL = Self.trimTrailingSlashes(baseURL)
        self.send = send
    }

    public static func tryFromProvider(
        _ provider: ModelProviderInfo,
        send: @escaping Send = LMStudioClient.urlSessionSend
    ) async throws -> LMStudioClient {
        guard let baseURL = provider.baseURL else {
            throw LMStudioClientError.missingBaseURL
        }
        let client = LMStudioClient(baseURL: baseURL, send: send)
        try await client.checkServer()
        return client
    }

    public func checkServer() async throws {
        do {
            let response = try await send(URLRequest(url: try endpointURL("/models")))
            guard response.isSuccess else {
                throw LMStudioClientError.serverReturnedError(statusCode: response.statusCode)
            }
        } catch let error as LMStudioClientError {
            throw error
        } catch {
            throw LMStudioClientError.connectionUnavailable
        }
    }

    public func fetchModels() async throws -> [String] {
        let response: LMStudioHTTPResponse
        do {
            response = try await send(URLRequest(url: try endpointURL("/models")))
        } catch {
            throw LMStudioClientError.requestFailed(String(describing: error))
        }

        guard response.isSuccess else {
            throw LMStudioClientError.fetchModelsFailed(statusCode: response.statusCode)
        }

        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: response.data)
        } catch {
            throw LMStudioClientError.jsonParseError(String(describing: error))
        }

        guard let object = value as? [String: Any],
              let data = object["data"] as? [[String: Any]]
        else {
            throw LMStudioClientError.missingDataArray
        }
        return data.compactMap { $0["id"] as? String }
    }

    public func loadModel(_ model: String) async throws {
        var request = URLRequest(url: try endpointURL("/responses"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "input": "",
            "max_output_tokens": 1
        ])

        let response: LMStudioHTTPResponse
        do {
            response = try await send(request)
        } catch {
            throw LMStudioClientError.requestFailed(String(describing: error))
        }
        guard response.isSuccess else {
            throw LMStudioClientError.loadModelFailed(statusCode: response.statusCode)
        }
    }

    private func endpointURL(_ path: String) throws -> URL {
        guard let url = URL(string: baseURL + path) else {
            throw LMStudioClientError.connectionUnavailable
        }
        return url
    }

    private static func trimTrailingSlashes(_ value: String) -> String {
        var result = value
        while result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }

    public static func urlSessionSend(_ request: URLRequest) async throws -> LMStudioHTTPResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LMStudioClientError.connectionUnavailable
        }
        return LMStudioHTTPResponse(statusCode: http.statusCode, data: data)
    }
}
