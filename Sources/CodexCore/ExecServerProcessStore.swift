import Foundation

public actor ExecServerProcessStore {
    public typealias OutboundNotification = @Sendable (ExecServerJSONRPCNotification) async -> Void

    private static let retainedOutputBytesPerProcess = 1024 * 1024
    private var outboundNotification: OutboundNotification
    private let retentionDelayNanoseconds: UInt64
    private var processes: [String: ExecServerProcessState] = [:]

    public init(
        retentionDelayNanoseconds: UInt64 = 30_000_000_000,
        outboundNotification: @escaping OutboundNotification = { _ in }
    ) {
        self.retentionDelayNanoseconds = retentionDelayNanoseconds
        self.outboundNotification = outboundNotification
    }

    public func setOutboundNotification(_ outboundNotification: @escaping OutboundNotification) {
        self.outboundNotification = outboundNotification
    }

    public func shutdown() {
        for process in processes.values {
            if process.process.isRunning {
                process.process.terminate()
            }
            process.pseudoTerminal?.closeSlaveHandles()
            closeStdin(process)
        }
        processes.removeAll()
    }

    public func start(_ params: ExecServerExecParams) async throws -> ExecServerExecResponse {
        guard let program = params.argv.first else {
            throw ExecServerRPC.invalidParams("argv must not be empty")
        }
        guard processes[params.processId] == nil else {
            throw ExecServerRPC.invalidRequest("process \(params.processId) already exists")
        }
        let process = Process()
        if program.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: program)
            process.arguments = Array(params.argv.dropFirst())
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = params.argv
        }
        process.currentDirectoryURL = URL(fileURLWithPath: params.cwd)
        process.environment = childEnvironment(params)

        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = Pipe()
        let pseudoTerminal: ExecServerPseudoTerminal?
        let stdoutHandle: FileHandle
        let stderrHandle: FileHandle
        let stdinHandle: FileHandle?
        if params.tty {
            let pty = try ExecServerPseudoTerminal()
            pseudoTerminal = pty
            process.standardInput = pty.stdinHandle
            process.standardOutput = pty.stdoutHandle
            process.standardError = pty.stderrHandle
            stdoutHandle = pty.master
            stderrHandle = pty.master
            stdinHandle = pty.master
        } else {
            pseudoTerminal = nil
            process.standardOutput = stdout
            process.standardError = stderr
            process.standardInput = stdin
            stdoutHandle = stdout.fileHandleForReading
            stderrHandle = stderr.fileHandleForReading
            stdinHandle = params.pipeStdin ? stdin.fileHandleForWriting : nil
        }

        let state = ExecServerProcessState(
            process: process,
            stdout: stdoutHandle,
            stderr: stderrHandle,
            stdin: stdinHandle,
            tty: params.tty,
            pipeStdin: params.pipeStdin,
            pseudoTerminal: pseudoTerminal
        )
        processes[params.processId] = state

        stdoutHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { await self?.handleOutput(data, processId: params.processId, stream: params.tty ? .pty : .stdout) }
        }
        if !params.tty {
            stderrHandle.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                Task { await self?.handleOutput(data, processId: params.processId, stream: .stderr) }
            }
        }
        process.terminationHandler = { [weak self] process in
            Task { await self?.handleExit(processId: params.processId, exitCode: process.terminationStatus) }
        }

        do {
            try process.run()
            pseudoTerminal?.closeSlaveHandles()
            if !params.tty && !params.pipeStdin {
                closeStdin(state)
            }
            return ExecServerExecResponse(processId: params.processId)
        } catch {
            processes.removeValue(forKey: params.processId)
            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil
            pseudoTerminal?.closeSlaveHandles()
            closeStdin(state)
            throw ExecServerRPC.internalError(error.localizedDescription)
        }
    }

    public func read(_ params: ExecServerReadParams) async throws -> ExecServerReadResponse {
        let afterSeq = params.afterSeq ?? 0
        let maxBytes = params.maxBytes ?? Int.max
        let waitMilliseconds = params.waitMs ?? 0
        let deadline = Date().addingTimeInterval(TimeInterval(waitMilliseconds) / 1000)

        while true {
            let state = try runningProcess(id: params.processId)
            let response = readResponse(from: state, afterSeq: afterSeq, maxBytes: maxBytes)
            let hasNewTerminalEvent = response.exited && afterSeq < response.nextSeq.saturatingSubtracting(1)
            if !response.chunks.isEmpty || response.closed || hasNewTerminalEvent || Date() >= deadline {
                return response
            }
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 {
                return response
            }
            try await Task.sleep(nanoseconds: min(UInt64(remaining * 1_000_000_000), 10_000_000))
        }
    }

    public func write(_ params: ExecServerWriteParams) async throws -> ExecServerWriteResponse {
        guard let state = processes[params.processId] else {
            return ExecServerWriteResponse(status: .unknownProcess)
        }
        guard (state.tty || state.pipeStdin), let stdin = state.stdin else {
            return ExecServerWriteResponse(status: .stdinClosed)
        }
        do {
            try stdin.write(contentsOf: Data(params.chunk.bytes))
            return ExecServerWriteResponse(status: .accepted)
        } catch {
            throw ExecServerRPC.internalError("failed to write to process stdin")
        }
    }

    public func terminate(_ params: ExecServerTerminateParams) async throws -> ExecServerTerminateResponse {
        guard let state = processes[params.processId], state.exitCode == nil else {
            return ExecServerTerminateResponse(running: false)
        }
        if state.process.isRunning {
            state.process.terminate()
            state.pseudoTerminal?.closeSlaveHandles()
            return ExecServerTerminateResponse(running: true)
        }
        return ExecServerTerminateResponse(running: false)
    }

    private func handleOutput(_ data: Data, processId: String, stream: ExecServerOutputStream) async {
        guard let state = processes[processId] else {
            return
        }
        if data.isEmpty {
            if stream == .pty {
                state.stdoutClosed = true
                state.stderrClosed = true
            } else if stream == .stdout {
                state.stdoutClosed = true
            } else {
                state.stderrClosed = true
            }
            await maybeClose(processId: processId, state: state)
            return
        }

        let seq = state.nextSeq
        state.nextSeq += 1
        state.retainedBytes += data.count
        state.output.append(ExecServerRetainedOutputChunk(seq: seq, stream: stream, bytes: Array(data)))
        while state.retainedBytes > Self.retainedOutputBytesPerProcess, !state.output.isEmpty {
            let removed = state.output.removeFirst()
            state.retainedBytes = max(0, state.retainedBytes - removed.bytes.count)
        }
        await sendNotification(
            method: execServerProcessOutputDeltaMethod,
            params: ExecServerOutputDeltaNotification(
                processId: processId,
                seq: seq,
                stream: stream,
                chunk: ExecServerByteChunk(Array(data))
            )
        )
    }

    private func handleExit(processId: String, exitCode: Int32) async {
        guard let state = processes[processId] else {
            return
        }
        let seq = state.nextSeq
        state.exitCode = exitCode
        state.nextSeq += 1
        await sendNotification(
            method: execServerProcessExitedMethod,
            params: ExecServerExitedNotification(
                processId: processId,
                seq: seq,
                exitCode: exitCode
            )
        )
        await maybeClose(processId: processId, state: state)
    }

    private func maybeClose(processId: String, state: ExecServerProcessState) async {
        guard !state.closed, state.exitCode != nil, state.stdoutClosed, state.stderrClosed else {
            return
        }
        let seq = state.nextSeq
        state.closed = true
        state.nextSeq += 1
        state.stdout.readabilityHandler = nil
        state.stderr.readabilityHandler = nil
        state.pseudoTerminal?.closeSlaveHandles()
        closeStdin(state)
        await sendNotification(
            method: execServerProcessClosedMethod,
            params: ExecServerClosedNotification(processId: processId, seq: seq)
        )
        Task {
            await evictClosedProcessAfterRetention(processId: processId)
        }
    }

    private func readResponse(
        from state: ExecServerProcessState,
        afterSeq: UInt64,
        maxBytes: Int
    ) -> ExecServerReadResponse {
        var chunks: [ExecServerProcessOutputChunk] = []
        var totalBytes = 0
        var nextSeq = state.nextSeq
        for retained in state.output where retained.seq > afterSeq {
            let chunkLength = retained.bytes.count
            if !chunks.isEmpty && totalBytes + chunkLength > maxBytes {
                break
            }
            totalBytes += chunkLength
            chunks.append(ExecServerProcessOutputChunk(
                seq: retained.seq,
                stream: retained.stream,
                chunk: ExecServerByteChunk(retained.bytes)
            ))
            nextSeq = retained.seq + 1
            if totalBytes >= maxBytes {
                break
            }
        }
        return ExecServerReadResponse(
            chunks: chunks,
            nextSeq: nextSeq,
            exited: state.exitCode != nil,
            exitCode: state.exitCode,
            closed: state.closed,
            failure: nil
        )
    }

    private func runningProcess(id: String) throws -> ExecServerProcessState {
        guard let state = processes[id] else {
            throw ExecServerRPC.invalidRequest("unknown process id \(id)")
        }
        return state
    }

    private func childEnvironment(_ params: ExecServerExecParams) -> [String: String] {
        guard let envPolicy = params.envPolicy else {
            return params.env
        }
        let policy = ShellEnvironmentPolicy(
            inherit: envPolicy.inherit,
            ignoreDefaultExcludes: envPolicy.ignoreDefaultExcludes,
            exclude: envPolicy.exclude.map(EnvironmentVariablePattern.newCaseInsensitive),
            set: envPolicy.set,
            includeOnly: envPolicy.includeOnly.map(EnvironmentVariablePattern.newCaseInsensitive),
            useProfile: false
        )
        var environment = ExecEnvironment.createEnv(policy: policy)
        environment.merge(params.env) { _, overlay in overlay }
        return environment
    }

    private func closeStdin(_ state: ExecServerProcessState) {
        try? state.stdin?.close()
    }

    private func evictClosedProcessAfterRetention(processId: String) async {
        try? await Task.sleep(nanoseconds: retentionDelayNanoseconds)
        guard let state = processes[processId], state.closed else {
            return
        }
        processes.removeValue(forKey: processId)
    }

    private func sendNotification<T: Encodable & Sendable>(method: String, params: T) async {
        guard let params = try? ExecServerRPC.jsonValue(from: params) else {
            return
        }
        await outboundNotification(ExecServerJSONRPCNotification(method: method, params: params))
    }
}

