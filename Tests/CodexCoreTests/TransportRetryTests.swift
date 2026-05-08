import CodexCore
import XCTest

final class TransportRetryTests: XCTestCase {
    func testTransportErrorDescriptionsMatchRustThisErrorStrings() {
        XCTAssertEqual(
            String(describing: TransportError.http(statusCode: 429, headers: nil, body: "slow down")),
            #"http 429 Too Many Requests: Some("slow down")"#
        )
        XCTAssertEqual(
            String(describing: TransportError.http(statusCode: 599, headers: [:], body: nil)),
            "http 599 <unknown status code>: None"
        )
        XCTAssertEqual(String(describing: TransportError.retryLimit), "retry limit reached")
        XCTAssertEqual(String(describing: TransportError.timeout), "timeout")
        XCTAssertEqual(String(describing: TransportError.network("offline")), "network error: offline")
        XCTAssertEqual(String(describing: TransportError.build("bad url")), "request build error: bad url")
    }

    func testStreamErrorDescriptionsMatchRustThisErrorStrings() {
        XCTAssertEqual(String(describing: StreamError.stream("bad frame")), "stream failed: bad frame")
        XCTAssertEqual(String(describing: StreamError.timeout), "timeout")
    }

    func testRetryOnShouldRetryMatchesRustPolicy() {
        let retry = ProviderRetryOn(retry429: true, retry5xx: true, retryTransport: true)

        XCTAssertTrue(retry.shouldRetry(.http(statusCode: 429, headers: nil, body: nil), attempt: 0, maxAttempts: 2))
        XCTAssertTrue(retry.shouldRetry(.http(statusCode: 500, headers: nil, body: nil), attempt: 0, maxAttempts: 2))
        XCTAssertTrue(retry.shouldRetry(.http(statusCode: 599, headers: nil, body: nil), attempt: 0, maxAttempts: 2))
        XCTAssertTrue(retry.shouldRetry(.timeout, attempt: 0, maxAttempts: 2))
        XCTAssertTrue(retry.shouldRetry(.network("reset"), attempt: 0, maxAttempts: 2))

        XCTAssertFalse(retry.shouldRetry(.http(statusCode: 418, headers: nil, body: nil), attempt: 0, maxAttempts: 2))
        XCTAssertFalse(retry.shouldRetry(.build("bad request"), attempt: 0, maxAttempts: 2))
        XCTAssertFalse(retry.shouldRetry(.retryLimit, attempt: 0, maxAttempts: 2))
        XCTAssertFalse(retry.shouldRetry(.http(statusCode: 500, headers: nil, body: nil), attempt: 2, maxAttempts: 2))
    }

    func testRetryOnHonorsDisabledBuckets() {
        let retry = ProviderRetryOn(retry429: false, retry5xx: false, retryTransport: false)

        XCTAssertFalse(retry.shouldRetry(.http(statusCode: 429, headers: nil, body: nil), attempt: 0, maxAttempts: 1))
        XCTAssertFalse(retry.shouldRetry(.http(statusCode: 503, headers: nil, body: nil), attempt: 0, maxAttempts: 1))
        XCTAssertFalse(retry.shouldRetry(.timeout, attempt: 0, maxAttempts: 1))
        XCTAssertFalse(retry.shouldRetry(.network("reset"), attempt: 0, maxAttempts: 1))
    }

    func testProviderRetryPolicyBackoffUsesConfiguredBaseAndRustExponent() {
        let policy = ProviderRetryPolicy(
            maxAttempts: 4,
            baseDelayMilliseconds: 250,
            retryOn: ProviderRetryOn(retry429: true, retry5xx: true, retryTransport: true)
        )

        XCTAssertEqual(policy.backoffMilliseconds(attempt: 0, jitter: { 1.0 }), 250)
        XCTAssertEqual(policy.backoffMilliseconds(attempt: 1, jitter: { 1.0 }), 250)
        XCTAssertEqual(policy.backoffMilliseconds(attempt: 2, jitter: { 1.0 }), 500)
        XCTAssertEqual(policy.backoffMilliseconds(attempt: 4, jitter: { 1.0 }), 2_000)
        XCTAssertEqual(policy.backoffMilliseconds(attempt: 2, jitter: { 0.9 }), 450)
        XCTAssertEqual(policy.backoffMilliseconds(attempt: 2, jitter: { 1.099 }), 549)
    }

