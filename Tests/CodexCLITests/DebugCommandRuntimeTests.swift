import CodexCLI
import CodexCore
import Foundation
import SQLite3
import XCTest

final class DebugCommandRuntimeTests: XCTestCase {
    func testClearMemoriesClearsStateRowsAndMemoryRoots() async throws {
        let temp = try TemporaryDirectory()
        let statePath = temp.url.appendingPathComponent("state_5.sqlite", isDirectory: false)
        try createMemoryTables(databaseURL: statePath)
        try insertMemoryRows(databaseURL: statePath)

        let memoryRoot = temp.url.appendingPathComponent("memories", isDirectory: true)
        let memoryExtensionRoot = temp.url.appendingPathComponent("memories_extensions", isDirectory: true)
        try FileManager.default.createDirectory(
            at: memoryRoot.appendingPathComponent("rollout_summaries", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: memoryExtensionRoot.appendingPathComponent("ad_hoc/resources", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "stale".write(
            to: memoryRoot.appendingPathComponent("MEMORY.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try "stale".write(
            to: memoryExtensionRoot.appendingPathComponent("ad_hoc/resources/stale.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let result = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .clearMemories),
            dependencies: testDependencies(codexHome: temp.url)
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(
            result.stdoutMessage,
            "Cleared memory state from \(statePath.path). Cleared memory directories under \(temp.url.path)."
        )
        XCTAssertNil(result.stderrMessage)
        XCTAssertEqual(try sqliteCount(databaseURL: statePath, query: "SELECT COUNT(*) FROM stage1_outputs"), 0)
        XCTAssertEqual(
            try sqliteCount(
                databaseURL: statePath,
                query: "SELECT COUNT(*) FROM jobs WHERE kind = 'memory_stage1' OR kind = 'memory_consolidate_global'"
            ),
            0
        )
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: memoryRoot.path), [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: memoryExtensionRoot.path), [])
    }

    func testClearMemoriesReportsMissingStateDBAndStillClearsMemoryRoots() async throws {
        let temp = try TemporaryDirectory()
        let memoryRoot = temp.url.appendingPathComponent("memories", isDirectory: true)
        let memoryExtensionRoot = temp.url.appendingPathComponent("memories_extensions", isDirectory: true)
        try FileManager.default.createDirectory(at: memoryRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: memoryExtensionRoot, withIntermediateDirectories: true)
        try "stale".write(
            to: memoryRoot.appendingPathComponent("MEMORY.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try "stale".write(
            to: memoryExtensionRoot.appendingPathComponent("extension.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let result = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .clearMemories),
            dependencies: testDependencies(codexHome: temp.url)
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(
            result.stdoutMessage,
            "No state db found at \(temp.url.appendingPathComponent("state_5.sqlite").path). Cleared memory directories under \(temp.url.path)."
        )
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: memoryRoot.path), [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: memoryExtensionRoot.path), [])
    }

    private func testDependencies(codexHome: URL) -> DebugCommandRuntime.Dependencies {
        DebugCommandRuntime.Dependencies(
            findCodexHome: { codexHome },
            loadConfig: { _, _ in
                CodexRuntimeConfig(modelProvider: "test-provider")
            }
        )
    }

    private func createMemoryTables(databaseURL: URL) throws {
        try withSQLiteDatabase(databaseURL: databaseURL) { database in
            try execute(
                """
                CREATE TABLE stage1_outputs (
                    thread_id TEXT PRIMARY KEY,
                    source_updated_at INTEGER NOT NULL,
                    raw_memory TEXT NOT NULL,
                    rollout_summary TEXT NOT NULL,
                    generated_at INTEGER NOT NULL
                )
                """,
                database: database
            )
            try execute(
                """
                CREATE TABLE jobs (
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
                database: database
            )
        }
    }

    private func insertMemoryRows(databaseURL: URL) throws {
        try withSQLiteDatabase(databaseURL: databaseURL) { database in
            try execute(
                """
                INSERT INTO stage1_outputs (
                    thread_id,
                    source_updated_at,
                    raw_memory,
                    rollout_summary,
                    generated_at
                ) VALUES ('thread-1', 1, 'raw', 'summary', 1)
                """,
                database: database
            )
            try execute(
                """
                INSERT INTO jobs (
                    kind,
                    job_key,
                    status,
                    retry_remaining
                ) VALUES
                    ('memory_stage1', 'thread-1', 'completed', 3),
                    ('memory_consolidate_global', 'global', 'completed', 3),
                    ('not_memory', 'other', 'completed', 3)
                """,
                database: database
            )
        }
    }

    private func sqliteCount(databaseURL: URL, query: String) throws -> Int {
        try withSQLiteDatabase(databaseURL: databaseURL) { database in
            var statement: OpaquePointer?
            XCTAssertEqual(sqlite3_prepare_v2(database, query, -1, &statement, nil), SQLITE_OK)
            defer { sqlite3_finalize(statement) }
            XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
            return Int(sqlite3_column_int(statement, 0))
        }
    }

    private func withSQLiteDatabase<T>(
        databaseURL: URL,
        _ body: (OpaquePointer) throws -> T
    ) throws -> T {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        guard let database else {
            throw NSError(domain: "DebugCommandRuntimeTests", code: 1)
        }
        defer { sqlite3_close(database) }
        return try body(database)
    }

    private func execute(_ sql: String, database: OpaquePointer) throws {
        var error: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &error)
        defer { sqlite3_free(error) }
        if result != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "sqlite error \(result)"
            XCTFail(message)
            throw NSError(domain: "DebugCommandRuntimeTests", code: Int(result))
        }
    }
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-swift-debug-runtime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
