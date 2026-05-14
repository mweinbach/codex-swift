import CodexCore
import XCTest

final class AppServerFeedbackProtocolTests: XCTestCase {
    func testFeedbackUploadParamsEncodeExplicitNullOptionalsLikeRustProtocol() throws {
        try XCTAssertJSONObjectEqual(
            FeedbackUploadParams(classification: "bug", includeLogs: false),
            [
                "classification": "bug",
                "reason": NSNull(),
                "threadId": NSNull(),
                "includeLogs": false,
                "extraLogFiles": NSNull(),
                "tags": NSNull()
            ]
        )

        try XCTAssertJSONObjectEqual(
            FeedbackUploadParams(
                classification: "bad_result",
                reason: "wrong answer",
                threadID: "00000000-0000-0000-0000-000000000001",
                includeLogs: true,
                extraLogFiles: ["logs/extra.log"],
                tags: ["surface": "app-server"]
            ),
            [
                "classification": "bad_result",
                "reason": "wrong answer",
                "threadId": "00000000-0000-0000-0000-000000000001",
                "includeLogs": true,
                "extraLogFiles": ["logs/extra.log"],
                "tags": ["surface": "app-server"]
            ]
        )
    }

    func testFeedbackUploadResponseShapeMatchesRustProtocol() throws {
        try XCTAssertJSONObjectEqual(
            FeedbackUploadResponse(threadID: "00000000-0000-0000-0000-000000000001"),
            [
                "threadId": "00000000-0000-0000-0000-000000000001"
            ]
        )
    }

    func testFeedbackUploadParamsDecodeNullOptionalsLikeRustProtocol() throws {
        let decoded = try JSONDecoder().decode(
            FeedbackUploadParams.self,
            from: Data(
                #"""
                {
                  "classification": "bug",
                  "reason": null,
                  "threadId": null,
                  "includeLogs": false,
                  "extraLogFiles": null,
                  "tags": null
                }
                """#.utf8
            )
        )

        XCTAssertEqual(decoded.classification, "bug")
        XCTAssertNil(decoded.reason)
        XCTAssertNil(decoded.threadID)
        XCTAssertFalse(decoded.includeLogs)
        XCTAssertNil(decoded.extraLogFiles)
        XCTAssertNil(decoded.tags)
    }
}
