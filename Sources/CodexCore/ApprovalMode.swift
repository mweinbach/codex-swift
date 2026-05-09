import Foundation

public enum AskForApproval: String, Codable, Equatable, Sendable {
    case unlessTrusted = "untrusted"
    case onFailure = "on-failure"
    case onRequest = "on-request"
    case never
}

public enum ApprovalsReviewer: Equatable, Sendable {
    case user
    case autoReview
}

extension ApprovalsReviewer: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        switch try container.decode(String.self) {
        case "user":
            self = .user
        case "guardian_subagent", "auto_review":
            self = .autoReview
        case let value:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown approvals reviewer: \(value)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .user:
            try container.encode("user")
        case .autoReview:
            try container.encode("guardian_subagent")
        }
    }
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
