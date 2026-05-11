import CodexCore
import XCTest

final class ExecEventsTests: XCTestCase {
    func testExecCommandSourceWireValuesAndDefaultMatchRust() throws {
        XCTAssertEqual(try encode(ExecCommandSource.agent), #""agent""#)
        XCTAssertEqual(try encode(ExecCommandSource.userShell), #""user_shell""#)
        XCTAssertEqual(try encode(ExecCommandSource.unifiedExecStartup), #""unified_exec_startup""#)
        XCTAssertEqual(try encode(ExecCommandSource.unifiedExecInteraction), #""unified_exec_interaction""#)
        XCTAssertEqual(ExecCommandSource.default, .agent)
    }

    func testOutputStreamWireValuesMatchRust() throws {
        XCTAssertEqual(try encode(ExecOutputStream.stdout), #""stdout""#)
        XCTAssertEqual(try encode(ExecOutputStream.stderr), #""stderr""#)
    }

    func testProtocolDurationUsesRustSerdeShape() throws {
        let duration = ProtocolDuration(timeInterval: 1.25)

        XCTAssertEqual(duration, ProtocolDuration(secs: 1, nanos: 250_000_000))
        XCTAssertEqual(duration.timeInterval, 1.25, accuracy: 0.000_001)
        try XCTAssertJSONObjectEqual(duration, [
            "secs": 1,
            "nanos": 250_000_000
        ])
    }

    func testExecCommandBeginWireShapeAndDefaults() throws {
        let event = ExecCommandBeginEvent(
            callID: "exec-1",
            turnID: "turn-1",
            command: ["bash", "-lc", "cat README.md"],
            cwd: "/repo",
            parsedCmd: [.read(cmd: "cat README.md", name: "README.md", path: "README.md")]
        )

        try XCTAssertJSONObjectEqual(event, [
            "call_id": "exec-1",
            "turn_id": "turn-1",
            "started_at_ms": 0,
            "command": ["bash", "-lc", "cat README.md"],
            "cwd": "/repo",
            "parsed_cmd": [
                [
                    "type": "read",
                    "cmd": "cat README.md",
                    "name": "README.md",
                    "path": "README.md"
                ]
            ],
            "source": "agent"
        ])

        let missingDefaults = """
        {
          "call_id": "exec-1",
          "turn_id": "turn-1",
          "command": ["pwd"],
          "cwd": "/repo",
          "parsed_cmd": []
        }
        """
        XCTAssertEqual(
            try JSONDecoder().decode(ExecCommandBeginEvent.self, from: Data(missingDefaults.utf8)),
            ExecCommandBeginEvent(
                callID: "exec-1",
                turnID: "turn-1",
                command: ["pwd"],
                cwd: "/repo",
                parsedCmd: []
            )
        )
    }

    func testExecCommandEndWireShapeAndDefaults() throws {
        let event = ExecCommandEndEvent(
            callID: "exec-1",
            processID: "123",
            turnID: "turn-1",
            command: ["bash", "-lc", "echo hi"],
            cwd: "/repo",
            parsedCmd: [.unknown(cmd: "echo hi")],
            source: .unifiedExecInteraction,
            interactionInput: "echo hi\n",
            stdout: "hi\n",
            stderr: "",
            aggregatedOutput: "hi\n",
            exitCode: 0,
            duration: ProtocolDuration(secs: 1, nanos: 5_000_000),
            formattedOutput: "hi"
        )

        try XCTAssertJSONObjectEqual(event, [
            "call_id": "exec-1",
            "process_id": "123",
            "turn_id": "turn-1",
            "completed_at_ms": 0,
            "command": ["bash", "-lc", "echo hi"],
            "cwd": "/repo",
            "parsed_cmd": [
                [
                    "type": "unknown",
                    "cmd": "echo hi"
                ]
            ],
            "source": "unified_exec_interaction",
            "interaction_input": "echo hi\n",
            "stdout": "hi\n",
            "stderr": "",
            "aggregated_output": "hi\n",
            "exit_code": 0,
            "duration": [
                "secs": 1,
                "nanos": 5_000_000
            ],
            "formatted_output": "hi",
            "status": "completed"
        ])

        let missingDefaults = """
        {
          "call_id": "exec-1",
          "turn_id": "turn-1",
          "command": ["pwd"],
          "cwd": "/repo",
          "parsed_cmd": [],
          "stdout": "/repo\\n",
          "stderr": "",
          "exit_code": 0,
          "duration": {"secs": 0, "nanos": 0},
          "formatted_output": "/repo"
        }
        """
        XCTAssertEqual(
            try JSONDecoder().decode(ExecCommandEndEvent.self, from: Data(missingDefaults.utf8)),
            ExecCommandEndEvent(
                callID: "exec-1",
                turnID: "turn-1",
                command: ["pwd"],
                cwd: "/repo",
                parsedCmd: [],
                stdout: "/repo\n",
                stderr: "",
                exitCode: 0,
                duration: ProtocolDuration(secs: 0),
                formattedOutput: "/repo"
            )
        )
    }

    func testExecBeginAndEndEventMessageWireShapes() throws {
        try XCTAssertJSONObjectEqual(EventMessage.execCommandBegin(ExecCommandBeginEvent(
            callID: "exec-1",
            turnID: "turn-1",
            command: ["pwd"],
            cwd: "/repo",
            parsedCmd: []
        )), [
            "type": "exec_command_begin",
            "call_id": "exec-1",
            "turn_id": "turn-1",
            "started_at_ms": 0,
            "command": ["pwd"],
            "cwd": "/repo",
            "parsed_cmd": [],
            "source": "agent"
        ])

        let end = EventMessage.execCommandEnd(ExecCommandEndEvent(
            callID: "exec-1",
            turnID: "turn-1",
            completedAtMilliseconds: 123,
            command: ["pwd"],
            cwd: "/repo",
            parsedCmd: [],
            stdout: "/repo\n",
            stderr: "",
            exitCode: 0,
            duration: ProtocolDuration(secs: 0),
            formattedOutput: "/repo"
        ))

        try XCTAssertJSONObjectEqual(end, [
            "type": "exec_command_end",
            "call_id": "exec-1",
            "turn_id": "turn-1",
            "completed_at_ms": 123,
            "command": ["pwd"],
            "cwd": "/repo",
            "parsed_cmd": [],
            "source": "agent",
            "stdout": "/repo\n",
            "stderr": "",
            "aggregated_output": "",
            "exit_code": 0,
            "duration": [
                "secs": 0,
                "nanos": 0
            ],
            "formatted_output": "/repo",
            "status": "completed"
        ])

        let data = try JSONEncoder().encode(end)
        XCTAssertEqual(try JSONDecoder().decode(EventMessage.self, from: data), end)
    }

    func testExecCommandOutputDeltaUsesRustBase64ChunkShape() throws {
        let event = ExecCommandOutputDeltaEvent(
            callID: "call21",
            stream: .stdout,
            chunk: [1, 2, 3, 4, 5]
        )

        try XCTAssertJSONObjectEqual(event, [
            "call_id": "call21",
            "stream": "stdout",
            "chunk": "AQIDBAU="
        ])

        let data = try JSONEncoder().encode(event)
        XCTAssertEqual(try JSONDecoder().decode(ExecCommandOutputDeltaEvent.self, from: data), event)
    }

    func testExecCommandOutputDeltaRejectsInvalidBase64() {
        let json = #"{"call_id":"call21","stream":"stdout","chunk":"not base64!"}"#

        XCTAssertThrowsError(try JSONDecoder().decode(
            ExecCommandOutputDeltaEvent.self,
            from: Data(json.utf8)
        ))
    }

    func testTerminalInteractionWireShape() throws {
        try XCTAssertJSONObjectEqual(TerminalInteractionEvent(
            callID: "call-1",
            processID: "1000",
            stdin: "hello\n"
        ), [
            "call_id": "call-1",
            "process_id": "1000",
            "stdin": "hello\n"
        ])
    }

    func testViewImageAndBackgroundEventsWireShape() throws {
        try XCTAssertJSONObjectEqual(ViewImageToolCallEvent(callID: "view-1", path: "/tmp/image.png"), [
            "call_id": "view-1",
            "path": "/tmp/image.png"
        ])

        try XCTAssertJSONObjectEqual(BackgroundEventEvent(message: "working"), [
            "message": "working"
        ])
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        String(data: try JSONEncoder().encode(value), encoding: .utf8) ?? ""
    }
}
