import Foundation

public enum AskForApproval: String, Equatable, Sendable {
    case unlessTrusted
    case onFailure
    case onRequest
    case never
}

public enum ApprovalModeCLIArgument: String, CaseIterable, Equatable, Sendable {
    case untrusted
    case onFailure = "on-failure"
    case onRequest = "on-request"
    case never

    public var approvalMode: AskForApproval {
        switch self {
        case .untrusted:
            return .unlessTrusted
        case .onFailure:
            return .onFailure
        case .onRequest:
            return .onRequest
        case .never:
            return .never
        }
    }
}