    func testRunWithRetryRebuildsRequestAndSleepsBeforeRetry() async {
        let policy = ProviderRetryPolicy(
            maxAttempts: 2,
            baseDelayMilliseconds: 250,
            retryOn: ProviderRetryOn(retry429: true, retry5xx: false, retryTransport: false)
        )
        var requestBuilds: [String] = []
        var attempts: [UInt64] = []
        var sleeps: [UInt64] = []

        let result: Result<String, TransportError> = await TransportRetry.runWithRetry(
            policy: policy,
            makeRequest: {
                let request = APIRequest(method: .get, url: "https://example.com/\(requestBuilds.count)")
                requestBuilds.append(request.url)
                return request
            },
            sleep: { milliseconds in sleeps.append(milliseconds) }
        ) { request, attempt in
            attempts.append(attempt)
            if request.url.hasSuffix("/0") {
                return .failure(.http(statusCode: 429, headers: nil, body: nil))
            }
            return .success("ok")
        }

        XCTAssertEqual(result, .success("ok"))
        XCTAssertEqual(requestBuilds, ["https://example.com/0", "https://example.com/1"])
        XCTAssertEqual(attempts, [0, 1])
        XCTAssertEqual(sleeps.count, 1)
        XCTAssertTrue((225..<275).contains(sleeps[0]), "sleep \(sleeps[0]) should include Rust jitter")
    }

    func testRunWithRetryStopsWhenErrorBucketIsNotRetryable() async {
        let policy = ProviderRetryPolicy(
            maxAttempts: 2,
            baseDelayMilliseconds: 250,
            retryOn: ProviderRetryOn(retry429: false, retry5xx: false, retryTransport: false)
        )
        var attempts: [UInt64] = []

        let result: Result<String, TransportError> = await TransportRetry.runWithRetry(
            policy: policy,
            makeRequest: { APIRequest(method: .get, url: "https://example.com") },
            sleep: { _ in XCTFail("sleep should not run") }
        ) { _, attempt in
            attempts.append(attempt)
            return .failure(.http(statusCode: 429, headers: nil, body: nil))
        }

        XCTAssertEqual(result, .failure(.http(statusCode: 429, headers: nil, body: nil)))
        XCTAssertEqual(attempts, [0])
    }

    func testRunWithRequestTelemetryRecordsStatusAndErrorsPerAttempt() async {
        let policy = ProviderRetryPolicy(
            maxAttempts: 1,
            baseDelayMilliseconds: 250,
            retryOn: ProviderRetryOn(retry429: false, retry5xx: true, retryTransport: false)
        )
        let telemetry = CapturingRequestTelemetry()
        var attempts: [UInt64] = []

        let result: Result<APIResponse, TransportError> = await TransportRetry.runWithRequestTelemetry(
            policy: policy,
            telemetry: telemetry,
            makeRequest: { APIRequest(method: .get, url: "https://example.com") },
            sleep: { _ in }
        ) { _ in
            let attempt = UInt64(attempts.count)
            attempts.append(attempt)
            if attempt == 0 {
                return .failure(.http(statusCode: 503, headers: nil, body: "busy"))
            }
            return .success(APIResponse(statusCode: 200))
        }

        XCTAssertEqual(result, .success(APIResponse(statusCode: 200)))
        XCTAssertEqual(telemetry.records.map(\.attempt), [0, 1])
        XCTAssertEqual(telemetry.records.map(\.statusCode), [503, 200])
        XCTAssertEqual(telemetry.records.map(\.error), [
            .http(statusCode: 503, headers: nil, body: "busy"),
            nil
        ])
    }
}

private final class CapturingRequestTelemetry: RequestTelemetry {
    struct Record: Equatable {
        let attempt: UInt64
        let statusCode: Int?
        let error: TransportError?
    }

    var records: [Record] = []

    func onRequest(
        attempt: UInt64,
        statusCode: Int?,
        error: TransportError?,
        duration _: Duration
    ) {
        records.append(Record(attempt: attempt, statusCode: statusCode, error: error))
    }
}
