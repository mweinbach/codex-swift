import CodexCore
import XCTest

final class AppServerCommandExecProtocolTests: XCTestCase {
    func testCommandExecParamsEncodeRustNullOptionalsAndOmittedFalseFlags() throws {
        try XCTAssertJSONObjectEqual(CommandExecParams(command: ["/bin/echo", "hi"]), [
            "command": ["/bin/echo", "hi"],
            "processId": NSNull(),
            "outputBytesCap": NSNull(),
            "timeoutMs": NSNull(),
            "cwd": NSNull(),
            "env": NSNull(),
            "size": NSNull(),
            "sandboxPolicy": NSNull(),
            "permissionProfile": NSNull()
        ])
    }

    func testCommandExecParamsEncodeRustFullWireShape() throws {
        let params = CommandExecParams(
            command: ["/bin/sh", "-c", "printf ok"],
            processID: "cmd-1",
            tty: true,
            streamStdin: true,
            streamStdoutStderr: true,
            outputBytesCap: 1024,
            disableOutputCap: true,
            disableTimeout: true,
            timeoutMs: 250,
            cwd: "/repo",
            env: [
                "CODEX_SET": "yes",
                "CODEX_UNSET": nil
            ],
            size: CommandExecTerminalSize(rows: 24, cols: 80),
            sandboxPolicy: .workspaceWrite(
                writableRoots: ["/repo"],
                networkAccess: true,
                excludeTmpdirEnvVar: true,
                excludeSlashTmp: true
            ),
            permissionProfile: .disabled
        )

        try XCTAssertJSONObjectEqual(params, [
            "command": ["/bin/sh", "-c", "printf ok"],
            "processId": "cmd-1",
            "tty": true,
            "streamStdin": true,
            "streamStdoutStderr": true,
            "outputBytesCap": 1024,
            "disableOutputCap": true,
            "disableTimeout": true,
            "timeoutMs": 250,
            "cwd": "/repo",
            "env": [
                "CODEX_SET": "yes",
                "CODEX_UNSET": NSNull()
            ],
            "size": [
                "rows": 24,
                "cols": 80
            ],
            "sandboxPolicy": [
                "type": "workspaceWrite",
                "writableRoots": ["/repo"],
                "networkAccess": true,
                "excludeTmpdirEnvVar": true,
                "excludeSlashTmp": true
            ],
            "permissionProfile": [
                "type": "disabled"
            ]
        ])
    }

    func testCommandExecParamsDecodeRustDefaults() throws {
        let decoded = try JSONDecoder().decode(
            CommandExecParams.self,
            from: Data(#"{"command":["/bin/echo","hi"]}"#.utf8)
        )

        XCTAssertEqual(decoded.command, ["/bin/echo", "hi"])
        XCTAssertNil(decoded.processID)
        XCTAssertFalse(decoded.tty)
        XCTAssertFalse(decoded.streamStdin)
        XCTAssertFalse(decoded.streamStdoutStderr)
        XCTAssertNil(decoded.outputBytesCap)
        XCTAssertFalse(decoded.disableOutputCap)
        XCTAssertFalse(decoded.disableTimeout)
        XCTAssertNil(decoded.timeoutMs)
        XCTAssertNil(decoded.cwd)
        XCTAssertNil(decoded.env)
        XCTAssertNil(decoded.size)
        XCTAssertNil(decoded.sandboxPolicy)
        XCTAssertNil(decoded.permissionProfile)
    }

    func testCommandExecSandboxPolicyEncodesRustCamelCaseVariants() throws {
        try XCTAssertJSONObjectEqual(AppServerCommandExecSandboxPolicy.dangerFullAccess, [
            "type": "dangerFullAccess"
        ])
        try XCTAssertJSONObjectEqual(AppServerCommandExecSandboxPolicy.readOnly(), [
            "type": "readOnly",
            "networkAccess": false
        ])
        try XCTAssertJSONObjectEqual(AppServerCommandExecSandboxPolicy.externalSandbox(networkAccess: .enabled), [
            "type": "externalSandbox",
            "networkAccess": "enabled"
        ])
        try XCTAssertJSONObjectEqual(AppServerCommandExecSandboxPolicy.workspaceWrite(), [
            "type": "workspaceWrite",
            "writableRoots": [],
            "networkAccess": false,
            "excludeTmpdirEnvVar": false,
            "excludeSlashTmp": false
        ])
    }

    func testCommandExecResponsesControlsAndNotificationsEncodeRustShapes() throws {
        try XCTAssertJSONObjectEqual(CommandExecResponse(exitCode: 7, stdout: "out", stderr: "err"), [
            "exitCode": 7,
            "stdout": "out",
            "stderr": "err"
        ])

        try XCTAssertJSONObjectEqual(CommandExecWriteParams(processID: "cmd-1"), [
            "processId": "cmd-1",
            "deltaBase64": NSNull()
        ])
        try XCTAssertJSONObjectEqual(
            CommandExecWriteParams(processID: "cmd-1", deltaBase64: "aGk=", closeStdin: true),
            [
                "processId": "cmd-1",
                "deltaBase64": "aGk=",
                "closeStdin": true
            ]
        )
        try XCTAssertJSONObjectEqual(CommandExecWriteResponse(), [:])
        try XCTAssertJSONObjectEqual(CommandExecTerminateParams(processID: "cmd-1"), [
            "processId": "cmd-1"
        ])
        try XCTAssertJSONObjectEqual(CommandExecTerminateResponse(), [:])
        try XCTAssertJSONObjectEqual(
            CommandExecResizeParams(processID: "cmd-1", size: CommandExecTerminalSize(rows: 40, cols: 120)),
            [
                "processId": "cmd-1",
                "size": [
                    "rows": 40,
                    "cols": 120
                ]
            ]
        )
        try XCTAssertJSONObjectEqual(CommandExecResizeResponse(), [:])
        try XCTAssertJSONObjectEqual(
            CommandExecOutputDeltaNotification(
                processID: "cmd-1",
                stream: .stderr,
                deltaBase64: "ZXJy",
                capReached: true
            ),
            [
                "processId": "cmd-1",
                "stream": "stderr",
                "deltaBase64": "ZXJy",
                "capReached": true
            ]
        )
    }
}
