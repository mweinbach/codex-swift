import Darwin
import Foundation

public let codexExecServerRemoteBearerTokenEnvironmentVariable = "CODEX_EXEC_SERVER_REMOTE_BEARER_TOKEN"

public let defaultExecServerListenURL = "ws://127.0.0.1:0"

public enum ExecServerListenTransport: Equatable, Sendable {
    case webSocket(host: String, port: UInt16)
    case stdio
}

public enum ExecServerListenURLParseError: Error, CustomStringConvertible, Equatable, Sendable {
    case unsupportedListenURL(String)
    case invalidWebSocketListenURL(String)

    public var description: String {
        switch self {
        case let .unsupportedListenURL(listenURL):
            return "unsupported --listen URL `\(listenURL)`; expected `ws://IP:PORT` or `stdio`"
        case let .invalidWebSocketListenURL(listenURL):
            return "invalid websocket --listen URL `\(listenURL)`; expected `ws://IP:PORT`"
        }
    }
}

public enum ExecServerConfigurationError: Error, CustomStringConvertible, Equatable, Sendable {
    case executorRegistryConfig(String)
    case executorRegistryAuth(String)

    public var description: String {
        switch self {
        case let .executorRegistryConfig(message):
            return "executor registry configuration error: \(message)"
        case let .executorRegistryAuth(message):
            return "executor registry authentication error: \(message)"
        }
    }
}

public struct ExecServerRemoteExecutorConfiguration: Equatable, Sendable {
    public let baseURL: String
    public let executorID: String
    public let name: String
    public let bearerToken: String

    public init(
        baseURL: String,
        executorID: String,
        name: String = "codex-exec-server",
        bearerToken: String
    ) throws {
        self.baseURL = try Self.normalizeBaseURL(baseURL)
        self.executorID = try Self.normalizeExecutorID(executorID)
        self.name = name
        self.bearerToken = try Self.normalizeBearerToken(bearerToken)
    }

    public static func fromEnvironment(
        baseURL: String,
        executorID: String,
        name: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> Self {
        guard let bearerToken = environment[codexExecServerRemoteBearerTokenEnvironmentVariable] else {
            throw ExecServerConfigurationError.executorRegistryAuth(
                "executor registry bearer token environment variable `\(codexExecServerRemoteBearerTokenEnvironmentVariable)` is not set"
            )
        }
        return try Self(
            baseURL: baseURL,
            executorID: executorID,
            name: name ?? "codex-exec-server",
            bearerToken: bearerToken
        )
    }

    private static func normalizeBaseURL(_ baseURL: String) throws -> String {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        guard !trimmed.isEmpty else {
            throw ExecServerConfigurationError.executorRegistryConfig("executor registry base URL is required")
        }
        return trimmed
    }

    private static func normalizeExecutorID(_ executorID: String) throws -> String {
        let trimmed = executorID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ExecServerConfigurationError.executorRegistryConfig(
                "executor id is required for remote exec-server registration"
            )
        }
        return trimmed
    }

    private static func normalizeBearerToken(_ bearerToken: String) throws -> String {
        let trimmed = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ExecServerConfigurationError.executorRegistryAuth(
                "executor registry bearer token environment variable `\(codexExecServerRemoteBearerTokenEnvironmentVariable)` is empty"
            )
        }
        return trimmed
    }
}

public enum ExecServerListenURLParser {
    public static func parse(_ listenURL: String) throws -> ExecServerListenTransport {
        if listenURL == "stdio" || listenURL == "stdio://" {
            return .stdio
        }

        guard listenURL.hasPrefix("ws://") else {
            throw ExecServerListenURLParseError.unsupportedListenURL(listenURL)
        }
        guard let components = URLComponents(string: listenURL),
              components.scheme == "ws",
              let rawHost = components.host,
              let port = components.port,
              port >= 0,
              port <= UInt16.max,
              components.path.isEmpty,
              components.query == nil,
              components.fragment == nil,
              let host = normalizedHost(rawHost),
              isIPAddress(host)
        else {
            throw ExecServerListenURLParseError.invalidWebSocketListenURL(listenURL)
        }

        return .webSocket(host: host, port: UInt16(port))
    }

    private static func isIPAddress(_ host: String) -> Bool {
        var ipv4 = in_addr()
        if host.withCString({ inet_pton(AF_INET, $0, &ipv4) }) == 1 {
            return true
        }
        var ipv6 = in6_addr()
        return host.withCString { inet_pton(AF_INET6, $0, &ipv6) } == 1
    }

    private static func normalizedHost(_ host: String) -> String? {
        if host.hasPrefix("[") && host.hasSuffix("]") {
            return String(host.dropFirst().dropLast())
        }
        return host
    }
}
