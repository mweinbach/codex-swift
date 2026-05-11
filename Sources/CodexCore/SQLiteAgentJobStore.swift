import Foundation
import SQLite3

public enum AgentJobStatus: String, Equatable, Sendable {
    case pending
    case running
    case completed
    case failed
    case cancelled

    public var isFinal: Bool {
        switch self {
        case .pending, .running:
            false
        case .completed, .failed, .cancelled:
            true
        }
    }
}

public enum AgentJobItemStatus: String, Equatable, Sendable {
    case pending
    case running
    case completed
    case failed
}

public struct AgentJob: Equatable, Sendable {
    public var id: String
    public var name: String
    public var status: AgentJobStatus
    public var instruction: String
    public var autoExport: Bool
    public var maxRuntimeSeconds: UInt64?
    public var outputSchemaJSON: JSONValue?
    public var inputHeaders: [String]
    public var inputCSVPath: String
    public var outputCSVPath: String
    public var createdAt: Date
    public var updatedAt: Date
    public var startedAt: Date?
    public var completedAt: Date?
    public var lastError: String?
}

public struct AgentJobItem: Equatable, Sendable {
    public var jobID: String
    public var itemID: String
    public var rowIndex: Int64
    public var sourceID: String?
    public var rowJSON: JSONValue
    public var status: AgentJobItemStatus
    public var assignedThreadID: String?
    public var attemptCount: Int64
    public var resultJSON: JSONValue?
    public var lastError: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var reportedAt: Date?
}

public struct AgentJobProgress: Equatable, Sendable {
    public var pending: Int64
    public var running: Int64
    public var completed: Int64
    public var failed: Int64

    public init(pending: Int64, running: Int64, completed: Int64, failed: Int64) {
        self.pending = pending
        self.running = running
        self.completed = completed
        self.failed = failed
    }
}

public struct AgentJobCreateParams: Equatable, Sendable {
    public var id: String
    public var name: String
    public var instruction: String
    public var outputSchemaJSON: JSONValue?
    public var inputHeaders: [String]
    public var inputCSVPath: String
    public var outputCSVPath: String
    public var autoExport: Bool
    public var maxRuntimeSeconds: UInt64?

    public init(
        id: String,
        name: String,
        instruction: String,
        outputSchemaJSON: JSONValue?,
        inputHeaders: [String],
        inputCSVPath: String,
        outputCSVPath: String,
        autoExport: Bool,
        maxRuntimeSeconds: UInt64?
    ) {
        self.id = id
        self.name = name
        self.instruction = instruction
        self.outputSchemaJSON = outputSchemaJSON
        self.inputHeaders = inputHeaders
        self.inputCSVPath = inputCSVPath
        self.outputCSVPath = outputCSVPath
        self.autoExport = autoExport
        self.maxRuntimeSeconds = maxRuntimeSeconds
    }
}

public struct AgentJobItemCreateParams: Equatable, Sendable {
    public var itemID: String
    public var rowIndex: Int64
    public var sourceID: String?
    public var rowJSON: JSONValue

    public init(itemID: String, rowIndex: Int64, sourceID: String?, rowJSON: JSONValue) {
        self.itemID = itemID
        self.rowIndex = rowIndex
        self.sourceID = sourceID
        self.rowJSON = rowJSON
    }
}

public enum SQLiteAgentJobStoreError: Error, Equatable, Sendable {
    case `internal`(message: String)
}

