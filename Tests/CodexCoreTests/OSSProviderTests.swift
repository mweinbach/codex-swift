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
}

private struct BoomError: Error, CustomStringConvertible {
    var description: String {
        "boom"
    }
}
