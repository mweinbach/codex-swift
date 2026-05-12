import CodexCore
import CryptoKit
import Darwin
import Foundation

public enum AppServerWebSocketTransportError: Error, CustomStringConvertible, Equatable, Sendable {
    case socket(String)
    case invalidHandshake
    case unsupportedFrame(String)
    case closed
    case handledHTTPResponse

    public var description: String {
        switch self {
        case let .socket(message):
            return message
        case .invalidHandshake:
            return "invalid app-server websocket handshake"
        case let .unsupportedFrame(message):
            return message
        case .closed:
            return "app-server websocket connection closed"
        case .handledHTTPResponse:
            return "app-server websocket handled http response"
        }
    }
}

public struct AppServerWebSocketTransport: Sendable {
    public typealias Announce = @Sendable (String) async throws -> Void

    private let configuration: CodexAppServerConfiguration
    private let authPolicy: AppServerWebsocketAuthPolicy
    private let connectionIDAllocator = AppServerConnectionIDAllocator()
    private let threadStateManager = AppServerThreadStateManager()

    public init(
        configuration: CodexAppServerConfiguration,
        authPolicy: AppServerWebsocketAuthPolicy = AppServerWebsocketAuthPolicy()
    ) {
        self.configuration = configuration
        self.authPolicy = authPolicy
    }

    public func run(host: String, port: UInt16, announce: @escaping Announce) async throws {
        let listenFD = try Self.makeListeningSocket(host: host, port: port)
        defer {
            Darwin.shutdown(listenFD, SHUT_RDWR)
            Darwin.close(listenFD)
        }

        let actualPort = try Self.localPort(for: listenFD)
        try await announce("ws://\(Self.displayHost(host)):\(actualPort)\n")

        while !Task.isCancelled {
            var descriptor = pollfd(fd: listenFD, events: Int16(POLLIN), revents: 0)
            let ready = Darwin.poll(&descriptor, 1, 100)
            if ready == 0 {
                continue
            }
            guard ready > 0 else {
                if errno == EINTR {
                    continue
                }
                throw AppServerWebSocketTransportError.socket(Self.posixMessage(operation: "poll"))
            }
            let clientFD = Darwin.accept(listenFD, nil, nil)
            guard clientFD >= 0 else {
                if errno == EINTR {
                    continue
                }
                throw AppServerWebSocketTransportError.socket(Self.posixMessage(operation: "accept"))
            }

            let configuration = configuration
            let authPolicy = authPolicy
            let connectionID = await connectionIDAllocator.allocate()
            let threadStateManager = threadStateManager
            Task.detached {
                try? await Self.runConnectedClient(
                    fileDescriptor: clientFD,
                    configuration: configuration,
                    connectionID: connectionID,
                    authPolicy: authPolicy,
                    threadStateManager: threadStateManager,
                    rejectOriginHeaders: true
                )
            }
        }
    }

    public func run(socketPath: String, announce: @escaping Announce = { _ in }) async throws {
        let listenFD = try Self.makeUnixListeningSocket(socketPath: socketPath)
        defer {
            Darwin.shutdown(listenFD, SHUT_RDWR)
            Darwin.close(listenFD)
            _ = try? FileManager.default.removeItem(atPath: socketPath)
        }

        try await announce(socketPath)

        while !Task.isCancelled {
            var descriptor = pollfd(fd: listenFD, events: Int16(POLLIN), revents: 0)
            let ready = Darwin.poll(&descriptor, 1, 100)
            if ready == 0 {
                continue
            }
            guard ready > 0 else {
                if errno == EINTR {
                    continue
                }
                throw AppServerWebSocketTransportError.socket(Self.posixMessage(operation: "poll"))
            }
            let clientFD = Darwin.accept(listenFD, nil, nil)
            guard clientFD >= 0 else {
                if errno == EINTR || errno == ECONNABORTED {
                    continue
                }
                throw AppServerWebSocketTransportError.socket(Self.posixMessage(operation: "accept"))
            }

            let configuration = configuration
            let connectionID = await connectionIDAllocator.allocate()
            let threadStateManager = threadStateManager
            Task.detached {
                try? await Self.runConnectedClient(
                    fileDescriptor: clientFD,
                    configuration: configuration,
                    connectionID: connectionID,
                    authPolicy: AppServerWebsocketAuthPolicy(),
                    threadStateManager: threadStateManager,
                    rejectOriginHeaders: false
                )
            }
        }
    }

