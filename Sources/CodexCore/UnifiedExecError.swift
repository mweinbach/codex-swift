import Foundation

public enum UnifiedExecError: Error, Equatable, CustomStringConvertible, Sendable {
    case createSession(message: String)
    case unknownSessionID(processID: String)
    case writeToStdin
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
        case .missingCommandLine:
            return "missing command line for unified exec request"
        case let .sandboxDenied(message, _):
            return "Command denied by sandbox: \(message)"
        }
    }
}
