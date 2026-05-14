import CodexCore
import XCTest

final class AppServerThreadProtocolTests: XCTestCase {
    private let repoPath = try! AbsolutePath(absolutePath: "/repo")
    private let agentsPath = try! AbsolutePath(absolutePath: "/repo/AGENTS.md")

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

    func testThreadStartSourceAndMockExperimentalMethodRoundTripLikeRustProtocol() throws {
        XCTAssertEqual(
            String(data: try JSONEncoder().encode(ThreadStartSource.startup), encoding: .utf8),
            #""startup""#
        )
        XCTAssertEqual(
            String(data: try JSONEncoder().encode(ThreadStartSource.clear), encoding: .utf8),
            #""clear""#
        )
        XCTAssertEqual(
            try JSONDecoder().decode(ThreadStartSource.self, from: Data(#""clear""#.utf8)),
            .clear
        )

        try XCTAssertJSONObjectEqual(MockExperimentalMethodParams(value: "hello"), [
            "value": "hello"
        ])
        try XCTAssertJSONObjectEqual(MockExperimentalMethodParams(), [
            "value": NSNull()
        ])
        try XCTAssertJSONObjectEqual(MockExperimentalMethodResponse(echoed: "hello"), [
            "echoed": "hello"
        ])
        try XCTAssertJSONObjectEqual(MockExperimentalMethodResponse(echoed: nil), [
            "echoed": NSNull()
        ])

        let decodedParams = try JSONDecoder().decode(
            MockExperimentalMethodParams.self,
            from: Data(#"{"value":null}"#.utf8)
        )
        XCTAssertNil(decodedParams.value)

        let decodedResponse = try JSONDecoder().decode(
            MockExperimentalMethodResponse.self,
            from: Data(#"{"echoed":"hello"}"#.utf8)
        )
        XCTAssertEqual(decodedResponse.echoed, "hello")
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

    func testAgentMessageItemCarriesMemoryCitationLikeRustProtocol() throws {
        let citation = AppServerMemoryCitation(
            entries: [
                AppServerMemoryCitationEntry(
                    path: "MEMORY.md",
                    lineStart: 12,
                    lineEnd: 14,
                    note: "port checkpoint"
                )
            ],
            threadIDs: ["019cc2ea-1dff-7902-8d40-c8f6e5d83cc4"]
        )
        let item = AppServerThreadItem.agentMessage(
            id: "item-1",
            text: "Ready",
            phase: .finalAnswer,
            memoryCitation: citation
        )

        try XCTAssertJSONObjectEqual(item, [
            "type": "agentMessage",
            "id": "item-1",
            "text": "Ready",
            "phase": "final_answer",
            "memoryCitation": [
                "entries": [[
                    "path": "MEMORY.md",
                    "lineStart": 12,
                    "lineEnd": 14,
                    "note": "port checkpoint"
                ]],
                "threadIds": ["019cc2ea-1dff-7902-8d40-c8f6e5d83cc4"]
            ]
        ])

        let decoded = try JSONDecoder().decode(
            AppServerThreadItem.self,
            from: Data(#"""
            {
              "type": "agentMessage",
              "id": "item-1",
              "text": "Ready",
              "phase": "final_answer",
              "memoryCitation": {
                "entries": [{
                  "path": "MEMORY.md",
                  "lineStart": 12,
                  "lineEnd": 14,
                  "note": "port checkpoint"
                }],
                "threadIds": ["019cc2ea-1dff-7902-8d40-c8f6e5d83cc4"]
              }
            }
            """#.utf8)
        )
        XCTAssertEqual(decoded, item)
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

    func testThreadListParamsRoundTripLikeRustProtocol() throws {
        try XCTAssertJSONObjectEqual(ThreadListParams(), [:])

        try XCTAssertJSONObjectEqual(
            ThreadListParams(
                cursor: "cursor_1",
                limit: 25,
                sortKey: .createdAt,
                sortDirection: .asc,
                modelProviders: ["openai"],
                sourceKinds: [.cli, .vsCode, .subAgentThreadSpawn],
                archived: true,
                cwd: .many(["/repo", "/other"]),
                useStateDBOnly: true,
                searchTerm: "shipping"
            ),
            [
                "cursor": "cursor_1",
                "limit": 25,
                "sortKey": "created_at",
                "sortDirection": "asc",
                "modelProviders": ["openai"],
                "sourceKinds": ["cli", "vscode", "subAgentThreadSpawn"],
                "archived": true,
                "cwd": ["/repo", "/other"],
                "useStateDbOnly": true,
                "searchTerm": "shipping"
            ]
        )

        try XCTAssertJSONObjectEqual(ThreadListParams(cwd: .one("/repo")), [
            "cwd": "/repo"
        ])

        let decoded = try JSONDecoder().decode(
            ThreadListParams.self,
            from: Data(#"""
            {
              "sortKey": "updated_at",
              "sortDirection": "desc",
              "sourceKinds": ["exec", "appServer", "unknown"],
              "cwd": "/repo",
              "useStateDbOnly": true
            }
            """#.utf8)
        )
        XCTAssertEqual(decoded.sortKey, .updatedAt)
        XCTAssertEqual(decoded.sortDirection, .desc)
        XCTAssertEqual(decoded.sourceKinds, [.exec, .appServer, .unknown])
        XCTAssertEqual(decoded.cwd, .one("/repo"))
        XCTAssertTrue(decoded.useStateDBOnly)
    }

    func testThreadListAndReadResponsesCarryRustThreadDataShape() throws {
        let turn = AppServerTurn(
            id: "turn-1",
            items: [.agentMessage(id: "item-1", text: "Ready")],
            itemsView: .summary,
            status: .completed,
            startedAt: 1_000,
            completedAt: 1_002,
            durationMs: 2_000
        )
        let thread = AppServerThread(
            id: "thread-1",
            sessionID: "session-1",
            preview: "Ship parity",
            ephemeral: false,
            modelProvider: "openai",
            createdAt: 900,
            updatedAt: 1_100,
            status: .idle,
            path: "/Users/me/.codex/sessions/thread-1.jsonl",
            cwd: "/repo",
            cliVersion: "0.50.0",
            source: .appServer,
            threadSource: .user,
            agentRole: "worker",
            gitInfo: AppServerThreadGitInfo(sha: "abc123", branch: "main", originURL: nil),
            name: "Parity slice",
            turns: [turn]
        )

        try XCTAssertJSONObjectEqual(
            ThreadListResponse(data: [thread], nextCursor: nil, backwardsCursor: "prev"),
            [
                "data": [[
                    "id": "thread-1",
                    "sessionId": "session-1",
                    "forkedFromId": NSNull(),
                    "preview": "Ship parity",
                    "ephemeral": false,
                    "modelProvider": "openai",
                    "createdAt": 900,
                    "updatedAt": 1_100,
                    "status": [
                        "type": "idle"
                    ],
                    "path": "/Users/me/.codex/sessions/thread-1.jsonl",
                    "cwd": "/repo",
                    "cliVersion": "0.50.0",
                    "source": "appServer",
                    "threadSource": "user",
                    "agentNickname": NSNull(),
                    "agentRole": "worker",
                    "gitInfo": [
                        "sha": "abc123",
                        "branch": "main",
                        "originUrl": NSNull()
                    ],
                    "name": "Parity slice",
                    "turns": [[
                        "id": "turn-1",
                        "items": [[
                            "type": "agentMessage",
                            "id": "item-1",
                            "text": "Ready"
                        ]],
                        "itemsView": "summary",
                        "status": "completed",
                        "error": NSNull(),
                        "startedAt": 1_000,
                        "completedAt": 1_002,
                        "durationMs": 2_000
                    ]]
                ]],
                "nextCursor": NSNull(),
                "backwardsCursor": "prev"
            ]
        )

        try XCTAssertJSONObjectEqual(ThreadReadResponse(thread: thread), [
            "thread": [
                "id": "thread-1",
                "sessionId": "session-1",
                "forkedFromId": NSNull(),
                "preview": "Ship parity",
                "ephemeral": false,
                "modelProvider": "openai",
                "createdAt": 900,
                "updatedAt": 1_100,
                "status": [
                    "type": "idle"
                ],
                "path": "/Users/me/.codex/sessions/thread-1.jsonl",
                "cwd": "/repo",
                "cliVersion": "0.50.0",
                "source": "appServer",
                "threadSource": "user",
                "agentNickname": NSNull(),
                "agentRole": "worker",
                "gitInfo": [
                    "sha": "abc123",
                    "branch": "main",
                    "originUrl": NSNull()
                ],
                "name": "Parity slice",
                "turns": [[
                    "id": "turn-1",
                    "items": [[
                        "type": "agentMessage",
                        "id": "item-1",
                        "text": "Ready"
                    ]],
                    "itemsView": "summary",
                    "status": "completed",
                    "error": NSNull(),
                    "startedAt": 1_000,
                    "completedAt": 1_002,
                    "durationMs": 2_000
                ]]
            ]
        ])

        let decodedSource = try JSONDecoder().decode(
            AppServerSessionSource.self,
            from: Data(#"{"custom":"atlas"}"#.utf8)
        )
        XCTAssertEqual(decodedSource, .custom("atlas"))
    }

    func testThreadStartResumeAndForkResponsesCarryRustRuntimeShape() throws {
        let thread = AppServerThread(
            id: "thread-1",
            sessionID: "session-1",
            preview: "Runtime",
            ephemeral: false,
            modelProvider: "mock_provider",
            createdAt: 1,
            updatedAt: 2,
            status: .notLoaded,
            path: nil,
            cwd: "/repo",
            cliVersion: "0.50.0",
            source: .appServer,
            threadSource: .user,
            turns: []
        )

        let permissionProfile = AppServerPermissionProfile.managed(
            network: AppServerPermissionProfileNetworkPermissions(enabled: true),
            fileSystem: .unrestricted
        )
        let activePermissionProfile = AppServerActivePermissionProfile(id: ":workspace")
        let expectedThread = expectedRuntimeThreadJSON()

        try XCTAssertJSONObjectEqual(
            ThreadStartResponse(
                thread: thread,
                model: "gpt-5",
                modelProvider: "mock_provider",
                serviceTier: nil,
                cwd: repoPath,
                approvalPolicy: .never,
                approvalsReviewer: .autoReview,
                sandbox: .newWorkspaceWritePolicy(),
                permissionProfile: nil,
                activePermissionProfile: nil,
                reasoningEffort: nil
            ),
            [
                "thread": expectedThread,
                "model": "gpt-5",
                "modelProvider": "mock_provider",
                "serviceTier": NSNull(),
                "cwd": "/repo",
                "instructionSources": [],
                "approvalPolicy": "never",
                "approvalsReviewer": "guardian_subagent",
                "sandbox": [
                    "type": "workspace-write",
                    "network_access": false,
                    "exclude_tmpdir_env_var": false,
                    "exclude_slash_tmp": false
                ],
                "permissionProfile": NSNull(),
                "activePermissionProfile": NSNull(),
                "reasoningEffort": NSNull()
            ]
        )

        let expectedConfiguredRuntime: [String: Any] = [
            "thread": expectedThread,
            "model": "gpt-5",
            "modelProvider": "mock_provider",
            "serviceTier": "priority",
            "cwd": "/repo",
            "instructionSources": ["/repo/AGENTS.md"],
            "approvalPolicy": "on-request",
            "approvalsReviewer": "user",
            "sandbox": [
                "type": "read-only"
            ],
            "permissionProfile": [
                "type": "managed",
                "network": [
                    "enabled": true
                ],
                "fileSystem": [
                    "type": "unrestricted"
                ]
            ],
            "activePermissionProfile": [
                "id": ":workspace",
                "extends": NSNull(),
                "modifications": []
            ],
            "reasoningEffort": "high"
        ]

        try XCTAssertJSONObjectEqual(
            ThreadResumeResponse(
                thread: thread,
                model: "gpt-5",
                modelProvider: "mock_provider",
                serviceTier: "priority",
                cwd: repoPath,
                instructionSources: [agentsPath],
                approvalPolicy: .onRequest,
                approvalsReviewer: .user,
                sandbox: .readOnly,
                permissionProfile: permissionProfile,
                activePermissionProfile: activePermissionProfile,
                reasoningEffort: .high
            ),
            expectedConfiguredRuntime
        )

        try XCTAssertJSONObjectEqual(
            ThreadForkResponse(
                thread: thread,
                model: "gpt-5",
                modelProvider: "mock_provider",
                serviceTier: "priority",
                cwd: repoPath,
                instructionSources: [agentsPath],
                approvalPolicy: .onRequest,
                approvalsReviewer: .user,
                sandbox: .readOnly,
                permissionProfile: permissionProfile,
                activePermissionProfile: activePermissionProfile,
                reasoningEffort: .high
            ),
            expectedConfiguredRuntime
        )
    }

    func testThreadRuntimeResponsesRejectRelativeCwdAndInstructionSourcesLikeRustAbsolutePathBuf() throws {
        let baseResponse = """
        {
          "thread": {
            "id": "thread_123",
            "archived": false,
            "source": "user",
            "metadata": {
              "createdAt": "2026-05-14T00:00:00Z",
              "updatedAt": "2026-05-14T00:00:00Z",
              "git": null
            },
            "turns": []
          },
          "model": "gpt-5",
          "modelProvider": "mock_provider",
          "serviceTier": null,
          "approvalPolicy": "never",
          "approvalsReviewer": "guardian_subagent",
          "sandbox": {
            "type": "read-only"
          },
          "permissionProfile": null,
          "activePermissionProfile": null,
          "reasoningEffort": null
        }
        """
        let baseObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(baseResponse.utf8)) as? [String: Any]
        )

        func payload(cwd: String = "/repo", instructionSources: [String] = []) throws -> Data {
            var object = baseObject
            object["cwd"] = cwd
            object["instructionSources"] = instructionSources
            return try JSONSerialization.data(withJSONObject: object)
        }

        XCTAssertThrowsError(try JSONDecoder().decode(ThreadStartResponse.self, from: try payload(cwd: "repo")))
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                ThreadResumeResponse.self,
                from: try payload(instructionSources: ["AGENTS.md"])
            )
        )
        XCTAssertThrowsError(try JSONDecoder().decode(ThreadForkResponse.self, from: try payload(cwd: "repo")))
    }

    func testThreadStatusRoundTripLikeRustProtocol() throws {
        try XCTAssertJSONObjectEqual(AppServerThreadStatus.notLoaded, [
            "type": "notLoaded"
        ])
        try XCTAssertJSONObjectEqual(AppServerThreadStatus.idle, [
            "type": "idle"
        ])
        try XCTAssertJSONObjectEqual(AppServerThreadStatus.systemError, [
            "type": "systemError"
        ])
        try XCTAssertJSONObjectEqual(
            AppServerThreadStatus.active(activeFlags: [.waitingOnApproval, .waitingOnUserInput]),
            [
                "type": "active",
                "activeFlags": ["waitingOnApproval", "waitingOnUserInput"]
            ]
        )

        let decoded = try JSONDecoder().decode(
            AppServerThreadStatus.self,
            from: Data(#"{"type":"active","activeFlags":["waitingOnApproval"]}"#.utf8)
        )
        XCTAssertEqual(decoded, .active(activeFlags: [.waitingOnApproval]))
    }

    func testThreadNotificationModelsRoundTripLikeRustProtocol() throws {
        let tokenBreakdown = TokenUsageBreakdown(
            totalTokens: 30,
            inputTokens: 20,
            cachedInputTokens: 5,
            outputTokens: 8,
            reasoningOutputTokens: 2
        )
        let tokenUsage = ThreadTokenUsage(total: tokenBreakdown, last: tokenBreakdown, modelContextWindow: nil)

        try XCTAssertJSONObjectEqual(
            ThreadTokenUsageUpdatedNotification(
                threadID: "thread-1",
                turnID: "turn-1",
                tokenUsage: tokenUsage
            ),
            [
                "threadId": "thread-1",
                "turnId": "turn-1",
                "tokenUsage": [
                    "total": [
                        "totalTokens": 30,
                        "inputTokens": 20,
                        "cachedInputTokens": 5,
                        "outputTokens": 8,
                        "reasoningOutputTokens": 2
                    ],
                    "last": [
                        "totalTokens": 30,
                        "inputTokens": 20,
                        "cachedInputTokens": 5,
                        "outputTokens": 8,
                        "reasoningOutputTokens": 2
                    ],
                    "modelContextWindow": NSNull()
                ]
            ]
        )

        try XCTAssertJSONObjectEqual(
            ThreadStartedNotification(
                thread: AppServerThread(
                    id: "thread-1",
                    turns: [
                        AppServerTurn(id: "turn-1", items: [.contextCompaction(id: "item-1")], status: .completed)
                    ]
                )
            ),
            [
                "thread": [
                    "id": "thread-1",
                    "sessionId": "thread-1",
                    "forkedFromId": NSNull(),
                    "preview": "",
                    "ephemeral": false,
                    "modelProvider": "",
                    "createdAt": 0,
                    "updatedAt": 0,
                    "status": [
                        "type": "notLoaded"
                    ],
                    "path": NSNull(),
                    "cwd": "/",
                    "cliVersion": "",
                    "source": "vscode",
                    "threadSource": NSNull(),
                    "agentNickname": NSNull(),
                    "agentRole": NSNull(),
                    "gitInfo": NSNull(),
                    "name": NSNull(),
                    "turns": [
                        [
                            "id": "turn-1",
                            "items": [
                                [
                                    "type": "contextCompaction",
                                    "id": "item-1"
                                ]
                            ],
                            "itemsView": "full",
                            "status": "completed",
                            "error": NSNull(),
                            "startedAt": NSNull(),
                            "completedAt": NSNull(),
                            "durationMs": NSNull()
                        ]
                    ]
                ]
            ]
        )

        try XCTAssertJSONObjectEqual(
            ThreadStatusChangedNotification(
                threadID: "thread-1",
                status: .active(activeFlags: [.waitingOnApproval])
            ),
            [
                "threadId": "thread-1",
                "status": [
                    "type": "active",
                    "activeFlags": ["waitingOnApproval"]
                ]
            ]
        )

        try XCTAssertJSONObjectEqual(ThreadArchivedNotification(threadID: "thread-1"), [
            "threadId": "thread-1"
        ])
        try XCTAssertJSONObjectEqual(ThreadUnarchivedNotification(threadID: "thread-1"), [
            "threadId": "thread-1"
        ])
        try XCTAssertJSONObjectEqual(ThreadClosedNotification(threadID: "thread-1"), [
            "threadId": "thread-1"
        ])
        try XCTAssertJSONObjectEqual(ThreadGoalClearedNotification(threadID: "thread-1"), [
            "threadId": "thread-1"
        ])
        try XCTAssertJSONObjectEqual(ContextCompactedNotification(threadID: "thread-1", turnID: "turn-1"), [
            "threadId": "thread-1",
            "turnId": "turn-1"
        ])

        let decodedUsage = try JSONDecoder().decode(
            ThreadTokenUsage.self,
            from: Data(#"""
            {
              "total": {
                "totalTokens": 1,
                "inputTokens": 2,
                "cachedInputTokens": 3,
                "outputTokens": 4,
                "reasoningOutputTokens": 5
              },
              "last": {
                "totalTokens": 6,
                "inputTokens": 7,
                "cachedInputTokens": 8,
                "outputTokens": 9,
                "reasoningOutputTokens": 10
              },
              "modelContextWindow": 128000
            }
            """#.utf8)
        )
        XCTAssertEqual(decodedUsage.modelContextWindow, 128_000)
        XCTAssertEqual(decodedUsage.total.totalTokens, 1)
        XCTAssertEqual(decodedUsage.last.reasoningOutputTokens, 10)
    }

    func testThreadNameAndGoalNotificationsPreserveRustNullSemantics() throws {
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

        try XCTAssertJSONObjectEqual(ThreadNameUpdatedNotification(threadID: threadID.description), [
            "threadId": threadID.description
        ])
        try XCTAssertJSONObjectEqual(
            ThreadNameUpdatedNotification(threadID: threadID.description, threadName: "Fresh name"),
            [
                "threadId": threadID.description,
                "threadName": "Fresh name"
            ]
        )

        let decodedMissingName = try JSONDecoder().decode(
            ThreadNameUpdatedNotification.self,
            from: Data(#"{"threadId":"\#(threadID.description)"}"#.utf8)
        )
        XCTAssertNil(decodedMissingName.threadName)

        try XCTAssertJSONObjectEqual(
            ThreadGoalUpdatedNotification(threadID: threadID.description, turnID: nil, goal: goal),
            [
                "threadId": threadID.description,
                "turnId": NSNull(),
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
            ]
        )

        let decodedGoalNotification = try JSONDecoder().decode(
            ThreadGoalUpdatedNotification.self,
            from: Data(#"""
            {
              "threadId": "\#(threadID.description)",
              "turnId": null,
              "goal": {
                "threadId": "\#(threadID.description)",
                "objective": "ship parity",
                "status": "active",
                "tokenBudget": null,
                "tokensUsed": 12,
                "timeUsedSeconds": 34,
                "createdAt": 100,
                "updatedAt": 200
              }
            }
            """#.utf8)
        )
        XCTAssertNil(decodedGoalNotification.turnID)
        XCTAssertEqual(decodedGoalNotification.goal, goal)
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

        let unarchivedThread = AppServerThread(
            id: "thread-1",
            sessionID: "session-1",
            preview: "Runtime",
            ephemeral: false,
            modelProvider: "mock_provider",
            createdAt: 1,
            updatedAt: 2,
            status: .notLoaded,
            path: nil,
            cwd: "/repo",
            cliVersion: "0.50.0",
            source: .appServer,
            threadSource: .user,
            turns: []
        )
        try XCTAssertJSONObjectEqual(ThreadUnarchiveResponse(thread: unarchivedThread), [
            "thread": expectedRuntimeThreadJSON()
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
        let thread = AppServerThread(
            id: "thread-1",
            sessionID: "session-1",
            preview: "Runtime",
            ephemeral: false,
            modelProvider: "mock_provider",
            createdAt: 1,
            updatedAt: 2,
            status: .notLoaded,
            path: nil,
            cwd: "/repo",
            cliVersion: "0.50.0",
            source: .appServer,
            threadSource: .user,
            turns: []
        )

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
        try XCTAssertJSONObjectEqual(ThreadRollbackResponse(thread: thread), [
            "thread": expectedRuntimeThreadJSON()
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
        try XCTAssertJSONObjectEqual(ThreadMetadataUpdateResponse(thread: thread), [
            "thread": expectedRuntimeThreadJSON()
        ])
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

private func expectedRuntimeThreadJSON() -> [String: Any] {
    [
        "id": "thread-1",
        "sessionId": "session-1",
        "forkedFromId": NSNull(),
        "preview": "Runtime",
        "ephemeral": false,
        "modelProvider": "mock_provider",
        "createdAt": 1,
        "updatedAt": 2,
        "status": [
            "type": "notLoaded"
        ],
        "path": NSNull(),
        "cwd": "/repo",
        "cliVersion": "0.50.0",
        "source": "appServer",
        "threadSource": "user",
        "agentNickname": NSNull(),
        "agentRole": NSNull(),
        "gitInfo": NSNull(),
        "name": NSNull(),
        "turns": []
    ]
}
