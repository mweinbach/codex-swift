import Foundation
import SQLite3

/// SQLite-backed implementation of `AgentGraphStore`.
///
/// This mirrors Rust's state-runtime persistence slices for directional thread-spawn edges and
/// thread-scoped dynamic tools, preserving Rust's ordering, upsert, and status-filter semantics.
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
            try Self.execute(
                """
                CREATE TABLE IF NOT EXISTS thread_dynamic_tools (
                    thread_id TEXT NOT NULL,
                    position INTEGER NOT NULL,
                    namespace TEXT,
                    name TEXT NOT NULL,
                    description TEXT NOT NULL,
                    input_schema TEXT NOT NULL,
                    defer_loading INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY(thread_id, position),
                    FOREIGN KEY(thread_id) REFERENCES threads(id) ON DELETE CASCADE
                )
                """,
                database: openedDatabase
            )
            try Self.execute(
                """
                CREATE INDEX IF NOT EXISTS idx_thread_dynamic_tools_thread
                    ON thread_dynamic_tools(thread_id)
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

    public func insertThreadSpawnEdgeIfAbsent(
        parentThreadID: ThreadId,
        childThreadID: ThreadId
    ) async throws {
        try execute(
            """
            INSERT INTO thread_spawn_edges (
                parent_thread_id,
                child_thread_id,
                status
            ) VALUES (?, ?, ?)
            ON CONFLICT(child_thread_id) DO NOTHING
            """,
            parentThreadID.description,
            childThreadID.description,
            ThreadSpawnEdgeStatus.open.rawValue
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

    public func persistDynamicTools(
        threadID: ThreadId,
        tools: [DynamicToolSpec]?
    ) async throws {
        guard let tools, !tools.isEmpty else {
            return
        }

        let database = handle.database
        try Self.execute("BEGIN IMMEDIATE", database: database)
        do {
            for (index, tool) in tools.enumerated() {
                let inputSchema = try String(
                    decoding: JSONEncoder().encode(tool.inputSchema),
                    as: UTF8.self
                )
                try Self.execute(
                    """
                    INSERT INTO thread_dynamic_tools (
                        thread_id,
                        position,
                        namespace,
                        name,
                        description,
                        input_schema,
                        defer_loading
                    ) VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(thread_id, position) DO NOTHING
                    """,
                    bindings: [
                        .text(threadID.description),
                        .int(Int64(index)),
                        .optionalText(tool.namespace),
                        .text(tool.name),
                        .text(tool.description),
                        .text(inputSchema),
                        .bool(tool.deferLoading),
                    ],
                    database: database
                )
            }
            try Self.execute("COMMIT", database: database)
        } catch {
            try? Self.execute("ROLLBACK", database: database)
            throw error
        }
    }

    public func getDynamicTools(threadID: ThreadId) async throws -> [DynamicToolSpec]? {
        let database = handle.database
        return try Self.withStatement(
            query:
            """
            SELECT namespace, name, description, input_schema, defer_loading
            FROM thread_dynamic_tools
            WHERE thread_id = ?
            ORDER BY position ASC
            """,
            bindings: [.text(threadID.description)],
            database: database
        ) { statement in
            var tools: [DynamicToolSpec] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE {
                    return tools.isEmpty ? nil : tools
                }
                guard result == SQLITE_ROW else {
                    throw Self.sqliteError(database: database)
                }

                let namespace = Self.optionalTextColumn(statement, index: 0)
                let name = try Self.requiredTextColumn(statement, index: 1, columnName: "name")
                let description = try Self.requiredTextColumn(statement, index: 2, columnName: "description")
                let inputSchemaText = try Self.requiredTextColumn(statement, index: 3, columnName: "input_schema")
                let inputSchema = try JSONDecoder().decode(JSONValue.self, from: Data(inputSchemaText.utf8))
                let deferLoading = sqlite3_column_int(statement, 4) != 0
                tools.append(DynamicToolSpec(
                    namespace: namespace,
                    name: name,
                    description: description,
                    inputSchema: inputSchema,
                    deferLoading: deferLoading
                ))
            }
        }
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
        try execute(query, bindings: bindings.map(SQLiteBinding.text), database: database)
    }

    private static func execute(_ query: String, bindings: [SQLiteBinding], database: OpaquePointer) throws {
        try withStatement(query: query, bindings: bindings, database: database) { statement in
            let result = sqlite3_step(statement)
            guard result == SQLITE_DONE else {
                throw sqliteError(database: database)
            }
        }
    }

    private func threadIDs(query: String, bindings: [String]) throws -> [ThreadId] {
        let database = handle.database
        return try Self.withStatement(
            query: query,
            bindings: bindings.map(SQLiteBinding.text),
            database: database
        ) { statement in
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
        bindings: [SQLiteBinding],
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
            let bindIndex = Int32(index + 1)
            let bindResult: Int32
            switch value {
            case let .text(text):
                bindResult = sqlite3_bind_text(statement, bindIndex, text, -1, sqliteTransient)
            case let .optionalText(text):
                if let text {
                    bindResult = sqlite3_bind_text(statement, bindIndex, text, -1, sqliteTransient)
                } else {
                    bindResult = sqlite3_bind_null(statement, bindIndex)
                }
            case let .int(number):
                bindResult = sqlite3_bind_int64(statement, bindIndex, number)
            case let .bool(flag):
                bindResult = sqlite3_bind_int(statement, bindIndex, flag ? 1 : 0)
            }
            guard bindResult == SQLITE_OK else {
                throw sqliteError(database: database)
            }
        }

        return try body(statement)
    }

    private static func requiredTextColumn(
        _ statement: OpaquePointer,
        index: Int32,
        columnName: String
    ) throws -> String {
        guard let rawValue = sqlite3_column_text(statement, index) else {
            throw AgentGraphStoreError.internal(message: "sqlite returned null \(columnName)")
        }
        return String(cString: rawValue)
    }

    private static func optionalTextColumn(_ statement: OpaquePointer, index: Int32) -> String? {
        guard let rawValue = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: rawValue)
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

private enum SQLiteBinding {
    case text(String)
    case optionalText(String?)
    case int(Int64)
    case bool(Bool)
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
