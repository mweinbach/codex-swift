@testable import CodexCore
import XCTest

final class FeedbackTests: XCTestCase {
    func testRingBufferDropsFrontWhenFullLikeRust() throws {
        let feedback = CodexFeedback(capacity: 8)
        let writer = feedback.makeWriter()

        writer.write(Array("abcdefgh".utf8))
        writer.write(Array("ij".utf8))

        let snapshot = feedback.snapshot(sessionID: nil)
        XCTAssertEqual(String(decoding: snapshot.bytes, as: UTF8.self), "cdefghij")
        XCTAssertTrue(snapshot.threadID.hasPrefix("no-active-thread-"))
    }

    func testRingBufferKeepsTrailingBytesWhenChunkExceedsCapacity() {
        var ring = FeedbackRingBuffer(capacity: 5)

        ring.push(Array("abcdefgh".utf8))

        XCTAssertEqual(String(decoding: ring.snapshotBytes(), as: UTF8.self), "defgh")
    }

    func testRingBufferIgnoresEmptyWritesAndZeroCapacity() {
        var ring = FeedbackRingBuffer(capacity: 0)

        ring.push(Array("abc".utf8))
        ring.push([])

        XCTAssertEqual(ring.count, 0)
        XCTAssertEqual(ring.snapshotBytes(), [])
    }

    func testSnapshotUsesProvidedConversationID() throws {
        let id = try ConversationId(string: "018f7a2d-4c5b-7abc-8def-0123456789ab")
        let feedback = CodexFeedback(capacity: 32)

        feedback.makeWriter().write(Data("hello".utf8))

        XCTAssertEqual(feedback.snapshot(sessionID: id), CodexLogSnapshot(
            bytes: Array("hello".utf8),
            threadID: "018f7a2d-4c5b-7abc-8def-0123456789ab"
        ))
    }

    func testSnapshotSavesToTempFileWithRustFilenamePrefix() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-swift-feedback-tests-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        let snapshot = CodexLogSnapshot(bytes: Array("logs".utf8), threadID: "thread-1")

        let path = try snapshot.saveToTempFile(temporaryDirectory: root)

