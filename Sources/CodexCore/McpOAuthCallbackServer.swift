import Darwin
import Foundation

public protocol McpOAuthCallbackServing: Sendable {
    var redirectURI: String { get }

    func waitForCallback(timeout: TimeInterval) async throws -> McpOAuthCallbackResult
    func stop()
}

public enum McpOAuthCallbackServerError: Error, Equatable, CustomStringConvertible, Sendable {
    case listenFailed(String)
    case invalidCallbackPort(UInt16)
    case invalidCallbackURL(String)
    case callbackTimedOut
    case callbackCancelled

    public var description: String {
        switch self {
        case let .listenFailed(message):
            return message
        case let .invalidCallbackPort(port):
            return "invalid MCP OAuth callback port `\(port)`: port must be between 1 and 65535"
        case let .invalidCallbackURL(url):
            return "invalid MCP OAuth callback URL `\(url)`"
        case .callbackTimedOut:
            return "timed out waiting for OAuth callback"
        case .callbackCancelled:
            return "OAuth callback was cancelled"
        }
    }
}

public final class McpOAuthLocalCallbackServer: McpOAuthCallbackServing, @unchecked Sendable {
    public let redirectURI: String

    private let queue: DispatchQueue
    private let callbackPath: String
    private let lock = NSLock()
    private var listenFileDescriptor: Int32?
    private var waitContinuation: CheckedContinuation<McpOAuthCallbackResult, Error>?
    private var pendingResult: McpOAuthCallbackResult?
    private var pendingError: Error?
    private var completed = false

    private init(listenFileDescriptor: Int32, port: UInt16, redirectURI: String?, callbackPath: String) {
        self.listenFileDescriptor = listenFileDescriptor
        self.redirectURI = redirectURI ?? "http://127.0.0.1:\(port)/callback"
        self.callbackPath = callbackPath
        self.queue = DispatchQueue(label: "codex.mcp-oauth.callback.\(port)")
    }

    deinit {
        stop()
    }

    public static func start(
        port requestedPort: UInt16? = nil,
        redirectURI redirectURIOverride: String? = nil
    ) throws -> McpOAuthLocalCallbackServer {
        if let requestedPort, requestedPort == 0 {
            throw McpOAuthCallbackServerError.invalidCallbackPort(requestedPort)
        }

        let parsedRedirectURI: URL?
        if let redirectURIOverride {
            guard let url = URL(string: redirectURIOverride), url.scheme != nil, url.host != nil else {
                throw McpOAuthCallbackServerError.invalidCallbackURL(redirectURIOverride)
            }
            parsedRedirectURI = url
        } else {
            parsedRedirectURI = nil
        }
        let bindHost = Self.callbackBindHost(parsedRedirectURI)
        let callbackPath = Self.callbackPath(from: parsedRedirectURI)

        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw McpOAuthCallbackServerError.listenFailed(posixMessage(operation: "socket"))
        }

