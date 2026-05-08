import Foundation

/// Lifecycle status attached to a directional thread-spawn edge.
public enum ThreadSpawnEdgeStatus: String, Codable, Equatable, Sendable {
    /// The child thread is still live or resumable as an open spawned agent.
    case open

    /// The child thread has been closed from the parent/child graph's perspective.
    case closed
}

/// Error type shared by agent graph store implementations.
public enum AgentGraphStoreError: Error, Equatable, CustomStringConvertible, Sendable {
    /// The caller supplied invalid request data.
    case invalidRequest(message: String)

    /// Catch-all for implementation failures that do not fit a more specific category.
    case `internal`(message: String)

    public var description: String {
        switch self {
        case let .invalidRequest(message):
            return "invalid agent graph store request: \(message)"
        case let .internal(message):
            return "agent graph store internal error: \(message)"
        }
    }
}

/// Storage-neutral boundary for persisted thread-spawn parent/child topology.
///
/// Implementations return stable ordering for list methods so callers can merge persisted graph
/// state with live in-memory state without introducing nondeterministic output.
public protocol AgentGraphStore: Sendable {
    /// Insert or replace the directional parent/child edge for a spawned thread.
    ///
    /// `childThreadID` has at most one persisted parent. Re-inserting the same child updates both
    /// the parent and status to match the supplied values.
    func upsertThreadSpawnEdge(
        parentThreadID: ConversationId,
        childThreadID: ConversationId,
        status: ThreadSpawnEdgeStatus
    ) async throws

    /// Update the persisted lifecycle status of a spawned thread's incoming edge.
    ///
    /// Implementations treat missing children as a successful no-op.
    func setThreadSpawnEdgeStatus(
        childThreadID: ConversationId,
        status: ThreadSpawnEdgeStatus
    ) async throws

    /// List direct spawned children of a parent thread.
    ///
    /// When `statusFilter` is non-nil, only child edges with that exact status are returned. When
    /// it is nil, all direct child edges are returned regardless of status.
    func listThreadSpawnChildren(
        parentThreadID: ConversationId,
        statusFilter: ThreadSpawnEdgeStatus?
    ) async throws -> [ConversationId]

    /// List spawned descendants breadth-first by depth, then by thread id.
    ///
    /// `statusFilter` is applied to every traversed edge, not just to the returned descendants.
    /// For example, `.open` walks only open edges, so descendants under a closed edge are not
    /// included even if their own incoming edge is open. `nil` walks and returns every edge.
    func listThreadSpawnDescendants(
        rootThreadID: ConversationId,
        statusFilter: ThreadSpawnEdgeStatus?
    ) async throws -> [ConversationId]
}

public actor InMemoryAgentGraphStore: AgentGraphStore {
    private struct Edge: Equatable, Sendable {
        var parentThreadID: ConversationId
        var childThreadID: ConversationId
        var status: ThreadSpawnEdgeStatus
    }

    private var edgesByChild: [ConversationId: Edge]

    public init() {
        self.edgesByChild = [:]
    }

    public func upsertThreadSpawnEdge(
        parentThreadID: ConversationId,
        childThreadID: ConversationId,
        status: ThreadSpawnEdgeStatus
    ) async throws {
        edgesByChild[childThreadID] = Edge(
            parentThreadID: parentThreadID,
            childThreadID: childThreadID,
            status: status
        )
    }

    public func setThreadSpawnEdgeStatus(
        childThreadID: ConversationId,
        status: ThreadSpawnEdgeStatus
    ) async throws {
        guard var edge = edgesByChild[childThreadID] else {
            return
        }
        edge.status = status
        edgesByChild[childThreadID] = edge
    }

    public func listThreadSpawnChildren(
        parentThreadID: ConversationId,
        statusFilter: ThreadSpawnEdgeStatus?
    ) async throws -> [ConversationId] {
        directChildren(parentThreadID: parentThreadID, statusFilter: statusFilter)
    }

    public func listThreadSpawnDescendants(
        rootThreadID: ConversationId,
        statusFilter: ThreadSpawnEdgeStatus?
    ) async throws -> [ConversationId] {
        var descendants: [ConversationId] = []
        var visited = Set<ConversationId>()
        var currentLevel = directChildren(parentThreadID: rootThreadID, statusFilter: statusFilter)

        while !currentLevel.isEmpty {
            var nextLevel: [ConversationId] = []
            for threadID in currentLevel {
                guard visited.insert(threadID).inserted else {
                    continue
                }

                descendants.append(threadID)
                nextLevel.append(contentsOf: directChildren(parentThreadID: threadID, statusFilter: statusFilter))
            }

            currentLevel = nextLevel.sorted { $0.description < $1.description }
        }

        return descendants
    }

    private func directChildren(
        parentThreadID: ConversationId,
        statusFilter: ThreadSpawnEdgeStatus?
    ) -> [ConversationId] {
        edgesByChild.values
            .filter { edge in
                edge.parentThreadID == parentThreadID
                    && (statusFilter == nil || edge.status == statusFilter)
            }
            .map(\.childThreadID)
            .sorted { $0.description < $1.description }
    }
}
