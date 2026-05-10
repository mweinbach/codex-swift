import CodexCore
import Foundation

public enum DebugCommandRuntime {
    public static func run(_ request: CodexCLI.DebugCommandRequest) async throws -> CodexCLI.CommandExecutionResult {
        switch request.action {
        case let .models(bundled):
            return try runModels(bundled: bundled)
        case .appServerSendMessageV2:
            return pendingRuntime("debug app-server send-message-v2")
        case .promptInput:
            return pendingRuntime("debug prompt-input")
        case .traceReduce:
            return pendingRuntime("debug trace-reduce")
        case .clearMemories:
            return pendingRuntime("debug clear-memories")
        }
    }

    private static func runModels(bundled: Bool) throws -> CodexCLI.CommandExecutionResult {
        guard bundled else {
            return pendingRuntime("debug models")
        }

        let encoder = JSONEncoder()
        let data = try encoder.encode(try ModelsManager.bundledModelsResponse())
        guard let output = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(
                ModelsManager.bundledModels,
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "Unable to encode bundled model catalog as UTF-8"
                )
            )
        }
        return CodexCLI.CommandExecutionResult(exitCode: 0, stdoutMessage: output)
    }

    private static func pendingRuntime(_ command: String) -> CodexCLI.CommandExecutionResult {
        CodexCLI.CommandExecutionResult(
            exitCode: 78,
            stderrMessage: "codex-swift: command '\(command)' runtime port is not complete yet."
        )
    }
}
