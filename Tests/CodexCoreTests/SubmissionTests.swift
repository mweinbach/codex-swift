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

    func testSubmissionTraceContextIsOptionalAndUsesRustWireShape() throws {
        let submission = Submission(
            id: "sub-2",
            op: .interrupt,
            trace: W3CTraceContext(
                traceparent: "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00",
                tracestate: "vendor=value"
            )
        )

        try XCTAssertJSONObjectEqual(submission, [
            "id": "sub-2",
            "op": [
                "type": "interrupt"
            ],
            "trace": [
                "traceparent": "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00",
                "tracestate": "vendor=value"
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
            approvalsReviewer: .string("native"),
            sandboxPolicy: .workspaceWrite(
                writableRoots: [try AbsolutePath(absolutePath: "/repo/out")],
                networkAccess: true,
                excludeTmpdirEnvVar: false,
                excludeSlashTmp: true
            ),
            permissionProfile: .object([
                "kind": .string("workspace")
            ]),
            model: "o3",
            effort: .high,
            summary: .detailed,
            serviceTier: .null,
            finalOutputJSONSchema: .object([
                "type": .string("object"),
                "required": .array([.string("answer")])
            ]),
            collaborationMode: .string("pair"),
            personality: .string("direct"),
            environments: [TurnEnvironmentSelection(environmentID: "env-2", cwd: "/repo")]
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
            "approvals_reviewer": "native",
            "sandbox_policy": [
                "type": "workspace-write",
                "writable_roots": ["/repo/out"],
                "network_access": true,
                "exclude_tmpdir_env_var": false,
                "exclude_slash_tmp": true
            ],
            "permission_profile": [
                "kind": "workspace"
            ],
            "model": "o3",
            "effort": "high",
            "summary": "detailed",
            "service_tier": NSNull(),
            "final_output_json_schema": [
                "type": "object",
                "required": ["answer"]
            ],
            "collaboration_mode": "pair",
            "personality": "direct",
            "environments": [
                [
                    "environment_id": "env-2",
                    "cwd": "/repo"
                ]
            ]
        ])

        let data = try JSONEncoder().encode(op)
        XCTAssertEqual(try JSONDecoder().decode(Op.self, from: data), op)
    }

    func testUserInputWithTurnContextWireShapePreservesOptionalOverrides() throws {
        let op = Op.userInputWithTurnContext(UserInputWithTurnContextParams(
            items: [.text("ship it")],
            environments: [TurnEnvironmentSelection(environmentID: "env-1", cwd: "/repo")],
            finalOutputJSONSchema: .object([
                "type": .string("object")
            ]),
            responsesAPIClientMetadata: ["surface": "app"],
            cwd: "/repo",
            approvalPolicy: .onRequest,
            approvalsReviewer: .string("native"),
            sandboxPolicy: .readOnly,
            permissionProfile: .object([
                "type": .string("managed")
            ]),
            activePermissionProfile: ActivePermissionProfile(
                id: ":workspace",
                modifications: [.additionalWritableRoot(path: "/repo/tmp")]
            ),
            windowsSandboxLevel: .string("read_only"),
            model: "gpt-5.4",
            effort: .null,
            summary: .auto,
            serviceTier: .null,
            collaborationMode: .string("default"),
            personality: .string("codex")
        ))

        try XCTAssertJSONObjectEqual(op, [
            "type": "user_input_with_turn_context",
            "items": [
                [
                    "type": "text",
                    "text": "ship it"
                ]
            ],
            "environments": [
                [
                    "environment_id": "env-1",
                    "cwd": "/repo"
                ]
            ],
            "final_output_json_schema": [
                "type": "object"
            ],
            "responsesapi_client_metadata": [
                "surface": "app"
            ],
            "cwd": "/repo",
            "approval_policy": "on-request",
            "approvals_reviewer": "native",
            "sandbox_policy": [
                "type": "read-only"
            ],
            "permission_profile": [
                "type": "managed"
            ],
            "active_permission_profile": [
                "id": ":workspace",
                "modifications": [
                    [
                        "type": "additional_writable_root",
                        "path": "/repo/tmp"
                    ]
                ]
            ],
            "windows_sandbox_level": "read_only",
            "model": "gpt-5.4",
            "effort": NSNull(),
            "summary": "auto",
            "service_tier": NSNull(),
            "collaboration_mode": "default",
            "personality": "codex"
        ])

        let data = try JSONEncoder().encode(op)
        XCTAssertEqual(try JSONDecoder().decode(Op.self, from: data), op)
    }

    func testActivePermissionProfileDefaultsMatchRustSerde() throws {
        let json = #"{"id":":workspace"}"#
        let profile = try JSONDecoder().decode(ActivePermissionProfile.self, from: Data(json.utf8))

        XCTAssertEqual(profile, ActivePermissionProfile(id: ":workspace"))
        XCTAssertTrue(profile.modifications.isEmpty)
        try XCTAssertJSONObjectEqual(profile, [
            "id": ":workspace"
        ])
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
            approvalsReviewer: .string("guardian"),
            sandboxPolicy: .readOnly,
            permissionProfile: .object([
                "type": .string("readonly")
            ]),
            windowsSandboxLevel: .string("read_only"),
            model: "gpt-5.4",
            effort: .set(.low),
            summary: .concise,
            serviceTier: .null,
            collaborationMode: .string("solo"),
            personality: .string("codex")
        ), [
            "type": "override_turn_context",
            "cwd": "/repo",
            "approval_policy": "on-failure",
            "approvals_reviewer": "guardian",
            "sandbox_policy": [
                "type": "read-only"
            ],
            "permission_profile": [
                "type": "readonly"
            ],
            "windows_sandbox_level": "read_only",
            "model": "gpt-5.4",
            "effort": "low",
            "summary": "concise",
            "service_tier": NSNull(),
            "collaboration_mode": "solo",
            "personality": "codex"
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
        try XCTAssertJSONObjectEqual(Op.execApproval(id: "exec-1", turnID: "turn-1", decision: .approved), [
            "type": "exec_approval",
            "id": "exec-1",
            "turn_id": "turn-1",
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
            decision: .accept,
            content: .object([
                "answer": .string("yes")
            ]),
            meta: .null
        ), [
            "type": "resolve_elicitation",
            "server_name": "mcp",
            "request_id": 7,
            "decision": "accept",
            "content": [
                "answer": "yes"
            ],
            "meta": NSNull()
        ])
    }

    func testApproveGuardianDeniedActionWireShape() throws {
        let op = Op.approveGuardianDeniedAction(event: GuardianAssessmentEvent(
            id: "guardian-1",
            turnID: "turn-1",
            startedAtMilliseconds: 1_234,
            status: .denied,
            riskLevel: .high,
            action: .command(source: .shell, command: "rm -rf build", cwd: "/repo")
        ))

        try XCTAssertJSONObjectEqual(op, [
            "type": "approve_guardian_denied_action",
            "event": [
                "id": "guardian-1",
                "turn_id": "turn-1",
                "started_at_ms": 1_234,
                "status": "denied",
                "risk_level": "high",
                "action": [
                    "type": "command",
                    "source": "shell",
                    "command": "rm -rf build",
                    "cwd": "/repo"
                ]
            ]
        ])

        let data = try JSONEncoder().encode(op)
        XCTAssertEqual(try JSONDecoder().decode(Op.self, from: data), op)
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
