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

    func testMockClientListEnvironmentsMatchesRustRows() async throws {
        let client = CloudMockClient(now: fixedCloudDate)

        let environments = try await client.listEnvironments().get()

        XCTAssertEqual(environments, [
            CloudEnvironmentRow(id: "env-A", label: "Env A", isPinned: true, repoHints: "mock/repo"),
            CloudEnvironmentRow(id: "env-B", label: "Env B")
        ])
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

    func testHTTPClientListTasksBuildsWhamRequestAndMapsRows() async throws {
        let transport = CloudCapturingTransport(executeResults: [
            .success(cloudResponse("""
            {
              "cursor": "next-page",
              "items": [
                {
                  "id": "T-9000",
                  "title": "Review branch",
                  "archived": false,
                  "has_unread_turn": true,
                  "updated_at": 1778243696.25,
                  "task_status_display": {
                    "environment_label": "Env A",
                    "latest_turn_status_display": {
                      "turn_status": "completed",
                      "diff_stats": {
                        "files_modified": 2,
                        "lines_added": 3,
                        "lines_removed": 1
                      },
                      "sibling_turn_ids": ["turn-2"]
                    }
                  },
                  "pull_requests": [{"id": "pr-1"}]
                }
              ]
            }
            """))
        ])
        let client = CloudHTTPClient(
            baseURL: "https://chatgpt.com/",
            transport: transport,
            auth: StaticAPIAuthProvider(bearerToken: "tok", accountID: "acct"),
            errorLog: { _ in }
        )

        let tasks = try await client.listTasks(environment: "env-A").get()

        XCTAssertEqual(transport.executeRequests.count, 1)
        let request = try XCTUnwrap(transport.executeRequests.first)
        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(
            request.url,
            "https://chatgpt.com/backend-api/wham/tasks/list?limit=20&task_filter=current&environment_id=env-A"
        )
        XCTAssertEqual(request.headers["user-agent"], "codex-cli")
        XCTAssertEqual(request.headers["authorization"], "Bearer tok")
        XCTAssertEqual(request.headers["ChatGPT-Account-ID"], "acct")
        XCTAssertNil(request.body)
        XCTAssertEqual(tasks, [
            CloudTaskSummary(
                id: CloudTaskID("T-9000"),
                title: "Review branch",
                status: .ready,
                updatedAt: Date(timeIntervalSince1970: 1_778_243_696.25),
                environmentID: nil,
                environmentLabel: "Env A",
                summary: CloudDiffSummary(filesChanged: 2, linesAdded: 3, linesRemoved: 1),
                isReview: true,
                attemptTotal: 2
            )
        ])

        let pagedTransport = CloudCapturingTransport(executeResults: [
            .success(cloudResponse(#"{"items":[],"cursor":"after"}"#))
        ])
        let pagedClient = CloudHTTPClient(
            baseURL: "https://chatgpt.com/",
            transport: pagedTransport,
            auth: StaticAPIAuthProvider(),
            errorLog: { _ in }
        )
        let page = try await pagedClient.listTasks(environment: "env-B", limit: 7, cursor: "before").get()
        XCTAssertEqual(page.cursor, "after")
        XCTAssertEqual(page.tasks, [])
        XCTAssertEqual(
            pagedTransport.executeRequests.first?.url,
            "https://chatgpt.com/backend-api/wham/tasks/list?limit=7&task_filter=current&cursor=before&environment_id=env-B"
        )
    }

    func testHTTPClientListTasksRequiresRustOpenAPIBooleanFields() async throws {
        let transport = CloudCapturingTransport(executeResults: [
            .success(cloudResponse("""
            {
              "items": [
                {
                  "id": "T-missing",
                  "title": "Missing required booleans"
                }
              ]
            }
            """))
        ])
        let client = CloudHTTPClient(
            baseURL: "https://chatgpt.com/",
            transport: transport,
            auth: StaticAPIAuthProvider(),
            errorLog: { _ in }
        )

        let result = await client.listTasks(environment: nil, limit: 20, cursor: nil)

        guard case let .failure(error) = result else {
            return XCTFail("expected Rust-style missing-field decode failure")
        }
        XCTAssertTrue(String(describing: error).contains("keyNotFound"))
        XCTAssertTrue(String(describing: error).contains("archived"))
    }

    func testHTTPClientListEnvironmentsMergesRepoAndGlobalRows() async throws {
        let transport = CloudCapturingTransport(executeResults: [
            .success(cloudResponse("""
            [
              { "id": "env-B", "label": "Repo Env", "is_pinned": true, "task_count": 7 }
            ]
            """)),
            .success(cloudResponse("""
            [
              { "id": "env-A", "label": "Alpha", "is_pinned": false },
              { "id": "env-B", "label": "Repo Env Global", "is_pinned": false }
            ]
            """))
        ])
        let client = CloudHTTPClient(
            baseURL: "https://chatgpt.com",
            transport: transport,
            auth: StaticAPIAuthProvider(bearerToken: "tok", accountID: "acct"),
            gitOriginURLs: { ["git@github.com:owner/repo.git"] },
            errorLog: { _ in }
        )

        let environments = try await client.listEnvironments().get()

        XCTAssertEqual(transport.executeRequests.map(\.url), [
            "https://chatgpt.com/backend-api/wham/environments/by-repo/github/owner/repo",
            "https://chatgpt.com/backend-api/wham/environments"
        ])
        XCTAssertEqual(transport.executeRequests.map(\.method), [.get, .get])
        XCTAssertEqual(transport.executeRequests[0].headers["authorization"], "Bearer tok")
        XCTAssertEqual(transport.executeRequests[0].headers["ChatGPT-Account-ID"], "acct")
        XCTAssertEqual(environments, [
            CloudEnvironmentRow(id: "env-B", label: "Repo Env", isPinned: true, repoHints: "owner/repo"),
            CloudEnvironmentRow(id: "env-A", label: "Alpha", isPinned: false, repoHints: nil)
        ])
    }

    func testHTTPClientTaskDetailsMapsSummaryDiffMessagesAndText() async throws {
        let body = cloudDetailsBody()
        let transport = CloudCapturingTransport(executeResults: [
            .success(cloudResponse(body)),
            .success(cloudResponse(body)),
            .success(cloudResponse(body)),
            .success(cloudResponse(body))
        ])
        let client = CloudHTTPClient(
            baseURL: "https://example.com",
            transport: transport,
            auth: StaticAPIAuthProvider(),
            now: fixedCloudDate,
            errorLog: { _ in }
        )

        let summary = try await client.getTaskSummary(id: CloudTaskID("T-9000")).get()
        XCTAssertEqual(summary.id, CloudTaskID("T-9000"))
        XCTAssertEqual(summary.title, "Detailed task")
        XCTAssertEqual(summary.status, .pending)
        XCTAssertEqual(summary.updatedAt, Date(timeIntervalSince1970: 1_778_243_000))
        XCTAssertEqual(summary.environmentID, "env-A")
        XCTAssertEqual(summary.environmentLabel, "Env A")
        XCTAssertEqual(summary.summary, CloudDiffSummary(filesChanged: 1, linesAdded: 2, linesRemoved: 1))
        XCTAssertTrue(summary.isReview)
        XCTAssertEqual(summary.attemptTotal, 3)

        let diff = try await client.getTaskDiff(id: CloudTaskID("T-9000")).get()
        XCTAssertTrue(diff?.contains("diff --git") == true)

        let messages = try await client.getTaskMessages(id: CloudTaskID("T-9000")).get()
        XCTAssertEqual(messages, ["Assistant response"])

        let text = try await client.getTaskText(id: CloudTaskID("T-9000")).get()
        XCTAssertEqual(text.prompt, "First line\n\nSecond line")
        XCTAssertEqual(text.messages, ["Assistant response"])
        XCTAssertEqual(text.turnID, "turn-1")
        XCTAssertEqual(text.siblingTurnIDs, ["turn-2"])
        XCTAssertEqual(text.attemptPlacement, 0)
        XCTAssertEqual(text.attemptStatus, .inProgress)

        XCTAssertEqual(transport.executeRequests.map(\.url), [
            "https://example.com/api/codex/tasks/T-9000",
            "https://example.com/api/codex/tasks/T-9000",
            "https://example.com/api/codex/tasks/T-9000",
            "https://example.com/api/codex/tasks/T-9000"
        ])
    }

    func testHTTPClientCreateTaskPostsRustBodyAndDecodesTaskID() async throws {
        let transport = CloudCapturingTransport(executeResults: [
            .success(cloudResponse(#"{"task":{"id":"task-new"}}"#))
        ])
        let client = CloudHTTPClient(
            baseURL: "https://example.com",
            transport: transport,
            auth: StaticAPIAuthProvider(bearerToken: "tok"),
            environment: { ["CODEX_STARTING_DIFF": "diff --git a/a b/a\n"] },
            errorLog: { _ in }
        )

        let created = try await client.createTask(
            environmentID: "env-A",
            prompt: "Ship it",
            gitRef: "main",
            qaMode: true,
            bestOfN: 3
        ).get()

        XCTAssertEqual(created, CloudCreatedTask(id: CloudTaskID("task-new")))
        let request = try XCTUnwrap(transport.executeRequests.first)
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.url, "https://example.com/api/codex/tasks")
        XCTAssertEqual(request.headers["content-type"], "application/json")
        XCTAssertEqual(request.headers["authorization"], "Bearer tok")
        XCTAssertEqual(request.body, .object([
            "new_task": .object([
                "environment_id": .string("env-A"),
                "branch": .string("main"),
                "run_environment_in_qa_mode": .bool(true)
            ]),
            "input_items": .array([
                .object([
                    "type": .string("message"),
                    "role": .string("user"),
                    "content": .array([
                        .object([
                            "content_type": .string("text"),
                            "text": .string("Ship it")
                        ])
                    ])
                ]),
                .object([
                    "type": .string("pre_apply_patch"),
                    "output_diff": .object(["diff": .string("diff --git a/a b/a\n")])
                ])
            ]),
            "metadata": .object(["best_of_n": .integer(3)])
        ]))
    }

    func testHTTPClientSiblingAttemptsSortAndMapTurnPayloads() async throws {
        let transport = CloudCapturingTransport(executeResults: [
            .success(cloudResponse("""
            {
              "sibling_turns": [
                {
                  "id": "turn-b",
                  "attempt_placement": 2,
                  "created_at": 1778243697,
                  "turn_status": "completed",
                  "output_items": [
                    {
                      "type": "pr",
                      "output_diff": { "diff": "diff --git a/b b/b\\n" }
                    }
                  ]
                },
                {
                  "id": "turn-a",
                  "attempt_placement": 1,
                  "created_at": 1778243696,
                  "turn_status": "failed",
                  "output_items": [
                    {
                      "type": "message",
                      "content": [{ "content_type": "text", "text": "failed text" }]
                    }
                  ]
                }
              ]
            }
            """))
        ])
        let client = CloudHTTPClient(
            baseURL: "https://chat.openai.com",
            transport: transport,
            auth: StaticAPIAuthProvider(),
            errorLog: { _ in }
        )

        let attempts = try await client.listSiblingAttempts(task: CloudTaskID("T-1"), turnID: "turn-root").get()

        XCTAssertEqual(transport.executeRequests.first?.url, "https://chat.openai.com/backend-api/wham/tasks/T-1/turns/turn-root/sibling_turns")
        XCTAssertEqual(attempts.map(\.turnID), ["turn-a", "turn-b"])
        XCTAssertEqual(attempts[0].status, .failed)
        XCTAssertEqual(attempts[0].messages, ["failed text"])
        XCTAssertNil(attempts[0].diff)
        XCTAssertEqual(attempts[1].status, .completed)
        XCTAssertEqual(attempts[1].diff, "diff --git a/b b/b\n")
    }

    func testHTTPClientApplyUsesInjectedGitApplyAndRejectsNonUnifiedDiff() async throws {
        let capture = CloudApplyCapture()
        let client = CloudHTTPClient(
            baseURL: "https://example.com",
            transport: CloudCapturingTransport(),
            auth: StaticAPIAuthProvider(),
            currentDirectory: { URL(fileURLWithPath: "/tmp/project", isDirectory: true) },
            applyGitPatch: { request in
                capture.requests.append(request)
                return .success(CloudGitApplyResult(
                    exitCode: 1,
                    appliedPaths: ["Sources/A.swift"],
                    skippedPaths: ["README.md"],
                    conflictedPaths: ["Package.swift"],
                    stdout: "out",
                    stderr: "err",
                    commandForLog: "git apply --check"
                ))
            },
            errorLog: { _ in }
        )

        let nonUnified = try await client.applyTask(id: CloudTaskID("T-1"), diffOverride: "*** Begin Patch").get()
        XCTAssertEqual(
            nonUnified,
            CloudApplyOutcome(
                applied: false,
                status: .error,
                message: "Expected unified git diff; backend returned an incompatible format."
            )
        )
        XCTAssertTrue(capture.requests.isEmpty)

        let partial = try await client.applyTaskPreflight(
            id: CloudTaskID("T-1"),
            diffOverride: """
            diff --git a/a b/a
            --- a/a
            +++ b/a
            @@ -1 +1 @@
            -old
            +new
            """
        ).get()

        XCTAssertEqual(capture.requests.count, 1)
        XCTAssertEqual(capture.requests[0].cwd.path, "/tmp/project")
        XCTAssertTrue(capture.requests[0].preflight)
        XCTAssertFalse(capture.requests[0].revert)
        XCTAssertEqual(
            partial,
            CloudApplyOutcome(
                applied: false,
                status: .partial,
                message: "Preflight: patch does not fully apply for task T-1 (applied=1, skipped=1, conflicts=1)",
                skippedPaths: ["README.md"],
                conflictPaths: ["Package.swift"]
            )
        )
    }

    func testHTTPClientApplyErrorLogMatchesRustPatchSummaryAndStatus() async throws {
        let diff = "diff --git a/unicode.txt b/unicode.txt\n--- a/unicode.txt\n+++ b/unicode.txt\n@@ -1 +1 @@\n-cafe\n+cafeé\n"
        let logs = CloudLogCapture()
        let client = CloudHTTPClient(
            baseURL: "https://example.com",
            transport: CloudCapturingTransport(),
            auth: StaticAPIAuthProvider(),
            currentDirectory: { URL(fileURLWithPath: "/tmp/project", isDirectory: true) },
            applyGitPatch: { request in
                XCTAssertEqual(request.diff, diff)
                return .success(CloudGitApplyResult(
                    exitCode: 1,
                    appliedPaths: ["unicode.txt"],
                    skippedPaths: [],
                    conflictedPaths: ["unicode.txt"],
                    stdout: "out",
                    stderr: "érr",
                    commandForLog: "git apply --check"
                ))
            },
            errorLog: { logs.messages.append($0) }
        )

        let outcome = try await client.applyTaskPreflight(id: CloudTaskID("T-log"), diffOverride: diff).get()

        XCTAssertEqual(outcome.status, .partial)
        let log = try XCTUnwrap(logs.messages.last)
        XCTAssertTrue(log.contains("apply_result: mode=preflight id=T-log status=Partial applied=1 skipped=0 conflicts=1 cmd=git apply --check"))
        XCTAssertTrue(log.contains("stderr_tail=\nérr"))
        XCTAssertTrue(log.contains("patch_summary: kind=git-diff lines=6 chars=\(diff.utf8.count) cwd=/tmp/project ; head=\n\(String(diff.dropLast()))"))
    }
}

private func fixedCloudDate() -> Date {
    Date(timeIntervalSince1970: 1_778_243_696)
}

private func cloudResponse(
    _ body: String,
    statusCode: Int = 200,
    headers: [String: String] = ["content-type": "application/json"]
) -> APIResponse {
    APIResponse(statusCode: statusCode, headers: headers, body: Data(body.utf8))
}

private func cloudDetailsBody() -> String {
    """
    {
      "task": {
        "id": "T-9000",
        "title": "Detailed task",
        "created_at": 1778243000,
        "environment_id": "env-A",
        "is_review": true
      },
      "task_status_display": {
        "environment_label": "Env A",
        "latest_turn_status_display": {
          "turn_status": "in_progress",
          "updated_at": 1778243696,
          "sibling_turn_ids": ["turn-2", "turn-3"]
        }
      },
      "current_user_turn": {
        "input_items": [
          {
            "type": "message",
            "role": "user",
            "content": [
              { "content_type": "text", "text": "First line" },
              { "content_type": "text", "text": "Second line" }
            ]
          }
        ]
      },
      "current_assistant_turn": {
        "id": "turn-1",
        "attempt_placement": 0,
        "turn_status": "in_progress",
        "sibling_turn_ids": ["turn-2"],
        "output_items": [
          {
            "type": "message",
            "content": [{ "content_type": "text", "text": "Assistant response" }]
          },
          {
            "type": "output_diff",
            "diff": "diff --git a/README.md b/README.md\\n--- a/README.md\\n+++ b/README.md\\n@@ -1,2 +1,3 @@\\n Intro\\n-Hello\\n+Hello, world!\\n+Task: T-9000\\n"
          }
        ]
      }
    }
    """
}

private final class CloudCapturingTransport: APITransport, @unchecked Sendable {
    private var executeResults: [Result<APIResponse, TransportError>]
    private(set) var executeRequests: [APIRequest] = []

    init(executeResults: [Result<APIResponse, TransportError>] = []) {
        self.executeResults = executeResults
    }

    func execute(_ request: APIRequest) async -> Result<APIResponse, TransportError> {
        executeRequests.append(request)
        guard !executeResults.isEmpty else {
            return .failure(.build("missing execute result"))
        }
        return executeResults.removeFirst()
    }

    func stream(_ request: APIRequest) async -> Result<APIStreamResponse, TransportError> {
        .failure(.build("unexpected stream request: \(request.url)"))
    }
}

private final class CloudApplyCapture: @unchecked Sendable {
    var requests: [CloudGitApplyRequest] = []
}

private final class CloudLogCapture: @unchecked Sendable {
    var messages: [String] = []
}
