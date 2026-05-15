import CodexCore
import XCTest

final class AppServerProcessProtocolTests: XCTestCase {
    func testProcessSpawnParamsEncodeRustDefaultAndNullableFields() throws {
        let cwd = try AbsolutePath(absolutePath: "/tmp/codex-process")

        try XCTAssertJSONObjectEqual(
            ProcessSpawnParams(command: ["/bin/echo", "hi"], processHandle: "proc-1", cwd: cwd),
            [
                "command": ["/bin/echo", "hi"],
                "processHandle": "proc-1",
                "cwd": "/tmp/codex-process",
                "env": NSNull(),
                "size": NSNull()
            ]
        )

        try XCTAssertJSONObjectEqual(
            ProcessSpawnParams(
                command: ["/bin/cat"],
                processHandle: "proc-tty",
                cwd: cwd,
                tty: true,
                streamStdin: true,
                streamStdoutStderr: true,
                outputBytesCap: .disabled,
                timeoutMs: .disabled,
                env: [
                    "CODEX_TEST": "enabled",
                    "CODEX_REMOVE": nil
                ],
                size: ProcessTerminalSize(rows: 24, cols: 80)
            ),
            [
                "command": ["/bin/cat"],
                "processHandle": "proc-tty",
                "cwd": "/tmp/codex-process",
                "tty": true,
                "streamStdin": true,
                "streamStdoutStderr": true,
                "outputBytesCap": NSNull(),
                "timeoutMs": NSNull(),
                "env": [
                    "CODEX_TEST": "enabled",
                    "CODEX_REMOVE": NSNull()
                ],
                "size": [
                    "rows": 24,
                    "cols": 80
                ]
            ]
        )

        try XCTAssertJSONObjectEqual(
            ProcessSpawnParams(
                command: ["/bin/sleep", "1"],
                processHandle: "proc-limited",
                cwd: cwd,
                outputBytesCap: .bytes(4096),
                timeoutMs: .milliseconds(1_000)
            ),
            [
                "command": ["/bin/sleep", "1"],
                "processHandle": "proc-limited",
                "cwd": "/tmp/codex-process",
                "outputBytesCap": 4096,
                "timeoutMs": 1_000,
                "env": NSNull(),
                "size": NSNull()
            ]
        )
    }

