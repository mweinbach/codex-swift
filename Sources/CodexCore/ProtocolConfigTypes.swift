import Foundation

public enum ReasoningSummary: String, Codable, CaseIterable, Equatable, Sendable {
    case auto
    case concise
    case detailed
    case none
}

public enum ReasoningEffort: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case none
    case minimal
    case low
    case medium
    case high
    case xhigh
}

public enum Verbosity: String, Codable, CaseIterable, Equatable, Sendable {
    case low
    case medium
    case high
}

public enum ServiceTier: String, Codable, CaseIterable, Equatable, Sendable {
    case fast
    case flex

    public var requestValue: String {
        switch self {
        case .fast:
            return "priority"
        case .flex:
            return "flex"
        }
    }

    public static func fromRequestValue(_ value: String) -> ServiceTier? {
        switch value {
        case "fast", "priority":
            return .fast
        case "flex":
            return .flex
        default:
            return nil
        }
    }
}

public enum WireAPI: String, Codable, CaseIterable, Equatable, Sendable {
    case responses
    case chat
    case compact
}

public enum ForcedLoginMethod: String, Codable, CaseIterable, Equatable, Sendable {
    case chatgpt
    case api
}

public enum TrustLevel: String, Codable, CaseIterable, Equatable, Sendable {
    case trusted
    case untrusted
}

public enum CollaborationModeKind: String, Codable, CaseIterable, Equatable, Sendable {
    case plan
    case defaultMode = "default"

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "plan":
            self = .plan
        case "default", "code", "pair_programming", "execute", "custom":
            self = .defaultMode
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown collaboration mode kind: \(rawValue)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var displayName: String {
        switch self {
        case .plan:
            return "Plan"
        case .defaultMode:
            return "Default"
        }
    }
}

public struct CollaborationModeMask: Equatable, Sendable {
    public var name: String
    public var mode: CollaborationModeKind?
    public var model: String?
    public var reasoningEffort: ReasoningEffort?

    public init(
        name: String,
        mode: CollaborationModeKind? = nil,
        model: String? = nil,
        reasoningEffort: ReasoningEffort? = nil
    ) {
        self.name = name
        self.mode = mode
        self.model = model
        self.reasoningEffort = reasoningEffort
    }
}

public enum CollaborationModeRegistry {
    public static let tuiVisibleModes: [CollaborationModeKind] = [.defaultMode, .plan]

    public static let builtinPresets: [CollaborationModeMask] = [
        CollaborationModeMask(
            name: CollaborationModeKind.plan.displayName,
            mode: .plan,
            reasoningEffort: .medium
        ),
        CollaborationModeMask(
            name: CollaborationModeKind.defaultMode.displayName,
            mode: .defaultMode
        )
    ]
}
