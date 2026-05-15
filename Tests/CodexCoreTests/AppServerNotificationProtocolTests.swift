import CodexCore
import XCTest

final class AppServerNotificationProtocolTests: XCTestCase {
    private let repoPath = try! AbsolutePath(absolutePath: "/repo")
    private let filePath = try! AbsolutePath(absolutePath: "/repo/Sources/App.swift")

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

    func testRemoteControlStatusChangedNotificationEncodesRustV2WireShape() throws {
        try XCTAssertJSONObjectEqual(
            RemoteControlStatusChangedNotification(
                status: .connected,
                installationID: "install-1",
                environmentID: "env-1"
            ),
            [
                "status": "connected",
                "installationId": "install-1",
                "environmentId": "env-1"
            ]
        )

        try XCTAssertJSONObjectEqual(
            RemoteControlStatusChangedNotification(
                status: .disabled,
                installationID: "install-2",
                environmentID: nil
            ),
            [
                "status": "disabled",
                "installationId": "install-2",
                "environmentId": NSNull()
            ]
        )

        let decoded = try JSONDecoder().decode(
            RemoteControlStatusChangedNotification.self,
            from: Data(
                #"""
                {
                  "status": "errored",
                  "installationId": "install-3",
                  "environmentId": null
                }
                """#.utf8
            )
        )

        XCTAssertEqual(
            decoded,
            RemoteControlStatusChangedNotification(
                status: .errored,
                installationID: "install-3",
                environmentID: nil
            )
        )
    }

    func testErrorAndResolvedNotificationsEncodeRustWireShape() throws {
        try XCTAssertJSONObjectEqual(
            ErrorNotification(
                error: AppServerTurnError(
                    message: "model failed",
                    codexErrorInfo: .usageLimitExceeded,
                    additionalDetails: "retry later"
                ),
                willRetry: true,
                threadID: "thread-1",
                turnID: "turn-1"
            ),
            [
                "error": [
                    "message": "model failed",
                    "codexErrorInfo": "usageLimitExceeded",
                    "additionalDetails": "retry later"
                ],
                "willRetry": true,
                "threadId": "thread-1",
                "turnId": "turn-1"
            ]
        )

        try XCTAssertJSONObjectEqual(
            ErrorNotification(
                error: AppServerTurnError(
                    message: "active turn cannot be steered",
                    codexErrorInfo: .activeTurnNotSteerable(turnKind: .compact)
                ),
                willRetry: false,
                threadID: "thread-1",
                turnID: "turn-1"
            ),
            [
                "error": [
                    "message": "active turn cannot be steered",
                    "codexErrorInfo": [
                        "activeTurnNotSteerable": [
                            "turnKind": "compact"
                        ]
                    ],
                    "additionalDetails": NSNull()
                ],
                "willRetry": false,
                "threadId": "thread-1",
                "turnId": "turn-1"
            ]
        )

        try XCTAssertJSONObjectEqual(
            ErrorNotification(
                error: AppServerTurnError(
                    message: "stream disconnected",
                    codexErrorInfo: .responseStreamDisconnected(httpStatusCode: nil)
                ),
                willRetry: false,
                threadID: "thread-1",
                turnID: "turn-1"
            ),
            [
                "error": [
                    "message": "stream disconnected",
                    "codexErrorInfo": [
                        "responseStreamDisconnected": [
                            "httpStatusCode": NSNull()
                        ]
                    ],
                    "additionalDetails": NSNull()
                ],
                "willRetry": false,
                "threadId": "thread-1",
                "turnId": "turn-1"
            ]
        )

        let decoded = try JSONDecoder().decode(
            AppServerTurnError.self,
            from: Data(
                #"""
                {
                  "message": "stream disconnected",
                  "codexErrorInfo": {
                    "responseStreamDisconnected": {
                      "httpStatusCode": 502
                    }
                  },
                  "additionalDetails": null
                }
                """#.utf8
            )
        )
        XCTAssertEqual(
            decoded,
            AppServerTurnError(
                message: "stream disconnected",
                codexErrorInfo: .responseStreamDisconnected(httpStatusCode: 502)
            )
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

    func testGuardianApprovalReviewNotificationsEncodeRustV2WireShape() throws {
        let started = ItemGuardianApprovalReviewStartedNotification(
            threadID: "thread-1",
            turnID: "turn-1",
            startedAtMilliseconds: 1_000,
            reviewID: "review-1",
            targetItemID: nil,
            review: GuardianApprovalReview(status: .inProgress),
            action: .command(source: .unifiedExec, command: "git status", cwd: repoPath)
        )

        try XCTAssertJSONObjectEqual(started, [
            "threadId": "thread-1",
            "turnId": "turn-1",
            "startedAtMs": 1_000,
            "reviewId": "review-1",
            "targetItemId": NSNull(),
            "review": [
                "status": "inProgress",
                "riskLevel": NSNull(),
                "userAuthorization": NSNull(),
                "rationale": NSNull()
            ],
            "action": [
                "type": "command",
                "source": "unifiedExec",
                "command": "git status",
                "cwd": "/repo"
            ]
        ])

        let decodedStarted = try JSONDecoder().decode(
            ItemGuardianApprovalReviewStartedNotification.self,
            from: Data("""
            {
              "threadId": "thread-1",
              "turnId": "turn-1",
              "startedAtMs": 1000,
              "reviewId": "review-1",
              "targetItemId": null,
              "review": {
                "status": "inProgress",
                "riskLevel": null,
                "userAuthorization": null,
                "rationale": null
              },
              "action": {
                "type": "command",
                "source": "unifiedExec",
                "command": "git status",
                "cwd": "/repo"
              }
            }
            """.utf8)
        )
        XCTAssertEqual(decodedStarted, started)

        let abortedReview = try JSONDecoder().decode(
            GuardianApprovalReview.self,
            from: Data("""
            {
              "status": "aborted",
              "riskLevel": null,
              "userAuthorization": null,
              "rationale": null
            }
            """.utf8)
        )
        XCTAssertEqual(abortedReview, GuardianApprovalReview(status: .aborted))

        let completed = ItemGuardianApprovalReviewCompletedNotification(
            threadID: "thread-1",
            turnID: "turn-1",
            startedAtMilliseconds: 1_000,
            completedAtMilliseconds: 1_042,
            reviewID: "review-2",
            targetItemID: "item-2",
            decisionSource: .agent,
            review: GuardianApprovalReview(
                status: .denied,
                riskLevel: .high,
                userAuthorization: .low,
                rationale: "too risky"
            ),
            action: .mcpToolCall(
                server: "github",
                toolName: "delete_repo",
                connectorID: nil,
                connectorName: "GitHub",
                toolTitle: nil
            )
        )

        try XCTAssertJSONObjectEqual(completed, [
            "threadId": "thread-1",
            "turnId": "turn-1",
            "startedAtMs": 1_000,
            "completedAtMs": 1_042,
            "reviewId": "review-2",
            "targetItemId": "item-2",
            "decisionSource": "agent",
            "review": [
                "status": "denied",
                "riskLevel": "high",
                "userAuthorization": "low",
                "rationale": "too risky"
            ],
            "action": [
                "type": "mcpToolCall",
                "server": "github",
                "toolName": "delete_repo",
                "connectorId": NSNull(),
                "connectorName": "GitHub",
                "toolTitle": NSNull()
            ]
        ])

        let decodedCompleted = try JSONDecoder().decode(
            ItemGuardianApprovalReviewCompletedNotification.self,
            from: Data("""
            {
              "threadId": "thread-1",
              "turnId": "turn-1",
              "startedAtMs": 1000,
              "completedAtMs": 1042,
              "reviewId": "review-2",
              "targetItemId": "item-2",
              "decisionSource": "agent",
              "review": {
                "status": "denied",
                "riskLevel": "high",
                "userAuthorization": "low",
                "rationale": "too risky"
              },
              "action": {
                "type": "mcpToolCall",
                "server": "github",
                "toolName": "delete_repo",
                "connectorId": null,
                "connectorName": "GitHub",
                "toolTitle": null
              }
            }
            """.utf8)
        )
        XCTAssertEqual(decodedCompleted, completed)

        try XCTAssertJSONObjectEqual(
            GuardianApprovalReviewAction.networkAccess(
                target: "https://example.com",
                host: "example.com",
                protocol: .socks5Tcp,
                port: 443
            ),
            [
                "type": "networkAccess",
                "target": "https://example.com",
                "host": "example.com",
                "protocol": "socks5Tcp",
                "port": 443
            ]
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                GuardianApprovalReviewAction.self,
                from: Data(#"{"type":"networkAccess","target":"https://example.com","host":"example.com","protocol":"socks5Tcp","port":443}"#.utf8)
            ),
            .networkAccess(target: "https://example.com", host: "example.com", protocol: .socks5Tcp, port: 443)
        )

        try XCTAssertJSONObjectEqual(
            GuardianApprovalReviewAction.applyPatch(cwd: repoPath, files: [filePath]),
            [
                "type": "applyPatch",
                "cwd": "/repo",
                "files": ["/repo/Sources/App.swift"]
            ]
        )
    }

    func testGuardianApprovalReviewPathActionsRejectRelativePathsLikeRustAbsolutePathBuf() throws {
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                GuardianApprovalReviewAction.self,
                from: Data(#"{"type":"command","source":"unifiedExec","command":"git status","cwd":"repo"}"#.utf8)
            )
        )

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                GuardianApprovalReviewAction.self,
                from: Data(#"{"type":"applyPatch","cwd":"/repo","files":["Sources/App.swift"]}"#.utf8)
            )
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
