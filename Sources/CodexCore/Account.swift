import Foundation

public enum PlanType: Equatable, Codable, Sendable {
    case free
    case go
    case plus
    case pro
    case proLite
    case team
    case selfServeBusinessUsageBased
    case business
    case enterpriseCbpUsageBased
    case enterprise
    case edu
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .free:
            return "free"
        case .go:
            return "go"
        case .plus:
            return "plus"
        case .pro:
            return "pro"
        case .proLite:
            return "prolite"
        case .team:
            return "team"
        case .selfServeBusinessUsageBased:
            return "self_serve_business_usage_based"
        case .business:
            return "business"
        case .enterpriseCbpUsageBased:
            return "enterprise_cbp_usage_based"
        case .enterprise:
            return "enterprise"
        case .edu:
            return "edu"
        case let .unknown(value):
            return value
        }
    }

    public var displayName: String {
        switch self {
        case .free:
            return "Free"
        case .go:
            return "Go"
        case .plus:
            return "Plus"
        case .pro:
            return "Pro"
        case .proLite:
            return "Pro Lite"
        case .team:
            return "Team"
        case .selfServeBusinessUsageBased:
            return "Self Serve Business Usage Based"
        case .business:
            return "Business"
        case .enterpriseCbpUsageBased:
            return "Enterprise CBP Usage Based"
        case .enterprise:
            return "Enterprise"
        case .edu:
            return "Edu"
        case .unknown:
            return "Unknown"
        }
    }

    public var isTeamLike: Bool {
        self == .team || self == .selfServeBusinessUsageBased
    }

    public var isBusinessLike: Bool {
        self == .business || self == .enterpriseCbpUsageBased
    }

    public var isWorkspaceAccount: Bool {
        switch self {
        case .team, .selfServeBusinessUsageBased, .business, .enterpriseCbpUsageBased, .enterprise, .edu:
            return true
        case .free, .go, .plus, .pro, .proLite, .unknown:
            return false
        }
    }

    public static func fromRawValue(_ rawValue: String) -> PlanType {
        switch rawValue.lowercased() {
        case "free":
            return .free
        case "go":
            return .go
        case "plus":
            return .plus
        case "pro":
            return .pro
        case "prolite":
            return .proLite
        case "team":
            return .team
        case "self_serve_business_usage_based":
            return .selfServeBusinessUsageBased
        case "business":
            return .business
        case "enterprise_cbp_usage_based":
            return .enterpriseCbpUsageBased
        case "enterprise", "hc":
            return .enterprise
        case "education", "edu":
            return .edu
        default:
            return .unknown(rawValue)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = Self.fromRawValue(try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
