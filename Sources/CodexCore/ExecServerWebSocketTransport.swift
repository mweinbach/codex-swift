import CryptoKit
import Darwin
import Foundation

public enum ExecServerWebSocketTransportError: Error, CustomStringConvertible, Equatable, Sendable {
    case socket(String)
    case invalidHandshake
    case unsupportedFrame(String)
    case closed

    public var description: String {
        switch self {
        case let .socket(message):
            return message
        case .invalidHandshake:
            return "invalid exec-server websocket handshake"
        case let .unsupportedFrame(message):
            return message
        case .closed:
            return "exec-server websocket connection closed"
        }
    }
}

public struct ExecServerWebSocketTransport: Sendable {
    public typealias Announce = @Sendable (String) async throws -> Void

    private let processor: ExecServerConnectionProcessor

    public init(processor: ExecServerConnectionProcessor = ExecServerConnectionProcessor()) {
        self.processor = processor
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
                throw ExecServerWebSocketTransportError.socket(Self.posixMessage(operation: "poll"))
            }
            var peer = sockaddr_storage()
            var peerLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let clientFD = withUnsafeMutablePointer(to: &peer) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.accept(listenFD, $0, &peerLength)
                }
            }
            guard clientFD >= 0 else {
                if errno == EINTR {
                    continue
                }
                throw ExecServerWebSocketTransportError.socket(Self.posixMessage(operation: "accept"))
            }

            let connectionLabel = "exec-server websocket \(Self.peerDescription(peer, length: peerLength))"
            let processor = processor
            Task.detached {
                let connection = await processor.makeConnection()
                try? await Self.runConnectedClient(
                    fileDescriptor: clientFD,
                    connection: connection,
                    connectionLabel: connectionLabel
                )
            }
        }
    }

    private static func runConnectedClient(
        fileDescriptor: Int32,
        connection: ExecServerConnection = ExecServerConnection(),
        connectionLabel: String = "exec-server websocket peer"
    ) async throws {
        defer {
            Darwin.shutdown(fileDescriptor, SHUT_RDWR)
            Darwin.close(fileDescriptor)
        }

        try performHandshake(fileDescriptor: fileDescriptor)
        let writer = ExecServerWebSocketFrameWriter(fileDescriptor: fileDescriptor)

        let outboundTask = Task {
            while !Task.isCancelled {
                guard let outbound = await connection.waitForOutbound() else {
                    break
                }
                try await writer.writeText(ExecServerJSONRPCCodec.encodeWebSocketText(outbound.jsonRPCMessage))
            }
        }

        do {
            while !Task.isCancelled {
                let frame = try readFrame(fileDescriptor: fileDescriptor)
                switch frame.opcode {
                case .text:
                    let text = String(decoding: frame.payload, as: UTF8.self)
                    if let outbound = await connection.handleWebSocketText(text, connectionLabel: connectionLabel) {
                        try await writer.writeText(ExecServerJSONRPCCodec.encodeWebSocketText(outbound.jsonRPCMessage))
                    }
                case .binary:
                    if let outbound = await connection.handleWebSocketBinary(
                        Data(frame.payload),
                        connectionLabel: connectionLabel
                    ) {
                        try await writer.writeText(ExecServerJSONRPCCodec.encodeWebSocketText(outbound.jsonRPCMessage))
                    }
                case .close:
                    _ = await connection.handle(.disconnected(reason: nil))
                    outboundTask.cancel()
                    return
                case .ping:
                    try await writer.writePong(payload: frame.payload)
                case .pong:
                    continue
                }
            }
        } catch ExecServerWebSocketTransportError.closed {
            _ = await connection.handle(.disconnected(reason: nil))
        } catch {
            outboundTask.cancel()
            _ = await connection.handle(.disconnected(reason: nil))
            throw error
        }

        outboundTask.cancel()
        try? await outboundTask.value
    }

    private static func performHandshake(fileDescriptor: Int32) throws {
        let request = try readHTTPRequest(fileDescriptor: fileDescriptor)
        let lines = request.components(separatedBy: "\r\n")
        guard lines.first?.hasPrefix("GET ") == true else {
            throw ExecServerWebSocketTransportError.invalidHandshake
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

        guard headers["upgrade"]?.lowercased() == "websocket",
              headers["connection"]?.lowercased().contains("upgrade") == true,
              let key = headers["sec-websocket-key"],
              headers["sec-websocket-version"] == "13"
        else {
            throw ExecServerWebSocketTransportError.invalidHandshake
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

    private static func readHTTPRequest(fileDescriptor: Int32) throws -> String {
        var bytes: [UInt8] = []
        while !bytes.suffix(4).elementsEqual([13, 10, 13, 10]) {
            guard bytes.count < 16 * 1024 else {
                throw ExecServerWebSocketTransportError.invalidHandshake
            }
            bytes.append(contentsOf: try readExact(fileDescriptor: fileDescriptor, byteCount: 1))
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func websocketAcceptKey(for key: String) -> String {
        let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let digest = Insecure.SHA1.hash(data: Data((key + magic).utf8))
        return Data(digest).base64EncodedString()
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
            throw ExecServerWebSocketTransportError.unsupportedFrame(
                "fragmented exec-server websocket frames are not supported"
            )
        }
        guard let opcode = WebSocketOpcode(rawValue: header[0] & 0x0F) else {
            throw ExecServerWebSocketTransportError.unsupportedFrame("unsupported exec-server websocket opcode")
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
            throw ExecServerWebSocketTransportError.unsupportedFrame("exec-server websocket frame is too large")
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
                throw ExecServerWebSocketTransportError.closed
            }
            guard count > 0 else {
                if errno == EINTR {
                    continue
                }
                throw ExecServerWebSocketTransportError.socket(posixMessage(operation: "recv"))
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
                throw ExecServerWebSocketTransportError.socket(posixMessage(operation: "send"))
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
            throw ExecServerWebSocketTransportError.socket("getaddrinfo failed: \(String(cString: gai_strerror(status)))")
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
        throw ExecServerWebSocketTransportError.socket(lastError)
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
            throw ExecServerWebSocketTransportError.socket(posixMessage(operation: "getsockname"))
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

    private static func peerDescription(_ storage: sockaddr_storage, length: socklen_t) -> String {
        var storage = storage
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        var service = [CChar](repeating: 0, count: Int(NI_MAXSERV))
        let status = withUnsafePointer(to: &storage) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getnameinfo($0, length, &host, socklen_t(host.count), &service, socklen_t(service.count), NI_NUMERICHOST | NI_NUMERICSERV)
            }
        }
        guard status == 0 else {
            return "peer"
        }
        let hostString = stringFromNullTerminated(host)
        let serviceString = stringFromNullTerminated(service)
        if hostString.contains(":") {
            return "[\(hostString)]:\(serviceString)"
        }
        return "\(hostString):\(serviceString)"
    }

    private static func displayHost(_ host: String) -> String {
        host.contains(":") ? "[\(host)]" : host
    }

    private static func stringFromNullTerminated(_ bytes: [CChar]) -> String {
        let end = bytes.firstIndex(of: 0) ?? bytes.endIndex
        return String(decoding: bytes[..<end].map(UInt8.init(bitPattern:)), as: UTF8.self)
    }

    private static func posixMessage(operation: String) -> String {
        "\(operation) failed: \(String(cString: strerror(errno)))"
    }
}

private actor ExecServerWebSocketFrameWriter {
    private let fileDescriptor: Int32

    init(fileDescriptor: Int32) {
        self.fileDescriptor = fileDescriptor
    }

    func writeText(_ text: String) throws {
        try ExecServerWebSocketTransport.writeFrame(
            fileDescriptor: fileDescriptor,
            opcode: .text,
            payload: Array(text.utf8),
            masked: false
        )
    }

    func writePong(payload: [UInt8]) throws {
        try ExecServerWebSocketTransport.writeFrame(
            fileDescriptor: fileDescriptor,
            opcode: .pong,
            payload: payload,
            masked: false
        )
    }
}
