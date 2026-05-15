import CodexCore
import XCTest

final class AppServerPluginProtocolTests: XCTestCase {
    func testMarketplaceAddParamsEncodeExplicitNullOptionalsLikeRustProtocol() throws {
        let params = MarketplaceAddParams(source: "openai/debug-marketplace")

        try XCTAssertJSONObjectEqual(params, [
            "source": "openai/debug-marketplace",
            "refName": NSNull(),
            "sparsePaths": NSNull()
        ])

        let decoded = try JSONDecoder().decode(
            MarketplaceAddParams.self,
            from: Data(#"{"source":"openai/debug-marketplace","refName":"main","sparsePaths":["plugins/debug"]}"#.utf8)
        )

        XCTAssertEqual(decoded.source, "openai/debug-marketplace")
        XCTAssertEqual(decoded.refName, "main")
        XCTAssertEqual(decoded.sparsePaths, ["plugins/debug"])
    }

    func testMarketplaceResponseShapesMatchRustProtocol() throws {
        try XCTAssertJSONObjectEqual(
            MarketplaceAddResponse(
                marketplaceName: "debug",
                installedRoot: try AbsolutePath(absolutePath: "/tmp/marketplaces/debug"),
                alreadyAdded: false
            ),
            [
                "marketplaceName": "debug",
                "installedRoot": "/tmp/marketplaces/debug",
                "alreadyAdded": false
            ]
        )

        try XCTAssertJSONObjectEqual(MarketplaceRemoveParams(marketplaceName: "debug"), [
            "marketplaceName": "debug"
        ])

        try XCTAssertJSONObjectEqual(MarketplaceRemoveResponse(marketplaceName: "debug"), [
            "marketplaceName": "debug",
            "installedRoot": NSNull()
        ])

        try XCTAssertJSONObjectEqual(
            MarketplaceRemoveResponse(
                marketplaceName: "debug",
                installedRoot: try AbsolutePath(absolutePath: "/tmp/marketplaces/debug")
            ),
            [
                "marketplaceName": "debug",
                "installedRoot": "/tmp/marketplaces/debug"
            ]
        )
    }

    func testMarketplaceUpgradeParamsAndResponseRoundTripLikeRustProtocol() throws {
        try XCTAssertJSONObjectEqual(MarketplaceUpgradeParams(), [
            "marketplaceName": NSNull()
        ])
        try XCTAssertJSONObjectEqual(MarketplaceUpgradeParams(marketplaceName: "debug"), [
            "marketplaceName": "debug"
        ])

        let response = MarketplaceUpgradeResponse(
            selectedMarketplaces: ["debug"],
            upgradedRoots: [try AbsolutePath(absolutePath: "/tmp/marketplaces/debug")],
            errors: [
                MarketplaceUpgradeErrorInfo(marketplaceName: "broken", message: "boom")
            ]
        )

        try XCTAssertJSONObjectEqual(response, [
            "selectedMarketplaces": ["debug"],
            "upgradedRoots": ["/tmp/marketplaces/debug"],
            "errors": [
                ["marketplaceName": "broken", "message": "boom"]
            ]
        ])

        let decoded = try JSONDecoder().decode(
            MarketplaceUpgradeParams.self,
            from: Data(#"{"marketplaceName":null}"#.utf8)
        )

        XCTAssertNil(decoded.marketplaceName)
    }

    func testPluginListAndReadParamsEncodeExplicitNullOptionalsLikeRustProtocol() throws {
        try XCTAssertJSONObjectEqual(PluginListParams(), [
            "cwds": NSNull(),
            "marketplaceKinds": NSNull()
        ])

        try XCTAssertJSONObjectEqual(
            PluginListParams(
                cwds: [try AbsolutePath(absolutePath: "/repo")],
                marketplaceKinds: [.local, .workspaceDirectory, .sharedWithMe]
            ),
            [
                "cwds": ["/repo"],
                "marketplaceKinds": ["local", "workspace-directory", "shared-with-me"]
            ]
        )

        try XCTAssertJSONObjectEqual(PluginReadParams(pluginName: "weather"), [
            "marketplacePath": NSNull(),
            "remoteMarketplaceName": NSNull(),
            "pluginName": "weather"
        ])

        try XCTAssertJSONObjectEqual(
            PluginReadParams(
                marketplacePath: try AbsolutePath(absolutePath: "/repo/.agents/plugins/marketplace.json"),
                pluginName: "weather"
            ),
            [
                "marketplacePath": "/repo/.agents/plugins/marketplace.json",
                "remoteMarketplaceName": NSNull(),
                "pluginName": "weather"
            ]
        )
    }

    func testPluginListResponseShapesMatchRustProtocol() throws {
        let minimal = try JSONDecoder().decode(
            PluginListResponse.self,
            from: Data(#"{"marketplaces":[]}"#.utf8)
        )
        XCTAssertEqual(minimal, PluginListResponse(marketplaces: []))

        let summary = PluginSummary(
            id: "weather@debug",
            name: "weather",
            source: .git(url: "https://example.test/weather.git", path: nil, refName: nil, sha: nil),
            installed: true,
            enabled: false,
            installPolicy: .available,
            authPolicy: .onInstall,
            interface: PluginInterface(displayName: "Weather", capabilities: ["forecast"]),
            keywords: ["weather"]
        )

        try XCTAssertJSONObjectEqual(
            PluginListResponse(
                marketplaces: [
                    PluginMarketplaceEntry(
                        name: "debug",
                        path: try AbsolutePath(absolutePath: "/repo/.agents/plugins/marketplace.json"),
                        interface: MarketplaceInterface(displayName: "Debug"),
                        plugins: [summary]
                    )
                ],
                marketplaceLoadErrors: [
                    MarketplaceLoadErrorInfo(
                        marketplacePath: try AbsolutePath(absolutePath: "/broken/marketplace.json"),
                        message: "bad marketplace"
                    )
                ],
                featuredPluginIDs: ["weather@debug"]
            ),
            [
                "marketplaces": [[
                    "name": "debug",
                    "path": "/repo/.agents/plugins/marketplace.json",
                    "interface": ["displayName": "Debug"],
                    "plugins": [[
                        "id": "weather@debug",
                        "name": "weather",
                        "shareContext": NSNull(),
                        "source": [
                            "type": "git",
                            "url": "https://example.test/weather.git",
                            "path": NSNull(),
                            "refName": NSNull(),
                            "sha": NSNull()
                        ],
                        "installed": true,
                        "enabled": false,
                        "installPolicy": "AVAILABLE",
                        "authPolicy": "ON_INSTALL",
                        "availability": "AVAILABLE",
                        "interface": [
                            "displayName": "Weather",
                            "shortDescription": NSNull(),
                            "longDescription": NSNull(),
                            "developerName": NSNull(),
                            "category": NSNull(),
                            "capabilities": ["forecast"],
                            "websiteUrl": NSNull(),
                            "privacyPolicyUrl": NSNull(),
                            "termsOfServiceUrl": NSNull(),
                            "defaultPrompt": NSNull(),
                            "brandColor": NSNull(),
                            "composerIcon": NSNull(),
                            "composerIconUrl": NSNull(),
                            "logo": NSNull(),
                            "logoUrl": NSNull(),
                            "screenshots": [],
                            "screenshotUrls": []
                        ],
                        "keywords": ["weather"]
                    ]]
                ]],
                "marketplaceLoadErrors": [[
                    "marketplacePath": "/broken/marketplace.json",
                    "message": "bad marketplace"
                ]],
                "featuredPluginIds": ["weather@debug"]
            ]
        )
    }

    func testPluginDetailAndInstallShapesMatchRustProtocol() throws {
        let summary = PluginSummary(
            id: "plugins~Plugin_weather",
            name: "plugins~Plugin_weather",
            shareContext: PluginShareContext(
                remotePluginID: "plugins~Plugin_weather",
                shareURL: nil,
                creatorAccountUserID: "user-1",
                creatorName: nil,
                shareTargets: [
                    PluginSharePrincipal(principalType: .user, principalID: "user-1", name: "User")
                ]
            ),
            source: .remote,
            installed: false,
            enabled: false,
            installPolicy: .available,
            authPolicy: .onUse,
            availability: .disabledByAdmin,
            interface: nil,
            keywords: []
        )
        let detail = PluginDetail(
            marketplaceName: "shared-with-me",
            summary: summary,
            description: nil,
            skills: [
                SkillSummary(
                    name: "forecast",
                    description: "Get forecast",
                    interface: AppServerSkillInterface(displayName: "Forecast"),
                    path: nil,
                    enabled: true
                )
            ],
            hooks: [
                PluginHookSummary(key: "plugin:hooks.json:pre_tool_use:0:0", eventName: .preToolUse)
            ],
            apps: [
                AppServerAppSummary(
                    id: "weather-app",
                    name: "Weather",
                    description: nil,
                    installURL: "https://example.test/install",
                    needsAuth: true
                )
            ],
            mcpServers: ["weather"]
        )

        try XCTAssertJSONObjectEqual(PluginReadResponse(plugin: detail), [
            "plugin": [
                "marketplaceName": "shared-with-me",
                "marketplacePath": NSNull(),
                "summary": [
                    "id": "plugins~Plugin_weather",
                    "name": "plugins~Plugin_weather",
                    "shareContext": [
                        "remotePluginId": "plugins~Plugin_weather",
                        "shareUrl": NSNull(),
                        "creatorAccountUserId": "user-1",
                        "creatorName": NSNull(),
                        "shareTargets": [[
                            "principalType": "user",
                            "principalId": "user-1",
                            "name": "User"
                        ]]
                    ],
                    "source": ["type": "remote"],
                    "installed": false,
                    "enabled": false,
                    "installPolicy": "AVAILABLE",
                    "authPolicy": "ON_USE",
                    "availability": "DISABLED_BY_ADMIN",
                    "interface": NSNull(),
                    "keywords": []
                ],
                "description": NSNull(),
                "skills": [[
                    "name": "forecast",
                    "description": "Get forecast",
                    "shortDescription": NSNull(),
                    "interface": [
                        "displayName": "Forecast",
                        "shortDescription": NSNull(),
                        "iconSmall": NSNull(),
                        "iconLarge": NSNull(),
                        "brandColor": NSNull(),
                        "defaultPrompt": NSNull()
                    ],
                    "path": NSNull(),
                    "enabled": true
                ]],
                "hooks": [[
                    "key": "plugin:hooks.json:pre_tool_use:0:0",
                    "eventName": "preToolUse"
                ]],
                "apps": [[
                    "id": "weather-app",
                    "name": "Weather",
                    "description": NSNull(),
                    "installUrl": "https://example.test/install",
                    "needsAuth": true
                ]],
                "mcpServers": ["weather"]
            ]
        ])

        try XCTAssertJSONObjectEqual(PluginInstallParams(remoteMarketplaceName: "shared-with-me", pluginName: "plugins~Plugin_weather"), [
            "marketplacePath": NSNull(),
            "remoteMarketplaceName": "shared-with-me",
            "pluginName": "plugins~Plugin_weather"
        ])

        try XCTAssertJSONObjectEqual(
            PluginInstallResponse(
                authPolicy: .onUse,
                appsNeedingAuth: [
                    AppServerAppSummary(id: "weather-app", name: "Weather", needsAuth: true)
                ]
            ),
            [
                "authPolicy": "ON_USE",
                "appsNeedingAuth": [[
                    "id": "weather-app",
                    "name": "Weather",
                    "description": NSNull(),
                    "installUrl": NSNull(),
                    "needsAuth": true
                ]]
            ]
        )
    }

    func testPluginSkillConfigAndUninstallShapesMatchRustProtocol() throws {
        try XCTAssertJSONObjectEqual(
            PluginSkillReadParams(
                remoteMarketplaceName: "shared-with-me",
                remotePluginID: "plugins~Plugin_weather",
                skillName: "forecast"
            ),
            [
                "remoteMarketplaceName": "shared-with-me",
                "remotePluginId": "plugins~Plugin_weather",
                "skillName": "forecast"
            ]
        )

        try XCTAssertJSONObjectEqual(PluginSkillReadResponse(), [
            "contents": NSNull()
        ])
        try XCTAssertJSONObjectEqual(SkillsConfigWriteParams(enabled: false), [
            "path": NSNull(),
            "name": NSNull(),
            "enabled": false
        ])
        try XCTAssertJSONObjectEqual(SkillsConfigWriteResponse(effectiveEnabled: true), [
            "effectiveEnabled": true
        ])
        try XCTAssertJSONObjectEqual(PluginUninstallParams(pluginID: "weather@debug"), [
            "pluginId": "weather@debug"
        ])
        try XCTAssertJSONObjectEqual(PluginUninstallResponse(), [:])

        let decoded = try JSONDecoder().decode(
            PluginSummary.self,
            from: Data("""
            {
              "id": "remote",
              "name": "remote",
              "shareContext": null,
              "source": { "type": "remote" },
              "installed": false,
              "enabled": false,
              "installPolicy": "AVAILABLE",
              "authPolicy": "ON_USE",
              "availability": "ENABLED",
              "interface": null,
              "keywords": []
            }
            """.utf8)
        )

        XCTAssertEqual(decoded.availability, .available)
    }

    func testPluginSummaryRejectsExplicitNullForRustDefaultedKeywords() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                PluginSummary.self,
                from: Data("""
                {
                  "id": "remote",
                  "name": "remote",
                  "shareContext": null,
                  "source": { "type": "remote" },
                  "installed": false,
                  "enabled": false,
                  "installPolicy": "AVAILABLE",
                  "authPolicy": "ON_USE",
                  "availability": "AVAILABLE",
                  "interface": null,
                  "keywords": null
                }
                """.utf8)
            )
        )
    }

