import CodexCore
import XCTest

final class AgentJobStoreTests: XCTestCase {
    func testCreatePersistsJobAndItemsWithRustOrderingAndFilters() async throws {
        let tempDirectory = try AgentJobStoreTemporaryDirectory()
        let store = try SQLiteAgentJobStore(databaseURL: tempDirectory.url.appendingPathComponent("state.sqlite3"))

        let job = try await store.createAgentJob(
            params: AgentJobCreateParams(
                id: "job-1",
                name: "CSV fanout",
                instruction: "Process each row",
                outputSchemaJSON: .object(["type": .string("object")]),
                inputHeaders: ["id", "path"],
                inputCSVPath: "/tmp/input.csv",
                outputCSVPath: "/tmp/output.csv",
                autoExport: true,
                maxRuntimeSeconds: 45
            ),
            items: [
                AgentJobItemCreateParams(
                    itemID: "row-2",
                    rowIndex: 2,
                    sourceID: "source-2",
                    rowJSON: .object(["id": .string("b")])
                ),
                AgentJobItemCreateParams(
                    itemID: "row-1",
                    rowIndex: 1,
                    sourceID: nil,
                    rowJSON: .object(["id": .string("a")])
                ),
            ]
        )

        XCTAssertEqual(job.id, "job-1")
        XCTAssertEqual(job.status, .pending)
        XCTAssertFalse(job.status.isFinal)
        XCTAssertEqual(job.outputSchemaJSON, .object(["type": .string("object")]))
        XCTAssertEqual(job.inputHeaders, ["id", "path"])
        XCTAssertEqual(job.maxRuntimeSeconds, 45)

        let persistedJob = try await store.getAgentJob("job-1")
        let unwrappedPersistedJob = try XCTUnwrap(persistedJob)
        XCTAssertEqual(unwrappedPersistedJob.name, "CSV fanout")
        XCTAssertEqual(unwrappedPersistedJob.autoExport, true)

        let items = try await store.listAgentJobItems(jobID: "job-1")
        XCTAssertEqual(items.map(\.itemID), ["row-1", "row-2"])
        XCTAssertEqual(items.map(\.status), [.pending, .pending])
        XCTAssertEqual(items[0].rowJSON, .object(["id": .string("a")]))
        XCTAssertNil(items[0].sourceID)
        XCTAssertEqual(items[1].sourceID, "source-2")

        let limited = try await store.listAgentJobItems(jobID: "job-1", status: .pending, limit: 1)
        XCTAssertEqual(limited.map(\.itemID), ["row-1"])
        let progress = try await store.getAgentJobProgress("job-1")
        XCTAssertEqual(progress, AgentJobProgress(
            pending: 2,
            running: 0,
            completed: 0,
            failed: 0
        ))
        let missingProgress = try await store.getAgentJobProgress("missing")
        XCTAssertEqual(missingProgress, AgentJobProgress(
            pending: 0,
            running: 0,
            completed: 0,
            failed: 0
        ))
    }

    func testJobLifecycleMatchesRustStatusGuards() async throws {
        let fixture = try await makeStoreWithSingleItem()
        let store = fixture.store

        try await store.markAgentJobRunning("job-1")
        let runningJob = try await store.getAgentJob("job-1")
        var job = try XCTUnwrap(runningJob)
        XCTAssertEqual(job.status, .running)
        XCTAssertNotNil(job.startedAt)
        XCTAssertNil(job.completedAt)

        let cancelled = try await store.markAgentJobCancelled("job-1", errorMessage: "user cancelled")
        XCTAssertTrue(cancelled)
        let cancelledJobAfterUpdate = try await store.getAgentJob("job-1")
        job = try XCTUnwrap(cancelledJobAfterUpdate)
        XCTAssertEqual(job.status, .cancelled)
        XCTAssertTrue(job.status.isFinal)
        XCTAssertEqual(job.lastError, "user cancelled")
        XCTAssertNotNil(job.completedAt)
        let isCancelled = try await store.isAgentJobCancelled("job-1")
        XCTAssertTrue(isCancelled)

        let cancelledAgain = try await store.markAgentJobCancelled("job-1", errorMessage: "second")
        XCTAssertFalse(cancelledAgain)
        let cancelledJob = try await store.getAgentJob("job-1")
        XCTAssertEqual(cancelledJob?.lastError, "user cancelled")
    }