    func testProcessSpawnParamsDecodeRustDefaultsAndDoubleOptions() throws {
        let defaulted = try JSONDecoder().decode(
            ProcessSpawnParams.self,
            from: Data(#"{"command":["/bin/echo"],"processHandle":"proc-1","cwd":"/tmp/codex-process"}"#.utf8)
        )

        XCTAssertFalse(defaulted.tty)
        XCTAssertFalse(defaulted.streamStdin)
        XCTAssertFalse(defaulted.streamStdoutStderr)
        XCTAssertEqual(defaulted.outputBytesCap, .serverDefault)
        XCTAssertEqual(defaulted.timeoutMs, .serverDefault)
        XCTAssertNil(defaulted.env)
        XCTAssertNil(defaulted.size)

        let disabled = try JSONDecoder().decode(
            ProcessSpawnParams.self,
            from: Data(
                #"""
                {
                  "command": ["/bin/echo"],
                  "processHandle": "proc-2",
                  "cwd": "/tmp/codex-process",
                  "outputBytesCap": null,
                  "timeoutMs": null,
                  "env": null,
                  "size": null
                }
                """#.utf8
            )
        )
        XCTAssertEqual(disabled.outputBytesCap, .disabled)
        XCTAssertEqual(disabled.timeoutMs, .disabled)

        let limited = try JSONDecoder().decode(
            ProcessSpawnParams.self,
            from: Data(#"{"command":["/bin/echo"],"processHandle":"proc-3","cwd":"/tmp/codex-process","outputBytesCap":2048,"timeoutMs":500}"#.utf8)
        )
        XCTAssertEqual(limited.outputBytesCap, .bytes(2_048))
        XCTAssertEqual(limited.timeoutMs, .milliseconds(500))
    }

    func testProcessSpawnParamsRoundTripsWithoutSandboxPolicyLikeRustProtocol() throws {
        let params = ProcessSpawnParams(
            command: ["sleep", "30"],
            processHandle: "sleep-1",
            cwd: try AbsolutePath(absolutePath: "/tmp/codex-process/readable")
        )

        try XCTAssertJSONObjectEqual(params, [
            "command": ["sleep", "30"],
            "processHandle": "sleep-1",
            "cwd": "/tmp/codex-process/readable",
            "env": NSNull(),
            "size": NSNull()
        ])

        let decoded = try JSONDecoder().decode(
            ProcessSpawnParams.self,
            from: Data(
                #"{"command":["sleep","30"],"processHandle":"sleep-1","cwd":"/tmp/codex-process/readable","env":null,"size":null}"#.utf8
            )
        )
        XCTAssertEqual(decoded, params)
    }

    func testProcessSpawnParamsRejectsNegativeOutputBytesCapLikeRustUsize() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                ProcessSpawnParams.self,
                from: Data(
                    #"{"command":["/bin/echo"],"processHandle":"proc-1","cwd":"/tmp/codex-process","outputBytesCap":-1}"#.utf8
                )
            )
        )
    }

    func testProcessParamsRejectExplicitNullForRustDefaultedFlags() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                ProcessSpawnParams.self,
                from: Data(#"{"command":["/bin/echo"],"processHandle":"proc-1","cwd":"/tmp/codex-process","tty":null}"#.utf8)
            )
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                ProcessSpawnParams.self,
                from: Data(#"{"command":["/bin/echo"],"processHandle":"proc-1","cwd":"/tmp/codex-process","streamStdin":null}"#.utf8)
            )
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                ProcessSpawnParams.self,
                from: Data(#"{"command":["/bin/echo"],"processHandle":"proc-1","cwd":"/tmp/codex-process","streamStdoutStderr":null}"#.utf8)
            )
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                ProcessWriteStdinParams.self,
                from: Data(#"{"processHandle":"proc-1","closeStdin":null}"#.utf8)
            )
        )
    }

    func testProcessControlPayloadsEncodeRustWireShapes() throws {
        try XCTAssertJSONObjectEqual(
            ProcessWriteStdinParams(processHandle: "proc-1"),
            [
                "processHandle": "proc-1",
                "deltaBase64": NSNull()
            ]
        )
        try XCTAssertJSONObjectEqual(
            ProcessWriteStdinParams(processHandle: "proc-7", closeStdin: true),
            [
                "processHandle": "proc-7",
                "deltaBase64": NSNull(),
                "closeStdin": true
            ]
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                ProcessWriteStdinParams.self,
                from: Data(#"{"processHandle":"proc-7","deltaBase64":null,"closeStdin":true}"#.utf8)
            ),
            ProcessWriteStdinParams(processHandle: "proc-7", closeStdin: true)
        )

        try XCTAssertJSONObjectEqual(
            ProcessWriteStdinParams(processHandle: "proc-1", deltaBase64: "aGk=", closeStdin: true),
            [
                "processHandle": "proc-1",
                "deltaBase64": "aGk=",
                "closeStdin": true
            ]
        )

        try XCTAssertJSONObjectEqual(ProcessWriteStdinResponse(), [:])
        try XCTAssertJSONObjectEqual(ProcessKillParams(processHandle: "proc-7"), ["processHandle": "proc-7"])
        XCTAssertEqual(
            try JSONDecoder().decode(
                ProcessKillParams.self,
                from: Data(#"{"processHandle":"proc-7"}"#.utf8)
            ),
            ProcessKillParams(processHandle: "proc-7")
        )
        try XCTAssertJSONObjectEqual(ProcessKillResponse(), [:])
        try XCTAssertJSONObjectEqual(
            ProcessResizePtyParams(processHandle: "proc-7", size: ProcessTerminalSize(rows: 50, cols: 160)),
            [
                "processHandle": "proc-7",
                "size": [
                    "rows": 50,
                    "cols": 160
                ]
            ]
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                ProcessResizePtyParams.self,
                from: Data(#"{"processHandle":"proc-7","size":{"rows":50,"cols":160}}"#.utf8)
            ),
            ProcessResizePtyParams(processHandle: "proc-7", size: ProcessTerminalSize(rows: 50, cols: 160))
        )
        try XCTAssertJSONObjectEqual(ProcessResizePtyResponse(), [:])
    }

    func testProcessNotificationsEncodeRustWireShapes() throws {
        try XCTAssertJSONObjectEqual(
            ProcessOutputDeltaNotification(
                processHandle: "proc-1",
                stream: .stdout,
                deltaBase64: "AQI=",
                capReached: false
            ),
            [
                "processHandle": "proc-1",
                "stream": "stdout",
                "deltaBase64": "AQI=",
                "capReached": false
            ]
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                ProcessOutputDeltaNotification.self,
                from: Data(#"{"processHandle":"proc-1","stream":"stdout","deltaBase64":"AQI=","capReached":false}"#.utf8)
            ),
            ProcessOutputDeltaNotification(
                processHandle: "proc-1",
                stream: .stdout,
                deltaBase64: "AQI=",
                capReached: false
            )
        )

        try XCTAssertJSONObjectEqual(
            ProcessExitedNotification(
                processHandle: "proc-1",
                exitCode: 0,
                stdout: "out",
                stdoutCapReached: false,
                stderr: "err",
                stderrCapReached: true
            ),
            [
                "processHandle": "proc-1",
                "exitCode": 0,
                "stdout": "out",
                "stdoutCapReached": false,
                "stderr": "err",
                "stderrCapReached": true
            ]
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                ProcessExitedNotification.self,
                from: Data(#"{"processHandle":"proc-1","exitCode":0,"stdout":"out","stdoutCapReached":false,"stderr":"err","stderrCapReached":true}"#.utf8)
            ),
            ProcessExitedNotification(
                processHandle: "proc-1",
                exitCode: 0,
                stdout: "out",
                stdoutCapReached: false,
                stderr: "err",
                stderrCapReached: true
            )
        )
    }
}
