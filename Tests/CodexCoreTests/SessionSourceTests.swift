import CodexCore
import XCTest

final class SessionSourceTests: XCTestCase {
    func testSessionSourceUnitVariantsUseRustLowercaseWireValues() throws {
        XCTAssertEqual(try encode(SessionSource.cli), #""cli""#)
        XCTAssertEqual(try encode(SessionSource.vscode), #""vscode""#)
        XCTAssertEqual(try encode(SessionSource.exec), #""exec""#)
        XCTAssertEqual(try encode(SessionSource.mcp), #""mcp""#)
        XCTAssertEqual(try encode(SessionSource.unknown), #""unknown""#)
        XCTAssertEqual(SessionSource.default, .vscode)
    }

    func testSessionSourceSubagentUsesRustExternallyTaggedShape() throws {
        try XCTAssertJSONObjectEqual(SessionSource.subagent(.review), [
            "subagent": "review"
        ])

        try XCTAssertJSONObjectEqual(SessionSource.subagent(.other("my-task")), [
            "subagent": [
                "other": "my-task"
            ]
        ])

        let decoded = try JSONDecoder().decode(
            SessionSource.self,
            from: Data(#"{"subagent":{"other":"my-task"}}"#.utf8)
        )
        XCTAssertEqual(decoded, .subagent(.other("my-task")))
    }

    func testSubAgentSourceDisplayMatchesRust() {
        XCTAssertEqual(SubAgentSource.review.description, "review")
        XCTAssertEqual(SubAgentSource.compact.description, "compact")
        XCTAssertEqual(SubAgentSource.other("override-check").description, "override-check")
        XCTAssertEqual(SessionSource.subagent(.review).description, "subagent_review")
        XCTAssertEqual(SessionSource.subagent(.other("my-task")).description, "subagent_my-task")
    }

    func testUnknownSessionSourceDecodesToUnknown() throws {
        XCTAssertEqual(
            try JSONDecoder().decode(SessionSource.self, from: Data(#""new-client""#.utf8)),
            .unknown
        )
        XCTAssertEqual(
            try JSONDecoder().decode(SessionSource.self, from: Data(#"{"new_client":"value"}"#.utf8)),
            .unknown
        )
    }

    func testConversationHeadersMatchRustHelper() {
        XCTAssertEqual(CodexRequestHeaders.conversationHeaders(conversationID: nil), [:])
        XCTAssertEqual(CodexRequestHeaders.conversationHeaders(conversationID: "conv-1"), [
            "conversation_id": "conv-1",
            "thread_id": "conv-1",
            "thread-id": "conv-1",
            "session_id": "conv-1",
            "session-id": "conv-1"
        ])
    }

    func testSubagentHeaderMatchesRustHelper() {
        XCTAssertNil(CodexRequestHeaders.subagentHeader(for: nil))
        XCTAssertNil(CodexRequestHeaders.subagentHeader(for: .cli))
        XCTAssertEqual(CodexRequestHeaders.subagentHeader(for: .subagent(.review)), "review")
        XCTAssertEqual(CodexRequestHeaders.subagentHeader(for: .subagent(.compact)), "compact")
        XCTAssertEqual(CodexRequestHeaders.subagentHeader(for: .subagent(.other("my-task"))), "my-task")
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        String(data: try JSONEncoder().encode(value), encoding: .utf8) ?? ""
    }
}
