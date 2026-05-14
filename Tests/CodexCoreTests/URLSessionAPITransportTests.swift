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
            .failure(.http(
                statusCode: 429,
                url: "https://example.com/v1/models",
                headers: ["retry-after": "1"],
                body: "slow down"
            ))
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

    func testStreamUsesConfiguredStreamingSenderAndCollectsChunks() async {
        let transport = URLSessionAPITransport(
            send: { _ in
                XCTFail("streaming path should not use the buffered sender")
                return URLSessionTransportResponse(statusCode: 200)
            },
            stream: { request in
                XCTAssertEqual(request.httpMethod, "POST")
                return APIStreamResponse(
                    statusCode: 200,
                    headers: ["content-type": "text/event-stream"],
                    byteStream: Self.byteStream([
                        Data("data: {\"type\":\"response.created\"".utf8),
                        Data(",\"response\":{}}\n\n".utf8)
                    ])
                )
            }
        )

        let result = await transport.stream(APIRequest(
            method: .post,
            url: "https://example.com/v1/responses",
            body: .object([:])
        ))

        guard case let .success(response) = result else {
            return XCTFail("expected stream response, got \(result)")
        }

        XCTAssertNil(response.sseText)
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.headers["content-type"], "text/event-stream")
        let collectedText = await response.collectSSEText()
        XCTAssertEqual(
            collectedText,
            .success("data: {\"type\":\"response.created\",\"response\":{}}\n\n")
        )
    }

    func testStreamHTTPFailureCollectsStreamingBody() async {
        let transport = URLSessionAPITransport(
            send: { _ in
                XCTFail("streaming path should not use the buffered sender")
                return URLSessionTransportResponse(statusCode: 200)
            },
            stream: { _ in
                APIStreamResponse(
                    statusCode: 503,
                    headers: ["retry-after": "2"],
                    byteStream: Self.byteStream([
                        Data("temporarily ".utf8),
                        Data("unavailable".utf8)
                    ])
                )
            }
        )

        let result = await transport.stream(APIRequest(method: .post, url: "https://example.com/v1/responses"))

        XCTAssertEqual(
            result,
            .failure(.http(
                statusCode: 503,
                url: "https://example.com/v1/responses",
                headers: ["retry-after": "2"],
                body: "temporarily unavailable"
            ))
        )
    }

    private static func byteStream(_ chunks: [Data]) -> APIByteStream {
        APIByteStream { continuation in
            for chunk in chunks {
                continuation.yield(.success(chunk))
            }
            continuation.finish()
        }
    }
}

private final class URLRequestCapture: @unchecked Sendable {
    var requests: [URLRequest] = []
}
