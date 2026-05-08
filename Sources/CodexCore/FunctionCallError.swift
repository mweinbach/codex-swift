import Foundation

public enum FunctionCallError: Error, Equatable, CustomStringConvertible, Sendable {
    case respondToModel(String)
    case denied(String)
    case missingLocalShellCallID
    case fatal(String)

    public var description: String {
        switch self {
        case let .respondToModel(message),
             let .denied(message):
            return message
        case .missingLocalShellCallID:
            return "LocalShellCall without call_id or id"
        case let .fatal(message):
            return "Fatal error: \(message)"
        }
    }
}
