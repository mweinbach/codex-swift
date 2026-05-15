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
                        "text": "hello",
                        "text_elements": []
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

    func testResponsesClientMetadataMergesTraceContextLikeRust() {
        let metadata = ResponsesClientMetadata.create(
            clientMetadata: [
                "origin": "app",
                ResponsesClientMetadata.wsRequestHeaderTraceparentKey: "old-parent"
            ],
            trace: W3CTraceContext(
                traceparent: "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00",
                tracestate: "vendor=value"
            )
        )

        XCTAssertEqual(metadata?["origin"], "app")
        XCTAssertEqual(
            metadata?[ResponsesClientMetadata.wsRequestHeaderTraceparentKey],
            "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00"
        )
        XCTAssertEqual(metadata?[ResponsesClientMetadata.wsRequestHeaderTracestateKey], "vendor=value")
    }

    func testResponsesClientMetadataReturnsNilWhenEmptyLikeRust() {
        XCTAssertNil(ResponsesClientMetadata.create())
        XCTAssertEqual(
            ResponsesClientMetadata.create(trace: W3CTraceContext(tracestate: "vendor=value")),
            [ResponsesClientMetadata.wsRequestHeaderTracestateKey: "vendor=value"]
        )
    }

    func testW3CTraceContextReadsValidEnvironmentLikeRust() {
        let trace = W3CTraceContext.fromEnvironment([
            "TRACEPARENT": "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
            "TRACESTATE": "vendor=value"
        ])

        XCTAssertEqual(
            trace,
            W3CTraceContext(
                traceparent: "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
                tracestate: "vendor=value"
            )
        )
    }

    func testW3CTraceContextIgnoresMissingOrInvalidTraceparentLikeRust() {
        XCTAssertNil(W3CTraceContext.fromEnvironment(["TRACESTATE": "vendor=value"]))
        XCTAssertNil(W3CTraceContext.fromEnvironment(["TRACEPARENT": "not-a-traceparent"]))
        XCTAssertNil(W3CTraceContext.fromEnvironment([
            "TRACEPARENT": "00-00000000000000000000000000000000-00f067aa0ba902b7-01"
        ]))
        XCTAssertNil(W3CTraceContext.fromEnvironment([
            "TRACEPARENT": "00-4bf92f3577b34da6a3ce929d0e0e4736-0000000000000000-01"
        ]))
    }

    func testUnitOperationsUseRustTagsOnly() throws {
        let cases: [(Op, [String: Any])] = [
            (.interrupt, ["type": "interrupt"]),
            (.cleanBackgroundTerminals, ["type": "clean_background_terminals"]),
            (.listCustomPrompts, ["type": "list_custom_prompts"]),
            (.compact, ["type": "compact"]),
            (.reloadUserConfig, ["type": "reload_user_config"]),
            (.undo, ["type": "undo"]),
            (.shutdown, ["type": "shutdown"])
        ]

        for (op, expected) in cases {
            try XCTAssertJSONObjectEqual(op, expected)
            let data = try JSONEncoder().encode(op)
            XCTAssertEqual(try JSONDecoder().decode(Op.self, from: data), op)
        }
    }

    func testRefreshRuntimeConfigCarriesMaterializedSnapshot() throws {
        let op = Op.refreshRuntimeConfig(config: .table([
            "model": .string("gpt-reloaded"),
            "features": .table(["plugins": .bool(true)])
        ]))

        try XCTAssertJSONObjectEqual(op, [
            "type": "refresh_runtime_config",
            "config": [
                "model": "gpt-reloaded",
                "features": ["plugins": true]
            ]
        ])
        let data = try JSONEncoder().encode(op)
        XCTAssertEqual(try JSONDecoder().decode(Op.self, from: data), op)
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
                    "text": "build",
                    "text_elements": []
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
                    "text": "ship it",
                    "text_elements": []
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

    func testFileSystemPermissionsRejectRustDeniedShapes() {
        XCTAssertThrowsError(try JSONDecoder().decode(FileSystemPermissions.self, from: Data(#"""
        {
            "entries": [],
            "read": ["/repo"]
        }
        """#.utf8)))

        XCTAssertThrowsError(try JSONDecoder().decode(FileSystemPermissions.self, from: Data(#"""
        {
            "read": ["/repo"],
            "extra": true
        }
        """#.utf8))) { error in
            XCTAssertTrue(String(describing: error).contains("unknown field `extra`"))
        }

        XCTAssertThrowsError(try JSONDecoder().decode(FileSystemPermissions.self, from: Data(#"""
        {
            "entries": [],
            "glob_scan_max_depth": 0
        }
        """#.utf8)))
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

    func testFileSystemSandboxPolicyFromLegacySandboxPolicyForCwdMatchesRustMetadataProjection() throws {
        let temp = try TemporaryDirectory()
        let cwd = temp.url.appendingPathComponent("cwd", isDirectory: true)
        let writableRoot = temp.url.appendingPathComponent("extra", isDirectory: true)
        let cwdGit = cwd.appendingPathComponent(".git", isDirectory: true)
        let writableAgents = writableRoot.appendingPathComponent(".agents", isDirectory: true)
        try FileManager.default.createDirectory(at: cwdGit, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: writableAgents, withIntermediateDirectories: true)
        let cwdPath = try AbsolutePath(absolutePath: cwd.path)
        let writableRootPath = try AbsolutePath(absolutePath: writableRoot.path)

        let sandboxPolicy = SandboxPolicy.workspaceWrite(
            writableRoots: [writableRootPath],
            networkAccess: false,
            excludeTmpdirEnvVar: true,
            excludeSlashTmp: true
        )

        XCTAssertEqual(
            FileSystemSandboxPolicy.fromLegacySandboxPolicyForCwd(sandboxPolicy, cwd: cwdPath.path),
            .restricted(entries: [
                FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .read),
                FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.projectRoots(subpath: nil).jsonValue), access: .write),
                FileSystemSandboxEntry(path: .path(writableRootPath.path), access: .write),
                FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.projectRoots(subpath: ".git").jsonValue), access: .read),
                FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.projectRoots(subpath: ".agents").jsonValue), access: .read),
                FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.projectRoots(subpath: ".codex").jsonValue), access: .read),
                FileSystemSandboxEntry(path: .path(writableAgents.path), access: .read),
                FileSystemSandboxEntry(path: .path(cwdGit.path), access: .read),
                FileSystemSandboxEntry(path: .path(cwd.appendingPathComponent(".codex").path), access: .read)
            ])
        )
    }

    func testFileSystemSandboxPolicyFromLegacySandboxPolicyPreservesDenyEntriesLikeRust() throws {
        let temp = try TemporaryDirectory()
        let cwd = temp.url.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
        let cwdPath = try AbsolutePath(absolutePath: cwd.path)
        let denyEntry = FileSystemSandboxEntry(path: .globPattern("\(cwdPath.path)/**/*.env"), access: .none)

        let rebuilt = FileSystemSandboxPolicy.fromLegacySandboxPolicyPreservingDenyEntries(
            .workspaceWrite(
                writableRoots: [],
                networkAccess: false,
                excludeTmpdirEnvVar: true,
                excludeSlashTmp: true
            ),
            cwd: cwdPath.path,
            existing: .restricted(entries: [denyEntry], globScanMaxDepth: 4)
        )

        XCTAssertEqual(
            rebuilt,
            .restricted(entries: [
                FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .read),
                FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.projectRoots(subpath: nil).jsonValue), access: .write),
                FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.projectRoots(subpath: ".git").jsonValue), access: .read),
                FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.projectRoots(subpath: ".agents").jsonValue), access: .read),
                FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.projectRoots(subpath: ".codex").jsonValue), access: .read),
                FileSystemSandboxEntry(path: .path(cwd.appendingPathComponent(".codex").path), access: .read),
                denyEntry
            ], globScanMaxDepth: 4)
        )
    }

    func testFileSystemSandboxPolicyFromLegacySandboxPolicyPreservingDenyEntriesReturnsUnrestrictedLikeRust() {
        let existing = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .globPattern("/repo/**/*.env"), access: .none)
        ], globScanMaxDepth: 2)

        XCTAssertEqual(
            FileSystemSandboxPolicy.fromLegacySandboxPolicyPreservingDenyEntries(
                .dangerFullAccess,
                cwd: "/repo",
                existing: existing
            ),
            .unrestricted
        )
    }

    func testPermissionProfileFromLegacySandboxPolicyForCwdUsesProjectedRuntimePolicyLikeRust() throws {
        let temp = try TemporaryDirectory()
        let cwd = temp.url.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
        let cwdPath = try AbsolutePath(absolutePath: cwd.path)
        let sandboxPolicy = SandboxPolicy.workspaceWrite(
            writableRoots: [],
            networkAccess: true,
            excludeTmpdirEnvVar: true,
            excludeSlashTmp: true
        )

        XCTAssertEqual(
            PermissionProfile.fromLegacySandboxPolicyForCwd(sandboxPolicy, cwd: cwdPath.path),
            .managed(
                fileSystem: .restricted(entries: [
                    FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .read),
                    FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.projectRoots(subpath: nil).jsonValue), access: .write),
                    FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.projectRoots(subpath: ".git").jsonValue), access: .read),
                    FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.projectRoots(subpath: ".agents").jsonValue), access: .read),
                    FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.projectRoots(subpath: ".codex").jsonValue), access: .read),
                    FileSystemSandboxEntry(path: .path(cwd.appendingPathComponent(".codex").path), access: .read)
                ]),
                network: .enabled
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
            "kind": .string("project_roots"),
            "subpath": .null
        ]))
        XCTAssertEqual(FileSystemSpecialPath.unknown(path: "future_token", subpath: nil).jsonValue, .object([
            "kind": .string("unknown"),
            "path": .string("future_token"),
            "subpath": .null
        ]))
    }

    func testPermissionProfileFromRuntimePermissionsMatchesRust() {
        let entries = [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .read)
        ]
        let restricted = FileSystemSandboxPolicy.restricted(entries: entries, globScanMaxDepth: 2)
        XCTAssertEqual(
            ManagedFileSystemPermissions.fromSandboxPolicy(restricted),
            .restricted(entries: entries, globScanMaxDepth: 2)
        )
        XCTAssertNil(ManagedFileSystemPermissions.fromSandboxPolicy(.externalSandbox))
        XCTAssertEqual(
            PermissionProfile.fromRuntimePermissions(fileSystem: restricted, network: .restricted),
            .managed(fileSystem: .restricted(entries: entries, globScanMaxDepth: 2), network: .restricted)
        )

        XCTAssertEqual(
            PermissionProfile.fromRuntimePermissions(fileSystem: .externalSandbox, network: .restricted),
            .external(network: .restricted)
        )
        XCTAssertEqual(
            PermissionProfile.fromRuntimePermissionsWithEnforcement(
                .managed,
                fileSystem: .externalSandbox,
                network: .restricted
            ),
            .external(network: .restricted)
        )
        XCTAssertEqual(
            PermissionProfile.fromRuntimePermissionsWithEnforcement(
                .disabled,
                fileSystem: .unrestricted,
                network: .restricted
            ),
            .disabled
        )
        XCTAssertEqual(
            PermissionProfile.fromRuntimePermissionsWithEnforcement(
                .external,
                fileSystem: .unrestricted,
                network: .restricted
            ),
            .managed(fileSystem: .unrestricted, network: .restricted)
        )
    }

    func testFileSystemSandboxPolicyPreservesConfiguredDenyReadsLikeRust() {
        let readableEntry = FileSystemSandboxEntry(path: .path("/tmp/project"), access: .read)
        let denyEntry = FileSystemSandboxEntry(path: .globPattern("/tmp/project/**/*.env"), access: .none)
        var replacement = FileSystemSandboxPolicy.restricted(entries: [readableEntry])
        let configured = FileSystemSandboxPolicy.restricted(entries: [denyEntry], globScanMaxDepth: 2)

        replacement.preserveDenyReadRestrictions(from: configured)

        XCTAssertEqual(
            replacement,
            .restricted(entries: [readableEntry, denyEntry], globScanMaxDepth: 2)
        )
        XCTAssertTrue(replacement.hasDeniedReadRestrictions)
    }

    func testFileSystemSandboxPolicyPreservesDenyReadsWhenReplacementIsUnrestrictedLikeRust() {
        let denyEntry = FileSystemSandboxEntry(path: .globPattern("/tmp/project/**/*.env"), access: .none)
        var replacement = FileSystemSandboxPolicy.unrestricted
        let configured = FileSystemSandboxPolicy.restricted(entries: [denyEntry], globScanMaxDepth: 2)

        replacement.preserveDenyReadRestrictions(from: configured)

        XCTAssertEqual(
            replacement,
            .restricted(
                entries: [
                    FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .write),
                    denyEntry
                ],
                globScanMaxDepth: 2
            )
        )
    }

    func testFileSystemSandboxPolicyAddsLegacyWritableRootsWithProtectedMetadataLikeRust() throws {
        let temp = try TemporaryDirectory()
        let root = temp.url.appendingPathComponent("workspace", isDirectory: true)
        let gitDir = root.appendingPathComponent(".git", isDirectory: true)
        let agentsDir = root.appendingPathComponent(".agents", isDirectory: true)
        let codexDir = root.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)

        let rootPath = try AbsolutePath(absolutePath: root.path)
        let policy = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .read),
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.projectRoots(subpath: nil).jsonValue), access: .write)
        ])

        XCTAssertEqual(
            policy.withAdditionalLegacyWorkspaceWritableRoots([rootPath]),
            .restricted(entries: [
                FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .read),
                FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.projectRoots(subpath: nil).jsonValue), access: .write),
                FileSystemSandboxEntry(path: .path(rootPath.path), access: .write),
                FileSystemSandboxEntry(path: .path(gitDir.path), access: .read),
                FileSystemSandboxEntry(path: .path(agentsDir.path), access: .read),
                FileSystemSandboxEntry(path: .path(codexDir.path), access: .read)
            ])
        )
    }

    func testFileSystemSandboxPolicyLegacyWritableRootKeepsExistingExactWriteAndReadRulesLikeRust() throws {
        let temp = try TemporaryDirectory()
        let root = temp.url.appendingPathComponent("workspace", isDirectory: true)
        let gitDir = root.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        let rootPath = try AbsolutePath(absolutePath: root.path)

        let policy = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .path(rootPath.path), access: .write),
            FileSystemSandboxEntry(path: .path(gitDir.path), access: .none)
        ], globScanMaxDepth: 3)

        XCTAssertEqual(
            policy.withAdditionalLegacyWorkspaceWritableRoots([rootPath, rootPath]),
            .restricted(entries: [
                FileSystemSandboxEntry(path: .path(rootPath.path), access: .write),
                FileSystemSandboxEntry(path: .path(gitDir.path), access: .none)
            ], globScanMaxDepth: 3)
        )
    }

    func testFileSystemSandboxPolicyLegacyWritableRootTracksGitPointerLikeRust() throws {
        let temp = try TemporaryDirectory()
        let root = temp.url.appendingPathComponent("worktree", isDirectory: true)
        let gitDir = temp.url.appendingPathComponent("actual-git-dir", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        let dotGit = root.appendingPathComponent(".git")
        try "gitdir: ../actual-git-dir\n".write(to: dotGit, atomically: true, encoding: .utf8)
        let rootPath = try AbsolutePath(absolutePath: root.path)

        let policy = FileSystemSandboxPolicy.restricted(entries: [])

        XCTAssertEqual(
            policy.withAdditionalLegacyWorkspaceWritableRoots([rootPath]),
            .restricted(entries: [
                FileSystemSandboxEntry(path: .path(rootPath.path), access: .write),
                FileSystemSandboxEntry(path: .path(gitDir.path), access: .read),
                FileSystemSandboxEntry(path: .path(dotGit.path), access: .read)
            ])
        )
    }

    func testFileSystemSandboxPolicyLegacyWritableRootLeavesNonRestrictedPoliciesUnchangedLikeRust() throws {
        let root = try AbsolutePath(absolutePath: "/repo/generated")

        XCTAssertEqual(
            FileSystemSandboxPolicy.unrestricted.withAdditionalLegacyWorkspaceWritableRoots([root]),
            .unrestricted
        )
        XCTAssertEqual(
            FileSystemSandboxPolicy.externalSandbox.withAdditionalLegacyWorkspaceWritableRoots([root]),
            .externalSandbox
        )
    }

    func testFileSystemSandboxPolicyMaterializesProjectRootsWithCwdLikeRust() throws {
        let policy = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.projectRoots(subpath: nil).jsonValue), access: .write),
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.projectRoots(subpath: ".codex").jsonValue), access: .read),
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .read),
            FileSystemSandboxEntry(path: .globPattern("**/*.secret"), access: .none)
        ], globScanMaxDepth: 5)

        XCTAssertEqual(
            policy.materializeProjectRootsWithCwd("/repo/workspace"),
            .restricted(entries: [
                FileSystemSandboxEntry(path: .path("/repo/workspace"), access: .write),
                FileSystemSandboxEntry(path: .path("/repo/workspace/.codex"), access: .read),
                FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .read),
                FileSystemSandboxEntry(path: .globPattern("**/*.secret"), access: .none)
            ], globScanMaxDepth: 5)
        )
    }

    func testFileSystemSandboxPolicyMaterializeProjectRootsLeavesNonRestrictedPoliciesUnchangedLikeRust() {
        XCTAssertEqual(
            FileSystemSandboxPolicy.unrestricted.materializeProjectRootsWithCwd("/repo"),
            .unrestricted
        )
        XCTAssertEqual(
            FileSystemSandboxPolicy.externalSandbox.materializeProjectRootsWithCwd("/repo"),
            .externalSandbox
        )
    }

    func testFileSystemSandboxPolicyResolveAccessWithCwdUsesMostSpecificEntryLikeRust() throws {
        let temp = try TemporaryDirectory()
        let cwd = temp.url
        let docs = cwd.appendingPathComponent("docs", isDirectory: true)
        let docsPrivate = docs.appendingPathComponent("private", isDirectory: true)
        let docsPublic = docsPrivate.appendingPathComponent("public", isDirectory: true)
        let policy = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.projectRoots(subpath: nil).jsonValue), access: .write),
            FileSystemSandboxEntry(path: .path(docs.path), access: .read),
            FileSystemSandboxEntry(path: .path(docsPrivate.path), access: .none),
            FileSystemSandboxEntry(path: .path(docsPublic.path), access: .write)
        ])

        XCTAssertEqual(policy.resolveAccessWithCwd(path: cwd.path, cwd: cwd.path), .write)
        XCTAssertEqual(policy.resolveAccessWithCwd(path: docs.path, cwd: cwd.path), .read)
        XCTAssertEqual(policy.resolveAccessWithCwd(path: docsPrivate.path, cwd: cwd.path), .none)
        XCTAssertEqual(policy.resolveAccessWithCwd(path: docsPublic.path, cwd: cwd.path), .write)
    }

    func testFileSystemSandboxPolicyAdditionalReadableRootsSkipExistingEffectiveAccessLikeRust() throws {
        let temp = try TemporaryDirectory()
        let cwd = try AbsolutePath(absolutePath: temp.url.path)
        let policy = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.projectRoots(subpath: nil).jsonValue), access: .read)
        ])

        XCTAssertEqual(
            policy.withAdditionalReadableRoots([cwd], cwd: cwd.path),
            policy
        )
    }

    func testFileSystemSandboxPolicyAdditionalWritableRootsSkipExistingEffectiveAccessLikeRust() throws {
        let temp = try TemporaryDirectory()
        let cwd = try AbsolutePath(absolutePath: temp.url.path)
        let policy = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.projectRoots(subpath: nil).jsonValue), access: .write)
        ])

        XCTAssertEqual(
            policy.withAdditionalWritableRoots([cwd], cwd: cwd.path),
            policy
        )
    }

    func testFileSystemSandboxPolicyAdditionalWritableRootsAddNewRootLikeRust() throws {
        let temp = try TemporaryDirectory()
        let cwd = temp.url.appendingPathComponent("workspace", isDirectory: true)
        let extra = try AbsolutePath(absolutePath: temp.url.appendingPathComponent("extra", isDirectory: true).path)
        let policy = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.projectRoots(subpath: nil).jsonValue), access: .write)
        ])

        XCTAssertEqual(
            policy.withAdditionalWritableRoots([extra], cwd: cwd.path),
            .restricted(entries: [
                FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.projectRoots(subpath: nil).jsonValue), access: .write),
                FileSystemSandboxEntry(path: .path(extra.path), access: .write)
            ])
        )
    }

    func testFileSystemSandboxPolicyBlocksProtectedMetadataWritesByDefaultLikeRust() throws {
        let temp = try TemporaryDirectory()
        let cwd = try AbsolutePath(absolutePath: temp.url.path)
        let policy = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .path(cwd.path), access: .write)
        ])

        XCTAssertFalse(policy.canWritePathWithCwd(cwd.path + "/.git/config", cwd: cwd.path))
        XCTAssertFalse(policy.canWritePathWithCwd(cwd.path + "/.agents/config", cwd: cwd.path))
        XCTAssertFalse(policy.canWritePathWithCwd(cwd.path + "/.codex/config.toml", cwd: cwd.path))
    }

    func testFileSystemSandboxPolicyAllowsExplicitMetadataWriteLikeRust() throws {
        let temp = try TemporaryDirectory()
        let cwd = try AbsolutePath(absolutePath: temp.url.path)
        let dotCodex = try cwd.join(".codex")
        let policy = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .path(cwd.path), access: .write),
            FileSystemSandboxEntry(path: .path(dotCodex.path), access: .write)
        ])

        XCTAssertTrue(policy.canWritePathWithCwd(dotCodex.path + "/config.toml", cwd: cwd.path))
    }

    func testFileSystemSandboxPolicyFullDiskAccessHelpersMatchRust() throws {
        let temp = try TemporaryDirectory()
        let cwd = try AbsolutePath(absolutePath: temp.url.path)
        let docs = try cwd.join("docs")
        let narrowed = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .write),
            FileSystemSandboxEntry(path: .path(docs.path), access: .read)
        ])
        let overridden = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .write),
            FileSystemSandboxEntry(path: .path(docs.path), access: .read),
            FileSystemSandboxEntry(path: .path(docs.path), access: .write)
        ])
        let deniedRead = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .read),
            FileSystemSandboxEntry(path: .globPattern("**/*.env"), access: .none)
        ])

        XCTAssertFalse(narrowed.hasFullDiskWriteAccess)
        XCTAssertTrue(overridden.hasFullDiskWriteAccess)
        XCTAssertFalse(deniedRead.hasFullDiskReadAccess)
    }

    func testFileSystemSandboxPolicyStableSpecialPathsShareAbsoluteTargetsLikeRust() {
        let rootPathOverride = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .write),
            FileSystemSandboxEntry(path: .path("/"), access: .read)
        ])
        let slashTmpOverride = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .write),
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.slashTmp.jsonValue), access: .read),
            FileSystemSandboxEntry(path: .path("/tmp"), access: .write)
        ])

        XCTAssertTrue(rootPathOverride.hasFullDiskWriteAccess)
        XCTAssertTrue(slashTmpOverride.hasFullDiskWriteAccess)
    }

    func testFileSystemSandboxPolicyIncludePlatformDefaultsMatchesRust() {
        let minimalRead = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.minimal.jsonValue), access: .read)
        ])
        let fullRead = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .read),
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.minimal.jsonValue), access: .read)
        ])

        XCTAssertTrue(minimalRead.includePlatformDefaults)
        XCTAssertFalse(fullRead.includePlatformDefaults)
        XCTAssertFalse(FileSystemSandboxPolicy.unrestricted.includePlatformDefaults)
    }

    func testFileSystemSandboxPolicyReadableAndUnreadableRootsMatchRust() throws {
        let temp = try TemporaryDirectory()
        let cwd = try AbsolutePath(absolutePath: temp.url.path)
        let docs = try cwd.join("docs")
        let docsPrivate = try docs.join("private")
        let effectiveCwd = try rustEffectiveTopLevelAliasPath(cwd)
        let effectiveDocs = try effectiveCwd.join("docs")
        let effectiveDocsPrivate = try effectiveDocs.join("private")
        let rootDenyPolicy = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .none),
            FileSystemSandboxEntry(path: .path(docs.path), access: .read)
        ])
        let nestedDenyPolicy = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.projectRoots(subpath: nil).jsonValue), access: .read),
            FileSystemSandboxEntry(path: .path(docsPrivate.path), access: .none)
        ])
        let fullReadPolicy = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .read)
        ])

        XCTAssertEqual(rootDenyPolicy.getReadableRootsWithCwd(cwd.path), [effectiveDocs])
        XCTAssertEqual(rootDenyPolicy.getUnreadableRootsWithCwd(cwd.path), [])
        XCTAssertEqual(nestedDenyPolicy.getUnreadableRootsWithCwd(cwd.path), [effectiveDocsPrivate])
        XCTAssertEqual(fullReadPolicy.getReadableRootsWithCwd(cwd.path), [])
        XCTAssertEqual(FileSystemSandboxPolicy.unrestricted.getUnreadableRootsWithCwd(cwd.path), [])
    }

    func testFileSystemSandboxPolicyProjectionsNormalizeTopLevelAliasesLikeRust() throws {
        guard let tmpDestination = try? FileManager.default.destinationOfSymbolicLink(atPath: "/tmp") else {
            throw XCTSkip("/tmp is not a top-level symlink on this platform")
        }
        let effectiveTmp = tmpDestination.hasPrefix("/") ? tmpDestination : "/" + tmpDestination
        let rawRootURL = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("codex-swift-permissions-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rawRootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rawRootURL) }

        let rawRoot = try AbsolutePath(absolutePath: rawRootURL.path)
        let rawPrivate = try rawRoot.join("private")
        let effectiveRoot = try AbsolutePath.resolve(rawRootURL.lastPathComponent, against: effectiveTmp)
        let effectivePrivate = try effectiveRoot.join("private")
        let policy = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .path(rawRoot.path), access: .write),
            FileSystemSandboxEntry(path: .path(rawPrivate.path), access: .none)
        ])

        XCTAssertEqual(policy.getReadableRootsWithCwd(rawRoot.path), [effectiveRoot])
        XCTAssertEqual(policy.getUnreadableRootsWithCwd(rawRoot.path), [effectivePrivate])
        XCTAssertEqual(policy.getWritableRootsWithCwd(rawRoot.path), [
            WritableRoot(root: effectiveRoot, readOnlySubpaths: [
                try effectiveRoot.join(".codex"),
                effectivePrivate
            ], protectedMetadataNames: [".git", ".agents", ".codex"])
        ])
    }

    func testFileSystemSandboxPolicyProjectionsPreserveNestedSymlinkRootsLikeRust() throws {
        let temp = try TemporaryDirectory()
        let realRootURL = temp.url.appendingPathComponent("real", isDirectory: true)
        let linkRootURL = temp.url.appendingPathComponent("link", isDirectory: true)
        let blockedURL = realRootURL.appendingPathComponent("blocked", isDirectory: true)
        let agentsURL = realRootURL.appendingPathComponent(".agents", isDirectory: true)
        let codexURL = realRootURL.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: blockedURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: agentsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linkRootURL, withDestinationURL: realRootURL)

        let linkRoot = try AbsolutePath(absolutePath: linkRootURL.path)
        let linkBlocked = try linkRoot.join("blocked")
        let policy = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.minimal.jsonValue), access: .read),
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.projectRoots(subpath: nil).jsonValue), access: .write),
            FileSystemSandboxEntry(path: .path(linkBlocked.path), access: .none)
        ])

        XCTAssertEqual(policy.getReadableRootsWithCwd(linkRoot.path), [linkRoot])
        XCTAssertEqual(policy.getUnreadableRootsWithCwd(linkRoot.path), [linkBlocked])
        XCTAssertEqual(policy.getWritableRootsWithCwd(linkRoot.path), [
            WritableRoot(root: linkRoot, readOnlySubpaths: [
                try linkRoot.join(".agents"),
                try linkRoot.join(".codex"),
                linkBlocked
            ], protectedMetadataNames: [".git", ".agents", ".codex"])
        ])
    }

    func testFileSystemSandboxPolicyWritableRootsIncludeReadOnlyCarveoutsLikeRust() throws {
        let temp = try TemporaryDirectory()
        let cwd = try AbsolutePath(absolutePath: temp.url.path)
        let docs = try cwd.join("docs")
        let docsPrivate = try docs.join("private")
        let effectiveCwd = try rustEffectiveTopLevelAliasPath(cwd)
        let effectiveDocsPrivate = try effectiveCwd.join("docs/private")
        let policy = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.projectRoots(subpath: nil).jsonValue), access: .write),
            FileSystemSandboxEntry(path: .path(docsPrivate.path), access: .read)
        ])

        XCTAssertEqual(policy.getWritableRootsWithCwd(cwd.path), [
            WritableRoot(root: effectiveCwd, readOnlySubpaths: [
                try effectiveCwd.join(".codex"),
                effectiveDocsPrivate
            ], protectedMetadataNames: [".git", ".agents", ".codex"])
        ])
        XCTAssertEqual(FileSystemSandboxPolicy.unrestricted.getWritableRootsWithCwd(cwd.path), [])
        XCTAssertEqual(
            FileSystemSandboxPolicy.restricted(entries: [
                FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .write)
            ]).getWritableRootsWithCwd(cwd.path),
            []
        )
    }

    func testFileSystemSandboxPolicyWritableRootsProtectExistingMetadataLikeRust() throws {
        let temp = try TemporaryDirectory()
        let cwdURL = temp.url
        let dotGitURL = cwdURL.appendingPathComponent(".git", isDirectory: true)
        let dotAgentsURL = cwdURL.appendingPathComponent(".agents", isDirectory: true)
        try FileManager.default.createDirectory(at: dotGitURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dotAgentsURL, withIntermediateDirectories: true)
        let cwd = try AbsolutePath(absolutePath: cwdURL.path)
        let effectiveCwd = try rustEffectiveTopLevelAliasPath(cwd)
        let policy = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .path(cwd.path), access: .write)
        ])

        XCTAssertEqual(policy.getWritableRootsWithCwd(cwd.path), [
            WritableRoot(root: effectiveCwd, readOnlySubpaths: [
                try effectiveCwd.join(".git"),
                try effectiveCwd.join(".agents"),
                try effectiveCwd.join(".codex")
            ], protectedMetadataNames: [".git", ".agents", ".codex"])
        ])

        let writableRoot = try XCTUnwrap(policy.getWritableRootsWithCwd(cwd.path).first)
        XCTAssertFalse(writableRoot.isPathWritable(try effectiveCwd.join(".git/config")))
        XCTAssertFalse(writableRoot.isPathWritable(try effectiveCwd.join(".agents/settings.json")))
        XCTAssertFalse(writableRoot.isPathWritable(try effectiveCwd.join(".codex/config.toml")))
        XCTAssertTrue(writableRoot.isPathWritable(try effectiveCwd.join("src/main.swift")))
    }

    func testFileSystemSandboxPolicyWritableRootsSkipExplicitMetadataRuleLikeRust() throws {
        let temp = try TemporaryDirectory()
        let cwd = try AbsolutePath(absolutePath: temp.url.path)
        let effectiveCwd = try rustEffectiveTopLevelAliasPath(cwd)
        let explicitDotCodex = try effectiveCwd.join(".codex")
        let policy = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.projectRoots(subpath: nil).jsonValue), access: .write),
            FileSystemSandboxEntry(path: .path(explicitDotCodex.path), access: .write)
        ])

        let writableRoot = try XCTUnwrap(policy.getWritableRootsWithCwd(cwd.path).first { $0.root == effectiveCwd })
        XCTAssertEqual(writableRoot.protectedMetadataNames, [".git", ".agents"])
        XCTAssertFalse(writableRoot.readOnlySubpaths.contains(explicitDotCodex))
        XCTAssertTrue(policy.canWritePathWithCwd(try explicitDotCodex.join("config.toml").path, cwd: cwd.path))
        XCTAssertTrue(writableRoot.isPathWritable(try explicitDotCodex.join("config.toml")))
        XCTAssertFalse(writableRoot.isPathWritable(try effectiveCwd.join(".git/config")))
    }

    func testFileSystemSandboxPolicyUnreadableGlobsResolveSortAndDedupLikeRust() throws {
        let temp = try TemporaryDirectory()
        let cwd = try AbsolutePath(absolutePath: temp.url.path)
        let policy = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .globPattern("z/**/*.env"), access: .none),
            FileSystemSandboxEntry(path: .globPattern("a/*.secret"), access: .none),
            FileSystemSandboxEntry(path: .globPattern("a/*.secret"), access: .none),
            FileSystemSandboxEntry(path: .globPattern("readable/*"), access: .read),
            FileSystemSandboxEntry(path: .path(cwd.path + "/literal"), access: .none)
        ])

        XCTAssertEqual(policy.getUnreadableGlobsWithCwd(cwd.path), [
            cwd.path + "/a/*.secret",
            cwd.path + "/z/**/*.env"
        ])
        XCTAssertEqual(FileSystemSandboxPolicy.externalSandbox.getUnreadableGlobsWithCwd(cwd.path), [])
    }

    func testReadDenyMatcherExactPathAndDescendantsMatchRust() throws {
        let temp = try TemporaryDirectory()
        let root = try AbsolutePath(absolutePath: temp.url.path)
        let denied = try root.join("denied")
        let nested = try denied.join("nested.txt")
        try FileManager.default.createDirectory(atPath: denied.path, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: nested.path, contents: Data("secret".utf8))
        let policy = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .path(denied.path), access: .none)
        ])

        XCTAssertTrue(isReadDenied(denied.path, policy: policy, cwd: root.path))
        XCTAssertTrue(isReadDenied(nested.path, policy: policy, cwd: root.path))
        XCTAssertFalse(isReadDenied(try root.join("other.txt").path, policy: policy, cwd: root.path))
    }

    func testReadDenyMatcherCanonicalTargetMatchesDeniedSymlinkAliasLikeRust() throws {
        let temp = try TemporaryDirectory()
        let root = try AbsolutePath(absolutePath: temp.url.path)
        let realDir = temp.url.appendingPathComponent("real", isDirectory: true)
        let aliasDir = temp.url.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createDirectory(at: realDir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: aliasDir, withDestinationURL: realDir)

        let realSecret = try root.join("real/secret.txt")
        let aliasSecret = try root.join("alias/secret.txt")
        FileManager.default.createFile(atPath: realSecret.path, contents: Data("secret".utf8))
        let policy = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .path(realDir.path), access: .none)
        ])

        XCTAssertTrue(isReadDenied(aliasSecret.path, policy: policy, cwd: root.path))
    }

    func testReadDenyMatcherLiteralPatternsAndGlobsMatchRust() throws {
        let temp = try TemporaryDirectory()
        let root = try AbsolutePath(absolutePath: temp.url.path)
        let literal = try root.join("private")
        let other = try root.join("notes.txt")
        try FileManager.default.createDirectory(atPath: literal.path, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: other.path, contents: Data("notes".utf8))
        let policy = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .path(literal.path), access: .none),
            FileSystemSandboxEntry(path: .globPattern("\(root.path)/**/*.txt"), access: .none)
        ])

        XCTAssertTrue(isReadDenied(literal.path, policy: policy, cwd: root.path))
        XCTAssertTrue(isReadDenied(other.path, policy: policy, cwd: root.path))
    }

    func testReadDenyMatcherGlobPatternsDoNotCrossSeparatorsLikeRust() throws {
        let temp = try TemporaryDirectory()
        let root = try AbsolutePath(absolutePath: temp.url.path)
        let matching = try root.join("app/file42.txt")
        let nested = try root.join("app/nested/file42.txt")
        let short = try root.join("app/file4.txt")
        let letters = try root.join("app/fileab.txt")
        try FileManager.default.createDirectory(atPath: try root.join("app/nested").path, withIntermediateDirectories: true)
        for path in [matching, nested, short, letters] {
            FileManager.default.createFile(atPath: path.path, contents: Data("secret".utf8))
        }
        let policy = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .read),
            FileSystemSandboxEntry(path: .globPattern("\(root.path)/*/file[0-9]?.txt"), access: .none)
        ])

        XCTAssertTrue(isReadDenied(matching.path, policy: policy, cwd: root.path))
        XCTAssertFalse(isReadDenied(nested.path, policy: policy, cwd: root.path))
        XCTAssertFalse(isReadDenied(short.path, policy: policy, cwd: root.path))
        XCTAssertFalse(isReadDenied(letters.path, policy: policy, cwd: root.path))
    }

    func testReadDenyMatcherGlobstarPatternsDenyRootAndNestedMatchesLikeRust() throws {
        let temp = try TemporaryDirectory()
        let root = try AbsolutePath(absolutePath: temp.url.path)
        let rootEnv = try root.join(".env")
        let nestedEnv = try root.join("app/.env")
        let other = try root.join("app/notes.txt")
        try FileManager.default.createDirectory(atPath: try root.join("app").path, withIntermediateDirectories: true)
        for path in [rootEnv, nestedEnv, other] {
            FileManager.default.createFile(atPath: path.path, contents: Data("secret".utf8))
        }
        let policy = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .read),
            FileSystemSandboxEntry(path: .globPattern("\(root.path)/**/*.env"), access: .none)
        ])

        XCTAssertTrue(isReadDenied(rootEnv.path, policy: policy, cwd: root.path))
        XCTAssertTrue(isReadDenied(nestedEnv.path, policy: policy, cwd: root.path))
        XCTAssertFalse(isReadDenied(other.path, policy: policy, cwd: root.path))
    }

    func testReadDenyMatcherUnclosedCharacterClassesMatchLiteralBracketsLikeRust() throws {
        let temp = try TemporaryDirectory()
        let root = try AbsolutePath(absolutePath: temp.url.path)
        let bracketFile = try root.join("[")
        let other = try root.join("notes.txt")
        FileManager.default.createFile(atPath: bracketFile.path, contents: Data("secret".utf8))
        FileManager.default.createFile(atPath: other.path, contents: Data("notes".utf8))
        let policy = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .read),
            FileSystemSandboxEntry(path: .globPattern("\(root.path)/["), access: .none)
        ])

        XCTAssertTrue(isReadDenied(bracketFile.path, policy: policy, cwd: root.path))
        XCTAssertFalse(isReadDenied(other.path, policy: policy, cwd: root.path))
    }

    func testFileSystemSandboxPolicyToLegacySandboxPolicyMatchesRustBridgeableCases() throws {
        let temp = try TemporaryDirectory()
        let cwd = try AbsolutePath(absolutePath: temp.url.path)
        let cache = try cwd.join("cache")
        let fullWrite = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .write)
        ])
        let workspaceWrite = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .read),
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.projectRoots(subpath: nil).jsonValue), access: .write),
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.projectRoots(subpath: "cache").jsonValue), access: .write),
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.slashTmp.jsonValue), access: .write)
        ])
        let readOnly = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .read)
        ])

        XCTAssertEqual(
            try FileSystemSandboxPolicy.externalSandbox.toLegacySandboxPolicy(networkPolicy: .enabled, cwd: cwd.path),
            .externalSandbox(networkAccess: .enabled)
        )
        XCTAssertEqual(
            try FileSystemSandboxPolicy.unrestricted.toLegacySandboxPolicy(networkPolicy: .restricted, cwd: cwd.path),
            .externalSandbox(networkAccess: .restricted)
        )
        XCTAssertEqual(
            try fullWrite.toLegacySandboxPolicy(networkPolicy: .enabled, cwd: cwd.path),
            .dangerFullAccess
        )
        XCTAssertEqual(
            try readOnly.toLegacySandboxPolicy(networkPolicy: .enabled, cwd: cwd.path),
            .readOnlyWithNetworkAccess
        )
        XCTAssertEqual(
            try workspaceWrite.toLegacySandboxPolicy(networkPolicy: .enabled, cwd: cwd.path),
            .workspaceWrite(
                writableRoots: [cache],
                networkAccess: true,
                excludeTmpdirEnvVar: true,
                excludeSlashTmp: false
            )
        )
    }

    func testFileSystemSandboxPolicyToLegacySandboxPolicyRejectsUnbridgeableWritesLikeRust() throws {
        let temp = try TemporaryDirectory()
        let cwd = try AbsolutePath(absolutePath: temp.url.path)
        let outside = try AbsolutePath(absolutePath: "/outside")
        let outsideWrite = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .read),
            FileSystemSandboxEntry(path: .path(outside.path), access: .write)
        ])
        let tmpOnlyWrite = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .read),
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.tmpdir.jsonValue), access: .write)
        ])

        XCTAssertThrowsError(try outsideWrite.toLegacySandboxPolicy(networkPolicy: .restricted, cwd: cwd.path)) { error in
            XCTAssertEqual(error as? FileSystemSandboxPolicyError, .unbridgeableWritesOutsideWorkspace)
        }
        XCTAssertThrowsError(try tmpOnlyWrite.toLegacySandboxPolicy(networkPolicy: .restricted, cwd: cwd.path)) { error in
            XCTAssertEqual(error as? FileSystemSandboxPolicyError, .unbridgeableWritesOutsideWorkspace)
        }
    }

    func testFileSystemSandboxPolicyDirectRuntimeEnforcementMatchesRust() throws {
        let temp = try TemporaryDirectory()
        let cwd = try AbsolutePath(absolutePath: temp.url.path)
        let docs = try cwd.join("docs")
        let splitCarveout = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.projectRoots(subpath: nil).jsonValue), access: .write),
            FileSystemSandboxEntry(path: .path(docs.path), access: .read)
        ])
        let unbridgeableWrite = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .read),
            FileSystemSandboxEntry(path: .path("/outside"), access: .write)
        ])
        let readOnly = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .read)
        ])

        XCTAssertTrue(splitCarveout.needsDirectRuntimeEnforcement(networkPolicy: .restricted, cwd: cwd.path))
        XCTAssertTrue(unbridgeableWrite.needsDirectRuntimeEnforcement(networkPolicy: .restricted, cwd: cwd.path))
        XCTAssertFalse(readOnly.needsDirectRuntimeEnforcement(networkPolicy: .restricted, cwd: cwd.path))
        XCTAssertFalse(FileSystemSandboxPolicy.unrestricted.needsDirectRuntimeEnforcement(networkPolicy: .enabled, cwd: cwd.path))
    }

    func testFileSystemSandboxPolicySemanticEquivalenceIgnoresEntryAndCarveoutOrderLikeRust() throws {
        let temp = try TemporaryDirectory()
        let cwd = try AbsolutePath(absolutePath: temp.url.path)
        let privateDocs = try cwd.join("private")
        let ordered = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.projectRoots(subpath: nil).jsonValue), access: .write),
            FileSystemSandboxEntry(path: .path(privateDocs.path), access: .read)
        ])
        let reordered = FileSystemSandboxPolicy.restricted(entries: [
            FileSystemSandboxEntry(path: .path(privateDocs.path), access: .read),
            FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.projectRoots(subpath: nil).jsonValue), access: .write)
        ])

        XCTAssertTrue(ordered.isSemanticallyEquivalent(to: reordered, cwd: cwd.path))
        XCTAssertEqual(
            ordered.needsDirectRuntimeEnforcement(networkPolicy: .restricted, cwd: cwd.path),
            reordered.needsDirectRuntimeEnforcement(networkPolicy: .restricted, cwd: cwd.path)
        )
    }

    func testFileSystemSandboxPolicySymbolicMetadataNeedsDirectRuntimeEnforcementLikeRust() throws {
        let temp = try TemporaryDirectory()
        let cwd = try AbsolutePath(absolutePath: temp.url.path)
        let policy = FileSystemSandboxPolicy.fromLegacySandboxPolicyForCwd(
            .workspaceWrite(
                writableRoots: [],
                networkAccess: false,
                excludeTmpdirEnvVar: true,
                excludeSlashTmp: true
            ),
            cwd: cwd.path
        )

        XCTAssertTrue(policy.needsDirectRuntimeEnforcement(networkPolicy: .restricted, cwd: cwd.path))
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

        let set = Op.overrideTurnContext(
            cwd: "/repo",
            approvalPolicy: .onFailure,
            approvalsReviewer: .string("guardian"),
            sandboxPolicy: .readOnly,
            permissionProfile: .external(network: .restricted),
            activePermissionProfile: ActivePermissionProfile(
                id: ":workspace",
                modifications: [.additionalWritableRoot(path: "/repo/tmp")]
            ),
            windowsSandboxLevel: .string("read_only"),
            model: "gpt-5.4",
            effort: .set(.low),
            summary: .concise,
            serviceTier: .null,
            collaborationMode: .string("solo"),
            personality: .string("codex")
        )
        try XCTAssertJSONObjectEqual(set, [
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
            "effort": "low",
            "summary": "concise",
            "service_tier": NSNull(),
            "collaboration_mode": "solo",
            "personality": "codex"
        ])
        let setData = try JSONEncoder().encode(set)
        XCTAssertEqual(try JSONDecoder().decode(Op.self, from: setData), set)

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

    func testRemovedCoreListOpsRejectLikeRustProtocol() throws {
        for type in ["list_mcp_tools", "list_skills", "list_models"] {
            XCTAssertThrowsError(try JSONDecoder().decode(Op.self, from: Data(#"{"type":"\#(type)"}"#.utf8)))
        }
    }

    private func rustEffectiveTopLevelAliasPath(_ path: AbsolutePath) throws -> AbsolutePath {
        let components = path.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let firstComponent = components.first else {
            return path
        }

        let topLevel = "/\(firstComponent)"
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: topLevel) else {
            return path
        }

        let effectiveRoot = destination.hasPrefix("/") ? destination : "/" + destination
        let remainder = components.dropFirst().joined(separator: "/")
        if remainder.isEmpty {
            return try AbsolutePath(absolutePath: effectiveRoot)
        }
        return try AbsolutePath.resolve(remainder, against: effectiveRoot)
    }

    private func isReadDenied(_ path: String, policy: FileSystemSandboxPolicy, cwd: String) -> Bool {
        ReadDenyMatcher(fileSystemSandboxPolicy: policy, cwd: cwd)?.isReadDenied(path) ?? false
    }
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
