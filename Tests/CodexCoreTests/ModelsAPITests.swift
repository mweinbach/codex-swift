import CodexCore
import XCTest

final class ModelsAPITests: XCTestCase {
    func testListModelsRequestAppendsClientVersionQuery() {
        let request = ModelsAPI.request(
            provider: provider(baseURL: "https://example.com/api/codex"),
            clientVersion: "0.99.0"
        )

        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.url, "https://example.com/api/codex/models?client_version=0.99.0")
        XCTAssertEqual(request.headers, [:])
        XCTAssertNil(request.body)
        XCTAssertNil(request.timeoutMilliseconds)
    }

    func testListModelsRequestUsesAmpersandWithProviderQueryAndMergesExtraHeaders() {
        let request = ModelsAPI.request(
            provider: provider(
                baseURL: "https://example.com/api/codex/",
                queryParams: ["api-version": "2025-04-01-preview"],
                headers: ["x-provider": "provider", "x-shared": "provider"]
            ),
            clientVersion: "0.99.0",
            extraHeaders: ["x-extra": "extra", "x-shared": "extra"]
        )

        XCTAssertEqual(
            request.url,
            "https://example.com/api/codex/models?api-version=2025-04-01-preview&client_version=0.99.0"
        )
        XCTAssertEqual(request.headers, [
            "x-provider": "provider",
            "x-extra": "extra",
            "x-shared": "extra"
        ])
    }

    func testDecodeModelsResponseUsesBodyETagWhenHeaderIsMissing() throws {
        let response = try ModelsAPI.decodeResponse(body: Data("""
        {
          "models": [],
          "etag": "\\"body-etag\\""
        }
        """.utf8))

        XCTAssertEqual(response, ModelsResponse(models: [], etag: "\"body-etag\""))
    }

    func testDecodeModelsResponseHeaderETagOverridesBodyETag() throws {
        let response = try ModelsAPI.decodeResponse(
            body: Data("""
            {
              "models": [],
              "etag": "\\"body-etag\\""
            }
            """.utf8),
            headers: ["ETag": "\"header-etag\""]
        )

        XCTAssertEqual(response, ModelsResponse(models: [], etag: "\"header-etag\""))
    }

    func testDecodeModelsResponseErrorMatchesRustMessageShape() {
        XCTAssertThrowsError(try ModelsAPI.decodeResponse(body: Data(#"{"models":null}"#.utf8))) { error in
            XCTAssertTrue(
                String(describing: error).hasPrefix("failed to decode models response:"),
                String(describing: error)
            )
            XCTAssertTrue(String(describing: error).contains(#"body: {"models":null}"#))
        }
    }

    private func provider(
        baseURL: String,
        queryParams: [String: String]? = nil,
        headers: [String: String] = [:]
    ) -> APIProvider {
        APIProvider(
            name: "test",
            baseURL: baseURL,
            queryParams: queryParams,
            wireAPI: .responses,
            headers: headers,
            retry: ProviderRetryConfig(
                maxAttempts: 1,
                baseDelayMilliseconds: 1,
                retry429: false,
                retry5xx: true,
                retryTransport: true
            ),
            streamIdleTimeoutMilliseconds: 1_000
        )
    }
}
