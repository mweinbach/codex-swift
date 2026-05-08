import CodexCore
import XCTest

final class URLSessionAPITransportTests: XCTestCase {
    func testExecuteBuildsJSONURLRequestAndReturnsResponse() async throws {
        let capture = URLRequestCapture()
        let transport = URLSessionAPITransport { request in
            capture.requests.append(request)
            return URLSessionTransportResponse(
                statusCode: 200,
                headers: ["x-request-id": "req_123"],
                body: Data("ok".utf8)
            )
        }

        let result = await transport.execute(APIRequest(
            method: .post,
            url: "https://example.com/v1/responses",
            headers: ["x-test": "1"],
            body: .object(["answer": .integer(42)]),
            timeoutMilliseconds: 2_500
        ))

        XCTAssertEqual(result, .success(APIResponse(
            statusCode: 200,
            headers: ["x-request-id": "req_123"],
            body: Data("ok".utf8)
        )))
        let sent = try XCTUnwrap(capture.requests.first)
        XCTAssertEqual(sent.url?.absoluteString, "https://example.com/v1/responses")
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.timeoutInterval, 2.5)
        XCTAssertEqual(sent.value(forHTTPHeaderField: "x-test"), "1")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "content-type"), "application/json")
        XCTAssertEqual(
            try JSONDecoder().decode(JSONValue.self, from: try XCTUnwrap(sent.httpBody)),
            .object(["answer": .integer(42)])
        )
    }

    func testHTTPFailureMapsStatusHeadersAndBody() async {
        let transport = URLSessionAPITransport { _ in
            URLSessionTransportResponse(
                statusCode: 429,
                headers: ["retry-after": "1"],
                body: Data("slow down".utf8)
            )
        }

        let result = await transport.execute(APIRequest(method: .get, url: "https://example.com/v1/models"))

        XCTAssertEqual(
            result,
            .failure(.http(statusCode: 429, headers: ["retry-after": "1"], body: "slow down"))
        )
    }

    func testBuildAndTimeoutErrorsMapToTransportErrors() async {
        let invalidURLTransport = URLSessionAPITransport { _ in
            XCTFail("invalid URL should fail before sender runs")
            return URLSessionTransportResponse(statusCode: 200)
        }

        let invalidURLResult = await invalidURLTransport.execute(APIRequest(method: .get, url: "http://[::1"))
        XCTAssertEqual(invalidURLResult, .failure(.build("invalid URL: http://[::1")))

        let timeoutTransport = URLSessionAPITransport { _ in
            throw URLError(.timedOut)
        }

        let timeoutResult = await timeoutTransport.execute(APIRequest(method: .get, url: "https://example.com"))
        XCTAssertEqual(timeoutResult, .failure(.timeout))
    }

    func testStreamReturnsBufferedSSEText() async {
        let transport = URLSessionAPITransport { request in
            XCTAssertEqual(request.httpMethod, "POST")
            return URLSessionTransportResponse(
                statusCode: 200,
                headers: ["content-type": "text/event-stream"],
                body: Data("data: {\"type\":\"response.created\",\"response\":{}}\n\n".utf8)
            )
        }

        let result = await transport.stream(APIRequest(
            method: .post,
            url: "https://example.com/v1/responses",
            body: .object([:])
        ))

        XCTAssertEqual(result, .success(APIStreamResponse(
            statusCode: 200,
            headers: ["content-type": "text/event-stream"],
            sseText: "data: {\"type\":\"response.created\",\"response\":{}}\n\n"
        )))
    }
}

private final class URLRequestCapture: @unchecked Sendable {
    var requests: [URLRequest] = []
}