    func testReportAgentJobItemResultCompletesItemAtomically() async throws {
        let fixture = try await makeStoreWithSingleItem()
        let store = fixture.store

        let markedRunning = try await store.markAgentJobItemRunningWithThread(
            jobID: "job-1",
            itemID: "row-1",
            threadID: "thread-1"
        )
        XCTAssertTrue(markedRunning)
        let reported = try await store.reportAgentJobItemResult(
            jobID: "job-1",
            itemID: "row-1",
            reportingThreadID: "thread-1",
            resultJSON: .object(["ok": .bool(true)])
        )

        XCTAssertTrue(reported)
        let reportedItem = try await store.getAgentJobItem(jobID: "job-1", itemID: "row-1")
        let item = try XCTUnwrap(reportedItem)
        XCTAssertEqual(item.status, .completed)
        XCTAssertEqual(item.resultJSON, .object(["ok": .bool(true)]))
        XCTAssertEqual(item.attemptCount, 1)
        XCTAssertNil(item.assignedThreadID)
        XCTAssertNil(item.lastError)
        XCTAssertNotNil(item.reportedAt)
        XCTAssertNotNil(item.completedAt)
        let progress = try await store.getAgentJobProgress("job-1")
        XCTAssertEqual(progress, AgentJobProgress(
            pending: 0,
            running: 0,
            completed: 1,
            failed: 0
        ))
    }

    func testLateReportAndCompletionWithoutResultAreRejectedLikeRust() async throws {
        let fixture = try await makeStoreWithSingleItem()
        let store = fixture.store

        let markedRunning = try await store.markAgentJobItemRunningWithThread(
            jobID: "job-1",
            itemID: "row-1",
            threadID: "thread-1"
        )
        XCTAssertTrue(markedRunning)
        let completedWithoutResult = try await store.markAgentJobItemCompleted(jobID: "job-1", itemID: "row-1")
        XCTAssertFalse(completedWithoutResult)
        let markedFailed = try await store.markAgentJobItemFailed(
            jobID: "job-1",
            itemID: "row-1",
            errorMessage: "boom"
        )
        XCTAssertTrue(markedFailed)

        let lateReport = try await store.reportAgentJobItemResult(
            jobID: "job-1",
            itemID: "row-1",
            reportingThreadID: "thread-1",
            resultJSON: .object(["late": .bool(true)])
        )
        XCTAssertFalse(lateReport)

        let failedItem = try await store.getAgentJobItem(jobID: "job-1", itemID: "row-1")
        let item = try XCTUnwrap(failedItem)
        XCTAssertEqual(item.status, .failed)
        XCTAssertNil(item.resultJSON)
        XCTAssertNil(item.assignedThreadID)
        XCTAssertEqual(item.lastError, "boom")
        let progress = try await store.getAgentJobProgress("job-1")
        XCTAssertEqual(progress, AgentJobProgress(
            pending: 0,
            running: 0,
            completed: 0,
            failed: 1
        ))
    }

    func testItemPendingAndThreadTransitionsOnlyApplyFromRunning() async throws {
        let fixture = try await makeStoreWithSingleItem()
        let store = fixture.store

        let setBeforeRunning = try await store.setAgentJobItemThread(
            jobID: "job-1",
            itemID: "row-1",
            threadID: "thread-1"
        )
        XCTAssertFalse(setBeforeRunning)
        let markedRunning = try await store.markAgentJobItemRunning(jobID: "job-1", itemID: "row-1")
        XCTAssertTrue(markedRunning)
        let setWhileRunning = try await store.setAgentJobItemThread(
            jobID: "job-1",
            itemID: "row-1",
            threadID: "thread-2"
        )
        XCTAssertTrue(setWhileRunning)
        let markedPending = try await store.markAgentJobItemPending(
            jobID: "job-1",
            itemID: "row-1",
            errorMessage: "retry"
        )
        XCTAssertTrue(markedPending)
        let pendingAgain = try await store.markAgentJobItemPending(
            jobID: "job-1",
            itemID: "row-1",
            errorMessage: "again"
        )
        XCTAssertFalse(pendingAgain)

        let pendingItem = try await store.getAgentJobItem(jobID: "job-1", itemID: "row-1")
        let item = try XCTUnwrap(pendingItem)
        XCTAssertEqual(item.status, .pending)
        XCTAssertEqual(item.attemptCount, 1)
        XCTAssertNil(item.assignedThreadID)
        XCTAssertEqual(item.lastError, "retry")
    }

    private func makeStoreWithSingleItem() async throws -> AgentJobStoreFixture {
        let tempDirectory = try AgentJobStoreTemporaryDirectory()
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
        return AgentJobStoreFixture(store: store, tempDirectory: tempDirectory)
    }
}

private struct AgentJobStoreFixture {
    let store: SQLiteAgentJobStore
    let tempDirectory: AgentJobStoreTemporaryDirectory
}

private final class AgentJobStoreTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-swift-agent-jobs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
