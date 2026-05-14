import CodexCore
import XCTest

final class AppServerPluginProtocolTests: XCTestCase {
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
