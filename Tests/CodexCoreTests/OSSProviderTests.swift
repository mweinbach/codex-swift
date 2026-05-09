import XCTest
@testable import CodexCore

final class OSSProviderTests: XCTestCase {
    func testDefaultModelForLMStudio() {
        XCTAssertEqual(
            OSSProvider.defaultModel(for: OSSProvider.lmStudioProviderID),
            OSSProvider.lmStudioDefaultModel
        )
    }

    func testDefaultModelForOllama() {
        XCTAssertEqual(
            OSSProvider.defaultModel(for: OSSProvider.ollamaProviderID),
            OSSProvider.ollamaDefaultModel
        )
    }

    func testDefaultModelForUnknownProvider() {
        XCTAssertNil(OSSProvider.defaultModel(for: "unknown-provider"))
    }

    func testResolveProviderIDPrefersExplicitOverConfigLikeRust() {
        let settings = CodexRuntimeConfig(ossProvider: "ollama")

        XCTAssertEqual(
            OSSProvider.resolveProviderID(explicitProvider: "lmstudio", settings: settings),
            "lmstudio"
        )
        XCTAssertEqual(
            OSSProvider.resolveProviderID(explicitProvider: nil, settings: settings),
            "ollama"
        )
        XCTAssertNil(OSSProvider.resolveProviderID(explicitProvider: nil, settings: CodexRuntimeConfig()))
    }

    func testDefaultModelOverrideUsesCLIModelBeforeOSSDefaultLikeRust() {
        XCTAssertEqual(
            OSSProvider.defaultModelOverride(providerID: OSSProvider.ollamaProviderID, cliModel: "custom"),
            "custom"
        )
        XCTAssertEqual(
            OSSProvider.defaultModelOverride(providerID: OSSProvider.lmStudioProviderID, cliModel: nil),
            OSSProvider.lmStudioDefaultModel
        )
        XCTAssertNil(OSSProvider.defaultModelOverride(providerID: "unknown-provider", cliModel: nil))
    }

    func testEnsureProviderReadyDispatchesLMStudioReadiness() async throws {
        var calls: [String] = []

        try await OSSProvider.ensureProviderReady(
            providerID: OSSProvider.lmStudioProviderID,
            lmStudioReadiness: { calls.append("lmstudio") },
            ollamaReadiness: { calls.append("ollama") }
        )

        XCTAssertEqual(calls, ["lmstudio"])
    }

    func testEnsureProviderReadyDispatchesOllamaReadiness() async throws {
        var calls: [String] = []

        try await OSSProvider.ensureProviderReady(
            providerID: OSSProvider.ollamaProviderID,
            lmStudioReadiness: { calls.append("lmstudio") },
            ollamaReadiness: { calls.append("ollama") }
        )

        XCTAssertEqual(calls, ["ollama"])
    }

    func testEnsureProviderReadyPassesProviderAndModelToLMStudioReadiness() async throws {
        let provider = ModelProviderInfo(name: "LM Studio", baseURL: "http://localhost:1234/v1")
        var calls: [(ModelProviderInfo, String)] = []

        try await OSSProvider.ensureProviderReady(
            providerID: OSSProvider.lmStudioProviderID,
            providerInfo: provider,
            model: "openai/gpt-oss-20b",
            lmStudioReadiness: { calls.append(($0, $1)) },
            ollamaVersionReadiness: { _ in XCTFail("LM Studio should not check Ollama version") },
            ollamaReadiness: { _, _ in XCTFail("LM Studio should not call Ollama readiness") }
        )

        XCTAssertEqual(calls.map(\.0), [provider])
        XCTAssertEqual(calls.map(\.1), ["openai/gpt-oss-20b"])
    }

    func testEnsureProviderReadyChecksOllamaResponsesBeforeModelReadiness() async throws {
        let provider = ModelProviderInfo(name: "Ollama", baseURL: "http://localhost:11434/v1")
        var calls: [String] = []

        try await OSSProvider.ensureProviderReady(
            providerID: OSSProvider.ollamaProviderID,
            providerInfo: provider,
            model: "gpt-oss:20b",
            lmStudioReadiness: { _, _ in XCTFail("Ollama should not call LM Studio readiness") },
            ollamaVersionReadiness: { _ in calls.append("version") },
            ollamaReadiness: { _, model in calls.append("model:\(model)") }
        )

        XCTAssertEqual(calls, ["version", "model:gpt-oss:20b"])
    }

    func testEnsureProviderReadySkipsUnknownProvider() async throws {
        try await OSSProvider.ensureProviderReady(
            providerID: "unknown-provider",
            lmStudioReadiness: { XCTFail("unknown provider should not call LM Studio readiness") },
            ollamaReadiness: { XCTFail("unknown provider should not call Ollama readiness") }
        )
    }

    func testEnsureProviderReadyWrapsLMStudioErrors() async throws {
        do {
            try await OSSProvider.ensureProviderReady(
                providerID: OSSProvider.lmStudioProviderID,
                lmStudioReadiness: { throw BoomError() },
                ollamaReadiness: {}
            )
            XCTFail("Expected LM Studio readiness failure")
        } catch let error as OSSProviderReadinessError {
            XCTAssertEqual(error.description, "OSS setup failed: boom")
            XCTAssertEqual(error.underlyingDescription, "boom")
        }
    }

    func testEnsureProviderReadyWrapsOllamaErrors() async throws {
        do {
            try await OSSProvider.ensureProviderReady(
                providerID: OSSProvider.ollamaProviderID,
                lmStudioReadiness: {},
                ollamaReadiness: { throw BoomError() }
            )
            XCTFail("Expected Ollama readiness failure")
        } catch let error as OSSProviderReadinessError {
            XCTAssertEqual(error.description, "OSS setup failed: boom")
            XCTAssertEqual(error.underlyingDescription, "boom")
        }
    }

    func testEnsureProviderReadyWrapsOllamaVersionErrors() async throws {
        do {
            try await OSSProvider.ensureProviderReady(
                providerID: OSSProvider.ollamaProviderID,
                providerInfo: ModelProviderInfo(name: "Ollama", baseURL: "http://localhost:11434/v1"),
                model: "gpt-oss:20b",
                lmStudioReadiness: { _, _ in },
                ollamaVersionReadiness: { _ in throw BoomError() },
                ollamaReadiness: { _, _ in XCTFail("version failure should stop Ollama readiness") }
            )
            XCTFail("Expected Ollama version readiness failure")
        } catch let error as OSSProviderReadinessError {
            XCTAssertEqual(error.description, "OSS setup failed: boom")
            XCTAssertEqual(error.underlyingDescription, "boom")
        }
    }
}

private struct BoomError: Error, CustomStringConvertible {
    var description: String {
        "boom"
    }
}
