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
