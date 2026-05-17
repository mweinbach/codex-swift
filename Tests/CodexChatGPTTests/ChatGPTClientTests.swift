import CodexChatGPT
import CodexCore
import Foundation
import XCTest

final class ChatGPTClientTests: XCTestCase {
    func testGetTaskSendsRustMatchingRequestHeadersAndDecodesResponse() async throws {
        let token = AuthTokenData(
            idToken: "header.payload.signature",
            accessToken: "access-token",
            refreshToken: "refresh-token",
            accountID: "account-id"
        )
        var capturedRequest: URLRequest?
        let client = ChatGPTTaskClient(
            configuration: ChatGPTClientConfiguration(
                chatgptBaseURL: ChatGPTClientConfiguration.defaultBaseURL,
                codexHome: URL(fileURLWithPath: "/tmp/codex-home", isDirectory: true)
            ),
            transport: { request in
                capturedRequest = request
                return ChatGPTHTTPResponse(statusCode: 200, body: Data(Self.taskResponseJSON.utf8))
            },
            tokenLoader: { token }
        )

        let response = try await client.getTask(taskID: "task_123")

        XCTAssertEqual(try CodexTaskDiffApplier.diff(from: response), "diff --git a/file.txt b/file.txt\n")
        XCTAssertEqual(capturedRequest?.httpMethod, "GET")
        XCTAssertEqual(capturedRequest?.url?.absoluteString, "https://chatgpt.com/backend-api//wham/tasks/task_123")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "chatgpt-account-id"), "account-id")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "OAI-Product-Sku"), "codex")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testGetTaskLoadsFileBackedAuthJSONByDefault() async throws {
        let dir = try ChatGPTTemporaryDirectory()
        let jwt = Self.fakeJWT()
        try """
        {
          "tokens": {
            "id_token": "\(jwt)",
            "access_token": "file-access-token",
            "refresh_token": "file-refresh-token",
            "account_id": "file-account-id"
          },
          "last_refresh": "\(Self.recentLastRefresh())"
        }
        """.write(to: dir.url.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)

        var authorization: String?
        var accountID: String?
        let client = ChatGPTTaskClient(
            configuration: ChatGPTClientConfiguration(chatgptBaseURL: "https://example.test/backend", codexHome: dir.url),
            transport: { request in
                authorization = request.value(forHTTPHeaderField: "Authorization")
                accountID = request.value(forHTTPHeaderField: "chatgpt-account-id")
                return ChatGPTHTTPResponse(statusCode: 200, body: Data(Self.taskResponseJSON.utf8))
            }
        )

        _ = try await client.getTask(taskID: "task_123")

        XCTAssertEqual(authorization, "Bearer file-access-token")
        XCTAssertEqual(accountID, "file-account-id")
    }

    func testGetTaskReportsMissingTokenLikeRustClient() async {
        let client = ChatGPTTaskClient(
            configuration: ChatGPTClientConfiguration(codexHome: URL(fileURLWithPath: "/tmp/codex-home", isDirectory: true)),
            transport: { _ in
                XCTFail("transport should not run without token data")
                return ChatGPTHTTPResponse(statusCode: 500, body: Data())
            },
            tokenLoader: { nil }
        )

        await XCTAssertThrowsErrorAsync(try await client.getTask(taskID: "task_123")) { error in
            XCTAssertEqual((error as? ChatGPTClientError)?.description, "ChatGPT token not available")
        }
    }

    func testGetTaskReportsMissingAccountIDLikeRustClient() async {
        let token = AuthTokenData(idToken: "id", accessToken: "access", refreshToken: "refresh", accountID: nil)
        let client = ChatGPTTaskClient(
            configuration: ChatGPTClientConfiguration(codexHome: URL(fileURLWithPath: "/tmp/codex-home", isDirectory: true)),
            transport: { _ in
                XCTFail("transport should not run without account id")
                return ChatGPTHTTPResponse(statusCode: 500, body: Data())
            },
            tokenLoader: { token }
        )

        await XCTAssertThrowsErrorAsync(try await client.getTask(taskID: "task_123")) { error in
            XCTAssertEqual((error as? ChatGPTClientError)?.description, "ChatGPT account ID not available, please re-run `codex login`")
        }
    }

    func testGetTaskReportsHTTPStatusAndBody() async {
        let token = AuthTokenData(idToken: "id", accessToken: "access", refreshToken: "refresh", accountID: "account")
        let client = ChatGPTTaskClient(
            configuration: ChatGPTClientConfiguration(codexHome: URL(fileURLWithPath: "/tmp/codex-home", isDirectory: true)),
            transport: { _ in
                ChatGPTHTTPResponse(statusCode: 404, body: Data("missing task".utf8))
            },
            tokenLoader: { token }
        )

        await XCTAssertThrowsErrorAsync(try await client.getTask(taskID: "missing")) { error in
            XCTAssertEqual((error as? ChatGPTClientError)?.description, "Request failed with status 404 Not Found: missing task")
        }
    }

    func testGetTaskReportsDecodeFailure() async {
        let token = AuthTokenData(idToken: "id", accessToken: "access", refreshToken: "refresh", accountID: "account")
        let client = ChatGPTTaskClient(
            configuration: ChatGPTClientConfiguration(codexHome: URL(fileURLWithPath: "/tmp/codex-home", isDirectory: true)),
            transport: { _ in
                ChatGPTHTTPResponse(statusCode: 200, body: Data(#"{"current_diff_task_turn":42}"#.utf8))
            },
            tokenLoader: { token }
        )

        await XCTAssertThrowsErrorAsync(try await client.getTask(taskID: "task_123")) { error in
            XCTAssertTrue((error as? ChatGPTClientError)?.description.hasPrefix("Failed to parse JSON response:") == true)
        }
    }

    private static let taskResponseJSON = #"""
    {
      "current_diff_task_turn": {
        "output_items": [
          {
            "type": "pr",
            "output_diff": {
              "diff": "diff --git a/file.txt b/file.txt\n"
            }
          }
        ]
      }
    }
    """#

    private static func recentLastRefresh() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private static func fakeJWT() -> String {
        let header: [String: Any] = ["alg": "none", "typ": "JWT"]
        let payload: [String: Any] = [
            "email": "user@example.com",
            "https://api.openai.com/auth": [
                "chatgpt_plan_type": "pro",
                "chatgpt_account_id": "jwt-account-id"
            ]
        ]
        return [
            base64URL(header),
            base64URL(payload),
            base64URL(Data("sig".utf8))
        ].joined(separator: ".")
    }

    private static func base64URL(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return base64URL(data)
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
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

private final class ChatGPTTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
