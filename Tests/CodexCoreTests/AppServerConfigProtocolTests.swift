import XCTest
@testable import CodexCore

final class AppServerConfigProtocolTests: XCTestCase {
    func testConfigReadParamsPreserveRustDefaultAndNullableCwdRules() throws {
        try XCTAssertJSONObjectEqual(AppServerProtocol.ConfigReadParams(), [
            "includeLayers": false,
            "cwd": NSNull()
        ])

        try XCTAssertJSONObjectEqual(
            AppServerProtocol.ConfigReadParams(includeLayers: true, cwd: "/repo"),
            [
                "includeLayers": true,
                "cwd": "/repo"
            ]
        )

        let decoded = try JSONDecoder().decode(
            AppServerProtocol.ConfigReadParams.self,
            from: Data(#"{"cwd":null}"#.utf8)
        )
        XCTAssertEqual(decoded, AppServerProtocol.ConfigReadParams())
    }

    func testConfigReadParamsRejectsExplicitNullForRustDefaultedIncludeLayers() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AppServerProtocol.ConfigReadParams.self,
                from: Data(#"{"includeLayers":null}"#.utf8)
            )
        )
    }

    func testConfigReadResponseSkipsMissingLayersLikeRust() throws {
        let response = AppServerProtocol.ConfigReadResponse(
            config: AppServerProtocol.Config(model: "gpt-5", approvalPolicy: .never),
            origins: [
                "model": ConfigLayerMetadata(
                    name: .user(file: try AbsolutePath(absolutePath: "/Users/me/.codex/config.toml")),
                    version: "sha256:user"
                )
            ]
        )

        try XCTAssertJSONObjectEqual(response, [
            "config": expectedConfigObject(model: "gpt-5", approvalPolicy: "never"),
            "origins": [
                "model": [
                    "name": [
                        "type": "user",
                        "file": "/Users/me/.codex/config.toml"
                    ],
                    "version": "sha256:user"
                ]
            ]
        ])
    }

    func testConfigReadResponseIncludesLayerDisabledReasonOnlyWhenPresent() throws {
        let response = AppServerProtocol.ConfigReadResponse(
            config: AppServerProtocol.Config(),
            origins: [:],
            layers: [
                AppServerProtocol.ConfigLayer(
                    name: .system(file: try AbsolutePath(absolutePath: "/etc/codex/config.toml")),
                    version: "sha256:system",
                    config: AppServerProtocol.Config(model: "gpt-system")
                ),
                AppServerProtocol.ConfigLayer(
                    name: .project(dotCodexFolder: try AbsolutePath(absolutePath: "/repo/.codex")),
                    version: "sha256:project",
                    config: AppServerProtocol.Config(),
                    disabledReason: "not trusted"
                )
            ]
        )

        try XCTAssertJSONObjectEqual(response, [
            "config": expectedConfigObject(),
            "origins": [String: Any](),
            "layers": [
                [
                    "name": [
                        "type": "system",
                        "file": "/etc/codex/config.toml"
                    ],
                    "version": "sha256:system",
                    "config": expectedConfigObject(model: "gpt-system")
                ],
                [
                    "name": [
                        "type": "project",
                        "dotCodexFolder": "/repo/.codex"
                    ],
                    "version": "sha256:project",
                    "config": expectedConfigObject(),
                    "disabledReason": "not trusted"
                ]
            ]
        ])
    }

    func testConfigReadResponseUsesTypedConfigRustShape() throws {
        let config = AppServerProtocol.Config(
            model: "gpt-5",
            modelContextWindow: 128_000,
            modelProvider: "openai",
            approvalPolicy: .onRequest,
            approvalsReviewer: .autoReview,
            sandboxMode: .workspaceWrite,
            sandboxWorkspaceWrite: AppServerProtocol.SandboxWorkspaceWrite(
                writableRoots: ["/repo"],
                networkAccess: true
            ),
            forcedLoginMethod: .chatgpt,
            webSearch: .live,
            tools: AppServerProtocol.ToolsV2(
                webSearch: AppServerProtocol.WebSearchToolConfig(
                    contextSize: .low,
                    allowedDomains: ["openai.com"],
                    location: AppServerProtocol.WebSearchLocation(country: "US", city: "New York")
                )
            ),
            profiles: [
                "work": AppServerProtocol.ProfileV2(
                    modelProvider: "openai",
                    webSearch: .cached,
                    additional: ["custom_profile_flag": .bool(true)]
                )
            ],
            analytics: AppServerProtocol.AnalyticsConfig(
                enabled: true,
                additional: ["sink": .string("test")]
            ),
            apps: AppServerProtocol.AppsConfig(
                defaultConfig: AppServerProtocol.AppsDefaultConfig(destructiveEnabled: false),
                apps: [
                    "slack": AppServerProtocol.AppConfig(
                        defaultToolsApprovalMode: .prompt,
                        tools: AppServerProtocol.AppToolsConfig(tools: [
                            "send": AppServerProtocol.AppToolConfig(enabled: true, approvalMode: .approve)
                        ])
                    )
                ]
            ),
            desktop: [
                "appearanceTheme": .string("dark"),
                "workspace": .object([
                    "collapsed": .bool(true),
                    "width": .integer(320)
                ])
            ],
            additional: ["custom_flag": .bool(true)]
        )

        try XCTAssertJSONObjectEqual(config, expectedConfigObject(
            model: "gpt-5",
            modelContextWindow: 128_000,
            modelProvider: "openai",
            approvalPolicy: "on-request",
            approvalsReviewer: "guardian_subagent",
            sandboxMode: "workspace-write",
            sandboxWorkspaceWrite: [
                "writable_roots": ["/repo"],
                "network_access": true,
                "exclude_tmpdir_env_var": false,
                "exclude_slash_tmp": false
            ],
            forcedLoginMethod: "chatgpt",
            webSearch: "live",
            tools: [
                "web_search": [
                    "context_size": "low",
                    "allowed_domains": ["openai.com"],
                    "location": [
                        "country": "US",
                        "region": NSNull(),
                        "city": "New York",
                        "timezone": NSNull()
                    ]
                ]
            ],
            profiles: [
                "work": [
                    "model": NSNull(),
                    "model_provider": "openai",
                    "approval_policy": NSNull(),
                    "approvals_reviewer": NSNull(),
                    "service_tier": NSNull(),
                    "model_reasoning_effort": NSNull(),
                    "model_reasoning_summary": NSNull(),
                    "model_verbosity": NSNull(),
                    "web_search": "cached",
                    "tools": NSNull(),
                    "chatgpt_base_url": NSNull(),
                    "custom_profile_flag": true
                ]
            ],
            analytics: [
                "enabled": true,
                "sink": "test"
            ],
            apps: [
                "_default": [
                    "enabled": true,
                    "destructive_enabled": false,
                    "open_world_enabled": true
                ],
                "slack": [
                    "enabled": true,
                    "destructive_enabled": NSNull(),
                    "open_world_enabled": NSNull(),
                    "default_tools_approval_mode": "prompt",
                    "default_tools_enabled": NSNull(),
                    "tools": [
                        "send": [
                            "enabled": true,
                            "approval_mode": "approve"
                        ]
                    ]
                ]
            ],
            desktop: [
                "appearanceTheme": "dark",
                "workspace": [
                    "collapsed": true,
                    "width": 320
                ]
            ],
            additional: ["custom_flag": true]
        ))

        let decoded = try JSONDecoder().decode(AppServerProtocol.Config.self, from: try JSONEncoder().encode(config))
        XCTAssertEqual(decoded, config)
    }

    func testConfigExperimentalReasonsMatchRustProtocolMarkers() {
        let granular = AskForApproval.granular(GranularApprovalConfig(
            sandboxApproval: true,
            rules: false,
            requestPermissions: true,
            mcpElicitations: false
        ))

        XCTAssertEqual(
            AppServerProtocol.ProfileV2(approvalPolicy: granular).appServerExperimentalReason,
            "askForApproval.granular"
        )
        XCTAssertEqual(
            AppServerProtocol.ProfileV2(approvalsReviewer: .autoReview).appServerExperimentalReason,
            "config/read.approvalsReviewer"
        )
        XCTAssertEqual(
            AppServerProtocol.Config(approvalPolicy: granular).appServerExperimentalReason,
            "askForApproval.granular"
        )
        XCTAssertEqual(
            AppServerProtocol.Config(approvalsReviewer: .autoReview).appServerExperimentalReason,
            "config/read.approvalsReviewer"
        )
        XCTAssertEqual(
            AppServerProtocol.Config(profiles: [
                "default": AppServerProtocol.ProfileV2(approvalPolicy: granular)
            ]).appServerExperimentalReason,
            "askForApproval.granular"
        )
        XCTAssertEqual(
            AppServerProtocol.Config(profiles: [
                "default": AppServerProtocol.ProfileV2(approvalsReviewer: .autoReview)
            ]).appServerExperimentalReason,
            "config/read.approvalsReviewer"
        )
        XCTAssertEqual(
            AppServerProtocol.ConfigReadResponse(
                config: AppServerProtocol.Config(apps: AppServerProtocol.AppsConfig()),
                origins: [:]
            ).appServerExperimentalReason,
            "config/read.apps"
        )
        XCTAssertNil(AppServerProtocol.Config(model: "gpt-5").appServerExperimentalReason)
    }

    func testConfigRequirementsExperimentalReasonsMatchRustProtocolMarkers() {
        let granular = AskForApproval.granular(GranularApprovalConfig(
            sandboxApproval: true,
            rules: true,
            mcpElicitations: false
        ))

        XCTAssertEqual(
            AppServerProtocol.ConfigRequirements(
                allowedApprovalPolicies: [granular]
            ).appServerExperimentalReason,
            "askForApproval.granular"
        )
        XCTAssertEqual(
            AppServerProtocol.ConfigRequirements(
                allowedApprovalsReviewers: [.autoReview]
            ).appServerExperimentalReason,
            "configRequirements/read.allowedApprovalsReviewers"
        )
        XCTAssertNil(AppServerProtocol.ConfigRequirements(allowedSandboxModes: [.readOnly]).appServerExperimentalReason)
    }

    func testConfigDefaultedFieldsRejectExplicitNullLikeRust() {
        XCTAssertThrowsError(try JSONDecoder().decode(
            AppServerProtocol.SandboxWorkspaceWrite.self,
            from: Data(#"{"writable_roots":null}"#.utf8)
        ))
        XCTAssertThrowsError(try JSONDecoder().decode(
            AppServerProtocol.Config.self,
            from: Data(#"{"profiles":null}"#.utf8)
        ))
        XCTAssertThrowsError(try JSONDecoder().decode(
            AppServerProtocol.AppsDefaultConfig.self,
            from: Data(#"{"enabled":null}"#.utf8)
        ))
    }

    func testConfigForcedChatGPTWorkspaceIDAcceptsStringOrListLikeRust() throws {
        let single = try JSONDecoder().decode(
            AppServerProtocol.Config.self,
            from: Data(#"{"forced_chatgpt_workspace_id":"org_one"}"#.utf8)
        )
        XCTAssertEqual(single.forcedChatGPTWorkspaceID?.values, ["org_one"])
        try XCTAssertJSONObjectEqual(
            single,
            expectedConfigObject(forcedChatGPTWorkspaceID: "org_one")
        )

        let multiple = try JSONDecoder().decode(
            AppServerProtocol.Config.self,
            from: Data(#"{"forced_chatgpt_workspace_id":["org_one","org_two"]}"#.utf8)
        )
        XCTAssertEqual(multiple.forcedChatGPTWorkspaceID?.values, ["org_one", "org_two"])
        try XCTAssertJSONObjectEqual(
            multiple,
            expectedConfigObject(forcedChatGPTWorkspaceID: ["org_one", "org_two"])
        )
    }

    func testConfigRequirementsReadResponseMatchesRustOptionShape() throws {
        try XCTAssertJSONObjectEqual(
            AppServerProtocol.ConfigRequirementsReadResponse(requirements: nil),
            [
                "requirements": NSNull()
            ]
        )

        let requirements = AppServerProtocol.ConfigRequirements(
            allowedApprovalPolicies: [.onRequest],
            allowedApprovalsReviewers: [.autoReview],
            allowedSandboxModes: [.workspaceWrite],
            allowedWebSearchModes: [.live, .disabled],
            allowManagedHooksOnly: true,
            enforceResidency: .us,
            network: AppServerProtocol.NetworkRequirements(
                enabled: true,
                domains: ["api.example.com": .allow]
            )
        )
        let response = AppServerProtocol.ConfigRequirementsReadResponse(requirements: requirements)

        try XCTAssertJSONObjectEqual(response, [
            "requirements": [
                "allowedApprovalPolicies": ["on-request"],
                "allowedApprovalsReviewers": ["guardian_subagent"],
                "allowedSandboxModes": ["workspace-write"],
                "allowedWebSearchModes": ["live", "disabled"],
                "allowManagedHooksOnly": true,
                "featureRequirements": NSNull(),
                "hooks": NSNull(),
                "enforceResidency": "us",
                "network": [
                    "enabled": true,
                    "httpPort": NSNull(),
                    "socksPort": NSNull(),
                    "allowUpstreamProxy": NSNull(),
                    "dangerouslyAllowNonLoopbackProxy": NSNull(),
                    "dangerouslyAllowAllUnixSockets": NSNull(),
                    "domains": [
                        "api.example.com": "allow"
                    ],
                    "managedAllowedDomainsOnly": NSNull(),
                    "allowedDomains": NSNull(),
                    "deniedDomains": NSNull(),
                    "unixSockets": NSNull(),
                    "allowUnixSockets": NSNull(),
                    "allowLocalBinding": NSNull()
                ]
            ]
        ])

        XCTAssertEqual(
            try JSONDecoder().decode(
                AppServerProtocol.ConfigRequirementsReadResponse.self,
                from: Data(#"{"requirements":null}"#.utf8)
            ),
            AppServerProtocol.ConfigRequirementsReadResponse(requirements: nil)
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                AppServerProtocol.ConfigRequirementsReadResponse.self,
                from: try JSONEncoder().encode(response)
            ),
            response
        )
    }

    func testNetworkRequirementsDecodeLegacyFieldsLikeRustProtocol() throws {
        let decoded = try JSONDecoder().decode(
            AppServerProtocol.NetworkRequirements.self,
            from: Data("""
            {
              "allowedDomains": ["api.openai.com"],
              "deniedDomains": ["blocked.example.com"],
              "allowUnixSockets": ["/tmp/proxy.sock"]
            }
            """.utf8)
        )

        XCTAssertEqual(
            decoded,
            AppServerProtocol.NetworkRequirements(
                allowedDomains: ["api.openai.com"],
                deniedDomains: ["blocked.example.com"],
                allowUnixSockets: ["/tmp/proxy.sock"]
            )
        )
    }

    func testNetworkRequirementsSerializeCanonicalAndLegacyFieldsLikeRustProtocol() throws {
        let requirements = AppServerProtocol.NetworkRequirements(
            enabled: true,
            httpPort: 8080,
            socksPort: 1080,
            allowUpstreamProxy: false,
            dangerouslyAllowNonLoopbackProxy: false,
            dangerouslyAllowAllUnixSockets: true,
            domains: [
                "api.openai.com": .allow,
                "blocked.example.com": .deny
            ],
            managedAllowedDomainsOnly: true,
            allowedDomains: ["api.openai.com"],
            deniedDomains: ["blocked.example.com"],
            unixSockets: [
                "/tmp/proxy.sock": .allow,
                "/tmp/ignored.sock": .none
            ],
            allowUnixSockets: ["/tmp/proxy.sock"],
            allowLocalBinding: true
        )

        try XCTAssertJSONObjectEqual(requirements, [
            "enabled": true,
            "httpPort": 8080,
            "socksPort": 1080,
            "allowUpstreamProxy": false,
            "dangerouslyAllowNonLoopbackProxy": false,
            "dangerouslyAllowAllUnixSockets": true,
            "domains": [
                "api.openai.com": "allow",
                "blocked.example.com": "deny"
            ],
            "managedAllowedDomainsOnly": true,
            "allowedDomains": ["api.openai.com"],
            "deniedDomains": ["blocked.example.com"],
            "unixSockets": [
                "/tmp/ignored.sock": "none",
                "/tmp/proxy.sock": "allow"
            ],
            "allowUnixSockets": ["/tmp/proxy.sock"],
            "allowLocalBinding": true
        ])
    }

    func testConfigRequirementsHooksMatchRustTaggedHandlerShape() throws {
        let requirements = AppServerProtocol.ConfigRequirements(
            hooks: AppServerProtocol.ManagedHooksRequirements(
                managedDir: "/managed/hooks",
                preToolUse: [
                    AppServerProtocol.ConfiguredHookMatcherGroup(
                        matcher: "Bash",
                        hooks: [
                            .command(
                                command: "validate.sh",
                                commandWindows: "powershell -File validate.ps1",
                                timeoutSec: 30,
                                async: false,
                                statusMessage: "Validating"
                            ),
                            .prompt,
                            .agent
                        ]
                    )
                ]
            )
        )

        try XCTAssertJSONObjectEqual(requirements, [
            "allowedApprovalPolicies": NSNull(),
            "allowedApprovalsReviewers": NSNull(),
            "allowedSandboxModes": NSNull(),
            "allowedWebSearchModes": NSNull(),
            "allowManagedHooksOnly": NSNull(),
            "featureRequirements": NSNull(),
            "hooks": [
                "managedDir": "/managed/hooks",
                "windowsManagedDir": NSNull(),
                "PreToolUse": [[
                    "matcher": "Bash",
                    "hooks": [
                        [
                            "type": "command",
                            "command": "validate.sh",
                            "commandWindows": "powershell -File validate.ps1",
                            "timeoutSec": 30,
                            "async": false,
                            "statusMessage": "Validating"
                        ],
                        [
                            "type": "prompt"
                        ],
                        [
                            "type": "agent"
                        ]
                    ]
                ]],
                "PermissionRequest": [],
                "PostToolUse": [],
                "PreCompact": [],
                "PostCompact": [],
                "SessionStart": [],
                "UserPromptSubmit": [],
                "Stop": []
            ],
            "enforceResidency": NSNull(),
            "network": NSNull()
        ])

        let decoded = try JSONDecoder().decode(
            AppServerProtocol.ConfigRequirements.self,
            from: try JSONEncoder().encode(requirements)
        )
        XCTAssertEqual(decoded, requirements)
    }

    func testConfiguredHookCommandHandlerDecodesWindowsOverrideLikeRust() throws {
        let decoded = try JSONDecoder().decode(
            AppServerProtocol.ConfiguredHookHandler.self,
            from: Data(
                #"""
                {
                  "type": "command",
                  "command": "validate.sh",
                  "commandWindows": "powershell -File validate.ps1",
                  "timeoutSec": 30,
                  "async": false,
                  "statusMessage": "Validating"
                }
                """#.utf8
            )
        )

        XCTAssertEqual(
            decoded,
            .command(
                command: "validate.sh",
                commandWindows: "powershell -File validate.ps1",
                timeoutSec: 30,
                async: false,
                statusMessage: "Validating"
            )
        )
    }

    func testConfigWarningNotificationMatchesRustWireShape() throws {
        let warning = ConfigWarningNotification(
            summary: "Invalid config.",
            details: "Unexpected field.",
            path: "/repo/.codex/config.toml",
            range: TextRange(
                start: TextPosition(line: 2, column: 3),
                end: TextPosition(line: 2, column: 8)
            )
        )

        try XCTAssertJSONObjectEqual(warning, [
            "summary": "Invalid config.",
            "details": "Unexpected field.",
            "path": "/repo/.codex/config.toml",
            "range": [
                "start": [
                    "line": 2,
                    "column": 3
                ],
                "end": [
                    "line": 2,
                    "column": 8
                ]
            ]
        ])

        try XCTAssertJSONObjectEqual(
            ConfigWarningNotification(summary: "Project config ignored."),
            [
                "summary": "Project config ignored.",
                "details": NSNull()
            ]
        )

        let decoded = try JSONDecoder().decode(
            ConfigWarningNotification.self,
            from: Data(#"{"summary":"Project config ignored."}"#.utf8)
        )
        XCTAssertEqual(decoded, ConfigWarningNotification(summary: "Project config ignored."))
    }

    func testConfigValueWriteParamsUseExplicitNullOptionalFields() throws {
        let params = AppServerProtocol.ConfigValueWriteParams(
            keyPath: "model",
            value: .string("gpt-5"),
            mergeStrategy: .replace
        )

        try XCTAssertJSONObjectEqual(params, [
            "keyPath": "model",
            "value": "gpt-5",
            "mergeStrategy": "replace",
            "filePath": NSNull(),
            "expectedVersion": NSNull()
        ])

        let decoded = try JSONDecoder().decode(
            AppServerProtocol.ConfigValueWriteParams.self,
            from: Data(#"{"keyPath":"model","value":"gpt-5","mergeStrategy":"replace","filePath":null,"expectedVersion":null}"#.utf8)
        )
        XCTAssertEqual(decoded, params)
    }

    func testConfigBatchWriteParamsSkipFalseReloadButKeepNullableOptionals() throws {
        let edit = AppServerProtocol.ConfigEdit(
            keyPath: "mcp_servers.docs",
            value: .object([
                "command": .string("docs-mcp"),
                "args": .array([.string("--stdio")])
            ]),
            mergeStrategy: .upsert
        )

        try XCTAssertJSONObjectEqual(AppServerProtocol.ConfigBatchWriteParams(edits: [edit]), [
            "edits": [[
                "keyPath": "mcp_servers.docs",
                "value": [
                    "args": ["--stdio"],
                    "command": "docs-mcp"
                ],
                "mergeStrategy": "upsert"
            ]],
            "filePath": NSNull(),
            "expectedVersion": NSNull()
        ])

        try XCTAssertJSONObjectEqual(
            AppServerProtocol.ConfigBatchWriteParams(
                edits: [edit],
                filePath: "/Users/me/.codex/config.toml",
                expectedVersion: "sha256:old",
                reloadUserConfig: true
            ),
            [
                "edits": [[
                    "keyPath": "mcp_servers.docs",
                    "value": [
                        "args": ["--stdio"],
                        "command": "docs-mcp"
                    ],
                    "mergeStrategy": "upsert"
                ]],
                "filePath": "/Users/me/.codex/config.toml",
                "expectedVersion": "sha256:old",
                "reloadUserConfig": true
            ]
        )

        let decoded = try JSONDecoder().decode(
            AppServerProtocol.ConfigBatchWriteParams.self,
            from: Data(#"{"edits":[{"keyPath":"mcp_servers.docs","value":{"args":["--stdio"],"command":"docs-mcp"},"mergeStrategy":"upsert"}],"filePath":null,"expectedVersion":null}"#.utf8)
        )
        XCTAssertEqual(decoded, AppServerProtocol.ConfigBatchWriteParams(edits: [edit]))
    }

    func testConfigBatchWriteRejectsNullReloadLikeRustDefaultBool() throws {
        XCTAssertThrowsError(try JSONDecoder().decode(
            AppServerProtocol.ConfigBatchWriteParams.self,
            from: Data(#"{"edits":[],"reloadUserConfig":null}"#.utf8)
        ))
    }

    func testConfigWriteResponseMatchesRustOverrideMetadataShape() throws {
        let response = AppServerProtocol.ConfigWriteResponse(
            status: .okOverridden,
            version: "sha256:new",
            filePath: try AbsolutePath(absolutePath: "/Users/me/.codex/config.toml"),
            overriddenMetadata: AppServerProtocol.OverriddenConfigMetadata(
                message: "Managed config overrides this value.",
                overridingLayer: ConfigLayerMetadata(
                    name: .legacyManagedConfigTomlFromMdm,
                    version: "sha256:managed"
                ),
                effectiveValue: .string("never")
            )
        )

        try XCTAssertJSONObjectEqual(response, [
            "status": "okOverridden",
            "version": "sha256:new",
            "filePath": "/Users/me/.codex/config.toml",
            "overriddenMetadata": [
                "message": "Managed config overrides this value.",
                "overridingLayer": [
                    "name": [
                        "type": "legacyManagedConfigTomlFromMdm"
                    ],
                    "version": "sha256:managed"
                ],
                "effectiveValue": "never"
            ]
        ])
    }

    func testConfigWriteErrorCodesUseRustCamelCaseValues() throws {
        let values: [AppServerProtocol.ConfigWriteErrorCode] = [
            .configLayerReadonly,
            .configVersionConflict,
            .configValidationError,
            .configPathNotFound,
            .configSchemaUnknownKey,
            .userLayerNotFound
        ]

        let data = try JSONEncoder().encode(values)
        let object = try JSONSerialization.jsonObject(with: data)
        XCTAssertEqual(object as? [String], [
            "configLayerReadonly",
            "configVersionConflict",
            "configValidationError",
            "configPathNotFound",
            "configSchemaUnknownKey",
            "userLayerNotFound"
        ])
    }
}

private func expectedConfigObject(
    model: Any = NSNull(),
    reviewModel: Any = NSNull(),
    modelContextWindow: Any = NSNull(),
    modelAutoCompactTokenLimit: Any = NSNull(),
    modelProvider: Any = NSNull(),
    approvalPolicy: Any = NSNull(),
    approvalsReviewer: Any = NSNull(),
    sandboxMode: Any = NSNull(),
    sandboxWorkspaceWrite: Any = NSNull(),
    forcedChatGPTWorkspaceID: Any = NSNull(),
    forcedLoginMethod: Any = NSNull(),
    webSearch: Any = NSNull(),
    tools: Any = NSNull(),
    profile: Any = NSNull(),
    profiles: Any = [String: Any](),
    instructions: Any = NSNull(),
    developerInstructions: Any = NSNull(),
    compactPrompt: Any = NSNull(),
    modelReasoningEffort: Any = NSNull(),
    modelReasoningSummary: Any = NSNull(),
    modelVerbosity: Any = NSNull(),
    serviceTier: Any = NSNull(),
    analytics: Any = NSNull(),
    apps: Any = NSNull(),
    desktop: Any = NSNull(),
    additional: [String: Any] = [:]
) -> [String: Any] {
    var object: [String: Any] = [
        "model": model,
        "review_model": reviewModel,
        "model_context_window": modelContextWindow,
        "model_auto_compact_token_limit": modelAutoCompactTokenLimit,
        "model_provider": modelProvider,
        "approval_policy": approvalPolicy,
        "approvals_reviewer": approvalsReviewer,
        "sandbox_mode": sandboxMode,
        "sandbox_workspace_write": sandboxWorkspaceWrite,
        "forced_chatgpt_workspace_id": forcedChatGPTWorkspaceID,
        "forced_login_method": forcedLoginMethod,
        "web_search": webSearch,
        "tools": tools,
        "profile": profile,
        "profiles": profiles,
        "instructions": instructions,
        "developer_instructions": developerInstructions,
        "compact_prompt": compactPrompt,
        "model_reasoning_effort": modelReasoningEffort,
        "model_reasoning_summary": modelReasoningSummary,
        "model_verbosity": modelVerbosity,
        "service_tier": serviceTier,
        "analytics": analytics,
        "apps": apps,
        "desktop": desktop
    ]
    for (key, value) in additional {
        object[key] = value
    }
    return object
}
