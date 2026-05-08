import CodexCore
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

    private func threadID(_ suffix: Int) throws -> ThreadId {
        try ThreadId(string: String(format: "00000000-0000-0000-0000-%012d", suffix))
    }

    private func jsonString<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }
}
