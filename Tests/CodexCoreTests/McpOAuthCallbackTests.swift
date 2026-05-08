import CodexCore
import Foundation
import XCTest

final class McpOAuthCallbackTests: XCTestCase {
    func testParseCallbackExtractsDecodedCodeAndState() {
        XCTAssertEqual(
            McpOAuthCallbackParser.parse(path: "/callback?code=auth%20code&state=csrf%2Fstate"),
            McpOAuthCallbackResult(code: "auth code", state: "csrf/state")
        )
    }

    func testParseCallbackIgnoresUnknownQueryPairs() {
        XCTAssertEqual(
            McpOAuthCallbackParser.parse(path: "/callback?ignored=yes&code=abc&state=xyz"),
            McpOAuthCallbackResult(code: "abc", state: "xyz")
        )
    }

    func testParseCallbackRejectsRustInvalidShapes() {
        XCTAssertNil(McpOAuthCallbackParser.parse(path: "/other?code=abc&state=xyz"))
        XCTAssertNil(McpOAuthCallbackParser.parse(path: "/callback"))
        XCTAssertNil(McpOAuthCallbackParser.parse(path: "/callback?code=abc"))
        XCTAssertNil(McpOAuthCallbackParser.parse(path: "/callback?state=xyz"))
        XCTAssertNil(McpOAuthCallbackParser.parse(path: "/callback?code=abc&state"))
        XCTAssertNil(McpOAuthCallbackParser.parse(path: "/callback?code=%ZZ&state=xyz"))
    }

    func testLocalCallbackServerRejectsInvalidCallbacksThenCompletesOnValidCallback() async throws {
        let server = try McpOAuthLocalCallbackServer.start()
        defer { server.stop() }

        let baseURL = server.redirectURI.replacingOccurrences(of: "/callback", with: "")
        let invalidURL = try XCTUnwrap(URL(string: "\(baseURL)/nope?code=abc&state=xyz"))
        let (invalidBody, invalidResponse) = try await URLSession.shared.data(from: invalidURL)
        XCTAssertEqual((invalidResponse as? HTTPURLResponse)?.statusCode, 400)
        XCTAssertEqual(String(data: invalidBody, encoding: .utf8), "Invalid OAuth callback")

        async let callback = server.waitForCallback(timeout: 2)
        let validURL = try XCTUnwrap(URL(string: "\(baseURL)/callback?code=auth%20code&state=csrf%2Fstate"))
        let (validBody, validResponse) = try await URLSession.shared.data(from: validURL)
        XCTAssertEqual((validResponse as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(
            String(data: validBody, encoding: .utf8),
            "Authentication complete. You may close this window."
        )
        let callbackResult = try await callback
        XCTAssertEqual(callbackResult, McpOAuthCallbackResult(code: "auth code", state: "csrf/state"))
    }
}
