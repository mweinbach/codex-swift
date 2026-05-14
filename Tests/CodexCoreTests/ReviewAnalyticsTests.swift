import CodexCore
import XCTest

final class ReviewAnalyticsTests: XCTestCase {
    func testTrackEventsRequestUsesRustUntaggedEventEnvelope() throws {
        var commandReducer = CodexCommandExecutionAnalyticsReducer()
        var collabReducer = CodexCollabAgentToolCallAnalyticsReducer()
        let command = try Self.reduceCommandExecution(
            status: .completed,
            source: .agent,
            reducer: &commandReducer
        )
        let collab = try Self.reduceCollabAgentToolCall(
            tool: .wait,
            status: .completed,
            receiverThreadIDs: ["child-1"],
            model: "gpt-5.5",
            reasoningEffort: .medium,
            agentsStates: ["child-1": AppServerCollabAgentState(status: .completed)],
            reducer: &collabReducer
        )
        let acceptedLine = AcceptedLineFingerprintsEventRequest(eventParams: AcceptedLineFingerprintsEventParams(
            eventType: "codex.accepted_line_fingerprints",
            turnID: "turn-1",
            threadID: "thread-1",
            productSurface: "codex-tui",
            modelSlug: "gpt-5.5",
            completedAt: 123,
            repoHash: "repo-hash",
            acceptedAddedLines: 1,
            acceptedDeletedLines: 0,
            lineFingerprints: [
                AcceptedLineFingerprint(pathHash: String(repeating: "a", count: 40), lineHash: String(repeating: "b", count: 40))
            ]
        ))

        let request = CodexTrackEventsRequest(events: [
            .commandExecution(command),
            .turnEvent(CodexTurnEventRequest(
                eventType: "codex_turn_event",
                eventParams: CodexTurnEventParams(
                    threadID: "thread-1",
                    turnID: "turn-1",
                    appServerClient: Self.analyticsContext.appServerClient,
                    runtime: Self.analyticsContext.runtime,
                    ephemeral: false,
                    threadSource: .user,
                    initializationMode: .new,
                    model: "gpt-5.5",
                    modelProvider: "openai",
                    serviceTier: "default",
                    approvalPolicy: "on-request",
                    approvalsReviewer: "user",
                    sandboxNetworkAccess: false,
                    numInputImages: 0,
                    isFirstTurn: true
                )
            )),
            .turnSteer(CodexTurnSteerEventRequest(
                eventType: "codex_turn_steer",
                eventParams: CodexTurnSteerEventParams(
                    threadID: "thread-1",
                    expectedTurnID: "turn-1",
                    acceptedTurnID: "turn-2",
                    appServerClient: Self.analyticsContext.appServerClient,
                    runtime: Self.analyticsContext.runtime,
                    threadSource: .user,
                    numInputImages: 0,
                    result: .accepted,
                    rejectionReason: nil,
                    createdAt: 124
                )
            )),
            .collabAgentToolCall(collab),
            .acceptedLineFingerprints(acceptedLine)
        ])

        let object = try JSONObject(request)
        let events = try XCTUnwrap(object["events"] as? [[String: Any]])
        XCTAssertEqual(events.compactMap { $0["event_type"] as? String }, [
            "codex_command_execution_event",
            "codex_turn_event",
            "codex_turn_steer",
            "codex_collab_agent_tool_call_event",
            "codex_accepted_line_fingerprints"
        ])
        XCTAssertNotNil(events[0]["event_params"])
        XCTAssertNotNil(events[1]["event_params"])
        XCTAssertNotNil(events[2]["event_params"])
        XCTAssertNotNil(events[3]["event_params"])
        XCTAssertNotNil(events[4]["event_params"])
    }

    func testTrackEventRequestBatchesIsolateAcceptedLineEventsLikeRust() throws {
        var commandReducer = CodexCommandExecutionAnalyticsReducer()
        var collabReducer = CodexCollabAgentToolCallAnalyticsReducer()
        var imageReducer = CodexImageGenerationAnalyticsReducer()
        let acceptedLine = AcceptedLineFingerprintsEventRequest(eventParams: AcceptedLineFingerprintsEventParams(
            eventType: "codex.accepted_line_fingerprints",
            turnID: "turn-1",
            threadID: "thread-1",
            completedAt: 123,
            acceptedAddedLines: 1,
            acceptedDeletedLines: 0,
            lineFingerprints: []
        ))
        let events: [CodexTrackEventRequest] = [
            .commandExecution(try Self.reduceCommandExecution(
                status: .completed,
                source: .agent,
                reducer: &commandReducer
            )),
            .collabAgentToolCall(try Self.reduceCollabAgentToolCall(
                tool: .closeAgent,
                status: .completed,
                receiverThreadIDs: ["child-1"],
                model: nil,
                reasoningEffort: nil,
                agentsStates: ["child-1": AppServerCollabAgentState(status: .completed)],
                reducer: &collabReducer
            )),
            .acceptedLineFingerprints(acceptedLine),
            .imageGeneration(try Self.reduceImageGeneration(status: "completed", reducer: &imageReducer)),
            .acceptedLineFingerprints(acceptedLine)
        ]

        let batches = CodexAnalytics.trackEventRequestBatches(events)

        XCTAssertEqual(batches, [
            [events[0], events[1]],
            [events[2]],
            [events[3]],
            [events[4]]
        ])
    }

