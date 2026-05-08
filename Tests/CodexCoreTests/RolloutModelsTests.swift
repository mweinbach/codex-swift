import CodexCore
import XCTest

final class RolloutModelsTests: XCTestCase {
    func testSessionMetaLineFlattensMetaAndOmitsMissingGit() throws {
        let id = try ConversationId(string: "67e55044-10b1-426f-9247-bb680e5fe0c8")
        let line = SessionMetaLine(meta: SessionMeta(
            id: id,
            timestamp: "2026-05-08T00:00:00Z",
            cwd: "/repo",
            originator: "codex_swift",
            cliVersion: "0.1.0",
            source: .cli,
            modelProvider: "openai"
        ))

        try XCTAssertJSONObjectEqual(line, [
            "id": "67e55044-10b1-426f-9247-bb680e5fe0c8",
            "timestamp": "2026-05-08T00:00:00Z",
            "cwd": "/repo",
            "originator": "codex_swift",
            "cli_version": "0.1.0",
            "instructions": NSNull(),
            "source": "cli",
            "model_provider": "openai"
        ])

        let data = try JSONEncoder().encode(line)
        XCTAssertEqual(try JSONDecoder().decode(SessionMetaLine.self, from: data), line)
    }

    func testSessionMetaDefaultsMissingSourceToVSCode() throws {
        let line = try JSONDecoder().decode(SessionMetaLine.self, from: Data("""
        {
          "id": "67e55044-10b1-426f-9247-bb680e5fe0c8",
          "timestamp": "",
          "cwd": "",
          "originator": "",
          "cli_version": "",
          "instructions": null,
          "model_provider": null
        }
        """.utf8))

        XCTAssertEqual(line.meta.source, .vscode)
        XCTAssertNil(line.git)
    }

    func testSessionMetaLineIncludesGitWhenPresent() throws {
        let id = try ConversationId(string: "67e55044-10b1-426f-9247-bb680e5fe0c8")
        let line = SessionMetaLine(
            meta: SessionMeta(
                id: id,
                timestamp: "2026-05-08T00:00:00Z",
                cwd: "/repo",
                originator: "codex_swift",
                cliVersion: "0.1.0",
                instructions: "be nice",
                source: .subagent(.review)
            ),
            git: GitInfo(commitHash: "abc123", branch: "main")
        )

        try XCTAssertJSONObjectEqual(line, [
            "id": "67e55044-10b1-426f-9247-bb680e5fe0c8",
            "timestamp": "2026-05-08T00:00:00Z",
            "cwd": "/repo",
            "originator": "codex_swift",
            "cli_version": "0.1.0",
            "instructions": "be nice",
            "source": [
                "subagent": "review"
            ],
            "model_provider": NSNull(),
            "git": [
                "commit_hash": "abc123",
                "branch": "main"
            ]
        ])
    }

    func testCompactedItemAndTruncationPolicyWireShapes() throws {
        try XCTAssertJSONObjectEqual(CompactedItem(message: "summary"), [
            "message": "summary"
        ])

        try XCTAssertJSONObjectEqual(CompactedItem(
            message: "summary",
            replacementHistory: [.message(role: "assistant", content: [.outputText(text: "kept")])]
        ), [
            "message": "summary",
            "replacement_history": [
                [
                    "type": "message",
                    "role": "assistant",
                    "content": [
                        [
                            "type": "output_text",
                            "text": "kept"
                        ]
                    ]
                ]
            ]
        ])

        try XCTAssertJSONObjectEqual(TruncationPolicy.bytes(4096), [
            "mode": "bytes",
            "limit": 4096
        ])
        try XCTAssertJSONObjectEqual(TruncationPolicy.tokens(1024), [
            "mode": "tokens",
            "limit": 1024
        ])

        let policy = try JSONDecoder().decode(TruncationPolicy.self, from: Data("""
        {
          "mode": "bytes",
          "limit": 2048
        }
        """.utf8))
        XCTAssertEqual(policy, .bytes(2048))
    }

    func testTurnContextItemWireShapeOmitsMissingOptionals() throws {
        let context = TurnContextItem(
            cwd: "/repo",
            approvalPolicy: .onRequest,
            sandboxPolicy: .readOnly,
            model: "gpt-5.4",
            summary: .auto
        )

        try XCTAssertJSONObjectEqual(context, [
            "cwd": "/repo",
            "approval_policy": "on-request",
            "sandbox_policy": [
                "type": "read-only"
            ],
            "model": "gpt-5.4",
            "summary": "auto"
        ])
    }

    func testTurnContextItemWireShapeIncludesOptionalFields() throws {
        let context = TurnContextItem(
            cwd: "/repo",
            approvalPolicy: .never,
            sandboxPolicy: .workspaceWrite(
                writableRoots: [],
                networkAccess: false,
                excludeTmpdirEnvVar: true,
                excludeSlashTmp: false
            ),
            model: "o3",
            effort: .high,
            summary: .detailed,
            baseInstructions: "base",
            userInstructions: "user",
            developerInstructions: "dev",
            finalOutputJSONSchema: .object(["type": .string("object")]),
            truncationPolicy: .tokens(2048)
        )

        try XCTAssertJSONObjectEqual(context, [
            "cwd": "/repo",
            "approval_policy": "never",
            "sandbox_policy": [
                "type": "workspace-write",
                "network_access": false,
                "exclude_tmpdir_env_var": true,
                "exclude_slash_tmp": false
            ],
            "model": "o3",
            "effort": "high",
            "summary": "detailed",
            "base_instructions": "base",
            "user_instructions": "user",
            "developer_instructions": "dev",
            "final_output_json_schema": [
                "type": "object"
            ],
            "truncation_policy": [
                "mode": "tokens",
                "limit": 2048
            ]
        ])
    }

    func testRolloutRecordItemUsesTypeAndPayloadWrapper() throws {
        let item = RolloutRecordItem.eventMsg(.warning(WarningEvent(message: "heads up")))

        try XCTAssertJSONObjectEqual(item, [
            "type": "event_msg",
            "payload": [
                "type": "warning",
                "message": "heads up"
            ]
        ])

        let data = try JSONEncoder().encode(item)
        XCTAssertEqual(try JSONDecoder().decode(RolloutRecordItem.self, from: data), item)
    }

    func testRolloutLineFlattensTimestampAndItemFields() throws {
        let line = RolloutLine(
            timestamp: "2026-05-08T00:00:00Z",
            item: .compacted(CompactedItem(message: "summary"))
        )

        try XCTAssertJSONObjectEqual(line, [
            "timestamp": "2026-05-08T00:00:00Z",
            "type": "compacted",
            "payload": [
                "message": "summary"
            ]
        ])

        let data = try JSONEncoder().encode(line)
        XCTAssertEqual(try JSONDecoder().decode(RolloutLine.self, from: data), line)
    }
}
