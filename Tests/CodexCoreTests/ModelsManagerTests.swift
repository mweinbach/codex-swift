import CodexCore
import XCTest

final class ModelsManagerTests: XCTestCase {
    func testModelsCacheWireShapeSkipsNilEtagAndAcceptsMissingEtag() throws {
        let cache = ModelsCache(
            fetchedAt: try parseDate("2026-05-08T12:34:56.789Z"),
            etag: nil,
            clientVersion: "1.2.3",
            models: [minimalModelInfo(slug: "codex-mini")]
        )

        let object = try JSONObject(cache)
        XCTAssertEqual(object["fetched_at"] as? String, "2026-05-08T12:34:56.789Z")
        XCTAssertNil(object["etag"])
        XCTAssertEqual(object["client_version"] as? String, "1.2.3")
        XCTAssertEqual((object["models"] as? [[String: Any]])?.first?["slug"] as? String, "codex-mini")

        let decoded = try JSONDecoder().decode(ModelsCache.self, from: Data("""
        {
          "fetched_at": "2026-05-08T12:34:56Z",
          "models": []
        }
        """.utf8))
        XCTAssertNil(decoded.etag)
        XCTAssertNil(decoded.clientVersion)
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
            clientVersion: "1.2.3",
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

    func testRawModelCatalogOnlineIfUncachedUsesFreshMatchingCache() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cachedModel = minimalModelInfo(slug: "cached-remote", priority: 0)
        try ModelsCache(
            fetchedAt: try parseDate("2026-05-08T12:00:00Z"),
            etag: "cache-etag",
            clientVersion: "1.2.3",
            models: [cachedModel]
        ).save(to: ModelsManager.cachePath(codexHome: root))

        let transport = RecordingAPITransport { _ in
            XCTFail("fresh cache should avoid network")
            return URLSessionTransportResponse(statusCode: 500)
        }

        let response = try await ModelsManager.rawModelCatalogOnlineIfUncached(
            codexHome: root,
            config: CodexRuntimeConfig(modelProvider: "openai"),
            auth: nil,
            transport: transport,
            clientVersion: "1.2.3",
            now: try parseDate("2026-05-08T12:04:59Z")
        )

        XCTAssertEqual(response.etag, "cache-etag")
        XCTAssertTrue(response.models.contains { $0.slug == "cached-remote" })
    }

    func testRawModelCatalogOnlineIfUncachedFetchesAndPersistsWhenAuthorized() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let remoteModel = minimalModelInfo(slug: "remote-model", priority: 0)
        let responseBody = try JSONEncoder().encode(ModelsResponse(models: [remoteModel], etag: "body-etag"))
        let capture = APIRequestCapture()
        let transport = RecordingAPITransport { request in
            await capture.append(request)
            return URLSessionTransportResponse(
                statusCode: 200,
                headers: ["etag": "header-etag"],
                body: responseBody
            )
        }

        let response = try await ModelsManager.rawModelCatalogOnlineIfUncached(
            codexHome: root,
            config: CodexRuntimeConfig(modelProvider: "openai"),
            auth: AuthDotJSON(authMode: .apiKey, openAIAPIKey: "sk-test", tokens: nil, lastRefresh: nil),
            transport: transport,
            clientVersion: "1.2.3",
            now: try parseDate("2026-05-08T12:00:00Z")
        )

