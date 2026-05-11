@testable import CodexMCPServer
import CodexCore
import Foundation
import XCTest

final class MemoriesMCPServerTests: XCTestCase {
    func testInitializeAndListMemoryTools() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        var state = MemoriesMCPServerState()

        let initialize = try response(
            for: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#,
            state: &state,
            root: temp.url
        )

        let result = try XCTUnwrap(initialize["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-06-18")
        XCTAssertEqual(result["instructions"] as? String, "Use these tools to list, read, and search Codex memory files.")
        let capabilities = try XCTUnwrap(result["capabilities"] as? [String: Any])
        let toolsCapability = try XCTUnwrap(capabilities["tools"] as? [String: Any])
        XCTAssertEqual(toolsCapability["listChanged"] as? Bool, true)

        let toolsResponse = try response(
            for: #"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#,
            state: &state,
            root: temp.url
        )
        let toolsResult = try XCTUnwrap(toolsResponse["result"] as? [String: Any])
        let tools = try XCTUnwrap(toolsResult["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.compactMap { $0["name"] as? String }, ["list", "read", "search"])

        let listTool = tools[0]
        XCTAssertEqual(
            listTool["description"] as? String,
            "List immediate files and directories under a path in the Codex memories store."
        )
        let annotations = try XCTUnwrap(listTool["annotations"] as? [String: Any])
        XCTAssertEqual(annotations["readOnlyHint"] as? Bool, true)
        let inputSchema = try XCTUnwrap(listTool["inputSchema"] as? [String: Any])
        XCTAssertEqual(inputSchema["additionalProperties"] as? Bool, false)
        XCTAssertNotNil(listTool["outputSchema"] as? [String: Any])
    }

    func testListReadAndSearchToolCallsReturnStructuredContent() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        try FileManager.default.createDirectory(at: temp.url.appendingPathComponent("notes", isDirectory: true), withIntermediateDirectories: true)
        try "alpha\nbeta needle\n".write(to: temp.url.appendingPathComponent("notes/one.md"), atomically: true, encoding: .utf8)
        var state = MemoriesMCPServerState()

        let list = try response(
            for: #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list","arguments":{"path":"notes","max_results":1}}}"#,
            state: &state,
            root: temp.url
        )
        let listContent = try structuredContent(from: list)
        XCTAssertEqual(listContent["path"] as? String, "notes")
        XCTAssertTrue(listContent["next_cursor"] is NSNull)
        let entries = try XCTUnwrap(listContent["entries"] as? [[String: Any]])
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0]["path"] as? String, "notes/one.md")
        XCTAssertEqual(entries[0]["entry_type"] as? String, "file")
        XCTAssertEqual(listContent["truncated"] as? Bool, false)

        let read = try response(
            for: #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"read","arguments":{"path":"notes/one.md","line_offset":2,"max_lines":1}}}"#,
            state: &state,
            root: temp.url
        )
        let readContent = try structuredContent(from: read)
        XCTAssertEqual(readContent["path"] as? String, "notes/one.md")
        XCTAssertEqual(readContent["start_line_number"] as? Int, 2)
        XCTAssertEqual(readContent["content"] as? String, "beta needle\n")

        let search = try response(
            for: #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"search","arguments":{"queries":["beta","needle"],"match_mode":{"type":"all_on_same_line"},"path":"notes","case_sensitive":false}}}"#,
            state: &state,
            root: temp.url
        )
        let searchContent = try structuredContent(from: search)
        XCTAssertEqual(searchContent["path"] as? String, "notes")
        XCTAssertTrue(searchContent["next_cursor"] is NSNull)
        let matches = try XCTUnwrap(searchContent["matches"] as? [[String: Any]])
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0]["path"] as? String, "notes/one.md")
        XCTAssertEqual(matches[0]["match_line_number"] as? Int, 2)
        XCTAssertEqual(matches[0]["matched_queries"] as? [String], ["beta", "needle"])
    }

    func testToolCallRejectsUnknownArgumentsAndMapsBackendErrors() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        var state = MemoriesMCPServerState()

        let legacyQuery = try response(
            for: #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"search","arguments":{"query":"needle"}}}"#,
            state: &state,
            root: temp.url
        )
        let legacyError = try error(from: legacyQuery)
        XCTAssertEqual(legacyError.code, -32602)
        XCTAssertEqual(legacyError.message, "unknown field `query`")

        let zeroWindow = try response(
            for: #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"search","arguments":{"queries":["needle"],"match_mode":{"type":"all_within_lines","line_count":0}}}}"#,
            state: &state,
            root: temp.url
        )
        let windowError = try error(from: zeroWindow)
        XCTAssertEqual(windowError.code, -32602)
        XCTAssertEqual(windowError.message, "all_within_lines.line_count must be a positive integer")

        let missingFile = try response(
            for: #"{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"read","arguments":{"path":"missing.md"}}}"#,
            state: &state,
            root: temp.url
        )
        let backendError = try error(from: missingFile)
        XCTAssertEqual(backendError.code, -32602)
        XCTAssertEqual(backendError.message, "path 'missing.md' was not found")
    }

    private func response(
        for line: String,
        state: inout MemoriesMCPServerState,
        root: URL
    ) throws -> [String: Any] {
        let output = MemoriesMCPServer.processLine(
            Data(line.utf8),
            state: &state,
            backend: LocalMemoriesBackend(memoryRoot: root)
        )
        XCTAssertEqual(output.count, 1)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: output[0]) as? [String: Any])
    }

    private func structuredContent(from response: [String: Any]) throws -> [String: Any] {
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, false)
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        let text = try XCTUnwrap(content.first?["text"] as? String)
        let structuredContent = try XCTUnwrap(result["structuredContent"] as? [String: Any])
        let textObject = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        XCTAssertEqual(textObject as NSDictionary, structuredContent as NSDictionary)
        return structuredContent
    }

    private func error(from response: [String: Any]) throws -> (code: Int, message: String) {
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        return (
            try XCTUnwrap(error["code"] as? Int),
            try XCTUnwrap(error["message"] as? String)
        )
    }
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-swift-memories-mcp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
