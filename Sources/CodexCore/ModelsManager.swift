import Foundation

public struct ModelsCache: Equatable, Sendable {
    public let fetchedAt: Date
    public let etag: String?
    public let clientVersion: String?
    public let models: [ModelInfo]

    private enum CodingKeys: String, CodingKey {
        case fetchedAt = "fetched_at"
        case etag
        case clientVersion = "client_version"
        case models
    }

    public init(fetchedAt: Date, etag: String? = nil, clientVersion: String? = nil, models: [ModelInfo]) {
        self.fetchedAt = fetchedAt
        self.etag = etag
        self.clientVersion = clientVersion
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
        self.clientVersion = try container.decodeIfPresent(String.self, forKey: .clientVersion)
        self.models = try container.decode([ModelInfo].self, forKey: .models)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.formatDate(fetchedAt), forKey: .fetchedAt)
        try container.encodeIfPresent(etag, forKey: .etag)
        try container.encodeIfPresent(clientVersion, forKey: .clientVersion)
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

public enum ModelsETagRefreshOutcome: Equatable, Sendable {
    case skipped
    case renewedCache
    case refreshedCache
    case refreshFailed
}

public enum ModelsManager {
    public static let hideGPT51MigrationPromptConfig = "hide_gpt5_1_migration_prompt"
    public static let hideGPT51CodexMaxMigrationPromptConfig = "hide_gpt-5.1-codex-max_migration_prompt"
    public static let modelCacheFile = "models_cache.json"
    public static let defaultModelCacheTTL: TimeInterval = 300
    public static let openAIDefaultAPIModel = "gpt-5.5"
    public static let openAIDefaultChatGPTModel = "gpt-5.5"
    public static let codexAutoBalancedModel = "codex-auto-balanced"
    public static let amazonBedrockDefaultModel = "openai.gpt-5.4"

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

