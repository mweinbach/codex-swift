import CodexCore
import XCTest

final class AppServerRemoteControlProtocolTests: XCTestCase {
    func testRemoteControlStatusReadResponseEncodesRustWireShape() throws {
        try XCTAssertJSONObjectEqual(
            RemoteControlStatusReadResponse(
                status: .connecting,
                serverName: "server-1",
                installationID: "install-1",
                environmentID: "env-1"
            ),
            [
                "status": "connecting",
                "serverName": "server-1",
                "installationId": "install-1",
                "environmentId": "env-1"
            ]
        )

        try XCTAssertJSONObjectEqual(
            RemoteControlStatusReadResponse(
                status: .disabled,
                serverName: "server-2",
                installationID: "install-2",
                environmentID: nil
            ),
            [
                "status": "disabled",
                "serverName": "server-2",
                "installationId": "install-2",
                "environmentId": NSNull()
            ]
        )
    }

    func testRemoteControlStatusReadResponseDecodesRustWireShape() throws {
        let decoded = try JSONDecoder().decode(
            RemoteControlStatusReadResponse.self,
            from: Data(
                #"""
                {
                  "status": "connected",
                  "serverName": "server-3",
                  "installationId": "install-3",
                  "environmentId": null
                }
                """#.utf8
            )
        )

        XCTAssertEqual(
            decoded,
            RemoteControlStatusReadResponse(
                status: .connected,
                serverName: "server-3",
                installationID: "install-3",
                environmentID: nil
            )
        )
    }

    func testRemoteControlEnableAndDisableResponsesConvertFromNotificationLikeRust() {
        let notification = RemoteControlStatusChangedNotification(
            status: .connected,
            serverName: "server-4",
            installationID: "install-4",
            environmentID: "env-4"
        )

        XCTAssertEqual(
            RemoteControlEnableResponse(notification: notification),
            RemoteControlEnableResponse(
                status: .connected,
                serverName: "server-4",
                installationID: "install-4",
                environmentID: "env-4"
            )
        )
        XCTAssertEqual(
            RemoteControlDisableResponse(notification: notification),
            RemoteControlDisableResponse(
                status: .connected,
                serverName: "server-4",
                installationID: "install-4",
                environmentID: "env-4"
            )
        )
    }
}
