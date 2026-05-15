import Foundation

public struct ModelProviderCapabilitiesReadParams: Equatable, Codable, Sendable {
    public init() {}
}

public struct ModelProviderCapabilitiesReadResponse: Equatable, Codable, Sendable {
    public let namespaceTools: Bool
    public let imageGeneration: Bool
    public let webSearch: Bool

    public init(namespaceTools: Bool, imageGeneration: Bool, webSearch: Bool) {
        self.namespaceTools = namespaceTools
        self.imageGeneration = imageGeneration
        self.webSearch = webSearch
    }

    public init(core capabilities: ModelProviderCapabilities) {
        self.init(
            namespaceTools: capabilities.namespaceTools,
            imageGeneration: capabilities.imageGeneration,
            webSearch: capabilities.webSearch
        )
    }
}

public struct ModelListParams: Equatable, Sendable {
    public let cursor: String?
    public let limit: UInt32?
    public let includeHidden: Bool?

    public init(cursor: String? = nil, limit: UInt32? = nil, includeHidden: Bool? = nil) {
        self.cursor = cursor
        self.limit = limit
        self.includeHidden = includeHidden
    }
}

extension ModelListParams: Codable {
    private enum CodingKeys: String, CodingKey {
        case cursor
        case limit
        case includeHidden
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cursor = try container.decodeIfPresent(String.self, forKey: .cursor)
        limit = try container.decodeIfPresent(UInt32.self, forKey: .limit)
        includeHidden = try container.decodeIfPresent(Bool.self, forKey: .includeHidden)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNilOrValue(cursor, forKey: .cursor)
        try container.encodeNilOrValue(limit, forKey: .limit)
        try container.encodeNilOrValue(includeHidden, forKey: .includeHidden)
    }
}

public struct Model: Equatable, Sendable {
    public let id: String
    public let model: String
    public let upgrade: String?
    public let upgradeInfo: ModelUpgradeInfo?
    public let availabilityNux: ModelAvailabilityNux?
    public let displayName: String
    public let description: String
    public let hidden: Bool
    public let supportedReasoningEfforts: [ReasoningEffortOption]
    public let defaultReasoningEffort: ReasoningEffort
    public let inputModalities: [InputModality]
    public let supportsPersonality: Bool
    public let additionalSpeedTiers: [String]
    public let serviceTiers: [ModelServiceTier]
    public let isDefault: Bool

    public init(
        id: String,
        model: String,
        upgrade: String?,
        upgradeInfo: ModelUpgradeInfo?,
        availabilityNux: ModelAvailabilityNux?,
        displayName: String,
        description: String,
        hidden: Bool,
        supportedReasoningEfforts: [ReasoningEffortOption],
        defaultReasoningEffort: ReasoningEffort,
        inputModalities: [InputModality] = InputModality.defaultInputModalities,
        supportsPersonality: Bool = false,
        additionalSpeedTiers: [String] = [],
        serviceTiers: [ModelServiceTier] = [],
        isDefault: Bool
    ) {
        self.id = id
        self.model = model
        self.upgrade = upgrade
        self.upgradeInfo = upgradeInfo
        self.availabilityNux = availabilityNux
        self.displayName = displayName
        self.description = description
        self.hidden = hidden
        self.supportedReasoningEfforts = supportedReasoningEfforts
        self.defaultReasoningEffort = defaultReasoningEffort
        self.inputModalities = inputModalities
        self.supportsPersonality = supportsPersonality
        self.additionalSpeedTiers = additionalSpeedTiers
        self.serviceTiers = serviceTiers
        self.isDefault = isDefault
    }

