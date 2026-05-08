import CodexCore
import XCTest

final class CloudTasksTests: XCTestCase {
    func testTaskIDAndTaskSummaryWireShapeMatchesRustSerde() throws {
        let summary = CloudTaskSummary(
            id: CloudTaskID("T-1000"),
            title: "Update README formatting",
            status: .ready,
            updatedAt: fixedCloudDate(),
            environmentID: "env-A",
            environmentLabel: "Env A",
            summary: CloudDiffSummary(filesChanged: 1, linesAdded: 2, linesRemoved: 1),
            attemptTotal: 2
        )

        try XCTAssertJSONObjectEqual(summary, [
            "id": "T-1000",
            "title": "Update README formatting",
            "status": "ready",
            "updated_at": "2026-05-08T12:34:56Z",
            "environment_id": "env-A",
            "environment_label": "Env A",
            "summary": [
                "files_changed": 1,
                "lines_added": 2,
                "lines_removed": 1
            ],
            "is_review": false,
            "attempt_total": 2
        ])

        let decoded = try JSONDecoder().decode(CloudTaskSummary.self, from: Data("""
        {
          "id": "T-1000",
          "title": "Review thing",
          "status": "pending",
          "updated_at": "2026-05-08T12:34:56.789Z",
          "environment_id": null,
          "environment_label": null,
          "summary": {
            "files_changed": 0,
            "lines_added": 0,
            "lines_removed": 0
          }
        }
        """.utf8))

        XCTAssertEqual(decoded.id, CloudTaskID("T-1000"))
        XCTAssertEqual(decoded.status, .pending)
        XCTAssertFalse(decoded.isReview)
        XCTAssertNil(decoded.attemptTotal)
    }

    func testApplyOutcomeDefaultsAndErrorDescriptionsMatchRust() throws {
        let decoded = try JSONDecoder().decode(CloudApplyOutcome.self, from: Data("""
        {
          "applied": true,
          "status": "success",
          "message": "ok"
        }
        """.utf8))

        XCTAssertEqual(decoded, CloudApplyOutcome(applied: true, status: .success, message: "ok"))
        try XCTAssertJSONObjectEqual(decoded, [
            "applied": true,
            "status": "success",
            "message": "ok",
            "skipped_paths": [],
            "conflict_paths": []
        ])
        XCTAssertEqual(String(describing: CloudTaskError.unimplemented("cloud")), "unimplemented: cloud")
        XCTAssertEqual(String(describing: CloudTaskError.http("bad")), "http error: bad")
        XCTAssertEqual(String(describing: CloudTaskError.io("disk")), "io error: disk")
        XCTAssertEqual(String(describing: CloudTaskError.message("plain")), "plain")
    }

    func testMockClientListTasksMatchesRustRowsAndDiffCounts() async throws {
        let client = CloudMockClient(now: fixedCloudDate)

        let global = try await client.listTasks(environment: nil).get()
        XCTAssertEqual(global.map(\.id), [CloudTaskID("T-1000"), CloudTaskID("T-1001"), CloudTaskID("T-1002")])
        XCTAssertEqual(global.map(\.title), [
            "Update README formatting",
            "Fix clippy warnings in core",
            "Add contributing guide"
        ])
        XCTAssertEqual(global.map(\.status), [.ready, .pending, .ready])
        XCTAssertEqual(global.map(\.environmentLabel), ["Global", "Global", "Global"])
        XCTAssertEqual(global.map(\.attemptTotal), [2, 1, 1])
        XCTAssertEqual(global[0].summary, CloudDiffSummary(filesChanged: 1, linesAdded: 2, linesRemoved: 1))
        XCTAssertEqual(global[1].summary, CloudDiffSummary(filesChanged: 1, linesAdded: 0, linesRemoved: 1))
        XCTAssertEqual(global[2].summary, CloudDiffSummary(filesChanged: 1, linesAdded: 3, linesRemoved: 0))

        let envB = try await client.listTasks(environment: "env-B").get()
        XCTAssertEqual(envB.map(\.id), [CloudTaskID("T-3000"), CloudTaskID("T-3001")])
        XCTAssertEqual(envB.map(\.environmentID), ["env-B", "env-B"])
        XCTAssertEqual(envB.map(\.environmentLabel), ["Env B", "Env B"])
    }

