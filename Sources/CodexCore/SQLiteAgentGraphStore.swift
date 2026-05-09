import Foundation
import SQLite3

/// SQLite-backed implementation of `AgentGraphStore`.
///
/// This mirrors Rust's state-runtime persistence slices for directional thread-spawn edges and
/// thread-scoped dynamic tools, preserving Rust's ordering, upsert, and status-filter semantics.
public actor SQLiteAgentGraphStore: AgentGraphStore {
    private let handle: SQLiteDatabaseHandle
    private var threadUpdatedAtMilliseconds: Int64 = 0

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

    public func getThreadMemoryMode(threadID: ThreadId) async throws -> String? {
        let database = handle.database
        return try Self.withStatement(
            query: "SELECT memory_mode FROM threads WHERE id = ?",
            bindings: [.text(threadID.description)],
            database: database
        ) { statement in
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return nil
            }
            guard result == SQLITE_ROW else {
                throw Self.sqliteError(database: database)
            }
            return Self.optionalTextColumn(statement, index: 0)
        }
    }

    public func setThreadMemoryMode(threadID: ThreadId, memoryMode: String) async throws -> Bool {
        let database = handle.database
        try Self.execute(
            "UPDATE threads SET memory_mode = ? WHERE id = ?",
            bindings: [
                .text(memoryMode),
                .text(threadID.description),
            ],
            database: database
        )
        return sqlite3_changes(database) > 0
    }

    public func findRolloutPath(
        threadID: ThreadId,
        archiveFilter: ThreadArchiveFilter
    ) async throws -> String? {
        var query = "SELECT rollout_path FROM threads WHERE id = ?"
        switch archiveFilter {
        case .all:
            break
        case .archivedOnly:
            query += " AND archived = 1"
        case .unarchivedOnly:
            query += " AND archived = 0"
        }

        let database = handle.database
        return try Self.withStatement(
            query: query,
            bindings: [.text(threadID.description)],
            database: database
        ) { statement in
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return nil
            }
            guard result == SQLITE_ROW else {
                throw Self.sqliteError(database: database)
            }
            return Self.optionalTextColumn(statement, index: 0)
        }
    }

    public func markThreadArchived(
        threadID: ThreadId,
        rolloutPath: URL,
        archivedAt: Date
    ) async throws -> Bool {
        let database = handle.database
        let archivedAtSeconds = Self.epochSeconds(archivedAt)
        if let modifiedAt = Self.fileModificationDate(rolloutPath) {
            let updatedAtMilliseconds = allocateThreadUpdatedAt(modifiedAt)
            try Self.execute(
                """
                UPDATE threads
                SET archived = 1,
                    archived_at = ?,
                    rollout_path = ?,
                    updated_at = ?,
                    updated_at_ms = ?
                WHERE id = ?
                """,
                bindings: [
                    .int(archivedAtSeconds),
                    .text(rolloutPath.path),
                    .int(Self.epochSeconds(fromMilliseconds: updatedAtMilliseconds)),
                    .int(updatedAtMilliseconds),
                    .text(threadID.description),
                ],
                database: database
            )
        } else {
            try Self.execute(
                """
                UPDATE threads
                SET archived = 1,
                    archived_at = ?,
                    rollout_path = ?
                WHERE id = ?
                """,
                bindings: [
                    .int(archivedAtSeconds),
                    .text(rolloutPath.path),
                    .text(threadID.description),
                ],
                database: database
            )
        }
        return sqlite3_changes(database) > 0
    }

    public func markThreadUnarchived(threadID: ThreadId, rolloutPath: URL) async throws -> Bool {
        let database = handle.database
        if let modifiedAt = Self.fileModificationDate(rolloutPath) {
            let updatedAtMilliseconds = allocateThreadUpdatedAt(modifiedAt)
            try Self.execute(
                """
                UPDATE threads
                SET archived = 0,
                    archived_at = NULL,
                    rollout_path = ?,
                    updated_at = ?,
                    updated_at_ms = ?
                WHERE id = ?
                """,
                bindings: [
                    .text(rolloutPath.path),
                    .int(Self.epochSeconds(fromMilliseconds: updatedAtMilliseconds)),
                    .int(updatedAtMilliseconds),
                    .text(threadID.description),
                ],
                database: database
            )
        } else {
            try Self.execute(
                """
                UPDATE threads
                SET archived = 0,
                    archived_at = NULL,
                    rollout_path = ?
                WHERE id = ?
                """,
                bindings: [
                    .text(rolloutPath.path),
                    .text(threadID.description),
                ],
                database: database
            )
        }
        return sqlite3_changes(database) > 0
    }

    public func listThreadIDs(
        limit: Int,
        anchor: ThreadListAnchor?,
        sortKey: ThreadListSortKey,
        allowedSources: [String],
        modelProviders: [String]?,
        archivedOnly: Bool
    ) async throws -> [ThreadId] {
        var query = "SELECT threads.id FROM threads WHERE 1 = 1"
        var bindings: [SQLiteBinding] = []
        query += archivedOnly ? " AND threads.archived = 1" : " AND threads.archived = 0"
        query += " AND threads.first_user_message <> ''"
        if !allowedSources.isEmpty {
            query += " AND threads.source IN (\(Self.placeholders(count: allowedSources.count)))"
            bindings.append(contentsOf: allowedSources.map(SQLiteBinding.text))
        }
        if let modelProviders, !modelProviders.isEmpty {
            query += " AND threads.model_provider IN (\(Self.placeholders(count: modelProviders.count)))"
            bindings.append(contentsOf: modelProviders.map(SQLiteBinding.text))
        }
        if let anchor {
            query += " AND \(sortKey.sqlColumn) < ?"
            bindings.append(.int(Self.epochMilliseconds(anchor.timestamp)))
        }
        query += " ORDER BY \(sortKey.sqlColumn) DESC LIMIT ?"
        bindings.append(.int(Int64(limit)))

        return try threadIDs(query: query, bindings: bindings)
    }

    public func listThreads(
        pageSize: Int,
        filters: ThreadListFilterOptions
    ) async throws -> ThreadsPage {
        let limit = pageSize == Int.max ? Int.max : pageSize + 1
        var query = Self.threadSelectColumns + " FROM threads"
        var bindings: [SQLiteBinding] = []
        Self.appendThreadFilters(query: &query, bindings: &bindings, filters: filters)
        query += " ORDER BY \(filters.sortKey.sqlColumn) \(filters.sortDirection.sqlKeyword) LIMIT ?"
        bindings.append(.int(Int64(limit)))

        let database = handle.database
        var items = try Self.withStatement(query: query, bindings: bindings, database: database) { statement in
            var items: [ThreadMetadata] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE {
                    return items
                }
                guard result == SQLITE_ROW else {
                    throw Self.sqliteError(database: database)
                }
                items.append(try Self.threadMetadata(from: statement))
            }
        }
        let numScannedRows = items.count
        let nextAnchor: ThreadListAnchor?
        if items.count > pageSize {
            items.removeLast()
            nextAnchor = items.last.map { item in
                ThreadListAnchor(timestamp: item.timestamp(for: filters.sortKey))
            }
        } else {
            nextAnchor = nil
        }

        return ThreadsPage(
            items: items,
            nextAnchor: nextAnchor,
            numScannedRows: numScannedRows
        )
    }

    public func findThreadByExactTitle(
        title: String,
        allowedSources: [String],
        modelProviders: [String]?,
        archivedOnly: Bool,
        cwd: URL?
    ) async throws -> ThreadMetadata? {
        var query =
            """
            SELECT
                threads.id,
                threads.rollout_path,
                threads.created_at_ms AS created_at,
                threads.updated_at_ms AS updated_at,
                threads.source,
                threads.thread_source,
                threads.agent_nickname,
                threads.agent_role,
                threads.agent_path,
                threads.model_provider,
                threads.model,
                threads.reasoning_effort,
                threads.cwd,
                threads.cli_version,
                threads.title,
                threads.sandbox_policy,
                threads.approval_mode,
                threads.tokens_used,
                threads.first_user_message,
                threads.archived_at,
                threads.git_sha,
                threads.git_branch,
                threads.git_origin_url
            FROM threads
            WHERE 1 = 1
            """
        var bindings: [SQLiteBinding] = []
        query += archivedOnly ? " AND threads.archived = 1" : " AND threads.archived = 0"
        query += " AND threads.first_user_message <> ''"
        if !allowedSources.isEmpty {
            query += " AND threads.source IN (\(Self.placeholders(count: allowedSources.count)))"
            bindings.append(contentsOf: allowedSources.map(SQLiteBinding.text))
        }
        if let modelProviders, !modelProviders.isEmpty {
            query += " AND threads.model_provider IN (\(Self.placeholders(count: modelProviders.count)))"
            bindings.append(contentsOf: modelProviders.map(SQLiteBinding.text))
        }
        query += " AND threads.title = ?"
        bindings.append(.text(title))
        if let cwd {
            query += " AND threads.cwd = ?"
            bindings.append(.text(cwd.path))
        }
        query += " ORDER BY threads.updated_at_ms DESC LIMIT ?"
        bindings.append(.int(1))

        let database = handle.database
        return try Self.withStatement(query: query, bindings: bindings, database: database) { statement in
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return nil
            }
            guard result == SQLITE_ROW else {
                throw Self.sqliteError(database: database)
            }
            return try Self.threadMetadata(from: statement)
        }
    }

    public func updateThreadTitle(threadID: ThreadId, title: String) async throws -> Bool {
        let database = handle.database
        try Self.execute(
            "UPDATE threads SET title = ? WHERE id = ?",
            bindings: [
                .text(title),
                .text(threadID.description),
            ],
            database: database
        )
        return sqlite3_changes(database) > 0
    }

    public func touchThreadUpdatedAt(threadID: ThreadId, updatedAt: Date) async throws -> Bool {
        let allocatedMilliseconds = allocateThreadUpdatedAt(updatedAt)
        let database = handle.database
        try Self.execute(
            "UPDATE threads SET updated_at = ?, updated_at_ms = ? WHERE id = ?",
            bindings: [
                .int(Self.epochSeconds(fromMilliseconds: allocatedMilliseconds)),
                .int(allocatedMilliseconds),
                .text(threadID.description),
            ],
            database: database
        )
        return sqlite3_changes(database) > 0
    }

    public func updateThreadGitInfo(
        threadID: ThreadId,
        sha: ThreadGitInfoPatchValue,
        branch: ThreadGitInfoPatchValue,
        originURL: ThreadGitInfoPatchValue
    ) async throws -> Bool {
        let database = handle.database
        try Self.execute(
            """
            UPDATE threads
            SET
                git_sha = CASE WHEN ? THEN ? ELSE git_sha END,
                git_branch = CASE WHEN ? THEN ? ELSE git_branch END,
                git_origin_url = CASE WHEN ? THEN ? ELSE git_origin_url END
            WHERE id = ?
            """,
            bindings: [
                .bool(sha.shouldUpdate),
                .optionalText(sha.replacement),
                .bool(branch.shouldUpdate),
                .optionalText(branch.replacement),
                .bool(originURL.shouldUpdate),
                .optionalText(originURL.replacement),
                .text(threadID.description),
            ],
            database: database
        )
        return sqlite3_changes(database) > 0
    }

    public func deleteThread(threadID: ThreadId) async throws -> Int {
        let database = handle.database
        try Self.execute(
            "DELETE FROM threads WHERE id = ?",
            bindings: [.text(threadID.description)],
            database: database
        )
        return Int(sqlite3_changes(database))
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

    private func allocateThreadUpdatedAt(_ updatedAt: Date) -> Int64 {
        let candidate = Self.epochMilliseconds(updatedAt)
        if candidate > threadUpdatedAtMilliseconds {
            threadUpdatedAtMilliseconds = candidate
            return candidate
        }

        if Self.saturatingAdd(candidate, 1_000) <= threadUpdatedAtMilliseconds {
            return candidate
        }

        threadUpdatedAtMilliseconds = Self.saturatingAdd(threadUpdatedAtMilliseconds, 1)
        return threadUpdatedAtMilliseconds
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
        try threadIDs(query: query, bindings: bindings.map(SQLiteBinding.text))
    }

    private func threadIDs(query: String, bindings: [SQLiteBinding]) throws -> [ThreadId] {
        let database = handle.database
        return try Self.withStatement(
            query: query,
            bindings: bindings,
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

    private static func optionalIntColumn(_ statement: OpaquePointer, index: Int32) -> Int64? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, index)
    }

    private static func epochMilliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded(.down))
    }

    private static func epochSeconds(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970.rounded(.down))
    }

    private static func epochSeconds(fromMilliseconds milliseconds: Int64) -> Int64 {
        milliseconds / 1_000
    }

    private static func fileModificationDate(_ url: URL) -> Date? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        return attributes[.modificationDate] as? Date
    }

    private static func placeholders(count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }

    private static let threadSelectColumns =
        """
        SELECT
            threads.id,
            threads.rollout_path,
            threads.created_at_ms AS created_at,
            threads.updated_at_ms AS updated_at,
            threads.source,
            threads.thread_source,
            threads.agent_nickname,
            threads.agent_role,
            threads.agent_path,
            threads.model_provider,
            threads.model,
            threads.reasoning_effort,
            threads.cwd,
            threads.cli_version,
            threads.title,
            threads.sandbox_policy,
            threads.approval_mode,
            threads.tokens_used,
            threads.first_user_message,
            threads.archived_at,
            threads.git_sha,
            threads.git_branch,
            threads.git_origin_url
        """

    private static func appendThreadFilters(
        query: inout String,
        bindings: inout [SQLiteBinding],
        filters: ThreadListFilterOptions
    ) {
        query += " WHERE 1 = 1"
        query += filters.archivedOnly ? " AND threads.archived = 1" : " AND threads.archived = 0"
        query += " AND threads.first_user_message <> ''"
        if !filters.allowedSources.isEmpty {
            query += " AND threads.source IN (\(placeholders(count: filters.allowedSources.count)))"
            bindings.append(contentsOf: filters.allowedSources.map(SQLiteBinding.text))
        }
        if let modelProviders = filters.modelProviders, !modelProviders.isEmpty {
            query += " AND threads.model_provider IN (\(placeholders(count: modelProviders.count)))"
            bindings.append(contentsOf: modelProviders.map(SQLiteBinding.text))
        }
        if let cwdFilters = filters.cwdFilters {
            if cwdFilters.isEmpty {
                query += " AND 1 = 0"
            } else {
                query += " AND threads.cwd IN (\(placeholders(count: cwdFilters.count)))"
                bindings.append(contentsOf: cwdFilters.map { .text($0.path) })
            }
        }
        if let searchTerm = filters.searchTerm {
            query += " AND instr(threads.title, ?) > 0"
            bindings.append(.text(searchTerm))
        }
        if let anchor = filters.anchor {
            query += " AND \(filters.sortKey.sqlColumn) \(filters.sortDirection.anchorOperator) ?"
            bindings.append(.int(epochMilliseconds(anchor.timestamp)))
        }
    }

    private static func threadMetadata(from statement: OpaquePointer) throws -> ThreadMetadata {
        let threadSource: ThreadSource?
        if let rawThreadSource = optionalTextColumn(statement, index: 5) {
            guard let parsedThreadSource = ThreadSource(rawValue: rawThreadSource) else {
                throw AgentGraphStoreError.internal(message: "unknown thread source: \(rawThreadSource)")
            }
            threadSource = parsedThreadSource
        } else {
            threadSource = nil
        }
        let firstUserMessage = try requiredTextColumn(statement, index: 18, columnName: "first_user_message")
        return ThreadMetadata(
            id: try ThreadId(string: try requiredTextColumn(statement, index: 0, columnName: "id")),
            rolloutPath: try requiredTextColumn(statement, index: 1, columnName: "rollout_path"),
            createdAt: epochMillisecondsDate(sqlite3_column_int64(statement, 2)),
            updatedAt: epochMillisecondsDate(sqlite3_column_int64(statement, 3)),
            source: try requiredTextColumn(statement, index: 4, columnName: "source"),
            threadSource: threadSource,
            agentNickname: optionalTextColumn(statement, index: 6),
            agentRole: optionalTextColumn(statement, index: 7),
            agentPath: optionalTextColumn(statement, index: 8),
            modelProvider: try requiredTextColumn(statement, index: 9, columnName: "model_provider"),
            model: optionalTextColumn(statement, index: 10),
            reasoningEffort: optionalTextColumn(statement, index: 11).flatMap(ReasoningEffort.init(rawValue:)),
            cwd: try requiredTextColumn(statement, index: 12, columnName: "cwd"),
            cliVersion: try requiredTextColumn(statement, index: 13, columnName: "cli_version"),
            title: try requiredTextColumn(statement, index: 14, columnName: "title"),
            sandboxPolicy: try requiredTextColumn(statement, index: 15, columnName: "sandbox_policy"),
            approvalMode: try requiredTextColumn(statement, index: 16, columnName: "approval_mode"),
            tokensUsed: sqlite3_column_int64(statement, 17),
            firstUserMessage: firstUserMessage.isEmpty ? nil : firstUserMessage,
            archivedAt: optionalIntColumn(statement, index: 19).map(epochSecondsDate),
            gitSHA: optionalTextColumn(statement, index: 20),
            gitBranch: optionalTextColumn(statement, index: 21),
            gitOriginURL: optionalTextColumn(statement, index: 22)
        )
    }

    private static func epochMillisecondsDate(_ value: Int64) -> Date {
        let minimumEpochMilliseconds: Int64 = 1_577_836_800_000
        let milliseconds = value < minimumEpochMilliseconds ? saturatingMultiply(value, 1_000) : value
        return Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
    }

    private static func epochSecondsDate(_ seconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(seconds))
    }

    private static func saturatingAdd(_ value: Int64, _ increment: Int64) -> Int64 {
        let result = value.addingReportingOverflow(increment)
        return result.overflow ? Int64.max : result.partialValue
    }

    private static func saturatingMultiply(_ value: Int64, _ multiplier: Int64) -> Int64 {
        let result = value.multipliedReportingOverflow(by: multiplier)
        return result.overflow ? Int64.max : result.partialValue
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

public enum ThreadArchiveFilter: Equatable, Sendable {
    case all
    case archivedOnly
    case unarchivedOnly
}

public struct ThreadMetadata: Equatable, Sendable {
    public let id: ThreadId
    public let rolloutPath: String
    public let createdAt: Date
    public let updatedAt: Date
    public let source: String
    public let threadSource: ThreadSource?
    public let agentNickname: String?
    public let agentRole: String?
    public let agentPath: String?
    public let modelProvider: String
    public let model: String?
    public let reasoningEffort: ReasoningEffort?
    public let cwd: String
    public let cliVersion: String
    public let title: String
    public let sandboxPolicy: String
    public let approvalMode: String
    public let tokensUsed: Int64
    public let firstUserMessage: String?
    public let archivedAt: Date?
    public let gitSHA: String?
    public let gitBranch: String?
    public let gitOriginURL: String?

    public init(
        id: ThreadId,
        rolloutPath: String,
        createdAt: Date,
        updatedAt: Date,
        source: String,
        threadSource: ThreadSource? = nil,
        agentNickname: String? = nil,
        agentRole: String? = nil,
        agentPath: String? = nil,
        modelProvider: String,
        model: String? = nil,
        reasoningEffort: ReasoningEffort? = nil,
        cwd: String,
        cliVersion: String,
        title: String,
        sandboxPolicy: String,
        approvalMode: String,
        tokensUsed: Int64,
        firstUserMessage: String? = nil,
        archivedAt: Date? = nil,
        gitSHA: String? = nil,
        gitBranch: String? = nil,
        gitOriginURL: String? = nil
    ) {
        self.id = id
        self.rolloutPath = rolloutPath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.source = source
        self.threadSource = threadSource
        self.agentNickname = agentNickname
        self.agentRole = agentRole
        self.agentPath = agentPath
        self.modelProvider = modelProvider
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.cwd = cwd
        self.cliVersion = cliVersion
        self.title = title
        self.sandboxPolicy = sandboxPolicy
        self.approvalMode = approvalMode
        self.tokensUsed = tokensUsed
        self.firstUserMessage = firstUserMessage
        self.archivedAt = archivedAt
        self.gitSHA = gitSHA
        self.gitBranch = gitBranch
        self.gitOriginURL = gitOriginURL
    }
}

public struct ThreadsPage: Equatable, Sendable {
    public let items: [ThreadMetadata]
    public let nextAnchor: ThreadListAnchor?
    public let numScannedRows: Int

    public init(
        items: [ThreadMetadata],
        nextAnchor: ThreadListAnchor?,
        numScannedRows: Int
    ) {
        self.items = items
        self.nextAnchor = nextAnchor
        self.numScannedRows = numScannedRows
    }
}

public struct ThreadListFilterOptions: Equatable, Sendable {
    public let archivedOnly: Bool
    public let allowedSources: [String]
    public let modelProviders: [String]?
    public let cwdFilters: [URL]?
    public let anchor: ThreadListAnchor?
    public let sortKey: ThreadListSortKey
    public let sortDirection: ThreadListSortDirection
    public let searchTerm: String?

    public init(
        archivedOnly: Bool = false,
        allowedSources: [String] = [],
        modelProviders: [String]? = nil,
        cwdFilters: [URL]? = nil,
        anchor: ThreadListAnchor? = nil,
        sortKey: ThreadListSortKey = .updatedAt,
        sortDirection: ThreadListSortDirection = .descending,
        searchTerm: String? = nil
    ) {
        self.archivedOnly = archivedOnly
        self.allowedSources = allowedSources
        self.modelProviders = modelProviders
        self.cwdFilters = cwdFilters
        self.anchor = anchor
        self.sortKey = sortKey
        self.sortDirection = sortDirection
        self.searchTerm = searchTerm
    }
}

public struct ThreadListAnchor: Equatable, Sendable {
    public let timestamp: Date

    public init(timestamp: Date) {
        self.timestamp = timestamp
    }
}

public enum ThreadListSortKey: Equatable, Sendable {
    case createdAt
    case updatedAt

    fileprivate var sqlColumn: String {
        switch self {
        case .createdAt:
            return "threads.created_at_ms"
        case .updatedAt:
            return "threads.updated_at_ms"
        }
    }
}

public enum ThreadListSortDirection: Equatable, Sendable {
    case ascending
    case descending

    fileprivate var sqlKeyword: String {
        switch self {
        case .ascending:
            return "ASC"
        case .descending:
            return "DESC"
        }
    }

    fileprivate var anchorOperator: String {
        switch self {
        case .ascending:
            return ">"
        case .descending:
            return "<"
        }
    }
}

private extension ThreadMetadata {
    func timestamp(for sortKey: ThreadListSortKey) -> Date {
        switch sortKey {
        case .createdAt:
            return createdAt
        case .updatedAt:
            return updatedAt
        }
    }
}

public enum ThreadGitInfoPatchValue: Equatable, Sendable {
    case preserve
    case clear
    case set(String)

    fileprivate var shouldUpdate: Bool {
        switch self {
        case .preserve:
            return false
        case .clear, .set:
            return true
        }
    }

    fileprivate var replacement: String? {
        switch self {
        case .preserve, .clear:
            return nil
        case let .set(value):
            return value
        }
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
