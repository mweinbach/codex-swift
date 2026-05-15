import CodexCore
import XCTest

final class CollabEventsTests: XCTestCase {
    private let sender = try! ThreadId(string: "018f7a2d-4c5b-7abc-8def-0123456789ab")
    private let receiver = try! ThreadId(string: "018f7a2d-4c5b-7abc-8def-0123456789ac")

    func testAgentStatusUsesRustExternalTagShape() throws {
        try XCTAssertJSONObjectEqual(["status": AgentStatus.running], [
            "status": "running"
        ])
        try XCTAssertJSONObjectEqual(["status": AgentStatus.completed(nil)], [
            "status": [
                "completed": NSNull()
            ]
        ])
        try XCTAssertJSONObjectEqual(["status": AgentStatus.errored("boom")], [
            "status": [
                "errored": "boom"
            ]
        ])

        XCTAssertEqual(try JSONDecoder().decode(AgentStatus.self, from: Data(#""pending_init""#.utf8)), .pendingInit)
        XCTAssertEqual(try JSONDecoder().decode(AgentStatus.self, from: Data(#"{"completed":"done"}"#.utf8)), .completed("done"))
    }

    func testAgentStatusDerivesFromStatusChangingEventsLikeRust() {
        XCTAssertEqual(
            AgentStatus.from(eventMessage: .taskStarted(TaskStartedEvent(turnID: "turn-1", modelContextWindow: nil))),
            .running
        )
        XCTAssertEqual(
            AgentStatus.from(eventMessage: .taskComplete(TaskCompleteEvent(turnID: "turn-1", lastAgentMessage: "done"))),
            .completed("done")
        )
        XCTAssertEqual(
            AgentStatus.from(eventMessage: .taskComplete(TaskCompleteEvent(turnID: "turn-1", lastAgentMessage: nil))),
            .completed(nil)
        )
        XCTAssertEqual(
            AgentStatus.from(eventMessage: .error(ErrorEvent(message: "boom"))),
            .errored("boom")
        )
        XCTAssertEqual(
            AgentStatus.from(eventMessage: .shutdownComplete),
            .shutdown
        )
    }

    func testAgentStatusDerivesAbortReasonsLikeRust() {
        XCTAssertEqual(
            AgentStatus.from(eventMessage: .turnAborted(TurnAbortedEvent(reason: .interrupted))),
            .interrupted
        )
        XCTAssertEqual(
            AgentStatus.from(eventMessage: .turnAborted(TurnAbortedEvent(reason: .budgetLimited))),
            .interrupted
        )
        XCTAssertEqual(
            AgentStatus.from(eventMessage: .turnAborted(TurnAbortedEvent(reason: .replaced))),
            .errored("Replaced")
        )
        XCTAssertEqual(
            AgentStatus.from(eventMessage: .turnAborted(TurnAbortedEvent(reason: .reviewEnded))),
            .errored("ReviewEnded")
        )
    }

    func testAgentStatusIgnoresNonStatusEventsAndFinalityMatchesRust() {
        XCTAssertNil(AgentStatus.from(eventMessage: .warning(WarningEvent(message: "heads up"))))

        XCTAssertFalse(AgentStatus.pendingInit.isFinal)
        XCTAssertFalse(AgentStatus.running.isFinal)
        XCTAssertFalse(AgentStatus.interrupted.isFinal)
        XCTAssertTrue(AgentStatus.completed(nil).isFinal)
        XCTAssertTrue(AgentStatus.errored("boom").isFinal)
        XCTAssertTrue(AgentStatus.shutdown.isFinal)
        XCTAssertTrue(AgentStatus.notFound.isFinal)
    }

    func testCollabSpawnEventsUseRustWireShapeAndDefaults() throws {
        let begin = CollabAgentSpawnBeginEvent(
            callID: "spawn-1",
            senderThreadID: sender,
            prompt: "help",
            model: "gpt-5.4",
            reasoningEffort: .medium
        )

        try XCTAssertJSONObjectEqual(begin, [
            "call_id": "spawn-1",
            "started_at_ms": 0,
            "sender_thread_id": sender.description,
            "prompt": "help",
            "model": "gpt-5.4",
            "reasoning_effort": "medium"
        ])

        let end = CollabAgentSpawnEndEvent(
            callID: "spawn-1",
            senderThreadID: sender,
            newThreadID: receiver,
            newAgentNickname: "reviewer",
            newAgentRole: "code-reviewer",
            prompt: "help",
            model: "gpt-5.4",
            reasoningEffort: .medium,
            status: .completed("done")
        )

        try XCTAssertJSONObjectEqual(end, [
            "call_id": "spawn-1",
            "completed_at_ms": 0,
            "sender_thread_id": sender.description,
            "new_thread_id": receiver.description,
            "new_agent_nickname": "reviewer",
            "new_agent_role": "code-reviewer",
            "prompt": "help",
            "model": "gpt-5.4",
            "reasoning_effort": "medium",
            "status": [
                "completed": "done"
            ]
        ])
    }

    func testCollabAgentMetadataRejectsDuplicateAgentRoleAliasLikeSerde() throws {
        XCTAssertThrowsError(try JSONDecoder().decode(CollabAgentRef.self, from: Data("""
        {
          "thread_id": "\(receiver.description)",
          "agent_role": "reviewer",
          "agent_type": "critic"
        }
        """.utf8))) { error in
            guard case let DecodingError.dataCorrupted(context) = error else {
                return XCTFail("expected dataCorrupted, got \(error)")
            }
            XCTAssertEqual(context.debugDescription, "duplicate field `agent_role`")
        }

        XCTAssertThrowsError(try JSONDecoder().decode(CollabAgentStatusEntry.self, from: Data("""
        {
          "thread_id": "\(receiver.description)",
          "agent_role": "reviewer",
          "agent_type": "critic",
          "status": "running"
        }
        """.utf8))) { error in
            guard case let DecodingError.dataCorrupted(context) = error else {
                return XCTFail("expected dataCorrupted, got \(error)")
            }
            XCTAssertEqual(context.debugDescription, "duplicate field `agent_role`")
        }
    }

    func testCollabWaitingEventsOmitEmptyMetadataAndDecodeAliases() throws {
        let begin = CollabWaitingBeginEvent(
            senderThreadID: sender,
            receiverThreadIDs: [receiver],
            callID: "wait-1"
        )

        try XCTAssertJSONObjectEqual(begin, [
            "started_at_ms": 0,
            "sender_thread_id": sender.description,
            "receiver_thread_ids": [receiver.description],
            "call_id": "wait-1"
        ])

        let decodedRef = try JSONDecoder().decode(CollabAgentRef.self, from: Data("""
        {
          "thread_id": "\(receiver.description)",
          "agent_nickname": "reviewer",
          "agent_type": "code-reviewer"
        }
        """.utf8))
        XCTAssertEqual(decodedRef.agentRole, "code-reviewer")

        let end = CollabWaitingEndEvent(
            senderThreadID: sender,
            callID: "wait-1",
            agentStatuses: [
                CollabAgentStatusEntry(
                    threadID: receiver,
                    agentNickname: "reviewer",
                    agentRole: "code-reviewer",
                    status: .running
                )
            ],
            statuses: [receiver: .running]
        )

        try XCTAssertJSONObjectEqual(end, [
            "sender_thread_id": sender.description,
            "call_id": "wait-1",
            "completed_at_ms": 0,
            "agent_statuses": [
                [
                    "thread_id": receiver.description,
                    "agent_nickname": "reviewer",
                    "agent_role": "code-reviewer",
                    "status": "running"
                ]
            ],
            "statuses": [
                receiver.description: "running"
            ]
        ])
    }

    func testCollabEventsDefaultMissingRustTimingFields() throws {
        let spawnBegin = try JSONDecoder().decode(CollabAgentSpawnBeginEvent.self, from: Data("""
        {
          "call_id": "spawn-1",
          "sender_thread_id": "\(sender.description)",
          "prompt": "help",
          "model": "gpt-5.4",
          "reasoning_effort": "medium"
        }
        """.utf8))
        XCTAssertEqual(spawnBegin.startedAtMilliseconds, 0)

        let spawnEnd = try JSONDecoder().decode(CollabAgentSpawnEndEvent.self, from: Data("""
        {
          "call_id": "spawn-1",
          "sender_thread_id": "\(sender.description)",
          "new_thread_id": "\(receiver.description)",
          "prompt": "help",
          "model": "gpt-5.4",
          "reasoning_effort": "medium",
          "status": "running"
        }
        """.utf8))
        XCTAssertEqual(spawnEnd.completedAtMilliseconds, 0)

        let waitingBegin = try JSONDecoder().decode(CollabWaitingBeginEvent.self, from: Data("""
        {
          "sender_thread_id": "\(sender.description)",
          "receiver_thread_ids": ["\(receiver.description)"],
          "call_id": "wait-1"
        }
        """.utf8))
        XCTAssertEqual(waitingBegin.startedAtMilliseconds, 0)
        XCTAssertEqual(waitingBegin.receiverAgents, [])

        let waitingEnd = try JSONDecoder().decode(CollabWaitingEndEvent.self, from: Data("""
        {
          "sender_thread_id": "\(sender.description)",
          "call_id": "wait-1",
          "statuses": {
            "\(receiver.description)": "running"
          }
        }
        """.utf8))
        XCTAssertEqual(waitingEnd.completedAtMilliseconds, 0)
        XCTAssertEqual(waitingEnd.agentStatuses, [])
    }

    func testCollabEventsRejectNullRustDefaultedTimingFields() {
        let payloads = [
            (
                "collab_agent_spawn_begin",
                """
            {
              "call_id": "spawn-1",
              "started_at_ms": null,
              "sender_thread_id": "\(sender.description)",
              "prompt": "help",
              "model": "gpt-5.4",
              "reasoning_effort": "medium"
            }
            """
            ),
            (
                "collab_agent_spawn_end",
                """
            {
              "call_id": "spawn-1",
              "completed_at_ms": null,
              "sender_thread_id": "\(sender.description)",
              "new_thread_id": "\(receiver.description)",
              "prompt": "help",
              "model": "gpt-5.4",
              "reasoning_effort": "medium",
              "status": "running"
            }
            """
            ),
            (
                "collab_agent_interaction_begin",
                """
            {
              "call_id": "interact-1",
              "started_at_ms": null,
              "sender_thread_id": "\(sender.description)",
              "receiver_thread_id": "\(receiver.description)",
              "prompt": "status?"
            }
            """
            ),
            (
                "collab_agent_interaction_end",
                """
            {
              "call_id": "interact-1",
              "completed_at_ms": null,
              "sender_thread_id": "\(sender.description)",
              "receiver_thread_id": "\(receiver.description)",
              "prompt": "status?",
              "status": "running"
            }
            """
            ),
            (
                "collab_waiting_begin",
                """
            {
              "started_at_ms": null,
              "sender_thread_id": "\(sender.description)",
              "receiver_thread_ids": ["\(receiver.description)"],
              "call_id": "wait-1"
            }
            """
            ),
            (
                "collab_waiting_end",
                """
            {
              "sender_thread_id": "\(sender.description)",
              "call_id": "wait-1",
              "completed_at_ms": null,
              "statuses": {
                "\(receiver.description)": "running"
              }
            }
            """
            ),
            (
                "collab_close_begin",
                """
            {
              "call_id": "close-1",
              "started_at_ms": null,
              "sender_thread_id": "\(sender.description)",
              "receiver_thread_id": "\(receiver.description)"
            }
            """
            ),
            (
                "collab_close_end",
                """
            {
              "call_id": "close-1",
              "completed_at_ms": null,
              "sender_thread_id": "\(sender.description)",
              "receiver_thread_id": "\(receiver.description)",
              "status": "shutdown"
            }
            """
            ),
            (
                "collab_resume_begin",
                """
            {
              "call_id": "resume-1",
              "started_at_ms": null,
              "sender_thread_id": "\(sender.description)",
              "receiver_thread_id": "\(receiver.description)"
            }
            """
            ),
            (
                "collab_resume_end",
                """
            {
              "call_id": "resume-1",
              "completed_at_ms": null,
              "sender_thread_id": "\(sender.description)",
              "receiver_thread_id": "\(receiver.description)",
              "status": "running"
            }
            """
            )
        ]

        for (type, payload) in payloads {
            XCTAssertThrowsError(try JSONDecoder().decode(EventMessage.self, from: Data(payloadWithType(type, payload).utf8)))
        }
    }

    func testCollabWaitingEventsRejectNullRustDefaultedMetadataArrays() {
        let waitingBegin = """
        {
          "type": "collab_waiting_begin",
          "sender_thread_id": "\(sender.description)",
          "receiver_thread_ids": ["\(receiver.description)"],
          "receiver_agents": null,
          "call_id": "wait-1"
        }
        """
        let waitingEnd = """
        {
          "type": "collab_waiting_end",
          "sender_thread_id": "\(sender.description)",
          "call_id": "wait-1",
          "agent_statuses": null,
          "statuses": {
            "\(receiver.description)": "running"
          }
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(EventMessage.self, from: Data(waitingBegin.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(EventMessage.self, from: Data(waitingEnd.utf8)))
    }

    func testCollabCloseResumeAndInteractionEventsRoundTrip() throws {
        let events: [EventMessage] = [
            .collabAgentInteractionBegin(CollabAgentInteractionBeginEvent(
                callID: "interact-1",
                senderThreadID: sender,
                receiverThreadID: receiver,
                prompt: "status?"
            )),
            .collabAgentInteractionEnd(CollabAgentInteractionEndEvent(
                callID: "interact-1",
                senderThreadID: sender,
                receiverThreadID: receiver,
                prompt: "status?",
                status: .interrupted
            )),
            .collabCloseBegin(CollabCloseBeginEvent(
                callID: "close-1",
                senderThreadID: sender,
                receiverThreadID: receiver
            )),
            .collabCloseEnd(CollabCloseEndEvent(
                callID: "close-1",
                senderThreadID: sender,
                receiverThreadID: receiver,
                status: .shutdown
            )),
            .collabResumeBegin(CollabResumeBeginEvent(
                callID: "resume-1",
                senderThreadID: sender,
                receiverThreadID: receiver
            )),
            .collabResumeEnd(CollabResumeEndEvent(
                callID: "resume-1",
                senderThreadID: sender,
                receiverThreadID: receiver,
                status: .running
            ))
        ]

        for event in events {
            let data = try JSONEncoder().encode(event)
            XCTAssertEqual(try JSONDecoder().decode(EventMessage.self, from: data), event)
        }
    }

    private func payloadWithType(_ type: String, _ payload: String) -> String {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = trimmed.dropFirst().dropLast()
        return "{ \"type\": \"\(type)\", \(body) }"
    }
}
