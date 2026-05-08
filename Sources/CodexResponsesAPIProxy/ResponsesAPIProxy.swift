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
        try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: bufferSize) { buffer in
            buffer.initialize(repeating: 0)
            defer { secureZero(buffer) }

            for index in prefix.indices {
                buffer[index] = prefix[index]
            }

            let prefixLength = prefix.count
            let capacity = buffer.count - prefixLength
            var totalRead = 0
            var sawNewline = false
            var sawEOF = false

            while totalRead < capacity {
                let start = prefixLength + totalRead
                let count = buffer.count - start
                let readCount = try read(UnsafeMutableBufferPointer(
                    start: buffer.baseAddress?.advanced(by: start),
                    count: count
                ))

                if readCount == 0 {
                    sawEOF = true
                    break
                }

                let end = start + readCount
                if let newlineIndex = (start..<end).first(where: { buffer[$0] == UInt8(ascii: "\n") }) {
                    totalRead += newlineIndex - start + 1
                    sawNewline = true
                    break
                }
                totalRead += readCount
            }

            if totalRead == capacity, !sawNewline, !sawEOF {
                throw ResponsesAPIProxyError.apiKeyTooLarge(bufferSize)
            }

            var total = prefixLength + totalRead
            while total > prefixLength,
                  buffer[total - 1] == UInt8(ascii: "\n") || buffer[total - 1] == UInt8(ascii: "\r") {
                total -= 1
            }

            guard total > prefixLength else {
                throw ResponsesAPIProxyError.apiKeyMissing
            }

            for index in prefixLength..<total {
                let byte = buffer[index]
                guard byte.isASCIIAlphaNumeric || byte == UInt8(ascii: "-") || byte == UInt8(ascii: "_") else {
                    throw ResponsesAPIProxyError.invalidAPIKeyCharacters
                }
            }

            return String(decoding: UnsafeBufferPointer(start: buffer.baseAddress, count: total), as: UTF8.self)
        }
    }

    private static func secureZero(_ buffer: UnsafeMutableBufferPointer<UInt8>) {
        guard let baseAddress = buffer.baseAddress else {
            return
        }
        _ = memset_s(baseAddress, buffer.count, 0, buffer.count)
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

            switch forward(request: request, upstreamURL: upstreamURL, hostHeader: hostHeader, authHeader: authHeader, downstreamFD: fd) {
            case .success:
                break
            case let .failure(error, responseStarted):
                fputs("forwarding error: \(error)\n", Darwin.stderr)
                if !responseStarted {
                    sendResponse(fd: fd, status: 502, headers: [], body: Data())
                }
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
        authHeader: String,
        downstreamFD: Int32
    ) -> ProxyForwardResult {
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
        let delegate = ProxyStreamingForwarder(fd: downstreamFD, completion: semaphore)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = .infinity
        configuration.timeoutIntervalForResource = .infinity
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: queue)
        let task = session.dataTask(with: upstreamRequest)
        task.resume()
        semaphore.wait()
        session.invalidateAndCancel()
        return delegate.result ?? .failure(ResponsesAPIProxyError.serverStoppedUnexpectedly, responseStarted: delegate.responseStarted)
    }

    fileprivate static func filteredResponseHeaders(_ response: HTTPURLResponse?) -> [(String, String)] {
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
        guard sendResponseHead(fd: fd, status: status, headers: headers, contentLength: body.count) else {
            return
        }
        _ = sendAll(fd: fd, data: body)
    }

    fileprivate static func sendResponseHead(
        fd: Int32,
        status: Int,
        headers: [(String, String)],
        contentLength: Int?
    ) -> Bool {
        var response = Data()
        response.append(Data("HTTP/1.1 \(status) \(reasonPhrase(for: status))\r\n".utf8))
        for (name, value) in headers {
            response.append(Data("\(name): \(value)\r\n".utf8))
        }
        if let contentLength {
            response.append(Data("Content-Length: \(contentLength)\r\n".utf8))
        }
        response.append(Data("Connection: close\r\n\r\n".utf8))
        return sendAll(fd: fd, data: response)
    }

    @discardableResult
    fileprivate static func sendAll(fd: Int32, data: Data) -> Bool {
        data.withUnsafeBytes { rawBuffer in
            guard var pointer = rawBuffer.baseAddress else {
                return true
            }
            var remaining = rawBuffer.count
            while remaining > 0 {
                let sent = Darwin.send(fd, pointer, remaining, 0)
                if sent <= 0 {
                    if errno == EINTR {
                        continue
                    }
                    return false
                }
                pointer = pointer.advanced(by: sent)
                remaining -= sent
            }
            return true
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

private enum ProxyForwardResult {
    case success
    case failure(Error, responseStarted: Bool)
}

private final class ProxyStreamingForwarder: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let fd: Int32
    private let completion: DispatchSemaphore
    private let lock = NSLock()
    private(set) var result: ProxyForwardResult?
    private(set) var responseStarted = false
    private var writeFailed = false

    init(fd: Int32, completion: DispatchSemaphore) {
        self.fd = fd
        self.completion = completion
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let httpResponse = response as? HTTPURLResponse else {
            finish(.failure(URLError(.badServerResponse), responseStarted: false))
            completionHandler(.cancel)
            return
        }

        let contentLength = httpResponse.expectedContentLength >= 0
            && httpResponse.expectedContentLength <= Int.max
            ? Int(httpResponse.expectedContentLength)
            : nil
        let sentHead = ResponsesAPIProxyServer.sendResponseHead(
            fd: fd,
            status: httpResponse.statusCode,
            headers: ResponsesAPIProxyServer.filteredResponseHeaders(httpResponse),
            contentLength: contentLength
        )
        setResponseStarted()
        if sentHead {
            completionHandler(.allow)
        } else {
            setWriteFailed()
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard ResponsesAPIProxyServer.sendAll(fd: fd, data: data) else {
            setWriteFailed()
            dataTask.cancel()
            return
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if writeFailed {
            finish(.success)
        } else if let error {
            finish(.failure(error, responseStarted: responseStarted))
        } else {
            finish(.success)
        }
    }

    private func setResponseStarted() {
        lock.lock()
        responseStarted = true
        lock.unlock()
    }

    private func setWriteFailed() {
        lock.lock()
        writeFailed = true
        lock.unlock()
    }

    private func finish(_ result: ProxyForwardResult) {
        lock.lock()
        let shouldSignal = self.result == nil
        if shouldSignal {
            self.result = result
        }
        lock.unlock()

        if shouldSignal {
            completion.signal()
        }
    }
}

private extension UInt8 {
    var isASCIIAlphaNumeric: Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(self)
            || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(self)
            || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(self)
    }
}
