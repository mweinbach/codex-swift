import Foundation

public struct ReasoningEffortPreset: Equatable, Codable, Sendable {
    public let effort: ReasoningEffort
    public let description: String

    public init(effort: ReasoningEffort, description: String) {
        self.effort = effort
        self.description = description
    }
}

public struct ModelUpgrade: Equatable, Sendable {
    public let id: String
    public let reasoningEffortMapping: [ReasoningEffort: ReasoningEffort]?
    public let migrationConfigKey: String
    public let modelLink: String?
    public let upgradeCopy: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case reasoningEffortMapping = "reasoning_effort_mapping"
        case migrationConfigKey = "migration_config_key"
        case modelLink = "model_link"
        case upgradeCopy = "upgrade_copy"
    }

    public init(
        id: String,
        reasoningEffortMapping: [ReasoningEffort: ReasoningEffort]? = nil,
        migrationConfigKey: String,
        modelLink: String? = nil,
        upgradeCopy: String? = nil
    ) {
        self.id = id
        self.reasoningEffortMapping = reasoningEffortMapping
        self.migrationConfigKey = migrationConfigKey
        self.modelLink = modelLink
        self.upgradeCopy = upgradeCopy
    }
}

extension ModelUpgrade: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.reasoningEffortMapping = try decodeReasoningEffortMapping(
            from: container,
            forKey: .reasoningEffortMapping
        )
        self.migrationConfigKey = try container.decode(String.self, forKey: .migrationConfigKey)
        self.modelLink = try container.decodeIfPresent(String.self, forKey: .modelLink)
        self.upgradeCopy = try container.decodeIfPresent(String.self, forKey: .upgradeCopy)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try encodeReasoningEffortMapping(reasoningEffortMapping, into: &container, forKey: .reasoningEffortMapping)
        try container.encode(migrationConfigKey, forKey: .migrationConfigKey)
        try encodeNullingOptional(modelLink, into: &container, forKey: .modelLink)
        try encodeNullingOptional(upgradeCopy, into: &container, forKey: .upgradeCopy)
    }
}

public struct ModelPreset: Equatable, Sendable {
    public let id: String
    public let model: String
    public let displayName: String
    public let description: String
    public let defaultReasoningEffort: ReasoningEffort
    public let supportedReasoningEfforts: [ReasoningEffortPreset]
    public let isDefault: Bool
    public let upgrade: ModelUpgrade?
    public let showInPicker: Bool
    public let supportedInAPI: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case model
        case displayName = "display_name"
        case description
        case defaultReasoningEffort = "default_reasoning_effort"
        case supportedReasoningEfforts = "supported_reasoning_efforts"
        case isDefault = "is_default"
        case upgrade
        case showInPicker = "show_in_picker"
        case supportedInAPI = "supported_in_api"
    }

    public init(
        id: String,
        model: String,
        displayName: String,
        description: String,
        defaultReasoningEffort: ReasoningEffort,
        supportedReasoningEfforts: [ReasoningEffortPreset],
        isDefault: Bool,
        upgrade: ModelUpgrade? = nil,
        showInPicker: Bool,
        supportedInAPI: Bool
    ) {
        self.id = id
        self.model = model
        self.displayName = displayName
        self.description = description
        self.defaultReasoningEffort = defaultReasoningEffort
        self.supportedReasoningEfforts = supportedReasoningEfforts
        self.isDefault = isDefault
        self.upgrade = upgrade
        self.showInPicker = showInPicker
        self.supportedInAPI = supportedInAPI
    }

    public init(modelInfo info: ModelInfo) {
        self.init(
            id: info.slug,
            model: info.slug,
            displayName: info.displayName,
            description: info.description ?? "",
            defaultReasoningEffort: info.defaultReasoningLevel,
            supportedReasoningEfforts: info.supportedReasoningLevels,
            isDefault: false,
            upgrade: info.upgrade.map { upgradeSlug in
                ModelUpgrade(
                    id: upgradeSlug,
                    reasoningEffortMapping: Self.reasoningEffortMapping(from: info.supportedReasoningLevels),
                    migrationConfigKey: info.slug
                )
            },
            showInPicker: info.visibility == .list,
            supportedInAPI: info.supportedInAPI
        )
    }

    private static func reasoningEffortMapping(
        from presets: [ReasoningEffortPreset]
    ) -> [ReasoningEffort: ReasoningEffort]? {
        let supported = presets.map(\.effort)
        guard !supported.isEmpty else {
            return nil
        }

        return ReasoningEffort.allCases.reduce(into: [:]) { result, effort in
            result[effort] = nearestEffort(to: effort, supported: supported)
        }
    }

    private static func nearestEffort(
        to target: ReasoningEffort,
        supported: [ReasoningEffort]
    ) -> ReasoningEffort {
        guard var best = supported.first else {
            return target
        }

        var bestDistance = abs(best.rank - target.rank)
        for candidate in supported.dropFirst() {
            let distance = abs(candidate.rank - target.rank)
            if distance < bestDistance {
                best = candidate
                bestDistance = distance
            }
        }
        return best
    }
}

