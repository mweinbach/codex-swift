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

/// Stored stage-1 memory extraction output for a single thread.
public struct Stage1Output: Equatable, Sendable {
    public var threadID: ThreadId
    public var rolloutPath: String
    public var sourceUpdatedAt: Date
    public var rawMemory: String
    public var rolloutSummary: String
    public var rolloutSlug: String?
    public var cwd: String
    public var gitBranch: String?
    public var generatedAt: Date

    public init(
        threadID: ThreadId,
        rolloutPath: String,
        sourceUpdatedAt: Date,
        rawMemory: String,
        rolloutSummary: String,
        rolloutSlug: String? = nil,
        cwd: String,
        gitBranch: String? = nil,
        generatedAt: Date
    ) {
        self.threadID = threadID
        self.rolloutPath = rolloutPath
        self.sourceUpdatedAt = sourceUpdatedAt
        self.rawMemory = rawMemory
        self.rolloutSummary = rolloutSummary
        self.rolloutSlug = rolloutSlug
        self.cwd = cwd
        self.gitBranch = gitBranch
        self.generatedAt = generatedAt
    }
}

/// Result of trying to claim a stage-1 memory extraction job.
public enum Stage1JobClaimOutcome: Equatable, Sendable {
    /// The caller owns the job and should continue with extraction.
    case claimed(ownershipToken: String)

    /// Existing output or job success state is already newer than or equal to the source rollout.
    case skippedUpToDate

    /// Another worker currently owns a fresh lease for this job.
    case skippedRunning

    /// The job is in backoff and should not be retried yet.
    case skippedRetryBackoff

    /// The job has exhausted retries and should not be retried automatically.
    case skippedRetryExhausted
}

/// Claimed stage-1 memory extraction job with thread metadata.
public struct Stage1JobClaim: Equatable, Sendable {
    public var thread: ThreadMetadata
    public var ownershipToken: String

    public init(thread: ThreadMetadata, ownershipToken: String) {
        self.thread = thread
        self.ownershipToken = ownershipToken
    }
}

/// Selection and lease parameters for startup stage-1 memory extraction claims.
public struct Stage1StartupClaimParams: Equatable, Sendable {
    public var scanLimit: Int
    public var maxClaimed: Int
    public var maxAgeDays: Int64
    public var minRolloutIdleHours: Int64
    public var allowedSources: [String]
    public var leaseSeconds: Int64

    public init(
        scanLimit: Int,
        maxClaimed: Int,
        maxAgeDays: Int64,
        minRolloutIdleHours: Int64,
        allowedSources: [String],
        leaseSeconds: Int64
    ) {
        self.scanLimit = scanLimit
        self.maxClaimed = maxClaimed
        self.maxAgeDays = maxAgeDays
        self.minRolloutIdleHours = minRolloutIdleHours
        self.allowedSources = allowedSources
        self.leaseSeconds = leaseSeconds
    }
}

/// Result of trying to claim a phase-2 memory consolidation job.
public enum Phase2JobClaimOutcome: Equatable, Sendable {
    /// The caller owns the global lock and may inspect the memory workspace.
    case claimed(ownershipToken: String, inputWatermark: Int64)

    /// The global job is in retry backoff.
    case skippedRetryUnavailable

    /// The global job completed recently enough that consolidation is cooling down.
    case skippedCooldown

