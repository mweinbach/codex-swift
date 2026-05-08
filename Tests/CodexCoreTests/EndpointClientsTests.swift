import CodexCore
import XCTest

final class EndpointClientsTests: XCTestCase {
    func testModelsClientExecutesWithAuthRetryTelemetryAndDecodesETag() async throws {
        let responseBody = try JSONEncoder().encode(ModelsResponse(models: [], etag: "body-etag"))
        let transport = CapturingTransport(
            executeResults: [
                .failure(.http(statusCode: 503, headers: nil, body: "busy")),
                .success(APIResponse(statusCode: 200, headers: ["ETag": "header-etag"], body: responseBody))
            ]
        )
        let telemetry = CapturingRequestTelemetry()
        let client = ModelsClient(
            transport: transport,
            provider: provider(
                baseURL: "https://example.com/api/codex",
                headers: ["x-provider": "provider"]
            ),
            auth: StaticAPIAuthProvider(bearerToken: "tok", accountID: "acct")
        )
        .withTelemetry(telemetry)

        let result = await client.listModels(
            clientVersion: "0.99.0",
            extraHeaders: ["x-extra": "extra"]
        )

        XCTAssertEqual(result, .success(ModelsResponse(models: [], etag: "header-etag")))
        XCTAssertEqual(transport.executeRequests.count, 2)
        XCTAssertEqual(
            transport.executeRequests.map(\.url),
            [
                "https://example.com/api/codex/models?client_version=0.99.0",
                "https://example.com/api/codex/models?client_version=0.99.0"
            ]
        )
        XCTAssertEqual(transport.executeRequests[0].method, .get)
        XCTAssertNil(transport.executeRequests[0].body)
        XCTAssertEqual(transport.executeRequests[0].headers["x-provider"], "provider")
        XCTAssertEqual(transport.executeRequests[0].headers["x-extra"], "extra")
        XCTAssertEqual(transport.executeRequests[0].headers["authorization"], "Bearer tok")
        XCTAssertEqual(transport.executeRequests[0].headers["ChatGPT-Account-ID"], "acct")
        XCTAssertEqual(telemetry.records.map(\.statusCode), [503, 200])
    }

