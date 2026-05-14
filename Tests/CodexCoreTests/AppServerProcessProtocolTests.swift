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

    func testProcessControlPayloadsEncodeRustWireShapes() throws {
        try XCTAssertJSONObjectEqual(
            ProcessWriteStdinParams(processHandle: "proc-1"),
            [
                "processHandle": "proc-1",
                "deltaBase64": NSNull()
            ]
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
        try XCTAssertJSONObjectEqual(ProcessKillParams(processHandle: "proc-1"), ["processHandle": "proc-1"])
        try XCTAssertJSONObjectEqual(ProcessKillResponse(), [:])
        try XCTAssertJSONObjectEqual(
            ProcessResizePtyParams(processHandle: "proc-1", size: ProcessTerminalSize(rows: 40, cols: 120)),
            [
                "processHandle": "proc-1",
                "size": [
                    "rows": 40,
                    "cols": 120
                ]
            ]
        )
        try XCTAssertJSONObjectEqual(ProcessResizePtyResponse(), [:])
    }

    func testProcessNotificationsEncodeRustWireShapes() throws {
        try XCTAssertJSONObjectEqual(
            ProcessOutputDeltaNotification(
                processHandle: "proc-1",
                stream: .stdout,
                deltaBase64: "b3V0",
                capReached: false
            ),
            [
                "processHandle": "proc-1",
                "stream": "stdout",
                "deltaBase64": "b3V0",
                "capReached": false
            ]
        )

        try XCTAssertJSONObjectEqual(
            ProcessExitedNotification(
                processHandle: "proc-1",
                exitCode: 7,
                stdout: "out",
                stdoutCapReached: true,
                stderr: "err",
                stderrCapReached: false
            ),
            [
                "processHandle": "proc-1",
                "exitCode": 7,
                "stdout": "out",
                "stdoutCapReached": true,
                "stderr": "err",
                "stderrCapReached": false
            ]
        )
    }
}