extension ModelPreset: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.model = try container.decode(String.self, forKey: .model)
        self.displayName = try container.decode(String.self, forKey: .displayName)
        self.description = try container.decode(String.self, forKey: .description)
        self.defaultReasoningEffort = try container.decode(ReasoningEffort.self, forKey: .defaultReasoningEffort)
        self.supportedReasoningEfforts = try container.decode(
            [ReasoningEffortPreset].self,
            forKey: .supportedReasoningEfforts
        )
        self.isDefault = try container.decode(Bool.self, forKey: .isDefault)
        self.upgrade = try container.decodeIfPresent(ModelUpgrade.self, forKey: .upgrade)
        self.showInPicker = try container.decode(Bool.self, forKey: .showInPicker)
        self.supportedInAPI = try container.decode(Bool.self, forKey: .supportedInAPI)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(model, forKey: .model)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(description, forKey: .description)
        try container.encode(defaultReasoningEffort, forKey: .defaultReasoningEffort)
        try container.encode(supportedReasoningEfforts, forKey: .supportedReasoningEfforts)
        try container.encode(isDefault, forKey: .isDefault)
        try encodeNullingOptional(upgrade, into: &container, forKey: .upgrade)
        try container.encode(showInPicker, forKey: .showInPicker)
        try container.encode(supportedInAPI, forKey: .supportedInAPI)
    }
}

public enum ModelVisibility: String, Codable, CaseIterable, Equatable, Sendable {
    case list
    case hide
    case none
}

public enum TruncationMode: String, Codable, CaseIterable, Equatable, Sendable {
    case bytes
    case tokens
}

public struct TruncationPolicyConfig: Equatable, Codable, Sendable {
    public let mode: TruncationMode
    public let limit: Int64

    public init(mode: TruncationMode, limit: Int64) {
        self.mode = mode
        self.limit = limit
    }

    public static func bytes(_ limit: Int64) -> TruncationPolicyConfig {
        TruncationPolicyConfig(mode: .bytes, limit: limit)
    }

    public static func tokens(_ limit: Int64) -> TruncationPolicyConfig {
        TruncationPolicyConfig(mode: .tokens, limit: limit)
    }
}

public struct ClientVersion: Equatable, Codable, Sendable {
    public let major: Int32
    public let minor: Int32
    public let patch: Int32

    public init(_ major: Int32, _ minor: Int32, _ patch: Int32) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.major = try container.decode(Int32.self)
        self.minor = try container.decode(Int32.self)
        self.patch = try container.decode(Int32.self)
        guard container.isAtEnd else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected three version parts")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(major)
        try container.encode(minor)
        try container.encode(patch)
    }
}

public struct ModelInfo: Equatable, Sendable {
    public let slug: String
    public let displayName: String
    public let description: String?
    public let defaultReasoningLevel: ReasoningEffort
    public let supportedReasoningLevels: [ReasoningEffortPreset]
    public let shellType: ConfigShellToolType
    public let visibility: ModelVisibility
    public let supportedInAPI: Bool
    public let priority: Int32
    public let upgrade: String?
    public let baseInstructions: String?
    public let supportsReasoningSummaries: Bool
    public let supportVerbosity: Bool
    public let defaultVerbosity: Verbosity?
    public let applyPatchToolType: ApplyPatchToolType?
    public let truncationPolicy: TruncationPolicyConfig
    public let supportsParallelToolCalls: Bool
    public let contextWindow: Int64?
    public let experimentalSupportedTools: [String]

