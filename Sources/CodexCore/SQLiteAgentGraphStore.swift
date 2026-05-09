import Foundation
import SQLite3

/// SQLite-backed implementation of `AgentGraphStore`.
///
/// This mirrors Rust's `LocalAgentGraphStore` boundary: the store persists only directional
/// thread-spawn edges and preserves Rust's ordering, upsert, and status-filter semantics.
public actor SQLiteAgentGraphStore: AgentGraphStore {
    private let handle: SQLiteDatabaseHandle

    public init(databaseURL: URL) throws {
        var openedDatabase: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(databaseURL.path, &openedDatabase, flags, nil)
        guard result == SQLITE_OK, let openedDatabase else {
            let message = openedDatabase.map(Self.errorMessage(database:)) ?? "unable to open sqlite database"
            if let openedDatabase {
                sqlite3_close(openedDatabase)
            }
            throw AgentGraphStoreError.internal(message: message)
        }

        do {
            try Self.execute(
                """
                CREATE TABLE IF NOT EXISTS thread_spawn_edges (
                    parent_thread_id TEXT NOT NULL,
                    child_thread_id TEXT NOT NULL PRIMARY KEY,
                    status TEXT NOT NULL
                )
                """,
                database: openedDatabase
            )
            try Self.execute(
                """
                CREATE INDEX IF NOT EXISTS idx_thread_spawn_edges_parent_status
                    ON thread_spawn_edges(parent_thread_id, status)
                """,
                database: openedDatabase
            )
        } catch {
            sqlite3_close(openedDatabase)
            throw error
        }

        handle = SQLiteDatabaseHandle(database: openedDatabase)
    }

    public func upsertThreadSpawnEdge(
        parentThreadID: ThreadId,
        childThreadID: ThreadId,
        status: ThreadSpawnEdgeStatus
    ) async throws {
        try execute(
            """
            INSERT INTO thread_spawn_edges (
                parent_thread_id,
                child_thread_id,
                status
            ) VALUES (?, ?, ?)
            ON CONFLICT(child_thread_id) DO UPDATE SET
                parent_thread_id = excluded.parent_thread_id,
                status = excluded.status
            """,
            parentThreadID.description,
            childThreadID.description,
            status.rawValue
        )
    }

    public func setThreadSpawnEdgeStatus(
        childThreadID: ThreadId,
        status: ThreadSpawnEdgeStatus
    ) async throws {
        try execute(
            "UPDATE thread_spawn_edges SET status = ? WHERE child_thread_id = ?",
            status.rawValue,
            childThreadID.description
        )
    }

    public func listThreadSpawnChildren(
        parentThreadID: ThreadId,
        statusFilter: ThreadSpawnEdgeStatus?
    ) async throws -> [ThreadId] {
        var query = "SELECT child_thread_id FROM thread_spawn_edges WHERE parent_thread_id = ?"
        var bindings = [parentThreadID.description]
        if let statusFilter {
            query += " AND status = ?"
            bindings.append(statusFilter.rawValue)
        }
        query += " ORDER BY child_thread_id"

        return try threadIDs(query: query, bindings: bindings)
    }

    public func listThreadSpawnDescendants(
        rootThreadID: ThreadId,
        statusFilter: ThreadSpawnEdgeStatus?
    ) async throws -> [ThreadId] {
        let statusFilterSQL = statusFilter == nil ? "" : " AND status = ?"
        let query =
            """
            WITH RECURSIVE subtree(child_thread_id, depth) AS (
                SELECT child_thread_id, 1
                FROM thread_spawn_edges
                WHERE parent_thread_id = ?\(statusFilterSQL)
                UNION ALL
                SELECT edge.child_thread_id, subtree.depth + 1
                FROM thread_spawn_edges AS edge
                JOIN subtree ON edge.parent_thread_id = subtree.child_thread_id
                WHERE 1 = 1\(statusFilterSQL)
            )
            SELECT child_thread_id
            FROM subtree
            ORDER BY depth ASC, child_thread_id ASC
            """

        var bindings = [rootThreadID.description]
        if let statusFilter {
            bindings.append(statusFilter.rawValue)
            bindings.append(statusFilter.rawValue)
        }

        return try threadIDs(query: query, bindings: bindings)
    }

    public func findThreadSpawnChild(
        parentThreadID: ThreadId,
        agentPath: AgentPath
    ) async throws -> ThreadId? {
        try oneThreadID(
            query:
            """
            SELECT threads.id
            FROM thread_spawn_edges
            JOIN threads ON threads.id = thread_spawn_edges.child_thread_id
            WHERE thread_spawn_edges.parent_thread_id = ?
              AND threads.agent_path = ?
            ORDER BY threads.id
            LIMIT 2
            """,
            bindings: [parentThreadID.description, agentPath.description],
            agentPath: agentPath
        )
    }

    public func findThreadSpawnDescendant(
        rootThreadID: ThreadId,
        agentPath: AgentPath
    ) async throws -> ThreadId? {
        try oneThreadID(
            query:
            """
            WITH RECURSIVE subtree(child_thread_id) AS (
                SELECT child_thread_id
                FROM thread_spawn_edges
                WHERE parent_thread_id = ?
                UNION ALL
                SELECT edge.child_thread_id
                FROM thread_spawn_edges AS edge
                JOIN subtree ON edge.parent_thread_id = subtree.child_thread_id
            )
            SELECT threads.id
            FROM subtree
            JOIN threads ON threads.id = subtree.child_thread_id
            WHERE threads.agent_path = ?
            ORDER BY threads.id
            LIMIT 2
            """,
            bindings: [rootThreadID.description, agentPath.description],
            agentPath: agentPath
        )
    }

    private func execute(_ query: String, _ bindings: String...) throws {
        try Self.execute(query, bindings: bindings, database: handle.database)
    }

    private static func execute(_ query: String, bindings: [String] = [], database: OpaquePointer) throws {
        try withStatement(query: query, bindings: bindings, database: database) { statement in
            let result = sqlite3_step(statement)
            guard result == SQLITE_DONE else {
                throw sqliteError(database: database)
            }
        }
    }

    private func threadIDs(query: String, bindings: [String]) throws -> [ThreadId] {
        let database = handle.database
        return try Self.withStatement(query: query, bindings: bindings, database: database) { statement in
            var threadIDs: [ThreadId] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE {
                    return threadIDs
                }
                guard result == SQLITE_ROW else {
                    throw Self.sqliteError(database: database)
                }
                guard let rawValue = sqlite3_column_text(statement, 0) else {
                    throw AgentGraphStoreError.internal(message: "sqlite returned null child_thread_id")
                }
                let value = String(cString: rawValue)
                do {
                    threadIDs.append(try ThreadId(string: value))
                } catch {
                    throw AgentGraphStoreError.internal(message: error.localizedDescription)
                }
            }
        }
    }

    private func oneThreadID(
        query: String,
        bindings: [String],
        agentPath: AgentPath
    ) throws -> ThreadId? {
        let ids = try threadIDs(query: query, bindings: bindings)
        switch ids.count {
        case 0:
            return nil
        case 1:
            return ids[0]
        default:
            throw AgentGraphStoreError.internal(
                message: "multiple agents found for canonical path `\(agentPath)`"
            )
        }
    }

    private static func withStatement<T>(
        query: String,
        bindings: [String],
        database: OpaquePointer,
        body: (OpaquePointer) throws -> T
    ) throws -> T {
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, query, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            throw sqliteError(database: database)
        }
        defer {
            sqlite3_finalize(statement)
        }

        for (index, value) in bindings.enumerated() {
            let bindResult = sqlite3_bind_text(
                statement,
                Int32(index + 1),
                value,
                -1,
                sqliteTransient
            )
            guard bindResult == SQLITE_OK else {
                throw sqliteError(database: database)
            }
        }

        return try body(statement)
    }

    private static func sqliteError(database: OpaquePointer) -> AgentGraphStoreError {
        .internal(message: errorMessage(database: database))
    }

    private static func errorMessage(database: OpaquePointer) -> String {
        if let message = sqlite3_errmsg(database) {
            return String(cString: message)
        }
        return "sqlite error"
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private final class SQLiteDatabaseHandle: @unchecked Sendable {
    let database: OpaquePointer

    init(database: OpaquePointer) {
        self.database = database
    }

    deinit {
        sqlite3_close(database)
    }
}
