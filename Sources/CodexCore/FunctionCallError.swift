import Foundation

public enum FunctionCallError: Error, Equatable, CustomStringConvertible, Sendable {
    case respondToModel(String)
    case fatal(String)

    public var description: String {
        switch self {
        case let .respondToModel(message):
            return message
        case let .fatal(message):
            return "Fatal error: \(message)"
        }
    }
}
