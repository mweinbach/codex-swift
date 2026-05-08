import CodexCore
import Foundation
import XCTest

final class NonInteractiveExecTests: XCTestCase {
    func testMakePromptBuildsEnvironmentAndUserInput() {
        let schema = JSONValue.object(["type": .string("object")])
        let prompt = NonInteractiveExec.makePrompt(
            prompt: "ship it",
            imagePaths: ["/tmp/screenshot.png"],
            outputSchema: schema,
            cwd: URL(fileURLWithPath: "/tmp/project", isDirectory: true),
            approvalPolicy: .never,
            sandboxPolicy: .readOnly,
            shell: Shell(shellType: .zsh, shellPath: "/bin/zsh")
        )

        XCTAssertEqual(prompt.tools, [])
        XCTAssertEqual(prompt.outputSchema, schema)
        XCTAssertEqual(prompt.input.count, 2)

        guard case let .message(_, role, content) = prompt.input[1] else {
            return XCTFail("expected user message")
        }
        XCTAssertEqual(role, "user")
        XCTAssertEqual(content.count, 2)
        guard case let .inputText(text) = content[1] else {
            return XCTFail("expected prompt text")
        }
        XCTAssertEqual(text, "ship it")
    }

    func testHumanOutputReturnsFinalAssistantMessageAndWritesLastMessage() throws {
        let id = try ConversationId(string: "018f7a2d-4c5b-7abc-8def-0123456789ab")
        let writes = WriteSink()

        let result = NonInteractiveExec.finish(
            responseEvents: [
                .success(.outputTextDelta("do")),
                .success(.outputTextDelta("ne")),
                .success(.completed(responseID: "resp_1", tokenUsage: TokenUsage(totalTokens: 12)))
            ],
            outputMode: .human,
            conversationID: id,
            lastMessageFile: "/tmp/last.txt",
            writeFile: { path, contents in
                writes.write(path: path, contents: contents)
            }
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdoutMessage, "done")
        XCTAssertEqual(result.stderrMessages, [])
        XCTAssertEqual(result.lastAgentMessage, "done")
        XCTAssertEqual(writes.contents(at: "/tmp/last.txt"), "done")
    }

    func testJSONLinesOutputUsesExecEventEnvelope() throws {
        let id = try ConversationId(string: "018f7a2d-4c5b-7abc-8def-0123456789ab")
        let result = NonInteractiveExec.finish(
            responseEvents: [
                .success(.outputItemDone(.message(role: "assistant", content: [.outputText(text: "done")]))),
                .success(.completed(
                    responseID: "resp_1",
                    tokenUsage: TokenUsage(
                        inputTokens: 3,
                        cachedInputTokens: 1,
                        outputTokens: 5,
                        reasoningOutputTokens: 2,
                        totalTokens: 8
                    )
                ))
            ],
            outputMode: .jsonLines,
            conversationID: id,
            lastMessageFile: nil
        )

        XCTAssertEqual(result.exitCode, 0)
        let lines = try XCTUnwrap(result.stdoutMessage?.split(separator: "\n").map(String.init))
        XCTAssertEqual(lines.count, 4)
        let objects = try lines.map(jsonObject)
        XCTAssertEqual(objects[0]["type"], .string("thread.started"))
        XCTAssertEqual(objects[0]["thread_id"], .string(id.description))
        XCTAssertEqual(objects[1]["type"], .string("turn.started"))
        XCTAssertEqual(objects[2]["type"], .string("item.completed"))
        XCTAssertEqual(objects[3]["type"], .string("turn.completed"))
        guard case let .object(item)? = objects[2]["item"] else {
            return XCTFail("expected completed item")
        }
        XCTAssertEqual(item["type"], .string("agent_message"))
        XCTAssertEqual(item["text"], .string("done"))
        guard case let .object(usage)? = objects[3]["usage"] else {
            return XCTFail("expected usage")
        }
        XCTAssertEqual(usage["input_tokens"], .integer(3))
        XCTAssertEqual(usage["cached_input_tokens"], .integer(1))
        XCTAssertEqual(usage["output_tokens"], .integer(5))
        XCTAssertEqual(usage["reasoning_output_tokens"], .integer(2))
        XCTAssertEqual(usage["total_tokens"], .integer(8))
    }

    func testFailureOutputReturnsExitOneAndWritesEmptyLastMessage() throws {
        let id = try ConversationId(string: "018f7a2d-4c5b-7abc-8def-0123456789ab")
        let writes = WriteSink()

        let result = NonInteractiveExec.finish(
            responseEvents: [.failure(.quotaExceeded)],
            outputMode: .human,
            conversationID: id,
            lastMessageFile: "/tmp/last.txt",
            writeFile: { path, contents in
                writes.write(path: path, contents: contents)
            }
        )

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertNil(result.stdoutMessage)
        XCTAssertEqual(result.stderrMessages.first, "quota exceeded")
        XCTAssertEqual(writes.contents(at: "/tmp/last.txt"), "")
        XCTAssertEqual(result.stderrMessages.last, "Warning: no last agent message; wrote empty content to /tmp/last.txt")
    }

    private func jsonObject(_ line: String) throws -> [String: JSONValue] {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))
        guard case let .object(object) = value else {
            throw XCTSkip("expected object")
        }
        return object
    }
}

private final class WriteSink: @unchecked Sendable {
    private let lock = NSLock()
    private var writes: [String: String] = [:]

    func write(path: String, contents: String) {
        lock.withLock {
            writes[path] = contents
        }
    }

    func contents(at path: String) -> String? {
        lock.withLock {
            writes[path]
        }
    }
}