    func testCompactClientPostsBodyWithAuthAndDecodesOutput() async throws {
        let output: [ResponseItem] = [
            .message(role: "assistant", content: [.outputText(text: "summary")])
        ]
        let transport = CapturingTransport(
            executeResults: [
                .success(APIResponse(
                    statusCode: 200,
                    body: try JSONEncoder().encode(CompactHistoryResponse(output: output))
                ))
            ]
        )
        let input = CompactionInput(
            model: "gpt-test",
            input: [.message(role: "user", content: [.inputText(text: "long")])],
            instructions: "summarize"
        )
        let client = CompactClient(
            transport: transport,
            provider: provider(headers: ["x-provider": "provider"]),
            auth: StaticAPIAuthProvider(bearerToken: "tok")
        )

        let result = await client.compactInput(input, extraHeaders: ["x-extra": "extra"])

        XCTAssertEqual(result, .success(output))
        XCTAssertEqual(transport.executeRequests.count, 1)
        let request = try XCTUnwrap(transport.executeRequests.first)
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.url, "https://example.com/v1/responses/compact")
        XCTAssertEqual(request.body, try CompactAPI.body(for: input))
        XCTAssertEqual(request.headers["x-provider"], "provider")
        XCTAssertEqual(request.headers["x-extra"], "extra")
        XCTAssertEqual(request.headers["authorization"], "Bearer tok")
    }

    func testCompactClientRejectsChatWireAPIWithoutTransport() async {
        let transport = CapturingTransport()
        let client = CompactClient(
            transport: transport,
            provider: provider(wireAPI: .chat),
            auth: StaticAPIAuthProvider()
        )

        let result = await client.compactInput(CompactionInput(model: "gpt-test", input: [], instructions: "inst"))

        XCTAssertEqual(result, .failure(.stream("compact endpoint requires responses wire api")))
        XCTAssertTrue(transport.executeRequests.isEmpty)
    }

    func testResponsesClientStreamsWithAcceptAuthAndResponseParser() async {
        let transport = CapturingTransport(
            streamResults: [
                .success(APIStreamResponse(statusCode: 200, sseText: """
                data: {"type":"response.created","response":{}}

                data: {"type":"response.completed","response":{"id":"resp_1","usage":null}}

                """))
            ]
        )
        let body: JSONValue = .object(["model": .string("gpt-test")])
        let client = ResponsesClient(
            transport: transport,
            provider: provider(queryParams: ["api-version": "2025-04-01-preview"]),
            auth: StaticAPIAuthProvider(bearerToken: "tok")
        )

        let result = await client.stream(
            body: body,
            extraHeaders: ["accept": "application/json", "x-extra": "extra"]
        )

        XCTAssertEqual(result, .success([
            .success(.rateLimits(RateLimitSnapshot(primary: nil, secondary: nil, credits: nil, planType: nil))),
            .success(.created),
            .success(.completed(responseID: "resp_1", tokenUsage: nil))
        ]))
        XCTAssertEqual(transport.streamRequests.count, 1)
        let request = transport.streamRequests[0]
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.url, "https://example.com/v1/responses?api-version=2025-04-01-preview")
        XCTAssertEqual(request.body, body)
        XCTAssertEqual(request.headers["accept"], "text/event-stream")
        XCTAssertEqual(request.headers["x-extra"], "extra")
        XCTAssertEqual(request.headers["authorization"], "Bearer tok")
    }

    func testResponsesClientParsesStreamingChunksAcrossUTF8AndSSEBoundaries() async {
        let delta = "hel\u{1F30A}"
        let sse = """
        data: {"type":"response.output_text.delta","delta":"\(delta)"}

        data: {"type":"response.completed","response":{"id":"resp_1","usage":null}}

        """
        let bytes = Data(sse.utf8)
        let emojiStart = bytes.firstIndex(of: 0xF0)!
        let splitInsideEmoji = emojiStart + 2
        let transport = CapturingTransport(
            streamResults: [
                .success(APIStreamResponse(
                    statusCode: 200,
                    byteStream: byteStream([
                        Data(bytes[..<splitInsideEmoji]),
                        Data(bytes[splitInsideEmoji...])
                    ])
                ))
            ]
        )
        let client = ResponsesClient(
            transport: transport,
            provider: provider(),
            auth: StaticAPIAuthProvider()
        )

        let result = await client.stream(body: .object([:]))

        XCTAssertEqual(result, .success([
            .success(.rateLimits(RateLimitSnapshot(primary: nil, secondary: nil, credits: nil, planType: nil))),
            .success(.outputTextDelta(delta)),
            .success(.completed(responseID: "resp_1", tokenUsage: nil))
        ]))
    }

    func testResponsesClientReturnsTransportErrorForStreamChunkFailure() async {
        let transport = CapturingTransport(
            streamResults: [
                .success(APIStreamResponse(
                    statusCode: 200,
                    byteStream: APIByteStream { continuation in
                        continuation.yield(.success(Data("data: ".utf8)))
                        continuation.yield(.failure(.network("reset")))
                        continuation.finish()
                    }
                ))
            ]
        )
        let client = ResponsesClient(
            transport: transport,
            provider: provider(),
            auth: StaticAPIAuthProvider()
        )

        let result = await client.stream(body: .object([:]))

        XCTAssertEqual(result, .success([
            .success(.rateLimits(RateLimitSnapshot(primary: nil, secondary: nil, credits: nil, planType: nil))),
            .failure(.stream("network error: reset"))
        ]))
    }

    func testResponsesClientStreamEventsEmitsRateLimitsBeforeSSEEvents() async {
        let snapshot = RateLimitSnapshot(
            primary: RateLimitWindow(usedPercent: 42, windowMinutes: 300, resetsAt: nil),
            secondary: nil,
            credits: nil,
            planType: nil
        )
        let transport = CapturingTransport(
            streamResults: [
                .success(APIStreamResponse(
                    statusCode: 200,
                    headers: [
                        "x-codex-primary-used-percent": "42",
                        "x-codex-primary-window-minutes": "300"
                    ],
                    sseText: """
                    data: {"type":"response.completed","response":{"id":"resp_1","usage":null}}

                    """
                ))
            ]
        )
        let client = ResponsesClient(
            transport: transport,
            provider: provider(),
            auth: StaticAPIAuthProvider()
        )

        let result = await client.streamEvents(body: .object([:]))

        guard case let .success(stream) = result else {
            return XCTFail("expected event stream, got \(result)")
        }
        let events = await collect(stream)

        XCTAssertEqual(events, [
            .success(.rateLimits(snapshot)),
            .success(.completed(responseID: "resp_1", tokenUsage: nil))
        ])
    }

    func testChatClientStreamEventsDoesNotEmitRateLimits() async {
        let transport = CapturingTransport(
            streamResults: [
                .success(APIStreamResponse(
                    statusCode: 200,
                    headers: [
                        "x-codex-primary-used-percent": "42",
                        "x-codex-primary-window-minutes": "300"
                    ],
                    sseText: """
                    data: {"choices":[{"delta":{},"finish_reason":"stop"}]}

                    """
                ))
            ]
        )
        let client = ChatClient(
            transport: transport,
            provider: provider(wireAPI: .chat),
            auth: StaticAPIAuthProvider()
        )

        let result = await client.streamEvents(body: .object([:]))

        guard case let .success(stream) = result else {
            return XCTFail("expected event stream, got \(result)")
        }
        let events = await collect(stream)

        XCTAssertEqual(events, [
            .success(.completed(responseID: "", tokenUsage: nil))
        ])
    }

    func testResponsesClientRecordsSseTelemetryForChunksAndClose() async {
        let telemetry = CapturingSseTelemetry()
        let transport = CapturingTransport(
            streamResults: [
                .success(APIStreamResponse(statusCode: 200, sseText: """
                data: {"type":"response.completed","response":{"id":"resp_telemetry","usage":null}}

                """))
            ]
        )
        let client = ResponsesClient(
            transport: transport,
            provider: provider(),
            auth: StaticAPIAuthProvider()
        )
        .withTelemetry(request: nil, sse: telemetry)

        let result = await client.streamEvents(body: .object([:]))

        guard case let .success(stream) = result else {
            return XCTFail("expected event stream, got \(result)")
        }

        _ = await collect(stream)

        XCTAssertEqual(telemetry.records.map(\.result), [.event, .streamClosed])
    }

    func testResponsesClientEmitsIdleTimeoutWhenSsePollStalls() async {
        let telemetry = CapturingSseTelemetry()
        let transport = CapturingTransport(
            streamResults: [
                .success(APIStreamResponse(
                    statusCode: 200,
                    byteStream: APIByteStream { _ in }
                ))
            ]
        )
        let client = ResponsesClient(
            transport: transport,
            provider: provider(streamIdleTimeoutMilliseconds: 1),
            auth: StaticAPIAuthProvider()
        )
        .withTelemetry(request: nil, sse: telemetry)

        let result = await client.streamEvents(body: .object([:]))

        guard case let .success(stream) = result else {
            return XCTFail("expected event stream, got \(result)")
        }
        let events = await collect(stream)

        XCTAssertEqual(events, [
            .success(.rateLimits(RateLimitSnapshot(primary: nil, secondary: nil, credits: nil, planType: nil))),
            .failure(.stream("idle timeout waiting for SSE"))
        ])
        XCTAssertEqual(telemetry.records.map(\.result), [.idleTimeout])
    }

    func testResponsesSSEFixtureStreamReadsFixtureLinesAsEventsWithoutRateLimits() async throws {
        let telemetry = CapturingSseTelemetry()
        let fixtureURL = try writeFixture("""
        data: {"type":"response.created","response":{}}
        data: {"type":"response.output_text.delta","delta":"fixture"}
        data: {"type":"response.completed","response":{"id":"resp_fixture","usage":null}}
        """)

        let result = ResponsesSSEFixtureStream.streamFromFixture(
            path: fixtureURL.path,
            idleTimeoutMilliseconds: 1_000,
            telemetry: telemetry
        )

        guard case let .success(stream) = result else {
            return XCTFail("expected fixture event stream, got \(result)")
        }

        let events = await collect(stream)

        XCTAssertEqual(events, [
            .success(.created),
            .success(.outputTextDelta("fixture")),
            .success(.completed(responseID: "resp_fixture", tokenUsage: nil))
        ])
        XCTAssertEqual(telemetry.records.map(\.result), [.event, .streamClosed])
    }

    func testResponsesSSEFixtureStreamReportsFileReadError() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing.sse")

        let result = ResponsesSSEFixtureStream.streamFromFixture(
            path: missing.path,
            idleTimeoutMilliseconds: 1_000
        )

        guard case let .failure(.stream(message)) = result else {
            return XCTFail("expected stream error, got \(result)")
        }
        XCTAssertFalse(message.isEmpty)
    }

    func testResponsesClientUsesChatPathWhenProviderWireIsChat() async {
        let transport = CapturingTransport(
            streamResults: [
                .success(APIStreamResponse(statusCode: 200, sseText: """
                data: {"type":"response.completed","response":{"id":"resp_1","usage":null}}

                """))
            ]
        )
        let client = ResponsesClient(
            transport: transport,
            provider: provider(wireAPI: .chat),
            auth: StaticAPIAuthProvider()
        )

        _ = await client.stream(body: .object([:]))

        XCTAssertEqual(transport.streamRequests.first?.url, "https://example.com/v1/chat/completions")
    }

    func testChatClientStreamsWithChatParserAndRouteSelection() async {
        let transport = CapturingTransport(
            streamResults: [
                .success(APIStreamResponse(statusCode: 200, sseText: """
                data: {"choices":[{"delta":{"content":"hi"},"finish_reason":null}]}

                data: {"choices":[{"delta":{},"finish_reason":"stop"}]}

                """))
            ]
        )
        let client = ChatClient(
            transport: transport,
            provider: provider(wireAPI: .chat),
            auth: StaticAPIAuthProvider()
        )

        let result = await client.stream(body: .object(["model": .string("gpt-test")]))

        XCTAssertEqual(result, .success([
            .success(.outputItemAdded(.message(role: "assistant", content: []))),
            .success(.outputTextDelta("hi")),
            .success(.outputItemDone(.message(role: "assistant", content: [.outputText(text: "hi")]))),
            .success(.completed(responseID: "", tokenUsage: nil))
        ]))
        XCTAssertEqual(transport.streamRequests.first?.url, "https://example.com/v1/chat/completions")
    }

    private func provider(
        wireAPI: WireAPI = .responses,
        baseURL: String = "https://example.com/v1",
        queryParams: [String: String]? = nil,
        headers: [String: String] = [:],
        streamIdleTimeoutMilliseconds: UInt64 = 1_000
    ) -> APIProvider {
        APIProvider(
            name: "test",
            baseURL: baseURL,
            queryParams: queryParams,
            wireAPI: wireAPI,
            headers: headers,
            retry: ProviderRetryConfig(
                maxAttempts: 1,
                baseDelayMilliseconds: 1,
                retry429: true,
                retry5xx: true,
                retryTransport: true
            ),
            streamIdleTimeoutMilliseconds: streamIdleTimeoutMilliseconds
        )
    }
}

