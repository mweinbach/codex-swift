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
