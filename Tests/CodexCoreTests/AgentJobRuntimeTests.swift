import CodexCore
import XCTest

final class AgentJobRuntimeTests: XCTestCase {
    func testNormalizeConcurrencyMatchesRustCapsAndConfigMax() {
        XCTAssertEqual(AgentJobRuntime.normalizeConcurrency(requested: nil, maxThreads: nil), 16)
        XCTAssertEqual(AgentJobRuntime.normalizeConcurrency(requested: 0, maxThreads: nil), 1)
        XCTAssertEqual(AgentJobRuntime.normalizeConcurrency(requested: 100, maxThreads: nil), 64)
        XCTAssertEqual(AgentJobRuntime.normalizeConcurrency(requested: 32, maxThreads: 4), 4)
        XCTAssertEqual(AgentJobRuntime.normalizeConcurrency(requested: 32, maxThreads: 0), 1)
    }

    func testNormalizeMaxRuntimeSecondsRejectsZeroLikeRust() {
        XCTAssertNoThrow(try AgentJobRuntime.normalizeMaxRuntimeSeconds(nil))
        XCTAssertEqual(try AgentJobRuntime.normalizeMaxRuntimeSeconds(30), 30)
        XCTAssertThrowsError(try AgentJobRuntime.normalizeMaxRuntimeSeconds(0)) { error in
            XCTAssertEqual(error as? FunctionCallError, .respondToModel("max_runtime_seconds must be >= 1"))
        }
    }

    func testBuildWorkerPromptMatchesRustInstructions() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let job = makeJob(
            instruction: "Return {path} from {{literal}}",
            outputSchemaJSON: .object(["type": .string("object")]),
            date: date
        )
        let item = makeItem(date: date)

        let prompt = AgentJobRuntime.buildWorkerPrompt(job: job, item: item)