private func writeFixture(_ contents: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("fixture.sse")
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url
}

private final class CapturingTransport: APITransport, @unchecked Sendable {
    private var executeResults: [Result<APIResponse, TransportError>]
    private var streamResults: [Result<APIStreamResponse, TransportError>]
    private(set) var executeRequests: [APIRequest] = []
    private(set) var streamRequests: [APIRequest] = []

    init(
        executeResults: [Result<APIResponse, TransportError>] = [],
        streamResults: [Result<APIStreamResponse, TransportError>] = []
    ) {
        self.executeResults = executeResults
        self.streamResults = streamResults
    }

    func execute(_ request: APIRequest) async -> Result<APIResponse, TransportError> {
        executeRequests.append(request)
        guard !executeResults.isEmpty else {
            return .failure(.build("missing execute result"))
        }
        return executeResults.removeFirst()
    }

    func stream(_ request: APIRequest) async -> Result<APIStreamResponse, TransportError> {
        streamRequests.append(request)
        guard !streamResults.isEmpty else {
            return .failure(.build("missing stream result"))
        }
        return streamResults.removeFirst()
    }
}

private func byteStream(_ chunks: [Data]) -> APIByteStream {
    APIByteStream { continuation in
        for chunk in chunks {
            continuation.yield(.success(chunk))
        }
        continuation.finish()
    }
}

private func collect(_ stream: ResponseEventStream) async -> ResponseEventResults {
    var events: ResponseEventResults = []
    for await event in stream {
        events.append(event)
    }
    return events
}

private final class CapturingRequestTelemetry: RequestTelemetry {
    struct Record: Equatable {
        let attempt: UInt64
        let statusCode: Int?
        let error: TransportError?
    }

    private(set) var records: [Record] = []

    func onRequest(
        attempt: UInt64,
        statusCode: Int?,
        error: TransportError?,
        duration _: Duration
    ) {
        records.append(Record(attempt: attempt, statusCode: statusCode, error: error))
    }
}

private final class CapturingSseTelemetry: SseTelemetry {
    struct Record: Equatable {
        let result: SsePollResult
    }

    private(set) var records: [Record] = []

    func onSSEPoll(result: SsePollResult, duration _: Duration) {
        records.append(Record(result: result))
    }
}
