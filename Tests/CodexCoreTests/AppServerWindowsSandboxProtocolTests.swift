import CodexCore
import XCTest

final class AppServerWindowsSandboxProtocolTests: XCTestCase {
    func testWindowsWorldWritableWarningNotificationShapeMatchesRustProtocol() throws {
        XCTAssertEqual(WindowsWorldWritableWarningNotification.method, "windows/worldWritableWarning")
        try XCTAssertJSONObjectEqual(
            WindowsWorldWritableWarningNotification(
                samplePaths: ["C:\\Users\\Public\\bad"],
                extraCount: 2,
                failedScan: false
            ),
            [
                "samplePaths": ["C:\\Users\\Public\\bad"],
                "extraCount": 2,
                "failedScan": false
            ]
        )
    }

    func testWindowsSandboxSetupStartParamsEncodeExplicitNullCwdLikeRustProtocol() throws {
        try XCTAssertJSONObjectEqual(
            WindowsSandboxSetupStartParams(mode: .unelevated),
            [
                "mode": "unelevated",
                "cwd": NSNull()
            ]
        )

        try XCTAssertJSONObjectEqual(
            WindowsSandboxSetupStartParams(
                mode: .elevated,
                cwd: try AbsolutePath(absolutePath: "/repo")
            ),
            [
                "mode": "elevated",
                "cwd": "/repo"
            ]
        )
    }

    func testWindowsSandboxResponseShapesMatchRustProtocol() throws {
        try XCTAssertJSONObjectEqual(WindowsSandboxSetupStartResponse(started: true), [
            "started": true
        ])

        try XCTAssertJSONObjectEqual(WindowsSandboxReadinessResponse(status: .notConfigured), [
            "status": "notConfigured"
        ])

        try XCTAssertJSONObjectEqual(
            WindowsSandboxSetupCompletedNotification(mode: .unelevated, success: false),
            [
                "mode": "unelevated",
                "success": false,
                "error": NSNull()
            ]
        )

        try XCTAssertJSONObjectEqual(
            WindowsSandboxSetupCompletedNotification(
                mode: .elevated,
                success: false,
                error: "elevated Windows sandbox setup is only supported on Windows"
            ),
            [
                "mode": "elevated",
                "success": false,
                "error": "elevated Windows sandbox setup is only supported on Windows"
            ]
        )
    }

    func testWindowsSandboxParamsDecodeNullCwdAndReadinessValuesLikeRustProtocol() throws {
        let params = try JSONDecoder().decode(
            WindowsSandboxSetupStartParams.self,
            from: Data(#"{"mode":"unelevated","cwd":null}"#.utf8)
        )

        XCTAssertEqual(params.mode, .unelevated)
        XCTAssertNil(params.cwd)
        XCTAssertEqual(try JSONDecoder().decode(WindowsSandboxReadiness.self, from: Data(#""ready""#.utf8)), .ready)
        XCTAssertEqual(
            try JSONDecoder().decode(WindowsSandboxReadiness.self, from: Data(#""updateRequired""#.utf8)),
            .updateRequired
        )
    }
}
