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
            config: .object([
                "model": .string("gpt-5"),
                "approval_policy": .string("never")
            ]),
            origins: [
                "model": ConfigLayerMetadata(
                    name: .user(file: try AbsolutePath(absolutePath: "/Users/me/.codex/config.toml")),
                    version: "sha256:user"
                )
            ]
        )

        try XCTAssertJSONObjectEqual(response, [
            "config": [
                "approval_policy": "never",
                "model": "gpt-5"
            ],
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
            config: .object([:]),
            origins: [:],
            layers: [
                AppServerProtocol.ConfigLayer(
                    name: .system(file: try AbsolutePath(absolutePath: "/etc/codex/config.toml")),
                    version: "sha256:system",
                    config: .object(["model": .string("gpt-system")])
                ),
                AppServerProtocol.ConfigLayer(
                    name: .project(dotCodexFolder: try AbsolutePath(absolutePath: "/repo/.codex")),
                    version: "sha256:project",
                    config: .object([:]),
                    disabledReason: "not trusted"
                )
            ]
        )

        try XCTAssertJSONObjectEqual(response, [
            "config": [String: Any](),
            "origins": [String: Any](),
            "layers": [
                [
                    "name": [
                        "type": "system",
                        "file": "/etc/codex/config.toml"
                    ],
                    "version": "sha256:system",
                    "config": [
                        "model": "gpt-system"
                    ]
                ],
                [
                    "name": [
                        "type": "project",
                        "dotCodexFolder": "/repo/.codex"
                    ],
                    "version": "sha256:project",
                    "config": [String: Any](),
                    "disabledReason": "not trusted"
                ]
            ]
        ])
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
