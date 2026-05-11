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
}
