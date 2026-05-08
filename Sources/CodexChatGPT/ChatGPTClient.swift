import CodexCore
import CodexGit
import Foundation

public struct ChatGPTClientConfiguration: Equatable, Sendable {
    public static let defaultBaseURL = "https://chatgpt.com/backend-api/"

    public let chatgptBaseURL: String
    public let codexHome: URL
    public let authCredentialsStoreMode: AuthCredentialsStoreMode

    public init(
        chatgptBaseURL: String = Self.defaultBaseURL,
        codexHome: URL,
        authCredentialsStoreMode: AuthCredentialsStoreMode = .file
    ) {
        self.chatgptBaseURL = chatgptBaseURL
        self.codexHome = codexHome
        self.authCredentialsStoreMode = authCredentialsStoreMode
    }
}

public struct ChatGPTHTTPResponse: Equatable, Sendable {
    public let statusCode: Int
    public let body: Data

    public init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }
}

public enum ChatGPTClientError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidURL(String)
    case chatGPTTokenNotAvailable
    case chatGPTAccountIDNotAvailable
    case requestFailed(status: String, body: String)
    case responseDecodeFailed(String)

    public var description: String {
        switch self {
        case let .invalidURL(url):
            return "Invalid ChatGPT request URL: \(url)"
        case .chatGPTTokenNotAvailable:
            return "ChatGPT token not available"
        case .chatGPTAccountIDNotAvailable:
            return "ChatGPT account ID not available, please re-run `codex login`"
        case let .requestFailed(status, body):
            return "Request failed with status \(status): \(body)"
        case let .responseDecodeFailed(message):
            return "Failed to parse JSON response: \(message)"
        }
    }
}

public struct ChatGPTTaskClient {
    public typealias Transport = (URLRequest) async throws -> ChatGPTHTTPResponse

    public let configuration: ChatGPTClientConfiguration
    private let transport: Transport
    private let tokenLoader: () throws -> AuthTokenData?

    public init(
        configuration: ChatGPTClientConfiguration,
        transport: Transport? = nil,
        tokenLoader: (() throws -> AuthTokenData?)? = nil
    ) {
        self.configuration = configuration
        self.transport = transport ?? Self.urlSessionTransport
        self.tokenLoader = tokenLoader ?? {
            try CodexAuthStorage.loadTokenData(
                codexHome: configuration.codexHome,
                mode: configuration.authCredentialsStoreMode
            )
        }
    }

    public func getTask(taskID: String) async throws -> GetTaskResponse {
        try await get(path: "/wham/tasks/\(taskID)")
    }

    public func applyTask(taskID: String, cwd: URL? = nil) async throws -> ApplyGitResult {
        let response = try await getTask(taskID: taskID)
        return try CodexTaskDiffApplier.applyDiff(from: response, cwd: cwd)
    }

    public func get<T: Decodable>(path: String) async throws -> T {
        guard let token = try tokenLoader() else {
            throw ChatGPTClientError.chatGPTTokenNotAvailable
        }
        guard let accountID = token.accountID else {
            throw ChatGPTClientError.chatGPTAccountIDNotAvailable
        }

        let urlText = configuration.chatgptBaseURL + path
        guard let url = URL(string: urlText) else {
            throw ChatGPTClientError.invalidURL(urlText)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(accountID, forHTTPHeaderField: "chatgpt-account-id")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let response = try await transport(request)
        guard (200..<300).contains(response.statusCode) else {
            let body = String(data: response.body, encoding: .utf8) ?? ""
            throw ChatGPTClientError.requestFailed(status: Self.statusText(response.statusCode), body: body)
        }

        do {
            return try JSONDecoder().decode(T.self, from: response.body)
        } catch {
            throw ChatGPTClientError.responseDecodeFailed(error.localizedDescription)
        }
    }

    private static func urlSessionTransport(_ request: URLRequest) async throws -> ChatGPTHTTPResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ChatGPTClientError.requestFailed(status: "0", body: "non-HTTP response")
        }
        return ChatGPTHTTPResponse(statusCode: http.statusCode, body: data)
    }

    private static func statusText(_ statusCode: Int) -> String {
        let reason = HTTPURLResponse.localizedString(forStatusCode: statusCode)
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
        guard !reason.isEmpty else {
            return "\(statusCode)"
        }
        return "\(statusCode) \(reason)"
    }
}