    public static func formatClientVersion(packageVersion: String) -> String {
        let coreVersion = packageVersion.split(
            maxSplits: 1,
            omittingEmptySubsequences: false,
            whereSeparator: { $0 == "-" || $0 == "+" }
        ).first
            .map(String.init) ?? packageVersion
        let parts = coreVersion.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        return formatClientVersion(
            major: parts.indices.contains(0) ? parts[0] : "0",
            minor: parts.indices.contains(1) ? parts[1] : "0",
            patch: parts.indices.contains(2) ? parts[2] : "0"
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
        mergedPresets = filterByAuth(mergedPresets, chatGPTMode: chatGPTMode)
        markDefaultByPickerVisibility(&mergedPresets)
        return mergedPresets
    }

    public static func filterVisibleModels(_ models: [ModelPreset], chatGPTMode: Bool) -> [ModelPreset] {
        filterByAuth(models, chatGPTMode: chatGPTMode).filter(\.showInPicker)
    }

    public static func filterByAuth(_ models: [ModelPreset], chatGPTMode: Bool) -> [ModelPreset] {
        models.filter { model in
            chatGPTMode || model.supportedInAPI
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
        if let defaultModel = availableModels.first(where: \.isDefault) {
            return defaultModel.model
        }
        if let firstModel = availableModels.first {
            return firstModel.model
        }
        return ""
    }

    public static func offlineModel(explicitModel: String?) -> String {
        explicitModel ?? openAIDefaultChatGPTModel
    }

    public static func builtinModelPresets(authMode: AuthMode? = nil) -> [ModelPreset] {
        filterByAuth(allModelPresets, chatGPTMode: authMode?.isChatGPT == true)
    }

    public static var allModelPresets: [ModelPreset] {
        var presets = bundledModels
            .sorted { $0.priority < $1.priority }
            .map(\.preset)
        markDefaultByPickerVisibility(&presets)
        return presets
    }

    public static var bundledModels: [ModelInfo] {
        do {
            return try bundledModelsResponse().models
        } catch {
            preconditionFailure("Unable to load bundled models.json: \(error)")
        }
    }

    public static func bundledModelsResponse(decoder: JSONDecoder = JSONDecoder()) throws -> ModelsResponse {
        guard let url = Bundle.module.url(forResource: "models", withExtension: "json") else {
            preconditionFailure("Missing bundled models.json resource")
        }
        return try decoder.decode(ModelsResponse.self, from: Data(contentsOf: url))
    }

    public static func amazonBedrockStaticModelCatalog() -> ModelsResponse {
        ModelsResponse(models: [
            amazonBedrockGPT54Model(priority: 0),
            amazonBedrockOSSModel(
                slug: "openai.gpt-oss-120b",
                displayName: "GPT OSS 120B on Bedrock",
                priority: 1
            ),
            amazonBedrockOSSModel(
                slug: "openai.gpt-oss-20b",
                displayName: "GPT OSS 20B on Bedrock",
                priority: 2
            )
        ])
    }

    public static func rawModelCatalogOnlineIfUncached<Transport: APITransport>(
        codexHome: URL,
        config: CodexRuntimeConfig,
        auth: AuthDotJSON?,
        transport: Transport,
        clientVersion: String,
        commandAuthRunner: ProviderAuthCommandRunner = ProviderAuthCommandRunner(),
        now: Date = Date(),
        cacheTTL: TimeInterval = defaultModelCacheTTL
    ) async throws -> ModelsResponse {
        if let modelCatalog = config.modelCatalog {
            return modelCatalog
        }

        let providerInfo = selectedProviderInfo(for: config)
        if providerInfo.isAmazonBedrock() {
            return amazonBedrockStaticModelCatalog()
        }

        let apiProvider = providerInfo.toAPIProvider(authMode: auth?.authMode)
        let authProvider = try await APIAuthResolver.authProvider(
            auth: auth,
            provider: providerInfo,
            commandRunner: commandAuthRunner
        )
        let cacheURL = cachePath(codexHome: codexHome)
        let fallbackModels = bundledModels

        if let cached = try ModelsCache.load(from: cacheURL),
           cached.clientVersion == clientVersion,
           cached.isFresh(ttl: cacheTTL, now: now) {
            return ModelsResponse(
                models: mergedRawModels(remoteModels: cached.models, existingModels: fallbackModels),
                etag: cached.etag ?? ""
            )
        }

        guard shouldRefreshRawModels(providerInfo: providerInfo, provider: apiProvider) else {
            return ModelsResponse(models: fallbackModels)
        }

        let client = ModelsClient(
            transport: transport,
            provider: apiProvider,
            auth: authProvider
        )
        switch await client.listModels(clientVersion: clientVersion) {
        case let .success(response):
            let cache = ModelsCache(
                fetchedAt: now,
                etag: response.etag.isEmpty ? nil : response.etag,
                clientVersion: clientVersion,
                models: response.models
            )
            try cache.save(to: cacheURL)
            return ModelsResponse(
                models: mergedRawModels(remoteModels: response.models, existingModels: fallbackModels),
                etag: response.etag
            )
        case .failure:
            return ModelsResponse(models: fallbackModels)
        }
    }

    public static func refreshCachedModelsIfNewETag<Transport: APITransport, Auth: APIAuthProvider>(
        codexHome: URL,
        config: CodexRuntimeConfig,
        provider: APIProvider,
        auth: Auth,
        transport: Transport,
        clientVersion: String,
        modelsETag: String,
        now: Date = Date()
    ) async throws -> ModelsETagRefreshOutcome {
        if config.modelCatalog != nil {
            return .skipped
        }

        let providerInfo = selectedProviderInfo(for: config)
        if providerInfo.isAmazonBedrock() {
            return .skipped
        }

        let cacheURL = cachePath(codexHome: codexHome)
        if let cached = try ModelsCache.load(from: cacheURL),
           cached.clientVersion == clientVersion,
           cached.etag == modelsETag {
            try ModelsCache(
                fetchedAt: now,
                etag: cached.etag,
                clientVersion: cached.clientVersion,
                models: cached.models
            ).save(to: cacheURL)
            return .renewedCache
        }

        guard shouldRefreshRawModels(providerInfo: providerInfo, provider: provider) else {
            return .skipped
        }

        let client = ModelsClient(
            transport: transport,
            provider: provider,
            auth: auth
        )
        switch await client.listModels(clientVersion: clientVersion) {
        case let .success(response):
            let cache = ModelsCache(
                fetchedAt: now,
                etag: response.etag.isEmpty ? nil : response.etag,
                clientVersion: clientVersion,
                models: response.models
            )
            try cache.save(to: cacheURL)
            return .refreshedCache
        case .failure:
            return .refreshFailed
        }
    }

    public static func markDefaultByPickerVisibility(_ models: inout [ModelPreset]) {
        for index in models.indices {
            models[index] = models[index].withIsDefault(false)
        }
        if let defaultIndex = models.firstIndex(where: \.showInPicker) ?? models.indices.first {
            models[defaultIndex] = models[defaultIndex].withIsDefault(true)
        }
    }

    private static func shouldRefreshRawModels(
        providerInfo: ModelProviderInfo,
        provider: APIProvider
    ) -> Bool {
        provider.baseURL.contains("/backend-api/codex") || providerInfo.hasCommandAuth()
    }

    private static func selectedProviderInfo(for config: CodexRuntimeConfig) -> ModelProviderInfo {
        if let providerInfo = config.selectedModelProvider {
            return providerInfo
        }
        if let providerInfo = ModelProviderInfo.builtInModelProviders()[config.selectedModelProviderID] {
            return providerInfo
        }
        return ModelProviderInfo.createOpenAIProvider()
    }

    private static func mergedRawModels(
        remoteModels: [ModelInfo],
        existingModels: [ModelInfo]
    ) -> [ModelInfo] {
        var models = existingModels
        for remoteModel in remoteModels {
            if let index = models.firstIndex(where: { $0.slug == remoteModel.slug }) {
                models[index] = remoteModel
            } else {
                models.append(remoteModel)
            }
        }
        return models
    }

    private static func amazonBedrockGPT54Model(priority: Int32) -> ModelInfo {
        ModelInfo(
            slug: amazonBedrockDefaultModel,
            displayName: "gpt-5.4",
            description: "Strong model for everyday coding.",
            defaultReasoningLevel: .medium,
            supportedReasoningLevels: [
                reasoningEffortPreset(.minimal),
                reasoningEffortPreset(.low),
                reasoningEffortPreset(.medium),
                reasoningEffortPreset(.high)
            ],
            shellType: .shellCommand,
            visibility: .list,
            supportedInAPI: true,
            priority: priority,
            serviceTiers: [
                ModelServiceTier(
                    id: ServiceTier.fast.requestValue,
                    name: "fast",
                    description: "Fastest inference with increased plan usage"
                )
            ],
            baseInstructions: ModelFamily.defaultBaseInstructions,
            supportsReasoningSummaries: true,
            defaultReasoningSummary: .none,
            supportVerbosity: true,
            defaultVerbosity: .medium,
            applyPatchToolType: .freeform,
            webSearchToolType: .textAndImage,
            truncationPolicy: .tokens(10_000),
            supportsParallelToolCalls: true,
            supportsImageDetailOriginal: true,
            contextWindow: 272_000,
            maxContextWindow: 1_000_000,
            experimentalSupportedTools: [],
            inputModalities: [.text, .image],
            supportsSearchTool: true
        )
    }

    private static func amazonBedrockOSSModel(slug: String, displayName: String, priority: Int32) -> ModelInfo {
        ModelInfo(
            slug: slug,
            displayName: displayName,
            description: displayName,
            defaultReasoningLevel: .medium,
            supportedReasoningLevels: [
                reasoningEffortPreset(.low),
                reasoningEffortPreset(.medium),
                reasoningEffortPreset(.high)
            ],
            shellType: .shellCommand,
            visibility: .list,
            supportedInAPI: true,
            priority: priority,
            baseInstructions: ModelFamily.defaultBaseInstructions,
            supportsReasoningSummaries: true,
            defaultReasoningSummary: .none,
            supportVerbosity: false,
            defaultVerbosity: nil,
            applyPatchToolType: nil,
            webSearchToolType: .text,
            truncationPolicy: .tokens(10_000),
            supportsParallelToolCalls: true,
            supportsImageDetailOriginal: false,
            contextWindow: 128_000,
            maxContextWindow: 128_000,
            experimentalSupportedTools: [],
            inputModalities: [.text],
            supportsSearchTool: false
        )
    }

    private static func reasoningEffortPreset(_ effort: ReasoningEffort) -> ReasoningEffortPreset {
        ReasoningEffortPreset(effort: effort, description: reasoningEffortDescription(effort))
    }

    private static func reasoningEffortDescription(_ effort: ReasoningEffort) -> String {
        switch effort {
        case .none:
            return "No reasoning"
        case .minimal:
            return "Minimal reasoning"
        case .low:
            return "Fast responses with lighter reasoning"
        case .medium:
            return "Balances speed and reasoning depth for everyday tasks"
        case .high:
            return "Greater reasoning depth for complex problems"
        case .xhigh:
            return "Extra high reasoning depth for complex problems"
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
            supportsPersonality: supportsPersonality,
            additionalSpeedTiers: additionalSpeedTiers,
            serviceTiers: serviceTiers,
            isDefault: isDefault,
            upgrade: upgrade,
            showInPicker: showInPicker,
            availabilityNux: availabilityNux,
            supportedInAPI: supportedInAPI,
            inputModalities: inputModalities
        )
    }
}
