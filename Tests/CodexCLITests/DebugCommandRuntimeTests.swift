import CodexCLI
import CodexCore
import Foundation
import SQLite3
import XCTest

final class DebugCommandRuntimeTests: XCTestCase {
    func testPromptInputOutputsEnvironmentImagesAndNormalizedPrompt() async throws {
        let temp = try TemporaryDirectory()
        let imagePath = temp.url.appendingPathComponent("image.png", isDirectory: false)
        try writeTinyPNG(to: imagePath)

        let result = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(
                action: .promptInput(prompt: "hello\r\nworld\ragain", imagePaths: [imagePath.path])
            ),
            dependencies: testDependencies(codexHome: temp.url)
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertNil(result.stderrMessage)
        let output = try XCTUnwrap(result.stdoutMessage)
        XCTAssertTrue(output.contains("\n  {"))

        let decoded = try JSONDecoder().decode([ResponseItem].self, from: Data(output.utf8))
        XCTAssertEqual(decoded.count, 2)
        guard case let .message(_, environmentRole, environmentContent, _) = decoded[0] else {
            return XCTFail("expected environment context message")
        }
        XCTAssertEqual(environmentRole, "user")
        guard case let .inputText(environmentText) = environmentContent.first else {
            return XCTFail("expected environment text")
        }
        XCTAssertTrue(environmentText.contains("<environment_context>"))

        guard case let .message(_, userRole, userContent, _) = decoded[1] else {
            return XCTFail("expected user input message")
        }
        XCTAssertEqual(userRole, "user")
        XCTAssertEqual(userContent.count, 4)
        guard case let .inputText(openTag) = userContent[0],
              case .inputImage = userContent[1],
              case let .inputText(closeTag) = userContent[2],
              case let .inputText(promptText) = userContent[3]
        else {
            return XCTFail("expected local image wrapper followed by prompt")
        }
        XCTAssertEqual(openTag, "<image name=[Image #1]>")
        XCTAssertEqual(closeTag, "</image>")
        XCTAssertEqual(promptText, "hello\nworld\nagain")
    }

