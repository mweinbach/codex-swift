import XCTest
@testable import CodexCore

final class CoreUtilsTests: XCTestCase {
    func testBackoffMillisecondsUsesRustBaseAndFactor() {
        XCTAssertEqual(CoreUtils.backoffMilliseconds(attempt: 0, jitter: { 1.0 }), 200)
        XCTAssertEqual(CoreUtils.backoffMilliseconds(attempt: 1, jitter: { 1.0 }), 200)
        XCTAssertEqual(CoreUtils.backoffMilliseconds(attempt: 2, jitter: { 1.0 }), 400)
        XCTAssertEqual(CoreUtils.backoffMilliseconds(attempt: 4, jitter: { 1.0 }), 1_600)
    }

    func testBackoffMillisecondsAppliesJitterAndTruncates() {
        XCTAssertEqual(CoreUtils.backoffMilliseconds(attempt: 2, jitter: { 0.9 }), 360)
        XCTAssertEqual(CoreUtils.backoffMilliseconds(attempt: 2, jitter: { 1.099 }), 439)
    }

    func testTryParseErrorMessageExtractsServerErrorMessage() {
        let text = #"""
        {
          "error": {
            "message": "Your refresh token has already been used to generate a new access token. Please try signing in again.",
            "type": "invalid_request_error",
            "param": null,
            "code": "refresh_token_reused"
          }
        }
        """#

        XCTAssertEqual(
            CoreUtils.tryParseErrorMessage(text),
            "Your refresh token has already been used to generate a new access token. Please try signing in again."
        )
    }

    func testTryParseErrorMessageFallsBackToTextOrUnknown() {
        XCTAssertEqual(CoreUtils.tryParseErrorMessage(#"{"message": "test"}"#), #"{"message": "test"}"#)
        XCTAssertEqual(CoreUtils.tryParseErrorMessage("not json"), "not json")
        XCTAssertEqual(CoreUtils.tryParseErrorMessage(""), "Unknown error")
    }

    func testResolvePathUsesAbsolutePathOrBaseJoin() {
        XCTAssertEqual(CoreUtils.resolvePath(base: "/repo", path: "/tmp/file"), "/tmp/file")
        XCTAssertEqual(CoreUtils.resolvePath(base: "/repo", path: "src/main.swift"), "/repo/src/main.swift")
        XCTAssertEqual(CoreUtils.resolvePath(base: "/", path: "src/main.swift"), "/src/main.swift")
    }
}
