import Darwin
import Foundation

public struct RemoteControlTarget: Equatable, Sendable {
    public var websocketURL: String
    public var enrollURL: String

    public init(websocketURL: String, enrollURL: String) {
        self.websocketURL = websocketURL
        self.enrollURL = enrollURL
    }
}

public struct RemoteControlEnrollmentRecord: Equatable, Sendable {
    public var websocketURL: String
    public var accountID: String
    public var appServerClientName: String?
    public var serverID: String
    public var environmentID: String
    public var serverName: String

    public init(
        websocketURL: String,
        accountID: String,
        appServerClientName: String?,
        serverID: String,
        environmentID: String,
        serverName: String
    ) {
        self.websocketURL = websocketURL
        self.accountID = accountID
        self.appServerClientName = appServerClientName
        self.serverID = serverID
        self.environmentID = environmentID
        self.serverName = serverName
    }
}

public enum RemoteControlURLNormalizationError: Error, CustomStringConvertible, Equatable, Sendable {
    case invalidURL(remoteControlURL: String, message: String)
    case unsupportedURL(remoteControlURL: String)

    public var description: String {
        switch self {
        case let .invalidURL(remoteControlURL, message):
            return "invalid remote control URL `\(remoteControlURL)`: \(message)"
        case let .unsupportedURL(remoteControlURL):
            return "invalid remote control URL `\(remoteControlURL)`; expected HTTPS URL for chatgpt.com or chatgpt-staging.com, or HTTP/HTTPS URL for localhost"
        }
    }
}

public enum RemoteControlURLNormalizer {
    public static func normalize(_ remoteControlURL: String) throws -> RemoteControlTarget {
        guard var components = URLComponents(string: remoteControlURL),
              let scheme = components.scheme,
              let host = components.host,
              !host.isEmpty
        else {
            throw RemoteControlURLNormalizationError.invalidURL(
                remoteControlURL: remoteControlURL,
                message: "relative URL without a base"
            )
        }
        guard scheme == "http" || scheme == "https" else {
            throw RemoteControlURLNormalizationError.unsupportedURL(remoteControlURL: remoteControlURL)
        }

        let normalizedPath = normalizedBasePath(components.percentEncodedPath)
        components.percentEncodedPath = normalizedPath
        components.percentEncodedQuery = nil
        components.percentEncodedFragment = nil
        guard components.url != nil else {
            throw RemoteControlURLNormalizationError.invalidURL(
                remoteControlURL: remoteControlURL,
                message: "invalid path"
            )
        }

        let localhost = isLocalhost(normalizedHost(host))
        switch scheme {
        case "https" where localhost || isAllowedChatGPTHost(host):
            break
        case "http" where localhost:
            break
        default:
            throw RemoteControlURLNormalizationError.unsupportedURL(remoteControlURL: remoteControlURL)
        }

        let enrollURL = try joinedURL(
            components: components,
            pathSuffix: "wham/remote/control/server/enroll",
            remoteControlURL: remoteControlURL
        )
        var websocketComponents = components
        websocketComponents.scheme = scheme == "https" ? "wss" : "ws"
        let websocketURL = try joinedURL(
            components: websocketComponents,
            pathSuffix: "wham/remote/control/server",
            remoteControlURL: remoteControlURL
        )
        return RemoteControlTarget(websocketURL: websocketURL, enrollURL: enrollURL)
    }

    private static func normalizedBasePath(_ path: String) -> String {
        let basePath = path.isEmpty ? "/" : path
        return basePath.hasSuffix("/") ? basePath : "\(basePath)/"
    }

    private static func joinedURL(
        components: URLComponents,
        pathSuffix: String,
        remoteControlURL: String
    ) throws -> String {
        var joinedComponents = components
        joinedComponents.percentEncodedPath = "\(normalizedBasePath(components.percentEncodedPath))\(pathSuffix)"
        guard let url = joinedComponents.url else {
            throw RemoteControlURLNormalizationError.invalidURL(
                remoteControlURL: remoteControlURL,
                message: "invalid URL components"
            )
        }
        return url.absoluteString
    }

    private static func isAllowedChatGPTHost(_ host: String) -> Bool {
        host == "chatgpt.com"
            || host == "chatgpt-staging.com"
            || host.hasSuffix(".chatgpt.com")
            || host.hasSuffix(".chatgpt-staging.com")
    }

    private static func normalizedHost(_ host: String) -> String {
        if host.hasPrefix("[") && host.hasSuffix("]") {
            return String(host.dropFirst().dropLast())
        }
        return host
    }

    private static func isLocalhost(_ host: String) -> Bool {
        if host == "localhost" {
            return true
        }
        var ipv4 = in_addr()
        if host.withCString({ inet_pton(AF_INET, $0, &ipv4) }) == 1 {
            return UInt32(bigEndian: ipv4.s_addr) >> 24 == 127
        }
        var ipv6 = in6_addr()
        if host.withCString({ inet_pton(AF_INET6, $0, &ipv6) }) == 1 {
            var loopback = in6_addr()
            _ = "::1".withCString { inet_pton(AF_INET6, $0, &loopback) }
            return withUnsafeBytes(of: &ipv6) { candidateBytes in
                withUnsafeBytes(of: &loopback) { loopbackBytes in
                    candidateBytes.elementsEqual(loopbackBytes)
                }
            }
        }
        return false
    }
}
