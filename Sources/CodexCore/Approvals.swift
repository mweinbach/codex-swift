import Foundation

public struct ExecPolicyAmendment: Equatable, Codable, Sendable {
    public let command: [String]

    public init(command: [String]) {
        self.command = command
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.command = try container.decode([String].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(command)
    }
}

public enum ReviewDecision: Equatable, Codable, Sendable {
    case approved
    case approvedExecpolicyAmendment(proposedExecpolicyAmendment: ExecPolicyAmendment)
    case approvedForSession
    case denied
    case abort

    public static let `default`: ReviewDecision = .denied

    private enum UnitDecision: String, Codable {
        case approved
        case approvedForSession = "approved_for_session"
        case denied
        case abort
    }

    private enum CodingKeys: String, CodingKey {
        case approvedExecpolicyAmendment = "approved_execpolicy_amendment"
    }

    private enum AmendmentKeys: String, CodingKey {
        case proposedExecpolicyAmendment = "proposed_execpolicy_amendment"
    }

    public init(from decoder: Decoder) throws {
        if let unit = try? UnitDecision(from: decoder) {
            switch unit {
            case .approved:
                self = .approved
            case .approvedForSession:
                self = .approvedForSession
            case .denied:
                self = .denied
            case .abort:
                self = .abort
            }
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.approvedExecpolicyAmendment) {
            let nested = try container.nestedContainer(
                keyedBy: AmendmentKeys.self,
                forKey: .approvedExecpolicyAmendment
            )
            self = .approvedExecpolicyAmendment(
                proposedExecpolicyAmendment: try nested.decode(
                    ExecPolicyAmendment.self,
                    forKey: .proposedExecpolicyAmendment
                )
            )
            return
        }

        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Unsupported review decision"
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .approved:
            try UnitDecision.approved.encode(to: encoder)
        case let .approvedExecpolicyAmendment(amendment):
            var container = encoder.container(keyedBy: CodingKeys.self)
            var nested = container.nestedContainer(
                keyedBy: AmendmentKeys.self,
                forKey: .approvedExecpolicyAmendment
            )
            try nested.encode(amendment, forKey: .proposedExecpolicyAmendment)
        case .approvedForSession:
            try UnitDecision.approvedForSession.encode(to: encoder)
        case .denied:
            try UnitDecision.denied.encode(to: encoder)
        case .abort:
            try UnitDecision.abort.encode(to: encoder)
        }
    }
}
