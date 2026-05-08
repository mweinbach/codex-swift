import Darwin
import Foundation

public struct StdioToUDSError: Error, CustomStringConvertible, Sendable {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}

public enum StdioToUDS {
    public static func run(
        socketPath: String,
        input: FileHandle = .standardInput,
        output: FileHandle = .standardOutput
    ) throws {
        let socketFD = try connectUnixStream(socketPath: socketPath)
        defer { close(socketFD) }

        let readerFD = dup(socketFD)
        guard readerFD >= 0 else {
            throw StdioToUDSError("failed to clone socket for reading: \(posixErrorMessage())")
        }

        let result = ThreadResultBox()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            defer {
                close(readerFD)
                done.signal()
            }
            do {
                try copy(from: FileHandle(fileDescriptor: readerFD, closeOnDealloc: false), to: output)
                result.set(.success(()))
            } catch {
                result.set(.failure(StdioToUDSError("failed to copy data from socket to stdout: \(error)")))
            }
        }

        do {
            try copy(from: input, to: FileHandle(fileDescriptor: socketFD, closeOnDealloc: false))
        } catch {
            throw StdioToUDSError("failed to copy data from stdin to socket: \(error)")
        }

        guard shutdown(socketFD, SHUT_WR) == 0 else {
            throw StdioToUDSError("failed to shutdown socket writer: \(posixErrorMessage())")
        }

        done.wait()
        switch result.value {
        case .success:
            return
        case let .failure(error):
            throw error
        case nil:
            throw StdioToUDSError("thread panicked while copying socket data to stdout")
        }
    }
}

private final class ThreadResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Result<Void, Error>?

    var value: Result<Void, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ result: Result<Void, Error>) {
        lock.lock()
        stored = result
        lock.unlock()
    }
}

private func connectUnixStream(socketPath: String) throws -> Int32 {
    let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
    guard socketFD >= 0 else {
        throw StdioToUDSError("failed to create unix socket: \(posixErrorMessage())")
    }

    do {
        var address = try unixSocketAddress(path: socketPath)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                connect(socketFD, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            throw StdioToUDSError("failed to connect to socket at \(socketPath): \(posixErrorMessage())")
        }
        return socketFD
    } catch {
        close(socketFD)
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
        throw StdioToUDSError("socket path is too long: \(path)")
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

private func copy(from source: FileHandle, to destination: FileHandle) throws {
    while true {
        let data = try source.read(upToCount: 64 * 1024) ?? Data()
        if data.isEmpty {
            return
        }
        try destination.write(contentsOf: data)
    }
}

private func posixErrorMessage() -> String {
    String(cString: strerror(errno))
}
