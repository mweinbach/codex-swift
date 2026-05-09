import CodexCore
import XCTest

final class AcceptedLinesTests: XCTestCase {
    func testParsesCountsAndEffectiveAddedFingerprints() {
        let diff = """
        diff --git a/src/lib.rs b/src/lib.rs
        index 1111111..2222222
        --- a/src/lib.rs
        +++ b/src/lib.rs
        @@ -1,3 +1,5 @@
        -old line
        +fn useful() {
        +}
        +    return user.id;
         context
        """

        let summary = AcceptedLines.acceptedLineFingerprints(fromUnifiedDiff: diff)

        XCTAssertEqual(summary, AcceptedLineFingerprintSummary(
            acceptedAddedLines: 3,
            acceptedDeletedLines: 1,
            lineFingerprints: [
                AcceptedLineFingerprint(
                    pathHash: AcceptedLines.fingerprintHash(domain: "path", value: "src/lib.rs"),
                    lineHash: AcceptedLines.fingerprintHash(domain: "line", value: "fn useful() {")
                ),
                AcceptedLineFingerprint(
                    pathHash: AcceptedLines.fingerprintHash(domain: "path", value: "src/lib.rs"),
                    lineHash: AcceptedLines.fingerprintHash(domain: "line", value: "return user.id;")
                )
            ]
        ))
    }

    func testSkipsAddedFileMetadataHeaders() {
        let diff = """
        diff --git a/new.py b/new.py
        new file mode 100644
        index 0000000..1111111
        --- /dev/null
        +++ b/new.py
        @@ -0,0 +1 @@
        +print('hello')
        """

        let summary = AcceptedLines.acceptedLineFingerprints(fromUnifiedDiff: diff)

        XCTAssertEqual(summary.acceptedAddedLines, 1)
        XCTAssertEqual(summary.acceptedDeletedLines, 0)
        XCTAssertEqual(summary.lineFingerprints.count, 1)
    }

    func testParsesHunkLinesThatLookLikeFileHeaders() {
        let diff = """
        diff --git a/src/lib.rs b/src/lib.rs
        index 1111111..2222222
        --- a/src/lib.rs
        +++ b/src/lib.rs
        @@ -1,2 +1,2 @@
        --- old value
        +++ new value
        """

        let summary = AcceptedLines.acceptedLineFingerprints(fromUnifiedDiff: diff)

        XCTAssertEqual(summary, AcceptedLineFingerprintSummary(
            acceptedAddedLines: 1,
            acceptedDeletedLines: 1,
            lineFingerprints: [
                AcceptedLineFingerprint(
                    pathHash: AcceptedLines.fingerprintHash(domain: "path", value: "src/lib.rs"),
                    lineHash: AcceptedLines.fingerprintHash(domain: "line", value: "++ new value")
                )
            ]
        ))
    }

