import CodexCore
import XCTest

final class AppServerInitializeProtocolTests: XCTestCase {
    func testInitializeParamsEncodeRustWireShapeWithOmittedCapabilities() throws {
        try XCTAssertJSONObjectEqual(
            InitializeParams(clientInfo: ClientInfo(name: "codex-app", version: "1.2.3")),
            [
                "clientInfo": [
                    "name": "codex-app",
                    "title": NSNull(),
                    "version": "1.2.3"
                ]
            ]
        )
    }

    func testInitializeParamsEncodeRustCapabilitiesDefaultsAndNulls() throws {
        try XCTAssertJSONObjectEqual(
            InitializeCapabilities(),
            [
                "experimentalApi": false,
                "requestAttestation": false,
                "optOutNotificationMethods": NSNull()
            ]
        )

        try XCTAssertJSONObjectEqual(
            InitializeParams(
                clientInfo: ClientInfo(name: "codex-app", title: "Codex", version: "1.2.3"),
                capabilities: InitializeCapabilities(
                    experimentalAPI: true,
                    requestAttestation: true,
                    optOutNotificationMethods: ["thread/started", "configWarning"]
                )
            ),
            [
                "clientInfo": [
                    "name": "codex-app",
                    "title": "Codex",
                    "version": "1.2.3"
                ],
                "capabilities": [
                    "experimentalApi": true,
                    "requestAttestation": true,
                    "optOutNotificationMethods": ["thread/started", "configWarning"]
                ]
            ]
        )
    }

    func testInitializeParamsDecodeRustDefaultsAndNulls() throws {
        let omittedCapabilities = try JSONDecoder().decode(
            InitializeParams.self,
            from: Data(#"{"clientInfo":{"name":"codex-app","title":null,"version":"1.2.3"}}"#.utf8)
        )
        XCTAssertEqual(
            omittedCapabilities,
            InitializeParams(clientInfo: ClientInfo(name: "codex-app", version: "1.2.3"))
        )

        let defaultCapabilities = try JSONDecoder().decode(
            InitializeParams.self,
            from: Data(#"{"clientInfo":{"name":"codex-app","title":"Codex","version":"1.2.3"},"capabilities":{}}"#.utf8)
        )
        XCTAssertEqual(
            defaultCapabilities,
            InitializeParams(
                clientInfo: ClientInfo(name: "codex-app", title: "Codex", version: "1.2.3"),
                capabilities: InitializeCapabilities()
            )
        )

        let nullOptOut = try JSONDecoder().decode(
            InitializeCapabilities.self,
            from: Data(#"{"experimentalApi":true,"requestAttestation":false,"optOutNotificationMethods":null}"#.utf8)
        )
        XCTAssertEqual(
            nullOptOut,
            InitializeCapabilities(experimentalAPI: true, requestAttestation: false)
        )
    }

    func testInitializeResponseEncodesRustWireShape() throws {
        try XCTAssertJSONObjectEqual(
            InitializeResponse(
                userAgent: "codex_cli_rs/0.0.0",
                codexHome: try AbsolutePath(absolutePath: "/Users/example/.codex"),
                platformFamily: "unix",
                platformOS: "macos"
            ),
            [
                "userAgent": "codex_cli_rs/0.0.0",
                "codexHome": "/Users/example/.codex",
                "platformFamily": "unix",
                "platformOs": "macos"
            ]
        )
    }
}
