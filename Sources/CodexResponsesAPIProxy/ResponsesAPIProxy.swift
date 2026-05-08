import Darwin
import Foundation

public struct ResponsesAPIProxyOptions: Equatable, Sendable {
    public static let defaultUpstreamURL = "https://api.openai.com/v1/responses"

    public let port: UInt16?
    public let serverInfoPath: URL?
    public let httpShutdown: Bool
    public let upstreamURL: String

    public init(
        port: UInt16? = nil,
        serverInfoPath: URL? = nil,
        httpShutdown: Bool = false,
        upstreamURL: String = Self.defaultUpstreamURL
    ) {
        self.port = port
        self.serverInfoPath = serverInfoPath
        self.httpShutdown = httpShutdown
        self.upstreamURL = upstreamURL
    }
}

public enum ResponsesAPIProxyError: Error, Equatable, CustomStringConvertible, Sendable {
    case apiKeyMissing
    case apiKeyTooLarge(Int)
    case invalidAPIKeyCharacters
    case stdinReadFailed(String)
    case invalidUpstreamURL(String)
    case bindFailed(String)
    case listenFailed(String)
    case localAddressFailed(String)
    case serverStoppedUnexpectedly

    public var description: String {
        switch self {
        case .apiKeyMissing:
            return "API key must be provided via stdin (e.g. printenv OPENAI_API_KEY | codex responses-api-proxy)"
        case let .apiKeyTooLarge(size):
            return "API key is too large to fit in the \(size)-byte buffer"
        case .invalidAPIKeyCharacters:
            return "API key may only contain ASCII letters, numbers, '-' or '_'"
        case let .stdinReadFailed(message):
            return message
        case let .invalidUpstreamURL(message):
            return message
        case let .bindFailed(message):
            return message
        case let .listenFailed(message):
            return message
        case let .localAddressFailed(message):
            return message
        case .serverStoppedUnexpectedly:
            return "server stopped unexpectedly"
        }
    }
}

public enum ResponsesAPIProxy {
    public static func run(options: ResponsesAPIProxyOptions) throws {
        let authHeader = try ResponsesAPIProxyAuth.readAuthHeaderFromStdin()
        let server = try ResponsesAPIProxyServer(options: options, authHeader: authHeader)
        if let serverInfoPath = options.serverInfoPath {
            try writeServerInfo(path: serverInfoPath, port: server.port)
        }

        fputs("responses-api-proxy listening on 127.0.0.1:\(server.port)\n", Darwin.stderr)
        try server.serveForever()
    }

    public static func writeServerInfo(path: URL, port: UInt16, pid: Int32 = Darwin.getpid()) throws {
        let parent = path.deletingLastPathComponent()
        if parent.path != path.path, !parent.path.isEmpty {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        let data = #"{"port":\#(port),"pid":\#(pid)}"# + "\n"
        try data.write(to: path, atomically: false, encoding: .utf8)
    }
}

public enum ResponsesAPIProxyAuth {
    static let bufferSize = 1024
    private static let prefix = Array("Bearer ".utf8)

    public static func readAuthHeaderFromStdin() throws -> String {
        try readAuthHeader { buffer in
            while true {
                let result = Darwin.read(STDIN_FILENO, buffer.baseAddress, buffer.count)
                if result == 0 {
                    return 0
                }
                if result < 0 {
                    if errno == EINTR {
                        continue
                    }
                    throw ResponsesAPIProxyError.stdinReadFailed(String(cString: strerror(errno)))
                }
                return result
            }
        }
    }