    private enum CodingKeys: String, CodingKey {
        case slug
        case displayName = "display_name"
        case description
        case defaultReasoningLevel = "default_reasoning_level"
        case supportedReasoningLevels = "supported_reasoning_levels"
        case shellType = "shell_type"
        case visibility
        case supportedInAPI = "supported_in_api"
        case priority
        case upgrade
        case baseInstructions = "base_instructions"
        case supportsReasoningSummaries = "supports_reasoning_summaries"
        case supportVerbosity = "support_verbosity"
        case defaultVerbosity = "default_verbosity"
        case applyPatchToolType = "apply_patch_tool_type"
        case truncationPolicy = "truncation_policy"
        case supportsParallelToolCalls = "supports_parallel_tool_calls"
        case contextWindow = "context_window"
        case experimentalSupportedTools = "experimental_supported_tools"
    }

    public init(
        slug: String,
        displayName: String,
        description: String? = nil,
        defaultReasoningLevel: ReasoningEffort,
        supportedReasoningLevels: [ReasoningEffortPreset],
        shellType: ConfigShellToolType,
        visibility: ModelVisibility,
        supportedInAPI: Bool,
        priority: Int32,
        upgrade: String? = nil,
        baseInstructions: String? = nil,
        supportsReasoningSummaries: Bool,
        supportVerbosity: Bool,
        defaultVerbosity: Verbosity? = nil,
        applyPatchToolType: ApplyPatchToolType? = nil,
        truncationPolicy: TruncationPolicyConfig,
        supportsParallelToolCalls: Bool,
        contextWindow: Int64? = nil,
        experimentalSupportedTools: [String]
    ) {
        self.slug = slug
        self.displayName = displayName
        self.description = description
        self.defaultReasoningLevel = defaultReasoningLevel
        self.supportedReasoningLevels = supportedReasoningLevels
        self.shellType = shellType
        self.visibility = visibility
        self.supportedInAPI = supportedInAPI
        self.priority = priority
        self.upgrade = upgrade
        self.baseInstructions = baseInstructions
        self.supportsReasoningSummaries = supportsReasoningSummaries
        self.supportVerbosity = supportVerbosity
        self.defaultVerbosity = defaultVerbosity
        self.applyPatchToolType = applyPatchToolType
        self.truncationPolicy = truncationPolicy
        self.supportsParallelToolCalls = supportsParallelToolCalls
        self.contextWindow = contextWindow
        self.experimentalSupportedTools = experimentalSupportedTools
    }

    public var preset: ModelPreset {
        ModelPreset(modelInfo: self)
    }
}

