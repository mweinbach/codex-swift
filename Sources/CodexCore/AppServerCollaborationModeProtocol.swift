public struct CollaborationModeListParams: Equatable, Codable, Sendable {
    public init() {}
}

public struct AppServerCollaborationModeMask: Equatable, Sendable {
    public let name: String
    public let mode: CollaborationModeKind?
    public let model: String?
    public let reasoningEffort: ReasoningEffort?

    private enum CodingKeys: String, CodingKey {
        case name
        case mode
        case model
        case reasoningEffort = "reasoning_effort"
    }

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

    public init(_ mask: CollaborationModeMask) {
        self.init(
            name: mask.name,
            mode: mask.mode,
            model: mask.model,
            reasoningEffort: mask.reasoningEffort.value
        )
    }
}

extension AppServerCollaborationModeMask: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        mode = try container.decodeIfPresent(CollaborationModeKind.self, forKey: .mode)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        reasoningEffort = try container.decodeIfPresent(ReasoningEffort.self, forKey: .reasoningEffort)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(mode, forKey: .mode)
        try container.encode(model, forKey: .model)
        try container.encode(reasoningEffort, forKey: .reasoningEffort)
    }
}

public struct CollaborationModeListResponse: Equatable, Codable, Sendable {
    public let data: [AppServerCollaborationModeMask]

    public init(data: [AppServerCollaborationModeMask]) {
        self.data = data
    }

    public init(coreMasks: [CollaborationModeMask]) {
        data = coreMasks.map(AppServerCollaborationModeMask.init)
    }
}