    public static func readAuthHeader(
        read: (UnsafeMutableBufferPointer<UInt8>) throws -> Int
    ) throws -> String {
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        buffer.replaceSubrange(0..<prefix.count, with: prefix)

        let prefixLength = prefix.count
        let capacity = buffer.count - prefixLength
        var totalRead = 0
        var sawNewline = false
        var sawEOF = false

        func zeroize() {
            for index in buffer.indices {
                buffer[index] = 0
            }
        }

        while totalRead < capacity {
            let start = prefixLength + totalRead
            let count = buffer.count - start
            let readCount: Int
            do {
                readCount = try buffer.withUnsafeMutableBufferPointer { pointer in
                    let base = pointer.baseAddress?.advanced(by: start)
                    return try read(UnsafeMutableBufferPointer(start: base, count: count))
                }
            } catch {
                zeroize()
                throw error
            }

            if readCount == 0 {
                sawEOF = true
                break
            }

            let newlyWritten = buffer[start..<(start + readCount)]
            if let newlineOffset = newlyWritten.firstIndex(of: UInt8(ascii: "\n")) {
                totalRead += newlineOffset - start + 1
                sawNewline = true
                break
            }
            totalRead += readCount
        }

        if totalRead == capacity, !sawNewline, !sawEOF {
            zeroize()
            throw ResponsesAPIProxyError.apiKeyTooLarge(bufferSize)
        }

        var total = prefixLength + totalRead
        while total > prefixLength, buffer[total - 1] == UInt8(ascii: "\n") || buffer[total - 1] == UInt8(ascii: "\r") {
            total -= 1
        }

        guard total > prefixLength else {
            zeroize()
            throw ResponsesAPIProxyError.apiKeyMissing
        }

        let keyBytes = buffer[prefixLength..<total]
        guard keyBytes.allSatisfy({ byte in
            byte.isASCIIAlphaNumeric || byte == UInt8(ascii: "-") || byte == UInt8(ascii: "_")
        }) else {
            zeroize()
            throw ResponsesAPIProxyError.invalidAPIKeyCharacters
        }

        let header = String(decoding: buffer[0..<total], as: UTF8.self)
        zeroize()
        return header
    }
}

public final class ResponsesAPIProxyServer: @unchecked Sendable {
    public let port: UInt16

    private let socketFD: Int32
    private let upstreamURL: URL
    private let hostHeader: String
    private let authHeader: String
    private let httpShutdown: Bool
    private var stopped = false

    public init(options: ResponsesAPIProxyOptions, authHeader: String) throws {
        guard let upstreamURL = URL(string: options.upstreamURL),
              let scheme = upstreamURL.scheme,
              (scheme == "http" || scheme == "https"),
              let host = upstreamURL.host
        else {
            throw ResponsesAPIProxyError.invalidUpstreamURL("parsing --upstream-url")
        }

        self.upstreamURL = upstreamURL
        if let upstreamPort = upstreamURL.port {
            self.hostHeader = "\(host):\(upstreamPort)"
        } else {
            self.hostHeader = host
        }
        self.authHeader = authHeader
        self.httpShutdown = options.httpShutdown

        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw ResponsesAPIProxyError.bindFailed("failed to create socket: \(String(cString: strerror(errno)))")
        }

