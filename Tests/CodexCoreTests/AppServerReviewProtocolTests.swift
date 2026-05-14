import CodexCore
import XCTest

final class AppServerReviewProtocolTests: XCTestCase {
    func testReviewStartParamsEncodeRustWireShapeWithNullDefaultDelivery() throws {
        try XCTAssertJSONObjectEqual(
            ReviewStartParams(
                threadID: "00000000-0000-0000-0000-000000000001",
                target: .uncommittedChanges
            ),
            [
                "threadId": "00000000-0000-0000-0000-000000000001",
                "target": [
                    "type": "uncommittedChanges"
                ],
                "delivery": NSNull()
            ]
        )

        try XCTAssertJSONObjectEqual(
            ReviewStartParams(
                threadID: "00000000-0000-0000-0000-000000000001",
                target: .baseBranch(branch: "main"),
                delivery: .detached
            ),
            [
                "threadId": "00000000-0000-0000-0000-000000000001",
                "target": [
                    "type": "baseBranch",
                    "branch": "main"
                ],
                "delivery": "detached"
            ]
        )
    }

    func testReviewStartParamsPreserveTaggedTargetVariants() throws {
        try XCTAssertJSONObjectEqual(
            ReviewStartParams(
                threadID: "thread-1",
                target: .commit(sha: "abcdef123", title: nil),
                delivery: .inline
            ),
            [
                "threadId": "thread-1",
                "target": [
                    "type": "commit",
                    "sha": "abcdef123",
                    "title": NSNull()
                ],
                "delivery": "inline"
            ]
        )

        try XCTAssertJSONObjectEqual(
            ReviewStartParams(
                threadID: "thread-1",
                target: .custom(instructions: "inspect parser"),
                delivery: .inline
            ),
            [
                "threadId": "thread-1",
                "target": [
                    "type": "custom",
                    "instructions": "inspect parser"
                ],
                "delivery": "inline"
            ]
        )
    }

    func testReviewStartPayloadsDecodeRustNullDelivery() throws {
        let decoded = try JSONDecoder().decode(
            ReviewStartParams.self,
            from: Data(
                #"""
                {
                  "threadId": "thread-1",
                  "target": {
                    "type": "commit",
                    "sha": "abcdef123",
                    "title": null
                  },
                  "delivery": null
                }
                """#.utf8
            )
        )

        XCTAssertEqual(decoded.threadID, "thread-1")
        XCTAssertEqual(decoded.target, .commit(sha: "abcdef123", title: nil))
        XCTAssertNil(decoded.delivery)
    }

    func testReviewStartResponseEncodesRustWireShape() throws {
        let turn = AppServerTurn(
            id: "turn-1",
            items: [
                .agentMessage(id: "item-1", text: "Review started")
            ],
            itemsView: .summary,
            status: .inProgress,
            startedAt: 1_700_000_000_000
        )

        try XCTAssertJSONObjectEqual(
            ReviewStartResponse(turn: turn, reviewThreadID: "review-thread-1"),
            [
                "turn": [
                    "id": "turn-1",
                    "items": [
                        [
                            "type": "agentMessage",
                            "id": "item-1",
                            "text": "Review started",
                            "phase": NSNull(),
                            "memoryCitation": NSNull()
                        ]
                    ],
                    "itemsView": "summary",
                    "status": "inProgress",
                    "error": NSNull(),
                    "startedAt": 1_700_000_000_000,
                    "completedAt": NSNull(),
                    "durationMs": NSNull()
                ],
                "reviewThreadId": "review-thread-1"
            ]
        )
    }
}
