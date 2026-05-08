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
