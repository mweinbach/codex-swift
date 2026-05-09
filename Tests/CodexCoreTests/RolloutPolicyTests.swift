import CodexCore
import XCTest

final class RolloutPolicyTests: XCTestCase {
    func testResponseItemPersistenceMatchesRustBuckets() throws {
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItem(.message(role: "assistant", content: [])))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItem(.reasoning(id: "r1", summary: [])))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItem(.functionCall(name: "do_it", arguments: "{}", callID: "call-1")))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItem(.toolSearchCall(callID: "search-1", execution: "client", arguments: .object(["query": .string("docs")]))))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItem(.functionCallOutput(callID: "call-1", output: FunctionCallOutputPayload(content: "ok"))))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItem(.toolSearchOutput(callID: "search-1", status: "completed", execution: "client", tools: [])))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItem(.customToolCall(callID: "tool-1", name: "custom", input: "{}")))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItem(.customToolCallOutput(callID: "tool-1", output: "ok")))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItem(.localShellCall(callID: "shell-1", status: .completed, action: .exec(LocalShellExecAction(command: ["echo"])))))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItem(.webSearchCall(status: "completed", action: .search(query: "weather"))))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItem(.imageGenerationCall(id: "ig-1", status: "completed", result: "Zm9v")))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItem(.compaction(encryptedContent: "encrypted")))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItem(.contextCompaction(encryptedContent: "encrypted")))
        XCTAssertFalse(RolloutPolicy.shouldPersistResponseItem(.ghostSnapshot(ghostCommit: GhostCommit(
            id: "ghost-1",
            preexistingUntrackedFiles: [],
            preexistingUntrackedDirs: []
        ))))
        XCTAssertFalse(RolloutPolicy.shouldPersistResponseItem(.other))

        for type in [
            "reasoning",
            "local_shell_call",
            "function_call",
            "tool_search_call",
            "function_call_output",
            "tool_search_output",
            "custom_tool_call",
            "custom_tool_call_output",
            "image_generation_call"
        ] {
            let item = try JSONDecoder().decode(ResponseItem.self, from: Data(#"{"type":"\#(type)"}"#.utf8))
            XCTAssertEqual(item, .knownPersisted(type: type))
            XCTAssertTrue(RolloutPolicy.shouldPersistResponseItem(item), type)
        }

        let legacyGhost = try JSONDecoder().decode(
            ResponseItem.self,
            from: Data(#"{"type":"ghost_snapshot","ghost_commit":{"id":"ghost-1","preexisting_untracked_files":[],"preexisting_untracked_dirs":[]}}"#.utf8)
        )
        XCTAssertEqual(legacyGhost, .other)
        XCTAssertFalse(RolloutPolicy.shouldPersistResponseItem(legacyGhost))
    }

    func testResponseItemMemoriesPersistenceMatchesRustBuckets() {
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItemForMemories(.message(role: "user", content: [])))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItemForMemories(.message(role: "assistant", content: [])))
        XCTAssertFalse(RolloutPolicy.shouldPersistResponseItemForMemories(.message(role: "developer", content: [])))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItemForMemories(.functionCall(name: "do_it", arguments: "{}", callID: "call-1")))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItemForMemories(.toolSearchCall(callID: "search-1", execution: "client", arguments: .object(["query": .string("docs")]))))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItemForMemories(.functionCallOutput(callID: "call-1", output: FunctionCallOutputPayload(content: "ok"))))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItemForMemories(.toolSearchOutput(callID: "search-1", status: "completed", execution: "client", tools: [])))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItemForMemories(.customToolCall(callID: "tool-1", name: "custom", input: "{}")))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItemForMemories(.customToolCallOutput(callID: "tool-1", output: "ok")))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItemForMemories(.localShellCall(callID: "shell-1", status: .completed, action: .exec(LocalShellExecAction(command: ["echo"])))))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItemForMemories(.webSearchCall(status: "completed", action: .search(query: "weather"))))
        XCTAssertFalse(RolloutPolicy.shouldPersistResponseItemForMemories(.reasoning(id: "r1", summary: [])))
        XCTAssertFalse(RolloutPolicy.shouldPersistResponseItemForMemories(.imageGenerationCall(id: "ig-1", status: "completed", result: "Zm9v")))
        XCTAssertFalse(RolloutPolicy.shouldPersistResponseItemForMemories(.compaction(encryptedContent: "encrypted")))
        XCTAssertFalse(RolloutPolicy.shouldPersistResponseItemForMemories(.contextCompaction(encryptedContent: "encrypted")))
        XCTAssertFalse(RolloutPolicy.shouldPersistResponseItemForMemories(.ghostSnapshot(ghostCommit: GhostCommit(
            id: "ghost-1",
            preexistingUntrackedFiles: [],
            preexistingUntrackedDirs: []
        ))))
        XCTAssertFalse(RolloutPolicy.shouldPersistResponseItemForMemories(.other))

        for type in [
            "local_shell_call",
            "function_call",
            "tool_search_call",
            "function_call_output",
            "tool_search_output",
            "custom_tool_call",
            "custom_tool_call_output",
            "web_search_call",
        ] {
            XCTAssertTrue(RolloutPolicy.shouldPersistResponseItemForMemories(.knownPersisted(type: type)), type)
        }

        for type in [
            "reasoning",
            "image_generation_call",
            "compaction",
            "context_compaction",
            "ghost_snapshot",
        ] {
            XCTAssertFalse(RolloutPolicy.shouldPersistResponseItemForMemories(.knownPersisted(type: type)), type)
        }
    }

    func testEventMessagePersistenceMatchesRustBuckets() {
        let limited: Set<RolloutEventMessageKind> = [
            .userMessage,
            .agentMessage,
            .agentReasoning,
            .agentReasoningRawContent,
            .patchApplyEnd,
            .tokenCount,
            .contextCompacted,
            .enteredReviewMode,
            .exitedReviewMode,
            .mcpToolCallEnd,
            .undoCompleted,
            .turnAborted,
            .taskStarted,
            .taskComplete,
            .threadRolledBack,
            .webSearchEnd,
            .imageGenerationEnd
        ]
        let extendedOnly: Set<RolloutEventMessageKind> = [
            .error,
            .guardianAssessment,
            .execCommandEnd,
            .viewImageToolCall,
            .dynamicToolCallRequest,
            .dynamicToolCallResponse,
            .collabAgentSpawnEnd,
            .collabAgentInteractionEnd,
            .collabWaitingEnd,
            .collabCloseEnd,
            .collabResumeEnd
        ]

        for event in RolloutEventMessageKind.allCases {
            XCTAssertEqual(
                RolloutPolicy.shouldPersistEventMessage(event),
                limited.contains(event),
                event.rawValue
            )
            XCTAssertEqual(
                RolloutPolicy.shouldPersistEventMessage(event, mode: .extended),
                limited.contains(event) || extendedOnly.contains(event),
                event.rawValue
            )
        }

        for event in limited {
            XCTAssertEqual(RolloutPolicy.eventMessagePersistenceMode(event), .limited, event.rawValue)
        }
        for event in extendedOnly {
            XCTAssertEqual(RolloutPolicy.eventMessagePersistenceMode(event), .extended, event.rawValue)
        }
    }

    func testEventMessageKindMappingFeedsPersistencePolicy() {
        XCTAssertEqual(RolloutPolicy.eventKind(for: .warning(WarningEvent(message: "heads up"))), .warning)
        XCTAssertEqual(
            RolloutPolicy.eventKind(for: .guardianWarning(WarningEvent(message: "careful"))),
            .guardianWarning
        )
        XCTAssertEqual(
            RolloutPolicy.eventKind(for: .realtimeConversationStarted(RealtimeConversationStartedEvent(
                realtimeSessionID: "conv-1"
            ))),
            .realtimeConversationStarted
        )
        XCTAssertEqual(
            RolloutPolicy.eventKind(for: .realtimeConversationRealtime(RealtimeConversationRealtimeEvent(
                payload: .conversationItemDone(itemID: "item-1")
            ))),
            .realtimeConversationRealtime
        )
        XCTAssertEqual(
            RolloutPolicy.eventKind(for: .realtimeConversationClosed(RealtimeConversationClosedEvent(reason: "done"))),
            .realtimeConversationClosed
        )
        XCTAssertEqual(
            RolloutPolicy.eventKind(for: .realtimeConversationSdp(RealtimeConversationSdpEvent(sdp: "v=0"))),
            .realtimeConversationSdp
        )
        XCTAssertEqual(
            RolloutPolicy.eventKind(for: .modelReroute(ModelRerouteEvent(
                fromModel: "gpt-5.4",
                toModel: "gpt-5.4-cyber",
                reason: .highRiskCyberActivity
            ))),
            .modelReroute
        )
        XCTAssertEqual(
            RolloutPolicy.eventKind(for: .modelVerification(ModelVerificationEvent(
                verifications: [.trustedAccessForCyber]
            ))),
            .modelVerification
        )
        XCTAssertEqual(
            RolloutPolicy.eventKind(for: .realtimeConversationListVoicesResponse(
                RealtimeConversationListVoicesResponseEvent(voices: .builtin())
            )),
            .realtimeConversationListVoicesResponse
        )
        let goalThreadID = try! ThreadId(string: "018f7a2d-4c5b-7abc-8def-0123456789ab")
        XCTAssertEqual(
            RolloutPolicy.eventKind(for: .threadGoalUpdated(ThreadGoalUpdatedEvent(
                threadID: goalThreadID,
                goal: ThreadGoal(
                    threadID: goalThreadID,
                    objective: "port",
                    status: .active,
                    tokensUsed: 0,
                    timeUsedSeconds: 0,
                    createdAt: 1,
                    updatedAt: 1
                )
            ))),
            .threadGoalUpdated
        )
        XCTAssertEqual(RolloutPolicy.eventKind(for: .userMessage(UserMessageEvent(message: "hello"))), .userMessage)
        XCTAssertEqual(
            RolloutPolicy.eventKind(for: .imageGenerationBegin(ImageGenerationBeginEvent(callID: "ig-1"))),
            .imageGenerationBegin
        )
        XCTAssertEqual(
            RolloutPolicy.eventKind(for: .patchApplyUpdated(PatchApplyUpdatedEvent(
                callID: "patch-1",
                changes: [:]
            ))),
            .patchApplyUpdated
        )
        XCTAssertEqual(
            RolloutPolicy.eventKind(for: .requestPermissions(RequestPermissionsEvent(
                callID: "perm-1",
                turnID: "turn-1",
                startedAtMilliseconds: 1_000,
                permissions: RequestPermissionProfile(network: RequestPermissionNetworkPermissions(enabled: true))
            ))),
            .requestPermissions
        )
        XCTAssertEqual(
            RolloutPolicy.eventKind(for: .requestUserInput(RequestUserInputEvent(
                callID: "input-1",
                questions: [RequestUserInputQuestion(id: "choice", header: "Choice", question: "Pick one")]
            ))),
            .requestUserInput
        )
        XCTAssertEqual(
            RolloutPolicy.eventKind(for: .dynamicToolCallRequest(DynamicToolCallRequest(
                callID: "dyn-1",
                turnID: "turn-1",
                tool: "lookup",
                arguments: .object([:])
            ))),
            .dynamicToolCallRequest
        )
        XCTAssertEqual(
            RolloutPolicy.eventKind(for: .dynamicToolCallResponse(DynamicToolCallResponseEvent(
                callID: "dyn-1",
                turnID: "turn-1",
                tool: "lookup",
                arguments: .object([:]),
                contentItems: [.text("done")],
                success: true,
                duration: ProtocolDuration(secs: 1)
            ))),
            .dynamicToolCallResponse
        )
        XCTAssertEqual(
            RolloutPolicy.eventKind(for: .hookStarted(HookStartedEvent(
                turnID: nil,
                run: minimalHookRunSummary()
            ))),
            .hookStarted
        )
        XCTAssertEqual(
            RolloutPolicy.eventKind(for: .hookCompleted(HookCompletedEvent(
                turnID: "turn-1",
                run: minimalHookRunSummary()
            ))),
            .hookCompleted
        )
        XCTAssertEqual(
            RolloutPolicy.eventKind(for: .planDelta(PlanDeltaEvent(
                threadID: "thread-1",
                turnID: "turn-1",
                itemID: "item-1",
                delta: "step"
            ))),
            .planDelta
        )
        XCTAssertEqual(
            RolloutPolicy.eventKind(for: .imageGenerationEnd(ImageGenerationEndEvent(
                callID: "ig-1",
                status: "completed",
                result: "base64-png"
            ))),
            .imageGenerationEnd
        )
        XCTAssertFalse(RolloutPolicy.shouldPersistEventMessage(.warning(WarningEvent(message: "heads up"))))
        XCTAssertFalse(RolloutPolicy.shouldPersistEventMessage(.guardianWarning(WarningEvent(message: "careful"))))
        XCTAssertFalse(RolloutPolicy.shouldPersistEventMessage(.realtimeConversationStarted(
            RealtimeConversationStartedEvent(realtimeSessionID: "conv-1")
        )))
        XCTAssertFalse(RolloutPolicy.shouldPersistEventMessage(.realtimeConversationRealtime(
            RealtimeConversationRealtimeEvent(payload: .conversationItemDone(itemID: "item-1"))
        )))
        XCTAssertFalse(RolloutPolicy.shouldPersistEventMessage(.realtimeConversationClosed(
            RealtimeConversationClosedEvent(reason: "done")
        )))
        XCTAssertFalse(RolloutPolicy.shouldPersistEventMessage(.realtimeConversationSdp(
            RealtimeConversationSdpEvent(sdp: "v=0")
        )))
        XCTAssertFalse(RolloutPolicy.shouldPersistEventMessage(.modelReroute(ModelRerouteEvent(
            fromModel: "gpt-5.4",
            toModel: "gpt-5.4-cyber",
            reason: .highRiskCyberActivity
        ))))
        XCTAssertFalse(RolloutPolicy.shouldPersistEventMessage(.modelVerification(ModelVerificationEvent(
            verifications: [.trustedAccessForCyber]
        ))))
        XCTAssertFalse(RolloutPolicy.shouldPersistEventMessage(.realtimeConversationListVoicesResponse(
            RealtimeConversationListVoicesResponseEvent(voices: .builtin())
        )))
        XCTAssertFalse(RolloutPolicy.shouldPersistEventMessage(.threadGoalUpdated(ThreadGoalUpdatedEvent(
            threadID: goalThreadID,
            goal: ThreadGoal(
                threadID: goalThreadID,
                objective: "port",
                status: .active,
                tokensUsed: 0,
                timeUsedSeconds: 0,
                createdAt: 1,
                updatedAt: 1
            )
        ))))
        XCTAssertFalse(RolloutPolicy.shouldPersistEventMessage(.requestPermissions(RequestPermissionsEvent(
            callID: "perm-1",
            turnID: "turn-1",
            startedAtMilliseconds: 1_000,
            permissions: RequestPermissionProfile(network: RequestPermissionNetworkPermissions(enabled: true))
        ))))
        XCTAssertFalse(RolloutPolicy.shouldPersistEventMessage(.requestUserInput(RequestUserInputEvent(
            callID: "input-1",
            questions: [RequestUserInputQuestion(id: "choice", header: "Choice", question: "Pick one")]
        ))))
        let dynamicToolCallRequest = EventMessage.dynamicToolCallRequest(DynamicToolCallRequest(
            callID: "dyn-1",
            turnID: "turn-1",
            tool: "lookup",
            arguments: .object([:])
        ))
        XCTAssertFalse(RolloutPolicy.shouldPersistEventMessage(dynamicToolCallRequest))
        XCTAssertTrue(RolloutPolicy.shouldPersistEventMessage(dynamicToolCallRequest, mode: .extended))
        XCTAssertFalse(RolloutPolicy.shouldPersistEventMessage(.patchApplyUpdated(PatchApplyUpdatedEvent(
            callID: "patch-1",
            changes: [:]
        ))))
        XCTAssertFalse(RolloutPolicy.shouldPersistEventMessage(.hookStarted(HookStartedEvent(
            turnID: nil,
            run: minimalHookRunSummary()
        ))))
        XCTAssertFalse(RolloutPolicy.shouldPersistEventMessage(.hookCompleted(HookCompletedEvent(
            turnID: "turn-1",
            run: minimalHookRunSummary()
        ))))
        XCTAssertFalse(RolloutPolicy.shouldPersistEventMessage(.planDelta(PlanDeltaEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            itemID: "item-1",
            delta: "step"
        ))))
        XCTAssertTrue(RolloutPolicy.shouldPersistEventMessage(
            .dynamicToolCallResponse(DynamicToolCallResponseEvent(
                callID: "dyn-1",
                turnID: "turn-1",
                tool: "lookup",
                arguments: .object([:]),
                contentItems: [.text("done")],
                success: true,
                duration: ProtocolDuration(secs: 1)
            )),
            mode: .extended
        ))
        XCTAssertFalse(RolloutPolicy.shouldPersistEventMessage(.dynamicToolCallResponse(DynamicToolCallResponseEvent(
            callID: "dyn-1",
            turnID: "turn-1",
            tool: "lookup",
            arguments: .object([:]),
            contentItems: [.text("done")],
            success: true,
            duration: ProtocolDuration(secs: 1)
        ))))
        XCTAssertTrue(RolloutPolicy.shouldPersistEventMessage(.userMessage(UserMessageEvent(message: "hello"))))
        XCTAssertTrue(RolloutPolicy.shouldPersistEventMessage(.threadRolledBack(ThreadRolledBackEvent(numTurns: 1))))
        XCTAssertFalse(RolloutPolicy.shouldPersistEventMessage(.imageGenerationBegin(ImageGenerationBeginEvent(callID: "ig-1"))))
        XCTAssertTrue(RolloutPolicy.shouldPersistEventMessage(.taskStarted(TaskStartedEvent(
            turnID: "turn-1",
            modelContextWindow: nil
        ))))
        XCTAssertTrue(RolloutPolicy.shouldPersistEventMessage(.taskComplete(TaskCompleteEvent(
            turnID: "turn-1",
            lastAgentMessage: nil
        ))))
        XCTAssertTrue(RolloutPolicy.shouldPersistEventMessage(.imageGenerationEnd(ImageGenerationEndEvent(
            callID: "ig-1",
            status: "completed",
            result: "base64-png"
        ))))
        let threadID = try! ConversationId(string: "018f7a2d-4c5b-7abc-8def-0123456789ab")
        XCTAssertTrue(RolloutPolicy.shouldPersistEventMessage(.itemCompleted(ItemCompletedEvent(
            threadID: threadID,
            turnID: "turn-1",
            item: .plan(PlanItem(id: "plan-1", text: "next"))
        ))))
        XCTAssertFalse(RolloutPolicy.shouldPersistEventMessage(.itemCompleted(ItemCompletedEvent(
            threadID: threadID,
            turnID: "turn-1",
            item: .agentMessage(AgentMessageItem(id: "agent-1", content: [.text("done")]))
        ))))
        XCTAssertFalse(RolloutPolicy.shouldPersistEventMessage(.guardianAssessment(GuardianAssessmentEvent(
            id: "guardian-1",
            status: .inProgress,
            action: .command(source: .unifiedExec, command: "git status", cwd: "/repo")
        ))))
        XCTAssertTrue(RolloutPolicy.shouldPersistEventMessage(.guardianAssessment(GuardianAssessmentEvent(
            id: "guardian-1",
            status: .inProgress,
            action: .command(source: .unifiedExec, command: "git status", cwd: "/repo")
        )), mode: .extended))
        XCTAssertFalse(RolloutPolicy.shouldPersistEventMessage(.error(ErrorEvent(message: "boom"))))
        XCTAssertTrue(RolloutPolicy.shouldPersistEventMessage(.error(ErrorEvent(message: "boom")), mode: .extended))
    }

    func testRolloutItemPersistenceMatchesRustBuckets() {
        XCTAssertTrue(RolloutPolicy.isPersistedResponseItem(.sessionMeta))
        XCTAssertTrue(RolloutPolicy.isPersistedResponseItem(.compacted))
        XCTAssertTrue(RolloutPolicy.isPersistedResponseItem(.turnContext))
        XCTAssertTrue(RolloutPolicy.isPersistedResponseItem(.eventMessage(.userMessage)))
        XCTAssertFalse(RolloutPolicy.isPersistedResponseItem(.eventMessage(.error)))
        XCTAssertTrue(RolloutPolicy.isPersistedResponseItem(.responseItem(.message(role: "assistant", content: []))))
        XCTAssertFalse(RolloutPolicy.isPersistedResponseItem(.responseItem(.other)))
    }

    private func minimalHookRunSummary() -> HookRunSummary {
        try! HookRunSummary(
            id: "run-1",
            eventName: .postToolUse,
            handlerType: .command,
            executionMode: .sync,
            scope: .turn,
            sourcePath: AbsolutePath(absolutePath: "/tmp/hook.json"),
            displayOrder: 0,
            status: .completed,
            statusMessage: nil,
            startedAt: 10,
            completedAt: 12,
            durationMs: 2,
            entries: []
        )
    }
}
