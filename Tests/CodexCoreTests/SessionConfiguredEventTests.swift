import CodexCore
import XCTest

final class SessionConfiguredEventTests: XCTestCase {
    func testSessionConfiguredWireShapeOmitsOptionalFields() throws {
        let sessionID = try ConversationId(string: "67e55044-10b1-426f-9247-bb680e5fe0c8")
        let event = SessionConfiguredEvent(
            sessionID: sessionID,
            model: "codex-mini-latest",
            modelProviderID: "openai",
            approvalPolicy: .never,
            sandboxPolicy: .readOnly,
            cwd: "/home/user/project",
            historyLogID: 0,
            historyEntryCount: 0,
            rolloutPath: "/tmp/rollout.jsonl"
        )

        try XCTAssertJSONObjectEqual(event, [
            "session_id": "67e55044-10b1-426f-9247-bb680e5fe0c8",
            "model": "codex-mini-latest",
            "model_provider_id": "openai",
            "approval_policy": "never",
            "sandbox_policy": [
                "type": "read-only"
            ],
            "cwd": "/home/user/project",
            "history_log_id": 0,
            "history_entry_count": 0,
            "rollout_path": "/tmp/rollout.jsonl"
        ])

        let data = try JSONEncoder().encode(event)
        XCTAssertEqual(try JSONDecoder().decode(SessionConfiguredEvent.self, from: data), event)
    }

    func testSessionConfiguredWireShapeIncludesReasoningAndInitialMessages() throws {
        let sessionID = try ConversationId(string: "67e55044-10b1-426f-9247-bb680e5fe0c8")
        let event = SessionConfiguredEvent(
            sessionID: sessionID,
            model: "gpt-5.4",
            modelProviderID: "openai",
            approvalPolicy: .onRequest,
            sandboxPolicy: .workspaceWrite(
                writableRoots: [try AbsolutePath(absolutePath: "/tmp/work")],
                networkAccess: true,
                excludeTmpdirEnvVar: true,
                excludeSlashTmp: false
            ),
            cwd: "/tmp/work",
            reasoningEffort: .high,
            historyLogID: 42,
            historyEntryCount: 7,
            initialMessages: [
                .userMessage(UserMessageEvent(message: "hello")),
                .agentMessage(AgentMessageEvent(message: "hi"))
            ],
            rolloutPath: "/tmp/rollout.jsonl"
        )

        try XCTAssertJSONObjectEqual(event, [
            "session_id": "67e55044-10b1-426f-9247-bb680e5fe0c8",
            "model": "gpt-5.4",
            "model_provider_id": "openai",
            "approval_policy": "on-request",
            "sandbox_policy": [
                "type": "workspace-write",
                "writable_roots": ["/tmp/work"],
                "network_access": true,
                "exclude_tmpdir_env_var": true,
                "exclude_slash_tmp": false
            ],
            "cwd": "/tmp/work",
            "reasoning_effort": "high",
            "history_log_id": 42,
            "history_entry_count": 7,
            "initial_messages": [
                [
                    "type": "user_message",
                    "message": "hello",
                    "local_images": [],
                    "text_elements": []
                ],
                [
                    "type": "agent_message",
                    "message": "hi"
                ]
            ],
            "rollout_path": "/tmp/rollout.jsonl"
        ])

        let data = try JSONEncoder().encode(event)
        XCTAssertEqual(try JSONDecoder().decode(SessionConfiguredEvent.self, from: data), event)
    }

    func testSessionConfiguredIsEventMessage() throws {
        let sessionID = try ConversationId(string: "67e55044-10b1-426f-9247-bb680e5fe0c8")
        let message = EventMessage.sessionConfigured(SessionConfiguredEvent(
            sessionID: sessionID,
            model: "codex-mini-latest",
            modelProviderID: "openai",
            approvalPolicy: .never,
            sandboxPolicy: .readOnly,
            cwd: "/home/user/project",
            reasoningEffort: .medium,
            historyLogID: 0,
            historyEntryCount: 0,
            rolloutPath: "/tmp/rollout.jsonl"
        ))

        try XCTAssertJSONObjectEqual(message, [
            "type": "session_configured",
            "session_id": "67e55044-10b1-426f-9247-bb680e5fe0c8",
            "model": "codex-mini-latest",
            "model_provider_id": "openai",
            "approval_policy": "never",
            "sandbox_policy": [
                "type": "read-only"
            ],
            "cwd": "/home/user/project",
            "reasoning_effort": "medium",
            "history_log_id": 0,
            "history_entry_count": 0,
            "rollout_path": "/tmp/rollout.jsonl"
        ])

        let data = try JSONEncoder().encode(message)
        XCTAssertEqual(try JSONDecoder().decode(EventMessage.self, from: data), message)
    }
}
