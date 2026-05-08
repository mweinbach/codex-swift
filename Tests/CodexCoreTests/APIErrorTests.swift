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

    func testUnexpectedResponseErrorDisplayMatchesRustStatusAndMetadata() {
        let error = UnexpectedResponseError(
            statusCode: 500,
            body: #"{"error":{"message":" server exploded "}}"#,
            url: "https://api.example.test/responses",
            cfRay: "ray-1",
            requestID: "req-1",
            identityAuthorizationError: "authorization failed",
            identityErrorCode: "workspace_mismatch"
        )

        XCTAssertEqual(
            String(describing: error),
            """
            unexpected status 500 Internal Server Error: server exploded, url: https://api.example.test/responses, cf-ray: ray-1, request id: req-1, auth error: authorization failed, auth error code: workspace_mismatch
            """
        )
    }

    func testUnexpectedResponseErrorUsesUnknownErrorForEmptyBody() {
        XCTAssertEqual(
            String(describing: UnexpectedResponseError(statusCode: 418, body: " \n\t ")),
            "unexpected status 418 I'm a teapot: Unknown error"
        )
    }

    func testUnexpectedResponseErrorTruncatesBodyAtUTF8BoundaryLikeRust() {
        let body = String(repeating: "a", count: 999) + "é" + "tail"

        XCTAssertEqual(
            String(describing: UnexpectedResponseError(statusCode: 400, body: body)),
            "unexpected status 400 Bad Request: \(String(repeating: "a", count: 999))..."
        )
    }

    func testUnexpectedResponseErrorCloudflareBlockedFriendlyMessageMatchesRust() {
        let error = UnexpectedResponseError(
            statusCode: 403,
            body: "<html><body>Cloudflare error: Sorry, you have been blocked</body></html>",
            url: "https://api.example.test/responses",
            cfRay: "abc123",
            requestID: "req-2"
        )

        XCTAssertEqual(
            String(describing: error),
            """
            Access blocked by Cloudflare. This usually happens when connecting from a restricted region (status 403 Forbidden), url: https://api.example.test/responses, cf-ray: abc123, request id: req-2
            """
        )
    }
}
