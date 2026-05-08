import CodexCore
import XCTest

final class McpEventsTests: XCTestCase {
    func testStartupStatusUsesRustInternallyTaggedStateShape() throws {
        try XCTAssertJSONObjectEqual(McpStartupStatus.starting, [
            "state": "starting"
        ])
        try XCTAssertJSONObjectEqual(McpStartupStatus.ready, [
            "state": "ready"
        ])
        try XCTAssertJSONObjectEqual(McpStartupStatus.failed(error: "boom"), [
            "state": "failed",
            "error": "boom"
        ])
        try XCTAssertJSONObjectEqual(McpStartupStatus.cancelled, [
            "state": "cancelled"
        ])

        let data = try JSONEncoder().encode(McpStartupStatus.failed(error: "boom"))
        XCTAssertEqual(try JSONDecoder().decode(McpStartupStatus.self, from: data), .failed(error: "boom"))
    }

    func testStartupUpdateEventWireShape() throws {
        try XCTAssertJSONObjectEqual(McpStartupUpdateEvent(
            server: "srv",
            status: .failed(error: "boom")
        ), [
            "server": "srv",
            "status": [
                "state": "failed",
                "error": "boom"
            ]
        ])
    }

    func testStartupCompleteEventWireShapeAndDefault() throws {
        let event = McpStartupCompleteEvent(
            ready: ["a"],
            failed: [McpStartupFailure(server: "b", error: "bad")],
            cancelled: ["c"]
        )

        try XCTAssertJSONObjectEqual(event, [
            "ready": ["a"],
            "failed": [
                [
                    "server": "b",
                    "error": "bad"
                ]
            ],
            "cancelled": ["c"]
        ])

        try XCTAssertJSONObjectEqual(McpStartupCompleteEvent(), [
            "ready": [],
            "failed": [],
            "cancelled": []
        ])
    }

    func testAuthStatusWireValuesAndDisplayMatchRust() throws {
        XCTAssertEqual(try encode(McpAuthStatus.unsupported), #""unsupported""#)
        XCTAssertEqual(try encode(McpAuthStatus.notLoggedIn), #""not_logged_in""#)
        XCTAssertEqual(try encode(McpAuthStatus.bearerToken), #""bearer_token""#)
        XCTAssertEqual(try encode(McpAuthStatus.oauth), #""oauth""#)

        XCTAssertEqual(McpAuthStatus.unsupported.description, "Unsupported")
        XCTAssertEqual(McpAuthStatus.notLoggedIn.description, "Not logged in")
        XCTAssertEqual(McpAuthStatus.bearerToken.description, "Bearer token")
        XCTAssertEqual(McpAuthStatus.oauth.description, "OAuth")
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        String(data: try JSONEncoder().encode(value), encoding: .utf8) ?? ""
    }
}