        XCTAssertTrue(prompt.contains("You are processing one item for a generic agent job."))
        XCTAssertTrue(prompt.contains("Job ID: job-12345678"))
        XCTAssertTrue(prompt.contains("Item ID: row-1"))
        XCTAssertTrue(prompt.contains("Return src/lib.rs from {literal}"))
        XCTAssertTrue(prompt.contains(#""path": "src/lib.rs""#))
        XCTAssertTrue(prompt.contains(#""type": "object""#))
        XCTAssertTrue(prompt.contains("You MUST call the `report_agent_job_result` tool exactly once with:"))
        XCTAssertTrue(prompt.contains(#"1. `job_id` = "job-12345678""#))
        XCTAssertTrue(prompt.contains(#"2. `item_id` = "row-1""#))
        XCTAssertTrue(prompt.contains("If you need to stop the job early, include `stop` = true in the tool call."))
        XCTAssertTrue(prompt.hasSuffix("After the tool call succeeds, stop."))
    }

    func testSpawnResultWireShapeIncludesFailureSummaries() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let job = makeJob(lastError: "job failed", date: date)
        let failedItem = makeItem(
            status: .failed,
            sourceID: "source-1",
            lastError: "worker failed",
            date: date
        )
        let result = AgentJobRuntime.makeSpawnResult(
            job: job,
            progress: AgentJobProgress(pending: 1, running: 0, completed: 2, failed: 1),
            failedItems: [failedItem]
        )

        try XCTAssertJSONObjectEqual(result, [
            "job_id": "job-12345678",
            "status": "failed",
            "output_csv_path": "/tmp/out.csv",
            "total_items": 4,
            "completed_items": 2,
            "failed_items": 1,
            "job_error": "job failed",
            "failed_item_errors": [[
                "item_id": "row-1",
                "source_id": "source-1",
                "last_error": "worker failed",
            ]],
        ])
    }

    func testSpawnResultAddsRustFallbackWhenFailedItemsHaveNoErrors() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let result = AgentJobRuntime.makeSpawnResult(
            job: makeJob(status: .failed, lastError: nil, date: date),
            progress: AgentJobProgress(pending: 0, running: 0, completed: 0, failed: 1),
            failedItems: [makeItem(status: .failed, lastError: nil, date: date)]
        )

        try XCTAssertJSONObjectEqual(result, [
            "job_id": "job-12345678",
            "status": "failed",
            "output_csv_path": "/tmp/out.csv",
            "total_items": 1,
            "completed_items": 0,
            "failed_items": 1,
            "job_error": "agent job has failed items but no error details were recorded",
        ])
    }

    func testReportAgentJobResultToolResultWireShape() throws {
        try XCTAssertJSONObjectEqual(ReportAgentJobResultToolResult(accepted: true), [
            "accepted": true,
        ])
    }

    func testDecodeReportAgentJobResultArgumentsUsesRustSnakeCaseFields() throws {
        let arguments = try AgentJobRuntime.decodeReportAgentJobResultArguments(
            #"{"job_id":"job-1","item_id":"row-1","result":{"ok":true},"stop":true}"#
        )

        XCTAssertEqual(arguments.jobID, "job-1")
        XCTAssertEqual(arguments.itemID, "row-1")
        XCTAssertEqual(arguments.result, .object(["ok": .bool(true)]))
        XCTAssertEqual(arguments.stop, true)
    }

    func testDecodeSpawnAgentsOnCSVArgumentsUsesRustSnakeCaseFields() throws {
        let arguments = try AgentJobRuntime.decodeSpawnAgentsOnCSVArguments(
            """
            {
              "csv_path": "input.csv",
              "instruction": "Review {path}",
              "max_concurrency": 32,
              "max_workers": 4,
              "id_column": "id",
              "output_csv_path": "out.csv",
              "output_schema": {"type": "object"},
              "max_runtime_seconds": 60
            }
            """
        )

        XCTAssertEqual(arguments.csvPath, "input.csv")
        XCTAssertEqual(arguments.instruction, "Review {path}")
        XCTAssertEqual(arguments.maxConcurrency, 32)
        XCTAssertEqual(arguments.maxWorkers, 4)
        XCTAssertEqual(arguments.idColumn, "id")
        XCTAssertEqual(arguments.outputCSVPath, "out.csv")
        XCTAssertEqual(arguments.outputSchemaJSON, .object(["type": .string("object")]))
        XCTAssertEqual(arguments.maxRuntimeSeconds, 60)
    }

    func testCreateSpawnAgentsOnCSVJobPersistsRustFrontHalf() async throws {
        let fixture = try AgentJobRuntimeStoreFixture.make()
        let prepared = try await AgentJobRuntime.createSpawnAgentsOnCSVJob(
            arguments: SpawnAgentsOnCSVArguments(
                csvPath: "input/jobs.csv",
                instruction: "Review {path}",
                maxConcurrency: 32,
                maxWorkers: 2,
                idColumn: "id",
                outputCSVPath: "output/jobs.csv",
                outputSchemaJSON: .object(["type": .string("object")]),
                maxRuntimeSeconds: nil
            ),
            csvContent: "id,path\nalpha,src/lib.rs\nalpha,src/main.rs\n",
            cwd: fixture.tempDirectory.url.path,
            store: fixture.store,
            jobID: "12345678-1234-1234-1234-123456789abc",
            maxThreads: 8,
            configuredMaxRuntimeSeconds: 45
        )

        XCTAssertEqual(prepared.job.id, "12345678-1234-1234-1234-123456789abc")
        XCTAssertEqual(prepared.job.name, "agent-job-12345678")
        XCTAssertEqual(prepared.job.status, .running)
        XCTAssertEqual(prepared.job.instruction, "Review {path}")
        XCTAssertEqual(prepared.job.outputSchemaJSON, .object(["type": .string("object")]))
        XCTAssertEqual(prepared.job.inputHeaders, ["id", "path"])
        XCTAssertEqual(prepared.job.inputCSVPath, fixture.tempDirectory.url.appendingPathComponent("input/jobs.csv").path)
        XCTAssertEqual(prepared.job.outputCSVPath, fixture.tempDirectory.url.appendingPathComponent("output/jobs.csv").path)
        XCTAssertEqual(prepared.job.maxRuntimeSeconds, 45)
        XCTAssertEqual(prepared.itemCount, 2)
        XCTAssertEqual(prepared.concurrency, 8)

        let items = try await fixture.store.listAgentJobItems(jobID: prepared.job.id)
        XCTAssertEqual(items.map(\.itemID), ["alpha", "alpha-2"])
        XCTAssertEqual(items.map(\.sourceID), ["alpha", "alpha"])
        XCTAssertEqual(items.map(\.status), [.pending, .pending])
        XCTAssertEqual(items[0].rowJSON, .object(["id": .string("alpha"), "path": .string("src/lib.rs")]))
    }

    func testCreateSpawnAgentsOnCSVJobDerivesDefaultOutputAndUsesMaxWorkersFallback() async throws {
        let fixture = try AgentJobRuntimeStoreFixture.make()
        let prepared = try await AgentJobRuntime.createSpawnAgentsOnCSVJob(
            arguments: SpawnAgentsOnCSVArguments(
                csvPath: "/tmp/input.csv",
                instruction: "Review {path}",
                maxWorkers: 3
            ),
            csvContent: "path\nsrc/lib.rs\n",
            cwd: fixture.tempDirectory.url.path,
            store: fixture.store,
            jobID: "abcdef12-0000-0000-0000-000000000000"
        )

        XCTAssertEqual(prepared.job.inputCSVPath, "/tmp/input.csv")
        XCTAssertEqual(prepared.job.outputCSVPath, "/tmp/input.agent-job-abcdef12.csv")
        XCTAssertNil(prepared.job.maxRuntimeSeconds)
        XCTAssertEqual(prepared.concurrency, 3)
    }

    func testCreateSpawnAgentsOnCSVJobRejectsRustValidationFailures() async throws {
        let fixture = try AgentJobRuntimeStoreFixture.make()

        do {
            _ = try await AgentJobRuntime.createSpawnAgentsOnCSVJob(
                arguments: SpawnAgentsOnCSVArguments(csvPath: "input.csv", instruction: "   "),
                csvContent: "id\n1\n",
                cwd: fixture.tempDirectory.url.path,
                store: fixture.store,
                jobID: "job-empty-instruction"
            )
            XCTFail("Expected empty instruction to be rejected")
        } catch let error as FunctionCallError {
            XCTAssertEqual(error, .respondToModel("instruction must be non-empty"))
        }

        do {
            _ = try await AgentJobRuntime.createSpawnAgentsOnCSVJob(
                arguments: SpawnAgentsOnCSVArguments(csvPath: "input.csv", instruction: "Review"),
                csvContent: "",
                cwd: fixture.tempDirectory.url.path,
                store: fixture.store,
                jobID: "job-empty-csv"
            )
            XCTFail("Expected headerless CSV to be rejected")
        } catch let error as FunctionCallError {
            XCTAssertEqual(error, .respondToModel("csv input must include a header row"))
        }

        do {
            _ = try await AgentJobRuntime.createSpawnAgentsOnCSVJob(
                arguments: SpawnAgentsOnCSVArguments(csvPath: "input.csv", instruction: "Review"),
                csvContent: "id\n\"unterminated",
                cwd: fixture.tempDirectory.url.path,
                store: fixture.store,
                jobID: "job-bad-csv"
            )
            XCTFail("Expected malformed CSV to be rejected")
        } catch let error as FunctionCallError {
            XCTAssertEqual(error, .respondToModel("failed to parse csv input: unterminated quoted CSV field"))
        }
    }

    func testRecordReportAgentJobResultRejectsNonObjectResultLikeRust() async throws {
        let fixture = try await makeStoreWithRunningItem()

        let arguments = ReportAgentJobResultArguments(
            jobID: "job-1",
            itemID: "row-1",
            result: .string("nope")
        )
        do {
            _ = try await AgentJobRuntime.recordReportAgentJobResult(
                arguments: arguments,
                reportingThreadID: "thread-1",
                store: fixture.store
            )
            XCTFail("Expected non-object result to be rejected")
        } catch let error as FunctionCallError {
            XCTAssertEqual(error, .respondToModel("result must be a JSON object"))
        }
    }

    func testRecordReportAgentJobResultAcceptsMatchingThreadAndCancelsOnStop() async throws {
        let fixture = try await makeStoreWithRunningItem()

        let result = try await AgentJobRuntime.recordReportAgentJobResult(
            argumentsJSON: #"{"job_id":"job-1","item_id":"row-1","result":{"ok":true},"stop":true}"#,
            reportingThreadID: "thread-1",
            store: fixture.store
        )

        XCTAssertEqual(result, ReportAgentJobResultToolResult(accepted: true))
        let reportedItem = try await fixture.store.getAgentJobItem(jobID: "job-1", itemID: "row-1")
        let item = try XCTUnwrap(reportedItem)
        XCTAssertEqual(item.status, .completed)
        XCTAssertEqual(item.resultJSON, .object(["ok": .bool(true)]))
        XCTAssertNil(item.assignedThreadID)
        let cancelledJob = try await fixture.store.getAgentJob("job-1")
        let job = try XCTUnwrap(cancelledJob)
        XCTAssertEqual(job.status, .cancelled)
        XCTAssertEqual(job.lastError, "cancelled by worker request")
    }

    func testRecordReportAgentJobResultRejectsWrongThreadAndDoesNotCancel() async throws {
        let fixture = try await makeStoreWithRunningItem()

        let result = try await AgentJobRuntime.recordReportAgentJobResult(
            arguments: ReportAgentJobResultArguments(
                jobID: "job-1",
                itemID: "row-1",
                result: .object(["ok": .bool(true)]),
                stop: true
            ),
            reportingThreadID: "other-thread",
            store: fixture.store
        )

        XCTAssertEqual(result, ReportAgentJobResultToolResult(accepted: false))
        let persistedItem = try await fixture.store.getAgentJobItem(jobID: "job-1", itemID: "row-1")
        let item = try XCTUnwrap(persistedItem)
        XCTAssertEqual(item.status, .running)
        XCTAssertEqual(item.assignedThreadID, "thread-1")
        XCTAssertNil(item.resultJSON)
        let runningJob = try await fixture.store.getAgentJob("job-1")
        let job = try XCTUnwrap(runningJob)
        XCTAssertEqual(job.status, .running)
        XCTAssertNil(job.lastError)
    }

    private func makeJob(
        instruction: String = "Return {path}",
        outputSchemaJSON: JSONValue? = nil,
        status: AgentJobStatus? = nil,
        lastError: String? = nil,
        date: Date
    ) -> AgentJob {
        AgentJob(
            id: "job-12345678",
            name: "agent-job-12345678",
            status: status ?? (lastError == nil ? .running : .failed),
            instruction: instruction,
            autoExport: true,
            maxRuntimeSeconds: 45,
            outputSchemaJSON: outputSchemaJSON,
            inputHeaders: ["path"],
            inputCSVPath: "/tmp/in.csv",
            outputCSVPath: "/tmp/out.csv",
            createdAt: date,
            updatedAt: date,
            startedAt: date,
            completedAt: lastError == nil ? nil : date,
            lastError: lastError
        )
    }

    private func makeItem(
        status: AgentJobItemStatus = .running,
        sourceID: String? = nil,
        lastError: String? = nil,
        date: Date
    ) -> AgentJobItem {
        AgentJobItem(
            jobID: "job-12345678",
            itemID: "row-1",
            rowIndex: 0,
            sourceID: sourceID,
            rowJSON: .object(["path": .string("src/lib.rs")]),
            status: status,
            assignedThreadID: "thread-1",
            attemptCount: 1,
            resultJSON: nil,
            lastError: lastError,
            createdAt: date,
            updatedAt: date,
            completedAt: status == .running ? nil : date,
            reportedAt: nil
        )
    }

    private func makeStoreWithRunningItem() async throws -> AgentJobRuntimeStoreFixture {
        let tempDirectory = try AgentJobRuntimeTemporaryDirectory()
        let store = try SQLiteAgentJobStore(databaseURL: tempDirectory.url.appendingPathComponent("state.sqlite3"))
        _ = try await store.createAgentJob(
            params: AgentJobCreateParams(
                id: "job-1",
                name: "job",
                instruction: "do it",
                outputSchemaJSON: nil,
                inputHeaders: ["id"],
                inputCSVPath: "/tmp/input.csv",
                outputCSVPath: "/tmp/output.csv",
                autoExport: true,
                maxRuntimeSeconds: nil
            ),
            items: [
                AgentJobItemCreateParams(
                    itemID: "row-1",
                    rowIndex: 0,
                    sourceID: nil,
                    rowJSON: .object(["id": .string("1")])
                ),
            ]
        )
        try await store.markAgentJobRunning("job-1")
        let markedRunning = try await store.markAgentJobItemRunningWithThread(
            jobID: "job-1",
            itemID: "row-1",
            threadID: "thread-1"
        )
        XCTAssertTrue(markedRunning)
        return AgentJobRuntimeStoreFixture(store: store, tempDirectory: tempDirectory)
    }
}

private struct AgentJobRuntimeStoreFixture {
    let store: SQLiteAgentJobStore
    let tempDirectory: AgentJobRuntimeTemporaryDirectory

    static func make() throws -> AgentJobRuntimeStoreFixture {
        let tempDirectory = try AgentJobRuntimeTemporaryDirectory()
        let store = try SQLiteAgentJobStore(databaseURL: tempDirectory.url.appendingPathComponent("state.sqlite3"))
        return AgentJobRuntimeStoreFixture(store: store, tempDirectory: tempDirectory)
    }
}

private final class AgentJobRuntimeTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-swift-agent-job-runtime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
