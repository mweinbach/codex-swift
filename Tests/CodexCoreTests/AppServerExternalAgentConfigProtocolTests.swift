import CodexCore
import XCTest

final class AppServerExternalAgentConfigProtocolTests: XCTestCase {
    func testExternalAgentConfigDetectParamsEncodeRustDefaultsAndNullableFields() throws {
        try XCTAssertJSONObjectEqual(ExternalAgentConfigDetectParams(), [
            "cwds": NSNull()
        ])

        try XCTAssertJSONObjectEqual(
            ExternalAgentConfigDetectParams(includeHome: true, cwds: ["/repo", "/work"]),
            [
                "includeHome": true,
                "cwds": ["/repo", "/work"]
            ]
        )
    }

    func testExternalAgentConfigDetectParamsDecodeRustDefaults() throws {
        let empty = try JSONDecoder().decode(ExternalAgentConfigDetectParams.self, from: Data(#"{}"#.utf8))
        XCTAssertFalse(empty.includeHome)
        XCTAssertNil(empty.cwds)

        let explicit = try JSONDecoder().decode(
            ExternalAgentConfigDetectParams.self,
            from: Data(#"{"includeHome":true,"cwds":["/repo"]}"#.utf8)
        )
        XCTAssertTrue(explicit.includeHome)
        XCTAssertEqual(explicit.cwds, ["/repo"])
    }

    func testExternalAgentConfigDetectParamsRejectExplicitNullForRustDefaultedIncludeHome() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                ExternalAgentConfigDetectParams.self,
                from: Data(#"{"includeHome":null}"#.utf8)
            )
        )
    }

    func testExternalAgentConfigMigrationItemsEncodeRustWireShape() throws {
        let details = ExternalAgentMigrationDetails(
            plugins: [
                ExternalAgentPluginsMigration(marketplaceName: "external", pluginNames: ["weather", "search"])
            ],
            sessions: [
                ExternalAgentSessionMigration(path: "/tmp/session.jsonl", cwd: "/repo", title: "Imported title")
            ],
            mcpServers: [
                ExternalAgentMcpServerMigration(name: "docs")
            ],
            hooks: [
                ExternalAgentHookMigration(name: "notify")
            ],
            subagents: [
                ExternalAgentSubagentMigration(name: "reviewer")
            ],
            commands: [
                ExternalAgentCommandMigration(name: "triage")
            ]
        )
        let item = ExternalAgentConfigMigrationItem(
            itemType: .mcpServerConfig,
            description: "Migrate MCP",
            cwd: "/repo",
            details: details
        )

        try XCTAssertJSONObjectEqual(item, [
            "itemType": "MCP_SERVER_CONFIG",
            "description": "Migrate MCP",
            "cwd": "/repo",
            "details": [
                "plugins": [
                    [
                        "marketplaceName": "external",
                        "pluginNames": ["weather", "search"]
                    ]
                ],
                "sessions": [
                    [
                        "path": "/tmp/session.jsonl",
                        "cwd": "/repo",
                        "title": "Imported title"
                    ]
                ],
                "mcpServers": [
                    ["name": "docs"]
                ],
                "hooks": [
                    ["name": "notify"]
                ],
                "subagents": [
                    ["name": "reviewer"]
                ],
                "commands": [
                    ["name": "triage"]
                ]
            ]
        ])
    }

    func testExternalAgentConfigMigrationItemsPreserveNullOptionalsLikeRust() throws {
        try XCTAssertJSONObjectEqual(
            ExternalAgentConfigMigrationItem(itemType: .sessions, description: "Migrate sessions"),
            [
                "itemType": "SESSIONS",
                "description": "Migrate sessions",
                "cwd": NSNull(),
                "details": NSNull()
            ]
        )

        try XCTAssertJSONObjectEqual(ExternalAgentMigrationDetails(), [
            "plugins": [],
            "sessions": [],
            "mcpServers": [],
            "hooks": [],
            "subagents": [],
            "commands": []
        ])
    }

    func testExternalAgentConfigMigrationDetailsDecodeRustDefaults() throws {
        let decoded = try JSONDecoder().decode(
            ExternalAgentMigrationDetails.self,
            from: Data(#"{"plugins":[{"marketplaceName":"external","pluginNames":["docs"]}]}"#.utf8)
        )

        XCTAssertEqual(decoded.plugins, [
            ExternalAgentPluginsMigration(marketplaceName: "external", pluginNames: ["docs"])
        ])
        XCTAssertEqual(decoded.sessions, [])
        XCTAssertEqual(decoded.mcpServers, [])
        XCTAssertEqual(decoded.hooks, [])
        XCTAssertEqual(decoded.subagents, [])
        XCTAssertEqual(decoded.commands, [])
    }

    func testExternalAgentConfigRequestResponsesAndNotificationEncodeRustShapes() throws {
        let item = ExternalAgentConfigMigrationItem(
            itemType: .config,
            description: "Migrate config",
            cwd: "/repo"
        )

        try XCTAssertJSONObjectEqual(ExternalAgentConfigDetectResponse(items: [item]), [
            "items": [
                [
                    "itemType": "CONFIG",
                    "description": "Migrate config",
                    "cwd": "/repo",
                    "details": NSNull()
                ]
            ]
        ])
        try XCTAssertJSONObjectEqual(ExternalAgentConfigImportParams(migrationItems: [item]), [
            "migrationItems": [
                [
                    "itemType": "CONFIG",
                    "description": "Migrate config",
                    "cwd": "/repo",
                    "details": NSNull()
                ]
            ]
        ])
        try XCTAssertJSONObjectEqual(ExternalAgentConfigImportResponse(), [:])
        try XCTAssertJSONObjectEqual(ExternalAgentConfigImportCompletedNotification(), [:])
    }
}
