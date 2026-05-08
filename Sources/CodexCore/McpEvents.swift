import Foundation

public struct McpStartupUpdateEvent: Equatable, Codable, Sendable {
    public let server: String
    public let status: McpStartupStatus

    public init(server: String, status: McpStartupStatus) {
        self.server = server
        self.status = status
    }
}

public enum McpStartupStatus: Equatable, Codable, Sendable {
    case starting
    case ready
    case failed(error: String)
    case cancelled

    private enum CodingKeys: String, CodingKey {
        case state
        case error
    }

    private enum State: String, Codable {
        case starting
        case ready
        case failed
        case cancelled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(State.self, forKey: .state) {
        case .starting:
            self = .starting
        case .ready:
            self = .ready
        case .failed:
            self = .failed(error: try container.decode(String.self, forKey: .error))
        case .cancelled:
            self = .cancelled
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .starting:
            try container.encode(State.starting, forKey: .state)
        case .ready:
            try container.encode(State.ready, forKey: .state)
        case let .failed(error):
            try container.encode(State.failed, forKey: .state)
            try container.encode(error, forKey: .error)
        case .cancelled:
            try container.encode(State.cancelled, forKey: .state)
        }
    }
}

public struct McpStartupCompleteEvent: Equatable, Codable, Sendable {
    public let ready: [String]
    public let failed: [McpStartupFailure]
    public let cancelled: [String]

    public init(ready: [String] = [], failed: [McpStartupFailure] = [], cancelled: [String] = []) {
        self.ready = ready
        self.failed = failed
        self.cancelled = cancelled
    }
}

public struct McpStartupFailure: Equatable, Codable, Sendable {
    public let server: String
    public let error: String

    public init(server: String, error: String) {
        self.server = server
        self.error = error
    }
}

public enum McpAuthStatus: String, Codable, Equatable, Sendable {
    case unsupported
    case notLoggedIn = "not_logged_in"
    case bearerToken = "bearer_token"
    case oauth

    public var description: String {
        switch self {
        case .unsupported:
            return "Unsupported"
        case .notLoggedIn:
            return "Not logged in"
        case .bearerToken:
            return "Bearer token"
        case .oauth:
            return "OAuth"
        }
    }
}
