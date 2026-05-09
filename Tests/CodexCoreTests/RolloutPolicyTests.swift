import CodexCore
import XCTest

final class RolloutPolicyTests: XCTestCase {
    func testResponseItemPersistenceMatchesRustBuckets() throws {
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItem(.message(role: "assistant", content: [])))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItem(.reasoning(id: "r1", summary: [])))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItem(.functionCall(name: "do_it", arguments: "{}", callID: "call-1")))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItem(.toolSearchCall(callID: "search-1", execution: "client", arguments: .object(["query": .string("docs")]))))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItem(.functionCallOutput(callID: "call-1", output: FunctionCallOutputPayload(content: "ok"))))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItem(.toolSearchOutput(callID: "search-1", status: "completed", execution: "client", tools: [])))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItem(.customToolCall(callID: "tool-1", name: "custom", input: "{}")))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItem(.customToolCallOutput(callID: "tool-1", output: "ok")))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItem(.localShellCall(callID: "shell-1", status: .completed, action: .exec(LocalShellExecAction(command: ["echo"])))))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItem(.webSearchCall(status: "completed", action: .search(query: "weather"))))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItem(.imageGenerationCall(id: "ig-1", status: "completed", result: "Zm9v")))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItem(.compaction(encryptedContent: "encrypted")))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItem(.contextCompaction(encryptedContent: "encrypted")))
        XCTAssertFalse(RolloutPolicy.shouldPersistResponseItem(.ghostSnapshot(ghostCommit: GhostCommit(
            id: "ghost-1",
            preexistingUntrackedFiles: [],
            preexistingUntrackedDirs: []
        ))))
        XCTAssertFalse(RolloutPolicy.shouldPersistResponseItem(.other))

        for type in [
            "reasoning",
            "local_shell_call",
            "function_call",
            "tool_search_call",
            "function_call_output",
            "tool_search_output",
            "custom_tool_call",
            "custom_tool_call_output",
            "image_generation_call",
            "ghost_snapshot"
        ] {
            let item = try JSONDecoder().decode(ResponseItem.self, from: Data(#"{"type":"\#(type)"}"#.utf8))
            XCTAssertEqual(item, .knownPersisted(type: type))
            XCTAssertTrue(RolloutPolicy.shouldPersistResponseItem(item), type)
        }
    }

    func testResponseItemMemoriesPersistenceMatchesRustBuckets() {
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItemForMemories(.message(role: "user", content: [])))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItemForMemories(.message(role: "assistant", content: [])))
        XCTAssertFalse(RolloutPolicy.shouldPersistResponseItemForMemories(.message(role: "developer", content: [])))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItemForMemories(.functionCall(name: "do_it", arguments: "{}", callID: "call-1")))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItemForMemories(.toolSearchCall(callID: "search-1", execution: "client", arguments: .object(["query": .string("docs")]))))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItemForMemories(.functionCallOutput(callID: "call-1", output: FunctionCallOutputPayload(content: "ok"))))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItemForMemories(.toolSearchOutput(callID: "search-1", status: "completed", execution: "client", tools: [])))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItemForMemories(.customToolCall(callID: "tool-1", name: "custom", input: "{}")))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItemForMemories(.customToolCallOutput(callID: "tool-1", output: "ok")))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItemForMemories(.localShellCall(callID: "shell-1", status: .completed, action: .exec(LocalShellExecAction(command: ["echo"])))))
        XCTAssertTrue(RolloutPolicy.shouldPersistResponseItemForMemories(.webSearchCall(status: "completed", action: .search(query: "weather"))))
        XCTAssertFalse(RolloutPolicy.shouldPersistResponseItemForMemories(.reasoning(id: "r1", summary: [])))
        XCTAssertFalse(RolloutPolicy.shouldPersistResponseItemForMemories(.imageGenerationCall(id: "ig-1", status: "completed", result: "Zm9v")))
        XCTAssertFalse(RolloutPolicy.shouldPersistResponseItemForMemories(.compaction(encryptedContent: "encrypted")))
        XCTAssertFalse(RolloutPolicy.shouldPersistResponseItemForMemories(.contextCompaction(encryptedContent: "encrypted")))
        XCTAssertFalse(RolloutPolicy.shouldPersistResponseItemForMemories(.ghostSnapshot(ghostCommit: GhostCommit(
            id: "ghost-1",
            preexistingUntrackedFiles: [],
            preexistingUntrackedDirs: []
        ))))
        XCTAssertFalse(RolloutPolicy.shouldPersistResponseItemForMemories(.other))

        for type in [
            "local_shell_call",
            "function_call",
            "tool_search_call",
            "function_call_output",
            "tool_search_output",
            "custom_tool_call",
            "custom_tool_call_output",
            "web_search_call",
        ] {
            XCTAssertTrue(RolloutPolicy.shouldPersistResponseItemForMemories(.knownPersisted(type: type)), type)
        }

        for type in [
            "reasoning",
            "image_generation_call",
            "compaction",
            "context_compaction",
            "ghost_snapshot",
        ] {
            XCTAssertFalse(RolloutPolicy.shouldPersistResponseItemForMemories(.knownPersisted(type: type)), type)
        }
    }

    func testEventMessagePersistenceMatchesRustBuckets() {
        let limited: Set<RolloutEventMessageKind> = [
            .userMessage,
            .agentMessage,
            .agentReasoning,
            .agentReasoningRawContent,
            .patchApplyEnd,
            .tokenCount,
            .contextCompacted,
            .enteredReviewMode,
            .exitedReviewMode,
            .mcpToolCallEnd,
            .undoCompleted,
            .turnAborted,
            .threadRolledBack,
            .webSearchEnd,
            .imageGenerationEnd
        ]
        let extendedOnly: Set<RolloutEventMessageKind> = [
            .error,
            .execCommandEnd,
            .viewImageToolCall
        ]

        for event in RolloutEventMessageKind.allCases {
            XCTAssertEqual(
                RolloutPolicy.shouldPersistEventMessage(event),
                limited.contains(event),
                event.rawValue
            )
            XCTAssertEqual(
                RolloutPolicy.shouldPersistEventMessage(event, mode: .extended),
                limited.contains(event) || extendedOnly.contains(event),
                event.rawValue
            )
        }

        for event in limited {
            XCTAssertEqual(RolloutPolicy.eventMessagePersistenceMode(event), .limited, event.rawValue)
        }
        for event in extendedOnly {
            XCTAssertEqual(RolloutPolicy.eventMessagePersistenceMode(event), .extended, event.rawValue)
        }
    }

    func testEventMessageKindMappingFeedsPersistencePolicy() {
        XCTAssertEqual(RolloutPolicy.eventKind(for: .warning(WarningEvent(message: "heads up"))), .warning)
        XCTAssertEqual(RolloutPolicy.eventKind(for: .userMessage(UserMessageEvent(message: "hello"))), .userMessage)
        XCTAssertEqual(
            RolloutPolicy.eventKind(for: .imageGenerationBegin(ImageGenerationBeginEvent(callID: "ig-1"))),
            .imageGenerationBegin
        )
        XCTAssertEqual(
            RolloutPolicy.eventKind(for: .imageGenerationEnd(ImageGenerationEndEvent(
                callID: "ig-1",
                status: "completed",
                result: "base64-png"
            ))),
            .imageGenerationEnd
        )
        XCTAssertFalse(RolloutPolicy.shouldPersistEventMessage(.warning(WarningEvent(message: "heads up"))))
        XCTAssertTrue(RolloutPolicy.shouldPersistEventMessage(.userMessage(UserMessageEvent(message: "hello"))))
        XCTAssertTrue(RolloutPolicy.shouldPersistEventMessage(.threadRolledBack(ThreadRolledBackEvent(numTurns: 1))))
        XCTAssertFalse(RolloutPolicy.shouldPersistEventMessage(.imageGenerationBegin(ImageGenerationBeginEvent(callID: "ig-1"))))
        XCTAssertTrue(RolloutPolicy.shouldPersistEventMessage(.imageGenerationEnd(ImageGenerationEndEvent(
            callID: "ig-1",
            status: "completed",
            result: "base64-png"
        ))))
        XCTAssertFalse(RolloutPolicy.shouldPersistEventMessage(.error(ErrorEvent(message: "boom"))))
        XCTAssertTrue(RolloutPolicy.shouldPersistEventMessage(.error(ErrorEvent(message: "boom")), mode: .extended))
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
