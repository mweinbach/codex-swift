import Foundation

public enum PlanType: Equatable, Codable, Sendable {
    case free
    case plus
    case pro
    case team
    case business
    case enterprise
    case edu
    case unknown

    public var rawValue: String {
        switch self {
        case .free:
            return "free"
        case .plus:
            return "plus"
        case .pro:
            return "pro"
        case .team:
            return "team"
        case .business:
            return "business"
        case .enterprise:
            return "enterprise"
        case .edu:
            return "edu"
        case .unknown:
            return "unknown"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        switch try container.decode(String.self) {
        case "free":
            self = .free
        case "plus":
            self = .plus
        case "pro":
            self = .pro
        case "team":
            self = .team
        case "business":
            self = .business
        case "enterprise":
            self = .enterprise
        case "edu":
            self = .edu
        default:
            self = .unknown
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
