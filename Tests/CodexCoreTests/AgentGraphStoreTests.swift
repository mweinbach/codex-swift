import CodexCore
import SQLite3
import XCTest

final class AgentGraphStoreTests: XCTestCase {
    func testThreadSpawnEdgeStatusSerializesAsSnakeCase() throws {
        XCTAssertEqual(try jsonString(ThreadSpawnEdgeStatus.open), #""open""#)
        XCTAssertEqual(try jsonString(ThreadSpawnEdgeStatus.closed), #""closed""#)
        XCTAssertEqual(try JSONDecoder().decode(ThreadSpawnEdgeStatus.self, from: Data(#""open""#.utf8)), .open)
        XCTAssertEqual(try JSONDecoder().decode(ThreadSpawnEdgeStatus.self, from: Data(#""closed""#.utf8)), .closed)
    }

    func testAgentGraphStoreErrorsMatchRustDisplayStrings() {
        XCTAssertEqual(
            AgentGraphStoreError.invalidRequest(message: "missing parent").description,
            "invalid agent graph store request: missing parent"
        )
        XCTAssertEqual(
            AgentGraphStoreError.internal(message: "sqlite failed").description,
            "agent graph store internal error: sqlite failed"
        )
    }

    func testInMemoryStoreUpsertsAndListsDirectChildrenWithStatusFilters() async throws {
        let store = InMemoryAgentGraphStore()
        let parentThreadID = try threadID(1)
        let firstChildThreadID = try threadID(2)
        let secondChildThreadID = try threadID(3)

        try await store.upsertThreadSpawnEdge(
            parentThreadID: parentThreadID,
            childThreadID: secondChildThreadID,
            status: .closed
        )
        try await store.upsertThreadSpawnEdge(
            parentThreadID: parentThreadID,
            childThreadID: firstChildThreadID,
            status: .open
        )

        let allChildren = try await store.listThreadSpawnChildren(
            parentThreadID: parentThreadID,
            statusFilter: nil
        )
        XCTAssertEqual(allChildren, [firstChildThreadID, secondChildThreadID])

        let openChildren = try await store.listThreadSpawnChildren(
            parentThreadID: parentThreadID,
            statusFilter: .open
        )
        XCTAssertEqual(openChildren, [firstChildThreadID])

        let closedChildren = try await store.listThreadSpawnChildren(
            parentThreadID: parentThreadID,
            statusFilter: .closed
        )
        XCTAssertEqual(closedChildren, [secondChildThreadID])
    }

    func testInMemoryStoreUpdatesEdgeStatusAndMissingChildIsNoOp() async throws {
        let store = InMemoryAgentGraphStore()
        let parentThreadID = try threadID(10)
        let childThreadID = try threadID(11)

        try await store.upsertThreadSpawnEdge(
            parentThreadID: parentThreadID,
            childThreadID: childThreadID,
            status: .open
        )
        try await store.setThreadSpawnEdgeStatus(childThreadID: childThreadID, status: .closed)
        try await store.setThreadSpawnEdgeStatus(childThreadID: try threadID(12), status: .closed)

        let openChildren = try await store.listThreadSpawnChildren(
            parentThreadID: parentThreadID,
            statusFilter: .open
        )
        XCTAssertEqual(openChildren, [])

        let closedChildren = try await store.listThreadSpawnChildren(
            parentThreadID: parentThreadID,
            statusFilter: .closed
        )
        XCTAssertEqual(closedChildren, [childThreadID])
    }

    func testInMemoryStoreReparentsChildOnUpsert() async throws {
        let store = InMemoryAgentGraphStore()
        let firstParentThreadID = try threadID(13)
        let secondParentThreadID = try threadID(14)
        let childThreadID = try threadID(15)

        try await store.upsertThreadSpawnEdge(
            parentThreadID: firstParentThreadID,
            childThreadID: childThreadID,
            status: .open
        )
        try await store.upsertThreadSpawnEdge(
            parentThreadID: secondParentThreadID,
            childThreadID: childThreadID,
            status: .closed
        )

        let firstParentChildren = try await store.listThreadSpawnChildren(
            parentThreadID: firstParentThreadID,
            statusFilter: nil
        )
        XCTAssertEqual(firstParentChildren, [])

        let secondParentChildren = try await store.listThreadSpawnChildren(
            parentThreadID: secondParentThreadID,
            statusFilter: nil
        )
        XCTAssertEqual(secondParentChildren, [childThreadID])

        let closedSecondParentChildren = try await store.listThreadSpawnChildren(
            parentThreadID: secondParentThreadID,
            statusFilter: .closed
        )
        XCTAssertEqual(closedSecondParentChildren, [childThreadID])
    }

    func testInMemoryStoreInsertsThreadSpawnEdgeFromSourceOnlyWhenAbsent() async throws {
        let store = InMemoryAgentGraphStore()
        let firstParentThreadID = try threadID(16)
        let secondParentThreadID = try threadID(17)
        let childThreadID = try threadID(18)
        let source = try persistedSource(
            .subagent(.threadSpawn(parentThreadID: firstParentThreadID, depth: 2))
        )

        try await store.insertThreadSpawnEdgeFromSourceIfAbsent(
            childThreadID: childThreadID,
            source: source
        )
        try await store.insertThreadSpawnEdgeFromSourceIfAbsent(
            childThreadID: try threadID(19),
            source: "cli"
        )

        let inferredChildren = try await store.listThreadSpawnChildren(
            parentThreadID: firstParentThreadID,
            statusFilter: .open
        )
        XCTAssertEqual(inferredChildren, [childThreadID])

        try await store.upsertThreadSpawnEdge(
            parentThreadID: secondParentThreadID,
            childThreadID: childThreadID,
            status: .closed
        )
        try await store.insertThreadSpawnEdgeFromSourceIfAbsent(
            childThreadID: childThreadID,
            source: source
        )

        let firstParentChildren = try await store.listThreadSpawnChildren(
            parentThreadID: firstParentThreadID,
            statusFilter: nil
        )
        XCTAssertEqual(firstParentChildren, [])

        let secondParentClosedChildren = try await store.listThreadSpawnChildren(
            parentThreadID: secondParentThreadID,
            statusFilter: .closed
        )
        XCTAssertEqual(secondParentClosedChildren, [childThreadID])
    }

    func testInMemoryStoreListsDescendantsBreadthFirstWithStatusFilters() async throws {
        let store = InMemoryAgentGraphStore()
        let rootThreadID = try threadID(20)
        let laterChildThreadID = try threadID(22)
        let earlierChildThreadID = try threadID(21)
        let closedGrandchildThreadID = try threadID(23)
        let openGrandchildThreadID = try threadID(24)
        let closedChildThreadID = try threadID(25)
        let closedGreatGrandchildThreadID = try threadID(26)

        for (parentThreadID, childThreadID, status) in [
            (rootThreadID, laterChildThreadID, ThreadSpawnEdgeStatus.open),
            (rootThreadID, earlierChildThreadID, ThreadSpawnEdgeStatus.open),
            (earlierChildThreadID, openGrandchildThreadID, ThreadSpawnEdgeStatus.open),
            (laterChildThreadID, closedGrandchildThreadID, ThreadSpawnEdgeStatus.closed),
            (rootThreadID, closedChildThreadID, ThreadSpawnEdgeStatus.closed),
            (closedChildThreadID, closedGreatGrandchildThreadID, ThreadSpawnEdgeStatus.closed),
        ] {
            try await store.upsertThreadSpawnEdge(
                parentThreadID: parentThreadID,
                childThreadID: childThreadID,
                status: status
            )
        }

        let allDescendants = try await store.listThreadSpawnDescendants(
            rootThreadID: rootThreadID,
            statusFilter: nil
        )
        XCTAssertEqual(
            allDescendants,
            [
                earlierChildThreadID,
                laterChildThreadID,
                closedChildThreadID,
                closedGrandchildThreadID,
                openGrandchildThreadID,
                closedGreatGrandchildThreadID,
            ]
        )

        let openDescendants = try await store.listThreadSpawnDescendants(
            rootThreadID: rootThreadID,
            statusFilter: .open
        )
        XCTAssertEqual(
            openDescendants,
            [
                earlierChildThreadID,
                laterChildThreadID,
                openGrandchildThreadID,
            ]
        )

        let closedDescendants = try await store.listThreadSpawnDescendants(
            rootThreadID: rootThreadID,
            statusFilter: .closed
        )
        XCTAssertEqual(closedDescendants, [closedChildThreadID, closedGreatGrandchildThreadID])
    }

    func testSQLiteStorePersistsEdgesAcrossReopen() async throws {
        let temp = try AgentGraphStoreTemporaryDirectory()
        let databaseURL = temp.url.appendingPathComponent("state.sqlite3")
        let parentThreadID = try threadID(30)
        let openChildThreadID = try threadID(31)
        let closedChildThreadID = try threadID(32)
        let futureChildThreadID = try threadID(33)

        do {
            let store = try SQLiteAgentGraphStore(databaseURL: databaseURL)
            try await store.upsertThreadSpawnEdge(
                parentThreadID: parentThreadID,
                childThreadID: closedChildThreadID,
                status: .closed
            )
            try await store.upsertThreadSpawnEdge(
                parentThreadID: parentThreadID,
                childThreadID: openChildThreadID,
                status: .open
            )
        }

        let reopenedStore = try SQLiteAgentGraphStore(databaseURL: databaseURL)
        try insertRawSQLiteThreadSpawnEdge(
            databaseURL: databaseURL,
            parentThreadID: parentThreadID,
            childThreadID: futureChildThreadID,
            status: "future"
        )

        let allChildren = try await reopenedStore.listThreadSpawnChildren(
            parentThreadID: parentThreadID,
            statusFilter: nil
        )
        XCTAssertEqual(allChildren, [openChildThreadID, closedChildThreadID, futureChildThreadID])

        let openChildren = try await reopenedStore.listThreadSpawnChildren(
            parentThreadID: parentThreadID,
            statusFilter: .open
        )
        XCTAssertEqual(openChildren, [openChildThreadID])
    }

    func testSQLiteStoreUpsertsStatusAndReparentsChild() async throws {
        let temp = try AgentGraphStoreTemporaryDirectory()
        let store = try SQLiteAgentGraphStore(databaseURL: temp.url.appendingPathComponent("state.sqlite3"))
        let firstParentThreadID = try threadID(40)
        let secondParentThreadID = try threadID(41)
        let childThreadID = try threadID(42)

        try await store.upsertThreadSpawnEdge(
            parentThreadID: firstParentThreadID,
            childThreadID: childThreadID,
            status: .open
        )
        try await store.upsertThreadSpawnEdge(
            parentThreadID: secondParentThreadID,
            childThreadID: childThreadID,
            status: .open
        )
        try await store.setThreadSpawnEdgeStatus(childThreadID: childThreadID, status: .closed)
        try await store.setThreadSpawnEdgeStatus(childThreadID: try threadID(43), status: .closed)

        let firstParentChildren = try await store.listThreadSpawnChildren(
            parentThreadID: firstParentThreadID,
            statusFilter: nil
        )
        XCTAssertEqual(firstParentChildren, [])

        let openSecondParentChildren = try await store.listThreadSpawnChildren(
            parentThreadID: secondParentThreadID,
            statusFilter: .open
        )
        XCTAssertEqual(openSecondParentChildren, [])

        let closedSecondParentChildren = try await store.listThreadSpawnChildren(
            parentThreadID: secondParentThreadID,
            statusFilter: .closed
        )
        XCTAssertEqual(closedSecondParentChildren, [childThreadID])
    }

    func testSQLiteStoreInsertsThreadSpawnEdgeFromSourceOnlyWhenAbsent() async throws {
        let temp = try AgentGraphStoreTemporaryDirectory()
        let store = try SQLiteAgentGraphStore(databaseURL: temp.url.appendingPathComponent("state.sqlite3"))
        let firstParentThreadID = try threadID(44)
        let secondParentThreadID = try threadID(45)
        let childThreadID = try threadID(46)
        let source = try persistedSource(
            .subagent(.threadSpawn(parentThreadID: firstParentThreadID, depth: 1))
        )

        try await store.insertThreadSpawnEdgeFromSourceIfAbsent(
            childThreadID: childThreadID,
            source: source
        )
        try await store.insertThreadSpawnEdgeFromSourceIfAbsent(
            childThreadID: try threadID(47),
            source: "exec"
        )

        let inferredChildren = try await store.listThreadSpawnChildren(
            parentThreadID: firstParentThreadID,
            statusFilter: .open
        )
        XCTAssertEqual(inferredChildren, [childThreadID])

        try await store.upsertThreadSpawnEdge(
            parentThreadID: secondParentThreadID,
            childThreadID: childThreadID,
            status: .closed
        )
        try await store.insertThreadSpawnEdgeFromSourceIfAbsent(
            childThreadID: childThreadID,
            source: source
        )

        let firstParentChildren = try await store.listThreadSpawnChildren(
            parentThreadID: firstParentThreadID,
            statusFilter: nil
        )
        XCTAssertEqual(firstParentChildren, [])

        let secondParentClosedChildren = try await store.listThreadSpawnChildren(
            parentThreadID: secondParentThreadID,
            statusFilter: .closed
        )
        XCTAssertEqual(secondParentClosedChildren, [childThreadID])
    }

    func testSQLiteStoreListsDescendantsBreadthFirstWithStatusFilters() async throws {
        let temp = try AgentGraphStoreTemporaryDirectory()
        let store = try SQLiteAgentGraphStore(databaseURL: temp.url.appendingPathComponent("state.sqlite3"))
        let rootThreadID = try threadID(50)
        let laterChildThreadID = try threadID(52)
        let earlierChildThreadID = try threadID(51)
        let closedGrandchildThreadID = try threadID(53)
        let openGrandchildThreadID = try threadID(54)
        let closedChildThreadID = try threadID(55)
        let closedGreatGrandchildThreadID = try threadID(56)

        for (parentThreadID, childThreadID, status) in [
            (rootThreadID, laterChildThreadID, ThreadSpawnEdgeStatus.open),
            (rootThreadID, earlierChildThreadID, ThreadSpawnEdgeStatus.open),
            (earlierChildThreadID, openGrandchildThreadID, ThreadSpawnEdgeStatus.open),
            (laterChildThreadID, closedGrandchildThreadID, ThreadSpawnEdgeStatus.closed),
            (rootThreadID, closedChildThreadID, ThreadSpawnEdgeStatus.closed),
            (closedChildThreadID, closedGreatGrandchildThreadID, ThreadSpawnEdgeStatus.closed),
        ] {
            try await store.upsertThreadSpawnEdge(
                parentThreadID: parentThreadID,
                childThreadID: childThreadID,
                status: status
            )
        }

        let allDescendants = try await store.listThreadSpawnDescendants(
            rootThreadID: rootThreadID,
            statusFilter: nil
        )
        XCTAssertEqual(
            allDescendants,
            [
                earlierChildThreadID,
                laterChildThreadID,
                closedChildThreadID,
                closedGrandchildThreadID,
                openGrandchildThreadID,
                closedGreatGrandchildThreadID,
            ]
        )

        let openDescendants = try await store.listThreadSpawnDescendants(
            rootThreadID: rootThreadID,
            statusFilter: .open
        )
        XCTAssertEqual(
            openDescendants,
            [
                earlierChildThreadID,
                laterChildThreadID,
                openGrandchildThreadID,
            ]
        )

        let closedDescendants = try await store.listThreadSpawnDescendants(
            rootThreadID: rootThreadID,
            statusFilter: .closed
        )
        XCTAssertEqual(closedDescendants, [closedChildThreadID, closedGreatGrandchildThreadID])
    }

    func testSQLiteStoreFindsDirectChildAndDescendantByAgentPath() async throws {
        let temp = try AgentGraphStoreTemporaryDirectory()
        let databaseURL = temp.url.appendingPathComponent("state.sqlite3")
        let store = try SQLiteAgentGraphStore(databaseURL: databaseURL)
        try createMinimalThreadsTable(databaseURL: databaseURL)
        let rootThreadID = try threadID(60)
        let childThreadID = try threadID(61)
        let grandchildThreadID = try threadID(62)
        let childPath = try AgentPath(validating: "/root/reviewer")
        let grandchildPath = try AgentPath(validating: "/root/reviewer/researcher")
        let missingPath = try AgentPath(validating: "/root/missing")

        try insertRawSQLiteThread(id: childThreadID, agentPath: childPath, databaseURL: databaseURL)
        try insertRawSQLiteThread(id: grandchildThreadID, agentPath: grandchildPath, databaseURL: databaseURL)
        try await store.upsertThreadSpawnEdge(
            parentThreadID: rootThreadID,
            childThreadID: childThreadID,
            status: .open
        )
        try await store.upsertThreadSpawnEdge(
            parentThreadID: childThreadID,
            childThreadID: grandchildThreadID,
            status: .closed
        )

        let directChild = try await store.findThreadSpawnChild(
            parentThreadID: rootThreadID,
            agentPath: childPath
        )
        XCTAssertEqual(directChild, childThreadID)

        let directGrandchild = try await store.findThreadSpawnChild(
            parentThreadID: rootThreadID,
            agentPath: grandchildPath
        )
        XCTAssertNil(directGrandchild)

        let descendant = try await store.findThreadSpawnDescendant(
            rootThreadID: rootThreadID,
            agentPath: grandchildPath
        )
        XCTAssertEqual(descendant, grandchildThreadID)

        let missing = try await store.findThreadSpawnDescendant(
            rootThreadID: rootThreadID,
            agentPath: missingPath
        )
        XCTAssertNil(missing)
    }

    func testSQLiteStoreFindByAgentPathReportsDuplicateCanonicalPath() async throws {
        let temp = try AgentGraphStoreTemporaryDirectory()
        let databaseURL = temp.url.appendingPathComponent("state.sqlite3")
        let store = try SQLiteAgentGraphStore(databaseURL: databaseURL)
        try createMinimalThreadsTable(databaseURL: databaseURL)
        let rootThreadID = try threadID(70)
        let firstChildThreadID = try threadID(71)
        let secondChildThreadID = try threadID(72)
        let duplicatePath = try AgentPath(validating: "/root/worker")

        try insertRawSQLiteThread(id: firstChildThreadID, agentPath: duplicatePath, databaseURL: databaseURL)
        try insertRawSQLiteThread(id: secondChildThreadID, agentPath: duplicatePath, databaseURL: databaseURL)
        try await store.upsertThreadSpawnEdge(
            parentThreadID: rootThreadID,
            childThreadID: firstChildThreadID,
            status: .open
        )
        try await store.upsertThreadSpawnEdge(
            parentThreadID: rootThreadID,
            childThreadID: secondChildThreadID,
            status: .open
        )

        do {
            _ = try await store.findThreadSpawnChild(
                parentThreadID: rootThreadID,
                agentPath: duplicatePath
            )
            XCTFail("duplicate canonical path lookup should fail")
        } catch let error as AgentGraphStoreError {
            XCTAssertEqual(
                error,
                .internal(message: "multiple agents found for canonical path `/root/worker`")
            )
        }
    }

    func testSQLiteStorePersistsDynamicToolsInPositionOrderWithoutOverwriting() async throws {
        let temp = try AgentGraphStoreTemporaryDirectory()
        let databaseURL = temp.url.appendingPathComponent("state.sqlite3")
        let store = try SQLiteAgentGraphStore(databaseURL: databaseURL)
        try createMinimalThreadsTable(databaseURL: databaseURL)
        let threadID = try threadID(80)
        try insertRawSQLiteThread(
            id: threadID,
            agentPath: try AgentPath(validating: "/root/tools"),
            databaseURL: databaseURL
        )

        let missingTools = try await store.getDynamicTools(threadID: threadID)
        XCTAssertNil(missingTools)
        try await store.persistDynamicTools(threadID: threadID, tools: nil)
        try await store.persistDynamicTools(threadID: threadID, tools: [])
        let stillMissingTools = try await store.getDynamicTools(threadID: threadID)
        XCTAssertNil(stillMissingTools)

        let firstTools = [
            DynamicToolSpec(
                namespace: "mcp_server",
                name: "lookup",
                description: "Look up a record",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "query": .object(["type": .string("string")])
                    ])
                ]),
                deferLoading: true
            ),
            DynamicToolSpec(
                name: "summarize",
                description: "Summarize content",
                inputSchema: .object(["type": .string("object")])
            ),
        ]
        let replacementTools = [
            DynamicToolSpec(
                name: "replacement",
                description: "Should not overwrite position zero",
                inputSchema: .object(["type": .string("object")])
            ),
            DynamicToolSpec(
                namespace: "later",
                name: "also-replacement",
                description: "Should not overwrite position one",
                inputSchema: .object(["type": .string("object")]),
                deferLoading: true
            ),
        ]

        try await store.persistDynamicTools(threadID: threadID, tools: firstTools)
        try await store.persistDynamicTools(threadID: threadID, tools: replacementTools)

        let storedTools = try await store.getDynamicTools(threadID: threadID)
        XCTAssertEqual(storedTools, firstTools)
    }

    func testSQLiteStoreGetsAndSetsThreadMemoryMode() async throws {
        let temp = try AgentGraphStoreTemporaryDirectory()
        let databaseURL = temp.url.appendingPathComponent("state.sqlite3")
        let store = try SQLiteAgentGraphStore(databaseURL: databaseURL)
        try createMinimalThreadsTable(databaseURL: databaseURL)
        let memoryThreadID = try threadID(81)
        let nullModeThreadID = try threadID(82)
        let missingThreadID = try threadID(83)
        try insertRawSQLiteThread(
            id: memoryThreadID,
            agentPath: try AgentPath(validating: "/root/memory"),
            memoryMode: "enabled",
            databaseURL: databaseURL
        )
        try insertRawSQLiteThread(
            id: nullModeThreadID,
            agentPath: try AgentPath(validating: "/root/memory_null"),
            memoryMode: nil,
            databaseURL: databaseURL
        )

        let initialMode = try await store.getThreadMemoryMode(threadID: memoryThreadID)
        let nullMode = try await store.getThreadMemoryMode(threadID: nullModeThreadID)
        let missingMode = try await store.getThreadMemoryMode(threadID: missingThreadID)
        XCTAssertEqual(initialMode, "enabled")
        XCTAssertNil(nullMode)
        XCTAssertNil(missingMode)

        let updated = try await store.setThreadMemoryMode(threadID: memoryThreadID, memoryMode: "disabled")
        let missingUpdated = try await store.setThreadMemoryMode(threadID: missingThreadID, memoryMode: "polluted")
        let updatedMode = try await store.getThreadMemoryMode(threadID: memoryThreadID)

        XCTAssertTrue(updated)
        XCTAssertFalse(missingUpdated)
        XCTAssertEqual(updatedMode, "disabled")
    }

    func testSQLiteStoreFindsRolloutPathWithArchiveFilter() async throws {
        let temp = try AgentGraphStoreTemporaryDirectory()
        let databaseURL = temp.url.appendingPathComponent("state.sqlite3")
        let store = try SQLiteAgentGraphStore(databaseURL: databaseURL)
        try createMinimalThreadsTable(databaseURL: databaseURL)
        let activeThreadID = try threadID(84)
        let archivedThreadID = try threadID(85)
        let missingThreadID = try threadID(86)
        try insertRawSQLiteThread(
            id: activeThreadID,
            agentPath: try AgentPath(validating: "/root/active"),
            rolloutPath: "/tmp/active-rollout.jsonl",
            archived: false,
            databaseURL: databaseURL
        )
        try insertRawSQLiteThread(
            id: archivedThreadID,
            agentPath: try AgentPath(validating: "/root/archived"),
            rolloutPath: "/tmp/archived-rollout.jsonl",
            archived: true,
            databaseURL: databaseURL
        )

        let activeAnyPath = try await store.findRolloutPath(threadID: activeThreadID, archiveFilter: .all)
        let archivedAnyPath = try await store.findRolloutPath(threadID: archivedThreadID, archiveFilter: .all)
        let activePath = try await store.findRolloutPath(threadID: activeThreadID, archiveFilter: .unarchivedOnly)
        let archivedPath = try await store.findRolloutPath(threadID: archivedThreadID, archiveFilter: .archivedOnly)
        let activeArchivedPath = try await store.findRolloutPath(threadID: activeThreadID, archiveFilter: .archivedOnly)
        let archivedActivePath = try await store.findRolloutPath(threadID: archivedThreadID, archiveFilter: .unarchivedOnly)
        let missingPath = try await store.findRolloutPath(threadID: missingThreadID, archiveFilter: .all)

        XCTAssertEqual(activeAnyPath, "/tmp/active-rollout.jsonl")
        XCTAssertEqual(archivedAnyPath, "/tmp/archived-rollout.jsonl")
        XCTAssertEqual(activePath, "/tmp/active-rollout.jsonl")
        XCTAssertEqual(archivedPath, "/tmp/archived-rollout.jsonl")
        XCTAssertNil(activeArchivedPath)
        XCTAssertNil(archivedActivePath)
        XCTAssertNil(missingPath)
    }

    func testSQLiteStoreUpdatesThreadTitle() async throws {
        let temp = try AgentGraphStoreTemporaryDirectory()
        let databaseURL = temp.url.appendingPathComponent("state.sqlite3")
        let store = try SQLiteAgentGraphStore(databaseURL: databaseURL)
        try createMinimalThreadsTable(databaseURL: databaseURL)
        let titledThreadID = try threadID(87)
        let missingThreadID = try threadID(88)
        try insertRawSQLiteThread(
            id: titledThreadID,
            agentPath: try AgentPath(validating: "/root/title"),
            title: "Old title",
            databaseURL: databaseURL
        )

        let updated = try await store.updateThreadTitle(threadID: titledThreadID, title: "New title")
        let missingUpdated = try await store.updateThreadTitle(threadID: missingThreadID, title: "Missing title")
        let title = try readRawSQLiteThreadTitle(id: titledThreadID, databaseURL: databaseURL)

        XCTAssertTrue(updated)
        XCTAssertFalse(missingUpdated)
        XCTAssertEqual(title, "New title")
    }

    func testSQLiteStoreTouchesThreadUpdatedAtWithRustAllocatorSemantics() async throws {
        let temp = try AgentGraphStoreTemporaryDirectory()
        let databaseURL = temp.url.appendingPathComponent("state.sqlite3")
        let store = try SQLiteAgentGraphStore(databaseURL: databaseURL)
        try createMinimalThreadsTable(databaseURL: databaseURL)
        let firstThreadID = try threadID(89)
        let secondThreadID = try threadID(90)
        let backfillThreadID = try threadID(91)
        let missingThreadID = try threadID(92)
        try insertRawSQLiteThread(
            id: firstThreadID,
            agentPath: try AgentPath(validating: "/root/updated_first"),
            databaseURL: databaseURL
        )
        try insertRawSQLiteThread(
            id: secondThreadID,
            agentPath: try AgentPath(validating: "/root/updated_second"),
            databaseURL: databaseURL
        )
        try insertRawSQLiteThread(
            id: backfillThreadID,
            agentPath: try AgentPath(validating: "/root/updated_backfill"),
            databaseURL: databaseURL
        )

        let hotMilliseconds: Int64 = 1_700_000_000_500
        let backfillMilliseconds = hotMilliseconds - 2_000
        let firstUpdated = try await store.touchThreadUpdatedAt(
            threadID: firstThreadID,
            updatedAt: date(milliseconds: hotMilliseconds)
        )
        let secondUpdated = try await store.touchThreadUpdatedAt(
            threadID: secondThreadID,
            updatedAt: date(milliseconds: hotMilliseconds)
        )
        let backfillUpdated = try await store.touchThreadUpdatedAt(
            threadID: backfillThreadID,
            updatedAt: date(milliseconds: backfillMilliseconds)
        )
        let missingUpdated = try await store.touchThreadUpdatedAt(
            threadID: missingThreadID,
            updatedAt: date(milliseconds: hotMilliseconds)
        )

        let firstTimestamps = try readRawSQLiteThreadUpdatedAt(id: firstThreadID, databaseURL: databaseURL)
        let secondTimestamps = try readRawSQLiteThreadUpdatedAt(id: secondThreadID, databaseURL: databaseURL)
        let backfillTimestamps = try readRawSQLiteThreadUpdatedAt(id: backfillThreadID, databaseURL: databaseURL)

        XCTAssertTrue(firstUpdated)
        XCTAssertTrue(secondUpdated)
        XCTAssertTrue(backfillUpdated)
        XCTAssertFalse(missingUpdated)
        XCTAssertEqual(firstTimestamps, ThreadUpdatedAt(seconds: 1_700_000_000, milliseconds: hotMilliseconds))
        XCTAssertEqual(secondTimestamps, ThreadUpdatedAt(seconds: 1_700_000_000, milliseconds: hotMilliseconds + 1))
        XCTAssertEqual(
            backfillTimestamps,
            ThreadUpdatedAt(seconds: 1_699_999_998, milliseconds: backfillMilliseconds)
        )
    }

    func testSQLiteStoreUpdatesThreadGitInfoWithRustDoubleOptionSemantics() async throws {
        let temp = try AgentGraphStoreTemporaryDirectory()
        let databaseURL = temp.url.appendingPathComponent("state.sqlite3")
        let store = try SQLiteAgentGraphStore(databaseURL: databaseURL)
        try createMinimalThreadsTable(databaseURL: databaseURL)
        let gitThreadID = try threadID(93)
        let missingThreadID = try threadID(94)
        try insertRawSQLiteThread(
            id: gitThreadID,
            agentPath: try AgentPath(validating: "/root/git"),
            gitInfo: ThreadGitInfo(sha: "old-sha", branch: "main", originURL: "git@example.com:repo.git"),
            databaseURL: databaseURL
        )

        let firstUpdated = try await store.updateThreadGitInfo(
            threadID: gitThreadID,
            sha: .preserve,
            branch: .set("feature/sidebar"),
            originURL: .clear
        )
        let firstGitInfo = try readRawSQLiteThreadGitInfo(id: gitThreadID, databaseURL: databaseURL)
        let secondUpdated = try await store.updateThreadGitInfo(
            threadID: gitThreadID,
            sha: .clear,
            branch: .preserve,
            originURL: .set("https://example.com/repo.git")
        )
        let secondGitInfo = try readRawSQLiteThreadGitInfo(id: gitThreadID, databaseURL: databaseURL)
        let missingUpdated = try await store.updateThreadGitInfo(
            threadID: missingThreadID,
            sha: .set("missing-sha"),
            branch: .set("missing-branch"),
            originURL: .set("missing-origin")
        )

        XCTAssertTrue(firstUpdated)
        XCTAssertEqual(
            firstGitInfo,
            ThreadGitInfo(sha: "old-sha", branch: "feature/sidebar", originURL: nil)
        )
        XCTAssertTrue(secondUpdated)
        XCTAssertEqual(
            secondGitInfo,
            ThreadGitInfo(sha: nil, branch: "feature/sidebar", originURL: "https://example.com/repo.git")
        )
        XCTAssertFalse(missingUpdated)
    }

    func testSQLiteStoreDeletesThreadAndReturnsRowsAffected() async throws {
        let temp = try AgentGraphStoreTemporaryDirectory()
        let databaseURL = temp.url.appendingPathComponent("state.sqlite3")
        let store = try SQLiteAgentGraphStore(databaseURL: databaseURL)
        try createMinimalThreadsTable(databaseURL: databaseURL)
        let deletedThreadID = try threadID(95)
        try insertRawSQLiteThread(
            id: deletedThreadID,
            agentPath: try AgentPath(validating: "/root/deleted"),
            rolloutPath: "/tmp/deleted-rollout.jsonl",
            databaseURL: databaseURL
        )

        let deletedRows = try await store.deleteThread(threadID: deletedThreadID)
        let deletedRolloutPath = try await store.findRolloutPath(threadID: deletedThreadID, archiveFilter: .all)
        let secondDeleteRows = try await store.deleteThread(threadID: deletedThreadID)

        XCTAssertEqual(deletedRows, 1)
        XCTAssertNil(deletedRolloutPath)
        XCTAssertEqual(secondDeleteRows, 0)
    }

    func testSQLiteStoreMarksThreadArchivedAndUnarchivedUsingRolloutModificationTime() async throws {
        let temp = try AgentGraphStoreTemporaryDirectory()
        let databaseURL = temp.url.appendingPathComponent("state.sqlite3")
        let archivedRolloutURL = temp.url.appendingPathComponent("archived-rollout.jsonl")
        let restoredRolloutURL = temp.url.appendingPathComponent("restored-rollout.jsonl")
        let store = try SQLiteAgentGraphStore(databaseURL: databaseURL)
        try createMinimalThreadsTable(databaseURL: databaseURL)
        let archivedThreadID = try threadID(96)
        let missingThreadID = try threadID(97)
        try insertRawSQLiteThread(
            id: archivedThreadID,
            agentPath: try AgentPath(validating: "/root/archive"),
            rolloutPath: "/tmp/original-rollout.jsonl",
            databaseURL: databaseURL
        )
        try Data("archived\n".utf8).write(to: archivedRolloutURL)
        try Data("restored\n".utf8).write(to: restoredRolloutURL)
        let archiveModifiedAt = date(milliseconds: 1_700_000_010_500)
        let restoredModifiedAt = date(milliseconds: 1_700_000_020_250)
        try FileManager.default.setAttributes([.modificationDate: archiveModifiedAt], ofItemAtPath: archivedRolloutURL.path)
        try FileManager.default.setAttributes([.modificationDate: restoredModifiedAt], ofItemAtPath: restoredRolloutURL.path)

        let archived = try await store.markThreadArchived(
            threadID: archivedThreadID,
            rolloutPath: archivedRolloutURL,
            archivedAt: date(milliseconds: 1_700_000_011_900)
        )
        let missingArchived = try await store.markThreadArchived(
            threadID: missingThreadID,
            rolloutPath: archivedRolloutURL,
            archivedAt: date(milliseconds: 1_700_000_011_900)
        )
        let archivedMetadata = try readRawSQLiteThreadArchiveMetadata(id: archivedThreadID, databaseURL: databaseURL)
        let archivedLookupPath = try await store.findRolloutPath(
            threadID: archivedThreadID,
            archiveFilter: .archivedOnly
        )

        XCTAssertTrue(archived)
        XCTAssertFalse(missingArchived)
        XCTAssertEqual(archivedMetadata, ThreadArchiveMetadata(
            rolloutPath: archivedRolloutURL.path,
            archived: true,
            archivedAt: 1_700_000_011,
            updatedAt: ThreadUpdatedAt(seconds: 1_700_000_010, milliseconds: 1_700_000_010_500)
        ))
        XCTAssertEqual(archivedLookupPath, archivedRolloutURL.path)

        let unarchived = try await store.markThreadUnarchived(threadID: archivedThreadID, rolloutPath: restoredRolloutURL)
        let missingUnarchived = try await store.markThreadUnarchived(threadID: missingThreadID, rolloutPath: restoredRolloutURL)
        let unarchivedMetadata = try readRawSQLiteThreadArchiveMetadata(id: archivedThreadID, databaseURL: databaseURL)
        let unarchivedLookupPath = try await store.findRolloutPath(
            threadID: archivedThreadID,
            archiveFilter: .unarchivedOnly
        )

        XCTAssertTrue(unarchived)
        XCTAssertFalse(missingUnarchived)
        XCTAssertEqual(unarchivedMetadata, ThreadArchiveMetadata(
            rolloutPath: restoredRolloutURL.path,
            archived: false,
            archivedAt: nil,
            updatedAt: ThreadUpdatedAt(seconds: 1_700_000_020, milliseconds: 1_700_000_020_250)
        ))
        XCTAssertEqual(unarchivedLookupPath, restoredRolloutURL.path)
    }

    func testSQLiteStoreArchiveLeavesUpdatedAtWhenRolloutModificationTimeIsUnavailable() async throws {
        let temp = try AgentGraphStoreTemporaryDirectory()
        let databaseURL = temp.url.appendingPathComponent("state.sqlite3")
        let missingRolloutURL = temp.url.appendingPathComponent("missing-rollout.jsonl")
        let store = try SQLiteAgentGraphStore(databaseURL: databaseURL)
        try createMinimalThreadsTable(databaseURL: databaseURL)
        let threadID = try threadID(98)
        try insertRawSQLiteThread(
            id: threadID,
            agentPath: try AgentPath(validating: "/root/archive_missing_mtime"),
            rolloutPath: "/tmp/original-rollout.jsonl",
            updatedAt: ThreadUpdatedAt(seconds: 123, milliseconds: 123_456),
            databaseURL: databaseURL
        )

        let archived = try await store.markThreadArchived(
            threadID: threadID,
            rolloutPath: missingRolloutURL,
            archivedAt: date(milliseconds: 1_700_000_030_999)
        )
        let archivedMetadata = try readRawSQLiteThreadArchiveMetadata(id: threadID, databaseURL: databaseURL)

        XCTAssertTrue(archived)
        XCTAssertEqual(archivedMetadata, ThreadArchiveMetadata(
            rolloutPath: missingRolloutURL.path,
            archived: true,
            archivedAt: 1_700_000_030,
            updatedAt: ThreadUpdatedAt(seconds: 123, milliseconds: 123_456)
        ))
    }

    private func threadID(_ suffix: Int) throws -> ThreadId {
        try ThreadId(string: String(format: "00000000-0000-0000-0000-%012d", suffix))
    }

    private func jsonString<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private func persistedSource(_ source: SessionSource) throws -> String {
        try jsonString(source)
    }

    private func date(milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
    }

    private func insertRawSQLiteThreadSpawnEdge(
        databaseURL: URL,
        parentThreadID: ThreadId,
        childThreadID: ThreadId,
        status: String
    ) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READWRITE, nil), SQLITE_OK)
        let openedDatabase = try XCTUnwrap(database)
        defer {
            sqlite3_close(openedDatabase)
        }

        var statement: OpaquePointer?
        let query =
            """
            INSERT INTO thread_spawn_edges (
                parent_thread_id,
                child_thread_id,
                status
            ) VALUES (?, ?, ?)
            """
        XCTAssertEqual(sqlite3_prepare_v2(openedDatabase, query, -1, &statement, nil), SQLITE_OK)
        let preparedStatement = try XCTUnwrap(statement)
        defer {
            sqlite3_finalize(preparedStatement)
        }

        XCTAssertEqual(sqlite3_bind_text(preparedStatement, 1, parentThreadID.description, -1, testSQLiteTransient), SQLITE_OK)
        XCTAssertEqual(sqlite3_bind_text(preparedStatement, 2, childThreadID.description, -1, testSQLiteTransient), SQLITE_OK)
        XCTAssertEqual(sqlite3_bind_text(preparedStatement, 3, status, -1, testSQLiteTransient), SQLITE_OK)
        XCTAssertEqual(sqlite3_step(preparedStatement), SQLITE_DONE)
    }

    private func createMinimalThreadsTable(databaseURL: URL) throws {
        try withRawSQLiteDatabase(databaseURL: databaseURL) { database in
            var statement: OpaquePointer?
            let query =
                """
                CREATE TABLE threads (
                    id TEXT NOT NULL PRIMARY KEY,
                    agent_path TEXT,
                    memory_mode TEXT,
                    rollout_path TEXT,
                    archived INTEGER NOT NULL DEFAULT 0,
                    archived_at INTEGER,
                    title TEXT,
                    updated_at INTEGER,
                    updated_at_ms INTEGER,
                    git_sha TEXT,
                    git_branch TEXT,
                    git_origin_url TEXT
                )
                """
            XCTAssertEqual(sqlite3_prepare_v2(database, query, -1, &statement, nil), SQLITE_OK)
            let preparedStatement = try XCTUnwrap(statement)
            defer {
                sqlite3_finalize(preparedStatement)
            }
            XCTAssertEqual(sqlite3_step(preparedStatement), SQLITE_DONE)
        }
    }

    private func insertRawSQLiteThread(
        id: ThreadId,
        agentPath: AgentPath,
        memoryMode: String? = nil,
        rolloutPath: String? = nil,
        archived: Bool = false,
        archivedAt: Int64? = nil,
        title: String? = nil,
        updatedAt: ThreadUpdatedAt = ThreadUpdatedAt(seconds: 0, milliseconds: 0),
        gitInfo: ThreadGitInfo = ThreadGitInfo(),
        databaseURL: URL
    ) throws {
        try withRawSQLiteDatabase(databaseURL: databaseURL) { database in
            var statement: OpaquePointer?
            let query =
                """
                INSERT INTO threads (
                    id,
                    agent_path,
                    memory_mode,
                    rollout_path,
                    archived,
                    archived_at,
                    title,
                    updated_at,
                    updated_at_ms,
                    git_sha,
                    git_branch,
                    git_origin_url
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """
            XCTAssertEqual(sqlite3_prepare_v2(database, query, -1, &statement, nil), SQLITE_OK)
            let preparedStatement = try XCTUnwrap(statement)
            defer {
                sqlite3_finalize(preparedStatement)
            }
            XCTAssertEqual(sqlite3_bind_text(preparedStatement, 1, id.description, -1, testSQLiteTransient), SQLITE_OK)
            XCTAssertEqual(sqlite3_bind_text(preparedStatement, 2, agentPath.description, -1, testSQLiteTransient), SQLITE_OK)
            if let memoryMode {
                XCTAssertEqual(sqlite3_bind_text(preparedStatement, 3, memoryMode, -1, testSQLiteTransient), SQLITE_OK)
            } else {
                XCTAssertEqual(sqlite3_bind_null(preparedStatement, 3), SQLITE_OK)
            }
            if let rolloutPath {
                XCTAssertEqual(sqlite3_bind_text(preparedStatement, 4, rolloutPath, -1, testSQLiteTransient), SQLITE_OK)
            } else {
                XCTAssertEqual(sqlite3_bind_null(preparedStatement, 4), SQLITE_OK)
            }
            XCTAssertEqual(sqlite3_bind_int(preparedStatement, 5, archived ? 1 : 0), SQLITE_OK)
            if let archivedAt {
                XCTAssertEqual(sqlite3_bind_int64(preparedStatement, 6, archivedAt), SQLITE_OK)
            } else {
                XCTAssertEqual(sqlite3_bind_null(preparedStatement, 6), SQLITE_OK)
            }
            if let title {
                XCTAssertEqual(sqlite3_bind_text(preparedStatement, 7, title, -1, testSQLiteTransient), SQLITE_OK)
            } else {
                XCTAssertEqual(sqlite3_bind_null(preparedStatement, 7), SQLITE_OK)
            }
            XCTAssertEqual(sqlite3_bind_int64(preparedStatement, 8, updatedAt.seconds), SQLITE_OK)
            XCTAssertEqual(sqlite3_bind_int64(preparedStatement, 9, updatedAt.milliseconds), SQLITE_OK)
            bindOptionalText(gitInfo.sha, to: preparedStatement, at: 10)
            bindOptionalText(gitInfo.branch, to: preparedStatement, at: 11)
            bindOptionalText(gitInfo.originURL, to: preparedStatement, at: 12)
            XCTAssertEqual(sqlite3_step(preparedStatement), SQLITE_DONE)
        }
    }

    private func readRawSQLiteThreadTitle(id: ThreadId, databaseURL: URL) throws -> String? {
        try withRawSQLiteDatabase(databaseURL: databaseURL) { database in
            var statement: OpaquePointer?
            let query = "SELECT title FROM threads WHERE id = ?"
            XCTAssertEqual(sqlite3_prepare_v2(database, query, -1, &statement, nil), SQLITE_OK)
            let preparedStatement = try XCTUnwrap(statement)
            defer {
                sqlite3_finalize(preparedStatement)
            }
            XCTAssertEqual(sqlite3_bind_text(preparedStatement, 1, id.description, -1, testSQLiteTransient), SQLITE_OK)
            let result = sqlite3_step(preparedStatement)
            if result == SQLITE_DONE {
                return nil
            }
            XCTAssertEqual(result, SQLITE_ROW)
            guard let rawTitle = sqlite3_column_text(preparedStatement, 0) else {
                return nil
            }
            return String(cString: rawTitle)
        }
    }

    private func readRawSQLiteThreadUpdatedAt(id: ThreadId, databaseURL: URL) throws -> ThreadUpdatedAt? {
        try withRawSQLiteDatabase(databaseURL: databaseURL) { database in
            var statement: OpaquePointer?
            let query = "SELECT updated_at, updated_at_ms FROM threads WHERE id = ?"
            XCTAssertEqual(sqlite3_prepare_v2(database, query, -1, &statement, nil), SQLITE_OK)
            let preparedStatement = try XCTUnwrap(statement)
            defer {
                sqlite3_finalize(preparedStatement)
            }
            XCTAssertEqual(sqlite3_bind_text(preparedStatement, 1, id.description, -1, testSQLiteTransient), SQLITE_OK)
            let result = sqlite3_step(preparedStatement)
            if result == SQLITE_DONE {
                return nil
            }
            XCTAssertEqual(result, SQLITE_ROW)
            return ThreadUpdatedAt(
                seconds: sqlite3_column_int64(preparedStatement, 0),
                milliseconds: sqlite3_column_int64(preparedStatement, 1)
            )
        }
    }

    private func readRawSQLiteThreadGitInfo(id: ThreadId, databaseURL: URL) throws -> ThreadGitInfo? {
        try withRawSQLiteDatabase(databaseURL: databaseURL) { database in
            var statement: OpaquePointer?
            let query = "SELECT git_sha, git_branch, git_origin_url FROM threads WHERE id = ?"
            XCTAssertEqual(sqlite3_prepare_v2(database, query, -1, &statement, nil), SQLITE_OK)
            let preparedStatement = try XCTUnwrap(statement)
            defer {
                sqlite3_finalize(preparedStatement)
            }
            XCTAssertEqual(sqlite3_bind_text(preparedStatement, 1, id.description, -1, testSQLiteTransient), SQLITE_OK)
            let result = sqlite3_step(preparedStatement)
            if result == SQLITE_DONE {
                return nil
            }
            XCTAssertEqual(result, SQLITE_ROW)
            return ThreadGitInfo(
                sha: optionalTextColumn(preparedStatement, index: 0),
                branch: optionalTextColumn(preparedStatement, index: 1),
                originURL: optionalTextColumn(preparedStatement, index: 2)
            )
        }
    }

    private func readRawSQLiteThreadArchiveMetadata(id: ThreadId, databaseURL: URL) throws -> ThreadArchiveMetadata? {
        try withRawSQLiteDatabase(databaseURL: databaseURL) { database in
            var statement: OpaquePointer?
            let query = "SELECT rollout_path, archived, archived_at, updated_at, updated_at_ms FROM threads WHERE id = ?"
            XCTAssertEqual(sqlite3_prepare_v2(database, query, -1, &statement, nil), SQLITE_OK)
            let preparedStatement = try XCTUnwrap(statement)
            defer {
                sqlite3_finalize(preparedStatement)
            }
            XCTAssertEqual(sqlite3_bind_text(preparedStatement, 1, id.description, -1, testSQLiteTransient), SQLITE_OK)
            let result = sqlite3_step(preparedStatement)
            if result == SQLITE_DONE {
                return nil
            }
            XCTAssertEqual(result, SQLITE_ROW)
            return ThreadArchiveMetadata(
                rolloutPath: optionalTextColumn(preparedStatement, index: 0),
                archived: sqlite3_column_int(preparedStatement, 1) != 0,
                archivedAt: sqlite3_column_type(preparedStatement, 2) == SQLITE_NULL
                    ? nil
                    : sqlite3_column_int64(preparedStatement, 2),
                updatedAt: ThreadUpdatedAt(
                    seconds: sqlite3_column_int64(preparedStatement, 3),
                    milliseconds: sqlite3_column_int64(preparedStatement, 4)
                )
            )
        }
    }

    private func bindOptionalText(_ value: String?, to statement: OpaquePointer, at index: Int32) {
        if let value {
            XCTAssertEqual(sqlite3_bind_text(statement, index, value, -1, testSQLiteTransient), SQLITE_OK)
        } else {
            XCTAssertEqual(sqlite3_bind_null(statement, index), SQLITE_OK)
        }
    }

    private func optionalTextColumn(_ statement: OpaquePointer, index: Int32) -> String? {
        guard let rawValue = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: rawValue)
    }

    private func withRawSQLiteDatabase<T>(
        databaseURL: URL,
        body: (OpaquePointer) throws -> T
    ) throws -> T {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READWRITE, nil), SQLITE_OK)
        let openedDatabase = try XCTUnwrap(database)
        defer {
            sqlite3_close(openedDatabase)
        }
        return try body(openedDatabase)
    }
}

private final class AgentGraphStoreTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-swift-agent-graph-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

private let testSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private struct ThreadUpdatedAt: Equatable {
    let seconds: Int64
    let milliseconds: Int64
}

private struct ThreadArchiveMetadata: Equatable {
    let rolloutPath: String?
    let archived: Bool
    let archivedAt: Int64?
    let updatedAt: ThreadUpdatedAt
}

private struct ThreadGitInfo: Equatable {
    var sha: String?
    var branch: String?
    var originURL: String?

    init(sha: String? = nil, branch: String? = nil, originURL: String? = nil) {
        self.sha = sha
        self.branch = branch
        self.originURL = originURL
    }
}