/// SQLite-backed agent-job persistence matching Rust's `state/runtime/agent_jobs.rs`.
public actor SQLiteAgentJobStore {
    private let handle: AgentJobSQLiteDatabaseHandle

    public init(databaseURL: URL) throws {
        var openedDatabase: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(databaseURL.path, &openedDatabase, flags, nil)
        guard result == SQLITE_OK, let openedDatabase else {
            let message = openedDatabase.map(Self.errorMessage(database:)) ?? "unable to open sqlite database"
            if let openedDatabase {
                sqlite3_close(openedDatabase)
            }
            throw SQLiteAgentJobStoreError.internal(message: message)
        }

        do {
            try Self.execute("PRAGMA foreign_keys = ON", database: openedDatabase)
            try Self.execute(
                """
                CREATE TABLE IF NOT EXISTS agent_jobs (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    status TEXT NOT NULL,
                    instruction TEXT NOT NULL,
                    output_schema_json TEXT,
                    input_headers_json TEXT NOT NULL,
                    input_csv_path TEXT NOT NULL,
                    output_csv_path TEXT NOT NULL,
                    auto_export INTEGER NOT NULL DEFAULT 1,
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    started_at INTEGER,
                    completed_at INTEGER,
                    last_error TEXT,
                    max_runtime_seconds INTEGER
                )
                """,
                database: openedDatabase
            )
            try Self.execute(
                """
                CREATE TABLE IF NOT EXISTS agent_job_items (
                    job_id TEXT NOT NULL,
                    item_id TEXT NOT NULL,
                    row_index INTEGER NOT NULL,
                    source_id TEXT,
                    row_json TEXT NOT NULL,
                    status TEXT NOT NULL,
                    assigned_thread_id TEXT,
                    attempt_count INTEGER NOT NULL DEFAULT 0,
                    result_json TEXT,
                    last_error TEXT,
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    completed_at INTEGER,
                    reported_at INTEGER,
                    PRIMARY KEY (job_id, item_id),
                    FOREIGN KEY(job_id) REFERENCES agent_jobs(id) ON DELETE CASCADE
                )
                """,
                database: openedDatabase
            )
            try Self.execute(
                """
                CREATE INDEX IF NOT EXISTS idx_agent_jobs_status
                    ON agent_jobs(status, updated_at DESC)
                """,
                database: openedDatabase
            )
            try Self.execute(
                """
                CREATE INDEX IF NOT EXISTS idx_agent_job_items_status
                    ON agent_job_items(job_id, status, row_index ASC)
                """,
                database: openedDatabase
            )
        } catch {
            sqlite3_close(openedDatabase)
            throw error
        }

        handle = AgentJobSQLiteDatabaseHandle(database: openedDatabase)
    }

    public func createAgentJob(
        params: AgentJobCreateParams,
        items: [AgentJobItemCreateParams]
    ) throws -> AgentJob {
        let database = handle.database
        let now = Self.currentTimestamp()
        let maxRuntime = try Self.bindableMaxRuntimeSeconds(params.maxRuntimeSeconds)
        let outputSchemaJSON = try params.outputSchemaJSON.map(Self.encodeJSONString)
        let inputHeadersJSON = try Self.encodeJSONString(params.inputHeaders)

        try Self.execute("BEGIN IMMEDIATE TRANSACTION", database: database)
        do {
            try Self.execute(
                """
                INSERT INTO agent_jobs (
                    id, name, status, instruction, output_schema_json, input_headers_json,
                    input_csv_path, output_csv_path, auto_export, created_at, updated_at,
                    started_at, completed_at, last_error, max_runtime_seconds
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL, ?)
                """,
                bindings: [
                    .text(params.id),
                    .text(params.name),
                    .text(AgentJobStatus.pending.rawValue),
                    .text(params.instruction),
                    .optionalText(outputSchemaJSON),
                    .text(inputHeadersJSON),
                    .text(params.inputCSVPath),
                    .text(params.outputCSVPath),
                    .bool(params.autoExport),
                    .int(now),
                    .int(now),
                    .optionalInt(maxRuntime),
                ],
                database: database
            )

            for item in items {
                try Self.execute(
                    """
                    INSERT INTO agent_job_items (
                        job_id, item_id, row_index, source_id, row_json, status,
                        assigned_thread_id, attempt_count, result_json, last_error,
                        created_at, updated_at, completed_at, reported_at
                    ) VALUES (?, ?, ?, ?, ?, ?, NULL, 0, NULL, NULL, ?, ?, NULL, NULL)
                    """,
                    bindings: [
                        .text(params.id),
                        .text(item.itemID),
                        .int(item.rowIndex),
                        .optionalText(item.sourceID),
                        .text(try Self.encodeJSONString(item.rowJSON)),
                        .text(AgentJobItemStatus.pending.rawValue),
                        .int(now),
                        .int(now),
                    ],
                    database: database
                )
            }

            try Self.execute("COMMIT", database: database)
        } catch {
            try? Self.execute("ROLLBACK", database: database)
            throw error
        }

        guard let job = try getAgentJob(params.id) else {
            throw SQLiteAgentJobStoreError.internal(message: "agent job insert did not return a row")
        }
        return job
    }

    public func getAgentJob(_ jobID: String) throws -> AgentJob? {
        try queryOne(
            """
            SELECT id, name, status, instruction, output_schema_json, input_headers_json,
                   input_csv_path, output_csv_path, auto_export, created_at, updated_at,
                   started_at, completed_at, last_error, max_runtime_seconds
            FROM agent_jobs
            WHERE id = ?
            """,
            bindings: [.text(jobID)],
            map: Self.readAgentJob
        )
    }

    public func listAgentJobItems(
        jobID: String,
        status: AgentJobItemStatus? = nil,
        limit: Int? = nil
    ) throws -> [AgentJobItem] {
        var bindings: [AgentJobSQLiteBinding] = [.text(jobID)]
        var query = """
            SELECT job_id, item_id, row_index, source_id, row_json, status,
                   assigned_thread_id, attempt_count, result_json, last_error,
                   created_at, updated_at, completed_at, reported_at
            FROM agent_job_items
            WHERE job_id = ?
            """
        if let status {
            query += " AND status = ?"
            bindings.append(.text(status.rawValue))
        }
        query += " ORDER BY row_index ASC"
        if let limit {
            query += " LIMIT ?"
            bindings.append(.int(Int64(limit)))
        }
        return try queryAll(query, bindings: bindings, map: Self.readAgentJobItem)
    }

    public func getAgentJobItem(jobID: String, itemID: String) throws -> AgentJobItem? {
        try queryOne(
            """
            SELECT job_id, item_id, row_index, source_id, row_json, status,
                   assigned_thread_id, attempt_count, result_json, last_error,
                   created_at, updated_at, completed_at, reported_at
            FROM agent_job_items
            WHERE job_id = ? AND item_id = ?
            """,
            bindings: [.text(jobID), .text(itemID)],
            map: Self.readAgentJobItem
        )
    }

    public func markAgentJobRunning(_ jobID: String) throws {
        let now = Self.currentTimestamp()
        try Self.execute(
            """
            UPDATE agent_jobs
            SET status = ?, started_at = ?, updated_at = ?
            WHERE id = ? AND status = ?
            """,
            bindings: [
                .text(AgentJobStatus.running.rawValue),
                .int(now),
                .int(now),
                .text(jobID),
                .text(AgentJobStatus.pending.rawValue),
            ],
            database: handle.database
        )
    }

    public func markAgentJobCompleted(_ jobID: String) throws {
        let now = Self.currentTimestamp()
        try Self.execute(
            """
            UPDATE agent_jobs
            SET status = ?, completed_at = ?, updated_at = ?
            WHERE id = ?
            """,
            bindings: [.text(AgentJobStatus.completed.rawValue), .int(now), .int(now), .text(jobID)],
            database: handle.database
        )
    }

    public func markAgentJobFailed(_ jobID: String, errorMessage: String) throws {
        let now = Self.currentTimestamp()
        try Self.execute(
            """
            UPDATE agent_jobs
            SET status = ?, completed_at = ?, updated_at = ?, last_error = ?
            WHERE id = ?
            """,
            bindings: [
                .text(AgentJobStatus.failed.rawValue),
                .int(now),
                .int(now),
                .text(errorMessage),
                .text(jobID),
            ],
            database: handle.database
        )
    }

    public func markAgentJobCancelled(_ jobID: String, errorMessage: String) throws -> Bool {
        let now = Self.currentTimestamp()
        try Self.execute(
            """
            UPDATE agent_jobs
            SET status = ?, completed_at = ?, updated_at = ?, last_error = ?
            WHERE id = ? AND status IN (?, ?)
            """,
            bindings: [
                .text(AgentJobStatus.cancelled.rawValue),
                .int(now),
                .int(now),
                .text(errorMessage),
                .text(jobID),
                .text(AgentJobStatus.pending.rawValue),
                .text(AgentJobStatus.running.rawValue),
            ],
            database: handle.database
        )
        return sqlite3_changes(handle.database) > 0
    }

    public func isAgentJobCancelled(_ jobID: String) throws -> Bool {
        try queryOne(
            """
            SELECT status
            FROM agent_jobs
            WHERE id = ?
            """,
            bindings: [.text(jobID)]
        ) { statement in
            Self.columnText(statement, 0) == AgentJobStatus.cancelled.rawValue
        } ?? false
    }

    public func markAgentJobItemRunning(jobID: String, itemID: String) throws -> Bool {
        let now = Self.currentTimestamp()
        try Self.execute(
            """
            UPDATE agent_job_items
            SET status = ?, attempt_count = attempt_count + 1, updated_at = ?
            WHERE job_id = ? AND item_id = ? AND status = ?
            """,
            bindings: [
                .text(AgentJobItemStatus.running.rawValue),
                .int(now),
                .text(jobID),
                .text(itemID),
                .text(AgentJobItemStatus.pending.rawValue),
            ],
            database: handle.database
        )
        return sqlite3_changes(handle.database) > 0
    }

    public func markAgentJobItemRunningWithThread(
        jobID: String,
        itemID: String,
        threadID: String
    ) throws -> Bool {
        let now = Self.currentTimestamp()
        try Self.execute(
            """
            UPDATE agent_job_items
            SET status = ?, assigned_thread_id = ?, attempt_count = attempt_count + 1, updated_at = ?
            WHERE job_id = ? AND item_id = ? AND status = ?
            """,
            bindings: [
                .text(AgentJobItemStatus.running.rawValue),
                .text(threadID),
                .int(now),
                .text(jobID),
                .text(itemID),
                .text(AgentJobItemStatus.pending.rawValue),
            ],
            database: handle.database
        )
        return sqlite3_changes(handle.database) > 0
    }

    public func markAgentJobItemPending(
        jobID: String,
        itemID: String,
        errorMessage: String
    ) throws -> Bool {
        let now = Self.currentTimestamp()
        try Self.execute(
            """
            UPDATE agent_job_items
            SET status = ?, assigned_thread_id = NULL, last_error = ?, updated_at = ?
            WHERE job_id = ? AND item_id = ? AND status = ?
            """,
            bindings: [
                .text(AgentJobItemStatus.pending.rawValue),
                .text(errorMessage),
                .int(now),
                .text(jobID),
                .text(itemID),
                .text(AgentJobItemStatus.running.rawValue),
            ],
            database: handle.database
        )
        return sqlite3_changes(handle.database) > 0
    }

    public func setAgentJobItemThread(jobID: String, itemID: String, threadID: String) throws -> Bool {
        let now = Self.currentTimestamp()
        try Self.execute(
            """
            UPDATE agent_job_items
            SET assigned_thread_id = ?, updated_at = ?
            WHERE job_id = ? AND item_id = ? AND status = ?
            """,
            bindings: [
                .text(threadID),
                .int(now),
                .text(jobID),
                .text(itemID),
                .text(AgentJobItemStatus.running.rawValue),
            ],
            database: handle.database
        )
        return sqlite3_changes(handle.database) > 0
    }

    public func reportAgentJobItemResult(
        jobID: String,
        itemID: String,
        reportingThreadID: String,
        resultJSON: JSONValue
    ) throws -> Bool {
        let now = Self.currentTimestamp()
        try Self.execute(
            """
            UPDATE agent_job_items
            SET status = ?, result_json = ?, reported_at = ?, completed_at = ?,
                updated_at = ?, last_error = NULL, assigned_thread_id = NULL
            WHERE job_id = ? AND item_id = ? AND status = ? AND assigned_thread_id = ?
            """,
            bindings: [
                .text(AgentJobItemStatus.completed.rawValue),
                .text(try Self.encodeJSONString(resultJSON)),
                .int(now),
                .int(now),
                .int(now),
                .text(jobID),
                .text(itemID),
                .text(AgentJobItemStatus.running.rawValue),
                .text(reportingThreadID),
            ],
            database: handle.database
        )
        return sqlite3_changes(handle.database) > 0
    }

    public func markAgentJobItemCompleted(jobID: String, itemID: String) throws -> Bool {
        let now = Self.currentTimestamp()
        try Self.execute(
            """
            UPDATE agent_job_items
            SET status = ?, completed_at = ?, updated_at = ?, assigned_thread_id = NULL
            WHERE job_id = ? AND item_id = ? AND status = ? AND result_json IS NOT NULL
            """,
            bindings: [
                .text(AgentJobItemStatus.completed.rawValue),
                .int(now),
                .int(now),
                .text(jobID),
                .text(itemID),
                .text(AgentJobItemStatus.running.rawValue),
            ],
            database: handle.database
        )
        return sqlite3_changes(handle.database) > 0
    }

    public func markAgentJobItemFailed(
        jobID: String,
        itemID: String,
        errorMessage: String
    ) throws -> Bool {
        let now = Self.currentTimestamp()
        try Self.execute(
            """
            UPDATE agent_job_items
            SET status = ?, completed_at = ?, updated_at = ?, last_error = ?, assigned_thread_id = NULL
            WHERE job_id = ? AND item_id = ? AND status = ?
            """,
            bindings: [
                .text(AgentJobItemStatus.failed.rawValue),
                .int(now),
                .int(now),
                .text(errorMessage),
                .text(jobID),
                .text(itemID),
                .text(AgentJobItemStatus.running.rawValue),
            ],
            database: handle.database
        )
        return sqlite3_changes(handle.database) > 0
    }

    public func getAgentJobProgress(_ jobID: String) throws -> AgentJobProgress {
        try queryOne(
            """
            SELECT
                COALESCE(SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END), 0),
                COALESCE(SUM(CASE WHEN status = 'running' THEN 1 ELSE 0 END), 0),
                COALESCE(SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END), 0),
                COALESCE(SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END), 0)
            FROM agent_job_items
            WHERE job_id = ?
            """,
            bindings: [.text(jobID)]
        ) { statement in
            AgentJobProgress(
                pending: sqlite3_column_int64(statement, 0),
                running: sqlite3_column_int64(statement, 1),
                completed: sqlite3_column_int64(statement, 2),
                failed: sqlite3_column_int64(statement, 3)
            )
        } ?? AgentJobProgress(pending: 0, running: 0, completed: 0, failed: 0)
    }

    private func queryAll<T>(
        _ query: String,
        bindings: [AgentJobSQLiteBinding],
        map: (OpaquePointer) throws -> T
    ) throws -> [T] {
        let statement = try Self.prepare(query, bindings: bindings, database: handle.database)
        defer { sqlite3_finalize(statement) }
        var values: [T] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                values.append(try map(statement))
            } else if result == SQLITE_DONE {
                return values
            } else {
                throw SQLiteAgentJobStoreError.internal(message: Self.errorMessage(database: handle.database))
            }
        }
    }

    private func queryOne<T>(
        _ query: String,
        bindings: [AgentJobSQLiteBinding],
        map: (OpaquePointer) throws -> T
    ) throws -> T? {
        let statement = try Self.prepare(query, bindings: bindings, database: handle.database)
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        if result == SQLITE_ROW {
            return try map(statement)
        }
        if result == SQLITE_DONE {
            return nil
        }
        throw SQLiteAgentJobStoreError.internal(message: Self.errorMessage(database: handle.database))
    }

    private static func readAgentJob(_ statement: OpaquePointer) throws -> AgentJob {
        let statusText = columnText(statement, 2)
        guard let status = AgentJobStatus(rawValue: statusText) else {
            throw SQLiteAgentJobStoreError.internal(message: "invalid agent job status: \(statusText)")
        }
        let outputSchemaJSON = try optionalColumnText(statement, 4).map(decodeJSONValue)
        let inputHeaders = try decodeJSONString([String].self, columnText(statement, 5))
        let maxRuntimeSeconds = optionalColumnInt(statement, 14).map(UInt64.init)
        return AgentJob(
            id: columnText(statement, 0),
            name: columnText(statement, 1),
            status: status,
            instruction: columnText(statement, 3),
            autoExport: sqlite3_column_int(statement, 8) != 0,
            maxRuntimeSeconds: maxRuntimeSeconds,
            outputSchemaJSON: outputSchemaJSON,
            inputHeaders: inputHeaders,
            inputCSVPath: columnText(statement, 6),
            outputCSVPath: columnText(statement, 7),
            createdAt: dateFromTimestamp(sqlite3_column_int64(statement, 9)),
            updatedAt: dateFromTimestamp(sqlite3_column_int64(statement, 10)),
            startedAt: optionalColumnInt(statement, 11).map(dateFromTimestamp),
            completedAt: optionalColumnInt(statement, 12).map(dateFromTimestamp),
            lastError: optionalColumnText(statement, 13)
        )
    }

    private static func readAgentJobItem(_ statement: OpaquePointer) throws -> AgentJobItem {
        let statusText = columnText(statement, 5)
        guard let status = AgentJobItemStatus(rawValue: statusText) else {
            throw SQLiteAgentJobStoreError.internal(message: "invalid agent job item status: \(statusText)")
        }
        let rowJSON = try decodeJSONValue(columnText(statement, 4))
        let resultJSON = try optionalColumnText(statement, 8).map(decodeJSONValue)
        return AgentJobItem(
            jobID: columnText(statement, 0),
            itemID: columnText(statement, 1),
            rowIndex: sqlite3_column_int64(statement, 2),
            sourceID: optionalColumnText(statement, 3),
            rowJSON: rowJSON,
            status: status,
            assignedThreadID: optionalColumnText(statement, 6),
            attemptCount: sqlite3_column_int64(statement, 7),
            resultJSON: resultJSON,
            lastError: optionalColumnText(statement, 9),
            createdAt: dateFromTimestamp(sqlite3_column_int64(statement, 10)),
            updatedAt: dateFromTimestamp(sqlite3_column_int64(statement, 11)),
            completedAt: optionalColumnInt(statement, 12).map(dateFromTimestamp),
            reportedAt: optionalColumnInt(statement, 13).map(dateFromTimestamp)
        )
    }

    private static func execute(
        _ query: String,
        bindings: [AgentJobSQLiteBinding] = [],
        database: OpaquePointer
    ) throws {
        let statement = try prepare(query, bindings: bindings, database: database)
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else {
            throw SQLiteAgentJobStoreError.internal(message: errorMessage(database: database))
        }
    }

    private static func prepare(
        _ query: String,
        bindings: [AgentJobSQLiteBinding],
        database: OpaquePointer
    ) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, query, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            throw SQLiteAgentJobStoreError.internal(message: errorMessage(database: database))
        }
        do {
            try bind(bindings, to: statement, database: database)
        } catch {
            sqlite3_finalize(statement)
            throw error
        }
        return statement
    }

    private static func bind(
        _ bindings: [AgentJobSQLiteBinding],
        to statement: OpaquePointer,
        database: OpaquePointer
    ) throws {
        for (index, binding) in bindings.enumerated() {
            let bindIndex = Int32(index + 1)
            let result: Int32
            switch binding {
            case let .text(value):
                result = sqlite3_bind_text(statement, bindIndex, value, -1, agentJobSQLiteTransient)
            case let .optionalText(value):
                if let value {
                    result = sqlite3_bind_text(statement, bindIndex, value, -1, agentJobSQLiteTransient)
                } else {
                    result = sqlite3_bind_null(statement, bindIndex)
                }
            case let .int(value):
                result = sqlite3_bind_int64(statement, bindIndex, value)
            case let .optionalInt(value):
                if let value {
                    result = sqlite3_bind_int64(statement, bindIndex, value)
                } else {
                    result = sqlite3_bind_null(statement, bindIndex)
                }
            case let .bool(value):
                result = sqlite3_bind_int(statement, bindIndex, value ? 1 : 0)
            }
            guard result == SQLITE_OK else {
                throw SQLiteAgentJobStoreError.internal(message: errorMessage(database: database))
            }
        }
    }

    private static func bindableMaxRuntimeSeconds(_ value: UInt64?) throws -> Int64? {
        guard let value else {
            return nil
        }
        guard value <= UInt64(Int64.max) else {
            throw SQLiteAgentJobStoreError.internal(message: "invalid max_runtime_seconds value")
        }
        return Int64(value)
    }

    private static func encodeJSONString<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw SQLiteAgentJobStoreError.internal(message: "failed to encode json")
        }
        return string
    }

    private static func decodeJSONString<T: Decodable>(_ type: T.Type, _ string: String) throws -> T {
        guard let data = string.data(using: .utf8) else {
            throw SQLiteAgentJobStoreError.internal(message: "failed to decode json")
        }
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: data)
    }

    private static func decodeJSONValue(_ string: String) throws -> JSONValue {
        try decodeJSONString(JSONValue.self, string)
    }

    private static func columnText(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let rawValue = sqlite3_column_text(statement, index) else {
            return ""
        }
        return String(cString: rawValue)
    }

    private static func optionalColumnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : columnText(statement, index)
    }

    private static func optionalColumnInt(_ statement: OpaquePointer, _ index: Int32) -> Int64? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, index)
    }

    private static func currentTimestamp() -> Int64 {
        Int64(Date().timeIntervalSince1970)
    }

    private static func dateFromTimestamp(_ timestamp: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp))
    }

    private static func errorMessage(database: OpaquePointer) -> String {
        if let message = sqlite3_errmsg(database) {
            return String(cString: message)
        }
        return "unknown sqlite error"
    }
}

private enum AgentJobSQLiteBinding {
    case text(String)
    case optionalText(String?)
    case int(Int64)
    case optionalInt(Int64?)
    case bool(Bool)
}

private let agentJobSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private final class AgentJobSQLiteDatabaseHandle: @unchecked Sendable {
    let database: OpaquePointer

    init(database: OpaquePointer) {
        self.database = database
    }

    deinit {
        sqlite3_close(database)
    }
}