    /// Another worker currently owns a fresh global consolidation lease.
    case skippedRunning
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
        parentThreadID: ThreadId,
        childThreadID: ThreadId,
        status: ThreadSpawnEdgeStatus
    ) async throws

    /// Insert an open directional parent/child edge only when the child has no existing edge.
    ///
    /// This preserves Rust's metadata-ingest bootstrap behavior: a discovered thread-spawn source
    /// should materialize the graph edge, but must not overwrite a live edge that was already
    /// recorded with an explicit parent or lifecycle status.
    func insertThreadSpawnEdgeIfAbsent(
        parentThreadID: ThreadId,
        childThreadID: ThreadId
    ) async throws

    /// Decode a persisted session-source string and insert the implied open thread-spawn edge.
    ///
    /// Non-thread-spawn sources are accepted as successful no-ops.
    func insertThreadSpawnEdgeFromSourceIfAbsent(
        childThreadID: ThreadId,
        source: String
    ) async throws

    /// Update the persisted lifecycle status of a spawned thread's incoming edge.
    ///
    /// Implementations treat missing children as a successful no-op.
    func setThreadSpawnEdgeStatus(
        childThreadID: ThreadId,
        status: ThreadSpawnEdgeStatus
    ) async throws

    /// List direct spawned children of a parent thread.
    ///
    /// When `statusFilter` is non-nil, only child edges with that exact status are returned. When
    /// it is nil, all direct child edges are returned regardless of status.
    func listThreadSpawnChildren(
        parentThreadID: ThreadId,
        statusFilter: ThreadSpawnEdgeStatus?
    ) async throws -> [ThreadId]

    /// List spawned descendants breadth-first by depth, then by thread id.
    ///
    /// `statusFilter` is applied to every traversed edge, not just to the returned descendants.
    /// For example, `.open` walks only open edges, so descendants under a closed edge are not
    /// included even if their own incoming edge is open. `nil` walks and returns every edge.
    func listThreadSpawnDescendants(
        rootThreadID: ThreadId,
        statusFilter: ThreadSpawnEdgeStatus?
    ) async throws -> [ThreadId]
}

public actor InMemoryAgentGraphStore: AgentGraphStore {
    private struct Edge: Equatable, Sendable {
        var parentThreadID: ThreadId
        var childThreadID: ThreadId
        var status: ThreadSpawnEdgeStatus
    }

    private var edgesByChild: [ThreadId: Edge]

    public init() {
        self.edgesByChild = [:]
    }

    public func upsertThreadSpawnEdge(
        parentThreadID: ThreadId,
        childThreadID: ThreadId,
        status: ThreadSpawnEdgeStatus
    ) async throws {
        edgesByChild[childThreadID] = Edge(
            parentThreadID: parentThreadID,
            childThreadID: childThreadID,
            status: status
        )
    }

    public func insertThreadSpawnEdgeIfAbsent(
        parentThreadID: ThreadId,
        childThreadID: ThreadId
    ) async throws {
        guard edgesByChild[childThreadID] == nil else {
            return
        }
        edgesByChild[childThreadID] = Edge(
            parentThreadID: parentThreadID,
            childThreadID: childThreadID,
            status: .open
        )
    }

    public func insertThreadSpawnEdgeFromSourceIfAbsent(
        childThreadID: ThreadId,
        source: String
    ) async throws {
        guard let parentThreadID = SessionSource.threadSpawnParentThreadID(fromPersistedSource: source) else {
            return
        }
        try await insertThreadSpawnEdgeIfAbsent(
            parentThreadID: parentThreadID,
            childThreadID: childThreadID
        )
    }

    public func setThreadSpawnEdgeStatus(
        childThreadID: ThreadId,
        status: ThreadSpawnEdgeStatus
    ) async throws {
        guard var edge = edgesByChild[childThreadID] else {
            return
        }
        edge.status = status
        edgesByChild[childThreadID] = edge
    }

    public func listThreadSpawnChildren(
        parentThreadID: ThreadId,
        statusFilter: ThreadSpawnEdgeStatus?
    ) async throws -> [ThreadId] {
        directChildren(parentThreadID: parentThreadID, statusFilter: statusFilter)
    }

    public func listThreadSpawnDescendants(
        rootThreadID: ThreadId,
        statusFilter: ThreadSpawnEdgeStatus?
    ) async throws -> [ThreadId] {
        var descendants: [ThreadId] = []
        var visited = Set<ThreadId>()
        var currentLevel = directChildren(parentThreadID: rootThreadID, statusFilter: statusFilter)

        while !currentLevel.isEmpty {
            var nextLevel: [ThreadId] = []
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
        parentThreadID: ThreadId,
        statusFilter: ThreadSpawnEdgeStatus?
    ) -> [ThreadId] {
        edgesByChild.values
            .filter { edge in
                edge.parentThreadID == parentThreadID
                    && (statusFilter == nil || edge.status == statusFilter)
            }
            .map(\.childThreadID)
            .sorted { $0.description < $1.description }
    }
}
