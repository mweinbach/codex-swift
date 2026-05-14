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
