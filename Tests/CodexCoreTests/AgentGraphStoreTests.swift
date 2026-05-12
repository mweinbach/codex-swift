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

    func testSQLiteStoreRoundTripsRemoteControlEnrollmentByTargetAccountAndClient() async throws {
        let temp = try AgentGraphStoreTemporaryDirectory()
        let databaseURL = temp.url.appendingPathComponent("state.sqlite3")
        let store = try SQLiteAgentGraphStore(databaseURL: databaseURL)
        let target = "wss://example.com/backend-api/wham/remote/control/server"

        try await store.upsertRemoteControlEnrollment(RemoteControlEnrollmentRecord(
            websocketURL: target,
            accountID: "account-a",
            appServerClientName: "desktop-client",
            serverID: "srv_e_first",
            environmentID: "env_first",
            serverName: "first-server"
        ))
        try await store.upsertRemoteControlEnrollment(RemoteControlEnrollmentRecord(
            websocketURL: target,
            accountID: "account-b",
            appServerClientName: "desktop-client",
            serverID: "srv_e_second",
            environmentID: "env_second",
            serverName: "second-server"
        ))

        let first = try await store.getRemoteControlEnrollment(
            websocketURL: target,
            accountID: "account-a",
            appServerClientName: "desktop-client"
        )
        let missingAccount = try await store.getRemoteControlEnrollment(
            websocketURL: target,
            accountID: "account-missing",
            appServerClientName: "desktop-client"
        )
        let wrongClient = try await store.getRemoteControlEnrollment(
            websocketURL: target,
            accountID: "account-a",
            appServerClientName: "other-client"
        )

        XCTAssertEqual(first, RemoteControlEnrollmentRecord(
            websocketURL: target,
            accountID: "account-a",
            appServerClientName: "desktop-client",
            serverID: "srv_e_first",
            environmentID: "env_first",
            serverName: "first-server"
        ))
        XCTAssertNil(missingAccount)
        XCTAssertNil(wrongClient)
    }

    func testSQLiteStoreDeletesOnlyMatchingRemoteControlEnrollmentAndMapsNilClient() async throws {
        let temp = try AgentGraphStoreTemporaryDirectory()
        let databaseURL = temp.url.appendingPathComponent("state.sqlite3")
        let store = try SQLiteAgentGraphStore(databaseURL: databaseURL)
        let target = "wss://example.com/backend-api/wham/remote/control/server"

        try await store.upsertRemoteControlEnrollment(RemoteControlEnrollmentRecord(
            websocketURL: target,
            accountID: "account-a",
            appServerClientName: nil,
            serverID: "srv_e_first",
            environmentID: "env_first",
            serverName: "first-server"
        ))
        try await store.upsertRemoteControlEnrollment(RemoteControlEnrollmentRecord(
            websocketURL: target,
            accountID: "account-b",
            appServerClientName: nil,
            serverID: "srv_e_second",
            environmentID: "env_second",
            serverName: "second-server"
        ))

        let deleted = try await store.deleteRemoteControlEnrollment(
            websocketURL: target,
            accountID: "account-a",
            appServerClientName: nil
        )
        let deletedEnrollment = try await store.getRemoteControlEnrollment(
            websocketURL: target,
            accountID: "account-a",
            appServerClientName: nil
        )
        let retainedEnrollment = try await store.getRemoteControlEnrollment(
            websocketURL: target,
            accountID: "account-b",
            appServerClientName: nil
        )

        XCTAssertEqual(deleted, 1)
        XCTAssertNil(deletedEnrollment)
        XCTAssertEqual(retainedEnrollment, RemoteControlEnrollmentRecord(
            websocketURL: target,
            accountID: "account-b",
            appServerClientName: nil,
            serverID: "srv_e_second",
            environmentID: "env_second",
            serverName: "second-server"
        ))
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

    func testSQLiteStoreListsThreadIDsWithRustFiltersAndUpdatedAtAnchor() async throws {
        let temp = try AgentGraphStoreTemporaryDirectory()
        let databaseURL = temp.url.appendingPathComponent("state.sqlite3")
        let store = try SQLiteAgentGraphStore(databaseURL: databaseURL)
        try createMinimalThreadsTable(databaseURL: databaseURL)
        let newestThreadID = try threadID(99)
        let olderThreadID = try threadID(100)
        let emptyMessageThreadID = try threadID(101)
        let archivedThreadID = try threadID(102)
        let otherSourceThreadID = try threadID(103)
        let otherProviderThreadID = try threadID(104)
        try insertRawSQLiteThread(
            id: olderThreadID,
            agentPath: try AgentPath(validating: "/root/list_older"),
            source: "cli",
            modelProvider: "openai",
            firstUserMessage: "hello",
            createdAtMilliseconds: 1_700_000_000_100,
            updatedAt: ThreadUpdatedAt(seconds: 1_700_000_001, milliseconds: 1_700_000_001_000),
            databaseURL: databaseURL
        )
        try insertRawSQLiteThread(
            id: newestThreadID,
            agentPath: try AgentPath(validating: "/root/list_newest"),
            source: "cli",
            modelProvider: "openai",
            firstUserMessage: "hello",
            createdAtMilliseconds: 1_700_000_000_200,
            updatedAt: ThreadUpdatedAt(seconds: 1_700_000_002, milliseconds: 1_700_000_002_000),
            databaseURL: databaseURL
        )
        try insertRawSQLiteThread(
            id: emptyMessageThreadID,
            agentPath: try AgentPath(validating: "/root/list_empty"),
            source: "cli",
            modelProvider: "openai",
            firstUserMessage: "",
            updatedAt: ThreadUpdatedAt(seconds: 1_700_000_003, milliseconds: 1_700_000_003_000),
            databaseURL: databaseURL
        )
        try insertRawSQLiteThread(
            id: archivedThreadID,
            agentPath: try AgentPath(validating: "/root/list_archived"),
            source: "cli",
            modelProvider: "openai",
            firstUserMessage: "hello",
            archived: true,
            updatedAt: ThreadUpdatedAt(seconds: 1_700_000_004, milliseconds: 1_700_000_004_000),
            databaseURL: databaseURL
        )
        try insertRawSQLiteThread(
            id: otherSourceThreadID,
            agentPath: try AgentPath(validating: "/root/list_source"),
            source: "vscode",
            modelProvider: "openai",
            firstUserMessage: "hello",
            updatedAt: ThreadUpdatedAt(seconds: 1_700_000_005, milliseconds: 1_700_000_005_000),
            databaseURL: databaseURL
        )
        try insertRawSQLiteThread(
            id: otherProviderThreadID,
            agentPath: try AgentPath(validating: "/root/list_provider"),
            source: "cli",
            modelProvider: "mock",
            firstUserMessage: "hello",
            updatedAt: ThreadUpdatedAt(seconds: 1_700_000_006, milliseconds: 1_700_000_006_000),
            databaseURL: databaseURL
        )

        let filteredIDs = try await store.listThreadIDs(
            limit: 10,
            anchor: nil,
            sortKey: .updatedAt,
            allowedSources: ["cli"],
            modelProviders: ["openai"],
            archivedOnly: false
        )
        let anchoredIDs = try await store.listThreadIDs(
            limit: 10,
            anchor: ThreadListAnchor(timestamp: date(milliseconds: 1_700_000_002_000)),
            sortKey: .updatedAt,
            allowedSources: ["cli"],
            modelProviders: ["openai"],
            archivedOnly: false
        )
        let archivedIDs = try await store.listThreadIDs(
            limit: 10,
            anchor: nil,
            sortKey: .updatedAt,
            allowedSources: ["cli"],
            modelProviders: ["openai"],
            archivedOnly: true
        )
        let noProviderFilterIDs = try await store.listThreadIDs(
            limit: 2,
            anchor: nil,
            sortKey: .updatedAt,
            allowedSources: ["cli"],
            modelProviders: [],
            archivedOnly: false
        )

        XCTAssertEqual(filteredIDs, [newestThreadID, olderThreadID])
        XCTAssertEqual(anchoredIDs, [olderThreadID])
        XCTAssertEqual(archivedIDs, [archivedThreadID])
        XCTAssertEqual(noProviderFilterIDs, [otherProviderThreadID, newestThreadID])
    }

    func testSQLiteStoreListsThreadIDsCanSortByCreatedAt() async throws {
        let temp = try AgentGraphStoreTemporaryDirectory()
        let databaseURL = temp.url.appendingPathComponent("state.sqlite3")
        let store = try SQLiteAgentGraphStore(databaseURL: databaseURL)
        try createMinimalThreadsTable(databaseURL: databaseURL)
        let firstCreatedThreadID = try threadID(105)
        let secondCreatedThreadID = try threadID(106)
        try insertRawSQLiteThread(
            id: firstCreatedThreadID,
            agentPath: try AgentPath(validating: "/root/created_first"),
            source: "cli",
            modelProvider: "openai",
            firstUserMessage: "hello",
            createdAtMilliseconds: 1_700_000_010_000,
            updatedAt: ThreadUpdatedAt(seconds: 1_700_000_020, milliseconds: 1_700_000_020_000),
            databaseURL: databaseURL
        )
        try insertRawSQLiteThread(
            id: secondCreatedThreadID,
            agentPath: try AgentPath(validating: "/root/created_second"),
            source: "cli",
            modelProvider: "openai",
            firstUserMessage: "hello",
            createdAtMilliseconds: 1_700_000_030_000,
            updatedAt: ThreadUpdatedAt(seconds: 1_700_000_015, milliseconds: 1_700_000_015_000),
            databaseURL: databaseURL
        )

        let createdIDs = try await store.listThreadIDs(
            limit: 10,
            anchor: nil,
            sortKey: .createdAt,
            allowedSources: [],
            modelProviders: nil,
            archivedOnly: false
        )
        let anchoredCreatedIDs = try await store.listThreadIDs(
            limit: 10,
            anchor: ThreadListAnchor(timestamp: date(milliseconds: 1_700_000_030_000)),
            sortKey: .createdAt,
            allowedSources: [],
            modelProviders: nil,
            archivedOnly: false
        )

        XCTAssertEqual(createdIDs, [secondCreatedThreadID, firstCreatedThreadID])
        XCTAssertEqual(anchoredCreatedIDs, [firstCreatedThreadID])
    }

    func testSQLiteStoreListsThreadMetadataPagesWithRustFiltersAndNextAnchor() async throws {
        let temp = try AgentGraphStoreTemporaryDirectory()
        let databaseURL = temp.url.appendingPathComponent("state.sqlite3")
        let store = try SQLiteAgentGraphStore(databaseURL: databaseURL)
        try createMinimalThreadsTable(databaseURL: databaseURL)
        let newestThreadID = try threadID(107)
        let middleThreadID = try threadID(108)
        let oldestThreadID = try threadID(109)
        let otherCwdThreadID = try threadID(110)
        let emptyMessageThreadID = try threadID(111)
        try insertRawSQLiteThread(
            id: oldestThreadID,
            agentPath: try AgentPath(validating: "/root/page_oldest"),
            rolloutPath: "/tmp/page-oldest.jsonl",
            source: "cli",
            modelProvider: "openai",
            cwd: "/repo",
            firstUserMessage: "hello",
            createdAtMilliseconds: 1_700_000_060_000,
            title: "Gamma project",
            updatedAt: ThreadUpdatedAt(seconds: 1_700_000_061, milliseconds: 1_700_000_061_000),
            databaseURL: databaseURL
        )
        try insertRawSQLiteThread(
            id: middleThreadID,
            agentPath: try AgentPath(validating: "/root/page_middle"),
            rolloutPath: "/tmp/page-middle.jsonl",
            source: "cli",
            modelProvider: "openai",
            cwd: "/repo",
            firstUserMessage: "hello",
            createdAtMilliseconds: 1_700_000_062_000,
            title: "Beta project",
            updatedAt: ThreadUpdatedAt(seconds: 1_700_000_063, milliseconds: 1_700_000_063_000),
            databaseURL: databaseURL
        )
        try insertRawSQLiteThread(
            id: newestThreadID,
            agentPath: try AgentPath(validating: "/root/page_newest"),
            rolloutPath: "/tmp/page-newest.jsonl",
            source: "cli",
            modelProvider: "openai",
            cwd: "/repo",
            firstUserMessage: "hello",
            createdAtMilliseconds: 1_700_000_064_000,
            title: "Alpha project",
            updatedAt: ThreadUpdatedAt(seconds: 1_700_000_065, milliseconds: 1_700_000_065_000),
            databaseURL: databaseURL
        )
        try insertRawSQLiteThread(
            id: otherCwdThreadID,
            agentPath: try AgentPath(validating: "/root/page_other_cwd"),
            rolloutPath: "/tmp/page-other-cwd.jsonl",
            source: "cli",
            modelProvider: "openai",
            cwd: "/other",
            firstUserMessage: "hello",
            title: "Other project",
            updatedAt: ThreadUpdatedAt(seconds: 1_700_000_066, milliseconds: 1_700_000_066_000),
            databaseURL: databaseURL
        )
        try insertRawSQLiteThread(
            id: emptyMessageThreadID,
            agentPath: try AgentPath(validating: "/root/page_empty"),
            rolloutPath: "/tmp/page-empty.jsonl",
            source: "cli",
            modelProvider: "openai",
            cwd: "/repo",
            firstUserMessage: "",
            title: "Empty project",
            updatedAt: ThreadUpdatedAt(seconds: 1_700_000_067, milliseconds: 1_700_000_067_000),
            databaseURL: databaseURL
        )

        let firstPage = try await store.listThreads(
            pageSize: 2,
            filters: ThreadListFilterOptions(
                archivedOnly: false,
                allowedSources: ["cli"],
                modelProviders: ["openai"],
                cwdFilters: [URL(fileURLWithPath: "/repo", isDirectory: true)],
                sortKey: .updatedAt,
                sortDirection: .descending,
                searchTerm: "project"
            )
        )
        let secondPage = try await store.listThreads(
            pageSize: 2,
            filters: ThreadListFilterOptions(
                archivedOnly: false,
                allowedSources: ["cli"],
                modelProviders: ["openai"],
                cwdFilters: [URL(fileURLWithPath: "/repo", isDirectory: true)],
                anchor: firstPage.nextAnchor,
                sortKey: .updatedAt,
                sortDirection: .descending,
                searchTerm: "project"
            )
        )
        let emptyCwdPage = try await store.listThreads(
            pageSize: 2,
            filters: ThreadListFilterOptions(cwdFilters: [])
        )

        XCTAssertEqual(firstPage.items.map(\.id), [newestThreadID, middleThreadID])
        XCTAssertEqual(firstPage.nextAnchor, ThreadListAnchor(timestamp: date(milliseconds: 1_700_000_063_000)))
        XCTAssertEqual(firstPage.numScannedRows, 3)
        XCTAssertEqual(secondPage.items.map(\.id), [oldestThreadID])
        XCTAssertNil(secondPage.nextAnchor)
        XCTAssertEqual(secondPage.numScannedRows, 1)
        XCTAssertEqual(emptyCwdPage.items, [])
        XCTAssertNil(emptyCwdPage.nextAnchor)
        XCTAssertEqual(emptyCwdPage.numScannedRows, 0)
    }

    func testSQLiteStoreListsThreadMetadataSupportsAscendingAnchor() async throws {
        let temp = try AgentGraphStoreTemporaryDirectory()
        let databaseURL = temp.url.appendingPathComponent("state.sqlite3")
        let store = try SQLiteAgentGraphStore(databaseURL: databaseURL)
        try createMinimalThreadsTable(databaseURL: databaseURL)
        let firstThreadID = try threadID(112)
        let secondThreadID = try threadID(113)
        try insertRawSQLiteThread(
            id: firstThreadID,
            agentPath: try AgentPath(validating: "/root/ascending_first"),
            rolloutPath: "/tmp/ascending-first.jsonl",
            source: "cli",
            modelProvider: "openai",
            firstUserMessage: "hello",
            createdAtMilliseconds: 1_700_000_070_000,
            title: "First",
            updatedAt: ThreadUpdatedAt(seconds: 1_700_000_090, milliseconds: 1_700_000_090_000),
            databaseURL: databaseURL
        )
        try insertRawSQLiteThread(
            id: secondThreadID,
            agentPath: try AgentPath(validating: "/root/ascending_second"),
            rolloutPath: "/tmp/ascending-second.jsonl",
            source: "cli",
            modelProvider: "openai",
            firstUserMessage: "hello",
            createdAtMilliseconds: 1_700_000_080_000,
            title: "Second",
            updatedAt: ThreadUpdatedAt(seconds: 1_700_000_080, milliseconds: 1_700_000_080_000),
            databaseURL: databaseURL
        )

        let anchoredPage = try await store.listThreads(
            pageSize: 10,
            filters: ThreadListFilterOptions(
                anchor: ThreadListAnchor(timestamp: date(milliseconds: 1_700_000_070_000)),
                sortKey: .createdAt,
                sortDirection: .ascending
            )
        )

        XCTAssertEqual(anchoredPage.items.map(\.id), [secondThreadID])
        XCTAssertNil(anchoredPage.nextAnchor)
        XCTAssertEqual(anchoredPage.numScannedRows, 1)
    }

    func testSQLiteStoreUpsertsThreadMetadataWithRustConflictSemantics() async throws {
        let temp = try AgentGraphStoreTemporaryDirectory()
        let databaseURL = temp.url.appendingPathComponent("state.sqlite3")
        let store = try SQLiteAgentGraphStore(databaseURL: databaseURL)
        try createMinimalThreadsTable(databaseURL: databaseURL)
        let threadID = try threadID(120)
        let createdAt = date(milliseconds: 1_700_000_100_000)
        let initialMetadata = try threadMetadata(
            id: threadID,
            rolloutPath: "/tmp/upsert-initial.jsonl",
            createdAt: createdAt,
            updatedAt: date(milliseconds: 1_700_000_101_000),
            title: "Initial title",
            tokensUsed: 10,
            gitInfo: ThreadGitInfo(
                sha: "sqlite-sha",
                branch: "sqlite-branch",
                originURL: "git@example.com:openai/codex.git"
            )
        )

        try await store.upsertThread(initialMetadata)
        let initialMemoryMode = try await store.getThreadMemoryMode(threadID: threadID)
        let loadedInitial = try await store.getThread(threadID: threadID)
        let memoryModeChanged = try await store.setThreadMemoryMode(threadID: threadID, memoryMode: "disabled")
        var rolloutMetadata = try threadMetadata(
            id: threadID,
            rolloutPath: "/tmp/upsert-rollout.jsonl",
            createdAt: createdAt,
            updatedAt: date(milliseconds: 1_700_000_102_000),
            title: "Rollout title",
            tokensUsed: 99,
            gitInfo: ThreadGitInfo(
                sha: "rollout-sha",
                branch: "rollout-branch",
                originURL: "https://example.com/repo.git"
            )
        )
        rolloutMetadata = ThreadMetadata(
            id: rolloutMetadata.id,
            rolloutPath: rolloutMetadata.rolloutPath,
            createdAt: rolloutMetadata.createdAt,
            updatedAt: rolloutMetadata.updatedAt,
            source: rolloutMetadata.source,
            threadSource: .user,
            agentNickname: "helper",
            agentRole: "reviewer",
            agentPath: rolloutMetadata.agentPath,
            modelProvider: rolloutMetadata.modelProvider,
            model: "gpt-5.4",
            reasoningEffort: .high,
            cwd: rolloutMetadata.cwd,
            cliVersion: rolloutMetadata.cliVersion,
            title: rolloutMetadata.title,
            sandboxPolicy: rolloutMetadata.sandboxPolicy,
            approvalMode: rolloutMetadata.approvalMode,
            tokensUsed: rolloutMetadata.tokensUsed,
            firstUserMessage: rolloutMetadata.firstUserMessage,
            archivedAt: rolloutMetadata.archivedAt,
            gitSHA: rolloutMetadata.gitSHA,
            gitBranch: rolloutMetadata.gitBranch,
            gitOriginURL: rolloutMetadata.gitOriginURL
        )
        try await store.upsertThread(rolloutMetadata)

        let loadedPersisted = try await store.getThread(threadID: threadID)
        let persisted = try XCTUnwrap(loadedPersisted)
        let updatedMemoryMode = try await store.getThreadMemoryMode(threadID: threadID)
        XCTAssertEqual(initialMemoryMode, "enabled")
        XCTAssertNotNil(loadedInitial)
        XCTAssertTrue(memoryModeChanged)
        XCTAssertEqual(updatedMemoryMode, "disabled")
        XCTAssertEqual(persisted.rolloutPath, "/tmp/upsert-rollout.jsonl")
        XCTAssertEqual(persisted.title, "Rollout title")
        XCTAssertEqual(persisted.tokensUsed, 99)
        XCTAssertEqual(persisted.threadSource, .user)
        XCTAssertEqual(persisted.agentNickname, "helper")
        XCTAssertEqual(persisted.agentRole, "reviewer")
        XCTAssertEqual(persisted.model, "gpt-5.4")
        XCTAssertEqual(persisted.reasoningEffort, .high)
        XCTAssertEqual(persisted.gitSHA, "sqlite-sha")
        XCTAssertEqual(persisted.gitBranch, "sqlite-branch")
        XCTAssertEqual(persisted.gitOriginURL, "git@example.com:openai/codex.git")
    }

    func testSQLiteStoreInsertThreadIfAbsentPreservesExistingMetadataAndAddsSpawnEdge() async throws {
        let temp = try AgentGraphStoreTemporaryDirectory()
        let databaseURL = temp.url.appendingPathComponent("state.sqlite3")
        let store = try SQLiteAgentGraphStore(databaseURL: databaseURL)
        try createMinimalThreadsTable(databaseURL: databaseURL)
        let parentThreadID = try threadID(121)
        let existingThreadID = try threadID(122)
        let newThreadID = try threadID(123)
        let spawnSource = try persistedSource(
            .subagent(.threadSpawn(parentThreadID: parentThreadID, depth: 1))
        )
        let existingMetadata = try threadMetadata(
            id: existingThreadID,
            rolloutPath: "/tmp/existing.jsonl",
            updatedAt: date(milliseconds: 1_700_000_111_000),
            source: "cli",
            title: "Existing",
            tokensUsed: 123,
            firstUserMessage: "newer preview"
        )
        let fallbackMetadata = try threadMetadata(
            id: existingThreadID,
            rolloutPath: "/tmp/fallback.jsonl",
            updatedAt: date(milliseconds: 1_700_000_001_000),
            source: spawnSource,
            title: "Fallback",
            tokensUsed: 0,
            firstUserMessage: nil
        )
        let newMetadata = try threadMetadata(
            id: newThreadID,
            rolloutPath: "/tmp/new.jsonl",
            updatedAt: date(milliseconds: 1_700_000_112_000),
            source: spawnSource,
            title: "New",
            tokensUsed: 7
        )

        try await store.upsertThread(existingMetadata)
        let existingInserted = try await store.insertThreadIfAbsent(fallbackMetadata)
        let newInserted = try await store.insertThreadIfAbsent(newMetadata)

        let loadedExisting = try await store.getThread(threadID: existingThreadID)
        let loadedNew = try await store.getThread(threadID: newThreadID)
        let persistedExisting = try XCTUnwrap(loadedExisting)
        let persistedNew = try XCTUnwrap(loadedNew)
        let newMemoryMode = try await store.getThreadMemoryMode(threadID: newThreadID)
        let inferredChildren = try await store.listThreadSpawnChildren(
            parentThreadID: parentThreadID,
            statusFilter: .open
        )
        XCTAssertFalse(existingInserted)
        XCTAssertTrue(newInserted)
        XCTAssertEqual(persistedExisting.rolloutPath, "/tmp/existing.jsonl")
        XCTAssertEqual(persistedExisting.title, "Existing")
        XCTAssertEqual(persistedExisting.tokensUsed, 123)
        XCTAssertEqual(persistedExisting.firstUserMessage, "newer preview")
        XCTAssertEqual(persistedNew.rolloutPath, "/tmp/new.jsonl")
        XCTAssertEqual(persistedNew.firstUserMessage, "hello")
        XCTAssertEqual(newMemoryMode, "enabled")
        XCTAssertEqual(inferredChildren, [existingThreadID, newThreadID])
    }

    func testSQLiteStoreApplyRolloutItemsRestoresMemoryModeAndPreservesExistingGitInfo() async throws {
        let temp = try AgentGraphStoreTemporaryDirectory()
        let databaseURL = temp.url.appendingPathComponent("state.sqlite3")
        let store = try SQLiteAgentGraphStore(databaseURL: databaseURL, defaultProvider: "test-provider")
        try createMinimalThreadsTable(databaseURL: databaseURL)
        let threadID = try threadID(124)
        let createdAt = date(milliseconds: 1_700_000_120_000)
        let existingMetadata = try threadMetadata(
            id: threadID,
            rolloutPath: "/tmp/apply-existing.jsonl",
            createdAt: createdAt,
            updatedAt: date(milliseconds: 1_700_000_121_000),
            title: "Existing",
            gitInfo: ThreadGitInfo(branch: "sqlite-branch")
        )
        let dynamicTools = [
            DynamicToolSpec(
                namespace: "search",
                name: "lookup",
                description: "Look things up",
                inputSchema: .object(["type": .string("object")]),
                deferLoading: true
            ),
        ]
        let metaLine = SessionMetaLine(
            meta: SessionMeta(
                id: ConversationId(uuid: threadID.uuid),
                timestamp: ISO8601DateFormatter().string(from: createdAt),
                cwd: "/repo/from-rollout",
                originator: "",
                cliVersion: "1.2.3",
                source: .cli,
                threadSource: .user,
                agentNickname: "agent",
                agentRole: "reviewer",
                agentPath: "/root/apply",
                modelProvider: "rollout-provider",
                dynamicTools: dynamicTools,
                memoryMode: "polluted"
            ),
            git: GitInfo(
                commitHash: "rollout-sha",
                branch: "rollout-branch",
                repositoryURL: "git@example.com:openai/codex.git"
            )
        )
        let builder = ThreadMetadataBuilder(
            id: threadID,
            rolloutPath: URL(fileURLWithPath: "/tmp/apply-rollout.jsonl"),
            createdAt: createdAt,
            source: .cli
        )

        try await store.upsertThread(existingMetadata)
        try await store.applyRolloutItems(
            builder: builder,
            items: [.sessionMeta(metaLine)]
        )

        let loadedPersisted = try await store.getThread(threadID: threadID)
        let persisted = try XCTUnwrap(loadedPersisted)
        let memoryMode = try await store.getThreadMemoryMode(threadID: threadID)
        let storedTools = try await store.getDynamicTools(threadID: threadID)
        XCTAssertEqual(memoryMode, "polluted")
        XCTAssertEqual(storedTools, dynamicTools)
        XCTAssertEqual(persisted.rolloutPath, "/tmp/apply-rollout.jsonl")
        XCTAssertEqual(persisted.source, "cli")
        XCTAssertEqual(persisted.threadSource, .user)
        XCTAssertEqual(persisted.agentNickname, "agent")
        XCTAssertEqual(persisted.agentRole, "reviewer")
        XCTAssertEqual(persisted.agentPath, "/root/apply")
        XCTAssertEqual(persisted.modelProvider, "rollout-provider")
        XCTAssertEqual(persisted.cwd, "/repo/from-rollout")
        XCTAssertEqual(persisted.cliVersion, "1.2.3")
        XCTAssertEqual(persisted.gitSHA, "rollout-sha")
        XCTAssertEqual(persisted.gitBranch, "sqlite-branch")
        XCTAssertEqual(persisted.gitOriginURL, "git@example.com:openai/codex.git")
    }

    func testSQLiteStoreApplyRolloutItemsCreatesThreadWithOverrideUpdatedAtAndEventMetadata() async throws {
        let temp = try AgentGraphStoreTemporaryDirectory()
        let databaseURL = temp.url.appendingPathComponent("state.sqlite3")
        let store = try SQLiteAgentGraphStore(databaseURL: databaseURL, defaultProvider: "test-provider")
        try createMinimalThreadsTable(databaseURL: databaseURL)
        let threadID = try threadID(125)
        let createdAt = date(milliseconds: 1_700_000_130_000)
        let overrideUpdatedAt = date(milliseconds: 1_700_001_234_000)
        let builder = ThreadMetadataBuilder(
            id: threadID,
            rolloutPath: URL(fileURLWithPath: "/tmp/apply-new.jsonl"),
            createdAt: createdAt,
            source: .cli
        )
        let tokenCount = EventMessage.tokenCount(TokenCountEvent(
            info: TokenUsageInfo(
                totalTokenUsage: TokenUsage(totalTokens: 321),
                lastTokenUsage: TokenUsage()
            ),
            rateLimits: nil
        ))
        let userMessage = EventMessage.userMessage(UserMessageEvent(
            message: "prefix\n## My request for Codex: actual user request",
            images: nil
        ))

        try await store.applyRolloutItems(
            builder: builder,
            items: [
                .eventMsg(tokenCount),
                .eventMsg(userMessage),
            ],
            newThreadMemoryMode: "disabled",
            updatedAtOverride: overrideUpdatedAt
        )

        let loadedPersisted = try await store.getThread(threadID: threadID)
        let persisted = try XCTUnwrap(loadedPersisted)
        let memoryMode = try await store.getThreadMemoryMode(threadID: threadID)
        XCTAssertEqual(memoryMode, "disabled")
        XCTAssertEqual(persisted.rolloutPath, "/tmp/apply-new.jsonl")
        XCTAssertEqual(persisted.createdAt, createdAt)
        XCTAssertEqual(persisted.updatedAt, overrideUpdatedAt)
        XCTAssertEqual(persisted.modelProvider, "test-provider")
        XCTAssertEqual(persisted.tokensUsed, 321)
        XCTAssertEqual(persisted.firstUserMessage, "actual user request")
        XCTAssertEqual(persisted.title, "actual user request")
    }

    func testSQLiteStoreFindsNewestThreadByExactTitleWithRustFilters() async throws {
        let temp = try AgentGraphStoreTemporaryDirectory()
        let databaseURL = temp.url.appendingPathComponent("state.sqlite3")
        let store = try SQLiteAgentGraphStore(databaseURL: databaseURL)
        try createMinimalThreadsTable(databaseURL: databaseURL)
        let olderThreadID = try threadID(114)
        let newestThreadID = try threadID(115)
        let archivedThreadID = try threadID(116)
        let emptyMessageThreadID = try threadID(117)
        let otherCwdThreadID = try threadID(118)
        try insertRawSQLiteThread(
            id: olderThreadID,
            agentPath: try AgentPath(validating: "/root/title_older"),
            rolloutPath: "/tmp/older.jsonl",
            source: "cli",
            threadSource: "user",
            agentNickname: "steady",
            agentRole: "reviewer",
            modelProvider: "openai",
            model: "gpt-5.4",
            reasoningEffort: "high",
            cwd: "/repo",
            cliVersion: "0.1.0",
            firstUserMessage: "hello",
            sandboxPolicy: "workspace-write",
            approvalMode: "on-request",
            tokensUsed: 17,
            createdAtMilliseconds: 1_700_000_040_000,
            title: "Ship it",
            updatedAt: ThreadUpdatedAt(seconds: 1_700_000_041, milliseconds: 1_700_000_041_000),
            gitInfo: ThreadGitInfo(sha: "old-sha", branch: "main", originURL: "https://example.com/old.git"),
            databaseURL: databaseURL
        )
        try insertRawSQLiteThread(
            id: newestThreadID,
            agentPath: try AgentPath(validating: "/root/title_newest"),
            rolloutPath: "/tmp/newest.jsonl",
            source: "cli",
            threadSource: "subagent",
            agentNickname: "quick",
            agentRole: "worker",
            modelProvider: "openai",
            model: "gpt-5.5",
            reasoningEffort: "future",
            cwd: "/repo",
            cliVersion: "0.2.0",
            firstUserMessage: "hello again",
            sandboxPolicy: "danger-full-access",
            approvalMode: "never",
            tokensUsed: 29,
            createdAtMilliseconds: 1_700_000_042_000,
            archivedAt: nil,
            title: "Ship it",
            updatedAt: ThreadUpdatedAt(seconds: 1_700_000_043, milliseconds: 1_700_000_043_000),
            gitInfo: ThreadGitInfo(sha: "new-sha", branch: "feature", originURL: "https://example.com/new.git"),
            databaseURL: databaseURL
        )
        try insertRawSQLiteThread(
            id: archivedThreadID,
            agentPath: try AgentPath(validating: "/root/title_archived"),
            rolloutPath: "/tmp/archived-title.jsonl",
            source: "cli",
            modelProvider: "openai",
            cwd: "/repo",
            firstUserMessage: "hello",
            archived: true,
            archivedAt: 1_700_000_044,
            title: "Ship it",
            updatedAt: ThreadUpdatedAt(seconds: 1_700_000_044, milliseconds: 1_700_000_044_000),
            databaseURL: databaseURL
        )
        try insertRawSQLiteThread(
            id: emptyMessageThreadID,
            agentPath: try AgentPath(validating: "/root/title_empty"),
            source: "cli",
            modelProvider: "openai",
            cwd: "/repo",
            firstUserMessage: "",
            title: "Ship it",
            updatedAt: ThreadUpdatedAt(seconds: 1_700_000_045, milliseconds: 1_700_000_045_000),
            databaseURL: databaseURL
        )
        try insertRawSQLiteThread(
            id: otherCwdThreadID,
            agentPath: try AgentPath(validating: "/root/title_other_cwd"),
            source: "cli",
            modelProvider: "openai",
            cwd: "/other",
            firstUserMessage: "hello",
            title: "Ship it",
            updatedAt: ThreadUpdatedAt(seconds: 1_700_000_046, milliseconds: 1_700_000_046_000),
            databaseURL: databaseURL
        )

        let metadata = try await store.findThreadByExactTitle(
            title: "Ship it",
            allowedSources: ["cli"],
            modelProviders: ["openai"],
            archivedOnly: false,
            cwd: URL(fileURLWithPath: "/repo", isDirectory: true)
        )
        let archivedMetadata = try await store.findThreadByExactTitle(
            title: "Ship it",
            allowedSources: ["cli"],
            modelProviders: ["openai"],
            archivedOnly: true,
            cwd: URL(fileURLWithPath: "/repo", isDirectory: true)
        )
        let missingMetadata = try await store.findThreadByExactTitle(
            title: "ship it",
            allowedSources: ["cli"],
            modelProviders: ["openai"],
            archivedOnly: false,
            cwd: URL(fileURLWithPath: "/repo", isDirectory: true)
        )

        XCTAssertEqual(metadata?.id, newestThreadID)
        XCTAssertEqual(metadata?.rolloutPath, "/tmp/newest.jsonl")
        XCTAssertEqual(metadata?.threadSource, .subagent)
        XCTAssertEqual(metadata?.agentNickname, "quick")
        XCTAssertEqual(metadata?.agentRole, "worker")
        XCTAssertEqual(metadata?.agentPath, "/root/title_newest")
        XCTAssertEqual(metadata?.model, "gpt-5.5")
        XCTAssertNil(metadata?.reasoningEffort)
        XCTAssertEqual(metadata?.cwd, "/repo")
        XCTAssertEqual(metadata?.cliVersion, "0.2.0")
        XCTAssertEqual(metadata?.sandboxPolicy, "danger-full-access")
        XCTAssertEqual(metadata?.approvalMode, "never")
        XCTAssertEqual(metadata?.tokensUsed, 29)
        XCTAssertEqual(metadata?.firstUserMessage, "hello again")
        XCTAssertEqual(metadata?.gitSHA, "new-sha")
        XCTAssertEqual(metadata?.gitBranch, "feature")
        XCTAssertEqual(metadata?.gitOriginURL, "https://example.com/new.git")
        XCTAssertEqual(archivedMetadata?.id, archivedThreadID)
        XCTAssertNil(missingMetadata)
    }

    func testSQLiteStoreFindThreadByExactTitleRejectsUnknownThreadSourceLikeRust() async throws {
        let temp = try AgentGraphStoreTemporaryDirectory()
        let databaseURL = temp.url.appendingPathComponent("state.sqlite3")
        let store = try SQLiteAgentGraphStore(databaseURL: databaseURL)
        try createMinimalThreadsTable(databaseURL: databaseURL)
        let threadID = try threadID(119)
        try insertRawSQLiteThread(
            id: threadID,
            agentPath: try AgentPath(validating: "/root/title_unknown_source"),
            threadSource: "future_source",
            firstUserMessage: "hello",
            title: "Future",
            updatedAt: ThreadUpdatedAt(seconds: 1_700_000_050, milliseconds: 1_700_000_050_000),
            databaseURL: databaseURL
        )

        do {
            _ = try await store.findThreadByExactTitle(
                title: "Future",
                allowedSources: ["cli"],
                modelProviders: nil,
                archivedOnly: false,
                cwd: nil
            )
            XCTFail("unknown thread source should fail")
        } catch let error as AgentGraphStoreError {
            XCTAssertEqual(error, .internal(message: "unknown thread source: future_source"))
        }
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

    private func threadMetadata(
        id: ThreadId,
        rolloutPath: String,
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date,
        source: String = "cli",
        title: String,
        tokensUsed: Int64 = 0,
        firstUserMessage: String? = "hello",
        gitInfo: ThreadGitInfo = ThreadGitInfo()
    ) throws -> ThreadMetadata {
        ThreadMetadata(
            id: id,
            rolloutPath: rolloutPath,
            createdAt: createdAt,
            updatedAt: updatedAt,
            source: source,
            agentPath: try AgentPath(validating: "/root/thread_\(id.description.suffix(12))").description,
            modelProvider: "openai",
            cwd: "/repo",
            cliVersion: "0.0.0-test",
            title: title,
            sandboxPolicy: "workspace-write",
            approvalMode: "on-request",
            tokensUsed: tokensUsed,
            firstUserMessage: firstUserMessage,
            gitSHA: gitInfo.sha,
            gitBranch: gitInfo.branch,
            gitOriginURL: gitInfo.originURL
        )
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
                CREATE TABLE IF NOT EXISTS threads (
                    id TEXT NOT NULL PRIMARY KEY,
                    agent_path TEXT,
                    memory_mode TEXT,
                    rollout_path TEXT,
                    created_at INTEGER,
                    created_at_ms INTEGER,
                    archived INTEGER NOT NULL DEFAULT 0,
                    archived_at INTEGER,
                    source TEXT NOT NULL DEFAULT 'cli',
                    thread_source TEXT,
                    agent_nickname TEXT,
                    agent_role TEXT,
                    model_provider TEXT NOT NULL DEFAULT 'openai',
                    model TEXT,
                    reasoning_effort TEXT,
                    cwd TEXT NOT NULL DEFAULT '',
                    cli_version TEXT NOT NULL DEFAULT '',
                    first_user_message TEXT NOT NULL DEFAULT '',
                    sandbox_policy TEXT NOT NULL DEFAULT '',
                    approval_mode TEXT NOT NULL DEFAULT '',
                    tokens_used INTEGER NOT NULL DEFAULT 0,
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
        source: String = "cli",
        threadSource: String? = nil,
        agentNickname: String? = nil,
        agentRole: String? = nil,
        modelProvider: String = "openai",
        model: String? = nil,
        reasoningEffort: String? = nil,
        cwd: String = "",
        cliVersion: String = "",
        firstUserMessage: String = "hello",
        sandboxPolicy: String = "",
        approvalMode: String = "",
        tokensUsed: Int64 = 0,
        createdAtMilliseconds: Int64 = 0,
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
                    created_at,
                    created_at_ms,
                    archived,
                    archived_at,
                    source,
                    thread_source,
                    agent_nickname,
                    agent_role,
                    model_provider,
                    model,
                    reasoning_effort,
                    cwd,
                    cli_version,
                    first_user_message,
                    sandbox_policy,
                    approval_mode,
                    tokens_used,
                    title,
                    updated_at,
                    updated_at_ms,
                    git_sha,
                    git_branch,
                    git_origin_url
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
            XCTAssertEqual(sqlite3_bind_int64(preparedStatement, 5, createdAtMilliseconds / 1_000), SQLITE_OK)
            XCTAssertEqual(sqlite3_bind_int64(preparedStatement, 6, createdAtMilliseconds), SQLITE_OK)
            XCTAssertEqual(sqlite3_bind_int(preparedStatement, 7, archived ? 1 : 0), SQLITE_OK)
            if let archivedAt {
                XCTAssertEqual(sqlite3_bind_int64(preparedStatement, 8, archivedAt), SQLITE_OK)
            } else {
                XCTAssertEqual(sqlite3_bind_null(preparedStatement, 8), SQLITE_OK)
            }
            XCTAssertEqual(sqlite3_bind_text(preparedStatement, 9, source, -1, testSQLiteTransient), SQLITE_OK)
            bindOptionalText(threadSource, to: preparedStatement, at: 10)
            bindOptionalText(agentNickname, to: preparedStatement, at: 11)
            bindOptionalText(agentRole, to: preparedStatement, at: 12)
            XCTAssertEqual(sqlite3_bind_text(preparedStatement, 13, modelProvider, -1, testSQLiteTransient), SQLITE_OK)
            bindOptionalText(model, to: preparedStatement, at: 14)
            bindOptionalText(reasoningEffort, to: preparedStatement, at: 15)
            XCTAssertEqual(sqlite3_bind_text(preparedStatement, 16, cwd, -1, testSQLiteTransient), SQLITE_OK)
            XCTAssertEqual(sqlite3_bind_text(preparedStatement, 17, cliVersion, -1, testSQLiteTransient), SQLITE_OK)
            XCTAssertEqual(sqlite3_bind_text(preparedStatement, 18, firstUserMessage, -1, testSQLiteTransient), SQLITE_OK)
            XCTAssertEqual(sqlite3_bind_text(preparedStatement, 19, sandboxPolicy, -1, testSQLiteTransient), SQLITE_OK)
            XCTAssertEqual(sqlite3_bind_text(preparedStatement, 20, approvalMode, -1, testSQLiteTransient), SQLITE_OK)
            XCTAssertEqual(sqlite3_bind_int64(preparedStatement, 21, tokensUsed), SQLITE_OK)
            if let title {
                XCTAssertEqual(sqlite3_bind_text(preparedStatement, 22, title, -1, testSQLiteTransient), SQLITE_OK)
            } else {
                XCTAssertEqual(sqlite3_bind_null(preparedStatement, 22), SQLITE_OK)
            }
            XCTAssertEqual(sqlite3_bind_int64(preparedStatement, 23, updatedAt.seconds), SQLITE_OK)
            XCTAssertEqual(sqlite3_bind_int64(preparedStatement, 24, updatedAt.milliseconds), SQLITE_OK)
            bindOptionalText(gitInfo.sha, to: preparedStatement, at: 25)
            bindOptionalText(gitInfo.branch, to: preparedStatement, at: 26)
            bindOptionalText(gitInfo.originURL, to: preparedStatement, at: 27)
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
