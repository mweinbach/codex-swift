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

    func testCommandExecParamsEncodeDisabledLimitShapesLikeRustProtocol() throws {
        try XCTAssertJSONObjectEqual(
            CommandExecParams(
                command: ["sleep", "30"],
                processID: "sleep-1",
                disableTimeout: true
            ),
            [
                "command": ["sleep", "30"],
                "processId": "sleep-1",
                "disableTimeout": true,
                "timeoutMs": NSNull(),
                "cwd": NSNull(),
                "env": NSNull(),
                "size": NSNull(),
                "sandboxPolicy": NSNull(),
                "permissionProfile": NSNull(),
                "outputBytesCap": NSNull()
            ]
        )

        try XCTAssertJSONObjectEqual(
            CommandExecParams(
                command: ["yes"],
                processID: "yes-1",
                streamStdoutStderr: true,
                disableOutputCap: true
            ),
            [
                "command": ["yes"],
                "processId": "yes-1",
                "streamStdoutStderr": true,
                "outputBytesCap": NSNull(),
                "disableOutputCap": true,
                "timeoutMs": NSNull(),
                "cwd": NSNull(),
                "env": NSNull(),
                "size": NSNull(),
                "sandboxPolicy": NSNull(),
                "permissionProfile": NSNull()
            ]
        )
    }

    func testCommandExecParamsEncodeEnvOverridesAndUnsetsLikeRustProtocol() throws {
        try XCTAssertJSONObjectEqual(
            CommandExecParams(
                command: ["printenv", "FOO"],
                processID: "env-1",
                env: [
                    "FOO": "override",
                    "BAR": "added",
                    "BAZ": nil
                ]
            ),
            [
                "command": ["printenv", "FOO"],
                "processId": "env-1",
                "outputBytesCap": NSNull(),
                "timeoutMs": NSNull(),
                "cwd": NSNull(),
                "env": [
                    "FOO": "override",
                    "BAR": "added",
                    "BAZ": NSNull()
                ],
                "size": NSNull(),
                "sandboxPolicy": NSNull(),
                "permissionProfile": NSNull()
            ]
        )
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

    func testCommandExecParamsRejectsNegativeOutputBytesCapLikeRustUsize() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                CommandExecParams.self,
                from: Data(#"{"command":["/bin/echo"],"outputBytesCap":-1}"#.utf8)
            )
        )
    }

    func testCommandExecParamsRejectExplicitNullForRustDefaultedFlags() {
        for field in ["tty", "streamStdin", "streamStdoutStderr", "disableOutputCap", "disableTimeout"] {
            XCTAssertThrowsError(
                try JSONDecoder().decode(
                    CommandExecParams.self,
                    from: Data(#"{"command":["/bin/echo"],"\#(field)":null}"#.utf8)
                )
            )
        }

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                CommandExecWriteParams.self,
                from: Data(#"{"processId":"cmd-1","closeStdin":null}"#.utf8)
            )
        )
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

    func testCommandExecSandboxPolicyRejectsExplicitNullForRustDefaultedFields() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AppServerCommandExecSandboxPolicy.self,
                from: Data(#"{"type":"readOnly","networkAccess":null}"#.utf8)
            )
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AppServerCommandExecSandboxPolicy.self,
                from: Data(#"{"type":"externalSandbox","networkAccess":null}"#.utf8)
            )
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AppServerCommandExecSandboxPolicy.self,
                from: Data(#"{"type":"workspaceWrite","networkAccess":null}"#.utf8)
            )
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AppServerCommandExecSandboxPolicy.self,
                from: Data(#"{"type":"workspaceWrite","writableRoots":null}"#.utf8)
            )
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AppServerCommandExecSandboxPolicy.self,
                from: Data(#"{"type":"workspaceWrite","excludeTmpdirEnvVar":null}"#.utf8)
            )
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AppServerCommandExecSandboxPolicy.self,
                from: Data(#"{"type":"workspaceWrite","excludeSlashTmp":null}"#.utf8)
            )
        )
    }

    func testCommandExecSandboxPolicyIgnoresLegacyReadOnlyFullAccessField() throws {
        let decoded = try JSONDecoder().decode(
            AppServerCommandExecSandboxPolicy.self,
            from: Data(
                #"{"type":"readOnly","access":{"type":"fullAccess"},"networkAccess":true}"#.utf8
            )
        )

        XCTAssertEqual(decoded, .readOnly(networkAccess: true))
    }

    func testCommandExecSandboxPolicyIgnoresLegacyWorkspaceWriteFullAccessField() throws {
        let decoded = try JSONDecoder().decode(
            AppServerCommandExecSandboxPolicy.self,
            from: Data(
                #"{"type":"workspaceWrite","writableRoots":["/workspace"],"readOnlyAccess":{"type":"fullAccess"},"networkAccess":true,"excludeTmpdirEnvVar":true,"excludeSlashTmp":true}"#.utf8
            )
        )

        XCTAssertEqual(
            decoded,
            .workspaceWrite(
                writableRoots: ["/workspace"],
                networkAccess: true,
                excludeTmpdirEnvVar: true,
                excludeSlashTmp: true
            )
        )
    }

    func testCommandExecSandboxPolicyRejectsLegacyReadOnlyRestrictedAccessField() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AppServerCommandExecSandboxPolicy.self,
                from: Data(
                    #"{"type":"readOnly","access":{"type":"restricted","includePlatformDefaults":false,"readableRoots":[]}}"#.utf8
                )
            )
        ) { error in
            XCTAssertTrue(String(describing: error).contains("readOnly.access"))
        }
    }

    func testCommandExecSandboxPolicyRejectsLegacyWorkspaceWriteRestrictedReadOnlyAccessField() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AppServerCommandExecSandboxPolicy.self,
                from: Data(
                    #"{"type":"workspaceWrite","writableRoots":[],"readOnlyAccess":{"type":"restricted","includePlatformDefaults":false,"readableRoots":[]},"networkAccess":false,"excludeTmpdirEnvVar":false,"excludeSlashTmp":false}"#.utf8
                )
            )
        ) { error in
            XCTAssertTrue(String(describing: error).contains("workspaceWrite.readOnlyAccess"))
        }
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
            CommandExecWriteParams(processID: "proc-7", closeStdin: true),
            [
                "processId": "proc-7",
                "deltaBase64": NSNull(),
                "closeStdin": true
            ]
        )
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
