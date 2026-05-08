import Foundation

public struct ModelsCache: Equatable, Sendable {
    public let fetchedAt: Date
    public let etag: String?
    public let models: [ModelInfo]

    private enum CodingKeys: String, CodingKey {
        case fetchedAt = "fetched_at"
        case etag
        case models
    }

    public init(fetchedAt: Date, etag: String? = nil, models: [ModelInfo]) {
        self.fetchedAt = fetchedAt
        self.etag = etag
        self.models = models
    }

    public func isFresh(ttl: TimeInterval, now: Date = Date()) -> Bool {
        guard ttl > 0 else {
            return false
        }
        return now.timeIntervalSince(fetchedAt) <= ttl
    }

    public static func load(from url: URL, decoder: JSONDecoder = JSONDecoder()) throws -> ModelsCache? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(ModelsCache.self, from: data)
    }

    public static func save(
        _ cache: ModelsCache,
        to url: URL,
        fileManager: FileManager = .default,
        encoder: JSONEncoder? = nil
    ) throws {
        if url.path != url.deletingLastPathComponent().path {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }
        let data = try (encoder ?? ModelsCache.makePrettyEncoder()).encode(cache)
        try data.write(to: url)
    }

    public func save(
        to url: URL,
        fileManager: FileManager = .default,
        encoder: JSONEncoder? = nil
    ) throws {
        try Self.save(self, to: url, fileManager: fileManager, encoder: encoder)
    }
}

extension ModelsCache: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawFetchedAt = try container.decode(String.self, forKey: .fetchedAt)
        guard let fetchedAt = Self.parseDate(rawFetchedAt) else {
            throw DecodingError.dataCorruptedError(
                forKey: .fetchedAt,
                in: container,
                debugDescription: "Invalid RFC3339 timestamp: \(rawFetchedAt)"
            )
        }

        self.fetchedAt = fetchedAt
        self.etag = try container.decodeIfPresent(String.self, forKey: .etag)
        self.models = try container.decode([ModelInfo].self, forKey: .models)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.formatDate(fetchedAt), forKey: .fetchedAt)
        try container.encodeIfPresent(etag, forKey: .etag)
        try container.encode(models, forKey: .models)
    }

    private static func parseDate(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func makePrettyEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        return encoder
    }
}

public enum ModelsManager {
    public static let hideGPT51MigrationPromptConfig = "hide_gpt5_1_migration_prompt"
    public static let hideGPT51CodexMaxMigrationPromptConfig = "hide_gpt-5.1-codex-max_migration_prompt"
    public static let modelCacheFile = "models_cache.json"
    public static let defaultModelCacheTTL: TimeInterval = 300
    public static let openAIDefaultAPIModel = "gpt-5.1-codex-max"
    public static let openAIDefaultChatGPTModel = "gpt-5.2-codex"
    public static let codexAutoBalancedModel = "codex-auto-balanced"

    public static func cachePath(codexHome: URL) -> URL {
        codexHome.appendingPathComponent(modelCacheFile, isDirectory: false)
    }

    public static func formatClientVersion(major: String, minor: String, patch: String) -> String {
        let normalized = "\(major).\(minor).\(patch)"
        return normalized == "0.0.0" ? "99.99.99" : normalized
    }

    public static func formatClientVersion(_ version: ClientVersion) -> String {
        formatClientVersion(
            major: "\(version.major)",
            minor: "\(version.minor)",
            patch: "\(version.patch)"
        )
    }

    public static func buildAvailableModels(
        remoteModels: [ModelInfo],
        localModels: [ModelPreset],
        chatGPTMode: Bool
    ) -> [ModelPreset] {
        let remotePresets = remoteModels
            .sorted { $0.priority < $1.priority }
            .map(\.preset)
        var mergedPresets = mergePresets(remotePresets: remotePresets, existingPresets: localModels)
        mergedPresets = filterVisibleModels(mergedPresets, chatGPTMode: chatGPTMode)

        guard !mergedPresets.contains(where: \.isDefault),
              let first = mergedPresets.first
        else {
            return mergedPresets
        }

        mergedPresets[0] = first.withIsDefault(true)
        return mergedPresets
    }

    public static func filterVisibleModels(_ models: [ModelPreset], chatGPTMode: Bool) -> [ModelPreset] {
        models.filter { model in
            model.showInPicker && (chatGPTMode || model.supportedInAPI)
        }
    }