    func testPromptInputWithoutUserItemsOnlyOutputsEnvironment() async throws {
        let temp = try TemporaryDirectory()

        let result = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .promptInput(prompt: nil, imagePaths: [])),
            dependencies: testDependencies(codexHome: temp.url)
        )

        let output = try XCTUnwrap(result.stdoutMessage)
        let decoded = try JSONDecoder().decode([ResponseItem].self, from: Data(output.utf8))
        XCTAssertEqual(decoded.count, 1)
        guard case let .message(_, role, content, _) = decoded[0] else {
            return XCTFail("expected environment context message")
        }
        XCTAssertEqual(role, "user")
        guard case let .inputText(text) = content.first else {
            return XCTFail("expected environment text")
        }
        XCTAssertTrue(text.contains("<environment_context>"))
    }

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

    func testTraceReduceWritesRustShapedLifecycleStateToDefaultOutput() async throws {
        let temp = try TemporaryDirectory()
        let bundle = temp.url.appendingPathComponent("trace-bundle", isDirectory: true)
        try writeLifecycleTraceBundle(at: bundle)

        let result = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .traceReduce(traceBundle: bundle.path, output: nil)),
            dependencies: testDependencies(codexHome: temp.url)
        )

        let stateURL = bundle.appendingPathComponent("state.json", isDirectory: false)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdoutMessage, "\(stateURL.path)\n")

        let state = try loadJSONObject(at: stateURL)
        XCTAssertEqual(state["schema_version"] as? Int, 1)
        XCTAssertEqual(state["trace_id"] as? String, "trace-1")
        XCTAssertEqual(state["rollout_id"] as? String, "rollout-1")
        XCTAssertEqual(state["root_thread_id"] as? String, "thread-root")
        XCTAssertEqual(state["started_at_unix_ms"] as? Int, 100)
        XCTAssertEqual(state["ended_at_unix_ms"] as? Int, 106)
        XCTAssertEqual(state["status"] as? String, "completed")

        let threads = try XCTUnwrap(state["threads"] as? [String: Any])
        let rootThread = try XCTUnwrap(threads["thread-root"] as? [String: Any])
        XCTAssertEqual(rootThread["agent_path"] as? String, "/root")
        XCTAssertEqual(rootThread["nickname"] as? String, "Main")
        XCTAssertEqual(rootThread["default_model"] as? String, "gpt-test")
        XCTAssertEqual((rootThread["origin"] as? [String: Any])?["type"] as? String, "root")
        let threadExecution = try XCTUnwrap(rootThread["execution"] as? [String: Any])
        XCTAssertEqual(threadExecution["started_seq"] as? Int, 2)
        XCTAssertEqual(threadExecution["ended_seq"] as? Int, 5)
        XCTAssertEqual(threadExecution["status"] as? String, "completed")

        let turns = try XCTUnwrap(state["codex_turns"] as? [String: Any])
        let turn = try XCTUnwrap(turns["turn-1"] as? [String: Any])
        XCTAssertEqual(turn["thread_id"] as? String, "thread-root")
        let turnExecution = try XCTUnwrap(turn["execution"] as? [String: Any])
        XCTAssertEqual(turnExecution["started_at_unix_ms"] as? Int, 103)
        XCTAssertEqual(turnExecution["ended_at_unix_ms"] as? Int, 105)
        XCTAssertEqual(turnExecution["status"] as? String, "completed")

        let rawPayloads = try XCTUnwrap(state["raw_payloads"] as? [String: Any])
        let metadataPayload = try XCTUnwrap(rawPayloads["payload-session"] as? [String: Any])
        XCTAssertEqual(metadataPayload["path"] as? String, "payloads/session.json")
    }

    func testTraceReduceUsesCustomOutputAndSpawnMetadata() async throws {
        let temp = try TemporaryDirectory()
        let bundle = temp.url.appendingPathComponent("trace-bundle", isDirectory: true)
        try writeLifecycleTraceBundle(at: bundle, includeSpawnedThread: true)
        let output = temp.url.appendingPathComponent("custom-state.json", isDirectory: false)

        let result = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .traceReduce(traceBundle: bundle.path, output: output.path)),
            dependencies: testDependencies(codexHome: temp.url)
        )

        XCTAssertEqual(result.stdoutMessage, "\(output.path)\n")
        let state = try loadJSONObject(at: output)
        let threads = try XCTUnwrap(state["threads"] as? [String: Any])
        let childThread = try XCTUnwrap(threads["thread-child"] as? [String: Any])
        XCTAssertEqual(childThread["agent_path"] as? String, "/root/repo_file_counter")
        XCTAssertEqual(childThread["nickname"] as? String, "Kepler")
        let origin = try XCTUnwrap(childThread["origin"] as? [String: Any])
        XCTAssertEqual(origin["type"] as? String, "spawned")
        XCTAssertEqual(origin["parent_thread_id"] as? String, "thread-root")
        XCTAssertEqual(origin["spawn_edge_id"] as? String, "edge:spawn:thread-root:thread-child")
        XCTAssertEqual(origin["task_name"] as? String, "repo_file_counter")
        XCTAssertEqual(origin["agent_role"] as? String, "worker")
    }

    func testTraceReduceRecordsInferenceLifecycleAndUsage() async throws {
        let temp = try TemporaryDirectory()
        let bundle = temp.url.appendingPathComponent("trace-bundle", isDirectory: true)
        let requestPayload: [String: Any] = [
            "raw_payload_id": "payload-request",
            "kind": ["type": "inference_request"],
            "path": "payloads/request.json"
        ]
        let responsePayload: [String: Any] = [
            "raw_payload_id": "payload-response",
            "kind": ["type": "inference_response"],
            "path": "payloads/response.json"
        ]

        try writeTraceBundle(at: bundle, events: [
            traceEvent(seq: 1, wallTime: 101, payload: [
                "type": "rollout_started",
                "trace_id": "trace-1",
                "root_thread_id": "thread-root"
            ]),
            traceEvent(seq: 2, wallTime: 102, payload: [
                "type": "thread_started",
                "thread_id": "thread-root",
                "agent_path": "/root"
            ]),
            traceEvent(seq: 3, wallTime: 103, threadID: "thread-root", payload: [
                "type": "codex_turn_started",
                "codex_turn_id": "turn-1",
                "thread_id": "thread-root"
            ]),
            traceEvent(seq: 4, wallTime: 104, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "inference_started",
                "inference_call_id": "inference-1",
                "thread_id": "thread-root",
                "codex_turn_id": "turn-1",
                "model": "gpt-test",
                "provider_name": "openai",
                "request_payload": requestPayload
            ]),
            traceEvent(seq: 5, wallTime: 106, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "inference_completed",
                "inference_call_id": "inference-1",
                "response_id": "resp-1",
                "upstream_request_id": "req-1",
                "response_payload": responsePayload
            ]),
            traceEvent(seq: 6, wallTime: 107, threadID: "thread-root", payload: [
                "type": "codex_turn_ended",
                "codex_turn_id": "turn-1",
                "status": "completed"
            ])
        ])
        try writeJSONObject(["input": []], to: bundle.appendingPathComponent("payloads/request.json", isDirectory: false))
        try writeJSONObject([
            "response_id": "resp-1",
            "token_usage": [
                "input_tokens": 11,
                "cached_input_tokens": 3,
                "output_tokens": 7,
                "reasoning_output_tokens": 2
            ],
            "output_items": []
        ], to: bundle.appendingPathComponent("payloads/response.json", isDirectory: false))

        let result = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .traceReduce(traceBundle: bundle.path, output: nil)),
            dependencies: testDependencies(codexHome: temp.url)
        )

        XCTAssertEqual(result.exitCode, 0)
        let state = try loadJSONObject(at: bundle.appendingPathComponent("state.json", isDirectory: false))
        let inferences = try XCTUnwrap(state["inference_calls"] as? [String: Any])
        let inference = try XCTUnwrap(inferences["inference-1"] as? [String: Any])
        XCTAssertEqual(inference["thread_id"] as? String, "thread-root")
        XCTAssertEqual(inference["codex_turn_id"] as? String, "turn-1")
        XCTAssertEqual(inference["model"] as? String, "gpt-test")
        XCTAssertEqual(inference["provider_name"] as? String, "openai")
        XCTAssertEqual(inference["response_id"] as? String, "resp-1")
        XCTAssertEqual(inference["upstream_request_id"] as? String, "req-1")
        XCTAssertEqual(inference["raw_request_payload_id"] as? String, "payload-request")
        XCTAssertEqual(inference["raw_response_payload_id"] as? String, "payload-response")
        XCTAssertEqual(inference["request_item_ids"] as? [String], [])
        XCTAssertEqual(inference["response_item_ids"] as? [String], [])

        let execution = try XCTUnwrap(inference["execution"] as? [String: Any])
        XCTAssertEqual(execution["started_seq"] as? Int, 4)
        XCTAssertEqual(execution["ended_seq"] as? Int, 5)
        XCTAssertEqual(execution["status"] as? String, "completed")

        let usage = try XCTUnwrap(inference["usage"] as? [String: Any])
        XCTAssertEqual(usage["input_tokens"] as? Int, 11)
        XCTAssertEqual(usage["cached_input_tokens"] as? Int, 3)
        XCTAssertEqual(usage["output_tokens"] as? Int, 7)
        XCTAssertEqual(usage["reasoning_output_tokens"] as? Int, 2)

        let rawPayloads = try XCTUnwrap(state["raw_payloads"] as? [String: Any])
        XCTAssertNotNil(rawPayloads["payload-request"])
        XCTAssertNotNil(rawPayloads["payload-response"])
    }

    func testTraceReduceClosesRunningInferenceOnTurnEndAndPreservesLatePartialPayload() async throws {
        let temp = try TemporaryDirectory()
        let bundle = temp.url.appendingPathComponent("trace-bundle", isDirectory: true)
        let requestPayload: [String: Any] = [
            "raw_payload_id": "payload-request",
            "kind": ["type": "inference_request"],
            "path": "payloads/request.json"
        ]
        let partialResponsePayload: [String: Any] = [
            "raw_payload_id": "payload-partial-response",
            "kind": ["type": "inference_response"],
            "path": "payloads/partial-response.json"
        ]

        try writeTraceBundle(at: bundle, events: [
            traceEvent(seq: 1, wallTime: 101, payload: [
                "type": "thread_started",
                "thread_id": "thread-root",
                "agent_path": "/root"
            ]),
            traceEvent(seq: 2, wallTime: 102, threadID: "thread-root", payload: [
                "type": "codex_turn_started",
                "codex_turn_id": "turn-1",
                "thread_id": "thread-root"
            ]),
            traceEvent(seq: 3, wallTime: 103, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "inference_started",
                "inference_call_id": "inference-1",
                "thread_id": "thread-root",
                "codex_turn_id": "turn-1",
                "model": "gpt-test",
                "provider_name": "openai",
                "request_payload": requestPayload
            ]),
            traceEvent(seq: 4, wallTime: 104, threadID: "thread-root", payload: [
                "type": "codex_turn_ended",
                "codex_turn_id": "turn-1",
                "status": "failed"
            ]),
            traceEvent(seq: 5, wallTime: 105, threadID: "thread-root", codexTurnID: "turn-1", payload: [
                "type": "inference_cancelled",
                "inference_call_id": "inference-1",
                "upstream_request_id": "req-late",
                "reason": "stream mapper noticed cancellation after turn end",
                "partial_response_payload": partialResponsePayload
            ])
        ])
        try writeJSONObject(["input": []], to: bundle.appendingPathComponent("payloads/request.json", isDirectory: false))
        try writeJSONObject([
            "response_id": NSNull(),
            "token_usage": NSNull(),
            "output_items": []
        ], to: bundle.appendingPathComponent("payloads/partial-response.json", isDirectory: false))

        _ = try await DebugCommandRuntime.run(
            CodexCLI.DebugCommandRequest(action: .traceReduce(traceBundle: bundle.path, output: nil)),
            dependencies: testDependencies(codexHome: temp.url)
        )

        let state = try loadJSONObject(at: bundle.appendingPathComponent("state.json", isDirectory: false))
        let inferences = try XCTUnwrap(state["inference_calls"] as? [String: Any])
        let inference = try XCTUnwrap(inferences["inference-1"] as? [String: Any])
        let execution = try XCTUnwrap(inference["execution"] as? [String: Any])
        XCTAssertEqual(execution["status"] as? String, "failed")
        XCTAssertEqual(execution["ended_seq"] as? Int, 4)
        XCTAssertEqual(inference["upstream_request_id"] as? String, "req-late")
        XCTAssertEqual(inference["raw_response_payload_id"] as? String, "payload-partial-response")
    }

    func testTraceReduceRejectsUnsupportedSemanticEvents() async throws {
        let temp = try TemporaryDirectory()
        let bundle = temp.url.appendingPathComponent("trace-bundle", isDirectory: true)
        try writeTraceBundle(
            at: bundle,
            events: [
                traceEvent(seq: 1, wallTime: 101, payload: [
                    "type": "tool_call_started",
                    "tool_call_id": "tool-1"
                ])
            ]
        )

        do {
            _ = try await DebugCommandRuntime.run(
                CodexCLI.DebugCommandRequest(action: .traceReduce(traceBundle: bundle.path, output: nil)),
                dependencies: testDependencies(codexHome: temp.url)
            )
            XCTFail("expected unsupported rich event to fail")
        } catch {
            XCTAssertEqual(String(describing: error), "unsupported trace event payload type tool_call_started")
        }
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

    private func writeTinyPNG(to path: URL) throws {
        let encoded = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
        let data = try XCTUnwrap(Data(base64Encoded: encoded))
        try data.write(to: path)
    }

    private func writeLifecycleTraceBundle(
        at bundle: URL,
        includeSpawnedThread: Bool = false
    ) throws {
        let sessionPayload: [String: Any] = [
            "raw_payload_id": "payload-session",
            "kind": ["type": "session_metadata"],
            "path": "payloads/session.json"
        ]
        var events: [[String: Any]] = [
            traceEvent(seq: 1, wallTime: 101, payload: [
                "type": "rollout_started",
                "trace_id": "trace-1",
                "root_thread_id": "thread-root"
            ]),
            traceEvent(seq: 2, wallTime: 102, payload: [
                "type": "thread_started",
                "thread_id": "thread-root",
                "agent_path": "/root-from-event",
                "metadata_payload": sessionPayload
            ]),
            traceEvent(seq: 3, wallTime: 103, threadID: "thread-root", payload: [
                "type": "codex_turn_started",
                "codex_turn_id": "turn-1",
                "thread_id": "thread-root"
            ]),
            traceEvent(seq: 4, wallTime: 105, threadID: "thread-root", payload: [
                "type": "codex_turn_ended",
                "codex_turn_id": "turn-1",
                "status": "completed"
            ])
        ]
        if includeSpawnedThread {
            let childPayload: [String: Any] = [
                "raw_payload_id": "payload-child-session",
                "kind": ["type": "session_metadata"],
                "path": "payloads/child-session.json"
            ]
            events.append(traceEvent(seq: 5, wallTime: 105, payload: [
                "type": "thread_started",
                "thread_id": "thread-child",
                "agent_path": "/event-child",
                "metadata_payload": childPayload
            ]))
        }
        events.append(contentsOf: [
            traceEvent(seq: includeSpawnedThread ? 6 : 5, wallTime: 105, payload: [
                "type": "thread_ended",
                "thread_id": "thread-root",
                "status": "completed"
            ]),
            traceEvent(seq: includeSpawnedThread ? 7 : 6, wallTime: 106, payload: [
                "type": "rollout_ended",
                "status": "completed"
            ])
        ])
        try writeTraceBundle(at: bundle, events: events)

        let payloads = bundle.appendingPathComponent("payloads", isDirectory: true)
        try writeJSONObject([
            "agent_path": "/root",
            "nickname": "Main",
            "model": "gpt-test",
            "session_source": ["exec": [:]]
        ], to: payloads.appendingPathComponent("session.json", isDirectory: false))
        if includeSpawnedThread {
            try writeJSONObject([
                "agent_path": "/root/repo_file_counter",
                "nickname": "Kepler",
                "agent_role": "worker",
                "session_source": [
                    "subagent": [
                        "thread_spawn": [
                            "parent_thread_id": "thread-root",
                            "agent_path": "/root/repo_file_counter",
                            "task_name": "repo_file_counter",
                            "agent_role": "worker"
                        ]
                    ]
                ]
            ], to: payloads.appendingPathComponent("child-session.json", isDirectory: false))
        }
    }

    private func writeTraceBundle(at bundle: URL, events: [[String: Any]]) throws {
        try FileManager.default.createDirectory(
            at: bundle.appendingPathComponent("payloads", isDirectory: true),
            withIntermediateDirectories: true
        )
        try writeJSONObject([
            "schema_version": 1,
            "trace_id": "trace-1",
            "rollout_id": "rollout-1",
            "root_thread_id": "thread-root",
            "started_at_unix_ms": 100,
            "raw_event_log": "trace.jsonl",
            "payloads_dir": "payloads"
        ], to: bundle.appendingPathComponent("manifest.json", isDirectory: false))
        let lines = try events.map { event -> String in
            let data = try JSONSerialization.data(withJSONObject: event, options: [.sortedKeys])
            return String(data: data, encoding: .utf8) ?? ""
        }
        try lines.joined(separator: "\n").write(
            to: bundle.appendingPathComponent("trace.jsonl", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
    }

    private func traceEvent(
        seq: Int,
        wallTime: Int,
        threadID: String? = nil,
        codexTurnID: String? = nil,
        payload: [String: Any]
    ) -> [String: Any] {
        [
            "schema_version": 1,
            "seq": seq,
            "wall_time_unix_ms": wallTime,
            "rollout_id": "rollout-1",
            "thread_id": threadID ?? NSNull(),
            "codex_turn_id": codexTurnID ?? NSNull(),
            "payload": payload
        ]
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }

    private func loadJSONObject(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
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