        XCTAssertEqual(path.lastPathComponent, "codex-feedback-thread-1.log")
        XCTAssertEqual(try String(contentsOf: path, encoding: .utf8), "logs")
    }

    func testUploadRequestBuildsSentryEnvelopeWithTagsAndAttachments() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-swift-feedback-upload-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let rolloutPath = root.appendingPathComponent("rollout-test.jsonl")
        try Data("rollout".utf8).write(to: rolloutPath)

        let snapshot = CodexLogSnapshot(bytes: Array("logs".utf8), threadID: "thread-1")
        let request = try snapshot.makeUploadRequest(
            classification: "bug",
            reason: "it broke",
            includeLogs: true,
            rolloutPath: rolloutPath,
            sessionSource: .cli,
            accountID: "actual-account",
            cliVersion: "1.2.3",
            eventID: "0123456789abcdef0123456789abcdef"
        )

        XCTAssertEqual(
            request.endpoint.absoluteString,
            "https://o33249.ingest.us.sentry.io/api/4510195390611458/envelope/"
        )
        XCTAssertEqual(
            request.authHeader,
            "Sentry sentry_version=7, sentry_key=ae32ed50620d7a7792c1ce5df38b3e3e, sentry_client=codex-swift/1.2.3"
        )
        XCTAssertEqual(request.timeout, 10)

        let envelope = String(decoding: request.envelope, as: UTF8.self)
        XCTAssertTrue(envelope.contains(#""dsn":"https:\/\/ae32ed50620d7a7792c1ce5df38b3e3e@o33249.ingest.us.sentry.io\/4510195390611458""#))
        XCTAssertTrue(envelope.contains(#""type":"event""#))
        XCTAssertTrue(envelope.contains(#""event_id":"0123456789abcdef0123456789abcdef""#))
        XCTAssertTrue(envelope.contains(#""level":"error""#))
        XCTAssertTrue(envelope.contains(#""message":"[Bug]: Codex session thread-1""#))
        XCTAssertTrue(envelope.contains(#""classification":"bug""#))
        XCTAssertTrue(envelope.contains(#""cli_version":"1.2.3""#))
        XCTAssertTrue(envelope.contains(#""session_source":"cli""#))
        XCTAssertTrue(envelope.contains(#""account_id":"actual-account""#))
        XCTAssertTrue(envelope.contains(#""reason":"it broke""#))
        XCTAssertTrue(envelope.contains(#""exception":{"values":[{"type":"[Bug]: Codex session thread-1","value":"it broke"}]}"#))
        XCTAssertTrue(envelope.contains(#""filename":"codex-logs.log""#))
        XCTAssertTrue(envelope.contains(#""length":4"#))
        XCTAssertTrue(envelope.contains("\nlogs\n"))
        XCTAssertTrue(envelope.contains(#""filename":"rollout-test.jsonl""#))
        XCTAssertTrue(envelope.contains(#""length":7"#))
        XCTAssertTrue(envelope.contains("\nrollout\n"))
    }

    func testUploadRequestAddsInMemoryAttachmentsLikeRustFeedback() throws {
        let snapshot = CodexLogSnapshot(bytes: Array("logs".utf8), threadID: "thread-attachment")
        let request = try snapshot.makeUploadRequest(
            classification: "bug",
            includeLogs: true,
            extraAttachments: [
                FeedbackAttachment(
                    filename: "codex-doctor-report.json",
                    contentType: "application/json",
                    data: Data(#"{"overallStatus":"ok"}"#.utf8)
                )
            ],
            eventID: "0123456789abcdef0123456789abcdef"
        )

        let envelope = String(decoding: request.envelope, as: UTF8.self)
        XCTAssertTrue(envelope.contains(#""filename":"codex-doctor-report.json""#))
        XCTAssertTrue(envelope.contains(#""content_type":"application\/json""#))
        XCTAssertTrue(envelope.contains(#"{"overallStatus":"ok"}"#))
    }

    func testUploadRequestOmitsLogsAndUsesInfoLevelForOtherClassifications() throws {
        let snapshot = CodexLogSnapshot(bytes: Array("logs".utf8), threadID: "thread-2")
        let request = try snapshot.makeUploadRequest(
            classification: "good_result",
            reason: nil,
            includeLogs: false,
            sessionSource: .vscode,
            cliVersion: "1.2.3",
            eventID: "fedcba9876543210fedcba9876543210"
        )

        let envelope = String(decoding: request.envelope, as: UTF8.self)
        XCTAssertTrue(envelope.contains(#""level":"info""#))
        XCTAssertTrue(envelope.contains(#""message":"[Good result]: Codex session thread-2""#))
        XCTAssertTrue(envelope.contains(#""session_source":"vscode""#))
        XCTAssertFalse(envelope.contains(#""filename":"codex-logs.log""#))
        XCTAssertFalse(envelope.contains(#""exception""#))
    }

    func testUploadFeedbackUsesInjectedTransport() async throws {
        let transport = RecordingFeedbackUploadTransport()
        let snapshot = CodexLogSnapshot(bytes: Array("logs".utf8), threadID: "thread-3")

        try await snapshot.uploadFeedback(
            classification: "bad_result",
            reason: "wrong answer",
            includeLogs: true,
            sessionSource: .exec,
            accountID: "transport-account",
            cliVersion: "9.9.9",
            transport: transport
        )

        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].endpoint.absoluteString, "https://o33249.ingest.us.sentry.io/api/4510195390611458/envelope/")
        XCTAssertTrue(String(decoding: requests[0].envelope, as: UTF8.self).contains(#""classification":"bad_result""#))
    }
}

private actor RecordingFeedbackUploadTransport: FeedbackUploadTransport {
    private(set) var requests: [FeedbackUploadRequest] = []

    func upload(_ request: FeedbackUploadRequest) async throws {
        requests.append(request)
    }
}