    func testURLSessionCodexAnalyticsUploaderPostsChatGPTTokenEventsLikeRust() async throws {
        let temp = try ReviewAnalyticsTemporaryDirectory()
        let accessToken = Self.fakeJWT(authClaims: [
            "chatgpt_account_id": "acct-123",
            "chatgpt_plan_type": "pro"
        ])
        try CodexAuthStorage.saveChatGPTAuthTokens(
            codexHome: temp.url,
            accessToken: accessToken,
            chatGPTAccountID: "acct-123",
            chatGPTPlanType: "pro",
            now: Date()
        )
        var reducer = CodexCommandExecutionAnalyticsReducer()
        let request = CodexTrackEventsRequest(events: [
            .commandExecution(try Self.reduceCommandExecution(
                status: .completed,
                source: .agent,
                reducer: &reducer
            ))
        ])
        let transport = RecordingCodexAnalyticsAPITransport()
        let uploader = URLSessionCodexAnalyticsUploader(
            codexHome: temp.url,
            baseURL: "https://chatgpt.example/backend-api/",
            transport: transport
        )

        try await uploader.upload(request)

        let requests = await transport.executeRequests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].method, .post)
        XCTAssertEqual(
            requests[0].url,
            "https://chatgpt.example/backend-api/codex/analytics-events/events"
        )
        XCTAssertEqual(requests[0].headers["authorization"], "Bearer \(accessToken)")
        XCTAssertEqual(requests[0].headers["ChatGPT-Account-ID"], "acct-123")
        XCTAssertEqual(requests[0].headers["Content-Type"], "application/json")
        XCTAssertEqual(requests[0].timeoutMilliseconds, URLSessionCodexAnalyticsUploader.timeoutMilliseconds)
        XCTAssertEqual(requests[0].body, try CodexAnalytics.jsonValue(request))
    }

    func testURLSessionCodexAnalyticsUploaderSkipsAPIKeyAuthLikeRust() async throws {
        let temp = try ReviewAnalyticsTemporaryDirectory()
        try CodexAuthStorage.loginWithAPIKey(codexHome: temp.url, apiKey: "sk-api")
        var reducer = CodexCommandExecutionAnalyticsReducer()
        let transport = RecordingCodexAnalyticsAPITransport()
        let uploader = URLSessionCodexAnalyticsUploader(
            codexHome: temp.url,
            baseURL: "https://chatgpt.example/backend-api/",
            transport: transport
        )

        try await uploader.upload(CodexTrackEventsRequest(events: [
            .commandExecution(try Self.reduceCommandExecution(
                status: .completed,
                source: .agent,
                reducer: &reducer
            ))
        ]))

        let requests = await transport.executeRequests
        XCTAssertTrue(requests.isEmpty)
    }

    func testImageGenerationAnalyticsReducerEmitsLifecycleEventLikeRust() throws {
        var reducer = CodexImageGenerationAnalyticsReducer()
        let item = AppServerThreadItem.imageGeneration(
            id: "image-1",
            status: "completed",
            revisedPrompt: "a small blue icon",
            result: "generated",
            savedPath: try AbsolutePath(absolutePath: "/repo/icon.png")
        )

        reducer.ingestStarted(ItemStartedNotification(
            item: item,
            threadID: "thread-1",
            turnID: "turn-1",
            startedAtMilliseconds: 6_000
        ))
        let event = try XCTUnwrap(reducer.ingestCompleted(
            ItemCompletedNotification(
                item: item,
                threadID: "thread-1",
                turnID: "turn-1",
                completedAtMilliseconds: 6_240
            ),
            context: Self.analyticsContext
        ))

        try XCTAssertJSONObjectEqual(event, [
            "event_type": "codex_image_generation_event",
            "event_params": [
                "thread_id": "thread-1",
                "turn_id": "turn-1",
                "item_id": "image-1",
                "app_server_client": [
                    "product_client_id": "codex_tui",
                    "client_name": "codex-tui",
                    "client_version": "1.2.3",
                    "rpc_transport": "websocket",
                    "experimental_api_enabled": true
                ],
                "runtime": [
                    "codex_rs_version": "0.99.0",
                    "runtime_os": "macos",
                    "runtime_os_version": "15.3.1",
                    "runtime_arch": "aarch64"
                ],
                "thread_source": "user",
                "subagent_source": nil,
                "parent_thread_id": nil,
                "tool_name": "image_generation",
                "started_at_ms": 6_000,
                "completed_at_ms": 6_240,
                "duration_ms": 240,
                "execution_duration_ms": nil,
                "review_count": 0,
                "guardian_review_count": 0,
                "user_review_count": 0,
                "final_approval_outcome": "unknown",
                "terminal_status": "completed",
                "failure_kind": nil,
                "requested_additional_permissions": false,
                "requested_network_access": false,
                "revised_prompt_present": true,
                "saved_path_present": true
            ]
        ])
    }

    func testImageGenerationAnalyticsReducerMapsRustStatusFallbacks() throws {
        var reducer = CodexImageGenerationAnalyticsReducer()

        let failed = try Self.reduceImageGeneration(status: "failed", reducer: &reducer)
        XCTAssertEqual(failed.eventParams.base.terminalStatus, .failed)
        XCTAssertEqual(failed.eventParams.base.failureKind, .toolError)
        XCTAssertFalse(failed.eventParams.revisedPromptPresent)
        XCTAssertFalse(failed.eventParams.savedPathPresent)

        let error = try Self.reduceImageGeneration(status: "error", reducer: &reducer)
        XCTAssertEqual(error.eventParams.base.terminalStatus, .failed)
        XCTAssertEqual(error.eventParams.base.failureKind, .toolError)

        let unknown = try Self.reduceImageGeneration(status: "queued", reducer: &reducer)
        XCTAssertEqual(unknown.eventParams.base.terminalStatus, .completed)
        XCTAssertNil(unknown.eventParams.base.failureKind)
    }

    func testImageGenerationAnalyticsReducerSuppressesMissingStartAndDoubleCompletionLikeRust() {
        var reducer = CodexImageGenerationAnalyticsReducer()
        let item = AppServerThreadItem.imageGeneration(id: "image-1", status: "completed", result: "generated")
        let completed = ItemCompletedNotification(
            item: item,
            threadID: "thread-1",
            turnID: "turn-1",
            completedAtMilliseconds: 20
        )

        XCTAssertNil(reducer.ingestCompleted(completed, context: Self.analyticsContext))

        reducer.ingestStarted(ItemStartedNotification(
            item: item,
            threadID: "thread-1",
            turnID: "turn-1",
            startedAtMilliseconds: 10
        ))
        XCTAssertNotNil(reducer.ingestCompleted(completed, context: Self.analyticsContext))
        XCTAssertNil(reducer.ingestCompleted(completed, context: Self.analyticsContext))
    }

    func testWebSearchAnalyticsReducerEmitsLifecycleEventLikeRust() throws {
        var reducer = CodexWebSearchAnalyticsReducer()
        let startedItem = AppServerThreadItem.webSearch(
            id: "web-1",
            query: "fallback query",
            action: .search(query: nil, queries: ["swift codex", "rust codex"])
        )

        reducer.ingestStarted(ItemStartedNotification(
            item: startedItem,
            threadID: "thread-1",
            turnID: "turn-1",
            startedAtMilliseconds: 5_000
        ))
        let event = try XCTUnwrap(reducer.ingestCompleted(
            ItemCompletedNotification(
                item: startedItem,
                threadID: "thread-1",
                turnID: "turn-1",
                completedAtMilliseconds: 5_080
            ),
            context: Self.analyticsContext
        ))

        try XCTAssertJSONObjectEqual(event, [
            "event_type": "codex_web_search_event",
            "event_params": [
                "thread_id": "thread-1",
                "turn_id": "turn-1",
                "item_id": "web-1",
                "app_server_client": [
                    "product_client_id": "codex_tui",
                    "client_name": "codex-tui",
                    "client_version": "1.2.3",
                    "rpc_transport": "websocket",
                    "experimental_api_enabled": true
                ],
                "runtime": [
                    "codex_rs_version": "0.99.0",
                    "runtime_os": "macos",
                    "runtime_os_version": "15.3.1",
                    "runtime_arch": "aarch64"
                ],
                "thread_source": "user",
                "subagent_source": nil,
                "parent_thread_id": nil,
                "tool_name": "web_search",
                "started_at_ms": 5_000,
                "completed_at_ms": 5_080,
                "duration_ms": 80,
                "execution_duration_ms": nil,
                "review_count": 0,
                "guardian_review_count": 0,
                "user_review_count": 0,
                "final_approval_outcome": "unknown",
                "terminal_status": "completed",
                "failure_kind": nil,
                "requested_additional_permissions": false,
                "requested_network_access": false,
                "web_search_action": "search",
                "query_present": true,
                "query_count": 2
            ]
        ])
    }

    func testWebSearchAnalyticsReducerMatchesRustQueryCountRules() throws {
        var reducer = CodexWebSearchAnalyticsReducer()

        let openPage = try Self.reduceWebSearch(
            query: "   ",
            action: .openPage(url: "https://example.com"),
            reducer: &reducer
        )
        XCTAssertEqual(openPage.eventParams.webSearchAction, .openPage)
        XCTAssertFalse(openPage.eventParams.queryPresent)
        XCTAssertNil(openPage.eventParams.queryCount)

        let legacyQuery = try Self.reduceWebSearch(query: "swift codex", action: nil, reducer: &reducer)
        XCTAssertNil(legacyQuery.eventParams.webSearchAction)
        XCTAssertTrue(legacyQuery.eventParams.queryPresent)
        XCTAssertEqual(legacyQuery.eventParams.queryCount, 1)

        let searchWithQuery = try Self.reduceWebSearch(
            query: "",
            action: .search(query: "one query", queries: nil),
            reducer: &reducer
        )
        XCTAssertEqual(searchWithQuery.eventParams.webSearchAction, .search)
        XCTAssertFalse(searchWithQuery.eventParams.queryPresent)
        XCTAssertEqual(searchWithQuery.eventParams.queryCount, 1)
    }

    func testWebSearchAnalyticsReducerSuppressesMissingStartAndDoubleCompletionLikeRust() {
        var reducer = CodexWebSearchAnalyticsReducer()
        let item = AppServerThreadItem.webSearch(id: "web-1", query: "swift")
        let completed = ItemCompletedNotification(
            item: item,
            threadID: "thread-1",
            turnID: "turn-1",
            completedAtMilliseconds: 20
        )

        XCTAssertNil(reducer.ingestCompleted(completed, context: Self.analyticsContext))

        reducer.ingestStarted(ItemStartedNotification(
            item: item,
            threadID: "thread-1",
            turnID: "turn-1",
            startedAtMilliseconds: 10
        ))
        XCTAssertNotNil(reducer.ingestCompleted(completed, context: Self.analyticsContext))
        XCTAssertNil(reducer.ingestCompleted(completed, context: Self.analyticsContext))
    }

    func testDynamicToolCallAnalyticsReducerEmitsLifecycleEventLikeRust() throws {
        var reducer = CodexDynamicToolCallAnalyticsReducer()
        let startedItem = AppServerThreadItem.dynamicToolCall(
            id: "dynamic-1",
            namespace: "ui",
            tool: "pick_color",
            arguments: .object(["prompt": .string("accent")]),
            status: .inProgress
        )
        let completedItem = AppServerThreadItem.dynamicToolCall(
            id: "dynamic-1",
            namespace: "ui",
            tool: "pick_color",
            arguments: .object(["prompt": .string("accent")]),
            status: .completed,
            contentItems: [
                .text("blue"),
                .imageURL("https://example.com/swatch.png"),
                .text("navy")
            ],
            success: true,
            durationMs: 75
        )

        reducer.ingestStarted(ItemStartedNotification(
            item: startedItem,
            threadID: "thread-1",
            turnID: "turn-1",
            startedAtMilliseconds: 4_000
        ))
        let event = try XCTUnwrap(reducer.ingestCompleted(
            ItemCompletedNotification(
                item: completedItem,
                threadID: "thread-1",
                turnID: "turn-1",
                completedAtMilliseconds: 4_120
            ),
            context: Self.analyticsContext
        ))

        try XCTAssertJSONObjectEqual(event, [
            "event_type": "codex_dynamic_tool_call_event",
            "event_params": [
                "thread_id": "thread-1",
                "turn_id": "turn-1",
                "item_id": "dynamic-1",
                "app_server_client": [
                    "product_client_id": "codex_tui",
                    "client_name": "codex-tui",
                    "client_version": "1.2.3",
                    "rpc_transport": "websocket",
                    "experimental_api_enabled": true
                ],
                "runtime": [
                    "codex_rs_version": "0.99.0",
                    "runtime_os": "macos",
                    "runtime_os_version": "15.3.1",
                    "runtime_arch": "aarch64"
                ],
                "thread_source": "user",
                "subagent_source": nil,
                "parent_thread_id": nil,
                "tool_name": "pick_color",
                "started_at_ms": 4_000,
                "completed_at_ms": 4_120,
                "duration_ms": 120,
                "execution_duration_ms": 75,
                "review_count": 0,
                "guardian_review_count": 0,
                "user_review_count": 0,
                "final_approval_outcome": "unknown",
                "terminal_status": "completed",
                "failure_kind": nil,
                "requested_additional_permissions": false,
                "requested_network_access": false,
                "dynamic_tool_name": "pick_color",
                "success": true,
                "output_content_item_count": 3,
                "output_text_item_count": 2,
                "output_image_item_count": 1
            ]
        ])
    }

    func testDynamicToolCallAnalyticsReducerMapsFailedAndNilContentLikeRust() throws {
        var reducer = CodexDynamicToolCallAnalyticsReducer()
        let event = try Self.reduceDynamicToolCall(
            status: .failed,
            contentItems: nil,
            success: false,
            reducer: &reducer
        )

        XCTAssertEqual(event.eventParams.base.terminalStatus, .failed)
        XCTAssertEqual(event.eventParams.base.failureKind, .toolError)
        XCTAssertEqual(event.eventParams.dynamicToolName, "lookup")
        XCTAssertEqual(event.eventParams.success, false)
        XCTAssertNil(event.eventParams.outputContentItemCount)
        XCTAssertNil(event.eventParams.outputTextItemCount)
        XCTAssertNil(event.eventParams.outputImageItemCount)
    }

    func testDynamicToolCallAnalyticsReducerSuppressesMissingStartDoubleCompletionAndInProgressLikeRust() {
        var reducer = CodexDynamicToolCallAnalyticsReducer()
        let completedItem = Self.dynamicToolCallItem(status: .completed)
        let inProgressItem = Self.dynamicToolCallItem(status: .inProgress)
        let completed = ItemCompletedNotification(
            item: completedItem,
            threadID: "thread-1",
            turnID: "turn-1",
            completedAtMilliseconds: 20
        )

        XCTAssertNil(reducer.ingestCompleted(completed, context: Self.analyticsContext))

        reducer.ingestStarted(ItemStartedNotification(
            item: completedItem,
            threadID: "thread-1",
            turnID: "turn-1",
            startedAtMilliseconds: 10
        ))
        XCTAssertNotNil(reducer.ingestCompleted(completed, context: Self.analyticsContext))
        XCTAssertNil(reducer.ingestCompleted(completed, context: Self.analyticsContext))

        reducer.ingestStarted(ItemStartedNotification(
            item: inProgressItem,
            threadID: "thread-1",
            turnID: "turn-1",
            startedAtMilliseconds: 10
        ))
        XCTAssertNil(reducer.ingestCompleted(
            ItemCompletedNotification(
                item: inProgressItem,
                threadID: "thread-1",
                turnID: "turn-1",
                completedAtMilliseconds: 20
            ),
            context: Self.analyticsContext
        ))
    }

    func testCollabAgentToolCallAnalyticsReducerEmitsLifecycleEventLikeRust() throws {
        var reducer = CodexCollabAgentToolCallAnalyticsReducer()
        let item = AppServerThreadItem.collabAgentToolCall(
            id: "collab-1",
            tool: .spawnAgent,
            status: .completed,
            senderThreadID: "thread-sender",
            receiverThreadIDs: ["child-1", "child-2", "child-3"],
            prompt: "research the issue",
            model: "gpt-5.5",
            reasoningEffort: .high,
            agentsStates: [
                "child-1": AppServerCollabAgentState(status: .completed),
                "child-2": AppServerCollabAgentState(status: .errored, message: "boom"),
                "child-3": AppServerCollabAgentState(status: .running)
            ]
        )

        reducer.ingestStarted(ItemStartedNotification(
            item: item,
            threadID: "thread-1",
            turnID: "turn-1",
            startedAtMilliseconds: 7_000
        ))
        let event = try XCTUnwrap(reducer.ingestCompleted(
            ItemCompletedNotification(
                item: item,
                threadID: "thread-1",
                turnID: "turn-1",
                completedAtMilliseconds: 7_125
            ),
            context: Self.analyticsContext
        ))

        try XCTAssertJSONObjectEqual(event, [
            "event_type": "codex_collab_agent_tool_call_event",
            "event_params": [
                "thread_id": "thread-1",
                "turn_id": "turn-1",
                "item_id": "collab-1",
                "app_server_client": [
                    "product_client_id": "codex_tui",
                    "client_name": "codex-tui",
                    "client_version": "1.2.3",
                    "rpc_transport": "websocket",
                    "experimental_api_enabled": true
                ],
                "runtime": [
                    "codex_rs_version": "0.99.0",
                    "runtime_os": "macos",
                    "runtime_os_version": "15.3.1",
                    "runtime_arch": "aarch64"
                ],
                "thread_source": "user",
                "subagent_source": nil,
                "parent_thread_id": nil,
                "tool_name": "spawn_agent",
                "started_at_ms": 7_000,
                "completed_at_ms": 7_125,
                "duration_ms": 125,
                "execution_duration_ms": nil,
                "review_count": 0,
                "guardian_review_count": 0,
                "user_review_count": 0,
                "final_approval_outcome": "unknown",
                "terminal_status": "completed",
                "failure_kind": nil,
                "requested_additional_permissions": false,
                "requested_network_access": false,
                "sender_thread_id": "thread-sender",
                "receiver_thread_count": 3,
                "receiver_thread_ids": ["child-1", "child-2", "child-3"],
                "requested_model": "gpt-5.5",
                "requested_reasoning_effort": "high",
                "agent_state_count": 3,
                "completed_agent_count": 1,
                "failed_agent_count": 1
            ]
        ])
    }

    func testCollabAgentToolCallAnalyticsReducerMapsFailedAndToolNamesLikeRust() throws {
        let mappings: [(AppServerCollabAgentTool, String)] = [
            (.spawnAgent, "spawn_agent"),
            (.sendInput, "send_input"),
            (.resumeAgent, "resume_agent"),
            (.wait, "wait_agent"),
            (.closeAgent, "close_agent")
        ]

        for (tool, expectedToolName) in mappings {
            var reducer = CodexCollabAgentToolCallAnalyticsReducer()
            let event = try Self.reduceCollabAgentToolCall(
                tool: tool,
                status: .failed,
                receiverThreadIDs: [],
                model: nil,
                reasoningEffort: nil,
                agentsStates: [
                    "child-1": AppServerCollabAgentState(status: .shutdown),
                    "child-2": AppServerCollabAgentState(status: .notFound)
                ],
                reducer: &reducer
            )

            XCTAssertEqual(event.eventParams.base.toolName, expectedToolName)
            XCTAssertEqual(event.eventParams.base.terminalStatus, .failed)
            XCTAssertEqual(event.eventParams.base.failureKind, .toolError)
            XCTAssertEqual(event.eventParams.receiverThreadCount, 0)
            XCTAssertEqual(event.eventParams.receiverThreadIDs, [])
            XCTAssertNil(event.eventParams.requestedModel)
            XCTAssertNil(event.eventParams.requestedReasoningEffort)
            XCTAssertEqual(event.eventParams.agentStateCount, 2)
            XCTAssertEqual(event.eventParams.completedAgentCount, 0)
            XCTAssertEqual(event.eventParams.failedAgentCount, 2)
        }
    }

    func testCollabAgentToolCallAnalyticsReducerSuppressesMissingStartDoubleCompletionAndInProgressLikeRust() {
        var reducer = CodexCollabAgentToolCallAnalyticsReducer()
        let completedItem = Self.collabAgentToolCallItem(status: .completed)
        let inProgressItem = Self.collabAgentToolCallItem(status: .inProgress)
        let completed = ItemCompletedNotification(
            item: completedItem,
            threadID: "thread-1",
            turnID: "turn-1",
            completedAtMilliseconds: 20
        )

        XCTAssertNil(reducer.ingestCompleted(completed, context: Self.analyticsContext))

        reducer.ingestStarted(ItemStartedNotification(
            item: completedItem,
            threadID: "thread-1",
            turnID: "turn-1",
            startedAtMilliseconds: 10
        ))
        XCTAssertNotNil(reducer.ingestCompleted(completed, context: Self.analyticsContext))
        XCTAssertNil(reducer.ingestCompleted(completed, context: Self.analyticsContext))

        reducer.ingestStarted(ItemStartedNotification(
            item: inProgressItem,
            threadID: "thread-1",
            turnID: "turn-1",
            startedAtMilliseconds: 10
        ))
        XCTAssertNil(reducer.ingestCompleted(
            ItemCompletedNotification(
                item: inProgressItem,
                threadID: "thread-1",
                turnID: "turn-1",
                completedAtMilliseconds: 20
            ),
            context: Self.analyticsContext
        ))
    }

    func testMcpToolCallAnalyticsReducerEmitsLifecycleEventLikeRust() throws {
        var reducer = CodexMcpToolCallAnalyticsReducer()
        let startedItem = AppServerThreadItem.mcpToolCall(
            id: "mcp-1",
            server: "filesystem",
            tool: "read_file",
            status: .inProgress,
            arguments: .object(["path": .string("/repo/README.md")])
        )
        let completedItem = AppServerThreadItem.mcpToolCall(
            id: "mcp-1",
            server: "filesystem",
            tool: "read_file",
            status: .completed,
            arguments: .object(["path": .string("/repo/README.md")]),
            result: AppServerProtocol.McpToolCallResult(
                content: [.object(["type": .string("text"), "text": .string("done")])],
                structuredContent: nil,
                meta: nil
            ),
            durationMs: 150
        )

        reducer.ingestStarted(ItemStartedNotification(
            item: startedItem,
            threadID: "thread-1",
            turnID: "turn-1",
            startedAtMilliseconds: 3_000
        ))
        let event = try XCTUnwrap(reducer.ingestCompleted(
            ItemCompletedNotification(
                item: completedItem,
                threadID: "thread-1",
                turnID: "turn-1",
                completedAtMilliseconds: 3_275
            ),
            context: Self.analyticsContext
        ))

        try XCTAssertJSONObjectEqual(event, [
            "event_type": "codex_mcp_tool_call_event",
            "event_params": [
                "thread_id": "thread-1",
                "turn_id": "turn-1",
                "item_id": "mcp-1",
                "app_server_client": [
                    "product_client_id": "codex_tui",
                    "client_name": "codex-tui",
                    "client_version": "1.2.3",
                    "rpc_transport": "websocket",
                    "experimental_api_enabled": true
                ],
                "runtime": [
                    "codex_rs_version": "0.99.0",
                    "runtime_os": "macos",
                    "runtime_os_version": "15.3.1",
                    "runtime_arch": "aarch64"
                ],
                "thread_source": "user",
                "subagent_source": nil,
                "parent_thread_id": nil,
                "tool_name": "read_file",
                "started_at_ms": 3_000,
                "completed_at_ms": 3_275,
                "duration_ms": 275,
                "execution_duration_ms": 150,
                "review_count": 0,
                "guardian_review_count": 0,
                "user_review_count": 0,
                "final_approval_outcome": "unknown",
                "terminal_status": "completed",
                "failure_kind": nil,
                "requested_additional_permissions": false,
                "requested_network_access": false,
                "mcp_server_name": "filesystem",
                "mcp_tool_name": "read_file",
                "mcp_error_present": false
            ]
        ])
    }

    func testMcpToolCallAnalyticsReducerMapsFailedErrorPresenceLikeRust() throws {
        var reducer = CodexMcpToolCallAnalyticsReducer()
        let event = try Self.reduceMcpToolCall(
            status: .failed,
            error: AppServerProtocol.McpToolCallError(message: "server disconnected"),
            reducer: &reducer
        )

        XCTAssertEqual(event.eventParams.base.terminalStatus, .failed)
        XCTAssertEqual(event.eventParams.base.failureKind, .toolError)
        XCTAssertEqual(event.eventParams.mcpServerName, "docs")
        XCTAssertEqual(event.eventParams.mcpToolName, "lookup")
        XCTAssertTrue(event.eventParams.mcpErrorPresent)
    }

    func testMcpToolCallAnalyticsReducerSuppressesMissingStartDoubleCompletionAndInProgressLikeRust() {
        var reducer = CodexMcpToolCallAnalyticsReducer()
        let completedItem = Self.mcpToolCallItem(status: .completed)
        let inProgressItem = Self.mcpToolCallItem(status: .inProgress)
        let completed = ItemCompletedNotification(
            item: completedItem,
            threadID: "thread-1",
            turnID: "turn-1",
            completedAtMilliseconds: 20
        )

        XCTAssertNil(reducer.ingestCompleted(completed, context: Self.analyticsContext))

        reducer.ingestStarted(ItemStartedNotification(
            item: completedItem,
            threadID: "thread-1",
            turnID: "turn-1",
            startedAtMilliseconds: 10
        ))
        XCTAssertNotNil(reducer.ingestCompleted(completed, context: Self.analyticsContext))
        XCTAssertNil(reducer.ingestCompleted(completed, context: Self.analyticsContext))

        reducer.ingestStarted(ItemStartedNotification(
            item: inProgressItem,
            threadID: "thread-1",
            turnID: "turn-1",
            startedAtMilliseconds: 10
        ))
        XCTAssertNil(reducer.ingestCompleted(
            ItemCompletedNotification(
                item: inProgressItem,
                threadID: "thread-1",
                turnID: "turn-1",
                completedAtMilliseconds: 20
            ),
            context: Self.analyticsContext
        ))
    }

    func testFileChangeAnalyticsReducerEmitsLifecycleEventLikeRust() throws {
        var reducer = CodexFileChangeAnalyticsReducer()
        let startedItem = AppServerThreadItem.fileChange(
            id: "patch-1",
            changes: Self.sampleFileChanges,
            status: .inProgress
        )
        let completedItem = AppServerThreadItem.fileChange(
            id: "patch-1",
            changes: Self.sampleFileChanges,
            status: .completed
        )

        reducer.ingestStarted(ItemStartedNotification(
            item: startedItem,
            threadID: "thread-1",
            turnID: "turn-1",
            startedAtMilliseconds: 2_000
        ))
        let event = try XCTUnwrap(reducer.ingestCompleted(
            ItemCompletedNotification(
                item: completedItem,
                threadID: "thread-1",
                turnID: "turn-1",
                completedAtMilliseconds: 2_333
            ),
            context: Self.analyticsContext
        ))

        try XCTAssertJSONObjectEqual(event, [
            "event_type": "codex_file_change_event",
            "event_params": [
                "thread_id": "thread-1",
                "turn_id": "turn-1",
                "item_id": "patch-1",
                "app_server_client": [
                    "product_client_id": "codex_tui",
                    "client_name": "codex-tui",
                    "client_version": "1.2.3",
                    "rpc_transport": "websocket",
                    "experimental_api_enabled": true
                ],
                "runtime": [
                    "codex_rs_version": "0.99.0",
                    "runtime_os": "macos",
                    "runtime_os_version": "15.3.1",
                    "runtime_arch": "aarch64"
                ],
                "thread_source": "user",
                "subagent_source": nil,
                "parent_thread_id": nil,
                "tool_name": "apply_patch",
                "started_at_ms": 2_000,
                "completed_at_ms": 2_333,
                "duration_ms": 333,
                "execution_duration_ms": nil,
                "review_count": 0,
                "guardian_review_count": 0,
                "user_review_count": 0,
                "final_approval_outcome": "unknown",
                "terminal_status": "completed",
                "failure_kind": nil,
                "requested_additional_permissions": false,
                "requested_network_access": false,
                "file_change_count": 4,
                "file_add_count": 1,
                "file_update_count": 1,
                "file_delete_count": 1,
                "file_move_count": 1
            ]
        ])
    }

    func testFileChangeAnalyticsReducerSuppressesMissingStartDoubleCompletionAndInProgressLikeRust() {
        var reducer = CodexFileChangeAnalyticsReducer()
        let completedItem = AppServerThreadItem.fileChange(
            id: "patch-1",
            changes: Self.sampleFileChanges,
            status: .completed
        )
        let inProgressItem = AppServerThreadItem.fileChange(
            id: "patch-2",
            changes: Self.sampleFileChanges,
            status: .inProgress
        )
        let completed = ItemCompletedNotification(
            item: completedItem,
            threadID: "thread-1",
            turnID: "turn-1",
            completedAtMilliseconds: 20
        )

        XCTAssertNil(reducer.ingestCompleted(completed, context: Self.analyticsContext))

        reducer.ingestStarted(ItemStartedNotification(
            item: completedItem,
            threadID: "thread-1",
            turnID: "turn-1",
            startedAtMilliseconds: 10
        ))
        XCTAssertNotNil(reducer.ingestCompleted(completed, context: Self.analyticsContext))
        XCTAssertNil(reducer.ingestCompleted(completed, context: Self.analyticsContext))

        reducer.ingestStarted(ItemStartedNotification(
            item: inProgressItem,
            threadID: "thread-1",
            turnID: "turn-1",
            startedAtMilliseconds: 10
        ))
        XCTAssertNil(reducer.ingestCompleted(
            ItemCompletedNotification(
                item: inProgressItem,
                threadID: "thread-1",
                turnID: "turn-1",
                completedAtMilliseconds: 20
            ),
            context: Self.analyticsContext
        ))
    }

    func testFileChangeAnalyticsReducerMapsFailureAndDeclinedStatusesLikeRust() throws {
        var reducer = CodexFileChangeAnalyticsReducer()

        let failed = try Self.reduceFileChange(status: .failed, reducer: &reducer)
        XCTAssertEqual(failed.eventParams.base.terminalStatus, .failed)
        XCTAssertEqual(failed.eventParams.base.failureKind, .toolError)

        let declined = try Self.reduceFileChange(status: .declined, reducer: &reducer)
        XCTAssertEqual(declined.eventParams.base.terminalStatus, .rejected)
        XCTAssertEqual(declined.eventParams.base.failureKind, .approvalDenied)
    }

    func testCommandExecutionAnalyticsReducerEmitsLifecycleEventLikeRust() throws {
        var reducer = CodexCommandExecutionAnalyticsReducer()
        let startedItem = AppServerThreadItem.commandExecution(
            id: "exec-1",
            command: "cat Package.swift && rg TODO",
            cwd: try AbsolutePath(absolutePath: "/repo"),
            source: .unifiedExecStartup,
            status: .inProgress,
            commandActions: [
                .read(command: "cat Package.swift", name: "Package.swift", path: "/repo/Package.swift"),
                .search(command: "rg TODO", query: "TODO", path: "/repo")
            ]
        )
        let completedItem = AppServerThreadItem.commandExecution(
            id: "exec-1",
            command: "cat Package.swift && rg TODO",
            cwd: try AbsolutePath(absolutePath: "/repo"),
            source: .unifiedExecStartup,
            status: .completed,
            commandActions: [
                .read(command: "cat Package.swift", name: "Package.swift", path: "/repo/Package.swift"),
                .search(command: "rg TODO", query: "TODO", path: "/repo")
            ],
            aggregatedOutput: "package\nmatch\n",
            exitCode: 0,
            durationMs: 120
        )

        reducer.ingestStarted(ItemStartedNotification(
            item: startedItem,
            threadID: "thread-1",
            turnID: "turn-1",
            startedAtMilliseconds: 1_000
        ))
        let event = try XCTUnwrap(reducer.ingestCompleted(
            ItemCompletedNotification(
                item: completedItem,
                threadID: "thread-1",
                turnID: "turn-1",
                completedAtMilliseconds: 1_250
            ),
            context: Self.analyticsContext
        ))

        try XCTAssertJSONObjectEqual(event, [
            "event_type": "codex_command_execution_event",
            "event_params": [
                "thread_id": "thread-1",
                "turn_id": "turn-1",
                "item_id": "exec-1",
                "app_server_client": [
                    "product_client_id": "codex_tui",
                    "client_name": "codex-tui",
                    "client_version": "1.2.3",
                    "rpc_transport": "websocket",
                    "experimental_api_enabled": true
                ],
                "runtime": [
                    "codex_rs_version": "0.99.0",
                    "runtime_os": "macos",
                    "runtime_os_version": "15.3.1",
                    "runtime_arch": "aarch64"
                ],
                "thread_source": "user",
                "subagent_source": nil,
                "parent_thread_id": nil,
                "tool_name": "unified_exec",
                "started_at_ms": 1_000,
                "completed_at_ms": 1_250,
                "duration_ms": 250,
                "execution_duration_ms": 120,
                "review_count": 0,
                "guardian_review_count": 0,
                "user_review_count": 0,
                "final_approval_outcome": "unknown",
                "terminal_status": "completed",
                "failure_kind": nil,
                "requested_additional_permissions": false,
                "requested_network_access": false,
                "command_execution_source": "unified_exec_startup",
                "exit_code": 0,
                "command_total_action_count": 2,
                "command_read_action_count": 1,
                "command_list_files_action_count": 0,
                "command_search_action_count": 1,
                "command_unknown_action_count": 0
            ]
        ])
    }

    func testCommandExecutionAnalyticsReducerSuppressesMissingStartAndDoubleCompletionLikeRust() throws {
        var reducer = CodexCommandExecutionAnalyticsReducer()
        let item = AppServerThreadItem.commandExecution(
            id: "exec-1",
            command: "false",
            cwd: try AbsolutePath(absolutePath: "/repo"),
            source: .agent,
            status: .failed,
            commandActions: [.unknown(command: "false")],
            exitCode: 1,
            durationMs: 10
        )
        let completed = ItemCompletedNotification(
            item: item,
            threadID: "thread-1",
            turnID: "turn-1",
            completedAtMilliseconds: 20
        )

        XCTAssertNil(reducer.ingestCompleted(completed, context: Self.analyticsContext))

        reducer.ingestStarted(ItemStartedNotification(
            item: item,
            threadID: "thread-1",
            turnID: "turn-1",
            startedAtMilliseconds: 10
        ))
        let firstEvent = reducer.ingestCompleted(completed, context: Self.analyticsContext)
        XCTAssertNotNil(firstEvent)
        XCTAssertNil(reducer.ingestCompleted(completed, context: Self.analyticsContext))
    }

    func testCommandExecutionAnalyticsReducerMapsFailureAndDeclinedStatusesLikeRust() throws {
        var reducer = CodexCommandExecutionAnalyticsReducer()

        let failed = try Self.reduceCommandExecution(status: .failed, source: .agent, reducer: &reducer)
        XCTAssertEqual(failed.eventParams.base.toolName, "shell")
        XCTAssertEqual(failed.eventParams.base.terminalStatus, .failed)
        XCTAssertEqual(failed.eventParams.base.failureKind, .toolError)
        XCTAssertEqual(failed.eventParams.commandExecutionSource, .agent)

        let declined = try Self.reduceCommandExecution(status: .declined, source: .userShell, reducer: &reducer)
        XCTAssertEqual(declined.eventParams.base.toolName, "user_shell")
        XCTAssertEqual(declined.eventParams.base.terminalStatus, .rejected)
        XCTAssertEqual(declined.eventParams.base.failureKind, .approvalDenied)
        XCTAssertEqual(declined.eventParams.commandExecutionSource, .userShell)
    }

    func testCommandExecutionAnalyticsReducerSkipsInProgressCompletionLikeRust() throws {
        var reducer = CodexCommandExecutionAnalyticsReducer()
        let item = AppServerThreadItem.commandExecution(
            id: "exec-1",
            command: "sleep 1",
            cwd: try AbsolutePath(absolutePath: "/repo"),
            source: .unifiedExecInteraction,
            status: .inProgress,
            commandActions: []
        )

        reducer.ingestStarted(ItemStartedNotification(
            item: item,
            threadID: "thread-1",
            turnID: "turn-1",
            startedAtMilliseconds: 10
        ))

        XCTAssertNil(reducer.ingestCompleted(
            ItemCompletedNotification(
                item: item,
                threadID: "thread-1",
                turnID: "turn-1",
                completedAtMilliseconds: 20
            ),
            context: Self.analyticsContext
        ))
    }

    func testCodexCompactionEventRequestUsesRustWireShape() throws {
        let event = CodexCompactionEventRequest(
            eventType: "codex_compaction_event",
            eventParams: CodexCompactionEventParams(
                threadID: "thread-1",
                turnID: "turn-1",
                appServerClient: CodexAppServerClientMetadata(
                    productClientID: "codex_tui",
                    clientName: "codex-tui",
                    clientVersion: "1.2.3",
                    rpcTransport: .websocket,
                    experimentalAPIEnabled: true
                ),
                runtime: CodexRuntimeMetadata(
                    codexRSVersion: "0.99.0",
                    runtimeOS: "macos",
                    runtimeOSVersion: "15.3.1",
                    runtimeArch: "aarch64"
                ),
                threadSource: .user,
                subagentSource: nil,
                parentThreadID: nil,
                trigger: .auto,
                reason: .contextLimit,
                implementation: .responsesCompact,
                phase: .midTurn,
                strategy: .memento,
                status: .completed,
                error: nil,
                activeContextTokensBefore: 120_000,
                activeContextTokensAfter: 18_000,
                startedAt: 100,
                completedAt: 106,
                durationMilliseconds: 6_543
            )
        )

        try XCTAssertJSONObjectEqual(event, [
            "event_type": "codex_compaction_event",
            "event_params": [
                "thread_id": "thread-1",
                "turn_id": "turn-1",
                "app_server_client": [
                    "product_client_id": "codex_tui",
                    "client_name": "codex-tui",
                    "client_version": "1.2.3",
                    "rpc_transport": "websocket",
                    "experimental_api_enabled": true
                ],
                "runtime": [
                    "codex_rs_version": "0.99.0",
                    "runtime_os": "macos",
                    "runtime_os_version": "15.3.1",
                    "runtime_arch": "aarch64"
                ],
                "thread_source": "user",
                "subagent_source": nil,
                "parent_thread_id": nil,
                "trigger": "auto",
                "reason": "context_limit",
                "implementation": "responses_compact",
                "phase": "mid_turn",
                "strategy": "memento",
                "status": "completed",
                "error": nil,
                "active_context_tokens_before": 120_000,
                "active_context_tokens_after": 18_000,
                "started_at": 100,
                "completed_at": 106,
                "duration_ms": 6_543
            ]
        ])
    }

    func testCompactionAnalyticsReducerIngestsCustomFactLikeRust() throws {
        let reducer = CodexCompactionAnalyticsReducer()
        let event = reducer.ingest(
            CodexCompactionAnalyticsFact(
                threadID: "thread-1",
                turnID: "turn-compact",
                trigger: .manual,
                reason: .userRequested,
                implementation: .responses,
                phase: .standaloneTurn,
                strategy: .memento,
                status: .failed,
                error: "context limit exceeded",
                activeContextTokensBefore: 131_000,
                activeContextTokensAfter: 131_000,
                startedAt: 100,
                completedAt: 101,
                durationMilliseconds: 1_200
            ),
            context: CodexCompactionAnalyticsContext(
                appServerClient: CodexAppServerClientMetadata(
                    productClientID: "codex_tui",
                    clientName: "codex-tui",
                    clientVersion: "1.0.0",
                    rpcTransport: .websocket,
                    experimentalAPIEnabled: false
                ),
                runtime: CodexRuntimeMetadata(
                    codexRSVersion: "0.99.0",
                    runtimeOS: "macos",
                    runtimeOSVersion: "15.3.1",
                    runtimeArch: "aarch64"
                ),
                threadSource: .subagent,
                subagentSource: "thread_spawn",
                parentThreadID: "22222222-2222-2222-2222-222222222222"
            )
        )

        try XCTAssertJSONObjectEqual(event, [
            "event_type": "codex_compaction_event",
            "event_params": [
                "thread_id": "thread-1",
                "turn_id": "turn-compact",
                "app_server_client": [
                    "product_client_id": "codex_tui",
                    "client_name": "codex-tui",
                    "client_version": "1.0.0",
                    "rpc_transport": "websocket",
                    "experimental_api_enabled": false
                ],
                "runtime": [
                    "codex_rs_version": "0.99.0",
                    "runtime_os": "macos",
                    "runtime_os_version": "15.3.1",
                    "runtime_arch": "aarch64"
                ],
                "thread_source": "subagent",
                "subagent_source": "thread_spawn",
                "parent_thread_id": "22222222-2222-2222-2222-222222222222",
                "trigger": "manual",
                "reason": "user_requested",
                "implementation": "responses",
                "phase": "standalone_turn",
                "strategy": "memento",
                "status": "failed",
                "error": "context limit exceeded",
                "active_context_tokens_before": 131_000,
                "active_context_tokens_after": 131_000,
                "started_at": 100,
                "completed_at": 101,
                "duration_ms": 1_200
            ]
        ])
    }

    func testCodexAnalyticsClientUploadsCompactionEventLikeRust() async throws {
        let uploader = RecordingCodexAnalyticsUploader()
        let client = CodexToolItemAnalyticsClient(uploader: uploader)

        await client.trackCompaction(
            CodexCompactionAnalyticsFact(
                threadID: "thread-1",
                turnID: "turn-compact",
                trigger: .auto,
                reason: .contextLimit,
                implementation: .responsesCompact,
                phase: .midTurn,
                strategy: .prefixCompaction,
                status: .completed,
                activeContextTokensBefore: 120_000,
                activeContextTokensAfter: 18_000,
                startedAt: 20,
                completedAt: 40,
                durationMilliseconds: 20
            ),
            context: Self.analyticsContext
        )

        let requests = await uploader.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].events.count, 1)
        guard case let .compaction(event) = requests[0].events[0] else {
            return XCTFail("expected compaction analytics event")
        }
        XCTAssertEqual(event.eventType, "codex_compaction_event")
        XCTAssertEqual(event.eventParams.threadID, "thread-1")
        XCTAssertEqual(event.eventParams.threadSource, .user)
        XCTAssertEqual(event.eventParams.status, .completed)
    }

    func testTurnAnalyticsReducerIngestsCompletedTurnLikeRust() throws {
        let event = CodexTurnAnalyticsReducer().ingest(
            CodexTurnAnalyticsFact(
                threadID: "thread-turn",
                turnID: "turn-complete",
                submissionType: .queued,
                ephemeral: false,
                threadSource: .subagent,
                initializationMode: .resumed,
                subagentSource: "thread_spawn",
                parentThreadID: "parent-thread",
                model: "gpt-5.5",
                modelProvider: "openai",
                sandboxPolicy: "workspace_write",
                reasoningEffort: "medium",
                reasoningSummary: "auto",
                serviceTier: "priority",
                approvalPolicy: "on-request",
                approvalsReviewer: "guardian_subagent",
                sandboxNetworkAccess: true,
                collaborationMode: "plan",
                personality: "friendly",
                numInputImages: 2,
                isFirstTurn: false,
                status: .completed,
                steerCount: 3,
                tokenUsage: TokenUsage(
                    inputTokens: 100,
                    cachedInputTokens: 40,
                    outputTokens: 30,
                    reasoningOutputTokens: 10,
                    totalTokens: 130
                ),
                durationMilliseconds: 1_234,
                startedAt: 100,
                completedAt: 105
            ),
            context: Self.analyticsContext
        )

        try XCTAssertJSONObjectEqual(event, [
            "event_type": "codex_turn_event",
            "event_params": [
                "thread_id": "thread-turn",
                "turn_id": "turn-complete",
                "submission_type": "queued",
                "app_server_client": Self.analyticsContextAppServerClientJSON(),
                "runtime": Self.analyticsContextRuntimeJSON(),
                "ephemeral": false,
                "thread_source": "subagent",
                "initialization_mode": "resumed",
                "subagent_source": "thread_spawn",
                "parent_thread_id": "parent-thread",
                "model": "gpt-5.5",
                "model_provider": "openai",
                "sandbox_policy": "workspace_write",
                "reasoning_effort": "medium",
                "reasoning_summary": "auto",
                "service_tier": "priority",
                "approval_policy": "on-request",
                "approvals_reviewer": "guardian_subagent",
                "sandbox_network_access": true,
                "collaboration_mode": "plan",
                "personality": "friendly",
                "num_input_images": 2,
                "is_first_turn": false,
                "status": "completed",
                "turn_error": nil,
                "steer_count": 3,
                "total_tool_call_count": nil,
                "shell_command_count": nil,
                "file_change_count": nil,
                "mcp_tool_call_count": nil,
                "dynamic_tool_call_count": nil,
                "subagent_tool_call_count": nil,
                "web_search_count": nil,
                "image_generation_count": nil,
                "input_tokens": 100,
                "cached_input_tokens": 40,
                "output_tokens": 30,
                "reasoning_output_tokens": 10,
                "total_tokens": 130,
                "duration_ms": 1_234,
                "started_at": 100,
                "completed_at": 105
            ]
        ])
    }

    func testTurnAnalyticsReducerPreservesRustNullFieldsAndErrorInfo() throws {
        let event = CodexTurnAnalyticsReducer().ingest(
            CodexTurnAnalyticsFact(
                threadID: "thread-turn",
                turnID: "turn-failed",
                ephemeral: true,
                initializationMode: .new,
                modelProvider: "openai",
                approvalPolicy: "never",
                approvalsReviewer: "user",
                sandboxNetworkAccess: false,
                numInputImages: 0,
                isFirstTurn: true,
                status: .failed,
                turnError: .contextWindowExceeded,
                completedAt: 900
            ),
            context: Self.analyticsContext
        )

        try XCTAssertJSONObjectEqual(event, [
            "event_type": "codex_turn_event",
            "event_params": [
                "thread_id": "thread-turn",
                "turn_id": "turn-failed",
                "submission_type": nil,
                "app_server_client": Self.analyticsContextAppServerClientJSON(),
                "runtime": Self.analyticsContextRuntimeJSON(),
                "ephemeral": true,
                "thread_source": nil,
                "initialization_mode": "new",
                "subagent_source": nil,
                "parent_thread_id": nil,
                "model": nil,
                "model_provider": "openai",
                "sandbox_policy": nil,
                "reasoning_effort": nil,
                "reasoning_summary": nil,
                "service_tier": "default",
                "approval_policy": "never",
                "approvals_reviewer": "user",
                "sandbox_network_access": false,
                "collaboration_mode": nil,
                "personality": nil,
                "num_input_images": 0,
                "is_first_turn": true,
                "status": "failed",
                "turn_error": "context_window_exceeded",
                "steer_count": nil,
                "total_tool_call_count": nil,
                "shell_command_count": nil,
                "file_change_count": nil,
                "mcp_tool_call_count": nil,
                "dynamic_tool_call_count": nil,
                "subagent_tool_call_count": nil,
                "web_search_count": nil,
                "image_generation_count": nil,
                "input_tokens": nil,
                "cached_input_tokens": nil,
                "output_tokens": nil,
                "reasoning_output_tokens": nil,
                "total_tokens": nil,
                "duration_ms": nil,
                "started_at": nil,
                "completed_at": 900
            ]
        ])
    }

    func testCodexAnalyticsClientUploadsTurnEventLikeRust() async throws {
        let uploader = RecordingCodexAnalyticsUploader()
        let client = CodexToolItemAnalyticsClient(uploader: uploader)

        await client.trackTurn(
            CodexTurnAnalyticsFact(
                threadID: "thread-turn",
                turnID: "turn-upload",
                ephemeral: false,
                threadSource: .user,
                initializationMode: .new,
                model: "gpt-5",
                modelProvider: "openai",
                sandboxPolicy: "read_only",
                serviceTier: "default",
                approvalPolicy: "on-failure",
                approvalsReviewer: "user",
                sandboxNetworkAccess: false,
                collaborationMode: "default",
                numInputImages: 0,
                isFirstTurn: true,
                status: .interrupted,
                steerCount: 0,
                completedAt: 222
            ),
            context: Self.analyticsContext
        )

        let requests = await uploader.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].events.count, 1)
        guard case let .turnEvent(event) = requests[0].events[0] else {
            return XCTFail("expected turn analytics event")
        }
        XCTAssertEqual(event.eventType, "codex_turn_event")
        XCTAssertEqual(event.eventParams.threadID, "thread-turn")
        XCTAssertEqual(event.eventParams.status, .interrupted)
    }

    func testTurnSteerAnalyticsReducerIngestsCustomFactLikeRust() throws {
        let reducer = CodexTurnSteerAnalyticsReducer()
        let event = reducer.ingest(
            CodexTurnSteerAnalyticsFact(
                threadID: "thread-steer",
                expectedTurnID: "turn-expected",
                acceptedTurnID: nil,
                numInputImages: 2,
                result: .rejected,
                rejectionReason: .expectedTurnMismatch,
                createdAt: 123
            ),
            context: CodexTurnSteerAnalyticsContext(
                appServerClient: CodexAppServerClientMetadata(
                    productClientID: "codex_tui",
                    clientName: "codex-tui",
                    clientVersion: "1.0.0",
                    rpcTransport: .websocket,
                    experimentalAPIEnabled: true
                ),
                runtime: CodexRuntimeMetadata(
                    codexRSVersion: "0.99.0",
                    runtimeOS: "macos",
                    runtimeOSVersion: "15.3.1",
                    runtimeArch: "aarch64"
                ),
                threadSource: .subagent,
                subagentSource: "thread_spawn",
                parentThreadID: "parent-thread"
            )
        )

        try XCTAssertJSONObjectEqual(event, [
            "event_type": "codex_turn_steer",
            "event_params": [
                "thread_id": "thread-steer",
                "expected_turn_id": "turn-expected",
                "accepted_turn_id": nil,
                "app_server_client": [
                    "product_client_id": "codex_tui",
                    "client_name": "codex-tui",
                    "client_version": "1.0.0",
                    "rpc_transport": "websocket",
                    "experimental_api_enabled": true
                ],
                "runtime": [
                    "codex_rs_version": "0.99.0",
                    "runtime_os": "macos",
                    "runtime_os_version": "15.3.1",
                    "runtime_arch": "aarch64"
                ],
                "thread_source": "subagent",
                "subagent_source": "thread_spawn",
                "parent_thread_id": "parent-thread",
                "num_input_images": 2,
                "result": "rejected",
                "rejection_reason": "expected_turn_mismatch",
                "created_at": 123
            ]
        ])
    }

    func testTurnSteerAnalyticsAcceptedEventPreservesNullRejectionReasonLikeRust() throws {
        let event = CodexTurnSteerAnalyticsReducer().ingest(
            CodexTurnSteerAnalyticsFact(
                threadID: "thread-steer",
                expectedTurnID: nil,
                acceptedTurnID: "turn-accepted",
                numInputImages: 0,
                result: .accepted,
                rejectionReason: nil,
                createdAt: 456
            ),
            context: Self.analyticsContext
        )

        try XCTAssertJSONObjectEqual(event, [
            "event_type": "codex_turn_steer",
            "event_params": [
                "thread_id": "thread-steer",
                "expected_turn_id": nil,
                "accepted_turn_id": "turn-accepted",
                "app_server_client": Self.analyticsContextAppServerClientJSON(),
                "runtime": Self.analyticsContextRuntimeJSON(),
                "thread_source": "user",
                "subagent_source": nil,
                "parent_thread_id": nil,
                "num_input_images": 0,
                "result": "accepted",
                "rejection_reason": nil,
                "created_at": 456
            ]
        ])
    }

    func testCodexAnalyticsClientUploadsTurnSteerEventLikeRust() async throws {
        let uploader = RecordingCodexAnalyticsUploader()
        let client = CodexToolItemAnalyticsClient(uploader: uploader)

        await client.trackTurnSteer(
            CodexTurnSteerAnalyticsFact(
                threadID: "thread-steer",
                expectedTurnID: "turn-old",
                acceptedTurnID: nil,
                numInputImages: 1,
                result: .rejected,
                rejectionReason: .inputTooLarge,
                createdAt: 789
            ),
            context: Self.analyticsContext
        )

        let requests = await uploader.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].events.count, 1)
        guard case let .turnSteer(event) = requests[0].events[0] else {
            return XCTFail("expected turn steer analytics event")
        }
        XCTAssertEqual(event.eventType, "codex_turn_steer")
        XCTAssertEqual(event.eventParams.threadID, "thread-steer")
        XCTAssertEqual(event.eventParams.result, .rejected)
        XCTAssertEqual(event.eventParams.rejectionReason, .inputTooLarge)
    }

    func testGuardianReviewAnalyticsReducerIngestsCustomFactLikeRust() throws {
        let reducer = CodexGuardianReviewAnalyticsReducer()
        let event = reducer.ingest(
            CodexGuardianReviewAnalyticsFact(
                threadID: "thread-guardian",
                turnID: "turn-guardian",
                reviewID: "review-guardian",
                targetItemID: nil,
                approvalRequestSource: .delegatedSubagent,
                reviewedAction: .networkAccess(protocol: .https, port: 443),
                reviewedActionTruncated: false,
                decision: .denied,
                terminalStatus: .timedOut,
                failureReason: .timeout,
                reviewTimeoutMilliseconds: 90_000,
                completionLatencyMilliseconds: 90_000,
                startedAt: 100,
                completedAt: 190
            ),
            context: CodexGuardianReviewAnalyticsContext(
                appServerClient: CodexAppServerClientMetadata(
                    productClientID: "codex_tui",
                    clientName: "codex-tui",
                    clientVersion: "1.0.0",
                    rpcTransport: .websocket,
                    experimentalAPIEnabled: false
                ),
                runtime: CodexRuntimeMetadata(
                    codexRSVersion: "0.1.0",
                    runtimeOS: "macos",
                    runtimeOSVersion: "15.3.1",
                    runtimeArch: "aarch64"
                )
            )
        )

        try XCTAssertJSONObjectEqual(event, [
            "event_type": "codex_guardian_review",
            "event_params": [
                "app_server_client": [
                    "product_client_id": "codex_tui",
                    "client_name": "codex-tui",
                    "client_version": "1.0.0",
                    "rpc_transport": "websocket",
                    "experimental_api_enabled": false
                ],
                "runtime": [
                    "codex_rs_version": "0.1.0",
                    "runtime_os": "macos",
                    "runtime_os_version": "15.3.1",
                    "runtime_arch": "aarch64"
                ],
                "thread_id": "thread-guardian",
                "turn_id": "turn-guardian",
                "review_id": "review-guardian",
                "target_item_id": nil,
                "approval_request_source": "delegated_subagent",
                "reviewed_action": [
                    "type": "network_access",
                    "protocol": "https",
                    "port": 443
                ],
                "reviewed_action_truncated": false,
                "decision": "denied",
                "terminal_status": "timed_out",
                "failure_reason": "timeout",
                "risk_level": nil,
                "user_authorization": nil,
                "outcome": nil,
                "guardian_thread_id": nil,
                "guardian_session_kind": nil,
                "guardian_model": nil,
                "guardian_reasoning_effort": nil,
                "had_prior_review_context": nil,
                "review_timeout_ms": 90_000,
                "tool_call_count": nil,
                "time_to_first_token_ms": nil,
                "completion_latency_ms": 90_000,
                "started_at": 100,
                "completed_at": 190,
                "input_tokens": nil,
                "cached_input_tokens": nil,
                "output_tokens": nil,
                "reasoning_output_tokens": nil,
                "total_tokens": nil
            ]
        ])
    }

    func testCodexAnalyticsClientUploadsGuardianReviewEventLikeRust() async throws {
        let uploader = RecordingCodexAnalyticsUploader()
        let client = CodexToolItemAnalyticsClient(uploader: uploader)

        await client.trackGuardianReview(
            CodexGuardianReviewAnalyticsFact(
                threadID: "thread-guardian",
                turnID: "turn-guardian",
                reviewID: "review-guardian",
                approvalRequestSource: .mainTurn,
                reviewedAction: .applyPatch,
                reviewedActionTruncated: false,
                decision: .approved,
                terminalStatus: .approved,
                reviewTimeoutMilliseconds: 90_000,
                startedAt: 100
            ),
            context: Self.analyticsContext
        )

        let requests = await uploader.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].events.count, 1)
        guard case let .guardianReview(event) = requests[0].events[0] else {
            return XCTFail("expected guardian review analytics event")
        }
        XCTAssertEqual(event.eventType, "codex_guardian_review")
        XCTAssertEqual(event.eventParams.guardianReview.threadID, "thread-guardian")
        XCTAssertEqual(event.eventParams.guardianReview.decision, .approved)
    }

    func testGuardianReviewTrackContextBuildsEventParamsLikeRust() throws {
        let tracking = CodexGuardianReviewTrackContext(
            threadID: "thread-track",
            turnID: "turn-track",
            reviewID: "review-track",
            targetItemID: "item-track",
            approvalRequestSource: .delegatedSubagent,
            reviewedAction: .mcpToolCall(
                server: "github",
                toolName: "pull_request_read",
                connectorID: "connector-1",
                connectorName: "GitHub",
                toolTitle: "Read Pull Request"
            ),
            reviewTimeoutMilliseconds: 120_000,
            startedAtMilliseconds: 123_456,
            elapsedMilliseconds: { 789 }
        )
        var result = CodexGuardianReviewAnalyticsResult.fromSession(
            guardianThreadID: "guardian-thread",
            guardianSessionKind: .ephemeralForked,
            guardianModel: "gpt-5.1",
            guardianReasoningEffort: "high",
            hadPriorReviewContext: true
        )
        result.decision = .approved
        result.terminalStatus = .approved
        result.riskLevel = .medium
        result.userAuthorization = .high
        result.outcome = .allow
        result.reviewedActionTruncated = true
        result.tokenUsage = TokenUsage(
            inputTokens: 10,
            cachedInputTokens: 4,
            outputTokens: 6,
            reasoningOutputTokens: 2,
            totalTokens: 16
        )
        result.timeToFirstTokenMilliseconds = 321

        let fact = tracking.eventParams(
            result: result,
            completedAtSeconds: 130
        )
        let event = CodexGuardianReviewAnalyticsReducer().ingest(
            fact,
            context: Self.analyticsContext
        )

        try XCTAssertJSONObjectEqual(event, [
            "event_type": "codex_guardian_review",
            "event_params": [
                "app_server_client": Self.analyticsContextAppServerClientJSON(),
                "runtime": Self.analyticsContextRuntimeJSON(),
                "thread_id": "thread-track",
                "turn_id": "turn-track",
                "review_id": "review-track",
                "target_item_id": "item-track",
                "approval_request_source": "delegated_subagent",
                "reviewed_action": [
                    "type": "mcp_tool_call",
                    "server": "github",
                    "tool_name": "pull_request_read",
                    "connector_id": "connector-1",
                    "connector_name": "GitHub",
                    "tool_title": "Read Pull Request"
                ],
                "reviewed_action_truncated": true,
                "decision": "approved",
                "terminal_status": "approved",
                "failure_reason": nil,
                "risk_level": "medium",
                "user_authorization": "high",
                "outcome": "allow",
                "guardian_thread_id": "guardian-thread",
                "guardian_session_kind": "ephemeral_forked",
                "guardian_model": "gpt-5.1",
                "guardian_reasoning_effort": "high",
                "had_prior_review_context": true,
                "review_timeout_ms": 120_000,
                "tool_call_count": nil,
                "time_to_first_token_ms": 321,
                "completion_latency_ms": 789,
                "started_at": 123,
                "completed_at": 130,
                "input_tokens": 10,
                "cached_input_tokens": 4,
                "output_tokens": 6,
                "reasoning_output_tokens": 2,
                "total_tokens": 16
            ]
        ])
    }

    func testGuardianReviewAnalyticsResultDefaultsMatchRust() {
        XCTAssertEqual(
            CodexGuardianReviewAnalyticsResult.withoutSession(),
            CodexGuardianReviewAnalyticsResult(
                decision: .denied,
                terminalStatus: .failedClosed
            )
        )

        let result = CodexGuardianReviewAnalyticsResult.fromSession(
            guardianThreadID: "guardian-thread",
            guardianSessionKind: .trunkReused,
            guardianModel: "gpt-5",
            guardianReasoningEffort: nil,
            hadPriorReviewContext: false
        )
        XCTAssertEqual(result.decision, .denied)
        XCTAssertEqual(result.terminalStatus, .failedClosed)
        XCTAssertEqual(result.guardianThreadID, "guardian-thread")
        XCTAssertEqual(result.guardianSessionKind, .trunkReused)
        XCTAssertEqual(result.guardianModel, "gpt-5")
        XCTAssertNil(result.guardianReasoningEffort)
        XCTAssertEqual(result.hadPriorReviewContext, false)
    }

    private static let analyticsContext = CodexCommandExecutionAnalyticsContext(
        appServerClient: CodexAppServerClientMetadata(
            productClientID: "codex_tui",
            clientName: "codex-tui",
            clientVersion: "1.2.3",
            rpcTransport: .websocket,
            experimentalAPIEnabled: true
        ),
        runtime: CodexRuntimeMetadata(
            codexRSVersion: "0.99.0",
            runtimeOS: "macos",
            runtimeOSVersion: "15.3.1",
            runtimeArch: "aarch64"
        ),
        threadSource: .user
    )

    private static func analyticsContextAppServerClientJSON() -> [String: Any?] {
        [
            "product_client_id": "codex_tui",
            "client_name": "codex-tui",
            "client_version": "1.2.3",
            "rpc_transport": "websocket",
            "experimental_api_enabled": true
        ]
    }

    private static func analyticsContextRuntimeJSON() -> [String: Any?] {
        [
            "codex_rs_version": "0.99.0",
            "runtime_os": "macos",
            "runtime_os_version": "15.3.1",
            "runtime_arch": "aarch64"
        ]
    }

    private static let sampleFileChanges: [AppServerFileUpdateChange] = [
        AppServerFileUpdateChange(path: "/repo/new.swift", kind: .add, diff: "+new"),
        AppServerFileUpdateChange(path: "/repo/existing.swift", kind: .update(movePath: nil), diff: "-old\n+new"),
        AppServerFileUpdateChange(path: "/repo/old.swift", kind: .delete, diff: "-old"),
        AppServerFileUpdateChange(path: "/repo/moved.swift", kind: .update(movePath: "/repo/renamed.swift"), diff: "-old\n+new")
    ]

    private static func reduceCommandExecution(
        status: AppServerCommandExecutionStatus,
        source: AppServerCommandExecutionSource,
        reducer: inout CodexCommandExecutionAnalyticsReducer
    ) throws -> CodexCommandExecutionEventRequest {
        let item = AppServerThreadItem.commandExecution(
            id: "exec-\(status.rawValue)",
            command: "command",
            cwd: try AbsolutePath(absolutePath: "/repo"),
            source: source,
            status: status,
            commandActions: [.unknown(command: "command")],
            exitCode: status == .failed ? 1 : nil,
            durationMs: 10
        )
        reducer.ingestStarted(ItemStartedNotification(
            item: item,
            threadID: "thread-1",
            turnID: "turn-1",
            startedAtMilliseconds: 10
        ))
        return try XCTUnwrap(reducer.ingestCompleted(
            ItemCompletedNotification(
                item: item,
                threadID: "thread-1",
                turnID: "turn-1",
                completedAtMilliseconds: 20
            ),
            context: analyticsContext
        ))
    }

    private static func reduceFileChange(
        status: AppServerPatchApplyStatus,
        reducer: inout CodexFileChangeAnalyticsReducer
    ) throws -> CodexFileChangeEventRequest {
        let item = AppServerThreadItem.fileChange(
            id: "patch-\(status.rawValue)",
            changes: sampleFileChanges,
            status: status
        )
        reducer.ingestStarted(ItemStartedNotification(
            item: item,
            threadID: "thread-1",
            turnID: "turn-1",
            startedAtMilliseconds: 10
        ))
        return try XCTUnwrap(reducer.ingestCompleted(
            ItemCompletedNotification(
                item: item,
                threadID: "thread-1",
                turnID: "turn-1",
                completedAtMilliseconds: 20
            ),
            context: analyticsContext
        ))
    }

    private static func mcpToolCallItem(
        status: McpToolCallStatus,
        error: AppServerProtocol.McpToolCallError? = nil
    ) -> AppServerThreadItem {
        .mcpToolCall(
            id: "mcp-\(status.rawValue)",
            server: "docs",
            tool: "lookup",
            status: status,
            arguments: .object([:]),
            error: error,
            durationMs: 10
        )
    }

    private static func reduceMcpToolCall(
        status: McpToolCallStatus,
        error: AppServerProtocol.McpToolCallError?,
        reducer: inout CodexMcpToolCallAnalyticsReducer
    ) throws -> CodexMcpToolCallEventRequest {
        let item = mcpToolCallItem(status: status, error: error)
        reducer.ingestStarted(ItemStartedNotification(
            item: item,
            threadID: "thread-1",
            turnID: "turn-1",
            startedAtMilliseconds: 10
        ))
        return try XCTUnwrap(reducer.ingestCompleted(
            ItemCompletedNotification(
                item: item,
                threadID: "thread-1",
                turnID: "turn-1",
                completedAtMilliseconds: 20
            ),
            context: analyticsContext
        ))
    }

    private static func dynamicToolCallItem(
        status: AppServerDynamicToolCallStatus,
        contentItems: [DynamicToolCallOutputContentItem]? = [.text("ok")],
        success: Bool? = true
    ) -> AppServerThreadItem {
        .dynamicToolCall(
            id: "dynamic-\(status.rawValue)",
            namespace: "docs",
            tool: "lookup",
            arguments: .object([:]),
            status: status,
            contentItems: contentItems,
            success: success,
            durationMs: 10
        )
    }

    private static func reduceDynamicToolCall(
        status: AppServerDynamicToolCallStatus,
        contentItems: [DynamicToolCallOutputContentItem]?,
        success: Bool?,
        reducer: inout CodexDynamicToolCallAnalyticsReducer
    ) throws -> CodexDynamicToolCallEventRequest {
        let item = dynamicToolCallItem(status: status, contentItems: contentItems, success: success)
        reducer.ingestStarted(ItemStartedNotification(
            item: item,
            threadID: "thread-1",
            turnID: "turn-1",
            startedAtMilliseconds: 10
        ))
        return try XCTUnwrap(reducer.ingestCompleted(
            ItemCompletedNotification(
                item: item,
                threadID: "thread-1",
                turnID: "turn-1",
                completedAtMilliseconds: 20
            ),
            context: analyticsContext
        ))
    }

    private static func collabAgentToolCallItem(
        tool: AppServerCollabAgentTool = .spawnAgent,
        status: AppServerCollabAgentToolCallStatus,
        receiverThreadIDs: [String] = ["child-1"],
        model: String? = "gpt-5.5",
        reasoningEffort: ReasoningEffort? = .medium,
        agentsStates: [String: AppServerCollabAgentState] = [
            "child-1": AppServerCollabAgentState(status: .completed)
        ]
    ) -> AppServerThreadItem {
        .collabAgentToolCall(
            id: "collab-\(tool.rawValue)-\(status.rawValue)",
            tool: tool,
            status: status,
            senderThreadID: "thread-sender",
            receiverThreadIDs: receiverThreadIDs,
            prompt: "work on this",
            model: model,
            reasoningEffort: reasoningEffort,
            agentsStates: agentsStates
        )
    }

    private static func reduceCollabAgentToolCall(
        tool: AppServerCollabAgentTool,
        status: AppServerCollabAgentToolCallStatus,
        receiverThreadIDs: [String],
        model: String?,
        reasoningEffort: ReasoningEffort?,
        agentsStates: [String: AppServerCollabAgentState],
        reducer: inout CodexCollabAgentToolCallAnalyticsReducer
    ) throws -> CodexCollabAgentToolCallEventRequest {
        let item = collabAgentToolCallItem(
            tool: tool,
            status: status,
            receiverThreadIDs: receiverThreadIDs,
            model: model,
            reasoningEffort: reasoningEffort,
            agentsStates: agentsStates
        )
        reducer.ingestStarted(ItemStartedNotification(
            item: item,
            threadID: "thread-1",
            turnID: "turn-1",
            startedAtMilliseconds: 10
        ))
        return try XCTUnwrap(reducer.ingestCompleted(
            ItemCompletedNotification(
                item: item,
                threadID: "thread-1",
                turnID: "turn-1",
                completedAtMilliseconds: 20
            ),
            context: analyticsContext
        ))
    }

    private static func reduceWebSearch(
        query: String,
        action: AppServerWebSearchAction?,
        reducer: inout CodexWebSearchAnalyticsReducer
    ) throws -> CodexWebSearchEventRequest {
        let item = AppServerThreadItem.webSearch(id: "web-reduced", query: query, action: action)
        reducer.ingestStarted(ItemStartedNotification(
            item: item,
            threadID: "thread-1",
            turnID: "turn-1",
            startedAtMilliseconds: 10
        ))
        return try XCTUnwrap(reducer.ingestCompleted(
            ItemCompletedNotification(
                item: item,
                threadID: "thread-1",
                turnID: "turn-1",
                completedAtMilliseconds: 20
            ),
            context: analyticsContext
        ))
    }

    private static func reduceImageGeneration(
        status: String,
        reducer: inout CodexImageGenerationAnalyticsReducer
    ) throws -> CodexImageGenerationEventRequest {
        let item = AppServerThreadItem.imageGeneration(
            id: "image-\(status)",
            status: status,
            result: "generated"
        )
        reducer.ingestStarted(ItemStartedNotification(
            item: item,
            threadID: "thread-1",
            turnID: "turn-1",
            startedAtMilliseconds: 10
        ))
        return try XCTUnwrap(reducer.ingestCompleted(
            ItemCompletedNotification(
                item: item,
                threadID: "thread-1",
                turnID: "turn-1",
                completedAtMilliseconds: 20
            ),
            context: analyticsContext
        ))
    }

    func testCodexCommandExecutionEventRequestUsesRustWireShape() throws {
        let actions: [AppServerProtocol.CommandAction] = [
            .read(command: "cat README.md", name: "README.md", path: "/repo/README.md"),
            .listFiles(command: "ls Sources", path: "/repo/Sources"),
            .search(command: "rg TODO", query: "TODO", path: nil),
            .unknown(command: "swift test")
        ]
        let event = CodexCommandExecutionEventRequest(
            eventType: "codex_command_execution_event",
            eventParams: CodexCommandExecutionEventParams(
                base: CodexToolItemEventBase(
                    threadID: "thread-1",
                    turnID: "turn-1",
                    itemID: "item-1",
                    appServerClient: CodexAppServerClientMetadata(
                        productClientID: "codex_tui",
                        clientName: "codex-tui",
                        clientVersion: "1.2.3",
                        rpcTransport: .websocket,
                        experimentalAPIEnabled: true
                    ),
                    runtime: CodexRuntimeMetadata(
                        codexRSVersion: "0.99.0",
                        runtimeOS: "macos",
                        runtimeOSVersion: "15.3.1",
                        runtimeArch: "aarch64"
                    ),
                    threadSource: .user,
                    subagentSource: nil,
                    parentThreadID: nil,
                    toolName: "shell",
                    startedAtMilliseconds: 123_000,
                    completedAtMilliseconds: 125_000,
                    durationMilliseconds: 2_000,
                    executionDurationMilliseconds: 1_900,
                    reviewCount: 0,
                    guardianReviewCount: 0,
                    userReviewCount: 0,
                    finalApprovalOutcome: .notNeeded,
                    terminalStatus: .completed,
                    failureKind: nil,
                    requestedAdditionalPermissions: false,
                    requestedNetworkAccess: false
                ),
                commandExecutionSource: .agent,
                exitCode: 0,
                commandActionCounts: CodexCommandActionCounts(actions: actions)
            )
        )

        try XCTAssertJSONObjectEqual(event, [
            "event_type": "codex_command_execution_event",
            "event_params": [
                "thread_id": "thread-1",
                "turn_id": "turn-1",
                "item_id": "item-1",
                "app_server_client": [
                    "product_client_id": "codex_tui",
                    "client_name": "codex-tui",
                    "client_version": "1.2.3",
                    "rpc_transport": "websocket",
                    "experimental_api_enabled": true
                ],
                "runtime": [
                    "codex_rs_version": "0.99.0",
                    "runtime_os": "macos",
                    "runtime_os_version": "15.3.1",
                    "runtime_arch": "aarch64"
                ],
                "thread_source": "user",
                "subagent_source": nil,
                "parent_thread_id": nil,
                "tool_name": "shell",
                "started_at_ms": 123_000,
                "completed_at_ms": 125_000,
                "duration_ms": 2_000,
                "execution_duration_ms": 1_900,
                "review_count": 0,
                "guardian_review_count": 0,
                "user_review_count": 0,
                "final_approval_outcome": "not_needed",
                "terminal_status": "completed",
                "failure_kind": nil,
                "requested_additional_permissions": false,
                "requested_network_access": false,
                "command_execution_source": "agent",
                "exit_code": 0,
                "command_total_action_count": 4,
                "command_read_action_count": 1,
                "command_list_files_action_count": 1,
                "command_search_action_count": 1,
                "command_unknown_action_count": 1
            ]
        ])
    }

    func testCodexReviewEventRequestUsesRustWireShape() throws {
        let event = CodexReviewEventRequest(
            eventType: "codex_review_event",
            eventParams: CodexReviewEventParams(
                threadID: "thread-1",
                turnID: "turn-1",
                itemID: nil,
                reviewID: "review-1",
                appServerClient: CodexAppServerClientMetadata(
                    productClientID: "codex_tui",
                    clientName: "codex-tui",
                    clientVersion: "1.2.3",
                    rpcTransport: .websocket,
                    experimentalAPIEnabled: true
                ),
                runtime: CodexRuntimeMetadata(
                    codexRSVersion: "0.99.0",
                    runtimeOS: "macos",
                    runtimeOSVersion: "15.3.1",
                    runtimeArch: "aarch64"
                ),
                threadSource: .user,
                subagentSource: nil,
                parentThreadID: nil,
                toolKind: .mcpToolCall,
                toolName: "mcp__example__run",
                reviewer: .guardian,
                trigger: .networkPolicyDenial,
                status: .approved,
                resolution: .networkPolicyAmendment,
                startedAtMilliseconds: 123_000,
                completedAtMilliseconds: 124_500,
                durationMilliseconds: nil
            )
        )

        try XCTAssertJSONObjectEqual(event, [
            "event_type": "codex_review_event",
            "event_params": [
                "thread_id": "thread-1",
                "turn_id": "turn-1",
                "item_id": nil,
                "review_id": "review-1",
                "app_server_client": [
                    "product_client_id": "codex_tui",
                    "client_name": "codex-tui",
                    "client_version": "1.2.3",
                    "rpc_transport": "websocket",
                    "experimental_api_enabled": true
                ],
                "runtime": [
                    "codex_rs_version": "0.99.0",
                    "runtime_os": "macos",
                    "runtime_os_version": "15.3.1",
                    "runtime_arch": "aarch64"
                ],
                "thread_source": "user",
                "subagent_source": nil,
                "parent_thread_id": nil,
                "tool_kind": "mcp_tool_call",
                "tool_name": "mcp__example__run",
                "reviewer": "guardian",
                "trigger": "network_policy_denial",
                "status": "approved",
                "resolution": "network_policy_amendment",
                "started_at_ms": 123_000,
                "completed_at_ms": 124_500,
                "duration_ms": nil
            ]
        ])
    }

    func testReviewAnalyticsEnumsUseRustSnakeCaseValues() throws {
        try XCTAssertJSONObjectEqual(EnumSamples(), [
            "tool_kinds": [
                "command_execution",
                "file_change",
                "mcp_tool_call",
                "permissions",
                "network_access"
            ],
            "reviewers": [
                "guardian",
                "user"
            ],
            "triggers": [
                "initial",
                "sandbox_denial",
                "network_policy_denial",
                "execve_intercept"
            ],
            "statuses": [
                "approved",
                "denied",
                "aborted",
                "timed_out"
            ],
            "resolutions": [
                "none",
                "session_approval",
                "exec_policy_amendment",
                "network_policy_amendment"
            ],
            "tool_item_outcomes": [
                "unknown",
                "not_needed",
                "config_allowed",
                "policy_forbidden",
                "guardian_approved",
                "guardian_denied",
                "guardian_aborted",
                "user_approved",
                "user_approved_for_session",
                "user_denied",
                "user_aborted"
            ],
            "tool_item_statuses": [
                "completed",
                "failed",
                "rejected",
                "interrupted"
            ],
            "tool_item_failure_kinds": [
                "tool_error",
                "approval_denied",
                "approval_aborted",
                "sandbox_denied",
                "policy_forbidden"
            ],
            "command_execution_sources": [
                "agent",
                "user_shell",
                "unified_exec_startup",
                "unified_exec_interaction"
            ],
            "compaction_triggers": [
                "manual",
                "auto"
            ],
            "compaction_reasons": [
                "user_requested",
                "context_limit",
                "model_downshift"
            ],
            "compaction_implementations": [
                "responses",
                "responses_compact"
            ],
            "compaction_phases": [
                "standalone_turn",
                "pre_turn",
                "mid_turn"
            ],
            "compaction_strategies": [
                "memento",
                "prefix_compaction"
            ],
            "compaction_statuses": [
                "completed",
                "failed",
                "interrupted"
            ]
        ])
    }

    private struct EnumSamples: Encodable {
        let toolKinds: [ReviewSubjectKind] = [
            .commandExecution,
            .fileChange,
            .mcpToolCall,
            .permissions,
            .networkAccess
        ]
        let reviewers: [ReviewAnalyticsReviewer] = [.guardian, .user]
        let triggers: [ReviewTrigger] = [
            .initial,
            .sandboxDenial,
            .networkPolicyDenial,
            .execveIntercept
        ]
        let statuses: [ReviewStatus] = [.approved, .denied, .aborted, .timedOut]
        let resolutions: [ReviewResolution] = [
            .none,
            .sessionApproval,
            .execPolicyAmendment,
            .networkPolicyAmendment
        ]
        let toolItemOutcomes: [ToolItemFinalApprovalOutcome] = [
            .unknown,
            .notNeeded,
            .configAllowed,
            .policyForbidden,
            .guardianApproved,
            .guardianDenied,
            .guardianAborted,
            .userApproved,
            .userApprovedForSession,
            .userDenied,
            .userAborted
        ]
        let toolItemStatuses: [ToolItemTerminalStatus] = [
            .completed,
            .failed,
            .rejected,
            .interrupted
        ]
        let toolItemFailureKinds: [ToolItemFailureKind] = [
            .toolError,
            .approvalDenied,
            .approvalAborted,
            .sandboxDenied,
            .policyForbidden
        ]
        let commandExecutionSources: [CommandExecutionSource] = [
            .agent,
            .userShell,
            .unifiedExecStartup,
            .unifiedExecInteraction
        ]
        let compactionTriggers: [CompactionTrigger] = [.manual, .auto]
        let compactionReasons: [CompactionReason] = [
            .userRequested,
            .contextLimit,
            .modelDownshift
        ]
        let compactionImplementations: [CompactionImplementation] = [
            .responses,
            .responsesCompact
        ]
        let compactionPhases: [CompactionPhase] = [
            .standaloneTurn,
            .preTurn,
            .midTurn
        ]
        let compactionStrategies: [CompactionStrategy] = [
            .memento,
            .prefixCompaction
        ]
        let compactionStatuses: [CompactionStatus] = [
            .completed,
            .failed,
            .interrupted
        ]

        private enum CodingKeys: String, CodingKey {
            case toolKinds = "tool_kinds"
            case reviewers
            case triggers
            case statuses
            case resolutions
            case toolItemOutcomes = "tool_item_outcomes"
            case toolItemStatuses = "tool_item_statuses"
            case toolItemFailureKinds = "tool_item_failure_kinds"
            case commandExecutionSources = "command_execution_sources"
            case compactionTriggers = "compaction_triggers"
            case compactionReasons = "compaction_reasons"
            case compactionImplementations = "compaction_implementations"
            case compactionPhases = "compaction_phases"
            case compactionStrategies = "compaction_strategies"
            case compactionStatuses = "compaction_statuses"
        }
    }

    private static func fakeJWT(authClaims: [String: Any]) -> String {
        func encode(_ object: Any) -> String {
            let data = try! JSONSerialization.data(withJSONObject: object)
            return data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }

        return [
            encode(["alg": "none"]),
            encode(["https://api.openai.com/auth": authClaims]),
            "sig"
        ].joined(separator: ".")
    }
}

private actor RecordingCodexAnalyticsAPITransport: APITransport {
    private(set) var executeRequests: [APIRequest] = []

    func execute(_ request: APIRequest) async -> Result<APIResponse, TransportError> {
        executeRequests.append(request)
        return .success(APIResponse(statusCode: 204))
    }

    func stream(_: APIRequest) async -> Result<APIStreamResponse, TransportError> {
        .failure(.network("stream not supported"))
    }
}

private actor RecordingCodexAnalyticsUploader: CodexAnalyticsUploading {
    private(set) var requests: [CodexTrackEventsRequest] = []

    func upload(_ request: CodexTrackEventsRequest) async throws {
        requests.append(request)
    }
}

private final class ReviewAnalyticsTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
