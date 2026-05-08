import CodexCore
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
}
