import CodexCore
import XCTest

final class EventMessageTests: XCTestCase {
    func testEventWrapperUsesRustIDAndMsgShape() throws {
        let event = Event(
            id: "submission-1",
            msg: .taskStarted(TaskStartedEvent(turnID: "turn-1", modelContextWindow: nil))
        )

        try XCTAssertJSONObjectEqual(event, [
            "id": "submission-1",
            "msg": [
                "type": "task_started",
                "turn_id": "turn-1",
                "model_context_window": NSNull(),
                "collaboration_mode_kind": "default"
            ]
        ])

        let data = try JSONEncoder().encode(event)
        XCTAssertEqual(
            try JSONDecoder().decode(Event.self, from: data),
            Event(id: "submission-1", msg: .taskStarted(TaskStartedEvent(
                turnID: "turn-1",
                modelContextWindow: nil,
                collaborationModeKind: .defaultMode
            )))
        )
    }

    func testTurnLifecycleAliasesAndTimingFieldsMatchRust() throws {
        let started = try JSONDecoder().decode(EventMessage.self, from: Data("""
        {
          "type": "turn_started",
          "turn_id": "turn-1",
          "started_at": 1778320000,
          "model_context_window": 128000,
          "collaboration_mode_kind": "plan"
        }
        """.utf8))

        XCTAssertEqual(started, .taskStarted(TaskStartedEvent(
            turnID: "turn-1",
            startedAt: 1_778_320_000,
            modelContextWindow: 128_000,
            collaborationModeKind: .plan
        )))

        let complete = EventMessage.taskComplete(TaskCompleteEvent(
            turnID: "turn-1",
            lastAgentMessage: "done",
            completedAt: 1_778_320_010,
            durationMilliseconds: 10_250,
            timeToFirstTokenMilliseconds: 300
        ))

        try XCTAssertJSONObjectEqual(complete, [
            "type": "task_complete",
            "turn_id": "turn-1",
            "last_agent_message": "done",
            "completed_at": 1_778_320_010,
            "duration_ms": 10_250,
            "time_to_first_token_ms": 300
        ])

        let decodedComplete = try JSONDecoder().decode(EventMessage.self, from: Data("""
        {
          "type": "turn_complete",
          "turn_id": "turn-1",
          "last_agent_message": "done",
          "completed_at": 1778320010,
          "duration_ms": 10250,
          "time_to_first_token_ms": 300
        }
        """.utf8))

        XCTAssertEqual(decodedComplete, complete)
    }

    func testTurnAbortedTimingFieldsMatchRust() throws {
        let aborted = EventMessage.turnAborted(TurnAbortedEvent(
            turnID: "turn-1",
            reason: .interrupted,
            completedAt: 1_778_320_020,
            durationMilliseconds: 12_500
        ))

        try XCTAssertJSONObjectEqual(aborted, [
            "type": "turn_aborted",
            "turn_id": "turn-1",
            "reason": "interrupted",
            "completed_at": 1_778_320_020,
            "duration_ms": 12_500
        ])

        let decoded = try JSONDecoder().decode(EventMessage.self, from: Data("""
        {
          "type": "turn_aborted",
          "turn_id": "turn-1",
          "reason": "interrupted",
          "completed_at": 1778320020,
          "duration_ms": 12500
        }
        """.utf8))

        XCTAssertEqual(decoded, aborted)
    }

    func testEventMessageFlattensPayloadFieldsBesideType() throws {
        let msg = EventMessage.error(ErrorEvent(
            message: "stream disconnected",
            codexErrorInfo: .responseStreamDisconnected(httpStatusCode: nil)
        ))

        try XCTAssertJSONObjectEqual(msg, [
            "type": "error",
            "message": "stream disconnected",
            "codex_error_info": [
                "response_stream_disconnected": [
                    "http_status_code": NSNull()
                ]
            ]
        ])

        let data = try JSONEncoder().encode(msg)
        XCTAssertEqual(try JSONDecoder().decode(EventMessage.self, from: data), msg)
    }

