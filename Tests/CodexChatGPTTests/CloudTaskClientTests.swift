import CodexChatGPT
import CodexCore
import Foundation
import XCTest

final class CloudTaskClientTests: XCTestCase {
    func testApplyTaskLoadsAuthAndDelegatesThroughCloudHTTPClient() async throws {
        let cwd = URL(fileURLWithPath: "/tmp/codex-cloud-client-test", isDirectory: true)
        let token = AuthTokenData(
            idToken: "header.payload.signature",
            accessToken: "access-token",
            refreshToken: "refresh-token",
            accountID: "account-id"
        )
        let expectedDiff = """
        diff --git a/file.txt b/file.txt
        --- a/file.txt
        +++ b/file.txt
        @@ -1 +1 @@
        -before
        +after
        """ + "\n"
        let capturedRequest = AsyncCapture<URLRequest>()
        let capturedApply = AsyncCapture<CloudGitApplyRequest>()
        let transport = URLSessionAPITransport { request in
            await capturedRequest.set(request)
            return URLSessionTransportResponse(statusCode: 200, body: Data(Self.taskResponseJSON(diff: expectedDiff).utf8))
        }
        let client = CloudTaskClient(
            configuration: CloudTaskClientConfiguration(
                chatgptBaseURL: "https://chatgpt.com",
                codexHome: URL(fileURLWithPath: "/tmp/codex-home", isDirectory: true)
            ),
            transport: transport,
            tokenLoader: { token },
            currentDirectory: { cwd },
            applyGitPatch: { request in
                await capturedApply.set(request)
                return .success(CloudGitApplyResult(exitCode: 0, appliedPaths: ["file.txt"]))
            },
            errorLog: { _ in }
        )

        let outcome = try await client.applyTask(taskID: "task_123")

        XCTAssertTrue(outcome.applied)
        XCTAssertEqual(outcome.status, .success)
        XCTAssertEqual(outcome.message, "Applied task task_123 locally (1 files)")
        let request = await capturedRequest.value
        let apply = await capturedApply.value
        XCTAssertEqual(request?.httpMethod, "GET")
        XCTAssertEqual(request?.url?.absoluteString, "https://chatgpt.com/backend-api/wham/tasks/task_123")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "ChatGPT-Account-ID"), "account-id")
        XCTAssertEqual(apply?.cwd, cwd)
        XCTAssertEqual(apply?.diff, expectedDiff)
        XCTAssertEqual(apply?.preflight, false)
    }

    func testApplyTaskReportsMissingTokenBeforeNetwork() async {
        let client = CloudTaskClient(
            configuration: CloudTaskClientConfiguration(codexHome: URL(fileURLWithPath: "/tmp/codex-home", isDirectory: true)),
            transport: URLSessionAPITransport { _ in
                XCTFail("transport should not run without token data")
                return URLSessionTransportResponse(statusCode: 500)
            },
            tokenLoader: { nil },
            errorLog: { _ in }
        )

        await XCTAssertThrowsErrorAsync(try await client.applyTask(taskID: "task_123")) { error in
            XCTAssertEqual((error as? CloudTaskClientError)?.description, "ChatGPT token not available")
        }
    }

    func testApplyTaskReportsMissingAccountIDBeforeNetwork() async {
        let token = AuthTokenData(idToken: "id", accessToken: "access", refreshToken: "refresh", accountID: nil)
        let client = CloudTaskClient(
            configuration: CloudTaskClientConfiguration(codexHome: URL(fileURLWithPath: "/tmp/codex-home", isDirectory: true)),
            transport: URLSessionAPITransport { _ in
                XCTFail("transport should not run without account id")
                return URLSessionTransportResponse(statusCode: 500)
            },
            tokenLoader: { token },
            errorLog: { _ in }
        )

        await XCTAssertThrowsErrorAsync(try await client.applyTask(taskID: "task_123")) { error in
            XCTAssertEqual((error as? CloudTaskClientError)?.description, "ChatGPT account ID not available, please re-run `codex login`")
        }
    }

    func testApplyTaskThrowsWhenPatchDoesNotApply() async {
        let token = AuthTokenData(idToken: "id", accessToken: "access", refreshToken: "refresh", accountID: "account")
        let transport = URLSessionAPITransport { _ in
            URLSessionTransportResponse(statusCode: 200, body: Data(Self.taskResponseJSON(diff: Self.validDiff).utf8))
        }
        let client = CloudTaskClient(
            configuration: CloudTaskClientConfiguration(codexHome: URL(fileURLWithPath: "/tmp/codex-home", isDirectory: true)),
            transport: transport,
            tokenLoader: { token },
            applyGitPatch: { _ in
                .success(CloudGitApplyResult(exitCode: 1, skippedPaths: ["file.txt"], stderr: "patch failed"))
            },
            errorLog: { _ in }
        )

        await XCTAssertThrowsErrorAsync(try await client.applyTask(taskID: "task_123")) { error in
            XCTAssertEqual((error as? CloudTaskClientError)?.description, "Apply failed for task task_123 (applied=0, skipped=1, conflicts=0)")
        }
    }

    func testCreateTaskResolvesEnvironmentLabelBranchAndReturnsBrowserURL() async throws {
        let token = AuthTokenData(idToken: "id", accessToken: "access", refreshToken: "refresh", accountID: "account")
        let capturedRequests = AsyncCapture<[URLRequest]>()
        let storage = RequestStorage()
        let transport = URLSessionAPITransport { request in
            await storage.append(request)
            await capturedRequests.set(storage.requests)
            if request.url?.path == "/backend-api/wham/environments" {
                return URLSessionTransportResponse(statusCode: 200, body: Data("""
                [
                  { "id": "env-A", "label": "Env A", "is_pinned": true },
                  { "id": "env-B", "label": "Other" }
                ]
                """.utf8))
            }
            return URLSessionTransportResponse(statusCode: 200, body: Data(#"{"task":{"id":"task-new"}}"#.utf8))
        }
        let client = CloudTaskClient(
            configuration: CloudTaskClientConfiguration(
                chatgptBaseURL: "https://chatgpt.com",
                codexHome: URL(fileURLWithPath: "/tmp/codex-home", isDirectory: true)
            ),
            transport: transport,
            tokenLoader: { token },
            currentDirectory: { URL(fileURLWithPath: "/tmp/codex-cloud-client-test-nonrepo", isDirectory: true) },
            currentBranchName: { _ in "feature/current" },
            defaultBranchName: { _ in "main" },
            errorLog: { _ in }
        )

        let url = try await client.createTask(
            prompt: "Ship it",
            environment: "env a",
            attempts: 2
        )

        XCTAssertEqual(url, "https://chatgpt.com/codex/tasks/task-new")
        let requests = await capturedRequests.value ?? []
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].httpMethod, "GET")
        XCTAssertEqual(requests[0].url?.absoluteString, "https://chatgpt.com/backend-api/wham/environments")
        XCTAssertEqual(requests[1].httpMethod, "POST")
        XCTAssertEqual(requests[1].url?.absoluteString, "https://chatgpt.com/backend-api/wham/tasks")
        let body = try JSONDecoder().decode(JSONValue.self, from: try XCTUnwrap(requests[1].httpBody))
        XCTAssertEqual(body, .object([
            "new_task": .object([
                "environment_id": .string("env-A"),
                "branch": .string("feature/current"),
                "run_environment_in_qa_mode": .bool(false)
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
                ])
            ]),
            "metadata": .object(["best_of_n": .integer(2)])
        ]))
    }

    func testCreateTaskReportsAmbiguousEnvironmentLabelBeforeCreate() async {
        let token = AuthTokenData(idToken: "id", accessToken: "access", refreshToken: "refresh", accountID: "account")
        let requests = RequestStorage()
        let transport = URLSessionAPITransport { request in
            await requests.append(request)
            return URLSessionTransportResponse(statusCode: 200, body: Data("""
            [
              { "id": "env-A", "label": "Prod" },
              { "id": "env-B", "label": "prod" }
            ]
            """.utf8))
        }
        let client = CloudTaskClient(
            configuration: CloudTaskClientConfiguration(codexHome: URL(fileURLWithPath: "/tmp/codex-home", isDirectory: true)),
            transport: transport,
            tokenLoader: { token },
            currentDirectory: { URL(fileURLWithPath: "/tmp/codex-cloud-client-test-nonrepo", isDirectory: true) },
            currentBranchName: { _ in nil },
            defaultBranchName: { _ in nil },
            errorLog: { _ in }
        )

        await XCTAssertThrowsErrorAsync(try await client.createTask(
            prompt: "Ship it",
            environment: "prod",
            branch: "main"
        )) { error in
            XCTAssertEqual(
                (error as? CloudTaskClientError)?.description,
                "environment label 'prod' is ambiguous; run `codex cloud` to pick the desired environment id"
            )
        }
        let requestCount = await requests.requests.count
        XCTAssertEqual(requestCount, 1)
    }

    func testParseTaskIDAcceptsURLsAndRejectsEmptyInput() throws {
        XCTAssertEqual(try CloudTaskClient<URLSessionAPITransport>.parseTaskID(" task_123 ").rawValue, "task_123")
        XCTAssertEqual(
            try CloudTaskClient<URLSessionAPITransport>.parseTaskID("https://chatgpt.com/codex/tasks/task_123?foo=bar#frag").rawValue,
            "task_123"
        )
        XCTAssertThrowsError(try CloudTaskClient<URLSessionAPITransport>.parseTaskID("https://chatgpt.com/codex/tasks/")) { error in
            XCTAssertEqual((error as? CloudTaskClientError)?.description, "task id must not be empty")
        }
    }

    func testStatusFormatterMatchesCloudTasksCLIShape() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let summary = CloudTaskSummary(
            id: CloudTaskID("task_123"),
            title: "Fix the thing",
            status: .ready,
            updatedAt: now.addingTimeInterval(-125),
            environmentID: "env-A",
            environmentLabel: "Env A",
            summary: CloudDiffSummary(filesChanged: 2, linesAdded: 7, linesRemoved: 3)
        )

        XCTAssertEqual(CloudTaskCommandFormatter.statusLines(task: summary, now: now), [
            "[READY] Fix the thing",
            "Env A  •  2m ago",
            "+7/-3 • 2 files"
        ])
    }

    func testListFormatterMatchesCloudTasksCLIShapeAndJSON() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let task = CloudTaskSummary(
            id: CloudTaskID("task_123"),
            title: "Fix the thing",
            status: .ready,
            updatedAt: now.addingTimeInterval(-125),
            environmentID: nil,
            environmentLabel: "Env A",
            summary: CloudDiffSummary(filesChanged: 2, linesAdded: 7, linesRemoved: 3),
            attemptTotal: nil
        )

        XCTAssertEqual(CloudTaskCommandFormatter.listLines(
            tasks: [task],
            baseURL: "https://chatgpt.com/backend-api",
            now: now
        ), [
            "https://chatgpt.com/codex/tasks/task_123",
            "  [READY] Fix the thing",
            "  Env A  •  2m ago",
            "  +7/-3 • 2 files"
        ])

        let json = try CloudTaskCommandFormatter.listJSON(
            tasks: [task],
            cursor: "next",
            baseURL: "https://chatgpt.com/backend-api"
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(object["cursor"] as? String, "next")
        let tasks = try XCTUnwrap(object["tasks"] as? [[String: Any]])
        XCTAssertEqual(tasks[0]["id"] as? String, "task_123")
        XCTAssertEqual(tasks[0]["url"] as? String, "https://chatgpt.com/codex/tasks/task_123")
        XCTAssertEqual(tasks[0]["updated_at"] as? String, "2023-11-14T22:11:15Z")
        XCTAssertTrue(tasks[0]["environment_id"] is NSNull)
        XCTAssertTrue(tasks[0]["attempt_total"] is NSNull)
    }

    func testStatusFormatterUsesRustLocalDateShapeForOlderTasks() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let timestamp = try XCTUnwrap(calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: .current,
            year: 2024,
            month: 3,
            day: 5,
            hour: 9,
            minute: 7
        )))

        XCTAssertEqual(
            CloudTaskCommandFormatter.formatRelativeTime(reference: timestamp.addingTimeInterval(48 * 60 * 60), timestamp: timestamp),
            "Mar  5 09:07"
        )
    }

    func testTaskURLMatchesRustUtilityShapes() {
        XCTAssertEqual(
            CloudTaskCommandFormatter.taskURL(baseURL: "https://chatgpt.com", taskID: "task_123"),
            "https://chatgpt.com/codex/tasks/task_123"
        )
        XCTAssertEqual(
            CloudTaskCommandFormatter.taskURL(baseURL: "https://example.com/api/codex", taskID: "task_123"),
            "https://example.com/codex/tasks/task_123"
        )
        XCTAssertEqual(
            CloudTaskCommandFormatter.taskURL(baseURL: "https://example.com/codex", taskID: "task_123"),
            "https://example.com/codex/tasks/task_123"
        )
        XCTAssertEqual(
            CloudTaskCommandFormatter.taskURL(baseURL: "https://example.com", taskID: "task_123"),
            "https://example.com/codex/tasks/task_123"
        )
    }

    private static let validDiff = """
    diff --git a/file.txt b/file.txt
    --- a/file.txt
    +++ b/file.txt
    @@ -1 +1 @@
    -before
    +after
    """ + "\n"

    private static func taskResponseJSON(diff: String) -> String {
        let payload: [String: Any] = [
            "current_diff_task_turn": [
                "output_items": [
                    [
                        "type": "pr",
                        "output_diff": ["diff": diff]
                    ]
                ]
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}

private actor AsyncCapture<Value: Sendable> {
    private var storedValue: Value?

    var value: Value? {
        storedValue
    }

    func set(_ value: Value) {
        storedValue = value
    }
}

private actor RequestStorage {
    private var storedRequests: [URLRequest] = []

    var requests: [URLRequest] {
        storedRequests
    }

    func append(_ request: URLRequest) {
        storedRequests.append(request)
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("expected expression to throw", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
