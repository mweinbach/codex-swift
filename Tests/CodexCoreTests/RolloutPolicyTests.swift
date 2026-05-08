import CodexCore
import XCTest

final class RolloutPolicyTests: XCTestCase {
    func testResponseItemPersistenceMatchesRustBuckets() throws {
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItem(.message(role: "assistant", content: [])))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItem(.webSearchCall(status: "completed", action: .search(query: "weather"))))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItem(.compaction(encryptedContent: "encrypted")))
        XCTAssertFalse(RolloutPolicy.shouldPersistResponseItem(.other))

        for type in [
            "reasoning",
            "local_shell_call",
            "function_call",
            "function_call_output",
            "custom_tool_call",
            "custom_tool_call_output",
            "ghost_snapshot"
        ] {
            let item = try JSONDecoder().decode(ResponseItem.self, from: Data(#"{"type":"\#(type)"}"#.utf8))
            XCTAssertEqual(item, .knownPersisted(type: type))
            XCTAssertTrue(RolloutPolicy.shouldPersistResponseItem(item), type)
        }
    }

    func testEventMessagePersistenceMatchesRustBuckets() {
        let persisted: Set<RolloutEventMessageKind> = [
            .userMessage,
            .agentMessage,
            .agentReasoning,
            .agentReasoningRawContent,
            .tokenCount,
            .contextCompacted,
            .enteredReviewMode,
            .exitedReviewMode,
            .undoCompleted,
            .turnAborted
        ]

        for event in RolloutEventMessageKind.allCases {
            XCTAssertEqual(
                RolloutPolicy.shouldPersistEventMessage(event),
                persisted.contains(event),
                event.rawValue
            )
        }
    }

    func testRolloutItemPersistenceMatchesRustBuckets() {
        XCTAssertTrue(RolloutPolicy.isPersistedResponseItem(.sessionMeta))
        XCTAssertTrue(RolloutPolicy.isPersistedResponseItem(.compacted))
        XCTAssertTrue(RolloutPolicy.isPersistedResponseItem(.turnContext))
        XCTAssertTrue(RolloutPolicy.isPersistedResponseItem(.eventMessage(.userMessage)))
        XCTAssertFalse(RolloutPolicy.isPersistedResponseItem(.eventMessage(.error)))
        XCTAssertTrue(RolloutPolicy.isPersistedResponseItem(.responseItem(.message(role: "assistant", content: []))))
        XCTAssertFalse(RolloutPolicy.isPersistedResponseItem(.responseItem(.other)))
    }
}