    public init(core preset: ModelPreset) {
        self.init(
            id: preset.id,
            model: preset.model,
            upgrade: preset.upgrade?.id,
            upgradeInfo: preset.upgrade.map(ModelUpgradeInfo.init(core:)),
            availabilityNux: preset.availabilityNux,
            displayName: preset.displayName,
            description: preset.description,
            hidden: !preset.showInPicker,
            supportedReasoningEfforts: preset.supportedReasoningEfforts.map(ReasoningEffortOption.init(core:)),
            defaultReasoningEffort: preset.defaultReasoningEffort,
            inputModalities: preset.inputModalities,
            supportsPersonality: preset.supportsPersonality,
            additionalSpeedTiers: preset.additionalSpeedTiers,
            serviceTiers: preset.serviceTiers,
            isDefault: preset.isDefault
        )
    }
}

extension Model: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case model
        case upgrade
        case upgradeInfo
        case availabilityNux
        case displayName
        case description
        case hidden
        case supportedReasoningEfforts
        case defaultReasoningEffort
        case inputModalities
        case supportsPersonality
        case additionalSpeedTiers
        case serviceTiers
        case isDefault
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        model = try container.decode(String.self, forKey: .model)
        upgrade = try container.decodeIfPresent(String.self, forKey: .upgrade)
        upgradeInfo = try container.decodeIfPresent(ModelUpgradeInfo.self, forKey: .upgradeInfo)
        availabilityNux = try container.decodeIfPresent(ModelAvailabilityNux.self, forKey: .availabilityNux)
        displayName = try container.decode(String.self, forKey: .displayName)
        description = try container.decode(String.self, forKey: .description)
        hidden = try container.decode(Bool.self, forKey: .hidden)
        supportedReasoningEfforts = try container.decode(
            [ReasoningEffortOption].self,
            forKey: .supportedReasoningEfforts
        )
        defaultReasoningEffort = try container.decode(ReasoningEffort.self, forKey: .defaultReasoningEffort)
        inputModalities = try container.decodeIfPresent(
            [InputModality].self,
            forKey: .inputModalities
        ) ?? InputModality.defaultInputModalities
        supportsPersonality = try container.decodeRustDefaulted(
            Bool.self,
            forKey: .supportsPersonality,
            defaultValue: false
        )
        additionalSpeedTiers = try container.decodeIfPresent([String].self, forKey: .additionalSpeedTiers) ?? []
        serviceTiers = try container.decodeIfPresent([ModelServiceTier].self, forKey: .serviceTiers) ?? []
        isDefault = try container.decode(Bool.self, forKey: .isDefault)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(model, forKey: .model)
        try container.encodeNilOrValue(upgrade, forKey: .upgrade)
        try container.encodeNilOrValue(upgradeInfo, forKey: .upgradeInfo)
        try container.encodeNilOrValue(availabilityNux, forKey: .availabilityNux)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(description, forKey: .description)
        try container.encode(hidden, forKey: .hidden)
        try container.encode(supportedReasoningEfforts, forKey: .supportedReasoningEfforts)
        try container.encode(defaultReasoningEffort, forKey: .defaultReasoningEffort)
        try container.encode(inputModalities, forKey: .inputModalities)
        try container.encode(supportsPersonality, forKey: .supportsPersonality)
        try container.encode(additionalSpeedTiers, forKey: .additionalSpeedTiers)
        try container.encode(serviceTiers, forKey: .serviceTiers)
        try container.encode(isDefault, forKey: .isDefault)
    }
}

public struct ModelUpgradeInfo: Equatable, Sendable {
    public let model: String
    public let upgradeCopy: String?
    public let modelLink: String?
    public let migrationMarkdown: String?

    public init(model: String, upgradeCopy: String?, modelLink: String?, migrationMarkdown: String?) {
        self.model = model
        self.upgradeCopy = upgradeCopy
        self.modelLink = modelLink
        self.migrationMarkdown = migrationMarkdown
    }

    public init(core upgrade: ModelUpgrade) {
        self.init(
            model: upgrade.id,
            upgradeCopy: upgrade.upgradeCopy,
            modelLink: upgrade.modelLink,
            migrationMarkdown: upgrade.migrationMarkdown
        )
    }
}

