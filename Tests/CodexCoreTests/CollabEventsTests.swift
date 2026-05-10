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
}
