import CodexCore
import XCTest

final class SubmissionTests: XCTestCase {
    func testSubmissionWrapsTaggedOperation() throws {
        let submission = Submission(id: "sub-1", op: .userInput(items: [.text("hello")]))

        try XCTAssertJSONObjectEqual(submission, [
            "id": "sub-1",
            "op": [
                "type": "user_input",
                "items": [
                    [
                        "type": "text",
                        "text": "hello"
                    ]
                ]
            ]
        ])

        let data = try JSONEncoder().encode(submission)
        XCTAssertEqual(try JSONDecoder().decode(Submission.self, from: data), submission)
    }

    func testUnitOperationsUseRustTagsOnly() throws {
        let cases: [(Op, [String: Any])] = [
            (.interrupt, ["type": "interrupt"]),
            (.cleanBackgroundTerminals, ["type": "clean_background_terminals"]),
            (.listMcpTools, ["type": "list_mcp_tools"]),
            (.listCustomPrompts, ["type": "list_custom_prompts"]),
            (.compact, ["type": "compact"]),
            (.reloadUserConfig, ["type": "reload_user_config"]),
            (.undo, ["type": "undo"]),
            (.shutdown, ["type": "shutdown"]),
            (.listModels, ["type": "list_models"])
        ]

        for (op, expected) in cases {
            try XCTAssertJSONObjectEqual(op, expected)
            let data = try JSONEncoder().encode(op)
            XCTAssertEqual(try JSONDecoder().decode(Op.self, from: data), op)
        }
    }

    func testUserTurnWireShapeIncludesNullSchemaAndOmitsMissingEffort() throws {
        let op = Op.userTurn(
            items: [.text("build")],
            cwd: "/repo",
            approvalPolicy: .onRequest,
            sandboxPolicy: .readOnly,
            model: "gpt-5.4",
            effort: nil,
            summary: .auto,
            finalOutputJSONSchema: nil
        )

        try XCTAssertJSONObjectEqual(op, [
            "type": "user_turn",
            "items": [
                [
                    "type": "text",
                    "text": "build"
                ]
            ],
            "cwd": "/repo",
            "approval_policy": "on-request",
            "sandbox_policy": [
                "type": "read-only"
            ],
            "model": "gpt-5.4",
            "summary": "auto",
            "final_output_json_schema": NSNull()
        ])
    }

    func testUserTurnWireShapeWithReasoningAndSchema() throws {
        let op = Op.userTurn(
            items: [.localImage(path: "/tmp/a.png")],
            cwd: "/repo",
            approvalPolicy: .never,
            sandboxPolicy: .workspaceWrite(
                writableRoots: [try AbsolutePath(absolutePath: "/repo/out")],
                networkAccess: true,
                excludeTmpdirEnvVar: false,
                excludeSlashTmp: true
            ),
            model: "o3",
            effort: .high,
            summary: .detailed,
            finalOutputJSONSchema: .object([
                "type": .string("object"),
                "required": .array([.string("answer")])
            ])
        )

        try XCTAssertJSONObjectEqual(op, [
            "type": "user_turn",
            "items": [
                [
                    "type": "local_image",
                    "path": "/tmp/a.png"
                ]
            ],
            "cwd": "/repo",
            "approval_policy": "never",
            "sandbox_policy": [
                "type": "workspace-write",
                "writable_roots": ["/repo/out"],
                "network_access": true,
                "exclude_tmpdir_env_var": false,
                "exclude_slash_tmp": true
            ],
            "model": "o3",
            "effort": "high",
            "summary": "detailed",
            "final_output_json_schema": [
                "type": "object",
                "required": ["answer"]
            ]
        ])

        let data = try JSONEncoder().encode(op)
        XCTAssertEqual(try JSONDecoder().decode(Op.self, from: data), op)
    }