private final class ExecServerProcessState {
    let process: Process
    let stdout: FileHandle
    let stderr: FileHandle
    let stdin: FileHandle?
    let tty: Bool
    let pipeStdin: Bool
    let pseudoTerminal: ExecServerPseudoTerminal?
    var output: [ExecServerRetainedOutputChunk] = []
    var retainedBytes = 0
    var nextSeq: UInt64 = 1
    var exitCode: Int32?
    var stdoutClosed = false
    var stderrClosed = false
    var closed = false

    init(
        process: Process,
        stdout: FileHandle,
        stderr: FileHandle,
        stdin: FileHandle?,
        tty: Bool,
        pipeStdin: Bool,
        pseudoTerminal: ExecServerPseudoTerminal?
    ) {
        self.process = process
        self.stdout = stdout
        self.stderr = stderr
        self.stdin = stdin
        self.tty = tty
        self.pipeStdin = pipeStdin
        self.pseudoTerminal = pseudoTerminal
    }
}

private struct ExecServerRetainedOutputChunk {
    let seq: UInt64
    let stream: ExecServerOutputStream
    let bytes: [UInt8]
}

private extension UInt64 {
    func saturatingSubtracting(_ value: UInt64) -> UInt64 {
        self > value ? self - value : 0
    }
}
