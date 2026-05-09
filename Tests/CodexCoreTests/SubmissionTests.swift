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
            permissionProfile: .managed(
                fileSystem: .unrestricted,
                network: .enabled
            ),
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
                "type": "managed",
                "file_system": [
                    "type": "unrestricted"
                ],
                "network": "enabled"
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
            permissionProfile: .managed(
                fileSystem: .restricted(entries: []),
                network: .restricted
            ),
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
                "type": "managed",
                "file_system": [
                    "type": "restricted",
                    "entries": []
                ],
                "network": "restricted"
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

    func testPermissionProfileTaggedAndLegacyWireShapesLikeRust() throws {
        let tagged = PermissionProfile.managed(
            fileSystem: .restricted(
                entries: [
                    FileSystemSandboxEntry(path: .globPattern("**/*.env"), access: .none)
                ],
                globScanMaxDepth: 2
            ),
            network: .restricted
        )

        try XCTAssertJSONObjectEqual(tagged, [
            "type": "managed",
            "file_system": [
                "type": "restricted",
                "entries": [
                    [
                        "path": [
                            "type": "glob_pattern",
                            "pattern": "**/*.env"
                        ],
                        "access": "none"
                    ]
                ],
                "glob_scan_max_depth": 2
            ],
            "network": "restricted"
        ])

        let legacy = try JSONDecoder().decode(PermissionProfile.self, from: Data(#"""
        {
            "network": {
                "enabled": true
            },
            "file_system": {
                "read": ["/repo"],
                "write": ["/repo/Sources"]
            }
        }
        """#.utf8))

        XCTAssertEqual(
            legacy,
            .managed(
                fileSystem: .restricted(
                    entries: [
                        FileSystemSandboxEntry(path: .path("/repo"), access: .read),
                        FileSystemSandboxEntry(path: .path("/repo/Sources"), access: .write)
                    ]
                ),
                network: .enabled
            )
        )
    }

    func testPermissionProfileHelperSemanticsLikeRust() {
        let managed = PermissionProfile.managed(fileSystem: .restricted(entries: []), network: .restricted)
        XCTAssertEqual(managed.enforcement, .managed)
        XCTAssertEqual(managed.networkSandboxPolicy, .restricted)
        XCTAssertFalse(managed.networkSandboxPolicy.isEnabled)

        let disabled = PermissionProfile.disabled
        XCTAssertEqual(disabled.enforcement, .disabled)
        XCTAssertEqual(disabled.networkSandboxPolicy, .enabled)
        XCTAssertTrue(disabled.networkSandboxPolicy.isEnabled)

        let external = PermissionProfile.external(network: .restricted)
        XCTAssertEqual(external.enforcement, .external)
        XCTAssertEqual(external.networkSandboxPolicy, .restricted)
    }

    func testPermissionProfileConstructorsMatchRust() throws {
        XCTAssertEqual(
            PermissionProfile.readOnly(),
            .managed(fileSystem: .readOnly(), network: .restricted)
        )

        let extraRoot = try AbsolutePath(absolutePath: "/repo/generated")
        let workspaceWrite = PermissionProfile.workspaceWriteWith(
            writableRoots: [extraRoot],
            network: .enabled,
            excludeTmpdirEnvVar: true,
            excludeSlashTmp: false
        )

        XCTAssertEqual(
            workspaceWrite,
            .managed(
                fileSystem: .restricted(entries: [
                    FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .read),
                    FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.projectRoots(subpath: nil).jsonValue), access: .write),
                    FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.slashTmp.jsonValue), access: .write),
                    FileSystemSandboxEntry(path: .path("/repo/generated"), access: .write),
                    FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.projectRoots(subpath: ".git").jsonValue), access: .read),
                    FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.projectRoots(subpath: ".agents").jsonValue), access: .read),
                    FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.projectRoots(subpath: ".codex").jsonValue), access: .read),
                    FileSystemSandboxEntry(path: .path("/repo/generated/.git"), access: .read),
                    FileSystemSandboxEntry(path: .path("/repo/generated/.agents"), access: .read),
                    FileSystemSandboxEntry(path: .path("/repo/generated/.codex"), access: .read)
                ]),
                network: .enabled
            )
        )
    }

    func testPermissionProfileFromLegacySandboxPolicyMatchesRust() throws {
        XCTAssertEqual(SandboxEnforcement.fromLegacySandboxPolicy(.dangerFullAccess), .disabled)
        XCTAssertEqual(SandboxEnforcement.fromLegacySandboxPolicy(.externalSandbox(networkAccess: .restricted)), .external)
        XCTAssertEqual(SandboxEnforcement.fromLegacySandboxPolicy(.readOnly), .managed)

        XCTAssertEqual(NetworkSandboxPolicy.fromLegacySandboxPolicy(.dangerFullAccess), .enabled)
        XCTAssertEqual(NetworkSandboxPolicy.fromLegacySandboxPolicy(.readOnly), .restricted)
        XCTAssertEqual(
            NetworkSandboxPolicy.fromLegacySandboxPolicy(.externalSandbox(networkAccess: .enabled)),
            .enabled
        )

        let writableRoot = try AbsolutePath(absolutePath: "/repo/out")
        let workspacePolicy = SandboxPolicy.workspaceWrite(
            writableRoots: [writableRoot],
            networkAccess: true,
            excludeTmpdirEnvVar: true,
            excludeSlashTmp: true
        )

        XCTAssertEqual(PermissionProfile.fromLegacySandboxPolicy(.dangerFullAccess), .disabled)
        XCTAssertEqual(
            PermissionProfile.fromLegacySandboxPolicy(.externalSandbox(networkAccess: .restricted)),
            .external(network: .restricted)
        )
        XCTAssertEqual(PermissionProfile.fromLegacySandboxPolicy(.readOnly), .readOnly())
        XCTAssertEqual(
            PermissionProfile.fromLegacySandboxPolicy(workspacePolicy),
            .workspaceWriteWith(
                writableRoots: [writableRoot],
                network: .enabled,
                excludeTmpdirEnvVar: true,
                excludeSlashTmp: true
            )
        )
    }

    func testPermissionProfileRuntimePermissionsMatchRust() throws {
        let readOnly = PermissionProfile.readOnly()
        XCTAssertEqual(readOnly.fileSystemSandboxPolicy, .restricted(entries: [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .read)
        ]))
        XCTAssertEqual(readOnly.runtimePermissions.network, .restricted)

        let unrestrictedManaged = PermissionProfile.managed(fileSystem: .unrestricted, network: .restricted)
        XCTAssertEqual(unrestrictedManaged.fileSystemSandboxPolicy, .unrestricted)
        XCTAssertEqual(unrestrictedManaged.runtimePermissions.network, .restricted)

        let disabled = PermissionProfile.disabled
        XCTAssertEqual(disabled.fileSystemSandboxPolicy, .unrestricted)
        XCTAssertEqual(disabled.runtimePermissions.network, .enabled)

        let external = PermissionProfile.external(network: .restricted)
        XCTAssertEqual(external.fileSystemSandboxPolicy, .externalSandbox)
        XCTAssertEqual(external.runtimePermissions.network, .restricted)
    }

    func testFileSystemSpecialPathParsesRustAliasesAndUnknowns() {
        XCTAssertEqual(FileSystemSpecialPath(jsonValue: .object(["kind": .string("root")])), .root)
        XCTAssertEqual(
            FileSystemSpecialPath(jsonValue: .object(["kind": .string("current_working_directory")])),
            .projectRoots(subpath: nil)
        )
        XCTAssertEqual(
            FileSystemSpecialPath(jsonValue: .object([
                "kind": .string("project_roots"),
                "subpath": .string("Sources")
            ])),
            .projectRoots(subpath: "Sources")
        )
        XCTAssertEqual(
            FileSystemSpecialPath(jsonValue: .object([
                "kind": .string("future_token"),
                "subpath": .string("nested")
            ])),
            .unknown(path: "future_token", subpath: "nested")
        )
        XCTAssertEqual(FileSystemSpecialPath.projectRoots(subpath: nil).jsonValue, .object([
            "kind": .string("project_roots")
        ]))
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
            permissionProfile: .external(network: .restricted),
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
                "type": "external",
                "network": "restricted"
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
