import Foundation
import XCTest
@testable import CodexCore

final class AgentJobToolExecutorTests: XCTestCase {
    func testReportAgentJobResultRecordsAcceptedResultLikeRustHandler() async throws {
        let temp = try AgentJobToolExecutorTemporaryDirectory()
        let store = try SQLiteAgentJobStore(databaseURL: temp.url.appendingPathComponent("state.sqlite3"))
        _ = try await store.createAgentJob(
            params: AgentJobCreateParams(
                id: "job-1",
                name: "job",
                instruction: "do it",
                outputSchemaJSON: nil,
                inputHeaders: ["id"],
                inputCSVPath: "/tmp/input.csv",
                outputCSVPath: temp.url.appendingPathComponent("output.csv").path,
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

        let output = await AgentJobToolExecutor.execute(
            name: "report_agent_job_result",
            arguments: #"{"job_id":"job-1","item_id":"row-1","result":{"ok":true},"stop":true}"#,
            callID: "call-report",
            cwd: temp.url,
            context: AgentJobToolContext(
                store: store,
                reportingThreadID: "thread-1"
            )
        )

        guard case let .functionCallOutput(callID, payload) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-report")
        XCTAssertEqual(payload.success, true)
        XCTAssertEqual(payload.content, #"{"accepted":true}"#)

        let persistedItem = try await store.getAgentJobItem(jobID: "job-1", itemID: "row-1")
        let item = try XCTUnwrap(persistedItem)
        XCTAssertEqual(item.status, .completed)
        XCTAssertEqual(item.resultJSON, .object(["ok": .bool(true)]))
        let persistedJob = try await store.getAgentJob("job-1")
        let job = try XCTUnwrap(persistedJob)
        XCTAssertEqual(job.status, .cancelled)
        XCTAssertEqual(job.lastError, "cancelled by worker request")
    }

    func testAgentJobExecutorReturnsNilForUnownedTools() async {
        let output = await AgentJobToolExecutor.execute(
            name: "exec_command",
            arguments: #"{"cmd":"pwd"}"#,
            callID: "call-exec",
            cwd: URL(fileURLWithPath: "/tmp", isDirectory: true),
            context: nil
        )

        XCTAssertNil(output)
    }

    func testSpawnAgentsOnCSVRequiresRunnerCallbacks() async {
        let output = await AgentJobToolExecutor.execute(
            name: "spawn_agents_on_csv",
            arguments: #"{"csv_path":"input.csv","instruction":"check {id}"}"#,
            callID: "call-spawn",
            cwd: URL(fileURLWithPath: "/tmp", isDirectory: true),
            context: nil
        )

        guard case let .functionCallOutput(callID, payload) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-spawn")
        XCTAssertEqual(payload.success, false)
        XCTAssertEqual(payload.content, "unsupported tool: spawn_agents_on_csv")
    }
}

private final class AgentJobToolExecutorTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-agent-job-tool-executor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
