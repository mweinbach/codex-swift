import Darwin
import Foundation

public let defaultAppServerListenURL = "stdio://"

public enum AppServerListenTransport: Equatable, Sendable {
    case stdio
    case unixSocket(socketPath: String)
    case webSocket(host: String, port: UInt16)
    case off
}

public enum AppServerTransportParseError: Error, CustomStringConvertible, Equatable, Sendable {
    case unsupportedListenURL(String)
    case invalidUnixSocketPath(listenURL: String, message: String)
    case invalidWebSocketListenURL(String)

    public var description: String {
        switch self {
        case let .unsupportedListenURL(listenURL):
            return "unsupported --listen URL `\(listenURL)`; expected `stdio://`, `unix://`, `unix://PATH`, `ws://IP:PORT`, or `off`"
        case let .invalidUnixSocketPath(listenURL, message):
            return "invalid unix socket --listen URL `\(listenURL)`; failed to resolve socket path: \(message)"
        case let .invalidWebSocketListenURL(listenURL):
            return "invalid websocket --listen URL `\(listenURL)`; expected `ws://IP:PORT`"
        }
    }
}

public enum AppServerListenURLParser {
    public static func parse(
        _ listenURL: String,
        codexHome: URL? = nil,
        currentDirectory: String = FileManager.default.currentDirectoryPath,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> AppServerListenTransport {
        if listenURL == defaultAppServerListenURL {
            return .stdio
        }

        if let rawSocketPath = listenURL.stripPrefix("unix://") {
            let socketPath: String
            if rawSocketPath.isEmpty {
                do {
                    let resolvedCodexHome = try codexHome ?? CodexHome.find(environment: environment)
                    socketPath = resolvedCodexHome
                        .appendingPathComponent("app-server-control", isDirectory: true)
                        .appendingPathComponent("app-server-control.sock", isDirectory: false)
                        .standardizedFileURL
                        .path
                } catch {
                    throw AppServerTransportParseError.invalidUnixSocketPath(
                        listenURL: listenURL,
                        message: "failed to resolve CODEX_HOME: \(error)"
                    )
                }
            } else {
                do {
                    socketPath = try AbsolutePath.resolve(rawSocketPath, against: currentDirectory).path
                } catch {
                    throw AppServerTransportParseError.invalidUnixSocketPath(
                        listenURL: listenURL,
                        message: String(describing: error)
                    )
                }
            }
            return .unixSocket(socketPath: socketPath)
        }

        if listenURL == "off" {
            return .off
        }

        if listenURL.hasPrefix("ws://") {
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
                throw AppServerTransportParseError.invalidWebSocketListenURL(listenURL)
            }

            return .webSocket(host: host, port: UInt16(port))
        }

        throw AppServerTransportParseError.unsupportedListenURL(listenURL)
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

private extension String {
    func stripPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else {
            return nil
        }
        return String(dropFirst(prefix.count))
    }
}
