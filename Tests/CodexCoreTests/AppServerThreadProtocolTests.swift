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

    func testTurnRejectsExplicitNullForRustDefaultedItemsView() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AppServerTurn.self,
                from: Data(#"""
                {
                  "id": "turn_123",
                  "items": [],
                  "itemsView": null,
                  "status": "completed",
                  "error": null,
                  "startedAt": null,
                  "completedAt": null,
                  "durationMs": null
                }
                """#.utf8)
            )
        )
    }

    func testThreadItemsRejectExplicitNullForRustDefaultedFields() {
        let nullReasoningSummary = Data(#"{"type":"reasoning","id":"item-1","summary":null,"content":[]}"#.utf8)
        let nullReasoningContent = Data(#"{"type":"reasoning","id":"item-1","summary":[],"content":null}"#.utf8)
        let nullCommandSource = Data(#"""
        {
          "type": "commandExecution",
          "id": "item-2",
          "command": "pwd",
          "cwd": "/repo",
          "processId": null,
          "source": null,
          "status": "completed",
          "commandActions": [],
          "aggregatedOutput": null,
          "exitCode": 0,
          "durationMs": null
        }
        """#.utf8)

        for payload in [nullReasoningSummary, nullReasoningContent, nullCommandSource] {
            XCTAssertThrowsError(try JSONDecoder().decode(AppServerThreadItem.self, from: payload))
        }
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

    func testThreadStartResumeAndForkParamsPreserveRustDoubleOptionServiceTier() throws {
        let startDefault = try JSONObject(ThreadStartParams())
        XCTAssertFalse(startDefault.keys.contains("serviceTier"))
        XCTAssertEqual(startDefault["model"] as? NSNull, NSNull())
        XCTAssertEqual(startDefault["experimentalRawEvents"] as? Bool, false)
        XCTAssertEqual(startDefault["persistExtendedHistory"] as? Bool, false)

        try XCTAssertJSONObjectEqual(
            ThreadStartParams(
                model: "gpt-5",
                modelProvider: "mock_provider",
                serviceTier: .clear,
                cwd: "/repo",
                approvalPolicy: .never,
                approvalsReviewer: .autoReview,
                sandbox: .workspaceWrite,
                config: ["feature": .bool(true)],
                serviceName: "desktop",
                baseInstructions: "Base",
                developerInstructions: "Dev",
                personality: .pragmatic,
                ephemeral: true,
                sessionStartSource: .startup,
                threadSource: .user,
                experimentalRawEvents: true,
                persistExtendedHistory: true
            ),
            [
                "model": "gpt-5",
                "modelProvider": "mock_provider",
                "serviceTier": NSNull(),
                "cwd": "/repo",
                "approvalPolicy": "never",
                "approvalsReviewer": "guardian_subagent",
                "sandbox": "workspace-write",
                "permissions": NSNull(),
                "config": ["feature": true],
                "serviceName": "desktop",
                "baseInstructions": "Base",
                "developerInstructions": "Dev",
                "personality": "pragmatic",
                "ephemeral": true,
                "sessionStartSource": "startup",
                "threadSource": "user",
                "environments": NSNull(),
                "dynamicTools": NSNull(),
                "mockExperimentalField": NSNull(),
                "experimentalRawEvents": true,
                "persistExtendedHistory": true
            ]
        )

        let startSet = try JSONDecoder().decode(
            ThreadStartParams.self,
            from: Data(#"{"serviceTier":"priority"}"#.utf8)
        )
        XCTAssertEqual(startSet.serviceTier, .set("priority"))
        XCTAssertFalse(startSet.experimentalRawEvents)
        XCTAssertFalse(startSet.persistExtendedHistory)

        let resumeClear = try JSONDecoder().decode(
            ThreadResumeParams.self,
            from: Data(#"{"threadId":"thread_123","serviceTier":null}"#.utf8)
        )
        XCTAssertEqual(resumeClear.serviceTier, .clear)
        XCTAssertFalse(resumeClear.excludeTurns)

        let forkSet = try JSONDecoder().decode(
            ThreadForkParams.self,
            from: Data(#"{"threadId":"thread_123","serviceTier":"priority","ephemeral":true,"excludeTurns":true}"#.utf8)
        )
        XCTAssertEqual(forkSet.serviceTier, .set("priority"))
        XCTAssertTrue(forkSet.ephemeral)
        XCTAssertTrue(forkSet.excludeTurns)
    }

    func testTurnStartParamsRoundTripEnvironmentsLikeRustProtocol() throws {
        let environment = AppServerTurnEnvironmentParams(
            environmentID: "local",
            cwd: try AbsolutePath(absolutePath: "/repo")
        )

        try XCTAssertJSONObjectEqual(
            AppServerTurnStartParams(threadID: "thread_123", input: [], environments: [environment]),
            [
                "threadId": "thread_123",
                "input": [],
                "responsesapiClientMetadata": NSNull(),
                "environments": [
                    [
                        "environmentId": "local",
                        "cwd": "/repo"
                    ]
                ],
                "cwd": NSNull(),
                "approvalPolicy": NSNull(),
                "approvalsReviewer": NSNull(),
                "sandboxPolicy": NSNull(),
                "permissions": NSNull(),
                "model": NSNull(),
                "effort": NSNull(),
                "summary": NSNull(),
                "personality": NSNull(),
                "outputSchema": NSNull(),
                "collaborationMode": NSNull()
            ]
        )

        let decoded = try JSONDecoder().decode(
            AppServerTurnStartParams.self,
            from: Data(#"{"threadId":"thread_123","input":[],"environments":[{"environmentId":"local","cwd":"/repo"}]}"#.utf8)
        )
        XCTAssertEqual(decoded.environments, [environment])

        let decodedEmpty = try JSONDecoder().decode(
            AppServerTurnStartParams.self,
            from: Data(#"{"threadId":"thread_123","input":[],"environments":[]}"#.utf8)
        )
        XCTAssertEqual(decodedEmpty.environments, [])
        try XCTAssertJSONObjectEqual(
            decodedEmpty,
            [
                "threadId": "thread_123",
                "input": [],
                "responsesapiClientMetadata": NSNull(),
                "environments": [],
                "cwd": NSNull(),
                "approvalPolicy": NSNull(),
                "approvalsReviewer": NSNull(),
                "sandboxPolicy": NSNull(),
                "permissions": NSNull(),
                "model": NSNull(),
                "effort": NSNull(),
                "summary": NSNull(),
                "personality": NSNull(),
                "outputSchema": NSNull(),
                "collaborationMode": NSNull()
            ]
        )
    }

    func testTurnStartParamsTreatNullOrOmittedEnvironmentsAsDefaultLikeRustProtocol() throws {
        let decodedNull = try JSONDecoder().decode(
            AppServerTurnStartParams.self,
            from: Data(#"{"threadId":"thread_123","input":[],"environments":null}"#.utf8)
        )
        XCTAssertNil(decodedNull.environments)

        let decodedOmitted = try JSONDecoder().decode(
            AppServerTurnStartParams.self,
            from: Data(#"{"threadId":"thread_123","input":[]}"#.utf8)
        )
        XCTAssertNil(decodedOmitted.environments)
    }

    func testTurnStartParamsRejectRelativeEnvironmentCwdLikeRustProtocol() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AppServerTurnStartParams.self,
                from: Data(#"{"threadId":"thread_123","input":[],"environments":[{"environmentId":"local","cwd":"relative"}]}"#.utf8)
            )
        ) { error in
            XCTAssertTrue(
                String(describing: error).contains("AbsolutePath"),
                "unexpected error: \(error)"
            )
        }
    }

    func testThreadLifecycleParamsRejectExplicitNullForRustDefaultedBooleans() {
        let payloads: [(Data) throws -> Void] = [
            { _ = try JSONDecoder().decode(ThreadStartParams.self, from: $0) },
            { _ = try JSONDecoder().decode(ThreadStartParams.self, from: $0) },
            { _ = try JSONDecoder().decode(ThreadResumeParams.self, from: $0) },
            { _ = try JSONDecoder().decode(ThreadResumeParams.self, from: $0) },
            { _ = try JSONDecoder().decode(ThreadForkParams.self, from: $0) },
            { _ = try JSONDecoder().decode(ThreadForkParams.self, from: $0) },
            { _ = try JSONDecoder().decode(ThreadForkParams.self, from: $0) }
        ]
        let inputs = [
            Data(#"{"experimentalRawEvents":null}"#.utf8),
            Data(#"{"persistExtendedHistory":null}"#.utf8),
            Data(#"{"threadId":"thread_123","excludeTurns":null}"#.utf8),
            Data(#"{"threadId":"thread_123","persistExtendedHistory":null}"#.utf8),
            Data(#"{"threadId":"thread_123","ephemeral":null}"#.utf8),
            Data(#"{"threadId":"thread_123","excludeTurns":null}"#.utf8),
            Data(#"{"threadId":"thread_123","persistExtendedHistory":null}"#.utf8)
        ]

        for (decode, payload) in zip(payloads, inputs) {
            XCTAssertThrowsError(try decode(payload))
        }
    }

    func testThreadResumeAndForkParamsSkipFalseFieldsLikeRustProtocol() throws {
        let resume = try JSONObject(ThreadResumeParams(threadID: "thread_123"))
        XCTAssertEqual(resume["threadId"] as? String, "thread_123")
        XCTAssertEqual(resume["history"] as? NSNull, NSNull())
        XCTAssertFalse(resume.keys.contains("serviceTier"))
        XCTAssertFalse(resume.keys.contains("excludeTurns"))
        XCTAssertEqual(resume["persistExtendedHistory"] as? Bool, false)

        let fork = try JSONObject(ThreadForkParams(threadID: "thread_123"))
        XCTAssertEqual(fork["threadId"] as? String, "thread_123")
        XCTAssertEqual(fork["path"] as? NSNull, NSNull())
        XCTAssertFalse(fork.keys.contains("serviceTier"))
        XCTAssertFalse(fork.keys.contains("ephemeral"))
        XCTAssertFalse(fork.keys.contains("excludeTurns"))
        XCTAssertEqual(fork["persistExtendedHistory"] as? Bool, false)

        try XCTAssertJSONObjectEqual(
            ThreadForkParams(
                threadID: "thread_123",
                serviceTier: .set("priority"),
                ephemeral: true,
                threadSource: .subagent,
                excludeTurns: true,
                persistExtendedHistory: true
            ),
            [
                "threadId": "thread_123",
                "path": NSNull(),
                "model": NSNull(),
                "modelProvider": NSNull(),
                "serviceTier": "priority",
                "cwd": NSNull(),
                "approvalPolicy": NSNull(),
                "approvalsReviewer": NSNull(),
                "sandbox": NSNull(),
                "permissions": NSNull(),
                "config": NSNull(),
                "baseInstructions": NSNull(),
                "developerInstructions": NSNull(),
                "ephemeral": true,
                "threadSource": "subagent",
                "excludeTurns": true,
                "persistExtendedHistory": true
            ]
        )
    }

    func testThreadTurnsListParamsAcceptsItemsViewLikeRustProtocol() throws {
        try XCTAssertJSONObjectEqual(ThreadTurnsListParams(threadID: "thr_123"), [
            "threadId": "thr_123",
            "cursor": NSNull(),
            "limit": NSNull(),
            "sortDirection": NSNull(),
            "itemsView": NSNull()
        ])

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

    func testUserMessageAndHookPromptItemsUseRustThreadItemShape() throws {
        let userMessage = AppServerThreadItem.userMessage(
            id: "item-user",
            content: [
                .text("Inspect @file", textElements: [
                    AppServerTextElement(
                        byteRange: AppServerByteRange(start: 8, end: 13),
                        placeholder: "@file"
                    )
                ]),
                .mention(name: "README.md", path: "/repo/README.md")
            ]
        )
        let hookPrompt = AppServerThreadItem.hookPrompt(
            id: "item-hook",
            fragments: [
                HookPromptFragment(text: "Check policy", hookRunID: "hook-1")
            ]
        )

        try XCTAssertJSONObjectEqual(userMessage, [
            "type": "userMessage",
            "id": "item-user",
            "content": [
                [
                    "type": "text",
                    "text": "Inspect @file",
                    "textElements": [[
                        "byteRange": [
                            "start": 8,
                            "end": 13
                        ],
                        "placeholder": "@file"
                    ]]
                ],
                [
                    "type": "mention",
                    "name": "README.md",
                    "path": "/repo/README.md"
                ]
            ]
        ])
        try XCTAssertJSONObjectEqual(hookPrompt, [
            "type": "hookPrompt",
            "id": "item-hook",
            "fragments": [[
                "text": "Check policy",
                "hookRunId": "hook-1"
            ]]
        ])

        let decoded = try JSONDecoder().decode([AppServerThreadItem].self, from: Data(#"""
        [
          {
            "type": "userMessage",
            "id": "item-user",
            "content": [
              {
                "type": "text",
                "text": "Inspect @file",
                "textElements": [{
                  "byteRange": { "start": 8, "end": 13 },
                  "placeholder": "@file"
                }]
              },
              {
                "type": "mention",
                "name": "README.md",
                "path": "/repo/README.md"
              }
            ]
          },
          {
            "type": "hookPrompt",
            "id": "item-hook",
            "fragments": [{
              "text": "Check policy",
              "hookRunId": "hook-1"
            }]
          }
        ]
        """#.utf8))
        XCTAssertEqual(decoded, [userMessage, hookPrompt])
        XCTAssertEqual(decoded.map(\.id), ["item-user", "item-hook"])
    }

    func testPlanAndReasoningItemsUseRustThreadItemShape() throws {
        let plan = AppServerThreadItem.plan(
            id: "item-plan",
            text: "1. Inspect\n2. Patch\n3. Test"
        )
        let reasoning = AppServerThreadItem.reasoning(
            id: "item-reasoning",
            summary: ["Checked Rust ThreadItem shape"],
            content: ["Reasoning body"]
        )
        let emptyReasoning = AppServerThreadItem.reasoning(id: "item-empty-reasoning")

        try XCTAssertJSONObjectEqual(plan, [
            "type": "plan",
            "id": "item-plan",
            "text": "1. Inspect\n2. Patch\n3. Test"
        ])
        try XCTAssertJSONObjectEqual(reasoning, [
            "type": "reasoning",
            "id": "item-reasoning",
            "summary": ["Checked Rust ThreadItem shape"],
            "content": ["Reasoning body"]
        ])
        try XCTAssertJSONObjectEqual(emptyReasoning, [
            "type": "reasoning",
            "id": "item-empty-reasoning",
            "summary": [],
            "content": []
        ])

        let decoded = try JSONDecoder().decode([AppServerThreadItem].self, from: Data(#"""
        [
          {
            "type": "plan",
            "id": "item-plan",
            "text": "1. Inspect\n2. Patch\n3. Test"
          },
          {
            "type": "reasoning",
            "id": "item-reasoning",
            "summary": ["Checked Rust ThreadItem shape"],
            "content": ["Reasoning body"]
          },
          {
            "type": "reasoning",
            "id": "item-default-reasoning"
          }
        ]
        """#.utf8))

        XCTAssertEqual(decoded, [
            plan,
            reasoning,
            .reasoning(id: "item-default-reasoning")
        ])
    }

    func testAgentMessageItemPreservesRustNullDefaults() throws {
        let item = AppServerThreadItem.agentMessage(
            id: "item-agent",
            text: "Working on it"
        )

        try XCTAssertJSONObjectEqual(item, [
            "type": "agentMessage",
            "id": "item-agent",
            "text": "Working on it",
            "phase": NSNull(),
            "memoryCitation": NSNull()
        ])

        let decoded = try JSONDecoder().decode(
            AppServerThreadItem.self,
            from: Data(#"""
            {
              "type": "agentMessage",
              "id": "item-agent",
              "text": "Working on it"
            }
            """#.utf8)
        )
        XCTAssertEqual(decoded, item)
    }

    func testMediaAndSearchItemsUseRustThreadItemShape() throws {
        let imagePath = try AbsolutePath(absolutePath: "/repo/screenshot.png")
        let savedPath = try AbsolutePath(absolutePath: "/repo/generated.png")
        let items: [AppServerThreadItem] = [
            .webSearch(
                id: "search-1",
                query: "swift docs",
                action: .findInPage(url: "https://swift.org/docs", pattern: "Package")
            ),
            .imageView(id: "view-1", path: imagePath),
            .imageGeneration(
                id: "image-1",
                status: "completed",
                revisedPrompt: nil,
                result: "base64",
                savedPath: savedPath
            )
        ]

        try XCTAssertJSONObjectEqual(items[0], [
            "type": "webSearch",
            "id": "search-1",
            "query": "swift docs",
            "action": [
                "type": "findInPage",
                "url": "https://swift.org/docs",
                "pattern": "Package"
            ]
        ])
        try XCTAssertJSONObjectEqual(items[1], [
            "type": "imageView",
            "id": "view-1",
            "path": "/repo/screenshot.png"
        ])
        try XCTAssertJSONObjectEqual(items[2], [
            "type": "imageGeneration",
            "id": "image-1",
            "status": "completed",
            "revisedPrompt": NSNull(),
            "result": "base64",
            "savedPath": "/repo/generated.png"
        ])

        let decoded = try JSONDecoder().decode([AppServerThreadItem].self, from: Data(#"""
        [
          {
            "type": "webSearch",
            "id": "search-1",
            "query": "swift docs",
            "action": {
              "type": "findInPage",
              "url": "https://swift.org/docs",
              "pattern": "Package"
            }
          },
          {
            "type": "imageView",
            "id": "view-1",
            "path": "/repo/screenshot.png"
          },
          {
            "type": "imageGeneration",
            "id": "image-1",
            "status": "completed",
            "revisedPrompt": null,
            "result": "base64",
            "savedPath": "/repo/generated.png"
          }
        ]
        """#.utf8))
        XCTAssertEqual(decoded, items)
        XCTAssertEqual(decoded.map(\.id), ["search-1", "view-1", "image-1"])
    }

    func testMediaAndSearchItemsPreserveRustNullAndOmittedOptionals() throws {
        try XCTAssertJSONObjectEqual(AppServerThreadItem.webSearch(
            id: "search-1",
            query: "swift docs"
        ), [
            "type": "webSearch",
            "id": "search-1",
            "query": "swift docs",
            "action": NSNull()
        ])

        try XCTAssertJSONObjectEqual(AppServerWebSearchAction.search(query: nil, queries: nil), [
            "type": "search",
            "query": NSNull(),
            "queries": NSNull()
        ])

        try XCTAssertJSONObjectEqual(AppServerThreadItem.imageGeneration(
            id: "image-1",
            status: "in_progress",
            result: ""
        ), [
            "type": "imageGeneration",
            "id": "image-1",
            "status": "in_progress",
            "revisedPrompt": NSNull(),
            "result": ""
        ])
    }

    func testReviewModeItemsUseRustThreadItemShape() throws {
        let items: [AppServerThreadItem] = [
            .enteredReviewMode(id: "review-entered", review: "Review uncommitted changes"),
            .exitedReviewMode(id: "review-exited", review: "Looks good")
        ]

        try XCTAssertJSONObjectEqual(items[0], [
            "type": "enteredReviewMode",
            "id": "review-entered",
            "review": "Review uncommitted changes"
        ])
        try XCTAssertJSONObjectEqual(items[1], [
            "type": "exitedReviewMode",
            "id": "review-exited",
            "review": "Looks good"
        ])

        let decoded = try JSONDecoder().decode([AppServerThreadItem].self, from: Data(#"""
        [
          {
            "type": "enteredReviewMode",
            "id": "review-entered",
            "review": "Review uncommitted changes"
          },
          {
            "type": "exitedReviewMode",
            "id": "review-exited",
            "review": "Looks good"
          }
        ]
        """#.utf8))
        XCTAssertEqual(decoded, items)
        XCTAssertEqual(decoded.map(\.id), ["review-entered", "review-exited"])
    }

    func testCommandExecutionItemUsesRustThreadItemShape() throws {
        let item = AppServerThreadItem.commandExecution(
            id: "exec-1",
            command: "cat Package.swift && ls Sources",
            cwd: repoPath,
            source: .unifiedExecStartup,
            status: .inProgress,
            commandActions: [
                .read(command: "cat Package.swift", name: "Package.swift", path: "/repo/Package.swift"),
                .listFiles(command: "ls Sources", path: nil)
            ]
        )

        try XCTAssertJSONObjectEqual(item, [
            "type": "commandExecution",
            "id": "exec-1",
            "command": "cat Package.swift && ls Sources",
            "cwd": "/repo",
            "processId": NSNull(),
            "source": "unifiedExecStartup",
            "status": "inProgress",
            "commandActions": [
                [
                    "type": "read",
                    "command": "cat Package.swift",
                    "name": "Package.swift",
                    "path": "/repo/Package.swift"
                ],
                [
                    "type": "listFiles",
                    "command": "ls Sources"
                ]
            ],
            "aggregatedOutput": NSNull(),
            "exitCode": NSNull(),
            "durationMs": NSNull()
        ])

        let decoded = try JSONDecoder().decode(AppServerThreadItem.self, from: Data(#"""
        {
          "type": "commandExecution",
          "id": "exec-1",
          "command": "cat Package.swift && ls Sources",
          "cwd": "/repo",
          "processId": null,
          "status": "completed",
          "commandActions": [
            {
              "type": "read",
              "command": "cat Package.swift",
              "name": "Package.swift",
              "path": "/repo/Package.swift"
            },
            {
              "type": "listFiles",
              "command": "ls Sources"
            }
          ],
          "aggregatedOutput": "Package.swift\nSources\n",
          "exitCode": 0,
          "durationMs": 42
        }
        """#.utf8))

        XCTAssertEqual(decoded, .commandExecution(
            id: "exec-1",
            command: "cat Package.swift && ls Sources",
            cwd: repoPath,
            source: .agent,
            status: .completed,
            commandActions: [
                .read(command: "cat Package.swift", name: "Package.swift", path: "/repo/Package.swift"),
                .listFiles(command: "ls Sources", path: nil)
            ],
            aggregatedOutput: "Package.swift\nSources\n",
            exitCode: 0,
            durationMs: 42
        ))
    }

    func testFileChangeItemUsesRustThreadItemShape() throws {
        let changes = AppServerFileUpdateChange.converted(from: [
            "Sources/Renamed.swift": .update(
                unifiedDiff: "@@ -1 +1 @@\n-old\n+new\n",
                movePath: "Sources/New.swift"
            ),
            "Sources/Added.swift": .add(content: "let added = true\n"),
            "Sources/Deleted.swift": .delete(content: "let deleted = true\n")
        ])
        let item = AppServerThreadItem.fileChange(
            id: "patch-1",
            changes: changes,
            status: .inProgress
        )

        try XCTAssertJSONObjectEqual(item, [
            "type": "fileChange",
            "id": "patch-1",
            "changes": [
                [
                    "path": "Sources/Added.swift",
                    "kind": ["type": "add"],
                    "diff": "let added = true\n"
                ],
                [
                    "path": "Sources/Deleted.swift",
                    "kind": ["type": "delete"],
                    "diff": "let deleted = true\n"
                ],
                [
                    "path": "Sources/Renamed.swift",
                    "kind": [
                        "type": "update",
                        "movePath": "Sources/New.swift"
                    ],
                    "diff": "@@ -1 +1 @@\n-old\n+new\n\n\nMoved to: Sources/New.swift"
                ]
            ],
            "status": "inProgress"
        ])

        let decoded = try JSONDecoder().decode(AppServerThreadItem.self, from: Data(#"""
        {
          "type": "fileChange",
          "id": "patch-1",
          "changes": [
            {
              "path": "Sources/Updated.swift",
              "kind": {
                "type": "update",
                "movePath": null
              },
              "diff": "@@ -1 +1 @@\n-old\n+new\n"
            }
          ],
          "status": "completed"
        }
        """#.utf8))

        XCTAssertEqual(decoded, .fileChange(
            id: "patch-1",
            changes: [
                AppServerFileUpdateChange(
                    path: "Sources/Updated.swift",
                    kind: .update(movePath: nil),
                    diff: "@@ -1 +1 @@\n-old\n+new\n"
                )
            ],
            status: .completed
        ))
        let missingPatchStatus: PatchApplyStatus? = nil
        XCTAssertEqual(AppServerPatchApplyStatus(missingPatchStatus), .inProgress)
        XCTAssertEqual(AppServerPatchApplyStatus(.failed), .failed)
    }

    func testMcpToolCallItemUsesRustThreadItemShape() throws {
        let completedItem = AppServerThreadItem.mcpToolCall(
            id: "mcp-1",
            server: "filesystem",
            tool: "read_file",
            status: .completed,
            arguments: .object(["path": .string("/tmp/notes.txt")]),
            mcpAppResourceURI: "plugin://filesystem",
            result: AppServerProtocol.McpToolCallResult(
                content: [
                    .object([
                        "type": .string("text"),
                        "text": .string("done")
                    ])
                ],
                structuredContent: nil,
                meta: nil
            ),
            durationMs: 2_000
        )

        try XCTAssertJSONObjectEqual(completedItem, [
            "type": "mcpToolCall",
            "id": "mcp-1",
            "server": "filesystem",
            "tool": "read_file",
            "status": "completed",
            "arguments": ["path": "/tmp/notes.txt"],
            "mcpAppResourceUri": "plugin://filesystem",
            "result": [
                "content": [[
                    "type": "text",
                    "text": "done"
                ]],
                "structuredContent": NSNull(),
                "_meta": NSNull()
            ],
            "error": NSNull(),
            "durationMs": 2_000
        ])

        let inProgressItem = AppServerThreadItem.mcpToolCall(
            id: "mcp-2",
            server: "github",
            tool: "search",
            status: .inProgress,
            arguments: .null
        )
        let encodedInProgress = try JSONObject(inProgressItem)
        XCTAssertNil(encodedInProgress["mcpAppResourceUri"])
        try XCTAssertJSONObjectEqual(inProgressItem, [
            "type": "mcpToolCall",
            "id": "mcp-2",
            "server": "github",
            "tool": "search",
            "status": "inProgress",
            "arguments": NSNull(),
            "result": NSNull(),
            "error": NSNull(),
            "durationMs": NSNull()
        ])

        let decoded = try JSONDecoder().decode(AppServerThreadItem.self, from: Data(#"""
        {
          "type": "mcpToolCall",
          "id": "mcp-3",
          "server": "docs",
          "tool": "lookup",
          "status": "failed",
          "arguments": {},
          "result": null,
          "error": {
            "message": "server disconnected"
          },
          "durationMs": 42
        }
        """#.utf8))

        XCTAssertEqual(decoded, .mcpToolCall(
            id: "mcp-3",
            server: "docs",
            tool: "lookup",
            status: .failed,
            arguments: .object([:]),
            error: AppServerProtocol.McpToolCallError(message: "server disconnected"),
            durationMs: 42
        ))
    }

    func testDynamicToolCallItemUsesRustThreadItemShape() throws {
        let inProgressItem = AppServerThreadItem.dynamicToolCall(
            id: "dynamic-1",
            namespace: nil,
            tool: "lookup",
            arguments: .object(["city": .string("New York")]),
            status: .inProgress
        )

        try XCTAssertJSONObjectEqual(inProgressItem, [
            "type": "dynamicToolCall",
            "id": "dynamic-1",
            "namespace": NSNull(),
            "tool": "lookup",
            "arguments": ["city": "New York"],
            "status": "inProgress",
            "contentItems": NSNull(),
            "success": NSNull(),
            "durationMs": NSNull()
        ])

        let completedItem = AppServerThreadItem.dynamicToolCall(
            id: "dynamic-2",
            namespace: "codex_app",
            tool: "render",
            arguments: .object(["id": .integer(42)]),
            status: .completed,
            contentItems: [
                .text("rendered"),
                .imageURL("https://example.com/render.png")
            ],
            success: true,
            durationMs: 37
        )

        try XCTAssertJSONObjectEqual(completedItem, [
            "type": "dynamicToolCall",
            "id": "dynamic-2",
            "namespace": "codex_app",
            "tool": "render",
            "arguments": ["id": 42],
            "status": "completed",
            "contentItems": [
                [
                    "type": "inputText",
                    "text": "rendered"
                ],
                [
                    "type": "inputImage",
                    "imageUrl": "https://example.com/render.png"
                ]
            ],
            "success": true,
            "durationMs": 37
        ])

        let decoded = try JSONDecoder().decode(AppServerThreadItem.self, from: Data(#"""
        {
          "type": "dynamicToolCall",
          "id": "dynamic-3",
          "namespace": "codex_app",
          "tool": "lookup",
          "arguments": {},
          "status": "failed",
          "contentItems": [],
          "success": false,
          "durationMs": 12
        }
        """#.utf8))

        XCTAssertEqual(decoded, .dynamicToolCall(
            id: "dynamic-3",
            namespace: "codex_app",
            tool: "lookup",
            arguments: .object([:]),
            status: .failed,
            contentItems: [],
            success: false,
            durationMs: 12
        ))
    }

    func testCollabAgentToolCallItemUsesRustThreadItemShape() throws {
        let inProgressItem = AppServerThreadItem.collabAgentToolCall(
            id: "collab-1",
            tool: .wait,
            status: .inProgress,
            senderThreadID: "thread-root",
            receiverThreadIDs: ["thread-child"],
            agentsStates: [
                "thread-child": AppServerCollabAgentState(status: .running)
            ]
        )

        try XCTAssertJSONObjectEqual(inProgressItem, [
            "type": "collabAgentToolCall",
            "id": "collab-1",
            "tool": "wait",
            "status": "inProgress",
            "senderThreadId": "thread-root",
            "receiverThreadIds": ["thread-child"],
            "prompt": NSNull(),
            "model": NSNull(),
            "reasoningEffort": NSNull(),
            "agentsStates": [
                "thread-child": [
                    "status": "running",
                    "message": NSNull()
                ]
            ]
        ])

        let completedItem = AppServerThreadItem.collabAgentToolCall(
            id: "collab-2",
            tool: .spawnAgent,
            status: .completed,
            senderThreadID: "thread-root",
            receiverThreadIDs: ["thread-new"],
            prompt: "Review this change",
            model: "gpt-5.4",
            reasoningEffort: .medium,
            agentsStates: [
                "thread-new": AppServerCollabAgentState(status: .completed, message: "done")
            ]
        )

        try XCTAssertJSONObjectEqual(completedItem, [
            "type": "collabAgentToolCall",
            "id": "collab-2",
            "tool": "spawnAgent",
            "status": "completed",
            "senderThreadId": "thread-root",
            "receiverThreadIds": ["thread-new"],
            "prompt": "Review this change",
            "model": "gpt-5.4",
            "reasoningEffort": "medium",
            "agentsStates": [
                "thread-new": [
                    "status": "completed",
                    "message": "done"
                ]
            ]
        ])

        let decoded = try JSONDecoder().decode(AppServerThreadItem.self, from: Data(#"""
        {
          "type": "collabAgentToolCall",
          "id": "collab-3",
          "tool": "closeAgent",
          "status": "failed",
          "senderThreadId": "thread-root",
          "receiverThreadIds": ["thread-child"],
          "prompt": null,
          "model": null,
          "reasoningEffort": null,
          "agentsStates": {
            "thread-child": {
              "status": "errored",
              "message": "lost connection"
            }
          }
        }
        """#.utf8))

        XCTAssertEqual(decoded, .collabAgentToolCall(
            id: "collab-3",
            tool: .closeAgent,
            status: .failed,
            senderThreadID: "thread-root",
            receiverThreadIDs: ["thread-child"],
            agentsStates: [
                "thread-child": AppServerCollabAgentState(
                    status: .errored,
                    message: "lost connection"
                )
            ]
        ))
    }

    func testCollabAgentStateMapsCoreAgentStatusLikeRustProtocol() {
        XCTAssertEqual(AppServerCollabAgentState(agentStatus: .pendingInit), .init(status: .pendingInit))
        XCTAssertEqual(AppServerCollabAgentState(agentStatus: .running), .init(status: .running))
        XCTAssertEqual(AppServerCollabAgentState(agentStatus: .interrupted), .init(status: .interrupted))
        XCTAssertEqual(AppServerCollabAgentState(agentStatus: .completed(nil)), .init(status: .completed))
        XCTAssertEqual(
            AppServerCollabAgentState(agentStatus: .completed("done")),
            .init(status: .completed, message: "done")
        )
        XCTAssertEqual(
            AppServerCollabAgentState(agentStatus: .errored("boom")),
            .init(status: .errored, message: "boom")
        )
        XCTAssertEqual(AppServerCollabAgentState(agentStatus: .shutdown), .init(status: .shutdown))
        XCTAssertEqual(AppServerCollabAgentState(agentStatus: .notFound), .init(status: .notFound))
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
        try XCTAssertJSONObjectEqual(ThreadLoadedListParams(), [
            "cursor": NSNull(),
            "limit": NSNull()
        ])

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
        try XCTAssertJSONObjectEqual(ThreadListParams(), [
            "cursor": NSNull(),
            "limit": NSNull(),
            "sortKey": NSNull(),
            "sortDirection": NSNull(),
            "modelProviders": NSNull(),
            "sourceKinds": NSNull(),
            "archived": NSNull(),
            "cwd": NSNull(),
            "searchTerm": NSNull()
        ])

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
            "cursor": NSNull(),
            "limit": NSNull(),
            "sortKey": NSNull(),
            "sortDirection": NSNull(),
            "modelProviders": NSNull(),
            "sourceKinds": NSNull(),
            "archived": NSNull(),
            "cwd": "/repo",
            "searchTerm": NSNull()
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

        let decodedManyCwds = try JSONDecoder().decode(
            ThreadListParams.self,
            from: Data(#"{"cwd":["/repo","/other"]}"#.utf8)
        )
        XCTAssertEqual(decodedManyCwds.cwd, .many(["/repo", "/other"]))
        XCTAssertFalse(decodedManyCwds.useStateDBOnly)
    }

    func testThreadListParamsRejectsExplicitNullForRustDefaultedStateDbFlag() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                ThreadListParams.self,
                from: Data(#"{"useStateDbOnly":null}"#.utf8)
            )
        )
    }

    func testThreadLifecycleParamsExperimentalReasonsMatchRustClientRequestInspection() {
        let granular = AskForApproval.granular(
            GranularApprovalConfig(
                sandboxApproval: true,
                rules: false,
                skillApproval: false,
                requestPermissions: true,
                mcpElicitations: false
            )
        )

        XCTAssertEqual(
            ThreadStartParams(approvalPolicy: granular).appServerExperimentalReason,
            "askForApproval.granular"
        )
        XCTAssertEqual(
            ThreadResumeParams(threadID: "thr_123", approvalPolicy: granular).appServerExperimentalReason,
            "askForApproval.granular"
        )
        XCTAssertEqual(
            ThreadForkParams(threadID: "thr_456", approvalPolicy: granular).appServerExperimentalReason,
            "askForApproval.granular"
        )

        XCTAssertEqual(
            ThreadStartParams(
                approvalPolicy: granular,
                permissions: AppServerPermissionProfileSelectionParams.profile(id: "workspace")
            ).appServerExperimentalReason,
            "askForApproval.granular"
        )
        XCTAssertEqual(
            ThreadResumeParams(threadID: "thr_123", history: []).appServerExperimentalReason,
            "thread/resume.history"
        )
        XCTAssertEqual(
            ThreadResumeParams(
                threadID: "thr_123",
                path: "/tmp/session.jsonl",
                approvalPolicy: granular
            ).appServerExperimentalReason,
            "thread/resume.path"
        )
        XCTAssertEqual(
            ThreadForkParams(
                threadID: "thr_456",
                path: "/tmp/session.jsonl",
                approvalPolicy: granular
            ).appServerExperimentalReason,
            "thread/fork.path"
        )
        XCTAssertEqual(
            ThreadStartParams(environments: []).appServerExperimentalReason,
            "thread/start.environments"
        )
        XCTAssertEqual(
            ThreadStartParams(dynamicTools: []).appServerExperimentalReason,
            "thread/start.dynamicTools"
        )
        XCTAssertEqual(
            ThreadStartParams(mockExperimentalField: "test").appServerExperimentalReason,
            "thread/start.mockExperimentalField"
        )
        XCTAssertEqual(
            ThreadStartParams(experimentalRawEvents: true).appServerExperimentalReason,
            "thread/start.experimentalRawEvents"
        )
        XCTAssertEqual(
            ThreadStartParams(persistExtendedHistory: true).appServerExperimentalReason,
            "thread/start.persistFullHistory"
        )
        XCTAssertEqual(
            ThreadResumeParams(threadID: "thr_123", excludeTurns: true).appServerExperimentalReason,
            "thread/resume.excludeTurns"
        )
        XCTAssertEqual(
            ThreadForkParams(threadID: "thr_456", persistExtendedHistory: true).appServerExperimentalReason,
            "thread/fork.persistFullHistory"
        )
        XCTAssertNil(ThreadStartParams(model: "gpt-5").appServerExperimentalReason)
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
            cwd: try AbsolutePath(absolutePath: "/repo"),
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
                            "text": "Ready",
                            "phase": NSNull(),
                            "memoryCitation": NSNull()
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
                        "text": "Ready",
                        "phase": NSNull(),
                        "memoryCitation": NSNull()
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

        let decodedUnknownUnitSource = try JSONDecoder().decode(
            AppServerSessionSource.self,
            from: Data(#""futureDesktop""#.utf8)
        )
        XCTAssertEqual(decodedUnknownUnitSource, .unknown)
    }

    func testAppServerSessionSourceRejectsMultipleExternallyTaggedVariantsLikeRustSerde() {
        XCTAssertThrowsError(try JSONDecoder().decode(
            AppServerSessionSource.self,
            from: Data(#"{"custom":"atlas","subAgent":"review"}"#.utf8)
        )) { error in
            guard case let DecodingError.dataCorrupted(context) = error else {
                return XCTFail("expected dataCorrupted, got \(error)")
            }
            XCTAssertEqual(
                context.debugDescription,
                "Expected externally tagged AppServerSessionSource object with exactly one tag"
            )
        }
    }

    func testThreadDataRejectsRelativeCwdLikeRustAbsolutePathBuf() throws {
        let payload = Data(#"""
        {
          "id": "thread-1",
          "sessionId": "session-1",
          "preview": "Ship parity",
          "ephemeral": false,
          "modelProvider": "openai",
          "createdAt": 900,
          "updatedAt": 1100,
          "status": { "type": "idle" },
          "cwd": "repo",
          "cliVersion": "0.50.0",
          "source": "appServer",
          "turns": []
        }
        """#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(AppServerThread.self, from: payload))
    }

    func testThreadDataRequiresSessionIDLikeRustProtocol() throws {
        let basePayload: [String: Any] = [
            "id": "thread-1",
            "sessionId": "session-1",
            "preview": "Ship parity",
            "ephemeral": false,
            "modelProvider": "openai",
            "createdAt": 900,
            "updatedAt": 1_100,
            "status": ["type": "idle"],
            "cwd": "/repo",
            "cliVersion": "0.50.0",
            "source": "appServer",
            "turns": []
        ]

        var omitted = basePayload
        omitted.removeValue(forKey: "sessionId")
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AppServerThread.self,
                from: try JSONSerialization.data(withJSONObject: omitted)
            )
        )

        var explicitNull = basePayload
        explicitNull["sessionId"] = NSNull()
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AppServerThread.self,
                from: try JSONSerialization.data(withJSONObject: explicitNull)
            )
        )
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
            cwd: try AbsolutePath(absolutePath: "/repo"),
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
                    "type": "workspaceWrite",
                    "writableRoots": [],
                    "networkAccess": false,
                    "excludeTmpdirEnvVar": false,
                    "excludeSlashTmp": false
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
                "type": "readOnly",
                "networkAccess": false
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

    func testThreadLifecycleResponsesDefaultMissingOptionalFieldsLikeRustProtocol() throws {
        let response: [String: Any] = [
            "thread": expectedRuntimeThreadJSON(),
            "model": "gpt-5",
            "modelProvider": "openai",
            "serviceTier": NSNull(),
            "cwd": "/repo",
            "approvalPolicy": "on-failure",
            "approvalsReviewer": "user",
            "sandbox": [
                "type": "dangerFullAccess"
            ],
            "reasoningEffort": NSNull()
        ]
        let data = try JSONSerialization.data(withJSONObject: response)

        let start = try JSONDecoder().decode(ThreadStartResponse.self, from: data)
        XCTAssertEqual(start.instructionSources, [])
        XCTAssertNil(start.permissionProfile)
        XCTAssertNil(start.activePermissionProfile)
        XCTAssertNil(start.reasoningEffort)

        let resume = try JSONDecoder().decode(ThreadResumeResponse.self, from: data)
        XCTAssertEqual(resume.instructionSources, [])
        XCTAssertNil(resume.permissionProfile)
        XCTAssertNil(resume.activePermissionProfile)
        XCTAssertNil(resume.reasoningEffort)

        let fork = try JSONDecoder().decode(ThreadForkResponse.self, from: data)
        XCTAssertEqual(fork.instructionSources, [])
        XCTAssertNil(fork.permissionProfile)
        XCTAssertNil(fork.activePermissionProfile)
        XCTAssertNil(fork.reasoningEffort)
    }

    func testThreadRuntimeResponsesRejectExplicitNullForRustDefaultedInstructionSources() throws {
        let base: [String: Any] = [
            "thread": expectedRuntimeThreadJSON(),
            "model": "gpt-5",
            "modelProvider": "mock_provider",
            "serviceTier": NSNull(),
            "cwd": "/repo",
            "instructionSources": NSNull(),
            "approvalPolicy": "never",
            "approvalsReviewer": "guardian_subagent",
            "sandbox": [
                "type": "workspaceWrite",
                "writableRoots": [],
                "networkAccess": false,
                "excludeTmpdirEnvVar": false,
                "excludeSlashTmp": false
            ],
            "permissionProfile": NSNull(),
            "activePermissionProfile": NSNull(),
            "reasoningEffort": NSNull()
        ]

        func data(_ object: [String: Any]) throws -> Data {
            try JSONSerialization.data(withJSONObject: object)
        }

        XCTAssertThrowsError(try JSONDecoder().decode(ThreadStartResponse.self, from: try data(base)))
        XCTAssertThrowsError(try JSONDecoder().decode(ThreadResumeResponse.self, from: try data(base)))

        XCTAssertThrowsError(try JSONDecoder().decode(ThreadForkResponse.self, from: try data(base)))
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
            "type": "readOnly"
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

    func testItemDeltaNotificationModelsUseRustProtocolShape() throws {
        try XCTAssertJSONObjectEqual(
            PlanDeltaNotification(threadID: "thread-1", turnID: "turn-1", itemID: "plan-1", delta: "- step"),
            [
                "threadId": "thread-1",
                "turnId": "turn-1",
                "itemId": "plan-1",
                "delta": "- step"
            ]
        )
        try XCTAssertJSONObjectEqual(
            ReasoningSummaryTextDeltaNotification(
                threadID: "thread-1",
                turnID: "turn-1",
                itemID: "reasoning-1",
                delta: "summary",
                summaryIndex: 2
            ),
            [
                "threadId": "thread-1",
                "turnId": "turn-1",
                "itemId": "reasoning-1",
                "delta": "summary",
                "summaryIndex": 2
            ]
        )
        try XCTAssertJSONObjectEqual(
            ReasoningSummaryPartAddedNotification(
                threadID: "thread-1",
                turnID: "turn-1",
                itemID: "reasoning-1",
                summaryIndex: 3
            ),
            [
                "threadId": "thread-1",
                "turnId": "turn-1",
                "itemId": "reasoning-1",
                "summaryIndex": 3
            ]
        )
        try XCTAssertJSONObjectEqual(
            ReasoningTextDeltaNotification(
                threadID: "thread-1",
                turnID: "turn-1",
                itemID: "reasoning-1",
                delta: "thinking",
                contentIndex: 4
            ),
            [
                "threadId": "thread-1",
                "turnId": "turn-1",
                "itemId": "reasoning-1",
                "delta": "thinking",
                "contentIndex": 4
            ]
        )
        try XCTAssertJSONObjectEqual(
            TerminalInteractionNotification(
                threadID: "thread-1",
                turnID: "turn-1",
                itemID: "exec-1",
                processID: "process-1",
                stdin: "q\n"
            ),
            [
                "threadId": "thread-1",
                "turnId": "turn-1",
                "itemId": "exec-1",
                "processId": "process-1",
                "stdin": "q\n"
            ]
        )
        try XCTAssertJSONObjectEqual(
            CommandExecutionOutputDeltaNotification(
                threadID: "thread-1",
                turnID: "turn-1",
                itemID: "item-1",
                delta: "\u{fffd}a\n"
            ),
            [
                "threadId": "thread-1",
                "turnId": "turn-1",
                "itemId": "item-1",
                "delta": "\u{fffd}a\n"
            ]
        )
        try XCTAssertJSONObjectEqual(
            FileChangeOutputDeltaNotification(
                threadID: "thread-1",
                turnID: "turn-1",
                itemID: "patch-1",
                delta: "diff"
            ),
            [
                "threadId": "thread-1",
                "turnId": "turn-1",
                "itemId": "patch-1",
                "delta": "diff"
            ]
        )

        let decodedSummaryDelta = try JSONDecoder().decode(
            ReasoningSummaryTextDeltaNotification.self,
            from: Data(#"""
            {
              "threadId": "thread-1",
              "turnId": "turn-1",
              "itemId": "reasoning-1",
              "delta": "summary",
              "summaryIndex": 2
            }
            """#.utf8)
        )
        XCTAssertEqual(decodedSummaryDelta.summaryIndex, 2)
        XCTAssertEqual(decodedSummaryDelta.itemID, "reasoning-1")

        let decodedCommandExecutionOutputDelta = try JSONDecoder().decode(
            CommandExecutionOutputDeltaNotification.self,
            from: Data(#"""
            {
              "threadId": "thread-1",
              "turnId": "turn-1",
              "itemId": "item-1",
              "delta": "\uFFFDa\n"
            }
            """#.utf8)
        )
        XCTAssertEqual(
            decodedCommandExecutionOutputDelta,
            CommandExecutionOutputDeltaNotification(
                threadID: "thread-1",
                turnID: "turn-1",
                itemID: "item-1",
                delta: "\u{fffd}a\n"
            )
        )
    }

    func testItemLifecycleNotificationsUseRustProtocolShape() throws {
        let started = ItemStartedNotification(
            item: .contextCompaction(id: "compact-1"),
            threadID: "thread-1",
            turnID: "turn-1",
            startedAtMilliseconds: 1_700
        )
        let completed = ItemCompletedNotification(
            item: .contextCompaction(id: "compact-1"),
            threadID: "thread-1",
            turnID: "turn-1",
            completedAtMilliseconds: 1_900
        )

        try XCTAssertJSONObjectEqual(started, [
            "item": [
                "type": "contextCompaction",
                "id": "compact-1"
            ],
            "threadId": "thread-1",
            "turnId": "turn-1",
            "startedAtMs": 1_700
        ])
        try XCTAssertJSONObjectEqual(completed, [
            "item": [
                "type": "contextCompaction",
                "id": "compact-1"
            ],
            "threadId": "thread-1",
            "turnId": "turn-1",
            "completedAtMs": 1_900
        ])

        let decoded = try JSONDecoder().decode(ItemCompletedNotification.self, from: Data(#"""
        {
          "item": { "type": "contextCompaction", "id": "compact-1" },
          "threadId": "thread-1",
          "turnId": "turn-1",
          "completedAtMs": 1900
        }
        """#.utf8))
        XCTAssertEqual(decoded, completed)
    }

    func testRawResponseAndAgentDeltaNotificationsUseRustProtocolShape() throws {
        let raw = RawResponseItemCompletedNotification(
            threadID: "thread-1",
            turnID: "turn-1",
            item: .message(
                role: "assistant",
                content: [.outputText(text: "done")],
                phase: .finalAnswer
            )
        )

        try XCTAssertJSONObjectEqual(raw, [
            "threadId": "thread-1",
            "turnId": "turn-1",
            "item": [
                "type": "message",
                "role": "assistant",
                "content": [
                    [
                        "type": "output_text",
                        "text": "done"
                    ]
                ],
                "phase": "final_answer"
            ]
        ])

        let decodedRaw = try JSONDecoder().decode(
            RawResponseItemCompletedNotification.self,
            from: Data(#"""
            {
              "threadId": "thread-1",
              "turnId": "turn-1",
              "item": {
                "type": "message",
                "role": "assistant",
                "content": [
                  { "type": "output_text", "text": "done" }
                ],
                "phase": "final_answer"
              }
            }
            """#.utf8)
        )
        XCTAssertEqual(decodedRaw, raw)

        let delta = AgentMessageDeltaNotification(
            threadID: "thread-1",
            turnID: "turn-1",
            itemID: "msg-1",
            delta: "hel"
        )
        try XCTAssertJSONObjectEqual(delta, [
            "threadId": "thread-1",
            "turnId": "turn-1",
            "itemId": "msg-1",
            "delta": "hel"
        ])

        let decodedDelta = try JSONDecoder().decode(AgentMessageDeltaNotification.self, from: Data(#"""
        {
          "threadId": "thread-1",
          "turnId": "turn-1",
          "itemId": "msg-1",
          "delta": "hel"
        }
        """#.utf8))
        XCTAssertEqual(decodedDelta, delta)
    }

    func testFileChangePatchUpdatedNotificationUsesRustProtocolShape() throws {
        let notification = FileChangePatchUpdatedNotification(
            threadID: "thread-1",
            turnID: "turn-1",
            itemID: "patch-1",
            changes: [
                AppServerFileUpdateChange(
                    path: "Sources/Updated.swift",
                    kind: .update(movePath: nil),
                    diff: "@@ -1 +1 @@\n-old\n+new\n"
                )
            ]
        )

        try XCTAssertJSONObjectEqual(notification, [
            "threadId": "thread-1",
            "turnId": "turn-1",
            "itemId": "patch-1",
            "changes": [
                [
                    "path": "Sources/Updated.swift",
                    "kind": [
                        "type": "update",
                        "movePath": NSNull()
                    ],
                    "diff": "@@ -1 +1 @@\n-old\n+new\n"
                ]
            ]
        ])

        let decoded = try JSONDecoder().decode(
            FileChangePatchUpdatedNotification.self,
            from: Data(#"""
            {
              "threadId": "thread-1",
              "turnId": "turn-1",
              "itemId": "patch-1",
              "changes": [
                {
                  "path": "Sources/Updated.swift",
                  "kind": {
                    "type": "update",
                    "movePath": null
                  },
                  "diff": "@@ -1 +1 @@\n-old\n+new\n"
                }
              ]
            }
            """#.utf8)
        )
        XCTAssertEqual(decoded, notification)
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
            cwd: try AbsolutePath(absolutePath: "/repo"),
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

    func testThreadShellCommandRoundTripsExactRustProtocolFixture() throws {
        let params = ThreadShellCommandParams(
            threadID: "thr_123",
            command: "printf 'hello world\\n'"
        )
        try XCTAssertJSONObjectEqual(params, [
            "threadId": "thr_123",
            "command": "printf 'hello world\\n'"
        ])

        let decoded = try JSONDecoder().decode(
            ThreadShellCommandParams.self,
            from: Data(#"{"threadId":"thr_123","command":"printf 'hello world\\n'"}"#.utf8)
        )
        XCTAssertEqual(decoded, params)

        let response = try JSONDecoder().decode(
            ThreadShellCommandResponse.self,
            from: Data(#"{}"#.utf8)
        )
        XCTAssertEqual(response, ThreadShellCommandResponse())
        try XCTAssertJSONObjectEqual(response, [:])
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
            "threadId": threadID.description,
            "objective": NSNull(),
            "status": NSNull()
        ])
        try XCTAssertJSONObjectEqual(
            ThreadGoalSetParams(threadID: threadID.description, tokenBudget: .clear),
            [
                "threadId": threadID.description,
                "objective": NSNull(),
                "status": NSNull(),
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
            cwd: try AbsolutePath(absolutePath: "/repo"),
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
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                ThreadReadParams.self,
                from: Data(#"{"threadId":"\#(threadID)","includeTurns":null}"#.utf8)
            )
        )

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
        try XCTAssertJSONObjectEqual(
            ThreadTurnsItemsListParams(threadID: "thr_123", turnID: "turn_456"),
            [
                "threadId": "thr_123",
                "turnId": "turn_456",
                "cursor": NSNull(),
                "limit": NSNull(),
                "sortDirection": NSNull()
            ]
        )

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
