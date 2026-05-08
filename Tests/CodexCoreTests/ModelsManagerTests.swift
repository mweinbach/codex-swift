import CodexCore
import XCTest

final class ModelsManagerTests: XCTestCase {
    func testModelsCacheWireShapeSkipsNilEtagAndAcceptsMissingEtag() throws {
        let cache = ModelsCache(
            fetchedAt: try parseDate("2026-05-08T12:34:56.789Z"),
            etag: nil,
            models: [minimalModelInfo(slug: "codex-mini")]
        )

        let object = try JSONObject(cache)
        XCTAssertEqual(object["fetched_at"] as? String, "2026-05-08T12:34:56.789Z")
        XCTAssertNil(object["etag"])
        XCTAssertEqual((object["models"] as? [[String: Any]])?.first?["slug"] as? String, "codex-mini")

        let decoded = try JSONDecoder().decode(ModelsCache.self, from: Data("""
        {
          "fetched_at": "2026-05-08T12:34:56Z",
          "models": []
        }
        """.utf8))
        XCTAssertNil(decoded.etag)
        XCTAssertEqual(decoded.models, [])
        XCTAssertEqual(decoded.fetchedAt, try parseDate("2026-05-08T12:34:56Z"))
    }

    func testModelsCacheFreshnessMatchesTTLBoundary() throws {
        let fetchedAt = try parseDate("2026-05-08T12:00:00Z")
        let cache = ModelsCache(fetchedAt: fetchedAt, models: [])

        XCTAssertFalse(cache.isFresh(ttl: 0, now: fetchedAt))
        XCTAssertTrue(cache.isFresh(ttl: 300, now: fetchedAt.addingTimeInterval(300)))
        XCTAssertFalse(cache.isFresh(ttl: 300, now: fetchedAt.addingTimeInterval(301)))
    }

    func testModelsCacheFileIOCreatesParentAndReturnsNilForMissingFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let cachePath = root
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent(ModelsManager.modelCacheFile, isDirectory: false)
        XCTAssertNil(try ModelsCache.load(from: cachePath))

        let cache = ModelsCache(
            fetchedAt: try parseDate("2026-05-08T12:34:56.789Z"),
            etag: "W/etag",
            models: [minimalModelInfo(slug: "cached")]
        )