    public static func mergePresets(
        remotePresets: [ModelPreset],
        existingPresets: [ModelPreset]
    ) -> [ModelPreset] {
        guard !remotePresets.isEmpty else {
            return existingPresets
        }

        let remoteSlugs = Set(remotePresets.map(\.model))
        let preservedExisting = existingPresets.compactMap { preset -> ModelPreset? in
            guard !remoteSlugs.contains(preset.model) else {
                return nil
            }
            return preset.withIsDefault(false)
        }
        return remotePresets + preservedExisting
    }

    public static func defaultModel(
        explicitModel: String?,
        isChatGPT: Bool,
        availableModels: [ModelPreset]
    ) -> String {
        if let explicitModel {
            return explicitModel
        }
        if isChatGPT {
            if availableModels.contains(where: { $0.model == codexAutoBalancedModel }) {
                return codexAutoBalancedModel
            }
            return openAIDefaultChatGPTModel
        }
        return openAIDefaultAPIModel
    }

    public static func offlineModel(explicitModel: String?) -> String {
        explicitModel ?? openAIDefaultChatGPTModel
    }

    public static func builtinModelPresets(authMode _: AuthMode? = nil) -> [ModelPreset] {
        allModelPresets.filter(\.showInPicker)
    }

    public static var allModelPresets: [ModelPreset] {
        [
            ModelPreset(
                id: "gpt-5.2-codex",
                model: "gpt-5.2-codex",
                displayName: "gpt-5.2-codex",
                description: "Latest frontier agentic coding model.",
                defaultReasoningEffort: .medium,
                supportedReasoningEfforts: codex52Efforts,
                isDefault: true,
                upgrade: nil,
                showInPicker: true,
                supportedInAPI: false
            ),
            ModelPreset(
                id: "gpt-5.1-codex-max",
                model: "gpt-5.1-codex-max",
                displayName: "gpt-5.1-codex-max",
                description: "Codex-optimized flagship for deep and fast reasoning.",
                defaultReasoningEffort: .medium,
                supportedReasoningEfforts: codex52Efforts,
                isDefault: false,
                upgrade: gpt52CodexUpgrade,
                showInPicker: true,
                supportedInAPI: true
            ),
            ModelPreset(
                id: "gpt-5.1-codex-mini",
                model: "gpt-5.1-codex-mini",
                displayName: "gpt-5.1-codex-mini",
                description: "Optimized for codex. Cheaper, faster, but less capable.",
                defaultReasoningEffort: .medium,
                supportedReasoningEfforts: codexMiniEfforts,
                isDefault: false,
                upgrade: gpt52CodexUpgrade,
                showInPicker: true,
                supportedInAPI: true
            ),
            ModelPreset(
                id: "gpt-5.2",
                model: "gpt-5.2",
                displayName: "gpt-5.2",
                description: "Latest frontier model with improvements across knowledge, reasoning and coding",
                defaultReasoningEffort: .medium,
                supportedReasoningEfforts: gpt52Efforts,
                isDefault: false,
                upgrade: gpt52CodexUpgrade,
                showInPicker: true,
                supportedInAPI: true
            ),
            ModelPreset(
                id: "bengalfox",
                model: "bengalfox",
                displayName: "bengalfox",
                description: "bengalfox",
                defaultReasoningEffort: .medium,
                supportedReasoningEfforts: codex52Efforts,
                isDefault: false,
                upgrade: nil,
                showInPicker: false,
                supportedInAPI: true
            ),
            ModelPreset(
                id: "boomslang",
                model: "boomslang",
                displayName: "boomslang",
                description: "boomslang",
                defaultReasoningEffort: .medium,
                supportedReasoningEfforts: gpt52Efforts,
                isDefault: false,
                upgrade: nil,
                showInPicker: false,
                supportedInAPI: true
            ),
            ModelPreset(
                id: "gpt-5-codex",
                model: "gpt-5-codex",
                displayName: "gpt-5-codex",
                description: "Optimized for codex.",
                defaultReasoningEffort: .medium,
                supportedReasoningEfforts: legacyCodexEfforts,
                isDefault: false,
                upgrade: gpt52CodexUpgrade,
                showInPicker: false,
                supportedInAPI: true
            ),
            ModelPreset(
                id: "gpt-5-codex-mini",
                model: "gpt-5-codex-mini",
                displayName: "gpt-5-codex-mini",
                description: "Optimized for codex. Cheaper, faster, but less capable.",
                defaultReasoningEffort: .medium,
                supportedReasoningEfforts: codexMiniEfforts,
                isDefault: false,
                upgrade: gpt52CodexUpgrade,
                showInPicker: false,
                supportedInAPI: true
            ),
            ModelPreset(
                id: "gpt-5.1-codex",
                model: "gpt-5.1-codex",
                displayName: "gpt-5.1-codex",
                description: "Optimized for codex.",
                defaultReasoningEffort: .medium,
                supportedReasoningEfforts: legacyCodexEfforts,
                isDefault: false,
                upgrade: gpt52CodexUpgrade,
                showInPicker: false,
                supportedInAPI: true
            ),
            ModelPreset(
                id: "gpt-5",
                model: "gpt-5",
                displayName: "gpt-5",
                description: "Broad world knowledge with strong general reasoning.",
                defaultReasoningEffort: .medium,
                supportedReasoningEfforts: gpt5Efforts,
                isDefault: false,
                upgrade: gpt52CodexUpgrade,
                showInPicker: false,
                supportedInAPI: true
            ),
            ModelPreset(
                id: "gpt-5.1",
                model: "gpt-5.1",
                displayName: "gpt-5.1",
                description: "Broad world knowledge with strong general reasoning.",
                defaultReasoningEffort: .medium,
                supportedReasoningEfforts: gpt51Efforts,
                isDefault: false,
                upgrade: gpt52CodexUpgrade,
                showInPicker: false,
                supportedInAPI: true
            )
        ]
    }