    private static func runConnectedClient(
        fileDescriptor: Int32,
        configuration: CodexAppServerConfiguration,
        connectionID: AppServerConnectionID,
        authPolicy: AppServerWebsocketAuthPolicy,
        threadStateManager: AppServerThreadStateManager,
        rejectOriginHeaders: Bool
    ) async throws {
        defer {
            Darwin.shutdown(fileDescriptor, SHUT_RDWR)
            Darwin.close(fileDescriptor)
        }

        do {
            try performHandshake(
                fileDescriptor: fileDescriptor,
                authPolicy: authPolicy,
                rejectOriginHeaders: rejectOriginHeaders
            )
        } catch AppServerWebSocketTransportError.handledHTTPResponse {
            return
        }
        let writer = AppServerWebSocketFrameWriter(fileDescriptor: fileDescriptor)
        let processor = CodexAppServerMessageProcessor(
            configuration: configuration,
            connectionID: connectionID,
            notificationSink: { data in
                for text in websocketTexts(from: data) {
                    try? await writer.writeText(text)
                }
            },
            threadStateManager: threadStateManager
        )
        defer {
            processor.closeConnection()
        }

        do {
            while !Task.isCancelled {
                let frame = try readFrame(fileDescriptor: fileDescriptor)
                switch frame.opcode {
                case .text:
                    let data = Data(frame.payload)
                    for text in websocketTexts(from: processor.processLine(data)) {
                        try await writer.writeText(text)
                    }
                case .binary:
                    continue
                case .close:
                    return
                case .ping:
                    try await writer.writePong(payload: frame.payload)
                case .pong:
                    continue
                }
            }
        } catch AppServerWebSocketTransportError.closed {
            return
        } catch {
            throw error
        }
    }

    private static func websocketTexts(from data: Data?) -> [String] {
        guard let data, !data.isEmpty else {
            return []
        }
        let text = String(decoding: data, as: UTF8.self)
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    private static func performHandshake(
        fileDescriptor: Int32,
        authPolicy: AppServerWebsocketAuthPolicy,
        rejectOriginHeaders: Bool
    ) throws {
        let request = try readHTTPRequest(fileDescriptor: fileDescriptor)
        guard request.method == "GET" else {
            throw AppServerWebSocketTransportError.invalidHandshake
        }

        if rejectOriginHeaders, request.headers["origin"] != nil {
            try writeHTTPResponse(fileDescriptor: fileDescriptor, statusCode: 403, reason: "Forbidden")
            throw AppServerWebSocketTransportError.handledHTTPResponse
        }

        if request.path == "/readyz" || request.path == "/healthz" {
            try writeHTTPResponse(fileDescriptor: fileDescriptor, statusCode: 200, reason: "OK")
            throw AppServerWebSocketTransportError.handledHTTPResponse
        }

        guard request.headers["upgrade"]?.lowercased() == "websocket",
              request.headers["connection"]?.lowercased().contains("upgrade") == true,
              let key = request.headers["sec-websocket-key"],
              request.headers["sec-websocket-version"] == "13"
        else {
            throw AppServerWebSocketTransportError.invalidHandshake
        }

        if let authError = AppServerWebsocketAuthorizer.authorize(
            authorizationHeader: request.headers["authorization"],
            policy: authPolicy
        ) {
            try writeHTTPResponse(
                fileDescriptor: fileDescriptor,
                statusCode: authError.statusCode,
                reason: "Unauthorized",
                body: authError.description
            )
            throw AppServerWebSocketTransportError.handledHTTPResponse
        }

        let accept = websocketAcceptKey(for: key)
        let response = (
            "HTTP/1.1 101 Switching Protocols\r\n" +
            "Upgrade: websocket\r\n" +
            "Connection: Upgrade\r\n" +
            "Sec-WebSocket-Accept: \(accept)\r\n" +
            "\r\n"
        )
        try writeAll(fileDescriptor: fileDescriptor, bytes: Array(response.utf8))
    }

    private struct HTTPRequest {
        let method: String
        let path: String
        let headers: [String: String]
    }

    private static func readHTTPRequest(fileDescriptor: Int32) throws -> HTTPRequest {
        var bytes: [UInt8] = []
        while !bytes.suffix(4).elementsEqual([13, 10, 13, 10]) {
            guard bytes.count < 16 * 1024 else {
                throw AppServerWebSocketTransportError.invalidHandshake
            }
            bytes.append(contentsOf: try readExact(fileDescriptor: fileDescriptor, byteCount: 1))
        }
        let request = String(decoding: bytes, as: UTF8.self)
        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            throw AppServerWebSocketTransportError.invalidHandshake
        }
        let parts = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2 else {
            throw AppServerWebSocketTransportError.invalidHandshake
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else {
                continue
            }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }
        return HTTPRequest(method: String(parts[0]), path: String(parts[1]), headers: headers)
    }

