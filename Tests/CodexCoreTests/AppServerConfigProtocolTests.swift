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
