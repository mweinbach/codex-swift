import CodexCore
import XCTest

final class APIAuthTests: XCTestCase {
    func testAddAuthHeadersAddsBearerAndAccountHeaders() {
        let request = APIRequest(
            method: .get,
            url: "https://example.com/models",
            headers: ["x-existing": "1"]
        )

        let authed = request.addingAuthHeaders(from: StaticAPIAuthProvider(
            bearerToken: "token",
            accountID: "account-id"
        ))

        XCTAssertEqual(authed.method, .get)
        XCTAssertEqual(authed.url, request.url)
        XCTAssertEqual(authed.headers, [
            "x-existing": "1",
            "authorization": "Bearer token",
            "ChatGPT-Account-ID": "account-id"
        ])
        XCTAssertNil(authed.body)
        XCTAssertNil(authed.timeoutMilliseconds)
    }

    func testAddAuthHeadersSkipsMissingValues() {
        let request = APIRequest(method: .get, url: "https://example.com/models")

        XCTAssertEqual(
            request.addingAuthHeaders(from: StaticAPIAuthProvider()).headers,
            [:]
        )
    }

    func testAddAuthHeadersSkipsInvalidHeaderValuesLikeRustParseFailures() {
        let request = APIRequest(
            method: .get,
            url: "https://example.com/models",
            headers: ["authorization": "original", "ChatGPT-Account-ID": "original-account"]
        )

        let authed = request.addingAuthHeaders(from: StaticAPIAuthProvider(
            bearerToken: "bad\nvalue",
            accountID: "bad\rvalue"
        ))

        XCTAssertEqual(authed.headers, [
            "authorization": "original",
            "ChatGPT-Account-ID": "original-account"
        ])
    }
}
