@testable import CodexAppServer
import CodexCore
import Foundation
import XCTest

final class CodexAppServerTests: XCTestCase {
    func testThreadListReturnsRolloutsWithRustAppServerShape() throws {
        let temp = try TemporaryDirectory()
        let newestID = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-02T12-00-00",
            timestamp: "2025-01-02T12:00:00Z",
            preview: "Hello A",
            provider: "openai"
        )
        _ = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-01T12-00-00",
            timestamp: "2025-01-01T12:00:00Z",
            preview: "Hello B",
            provider: "other"
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"thread/list","params":{"limit":1,"modelProviders":["openai"]}}"#,
            codexHome: temp.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let data = try XCTUnwrap(result["data"] as? [[String: Any]])
        XCTAssertEqual(data.count, 1)
        XCTAssertNotNil(result["nextCursor"] as? String)
        XCTAssertEqual(data[0]["id"] as? String, newestID)
        XCTAssertEqual(data[0]["preview"] as? String, "Hello A")
        XCTAssertEqual(data[0]["modelProvider"] as? String, "openai")
        XCTAssertEqual(data[0]["createdAt"] as? Int, 1_735_819_200)
        XCTAssertEqual(data[0]["cwd"] as? String, "/")
        XCTAssertEqual(data[0]["cliVersion"] as? String, "0.0.0")
        XCTAssertEqual(data[0]["source"] as? String, "cli")
        XCTAssertEqual((data[0]["turns"] as? [Any])?.count, 0)
    }

    func testLegacyListConversationsUsesPageSizeCursorAndDefaultProvider() throws {
        let temp = try TemporaryDirectory()
        _ = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-02T12-00-00",
            timestamp: "2025-01-02T12:00:00Z",
            preview: "Hello A",
            provider: nil
        )
        _ = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-01T12-00-00",
            timestamp: "2025-01-01T12:00:00Z",
            preview: "Hello B",
            provider: "other"
        )

        let first = try appServerResponse(
            #"{"id":"list","method":"listConversations","params":{"pageSize":1,"modelProviders":["openai"]}}"#,
            codexHome: temp.url
        )
        let firstResult = try XCTUnwrap(first["result"] as? [String: Any])
        let firstItems = try XCTUnwrap(firstResult["items"] as? [[String: Any]])
        XCTAssertEqual(firstItems.count, 1)
        XCTAssertEqual(firstItems[0]["preview"] as? String, "Hello A")
        XCTAssertEqual(firstItems[0]["modelProvider"] as? String, "openai")
        XCTAssertEqual(firstItems[0]["source"] as? String, "cli")
        XCTAssertNotNil(firstResult["nextCursor"] as? String)

        let second = try appServerResponse(
            #"{"id":"list2","method":"listConversations","params":{"pageSize":1,"modelProviders":["openai"],"cursor":"\#(firstResult["nextCursor"] as! String)"}}"#,
            codexHome: temp.url
        )
        let secondResult = try XCTUnwrap(second["result"] as? [String: Any])
        let secondItems = try XCTUnwrap(secondResult["items"] as? [[String: Any]])
        XCTAssertTrue(secondItems.isEmpty)
        XCTAssertNil(secondResult["nextCursor"])
    }

    func testListingWithoutProviderFilterDefaultsToConfiguredProvider() throws {
        let temp = try TemporaryDirectory()
        _ = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-03T12-00-00",
            timestamp: "2025-01-03T12:00:00Z",
            preview: "Other provider",
            provider: "other"
        )
        _ = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-02T12-00-00",
            timestamp: "2025-01-02T12:00:00Z",
            preview: "Default provider",
            provider: "openai"
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"thread/list","params":{}}"#,
            codexHome: temp.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let data = try XCTUnwrap(result["data"] as? [[String: Any]])
        XCTAssertEqual(data.map { $0["preview"] as? String }, ["Default provider"])
    }

    func testEmptyProviderFilterListsAllInteractiveProviders() throws {
        let temp = try TemporaryDirectory()
        _ = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-03T12-00-00",
            timestamp: "2025-01-03T12:00:00Z",
            preview: "Other provider",
            provider: "other"
        )
        _ = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-02T12-00-00",
            timestamp: "2025-01-02T12:00:00Z",
            preview: "Default provider",
            provider: "openai"
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"thread/list","params":{"modelProviders":[]}}"#,
            codexHome: temp.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let data = try XCTUnwrap(result["data"] as? [[String: Any]])
        XCTAssertEqual(data.map { $0["preview"] as? String }, ["Other provider", "Default provider"])
    }

    func testThreadListFiltersToInteractiveSourcesAndClampsLimit() throws {
        let temp = try TemporaryDirectory()
        _ = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-03T12-00-00",
            timestamp: "2025-01-03T12:00:00Z",
            preview: "Exec session",
            provider: "openai",
            source: .exec
        )
        _ = try writeRollout(
            codexHome: temp.url,
            filenameTimestamp: "2025-01-02T12-00-00",
            timestamp: "2025-01-02T12:00:00Z",
            preview: "Interactive session",
            provider: "openai",
            source: .cli
        )

        let response = try appServerResponse(
            #"{"id":1,"method":"thread/list","params":{"limit":0}}"#,
            codexHome: temp.url
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let data = try XCTUnwrap(result["data"] as? [[String: Any]])
        XCTAssertEqual(data.map { $0["preview"] as? String }, ["Interactive session"])
    }

    func testInitializeUsesAppServerJSONRPCShapeWithoutJsonrpcField() throws {
        let temp = try TemporaryDirectory()
        let response = try appServerResponse(
            #"{"id":9,"method":"initialize","params":{"clientInfo":{"name":"test","version":"0"}}}"#,
            codexHome: temp.url
        )
        XCTAssertEqual(response["id"] as? Int, 9)
        XCTAssertNil(response["jsonrpc"])
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["userAgent"] as? String, "codex_cli_swift/0.0.0")
    }

    private func appServerResponse(_ line: String, codexHome: URL) throws -> [String: Any] {
        let data = try XCTUnwrap(CodexAppServer.processLine(
            Data(line.utf8),
            configuration: CodexAppServerConfiguration(codexHome: codexHome)
        ))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @discardableResult
    private func writeRollout(
        codexHome: URL,
        filenameTimestamp: String,
        timestamp: String,
        preview: String,
        provider: String?,
        source: SessionSource = .cli
    ) throws -> String {
        let id = UUID().uuidString.lowercased()
        let path = codexHome
            .appendingPathComponent("sessions/2025/01/02", isDirectory: true)
            .appendingPathComponent("rollout-\(filenameTimestamp)-\(id).jsonl", isDirectory: false)
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let conversationID = try ConversationId(string: id)
        let meta = RolloutLine(
            timestamp: timestamp,
            item: .sessionMeta(SessionMetaLine(meta: SessionMeta(
                id: conversationID,
                timestamp: timestamp,
                cwd: "/",
                originator: "codex_cli_rs",
                cliVersion: "0.0.0",
                source: source,
                modelProvider: provider
            )))
        )
        let user = RolloutLine(
            timestamp: timestamp,
            item: .eventMsg(.userMessage(UserMessageEvent(message: preview)))
        )
        let encoder = JSONEncoder()
        let lines = try [meta, user].map { line in
            String(data: try encoder.encode(line), encoding: .utf8)!
        }.joined(separator: "\n")
        try lines.write(to: path, atomically: true, encoding: .utf8)
        return id
    }
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        self.url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
