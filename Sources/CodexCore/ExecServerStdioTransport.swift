import Foundation

public struct ExecServerStdioTransport: Sendable {
    public typealias WriteLine = @Sendable (Data) async throws -> Void

    private let server: ExecServerLineServer

    public init(server: ExecServerLineServer = ExecServerLineServer()) {
        self.server = server
    }

    public func run<Lines: AsyncSequence>(
        lines: Lines,
        writeLine: @escaping WriteLine
    ) async throws where Lines.Element == String {
        let writer = ExecServerStdioWriter(writeLine: writeLine)
        let outboundTask = Task {
            while !Task.isCancelled {
                guard let line = try await server.nextQueuedLine() else {
                    break
                }
                try await writer.write(line)
            }
        }

        do {
            for try await line in lines {
                let responseLines = try await server.receiveLine(line, drainMode: .directOnly)
                for responseLine in responseLines {
                    try await writer.write(responseLine)
                }
            }
            let disconnectLines = try await server.disconnect()
            for line in disconnectLines {
                try await writer.write(line)
            }
            try await outboundTask.value
        } catch {
            outboundTask.cancel()
            _ = try? await server.disconnect()
            throw error
        }
    }
}

private actor ExecServerStdioWriter {
    private let writeLine: ExecServerStdioTransport.WriteLine

    init(writeLine: @escaping ExecServerStdioTransport.WriteLine) {
        self.writeLine = writeLine
    }

    func write(_ line: Data) async throws {
        try await writeLine(line)
    }
}