        try cache.save(to: cachePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cachePath.path))
        XCTAssertEqual(try ModelsCache.load(from: cachePath), cache)
    }

    func testModelsCacheLoadThrowsForInvalidJSON() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let path = root.appendingPathComponent(ModelsManager.modelCacheFile, isDirectory: false)
        try Data(#"{"fetched_at":true}"#.utf8).write(to: path)

        XCTAssertThrowsError(try ModelsCache.load(from: path))
    }

    func testClientVersionFormattingUsesDevFallback() {
        XCTAssertEqual(
            ModelsManager.formatClientVersion(major: "0", minor: "0", patch: "0"),
            "99.99.99"
        )
        XCTAssertEqual(
            ModelsManager.formatClientVersion(major: "1", minor: "2", patch: "3"),
            "1.2.3"
        )
        XCTAssertEqual(ModelsManager.formatClientVersion(ClientVersion(0, 62, 0)), "0.62.0")
    }

    func testMergePresetsKeepsExistingOnlyWhenRemoteDoesNotShadowIt() {
        let remote = preset(model: "remote", isDefault: false)
        let duplicate = preset(model: "remote", isDefault: true)
        let existing = preset(model: "existing", isDefault: true)

        XCTAssertEqual(
            ModelsManager.mergePresets(remotePresets: [], existingPresets: [existing]),
            [existing]
        )
        XCTAssertEqual(
            ModelsManager.mergePresets(remotePresets: [remote], existingPresets: [duplicate, existing]),
            [remote, existing.withIsDefault(false)]
        )
    }

    func testBuildAvailableModelsSortsFiltersAndMarksFirstVisibleDefault() {
        let hiddenRemote = minimalModelInfo(
            slug: "hidden",
            visibility: .hide,
            supportedInAPI: true,
            priority: 0
        )
        let visibleRemote = minimalModelInfo(
            slug: "visible",
            visibility: .list,
            supportedInAPI: true,
            priority: 1
        )
        let apiLocal = preset(model: "api-local", isDefault: true, showInPicker: true, supportedInAPI: true)
        let chatGPTOnlyLocal = preset(model: "chatgpt-only", showInPicker: true, supportedInAPI: false)

        let apiModels = ModelsManager.buildAvailableModels(
            remoteModels: [visibleRemote, hiddenRemote],
            localModels: [apiLocal, chatGPTOnlyLocal],
            chatGPTMode: false
        )
        XCTAssertEqual(apiModels.map(\.model), ["visible", "api-local"])
        XCTAssertTrue(apiModels[0].isDefault)
        XCTAssertFalse(apiModels[1].isDefault)

        let chatGPTModels = ModelsManager.buildAvailableModels(
            remoteModels: [],
            localModels: [apiLocal, chatGPTOnlyLocal],
            chatGPTMode: true
        )
        XCTAssertEqual(chatGPTModels.map(\.model), ["api-local", "chatgpt-only"])
        XCTAssertTrue(chatGPTModels[0].isDefault)
    }

    func testBuildAvailableModelsRespectsExistingDefaultAfterFiltering() {
        let first = minimalModelInfo(slug: "first", priority: 0)
        let localDefault = preset(model: "local-default", isDefault: true, showInPicker: true, supportedInAPI: true)

        let available = ModelsManager.buildAvailableModels(
            remoteModels: [first],
            localModels: [localDefault],
            chatGPTMode: false
        )

        XCTAssertEqual(available.map(\.model), ["first", "local-default"])
        XCTAssertTrue(available[0].isDefault)
        XCTAssertFalse(available[1].isDefault)
    }

    func testDefaultModelSelectionMatchesRustFallbacks() {
        XCTAssertEqual(
            ModelsManager.defaultModel(
                explicitModel: "manual",
                isChatGPT: true,
                availableModels: [preset(model: ModelsManager.codexAutoBalancedModel)]
            ),
            "manual"
        )
        XCTAssertEqual(
            ModelsManager.defaultModel(
                explicitModel: nil,
                isChatGPT: true,
                availableModels: [preset(model: ModelsManager.codexAutoBalancedModel)]
            ),
            ModelsManager.codexAutoBalancedModel
        )
        XCTAssertEqual(
            ModelsManager.defaultModel(explicitModel: nil, isChatGPT: true, availableModels: []),
            ModelsManager.openAIDefaultChatGPTModel
        )
        XCTAssertEqual(
            ModelsManager.defaultModel(explicitModel: nil, isChatGPT: false, availableModels: []),
            ModelsManager.openAIDefaultAPIModel
        )
        XCTAssertEqual(
            ModelsManager.offlineModel(explicitModel: nil),
            ModelsManager.openAIDefaultChatGPTModel
        )
        XCTAssertEqual(ModelsManager.offlineModel(explicitModel: "offline-manual"), "offline-manual")
    }

    func testBuiltInModelPresetsMatchRustOrderAndVisibility() {
        XCTAssertEqual(ModelsManager.hideGPT51MigrationPromptConfig, "hide_gpt5_1_migration_prompt")
        XCTAssertEqual(
            ModelsManager.hideGPT51CodexMaxMigrationPromptConfig,
            "hide_gpt-5.1-codex-max_migration_prompt"
        )

        XCTAssertEqual(
            ModelsManager.allModelPresets.map(\.model),
            [
                "gpt-5.2-codex",
                "gpt-5.1-codex-max",
                "gpt-5.1-codex-mini",
                "gpt-5.2",
                "bengalfox",
                "boomslang",
                "gpt-5-codex",
                "gpt-5-codex-mini",
                "gpt-5.1-codex",
                "gpt-5",
                "gpt-5.1"
            ]
        )
        XCTAssertEqual(
            ModelsManager.builtinModelPresets(authMode: .apiKey).map(\.model),
            [
                "gpt-5.2-codex",
                "gpt-5.1-codex-max",
                "gpt-5.1-codex-mini",
                "gpt-5.2"
            ]
        )
        XCTAssertEqual(
            ModelsManager.builtinModelPresets(authMode: .chatGPT),
            ModelsManager.builtinModelPresets(authMode: .apiKey)
        )
        XCTAssertEqual(ModelsManager.allModelPresets.filter(\.isDefault).map(\.model), ["gpt-5.2-codex"])
    }

    func testBuiltInPresetDetailsMatchRustMetadata() throws {
        let presets = Dictionary(uniqueKeysWithValues: ModelsManager.allModelPresets.map { ($0.model, $0) })

        let codex52 = try XCTUnwrap(presets["gpt-5.2-codex"])
        XCTAssertEqual(codex52.description, "Latest frontier agentic coding model.")
        XCTAssertTrue(codex52.isDefault)
        XCTAssertFalse(codex52.supportedInAPI)
        XCTAssertNil(codex52.upgrade)
        XCTAssertEqual(codex52.supportedReasoningEfforts.map(\.effort), [.low, .medium, .high, .xhigh])
        XCTAssertEqual(
            codex52.supportedReasoningEfforts.map(\.description),
            [
                "Fast responses with lighter reasoning",
                "Balances speed and reasoning depth for everyday tasks",
                "Greater reasoning depth for complex problems",
                "Extra high reasoning depth for complex problems"
            ]
        )

        let max = try XCTUnwrap(presets["gpt-5.1-codex-max"])
        XCTAssertEqual(max.description, "Codex-optimized flagship for deep and fast reasoning.")
        XCTAssertEqual(max.upgrade?.id, "gpt-5.2-codex")
        XCTAssertEqual(max.upgrade?.migrationConfigKey, "gpt-5.2-codex")
        XCTAssertEqual(max.upgrade?.modelLink, "https://openai.com/index/introducing-gpt-5-2-codex")
        XCTAssertEqual(
            max.upgrade?.upgradeCopy,
            "Codex is now powered by gpt-5.2-codex, our latest frontier agentic coding model. It is smarter and faster than its predecessors and capable of long-running project-scale work."
        )
        XCTAssertNil(max.upgrade?.reasoningEffortMapping)

        let gpt5 = try XCTUnwrap(presets["gpt-5"])
        XCTAssertEqual(gpt5.supportedReasoningEfforts.map(\.effort), [.minimal, .low, .medium, .high])
        XCTAssertFalse(gpt5.showInPicker)
        XCTAssertTrue(gpt5.supportedInAPI)
    }

    func testBuiltInAvailableModelsMatchRustAuthFiltering() {
        let apiModels = ModelsManager.buildAvailableModels(
            remoteModels: [],
            localModels: ModelsManager.builtinModelPresets(authMode: .apiKey),
            chatGPTMode: false
        )
        XCTAssertEqual(apiModels.map(\.model), ["gpt-5.1-codex-max", "gpt-5.1-codex-mini", "gpt-5.2"])
        XCTAssertEqual(apiModels.map(\.isDefault), [true, false, false])

        let chatGPTModels = ModelsManager.buildAvailableModels(
            remoteModels: [],
            localModels: ModelsManager.builtinModelPresets(authMode: .chatGPT),
            chatGPTMode: true
        )
        XCTAssertEqual(
            chatGPTModels.map(\.model),
            ["gpt-5.2-codex", "gpt-5.1-codex-max", "gpt-5.1-codex-mini", "gpt-5.2"]
        )
        XCTAssertEqual(chatGPTModels.map(\.isDefault), [true, false, false, false])
    }

    private func parseDate(_ text: String) throws -> Date {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return try XCTUnwrap(formatter.date(from: text))
    }

    private func minimalModelInfo(
        slug: String,
        visibility: ModelVisibility = .list,
        supportedInAPI: Bool = true,
        priority: Int32 = 5
    ) -> ModelInfo {
        ModelInfo(
            slug: slug,
            displayName: slug,
            description: "\(slug) desc",
            defaultReasoningLevel: .medium,
            supportedReasoningLevels: [
                ReasoningEffortPreset(effort: .low, description: "low"),
                ReasoningEffortPreset(effort: .medium, description: "medium")
            ],
            shellType: .shellCommand,
            visibility: visibility,
            supportedInAPI: supportedInAPI,
            priority: priority,
            upgrade: nil,
            baseInstructions: nil,
            supportsReasoningSummaries: false,
            supportVerbosity: false,
            defaultVerbosity: nil,
            applyPatchToolType: nil,
            truncationPolicy: .bytes(10_000),
            supportsParallelToolCalls: false,
            contextWindow: nil,
            experimentalSupportedTools: []
        )
    }

    private func preset(
        model: String,
        isDefault: Bool = false,
        showInPicker: Bool = true,
        supportedInAPI: Bool = true
    ) -> ModelPreset {
        ModelPreset(
            id: model,
            model: model,
            displayName: model,
            description: "\(model) desc",
            defaultReasoningEffort: .medium,
            supportedReasoningEfforts: [
                ReasoningEffortPreset(effort: .medium, description: "medium")
            ],
            isDefault: isDefault,
            upgrade: nil,
            showInPicker: showInPicker,
            supportedInAPI: supportedInAPI
        )
    }
}
