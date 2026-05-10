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
        var inputTasks: [Task<Void, Error>] = []
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
                guard let event = ExecServerJSONRPCCodec.stdioEvent(fromLine: line, connectionLabel: "exec-server stdio") else {
                    continue
                }
                let server = server
                let writer = writer
                switch event {
                case let .message(.request(request)) where request.method != execServerInitializeMethod:
                    inputTasks.append(Task {
                        let responseLines = try await server.receiveEvent(event, drainMode: .directOnly)
                        for responseLine in responseLines {
                            try await writer.write(responseLine)
                        }
                    })
                    inputTasks.removeAll { $0.isCancelled }
                default:
                    let responseLines = try await server.receiveEvent(event, drainMode: .directOnly)
                    for responseLine in responseLines {
                        try await writer.write(responseLine)
                    }
                }
            }
            let disconnectLines = try await server.disconnect()
            for line in disconnectLines {
                try await writer.write(line)
            }
            for task in inputTasks {
                do {
                    try await task.value
                } catch is CancellationError {
                    continue
                }
            }
            try await outboundTask.value
        } catch {
            outboundTask.cancel()
            for task in inputTasks {
                task.cancel()
            }
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
