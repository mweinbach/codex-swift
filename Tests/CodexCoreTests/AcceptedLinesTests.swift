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
}
