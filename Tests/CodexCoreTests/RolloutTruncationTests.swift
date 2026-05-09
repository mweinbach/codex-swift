import CodexCore
import XCTest

final class RolloutTruncationTests: XCTestCase {
    func testTruncatesRolloutFromStartBeforeNthUserOnly() {
        let items: [RolloutRecordItem] = [
            .responseItem(userMessage("u1")),
            .responseItem(assistantMessage("a1")),
            .responseItem(assistantMessage("a2")),
            .responseItem(userMessage("u2")),
            .responseItem(assistantMessage("a3")),
            .responseItem(.reasoning(id: "r1", summary: [.summaryText(text: "s")])),
            .responseItem(.functionCall(name: "tool", arguments: "{}", callID: "c1")),
            .responseItem(assistantMessage("a4"))
        ]

        XCTAssertEqual(
            RolloutTruncation.truncateBeforeNthUserMessageFromStart(items, nFromStart: 1),
            Array(items[..<3])
        )
        XCTAssertEqual(
            RolloutTruncation.truncateBeforeNthUserMessageFromStart(items, nFromStart: 2),
            items
        )
    }

    func testTruncationMaxKeepsFullRollout() {
        let items: [RolloutRecordItem] = [
            .responseItem(userMessage("u1")),
            .responseItem(assistantMessage("a1")),
            .responseItem(userMessage("u2"))
        ]

        XCTAssertEqual(
            RolloutTruncation.truncateBeforeNthUserMessageFromStart(items, nFromStart: Int.max),
            items
        )
    }

    func testTruncatesRolloutFromStartAppliesThreadRollbackMarkers() {
        let items: [RolloutRecordItem] = [
            .responseItem(userMessage("u1")),
            .responseItem(assistantMessage("a1")),
            .responseItem(userMessage("u2")),
            .responseItem(assistantMessage("a2")),
            .eventMsg(.threadRolledBack(ThreadRolledBackEvent(numTurns: 1))),
            .responseItem(userMessage("u3")),
            .responseItem(assistantMessage("a3")),
            .responseItem(userMessage("u4")),
            .responseItem(assistantMessage("a4"))
        ]

        XCTAssertEqual(
            RolloutTruncation.truncateBeforeNthUserMessageFromStart(items, nFromStart: 2),
            Array(items[..<7])
        )
    }

    func testForkTurnPositionsCountTriggerTurnMessages() throws {
        let items: [RolloutRecordItem] = [
            .responseItem(userMessage("u1")),
            .responseItem(assistantMessage("a1")),
            .responseItem(try interAgentMessage("queued message", triggerTurn: false)),
            .responseItem(assistantMessage("a2")),
            .responseItem(try interAgentMessage("triggered task", triggerTurn: true)),
            .responseItem(assistantMessage("a3")),
            .responseItem(userMessage("u2")),
            .responseItem(assistantMessage("a4"))
        ]

        XCTAssertEqual(RolloutTruncation.forkTurnPositions(in: items), [0, 4, 6])
        XCTAssertEqual(RolloutTruncation.truncateToLastNForkTurns(items, nFromEnd: 2), Array(items[4...]))
    }

    func testForkTurnRollbackDiscardsRolledBackTriggerSuffix() throws {
        let items: [RolloutRecordItem] = [
            .responseItem(userMessage("u1")),
            .responseItem(userMessage("u2")),
            .responseItem(try interAgentMessage("triggered task", triggerTurn: true)),
            .responseItem(assistantMessage("a1")),
            .eventMsg(.threadRolledBack(ThreadRolledBackEvent(numTurns: 1))),
            .responseItem(userMessage("u3")),
            .responseItem(assistantMessage("a2"))
        ]

        XCTAssertEqual(RolloutTruncation.truncateToLastNForkTurns(items, nFromEnd: 2), Array(items[1...]))
    }

    func testForkTurnRollbackUsesAssistantInstructionTurnsForRollbackOnly() throws {
        let items: [RolloutRecordItem] = [
            .responseItem(userMessage("u1")),
            .responseItem(assistantMessage("a1")),
            .responseItem(try interAgentMessage("triggered task 1", triggerTurn: true)),
            .responseItem(assistantMessage("a2")),
            .eventMsg(.threadRolledBack(ThreadRolledBackEvent(numTurns: 1))),
            .responseItem(try interAgentMessage("triggered task 2", triggerTurn: true)),
            .responseItem(assistantMessage("a3"))
        ]

        XCTAssertEqual(RolloutTruncation.truncateToLastNForkTurns(items, nFromEnd: 1), Array(items[5...]))
    }

    func testInitialHistoryDetectsPriorUserTurns() {
        XCTAssertFalse(RolloutTruncation.initialHistoryHasPriorUserTurns(.new))
        XCTAssertFalse(RolloutTruncation.initialHistoryHasPriorUserTurns(.forked([
            .responseItem(assistantMessage("a1"))
        ])))
        XCTAssertTrue(RolloutTruncation.initialHistoryHasPriorUserTurns(.forked([
            .responseItem(userMessage("u1"))
        ])))
    }

    private func userMessage(_ text: String) -> ResponseItem {
        .message(role: "user", content: [.outputText(text: text)])
    }

    private func assistantMessage(_ text: String) -> ResponseItem {
        .message(role: "assistant", content: [.outputText(text: text)])
    }

    private func interAgentMessage(_ text: String, triggerTurn: Bool) throws -> ResponseItem {
        InterAgentCommunication(
            author: .root,
            recipient: try AgentPath.root.join("worker"),
            content: text,
            triggerTurn: triggerTurn
        ).toResponseInputItem().responseItem()
    }
}
