import CodexCore
import XCTest

final class AppServerNotificationProtocolTests: XCTestCase {
    func testWarningAndDeprecationNotificationsEncodeRustNullOptionals() throws {
        try XCTAssertJSONObjectEqual(
            DeprecationNoticeNotification(summary: "old flag"),
            [
                "summary": "old flag",
                "details": NSNull()
            ]
        )
        try XCTAssertJSONObjectEqual(
            DeprecationNoticeNotification(summary: "old flag", details: "use --new"),
            [
                "summary": "old flag",
                "details": "use --new"
            ]
        )

        try XCTAssertJSONObjectEqual(
            WarningNotification(message: "careful"),
            [
                "threadId": NSNull(),
                "message": "careful"
            ]
        )
        try XCTAssertJSONObjectEqual(
            WarningNotification(threadID: "thread-1", message: "careful"),
            [
                "threadId": "thread-1",
                "message": "careful"
            ]
        )
        try XCTAssertJSONObjectEqual(
            GuardianWarningNotification(threadID: "thread-1", message: "approval needed"),
            [
                "threadId": "thread-1",
                "message": "approval needed"
            ]
        )
    }

    func testErrorAndResolvedNotificationsEncodeRustWireShape() throws {
        try XCTAssertJSONObjectEqual(
            ErrorNotification(
                error: AppServerTurnError(message: "model failed"),
                willRetry: true,
                threadID: "thread-1",
                turnID: "turn-1"
            ),
            [
                "error": [
                    "message": "model failed",
                    "codexErrorInfo": NSNull(),
                    "additionalDetails": NSNull()
                ],
                "willRetry": true,
                "threadId": "thread-1",
                "turnId": "turn-1"
            ]
        )

        try XCTAssertJSONObjectEqual(
            ServerRequestResolvedNotification(threadID: "thread-1", requestID: .string("req-1")),
            [
                "threadId": "thread-1",
                "requestId": "req-1"
            ]
        )
        try XCTAssertJSONObjectEqual(
            ServerRequestResolvedNotification(threadID: "thread-1", requestID: .integer(7)),
            [
                "threadId": "thread-1",
                "requestId": 7
            ]
        )
    }

    func testRemoteControlStatusChangedNotificationUsesRustCamelCaseShape() throws {
        try XCTAssertJSONObjectEqual(
            RemoteControlStatusChangedNotification(
                status: .connected,
                installationID: "install-1",
                environmentID: nil
            ),
            [
                "status": "connected",
                "installationId": "install-1",
                "environmentId": NSNull()
            ]
        )

        try XCTAssertJSONObjectEqual(
            RemoteControlStatusChangedNotification(
                snapshot: RemoteControlStatusSnapshot(
                    status: .errored,
                    installationID: "install-1",
                    environmentID: "env-1"
                )
            ),
            [
                "status": "errored",
                "installationId": "install-1",
                "environmentId": "env-1"
            ]
        )
    }

    func testTurnErrorEncodesRustExplicitNullOptionals() throws {
        try XCTAssertJSONObjectEqual(
            AppServerTurnError(message: "failed"),
            [
                "message": "failed",
                "codexErrorInfo": NSNull(),
                "additionalDetails": NSNull()
            ]
        )

        let decoded = try JSONDecoder().decode(
            AppServerTurnError.self,
            from: Data(#"{"message":"failed"}"#.utf8)
        )
        XCTAssertEqual(decoded.message, "failed")
        XCTAssertNil(decoded.codexErrorInfo)
        XCTAssertNil(decoded.additionalDetails)
    }
}
