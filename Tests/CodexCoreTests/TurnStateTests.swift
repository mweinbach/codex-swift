import CodexCore
import XCTest

final class TurnStateTests: XCTestCase {
    func testPendingApprovalsInsertRemoveAndClearLikeRustHashMap() {
        var state = TurnState()

        XCTAssertNil(state.insertPendingApproval(key: "call-1", sender: PendingApprovalSender(identifier: "tx-1")))
        XCTAssertEqual(state.pendingApprovalCount, 1)

        XCTAssertEqual(
            state.insertPendingApproval(key: "call-1", sender: PendingApprovalSender(identifier: "tx-2")),
            PendingApprovalSender(identifier: "tx-1")
        )
        XCTAssertEqual(state.pendingApprovalCount, 1)

        XCTAssertEqual(
            state.removePendingApproval(key: "call-1"),
            PendingApprovalSender(identifier: "tx-2")
        )
        XCTAssertNil(state.removePendingApproval(key: "call-1"))

        _ = state.insertPendingApproval(key: "call-2", sender: PendingApprovalSender(identifier: "tx-3"))
        state.pushPendingInput(.message(role: "user", content: [.inputText(text: "queued")]))
        state.clearPending()

        XCTAssertEqual(state.pendingApprovalCount, 0)
        XCTAssertEqual(state.pendingInputCount, 0)
        XCTAssertEqual(state.takePendingInput(), [])
    }

    func testPendingInputIsFIFOTakeAndClear() {
        var state = TurnState()
        let first = ResponseInputItem.message(role: "user", content: [.inputText(text: "first")])
        let second = ResponseInputItem.functionCallOutput(
            callID: "call-1",
            output: FunctionCallOutputPayload(content: "done")
        )

        state.pushPendingInput(first)
        state.pushPendingInput(second)

        XCTAssertEqual(state.pendingInputCount, 2)
        XCTAssertEqual(state.takePendingInput(), [first, second])
        XCTAssertEqual(state.pendingInputCount, 0)
        XCTAssertEqual(state.takePendingInput(), [])
    }

    func testActiveTurnTaskOrderingReplacementAndDrain() {
        var activeTurn = ActiveTurn()
        let first = runningTask(subID: "a", kind: .regular)
        let second = runningTask(subID: "b", kind: .review)
        let replacement = runningTask(subID: "a", kind: .compact)

        activeTurn.addTask(first)
        activeTurn.addTask(second)
        activeTurn.addTask(replacement)

        XCTAssertEqual(activeTurn.taskCount, 2)
        XCTAssertEqual(activeTurn.taskSubIDs, ["a", "b"])
        XCTAssertEqual(activeTurn.drainTasks(), [replacement, second])
        XCTAssertEqual(activeTurn.taskCount, 0)
        XCTAssertEqual(activeTurn.drainTasks(), [])
    }

    func testActiveTurnRemoveUsesRustSwapRemoveOrderAndEmptyReturn() {
        var activeTurn = ActiveTurn(tasks: [
            runningTask(subID: "a", kind: .regular),
            runningTask(subID: "b", kind: .review),
            runningTask(subID: "c", kind: .compact)
        ])

        XCTAssertFalse(activeTurn.removeTask(subID: "b"))
        XCTAssertEqual(activeTurn.taskSubIDs, ["a", "c"])
        XCTAssertFalse(activeTurn.removeTask(subID: "missing"))
        XCTAssertFalse(activeTurn.removeTask(subID: "a"))
        XCTAssertTrue(activeTurn.removeTask(subID: "c"))
        XCTAssertTrue(activeTurn.removeTask(subID: "missing"))
    }

    func testActiveTurnClearPendingDelegatesToTurnState() {
        var turnState = TurnState()
        _ = turnState.insertPendingApproval(key: "call-1", sender: PendingApprovalSender(identifier: "tx-1"))
        turnState.pushPendingInput(.message(role: "user", content: [.inputText(text: "queued")]))
        var activeTurn = ActiveTurn(turnState: turnState)

        activeTurn.clearPending()

        XCTAssertEqual(activeTurn.turnState.pendingApprovalCount, 0)
        XCTAssertEqual(activeTurn.turnState.pendingInputCount, 0)
    }

    private func runningTask(subID: String, kind: TaskKind) -> RunningTask {
        RunningTask(
            subID: subID,
            kind: kind,
            turnContext: TurnContext(
                cwd: "/repo/\(subID)",
                approvalPolicy: .onRequest,
                sandboxPolicy: .readOnly
            )
        )
    }
}
