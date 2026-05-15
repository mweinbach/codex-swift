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
        XCTAssertEqual(
            String(describing: APIError.invalidRequest(message: "bad prompt")),
            "invalid request: bad prompt"
        )
        XCTAssertEqual(
            String(describing: APIError.cyberPolicy(message: "blocked")),
            "cyber policy: blocked"
        )
        XCTAssertEqual(String(describing: APIError.serverOverloaded), "server overloaded")
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

    func testCodexErrorBridgeMapsServerOverloadedFrom503BodyLikeRust() {
        let body = #"{"error":{"code":"server_is_overloaded"}}"#

        XCTAssertEqual(
            CodexError(apiError: .transport(.http(statusCode: 503, headers: nil, body: body))),
            .serverOverloaded
        )

        let slowDownBody = #"{"error":{"code":"slow_down"}}"#
        XCTAssertEqual(
            CodexError(apiError: .transport(.http(statusCode: 503, headers: nil, body: slowDownBody))),
            .serverOverloaded
        )
    }

    func testCodexErrorBridgeMapsCyberPolicyBodiesLikeRust() {
        let body = #"""
        {
          "error": {
            "message": "This request has been flagged for potentially high-risk cyber activity.",
            "type": "invalid_request",
            "param": null,
            "code": "cyber_policy"
          }
        }
        """#

        XCTAssertEqual(
            CodexError(apiError: .transport(.http(statusCode: 400, headers: nil, body: body))),
            .cyberPolicy(message: "This request has been flagged for potentially high-risk cyber activity.")
        )
    }

    func testCodexErrorBridgeMapsWrappedWebSocketCyberPolicyBodyLikeRust() {
        let body = #"""
        {
          "type": "error",
          "status": 400,
          "error": {
            "message": "This websocket request was flagged.",
            "type": "invalid_request",
            "code": "cyber_policy"
          }
        }
        """#

        XCTAssertEqual(
            CodexError(apiError: .transport(.http(statusCode: 400, headers: nil, body: body))),
            .cyberPolicy(message: "This websocket request was flagged.")
        )
    }

    func testCodexErrorBridgeUsesCyberPolicyFallbackAndKeepsUnknown400GenericLikeRust() {
        let cyberBody = #"{"error":{"code":"cyber_policy","message":"   "}}"#
        XCTAssertEqual(
            CodexError(apiError: .transport(.http(statusCode: 400, headers: nil, body: cyberBody))),
            .cyberPolicy(message: "This request has been flagged for possible cybersecurity risk.")
        )

        let unknownBody = #"{"error":{"message":"Some other bad request.","code":"some_other_policy"}}"#
        XCTAssertEqual(
            CodexError(apiError: .transport(.http(statusCode: 400, headers: nil, body: unknownBody))),
            .invalidRequest(unknownBody)
        )
    }

    func testCodexErrorBridgeMapsUsageLimitHeadersLikeRust() throws {
        let body = #"{"error":{"type":"usage_limit_reached","plan_type":"pro","resets_at":1738888888}}"#
        let error = CodexError(apiError: .transport(.http(
            statusCode: 429,
            headers: [
                "x-codex-active-limit": "codex_other",
                "x-codex-other-limit-name": " codex_other ",
                "x-codex-promo-message": " Visit the usage page ",
                "x-codex-other-primary-used-percent": "100",
                "x-codex-other-primary-window-minutes": "15"
            ],
            body: body
        )))

        guard case let .usageLimitReached(usageLimit) = error else {
            return XCTFail("expected usage limit, got \(error)")
        }
        XCTAssertEqual(usageLimit.planType, .pro)
        XCTAssertEqual(usageLimit.resetsAt, Date(timeIntervalSince1970: 1_738_888_888))
        XCTAssertEqual(usageLimit.rateLimits?.limitID, "codex_other")
        XCTAssertEqual(usageLimit.rateLimits?.limitName, "codex_other")
        XCTAssertEqual(usageLimit.rateLimits?.primary?.usedPercent, 100)
        XCTAssertEqual(usageLimit.rateLimits?.primary?.windowMinutes, 15)
        XCTAssertEqual(usageLimit.promoMessage, "Visit the usage page")
    }

    func testCodexErrorBridgeDoesNotFallbackLimitNameToLimitIDLikeRust() throws {
        let body = #"{"error":{"type":"usage_limit_reached","plan_type":"pro"}}"#
        let error = CodexError(apiError: .transport(.http(
            statusCode: 429,
            headers: ["x-codex-active-limit": "codex_other"],
            body: body
        )))

        guard case let .usageLimitReached(usageLimit) = error else {
            return XCTFail("expected usage limit, got \(error)")
        }
        XCTAssertEqual(usageLimit.rateLimits?.limitID, "codex_other")
        XCTAssertNil(usageLimit.rateLimits?.limitName)
    }

    func testCodexErrorBridgeExtractsTrackingAndIdentityHeadersLikeRust() {
        let xErrorJSON = Data(#"{"error":{"code":"token_expired"}}"#.utf8).base64EncodedString()
        let error = CodexError(apiError: .transport(.http(
            statusCode: 401,
            url: "https://api.example.test/responses",
            headers: [
                "x-request-id": "req-401",
                "cf-ray": "ray-401",
                "x-openai-authorization-error": "missing_authorization_header",
                "x-error-json": xErrorJSON
            ],
            body: #"{"detail":"Unauthorized"}"#
        )))

        guard case let .unexpectedStatus(unexpected) = error else {
            return XCTFail("expected unexpected status, got \(error)")
        }
        XCTAssertEqual(unexpected.url, "https://api.example.test/responses")
        XCTAssertEqual(unexpected.requestID, "req-401")
        XCTAssertEqual(unexpected.cfRay, "ray-401")
        XCTAssertEqual(unexpected.identityAuthorizationError, "missing_authorization_header")
        XCTAssertEqual(unexpected.identityErrorCode, "token_expired")
    }

    func testCodexErrorBridgeMaps429FallbackAndTransportErrorsLikeRust() {
        XCTAssertEqual(
            CodexError(apiError: .transport(.http(
                statusCode: 429,
                headers: ["cf-ray": "ray-429"],
                body: #"{"error":{"type":"other"}}"#
            ))),
            .retryLimit(RetryLimitReachedError(statusCode: 429, requestID: "ray-429"))
        )
        XCTAssertEqual(CodexError(apiError: .transport(.timeout)), .timeout)
        XCTAssertEqual(
            CodexError(apiError: .transport(.network("dns failed"))),
            .stream(message: "dns failed", delay: nil)
        )
        XCTAssertEqual(
            CodexError(apiError: .rateLimit("credits exhausted")),
            .stream(message: "credits exhausted", delay: nil)
        )
    }

    func testCodexErrorProtocolMappingMatchesRust() {
        XCTAssertEqual(CodexError.contextWindowExceeded.toCodexProtocolError(), .contextWindowExceeded)
        XCTAssertEqual(
            CodexError.usageLimitReached(UsageLimitReachedError()).toCodexProtocolError(),
            .usageLimitExceeded
        )
        XCTAssertEqual(CodexError.quotaExceeded.toCodexProtocolError(), .usageLimitExceeded)
        XCTAssertEqual(CodexError.usageNotIncluded.toCodexProtocolError(), .usageLimitExceeded)
        XCTAssertEqual(CodexError.serverOverloaded.toCodexProtocolError(), .serverOverloaded)
        XCTAssertEqual(
            CodexError.cyberPolicy(message: "blocked").toCodexProtocolError(),
            .cyberPolicy
        )
        XCTAssertEqual(
            CodexError.retryLimit(RetryLimitReachedError(statusCode: 429)).toCodexProtocolError(),
            .responseTooManyFailedAttempts(httpStatusCode: 429)
        )
        XCTAssertEqual(
            CodexError.connectionFailed(ConnectionFailedError(statusCode: 503, url: "http://example.com/"))
                .toCodexProtocolError(),
            .httpConnectionFailed(httpStatusCode: 503)
        )
        XCTAssertEqual(
            CodexError.responseStreamFailed(ResponseStreamFailedError(statusCode: 502, url: "http://example.com/"))
                .toCodexProtocolError(),
            .responseStreamConnectionFailed(httpStatusCode: 502)
        )
        XCTAssertEqual(CodexError.internalServerError.toCodexProtocolError(), .internalServerError)
        XCTAssertEqual(CodexError.invalidRequest("bad prompt").toCodexProtocolError(), .other)
        XCTAssertEqual(CodexError.timeout.toCodexProtocolError(), .other)
    }

    func testCodexErrorToErrorEventHandlesResponseStreamFailedLikeRust() {
        let event = CodexError.responseStreamFailed(ResponseStreamFailedError(
            statusCode: 429,
            url: "http://example.com/",
            requestID: "req-123"
        )).toErrorEvent(messagePrefix: "prefix")

        XCTAssertEqual(
            event.message,
            "prefix: Error while reading the server response: HTTP status client error (429 Too Many Requests) for url (http://example.com/), request id: req-123"
        )
        XCTAssertEqual(
            event.codexErrorInfo,
            .responseStreamConnectionFailed(httpStatusCode: 429)
        )
    }

    func testCodexErrorToErrorEventUsesRustMessagePrefixAndDefaultInfo() {
        XCTAssertEqual(
            CodexError.invalidRequest("bad prompt").toErrorEvent(),
            ErrorEvent(message: "bad prompt", codexErrorInfo: .other)
        )
        XCTAssertEqual(
            CodexError.retryLimit(RetryLimitReachedError(statusCode: 700)).toErrorEvent(messagePrefix: "turn failed"),
            ErrorEvent(
                message: "turn failed: exceeded retry limit, last status: 700 <unknown status code>",
                codexErrorInfo: .responseTooManyFailedAttempts(httpStatusCode: 700)
            )
        )
        XCTAssertEqual(
            CodexError.retryLimit(RetryLimitReachedError(statusCode: 70_000)).toCodexProtocolError(),
            .responseTooManyFailedAttempts(httpStatusCode: nil)
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

    func testRetryLimitReachedErrorDisplayMatchesRustShape() {
        XCTAssertEqual(
            String(describing: RetryLimitReachedError(statusCode: 429)),
            "exceeded retry limit, last status: 429 Too Many Requests"
        )
        XCTAssertEqual(
            String(describing: RetryLimitReachedError(statusCode: 503, requestID: "req-3")),
            "exceeded retry limit, last status: 503 Service Unavailable, request id: req-3"
        )
    }

    func testEnvVarErrorDisplayMatchesRustShape() {
        XCTAssertEqual(
            String(describing: EnvVarError(variable: "OPENAI_API_KEY")),
            "Missing environment variable: `OPENAI_API_KEY`."
        )
        XCTAssertEqual(
            String(describing: EnvVarError(variable: "CODEX_HOME", instructions: "Set it before starting Codex.")),
            "Missing environment variable: `CODEX_HOME`. Set it before starting Codex."
        )
    }

    func testUsageLimitReachedErrorFormatsPlanSpecificRustMessagesWithoutReset() {
        XCTAssertEqual(
            String(describing: UsageLimitReachedError(planType: .plus)),
            """
            You've hit your usage limit. Upgrade to Pro (https://chatgpt.com/explore/pro), visit https://chatgpt.com/codex/settings/usage to purchase more credits or try again later.
            """
        )
        XCTAssertEqual(
            String(describing: UsageLimitReachedError(planType: .free)),
            "You've hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again later."
        )
        XCTAssertEqual(
            String(describing: UsageLimitReachedError(planType: .go)),
            "You've hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again later."
        )
        XCTAssertEqual(
            String(describing: UsageLimitReachedError(planType: .proLite)),
            "You've hit your usage limit. Visit https://chatgpt.com/codex/settings/usage to purchase more credits or try again later."
        )
        XCTAssertEqual(
            String(describing: UsageLimitReachedError(planType: .team)),
            "You've hit your usage limit. To get more access now, send a request to your admin or try again later."
        )
        XCTAssertEqual(
            String(describing: UsageLimitReachedError(planType: .enterprise)),
            "You've hit your usage limit. Try again later."
        )
        XCTAssertEqual(
            String(describing: UsageLimitReachedError()),
            "You've hit your usage limit. Try again later."
        )
    }

    func testUsageLimitReachedErrorUsesLimitNameBeforeUpsellLikeRust() {
        let snapshot = RateLimitSnapshot(
            limitID: "codex_other",
            limitName: " codex_other ",
            primary: nil,
            secondary: nil,
            credits: nil,
            planType: nil
        )

        XCTAssertEqual(
            String(describing: UsageLimitReachedError(
                planType: .plus,
                rateLimits: snapshot,
                promoMessage: "Visit https://chatgpt.com/codex/settings/usage to purchase more credits"
            )),
            "You've hit your usage limit for codex_other. Switch to another model now, or try again later."
        )
    }

    func testUsageLimitReachedErrorUsesPromoMessageBeforePlanLikeRust() {
        XCTAssertEqual(
            String(describing: UsageLimitReachedError(
                planType: .plus,
                promoMessage: "To continue using Codex, start a free trial of <PLAN> today"
            )),
            "You've hit your usage limit. To continue using Codex, start a free trial of <PLAN> today, or try again later."
        )
    }

    func testUsageLimitReachedErrorFormatsSameDayResetTimeLikeRust() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01 00:00:00 UTC
        let resetsAt = Date(timeIntervalSince1970: 1_704_070_800) // 2024-01-01 01:00:00 UTC

        XCTAssertEqual(
            UsageLimitReachedError(planType: .team, resetsAt: resetsAt).description(now: now, calendar: calendar),
            "You've hit your usage limit. To get more access now, send a request to your admin or try again at 1:00 AM."
        )
    }

    func testUsageLimitReachedErrorFormatsFutureDateWithOrdinalSuffixLikeRust() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01 00:00:00 UTC
        let resetsAt = Date(timeIntervalSince1970: 1_705_365_300) // 2024-01-16 00:35:00 UTC

        XCTAssertEqual(
            UsageLimitReachedError(planType: .unknown("future-plan"), resetsAt: resetsAt).description(now: now, calendar: calendar),
            "You've hit your usage limit. Try again at Jan 16th, 2024 12:35 AM."
        )
    }
}
