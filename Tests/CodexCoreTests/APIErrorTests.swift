import CodexCore
import XCTest

final class APIErrorTests: XCTestCase {
    func testDescriptionsMatchRustThisErrorStrings() {
        XCTAssertEqual(
            String(describing: APIError.transport(.http(statusCode: 429, headers: nil, body: "slow down"))),
            #"http 429 Too Many Requests: Some("slow down")"#
        )
        XCTAssertEqual(
            String(describing: APIError.api(statusCode: 500, message: "server exploded")),
            "api error 500 Internal Server Error: server exploded"
        )
        XCTAssertEqual(
            String(describing: APIError.api(statusCode: 599, message: "custom")),
            "api error 599 <unknown status code>: custom"
        )
        XCTAssertEqual(String(describing: APIError.stream("bad frame")), "stream error: bad frame")
        XCTAssertEqual(String(describing: APIError.contextWindowExceeded), "context window exceeded")
        XCTAssertEqual(String(describing: APIError.quotaExceeded), "quota exceeded")
        XCTAssertEqual(String(describing: APIError.usageNotIncluded), "usage not included")
        XCTAssertEqual(
            String(describing: APIError.retryable(message: "try again", delay: .seconds(2))),
            "retryable error: try again"
        )
        XCTAssertEqual(String(describing: APIError.rateLimit("credits exhausted")), "rate limit: credits exhausted")
    }

    func testRateLimitErrorConversionMatchesRustFromImplementation() {
        let rateLimitError = RateLimitError(message: "daily limit")

        XCTAssertEqual(String(describing: rateLimitError), "daily limit")
        XCTAssertEqual(
            APIError(rateLimitError: rateLimitError),
            .rateLimit("daily limit")
        )
        XCTAssertEqual(
            String(describing: APIError(rateLimitError: rateLimitError)),
            "rate limit: daily limit"
        )
    }
}
