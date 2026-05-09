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
    case lmsNotFound
    case missingBaseURL
    case serverReturnedError(statusCode: Int)
    case requestFailed(String)
    case jsonParseError(String)
    case missingDataArray
    case fetchModelsFailed(statusCode: Int)
    case loadModelFailed(statusCode: Int)
    case downloadExecutionFailed(command: String, underlying: String)
    case downloadFailed(exitCode: Int32?)

    public var description: String {
        switch self {
        case .connectionUnavailable:
            return Self.connectionErrorMessage
        case .lmsNotFound:
            return "LM Studio not found. Please install LM Studio from https://lmstudio.ai/"
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
        case let .downloadExecutionFailed(command, underlying):
            return "Failed to execute '\(command)': \(underlying)"
        case let .downloadFailed(exitCode):
            return "Model download failed with exit code: \(exitCode ?? -1)"
        }
    }

    public var errorDescription: String? {
        description
    }
}

public struct LMStudioDownloadCommand: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]

    public init(executable: String, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }

    public var displayCommand: String {
        ([executable] + arguments).joined(separator: " ")
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

    public static func findLMS(
        pathEnvironment: String? = ProcessInfo.processInfo.environment["PATH"],
        homeDirectory: String? = Self.defaultHomeDirectory(),
        fileExists: (String) -> Bool = FileManager.default.fileExists(atPath:)
    ) throws -> String {
        if let pathEnvironment, pathContainsLMS(pathEnvironment, fileExists: fileExists) {
            return "lms"
        }

        if let homeDirectory {
            let fallback = fallbackLMSPath(homeDirectory: homeDirectory)
            if fileExists(fallback) {
                return fallback
            }
        }

        throw LMStudioClientError.lmsNotFound
    }

    public static func fallbackLMSPath(homeDirectory: String) -> String {
        #if os(Windows)
        return homeDirectory + "\\.lmstudio\\bin\\lms.exe"
        #else
        return homeDirectory + "/.lmstudio/bin/lms"
        #endif
    }

    public static func downloadCommand(for model: String, lmsExecutable: String) -> LMStudioDownloadCommand {
        LMStudioDownloadCommand(executable: lmsExecutable, arguments: ["get", "--yes", model])
    }

    private static func pathContainsLMS(
        _ pathEnvironment: String,
        fileExists: (String) -> Bool
    ) -> Bool {
        for directory in pathEnvironment.split(separator: pathListSeparator, omittingEmptySubsequences: true) {
            if fileExists(String(directory) + pathSeparator + "lms") {
                return true
            }
        }
        return false
    }

    public static func defaultHomeDirectory() -> String? {
        #if os(Windows)
        return ProcessInfo.processInfo.environment["USERPROFILE"]
        #else
        return ProcessInfo.processInfo.environment["HOME"]
        #endif
    }

    private static var pathListSeparator: Character {
        #if os(Windows)
        return ";"
        #else
        return ":"
        #endif
    }

    private static var pathSeparator: String {
        #if os(Windows)
        return "\\"
        #else
        return "/"
        #endif
    }

    public static func urlSessionSend(_ request: URLRequest) async throws -> LMStudioHTTPResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LMStudioClientError.connectionUnavailable
        }
        return LMStudioHTTPResponse(statusCode: http.statusCode, data: data)
    }
}