        var reuse: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.stride))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = (options.port ?? 0).bigEndian
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.stride))
            }
        }
        guard bindResult == 0 else {
            let message = String(cString: strerror(errno))
            Darwin.close(fd)
            throw ResponsesAPIProxyError.bindFailed("failed to bind 127.0.0.1:\(options.port ?? 0): \(message)")
        }

        guard Darwin.listen(fd, SOMAXCONN) == 0 else {
            let message = String(cString: strerror(errno))
            Darwin.close(fd)
            throw ResponsesAPIProxyError.listenFailed("failed to listen: \(message)")
        }

        var bound = sockaddr_in()
        var boundLength = socklen_t(MemoryLayout<sockaddr_in>.stride)
        let localResult = withUnsafeMutablePointer(to: &bound) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.getsockname(fd, sockaddrPointer, &boundLength)
            }
        }
        guard localResult == 0 else {
            let message = String(cString: strerror(errno))
            Darwin.close(fd)
            throw ResponsesAPIProxyError.localAddressFailed("failed to read local_addr: \(message)")
        }

        self.socketFD = fd
        self.port = UInt16(bigEndian: bound.sin_port)
    }

    deinit {
        stop()
    }

    public func stop() {
        if !stopped {
            stopped = true
            Darwin.shutdown(socketFD, SHUT_RDWR)
            Darwin.close(socketFD)
        }
    }

    public func serveForever() throws {
        while !stopped {
            let clientFD = Darwin.accept(socketFD, nil, nil)
            if clientFD < 0 {
                if stopped || errno == EBADF || errno == EINVAL {
                    break
                }
                if errno == EINTR {
                    continue
                }
                break
            }

            Thread.detachNewThread { [authHeader, hostHeader, httpShutdown, upstreamURL] in
                Self.handleConnection(
                    fd: clientFD,
                    upstreamURL: upstreamURL,
                    hostHeader: hostHeader,
                    authHeader: authHeader,
                    httpShutdown: httpShutdown
                )
            }
        }

        throw ResponsesAPIProxyError.serverStoppedUnexpectedly
    }

    private static func handleConnection(
        fd: Int32,
        upstreamURL: URL,
        hostHeader: String,
        authHeader: String,
        httpShutdown: Bool
    ) {
        defer {
            Darwin.close(fd)
        }

        do {
            guard let request = try readHTTPRequest(fd: fd) else {
                return
            }

            if httpShutdown, request.method == "GET", request.path == "/shutdown" {
                sendResponse(fd: fd, status: 200, headers: [], body: Data())
                Darwin.exit(0)
            }

            guard request.method == "POST", request.path == "/v1/responses" else {
                sendResponse(fd: fd, status: 403, headers: [], body: Data())
                return
            }

            switch forward(request: request, upstreamURL: upstreamURL, hostHeader: hostHeader, authHeader: authHeader) {
            case let .success(response):
                sendResponse(fd: fd, status: response.statusCode, headers: response.headers, body: response.body)
            case let .failure(error):
                fputs("forwarding error: \(error)\n", Darwin.stderr)
                sendResponse(fd: fd, status: 502, headers: [], body: Data())
            }
        } catch {
            fputs("forwarding error: \(error)\n", Darwin.stderr)
        }
    }

    private static func readHTTPRequest(fd: Int32) throws -> ProxyHTTPRequest? {
        var data = Data()
        var headerEnd: Range<Data.Index>?
        var contentLength = 0

        while true {
            var buffer = [UInt8](repeating: 0, count: 8_192)
            let readCount = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.recv(fd, rawBuffer.baseAddress, rawBuffer.count, 0)
            }
            if readCount == 0 {
                return nil
            }
            if readCount < 0 {
                if errno == EINTR {
                    continue
                }
                throw ResponsesAPIProxyError.stdinReadFailed(String(cString: strerror(errno)))
            }

            data.append(buffer, count: readCount)

            if headerEnd == nil,
               let range = data.range(of: Data([13, 10, 13, 10])) {
                headerEnd = range
                let headerData = data[..<range.lowerBound]
                let headerString = String(decoding: headerData, as: UTF8.self)
                contentLength = parseContentLength(from: headerString)
            }

            if let headerEnd, data.count >= headerEnd.upperBound + contentLength {
                let headerData = data[..<headerEnd.lowerBound]
                let bodyStart = headerEnd.upperBound
                let body = data[bodyStart..<(bodyStart + contentLength)]
                return parseHTTPRequestHeader(String(decoding: headerData, as: UTF8.self), body: Data(body))
            }
        }
    }

    private static func parseContentLength(from header: String) -> Int {
        for line in header.components(separatedBy: "\r\n").dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                continue
            }
            if parts[0].trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("content-length") == .orderedSame {
                return Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        return 0
    }

    private static func parseHTTPRequestHeader(_ header: String, body: Data) -> ProxyHTTPRequest? {
        var lines = header.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return nil
        }
        lines.removeFirst()

        let requestParts = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard requestParts.count >= 2 else {
            return nil
        }

        var headers: [(String, String)] = []
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                continue
            }
            headers.append((
                String(parts[0]).trimmingCharacters(in: .whitespaces),
                String(parts[1]).trimmingCharacters(in: .whitespaces)
            ))
        }

        return ProxyHTTPRequest(
            method: String(requestParts[0]),
            path: String(requestParts[1]),
            headers: headers,
            body: body
        )
    }

    private static func forward(
        request: ProxyHTTPRequest,
        upstreamURL: URL,
        hostHeader: String,
        authHeader: String
    ) -> Result<ProxyHTTPResponse, Error> {
        var upstreamRequest = URLRequest(url: upstreamURL)
        upstreamRequest.httpMethod = "POST"
        upstreamRequest.httpBody = request.body
        upstreamRequest.timeoutInterval = .infinity

        for (name, value) in request.headers {
            let lower = name.lowercased()
            if lower == "authorization" || lower == "host" {
                continue
            }
            upstreamRequest.addValue(value, forHTTPHeaderField: lower)
        }
        upstreamRequest.setValue(authHeader, forHTTPHeaderField: "authorization")
        upstreamRequest.setValue(hostHeader, forHTTPHeaderField: "host")

        let semaphore = DispatchSemaphore(value: 0)
        let box = ProxyForwardResultBox()
        let task = URLSession.shared.dataTask(with: upstreamRequest) { data, response, error in
            if let error {
                box.set(.failure(error))
            } else {
                let httpResponse = response as? HTTPURLResponse
                box.set(.success(ProxyHTTPResponse(
                    statusCode: httpResponse?.statusCode ?? 502,
                    headers: filteredResponseHeaders(httpResponse),
                    body: data ?? Data()
                )))
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()
        return box.result() ?? .failure(ResponsesAPIProxyError.serverStoppedUnexpectedly)
    }

    private static func filteredResponseHeaders(_ response: HTTPURLResponse?) -> [(String, String)] {
        guard let response else {
            return []
        }
        let skipped = Set(["content-length", "transfer-encoding", "connection", "trailer", "upgrade"])
        var headers: [(String, String)] = []
        for (name, value) in response.allHeaderFields {
            let headerName = String(describing: name)
            guard !skipped.contains(headerName.lowercased()) else {
                continue
            }
            headers.append((headerName, String(describing: value)))
        }
        return headers
    }

    private static func sendResponse(fd: Int32, status: Int, headers: [(String, String)], body: Data) {
        var response = Data()
        response.append(Data("HTTP/1.1 \(status) \(reasonPhrase(for: status))\r\n".utf8))
        for (name, value) in headers {
            response.append(Data("\(name): \(value)\r\n".utf8))
        }
        response.append(Data("Content-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8))
        response.append(body)
        sendAll(fd: fd, data: response)
    }

    private static func sendAll(fd: Int32, data: Data) {
        data.withUnsafeBytes { rawBuffer in
            guard var pointer = rawBuffer.baseAddress else {
                return
            }
            var remaining = rawBuffer.count
            while remaining > 0 {
                let sent = Darwin.send(fd, pointer, remaining, 0)
                if sent <= 0 {
                    if errno == EINTR {
                        continue
                    }
                    return
                }
                pointer = pointer.advanced(by: sent)
                remaining -= sent
            }
        }
    }

    private static func reasonPhrase(for status: Int) -> String {
        switch status {
        case 200:
            return "OK"
        case 403:
            return "Forbidden"
        case 502:
            return "Bad Gateway"
        default:
            return "Status"
        }
    }
}

private struct ProxyHTTPRequest {
    let method: String
    let path: String
    let headers: [(String, String)]
    let body: Data
}

private struct ProxyHTTPResponse {
    let statusCode: Int
    let headers: [(String, String)]
    let body: Data
}

private final class ProxyForwardResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Result<ProxyHTTPResponse, Error>?

    func set(_ result: Result<ProxyHTTPResponse, Error>) {
        lock.lock()
        value = result
        lock.unlock()
    }

    func result() -> Result<ProxyHTTPResponse, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private extension UInt8 {
    var isASCIIAlphaNumeric: Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(self)
            || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(self)
            || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(self)
    }
}
