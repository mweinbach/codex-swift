@testable import CodexResponsesAPIProxy
import Darwin
import Foundation
import XCTest

final class ResponsesAPIProxyTests: XCTestCase {
    func testAuthHeaderReaderReadsKeyWithNoNewline() throws {
        var sent = false
        let header = try ResponsesAPIProxyAuth.readAuthHeader { buffer in
            guard !sent else {
                return 0
            }
            write(Array("sk-abc123".utf8), into: buffer)
            sent = true
            return "sk-abc123".utf8.count
        }

        XCTAssertEqual(header, "Bearer sk-abc123")
    }

    func testAuthHeaderReaderHandlesShortReadsAndTrimsNewlines() throws {
        var chunks = [
            Array("sk-".utf8),
            Array("abc".utf8),
            Array("123\r\n".utf8)
        ]

        let header = try ResponsesAPIProxyAuth.readAuthHeader { buffer in
            guard !chunks.isEmpty else {
                return 0
            }
            let chunk = chunks.removeFirst()
            write(chunk, into: buffer)
            return chunk.count
        }

        XCTAssertEqual(header, "Bearer sk-abc123")
    }

    func testAuthHeaderReaderRejectsMissingOversizedAndInvalidKeys() {
        XCTAssertThrowsError(try ResponsesAPIProxyAuth.readAuthHeader { _ in 0 }) { error in
            XCTAssertEqual(error as? ResponsesAPIProxyError, .apiKeyMissing)
        }

        XCTAssertThrowsError(try ResponsesAPIProxyAuth.readAuthHeader { buffer in
            let data = Array(repeating: UInt8(ascii: "a"), count: buffer.count)
            write(data, into: buffer)
            return data.count
        }) { error in
            XCTAssertEqual(error as? ResponsesAPIProxyError, .apiKeyTooLarge(ResponsesAPIProxyAuth.bufferSize))
        }

        var sentInvalidKey = false
        XCTAssertThrowsError(try ResponsesAPIProxyAuth.readAuthHeader { buffer in
            guard !sentInvalidKey else {
                return 0
            }
            let data = Array("sk-abc!23".utf8)
            write(data, into: buffer)
            sentInvalidKey = true
            return data.count
        }) { error in
            XCTAssertEqual(error as? ResponsesAPIProxyError, .invalidAPIKeyCharacters)
        }
    }

    func testWriteServerInfoCreatesParentAndWritesRustShape() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let path = tempDir.appendingPathComponent("nested/server.json")

        try ResponsesAPIProxy.writeServerInfo(path: path, port: 3456, pid: 99)

        let data = try String(contentsOf: path, encoding: .utf8)
        XCTAssertEqual(data, #"{"port":3456,"pid":99}"# + "\n")
    }

    func testProxyStreamsUpstreamBodyBeforeUpstreamCompletes() throws {
        let secondChunkGate = DispatchSemaphore(value: 0)
        let upstream = try StreamingUpstreamServer(secondChunkGate: secondChunkGate)
        defer { upstream.stop() }

        let proxy = try ResponsesAPIProxyServer(
            options: ResponsesAPIProxyOptions(
                upstreamURL: "http://127.0.0.1:\(upstream.port)/upstream"
            ),
            authHeader: "Bearer sk-test"
        )
        defer { proxy.stop() }

        let proxyFinished = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            _ = try? proxy.serveForever()
            proxyFinished.signal()
        }

        let client = try connectToLocalhost(port: proxy.port)
        defer { Darwin.close(client) }
        try setReceiveTimeout(fd: client, seconds: 1)

        let request = """
        POST /v1/responses HTTP/1.1\r
        Host: 127.0.0.1:\(proxy.port)\r
        Authorization: Bearer incoming\r
        X-Test: kept\r
        Content-Length: 2\r
        \r
        {}
        """
        XCTAssertTrue(sendAll(fd: client, data: Data(request.utf8)))

        let firstBytes = try readUntil(fd: client, contains: Data("one\n".utf8))
        let firstText = String(decoding: firstBytes, as: UTF8.self)
        XCTAssertTrue(firstText.hasPrefix("HTTP/1.1 200"))
        XCTAssertTrue(firstText.contains("Content-Type: text/event-stream"))
        XCTAssertFalse(firstText.localizedCaseInsensitiveContains("Content-Length:"))
        XCTAssertTrue(firstText.hasSuffix("one\n"))

        secondChunkGate.signal()
        let remainder = try readUntilEOF(fd: client)
        XCTAssertEqual(String(decoding: remainder, as: UTF8.self), "two\n")

        XCTAssertEqual(upstream.recordedAuthorization, "Bearer sk-test")
        XCTAssertEqual(upstream.recordedXTest, "kept")

        proxy.stop()
        _ = proxyFinished.wait(timeout: .now() + 1)
    }

    private func write(_ bytes: [UInt8], into buffer: UnsafeMutableBufferPointer<UInt8>) {
        for index in bytes.indices {
            buffer[index] = bytes[index]
        }
    }
}

private final class StreamingUpstreamServer: @unchecked Sendable {
    let port: UInt16

    private let listenerFD: Int32
    private let secondChunkGate: DispatchSemaphore
    private let lock = NSLock()
    private var stopped = false
    private var headers: [String: String] = [:]

    var recordedAuthorization: String? {
        header("authorization")
    }

    var recordedXTest: String? {
        header("x-test")
    }

