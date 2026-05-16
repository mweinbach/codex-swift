import CodexCore
import XCTest

final class RolloutModelsTests: XCTestCase {
    func testSessionMetaLineFlattensMetaAndOmitsMissingGit() throws {
        let id = try ConversationId(string: "67e55044-10b1-426f-9247-bb680e5fe0c8")
        let forkedID = try ConversationId(string: "77e55044-10b1-426f-9247-bb680e5fe0c8")
        let line = SessionMetaLine(meta: SessionMeta(
            id: id,
            forkedFromID: forkedID,
            timestamp: "2026-05-08T00:00:00Z",
            cwd: "/repo",
            originator: "codex_swift",
            cliVersion: "0.1.0",
            source: .cli,
            threadSource: .subagent,
            agentNickname: "reviewer",
            agentRole: "analyst",
            agentPath: "/root/reviewer",
            modelProvider: "openai",
            baseInstructions: BaseInstructions(text: "base"),
            dynamicTools: [
                DynamicToolSpec(name: "lookup", description: "Look up things", inputSchema: .object([:]))
            ],
            memoryMode: "read_write"
        ))

        try XCTAssertJSONObjectEqual(line, [
            "id": "67e55044-10b1-426f-9247-bb680e5fe0c8",
            "forked_from_id": "77e55044-10b1-426f-9247-bb680e5fe0c8",
            "timestamp": "2026-05-08T00:00:00Z",
            "cwd": "/repo",
            "originator": "codex_swift",
            "cli_version": "0.1.0",
            "instructions": NSNull(),
            "source": "cli",
            "thread_source": "subagent",
            "agent_nickname": "reviewer",
            "agent_role": "analyst",
            "agent_path": "/root/reviewer",
            "model_provider": "openai",
            "base_instructions": [
                "text": "base"
            ],
            "dynamic_tools": [[
                "name": "lookup",
                "description": "Look up things",
                "inputSchema": [:]
            ]],
            "memory_mode": "read_write"
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
        XCTAssertNil(line.meta.forkedFromID)
        XCTAssertNil(line.meta.threadSource)
        XCTAssertNil(line.meta.agentNickname)
        XCTAssertNil(line.meta.agentRole)
        XCTAssertNil(line.meta.agentPath)
        XCTAssertNil(line.meta.dynamicTools)
        XCTAssertNil(line.meta.memoryMode)
        XCTAssertNil(line.git)
    }

    func testSessionMetaRejectsNullRustDefaultedSourceLikeSerde() throws {
        XCTAssertThrowsError(try JSONDecoder().decode(SessionMetaLine.self, from: Data("""
        {
          "id": "67e55044-10b1-426f-9247-bb680e5fe0c8",
          "timestamp": "",
          "cwd": "",
          "originator": "",
          "cli_version": "",
          "source": null,
          "model_provider": null
        }
        """.utf8))) { error in
            guard case DecodingError.valueNotFound = error else {
                return XCTFail("expected valueNotFound, got \(error)")
            }
        }
    }

    func testInitialHistoryReturnsFirstSessionMetaDynamicToolsLikeRust() throws {
        let id = try ConversationId(string: "67e55044-10b1-426f-9247-bb680e5fe0c8")
        let dynamicTools = [
            DynamicToolSpec(
                namespace: "codex_app",
                name: "lookup",
                description: "Look up things",
                inputSchema: .object(["type": .string("object")]),
                deferLoading: true
            )
        ]
        let firstMeta = RolloutRecordItem.sessionMeta(SessionMetaLine(meta: SessionMeta(
            id: id,
            timestamp: "2026-05-08T00:00:00Z",
            cwd: "/repo",
            originator: "codex_swift",
            cliVersion: "0.1.0",
            dynamicTools: dynamicTools
        )))
        let laterMeta = RolloutRecordItem.sessionMeta(SessionMetaLine(meta: SessionMeta(
            id: id,
            timestamp: "2026-05-08T00:00:01Z",
            cwd: "/repo",
            originator: "codex_swift",
            cliVersion: "0.1.0",
            dynamicTools: [
                DynamicToolSpec(name: "later", description: "Later", inputSchema: .object([:]))
            ]
        )))

        XCTAssertEqual(
            InitialHistory.resumed(ResumedHistory(conversationID: id, history: [firstMeta, laterMeta], rolloutPath: nil))
                .dynamicTools,
            dynamicTools
        )
        XCTAssertEqual(InitialHistory.forked([firstMeta]).dynamicTools, dynamicTools)
        XCTAssertNil(InitialHistory.new.dynamicTools)
        XCTAssertNil(InitialHistory.cleared.dynamicTools)
    }

    func testInitialHistoryProjectsFirstSessionMetaHelpersLikeRust() throws {
        let id = try ConversationId(string: "67e55044-10b1-426f-9247-bb680e5fe0c8")
        let forkedID = try ConversationId(string: "77e55044-10b1-426f-9247-bb680e5fe0c8")
        let firstMeta = RolloutRecordItem.sessionMeta(SessionMetaLine(meta: SessionMeta(
            id: id,
            forkedFromID: forkedID,
            timestamp: "2026-05-08T00:00:00Z",
            cwd: "/first",
            originator: "codex_swift",
            cliVersion: "0.1.0",
            threadSource: .user,
            baseInstructions: BaseInstructions(text: "base")
        )))
        let laterMeta = RolloutRecordItem.sessionMeta(SessionMetaLine(meta: SessionMeta(
            id: try ConversationId(string: "87e55044-10b1-426f-9247-bb680e5fe0c8"),
            timestamp: "2026-05-08T00:00:01Z",
            cwd: "/later",
            originator: "codex_swift",
            cliVersion: "0.1.0",
            threadSource: .subagent,
            baseInstructions: BaseInstructions(text: "later base")
        )))
        let turnContext = RolloutRecordItem.turnContext(TurnContextItem(
            cwd: "/turn-context",
            approvalPolicy: .onRequest,
            sandboxPolicy: .readOnly,
            model: "gpt-5.4",
            summary: .auto
        ))

        let resumed = InitialHistory.resumed(ResumedHistory(
            conversationID: id,
            history: [turnContext, firstMeta, laterMeta],
            rolloutPath: nil
        ))
        XCTAssertEqual(resumed.forkedFromID, forkedID)
        XCTAssertEqual(resumed.sessionCwd, "/first")
        XCTAssertEqual(resumed.baseInstructions, BaseInstructions(text: "base"))
        XCTAssertEqual(resumed.resumedThreadSource, .user)

        let forked = InitialHistory.forked([turnContext, firstMeta, laterMeta])
        XCTAssertEqual(forked.forkedFromID, id)
        XCTAssertEqual(forked.sessionCwd, "/first")
        XCTAssertEqual(forked.baseInstructions, BaseInstructions(text: "base"))
        XCTAssertNil(forked.resumedThreadSource)

        XCTAssertNil(InitialHistory.new.forkedFromID)
        XCTAssertNil(InitialHistory.new.sessionCwd)
        XCTAssertNil(InitialHistory.new.baseInstructions)
        XCTAssertNil(InitialHistory.new.resumedThreadSource)
        XCTAssertNil(InitialHistory.cleared.forkedFromID)
        XCTAssertNil(InitialHistory.cleared.sessionCwd)
        XCTAssertNil(InitialHistory.cleared.baseInstructions)
        XCTAssertNil(InitialHistory.cleared.resumedThreadSource)
    }

    func testSessionMetaDecodesAgentTypeAliasForAgentRole() throws {
        let line = try JSONDecoder().decode(SessionMetaLine.self, from: Data("""
        {
          "id": "67e55044-10b1-426f-9247-bb680e5fe0c8",
          "timestamp": "",
          "cwd": "",
          "originator": "",
          "cli_version": "",
          "source": "cli",
          "thread_source": "memory_consolidation",
          "agent_type": "critic",
          "model_provider": null
        }
        """.utf8))

        XCTAssertEqual(line.meta.threadSource, .memoryConsolidation)
        XCTAssertEqual(line.meta.agentRole, "critic")
    }

    func testSessionMetaRejectsDuplicateAgentRoleAliasLikeSerde() throws {
        XCTAssertThrowsError(try JSONDecoder().decode(SessionMetaLine.self, from: Data("""
        {
          "id": "67e55044-10b1-426f-9247-bb680e5fe0c8",
          "timestamp": "",
          "cwd": "",
          "originator": "",
          "cli_version": "",
          "source": "cli",
          "agent_role": "analyst",
          "agent_type": "critic",
          "model_provider": null
        }
        """.utf8))) { error in
            guard case let DecodingError.dataCorrupted(context) = error else {
                return XCTFail("expected dataCorrupted, got \(error)")
            }
            XCTAssertEqual(context.debugDescription, "duplicate field `agent_role`")
        }
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
            "base_instructions": NSNull(),
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

    func testTurnContextItemOmitsActivePermissionProfileLikeRustRollout() throws {
        let context = TurnContextItem(
            cwd: "/repo",
            approvalPolicy: .onRequest,
            sandboxPolicy: .readOnly,
            permissionProfile: .readOnly(),
            activePermissionProfile: ActivePermissionProfile(id: ":read-only"),
            model: "gpt-5.4",
            summary: .auto
        )

        try XCTAssertJSONObjectEqual(context, [
            "cwd": "/repo",
            "approval_policy": "on-request",
            "sandbox_policy": [
                "type": "read-only"
            ],
            "permission_profile": [
                "type": "managed",
                "file_system": [
                    "type": "restricted",
                    "entries": [
                        [
                            "path": [
                                "type": "special",
                                "value": [
                                    "kind": "root"
                                ]
                            ],
                            "access": "read"
                        ]
                    ]
                ],
                "network": "restricted"
            ],
            "model": "gpt-5.4",
            "summary": "auto"
        ])
    }

    func testTurnContextItemDecodesLegacyActivePermissionProfile() throws {
        let json = #"""
        {
            "cwd": "/repo",
            "approval_policy": "on-request",
            "sandbox_policy": {
                "type": "read-only"
            },
            "active_permission_profile": {
                "id": ":read-only",
                "modifications": []
            },
            "model": "gpt-5.4",
            "summary": "auto"
        }
        """#

        let context = try JSONDecoder().decode(TurnContextItem.self, from: Data(json.utf8))
        XCTAssertEqual(context.activePermissionProfile, ActivePermissionProfile(id: ":read-only"))
    }

    func testTurnContextItemWireShapeIncludesOptionalFields() throws {
        let context = TurnContextItem(
            turnID: "turn-1",
            traceID: "trace-1",
            cwd: "/repo",
            currentDate: "2026-05-09",
            timezone: "America/New_York",
            approvalPolicy: .never,
            sandboxPolicy: .workspaceWrite(
                writableRoots: [],
                networkAccess: false,
                excludeTmpdirEnvVar: true,
                excludeSlashTmp: false
            ),
            permissionProfile: .managed(
                fileSystem: .restricted(entries: [
                    FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .read)
                ]),
                network: .restricted
            ),
            network: TurnContextNetworkItem(
                allowedDomains: ["api.openai.com"],
                deniedDomains: ["example.test"]
            ),
            fileSystemSandboxPolicy: .restricted(
                entries: [
                    FileSystemSandboxEntry(path: .path("/repo"), access: .write)
                ],
                globScanMaxDepth: 3
            ),
            model: "o3",
            personality: .friendly,
            collaborationMode: CollaborationMode(
                mode: .plan,
                settings: CollaborationModeSettings(
                    model: "o3",
                    reasoningEffort: .high,
                    developerInstructions: "plan first"
                )
            ),
            realtimeActive: true,
            effort: .high,
            summary: .detailed,
            userInstructions: "user",
            developerInstructions: "dev",
            finalOutputJSONSchema: .object(["type": .string("object")]),
            truncationPolicy: .tokens(2048)
        )

        try XCTAssertJSONObjectEqual(context, [
            "turn_id": "turn-1",
            "trace_id": "trace-1",
            "cwd": "/repo",
            "current_date": "2026-05-09",
            "timezone": "America/New_York",
            "approval_policy": "never",
            "sandbox_policy": [
                "type": "workspace-write",
                "network_access": false,
                "exclude_tmpdir_env_var": true,
                "exclude_slash_tmp": false
            ],
            "permission_profile": [
                "type": "managed",
                "file_system": [
                    "type": "restricted",
                    "entries": [
                        [
                            "path": [
                                "type": "special",
                                "value": [
                                    "kind": "root"
                                ]
                            ],
                            "access": "read"
                        ]
                    ]
                ],
                "network": "restricted"
            ],
            "network": [
                "allowed_domains": ["api.openai.com"],
                "denied_domains": ["example.test"]
            ],
            "file_system_sandbox_policy": [
                "kind": "restricted",
                "glob_scan_max_depth": 3,
                "entries": [
                    [
                        "path": [
                            "type": "path",
                            "path": "/repo"
                        ],
                        "access": "write"
                    ]
                ]
            ],
            "model": "o3",
            "personality": "friendly",
            "collaboration_mode": [
                "mode": "plan",
                "settings": [
                    "model": "o3",
                    "reasoning_effort": "high",
                    "developer_instructions": "plan first"
                ]
            ],
            "realtime_active": true,
            "effort": "high",
            "summary": "detailed",
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

        let data = try JSONEncoder().encode(context)
        XCTAssertEqual(try JSONDecoder().decode(TurnContextItem.self, from: data), context)
        XCTAssertEqual(context.effectivePermissionProfile, context.permissionProfile)
    }

    func testTurnContextItemDerivesPermissionProfileFromRuntimePolicyLikeRust() {
        let runtimePolicy = FileSystemSandboxPolicy.externalSandbox
        let context = TurnContextItem(
            cwd: "/repo",
            approvalPolicy: .onRequest,
            sandboxPolicy: .readOnly,
            fileSystemSandboxPolicy: runtimePolicy,
            model: "gpt-5.4",
            summary: .auto
        )

        XCTAssertEqual(context.effectivePermissionProfile, .external(network: .restricted))
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

    func testConversationPathResponseWireShape() throws {
        let id = try ConversationId(string: "67e55044-10b1-426f-9247-bb680e5fe0c8")
        let event = ConversationPathResponseEvent(
            conversationID: id,
            path: "/repo/.codex/sessions/session.jsonl"
        )

        try XCTAssertJSONObjectEqual(event, [
            "conversation_id": "67e55044-10b1-426f-9247-bb680e5fe0c8",
            "path": "/repo/.codex/sessions/session.jsonl"
        ])

        let data = try JSONEncoder().encode(event)
        XCTAssertEqual(try JSONDecoder().decode(ConversationPathResponseEvent.self, from: data), event)
    }

    func testInitialHistoryUsesRustExternalTagsAndExtractsEvents() throws {
        let id = try ConversationId(string: "67e55044-10b1-426f-9247-bb680e5fe0c8")
        let eventItem = RolloutRecordItem.eventMsg(.warning(WarningEvent(message: "heads up")))
        let responseItem = RolloutRecordItem.responseItem(.message(
            role: "assistant",
            content: [.outputText(text: "kept")]
        ))
        let resumed = ResumedHistory(
            conversationID: id,
            history: [eventItem, responseItem],
            rolloutPath: "/repo/.codex/sessions/session.jsonl"
        )

        let newData = try JSONEncoder().encode(InitialHistory.new)
        XCTAssertEqual(String(data: newData, encoding: .utf8), #""New""#)
        XCTAssertEqual(try JSONDecoder().decode(InitialHistory.self, from: newData), .new)
        XCTAssertEqual(InitialHistory.new.rolloutItems, [])
        XCTAssertNil(InitialHistory.new.eventMessages)

        let clearedData = try JSONEncoder().encode(InitialHistory.cleared)
        XCTAssertEqual(String(data: clearedData, encoding: .utf8), #""Cleared""#)
        XCTAssertEqual(try JSONDecoder().decode(InitialHistory.self, from: clearedData), .cleared)
        XCTAssertEqual(InitialHistory.cleared.rolloutItems, [])
        XCTAssertNil(InitialHistory.cleared.eventMessages)

        try XCTAssertJSONObjectEqual(InitialHistory.resumed(resumed), [
            "Resumed": [
                "conversation_id": "67e55044-10b1-426f-9247-bb680e5fe0c8",
                "history": [
                    [
                        "type": "event_msg",
                        "payload": [
                            "type": "warning",
                            "message": "heads up"
                        ]
                    ],
                    [
                        "type": "response_item",
                        "payload": [
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
                ],
                "rollout_path": "/repo/.codex/sessions/session.jsonl"
            ]
        ])

        let resumedHistory = InitialHistory.resumed(resumed)
        XCTAssertEqual(resumedHistory.rolloutItems, [eventItem, responseItem])
        XCTAssertEqual(resumedHistory.eventMessages, [.warning(WarningEvent(message: "heads up"))])

        let nilRolloutPath = ResumedHistory(
            conversationID: id,
            history: [eventItem],
            rolloutPath: nil
        )
        try XCTAssertJSONObjectEqual(InitialHistory.resumed(nilRolloutPath), [
            "Resumed": [
                "conversation_id": "67e55044-10b1-426f-9247-bb680e5fe0c8",
                "history": [
                    [
                        "type": "event_msg",
                        "payload": [
                            "type": "warning",
                            "message": "heads up"
                        ]
                    ]
                ],
                "rollout_path": NSNull()
            ]
        ])
        let nilPathJSON = #"{"Resumed":{"conversation_id":"67e55044-10b1-426f-9247-bb680e5fe0c8","history":[],"rollout_path":null}}"#
        XCTAssertEqual(
            try JSONDecoder().decode(InitialHistory.self, from: Data(nilPathJSON.utf8)),
            .resumed(ResumedHistory(conversationID: id, history: [], rolloutPath: nil))
        )

        let forkedHistory = InitialHistory.forked([responseItem, eventItem])
        try XCTAssertJSONObjectEqual(forkedHistory, [
            "Forked": [
                [
                    "type": "response_item",
                    "payload": [
                        "type": "message",
                        "role": "assistant",
                        "content": [
                            [
                                "type": "output_text",
                                "text": "kept"
                            ]
                        ]
                    ]
                ],
                [
                    "type": "event_msg",
                    "payload": [
                        "type": "warning",
                        "message": "heads up"
                    ]
                ]
            ]
        ])

        let forkedData = try JSONEncoder().encode(forkedHistory)
        XCTAssertEqual(try JSONDecoder().decode(InitialHistory.self, from: forkedData), forkedHistory)
        XCTAssertEqual(forkedHistory.eventMessages, [.warning(WarningEvent(message: "heads up"))])
    }
}