    func testEventMessageCoversGuardianWarningAndModelRoutingLikeRust() throws {
        let warning = EventMessage.guardianWarning(WarningEvent(message: "approval needed"))
        try XCTAssertJSONObjectEqual(warning, [
            "type": "guardian_warning",
            "message": "approval needed"
        ])

        let reroute = EventMessage.modelReroute(ModelRerouteEvent(
            fromModel: "gpt-5.4",
            toModel: "gpt-5.4-cyber",
            reason: .highRiskCyberActivity
        ))
        try XCTAssertJSONObjectEqual(reroute, [
            "type": "model_reroute",
            "from_model": "gpt-5.4",
            "to_model": "gpt-5.4-cyber",
            "reason": "high_risk_cyber_activity"
        ])

        let verification = try JSONDecoder().decode(EventMessage.self, from: Data("""
        {
          "type": "model_verification",
          "verifications": ["trusted_access_for_cyber"]
        }
        """.utf8))

        XCTAssertEqual(verification, .modelVerification(ModelVerificationEvent(
            verifications: [.trustedAccessForCyber]
        )))

        let data = try JSONEncoder().encode(reroute)
        XCTAssertEqual(try JSONDecoder().decode(EventMessage.self, from: data), reroute)
    }

    func testEventMessageCoversRealtimeConversationEventsLikeRust() throws {
        let started = EventMessage.realtimeConversationStarted(RealtimeConversationStartedEvent(
            realtimeSessionID: nil,
            version: .v2
        ))
        try XCTAssertJSONObjectEqual(started, [
            "type": "realtime_conversation_started",
            "realtime_session_id": NSNull(),
            "version": "v2"
        ])

        let realtime = EventMessage.realtimeConversationRealtime(RealtimeConversationRealtimeEvent(
            payload: .inputAudioSpeechStarted(RealtimeInputAudioSpeechStarted(itemID: "item-1"))
        ))
        try XCTAssertJSONObjectEqual(realtime, [
            "type": "realtime_conversation_realtime",
            "payload": [
                "InputAudioSpeechStarted": [
                    "item_id": "item-1"
                ]
            ]
        ])

        try XCTAssertJSONObjectEqual(EventMessage.realtimeConversationSdp(RealtimeConversationSdpEvent(
            sdp: "v=0"
        )), [
            "type": "realtime_conversation_sdp",
            "sdp": "v=0"
        ])

        try XCTAssertJSONObjectEqual(EventMessage.realtimeConversationClosed(RealtimeConversationClosedEvent()), [
            "type": "realtime_conversation_closed"
        ])

        let voices = EventMessage.realtimeConversationListVoicesResponse(RealtimeConversationListVoicesResponseEvent(
            voices: .builtin()
        ))
        try XCTAssertJSONObjectEqual(voices, [
            "type": "realtime_conversation_list_voices_response",
            "voices": [
                "v1": ["juniper", "maple", "spruce", "ember", "vale", "breeze", "arbor", "sol", "cove"],
                "v2": ["alloy", "ash", "ballad", "coral", "echo", "sage", "shimmer", "verse", "marin", "cedar"],
                "defaultV1": "cove",
                "defaultV2": "marin"
            ]
        ])

        for event in [started, realtime, voices] {
            let data = try JSONEncoder().encode(event)
            XCTAssertEqual(try JSONDecoder().decode(EventMessage.self, from: data), event)
        }
    }