    func testOverrideTurnContextOmittedSetAndClearEffortWireShapes() throws {
        try XCTAssertJSONObjectEqual(Op.overrideTurnContext(
            cwd: nil,
            approvalPolicy: nil,
            sandboxPolicy: nil,
            model: nil,
            effort: nil,
            summary: nil
        ), [
            "type": "override_turn_context"
        ])

        try XCTAssertJSONObjectEqual(Op.overrideTurnContext(
            cwd: "/repo",
            approvalPolicy: .onFailure,
            sandboxPolicy: .readOnly,
            model: "gpt-5.4",
            effort: .set(.low),
            summary: .concise
        ), [
            "type": "override_turn_context",
            "cwd": "/repo",
            "approval_policy": "on-failure",
            "sandbox_policy": [
                "type": "read-only"
            ],
            "model": "gpt-5.4",
            "effort": "low",
            "summary": "concise"
        ])

        let clear = Op.overrideTurnContext(
            cwd: nil,
            approvalPolicy: nil,
            sandboxPolicy: nil,
            model: nil,
            effort: .clear,
            summary: nil
        )
        try XCTAssertJSONObjectEqual(clear, [
            "type": "override_turn_context",
            "effort": NSNull()
        ])

        let data = try JSONEncoder().encode(clear)
        XCTAssertEqual(try JSONDecoder().decode(Op.self, from: data), clear)
    }

    func testApprovalAndElicitationOperationsWireShape() throws {
        try XCTAssertJSONObjectEqual(Op.execApproval(id: "exec-1", decision: .approved), [
            "type": "exec_approval",
            "id": "exec-1",
            "decision": "approved"
        ])

        try XCTAssertJSONObjectEqual(Op.patchApproval(id: "patch-1", decision: .denied), [
            "type": "patch_approval",
            "id": "patch-1",
            "decision": "denied"
        ])

        try XCTAssertJSONObjectEqual(Op.resolveElicitation(
            serverName: "mcp",
            requestID: .integer(7),
            decision: .accept
        ), [
            "type": "resolve_elicitation",
            "server_name": "mcp",
            "request_id": 7,
            "decision": "accept"
        ])
    }

    func testHistorySkillsReviewAndShellOperationsWireShape() throws {
        try XCTAssertJSONObjectEqual(Op.addToHistory(text: "remember this"), [
            "type": "add_to_history",
            "text": "remember this"
        ])

        try XCTAssertJSONObjectEqual(Op.getHistoryEntryRequest(offset: 4, logID: 99), [
            "type": "get_history_entry_request",
            "offset": 4,
            "log_id": 99
        ])

        try XCTAssertJSONObjectEqual(Op.listSkills(cwds: [], forceReload: false), [
            "type": "list_skills"
        ])

        try XCTAssertJSONObjectEqual(Op.listSkills(cwds: ["/repo"], forceReload: true), [
            "type": "list_skills",
            "cwds": ["/repo"],
            "force_reload": true
        ])

        try XCTAssertJSONObjectEqual(Op.review(reviewRequest: ReviewRequest(target: .uncommittedChanges)), [
            "type": "review",
            "review_request": [
                "target": [
                    "type": "uncommittedChanges"
                ]
            ]
        ])

        try XCTAssertJSONObjectEqual(Op.runUserShellCommand(command: "ls -la"), [
            "type": "run_user_shell_command",
            "command": "ls -la"
        ])
    }

    func testThreadControlOperationsWireShape() throws {
        let enableMemory = Op.setThreadMemoryMode(mode: .enabled)
        try XCTAssertJSONObjectEqual(enableMemory, [
            "type": "set_thread_memory_mode",
            "mode": "enabled"
        ])

        let disableMemory = Op.setThreadMemoryMode(mode: .disabled)
        try XCTAssertJSONObjectEqual(disableMemory, [
            "type": "set_thread_memory_mode",
            "mode": "disabled"
        ])

        let rollback = Op.threadRollback(numTurns: 3)
        try XCTAssertJSONObjectEqual(rollback, [
            "type": "thread_rollback",
            "num_turns": 3
        ])

        for op in [enableMemory, disableMemory, rollback] {
            let data = try JSONEncoder().encode(op)
            XCTAssertEqual(try JSONDecoder().decode(Op.self, from: data), op)
        }
    }

    func testListSkillsDefaultsDecodeLikeSerdeDefaults() throws {
        let decoded = try JSONDecoder().decode(Op.self, from: Data(#"{"type":"list_skills"}"#.utf8))
        XCTAssertEqual(decoded, .listSkills(cwds: [], forceReload: false))
    }
}
