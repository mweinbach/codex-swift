import Foundation

public struct LineModeInteractiveRuntime: Sendable {
    public struct IO: Sendable {
        public var readLine: @Sendable () -> String?
        public var writeStdout: @Sendable (String) -> Void
        public var writeStderr: @Sendable (String) -> Void
        public var writePrompt: @Sendable (String) -> Void

        public init(
            readLine: @escaping @Sendable () -> String?,
            writeStdout: @escaping @Sendable (String) -> Void,
            writeStderr: @escaping @Sendable (String) -> Void,
            writePrompt: @escaping @Sendable (String) -> Void
        ) {
            self.readLine = readLine
            self.writeStdout = writeStdout
            self.writeStderr = writeStderr
            self.writePrompt = writePrompt
        }
    }

    public struct Turn: Sendable {
        public let prompt: String
        public let turnIndex: Int
        public let request: CodexCLI.InteractiveCommandRequest

        public init(prompt: String, turnIndex: Int, request: CodexCLI.InteractiveCommandRequest) {
            self.prompt = prompt
            self.turnIndex = turnIndex
            self.request = request
        }
    }

    public typealias TurnRunner = @Sendable (Turn) async throws -> CodexCLI.CommandExecutionResult

    private let request: CodexCLI.InteractiveCommandRequest
    private let io: IO
    private let turnRunner: TurnRunner

    public init(
        request: CodexCLI.InteractiveCommandRequest,
        io: IO,
        turnRunner: @escaping TurnRunner
    ) {
        self.request = request
        self.io = io
        self.turnRunner = turnRunner
    }

    public func run() async -> CodexCLI.CommandExecutionResult {
        if request.remote != nil || request.remoteAuthTokenEnv != nil {
            return CodexCLI.CommandExecutionResult(
                exitCode: 78,
                stderrMessage: "codex-swift: line-mode interactive fallback does not support remote sessions yet."
            )
        }

        io.writeStderr("codex-swift: starting line-mode interactive fallback. Type /quit or /exit to leave.")

        var turnIndex = 0
        if let prompt = request.prompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            turnIndex += 1
            let result = await runTurn(prompt: prompt, turnIndex: turnIndex)
            guard result.exitCode == 0 else {
                return result
            }
        }

        while true {
            io.writePrompt("codex> ")
            guard let line = io.readLine() else {
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            if trimmed == "/quit" || trimmed == "/exit" {
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }

            turnIndex += 1
            let result = await runTurn(prompt: line, turnIndex: turnIndex)
            guard result.exitCode == 0 else {
                return result
            }
        }
    }

    private func runTurn(prompt: String, turnIndex: Int) async -> CodexCLI.CommandExecutionResult {
        do {
            let result = try await turnRunner(Turn(prompt: prompt, turnIndex: turnIndex, request: request))
            if let stderrMessage = result.stderrMessage, !stderrMessage.isEmpty {
                io.writeStderr(stderrMessage)
            }
            if let stdoutMessage = result.stdoutMessage, !stdoutMessage.isEmpty {
                io.writeStdout(stdoutMessage)
            }
            return result
        } catch {
            let message = String(describing: error)
            io.writeStderr(message)
            return CodexCLI.CommandExecutionResult(exitCode: 1, stderrMessage: message)
        }
    }
}