    func testAcceptedLineFingerprintEventRequestUsesRustWireShape() throws {
        let fingerprints = [
            AcceptedLineFingerprint(pathHash: "path1", lineHash: "line1"),
            AcceptedLineFingerprint(pathHash: "path2", lineHash: "line2")
        ]
        let requests = AcceptedLines.acceptedLineFingerprintEventRequests(input: AcceptedLineFingerprintEventInput(
            eventType: "turn_completed",
            turnID: "turn-1",
            threadID: "thread-1",
            productSurface: "cli",
            modelSlug: "gpt-5.4",
            completedAt: 123,
            repoHash: "repo",
            acceptedAddedLines: 2,
            acceptedDeletedLines: 1,
            lineFingerprints: fingerprints
        ))

        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requests[0].shouldSendInIsolatedRequest)
        try XCTAssertJSONObjectEqual(requests[0], [
            "event_type": "codex_accepted_line_fingerprints",
            "event_params": [
                "event_type": "turn_completed",
                "turn_id": "turn-1",
                "thread_id": "thread-1",
                "product_surface": "cli",
                "model_slug": "gpt-5.4",
                "completed_at": 123,
                "repo_hash": "repo",
                "accepted_added_lines": 2,
                "accepted_deleted_lines": 1,
                "line_fingerprints": [
                    [
                        "path_hash": "path1",
                        "line_hash": "line1"
                    ],
                    [
                        "path_hash": "path2",
                        "line_hash": "line2"
                    ]
                ]
            ]
        ])
    }

    func testReducerEmitsAcceptedLineFingerprintsOnceFromLatestTurnDiffOnCompletion() {
        var reducer = AcceptedLineFingerprintReducer(repoHashResolver: { url in
            "repo:\(url.lastPathComponent)"
        })
        let cwd = URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        reducer.ingestResolvedTurn(
            turnID: "turn-2",
            threadID: "thread-2",
            modelSlug: "gpt-5.4",
            cwd: cwd
        )

        for line in ["let old_value = 1;", "let latest_value = 2;"] {
            let diff = """
            diff --git a/src/lib.rs b/src/lib.rs
            index 1111111..2222222
            --- a/src/lib.rs
            +++ b/src/lib.rs
            @@ -0,0 +1 @@
            +\(line)
            """
            reducer.ingestTurnDiff(threadID: "thread-2", turnID: "turn-2", unifiedDiff: diff)
        }

        let events = reducer.completeTurn(turnID: "turn-2", completedAt: 456)

        XCTAssertEqual(events.count, 1)
        let params = events[0].eventParams
        XCTAssertEqual(params.eventType, "codex.accepted_line_fingerprints")
        XCTAssertEqual(params.turnID, "turn-2")
        XCTAssertEqual(params.threadID, "thread-2")
        XCTAssertEqual(params.productSurface, "codex")
        XCTAssertEqual(params.modelSlug, "gpt-5.4")
        XCTAssertEqual(params.completedAt, 456)
        XCTAssertEqual(params.repoHash, "repo:project")
        XCTAssertEqual(params.acceptedAddedLines, 1)
        XCTAssertEqual(params.acceptedDeletedLines, 0)
        XCTAssertEqual(params.lineFingerprints.count, 1)
        XCTAssertEqual(
            params.lineFingerprints[0].lineHash,
            AcceptedLines.fingerprintHash(domain: "line", value: "let latest_value = 2;")
        )
        XCTAssertTrue(events[0].shouldSendInIsolatedRequest)

        XCTAssertTrue(reducer.completeTurn(turnID: "turn-2", completedAt: 457).isEmpty)
    }

    func testAnalyticsClientUploadsAcceptedLineEventsOnCompletion() async {
        let uploader = RecordingAcceptedLineAnalyticsUploader()
        let client = AcceptedLineAnalyticsClient(
            uploader: uploader,
            nowUnixSeconds: { 123 },
            repoHashResolver: { _ in "repo-hash" }
        )
        await client.trackResolvedTurn(
            turnID: "turn-1",
            threadID: "thread-1",
            modelSlug: "gpt-test",
            cwd: URL(fileURLWithPath: "/repo", isDirectory: true)
        )
        await client.trackTurnDiff(
            threadID: "thread-1",
            turnID: "turn-1",
            unifiedDiff: """
            diff --git a/src/lib.rs b/src/lib.rs
            --- a/src/lib.rs
            +++ b/src/lib.rs
            @@ -1 +1 @@
            -let old_value = 1;
            +let new_value = 2;
            """
        )

        await client.trackTurnCompleted(turnID: "turn-1")

        let requests = await uploader.requests
        XCTAssertEqual(requests.count, 1)
        let event = requests[0].events[0]
        XCTAssertEqual(event.eventParams.turnID, "turn-1")
        XCTAssertEqual(event.eventParams.threadID, "thread-1")
        XCTAssertEqual(event.eventParams.modelSlug, "gpt-test")
        XCTAssertEqual(event.eventParams.completedAt, 123)
        XCTAssertEqual(event.eventParams.repoHash, "repo-hash")
        XCTAssertEqual(event.eventParams.acceptedAddedLines, 1)
        XCTAssertEqual(event.eventParams.acceptedDeletedLines, 1)
    }

    func testAnalyticsUploadBatchesIsolateAcceptedLineFingerprintEvents() {
        let requests = AcceptedLines.acceptedLineFingerprintEventRequests(input: AcceptedLineFingerprintEventInput(
            eventType: "codex.accepted_line_fingerprints",
            turnID: "turn-1",
            threadID: "thread-1",
            completedAt: 123,
            acceptedAddedLines: 2,
            acceptedDeletedLines: 0,
            lineFingerprints: [
                AcceptedLineFingerprint(pathHash: String(repeating: "a", count: 40), lineHash: String(repeating: "b", count: 40)),
                AcceptedLineFingerprint(pathHash: String(repeating: "c", count: 40), lineHash: String(repeating: "d", count: 40))
            ]
        ))

        let batches = AcceptedLines.acceptedLineAnalyticsUploadBatches(requests)

        XCTAssertEqual(batches.count, requests.count)
        XCTAssertTrue(batches.allSatisfy { $0.count == 1 })
    }

    func testURLSessionAnalyticsUploaderPostsChatGPTTokenEvents() async throws {
        let temp = try AcceptedLinesTemporaryDirectory()
        let accessToken = Self.fakeJWT(authClaims: [
            "chatgpt_account_id": "acct-123",
            "chatgpt_plan_type": "pro"
        ])
        try CodexAuthStorage.saveChatGPTAuthTokens(
            codexHome: temp.url,
            accessToken: accessToken,
            chatGPTAccountID: "acct-123",
            chatGPTPlanType: "pro",
            now: Date()
        )
        let transport = RecordingAcceptedLineAPITransport()
        let uploader = URLSessionAcceptedLineAnalyticsUploader(
            codexHome: temp.url,
            baseURL: "https://chatgpt.example/backend-api/",
            transport: transport
        )
        let request = AcceptedLineAnalyticsUploadRequest(events: Self.sampleAcceptedLineEvents())

        try await uploader.upload(request)

        let requests = await transport.executeRequests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].method, .post)
        XCTAssertEqual(
            requests[0].url,
            "https://chatgpt.example/backend-api/codex/analytics-events/events"
        )
        XCTAssertEqual(requests[0].headers["authorization"], "Bearer \(accessToken)")
        XCTAssertEqual(requests[0].headers["ChatGPT-Account-ID"], "acct-123")
        XCTAssertEqual(requests[0].headers["Content-Type"], "application/json")
        XCTAssertEqual(requests[0].timeoutMilliseconds, URLSessionAcceptedLineAnalyticsUploader.timeoutMilliseconds)
        XCTAssertEqual(requests[0].body, try AcceptedLines.jsonValue(request))
    }

    func testURLSessionAnalyticsUploaderSkipsAPIKeyAuthLikeRust() async throws {
        let temp = try AcceptedLinesTemporaryDirectory()
        try CodexAuthStorage.loginWithAPIKey(codexHome: temp.url, apiKey: "sk-api")
        let transport = RecordingAcceptedLineAPITransport()
        let uploader = URLSessionAcceptedLineAnalyticsUploader(
            codexHome: temp.url,
            baseURL: "https://chatgpt.example/backend-api/",
            transport: transport
        )

        try await uploader.upload(AcceptedLineAnalyticsUploadRequest(events: Self.sampleAcceptedLineEvents()))

        let requests = await transport.executeRequests
        XCTAssertTrue(requests.isEmpty)
    }

    func testReducerChunksLargeAcceptedLineFingerprintEventsWithoutRepeatingCounts() throws {
        var reducer = AcceptedLineFingerprintReducer(repoHashResolver: { _ in nil })
        reducer.ingestResolvedTurn(
            turnID: "turn-3",
            threadID: "thread-3",
            modelSlug: "gpt-5.4",
            cwd: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        )
        var diff = """
        diff --git a/src/lib.rs b/src/lib.rs
        index 1111111..2222222
        --- a/src/lib.rs
        +++ b/src/lib.rs
        @@ -0,0 +1,20000 @@

        """
        for index in 0..<20_000 {
            diff += "+let value_\(index) = \(index);\n"
        }
        reducer.ingestTurnDiff(threadID: "thread-3", turnID: "turn-3", unifiedDiff: diff)

        let events = reducer.completeTurn(turnID: "turn-3", completedAt: 789)

        XCTAssertGreaterThan(events.count, 1)
        var totalFingerprints = 0
        for (index, event) in events.enumerated() {
            XCTAssertTrue(event.shouldSendInIsolatedRequest)
            XCTAssertEqual(event.eventParams.turnID, "turn-3")
            XCTAssertEqual(event.eventParams.threadID, "thread-3")
            totalFingerprints += event.eventParams.lineFingerprints.count
            if index == 0 {
                XCTAssertEqual(event.eventParams.acceptedAddedLines, 20_000)
                XCTAssertEqual(event.eventParams.acceptedDeletedLines, 0)
            } else {
                XCTAssertEqual(event.eventParams.acceptedAddedLines, 0)
                XCTAssertEqual(event.eventParams.acceptedDeletedLines, 0)
            }
            XCTAssertLessThan(try JSONEncoder().encode(event).count, 2_100_000)
        }
        XCTAssertEqual(totalFingerprints, 20_000)
    }

    private static func sampleAcceptedLineEvents() -> [AcceptedLineFingerprintsEventRequest] {
        AcceptedLines.acceptedLineFingerprintEventRequests(input: AcceptedLineFingerprintEventInput(
            eventType: "codex.accepted_line_fingerprints",
            turnID: "turn-1",
            threadID: "thread-1",
            completedAt: 123,
            acceptedAddedLines: 1,
            acceptedDeletedLines: 0,
            lineFingerprints: [
                AcceptedLineFingerprint(pathHash: String(repeating: "a", count: 40), lineHash: String(repeating: "b", count: 40))
            ]
        ))
    }

    private static func fakeJWT(authClaims: [String: Any]) -> String {
        func encode(_ object: Any) -> String {
            let data = try! JSONSerialization.data(withJSONObject: object)
            return data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return [
            encode(["alg": "none"]),
            encode(["https://api.openai.com/auth": authClaims]),
            "sig"
        ].joined(separator: ".")
    }
}

private actor RecordingAcceptedLineAnalyticsUploader: AcceptedLineAnalyticsUploading {
    private(set) var requests: [AcceptedLineAnalyticsUploadRequest] = []

    func upload(_ request: AcceptedLineAnalyticsUploadRequest) async throws {
        requests.append(request)
    }
}

private actor RecordingAcceptedLineAPITransport: APITransport {
    private(set) var executeRequests: [APIRequest] = []

    func execute(_ request: APIRequest) async -> Result<APIResponse, TransportError> {
        executeRequests.append(request)
        return .success(APIResponse(statusCode: 204))
    }

    func stream(_: APIRequest) async -> Result<APIStreamResponse, TransportError> {
        .failure(.network("stream not supported"))
    }
}

private final class AcceptedLinesTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