        XCTAssertEqual(response.etag, "header-etag")
        XCTAssertTrue(response.models.contains { $0.slug == "remote-model" })
        let capturedRequest = await capture.firstRequest()
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.url, "https://api.openai.com/v1/models?client_version=1.2.3")
        XCTAssertEqual(request.headers["authorization"], "Bearer sk-test")

        let cache = try XCTUnwrap(ModelsCache.load(from: ModelsManager.cachePath(codexHome: root)))
        XCTAssertEqual(cache.etag, "header-etag")
        XCTAssertEqual(cache.clientVersion, "1.2.3")
        XCTAssertEqual(cache.models.map(\.slug), ["remote-model"])
    }

    func testRawModelCatalogOnlineIfUncachedUsesProviderCommandAuthLikeRust() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let remoteModel = minimalModelInfo(slug: "remote-model", priority: 0)
        let responseBody = try JSONEncoder().encode(ModelsResponse(models: [remoteModel], etag: "body-etag"))
        let capture = APIRequestCapture()
        let transport = RecordingAPITransport { request in
            await capture.append(request)
            return URLSessionTransportResponse(statusCode: 200, body: responseBody)
        }
        let provider = try ModelProviderInfo(
            name: "Corp",
            baseURL: "https://corp.example/v1",
            auth: ModelProviderAuthInfo(
                command: "printf",
                args: ["provider-token"],
                timeoutMilliseconds: 10_000,
                cwd: AbsolutePath.currentDirectory()
            ),
            wireAPI: .responses
        )

        let response = try await ModelsManager.rawModelCatalogOnlineIfUncached(
            codexHome: root,
            config: CodexRuntimeConfig(modelProvider: "corp", modelProviders: ["corp": provider]),
            auth: AuthDotJSON(authMode: .apiKey, openAIAPIKey: "auth-json-key", tokens: nil, lastRefresh: nil),
            transport: transport,
            clientVersion: "1.2.3",
            commandAuthRunner: ProviderAuthCommandRunner(),
            now: try parseDate("2026-05-08T12:00:00Z")
        )

        XCTAssertTrue(response.models.contains { $0.slug == "remote-model" })
        let capturedRequest = await capture.firstRequest()
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.url, "https://corp.example/v1/models?client_version=1.2.3")
        XCTAssertEqual(request.headers["authorization"], "Bearer provider-token")
    }

    func testRawModelCatalogOnlineIfUncachedFallsBackToBundledOnFetchFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = RecordingAPITransport { _ in
            URLSessionTransportResponse(statusCode: 500, body: Data("nope".utf8))
        }

        let response = try await ModelsManager.rawModelCatalogOnlineIfUncached(
            codexHome: root,
            config: CodexRuntimeConfig(modelProvider: "openai"),
            auth: AuthDotJSON(authMode: .apiKey, openAIAPIKey: "sk-test", tokens: nil, lastRefresh: nil),
            transport: transport,
            clientVersion: "1.2.3"
        )

        XCTAssertEqual(response.models, try ModelsManager.bundledModelsResponse().models)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ModelsManager.cachePath(codexHome: root).path))
    }

    func testAmazonBedrockStaticModelCatalogMatchesRust() {
        let catalog = ModelsManager.amazonBedrockStaticModelCatalog()

        XCTAssertEqual(catalog.models.map(\.slug), [
            "openai.gpt-5.4",
            "openai.gpt-oss-120b",
            "openai.gpt-oss-20b"
        ])

        let defaultModel = catalog.models[0]
        XCTAssertEqual(defaultModel.displayName, "gpt-5.4")
        XCTAssertEqual(defaultModel.supportedReasoningLevels.map(\.effort), [.minimal, .low, .medium, .high])
        XCTAssertEqual(defaultModel.serviceTiers.map(\.id), ["priority"])
        XCTAssertEqual(defaultModel.defaultVerbosity, .medium)
        XCTAssertEqual(defaultModel.applyPatchToolType, .freeform)
        XCTAssertEqual(defaultModel.webSearchToolType, .textAndImage)
        XCTAssertEqual(defaultModel.truncationPolicy, .tokens(10_000))
        XCTAssertEqual(defaultModel.contextWindow, 272_000)
        XCTAssertEqual(defaultModel.maxContextWindow, 1_000_000)
        XCTAssertEqual(defaultModel.inputModalities, [.text, .image])
        XCTAssertTrue(defaultModel.supportsSearchTool)

        let ossModel = catalog.models[1]
        XCTAssertEqual(ossModel.supportedReasoningLevels.map(\.effort), [.low, .medium, .high])
        XCTAssertFalse(ossModel.supportVerbosity)
        XCTAssertNil(ossModel.applyPatchToolType)
        XCTAssertEqual(ossModel.webSearchToolType, .text)
        XCTAssertEqual(ossModel.contextWindow, 128_000)
        XCTAssertEqual(ossModel.maxContextWindow, 128_000)
        XCTAssertEqual(ossModel.inputModalities, [.text])
        XCTAssertFalse(ossModel.supportsSearchTool)
    }

    func testRawModelCatalogOnlineIfUncachedUsesStaticBedrockCatalogLikeRust() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = RecordingAPITransport { _ in
            XCTFail("Bedrock static model manager should not fetch remote models")
            return URLSessionTransportResponse(statusCode: 200, body: Data())
        }

        let response = try await ModelsManager.rawModelCatalogOnlineIfUncached(
            codexHome: root,
            config: CodexRuntimeConfig(modelProvider: "amazon-bedrock"),
            auth: AuthDotJSON(authMode: .apiKey, openAIAPIKey: "unused-openai-key", tokens: nil, lastRefresh: nil),
            transport: transport,
            clientVersion: "1.2.3"
        )

        XCTAssertEqual(response.models, ModelsManager.amazonBedrockStaticModelCatalog().models)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ModelsManager.cachePath(codexHome: root).path))
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
        XCTAssertEqual(apiModels.map(\.model), ["hidden", "visible", "api-local"])
        XCTAssertFalse(apiModels[0].isDefault)
        XCTAssertTrue(apiModels[1].isDefault)
        XCTAssertFalse(apiModels[2].isDefault)

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
                availableModels: [preset(model: "available-default", isDefault: true)]
            ),
            "available-default"
        )
        XCTAssertEqual(
            ModelsManager.defaultModel(
                explicitModel: nil,
                isChatGPT: false,
                availableModels: [preset(model: "first-available")]
            ),
            "first-available"
        )
        XCTAssertEqual(
            ModelsManager.defaultModel(explicitModel: nil, isChatGPT: true, availableModels: []),
            ""
        )
        XCTAssertEqual(
            ModelsManager.defaultModel(explicitModel: nil, isChatGPT: false, availableModels: []),
            ""
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
                "gpt-5.5",
                "gpt-5.4",
                "gpt-5.4-mini",
                "gpt-5.3-codex",
                "gpt-5.2",
                "codex-auto-review"
            ]
        )
        XCTAssertEqual(
            ModelsManager.builtinModelPresets(authMode: .apiKey).map(\.model),
            [
                "gpt-5.5",
                "gpt-5.4",
                "gpt-5.4-mini",
                "gpt-5.3-codex",
                "gpt-5.2",
                "codex-auto-review"
            ]
        )
        XCTAssertEqual(
            ModelsManager.builtinModelPresets(authMode: .chatGPT),
            ModelsManager.builtinModelPresets(authMode: .apiKey)
        )
        XCTAssertEqual(ModelsManager.allModelPresets.filter(\.isDefault).map(\.model), ["gpt-5.5"])
    }

    func testBuiltInPresetDetailsMatchRustMetadata() throws {
        let presets = Dictionary(uniqueKeysWithValues: ModelsManager.allModelPresets.map { ($0.model, $0) })

        let gpt55 = try XCTUnwrap(presets["gpt-5.5"])
        XCTAssertEqual(gpt55.displayName, "GPT-5.5")
        XCTAssertEqual(gpt55.description, "Frontier model for complex coding, research, and real-world work.")
        XCTAssertTrue(gpt55.isDefault)
        XCTAssertTrue(gpt55.supportedInAPI)
        XCTAssertNil(gpt55.upgrade)
        XCTAssertTrue(gpt55.supportsFastMode())
        XCTAssertEqual(gpt55.serviceTiers.map(\.id), ["priority"])
        XCTAssertFalse(gpt55.serviceTiers.contains { $0.id == "ultrafast" })
        XCTAssertEqual(gpt55.additionalSpeedTiers, ["fast"])
        XCTAssertEqual(gpt55.supportedReasoningEfforts.map(\.effort), [.low, .medium, .high, .xhigh])
        XCTAssertEqual(
            gpt55.supportedReasoningEfforts.map(\.description),
            [
                "Fast responses with lighter reasoning",
                "Balances speed and reasoning depth for everyday tasks",
                "Greater reasoning depth for complex problems",
                "Extra high reasoning depth for complex problems"
            ]
        )

        let gpt54 = try XCTUnwrap(presets["gpt-5.4"])
        XCTAssertEqual(gpt54.description, "Strong model for everyday coding.")
        XCTAssertTrue(gpt54.supportsFastMode())
        XCTAssertEqual(gpt54.serviceTiers.map(\.id), ["priority"])
        XCTAssertFalse(gpt54.serviceTiers.contains { $0.id == "ultrafast" })

        let codex53 = try XCTUnwrap(presets["gpt-5.3-codex"])
        XCTAssertEqual(codex53.upgrade?.id, "gpt-5.4")
        XCTAssertEqual(codex53.upgrade?.migrationConfigKey, "gpt-5.3-codex")
        XCTAssertNil(codex53.upgrade?.modelLink)
        XCTAssertNil(codex53.upgrade?.upgradeCopy)
        XCTAssertTrue(codex53.upgrade?.migrationMarkdown?.contains("Introducing GPT-5.4") == true)

        let review = try XCTUnwrap(presets["codex-auto-review"])
        XCTAssertFalse(review.showInPicker)
        XCTAssertTrue(review.supportedInAPI)
    }

    func testBuiltInAvailableModelsMatchRustAuthFiltering() {
        let apiModels = ModelsManager.buildAvailableModels(
            remoteModels: [],
            localModels: ModelsManager.builtinModelPresets(authMode: .apiKey),
            chatGPTMode: false
        )
        XCTAssertEqual(
            apiModels.map(\.model),
            ["gpt-5.5", "gpt-5.4", "gpt-5.4-mini", "gpt-5.3-codex", "gpt-5.2", "codex-auto-review"]
        )
        XCTAssertEqual(apiModels.map(\.isDefault), [true, false, false, false, false, false])

        let chatGPTModels = ModelsManager.buildAvailableModels(
            remoteModels: [],
            localModels: ModelsManager.builtinModelPresets(authMode: .chatGPT),
            chatGPTMode: true
        )
        XCTAssertEqual(
            chatGPTModels.map(\.model),
            ["gpt-5.5", "gpt-5.4", "gpt-5.4-mini", "gpt-5.3-codex", "gpt-5.2", "codex-auto-review"]
        )
        XCTAssertEqual(chatGPTModels.map(\.isDefault), [true, false, false, false, false, false])
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

private actor APIRequestCapture {
    private var requests: [APIRequest] = []

    func append(_ request: APIRequest) {
        requests.append(request)
    }

    func firstRequest() -> APIRequest? {
        requests.first
    }
}

private struct RecordingAPITransport: APITransport {
    let handler: @Sendable (APIRequest) async -> URLSessionTransportResponse

    func execute(_ request: APIRequest) async -> Result<APIResponse, TransportError> {
        let response = await handler(request)
        if (200..<300).contains(response.statusCode) {
            return .success(APIResponse(
                statusCode: response.statusCode,
                headers: response.headers,
                body: response.body
            ))
        }
        return .failure(.http(
            statusCode: response.statusCode,
            headers: response.headers,
            body: String(data: response.body, encoding: .utf8)
        ))
    }

    func stream(_ request: APIRequest) async -> Result<APIStreamResponse, TransportError> {
        let response = await handler(request)
        return .success(APIStreamResponse(
            statusCode: response.statusCode,
            headers: response.headers,
            sseText: String(decoding: response.body, as: UTF8.self)
        ))
    }
}
