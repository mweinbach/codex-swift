import XCTest
@testable import CodexCore

final class TurnMetadataTests: XCTestCase {
    func testCurrentHeaderValueStartsWithBaseTurnMetadataLikeRust() throws {
        let state = TurnMetadataState(
            sessionID: "session-a",
            threadID: "thread-a",
            threadSource: .user,
            turnID: "turn-a",
            sandbox: "read-only"
        )

        let header = try XCTUnwrap(state.currentHeaderValue())
        let json = try jsonObject(header)

        XCTAssertEqual(json["session_id"] as? String, "session-a")
        XCTAssertEqual(json["thread_id"] as? String, "thread-a")
        XCTAssertEqual(json["thread_source"] as? String, "user")
        XCTAssertEqual(json["turn_id"] as? String, "turn-a")
        XCTAssertEqual(json["sandbox"] as? String, "read-only")
    }

    func testClientMetadataCannotSetReservedTurnStartedAtLikeRust() throws {
        let state = TurnMetadataState(
            sessionID: "session-a",
            threadID: "thread-a",
            threadSource: .user,
            turnID: "turn-a"
        )
        state.setResponsesAPIClientMetadata([
            "turn_started_at_unix_ms": "client-supplied"
        ])

        let header = try XCTUnwrap(state.currentHeaderValue())
        let json = try jsonObject(header)

        XCTAssertNil(json["turn_started_at_unix_ms"])
    }

    func testClientMetadataMergesWithoutReplacingReservedFieldsLikeRust() throws {
        let state = TurnMetadataState(
            sessionID: "session-a",
            threadID: "thread-a",
            threadSource: .user,
            turnID: "turn-a"
        )
        state.setResponsesAPIClientMetadata([
            "fiber_run_id": "fiber-123",
            "origin": "東京",
            "model": "client-supplied",
            "reasoning_effort": "client-supplied",
            "session_id": "client-supplied",
            "thread_id": "client-supplied",
            "thread_source": "client-supplied",
            "turn_started_at_unix_ms": "client-supplied"
        ])
        state.setTurnStartedAtUnixMs(1_700_000_000_123)

        let header = try XCTUnwrap(state.currentHeaderValue())
        XCTAssertTrue(header.allSatisfy(\.isASCII))
        XCTAssertFalse(header.contains("東京"))
        let json = try jsonObject(header)

        XCTAssertEqual(json["fiber_run_id"] as? String, "fiber-123")
        XCTAssertEqual(json["origin"] as? String, "東京")
        XCTAssertEqual(json["model"] as? String, "client-supplied")
        XCTAssertEqual(json["reasoning_effort"] as? String, "client-supplied")
        XCTAssertEqual(json["session_id"] as? String, "session-a")
        XCTAssertEqual(json["thread_id"] as? String, "thread-a")
        XCTAssertEqual(json["thread_source"] as? String, "user")
        XCTAssertEqual(json["turn_id"] as? String, "turn-a")
        XCTAssertEqual(json["turn_started_at_unix_ms"] as? Int64, 1_700_000_000_123)
    }

    func testCurrentMetaValueForMcpRequestAddsModelAndReasoningEffortLikeRust() throws {
        let state = TurnMetadataState(
            sessionID: "session-a",
            threadID: "thread-a",
            threadSource: .user,
            turnID: "turn-a"
        )
        state.setResponsesAPIClientMetadata([
            "model": "client-supplied",
            "reasoning_effort": "client-supplied",
            "trace": "turn-trace"
        ])

        let value = try XCTUnwrap(state.currentMetaValueForMcpRequest(
            context: McpTurnMetadataContext(model: "gpt-5.4", reasoningEffort: .high)
        ))
        guard case let .object(object) = value else {
            return XCTFail("expected object metadata")
        }

        XCTAssertEqual(object["model"], .string("gpt-5.4"))
        XCTAssertEqual(object["reasoning_effort"], .string("high"))
        XCTAssertEqual(object["trace"], .string("turn-trace"))
        XCTAssertEqual(object["session_id"], .string("session-a"))

        let noEffort = try XCTUnwrap(state.currentMetaValueForMcpRequest(
            context: McpTurnMetadataContext(model: "gpt-5.4")
        ))
        guard case let .object(noEffortObject) = noEffort else {
            return XCTFail("expected object metadata")
        }
        XCTAssertNil(noEffortObject["reasoning_effort"])
    }
}

private func jsonObject(_ text: String) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
}
