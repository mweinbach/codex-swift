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
        _ = state.insertPendingRequestPermissions(
            key: "perm-1",
            pending: PendingRequestPermissions(
                sender: PendingApprovalSender(identifier: "tx-perm"),
                requestedPermissions: RequestPermissionProfile(network: .init(enabled: true)),
                cwd: "/repo"
            )
        )
        _ = state.insertPendingUserInput(key: "input-1", sender: PendingApprovalSender(identifier: "tx-input"))
        _ = state.insertPendingElicitation(
            key: ElicitationKey(serverName: "server", requestID: "req-1"),
            sender: PendingApprovalSender(identifier: "tx-elicit")
        )
        _ = state.insertPendingDynamicTool(key: "dyn-1", sender: PendingApprovalSender(identifier: "tx-dyn"))
        state.pushPendingInput(.message(role: "user", content: [.inputText(text: "queued")]))
        state.clearPending()

        XCTAssertEqual(state.pendingApprovalCount, 0)
        XCTAssertEqual(state.pendingRequestPermissionsCount, 0)
        XCTAssertEqual(state.pendingUserInputCount, 0)
        XCTAssertEqual(state.pendingElicitationCount, 0)
        XCTAssertEqual(state.pendingDynamicToolCount, 0)
        XCTAssertEqual(state.pendingInputCount, 0)
        XCTAssertEqual(state.takePendingInput(), [])
    }

    func testPendingRequestRegistriesReplaceAndRemoveLikeRustMaps() {
        var state = TurnState()
        let firstPermissions = PendingRequestPermissions(
            sender: PendingApprovalSender(identifier: "perm-1"),
            requestedPermissions: RequestPermissionProfile(network: .init(enabled: true)),
            cwd: "/repo"
        )
        let secondPermissions = PendingRequestPermissions(
            sender: PendingApprovalSender(identifier: "perm-2"),
            requestedPermissions: RequestPermissionProfile(fileSystem: FileSystemPermissions(entries: [])),
            cwd: "/other"
        )
        XCTAssertNil(state.insertPendingRequestPermissions(key: "call", pending: firstPermissions))
        XCTAssertEqual(state.insertPendingRequestPermissions(key: "call", pending: secondPermissions), firstPermissions)
        XCTAssertEqual(state.pendingRequestPermissionsCount, 1)
        XCTAssertEqual(state.removePendingRequestPermissions(key: "call"), secondPermissions)
        XCTAssertNil(state.removePendingRequestPermissions(key: "call"))

        let userInput = PendingApprovalSender(identifier: "user-input")
        XCTAssertNil(state.insertPendingUserInput(key: "sub", sender: userInput))
        XCTAssertEqual(state.insertPendingUserInput(key: "sub", sender: PendingApprovalSender(identifier: "new")), userInput)
        XCTAssertEqual(state.removePendingUserInput(key: "sub"), PendingApprovalSender(identifier: "new"))

        let elicitationKey = ElicitationKey(serverName: "server", requestID: "req")
        XCTAssertNil(state.insertPendingElicitation(key: elicitationKey, sender: PendingApprovalSender(identifier: "elicit")))
        XCTAssertEqual(
            state.insertPendingElicitation(key: elicitationKey, sender: PendingApprovalSender(identifier: "new-elicit")),
            PendingApprovalSender(identifier: "elicit")
        )
        XCTAssertEqual(state.removePendingElicitation(key: elicitationKey), PendingApprovalSender(identifier: "new-elicit"))

        XCTAssertNil(state.insertPendingDynamicTool(key: "tool", sender: PendingApprovalSender(identifier: "dynamic")))
        XCTAssertEqual(
            state.insertPendingDynamicTool(key: "tool", sender: PendingApprovalSender(identifier: "new-dynamic")),
            PendingApprovalSender(identifier: "dynamic")
        )
        XCTAssertEqual(state.removePendingDynamicTool(key: "tool"), PendingApprovalSender(identifier: "new-dynamic"))
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
        XCTAssertTrue(state.hasPendingInput)
        XCTAssertEqual(state.takePendingInput(), [first, second])
        XCTAssertEqual(state.pendingInputCount, 0)
        XCTAssertFalse(state.hasPendingInput)
        XCTAssertEqual(state.takePendingInput(), [])
    }

    func testPrependPendingInputKeepsOlderTailBeforeNewerInputLikeRust() {
        var state = TurnState()
        let later = ResponseInputItem.message(role: "user", content: [.inputText(text: "later queued prompt")])
        let newer = ResponseInputItem.message(role: "user", content: [.inputText(text: "newer queued prompt")])

        state.pushPendingInput(newer)
        state.prependPendingInput([later])

        XCTAssertEqual(state.takePendingInput(), [later, newer])
        state.prependPendingInput([])
        XCTAssertEqual(state.takePendingInput(), [])
    }

    func testMailboxPhaseAndTurnFlagsMatchRustDefaultsAndMutations() {
        var state = TurnState()

        XCTAssertTrue(state.acceptsMailboxDeliveryForCurrentTurn)
        XCTAssertFalse(state.hasMemoryCitation)
        XCTAssertFalse(state.isStrictAutoReviewEnabled)
        XCTAssertEqual(state.toolCallCount, 0)
        XCTAssertEqual(state.tokenUsageAtTurnStart, TokenUsage())

        state.setMailboxDeliveryPhase(.nextTurn)
        XCTAssertFalse(state.acceptsMailboxDeliveryForCurrentTurn)
        state.acceptMailboxDeliveryForCurrentTurn()
        XCTAssertTrue(state.acceptsMailboxDeliveryForCurrentTurn)

        state.incrementToolCallCount()
        state.incrementToolCallCount()
        state.recordMemoryCitationForTurn()
        state.enableStrictAutoReview()
        state.setTokenUsageAtTurnStart(TokenUsage(inputTokens: 3, outputTokens: 4, totalTokens: 7))

        XCTAssertEqual(state.toolCallCount, 2)
        XCTAssertTrue(state.hasMemoryCitation)
        XCTAssertTrue(state.isStrictAutoReviewEnabled)
        XCTAssertEqual(state.tokenUsageAtTurnStart, TokenUsage(inputTokens: 3, outputTokens: 4, totalTokens: 7))
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