    private static var gpt52CodexUpgrade: ModelUpgrade {
        ModelUpgrade(
            id: "gpt-5.2-codex",
            reasoningEffortMapping: nil,
            migrationConfigKey: "gpt-5.2-codex",
            modelLink: "https://openai.com/index/introducing-gpt-5-2-codex",
            upgradeCopy: "Codex is now powered by gpt-5.2-codex, our latest frontier agentic coding model. It is smarter and faster than its predecessors and capable of long-running project-scale work."
        )
    }

    private static var codex52Efforts: [ReasoningEffortPreset] {
        efforts([
            (.low, "Fast responses with lighter reasoning"),
            (.medium, "Balances speed and reasoning depth for everyday tasks"),
            (.high, "Greater reasoning depth for complex problems"),
            (.xhigh, "Extra high reasoning depth for complex problems")
        ])
    }

    private static var gpt52Efforts: [ReasoningEffortPreset] {
        efforts([
            (.low, "Balances speed with some reasoning; useful for straightforward queries and short explanations"),
            (.medium, "Provides a solid balance of reasoning depth and latency for general-purpose tasks"),
            (.high, "Maximizes reasoning depth for complex or ambiguous problems"),
            (.xhigh, "Extra high reasoning for complex problems")
        ])
    }

    private static var codexMiniEfforts: [ReasoningEffortPreset] {
        efforts([
            (.medium, "Dynamically adjusts reasoning based on the task"),
            (.high, "Maximizes reasoning depth for complex or ambiguous problems")
        ])
    }

    private static var legacyCodexEfforts: [ReasoningEffortPreset] {
        efforts([
            (.low, "Fastest responses with limited reasoning"),
            (.medium, "Dynamically adjusts reasoning based on the task"),
            (.high, "Maximizes reasoning depth for complex or ambiguous problems")
        ])
    }

    private static var gpt5Efforts: [ReasoningEffortPreset] {
        efforts([
            (.minimal, "Fastest responses with little reasoning"),
            (.low, "Balances speed with some reasoning; useful for straightforward queries and short explanations"),
            (.medium, "Provides a solid balance of reasoning depth and latency for general-purpose tasks"),
            (.high, "Maximizes reasoning depth for complex or ambiguous problems")
        ])
    }

    private static var gpt51Efforts: [ReasoningEffortPreset] {
        efforts([
            (.low, "Balances speed with some reasoning; useful for straightforward queries and short explanations"),
            (.medium, "Provides a solid balance of reasoning depth and latency for general-purpose tasks"),
            (.high, "Maximizes reasoning depth for complex or ambiguous problems")
        ])
    }

    private static func efforts(_ entries: [(ReasoningEffort, String)]) -> [ReasoningEffortPreset] {
        entries.map { effort, description in
            ReasoningEffortPreset(effort: effort, description: description)
        }
    }
}

extension ModelPreset {
    public func withIsDefault(_ isDefault: Bool) -> ModelPreset {
        ModelPreset(
            id: id,
            model: model,
            displayName: displayName,
            description: description,
            defaultReasoningEffort: defaultReasoningEffort,
            supportedReasoningEfforts: supportedReasoningEfforts,
            isDefault: isDefault,
            upgrade: upgrade,
            showInPicker: showInPicker,
            supportedInAPI: supportedInAPI
        )
    }
}
