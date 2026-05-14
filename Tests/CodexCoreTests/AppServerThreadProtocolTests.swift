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

    func testThreadArchiveAndUnsubscribeRoundTripLikeRustProtocol() throws {
        try XCTAssertJSONObjectEqual(ThreadArchiveParams(threadID: "thr_archive"), [
            "threadId": "thr_archive"
        ])
        try XCTAssertJSONObjectEqual(ThreadArchiveResponse(), [:])

        try XCTAssertJSONObjectEqual(ThreadUnarchiveParams(threadID: "thr_unarchive"), [
            "threadId": "thr_unarchive"
        ])

        try XCTAssertJSONObjectEqual(ThreadUnsubscribeParams(threadID: "thr_unsubscribe"), [
            "threadId": "thr_unsubscribe"
        ])

        for status in [
            ThreadUnsubscribeStatus.notLoaded,
            .notSubscribed,
            .unsubscribed
        ] {
            let response = ThreadUnsubscribeResponse(status: status)
            let expectedStatus: String
            switch status {
            case .notLoaded:
                expectedStatus = "notLoaded"
            case .notSubscribed:
                expectedStatus = "notSubscribed"
            case .unsubscribed:
                expectedStatus = "unsubscribed"
            }
            try XCTAssertJSONObjectEqual(response, ["status": expectedStatus])
        }

        let decoded = try JSONDecoder().decode(
            ThreadUnsubscribeResponse.self,
            from: Data(#"{"status":"notSubscribed"}"#.utf8)
        )
        XCTAssertEqual(decoded.status, .notSubscribed)
    }

    func testThreadElicitationCounterRoundTripsLikeRustProtocol() throws {
        try XCTAssertJSONObjectEqual(ThreadIncrementElicitationParams(threadID: "thr_increment"), [
            "threadId": "thr_increment"
        ])
        try XCTAssertJSONObjectEqual(ThreadIncrementElicitationResponse(count: 1, paused: true), [
            "count": 1,
            "paused": true
        ])

        try XCTAssertJSONObjectEqual(ThreadDecrementElicitationParams(threadID: "thr_decrement"), [
            "threadId": "thr_decrement"
        ])
        try XCTAssertJSONObjectEqual(ThreadDecrementElicitationResponse(count: 0, paused: false), [
            "count": 0,
            "paused": false
        ])

        let decoded = try JSONDecoder().decode(
            ThreadIncrementElicitationResponse.self,
            from: Data(#"{"count":42,"paused":true}"#.utf8)
        )
        XCTAssertEqual(decoded, ThreadIncrementElicitationResponse(count: 42, paused: true))
    }

    func testThreadCommandActionParamsRoundTripLikeRustProtocol() throws {
        try XCTAssertJSONObjectEqual(ThreadSetNameParams(threadID: "thr_name", name: "Working title"), [
            "threadId": "thr_name",
            "name": "Working title"
        ])
        try XCTAssertJSONObjectEqual(ThreadSetNameResponse(), [:])

        try XCTAssertJSONObjectEqual(ThreadCompactStartParams(threadID: "thr_compact"), [
            "threadId": "thr_compact"
        ])
        try XCTAssertJSONObjectEqual(ThreadCompactStartResponse(), [:])

        try XCTAssertJSONObjectEqual(ThreadShellCommandParams(threadID: "thr_shell", command: "git status --short"), [
            "threadId": "thr_shell",
            "command": "git status --short"
        ])
        try XCTAssertJSONObjectEqual(ThreadShellCommandResponse(), [:])

        let guardianEvent: JSONValue = .object([
            "kind": .string("guardian"),
            "decision": .string("denied")
        ])
        try XCTAssertJSONObjectEqual(
            ThreadApproveGuardianDeniedActionParams(threadID: "thr_guardian", event: guardianEvent),
            [
                "threadId": "thr_guardian",
                "event": [
                    "kind": "guardian",
                    "decision": "denied"
                ]
            ]
        )
        try XCTAssertJSONObjectEqual(ThreadApproveGuardianDeniedActionResponse(), [:])

        try XCTAssertJSONObjectEqual(ThreadBackgroundTerminalsCleanParams(threadID: "thr_background"), [
            "threadId": "thr_background"
        ])
        try XCTAssertJSONObjectEqual(ThreadBackgroundTerminalsCleanResponse(), [:])

        let decoded = try JSONDecoder().decode(
            ThreadShellCommandParams.self,
            from: Data(#"{"threadId":"thr_shell_2","command":"printf 'hello' | cat"}"#.utf8)
        )
        XCTAssertEqual(decoded.threadID, "thr_shell_2")
        XCTAssertEqual(decoded.command, "printf 'hello' | cat")
    }

    func testThreadGoalAndMemoryModeParamsRoundTripLikeRustProtocol() throws {
        let threadID = try ThreadId(string: "018f7a2d-4c5b-7abc-8def-0123456789ab")
        let goal = ThreadGoal(
            threadID: threadID,
            objective: "ship parity",
            status: .active,
            tokenBudget: nil,
            tokensUsed: 12,
            timeUsedSeconds: 34,
            createdAt: 100,
            updatedAt: 200
        )

        try XCTAssertJSONObjectEqual(
            ThreadGoalSetParams(
                threadID: threadID.description,
                objective: "ship parity",
                status: .budgetLimited,
                tokenBudget: .set(1_024)
            ),
            [
                "threadId": threadID.description,
                "objective": "ship parity",
                "status": "budgetLimited",
                "tokenBudget": 1_024
            ]
        )
        try XCTAssertJSONObjectEqual(ThreadGoalSetParams(threadID: threadID.description), [
            "threadId": threadID.description
        ])
        try XCTAssertJSONObjectEqual(
            ThreadGoalSetParams(threadID: threadID.description, tokenBudget: .clear),
            [
                "threadId": threadID.description,
                "tokenBudget": NSNull()
            ]
        )
        try XCTAssertJSONObjectEqual(ThreadGoalSetResponse(goal: goal), [
            "goal": [
                "threadId": threadID.description,
                "objective": "ship parity",
                "status": "active",
                "tokenBudget": NSNull(),
                "tokensUsed": 12,
                "timeUsedSeconds": 34,
                "createdAt": 100,
                "updatedAt": 200
            ]
        ])

        try XCTAssertJSONObjectEqual(ThreadGoalGetParams(threadID: threadID.description), [
            "threadId": threadID.description
        ])
        try XCTAssertJSONObjectEqual(ThreadGoalGetResponse(goal: nil), [
            "goal": NSNull()
        ])
        try XCTAssertJSONObjectEqual(ThreadGoalClearParams(threadID: threadID.description), [
            "threadId": threadID.description
        ])
        try XCTAssertJSONObjectEqual(ThreadGoalClearResponse(cleared: true), [
            "cleared": true
        ])

        try XCTAssertJSONObjectEqual(ThreadMemoryModeSetParams(threadID: threadID.description, mode: .disabled), [
            "threadId": threadID.description,
            "mode": "disabled"
        ])
        try XCTAssertJSONObjectEqual(ThreadMemoryModeSetResponse(), [:])

        let preserve = try JSONDecoder().decode(
            ThreadGoalSetParams.self,
            from: Data(#"{"threadId":"\#(threadID.description)","objective":"keep going"}"#.utf8)
        )
        XCTAssertEqual(preserve.tokenBudget, .preserve)

        let clear = try JSONDecoder().decode(
            ThreadGoalSetParams.self,
            from: Data(#"{"threadId":"\#(threadID.description)","tokenBudget":null}"#.utf8)
        )
        XCTAssertEqual(clear.tokenBudget, .clear)

        let set = try JSONDecoder().decode(
            ThreadGoalSetParams.self,
            from: Data(#"{"threadId":"\#(threadID.description)","tokenBudget":99}"#.utf8)
        )
        XCTAssertEqual(set.tokenBudget, .set(99))
    }

    func testThreadReadRollbackMetadataAndMemoryResetRoundTripLikeRustProtocol() throws {
        let threadID = "018f7a2d-4c5b-7abc-8def-0123456789ab"

        try XCTAssertJSONObjectEqual(ThreadReadParams(threadID: threadID), [
            "threadId": threadID,
            "includeTurns": false
        ])
        try XCTAssertJSONObjectEqual(ThreadReadParams(threadID: threadID, includeTurns: true), [
            "threadId": threadID,
            "includeTurns": true
        ])
        let defaultRead = try JSONDecoder().decode(
            ThreadReadParams.self,
            from: Data(#"{"threadId":"\#(threadID)"}"#.utf8)
        )
        XCTAssertFalse(defaultRead.includeTurns)

        try XCTAssertJSONObjectEqual(ThreadRollbackParams(threadID: threadID, numTurns: 3), [
            "threadId": threadID,
            "numTurns": 3
        ])

        try XCTAssertJSONObjectEqual(
            ThreadMetadataUpdateParams(
                threadID: threadID,
                gitInfo: ThreadMetadataGitInfoUpdateParams(
                    sha: .set("abc123"),
                    branch: .clear,
                    originURL: .preserve
                )
            ),
            [
                "threadId": threadID,
                "gitInfo": [
                    "sha": "abc123",
                    "branch": NSNull()
                ]
            ]
        )
        try XCTAssertJSONObjectEqual(ThreadMetadataUpdateParams(threadID: threadID, gitInfo: nil), [
            "threadId": threadID,
            "gitInfo": NSNull()
        ])
        let gitPatch = try JSONDecoder().decode(
            ThreadMetadataGitInfoUpdateParams.self,
            from: Data(#"{"sha":"def456","branch":null}"#.utf8)
        )
        XCTAssertEqual(gitPatch.sha, .set("def456"))
        XCTAssertEqual(gitPatch.branch, .clear)
        XCTAssertEqual(gitPatch.originURL, .preserve)

        try XCTAssertJSONObjectEqual(MemoryResetResponse(), [:])
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
