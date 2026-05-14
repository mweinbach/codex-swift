import CodexCore
import XCTest

final class AppServerThreadProtocolTests: XCTestCase {
    func testTurnDefaultsLegacyMissingItemsViewToFullLikeRustProtocol() throws {
        let json = """
        {
          "id": "turn_123",
          "items": [],
          "status": "completed",
          "error": null,
          "startedAt": null,
          "completedAt": null,
          "durationMs": null
        }
        """

        let turn = try JSONDecoder().decode(AppServerTurn.self, from: Data(json.utf8))

        XCTAssertEqual(turn.itemsView, .full)
        XCTAssertEqual(turn.id, "turn_123")
        XCTAssertEqual(turn.items, [])
        XCTAssertEqual(turn.status, .completed)
        XCTAssertNil(turn.error)
    }

    func testThreadTurnsListParamsAcceptsItemsViewLikeRustProtocol() throws {
        let json = """
        {
          "threadId": "thr_123",
          "cursor": null,
          "limit": 25,
          "sortDirection": "desc",
          "itemsView": "notLoaded"
        }
        """

        let params = try JSONDecoder().decode(ThreadTurnsListParams.self, from: Data(json.utf8))

        XCTAssertEqual(params.threadID, "thr_123")
        XCTAssertNil(params.cursor)
        XCTAssertEqual(params.limit, 25)
        XCTAssertEqual(params.sortDirection, .desc)
        XCTAssertEqual(params.itemsView, .notLoaded)
    }

    func testThreadLoadedListRoundTripsLikeRustProtocol() throws {
        let params = ThreadLoadedListParams(cursor: "thread-1", limit: 25)

        try XCTAssertJSONObjectEqual(params, [
            "cursor": "thread-1",
            "limit": 25
        ])

        let response = ThreadLoadedListResponse(data: ["thread-2"], nextCursor: nil)

        try XCTAssertJSONObjectEqual(response, [
            "data": ["thread-2"],
            "nextCursor": NSNull()
        ])

        let decoded = try JSONDecoder().decode(
            ThreadLoadedListParams.self,
            from: Data(#"{"cursor":null,"limit":0}"#.utf8)
        )
        XCTAssertNil(decoded.cursor)
        XCTAssertEqual(decoded.limit, 0)
    }

    func testThreadInjectItemsRoundTripsLikeRustProtocol() throws {
        let item: JSONValue = .object([
            "type": .string("message"),
            "role": .string("assistant"),
            "content": .array([
                .object([
                    "type": .string("output_text"),
                    "text": .string("Injected assistant context")
                ])
            ])
        ])
        let params = ThreadInjectItemsParams(threadID: "thr_123", items: [item])

        try XCTAssertJSONObjectEqual(params, [
            "threadId": "thr_123",
            "items": [
                [
                    "type": "message",
                    "role": "assistant",
                    "content": [
                        [
                            "type": "output_text",
                            "text": "Injected assistant context"
                        ]
                    ]
                ]
            ]
        ])

        let decoded = try JSONDecoder().decode(
            ThreadInjectItemsParams.self,
            from: Data(#"{"threadId":"thr_456","items":[{"type":"reasoning","summary":[]}]}"#.utf8)
        )
        XCTAssertEqual(decoded.threadID, "thr_456")
        XCTAssertEqual(decoded.items, [
            .object([
                "type": .string("reasoning"),
                "summary": .array([])
            ])
        ])

        try XCTAssertJSONObjectEqual(ThreadInjectItemsResponse(), [:])
    }

    func testThreadTurnsItemsListRoundTripsLikeRustProtocol() throws {
        let params = ThreadTurnsItemsListParams(
            threadID: "thr_123",
            turnID: "turn_456",
            cursor: "cursor_1",
            limit: 50,
            sortDirection: .asc
        )

        try XCTAssertJSONObjectEqual(params, [
            "threadId": "thr_123",
            "turnId": "turn_456",
            "cursor": "cursor_1",
            "limit": 50,
            "sortDirection": "asc"
        ])

        let response = ThreadTurnsItemsListResponse(
            data: [.contextCompaction(id: "item_1")],
            nextCursor: nil,
            backwardsCursor: "cursor_0"
        )

        try XCTAssertJSONObjectEqual(response, [
            "data": [
                [
                    "type": "contextCompaction",
                    "id": "item_1"
                ]
            ],
            "nextCursor": NSNull(),
            "backwardsCursor": "cursor_0"
        ])
    }

    func testTurnItemsForThreadReturnsMatchingTurnItemsLikeRustExec() {
        let thread = AppServerThread(id: "thread-1", turns: [
            AppServerTurn(
                id: "turn-1",
                items: [.agentMessage(id: "msg-1", text: "hello")],
                status: .completed
            ),
            AppServerTurn(
                id: "turn-2",
                items: [.plan(id: "plan-1", text: "ship it")],
                status: .completed
            )
        ])

        XCTAssertEqual(thread.items(forTurnID: "turn-1"), [.agentMessage(id: "msg-1", text: "hello")])
        XCTAssertNil(thread.items(forTurnID: "missing"))
    }

    func testTurnCompletionBackfillSkipsEphemeralAndNonEmptyTurnsLikeRustExec() {
        let emptyCompletedTurn = AppServerTurn(id: "turn-1", items: [], status: .completed)
        let nonEmptyCompletedTurn = AppServerTurn(
            id: "turn-1",
            items: [.agentMessage(id: "msg-1", text: "hello")],
            status: .completed
        )

        XCTAssertTrue(AppServerTurnCompletionBackfill.shouldBackfill(
            threadEphemeral: false,
            completedTurn: emptyCompletedTurn
        ))
        XCTAssertFalse(AppServerTurnCompletionBackfill.shouldBackfill(
            threadEphemeral: true,
            completedTurn: emptyCompletedTurn
        ))
        XCTAssertFalse(AppServerTurnCompletionBackfill.shouldBackfill(
            threadEphemeral: false,
            completedTurn: nonEmptyCompletedTurn
        ))
    }

    func testTurnCompletionBackfillCopiesMatchingItemsLikeRustExec() {
        let thread = AppServerThread(id: "thread-1", turns: [
            AppServerTurn(
                id: "turn-1",
                items: [.agentMessage(id: "msg-1", text: "hello")],
                status: .completed
            ),
            AppServerTurn(
                id: "turn-2",
                items: [.plan(id: "plan-1", text: "ship it")],
                status: .completed
            )
        ])
        let emptyCompletedTurn = AppServerTurn(id: "turn-2", items: [], status: .completed)
        let missingCompletedTurn = AppServerTurn(id: "missing", items: [], status: .completed)

        XCTAssertEqual(
            AppServerTurnCompletionBackfill.backfilledTurn(emptyCompletedTurn, from: thread).items,
            [.plan(id: "plan-1", text: "ship it")]
        )
        XCTAssertEqual(
            AppServerTurnCompletionBackfill.backfilledTurn(missingCompletedTurn, from: thread).items,
            []
        )
    }
}