    func testEventMessageCoversRequestAndDynamicToolEventsLikeRust() throws {
        let permissions = EventMessage.requestPermissions(RequestPermissionsEvent(
            callID: "perm-1",
            turnID: "turn-1",
            startedAtMilliseconds: 1_000,
            reason: "needs network",
            permissions: RequestPermissionProfile(network: RequestPermissionNetworkPermissions(enabled: true)),
            cwd: try AbsolutePath(absolutePath: "/repo")
        ))
        try XCTAssertJSONObjectEqual(permissions, [
            "type": "request_permissions",
            "call_id": "perm-1",
            "turn_id": "turn-1",
            "started_at_ms": 1_000,
            "reason": "needs network",
            "permissions": [
                "network": [
                    "enabled": true
                ]
            ],
            "cwd": "/repo"
        ])

        let relativeCwd = Data(#"""
        {
          "type": "request_permissions",
          "call_id": "perm-1",
          "turn_id": "turn-1",
          "started_at_ms": 1000,
          "permissions": { "network": { "enabled": true } },
          "cwd": "repo"
        }
        """#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(EventMessage.self, from: relativeCwd))

        let missingRequestPermissionsTiming = Data(#"""
        {
          "type": "request_permissions",
          "call_id": "perm-legacy",
          "permissions": { "network": { "enabled": true } }
        }
        """#.utf8)
        XCTAssertEqual(
            try JSONDecoder().decode(EventMessage.self, from: missingRequestPermissionsTiming),
            .requestPermissions(RequestPermissionsEvent(
                callID: "perm-legacy",
                permissions: RequestPermissionProfile(network: RequestPermissionNetworkPermissions(enabled: true))
            ))
        )

        let userInput = EventMessage.requestUserInput(RequestUserInputEvent(
            callID: "input-1",
            turnID: "turn-1",
            questions: [RequestUserInputQuestion(id: "choice", header: "Choice", question: "Pick one")]
        ))
        try XCTAssertJSONObjectEqual(userInput, [
            "type": "request_user_input",
            "call_id": "input-1",
            "turn_id": "turn-1",
            "questions": [
                [
                    "id": "choice",
                    "header": "Choice",
                    "question": "Pick one",
                    "isOther": false,
                    "isSecret": false
                ]
            ]
        ])

        let request = EventMessage.dynamicToolCallRequest(DynamicToolCallRequest(
            callID: "dyn-1",
            turnID: "turn-1",
            startedAtMilliseconds: 2_000,
            tool: "lookup",
            arguments: .object(["id": .string("ISSUE-1")])
        ))
        try XCTAssertJSONObjectEqual(request, [
            "type": "dynamic_tool_call_request",
            "callId": "dyn-1",
            "turnId": "turn-1",
            "startedAtMs": 2_000,
            "namespace": NSNull(),
            "tool": "lookup",
            "arguments": [
                "id": "ISSUE-1"
            ]
        ])

        let response = EventMessage.dynamicToolCallResponse(DynamicToolCallResponseEvent(
            callID: "dyn-1",
            turnID: "turn-1",
            completedAtMilliseconds: 2_250,
            tool: "lookup",
            arguments: .object(["id": .string("ISSUE-1")]),
            contentItems: [.text("done")],
            success: true,
            duration: ProtocolDuration(secs: 0, nanos: 250_000_000)
        ))
        try XCTAssertJSONObjectEqual(response, [
            "type": "dynamic_tool_call_response",
            "call_id": "dyn-1",
            "turn_id": "turn-1",
            "completed_at_ms": 2_250,
            "namespace": NSNull(),
            "tool": "lookup",
            "arguments": [
                "id": "ISSUE-1"
            ],
            "content_items": [
                [
                    "type": "inputText",
                    "text": "done"
                ]
            ],
            "success": true,
            "error": NSNull(),
            "duration": [
                "secs": 0,
                "nanos": 250_000_000
            ]
        ])

        for event in [permissions, userInput, request, response] {
            let data = try JSONEncoder().encode(event)
            XCTAssertEqual(try JSONDecoder().decode(EventMessage.self, from: data), event)
        }
    }

    func testEventMessageCoversHookPatchAndPlanDeltaEventsLikeRust() throws {
        let run = try HookRunSummary(
            id: "run-1",
            eventName: .postToolUse,
            handlerType: .command,
            executionMode: .sync,
            scope: .turn,
            sourcePath: AbsolutePath(absolutePath: "/tmp/hook.json"),
            displayOrder: 0,
            status: .completed,
            statusMessage: "done",
            startedAt: 10,
            completedAt: 12,
            durationMs: 2,
            entries: []
        )

        let hookStarted = EventMessage.hookStarted(HookStartedEvent(turnID: nil, run: run))
        let startedObject = try JSONObject(hookStarted)
        XCTAssertEqual(startedObject["type"] as? String, "hook_started")
        XCTAssertTrue(startedObject["turn_id"] is NSNull)
        XCTAssertNotNil(startedObject["run"])

        let hookCompleted = EventMessage.hookCompleted(HookCompletedEvent(turnID: "turn-1", run: run))
        let completedObject = try JSONObject(hookCompleted)
        XCTAssertEqual(completedObject["type"] as? String, "hook_completed")
        XCTAssertEqual(completedObject["turn_id"] as? String, "turn-1")
        XCTAssertNotNil(completedObject["run"])

        let patchUpdated = EventMessage.patchApplyUpdated(PatchApplyUpdatedEvent(
            callID: "patch-1",
            changes: [
                "Sources/New.swift": .add(content: "let x = 1\n")
            ]
        ))
        try XCTAssertJSONObjectEqual(patchUpdated, [
            "type": "patch_apply_updated",
            "call_id": "patch-1",
            "changes": [
                "Sources/New.swift": [
                    "type": "add",
                    "content": "let x = 1\n"
                ]
            ]
        ])

        let planDelta = EventMessage.planDelta(PlanDeltaEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            itemID: "item-1",
            delta: "step"
        ))
        try XCTAssertJSONObjectEqual(planDelta, [
            "type": "plan_delta",
            "thread_id": "thread-1",
            "turn_id": "turn-1",
            "item_id": "item-1",
            "delta": "step"
        ])

        for event in [hookStarted, hookCompleted, patchUpdated, planDelta] {
            let data = try JSONEncoder().encode(event)
            XCTAssertEqual(try JSONDecoder().decode(EventMessage.self, from: data), event)
        }
    }

    func testUnitEventMessagesUseTypeOnlyRustShape() throws {
        try XCTAssertJSONObjectEqual(EventMessage.contextCompacted(ContextCompactedEvent()), [
            "type": "context_compacted"
        ])
        try XCTAssertJSONObjectEqual(EventMessage.skillsUpdateAvailable, [
            "type": "skills_update_available"
        ])
        try XCTAssertJSONObjectEqual(EventMessage.shutdownComplete, [
            "type": "shutdown_complete"
        ])
    }

    func testEventMessageCoversPortedStreamingAndToolPayloads() throws {
        try XCTAssertJSONObjectEqual(EventMessage.execCommandOutputDelta(ExecCommandOutputDeltaEvent(
            callID: "exec-1",
            stream: .stderr,
            chunk: [0xde, 0xad]
        )), [
            "type": "exec_command_output_delta",
            "call_id": "exec-1",
            "stream": "stderr",
            "chunk": "3q0="
        ])

        try XCTAssertJSONObjectEqual(EventMessage.mcpToolCallBegin(McpToolCallBeginEvent(
            callID: "mcp-1",
            invocation: McpInvocation(
                server: "filesystem",
                tool: "read_file",
                arguments: .object(["path": .string("/tmp/a.txt")])
            )
        )), [
            "type": "mcp_tool_call_begin",
            "call_id": "mcp-1",
            "invocation": [
                "server": "filesystem",
                "tool": "read_file",
                "arguments": [
                    "path": "/tmp/a.txt"
                ]
            ]
        ])

        try XCTAssertJSONObjectEqual(EventMessage.imageGenerationBegin(ImageGenerationBeginEvent(
            callID: "ig-1"
        )), [
            "type": "image_generation_begin",
            "call_id": "ig-1"
        ])

        try XCTAssertJSONObjectEqual(EventMessage.imageGenerationEnd(ImageGenerationEndEvent(
            callID: "ig-1",
            status: "completed",
            revisedPrompt: "a clearer prompt",
            result: "base64-png",
            savedPath: try AbsolutePath(absolutePath: "/tmp/generated.png")
        )), [
            "type": "image_generation_end",
            "call_id": "ig-1",
            "status": "completed",
            "revised_prompt": "a clearer prompt",
            "result": "base64-png",
            "saved_path": "/tmp/generated.png"
        ])

        try XCTAssertJSONObjectEqual(EventMessage.agentMessageContentDelta(AgentMessageContentDeltaEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            itemID: "item-1",
            delta: "hi"
        )), [
            "type": "agent_message_content_delta",
            "thread_id": "thread-1",
            "turn_id": "turn-1",
            "item_id": "item-1",
            "delta": "hi"
        ])

        let message = try JSONDecoder().decode(EventMessage.self, from: Data("""
        {
          "type": "reasoning_content_delta",
          "thread_id": "thread-1",
          "turn_id": "turn-1",
          "item_id": "item-1",
          "delta": "thinking"
        }
        """.utf8))

        XCTAssertEqual(message, .reasoningContentDelta(ReasoningContentDeltaEvent(
            threadID: "thread-1",
            turnID: "turn-1",
            itemID: "item-1",
            delta: "thinking"
        )))

        let mcpEnd = try JSONDecoder().decode(EventMessage.self, from: Data("""
        {
          "type": "mcp_tool_call_end",
          "call_id": "mcp-1",
          "invocation": {
            "server": "filesystem",
            "tool": "read_file",
            "arguments": null
          },
          "duration": {
            "secs": 1,
            "nanos": 0
          },
          "result": {
            "Ok": {
              "content": [
                {
                  "type": "text",
                  "text": "done"
                }
              ]
            }
          }
        }
        """.utf8))

        XCTAssertEqual(mcpEnd, .mcpToolCallEnd(McpToolCallEndEvent(
            callID: "mcp-1",
            invocation: McpInvocation(server: "filesystem", tool: "read_file"),
            duration: ProtocolDuration(secs: 1),
            result: .ok(McpCallToolResult(content: [.text(McpTextContent(text: "done"))]))
        )))
    }

    func testEventMessageDecodesReviewAndPlanPayloads() throws {
        let plan = EventMessage.planUpdate(UpdatePlanArguments(
            explanation: "next",
            plan: [PlanItemArgument(step: "port", status: .inProgress)]
        ))

        try XCTAssertJSONObjectEqual(plan, [
            "type": "plan_update",
            "explanation": "next",
            "plan": [
                [
                    "step": "port",
                    "status": "in_progress"
                ]
            ]
        ])

        let review = try JSONDecoder().decode(EventMessage.self, from: Data("""
        {
          "type": "entered_review_mode",
          "target": {
            "type": "uncommittedChanges"
          }
        }
        """.utf8))

        XCTAssertEqual(review, .enteredReviewMode(ReviewRequest(target: .uncommittedChanges)))
    }

    func testEventMessageCarriesThreadGoalUpdatedLikeRust() throws {
        let threadID = try ThreadId(string: "018f7a2d-4c5b-7abc-8def-0123456789ab")
        let goal = ThreadGoal(
            threadID: threadID,
            objective: "port everything",
            status: .budgetLimited,
            tokensUsed: 42,
            timeUsedSeconds: 7,
            createdAt: 1_000,
            updatedAt: 2_000
        )
        let message = EventMessage.threadGoalUpdated(ThreadGoalUpdatedEvent(threadID: threadID, goal: goal))

        try XCTAssertJSONObjectEqual(message, [
            "type": "thread_goal_updated",
            "threadId": threadID.description,
            "goal": [
                "threadId": threadID.description,
                "objective": "port everything",
                "status": "budgetLimited",
                "tokenBudget": NSNull(),
                "tokensUsed": 42,
                "timeUsedSeconds": 7,
                "createdAt": 1_000,
                "updatedAt": 2_000
            ]
        ])

        let decoded = try JSONDecoder().decode(EventMessage.self, from: Data("""
        {
          "type": "thread_goal_updated",
          "threadId": "\(threadID.description)",
          "turnId": "turn-1",
          "goal": {
            "threadId": "\(threadID.description)",
            "objective": "ship parity",
            "status": "active",
            "tokenBudget": 1000,
            "tokensUsed": 12,
            "timeUsedSeconds": 34,
            "createdAt": 100,
            "updatedAt": 200
          }
        }
        """.utf8))

        XCTAssertEqual(decoded, .threadGoalUpdated(ThreadGoalUpdatedEvent(
            threadID: threadID,
            turnID: "turn-1",
            goal: ThreadGoal(
                threadID: threadID,
                objective: "ship parity",
                status: .active,
                tokenBudget: 1_000,
                tokensUsed: 12,
                timeUsedSeconds: 34,
                createdAt: 100,
                updatedAt: 200
            )
        )))
    }

    func testEventMessageCarriesGuardianAssessmentLikeRust() throws {
        let assessment = GuardianAssessmentEvent(
            id: "guardian-1",
            targetItemID: "item-1",
            turnID: "turn-1",
            startedAtMilliseconds: 123,
            status: .inProgress,
            action: .command(source: .unifiedExec, command: "git status", cwd: "/repo")
        )
        let message = EventMessage.guardianAssessment(assessment)

        try XCTAssertJSONObjectEqual(message, [
            "type": "guardian_assessment",
            "id": "guardian-1",
            "target_item_id": "item-1",
            "turn_id": "turn-1",
            "started_at_ms": 123,
            "status": "in_progress",
            "action": [
                "type": "command",
                "source": "unified_exec",
                "command": "git status",
                "cwd": "/repo"
            ]
        ])

        let data = try JSONEncoder().encode(message)
        XCTAssertEqual(try JSONDecoder().decode(EventMessage.self, from: data), message)
    }

    func testUnsupportedEventMessageVariantThrows() {
        XCTAssertThrowsError(try JSONDecoder().decode(
            EventMessage.self,
            from: Data(#"{"type":"future_unported_event"}"#.utf8)
        ))

        XCTAssertThrowsError(try JSONDecoder().decode(
            EventMessage.self,
            from: Data(#"{"type":"mcp_list_tools_response","tools":{},"resources":{},"resource_templates":{},"auth_statuses":{}}"#.utf8)
        ))

        XCTAssertThrowsError(try JSONDecoder().decode(
            EventMessage.self,
            from: Data(#"{"type":"list_skills_response","skills":[]}"#.utf8)
        ))
    }
}
