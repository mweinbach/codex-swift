import CodexCore
import XCTest

final class RolloutForkingTests: XCTestCase {
    func testKeepsStableMessageRolesAndFinalAssistantLikeRustAgentControl() {
        let items: [RolloutRecordItem] = [
            message(role: "system", text: "system"),
            message(role: "developer", text: "developer"),
            message(role: "user", text: "user"),
            message(role: "assistant", text: "final", phase: .finalAnswer),
            message(role: "assistant", text: "commentary", phase: .commentary),
            message(role: "assistant", text: "missing phase"),
            message(role: "tool", text: "unexpected role"),
        ]

        XCTAssertEqual(
            RolloutForking.filteredForkHistory(items),
            Array(items[0...3])
        )
    }

    func testDropsToolLikeResponseItemsAndTurnContextLikeRustAgentControl() {
        let items: [RolloutRecordItem] = [
            .responseItem(.reasoning(id: "rs_1", summary: [])),
            .responseItem(.localShellCall(
                callID: "call_1",
                status: .completed,
                action: .exec(LocalShellExecAction(command: ["echo", "hi"]))
            )),
            .responseItem(.functionCall(name: "shell", arguments: "{}", callID: "call_2")),
            .responseItem(.toolSearchCall(execution: "search", arguments: .object([:]))),
            .responseItem(.functionCallOutput(
                callID: "call_2",
                output: FunctionCallOutputPayload(content: "ok")
            )),
            .responseItem(.customToolCall(callID: "call_3", name: "apply_patch", input: "*** Begin Patch")),
            .responseItem(.customToolCallOutput(callID: "call_3", output: FunctionCallOutputPayload(content: "ok"))),
            .responseItem(.toolSearchOutput(status: "completed", execution: "search", tools: [])),
            .responseItem(.webSearchCall(status: "completed", action: nil)),
            .responseItem(.imageGenerationCall(id: "img_1", status: "completed", result: "base64")),
            .responseItem(.ghostSnapshot(ghostCommit: GhostCommit(
                id: "deadbeef",
                preexistingUntrackedFiles: [],
                preexistingUntrackedDirs: []
            ))),
            .responseItem(.compaction(encryptedContent: "encrypted")),
            .responseItem(.contextCompaction(encryptedContent: "encrypted")),
            .responseItem(.knownPersisted(type: "future_item")),
            .responseItem(.other),
            .turnContext(TurnContextItem(
                cwd: "/repo",
                approvalPolicy: .onRequest,
                sandboxPolicy: .readOnly,
                model: "gpt-5.4",
                summary: .auto
            )),
            message(role: "user", text: "kept"),
        ]

        XCTAssertEqual(
            RolloutForking.filteredForkHistory(items),
            [message(role: "user", text: "kept")]
        )
    }

    func testKeepsCompactedEventAndSessionMetaLikeRustAgentControl() throws {
        let items: [RolloutRecordItem] = [
            .compacted(CompactedItem(message: "summary")),
            .eventMsg(.warning(WarningEvent(message: "heads up"))),
            .sessionMeta(SessionMetaLine(meta: SessionMeta(
                id: try ConversationId(string: "67e55044-10b1-426f-9247-bb680e5fe0c8"),
                timestamp: "2026-05-09T12:00:00.000Z",
                cwd: "/repo",
                originator: "codex-swift",
                cliVersion: "0.0.0"
            ))),
            .turnContext(TurnContextItem(
                cwd: "/repo",
                approvalPolicy: .never,
                sandboxPolicy: .readOnly,
                model: "gpt-5.4",
                summary: .auto
            )),
        ]

        XCTAssertEqual(
            RolloutForking.filteredForkHistory(items),
            Array(items[0...2])
        )
    }

    func testFiltersExactDeveloperUsageHintsBeforeKeepingDeveloperMessages() {
        let exactRootHint = message(role: "developer", text: "root usage hint")
        let exactSubagentHint = message(role: "developer", text: "subagent usage hint")
        let outputTextHint = RolloutRecordItem.responseItem(.message(
            role: "developer",
            content: [.outputText(text: "root usage hint")]
        ))
        let multiPartHint = RolloutRecordItem.responseItem(.message(
            role: "developer",
            content: [
                .inputText(text: "root usage hint"),
                .inputText(text: "extra"),
            ]
        ))
        let userText = message(role: "user", text: "root usage hint")
        let unrelatedDeveloper = message(role: "developer", text: "ordinary instruction")

        let items = [
            exactRootHint,
            exactSubagentHint,
            outputTextHint,
            multiPartHint,
            userText,
            unrelatedDeveloper,
        ]

        XCTAssertEqual(
            RolloutForking.filteredForkHistory(
                items,
                usageHintTextsToFilter: ["root usage hint", "subagent usage hint"]
            ),
            [
                outputTextHint,
                multiPartHint,
                userText,
                unrelatedDeveloper,
            ]
        )
    }

    private func message(
        role: String,
        text: String,
        phase: MessagePhase? = nil
    ) -> RolloutRecordItem {
        .responseItem(.message(role: role, content: [.inputText(text: text)], phase: phase))
    }
}