    private static func websocketAcceptKey(for key: String) -> String {
        let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let digest = Insecure.SHA1.hash(data: Data((key + magic).utf8))
        return Data(digest).base64EncodedString()
    }

    private static func writeHTTPResponse(
        fileDescriptor: Int32,
        statusCode: Int,
        reason: String,
        body: String = ""
    ) throws {
        let bodyBytes = Array(body.utf8)
        let contentType = bodyBytes.isEmpty ? "" : "Content-Type: text/plain; charset=utf-8\r\n"
        let response = (
            "HTTP/1.1 \(statusCode) \(reason)\r\n" +
            contentType +
            "Content-Length: \(bodyBytes.count)\r\n" +
            "\r\n" +
            body
        )
        try writeAll(fileDescriptor: fileDescriptor, bytes: Array(response.utf8))
    }

    fileprivate enum WebSocketOpcode: UInt8 {
        case text = 0x1
        case binary = 0x2
        case close = 0x8
        case ping = 0x9
        case pong = 0xA
    }

    private struct WebSocketFrame {
        let opcode: WebSocketOpcode
        let payload: [UInt8]
    }

    private static func readFrame(fileDescriptor: Int32) throws -> WebSocketFrame {
        let header = try readExact(fileDescriptor: fileDescriptor, byteCount: 2)
        let isFinal = (header[0] & 0x80) != 0
        guard isFinal else {
            throw AppServerWebSocketTransportError.unsupportedFrame(
                "fragmented app-server websocket frames are not supported"
            )
        }
        guard let opcode = WebSocketOpcode(rawValue: header[0] & 0x0F) else {
            throw AppServerWebSocketTransportError.unsupportedFrame("unsupported app-server websocket opcode")
        }
        let masked = (header[1] & 0x80) != 0
        var payloadLength = UInt64(header[1] & 0x7F)
        if payloadLength == 126 {
            let bytes = try readExact(fileDescriptor: fileDescriptor, byteCount: 2)
            payloadLength = UInt64(bytes[0]) << 8 | UInt64(bytes[1])
        } else if payloadLength == 127 {
            let bytes = try readExact(fileDescriptor: fileDescriptor, byteCount: 8)
            payloadLength = bytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        }
        guard payloadLength <= UInt64(Int.max) else {
            throw AppServerWebSocketTransportError.unsupportedFrame("app-server websocket frame is too large")
        }
        let mask = masked ? try readExact(fileDescriptor: fileDescriptor, byteCount: 4) : []
        var payload = try readExact(fileDescriptor: fileDescriptor, byteCount: Int(payloadLength))
        if masked {
            for index in payload.indices {
                payload[index] ^= mask[index % 4]
            }
        }
        return WebSocketFrame(opcode: opcode, payload: payload)
    }

