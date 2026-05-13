import Foundation
import SQLite3

/// SQLite-backed implementation of `AgentGraphStore`.
///
/// This mirrors Rust's state-runtime persistence slices for directional thread-spawn edges and
/// thread-scoped dynamic tools, preserving Rust's ordering, upsert, and status-filter semantics.
public actor SQLiteAgentGraphStore: AgentGraphStore {
    private let handle: SQLiteDatabaseHandle
    private let defaultProvider: String
    private var threadUpdatedAtMilliseconds: Int64 = 0
    private static let defaultRetryRemaining: Int64 = 3
    private static let memoryStage1JobKind = "memory_stage1"
    private static let memoryConsolidateGlobalJobKind = "memory_consolidate_global"
    private static let memoryConsolidationJobKey = "global"
    private static let phase2SuccessCooldownSeconds: Int64 = 6 * 60 * 60

    public init(databaseURL: URL, defaultProvider: String = "openai") throws {
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
                """,
                database: openedDatabase
            )
            try Self.execute(
                "CREATE INDEX IF NOT EXISTS idx_threads_created_at ON threads(created_at_ms DESC, id DESC)",
                database: openedDatabase
            )
            try Self.execute(
                "CREATE INDEX IF NOT EXISTS idx_threads_updated_at ON threads(updated_at_ms DESC, id DESC)",
                database: openedDatabase
            )
            try Self.execute(
                "CREATE INDEX IF NOT EXISTS idx_threads_archived ON threads(archived)",
                database: openedDatabase
            )
            try Self.execute(
                "CREATE INDEX IF NOT EXISTS idx_threads_source ON threads(source)",
                database: openedDatabase
            )
            try Self.execute(
                "CREATE INDEX IF NOT EXISTS idx_threads_provider ON threads(model_provider)",
                database: openedDatabase
            )
            try Self.execute(
                """
                CREATE TABLE IF NOT EXISTS stage1_outputs (
                    thread_id TEXT NOT NULL PRIMARY KEY,
                    source_updated_at INTEGER NOT NULL,
                    raw_memory TEXT NOT NULL,
                    rollout_summary TEXT NOT NULL,
                    rollout_slug TEXT,
                    generated_at INTEGER NOT NULL,
                    usage_count INTEGER,
                    last_usage INTEGER,
                    selected_for_phase2 INTEGER NOT NULL DEFAULT 0,
                    selected_for_phase2_source_updated_at INTEGER,
                    FOREIGN KEY(thread_id) REFERENCES threads(id) ON DELETE CASCADE
                )
                """,
                database: openedDatabase
            )
            try Self.addColumnIfMissing(
                table: "stage1_outputs",
                column: "rollout_slug",
                definition: "TEXT",
                database: openedDatabase
            )
            try Self.addColumnIfMissing(
                table: "stage1_outputs",
                column: "usage_count",
                definition: "INTEGER",
                database: openedDatabase
            )
            try Self.addColumnIfMissing(
                table: "stage1_outputs",
                column: "last_usage",
                definition: "INTEGER",
                database: openedDatabase
            )
            try Self.addColumnIfMissing(
                table: "stage1_outputs",
                column: "selected_for_phase2",
                definition: "INTEGER NOT NULL DEFAULT 0",
                database: openedDatabase
            )
            try Self.addColumnIfMissing(
                table: "stage1_outputs",
                column: "selected_for_phase2_source_updated_at",
                definition: "INTEGER",
                database: openedDatabase
            )
            try Self.execute(
                """
                CREATE INDEX IF NOT EXISTS idx_stage1_outputs_source_updated_at
                    ON stage1_outputs(source_updated_at DESC, thread_id DESC)
                """,
                database: openedDatabase
            )
            try Self.execute(
                """
                CREATE TABLE IF NOT EXISTS jobs (
                    kind TEXT NOT NULL,
                    job_key TEXT NOT NULL,
                    status TEXT NOT NULL,
                    worker_id TEXT,
                    ownership_token TEXT,
                    started_at INTEGER,
                    finished_at INTEGER,
                    lease_until INTEGER,
                    retry_at INTEGER,
                    retry_remaining INTEGER NOT NULL,
                    last_error TEXT,
                    input_watermark INTEGER,
                    last_success_watermark INTEGER,
                    PRIMARY KEY (kind, job_key)
                )
                """,
                database: openedDatabase
            )
            try Self.execute(
                """
                CREATE INDEX IF NOT EXISTS idx_jobs_kind_status_retry_lease
                    ON jobs(kind, status, retry_at, lease_until)
                """,
                database: openedDatabase
            )
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
            try Self.execute(
                """
                CREATE TABLE IF NOT EXISTS thread_goals (
                    thread_id TEXT PRIMARY KEY NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
                    goal_id TEXT NOT NULL,
                    objective TEXT NOT NULL,
                    status TEXT NOT NULL CHECK(status IN ('active', 'paused', 'budget_limited', 'complete')),
                    token_budget INTEGER,
                    tokens_used INTEGER NOT NULL DEFAULT 0,
                    time_used_seconds INTEGER NOT NULL DEFAULT 0,
                    created_at_ms INTEGER NOT NULL,
                    updated_at_ms INTEGER NOT NULL
                )
                """,
                database: openedDatabase
            )
            try Self.execute(
                """
                CREATE TABLE IF NOT EXISTS remote_control_enrollments (
                    websocket_url TEXT NOT NULL,
                    account_id TEXT NOT NULL,
                    app_server_client_name TEXT NOT NULL,
                    server_id TEXT NOT NULL,
                    environment_id TEXT NOT NULL,
                    server_name TEXT NOT NULL,
                    updated_at INTEGER NOT NULL,
                    PRIMARY KEY (websocket_url, account_id, app_server_client_name)
                )
                """,
                database: openedDatabase
            )
        } catch {
            sqlite3_close(openedDatabase)
            throw error
        }

        self.defaultProvider = defaultProvider
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

    public func getRemoteControlEnrollment(
        websocketURL: String,
        accountID: String,
        appServerClientName: String?
    ) async throws -> RemoteControlEnrollmentRecord? {
        let database = handle.database
        return try Self.withStatement(
            query:
            """
            SELECT websocket_url, account_id, app_server_client_name, server_id, environment_id, server_name
            FROM remote_control_enrollments
            WHERE websocket_url = ? AND account_id = ? AND app_server_client_name = ?
            """,
            bindings: [
                .text(websocketURL),
                .text(accountID),
                .text(Self.remoteControlAppServerClientNameKey(appServerClientName)),
            ],
            database: database
        ) { statement in
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return nil
            }
            guard result == SQLITE_ROW else {
                throw Self.sqliteError(database: database)
            }
            return RemoteControlEnrollmentRecord(
                websocketURL: try Self.requiredTextColumn(statement, index: 0, columnName: "websocket_url"),
                accountID: try Self.requiredTextColumn(statement, index: 1, columnName: "account_id"),
                appServerClientName: Self.remoteControlAppServerClientNameFromKey(
                    try Self.requiredTextColumn(statement, index: 2, columnName: "app_server_client_name")
                ),
                serverID: try Self.requiredTextColumn(statement, index: 3, columnName: "server_id"),
                environmentID: try Self.requiredTextColumn(statement, index: 4, columnName: "environment_id"),
                serverName: try Self.requiredTextColumn(statement, index: 5, columnName: "server_name")
            )
        }
    }

    public func upsertRemoteControlEnrollment(_ enrollment: RemoteControlEnrollmentRecord) async throws {
        try Self.execute(
            """
            INSERT INTO remote_control_enrollments (
                websocket_url,
                account_id,
                app_server_client_name,
                server_id,
                environment_id,
                server_name,
                updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(websocket_url, account_id, app_server_client_name) DO UPDATE SET
                server_id = excluded.server_id,
                environment_id = excluded.environment_id,
                server_name = excluded.server_name,
                updated_at = excluded.updated_at
            """,
            bindings: [
                .text(enrollment.websocketURL),
                .text(enrollment.accountID),
                .text(Self.remoteControlAppServerClientNameKey(enrollment.appServerClientName)),
                .text(enrollment.serverID),
                .text(enrollment.environmentID),
                .text(enrollment.serverName),
                .int(Self.currentTimeSeconds()),
            ],
            database: handle.database
        )
    }

    public func deleteRemoteControlEnrollment(
        websocketURL: String,
        accountID: String,
        appServerClientName: String?
    ) async throws -> Int {
        let database = handle.database
        try Self.execute(
            """
            DELETE FROM remote_control_enrollments
            WHERE websocket_url = ? AND account_id = ? AND app_server_client_name = ?
            """,
            bindings: [
                .text(websocketURL),
                .text(accountID),
                .text(Self.remoteControlAppServerClientNameKey(appServerClientName)),
            ],
            database: database
        )
        return Int(sqlite3_changes(database))
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

    public func getThread(threadID: ThreadId) async throws -> ThreadMetadata? {
        let database = handle.database
        return try Self.withStatement(
            query: Self.threadSelectColumns + " FROM threads WHERE threads.id = ?",
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
            return try Self.threadMetadata(from: statement)
        }
    }

    public func upsertThread(_ metadata: ThreadMetadata) async throws {
        try await upsertThread(metadata, creationMemoryMode: nil)
    }

    public func insertThreadIfAbsent(_ metadata: ThreadMetadata) async throws -> Bool {
        let updatedAtMilliseconds = allocateThreadUpdatedAt(metadata.updatedAt)
        let database = handle.database
        try Self.execute(
            """
            INSERT INTO threads (
                id,
                rollout_path,
                created_at,
                updated_at,
                created_at_ms,
                updated_at_ms,
                source,
                thread_source,
                agent_nickname,
                agent_role,
                agent_path,
                model_provider,
                model,
                reasoning_effort,
                cwd,
                cli_version,
                title,
                sandbox_policy,
                approval_mode,
                tokens_used,
                first_user_message,
                archived,
                archived_at,
                git_sha,
                git_branch,
                git_origin_url,
                memory_mode
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO NOTHING
            """,
            bindings: Self.threadMetadataBindings(
                metadata,
                updatedAtMilliseconds: updatedAtMilliseconds,
                memoryMode: "enabled"
            ),
            database: database
        )
        let inserted = sqlite3_changes(database) > 0
        try await insertThreadSpawnEdgeFromSourceIfAbsent(
            childThreadID: metadata.id,
            source: metadata.source
        )
        return inserted
    }

    public func applyRolloutItems(
        builder: ThreadMetadataBuilder,
        items: [RolloutRecordItem],
        newThreadMemoryMode: String? = nil,
        updatedAtOverride: Date? = nil
    ) async throws {
        guard !items.isEmpty else {
            return
        }

        let existingMetadata = try await getThread(threadID: builder.id)
        var draft = existingMetadata
            .map(ThreadMetadataDraft.init(metadata:))
            ?? ThreadMetadataDraft(metadata: builder.build(defaultProvider: defaultProvider))
        draft.rolloutPath = builder.rolloutPath.path

        for item in items {
            Self.applyRolloutItem(item, to: &draft, defaultProvider: defaultProvider)
        }
        if let existingMetadata {
            draft.preferExistingGitInfo(existingMetadata)
        }

        let updatedAt = updatedAtOverride ?? Self.fileModificationDate(builder.rolloutPath)
        if let updatedAt {
            draft.updatedAt = updatedAt
        }

        let metadata = draft.metadata
        if existingMetadata == nil {
            try await upsertThread(metadata, creationMemoryMode: newThreadMemoryMode)
        } else {
            try await upsertThread(metadata)
        }

        if let memoryMode = Self.extractMemoryMode(from: items) {
            _ = try await setThreadMemoryMode(threadID: builder.id, memoryMode: memoryMode)
        }
        if let dynamicTools = Self.extractDynamicTools(from: items) {
            try await persistDynamicTools(threadID: builder.id, tools: dynamicTools)
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

    public func getThreadGoal(threadID: ThreadId) async throws -> ThreadGoal? {
        let database = handle.database
        return try Self.withStatement(
            query:
            """
            SELECT
                thread_id,
                objective,
                status,
                token_budget,
                tokens_used,
                time_used_seconds,
                created_at_ms,
                updated_at_ms
            FROM thread_goals
            WHERE thread_id = ?
            """,
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
            return try Self.threadGoal(from: statement)
        }
    }

    public func replaceThreadGoal(
        threadID: ThreadId,
        objective: String,
        status: ThreadGoalStatus,
        tokenBudget: Int64?
    ) async throws -> ThreadGoal {
        let goalID = UUID().uuidString.lowercased()
        let nowMilliseconds = Self.currentTimeMilliseconds()
        let status = Self.statusAfterBudgetLimit(
            status,
            tokensUsed: 0,
            tokenBudget: tokenBudget
        )
        let database = handle.database
        return try Self.withStatement(
            query:
            """
            INSERT INTO thread_goals (
                thread_id,
                goal_id,
                objective,
                status,
                token_budget,
                tokens_used,
                time_used_seconds,
                created_at_ms,
                updated_at_ms
            ) VALUES (?, ?, ?, ?, ?, 0, 0, ?, ?)
            ON CONFLICT(thread_id) DO UPDATE SET
                goal_id = excluded.goal_id,
                objective = excluded.objective,
                status = excluded.status,
                token_budget = excluded.token_budget,
                tokens_used = 0,
                time_used_seconds = 0,
                created_at_ms = excluded.created_at_ms,
                updated_at_ms = excluded.updated_at_ms
            RETURNING
                thread_id,
                objective,
                status,
                token_budget,
                tokens_used,
                time_used_seconds,
                created_at_ms,
                updated_at_ms
            """,
            bindings: [
                .text(threadID.description),
                .text(goalID),
                .text(objective),
                .text(Self.databaseStatus(status)),
                .optionalInt(tokenBudget),
                .int(nowMilliseconds),
                .int(nowMilliseconds),
            ],
            database: database
        ) { statement in
            let result = sqlite3_step(statement)
            guard result == SQLITE_ROW else {
                throw Self.sqliteError(database: database)
            }
            return try Self.threadGoal(from: statement)
        }
    }

    public func updateThreadGoal(
        threadID: ThreadId,
        status: ThreadGoalStatus?,
        tokenBudget: ThreadGoalTokenBudgetUpdate
    ) async throws -> ThreadGoal? {
        let existing = try await getThreadGoal(threadID: threadID)
        guard let existing else {
            return nil
        }
        if status == nil, tokenBudget == .preserve {
            return existing
        }
        let replacementBudget: Int64?
        switch tokenBudget {
        case .preserve:
            replacementBudget = existing.tokenBudget
        case let .set(value):
            replacementBudget = value
        }
        var replacementStatus = status ?? existing.status
        if existing.status == .budgetLimited, replacementStatus == .paused {
            replacementStatus = .budgetLimited
        } else if replacementStatus == .active,
                  let replacementBudget,
                  existing.tokensUsed >= replacementBudget {
            replacementStatus = .budgetLimited
        }

        let nowMilliseconds = Self.currentTimeMilliseconds()
        let database = handle.database
        return try Self.withStatement(
            query:
            """
            UPDATE thread_goals
            SET
                status = ?,
                token_budget = ?,
                updated_at_ms = ?
            WHERE thread_id = ?
            RETURNING
                thread_id,
                objective,
                status,
                token_budget,
                tokens_used,
                time_used_seconds,
                created_at_ms,
                updated_at_ms
            """,
            bindings: [
                .text(Self.databaseStatus(replacementStatus)),
                .optionalInt(replacementBudget),
                .int(nowMilliseconds),
                .text(threadID.description),
            ],
            database: database
        ) { statement in
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return nil
            }
            guard result == SQLITE_ROW else {
                throw Self.sqliteError(database: database)
            }
            return try Self.threadGoal(from: statement)
        }
    }

    public func deleteThreadGoal(threadID: ThreadId) async throws -> Bool {
        let database = handle.database
        try Self.execute(
            "DELETE FROM thread_goals WHERE thread_id = ?",
            bindings: [.text(threadID.description)],
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

    public func clearMemoryData() async throws {
        let database = handle.database
        try Self.execute("BEGIN IMMEDIATE TRANSACTION", bindings: [SQLiteBinding](), database: database)
        do {
            try Self.execute("DELETE FROM stage1_outputs", bindings: [SQLiteBinding](), database: database)
            try Self.execute(
                "DELETE FROM jobs WHERE kind = ? OR kind = ?",
                bindings: [
                    .text("memory_stage1"),
                    .text("memory_consolidate_global")
                ],
                database: database
            )
            try Self.execute("COMMIT", bindings: [SQLiteBinding](), database: database)
        } catch {
            try? Self.execute("ROLLBACK", bindings: [SQLiteBinding](), database: database)
            throw error
        }
    }

    public func listStage1OutputsForGlobal(limit: Int) async throws -> [Stage1Output] {
        guard limit > 0 else {
            return []
        }
        let database = handle.database
        return try Self.withStatement(
            query: """
                SELECT
                    so.thread_id,
                    COALESCE(t.rollout_path, '') AS rollout_path,
                    so.source_updated_at,
                    so.raw_memory,
                    so.rollout_summary,
                    so.rollout_slug,
                    so.generated_at,
                    COALESCE(t.cwd, '') AS cwd,
                    t.git_branch AS git_branch
                FROM stage1_outputs AS so
                LEFT JOIN threads AS t
                    ON t.id = so.thread_id
                WHERE t.memory_mode = 'enabled'
                  AND (length(trim(so.raw_memory)) > 0 OR length(trim(so.rollout_summary)) > 0)
                ORDER BY so.source_updated_at DESC, so.thread_id DESC
                LIMIT ?
                """,
            bindings: [.int(Int64(limit))],
            database: database
        ) { statement in
            var outputs: [Stage1Output] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE {
                    return outputs
                }
                guard result == SQLITE_ROW else {
                    throw Self.sqliteError(database: database)
                }
                outputs.append(try Self.stage1Output(statement))
            }
        }
    }

    public func recordStage1OutputUsage(threadIDs: [ThreadId]) async throws -> Int {
        guard !threadIDs.isEmpty else {
            return 0
        }
        let database = handle.database
        let now = Self.currentTimeSeconds()
        var updatedRows = 0
        try Self.execute("BEGIN IMMEDIATE TRANSACTION", bindings: [SQLiteBinding](), database: database)
        do {
            for threadID in threadIDs {
                try Self.execute(
                    """
                    UPDATE stage1_outputs
                    SET
                        usage_count = COALESCE(usage_count, 0) + 1,
                        last_usage = ?
                    WHERE thread_id = ?
                    """,
                    bindings: [
                        .int(now),
                        .text(threadID.description)
                    ],
                    database: database
                )
                updatedRows += Int(sqlite3_changes(database))
            }
            try Self.execute("COMMIT", bindings: [SQLiteBinding](), database: database)
        } catch {
            try? Self.execute("ROLLBACK", bindings: [SQLiteBinding](), database: database)
            throw error
        }
        return updatedRows
    }

    public func pruneStage1OutputsForRetention(
        maxUnusedDays: Int64,
        limit: Int
    ) async throws -> Int {
        guard limit > 0 else {
            return 0
        }
        let database = handle.database
        let cutoff = Self.saturatingAdd(
            Self.currentTimeSeconds(),
            -Self.saturatingMultiply(max(maxUnusedDays, 0), 86_400)
        )
        try Self.execute(
            """
            DELETE FROM stage1_outputs
            WHERE thread_id IN (
                SELECT thread_id
                FROM stage1_outputs
                WHERE selected_for_phase2 = 0
                  AND COALESCE(last_usage, source_updated_at) < ?
                ORDER BY
                  COALESCE(last_usage, source_updated_at) ASC,
                  source_updated_at ASC,
                  thread_id ASC
                LIMIT ?
            )
            """,
            bindings: [
                .int(cutoff),
                .int(Int64(limit))
            ],
            database: database
        )
        return Int(sqlite3_changes(database))
    }

    public func getPhase2InputSelection(
        limit: Int,
        maxUnusedDays: Int64
    ) async throws -> [Stage1Output] {
        guard limit > 0 else {
            return []
        }
        let database = handle.database
        let cutoff = Self.saturatingAdd(
            Self.currentTimeSeconds(),
            -Self.saturatingMultiply(max(maxUnusedDays, 0), 86_400)
        )
        return try Self.withStatement(
            query: """
                SELECT
                    selected.thread_id,
                    selected.rollout_path,
                    selected.source_updated_at,
                    selected.raw_memory,
                    selected.rollout_summary,
                    selected.rollout_slug,
                    selected.generated_at,
                    selected.cwd,
                    selected.git_branch
                FROM (
                    SELECT
                        so.thread_id,
                        COALESCE(t.rollout_path, '') AS rollout_path,
                        so.source_updated_at,
                        so.raw_memory,
                        so.rollout_summary,
                        so.rollout_slug,
                        so.generated_at,
                        COALESCE(t.cwd, '') AS cwd,
                        t.git_branch AS git_branch
                    FROM stage1_outputs AS so
                    LEFT JOIN threads AS t
                        ON t.id = so.thread_id
                    WHERE t.memory_mode = 'enabled'
                      AND (length(trim(so.raw_memory)) > 0 OR length(trim(so.rollout_summary)) > 0)
                      AND (
                            (so.last_usage IS NOT NULL AND so.last_usage >= ?)
                            OR (so.last_usage IS NULL AND so.source_updated_at >= ?)
                      )
                    ORDER BY
                        COALESCE(so.usage_count, 0) DESC,
                        COALESCE(so.last_usage, so.source_updated_at) DESC,
                        so.source_updated_at DESC,
                        so.thread_id DESC
                    LIMIT ?
                ) AS selected
                ORDER BY selected.thread_id ASC
                """,
            bindings: [
                .int(cutoff),
                .int(cutoff),
                .int(Int64(limit))
            ],
            database: database
        ) { statement in
            var outputs: [Stage1Output] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE {
                    return outputs
                }
                guard result == SQLITE_ROW else {
                    throw Self.sqliteError(database: database)
                }
                outputs.append(try Self.stage1Output(statement))
            }
        }
    }

    public func markThreadMemoryModePolluted(threadID: ThreadId) async throws -> Bool {
        let database = handle.database
        let now = Self.currentTimeSeconds()
        try Self.execute("BEGIN TRANSACTION", bindings: [SQLiteBinding](), database: database)
        do {
            try Self.execute(
                """
                UPDATE threads
                SET memory_mode = 'polluted'
                WHERE id = ? AND memory_mode != 'polluted'
                """,
                bindings: [.text(threadID.description)],
                database: database
            )
            guard sqlite3_changes(database) > 0 else {
                try Self.execute("COMMIT", bindings: [SQLiteBinding](), database: database)
                return false
            }

            let selectedForPhase2 = try Self.optionalIntValue(
                query: """
                    SELECT selected_for_phase2
                    FROM stage1_outputs
                    WHERE thread_id = ?
                    """,
                bindings: [.text(threadID.description)],
                database: database
            ) ?? 0
            if selectedForPhase2 != 0 {
                try Self.enqueueGlobalConsolidation(inputWatermark: now, database: database)
            }

            try Self.execute("COMMIT", bindings: [SQLiteBinding](), database: database)
            return true
        } catch {
            try? Self.execute("ROLLBACK", bindings: [SQLiteBinding](), database: database)
            throw error
        }
    }

    public func claimStage1JobsForStartup(
        currentThreadID: ThreadId,
        params: Stage1StartupClaimParams
    ) async throws -> [Stage1JobClaim] {
        guard params.scanLimit > 0, params.maxClaimed > 0 else {
            return []
        }

        let database = handle.database
        let nowMilliseconds = Self.currentTimeMilliseconds()
        let maxAgeCutoff = Self.saturatingAdd(
            nowMilliseconds,
            -Self.saturatingMultiply(max(params.maxAgeDays, 0), 86_400_000)
        )
        let idleCutoff = Self.saturatingAdd(
            nowMilliseconds,
            -Self.saturatingMultiply(max(params.minRolloutIdleHours, 0), 3_600_000)
        )
        var query = Self.threadSelectColumns
        query +=
            """
             FROM threads
            LEFT JOIN stage1_outputs
                ON stage1_outputs.thread_id = threads.id
            LEFT JOIN jobs
                ON jobs.kind = ?
               AND jobs.job_key = threads.id
            WHERE 1 = 1
              AND threads.archived = 0
              AND threads.first_user_message <> ''
            """
        var bindings: [SQLiteBinding] = [.text(Self.memoryStage1JobKind)]
        if !params.allowedSources.isEmpty {
            query += " AND threads.source IN (\(Self.placeholders(count: params.allowedSources.count)))"
            bindings.append(contentsOf: params.allowedSources.map(SQLiteBinding.text))
        }
        query +=
            """
              AND threads.memory_mode = 'enabled'
              AND threads.id != ?
              AND threads.updated_at_ms >= ?
              AND threads.updated_at_ms <= ?
              AND ((COALESCE(stage1_outputs.source_updated_at, -1) + 1) * 1000) <= threads.updated_at_ms
              AND ((COALESCE(jobs.last_success_watermark, -1) + 1) * 1000) <= threads.updated_at_ms
            ORDER BY threads.updated_at_ms DESC
            LIMIT ?
            """
        bindings.append(.text(currentThreadID.description))
        bindings.append(.int(maxAgeCutoff))
        bindings.append(.int(idleCutoff))
        bindings.append(.int(Int64(params.scanLimit)))

        let candidates = try Self.withStatement(query: query, bindings: bindings, database: database) { statement in
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

        var claims: [Stage1JobClaim] = []
        for candidate in candidates {
            if claims.count >= params.maxClaimed {
                break
            }
            let sourceUpdatedAt = Self.epochSeconds(candidate.updatedAt)
            let outcome = try await tryClaimStage1Job(
                threadID: candidate.id,
                workerID: currentThreadID,
                sourceUpdatedAt: sourceUpdatedAt,
                leaseSeconds: params.leaseSeconds,
                maxRunningJobs: params.maxClaimed
            )
            if case let .claimed(ownershipToken) = outcome {
                claims.append(Stage1JobClaim(thread: candidate, ownershipToken: ownershipToken))
            }
        }
        return claims
    }

    public func tryClaimStage1Job(
        threadID: ThreadId,
        workerID: ThreadId,
        sourceUpdatedAt: Int64,
        leaseSeconds: Int64,
        maxRunningJobs: Int
    ) async throws -> Stage1JobClaimOutcome {
        let database = handle.database
        let now = Self.currentTimeSeconds()
        let leaseUntil = Self.saturatingAdd(now, max(leaseSeconds, 0))
        let maxRunningJobs = Int64(maxRunningJobs)
        let ownershipToken = UUID().uuidString.lowercased()

        try Self.execute("BEGIN IMMEDIATE TRANSACTION", bindings: [SQLiteBinding](), database: database)
        do {
            let existingOutputSourceUpdatedAt = try Self.optionalIntValue(
                query: "SELECT source_updated_at FROM stage1_outputs WHERE thread_id = ?",
                bindings: [.text(threadID.description)],
                database: database
            )
            if existingOutputSourceUpdatedAt.map({ $0 >= sourceUpdatedAt }) == true {
                try Self.execute("COMMIT", bindings: [SQLiteBinding](), database: database)
                return .skippedUpToDate
            }

            let lastSuccessWatermark = try Self.optionalIntValue(
                query: """
                    SELECT last_success_watermark
                    FROM jobs
                    WHERE kind = ? AND job_key = ?
                    """,
                bindings: [
                    .text(Self.memoryStage1JobKind),
                    .text(threadID.description)
                ],
                database: database
            )
            if lastSuccessWatermark.map({ $0 >= sourceUpdatedAt }) == true {
                try Self.execute("COMMIT", bindings: [SQLiteBinding](), database: database)
                return .skippedUpToDate
            }

            try Self.execute(
                """
                INSERT INTO jobs (
                    kind,
                    job_key,
                    status,
                    worker_id,
                    ownership_token,
                    started_at,
                    finished_at,
                    lease_until,
                    retry_at,
                    retry_remaining,
                    last_error,
                    input_watermark,
                    last_success_watermark
                )
                SELECT ?, ?, 'running', ?, ?, ?, NULL, ?, NULL, ?, NULL, ?, NULL
                WHERE (
                    SELECT COUNT(*)
                    FROM jobs
                    WHERE kind = ?
                      AND status = 'running'
                      AND lease_until IS NOT NULL
                      AND lease_until > ?
                ) < ?
                ON CONFLICT(kind, job_key) DO UPDATE SET
                    status = 'running',
                    worker_id = excluded.worker_id,
                    ownership_token = excluded.ownership_token,
                    started_at = excluded.started_at,
                    finished_at = NULL,
                    lease_until = excluded.lease_until,
                    retry_at = NULL,
                    retry_remaining = CASE
                        WHEN excluded.input_watermark > COALESCE(jobs.input_watermark, -1) THEN ?
                        ELSE jobs.retry_remaining
                    END,
                    last_error = NULL,
                    input_watermark = excluded.input_watermark
                WHERE
                    (jobs.status != 'running' OR jobs.lease_until IS NULL OR jobs.lease_until <= excluded.started_at)
                    AND (
                        jobs.retry_at IS NULL
                        OR jobs.retry_at <= excluded.started_at
                        OR excluded.input_watermark > COALESCE(jobs.input_watermark, -1)
                    )
                    AND (
                        jobs.retry_remaining > 0
                        OR excluded.input_watermark > COALESCE(jobs.input_watermark, -1)
                    )
                    AND (
                        SELECT COUNT(*)
                        FROM jobs AS running_jobs
                        WHERE running_jobs.kind = excluded.kind
                          AND running_jobs.status = 'running'
                          AND running_jobs.lease_until IS NOT NULL
                          AND running_jobs.lease_until > excluded.started_at
                          AND running_jobs.job_key != excluded.job_key
                    ) < ?
                """,
                bindings: [
                    .text(Self.memoryStage1JobKind),
                    .text(threadID.description),
                    .text(workerID.description),
                    .text(ownershipToken),
                    .int(now),
                    .int(leaseUntil),
                    .int(Self.defaultRetryRemaining),
                    .int(sourceUpdatedAt),
                    .text(Self.memoryStage1JobKind),
                    .int(now),
                    .int(maxRunningJobs),
                    .int(Self.defaultRetryRemaining),
                    .int(maxRunningJobs)
                ],
                database: database
            )

            if sqlite3_changes(database) > 0 {
                try Self.execute("COMMIT", bindings: [SQLiteBinding](), database: database)
                return .claimed(ownershipToken: ownershipToken)
            }

            let existingJob = try Self.stage1JobSnapshot(
                threadID: threadID,
                database: database
            )
            try Self.execute("COMMIT", bindings: [SQLiteBinding](), database: database)

            guard let existingJob else {
                return .skippedRunning
            }
            if existingJob.retryRemaining <= 0 {
                return .skippedRetryExhausted
            }
            if existingJob.retryAt.map({ $0 > now }) == true {
                return .skippedRetryBackoff
            }
            if existingJob.status == "running", existingJob.leaseUntil.map({ $0 > now }) == true {
                return .skippedRunning
            }
            return .skippedRunning
        } catch {
            try? Self.execute("ROLLBACK", bindings: [SQLiteBinding](), database: database)
            throw error
        }
    }

    public func markStage1JobSucceeded(
        threadID: ThreadId,
        ownershipToken: String,
        sourceUpdatedAt: Int64,
        rawMemory: String,
        rolloutSummary: String,
        rolloutSlug: String?
    ) async throws -> Bool {
        let database = handle.database
        let now = Self.currentTimeSeconds()
        try Self.execute("BEGIN TRANSACTION", bindings: [SQLiteBinding](), database: database)
        do {
            try Self.execute(
                """
                UPDATE jobs
                SET
                    status = 'done',
                    finished_at = ?,
                    lease_until = NULL,
                    last_error = NULL,
                    last_success_watermark = input_watermark
                WHERE kind = ? AND job_key = ?
                  AND status = 'running' AND ownership_token = ?
                """,
                bindings: [
                    .int(now),
                    .text(Self.memoryStage1JobKind),
                    .text(threadID.description),
                    .text(ownershipToken)
                ],
                database: database
            )

            guard sqlite3_changes(database) > 0 else {
                try Self.execute("COMMIT", bindings: [SQLiteBinding](), database: database)
                return false
            }

            try Self.execute(
                """
                INSERT INTO stage1_outputs (
                    thread_id,
                    source_updated_at,
                    raw_memory,
                    rollout_summary,
                    rollout_slug,
                    generated_at
                ) VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(thread_id) DO UPDATE SET
                    source_updated_at = excluded.source_updated_at,
                    raw_memory = excluded.raw_memory,
                    rollout_summary = excluded.rollout_summary,
                    rollout_slug = excluded.rollout_slug,
                    generated_at = excluded.generated_at
                WHERE excluded.source_updated_at >= stage1_outputs.source_updated_at
                """,
                bindings: [
                    .text(threadID.description),
                    .int(sourceUpdatedAt),
                    .text(rawMemory),
                    .text(rolloutSummary),
                    .optionalText(rolloutSlug),
                    .int(now)
                ],
                database: database
            )

            try Self.enqueueGlobalConsolidation(inputWatermark: sourceUpdatedAt, database: database)
            try Self.execute("COMMIT", bindings: [SQLiteBinding](), database: database)
            return true
        } catch {
            try? Self.execute("ROLLBACK", bindings: [SQLiteBinding](), database: database)
            throw error
        }
    }

    public func markStage1JobSucceededNoOutput(
        threadID: ThreadId,
        ownershipToken: String
    ) async throws -> Bool {
        let database = handle.database
        let now = Self.currentTimeSeconds()
        try Self.execute("BEGIN TRANSACTION", bindings: [SQLiteBinding](), database: database)
        do {
            try Self.execute(
                """
                UPDATE jobs
                SET
                    status = 'done',
                    finished_at = ?,
                    lease_until = NULL,
                    last_error = NULL,
                    last_success_watermark = input_watermark
                WHERE kind = ? AND job_key = ?
                  AND status = 'running' AND ownership_token = ?
                """,
                bindings: [
                    .int(now),
                    .text(Self.memoryStage1JobKind),
                    .text(threadID.description),
                    .text(ownershipToken)
                ],
                database: database
            )

            guard sqlite3_changes(database) > 0 else {
                try Self.execute("COMMIT", bindings: [SQLiteBinding](), database: database)
                return false
            }

            let sourceUpdatedAt = try Self.optionalIntValue(
                query: """
                    SELECT input_watermark
                    FROM jobs
                    WHERE kind = ? AND job_key = ? AND ownership_token = ?
                    """,
                bindings: [
                    .text(Self.memoryStage1JobKind),
                    .text(threadID.description),
                    .text(ownershipToken)
                ],
                database: database
            ) ?? 0

            try Self.execute(
                "DELETE FROM stage1_outputs WHERE thread_id = ?",
                bindings: [.text(threadID.description)],
                database: database
            )

            if sqlite3_changes(database) > 0 {
                try Self.enqueueGlobalConsolidation(inputWatermark: sourceUpdatedAt, database: database)
            }

            try Self.execute("COMMIT", bindings: [SQLiteBinding](), database: database)
            return true
        } catch {
            try? Self.execute("ROLLBACK", bindings: [SQLiteBinding](), database: database)
            throw error
        }
    }

    public func markStage1JobFailed(
        threadID: ThreadId,
        ownershipToken: String,
        failureReason: String,
        retryDelaySeconds: Int64
    ) async throws -> Bool {
        let database = handle.database
        let now = Self.currentTimeSeconds()
        try Self.execute(
            """
            UPDATE jobs
            SET
                status = 'error',
                finished_at = ?,
                lease_until = NULL,
                retry_at = ?,
                retry_remaining = retry_remaining - 1,
                last_error = ?
            WHERE kind = ? AND job_key = ?
              AND status = 'running' AND ownership_token = ?
            """,
            bindings: [
                .int(now),
                .int(Self.saturatingAdd(now, max(retryDelaySeconds, 0))),
                .text(failureReason),
                .text(Self.memoryStage1JobKind),
                .text(threadID.description),
                .text(ownershipToken)
            ],
            database: database
        )
        return sqlite3_changes(database) > 0
    }

    public func enqueueGlobalConsolidation(inputWatermark: Int64) async throws {
        try Self.enqueueGlobalConsolidation(inputWatermark: inputWatermark, database: handle.database)
    }

    public func tryClaimGlobalPhase2Job(
        workerID: ThreadId,
        leaseSeconds: Int64
    ) async throws -> Phase2JobClaimOutcome {
        let database = handle.database
        let now = Self.currentTimeSeconds()
        let leaseUntil = Self.saturatingAdd(now, max(leaseSeconds, 0))
        let cooldownCutoff = Self.saturatingAdd(now, -Self.phase2SuccessCooldownSeconds)
        let ownershipToken = UUID().uuidString.lowercased()

        try Self.execute("BEGIN IMMEDIATE TRANSACTION", bindings: [SQLiteBinding](), database: database)
        do {
            let existingJob = try Self.phase2JobSnapshot(database: database)
            guard let existingJob else {
                try Self.execute(
                    """
                    INSERT INTO jobs (
                        kind,
                        job_key,
                        status,
                        worker_id,
                        ownership_token,
                        started_at,
                        finished_at,
                        lease_until,
                        retry_at,
                        retry_remaining,
                        last_error,
                        input_watermark,
                        last_success_watermark
                    ) VALUES (?, ?, 'running', ?, ?, ?, NULL, ?, NULL, ?, NULL, 0, 0)
                    """,
                    bindings: [
                        .text(Self.memoryConsolidateGlobalJobKind),
                        .text(Self.memoryConsolidationJobKey),
                        .text(workerID.description),
                        .text(ownershipToken),
                        .int(now),
                        .int(leaseUntil),
                        .int(Self.defaultRetryRemaining)
                    ],
                    database: database
                )
                let rowsChanged = sqlite3_changes(database)
                try Self.execute("COMMIT", bindings: [SQLiteBinding](), database: database)
                if rowsChanged == 0 {
                    return .skippedRunning
                }
                return .claimed(ownershipToken: ownershipToken, inputWatermark: 0)
            }

            let inputWatermark = existingJob.inputWatermark ?? 0
            if existingJob.retryAt.map({ $0 > now }) == true {
                try Self.execute("COMMIT", bindings: [SQLiteBinding](), database: database)
                return .skippedRetryUnavailable
            }
            if existingJob.status == "running", existingJob.leaseUntil.map({ $0 > now }) == true {
                try Self.execute("COMMIT", bindings: [SQLiteBinding](), database: database)
                return .skippedRunning
            }
            if existingJob.lastError == nil, existingJob.finishedAt.map({ $0 > cooldownCutoff }) == true {
                try Self.execute("COMMIT", bindings: [SQLiteBinding](), database: database)
                return .skippedCooldown
            }

            try Self.execute(
                """
                UPDATE jobs
                SET
                    status = 'running',
                    worker_id = ?,
                    ownership_token = ?,
                    started_at = ?,
                    finished_at = NULL,
                    lease_until = ?,
                    retry_at = NULL,
                    last_error = NULL
                WHERE kind = ? AND job_key = ?
                  AND (status != 'running' OR lease_until IS NULL OR lease_until <= ?)
                  AND (retry_at IS NULL OR retry_at <= ?)
                  AND (last_error IS NOT NULL OR finished_at IS NULL OR finished_at <= ?)
                """,
                bindings: [
                    .text(workerID.description),
                    .text(ownershipToken),
                    .int(now),
                    .int(leaseUntil),
                    .text(Self.memoryConsolidateGlobalJobKind),
                    .text(Self.memoryConsolidationJobKey),
                    .int(now),
                    .int(now),
                    .int(cooldownCutoff)
                ],
                database: database
            )
            let rowsChanged = sqlite3_changes(database)
            try Self.execute("COMMIT", bindings: [SQLiteBinding](), database: database)
            if rowsChanged == 0 {
                return .skippedRunning
            }
            return .claimed(ownershipToken: ownershipToken, inputWatermark: inputWatermark)
        } catch {
            try? Self.execute("ROLLBACK", bindings: [SQLiteBinding](), database: database)
            throw error
        }
    }

    public func heartbeatGlobalPhase2Job(
        ownershipToken: String,
        leaseSeconds: Int64
    ) async throws -> Bool {
        let database = handle.database
        let now = Self.currentTimeSeconds()
        try Self.execute(
            """
            UPDATE jobs
            SET lease_until = ?
            WHERE kind = ? AND job_key = ?
              AND status = 'running' AND ownership_token = ?
            """,
            bindings: [
                .int(Self.saturatingAdd(now, max(leaseSeconds, 0))),
                .text(Self.memoryConsolidateGlobalJobKind),
                .text(Self.memoryConsolidationJobKey),
                .text(ownershipToken)
            ],
            database: database
        )
        return sqlite3_changes(database) > 0
    }

    public func markGlobalPhase2JobSucceeded(
        ownershipToken: String,
        completedWatermark: Int64,
        selectedOutputs: [Stage1Output]
    ) async throws -> Bool {
        let database = handle.database
        let now = Self.currentTimeSeconds()
        try Self.execute("BEGIN TRANSACTION", bindings: [SQLiteBinding](), database: database)
        do {
            try Self.execute(
                """
                UPDATE jobs
                SET
                    status = 'done',
                    finished_at = ?,
                    lease_until = NULL,
                    last_error = NULL,
                    last_success_watermark = max(COALESCE(last_success_watermark, 0), ?)
                WHERE kind = ? AND job_key = ?
                  AND status = 'running' AND ownership_token = ?
                """,
                bindings: [
                    .int(now),
                    .int(completedWatermark),
                    .text(Self.memoryConsolidateGlobalJobKind),
                    .text(Self.memoryConsolidationJobKey),
                    .text(ownershipToken)
                ],
                database: database
            )

            guard sqlite3_changes(database) > 0 else {
                try Self.execute("COMMIT", bindings: [SQLiteBinding](), database: database)
                return false
            }

            try Self.execute(
                """
                UPDATE stage1_outputs
                SET
                    selected_for_phase2 = 0,
                    selected_for_phase2_source_updated_at = NULL
                WHERE selected_for_phase2 != 0 OR selected_for_phase2_source_updated_at IS NOT NULL
                """,
                bindings: [SQLiteBinding](),
                database: database
            )

            for output in selectedOutputs {
                let sourceUpdatedAt = Self.epochSeconds(output.sourceUpdatedAt)
                try Self.execute(
                    """
                    UPDATE stage1_outputs
                    SET
                        selected_for_phase2 = 1,
                        selected_for_phase2_source_updated_at = ?
                    WHERE thread_id = ? AND source_updated_at = ?
                    """,
                    bindings: [
                        .int(sourceUpdatedAt),
                        .text(output.threadID.description),
                        .int(sourceUpdatedAt)
                    ],
                    database: database
                )
            }

            try Self.execute("COMMIT", bindings: [SQLiteBinding](), database: database)
            return true
        } catch {
            try? Self.execute("ROLLBACK", bindings: [SQLiteBinding](), database: database)
            throw error
        }
    }

    public func markGlobalPhase2JobFailed(
        ownershipToken: String,
        failureReason: String,
        retryDelaySeconds: Int64
    ) async throws -> Bool {
        try markGlobalPhase2JobFailed(
            ownershipToken: ownershipToken,
            failureReason: failureReason,
            retryDelaySeconds: retryDelaySeconds,
            allowUnowned: false
        )
    }

    public func markGlobalPhase2JobFailedIfUnowned(
        ownershipToken: String,
        failureReason: String,
        retryDelaySeconds: Int64
    ) async throws -> Bool {
        try markGlobalPhase2JobFailed(
            ownershipToken: ownershipToken,
            failureReason: failureReason,
            retryDelaySeconds: retryDelaySeconds,
            allowUnowned: true
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

    private func upsertThread(_ metadata: ThreadMetadata, creationMemoryMode: String?) async throws {
        let updatedAtMilliseconds = allocateThreadUpdatedAt(metadata.updatedAt)
        try Self.execute(
            """
            INSERT INTO threads (
                id,
                rollout_path,
                created_at,
                updated_at,
                created_at_ms,
                updated_at_ms,
                source,
                thread_source,
                agent_nickname,
                agent_role,
                agent_path,
                model_provider,
                model,
                reasoning_effort,
                cwd,
                cli_version,
                title,
                sandbox_policy,
                approval_mode,
                tokens_used,
                first_user_message,
                archived,
                archived_at,
                git_sha,
                git_branch,
                git_origin_url,
                memory_mode
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                rollout_path = excluded.rollout_path,
                created_at = excluded.created_at,
                updated_at = excluded.updated_at,
                created_at_ms = excluded.created_at_ms,
                updated_at_ms = excluded.updated_at_ms,
                source = excluded.source,
                thread_source = excluded.thread_source,
                agent_nickname = excluded.agent_nickname,
                agent_role = excluded.agent_role,
                agent_path = excluded.agent_path,
                model_provider = excluded.model_provider,
                model = excluded.model,
                reasoning_effort = excluded.reasoning_effort,
                cwd = excluded.cwd,
                cli_version = excluded.cli_version,
                title = excluded.title,
                sandbox_policy = excluded.sandbox_policy,
                approval_mode = excluded.approval_mode,
                tokens_used = excluded.tokens_used,
                first_user_message = excluded.first_user_message,
                archived = excluded.archived,
                archived_at = excluded.archived_at,
                git_sha = COALESCE(threads.git_sha, excluded.git_sha),
                git_branch = COALESCE(threads.git_branch, excluded.git_branch),
                git_origin_url = COALESCE(threads.git_origin_url, excluded.git_origin_url)
            """,
            bindings: Self.threadMetadataBindings(
                metadata,
                updatedAtMilliseconds: updatedAtMilliseconds,
                memoryMode: creationMemoryMode ?? "enabled"
            ),
            database: handle.database
        )
        try await insertThreadSpawnEdgeFromSourceIfAbsent(
            childThreadID: metadata.id,
            source: metadata.source
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
            case let .optionalInt(number):
                if let number {
                    bindResult = sqlite3_bind_int64(statement, bindIndex, number)
                } else {
                    bindResult = sqlite3_bind_null(statement, bindIndex)
                }
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

    private static func addColumnIfMissing(
        table: String,
        column: String,
        definition: String,
        database: OpaquePointer
    ) throws {
        let columns = try withStatement(query: "PRAGMA table_info(\(table))", bindings: [], database: database) { statement in
            var columns: [String] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE {
                    return columns
                }
                guard result == SQLITE_ROW else {
                    throw sqliteError(database: database)
                }
                columns.append(try requiredTextColumn(statement, index: 1, columnName: "name"))
            }
        }
        guard !columns.contains(column) else {
            return
        }
        try execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition)", database: database)
    }

    private static func epochMilliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded(.down))
    }

    private static func currentTimeMilliseconds() -> Int64 {
        epochMilliseconds(Date())
    }

    private static func currentTimeSeconds() -> Int64 {
        epochSeconds(Date())
    }

    private static func epochSeconds(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970.rounded(.down))
    }

    private static func remoteControlAppServerClientNameKey(_ appServerClientName: String?) -> String {
        appServerClientName ?? ""
    }

    private static func remoteControlAppServerClientNameFromKey(_ appServerClientName: String) -> String? {
        appServerClientName.isEmpty ? nil : appServerClientName
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

    private static func applyRolloutItem(
        _ item: RolloutRecordItem,
        to metadata: inout ThreadMetadataDraft,
        defaultProvider: String
    ) {
        switch item {
        case let .sessionMeta(metaLine):
            applySessionMeta(metaLine, to: &metadata)
        case let .turnContext(turnContext):
            applyTurnContext(turnContext, to: &metadata)
        case let .eventMsg(event):
            applyEventMessage(event, to: &metadata)
        case .responseItem, .compacted:
            break
        }
        if metadata.modelProvider.isEmpty {
            metadata.modelProvider = defaultProvider
        }
    }

    private static func applySessionMeta(
        _ metaLine: SessionMetaLine,
        to metadata: inout ThreadMetadataDraft
    ) {
        guard metaLine.meta.id.description == metadata.id.description else {
            return
        }
        metadata.source = metaLine.meta.source.description
        metadata.threadSource = metaLine.meta.threadSource
        metadata.agentNickname = metaLine.meta.agentNickname
        metadata.agentRole = metaLine.meta.agentRole
        metadata.agentPath = metaLine.meta.agentPath
        if let modelProvider = metaLine.meta.modelProvider {
            metadata.modelProvider = modelProvider
        }
        if !metaLine.meta.cliVersion.isEmpty {
            metadata.cliVersion = metaLine.meta.cliVersion
        }
        if !metaLine.meta.cwd.isEmpty {
            metadata.cwd = metaLine.meta.cwd
        }
        if let git = metaLine.git {
            metadata.gitSHA = git.commitHash
            metadata.gitBranch = git.branch
            metadata.gitOriginURL = git.repositoryURL
        }
    }

    private static func applyTurnContext(
        _ turnContext: TurnContextItem,
        to metadata: inout ThreadMetadataDraft
    ) {
        if metadata.cwd.isEmpty {
            metadata.cwd = turnContext.cwd
        }
        metadata.model = turnContext.model
        metadata.reasoningEffort = turnContext.effort
        metadata.sandboxPolicy = persistedSandboxPolicy(turnContext.sandboxPolicy)
        metadata.approvalMode = turnContext.approvalPolicy.rawValue
    }

    private static func applyEventMessage(
        _ event: EventMessage,
        to metadata: inout ThreadMetadataDraft
    ) {
        switch event {
        case let .tokenCount(tokenCount):
            if let info = tokenCount.info {
                metadata.tokensUsed = max(info.totalTokenUsage.totalTokens, 0)
            }
        case let .userMessage(userMessage):
            if metadata.firstUserMessage == nil {
                metadata.firstUserMessage = userMessagePreview(userMessage)
            }
            if metadata.title.isEmpty {
                let title = strippedUserMessagePrefix(userMessage.message)
                if !title.isEmpty {
                    metadata.title = title
                }
            }
        default:
            break
        }
    }

    private static func extractMemoryMode(from items: [RolloutRecordItem]) -> String? {
        for item in items.reversed() {
            guard case let .sessionMeta(metaLine) = item,
                  let memoryMode = metaLine.meta.memoryMode
            else {
                continue
            }
            return memoryMode
        }
        return nil
    }

    private static func extractDynamicTools(from items: [RolloutRecordItem]) -> [DynamicToolSpec]?? {
        for item in items {
            guard case let .sessionMeta(metaLine) = item else {
                continue
            }
            return metaLine.meta.dynamicTools
        }
        return nil
    }

    private static func userMessagePreview(_ userMessage: UserMessageEvent) -> String? {
        let message = strippedUserMessagePrefix(userMessage.message)
        if !message.isEmpty {
            return message
        }
        if userMessage.images?.isEmpty == false || !userMessage.localImages.isEmpty {
            return "[Image]"
        }
        return nil
    }

    private static func strippedUserMessagePrefix(_ text: String) -> String {
        let prefix = "## My request for Codex:"
        if let range = text.range(of: prefix) {
            return String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    fileprivate static func persistedSandboxPolicy(_ policy: SandboxPolicy) -> String {
        switch policy {
        case .dangerFullAccess:
            return "danger-full-access"
        case .readOnly, .readOnlyWithNetworkAccess:
            return "read-only"
        case .externalSandbox:
            return "external-sandbox"
        case .workspaceWrite:
            return "workspace-write"
        }
    }

    private static func threadMetadataBindings(
        _ metadata: ThreadMetadata,
        updatedAtMilliseconds: Int64,
        memoryMode: String
    ) -> [SQLiteBinding] {
        [
            .text(metadata.id.description),
            .text(metadata.rolloutPath),
            .int(epochSeconds(metadata.createdAt)),
            .int(epochSeconds(fromMilliseconds: updatedAtMilliseconds)),
            .int(epochMilliseconds(metadata.createdAt)),
            .int(updatedAtMilliseconds),
            .text(metadata.source),
            .optionalText(metadata.threadSource?.rawValue),
            .optionalText(metadata.agentNickname),
            .optionalText(metadata.agentRole),
            .optionalText(metadata.agentPath),
            .text(metadata.modelProvider),
            .optionalText(metadata.model),
            .optionalText(metadata.reasoningEffort?.rawValue),
            .text(metadata.cwd),
            .text(metadata.cliVersion),
            .text(metadata.title),
            .text(metadata.sandboxPolicy),
            .text(metadata.approvalMode),
            .int(metadata.tokensUsed),
            .text(metadata.firstUserMessage ?? ""),
            .bool(metadata.archivedAt != nil),
            .optionalInt(metadata.archivedAt.map(epochSeconds)),
            .optionalText(metadata.gitSHA),
            .optionalText(metadata.gitBranch),
            .optionalText(metadata.gitOriginURL),
            .text(memoryMode),
        ]
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

    private static func threadGoal(from statement: OpaquePointer) throws -> ThreadGoal {
        let databaseStatus = try requiredTextColumn(statement, index: 2, columnName: "status")
        guard let status = apiStatus(databaseStatus) else {
            throw AgentGraphStoreError.internal(message: "unknown thread goal status: \(databaseStatus)")
        }
        return ThreadGoal(
            threadID: try ThreadId(string: try requiredTextColumn(statement, index: 0, columnName: "thread_id")),
            objective: try requiredTextColumn(statement, index: 1, columnName: "objective"),
            status: status,
            tokenBudget: optionalIntColumn(statement, index: 3),
            tokensUsed: sqlite3_column_int64(statement, 4),
            timeUsedSeconds: sqlite3_column_int64(statement, 5),
            createdAt: epochSeconds(fromMilliseconds: sqlite3_column_int64(statement, 6)),
            updatedAt: epochSeconds(fromMilliseconds: sqlite3_column_int64(statement, 7))
        )
    }

    private static func databaseStatus(_ status: ThreadGoalStatus) -> String {
        switch status {
        case .active:
            return "active"
        case .paused:
            return "paused"
        case .budgetLimited:
            return "budget_limited"
        case .complete:
            return "complete"
        }
    }

    private static func apiStatus(_ status: String) -> ThreadGoalStatus? {
        switch status {
        case "active":
            return .active
        case "paused":
            return .paused
        case "budget_limited":
            return .budgetLimited
        case "complete":
            return .complete
        default:
            return nil
        }
    }

    private static func statusAfterBudgetLimit(
        _ status: ThreadGoalStatus,
        tokensUsed: Int64,
        tokenBudget: Int64?
    ) -> ThreadGoalStatus {
        if status == .active, let tokenBudget, tokensUsed >= tokenBudget {
            return .budgetLimited
        }
        return status
    }

    private static func epochMillisecondsDate(_ value: Int64) -> Date {
        let minimumEpochMilliseconds: Int64 = 1_577_836_800_000
        let milliseconds = value < minimumEpochMilliseconds ? saturatingMultiply(value, 1_000) : value
        return Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
    }

    private static func epochSecondsDate(_ seconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(seconds))
    }

    private static func stage1Output(_ statement: OpaquePointer) throws -> Stage1Output {
        let threadIDValue = try requiredTextColumn(statement, index: 0, columnName: "thread_id")
        let threadID = try ThreadId(string: threadIDValue)
        return Stage1Output(
            threadID: threadID,
            rolloutPath: try requiredTextColumn(statement, index: 1, columnName: "rollout_path"),
            sourceUpdatedAt: epochSecondsDate(sqlite3_column_int64(statement, 2)),
            rawMemory: try requiredTextColumn(statement, index: 3, columnName: "raw_memory"),
            rolloutSummary: try requiredTextColumn(statement, index: 4, columnName: "rollout_summary"),
            rolloutSlug: optionalTextColumn(statement, index: 5),
            cwd: try requiredTextColumn(statement, index: 7, columnName: "cwd"),
            gitBranch: optionalTextColumn(statement, index: 8),
            generatedAt: epochSecondsDate(sqlite3_column_int64(statement, 6))
        )
    }

    private struct Stage1JobSnapshot {
        var status: String
        var leaseUntil: Int64?
        var retryAt: Int64?
        var retryRemaining: Int64
    }

    private static func stage1JobSnapshot(
        threadID: ThreadId,
        database: OpaquePointer
    ) throws -> Stage1JobSnapshot? {
        try withStatement(
            query: """
                SELECT status, lease_until, retry_at, retry_remaining
                FROM jobs
                WHERE kind = ? AND job_key = ?
                """,
            bindings: [
                .text(memoryStage1JobKind),
                .text(threadID.description)
            ],
            database: database
        ) { statement in
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return nil
            }
            guard result == SQLITE_ROW else {
                throw sqliteError(database: database)
            }
            return Stage1JobSnapshot(
                status: try requiredTextColumn(statement, index: 0, columnName: "status"),
                leaseUntil: optionalIntColumn(statement, index: 1),
                retryAt: optionalIntColumn(statement, index: 2),
                retryRemaining: sqlite3_column_int64(statement, 3)
            )
        }
    }

    private struct Phase2JobSnapshot {
        var status: String
        var leaseUntil: Int64?
        var retryAt: Int64?
        var inputWatermark: Int64?
        var finishedAt: Int64?
        var lastError: String?
    }

    private static func phase2JobSnapshot(database: OpaquePointer) throws -> Phase2JobSnapshot? {
        try withStatement(
            query: """
                SELECT status, lease_until, retry_at, input_watermark, finished_at, last_error
                FROM jobs
                WHERE kind = ? AND job_key = ?
                """,
            bindings: [
                .text(memoryConsolidateGlobalJobKind),
                .text(memoryConsolidationJobKey)
            ],
            database: database
        ) { statement in
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return nil
            }
            guard result == SQLITE_ROW else {
                throw sqliteError(database: database)
            }
            return Phase2JobSnapshot(
                status: try requiredTextColumn(statement, index: 0, columnName: "status"),
                leaseUntil: optionalIntColumn(statement, index: 1),
                retryAt: optionalIntColumn(statement, index: 2),
                inputWatermark: optionalIntColumn(statement, index: 3),
                finishedAt: optionalIntColumn(statement, index: 4),
                lastError: optionalTextColumn(statement, index: 5)
            )
        }
    }

    private func markGlobalPhase2JobFailed(
        ownershipToken: String,
        failureReason: String,
        retryDelaySeconds: Int64,
        allowUnowned: Bool
    ) throws -> Bool {
        let database = handle.database
        let now = Self.currentTimeSeconds()
        let ownershipPredicate = allowUnowned
            ? "AND (ownership_token = ? OR ownership_token IS NULL)"
            : "AND ownership_token = ?"
        try Self.execute(
            """
            UPDATE jobs
            SET
                status = 'error',
                finished_at = ?,
                lease_until = NULL,
                retry_at = ?,
                retry_remaining = max(retry_remaining - 1, 0),
                last_error = ?
            WHERE kind = ? AND job_key = ?
              AND status = 'running'
              \(ownershipPredicate)
            """,
            bindings: [
                .int(now),
                .int(Self.saturatingAdd(now, max(retryDelaySeconds, 0))),
                .text(failureReason),
                .text(Self.memoryConsolidateGlobalJobKind),
                .text(Self.memoryConsolidationJobKey),
                .text(ownershipToken)
            ],
            database: database
        )
        return sqlite3_changes(database) > 0
    }

    private static func optionalIntValue(
        query: String,
        bindings: [SQLiteBinding],
        database: OpaquePointer
    ) throws -> Int64? {
        try withStatement(query: query, bindings: bindings, database: database) { statement in
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return nil
            }
            guard result == SQLITE_ROW else {
                throw sqliteError(database: database)
            }
            return optionalIntColumn(statement, index: 0)
        }
    }

    private static func enqueueGlobalConsolidation(inputWatermark: Int64, database: OpaquePointer) throws {
        try execute(
            """
            INSERT INTO jobs (
                kind,
                job_key,
                status,
                worker_id,
                ownership_token,
                started_at,
                finished_at,
                lease_until,
                retry_at,
                retry_remaining,
                last_error,
                input_watermark,
                last_success_watermark
            ) VALUES (?, ?, 'pending', NULL, NULL, NULL, NULL, NULL, NULL, ?, NULL, ?, 0)
            ON CONFLICT(kind, job_key) DO UPDATE SET
                status = CASE
                    WHEN jobs.status = 'running' THEN 'running'
                    ELSE 'pending'
                END,
                retry_at = CASE
                    WHEN jobs.status = 'running' THEN jobs.retry_at
                    ELSE NULL
                END,
                retry_remaining = max(jobs.retry_remaining, excluded.retry_remaining),
                input_watermark = CASE
                    WHEN excluded.input_watermark > COALESCE(jobs.input_watermark, 0)
                        THEN excluded.input_watermark
                    ELSE COALESCE(jobs.input_watermark, 0) + 1
                END
            """,
            bindings: [
                .text(memoryConsolidateGlobalJobKind),
                .text(memoryConsolidationJobKey),
                .int(defaultRetryRemaining),
                .int(inputWatermark)
            ],
            database: database
        )
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

public struct ThreadMetadataBuilder: Equatable, Sendable {
    public var id: ThreadId
    public var rolloutPath: URL
    public var createdAt: Date
    public var updatedAt: Date?
    public var source: SessionSource
    public var threadSource: ThreadSource?
    public var agentNickname: String?
    public var agentRole: String?
    public var agentPath: String?
    public var modelProvider: String?
    public var cwd: String
    public var cliVersion: String?
    public var sandboxPolicy: SandboxPolicy
    public var approvalMode: AskForApproval
    public var archivedAt: Date?
    public var gitSHA: String?
    public var gitBranch: String?
    public var gitOriginURL: String?

    public init(
        id: ThreadId,
        rolloutPath: URL,
        createdAt: Date,
        source: SessionSource
    ) {
        self.id = id
        self.rolloutPath = rolloutPath
        self.createdAt = createdAt
        self.updatedAt = nil
        self.source = source
        self.threadSource = nil
        self.agentNickname = nil
        self.agentRole = nil
        self.agentPath = nil
        self.modelProvider = nil
        self.cwd = ""
        self.cliVersion = nil
        self.sandboxPolicy = .newReadOnlyPolicy()
        self.approvalMode = .onRequest
        self.archivedAt = nil
        self.gitSHA = nil
        self.gitBranch = nil
        self.gitOriginURL = nil
    }

    public func build(defaultProvider: String) -> ThreadMetadata {
        ThreadMetadata(
            id: id,
            rolloutPath: rolloutPath.path,
            createdAt: createdAt,
            updatedAt: updatedAt ?? createdAt,
            source: source.description,
            threadSource: threadSource,
            agentNickname: agentNickname,
            agentRole: agentRole,
            agentPath: agentPath ?? source.agentPath?.description,
            modelProvider: modelProvider ?? defaultProvider,
            model: nil,
            reasoningEffort: nil,
            cwd: cwd,
            cliVersion: cliVersion ?? "",
            title: "",
            sandboxPolicy: SQLiteAgentGraphStore.persistedSandboxPolicy(sandboxPolicy),
            approvalMode: approvalMode.rawValue,
            tokensUsed: 0,
            firstUserMessage: nil,
            archivedAt: archivedAt,
            gitSHA: gitSHA,
            gitBranch: gitBranch,
            gitOriginURL: gitOriginURL
        )
    }
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

private struct ThreadMetadataDraft {
    var id: ThreadId
    var rolloutPath: String
    var createdAt: Date
    var updatedAt: Date
    var source: String
    var threadSource: ThreadSource?
    var agentNickname: String?
    var agentRole: String?
    var agentPath: String?
    var modelProvider: String
    var model: String?
    var reasoningEffort: ReasoningEffort?
    var cwd: String
    var cliVersion: String
    var title: String
    var sandboxPolicy: String
    var approvalMode: String
    var tokensUsed: Int64
    var firstUserMessage: String?
    var archivedAt: Date?
    var gitSHA: String?
    var gitBranch: String?
    var gitOriginURL: String?

    init(metadata: ThreadMetadata) {
        self.id = metadata.id
        self.rolloutPath = metadata.rolloutPath
        self.createdAt = metadata.createdAt
        self.updatedAt = metadata.updatedAt
        self.source = metadata.source
        self.threadSource = metadata.threadSource
        self.agentNickname = metadata.agentNickname
        self.agentRole = metadata.agentRole
        self.agentPath = metadata.agentPath
        self.modelProvider = metadata.modelProvider
        self.model = metadata.model
        self.reasoningEffort = metadata.reasoningEffort
        self.cwd = metadata.cwd
        self.cliVersion = metadata.cliVersion
        self.title = metadata.title
        self.sandboxPolicy = metadata.sandboxPolicy
        self.approvalMode = metadata.approvalMode
        self.tokensUsed = metadata.tokensUsed
        self.firstUserMessage = metadata.firstUserMessage
        self.archivedAt = metadata.archivedAt
        self.gitSHA = metadata.gitSHA
        self.gitBranch = metadata.gitBranch
        self.gitOriginURL = metadata.gitOriginURL
    }

    var metadata: ThreadMetadata {
        ThreadMetadata(
            id: id,
            rolloutPath: rolloutPath,
            createdAt: createdAt,
            updatedAt: updatedAt,
            source: source,
            threadSource: threadSource,
            agentNickname: agentNickname,
            agentRole: agentRole,
            agentPath: agentPath,
            modelProvider: modelProvider,
            model: model,
            reasoningEffort: reasoningEffort,
            cwd: cwd,
            cliVersion: cliVersion,
            title: title,
            sandboxPolicy: sandboxPolicy,
            approvalMode: approvalMode,
            tokensUsed: tokensUsed,
            firstUserMessage: firstUserMessage,
            archivedAt: archivedAt,
            gitSHA: gitSHA,
            gitBranch: gitBranch,
            gitOriginURL: gitOriginURL
        )
    }

    mutating func preferExistingGitInfo(_ existing: ThreadMetadata) {
        if let gitSHA = existing.gitSHA {
            self.gitSHA = gitSHA
        }
        if let gitBranch = existing.gitBranch {
            self.gitBranch = gitBranch
        }
        if let gitOriginURL = existing.gitOriginURL {
            self.gitOriginURL = gitOriginURL
        }
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

public enum ThreadGoalTokenBudgetUpdate: Equatable, Sendable {
    case preserve
    case set(Int64?)
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

public extension ThreadMetadata {
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
    case optionalInt(Int64?)
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
