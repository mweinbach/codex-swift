import Foundation

private let sandboxDeniedUIMessageMaxBytes = 2 * 1024

public enum UnifiedExecError: Error, Equatable, CustomStringConvertible, Sendable {
    case createSession(message: String)
    case unknownSessionID(processID: String)
    case writeToStdin
    case stdinClosed
    case missingCommandLine
    case sandboxDenied(message: String, output: ExecToolCallOutput)

    public static func createSession(_ message: String) -> UnifiedExecError {
        .createSession(message: message)
    }

    public static func makeSandboxDenied(message: String, output: ExecToolCallOutput) -> UnifiedExecError {
        .sandboxDenied(message: message, output: output)
    }

    public var description: String {
        switch self {
        case let .createSession(message):
            return "Failed to create unified exec session: \(message)"
        case let .unknownSessionID(processID):
            return "Unknown session id \(processID)"
        case .writeToStdin:
            return "failed to write to stdin"
        case .stdinClosed:
            return "stdin is closed for this session; rerun exec_command with tty=true to keep stdin open"
        case .missingCommandLine:
            return "missing command line for unified exec request"
        case let .sandboxDenied(message, _):
            return "Command denied by sandbox: \(message)"
        }
    }

    public var userFacingMessage: String {
        let message = switch self {
        case let .sandboxDenied(_, output):
            Self.sandboxDeniedUserFacingMessage(output)
        default:
            description
        }
        return Truncation.truncateText(message, policy: .bytes(sandboxDeniedUIMessageMaxBytes))
    }

    private static func sandboxDeniedUserFacingMessage(_ output: ExecToolCallOutput) -> String {
        if !output.aggregatedOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return output.aggregatedOutput
        }

        let stderr = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let stdout = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (stderr.isEmpty, stdout.isEmpty) {
        case (false, false):
            return "\(stderr)\n\(stdout)"
        case (false, true):
            return output.stderr
        case (true, false):
            return output.stdout
        case (true, true):
            return "command failed inside sandbox with exit code \(output.exitCode)"
        }
    }
}
