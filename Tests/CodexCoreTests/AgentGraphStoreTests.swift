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

    private func threadID(_ suffix: Int) throws -> ThreadId {
        try ThreadId(string: String(format: "00000000-0000-0000-0000-%012d", suffix))
    }

    private func jsonString<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
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
                    agent_path TEXT
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
        databaseURL: URL
    ) throws {
        try withRawSQLiteDatabase(databaseURL: databaseURL) { database in
            var statement: OpaquePointer?
            let query = "INSERT INTO threads (id, agent_path) VALUES (?, ?)"
            XCTAssertEqual(sqlite3_prepare_v2(database, query, -1, &statement, nil), SQLITE_OK)
            let preparedStatement = try XCTUnwrap(statement)
            defer {
                sqlite3_finalize(preparedStatement)
            }
            XCTAssertEqual(sqlite3_bind_text(preparedStatement, 1, id.description, -1, testSQLiteTransient), SQLITE_OK)
            XCTAssertEqual(sqlite3_bind_text(preparedStatement, 2, agentPath.description, -1, testSQLiteTransient), SQLITE_OK)
            XCTAssertEqual(sqlite3_step(preparedStatement), SQLITE_DONE)
        }
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
