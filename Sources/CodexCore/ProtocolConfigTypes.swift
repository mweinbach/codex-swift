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

public enum Personality: String, Codable, CaseIterable, Equatable, Sendable {
    case none
    case friendly
    case pragmatic
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

public struct CollaborationModeSettings: Codable, Equatable, Sendable {
    public var model: String
    public var reasoningEffort: ReasoningEffort?
    public var developerInstructions: String?

    private enum CodingKeys: String, CodingKey {
        case model
        case reasoningEffort = "reasoning_effort"
        case developerInstructions = "developer_instructions"
    }

    public init(
        model: String,
        reasoningEffort: ReasoningEffort? = nil,
        developerInstructions: String? = nil
    ) {
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.developerInstructions = developerInstructions
    }
}

public struct CollaborationMode: Codable, Equatable, Sendable {
    public var mode: CollaborationModeKind
    public var settings: CollaborationModeSettings

    public init(mode: CollaborationModeKind, settings: CollaborationModeSettings) {
        self.mode = mode
        self.settings = settings
    }

    public func applying(_ mask: CollaborationModeMask) -> CollaborationMode {
        CollaborationMode(
            mode: mask.mode ?? mode,
            settings: CollaborationModeSettings(
                model: mask.model ?? settings.model,
                reasoningEffort: mask.reasoningEffort.applied(to: settings.reasoningEffort),
                developerInstructions: mask.developerInstructions.applied(to: settings.developerInstructions)
            )
        )
    }
}

public enum CollaborationModeOptionalSetting<Value: Codable & Equatable & Sendable>: Equatable, Sendable {
    case preserve
    case clear
    case set(Value)

    public var value: Value? {
        switch self {
        case .preserve, .clear:
            return nil
        case let .set(value):
            return value
        }
    }

    public func applied(to current: Value?) -> Value? {
        switch self {
        case .preserve:
            return current
        case .clear:
            return nil
        case let .set(value):
            return value
        }
    }
}

public struct CollaborationModeMask: Codable, Equatable, Sendable {
    public var name: String
    public var mode: CollaborationModeKind?
    public var model: String?
    public var reasoningEffort: CollaborationModeOptionalSetting<ReasoningEffort>
    public var developerInstructions: CollaborationModeOptionalSetting<String>

    private enum CodingKeys: String, CodingKey {
        case name
        case mode
        case model
        case reasoningEffort = "reasoning_effort"
        case developerInstructions = "developer_instructions"
    }

    public init(
        name: String,
        mode: CollaborationModeKind? = nil,
        model: String? = nil,
        reasoningEffort: ReasoningEffort? = nil,
        developerInstructions: String? = nil
    ) {
        self.name = name
        self.mode = mode
        self.model = model
        self.reasoningEffort = reasoningEffort.map(CollaborationModeOptionalSetting.set) ?? .preserve
        self.developerInstructions = developerInstructions.map(CollaborationModeOptionalSetting.set) ?? .preserve
    }

    public init(
        name: String,
        mode: CollaborationModeKind? = nil,
        model: String? = nil,
        reasoningEffort: CollaborationModeOptionalSetting<ReasoningEffort>,
        developerInstructions: CollaborationModeOptionalSetting<String> = .preserve
    ) {
        self.name = name
        self.mode = mode
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.developerInstructions = developerInstructions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        mode = try container.decodeIfPresent(CollaborationModeKind.self, forKey: .mode)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        reasoningEffort = try Self.decodeOptionalSetting(
            ReasoningEffort.self,
            from: container,
            forKey: .reasoningEffort
        )
        developerInstructions = try Self.decodeOptionalSetting(
            String.self,
            from: container,
            forKey: .developerInstructions
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(mode, forKey: .mode)
        try container.encode(model, forKey: .model)
        try Self.encodeOptionalSetting(reasoningEffort, into: &container, forKey: .reasoningEffort)
        try Self.encodeOptionalSetting(developerInstructions, into: &container, forKey: .developerInstructions)
    }

    private static func decodeOptionalSetting<Value: Codable & Equatable & Sendable>(
        _: Value.Type,
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> CollaborationModeOptionalSetting<Value> {
        guard container.contains(key) else {
            return .preserve
        }
        if try container.decodeNil(forKey: key) {
            return .clear
        }
        return .set(try container.decode(Value.self, forKey: key))
    }

    private static func encodeOptionalSetting<Value: Codable & Equatable & Sendable>(
        _ setting: CollaborationModeOptionalSetting<Value>,
        into container: inout KeyedEncodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws {
        switch setting {
        case .preserve, .clear:
            try container.encodeNil(forKey: key)
        case let .set(value):
            try container.encode(value, forKey: key)
        }
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
