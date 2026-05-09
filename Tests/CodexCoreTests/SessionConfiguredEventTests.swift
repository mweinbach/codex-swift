import CodexCore
import XCTest

final class SessionConfiguredEventTests: XCTestCase {
    private var rootReadEntry: [String: Any] {
        [
            "path": [
                "type": "special",
                "value": [
                    "kind": "root"
                ]
            ],
            "access": "read"
        ]
    }

    private func specialEntry(kind: String, access: String, subpath: String? = nil) -> [String: Any] {
        var value: [String: Any] = [
            "kind": kind
        ]
        if let subpath {
            value["subpath"] = subpath
        }
        return [
            "path": [
                "type": "special",
                "value": value
            ],
            "access": access
        ]
    }

    private func pathEntry(_ path: String, access: String) -> [String: Any] {
        [
            "path": [
                "type": "path",
                "path": path
            ],
            "access": access
        ]
    }

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
            "thread_id": "67e55044-10b1-426f-9247-bb680e5fe0c8",
            "model": "codex-mini-latest",
            "model_provider_id": "openai",
            "approval_policy": "never",
            "approvals_reviewer": "user",
            "permission_profile": [
                "type": "managed",
                "file_system": [
                    "type": "restricted",
                    "entries": [
                        rootReadEntry
                    ]
                ],
                "network": "restricted"
            ],
            "cwd": "/home/user/project",
            "rollout_path": "/tmp/rollout.jsonl"
        ])

        let data = try JSONEncoder().encode(event)
        XCTAssertEqual(try JSONDecoder().decode(SessionConfiguredEvent.self, from: data), event)
    }

    func testSessionConfiguredWireShapeIncludesReasoningAndInitialMessages() throws {
        let sessionID = try ConversationId(string: "67e55044-10b1-426f-9247-bb680e5fe0c8")
        let forkedFromID = try ThreadId(string: "77e55044-10b1-426f-9247-bb680e5fe0c8")
        let event = SessionConfiguredEvent(
            sessionID: sessionID,
            forkedFromID: forkedFromID,
            threadSource: .subagent,
            threadName: "Fix build",
            model: "gpt-5.4",
            modelProviderID: "openai",
            serviceTier: "flex",
            approvalPolicy: .onRequest,
            approvalsReviewer: .autoReview,
            activePermissionProfile: ActivePermissionProfile(id: ":workspace"),
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
            networkProxy: SessionNetworkProxyRuntime(httpAddr: "127.0.0.1:18080", socksAddr: "127.0.0.1:18081"),
            rolloutPath: "/tmp/rollout.jsonl"
        )

        try XCTAssertJSONObjectEqual(event, [
            "session_id": "67e55044-10b1-426f-9247-bb680e5fe0c8",
            "thread_id": "67e55044-10b1-426f-9247-bb680e5fe0c8",
            "forked_from_id": "77e55044-10b1-426f-9247-bb680e5fe0c8",
            "thread_source": "subagent",
            "thread_name": "Fix build",
            "model": "gpt-5.4",
            "model_provider_id": "openai",
            "service_tier": "flex",
            "approval_policy": "on-request",
            "approvals_reviewer": "guardian_subagent",
            "permission_profile": [
                "type": "managed",
                "file_system": [
                    "type": "restricted",
                    "entries": [
                        rootReadEntry,
                        specialEntry(kind: "project_roots", access: "write"),
                        specialEntry(kind: "slash_tmp", access: "write"),
                        pathEntry("/tmp/work", access: "write"),
                        specialEntry(kind: "project_roots", access: "read", subpath: ".git"),
                        specialEntry(kind: "project_roots", access: "read", subpath: ".agents"),
                        specialEntry(kind: "project_roots", access: "read", subpath: ".codex"),
                        pathEntry("/tmp/work/.git", access: "read"),
                        pathEntry("/tmp/work/.agents", access: "read"),
                        pathEntry("/tmp/work/.codex", access: "read")
                    ]
                ],
                "network": "enabled"
            ],
            "active_permission_profile": [
                "id": ":workspace"
            ],
            "cwd": "/tmp/work",
            "reasoning_effort": "high",
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
            "network_proxy": [
                "http_addr": "127.0.0.1:18080",
                "socks_addr": "127.0.0.1:18081"
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
            "thread_id": "67e55044-10b1-426f-9247-bb680e5fe0c8",
            "model": "codex-mini-latest",
            "model_provider_id": "openai",
            "approval_policy": "never",
            "approvals_reviewer": "user",
            "permission_profile": [
                "type": "managed",
                "file_system": [
                    "type": "restricted",
                    "entries": [
                        rootReadEntry
                    ]
                ],
                "network": "restricted"
            ],
            "cwd": "/home/user/project",
            "reasoning_effort": "medium",
            "rollout_path": "/tmp/rollout.jsonl"
        ])

        let data = try JSONEncoder().encode(message)
        XCTAssertEqual(try JSONDecoder().decode(EventMessage.self, from: data), message)
    }

    func testLegacySessionConfiguredDecodesSandboxPolicy() throws {
        let json = """
        {
          "session_id": "67e55044-10b1-426f-9247-bb680e5fe0c8",
          "model": "codex-mini-latest",
          "model_provider_id": "openai",
          "approval_policy": "never",
          "sandbox_policy": {
            "type": "read-only"
          },
          "cwd": "/home/user/project"
        }
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(SessionConfiguredEvent.self, from: json)

        XCTAssertEqual(event.threadID, ThreadId(uuid: event.sessionID.uuid))
        XCTAssertEqual(event.approvalsReviewer, .user)
        XCTAssertEqual(event.sandboxPolicy, .readOnly)
        XCTAssertEqual(event.permissionProfile, .readOnly())
    }

    func testApprovalsReviewerAcceptsLegacyAlias() throws {
        let json = """
        {
          "session_id": "67e55044-10b1-426f-9247-bb680e5fe0c8",
          "thread_id": "67e55044-10b1-426f-9247-bb680e5fe0c8",
          "model": "codex-mini-latest",
          "model_provider_id": "openai",
          "approval_policy": "never",
          "approvals_reviewer": "auto_review",
          "permission_profile": {
            "type": "managed",
            "file_system": {
              "type": "restricted",
              "entries": []
            },
            "network": "restricted"
          },
          "cwd": "/home/user/project"
        }
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(SessionConfiguredEvent.self, from: json)

        XCTAssertEqual(event.approvalsReviewer, .autoReview)
        let data = try JSONEncoder().encode(event.approvalsReviewer)
        XCTAssertEqual(String(data: data, encoding: .utf8), #""guardian_subagent""#)
    }
}