extension ModelInfo: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.slug = try container.decode(String.self, forKey: .slug)
        self.displayName = try container.decode(String.self, forKey: .displayName)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.defaultReasoningLevel = try container.decode(ReasoningEffort.self, forKey: .defaultReasoningLevel)
        self.supportedReasoningLevels = try container.decode(
            [ReasoningEffortPreset].self,
            forKey: .supportedReasoningLevels
        )
        self.shellType = try container.decode(ConfigShellToolType.self, forKey: .shellType)
        self.visibility = try container.decode(ModelVisibility.self, forKey: .visibility)
        self.supportedInAPI = try container.decode(Bool.self, forKey: .supportedInAPI)
        self.priority = try container.decode(Int32.self, forKey: .priority)
        self.upgrade = try container.decodeIfPresent(String.self, forKey: .upgrade)
        self.baseInstructions = try container.decodeIfPresent(String.self, forKey: .baseInstructions)
        self.supportsReasoningSummaries = try container.decode(Bool.self, forKey: .supportsReasoningSummaries)
        self.supportVerbosity = try container.decode(Bool.self, forKey: .supportVerbosity)
        self.defaultVerbosity = try container.decodeIfPresent(Verbosity.self, forKey: .defaultVerbosity)
        self.applyPatchToolType = try container.decodeIfPresent(ApplyPatchToolType.self, forKey: .applyPatchToolType)
        self.truncationPolicy = try container.decode(TruncationPolicyConfig.self, forKey: .truncationPolicy)
        self.supportsParallelToolCalls = try container.decode(Bool.self, forKey: .supportsParallelToolCalls)
        self.contextWindow = try container.decodeIfPresent(Int64.self, forKey: .contextWindow)
        self.experimentalSupportedTools = try container.decode([String].self, forKey: .experimentalSupportedTools)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(slug, forKey: .slug)
        try container.encode(displayName, forKey: .displayName)
        try encodeNullingOptional(description, into: &container, forKey: .description)
        try container.encode(defaultReasoningLevel, forKey: .defaultReasoningLevel)
        try container.encode(supportedReasoningLevels, forKey: .supportedReasoningLevels)
        try container.encode(shellType, forKey: .shellType)
        try container.encode(visibility, forKey: .visibility)
        try container.encode(supportedInAPI, forKey: .supportedInAPI)
        try container.encode(priority, forKey: .priority)
        try encodeNullingOptional(upgrade, into: &container, forKey: .upgrade)
        try encodeNullingOptional(baseInstructions, into: &container, forKey: .baseInstructions)
        try container.encode(supportsReasoningSummaries, forKey: .supportsReasoningSummaries)
        try container.encode(supportVerbosity, forKey: .supportVerbosity)
        try encodeNullingOptional(defaultVerbosity, into: &container, forKey: .defaultVerbosity)
        try encodeNullingOptional(applyPatchToolType, into: &container, forKey: .applyPatchToolType)
        try container.encode(truncationPolicy, forKey: .truncationPolicy)
        try container.encode(supportsParallelToolCalls, forKey: .supportsParallelToolCalls)
        try encodeNullingOptional(contextWindow, into: &container, forKey: .contextWindow)
        try container.encode(experimentalSupportedTools, forKey: .experimentalSupportedTools)
    }
}

public struct ModelsResponse: Equatable, Sendable {
    public let models: [ModelInfo]
    public let etag: String

    private enum CodingKeys: String, CodingKey {
        case models
        case etag
    }

    public init(models: [ModelInfo] = [], etag: String = "") {
        self.models = models
        self.etag = etag
    }
}

extension ModelsResponse: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.models = try container.decode([ModelInfo].self, forKey: .models)
        self.etag = container.contains(.etag) ? try container.decode(String.self, forKey: .etag) : ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(models, forKey: .models)
        try container.encode(etag, forKey: .etag)
    }
}

extension ReasoningEffort {
    fileprivate var rank: Int {
        switch self {
        case .none:
            return 0
        case .minimal:
            return 1
        case .low:
            return 2
        case .medium:
            return 3
        case .high:
            return 4
        case .xhigh:
            return 5
        }
    }
}

private func decodeReasoningEffortMapping<K: CodingKey>(
    from container: KeyedDecodingContainer<K>,
    forKey key: K
) throws -> [ReasoningEffort: ReasoningEffort]? {
    guard container.contains(key), try !container.decodeNil(forKey: key) else {
        return nil
    }

    let rawMapping = try container.decode([String: ReasoningEffort].self, forKey: key)
    return try rawMapping.reduce(into: [:]) { result, entry in
        guard let effort = ReasoningEffort(rawValue: entry.key) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath + [key],
                    debugDescription: "Unsupported reasoning effort key: \(entry.key)"
                )
            )
        }
        result[effort] = entry.value
    }
}

private func encodeReasoningEffortMapping<K: CodingKey>(
    _ mapping: [ReasoningEffort: ReasoningEffort]?,
    into container: inout KeyedEncodingContainer<K>,
    forKey key: K
) throws {
    guard let mapping else {
        try container.encodeNil(forKey: key)
        return
    }

    let rawMapping = mapping.reduce(into: [String: ReasoningEffort]()) { result, entry in
        result[entry.key.rawValue] = entry.value
    }
    try container.encode(rawMapping, forKey: key)
}

private func encodeNullingOptional<T: Encodable, K: CodingKey>(
    _ value: T?,
    into container: inout KeyedEncodingContainer<K>,
    forKey key: K
) throws {
    if let value {
        try container.encode(value, forKey: key)
    } else {
        try container.encodeNil(forKey: key)
    }
}