    func testPluginSummaryRejectsExplicitNullForRustDefaultedAvailability() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                PluginSummary.self,
                from: Data("""
                {
                  "id": "remote",
                  "name": "remote",
                  "shareContext": null,
                  "source": { "type": "remote" },
                  "installed": false,
                  "enabled": false,
                  "installPolicy": "AVAILABLE",
                  "authPolicy": "ON_USE",
                  "availability": null,
                  "interface": null,
                  "keywords": []
                }
                """.utf8)
            )
        )
    }

    func testPluginShareSaveParamsEncodeExplicitNullOptionalsLikeRustProtocol() throws {
        let params = PluginShareSaveParams(pluginPath: try AbsolutePath(absolutePath: "/repo/plugin"))

        try XCTAssertJSONObjectEqual(params, [
            "pluginPath": "/repo/plugin",
            "remotePluginId": NSNull(),
            "discoverability": NSNull(),
            "shareTargets": NSNull()
        ])

        let decoded = try JSONDecoder().decode(
            PluginShareSaveParams.self,
            from: Data(#"{"pluginPath":"/repo/plugin","remotePluginId":null,"discoverability":null,"shareTargets":null}"#.utf8)
        )

        XCTAssertEqual(decoded.pluginPath.path, "/repo/plugin")
        XCTAssertNil(decoded.remotePluginID)
        XCTAssertNil(decoded.discoverability)
        XCTAssertNil(decoded.shareTargets)
    }

    func testPluginShareUpdateTargetsRoundTripsLikeRustProtocol() throws {
        let targets = [
            PluginShareTarget(principalType: .user, principalID: "user-1"),
            PluginShareTarget(principalType: .group, principalID: "group-1")
        ]
        let params = PluginShareUpdateTargetsParams(
            remotePluginID: "plugins~Plugin_123",
            discoverability: .unlisted,
            shareTargets: targets
        )

        try XCTAssertJSONObjectEqual(params, [
            "remotePluginId": "plugins~Plugin_123",
            "discoverability": "UNLISTED",
            "shareTargets": [
                ["principalType": "user", "principalId": "user-1"],
                ["principalType": "group", "principalId": "group-1"]
            ]
        ])

        let response = PluginShareUpdateTargetsResponse(
            principals: [
                PluginSharePrincipal(principalType: .workspace, principalID: "workspace-1", name: "Workspace")
            ],
            discoverability: .private
        )

        try XCTAssertJSONObjectEqual(response, [
            "principals": [
                ["principalType": "workspace", "principalId": "workspace-1", "name": "Workspace"]
            ],
            "discoverability": "PRIVATE"
        ])

        let decoded = try JSONDecoder().decode(
            PluginShareUpdateTargetsParams.self,
            from: Data(#"{"remotePluginId":"plugins~Plugin_123","discoverability":"PRIVATE","shareTargets":[]}"#.utf8)
        )

        XCTAssertEqual(decoded.remotePluginID, "plugins~Plugin_123")
        XCTAssertEqual(decoded.discoverability, .private)
        XCTAssertEqual(decoded.shareTargets, [])
    }

    func testPluginShareResponseAndDeleteShapesMatchRustProtocol() throws {
        try XCTAssertJSONObjectEqual(
            PluginShareSaveResponse(
                remotePluginID: "plugins~Plugin_123",
                shareURL: "https://chatgpt.example/plugins/share/key"
            ),
            [
                "remotePluginId": "plugins~Plugin_123",
                "shareUrl": "https://chatgpt.example/plugins/share/key"
            ]
        )

        try XCTAssertJSONObjectEqual(PluginShareListParams(), [:])
        try XCTAssertJSONObjectEqual(PluginShareDeleteParams(remotePluginID: "plugins~Plugin_123"), [
            "remotePluginId": "plugins~Plugin_123"
        ])
        try XCTAssertJSONObjectEqual(PluginShareDeleteResponse(), [:])
    }
}