        do {
            var reuse: Int32 = 1
            guard Darwin.setsockopt(
                fd,
                SOL_SOCKET,
                SO_REUSEADDR,
                &reuse,
                socklen_t(MemoryLayout<Int32>.size)
            ) == 0 else {
                throw McpOAuthCallbackServerError.listenFailed(posixMessage(operation: "setsockopt"))
            }

            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = in_port_t(requestedPort ?? 0).bigEndian
            address.sin_addr = in_addr(s_addr: Darwin.inet_addr(bindHost))

            let bindResult = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    Darwin.bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard bindResult == 0 else {
                throw McpOAuthCallbackServerError.listenFailed(posixMessage(operation: "bind"))
            }

            guard Darwin.listen(fd, SOMAXCONN) == 0 else {
                throw McpOAuthCallbackServerError.listenFailed(posixMessage(operation: "listen"))
            }

            var actualAddress = sockaddr_in()
            var actualLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let nameResult = withUnsafeMutablePointer(to: &actualAddress) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    Darwin.getsockname(fd, sockaddrPointer, &actualLength)
                }
            }
            guard nameResult == 0 else {
                throw McpOAuthCallbackServerError.listenFailed(posixMessage(operation: "getsockname"))
            }

            let server = McpOAuthLocalCallbackServer(
                listenFileDescriptor: fd,
                port: UInt16(bigEndian: actualAddress.sin_port),
                redirectURI: redirectURIOverride,
                callbackPath: callbackPath
            )
            server.queue.async { [server] in
                server.acceptLoop()
            }
            return server
        } catch {
            Darwin.close(fd)
            throw error
        }
    }

    public func waitForCallback(timeout: TimeInterval) async throws -> McpOAuthCallbackResult {
        try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: McpOAuthCallbackResult.self) { group in
                group.addTask { [self] in
                    try await waitForCallback()
                }
                group.addTask { [self] in
                    let clamped = max(timeout, 1)
                    try await Task.sleep(nanoseconds: UInt64(clamped * 1_000_000_000))
                    finish(error: McpOAuthCallbackServerError.callbackTimedOut)
                    throw McpOAuthCallbackServerError.callbackTimedOut
                }

                do {
                    guard let result = try await group.next() else {
                        throw McpOAuthCallbackServerError.callbackCancelled
                    }
                    group.cancelAll()
                    return result
                } catch {
                    group.cancelAll()
                    throw error
                }
            }
        } onCancel: { [self] in
            finish(error: McpOAuthCallbackServerError.callbackCancelled)
        }
    }

    public func stop() {
        finish(error: McpOAuthCallbackServerError.callbackCancelled)
    }

    private func waitForCallback() async throws -> McpOAuthCallbackResult {
        try await withCheckedThrowingContinuation { continuation in
            let immediate: Result<McpOAuthCallbackResult, Error>? = lock.withLock {
                if let pendingResult {
                    self.pendingResult = nil
                    return .success(pendingResult)
                }
                if let pendingError {
                    self.pendingError = nil
                    return .failure(pendingError)
                }
                if completed {
                    return .failure(McpOAuthCallbackServerError.callbackCancelled)
                }
                if waitContinuation == nil {
                    waitContinuation = continuation
                    return nil
                }
                return .failure(McpOAuthCallbackServerError.callbackCancelled)
            }

            if let immediate {
                switch immediate {
                case let .success(result):
                    continuation.resume(returning: result)
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func acceptLoop() {
        while true {
            guard let listenFD = currentListenFileDescriptor() else {
                return
            }

            let clientFD = Darwin.accept(listenFD, nil, nil)
            if clientFD < 0 {
                if currentListenFileDescriptor() == nil {
                    return
                }
                continue
            }

            let shouldStop = handleConnection(fileDescriptor: clientFD)
            Darwin.close(clientFD)
            if shouldStop {
                return
            }
        }
    }

    private func currentListenFileDescriptor() -> Int32? {
        lock.withLock {
            listenFileDescriptor
        }
    }

    private func handleConnection(fileDescriptor: Int32) -> Bool {
        guard let path = readRequestPath(fileDescriptor: fileDescriptor) else {
            writeHTTPResponse(
                fileDescriptor: fileDescriptor,
                statusCode: 400,
                reason: "Bad Request",
                body: "Invalid OAuth callback"
            )
            return false
        }

        switch McpOAuthCallbackParser.parseOutcome(path: path, callbackPath: callbackPath) {
        case let .success(callback):
            writeHTTPResponse(
                fileDescriptor: fileDescriptor,
                statusCode: 200,
                reason: "OK",
                body: "Authentication complete. You may close this window."
            )
            finish(result: callback)
            return true

        case let .providerError(error):
            writeHTTPResponse(
                fileDescriptor: fileDescriptor,
                statusCode: 400,
                reason: "Bad Request",
                body: error.description
            )
            finish(error: error)
            return true

        case .invalid:
            writeHTTPResponse(
                fileDescriptor: fileDescriptor,
                statusCode: 400,
                reason: "Bad Request",
                body: "Invalid OAuth callback"
            )
            return false
        }
    }

    private func readRequestPath(fileDescriptor: Int32) -> String? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        let headerEnd = Data("\r\n\r\n".utf8)
        let fallbackHeaderEnd = Data("\n\n".utf8)

        while data.count < 8192 {
            let count = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.recv(fileDescriptor, rawBuffer.baseAddress, rawBuffer.count, 0)
            }
            guard count > 0 else {
                break
            }
            data.append(buffer, count: count)
            if data.range(of: headerEnd) != nil || data.range(of: fallbackHeaderEnd) != nil {
                break
            }
        }

        guard let request = String(data: data, encoding: .utf8),
              let firstLine = request.split(whereSeparator: \.isNewline).first
        else {
            return nil
        }
        let parts = firstLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2, parts[0] == "GET" else {
            return nil
        }
        return String(parts[1])
    }

    private func writeHTTPResponse(fileDescriptor: Int32, statusCode: Int, reason: String, body: String) {
        let bodyData = Data(body.utf8)
        let header = "HTTP/1.1 \(statusCode) \(reason)\r\n"
            + "Content-Type: text/plain; charset=utf-8\r\n"
            + "Content-Length: \(bodyData.count)\r\n"
            + "Connection: close\r\n"
            + "\r\n"
        var response = Data(header.utf8)
        response.append(bodyData)
        response.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }
            _ = Darwin.send(fileDescriptor, baseAddress, rawBuffer.count, 0)
        }
    }

    private func finish(result: McpOAuthCallbackResult) {
        let continuation: CheckedContinuation<McpOAuthCallbackResult, Error>?
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        continuation = waitContinuation
        waitContinuation = nil
        if continuation == nil {
            pendingResult = result
        }
        closeListenFileDescriptorLocked()
        lock.unlock()

        continuation?.resume(returning: result)
    }

    private func finish(error: Error) {
        let continuation: CheckedContinuation<McpOAuthCallbackResult, Error>?
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        continuation = waitContinuation
        waitContinuation = nil
        if continuation == nil {
            pendingError = error
        }
        closeListenFileDescriptorLocked()
        lock.unlock()

        continuation?.resume(throwing: error)
    }

    private func closeListenFileDescriptorLocked() {
        guard let fd = listenFileDescriptor else {
            return
        }
        listenFileDescriptor = nil
        Darwin.shutdown(fd, SHUT_RDWR)
        Darwin.close(fd)
    }

    private static func posixMessage(operation: String) -> String {
        "\(operation) failed: \(String(cString: Darwin.strerror(errno)))"
    }

    private static func callbackBindHost(_ redirectURI: URL?) -> String {
        guard let host = redirectURI?.host else {
            return "127.0.0.1"
        }
        switch host {
        case "localhost", "127.0.0.1", "::1":
            return "127.0.0.1"
        default:
            return "0.0.0.0"
        }
    }

    private static func callbackPath(from redirectURI: URL?) -> String {
        guard let path = redirectURI?.path, !path.isEmpty else {
            return "/callback"
        }
        return path
    }
}