    init(secondChunkGate: DispatchSemaphore) throws {
        self.secondChunkGate = secondChunkGate
        let listener = try makeListeningSocket()
        self.listenerFD = listener.fd
        self.port = listener.port

        Thread.detachNewThread { [weak self] in
            self?.serveOneRequest()
        }
    }

    func stop() {
        lock.lock()
        let shouldClose = !stopped
        stopped = true
        lock.unlock()

        if shouldClose {
            Darwin.shutdown(listenerFD, SHUT_RDWR)
            Darwin.close(listenerFD)
        }
    }

    private func serveOneRequest() {
        let clientFD = Darwin.accept(listenerFD, nil, nil)
        guard clientFD >= 0 else {
            return
        }
        defer {
            Darwin.close(clientFD)
            stop()
        }

        guard let request = try? readHTTPRequest(fd: clientFD) else {
            return
        }
        recordHeaders(request.headers)

        let responseHead = """
        HTTP/1.1 200 OK\r
        Content-Type: text/event-stream\r
        Connection: close\r
        \r
        one\n
        """
        _ = sendAll(fd: clientFD, data: Data(responseHead.utf8))
        _ = secondChunkGate.wait(timeout: .now() + 5)
        _ = sendAll(fd: clientFD, data: Data("two\n".utf8))
    }

    private func recordHeaders(_ headers: [String: String]) {
        lock.lock()
        self.headers = headers
        lock.unlock()
    }

    private func header(_ name: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return headers[name]
    }
}

private struct TestHTTPRequest {
    let headers: [String: String]
}

private enum SocketTestError: Error {
    case socket(String)
    case timeout
    case closed
    case invalidResponse
}

private func makeListeningSocket() throws -> (fd: Int32, port: UInt16) {
    let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else {
        throw SocketTestError.socket(String(cString: strerror(errno)))
    }

    var reuse: Int32 = 1
    _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.stride))

    var addr = sockaddr_in()
    addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = 0
    addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

    let bindResult = withUnsafePointer(to: &addr) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
            Darwin.bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.stride))
        }
    }
    guard bindResult == 0 else {
        let message = String(cString: strerror(errno))
        Darwin.close(fd)
        throw SocketTestError.socket(message)
    }

    guard Darwin.listen(fd, SOMAXCONN) == 0 else {
        let message = String(cString: strerror(errno))
        Darwin.close(fd)
        throw SocketTestError.socket(message)
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
        throw SocketTestError.socket(message)
    }

    return (fd, UInt16(bigEndian: bound.sin_port))
}

private func connectToLocalhost(port: UInt16) throws -> Int32 {
    let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else {
        throw SocketTestError.socket(String(cString: strerror(errno)))
    }

    var addr = sockaddr_in()
    addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = port.bigEndian
    addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

    let connectResult = withUnsafePointer(to: &addr) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
            Darwin.connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.stride))
        }
    }
    guard connectResult == 0 else {
        let message = String(cString: strerror(errno))
        Darwin.close(fd)
        throw SocketTestError.socket(message)
    }

    return fd
}

private func setReceiveTimeout(fd: Int32, seconds: Int) throws {
    var timeout = timeval(tv_sec: seconds, tv_usec: 0)
    let result = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.stride))
    guard result == 0 else {
        throw SocketTestError.socket(String(cString: strerror(errno)))
    }
}

private func readHTTPRequest(fd: Int32) throws -> TestHTTPRequest {
    let data = try readUntil(fd: fd, contains: Data([13, 10, 13, 10]))
    guard let range = data.range(of: Data([13, 10, 13, 10])) else {
        throw SocketTestError.invalidResponse
    }

    let headerText = String(decoding: data[..<range.lowerBound], as: UTF8.self)
    var headers: [String: String] = [:]
    for line in headerText.components(separatedBy: "\r\n").dropFirst() {
        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            continue
        }
        headers[String(parts[0]).lowercased()] = parts[1].trimmingCharacters(in: .whitespaces)
    }
    return TestHTTPRequest(headers: headers)
}

private func readUntil(fd: Int32, contains marker: Data) throws -> Data {
    var data = Data()
    while data.range(of: marker) == nil {
        var buffer = [UInt8](repeating: 0, count: 4_096)
        let readCount = buffer.withUnsafeMutableBytes { rawBuffer in
            Darwin.recv(fd, rawBuffer.baseAddress, rawBuffer.count, 0)
        }
        if readCount == 0 {
            throw SocketTestError.closed
        }
        if readCount < 0 {
            if errno == EWOULDBLOCK || errno == EAGAIN {
                throw SocketTestError.timeout
            }
            if errno == EINTR {
                continue
            }
            throw SocketTestError.socket(String(cString: strerror(errno)))
        }
        data.append(buffer, count: readCount)
    }
    return data
}

private func readUntilEOF(fd: Int32) throws -> Data {
    var data = Data()
    while true {
        var buffer = [UInt8](repeating: 0, count: 4_096)
        let readCount = buffer.withUnsafeMutableBytes { rawBuffer in
            Darwin.recv(fd, rawBuffer.baseAddress, rawBuffer.count, 0)
        }
        if readCount == 0 {
            return data
        }
        if readCount < 0 {
            if errno == EWOULDBLOCK || errno == EAGAIN {
                throw SocketTestError.timeout
            }
            if errno == EINTR {
                continue
            }
            throw SocketTestError.socket(String(cString: strerror(errno)))
        }
        data.append(buffer, count: readCount)
    }
}

@discardableResult
private func sendAll(fd: Int32, data: Data) -> Bool {
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
