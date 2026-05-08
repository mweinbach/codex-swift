import CodexStdioToUDS
import Darwin
import Foundation
import XCTest

final class StdioToUDSTests: XCTestCase {
    func testPipesInputAndOutputThroughUnixSocket() throws {
        let socketPath = "/tmp/codex-stdio-\(UUID().uuidString.prefix(8)).sock"
        unlink(socketPath)
        defer { unlink(socketPath) }

        let listener = try bindUnixListener(path: socketPath)
        let server = ServerResultBox()
        let done = DispatchSemaphore(value: 0)

        DispatchQueue.global(qos: .userInitiated).async {
            defer {
                close(listener)
                done.signal()
            }
            do {
                let connection = accept(listener, nil, nil)
                guard connection >= 0 else {
                    throw TestSocketError("failed to accept test connection: \(posixErrorMessage())")
                }
                defer { close(connection) }

                let received = try readExactly(Data("request".utf8).count, from: connection)
                try expectEOF(from: connection)
                try writeAll(Data("response".utf8), to: connection)
                server.set(.success(received))
            } catch {
                server.set(.failure(error))
            }
        }

        let input = Pipe()
        let output = Pipe()
        try input.fileHandleForWriting.write(contentsOf: Data("request".utf8))
        try input.fileHandleForWriting.close()

        try StdioToUDS.run(
            socketPath: socketPath,
            input: input.fileHandleForReading,
            output: output.fileHandleForWriting
        )
        try output.fileHandleForWriting.close()

        XCTAssertEqual(output.fileHandleForReading.readDataToEndOfFile(), Data("response".utf8))
        XCTAssertEqual(done.wait(timeout: .now() + 1), .success)

        switch server.value {
        case let .success(received):
            XCTAssertEqual(received, Data("request".utf8))
        case let .failure(error):
            XCTFail("server failed: \(error)")
        case nil:
            XCTFail("server did not report a result")
        }
    }

    func testMissingSocketReportsConnectContext() {
        XCTAssertThrowsError(try StdioToUDS.run(socketPath: "/tmp/codex-stdio-missing.sock")) { error in
            XCTAssertTrue(String(describing: error).contains("failed to connect to socket at /tmp/codex-stdio-missing.sock"))
        }
    }
}

private final class ServerResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Result<Data, Error>?

    var value: Result<Data, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ result: Result<Data, Error>) {
        lock.lock()
        stored = result
        lock.unlock()
    }
}

private struct TestSocketError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private func bindUnixListener(path: String) throws -> Int32 {
    let listener = socket(AF_UNIX, SOCK_STREAM, 0)
    guard listener >= 0 else {
        throw TestSocketError("failed to create test listener: \(posixErrorMessage())")
    }

    do {
        var address = try unixSocketAddress(path: path)
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(listener, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            throw TestSocketError("failed to bind test listener: \(posixErrorMessage())")
        }

        guard listen(listener, 1) == 0 else {
            throw TestSocketError("failed to listen on test socket: \(posixErrorMessage())")
        }
        return listener
    } catch {
        close(listener)
        throw error
    }
}

private func unixSocketAddress(path: String) throws -> sockaddr_un {
    var address = sockaddr_un()
    #if os(macOS)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    #endif
    address.sun_family = sa_family_t(AF_UNIX)

    let pathBytes = Array(path.utf8)
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    guard pathBytes.count < capacity else {
        throw TestSocketError("socket path is too long: \(path)")
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

private func readExactly(_ byteCount: Int, from fileDescriptor: Int32) throws -> Data {
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while data.count < byteCount {
        try waitForReadable(fileDescriptor)

        let remaining = min(buffer.count, byteCount - data.count)
        let count = Darwin.read(fileDescriptor, &buffer, remaining)
        guard count != 0 else {
            throw TestSocketError("test socket closed after \(data.count) of \(byteCount) request bytes")
        }
        guard count > 0 else {
            if errno == EINTR {
                continue
            }
            throw TestSocketError("failed to read from test socket: \(posixErrorMessage())")
        }
        data.append(buffer, count: count)
    }
    return data
}

private func expectEOF(from fileDescriptor: Int32) throws {
    try waitForReadable(fileDescriptor)

    var byte: UInt8 = 0
    let count = Darwin.read(fileDescriptor, &byte, 1)
    if count == 0 {
        return
    }
    guard count > 0 else {
        throw TestSocketError("failed to read client shutdown from test socket: \(posixErrorMessage())")
    }
    throw TestSocketError("expected client write side to close after request")
}

private func waitForReadable(_ fileDescriptor: Int32) throws {
    var descriptor = pollfd(
        fd: fileDescriptor,
        events: Int16(POLLIN) | Int16(POLLHUP) | Int16(POLLERR),
        revents: 0
    )
    while true {
        let result = Darwin.poll(&descriptor, 1, 1_000)
        if result > 0 {
            if descriptor.revents & Int16(POLLERR) != 0 {
                throw TestSocketError("test socket reported poll error")
            }
            return
        }
        if result == 0 {
            throw TestSocketError("timed out waiting for test socket data")
        }
        if errno == EINTR {
            continue
        }
        throw TestSocketError("failed to poll test socket: \(posixErrorMessage())")
    }
}

private func writeAll(_ data: Data, to fileDescriptor: Int32) throws {
    try data.withUnsafeBytes { rawBuffer in
        guard let baseAddress = rawBuffer.baseAddress else { return }
        var remaining = data.count
        var offset = 0
        while remaining > 0 {
            let written = Darwin.write(fileDescriptor, baseAddress.advanced(by: offset), remaining)
            guard written > 0 else {
                throw TestSocketError("failed to write to test socket: \(posixErrorMessage())")
            }
            remaining -= written
            offset += written
        }
    }
}

private func posixErrorMessage() -> String {
    String(cString: strerror(errno))
}