    fileprivate static func writeFrame(
        fileDescriptor: Int32,
        opcode: WebSocketOpcode,
        payload: [UInt8],
        masked: Bool
    ) throws {
        var frame: [UInt8] = [0x80 | opcode.rawValue]
        let maskBit: UInt8 = masked ? 0x80 : 0
        if payload.count < 126 {
            frame.append(maskBit | UInt8(payload.count))
        } else if payload.count <= UInt16.max {
            frame.append(maskBit | 126)
            frame.append(UInt8((payload.count >> 8) & 0xFF))
            frame.append(UInt8(payload.count & 0xFF))
        } else {
            frame.append(maskBit | 127)
            let length = UInt64(payload.count)
            for shift in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((length >> UInt64(shift)) & 0xFF))
            }
        }

        if masked {
            let mask: [UInt8] = [0x12, 0x34, 0x56, 0x78]
            frame += mask
            frame += payload.enumerated().map { index, byte in byte ^ mask[index % 4] }
        } else {
            frame += payload
        }
        try writeAll(fileDescriptor: fileDescriptor, bytes: frame)
    }

    private static func readExact(fileDescriptor: Int32, byteCount: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        var offset = 0
        while offset < byteCount {
            let count = bytes.withUnsafeMutableBytes { buffer in
                Darwin.recv(fileDescriptor, buffer.baseAddress!.advanced(by: offset), byteCount - offset, 0)
            }
            if count == 0 {
                throw AppServerWebSocketTransportError.closed
            }
            guard count > 0 else {
                if errno == EINTR {
                    continue
                }
                throw AppServerWebSocketTransportError.socket(posixMessage(operation: "recv"))
            }
            offset += count
        }
        return bytes
    }

    private static func writeAll(fileDescriptor: Int32, bytes: [UInt8]) throws {
        var offset = 0
        while offset < bytes.count {
            let count = bytes.withUnsafeBytes { buffer in
                Darwin.send(fileDescriptor, buffer.baseAddress!.advanced(by: offset), bytes.count - offset, 0)
            }
            guard count >= 0 else {
                if errno == EINTR {
                    continue
                }
                throw AppServerWebSocketTransportError.socket(posixMessage(operation: "send"))
            }
            offset += count
        }
    }

    private static func makeListeningSocket(host: String, port: UInt16) throws -> Int32 {
        var hints = addrinfo(
            ai_flags: AI_NUMERICHOST | AI_NUMERICSERV | AI_PASSIVE,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, String(port), &hints, &result)
        guard status == 0, let result else {
            throw AppServerWebSocketTransportError.socket("getaddrinfo failed: \(String(cString: gai_strerror(status)))")
        }
        defer { freeaddrinfo(result) }

        var lastError = posixMessage(operation: "socket")
        var cursor: UnsafeMutablePointer<addrinfo>? = result
        while let info = cursor {
            let fd = Darwin.socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
            if fd < 0 {
                lastError = posixMessage(operation: "socket")
                cursor = info.pointee.ai_next
                continue
            }
            var reuse: Int32 = 1
            _ = withUnsafePointer(to: &reuse) {
                Darwin.setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, $0, socklen_t(MemoryLayout<Int32>.size))
            }
            if Darwin.bind(fd, info.pointee.ai_addr, info.pointee.ai_addrlen) == 0,
               Darwin.listen(fd, SOMAXCONN) == 0 {
                return fd
            }
            lastError = posixMessage(operation: "bind")
            Darwin.close(fd)
            cursor = info.pointee.ai_next
        }
        throw AppServerWebSocketTransportError.socket(lastError)
    }

    private static func makeUnixListeningSocket(socketPath: String) throws -> Int32 {
        try prepareUnixSocketPath(socketPath)

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw AppServerWebSocketTransportError.socket(posixMessage(operation: "socket"))
        }

        do {
            var address = try unixSocketAddress(path: socketPath)
            let bindResult = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    Darwin.bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard bindResult == 0 else {
                throw AppServerWebSocketTransportError.socket(posixMessage(operation: "bind"))
            }
            guard Darwin.chmod(socketPath, 0o600) == 0 else {
                throw AppServerWebSocketTransportError.socket(posixMessage(operation: "chmod"))
            }
            guard Darwin.listen(fd, SOMAXCONN) == 0 else {
                throw AppServerWebSocketTransportError.socket(posixMessage(operation: "listen"))
            }
            return fd
        } catch {
            Darwin.close(fd)
            _ = try? FileManager.default.removeItem(atPath: socketPath)
            throw error
        }
    }

    private static func prepareUnixSocketPath(_ socketPath: String) throws {
        let fileManager = FileManager.default
        let parent = URL(fileURLWithPath: socketPath).deletingLastPathComponent()
        try fileManager.createDirectory(
            at: parent,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard Darwin.chmod(parent.path, 0o700) == 0 else {
            throw AppServerWebSocketTransportError.socket(posixMessage(operation: "chmod"))
        }

        let probe = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard probe >= 0 else {
            throw AppServerWebSocketTransportError.socket(posixMessage(operation: "socket"))
        }
        defer { Darwin.close(probe) }

        var address = try unixSocketAddress(path: socketPath)
        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(probe, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if connectResult == 0 {
            throw AppServerWebSocketTransportError.socket(
                "app-server control socket is already in use at \(socketPath)"
            )
        }
        let connectErrno = errno
        if connectErrno == ENOENT {
            return
        }
        guard connectErrno == ECONNREFUSED else {
            if !fileManager.fileExists(atPath: socketPath) {
                return
            }
            throw AppServerWebSocketTransportError.socket(posixMessage(operation: "connect", errno: connectErrno))
        }

        var status = stat()
        if Darwin.lstat(socketPath, &status) != 0 {
            if errno == ENOENT {
                return
            }
            throw AppServerWebSocketTransportError.socket(posixMessage(operation: "lstat"))
        }
        guard (status.st_mode & S_IFMT) == S_IFSOCK else {
            throw AppServerWebSocketTransportError.socket(
                "app-server control socket path exists and is not a socket: \(socketPath)"
            )
        }
        try fileManager.removeItem(atPath: socketPath)
    }

    private static func unixSocketAddress(path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        #if os(macOS)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        #endif
        address.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count < capacity else {
            throw AppServerWebSocketTransportError.socket("socket path is too long: \(path)")
        }

        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { buffer in
                for index in 0..<capacity {
                    buffer[index] = 0
                }
                for (index, byte) in pathBytes.enumerated() {
                    buffer[index] = CChar(bitPattern: byte)
                }
            }
        }

        return address
    }

    private static func localPort(for fileDescriptor: Int32) throws -> UInt16 {
        var storage = sockaddr_storage()
        var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let result = withUnsafeMutablePointer(to: &storage) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(fileDescriptor, $0, &length)
            }
        }
        guard result == 0 else {
            throw AppServerWebSocketTransportError.socket(posixMessage(operation: "getsockname"))
        }
        if storage.ss_family == sa_family_t(AF_INET) {
            return withUnsafePointer(to: &storage) {
                $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    UInt16(bigEndian: $0.pointee.sin_port)
                }
            }
        }
        return withUnsafePointer(to: &storage) {
            $0.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                UInt16(bigEndian: $0.pointee.sin6_port)
            }
        }
    }

    private static func displayHost(_ host: String) -> String {
        host.contains(":") ? "[\(host)]" : host
    }

    private static func posixMessage(operation: String) -> String {
        posixMessage(operation: operation, errno: errno)
    }

    private static func posixMessage(operation: String, errno: Int32) -> String {
        "\(operation) failed: \(String(cString: strerror(errno)))"
    }
}

private actor AppServerConnectionIDAllocator {
    private var next: AppServerConnectionID = 1

    func allocate() -> AppServerConnectionID {
        defer {
            next += 1
        }
        return next
    }
}

private actor AppServerWebSocketFrameWriter {
    private let fileDescriptor: Int32

    init(fileDescriptor: Int32) {
        self.fileDescriptor = fileDescriptor
    }

    func writeText(_ text: String) throws {
        try AppServerWebSocketTransport.writeFrame(
            fileDescriptor: fileDescriptor,
            opcode: .text,
            payload: Array(text.utf8),
            masked: false
        )
    }

    func writePong(payload: [UInt8]) throws {
        try AppServerWebSocketTransport.writeFrame(
            fileDescriptor: fileDescriptor,
            opcode: .pong,
            payload: payload,
            masked: false
        )
    }
}