    func testMockClientTaskAccessAndApplyOutcomes() async throws {
        let client = CloudMockClient(now: fixedCloudDate)

        let summary = try await client.getTaskSummary(id: CloudTaskID("T-1000")).get()
        XCTAssertEqual(summary.id, CloudTaskID("T-1000"))

        let missing = await client.getTaskSummary(id: CloudTaskID("missing"))
        guard case let .failure(error) = missing else {
            return XCTFail("expected missing task failure")
        }
        XCTAssertEqual(error, .message("Task missing not found (mock)"))

        let diff = try await client.getTaskDiff(id: CloudTaskID("T-1000")).get()
        XCTAssertTrue(diff?.contains("Task: T-1000") == true)

        let messages = try await client.getTaskMessages(id: CloudTaskID("T-1000")).get()
        XCTAssertEqual(messages, ["Mock assistant output: this task contains no diff."])

        let taskText = try await client.getTaskText(id: CloudTaskID("T-1000")).get()
        XCTAssertEqual(
            taskText,
            CloudTaskText(
                prompt: "Why is there no diff?",
                messages: ["Mock assistant output: this task contains no diff."],
                turnID: "mock-turn",
                attemptPlacement: 0,
                attemptStatus: .completed
            )
        )

        let preflight = try await client.applyTaskPreflight(id: CloudTaskID("T-1000"), diffOverride: nil).get()
        XCTAssertEqual(
            preflight,
            CloudApplyOutcome(
                applied: false,
                status: .success,
                message: "Preflight passed for task T-1000 (mock)"
            )
        )

        let applied = try await client.applyTask(id: CloudTaskID("T-1000"), diffOverride: nil).get()
        XCTAssertEqual(
            applied,
            CloudApplyOutcome(
                applied: true,
                status: .success,
                message: "Applied task T-1000 locally (mock)"
            )
        )
    }

    func testMockClientSiblingAttemptsAndCreateTask() async throws {
        let client = CloudMockClient(now: fixedCloudDate)

        let emptyAttempts = try await client.listSiblingAttempts(task: CloudTaskID("T-1001"), turnID: "turn").get()
        XCTAssertEqual(emptyAttempts, [])

        let attempts = try await client.listSiblingAttempts(task: CloudTaskID("T-1000"), turnID: "turn").get()
        XCTAssertEqual(attempts.count, 1)
        XCTAssertEqual(attempts[0].turnID, "T-1000-attempt-2")
        XCTAssertEqual(attempts[0].attemptPlacement, 1)
        XCTAssertEqual(attempts[0].createdAt, fixedCloudDate())
        XCTAssertEqual(attempts[0].status, .completed)
        XCTAssertEqual(attempts[0].messages, ["Mock alternate attempt"])

        let created = try await client.createTask(
            environmentID: "env-A",
            prompt: "do it",
            gitRef: "main",
            qaMode: false,
            bestOfN: 1
        ).get()
        XCTAssertEqual(created, CloudCreatedTask(id: CloudTaskID("task_local_1778243696000")))
    }

    func testDiffCounterIgnoresHeadersAndHunks() {
        let counts = CloudMockClient.countFromUnified("""
        diff --git a/a b/a
        --- a/a
        +++ b/a
        @@ -1 +1,2 @@
        -old
        +new
        +again
        """)
        XCTAssertEqual(counts.added, 2)
        XCTAssertEqual(counts.removed, 1)
    }
}

private func fixedCloudDate() -> Date {
    Date(timeIntervalSince1970: 1_778_243_696)
}
