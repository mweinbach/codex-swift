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

        try XCTAssertJSONObjectEqual(SessionSource.internal(.memoryConsolidation), [
            "internal": "memory_consolidation"
        ])

        try XCTAssertJSONObjectEqual(SessionSource.custom("atlas"), [
            "custom": "atlas"
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

    func testThreadSpawnSubagentUsesRustTaggedShapeAndAliases() throws {
        let parent = try ThreadId(string: "018f7a2d-4c5b-7abc-8def-0123456789ab")
        let source = SubAgentSource.threadSpawn(
            parentThreadID: parent,
            depth: 2,
            agentPath: try AgentPath(validating: "/root/reviewer"),
            agentNickname: "reviewer",
            agentRole: "analyst"
        )

        try XCTAssertJSONObjectEqual(SessionSource.subagent(source), [
            "subagent": [
                "thread_spawn": [
                    "parent_thread_id": "018f7a2d-4c5b-7abc-8def-0123456789ab",
                    "depth": 2,
                    "agent_path": "/root/reviewer",
                    "agent_nickname": "reviewer",
                    "agent_role": "analyst"
                ]
            ]
        ])

        let decoded = try JSONDecoder().decode(
            SessionSource.self,
            from: Data(#"{"subagent":{"thread_spawn":{"parent_thread_id":"018f7a2d-4c5b-7abc-8def-0123456789ab","depth":3,"agent_type":"critic"}}}"#.utf8)
        )
        XCTAssertEqual(decoded, .subagent(.threadSpawn(parentThreadID: parent, depth: 3, agentRole: "critic")))
        XCTAssertEqual(decoded.agentRole, "critic")
        XCTAssertNil(decoded.agentPath)
    }

    func testPersistedSourceThreadSpawnParentExtractionMatchesRustFallbackOrder() throws {
        let parent = try ThreadId(string: "018f7a2d-4c5b-7abc-8def-0123456789ab")
        let source = SessionSource.subagent(.threadSpawn(parentThreadID: parent, depth: 3))
        let encodedSource = try encode(source)

        XCTAssertEqual(
            SessionSource.threadSpawnParentThreadID(fromPersistedSource: encodedSource),
            parent
        )
        XCTAssertNil(SessionSource.threadSpawnParentThreadID(fromPersistedSource: "cli"))
        XCTAssertNil(SessionSource.threadSpawnParentThreadID(fromPersistedSource: "subagent_thread_spawn_\(parent)_d3"))
    }

    func testSubAgentSourceDisplayMatchesRust() {
        let parent = ThreadId(uuid: UUID(uuidString: "018f7a2d-4c5b-7abc-8def-0123456789ab")!)
        XCTAssertEqual(SubAgentSource.review.description, "review")
        XCTAssertEqual(SubAgentSource.compact.description, "compact")
        XCTAssertEqual(SubAgentSource.memoryConsolidation.description, "memory_consolidation")
        XCTAssertEqual(
            SubAgentSource.threadSpawn(parentThreadID: parent, depth: 4).description,
            "thread_spawn_018f7a2d-4c5b-7abc-8def-0123456789ab_d4"
        )
        XCTAssertEqual(SubAgentSource.other("override-check").description, "override-check")
        XCTAssertEqual(SessionSource.subagent(.review).description, "subagent_review")
        XCTAssertEqual(SessionSource.internal(.memoryConsolidation).description, "internal_memory_consolidation")
        XCTAssertEqual(SessionSource.custom("atlas").description, "atlas")
        XCTAssertEqual(SessionSource.subagent(.other("my-task")).description, "subagent_my-task")
    }

    func testSessionSourceStartupArgAndProductRestrictionMatchRust() throws {
        XCTAssertEqual(try SessionSource.fromStartupArg("vscode"), .vscode)
        XCTAssertEqual(try SessionSource.fromStartupArg("app-server"), .mcp)
        XCTAssertEqual(try SessionSource.fromStartupArg(" Atlas "), .custom("atlas"))

        XCTAssertThrowsError(try SessionSource.fromStartupArg(" \n ")) { error in
            XCTAssertEqual(String(describing: error), "session source must not be empty")
        }

        XCTAssertEqual(SessionSource.cli.restrictionProduct(), .codex)
        XCTAssertEqual(SessionSource.unknown.restrictionProduct(), .codex)
        XCTAssertNil(SessionSource.subagent(.review).restrictionProduct())
        XCTAssertNil(SessionSource.internal(.memoryConsolidation).restrictionProduct())
        XCTAssertEqual(SessionSource.custom("chatgpt").restrictionProduct(), .chatgpt)
        XCTAssertEqual(SessionSource.custom("ATLAS").restrictionProduct(), .atlas)
        XCTAssertEqual(SessionSource.custom("codex").restrictionProduct(), .codex)
        XCTAssertNil(SessionSource.custom("atlas-dev").restrictionProduct())

        XCTAssertTrue(SessionSource.custom("chatgpt").matchesProductRestriction([.chatgpt]))
        XCTAssertFalse(SessionSource.custom("chatgpt").matchesProductRestriction([.codex]))
        XCTAssertTrue(SessionSource.vscode.matchesProductRestriction([.codex]))
        XCTAssertFalse(SessionSource.custom("atlas-dev").matchesProductRestriction([.atlas]))
        XCTAssertTrue(SessionSource.custom("atlas-dev").matchesProductRestriction([]))

        XCTAssertEqual(Product.chatgpt.appPlatform, "chat")
        XCTAssertEqual(Product.codex.appPlatform, "codex")
        XCTAssertEqual(Product.atlas.appPlatform, "atlas")
        XCTAssertEqual(try JSONDecoder().decode(Product.self, from: Data(#""CHATGPT""#.utf8)), .chatgpt)
        XCTAssertEqual(try JSONDecoder().decode(Product.self, from: Data(#""CODEX""#.utf8)), .codex)
        XCTAssertEqual(try JSONDecoder().decode(Product.self, from: Data(#""ATLAS""#.utf8)), .atlas)
        XCTAssertEqual(try encode(Product.atlas), #""atlas""#)
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
        XCTAssertEqual(CodexRequestHeaders.subagentHeader(for: .subagent(.memoryConsolidation)), "memory_consolidation")
        XCTAssertEqual(
            CodexRequestHeaders.subagentHeader(for: .subagent(.threadSpawn(
                parentThreadID: ThreadId(uuid: UUID(uuidString: "018f7a2d-4c5b-7abc-8def-0123456789ab")!),
                depth: 1
            ))),
            "collab_spawn"
        )
        XCTAssertEqual(CodexRequestHeaders.subagentHeader(for: .subagent(.other("my-task"))), "my-task")
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        String(data: try JSONEncoder().encode(value), encoding: .utf8) ?? ""
    }
}
