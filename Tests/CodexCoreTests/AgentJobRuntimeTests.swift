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

    func testBuildRunnerOptionsMatchesRustDepthAndThreadLimits() throws {
        let parentThreadID = try ThreadId(string: "00000000-0000-4000-8000-000000000061")
        let childSource = SessionSource.subagent(.threadSpawn(parentThreadID: parentThreadID, depth: 1))

        let options = try AgentJobRuntime.buildRunnerOptions(
            requestedConcurrency: 32,
            maxThreads: 6,
            sessionSource: childSource,
            maxDepth: 2
        )

        XCTAssertEqual(options.maxConcurrency, 6)
        XCTAssertEqual(options.childDepth, 2)
        XCTAssertEqual(AgentJobRuntime.nextThreadSpawnDepth(for: .vscode), 1)
        XCTAssertFalse(AgentJobRuntime.exceedsThreadSpawnDepthLimit(depth: 2, maxDepth: 2))
        XCTAssertTrue(AgentJobRuntime.exceedsThreadSpawnDepthLimit(depth: 3, maxDepth: 2))

        XCTAssertThrowsError(
            try AgentJobRuntime.buildRunnerOptions(
                requestedConcurrency: nil,
                maxThreads: 6,
                sessionSource: childSource,
                maxDepth: 1
            )
        ) { error in
            XCTAssertEqual(
                error as? FunctionCallError,
                .respondToModel("agent depth limit reached; this session cannot spawn more subagents")
            )
        }

        XCTAssertThrowsError(
            try AgentJobRuntime.buildRunnerOptions(
                requestedConcurrency: nil,
                maxThreads: 0,
                sessionSource: .vscode,
                maxDepth: 1
            )
        ) { error in
            XCTAssertEqual(
                error as? FunctionCallError,
                .respondToModel("agent thread limit reached; this session cannot spawn more subagents")
            )
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

    func testCreateSpawnAgentsOnCSVJobFailsPendingJobWhenRunnerOptionsRejectLikeRust() async throws {
        let fixture = try AgentJobRuntimeStoreFixture.make()
        do {
            _ = try await AgentJobRuntime.createSpawnAgentsOnCSVJob(
                arguments: SpawnAgentsOnCSVArguments(
                    csvPath: "input/jobs.csv",
                    instruction: "Review {path}"
                ),
                csvContent: "id,path\nalpha,src/lib.rs\n",
                cwd: fixture.tempDirectory.url.path,
                store: fixture.store,
                jobID: "job-thread-limit",
                maxThreads: 0
            )
            XCTFail("Expected max thread zero to reject the runner")
        } catch let error as FunctionCallError {
            XCTAssertEqual(
                error,
                .respondToModel("agent thread limit reached; this session cannot spawn more subagents")
            )
        }

        let persistedJob = try await fixture.store.getAgentJob("job-thread-limit")
        let job = try XCTUnwrap(persistedJob)
        XCTAssertEqual(job.status, .failed)
        XCTAssertEqual(job.lastError, "agent thread limit reached; this session cannot spawn more subagents")

        let items = try await fixture.store.listAgentJobItems(jobID: "job-thread-limit")
        XCTAssertEqual(items.map(\.status), [.pending])
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

    func testMakeSpawnAgentsOnCSVResultExportsMissingSnapshotLikeRust() async throws {
        let fixture = try AgentJobRuntimeStoreFixture.make()
        let outputURL = fixture.tempDirectory.url
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("results.csv")
        _ = try await fixture.store.createAgentJob(
            params: AgentJobCreateParams(
                id: "job-export",
                name: "agent-job-export",
                instruction: "Review {name}",
                outputSchemaJSON: nil,
                inputHeaders: ["id", "name"],
                inputCSVPath: fixture.tempDirectory.url.appendingPathComponent("input.csv").path,
                outputCSVPath: outputURL.path,
                autoExport: true,
                maxRuntimeSeconds: nil
            ),
            items: [
                AgentJobItemCreateParams(
                    itemID: "row-1",
                    rowIndex: 0,
                    sourceID: "source-1",
                    rowJSON: .object(["id": .string("1"), "name": .string("alpha, beta")])
                ),
                AgentJobItemCreateParams(
                    itemID: "row-2",
                    rowIndex: 1,
                    sourceID: nil,
                    rowJSON: .object(["id": .string("2"), "name": .string("gamma")])
                ),
            ]
        )
        try await fixture.store.markAgentJobRunning("job-export")
        let markedFirstRunning = try await fixture.store.markAgentJobItemRunningWithThread(
            jobID: "job-export",
            itemID: "row-1",
            threadID: "thread-1"
        )
        XCTAssertTrue(markedFirstRunning)
        let reportedFirstResult = try await fixture.store.reportAgentJobItemResult(
            jobID: "job-export",
            itemID: "row-1",
            reportingThreadID: "thread-1",
            resultJSON: .object(["ok": .bool(true)])
        )
        XCTAssertTrue(reportedFirstResult)
        let markedSecondRunning = try await fixture.store.markAgentJobItemRunningWithThread(
            jobID: "job-export",
            itemID: "row-2",
            threadID: "thread-2"
        )
        XCTAssertTrue(markedSecondRunning)
        let markedSecondFailed = try await fixture.store.markAgentJobItemFailed(
            jobID: "job-export",
            itemID: "row-2",
            errorMessage: "worker finished without calling report_agent_job_result"
        )
        XCTAssertTrue(markedSecondFailed)
        try await fixture.store.markAgentJobCompleted("job-export")

        let persistedJob = try await fixture.store.getAgentJob("job-export")
        let job = try XCTUnwrap(persistedJob)
        let result = try await AgentJobRuntime.makeSpawnAgentsOnCSVResult(
            store: fixture.store,
            job: job
        )

        XCTAssertEqual(result.status, "completed")
        XCTAssertEqual(result.outputCSVPath, outputURL.path)
        XCTAssertEqual(result.totalItems, 2)
        XCTAssertEqual(result.completedItems, 1)
        XCTAssertEqual(result.failedItems, 1)
        XCTAssertNil(result.jobError)
        XCTAssertEqual(result.failedItemErrors, [
            AgentJobFailureSummary(
                itemID: "row-2",
                sourceID: nil,
                lastError: "worker finished without calling report_agent_job_result"
            ),
        ])

        let csv = try String(contentsOf: outputURL, encoding: .utf8)
        XCTAssertTrue(csv.hasPrefix(
            "id,name,job_id,item_id,row_index,source_id,status,attempt_count,last_error,result_json,reported_at,completed_at\n"
        ))
        XCTAssertTrue(csv.contains(#"1,"alpha, beta",job-export,row-1,0,source-1,completed,1,,"{""ok"":true}""#))
        XCTAssertTrue(csv.contains(
            "2,gamma,job-export,row-2,1,,failed,1,worker finished without calling report_agent_job_result,"
        ))
    }

    func testRecoverRunningItemsAppliesRustFinalAndMalformedThreadRules() async throws {
        let fixture = try await makeStoreWithItems(["missing-thread", "invalid-thread", "finished-thread", "active-thread"])
        let finishedThreadID = try ThreadId(string: "00000000-0000-4000-8000-000000000003")
        let activeThreadID = try ThreadId(string: "00000000-0000-4000-8000-000000000004")
        let markedMissingRunning = try await fixture.store.markAgentJobItemRunning(
            jobID: "job-1",
            itemID: "missing-thread"
        )
        XCTAssertTrue(markedMissingRunning)
        let markedInvalidRunning = try await fixture.store.markAgentJobItemRunning(
            jobID: "job-1",
            itemID: "invalid-thread"
        )
        XCTAssertTrue(markedInvalidRunning)
        let setInvalidThread = try await fixture.store.setAgentJobItemThread(
            jobID: "job-1",
            itemID: "invalid-thread",
            threadID: "not-a-thread-id"
        )
        XCTAssertTrue(setInvalidThread)
        let markedFinishedRunning = try await fixture.store.markAgentJobItemRunningWithThread(
            jobID: "job-1",
            itemID: "finished-thread",
            threadID: finishedThreadID.description
        )
        XCTAssertTrue(markedFinishedRunning)
        let markedActiveRunning = try await fixture.store.markAgentJobItemRunningWithThread(
            jobID: "job-1",
            itemID: "active-thread",
            threadID: activeThreadID.description
        )
        XCTAssertTrue(markedActiveRunning)

        let shutdownThreads = ThreadRecorder()
        let activeItems = try await AgentJobRuntime.recoverRunningItems(
            store: fixture.store,
            jobID: "job-1",
            runtimeTimeout: 999,
            statusForThread: { threadID in
                threadID == finishedThreadID ? .completed(nil) : .running
            },
            shutdownThread: { threadID in
                await shutdownThreads.append(threadID)
            }
        )

        XCTAssertEqual(activeItems.map(\.itemID), ["active-thread"])
        XCTAssertEqual(activeItems.map(\.threadID), [activeThreadID])
        let recordedShutdownThreads = await shutdownThreads.values()
        XCTAssertEqual(recordedShutdownThreads, [finishedThreadID])

        let persistedMissing = try await fixture.store.getAgentJobItem(
            jobID: "job-1",
            itemID: "missing-thread"
        )
        let missing = try XCTUnwrap(persistedMissing)
        XCTAssertEqual(missing.status, .failed)
        XCTAssertEqual(missing.lastError, "running item is missing assigned_thread_id")

        let persistedInvalid = try await fixture.store.getAgentJobItem(
            jobID: "job-1",
            itemID: "invalid-thread"
        )
        let invalid = try XCTUnwrap(persistedInvalid)
        XCTAssertEqual(invalid.status, .failed)
        XCTAssertTrue(invalid.lastError?.hasPrefix("invalid assigned_thread_id: Invalid thread id: not-a-thread-id") == true)

        let persistedFinished = try await fixture.store.getAgentJobItem(
            jobID: "job-1",
            itemID: "finished-thread"
        )
        let finished = try XCTUnwrap(persistedFinished)
        XCTAssertEqual(finished.status, .failed)
        XCTAssertEqual(finished.lastError, "worker finished without calling report_agent_job_result")
    }

    func testRecoverRunningItemsReapsStalePersistedItemsLikeRust() async throws {
        let fixture = try await makeStoreWithItems(["stale-thread"])
        let staleThreadID = try ThreadId(string: "00000000-0000-4000-8000-000000000011")
        let markedStaleRunning = try await fixture.store.markAgentJobItemRunningWithThread(
            jobID: "job-1",
            itemID: "stale-thread",
            threadID: staleThreadID.description
        )
        XCTAssertTrue(markedStaleRunning)

        let shutdownThreads = ThreadRecorder()
        let activeItems = try await AgentJobRuntime.recoverRunningItems(
            store: fixture.store,
            jobID: "job-1",
            runtimeTimeout: 45,
            now: Date().addingTimeInterval(90),
            statusForThread: { _ in .running },
            shutdownThread: { threadID in
                await shutdownThreads.append(threadID)
            }
        )

        XCTAssertEqual(activeItems, [])
        let recordedShutdownThreads = await shutdownThreads.values()
        XCTAssertEqual(recordedShutdownThreads, [staleThreadID])
        let persistedStale = try await fixture.store.getAgentJobItem(jobID: "job-1", itemID: "stale-thread")
        let stale = try XCTUnwrap(persistedStale)
        XCTAssertEqual(stale.status, .failed)
        XCTAssertEqual(stale.lastError, "worker exceeded max runtime of 45s")
    }

    func testFindAndReapActiveItemsMatchRustFinalAndTimeoutRules() async throws {
        let fixture = try await makeStoreWithItems(["stale-active", "fresh-active"])
        let staleThreadID = try ThreadId(string: "00000000-0000-4000-8000-000000000021")
        let freshThreadID = try ThreadId(string: "00000000-0000-4000-8000-000000000022")
        let markedStaleRunning = try await fixture.store.markAgentJobItemRunningWithThread(
            jobID: "job-1",
            itemID: "stale-active",
            threadID: staleThreadID.description
        )
        XCTAssertTrue(markedStaleRunning)
        let markedFreshRunning = try await fixture.store.markAgentJobItemRunningWithThread(
            jobID: "job-1",
            itemID: "fresh-active",
            threadID: freshThreadID.description
        )
        XCTAssertTrue(markedFreshRunning)

        let now = Date()
        let activeItems = [
            ActiveAgentJobItem(threadID: staleThreadID, itemID: "stale-active", startedAt: now.addingTimeInterval(-60)),
            ActiveAgentJobItem(threadID: freshThreadID, itemID: "fresh-active", startedAt: now),
        ]
        let finished = await AgentJobRuntime.findFinishedThreads(
            activeItems: activeItems,
            statusForThread: { threadID in
                threadID == freshThreadID ? .errored("done") : .running
            }
        )
        XCTAssertEqual(finished.map(\.itemID), ["fresh-active"])

        let shutdownThreads = ThreadRecorder()
        let reapResult = try await AgentJobRuntime.reapStaleActiveItems(
            store: fixture.store,
            jobID: "job-1",
            activeItems: activeItems,
            runtimeTimeout: 45,
            now: now,
            shutdownThread: { threadID in
                await shutdownThreads.append(threadID)
            }
        )

        XCTAssertTrue(reapResult.didProgress)
        XCTAssertEqual(reapResult.remainingItems.map(\.itemID), ["fresh-active"])
        let recordedShutdownThreads = await shutdownThreads.values()
        XCTAssertEqual(recordedShutdownThreads, [staleThreadID])
        let persistedStale = try await fixture.store.getAgentJobItem(jobID: "job-1", itemID: "stale-active")
        let stale = try XCTUnwrap(persistedStale)
        XCTAssertEqual(stale.status, .failed)
        XCTAssertEqual(stale.lastError, "worker exceeded max runtime of 45s")
    }

    func testSpawnPendingItemsFillsAvailableSlotsLikeRust() async throws {
        let fixture = try await makeStoreWithItems(["row-1", "row-2", "row-3"])
        let persistedJob = try await fixture.store.getAgentJob("job-1")
        let job = try XCTUnwrap(persistedJob)
        let existingThreadID = try ThreadId(string: "00000000-0000-4000-8000-000000000031")
        let firstThreadID = try ThreadId(string: "00000000-0000-4000-8000-000000000032")
        let secondThreadID = try ThreadId(string: "00000000-0000-4000-8000-000000000033")
        let recorder = SpawnRequestRecorder(results: [.spawned(firstThreadID), .spawned(secondThreadID)])

        let result = try await AgentJobRuntime.spawnPendingItems(
            store: fixture.store,
            job: job,
            activeItems: [
                ActiveAgentJobItem(threadID: existingThreadID, itemID: "existing", startedAt: Date()),
            ],
            maxConcurrency: 3,
            spawnWorker: { request in
                await recorder.spawn(request)
            },
            shutdownThread: { _ in }
        )

        XCTAssertTrue(result.didProgress)
        XCTAssertEqual(result.activeItems.map(\.itemID), ["existing", "row-1", "row-2"])
        XCTAssertEqual(result.activeItems.map(\.threadID), [existingThreadID, firstThreadID, secondThreadID])
        let requests = await recorder.requests()
        XCTAssertEqual(requests.map(\.itemID), ["row-1", "row-2"])
        XCTAssertTrue(requests[0].prompt.contains("Job ID: job-1"))
        XCTAssertTrue(requests[0].prompt.contains("Item ID: row-1"))

        let persistedFirst = try await fixture.store.getAgentJobItem(jobID: "job-1", itemID: "row-1")
        let first = try XCTUnwrap(persistedFirst)
        XCTAssertEqual(first.status, .running)
        XCTAssertEqual(first.assignedThreadID, firstThreadID.description)
        XCTAssertEqual(first.attemptCount, 1)
        let persistedThird = try await fixture.store.getAgentJobItem(jobID: "job-1", itemID: "row-3")
        let third = try XCTUnwrap(persistedThird)
        XCTAssertEqual(third.status, .pending)
    }

    func testSpawnPendingItemsStopsOnAgentLimitLikeRust() async throws {
        let fixture = try await makeStoreWithItems(["row-1", "row-2"])
        let persistedJob = try await fixture.store.getAgentJob("job-1")
        let job = try XCTUnwrap(persistedJob)
        let recorder = SpawnRequestRecorder(results: [.agentLimitReached, .failed("should not run")])

        let result = try await AgentJobRuntime.spawnPendingItems(
            store: fixture.store,
            job: job,
            activeItems: [],
            maxConcurrency: 2,
            spawnWorker: { request in
                await recorder.spawn(request)
            },
            shutdownThread: { _ in }
        )

        XCTAssertFalse(result.didProgress)
        XCTAssertEqual(result.activeItems, [])
        let requests = await recorder.requests()
        XCTAssertEqual(requests.map(\.itemID), ["row-1"])
        let persistedFirst = try await fixture.store.getAgentJobItem(jobID: "job-1", itemID: "row-1")
        let first = try XCTUnwrap(persistedFirst)
        let persistedSecond = try await fixture.store.getAgentJobItem(jobID: "job-1", itemID: "row-2")
        let second = try XCTUnwrap(persistedSecond)
        XCTAssertEqual(first.status, .pending)
        XCTAssertEqual(second.status, .pending)
    }

    func testSpawnPendingItemsHandlesFailuresAndAssignmentRacesLikeRust() async throws {
        let fixture = try await makeStoreWithItems(["failed-spawn", "race-spawn"])
        let persistedJob = try await fixture.store.getAgentJob("job-1")
        let job = try XCTUnwrap(persistedJob)
        let raceThreadID = try ThreadId(string: "00000000-0000-4000-8000-000000000041")
        let shutdownThreads = ThreadRecorder()
        let store = fixture.store

        let result = try await AgentJobRuntime.spawnPendingItems(
            store: fixture.store,
            job: job,
            activeItems: [],
            maxConcurrency: 2,
            spawnWorker: { request in
                if request.itemID == "race-spawn" {
                    _ = try? await store.markAgentJobItemFailed(
                        jobID: "job-1",
                        itemID: "race-spawn",
                        errorMessage: "claimed elsewhere"
                    )
                    return .spawned(raceThreadID)
                }
                return .failed("boom")
            },
            shutdownThread: { threadID in
                await shutdownThreads.append(threadID)
            }
        )

        XCTAssertTrue(result.didProgress)
        XCTAssertEqual(result.activeItems, [])
        let persistedFailed = try await fixture.store.getAgentJobItem(jobID: "job-1", itemID: "failed-spawn")
        let failed = try XCTUnwrap(persistedFailed)
        XCTAssertEqual(failed.status, .failed)
        XCTAssertEqual(failed.lastError, "failed to spawn worker: boom")
        let persistedRaced = try await fixture.store.getAgentJobItem(jobID: "job-1", itemID: "race-spawn")
        let raced = try XCTUnwrap(persistedRaced)
        XCTAssertEqual(raced.status, .failed)
        XCTAssertEqual(raced.lastError, "claimed elsewhere")
        let recordedShutdownThreads = await shutdownThreads.values()
        XCTAssertEqual(recordedShutdownThreads, [raceThreadID])
    }

    func testRunAgentJobLoopCompletesAfterWorkerReportsResultLikeRust() async throws {
        let fixture = try await makeStoreWithItems(["row-1"])
        let threadID = try ThreadId(string: "00000000-0000-4000-8000-000000000051")
        let statusStore = AgentStatusStore(statuses: [threadID: .running])
        let shutdownThreads = ThreadRecorder()
        let store = fixture.store

        let finalJob = try await AgentJobRuntime.runAgentJobLoop(
            store: store,
            jobID: "job-1",
            maxConcurrency: 1,
            fileManager: .default,
            statusForThread: { threadID in
                await statusStore.status(for: threadID)
            },
            spawnWorker: { _ in
                .spawned(threadID)
            },
            shutdownThread: { threadID in
                await shutdownThreads.append(threadID)
            },
            waitWhenIdle: {
                _ = try? await store.reportAgentJobItemResult(
                    jobID: "job-1",
                    itemID: "row-1",
                    reportingThreadID: threadID.description,
                    resultJSON: .object(["ok": .bool(true)])
                )
                await statusStore.set(.completed(nil), for: threadID)
            }
        )

        XCTAssertEqual(finalJob.status, .completed)
        let persistedItem = try await store.getAgentJobItem(jobID: "job-1", itemID: "row-1")
        let item = try XCTUnwrap(persistedItem)
        XCTAssertEqual(item.status, .completed)
        XCTAssertEqual(item.resultJSON, .object(["ok": .bool(true)]))
        let recordedShutdownThreads = await shutdownThreads.values()
        XCTAssertEqual(recordedShutdownThreads, [threadID])
        let csv = try String(contentsOfFile: finalJob.outputCSVPath, encoding: .utf8)
        XCTAssertTrue(csv.contains(#"row-1,job-1,row-1,0,,completed,1,,"{""ok"":true}""#))
    }

    func testRunAgentJobLoopHonorsCancellationWithoutCompletingLikeRust() async throws {
        let fixture = try await makeStoreWithItems(["row-1"])
        let threadID = try ThreadId(string: "00000000-0000-4000-8000-000000000052")
        let markedRunning = try await fixture.store.markAgentJobItemRunningWithThread(
            jobID: "job-1",
            itemID: "row-1",
            threadID: threadID.description
        )
        XCTAssertTrue(markedRunning)
        _ = try await fixture.store.markAgentJobCancelled("job-1", errorMessage: "cancelled")
        let statusStore = AgentStatusStore(statuses: [threadID: .running])
        let store = fixture.store

        let finalJob = try await AgentJobRuntime.runAgentJobLoop(
            store: store,
            jobID: "job-1",
            maxConcurrency: 1,
            statusForThread: { threadID in
                await statusStore.status(for: threadID)
            },
            spawnWorker: { _ in
                .failed("should not spawn")
            },
            shutdownThread: { _ in },
            waitWhenIdle: {
                await statusStore.set(.completed(nil), for: threadID)
            }
        )

        XCTAssertEqual(finalJob.status, .cancelled)
        XCTAssertEqual(finalJob.lastError, "cancelled")
        let persistedItem = try await store.getAgentJobItem(jobID: "job-1", itemID: "row-1")
        let item = try XCTUnwrap(persistedItem)
        XCTAssertEqual(item.status, .failed)
        XCTAssertEqual(item.lastError, "worker finished without calling report_agent_job_result")
    }

    func testRunAgentJobLoopMarksJobFailedWhenAutoExportFailsLikeRust() async throws {
        let fixture = try await makeStoreWithItems(["row-1"])
        let directoryOutput = fixture.tempDirectory.url.appendingPathComponent("output-directory", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryOutput, withIntermediateDirectories: true)
        let store = try SQLiteAgentJobStore(databaseURL: fixture.tempDirectory.url.appendingPathComponent("failing-export.sqlite3"))
        _ = try await store.createAgentJob(
            params: AgentJobCreateParams(
                id: "job-export-fails",
                name: "job",
                instruction: "do it",
                outputSchemaJSON: nil,
                inputHeaders: ["id"],
                inputCSVPath: "/tmp/input.csv",
                outputCSVPath: directoryOutput.path,
                autoExport: true,
                maxRuntimeSeconds: nil
            ),
            items: []
        )
        try await store.markAgentJobRunning("job-export-fails")

        let finalJob = try await AgentJobRuntime.runAgentJobLoop(
            store: store,
            jobID: "job-export-fails",
            maxConcurrency: 1,
            statusForThread: { _ in .notFound },
            spawnWorker: { _ in .failed("should not spawn") },
            shutdownThread: { _ in }
        )

        XCTAssertEqual(finalJob.status, .failed)
        XCTAssertTrue(finalJob.lastError?.hasPrefix("auto-export failed: ") == true)
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
                outputCSVPath: tempDirectory.url.appendingPathComponent("output.csv").path,
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

    private func makeStoreWithItems(_ itemIDs: [String]) async throws -> AgentJobRuntimeStoreFixture {
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
                outputCSVPath: tempDirectory.url.appendingPathComponent("output.csv").path,
                autoExport: true,
                maxRuntimeSeconds: nil
            ),
            items: itemIDs.enumerated().map { index, itemID in
                AgentJobItemCreateParams(
                    itemID: itemID,
                    rowIndex: Int64(index),
                    sourceID: nil,
                    rowJSON: .object(["id": .string(itemID)])
                )
            }
        )
        try await store.markAgentJobRunning("job-1")
        return AgentJobRuntimeStoreFixture(store: store, tempDirectory: tempDirectory)
    }
}

private actor ThreadRecorder {
    private var recordedThreads: [ThreadId] = []

    func append(_ threadID: ThreadId) {
        recordedThreads.append(threadID)
    }

    func values() -> [ThreadId] {
        recordedThreads
    }
}

private actor SpawnRequestRecorder {
    private var recordedRequests: [AgentJobWorkerSpawnRequest] = []
    private var results: [AgentJobWorkerSpawnResult]

    init(results: [AgentJobWorkerSpawnResult]) {
        self.results = results
    }

    func spawn(_ request: AgentJobWorkerSpawnRequest) -> AgentJobWorkerSpawnResult {
        recordedRequests.append(request)
        guard !results.isEmpty else {
            return .failed("missing test spawn result")
        }
        return results.removeFirst()
    }

    func requests() -> [AgentJobWorkerSpawnRequest] {
        recordedRequests
    }
}

private actor AgentStatusStore {
    private var statuses: [ThreadId: AgentStatus]

    init(statuses: [ThreadId: AgentStatus]) {
        self.statuses = statuses
    }

    func set(_ status: AgentStatus, for threadID: ThreadId) {
        statuses[threadID] = status
    }

    func status(for threadID: ThreadId) -> AgentStatus {
        statuses[threadID] ?? .running
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