extension ModelUpgradeInfo: Codable {
    private enum CodingKeys: String, CodingKey {
        case model
        case upgradeCopy
        case modelLink
        case migrationMarkdown
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decode(String.self, forKey: .model)
        upgradeCopy = try container.decodeIfPresent(String.self, forKey: .upgradeCopy)
        modelLink = try container.decodeIfPresent(String.self, forKey: .modelLink)
        migrationMarkdown = try container.decodeIfPresent(String.self, forKey: .migrationMarkdown)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encodeNilOrValue(upgradeCopy, forKey: .upgradeCopy)
        try container.encodeNilOrValue(modelLink, forKey: .modelLink)
        try container.encodeNilOrValue(migrationMarkdown, forKey: .migrationMarkdown)
    }
}

public struct ReasoningEffortOption: Equatable, Codable, Sendable {
    public let reasoningEffort: ReasoningEffort
    public let description: String

    public init(reasoningEffort: ReasoningEffort, description: String) {
        self.reasoningEffort = reasoningEffort
        self.description = description
    }

    public init(core preset: ReasoningEffortPreset) {
        self.init(reasoningEffort: preset.effort, description: preset.description)
    }
}

public struct ModelListResponse: Equatable, Sendable {
    public let data: [Model]
    public let nextCursor: String?

    public init(data: [Model], nextCursor: String?) {
        self.data = data
        self.nextCursor = nextCursor
    }
}

extension ModelListResponse: Codable {
    private enum CodingKeys: String, CodingKey {
        case data
        case nextCursor
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decode([Model].self, forKey: .data)
        nextCursor = try container.decodeIfPresent(String.self, forKey: .nextCursor)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(data, forKey: .data)
        try container.encodeNilOrValue(nextCursor, forKey: .nextCursor)
    }
}

public struct ModelReroutedNotification: Equatable, Codable, Sendable {
    public let threadID: String
    public let turnID: String
    public let fromModel: String
    public let toModel: String
    public let reason: AppServerModelRerouteReason

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case turnID = "turnId"
        case fromModel
        case toModel
        case reason
    }

    public init(
        threadID: String,
        turnID: String,
        fromModel: String,
        toModel: String,
        reason: AppServerModelRerouteReason
    ) {
        self.threadID = threadID
        self.turnID = turnID
        self.fromModel = fromModel
        self.toModel = toModel
        self.reason = reason
    }

    public init(threadID: String, turnID: String, core event: ModelRerouteEvent) {
        self.init(
            threadID: threadID,
            turnID: turnID,
            fromModel: event.fromModel,
            toModel: event.toModel,
            reason: AppServerModelRerouteReason(core: event.reason)
        )
    }
}

public enum AppServerModelRerouteReason: String, Codable, Equatable, Sendable {
    case highRiskCyberActivity

    public init(core reason: ModelRerouteReason) {
        switch reason {
        case .highRiskCyberActivity:
            self = .highRiskCyberActivity
        }
    }
}

public struct ModelVerificationNotification: Equatable, Codable, Sendable {
    public let threadID: String
    public let turnID: String
    public let verifications: [AppServerModelVerification]

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case turnID = "turnId"
        case verifications
    }

    public init(threadID: String, turnID: String, verifications: [AppServerModelVerification]) {
        self.threadID = threadID
        self.turnID = turnID
        self.verifications = verifications
    }

    public init(threadID: String, turnID: String, core event: ModelVerificationEvent) {
        self.init(
            threadID: threadID,
            turnID: turnID,
            verifications: event.verifications.map(AppServerModelVerification.init(core:))
        )
    }
}

public enum AppServerModelVerification: String, Codable, Equatable, Sendable {
    case trustedAccessForCyber

    public init(core verification: ModelVerification) {
        switch verification {
        case .trustedAccessForCyber:
            self = .trustedAccessForCyber
        }
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeNilOrValue<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}
