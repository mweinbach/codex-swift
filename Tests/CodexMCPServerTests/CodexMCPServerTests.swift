@testable import CodexMCPServer
import Foundation
import XCTest

final class CodexMCPServerTests: XCTestCase {
    func testInitializePingAndListToolsResponses() async throws {
        var state = CodexMCPServerState()

        let initialize = try await response(
            for: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","clientInfo":{"name":"test","version":"0"}}}"#,
            state: &state
        )
        XCTAssertEqual(initialize["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(initialize["id"] as? Int, 1)
        let initializeResult = try XCTUnwrap(initialize["result"] as? [String: Any])
        XCTAssertEqual(initializeResult["protocolVersion"] as? String, "2025-06-18")
        let serverInfo = try XCTUnwrap(initializeResult["serverInfo"] as? [String: Any])
        XCTAssertEqual(serverInfo["name"] as? String, "codex-mcp-server")
        let capabilities = try XCTUnwrap(initializeResult["capabilities"] as? [String: Any])
        let toolsCapability = try XCTUnwrap(capabilities["tools"] as? [String: Any])
        XCTAssertEqual(toolsCapability["listChanged"] as? Bool, true)

        let ping = try await response(for: #"{"jsonrpc":"2.0","id":"p","method":"ping","params":{}}"#, state: &state)
        XCTAssertEqual(ping["id"] as? String, "p")
        XCTAssertNotNil(ping["result"] as? [String: Any])

        let tools = try await response(for: #"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#, state: &state)
        let toolsResult = try XCTUnwrap(tools["result"] as? [String: Any])
        let toolRows = try XCTUnwrap(toolsResult["tools"] as? [[String: Any]])
        XCTAssertEqual(toolRows.compactMap { $0["name"] as? String }, ["codex", "codex-reply"])
        let codexTool = toolRows[0]
        XCTAssertEqual(codexTool["title"] as? String, "Codex")
        let inputSchema = try XCTUnwrap(codexTool["inputSchema"] as? [String: Any])
        XCTAssertEqual(inputSchema["required"] as? [String], ["prompt"])
    }

    func testCodexToolCallDecodesArgumentsAndReturnsTextContent() async throws {
        var state = CodexMCPServerState()
        let receivedCall = CallCapture()

        let message = """
        {"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"codex","arguments":{"prompt":"ship it","model":"gpt-5","profile":"work","cwd":"/tmp/work","approval-policy":"never","sandbox":"workspace-write","config":{"model_reasoning_effort":"high"},"base-instructions":"base","developer-instructions":"dev","compact-prompt":"compact"}}}
        """
        let result = try await response(
            for: message,
            state: &state,
            codexToolRunner: { call in
                await receivedCall.set(call)
                return CodexMCPToolResult(text: "done")
            }
        )

        let capturedCall = await receivedCall.value
        XCTAssertEqual(capturedCall, CodexMCPToolCall(
            prompt: "ship it",
            model: "gpt-5",
            profile: "work",
            cwd: "/tmp/work",
            approvalPolicy: "never",
            sandbox: "workspace-write",
            config: ["model_reasoning_effort": .string("high")],
            baseInstructions: "base",
            developerInstructions: "dev",
            compactPrompt: "compact"
        ))
        let content = try textContent(from: result)
        XCTAssertEqual(content.text, "done")
        XCTAssertFalse(content.isError)
    }

    func testCodexToolCallReportsMissingPromptAsToolError() async throws {
        var state = CodexMCPServerState()

        let result = try await response(
            for: #"{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"codex","arguments":{"model":"gpt-5"}}}"#,
            state: &state,
            codexToolRunner: { _ in
                XCTFail("runner should not be called when prompt is missing")
                return CodexMCPToolResult(text: "unused")
            }
        )

        let content = try textContent(from: result)
        XCTAssertEqual(content.text, "Missing arguments for codex tool-call; the `prompt` field is required.")
        XCTAssertTrue(content.isError)
    }

    private func response(
        for line: String,
        state: inout CodexMCPServerState,
        codexToolRunner: @escaping CodexMCPServer.CodexToolRunner = { _ in CodexMCPToolResult(text: "") }
    ) async throws -> [String: Any] {
        let output = await CodexMCPServer.processLine(
            Data(line.utf8),
            state: &state,
            codexToolRunner: codexToolRunner
        )
        XCTAssertEqual(output.count, 1)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: output[0]) as? [String: Any])
    }

    private func textContent(from response: [String: Any]) throws -> (text: String, isError: Bool) {
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        let text = try XCTUnwrap(content.first?["text"] as? String)
        return (text, result["isError"] as? Bool ?? false)
    }
}

private actor CallCapture {
    var value: CodexMCPToolCall?

    func set(_ value: CodexMCPToolCall) {
        self.value = value
    }
}
